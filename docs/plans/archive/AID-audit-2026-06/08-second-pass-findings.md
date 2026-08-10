---
audit: P041
phase: 3 (second adversarial pass + L2 completeness critic)
artifact: second-pass-findings
status: draft
generated: 2026-06-01
note: re-analysis of the whole of Phase 3 — new findings, refutations of wrong first-pass findings, and audit-level coverage holes
---

# P041 Phase 3 — Second-Pass Findings + L2 Completeness

Marek requested a full re-analysis of Phase 3. Three adversarial re-audit agents
(5 files each) + one L2/completeness critic. As in Phase 1, the second pass found
new findings AND corrected wrong first-pass ones AND exposed scope holes.

## A. NEW findings (missed by first pass)

| file:line | dim | pri | finding | recommendation |
|-----------|-----|-----|---------|----------------|
| agent-protocol.md:9 vs :286 | 3c | HIGH | Header date `2026-05-13` ≠ footer `2026-05-31` (MUST Rule #2 violation); first pass missed entirely for this file | Set both to 2026-05-31 |
| memory.md:21 | 3a | HIGH | `cat state.yaml` claims fields `state/current_step/total_steps/gate_retries`; those live in `fsm-state.yaml`. `state.yaml` is a progress array (aid-epic-to-json.sh:807) | Point query at fsm-state.yaml or document the two-file split |
| run-management.md:63,78 | 3a | HIGH | Run ID format `R-{EPIC_ID}-{run_number}` (ex `R-005-1_4-1`) is unproducible; script emits `R-E{plan_num}-{phase}` (ex `R-E018-1`) | Correct format + frontmatter examples |
| verifier.md:71 vs template:20 vs aid-fsm.sh:330 | 3a | HIGH | CP4 filename collision: template says `verifier-output-cp4-curator.md`, FSM requires `...-curator-validation.md` → verifier writes wrong name, FSM never finds it (CP4 precondition fails) | Standardize on `-curator-validation.md` across template + verifier.md; add CP4 to verifier.md L71 output list |
| curator.md:91 vs :21-22 + pipeline.md:936 | 3a | HIGH | Phase 5 says curator "dispatch fix agent"; Identity says curator does NOT modify code + Orchestrator evaluates proposals; pipeline.md:936 has Orchestrator dispatch gate-fixer | Reword Phase 5: curator hands proposal to Orchestrator (propose-only) |
| implementer.md:13-16 | 3a | HIGH | Model-tier block omits `security`/`release`/VULCAN roles role-cards defines → those silently fall to default sonnet, masking role-cards' explicit tiers | Replace enumerated block with pointer to role card's `**Model:**` (also fixes Forbidden Pattern #3) |
| memory-mcp.md:91 vs integrations.yaml | 3a | HIGH | First-pass said "add 0.85 to yaml"; the 0.85 in yaml is under `knowledge` section, NOT `memory` (which has no dedup threshold). Skill's 0.85 is genuinely un-sourced for memory | Add `dedup_threshold` under `memory`, don't reuse knowledge value |
| auditor.md:490-491 | 3a | MED | Memory Health (J) uses a THIRD scoring scheme (0-20 ×5) inconsistent with global "start at 100, deduct per severity" (L537) — first pass caught L50-vs-L539 but missed J | Convert J to start-at-100/deduct, or carve out explicitly |
| planner.md:129,230 | 3a | MED | Cites model-tier source `defaults/policies/role-cards.md` — path doesn't exist (real: `skills/role-cards.md`) | Fix path (and per first pass, delete the model claim — script emits none) |
| gate-fixer.md:171 | 3c | MED | Dangling reference "from retry-engine dispatch" — no retry-engine exists (planned-but-never-built per pipeline.md:1206); real dispatcher is pipeline Task tool (its own L13) | Change to "from pipeline.md fix-loop dispatch (Task tool)" |
| verifier.md:9 vs agent-protocol.md:67 | 3a | MED | verifier.md says "follow agent-protocol Output format exactly", but that section is the *implementer* AGENT OUTPUT block — inapplicable to verifier | Scope L9 to Input only; point output at verifier-output-template.md |
| curator.md:14 | 3d | MED | Curator unaware its proposals get a CP4 verifier re-review (pipeline.md:914,929) | Add CP4 re-review note |
| brainstorming.md:330 vs :331 | 3a | MED | Internal: L330 "reuse review_result enum unchanged" then L331 narrows to `critical\|low` — claims "unchanged" while changing it | State full 4-level enum or say "uses only critical/low of shared enum" |
| role-cards.md:408-456 | 3a | LOW | VULCAN roles lack `Max Parallel` → undefined fan-out bound when dispatched in a wave | Add `Max Parallel: 1` default (esp. sql-isolation) |

## B. REFUTATIONS / corrections of first-pass findings (prevented bad fixes)

| first-pass finding | verdict | correction |
|--------------------|---------|------------|
| role-cards "header '(7)' but 8 blocks exist → fix count" | **WRONG** | There ARE exactly 7 `## Focus:` cards. The "8th" is the bare `## e2e` orphan duplicate (L459). Count is correct; defect is the duplicate. "Fixing the count" would INTRODUCE an error. |
| verifier.md "omits qa AND e2e" | **PARTLY WRONG** | verifier.md DOES list `qa` (L16). It omits only `e2e`. |
| verifier.md output schema "FSM REJECTS the run" (HIGH) | **OVERSTATED → downgrade** | FSM only greps the flat header (`^_generated_by:`/`^classification:`/`^verdict:`), which verifier.md L71-75 DOES instruct correctly → compliant verifier passes. Real defect: internal dual-schema (flat header vs nested review_result), no reconciliation note. |
| gate-fixer "output lacks _generated_by = NR10/17 root cause" (HIGH) | **OVERSTATED → LOW** | No FSM/pipeline check consumes `gate_fix_result` provenance. Adding `_generated_by` addresses no real gap. Consistency-only. |
| auditor "two contradictory severity scales (live)" | **VALID, reframe** | L50 (10/5/2/1) is a dead/orphaned scale (nothing consumes it); L539 is the live one. Defect = dead scale, not live contradiction. Still fix (delete L50). |
| run-management "stale state.yaml" (flat stale-call) | **CONFIRMED w/ nuance** | FSM accepts `state.yaml` as legacy fallback (aid-fsm.sh:277); codebase is mid-migration (dual-file w/ precedence, E128). Add "migration in progress, both live" qualifier. |
| planner.md FAIL verdict | **CONFIRMED, if anything understated** | Every Script-Contract/Algorithm/Output claim verified wrong vs aid-epic-to-json.sh except the Kahn cycle-detection. Ground-up rewrite is right. |
| agent-protocol `*(planned)*` entries | **CONFIRMED correct** | Both verified accurate against scripts; pass Forbidden Pattern #2. |
| memory.md:53 FSM-enforcement claim | **CONFIRMED correct** | aid-fsm.sh:1774-1793 requires the two Memory sections. |

## C. L2 completeness critic — audit-level coverage holes

1. **Commands (10 files) never quality-audited (biggest hole).** Phase 1 inventoried command enforcement (E35/36/37/79/80/81/82, E172-175) — 6+ commands carry live LLM-facing enforcement contracts (aid-do fix-loop, aid-research idempotency STOP) — but Phase-3 scope was "9 skills + 6 agents" and NO command got the 4-dimension audit. Exclusion never justified. → schedule Phase-3b command pass or justify.
2. **E87–E177 (~91 enforcements) unmapped AND unaudited.** Phase 2 mapped only E01–E86; >half the enforcement universe has no instruction-mapping verdict and no skill-audit cross-check. The audit is honest about it but 05's headline doesn't surface it as a coverage limit.
3. **Learning #11 never checked anywhere** (both homes — permissions.yaml + aid-setup.md — out of Phase-3 scope). Only learning with zero propagation verdict. Mark explicitly "not checked — homes out of scope."
4. **Non-skill learning-homes one-sided:** #7/#16 name aid-run.md (command, skipped); #8/#16/#19/#20 name scripts/execution.yaml (not content-audited). Their propagation verdicts cover only the skill half.
5. **Excluded files revisited:** setup/*.md (4), visual-companion/SKILL.md (carries E161 visual-anchoring gate), defaults/templates/design-sections.md (carries E177) — all enforcement-bearing, all unaudited. setup/ exclusion defensible but set-and-forgotten.
6. **Shallow audits → deeper pass candidates:** `project-scanner.md` (1100L, only 6 findings — thinnest per line) and `auditor.md` (770L, 8 findings — and it's the enforcement-critical scoring agent; its scoring-logic correctness under-examined).

## D. Cross-phase contradictions the synthesis glossed

- **Provenance both OVER-fires and UNDER-fires (must be shown together).** Phase 2 = CONTRADICTORY (enforcement hard-fails on "fabricated" which NR17 reframes as a ±60s timing false-positive → over-fires). Phase 3 = yq-disarm (block keys off `severity==blocking`; without yq the synthetic failure defaults advisory → silently UNDER-fires). Both true, opposite directions, compounding. 05 presented only the under-fire story.
- **state.yaml/fsm-state.yaml** is mid-migration (dual-file, both live with precedence), not a clean "fsm-state canonical / state.yaml stale" — audit's own E128 + planner 3a contradict the flat stale-call.

## E. Internal drift (05 master index)
- Count "~135" actually ~128 (sum of per-file column).
- **P2 (qdrant) names 2 files but it's 3+:** pipeline.md:251 (3a-3) is also a raw qdrant-find/store conflict — the PM decision's blast radius is wider than 05 states.
- E12 Phase-2 CONTRADICTORY finding absent from 05 synthesis (see D).

## Net
Second pass added ~14 new findings (5 HIGH), corrected/downgraded 4 first-pass findings (preventing bad fixes — esp. the role-cards count and the gate-fixer/verifier overstatements), and exposed that the audit's real scope was narrower than the headline implied (commands + half the enforcement universe unaudited). The planner.md FAIL is upheld and understated. The most material correction for the PM: the qdrant decision touches 3+ files, and the provenance mechanism is broken in BOTH directions.
