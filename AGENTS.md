# AGENTS.md

Guidance for coding agents working on this repository.

## What this is

A local, development-only Sigstore deployment for keyless signing of blobs and
container images. It runs Fulcio, Rekor v1, a Tesseract CT log, Keycloak as the
OIDC issuer, the Rekor search UI, a local OCI registry, and MySQL/Trillian via
Docker Compose or Podman Compose.

**Never treat any key, password, or endpoint here as production material.** The
CA/log keys are committed, passwords live in `.env`, and all services use plain
HTTP. Keycloak runs with `start-dev`.

## Golden rules

1. **Use the cosign v3 interface.** Sign/verify with `--signing-config`,
   `--trusted-root`, and `--bundle`. Do not reintroduce the removed
   `--fulcio-url`, `--rekor-url`, or `--oidc-issuer` flags.
2. **The Rekor log key must be ECDSA P-256.** `sigstore-go` verifies Rekor v1
   SETs with `ecdsa.VerifyASN1`. An Ed25519 log key parses but causes bundle
   creation/verification to fail with
   `not enough verified log entries from transparency log: 0 < 1`.
3. **Keep the issuer URL exact:** `http://keycloak.localhost:8080/realms/sigstore`.
   It is embedded in issued certificates. It must resolve to loopback on the
   host and is a Compose network alias for containers.
4. **PKI or URL changes require `make pki && make reset`.** Trust material is
   generated, not fetched from TUF, and old Rekor entries do not verify against
   a new log key.
5. **Preserve the out-of-box flow:** `make up && make demo` must pass without
   manual steps.
6. **The bundled registry is HTTP.** Use `--allow-http-registry` with cosign and
   `--tls-verify=false` with `podman push`.
7. **Pin versions.** Keep container image tags pinned in `compose.yaml`; do not
   replace pins with `latest`.

## Commands

| Command | Purpose |
| --- | --- |
| `make up` | Start the stack (builds Rekor wrapper and UI on first run) |
| `make down` | Stop containers, keep volumes |
| `make reset` | Stop, delete volumes, start clean |
| `make ps` / `make logs` | Status / follow logs |
| `make pki` | Regenerate dev PKI and cosign trust files |
| `make token` | Print a Keycloak access token |
| `make demo` | End-to-end blob and image sign/verify smoke test |
| `make seed-registry` | Build/push demo image, print `IMAGE=repo@sha256:...` |
| `make sign-blob FILE=...` / `make verify-blob FILE=...` | Blob flow |
| `make sign-image IMAGE=...` / `make verify-image IMAGE=...` | Image flow |

Compose is selected automatically: `podman-compose`, else `docker compose`.
Override with `make COMPOSE="docker compose" ...`.

## Validate changes

Run at minimum:

```bash
bash -n scripts/*.sh
make up
make demo
```

Expected results:

- Blob signing reports `Wrote bundle ...` and verification prints `Verified OK`.
- Image signing reports `Pushing signature to: ...` and verification lists the
  checks as successful.
- `curl -s http://localhost:3000/api/v1/log | jq '{treeSize,treeID}'` shows a
  growing tree size.

For Compose, Rekor wrapper, PKI, or URL changes, also run:

```bash
make reset
make demo
```

## Architecture invariants

**Rekor tree persistence.** `rekor/entrypoint.sh` waits for MySQL and Trillian,
reads the highest `TreeId` from Trillian's `Trees` table, then appends
`--trillian_log_server.tlog_id=<id>` before starting `rekor-server`. Preserve
this behavior; without it, every container restart can create a new Trillian
tree and the Rekor log appears empty.

**Trust material.** `scripts/gen-pki.sh` generates:

- Fulcio root CA (`config/pki/fulcio.{crt,key}.pem`)
- Rekor ECDSA P-256 log key (`config/pki/rekor.{key,pub}.pem`)
- CT log ECDSA P-256 key (`config/pki/ctlog.{key,pub}.pem`)
- `config/cosign/trusted-root.json`
- `config/cosign/signing-config.json`

The trusted-root Rekor `logId.keyId` must equal the SHA-256 of the DER-encoded
Rekor public key. Verify with:

```bash
openssl pkey -pubin -in config/pki/rekor.pub.pem -outform DER | sha256sum
python3 -c "import json,base64; print(base64.b64decode(json.load(open('config/cosign/trusted-root.json'))['tlogs'][0]['logId']['keyId']).hex())"
```

**Rekor UI.** `rekor-ui/Dockerfile` pins an upstream commit and applies
`0001-build-fixes.patch`. The patch works around an `@peculiar/x509` API change
and enables static export. Keep the commit and patch in sync; do not build the
UI from an unpinned branch.

## Important files

| Path | Notes |
| --- | --- |
| `compose.yaml` | Service topology, pins, ports, healthchecks, volumes |
| `.env` / `.env.example` | Dev defaults consumed by Compose and scripts |
| `config/fulcio/config.yaml` | Fulcio OIDC provider configuration |
| `config/keycloak/realm-sigstore.json` | Realm, `sigstore` client, mappers, `alice` user |
| `rekor/` | Wrapper image that discovers the persisted Trillian tree ID |
| `rekor-ui/` | Pinned UI build and nginx static serving |
| `scripts/gen-pki.sh` | Single source of truth for dev PKI and cosign config |
| `scripts/lib.sh` | Shared `.env` loading and dependency checks |

## Common pitfalls

- **Wrong image digest.** Sign the manifest digest (`repo@sha256:...`), not the
  config digest printed by `podman build`. `make seed-registry` resolves the
  correct one.
- **Stale containers after rebuilding.** `podman-compose` may keep an existing
  container. Remove it and `up -d --force-recreate <service>`, or use
  `make reset`.
- **YAML healthcheck quoting.** Keycloak's healthcheck writes an HTTP request
  with `\r\n`; keep the command a quoted block scalar. An unquoted colon breaks
  Compose parsing.
- **MariaDB auth plugin.** The Rekor wrapper installs `mariadb-connector-c` so
  the Alpine client can authenticate with MySQL's
  `caching_sha2_password`.
- **`make pki` invalidates existing bundles.** It regenerates every key and the
  Fulcio root, so reset volumes and re-sign artifacts afterwards.
- **No TSA.** Do not add timestamp-authority requirements to verification
  policies unless you also add and configure a TSA.

## Style

- Bash scripts: `#!/usr/bin/env bash`, `usage()`, `main()`, dependency checks,
  explicit error handling, guard clause. Keep output parseable where scripts
  are composed (e.g. `seed-registry.sh` prints only `IMAGE=...` on stdout).
- Keep development defaults obvious and documented rather than silently
  hardening the stack.
