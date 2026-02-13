FROM debian:stable-slim

LABEL maintainer="Alessandro9749"
LABEL description="EventHorizon - Universal archive extractor"

ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies required by EventHorizon for all supported archive formats
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

# Working directory
WORKDIR /event_horizon

# Copy the script
COPY event_horizon.sh /usr/local/bin/event_horizon

# Set execution permission
RUN chmod 755 /usr/local/bin/event_horizon

# Default entrypoint
ENTRYPOINT ["event_horizon"]
