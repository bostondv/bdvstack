#!/bin/bash
#
# fix-paths.sh - Fix Claude settings after syncing from Mac to Linux
#
# Usage: ./fix-paths.sh [--dry-run]
#

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
DRY_RUN="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect environment
if [[ "$HOME" == /home/* ]]; then
    LOCAL_PATH_PREFIX="/Users/bostondv"
    REMOTE_PATH_PREFIX="$HOME"
    MACHINE_TYPE="linux"
else
    LOCAL_PATH_PREFIX="/home/bento"
    REMOTE_PATH_PREFIX="$HOME"
    MACHINE_TYPE="mac"
fi

log_info "Running on $MACHINE_TYPE"
log_info "Claude dir: $CLAUDE_DIR"
log_info "Fixing paths: $LOCAL_PATH_PREFIX → $REMOTE_PATH_PREFIX"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log_warn "DRY RUN - no changes will be made"
fi

# 1. Remove macOS metadata files
log_info "Removing macOS metadata files..."
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    find "$CLAUDE_DIR" -name "._*" -type f -delete 2>/dev/null || true
    find "$CLAUDE_DIR" -name ".DS_Store" -type f -delete 2>/dev/null || true
    log_info "  Removed ._* and .DS_Store files"
else
    count=$(find "$CLAUDE_DIR" -name "._*" -type f 2>/dev/null | wc -l)
    log_info "  Would remove $count ._* files"
fi

# 2. Remove git lock files
log_info "Removing stale git lock files..."
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    find "$CLAUDE_DIR" -name "*.lock" -path "*/.git/*" -delete 2>/dev/null || true
    log_info "  Removed git lock files"
else
    count=$(find "$CLAUDE_DIR" -name "*.lock" -path "*/.git/*" 2>/dev/null | wc -l)
    log_info "  Would remove $count git lock files"
fi

# 3. Remove temp git directories
log_info "Removing temp git directories..."
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    rm -rf "$CLAUDE_DIR/plugins/cache/temp_git_"* 2>/dev/null || true
    rm -rf "$CLAUDE_DIR/cache/temp_git_"* 2>/dev/null || true
    log_info "  Removed temp_git_* directories"
else
    log_info "  Would remove temp_git_* directories"
fi

# 4. Fix paths in JSON files
fix_json_paths() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if grep -q "$LOCAL_PATH_PREFIX" "$file" 2>/dev/null; then
            log_info "  Fixing paths in $(basename "$file")"
            if [[ "$DRY_RUN" != "--dry-run" ]]; then
                if [[ "$MACHINE_TYPE" == "mac" ]]; then
                    sed -i '' "s|$LOCAL_PATH_PREFIX|$REMOTE_PATH_PREFIX|g" "$file"
                else
                    sed -i "s|$LOCAL_PATH_PREFIX|$REMOTE_PATH_PREFIX|g" "$file"
                fi
            fi
        else
            log_info "  $(basename "$file") - paths OK"
        fi
    fi
}

log_info "Fixing paths in config files..."
fix_json_paths "$CLAUDE_DIR/known_marketplaces.json"
fix_json_paths "$CLAUDE_DIR/installed_plugins.json"
fix_json_paths "$CLAUDE_DIR/settings.json"

# 5. Fix permissions (Linux only)
if [[ "$MACHINE_TYPE" == "linux" ]]; then
    log_info "Fixing permissions..."
    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        chmod -R u+rwX "$CLAUDE_DIR" 2>/dev/null || true
        # Make scripts executable
        find "$CLAUDE_DIR" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
        log_info "  Fixed permissions"
    fi
fi

# 6. Clean up duplicate directories
log_info "Checking for duplicate/misnamed directories..."
if [[ -d "$CLAUDE_DIR/plugins/marketplaces/anthropics-claude-plugins-official" ]]; then
    log_warn "  Found misnamed anthropics-claude-plugins-official"
    if [[ "$DRY_RUN" != "--dry-run" ]]; then
        rm -rf "$CLAUDE_DIR/plugins/marketplaces/anthropics-claude-plugins-official"
        log_info "  Removed misnamed directory"
    fi
fi

# 7. Verify git repos are healthy
log_info "Verifying marketplace git repos..."
for dir in "$CLAUDE_DIR/plugins/marketplaces"/*/; do
    if [[ -d "$dir/.git" ]]; then
        name=$(basename "$dir")
        if cd "$dir" && git status &>/dev/null; then
            log_info "  $name - OK"
        else
            log_warn "  $name - git repo issue"
            if [[ "$DRY_RUN" != "--dry-run" ]]; then
                log_info "    Removing corrupted repo (will re-clone)"
                rm -rf "$dir"
            fi
        fi
    fi
done

log_info "Done! Run '/plugin' to verify plugins load correctly."
