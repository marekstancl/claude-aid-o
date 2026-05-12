---
id: P{NNN}
type: regular   # Plan content classification — enum: regular | bug-fix | refactor | docs
                # Controls quality gate activation:
                #   regular  → standard checks #1-18 + 17e
                #   bug-fix  → standard + #19 (Design Defeat Detection)
                #   refactor → standard + 17e + heightened #18
                #   docs     → standard, skip behavior-related checks
                # Default if missing: regular. Legacy `type: plan` is treated
                # as alias for `regular` (P001-P035 backward-compat).
status: draft
created: YYYY-MM-DD
author: PM + AI
---

# Plan: {Title}

## Plan Type

This plan is type: `{regular | bug-fix | refactor | docs}` (per frontmatter `type:` field).

| Type | Description | Activates |
|------|-------------|-----------|
| `regular` | Feature additions, new capabilities | Standard checks #1-18 + 17e |
| `bug-fix` | Fixes existing precondition / validation / behavior failure | Standard + #19 (Design Defeat Detection) |
| `refactor` | Code restructuring without behavior change | Standard + 17e + heightened #18 (outputs concreteness) |
| `docs` | Documentation-only changes (markdown, comments) | Standard, skip behavior-related checks (#19, runtime grounding) |

**Default if missing:** `regular`. Legacy `type: plan` (used by P001-P035) is treated as an alias for `regular`. Validation: invalid value → REVISE_REQUIRED with the valid enum list.

## Context

{Why does this plan exist? What problem does it solve? What triggered it?}

## Goal

{One-sentence description of the desired outcome}

## Scope

**In scope:**
- {What this plan covers}

**Out of scope:**
- {What this plan does NOT cover}

## Approach

### Option A: {Name} (Recommended)
{Description of approach}

**Pros:**
- {Advantage 1}

**Cons:**
- {Disadvantage 1}

### Option B: {Name}
{Description of alternative approach}

**Pros:**
- {Advantage 1}

**Cons:**
- {Disadvantage 1}

### Decision

**Chosen:** Option A
**Rationale:** {Why this option}

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1 | {Step name} | {What needs to happen} | {S/M/L} |
| 2 | {Step name} | {What needs to happen} | {S/M/L} |

## Constraints

- {Technical constraint}
- {Business constraint}
- {Timeline constraint}

## Resources Verification

> Auto-populated by `/aid-plan` Step 9 verifier dispatch (CP1). Each item must be
> VERIFIED (with location/evidence) or ABSENT (mapped to a Create step in this plan
> OR confirmed as PM-acknowledged risk).
>
> Detection: items extracted via grep/regex from whole plan body — no specific
> `related_backlog` or similar field required. Verifier scans the entire plan.

### Existing Resources (must exist in codebase)

- [ ] Functions/helpers: {list extracted from plan + grep results}
- [ ] File paths: {list extracted from Files entries + ls results}
- [ ] Ports: {list + docker ps cross-check}
- [ ] Services / containers: {list + docker ps name collision check}
- [ ] External commands: {list + command -v results}
- [ ] Environment variables: {list + grep declaration results}

### Plan Assumptions (must match reality — Completeness Gate sub-checks 17a-17d)

- [ ] Backlog IDs (T-NNN): {whole-plan regex `\bT-[0-9]+\b` + `git log --since="24 hours ago" --grep` grounding}
- [ ] Test directory paths: {list + `find tests/ -type f \( -name "*.py" -o -name "*.ts" -o -name "*.bats" \) -name "*<basename>*"` analog search}
- [ ] DB field semantics: {regex `[A-Z][a-zA-Z]+\.[a-z_]+` + models.py stored vs computed verification}
- [ ] File removal claims: {list + ls existence verification}

### Resolution

- [ ] All items VERIFIED OR mapped to a Create step in this plan
- [ ] PM acknowledges any ABSENT items as out-of-scope risks (with rationale)

## Acceptance Criteria

> Plan-level AC (distinct from per-step AC). Each AC describes a state that
> must hold in the codebase after EXECUTE+GATES+DONE. Each AC has a
> `verification_pattern` block that `aid-plan-diff.sh` runs against codebase
> HEAD to produce per-AC verdict (`present`|`absent`).
>
> **Three pattern types:**
> - `cmd` — run shell command, check exit code matches `expected_exit`
> - `must_not_exist` — file must be absent
> - `must_contain` — file exists AND contains regex match (any matching line suffices)
>
> Patterns must be self-contained (no `<placeholder>` brackets, no unresolved variables).
> Plan-writing Completeness Gate sub-check #20 enforces this for new plans.

- [ ] AC1: {one-sentence claim}
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "{concrete shell command}"
    expected_exit: 0
  ```

- [ ] AC2: {one-sentence claim}
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "{concrete file path relative to repo root}"
  ```

- [ ] AC3: {one-sentence claim}
  ```yaml
  verification_pattern:
    type: must_contain
    file: "{concrete file path}"
    regex: "{regex — any line match suffices}"
  ```

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| {Risk 1} | low/medium/high | low/medium/high | {How to mitigate} |

## Success Criteria

- {How do we know this plan succeeded?}

## Next Steps

- [ ] Create Epic(s) from this plan
- [ ] {Additional preparation steps}

---

**Last Updated:** 2026-05-12
