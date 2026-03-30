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
2. If `browser_testing` is enabled in spec:
   - Write `{session_dir}/browser-test-plan.md` with concrete browser validation flows
   - Each flow: route (URL path), criteria (what to validate), steps (user actions), expected outcomes
   - Refine flows as code lands — use actual routes, element labels, and form fields from implementation
   - The plan is executed by a separate browser validation step in VERIFY, not by the QA tester
3. End-to-end scenarios that cross boundaries (frontend -> API -> DB -> response)
4. Regression checks: verify existing functionality still works
