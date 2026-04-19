---
name: container-tools
description: Step-by-step procedures for common tasks in this container — database setup, running tests, build commands, and PR workflow. Use when running integration tests, querying postgres, or building either repo.
---

# Container Tools

## PostgreSQL

```bash
# Connect interactively
psql $DATABASE_URL

# Run a query inline
psql $DATABASE_URL -c "SELECT count(*) FROM my_table"

# Create an isolated test database
createdb -h localhost myapp_test
psql postgresql://$USERNAME@localhost:5432/myapp_test

# Drop and recreate for a clean slate
dropdb -h localhost myapp_test && createdb -h localhost myapp_test

# Run migrations against a specific database (Flyway / Liquibase)
DATABASE_URL=postgresql://$USERNAME@localhost:5432/myapp_test ./gradlew flywayMigrate
```

Spring Boot — add to `application-test.properties`:
```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/${USERNAME}
spring.datasource.username=${USERNAME}
spring.datasource.password=
```

Prisma / Node — `DATABASE_URL` is already the expected env var name. No extra config needed.

## Running Tests

```bash
# Gradle — all tests
./gradlew test

# Gradle — specific class or method
./gradlew test --tests "com.example.MyServiceTest"
./gradlew test --tests "com.example.MyServiceTest.myMethod"

# Gradle — integration tests only (assumes separate source set)
./gradlew integrationTest

# Maven
./mvnw test
./mvnw -Dtest=MyServiceTest test

# npm / Jest
npm test
npx jest --testPathPattern=MyComponent
npx jest --watch

# TypeScript type check (no test runner)
npm run tsc
```

## Building

```bash
# Gradle build (skip tests)
./gradlew build -x test

# Gradle clean build
./gradlew clean build

# Maven
./mvnw package -DskipTests

# Node
npm run build
bun run build

# Go
go build ./...
go test ./...
```

## GitHub CLI

```bash
# List issues ready for the agent
gh issue list --label agent-ready

# View issue details
gh issue view 123

# Remove agent-ready label after completing work
gh issue edit 123 --remove-label agent-ready

# Create a pull request
gh pr create --title "feat: description" --body "Closes #123"

# Check PR status / CI
gh pr status
gh pr checks
```

## Playwright (browser automation)

```bash
# Run all browser tests
npx playwright test

# Run a specific test file
npx playwright test tests/login.spec.ts

# Run in headed mode (requires Xvfb — already running)
DISPLAY=:99 npx playwright test --headed

# Record a new test interactively
DISPLAY=:99 npx playwright codegen http://localhost:3000
```

## Wrangler (Cloudflare)

```bash
# Deploy a Worker
wrangler deploy

# Tail live logs
wrangler tail

# R2 — list buckets
wrangler r2 bucket list

# R2 — upload a file
wrangler r2 object put my-bucket/path/to/file.txt --file ./local-file.txt
```
