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
