FROM debian:stable-slim

LABEL maintainer="Alessandro9749"
LABEL description="EventHorizon - Universal archive extractor"

ENV DEBIAN_FRONTEND=noninteractive

# Install only the bare minimum needed to run the script
RUN apt update && apt install -y \
    bash \
    ca-certificates \
    apt \
    && rm -rf /var/lib/apt/lists/*

# Working directory
WORKDIR /event_horizon

# Copy the script
COPY event_horizon.sh /usr/local/bin/event_horizon

# Set execution permission
RUN chmod 755 /usr/local/bin/event_horizon

# Default entrypoint
ENTRYPOINT ["event_horizon"]
