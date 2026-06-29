# Biochementity Vocabulary — Nanopublication Workflow Plan

> Status: **upstream (N0–N2) and the pubmate library (P1–P4) are done; the B-series in this
> repo is the remaining work.** This document records the agreed direction so work can proceed
> as small, reviewable pull requests.
> Last updated: 2026-06-22.

## 1. Background & goal

Today the repo treats nanopublications as a *publish-time* concern: `dropbox/*.yaml`
is turned into bare RDF assertions (`unpublished/*.ttl`), and only at publish time does
`pubmate-publish` wrap each assertion into a nanopublication, sign, and push it.

We want nanopublications to be the **central artifact** and to make the identifiers
themselves nanopub-based (trusty artifact codes), while keeping a low-friction
"drop a YAML file, open a PR" contribution path. The work is split across two repos and
delivered as incremental PRs to both:

- **`knowledgepixels/biochementity-vocabulary`** (this repo): the vocabulary-specific glue —
  dropbox YAML contract, folder layout, CI/Make wiring, site build, migration data.
- **`knowledgepixels/pubmate`**: the reusable library logic — building/signing/publishing
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

6. **nanopub-py now supports custom-namespace artifact-code minting (scheme A) — DONE & RELEASED.**
   Originally it did not (its vendored `trustyuri` only rewrote URIs inside the dummy
   namespace; a placeholder in another namespace was passed through verbatim). This was
   fixed upstream in `nanopub/trustyuri/rdf/RdfUtils.py::get_trustyuri` (commit `a909047`,
   "Support `~~~ARTIFACTCODE~~~` placeholder in custom namespaces (#232)"). It first shipped
   in **nanopub-py `v2.2.1` (released 2026-06-22)** — note **not** `v2.2.0` (tagged 2026-04-21,
   six commits before `a909047`, so 2.2.0 has no placeholder support). Consume via
   `nanopub>=2.2.1` from PyPI:
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

> ✅ **Spike resolved, implemented & released (N0/N1).** The custom-namespace artifact-code thing
> URI works in nanopub-py as of commit `a909047`, released in **`v2.2.1` (2026-06-22)**. Consume via
> `nanopub>=2.2.1` from PyPI — the earlier git-pin to nanopub-py `main` is no longer needed and has
> been dropped in pubmate. This unblocks the pubmate builder (P1).

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
- `assertions/` — plain `.ttl` per term for the Pages site, **extracted from `published/` as a
  build artifact (not committed); the Pages job is its only consumer.** Required because
  `serves-me-right` (v0.0.1) cannot read nanopubs: it globs only `*.ttl`
  (`data_dir.rglob("*.ttl")`) — so `.trig` is silently skipped — and parses each as
  `format="turtle"` into a single flat `rdflib.Graph`, which can neither read TriG named graphs
  nor separate the assertion graph from provenance/pubinfo/signature. So the assertion graph
  must be projected out to plain `.ttl` for it. *(Name TBD. Generated into a temp dir inside the
  build, e.g. `make assertions`; teaching `serves-me-right` to read nanopubs directly would
  remove this folder, but that's an upstream change to a repo we don't pin here.)*
- `id-map/` (or `redirect/`) — old-minted-id → nanopub-id map + term→nanopub redirects.
- No committed `unpublished/`.

### Identifier model
- Canonical term IRI = `https://w3id.org/peh/biochementities/RA<artifactcode>`, where
  `<artifactcode>` is the artifact code of the term's **defining** nanopub.
- The nanopub's own URI stays the default `https://w3id.org/np/RA<artifactcode>`.
- Mechanism: defining nanopub built with the thing URI as
  `…/biochementities/~~~ARTIFACTCODE~~~` (requires the nanopub-py change N1; see §3 #6).
- **Sequential minting with inline cross-ref resolution:** process terms in topological order;
  rewrite each term's inter-term references to the **new** thing URIs via the id-map *before*
  signing (the nanopub-java `np sign -r` pattern — a `Resource→IRI` rewrite; reimplemented in
  pubmate). An acyclic link can be baked into the defining nanopub because its target is already
  minted (fixed artifact code).
- **Cycles** (symmetric `isIsomerOf`) have no single-pass fixed point — including the link changes
  the artifact code, which changes what the counterpart points to. So the cyclic link is **omitted**
  from the defining nanopub and added afterwards by **superseding**, once both endpoints have IRIs.

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
  id-map and redirects → commit `published/`, `archive/`, id-map. (Single bot-run; no keyless
  serialize step needed.) `assertions/` is **not** committed here — it is regenerated inside the
  Pages job.
- **Site (`pages.yaml`):** extract `assertions/` from `published/` at build time, then build
  from it.

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

**Additions** (template change, per the call):
- `suggester` (ORCID) — for `prov:wasAttributedTo`. **Per-entry, with an optional file-level
  default** that applies to entries omitting their own. The slot is defined upstream in
  `knowledgepixels/parco-hbm` (`schema/peh.yaml`, `suggester` → `prov:wasAttributedTo`, v0.6.2;
  on fork `main`, PR to `eu-parc/parco-hbm` pending). **DONE** as a dropbox contract in this
  repo (JSON schema + example); pipeline wiring still pending the upstream tag (see B1).
- Fixed the README example (`parent_biochementity` → `parent_biochementities`, a list; parent
  IRI `…/terms/BioChemEntity`) and added a real dropbox JSON schema. **DONE.**

## 6. Identifier transition / migration (plan now, run later)

The 879 existing terms carry minted ULID/hash IDs and reference each other by them
(`isMetaboliteOf` 267, `subClassOf`→biochementity 201, `isIsomerOf` 42 — symmetric, cyclic).
Migrating them to nanopub-based IDs is a **one-time** operation, executed deliberately
after the new flow is proven on the test registry.

**Approach: resolve non-cyclic links inline, supersede only the cycles.** Inter-term references
are rewritten to the *new* thing URIs at mint time via the id-map (the nanopub-java `np sign -r`
"resolve cross-nanopub references" pattern — a `Resource→IRI` rewrite over each assertion before
signing; reimplemented in pubmate since nanopub-py has no `-r`). A reference can be baked into a
term's defining nanopub **iff the referenced term is already minted** (its new URI is known and its
artifact code is fixed); topological order guarantees this for all **acyclic** links. **Cycles
cannot** be resolved in one pass — including the link changes the artifact code, which changes what
the counterpart points to (no fixed point) — so cyclic links are omitted from the defining nanopub
and added afterwards by **superseding**.

1. Build a dependency graph of the 879 terms (handles = current minted IDs); detect cycles
   (the symmetric `isIsomerOf` pairs).
2. Topologically order. Defining content includes **acyclic** inter-term links (resolved to new
   IRIs via the id-map); **cyclic** links are held back for step 4.
3. Sequentially sign+publish each **defining** nanopub (live), rewriting acyclic references to
   already-minted new IRIs as it goes → record `old-minted-id → new RA-thing-URI` in the id-map.
4. For the held-back cyclic links (`isIsomerOf`, ~42), publish **superseding** nanopubs (P3)
   adding the link triples once both endpoints have new IRIs.
5. Emit the full id-map and any redirects. (The site source `assertions/` is not persisted —
   it is regenerated from `published/` in the Pages job.)
6. Keep the old→new map permanently so old IDs remain resolvable.

Estimated volume: ~879 defining nanopubs + ~42 superseding (cyclic `isIsomerOf` only). Resolving
the ~468 acyclic links inline drops the superseding count from "every linked term" to just the
cyclic subset.

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
- **N1 (nanopub-py, #232) — ✅ DONE & RELEASED (commit `a909047`, shipped in `v2.2.1`, 2026-06-22).**
  Global `~~~ARTIFACTCODE~~~` substitution in `get_trustyuri`. Consume via `nanopub>=2.2.1` from
  PyPI (NOT 2.2.0 — that release predates the change). **No longer blocks the pubmate builder.**
- **N2 (nanopub-testsuite, #3) — ✅ DONE (merged, PR #4, commit `cfe9630`, 2026-06-17).**
  `transform/` case covering a foreign-namespace artifact-code thing URI; verifies Java/Python
  parity. Scheme A is now cross-implementation-pinned for the implementations we use.

**pubmate** (merged to `eu-parc/pubmate` via
**[PR #1](https://github.com/eu-parc/pubmate/pull/1)** and released as **`v0.1.0`**; this repo now
pins that tag — the `knowledgepixels` HEAD stopgap is gone):
- **P1 — ✅ DONE (`00cc0f3`).** defining-nanopub builder — wraps the given assertion graph into an
  unsigned nanopub via nanopub-py with thing URI `…/~~~ARTIFACTCODE~~~`,
  `prov:wasAttributedTo` suggester, pubinfo (label/license/introduces). (What goes *into* the
  assertion — which inter-term links are resolved vs held back for superseding — is decided upstream
  by the B6 migration, not here.)
- **P2 — ✅ DONE (`0b4671d`).** sequential mint+publish over a term set in dependency order;
  returns handle→thing-URI and term→nanopub-URI maps; nanopub-py sign+publish (test/live).
- **P3 — ✅ DONE (`cb348e5`).** supersede-to-add-links helper for cyclic/forward references.
- **P4 — ✅ DONE (`8f30f51`).** id-mapping / transition helpers.

**biochementity-vocabulary (this repo):**
- **B1 — ✅ DONE.** dropbox YAML template +
  `suggester` field; real dropbox JSON schema; README fixes.
  Landed: `schema/dropbox-biochementity.schema.json` + `…example.yaml`, README
  fixes, and the upstream `suggester` slot — merged to `eu-parc/parco-hbm` and served under tag
  `v0.6.1` (the tag was moved to include it; schema `version:` stayed `0.6.1`, our 0.6.2 bump was
  dropped). `PEH_SCHEMA_TAG` bumped `v0.6.0 → v0.6.1` and the schema re-fetched, so a **per-entry**
  `suggester` now flows through `make pipeline` to `prov:wasAttributedTo` (verified end-to-end).
  **File-level default — done (on a temporary pin).** Implemented as `pubmate-yamlconcat
  --inherit suggester` (pushes a top-level `suggester:` into entries that omit it; no key leak, no
  cross-file bleed; tests in `knowledgepixels/pubmate`). The Makefile `aggregate` step now passes
  `--inherit suggester`, and `make pipeline` produces `prov:wasAttributedTo` for both file-level
  and per-entry suggesters (verified end-to-end). **Pin:** `[tool.uv.sources] pubmate` is pinned to
  `eu-parc/pubmate` **`v0.1.0`** (the release carrying these CLIs + the P-series). The earlier
  `knowledgepixels/pubmate` HEAD stopgap has been retired.
- **B2 — ✅ DONE.** folder model — `published/` is now the home for signed nanopub `.trig`
  (source of truth). New `make assertions` target runs `pubmate-extract-assertions` to project
  each `published/*.trig` assertion graph to plain `.ttl` under `$(OUT_FOLDER)/assertions`
  (gitignored build artifact, not committed). The Pages workflow now runs `make assertions`
  and builds the site from `build/assertions` + `unpublished` (`serves-me-right` stays
  `.ttl`-only). **`unpublished/` kept in place** — still the only committed copy of the 879
  assertions and the live site source until migration runs (dropped in B7). During the
  transition `published/` is empty, so the extraction is a no-op and the site builds from
  `unpublished` as before. Verified end-to-end against a sample signed nanopub (assertion-only,
  artifact code on the thing URI). Folds B5 (site-from-`assertions/`) into this change.
- **B3 — ✅ DONE.** GitHub Action — PR validation, no secrets. `test-serialize.yaml`
  (`pull_request` on `dropbox/**`) runs `make validate-pr`: builds the proposed terms into an
  isolated `build/pr-assertions/` and runs `pubmate-validate-defining`, which wraps each
  assertion into a defining nanopub and signs it with an **ephemeral in-memory key** (no repo
  secrets, no network), asserting structural validity (valid trusty + signature). Proves every
  proposed term can become a well-formed nanopub. Stays on the `pull_request` trigger (safe for
  fork PRs); **not** `pull_request_target` (would expose secrets to untrusted PR content).
  *Deferred (optional):* a live dry-run against the **test registry** (needs the testsuite
  connector / network) — left out to keep the gate fully offline and fork-safe.
- **B4 — test-registry stage ✅ DONE; live activation remaining.** The publish path exists:
  `pubmate-mint-publish` drives the P2 sequential minter (re-keying assertions onto the
  artifact-code placeholder, lifting the suggester into provenance), writes `published/<code>.trig`
  + the merged `redirect/id-map.tsv` (old-id → thing/np URI), and skips already-minted terms.
  `make publish-defining` wires it; `publish-defining.yaml` (`workflow_dispatch`) mints the dropbox
  proposal on a branch and publishes to the **nanopub test server** via testsuite keys (no
  secrets), uploading nanopubs + id-map as artifacts. Verified end-to-end offline (dry-run): codes
  land on the thing URI (scheme A), suggester in provenance, id-map correct, re-runs idempotent.
  **Live activation (remaining):** (1) provision the **bot keypair** as a GitHub secret + an
  **introduction nanopub**; (2) ✅ **DONE** — `pubmate` is pinned to `eu-parc/pubmate` **`v0.1.0`**
  (reproducible release; the `knowledgepixels` HEAD stopgap is gone); (3)
  switch the trigger to **on-merge to `main`** and **commit** `published/` + id-map. Note: the
  incremental "publish only new terms" relies on the id-map already holding the 879 existing terms
  — that seeding is the migration (B6). Inline cross-ref resolution (acyclic links) and cycle
  **superseding** (P3, `isIsomerOf`) are part of B6.
- **B5 — ✅ DONE (folded into B2).** Pages job regenerates `assertions/` from `published/`
  (build artifact) and builds the site from it; `serves-me-right` stays `.ttl`-only.
- **B6:** migration (Section 6) — **not yet built or executed.** Primitives exist (P2 sequential
  minter, P3 supersession, id-map, `mint-publish`), but `mint-publish` currently mints assertions
  *as given* (inter-term references keep their old ids — see the dry-run preview). B6 adds: (a) the
  term **dependency graph + topological sort**, (b) **inline cross-ref resolution** — rewrite acyclic
  inter-term references to new thing URIs via the id-map before signing (the `np sign -r` pattern,
  reimplemented in pubmate; nanopub-py has no `-r`), and (c) **cycle detection** → defer the ~42
  cyclic `isIsomerOf` links to a P3 **superseding** pass. Then a live run over the 879. Test-registry-testable.
- **B7:** drop committed `unpublished/`. **Depends on B6 having run** — only once the 879
  assertions exist as nanopubs in `published/` and the site builds from regenerated
  `assertions/` can the old folder be removed without losing data or breaking the site.

Each PR should be independently reviewable. N1/N2, the full P-series (P1–P4), B1, B2, B3, B5, and
the test-registry stage of B4 have landed. Remaining: B4 live activation (bot secret + on-merge
commit — the eu-parc tag pin-back is done), B6 (migration — also seeds the id-map and adds inter-term
links by superseding), and B7 (drop `unpublished/`). Ordering note:
`unpublished/` cannot be dropped standalone — B2 introduced the new folders alongside it, the B6
migration repopulates the data as nanopubs, and only then does B7 remove the old folder.

Cross-cutting follow-up: ✅ **RESOLVED.** pubmate (P-series + the four new CLIs) landed in
`eu-parc/pubmate` via **[PR #1](https://github.com/eu-parc/pubmate/pull/1)** and is released as
**`v0.1.0`** (depending on released `nanopub>=2.2.2`, which carries the object-blank-node sign fix).
This repo's `pubmate` source is pinned to that tag, so publishing is reproducible — the
`knowledgepixels` HEAD stopgap and the nanopub-py git-pin are both gone. See B1/B4.

## 8. Out of scope / later

- Nanodash direct-contribution flow (users' own keys) and merging it with the GitHub flow.
- Nightly sync of all biochementity nanopubs (incl. Nanodash) into `published/`.
- Batch-as-index approval workflow.
- Roles/governance setup in the Nanodash space.
- Semantic-versioning releases of the vocabulary.
