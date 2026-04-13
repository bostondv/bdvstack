#!/usr/bin/env bash
# auto-approve-writes.sh — PreToolUse hook that auto-approves Write/Edit
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

# Extract the file path from the tool input
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
else
  # Fallback: grep for file_path or path field
  FILE_PATH="$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//' || true)"
fi

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Auto-approve writes to autopilot state/knowledge directories
case "$FILE_PATH" in
  ${AUTOPILOT_STATE_DIR}/*)
    echo '{"approved": true}'
    ;;
esac

exit 0
