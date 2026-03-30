---
name: sync-claude
description: Sync Claude Code settings between machines via dotfiles git repo. Copies files (no symlinks) between ~/.claude and ~/dotfiles/.claude.
context: fork
version: 2.0.1
author: bostondv
tags: [sync, settings, dotfiles, plugins]
user-invocable: true
---

# Sync Claude Settings

Sync Claude Code settings between machines using your dotfiles git repo.

`~/.claude` stays standalone. Settings are **copied** (not symlinked) to/from `~/dotfiles/.claude` which is git-tracked. Git handles transport between machines.

## What Gets Synced

- `settings.json` - Claude Code preferences
- `CLAUDE.md` - User preferences and rules
- `skills/` - User-created skills
- `commands/` - Custom commands
- `statusline.sh` - Status line script
- `docs/` - Personal documentation

## How It Works

```
~/.claude  ←── copy ──→  ~/dotfiles/claude/.claude  ←── git ──→  remote
(standalone)              (git-tracked)
```

Auto-detects dotfiles layout: `dotfiles/claude/.claude` (stow) or `dotfiles/.claude` (flat).

- **push**: Copy `~/.claude` → `~/dotfiles/.claude`, git commit & push
- **pull**: Git pull dotfiles, copy `~/dotfiles/.claude` → `~/.claude`, fix paths
- No symlinks. No rsync over SSH. Git is the transport.

## Usage

### Push (export settings to git)

```bash
~/.claude/skills/sync-claude/scripts/sync.sh push
```

### Pull (import settings from git)

```bash
~/.claude/skills/sync-claude/scripts/sync.sh pull
```

### Fix paths only

```bash
~/.claude/skills/sync-claude/scripts/sync.sh fix
```

## Configuration

```bash
# Override defaults if needed
export CLAUDE_DIR="$HOME/.claude"       # default
export DOTFILES_DIR="$HOME/dotfiles"    # default
```

## Post-Sync Fixes Applied

The fix script handles these common issues:

### 1. Path Translation
```
/Users/bostondv/.claude → /home/bento/.claude  (on Linux)
/home/bento/.claude → /Users/bostondv/.claude  (on Mac)
```

### 2. macOS Metadata Removal
```bash
find ~/.claude -name "._*" -delete
find ~/.claude -name ".DS_Store" -delete
```

### 3. Git Lock Cleanup
```bash
find ~/.claude -name "*.lock" -path "*/.git/*" -delete
```

### 4. Permission Fixes (Linux only)
```bash
chmod -R u+rwX ~/.claude/
find ~/.claude -name "*.sh" -exec chmod +x {} \;
```

## Files Never Synced

These are machine-specific and excluded from copy:

- `.credentials.json` - Auth tokens
- `settings.local.json` - Machine-local settings
- `cache/`, `debug/`, `session-env/` - Runtime data
- `paste-cache/`, `file-history/` - Local caches
- `projects/`, `tasks/`, `todos/` - Project-specific state
- `history.jsonl` - Command history
- `statsig/`, `stats-cache.json` - Feature flags/stats
- `shell-snapshots/`, `ide/` - Session state
- `marketplaces/` - Managed by plugin system (separate git repos)

## Troubleshooting

### Plugin Not Loading
```bash
# Verify paths are correct for this machine
grep -r "/Users/" ~/.claude/*.json
# If found, run fix
~/.claude/skills/sync-claude/scripts/sync.sh fix
```

### Permissions Issues
```bash
chmod -R u+rwX ~/.claude/
```

### Dotfiles Repo Not Found
```bash
# Ensure DOTFILES_DIR points to your dotfiles repo
ls ~/dotfiles/.git
# Or override:
export DOTFILES_DIR=/path/to/your/dotfiles
```
