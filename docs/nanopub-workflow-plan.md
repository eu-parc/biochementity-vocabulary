# Biochementity Vocabulary — Nanopublication Workflow Plan

> Status: **planning only — nothing implemented yet.** This document records the
> agreed direction so work can proceed as small, reviewable pull requests.
> Last updated: 2026-06-19.

## 1. Background & goal

Today the repo treats nanopublications as a *publish-time* concern: `dropbox/*.yaml`
is turned into bare RDF assertions (`unpublished/*.ttl`), and only at publish time does
`pubmate-publish` wrap each assertion into a nanopublication, sign, and push it.

We want nanopublications to be the **central artifact** and to make the identifiers
themselves nanopub-based (trusty artifact codes), while keeping a low-friction
"drop a YAML file, open a PR" contribution path. The work is split across two repos and
delivered as incremental PRs to both:

- **`eu-parc/biochementity-vocabulary`** (this repo): the vocabulary-specific glue —
  dropbox YAML contract, folder layout, CI/Make wiring, site build, migration data.
- **`eu-parc/pubmate`**: the reusable library logic — building/signing/publishing
  nanopubs, sequential minting, id mapping.

## 2. Decisions from the 17 June 2026 project call

These are authoritative.

- **Folders:** drop the `unpublished/` vs `published/` distinction. Keep a single
  **`published/`** folder containing all nanopubs. (Nightly sync of *all* biochementity
  nanopubs — including ones created via Nanodash — into `published/` is desired but
  **low priority**.)
- **Identifiers:** transition **fully to nanopub-based identifiers** (trusty artifact
  codes). Provide a **map** from the currently minted "unpublished" identifiers to the
  new nanopub-based ones. Minting should be **sequential** so an entry can point to
  already-existing identifiers. Cycles are **not normal**; when needed they are handled
  by **updating (superseding) after minting**.
- **Toolchain:** use **nanopub-py** (the Python `nanopub` library), **not** the Java jar.
- **Incoming flows (dual):**
  - *GitHub/dropbox* (first, primary): `prov:wasAttributedTo` the **suggester**; signed
    with a **repo-local bot keypair**; published by the **bot** via a GitHub Action.
  - *Nanodash* (later): community members sign with **their own** Nanodash keypairs.
- **Suggester field:** the dropbox YAML template will get a **new field** to carry the
  suggester (so provenance can attribute to them).
- **Key storage:** the bot signing key lives in a **GitHub secret**.
- **Scope of vocabulary:** only **classes / a class hierarchy**. Top class
  `https://w3id.org/peh/terms/BioChemEntity`; sub- and sub-sub-classes, possibly with
  **multiple superclasses**.
- **Roles / governance** (via the Nanodash space `https://w3id.org/spaces/biochementity`):
  space admins; "maintainer" (Gertjan + a few); self-assigned observer/follower.
- **Versioning:** semantic versioning.
- **Batch approval:** possibly represent batches as **nanopub indexes** that can be
  approved. *(Open, later.)*
- **Integrate with pubmate:** the reusable logic belongs in `pubmate`.
- **Process:** ship as **small incremental PRs** to both repos.

## 3. Verified technical findings

1. **Unsigned nanopubs can be built without keys.** `nanopub.Nanopub(conf, assertion=g)`
   produces a complete 4-graph nanopub with `http://purl.org/nanopub/temp/np/` URIs and
   no signing keys. (`Profile` accepts no keys; it generates ephemeral in-memory keys
   that are never written to disk.)
2. **The trusty artifact code is the placeholder `~~~ARTIFACTCODE~~~`** (confirmed in
   `net/trustyuri/rdf/RdfUtils`; `ARTIFACTCODE-PLACEHOLDER` is the deprecated fallback).
   A base URI containing it, matched as `~~~ARTIFACTCODE~~~[\.#/]?$`, has the placeholder
   replaced by the computed code at signing; URIs outside the nanopub's base scope are
   left as-is **except** the placeholder is still substituted in them.
3. **A custom-namespace thing URI works (verified with the Java jar).** Keeping the
   default temp URI for the nanopub *itself* and using
   `https://w3id.org/peh/biochementities/~~~ARTIFACTCODE~~~` as the introduced term's
   IRI yields, after signing:
   - nanopub URI `https://w3id.org/np/RA<code>` (default), and
   - thing URI `https://w3id.org/peh/biochementities/RA<code>` (same code, our namespace).
   This matches the requirement: **artifact code on the thing URI, not the nanopub URI.**
4. **The artifact code depends on the signing key** (same content, two keys → two
   different codes). Therefore the final identifier can only be computed by signing with
   the **real bot key**, i.e. at **publish time** — not in a keyless step. Pre-publish
   artifacts must use a temporary handle.
5. **Cycles exist in the real data:** among the 879 current assertions, internal
   references are `isMetaboliteOf` (267), `subClassOf`→biochementity (201),
   `isIsomerOf` (42, symmetric). DFS finds cycles (≥21 mutual `isIsomerOf` pairs). Since
   identifier = content hash, a cycle is unresolvable in a single pass — hence
   "mint first, add links by superseding afterwards."

6. **nanopub-py now supports custom-namespace artifact-code minting (scheme A) — DONE.**
   Originally it did not (its vendored `trustyuri` only rewrote URIs inside the dummy
   namespace; a placeholder in another namespace was passed through verbatim). This was
   fixed upstream in `nanopub/trustyuri/rdf/RdfUtils.py::get_trustyuri` (commit `a909047`,
   "Support `~~~ARTIFACTCODE~~~` placeholder in custom namespaces (#232)"; **not yet
   released** — the commit bumps the pyproject version toward 2.2.0):
   substitute `~~~ARTIFACTCODE~~~` → `hashstr` in any URI, and on verify blank this
   nanopub's own `RA…` code in out-of-namespace URIs, leaving other trusty URIs intact.
   Verified end-to-end against that commit (foreign-namespace thing URI, default nanopub
   URI): thing code == nanopub code, placeholder gone, other references preserved, valid
   trusty **and** signature.
7. **Scheme A is now pinned in the shared testsuite for the Java/Python implementations.**
   `nanopub-testsuite` gained a `transform/` case for the foreign-namespace
   `~~~ARTIFACTCODE~~~` placeholder (PR #4, merge `cfe9630`, 2026-06-17), verifying Java/Python
   parity. So implementations: **Java ✅, nanopub-py ✅ (commit `a909047`, unreleased)**.
   (nanopub-js still substitutes the placeholder only when it sits in the nanopub's own base
   URI — scheme B — not in a foreign concept namespace; generalizing it is out of scope here,
   relevant only to future Nanodash/JS consumers.)

> ✅ **Spike resolved & implemented (N0/N1).** The custom-namespace artifact-code thing URI
> works in nanopub-py as of commit `a909047` (unreleased). Until 2.2.0 is on PyPI, consume it by
> **git-pinning** nanopub to that commit (workspace-root `[tool.uv.sources]`); switch to
> `nanopub>=2.2.0` once released. This unblocks the pubmate builder (P1).

### nanopub-py capability audit — everything needed is present

Verified against commit `a909047` (unreleased). The full GitHub/dropbox flow can be built on
nanopub-py alone (no Java jar):

- Build an unsigned 4-graph nanopub from an assertion graph, keyless. ✅
- Mint the artifact code into the thing URI in our namespace while the nanopub URI stays the
  default `w3id.org/np` (scheme A), round-tripping to valid trusty + signature. ✅
- Sign with the bot key (`signedBy` = signer). ✅
- Attribute the assertion to the **suggester** (≠ signer) via
  `assertion_attributed_to=<orcid>` **with** `attribute_assertion_to_profile=False`
  (passing both raises `MalformedNanopubError`). ✅
- `prov:wasDerivedFrom` source via `derived_from=…`; pubinfo `rdfs:label` / `dct:license` /
  `npx:introduces` by adding triples. ✅
- Read the trusty URI/code after `sign()` (for sequential reference resolution). ✅
- Supersede to add cyclic/forward links in phase 2 — add an `npx:supersedes` triple to a
  plain `Nanopub` (offline-friendly); fixed thing URIs and cyclic refs are preserved. ✅
- Load an existing trig (`Nanopub(rdf=…)`) and re-sign; `NanopubClient` for test/live
  publishing. ✅

Operational notes:
- `NanopubUpdate(uri=…)` **fetches the superseded nanopub over the network** to check
  key-match — fine once phase-1 is published, but use the manual `npx:supersedes` triple for
  offline/local runs and tests.
- Sequential minting + reference rewriting is **our** orchestration (pubmate P2/P3);
  nanopub-py supplies the per-nanopub primitives above.

## 4. Target architecture

### Folders
- `dropbox/` — incoming YAML (unchanged contract + new suggester field).
- `archive/` — minted/combined YAML snapshots (kept for provenance/audit).
- `published/` — **all** nanopubs as signed `.trig` (single source of truth).
- `assertions/` — plain `.ttl` per term for the Pages site (regenerated from
  `published/`; `serves-me-right` only reads `.ttl`). *(Folder name TBD; could also be a
  build artifact rather than committed.)*
- `id-map/` (or `redirect/`) — old-minted-id → nanopub-id map + term→nanopub redirects.
- No committed `unpublished/`.

### Identifier model
- Canonical term IRI = `https://w3id.org/peh/biochementities/RA<artifactcode>`, where
  `<artifactcode>` is the artifact code of the term's **defining** nanopub.
- The nanopub's own URI stays the default `https://w3id.org/np/RA<artifactcode>`.
- Mechanism: defining nanopub built with the thing URI as
  `…/biochementities/~~~ARTIFACTCODE~~~` (requires the nanopub-py change N1; see §3 #6).
- **Sequential minting:** process terms in dependency order so references resolve to
  already-minted IRIs. References to other *new* same-batch terms use a temporary handle
  until that term is minted.
- **Cycles:** publish the defining nanopub first (intrinsic props only), then **supersede**
  it to add the cyclic/forward link triples once both endpoints have IRIs.

### Signing & provenance (GitHub/dropbox flow)
- Sign with the **bot keypair** (private key from a GitHub secret); the bot needs an
  **introduction nanopub** establishing its identity/owner.
- `prov:wasAttributedTo <suggester>` from the new YAML field; `dct:creator`/signature =
  the bot. pubinfo: `rdfs:label`, `dct:license` (CC BY 4.0), `npx:introduces <thing-URI>`.

### Pipeline flow
- **PR validation (no secrets):** build the defining nanopubs unsigned and validate them
  (and optionally a dry-run against the **test registry**).
- **On merge to `main` (bot secret available):** build → sequentially sign+publish defining
  nanopubs (live network) → supersede for any cyclic/forward links → write/append the
  id-map and redirects → regenerate `assertions/` for the site → commit `published/`,
  `archive/`, `assertions/`, id-map. (Single bot-run; no keyless serialize step needed.)
- **Site (`pages.yaml`):** build from `assertions/`.

## 5. Dropbox input format

Top-level list under `biochementity_subclasses:` (the `TARGET_CLASS`); each entry is a
LinkML `BioChemEntitySubClass` (defined in `schema/peh.yaml`; note the README links a
non-existent `schema/dropbox-biochementity.schema.json`).

| Field | Predicate | Notes |
|---|---|---|
| `id` | subject IRI (`schema:identifier`) | optional; minted if absent; an existing valid URI is kept |
| `name` | `rdfs:label` | preferred label; effectively required |
| `short_name` | `schema:alternateName` | |
| `ui_label` | `pehterms:hasUiLabel` | |
| `description` | `schema:description` | |
| `remark` | `schema:comment` | |
| `exact_matches` | `skos:exactMatch` | external ids (CHEBI/CAS/pubchem/inchikey) |
| `aliases` | `schema:alternateName` | list |
| `context_aliases` | `pehterms:hasContextAlias` | `{property_name, context, alias}` |
| `translations` | `pehterms:hasTranslation` | `{property_name, language, translated_value}` |
| `grouping_id_list` | `skos:broader` | |
| `group_labels` | `pehterms:hasGroupLabel` | list of strings |
| `molweight_grampermol` | `pehterms:hasMolecularWeight` | decimal |
| `has_role` | `RO_0000087` | external (CHEBI roles) |
| `is_metabolite_of` | `pehterms:isMetaboliteOf` | ⚠️ internal link |
| `is_isomer_of` | `pehterms:isIsomerOf` | ⚠️ internal link (symmetric → cycles) |
| `parent_biochementities` | `rdfs:subClassOf` | usually `…/terms/BioChemEntity`; may be another biochementity (⚠️, multiple allowed) |

**Proposed additions** (template change, per the call):
- `suggester` (ORCID) — for `prov:wasAttributedTo`. (Per-entry, or a per-file/batch default.)
- Fix the README example (`parent_biochementity` → `parent_biochementities`, a list) and
  add/point to a real dropbox JSON schema.

## 6. Identifier transition / migration (plan now, run later)

The 879 existing terms carry minted ULID/hash IDs and reference each other by them.
Migrating them to nanopub-based IDs is a **one-time** operation, executed deliberately
after the new flow is proven on the test registry.

1. Build a dependency graph of the 879 terms (handles = current minted IDs).
2. Topologically order (defining content excludes inter-biochementity links).
3. Sequentially sign+publish each **defining** nanopub (live) → record
   `old-minted-id → new RA-thing-URI`.
4. For terms with links (incl. the cyclic `isIsomerOf` pairs), publish **superseding**
   nanopubs adding the link triples with all references resolved to new IRIs.
5. Emit the full id-map; rewrite the site source (`assertions/`) and any redirects.
6. Keep the old→new map permanently so old IDs remain resolvable.

Estimated volume: ~879 defining + ~a few hundred superseding nanopubs.

## 7. Incremental PR breakdown

**Decision: scheme A (global placeholder substitution).** The artifact code goes on the
*thing* URI in our namespace while the nanopub URI stays the default `w3id.org/np`. This is
the strict generalization of the base-scoped placeholder (scheme A ⊇ B): substitute
`~~~ARTIFACTCODE~~~` wherever it appears, not only in the nanopub's own base URI. The Java and
nanopub-py implementations do this and are now pinned by a shared testsuite case. Tracking
issues:
[nanopub-py#232](https://github.com/Nanopublication/nanopub-py/issues/232),
[nanopub-testsuite#3](https://github.com/Nanopublication/nanopub-testsuite/issues/3).

**nanopub upstream changes:**
- **N0 (spike) — done.**
- **N1 (nanopub-py, #232) — ✅ DONE (merged, commit `a909047`; not yet released).** Global
  `~~~ARTIFACTCODE~~~` substitution in `get_trustyuri`. Consume via git-pin until 2.2.0 is on
  PyPI, then `nanopub>=2.2.0`. **No longer blocks the pubmate builder.**
- **N2 (nanopub-testsuite, #3) — ✅ DONE (merged, PR #4, commit `cfe9630`, 2026-06-17).**
  `transform/` case covering a foreign-namespace artifact-code thing URI; verifies Java/Python
  parity. Scheme A is now cross-implementation-pinned for the implementations we use.

**pubmate:**
- **P1:** defining-nanopub builder — assertion/term → unsigned nanopub via nanopub-py with
  thing URI `…/~~~ARTIFACTCODE~~~`, intrinsic props only, `prov:wasAttributedTo` suggester,
  pubinfo (label/license/introduces).
- **P2:** sequential mint+publish over a term set in dependency order; returns
  handle→thing-URI and term→nanopub-URI maps; nanopub-py sign+publish (test/live).
- **P3:** supersede-to-add-links helper for cyclic/forward references.
- **P4:** id-mapping / transition helpers.

**biochementity-vocabulary (this repo):**
- **B1:** dropbox YAML template + `suggester` field; real dropbox JSON schema; README fixes.
- **B2:** folder model — drop committed `unpublished/`; single `published/`; Make/CI scaffolding.
- **B3:** GitHub Action — PR validation (unsigned build + optional test-registry dry-run),
  no secrets.
- **B4:** GitHub Action — on-merge bot publish (secret key) → `published/` + id-map; commit/push.
- **B5:** site builds from `assertions/` regenerated from `published/`.
- **B6:** migration tooling (Section 6) wired but **not executed**; live run is a separate, deliberate step.

Each PR should be independently reviewable. N1 and N2 have landed, so the P-series (pubmate) is
unblocked and can proceed in parallel with the B-series; B3/B4 depend on P1–P3.

## 8. Out of scope / later

- Nanodash direct-contribution flow (users' own keys) and merging it with the GitHub flow.
- Nightly sync of all biochementity nanopubs (incl. Nanodash) into `published/`.
- Batch-as-index approval workflow.
- Roles/governance setup in the Nanodash space.
- Semantic-versioning releases of the vocabulary.
