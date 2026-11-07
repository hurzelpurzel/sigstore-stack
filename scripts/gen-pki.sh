#!/usr/bin/env bash
#
# Generate the development PKI and the cosign trust material for the local
# Sigstore stack. This is intentionally a development/test CA: the private
# keys live next to the certificates and are not protected beyond the
# passwords in .env.
#
# Usage: ./scripts/gen-pki.sh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  source .env
  set +a
fi

PKI_DIR="${ROOT_DIR}/config/pki"
COSIGN_DIR="${ROOT_DIR}/config/cosign"
FULCIO_PASS="${FULCIO_CA_PASSWORD:-fulcio-dev-password}"
REKOR_PASS="${REKOR_SIGNER_PASSWORD:-rekor-dev-password}"
FULCIO_URL="${FULCIO_URL:-http://localhost:5555}"
REKOR_URL="${REKOR_URL:-http://localhost:3000}"
CTLOG_URL="${CTLOG_URL:-http://localhost:6962}"
KEYCLOAK_ISSUER="${KEYCLOAK_ISSUER:-http://keycloak.localhost:8080/realms/sigstore}"

for bin in openssl; do
  command -v "${bin}" >/dev/null || { echo "missing required command: ${bin}" >&2; exit 1; }
done

mkdir -p "${PKI_DIR}" "${COSIGN_DIR}"
umask 027

echo "==> Fulcio root CA"
# The CA private key is password-encrypted PKCS#8, as required by Fulcio's
# fileca backend.
openssl ecparam -name prime256v1 -genkey -noout -out "${PKI_DIR}/.fulcio-key.plain.pem"
openssl pkcs8 -topk8 -nocrypt -in "${PKI_DIR}/.fulcio-key.plain.pem" -out "${PKI_DIR}/.fulcio-key.nocrypt.pem"
openssl pkcs8 -topk8 -in "${PKI_DIR}/.fulcio-key.plain.pem" \
  -out "${PKI_DIR}/fulcio.key.pem" -passout "pass:${FULCIO_PASS}"
openssl req -x509 -new -key "${PKI_DIR}/.fulcio-key.plain.pem" \
  -out "${PKI_DIR}/fulcio.crt.pem" -sha256 -days 3650 \
  -subj "/O=Sigstore Local/CN=Sigstore Local Fulcio Root CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
rm -f "${PKI_DIR}/.fulcio-key.plain.pem" "${PKI_DIR}/.fulcio-key.nocrypt.pem"

echo "==> Rekor log signing key (ECDSA P-256, encrypted)"
# Rekor v1 SETs are verified with ECDSA in cosign/sigstore-go; an Ed25519 log
# key parses fine but SET verification is then silently skipped.
openssl ecparam -name prime256v1 -genkey -noout -out "${PKI_DIR}/.rekor-key.plain.pem"
openssl pkcs8 -topk8 -in "${PKI_DIR}/.rekor-key.plain.pem" \
  -out "${PKI_DIR}/rekor.key.pem" -passout "pass:${REKOR_PASS}"
openssl ec -in "${PKI_DIR}/.rekor-key.plain.pem" -pubout -out "${PKI_DIR}/rekor.pub.pem" 2>/dev/null
rm -f "${PKI_DIR}/.rekor-key.plain.pem"

echo "==> CT log signing key (ECDSA P-256)"
openssl ecparam -name prime256v1 -genkey -noout -out "${PKI_DIR}/ctlog.key.pem"
openssl ec -in "${PKI_DIR}/ctlog.key.pem" -pubout -out "${PKI_DIR}/ctlog.pub.pem" 2>/dev/null

# Keep the passwords next to the keys so the stack and helper scripts agree.
# DEV ONLY: these are not secrets in any meaningful sense.
printf '%s\n' "${FULCIO_PASS}" > "${PKI_DIR}/fulcio.password"
printf '%s\n' "${REKOR_PASS}" > "${PKI_DIR}/rekor.password"
chmod 644 "${PKI_DIR}"/*.pem "${PKI_DIR}"/*.password

echo "==> cosign trust material"
if command -v cosign >/dev/null 2>&1; then
  cosign trusted-root create \
    --fulcio="url=${FULCIO_URL},certificate-chain=${PKI_DIR}/fulcio.crt.pem,start-time=2020-01-01T00:00:00Z" \
    --rekor="url=${REKOR_URL},public-key=${PKI_DIR}/rekor.pub.pem,start-time=2020-01-01T00:00:00Z" \
    --ctfe="url=${CTLOG_URL},public-key=${PKI_DIR}/ctlog.pub.pem,origin=ctlog,start-time=2020-01-01T00:00:00Z" \
    --no-default-fulcio --no-default-rekor --no-default-ctfe --no-default-tsa \
    --out "${COSIGN_DIR}/trusted-root.json"

  cosign signing-config create \
    --fulcio="url=${FULCIO_URL},api-version=1,start-time=2020-01-01T00:00:00Z,operator=local-sigstore" \
    --rekor="url=${REKOR_URL},api-version=1,start-time=2020-01-01T00:00:00Z,operator=local-sigstore" \
    --oidc-provider="url=${KEYCLOAK_ISSUER},api-version=1,start-time=2020-01-01T00:00:00Z,operator=local-sigstore" \
    --rekor-config=ANY \
    --no-default-fulcio --no-default-rekor --no-default-oidc --no-default-tsa \
    --out "${COSIGN_DIR}/signing-config.json"
else
  echo "WARNING: cosign not found; skipping trusted-root.json and signing-config.json." >&2
  echo "         Install cosign >= 3.0 and rerun this script." >&2
fi

echo
echo "Done. Generated files:"
ls -1 "${PKI_DIR}" "${COSIGN_DIR}"
