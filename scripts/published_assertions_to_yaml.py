#!/usr/bin/env python3
"""Build a schema-shaped YAML dump from published nanopub assertions."""

from __future__ import annotations

import argparse
import sys
from decimal import Decimal
from pathlib import Path
from typing import Any

import yaml
from rdflib import Graph, Literal, Namespace, RDF, URIRef


OBO = Namespace("http://purl.obolibrary.org/obo/")
OWL = Namespace("http://www.w3.org/2002/07/owl#")
PEHTERMS = Namespace("https://w3id.org/peh/terms/")
PROV = Namespace("http://www.w3.org/ns/prov#")
RDFS = Namespace("http://www.w3.org/2000/01/rdf-schema#")
SCHEMA = Namespace("http://schema.org/")
SKOS = Namespace("http://www.w3.org/2004/02/skos/core#")


PREDICATE_SLOTS = {
    RDFS.subClassOf: "parent_biochementities",
    SCHEMA.comment: "remark",
    SCHEMA.description: "description",
    SCHEMA.alternateName: "aliases",
    SKOS.exactMatch: "exact_matches",
    PEHTERMS.hasGroupLabel: "group_labels",
    PEHTERMS.hasMolecularWeight: "molweight_grampermol",
    PEHTERMS.isMetaboliteOf: "is_metabolite_of",
    PEHTERMS.isIsomerOf: "is_isomer_of",
    OBO.RO_0000087: "has_role",
    PROV.wasAttributedTo: "suggester",
}

# Language-tagged values of these predicates are exported as translations, under
# the property names that pubmate-cleanrdf turns back into language-tagged
# literals, so that a re-submitted entry comes out unchanged.
TRANSLATED_PREDICATES = {
    RDFS.label: "name",
    SCHEMA.alternateName: "short_name",
}

LIST_SLOTS = {
    "aliases",
    "exact_matches",
    "group_labels",
    "has_role",
    "is_isomer_of",
    "is_metabolite_of",
    "parent_biochementities",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assertion-folder", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def scalar(value: Any) -> Any:
    if isinstance(value, URIRef):
        return str(value)
    if isinstance(value, Literal):
        py_value = value.toPython()
        if isinstance(py_value, Decimal):
            return float(py_value)
        return py_value
    return str(value)


def warn(subject: Any, message: str) -> None:
    print(f"WARNING {subject}: {message}", file=sys.stderr)


def append(record: dict[str, Any], slot: str, value: Any) -> None:
    if slot in LIST_SLOTS:
        record.setdefault(slot, [])
        if value not in record[slot]:
            record[slot].append(value)
    elif slot not in record:
        record[slot] = value
    elif record[slot] != value:
        warn(record["id"], f"{slot} has more than one value; exported only {record[slot]!r}, not {value!r}")


def translations(graph: Graph, subject: Any) -> list[dict[str, str]]:
    items = [
        {"property_name": name, "language": value.language, "translated_value": str(value)}
        for predicate, name in TRANSLATED_PREDICATES.items()
        for value in graph.objects(subject, predicate)
        if isinstance(value, Literal) and value.language
    ]
    return sorted(
        items,
        key=lambda t: (t["property_name"] != "name", t["property_name"], t["language"], t["translated_value"]),
    )


def context_alias(graph: Graph, node: Any) -> dict[str, Any]:
    item: dict[str, Any] = {}
    first_values = {
        "property_name": graph.objects(node, SCHEMA.identifier),
        "context": graph.objects(node, PEHTERMS.hasContext),
        "alias": graph.objects(node, SCHEMA.alternateName),
    }
    for slot, values in first_values.items():
        for value in values:
            item[slot] = scalar(value)
            break
    return item


def main() -> None:
    args = parse_args()
    graph = Graph()
    ttl_files = sorted(args.assertion_folder.glob("*.ttl"))
    if not ttl_files:
        raise SystemExit(f"No .ttl assertion files found in {args.assertion_folder}")

    for ttl_file in ttl_files:
        graph.parse(ttl_file, format="turtle")

    records: list[dict[str, Any]] = []
    for subject in sorted(graph.subjects(RDF.type, OWL.Class), key=str):
        record: dict[str, Any] = {"id": str(subject)}

        for label in sorted(graph.objects(subject, RDFS.label), key=str):
            if not (isinstance(label, Literal) and label.language):
                append(record, "name", str(label))
        if translated := translations(graph, subject):
            record["translations"] = translated

        for predicate, slot in PREDICATE_SLOTS.items():
            for value in graph.objects(subject, predicate):
                if isinstance(value, Literal) and value.language:
                    if predicate not in TRANSLATED_PREDICATES:
                        warn(subject, f"{slot} {value!r}: exported without its language tag")
                    else:
                        continue
                append(record, slot, scalar(value))

        for node in graph.objects(subject, PEHTERMS.hasContextAlias):
            item = context_alias(graph, node)
            if item:
                record.setdefault("context_aliases", []).append(item)

        for slot in LIST_SLOTS:
            if slot in record:
                record[slot] = sorted(record[slot], key=str)
        records.append(record)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as stream:
        yaml.safe_dump(
            {"biochementity_subclasses": records},
            stream,
            allow_unicode=True,
            sort_keys=False,
        )


if __name__ == "__main__":
    main()
