#!/bin/bash
# PR watchdog, tier 1. No model, no tokens.
#
# For every PR in the registry: fingerprint it, and only when something moved
# append one line to events.jsonl and set its `pending` flag for the heartbeat.
# Silent otherwise.
#
#   ./poll.sh            normal run (the launchd job calls this every 5 minutes)
#   ./poll.sh -v         say what it did
#   ./poll.sh <key>      poll one entry, e.g. instacart/carrot#904995
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HERE/../state"
PRS="$STATE_DIR/prs.json"
STATE="$STATE_DIR/.pr-state"
EVENTS="$STATE_DIR/events.jsonl"
# everything tunable lives in config.json next to the skill
STALE_DAYS=$(python3 -c 'import json,os
p=os.path.join(os.path.dirname("'"$HERE"'"), "config.json")
try: print(json.load(open(p)).get("staleDays", 5))
except Exception: print(5)')
VERBOSE=0
ONLY=""

for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    *) ONLY="$arg" ;;
  esac
done

say() { [ "$VERBOSE" = 1 ] && echo "$@"; return 0; }
state_path() { echo "$STATE/$(echo "$1" | tr '/' '_' | tr '#' '-').json"; }

mkdir -p "$STATE" "$STATE_DIR" || exit 0

LOCK="$STATE/.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  say "another run is in progress, skipping"; exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ -n "$ONLY" ]; then
  KEY_LIST="$ONLY"
else
  [ -f "$PRS" ] || { say "no prs.json"; exit 0; }
  KEY_LIST=$(python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d={}
print("\n".join(sorted(d)))' "$PRS") || exit 0
fi
[ -z "$KEY_LIST" ] && { say "no PRs registered"; exit 0; }

while IFS= read -r KEY; do
  [ -n "$KEY" ] || continue

  IFS=$'\t' read -r REPO PR BRANCH PIPELINE WORKTREE <<< "$(
    python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1])); e=d.get(sys.argv[2],{})
except Exception: e={}
repo=e.get("repo",""); pr=e.get("pr","")
pipe=e.get("pipeline","") or (repo.split("/")[-1] if repo else "")
print("\t".join([repo, pr, e.get("branch",""), pipe, e.get("worktree","")]))' "$PRS" "$KEY")"

  if [ -z "$REPO" ] || [ -z "$PR" ]; then
    say "$KEY: entry has no repo or pr, skipping"; continue
  fi

  # a vanished worktree is a real problem: say so once, don't guess
  if [ -n "$WORKTREE" ] && [ ! -d "$WORKTREE" ]; then
    SP=$(state_path "$KEY")
    IF_MISSING=$(python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d={}
print("" if d.get("brokenNotified") else "1")' "$SP")
    if [ -n "$IF_MISSING" ]; then
      KEY="$KEY" REPO="$REPO" PR="$PR" WORKTREE="$WORKTREE" STATE_PATH="$SP" EVENTS="$EVENTS" python3 - <<'PY'
import json, os, sys, datetime
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
key, repo, pr = os.environ["KEY"], os.environ["REPO"], os.environ["PR"]
open(os.environ["EVENTS"], "a").write(json.dumps({
    "at": now, "key": key, "repo": repo, "pr": pr, "kind": "broken",
    "error": "worktree is gone: " + os.environ.get("WORKTREE", "")}, sort_keys=True) + "\n")
try:
    d = json.load(open(os.environ["STATE_PATH"]))
except Exception:
    d = {}
d["brokenNotified"] = True
json.dump(d, open(os.environ["STATE_PATH"], "w"), indent=2, sort_keys=True)
PY
    fi
    say "$KEY: worktree missing: $WORKTREE"; continue
  fi

  PR_JSON=$(gh pr view "$PR" --repo "$REPO" --json number,state,isDraft,headRefOid,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,comments,updatedAt 2>/dev/null)
  if [ -z "$PR_JSON" ]; then
    say "$KEY: gh returned nothing (rate limit, or the PR isn't there)"
    continue
  fi

  BUILD_JSON=""
  if [ -n "$BRANCH" ] && [ -n "$PIPELINE" ]; then
    BUILD_JSON=$(bk build list -p "$PIPELINE" --branch "$BRANCH" --limit 1 --json 2>/dev/null)
  fi

  KEY="$KEY" REPO="$REPO" PR="$PR" PR_JSON="$PR_JSON" BUILD_JSON="$BUILD_JSON" \
  STATE_PATH="$(state_path "$KEY")" EVENTS="$EVENTS" STALE_DAYS="$STALE_DAYS" VERBOSE="$VERBOSE" \
  python3 - <<'PY'
import hashlib, json, os, sys, datetime

key, repo, pr = os.environ["KEY"], os.environ["REPO"], os.environ["PR"]
state_path, events_path = os.environ["STATE_PATH"], os.environ["EVENTS"]
stale_days = int(os.environ["STALE_DAYS"])
verbose = os.environ.get("VERBOSE") == "1"

now = datetime.datetime.now(datetime.timezone.utc)
now_s = now.strftime("%Y-%m-%dT%H:%M:%SZ")

try:
    prj = json.loads(os.environ.get("PR_JSON") or "null")
except ValueError:
    sys.exit(0)
if not prj:
    sys.exit(0)

try:
    builds = json.loads(os.environ.get("BUILD_JSON") or "[]")
except ValueError:
    builds = []
build = builds[0] if builds else {}

checks = sorted((c.get("name") or c.get("context") or "", (c.get("conclusion") or c.get("state") or ""))
                for c in (prj.get("statusCheckRollup") or []))
checks_hash = hashlib.sha256(json.dumps(checks, sort_keys=True).encode()).hexdigest()[:16]
comments = prj.get("comments") or []
last_comment = max((c.get("id") or c.get("databaseId") or 0) for c in comments) if comments else 0

try:
    old = json.load(open(state_path))
except Exception:
    old = {}
prev = old.get("fields") or {}
first_sight = not prev

# GitHub computes mergeability lazily; carry the last known value
mergeable = prj.get("mergeable")
merge_state = prj.get("mergeStateStatus")
if mergeable == "UNKNOWN" and prev.get("mergeable"):
    mergeable = prev["mergeable"]
if merge_state in (None, "UNKNOWN") and prev.get("mergeState"):
    merge_state = prev["mergeState"]

fields = {
    "state": prj.get("state"),
    "draft": prj.get("isDraft"),
    "head": prj.get("headRefOid"),
    "mergeable": mergeable,
    "mergeState": merge_state,
    "review": prj.get("reviewDecision"),
    "checks": checks_hash,
    "comment": last_comment,
    "build": [build.get("number"), build.get("state")],
}
fingerprint = hashlib.sha256(json.dumps(fields, sort_keys=True).encode()).hexdigest()
changed = [k for k in fields if prev.get(k) != fields[k]]
# GitHub answering UNKNOWN then the real value is settling, not news
if prev.get("mergeable") in (None, "UNKNOWN") and "mergeable" in changed:
    changed.remove("mergeable")
if prev.get("mergeState") in (None, "UNKNOWN") and "mergeState" in changed:
    changed.remove("mergeState")

dead = prj.get("state") in ("MERGED", "CLOSED")
territory = dict(old)
territory.update({
    "key": key, "repo": repo, "pr": pr,
    "fingerprint": fingerprint,
    "fields": fields,
    "updatedAt": now_s,
    "state": prj.get("state"),
    "ciRunning": build.get("state") in ("running", "scheduled", "creating"),
    "lastSeenCommentId": last_comment,
    "lastSeenBuild": build.get("number"),
})
territory.setdefault("lastActivity", now_s)

events = []
if first_sight and not dead:
    json.dump(territory, open(state_path, "w"), indent=2, sort_keys=True)
    if verbose:
        print("%s: baseline recorded" % key)
    sys.exit(0)

if dead:
    if old.get("state") != prj.get("state"):
        events.append({"at": now_s, "key": key, "repo": repo, "pr": pr,
                       "kind": "closed", "state": prj.get("state")})
elif changed:
    territory["lastActivity"] = now_s
    territory["pending"] = True
    territory["pendingAt"] = now_s
    territory.pop("staleNotified", None)
    events.append({"at": now_s, "key": key, "repo": repo, "pr": pr, "kind": "changed",
                   "changed": changed, "state": prj.get("state"),
                   "build": {"number": build.get("number"), "state": build.get("state")},
                   "checks": [c[0] for c in checks if c[1] in ("FAILURE", "failed", "broken", "timed_out")],
                   "comment": last_comment})
else:
    la = territory.get("lastActivity") or now_s
    age = (now - datetime.datetime.fromisoformat(la.replace("Z", "+00:00"))).days
    if age >= stale_days and not old.get("staleNotified"):
        territory["staleNotified"] = True
        events.append({"at": now_s, "key": key, "repo": repo, "pr": pr, "kind": "stale",
                       "days": age, "note": "no commits, comments, reviews or CI change for %d days" % age})

if not events:
    if verbose:
        print("%s: unchanged" % key)
    sys.exit(0)

with open(events_path, "a", encoding="utf-8") as f:
    for e in events:
        f.write(json.dumps(e, sort_keys=True) + "\n")

tmp = state_path + ".tmp"
json.dump(territory, open(tmp, "w"), indent=2, sort_keys=True)
os.replace(tmp, state_path)
if verbose:
    for e in events:
        print("%s: %s %s" % (key, e["kind"], ",".join(e.get("changed", [])) or e.get("note", "")))
PY
done <<< "$KEY_LIST"
