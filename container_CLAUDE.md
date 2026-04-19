# Contagent Container

You are operating inside an agentic development container. Repos are pre-cloned at `/home/$USERNAME/` and all credentials are already in the environment.

## Repos

| Variable | Path |
|----------|------|
| `$GITHUB_REPO` | `/home/$USERNAME/$GITHUB_REPO` |
| `$GITHUB_REPO_2` | `/home/$USERNAME/$GITHUB_REPO_2` (if set) |

## PostgreSQL

A local PostgreSQL 16 instance is running. No password required — trust auth is configured for all local connections.

| | |
|-|-|
| Connection string | `$DATABASE_URL` → `postgresql://<USERNAME>@localhost:5432/<USERNAME>` |
| Unix socket | `/var/run/postgresql/` |
| Version | 16 |

```bash
psql $DATABASE_URL                     # interactive shell
psql $DATABASE_URL -c "SELECT 1"       # one-off query
createdb -h localhost myapp_test       # create an extra test database
```

Point your test suite at `$DATABASE_URL`. For Spring Boot, set `spring.datasource.url` from the environment. For Node/Prisma, `DATABASE_URL` is already the expected variable name.

## Build Tools

| Tool | Command | Notes |
|------|---------|-------|
| Java 21 (Corretto) | `java`, `javac` | `$JAVA_HOME` set |
| Maven | `mvn` or `./mvnw` | `$M2_HOME` → `/opt/maven` |
| Gradle | `./gradlew` | always use the wrapper |
| Node.js 22 | `node`, `npm` | |
| TypeScript | `tsc`, `ts-node` | global |
| Bun | `bun` | `/opt/bun` |
| Python 3 | `python3`, `uv` | venv at `/opt/global_venv` |
| Go 1.23 | `go` | `/usr/local/go` |

## Other Tools

| Tool | Command | Notes |
|------|---------|-------|
| GitHub CLI | `gh` | pre-authenticated via `$GITHUB_TOKEN` |
| Wrangler | `wrangler` | Cloudflare Workers/R2/DNS |
| Playwright | `playwright` | Chromium at `/opt/playwright-browsers` |
| psql | `psql` | PostgreSQL 16 client |

## Standard Workflow

```bash
# 1. Create a feature branch
git checkout -b feat/issue-123-short-description

# 2. Implement changes

# 3. Run backend tests (Gradle)
cd /home/$USERNAME/$GITHUB_REPO && ./gradlew test

# 4. Run frontend type check + tests
cd /home/$USERNAME/$GITHUB_REPO_2 && npm run tsc && npm test

# 5. Commit using conventional commit format
git commit -m "feat: solve issue #123 — short description"

# 6. Open a pull request
gh pr create --title "feat: ..." --body "Closes #123"
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Claude API authentication |
| `GITHUB_TOKEN` | GitHub — `gh` is pre-authenticated |
| `GITHUB_ORG` | Target GitHub organization |
| `GITHUB_REPO` | Primary repository name |
| `GITHUB_REPO_2` | Secondary repository name (optional) |
| `DATABASE_URL` | Local PostgreSQL connection string |
| `EXPO_TOKEN` | Expo / EAS build authentication |
| `CLOUDFLARE_API_TOKEN` | Wrangler authentication |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account identifier |
