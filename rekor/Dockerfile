# Wrap the official Rekor server image so we can persist and reuse the Trillian
# tree ID across restarts. Rekor creates a tree automatically when no
# --trillian_log_server.tlog_id is supplied, but it does not remember the ID
# afterwards. The wrapper reads it back from MySQL before starting Rekor.
FROM ghcr.io/sigstore/rekor/rekor-server:v1.5.5 AS rekor

FROM alpine:3.20

RUN apk add --no-cache mariadb-client mariadb-connector-c

COPY --from=rekor /ko-app/rekor-server /usr/local/bin/rekor-server
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
