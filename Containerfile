# Containerfile - Apple Container image for Claude Code sandbox
#
# This creates a minimal Linux environment for running Claude Code
# with strong VM-based isolation on macOS using Apple's Container framework.
#
# Build:
#   container build -t claude-sandbox .
#
# The resulting image contains:
#   - Minimal Debian base
#   - Node.js 20 LTS
#   - Claude Code CLI
#   - Non-root user matching typical macOS UID
#

# Use minimal Debian as base
FROM debian:bookworm-slim

# Avoid interactive prompts during build
ARG DEBIAN_FRONTEND=noninteractive

# Arguments for customizing the build
ARG NODE_VERSION=20
ARG HOST_UID=501
ARG HOST_GID=20
ARG USERNAME=claude

# Install essential packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    ca-certificates \
    curl \
    git \
    openssh-client \
    # Build tools (some npm packages need these)
    build-essential \
    python3 \
    # Locales
    locales \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install Node.js via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

# Create non-root user with UID matching macOS default
# This ensures file permissions work correctly with bind mounts
RUN groupadd -g ${HOST_GID} ${USERNAME} 2>/dev/null || true \
    && useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/bash ${USERNAME}

# Create directories that will be used for mounts
RUN mkdir -p /workspace \
    && mkdir -p /home/${USERNAME}/.claude \
    && mkdir -p /home/${USERNAME}/.ssh \
    && mkdir -p /home/${USERNAME}/.npm \
    && chown -R ${USERNAME}:${HOST_GID} /workspace /home/${USERNAME}

# Set up SSH directory permissions
RUN chmod 700 /home/${USERNAME}/.ssh

# Switch to non-root user
USER ${USERNAME}

# Configure git to trust the workspace directory
# (needed because it's a bind mount with potentially different ownership)
RUN git config --global --add safe.directory /workspace

# Default working directory
WORKDIR /workspace

# Health check - verify Claude is available
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD claude --version || exit 1

# Default entrypoint is Claude
ENTRYPOINT ["claude"]

# Default to interactive mode (can be overridden)
CMD []
