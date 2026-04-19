import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

logging.basicConfig(
    stream=sys.stdout,
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)-8s %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger("claude_worker")

WORKSPACE_ROOT = Path(__file__).parent.resolve()
BACKEND_REPO  = os.getenv('GITHUB_REPO')
FRONTEND_REPO = os.getenv('GITHUB_REPO_2')
TRIGGER_LABEL      = "agent-ready"
INPROGRESS_LABEL   = "agent-inprogress"
COMPLETE_LABEL     = "agent-complete"
MAX_RETRIES        = 4
RETRY_BASE_DELAY   = 60  # seconds; doubles on each attempt (60 → 120 → 240 → 480)

log.info("Configuration: WORKSPACE_ROOT=%s BACKEND_REPO=%s FRONTEND_REPO=%s TRIGGER_LABEL=%s",
         WORKSPACE_ROOT, BACKEND_REPO, FRONTEND_REPO, TRIGGER_LABEL)


def run_command(cmd, cwd=None):
    log.debug("run_command: %s (cwd=%s)", cmd, cwd)
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd)
    if result.returncode != 0:
        log.error("Command failed (exit %d): %s", result.returncode, result.stderr.strip())
        return None
    log.debug("Command output: %s", result.stdout.strip()[:500])
    return result.stdout.strip()


def get_pending_issues(repo_path):
    log.info("Fetching issues labelled '%s' in %s", TRIGGER_LABEL, repo_path)
    cmd = f"gh issue list --label '{TRIGGER_LABEL}' --json number,title,body"
    output = run_command(cmd, cwd=repo_path)
    issues = json.loads(output) if output else []
    log.info("Found %d pending issue(s) in %s", len(issues), repo_path.name)
    return issues


def get_pr_urls(repo_path):
    """Return URLs of any open PRs on the current branch."""
    output = run_command("gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json url --jq '.[].url'", cwd=repo_path)
    if not output:
        return []
    return [line.strip() for line in output.splitlines() if line.strip()]


def process_issue(issue, repo_name):
    issue_num = issue['number']
    title     = issue['title']
    repo_path = WORKSPACE_ROOT / repo_name

    log.info("--- Starting issue #%d in %s: %s", issue_num, repo_name, title)

    # Mark in-progress before handing off to Claude
    run_command(f"gh issue edit {issue_num} --add-label '{INPROGRESS_LABEL}'", cwd=repo_path)

    sibling = FRONTEND_REPO if repo_name == BACKEND_REPO else BACKEND_REPO

    instruction = (
        f"Task: Solve issue #{issue_num} in {repo_name}: '{title}'.\n\n"
        f"CONTEXT FOR WORKSPACE:\n"
        f"- Backend: read CLAUDE.md\n"
        f"- Frontend: read CLAUDE.md\n"
        f"- Sync Method: Manual mapping of Java DTOs to TS Interfaces.\n\n"
        f"YOUR GOAL:\n"
        f"1. Create a feature branch for your changes\n"
        f"2. Implement the logic changes in {repo_name}.\n"
        f"3. If you modify a Java Record or POJO in the backend, you MUST locate the corresponding "
        f"TypeScript interface in '../{sibling}' and update it to match.\n"
        f"4. Search the frontend code for any API calls or hooks that use this data and update them.\n"
        f"5. Verify the build in both repos (e.g., `./gradlew build` and `npm run tsc`).\n"
        f"6. Run relevant tests in both directories.\n"
        f"7. Commit with conventional commit messages (feat:, fix:, chore:, docs:, refactor:, test:)\n"
        f"8. Create a Pull Request for each repository containing changes."
    )

    log.info("Launching Claude for issue #%d (cwd=%s)", issue_num, repo_path)
    log.debug("Instruction:\n%s", instruction)

    result = None
    for attempt in range(1, MAX_RETRIES + 1):
        if attempt > 1:
            delay = RETRY_BASE_DELAY * (2 ** (attempt - 2))
            log.warning("Retry %d/%d for issue #%d — waiting %ds", attempt, MAX_RETRIES, issue_num, delay)
            time.sleep(delay)

        result = subprocess.run(
            ["claude", "--dangerously-skip-permissions", instruction],
            cwd=repo_path,
        )
        log.info("Claude exited with code %d for issue #%d (attempt %d)", result.returncode, issue_num, attempt)

        if result.returncode == 0:
            break
        log.warning("Non-zero exit from Claude on issue #%d attempt %d — will retry", issue_num, attempt)

    if result.returncode != 0:
        log.error("Claude failed all %d attempts for issue #%d", MAX_RETRIES, issue_num)

    # Collect PR URLs from both repos (Claude may have pushed to either)
    pr_urls = get_pr_urls(repo_path)
    if sibling:
        pr_urls += get_pr_urls(WORKSPACE_ROOT / sibling)
    pr_urls = list(dict.fromkeys(pr_urls))  # deduplicate, preserve order

    if pr_urls:
        log.info("PRs created for issue #%d: %s", issue_num, pr_urls)
        body = "Agent completed work. Pull request(s):\n" + "\n".join(f"- {u}" for u in pr_urls)
        run_command(f"gh issue comment {issue_num} --body '{body}'", cwd=repo_path)
        run_command(
            f"gh issue edit {issue_num} --add-label '{COMPLETE_LABEL}' --remove-label '{INPROGRESS_LABEL}'",
            cwd=repo_path,
        )
    else:
        log.warning("No PRs found after Claude finished issue #%d", issue_num)
        run_command(
            f"gh issue edit {issue_num} --remove-label '{INPROGRESS_LABEL}'",
            cwd=repo_path,
        )


def main():
    log.info("Worker started (pid=%d)", os.getpid())
    while True:
        try:
            repos = [r for r in [BACKEND_REPO, FRONTEND_REPO] if r]
            if not repos:
                log.warning("No repos configured (GITHUB_REPO and GITHUB_REPO_2 are both unset) — sleeping")
            else:
                log.debug("Poll cycle: checking repos %s", repos)

            for repo in repos:
                repo_path = WORKSPACE_ROOT / repo
                if not repo_path.exists():
                    log.warning("Repo path does not exist, skipping: %s", repo_path)
                    continue

                issues = get_pending_issues(repo_path)
                for issue in issues:
                    run_command(
                        f"gh issue edit {issue['number']} --remove-label '{TRIGGER_LABEL}'",
                        cwd=repo_path,
                    )
                    process_issue(issue, repo)

            log.debug("Poll cycle complete, sleeping 300s")
            time.sleep(30)

        except Exception as e:
            log.exception("Unhandled loop error: %s", e)
            log.info("Sleeping 60s before retry")
            time.sleep(60)

def looper():
    while True:
        time.sleep(300)


if __name__ == "__main__":
    log.info("Worker starting...")
    #main()
    looper()
