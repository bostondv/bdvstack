---
name: go
description: Use when the user appends "/go" to a task or invokes /go directly — runs the full ship loop: implement → code review → end-to-end verify → simplify → draft PR. Each phase runs as a general-purpose teammate to protect the main chat context. The "ship it" closer that proves the work actually works before handing it back.
---

# /go — Build, Review, Verify, Simplify, Ship

`/go` means: "you're not done until this is implemented, reviewed, proven to work end-to-end, simplified, and up as a PR."

Run the five phases **in order**. Each phase runs as a **general-purpose teammate** via the Agent tool — keeps the heavy work out of the main chat so the context stays clean for orchestration and the user.

If any phase fails, **stop**. Report what failed. Do not paper over it to reach the PR.

## Phase Loop

```
1. BUILD     → general-purpose teammate implements the user's request
2. REVIEW    → general-purpose teammate code-reviews the diff
3. VERIFY    → general-purpose teammate exercises the feature end-to-end
4. SIMPLIFY  → invoke the `simplify` skill on the diff, then re-verify
5. PR        → commit + push + open draft PR
```

Between phases, **summarize the teammate's result in 1-2 sentences** for the user, then move on. Do not dump full transcripts.

## How to dispatch a teammate

Each phase = one `Agent` call (or one `TaskCreate` if a team has been set up).

- **`subagent_type: "general-purpose"`** for every phase.
- **Model: Opus** (`model: "opus"`) — Boston's standing preference for subagents. Never use `inherit`.
- **No worktrees** (`isolation` unset). Worktree branches get cleaned up when the agent shuts down, losing changes. Run on the working tree.
- The teammate's prompt must be **fully self-contained** — it has no memory of this conversation. Include the original request, relevant file paths, prior decisions, and what "done" looks like for that phase.
- Optionally `TeamCreate` once at the top so all phase teammates share a team context, but a single Agent call per phase is fine for short loops.

## Phase 1 — BUILD

Dispatch a `general-purpose` teammate with the user's full request as the prompt. Include all the context the teammate needs (the original ask, any constraints from the conversation, what's already been tried). The teammate writes code, runs tests as it goes, and reports back what it built.

If the user already implemented the work themselves before typing `/go`, **skip phase 1** and start at REVIEW. Detect this by checking `git status` / `git diff` — if there's already a substantive diff matching the request, skip.

## Phase 2 — REVIEW

Dispatch a `general-purpose` teammate to code-review the diff (`git diff master...HEAD` plus uncommitted changes). The reviewer checks for:

- Correctness vs. the original request
- Bugs, edge cases, error handling gaps
- Style/convention drift from surrounding code
- Scope creep — anything unrelated that snuck in
- Security issues (injection, secrets, auth)

Reviewer reports a short list of issues with severity. **High-severity issues block the loop** — go back to BUILD with the feedback. Low-severity stuff: note it, but proceed.

## Phase 3 — VERIFY (end-to-end)

Dispatch a `general-purpose` teammate to **actually exercise the feature**. Type-checks and unit tests verify code correctness, not feature correctness — this phase verifies the feature.

| Change type | How the teammate verifies |
|-------------|---------------------------|
| **Backend / API** | Start the service (`bento`, `make run`, etc.), hit endpoints with `curl`, inspect responses. |
| **Frontend / UI** | Use `agent-browser --auto-connect` to drive the user's already-running Chrome. Navigate to the feature, exercise the golden path **and** the edge cases that were touched. Snapshot to confirm. |
| **CLI / script / library** | Run the binary with realistic inputs. Show actual output. |
| **Desktop app** | Use computer use to drive the app. |
| **Pure refactor / no behavior change** | Run the full test/lint/typecheck suite. State explicitly that no runtime verification was possible. |

The teammate also runs the **full** check suite (tests, lint, typecheck, build). After fixing any issue, re-runs the **whole** suite — not just the failing piece.

If verification fails: stop. Report. Do not proceed to SIMPLIFY with a broken build.

If the teammate cannot verify (no server, no browser available, can't exercise the path): it must say so explicitly. Do not claim success.

## Phase 4 — SIMPLIFY

Invoke the `simplify` skill via the Skill tool. It reviews changed code for reuse, quality, and efficiency, and applies fixes.

After simplify finishes, dispatch a quick VERIFY teammate again — simplification can break things. If the re-verify fails, stop.

## Phase 5 — PR

Only reach this phase if phases 2-4 all came back green.

Dispatch a `general-purpose` teammate to:

1. Stage and commit any uncommitted work with logical, well-formed messages (use `awesome-agent:make-commits` if there's a lot to break up). Never `git add -A`.
2. Rebase from master if the branch is stale.
3. `git push -u origin <current-branch>`.
4. Create PR as **draft** (`gh pr create --draft`). Title under 70 chars. Description:
   ```
   ## Summary
   <1-3 bullets: what changed>

   ## Why
   <1-2 bullets: motivation, key decisions>
   ```
   No "Test plan" section unless something needs manual checking. No file-by-file walkthrough.
5. Return the PR URL.

Relay the URL to the user.

## Hard rules

- **Each phase = one teammate dispatch.** Do not run phases inline in the main chat — that defeats the context-protection purpose. The main session orchestrates and relays; teammates do the work.
- **Always specify model explicitly** (Opus). Never `inherit`.
- **No worktrees.** Run teammates on the working tree.
- **Never** push without verifying first. The whole point of `/go` is that long-running work is trustworthy when you come back to it.
- **Never** create a non-draft PR unless the user said so.
- **Never** invent verification you didn't actually run. If the teammate couldn't exercise the feature, say so.
- **Never** skip SIMPLIFY because "the diff looks fine."
- If any phase fails, stop and report — don't paper over it.

## Red flags — STOP

- "I'll just run the work in main context, it's faster" → no, dispatch a teammate.
- "Tests pass, that's enough" → no, exercise the feature.
- "I'll skip simplify, the code is already clean" → run it anyway.
- "I'll push as ready since it's obviously done" → draft, always.
- "Verification is too hard to set up here" → say so, don't fake it.
