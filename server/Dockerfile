# OpenWord API: one static Go binary in a small Alpine image.
#
# Builds for linux/arm64 (Raspberry Pi 4) and linux/amd64 with no cgo, so a
# multi-arch image needs nothing beyond buildx:
#
#   docker buildx build --platform linux/arm64,linux/amd64 \
#     -t you/openword-api:latest --push server
#
# Run from the server/ directory (the context is this directory).

ARG GO_VERSION=1.24
ARG ALPINE_VERSION=3.20

# --- build -------------------------------------------------------------------
# The build stage runs on the host's native platform and cross-compiles for
# the target, which keeps a Pi build from crawling under emulation.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS build
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src

# Dependencies first so editing code does not re-download modules.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/openword-api ./cmd/openword-api

# --- runtime -----------------------------------------------------------------
# Alpine rather than distroless so compose can HEALTHCHECK with wget.
# ca-certificates: the push service endpoints are HTTPS.
# tzdata: reminder times are evaluated in each user's IANA zone.
FROM alpine:${ALPINE_VERSION}
RUN apk add --no-cache ca-certificates tzdata wget \
    && addgroup -S openword && adduser -S -G openword -H openword

COPY --from=build /out/openword-api /usr/local/bin/openword-api

USER openword
EXPOSE 8080
ENV LISTEN=:8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/openword-api"]
