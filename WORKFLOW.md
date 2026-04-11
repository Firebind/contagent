---
tracker:
  kind: github
  api_key: $SORTIE_GITHUB_TOKEN
  project: $SORTIE_GITHUB_PROJECT
  query_filter: "label:sortie"
  active_states:
    - backlog
    - in-progress
  in_progress_state: in-progress
  handoff_state: review
  terminal_states:
    - done
    - wontfix

polling:
  interval_ms: 60000

workspace:
  root: ~/workspaces

agent:
  kind: claude-code
  command: claude
  max_turns: 20
---

You are a senior software engineer. Implement the GitHub issue assigned to you.

## Task

**#{{ .issue.identifier }}**: {{ .issue.title }}
{{ if .issue.description }}
### Description

{{ .issue.description }}
{{ end }}
{{ if .issue.url }}
**Issue:** {{ .issue.url }}
{{ end }}

## Instructions

- Work in the cloned repository at your current directory
- Create a feature branch for your changes
- Write tests where appropriate
- Commit with conventional commit messages (feat:, fix:, chore:, docs:, refactor:, test:)
- Open a pull request when complete, linking the issue number
