import subprocess
import json
import os
import sys, time
from pathlib import Path

# --- Configuration ---
WORKSPACE_ROOT = Path(__file__).parent.resolve()
BACKEND_REPO = user = os.getenv('BACKEND_REPO')
FRONTEND_REPO = user = os.getenv('FRONTEND_REPO')
TRIGGER_LABEL = "agent-ready"

def run_command(cmd, cwd=None):
    """Utility to run shell commands and return output."""
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, cwd=cwd
    )
    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return None
    return result.stdout.strip()

def get_pending_issues(repo_path):
    """Fetch issues with the trigger label using GitHub CLI."""
    cmd = f"gh issue list --label '{TRIGGER_LABEL}' --json number,title,body"
    output = run_command(cmd, cwd=repo_path)
    return json.loads(output) if output else []

def process_issue(issue, repo_name):
    # ... (rest of setup remains same)

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
        f"TypeScript interface in '../{FRONTEND_REPO}' and update it to match.\n"
        f"4. Search the frontend code for any API calls or hooks that use this data and update them.\n"
        f"5. Verify the build in both repos (e.g., `./gradlew build` and `npm run tsc`).\n"
        f"6. Run relevant tests in both directories.\n"
        f"7. Commit with conventional commit messages (feat:, fix:, chore:, docs:, refactor:, test:) \n"
        f"8. Create a Pull Request for each repository containing changes."
    )

    # Calling Claude Code CLI
    # We use --exec to pass the instruction and auto-exit after completion
    claude_cmd = f"claude --dangerously-skip-permissions '{instruction}'"

    # We execute from the repo where the issue was found
    subprocess.run(claude_cmd, shell=True, cwd=WORKSPACE_ROOT / repo_name)

def process_issue_old(issue, repo_name):
    issue_num = issue['number']
    title = issue['title']
    
    print(f"🚀 Processing {repo_name} Issue #{issue_num}: {title}")
    
    # Unified prompt for cross-repo context
    instruction = (
        f"I need you to solve issue #{issue_num} in {repo_name}: '{title}'.\n"
        f"IMPORTANT: This is a full-stack task. \n"
        f"1. Your primary work is in {repo_name}.\n"
        f"2. Check the sibling directory '../{FRONTEND_REPO if repo_name == BACKEND_REPO else BACKEND_REPO}' "
        "to see if complementary changes (like API types, DTOs, or UI updates) are needed.\n"
        "3. Implement the fix in BOTH repositories if necessary.\n"
        "4. Run relevant tests in both directories.\n"
        "5. Once finished, create a Pull Request for each repository that has changes."
    )

    # Calling Claude Code CLI
    # We use --exec to pass the instruction and auto-exit after completion
    claude_cmd = f"claude '{instruction}'"

    # We execute from the repo where the issue was found
    subprocess.run(claude_cmd, shell=True, cwd=WORKSPACE_ROOT / repo_name)

import time

# ... (keep your previous functions: run_command, get_pending_issues, process_issue)

def main():
    print("Worker started...")
    while True:
        try:
            for repo in [BACKEND_REPO, FRONTEND_REPO]:
                repo_path = WORKSPACE_ROOT / repo
                if not repo_path.exists():
                    continue

                issues = get_pending_issues(repo_path)
                for issue in issues:
                    process_issue(issue, repo)
                    # Label removal acts as your "queue acknowledgement"
                    run_command(f"gh issue edit {issue['number']} --remove-label '{TRIGGER_LABEL}'", cwd=repo_path)

            # Wait 5 minutes before checking GitHub for new work items again
            time.sleep(300)

        except Exception as e:
            print(f"Loop error: {e}")
            time.sleep(60) # Wait a minute before retrying on error

if __name__ == "__main__":
    print("Worker starting...")
    #main()

