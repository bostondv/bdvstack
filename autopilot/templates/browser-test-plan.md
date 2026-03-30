# Browser Test Plan

## App Context

- **Base URL:** {{BASE_URL}}
- **Feature:** {{FEATURE_NAME}}
- **What changed:** {{SUMMARY_OF_CHANGES}}

## Prerequisites

- Dev server running at the base URL
- Chrome Debug running on port 9222 with a logged-in session (if auth required)
- {{ADDITIONAL_PREREQUISITES}}

## Flows

{{FLOWS}}

---

## Flow Format Reference

Each flow follows this structure. Flows are executed sequentially using `agent-browser` CLI connected to Chrome Debug.

```markdown
### Flow N: <descriptive name>

**Route:** <URL path, e.g. /settings>
**Criteria:** <one-line summary of what to validate — the pass/fail check>

**Preconditions:** <state that must be true — logged in, data exists, etc.>

**Steps:**
1. Navigate to <base URL + route>
2. Verify <element/content> is visible on the page
3. Click the "<button/link text>" button/link
4. Fill the "<field label>" field with "<test value>"
5. Select "<option>" from the "<dropdown label>" dropdown
6. Submit the form / click "<action button>"
7. Wait for <navigation/content update/success message>

**Expected outcome:**
- Page shows <specific content or state>
- URL changes to <expected URL>
- <element> displays <expected value>
- No error messages visible

**What could go wrong:**
- <potential failure mode>
```

### Field reference:
- **Route** (required) — URL path relative to base URL
- **Criteria** (required) — one-line validation summary, the primary pass/fail check
- **Preconditions** — state required before the flow (auth, test data)
- **Steps** — concrete user actions with element descriptions (button text, field labels, dropdown names)
- **Expected outcome** — specific, verifiable assertions
- **What could go wrong** — potential failure modes to help diagnose issues
