---
name: git-workflow
description: Use when autopilot needs to create branches, commit changes, push, or create PRs — handles all git operations with consistent conventions
---

# Git Workflow

All git operations during autopilot follow these conventions.

## Branch Naming

- Format: `bostondv/<feature-slug>`
- Create branch from `main` or `master` before starting work
- Example: `bostondv/add-login-page`

## Commits

- Use conventional commits style (e.g., `feat:`, `fix:`, `chore:`)
- Keep messages concise, focus on **why** not what
- Example: `feat: add user auth flow to support SSO requirements`

## Pushing

- Always push with `-u origin <branch>` on first push
- Rebase from master before pushing if the branch is stale:
  ```
  git fetch origin
  git rebase origin/main
  ```

## Pull Requests

- Always create as **draft**: `gh pr create --draft`
- PR description: concise, focus on why/how — not a list of every file changed
- Include spec summary and acceptance criteria in PR body
- If scope changes, rewrite the full description (don't append)
- Only include files relevant to the task in the diff
