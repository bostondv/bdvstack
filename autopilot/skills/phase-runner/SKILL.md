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
2. Create a team:
   ```
   TeamCreate(name="autopilot-explore-{session_id}")
   ```
3. Read the Explorer agent persona from `${CLAUDE_PLUGIN_ROOT}/agents/explorer.md`
4. Create the Explorer's task:
   ```
   TaskCreate(
     team_id={team_id},
     prompt="{explorer persona content}\n\n---\n\nSESSION CONTEXT:\n
       Project root: {cwd}\n
       Session directory: {session_dir}\n
       Feature being built: {feature name from state.json}\n
       Spec location: {session_dir}/spec.md (READ THIS FIRST)\n\n
       Write your exploration report to: {session_dir}/exploration.md\n
       Focus especially on patterns relevant to this feature's spec.",
     model="claude-opus-4-6",
     mode="acceptEdits"
   )
   ```
5. Monitor with `TaskGet` until the Explorer completes
6. Verify `{session_dir}/exploration.md` was written (read it)
7. `TeamDelete` the explore team
8. Update state: set phase to `BUILD`

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

`TeamDelete` the build team, then update state: set phase to `VERIFY`

---

## VERIFY Phase

**Goal:** Run all quality gates. This phase runs directly in the main session — do NOT spawn agents for this.

### Steps

1. **Discover project-specific quality commands.** Read `CLAUDE.md` (and `.claude/CLAUDE.md` if it exists) and `exploration.md` from the session directory. Look for lint, typecheck, test, and format commands (e.g. `./script/lint`, `npm run test`, `bundle exec rspec`). If project-specific commands are found, use those. If no project-specific commands are found, fall back to the generic quality gates script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-quality-gates.sh
   ```
   Run each discovered command and collect pass/fail results.

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

3. If ALL quality gate checks pass -> set phase to `COMMIT`
4. If ANY quality gate checks fail -> save output to `{session_dir}/quality-gate-results.txt`, set phase to `FIX`

---

## FIX Phase

**Goal:** Fix quality gate failures using targeted agents.

### Steps

1. Read `{session_dir}/quality-gate-results.txt` for failure details
2. Read `fix_attempts` and `max_fix_attempts` from state.json
3. **If `fix_attempts >= max_fix_attempts`** -> set phase to `COMMIT` (ship what we have, note issues in PR)
4. **Otherwise:**

   a. Create a team:
   ```
   TeamCreate(name="autopilot-fix-{session_id}-attempt{fix_attempts}")
   ```

   b. Analyze the failure output and categorize errors (type errors, lint errors, test failures, etc.)

   c. For EACH failure category, spawn a targeted fix agent:
   ```
   TaskCreate(
     team_id={team_id},
     prompt="You are a focused bug fixer. Fix ONLY the errors described below.\n\n
       Project root: {cwd}\n
       Codebase conventions: {session_dir}/exploration.md (READ THIS)\n\n
       ERRORS TO FIX:\n{specific error output for this category}\n\n
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

   d. Wait for all fix agents to complete
   e. `TeamDelete` the fix team
   f. Increment `fix_attempts` in state.json
   g. Set phase to `VERIFY`

---

## COMMIT Phase

**Goal:** Stage, commit, push, and create a draft PR. This phase runs directly in the main session.

### Steps

1. Run the commit script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit-and-pr.sh {session_id}
   ```
2. The script handles staging, committing, pushing, and creating a draft PR
3. Set phase to `REVIEW`

---

## REVIEW Phase

**Goal:** Get independent code reviews from the Code Reviewer and Infra Reviewer in parallel.

### Steps

1. Read `review_rounds` and `max_review_rounds` from state.json
2. **If `review_rounds >= max_review_rounds`** -> set phase to `DONE`
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
   - Code Reviewer `APPROVE` + Infra Reviewer `SHIP IT` -> **APPROVE** -> set phase to `DONE`
   - Either requests changes -> **REQUEST_CHANGES** -> increment `review_rounds`, reset `fix_attempts`, set phase to `BUILD`

   Infra Reviewer verdict mapping:
   - `SHIP IT` = approve
   - `FIX THEN SHIP` = request changes
   - `NOPE` = request changes

   g. `TeamDelete` the review team

   h. Write a combined review summary to `{session_dir}/review-combined-r{round}.md` with both verdicts and merged action items

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
    FIX -> VERIFY [label="attempts < max"];
    FIX -> COMMIT [label="attempts >= max"];
    COMMIT -> REVIEW;
    REVIEW -> DONE [label="both approve"];
    REVIEW -> BUILD [label="changes requested\n(rounds < max)"];
    REVIEW -> DONE [label="changes requested\n(rounds >= max)"];
}
```
