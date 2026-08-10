---
audit: P041
phase: 3 (fan-out) + L2 cross-section synthesis
artifact: skill-audit-master-index
status: draft-for-PM (PM-GATE-B input)
generated: 2026-06-01
covers: 15 files (2 pilots + 13 fan-out) × 4 dimensions
criteria: skill-writing-PROVISIONAL.md + 00-canonical-learnings.md
note: numbered 05 because 03=governance-recommendation, 04 reserved for decisions
---

# P041 Phase 3 — Skill/Agent Audit Master Index

Per-file 4-dimension audit of all 15 in-scope files (9 skills + 6 agents),
plus L2 cross-section synthesis. Each file audited by an independent agent;
pilots (plan-writing.md, pipeline.md) additionally L1-verified (10/10 citations
confirmed, 0 refuted).

## Headline

The audit's core thesis — **the instruction layer drifts from the enforcement
layer when nothing keeps them paired** — is now proven inside the skill content
itself, not just inferred. The most severe case: `planner.md` documents a
*fictional* script contract. Two systemic patterns (stale dates everywhere,
a qdrant-vs-vulcan-memory mandate conflict in two files) cut across the corpus.

## Per-file summary

| File | Lines | Verdict | Findings | Top finding |
|------|-------|---------|----------|-------------|
| skills/plan-writing.md (pilot) | 1029 | PASS_W_NOTES | 16 | `## Acceptance Criteria` enforced by Gate #20 but never defined in Sections table (3a-1) |
| skills/pipeline.md (pilot) | 1207 | PASS_W_NOTES | 12 | **must-fix:** fabricated-provenance block silently disarmed by missing `yq` (3d-1, L1-confirmed) |
| skills/brainstorming.md | 507 | PASS_W_NOTES | 8 | **must:** prior-work glob `.aid-o/epics/` (canonical is `.aid-o/tasks/`) → silently matches nothing; severity enum `critical\|low` vs role-cards `critical\|high\|medium\|low` |
| skills/role-cards.md | 492 | PASS_W_NOTES | 14 | **HIGH:** duplicate contradictory `e2e` cards (L315 vs L459); verifier.md lists 6 focuses but role-cards defines 8 |
| skills/agent-protocol.md | 286 | PASS_W_NOTES | 6 | **high:** version-stamped heading `## Tiered Severity Reference (v2.21.0)` (L197); NR7 verifier-output schema partially dropped |
| skills/run-management.md | 277 | PASS_W_NOTES | 6 | **HIGH:** stale `state.yaml` (canonical now `fsm-state.yaml`, L149); internal archive-path collision (L22 vs L153) |
| skills/memory-mcp.md | 289 | PASS_W_NOTES | 8 | **HIGH:** built on raw `qdrant-store/find` — conflicts CLAUDE.md vulcan-memory mandate; threshold drift vs integrations.yaml |
| skills/memory.md | 69 | PASS_W_NOTES | 8 | L53 enforcement claim verified correct vs aid-fsm.sh:1775; Czech typo "kondice"; missing N/A escape-hatch doc |
| skills/planner.md | 234 | **FAIL (content)** | 10 | **CRITICAL ×3:** wrong CLI, wrong EPIC input format (heading-blocks vs real table), fabricated wave/level algorithm — none match aid-epic-to-json.sh |
| agents/auditor.md | 770 | PASS_W_NOTES | 8 | **high:** two contradictory severity scales (L50 vs L539); TODO handling contradicts execution.yaml `max_todo_count:0` |
| agents/project-scanner.md | 1100 | PASS_W_NOTES | 6 | **HIGH:** raw `qdrant-store/find` throughout — same vulcan-memory mandate conflict |
| agents/curator.md | 186 | PASS_W_NOTES | 6 | **high:** learning #21 (4 auto-fix classes) homeless+dropped; `curator_auto_rules` duplicated across 2 yaml |
| agents/gate-fixer.md | 199 | PASS_W_NOTES | 8 | **HIGH:** output lacks `_generated_by` provenance (NR10/17 root cause); dead "replaced in Run 4" skeleton (L195) |
| agents/implementer.md | 16 | PASS_W_NOTES | 3 | medium: inline model block duplicates role-cards canonical `**Model:**` values |
| agents/verifier.md | 159 | PASS_W_NOTES | 6 | **HIGH:** focus list omits `qa`+`e2e`; output schema (nested) mismatches FSM-enforced flat template → FSM would reject |

**Totals:** ~128 findings across 15 files (first pass). 1 FAIL (planner.md), 14 PASS_WITH_NOTES. No file is clean; none except planner.md needs a ground-up rewrite.

> **Second-pass update (see [08-second-pass-findings.md](08-second-pass-findings.md)):** a full re-analysis added ~14 new findings (5 HIGH) and **corrected 4 first-pass findings** — notably the role-cards "(7) vs 8" count finding was WRONG (there are exactly 7 Focus cards; the defect is the duplicate e2e orphan), verifier.md omits only `e2e` (it does list `qa`), and the gate-fixer `_generated_by` + verifier "FSM rejects" findings were OVERSTATED and downgraded. Read 08 alongside this index.

## L2 cross-section synthesis — 7 systemic patterns

These are the patterns that recur across files (the cross-section reviewer's job).
They matter more than any single finding because they point at process gaps, not
one-off mistakes.

### P1 — Doc-vs-code drift (MOST SEVERE; the P041 thesis, proven)
The instruction layer has drifted from the enforcement code in multiple files:
- `planner.md` (FAIL) — describes a CLI, EPIC format, and wave/level algorithm that **do not exist** in `aid-epic-to-json.sh`. Only the Kahn cycle-detection claim is accurate.
- `run-management.md` — still says `state.yaml`; pipeline.md made `fsm-state.yaml` canonical.
- `verifier.md` — documents a nested output schema that the FSM (which greps a flat line-anchored template) would **reject**.
→ This is exactly what the enforcement registry + sync-guard (governance Component 3) is designed to catch. **Strongest evidence yet for the governance recommendation.**

### P2 — qdrant-* vs vulcan-memory mandate conflict (needs PM adjudication)
`memory-mcp.md`, `agents/project-scanner.md`, **and `pipeline.md:251` (3a-3)** are
built on raw `qdrant-store`/`qdrant-find`, which the binding global+project
CLAUDE.md (B-051) **forbids** in favor of `vulcan-store`/`vulcan-find`. Note the
in-repo config (`integrations.yaml:38` + `aid-init.md:264`) actually agrees on
`qdrant-brain` — so the conflict is the *ecosystem* CLAUDE.md mandate vs the
plugin's own consistent config. Either the plugin legitimately targets a
consumer-project `qdrant-brain` tool (then it needs one explicit carve-out
sentence), or it migrates to vulcan-memory naming. **One PM decision, but it
touches 3+ files + integrations.yaml** (second pass corrected the earlier "2 files").

### P3 — Systemic freshness debt
Almost every file has a stale `Last Updated` (run-management/planner/implementer 2026-03-03; curator 03-14; gate-fixer 03-12; role-cards has a **mismatched pair** 03-16 header / 03-19 footer; memory-mcp 03-19; pipeline 05-13 with later P040 content). And **no skill carries the line-2 header date** that skill-writing.md mandates. Dates aren't bumped when rules change.

### P4 — Version-stamped headings (Forbidden Pattern #1, widespread)
plan-writing.md (3+), pipeline.md (11), agent-protocol.md (1), brainstorming.md (1). The accretion pattern skill-writing.md names is the single most common skeleton across the corpus.

### P5 — Dropped reflection learnings (propagation is weak)
Recurring NOT-PROPAGATED-DROPPED: #21 (curator 4 auto-fix classes — homeless: role-cards has no curator card, curator.md omits it); #15 (behavior-covered vs literal-AC — dropped in both verifier.md + role-cards); #10/#20 (qa mock-diagnostic + env gotchas — dropped in role-cards qa card); #5/#17 (inline-mode provenance, file-ownership — dropped in pipeline.md). The reflection→skill pipeline leaks — exactly what skill-writing.md §Reflection Propagation + reflection-prompt Sekce 9 (Phase 4c) target.

### P6 — Internal contradictions within single files
auditor.md (two severity scales), brainstorming.md (severity enum + wrong glob), role-cards.md (duplicate e2e card), memory-mcp.md (filter-support claim contradicts its own example). The class learning #9 (cross-section drift) predicted.

### P7 — Missing standard structure + 4-part contracts (grandfathered, systemic)
Most skills predate skill-writing.md and lack When-to-Invoke / MUST Rules / Completeness Gate sections, and state enforcement rules as bare imperatives without trigger/failure/fix. Real but grandfathered — converge on next substantial edit, don't treat as regressions.

### P8 — Provenance enforcement is broken in BOTH directions (added second pass)
The fabricated-provenance check is the single most-severe recurring incident, and
the two audit phases found it failing in **opposite** directions:
- **Over-fires (Phase 2, E12 CONTRADICTORY):** enforcement hard-fails on
  `provenance_aggregate==fabricated`, but NR17 reframes "fabricated" as a ±60s
  timing false-positive (commit time lags dispatch) — genuine reviews get flagged.
- **Under-fires (Phase 3 pilot 3d-1, L1-confirmed):** the review→release block keys
  off `severity=="blocking"`; on a host without `yq` the synthetic failure defaults
  to advisory → the block silently does NOT fire, and a fabricated-provenance
  self-merge passes.
Both compound: the check that over-flags honest runs is the same check that can be
silently disarmed. **These must be presented to the PM together** — fixing one
without the other leaves the mechanism broken the other way.

## Coverage limits (be honest with PM — added second pass / L2 critic)

The 15-file audit is thorough *within its declared scope*, but the scope is
narrower than the headline implies:
- **Commands (10 files) were never quality-audited.** 6+ carry live LLM-facing
  enforcement (aid-do fix-loop, aid-research idempotency STOP, aid-status duplicate
  reject). The skill/agent audit skipped the entire command surface without stating
  why. → Phase-3b command pass recommended.
- **~91 enforcements (E87–E177) are unmapped and unaudited** — over half the real
  enforcement universe has no Phase-2 verdict and no Phase-3 cross-check.
- **Canonical learning #11 was never checked** (both homes — permissions.yaml +
  aid-setup.md — out of scope). Non-skill learning homes (scripts, execution.yaml)
  got only their skill half verified.
- **Excluded-but-enforcement-bearing:** setup/*.md (4), visual-companion/SKILL.md
  (E161 gate), design-sections.md (E177) — unaudited.
- **Shallow first-pass files:** project-scanner.md (1100L, 6 findings) and
  auditor.md (770L, the enforcement-critical scoring agent) warrant a deeper pass.

## skill-writing.md — external review verdict

Independent (curator-agent) external review: **APPROVE-WITH-CHANGES.** Found 4
blocking self-consistency issues that must be fixed before the standard goes
binding:
1. The file is **462 lines — over its own 450 ceiling** (MUST Rule #9 / Gate #5 self-fail).
2. Cites pipeline.md/plan-writing.md/agent-protocol.md as canonical references, but all three **fail its own gate** → needs an explicit **Grandfathering/Migration section** (else the first audit run floods the PM with structural noise on every existing file).
3. Gate check #14 can't pass for type-12/13 (skill-loaded/agent-contract) enforcements → needs an N/A carve-out.
4. Band-classification ("Tight" vs "Standard") is subjective → needs a deterministic rule.
Plus ~13 medium/low items (audience definition, MUST-vs-SHOULD audit consequence, whole-skill deprecation lifecycle, the duplicated type→home table). Full list lives in the review (recorded in this session's transcript; fold into Phase 4b-final).

## Recommendations (priority order, for Phase 5 decisions)

1. **PM adjudicate P2** (qdrant vs vulcan-memory) — one decision, unblocks 3 files.
2. **planner.md rewrite** (FAIL) — ground-up against the real table-based, manifest-emitting, wave-less script. Highest-value single fix; it actively misleads any agent reading it.
3. **pipeline.md 3d-1** (yq-disarm of the provenance block) — document the operational precondition; it's the most-severe *enforcement* gap, even if not a doc-only fix.
4. **Fix skill-writing.md's 4 blockers + add Grandfathering section** before adopting it as binding (Phase 4b-final).
5. **Batch the freshness (P3) + version-stamp (P4) cleanups** — mechanical, low-risk, do together.
6. **Reflection propagation (P5)** — resolve homeless learning #21; wire reflection-prompt Sekce 9 (Phase 4c) so this stops recurring.

## Verification status
- L1: pilots verified (10/10 confirmed). Fan-out: each file audited by an independent agent; cross-file claims (verifier.md focus count, qdrant conflict, planner.md script mismatch) were cross-checked against source by the auditing agents.
- L2: this synthesis IS the cross-section pass (done by orchestrator over all 15 reports). An additional independent L2 dispatch is optional extra rigor if PM wants it before PM-GATE-B sign-off.
- L3: PM (pending).
