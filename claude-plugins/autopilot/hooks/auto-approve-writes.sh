#!/usr/bin/env bash
# auto-approve-writes.sh — PreToolUse hook that auto-approves tool calls
# during active autopilot sessions.
#
# Two modes:
# 1. Active autopilot session → approve ALL tool calls (autonomous execution)
# 2. No active session → approve only Write/Edit/Bash targeting ~/.claude/autopilot/

set -euo pipefail

AUTOPILOT_STATE_DIR="${HOME}/.claude/autopilot"
ACTIVE_SESSIONS="${AUTOPILOT_STATE_DIR}/active-sessions.json"

# Read tool input from stdin
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT="$(cat)"
fi

if [[ -z "$INPUT" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Mode 1: Active autopilot session — approve everything
# ---------------------------------------------------------------------------
if [[ -f "$ACTIVE_SESSIONS" ]]; then
  HAS_ACTIVE=false
  if command -v jq &>/dev/null; then
    # Check for any session with status "active"
    ACTIVE_COUNT="$(jq '[.[] | select(.status == "active")] | length' "$ACTIVE_SESSIONS" 2>/dev/null || echo "0")"
    if (( ACTIVE_COUNT > 0 )); then
      HAS_ACTIVE=true
    fi
  else
    # Fallback: if the file exists and is non-empty and not just "[]"
    if [[ -s "$ACTIVE_SESSIONS" ]] && ! grep -qx '\[\]' "$ACTIVE_SESSIONS" 2>/dev/null; then
      HAS_ACTIVE=true
    fi
  fi

  if $HAS_ACTIVE; then
    echo '{"approved": true}'
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Mode 2: No active session — only approve ops targeting autopilot paths
# ---------------------------------------------------------------------------

# Detect tool type from the hook input
TOOL_NAME=""
if command -v jq &>/dev/null; then
  TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
fi

# For Bash calls, check if the command targets autopilot paths
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=""
  if command -v jq &>/dev/null; then
    COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  else
    COMMAND="$(echo "$INPUT" | grep -oP '"command"\s*:\s*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' || true)"
  fi

  if [[ -z "$COMMAND" ]]; then
    exit 0
  fi

  # Auto-approve any Bash command that references the autopilot state dir
  # Check both the ~ form and the expanded form
  if echo "$COMMAND" | grep -qF "$AUTOPILOT_STATE_DIR"; then
    echo '{"approved": true}'
  elif echo "$COMMAND" | grep -qF '~/.claude/autopilot'; then
    echo '{"approved": true}'
  fi

  exit 0
fi

# For Write/Edit/Read calls, extract the file path
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
else
  FILE_PATH="$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' || true)"
fi

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Auto-approve operations targeting autopilot paths
case "$FILE_PATH" in
  ${AUTOPILOT_STATE_DIR}/*)
    echo '{"approved": true}'
    ;;
  *autopilot.local.md)
    echo '{"approved": true}'
    ;;
esac

exit 0
