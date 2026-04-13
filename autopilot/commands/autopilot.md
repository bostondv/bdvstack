---
description: "Autonomous SWE agent loop — turns a feature description into a reviewed PR"
user-invocable: true
argument-hint: "[--non-interactive | --plan <path> [--phase <N>]] <feature description>"
---

# Autopilot — Autonomous Feature Development

You are the orchestrator for an autonomous software engineering loop. Your job is to take a feature description, run an interactive spec phase, then hand off to the autonomous loop.

## Input

The user's argument is the feature description: `$ARGUMENTS`

**Parse the arguments:**

1. **`--plan <path> [--phase <N>]`** — Plan-import mode. `<path>` is a file path to an existing plan/spec document. Optional `--phase <N>` extracts only Phase N from the plan. Any remaining text after flags is the feature description override; if none provided, derive it from the plan's title. **Skips DANCE entirely.**

2. **`--non-interactive`** — Auto-generates a spec from the feature description. **Skips DANCE.**

3. **No flags** — Interactive mode with DANCE interview.

Examples:
- `--plan ~/Dev/docs/plans/loadable-dialog.md --phase 1` → imports Phase 1 of the plan
- `--plan ~/Dev/docs/plans/loadable-dialog.md` → imports the entire plan as spec
- `--plan ./spec.md Add LoadableDialog wrapper` → imports plan with a custom feature name
- `--non-interactive Add user preferences page` → auto-generates spec
- `Add user preferences page` → interactive DANCE interview

## Phase 1: WORKSPACE QUESTION

**This is always the first question, even in `--non-interactive` mode.**

Use `AskUserQuestion` to ask:

> Where should I do this work?
> 1. **This session** — work in the current directory
> 2. **New worktree** — create an isolated worktree (via graft) with its own branch
>
> **Note:** Autopilot runs best in **Accept Edits** mode (`Shift+Tab` → Accept Edits) to avoid permission prompts during autonomous execution.

Record the answer. If the user picks worktree, note it — the worktree is created *after* the spec is finalized (Phase 2), right before autonomous execution begins. Worktree sessions are launched with `--mode acceptEdits` automatically.

For `--non-interactive` and `--plan` modes: if the user didn't answer this question (no interaction at all), default to **this session**.

## Phase 2: SETUP

Run the setup script to initialize a session directory and state file:

```
${CLAUDE_PLUGIN_ROOT}/scripts/setup-autopilot.sh "$FEATURE_DESCRIPTION"
```

This creates:
- A session directory under `~/.claude/autopilot/sessions/<session-id>/`
- A `state.json` with phase set to `SPEC`
- An entry in `~/.claude/autopilot/active-sessions.json`
- A `.claude/autopilot.local.md` marker in the working directory

Read the created `state.json` to get the session ID and session directory path.

Save the workspace choice to state.json: `"worktree": true|false`.

Create a feature branch name using the convention: `bostondv/<slug>` where `<slug>` is a kebab-case version of the feature description. Save it to state.json but **do not create the branch yet** — if using a worktree, graft creates it.

## Phase 3: SPEC

**If `--plan` was passed, skip to the plan-import path below.**
**If `--non-interactive` was passed, skip to the non-interactive path below.**

### Plan-import (`--plan <path> [--phase <N>]`)

The plan file IS the spec. Skip DANCE entirely.

1. **Read the plan file** at the provided path. If the file doesn't exist, tell the user and stop.

2. **Extract the feature name.** In priority order:
   - Use the feature description override from the arguments (if any text after the flags)
   - Read the plan's first `# heading` and use it
   - Fall back to the filename (slugified)

3. **Phase extraction** (if `--phase <N>` was given):
   - Scan the plan for a section matching `## Phase <N>` (case-insensitive, allows text after the number like `## Phase 1: Define LoadableDialog`)
   - Extract everything from that header until the next `## Phase` header (or end of file)
   - Also extract any content BEFORE the first `## Phase` header — this is the plan preamble (architecture notes, file structure, tech stack) that provides context regardless of which phase is being executed
   - The extracted phase becomes the spec; the preamble is prepended for context
   - Update the feature name to include the phase: e.g., `LoadableDialog — Phase 1: Define wrapper + first migration`

4. **Detect custom quality gates.** Scan the plan for verification commands — look for patterns like:
   - `yarn jest`, `yarn typecheck`, `yarn eslint`, `yarn build-rspack-stats`
   - `bun .claude/skills/...`
   - Bash code blocks inside steps named "Verify", "Run typecheck", "Run lint", "Run tests", "Bundle verification"
   - Any `- [ ] **Step N: Run ...**` or `- [ ] **Step N: Verify ...**` patterns

   Collect these into a `## Custom Quality Gates` section appended to the spec:
   ```markdown
   ## Custom Quality Gates
   In addition to standard lint/typecheck/test, run these project-specific checks during VERIFY:
   - `yarn jest client/store/platform/shared/__tests__/LoadableDialog.spec.tsx --runInBand`
   - `yarn build-rspack-stats`
   - `bun .claude/skills/bundle-analysis/scripts/chunk-group.ts LandingPageModalInternal`
   ```

5. **Write `spec.md`** to the session directory. The spec is the plan content (or extracted phase) as-is — do NOT reformat it into the standard spec.md template. Plans are already more detailed than what DANCE produces. Preserve exact code blocks, exact file paths, exact commands. Workers need these verbatim.

6. **Set `browser_testing` to `false`** in state.json (plans don't use the browser testing flow).

7. **Continue to branch/worktree setup and autonomous execution** — same as the interactive path from "Once approved" onward. There is no approval step — the plan was pre-approved by the user.

### Interactive (default)

**This phase is interactive — the user must answer questions.**

**IMPORTANT: Always use the `AskUserQuestion` tool to ask questions. Never output questions as plain text.**

Adopt the persona of the **Team Lead**, a senior PM agent. Invoke the `dance-spec` skill to conduct a structured interview using the DANCE framework:

- **Discover**: Understand the user's goal, motivation, and constraints (2-3 questions)
- **Analyze**: Dig into edge cases, dependencies, and scope boundaries (2-3 questions). If the feature has a UI component and the user hasn't already specified, ask about browser testing.
- **Narrow**: Prioritize and cut scope to an achievable first iteration (2 questions)
- **Code**: Clarify technical preferences, patterns, and conventions (1-2 questions)
- **Evaluate**: Confirm acceptance criteria and definition of done (1 question)

The Team Lead asks 8-10 structured questions total, one at a time, waiting for the user's response before proceeding.

After the interview, synthesize the answers into a `spec.md` and save it to the session directory. Present the spec to the user for approval. If the user requests changes, revise and re-present.

Once approved:

1. **If this session:** Create the branch and continue in-process:
   ```bash
   git checkout -b <branch>
   ```
   Update `state.json`: set phase to `EXPLORE`. Continue to Phase 4.

2. **If worktree was selected:** Hand off to a new terminal (see Worktree Handoff below).

### Non-interactive (`--non-interactive`)

Skip the DANCE interview entirely. Instead:

1. **Explore the codebase briefly** — read the project structure, `CLAUDE.md`, `package.json` or equivalent, and any files obviously related to the feature description. This gives you enough context to write a reasonable spec.
2. **Generate `spec.md` automatically** from the feature description and codebase context. Use the same format as the interactive path (Overview, User Stories, Acceptance Criteria, Technical Approach, Out of Scope, Browser Testing). Make reasonable assumptions — prefer a tight, minimal scope over an ambitious one.
3. **Set `browser_testing` to `false`** in state.json (can't ask the user).
4. **Save `spec.md`** to the session directory.
5. **If this session:** Create the branch normally, set phase to `EXPLORE`, continue to Phase 4.
6. **If worktree was selected:** Hand off to a new terminal (see Worktree Handoff below).

Do NOT ask the user any questions beyond the workspace question. Do NOT present the spec for approval.

### Worktree Handoff

When the user chose "new worktree", the original session creates the worktree and then **hands off to a new Claude instance** whose native cwd is the worktree. This solves all cwd issues — git, gh, scripts, and agents all work naturally.

1. Tell the user: "Creating worktree — this may take a minute or two."
2. Create the worktree:
   ```bash
   graft new <branch> .
   ```
   Wait for graft to complete fully. Graft typically handles dependency installation, but if a build or quality gate later fails due to missing dependencies, install them then (e.g. `uv sync`, `npm install`).
3. Get the worktree project path using `graft cd <branch>` — this automatically resolves to the correct monorepo subdirectory:
   ```bash
   WORKTREE_PROJECT_PATH="$(graft cd <branch> --print)"
   ```
4. Save to state.json: `"worktree_path": "<worktree_project_path>"`. Set phase to `EXPLORE`.
5. Create the `.claude/autopilot.local.md` marker in the worktree project path.
6. Build the continuation prompt:
   ```
   CONTINUATION="Continue autopilot session <session_id>. Read state at ~/.claude/autopilot/sessions/<session_id>/state.json. Invoke the phase-runner skill and run phases EXPLORE through DONE."
   ```
7. **Launch a new Claude session in the worktree** using `cmux` if available, otherwise print the command. Always use `--mode acceptEdits` so the autonomous loop isn't blocked by write permission prompts:
   ```bash
   # If cmux is available:
   cmux split --cmd "cd <worktree_project_path> && claude --mode acceptEdits '$CONTINUATION'"
   # Otherwise, print for the user:
   echo "Run this in a new terminal:"
   echo "  cd <worktree_project_path> && claude --mode acceptEdits '$CONTINUATION'"
   ```
8. **This session is now done.** Tell the user: "Autopilot is running in the new terminal. You can watch and interact with it there." Do NOT continue to Phase 4 in this session.

## Phase 4+: AUTONOMOUS EXECUTION

**This phase only runs in the "this session" path** (or in the new Claude instance after worktree handoff).

From `EXPLORE` onward, the **stop hook** takes over and drives all remaining phases automatically:

`EXPLORE` → `BUILD` → `VERIFY` → `FIX` (if needed) → `COMMIT` → `REVIEW` → `DONE`

The stop hook detects the current phase, injects a continuation prompt that tells you to invoke the `phase-runner` skill, and blocks exit. The phase-runner has concrete orchestration recipes for each phase — follow them exactly.

**You do NOT manually drive phases after SPEC.** The stop hook handles the loop.

## Key Rules

- The SPEC phase is the **only** interactive phase. Everything after is autonomous.
- **All substantive work happens in agents** via `TeamCreate` + `TaskCreate` — main session is coordinator only.
- Always specify model explicitly as `claude-opus-4-6` in TaskCreate (never use `inherit`).
- Always specify `mode: "bypassPermissions"` in TaskCreate so agents aren't blocked by write/sensitive-path prompts.
- Never use worktrees for agents — changes get lost on cleanup.
- Never commit or push without the phase runner reaching the COMMIT phase.
- Keep `state.json` updated at every phase transition.
- If anything fails catastrophically, set phase to `DONE` with an error message in state.json.
