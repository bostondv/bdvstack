#!/usr/bin/env bash
# auto-approve-writes.sh — PreToolUse hook that auto-approves Write/Edit/Bash
# calls targeting autopilot's own state and knowledge directories.
# Returns {"approved": true} for matching paths, empty otherwise.

set -euo pipefail

AUTOPILOT_STATE_DIR="${HOME}/.claude/autopilot"

# Read tool input from stdin
INPUT=""
if [[ ! -t 0 ]]; then
  INPUT="$(cat)"
fi

if [[ -z "$INPUT" ]]; then
  exit 0
fi

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

  # Auto-approve Bash commands that only target autopilot state dir
  # Match: mkdir, touch, cp, mv, cat, echo/printf redirects to autopilot paths
  if echo "$COMMAND" | grep -qP "(^|\s|&&|\|\||;)\s*(mkdir|touch|cp|mv|cat|echo|printf|tee|rm)\b" && \
     echo "$COMMAND" | grep -qF "$AUTOPILOT_STATE_DIR"; then
    echo '{"approved": true}'
  fi

  exit 0
fi

# For Write/Edit calls, extract the file path
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
else
  FILE_PATH="$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' || true)"
fi

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Auto-approve writes to:
# 1. ~/.claude/autopilot/ — session state, knowledge, journal, active-sessions
# 2. */.claude/autopilot.local.md — project-local session marker file
case "$FILE_PATH" in
  ${AUTOPILOT_STATE_DIR}/*)
    echo '{"approved": true}'
    ;;
  */.claude/autopilot.local.md)
    echo '{"approved": true}'
    ;;
esac

exit 0
