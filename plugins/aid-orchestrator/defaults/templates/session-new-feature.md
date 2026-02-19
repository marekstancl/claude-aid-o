---
id: S-{YYYYMMDD}-{4char-hash}
session_id: {YYYY-MM-DD}-new-feature-{short-description}
type: new-feature
status: active
priority: critical|high|medium|low
started: YYYY-MM-DD HH:MM CET
completed: YYYY-MM-DD HH:MM CET (if completed)
ai_agent: {AI_NAME}
epic_id: {epic-id} (if epic session)
epic_session: {N} of {M} (if epic session)
epic_file: .aid-o/02-epics/{active|completed}/{epic-id}/epic-breakdown.md (if epic session)
plan_ref: {path to plan.json or plan file} (if exists)
orchestrated: true|false (if orchestrated by Controller)
---

# New Feature: {Title}

> **Multi-Session Work?** If this feature requires 3+ sessions or involves multiple components, consider creating an **Epic Breakdown** first using `.aid-o/03-config/templates/epic.md`.

## Objective
<!-- MIN: 3-5 sentences. State WHAT you're building, WHY it's needed, and what SUCCESS looks like.
     Bad:  "Add dark mode"
     Good: "Add dark mode toggle to application settings. Users have requested reduced eye strain
            for evening use (Issue #42). This enables theme switching via a persistent user
            preference stored in localStorage. Success: toggle works, preference persists across
            sessions, all components respect the theme." -->

## Context
<!-- What preceded this work. Reference previous sessions, state of the codebase, dependencies.
     For orchestrated sessions: which EPIC session is this, what was delivered before.
     For non-orchestrated: what's the current project state, any related ongoing work. -->

**Previous work:** {reference prior sessions or "N/A — greenfield"}
**Current state:** {what exists now that this session builds on}
**Dependencies:** {external systems, libraries, or other sessions this depends on}

## Scope
<!-- Explicit IN/OUT lists prevent scope creep. Be specific — name files, components, areas. -->

**In Scope:**
<!-- MIN: 3 items -->
- {what WILL be done}
- {what WILL be done}
- {what WILL be done}

**Out of Scope:**
<!-- MIN: 2 items -->
- {what will NOT be done in this session}
- {what will NOT be done in this session}

---

## Requirements
<!-- Define what the feature must do. Use MoSCoW prioritization for technical requirements.
     For orchestrated sessions: derive from EPIC scope + plan.json constraints.
     For non-orchestrated: derive from PM's request + codebase analysis. -->

### Business Requirements
**User Story:**
> As a {user type}, I want {goal} so that {benefit}

**Success Criteria:**
- {Criterion 1}
- {Criterion 2}

### Technical Requirements
- **Must Have:**
  - [ ] {Requirement 1}
  - [ ] {Requirement 2}
- **Should Have:**
  - [ ] {Requirement 3}
- **Nice to Have:**
  - [ ] {Requirement 4}

### Constraints
- **Performance:** {e.g., "Response time < 2s"}
- **Security:** {e.g., "Data encryption at rest"}
- **Compatibility:** {e.g., "DOCX 2007+ format support"}

---

## Phases

<!-- Each phase = one logical chunk of work. Map from plan.json steps (orchestrated)
     or decompose the task yourself (non-orchestrated).
     Every phase MUST have all 6 subsections below. Do not skip any. -->

### Phase 1: {Phase Title}

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters in the session context. -->
{Describe what this phase solves — not just "implement X" but why, what it enables, what changes.}

**Agent / Role:** {role name — e.g., backend, frontend, architect, security, qa}

**Inputs:**
<!-- Files, context, or outputs from previous phases that this phase needs. -->
- {file path or description}

**Outputs:**
<!-- Files produced, artifacts created. Include expected file paths. -->
- {file path or description}

**Constraints:**
<!-- Boundaries: allowed/forbidden paths, backward compatibility, performance limits. -->
- {constraint}

**Acceptance:**
<!-- MIN: 3 items. How we verify this phase is done. -->
- [ ] {criterion 1}
- [ ] {criterion 2}
- [ ] {criterion 3}

<!-- Repeat for Phase 2, Phase 3, etc. -->

---

## Dependencies

<!-- Which phases depend on which and why. For single-phase sessions, write "No inter-phase dependencies." -->

| Phase | Depends On | Reason |
|-------|-----------|--------|
| Phase 2 | Phase 1 | {why — e.g., "needs API contract from Phase 1"} |

---

## Quality Gates

<!-- What automated checks run after this session's work. Reference specific gate names from gates.yaml. -->

- **{gate name}** — {what it verifies}

---

## Testing

### Test Plan
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual QA in dev environment
- [ ] Edge cases covered
- [ ] Performance validated

### Test Results
**Unit Tests:**
```
pytest tests/test_new_feature.py
```

---

## Impact

- **Lines of Code:** {X} added, {Y} modified
- **Test Coverage:** {X}%
- **Performance:** {metrics}

---

## Documentation Updates

- [ ] API docs updated
- [ ] Developer guides updated
- [ ] `CHANGELOG.md` entry added

**See:** `skills/agent-core.md` for documentation dependency tables

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
- [ ] Feature implemented and tested
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
- Validate feature in staging

**For AI (if session continues):**
- Monitor for related issues
- Consider optimization opportunities

---

**Status:** {active|blocked|completed}
**Last Updated:** {YYYY-MM-DD HH:MM CET}
**Completion:** {%}
