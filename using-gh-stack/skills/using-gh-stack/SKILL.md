---
name: using-gh-stack
description: Use when the user asks to create, update, rebase, or edit stacked pull requests — chains of dependent PRs where each branch is based on the previous. Triggers on "stacked PR", "stack", "restack", "rebase the stack", "PR chain", "dependent PRs", "stacked branches", "chain of PRs".
---

# Using gh-stack

`gh-stack` (github.com/instacart/gh-stack) manages stacked PR workflows: chains of dependent branches where each PR builds on the previous one. It automates the tedious part — rebasing the whole chain onto updated `master` and force-pushing safely after a base PR merges.

Already installed at `/Users/bostondv/.config/gohan/bin/gh-stack` (via Gohan). Verify with `which gh-stack` before first use in a new session.

## The stack model

```
master
  └─ bostondv/feat-1   (PR #1, base: master)
      └─ bostondv/feat-2   (PR #2, base: bostondv/feat-1)
          └─ bostondv/feat-3   (PR #3, base: bostondv/feat-2)
```

Each PR's **base branch on GitHub** is the branch below it, NOT `master`. Set with `gh pr create --base <parent-branch>`. If bases are wrong on GitHub, gh-stack still rebases locally but GitHub won't display them as a stack.

## Commands

| Command | Use when |
|---|---|
| `gh-stack rebase` | The bottom PR just merged. Auto-detects the merged branch, rebases everything above onto updated `master`, force-pushes with `--force-with-lease`. Run from any branch in the stack. |
| `gh-stack rebase-from <ref>` | Auto-detect failed (branch already deleted, multiple candidates), or you want to be explicit. `<ref>` = the merged branch name or SHA. |
| `gh-stack edit <commit-sha>` | Amend a commit mid-stack. Git pauses on that commit — edit files → `git commit --amend` → `git rebase --continue`. Everything above auto-rebases and force-pushes. |

Common flags on all commands: `-n/--dry-run`, `-y/--yes`, `-b/--base <branch>` (default `master`), `-v/--verbose`. Full help: `gh-stack <command> --help`.

## Creating a new stack

gh-stack does NOT create stacks — only rebases/edits them. To build one, use plain git + gh:

```bash
git checkout master && git pull
git checkout -b bostondv/feat-1
# work, commit
git push -u origin bostondv/feat-1
gh pr create --draft --base master

git checkout -b bostondv/feat-2
# work, commit
git push -u origin bostondv/feat-2
gh pr create --draft --base bostondv/feat-1
# ...repeat
```

Per user prefs: `bostondv/` branch prefix, always `--draft`.

## Workflow: after a bottom PR merges

1. `git fetch origin master` (or let gh-stack do it)
2. `gh-stack rebase --dry-run` — preview what will change
3. `gh-stack rebase` — execute
4. If conflicts: resolve, `git add`, `git rebase --continue` — gh-stack's push logic runs automatically when the rebase completes

## Gotchas

- **Working tree must be clean.** `git status` first; stash or commit before running.
- **Never rebase mid-stack manually.** Use `gh-stack edit` — it wires up the label/update-ref/push machinery that plain `git rebase -i` doesn't.
- **Always `--dry-run` first** unless the user explicitly said "just do it". Force-push is fast to trigger and slow to undo.
- **Don't reach for `--clobber`** unless divergence is expected — it disables the `--force-with-lease` safety that catches teammates pushing to your branch.
- **Carrot worktrees (graft):** if the stack's branches are checked out in another worktree, gh-stack in this worktree can't update those branch refs — run gh-stack from the worktree that owns the stack, or from the main checkout.
- **Base is `master` in carrot.** Default is fine; only pass `--base` if the repo uses `main` or a different trunk.
