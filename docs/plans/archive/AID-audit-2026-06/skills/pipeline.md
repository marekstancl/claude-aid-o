---
audit: P041
phase: 3 (pilot 2)
target: plugins/aid-orchestrator/skills/pipeline.md
dimensions_emphasis: 3d (reflection incorporation)
criteria_source: skill-writing-PROVISIONAL.md + 00-canonical-learnings.md
status: draft (pre-L1)
generated: 2026-06-01
---

# Pilot 2 Audit — pipeline.md

**Per-dimension summary:** 3d 5 findings (9 learnings PROPAGATED, 3 DELIBERATE-elsewhere, 4 DROPPED) · 3a 3 · 3b 1 · 3c 2 (grandfathered). pipeline.md is a high-quality Epic-band spec that absorbed the two dominant P041 themes (provenance/dispatch family + self-merge block). The one dangerous residue is 3d-1.

## 3d Propagation table (16 pipeline-touching learnings)

| learning# | verdict | anchor |
|-----------|---------|--------|
| #1 provenance_aggregate fabricated → block | PROPAGATED (partial/defective) | §7 `:840` + aid-fsm.sh:1980; **disarm undocumented — see 3d-1** |
| #2 self-merge despite overall:fail | PROPAGATED | §7 `:813-833`, done-advance `:57` |
| #3 dispatch events not emitted / verifier schema | PROPAGATED | §4 `:464-493`, CP2 `:411-435`, `:444` |
| #4 `_generated_by` agent_id / templates | PROPAGATED | CP3 `:540-541`, CP2 `:444` |
| #5 inline-mode CP2 self-review defect; SKIP bypass | **DROPPED** | absent — no inline provenance warning; Trivial Skip `:1187` is file/line-count only |
| #6 delete-step raw-SQL consumer grep | **DROPPED** | absent |
| #7 streamlined-abandoned detector + telemetry | PROPAGATED-in-code, under-documented | aid-fsm.sh:400; CP4 skip `:932-935`; prose contract absent |
| #10 compliance single-writer + DONE surface | PROPAGATED | aid-fsm.sh:984; trust level `:769-776` |
| #12 AC-match sub-clause detection | DELIBERATE (home=plan-writing.md) | correctly absent |
| #13 silent scope cuts | DELIBERATE (home=plan-writing.md) | correctly absent |
| #15 behavior-covered vs literal AC; pending stub | PROPAGATED (pending half `:445`); DELIBERATE (role-cards) | partial |
| #16 FSM friction / undocumented schemas | PROPAGATED | `:162-172`, `:495`, `:346-378`, `:444` |
| #17 file-ownership = atomic parallel-safety unit | **DROPPED** | absent — §4/§10 describe isolation, never the non-overlapping-files rule |
| #18 dispatch 500 → switch to sonnet | **DROPPED** | absent |
| #19 no-build EPICs → type:rule gates | DELIBERATE (home=execution.yaml) | correctly absent |
| #22 credit-exhaustion string fragility | DELIBERATE (I/C low-priority) | acceptable |

## Findings

| # | Dim | file:line | Priority | Effort | Finding | Recommendation |
|---|-----|-----------|----------|--------|---------|----------------|
| 3d-1 | 3d | `:830-833` + `:840` | **must-fix** | S | **Most-severe residue.** `verifier_provenance: blocking` IS wired (aid-fsm.sh:1980 prepends a block when provenance_aggregate==fabricated). BUT pipeline.md documents the soft-fail (`yq` missing → ALL failures downgraded to advisory, release proceeds) WITHOUT documenting the consequence: the exact NR8/NR17 self-merge passes silently on any host without `yq`. Principle #1 inversion — the most-severe learning's enforcement is conditional on an unstated host dependency. | Add Failure-mode + Fix: state that fabricated-provenance blocks done-advance ONLY when yq + check-severity.yaml present; absent yq downgrades the block to advisory. Cite NR8/NR17. |
| 3d-2 | 3d | `:564-576`, `:1064-1078` | should-fix | S | Learning #17 (file-ownership atomic-safety invariant) dropped — §4/§10 only describe post-hoc conflict detection. | Add MUST rule to §10: parallel steps in a wave MUST declare non-overlapping outputs[]; planner serializes overlaps. Makes re-enabling parallel safe. |
| 3d-3 | 3d | `:1187-1192`, `:396` | should-fix | M | Learning #5 dropped: no warning that inline dispatch_mode collapses CP2/CP3 to self-review (loses independence guarantee); Trivial Skip has no guard against skipping E2E/acceptance-bearing steps. | (a) CP2/CP3 note: inline mode = provenance defect, treat as fabricated for blocking. (b) Never SKIP a step with e2e acceptance regardless of line count. |
| 3d-4 | 3d | `:338-343` (#18), §4 (#6) | nice | S | Learnings #6 (delete-step grep) + #18 (dispatch-500→sonnet) dropped — cheap operational rules, no home. | Add both as short §4 rules. |
| 3d-5 | 3d | `:162-172`, `:932-935` | should-fix | S | Learning #7: streamlined-abandoned detector wired but prose contract absent. | Add §2/§7 note: --streamlined STILL writes timeline+compliance; <3 events = abandoned-but-shipped → blocks (SOUSTO NR12 anchor). |
| 3a-1 | 3a | `:66` vs `:97` | should-fix | S | Force-override char-count self-contradiction: `--reason` min 20 chars (`:66`) vs SYSTEMATIC flag if <30 chars (`:97`). A 25-char reason is both accepted and flagged. | Reconcile to one threshold or document why they differ. |
| 3a-2 | 3a | `:142-160`, `:780-800` | nice | M | Some enforcement sections state Rule+Trigger without Failure/Fix (incomplete 4-part contract). | Grandfathered; add Failure/Fix when next touched. |
| 3a-3 | 3a | `:251`, `:905` | should-fix | S | `qdrant-find`/`qdrant-store` referenced directly — conflicts with project/global vulcan-memory mandate (forbids raw qdrant-*). | Confirm with PM whether plugin-internal memory uses raw qdrant or routes through vulcan-memory; align wording. |
| 3b-1 | 3b | `:411-435`,`:472-488`,`:501-532`,`:918-931` | should-fix | M | Dispatch-wrapper bash duplicated ~4× (~80-120 lines) = Forbidden Pattern #3. | Keep one canonical block in §4; replace CP2/CP3/CP4 copies with one-line refs. Epic-band size otherwise justified. |
| 3c-1 | 3c | 11 headings (`:64,:142,:396,:464,:495,:609,:634,:755,:780,:813,:918`) | should-fix (grandfathered) | M | 11 version-stamped headings violate Forbidden Pattern #1; `:813` "Tiered Severity (NEW v2.21.0 — P038...)" is almost verbatim the skill-writing.md WRONG example. | Strip stamps from headings → CHANGELOG/body parenthetical. |
| 3c-2 | 3c | `:1203`, `:7` | should-fix | S | Stale footer `Last Updated 2026-05-13` despite P040/v2.25.0 content at `:464`/`:918`; no line-2 Last Updated at all. | Add line-2 date, bump footer to most-recent P040 edit, keep identical. |

## L1 verification (adversarial, 2026-06-01)
Independent verifier confirmed 3d-1, 3d-2, 3a-1 (3 of 3 pipeline claims checked) — **0 refuted**. It **deepened 3d-1**: the `overall_pre="fail"` override only stamps compliance.json telemetry; the actual review→release precondition (aid-fsm.sh:1968-2022) keys off `_blocking_count` (entries with `severity=="blocking"`) — NOT `overall`. Without `yq`, the synthetic `verifier_provenance` failure defaults to advisory (empty registry), `_blocking_count`=0, no `exit 2`, release proceeds. So the silent self-merge is confirmed end-to-end and is worse than first stated: the v3-principles §1 "blocking" guarantee for verifier_provenance is neutralized on any yq-less host.

## Net assessment
The two dominant P041 themes (provenance/dispatch family #3/#4/#16, self-merge block #2) are mechanically wired AND mostly documented. The dangerous residue is **3d-1**: the fabricated-provenance block — the single most-severe recurrent incident — is silently downgradable by a missing `yq`, and pipeline.md documents the disarm without the consequence. The 4 DROPPED learnings (#5/#6/#17/#18) are cheap to add; none is active risk today (parallel disabled, inline opt-in), but #5/#17 must land before parallel/inline modes are re-enabled.
