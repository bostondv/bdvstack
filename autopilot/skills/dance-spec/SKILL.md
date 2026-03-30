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

**Browser testing:** If the feature has a UI component AND the user hasn't already mentioned browser testing preferences, add ONE question:
- "Should I include automated browser testing for this feature — navigating pages, filling forms, clicking buttons, taking screenshots to verify the UI works? Requires `agent-browser` CLI and Chrome Debug running. [Yes / No]"

Record the answer in state.json as `"browser_testing": true|false`. If yes, also ask for the base URL if not already known (e.g. `http://localhost:3000`).

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

## Browser Testing
- Enabled: yes/no
- Base URL: <local dev URL if known, e.g. http://localhost:3000>
- Key flows to validate in browser (if enabled):
  - <flow 1: description + expected outcome>
  - <flow 2: description + expected outcome>
```
