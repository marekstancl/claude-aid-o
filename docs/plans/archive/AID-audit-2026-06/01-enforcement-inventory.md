---
audit: P041
phase: 1
artifact: enforcement-inventory
status: draft-pre-reconciliation
generated: 2026-06-01
source_plan: docs/plans/AID-P041-skill-instruction-audit.md
---

# P041 Phase 1 — Enforcement Inventory

Flat list of every enforcement mechanism in the `aid-orchestrator` plugin
distribution, with `file:line` anchor, short description, and one of the 15
enforcement types from the plan §Architecture taxonomy.

**Method:** Orchestrator grep-guided source pass across 7 directory groups
(`scripts/`, `scripts/lib/`, `scripts/gates/`, `scripts/tests/`, `defaults/`
+ 6 subdirs, `skills/`, `agents/`, `commands/`), followed by an adversarial
independent-agent reconciliation pass (see §Reconciliation).

**Enforcement type legend (15 categories):**
1 FSM-precondition · 2 FSM-precondition (subagent output) · 3 Dispatch-wrapper ·
4 Structural-check · 5 Pre-filter-regex · 6 Schema-validator · 7 Command-orchestration-rule ·
8 Hook-enforcement · 9 YAML-policy-driven · 10 Template-shaped · 11 Audit-log invariant ·
12 Skill-loaded-protocol · 13 Agent-contract · 14 Test-regression-gate · 15 Stack-gate-binding

---

## Inventory table

| ID | file:line | Description | Type |
|----|-----------|-------------|------|
| E01 | `scripts/aid-fsm.sh:23` | `VALID_TRANSITIONS` whitelist of `FROM:TO` state pairs; any unlisted transition rejected by `is_valid_transition` (line 45) | 1 FSM-precondition |
| E02 | `scripts/aid-fsm.sh:1049` | `check_preconditions()` dispatcher — runs AFTER whitelist, BEFORE state update; returns 1 to abort transition | 1 FSM-precondition |
| E03 | `scripts/aid-fsm.sh:1059` | READY→EXECUTE precondition: `plan.json` exists + `total_steps >= 1` (PRE-FLIGHT must have run) | 1 FSM-precondition |
| E04 | `scripts/aid-fsm.sh:1074` | EXECUTE→EXECUTE (increment): more steps must remain | 1 FSM-precondition |
| E05 | `scripts/aid-fsm.sh:1085` | EXECUTE→GATES precondition: all steps must be completed | 1 FSM-precondition |
| E06 | `scripts/aid-fsm.sh:1102` | EXECUTE→GATES: `gates_report.json` must exist with `_generated_by` field (`gates_no_generated_by` reason; closes AID-005 hand-written report bypass) | 1 FSM-precondition |
| E07 | `scripts/aid-fsm.sh:1173` | GATES→DONE precondition: `gates_report.json` `overall == pass` | 1 FSM-precondition |
| E08 | `scripts/aid-fsm.sh:1137` | Session B CP3 precondition: `verifier-output-cp3-*` file presence + valid `_generated_by` before EXECUTE→GATES | 1 FSM-precondition |
| E09 | `scripts/aid-fsm.sh:440` | `--force` requires `--reason` with ≥20 chars (force-override audit floor) | 1 FSM-precondition |
| E10 | `scripts/aid-fsm.sh:720` | CP2 per-step: every `step-*-verify.md` must have matching `verifier-output-step-N.md` with `^_generated_by:` + `^classification:` | 2 FSM-precondition (subagent output) |
| E11 | `scripts/aid-fsm.sh:614` | `verify_provenance()` — cross-references verifier output `_generated_by`/`_generated_at` vs timeline.jsonl (subagent mode) or git SHA (inline mode) | 2 FSM-precondition (subagent output) |
| E12 | `scripts/aid-fsm.sh:975` | `provenance_aggregate == fabricated` → force `overall: fail` with explanation note (≥1 unverifiable verifier output) | 2 FSM-precondition (subagent output) |
| E13 | `scripts/aid-fsm.sh:758` / `:772` | CP3 code-review + security: `verifier-output-cp3-{focus}.md` must have `^_generated_by:` to count as dispatched | 2 FSM-precondition (subagent output) |
| E14 | `scripts/aid-emit-dispatch.sh:48` | `cmd_start` — emits `verifier_dispatch_start` audit event + appends pending-dispatches.jsonl ledger line | 3 Dispatch-wrapper |
| E15 | `scripts/aid-emit-dispatch.sh:80` | `--focus` allowlist regex `^cp[1-4](-step-[0-9]+\|-[a-z][a-z0-9-]*)?$` — rejects malformed focus (HIGH-1 injection defense) | 3 Dispatch-wrapper |
| E16 | `scripts/aid-emit-dispatch.sh:94` | Nonce + flock on `pending-dispatches.jsonl` — prevents duplicate/colliding same-focus starts | 3 Dispatch-wrapper |
| E17 | `scripts/aid-fsm.sh:169` | `fsm_check_orphan_dispatches` — refuses increment/transition if pending start has no matching complete (`missing_dispatch_complete`) | 3 Dispatch-wrapper |
| E18 | `scripts/aid-fsm.sh:209` | Orphan backstop: malformed `pending-dispatches.jsonl` → `die "pending_file_malformed"` (fails closed) | 3 Dispatch-wrapper |
| E19 | `scripts/gates/scope-check.sh:30` | Diff every changed file (vs base_commit) against `allowed_paths` glob patterns; any out-of-scope file → `exit 1` | 4 Structural-check |
| E20 | `scripts/aid-fsm.sh:330` | `fsm_check_cp4` — `verifier-output-cp4-curator-validation.md` presence required (`missing_cp4_curator_validation`) | 4 Structural-check |
| E21 | `scripts/aid-fsm.sh:310` | CP4 glob `cp4_production_paths` malformed ERE → `die "cp4_glob_invalid"` (CP3-security fail-closed) | 4 Structural-check |
| E22 | `scripts/aid-plan-diff.sh:12` | plan_ac_match gate: ≥1 plan AC absent from verify evidence → `exit 1` | 4 Structural-check |
| E23 | `scripts/aid-fsm.sh:707` | `evaluate_compliance_checks` / `write_compliance_json` — aggregates branch_correct, execution_yaml_present, gates_generated_by, plan_ac_match, verifier_outputs into compliance.json | 4 Structural-check |
| E24 | `scripts/aid-fsm.sh:362` | `fsm_check_streamlined_integration_review` — streamlined_mode requires cp3-code-review + cp3-security + gates_report (`streamlined_integration_review`) | 4 Structural-check |
| E25 | `scripts/aid-fsm.sh:400` | `fsm_check_streamlined_abandoned` — streamlined_mode + timeline `<3` events → `die "streamlined_abandoned"` (NR 12 SOUSTO P009 anchor) | 4 Structural-check |
| E26 | `scripts/aid-prefilter.sh:80` | `fail_rules` application — any security-sensitive regex match → `exit 20` FAIL (security verifier mandatory) | 5 Pre-filter-regex |
| E27 | `scripts/aid-prefilter.sh:65` | `skip_rules` — docs/config-only diffs match → `exit 0` SKIP (no LLM dispatch) | 5 Pre-filter-regex |
| E28 | `defaults/pre-filter-rules.yaml:15` | `fail_rules[]` pattern registry (exec/eval, shell=True, hardcoded secret, shell/SQL injection, dangerous HTML, unsafe deserialize, dynamic import, regex bypass) | 5 Pre-filter-regex |
| E29 | `defaults/policies/review-checkpoints.yaml:34` | `pre_filter.fail_patterns[]` with per-pattern severity (critical/high/medium) | 5 Pre-filter-regex |
| E30 | `scripts/aid-epic-to-json.sh:711` | Step 14 structural jq validation of generated plan.json against plan.schema.json critical requirements | 6 Schema-validator |
| E31 | `scripts/aid-epic-to-json.sh:63` | `validate_role()` — role must be in 9-value enum (matches plan.schema.json) | 6 Schema-validator |
| E32 | `defaults/templates/plan.schema.json:7` | JSON Schema: `required: [epic_id, version, steps, dependencies]`, step id `pattern ^step_[a-z0-9_]+$`, role enum, objective `minLength: 10`, model enum | 6 Schema-validator |
| E33 | `scripts/aid-plan-to-epic.sh:142` | EPIC generation: plan must contain a recognizable steps section header, else `error_exit` | 6 Schema-validator |
| E34 | `scripts/aid-queue-add.sh:55` | epic-id format validation (must start with `E-`) | 6 Schema-validator |
| E35 | `commands/aid-run.md:42` | FSM mechanically enforced — "Scripts WILL REFUSE to proceed if preconditions are not met" | 7 Command-orchestration-rule |
| E36 | `commands/aid-do.md:81` | Fast Mode: pre-filter match → immediate FAIL; verifier FAIL + fix_loop_eligible → gate-fixer, max 2 iterations | 7 Command-orchestration-rule |
| E37 | `commands/aid-plan.md:103` | CP1: dispatch verifier `docs-review` on written plan; `verifier_dispatch_start` event logged before `Agent()` | 7 Command-orchestration-rule |
| E38 | `defaults/hooks/pre-commit:29` | Blocks commit when FSM in DONE/review or READY state (`exit 1`) | 8 Hook-enforcement |
| E39 | `defaults/hooks/pre-push:39` | Blocks push if feat:/fix: commits since last tag without a version bump (`exit 1`) | 8 Hook-enforcement |
| E40 | `defaults/check-severity.yaml:16` | Severity registry: per-check `blocking` vs `advisory`; 4 blocking (verifier_provenance, gates_generated_by, plan_ac_match, + P040 entries), rest advisory | 9 YAML-policy-driven |
| E41 | `scripts/aid-fsm.sh:508` | `cmd_done_advance` reads check-severity → enriches compliance failures with severity; only `blocking` failures refuse review→release | 9 YAML-policy-driven |
| E42 | `scripts/aid-fsm.sh:815` (via pipeline.md) | `cmd_done_advance review release` reads `compliance.json failures[]` and refuses release on blocking failures | 9 YAML-policy-driven |
| E43 | `defaults/standards/general.yaml:30` + `vulcan.yaml:19` | Code standards rules with per-rule severity; vulcan profile escalates GEN-005/010/011/012 to critical (verifier-enforced context) | 9 YAML-policy-driven |
| E44 | `defaults/templates/verifier-output-template.md:30` | `_generated_by:`/`classification:`/`verdict:` MUST be at line-start (grep `^`-anchored); FSM rejects otherwise | 10 Template-shaped |
| E45 | `defaults/templates/step-verify-template.md:44` | Acceptance Criteria checklist format (`- [x]`/`- [ ]` per plan.json step.dod) consumed by plan_ac_match | 10 Template-shaped |
| E46 | `defaults/templates/plan.md` + `run-*.md` (4) | Plan + run templates shape the structure FSM/generators expect | 10 Template-shaped |
| E47 | `scripts/aid-audit-log.sh:26` | `cmd_append` — atomic `>>` append to audit-log.jsonl; failure non-fatal ("must never abort primary FSM operation", line 90) | 11 Audit-log invariant |
| E48 | `scripts/aid-fsm.sh:349` (et al.) | `fsm_emit_audit_log` — emits `cp4_missing_fail`, `streamlined_*_fail`, etc. to audit log on precondition failures | 11 Audit-log invariant |
| E49 | `scripts/lib/aid-stage-log.sh:49` | Invalid JSON → writes `log_error` event instead, never blocks pipeline | 11 Audit-log invariant |
| E50 | `skills/agent-protocol.md:69` | Every agent output MUST end with `# AGENT OUTPUT` YAML block | 12 Skill-loaded-protocol |
| E51 | `skills/agent-protocol.md:119` | Pre-Output Quality Check (MANDATORY) — lint before returning | 12 Skill-loaded-protocol |
| E52 | `skills/agent-protocol.md:186` | Scope Enforcement: agent MUST NOT modify files outside `allowed_paths` | 12 Skill-loaded-protocol |
| E53 | `skills/pipeline.md:272` | Agent Dispatch Protocol (non-negotiable): verbatim plan content, never "read the plan" | 12 Skill-loaded-protocol |
| E54 | `skills/brainstorming.md` RULE 9-12 | Validate-then-verify cycle for brainstorm section drafts (the protocol P041 found systematically unenforced) | 12 Skill-loaded-protocol |
| E55 | `agents/verifier.md:22` | Verdict contract: PASS \| FAIL \| PASS_WITH_NOTES, always include evidence | 13 Agent-contract |
| E56 | `agents/gate-fixer.md:89` | NEVER modify `forbidden_paths`; MUST NOT circumvent gate check (line 94) | 13 Agent-contract |
| E57 | `agents/curator.md:121` / `agents/implementer.md:8` | Output Format contracts; implementer/verifier MUST follow agent-protocol.md Output Format exactly | 13 Agent-contract |
| E58 | `agents/project-scanner.md:186` | MUST qdrant-find before every qdrant-store (dedup); summary MUST be ≥20 words | 13 Agent-contract |
| E59 | `agents/auditor.md:196` | Audit assertion rules: file description in first 5 lines, no dev-marker comments, refs must resolve | 13 Agent-contract |
| E60 | `scripts/tests/run-all-tests.sh:49` | Test runner — discovers all `test-*.sh`, `exit 1` if any suite fails | 14 Test-regression-gate |
| E61 | `scripts/tests/test-instruction-consistency.sh:5` | Meta-enforcement: verifies markdown instruction files (pipeline.md, aid-run.md, orchestration.yaml) match aid-fsm.sh reality (states, preconditions) | 14 Test-regression-gate |
| E62 | `scripts/tests/test-fsm.sh` / `test-run-gates.sh` / `test-scope-check.sh` / `test-prefilter` (via others) | Per-script regression suites locking enforcement behavior | 14 Test-regression-gate |
| E63 | `scripts/tests/test-plan-quality-enforcement.sh:3` | P036 plan-quality layers smoke test | 14 Test-regression-gate |
| E64 | `scripts/tests/test-cp1-grounding.sh:3` | CP1 grounding sub-checks 17a–17d smoke test | 14 Test-regression-gate |
| E65 | `defaults/execution-stacks/{bash,go,python,rust,typescript}.yaml:1` | Per-stack `gates:` with `command` + `required_when` — language-bound gate definitions | 15 Stack-gate-binding |
| E66 | `scripts/aid-run-gates.sh:117` | `run_all_gates` reads execution.yaml `gates`, runs each, requires state==GATES (line 158), writes gates_report.json with `_generated_by` | 15 Stack-gate-binding |
| E67 | `scripts/lib/aid-init-execution-yaml.sh:52` | Stack auto-detection (markers: pyproject.toml→python, >5 .sh→bash, etc.) → selects which stack gates bind | 15 Stack-gate-binding |
| E68 | `scripts/aid-run-gates.sh:36` | Gate command `{token}` placeholder resolver — unknown token → fail-loud `exit 1` (no silent pass-through) | 4 Structural-check |
| E69 | `scripts/aid-release.sh:101` | Release blocked unless FSM state DONE with done_phase set; version-file registry sync enforced | 4 Structural-check |
| E70 | `scripts/aid-promote-checks.sh:9` | Advisory→blocking promotion governance: ≥5 clean EPICs + force_override_rate <0.05; promotion via `aid-fsm.sh promote-check --reason ≥20 chars` | 9 YAML-policy-driven |
| E71 | `scripts/aid-check-deps.sh:60` + `scripts/lib/common.sh:67` | Runtime dependency gate: bash 4.0+, git, jq, yq (mikefarah) required → `exit 1` if missing | 4 Structural-check |
| E72 | `scripts/aid-fsm.sh:107` | `fsm_count_recent_fails` + repeated-fail detection → `fsm_precondition_repeated_fail` event + Telegram alert (×N) | 11 Audit-log invariant |
| E73 | `skills/memory-mcp.md:240` | Controller validates every agent `memory_writes` block (≥20-word summary, source_file glob-exists, ≥3 tags, ≥3-line code_example); on failure REJECTS output + re-dispatches | 2 FSM-precondition (subagent output) |
| E74 | `skills/memory-mcp.md:264` | `memory_writes: N/A` REJECTED when no reason given OR `files_changed` contains code extensions — forces substantive memory on code steps | 2 FSM-precondition (subagent output) |
| E75 | `scripts/aid-fsm.sh:1893` | `cmd_set_field` hard-rejects `set-field done_phase` (reserved — use `done-advance`); prevents bypassing review→release sub-phase machinery | 1 FSM-precondition |
| E76 | `scripts/aid-fsm.sh:1929` | `done-advance` sub-phase guard: refuses if current `done_phase` != expected `from_phase`, and refuses any `to_phase` not in `VALID_DONE_PHASES="review release"` | 1 FSM-precondition |
| E77 | `scripts/aid-compliance-report.sh:185` / `:506` | `--reflect` SYSTEMATIC detector — emits hard "STOP, investigate before next Session brainstorm" on force_override triple-condition OR any dimension ≥2 fails | 9 YAML-policy-driven |
| E78 | `defaults/policies/permissions.yaml:116` | `autonomous` preset `claude_code_deny` denylist (rm -rf, git push --force, reset --hard, clean -fd, DROP TABLE, DELETE FROM, kill -9, chmod 777) dual-written to settings.local.json | 9 YAML-policy-driven |
| E79 | `commands/aid-research.md:128` / `:184` | `run_quality_gates(chunk)` — 4 quality gates (min-value, dedup/merge, metadata, size); failing chunks REJECTED before Qdrant write | 4 Structural-check |
| E80 | `commands/aid-research.md:104` | Knowledge-acquisition idempotency gate: framework already active + sufficient depth + no topic → STOP (refuse redundant re-fetch) | 7 Command-orchestration-rule |
| E81 | `commands/aid-status.md:123` | Queue-add path REJECTS duplicate EPIC (already queued/running) before enqueue | 7 Command-orchestration-rule |
| E82 | `commands/aid-status.md:177` | `/aid-status` read-only invariant — never modifies files | 7 Command-orchestration-rule |
| E83 | `scripts/aid-json-to-run.sh:634` | Step 18 FSM auto-init hard-fails on detached HEAD (empty/`HEAD` branch) or unreadable HEAD SHA — refuses unanchorable base_commit | 4 Structural-check |
| E84 | `scripts/aid-auto-pipeline.sh:82` | Pre-flight gate: all 4 sub-scripts must exist AND be executable (`-x`), else `error_exit ... 2` — refuses partial pipeline | 4 Structural-check |
| E85 | `scripts/aid-auto-pipeline.sh:223` | Phase-detection gate: zero phases detected → `error_exit "Cannot detect any phases"` — refuses empty EPIC set | 4 Structural-check |
| E86 | `scripts/lib/common.sh:19` | Source-only guard — refuses direct execution ("must be sourced, not executed"), exit 1 | 4 Structural-check |

---

## Type coverage assertion (Step 1 AC #3)

| Type | Count | Example IDs |
|------|-------|-------------|
| 1 FSM-precondition | 11 | E01–E09, E75, E76 |
| 2 FSM-precondition (subagent output) | 6 | E10–E13, E73, E74 |
| 3 Dispatch-wrapper | 5 | E14–E18 |
| 4 Structural-check | 14 | E19–E25, E68, E69, E71, E79, E83, E84, E85, E86 |
| 5 Pre-filter-regex | 4 | E26–E29 |
| 6 Schema-validator | 5 | E30–E34 |
| 7 Command-orchestration-rule | 6 | E35–E37, E80, E81, E82 |
| 8 Hook-enforcement | 2 | E38, E39 |
| 9 YAML-policy-driven | 7 | E40–E43, E70, E77, E78 |
| 10 Template-shaped | 3 | E44–E46 |
| 11 Audit-log invariant | 4 | E47–E49, E72 |
| 12 Skill-loaded-protocol | 5 | E50–E54 |
| 13 Agent-contract | 5 | E55–E59 |
| 14 Test-regression-gate | 5 | E60–E64 |
| 15 Stack-gate-binding | 3 | E65–E67 |

**All 15 types have ≥1 example entry.** ✅ (AC #3 satisfied)
**Total: 86 enforcements ≥ 30 floor.** ✅ (AC #1 satisfied, PM-GATE-A floor)

---

## Reconciliation (adversarial agent pass)

Independent `aid-orchestrator:verifier` agent dispatched with adversarial
"find what I missed" prompt, author-blind to the orchestrator's reasoning.
Agent swept 18 files end-to-end + grep-swept all 10 commands and remaining skills.

**Result: 14 genuine missed enforcements found (E73–E86), merged above.**

- **Missed-enforcement rate: 14 / 86 = 16.3%** — this **EXCEEDS the AC #4 ≤5% target.**
  The first orchestrator pass was strong on the FSM/gates/dispatch core but
  under-covered three areas: (a) `done_phase`/`done-advance` sub-phase machinery
  in aid-fsm.sh (E75, E76), (b) the controller-side memory_writes validation gate
  in memory-mcp.md (E73, E74), (c) command-surface + auxiliary-script structural
  gates (aid-research, aid-status, aid-json-to-run, aid-auto-pipeline, common.sh).
- No inventoried claim was found factually wrong by the agent (it double-checked
  the cross-plan grandfather gate line range — consistent).
- **Honest coverage caveat:** agent flagged un-swept areas where MORE enforcements
  likely exist — `scripts/tests/bats/*` (13 bats files incl. test-anti-fabrication,
  test-tiered-severity) and the remaining `defaults/templates/*` (run-* templates).
  Type-14 (test-regression-gate) is therefore **under-counted**; current inventory
  treats the test suite at suite granularity, not per-assertion. Flagged for PM:
  a dedicated bats pass would raise the type-14 count but is not needed to clear
  the ≥30 / all-15-types PM-GATE-A floor.

**Interpretation for PM-GATE-A:** the inventory comfortably clears the gate
floors (86 ≥ 30; all 15 types covered), but the 16.3% adversarial miss-rate is
itself a finding — it empirically supports the P041 thesis that enforcement is
spread wide and easy to under-track, and means the "universe" is likely >86 once
bats assertions are enumerated.

---

## Phase 1b — Deep second-pass addendum (E87–E177)

PM requested a second, deeper sweep of areas the first pass only grep-touched.
Three independent agents read end-to-end: (A) all 12 `scripts/tests/bats/*.bats`
(2307 lines), (B) the 3 large generation scripts + uncovered `aid-fsm.sh` regions
(cmd_init, increment-step, promote-check), (C) all configs/templates + remaining
skills + commands.

**Headline: the second pass roughly TRIPLED the count.** ~90 additional distinct
enforcements were found, none in the E01–E86 set. Revised universe ≈ **177**.
This is the single strongest piece of evidence for the audit thesis: the
enforcement layer is far larger and more scattered than even the reconciled
86 suggested — no single careful pass holds it all.

**Dedup note:** Agent A's bats findings largely *lock* (type-14 view) the same
source enforcements Agent B found in code; those are counted once at the source,
with the test noted as its regression gate. Genuinely test-only items (atomicity,
TZ=UTC orphan-margin pinning, coverage_mode emission) are listed separately.

### B1 — Plan/EPIC generation gates (`aid-epic-to-json.sh`, `aid-plan-to-epic.sh`, `aid-json-to-run.sh`)

| ID | file:line | Description | Type |
|----|-----------|-------------|------|
| E87 | `aid-epic-to-json.sh:301` | **Dependency-cycle detection** via Kahn's topological sort (awk) — `CYCLE:` → `error_exit "Circular dependency detected"` | 4 |
| E88 | `aid-epic-to-json.sh:270` | Dependency-by-number: numeric dep to non-existent step → `error_exit` | 4 |
| E89 | `aid-epic-to-json.sh:277` | Dependency-by-role: role dep with no matching step → `error_exit` | 4 |
| E90 | `aid-epic-to-json.sh:284` | Unresolvable dependency token (neither number nor role) → `error_exit` | 4 |
| E91 | `aid-epic-to-json.sh:198` | Malformed Steps-table row (first field not `^[0-9]+$`) silently dropped (parse sanitization) | 4 |
| E92 | `aid-epic-to-json.sh:220` | `row_count == 0` → `error_exit "No valid steps found"` | 4 |
| E93 | `aid-epic-to-json.sh:751` | Step-14 sub-validators: dangling dep edge refs, parallel `minItems:2`, analysis_groups id-pattern/target-ref, gate enum | 6 |
| E94 | `aid-epic-to-json.sh:796,802,809,814` | I/O write guards (evidence dir, plan.json, state.yaml, EPIC copy) — each `\|\| error_exit` exit 3 | 4 |
| E95 | `aid-epic-to-json.sh:123` | EPIC-ID extraction failure (filename + H1 fallback) → `error_exit` | 4 |
| E96 | `aid-plan-to-epic.sh:66` | **Phase bounds check** — `phase < 1 \|\| phase > total` → `error_exit "out of range"` | 4 |
| E97 | `aid-plan-to-epic.sh:64` | Phase/total must be positive integers (2 regex guards) | 4 |
| E98 | `aid-plan-to-epic.sh:60` | EPIC-template-not-found → `error_exit` exit 2 ("Run /aid-init") | 4 |
| E99 | `aid-plan-to-epic.sh:80` | Plan frontmatter missing `id` → `error_exit` | 4 |
| E100 | `aid-plan-to-epic.sh:132` | Steps-section presence with **fence-aware** awk (quoted ``` AID syntax doesn't false-match) | 4 |
| E101 | `aid-plan-to-epic.sh:352` | Reversed dependency-range (`start > end`) rejection (WARN + skip) | 4 |
| E102 | `aid-plan-to-epic.sh:386` | Cross-phase dependency stripping (enforces phase isolation of deps) | 4 |
| E103 | `aid-json-to-run.sh:74` | Output-dir writability gate (`[[ ! -w ]]` → exit 3) | 4 |
| E104 | `aid-json-to-run.sh:81` | plan.json JSON-validity (`jq empty \|\| error_exit`) | 6 |
| E105 | `aid-json-to-run.sh:85` | `step_count == 0` → `error_exit "zero steps"` | 4 |
| E106 | `aid-json-to-run.sh:597` | **Atomic-write guard** (`mktemp`+`mv`, cleanup-on-failure, 3 exit-3 guards) | 4 |
| E107 | `aid-json-to-run.sh:635` | Step-18 base_commit guard — empty HEAD SHA → `error_exit` (companion to E83 detached-HEAD) | 1 |
| E108 | `aid-json-to-run.sh:591` | Output-filename length cap (>200 chars truncated) | 4 |

### B2 — `aid-fsm.sh` init + increment-step + promote-check gates

| ID | file:line | Description | Type |
|----|-----------|-------------|------|
| E109 | `aid-fsm.sh:1368` | **cmd_init uncommitted-changes guard** — `git diff` dirty → `die` (runs even in worktree mode) | 1 |
| E110 | `aid-fsm.sh:1343` | **cmd_init cross-EPIC branch-mismatch** — on `task/E-OTHER` → emit `fsm_branch_mismatch_detected` + `die` (AID-001) | 1 |
| E111 | `aid-fsm.sh:1263` | cmd_init duplicate-init rejection — state_file exists → exit 1 | 1 |
| E112 | `aid-fsm.sh:1322` | cmd_init not-in-git-repo → `die` | 1 |
| E113 | `aid-fsm.sh:1252` | cmd_init preflight git/jq missing → exit 1 (+ install hint) | 4 |
| E114 | `aid-fsm.sh:1335` | cmd_init branch checkout/create failure → `die` | 1 |
| E115 | `aid-fsm.sh:1727` | increment-step: `step-N-verify.md` must exist → exit 1 | 2 |
| E116 | `aid-fsm.sh:1739` | increment-step: verify file must contain `## Result: PASS` → exit 1 | 2 |
| E117 | `aid-fsm.sh:1750` | increment-step: AC-checklist `- [x]` ≥1 required → exit 1 | 2 |
| E118 | `aid-fsm.sh:1764` | increment-step: commit-reference (`[a-f0-9]{7,}`) required → exit 1 | 2 |
| E119 | `aid-fsm.sh:1775` | increment-step: `## Memory Used` + `## Memory Written` sections required (2 gates) | 2 |
| E120 | `aid-fsm.sh:1839` | **mid-EPIC plan.json hash-tampering check** — sha256 mismatch → `die "modified mid-EPIC"` | 11 |
| E121 | `aid-fsm.sh:1867` | Orphan-waiver force-coupling — waiver needs BOTH `--force` AND `--blocked-checks` (HIGH-2) | 1 |
| E122 | `aid-fsm.sh:1892` | cmd_set_field `state` reserved reject (companion to E75 done_phase) | 1 |
| E123 | `aid-fsm.sh:2153` | promote-check check_name regex `^[a-zA-Z_][a-zA-Z0-9_]*$` (path-traversal/metachar defense) | 4 |
| E124 | `aid-fsm.sh:2173` | promote-check `--reason` yq-injection escaping (P038 CRITICAL-1) | 4 |
| E125 | `aid-fsm.sh:2179` | promote-check check-not-in-registry → exit 1 | 9 |
| E126 | `aid-fsm.sh:2161,2199` | promote-check severity.yaml/yq missing + write-failure guards | 4 |
| E127 | `aid-fsm.sh:1252`(set-field state) / `:198` advance-to-gates | **advance-to-gates atomicity** — gate failure leaves EXECUTE, no half-committed transition | 1 |
| E128 | `aid-fsm.sh` `read_steps_array` | fsm-state.yaml steps[] precedence over legacy state.yaml (deterministic source-of-truth) | 4 |

### A — Test-locked behaviors (regression gates / test-only invariants)

| ID | file:line | Description | Type |
|----|-----------|-------------|------|
| E129 | `test-aid-fsm.bats:26` | PRE-FLIGHT branch matrix locked (HEAD=main auto-create; foreign task branch hard-fail; dirty tree reject) | 14 |
| E130 | `test-aid-fsm.bats:103` | **Grandfather clause** locked — `_generated_by` precondition bypassed when `created_at < AID_DEPLOY_DATE` | 14 |
| E131 | `test-aid-fsm.bats:346` | Orphan deadline math pinned to `TZ=UTC` (prevents host-TZ understatement) | 14 |
| E132 | `test-aid-fsm.bats:434` | CP4 production-touch scans full `base_commit..HEAD` range (not just last commit) | 14 |
| E133 | `test-aid-fsm.bats:619` | Streamlined compliance.json must emit `coverage_mode` + `skipped_dimensions` (non-silent reduced coverage) | 11 |
| E134 | `test-aid-fsm.bats:537` | Gate-runner rejects unless FSM==GATES (`AID_GATES_TRIGGERED_BY_FSM=1` sole bypass) | 15 |
| E135 | `test-plan-ac-diff.bats:26` | plan-diff verification_pattern types: `must_contain`/`must_not_exist`/`cmd`+`expected_exit`; Fast Mode exempt (exit 2) | 6 |
| E136 | `test-aid-emit-dispatch.bats:72` | `--expected-duration-max` clamped to 1800s ceiling | 4 |
| E137 | `test-aid-emit-dispatch.bats:94` | `complete` with non-existent output_file → exit 2, start entry NOT cleared (anti-fabrication) | 11 |
| E138 | `test-aid-prefilter.bats:50` | Pre-filter defaults to RUN on empty/ambiguous diff (fail-toward-review, never SKIP on doubt) | 5 |

### C1 — Config-policy enforcement (`orchestration.yaml`, `execution.yaml`, `integrations.yaml`, `permissions.yaml`)

| ID | file:line | Description | Type |
|----|-----------|-------------|------|
| E139 | `orchestration.yaml:22` | `dispatch.strategy: sequential`, `max_parallel: 1` — hard cap of one agent at a time | 9 |
| E140 | `orchestration.yaml:33` | `timeline_window_seconds: 60` — verifier `_generated_by` must match dispatch event within ±60s | 11 |
| E141 | `orchestration.yaml:37` | `escalation.max_per_session: 3` — hard-stop counter | 9 |
| E142 | `orchestration.yaml:101` | `release.skip_when` — refuse bump/tag when no new CHANGELOG version | 9 |
| E143 | `orchestration.yaml:108` | `skill_conflicts` deny list (superpowers brainstorming/writing-plans/executing-plans) | 9 |
| E144 | `execution.yaml:39,48` | `scope_check.max_retries: 0` + `plan_diff.max_retries: 0` — these gates never retry (immediate hard fail) | 9 |
| E145 | `execution.yaml:26` | `docs_updated` deterministic gate — API-path change without docs → exit 1 | 5 |
| E146 | `execution.yaml:123` | `budget.max_llm_cost_per_epic_usd: 50` — cost ceiling → HARD STOP escalation | 9 |
| E147 | `execution.yaml:135` | `quality_thresholds` — todo:0, security_high:0, coverage:80, review:7 | 9 |
| E148 | `execution.yaml:158` | `escalation_triggers` HARD STOP set (security CRITICAL, budget, conflicting outputs, no-output) | 9 |
| E149 | `execution.yaml:209` | `not_acceptable` list (hardcoded creds, disabled security, forbidden-path, console.log, empty catch, untracked TODO) | 9 |
| E150 | `execution.yaml:219` | `curator_auto_rules` — always_defer architecture/standards-L; always_approve dx/security-high/docs | 9 |
| E151 | `execution.yaml:106` | `retry.max_attempts: 3` then `on_failure: escalate` | 9 |
| E152 | `execution.yaml:238` | `cp4_production_paths` ERE deciding CP4 trigger | 5 |
| E153 | `integrations.yaml:51` | Memory rejection thresholds (summary ≥20 words, code 3–15 lines, ≥3 tags) | 6 |
| E154 | `integrations.yaml:67` | `search.min_score: 0.4` — below-floor results dropped | 9 |
| E155 | `integrations.yaml:101` | Knowledge `dedup_threshold: 0.85` / `merge_threshold: 0.70` | 9 |
| E156 | `integrations.yaml:40` | Scanner per-scan entry budgets (full 150 / incremental 50 / refactor 100) | 9 |
| E157 | `permissions.yaml:133` | `role_overrides` capability scoping — only release gets git tag/push; only security gets audit tools | 13 |
| E158 | `permissions.yaml:107,40` | YELLOW eco-admin tools not whitelisted; destructive tools (vulcan-delete, delete_file) excluded | 9 |

### C2 — Agent contracts (`role-cards.md`) + skill protocols + command guards + templates

| ID | file:line | Description | Type |
|----|-----------|-------------|------|
| E159 | `role-cards.md:357` | section-review MANDATORY citation rule — finding without `file:line` is INVALID, dropped/downgraded | 12 |
| E160 | `role-cards.md:389` | cross-section-review citation rule — uncitable → `severity: low`; fixed enum, no invented labels | 12 |
| E161 | `role-cards.md:92` | frontend Visual Anchoring — `visual_refs` present → MUST emit `## Visual Anchoring` BEFORE code | 2 |
| E162 | `role-cards.md:448` | sql-isolation HARD RULE — no query without tenant scoping + mandatory cross-tenant leak test | 13 |
| E163 | `role-cards.md:60,88,145,171,194,220` | Per-role agent contracts (backend/frontend/observability/docs/release/security MUST/NEVER rules) | 13 |
| E164 | `role-cards.md:474` | e2e — NEVER mock, max 3 repair cycles → ESCALATION, final rerun 0 failures | 13 |
| E165 | `run-management.md:124` | PHASE-END CHECKPOINT HARD STOP — AI must stop, wait for PM GO ("violating = AI error") | 12 |
| E166 | `run-management.md:14` | 12 MUST rules (read active.md each start, update after commit, archive done) | 12 |
| E167 | `run-management.md:62` | ID allocation — increment counter immediately, never roll back (collision prevention) | 4 |
| E168 | `memory.md:53` | increment-step requires `## Memory Used` + `## Memory Written` (instruction side of E119) | 2 |
| E169 | `memory.md:64` | NEVER write project.yaml (read-only); NEVER delete backlog entries (write-protection) | 4 |
| E170 | `planner.md:148` | Kahn topo-sort cycle + self-dep + all-refs-exist (instruction side of E87) | 6 |
| E171 | `planner.md:172` | Parallel-group file-conflict → forced sequential; waves of 5+ split to sub-waves of 4 | 4 |
| E172 | `aid-init.md:273` | pre-commit + pre-push hook install (instruction side of E38/E39) + idempotency | 8 |
| E173 | `aid-init.md:333` | `/aid-init` idempotency contract — existing config/work never overwritten | 7 |
| E174 | `aid-setup.md:24` | `/aid-setup` refuses to run if project.yaml missing | 7 |
| E175 | `aid-stop.md:53` | `/aid-stop` sets `mode: paused` first (block new dispatch) + `resumable: true` progress-save guarantee | 1 |
| E176 | `epic.md:31,83` | EPIC template scope (Allowed/Forbidden paths) + DoD Gates block — template contract consumed by scope-check + planner | 10 |
| E177 | `run-*.md` + `design-sections.md:113` | Run-template completion contracts + E2E ≥1 happy + ≥1 negative scenario rule | 10 |

### Revised totals (post Phase 1b)

- **~177 distinct enforcements** (86 first pass + ~91 second pass), still likely a
  floor — config knobs and per-role contracts could be split finer.
- All 15 types remain covered; the deep pass especially enriched type 4
  (structural-check), type 9 (YAML-policy), type 13 (agent-contract), type 2
  (subagent-output gates), and type 12 (skill protocols).
- **Cumulative miss-rate of the first pass: ~91/177 ≈ 51%.** The first careful
  pass captured under half the real enforcement universe. This is the audit's
  load-bearing empirical result.

_Note: Phase 2 mapping (02-mapping.md) covers E01–E86 only. The E87–E177
addendum is NOT yet mapped to instructions — that is follow-on work, scoped
in the governance recommendation (03-governance-recommendation.md)._

---

## Post-I2 corrections (AID-052, 2026-06-03) — inventory accuracy fixes

Surfaced during I2 coverage mapping + external verification. These correct the inventory rows
above; the PLUGIN is right, the inventory text was stale/wrong.

- **E12 / E140** — provenance is no longer a "±60s window around _generated_by". After C1/AID-046 it
  is interval-bracket (output `_generated_at` must fall within the focus's dispatch start..complete
  interval ± window_s tolerance), and the verdict value is `unverifiable` (not `fabricated`).
- **E106** — reclassify ALIGNED → **GAP** (atomic-write guard exists at aid-json-to-run.sh:597, but no
  LLM-facing instruction documents it; low priority).
- **E121** — reclassify GAP → **ALIGNED** (the `--force` + `--blocked-checks` coupling IS documented at
  pipeline.md:505; only the security rationale is unstated).
- **E141 / E142 / E143 / E148 / E149 / E151 / E154 / E157** — reclassify ALIGNED → **ORPHAN/decoration**
  (config-policy knobs read by no script and honored by no instruction; see 16-coverage-completion.md).
  E151 (global `retry.max_attempts`) was DELETED 2026-06-03 (per-gate `max_retries` is the only knob).
- **E155** — phantom: `integrations.yaml` has no `dedup_threshold` / `merge_threshold` fields. Remove
  this row (or treat as MEM-AUDIT scope).
- **E157** — line ref is permissions.yaml:129; confirmed SECURITY decoration (role_overrides never
  written to settings.local.json; blanket `Bash(*)` makes per-role Bash perms moot).
- **E159–E164** — role-cards.md line refs are stale after the P041 rewrite. Notably **E161**
  Visual Anchoring is now role-cards.md:136 (was :92) — and as of 2026-06-03 it is **no longer an
  ORPHAN**: a frontend+visual_refs step now hard-fails increment-step without a `## Visual Anchoring`
  section (aid-fsm.sh cmd_increment_step). **E164** (e2e NEVER mock / max 3 cycles) survived the rewrite
  in the new e2e step-role card.
- **E165** — run-management.md no longer claims the Controller auto-enforces the PM-GO phase boundary
  (corrected 2026-06-03: it is a manual-mode convention; `--auto` relies on escalation rules).
- **E171** — line ref is planner.md:183 (was :172); remains ORPHAN but moot while
  orchestration.yaml `max_parallel: 1` (parallelism disabled).
- **E175** — `/aid-stop` writes `mode: manual` (NOT `paused`), and persists no `resumable: true` flag
  (progress is persisted by the FSM, not by /aid-stop). Correct the description.

New finding (AID-052): **pre-filter config drift** — two pre-filter config files exist
(`review-checkpoints.yaml` referenced in docs vs `defaults/pre-filter-rules.yaml` actually read by
aid-prefilter.sh:16). Reconcile / single-source (tracked in 17-config-policy-proposal.md).
