# Writing eval

Deterministic scoring for writing-rule changes. No model in the loop, no dependencies.

```bash
./run.sh current            # score fixtures against rewrites/current, print table, write runs/
python3 score.py compare baseline current   # one table: original vs current rules
./run.sh v3 --rewrite        # generate rewrites/v3 with the current SKILL.md, then score
```

Each run writes `runs/<timestamp>-<version>.json`, prints a table with the delta against the previous run of the same version, and regenerates `report.html`. Nothing is overwritten, so history stays.

## Checking a draft

```bash
python3 check_links.py draft.md      # exit 1 and prints each unlinked ticket, PR or path
```

Tickets (`[A-Z]{2,6}-\d+`), PR references (`word#123`) and backticked file paths must all sit inside a markdown link whose text is the name. A short summary with bare ticket and PR references is the fixture for it: several hits as written, clean once rewritten.

## The report

`report.py` writes `eval/report.html`: metrics tables plus the actual text of every fixture under every arm, side by side. Arms are discovered, so dropping in `rewrites/v4/` puts it on the next run with no other change. The file is written locally and that is the end of it.

## Arms

There are two arms: `baseline` (the source documents) and `current` (the rules in force). Superseded arms are deleted once their numbers are recorded in `runs/`.

## Fixtures

Put whatever documents you want to score into `fixtures/`, one file per document. Each one needs a matching file under `rewrites/<version>/`, with the same filename.

The baseline is the fixture as it stands. The rewrite is the same document under that version of the rules.

## Metrics

| Metric | Meaning | Direction |
| --- | --- | --- |
| words | prose word count, code and tables excluded | lower |
| longest sentence | words in the longest sentence | lower |
| max sentences / paragraph | the worst paragraph | lower |
| tables | markdown tables | higher |
| figures | mermaid blocks plus images | higher |
| first actionable word | word offset of the first decision, ask, or recommendation | lower |
| em dashes | count of — | tracked |
| ASCII / box diagrams | fenced blocks with box-drawing or arrows | lower |
| Flesch reading ease | 0–100, higher is easier | higher |
| Flesch-Kincaid grade | US school grade level | lower |
| Gunning Fog | grade level, weights long words | lower |
| SMOG | grade level, weights 3+ syllable words | lower |
| ARI | grade level from characters and words | lower |
| Coleman-Liau | grade level from characters | lower |
| % words 3+ syllables | the main driver of all five indices | lower |

Five indices, not one, because they disagree in useful ways. Flesch and FK both use syllables per word, so a rewrite that swaps "approximately" for "about" moves them together. Fog and SMOG punish long words harder and catch the case where sentence length improved but vocabulary did not. ARI and Coleman-Liau use characters instead, so they notice jargon that is long but not multi-syllable.

Known limits: the first-actionable detector is keyword-based, and sentence splitting treats checklist lines and code as prose unless they are fenced. Both are documented so a surprising number can be explained rather than trusted blindly.

## What a good delta looks like

Using the current arm as the reference point:

- Words down 40–60% without losing the decision.
- Longest sentence down to 25 words or fewer.
- Max sentences per paragraph at 3 or fewer.
- Figures up when the document has three or more interacting pieces.
- Flesch up 10 points or more.
- Em dashes flat or down, never up.

A version that cuts words but buries the ask is a regression: watch the first-actionable column against the word count, not on its own.
