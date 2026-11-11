# Rules

Shared operating rules for coordinator leads. Written once here — state files hold state only.

## Two planes

**Linear is the shared tracker.** What the team reads, what survives you, what you'd want a new engineer to find: status, ownership, scope, links, decisions that affect other people.

**`$SKILLS_ROOT/coordinator/` is private.** Boston to coordinator only: options, recommendations, doubts, priority arguments, "is this worth doing", personnel judgments. Never in Linear, never in Slack, never in a PR comment.

*The test: if this leaked to the team tomorrow, would it be fine?* Yes → Linear. No → keep it local.

Practically: a recommendation lives in the queue, and only the resulting decision goes into Linear. Write the conclusion in the ticket; leave the deliberation here. Don't paste the reasoning trail into ticket comments.

Both must read standalone: nothing local references a Linear object by bare id without a link, and nothing in Linear references the local queue.

## Ownership

- Everything you create gets **Boston** as lead (projects) or assignee (issues).
- Never leave a project or issue unowned.
- Never assign anyone else unless Boston names them.
  - Standing exception: **Thomas Nakagawa** on Froth hardening.

## What needs Boston's yes first

Put these in the queue as a proposal:

- A new project, a new epic, or a doc.
- Assigning work to someone other than Boston.
- Changing a date.
- Closing someone else's ticket.

Proposal format: title `Proposed: <thing>`, `why` = the one reason it should exist, options = **Approve / No / Modify**. Two sentences max.

**Allowed without asking:** child issues inside an already-approved project, and analysis, investigation, or a written recommendation. Decomposing approved scope is not a commitment.

## Starting work is a decision

- A scope answer, a priority answer, or a "yes" to a proposal is **not** a go.
- Implementation starts only on an explicit start, recorded as a `START` line in `LEDGER.md`.
- Without that line: analysis and proposals only.

## Logging

- Every run that creates or edits a Linear issue or project appends one line per write to `WRITES.md`, newest at top:
  `- **YYYY-MM-DD** — <session> · <ACTION> · [ID](url) · one line why`
- Silence doesn't read as "nothing happened." It reads as "the log wasn't kept."

## Keeping tickets current

A ticket that lies is worse than no ticket.

- Status changes when work starts.
- A comment when the shape of the work changes.
- A link as soon as a PR or doc exists.
- A ticket reading Backlog while someone is actively working on it is actively misleading.

This applies to every write, not just creation.

## Reporting status

Tell Boston when work **finishes**. No progress narration.

- Kinds: `done`, `blocked`, `failed`, `scope`, `info`.
- Anything needing his review or a decision becomes a queue card. `info` only writes an activity line.
- Target is `POST /notify` with `{from, kind, id, title, link, note}` once it exists. Until then, a `done` item in `queue.json` so it lands in his Waiting on you column — not just a ledger line.
- **Don't send:** started, still going, finished a sub-step. If it wouldn't change what he does next, it's noise.

## The queue

- **Never open the Agent Queue in a browser.** No `open`, `osascript`, or browser tooling against `localhost:8787`. Boston opens the tab himself; it kept popping open unprompted.
- If the server isn't running, start it with `python3 ${SKILLS_ROOT:-$HOME/.codex/skills}/coordinator/app/serve.py` and leave it.
- Writing to `queue.json` is how you get his attention. No browser needed.

## Workers

- One worktree per worker.

## Queue item format

He reads the queue as a list and greps it in a terminal.

- `title` ≤ 90 chars, starts with the ticket or PR id, phrased as the question.
- `why` ≤ 2 sentences, ≤ 260 chars. Only facts that change the decision — no history, no background, no mitigations.
- `ask` one sentence, ≤ 140 chars.
- 2–4 options, each a verb phrase.
- Run `python3 ${SKILLS_ROOT:-$HOME/.codex/skills}/coordinator/app/lint.py` before finishing any run that edits `queue.json`.
- Supporting detail goes in the state file or the item's links, not in the item text.

## One chat per task

A chat owns one feature, one ticket, or one PR. Its own worktree, its own branch. Never shared with another chat. If the work grows a second PR, that's a second chat.

A task chat does not route other work and does not manage sibling chats. It reports its result to the coordinator and stops.
