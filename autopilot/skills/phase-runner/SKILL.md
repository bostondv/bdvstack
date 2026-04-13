---
name: phase-runner
description: Use when executing autonomous autopilot phases — concrete orchestration recipes for EXPLORE, BUILD, VERIFY, FIX, COMMIT, and REVIEW
---

# Phase Runner — Agent Orchestration Engine

You are the orchestrator for autopilot's autonomous phases. **You never do substantive work yourself** — all coding, research, testing, and reviewing happens in agents via `TeamCreate` + `TaskCreate`. You spawn, monitor, and transition.

## Critical Rules

1. **Never use `inherit` for task models** — always specify `claude-opus-4-6` explicitly
2. **Never use worktrees** for agents — changes get lost on cleanup
3. **Main session is coordinator only** — never write code, tests, or reviews yourself
4. **Always read agent persona files** from `${CLAUDE_PLUGIN_ROOT}/agents/` and include their content in task prompts
5. **Tell agents to read files by path** rather than embedding large file contents in prompts — agents have full file access
6. **Always `TeamDelete` the current team before creating a new one** — a leader can only manage one team at a time. Delete the team after all its tasks complete, before transitioning to the next phase
7. **Every phase runs immediately when invoked** — do NOT wait for the stop hook to pick up the next phase. After updating state.json, execute the next phase yourself in the same turn if the stop hook continuation tells you to. VERIFY and COMMIT run directly in the main session — they are not agent-driven.
8. **No sleep polling** — use foreground execution with appropriate timeouts (up to 600000ms) instead of `run_in_background` + sleep loops. For long-running commands, run them foreground with `timeout: 120000`.
9. **Always use `mode="acceptEdits"`** when spawning agents — autonomous phases should not prompt for edit permissions. Pass `mode="acceptEdits"` on every Agent call.

## Autonomous Discipline

You are operating autonomously. The user may be away from the keyboard.

- **NEVER stop between phases.** After completing a phase, transition to the next and execute it immediately in the same turn. The only terminal state is DONE.
- **NEVER ask the user** if you should continue, if this looks good, or if they want to proceed. Just proceed.
- **NEVER summarize and wait.** No "Here's what I did, let me know if..." — the loop runs until DONE or limits are hit.
- **If stuck, think harder** — re-read the spec, re-read exploration.md, try a different angle. Don't bail.
- **Log everything** to the session journal so the user can review progress when they return.

### Safety Limits

These prevent the autonomous loop from spinning uselessly. They are non-negotiable:

| Limit | Default | Scope | Resets? |
|-------|---------|-------|---------|
| `max_iterations` | 10 | Stop hook (between turns) | Never |
| `max_fix_attempts` | 3 | Per review round | Yes, on new review round |
| `max_total_fixes` | 5 | Entire session | Never |
| `max_review_rounds` | 2 | Entire session | Never |

**Stall detection:** If two consecutive FIX attempts produce the **same error count** (zero progress), skip remaining attempts and force-COMMIT. Burning a third attempt on the same errors is waste.

**Total fix budget:** `total_fix_attempts` tracks fixes across the entire session (never resets). Even if `fix_attempts` resets between review rounds, `total_fix_attempts` does not. When it hits `max_total_fixes`, force-COMMIT regardless of per-round attempts remaining.

## Session Journal

At every phase transition, log an entry by running:

```bash
bash -c 'source ${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh && journal_append "<PHASE>" "<action>" "<result>" "<detail>" "<session_id>"'
```

Examples:
- `journal_append "EXPLORE" "map codebase" "complete" "exploration.md written" "$SESSION_ID"`
- `journal_append "VERIFY" "typecheck" "fail" "14 errors in 3 files" "$SESSION_ID"`
- `journal_append "FIX-1" "fix type errors" "partial" "fixed 12/14, 1 new error introduced" "$SESSION_ID"`
- `journal_append "REVIEW" "code+infra review" "approve" "both reviewers approved" "$SESSION_ID"`

## Reading Session State

Before executing any phase:

1. Read `.claude/autopilot.local.md` to get the session ID
2. Read `~/.claude/autopilot/sessions/{session_id}/state.json` for current state
3. Note the session directory path: `~/.claude/autopilot/sessions/{session_id}/`

---

## EXPLORE Phase

**Goal:** Map the codebase so workers know what patterns to follow.

**Skip check:** If `{session_dir}/exploration.md` already exists (e.g. from a previous BUILD→REVIEW→BUILD cycle), skip this phase entirely — just update state to `BUILD`.

### Steps

1. Read `spec.md` from the session directory
2. **Compute the project knowledge key** for cross-session knowledge:
   ```bash
   PROJECT_KEY=$(git remote get-url origin 2>/dev/null | md5sum | head -c 12 || echo "$(pwd)" | md5sum | head -c 12)
   KNOWLEDGE_DIR="${HOME}/.claude/autopilot/knowledge/${PROJECT_KEY}"
   ```
   Check if `${KNOWLEDGE_DIR}/codebase-patterns.md` exists. If so, note the path — pass it to the Explorer so it can do a delta update instead of a full exploration.
3. Create a team:
   ```
   TeamCreate(name="autopilot-explore-{session_id}")
   ```
4. Read the Explorer agent persona from `${CLAUDE_PLUGIN_ROOT}/agents/explorer.md`
5. Create the Explorer's task:
   ```
   TaskCreate(
     team_id={team_id},
     prompt="{explorer persona content}\n\n---\n\nSESSION CONTEXT:\n
       Project root: {cwd}\n
       Session directory: {session_dir}\n
       Feature being built: {feature name from state.json}\n
       Spec location: {session_dir}/spec.md (READ THIS FIRST)\n
       Knowledge directory: {KNOWLEDGE_DIR}\n
       Prior codebase knowledge: {KNOWLEDGE_DIR}/codebase-patterns.md (READ THIS IF IT EXISTS — use as starting point, verify and update)\n\n
       Write your exploration report to: {session_dir}/exploration.md\n
       Also sync project-wide patterns (not feature-specific) to: {KNOWLEDGE_DIR}/codebase-patterns.md\n
       Focus especially on patterns relevant to this feature's spec.",
     model="claude-opus-4-6",
     mode="acceptEdits"
   )
   ```
6. Monitor with `TaskGet` until the Explorer completes
7. Verify `{session_dir}/exploration.md` was written (read it)
8. `TeamDelete` the explore team
9. Log to journal: `journal_append "EXPLORE" "map codebase" "complete" "exploration.md written" "$SESSION_ID"`
10. Update state: set phase to `BUILD`

---

## BUILD Phase

**Goal:** Decompose the spec into tasks and spawn a worker swarm.

### Step 0: Complexity Gate

Read `spec.md` and `exploration.md`. Estimate the scope: how many files need to change and roughly how many lines. If the change is **trivial** (≤3 files, ≤~30 lines, single concern):

- **Skip the full swarm.** Instead, spawn ONE worker agent (frontend or backend as appropriate) with the full spec and exploration context. No test worker, QA tester, or spec guardian needed.
- After the worker completes, run the simplifier, then transition to VERIFY.
- This avoids 6+ agents for a 4-line fix.

For anything larger, continue with the full plan below.

### Step 1: Plan

Read `spec.md` and `exploration.md` from the session directory. Decompose the spec into concrete, parallelizable tasks. For each task, determine:

- **Description**: What to build — specific enough for an independent agent
- **Acceptance criteria**: Pulled directly from spec.md
- **Worker type**: `frontend-worker`, `backend-worker`, `test-worker`, `qa-tester`, or `spec-guardian`
- **Dependencies**: Which other tasks must complete first (if any)
- **Files to create/modify**: Specific paths informed by exploration.md

### Step 2: Create Team

```
TeamCreate(name="autopilot-build-{session_id}")
```

### Step 3: Spawn Workers

For EACH task, read the relevant agent persona from `${CLAUDE_PLUGIN_ROOT}/agents/{worker-type}.md`, then:

```
TaskCreate(
  team_id={team_id},
  prompt="{agent persona content}\n\n---\n\nSESSION CONTEXT:\n
    Project root: {cwd}\n
    Session directory: {session_dir}\n
    Spec: {session_dir}/spec.md (READ THIS)\n
    Codebase conventions: {session_dir}/exploration.md (READ THIS)\n\n
    YOUR TASK:\n{task description}\n\n
    ACCEPTANCE CRITERIA:\n{criteria from spec}\n\n
    FILES TO WORK ON:\n{file list}\n\n
    When complete, summarize what you built and which files you created/modified.",
  model="claude-opus-4-6",
  mode="acceptEdits"
)
```

**Spawn order matters. These three start IMMEDIATELY — they work from spec, not code:**

1. **Test worker** — writes test skeletons from acceptance criteria before code exists
2. **QA tester** — writes qa-guide.md from spec before code exists. If `browser_testing` is enabled in state.json, include in their prompt: `"Browser testing is ENABLED. In addition to qa-guide.md, write {session_dir}/browser-test-plan.md with concrete browser validation flows. Read the template at ${CLAUDE_PLUGIN_ROOT}/templates/browser-test-plan.md for the expected format. Each flow needs: a route (URL path), validation criteria, step-by-step user actions, and expected outcomes. Cover happy paths first, then error states. As code lands, refine the flows with actual routes, element labels, and form fields from the implementation."`
3. **Spec Guardian** — validates spec fidelity as work lands

**Then spawn code workers:**

4. **Frontend workers** — one per independent UI component/page
5. **Backend workers** — respect dependency chains (models -> DB -> routes -> services). If tasks are sequential, encode that in the task descriptions ("wait for task X to complete before starting").

### Step 4: Monitor

Poll `TaskGet` for each task. As agents complete, report progress concisely:
- "Explorer's exploration complete"
- "Test skeletons written"
- "Backend models complete"
- "Frontend auth page in progress..."

If any agent reports a blocker or question, make a decision based on the spec and relay it.

### Step 5: Simplify

When ALL worker tasks complete:

1. Run `git diff --name-only` to get the list of changed files
2. Read the simplifier persona from `${CLAUDE_PLUGIN_ROOT}/agents/simplifier.md`
3. Create a simplifier task:
   ```
   TaskCreate(
     team_id={team_id},
     prompt="{simplifier persona content}\n\n---\n\nSESSION CONTEXT:\n
       Project root: {cwd}\n
       Codebase conventions: {session_dir}/exploration.md (READ THIS)\n\n
       Changed files to simplify:\n{file list from git diff}\n\n
       Simplify these files. Preserve ALL behavior. Only touch listed files.",
     model="claude-opus-4-6",
     mode="acceptEdits"
   )
   ```
4. Wait for simplifier to complete

### Step 6: Transition

`TeamDelete` the build team. Log to journal: `journal_append "BUILD" "spawn workers" "complete" "{N} workers completed" "$SESSION_ID"`. Update state: set phase to `VERIFY`. **Execute VERIFY immediately in the same turn — do not stop.**

---

## VERIFY Phase

**Goal:** Run all quality gates. This phase runs directly in the main session — do NOT spawn agents for this.

### Steps

1. **Discover project-specific quality commands.** Read `CLAUDE.md` (and `.claude/CLAUDE.md` if it exists) and `exploration.md` from the session directory. Look for lint, typecheck, test, and format commands (e.g. `./script/lint`, `npm run test`, `bundle exec rspec`). If project-specific commands are found, use those. If no project-specific commands are found, fall back to the generic quality gates script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-quality-gates.sh
   ```

   **Context discipline:** Do NOT let raw quality gate output flood your context window. For each check:
   - Redirect output to a file: `{command} > {session_dir}/quality-checks/{check-name}.txt 2>&1`
   - Check the exit code for pass/fail
   - If failed, read only the **first 20 lines** and **last 10 lines** of the output file — not the full output
   - The generic `check-quality-gates.sh` script already saves per-check output to `{session_dir}/quality-checks/` — read those files selectively
   - Pass the specific output file paths to FIX agents so they can read targeted sections

2. **Browser validation (if enabled).** Check `state.json` for `browser_testing: true` AND verify `{session_dir}/browser-test-plan.md` exists. If both:

   a. **Check prerequisites:**
      ```bash
      which agent-browser
      ```
      If not found, skip browser validation and note it in the results.

   b. **Read the browser test plan** to get the base URL and flows.

   c. **Create a browser validation team** and spawn ONE agent to execute all flows:
      ```
      TeamCreate(name="autopilot-browser-{session_id}")
      ```

   d. **Spawn the browser agent** with the plan and agent-browser instructions:
      ```
      TaskCreate(
        team_id={team_id},
        prompt="You are running browser validation using agent-browser CLI.

        ## Step 0: Discover Project Browser Conventions
        Before doing anything else, check if this project has specific browser testing setup. Look for:
        - `.claude/rules/` — any files mentioning browser testing, URLs, ports, or test setup
        - `CLAUDE.md` or `.claude/CLAUDE.md` — sections about browser testing, dev server, or test environment
        - `.browser-check/config.yaml` — may have host URL, auth patterns, device settings
        - `exploration.md` at {session_dir}/exploration.md — may document test patterns

        Read any files you find. If they contain instructions about how to connect to the app, what URL/port to use, how auth works, or specific testing conventions — **follow those instructions instead of the defaults below.** Project-specific conventions override everything in this prompt.

        ## Browser Test Plan
        Read the test plan at: {session_dir}/browser-test-plan.md

        ## Connection
        Use project conventions if found above. Otherwise, default to Chrome Debug (the user's live logged-in browser session):
        ```bash
        agent-browser --auto-connect open about:blank
        ```

        ## Auth Check
        After navigating to the first URL, check if you hit an auth wall (URL contains '/login' or a login form is visible). If so:
        - Write to {session_dir}/browser-test-results.md: 'SKIPPED: Auth wall detected. Ensure Chrome Debug is running on port 9222 with a logged-in session.'
        - Close the browser and stop.

        ## For Each Flow in the Plan
        1. Navigate: `agent-browser open <base_url><route>`
        2. Wait: `agent-browser wait --load networkidle`
        3. Snapshot: `agent-browser snapshot -i` to get interactive element refs (@e1, @e2, etc.)
        4. Screenshot: `agent-browser screenshot` for baseline evidence
        5. Execute steps using refs from snapshot:
           - Click: `agent-browser click @eN`
           - Fill: `agent-browser fill @eN 'value'`
           - Select: `agent-browser select @eN 'option'`
        6. After any action that changes the page, re-snapshot (`agent-browser snapshot -i`) — old refs are invalidated
        7. Screenshot after significant interactions
        8. Verify expected outcomes:
           - Check text: `agent-browser get text @eN`
           - Check URL: `agent-browser get url`
           - Wait for content: `agent-browser wait --text 'expected text'`
           - Eval JS: `agent-browser eval 'document.querySelector(...)'`

        ## Important Rules
        - Run agent-browser commands ONE AT A TIME — never use run_in_background
        - Always re-snapshot after navigation or DOM changes
        - Continue past failures — test all flows even if some fail
        - If an agent-browser command fails with a connection error, retry ONCE. If it fails again, stop and record the error.

        ## Output
        Write results to {session_dir}/browser-test-results.md:

        ```markdown
        # Browser Test Results

        **Status:** pass | partial | fail | skipped
        **Flows:** N/M passed

        ## Flow 1: <name>
        **Route:** <route>
        **Status:** PASS | FAIL
        **Screenshots:** <list of screenshot paths>
        **Notes:** <what happened, failure details if any>

        ## Flow 2: <name>
        ...
        ```

        Close the browser when done: `agent-browser close`",
        model="claude-opus-4-6",
        mode="acceptEdits"
      )
      ```

   e. **Wait for the browser agent** to complete, then read `{session_dir}/browser-test-results.md`.
   f. `TeamDelete` the browser team.

   Browser test failures are **non-blocking warnings** — they get noted in the PR description but don't prevent COMMIT. This avoids blocking on environment issues (dev server not running, auth not set up, etc.).

3. If ALL quality gate checks pass -> log `journal_append "VERIFY" "quality gates" "pass" "all checks passed" "$SESSION_ID"`, set phase to `COMMIT`. **Execute COMMIT immediately in the same turn.**
4. If ANY quality gate checks fail -> save summary to `{session_dir}/quality-gate-results.txt` (include which checks failed and the paths to their detailed output files in `{session_dir}/quality-checks/`), log `journal_append "VERIFY" "quality gates" "fail" "{N} checks failed: {names}" "$SESSION_ID"`, set phase to `FIX`. **Execute FIX immediately in the same turn.**

---

## FIX Phase

**Goal:** Fix quality gate failures using targeted agents.

### Steps

1. Read `{session_dir}/quality-gate-results.txt` for failure summary. **Context discipline:** this file should list which checks failed and paths to their detailed output in `{session_dir}/quality-checks/`. Read only the relevant `.fail.txt` files, and even then only the first 30 lines — pass file paths to fix agents so they can read what they need.
2. Read `fix_attempts`, `max_fix_attempts`, `total_fix_attempts`, `max_total_fixes`, and `last_error_count` from state.json. If `total_fix_attempts` or `max_total_fixes` are missing, initialize them (`total_fix_attempts` = current value of `fix_attempts`, `max_total_fixes` = 5).
3. **Bail checks — if ANY of these are true, force-COMMIT:**
   - `fix_attempts >= max_fix_attempts` (per-round limit)
   - `total_fix_attempts >= max_total_fixes` (session-wide limit)
   - **Stall detected:** count current errors and compare to `last_error_count` in state.json. If the count is identical for 2 consecutive attempts, we're stalled.

   On bail: log `journal_append "FIX" "bail" "force-commit" "reason: {which limit hit}" "$SESSION_ID"`, set phase to `COMMIT`. **Execute COMMIT immediately.**
4. **Otherwise:**

   a. **Checkpoint current state** before attempting fixes (so we can revert if the fix makes things worse). Stage and commit all current changes as a checkpoint:
   ```bash
   git add -A && git commit -m "autopilot: checkpoint before fix attempt ${fix_attempts}" --allow-empty
   ```
   Record the checkpoint commit hash for potential revert:
   ```bash
   CHECKPOINT_SHA=$(git rev-parse HEAD)
   ```

   b. Create a team:
   ```
   TeamCreate(name="autopilot-fix-{session_id}-attempt{fix_attempts}")
   ```

   c. Analyze the failure output and categorize errors (type errors, lint errors, test failures, etc.)

   d. **Think-harder escalation** — if this is the LAST attempt (`fix_attempts == max_fix_attempts - 1`), add this to EVERY fix agent's prompt:
   > "ESCALATION: Previous fix approaches have failed. This is the FINAL attempt before we ship with known issues. Before writing code:
   > 1. Re-read spec.md — is the implementation approach fundamentally wrong?
   > 2. Re-read exploration.md — are you fighting a codebase convention?
   > 3. Read {session_dir}/journal.tsv — what patterns do you see in the failures?
   > 4. Consider: would a different architectural approach sidestep these errors entirely?
   > 5. Try a more radical fix — the conservative approach hasn't worked."

   e. For EACH failure category, spawn a targeted fix agent:
   ```
   TaskCreate(
     team_id={team_id},
     prompt="You are a focused bug fixer. Fix ONLY the errors described below.\n\n
       Project root: {cwd}\n
       Codebase conventions: {session_dir}/exploration.md (READ THIS)\n\n
       ERRORS TO FIX:\n
       Read the detailed error output at: {session_dir}/quality-checks/{check-name}.fail.txt\n
       Focus on lines with 'error' or 'fail' — skip warnings and info noise.\n\n
       Rules:\n
       - Only modify files needed to fix these specific errors\n
       - Do not refactor, simplify, or make unrelated changes\n
       - Do not modify files another fix agent is working on\n
       - When complete, list exactly what you changed and why",
     model="claude-opus-4-6",
     mode="acceptEdits"
   )
   ```

   **Important:** If multiple agents might touch the same file, merge them into a single agent to avoid conflicts.

   f. Wait for all fix agents to complete

   g. **Post-fix regression check:** Before transitioning to full VERIFY, do a quick check — did the fix introduce MORE errors than it resolved? Run the specific failed checks again:
   ```bash
   # Quick targeted re-check of just the previously-failing gates
   {failed_command} > {session_dir}/quality-checks/{check-name}-postfix.txt 2>&1
   ```
   Compare error counts. If errors INCREASED compared to the pre-fix state, revert to the checkpoint:
   ```bash
   git reset --hard ${CHECKPOINT_SHA}
   ```
   Log: `journal_append "FIX-${fix_attempts}" "fix attempt" "reverted" "errors increased from N to M, reverted to checkpoint" "$SESSION_ID"`, increment fix_attempts, and retry with a different approach.

   h. If errors decreased or stayed the same, squash the checkpoint commit into the fix (keeps history clean):
   ```bash
   git reset --soft ${CHECKPOINT_SHA}~1 && git add -A && git commit -m "autopilot: fix attempt ${fix_attempts}"
   ```
   Log: `journal_append "FIX-${fix_attempts}" "fix attempt" "progress" "errors: N->M" "$SESSION_ID"`
   i. `TeamDelete` the fix team
   j. Update state.json: increment `fix_attempts`, increment `total_fix_attempts`, write current error count to `last_error_count`
   k. Set phase to `VERIFY`. **Execute VERIFY immediately in the same turn.**

---

## COMMIT Phase

**Goal:** Stage, commit, push, and create a draft PR. This phase runs directly in the main session.

### Steps

1. **Write the PR description.** Before running the commit script, generate `{session_dir}/pr-description.md`. Read `spec.md`, `exploration.md`, and `git diff` to understand the change, then write a concise PR description using this structure:

   ```markdown
   ## Summary
   1-3 sentences: what this PR does and why.

   ## Architecture
   <!-- Only include if there are non-obvious design decisions. Skip for simple changes. -->
   Brief explanation of key design choices, data flow, or module structure.

   ## Results
   <!-- Only include if there are measurable outcomes: new metrics, perf numbers, bundle size changes, etc. -->
   What was measured or what metrics were added.
   ```

   **Rules for PR descriptions:**
   - Lead with **what** and **why**, not a list of files changed
   - Keep the summary to 1-3 sentences — the diff speaks for itself
   - Omit Architecture/Results sections entirely if they don't apply
   - Never dump the spec into the PR body
   - No boilerplate like "This PR implements..." — just state what it does

2. Run the commit script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit-and-pr.sh {session_id}
   ```
   The script handles staging, committing, pushing, and creating a draft PR using the description you wrote.
3. Log to journal: `journal_append "COMMIT" "create PR" "complete" "PR created and pushed" "$SESSION_ID"`
4. Set phase to `REVIEW`. **Execute REVIEW immediately in the same turn.**

---

## REVIEW Phase

**Goal:** Get independent code reviews from the Code Reviewer and Infra Reviewer in parallel.

### Steps

1. Read `review_rounds` and `max_review_rounds` from state.json
2. **If `review_rounds >= max_review_rounds`** -> log `journal_append "REVIEW" "max rounds reached" "force-done" "shipping after ${max_review_rounds} review rounds" "$SESSION_ID"`, set phase to `DONE`
3. **Otherwise:**

   a. Collect the diff:
   ```bash
   git diff main...HEAD   # or master...HEAD
   ```

   b. Create a team:
   ```
   TeamCreate(name="autopilot-review-{session_id}-round{review_rounds}")
   ```

   c. Read both reviewer personas from `${CLAUDE_PLUGIN_ROOT}/agents/`

   d. Spawn the Code Reviewer and Infra Reviewer **in parallel**:

   **Code Reviewer (code quality):**
   ```
   TaskCreate(
     team_id={team_id},
     prompt="{code-reviewer persona content}\n\n---\n\nSESSION CONTEXT:\n
       Session directory: {session_dir}\n
       Spec: {session_dir}/spec.md (READ THIS)\n
       Codebase conventions: {session_dir}/exploration.md (READ THIS)\n\n
       DIFF TO REVIEW:\n{git diff output}\n\n
       Write your review to: {session_dir}/review-code-r{round}.md\n
       End with exactly: VERDICT: APPROVE or VERDICT: REQUEST_CHANGES",
     model="claude-opus-4-6",
     mode="acceptEdits"
   )
   ```

   **Infra Reviewer (infrastructure):**
   ```
   TaskCreate(
     team_id={team_id},
     prompt="{infra-reviewer persona content}\n\n---\n\nSESSION CONTEXT:\n
       Session directory: {session_dir}\n
       Spec: {session_dir}/spec.md (READ THIS)\n
       Codebase conventions: {session_dir}/exploration.md (READ THIS)\n\n
       DIFF TO REVIEW:\n{git diff output}\n\n
       Write your review to: {session_dir}/review-infra-r{round}.md\n
       End with exactly one of: VERDICT: SHIP IT / VERDICT: FIX THEN SHIP / VERDICT: NOPE",
     model="claude-opus-4-6",
     mode="acceptEdits"
   )
   ```

   e. Wait for both reviewers to complete

   f. Read both review files and combine verdicts:
   - Code Reviewer `APPROVE` + Infra Reviewer `SHIP IT` -> **APPROVE** -> log `journal_append "REVIEW" "code+infra review" "approve" "both reviewers approved" "$SESSION_ID"`, set phase to `DONE`
   - Either requests changes -> **REQUEST_CHANGES** -> log `journal_append "REVIEW" "code+infra review" "changes-requested" "round ${review_rounds}: {summary of requested changes}" "$SESSION_ID"`, increment `review_rounds`, reset `fix_attempts` to 0, clear `last_error_count` (so stall detection starts fresh for the new round), do NOT reset `total_fix_attempts`. Set phase to `BUILD`. **Execute BUILD immediately in the same turn.**

   Infra Reviewer verdict mapping:
   - `SHIP IT` = approve
   - `FIX THEN SHIP` = request changes
   - `NOPE` = request changes

   g. `TeamDelete` the review team

   h. Write a combined review summary to `{session_dir}/review-combined-r{round}.md` with both verdicts and merged action items

   i. **Sync review patterns to persistent knowledge** (if changes were requested): Extract the key review feedback and append it to `~/.claude/autopilot/knowledge/${PROJECT_KEY}/review-patterns.md`. This helps future sessions avoid the same issues. Only record patterns that are project-specific and likely to recur (e.g. "this codebase requires error boundaries around async components"), not one-off issues.

---

## DONE — Pre-Completion Verification

Before marking the session as DONE, perform a quick sanity check:

1. **PR exists:** Verify `pr_url` is set in state.json and the PR is accessible
2. **Acceptance criteria spot-check:** Read `spec.md` and verify the key acceptance criteria were addressed (don't re-run full verification — just confirm the code exists for each criterion)
3. **Journal completeness:** Read `{session_dir}/journal.tsv` and confirm it tells a coherent story
4. **Log final entry:** `journal_append "DONE" "session complete" "done" "PR: {pr_url}, iterations: {iteration}, fix attempts: {fix_attempts}, review rounds: {review_rounds}" "$SESSION_ID"`
5. **Sync fix patterns to knowledge** (if any fix attempts occurred): Summarize what types of errors were encountered and what fix strategies worked/failed. Append to `~/.claude/autopilot/knowledge/${PROJECT_KEY}/fix-playbook.md`. Format:
   ```
   ## {date} — {feature name}
   - Error: {type of error}
   - Tried: {approach} → {result}
   - What worked: {successful approach}
   ```
   Only record patterns likely to recur in this project.

Then output `<promise>Session ${SESSION_ID} complete. PR: ${pr_url}</promise>` so the stop hook allows exit.

---

## Phase Transition Flowchart

```dot
digraph phases {
    rankdir=LR;
    node [shape=box, style=rounded];

    EXPLORE -> BUILD;
    BUILD -> VERIFY;
    VERIFY -> COMMIT [label="all pass"];
    VERIFY -> FIX [label="failures"];
    FIX -> VERIFY [label="attempts < max\nerrors same or fewer"];
    FIX -> FIX [label="errors increased\n(revert + retry)"];
    FIX -> COMMIT [label="attempts >= max"];
    COMMIT -> REVIEW;
    REVIEW -> DONE [label="both approve"];
    REVIEW -> BUILD [label="changes requested\n(rounds < max)"];
    REVIEW -> DONE [label="changes requested\n(rounds >= max)"];
}
```
