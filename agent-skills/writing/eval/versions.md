# Arms and how to test a change

`rewrites/current` is the rules in force. `archive/` holds what came before, kept only so a change can be compared against history.

| Arm | What it changed | Words | Flesch | PR headings |
| --- | --- | ---: | ---: | ---: |
| baseline | the AGENTS.md section as it stood | 386 | 65.4 | 50% |
| archive/v1 | answer first, sentence and paragraph caps, tables, links | 180 | 66.8 | 0% |
| archive/v2 | added answer-then-stop, the visual trigger, before/after, no ASCII | 157 | 71.1 | 0% |
| current | added the PR heading template, enforced links, readability pass | 155 | 78.1 | 100% |

## Changing a rule

1. Copy `rewrites/current` to `rewrites/candidate`.
2. Change the rule in `SKILL.md`.
3. `./run.sh candidate`.
4. Read the table before the prose. It is not an improvement if words go up, Flesch goes down, PR headings drop below 100%, unlinked refs go above 0, or an em-dash appears.
5. If it wins, replace `current` with `candidate` and move the old `current` into `archive/` under the date.

## Regressions

More words, lower Flesch, PR headings under 100%, any unlinked ticket or PR reference, any em-dash. Any one of those blocks the swap.
