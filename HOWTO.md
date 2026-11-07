# HOWTO: sign and verify container images with cosign

A step-by-step walkthrough for signing a container image with this local
Sigstore stack. It uses cosign v3 and the bundled local registry on
`localhost:5001`.

For blob signing, see the main [README](README.md).

## What happens during signing

1. `scripts/token.sh` gets an OIDC token from Keycloak (`alice@example.com`).
2. cosign generates an ephemeral key pair and requests a certificate from Fulcio.
3. Fulcio embeds the OIDC identity in the certificate and logs it to the CT log.
4. cosign signs the image digest and writes the entry to Rekor.
5. cosign uploads the Sigstore bundle to the registry as an OCI artifact.

No long-lived signing key is involved.

## 1. Start the stack

You need cosign v3, `curl`, `jq`, `skopeo`, and Podman or Docker.

```bash
cp .env.example .env   # only needed the first time
make up
make ps
```

Wait until `keycloak`, `rekor-server`, and `rekor-ui` report healthy.

Check the tooling:

```bash
cosign version                 # must be v3 or newer
curl -s http://localhost:3000/api/v1/log | jq '{treeID,treeSize}'
```

## 2. Get an image digest

You sign an immutable digest, not a mutable tag.

### Use the bundled demo image

```bash
make seed-registry
```

The last line looks like:

```
IMAGE=localhost:5001/demo/hello@sha256:ec0e...
```

Capture it for later commands:

```bash
REF=$(make -s seed-registry | sed -n 's/^IMAGE=//p')
echo "$REF"
```

### Or use your own image

Build it, push it to the local registry, then resolve the digest:

```bash
podman build -t localhost:5001/myapp:v1 .
podman push --tls-verify=false localhost:5001/myapp:v1

DIGEST=$(skopeo inspect --tls-verify=false \
  --format '{{.Digest}}' docker://localhost:5001/myapp:v1)
REF="localhost:5001/myapp@${DIGEST}"
echo "$REF"
```

Using Docker instead of Podman:

```bash
docker build -t localhost:5001/myapp:v1 .
docker push localhost:5001/myapp:v1
```

Docker treats `localhost` registries as insecure automatically.

## 3. Sign the image

With the helper (gets a token for you):

```bash
make sign-image IMAGE="$REF"
```

Or with annotations:

```bash
./scripts/sign-image.sh -a env=dev -a owner=alice "$REF"
```

Equivalent raw cosign command:

```bash
TOKEN=$(./scripts/token.sh)

cosign sign --yes \
  --allow-http-registry \
  --signing-config config/cosign/signing-config.json \
  --trusted-root config/cosign/trusted-root.json \
  --identity-token "$TOKEN" \
  -a env=dev \
  "$REF"
```

Expected output includes:

```
Generating ephemeral keys...
Signing artifact...
Pushing signature to: localhost:5001/demo/hello
```

The signature bundle is stored in the registry; it is not written to the current
directory.

## 4. Verify the image

With the helper:

```bash
make verify-image IMAGE="$REF"
```

Raw cosign command:

```bash
cosign verify \
  --allow-http-registry \
  --trusted-root config/cosign/trusted-root.json \
  --certificate-identity alice@example.com \
  --certificate-oidc-issuer http://keycloak.localhost:8080/realms/sigstore \
  "$REF"
```

Successful output starts with:

```
Verification for localhost:5001/demo/hello@sha256:... --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The code-signing certificate was verified using trusted certificate authority certificates
```

`--certificate-identity` and `--certificate-oidc-issuer` are your verification
policy. A valid signature from a different identity must not pass. A regexp
identity works too:

```bash
cosign verify --allow-http-registry \
  --trusted-root config/cosign/trusted-root.json \
  --certificate-identity-regexp '^alice@example\.com$' \
  --certificate-oidc-issuer http://keycloak.localhost:8080/realms/sigstore \
  "$REF"
```

## 5. Inspect the signature and transparency log

Download the bundle stored in the registry:

```bash
cosign download signature --allow-http-registry "$REF" | jq .
```

Open the Rekor UI at http://localhost:8081 and search for the image digest or
`alice@example.com`. You can also check the log size:

```bash
curl -s http://localhost:3000/api/v1/log | jq '{treeID,treeSize}'
```

Because the bundle contains a Rekor inclusion proof and SET, `cosign verify`
does not need Rekor or Fulcio to be running; it only needs the image and its
bundle from the registry plus the trusted root file.

## 6. Sign another image with a different identity

Create a user in the Keycloak admin console
(http://keycloak.localhost:8080/admin, `admin` / `admin`). Set an email address
and mark it verified, otherwise Fulcio will not accept the identity. Then pass
the credentials to the token helper:

```bash
TOKEN=$(./scripts/token.sh --user bob --password 'bob-password')
./scripts/sign-image.sh --identity-token "$TOKEN" "$REF"

./scripts/verify-image.sh --identity bob@example.com "$REF"
```

Certificates carry the user's email, so use that exact value or a deliberate
regexp.

## 7. Clean up

```bash
make down    # stop containers, keep registry and log data
make reset   # stop and delete all volumes (images, signatures, Rekor entries)
```

After `make reset`, previously signed images and their signatures are gone.
Re-sign with the steps above.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `manifest unknown` on sign/verify | Signed the config digest instead of the manifest digest, or the image was never pushed | Resolve the digest with `skopeo inspect` or use `make seed-registry` |
| `http: server gave HTTP response to HTTPS client` | cosign tried HTTPS against the plain-HTTP registry | Add `--allow-http-registry` (the helpers already do) |
| `401 Unauthorized` or TLS errors on push | Podman tried TLS against `localhost:5001` | Add `--tls-verify=false` to `podman push` |
| `keycloak.localhost` does not resolve | Missing `*.localhost` loopback mapping | Add `127.0.0.1 keycloak.localhost` to `/etc/hosts` |
| `not enough verified log entries ... 0 < 1` | Rekor log key is Ed25519 | Run `make pki && make reset`; the generator must produce ECDSA P-256 |
| Verification fails with an identity error | The certificate identity or issuer does not match | Use `alice@example.com` and the exact `KEYCLOAK_ISSUER` URL |
| Signature exists but verification fails after PKI changes | Trust material and log key were regenerated | `make pki && make reset`, then re-sign |
| `podman-compose` uses a stale image | Container was not recreated | `podman rm -f <container>` then `podman-compose up -d --force-recreate <service>` |

Logs:

```bash
make logs
podman-compose logs rekor-server
podman-compose logs fulcio
```
