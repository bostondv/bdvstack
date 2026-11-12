# Arms and how to test a change

Two arms: `baseline` (the source documents) and `rewrites/current` (the rules in force). Superseded arms are deleted once their numbers are recorded below, so the directory stays small.

| Arm | What it changed | Words | Flesch | PR headings |
| --- | --- | ---: | ---: | ---: |
| baseline | the original AGENTS.md section | 386 | 65.4 | 50% |
| v1 (deleted) | answer first, sentence and paragraph caps, tables, links | 180 | 66.8 | 0% |
| v2 (deleted) | answer-then-stop, visual trigger, before/after, no ASCII | 157 | 71.1 | 0% |
| current | PR heading template, enforced links, readability pass | 155 | 78.1 | 100% |

## Changing a rule

1. Copy `rewrites/current` to `rewrites/candidate`.
2. Change the rule in `SKILL.md`.
3. `./run.sh candidate`.
4. Read the table before the prose. It is not an improvement if words go up, Flesch goes down, PR headings drop below 100%, unlinked refs go above 0, or an em-dash appears.
5. If it wins, replace `rewrites/current` with `candidate`, delete `rewrites/candidate`, and add a row to the table above with the new numbers.

The numbers are the record. The files are disposable.

## Backtest: 20 replies from 24h, regenerated under the five rules

| metric | original | regenerated |
| --- | ---: | ---: |
| longest sentence | 29.9 | 22.4 |
| em-dashes | 1.6 | 0 |
| unlinked refs | 0.7 | 0 |
| words | 138.3 | 137.9 |
| flesch | 66.6 | 68.9 |

Applied to the same twenty replies, the five rules fix every measurable failure. Sentence length comes in under the cap, em-dashes go to zero, references get linked, readability rises 2.3 points, and length holds within half a word.

The remaining gap is application at composition time, not the rules. Checked before sending, output passes. Skipped, it does not.
