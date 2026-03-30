---
description: "Cancel the active autopilot session"
user-invocable: true
argument-hint: "[session-id]"
---

# Cancel Autopilot Session

Gracefully cancel an active autopilot session.

## Steps

1. **Determine the session ID**:
   - If a session ID is provided as an argument (`$ARGUMENTS`), use that.
   - Otherwise, read `.claude/autopilot.local.md` in the current working directory to find the active session ID for this project.
   - If neither source yields a session ID, tell the user no active session was found and stop.

2. **Read the session state**: Load `~/.claude/autopilot/sessions/<session-id>/state.json`. If it does not exist, tell the user the session was not found.

3. **Update state.json**: Set the `phase` field to `CANCELLED`. Preserve all other fields.

4. **Update active-sessions.json**: In `~/.claude/autopilot/active-sessions.json`, update the session's status to `CANCELLED` or remove it from the active list.

5. **Remove the local marker**: Delete `.claude/autopilot.local.md` from the current working directory if it exists.

6. **Confirm to user**: Tell the user the session has been cancelled, showing the session ID and feature name.

7. **Note**: Any in-flight agents (e.g., a build or verify step currently running) will finish their current task, but the stop hook will not re-dispatch further phases once it sees the `CANCELLED` state.
