# Contagent Dockerfile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a kitchen-sink Docker container with Sortie AI orchestration, Claude Code, full polyglot dev toolchain, SSH access, and supervisord process management for Coolify deployment.

**Architecture:** Ubuntu 24.04 base with multi-stage build to extract the Sortie binary. supervisord manages sshd (root, port 8022) and sortie (non-root UID 1000, port 7678). An entrypoint script handles first-run provisioning. All credentials injected as runtime env vars via Coolify; only SSH credentials need build-time ARGs.

**Tech Stack:** Docker multi-stage, Ubuntu 24.04, supervisord, Sortie AI, Claude Code, Node.js 22, Bun, uv, Python 3, Go 1.23.0, Java/Corretto 21, Maven 3.9.6, Gradle 8.7, Android SDK (platform-34), Playwright/Chromium, Watchman, GitHub CLI, Wrangler, Expo CLI, EAS CLI, React Native CLI, TypeScript

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `Dockerfile` | Rewrite | Multi-stage image with full toolchain, supervisord config, and entrypoint (all inline) |
| `CLAUDE.md` | Create | Claude Code context for AI workers running inside the container |
| `README.md` | Rewrite | Env var docs and Coolify deployment instructions |

`supervisord.conf` and `entrypoint.sh` are written via inline heredocs in the Dockerfile — no separate files to COPY.

---

### Task 1: Dockerfile skeleton — multi-stage base, ARGs, build validation

**Files:**
- Rewrite: `Dockerfile`

- [ ] **Step 1: Replace entire Dockerfile with skeleton**

```dockerfile
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
```

- [ ] **Step 2: Verify build passes with SSH_PASSWORD**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: ends with `=> exporting to image` — no error.

- [ ] **Step 3: Verify build validation fires without credentials**

```bash
docker build -t contagent:dev . 2>&1 | grep "ERROR:"
```
Expected: `ERROR: SSH_KEY or SSH_PASSWORD must be provided as build args.`

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile skeleton with multi-stage base and build validation"
```

---

### Task 2: System packages + GitHub CLI

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append system packages and GitHub CLI layers**

```dockerfile
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
```

Note: `watchman` is in Ubuntu 24.04's universe repo. If the build fails on it, remove it — Metro bundler falls back to polling automatically.

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds. First run takes 2-3 minutes.

- [ ] **Step 3: Spot-check installed packages**

```bash
docker run --rm contagent:dev sh -c "gh --version && git --version && watchman --version"
```
Expected: version strings printed for all three.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add system packages and GitHub CLI layers"
```

---

### Task 3: Node.js 22 + global npm packages

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append Node.js and npm packages layers**

```dockerfile
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
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds. npm global install takes 3-5 minutes on first run.

- [ ] **Step 3: Verify key packages**

```bash
docker run --rm contagent:dev sh -c "node --version && tsc --version && wrangler --version && expo --version"
```
Expected: version strings for all four — no errors.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Node.js 22 and global npm packages (Claude Code, TypeScript, Expo, Wrangler, RN)"
```

---

### Task 4: Bun + uv + global Python venv

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append Bun and uv/Python layers**

```dockerfile
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
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds.

- [ ] **Step 3: Verify Bun and uv**

```bash
docker run --rm contagent:dev sh -c "bun --version && uv --version && python3 --version"
```
Expected: version strings for all three.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Bun, uv, and global Python venv layers"
```

---

### Task 5: Go

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append Go layer**

```dockerfile
# 7. Go (architecture-aware download)
RUN ARCH=$(dpkg --print-architecture) && \
    wget -qO /tmp/go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds.

- [ ] **Step 3: Verify Go**

```bash
docker run --rm contagent:dev go version
```
Expected: `go version go1.23.0 linux/amd64`

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Go 1.23 layer"
```

---

### Task 6: Java (Corretto 21) + Maven + Gradle

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append Java, Maven, Gradle layers**

```dockerfile
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
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds.

- [ ] **Step 3: Verify Java, Maven, Gradle**

```bash
docker run --rm contagent:dev sh -c "java -version 2>&1 && mvn --version | head -1 && gradle --version | grep Gradle"
```
Expected:
```
openjdk version "21.x.x" ...
Apache Maven 3.9.6 ...
Gradle 8.7
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Java Corretto 21, Maven 3.9.6, and Gradle 8.7 layers"
```

---

### Task 7: Android SDK

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append Android SDK layer**

```dockerfile
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
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds. sdkmanager downloads take 2-3 minutes on first run.

- [ ] **Step 3: Verify Android SDK**

```bash
docker run --rm contagent:dev sdkmanager --list_installed 2>/dev/null | grep -E "platform-tools|android-34|34\.0\.0"
```
Expected: lines showing `platform-tools`, `platforms;android-34`, `build-tools;34.0.0` are installed.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Android SDK cmdline-tools, platform-34, and build-tools layers"
```

---

### Task 8: User creation + Playwright + SSH config

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append user, Playwright, and SSH layers**

```dockerfile
# 12. Create non-root user (UID 1000 — required by Sortie)
RUN useradd --create-home --shell /bin/bash --uid 1000 "${USERNAME}" && \
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
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds. Playwright browser download takes 2-3 minutes on first run.

- [ ] **Step 3: Verify user and Playwright**

```bash
docker run --rm contagent:dev sh -c "id sortie && ls /opt/playwright-browsers/"
```
Expected:
```
uid=1000(sortie) gid=1000(sortie) groups=1000(sortie)
chromium
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add user creation, Playwright/Chromium, and SSH configuration"
```

---

### Task 9: supervisord config

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append supervisord config layer**

```dockerfile
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
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds.

- [ ] **Step 3: Verify sortie runs as non-root in config**

```bash
docker run --rm contagent:dev grep "user=" /etc/supervisor/conf.d/supervisord.conf
```
Expected:
```
user=root
user=sortie
```
(root for supervisord itself, sortie for the sortie program)

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add supervisord config managing sshd (root) and sortie (non-root)"
```

---

### Task 10: Entrypoint script

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append entrypoint script layer**

```dockerfile
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
export SORTIE_GITHUB_TOKEN=${SORTIE_GITHUB_TOKEN}
export SORTIE_GITHUB_PROJECT=${SORTIE_GITHUB_PROJECT}
export EXPO_TOKEN=${EXPO_TOKEN}
export CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
export CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID}
ENVEOF

# Authenticate GitHub CLI as the non-root user
if [ -n "${GITHUB_TOKEN}" ]; then
    echo "${GITHUB_TOKEN}" | su - "${USERNAME}" -c "gh auth login --with-token" || true
fi

# Clone target repo if not already present
if [ -n "${GITHUB_TOKEN}" ] && [ -n "${GITHUB_ORG}" ] && [ -n "${GITHUB_REPO}" ]; then
    if [ ! -d "/home/${USERNAME}/${GITHUB_REPO}/.git" ]; then
        su - "${USERNAME}" -c "git clone 'https://${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${GITHUB_REPO}.git' '/home/${USERNAME}/${GITHUB_REPO}'"
    fi
fi

# Write Claude Code config if not present (skip onboarding, allow all permissions)
CLAUDE_CONFIG="/home/${USERNAME}/.claude.json"
if [ ! -f "${CLAUDE_CONFIG}" ]; then
    cat > "${CLAUDE_CONFIG}" <<'CLAUDEJSON'
{
  "theme": "dark",
  "hasCompletedOnboarding": true,
  "permissions": { "allow": ["*"], "deny": [] }
}
CLAUDEJSON
fi

# Fix ownership of entire home directory
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
ENTRYPOINT_EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
```

- [ ] **Step 2: Build and verify**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:dev . 2>&1 | tail -3
```
Expected: build succeeds.

- [ ] **Step 3: Verify entrypoint script is executable**

```bash
docker run --rm contagent:dev sh -c "head -3 /usr/local/bin/entrypoint.sh && ls -la /usr/local/bin/entrypoint.sh"
```
Expected: first line is `#!/bin/bash`, file has `-rwxr-xr-x` permissions.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add entrypoint provisioning script"
```

---

### Task 11: Final wiring — Sortie binary, PATH, EXPOSE, HEALTHCHECK, CMD

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Append final sections**

```dockerfile
# 17. Sortie binary from stage 1
COPY --from=sortie /usr/bin/sortie /usr/bin/sortie

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

EXPOSE 7678 8022

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD wget -qO /dev/null http://localhost:7678/readyz || exit 1

CMD ["/usr/local/bin/entrypoint.sh"]
```

- [ ] **Step 2: Full clean build**

```bash
docker build --build-arg SSH_PASSWORD=test -t contagent:latest . 2>&1 | tail -5
```
Expected: build succeeds. Most layers will be cached from previous tasks.

- [ ] **Step 3: Verify Sortie binary is present**

```bash
docker run --rm contagent:latest ls -la /usr/bin/sortie
```
Expected: `-rwxr-xr-x ... /usr/bin/sortie`

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: wire up Sortie binary, PATH persistence, ports, healthcheck, and CMD"
```

---

### Task 12: Integration test — services

**Files:** None (test only)

- [ ] **Step 1: Start the container**

```bash
docker run -d \
  --name contagent-test \
  -e ANTHROPIC_API_KEY=dummy \
  -e GITHUB_TOKEN=dummy \
  -e GITHUB_ORG=dummy \
  -e GITHUB_REPO=dummy \
  -e SORTIE_GITHUB_TOKEN=dummy \
  -e SORTIE_GITHUB_PROJECT=dummy/dummy \
  -e EXPO_TOKEN=dummy \
  -e CLOUDFLARE_API_TOKEN=dummy \
  -e CLOUDFLARE_ACCOUNT_ID=dummy \
  -p 7678:7678 \
  -p 8022:8022 \
  contagent:latest
```

- [ ] **Step 2: Wait for services and check Sortie health**

```bash
sleep 10 && curl -sf http://localhost:7678/readyz && echo "Sortie: OK"
```
Expected: `Sortie: OK` (Sortie's readyz returns HTTP 200).

- [ ] **Step 3: Verify supervisord is managing both processes**

```bash
docker exec contagent-test supervisorctl status
```
Expected:
```
sshd                             RUNNING   pid X, uptime 0:00:XX
sortie                           RUNNING   pid X, uptime 0:00:XX
```

- [ ] **Step 4: Verify SSH is accessible**

Install `sshpass` locally if needed (`apt-get install sshpass` or `brew install sshpass`), then:

```bash
sshpass -p test ssh -p 8022 -o StrictHostKeyChecking=no sortie@localhost "echo SSH_OK"
```
Expected: `SSH_OK`

- [ ] **Step 5: Clean up test container**

```bash
docker stop contagent-test && docker rm contagent-test
```

---

### Task 13: Integration test — tool availability

**Files:** None (test only)

- [ ] **Step 1: Run tool verification**

```bash
docker run --rm contagent:latest sh -c "
  echo '=== Node ===' && node --version &&
  echo '=== TypeScript ===' && tsc --version &&
  echo '=== Bun ===' && bun --version &&
  echo '=== Python ===' && python3 --version &&
  echo '=== uv ===' && uv --version &&
  echo '=== Go ===' && go version &&
  echo '=== Java ===' && java -version 2>&1 | head -1 &&
  echo '=== Maven ===' && mvn --version | head -1 &&
  echo '=== Gradle ===' && gradle --version | grep 'Gradle' &&
  echo '=== sdkmanager ===' && sdkmanager --version &&
  echo '=== gh ===' && gh --version | head -1 &&
  echo '=== wrangler ===' && wrangler --version &&
  echo '=== expo ===' && expo --version &&
  echo '=== eas ===' && eas --version &&
  echo '=== sortie ===' && ls /usr/bin/sortie && echo 'sortie: present'
"
```
Expected: all tools print version strings without errors.

- [ ] **Step 2: Verify non-root user**

```bash
docker run --rm contagent:latest id sortie
```
Expected: `uid=1000(sortie) gid=1000(sortie) groups=1000(sortie)`

---

### Task 14: Write CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Create CLAUDE.md**

```markdown
# Contagent

Container-based agentic development environment. Sortie AI orchestrates Claude Code to
automatically pick up and implement GitHub Issues. SSH access available for direct
developer interaction. Deployed via Coolify.

## Services

| Service | Port | User | Purpose |
|---------|------|------|---------|
| Sortie | 7678 | sortie (UID 1000) | GitHub Issues orchestration + Claude Code dispatch |
| sshd | 8022 | root (sessions drop to user) | Direct developer SSH access |

Both services are managed by supervisord. Logs: `/var/log/supervisor/`

## Architecture

```
supervisord (root, PID 1)
├── sshd -D                       (root, port 8022)
└── sortie --host 0.0.0.0         (sortie user, port 7678)
    └── claude --dangerously-skip-permissions   (sortie user, per-issue subprocess)
```

## Building

```bash
# Coolify: set SSH_KEY and/or SSH_PASSWORD as Build Variables (check "Build Variable")
# CLI:
docker build \
  --build-arg USERNAME=sortie \
  --build-arg SSH_PASSWORD=yourpassword \
  -t contagent:latest .
```

## Required Environment Variables

### Build-time ARGs (Coolify: check "Build Variable")

| Variable | Default | Purpose |
|----------|---------|---------|
| `USERNAME` | `sortie` | Linux user created in the container |
| `SSH_KEY` | — | SSH public key written to authorized_keys |
| `SSH_PASSWORD` | — | Fallback SSH password (at least one of SSH_KEY/SSH_PASSWORD required) |

### Runtime ENV (standard Coolify environment variables)

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Claude Code authentication |
| `GITHUB_TOKEN` | gh CLI auth + repo cloning |
| `GITHUB_ORG` | Target GitHub organization |
| `GITHUB_REPO` | Target repository name |
| `SORTIE_GITHUB_TOKEN` | Sortie GitHub Issues tracker auth |
| `SORTIE_GITHUB_PROJECT` | GitHub project in `owner/repo` format |
| `EXPO_TOKEN` | EAS CLI / Expo build authentication |
| `CLOUDFLARE_API_TOKEN` | Wrangler auth (Workers + R2 + DNS) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account identifier |

## SSH Access

```bash
ssh -p 8022 sortie@<server-ip>
```

## Installed Toolchain

- **Node.js 22** + npm
- **TypeScript** + ts-node (global npm)
- **Bun** → `/opt/bun`
- **Python 3** + uv + global venv → `/opt/global_venv`
- **Go 1.23** → `/usr/local/go`
- **Java 21** (Amazon Corretto) → `/usr/lib/jvm/java-21-amazon-corretto`
- **Maven 3.9.6** → `/opt/maven`
- **Gradle 8.7** → `/opt/gradle`
- **Android SDK** (platform-34, build-tools 34.0.0) → `/opt/android-sdk`
- **React Native CLI**, **Expo CLI**, **EAS CLI** (global npm)
- **Playwright** + Chromium → `/opt/playwright-browsers`
- **Watchman** (Metro bundler file watching)
- **GitHub CLI** (`gh`)
- **Wrangler** (Cloudflare Workers + R2)
- **Claude Code** (`claude`)
- **Sortie** → `/usr/bin/sortie`

## Sortie Configuration

Sortie reads `SORTIE_GITHUB_TOKEN` and `SORTIE_GITHUB_PROJECT` to poll GitHub Issues.
It dispatches each issue to Claude Code running as the `sortie` user with
`--dangerously-skip-permissions` for headless unattended operation.

Health endpoint: `GET http://localhost:7678/readyz`

## First-Run Provisioning (entrypoint.sh)

On every container start, `entrypoint.sh` (runs as root):
1. Copies `/etc/ssh/authorized_keys.provision` → `/home/sortie/.ssh/authorized_keys`
2. Creates `screenshots/` and `workspaces/` dirs
3. Writes all runtime ENV vars to `/etc/contagent-env.sh` (sourced by bash.bashrc)
4. Authenticates `gh` CLI with `GITHUB_TOKEN`
5. Clones `GITHUB_REPO` to `/home/sortie/<GITHUB_REPO>/` if not present
6. Writes `.claude.json` with permissions and onboarding skip
7. Fixes ownership: `chown -R sortie:sortie /home/sortie`
8. `exec supervisord`
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with architecture, env vars, and toolchain reference"
```

---

### Task 15: Rewrite README.md

**Files:**
- Rewrite: `README.md`

- [ ] **Step 1: Replace README.md**

```markdown
# Contagent = Container + Agent

Kitchen-sink container for automatic agentic software development. Sortie AI picks up
GitHub Issues and dispatches them to Claude Code. SSH access for direct developer
interaction. Deployed via Coolify.

## Architecture

```
supervisord (root, PID 1)
├── sshd -D                       (root, port 8022)
└── sortie --host 0.0.0.0         (sortie user, port 7678)
    └── claude --dangerously-skip-permissions   (sortie user, per-issue subprocess)
```

## Coolify Deployment

### 1. Build Variables

In your Coolify application, check **"Build Variable"** for each of these:

| Variable | Purpose |
|----------|---------|
| `USERNAME` | Linux username (default: `sortie`) |
| `SSH_KEY` | Your SSH public key (`cat ~/.ssh/id_rsa.pub`) |
| `SSH_PASSWORD` | Fallback password (optional if SSH_KEY is set) |

### 2. Environment Variables

Standard Coolify env vars (no "Build Variable" checkbox needed):

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Claude Code authentication |
| `GITHUB_TOKEN` | gh CLI auth + repo cloning |
| `GITHUB_ORG` | Target GitHub organization |
| `GITHUB_REPO` | Target repository name |
| `SORTIE_GITHUB_TOKEN` | Sortie GitHub Issues tracker |
| `SORTIE_GITHUB_PROJECT` | GitHub project (`owner/repo`) |
| `EXPO_TOKEN` | EAS CLI authentication |
| `CLOUDFLARE_API_TOKEN` | Wrangler (Workers + R2 + DNS) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID |

### 3. Save and Deploy

## CLI Build

```bash
docker build \
  --build-arg USERNAME="sortie" \
  --build-arg SSH_KEY="$(cat ~/.ssh/id_rsa.pub)" \
  --build-arg SSH_PASSWORD="your_password" \
  -t contagent:latest .
```

## SSH Access

```bash
ssh -p 8022 sortie@<server-ip>
```

## Health Check

```bash
curl http://<server-ip>:7678/readyz
```

## Service Logs

```bash
# From inside container:
supervisorctl status
tail -f /var/log/supervisor/sortie.stdout.log
tail -f /var/log/supervisor/sshd.stderr.log
```

## Installed Toolchain

| Tool | Version |
|------|---------|
| Node.js | 22 LTS |
| TypeScript + ts-node | latest |
| Bun | latest |
| Python 3 + uv | system + latest |
| Go | 1.23.0 |
| Java (Amazon Corretto) | 21 |
| Maven | 3.9.6 |
| Gradle | 8.7 |
| Android SDK | platform-34, build-tools 34.0.0 |
| React Native CLI | latest |
| Expo CLI + EAS CLI | latest |
| Playwright + Chromium | latest |
| GitHub CLI | latest |
| Wrangler | latest |
| Watchman | system |
| Claude Code | latest |
| Sortie | latest |
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for Sortie-based architecture with env vars and toolchain table"
```

---

## Self-Review

**Spec coverage:**
- Multi-stage build (Sortie binary) ✓ Task 1
- Ubuntu 24.04 base ✓ Task 1
- System packages incl. watchman ✓ Task 2
- GitHub CLI ✓ Task 2
- Node.js 22 + all global npm packages ✓ Task 3
- Bun + uv + Python venv ✓ Task 4
- Go ✓ Task 5
- Java Corretto 21 + Maven + Gradle ✓ Task 6
- Android SDK ✓ Task 7
- User creation UID 1000 + passwordless sudo ✓ Task 8
- Playwright + Chromium ✓ Task 8
- SSH server config ✓ Task 8
- supervisord (sortie non-root, sshd root, autorestart) ✓ Task 9
- Entrypoint provisioning ✓ Task 10
- Runtime ENV vars written to /etc/contagent-env.sh ✓ Task 10
- Sortie binary copy ✓ Task 11
- PATH persistence for SSH sessions ✓ Task 11
- EXPOSE 7678 8022 ✓ Task 11
- HEALTHCHECK /readyz ✓ Task 11
- Build ARGs: USERNAME, SSH_KEY, SSH_PASSWORD ✓ Task 1
- All 9 runtime ENV vars documented and wired ✓ Tasks 10, 14, 15
- CLAUDE.md ✓ Task 14
- README.md ✓ Task 15

**No placeholders found.**

**Name consistency:** `PLAYWRIGHT_BROWSERS_PATH`, `BUN_INSTALL`, `VIRTUAL_ENV`, `JAVA_HOME`, `M2_HOME`, `GRADLE_HOME`, `ANDROID_HOME` used consistently throughout all tasks.
