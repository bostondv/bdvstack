# Durable records

Sessions get compacted. Context is not memory. Everything that matters goes on disk, in this folder.

| File | Written by | Rule |
|---|---|---|
| `state/web-platform.md` | Web Platform lead | overwrite at end of every run — current truth only |
| `state/extensibility.md` | Extensibility lead | overwrite at end of every run |
| `LEDGER.md` | everyone | append only, newest at top, never edit history |
| `queue.json` | coordinator | the only thing that reaches you |
| `BRAIN.md` | coordinator | your preferences, updated the moment you correct me |

## What goes where

- A **decision** → `LEDGER.md` (dated, one line, plus why).
- The **current state** of an area → `state/<area>.md`.
- Something **waiting on you** → `queue.json`.
- A **preference** → `BRAIN.md`.

## Session start

Every lead and worker begins by reading its `state/` file and the last 20 lines of `LEDGER.md`. If the file contradicts the ticket tracker, the ticket tracker wins and the file gets fixed.

## Session end

Write `state/`, then append to `LEDGER.md` if a decision was made. A session that ends without writing state is a bug.

## Answering the queue

You do not have to write anything down twice.

- **Press `1`–`4`** when my framing is right and you're just picking. Writes the line to `LEDGER.md` immediately.
- **Press `a` and talk or type** when the framing is wrong, or the answer has a "because". Also writes to `LEDGER.md`.
- **Press `x`** when the item shouldn't exist — my mistake, not your decision.
- **Press `s`** to push it out. Snoozed items come back; they don't disappear.

Leads read `LEDGER.md` and `decisions.json`. A decision you make in the UI is a decision they act on.

## Item format

Every queue item is read in a list and grepped in a terminal. Keep it that way.

| Field | Cap | Rule |
|---|---|---|
| `title` | 90 chars | Start with the ticket or PR id. Ask the question, don't describe the situation. |
| `why` | 260 chars, max 2 sentences | Only the facts that change the decision. |
| `ask` | 140 chars, one sentence | What Boston does when he answers. |
| `options` | 2–4 | Each a verb phrase he can pick without reading further. |

Run `python3 ${SKILLS_ROOT:-$HOME/.codex/skills}/coordinator/app/lint.py` before finishing any run that edits `queue.json`. It fails on overlong fields and on more than two sentences.

Do not put history, mitigations, or background in `why` — that belongs in the state file or the ticket. If the item needs a paragraph, it isn't a decision yet.

## Linear writes

Child issues inside an approved project are allowed. Anything bigger — a new project, a new epic, assigning someone else, changing a date, closing someone's ticket — is a queue proposal first.

Every write gets logged, same run, in `WRITES.md`:

| Field | |
|---|---|
| when | ISO date |
| who | which lead or worker |
| action | CREATED / EDITED / CLOSED |
| id | `EXT-123`, with link |
| why | one line |

The coordinator reads the log at each check-in and tells Boston what changed. For now he wants to stay close to this, so the log is the default and silence is not.

Keep entries to one line. This is a change feed, not a changelog.

## Starting work

A decision about what something *means* — scope, definition of done, priority order — is not permission to begin it. Those are two separate decisions.

Starting work requires an explicit go, and it gets its own ledger line:

`- **2026-11-09** — START — <project or ticket> — <what will be built>`

Until that line exists, a lead's job on that item is analysis and proposals only. No branches, no specs, no commits. If a lead is unsure whether a go was given, it asks the coordinator, and the coordinator asks Boston. Getting this wrong costs someone a worktree full of work nobody asked for.

## Ownership default

Every new Linear project and every new issue gets Boston as lead/assignee. Do not leave them unowned, and do not assign them to anyone else — splitting work is his call. When he names other owners (Thomas on Froth hardening), that's an explicit override, not a pattern.

If a worker starts on a ticket, the ticket gets assigned before the first commit, not after.
