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
