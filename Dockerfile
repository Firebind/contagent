FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# --- BUILD ARGUMENTS ---
# ARGs must be declared after FROM in each stage where they're used
ARG USERNAME=jay
ARG SSH_KEY
ARG SSH_PASSWORD
ARG MAVEN_VERSION=3.9.6
ARG GRADLE_VERSION=8.7
ARG GO_VERSION=1.23.0
ARG GITHUB_REPO_2
ARG INSTALL_ANDROID_SDK=false

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

# 1. System packages — add all third-party apt sources first, then single update + install
RUN \
    # GitHub CLI apt source
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    # Amazon Corretto 21 apt source
    wget -qO - https://apt.corretto.aws/corretto.key \
        | gpg --dearmor -o /usr/share/keyrings/corretto-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/corretto-keyring.gpg] https://apt.corretto.aws stable main" \
        | tee /etc/apt/sources.list.d/corretto.list && \
    apt-get update && \
    apt-get install -y -o Acquire::Retries=3 -o Acquire::ForceIPv4=true \
        build-essential \
        ca-certificates \
        curl \
        fonts-liberation \
        fonts-noto-color-emoji \
        fonts-roboto \
        gh \
        git \
        gnupg \
        htop \
        java-21-amazon-corretto-jdk \
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

# 2. Node.js 22 (via NodeSource — runs its own apt-get update internally)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# 3. Global npm packages
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

# 4. Bun
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/opt/bun bash
ENV BUN_INSTALL=/opt/bun
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
RUN ln -sf /opt/bun/bin/bun /usr/local/bin/bun

# 5. uv + global Python venv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
RUN uv venv /opt/global_venv
ENV VIRTUAL_ENV=/opt/global_venv
ENV PATH="/opt/global_venv/bin:${PATH}"

# 6. Go (architecture-aware download)
RUN ARCH=$(dpkg --print-architecture) && \
    wget -qO /tmp/go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# 7. Java — resolve JAVA_HOME dynamically (handles amd64 and arm64)
RUN JAVA_BIN=$(readlink -f "$(which java)") && \
    echo "export JAVA_HOME=$(dirname $(dirname ${JAVA_BIN}))" >> /etc/environment
ENV JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto

# 8. Maven
RUN wget -qO /tmp/maven.tar.gz \
        "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" && \
    tar -xzf /tmp/maven.tar.gz -C /opt && \
    ln -s /opt/apache-maven-${MAVEN_VERSION} /opt/maven && \
    rm /tmp/maven.tar.gz
ENV M2_HOME=/opt/maven

# 9. Gradle
RUN wget -qO /tmp/gradle.zip \
        "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" && \
    unzip -q /tmp/gradle.zip -d /opt && \
    ln -s /opt/gradle-${GRADLE_VERSION} /opt/gradle && \
    rm /tmp/gradle.zip
ENV GRADLE_HOME=/opt/gradle

ENV PATH="${JAVA_HOME}/bin:${M2_HOME}/bin:${GRADLE_HOME}/bin:${PATH}"

# 10. Android SDK cmdline-tools (optional — pass --build-arg INSTALL_ANDROID_SDK=true to include)
ENV ANDROID_HOME=/opt/android-sdk
RUN if [ "${INSTALL_ANDROID_SDK}" = "true" ]; then \
        mkdir -p "${ANDROID_HOME}/cmdline-tools" && \
        wget -qO /tmp/tools.zip \
            https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip && \
        unzip -q /tmp/tools.zip -d "${ANDROID_HOME}/cmdline-tools" && \
        mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest" && \
        rm /tmp/tools.zip; \
    fi
ENV PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
RUN if [ "${INSTALL_ANDROID_SDK}" = "true" ]; then \
        yes | sdkmanager --licenses && \
        sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"; \
    fi

# 11. Create non-root user (UID 1000 — required)
# Ubuntu 24.04 ships a built-in 'ubuntu' user at UID 1000; remove it first.
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd --create-home --shell /bin/bash --uid 1000 "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 12. Worker script (placed early so downstream layer changes don't bust this cache)
COPY claude_worker.py /home/${USERNAME}/

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
# Using <<EOF (unquoted) to expand ${USERNAME} from ARG at build time.
# ANTHROPIC_API_KEY is NOT baked in — uses %(ENV_ANTHROPIC_API_KEY)s, read from
# supervisord's inherited process environment (exported by entrypoint.sh at runtime).
RUN mkdir -p /var/log/supervisor && \
    cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
loglevel=info
user=root

[program:sshd]
command=/usr/sbin/sshd -D
user=root
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/sshd.stdout.log
stderr_logfile=/var/log/supervisor/sshd.stderr.log

[program:claude-worker]
command=/usr/bin/python3 /home/${USERNAME}/claude_worker.py
directory=/home/${USERNAME}
user=${USERNAME}
autostart=true
autorestart=true
priority=20
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=PATH="/usr/local/bin:/usr/bin:%(ENV_PATH)s",ANTHROPIC_API_KEY="%(ENV_ANTHROPIC_API_KEY)s",HOME=/home/${USERNAME},ANTHROPIC_MODEL=claude-sonnet-4-6
EOF

# 16. Entrypoint provisioning script
# <<'ENTRYPOINT_EOF' (quoted) — variables inside are NOT expanded at build time.
# They are read from the container's runtime environment when the script executes.
RUN cat > /usr/local/bin/entrypoint.sh <<'ENTRYPOINT_EOF'
#!/bin/bash
set -e

# Provision SSH authorized_keys after any volume mount
if [ -f /etc/ssh/authorized_keys.provision ]; then
    mkdir -p "/home/${USERNAME}/.ssh"
    cp /etc/ssh/authorized_keys.provision "/home/${USERNAME}/.ssh/authorized_keys"
    chmod 700 "/home/${USERNAME}/.ssh"
    chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"
fi

# Create required working directories
mkdir -p "/home/${USERNAME}/screenshots"
mkdir -p "/home/${USERNAME}/workspaces"

# Write runtime credentials to a dedicated env file.
# Written fresh on every start so Coolify env var changes take effect on redeploy.
# /etc/bash.bashrc sources this file (wired up in the next Dockerfile step).
cat > /etc/contagent-env.sh <<ENVEOF
export ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
export GITHUB_TOKEN=${GITHUB_TOKEN}
export GITHUB_ORG=${GITHUB_ORG}
export GITHUB_REPO=${GITHUB_REPO}
export GITHUB_REPO_2=${GITHUB_REPO_2}
export EXPO_TOKEN=${EXPO_TOKEN}
export CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
export CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}
ENVEOF
chmod 644 /etc/contagent-env.sh

# Authenticate GitHub CLI as the non-root user
if [ -n "${GITHUB_TOKEN}" ]; then
    echo "${GITHUB_TOKEN}" | su - "${USERNAME}" -c "gh auth login --with-token" || true
fi

# Clone primary repo if not already present
if [ -n "${GITHUB_TOKEN}" ] && [ -n "${GITHUB_ORG}" ] && [ -n "${GITHUB_REPO}" ]; then
    if [ ! -d "/home/${USERNAME}/${GITHUB_REPO}/.git" ]; then
        su - "${USERNAME}" -c "git clone 'https://${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${GITHUB_REPO}.git' '/home/${USERNAME}/${GITHUB_REPO}'" || true
    fi
fi

# Clone secondary repo if defined
if [ -n "${GITHUB_TOKEN}" ] && [ -n "${GITHUB_ORG}" ] && [ -n "${GITHUB_REPO_2}" ]; then
    if [ ! -d "/home/${USERNAME}/${GITHUB_REPO_2}/.git" ]; then
        su - "${USERNAME}" -c "git clone 'https://${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${GITHUB_REPO_2}.git' '/home/${USERNAME}/${GITHUB_REPO_2}'" || true
    fi
fi

# Write Claude Code config — always overwrite to prevent stale personal settings
# (e.g. bridge/Harbor features from a developer's account) from blocking headless operation.
CLAUDE_CONFIG="/home/${USERNAME}/.claude.json"
cat > "${CLAUDE_CONFIG}" <<'CLAUDEJSON'
{
  "theme": "dark",
  "hasCompletedOnboarding": true,
  "permissions": { "allow": ["*"], "deny": [] }
}
CLAUDEJSON

# Fix ownership of entire home directory
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

# Export runtime env vars so supervisord inherits them (used by %(ENV_X)s in supervisord.conf)
set -a
source /etc/contagent-env.sh
set +a

exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
ENTRYPOINT_EOF

RUN chmod +x /usr/local/bin/entrypoint.sh

# 17. Claude Code wrapper — execs the command as a single binary name,
# so flags cannot be embedded in the command string. This wrapper forwards all args.
RUN printf '#!/bin/bash\nexec claude --dangerously-skip-permissions "$@"\n' \
        > /usr/local/bin/claude-headless && \
    chmod +x /usr/local/bin/claude-headless

# 18. PATH and environment persistence for SSH sessions
# /etc/contagent-env.sh is written by entrypoint.sh at container start with runtime values.
# The source line here ensures all interactive SSH shells pick it up.
RUN echo '[ -f /etc/contagent-env.sh ] && source /etc/contagent-env.sh' >> /etc/bash.bashrc && \
    { \
        echo "export JAVA_HOME=${JAVA_HOME}"; \
        echo "export M2_HOME=${M2_HOME}"; \
        echo "export GRADLE_HOME=${GRADLE_HOME}"; \
        echo "export ANDROID_HOME=${ANDROID_HOME}"; \
        echo "export BUN_INSTALL=${BUN_INSTALL}"; \
        echo "export VIRTUAL_ENV=${VIRTUAL_ENV}"; \
        echo "export PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH}"; \
        echo "export DISPLAY=${DISPLAY}"; \
        echo 'export PATH="/opt/global_venv/bin:/opt/bun/bin:/usr/local/go/bin:/usr/lib/jvm/java-21-amazon-corretto/bin:/opt/maven/bin:/opt/gradle/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH"'; \
        echo "source /opt/global_venv/bin/activate"; \
        echo "alias ls='ls -lrth --color=auto'"; \
        echo "alias headless-chrome='chromium --headless --no-sandbox --disable-gpu'"; \
    } >> /etc/bash.bashrc

EXPOSE 8022

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD nc -z localhost 8022 || exit 1

CMD ["/usr/local/bin/entrypoint.sh"]
