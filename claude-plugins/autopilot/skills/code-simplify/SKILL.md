---
name: code-simplify
description: Use when running the post-build simplification pass — reduces complexity while preserving all behavior
---

# Code Simplification Rules

Run after BUILD completes. The goal is less complexity, not different structure.

## Scope

Only touch files changed in this session:
```
git diff --name-only main...HEAD
```

## Rules

1. **Every change must preserve behavior** — if unsure, skip
2. **Reduce nesting** — extract early returns, flatten if/else chains
3. **Remove redundancy** — consolidate duplicate logic
4. **Prefer explicit over clever** — no ternary chains, no nested template literals
5. **Flatten unnecessary abstractions** — inline single-use helpers
6. **Remove dead code** — unused imports, unreachable branches
7. **Simplify conditionals** — De Morgan's laws, positive conditions over negative

## Do NOT

- Add comments, types, or docstrings to unchanged code
- Rename variables unless the name is actively misleading
- Refactor — simplify. Less complexity, not different structure
- Touch files outside the session's diff
- Make changes you aren't confident preserve behavior
