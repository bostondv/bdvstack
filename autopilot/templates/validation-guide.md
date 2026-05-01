# Validation Guide

Worker-authored instructions for the VALIDATE phase. Workers append entries here during BUILD so the validator has concrete, copy-pasteable steps for exercising the feature at runtime. The validator has not seen the code — only spec.md, exploration.md, and this file.

Be precise. No prose summaries — give exact commands, exact routes, exact expected outputs.

## Prerequisites

What must be true before VALIDATE can run? Examples:
- `bento` running on port 3000 (or `npm run dev`)
- `DATABASE_URL` set, migrations applied
- Logged-in Chrome session for the test user
- Fixture data seeded (`yarn seed:fixtures`)

## Surfaces to Exercise

For each surface (endpoint, page, CLI command), document exactly how to drive it and what to expect.

### <surface name>
- **Type:** api | ui | cli | library
- **How to invoke:**
  ```
  <copy-pasteable command, URL, or steps>
  ```
- **Expected:** <status code, response shape, visible UI, output>
- **Edge cases worth checking:** <empty input, auth failure, etc.>

## Out of Scope for VALIDATE

Things this feature does that genuinely can't be exercised at runtime — VALIDATE will mark these SKIPPED with this reason:
- Cron jobs that fire on a schedule
- Third-party webhook callbacks
- Background workers triggered by external events

## Notes

Anything else the validator needs to know — known flaky behaviors, ordering requirements between surfaces, etc.
