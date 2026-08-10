---
audit: P041
phase: 4b-pre (external review of provisional skill-writing.md)
artifact: skill-writing-external-review
status: recorded
generated: 2026-06-01
reviewer: independent curator-agent (author-blind external critique)
verdict: APPROVE-WITH-CHANGES
target: docs/plans/AID-audit-2026-06/skill-writing-PROVISIONAL.md
---

# External Review — skill-writing.md (PROVISIONAL)

Independent skeptical review against (a) general technical-writing best practice
and (b) the file's own self-consistency claim. **Verdict: APPROVE-WITH-CHANGES.**
No fundamental design flaws; a cluster of self-consistency failures + rule-quality
gaps must be fixed before the standard goes binding.

## Priority 1 — Blocking (the standard violates its own gate)

| # | Location | Problem | Fix |
|---|----------|---------|-----|
| 1.1 | MUST Rule #9 / Length table | File is **462 lines — over its own 450 ceiling**; fails Gate check #5 + MUST #9 on its own terms | Compress below 450 (Examples section is most compressible) OR reclassify as Reference band + update "Practical targeting" |
| 1.2 | Freshness / MUST #2 / Gate #3 | `pipeline.md` (cited canonical reference) has no line-2 header `Last Updated` → every auditor reports a finding on the most-used skill | Add grandfathering clause: existing skills need not retro-add header date unless >25% revised |
| 1.3 | Structure / MUST #1 / Gate #4 | `plan-writing.md` (cited as Completeness-Gate reference) has no `## MUST Rules` / `## Completeness Gate` top-level sections | Same grandfathering clause; note plan-writing is pre-standard, not conformant exemplar |
| 1.4 | Forbidden Pattern #1 / MUST #5 | `agent-protocol.md:197` has version-stamped heading `## Tiered Severity Reference (v2.21.0)` — a cited canonical home that is a documented violator | Same grandfathering clause; or "existing stamps retired on next substantive revision" |

**The four blocking items share one fix: an explicit Grandfathering/Migration section.** Without it, the first audit run after adoption floods the PM with structural noise on every existing file.

## Priority 2 — Rule quality (uncheckable / disagreement risk)

| # | Location | Problem | Fix |
|---|----------|---------|-----|
| 2.1 | Length Guidelines | Band classification ("Tight" vs "Standard") subjective; bands overlap; no decision rule | Add: "Tight = single interaction pattern, no sub-types; Standard = multiple rules / 2+ roles / requires a gate; when in doubt, Standard" |
| 2.2 | MUST #4 / Forbidden #3 | No carve-out for a downstream skill restating a constraint in its own actor's terms → false DUPLICATION findings | Add: downstream may restate with "See also: [canonical home]" without it being duplication |
| 2.3 | Completeness Gate #14 | Type-12 (skill-loaded) / type-13 (agent-contract) instructions have no external mechanical check → always fail #14 | Add N/A guidance: "type-12/13 — enforcement IS the loaded skill; mark N/A" |

## Priority 3 — Best-practice gaps

| # | Location | Problem | Fix |
|---|----------|---------|-----|
| 3.1 | Purpose | No audience definition (human author vs LLM auditor) | One sentence naming both audiences + which sections serve which |
| 3.2 | Completeness Gate | No mechanical-vs-judgment check classification → LLM auditor treats judgment checks as binary | Split: mechanical (1,2,3,5,7,8,9) vs judgment (4,6,10-15) |
| 3.3 | Frontmatter | `status: provisional` removal protocol undefined (structurally identical to the `(planned)` ORPHAN it forbids) | Require plan-ID comment when set (file already does this on L5 — make it a rule) |
| 3.4 | Instruction Style | MUST vs SHOULD audit consequence undefined | "MUST violation = gate failure; SHOULD violation = advisory; deviate with documented reason" |
| 3.5 | Freshness | No whole-skill deprecation lifecycle (only section-level) | Add `status: deprecated` + replacement-pointer rule; keep file (don't delete) |

## Priority 4 — Practicality

| # | Location | Problem | Fix |
|---|----------|---------|-----|
| 4.1 | Standard Structure | 9 mandatory sections add 30%+ overhead to Tight (80-line) skills — mandated padding | Allow Tight skills to collapse MUST Rules + Completeness Gate to one-line attestations referencing skill-writing.md |
| 4.2 | (absent section) | Grandfathering story implicit → first audit = structural noise on all existing files | Add explicit §Migration & Grandfathering (relaxed criteria for pre-standard skills until >25% revision) |

## Priority 5 — Minor
- 5.1 type→home table duplicated from 03-governance-recommendation.md without explicit waiver (make duplication intentional + cite canonical-on-conflict, or move to enforcement-registry.yaml header).
- 5.2 "Candidate Principle #5" is an unanchored draft reference (note provisional-statement-if-absent).
- 5.3 "Last Updated on line 2" is literally false when frontmatter present (reword to "immediately after H1, before first ---").

## Disposition
All Priority-1 items + the cheap Priority 2-4 items should be resolved in the Phase-4b-final editing pass before skill-writing.md is adopted as binding. Priority 5 deferrable. The standard is sound in concept; it needs to practice what it preaches and add a grandfathering on-ramp.
