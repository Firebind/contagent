# Stage 1: Extract Sortie binary
FROM ghcr.io/sortie-ai/sortie:latest AS sortie

# Stage 2: Kitchen-sink Ubuntu image
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# --- BUILD ARGUMENTS ---
# ARGs must be declared after FROM in each stage where they're used
ARG USERNAME=sortie
ARG SSH_KEY
ARG SSH_PASSWORD
ARG MAVEN_VERSION=3.9.6
ARG GRADLE_VERSION=8.7
ARG GO_VERSION=1.23.0

# Persist USERNAME as runtime ENV so entrypoint.sh can read it
ENV USERNAME=${USERNAME}

# --- BUILD VALIDATION ---
# Fail early if neither SSH_KEY nor SSH_PASSWORD is provided
RUN if [ -z "$(echo "${SSH_KEY}" | xargs)" ] && [ -z "$(echo "${SSH_PASSWORD}" | xargs)" ]; then \
        echo "-----------------------------------------------------------------------" >&2; \
        echo "ERROR: SSH_KEY or SSH_PASSWORD must be provided as build args." >&2; \
        echo "FIX: In Coolify, check 'Build Variable' for SSH_KEY and/or SSH_PASSWORD." >&2; \
        echo "     On CLI: --build-arg SSH_PASSWORD=yourpassword" >&2; \
        echo "-----------------------------------------------------------------------" >&2; \
        exit 1; \
    fi

# 1. System packages (single layer, sorted for cache stability)
RUN apt-get update && \
    apt-get install -y -o Acquire::Retries=3 -o Acquire::ForceIPv4=true \
        build-essential \
        ca-certificates \
        curl \
        fonts-liberation \
        fonts-noto-color-emoji \
        fonts-roboto \
        git \
        gnupg \
        htop \
        libgbm1 \
        libasound2t64 \
        libnss3 \
        libxss1 \
        net-tools \
        netcat-openbsd \
        nmap \
        openssl \
        openssh-server \
        openssh-client \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        silversearcher-ag \
        sudo \
        supervisor \
        tmux \
        tree \
        unzip \
        vim \
        watchman \
        wget \
        xvfb && \
    rm -rf /var/lib/apt/lists/*

# 2. GitHub CLI (official apt source)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# 3. Node.js 22 (via NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 4. Global npm packages
RUN npm install -g \
        @anthropic-ai/claude-code \
        typescript \
        ts-node \
        expo-cli \
        @expo/cli \
        eas-cli \
        @react-native-community/cli \
        playwright \
        wrangler && \
    npm cache clean --force

# 5. Bun
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/opt/bun bash
ENV BUN_INSTALL=/opt/bun
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
RUN ln -sf /opt/bun/bin/bun /usr/local/bin/bun

# 6. uv + global Python venv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
RUN uv venv /opt/global_venv
ENV VIRTUAL_ENV=/opt/global_venv
ENV PATH="/opt/global_venv/bin:${PATH}"
