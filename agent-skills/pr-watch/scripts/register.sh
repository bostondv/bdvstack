#!/bin/bash
# Register a PR with this skill's own registry. Run it right after you open a PR.
#
#   ./register.sh --pr 904995 --thread <thread id> [--worktree <checkout>]
#                 [--branch feature/x] [--repo owner/name] [--pipeline slug]
#
# repo and branch come from the PR itself; worktree defaults to where you are.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$HERE/../state"
REG="$STATE/prs.json"
PR=""; THREAD=""; WORKTREE=""; BRANCH=""; REPO=""; PIPELINE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr) PR="$2"; shift 2 ;;
    --thread) THREAD="$2"; shift 2 ;;
    --worktree) WORKTREE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --pipeline) PIPELINE="$2"; shift 2 ;;
    *) echo "register: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$PR" ] || { echo "register: --pr is required" >&2; exit 2; }
[ -n "$THREAD" ] || { echo "register: --thread is required" >&2; exit 2; }
case "$PR" in ''|*[!0-9]*) echo "register: --pr must be numeric" >&2; exit 2 ;; esac
WORKTREE="${WORKTREE:-$PWD}"

if [ ! -d "$WORKTREE" ]; then
  echo "register: worktree does not exist: $WORKTREE" >&2; exit 3
fi
if ! git -C "$WORKTREE" rev-parse --git-dir >/dev/null 2>&1; then
  echo "register: not a git checkout: $WORKTREE" >&2; exit 3
fi

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
fi
[ -n "$REPO" ] || { echo "register: could not resolve the repo; pass --repo owner/name" >&2; exit 3; }

if [ -z "$BRANCH" ]; then
  BRANCH=$(gh pr view "$PR" --repo "$REPO" --json headRefName -q .headRefName 2>/dev/null)
fi
if [ -z "$BRANCH" ]; then
  BRANCH=$(git -C "$WORKTREE" rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

mkdir -p "$STATE/.pr-state" || exit 1
LOCK="$STATE/.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "register: registry is busy, try again" >&2; exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

REPO="$REPO" PR="$PR" THREAD="$THREAD" WORKTREE="$WORKTREE" BRANCH="$BRANCH" \
PIPELINE="$PIPELINE" REG="$REG" python3 - <<'PY'
import json, os, datetime

reg = os.environ["REG"]
repo, pr = os.environ["REPO"], os.environ["PR"]
key = "%s#%s" % (repo, pr)
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
try:
    data = json.load(open(reg))
except Exception:
    data = {}

entry = data.get(key, {})
entry.update({
    "repo": repo, "pr": pr, "key": key,
    "thread": os.environ["THREAD"],
    "automation": entry.get("automation") or "pr-watch-%s-%s" % (repo.split("/")[-1], pr),
    "pipeline": os.environ.get("PIPELINE") or (repo.split("/")[-1]),
    "worktree": os.environ["WORKTREE"],
    "branch": os.environ["BRANCH"],
    "created": entry.get("created") or now,
    "lastActivity": now,
})
entry.setdefault("attempts", {})
data[key] = entry

tmp = reg + ".tmp"
json.dump(data, open(tmp, "w"), indent=2, sort_keys=True)
os.replace(tmp, reg)
print(key)
print("automation: %s" % entry["automation"])
print("branch: %s" % entry["branch"])
print("worktree: %s" % entry["worktree"])
PY
