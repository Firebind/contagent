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

# 7. Go (architecture-aware download)
RUN ARCH=$(dpkg --print-architecture) && \
    wget -qO /tmp/go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# 8. Java — Amazon Corretto 21
RUN wget -qO - https://apt.corretto.aws/corretto.key \
        | gpg --dearmor -o /usr/share/keyrings/corretto-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/corretto-keyring.gpg] https://apt.corretto.aws stable main" \
        | tee /etc/apt/sources.list.d/corretto.list && \
    apt-get update && \
    apt-get install -y java-21-amazon-corretto-jdk && \
    rm -rf /var/lib/apt/lists/*
# Resolve JAVA_HOME dynamically (handles amd64 and arm64)
RUN JAVA_BIN=$(readlink -f "$(which java)") && \
    echo "export JAVA_HOME=$(dirname $(dirname ${JAVA_BIN}))" >> /etc/environment
ENV JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto

# 9. Maven
RUN wget -qO /tmp/maven.tar.gz \
        "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" && \
    tar -xzf /tmp/maven.tar.gz -C /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven && \
    rm /tmp/maven.tar.gz
ENV M2_HOME=/opt/maven

# 10. Gradle
RUN wget -qO /tmp/gradle.zip \
        "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" && \
    unzip -q /tmp/gradle.zip -d /opt && \
    ln -s /opt/gradle-${GRADLE_VERSION} /opt/gradle && \
    rm /tmp/gradle.zip
ENV GRADLE_HOME=/opt/gradle

ENV PATH="${JAVA_HOME}/bin:${M2_HOME}/bin:${GRADLE_HOME}/bin:${PATH}"

# 11. Android SDK cmdline-tools
ENV ANDROID_HOME=/opt/android-sdk
RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" && \
    wget -qO /tmp/tools.zip \
        https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
    unzip -q /tmp/tools.zip -d "${ANDROID_HOME}/cmdline-tools" && \
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" && \
    rm /tmp/tools.zip
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# 12. Create non-root user (UID 1000 — required by Sortie)
# Ubuntu 24.04 ships a built-in 'ubuntu' user at UID 1000; remove it first.
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd --create-home --shell /bin/bash --uid 1000 "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 13. Playwright + Chromium (after user creation so chown works)
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
RUN playwright install --with-deps chromium && \
    chown -R "${USERNAME}:${USERNAME}" "${PLAYWRIGHT_BROWSERS_PATH}"
ENV DISPLAY=:99
ENV SCREEN_WIDTH=1280
ENV SCREEN_HEIGHT=720
RUN printf '#!/bin/bash\nXvfb :99 -screen 0 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}x24 &\n' \
        > /usr/local/bin/start-xvfb && \
    chmod +x /usr/local/bin/start-xvfb

# Fix ownership for directories the user needs to write to
RUN chown -R "${USERNAME}:${USERNAME}" /opt/global_venv

# 14. SSH server configuration
RUN mkdir -p /var/run/sshd
# Store SSH_KEY for entrypoint to install after any volume mount
RUN if [ -n "${SSH_KEY}" ]; then \
        printf '%s\n' "${SSH_KEY}" > /etc/ssh/authorized_keys.provision && \
        chmod 600 /etc/ssh/authorized_keys.provision; \
    fi
RUN if [ -n "${SSH_PASSWORD}" ]; then \
        echo "${USERNAME}:${SSH_PASSWORD}" | chpasswd; \
    fi
RUN sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#Port 22/Port 8022/' /etc/ssh/sshd_config && \
    if [ -n "${SSH_PASSWORD}" ]; then \
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config; \
    else \
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config; \
    fi

# 15. supervisord config
# Using <<EOF (unquoted) so ${USERNAME} is expanded from ARG at build time,
# baking the username string into the config file.
RUN mkdir -p /var/log/supervisor && \
    cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
loglevel=info
user=root

[program:sshd]
command=/usr/sbin/sshd -D
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/sshd.stdout.log
stderr_logfile=/var/log/supervisor/sshd.stderr.log

[program:sortie]
command=/usr/bin/sortie --host 0.0.0.0
user=${USERNAME}
autostart=true
autorestart=true
priority=20
stdout_logfile=/var/log/supervisor/sortie.stdout.log
stderr_logfile=/var/log/supervisor/sortie.stderr.log
EOF
