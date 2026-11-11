Watchdog tick for `<KEY>` (PR `<PR>`). One tick, then reschedule yourself.

**1. Is there anything?** Read these three, nothing else:
- `$SKILLS_ROOT/pr-watch/state/.pr-state/<KEY>.json` for `pending`, `ciRunning`, `blocked`
- `$SKILLS_ROOT/pr-watch/state/pending.json` for escalations still open
- `$SKILLS_ROOT/pr-watch/state/events.jsonl` for lines with `"key": "<KEY>"` after `lastSeen`

Nothing there and nothing pending → reply exactly `QUIET`. No other tool calls.

**2. Handle only those events.**
- `closed` → delete automation `<AUTOMATION>`, remove the entry, one line: `PR <PR> is
  <merged|closed>, watchdog stopped.` Stop.
- `stale` → delete the automation, remove the entry, one line: `PR <PR> went quiet
  after 5 days; still open.` Stop.
- `changed` with failing `checks` → `bk build view <n> -p <pipeline> --json` for job
  ids, `bk job log <job-id> --agent` for the failing job. Mechanical fixes only
  (lint, format, types, snapshot, schema regen, flaky retest). Max 2 attempts per
  check per hour in `attempts`; at the cap → escalate and stop.
- `changed` with a new `comment` → `gh pr view <PR> --json comments`, read only
  comments newer than `lastSeenCommentId`. Fix clear ones, push. Draft replies in
  your message; never post.
- `changed` with `mergeState` CONFLICTING → clean rebase only.
- Any escalation open in `pending.json` → restate it here in one line.

**3. Need a decision?** Say it in this thread — what's broken, what you'd do, what
you need — then
`${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/status.sh --block <KEY> --note "<one line>"`.

**4. Close out.** `${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/status.sh --handled <KEY>`, and
record `lastSeen` in the state file (newest event `at` you handled).

**5. Reschedule.** CI running or `pending` → 10 min. Moved in the last 2h → 30 min.
Quiet → 60 min. `automation_update` on `<AUTOMATION>`.

Never force-push, merge, weaken a test, post a review reply, or touch another PR.
Report only what you changed.
