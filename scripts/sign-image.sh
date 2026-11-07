#!/usr/bin/env bash
#
# Sign a container image with the local Sigstore stack and upload the Sigstore
# bundle to the registry. Prefer passing an immutable digest reference.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEPENDENCIES=(cosign curl jq)

function usage() {
  cat <<EOM

Sign a container image with the local Sigstore stack (keyless, OIDC via Keycloak).

usage: sign-image.sh [options] <image>

options:
    -i|--identity-token  <token>  OIDC token; if omitted, token.sh is used
    -a|--annotation      k=v      Add an annotation (repeatable)
    -h|--help                     Show this help message

Pass an image digest (repo@sha256:...) rather than a tag where possible.
HTTP is allowed so the bundled localhost:5001 registry works out of the box.

dependencies: ${DEPENDENCIES[*]}

examples:
    sign-image.sh localhost:5001/demo/hello@sha256:...
    sign-image.sh -a env=dev localhost:5001/demo/hello@sha256:...

EOM
  exit "${1:-1}"
}

function main() {
  local image=""
  local token=""
  local -a annotations=()

  while [ "$1" != "" ]; do
    case $1 in
    -i | --identity-token)
      shift
      token="$1"
      ;;
    -a | --annotation)
      shift
      annotations+=("-a" "$1")
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
        printf "Error: only one image may be signed at a time\n" >&2
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

  if [[ -z "${token}" ]]; then
    if ! token=$("${SCRIPT_DIR}/token.sh"); then
      die "could not obtain an identity token"
    fi
  fi

  if ! cosign sign --yes \
    --allow-http-registry \
    --signing-config "${COSIGN_DIR}/signing-config.json" \
    --trusted-root "${COSIGN_DIR}/trusted-root.json" \
    --identity-token "${token}" \
    "${annotations[@]}" \
    "${image}"; then
    die "signing failed"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
