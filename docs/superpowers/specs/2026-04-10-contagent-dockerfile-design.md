# Contagent Dockerfile Design
Date: 2026-04-10

## Overview

A "kitchen sink" container for automatic agentic git-issues based software development. Sortie AI handles GitHub Issues orchestration, dispatching tasks to Claude Code running as a non-root user. SSH access allows direct developer interaction. Deployed to Coolify.

## Architecture

Two long-lived services managed by **supervisord** (PID 1):

| Service  | Process        | User          | Port |
|----------|---------------|---------------|------|
| Sortie   | `/usr/bin/sortie --host 0.0.0.0` | `${USERNAME}` (UID 1000) | 7678 |
| SSH      | `/usr/sbin/sshd -D` | root          | 8022 |

Sortie invokes Claude Code as subprocesses under the non-root user with `--dangerously-skip-permissions` for headless unattended operation. sshd must run as root to handle authentication and privilege separation.

## Base Image & Build Strategy

- **Base**: `ubuntu:24.04`
- **Multi-stage**: extract `/usr/bin/sortie` binary from `ghcr.io/sortie-ai/sortie:latest` in stage 1
- **Final image**: Ubuntu 24.04 with full toolchain

Ubuntu 24.04 is required — the full toolchain (Java, Android SDK, Playwright, etc.) cannot be cleanly installed on slim Node images.

## Toolchain Layers

Layers ordered for cache stability (least-changing first):

1. **System apt packages**: git, curl, gnupg, ca-certificates, build-essential, openssh-server, openssh-client, python3/dev/pip/venv, supervisor, wget, unzip, tmux, vim, htop, xvfb, headless browser libs (libgbm1, libnss3, libxss1, libasound2t64), net-tools, netcat-openbsd, nmap, silversearcher-ag, tree, fonts-liberation, fonts-noto-color-emoji, fonts-roboto
2. **GitHub CLI**: via official apt source (`cli.github.com`)
3. **Watchman**: via Meta's PPA — required by Metro bundler for React Native
4. **Node.js 22**: via NodeSource apt source
5. **Global npm packages**: `@anthropic-ai/claude-code`, `typescript`, `ts-node`, `expo-cli`, `@expo/cli`, `eas-cli`, `@react-native-community/cli`, `playwright`, `wrangler`
6. **Bun**: via install script → `/opt/bun`
7. **uv** (from `ghcr.io/astral-sh/uv:latest`) + global Python venv → `/opt/global_venv`
8. **Go**: from `golang.org/dl` tarball → `/usr/local/go`
9. **Java**: Amazon Corretto 21 via apt; `JAVA_HOME` resolved dynamically via `readlink`
10. **Maven** (3.9.6) + **Gradle** (8.7): downloaded tarballs → `/opt/maven`, `/opt/gradle`
11. **Android SDK**: cmdline-tools 11076708 → `/opt/android-sdk`; accept licenses; install `platform-tools`, `platforms;android-34`, `build-tools;34.0.0`
12. **Playwright + Chromium**: global npm install; browsers to `/opt/playwright-browsers`; Xvfb wrapper script at `/usr/local/bin/start-xvfb`

## User & Permissions

```dockerfile
RUN userdel -r node 2>/dev/null; \
    useradd --create-home --shell /bin/bash --uid 1000 ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
```

- UID 1000 matches Sortie's expected non-root UID
- Passwordless sudo allows the user to perform system operations when SSHed in
- Sortie and Claude Code run under this user; sshd runs as root

## Process Supervision (supervisord)

`/etc/supervisor/conf.d/supervisord.conf`:

```ini
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
logfile_maxbytes=50MB
loglevel=info

[program:sshd]
command=/usr/sbin/sshd -D
autostart=true
autorestart=true
priority=10
stdout_logfile=/var/log/supervisor/sshd.stdout.log
stderr_logfile=/var/log/supervisor/sshd.stderr.log

[program:sortie]
command=/usr/bin/sortie --host 0.0.0.0
user=<USERNAME baked in at build>
autostart=true
autorestart=true
priority=20
stdout_logfile=/var/log/supervisor/sortie.stdout.log
stderr_logfile=/var/log/supervisor/sortie.stderr.log
```

The `user=` directive in supervisord drops Sortie to the non-root user. The USERNAME value is baked into the conf file during build via a `RUN sed` or heredoc substitution.

## SSH Configuration

- Port: 8022 (set in `sshd_config`)
- PubkeyAuthentication: always enabled
- PasswordAuthentication: enabled only if `SSH_PASSWORD` build arg is non-empty
- `SSH_KEY` (build arg) → written to `/etc/ssh/authorized_keys.provision` at build time → copied to `/home/${USERNAME}/.ssh/authorized_keys` by entrypoint on first run (after any volume mount)

## Entrypoint Provisioning

`/usr/local/bin/entrypoint.sh` runs as root, then `exec supervisord`:

1. Copy `/etc/ssh/authorized_keys.provision` → `/home/${USERNAME}/.ssh/authorized_keys` (if present)
2. Create dirs: `/home/${USERNAME}/{.ssh,screenshots,workspaces}`
3. Write runtime ENV vars (`ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, `SORTIE_GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN`, `EXPO_TOKEN`, etc.) to `/etc/bash.bashrc` so SSH sessions inherit them
4. Authenticate gh CLI: `echo $GITHUB_TOKEN | gh auth login --with-token`
5. Clone target repo if not present: `https://${GITHUB_TOKEN}@github.com/${GITHUB_ORG}/${GITHUB_REPO}`
6. Write `/home/${USERNAME}/.claude.json` if not present:
   ```json
   { "theme": "dark", "hasCompletedOnboarding": true, "permissions": { "allow": ["*"], "deny": [] } }
   ```
7. `chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}`
8. `exec supervisord -c /etc/supervisor/conf.d/supervisord.conf`

## Environment Variables

### Build-time ARGs (must have "Build Variable" checked in Coolify)

| ARG | Default | Purpose |
|-----|---------|---------|
| `USERNAME` | `sortie` | Linux username + home dir |
| `SSH_KEY` | — | Public key for authorized_keys |
| `SSH_PASSWORD` | — | Optional fallback SSH password |

### Runtime ENV (standard Coolify environment variables)

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Claude Code authentication |
| `GITHUB_TOKEN` | gh CLI auth + repo cloning |
| `GITHUB_ORG` | Target GitHub organization |
| `GITHUB_REPO` | Target GitHub repository |
| `SORTIE_GITHUB_TOKEN` | Sortie GitHub Issues tracker auth |
| `SORTIE_GITHUB_PROJECT` | GitHub project in `owner/repo` format |
| `EXPO_TOKEN` | EAS CLI / Expo build authentication |
| `CLOUDFLARE_API_TOKEN` | Wrangler auth (Workers + R2 + DNS) |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account identifier |

Additional tokens can be injected as plain Coolify env vars and will be available in both the Sortie process environment and SSH sessions.

## Ports & Healthcheck

```dockerfile
EXPOSE 7678 8022

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD wget -qO /dev/null http://localhost:7678/readyz || exit 1
```

Coolify uses the `/readyz` healthcheck to determine container readiness.

## PATH & Environment Persistence

All tool paths baked into `/etc/bash.bashrc` and Docker `ENV` instructions:

```
/opt/global_venv/bin
/opt/bun/bin
/usr/local/go/bin
${JAVA_HOME}/bin
/opt/maven/bin
/opt/gradle/bin
/opt/android-sdk/cmdline-tools/latest/bin
/opt/android-sdk/platform-tools
```

## Key Constraints

- Sortie **must** run as non-root (UID 1000) — required for `--dangerously-skip-permissions` safety
- sshd **must** run as root — required for PAM/privilege separation
- All credentials injected at runtime, never baked into image layers
- `SSH_KEY` and `SSH_PASSWORD` are the only secrets that must be build-time ARGs (SSH config is applied during image build)
