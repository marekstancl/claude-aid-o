---
id: S-{YYYYMMDD}-{4char-hash}
session_id: {YYYY-MM-DD}-bug-fix-{short-description}
type: bug-fix
status: active
priority: critical|high|medium|low
started: YYYY-MM-DD HH:MM CET
completed: YYYY-MM-DD HH:MM CET (if completed)
ai_agent: {AI_NAME}
epic_id: {epic-id} (if epic session)
epic_session: {N} of {M} (if epic session)
epic_file: .aid-o/02-epics/{active|completed}/{epic-id}/epic-breakdown.md (if epic session)
---

# Bug Fix: {Title}

> **Multi-Session Work?** If this bug fix requires 3+ sessions, consider creating an **Epic Breakdown** first using `.aid-o/03-config/templates/epic.md`.

## Objective
> One-sentence description of what needs to be fixed

## Discovery
**Reported:** {Date}
**Discovered In:** {Environment - dev/staging/prod}
**Affected Features:** {List components affected}
**Severity:** CRITICAL / HIGH / MEDIUM / LOW

### Symptom
{What's visibly broken? User-facing description}

### Expected Behavior
{What should happen correctly?}

### Current Behavior
{What actually happens?}

---

## Investigation Steps

**Checklist (update as you progress):**
- [ ] Reproduced bug locally
- [ ] Analyzed logs/errors
- [ ] Identified root cause in {file.py:line}
- [ ] Verified scope (what else is affected?)
- [ ] Checked for similar issues in codebase

### Investigation Log
**{Timestamp}** - {Finding}

---

## Solution

### Root Cause
{Technical explanation of WHY bug exists}

### Proposed Fix
{High-level strategy}

### Changes Made
| File | Lines | Description | Commit |
|------|-------|-------------|--------|
| {path/file.py} | 123-145 | {What changed} | {hash} |

### Code Snippet
```
# Show key changes here
```

---

## Testing

### Test Plan
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual QA in dev environment
- [ ] Edge cases covered
- [ ] Performance validated (if relevant)

### Test Results
**Unit Tests:**
```
pytest tests/test_fix.py
```

**Manual QA:**
- {Verification steps and results}

---

## Impact

### Before Fix:
- {Metric 1}

### After Fix:
- {Metric 1}

---

## Documentation Updates

- [ ] Relevant docs updated
- [ ] `CHANGELOG.md` entry added

**See:** `skills/coding-standards.md` for documentation dependency tables

---

## References

**Related Issues:** #{issue_number}
**Related PRs:** #{pr_number}
**Related Sessions:** [Previous session](../archive/{session-id}.md)
**Commits:** `{hash}` - {message}

---

## AI Session Log

**{Timestamp}** - {Action/Decision}

---

## Completion Checklist

### Pre-Completion:
- [ ] Bug fixed and verified
- [ ] Tests written and passing
- [ ] Documentation updated
- [ ] No TODO/FIXME left in code

### Session Closure:
- [ ] Commit messages follow conventions
- [ ] Session file archived to completed/
- [ ] Handoff protocol executed (see `skills/session-management.md`)
- [ ] Session log updated

---

## Next Steps

**For Human Review:**
- Review PR #{pr_number}
- Validate fix in staging

**For AI (if session continues):**
- Monitor for related issues
- Consider optimization opportunities

---

**Status:** {active|blocked|completed}
**Last Updated:** {YYYY-MM-DD HH:MM CET}
**Completion:** {%}
