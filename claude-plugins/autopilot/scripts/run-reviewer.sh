#!/usr/bin/env bash
# run-reviewer.sh — Launches an isolated code reviewer.
# Reads spec + diff, fills reviewer prompt template, pipes to happy/claude,
# and parses the verdict to update session phase.
# Usage: run-reviewer.sh <session_id>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source state management
# shellcheck source=lib/state.sh
source "${SCRIPT_DIR}/lib/state.sh"

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: run-reviewer.sh <session_id>" >&2
  exit 1
fi

SESSION_ID="$1"
SESSION_DIR="$(get_session_dir "$SESSION_ID")"

# ---------------------------------------------------------------------------
# Read inputs
# ---------------------------------------------------------------------------
SPEC_FILE="${SESSION_DIR}/spec.md"
REVIEW_TEMPLATE="${PLUGIN_ROOT}/templates/reviewer-prompt.md"

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "ERROR: Spec file not found: ${SPEC_FILE}" >&2
  exit 1
fi

if [[ ! -f "$REVIEW_TEMPLATE" ]]; then
  echo "ERROR: Reviewer template not found: ${REVIEW_TEMPLATE}" >&2
  exit 1
fi

SPEC="$(cat "$SPEC_FILE")"

# Get diff against main/master
DIFF=""
if git rev-parse --verify main &>/dev/null; then
  DIFF="$(git diff main...HEAD 2>/dev/null || true)"
elif git rev-parse --verify master &>/dev/null; then
  DIFF="$(git diff master...HEAD 2>/dev/null || true)"
else
  DIFF="$(git diff HEAD~1 2>/dev/null || true)"
fi

if [[ -z "$DIFF" ]]; then
  echo "[reviewer] No diff found. Nothing to review." >&2
  update_phase "DONE" "$SESSION_ID"
  exit 0
fi

# ---------------------------------------------------------------------------
# Build reviewer prompt from template
# ---------------------------------------------------------------------------
PROMPT="$(cat "$REVIEW_TEMPLATE")"
PROMPT="${PROMPT//\{\{SPEC\}\}/$SPEC}"
PROMPT="${PROMPT//\{\{DIFF\}\}/$DIFF}"

# ---------------------------------------------------------------------------
# Run reviewer via happy (preferred) or claude
# ---------------------------------------------------------------------------
REVIEWER_CMD=""
if command -v happy &>/dev/null; then
  REVIEWER_CMD="happy"
elif command -v claude &>/dev/null; then
  REVIEWER_CMD="claude"
else
  echo "ERROR: Neither 'happy' nor 'claude' CLI found in PATH." >&2
  exit 1
fi

echo "[reviewer] Running isolated review with ${REVIEWER_CMD}..." >&2

REVIEW_OUTPUT="$(printf '%s' "$PROMPT" | $REVIEWER_CMD -p 2>/dev/null)" || {
  echo "ERROR: Reviewer command failed." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Save review output
# ---------------------------------------------------------------------------
echo "$REVIEW_OUTPUT" > "${SESSION_DIR}/review.md"
echo "[reviewer] Review saved to ${SESSION_DIR}/review.md" >&2

# ---------------------------------------------------------------------------
# Parse verdict
# ---------------------------------------------------------------------------
REVIEW_ROUNDS="$(read_state_field "review_rounds" "$SESSION_ID")"
MAX_REVIEW_ROUNDS="$(read_state_field "max_review_rounds" "$SESSION_ID")"
REVIEW_ROUNDS="${REVIEW_ROUNDS:-0}"
MAX_REVIEW_ROUNDS="${MAX_REVIEW_ROUNDS:-2}"

if echo "$REVIEW_OUTPUT" | grep -qi "APPROVE"; then
  echo "[reviewer] Verdict: APPROVE" >&2
  update_phase "DONE" "$SESSION_ID"
  update_session_status "$SESSION_ID" "completed" "DONE" 2>/dev/null || true
  echo "VERDICT: APPROVE"

elif echo "$REVIEW_OUTPUT" | grep -qi "REQUEST_CHANGES"; then
  increment_review_rounds "$SESSION_ID"
  REVIEW_ROUNDS=$((REVIEW_ROUNDS + 1))

  if (( REVIEW_ROUNDS >= MAX_REVIEW_ROUNDS )); then
    echo "[reviewer] Verdict: REQUEST_CHANGES (max review rounds reached, shipping anyway)" >&2
    update_phase "DONE" "$SESSION_ID"
    update_session_status "$SESSION_ID" "completed" "DONE" 2>/dev/null || true
    echo "VERDICT: REQUEST_CHANGES (max rounds reached — DONE)"
  else
    echo "[reviewer] Verdict: REQUEST_CHANGES (round ${REVIEW_ROUNDS}/${MAX_REVIEW_ROUNDS})" >&2
    update_phase "BUILD" "$SESSION_ID"
    reset_fix_attempts "$SESSION_ID"
    echo "VERDICT: REQUEST_CHANGES (returning to BUILD)"
  fi

else
  echo "[reviewer] Verdict: UNCLEAR (defaulting to DONE)" >&2
  update_phase "DONE" "$SESSION_ID"
  echo "VERDICT: UNCLEAR (defaulting to DONE)"
fi
