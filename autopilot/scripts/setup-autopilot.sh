#!/usr/bin/env bash
# setup-autopilot.sh — Session initialization script.
# Called by the /autopilot command to bootstrap a new session.
# Usage: setup-autopilot.sh <feature_name>

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
  echo "Usage: setup-autopilot.sh <feature_name>" >&2
  exit 1
fi

FEATURE="$1"

# ---------------------------------------------------------------------------
# Generate session ID and create directory
# ---------------------------------------------------------------------------
SESSION_ID="$(generate_session_id "$FEATURE")"
SESSION_DIR="${AUTOPILOT_SESSIONS_DIR}/${SESSION_ID}"

mkdir -p "$SESSION_DIR"

# ---------------------------------------------------------------------------
# Initialize state.json
# ---------------------------------------------------------------------------
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Determine branch name
BRANCH="bostondv/autopilot-${SESSION_ID}"

cat > "${SESSION_DIR}/state.json" <<EOF
{
  "phase": "SPEC",
  "iteration": 0,
  "max_iterations": 10,
  "fix_attempts": 0,
  "max_fix_attempts": 3,
  "review_rounds": 0,
  "max_review_rounds": 2,
  "worktree": false,
  "worktree_path": null,
  "browser_testing": null,
  "feature": "${FEATURE}",
  "branch": "${BRANCH}",
  "session_id": "${SESSION_ID}",
  "created_at": "${NOW}",
  "updated_at": "${NOW}"
}
EOF

# ---------------------------------------------------------------------------
# Create session marker file in working directory
# ---------------------------------------------------------------------------
mkdir -p "${PWD}/.claude"
cat > "${PWD}/${SESSION_MARKER}" <<EOF
---
session_id: ${SESSION_ID}
---
# Autopilot Session

Feature: ${FEATURE}
Session: ${SESSION_ID}
Branch: ${BRANCH}
State: ${SESSION_DIR}/state.json
EOF

# ---------------------------------------------------------------------------
# Register in active sessions
# ---------------------------------------------------------------------------
register_session "$SESSION_ID" "$FEATURE" "$PWD"

# ---------------------------------------------------------------------------
# Output session ID
# ---------------------------------------------------------------------------
echo "$SESSION_ID"
