---
name: writing
description: Rules for anything a human reads: chat replies, status updates, PR descriptions, docs, plans, commit messages, code comments. Applies to every output, however short, and to every revision of one.
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

Applies to everything you send: a one-line reply, a status update, a PR body, a design doc, a commit message, a code comment. There is no minimum length below which this stops applying.

Numbers behind each rule are in `voice/profile.md`, which stays local and is not committed (see `voice/README.md`). The eval that keeps them honest is in `eval/`.

## Answer, then stop

1. **Answer in one or two sentences when that covers it.** The reader decides whether to ask for more.
2. **Expansion is opt-in.** Offer it in a clause; do not ship it unasked.
3. **A caveat survives only if it changes what the reader does next.** Otherwise drop it.
4. **No recap, no closing summary, no sign-off.**

## Shape

5. **Max 25 words per sentence.**
6. **Max 3 sentences per paragraph.** The fourth becomes a bullet, a table row, or gets cut.
7. **Sentence one is the decision, outcome, or recommendation.** Not what you looked at.
8. **Numbers, versions, and test tallies only when the reader acts on them.**
9. **Every reference gets a link, and the name carries it.** `[the page](url)`, never `the page: url`.

## Visuals

10. **Three or more interacting pieces means build the visual first.** Count services, states, components, or steps. At three, it is a picture, not paragraphs.
11. **HTML for flows and anything spatial, mermaid for labelled graphs.** Whichever renders without the reader assembling it in their head.
12. **After the visual, the reply is one line plus the decision.** Point at what to notice; don't restate the picture.
13. **Any proposal shows before and after**: old left, new right, changed bits marked, one line on what it fixes.
14. **No ASCII, box-drawing, or arrow diagrams in code blocks.** If it needs to be a picture, it is HTML or mermaid.

## Voice

15. **Say it like you'd say it.** Contractions, I, we, you. If it wouldn't survive standup, rewrite it.
16. **Start at the trigger or the surprise,** not the definition.
17. **Plain words**: use, help, fix, cut, show. Not utilize, facilitate, remediate, leverage.
18. **Own the uncertainty in first person.** "I couldn't reproduce it."
19. **Delete process narration and restatement.** The finding is the message.
20. **Code comments only for context the code cannot show.** One or two lines, usually why rather than what. A comment that restates the line is deleted, not shortened.

## PR descriptions

Keep the heading template, in this order. Skip the optional ones when there is nothing to put in them.

| Heading | What goes in it | Required |
| --- | --- | --- |
| `## Why` | the problem, the trigger, or the decision behind the change | yes |
| `## What` | what changed and how it works | yes |
| `## Demo` | a screenshot, gif, query, or command that shows it working | optional |
| `## Additional` | links to docs, tickets, designs, notes, known limits | optional |

Fill those sections with the rules above: short sentences, a table when items are parallel, a diagram when three or more things interact. Don't replace the headings with prose.

## Progressive disclosure

Reference these only when the trigger word shows up; don't restate them here.

| Words that pull it in | File |
| --- | --- |
| PR body, reviewer, review comment, merge | `$SKILLS_ROOT/pr-description/SKILL.md` |
| preference, mistake, correction, "you did this before" | `$SKILLS_ROOT/agent-memory/RULES.md`, `LESSONS.md` |
| score, metric, did this improve, eval | `$SKILLS_ROOT/writing/eval/README.md` |
| sound like me, my voice, write this as me | `$SKILLS_ROOT/writing/voice/style-card.md` (read the register that matches the artifact) |

## Where these numbers come from

Every numeric rule traces to `voice/profile.md`, built from 42,762 words of your own writing. That profile and the corpus behind it are local only; the numbers are restated below so the rules stand on their own. No rule here is borrowed from a style guide without saying so.

| Rule | What the corpus shows |
| --- | --- |
| 25-word sentence cap | p90 is 21 words in your PR bodies, 27 in Slack |
| 3 sentences per paragraph | 0.4% of your PR paragraphs go past three |
| answer first | the first ask lands 16.4% into a PR body, not in sentence one |
| no em-dashes | zero in 42,762 words of your own text |
| no please or thanks | zero in 363 prompts |
| plain-word ban list | leverage, utilize, robust, delve, crucial: zero hits in your corpus |
| PR headings | Why / What / Demo / Additional, from your own PR bodies |
| 6 to 12 word median | 6 in PRs, 11 in prompts, 16 in Slack |

## Before sending

Read sentence one. Can the reader state the decision? Then count the longest sentence and the biggest paragraph. Then count interacting pieces: three or more and the picture comes first.
