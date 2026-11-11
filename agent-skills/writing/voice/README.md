# Voice corpus

> **What is in this repo:** the three scripts (`build_corpus.py`, `stats.py`, `check.py`)
> and `style-card.md`. The corpus itself — `corpus/`, `raw/`, and the generated
> `profile.md`, `manifest.json`, `stats.json` — is personal writing and is not
> committed. `.gitignore` here enforces that. See "Regenerating" below.

```bash
python3 build_corpus.py   # rebuild corpus/ + manifest.json from raw/
python3 stats.py          # per-register numbers -> stats.json
python3 check.py --register slack draft.md
```

## What is in here

`corpus/` holds the text, `manifest.json` holds provenance and an `ai_likelihood` column (`human`, `mixed`, `ai`) per file. Read that before quoting any number. Both are local only.

The honest summary: 42,762 human words out of 135,700 collected. 32,127 are 2020-2021 PR bodies, 8,714 prompts, 1,659 Slack, 262 corrections. The prompt register is the largest live-typed source and the best evidence for word choice and stance.

## Why so small

195 of 500 PR bodies from 2026 carry an explicit AI marker, and Boston says most untagged ones are AI too. Commit messages are all AI and are excluded. Docs in `~/docs` are assistant-written, so no doc register exists.

## Regenerating

1. `raw/prs.json`, `raw/prs-asc-*.json` — `gh api search/issues?q=repo:instacart/carrot+author:bostondv+type:pr`.
2. `raw/prompts.md` — user turns scraped from your agent's session logs, e.g. `${SESSIONS_DIR:-$HOME/.codex/sessions}/**/*.jsonl`. Typed or dictated by him, never assistant output. Re-run the scrape to pick up new turns.
3. `raw/slack.md` — Slack search results from public channels, plus DMs he approved. Keep it sampled, not exhaustive.
4. `raw/corrections.md` — his own corrections to assistant drafts. Append new ones; this is the highest-value file.
5. `python3 build_corpus.py && python3 stats.py`.

## Known gaps

- No human commit, doc, or ticket register. The style card says which lines are borrowed rather than measured.
- 2020-2021 PRs are his, but four to six years old. If his writing moved, this corpus would not know.
- Prompts are the cleanest source but the worst for structure: dictation run-ons and repairs mean sentence targets must come from PR bodies.
- Slack sample is 60 messages. Enough for register, not enough for vocabulary claims.
- Corrections are 262 words. They are opinions about output, not prose samples; they belong in front of a writer, not in a frequency table.
