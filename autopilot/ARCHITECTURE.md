# Autopilot: Autonomous SWE Agent Loop

A self-contained Claude Code plugin that turns a feature description into a reviewed PR. It interviews you once, then runs autonomously — exploring the codebase, spawning parallel build teams, verifying quality, getting a fresh-eyes code review, and iterating until the work passes muster.

**One command. Zero babysitting.**

```
/autopilot "Add user preferences page with theme and notification settings"
```

## Plugin Manifest

```json
{
  "name": "autopilot",
  "version": "1.1.0",
  "description": "Self-contained autonomous SWE agent loop..."
}
```

The plugin ships 3 commands, 10 agents, 6 skills, 4 templates, 4 scripts, and 1 hook.

## Component Inventory

```
autopilot/
├── .claude-plugin/plugin.json          ← identity + version
├── ARCHITECTURE.md                     ← this file
│
├── commands/
│   ├── autopilot.md                    ← main entry point (/autopilot)
│   ├── autopilot-status.md             ← session dashboard (/autopilot-status)
│   └── autopilot-cancel.md             ← kill switch (/autopilot-cancel)
│
├── agents/
│   ├── team-lead.md                    ← PM & team lead
│   ├── explorer.md                     ← read-only codebase mapper
│   ├── code-reviewer.md               ← isolated code reviewer
│   ├── infra-reviewer.md              ← infrastructure-focused reviewer
│   ├── spec-guardian.md               ← spec fidelity validator
│   ├── frontend-worker.md              ← UI builder (language-agnostic)
│   ├── backend-worker.md               ← server-side builder
│   ├── test-worker.md                  ← spec-first test writer
│   ├── qa-tester.md                    ← adversarial QA with optional browser testing
│   └── simplifier.md                   ← post-build code simplification
│
├── skills/
│   ├── dance-spec/SKILL.md             ← DANCE interview framework
│   ├── phase-runner/SKILL.md           ← phase dispatch logic
│   ├── git-workflow/SKILL.md           ← branch, commit, push, PR
│   ├── code-review/
│   │   ├── SKILL.md                    ← review criteria
│   │   └── references/review-criteria.md
│   ├── code-simplify/SKILL.md          ← simplification rules
│   └── qa-testing/SKILL.md             ← two-phase QA protocol
│
├── hooks/
│   ├── hooks.json                      ← hook registration (Stop event)
│   └── autopilot-stop-hook.sh          ← the autonomous loop engine
│
├── scripts/
│   ├── setup-autopilot.sh              ← session initialization
│   ├── check-quality-gates.sh          ← type-check, lint, tests
│   ├── commit-and-pr.sh                ← git workflow automation
│   ├── run-reviewer.sh                 ← launches Code Reviewer in claude -p
│   └── lib/
│       └── state.sh                    ← shared state read/write helpers
│
└── templates/
    ├── reviewer-prompt.md              ← Code Reviewer's prompt ({{SPEC}}, {{DIFF}})
    ├── simplifier-prompt.md            ← post-build simplification prompt
    ├── qa-prompt.md                    ← QA generation prompt
    └── browser-test-plan.md            ← browser test plan template (tool-agnostic)
```

## How It Thinks: The DANCE Framework

Before a line of code is written, the Team Lead interviews you using DANCE — a structured 8-10 question framework that front-loads all the thinking:

| Phase | Purpose | Team Lead asks... |
|-------|---------|---------------|
| **D**iscover | Understand the feature | "Elevator pitch. Who's it for? Where does it live?" |
| **A**nalyze | Probe deeper | "Data model? Existing patterns to reuse? Edge cases?" |
| **N**arrow | Lock scope | "Here's what's IN. Here's what's OUT. Fight me." |
| **C**ode | Write the spec | Produces `spec.md` with stories, files, acceptance criteria |
| **E**valuate | Get sign-off | "Read it. Anything missing? Shall I proceed?" |

This isn't bureaucratic — it forces you to articulate the thing you haven't fully formed. The **N**arrow step is particularly powerful — the Team Lead pushes back on scope creep ("that sounds like a separate feature") before anyone touches code. The spec becomes the contract for everything that follows. Workers build to it. Tests validate it. The Spec Guardian compares code against it.

## The Loop

The main phases flow: SPEC → EXPLORE → BUILD → VERIFY → (pass→COMMIT, fail→FIX→VERIFY) → REVIEW → (approve→DONE, changes→BUILD)

**SPEC** is interactive — the Team Lead asks you questions. Everything after is autonomous, driven by a stop hook that reads the current phase from `state.json` and injects the next instruction. The loop terminates when the review passes, the iteration limit is hit, or you cancel.

## The Cast

Autopilot uses 10 specialized agent personas. Each has a distinct job, a constrained toolset, and a personality that shapes how they work.

### Team Lead (PM & Orchestrator) — Mustard `#FFBB1B`
The Team Lead has two faces. During SPEC, it's a product manager — interviewing you, pushing back on scope creep, writing a tight spec. During BUILD, it becomes an orchestrator — decomposing the spec into parallel tasks, spawning workers, monitoring progress, resolving conflicts.

### Explorer (Codebase Cartographer) — Matcha `#A8CC3E`
The Explorer is the codebase cartographer. Read-only — it can only observe and report. Before anyone builds anything, the Explorer maps the terrain: import conventions, component patterns, state management approaches, test frameworks, styling patterns, naming conventions, and relevant utilities.

### Code Reviewer — Carrot `#FF7009`
The Code Reviewer is the senior code reviewer, and it's deliberately isolated. It runs via `happy -p` in a separate process — it's never seen the build errors, the workarounds, the "I'll fix this later" compromises. Its verdict is binary: APPROVE or REQUEST_CHANGES.

### Infra Reviewer — Crimson `#b91c1c`
The Infra Reviewer is the infrastructure-minded second reviewer. Where the Code Reviewer focuses on code quality and correctness, the Infra Reviewer thinks about blast radius, failure modes, and operational impact. Its verdict is a three-level scale: SHIP IT, FIX THEN SHIP, or NOPE.

### Spec Guardian — Cashew `#FAF1E5`
The Spec Guardian doesn't build. Doesn't test. Validates. It reads every acceptance criterion in the spec and watches what both the coders and the testers produce.

### The Workers — Honeydew `#C5FF96`
Frontend workers, backend workers, and test workers are the hands. They're language-agnostic — they read `exploration.md` and adapt to whatever stack they find.

### QA Tester — Cantaloupe `#FFBB6E`
The QA tester starts working the moment BUILD begins — not when code is done. They read the spec and immediately start writing `qa-guide.md`. If browser testing is enabled (opted in during SPEC), the QA tester also writes `browser-test-plan.md` with concrete flows. A separate browser validation agent executes the plan during VERIFY using `agent-browser` CLI connected to Chrome Debug.

### Simplifier
Runs after BUILD completes. Reviews recently written code and simplifies it.

## The Swarm

The BUILD phase is where parallelism gets interesting. The Team Lead creates a team, decomposes the spec into tasks with dependency chains, then spawns workers. The critical design choice: **test and QA tasks are NOT blocked by code tasks**. Both start from the spec simultaneously.

## The Engine: Stop Hook

The autonomous loop is powered by `hooks/autopilot-stop-hook.sh` — a shell script that intercepts Claude's exit signal and decides whether to let it stop or inject a continuation prompt.

### How It Works

1. Reads JSON from stdin (`transcript_path`)
2. Checks for an active session via `.claude/autopilot.local.md` frontmatter
3. Reads `state.json` from the session directory
4. **Terminal phases** (DONE, CANCELLED, SPEC) → allow exit
5. **Iteration limit** (configurable `max_iterations`, default 10) → force DONE, allow exit
6. **Completion promise** — scans the transcript for a `<promise>` tag matching the expected completion text → mark DONE, allow exit
7. **Active phase** → increment iteration, inject continuation prompt with phase instructions, block exit

## Session Isolation

Each `/autopilot` invocation creates an isolated session. Two engineers running autopilot on different features in the same repo don't interfere with each other.

## Design Decisions Worth Knowing

**Why spec-first testing?** Tests that verify what the code does, not what the spec requires, enshrine bugs.

**Why a Spec Guardian?** Code review catches quality issues. Spec fidelity — "did we build what was asked for?" — is a different question.

**Why two reviewers?** The Code Reviewer focuses on code correctness. The Infra Reviewer focuses on systems thinking. Different lenses catch different problems.

**Why isolated review?** The builder accumulates context bias. The Code Reviewer in `happy -p` sees none of that.

**Why DANCE before EXPLORE?** The spec focuses the exploration. The Explorer only maps what's relevant.

**Why language-agnostic workers?** Workers read the Explorer's `exploration.md` and adapt. The intelligence is in the exploration.

**Why a stop hook, not a while loop?** Claude Code's stop hook mechanism is battle-tested and phase-aware.

**Why constraints make agents better?** A reviewer who can also edit will start fixing instead of reviewing. Every constraint forces focus.