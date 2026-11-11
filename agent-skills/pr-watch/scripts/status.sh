#!/bin/bash
# What this skill knows. All local, no server.
#
#   ./status.sh                          table of registered PRs
#   ./status.sh --handled <key>          a tick handled everything: clear pending + blocked
#   ./status.sh --block <key> --note "…" needs a decision: mark blocked, record it in pending.json
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/../state"
TS="$HERE/status.py"

case "${1:-}" in
  --handled)
    KEY="${2:-}"; [ -n "$KEY" ] || { echo "usage: status.sh --handled <key>" >&2; exit 2; }
    python3 "$TS" handled "$STATE" "$KEY" ;;
  --block)
    KEY="${2:-}"; NOTE="${4:-}"
    [ "${3:-}" = "--note" ] || { echo "usage: status.sh --block <key> --note \"what you need\"" >&2; exit 2; }
    [ -n "$KEY" ] && [ -n "$NOTE" ] || { echo "usage: status.sh --block <key> --note \"what you need\"" >&2; exit 2; }
    python3 "$TS" block "$STATE" "$KEY" "$NOTE" ;;
  *)
    python3 "$TS" table "$STATE" ;;
esac
