# nanopub-preview — TEMPORARY review artifact

**This folder is not meant to be merged.** It is committed only so the migrated
nanopublications can be double-checked in-place, and will be **removed before the
PR is merged** (so the squash-merge nets it out of the upstream history).

## What's here

The full output of a migration dry-run over the 879 staged term definitions in
[`../unpublished/`](../unpublished):

- **879 defining** nanopublications + **21 superseding** nanopublications
  (the 21 = symmetric `isIsomerOf` cycles, whose held-back back-edge is added by
  a superseding nanopub), one `.trig` per file, named by its trusty artifact code.
- Generated with `pubmate-migrate` (cross-references resolved inline to the new
  trusty thing URIs; cyclic links deferred to superseding).

## Important caveats

- **Dry-run / throwaway signature.** These are signed with an *ephemeral* key, so
  `npx:signedBy` is `orcid:0000-0000-0000-0000` and the artifact codes are **not
  final** — the real run signs with the bot key, which changes every code. Review
  the *content and structure*, not the specific codes.
- **7 dangling references were dropped** (and reported as errors) — broken
  `isMetaboliteOf` links to 3 missing terms; see
  eu-parc/biochementity-vocabulary#45. Affected terms still mint, minus the
  broken link.
