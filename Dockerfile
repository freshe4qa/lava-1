# syntax = docker/dockerfile:1.2
# WARNING! Use with `docker buildx ...` or `DOCKER_BUILDKIT=1 docker build ...`
# to enable --mount feature used below.

########################################################################
# Dockerfile for reproducible build of lavad binary and docker image
########################################################################

ARG GO_VERSION="1.18.2"
ARG RUNNER_IMAGE="debian:11-slim"

# --------------------------------------------------------
# Base
# --------------------------------------------------------

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} as base

ARG GIT_VERSION
ARG GIT_COMMIT

# Download debian packages for building
RUN --mount=type=cache,target=/var/cache/apt \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends \
        build-essential \
        ca-certificates \
        curl

# --------------------------------------------------------
# Builder
# --------------------------------------------------------

FROM --platform=$BUILDPLATFORM base as builder

ARG TARGETOS
ARG TARGETARCH

# Download go dependencies
WORKDIR /lava
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go mod download

# Copy the remaining files
COPY . .

# Export our version/commit for the Makefile to know (the .git directory
# is not here, so the Makefile cannot infer them).
ENV BUILD_VERSION=${GIT_VERSION}
ENV BUILD_COMMIT=${GIT_COMMIT}

ENV GOOS=${TARGETOS}
ENV GOARCH=${TARGETARCH}

# Build lavad binary
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    LAVA_BUILD_OPTIONS="static" make -f Makefile build

# --------------------------------------------------------
# Runner
# --------------------------------------------------------

FROM ${RUNNER_IMAGE}

COPY --from=builder /lava/build/lavad /bin/lavad

ENV HOME /lava
WORKDIR $HOME

EXPOSE 26656
EXPOSE 26657
EXPOSE 1317

ENTRYPOINT ["lavad"]
