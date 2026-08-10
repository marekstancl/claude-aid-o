---
id: P025
type: plan
status: done
created: 2026-03-14
author: PM + AI
version: v2.6.0
---

# Plan: Standards Enforcement System

## Context

AID Orchestrator dispatches agents that produce code, but has no mechanism to enforce consistent development standards across projects. Each project defines its own conventions (or none), leading to inconsistent quality. Two concrete standard sets exist:

1. **General** — universal, language-agnostic development standards (27→26 rules after removing GEN-014 duplicate)
2. **Vulcan** — ecosystem-specific standards for the Vulcan multi-tenant AI platform (22 rules + 4 severity overrides)

Standards were synthesized from Google Engineering Practices, OWASP, Clean Code, 12-Factor App, Conventional Commits, and validated against C.I.C.E.R.O. project conventions (18/26 general rules confirmed in practice).

### Determinism Principle (70/30)

All gate-blocking rules use `check_type: pattern | structural | file-exists` — fully deterministic, no LLM involved. Rules requiring LLM judgment (`check_type: custom`) are `gate_blocking: false` and run only in the auditor as advisory findings. This preserves the 70/30 deterministic/LLM split.

| Layer | Deterministic | LLM (advisory) |
|-------|--------------|-----------------|
| General | 13 gate-blocking | 13 auditor-only |
| Vulcan | 19 gate-blocking | 3 auditor-only |
| **Total** | **32** | **16** |

## Goal

Add a standards enforcement system to AID that is selectable at init, enforced in gates (deterministic only), evaluated in audits (full set), and surfaced in curator proposals.

## Scope

**In scope:**
- Standard definition files (`defaults/standards/general.yaml`, `vulcan.yaml`) — ALREADY CREATED
- Selection step in `/aid-init` → stored in `project.yaml → standards.active`
- New `standards_compliance` gate in `execution.yaml` (deterministic rules only)
- New audit category I) Standards Compliance in `auditor.md` (full set including custom)
- Standards hotspot detection in `curator.md`
- Standards context in agent dispatch prompts (`pipeline.md`)
- Self-reported violations in agent execution summary (`agent-core.md`)

**Out of scope:**
- Custom user-defined standard sets (future — users can create their own YAML)
- Per-file exclusion annotations (e.g., `# standards:ignore GEN-007`)
- CI integration (standards run inside AID pipeline, not GitHub Actions)
- Bash script for standards gate (`scripts/gates/standards-check.sh`) — defer to implementation EPIC

## Approach

### Option A: Integrated Standards (Recommended)

Standards are YAML rule files in `defaults/standards/`. Selection at init time, stored in `project.yaml`. Gate runs deterministic rules against `git diff`. Auditor runs full set against entire codebase. Curator detects systemic violations (3+ occurrences of same rule).

**Pros:**
- Single selection point (init) — no per-run config
- Inheritance model (`vulcan` extends `general`) — DRY
- Gate is 100% deterministic — no LLM flakiness
- Auditor provides full-codebase view beyond just the diff
- Curator auto-fixes S-effort standards violations

**Cons:**
- Adding new standard sets requires plugin update
- Rule YAML schema needs documentation

### Option B: External Standards (Reference-Only)

Standards defined externally (e.g., in project docs), agents instructed to follow them via CLAUDE.md. No gate, no auditor category — purely advisory.

**Pros:**
- Zero implementation effort
- Maximum flexibility

**Cons:**
- No enforcement — agents ignore standards when convenient
- No tracking or trend visibility
- No consistency across projects

### Decision

**Chosen:** Option A — Integrated Standards
**Rationale:** The entire value proposition is enforcement and tracking. Advisory-only standards (Option B) are already possible today and demonstrably insufficient.

## High-Level Steps

| # | Step | Description | Files | Effort |
|---|------|-------------|-------|--------|
| 1 | Standards YAML files | Review and finalize `general.yaml` (26 rules) and `vulcan.yaml` (22 rules) | `defaults/standards/general.yaml`, `defaults/standards/vulcan.yaml` | S (already created) |
| 2 | Init selection | Add standards profile selection to `/aid-init` + extend `project.yaml` template | `commands/aid-init.md` | S |
| 3 | Standards gate | Add `standards_compliance` gate to `execution.yaml` + curator auto-rules | `defaults/execution.yaml` | S |
| 4 | Auditor integration | Add category I) Standards Compliance (conditional, 15% weight) | `agents/auditor.md` | M |
| 5 | Curator integration | Standards hotspot pattern + `source_type: standards` proposals | `agents/curator.md` | S |
| 6 | Dispatch context | Add Standards Context block to agent dispatch prompts | `skills/pipeline.md` | S |
| 7 | Agent output | Add `Standards violations noted` to Execution Summary | `skills/agent-core.md` | S |
| 8 | Version bump + CHANGELOG | Bump to v2.6.0, update all 8 version locations | 8 files | S |

**Dependencies:** Steps 1→2→3 (sequential), Steps 4-7 (parallel after Step 3), Step 8 (after all).

## Detailed Changes

### Step 2: Init Selection (`commands/aid-init.md`)

After auto-detection, add:

```
### Standards Selection

After auto-detection completes, present the standards profile selection:

  (A) general — Universal development standards (recommended)
  (B) vulcan — Vulcan ecosystem standards (includes general)
  (C) none — No standards enforcement

Rules:
- Default: general (A) if PM does not respond
- vulcan inherits all general rules + adds ecosystem-specific rules
- none disables all standards enforcement
- On re-run: if standards key exists, show current and ask "Keep? (Y/N)"
```

Extend `project.yaml` template:

```yaml
standards:
  active: general|vulcan|none
  selected_at: "{ISO 8601}"
  overrides:
    disabled_rules: []
    severity_overrides: {}
```

### Step 3: Standards Gate (`defaults/execution.yaml`)

Add after `lint_pass`, before `type_check`:

```yaml
standards_compliance:
  description: "Project standards compliance check (deterministic rules only)"
  required: true
  type: deterministic
  when: "standards.active != 'none' in project.yaml"
  rule: "Load active standard set, run pattern/structural/file-exists rules against git diff"
  pass_criteria: "No gate_blocking violations found in diff"
```

Add curator auto-rules:

```yaml
always_approve:
  - { source_type: standards, effort: S }
always_defer:
  - { source_type: standards, effort: L }
```

### Step 4: Auditor (`agents/auditor.md`)

New category I) Standards Compliance (conditional):
- **Condition:** `project.yaml → standards.active != 'none'`
- **Scope:** Full codebase (not just diff) — detects systemic violations
- **Includes:** ALL rules (pattern + structural + custom/LLM)
- **Scoring:** Start 100, deduct per severity (critical: -15, high: -10, medium: -5, low: -2), cap 5 violations/rule
- **Weight:** 15% when active (Code 30→25%, Security 30→27%, Docs 25→23%)
- Update category count: 8→9, conditional list update

### Step 5: Curator (`agents/curator.md`)

- Phase 1: Read `standards_compliance` from audit report
- Phase 3: New pattern — "standards hotspot" (same rule violated 3+ times = systemic, auto-escalate to high)
- Phase 4: Proposals get `source_type: standards` + `standard_rule: "GEN-XXX"` fields

### Step 6: Dispatch Context (`skills/pipeline.md`)

Add item 7 to context assembly:

```
7. STANDARDS CONTEXT — when standards.active != 'none'
   - Load standard set, filter by agent role + project languages
   - Gate-blocking rules first (⚠ prefix)
   - Format as ## Standards section in dispatch prompt
```

### Step 7: Agent Output (`skills/agent-core.md`)

Add to Execution Summary block:

```
- Standards violations noted: {count}
```

## Standard Files Summary

### general.yaml (26 rules)

| Category | Rules | Gate-blocking | Auditor-only |
|----------|-------|--------------|--------------|
| Code Quality | GEN-001 to GEN-007 | 3 (001, 002, 007) | 4 (003-006) |
| Security | GEN-008 to GEN-012 | 3 (008, 010, 011) | 2 (009, 012) |
| Testing | GEN-013, 015, 016 | 1 (013) | 2 (015, 016) |
| Documentation | GEN-017 to GEN-019 | 2 (017, 018) | 1 (019) |
| Git | GEN-020 to GEN-023 | 3 (020, 022, 023) | 1 (021) |
| API | GEN-024 to GEN-026 | 0 | 3 (024-026) |
| Config | GEN-027 | 1 (027) | 0 |
| **Total** | **26** | **13** | **13** |

GEN-014 ("All tests pass") removed — duplicates `tests_pass` gate.

### vulcan.yaml (22 rules + 4 overrides)

| Category | Rules | Gate-blocking | Auditor-only |
|----------|-------|--------------|--------------|
| Type Safety (D-006) | VUL-001, 002 | 2 | 0 |
| Determinism (D-007) | VUL-003, 004 | 1 (003) | 1 (004) |
| Tenant Isolation | VUL-005, 006, 007 | 3 | 0 |
| Agent Framework | VUL-008, 009 | 2 | 0 |
| Security (D-010) | VUL-010, 011 | 1 (010) | 1 (011) |
| Architecture | VUL-012, 013 | 1 (012) | 1 (013) |
| Error Handling (D-013) | VUL-014, 015 | 2 | 0 |
| Naming | VUL-016, 017, 018 | 1 (016) | 2 (017, 018) |
| Config | VUL-019, 020 | 2 | 0 |
| Testing | VUL-021, 022 | 2 | 0 |
| **Total** | **22** | **19** | **3** |

**Overrides:** GEN-005 → critical, GEN-010 → critical, GEN-011 → critical, GEN-012 → critical

## Constraints

- Gate must be 100% deterministic — no `check_type: custom` rules in gate
- Custom rules run only in auditor (advisory, not blocking)
- Inheritance: `vulcan` extends `general` (loads general first, merges vulcan on top)
- Standards selection stored in `project.yaml` (user-editable, not locked)
- No breaking changes to existing gates or audit categories

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| False positives from pattern rules on non-code files | medium | low | Filter by `languages` field + standard glob patterns |
| Auditor weight redistribution breaks existing score baselines | low | medium | Weights only shift when standards are active; `none` = unchanged |
| Agents ignore Standards Context in dispatch prompt | medium | medium | Gate catches violations deterministically regardless of agent behavior |
| Too many gate-blocking rules slow down pipeline | low | low | Rules scan only `git diff`, not full codebase (auditor does full scan) |

## Success Criteria

- `/aid-init` on a new project offers standards selection (A/B/C)
- `project.yaml` contains `standards.active` after init
- Standards gate runs during GATES state and catches pattern violations
- Auditor report includes Standards Compliance category with score
- Curator generates proposals for systemic standards violations (3+ occurrences)
- Dispatched agents receive filtered standards in their prompt context
- All custom rules are auditor-only (no LLM in gate)

## Next Steps

- [ ] Create EPIC(s) from this plan: `/aid-plan --epic .aid-o/plans/P025-standards-enforcement-system.md`
- [ ] Review standard YAML files for rule completeness
- [ ] Implement integration changes (Steps 2-7)
- [ ] Version bump to v2.6.0

---

**Last Updated:** 2026-03-14
