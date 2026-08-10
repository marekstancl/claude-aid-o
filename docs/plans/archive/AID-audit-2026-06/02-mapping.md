---
audit: P041
phase: 2
artifact: enforcement-to-instruction-mapping
status: draft-pre-reconciliation
generated: 2026-06-01
source_plan: docs/plans/AID-P041-skill-instruction-audit.md
depends_on: 01-enforcement-inventory.md
---

# P041 Phase 2 — Enforcement-to-Instruction Mapping

For each Phase-1 enforcement (E01–E86), identifies the expected instruction
location via the heuristic anchor table, greps for the instructional anchor,
and assigns one of 5 verdicts with evidence.

**Verdicts:** ALIGNED · GAP (enforcement exists, instruction missing) · ORPHAN
(instruction exists, enforcement removed/not-wired) · CONTRADICTORY (both exist,
disagree) · UNREACHABLE (enforcement present but never triggered / dead path).

---

## Heuristic anchor table (17 rows — covers all 15 enforcement types)

| # | Enforcement type | Expected instruction location |
|---|---|---|
| 1 | FSM-precondition (orchestrator) | `skills/pipeline.md` (§1 transition table, §2–§7) |
| 2 | FSM-precondition (subagent output) | `agents/verifier.md` OR `skills/agent-protocol.md` |
| 3 | Hard-gate orchestration | `pipeline.md` §13 (line 1143) |
| 4 | Hard-gate pre-filter patterns | `defaults/policies/review-checkpoints.yaml` `pre_filter.fail_patterns[]` |
| 5 | Pre-filter regex | `defaults/pre-filter-rules.yaml` + `pipeline.md` §13 |
| 6 | Structural-check (compliance) | `pipeline.md` compliance section (§7) |
| 7 | Schema-validator (plan) | `skills/plan-writing.md` |
| 8 | Dispatch-wrapper | `pipeline.md` §4 "Dispatch Protocol (P040)" (line 464) |
| 9 | Command-orchestration-rule | `commands/<cmd>.md` OR `pipeline.md` |
| 10 | Hook-enforcement | `defaults/hooks/*` + `agent-protocol.md` git discipline |
| 11 | YAML-policy-driven (check-severity) | `pipeline.md` + `agent-protocol.md` |
| 12 | Template-shaped (verifier-output) | `agents/verifier.md` Output Format |
| 13 | Audit-log invariant | `agent-protocol.md` "P040 audit events" table (line ~253) |
| 14 | Skill-loaded-protocol | the skill itself |
| 15 | Agent-contract | `agents/<agent>.md` Output Format |
| 16 | Test-regression-gate | corresponding `scripts/tests/test-<thing>.sh` |
| 17 | Stack-gate-binding | relevant `defaults/execution-stacks/<lang>.yaml` |

**Cross-reference check:** all 15 enforcement-type categories from §Architecture
map to ≥1 row here (types 1–2 → rows 1–2; type 4 → rows 3/6; type 5 → rows 4/5;
type 6 → row 7; type 3 → row 8; type 7 → row 9; type 8 → row 10; type 9 → row 11;
type 10 → row 12; type 11 → row 13; type 12 → row 14; type 13 → row 15;
type 14 → row 16; type 15 → row 17). ✅

---

## Mapping table (all 86 enforcements)

| ID | Type | Expected instruction location | Verdict | Note |
|----|------|-------------------------------|---------|------|
| E01 | 1 | pipeline.md:53–57 transition table | ALIGNED | VALID_TRANSITIONS documented as transition table |
| E02 | 1 | pipeline.md:48 | ALIGNED | "verifies preconditions before allowing state changes" |
| E03 | 1 | pipeline.md:53 | ALIGNED | "plan.json exists, total_steps >= 1" |
| E04 | 1 | pipeline.md:54 | ALIGNED | increment covered by EXECUTE→GATES current_step rule |
| E05 | 1 | pipeline.md:54 | ALIGNED | `current_step >= total_steps` |
| E06 | 1 | pipeline.md:544, 613 | ALIGNED | gates_report `_generated_by` present requirement |
| E07 | 1 | pipeline.md:55 | ALIGNED | "gates_report.json with overall: pass" |
| E08 | 1 | pipeline.md:495 | ALIGNED | "Integration Review CP3 (ENFORCED v2.18.0+)" |
| E09 | 1 | pipeline.md:66 | ALIGNED | "--reason min 20 characters" |
| E75 | 1 | aid-run.md:343 | ALIGNED | "set-field rejects writes to done_phase" |
| E76 | 1 | pipeline.md:57, 747–752 | ALIGNED | done-advance review→release preconditions documented |
| E10 | 2 | verifier.md:71–73 + template | ALIGNED | verifier-output-step-N.md format documented |
| E11 | 2 | agent-protocol.md:197, 207 | ALIGNED | verifier_provenance listed as blocking check |
| E12 | 2 | agent-outputs.md NR 17 §4D | **CONTRADICTORY** | enforcement forces fail on "fabricated"; reflection reframes as timestamp-fragility false-positive (plan 4e) |
| E13 | 2 | verifier.md:72 + template | ALIGNED | CP3 `_generated_by` requirement documented |
| E73 | 2 | memory-mcp.md:96, 121, 240 | ALIGNED | "Validate Before Storing" + "Rejection Criteria" |
| E74 | 2 | memory-mcp.md:229–232 | ALIGNED | "N/A acceptable for non-code steps" |
| E14 | 3 | pipeline.md:413, 429 | ALIGNED | emit-dispatch start/complete documented |
| E15 | 3 | pipeline.md:476 (values only) | **GAP** | allowed focus *values* listed; the rejection-regex enforcement (malformed focus) is not instructed |
| E16 | 3 | (none) | **GAP** | nonce/flock concurrency guard — 0 instruction matches (internal, non-LLM-facing) |
| E17 | 3 | agent-protocol.md:259 | ALIGNED | `fsm_orphan_dispatch_fail` documented |
| E18 | 3 | (none) | **GAP** | `pending_file_malformed` fail-closed — 0 instruction matches |
| E19 | 4 | pipeline.md:40 + agent-protocol.md:186 | ALIGNED | scope validation documented |
| E20 | 4 | verifier-output-template.md:42 | **ORPHAN** | reclassified from CONTRADICTORY after verifier refutation: template names `verifier-output-cp4-curator.md` ("FSM does NOT enforce") but FSM enforces a **differently-named** file `verifier-output-cp4-curator-validation.md` → stale instruction filename, not a logical contradiction |
| E21 | 4 | agent-protocol.md:273 | ALIGNED | `cp4_glob_invalid` documented |
| E22 | 4 | pipeline.md (plan_ac_match) + check-severity | ALIGNED | plan_ac_match blocking check documented |
| E23 | 4 | pipeline.md:783 | ALIGNED | "compliance.json capturing 6 enforcement dimensions" |
| E24 | 4 | agent-protocol.md:282 | ALIGNED | streamlined_integration_review documented |
| E25 | 4 | agent-protocol.md:281 | ALIGNED | streamlined_abandoned documented |
| E68 | 4 | (none) | **GAP** | `{token}` resolver fail-loud — 0 instruction matches |
| E69 | 4 | pipeline.md:748 + CLAUDE.md version registry | ALIGNED | "aid-release.sh refuses release if done_phase != release" |
| E71 | 4 | (none in skills) | **GAP** | runtime dependency gate (bash/jq/yq) not surfaced in any skill (README-only) |
| E79 | 4 | aid-research.md:128, 184 | ALIGNED | command self-documents run_quality_gates |
| E83 | 4 | (none) | **GAP** | detached-HEAD hard-fail — internal guard, not instructed |
| E84 | 4 | (none) | **GAP** | sub-scripts executable check — internal guard |
| E85 | 4 | (none) | **GAP** | zero-phases error — error message is the only "instruction" |
| E86 | 4 | (none) | **GAP** | common.sh source-only guard — internal guard |
| E26 | 5 | pipeline.md:1178 | ALIGNED | "Regex scan against review-checkpoints.yaml fail_patterns[]" |
| E27 | 5 | pipeline.md §13 | ALIGNED | skip path documented |
| E28 | 5 | pre-filter-rules.yaml (self) | ALIGNED | rule registry is its own instruction |
| E29 | 5 | pipeline.md:1178 | ALIGNED | fail_patterns referenced |
| E30 | 6 | plan-writing.md | **GAP** | epic-to-json structural jq validation not surfaced to plan author |
| E31 | 6 | plan-writing.md | **GAP** | role 9-value enum not documented in plan-writing.md |
| E32 | 6 | plan-writing.md | **GAP** | plan.schema.json constraints (objective minLength:10, step id pattern, role enum) not surfaced to plan author |
| E33 | 6 | plan-writing.md (Implementation Steps) | ALIGNED | steps-section requirement documented |
| E34 | 6 | (none) | **GAP** | epic-id `E-` format not instructed in any skill |
| E35 | 7 | aid-run.md:42 (self) | ALIGNED | "Scripts WILL REFUSE to proceed" |
| E36 | 7 | aid-do.md:81 (self) | ALIGNED | Fast Mode fix loop documented |
| E37 | 7 | aid-plan.md:103 (self) | ALIGNED | CP1 docs-review dispatch documented |
| E80 | 7 | aid-research.md:104 (self) | ALIGNED | idempotency STOP documented |
| E81 | 7 | aid-status.md:123 (self) | ALIGNED | duplicate-reject documented |
| E82 | 7 | aid-status.md:177 (self) | ALIGNED | read-only invariant documented |
| E38 | 8 | aid-run.md:55 | ALIGNED | "git pre-commit hook independently verify done_phase" |
| E39 | 8 | aid-run.md:55 + pipeline.md:748 | ALIGNED | version-bump pre-push multi-layer defense documented |
| E40 | 9 | pipeline.md:843 + agent-protocol.md:197 | ALIGNED* | registry documented; *3 sub-entries UNREACHABLE — see below |
| E41 | 9 | pipeline.md:815 | ALIGNED | cmd_done_advance reads compliance failures |
| E42 | 9 | pipeline.md:815 | ALIGNED | "refuses" release on blocking failures |
| E43 | 9 | pipeline.md:304–309 | ALIGNED | standards profile loading + overrides documented |
| E70 | 9 | pipeline.md:849–862 | ALIGNED | promotion ceremony documented |
| E77 | 9 | pipeline.md:93 | ALIGNED | "--reflect flags 🔴 SYSTEMATIC if..." |
| E78 | 9 | permissions.yaml (self) | ALIGNED | autonomous denylist is its own policy instruction |
| E44 | 10 | verifier-output-template.md (self) + verifier.md:71 | ALIGNED | line-start format documented |
| E45 | 10 | step-verify-template.md (self) + pipeline.md:348 | ALIGNED | AC checklist format documented |
| E46 | 10 | templates (self) | ALIGNED | plan/run templates are their own shape spec |
| E47 | 11 | agent-protocol.md:253 | ALIGNED | P040 audit events table |
| E48 | 11 | agent-protocol.md:253–282 | ALIGNED | per-failure audit events documented |
| E49 | 11 | (none) | **GAP** | stage-log invalid-JSON handling not instructed (internal) |
| E72 | 11 | pipeline.md:450 | ALIGNED | fsm_precondition_repeated_fail_epic documented |
| E50 | 12 | agent-protocol.md:69 (self) | ALIGNED | AGENT OUTPUT block |
| E51 | 12 | agent-protocol.md:119 (self) | ALIGNED | Pre-Output Quality Check MANDATORY |
| E52 | 12 | agent-protocol.md:186 (self) | ALIGNED | Scope Enforcement |
| E53 | 12 | pipeline.md:272 (self) | ALIGNED | Dispatch Protocol non-negotiable |
| E54 | 12 | brainstorming.md (self) | ALIGNED** | **instruction present, NO out-of-band enforcement — Principle #5 anchor (drift occurred 7× in P041 brainstorm) |
| E55 | 13 | verifier.md:22 (self) | ALIGNED | verdict contract |
| E56 | 13 | gate-fixer.md:89 (self) | ALIGNED | forbidden_paths / no-circumvent |
| E57 | 13 | curator.md:121 / implementer.md:8 (self) | ALIGNED | output-format contracts |
| E58 | 13 | project-scanner.md:186 (self) | ALIGNED | qdrant-find-before-store |
| E59 | 13 | auditor.md:196 (self) | ALIGNED | audit assertion rules |
| E60 | 14 | run-all-tests.sh (self) | ALIGNED | runner self-documents |
| E61 | 14 | test-instruction-consistency.sh (self) | ALIGNED | meta-enforcement (alignment checker) |
| E62 | 14 | per-script test-*.sh (self) | ALIGNED | regression suites |
| E63 | 14 | test-plan-quality-enforcement.sh (self) | ALIGNED | P036 smoke test |
| E64 | 14 | test-cp1-grounding.sh (self) | ALIGNED | CP1 grounding smoke test |
| E65 | 15 | execution-stacks/*.yaml (self) | ALIGNED | gate definitions self-document |
| E66 | 15 | pipeline.md:587 | ALIGNED | run-all gate execution documented |
| E67 | 15 | pipeline.md:158, 306 (tech_stack) | ALIGNED | stack detection / tech_stack referenced |

**Instruction-side findings (not in E-inventory — instruction without live enforcement):**

| ID | Source instruction | Verdict | Note |
|----|--------------------|---------|------|
| O1 | agent-protocol.md:268 `dispatch_completed_late` | **ORPHAN** | "per-dispatch expected_duration_max comparison *(planned — not threaded through cmd_complete yet)*" — instruction documents an enforcement not wired |
| O2 | agent-protocol.md:272 `cp4_glob_evaluated` | **ORPHAN** | "*(planned — not yet emitted in v2.25.0)*" — audit-event-table entry with no backing emitter |

---

## Detailed evidence (non-ALIGNED findings)

### CONTRADICTORY

**E12 — provenance_aggregate "fabricated" forces fail**
- `command_run:` `grep -n 'provenance_aggregate\|fabricated' scripts/aid-fsm.sh`
- `output_excerpt:` `975: # ...has unverifiable _generated_by metadata, force overall=fail`; `980: provenance_aggregate: fabricated — at least one verifier output has unverifiable _generated_by metadata`
- `command_run:` `grep -rni 'provenance_aggregate' skills/ agents/`
- `output_excerpt:` `(0 matches — the "fabricated" label is not surfaced in any skill/agent)`
- **Verdict basis:** the enforcement hard-fails on "fabricated", but the term conflates *unverifiable* with *fraudulent*. P041 plan §4e (NR 17 §4D reframing) documents the original "fabricated provenance hard block" as a **timestamp-fragility false-positive** (P040 own ship Step 7 timing slip, not actual fabrication). Enforcement semantics and the reflection record disagree → CONTRADICTORY.

### ORPHAN (reclassified from CONTRADICTORY)

**E20 — CP4 template names a stale/wrong file**
- `command_run:` `grep -n 'FSM does NOT enforce\|cp4' defaults/templates/verifier-output-template.md`
- `output_excerpt:` `42: D. CP4 curator → verifier-output-cp4-curator.md (classification: FULL_REVIEW; FSM does NOT enforce)`
- `command_run:` `grep -n 'missing_cp4_curator_validation\|fsm_check_cp4' scripts/aid-fsm.sh`
- `output_excerpt:` `330: local cp4_file=".../verifier-output-cp4-curator-validation.md"`; `354: die "missing_cp4_curator_validation"`
- **Verdict basis (post-verifier):** Phase-2 adversarial verifier REFUTED the CONTRADICTORY call. The two statements reference **different filenames** — template says `verifier-output-cp4-curator.md` "FSM does NOT enforce", while FSM enforces presence of `verifier-output-cp4-curator-validation.md`. So it is not a logical contradiction but a **stale instruction**: the template documents an outdated filename and an outdated "not enforced" claim. Reclassified ORPHAN (instruction exists, the enforcement it describes changed underneath it). The verifier noted this is "arguably a worse documentation bug" — flag to Phase 5.

### UNREACHABLE

**E40-sub — 3 advisory checks with no evaluator**
- `command_run:` `for c in epic_compliance_coverage_ratio ai_mechanics_friction_ratio iteration_density_per_step; do grep -c "$c" scripts/aid-fsm.sh; done`
- `output_excerpt:` `0` / `0` / `0` (zero evaluator code in aid-fsm.sh)
- `command_run:` `grep -rn 'epic_compliance_coverage_ratio\|ai_mechanics_friction_ratio\|iteration_density_per_step' scripts/`
- `output_excerpt:` `(only check-severity.yaml registry + no compute path; not written to compliance.json by aid-fsm.sh or aid-compliance-backfill.sh)`
- `command_run:` `grep -n 'coverage_ratio\|friction_ratio\|iteration_density' skills/pipeline.md`
- `output_excerpt:` `845–847: | epic_compliance_coverage_ratio | advisory | — | Awaiting empirical track record |` (×3)
- **Verdict basis:** these 3 checks are registered (E40) + documented in pipeline.md as advisory, but **no code ever computes them** → the severity classification can never fire = UNREACHABLE (dead registry entries). Contrast `memory_substantive`/`dod_present`, which DO have evaluators at aid-fsm.sh:876/890 (intentionally null pending Session B/C = ALIGNED, not dead).

### ORPHAN

**O1/O2 — planned-not-wired audit events**
- `command_run:` `grep -n 'planned\|not.*wired\|not yet\|not threaded' skills/agent-protocol.md`
- `output_excerpt:` `268: dispatch_completed_late ... *(planned — not threaded through cmd_complete yet)*`; `272: cp4_glob_evaluated ... *(planned — not yet emitted in v2.25.0)*`
- **Verdict basis:** instruction (audit-events table) documents enforcements that are explicitly not implemented → instruction exists, enforcement absent = ORPHAN. (Honest mitigation: both are annotated "(planned)" so this is disclosed drift, not silent.)

### GAP (representative evidence)

**E15 — focus allowlist rejection not instructed**
- `command_run:` `grep -rniE 'cp\[1-4\]|allowed pattern|focus.*regex|allowlist' skills/ agents/ commands/`
- `output_excerpt:` `(0 matches)` — the defensive regex `^cp[1-4](-step-[0-9]+|-[a-z][a-z0-9-]*)?$` that *rejects* malformed focus has no instructional counterpart; only the allowed *values* are listed (pipeline.md:476).

**E30/E31/E32 — plan schema constraints not surfaced**
- `command_run:` `grep -niE 'role.*enum|minLength|epic_id|required field' skills/plan-writing.md`
- `output_excerpt:` `(no matches for role enum / objective minLength / required fields)` — the plan author is not told the 9-role enum, `objective minLength:10`, or `step id ^step_[a-z0-9_]+$` that the generator/schema enforces downstream.

**E16/E18/E49/E68/E83/E84/E85/E86 — internal guards (acceptable GAPs)**
- `command_run:` `grep -rniE 'nonce|flock|pending_file_malformed|unknown placeholder|detached HEAD|source.*not.*execute' skills/ agents/ commands/`
- `output_excerpt:` `(0 matches)` — these are defense-in-depth / hygiene guards not in the LLM-facing decision surface. Classified GAP but **non-material** (no LLM action depends on them; see analysis).

---

## Summary statistics

**Coverage:** 86 / 86 Phase-1 enforcements mapped = **100%** (≥80% PM-GATE-A floor ✅).
Plus 2 instruction-side findings (O1, O2).

| Verdict | Count | % of 86 | IDs |
|---------|-------|---------|-----|
| ALIGNED | 70 | 81.4% | (all not listed below) |
| GAP | 14 | 16.3% | E15, E16, E18, E30, E31, E32, E34, E49, E68, E71, E83, E84, E85, E86 |
| ORPHAN | 1 | 1.2% | E20 (+ O1, O2 instruction-side) |
| CONTRADICTORY | 1 | 1.2% | E12 |
| UNREACHABLE | 3* | (sub-entry) | E40 sub-entries (coverage_ratio, friction_ratio, iteration_density) |

70 + 14 + 1 + 1 = 86 enforcements classified. \* UNREACHABLE counts 3 dead registry
checks *inside* E40 (E40 itself is ALIGNED for its live entries), so it does not
add to the 86 total. O1/O2 are instruction-side ORPHANs (planned-not-wired audit
events; no E-inventory enforcement).

**Verdict reclassification (post-reconciliation):** E20 moved CONTRADICTORY→ORPHAN
after the Phase-2 adversarial verifier refuted the contradiction (it is a stale
filename in the template, not a logical disagreement). All 5 verdict types still
have ≥1 example (ALIGNED, GAP, ORPHAN, CONTRADICTORY=E12, UNREACHABLE).

**All 5 verdict types have ≥1 example.** ✅ (Step 2 AC #2 satisfied)

### GAP materiality split (for Phase 5 triage)

- **Material GAPs (4)** — LLM-facing, drift-prone, Principle #5 relevant:
  `E15` (focus regex), `E30/E31/E32` (plan schema constraints unsurfaced to plan author).
- **Non-material GAPs (10)** — internal hygiene/defense-in-depth guards no LLM
  decision depends on: E16, E18, E34, E49, E68, E71, E83, E84, E85, E86.

### Structural observation (feeds Principle #5)

Type-12 (skill-loaded-protocol) enforcements are **self-referential**: the
"enforcement" and the "instruction" are the same artifact. They are trivially
ALIGNED, but several have **no out-of-band enforcement** backing them. `E54`
(brainstorming.md RULE 9-12) is the empirical anchor — the instruction exists,
nothing mechanically enforces it, and drift occurred 7× during the P041
brainstorm itself. This is the core evidence for candidate Principle #5
("Enforcement without Instruction is Cargo Cult") **and its inverse**
("Instruction without Enforcement drifts").

---

## Reconciliation (adversarial agent pass)

Independent `aid-orchestrator:verifier` dispatched to REFUTE 5 verdicts (each
told to default to "refuted" if evidence was weak): CLAIM 1 = UNREACHABLE trio,
CLAIM 2 = E20 CONTRADICTORY, CLAIM 3 = E15 GAP, CLAIM 4 = E30/31/32 GAP,
CLAIM 5 = E12 CONTRADICTORY.

**Result: 4 of 5 CONFIRMED, 1 REFUTED.**

- **CONFIRMED — CLAIM 1 (UNREACHABLE):** `grep -rn` across `scripts/` → 0 matches
  for the 3 ratio checks; they exist only in check-severity.yaml + pipeline.md +
  agent-protocol.md docs, never computed. Dead registry entries.
- **CONFIRMED — CLAIM 3 (E15 GAP):** regex + rejection rule live only in
  aid-emit-dispatch.sh:80-81; instruction layer lists allowed values, never the
  rejection.
- **CONFIRMED — CLAIM 4 (E30/31/32 GAP):** plan-writing.md never surfaces
  `objective minLength:10` or `^step_[a-z0-9_]+$`; role values appear at line 278
  but not as the binding schema enum.
- **CONFIRMED — CLAIM 5 (E12 CONTRADICTORY):** force-fail exists at aid-fsm.sh:978;
  `provenance_aggregate` = 0 occurrences in skills/agents (`fabricated` appears 3×
  but in unrelated contexts). Substantive gap holds; minor wording correction
  applied (the term does appear, just not for this mechanism).
- **REFUTED — CLAIM 2 (E20):** the template note and the FSM enforcement target
  **different filenames** (`verifier-output-cp4-curator.md` vs
  `verifier-output-cp4-curator-validation.md`), so it is a stale-instruction /
  naming-mismatch bug, not a logical contradiction. **Action taken:** E20
  reclassified CONTRADICTORY→ORPHAN above; evidence block updated.

The refutation is recorded, not overridden — it improved the verdict quality
(CONTRADICTORY would have over-stated the finding). No other verdict changed.
