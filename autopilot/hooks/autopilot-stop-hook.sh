#!/usr/bin/env bash
# autopilot-stop-hook.sh — The autonomous loop engine.
# Registered as a Stop event hook. Reads stdin JSON, checks session state,
# and either allows exit (0) or blocks with a continuation prompt (exit 2).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source state management
# shellcheck source=../scripts/lib/state.sh
source "${PLUGIN_ROOT}/scripts/lib/state.sh"

# ---------------------------------------------------------------------------
# Read hook input from stdin
# ---------------------------------------------------------------------------
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT="$(cat)"
fi

# Extract transcript_path if available (for promise scanning)
TRANSCRIPT_PATH=""
if [[ -n "$INPUT" ]]; then
  if _has_jq; then
    TRANSCRIPT_PATH="$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  fi
fi

# ---------------------------------------------------------------------------
# Check for active session
# ---------------------------------------------------------------------------
SESSION_ID="$(get_active_session_id)"

if [[ -z "$SESSION_ID" ]]; then
  # No active autopilot session — allow normal exit
  exit 0
fi

SESSION_DIR="$(get_session_dir "$SESSION_ID")"
STATE_FILE="$(get_state_file "$SESSION_ID")"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[autopilot] State file missing for session ${SESSION_ID}, allowing exit." >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Read current state
# ---------------------------------------------------------------------------
PHASE="$(read_state_field "phase" "$SESSION_ID")"
ITERATION="$(read_state_field "iteration" "$SESSION_ID")"
MAX_ITERATIONS="$(read_state_field "max_iterations" "$SESSION_ID")"
FIX_ATTEMPTS="$(read_state_field "fix_attempts" "$SESSION_ID")"
MAX_FIX_ATTEMPTS="$(read_state_field "max_fix_attempts" "$SESSION_ID")"
REVIEW_ROUNDS="$(read_state_field "review_rounds" "$SESSION_ID")"
MAX_REVIEW_ROUNDS="$(read_state_field "max_review_rounds" "$SESSION_ID")"

# Defaults
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
FIX_ATTEMPTS="${FIX_ATTEMPTS:-0}"
MAX_FIX_ATTEMPTS="${MAX_FIX_ATTEMPTS:-3}"
REVIEW_ROUNDS="${REVIEW_ROUNDS:-0}"
MAX_REVIEW_ROUNDS="${MAX_REVIEW_ROUNDS:-2}"

# ---------------------------------------------------------------------------
# Terminal phases — allow exit
# ---------------------------------------------------------------------------
case "$PHASE" in
  DONE|CANCELLED|SPEC)
    update_session_status "$SESSION_ID" "completed" "$PHASE" 2>/dev/null || true
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Iteration limit check
# ---------------------------------------------------------------------------
if (( ITERATION >= MAX_ITERATIONS )); then
  echo "[autopilot] Max iterations (${MAX_ITERATIONS}) reached. Completing." >&2
  set_phase "DONE" "$SESSION_ID"
  update_session_status "$SESSION_ID" "completed" "DONE" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------------------
# Promise tag scanning
# ---------------------------------------------------------------------------
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  # Look for <promise> tag indicating completion
  if grep -q '<promise>' "$TRANSCRIPT_PATH" 2>/dev/null; then
    echo "[autopilot] Promise tag found in transcript. Marking DONE." >&2
    set_phase "DONE" "$SESSION_ID"
    update_session_status "$SESSION_ID" "completed" "DONE" 2>/dev/null || true
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Active phase — build continuation prompt and block exit
# ---------------------------------------------------------------------------
increment_iteration "$SESSION_ID"

# Phase-specific continuation messages
# All phases delegate to the phase-runner skill which has concrete orchestration recipes.
CONTINUATION=""
case "$PHASE" in
  EXPLORE)
    CONTINUATION="Continue autopilot session ${SESSION_ID}. Session directory: ${SESSION_DIR}. Plugin root: ${PLUGIN_ROOT}. Current phase: EXPLORE. Invoke the phase-runner skill to execute the EXPLORE phase. Execute it immediately — do not wait."
    ;;
  BUILD)
    CONTINUATION="Continue autopilot session ${SESSION_ID}. Session directory: ${SESSION_DIR}. Plugin root: ${PLUGIN_ROOT}. Current phase: BUILD (iteration ${ITERATION}/${MAX_ITERATIONS}). Invoke the phase-runner skill to execute the BUILD phase. Execute it immediately — do not wait."
    ;;
  VERIFY)
    CONTINUATION="Continue autopilot session ${SESSION_ID}. Session directory: ${SESSION_DIR}. Plugin root: ${PLUGIN_ROOT}. Current phase: VERIFY. Invoke the phase-runner skill to execute the VERIFY phase. This runs directly in the main session — do NOT spawn agents for quality gates. Execute it immediately."
    ;;
  FIX)
    CONTINUATION="Continue autopilot session ${SESSION_ID}. Session directory: ${SESSION_DIR}. Plugin root: ${PLUGIN_ROOT}. Current phase: FIX (attempt $((FIX_ATTEMPTS + 1))/${MAX_FIX_ATTEMPTS}). Invoke the phase-runner skill to execute the FIX phase. Execute it immediately — do not wait."
    ;;
  COMMIT)
    CONTINUATION="Continue autopilot session ${SESSION_ID}. Session directory: ${SESSION_DIR}. Plugin root: ${PLUGIN_ROOT}. Current phase: COMMIT. Invoke the phase-runner skill to execute the COMMIT phase. This runs directly in the main session — stage, commit, push, create draft PR. Execute it immediately."
    ;;
  REVIEW)
    CONTINUATION="Continue autopilot session ${SESSION_ID}. Session directory: ${SESSION_DIR}. Plugin root: ${PLUGIN_ROOT}. Current phase: REVIEW (round $((REVIEW_ROUNDS + 1))/${MAX_REVIEW_ROUNDS}). Invoke the phase-runner skill to execute the REVIEW phase. Execute it immediately — do not wait."
    ;;
  *)
    echo "[autopilot] Unknown phase: ${PHASE}. Allowing exit." >&2
    exit 0
    ;;
esac

update_session_status "$SESSION_ID" "active" "$PHASE" 2>/dev/null || true

# Output blocking response as JSON to stdout
if _has_jq; then
  jq -n \
    --arg decision "block" \
    --arg reason "Autopilot phase: ${PHASE}" \
    --arg msg "$CONTINUATION" \
    '{"decision": $decision, "reason": $reason, "updatedUserMessage": $msg}'
else
  # Manual JSON construction
  # Escape special chars in continuation message
  ESCAPED_CONTINUATION="$(printf '%s' "$CONTINUATION" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"decision":"block","reason":"Autopilot phase: %s","updatedUserMessage":"%s"}\n' \
    "$PHASE" "$ESCAPED_CONTINUATION"
fi

# Exit 2 to block the stop and continue the loop
exit 2
