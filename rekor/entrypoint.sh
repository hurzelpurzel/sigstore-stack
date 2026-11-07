#!/bin/sh
#
# Wait for dependencies, discover the Trillian tree that Rekor previously
# created, and start the server with that tree ID. On the very first start the
# tree does not exist yet; Rekor is started without a tlog_id and creates one.
set -eu

DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-sigstore}"
DB_USER="${DB_USER:-sigstore}"
DB_PASSWORD="${DB_PASSWORD:-}"
TRILLIAN_HOST="${TRILLIAN_HOST:-trillian-log-server}"
TRILLIAN_PORT="${TRILLIAN_PORT:-8090}"

log() {
  printf '%s rekor-entrypoint: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

maria() {
  mariadb --skip-ssl --protocol=tcp \
    -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" "$@"
}

log "waiting for MySQL at ${DB_HOST}:${DB_PORT}"
until mariadb-admin --skip-ssl --protocol=tcp \
  -h "${DB_HOST}" -P "${DB_PORT}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
  --silent ping >/dev/null 2>&1; do
  sleep 2
done

log "waiting for Trillian at ${TRILLIAN_HOST}:${TRILLIAN_PORT}"
until nc -z -w 2 "${TRILLIAN_HOST}" "${TRILLIAN_PORT}" >/dev/null 2>&1; do
  sleep 2
done

log "waiting for the Trillian schema to be created"
until maria -N -B -e 'SELECT 1 FROM Trees LIMIT 1' "${DB_NAME}" >/dev/null 2>&1; do
  sleep 2
done

TREE_ID=$(maria -N -B -e 'SELECT COALESCE(MAX(TreeId), 0) FROM Trees' "${DB_NAME}" | tr -d '[:space:]')
TREE_ID=${TREE_ID:-0}

if [ "${TREE_ID}" != "0" ]; then
  log "using existing Trillian tree ${TREE_ID}"
  set -- serve --trillian_log_server.tlog_id="${TREE_ID}" "$@"
else
  log "no Trillian tree found; Rekor will create one on startup"
  set -- serve "$@"
fi

exec /usr/local/bin/rekor-server "$@"
