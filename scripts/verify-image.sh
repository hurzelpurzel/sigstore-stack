#!/usr/bin/env bash
#
# Verify a container image signature produced by this stack.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEPENDENCIES=(cosign)

function usage() {
  cat <<EOM

Verify a container image signed by this Sigstore stack.

usage: verify-image.sh [options] <image>

options:
    -i|--identity   <email>  Certificate identity (default: ${CERTIFICATE_IDENTITY:-alice@example.com})
    -s|--issuer     <url>    OIDC issuer (default: ${KEYCLOAK_ISSUER:-http://keycloak.localhost:8080/realms/sigstore})
    -h|--help                Show this help message

dependencies: ${DEPENDENCIES[*]}

examples:
    verify-image.sh localhost:5001/demo/hello@sha256:...

EOM
  exit "${1:-1}"
}

function main() {
  local image=""
  local identity="${CERTIFICATE_IDENTITY:-alice@example.com}"
  local issuer="${KEYCLOAK_ISSUER:-http://keycloak.localhost:8080/realms/sigstore}"

  while [ "$1" != "" ]; do
    case $1 in
    -i | --identity)
      shift
      identity="$1"
      ;;
    -s | --issuer)
      shift
      issuer="$1"
      ;;
    -h | --help)
      usage 0
      ;;
    -*)
      printf "Error: unknown option '%s'\n" "$1" >&2
      usage
      ;;
    *)
      if [[ -n "${image}" ]]; then
        printf "Error: only one image may be verified at a time\n" >&2
        usage
      fi
      image="$1"
      ;;
    esac
    shift
  done

  [[ -n "${image}" ]] || { printf 'Error: an image argument is required\n' >&2; usage; }

  load_env
  require_tools "${DEPENDENCIES[@]}"
  require_trust_material

  cosign verify \
    --allow-http-registry \
    --trusted-root "${COSIGN_DIR}/trusted-root.json" \
    --certificate-identity "${identity}" \
    --certificate-oidc-issuer "${issuer}" \
    "${image}" || die "verification failed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
