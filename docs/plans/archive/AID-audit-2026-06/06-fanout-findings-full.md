---
audit: P041
phase: 3 (fan-out) — full per-file findings
artifact: fanout-findings-full
status: draft
generated: 2026-06-01
note: full finding tables for the 13 fan-out files; pilots are in skills/plan-writing.md + skills/pipeline.md
---

# P041 Phase 3 Fan-out — Full Findings (13 files)

Complete per-file finding tables (the master index 05 carries only top-finding + counts).

---

## skills/brainstorming.md (507) — PASS_WITH_NOTES
3a present incl. RULE 9-12 validate-then-verify (the P041 thesis anchor, coherent). 3d #9 PROPAGATED (Cross-Section Validation Step 7, L341-354).

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | brainstorming.md:64 | must | S | Prior-work glob `.aid-o/epics/*.md`; canonical EPIC dir is `.aid-o/tasks/` → silently matches nothing | Change glob to `.aid-o/tasks/*.md` |
| 3a | brainstorming.md:332 | must | S | Severity `critical\|low` (2 levels) contradicts role-cards `critical\|high\|medium\|low` (4) it claims to reuse | Align to 4-level enum; add high/medium render glyphs |
| 3a | brainstorming.md:30,48 | should | S | MUST Rule 5 + Principle #3 inline-duplicate the validate-then-verify cycle (RULE 9-12) | Keep one-line pointer; protocol is canonical |
| 3a | brainstorming.md:24-40 | nice | S | MUST rules not 4-part contracts (grandfathered; author-facing) | Add failure-mode pointers to enforcement rules 5,6,10 next edit |
| 3a | brainstorming.md:3,7-9 | nice | S | Missing Purpose para / When-to-Invoke / Completeness Gate (grandfathered) | Add on next major revision |
| 3b | brainstorming.md:277-354 | should | M | P039 added ~78 lines, no compensating cuts → pushed into Reference band | Accept OR extract validate-then-verify cycle to own skill |
| 3b | brainstorming.md:86-93,360-368 | nice | S | Mockup handling described twice | Consolidate source-type taxonomy |
| 3c | brainstorming.md:309 | should | S | Version-stamped heading `### Section Verdict Format (P039 — ...)` | Rename; keep (P039) as body annotation |

## skills/role-cards.md (492) — PASS_WITH_NOTES
3d: #9 PROPAGATED (cross-section-review L370-397), #17 PROPAGATED (architect L30). #4 home is agent-protocol (no change).

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | role-cards.md:315 vs :459 | HIGH | M | Two contradictory `e2e` cards (Playwright-only sonnet vs 5-layer opus) | Merge into one (keep L459); or split e2e-browser vs e2e-fullstack |
| 3a | role-cards.md:11 / verifier.md:14-19 | HIGH | S | Header "focus cards (7)" but 8 blocks exist; verifier.md lists only 6 (no qa/e2e) | Reconcile true focus set; fix count + verifier.md list |
| 3a | role-cards.md:459 | MED | S | Bare `## e2e` breaks `## Focus:` convention | Rename to `## Focus: e2e` |
| 3a | role-cards.md:408-455 | LOW | S | VULCAN roles drop `Max Parallel` field | Add or document default |
| 3b | role-cards.md:459-487 | MED | S | ~29-line duplicate e2e block (only extractable accretion) | Delete after merge |
| 3c | role-cards.md:9 vs :491 | HIGH | XS | Header date 2026-03-16 ≠ footer 2026-03-19 | Set both identical |
| 3c | role-cards.md:492 | MED | XS | Stale `**Replaces:** defaults/playbooks/` (dir no longer exists) | Remove line |
| 3d #10 | role-cards.md:239-256 | DROPPED M | | NR15 mock-vs-real diagnostic absent from qa card | Add qa key-check |
| 3d #14 | role-cards.md:323-329,461 | PARTIAL S | | NR4 backend-introspection-substitution prohibition not explicit | Add to e2e Do-NOT |
| 3d #15 | role-cards.md:296-311 | DROPPED S | | NR3 behavior-covered vs literal-AC + drift-report absent | Add to code-review/qa |
| 3d #20 | role-cards.md:239-256 | DROPPED M | | qa env gotchas (pkg, deps, patterns, store reset) no home | Add qa env preconditions or ref execution.yaml |
| 3d #21 | role-cards.md (no curator card) | DROPPED M | | curator 4 auto-fix classes homeless — no curator card exists | Resolve home (curator.md) + fix inventory touches_skill |

## skills/agent-protocol.md (286) — PASS_WITH_NOTES
Both `*(planned)*` entries VERIFIED correct against scripts (pass Forbidden Pattern #2).

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3c | agent-protocol.md:197 | high | S | Version-stamped heading `## Tiered Severity Reference (v2.21.0)` | Rename; move stamp to body/CHANGELOG |
| 3d #3 | agent-protocol.md:197-212 | medium | M | NR7 verifier-output frontmatter schema not documented inline (partial drop) | Add schema block or cross-ref verifier.md with NR-7 disposition |
| 3a | agent-protocol.md (whole) | medium | L | Missing When-to-Invoke/MUST Rules/Completeness Gate; enforcement rules bare imperatives (grandfathered) | Retrofit 9-section structure next major revision |
| 3a | agent-protocol.md:268,272 | low | — | Both `*(planned)*` entries confirmed accurate; keep | Add IMP/backlog ID for stronger traceability |
| 3d | agent-protocol.md (provenance) | low | S | #1/2/4/5/10 are DELIBERATE-elsewhere (pipeline.md) | Optional one-line pointer to pipeline.md §7 |
| 3b | agent-protocol.md (286) | low | — | Tight/standard boundary; no accretion | None |

## skills/run-management.md (277) — PASS_WITH_NOTES

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a/3d | run-management.md:149 | HIGH | S | Stale `state.yaml`; pipeline.md made `fsm-state.yaml` canonical (NR16) | Change to fsm-state.yaml; bump date |
| 3a | run-management.md:40,105,225,229 vs pipeline.md:14,180 | MED | S | Run files at `.aid-o/work/tasks/`; pipeline uses `.aid-o/work/runs/{run_id}/` | Reconcile or document split |
| 3a | run-management.md:153 vs :22 | MED | XS | Archive-path collision: task→`.aid-o/tasks/archive/` vs MUST#7 runs→`.aid-o/work/tasks/archive/` | Disambiguate both invariants |
| 3a | run-management.md:124-155 | MED | M | PHASE-END HARD STOP + Run Closure lack 4-part contract | Add trigger/failure/fix or cite pipeline.md |
| 3d #7 | run-management.md:83-92 | MED | M | Streamlined/abandoned-but-shipped not mentioned in run-lifecycle skill | Add Streamlined row or ref aid-run.md |
| 3a/3c | run-management.md:277 | LOW | XS | Footer date 2026-03-03 stale; no line-2 header date | Add line-2 date; bump |

## skills/memory-mcp.md (289) — PASS_WITH_NOTES

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3d | memory-mcp.md:22,90,110,140,165 vs CLAUDE.md | HIGH | M | Mandates raw qdrant-store/find; CLAUDE.md forbids (vulcan-memory) | PM adjudicate; carve-out or migrate naming |
| 3a | memory-mcp.md:91 vs integrations.yaml:63-68 | HIGH | S | Dedup 0.85 hard-coded; min_score 0.4/top_k never cited → drift | Reference integrations.yaml; add 0.85 to yaml |
| 3a | memory-mcp.md:100-106 vs 244-249 | MED | S | §4 + §8 validation tables duplicate + diverge; neither enforces max 15 lines | Make §8 canonical; add 15-line max |
| 3a | memory-mcp.md:240,253-266 | MED | M | Quality gate/rejection/N-A lack 4-part contracts | Rewrite as 4-part (fix text already at L268-276) |
| 3c | memory-mcp.md:23 vs 141-144 | MED | S | L23 says no payload filtering; L140-144 shows filter= | Reconcile |
| 3d #4 | memory-mcp.md:209-227 | MED | S | memory_writes block has no agent_id/_generated_by (NR10 un-propagated) | Add provenance field |
| 3b | memory-mcp.md:289 | LOW | XS | Footer 2026-03-19 stale vs shared-brain migration commit | Bump |

## skills/memory.md (69) — PASS_WITH_NOTES
L53 claim VERIFIED correct vs aid-fsm.sh:1774-1793.

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | memory.md:53 | medium | S | Sole enforcement ref lacks 4-part contract | Add trigger/failure/fix mirroring aid-fsm.sh stderr |
| 3a | memory.md:48 | low | S | Czech "kondice" in English-only file | Replace with English term |
| 3b | memory.md (69) | low | M | Below Tight floor (80) but content-complete; missing 4 of 9 sections | Grandfather; don't pad; flag Tight-skill exemption for Phase-4 |
| 3d | memory.md:53 | medium | M | N/A escape-hatch (aid-fsm.sh:1778) + the why (provenance) not documented | Add N/A allowance + link to agent-protocol.md |
| 3d | memory.md:64-67 | low | S | Write-protection NEVERs lack enforcement pointer | Note whether a check enforces, or mark absence |

## skills/planner.md (234) — **FAIL (content)**
Only the Kahn cycle-detection claim (L145→script:301-374) is accurate. Needs ground-up rewrite.

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | planner.md:28 vs script:33-36 | CRITICAL | M | Documented CLI wrong; real flags `--epic --schema --output-dir [--plan-source]` | Rewrite Script Contract |
| 3a | planner.md:48-87 vs script:137 | CRITICAL | M | EPIC input shown as heading-blocks; script parses a markdown TABLE | Replace Input section with real table format |
| 3a | planner.md:141-161,115-124,167 vs script | CRITICAL | L | Level/wave algorithm + waves[] output FABRICATED; script computes no waves; parallel_groups from author column | Delete wave algorithm; document author-declared column |
| 3a/3d | planner.md:171-173 vs script:383-405 | HIGH | S | False claim script auto-serializes overlapping allowed_paths (contradicts #17, unenforced) | Remove claim; state file-ownership is author/LLM responsibility |
| 3a | planner.md:33-34 vs script:14 | HIGH | S | Claims writes state.yaml+execution.yaml; emits JSON manifest to stdout + state.yaml only | Correct Writes list |
| 3a | planner.md:129 | MED | S | Claims `model` field from role-cards tier; script emits none | Remove or cite where set |
| 3a | planner.md:40,218 vs script:131 | MED | S | Wrong required-section error (Goal/Scope/DoD vs real "Steps (Role Pipeline)") | Align Error Handling |
| 3c | planner.md:234 | MED | XS | Only one date stamp; no line-2 header date | Add header date; bump |
| 3a | planner.md (structure) | MED | M | Missing When-to-Invoke/MUST Rules/Completeness Gate (grandfathered) | Add on rewrite |
| 3d #8 | planner.md:51-79 | LOW | XS | EPIC examples use `### step_N` headings (could re-trip plan-about-AID parsers) | Note IDs live in table; cross-link self-reference rule |

## agents/auditor.md (770) — PASS_WITH_NOTES

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | auditor.md:50 vs :539-544 | high | S | Two contradictory severity scales (Security 10/5/2/1 vs global -15/-10/-5/-2) | Delete L50; reference single global table |
| 3a | auditor.md:204-214 vs execution.yaml:138,209 | high | M | TODO treated -2 non-blocking; execution.yaml says max_todo_count:0 + not_acceptable | Align G.2 to execution.yaml; cite as source of truth |
| 3a | auditor.md:135-140 (absent) | medium | M | Never reads execution.yaml quality_thresholds; parallel hardcoded scale | Load quality_thresholds, map into scoring |
| 3a/3d | auditor.md:114-120 (F.3) | high | M | No AC-match/sub-clause assertion despite being canonical home (#12/#13) | Add F.3 AC-match check incl sub-clauses |
| 3d | auditor.md:128-179 | medium | M | #9 cross-section drift + #5 docs_only-SKIP-bypass not propagated | Add Process check for SKIPped real-AC steps |
| 3b | auditor.md:352-372,439-456 | low | S | H.5/I.4 report templates duplicate Output Format | Collapse to single Output Format ref |
| 3b | auditor.md:284 | low | S | Baseline table "(v2)" soft version-stamp | Drop; move to CHANGELOG |
| 3c | auditor.md:8 | low | S | Single stale date stamp | Bump when categories change |

## agents/project-scanner.md (1100) — PASS_WITH_NOTES
1100 lines justified by tri-modal scope. Budget caps internally consistent + match integrations.yaml.

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a/3d | project-scanner.md:52,186,...,1054-1069 + integrations.yaml:38 | HIGH | M | Raw qdrant-store/find throughout; conflicts CLAUDE.md vulcan-memory mandate | PM adjudicate; migrate or carve-out |
| 3a | project-scanner.md:192 | LOW | S | "summary MUST be >=20 words" unverifiable hard MUST for LLM | Reframe as guidance or cite enforcing gate |
| 3b | project-scanner.md:241-678 | MED | M | 10 category blocks (~440 lines) share identical skeleton | Optional: category template + per-category cue table |
| 3b | project-scanner.md:19-27 vs 162-186 | LOW | S | Embedded role-card duplicates prose Identity/Constraints | Trim one to a pointer |
| 3c | project-scanner.md (whole) | INFO | — | No version-stamps/TODO/(planned) skeletons | None |

## agents/curator.md (186) — PASS_WITH_NOTES

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a/3d | curator.md (whole) | high | S | Learning #21 (4 auto-fix classes) absent; doc covers auto-approval not auto-FIX scope | Add "Auto-Fix Scope (4 classes)" near Phase 6 |
| 3d | role-cards (no curator card) + canonical-learnings:44 | high | M | #21 homed to role-cards curator card which doesn't exist → DROPPED | Place in curator.md; fix inventory touches_skill |
| 3a | curator.md:79,97 | medium | S | curator_auto_rules duplicated execution.yaml + decision-policies.yaml; .aid-o copy lacks standards rules | Pick canonical; note mirror or deprecate |
| 3b | curator.md:8 | medium | S | Last Updated 2026-03-14 stale (P040 CP4 didn't bump) | Bump; add CP4 cross-ref |
| 3a | curator.md:121-147 | low | — | Output Format internally consistent | None |
| 3c | curator.md | low | — | Clean — no skeletons | None |

## agents/gate-fixer.md (199) — PASS_WITH_NOTES

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | gate-fixer.md:121-139 | HIGH | M | Output gate_fix_result lacks `_generated_by` (NR10/17 root cause of fabricated) | Add `_generated_by: aid-orchestrator:gate-fixer@<agent_id>` |
| 3a | gate-fixer.md:88-91 | MED | S | `allowed_paths` vs dispatch `step_forbidden_paths` term drift | Align; ref execution.yaml:150-153 |
| 3a | gate-fixer.md:34 | LOW | S | "Never downgrade findings" lacks failure-mode pointer | Add: caught at iteration-2 re-verify |
| 3c | gate-fixer.md:195-196 | MED | S | Dead "replaced in Run 4" roadmap skeleton | Remove (history in git) |
| 3c | gate-fixer.md:199 | LOW | S | Last Updated 2026-03-12 stale | Bump |
| 3d | gate-fixer.md:28-34 | MED | M | Omits auto_fix_severities:[critical,high] contract (review-checkpoints.yaml) | State dispatched-for severities; cite fix_loop |
| 3d | gate-fixer.md:11,187 | LOW | S | "all domains/no expertise" vs #21 scoped 4 classes | Optionally note 4 safe-fix classes |

## agents/implementer.md (16) — PASS_WITH_NOTES
16-line minimalism is deliberate house-style, not under-spec. Delegation verified correct.

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | implementer.md:13-16 | Medium | XS | Inline model block duplicates role-cards canonical `**Model:**` (Forbidden Pattern #3) | Replace with pointer to role card's Model field |
| 3a | implementer.md:5-11 | Low | — | Delegation chain verified complete | None |
| 3c | implementer.md:3 | Low | XS | Last Updated 2026-03-03 (oldest) | Bump only if 3a fix applied |

## agents/verifier.md (159) — PASS_WITH_NOTES
#4 PROPAGATED (L72 verifier@<agent_id>).

| dim | file:line | pri | eff | finding | recommendation |
|-----|-----------|-----|-----|---------|----------------|
| 3a | verifier.md:13-19 | High | S | Focus list names 6; role-cards defines qa+e2e too (8) | Add qa/e2e rows; reconcile count |
| 3a/3d #3 | verifier.md:71-75,142-159 | High | M | Output schema (nested) ≠ FSM-enforced flat template → FSM rejects | Point at verifier-output-template.md as source-of-truth or document both |
| 3a | verifier.md:54,71 | Medium | S | Prompt header restricts focus to (code-review\|security) but 7 focuses exist | Scope header to CP2/CP3 or generalize enum |
| 3d #15 | verifier.md (absent) | Medium | S | behavior-covered vs literal-AC + drift-report not propagated | Add re-verification check |
| 3c | verifier.md:26 | Low | S | `v2.18.0+` version label in heading | Demote to inline note |
| 3b | verifier.md (159) | Info | — | Tight band, correctly scoped | Keep tight |
