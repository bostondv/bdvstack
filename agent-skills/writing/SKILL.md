---
name: writing
description: Rules for anything a human reads: replies, status updates, PR descriptions, docs, commit messages. Twelve rules, each checkable before sending.
---

## Paths

`SKILLS_ROOT` is where these skills are installed. It defaults to `~/.codex/skills`
(Codex). On Claude Code, or anywhere else, set it once:

```bash
export SKILLS_ROOT="$HOME/.claude/skills"   # or wherever the skills live
```

Scripts fall back to `$HOME/.codex/skills` when it is unset, so an unmodified Codex
install works with no setup.

# Writing

Applies to everything sent, at any length.

## Answer first

1. **Sentence one names the decision, the outcome, or what changed.** Read it alone. If the reader learns what happened or what to do, it passes. If it says what you looked at, it fails.
2. **One or two sentences is a whole reply** unless the reader cannot act without more. Longer, say what else exists and let them ask.
3. **The last line is not a summary, a recap, or an offer to help.** End on the last thing worth knowing.

## Shape

4. **No sentence over 25 words.** Split at the first "and", "but", or "which".
5. **No paragraph over 3 sentences.** The fourth is a bullet, a table row, or gone.
6. **Every number, version, or tally is one the reader acts on.** Others go.
7. **Every reference is a link, and the link text is the name.** `[WEB-52](url)`, never bare `WEB-52`; `[the page](url)`, never `the page: url`.

## Visuals

8. **Three or more interacting pieces: build the visual before writing the explanation.** Count services, states, components, steps. HTML for flows, mermaid for labelled graphs.
9. **Proposals show old and new side by side,** changed bits marked, one line on what it fixes.
10. **No ASCII, box-drawing, or arrow diagrams.** If it needs a picture, it is HTML or mermaid.

## Voice

11. **No em-dashes.** Zero. Use a comma, a colon, or a full stop.
12. **First person, plain words.** "I couldn't reproduce it", not "it may not be reproducible". Use, help, fix, cut, show; never utilize, facilitate, leverage, remediate.

## PR descriptions

| Heading | Contents | Required |
| --- | --- | --- |
| `## Why` | the problem, trigger, or decision behind the change | yes |
| `## What` | what changed and how it works | yes |
| `## Demo` | screenshot, gif, query, or command that shows it working | optional |
| `## Additional` | links to docs, tickets, designs, notes, known limits | optional |

Fill those sections with the rules above. Don't replace the headings with prose.

## Sounding like Boston

`voice/style-card.md`, by register. Word choice and stance come from his prompts; structure comes from his PR bodies.
