---
name: stacked-prs
description: Use when managing stacked PRs, multi-PR feature development, or when user needs to create, rebase, or track a chain of dependent PRs.
---

# Stacked PR Management

Manage multi-PR feature development workflows where PRs depend on each other in a chain.

## When to Use

- User wants to split a large feature into reviewable slices
- User says "stack", "stacked PR", "dependent PRs", "chain of PRs"
- User needs to rebase a stack after changes
- User needs to create PRs for a branch chain

## Core Concepts

Stack = ordered list of branches where each depends on the previous:
```
master → feature/auth-1-model → feature/auth-2-service → feature/auth-3-api
```

Each branch gets its own PR targeting the previous branch (not master).

## Stack Naming Convention

```
feature/<name>-<number>[-description]
# e.g., feature/auth-1-model, feature/auth-2-service, feature/auth-3-api
```

Or with the user's branch prefix:
```
bostondv/<name>-<number>[-description]
```

## Workflow

### Create a Stack

1. Define branches in order (base dependency first)
2. Use `/create-stacked-pr` command or the stack scripts
3. Each PR targets the previous branch, not master

### After Making Changes

1. Rebase the entire stack: `source scripts/stack-scripts.sh && stack_rebase`
2. Force push all: `stack_push`

### After Base PR Merges

1. Update next PR's base to master: `gh pr edit <number> --base master`
2. Rebase remaining stack on master
3. Force push affected branches

## Quick Reference

| Action | Command |
|--------|---------|
| Check stack status | `stack_status` |
| Rebase entire stack | `stack_rebase` |
| Push all branches | `stack_push` |
| Create all PRs | `stack_create_prs` |
| After merge cleanup | `stack_update_after_merge <position>` |
| Delete merged branches | `stack_cleanup` |

## PR Description

Always include a stack position table in PR descriptions:

```markdown
## Stack Position
| # | PR | Status | Branch |
|---|-----|--------|--------|
| 1 | #101 | Merged | feature/auth-1-model |
| 2 | **#102** | **This PR** | feature/auth-2-service |
| 3 | #103 | Draft | feature/auth-3-api |
```

See `references/stack-management.md` for detailed patterns and scripts.
