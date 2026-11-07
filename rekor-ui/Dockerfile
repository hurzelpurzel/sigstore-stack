# Build the Rekor search UI (https://github.com/sigstore/rekor-search-ui) as a
# static Next.js export and serve it with nginx. There is no upstream image, so
# the source is pinned to a known commit.
FROM node:22-alpine AS build

ARG REKOR_UI_REPO=https://github.com/sigstore/rekor-search-ui.git
ARG REKOR_UI_REF=29c5468e979bdf557aab423577c8f0c087e8cb02
ARG REKOR_UI_DEFAULT_DOMAIN=http://localhost:3000

RUN apk add --no-cache git

WORKDIR /src
RUN git clone "${REKOR_UI_REPO}" . \
 && git checkout "${REKOR_UI_REF}"

# @peculiar/x509 1.14.3 moved the SAN JSON representation onto GeneralNames.
COPY 0001-build-fixes.patch /tmp/
RUN git apply /tmp/0001-build-fixes.patch

RUN npm ci --no-audit --no-fund

ENV NEXT_PUBLIC_REKOR_DEFAULT_DOMAIN=${REKOR_UI_DEFAULT_DOMAIN}
RUN npm run build

FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/out /usr/share/nginx/html

EXPOSE 80
