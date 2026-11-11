# Nightly review

Every night, look at the day's actual record and extract lessons that change tomorrow's behavior.

## Grounding

- **Reflexion** (arXiv 2303.11366): reflect on feedback, keep the reflection, use it next trial. Verbal reinforcement beats another training run.
- **Generative Agents** (arXiv 2304.03442): compress a memory stream into higher-level reflections, retrieve them to plan. Ablation shows reflection carries weight.
- **MemGPT** (arXiv 2310.08560): tiered memory with a consolidation step, because unbounded memory degrades retrieval.

Common structure: **events → synthesis → few durable lessons → retrieved when relevant.** The risk they all name is bloat.

## Inputs — evidence only

| Source | Signal |
|---|---|
| Chat history of this thread | every correction Boston made — the strongest signal |
| Task chats | work finished, rework, pushes that went wrong, claims that were wrong |
| GitHub / CI | red builds, reverted commits, PRs that needed redoing |

No evidence, no lesson. "I did well" without a merged result that survived review is not a finding.

## Output — two places

- `lessons/YYYY-MM-DD.md` — the day's review.
- `proposed/*.md` — any rule change, as a diff against `BRAIN.md` or `RULES.md`, left for approval. Never applied directly, never routed through another skill.

## Output — three parts, capped

1. **At most 3 lessons.** Each cites a specific incident: date, what happened, what should have happened. One line each, no paragraphs.
2. **Proposed rule changes**, as a diff against `BRAIN.md` or `RULES.md`. Queued for approval — not applied.
3. **One thing that worked**, with evidence it survived (merged, no rework). Optional.

## The rubric

Score the day on these, because they're the failure modes we actually hit:

- Did Boston have to correct me? How many times, for the same thing?
- Did I claim something I hadn't verified? (tool stalls, green builds, "done")
- Did work start without a `START` line?
- Did something get pushed, merged or posted without a look?
- Did a branch drift from master until it broke?
- Did I surface what agents finished, or did he have to ask?

## Anti-bloat

- `LESSONS.md` is capped at 30 active entries. Adding one means retiring one.
- A lesson that recurs 3+ times gets promoted into `BRAIN.md` as a rule and leaves the list.
- A lesson unused for 30 days gets retired.
- Weekly consolidation (Sundays): merge duplicates, retire stale, flag contradictions.

## Anti-flattery

The default question is not "what went well" — it's **"what did Boston have to fix?"** A self-assessment with no corrections cited is either a genuinely clean day or a bad review. Say which, and show the evidence.

## Retrieval

`BRAIN.md` stays small because it loads in every session. `LESSONS.md` is retrieved by topic, not pasted into context wholesale.
