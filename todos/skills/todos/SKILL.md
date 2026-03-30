---
name: todos
description: Use when user mentions todos, to-dos, tasks, what they're working on, what's on their plate, checking in, or asks to add/remove/update work items. Also use at session start when user checks in.
user-invocable: true
---

# Todo Management

Manage a persistent, file-based todo system where each todo is a directory containing a `todo.md` file with YAML frontmatter. Todos can live at user-level or project-level.

## Invocation

Explicitly via `/todos` or triggered when the user:

- Asks "what am I working on?", "what's on my plate?", "what's left?"
- Says "add a todo", "track this", "put this on my list"
- Says "mark X as done", "finish X", "complete X"
- Says "remove X", "drop X from my list"
- Says "show my todos", "what are my tasks?"
- Checks in at the start of a session
- Mentions a new work item they want to remember
- Says "start working on #X", "work on #X", "pick up #X", "implement #X"

## Level Detection

Determine the base todos path (`$TODOS`) using these rules:

1. If `--user` flag is provided: use `~/todos/`
2. If `--project` flag is provided: use `<project-root>/.claude/todos/`
3. If the current directory is inside a git repo AND `<project-root>/.claude/todos/` exists: use that (project-level)
4. Otherwise: use `~/todos/` (user-level)

**Finding `<project-root>`**: Walk up from the current directory toward the git root (via `git rev-parse --show-toplevel`), checking each directory for a project marker file. Stop at the first (nearest to cwd) directory containing any of: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, `build.gradle`, `composer.json`, `.claude/`. If no marker is found before reaching git root, use git root.

Store the resolved path as `$TODOS` and use it for all operations in the session.

## Group Defaults

Each group directory can contain a `group.md` file with YAML frontmatter that defines defaults for all todos in that group.

```
---
name: Fig MCP Server
workspace: ~/carrot/enterprise/fig-mcp-server
default_priority: P2
tags: [fig]
---

Optional freeform description of the group/project.
```

**Supported default fields:** `workspace`, `default_priority`, `tags`, `assignee`

**Inheritance rules:**
- When reading a todo, check if the todo's group has a `group.md`
- For each supported field: if the todo's value is empty/unset, use the group default
- Todo-level values always override group defaults
- When creating a new todo in a group with a `group.md`, pre-fill defaults from the group but still write them to the todo's frontmatter (so each todo is self-contained)

**When displaying a todo**, show the effective values (with group defaults applied). Note inherited fields with "(from group)" if relevant.

## Operations

### 1. View Todos (list)

1. Check if `$TODOS/todo-list.md` exists. If not, run the **Regenerate todo-list.md** procedure first.
2. Read `$TODOS/todo-list.md`.
3. Display its contents to the user.
4. Highlight items marked `🔴 OVERDUE` and `⚠ STALE` prominently.
5. Omit `done` items unless the user specifically asks to see them (done items are normally archived, but may exist if auto_archive is off).

### 2. View Single Todo (detail)

1. Find the todo by ID number or title substring match:
   - If a number is given, scan `$TODOS/active/` recursively for a directory whose name starts with that zero-padded number (e.g., `003-`).
   - If text is given, scan all `todo.md` files under `$TODOS/active/` and match against the `title` field (case-insensitive substring).
2. Read the full `todo.md` file from the matched directory.
3. Display the frontmatter as a summary table, then the full body content.

### 3. Add Todo

1. **Check for duplicates**: Before creating anything, scan all `todo.md` files under `$TODOS/active/` and `$TODOS/archive/` (if it exists). For each existing todo, compare its `title` against the new title using fuzzy matching:
   - Tokenize both titles into lowercase words, strip common stop words (`a`, `an`, `the`, `and`, `or`, `to`, `for`, `of`, `in`, `on`, `from`, `with`)
   - A todo is a **suspect duplicate** if 50%+ of the meaningful tokens overlap, OR if one title is a substring of the other (case-insensitive)
   - If any suspects are found, **stop and show the user** a list of matches (ID, title, group, status), then ask:
     > "This looks similar to existing todo(s). What would you like to do?
     > 1. Add it anyway (they're different)
     > 2. Use existing #NNN instead
     > 3. Cancel"
   - Wait for the user's choice before proceeding. If they choose 2 or 3, stop here.
2. **Determine next ID**: Scan all directories under `$TODOS/active/` recursively. For each directory name matching the pattern `NNN-*` (where NNN is digits), parse the numeric prefix. Find the highest existing ID. Increment by 1. Zero-pad to 3 digits.
3. **Generate slug**: Take the title, lowercase it, replace spaces and non-alphanumeric characters with hyphens, collapse multiple hyphens, trim hyphens from ends, truncate to 50 characters.
4. **Read config**: Read `$TODOS/config.md` for `default_group` and `default_priority`. If config doesn't exist, use `general` as default group and `P2` as default priority.
5. **Determine group**: Use the group from user args if provided, otherwise use `default_group` from config.
6. **Read group defaults**: If `$TODOS/active/<group>/group.md` exists, read its frontmatter. Use group defaults to pre-fill `workspace`, `priority`, `tags`, and `assignee` when not specified by the user.
7. **Create directory**: `$TODOS/active/<group>/<NNN>-<slug>/`
   - Create intermediate directories as needed.
8. **Create `todo.md`** with this content:

```
---
id: <integer, not zero-padded>
title: <from user>
status: draft
priority: <from args or config default_priority>
assignee:
workspace:
created: <today YYYY-MM-DD>
updated: <today YYYY-MM-DD>
claimed_at:
due: <from args if provided, otherwise leave empty>
tags: <from args if provided, otherwise []>
blocked_by: <from args if provided, otherwise []>
group: <group name>
---

# <title>

## Description

<description from user if provided, otherwise leave a placeholder>

## Acceptance Criteria

- [ ] <criteria from user if provided>

## Verification

- [ ] Tests pass
- [ ] Manual verification

## Progress

## Notes
```

9. **Regenerate `todo-list.md`** (see procedure below).
10. **Confirm** to the user what was added, including the ID, title, group, and file path.

### 4. Update Todo

1. Find the todo by ID or title match (same logic as View Single Todo).
2. Read the current `todo.md`.
3. Edit the frontmatter fields as requested by the user.
4. **Always** set `updated` to today's date (YYYY-MM-DD).
5. **Special status transitions:**
   - If status changes to `in_progress`: set `claimed_at` to the current ISO 8601 timestamp (e.g., `2026-03-04T14:30:00Z`).
   - If status changes to `done`: check `$TODOS/config.md` for `auto_archive: true`. If true, run the **Archive Todo** procedure after saving.
6. Write the updated `todo.md`.
7. **Regenerate `todo-list.md`**.
8. **Confirm** the changes to the user.

### 5. Archive Todo

1. Find the todo by ID or title match.
2. Read the `todo.md` to get metadata (title, group, assignee).
3. Determine source path: `$TODOS/active/<group>/<NNN>-<slug>/` (or `$TODOS/active/<NNN>-<slug>/` if ungrouped).
4. Determine destination path: `$TODOS/archive/<group>/<NNN>-<slug>/` (preserve group structure; `$TODOS/archive/<NNN>-<slug>/` if ungrouped).
5. Create the destination parent directory if it doesn't exist.
6. Move the entire todo directory from source to destination.
7. **Append to `$TODOS/archive-log.md`:**
   - If the file doesn't exist, create it with this header:
     ```
     # Archive Log

     | ID | Title | Group | Completed | Assignee |
     |----|-------|-------|-----------|----------|
     ```
   - Append a row: `| <ID> | <Title> | <Group> | <today YYYY-MM-DD> | <Assignee> |`
8. **Regenerate `todo-list.md`**.
9. **Confirm** what was archived.

### 6. Delete Todo

1. Find the todo by ID or title match.
2. Read the `todo.md` to get the title for confirmation.
3. **Ask the user for confirmation** before deleting. Show the todo ID, title, and group.
4. If confirmed, remove the entire todo directory.
5. **Regenerate `todo-list.md`**.
6. **Confirm** what was deleted.

### 7. Move Group

1. Find the todo by ID or title match.
2. Read the `todo.md` to get current group.
3. Determine the new group from the user's request.
4. Move the entire todo directory from `$TODOS/active/<old-group>/<NNN>-<slug>/` to `$TODOS/active/<new-group>/<NNN>-<slug>/`.
5. Create the new group directory if it doesn't exist.
6. Update the `group` field in the `todo.md` frontmatter.
7. Update `updated` to today's date.
8. **Regenerate `todo-list.md`**.
9. **Confirm** the move.

### 8. Work Todo

Triggered when the user says "start working on #X", "work on #X", "pick up #X", or "implement #X". Sets up an autonomous Claude session to implement the todo.

#### Prerequisites

- `graft` CLI installed (monorepo-aware git worktree manager) — only needed for Worktree Mode
- cmux or tmux running — only needed for Worktree Mode

#### Steps

1. **Find the todo** by ID (same logic as View Single Todo).
2. **Read the todo** — get title, description, workspace, group, and check if `docs/plan.md` exists in the todo directory.
3. **Resolve workspace**: The todo's `workspace` field (or group default) determines the graft project path. This should be a path relative to the git root (e.g., `customers/store`). If `workspace` is an absolute path like `~/carrot/customers/store`, extract the relative portion after the git root.
4. **Determine execution mode** (no user prompt — pick automatically):
   - If the `/autopilot` skill is available (check the skill list for `autopilot:autopilot`): use **Autopilot Mode**.
   - Otherwise: update the todo status to `in_progress`, set `claimed_at`, regenerate `todo-list.md`, then implement in the current session.

#### Autopilot Mode

When autopilot is available, hand off the todo to the autopilot plugin which handles everything autonomously — spec refinement, exploration, parallel build, verification, review, and PR creation.

1. **Build the autopilot prompt** from the todo context:
   - Read the todo's title, description, and acceptance criteria from `todo.md`
   - If `docs/plan.md` exists in the todo directory, include it as additional context
   - Combine into a feature description string

2. **Resolve the workspace directory**: Navigate to the todo's workspace before invoking autopilot so it runs in the right project context. If workspace is a graft project path, resolve it to the absolute path.

3. **Update todo status** to `in_progress`, set `claimed_at`, set `updated`.

4. **Invoke `/autopilot`** with the feature description. Autopilot will:
   - Run the DANCE interview (Kevin may ask clarifying questions — the user answers)
   - Explore the codebase (Billy)
   - Spawn parallel build teams (workers, test writers, QA)
   - Verify quality (type-check, lint, tests)
   - Create a draft PR
   - Run isolated code review (Daniel + Gilfoyle)
   - Iterate if review requests changes

5. **After autopilot completes**, update the todo status to `in_review` and regenerate `todo-list.md`.

6. **Report to user**: "Todo #X handed off to autopilot. It will interview you for the spec, then run autonomously."

#### Worktree Mode

Worktree mode is not auto-selected. The user must explicitly request it (e.g., "work on #X in a worktree").

1. **Generate variables**:

```bash
GITHUB_USER="${GITHUB_USERNAME:-$(whoami)}"
BRANCH_NAME="$GITHUB_USER/todo-<id>-<slug>"  # e.g., bostondv/todo-19-remove-instacart-dep
TODO_DIR="<absolute path to the todo directory>"  # e.g., ~/todos/active/customers-store/019-remove-instacart-dep-bento-dns-proxy
PROJECT_PATH="<workspace relative to git root>"  # e.g., customers/store
WINDOW_NAME="<human-friendly short title>"  # e.g., "Changelog Skill", "DNS Rewrite" — derive from the todo title, title-cased, max ~30 chars
```

2. **Detect terminal multiplexer**:

```bash
if [[ -n "$CMUX_WORKSPACE_ID" ]] && command -v cmux &>/dev/null; then
    MODE="cmux"
elif [[ -n "$TMUX" ]]; then
    MODE="tmux"
else
    echo "Error: cmux or tmux required for worktree mode"
    exit 1
fi
```

3. **Write startup script** to `/tmp/todo-<id>-<slug>.sh`:

```bash
#!/bin/bash

# Trap to keep window open on any exit
trap '
    EXIT_CODE=$?
    echo ""
    if [ "$EXIT_CODE" -ne 0 ]; then
        echo "ERROR: Script failed (exit code $EXIT_CODE)"
    fi
    echo "Press Enter to close this window."
    read
' EXIT

set -e
echo "Setting up todo #<id>: <title>"
echo ""

BRANCH_NAME="<branch_name>"
PROJECT_PATH="<project_path>"
TODO_DIR="<todo_dir>"

# Create graft worktree
echo "Creating worktree (this may take a few minutes)..."
IN_BENTO_SCRIPT=true graft new "$BRANCH_NAME" "$PROJECT_PATH" --sparse
echo "Worktree created!"

# Get worktree path and cd into it
WORKTREE_ROOT=$(graft info --name "$BRANCH_NAME" -o "template={{.Path}}")
WORK_DIR="$WORKTREE_ROOT/$PROJECT_PATH"

if [[ ! -d "$WORK_DIR" ]]; then
    echo "ERROR: Working directory does not exist: $WORK_DIR"
    echo "Worktree contents:"
    ls -la "$WORKTREE_ROOT"
    exit 1
fi

cd "$WORK_DIR"

# Copy todo context into worktree
echo "Copying todo context..."
mkdir -p .todo-context
cp -r "$TODO_DIR"/* .todo-context/ 2>/dev/null || true
cp -r "$TODO_DIR"/todo.md .todo-context/ 2>/dev/null || true

echo ""
echo "Setup complete. Launching Claude..."
echo ""

# Detect CLI: prefer happy (drop-in claude wrapper) if available
if command -v happy &>/dev/null; then
    CLI="happy"
else
    CLI="claude"
fi

# Launch autonomously
$CLI --dangerously-skip-permissions "$(cat <<'PROMPT'
You are implementing a todo. Read all files in .todo-context/ for the full task description and any supporting context.

If .todo-context/docs/plan.md exists, follow it task-by-task using the superpowers:executing-plans skill.

If no plan exists, read the todo description and acceptance criteria, then implement accordingly.

## Workflow

1. Read .todo-context/todo.md and all other files in .todo-context/
2. Implement the changes following the plan or acceptance criteria
3. Run all relevant tests and checks
4. Fix any failures, loop as needed until checks pass
5. Create a draft PR with: gh pr create --draft --title "<todo title>" --body "<description>"
   - For project-level todos: include "Implements todo #<id>" in the PR body
   - For user-level todos (~\/todos\/): do NOT reference the todo in the PR body (user-level todos are personal tracking)
6. Update the todo status to in_review in BOTH locations:
   - The canonical todo file: $TODO_DIR/todo.md
   - The local copy: .todo-context/todo.md
7. Send a completion notification

## Notifications

When finished or blocked, notify the user. Try in order until one works:
1. cmux notify --title "Todo #<id>" --body "<message>"
2. tmux display-message "Todo #<id>: <message>"
3. osascript -e 'display notification "<message>" with title "Todo #<id>"'

Messages:
- Success: "Done -- draft PR created"
- Blocked: "Blocked -- check session for details"

If you hit a blocker you cannot resolve after 2 attempts, stop and notify. Do not loop forever.
PROMPT
)"
```

4. **Launch in terminal window**:

   **cmux mode:**
   ```bash
   # cmux new-workspace outputs: "OK workspace:NN"
   CMUX_OUTPUT=$(cmux new-workspace --command "bash $SCRIPT_PATH")
   CMUX_WS_ID=$(echo "$CMUX_OUTPUT" | grep -o 'workspace:[0-9]*')
   if [[ -z "$CMUX_WS_ID" ]]; then
       echo "WARNING: Failed to parse workspace ID from cmux output: $CMUX_OUTPUT"
   else
       cmux rename-workspace --workspace "$CMUX_WS_ID" "$WINDOW_NAME"
   fi
   cmux notify --title "Todo #<id> started" --body "$WINDOW_NAME"
   ```

   **tmux mode:**
   ```bash
   TMUX_SESSION=$(tmux display-message -p '#{session_name}')
   tmux new-window -d -t "$TMUX_SESSION" -n "$WINDOW_NAME" bash "$SCRIPT_PATH"
   tmux display-message "Todo #<id> started: $WINDOW_NAME (Ctrl-b w to switch)"
   ```

5. **Update todo status** to `in_progress`, set `claimed_at` to current ISO 8601 timestamp, set `updated` to today.
6. **Regenerate `todo-list.md`**.
7. **Report to user:**
    - "Todo #X starting in [cmux workspace / tmux window]: `$WINDOW_NAME`"
    - "Branch: `$BRANCH_NAME`"
    - "Switch to watch: [cmux sidebar / Ctrl-b w]"
    - "Clean up when done: `graft rm $BRANCH_NAME`"

---

## Regenerate todo-list.md

This procedure is called by every write operation. Follow these steps exactly:

1. **Scan**: Find all `todo.md` files under `$TODOS/active/` recursively.
2. **Skip example**: Exclude any todo with `id: 0` (the example template at `000-example/`).
3. **Parse**: Read YAML frontmatter from each `todo.md`.
4. **Validate**: Run validation checks on each todo (see Validation section). Note any issues but continue.
5. **Read config**: Read `$TODOS/config.md` for `stale_threshold_hours` (default: 48 if config missing).
6. **Determine groups**: Group todos by their parent subdirectory under `active/`. If a todo sits directly under `active/` (no group subdirectory), group it as "Ungrouped".
7. **Sort**: Within each group, sort by priority (P0 first, then P1, P2, P3). Break ties by ID (lowest first). Sort groups alphabetically, with "Ungrouped" last.
8. **Build status annotations** for each todo:
   - If `due` is a date in the past AND `status` is not `done`: append `🔴 OVERDUE` to the status cell.
   - If `status` is `in_progress`, `blocked`, or `in_review` AND the `updated` date is more than `stale_threshold_hours` ago (convert hours to days: threshold / 24): append `⚠ STALE` to the status cell.
9. **Write** `$TODOS/todo-list.md` with this format:

```markdown
# Todo List

> Auto-generated from active todos. Do not edit directly.

## <Group Name> (<N> active)

| ID | Title | Priority | Status | Assignee | Due |
|----|-------|----------|--------|----------|-----|
| <NNN> | <title> | <priority> | <status> [annotations] | <assignee or —> | <due or —> |

---
*Last synced: YYYY-MM-DD HH:MM*
```

- Zero-pad the ID to 3 digits in the table.
- Use `—` (em dash) for empty assignee and due fields.
- Include a section for each group that has active todos.

## Validation

Run on every read and write. Report issues to the user but do NOT auto-fix.

### Required Fields

Every `todo.md` must have these frontmatter fields present: `id`, `title`, `status`, `priority`, `created`, `updated`.

### Value Validation

| Field | Rule |
|-------|------|
| `status` | Must be one of: `draft`, `pending`, `in_progress`, `blocked`, `in_review`, `done` |
| `priority` | Must be one of: `P0`, `P1`, `P2`, `P3` |
| `id` | Must be a non-negative integer. Must match the numeric prefix of its directory name. |
| `blocked_by` | Each entry should reference an existing todo ID if possible |
| `created`, `updated`, `due` | Must be valid `YYYY-MM-DD` format if present |

### Behavior on Invalid Todos

- **When listing or viewing**: Warn about the invalid todo but still show it with a validation error note.
- **When an agent tries to claim**: Skip invalid todos and report the issue.
- **Never auto-fix**: Report issues for humans to correct.

## PR Descriptions

Never reference user-level todos (`~/todos/`) in PR descriptions. User-level todos are personal tracking and not meaningful to PR reviewers. Only project-level todos (`.claude/todos/`) should be referenced in PRs.

## Relationship to Other Tools

- This todo system tracks **high-level work items** (like Jira tickets): "Fix login bug", "Add SSO support".
- During active implementation, use the **built-in TaskCreate/TaskUpdate tools** for granular session-scoped steps like "Update auth controller", "Write tests". Those are ephemeral.
- Plans for a todo go in `<todo>/docs/plan.md`.
- See `AGENTS.md` in the todos root for the full agent workflow protocol.
- See `README.md` in the todos root for human-facing documentation.
