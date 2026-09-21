# OpenWord on a Raspberry Pi, from a published release.
#
# The web bundle is static files and nothing else, so this image is
# architecture-free: the only thing that has to match the Pi is nginx, and
# that comes multi-arch. Nothing here needs Flutter, which matters because
# Flutter publishes no arm64 Linux SDK — see Dockerfile.source.
#
#   docker build -t openword:1.10.0 --build-arg VERSION=v1.10.0 -f deploy/Dockerfile deploy

ARG NGINX_VERSION=1.27-alpine

FROM alpine:3.20 AS fetch
ARG VERSION=v1.10.0
ARG REPO=tahuffman1s/OpenWord
# The published SHA-256 of the zip, if you want the build to refuse a
# tampered or truncated download. Leave empty to skip the check.
ARG SHA256=

RUN apk add --no-cache curl unzip
WORKDIR /src
RUN set -eux; \
    url="https://github.com/${REPO}/releases/download/${VERSION}/OpenWord-${VERSION}-web.zip"; \
    curl -fsSL "$url" -o web.zip; \
    if [ -n "$SHA256" ]; then echo "$SHA256  web.zip" | sha256sum -c -; fi; \
    mkdir -p /web && unzip -q web.zip -d /web; \
    test -f /web/index.html

# Pre-compress what compresses, so the Pi spends no CPU on it per request and
# the tunnel carries a third of the bytes. Files that are already compressed
# — the .bib translations, originals.ows.gz, xrefs.owx.gz — are deliberately
# left alone: nginx must serve those as opaque bytes for the app to unpack
# itself.
RUN find /web -type f \( \
        -name '*.js'   -o -name '*.wasm'  -o -name '*.json' -o \
        -name '*.html' -o -name '*.css'   -o -name '*.ttf'  -o \
        -name '*.otf'  -o -name '*.symbols' \) \
        -exec gzip -9 -k -f {} \;

FROM nginx:${NGINX_VERSION}
# .ttf and .otf are absent from nginx's table. They have to be appended to
# the map rather than declared in a types{} block in the server config: such
# a block replaces the inherited map instead of extending it, and index.html
# and canvaskit.wasm would lose their own types.
RUN sed -i 's#^\( *\)font/woff  *woff;#\1font/ttf     ttf;\n\1font/otf     otf;\n&#' \
        /etc/nginx/mime.types \
    && grep -q 'font/ttf' /etc/nginx/mime.types

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=fetch /web /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1/healthz >/dev/null 2>&1 || exit 1
