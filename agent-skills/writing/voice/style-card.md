# Style card

Apply this per register. Grounding is in `profile.md`; where the human sample is thin, the line says so.

## Grounded in 42,762 words of his own

- **Median sentence 6 words in a PR, 16 in Slack.** Never above 25; his p90 is 21 in PRs and 27 in Slack. 61% of his PR sentences run under 10 words.
- **One or two sentences per paragraph.** 0.3% of his PR paragraphs go past three. Assistant drafts go past it 15% of the time.
- **Concrete nouns first**: the function, the flag, the date, the number. His first sentence is a fact about the system, not a thesis.
- **No em-dashes.** Zero in 32,127 words of his PRs. Use a comma, a colon, or a new sentence.
- **Never**: leverage, utilize, facilitate, robust, delve, crucial, moreover, furthermore, holistic, nuanced, myriad, plethora, additionally. "Ensure" is rare but he does use it.
- **Uncertainty is a named gap**, not a hedge: what he could not check, and what would settle it.

## `pr_description`

Grounded: 285 bodies, 32k words.

- Headings: `## Why`, `## What`, then `## Demo` and `## Additional` when they earn a place.
- Open with the concrete thing that changed or broke. Not a thesis, not a preamble.
- Then what he did, then the scope caveat: what this does not cover.
- Almost no hedging at 0.4 per 1,000 words. State what is true; name what is unverified.
- Verb-led openings are fine and used: "Adds", "Removes", "Moves".
- The ask lands about 15% into the body. Early, not first.

## `pr_comment`

Directional only: 1,900 words of live-typed text, mostly Slack.

- One point, then the reason in a clause.
- Suggestions are labelled: "consider", "suggestion only", "nothing blocking".

## `slack`

Grounded, 1,659 words, short-form.

- Lowercase fine. No terminal period fine. Fragments fine.
- Hedge freely: I think, probably, seems, guessing, maybe. 24 per 1,000 words, thirty times his PR rate.
- End on the question or the offer, not a summary.

## `prompt` — how to read a request from him

Grounded: 363 turns, 6,485 words of message text.

- Short: median 13 words. Verb or question first 30% of the time, context first 18%.
- No ceremony: zero "please" or "thanks" in 363 turns. Don't add politeness back into replies.
- One in five messages corrects itself, usually about 40% in. The second half is the real instruction.
- Parenthetical asides are normal, 71 in 363 turns.
- He asks rather than asserts here, 29.5% of turns carry a question. Answer the question that was asked.
- Do not copy the run-ons. Dictation produces them; documents should not.

## `doc` and `commit`

No human sample. Every doc and commit message in reach is assistant-written, so anything here is borrowed from his PR voice, not measured.

- Doc: two sentences per paragraph, a table once there are three parallel items.
- Commit: six to ten words, imperative, body only when the why is invisible from the diff.

## How to check a draft

`python3 check.py --register slack draft.md`. It fails on sentences far past his p90, paragraphs over three, banned vocabulary, and a buried ask. It warns on em-dashes and on hedging that is out of register.
