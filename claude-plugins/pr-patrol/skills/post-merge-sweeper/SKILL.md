---
name: post-merge-sweeper
description: "Scan recently merged PRs for missed/unaddressed review comments, then create follow-up PRs. Invoke: `/post-merge-sweeper --repo owner/repo` or `/loop 30m /post-merge-sweeper --repo owner/repo`"
user-invocable: true
argument-hint: "--repo owner/repo [--since 48h] [--yolo]"
---

# Post-Merge Sweeper

Catch review feedback that slipped through the cracks after merge.

## Execution Model

The **invoking Claude instance** (main conversation) does the setup, then hands off to background agents. `TeamCreate`, `TaskCreate`, and `SendMessage` must be called from the main conversation — background agents don't have these tools unless spawned with `team_name`.

### Invoking Claude — Setup (blocking, but fast)

#### 1. Guard: create or reuse team

**CRITICAL: You MUST call `TeamCreate` here and confirm it succeeds (or handle the "already exists" case below) BEFORE proceeding to any later step. Do NOT skip ahead to spawning agents — agents spawned with `team_name` will fail if the team doesn't exist yet.**

```
TeamCreate(team_name: "sweeper-<repo-slug>")
```
Use repo slug (e.g. `sweeper-carrot` for `instacart/carrot`). Multiple repos → one team per repo.

If `TeamCreate` succeeds → proceed to Step 2.

If `TeamCreate` fails with "team already exists":
- Call `TaskList` on the existing team
- If **any task is `in_progress`** and its `started_at` is **< 20 minutes ago** → **exit as no-op** (previous run still working)
- If tasks are `in_progress` but `started_at` is ≥ 20 minutes ago → those workers likely crashed; reset them to `pending` with `TaskUpdate` and proceed
- If all tasks are `completed` or none exist → proceed with the existing team

#### 2. Load state + discover merged PRs

Read `~/.claude/cache/post-merge-sweeper/seen.json`. Create if it doesn't exist.

Discover merged PRs in the time window, filter already-seen comment IDs.

#### 3. Create tasks and spawn workers

For each PR with unseen candidate comments, create a task and spawn a worker:

```
TaskCreate(title: "Analyze instacart/carrot#<number>", description: "started_at: <ISO timestamp>\n<PR title>\nmergedAt: <ts>\nthreads: <json of candidate threads>\nseen_ids: <json list to skip>")

Agent(
  team_name: "sweeper-<repo-slug>",
  name: "worker-<number>",
  model: "sonnet",
  run_in_background: true,
  prompt: "..." // include all per-PR instructions below + PR-specific data
)
```

Spawn all workers in parallel (sweeper workers are read-only — no worktree conflicts).

#### 4. Collect results

Worker messages are delivered automatically to the main conversation. Each result includes findings (comment ID, author, path, line, classification, suggested fix).

#### 5. Output report + update state

If any findings, output report and mark surfaced comments in `seen.json`. Notify per `references/notifications.md` (title: `"Sweeper"`). Silent on clean sweeps.

#### 6. Shut down workers

```
SendMessage(to: "worker-<number>", message: {type: "shutdown_request"})
```

Do **not** call `TeamDelete` — the team persists for the next run.

### Worker Responsibilities

Each worker:
1. Claims its task via `TaskUpdate(owner: "worker-<number>", status: "in_progress")`
2. Analyzes the PR per the Per-PR Analysis steps below (read-only — fetches file content, checks if concerns were addressed)
3. Reports findings to main conversation via `SendMessage(to: "main")`
4. Marks task complete: `TaskUpdate(status: "completed")`

Workers only read file content — they never write files or create PRs (that's triggered later by user or `--yolo`). No worktree needed for workers.

## Invocation

```
/post-merge-sweeper [--repo owner/repo ...] [--since 3d] [--yolo]
/loop 2h /post-merge-sweeper
/loop 2h /post-merge-sweeper --repo instacart/carrot --since 7d
```

## Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `--repo owner/repo` | Narrow to specific repo(s). Repeatable. | All repos with your merged PRs |
| `--since <duration>` | How far back to look. Format: `Nh` (hours) or `Nd` (days). | `48h` |
| `--yolo` | Auto-create follow-up PRs without asking | Off (report mode) |

## State Tracking

Maintain a seen-comments file to avoid re-surfacing the same comments:

**Path:** `~/.claude/cache/post-merge-sweeper/seen.json`

**Schema:**
```json
{
  "seen": {
    "<repo>#<pr-number>/<comment-id>": {
      "surfaced_at": "2026-03-30T10:00:00Z",
      "status": "surfaced|fixed|dismissed"
    }
  }
}
```

Create the directory and file if they don't exist. Load at the start of each run, save at the end.

## PR Discovery

Find merged PRs authored by the current user within the time window.

**Parse `--since`:** Extract the number and unit. Convert to an ISO date:
```bash
# Example: "48h" → 48 hours ago, "3d" → 3 days ago
SINCE_DATE=$(date -v-48H +%Y-%m-%dT%H:%M:%SZ)  # macOS
# or
SINCE_DATE=$(date -d "48 hours ago" --iso-8601=seconds)  # Linux
```

**Default (all repos):**
```bash
gh api graphql -f query='
{
  viewer {
    pullRequests(first: 100, states: MERGED, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        title
        headRefName
        baseRefName
        mergedAt
        url
        repository {
          nameWithOwner
          defaultBranchRef { name }
        }
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 10) {
              nodes {
                id
                databaseId
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
  }
}'
```

Filter results to only PRs merged after `SINCE_DATE`.

**With `--repo`:**
```bash
gh pr list --repo <owner/repo> --author @me --state merged --json number,title,headRefName,mergedAt,url --limit 50
```
Then filter by `mergedAt` > `SINCE_DATE` and fetch review threads for each.

## Per-PR Analysis

For each merged PR within the time window:

### Step 1: Collect Candidate Comments

Gather comments that might have been missed:

1. **Unresolved threads** — any `reviewThread` where `isResolved` is false
2. **Late comments** — any comment with `createdAt` after the PR's last push:
   ```bash
   # Get the last push timestamp
   LAST_PUSH=$(gh api repos/<owner>/<repo>/pulls/<number>/commits --jq '.[-1].commit.committer.date')
   ```
   Comments created after this timestamp were posted after the author stopped working on the PR.

3. **Skip already-seen** — check each comment's ID against `seen.json`. Skip if already surfaced, fixed, or dismissed.

4. **Apply skip rules** from `references/review-classification.md` (bots, self-comments, praise, hedged comments).

### Step 2: Filter — Was It Actually Addressed?

For each candidate comment, determine if it was addressed in the final merged code even though the thread wasn't resolved:

1. **Fetch the final state of the file** the comment references:
   ```bash
   gh api repos/<owner>/<repo>/contents/<path>?ref=<default-branch> --jq '.content' | base64 -d
   ```

2. **Analyze the comment against the code:**
   - If the comment suggests a specific code change (e.g., "rename X to Y", "add null check here"), check if that change exists in the final code
   - If the comment asks a question, it may have been answered verbally but not in code — keep it as a candidate unless the code clearly addresses the concern
   - If the comment points out a bug and the code at that location has been modified since, it was likely addressed

3. **Confidence scoring** — see `references/review-classification.md` (confidence scoring section). Only keep comments at high or medium confidence.

### Step 3: Classify Severity

Classify using `references/review-classification.md` (severity section). Only surface **meaningful** and **improvement** comments — drop **cosmetic**.

### Step 4: Output Report

Group findings by PR:

```
## Post-Merge Sweep Report

### instacart/carrot#1234 — "Add SSO support" (merged 6h ago)

**2 missed comments found:**

1. **@reviewer** on `src/auth/sso.ts:45` (unresolved thread)
   > "This doesn't handle the case where the SAML response has an expired assertion.
   > Should check `notOnOrAfter` before accepting."
   **Classification:** Bug — missing validation
   **Suggested fix:** Add expiry check before assertion acceptance

2. **@other-reviewer** on `src/auth/sso.ts:112` (posted after last push)
   > "The error message here leaks internal state. Should return a generic
   > 'authentication failed' to the client."
   **Classification:** Security — information leakage
   **Suggested fix:** Replace detailed error with generic message

---

**To fix:** Say "fix it", "fix #1234", or "fix all"
**To dismiss:** Say "dismiss #1234" or "dismiss all"
```

### Step 5: Act on User Response (or `--yolo`)

When the user says "fix it" / "fix all" / "fix #NNN", or when `--yolo` is active:

1. **Set up worktree** using `references/worktree-model.md` with worktree name `sweeper-<repo-slug>`. Checkout the default branch, then create the fix branch:
   ```bash
   git checkout -b bostondv/sweep-<pr-number>
   ```

2. **Apply all fixes** for that PR:
   - Read each file referenced by the comments
   - Make the suggested changes
   - Run available local checks if detectable
   - Commit each logical fix separately:
     ```
     Address review feedback from #NNN: <brief description>
     ```

3. **Push and create PR:**
   ```bash
   git push -u origin bostondv/sweep-<pr-number>
   ```
   ```bash
   gh pr create --repo <repo> --draft \
     --title "Address review feedback from #<pr-number>" \
     --body "$(cat <<'EOF'
   ## Summary

   Follow-up to #<pr-number> — addresses review comments that were not resolved before merge.

   ## Comments addressed

   - [ ] <path>:<line> — <brief description> ([comment](<comment-url>))
   - [ ] <path>:<line> — <brief description> ([comment](<comment-url>))

   Sent from Claude Code
   EOF
   )"
   ```

4. **Update state:** Mark each addressed comment as `fixed` in `seen.json`.

### Step 6: Dismiss

When the user says "dismiss #NNN" or "dismiss all":
- Mark all comments from that PR as `dismissed` in `seen.json`
- They won't be surfaced again

## Notifications

See `references/notifications.md` for the cascade. Use title `"Sweeper"`. Only notify when new missed comments are found. Silent on clean sweeps.

## Safety Rules

See `references/worktree-model.md` for worktree safety rules (no user dir modifications, new commits only, discard on failure).

Additional sweeper-specific rules:
- **Always create draft PRs** — never create ready-for-review PRs
- **All PRs include** `Sent from Claude Code` attribution
- **Never modify the original merged PR** — only create new follow-up PRs
- **Respect dismissals** — once dismissed, a comment never resurfaces
- **One follow-up PR per original PR** — group all fixes from the same source PR together

## Loop Behavior

When running under `/loop`:
- Each invocation is a full scan within the time window
- `seen.json` prevents re-surfacing old findings
- In report mode (no `--yolo`): new findings are output to the conversation + notification
- In `--yolo` mode: new findings are auto-fixed and PRs are created
- Clean sweeps (no new findings) produce no output to reduce noise
