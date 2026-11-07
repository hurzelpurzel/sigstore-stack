SHELL := /bin/bash

COMPOSE ?= $(shell if command -v podman-compose >/dev/null 2>&1; then echo podman-compose; elif docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo podman-compose; fi)

FILE ?=
IMAGE ?=

.PHONY: help up down reset logs ps pki ensure-pki token demo sign-blob verify-blob seed-registry sign-image verify-image

help:
	@echo "Local Sigstore stack"
	@echo
	@echo "  make up                 Start the stack"
	@echo "  make down               Stop the stack (keeps data)"
	@echo "  make reset              Stop and delete all data, then start"
	@echo "  make logs               Follow all service logs"
	@echo "  make ps                 Show service status"
	@echo "  make pki                Regenerate dev PKI and cosign trust material"
	@echo "  make ensure-pki         Generate PKI only if it is missing"
	@echo "  make token              Print a Keycloak access token"
	@echo "  make demo               Sign/verify a blob and an image end to end"
	@echo
	@echo "  make sign-blob FILE=path"
	@echo "  make verify-blob FILE=path"
	@echo "  make seed-registry      Build/push a demo image, print IMAGE reference"
	@echo "  make sign-image IMAGE=repo@sha256:..."
	@echo "  make verify-image IMAGE=repo@sha256:..."

# Generate keys on a fresh checkout, but never rotate them on a normal start:
# existing Rekor entries and bundles are tied to the current log key.
ensure-pki:
	@./scripts/gen-pki.sh --if-missing

up: ensure-pki
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

reset: ensure-pki
	$(COMPOSE) down -v
	$(COMPOSE) up -d

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

pki:
	./scripts/gen-pki.sh

token:
	./scripts/token.sh

sign-blob:
	@test -n "$(FILE)" || { echo "Usage: make sign-blob FILE=path" >&2; exit 1; }
	./scripts/sign-blob.sh "$(FILE)"

verify-blob:
	@test -n "$(FILE)" || { echo "Usage: make verify-blob FILE=path" >&2; exit 1; }
	./scripts/verify-blob.sh "$(FILE)"

seed-registry:
	./scripts/seed-registry.sh

sign-image:
	@test -n "$(IMAGE)" || { echo "Usage: make sign-image IMAGE=repo@sha256:..." >&2; exit 1; }
	./scripts/sign-image.sh "$(IMAGE)"

verify-image:
	@test -n "$(IMAGE)" || { echo "Usage: make verify-image IMAGE=repo@sha256:..." >&2; exit 1; }
	./scripts/verify-image.sh "$(IMAGE)"

demo:
	@set -o pipefail; \
	tmp=$$(mktemp /tmp/sigstore-demo-XXXXXX.txt); \
	printf 'hello from the local Sigstore stack\n' > "$$tmp"; \
	echo "==> Blob signing demo"; \
	./scripts/sign-blob.sh "$$tmp" || exit 1; \
	./scripts/verify-blob.sh "$$tmp" || exit 1; \
	echo "==> Image signing demo"; \
	ref=$$(./scripts/seed-registry.sh | sed -n 's/^IMAGE=//p'); \
	[[ -n "$$ref" ]] || { echo "Error: could not determine demo image digest" >&2; exit 1; }; \
	./scripts/sign-image.sh "$$ref" || exit 1; \
	./scripts/verify-image.sh "$$ref" || exit 1; \
	rm -f "$$tmp" "$$tmp.sigstore.json"; \
	echo; \
	echo "Demo completed successfully."
