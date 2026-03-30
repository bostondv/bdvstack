# Review Criteria Reference

## Code Reviewer — Code Quality Checklist

### Complexity
- [ ] No unnecessary abstractions or indirection
- [ ] Functions do one thing and are reasonably sized
- [ ] No deeply nested logic (3+ levels)
- [ ] No premature optimization

### Performance
- [ ] No N+1 queries or unbounded loops
- [ ] Expensive operations are memoized or cached where appropriate
- [ ] No unnecessary re-renders (React)
- [ ] Large lists are virtualized if needed

### Security (OWASP Top 10)
- [ ] No SQL/NoSQL injection vectors
- [ ] No XSS vulnerabilities (user input is sanitized)
- [ ] Authentication/authorization checks in place
- [ ] No sensitive data in logs or error messages
- [ ] No hardcoded secrets or credentials
- [ ] CSRF protection where applicable

### Code Hygiene
- [ ] No dead code or unused imports
- [ ] No commented-out code
- [ ] Consistent naming conventions
- [ ] Error handling covers failure cases
- [ ] No swallowed errors (empty catch blocks)

### Pattern Consistency
- [ ] Follows patterns documented in exploration.md
- [ ] Uses existing utilities rather than reimplementing
- [ ] Consistent with codebase conventions

### React-Specific
- [ ] Hooks follow rules of hooks (no conditional hooks)
- [ ] List items have stable key props
- [ ] React.memo used appropriately (not everywhere)
- [ ] useEffect dependencies are correct
- [ ] No state that can be derived from other state

---

## Infra Reviewer — Infrastructure/Systems Checklist

### 1. Blast Radius
- [ ] Failure in this code is isolated — doesn't cascade
- [ ] Feature flags or rollback path exists
- [ ] Database migrations are reversible

### 2. Abstraction Theater
- [ ] Every abstraction earns its keep
- [ ] No "just in case" interfaces or factories
- [ ] Complexity matches the problem being solved

### 3. Failure Modes
- [ ] Graceful degradation on dependency failure
- [ ] Timeouts on external calls
- [ ] Retry logic has backoff and limits
- [ ] Error states are user-visible and actionable

### 4. Consistency Across Boundaries
- [ ] API contracts match between frontend and backend
- [ ] Types/schemas are shared or validated at boundaries
- [ ] No implicit assumptions about data shape

### 5. Data Flow Integrity
- [ ] Data transformations are correct end-to-end
- [ ] No data loss in serialization/deserialization
- [ ] Validation happens at system boundaries

### 6. Operational Impact
- [ ] No new unmonitored failure points
- [ ] Logging is sufficient for debugging
- [ ] No performance regression under load
- [ ] Deployment requires no manual steps
