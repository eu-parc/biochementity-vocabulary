## Biochementity Vocabulary Dropbox to Nanopublication Template

This repository implements a staged vocabulary workflow for biochementities:

## Proposing a new biochementity

1. All new biochementity info can be added to one or more `*.yaml` files following this structure. This is a minimal example for such a `*.yaml`. The full contract is the json-schema in [schema/dropbox-biochementity.schema.json](schema/dropbox-biochementity.schema.json), with a worked example in [schema/dropbox-biochementity.example.yaml](schema/dropbox-biochementity.example.yaml).

```yaml
# Optional file-level default suggester (ORCID); applied to entries without their own.
suggester: https://orcid.org/0000-0002-1825-0097
biochementity_subclasses:
- id: environmentalbiochementity
  name: "environmental biochementity"
  description: All abiotic environmental compartments in which chemicals can be measured
  parent_biochementities:
    - https://w3id.org/peh/terms/BioChemEntity
  group_labels:
    - 'pesticides'
- id: bioticbiochementity
  name: "biotic biochementity"
  description: All biological organisms and their tissues
  parent_biochementities:
    - https://w3id.org/peh/terms/BioChemEntity
```
Note that the identifier field does not need to be provided; identifiers are minted on the fly.

The optional `suggester` field (an ORCID) records who proposed the term; it becomes the `prov:wasAttributedTo` provenance of the resulting nanopublication. Set it once at the top of the file as a default, or per entry to override.

### Field reference

Each entry under `biochementity_subclasses` describes one biochementity. Only `name` is required. Fields that take a list are written as YAML lists, even for one value. The full contract is the JSON schema in [schema/dropbox-biochementity.schema.json](schema/dropbox-biochementity.schema.json); the RDF property each field becomes is given in brackets.

| Field | Required | Description | Format and example |
| --- | --- | --- | --- |
| `id` | No | Identifier of the term. Leave it out for a new term: one is minted. Give it only for an existing term, to change it. | The term's URI, e.g. `https://w3id.org/peh/biochementities/RA…`, or its legacy ID. |
| `name` | Yes | Preferred name, in English (`rdfs:label`). | Text, e.g. `Formaldehyde` |
| `translations` | No | The name or an alternative name in another language. | List of items with `property_name` (`name` for the name, `short_name` for an alternative name), `language` (a language tag such as `nl-be`) and `translated_value`. See the example below. |
| `aliases` | No | Other names: synonyms, abbreviations, codes (`schema:alternateName`). | List of text, e.g. `[methanal, HCHO]` |
| `short_name` | No | A short name or code. It is stored like an alias (`schema:alternateName`). | Text |
| `ui_label` | No | Label for forms and documents, if it should differ from `name` (`pehterms:hasUiLabel`). | Text |
| `description` | No | Definition or description (`schema:description`). | Text |
| `remark` | No | Comment, e.g. on sources or open questions (`schema:comment`). | Text |
| `parent_biochementities` | No | The biochementities this one is a kind of; for example, 2-methylfuran is a furan (`rdfs:subClassOf`). Always include `https://w3id.org/peh/terms/BioChemEntity`. | List of URIs |
| `group_labels` | No | Groups for browsing and selection (`pehterms:hasGroupLabel`). Reuse existing labels where possible; see `published-yaml/`. | List of text, e.g. `[pesticides]`, `[PFAS]` |
| `grouping_id_list` | No | Groupings this term belongs to (`skos:broader`). | List of URIs |
| `exact_matches` | No | The same chemical in external databases (`skos:exactMatch`). | List of identifiers.org URIs: `https://identifiers.org/cas:50-00-0`, `https://identifiers.org/inchikey:WSFSSNUMVMOOMR-UHFFFAOYSA-N`, `https://identifiers.org/pubchem.compound:712`, `https://identifiers.org/CHEBI:16842` |
| `has_role` | No | Chemical roles from ChEBI (`RO_0000087`, "has role"). | List of ChEBI URIs, e.g. `https://purl.obolibrary.org/obo/CHEBI_25944` (pesticide) |
| `is_metabolite_of` | No | The biochementities this one is a metabolite of (`pehterms:isMetaboliteOf`). | List of biochementity URIs |
| `is_isomer_of` | No | The biochementities this one is an isomer of (`pehterms:isIsomerOf`; it applies in both directions). | List of biochementity URIs |
| `molweight_grampermol` | No | Molecular weight in g/mol (`pehterms:hasMolecularWeight`). | Number, e.g. `30.03` |
| `context_aliases` | No | A name used by a particular institute or project (`pehterms:hasContextAlias`). | List of items with `property_name`, `context` (an institute or project identifier, such as a ROR URL) and `alias`. See the example below. |
| `suggester` | No | Who proposed the term (`prov:wasAttributedTo`). Overrides the file-level `suggester`. | ORCID URL, e.g. `https://orcid.org/0000-0002-1825-0097` |

Use `translations` for the name or an alternative name in another language:

```yaml
translations:
  - property_name: name
    language: nl-be
    translated_value: formaldehyde
  - property_name: short_name
    language: nl-be
    translated_value: methanal
```

Use `context_aliases` when a particular institute or project uses a local alias for a property value:

```yaml
context_aliases:
  - property_name: short_name
    context: https://ror.org/04gq0w522
    alias: omc
```

In this example, `omc` is an alias for the `short_name` value in the context of the institute identified by `https://ror.org/04gq0w522`.

2. Open a PR with these `*.yaml` files added to the dropbox.

## Under the hood

1. New YAML vocab files are dropped into `dropbox/`.
2. Processing converts them into transient RDF assertions under `build/`.
3. The minted combined YAML file is copied to `archive/` with a ULID suffix to avoid overwriting earlier submissions, and processed source YAML files are removed from `dropbox/`.
4. Publishing creates nanopublications from the transient assertions.
5. Publishing also writes a timestamped term-to-nanopub redirect mapping into `redirect/`.
6. Successfully published nanopublications are written to `published/`.

## Folder Semantics

- `dropbox/`: incoming YAML vocabulary files
- `archive/`: processed combined YAML files with minted identifiers and ULID-labeled filenames
- `redirect/`: timestamped term identifier to nanopub identifier mappings produced during publishing
- `published/`: assertions already published as nanopublications
- `build/`: transient build artifacts

## Local Usage

Install dependencies:

```bash
uv sync
```

Download a tagged `peh.yaml` snapshot into `schema/`:

```bash
make fetch-peh-schema
```

Override the upstream tag when you want a different schema release:

```bash
make fetch-peh-schema PEH_SCHEMA_TAG=v0.4.0
```

Process incoming YAML from `dropbox/`:

```bash
make pipeline
```

Dry-run publish (no move to `published/`):

```bash
make publish-pipeline DRY=--dry-run
```

Real publish (requires nanopub credentials in environment):

```bash
export NANOPUB_PRIVATE_KEY=...
export NANOPUB_PUBLIC_KEY=...
export INTRO_NANOPUB_URI=...
make publish-pipeline
```

Each publish run writes a uniquely named redirect mapping file such as
`redirect/term-to-nanopub_20260424T120102Z.tsv`.

End-to-end local smoke test:

```bash
make test-flow
```

## GitHub Workflows

- `publish.yaml`: validates proposals and publishes nanopublications on:
  - pull requests with `dropbox/**` changes (test publish),
  - pushes to `main` with `dropbox/**` changes (production),
  - manual `workflow_dispatch` runs (`dry-run`, `test-publish`, or `production`).
- `consistency-check.yaml` (weekly, and on demand): checks the vocabulary as
  Nanodash shows it and as `published/` holds it. It fails on duplicate labels
  and on links to terms that are not current (withdrawn or not approved), and
  warns when `published/` is out of date, on links to deprecated terms and on
  terms that share an InChIKey or CAS number. Run it locally with
  `make check-consistency`.

In production mode, processed source YAML files are archived, published nanopublications are committed under `published/`, and the redirect mapping is committed from `redirect/`.
