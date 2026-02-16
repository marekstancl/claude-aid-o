---
id: S-{YYYYMMDD}-{4char-hash}
session_id: {YYYY-MM-DD}-exploration-{short-description}
type: exploration
status: active
priority: critical|high|medium|low
started: YYYY-MM-DD HH:MM CET
completed: YYYY-MM-DD HH:MM CET (if completed)
ai_agent: {AI_NAME}
epic_id: {epic-id} (if epic session)
epic_session: {N} of {M} (if epic session)
epic_file: .aid-o/02-epics/{active|completed}/{epic-id}/epic-breakdown.md (if epic session)
---

# Exploration: {Title}

> **Multi-Session Work?** If exploration findings suggest 3+ sessions for implementation, consider creating an **Epic Breakdown** using `.aid-o/03-config/templates/epic.md`.

## Research Question
> Clear, answerable question this exploration aims to resolve

## Time Budget & Scope

**Budget:**
| Phase | Planned | Actual |
|-------|---------|--------|
| Research | 1h | - |
| Options Analysis | 30m | - |
| Prototype (if needed) | 1.5h | - |
| Documentation | 30m | - |
| **Total** | 3.5h | - |

**In Scope:**
- [ ] {Specific thing to investigate}

**Out of Scope:**
- {What we're NOT investigating}

## Success Criteria
- [ ] Understand tradeoffs between at least 2-3 options
- [ ] Have clear recommendation with reasoning
- [ ] Document findings for future reference
- [ ] Know estimated effort for implementation (if proceeding)

---

## Research Phase

### Existing Knowledge
{What do we already know? Check previous sessions, docs, code}

### External Sources
| Source | Key Insight | Relevance |
|--------|-------------|-----------|
| [Link](url) | {Main takeaway} | High/Medium/Low |

### Key Learnings
1. {Learning 1}
2. {Learning 2}

---

## Options Analysis

### Option 0: Do Nothing (Baseline)
**What:** Keep current approach unchanged
**Pros:** No effort, no regression risk
**Cons:** {Cons}

### Option 1: {Option Name}
**What:** {Description}
**Pros:** {list}
**Cons:** {list}
**Effort:** {X hours/days}
**Risk:** {Low/Medium/High}

### Option 2: {Option Name}
{Repeat structure from Option 1}

---

## Prototype (If Needed)

### Goals
- {Goal 1}

### Implementation
```
# Show prototype code here
```

### Results
- **Findings:** {list}
- **Performance:** {metrics}
- **Limitations:** {list}

---

## Recommendations

### Recommended Approach
**Option:** {Option Name}
**Rationale:** {reasons}

### Implementation Plan (If Proceeding)
1. {Step 1}
2. {Step 2}

**Estimated Effort:** {X hours/days}
**Estimated Sessions:** {N sessions}

---

## Documentation Updates

- [ ] Research document created
- [ ] Architecture decision documented (if applicable)

**See:** `skills/coding-standards.md` for documentation dependency tables

---

## References

**External Sources:** [Source](url)
**Related Sessions:** [Previous session](../archive/{session-id}.md)
**Commits:** `{hash}` - {message} (if prototype created)

---

## AI Session Log

**{Timestamp}** - {Action/Decision}

---

## Completion Checklist

### Pre-Completion:
- [ ] Research question answered
- [ ] Options analyzed
- [ ] Recommendations provided
- [ ] Findings documented

### Session Closure:
- [ ] Commit messages follow conventions
- [ ] Session file archived to completed/
- [ ] Handoff protocol executed (see `skills/session-management.md`)
- [ ] Session log updated

---

## Next Steps

**For Human Review:**
- Review recommendations
- Decide on implementation approach

**For AI (if session continues):**
- Implement recommended approach
- Create epic breakdown for implementation

---

**Status:** {active|blocked|completed}
**Last Updated:** {YYYY-MM-DD HH:MM CET}
**Completion:** {%}
