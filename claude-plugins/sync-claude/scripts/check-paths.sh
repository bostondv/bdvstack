#!/bin/bash
#
# check-paths.sh - Quick check if paths need fixing (fast, silent)
# Returns 0 if fix needed, 1 if paths are OK
#

CLAUDE_DIR="${HOME}/.claude"

# Quick check - look for Mac paths in key files
if grep -q "/Users/bostondv" "$CLAUDE_DIR/known_marketplaces.json" 2>/dev/null; then
    exit 0
fi

if grep -q "/Users/bostondv" "$CLAUDE_DIR/installed_plugins.json" 2>/dev/null; then
    exit 0
fi

# Check for Mac metadata files
if find "$CLAUDE_DIR" -maxdepth 2 -name "._*" -type f 2>/dev/null | head -1 | grep -q .; then
    exit 0
fi

# Paths look OK
exit 1
