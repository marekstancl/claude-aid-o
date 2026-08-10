---
audit: P041
phase: 5 (decision log)
artifact: decisions
status: draft-for-PM (PM-GATE-C input — recommended outcomes; OPEN items need Marek)
generated: 2026-06-01
inventory_id_space: last assigned AID-043; AID-044 reserved (Tier-3 provenance follow-up); new = AID-045+
---

# P041 Phase 5 — Decision Log

Consolidates the audit's findings into actionable decisions. Each item has a
recommended outcome; **OPEN items require PM (Marek)**. Non-now fixes get an
AID-NNN inventory ID so they don't evaporate (the recurring "97.5% plans stuck at
draft" risk the plan flagged). No code changes were made in this audit — every
outcome below is a recommendation.

**Outcome vocabulary:** Apply-now · Inventory AID-NNN · Park-as-candidate ·
Promote-to-binding · Approve-draft · OPEN (PM decides).

---

### D-01: planner.md is a fictional script contract (FAIL)
- **Source:** Phase-3 fan-out + both re-audit rounds (confirmed, "if anything understated").
- **Category:** fix-now-or-defer · **Priority:** must-fix · **Effort:** M (rewrite).
- **Outcome:** **Inventory AID-045.** Ground-up rewrite of planner.md against the real `aid-epic-to-json.sh` (table-based EPIC input, manifest-to-stdout, no wave algorithm; only Kahn cycle-detection is accurate today).
- **Rationale:** Exceeds a docs-edit; actively misleads any agent that reads it.

### D-02: Provenance enforcement broken in BOTH directions (P8) — the original P041 nonce task, reframed
- **Source:** Phase-2 E12 (CONTRADICTORY, over-fire) + Phase-3 pilot 3d-1 (yq-disarm, under-fire, L1-confirmed) + NR 17 §4D annotation.
- **Category:** fix-now-or-defer · **Priority:** must-fix · **Effort:** M.
- **Outcome:** **Inventory AID-046.** Paired fix: (a) widen/repair the ±60s provenance window so honest runs aren't flagged fabricated, BEFORE (b) wiring `provenance_aggregate==fabricated` → hard block in done-advance, AND (c) ensure the block can't be silently disarmed by a missing `yq`.
- **Rationale:** This is what the original "P041 = hard-block fabricated" survives as — but the audit proved a naive hard-block would over-fire on honest runs. Must fix both directions together.

### D-03: Three command functional bugs
- **Source:** Phase-3b command audit (both rounds).
- **Category:** fix-now-or-defer · **Priority:** must-fix · **Effort:** S each.
- **Outcome:** **Inventory AID-047.** (1) aid-help Level detection greps legacy `state.yaml` → always Level 0; (2) aid-stop saves resume data to `auto-mode-state.yaml` that `--resume` never reads → resume broken; (3) aid-research reads `defaults/integrations.yaml` (template) not `.aid-o/config/` (live) + cites nonexistent `/aid-setup Option 6a/6b`.
- **Rationale:** Real runtime breaks, not doc hygiene. Small fixes, high value.

### D-04: qdrant-* vs vulcan-memory mandate conflict (3+ files)
- **Source:** Phase-3 (memory-mcp, project-scanner, pipeline:251) + Phase-3b (aid-research).
- **Category:** fix-now-or-defer · **Priority:** should-fix · **Effort:** M.
- **Outcome:** **OPEN — PM adjudication required.** Either (A) the plugin legitimately targets a consumer-project `qdrant-brain` tool → add one carve-out sentence distinguishing it from the eco-ecosystem vulcan-memory mandate; or (B) migrate the plugin's memory references to vulcan-memory naming. In-repo config (`integrations.yaml`, `aid-init.md`) already agrees on `qdrant-brain`; only the eco CLAUDE.md mandate diverges.
- **Rationale:** Cannot be decided from the code alone — it's a policy boundary (is the plugin eco-internal or distributed?). **Needs Marek.**

### D-05: state.yaml → fsm-state.yaml drift across the command/skill layer
- **Source:** canonical learning #16; found unpropagated to aid-run, aid-status, aid-stop, aid-help, run-management.md.
- **Category:** inventory-item-or-now · **Priority:** should-fix · **Effort:** S (batch).
- **Outcome:** **Inventory AID-048.** Rename pass — BUT not a blind rip-out: the codebase is mid-migration (aid-fsm.sh:277 still accepts `state.yaml` as a legacy fallback, E128). Update docs to name `fsm-state.yaml` canonical + `state.yaml` legacy-fallback; do not delete the still-live fallback. Folds into D-03's aid-help/aid-stop fixes.

### D-06: Version-stamped headings + systemic stale dates
- **Source:** Phase-3 P3/P4 + Phase-3b pattern 4 (all 10 commands stale; version-stamps in pipeline ×11, plan-writing ×3, agent-protocol, brainstorming, aid-plan).
- **Category:** inventory-item-or-now · **Priority:** nice-to-have · **Effort:** S (batch, mechanical).
- **Outcome:** **Inventory AID-049.** Strip version stamps from headings → CHANGELOG/body; bump stale footers. Do as one sweep.

### D-07: Promote skill-writing.md + command-writing.md to the plugin
- **Source:** Phase-4b-pre/final + external review.
- **Category:** approve-Phase-4-draft · **Effort:** M (separate code-change EPIC).
- **Outcome:** **Approve-draft (provisional) + Inventory AID-050 for promotion.** The two standards are refined (skill-writing's 4 external-review blockers fixed: Reference-band reclassification, grandfathering section, gate #14 N/A, deterministic band rule; command-writing built with those lessons baked in). **Do NOT ship to `plugins/.../skills/` in this audit** — promotion is a code change that MUST land together with the governance sync-guard (Component 3), else the standards are Principle-#1 decoration. That EPIC carries the CHANGELOG + version-bump ceremony.
- **Rationale:** Keeps the audit code-change-free; sequences the guard with the standard.

### D-08: Promote Principle #5 (Cargo Cult) to binding?
- **Source:** Phase-4a + the audit's empirical weight.
- **Category:** promote-candidate-to-binding · **Effort:** XS.
- **Outcome:** **Park-as-candidate with strong evidence (recommend) — OR Promote, PM's call.** The sub-criterion (≥3 GAP findings across ≥2 enforcement mechanisms) is **met**: focus-allowlist regex (dispatch), plan.schema constraints (structural/schema), planner.md + command doc-vs-code drift (instruction-loaded). The global gate's (a) ≥2 reflection sessions + (b) inventory item are also met. Only **(c) PM confirmation** is outstanding.
- **Rationale:** Evidence is unusually strong, but per the gate it's Marek's confirmation that promotes it. **Light PM decision.**

### D-09: Dropped reflection learnings (propagation leak)
- **Source:** Phase-3 3d (#21 homeless, #15, #5, #17, #10/#20 in role-cards/pipeline).
- **Category:** reflection-incorporation · **Priority:** should-fix · **Effort:** M.
- **Outcome:** **Inventory AID-051.** Resolve homeless #21 (place 4 auto-fix classes in curator.md; fix inventory `touches_skill`); backfill the dropped learnings into their canonical homes; going forward, reflection-prompt **Sekce 9** (added this session) prevents recurrence. **Also:** learning **#11** (permissions preset stale) was never *checked* in Phase 3 (both homes out of scope) — deferred to AID-052 coverage completion, recorded here so it doesn't vanish.

### D-10: Coverage holes
- **Source:** L2 completeness critic (A1/A5).
- **Category:** inventory-item-or-now · **Priority:** should-fix · **Effort:** L.
- **Outcome:** **Inventory AID-052.** (a) Map E87–E177 (~91 enforcements) to instructions (extend Phase 2); (b) audit the still-excluded setup/*.md (4), visual-companion/SKILL.md, design-sections.md. Commands are now done (Phase-3b closed the biggest hole).

### D-11: Phase-4 documentation deliverables (4a/4c/4d/4e/4f)
- **Source:** this session.
- **Category:** approve-Phase-4-draft · **Effort:** done.
- **Outcome:** **Approve-draft (delivered).** #5 candidate added to principles.md; Sekce 9 added to reflection-prompt; inventory v1.12 cross-link; NR 17 §4D annotation; roadmap P041 entry rewritten. All in `docs/plans/` (design docs, not plugin distribution).

### D-12: Doc-vs-code fabrication sweep (the planner.md class, beyond planner)
- **Source:** Phase-3b round-2 — the same fabrication class as D-01 spread across the command/agent surface (completeness critic A).
- **Category:** fix-now-or-defer · **Priority:** must-fix · **Effort:** M (batch).
- **Outcome:** **Inventory AID-053.** Bucket the unnamed doc-vs-code fabrications: aid-run.md invented `DONE→ERROR` edge + per-step branch + `git merge epic/{id}` + parallel-as-current; aid-do.md missing `aid-do-log.jsonl` log contract; aid-plan.md CP1 raw `aid-stage-log` instead of mandated `aid-emit-dispatch` wrapper + stale "24" gate count; brainstorming.md `.aid-o/epics/` glob (matches nothing); run-management.md Run-ID format unproducible + archive-path collision; curator.md propose-vs-dispatch contradiction; memory.md `cat state.yaml` field error.
- **Rationale:** D-01 was scoped planner-only; this is the rest of the same class. Each item is a real instruction-vs-code break.

### D-13: aid-init pre-push hook-marker bug (4th command functional bug)
- **Source:** Phase-3b aid-init audit.
- **Category:** fix-now-or-defer · **Priority:** must-fix · **Effort:** S.
- **Outcome:** **Inventory AID-054.** aid-init.md says pre-push uses "same markers as pre-commit", but the hooks use different markers (`AID-ORCHESTRATOR-HOOK-START` vs `-PREPUSH-START`) → an LLM re-running `/aid-init` appends duplicate hook blocks each time. (D-03 was capped at 3 bugs; this is the 4th.)

### D-14: CP4 verifier-output filename collision (E20 ORPHAN — enforcement-shaped)
- **Source:** Phase-2 E20 + Phase-3 second pass (escalated "to Phase 5").
- **Category:** fix-now-or-defer · **Priority:** must-fix · **Effort:** S.
- **Outcome:** **Inventory AID-055.** Template + verifier.md tell the verifier to write `verifier-output-cp4-curator.md`, but `fsm_check_cp4` requires `verifier-output-cp4-curator-validation.md` → the CP4 gate can never find its file. Standardize the name across template + verifier.md + add CP4 to verifier.md's output list.
- **Rationale:** Pairs with D-02 — an enforcement that silently can't fire (the file it scans for is never produced).

### D-15: auditor.md / aid-audit.md scoring-contract inconsistency
- **Source:** Phase-3 auditor.md + Phase-3b aid-audit.md.
- **Category:** fix-now-or-defer · **Priority:** should-fix · **Effort:** M.
- **Outcome:** **Inventory AID-056.** Three severity scales coexist in auditor.md (dead L50 `10/5/2/1`, live L539 `-15/-10/-5/-2`, Memory-Health J `0-20×5`); TODO handling contradicts execution.yaml `max_todo_count:0`; aid-audit.md menu lists 8 types vs auditor's 10 categories + severity vocab "Critical/Warning/Suggestion" vs auditor's Critical/High/Medium/Low. (D-10 only scheduled a *deeper pass*; these are already-found defects needing a fix home.)

### D-16: Principle-#1 violations on the command surface
- **Source:** Phase-3b (aid-status, auto-mode-state).
- **Category:** fix-now-or-defer · **Priority:** should-fix · **Effort:** S.
- **Outcome:** **Inventory AID-057.** Documented-but-unbacked capabilities: aid-status `pause/resume/reorder` (no script), `auto-mode-state.mode` (written by nothing), "Auto-pickup: active" (no store). Either build the enforcement or delete the prose. (Ironic to leave unhomed — this is the project's founding Principle #1.)

### D-17: memory-mcp + implementer behavioral defects
- **Source:** Phase-3 second pass.
- **Category:** inventory-item-or-now · **Priority:** should-fix · **Effort:** S.
- **Outcome:** **Inventory AID-058.** (a) memory-mcp.md hard-codes a `0.85` dedup threshold un-sourced for the `memory` section (the yaml's 0.85 is under `knowledge`); (b) implementer.md model-block omits security/release/VULCAN roles → they silently dispatch at default sonnet, masking role-cards' explicit tiers.

---

## CHANGELOG note
No `CHANGELOG.md` entry is due from this audit: it made **zero changes to
`plugins/aid-orchestrator/`** (all outputs are in `docs/plans/`). The CHANGELOG +
version-bump ceremony attaches to the D-07 promotion EPIC (when the standards +
sync-guard ship), not to the audit.

## AID-NNN allocation summary
AID-045 planner.md rewrite · AID-046 provenance both-ways fix · AID-047 command
functional bugs (3) · AID-048 state-file rename · AID-049 version-stamp/date sweep ·
AID-050 standards promotion + sync-guard · AID-051 reflection backfill ·
AID-052 coverage completion · AID-053 doc-vs-code fabrication sweep · AID-054
aid-init hook-marker bug · AID-055 CP4 filename collision · AID-056 auditor/aid-audit
contract · AID-057 command-surface Principle-#1 violations · AID-058 memory-mcp +
implementer defects. (AID-044 remains reserved for the Tier-3 provenance follow-up.)
Contiguous AID-045..058, no gaps, no duplicates.

## OPEN items for Marek (PM-GATE-C)
1. **D-04 qdrant vs vulcan-memory** — adjudicate (A carve-out / B migrate). Blocks 3+ files.
2. **D-08 Principle #5** — confirm promotion to binding, or keep candidate.
3. **Ship/iterate** — accept these recommendations + AID-NNN allocations, or revise.
