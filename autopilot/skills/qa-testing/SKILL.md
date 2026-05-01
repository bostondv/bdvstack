---
name: qa-testing
description: Use when running QA testing during autopilot BUILD phase — defines the two-phase QA approach starting from spec before code exists
---

# Two-Phase QA Protocol

QA starts immediately from the spec, before code exists. It does not wait for implementation.

## Phase 1: Spec-Driven (Immediate, Before Code)

1. Read `spec.md` acceptance criteria
2. Create `qa-guide.md` with:

### Test Plan
- What to test, in what order
- Priority ranking of test scenarios

### Edge Cases
- Boundary values
- Empty states
- Error conditions
- Unexpected input types

### Accessibility Checks
- Keyboard navigation (tab order, focus traps)
- Screen reader compatibility
- Color contrast ratios
- Focus management on route changes and modals

### Error Scenarios
- Network failures (offline, timeout, 5xx)
- Invalid input (too long, wrong type, special characters)
- Concurrent operations (double submit, race conditions)

### Security Considerations
- XSS via user input fields
- Injection attacks
- Auth bypass attempts
- CSRF where applicable

## Phase 2: Code-Driven (As Code Lands)

1. Update `qa-guide.md` with concrete test steps based on actual implementation
2. End-to-end scenarios that cross boundaries (frontend -> API -> DB -> response)
3. Regression checks: verify existing functionality still works

The end-to-end runtime verification (curling endpoints, driving the browser, exercising the CLI) is handled by the separate VALIDATE phase if `verification_loop` is enabled. The QA tester does not execute it — but `qa-guide.md` should still capture the scenarios that VALIDATE will exercise so they're documented.
