---
description: "Show current autopilot session status and progress"
user-invocable: true
---

# Autopilot Status Dashboard

Display the current status of all active autopilot sessions.

## Steps

1. Read `~/.claude/autopilot/active-sessions.json`. If the file does not exist or is empty, tell the user there are no active sessions and stop.

2. For each session listed in `active-sessions.json`, read its `state.json` from the session directory (`~/.claude/autopilot/sessions/<session-id>/state.json`).

3. Display a formatted dashboard for each session with the following fields:

   - **Session ID**: The unique session identifier
   - **Feature**: The feature description / name
   - **Phase**: Current phase with a visual indicator:
     - `SPEC` — Interviewing
     - `EXPLORE` — Mapping codebase
     - `BUILD` — Implementing
     - `VERIFY` — Running checks
     - `FIX` — Fixing issues
     - `COMMIT` — Committing & pushing
     - `REVIEW` — Self-reviewing PR
     - `DONE` — Complete
     - `ERROR` — Failed
     - `CANCELLED` — Cancelled
   - **Iteration**: Current iteration count / max iterations
   - **Fix Attempts**: Current fix attempts / max fix attempts
   - **Review Rounds**: Current review round / max review rounds
   - **Branch**: The git branch name
   - **PR URL**: The pull request URL if one has been created, otherwise "not yet created"
   - **Elapsed**: Time elapsed since session creation (human-readable, e.g. "2h 15m")

4. If there are multiple sessions, display them in order of most recently created first.

5. If any session's `state.json` cannot be read, note it as "status unavailable" for that session.
