---
name: dance-spec
description: Use when conducting the initial feature interview during autopilot SPEC phase — structures discovery through the DANCE framework to produce a tight spec
---

# DANCE Interview Framework

Structure the feature discovery process through 5 phases to produce a tight, actionable spec.

## Phases

### D - Discover
**Purpose:** Understand the feature at a high level.

Ask questions like:
- "Elevator pitch — what is this?"
- "Who's it for?"
- "Where does it live in the app?"

### A - Analyze
**Purpose:** Probe deeper into technical details.

Ask questions like:
- "What's the data model?"
- "Existing patterns to reuse?"
- "Edge cases?"
- "Dependencies?"

**Verification loop (ALWAYS ASK — exactly once per session):** Add this question regardless of feature type:
- "Should I run an end-to-end verification loop after the standard quality gates pass? This phase actually exercises the feature (curls API endpoints, drives the browser, runs the CLI binary, etc.) to prove it works at runtime — not just that it compiles and tests pass. Quality gates (tests, lint, typecheck) always run regardless. [Yes / No]"

Record the answer in state.json as `"verification_loop": true|false`. If yes and the feature is UI-driven, run the **browser-check preflight** (next subsection) before continuing.

#### Browser-check preflight (UI features with verification_loop=true)

VALIDATE drives the browser via `agent-browser` and reads from `.browser-check/config.yaml` + `.browser-flows/flows.yml` (the **browser-check** skill format). When the user opts into the verification loop on a UI feature:

1. **Check `agent-browser` is installed:** `which agent-browser`. If not found, tell the user one of: `gohan install agent-browser` or `npm install -g agent-browser && agent-browser install`. Continue regardless — VALIDATE will record SKIPPED for browser scenarios if it can't run.

2. **Ask for the base URL** if not already known: e.g. `http://localhost:3000`. Save as `validate_base_url` in state.json.

3. **Check `.browser-check/config.yaml` exists.** If missing, ask the user:
   > "No `.browser-check/config.yaml` found. I can scaffold it now with host `<base_url>` so VALIDATE can drive the browser. Ok? [Yes / No]"

   If Yes, scaffold both files (idempotent — only create what's missing):
   ```bash
   mkdir -p .browser-check/runs .browser-flows
   grep -q "^\.browser-check" .gitignore 2>/dev/null || echo ".browser-check/" >> .gitignore

   # Only write config if missing
   [ -f .browser-check/config.yaml ] || cat > .browser-check/config.yaml <<EOF
   host: "<base_url>"
   device: null
   screenshots: true
   annotateScreenshots: false
   timeout: 30000
   parallel: false
   EOF

   # Only write flows.yml if missing
   [ -f .browser-flows/flows.yml ] || cat > .browser-flows/flows.yml <<'EOF'
   # Named browser flows. Each entry: path (or script) + criteria.
   # Workers may append entries here for new UI surfaces during BUILD.
   #
   # smoke:
   #   path: /
   #   criteria: page renders without console errors
   EOF
   ```

   If No, continue without scaffolding — VALIDATE will fall back to direct navigation against `validate_base_url` and skip flow-based scenarios.

4. **Record outcome in state.json:**
   - `"browser_check_configured": true|false` — whether `.browser-check/config.yaml` exists at this point
   - `"browser_check_scaffolded": true|false` — whether autopilot wrote it during this session (so workers know they may append to flows.yml)

### N - Narrow
**Purpose:** Lock scope. This is the critical phase.

Present what's IN and what's OUT. Push back on scope creep. When something sounds like it could balloon, say "that sounds like a separate feature" and exclude it.

### C - Code
**Purpose:** Write the spec.

Produce `spec.md` using the output format below.

### E - Evaluate
**Purpose:** Get sign-off.

Ask: "Read it. Anything missing? Shall I proceed?"

## Rules

- **Always use the `AskUserQuestion` tool to ask questions** — never output questions as plain text
- Ask ONE question at a time via `AskUserQuestion`
- 8-10 total questions across all phases
- The Narrow phase is critical — push back hard on scope creep ("that sounds like a separate feature")
- Prefer multiple choice when possible
- The spec becomes the CONTRACT for everything that follows
- Workers build to it, tests validate it, the reviewer compares code against it

## spec.md Output Format

```markdown
# Feature: <name>

## Overview
<1-2 paragraph description>

## User Stories
- As a <role>, I want <capability> so that <benefit>

## Acceptance Criteria
- [ ] <specific, testable criterion>

## Technical Approach
- Files to create/modify
- Data model changes
- API changes
- UI components

## Out of Scope
- <explicitly excluded items>

## Verification Loop
- Enabled: yes/no
- Base URL (UI features only): <local dev URL if known, e.g. http://localhost:3000>
- Browser-check configured: yes/no (scaffolded by autopilot if missing)
- How to exercise the feature end-to-end (if enabled):
  - <how to start the service / run the CLI / open the page>
  - <key flows or commands to validate>
```
