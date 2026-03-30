---
name: post-merge-sweeper
description: Scan recently merged PRs for review comments that were missed or unaddressed, then create follow-up PRs to fix them. Designed for use with /loop (e.g., /loop 2h /post-merge-sweeper).
user-invocable: true
---

# Post-Merge Sweeper

Catch review feedback that slipped through the cracks after merge.

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

4. **Skip bot comments** — ignore comments from known bots (dependabot, renovate, github-actions, etc.)

5. **Skip your own comments** — ignore comments authored by you (the PR author).

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

3. **Confidence scoring** — only keep comments where you have **reasonable confidence** they were missed:
   - **High confidence (keep):** Comment suggests specific change, change is not present in final code
   - **High confidence (keep):** Comment points out a bug, code is unchanged
   - **Medium confidence (keep):** Comment raises architectural concern, no evidence it was addressed
   - **Low confidence (drop):** Comment is a question that may have been answered in conversation
   - **Low confidence (drop):** Comment is a nitpick (style-only, subjective preference)
   - **Low confidence (drop):** Comment says "nit:", "optional:", "take it or leave it", or similar hedging language
   - **Drop:** Comment is praise ("nice!", "LGTM", "good call")

### Step 3: Classify Severity

For comments that pass the filter, classify:

- **Meaningful** (keep): bug, logic error, security concern, missing error handling, missing test, incorrect behavior, wrong type, data loss risk
- **Improvement** (keep): performance issue, better API usage, missing validation, readability concern with substance
- **Cosmetic** (drop): style preferences already merged, formatting on merged code, naming preferences that are subjective

Only surface **meaningful** and **improvement** comments.

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

1. **Clone the repo:**
   ```bash
   WORK=$(mktemp -d)
   cd "$WORK"
   gh repo clone <repo> . -- --depth=50
   git checkout <default-branch>
   git pull
   ```

2. **Create a branch:**
   ```bash
   GITHUB_USER="${GITHUB_USERNAME:-$(whoami)}"
   git checkout -b "$GITHUB_USER/sweep-<pr-number>"
   ```

3. **Apply all fixes** for that PR:
   - Read each file referenced by the comments
   - Make the suggested changes
   - Run available local checks if detectable
   - Commit each logical fix separately:
     ```
     Address review feedback from #NNN: <brief description>
     ```

4. **Push and create PR:**
   ```bash
   git push -u origin "$GITHUB_USER/sweep-<pr-number>"
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

5. **Update state:** Mark each addressed comment as `fixed` in `seen.json`.

### Step 6: Dismiss

When the user says "dismiss #NNN" or "dismiss all":
- Mark all comments from that PR as `dismissed` in `seen.json`
- They won't be surfaced again

## Notifications

Use a cascade — try each method, use the first that works:

1. `cmux notify --title "Sweeper" --body "<message>"` (if `$CMUX_WORKSPACE_ID` is set and `cmux` exists)
2. `tmux display-message "Sweeper: <message>"` (if `$TMUX` is set)
3. `osascript -e 'display notification "<message>" with title "Sweeper"'` (macOS fallback)
4. Console output only (always happens regardless)

Only notify when new missed comments are found. Don't notify on clean sweeps.

## Safety Rules

- **All code changes happen in temp directories** — never modify the user's working directory
- **Always create draft PRs** — never create ready-for-review PRs
- **All PRs include** `Sent from Claude Code` attribution
- **Never modify the original merged PR** — only create new follow-up PRs
- **If a fix attempt fails** (tests don't pass), report it instead of pushing broken code
- **Respect dismissals** — once dismissed, a comment never resurfaces
- **One follow-up PR per original PR** — group all fixes from the same source PR together

## Loop Behavior

When running under `/loop`:
- Each invocation is a full scan within the time window
- `seen.json` prevents re-surfacing old findings
- In report mode (no `--yolo`): new findings are output to the conversation + notification
- In `--yolo` mode: new findings are auto-fixed and PRs are created
- Clean sweeps (no new findings) produce no output to reduce noise
