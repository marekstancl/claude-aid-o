---
id: P041
type: plan
status: draft
created: 2026-06-01
author: PM + AI
---

# P041 — Enforcement-vs-Instruction Audit + Skill Quality Audit

## Stakeholder Brief

P041 audituje alignment mezi **enforcement vrstvou** (FSM preconditions, gates, dispatch wrappers, structural checks v aid-orchestrator pluginu) a **instruction vrstvou** (skill + agent dokumenty). Plus auditní obsah a strukturu všech 9 top-level skills + 6 agents napříč 4 dimenzemi: content quality, length, historical skeletons, reflection incorporation.

**Motivace:** Brainstorm P041 sám empiricky prokázal pattern — `brainstorming.md` skill obsahuje validate-then-verify protokol (RULE 9-12) ale orchestrátor ho při draftu sekcí systematically nepoužil, což vedlo k 100% finding rate při post-hoc verifier reviews. Tento pattern — *instruction without enforcement causes drift* — je hypotéza, kterou audit ověří širším measurement.

**Co plán produkuje:**
- Enforcement-instruction mapping (~100 file Phase 1 inventory + ALIGNED/GAP/ORPHAN/CONTRADICTORY/UNREACHABLE verdicts)
- Per-file audit (15 skills/agents × 4 dimensions)
- Candidate Principle #5 "Enforcement without Instruction is Cargo Cult" v Future principle slots
- NEW skill `skill-writing.md` (eat-own-dogfood — how to write/maintain skills)
- Reflection-to-skill propagation update (Sekce 9 v post-plan-reflection-prompt)

**Co NEPRODUKUJE:** Žádný code change. Žádný immediate fix. Audit doporučuje; implementace fixes je manuální mimo AID pipeline (PM rozhodnutí).

**Klíčová rizika:** Audit-recommendation-stagnation (High, recurring — 97.5% prior plans stuck at status:draft per AID-v3-roadmap evidence), audit findings overwhelm PM (Medium-High — 60 file-dimension audits), audit output meta-drift (Medium-High — same drift classes mohou propagovat do audit reportů).

## Context

Tento brainstorm byl trigger-ován PM otázkou „co máme za enforcementy a jsou podpořeny instrukcemi?". Při draftu Step 5 design jsem (orchestrátor) opakovaně driftoval — nepoužil jsem brainstorming.md RULE 9-12 (validate-then-verify cycle) pro vlastní sekce, což verifier post-hoc identifikoval u **každé** sekce: §1 FAIL (file count 11 wrong, CP namespace collision), §2 FAIL (~40% inventory missing), §4 FAIL (NR count "1-17" wrong, 3c patterns returned zero), §5 FAIL (Principle #5 promotion contradicted global gate), §6 FAIL (PM-GATE-C undefined, timebox missing), §7 FAIL (severity vocabulary drift), §8 FAIL (CHANGELOG missing, subdir convention), §9 FAIL (focus names informal).

**Pattern:** Skill instructions exist ale enforcement neexistuje → drift každý draft, predictably. Direct empirical evidence pro Principle #5 candidate.

Roadmap anchor: P042 (Plan-writing hardening bundle z `docs/plans/AID-v3-roadmap.md:41`) řeší related but distinct concern (plán format gate). P041 = enforcement-instruction alignment broader scope.

## Goal

Produkovat audit findings + meta-structure (new principle candidate + skill template + reflection propagation rule), které documentují current enforcement-vs-instruction alignment state a poskytují forward-looking rules pro maintenance.

## Scope

### In-scope

**Audit targets (Phase 1 enforcement inventory):**
- `plugins/aid-orchestrator/scripts/*.sh` (18 files) + `scripts/lib/*` (4) + `scripts/gates/*` (1: scope-check.sh) + `scripts/tests/*` (18+)
- `plugins/aid-orchestrator/defaults/*.yaml` (5 root) + `defaults/policies/*.yaml` (2) + `defaults/templates/*` (13) + `defaults/standards/*` (2) + `defaults/execution-stacks/*` (5) + `defaults/hooks/*` (2)
- `plugins/aid-orchestrator/skills/*.md` (9 top-level + 5 nested) + `agents/*.md` (6) + `commands/*.md` (10)

**Per-file audit (Phase 3 — 15 files):**
- 9 top-level skills: `agent-protocol.md`, `brainstorming.md`, `memory-mcp.md`, `memory.md`, `pipeline.md`, `plan-writing.md`, `planner.md`, `role-cards.md`, `run-management.md`
- 6 agents: `auditor.md`, `curator.md`, `gate-fixer.md`, `implementer.md`, `project-scanner.md`, `verifier.md`

**Internal docs (cross-referenced):**
- `docs/plans/AID-v3-principles.md` (4a: candidate #5 add)
- `docs/plans/AID-post-plan-reflection-prompt.md` (4c: Sekce 9 add)
- `docs/plans/AID-v3-architectural-inventory.md` (4d: #5 cross-link updates)
- `docs/plans/AID-v3-agents-outputs.md` (4e: NR 17 §4D annotation)
- `docs/plans/AID-v3-roadmap.md` (4f: P041 entry rewrite)

### Out-of-scope

- `skills/setup/*.md` (4 files: claude-md, integrations, permissions, project-scan) — config templates pro /aid-init phase, ne running-time skills
- `skills/visual-companion/SKILL.md` — separate workflow, may add as follow-up
- Any code change — audit produces recommendations only
- Re-validation of P040 dispatch protocol — separate concern (AID-038 Phase 4 = follow-up)
- Tier 3 platform-level provenance (transcript JSONL cross-reference) — AID-044 reserved follow-up

## Approach

**Approach B (Pragmatic) — selected at Step 4:**

- **Pilot-then-fan-out cadence** s 3 PM-GATEs
- **Parallel Agent dispatches** (NOT Workflow tool) — batched 3-4 paralelně
- **Per-file outputs** + master index v `docs/plans/AID-audit-2026-06/` subdir
- **3-layer verification stack:** L1 section-review (sampled ~30%), L2 cross-section-review, L3 PM spot-check
- **Brainstorm dispatch opt-out** of P040 stage-log per brainstorming.md RULE 9 (no FSM run in audit context)

**Rejected alternatives:**
- Approach A (Conservative manual sériový) — over-conservative, mega-doc unfriendly
- Approach C (Workflow tool) — requires explicit Workflow opt-in, high token cost

## Architecture

### Phase flow

```
┌─────────────────────────────────────────────────────────────┐
│ Pilot block                                                  │
│  Phase 1 (enforcement inventory, ~100 files) →               │
│  Phase 2 (enforcement-to-instruction mapping, 5 verdicts) → │
│  Phase 4b-pre (provisional skill-writing.md, researcher      │
│    agent + PM sign-off — runs BEFORE Phase 3 because         │
│    serves as criteria source) →                              │
│  Phase 3 pilot:                                              │
│    • plan-writing.md (3a/3b/3c emphasis)                     │
│    • pipeline.md (3d reflection density emphasis)            │
│       │                                                      │
│       ▼ PM-GATE-A EXIT CRITERIA:                             │
│         - Phase 1 inventory ≥30 enforcements                 │
│         - Phase 2 mapping covers ≥80% Phase-1 entries        │
│         - Pilots collectively produce findings spanning      │
│           all 4 dimensions                                    │
│         - L1 agent review: no critical methodology errors    │
│         - 4b-pre draft + PM sign-off                          │
├─────────────────────────────────────────────────────────────┤
│ Fan-out block (Phase 3 rest)                                 │
│  13 files audited via parallel Agent dispatches              │
│  batched 3-4 parallel                                        │
│       │                                                      │
│       ▼ PM-GATE-B EXIT CRITERIA:                             │
│         - 13 files audited                                   │
│         - L1 verification sampled ~30% (≥4 files)            │
│         - L2 cross-section consistency report:               │
│           no critical conflicts                              │
│         - PM read master index + per-file findings           │
├─────────────────────────────────────────────────────────────┤
│ Synthesis block (Phase 4 rest + Phase 5)                     │
│  Phase 4a candidate principle drafted                        │
│  Phase 4b-final (refined skill-writing.md)                   │
│  Phase 4c reflection prompt update (Sekce 9)                 │
│  Phase 4d inventory cross-link updates                       │
│  Phase 4e NR 17 §4D annotation                                │
│  Phase 4f roadmap P041 entry rewrite                         │
│  Phase 5 discussion items ALL resolved                       │
│       │                                                      │
│       ▼ PM-GATE-C EXIT CRITERIA:                             │
│         - All Phase 4a-4f deliverables complete              │
│         - Phase 5 zero open items                            │
│         - PM ship/iterate decision                           │
└─────────────────────────────────────────────────────────────┘
```

**PM-GATE naming note:** PM-GATE-A/B/C jsou brainstorm/audit gates, distinct from pipeline.md's canonical CP1..CP6 review-checkpoint namespace. Different concept; renamed to prevent silent collision.

**Mapping 3 PM-GATEs → phases:**
- PM-GATE-A = end of (P1 + P2 + P4b-pre + P3-pilot)
- PM-GATE-B = end of P3-fan-out
- PM-GATE-C = end of (P4-rest + P5)

### Enforcement type taxonomy (15 categories)

1. FSM-precondition · 2. Hard-gate · 3. Dispatch-wrapper · 4. Structural-check · 5. Pre-filter-regex · 6. Schema-validator · 7. Command-orchestration-rule · 8. Hook-enforcement · 9. YAML-policy-driven · 10. Template-shaped · 11. Audit-log invariant · 12. Skill-loaded-protocol · 13. Agent-contract · 14. Test-regression-gate · 15. Stack-gate-binding

### Verdict types (mapping, 5 categories)

- **ALIGNED** — instruction matches enforcement
- **GAP** — enforcement exists, instruction missing
- **ORPHAN** — instruction exists, enforcement removed/changed
- **CONTRADICTORY** — both exist but disagree
- **UNREACHABLE** — enforcement code present but never triggered (dead path)

## Data Model

**Source of truth:** Markdown audit reports (`01-enforcement-inventory.md`, `02-mapping.md`, `03-skill-audit.md`, per-file outputs). The YAML schemas below are illustrative — they describe the conceptual finding/mapping shape that each Markdown entry follows. Markdown is the canonical format because audit is for human PM review, not automated consumption.

**Vocabulary table:**

| Source | Field | Values | Purpose |
|---|---|---|---|
| `defaults/check-severity.yaml` | `severity` | `blocking, advisory` | Gate enforcement decision |
| P041 audit finding | `priority` | `must-fix, should-fix, nice-to-have` | Recommendation strength |
| P041 mapping | `verdict` | `ALIGNED, GAP, ORPHAN, CONTRADICTORY, UNREACHABLE` | Mapping state |

**Priority → Phase 5 outcome:** must-fix → apply-now · should-fix → inventory-item · nice-to-have → rejected/deferred

### Audit finding schema

```yaml
finding:
  id: "audit-{file_stem}-{dimension}-{seq}"      # e.g., audit-plan-writing-3c-001
  audit_run_id: "p041-phase3-2026-06-DD"          # disambiguates runs
  _generated_by: "p041-audit:phase3"               # provenance per Principle #1
  file: "plugins/aid-orchestrator/skills/plan-writing.md"
  dimension: "3a | 3b | 3c | 3d"
  priority: "must-fix | should-fix | nice-to-have"
  effort: "small | medium | large"                 # informs Phase 5 decisions
  finding: "..."
  evidence:
    - tool: "grep"
      file: "plan-writing.md"
      lines: "245-310"
      query: "[0-9]+[a-e]"
      result: "5 matches: 17a (L246), ..."
  reflection_ref: null                             # "NR 17" or "NR 17 §4D"
  recommendation: "..."
  follow_up_class: "apply-now | inventory-item | rejected | promote-candidate | approve-draft"
  implementation_status: "pending | in-progress | done | wontfix"   # added for §10 risk #4 mitigation
```

### Enforcement-instruction mapping schema

```yaml
mapping:
  enforcement_id: "gates_generated_by"           # snake_case matching check-severity.yaml
  enforcement_type: "FSM-precondition"
  enforcement_file: "aid-fsm.sh:622"
  enforcement_description: "..."
  expected_instruction_file: "skills/pipeline.md"
  expected_instruction_section: "Dispatch Protocol (P040, v2.25.0+)"
  expected_instruction_line: 464
  verdict: "ALIGNED | GAP | ORPHAN | CONTRADICTORY | UNREACHABLE"
  evidence:
    - tool: "grep"
      file: "skills/pipeline.md"
      lines: "464-510"
      query: "_generated_by"
      result: "0 matches"
  reflection_ref: null                            # any mapping may cite
  recommendation: "..."
  implementation_status: "pending | in-progress | done | wontfix"
```

### ID format conventions

- **Audit finding ID:** kebab-case, `audit-{file_stem}-{dimension}-{seq}` (file_stem = basename without `.md`)
- **Enforcement ID:** snake_case matching `defaults/check-severity.yaml` keys (e.g., `gates_generated_by`, `verifier_provenance`); kebab-case reserved for audit-discovered enforcements without existing check-severity entry

### Reflection_ref format

- `"NR N"` (space, matches 18 codebase usages in agent-outputs.md)
- Optional sub-anchor: `"NR 17 §4D"`
- **Available on ANY finding/mapping** (not restricted to dimension=3d)

## Implementation Steps

### Step 1: Phase 1 — Enforcement inventory

**Objective:** Flat-list všechny enforcement mechanismy v plugin distribution s file:line anchory; output ~50+ entries spanning 15 enforcement types.

**Files:**
- Create: `docs/plans/AID-audit-2026-06/01-enforcement-inventory.md` — flat table per-enforcement (file:line, description, type)

**Architecture Context:** Phase 1 establishes the *universe* of enforcement mechanisms. Phase 2 (Step 2) maps each to expected instruction location. Phase 3 (Step 3) audits per-file content quality. Phase 1 inventory is broader (~100 files) than Phase 3 audit scope (15 files).

**Implementation Detail:** Orchestrátor reads source code in target adresářích per batched per-directory passes (context window risk mitigation). For each enforcement found: extract `file:line`, short description, type (one of 15). After own pass, dispatches independent agent with adversarial prompt ("najdi enforcement, které jsem missed"). Reconciles + merges into final inventory table.

Target directories: `scripts/`, `scripts/lib/`, `scripts/gates/`, `scripts/tests/`, `defaults/` (root + 5 subdirs), `skills/` (top-level + nested), `agents/`, `commands/`.

**Error Handling:** Pokud independent agent finds enforcement that orchestrator missed, both findings preserved s notation "orchestrator-missed, agent-found"; reconciliation step manual review.

**Edge Cases:**
- File contains enforcement that doesn't fit any of 15 types → log s `type: uncategorized` for Phase 5 discussion
- Single file contains multiple enforcement types → multiple entries per file with distinct IDs
- Enforcement spans multiple files (e.g., compliance.json writer + reader) → single entry with primary file as anchor + cross-refs

**Dependencies:** No dependencies — entry point of audit work.

**Acceptance Criteria:**
- [ ] Inventory ≥30 enforcements (PM-GATE-A floor; empirical baseline: plan-writing.md alone produces ~20+ enforcement-keyword matches depending on regex pattern — conservative floor for ~100-file universe)
- [ ] Each entry has `file:line` + description + type from 15-category taxonomy
- [ ] All 15 enforcement types have ≥1 example entry (coverage assertion)
- [ ] Independent agent verification produced ≤5% missed-enforcement findings on reconciliation

**Effort:** L (~100-file inventory across 7 directory groups; agent-verification reconciliation pass)
**AID Role:** docs

### Step 2: Phase 2 — Enforcement-to-instruction mapping

**Objective:** Pro každý Phase-1 enforcement identify expected instruction location + verify presence; produce mapping table s 5-verdict classification.

**Files:**
- Create: `docs/plans/AID-audit-2026-06/02-mapping.md` — per-enforcement mapping table + summary statistics (% ALIGNED / GAP / ORPHAN / CONTRADICTORY / UNREACHABLE)

**Architecture Context:** Phase 2 transforms Phase 1's inventory (`what enforces?`) into alignment verdicts (`is enforcement matched by instruction?`). GAP and CONTRADICTORY findings feed Phase 5 discussion + Principle #5 promotion criteria. UNREACHABLE findings flag dead code.

**Implementation Detail:** For each enforcement in inventory:
1. Identify expected instruction location via heuristics table (16 rows mapping enforcement type → target skill/agent file with pinned section anchors where available)
2. Grep target file pro instructional anchor (prose rule describing the behavior)
3. Per-entry verdict + evidence (grep command + output excerpt per EVIDENCE rule)
4. Independent agent dispatch (`focus=section-review`, NO P040 wrapper per brainstorming.md RULE 9 brainstorm opt-out) — verify random sample of 3-5 GAP + UNREACHABLE findings adversarially

**Heuristic anchor table (covers all 15 enforcement types — Step 1 AC #3 satisfaction):**

| # | Enforcement type | Expected instruction location |
|---|---|---|
| 1 | FSM-precondition (orchestrator) | `skills/pipeline.md` |
| 2 | FSM-precondition (subagent output) | `agents/verifier.md` OR `skills/agent-protocol.md` |
| 3 | Hard-gate orchestration | `pipeline.md` §13 (line 1143) |
| 4 | Hard-gate pre-filter patterns | `defaults/policies/review-checkpoints.yaml` `pre_filter.fail_patterns[]` |
| 5 | Pre-filter regex | `defaults/pre-filter-rules.yaml` + `pipeline.md` §13 reference |
| 6 | Structural-check (compliance aggregation) | `pipeline.md` compliance section |
| 7 | Schema-validator (plan) | `skills/plan-writing.md` |
| 8 | Dispatch-wrapper | `pipeline.md` §4 "Dispatch Protocol (P040, v2.25.0+)" (line 464) |
| 9 | Command-orchestration-rule | `commands/<cmd>.md` OR `pipeline.md` for cross-command |
| 10 | Hook-enforcement | `defaults/hooks/pre-commit`/`pre-push` themselves + `agent-protocol.md` git discipline as companion |
| 11 | YAML-policy-driven (check-severity) | `pipeline.md` + `agent-protocol.md` |
| 12 | Template-shaped (verifier-output-template) | `agents/verifier.md` Output Format section |
| 13 | Audit-log invariant | `agent-protocol.md` "P040 audit events" table (line ~253) |
| 14 | Skill-loaded-protocol | the skill itself |
| 15 | Agent-contract | `agents/<agent>.md` Output Format section |
| 16 | Test-regression-gate | corresponding `scripts/tests/test-<thing>.sh` |
| 17 | Stack-gate-binding | relevant `defaults/execution-stacks/<lang>.yaml` |

(Table has 17 rows because some types have multiple expected locations — coverage of all 15 enforcement types from §Architecture taxonomy is complete.)

**Error Handling:** Pokud heuristic location doesn't contain expected instruction AND no obvious alternative exists, mark as GAP (not "unable to verify"). Pokud heuristic returns CONTRADICTORY (instruction says X, enforcement does Y), surface as priority: must-fix.

**Edge Cases:**
- Multiple enforcement instances share same instruction file (e.g., 10 FSM preconditions all reference pipeline.md) → individual mapping entries, but recommendations may be consolidated in Phase 5
- Heuristic points to non-existent location (script was deleted) → UNREACHABLE verdict with note
- Instruction exists in MULTIPLE files (e.g., pipeline.md + agent-protocol.md both describe dispatch protocol) → ALIGNED if either is correct, ORPHAN if both are stale

**Dependencies:**
- Depends on: Step 1 — needs Phase 1 inventory as input
- Blocks: Step 3 (pilot) — Phase 3 audit references Phase 2 mapping for context

**Acceptance Criteria:**
- [ ] Mapping covers ≥80% of Phase 1 entries (PM-GATE-A criterion)
- [ ] All 5 verdict types have ≥1 example entry (vocabulary exercise)
- [ ] Independent agent verification on 3-5 GAP/UNREACHABLE findings clean
- [ ] Summary statistics computed (% per verdict)

**Effort:** L (17-row heuristic table × ~50+ enforcements mapped; 5-verdict classification; agent verification sample)
**AID Role:** docs

### Step 3: Phase 3 pilot — Per-file audit on plan-writing.md + pipeline.md

**Objective:** Stress-test 4-dimension per-file audit methodology on 2 pilot skills; produce pilot output files + L1 verification + PM-GATE-A approval to proceed with fan-out.

**Files:**
- Create: `docs/plans/AID-audit-2026-06/00-canonical-learnings.md` — pre-prep canonical learnings inventory (15 NR entries: NR 2-8, 10-17; NR 1 + NR 9 absent — + `lessons-learned.md` table rows + narrative section)
- Create: `docs/plans/AID-audit-2026-06/skills/plan-writing.md` — pilot 1 audit (3a/3b/3c emphasis)
- Create: `docs/plans/AID-audit-2026-06/skills/pipeline.md` — pilot 2 audit (3d emphasis)
- Create: `plugins/aid-orchestrator/skills/skill-writing.md` (PROVISIONAL — Phase 4b-pre runs HERE before Phase 3 audit work, drafted by researcher agent + PM sign-off; serves as criteria source for 3a/3b/3c audits)

**Architecture Context:** Pilot validates methodology before committing to fan-out cost. Plan-writing.md selected as pilot 1 because P040 5-CP1-passes evidence empirically anchors 3a/3b/3c stress-test. Pipeline.md selected as pilot 2 because high reflection density (touched by NR 8, 13, 17) stress-tests 3d operational rubric. 4b-pre (provisional skill-writing.md) drafted before pilot to provide audit criteria — chicken-and-egg resolution per Step 5 Fix 4.

**Implementation Detail:** Per-file methodology applied uniformly:

**Pre-prep (runs once):** Build canonical learnings inventory:
1. Extract 15 NR entries from `docs/plans/AID-v3-agents-outputs.md` (NR 1 + NR 9 absent — skip)
2. Extract `lessons-learned.md` entries (mixed format normalization: table rows = Lesson column as anchor+recommendation; narrative section = Issue+Recommendation)
3. Pre-filter classification: (a) plan-reflection (touch from PLAN VS REALITA prose), (b) standalone-observation (NR 11 example: `defaults/policies/permissions.yaml`), (c) infra/config (skip)
4. Dedupe overlapping items (same anchor + same recommendation)

**4b-pre researcher dispatch:** Agent dispatched with prompt: best-practice research (style guides, technical writing standards) + `plan-writing.md` parallel analysis → drafts provisional skill-writing.md with 13 content sections (Frontmatter, Purpose, When to invoke, Standard structure, Length guidelines, Freshness rules, Forbidden patterns, Instruction style, MUST Rules, Completeness Gate, Anti-Circumvention, Reflection propagation, Examples). PM sign-off required before becomes criteria source.

**Per-dimension audit (each pilot):**
- 3a Content quality — end-to-end read; structural integrity; cross-file consistency against role-cards.md / agent-protocol.md / pipeline.md
- 3b Length analysis — `git log --oneline -5 <file>` baseline comparator; flag sections grown without compensating cuts
- 3c Historical skeletons — grep calibrated patterns: `(added v[0-9.]+)`, `[0-9]+[a-e]( |\.|$)`, `\(P[0-9]+, v[0-9.]+\+\)`, `(force_override|deprecated|obsolete|TODO|FIXME|XXX)`, version-stamped section titles
- 3d Reflection incorporation — for each canonical learning (a)/(b): touch check, propagation check (PROPAGATED / NOT-PROPAGATED-DELIBERATE — search corpus = principles.md, CHANGELOG.md root + plugin, inline comments referencing NR / NOT-PROPAGATED-DROPPED)

**L1 verification (after each pilot):** Dispatch `Agent(aid-orchestrator:verifier, focus=section-review)` adversarial review of pilot output.

**Error Handling:**
- Pokud 3c grep patterns return 0 matches on healthy file → acknowledge legitimate-empty; methodology validation gate = "pilots collectively produce findings spanning all 4 dimensions" (plan-writing 3a/b/c + pipeline 3d), nepilot individually
- Pokud L1 agent finds critical methodology errors → loop back, refine methodology, re-run pilot before fan-out
- Pokud pre-prep canonical learnings inventory unwieldy (>50 entries) → priority-filter by impact OR split into per-skill sub-inventories

**Edge Cases:**
- Pilot 1 (plan-writing.md) produces 3d touches even though designated for 3a/b/c → OK, 3d auditor may run on both
- Pilot 2 (pipeline.md) doesn't touch NR 8/13/17 as expected → document explicitly proč not, validation still passes if produces non-empty 3d propagation table elsewhere
- Researcher agent (4b-pre) produces skill-writing.md that violates its own rules (self-violation) → flag to PM, may ship as `experimental` frontmatter flag pokud PM accepts

**Dependencies:**
- Depends on: Step 1, Step 2 — needs inventory + mapping context
- Blocks: Step 4 (fan-out) — methodology must be validated at PM-GATE-A before fan-out kickoff

**Acceptance Criteria (= PM-GATE-A exit criteria):**
- [ ] Phase 1 inventory ≥30 enforcements (delivered by Step 1)
- [ ] Phase 2 mapping covers ≥80% (delivered by Step 2)
- [ ] Pilots collectively produce findings spanning all 4 dimensions (plan-writing: 3a/b/c + pipeline: 3d)
- [ ] L1 agent review of each pilot: no critical methodology errors
- [ ] 4b-pre provisional skill-writing.md drafted + PM sign-off recorded
- [ ] PM read-and-approve methodology after pilot review

**Effort:** M (2 pilots stress-test methodology + canonical learnings pre-prep + 4b-pre researcher dispatch + L1 verification; methodology refinement loop possible)
**AID Role:** docs

### Step 4: Phase 3 fan-out — Per-file audit on 13 remaining files

**Objective:** Apply validated 4-dimension methodology to remaining 13 files (7 skills + 6 agents) via parallel Agent dispatches; produce per-file audit outputs + master index + L1/L2 verification.

**Files:**
- Create: `docs/plans/AID-audit-2026-06/skills/agent-protocol.md`, `brainstorming.md`, `memory-mcp.md`, `memory.md`, `planner.md`, `role-cards.md`, `run-management.md` (7 files)
- Create: `docs/plans/AID-audit-2026-06/agents/auditor.md`, `curator.md`, `gate-fixer.md`, `implementer.md`, `project-scanner.md`, `verifier.md` (6 files)
- Create: `docs/plans/AID-audit-2026-06/03-skill-audit.md` — master index (cross-file patterns + summary findings table + links to per-file audits)

**Architecture Context:** Fan-out is bulk audit execution. Methodology already validated at PM-GATE-A. L1 verification sampled (~30% = ≥4 files of 13) catches shallow agent analysis. L2 cross-section runs across all 13 outputs for systematic patterns.

**Implementation Detail:**

**Dispatch pattern:** Batched 3-4 parallel Agent calls (1 message per batch). Each agent audits 1 file × 4 dimensions per uniform methodology. Orchestrator captures each agent's final message → writes to per-file output path.

**L1 verification:** Sample top-4 files by line count (deterministic). For each: `Agent(aid-orchestrator:verifier, focus=section-review)` adversarial review of audit output, verifying every file:line citation, every NR reference, every propagation verdict against source skill file.

**L2 cross-section:** After all 13 audits complete, dispatch `Agent(aid-orchestrator:verifier, focus=cross-section-review)` across all 13 per-file outputs + master index. Focus on drift, decision propagation, files-summary completeness, dependency consistency.

**Master index assembly (`03-skill-audit.md`):**
- Cross-file patterns observed (e.g., "5/13 files have version-stamped section adds")
- Summary table: file × dimension × finding count (with priority breakdown)
- Links to per-file outputs

**Error Handling:**
- Batch agent failure (1 of 4 returns error) → retry that single dispatch s context isolated
- L1 finds critical issue in sampled file → all-files audit of same dimension OR PM consultation
- L2 cross-section finds drift in fan-out → fix targeted, re-run L2 OR document as systematic finding

**Edge Cases:**
- Small file (e.g., implementer.md ~600 lines) audit returns near-empty 3b/3c findings — legitimate if file is genuinely clean
- Two files mention same NR but with different recommendations — log as decision-propagation finding for Phase 5
- Pilot calibration bias (per §10 risk #14) — methodology tuned on largest files may under-detect smaller files → PM-GATE-B spot-check of 1 small file (memory.md OR memory-mcp.md) before sign-off

**Dependencies:**
- Depends on: Step 3 (PM-GATE-A approval signals methodology validated)
- Blocks: Step 5 (synthesis) — needs all 13 audit outputs + L2 cross-section report

**Acceptance Criteria (= PM-GATE-B exit criteria):**
- [ ] All 13 fan-out files audited (7 skills + 6 agents)
- [ ] L1 verification sampled (≥4 files, top-4 by line count desc)
- [ ] L2 cross-section consistency report: no critical conflicts
- [ ] Master index `03-skill-audit.md` complete s findings summary + cross-file patterns + per-file links
- [ ] PM read master index + at least 3 per-file findings; approve before synthesis

**Effort:** L (13 parallel Agent dispatches batched 3-4 + L1 sampled ~30% + L2 cross-section + master index assembly)
**AID Role:** docs

### Step 5: Phase 4 synthesis + Phase 5 discussion + final approval

**Objective:** Produce 6 meta-structure deliverables (4a candidate principle, 4b-final skill-writing.md, 4c reflection prompt update, 4d inventory cross-links, 4e NR annotation, 4f roadmap rewrite); run Phase 5 PM discussion resolving all open items; produce decision log; PM-GATE-C final sign-off.

**Files:**

**Phase 4 deliverables:**
- Modify: `docs/plans/AID-v3-principles.md` — add Candidate Principle #5 "Cargo Cult" to Future principle slots (4a)
- Modify: `plugins/aid-orchestrator/skills/skill-writing.md` — refined from provisional draft, incorporating Phase 3 empirical findings (4b-final)
- Modify: `docs/plans/AID-post-plan-reflection-prompt.md` — add Sekce 9 "Skill propagation check" (4c)
- Modify: `docs/plans/AID-v3-architectural-inventory.md` — scan for Principle #5-applicable items, add #5 citations (4d)
- Modify: `docs/plans/AID-v3-agents-outputs.md` — NR 17 §4D post-hoc annotation reinterpreting original "fabricated provenance" as timestamp-fragility false-positive (4e)
- Modify: `docs/plans/AID-v3-roadmap.md` — rewrite P041 entry to reflect final scope (audit + meta-structure, not nonce protocol) (4f)

**Phase 5 deliverables:**
- Create: `docs/plans/AID-audit-2026-06/04-decisions.md` — per-item decision log

**Plugin metadata (required per CLAUDE.md:180 "On Plugin Changes — Mandatory Updates"):**
- Modify: `CHANGELOG.md` (root) — add release entry for skill-writing.md introduction
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical entry to root

**Architecture Context:** Phase 4 synthesizes audit findings into forward-looking artifacts (principle, template, reflection rule). Phase 5 resolves audit-discovered issues that exceed docs-edit scope. Together they close the audit cycle with both retrospective (findings) and prospective (rules) outputs.

**Implementation Detail:**

**4a — Candidate Principle #5:**
Append to `Future principle slots` in `principles.md`:
> #5 — Enforcement without Instruction is Cargo Cult. Every enforcement mechanism (FSM precondition, structural check, dispatch wrapper, schema validator) must be accompanied by a matching LLM-facing instruction in the relevant skill or agent file. Cargo Cult gloss: enforcement that fires correctly but no agent/LLM knows the rule, so the rule is rediscovered by failure each time.
> Candidate empirical anchors: P041 brainstorm (2026-06-01) — §1-§10 section verifier review repeatedly found instruction-vs-enforcement misalignment in own design work + P041 audit Phase 2 GAP findings.
> Promotion follows global gate (a/b/c per principles.md:111-114). Sub-criterion: ≥3 GAP findings spanning ≥2 of three enforcement mechanisms defined in principles.md:25-40.
> Status: candidate, NOT binding.

**4b-final — Refined skill-writing.md:**
Refine 4b-pre provisional draft (created in Step 3) incorporating Phase 3 empirical findings. 13 content sections + own frontmatter convention demonstrated. CHANGELOG entries in both root + plugin per CLAUDE.md:180 "On Plugin Changes — Mandatory Updates".

**4c — Sekce 9 reflection propagation:**
Add to `AID-post-plan-reflection-prompt.md` (per file's existing "Sekce N" convention; current max sekce = 8 → new = 9):
```
═══════════════════════════════════════════════════════════════
Sekce 9. SKILL PROPAGATION CHECK (mandatory after each NR write)
═══════════════════════════════════════════════════════════════
```
4 outcome branches: Apply now / Inventory AID-NNN / PM rejected / N/A no skill touched.

**4d — Inventory cross-links:**
Scan `AID-v3-architectural-inventory.md` for items fitting Principle #5 application criteria (12+ existing references to Principle #1 baseline). Add #5 citations to `notes:` field.

**4e — NR 17 §4D annotation:**
Append post-hoc annotation to NR 17 §4D explaining that original "fabricated provenance hard block" recommendation was based on timestamp-fragility false-positive (P040 own ship Step 7 timing slip, not actual fabrication). Cross-reference P041 reframing #2 + AID-038 reinterpretation.

**4f — Roadmap P041 entry rewrite:**
Update `AID-v3-roadmap.md` P041 entry from "Nonce-based Provenance + Visibility Fix" (current outdated text) to "Enforcement-vs-Instruction Audit + Skill Quality Audit" with current scope summary.

**Phase 5 discussion methodology:**

Inputs (3 classes):
- (a) Phase 1+2 GAP/ORPHAN/CONTRADICTORY/UNREACHABLE findings
- (b) Phase 3 priority: must-fix / should-fix findings exceeding docs-edit
- (c) Phase 4 draft outputs (4a-4f) — Approve/Revise/Reject-draft decisions

5 decision categories with outcome mappings:
1. **fix-now-or-defer** — Apply-now / Inventory-item / Rejected
2. **inventory-item-or-now** — Apply-now / Inventory-item / Rejected
3. **promote-candidate-to-binding** (4a) — Promote-to-binding / Park-as-candidate / Reject-principle
4. **approve-Phase-4-draft** (4b/c/d/e/f) — Approve-draft / Revise-draft / Reject-draft
5. **reflection-incorporation** (Phase 3d) — Apply-now / Inventory-item / Mark-deliberate / Mark-N/A

Forcing function: Phase 5 budget max 4h total OR 15min/item, whichever shorter. Items > 15min auto-deferred to Inventory s AID-NNN reserved (next new = AID-045+; AID-044 reserved by Tier 3 follow-up). No "park" status outside explicit Park-as-candidate enum.

Decision log schema (`04-decisions.md`): per-item `### D-NN: <title>` with fields Source-finding, Category, Outcome, Inventory ID, Rationale, Follow-up. Rejection persistence: `DEC-P041-NN-REJECTED` marker.

**Error Handling:**
- Discussion item exceeds 15min timebox → auto-defer to Inventory with AID-NNN allocation, log timebox-exceeded reason
- Phase 4 draft fails PM review (Revise-draft) → orchestrator iterates, re-presents; if Reject-draft, log + remove from deliverables
- Phase 5 total time exceeds 4h → mid-session checkpoint with PM, decide continue/defer-rest

**Edge Cases:**
- Audit-discovered CLAUDE.md:98 staleness ("7 controller agents" claim, real = 6) — surface as Phase 5 discussion item, decide fix-now / inventory / defer
- Principle #5 promotion criteria insufficiently met (< 3 GAP findings or < 2 enforcement mechanisms covered) — candidate remains in Future slots; documented as "pending more evidence" status
- Inventory ID conflict (concurrent allocation) — orchestrator uses last-AID-NNN + 1 mechanism, AID-044 explicitly reserved

**Dependencies:**
- Depends on: Step 4 (PM-GATE-B approval signals fan-out complete)
- Blocks: P041 completion (PM-GATE-C is final gate)

**Acceptance Criteria (= PM-GATE-C exit criteria):**
- [ ] All Phase 4 deliverables (4a-4f) complete
- [ ] All Phase 5 discussion items resolved with one outcome from category's outcome set (no "park" outside explicit Park-as-candidate)
- [ ] CHANGELOG entries in both root + plugin (identical) per CLAUDE.md
- [ ] Decision log `04-decisions.md` complete s ≥1 entry per discussion item
- [ ] PM ship/iterate decision recorded

**Effort:** L (6 Phase 4 deliverables 4a-4f + Phase 5 discussion 4h/15min timebox + decision log + CHANGELOG entries in root + plugin)
**AID Role:** docs

## Testing Strategy

P041 is documentation/audit work, ne kód implementation — "testing" means **verification of audit outputs**, ne unit/integration tests.

### 3-layer verification stack (per Q2 decision)

| Layer | Who | What it does | Trigger |
|---|---|---|---|
| **L1: `section-review`** | dispatched Agent (verifier focus) | Adversarial review of orchestrator's audit findings — find blind spots, factual errors, missing references | After each phase output draft; sampled ~30% (≥4 of 13) for Phase 3 fan-out |
| **L2: `cross-section-review`** | dispatched Agent (verifier focus) | Cross-phase/cross-file consistency check — does Phase 2 mapping match Phase 1 inventory? Does Phase 3 finding contradict Phase 2 mapping? | Before Phase 5 (after all phases drafted but before PM final review). Runs only after every section has L1-PASS or PM override. |
| **L3: PM** | Marek | Sign-off + spot-check ≥1 cited file:line per L1 verdict | PM-GATE-A (post-pilot) / PM-GATE-B (post-fan-out) / PM-GATE-C (post-synthesis) |

L1 + L2 dispatched by orchestrator. L3 = PM read-and-approve + spot-check.

**Brainstorm/audit context opt-out:** L1/L2 dispatches do NOT use P040 `aid-emit-dispatch.sh` wrapper. Per `brainstorming.md` RULE 9, brainstorm dispatches are explicitly out-of-scope of FSM stage-log enforcement ("Do NOT wire stage-log events here — dead no-op in brainstorm — no FSM run"). The script's allowlist regex (`^cp[1-4](-step-[0-9]+|-[a-z][a-z0-9-]*)?$`) rejects non-CP focuses by design.

**Disagreement resolution:**
- L1 PASS vs L2 FAIL on same claim → L2 overrides on cross-section claims
- L1 vs L1 conflict (two reviewers, adjacent sections) → PM tiebreaker at next PM-GATE
- L1 FAIL but PM override at PM-GATE → both verdicts recorded; PM rationale logged

**Recursive-trust caveat:** L1/L2 prompts are author-blind — section text + codebase scope only, NEVER orchestrator's conclusion. PM-GATE-A/B/C is the only non-orchestrator verification layer; PM spot-checks ≥1 L1 verdict per phase against cited file:line.

**File-write protocol:** Orchestrator (NOT subagent) captures agent's final message text → writes to `evidence_dir/verifier-output-<focus>.md`. Reason: verifier.md mandates "Do NOT write report/summary/.md files; return findings inline as final assistant message" — orchestrator is the file-write agent.

**L1 sampling criteria (Phase 3 fan-out):** Deterministic — files ranked by line count descending, take top-4 (= ~30% of 13).

## Constraints

- **Token budget:** PM accepted lack of time estimates; wall-clock variable. Audit may span multiple sessions; session-state docs preserve progress.
- **Context window:** Phase 1 inventory done in batched per-directory passes (orchestrator context budget mitigation per §10 risk #8)
- **No code change:** P041 produces audit findings + meta-structure ONLY. Code/doc fixes are manual outside AID (PM decision).
- **No Workflow tool:** Approach B uses Agent dispatches only (parallel batches of 3-4). Workflow tool requires explicit PM opt-in (not given).
- **Plugin distribution:** skill-writing.md ships with plugin; CHANGELOG entries required in both root + plugin (identical per CLAUDE.md:180 "On Plugin Changes — Mandatory Updates").
- **Inventory ID space:** Last assigned AID-043; AID-044 reserved by Tier 3 follow-up; next new = AID-045+.

## Risks

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | Methodology validation (during-pilot + post-pilot, merged) — pilot exposes 4-dim criteria nejsou ops-clear, OR methodology invalidated AFTER fan-out (sunk cost) | Medium | PM-GATE-A explicit refinement place; pilot scope ≤ 2 files limits sunk cost; fan-out kicks off only post-PM approval |
| 2 | Audit findings overwhelm PM — 60 file-dimension audits | Medium-High | Per-file outputs + master index s summary table + priority prioritization; L2 cross-section pre-aggreguje patterns |
| 3 | Independent agents inconsistent — různí agenti dají různé verdicts | Medium | L2 cross-section reconciliuje; konflikty surface jako Phase 5 discussion items |
| 4 | Audit-derived recommendations zůstanou neprovedené — P041 ships, fixy nikdo neudělá | **High (recurring)** — anchor: AID-v3-roadmap:56 "39/40 archived plans stuck na status: draft" + 41/43 inventory items bez implementation_status | Mandatory AID-NNN inventory entry per non-now decision + explicit `implementation_status` field (parallel to AID-003/AID-038 pattern); Phase 5 decision log links to AID-NNN, NOT stand-alone roadmap update |
| 5 | Scope creep — Phase 5 discussions otevřou nové sub-plány | Medium | "Apply-now" decisions explicitně limited to P041 cycle; vše ostatní → inventory s explicit AID-NNN |
| 6 | Wall-clock too long — audit může protáhnout napříč multiple sessions | Medium | Per-phase output independently committable; session-state docs preserve progress; resume-friendly architecture |
| 7 | Cargo Cult candidate principle nemá ≥3 gap findings — promote criteria nesplněna | Low-Medium | Brainstorm-internal evidence (interim §327-338 documenting 7 consecutive section-review FAILs) already approaching threshold; candidate zůstává v Future slots pokud audit fails to confirm |
| 8 | Orchestrator context-window exhaustion napříč 17 files | Medium | Phase 1 done in batched per-directory passes; Phase 3 fan-out uses Agent dispatches (offload context) |
| 9 | Shallow LLM analysis on fan-out (agent fatigue) | Medium | L1 verification sampled — catches shallow audits; L2 cross-section identifies systematic shallowness |
| 10 | Reflection 3d producing politically charged findings ("PM forgot to act on NR-X") | Low | NOT-PROPAGATED-DELIBERATE vs DROPPED distinction explicit; surface as PM Phase 5 discussion item, NEVER as accusation |
| 11 | skill-writing.md compliance burden — 9 pre-existing skills become non-compliant on ship | Low-Medium | Grandfathering policy v skill-writing.md frontmatter — pre-existing skills get exemption window; new edits to those skills must converge toward compliance; pre-existing violations → Phase 5 case-by-case |
| 12 | AID-audit/ docs vs inventory.md tracking divergence | Low-Medium | 4d deliverable: bidirectional cross-link (audit MD ↔ inventory ↔ decision log); each non-now recommendation gets AID-NNN inventory entry |
| 13 | **Audit output meta-drift** — agents producing audit reports exhibit same drift classes documented v interim §327-338 evidence (factual errors, namespace collisions, methodology gaps) | Medium-High | L1 sampled 30% + section-review na top-4-by-line-count audit outputs; explicit acceptance — some drift will ship |
| 14 | **Pilot calibration bias** — pilots (plan-writing, pipeline) jsou 2 largest/most-instruction-dense files; methodology tuned on them může under-detect v smaller files (memory.md, memory-mcp.md) | Medium | PM-GATE-B includes spot-check of 1 small file (memory.md OR memory-mcp.md) před fan-out sign-off |
| 15 | **skill-writing.md self-violation** — new skill may violate own rules at write-time (chicken-and-egg) | Low-Medium | 4b-pre researcher dispatch + PM sign-off (gated v Step 3); explicit rollback: ship as `experimental` frontmatter flag if self-audit fails |

## Success Criteria

- [ ] Phase 1 enforcement inventory ≥30 entries, all 15 enforcement types covered
- [ ] Phase 2 mapping ≥80% Phase-1 coverage, all 5 verdict types represented
- [ ] Phase 3 audit complete for 15 files (2 pilot + 13 fan-out), all 4 dimensions covered collectively across pilots
- [ ] Phase 4 deliverables (4a-4f) all complete; Principle #5 candidate in Future slots; skill-writing.md shipped (provisional + final); Sekce 9 added to reflection prompt; inventory + agents-outputs + roadmap updated
- [ ] Phase 5 decision log resolves all open items (zero "park" status outside Park-as-candidate enum)
- [ ] 3-layer verification stack (L1 + L2 + L3) ran at each PM-GATE without escalation
- [ ] CHANGELOG entries in both root + plugin (identical) per CLAUDE.md
- [ ] At least one of two outcomes:
  - (a) Principle #5 promoted to binding (≥3 GAP findings across ≥2 enforcement mechanisms), OR
  - (b) Principle #5 remains candidate with explicit "pending more evidence" status logged

## Next Steps

After P041 completes:
1. **Manual fix execution** — file-by-file outside AID, per PM original decision. Each apply-now decision from Phase 5 logged with implementation_status: pending → in-progress → done. Inventory items tracked separately.
2. **Follow-up plans triggered by audit findings:**
   - If audit finds skill-writing.md self-violation → P0XX rollback OR remediation plan
   - If Principle #5 promoted to binding → audit existing principles for compliance
   - If CLAUDE.md staleness confirmed (7 controller agents claim) → P0XX cleanup pass
3. **AID-044 follow-up** (Tier 3 platform-level provenance audit) reserved separately
4. **P042 "Plan-writing hardening bundle"** continues from roadmap

## Brainstorm Decision Log

Decisions locked during P041 brainstorm (preserved for traceability):

- **Q1 scope:** C (plugin files primary, internal docs only where cross-referenced)
- **Q2 verification:** B (3-layer: L1 independent agent + L2 cross-section + L3 PM self)
- **Q3 reflection sources:** B (NR 2-17 + lessons-learned.md, deduped into canonical inventory)
- **Q4 #5 wording:** A hybrid (Cargo Cult name + candidate status + promote-after-audit per global gate)
- **Q5 cadence:** C (pilot-then-fan-out, 3 PM-GATEs)
- **Q6 pilot:** 2-pilot (plan-writing.md + pipeline.md, per revised D variant)
- **Approach:** B (Pragmatic — parallel Agent dispatches, per-file outputs, no Workflow tool)

Reframings during brainstorm (preserved for traceability):
1. Original: Nonce-based Provenance + Visibility Fix
2. Step 2 critique → drop nonce (independent agent found nonce doesn't help "honest mistake" threat model)
3. Step 3 fraud-resistance detour → Tier 3 platform-level provenance = AID-044 follow-up
4. Step 5 PM scope expansion → FULL audit + skill quality (current scope)

Brainstorm meta-evidence pro Phase 3d canonical learnings inventory:
- 7+ consecutive section-review FAILs (§1, §2, §4, §5, §6, §7, §8, §9) on first draft
- 100% finding rate when validate-then-verify cycle applied; high finding rate when methodology drift occurs
- Drift sub-classes: factual errors, namespace collisions, methodology gaps, internal inconsistencies, chat-to-interim sync drift
- This pattern IS empirical evidence for Principle #5 candidate
