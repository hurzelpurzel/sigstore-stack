#!/usr/bin/env bash
#
# Sign a file (a blob) with cosign using the local Fulcio, Rekor and Keycloak
# deployment. Produces a Sigstore bundle next to the file by default.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEPENDENCIES=(cosign curl jq)

function usage() {
  cat <<EOM

Sign a file with the local Sigstore stack (keyless, OIDC via Keycloak).

usage: sign-blob.sh [options] <file>

options:
    -b|--bundle          <file>  Bundle output path (default: <file>.sigstore.json)
    -i|--identity-token  <token> OIDC token; if omitted, token.sh is used
    -h|--help                    Show this help message

dependencies: ${DEPENDENCIES[*]}

examples:
    sign-blob.sh ./release.tar.gz
    sign-blob.sh --bundle ./release.bundle ./release.tar.gz

EOM
  exit "${1:-1}"
}

function main() {
  local file=""
  local bundle=""
  local token=""

  while [ "$1" != "" ]; do
    case $1 in
    -b | --bundle)
      shift
      bundle="$1"
      ;;
    -i | --identity-token)
      shift
      token="$1"
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
        printf "Error: only one file may be signed at a time\n" >&2
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
  require_trust_material

  [[ -f "${file}" ]] || die "file not found: ${file}"
  bundle="${bundle:-${file}.sigstore.json}"

  if [[ -z "${token}" ]]; then
    if ! token=$("${SCRIPT_DIR}/token.sh"); then
      die "could not obtain an identity token"
    fi
  fi

  if ! cosign sign-blob --yes \
    --signing-config "${COSIGN_DIR}/signing-config.json" \
    --trusted-root "${COSIGN_DIR}/trusted-root.json" \
    --bundle "${bundle}" \
    --identity-token "${token}" \
    "${file}"; then
    die "signing failed"
  fi

  printf 'Bundle written to %s\n' "${bundle}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
