## Biochementity Vocabulary Dropbox to Nanopublication Template

This repository implements a staged vocabulary workflow for matrices:

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
Note that the identifier field does not need to be provided, identifiers are minted on the fly.

The optional `suggester` field (an ORCID) records who proposed the term; it becomes the `prov:wasAttributedTo` provenance of the resulting nanopublication. Set it once at the top of the file as a default, or per entry to override.

2. Open a PR with these *.yaml files added to the dropbox

## Under the hood

1. New YAML vocab files are dropped into `dropbox/`.
2. Processing converts them into RDF assertions in `unpublished/`.
3. The minted combined YAML file is copied to `archive/` with a ULID suffix to avoid overwriting earlier submissions, and processed source YAML files are removed from `dropbox/`.
4. Publishing creates nanopublications from `unpublished/`.
5. Publishing also writes a timestamped term-to-nanopub redirect mapping into `redirect/`.
6. Successfully published assertion files move to `published/`.

## Folder Semantics

- `dropbox/`: incoming YAML vocabulary files
- `archive/`: processed combined YAML files with minted identifiers and ULID-labeled filenames
- `unpublished/`: generated RDF term assertions waiting for publish
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

- `serialize.yaml`: on push to `main` with `dropbox/**` changes, runs `make pipeline` and commits `archive/` + `unpublished/` updates.
- `test-serialize.yaml`: on PR with `dropbox/**` changes, validates processing behavior.
- `publish.yaml`: publishes nanopublications on:
  - release publish (real publish),
  - tag push (dry-run),
  - manual `workflow_dispatch` ("Publish mode" input: `dry-run` or `publish`).

In manual real publish mode (`workflow_dispatch` with `publish`), published assertion files are moved from `unpublished/` to `published/`, the new redirect mapping file is committed from `redirect/`, and both changes are pushed.
