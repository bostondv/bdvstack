---
name: pr-watch
description: Use right after opening a pull request — "opened a PR", "PR is up", "after creating a pull request", "pushed it and opened the PR", "PR created". Registers the PR with the local watchdog and starts the heartbeat that handles CI failures, review comments and conflicts for it. Not for reading a PR, not for reviewing someone else's work.
---

## Paths

`SKILLS_ROOT` is where these skills are installed. It defaults to `~/.codex/skills`
(Codex). On Claude Code, or anywhere else, set it once:

```bash
export SKILLS_ROOT="$HOME/.claude/skills"   # or wherever the skills live
```

Scripts fall back to `$HOME/.codex/skills` when it is unset, so an unmodified Codex
install works with no setup.

# PR watch

You just opened a PR. Register it, start its heartbeat, and go back to what you
were doing. A launchd job polls the PR every 5 minutes for free; the heartbeat
only wakes to handle what actually moved.

This skill is self-contained: its state lives in `$SKILLS_ROOT/pr-watch/state/`,
and it talks to nothing but `gh`, `bk` and git. No other session, service or
queue is involved.

## On PR creation

1. **Register** from the worktree you opened the PR from:

   ```bash
   ${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/register.sh --pr <N> --thread <this thread id>
   ```

   It resolves the repo from `gh`, the branch from the PR, and the worktree from
   where you are. Override with `--repo owner/name`, `--branch name`,
   `--worktree path`, `--pipeline slug`. It prints the key (`owner/repo#N`) and the
   automation name, and fails loudly if the worktree is gone.

2. **Start the heartbeat** on this thread: take `templates/heartbeat.md`, fill in
   `<KEY>`, `<PR>`, `<AUTOMATION>`, create it with `automation_update`
   (`kind: heartbeat`, `rrule: FREQ=MINUTELY;INTERVAL=10`).

3. **One line to the user**: `Watching repo#123 — I'll handle CI and review
   comments, and stop when it merges.`

First run only, if the 5-minute poller isn't installed yet:
`${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/install.sh`.

## The tick

Read, in this order:

- `state/.pr-state/<key>.json` — `pending`, `ciRunning`, `blocked`, `lastSeen`
- `state/pending.json` — escalations you raised that nobody has answered
- `state/events.jsonl` — lines with your `key` after `lastSeen`

**Nothing there and nothing pending** → reply exactly `QUIET`, no other tool calls.
That is the normal outcome.

**Something there** → handle only those events, then
`scripts/status.sh --handled <KEY>`.

Escalations still open in `pending.json` → say them again, briefly, in this thread.
That's the whole reason they're on disk: the app can be closed when you raise one.

Reschedule after every tick (edit `<AUTOMATION>` with `automation_update`):

| Condition | Interval |
|---|---|
| CI running, or `pending` true | 10 min |
| something moved in the last 2h | 30 min |
| quiet over 2h, PR still open | 60 min |

## When you need a decision

Say it here, in this thread: what's broken, what you'd do, what you need decided.
Then mark it so the next tick doesn't repeat it every 30 minutes:

```bash
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/status.sh --block <KEY> --note "one line"
```

That writes `state/pending.json`, so it survives the app being closed and comes
back on the next tick. `--handled` clears it once it's resolved.

## Terminal states

- **Merged or closed** → delete your automation (`automation_update mode="delete"`,
  id `<AUTOMATION>`), remove the entry
  (`scripts/status.sh --handled <KEY>` then delete the key from `state/prs.json`),
  and say one line: `PR <N> is merged, watchdog stopped.`
- **Stale 5 days** (the poller emits `stale`) → delete the automation, same cleanup,
  one line: `PR <N> went quiet after 5 days; still open.`

## Guardrails

- Never force-push. Never merge.
- Never weaken, skip or rewrite a test to get green.
- Draft every review reply in your message. **Never post one**, never resolve
  someone else's thread.
- Max 2 fix attempts per failing check per hour (track in `attempts` in the state
  file), then escalate and leave it until something changes.
- Conflicts: clean rebase onto the base branch only. If resolving needs a decision
  about intent, escalate and stop.
- Touch no PR other than this one.

## Scripts

```bash
# register (from the PR's worktree)
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/register.sh --pr 904995 --thread 01a1c227-...
#   owner/repo#123
#   automation: pr-watch-repo-123

# what the watchdog knows
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/status.sh
# PR                     state    pending  blocked  worktree
# owner/repo#123 OPEN     yes      no       /path/to/your/worktree

# after a tick
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/status.sh --handled owner/repo#123

# needs a decision
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/status.sh --block owner/repo#123 --note "two ways to fix the schema"

# poll by hand (launchd does this every 5 minutes)
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/poll.sh -v

# install / remove the poller
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/install.sh
${SKILLS_ROOT:-$HOME/.codex/skills}/pr-watch/scripts/install.sh --remove
```

## Files

All under `$SKILLS_ROOT/pr-watch/`:

- `config.json` — poll seconds, tick intervals, attempt cap, stale window
- `state/prs.json` — registry, keyed `owner/repo#N`
- `state/events.jsonl` — append-only change log
- `state/pending.json` — open escalations
- `state/.pr-state/<repo>_<n>-<pr>.json` — fingerprint, `pending`, `blocked`, `lastActivity`
