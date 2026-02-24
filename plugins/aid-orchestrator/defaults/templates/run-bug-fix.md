---
id: R-{YYYYMMDD}-{4char-hash}
run_id: {YYYY-MM-DD}-bug-fix-{short-description}
type: bug-fix
status: active
priority: critical|high|medium|low
started: YYYY-MM-DD HH:MM CET
completed: YYYY-MM-DD HH:MM CET (if completed)
ai_agent: {AI_NAME}
epic_id: {epic-id} (if epic run)
epic_run: {N} of {M} (if epic run)
epic_file: .aid-o/02-epics/{active|completed}/{epic-id}/epic-breakdown.md (if epic run)
plan_ref: {path to plan.json or plan file} (if exists)
orchestrated: true|false (if orchestrated by Controller)
---

# Bug Fix: {Title}

> **Multi-Run Work?** If this bug fix requires 3+ runs or involves multiple components, consider creating an **Epic Breakdown** first using `.aid-o/03-config/templates/epic.md`.

## Objective
<!-- MIN: 3-5 sentences. State WHAT is broken, WHY it matters, and what FIXED looks like.
     Bad:  "Fix login crash"
     Good: "Fix crash on login when user has special characters in password. Users with
            passwords containing '&' or '<' trigger an unescaped HTML injection in the
            auth form (Issue #87). This blocks ~5% of users from logging in. Fixed means:
            all special characters are properly escaped, login succeeds for all valid
            passwords, and XSS vector is eliminated." -->

## Context
<!-- What preceded this work. Reference previous runs, state of the codebase, dependencies.
     For orchestrated runs: which EPIC run is this, what was delivered before.
     For non-orchestrated: what's the current project state, any related ongoing work. -->

**Previous work:** {reference prior runs or "N/A — first report"}
**Current state:** {what exists now, when did the bug first appear}
**Dependencies:** {external systems, libraries, or other runs this depends on}

## Scope
<!-- Explicit IN/OUT lists prevent scope creep. Be specific — name files, components, areas. -->

**In Scope:**
<!-- MIN: 3 items -->
- {what WILL be done}
- {what WILL be done}
- {what WILL be done}

**Out of Scope:**
<!-- MIN: 2 items -->
- {what will NOT be done in this run}
- {what will NOT be done in this run}

---

## Discovery
<!-- Bug-specific context. Fill in every field — this is critical for root cause analysis
     and for future agents who need to understand the bug without re-investigating. -->

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

## Phases

<!-- Each phase = one logical chunk of work. Map from plan.json steps (orchestrated)
     or decompose the task yourself (non-orchestrated).
     Every phase MUST have all 6 subsections below. Do not skip any. -->

### Phase 1: Investigation

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters in the run context. -->
{Reproduce the bug, trace execution path, identify root cause. Explain what you expect to find
and why narrowing the root cause first prevents wasted effort on symptoms rather than the
underlying defect.}

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

### Phase 2: Fix Implementation

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters in the run context. -->
{Apply the minimal, targeted fix that addresses the root cause identified in Phase 1. Explain
the fix strategy and why it's preferred over alternatives. This phase should change only what
is necessary to resolve the defect without introducing side effects.}

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

### Phase 3: Regression Testing

**Goal:**
<!-- MIN: 1 full paragraph. What this phase accomplishes and why it matters in the run context. -->
{Verify the fix resolves the reported symptom AND does not break existing functionality.
Write regression tests that would catch this bug if it were re-introduced. Confirm all
existing test suites still pass.}

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

<!-- Repeat for additional phases if needed. -->

---

## Dependencies

<!-- Which phases depend on which and why. For single-phase runs, write "No inter-phase dependencies." -->

| Phase | Depends On | Reason |
|-------|-----------|--------|
| Phase 2 | Phase 1 | {why — e.g., "needs root cause analysis from Phase 1"} |
| Phase 3 | Phase 2 | {why — e.g., "needs fix applied before regression testing"} |

---

## Quality Gates

<!-- What automated checks run after this run's work. Reference specific gate names from gates.yaml. -->

- **{gate name}** — {what it verifies}

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

**See:** `skills/agent-core.md` for documentation dependency tables

---

## References

**Related Issues:** #{issue_number}
**Related PRs:** #{pr_number}
**Related Runs:** [Previous run](../archive/{run-id}.md)
**Commits:** `{hash}` - {message}

---

## AI Run Log

**{Timestamp}** - {Action/Decision}

---

## Completion Checklist

### Pre-Completion:
- [ ] Bug fixed and verified
- [ ] Tests written and passing
- [ ] Documentation updated
- [ ] No TODO/FIXME left in code

### Run Closure:
- [ ] Commit messages follow conventions
- [ ] Run file archived to completed/
- [ ] Handoff protocol executed (see `skills/run-management.md`)
- [ ] Run log updated

---

## Next Steps

**For Human Review:**
- Review PR #{pr_number}
- Validate fix in staging

**For AI (if run continues):**
- Monitor for related issues
- Consider optimization opportunities

---

**Status:** {active|blocked|completed}
**Last Updated:** {YYYY-MM-DD HH:MM CET}
**Completion:** {%}
