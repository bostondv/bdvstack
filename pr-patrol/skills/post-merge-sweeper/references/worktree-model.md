# Worktree Model

Shared graft worktree instructions for pr-patrol workers. All local code changes use graft. Never `git clone`, never `mktemp` working dirs.

## Finding the project path

When you need a worktree for a branch, determine `project_path` in this order:

1. **Existing worktree for this branch:**
   ```bash
   graft ls
   ```
   Parse output — if the branch appears, its PROJECT column is the path. Use that exact path.

2. **Existing worktree for this repo:**
   ```bash
   graft ls | grep "^<repo-slug>.*<worktree-name>"
   ```
   If found, it has a known project path. Reuse it (checkout the new branch).

3. **Infer from PR diff:**
   ```bash
   gh pr diff <number> --repo <repo> --name-only | head -30
   ```
   Find the shallowest directory that:
   - Appears as a prefix of multiple changed files, AND
   - Contains a project root marker (`package.json`, `Gemfile`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `build.gradle`)

   Example: if changed files are `customers/store/client/foo.ts`, `customers/store/server/bar.ts` → check if `customers/store/package.json` exists → project_path is `customers/store`.

4. **Fall back to repo root** (`.`).

## Using the worktree

The `<worktree-name>` is caller-specific (e.g. `babysit-<repo-slug>` or `sweeper-<repo-slug>`).

```bash
# Check if branch already has a worktree
WORKTREE=$(graft ls | awk '/^<repo>.*<branch>/ {print $3}')

if [ -n "$WORKTREE" ]; then
  # Use existing branch worktree
  cd $(graft cd <branch> --print 2>/dev/null || echo "~/grafts/<repo>/<branch>/<project_path>")
  git pull
else
  # Use or create generic worktree
  if ! graft ls | grep -q "<worktree-name>"; then
    graft new <worktree-name> <project_path> --no-create -r <repo-slug>
    # Note: --no-create requires the branch to exist. The worktree
    # starts on master/main. We then checkout the target branch inside it.
  fi
  WORK_DIR=$(graft cd <worktree-name> --print 2>/dev/null)
  cd "$WORK_DIR"
  git fetch origin <head-branch>
  git checkout <head-branch>
  git pull
fi
```

## Key rules

- **Never create a per-PR worktree** — use existing or the generic `<worktree-name>` worktree
- **Never modify the user's working directory** — all changes in graft worktrees
- **Leave the worktree after use** — don't switch branch back to master (next run will switch to whatever branch it needs)
- **Code-change workers for the same repo run sequentially** (enforced by team lead)
- **After pushing:** capture the new HEAD SHA with `git rev-parse HEAD`
- **New commits only** — never amend, squash, or force-push (except `--force-with-lease` after rebase)
- **Verify push auth** before committing — run `git remote -v` to confirm remote is set up for push
- **If a fix attempt fails** — discard and report instead of pushing broken code
