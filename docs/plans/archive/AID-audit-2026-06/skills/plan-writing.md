---
audit: P041
phase: 3 (pilot 1)
target: plugins/aid-orchestrator/skills/plan-writing.md
dimensions_emphasis: 3a, 3b, 3c
criteria_source: skill-writing-PROVISIONAL.md
status: draft (pre-L1)
generated: 2026-06-01
---

# Pilot 1 Audit — plan-writing.md

**Per-dimension summary:** 3a Content 6 (2 must, 3 should, 1 nice) · 3b Length 3 (1 should, 2 nice) · 3c Skeletons 4 (2 must, 2 should) · 3d Reflection 3 (2 should, 1 nice).

**Headline:** File predates skill-writing-PROVISIONAL.md (footer 2026-05-12; standard 2026-06-01) → grandfathering applies to structural-standard misses. But two real internal contradictions (3a-1, 3a-2) and four version-stamped headings (3c-1/2/3) are defects independent of the new standard and are the immediate fixes.

## Priority-ordered findings

| # | Dim | file:line | Priority | Effort | Finding | Recommendation |
|---|-----|-----------|----------|--------|---------|----------------|
| 3a-1 | 3a | L685/708/711 vs L117 | must-fix | S | Gate #20 enforces a plan-level `## Acceptance Criteria` section that the canonical Sections table (L101-118) never defines — it lists `## Success Criteria`. Hard gate enforces a section the structure spec doesn't tell the author to create. | Add `## Acceptance Criteria` to Sections table, or rename #20 to target `## Success Criteria`. Resolve which is canonical. |
| 3a-2 | 3a | L723-724 | must-fix | S | Completeness Gate "out of 27 (24 existing + 20a/b/c)" counts multi-part checks inconsistently (folds 17a-e silently, splits #20). Reader can't reconstruct 27. The count-drift class from learning #9. | State arithmetic inline + count parents/children uniformly, or drop the hardcoded total. |
| 3c-1 | 3c | L521 | must-fix | S | Version-stamped heading "CODEBASE GROUNDING (added v2.17.0 — addresses CP1...)" = Forbidden Pattern #1. | Rename to `CODEBASE GROUNDING`; stamp → CHANGELOG. |
| 3c-2 | 3c | L614 | must-fix | S | "STEP OUTPUTS CONCRETENESS (added v2.18.0...)" = Forbidden Pattern #1. | Rename; stamp → CHANGELOG. |
| 3c-3 | 3c | L630/681 | should-fix | S | "DESIGN DEFEAT DETECTION (added v2.20.0...)" + "PLAN-AC EXECUTABLE VERIFICATION (added 2026-05 — P037...)" embed incident lists in headings. | Rename both; move P0NN attributions to CHANGELOG. After 3c-1/2/3: zero version-stamped headings (passes Gate check #8). |
| 3c-4 | 3c | L547-612, L688-706 | should-fix | M | 17a-17e + 20a-20c lettered sub-numbering sprawl; hard to renumber, caused the 3a-2 count drift. | Promote to flat numbers, OR restructure #17/#20 as one check + a "resource type → grounding command" sub-table. |
| 3d-1 | 3d | Completeness Gate (absent) | should-fix | M | Learning #9 (NR 16 cross-section consistency drift — the ⚑ P041 through-line) NOT propagated. Gate is entirely per-section; no check that counts/renames across sections agree. Highest-value missing learning, explicitly names this file. | Add a "CROSS-SECTION CONSISTENCY" gate group (step counts across markers/headers/restatements agree; entity names consistent across Data Model/API/Steps). Also fixes 3a-2. |
| 3d-2 | 3d | L207/213-218/318/350 | should-fix | S | Learning #8 (NR 14 self-reference) NOT propagated, and the file reproduces the hazard: `## Phase`/`### Step N` at column 0 inside ```` ```markdown ```` fences (the pattern that crashes aid-plan-to-epic.sh). | Add MUST rule: when a plan documents AID itself, never place `### Step N`/`## Phase`/`## EPIC` at column 0 inside code fences. |
| 3b-1 | 3b | whole file | should-fix | L | ~1029 lines, 2.3× Standard ceiling. Completeness Gate is 243 lines (24% of file); git history shows pure accretion (every recent commit ADDED a check, zero cuts). | Extract per-check "Empirical evidence: PNNN" paragraphs to CHANGELOG/rationale doc; restores gate to scannable checklist (~60-80 lines saved). |
| 3a-3 | 3a | L7-14, L1029 | should-fix | M | Missing standard sections vs skill-writing.md: no Purpose paragraph (has summary-style TL;DR), no "Do NOT invoke for", no line-2 `**Last Updated:**`. | Grandfathered — batch into next substantial revision, don't block. |
| 3a-5 | 3a | L101, L120-125 | should-fix | S | "14 sections in this order" not verifiable — 5 conditional sections + the AC ambiguity have no insertion-point guidance. | Specify where conditionals insert. |
| 3a-6 | 3a | L378-389 vs L240-280 | should-fix | S | Mandatory-fields table (10) vs per-step template (11, incl Visual Refs) don't cross-state mandatory/optional. | Add (optional) marker to template. |
| 3b-2 | 3b | L554-720 (7 places) | nice | M | "Empirical evidence" narratives inside gate checks are documentation, not instruction (§Instruction Style: history lives in git). | Move to CHANGELOG; keep `(see P035)` pointer. |
| 3b-3 | 3b | L14-39 | nice | S | TL;DR duplicates Invocation Modes content. | Collapse TL;DR to 3 lines. |
| 3d-3 | 3d | L416-421, L282-308 | nice | S | Learnings #12/#13/#14 (scope cuts / E2E substitution) partially propagated; sub-clause-drop detection is correctly mostly an auditor (pipeline) concern. | Low priority; ensure auditor-side carries sub-clause detection. |

**Accretion scan:** no TODO/FIXME/deprecated/obsolete markers (clean). Accretion is entirely in the Completeness Gate (version-stamped headings + lettered sub-checks).

## L1 verification (adversarial, 2026-06-01)
Independent verifier confirmed 3a-1, 3a-2, 3c-1, 3c-2 (4 of 4 plan-writing claims checked) — **0 refuted**. All cited file:line anchors resolved; the two contradictions and two version-stamped headings are real.

## Methodology validation note
Pilot 1 produced findings in all of 3a/3b/3c (its emphasis) plus a light 3d touch-check. The 3c grep patterns returned real matches (not legitimate-empty), and the 3a contradictions were found by end-to-end read, not grep. Methodology behaves as designed.
