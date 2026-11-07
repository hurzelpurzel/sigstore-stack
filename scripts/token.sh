#!/usr/bin/env bash
#
# Obtain an OIDC access token from the local Keycloak realm using the demo
# user's password grant. The token is printed to stdout so it can be used as
# `cosign ... --identity-token "$(scripts/token.sh)"`.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEPENDENCIES=(curl jq)

function usage() {
  cat <<EOM

Obtain an OIDC access token from the Keycloak realm used by this stack.

usage: token.sh [options]

options:
    -r|--realm     <realm>     Keycloak realm (default: ${KEYCLOAK_REALM:-sigstore})
    -u|--user      <user>      Demo username (default: ${KEYCLOAK_DEMO_USER:-alice})
    -p|--password  <password>  Demo password (default: ${KEYCLOAK_DEMO_PASSWORD:-alice})
    -c|--client    <client>    OIDC client ID (default: sigstore)
    -h|--help                  Show this help message

The token is written to stdout; diagnostics go to stderr.

dependencies: ${DEPENDENCIES[*]}

examples:
    token.sh
    token.sh --user alice --password alice

EOM
  exit "${1:-1}"
}

function main() {
  local realm="${KEYCLOAK_REALM:-sigstore}"
  local user="${KEYCLOAK_DEMO_USER:-alice}"
  local password="${KEYCLOAK_DEMO_PASSWORD:-alice}"
  local client="sigstore"

  while [ "$1" != "" ]; do
    case $1 in
    -r | --realm)
      shift
      realm="$1"
      ;;
    -u | --user)
      shift
      user="$1"
      ;;
    -p | --password)
      shift
      password="$1"
      ;;
    -c | --client)
      shift
      client="$1"
      ;;
    -h | --help)
      usage 0
      ;;
    *)
      printf "Error: unknown option '%s'\n" "$1" >&2
      usage
      ;;
    esac
    shift
  done

  load_env
  require_tools "${DEPENDENCIES[@]}"

  local issuer="${KEYCLOAK_ISSUER:-http://keycloak.localhost:8080/realms/${realm}}"
  local response token error

  if ! response=$(curl -sS -X POST "${issuer}/protocol/openid-connect/token" \
    -d grant_type=password \
    -d "client_id=${client}" \
    -d "username=${user}" \
    -d "password=${password}" \
    -d 'scope=openid email profile'); then
    die "could not reach Keycloak at ${issuer}"
  fi

  token=$(jq -r '.access_token // empty' <<<"${response}")
  if [[ -z "${token}" ]]; then
    error=$(jq -r '.error_description // .error // "unknown error"' <<<"${response}")
    die "token request failed: ${error}"
  fi

  printf '%s\n' "${token}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
