---
name: babysit
description: "Monitor and maintain open PRs — auto-rebase, fix CI failures, address trivial review comments, surface complex ones. Invoke: `/babysit --repo owner/repo` or `/loop 10m /babysit --repo owner/repo`"
user-invocable: true
argument-hint: "--repo owner/repo [--yolo]"
---

# Babysit

Automated PR maintenance loop. Keeps your open PRs healthy and moving toward merge.

## Invocation

```
/babysit [--repo owner/repo ...] [--yolo]
/loop 10m /babysit --repo instacart/carrot
```

## Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `--repo owner/repo` | Narrow to specific repo(s). Repeatable. | All repos with your open PRs |
| `--yolo` | Full autonomy — fix everything including complex review comments | Off (triage mode) |

---

## Execution Model

The **invoking Claude instance** (main conversation) does the setup, then hands off to background agents. `TeamCreate`, `TaskCreate`, and `SendMessage` must be called from the main conversation — background agents don't have these tools unless spawned with `team_name`.

### Invoking Claude — Setup (blocking, but fast)

#### 1. Guard: create or reuse team

**CRITICAL: You MUST call `TeamCreate` here and confirm it succeeds (or handle the "already exists" case below) BEFORE proceeding to any later step. Do NOT skip ahead to spawning agents — agents spawned with `team_name` will fail if the team doesn't exist yet.**

```
TeamCreate(team_name: "babysit-<repo-slug>")
```
Use repo slug (e.g. `babysit-carrot` for `instacart/carrot`). Multiple repos → one team per repo.

If `TeamCreate` succeeds → proceed to Step 2.

If `TeamCreate` fails with "team already exists":
- Call `TaskList` on the existing team
- If **any task is `in_progress`** and its `started_at` is **< 20 minutes ago** → **exit as no-op** (previous run still working)
- If tasks are `in_progress` but `started_at` is ≥ 20 minutes ago → those workers likely crashed; reset them to `pending` with `TaskUpdate` and proceed
- If all tasks are `completed` or none exist → proceed with the existing team

#### 2. Load state

Read `~/.claude/cache/babysit/state.json`. Schema:

```json
{
  "prs": {
    "<repo>#<number>": {
      "last_checked": "2026-03-30T15:00:00Z",
      "head_sha": "abc123",
      "ci_state": "SUCCESS|FAILURE|PENDING",
      "ci_pending_since": "2026-03-30T15:00:00Z",
      "unresolved_comment_ids": ["PRRC_abc"],
      "notified_comment_ids": ["PRRC_abc"]
    }
  }
}
```

- `ci_pending_since`: ISO timestamp when this PR's CI first entered PENDING state (null if not pending)
- `notified_comment_ids`: comment IDs already surfaced to the user — never re-notify these

Create the file if it doesn't exist: `{"prs":{}}`.

#### 3. Discover open PRs

With `--repo`:
```bash
gh pr list --repo <owner/repo> --author @me --state open \
  --json number,title,headRefName,baseRefName,url,headRefOid --limit 100
```

Without `--repo`, use GraphQL across all repos (see PR Discovery section below).

Remove from state any PRs no longer in the open list (merged/closed).

#### 4. Batch-fetch current status

**IMPORTANT: Always fetch ALL discovered PRs, even when all SHAs from Step 3 match state.** `mergeStateStatus`, `ci_state`, and review comments can change independently of `headRefOid`. Skipping this step causes missed rebases and stale CI detection.

One GraphQL call for all discovered PRs:
- `headRefOid`, `mergeable`, `mergeStateStatus`
- `statusCheckRollup { state }`
- `reviewThreads(first:100)` → `isResolved`, comment nodes with `id`, `body`, `author { login }`, `path`, `line`, `createdAt`

#### 5. Determine which PRs need processing

For each PR, compare current data against state. A PR **needs processing** if any of:

| Condition | Action needed |
|-----------|---------------|
| `head_sha` changed | Recheck everything |
| `ci_state` changed to `FAILURE` | Investigate CI |
| `ci_state` is `FAILURE` (same as before) | Re-investigate (may be fixable now) |
| New unresolved comment IDs (not in `unresolved_comment_ids`) | Review new comments |
| `mergeStateStatus` is `BEHIND` or `CONFLICTING` | Rebase |

**Skip the PR entirely if:**
- `head_sha` unchanged AND `ci_state` unchanged AND no new comment IDs AND `mergeStateStatus` is not `BEHIND` or `CONFLICTING`

**Skip only the CI step if:**
- `ci_state` is `PENDING` (same as before) → CI is still running, nothing actionable. Update `ci_pending_since` if not set. Still check review comments.

#### 6. Categorize workers

Split PRs that need processing into two buckets:

- **Read-only workers**: PRs that only need rebase (`gh pr update-branch` has no local files) or comment triage (no auto-fixes). Spawn all in parallel.
- **Code-change workers**: PRs that need CI fixes or trivial review auto-fixes applied locally. Spawn **one at a time** (they share the graft worktree). Wait for each to complete before spawning the next.

To determine which bucket: a PR needs code changes if `ci_state == FAILURE` (may need a fix) or it has unresolved trivial comments. When in doubt, treat as read-only and let the worker self-report if it needs code changes.

#### 7. Spawn workers

**Prerequisite: Step 1's `TeamCreate` MUST have succeeded before reaching this step. If you skipped Step 1 or it failed without recovery, go back and create the team now. Agents spawned with `team_name` will error if the team doesn't exist.**

Create a task for each PR, then spawn its worker Agent (both from the main conversation):

```
TaskCreate(title: "PR #<number>: <title>", description: "started_at: <ISO timestamp>")

Agent(
  team_name: "babysit-<repo-slug>",
  name: "worker-<pr-number>",
  model: "sonnet",
  run_in_background: true,
  prompt: "..." // include all per-PR instructions below + PR-specific data
)
```

Pass to each worker: PR number, repo, branch, base branch, head_sha, ci_state, mergeStateStatus, unresolved thread data (JSON), notified_comment_ids, yolo flag, team name.

Workers have access to `TaskUpdate` and `SendMessage` because they are spawned with `team_name`. They claim their task and report back to the invoking conversation (use `SendMessage(to: "main")` or the conversation receives messages automatically).

Spawn read-only workers all at once. Spawn code-change workers one at a time (wait for previous to complete before spawning next).

#### 8. Collect results

Worker messages are delivered automatically to the main conversation. Each result includes:
- `actions`: list of things done
- `needs_attention`: list of non-trivial items
- `new_head_sha`: SHA after any pushes
- `new_ci_state`: CI state after any re-runs
- `new_unresolved_comment_ids`: current unresolved IDs post-processing

#### 9. Update state + notify

For each PR result received:
- Set `head_sha` = `new_head_sha`
- Set `ci_state` = `new_ci_state`
- Set `ci_pending_since` = existing value if still PENDING, else null
- Set `unresolved_comment_ids` = `new_unresolved_comment_ids`
- Add newly surfaced comment IDs to `notified_comment_ids`

**Notifications** (only for new `needs_attention` items — skip IDs already in `notified_comment_ids`):

See `references/notifications.md` for the cascade. Use title `"Babysit"`. Silent on clean runs.

#### 10. Output report

Only include PRs where something happened or that need attention. Silent for unchanged/clean PRs.

```
## Babysit Report — instacart/carrot

### #123 — "Add login page"
- Rebased onto master
- CI: fixed missing import in auth.ts (re-running)
- Addressed review comment: renamed `foo` → `fooBar` (@reviewer)
- ⚠ Needs attention: architecture question from @reviewer on src/auth.ts

### #456 — "Remove jQuery"
- CI: PENDING (running 8 min)
```

#### 11. Shut down workers

```
SendMessage(to: "worker-<number>", message: {type: "shutdown_request"})
```

Do **not** call `TeamDelete` — the team persists for the next run.

---

## Per-PR Processing (Worker Instructions)

### Step 0: Claim task

```
TaskUpdate(owner: "worker-<number>", status: "in_progress")
```

### Step 1: Rebase

If `mergeStateStatus` is `BEHIND` or `mergeable` is `CONFLICTING`:

```bash
gh pr update-branch <number> --repo <repo> --rebase
```

- Exit 0 → report `rebased`
- Non-zero → report rebase conflict (parse conflicting files from output), add to `needs_attention`, notify

No local worktree needed for rebase.

### Step 2: CI Failures

Only if `ci_state == FAILURE`.

1. Get failing checks:
   ```bash
   gh pr checks <number> --repo <repo>
   ```

2. Fetch logs — try Buildkite MCP first (`mcp__buildkite__get_build`, `mcp__buildkite__read_logs`), fall back to:
   ```bash
   gh run view <run-id> --repo <repo> --log-failed
   ```

3. **Before re-triggering anything**, check if a re-run is already in progress:

   For GitHub Actions: check if the run is already in a `queued` or `in_progress` state — if so, skip re-trigger.

   For Buildkite: use `mcp__buildkite__get_build` to check the build state. Also check child pipelines — if any child build is still `running` or `scheduled`, the parent may still produce results. Skip re-triggering if:
   - The failing Buildkite build's state is `running` or `scheduled`, OR
   - Any child pipeline build for the same commit is still `running` or `scheduled`

   If a re-run is already in progress, report `ci-already-rerunning` in actions and skip.

4. Categorize (only if no re-run already in progress):
   - **Flaky** (non-deterministic, test passed in prior runs): re-run
     ```bash
     gh run rerun <run-id> --repo <repo> --failed
     ```
   - **Code issue** (compile error, lint, failing assertion): attempt fix via worktree (see Worktree Model)
   - **Infra** (timeout, OOM, network): add to `needs_attention`, do not attempt fix

5. For code fixes: make the change in the worktree, commit `Fix CI: <brief description>`, push. Record the new SHA.

6. After pushing: report `fixed-ci: <description>` in actions.

### Step 3: Review Comments

Fetch via GraphQL (use data passed from team lead — no need to re-fetch if already provided).

For each unresolved thread where **last comment is NOT from `bostondv`**:

1. Read the comment body and the referenced code (fetch file content from the branch if needed)

2. Classify using `references/review-classification.md` (triviality section). Trivial → auto-fix in any mode. Non-trivial → auto-fix only in `--yolo` mode.

3. For **trivial** (or any in `--yolo`): apply fix via worktree, commit `Address review: <description>`, push. Then reply:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment-id>/replies \
     -f body="Done — <what was changed>.

   Sent from Claude Code"
   ```
   Record in actions: `replied-to-<comment-id>`.

4. For **non-trivial** (triage mode): add to `needs_attention` with the comment ID, author, path/line, and a one-sentence summary.

### Step 4: Report to team lead

Send via `SendMessage` to the team lead:

```
PR #<number> done.
actions: [<list>]
needs_attention: [<list of {comment_id, author, path, line, summary}>]
new_head_sha: <sha>
new_ci_state: <state>
new_unresolved_comment_ids: [<ids>]
```

Mark task complete: `TaskUpdate(status: "completed")`.

---

## Worktree Model

See `references/worktree-model.md` for full graft worktree instructions (finding project path, setup, key rules).

**Babysit-specific:** Use worktree name `babysit-<repo-slug>` (e.g. `babysit-carrot`). Code-change workers for the same repo run sequentially (enforced by team lead).

---

## PR Discovery (All Repos)

```bash
gh api graphql -f query='
{
  viewer {
    pullRequests(first: 100, states: OPEN, orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes {
        number title headRefName baseRefName url headRefOid
        repository { nameWithOwner }
        mergeable mergeStateStatus
        statusCheckRollup { state }
      }
    }
  }
}'
```

---

## Safety Rules

See `references/worktree-model.md` for worktree safety rules (no user dir modifications, new commits only, verify push auth, discard on failure).

Additional babysit-specific rules:
- **All PR replies include** `Sent from Claude Code`
- **Never merge a PR**, dismiss reviews, or approve your own PR
