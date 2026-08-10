---
audit: P041
phase: 3 (pre-prep)
artifact: canonical-learnings-inventory
status: draft
generated: 2026-06-01
sources:
  - docs/plans/AID-v3-agents-outputs.md (15 NR entries, ~35% sampled at NR offsets)
  - .aid-o/work/lessons-learned.md (read fully)
feeds: Phase 3 dimension 3d (reflection incorporation)
---

# P041 Phase 3 Pre-Prep — Canonical Learnings Inventory

Deduped list of learnings from the reflection corpus (15 NR entries + lessons-learned.md).
This is the reference the Phase-3 audit (dimension 3d) checks were propagated into skills.

**Class legend:** `P-R` plan-reflection · `S-O` standalone-observation · `I/C` infra/config (low propagation priority). ⚑ = especially relevant to P041 thesis.

## Deduped canonical learnings

| # | nr_id | project / date | learning | recommendation | class | touches_skill |
|---|-------|----------------|----------|----------------|-------|---------------|
| 1 ⚑ | NR 17 | AID 2026-05-31 | `provenance_aggregate: fabricated` + `overall: fail` did NOT block merge; done-advance ignores both. **Reframes earlier "fabrication" (NR 7/8/10) as a ±60s timing false-positive** (commit time lagged dispatch >60s). | Wire `provenance_aggregate==fabricated` → hard block in `cmd_done_advance review→release` (with force escape). Prereq: close provenance_aggregate visibility gap in eval script. | P-R | pipeline.md (done-advance), agent-protocol.md (provenance semantics) |
| 2 ⚑ | NR 8 | AID 2026-05-13 | **Self-merged with `overall:fail`** — merge-blocking enforcement failed to block its own merge (ran from cached plugin without the new precondition). Same as P026 mode. Risk: chronic "fabricated" → 100% fire → PM trained to reflexive `--force`. | New enforcement must not deploy-precede itself; provenance must be machine-verifiable before a blocking precondition relies on it. | P-R | pipeline.md (release-blocking), agent-protocol.md |
| 3 | NR 7 | WAN 2026-05-13 | Subagent dispatch doesn't auto-emit `verifier_dispatch_start/complete` → compliance labels 100% verifier outputs "fabricated". Verifier-output schema undocumented → ~12 min lost. | Wrap dispatch in helper emitting events; document verifier-output header schema inline. | P-R | pipeline.md (§4 dispatch wrapper), agent-protocol.md (verifier-output schema) |
| 4 | NR 10 | VULCAN 2026-05-26 | Provenance "fabricated" across all EPICs because `_generated_by` was a focus-label not real agent_id. No enforced templates for FSM artifacts caused 2/3 fails. Compliance "fail" never surfaced as blocking. | Enforce verifier-output template + auto-stamp real agent_id; surface compliance fail in PM DONE summary. | P-R | pipeline.md, agent-protocol.md, role-cards.md (verifier card) |
| 5 ⚑ | NR 13 | VULCAN 2026-05-31 | Switching CP2 to `dispatch_mode: inline` made all 16 reviews `main-context@sha` = 100% self-review, removing per-step independence (AID's core guarantee). A docs_only auto-SKIP bypassed a step carrying E2E acceptance. | Treat inline-mode CP2/CP3 as provenance defect; guard CP2 SKIP against steps bearing real acceptance. | P-R | pipeline.md (CP2/CP3 dispatch + SKIP), agent-protocol.md |
| 6 | NR 13 | VULCAN 2026-05-31 | Symbol-scoped (ORM-only) grep missed raw-SQL consumers; migration broke them at runtime — passed all 17 step-verifies AND CP3, caught only by Curator+Auditor. | When a step deletes a symbol/model, add a raw-SQL / non-ORM consumer grep. | S-O | pipeline.md (delete-step guidance) |
| 7 ⚑ | NR 12 | SOUSTO 2026-05-31 | **Streamlined-abandoned anchor:** FSM stuck in EXECUTE/step 0, yet code merged to main AND deployed to prod — zero gates/compliance/curator/auditor. No "abandoned-in-EXECUTE but descendants in main" detector. | Add abandoned-but-shipped detector; first-class `--streamlined` that STILL writes timeline + compliance.json. | P-R | pipeline.md (streamlined + detector), aid-run.md |
| 8 | NR 14 | AID 2026-05-31 | PM-approved execution-path shift (direct edits instead of /aid-run) → no telemetry exists (real absence). Pipeline parser counted `### Step 7` quoted in fenced blocks as real steps → crash. | Plans-about-AID must not quote `### Step N` at line-start in fences; streamlined path still emits minimal telemetry. | P-R | aid-plan-to-epic.sh parser, plan-writing.md (self-reference rule) |
| 9 ⚑ | NR 16 | AID 2026-05-31 | **Cross-section consistency drift** → 5 sequential CP1 passes (~3-4h, ~2.5M tokens). Plan restated counts/renames in 7+ places; fixing one left others stale. Completeness Gate is all per-section — no cross-section invariant. | Add cross-section invariant check to plan-writing.md Completeness Gate; add cross-section sweep to section-review. | P-R | plan-writing.md (Completeness Gate), brainstorming.md, role-cards.md (cross-section-review) |
| 10 | NR 15 | WAN 2026-05-31 | **Misdiagnosis meta-lesson:** test failing on "LLM returns X" was a stale mock value, not env/LLM. Self-audit missed it; independent session caught it. FSM done-advance overwrote auditor's `overall:pass` → two divergent compliance.json. | Verify "LLM/service returns X" isn't a mock before blaming env. Reconcile auditor vs FSM compliance.json (single-writer). | P-R | role-cards.md (qa diagnostic), pipeline.md (compliance single-writer) |
| 11 | NR 11 | MANUAL (permissions) | `/aid-setup permissions` preset names MCP servers not running in current eco setup → dual-write produces allow-rules matching nothing → autonomous prompts for permission. | Update permissions.yaml preset to actually-configured servers; don't use stale preset. | S-O | defaults/policies/permissions.yaml, aid-setup.md |
| 12 | NR 6 | WAN 2026-05-12 | Silent scope cut: "drop excess + log warning" → only drop coded, warning never coded/mentioned; audit passed without trace. 3 fixtures → 1. Wrong plan AC fixed in tests not flagged as plan bug. | AC-match must detect dropped sub-clauses ("+ log warning"), not just primary verb; reframing a wrong AC updates the plan, not silently the tests. | P-R | pipeline.md (AC-match/auditor), plan-writing.md |
| 13 | NR 5 | WAN 2026-05-11 | 5 goalpost shifts: silent UI cuts, manual-verification substituted, backlog items (T-137/138) silently dropped, "3 commits"→34. Backlog-instruction drop is recurring. | Plan-mandated backlog/follow-up needs explicit post-impl checklist item the auditor verifies; manual-verification ACs need concrete recipe. | P-R | pipeline.md (auditor AC-match), plan-writing.md |
| 14 | NR 4 | WAN 2026-05-10 | Playwright E2E AC substituted with backend introspection (admitted rationalization); UI-render never proven. | For UI-render ACs do not substitute backend introspection; require browser assertion or escalate to PM. | P-R | role-cards.md (qa/e2e), plan-writing.md |
| 15 | NR 3 | WAN (P021) | Goalpost drift on test names accepted as "behavior covered"; screenshot AC drift uncaught; pre-filter stub `verdict: pending` write-then-overwrite error-prone. | Verifier distinguishes "behavior covered" from literal-AC-met + reports drift; pre-filter SKIP stub must not let `pending` pass un-updated. | P-R | role-cards.md (verifier), pipeline.md (pre-filter SKIP) |
| 16 | NR 2 | WAN (P020) | 7 FSM/gates stucks (~30-40% of run): `state.yaml` vs `fsm-state.yaml`; undocumented step-verify sections; undocumented verifier-output frontmatter; CP3-before-GATES surprise; gates chicken-and-egg; epic-to-json path bug; pre-filter pending stub. | Rename state file; print step-verify template on first fail; document EXECUTE-entry prereq checklist (incl CP3). | P-R | aid-run.md (prereq checklist), pipeline.md, aid-epic-to-json.sh |
| 17 | LL table | AID multi-EPIC (Feb 2026) | **File-ownership is the atomic safety unit for parallel dispatch** — parallel steps must own non-overlapping files or be serialized; validated zero-conflict across EPICs. | Keep file-ownership rule as parallel-dispatch safety condition; architect manifest for large EPICs. | P-R | pipeline.md (parallel dispatch), role-cards.md (architect) |
| 18 | LL table | AID 2026-02-22 | Claude API 500 during dispatch cleared by switching dispatch model to `sonnet`; retrying same/opus doesn't help. | On dispatch 500, switch model to sonnet immediately. | S-O | pipeline.md (dispatch error handling) |
| 19 | LL table | AID 2026-02-22 | Plugin/docs projects have no build/test → `docs_updated` gate must be `type: rule`, never `type: command`; omit build/test gates for markdown/YAML EPICs. | For no-build EPICs use `type: rule` gates only. | S-O | execution.yaml defaults, pipeline.md (gate selection) |
| 20 | LL gotchas | AID 2026-02-27 | Env gotchas: QA defaults to wrong test package; type-check/build gates fail unless `npm install` first; Vitest/Playwright pattern collision silently skips; Zustand singleton leaks without reset. | Specify package in QA dispatch; gates install deps first; separate test patterns; reset store per test. | S-O | role-cards.md (qa), execution.yaml (gate prereqs) |
| 21 | LL gotchas | AID 2026-02-27 | Curator auto-fixes 4 bug classes (wrong calls, path errors, missing error handling, security allowlists) → safe auto-merge of imperfect output. | Keep curator auto-fix scope to these 4 classes. | S-O | role-cards.md (curator) |
| 22 | LL narrative | AID 2026-02-25 | Credit-exhaustion detection is string-matching only; breaks if CC error format changes; no proactive credit API. | Periodically verify CC credit-error strings; add pre-dispatch check if API appears. | I/C | pipeline.md (low priority, env-noise) |

## Dedupe / merge notes

- **#3 + #4 + #10** = one lesson family (verifier provenance unverifiable: dispatch events not emitted + `_generated_by` not machine-bound). NR 17 (#1) reframes part as a ±60s timing false-positive. Audit treats as ONE propagated lesson with facets.
- **#2 + #1** = self-merge-despite-fail family (NR 8 reproduced P026; NR 17 reproduced again + named the fix).
- **#16 + #3 + #7** overlap on FSM-mechanics friction; #16 kept as canonical FSM-friction row, #3 as canonical provenance row.
- Positive/confirmatory LL rows (docs-only→0 retries, detailed EPIC→<2min review, session-resume works) folded into #17 or omitted as non-actionable.

## Recurring themes (5)

1. **Instruction-without-enforcement drift** (dominant; the P041 through-line). Plans state a count/rename/"+log warning"/backlog-add/fixture; the missing half silently disappears with no gate catching it (NR 6, 5, 16, 3, 4). Same class as Principle #1 — appears in both plan-writing (no cross-section invariant) and auditing (AC-match checks primary verb only).
2. **Self-merge despite `overall:fail`** (most severe + recurrent; NR 8 then NR 17). Detection machinery exists and fired, but the final enforcement edge in done-advance was never wired. The canonical P041 candidate.
3. **Dispatch provenance / fabrication** (NR 7, 8, 10, 13, 17). Dispatches don't emit events; `_generated_by` carried focus-label; inline-mode stamps main-context → genuine reviews unprovable → 100% "fabricated". NR 17 partly exonerates as ±60s timing window — fix is dual (instrument events AND clean the window before any blocking precondition).
4. **FSM bypass / abandoned-but-shipped** (NR 12 anchor + NR 6/14). All-or-nothing FSM → operators bypass entirely; a bypassed run ships to prod with empty timeline + no compliance.json, undetected. Fix: first-class `--streamlined` that still emits telemetry + abandoned-in-EXECUTE detector.
5. **FSM mechanics friction / undocumented schemas** (NR 2, 3, 7, 8, 10). State-file naming, undocumented step-verify + verifier-output schemas, CP3-before-GATES surprise, gates chicken-and-egg, pre-filter pending stub. ~20-40% of run wallclock; cheap documentation debt to propagate into aid-run.md + agent-protocol.md.
