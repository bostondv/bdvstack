---
name: phase-runner
description: Use when executing autonomous autopilot phases — concrete orchestration recipes for EXPLORE, BUILD, TEST, VALIDATE, FIX, COMMIT, and REVIEW
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
7. **Every phase runs immediately when invoked** — do NOT wait for the stop hook to pick up the next phase. After updating state.json, execute the next phase yourself in the same turn if the stop hook continuation tells you to. TEST and COMMIT run directly in the main session — they are not agent-driven. (VALIDATE spawns one agent.)
8. **No sleep polling** — use foreground execution with appropriate timeouts (up to 600000ms) instead of `run_in_background` + sleep loops. For long-running commands, run them foreground with `timeout: 120000`.
9. **Always use `mode="bypassPermissions"`** when spawning agents — autonomous phases must never prompt for permissions, including writes to `.claude/` paths. Pass `mode="bypassPermissions"` on every TaskCreate call.

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
- `journal_append "TEST" "typecheck" "fail" "14 errors in 3 files" "$SESSION_ID"`
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
     mode="bypassPermissions"
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
- After the worker completes, run the simplifier, then transition to TEST.
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
  mode="bypassPermissions"
)
```

**Spawn order matters. These three start IMMEDIATELY — they work from spec, not code:**

1. **Test worker** — writes test skeletons from acceptance criteria before code exists
2. **QA tester** — writes qa-guide.md from spec before code exists. The QA tester does NOT write a browser test plan — runtime verification is handled by the separate VALIDATE phase if `verification_loop` is enabled in state.json.
3. **Spec Guardian** — validates spec fidelity as work lands

**Then spawn code workers:**

4. **Frontend workers** — one per independent UI component/page
5. **Backend workers** — respect dependency chains (models -> DB -> routes -> services). If tasks are sequential, encode that in the task descriptions ("wait for task X to complete before starting").

**If `verification_loop: true` in state.json**, append this block to EVERY worker prompt so VALIDATE has concrete instructions to follow:

> ### Validation guide contributions (verification_loop is on)
> As you build, contribute to `{session_dir}/validation-guide.md` (create it if missing — use the template at `${CLAUDE_PLUGIN_ROOT}/templates/validation-guide.md`). Append entries under the appropriate sections:
> - **Prerequisites:** any env vars, services, or auth state needed to exercise your changes (e.g. `DATABASE_URL`, `bento` running, logged-in Chrome session)
> - **Surfaces to exercise:** for backend — the exact `curl` commands hitting your new/changed endpoints with realistic payloads and the expected status code / response shape. For frontend — the route(s), the user actions to take, and the visible state to assert.
> - **Out of scope for VALIDATE:** anything that genuinely can't be exercised at runtime (e.g. cron jobs that fire on a schedule, third-party webhook callbacks). VALIDATE will mark these SKIPPED.
>
> Be concrete and copy-pasteable. The VALIDATE agent has not seen your code — it only has spec.md, exploration.md, and this guide.
>
> **For UI surfaces only**, also append a flow entry to `.browser-flows/flows.yml` (the browser-check format) so VALIDATE can drive it via `agent-browser`. Use the existing structure of the file if entries are already there. Minimal entry:
> ```yaml
> <slug-name>:
>   path: <route you added/changed>
>   criteria: <what should be visible / what action to take, in plain English>
> ```
> If `.browser-flows/flows.yml` doesn't exist, create it with a top-level commented header — the dance-spec preflight only scaffolds when the user opts in. Skip the flows.yml write if the file is absent and `browser_check_scaffolded` is false in state.json.

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
     mode="bypassPermissions"
   )
   ```
4. Wait for simplifier to complete

### Step 6: Transition

`TeamDelete` the build team. Log to journal: `journal_append "BUILD" "spawn workers" "complete" "{N} workers completed" "$SESSION_ID"`. Update state: set phase to `TEST`. **Execute TEST immediately in the same turn — do not stop.**

---

## TEST Phase

**Goal:** Run all quality gates (lint, typecheck, tests, custom checks). This phase runs directly in the main session — do NOT spawn agents for this. **Always required.** Runtime verification of the feature itself happens in the separate VALIDATE phase.

### Steps

1. **Discover affected files** to scope checks for speed:
   ```bash
   git fetch origin main 2>/dev/null || git fetch origin master 2>/dev/null || true
   BASE=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null || git rev-parse HEAD~1)
   git diff --name-only "$BASE"...HEAD > {session_dir}/affected-files.txt
   git diff --name-only >> {session_dir}/affected-files.txt   # uncommitted too
   sort -u {session_dir}/affected-files.txt -o {session_dir}/affected-files.txt
   ```
   If the affected list is empty, skip scoping and run the full suite.

2. **Discover quality commands from three sources** (in priority order):

   **a. Custom quality gates from spec.** Read `{session_dir}/spec.md` and look for a `## Custom Quality Gates` section. If found, these are plan-specific verification commands (e.g., specific test files, bundle analysis scripts). Run each command listed. These are IN ADDITION TO standard checks, not a replacement.

   **b. Project-specific commands.** Read `CLAUDE.md` (and `.claude/CLAUDE.md` if it exists) and `exploration.md` from the session directory. Look for lint, typecheck, test, and format commands (e.g. `./script/lint`, `npm run test`, `bundle exec rspec`).

   **c. Generic fallback.** If no project-specific commands are found, fall back to the generic quality gates script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-quality-gates.sh
   ```

3. **Try scoped invocations first** for speed. The goal: when the project's chosen test/lint runner can target only the affected files, do that instead of running the whole suite.

   You don't know what runner the project uses — **discover it from the project itself**:
   - Read `exploration.md` for the test/lint commands and the framework names it identifies
   - Check `CLAUDE.md`, `package.json` scripts, `Makefile`, `pyproject.toml`, `Gemfile`, etc. for the actual commands
   - Check the runner's `--help` output if you're unsure whether a scoped flag exists (`<runner> --help | head -50`)

   For each discovered command:
   - If you can identify a documented way to scope it to specific files, prefer that for the affected list (filtered to file types the tool actually accepts).
   - Otherwise, run it as documented (whole suite).
   - If a scoped invocation errors out (unknown flag, exits before doing real work), fall back to the unscoped command.

   Rules:
   - **Custom Quality Gates from the spec are run as written** — never try to scope them.
   - Typecheck and build steps are usually project-wide; don't try to scope them unless the project's docs explicitly support it.
   - If in doubt, run the unscoped command. Speed is a nice-to-have; correctness is mandatory.

4. **Run each check.** For each command:
   - Redirect output to a file: `{command} > {session_dir}/quality-checks/{check-name}.txt 2>&1`
   - Check the exit code for pass/fail
   - If failed, read only the **first 20 lines** and **last 10 lines** of the output file — not the full output
   - The generic `check-quality-gates.sh` script already saves per-check output to `{session_dir}/quality-checks/` — read those files selectively
   - Pass the specific output file paths to FIX agents so they can read targeted sections

5. **Determine the next phase based on `verification_loop`** in state.json:
   - If ALL quality gate checks pass:
     - If `verification_loop: true` → log `journal_append "TEST" "quality gates" "pass" "all checks passed" "$SESSION_ID"`, set phase to `VALIDATE`. **Execute VALIDATE immediately in the same turn.**
     - Otherwise → log `journal_append "TEST" "quality gates" "pass" "all checks passed" "$SESSION_ID"`, set phase to `COMMIT`. **Execute COMMIT immediately in the same turn.**
   - If ANY quality gate checks fail → save summary to `{session_dir}/quality-gate-results.txt` (include which checks failed and the paths to their detailed output files in `{session_dir}/quality-checks/`), set `fix_source: "test"` in state.json, log `journal_append "TEST" "quality gates" "fail" "{N} checks failed: {names}" "$SESSION_ID"`, set phase to `FIX`. **Execute FIX immediately in the same turn.**

---

## VALIDATE Phase

**Goal:** Exercise the feature end-to-end at runtime to prove it actually works — not just that it compiles and unit tests pass. Inspired by the `/go` skill's verify phase. **Only runs if `verification_loop: true` in state.json.**

The validator **actually runs the feature in the environment** — starts the service, drives the browser, runs the CLI binary, etc. It does not simulate. If it finds real bugs, the loop tries to fix them and re-validate. If it can't easily resolve (e.g., env issues, attempts exhausted), it surfaces the findings in the draft PR description and continues — never deadlocks the autonomous loop.

### Skip check

If `verification_loop` is not `true` in state.json, this phase should never run — TEST transitions directly to COMMIT in that case. If something invokes VALIDATE anyway, write `validate-results.md` with `Status: skipped` and transition to COMMIT.

### Steps

1. **Read state and detect feature type.** Read `{session_dir}/spec.md`, `{session_dir}/exploration.md`, and `state.json`. Note `validate_base_url`, `validate_attempts`, `max_validate_attempts` (default 3), and `total_fix_attempts` / `max_total_fixes`. Categorize the feature:

   | Category | Signals from spec/exploration |
   |----------|-------------------------------|
   | **Backend / API** | Spec mentions endpoints, routes, services, DB models. Exploration shows server framework. |
   | **Frontend / UI** | Spec mentions pages, components, forms, user flows. Exploration shows React/Vue/etc. |
   | **CLI / script / library** | Spec mentions a binary, command, function, or module API. |
   | **Pure refactor** | Spec is structural with no behavior change. |

   A feature can span categories (full-stack) — exercise both sides.

2. **Create a validation team:**
   ```
   TeamCreate(name="autopilot-validate-{session_id}-attempt{validate_attempts}")
   ```

3. **Spawn ONE general-purpose validator agent** that ACTUALLY runs the feature:
   ```
   TaskCreate(
     team_id={team_id},
     prompt="You are running end-to-end validation for an autopilot session. Your job is to ACTUALLY RUN the feature and prove it works at runtime — not just that it compiles and tests pass. Quality gates already ran and passed.

     ## Step 0: Discover Project Conventions
     Before doing anything else, look for project-specific runtime / browser / dev-server conventions:
     - `{session_dir}/validation-guide.md` — workers wrote concrete prerequisites, surfaces, and out-of-scope notes here during BUILD. **READ THIS FIRST if it exists** — it's the most precise instructions you'll get.
     - `.browser-flows/flows.yml` — named browser flows (browser-check format) with paths, scripts, and criteria. If present, prefer running these flows over ad-hoc navigation for UI scenarios.
     - `.browser-check/config.yaml` — host URL, auth patterns, device settings.
     - `.claude/rules/` — any files mentioning local dev, URLs, ports, auth, runtime testing
     - `CLAUDE.md` or `.claude/CLAUDE.md` — sections about dev server, browser, runtime testing
     - `exploration.md` at {session_dir}/exploration.md
     - Project README / Makefile / package.json scripts for `dev`, `start`, `serve`

     If they specify how to connect to the app, what URL/port to use, how auth works — **follow those instructions instead of the generic defaults below.** Project conventions override.

     ## Context
     - Spec: {session_dir}/spec.md (READ THIS FIRST)
     - Codebase conventions: {session_dir}/exploration.md
     - Validation guide (worker-authored): {session_dir}/validation-guide.md (READ if present)
     - Feature category (initial guess from orchestrator): {category}
     - Base URL (if applicable): {validate_base_url or 'unset — discover from project conventions'}
     - Browser-check configured: {browser_check_configured}
     - Attempt: {validate_attempts + 1} of {max_validate_attempts}

     ## You MUST Try to Run It
     Do not just read code and reason about it. Execute it. The whole point of this phase is to catch what static checks miss — runtime errors, broken wiring, wrong responses, missing data.

     - Backend services: start the dev server (e.g. `bento`, `make run`, `npm run dev`, `cargo run`). If the project has a known way to start it (in CLAUDE.md, README, package.json scripts), use that. Tail logs to a file and check it for boot errors. If the server is already running on the expected port, reuse it.
     - APIs: hit the new/changed endpoints with `curl` (or `httpie`). Show actual status codes and response bodies.
     - Frontend / UI: use `agent-browser --auto-connect` to drive the user's already-running Chrome. Boston's standing preference is `agent-browser` over Playwright/DevTools MCP.
       - **If `.browser-flows/flows.yml` exists**, prefer running its named flows over ad-hoc navigation. Each entry has `path` (or `script`) + `criteria` — open the URL or run the script, then validate against the criteria. Workers may have added new flow entries during BUILD for the surfaces they built.
       - Workflow: `agent-browser open <url>` → `agent-browser wait --load networkidle` → `agent-browser snapshot -i` → interact via @eN refs → re-snapshot after navigation → screenshot for evidence.
       - Cover the golden path first, then the edge cases the spec calls out.
       - Run agent-browser commands ONE AT A TIME — never `run_in_background`.
     - CLI / script: actually invoke the binary with realistic inputs. Show the output.
     - Library: write a tiny driver under `{session_dir}/validate-scratch/` that imports the library and exercises the new API.

     ## Best-Effort Environment Setup
     - If `agent-browser` is not installed (`which agent-browser` returns nothing) → record SKIPPED for browser scenarios, continue with whatever else you can exercise.
     - If a dev server fails to start cleanly → capture the boot error in the results, mark related scenarios SKIPPED (with the boot error as the reason), and continue with the rest. Do not paper over.
     - If you hit an auth wall on a UI flow (URL contains '/login' or login form visible) and Chrome Debug is not logged in → record SKIPPED with the auth-wall reason for that flow, continue with the rest.
     - If a required dependency is missing → install if it's lightweight and the project clearly expects it (e.g. `npm install`, `uv sync`, `bundle install`); otherwise record SKIPPED with the missing-dep reason.

     **Continue past blockers.** Exercise as much as you can. Don't bail on the whole phase because one scenario can't be set up.

     ## Rules
     - **Do NOT modify project source code.** You are exercising, not building. If you find a bug, record it in detail (file paths, error messages, repro steps) — the FIX phase will handle it.
     - You MAY write throwaway driver scripts under `{session_dir}/validate-scratch/`.
     - **Never claim success you didn't observe.** Show the actual command output, screenshot path, or curl response. If you couldn't run it, say SKIPPED with the reason. No fabrication.

     ## Output
     Write results to `{session_dir}/validate-results.md`:

     ```markdown
     # Validation Results

     **Status:** pass | partial | fail | skipped
     **Strategy used:** <api / browser / cli / library / refactor-only / mix>
     **Summary:** <one paragraph: what you exercised and the headline result>

     ## Scenarios

     ### Scenario 1: <descriptive name>
     **Strategy:** <curl / agent-browser / direct invocation / etc.>
     **Status:** PASS | FAIL | SKIPPED
     **Evidence:** <curl response / screenshot path / command output / why skipped>
     **Notes:** <observed behavior, deviations from spec>

     ### Scenario 2: ...

     ## Bugs Found
     For each bug, provide enough detail for a fix agent to act on it without re-running validation:
     - **Bug:** <short title>
       - **Repro:** <exact command / URL / steps>
       - **Expected:** <what the spec / common sense says should happen>
       - **Actual:** <what actually happened, with the error message or response>
       - **Suspected location:** <file:line if you can identify it from a stack trace>
     <empty bullet list if no bugs>

     ## Skipped / Not Verifiable
     <why scenarios were skipped, e.g. 'agent-browser not installed', 'no dev server', 'auth wall', 'env-only feature'>
     ```

     Close any browser session you opened with `agent-browser close` before finishing.",
     model="claude-opus-4-6",
     mode="bypassPermissions"
   )
   ```

4. **Wait for the validator** to complete, then read `{session_dir}/validate-results.md`. Increment `validate_attempts` in state.json.

5. `TeamDelete` the validation team.

6. **Decide what to do next based on Status and Bugs Found:**

   - **`pass`, or `partial`/`fail`/`skipped` with empty Bugs Found** (i.e. only env-level skips):
     - Log `journal_append "VALIDATE" "runtime verification" "<status>" "<one-line summary>" "$SESSION_ID"`
     - Set phase to `COMMIT`. **Execute COMMIT immediately.**

   - **`fail`/`partial` with non-empty Bugs Found** — real runtime bugs were caught:
     - **Bail checks** (any of these → log and force-COMMIT, results land in PR description):
       - `validate_attempts >= max_validate_attempts` (we've tried enough)
       - `total_fix_attempts >= max_total_fixes` (session-wide fix budget exhausted)
       - **Stall:** the new validate-results.md has the same Bugs Found list as the previous attempt's (no progress) — compare bug titles
     - On bail: log `journal_append "VALIDATE" "bail" "force-commit" "reason: {which limit / stall}" "$SESSION_ID"`, set phase to `COMMIT`. **Execute COMMIT immediately.**
     - Otherwise:
       - Save a snapshot of the bug list to `{session_dir}/last-validate-bugs.txt` for the next-round stall comparison
       - Set `fix_source: "validate"` in state.json
       - Log `journal_append "VALIDATE" "bugs found" "fix" "{N} bugs, attempt {validate_attempts}/{max_validate_attempts}" "$SESSION_ID"`
       - Set phase to `FIX`. **Execute FIX immediately.** FIX will read the Bugs Found list from validate-results.md, fix them, then transition back to TEST. TEST passes → VALIDATE again → loop.

---

## FIX Phase

**Goal:** Fix failures from the previous phase using targeted agents. The previous phase is identified by `fix_source` in state.json:

- `fix_source: "test"` → quality gate failures from TEST. Read `{session_dir}/quality-gate-results.txt` and the per-check `.fail.txt` files.
- `fix_source: "validate"` → runtime bugs caught by VALIDATE. Read the **Bugs Found** section of `{session_dir}/validate-results.md`.

After fixing, FIX always returns to TEST so quality gates re-run on the modified code (TEST will then transition to VALIDATE if `verification_loop` is true).

### Steps

1. Read `fix_source` from state.json. Default to `"test"` if missing (legacy state files).
2. Read failure input based on source:
   - **`fix_source: "test"`** → read `{session_dir}/quality-gate-results.txt` for the failure summary. Read only the relevant `.fail.txt` files (first 30 lines). Pass file paths to fix agents so they can read what they need.
   - **`fix_source: "validate"`** → read `{session_dir}/validate-results.md`, focusing on the **Bugs Found** section (file:line, repro steps, expected vs actual). Pass the file path to fix agents so they can read the full context.
3. Read `fix_attempts`, `max_fix_attempts`, `total_fix_attempts`, `max_total_fixes`, and `last_error_count` from state.json. If `total_fix_attempts` or `max_total_fixes` are missing, initialize them (`total_fix_attempts` = current value of `fix_attempts`, `max_total_fixes` = 5).
4. **Bail checks — if ANY of these are true, force-COMMIT:**
   - `fix_attempts >= max_fix_attempts` (per-round limit, applies to test-source fixes)
   - `total_fix_attempts >= max_total_fixes` (session-wide limit)
   - **Stall detected (test source only):** count current errors and compare to `last_error_count` in state.json. If the count is identical for 2 consecutive attempts, we're stalled.

   Note: validate-source bail checks live in the VALIDATE phase itself (`validate_attempts >= max_validate_attempts`, bug-list stall). When VALIDATE bails it goes straight to COMMIT without invoking FIX.

   On bail: log `journal_append "FIX" "bail" "force-commit" "reason: {which limit hit}" "$SESSION_ID"`, set phase to `COMMIT`. **Execute COMMIT immediately.**
5. **Otherwise:**

   a. **Checkpoint current state** before attempting fixes (so we can revert if the fix makes things worse). Stage and commit all current changes as a checkpoint:
   ```bash
   git add -A && git commit -m "autopilot: checkpoint before fix attempt ${fix_attempts} (source: ${fix_source})" --allow-empty
   ```
   Record the checkpoint commit hash for potential revert:
   ```bash
   CHECKPOINT_SHA=$(git rev-parse HEAD)
   ```

   b. Create a team:
   ```
   TeamCreate(name="autopilot-fix-{session_id}-attempt{fix_attempts}-{fix_source}")
   ```

   c. Analyze the failure input and categorize:
      - Test-source: type errors, lint errors, test failures, etc.
      - Validate-source: each Bug in the Bugs Found list is its own item.

   d. **Think-harder escalation** — if this is the LAST attempt (`fix_attempts == max_fix_attempts - 1`), add this to EVERY fix agent's prompt:
   > "ESCALATION: Previous fix approaches have failed. This is the FINAL attempt before we ship with known issues. Before writing code:
   > 1. Re-read spec.md — is the implementation approach fundamentally wrong?
   > 2. Re-read exploration.md — are you fighting a codebase convention?
   > 3. Read {session_dir}/journal.tsv — what patterns do you see in the failures?
   > 4. Consider: would a different architectural approach sidestep these errors entirely?
   > 5. Try a more radical fix — the conservative approach hasn't worked."

   e. For EACH failure category, spawn a targeted fix agent. Use a source-aware prompt:

   **Test-source prompt:**
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
     mode="bypassPermissions"
   )
   ```

   **Validate-source prompt:**
   ```
   TaskCreate(
     team_id={team_id},
     prompt="You are a focused runtime-bug fixer. The end-to-end validator actually ran the feature and caught real bugs that static checks missed.\n\n
       Project root: {cwd}\n
       Spec: {session_dir}/spec.md\n
       Codebase conventions: {session_dir}/exploration.md (READ THIS)\n
       Validation results: {session_dir}/validate-results.md (READ THE 'Bugs Found' SECTION)\n\n
       BUG TO FIX:\n{bug title and detail extracted from Bugs Found}\n\n
       Rules:\n
       - Use the repro / expected / actual / suspected location from validate-results.md to localize the bug\n
       - Fix the underlying issue. Do NOT add try/catch to swallow the error or write a workaround\n
       - Do not modify files another fix agent is working on\n
       - When complete, list exactly what you changed and how it addresses the bug",
     model="claude-opus-4-6",
     mode="bypassPermissions"
   )
   ```

   **Important:** If multiple agents might touch the same file, merge them into a single agent to avoid conflicts.

   f. Wait for all fix agents to complete

   g. **Post-fix regression check (test-source only):** Before transitioning to TEST, do a quick check — did the fix introduce MORE errors than it resolved? Run the specific failed checks again:
   ```bash
   # Quick targeted re-check of just the previously-failing gates
   {failed_command} > {session_dir}/quality-checks/{check-name}-postfix.txt 2>&1
   ```
   Compare error counts. If errors INCREASED compared to the pre-fix state, revert to the checkpoint:
   ```bash
   git reset --hard ${CHECKPOINT_SHA}
   ```
   Log: `journal_append "FIX-${fix_attempts}" "fix attempt" "reverted" "errors increased from N to M, reverted to checkpoint" "$SESSION_ID"`, increment fix_attempts, and retry with a different approach. (Validate-source fixes skip this check — TEST will surface any regression on the next pass.)

   h. If errors decreased or stayed the same (or this is a validate-source fix), squash the checkpoint commit into the fix (keeps history clean):
   ```bash
   git reset --soft ${CHECKPOINT_SHA}~1 && git add -A && git commit -m "autopilot: fix attempt ${fix_attempts} (${fix_source})"
   ```
   Log: `journal_append "FIX-${fix_attempts}" "fix attempt" "progress" "source: ${fix_source}, errors: N->M" "$SESSION_ID"`
   i. `TeamDelete` the fix team
   j. Update state.json:
      - Test-source: increment `fix_attempts`, increment `total_fix_attempts`, write current error count to `last_error_count`
      - Validate-source: increment `total_fix_attempts` only (validate's per-round counter is `validate_attempts`, managed by VALIDATE)
   k. Set phase to `TEST`. **Execute TEST immediately in the same turn.** TEST will run quality gates on the modified code, then transition to VALIDATE if `verification_loop` is true.

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

   ## Verification
   <!-- Only include if `{session_dir}/validate-results.md` exists. Summarize the runtime verification in 2-4 lines: status, strategy, and any bugs found. Link to the results file is unnecessary — paste the relevant Bugs Found / Skipped sections inline. Skip this section entirely if VALIDATE didn't run. -->
   ```

   **Rules for PR descriptions:**
   - Lead with **what** and **why**, not a list of files changed
   - Keep the summary to 1-3 sentences — the diff speaks for itself
   - Omit Architecture/Results/Verification sections entirely if they don't apply
   - Never dump the spec into the PR body
   - No boilerplate like "This PR implements..." — just state what it does
   - If `{session_dir}/validate-results.md` exists and contains bugs or skipped scenarios, surface them in the Verification section so the reviewing user sees them on the draft PR

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
     mode="bypassPermissions"
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
     mode="bypassPermissions"
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
    BUILD -> TEST;
    TEST -> VALIDATE [label="all pass\n+ verification_loop=true"];
    TEST -> COMMIT [label="all pass\n+ verification_loop=false"];
    TEST -> FIX [label="failures\n(fix_source=test)"];
    FIX -> TEST [label="fix complete"];
    FIX -> FIX [label="errors increased\n(revert + retry)"];
    FIX -> COMMIT [label="attempts >= max"];
    VALIDATE -> COMMIT [label="pass / env-only skips"];
    VALIDATE -> FIX [label="bugs found\n(fix_source=validate)\n+ attempts < max"];
    VALIDATE -> COMMIT [label="bugs found\n+ attempts >= max\n(non-blocking, in PR body)"];
    COMMIT -> REVIEW;
    REVIEW -> DONE [label="both approve"];
    REVIEW -> BUILD [label="changes requested\n(rounds < max)"];
    REVIEW -> DONE [label="changes requested\n(rounds >= max)"];
}
```
