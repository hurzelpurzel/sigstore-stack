#!/usr/bin/env bash
# Shared helpers for the Sigstore stack scripts. This file is sourced, not run.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
COSIGN_DIR="${ROOT_DIR}/config/cosign"

load_env() {
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/.env"
    set +a
  fi
}

require_tools() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      printf "Error: required tool '%s' is not installed or not in PATH\n" "${cmd}" >&2
      exit 1
    fi
  done
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Fail early with an actionable message when the local trust material has not
# been generated yet. Signs/verifies must never silently regenerate keys while
# a stack is running; that would rotate the log key out from under it.
require_trust_material() {
  local file
  for file in "${COSIGN_DIR}/trusted-root.json" "${COSIGN_DIR}/signing-config.json"; do
    if [[ ! -f "${file}" ]]; then
      die "missing ${file#"${ROOT_DIR}/"}; run 'make up' or 'make pki' first"
    fi
  done
}
