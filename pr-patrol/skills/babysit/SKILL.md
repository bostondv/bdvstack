---
name: babysit
description: Monitor and maintain open PRs — auto-rebase, fix CI failures, address trivial review comments, surface complex ones. Designed for use with /loop (e.g., /loop 5m /babysit).
user-invocable: true
---

# Babysit

Automated PR maintenance loop. Keeps your open PRs healthy and moving toward merge.

## Invocation

```
/babysit [--repo owner/repo ...] [--yolo]
/loop 5m /babysit
/loop 5m /babysit --repo instacart/carrot --repo instacart/toolbox
```

## Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `--repo owner/repo` | Narrow to specific repo(s). Repeatable. | All repos with your open PRs |
| `--yolo` | Full autonomy — fix everything including complex review comments | Off (triage mode) |

## PR Discovery

Discover open PRs authored by the current user.

**Default (all repos):**

```bash
gh pr list --author @me --state open --json number,title,headRefName,baseRefName,url,repository --limit 100
```

If that returns nothing or errors (single-repo context), fall back to enumerating repos:

```bash
# Get all repos the user has contributed to recently
gh api graphql -f query='
{
  viewer {
    pullRequests(first: 100, states: OPEN, orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes {
        number
        title
        headRefName
        baseRefName
        url
        repository {
          nameWithOwner
        }
        reviewDecision
        mergeable
        statusCheckRollup {
          state
        }
      }
    }
  }
}'
```

**With `--repo`:**

For each specified repo:
```bash
gh pr list --repo <owner/repo> --author @me --state open --json number,title,headRefName,baseRefName,url
```

## Per-PR Processing

Process each discovered PR in order. For each PR:

### Step 1: Rebase Check

```bash
gh pr view <number> --repo <repo> --json mergeable,mergeStateStatus
```

If the PR is behind its base branch (merge conflicts or stale):

```bash
# Clone/fetch in a temp directory to avoid touching working dir
WORK=$(mktemp -d)
cd "$WORK"
gh repo clone <repo> . -- --depth=50
git checkout <head-branch>
git rebase origin/<base-branch>
```

If rebase succeeds:
```bash
git push --force-with-lease
```
Report: "Rebased `<branch>` onto `<base>`"

If rebase has conflicts:
- Report the conflicting files to the user
- Do NOT force-resolve conflicts
- Notify: "PR #NNN has rebase conflicts in: file1, file2"

Clean up the temp directory when done.

### Step 2: CI Failures

Check CI status:
```bash
gh pr checks <number> --repo <repo> --json name,state,description,detailsUrl
```

If any checks are failing:

1. **Identify the failure** — fetch logs from the failing check:
   ```bash
   # For GitHub Actions
   gh run view <run-id> --repo <repo> --log-failed

   # For Buildkite (if buildkite MCP is available)
   # Use mcp__buildkite__get_build and mcp__buildkite__read_logs
   ```

2. **Diagnose** — read the error output. Categorize:
   - **Flaky test**: test passed before, failure looks non-deterministic → re-run the check
     ```bash
     gh run rerun <run-id> --repo <repo> --failed
     ```
   - **Code issue**: compilation error, test assertion, lint failure → attempt fix
   - **Infra issue**: timeout, OOM, service unavailable → report only, don't attempt fix

3. **Attempt fix** (code issues only):
   ```bash
   WORK=$(mktemp -d)
   cd "$WORK"
   gh repo clone <repo> . -- --depth=50
   git checkout <head-branch>
   ```
   - Read the relevant source files
   - Make the fix
   - Run available local checks (lint, typecheck, test) if detectable
   - Commit with message: `Fix CI: <brief description>`
   - Push
   - Report what was fixed

4. **Report unfixable issues** to the user with the error context.

### Step 3: Review Comments

Fetch unresolved review threads:
```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate
gh api repos/<owner>/<repo>/pulls/<number>/reviews --paginate
```

Also fetch via GraphQL for thread resolution status:
```bash
gh api graphql -f query='
{
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <number>) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 10) {
            nodes {
              body
              author { login }
              path
              line
              createdAt
            }
          }
        }
      }
    }
  }
}'
```

For each unresolved thread where the last comment is NOT from you:

1. **Read the comment** and the code it references
2. **Classify** the comment:

   **Trivial** (auto-fix in any mode):
   - Naming suggestions (variable/function rename)
   - Typo fixes
   - Import ordering / unused imports
   - Missing type annotations
   - Simple refactors where the reviewer gave explicit code
   - Formatting issues
   - Adding/removing a comment

   **Non-trivial** (auto-fix only in `--yolo` mode):
   - Logic changes
   - Architecture / design suggestions
   - Performance concerns
   - Security issues
   - Anything requiring judgment about trade-offs
   - Anything where the fix isn't obvious from the comment

3. **For auto-fixable comments:**
   ```bash
   WORK=$(mktemp -d)
   cd "$WORK"
   gh repo clone <repo> . -- --depth=50
   git checkout <head-branch>
   ```
   - Make the change
   - Commit: `Address review: <brief description>`
   - Push
   - Reply to the comment thread:
     ```bash
     gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment-id>/replies \
       -f body="$(cat <<'EOF'
     Done — <brief description of what was changed>.

     Sent from Claude Code
     EOF
     )"
     ```

4. **For non-trivial comments (triage mode):**
   - Output to conversation: the PR, the comment, the file/line, and a brief summary
   - Notify (see Notifications below)

### Step 4: Status Report

After processing all PRs, output a brief summary:

```
## Babysit Report

### owner/repo#123 — "Add login page"
- Rebased onto main
- Fixed CI: missing import in auth.ts
- Addressed 2 review comments (naming, unused import)
- 1 comment needs your attention: architecture question from @reviewer

### owner/repo#456 — "Update API schema"
- All checks passing
- No new review comments
```

## Notifications

Use a cascade — try each method, use the first that works:

1. `cmux notify --title "Babysit" --body "<message>"` (if `$CMUX_WORKSPACE_ID` is set and `cmux` exists)
2. `tmux display-message "Babysit: <message>"` (if `$TMUX` is set)
3. `osascript -e 'display notification "<message>" with title "Babysit"'` (macOS fallback)
4. Console output only (always happens regardless)

Only notify for items needing attention (non-trivial comments, unfixable CI, rebase conflicts). Don't notify when everything is clean.

## Safety Rules

- **All code changes happen in temp directories** — never modify the user's working directory
- **New commits only** — never amend, squash, or force-push (except `--force-with-lease` for rebases)
- **All PR replies include** `Sent from Claude Code` attribution
- **Never merge a PR** — only push fixes and reply to comments
- **Never dismiss reviews** or approve your own PR
- **If a fix attempt fails** (tests don't pass after the change), discard it and report instead of pushing broken code
- **Rate limit**: if a PR was already processed in the last loop iteration and nothing changed (no new comments, same CI status), skip it

## Loop Behavior

When running under `/loop`:
- Each invocation is a full scan of all matching PRs
- Output is cumulative — each cycle produces its own report section
- Skip PRs with no changes since last cycle to avoid noise
- Notify only on new findings, not repeated ones
