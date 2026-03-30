#!/usr/bin/env bash
# commit-and-pr.sh — Git workflow automation.
# Stages, commits, pushes, and creates a draft PR.
# Usage: commit-and-pr.sh <session_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source state management
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: commit-and-pr.sh <session_id>" >&2
  exit 1
fi

SESSION_ID="$1"
SESSION_DIR="$(get_session_dir "$SESSION_ID")"
STATE_FILE="$(get_state_file "$SESSION_ID")"

# ---------------------------------------------------------------------------
# Read state
# ---------------------------------------------------------------------------
FEATURE="$(read_state_field "feature" "$SESSION_ID")"
BRANCH="$(read_state_field "branch" "$SESSION_ID")"

if [[ -z "$FEATURE" || -z "$BRANCH" ]]; then
  echo "ERROR: Missing feature or branch in state.json" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Ensure we're on the correct branch
# ---------------------------------------------------------------------------
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  # Check if branch exists
  if git rev-parse --verify "$BRANCH" &>/dev/null; then
    git checkout "$BRANCH"
  else
    git checkout -b "$BRANCH"
  fi
fi

# ---------------------------------------------------------------------------
# Stage and commit
# ---------------------------------------------------------------------------
git add -A

# Check if there are changes to commit
if git diff --cached --quiet; then
  echo "[commit-and-pr] No changes to commit." >&2
else
  COMMIT_MSG="feat: ${FEATURE}

Autopilot session: ${SESSION_ID}"

  git commit -m "$(cat <<EOF
${COMMIT_MSG}
EOF
)"
  echo "[commit-and-pr] Committed changes." >&2
fi

# ---------------------------------------------------------------------------
# Push to remote
# ---------------------------------------------------------------------------
git push -u origin "$BRANCH" 2>&1 || {
  echo "[commit-and-pr] Push failed, attempting to set upstream and retry." >&2
  git push --set-upstream origin "$BRANCH" 2>&1
}
echo "[commit-and-pr] Pushed to origin/${BRANCH}." >&2

# ---------------------------------------------------------------------------
# Create draft PR
# ---------------------------------------------------------------------------
PR_TITLE="feat: ${FEATURE}"

# Build PR body from spec if available
PR_BODY="Autopilot session: ${SESSION_ID}"
SPEC_FILE="${SESSION_DIR}/spec.md"
if [[ -f "$SPEC_FILE" ]]; then
  SPEC_CONTENT="$(cat "$SPEC_FILE")"
  PR_BODY="$(cat <<EOF
## Summary

${SPEC_CONTENT}

---
Autopilot session: \`${SESSION_ID}\`
EOF
)"
fi

# Check if PR already exists — use --head flag for worktree compatibility
EXISTING_PR="$(gh pr view "$BRANCH" --json url --jq '.url' 2>/dev/null || true)"

if [[ -n "$EXISTING_PR" ]]; then
  echo "[commit-and-pr] PR already exists: ${EXISTING_PR}" >&2
  PR_URL="$EXISTING_PR"
else
  # Use --head to explicitly specify the branch (required in worktree context)
  PR_URL="$(gh pr create --draft \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "$(cat <<EOF
${PR_BODY}
EOF
)" 2>&1)"
  echo "[commit-and-pr] Created draft PR: ${PR_URL}" >&2
fi

# ---------------------------------------------------------------------------
# Update state with PR URL
# ---------------------------------------------------------------------------
write_state_field "pr_url" "$PR_URL" "$SESSION_ID"
update_phase "REVIEW" "$SESSION_ID"

echo "[commit-and-pr] Done. PR: ${PR_URL}"
