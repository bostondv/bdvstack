---
name: cmux
description: Use when user asks to manipulate terminal panes, splits, workspaces, tabs, surfaces, or browser panels inside cmux. Also use when sending commands to other panes, reading screen content, showing diffs/logs in splits, managing notifications, or updating sidebar status/progress. Triggers on "split pane", "new workspace", "open in another pane", "send notification", "open browser", "read screen".
---

# cmux CLI

Control the cmux terminal multiplexer from Claude Code.

## Detection

Verify cmux is available before running commands:

```bash
if [ -z "$CMUX_WORKSPACE_ID" ]; then
  echo "Not running inside cmux"
  exit 1
fi
```

Environment variables auto-set in cmux terminals: `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_TAB_ID`.

## Hierarchy

```
Window > Workspace > Pane > Surface > Panel
```

- **Window**: macOS window
- **Workspace**: sidebar entry (called "tabs" in UI). Has one or more panes.
- **Pane**: split region. Has one or more surfaces (tabbed).
- **Surface**: individual tab within a pane. Each has its own `CMUX_SURFACE_ID`.
- **Panel**: content inside surface (terminal or browser). Internal concept — interact via surfaces.

IDs use ref format: `workspace:1`, `pane:2`, `surface:3`. UUIDs also accepted.

## Common Recipes

### Open diff/logs/output in a split

```bash
# Split right and capture the new surface ref (output: "OK surface:N workspace:N")
NEW=$(cmux new-split right | awk '{print $2}')
# Send a command to the new surface
cmux send --surface "$NEW" "git diff"
cmux send-key --surface "$NEW" enter
```

### Run a command in a new split

```bash
NEW=$(cmux new-split down | awk '{print $2}')
cmux send --surface "$NEW" "npm test"
cmux send-key --surface "$NEW" enter
```

### Open a browser panel

```bash
cmux browser open "https://example.com"
# Or in a specific direction
cmux new-pane --type browser --direction right --url "https://example.com"
```

### Read another pane's screen content

```bash
cmux read-screen --surface "$SURFACE_ID"
# With scrollback history
cmux read-screen --surface "$SURFACE_ID" --scrollback --lines 200
```

### Create a new workspace

```bash
cmux new-workspace
# With a command already running
cmux new-workspace --command "htop"
```

### Switch/rename workspaces

```bash
cmux select-workspace --workspace workspace:2
cmux rename-workspace "my-feature"
cmux list-workspaces
```

### Send a notification

```bash
cmux notify --title "Build Complete" --body "All tests passed"
cmux notify --title "Error" --subtitle "CI" --body "Pipeline failed"
```

### Update sidebar status/progress

```bash
cmux set-status "build" "passing" --icon "checkmark" --color "#00ff00"
cmux set-progress 0.75 --label "Running tests..."
cmux clear-progress
cmux log --level success --source "test" "All 42 tests passed"
```

## Quick Reference

### Workspace Commands

| Command | Purpose |
|---------|---------|
| `list-workspaces` | List all workspaces |
| `new-workspace [--command <cmd>]` | Create workspace |
| `select-workspace --workspace <id>` | Switch to workspace |
| `current-workspace` | Get active workspace |
| `close-workspace --workspace <id>` | Close workspace |
| `rename-workspace [--workspace <id>] <title>` | Rename workspace |

### Pane & Surface Commands

| Command | Purpose |
|---------|---------|
| `new-split <left\|right\|up\|down>` | Split current pane |
| `new-pane [--type <terminal\|browser>] [--direction <dir>]` | New pane |
| `new-surface [--type <terminal\|browser>] [--pane <id>]` | New tab in pane |
| `list-panes [--workspace <id>]` | List panes |
| `list-pane-surfaces [--pane <id>]` | List surfaces in pane |
| `focus-surface --surface <id>` | Focus a surface |
| `focus-pane --pane <id>` | Focus a pane |
| `close-surface [--surface <id>]` | Close surface |
| `resize-pane --pane <id> (-L\|-R\|-U\|-D) [--amount <n>]` | Resize pane |
| `swap-pane --pane <id> --target-pane <id>` | Swap two panes |
| `drag-surface-to-split --surface <id> <dir>` | Move surface to split |

### Input Commands

| Command | Purpose |
|---------|---------|
| `send [--surface <id>] <text>` | Send text to terminal |
| `send-key [--surface <id>] <key>` | Send keypress (enter, tab, escape, up, down, etc.) |
| `read-screen [--surface <id>] [--scrollback] [--lines <n>]` | Read terminal content |

### Browser Commands

| Command | Purpose |
|---------|---------|
| `browser open [url]` | Open browser split |
| `browser goto <url>` | Navigate to URL |
| `browser snapshot [--interactive] [--compact]` | Get page snapshot |
| `browser eval <script>` | Run JavaScript |
| `browser click <selector>` | Click element |
| `browser type <selector> <text>` | Type into element |
| `browser fill <selector> <text>` | Fill input field |
| `browser get <url\|title\|text\|html>` | Get page info |
| `browser back\|forward\|reload` | Navigation |
| `browser tab <new\|list\|switch\|close>` | Manage browser tabs |

### Notification Commands

| Command | Purpose |
|---------|---------|
| `notify --title <t> [--subtitle <s>] [--body <b>]` | Send notification |
| `list-notifications` | List notifications |
| `clear-notifications` | Clear all notifications |

### Sidebar Metadata

| Command | Purpose |
|---------|---------|
| `set-status <key> <value> [--icon <name>] [--color <hex>]` | Status pill |
| `clear-status <key>` | Remove status |
| `set-progress <0.0-1.0> [--label <text>]` | Progress bar |
| `clear-progress` | Remove progress bar |
| `log [--level <info\|progress\|success\|warning\|error>] [--source <name>] <msg>` | Log entry |
| `clear-log` | Clear all logs |
| `sidebar-state` | Dump all sidebar metadata |

### Window Commands

| Command | Purpose |
|---------|---------|
| `list-windows` | List all windows |
| `new-window` | Create window |
| `focus-window --window <id>` | Focus window |
| `move-workspace-to-window --workspace <id> --window <id>` | Move workspace |

### Utility

| Command | Purpose |
|---------|---------|
| `identify` | Show current context (window/workspace/pane/surface IDs) |
| `ping` | Check cmux is responsive |
| `capabilities` | List available socket methods |

## Global Flags

- `--json` — JSON output (useful for parsing IDs from commands)
- `--workspace <id>` — target specific workspace
- `--surface <id>` — target specific surface
- `--window <id>` — target specific window
- `--id-format refs|uuids|both` — control ID format in output

## Common Patterns

### Get current context IDs

```bash
cmux identify --json
```

### Chain: split + send + read result

```bash
NEW=$(cmux new-split right | awk '{print $2}')
cmux send --surface "$NEW" "git log --oneline -20"
cmux send-key --surface "$NEW" enter
sleep 1
cmux read-screen --surface "$NEW"
```

### Show progress during long operations

```bash
cmux set-progress 0.0 --label "Starting build..."
# ... after each step ...
cmux set-progress 0.5 --label "Running tests..."
# ... when done ...
cmux clear-progress
cmux log --level success "Build complete"
cmux notify --title "Done" --body "Build finished successfully"
```

## Common Mistakes

- **Forgetting `send-key enter`** after `send` — `send` types text but doesn't press enter
- **Not using `--json`** when you need to capture IDs from `new-split` or `new-pane`
- **Using panel commands** when you mean surface — interact with surfaces, not panels
- **Assuming surface IDs** — always capture from command output or use `identify`
