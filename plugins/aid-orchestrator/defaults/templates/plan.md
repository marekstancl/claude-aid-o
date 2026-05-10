---
id: P{NNN}
type: plan
status: draft
created: YYYY-MM-DD
author: PM + AI
---

# Plan: {Title}

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

**Last Updated:** 2026-05-10
