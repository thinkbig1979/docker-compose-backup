# Test Runner Container for Backup Script Testing
FROM ubuntu:22.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    wget \
    dialog \
    docker.io \
    docker-compose \
    restic \
    rclone \
    jq \
    bats \
    shellcheck \
    netcat \
    procps \
    tree \
    && rm -rf /var/lib/apt/lists/*

# Install bats-core (latest version)
RUN cd /tmp && \
    curl -sSL https://github.com/bats-core/bats-core/archive/v1.10.0.tar.gz | tar xz && \
    cd bats-core-1.10.0 && \
    ./install.sh /usr/local && \
    cd / && rm -rf /tmp/bats-core-1.10.0

# Install bats helper libraries
RUN mkdir -p /opt/bats-helpers && \
    cd /opt/bats-helpers && \
    git clone https://github.com/bats-core/bats-support.git && \
    git clone https://github.com/bats-core/bats-assert.git && \
    git clone https://github.com/bats-core/bats-file.git

# Set up test environment
ENV BATS_LIB_PATH=/opt/bats-helpers
ENV PATH="/usr/local/bin:$PATH"

# Create test directories
RUN mkdir -p /test-results /test-fixtures

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]