# EventHorizon Dockerfile
# Choose base image: debian or arch
# For Arch-based, use: docker build --build-arg BASE_IMAGE=archlinux -t event_horizon .

ARG BASE_IMAGE=debian
FROM ${BASE_IMAGE}:stable-slim AS base-debian
FROM ${BASE_IMAGE}:latest AS base-arch

# Debian stage
FROM base-debian AS debian-build
LABEL maintainer="Alessandro9749"
LABEL description="EventHorizon - Universal archive extractor (Debian)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    file \
    unzip \
    p7zip-full \
    tar \
    gzip \
    bzip2 \
    xz-utils \
    zstd \
    lz4 \
    wimtools \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /event_horizon
COPY event_horizon.sh /usr/local/bin/event_horizon
RUN chmod 755 /usr/local/bin/event_horizon
ENTRYPOINT ["event_horizon"]

# Arch Linux stage
FROM base-arch AS arch-build
LABEL maintainer="Alessandro9749"
LABEL description="EventHorizon - Universal archive extractor (Arch Linux)"

RUN pacman -Sy --noconfirm \
    bash \
    ca-certificates \
    file \
    unzip \
    p7zip \
    tar \
    gzip \
    bzip2 \
    xz \
    zstd \
    lz4 \
    wimlib \
    && rm -rf /var/cache/pacman/pkg/*

WORKDIR /event_horizon
COPY event_horizon.sh /usr/local/bin/event_horizon
RUN chmod 755 /usr/local/bin/event_horizon
ENTRYPOINT ["event_horizon"]

# Default to debian
FROM debian-build
