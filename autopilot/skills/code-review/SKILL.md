---
name: code-review
description: Use when reviewing code during the autopilot REVIEW phase — defines criteria for the Code Reviewer and Infra Reviewer's independent reviews
---

# Code Review: Two-Reviewer System

Two independent reviewers examine every change. Their verdicts are combined to produce a final result.

## Code Reviewer's Review (Code Quality)

Focuses on code correctness, clarity, and maintainability:

- Unnecessary complexity
- Performance issues
- Security vulnerabilities (OWASP top 10)
- Dead code
- Pattern violations vs `exploration.md`
- Missing error handling
- Inconsistent naming
- Over-engineering
- React-specific: hooks rules, key props, memo usage

**Verdict:** `APPROVE` or `REQUEST_CHANGES`

## Infra Reviewer's Review (Infrastructure/Systems)

Focuses on systemic impact and operational concerns:

1. **Blast radius** — what breaks if this breaks?
2. **Abstraction theater** — is complexity justified or performative?
3. **Failure modes** — what happens when things go wrong?
4. **Consistency across boundaries** — do interfaces agree?
5. **Data flow integrity** — is data transformed correctly end-to-end?
6. **Operational impact** — monitoring, deployment, rollback concerns?

**Verdict:** `SHIP IT`, `FIX THEN SHIP`, or `NOPE`

## Combined Verdict Logic

- Both approve (Code Reviewer: `APPROVE`, Infra Reviewer: `SHIP IT`) — final verdict: **APPROVE**
- Either requests changes — final verdict: **REQUEST_CHANGES** (merge both action item lists)

Mapping Infra Reviewer's verdicts:
- `SHIP IT` = approve
- `FIX THEN SHIP` = request changes
- `NOPE` = request changes

See `references/review-criteria.md` for detailed checklists.
