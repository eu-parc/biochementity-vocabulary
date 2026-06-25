# Setting up the publishing bot identity

The defining nanopublications are signed and published by a **bot**: a software
agent with its own RSA keypair. The bot is *introduced* once by a self-signed
**introduction** nanopublication that binds the agent URI to its public key, so
anyone can verify that later nanopubs `npx:signedBy` the bot really come from it.

This is a **one-time setup**, wrapped in three `make` targets. Do it once; the key
then lives as a GitHub secret and CI uses it for every publish (incremental
`publish-defining` and the one-time `migrate`).

## Identity facts

These are pinned as `make` variables (override on the command line if needed):

| Variable | Default |
|---|---|
| `BOT_NAME` | `Biochementity bot` |
| `BOT_ID` | `biochementity-bot` (→ `…/np/RA<code>/biochementity-bot`) |
| `BOT_OWNER_ORCID` | `https://orcid.org/0000-0001-8327-0142` (Gertjan Bisschop) |
| `CI_REPO` | `eu-parc/biochementity-vocabulary` |

The bot publishes to the nanopub **production** registry. Pass
`BOT_PUBLISH_ARGS=--test-server` to use the test registry instead.

> The private key **is** the bot's identity — a regenerated key is a *different*
> bot (the agent URI is derived from the key). Generate it offline, review before
> publishing, then keep it stable: rotating it means a new introduction.

## Prerequisites

`pubmate >= 0.2.0` (provides `pubmate-bootstrap-identity`), available once this
repo's `pyproject.toml` is pinned to `eu-parc/pubmate` `v0.2.0`. `gh`
authenticated with access to `CI_REPO`.

## Steps

```bash
# 1. Generate the keypair + a signed (unpublished) introduction under ./bot-identity/
make bot-identity

# 2. REVIEW ./bot-identity/introduction.trig
#    (agent typed npx:Bot/SoftwareAgent, frbr:owner = the owner ORCID, key declared).

# 3. Publish the reviewed introduction to the network.
make publish-bot-introduction

# 4. Push the signing key (secret) + bot/introduction URIs (variables) to CI.
make bot-ci-secrets
```

`make bot-ci-secrets` derives the canonical bot and introduction URIs from the
published `introduction.trig` and sets, on `CI_REPO`:

- secret `NANOPUB_BOT_PRIVATE_KEY` — the signing key (the only secret);
- variables `NANOPUB_BOT_PUBLIC_KEY`, `NANOPUB_BOT_URI`, `NANOPUB_BOT_INTRO_URI`.

`./bot-identity/` is git-ignored — keep the private key off the repo and archive
it somewhere safe (password manager / secret store).

## Wire it into publishing (B4 live activation)

The live steps already exist in `.github/workflows/publish-defining.yaml` as
commented-out blocks marked **`LIVE:`** — uncomment them (and drop/guard the
test-publish + upload steps) to switch the workflow to the real bot key, the
production registry, the on-merge trigger, and committing `published/` + the
id-map back. They consume the secret + variables `make bot-ci-secrets` set above.

The publish targets take the signing material through `PUBLISH_KEY_ARGS`, where
`--orcid-id` is the **bot agent URI** (so `npx:signedBy` resolves to the bot, not
a person). The same `PUBLISH_KEY_ARGS` drives the one-time `make migrate` (B6), so
migration and all later incremental publishing share one bot identity.
