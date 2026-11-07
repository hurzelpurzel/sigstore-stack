#!/usr/bin/env bash
#
# Verify a blob signature bundle produced by this stack. Uses the committed
# development trust root, so no network access to TUF is required.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEPENDENCIES=(cosign)

function usage() {
  cat <<EOM

Verify a blob with a Sigstore bundle and the local trusted root.

usage: verify-blob.sh [options] <file>

options:
    -b|--bundle     <file>  Bundle path (default: <file>.sigstore.json)
    -i|--identity   <email> Certificate identity (default: ${CERTIFICATE_IDENTITY:-alice@example.com})
    -s|--issuer     <url>   OIDC issuer (default: ${KEYCLOAK_ISSUER:-http://keycloak.localhost:8080/realms/sigstore})
    -h|--help               Show this help message

dependencies: ${DEPENDENCIES[*]}

examples:
    verify-blob.sh ./release.tar.gz
    verify-blob.sh --bundle ./release.bundle ./release.tar.gz

EOM
  exit "${1:-1}"
}

function main() {
  local file=""
  local bundle=""
  local identity="${CERTIFICATE_IDENTITY:-alice@example.com}"
  local issuer="${KEYCLOAK_ISSUER:-http://keycloak.localhost:8080/realms/sigstore}"

  while [ "$1" != "" ]; do
    case $1 in
    -b | --bundle)
      shift
      bundle="$1"
      ;;
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
      if [[ -n "${file}" ]]; then
        printf "Error: only one file may be verified at a time\n" >&2
        usage
      fi
      file="$1"
      ;;
    esac
    shift
  done

  [[ -n "${file}" ]] || { printf 'Error: a file argument is required\n' >&2; usage; }

  load_env
  require_tools "${DEPENDENCIES[@]}"

  [[ -f "${file}" ]] || die "file not found: ${file}"
  bundle="${bundle:-${file}.sigstore.json}"
  [[ -f "${bundle}" ]] || die "bundle not found: ${bundle}"

  cosign verify-blob \
    --bundle "${bundle}" \
    --trusted-root "${COSIGN_DIR}/trusted-root.json" \
    --certificate-identity "${identity}" \
    --certificate-oidc-issuer "${issuer}" \
    "${file}" || die "verification failed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
