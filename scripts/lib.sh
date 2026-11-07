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
