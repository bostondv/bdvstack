#!/usr/bin/env bash
# state.sh — Core state management library for autopilot sessions
# Sourced by all other scripts. Provides helpers for reading/writing session state.

set -euo pipefail

AUTOPILOT_HOME="${HOME}/.claude/autopilot"
AUTOPILOT_SESSIONS_DIR="${AUTOPILOT_HOME}/sessions"
ACTIVE_SESSIONS_FILE="${AUTOPILOT_HOME}/active-sessions.json"
SESSION_MARKER=".claude/autopilot.local.md"

# ---------------------------------------------------------------------------
# JSON helpers — prefer jq, fall back to sed/grep
# ---------------------------------------------------------------------------

_has_jq() {
  command -v jq &>/dev/null
}

_json_read_field() {
  # Usage: _json_read_field <file> <field>
  local file="$1" field="$2"
  if _has_jq; then
    jq -r ".[\"${field}\"] // empty" "$file" 2>/dev/null
  else
    # Fallback: simple sed extraction for flat JSON
    sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p" "$file" | head -1
  fi
}

_json_write_field() {
  # Usage: _json_write_field <file> <field> <value>
  local file="$1" field="$2" value="$3"

  if _has_jq; then
    # Auto-detect JSON type
    local jq_expr
    case "$value" in
      true|false)       jq_expr=".\"${field}\" = ${value}" ;;
      ''|*[!0-9]*)      jq_expr=".\"${field}\" = \"${value}\"" ;;  # string
      *)                jq_expr=".\"${field}\" = ${value}" ;;       # number
    esac
    local tmp
    tmp=$(jq "$jq_expr" "$file") && printf '%s\n' "$tmp" > "$file"
  else
    # Fallback: sed in-place replacement (handles strings, numbers, booleans)
    local escaped_value
    escaped_value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')
    # Detect type for proper quoting
    case "$value" in
      true|false|[0-9]*)
        sed -i.bak "s/\"${field}\"[[:space:]]*:[[:space:]]*[^,}]*/\"${field}\": ${escaped_value}/" "$file"
        ;;
      *)
        sed -i.bak "s/\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"${field}\": \"${escaped_value}\"/" "$file"
        ;;
    esac
    rm -f "${file}.bak"
  fi
}

# ---------------------------------------------------------------------------
# Session directory helpers
# ---------------------------------------------------------------------------

get_session_dir() {
  # Usage: get_session_dir [session_id]
  # If no session_id given, reads from active session marker
  local sid="${1:-$(get_active_session_id)}"
  if [[ -z "$sid" ]]; then
    echo "ERROR: No session ID available" >&2
    return 1
  fi
  echo "${AUTOPILOT_SESSIONS_DIR}/${sid}"
}

get_state_file() {
  local session_dir
  session_dir="$(get_session_dir "${1:-}")"
  echo "${session_dir}/state.json"
}

# ---------------------------------------------------------------------------
# State read/write
# ---------------------------------------------------------------------------

read_state() {
  local state_file
  state_file="$(get_state_file "${1:-}")"
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo "ERROR: State file not found: ${state_file}" >&2
    return 1
  fi
}

read_state_field() {
  # Usage: read_state_field <field> [session_id]
  local field="$1"
  local state_file
  state_file="$(get_state_file "${2:-}")"
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: State file not found: ${state_file}" >&2
    return 1
  fi
  _json_read_field "$state_file" "$field"
}

write_state_field() {
  # Usage: write_state_field <field> <value> [session_id]
  local field="$1" value="$2"
  local state_file
  state_file="$(get_state_file "${3:-}")"
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: State file not found: ${state_file}" >&2
    return 1
  fi
  _json_write_field "$state_file" "$field" "$value"
  # Always bump updated_at
  if [[ "$field" != "updated_at" ]]; then
    _json_write_field "$state_file" "updated_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
}

# ---------------------------------------------------------------------------
# Phase management
# ---------------------------------------------------------------------------

set_phase() {
  # Usage: set_phase <phase> [session_id]
  write_state_field "phase" "$1" "${2:-}"
}

update_phase() {
  # Usage: update_phase <new_phase> [session_id]
  local new_phase="$1"
  local sid="${2:-}"
  local old_phase
  old_phase="$(read_state_field "phase" "$sid")"
  set_phase "$new_phase" "$sid"
  echo "[autopilot] Phase transition: ${old_phase} -> ${new_phase}" >&2
}

# ---------------------------------------------------------------------------
# Counter helpers
# ---------------------------------------------------------------------------

increment_iteration() {
  local sid="${1:-}"
  local current
  current="$(read_state_field "iteration" "$sid")"
  current="${current:-0}"
  write_state_field "iteration" "$(( current + 1 ))" "$sid"
}

increment_fix_attempts() {
  local sid="${1:-}"
  local current
  current="$(read_state_field "fix_attempts" "$sid")"
  current="${current:-0}"
  write_state_field "fix_attempts" "$(( current + 1 ))" "$sid"
}

increment_review_rounds() {
  local sid="${1:-}"
  local current
  current="$(read_state_field "review_rounds" "$sid")"
  current="${current:-0}"
  write_state_field "review_rounds" "$(( current + 1 ))" "$sid"
}

reset_fix_attempts() {
  write_state_field "fix_attempts" "0" "${1:-}"
}

# ---------------------------------------------------------------------------
# Session ID / marker file
# ---------------------------------------------------------------------------

get_active_session_id() {
  # Reads session_id from .claude/autopilot.local.md frontmatter in CWD
  local marker="${PWD}/${SESSION_MARKER}"
  if [[ ! -f "$marker" ]]; then
    return 0  # No active session — not an error
  fi
  # Extract session_id from YAML frontmatter (avoid nested braces — BSD sed compat)
  sed -n '/^---$/,/^---$/p' "$marker" | grep '^session_id:' | sed 's/^session_id:[[:space:]]*//' | head -1
}

generate_session_id() {
  # Usage: generate_session_id <feature_name>
  # Produces: slugified-name-6charhash
  local feature="$1"
  # Slugify: lowercase, replace non-alnum with hyphens, collapse, trim
  local slug
  slug=$(printf '%s' "$feature" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
  # Truncate slug to 40 chars
  slug="${slug:0:40}"
  # Generate 6-char hash from feature + timestamp
  local hash
  if command -v md5sum &>/dev/null; then
    hash=$(printf '%s-%s' "$feature" "$(date +%s%N)" | md5sum | head -c 6)
  elif command -v md5 &>/dev/null; then
    hash=$(printf '%s-%s' "$feature" "$(date +%s%N)" | md5 | head -c 6)
  else
    hash=$(printf '%06x' $((RANDOM * RANDOM)) | head -c 6)
  fi
  echo "${slug}-${hash}"
}

# ---------------------------------------------------------------------------
# Multi-session registry
# ---------------------------------------------------------------------------

_ensure_active_sessions_file() {
  mkdir -p "$(dirname "$ACTIVE_SESSIONS_FILE")"
  if [[ ! -f "$ACTIVE_SESSIONS_FILE" ]]; then
    echo '[]' > "$ACTIVE_SESSIONS_FILE"
  fi
}

register_session() {
  # Usage: register_session <session_id> <feature> <worktree_path>
  local session_id="$1" feature="$2" worktree_path="$3"
  _ensure_active_sessions_file

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if _has_jq; then
    local tmp
    tmp=$(jq --arg sid "$session_id" --arg feat "$feature" --arg wt "$worktree_path" --arg ts "$now" \
      '. + [{"session_id": $sid, "feature": $feat, "worktree": $wt, "status": "active", "phase": "SPEC", "started_at": $ts, "updated_at": $ts}]' \
      "$ACTIVE_SESSIONS_FILE")
    printf '%s\n' "$tmp" > "$ACTIVE_SESSIONS_FILE"
  else
    # Fallback: append JSON manually
    local content
    content=$(cat "$ACTIVE_SESSIONS_FILE")
    if [[ "$content" == "[]" ]]; then
      printf '[{"session_id":"%s","feature":"%s","worktree":"%s","status":"active","phase":"SPEC","started_at":"%s","updated_at":"%s"}]\n' \
        "$session_id" "$feature" "$worktree_path" "$now" "$now" > "$ACTIVE_SESSIONS_FILE"
    else
      # Remove trailing ] and append
      sed -i.bak 's/]$//' "$ACTIVE_SESSIONS_FILE"
      printf ',{"session_id":"%s","feature":"%s","worktree":"%s","status":"active","phase":"SPEC","started_at":"%s","updated_at":"%s"}]\n' \
        "$session_id" "$feature" "$worktree_path" "$now" "$now" >> "$ACTIVE_SESSIONS_FILE"
      rm -f "${ACTIVE_SESSIONS_FILE}.bak"
    fi
  fi
}

update_session_status() {
  # Usage: update_session_status <session_id> <status> <phase>
  local session_id="$1" status="$2" phase="$3"
  _ensure_active_sessions_file

  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if _has_jq; then
    local tmp
    tmp=$(jq --arg sid "$session_id" --arg st "$status" --arg ph "$phase" --arg ts "$now" \
      'map(if .session_id == $sid then .status = $st | .phase = $ph | .updated_at = $ts else . end)' \
      "$ACTIVE_SESSIONS_FILE")
    printf '%s\n' "$tmp" > "$ACTIVE_SESSIONS_FILE"
  else
    # Fallback: simple sed updates (fragile but functional)
    echo "WARN: update_session_status without jq may be unreliable" >&2
  fi
}

get_active_sessions() {
  _ensure_active_sessions_file
  if _has_jq; then
    jq '[.[] | select(.status == "active")]' "$ACTIVE_SESSIONS_FILE"
  else
    cat "$ACTIVE_SESSIONS_FILE"
  fi
}
