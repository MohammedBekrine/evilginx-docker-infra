# ---- Stage 1: Build Evilginx from source ----
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git make

ARG EVILGINX_REPO=https://github.com/kgretzky/evilginx2.git
ARG EVILGINX_BRANCH=master

RUN git clone --depth 1 --branch ${EVILGINX_BRANCH} ${EVILGINX_REPO} /src/evilginx

WORKDIR /src/evilginx
# evilginx2 has main.go at the repo root and ships a Makefile
RUN make && mkdir -p /out && cp ./build/evilginx /out/evilginx

# ---- Stage 2: Minimal runtime image ----
FROM alpine:3.19

RUN apk add --no-cache bash ca-certificates gettext

COPY --from=builder /out/evilginx /usr/local/bin/evilginx
RUN chmod +x /usr/local/bin/evilginx

# Create working directories
RUN mkdir -p /app/phishlets /app/phishlets-default /app/redirectors /root/.evilginx

# Bake in upstream evilginx2's shipped phishlets (only example.yaml in v3.3.0).
# Kept at a separate path because /app/phishlets is bind-mounted by compose.
COPY --from=builder /src/evilginx/phishlets/ /app/phishlets-default/

COPY scripts/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Local custom phishlets baked in for `docker run` use. In compose, this
# path is overlaid by the ./config/phishlets bind mount.
COPY config/phishlets/ /app/phishlets/

WORKDIR /app

EXPOSE 53/udp 80/tcp 443/tcp

ENTRYPOINT ["/app/entrypoint.sh"]
