# Notification Cascade

Shared notification logic for pr-patrol skills. Try each method in order, use the first that works.

## Cascade

1. `cmux notify --title "<title>" --body "<message>"` — if `$CMUX_WORKSPACE_ID` is set and `cmux` is in PATH
2. `tmux display-message "<title>: <message>"` — if `$TMUX` is set
3. `osascript -e 'display notification "<message>" with title "<title>"'` — macOS fallback
4. Console output only — always happens regardless

## When to notify

- **babysit:** Only for new `needs_attention` items. Skip IDs already in `notified_comment_ids`. Silent on clean runs. Title: `"Babysit"`.
- **post-merge-sweeper:** Only when new missed comments are found. Silent on clean sweeps. Title: `"Sweeper"`.
