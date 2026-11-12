---
name: writing
description: Rules for anything a human reads: replies, status updates, PR descriptions, docs, commit messages. Check the five hard rules before sending; read the linked files only when the task calls for them.
---

# Writing

## The five that decide it

Check these on every reply, at any length. Five failures, not twelve.

1. **Sentence one names the decision, the outcome, or what changed.** Read it alone. If it says what you looked at, rewrite.
2. **No sentence over 25 words.** Split at the first "and", "but", or "which".
3. **No paragraph over 3 sentences.** The fourth becomes a bullet, a table row, or disappears.
4. **Every reference is a link, and the link text is the name.** `[WEB-52](url)`, never bare `WEB-52`.
5. **No em-dashes.** A comma, a colon, or a full stop.

One or two sentences is a whole reply unless the reader cannot act without more. Do not end on a summary or an offer to help.

## The rest

- **Numbers only when the reader acts on them.** Test tallies, versions, line counts: cut unless they change a decision.
- **Three or more interacting pieces: build the visual before the explanation.** Count services, states, components, steps. HTML for flows, mermaid for labelled graphs.
- **Proposals show old and new side by side**, changed bits marked, one line on what it fixes.
- **No ASCII or box-drawing diagrams.** If it needs a picture, it is HTML or mermaid.
- **First person, plain words.** "I couldn't reproduce it", not "it may not be reproducible". Never utilize, facilitate, leverage, remediate.

## When the task needs more

Read these only when the trigger applies. Paths are relative to this skill.

| Trigger | File |
| --- | --- |
| writing or revising a PR body | `pr-template.md` |
| measuring whether rules changed anything | `eval/README.md` |
