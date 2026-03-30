#!/bin/bash
#
# sync.sh - Sync Claude settings via dotfiles git repo
#
# Copies files between ~/.claude (standalone) and ~/dotfiles/.claude (git-tracked).
# Git handles transport between machines. No symlinks, no rsync over SSH.
#
# Uses 3-way merge on pull: keeps a base snapshot of last sync state so local
# and remote changes can be auto-merged per file using git merge-file.
#
# Usage:
#   ./sync.sh push          - Copy ~/.claude → dotfiles, git commit & push
#   ./sync.sh pull          - Git pull dotfiles, 3-way merge → ~/.claude, fix paths
#   ./sync.sh fix           - Fix paths for current machine
#   ./sync.sh push --force  - Push without checking for remote changes
#   ./sync.sh pull --force  - Pull, overwrite local (skip merge), fix paths
#

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
# Support both flat (dotfiles/.claude) and stow (dotfiles/claude/.claude) layouts
if [[ -d "$DOTFILES_DIR/claude/.claude" ]]; then
    DOTFILES_CLAUDE="$DOTFILES_DIR/claude/.claude"
elif [[ -d "$DOTFILES_DIR/.claude" ]]; then
    DOTFILES_CLAUDE="$DOTFILES_DIR/.claude"
else
    DOTFILES_CLAUDE="$DOTFILES_DIR/claude/.claude"
fi
SYNC_BASE="$CLAUDE_DIR/.sync-base"
BACKUP_DIR="$CLAUDE_DIR/.sync-backups"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORCE=false
if [[ "${2:-}" == "--force" ]]; then
    FORCE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_merge() { echo -e "${CYAN}[MERGE]${NC} $1"; }

detect_machine() {
    if [[ "$HOME" == /home/* ]]; then
        echo "linux"
    else
        echo "mac"
    fi
}

# Files/dirs to exclude from sync (machine-specific)
EXCLUDES=(
    '--exclude=.credentials.json'
    '--exclude=cache/'
    '--exclude=debug/'
    '--exclude=session-env/'
    '--exclude=paste-cache/'
    '--exclude=file-history/'
    '--exclude=projects/'
    '--exclude=tasks/'
    '--exclude=todos/'
    '--exclude=history.jsonl'
    '--exclude=statsig/'
    '--exclude=stats-cache.json'
    '--exclude=install-counts-cache.json'
    '--exclude=shell-snapshots/'
    '--exclude=ide/'
    '--exclude=settings.local.json'
    '--exclude=._*'
    '--exclude=.DS_Store'
    '--exclude=*.pyc'
    '--exclude=__pycache__/'
    '--exclude=.venv/'
    '--exclude=node_modules/'
    '--exclude=*.lock'
    '--exclude=*.bak'
    '--exclude=*.sync-backup'
    '--exclude=teams/'
    '--exclude=marketplaces/'
    '--exclude=.gitignore'
    '--exclude=sync-claude.log'
    '--exclude=.sync-backups/'
    '--exclude=.sync-base/'
)

usage() {
    echo "Usage: $0 {push|pull|fix} [--force]"
    echo ""
    echo "Commands:"
    echo "  push  - Copy ~/.claude → ~/dotfiles/.claude, then git commit & push"
    echo "  pull  - Git pull dotfiles, 3-way merge into ~/.claude, fix paths"
    echo "  fix   - Fix paths and permissions for current machine"
    echo ""
    echo "Options:"
    echo "  --force  - Skip merge (push: ignore remote, pull: overwrite local)"
    echo ""
    echo "Environment variables:"
    echo "  CLAUDE_DIR    - Claude config dir (default: ~/.claude)"
    echo "  DOTFILES_DIR  - Dotfiles repo dir (default: ~/dotfiles)"
    exit 1
}

# Check if dotfiles remote has changes we haven't pulled
check_remote_ahead() {
    cd "$DOTFILES_DIR"
    git fetch --quiet 2>/dev/null || true

    local local_head remote_head
    local_head=$(git rev-parse HEAD 2>/dev/null)
    remote_head=$(git rev-parse @{u} 2>/dev/null) || return 0

    if [[ "$local_head" == "$remote_head" ]]; then
        return 0  # up to date
    fi

    if git merge-base --is-ancestor "$local_head" "$remote_head" 2>/dev/null; then
        return 1  # remote is ahead
    fi

    local merge_base
    merge_base=$(git merge-base "$local_head" "$remote_head" 2>/dev/null)
    if [[ "$merge_base" != "$local_head" && "$merge_base" != "$remote_head" ]]; then
        return 2  # diverged
    fi

    return 0
}

# List syncable files in a directory (relative paths)
list_syncable_files() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        return
    fi
    # Use rsync dry-run to respect our exclude list, then extract file paths
    rsync -avn "${EXCLUDES[@]}" "$dir/" "/dev/null" 2>/dev/null \
        | grep -v '/$' \
        | grep -v '^sending' \
        | grep -v '^total size' \
        | grep -v '^sent ' \
        | grep -v '^\.\/$' \
        | grep -v '^\.$' \
        | sed 's|^\./||' \
        | sort || true
}

# Attempt JSON merge using jq (merge keys from both, remote wins on conflict)
try_json_merge() {
    local base="$1" local_file="$2" remote="$3" output="$4"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    # Validate all three are valid JSON
    jq empty "$base" 2>/dev/null || return 1
    jq empty "$local_file" 2>/dev/null || return 1
    jq empty "$remote" 2>/dev/null || return 1

    # 3-way JSON merge: start with base, apply local changes, apply remote changes
    # Remote wins on key conflicts (most recent push wins)
    local base_json local_json remote_json
    base_json=$(cat "$base")
    local_json=$(cat "$local_file")
    remote_json=$(cat "$remote")

    # Merge: base * local_changes * remote_changes
    # Using jq: combine base with local additions, then overlay remote
    jq -n --argjson base "$base_json" --argjson local "$local_json" --argjson remote "$remote_json" \
        '$base * $local * $remote' > "$output" 2>/dev/null
}

# 3-way merge a single file. Returns:
#   0 = clean merge (or no merge needed)
#   1 = conflict (markers left in file)
#   2 = error
merge_one_file() {
    local rel_path="$1"
    local local_file="$CLAUDE_DIR/$rel_path"
    local remote_file="$DOTFILES_CLAUDE/$rel_path"
    local base_file="$SYNC_BASE/$rel_path"

    local has_local=false has_remote=false has_base=false
    [[ -f "$local_file" ]] && has_local=true
    [[ -f "$remote_file" ]] && has_remote=true
    [[ -f "$base_file" ]] && has_base=true

    # Remote only (new from other machine) → copy in
    if [[ "$has_remote" == true && "$has_local" == false ]]; then
        log_merge "  + $rel_path (new from remote)"
        mkdir -p "$(dirname "$local_file")"
        cp "$remote_file" "$local_file"
        return 0
    fi

    # Local only (not in dotfiles) → keep as-is
    if [[ "$has_local" == true && "$has_remote" == false ]]; then
        log_merge "  ~ $rel_path (local only, keeping)"
        return 0
    fi

    # Both exist - check if identical
    if [[ "$has_local" == true && "$has_remote" == true ]]; then
        if cmp -s "$local_file" "$remote_file"; then
            return 0  # identical, nothing to do
        fi
    fi

    # Both exist and differ - need merge

    # No base (first sync with this file) → take remote, backup local
    if [[ "$has_base" == false ]]; then
        log_merge "  ! $rel_path (no base, taking remote, backed up local)"
        mkdir -p "$(dirname "$BACKUP_DIR/no-base/$rel_path")"
        cp "$local_file" "$BACKUP_DIR/no-base/$rel_path"
        cp "$remote_file" "$local_file"
        return 0
    fi

    # Has base - determine what changed
    local local_changed=false remote_changed=false
    if ! cmp -s "$base_file" "$local_file"; then
        local_changed=true
    fi
    if ! cmp -s "$base_file" "$remote_file"; then
        remote_changed=true
    fi

    # Only remote changed → take remote
    if [[ "$local_changed" == false && "$remote_changed" == true ]]; then
        log_merge "  < $rel_path (updated from remote)"
        cp "$remote_file" "$local_file"
        return 0
    fi

    # Only local changed → keep local
    if [[ "$local_changed" == true && "$remote_changed" == false ]]; then
        log_merge "  ~ $rel_path (local changes preserved)"
        return 0
    fi

    # Both changed - attempt auto-merge
    log_merge "  * $rel_path (both sides changed, merging...)"

    # For JSON files, try jq merge first
    if [[ "$rel_path" == *.json ]]; then
        local tmp_merged
        tmp_merged=$(mktemp)
        if try_json_merge "$base_file" "$local_file" "$remote_file" "$tmp_merged"; then
            cp "$tmp_merged" "$local_file"
            rm -f "$tmp_merged"
            log_merge "    → JSON merge successful"
            return 0
        fi
        rm -f "$tmp_merged"
    fi

    # Fall back to git merge-file (3-way text merge)
    local tmp_work
    tmp_work=$(mktemp)
    cp "$local_file" "$tmp_work"

    # git merge-file modifies the first file in place
    # Returns 0 on clean merge, >0 on conflicts
    if git merge-file -L "local" -L "base" -L "remote" \
        "$tmp_work" "$base_file" "$remote_file" 2>/dev/null; then
        cp "$tmp_work" "$local_file"
        rm -f "$tmp_work"
        log_merge "    → auto-merged cleanly"
        return 0
    else
        # Has conflict markers - still write it but warn
        cp "$tmp_work" "$local_file"
        rm -f "$tmp_work"
        log_warn "    → CONFLICT in $rel_path (markers left in file)"
        return 1
    fi
}

# Update sync base after successful sync
update_sync_base() {
    log_step "Updating sync base snapshot..."
    mkdir -p "$SYNC_BASE"
    rsync -a --delete "${EXCLUDES[@]}" \
        "$CLAUDE_DIR/" "$SYNC_BASE/"
}

sync_push() {
    local machine=$(detect_machine)

    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        log_error "Dotfiles repo not found at $DOTFILES_DIR"
        exit 1
    fi

    # Check if remote has changes we should pull first
    if [[ "$FORCE" != true ]]; then
        log_step "Checking for remote changes..."
        check_remote_ahead
        local rc=$?
        if [[ $rc -eq 1 ]]; then
            log_warn "Remote has new changes. Pulling before push..."
            cd "$DOTFILES_DIR"
            git pull
        elif [[ $rc -eq 2 ]]; then
            log_error "Local and remote have diverged. Resolve manually:"
            log_error "  cd $DOTFILES_DIR && git pull --rebase"
            log_error "Or use --force to push anyway"
            exit 1
        fi
    fi

    log_step "Copying $CLAUDE_DIR → $DOTFILES_CLAUDE"
    mkdir -p "$DOTFILES_CLAUDE"

    # Merge into dotfiles (no --delete, preserves files from other machines)
    rsync -av "${EXCLUDES[@]}" \
        "$CLAUDE_DIR/" "$DOTFILES_CLAUDE/"

    # Strip machine-specific env vars from settings.json before committing
    local settings_in_dotfiles="$DOTFILES_CLAUDE/settings.json"
    if [[ -f "$settings_in_dotfiles" ]] && command -v jq &>/dev/null; then
        local tmp_settings
        tmp_settings=$(mktemp)
        jq 'del(.env)' "$settings_in_dotfiles" > "$tmp_settings" && mv "$tmp_settings" "$settings_in_dotfiles"
        log_info "Stripped 'env' key from settings.json"
    fi

    log_step "Committing changes in dotfiles repo..."
    cd "$DOTFILES_DIR"

    local git_rel="${DOTFILES_CLAUDE#$DOTFILES_DIR/}"
    git add "$git_rel/"
    if git diff --cached --quiet "$git_rel/"; then
        log_info "No changes to commit"
    else
        git commit -m "Sync Claude settings from $machine"
        log_step "Pushing to remote..."
        git push
        log_info "Pushed to remote"
    fi

    # Update base to reflect current state
    update_sync_base

    log_info "Push complete!"
}

sync_pull() {
    local machine=$(detect_machine)

    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        log_error "Dotfiles repo not found at $DOTFILES_DIR"
        exit 1
    fi

    log_step "Pulling latest dotfiles..."
    cd "$DOTFILES_DIR"
    git pull

    if [[ ! -d "$DOTFILES_CLAUDE" ]]; then
        log_error "No .claude directory in dotfiles repo"
        exit 1
    fi

    # Force mode: skip merge, just overwrite
    if [[ "$FORCE" == true ]]; then
        log_step "Force mode: overwriting $CLAUDE_DIR from dotfiles"
        rsync -av "${EXCLUDES[@]}" \
            "$DOTFILES_CLAUDE/" "$CLAUDE_DIR/"
        update_sync_base
        "$SCRIPT_DIR/fix-paths.sh"
        log_info "Pull (force) complete!"
        return
    fi

    # No base yet → first sync, just copy and establish base
    if [[ ! -d "$SYNC_BASE" ]]; then
        log_warn "No sync base found (first sync). Copying dotfiles → local."
        log_warn "Local files backed up to $BACKUP_DIR/initial/"

        # Backup everything local first
        mkdir -p "$BACKUP_DIR/initial"
        rsync -a "${EXCLUDES[@]}" "$CLAUDE_DIR/" "$BACKUP_DIR/initial/" 2>/dev/null || true

        rsync -av "${EXCLUDES[@]}" \
            "$DOTFILES_CLAUDE/" "$CLAUDE_DIR/"
        update_sync_base
        "$SCRIPT_DIR/fix-paths.sh"
        log_info "Pull (initial) complete! Run 'push' to establish sync base with your changes."
        return
    fi

    # 3-way merge
    log_step "Merging dotfiles into $CLAUDE_DIR (3-way merge)..."

    # Collect all unique file paths from local, remote, and base
    local all_files
    all_files=$(
        {
            list_syncable_files "$CLAUDE_DIR"
            list_syncable_files "$DOTFILES_CLAUDE"
        } | sort -u
    )

    local conflicts=0
    local merged=0
    local unchanged=0
    local conflict_files=()

    # Ensure backup dir exists for no-base cases
    mkdir -p "$BACKUP_DIR"

    while IFS= read -r rel_path; do
        [[ -z "$rel_path" ]] && continue

        merge_one_file "$rel_path"
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            ((merged++))
        elif [[ $rc -eq 1 ]]; then
            ((conflicts++))
            conflict_files+=("$rel_path")
        fi
    done <<< "$all_files"

    # Update base to reflect merged state
    update_sync_base

    log_step "Fixing paths for $machine..."
    "$SCRIPT_DIR/fix-paths.sh"

    # Summary
    echo ""
    log_info "Pull complete! Merged $merged files."
    if [[ $conflicts -gt 0 ]]; then
        log_warn "$conflicts file(s) have conflicts (markers in file):"
        for f in "${conflict_files[@]}"; do
            echo "  $CLAUDE_DIR/$f"
        done
        log_warn "Edit these files to resolve, then run 'push' to sync."
    fi
}

run_fix() {
    "$SCRIPT_DIR/fix-paths.sh" "${2:-}"
}

# Main
case "${1:-}" in
    push)
        sync_push
        ;;
    pull)
        sync_pull
        ;;
    fix)
        run_fix "$@"
        ;;
    *)
        usage
        ;;
esac
