#!/usr/bin/env bash
#
# Build and push a tiny demo image to the local registry, then print the
# immutable image reference (repo@sha256:...) on stdout for signing.

set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

DEPENDENCIES=(curl)

function usage() {
  cat <<EOM

Build and push a tiny demo image to the local registry.

usage: seed-registry.sh [options]

options:
    -r|--repository <name>  Repository name (default: demo/hello)
    -t|--tag        <tag>   Image tag (default: v1)
    -h|--help               Show this help message

The immutable image reference is printed to stdout as IMAGE=<repo>@<digest>.
Progress messages go to stderr.

dependencies: ${DEPENDENCIES[*]} plus podman or docker

examples:
    seed-registry.sh
    seed-registry.sh --repository demo/example --tag v2

EOM
  exit "${1:-1}"
}

function detect_engine() {
  if command -v podman >/dev/null 2>&1; then
    ENGINE=podman
    PUSH_ARGS=(--tls-verify=false)
  elif command -v docker >/dev/null 2>&1; then
    ENGINE=docker
    PUSH_ARGS=()
  else
    die "podman or docker is required"
  fi
}

function main() {
  local repository="demo/hello"
  local tag="v1"

  while [ "$1" != "" ]; do
    case $1 in
    -r | --repository)
      shift
      repository="$1"
      ;;
    -t | --tag)
      shift
      tag="$1"
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
  detect_engine

  local registry="${REGISTRY:-localhost:5001}"
  registry="${registry#http://}"
  registry="${registry#https://}"
  registry="${registry%/}"
  local ref="${registry}/${repository}:${tag}"
  local workdir
  workdir=$(mktemp -d)
  trap 'rm -rf "${workdir}"' EXIT

  printf 'Building %s with %s...\n' "${ref}" "${ENGINE}" >&2
  printf 'hello from the local Sigstore stack\n' > "${workdir}/hello.txt"
  cat > "${workdir}/Dockerfile" <<'DOCKERFILE'
FROM scratch
COPY hello.txt /hello.txt
DOCKERFILE

  if ! "${ENGINE}" build -t "${ref}" "${workdir}" 1>&2; then
    die "image build failed"
  fi

  printf 'Pushing %s...\n' "${ref}" >&2
  if ! "${ENGINE}" push "${PUSH_ARGS[@]}" "${ref}" 1>&2; then
    die "image push failed"
  fi

  local headers digest
  if ! headers=$(curl -fsSI \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    "http://${registry}/v2/${repository}/manifests/${tag}"); then
    die "could not query the registry for the manifest digest"
  fi

  digest=$(printf '%s\n' "${headers}" | tr -d '\r' \
    | grep -i '^docker-content-digest:' | awk '{print $2}' | tail -n 1)
  [[ -n "${digest}" ]] || die "registry did not return a Docker-Content-Digest header"

  printf 'IMAGE=%s/%s@%s\n' "${registry}" "${repository}" "${digest}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit 0
fi
