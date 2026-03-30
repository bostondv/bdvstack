---
description: "Autonomous SWE agent loop — turns a feature description into a reviewed PR"
user-invocable: true
argument-hint: "[--non-interactive] <feature description>"
---

# Autopilot — Autonomous Feature Development

You are the orchestrator for an autonomous software engineering loop. Your job is to take a feature description, run an interactive spec phase, then hand off to the autonomous loop.

## Input

The user's argument is the feature description: `$ARGUMENTS`

**Parse the arguments:** Check if `$ARGUMENTS` starts with `--non-interactive`. If so, strip the flag and use the remainder as the feature description. Example: `--non-interactive Add user preferences page` → feature is `Add user preferences page`.

## Phase 1: WORKSPACE QUESTION

**This is always the first question, even in `--non-interactive` mode.**

Use `AskUserQuestion` to ask:

> Where should I do this work?
> 1. **This session** — work in the current directory
> 2. **New worktree** — create an isolated worktree (via graft) with its own branch

Record the answer. If the user picks worktree, note it — the worktree is created *after* the spec is finalized (Phase 2), right before autonomous execution begins.

For `--non-interactive` mode: if the user didn't answer this question (no interaction at all), default to **this session**.

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

**If `--non-interactive` was passed, skip to the non-interactive path below.**

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
7. **Launch a new Claude session in the worktree** using `cmux` if available, otherwise print the command:
   ```bash
   # If cmux is available:
   cmux split --cmd "cd <worktree_project_path> && claude '$CONTINUATION'"
   # Otherwise, print for the user:
   echo "Run this in a new terminal:"
   echo "  cd <worktree_project_path> && claude '$CONTINUATION'"
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
- Never use worktrees for agents — changes get lost on cleanup.
- Never commit or push without the phase runner reaching the COMMIT phase.
- Keep `state.json` updated at every phase transition.
- If anything fails catastrophically, set phase to `DONE` with an error message in state.json.
