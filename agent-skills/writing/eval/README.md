# Writing eval

Deterministic scoring for writing-rule changes. No model in the loop, no dependencies.

```bash
./run.sh v2                  # score fixtures against rewrites/v2, print table, write runs/
python3 score.py compare v1 v2   # one table: baseline, v1, v2 side by side
./run.sh v3 --rewrite        # generate rewrites/v3 with the current SKILL.md, then score
```

Each run writes `runs/<timestamp>-<version>.json`, prints a table with the delta against the previous run of the same version, and regenerates `report.html`. Nothing is overwritten, so history stays.

## The report

`report.py` builds one static page from the fixtures and every directory in `rewrites/`. Arms are discovered, so dropping in `rewrites/v4/` puts it on the next run with no other change. The page is the review artifact: metrics tables plus the actual text of every fixture under every arm, side by side.

Publishing is one command:

```bash
python3 report.py
pastry update <slug> --no-add -f report.html -t "Writing eval"
```

## Arms

A rules version is an arm. Today: `v1` (first rules), `v2` (reference-doc changes), `v3` (readability pass). Going forward the interesting comparison is `baseline` against whichever arm is newest; older arms stay for history.

## Fixtures

Not committed. Real documents are confidential, so they stay on your machine and
`.gitignore` keeps them out. Five of them is enough to score a rule change:

| Fixture | Source |
| --- | --- |
| `erd-nitro.md` | one internal design doc |
| `pr-897113.md` | a real PR description |
| `pr-902018.md` | a longer PR description |
| `status-web-platform.md` | a weekly status update |
| `proposal-writing.md` | a proposal doc |

Drop them in `fixtures/`, trimmed to a few hundred words each to keep scoring cheap.
`rewrites/<version>/` holds the same five files rewritten under that version of the
rules. The baseline is the fixture as it stands.

Nothing here scores anything until `fixtures/` exists, so treat the scripts as a
harness you point at your own documents.

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

Using v2 as the reference point:

- Words down 40–60% without losing the decision.
- Longest sentence down to 25 words or fewer.
- Max sentences per paragraph at 3 or fewer.
- Figures up when the document has three or more interacting pieces.
- Flesch up 10 points or more.
- Em dashes flat or down, never up.

A version that cuts words but buries the ask is a regression: watch the first-actionable column against the word count, not on its own.
