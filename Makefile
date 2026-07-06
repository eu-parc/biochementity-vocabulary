DROPBOX_FOLDER ?= dropbox
UNPUBLISHED_FOLDER ?= unpublished
PUBLISHED_FOLDER ?= published
ARCHIVE_FOLDER ?= archive
REDIRECT_FOLDER ?= redirect
SCHEMA ?= schema/peh.yaml
PEH_SCHEMA_REPO ?= eu-parc/parco-hbm
PEH_SCHEMA_TAG ?= v0.6.1
PEH_SCHEMA_SOURCE_PATH ?= linkml/schema/peh.yaml
PEH_SCHEMA_DEST ?= schema/peh.yaml
PEH_SCHEMA_URL ?= https://raw.githubusercontent.com/$(PEH_SCHEMA_REPO)/$(PEH_SCHEMA_TAG)/$(PEH_SCHEMA_SOURCE_PATH)
OUT_FOLDER ?= build
ASSERTIONS_FOLDER ?= $(OUT_FOLDER)/assertions
PR_ASSERTIONS_FOLDER ?= $(OUT_FOLDER)/pr-assertions
ONTOLOGY_LABEL ?= biochementities.ttl
TARGET_CLASS ?= biochementity_subclasses
BASE_NAMESPACE ?= https://w3id.org/peh/terms/
TERM_PARENT_CLASS ?= https://w3id.org/peh/terms/BioChemEntity
MINT_NAMESPACE ?= https://w3id.org/peh/biochementities/
ENTITY_LIST_PREDICATE ?= https://w3id.org/peh/terms/hasBioChemEntitySubclass
COMBINED_DATA ?= $(OUT_FOLDER)/combined.yaml
ID_MAP_FILE ?= $(REDIRECT_FOLDER)/id-map.tsv
# Signing material for `publish-defining`. Default: nanopub-testsuite keys
# (test server, no repo secret). For live publishing set, e.g.:
PUBLISH_KEY_ARGS ?= --private-key bot-identity/id_rsa --public-key bot-identity/id_rsa.pub --orcid-id https://w3id.org/np/RAWDFdbuQxoc9NE7suv9ZPpGeQJ4h_QVL67iJy5ZFaCYA/biochementity-bot --name 'Biochementity bot' --intro-nanopub-uri https://w3id.org/np/RAWDFdbuQxoc9NE7suv9ZPpGeQJ4h_QVL67iJy5ZFaCYA
# PUBLISH_KEY_ARGS ?= --use-testsuite-keys
# Suggester (prov:wasAttributedTo) attributed to every existing term during the
# one-time `migrate`. All current data was contributed by Gertjan Bisschop.
MIGRATE_SUGGESTER ?= https://orcid.org/0000-0001-8327-0142
# pubinfo tags stamped on every minted nanopub: npx:hasNanopubType (the kind of
# thing each nanopub defines) and nt:wasCreatedFromTemplate (the published
# "Defining a biochementity" assertion template, so Nanodash renders them with
# the matching form).
NANOPUB_TYPE ?= https://w3id.org/peh/terms/BioChemEntity
NANOPUB_TEMPLATE ?= https://w3id.org/np/RALm3XedpEbjtQy1nPJEQpOdsV0hPm5APkvvym-7P1Vpk
# Vocabulary each term links to via dcterms:isPartOf in its assertion.
NANOPUB_PART_OF ?= https://w3id.org/spaces/biochementity/r/vocabulary
DRY ?=

# Publishing bot identity (one-time setup; see docs/bot-identity-setup.md).
BOT_NAME ?= Biochementity bot
BOT_ID ?= biochementity-bot
BOT_OWNER_ORCID ?= https://orcid.org/0000-0001-8327-0142
BOT_OWNER_NAME ?= Gertjan Bisschop
BOT_IDENTITY_DIR ?= bot-identity
# Repo the publishing CI runs in (where the signing secret/variables live).
CI_REPO ?= eu-parc/biochementity-vocabulary
# Pass BOT_PUBLISH_ARGS=--test-server to introduce the bot on the test registry.
BOT_PUBLISH_ARGS ?=
_BOOTSTRAP_ARGS = --bot-name "$(BOT_NAME)" --bot-id "$(BOT_ID)" \
	--owner-orcid "$(BOT_OWNER_ORCID)" --owner-name "$(BOT_OWNER_NAME)" \
	--output-dir "$(BOT_IDENTITY_DIR)"

DATA_FILES = $(sort $(wildcard $(DROPBOX_FOLDER)/*.yaml))

.PHONY: help print-data prepare fetch-peh-schema aggregate mint build graph2assertions \
	validate-pipeline validate-nanopubs validate-pr process-dropbox archive-dropbox \
	publish-defining migrate pipeline assertions \
	bot-identity publish-bot-introduction bot-ci-secrets \
	test-flow clean

help:
	@echo "Targets:"
	@echo "  make fetch-peh-schema          # download schema/peh.yaml from a tagged parco-hbm release"
	@echo "  make pipeline                  # process dropbox -> unpublished + archive"
	@echo "  make validate-pipeline         # process dropbox -> build + unpublished, without archive/publish"
	@echo "  make validate-pr               # PR gate: build proposed terms + validate as defining nanopubs (keyless)"
	@echo "  make assertions                # extract published/*.trig -> $(ASSERTIONS_FOLDER) (site build artifact)"
	@echo "  make publish-defining          # mint unpublished assertions -> published/*.trig + id-map (test server)"
	@echo "  make publish-defining DRY=--dry-run"
	@echo "  make migrate                   # B6: one-time id migration of existing terms (+ links) -> published/*.trig + id-map"
	@echo "  make migrate DRY=--dry-run"
	@echo "  make bot-identity              # one-time: generate bot keypair + introduction to review (offline)"
	@echo "  make publish-bot-introduction  # one-time: publish the reviewed introduction to the network"
	@echo "  make bot-ci-secrets            # one-time: push signing key + identity URIs to $(CI_REPO)"
	@echo "  make test-flow                 # local end-to-end dry-run test"

print-data:
	@echo "$(DATA_FILES)"

prepare:
	mkdir -p $(OUT_FOLDER) $(UNPUBLISHED_FOLDER) $(PUBLISHED_FOLDER) $(ARCHIVE_FOLDER) $(REDIRECT_FOLDER)

fetch-peh-schema:
	@if [ -z "$(PEH_SCHEMA_TAG)" ]; then \
		echo "PEH_SCHEMA_TAG must be set to a released tag, for example v0.4.0."; \
		exit 1; \
	fi
	mkdir -p $(dir $(PEH_SCHEMA_DEST))
	curl -fsSL "$(PEH_SCHEMA_URL)" -o "$(PEH_SCHEMA_DEST)"
	@echo "Downloaded $(PEH_SCHEMA_DEST) from $(PEH_SCHEMA_REPO) tag $(PEH_SCHEMA_TAG)"

aggregate: prepare
	@set -e; \
	if [ -z "$(DATA_FILES)" ]; then \
		echo "No YAML files found in $(DROPBOX_FOLDER). Skipping aggregation."; \
	else \
		uv run pubmate-yamlconcat \
			--target $(TARGET_CLASS) \
			--inherit suggester \
			$(COMBINED_DATA) \
			$(DATA_FILES); \
	fi

mint: aggregate
	@set -e; \
	if [ ! -f "$(COMBINED_DATA)" ]; then \
		echo "No combined YAML available. Skipping mint."; \
	else \
		uv run pubmate-mint \
			--data $(COMBINED_DATA) \
			--target $(TARGET_CLASS) \
			--namespace "$(MINT_NAMESPACE)" \
			--verbose \
			--preflabel name; \
	fi

build: mint
	@set -e; \
	if [ ! -f "$(COMBINED_DATA)" ]; then \
		echo "No combined YAML available. Skipping RDF conversion."; \
	else \
		echo "Building $(ONTOLOGY_LABEL)"; \
		uv run linkml-convert \
			--target-class EntityList \
			-s $(SCHEMA) \
			-o $(OUT_FOLDER)/$(ONTOLOGY_LABEL) \
			$(COMBINED_DATA); \
		echo "Build completed successfully for $(ONTOLOGY_LABEL)"; \
	fi

graph2assertions: build
	@set -e; \
	if [ ! -f "$(OUT_FOLDER)/$(ONTOLOGY_LABEL)" ]; then \
		echo "No ontology file available. Skipping assertion extraction."; \
	else \
		uv run pubmate-cleanrdf \
			--input-ontology-path $(OUT_FOLDER)/$(ONTOLOGY_LABEL) \
			--base-namespace $(BASE_NAMESPACE) \
			--term-output-path $(UNPUBLISHED_FOLDER) \
			--subjects-from-predicate $(ENTITY_LIST_PREDICATE); \
	fi

validate-pipeline: graph2assertions

# Keyless PR gate: build the proposed terms' assertions into an isolated folder
# and confirm each one forms a valid, signable defining nanopub (ephemeral key,
# no secrets, no network). Final URIs/publishing happen later with the bot key.
validate-nanopubs:
	@set -e; \
	uv run pubmate-validate-defining \
		--assertion-folder $(PR_ASSERTIONS_FOLDER) \
		--namespace "$(MINT_NAMESPACE)"

validate-pr:
	$(MAKE) validate-pipeline UNPUBLISHED_FOLDER=$(PR_ASSERTIONS_FOLDER)
	$(MAKE) validate-nanopubs

archive-dropbox: graph2assertions
	@set -e; \
	if [ -n "$(DRY)" ]; then \
		echo "DRY mode enabled. Keeping YAML files in $(DROPBOX_FOLDER)."; \
		exit 0; \
	fi; \
	files="$(DATA_FILES)"; \
	if [ -z "$$files" ]; then \
		echo "No YAML files found in $(DROPBOX_FOLDER). Nothing to archive."; \
		exit 0; \
	fi; \
	if [ ! -f "$(COMBINED_DATA)" ]; then \
		echo "No minted combined YAML available. Nothing to archive."; \
		exit 1; \
	fi; \
	while :; do \
		label=$$(python3 -c 'import os, time; alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; value = (int(time.time() * 1000) << 80) | int.from_bytes(os.urandom(10), "big"); print("".join(alphabet[(value >> shift) & 31] for shift in range(125, -1, -5)))'); \
		dest="$(ARCHIVE_FOLDER)/combined_$${label}.yaml"; \
		[ ! -e "$$dest" ] && break; \
	done; \
	cp "$(COMBINED_DATA)" "$$dest"; \
	echo "Archived minted combined YAML -> $$dest"; \
	for src in $$files; do \
		rm "$$src"; \
		echo "Removed processed dropbox file $$src"; \
	done

process-dropbox: archive-dropbox

pipeline: process-dropbox

# B4: mint the unpublished assertions into signed defining nanopublications
# (artifact code on the thing URI) in $(PUBLISHED_FOLDER), and write/merge the
# old-id -> nanopub id-map. Already-minted terms (per the id-map) are skipped.
# Defaults to the nanopub test server via testsuite keys; override
# PUBLISH_KEY_ARGS for live publishing, and pass DRY=--dry-run for an offline
# sign-only preview. Inter-term link/cycle superseding is handled by migration.
publish-defining: prepare
	@set -e; \
	uv run pubmate-mint-publish \
		--assertion-folder $(UNPUBLISHED_FOLDER) \
		--namespace "$(MINT_NAMESPACE)" \
		--output-dir $(PUBLISHED_FOLDER) \
		--id-map-file $(ID_MAP_FILE) \
		--part-of "$(NANOPUB_PART_OF)" \
		--nanopub-type "$(NANOPUB_TYPE)" \
		--template "$(NANOPUB_TEMPLATE)" \
		$(PUBLISH_KEY_ARGS) \
		$(DRY)

# B6: one-time migration of the existing cross-referencing terms to nanopub
# identifiers. Mints a defining nanopub per term with inter-term references
# resolved inline to the new trusty URIs, and superseding nanopubs for cyclic
# links (e.g. symmetric isIsomerOf). All existing data is attributed to
# MIGRATE_SUGGESTER. Writes to $(PUBLISHED_FOLDER) and seeds the old-id ->
# nanopub id-map ($(ID_MAP_FILE)) that `publish-defining` then extends
# incrementally. Resumable: terms already in the id-map are skipped. Same signing
# defaults as publish-defining (testsuite keys -> test server); override
# PUBLISH_KEY_ARGS for live, pass DRY=--dry-run for an offline sign-only preview.
# Requires a pubmate release that includes pubmate-migrate (see pyproject pin).
migrate: prepare
	@set -e; \
	uv run pubmate-migrate \
		--assertion-folder $(UNPUBLISHED_FOLDER) \
		--namespace "$(MINT_NAMESPACE)" \
		--output-dir $(PUBLISHED_FOLDER) \
		--id-map-file $(ID_MAP_FILE) \
		--default-suggester "$(MIGRATE_SUGGESTER)" \
		--nanopub-type "$(NANOPUB_TYPE)" \
		--template "$(NANOPUB_TEMPLATE)" \
		--part-of "$(NANOPUB_PART_OF)" \
		$(PUBLISH_KEY_ARGS) \
		$(DRY)

# --- Publishing bot identity (one-time setup; see docs/bot-identity-setup.md) ---
# The bot is a software agent with its own RSA key; an introduction nanopub binds
# its agent URI to that key so consumers can verify what it signs. Generate the
# key OFFLINE and review before publishing -- the key IS the identity.

# 1. Generate the keypair + a signed-but-unpublished introduction under
#    $(BOT_IDENTITY_DIR). Review $(BOT_IDENTITY_DIR)/introduction.trig before
#    publishing. Refuses to overwrite an existing key (delete the dir to redo).
bot-identity:
	uv run pubmate-bootstrap-identity $(_BOOTSTRAP_ARGS) --generate-keys

# 2. Publish the reviewed introduction to the network (production; pass
#    BOT_PUBLISH_ARGS=--test-server for the test registry). Overwrites
#    introduction.trig in place with the published (canonical) version.
publish-bot-introduction:
	uv run pubmate-bootstrap-identity $(_BOOTSTRAP_ARGS) \
		--private-key $(BOT_IDENTITY_DIR)/id_rsa --public-key $(BOT_IDENTITY_DIR)/id_rsa.pub \
		--publish $(BOT_PUBLISH_ARGS)

# 3. Push the signing key (secret) + identity URIs (variables) to the CI repo.
#    The bot/intro URIs are derived from the published introduction.trig, so run
#    this after publish-bot-introduction. Needs gh authenticated for $(CI_REPO).
bot-ci-secrets:
	@set -e; \
	intro=$$(grep -oP '@prefix this: <\K[^>]+' $(BOT_IDENTITY_DIR)/introduction.trig); \
	bot="$$intro/$(BOT_ID)"; \
	echo "Introduction : $$intro"; echo "Bot agent URI: $$bot"; \
	gh secret   set NANOPUB_BOT_PRIVATE_KEY --repo $(CI_REPO) < $(BOT_IDENTITY_DIR)/id_rsa; \
	gh variable set NANOPUB_BOT_PUBLIC_KEY  --repo $(CI_REPO) < $(BOT_IDENTITY_DIR)/id_rsa.pub; \
	gh variable set NANOPUB_BOT_URI         --repo $(CI_REPO) --body "$$bot"; \
	gh variable set NANOPUB_BOT_INTRO_URI   --repo $(CI_REPO) --body "$$intro"; \
	echo "Pushed signing key + identity URIs to $(CI_REPO)."

# Site-facing projection: extract the assertion graph of each published
# nanopublication (.trig) into plain .ttl. This is a build artifact (under
# $(OUT_FOLDER), gitignored) consumed only by the Pages build; not committed.
assertions: prepare
	@set -e; \
	uv run pubmate-extract-assertions \
		--nanopub-folder $(PUBLISHED_FOLDER) \
		--out $(ASSERTIONS_FOLDER)

test-flow:
	$(MAKE) validate-pipeline

clean:
	rm -f $(OUT_FOLDER)/* $(UNPUBLISHED_FOLDER)/*.ttl
