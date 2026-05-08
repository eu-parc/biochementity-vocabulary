#!/usr/bin/env python3
"""Group reviewed BioChemEntity YAML entries by BiomarkerList CompoundGroup."""

from __future__ import annotations

import csv
import sys
import re
from collections import defaultdict
from pathlib import Path

import yaml


BASE_DIR = Path(__file__).resolve().parent
CSV_PATH = BASE_DIR / "biomarkerlist-sheet.csv"
YAML_PATH = BASE_DIR / "BioChemEntity_vocabulary_review_sylvie.yaml"
GROUP_FILE_NAME = "biochementities.yaml"

NAME_COLUMNS = ("ParentCompound_name", "Biomarker_name")
SHORT_NAME_COLUMNS = ("Biomarker_abbreviation", "Biomarker_varname")
EXACT_MATCH_COLUMNS = {
    "CHEBI": "CHEBI_key",
    "INCHIKEY": "INCHI_key",
    "CAS": "CAS_numer",
}


def normalize_text(value: object) -> str:
    """Normalize text enough to catch case and punctuation variants."""
    if value is None:
        return ""
    text = str(value).casefold().strip()
    text = re.sub(r"[\u2010-\u2015\u2212]", "-", text)
    text = re.sub(r"\s+", " ", text)
    return text


def compact_text(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", normalize_text(value))


def normalize_exact(prefix: str, value: object) -> str:
    text = str(value or "").strip().upper()
    if not text:
        return ""
    if prefix == "CHEBI":
        text = text.removeprefix("CHEBI:")
        return f"CHEBI:{text}"
    return text.removeprefix(f"{prefix}:")


def folder_name(group: str, used: set[str]) -> str:
    safe = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", group).strip()
    safe = re.sub(r"\s+", " ", safe) or "Ungrouped"
    candidate = safe
    index = 2
    while candidate in used:
        candidate = f"{safe} ({index})"
        index += 1
    used.add(candidate)
    return candidate


def split_compoundgroups(value: object) -> list[str]:
    return [group.strip() for group in str(value or "").split(";") if group.strip()]


def load_csv_rows(path: Path) -> list[dict[str, str]]:
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;")
    except csv.Error:
        dialect = csv.excel
    return list(csv.DictReader(text.splitlines(), dialect=dialect))


def split_entry_blocks(yaml_text: str) -> list[str]:
    lines = yaml_text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith("- ")]
    blocks: list[str] = []
    for position, start in enumerate(starts):
        end = starts[position + 1] if position + 1 < len(starts) else len(lines)
        blocks.append("".join(lines[start:end]))
    return blocks


def without_compoundgroups_field(block: str) -> str:
    lines = block.splitlines(keepends=True)
    filtered: list[str] = []
    skip = False
    for line in lines:
        if line.startswith("  compoundgroups:"):
            skip = True
            continue
        if skip and re.match(r"^  [A-Za-z0-9_]+:", line):
            skip = False
        if not skip:
            filtered.append(line)
    return "".join(filtered)


def quote_yaml_scalar(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def add_compoundgroups_field(block: str, groups: set[str]) -> str:
    block = without_compoundgroups_field(block)
    lines = block.splitlines(keepends=True)
    group_lines = ["  compoundgroups:\n"]
    if groups:
        group_lines.extend(f"  - {quote_yaml_scalar(group)}\n" for group in sorted(groups))
    else:
        group_lines = ["  compoundgroups: []\n"]

    insert_after = None
    for preferred in ("  short_name:", "  name:", "- id:"):
        for index, line in enumerate(lines):
            if line.startswith(preferred):
                insert_after = index + 1
                break
        if insert_after is not None:
            break

    if insert_after is None:
        return "".join([*group_lines, *lines])
    return "".join([*lines[:insert_after], *group_lines, *lines[insert_after:]])


def parse_exact_matches(entry: dict) -> list[tuple[str, str]]:
    matches: list[tuple[str, str]] = []
    for item in entry.get("exact_matches") or []:
        for part in str(item).split("|"):
            if ":" not in part:
                continue
            prefix, value = part.split(":", 1)
            prefix = prefix.strip().upper()
            if prefix in EXACT_MATCH_COLUMNS:
                normalized = normalize_exact(prefix, value)
                if normalized:
                    matches.append((prefix, normalized))
    return matches


def build_indexes(rows: list[dict[str, str]]) -> tuple[dict[str, set[str]], dict[str, set[str]]]:
    text_index: dict[str, set[str]] = defaultdict(set)
    exact_index: dict[str, set[str]] = defaultdict(set)

    for row in rows:
        groups = set(split_compoundgroups(row.get("CompoundGroup")))
        if not groups:
            continue
        for column in (*NAME_COLUMNS, *SHORT_NAME_COLUMNS):
            value = row.get(column)
            for key in (normalize_text(value), compact_text(value)):
                if key:
                    text_index[key].update(groups)

        for prefix, column in EXACT_MATCH_COLUMNS.items():
            key = normalize_exact(prefix, row.get(column))
            if key:
                exact_index[f"{prefix}:{key}"].update(groups)

    return text_index, exact_index


def groups_for_entry(
    entry: dict,
    text_index: dict[str, set[str]],
    exact_index: dict[str, set[str]],
) -> set[str]:
    groups: set[str] = set()

    text_values = [
        entry.get("name"),
        entry.get("short_name"),
        entry.get("varname"),
        *(entry.get("aliases") or []),
    ]
    for value in text_values:
        for key in (normalize_text(value), compact_text(value)):
            groups.update(text_index.get(key, set()))

    for prefix, value in parse_exact_matches(entry):
        groups.update(exact_index.get(f"{prefix}:{value}", set()))

    return groups


def write_yaml(path: Path, blocks: list[str]) -> None:
    if blocks:
        body = "".join(block if block.endswith("\n") else f"{block}\n" for block in blocks)
        path.write_text(f"biochementities:\n{body}", encoding="utf-8")
    else:
        path.write_text("biochementities: []\n", encoding="utf-8")


def clean_previous_outputs(group_dirs: dict[str, Path]) -> None:
    needed_dirs = set(group_dirs.values())
    for path in BASE_DIR.iterdir():
        if not path.is_dir():
            continue
        output_file = path / GROUP_FILE_NAME
        if output_file.exists():
            output_file.unlink()
        if path not in needed_dirs:
            try:
                path.rmdir()
            except OSError:
                pass


def main() -> None:
    rows = load_csv_rows(CSV_PATH)

    yaml_text = YAML_PATH.read_text(encoding="utf-8")
    parsed = yaml.safe_load(yaml_text)
    entries = parsed["biochementities"]
    blocks = split_entry_blocks(yaml_text)
    if len(entries) != len(blocks):
        raise RuntimeError(f"Parsed {len(entries)} entries but found {len(blocks)} YAML blocks")

    groups = sorted({group for row in rows for group in split_compoundgroups(row.get("CompoundGroup"))})
    used_folder_names: set[str] = set()
    group_dirs = {group: BASE_DIR / folder_name(group, used_folder_names) for group in groups}
    clean_previous_outputs(group_dirs)
    for directory in group_dirs.values():
        directory.mkdir(parents=True, exist_ok=True)

    text_index, exact_index = build_indexes(rows)
    grouped_blocks: dict[str, list[str]] = {group: [] for group in groups}
    remaining_blocks: list[str] = []

    for entry, block in zip(entries, blocks):
        matched_groups = groups_for_entry(entry, text_index, exact_index)
        block = add_compoundgroups_field(block, matched_groups)
        if matched_groups:
            for group in sorted(matched_groups):
                grouped_blocks[group].append(block)
        else:
            remaining_blocks.append(block)

    for group, directory in group_dirs.items():
        write_yaml(directory / GROUP_FILE_NAME, grouped_blocks[group])
    write_yaml(BASE_DIR / "remaining.yaml", remaining_blocks)

    assigned_unique = len(entries) - len(remaining_blocks)
    assigned_total = sum(len(items) for items in grouped_blocks.values())
    print(f"CSV rows: {len(rows)}")
    print(f"CompoundGroup folders: {len(groups)}")
    print(f"YAML entries: {len(entries)}")
    print(f"Matched unique entries: {assigned_unique}")
    print(f"Remaining entries: {len(remaining_blocks)}")
    print(f"Total group assignments: {assigned_total}")


if __name__ == "__main__":
    main()
