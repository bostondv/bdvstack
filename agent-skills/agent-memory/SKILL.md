---
name: agent-memory
description: Use before making a judgment call you may have made before, and before claiming work is done, finished, fixed or verified. Carries Boston's standing preferences (BRAIN.md), operating rules (RULES.md) and the specific mistakes already made (LESSONS.md) so the same correction isn't needed twice.
---

## Paths

`SKILLS_ROOT` is where these skills are installed. It defaults to `~/.codex/skills`
(Codex). On Claude Code, or anywhere else, set it once:

```bash
export SKILLS_ROOT="$HOME/.claude/skills"   # or wherever the skills live
```

Scripts fall back to `$HOME/.codex/skills` when it is unset, so an unmodified Codex
install works with no setup.

# Agent memory

Three files, all next to this one. Read the right one at the right moment —
they exist so Boston stops repeating himself.

| When | Read |
|---|---|
| Starting substantial work | `BRAIN.md` — his preferences and hard rules |
| Any work at all | `RULES.md` — how agents are expected to operate |
| Before claiming done / fixed / verified | `LESSONS.md`, by topic |
| Writing tonight's review | `DREAM.md` — the spec for the nightly pass |

## BRAIN.md

`$SKILLS_ROOT/agent-memory/BRAIN.md`. Read it at the start of anything
substantial. It changes faster than the instruction files and it wins over your
defaults: if it says he never does the work in that thread, or never creates a
ticket without a yes, that is the rule.

Don't read it for a one-line reply. Don't quote it back at him.

## LESSONS.md

`$SKILLS_ROOT/agent-memory/LESSONS.md`. Capped at 30 entries, each citing a
real incident. If it isn't there yet, copy `LESSONS.template.md` to
`LESSONS.md` — the template documents the format and the cap. **Never read the whole file.** Search it for the topic you're
about to touch — `grep -i "<topic>" LESSONS.md` — and read the two or three
entries that match.

Read it before you say something is done, fixed or verified. Every entry there
is a claim that turned out to be wrong, and the pattern repeats: green tests on
the wrong thing, "shipped" without a merge, "verified" without a screenshot.

## lessons/

`$SKILLS_ROOT/agent-memory/lessons/YYYY-MM-DD.md` — the nightly review's
working notes, one file per day. Read one only when you're reconstructing what
happened on a specific day.

## Writing to memory

Don't, unless you were asked to. Preferences Boston states directly belong in
`BRAIN.md` — add them as he says them, in his words. Lessons come from the
nightly review, which writes `lessons/<date>.md` and updates `LESSONS.md`.
Rule changes need his approval; preferences don't.

## Nightly review

`DREAM.md` defines a nightly pass over the day's sessions: at most three lessons, each citing an incident, written to `lessons/`, plus any rule proposals in `proposed/`. It reads sessions, git and CI directly. It depends on nothing outside this skill.
