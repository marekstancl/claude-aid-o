---
id: P028
type: plan
status: draft
created: 2026-03-16
author: PM + AI
---

# Plan: v2 Documentation Cleanup — Dead References, v1 Remnants, Bloat Reduction

## Context

Full project audit (v2.7.0) revealed significant documentation debt from the v2.0 migration:
- 20+ dead cross-references to deleted files (`dispatch-protocol.md`, `epic-orchestration.md`)
- 15+ v1 state names in active skills (`PM_APPROVAL`, `CURATOR_RESOLVE`, `PHASE_CHECK`, `IDLE`)
- v1 directory paths in CLAUDE.md and templates (`01-plans/`, `04-engine/`)
- 200 lines of duplicated state descriptions in `aid-run.md`
- 4-5 skills with extensive v1 references needing alignment
- Pre-commit hook dead code
- `aid-release.sh` misaligned with version registry

The architecture is sound — bash scripts are clean and focused. This is purely a documentation hygiene pass.

## Goal

Remove all dead references, v1 remnants, and unnecessary duplication so that every file an LLM reads during orchestration is consistent with the current v2.7.0 architecture.

## Scope

**In scope:**
- Fix dead cross-references in active skill files
- Replace v1 state names with v2 equivalents
- Fix v1 directory paths in CLAUDE.md and templates
- Deduplicate `aid-run.md` state descriptions (replace with pipeline.md reference)
- Clean pre-commit hook dead code
- Align `aid-release.sh` with version registry (or document the gap)
- Fix v1 command names (`/aid-run-epic` → `/aid-run`, `/aid-first-aid` → `/aid-run --auto`)

**Out of scope:**
- Rewriting stale skills from scratch (`improvement-proposals.md`, `analytics.md`) — mark as v1 legacy
- Adding new features
- Architectural changes

## Approach

### Option A: Single Sweep (Recommended)
One EPIC, 6 steps, mostly find-and-replace. Each step targets a specific category of fixes across all affected files.

**Pros:**
- Fast — all changes are mechanical text replacement
- Low risk — no logic changes, only documentation
- Can be done in one session

**Cons:**
- Large diff across many files

### Option B: Per-File Approach
Fix each file individually as its own step.

**Pros:**
- Easier to review per-file

**Cons:**
- 15+ steps for what is fundamentally the same operation
- Artificial separation

### Decision

**Chosen:** Option A — categorical sweep
**Rationale:** The fixes are all the same type (text replacement). Grouping by category keeps the plan concise and makes it easy to verify completeness.

## Implementation Steps

**EPIC 1: Steps 1-6 — v2 Documentation Cleanup**

### Step 1: Fix Dead File References

**Objective:** Replace all references to deleted skill/command files with their v2 equivalents.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines 29, 602, 677) — `dispatch-protocol.md` → `pipeline.md §4`
- Modify: `plugins/aid-orchestrator/skills/token-estimator.md` (line 10, 385) — `dispatch-protocol.md` → `pipeline.md §4`, `epic-state-machine` → `pipeline.md §1`
- Modify: `plugins/aid-orchestrator/skills/agent-core.md` (lines 248, 442) — `epic-orchestration.md` → `pipeline.md`
- Modify: `plugins/aid-orchestrator/skills/improvement-proposals.md` (lines 385-386) — `epic-orchestration.md` → `pipeline.md`, `run-epic.md` → `aid-run.md`
- Modify: `plugins/aid-orchestrator/skills/analytics.md` (line 75) — `epic-orchestration.md` → `pipeline.md`
- Modify: `plugins/aid-orchestrator/commands/aid-analytics.md` (line 75) — `epic-orchestration.md` → `pipeline.md`
- Modify: `plugins/aid-orchestrator/defaults/orchestration.yaml` (line 14) — remove `dispatch-protocol skill` reference
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` (line 17) — `.aid-o/01-plans/` → `.aid-o/plans/`
- Modify: `plugins/aid-orchestrator/defaults/templates/knowledge-base.yaml` (line 7) — `.aid-o/04-engine/memory/` → `.aid-o/work/`
- Modify: `plugins/aid-orchestrator/defaults/templates/epic-example.md` (line 13) — `/aid-plan-epic` → `/aid-plan epic`, `/aid-run-epic` → `/aid-run`
- Modify: `CLAUDE.md` — `skills/epic-orchestration.md` → `skills/pipeline.md`

**Architecture Context:**
These files are read by the LLM during orchestration. Dead references cause the LLM to attempt reading non-existent files, wasting context and potentially causing confusion. Replacing with correct v2 paths ensures accurate navigation.

**Implementation Detail:**
For each file, search for the dead reference string and replace with the v2 equivalent:
- `skills/dispatch-protocol.md` → `skills/pipeline.md` (§4 Context assembly)
- `skills/epic-orchestration.md` → `skills/pipeline.md`
- `skills/epic-state-machine.md` → `skills/pipeline.md` (§1 Mechanical Enforcement)
- `/aid-run-epic` → `/aid-run`
- `/aid-first-aid` → `/aid-run --auto`
- `/aid-plan-epic` → `/aid-plan epic`

Preserve references in CHANGELOG (historical record) and aid-init.md upgrade section (needed for v1→v2 migration). Also preserve pipeline.md line 663-665 which explicitly documents what was consolidated.

**Error Handling:**
- If a reference is ambiguous (could map to multiple v2 files) → use the most specific reference
- If a reference is in a context that no longer makes sense in v2 → rewrite the sentence

**Edge Cases:**
- References in CHANGELOG entries — leave as-is (historical record)
- References in aid-init.md upgrade section — leave as-is (migration docs)
- `.gitignore` v1 entries — leave as-is (need to ignore v1 dirs in upgraded projects)

**Dependencies:**
- No dependencies — can start immediately
- Blocks: Step 3 (v1 state names often co-occur with dead references)

**Acceptance Criteria:**
- [ ] `grep -r "dispatch-protocol" plugins/aid-orchestrator/skills/` returns zero matches
- [ ] `grep -r "epic-orchestration" plugins/aid-orchestrator/skills/` returns zero matches (excluding pipeline.md "Replaces" line)
- [ ] `grep -r "aid-run-epic" plugins/aid-orchestrator/skills/ plugins/aid-orchestrator/commands/` returns zero matches (excluding aid-run.md "Replaces" context and CHANGELOG)
- [ ] All replaced references point to files that actually exist

**Effort:** M
**AID Role:** docs

### Step 2: Fix v1 State Names

**Objective:** Replace all v1 FSM state names in active skills with v2 equivalents or mark the skill as v1 legacy.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines 53, 84, 492, 509, 570, 587) — replace v1 commands and state names
- Modify: `plugins/aid-orchestrator/skills/improvement-proposals.md` — add v1 legacy header OR replace 15+ state references
- Modify: `plugins/aid-orchestrator/skills/analytics.md` — add v1 legacy header OR replace state references
- Modify: `plugins/aid-orchestrator/skills/token-estimator.md` — replace `PHASE_CHECK` references
- Modify: `plugins/aid-orchestrator/skills/agent-core.md` — replace `PHASE_CHECK` reference

**Architecture Context:**
The current FSM has 6 states: READY, EXECUTE, GATES, ESCALATION, DONE, ERROR. v1 had additional states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE). Skills referencing v1 states could cause an LLM to attempt invalid transitions.

**Implementation Detail:**
**pipeline.md** (critical — primary orchestration reference):
- Line 53: `/aid-run-epic` → `/aid-run`
- Line 84: `/aid-run-epic` → `/aid-run`
- Line 492: `/aid-first-aid` → `/aid-run --auto`
- Line 509: `PM_APPROVAL` → `DONE (review sub-phase)` with `pm_decision` field
- Line 570: `/aid-run-epic --resume {run_id}` → `/aid-run --resume {run_id}`
- Line 587: `IDLE` → remove or replace with context-appropriate v2 state

**improvement-proposals.md** and **analytics.md** — these skills have 15+ v1 references each. Full rewrite is out of scope (see plan scope). Instead:
- Add header: `> ⚠️ This skill references v1 state names (PM_APPROVAL, CURATOR_RESOLVE). Mapping: PM_APPROVAL → DONE sub-phase (review), CURATOR_RESOLVE → DONE sub-phase (review). See pipeline.md §7 for current protocol.`
- This warns the LLM without requiring a full rewrite

**token-estimator.md** and **agent-core.md**:
- Replace `PHASE_CHECK` → `GATES` (closest v2 equivalent)

**Error Handling:**
- If v1 state is used in a code example or flow diagram → rewrite the example with v2 states
- If the context is too complex to replace inline → add v1 legacy header

**Edge Cases:**
- `PM_APPROVAL` has no direct v2 equivalent (it's split across DONE sub-phases + pm_decision field) — use explanation rather than simple replacement
- `IDLE` was the initial state in v1 — in v2 runs start at READY, there is no idle state

**Dependencies:**
- Depends on: Step 1 (dead file references often co-occur with v1 state names)

**Acceptance Criteria:**
- [ ] `pipeline.md` contains zero v1 state names and zero v1 command names
- [ ] `improvement-proposals.md` and `analytics.md` have v1 legacy headers
- [ ] `token-estimator.md` and `agent-core.md` have no v1 state names
- [ ] No file references a state outside {READY, EXECUTE, GATES, ESCALATION, DONE, ERROR} as a current FSM state

**Effort:** M
**AID Role:** docs

### Step 3: Fix v1 Directory Paths

**Objective:** Replace all v1 directory paths in CLAUDE.md and templates with v2 equivalents.

**Files:**
- Modify: `CLAUDE.md` (lines 57-60) — v1 workspace structure → v2
- Modify: `CLAUDE.md` (line 208) — `.aid-o/01-plans/` → `.aid-o/plans/`

**Architecture Context:**
CLAUDE.md is read at the start of every conversation. v1 paths mislead the LLM about where to find/create files. The workspace structure section is particularly critical as it's the first thing read.

**Implementation Detail:**
Replace CLAUDE.md lines 57-60:
```
# FROM:
  01-plans/          # PM + AI brainstorming → plans
  02-epics/          # PM + AI detail → specifications
  03-config/         # PM-customizable
  04-engine/         # AI internal

# TO:
  plans/             # PM + AI brainstorming → plans
  tasks/             # PM + AI detail → EPIC specifications
  config/            # PM-customizable (policies, templates, playbooks)
  work/              # AI internal (runs, active, backlog, evidence)
```

Replace CLAUDE.md line 208:
```
- Plans: .aid-o/plans/
```

**Error Handling:**
- Verify the line numbers are still correct before editing (context may have shifted)

**Edge Cases:**
- The `## AID Orchestrator` section at the bottom of CLAUDE.md may be auto-generated by `/aid-init` — if so, also check the init template that generates it
- v1 paths in `.gitignore` template should stay (needed for v1→v2 upgraded projects)

**Dependencies:**
- No dependencies — independent fix

**Acceptance Criteria:**
- [ ] `grep -n "01-plans\|02-epics\|03-config\|04-engine" CLAUDE.md` returns zero matches (excluding the upgrade migration section if it exists)
- [ ] CLAUDE.md workspace structure shows v2 paths

**Effort:** S
**AID Role:** docs

### Step 4: Deduplicate aid-run.md State Descriptions

**Objective:** Remove ~200 lines of duplicated state descriptions from aid-run.md, replace with reference to pipeline.md.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~130-305) — replace state descriptions with pipeline.md reference

**Architecture Context:**
`aid-run.md` is the command definition. `pipeline.md` is the skill with detailed state protocols. Currently both contain near-identical state descriptions. The LLM reads both, wasting ~200 lines of context on duplicated content. `aid-run.md` should define the command interface and enforcement rules; `pipeline.md` should define state protocols.

**Implementation Detail:**
Replace the entire block of state descriptions (State: READY through State: ERROR) with:
```markdown
### State Protocols

See `skills/pipeline.md` sections §3-§7 for detailed state protocols:
- §3 READY — pre-flight checks, plan.json loading
- §4 EXECUTE — step dispatch, agent protocol, verification
- §5 GATES — gate execution, report generation
- §6 ESCALATION — PM decision flow
- §7 DONE — curator, auditor, PM review, release

Key FSM state-specific notes (unique to this command):
```

Then keep ONLY the unique content from aid-run.md that isn't in pipeline.md:
- The FSM diagram (unique visualization)
- PRE-FLIGHT initialization steps (command-specific)
- The `--auto` mode differences
- Error recovery table

**Error Handling:**
- Before deleting, verify each section in aid-run.md has an equivalent in pipeline.md
- If any content is unique to aid-run.md, keep it

**Edge Cases:**
- The DONE sub-phase documentation was recently added to aid-run.md — verify pipeline.md has equivalent before removing
- FSM diagram at the top is unique to aid-run.md — keep it

**Dependencies:**
- No dependencies

**Acceptance Criteria:**
- [ ] `aid-run.md` is under 180 lines (currently ~330)
- [ ] No state protocol content is lost — everything exists in pipeline.md
- [ ] MECHANICAL ENFORCEMENT PROTOCOL is preserved
- [ ] FSM diagram is preserved

**Effort:** M
**AID Role:** docs

### Step 5: Fix Pre-Commit Hook + Release Script

**Objective:** Clean pre-commit hook dead code and document `aid-release.sh` version registry gap.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-commit` — remove dead `case` statement
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` — add comment documenting which version registry locations it covers vs. manual

**Architecture Context:**
The pre-commit hook has a non-functional `case` statement (remnant from refactoring). The release script updates 4 of 8 version locations — the gap should be documented.

**Implementation Detail:**
**Pre-commit hook:**
Remove the `case` statement (lines 8-12) since the `if` block (line 13) handles the same logic:
```bash
# REMOVE:
case "$_AID_BRANCH" in
  task/*|epic/*) ;;
  *) true; # AID-ORCHESTRATOR-HOOK-END
esac

# KEEP (already handles the logic):
if [[ "$_AID_BRANCH" == task/* || "$_AID_BRANCH" == epic/* ]]; then
```

**Release script:**
Add a comment block after the shebang:
```bash
# NOTE: This script updates JSON version files only (4 of 8 version registry locations).
# Remaining locations (CHANGELOGs, READMEs) must be updated manually.
# See CLAUDE.md "Version File Registry" for the full 8-location list.
```

**Error Handling:**
- Verify hook still functions correctly after removing case statement (run tests)

**Edge Cases:**
- The case statement's `# AID-ORCHESTRATOR-HOOK-END` comment was a marker — verify the END marker still exists after removal (it should be at the end of the if block)

**Dependencies:**
- No dependencies

**Acceptance Criteria:**
- [ ] Pre-commit hook has no dead `case` statement
- [ ] Pre-commit hook still blocks commits correctly on FSM branches (re-run tests)
- [ ] `aid-release.sh` has documentation comment about version registry coverage
- [ ] Hook START/END markers are correctly placed

**Effort:** S
**AID Role:** backend

### Step 6: Update CHANGELOGs

**Objective:** Add cleanup entries to v2.7.0 CHANGELOG and update pipeline.md Last Updated date.

**Files:**
- Modify: `CHANGELOG.md` — add Fixed section entries
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical copy
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — update Last Updated date

**Architecture Context:**
Per CLAUDE.md contributing guidelines, all changes require CHANGELOG entries. Both CHANGELOGs must be identical.

**Implementation Detail:**
Add to v2.7.0 entry under `### Fixed`:
```markdown
### Fixed
- **Dead Cross-References** — replaced 20+ references to deleted v1 files (dispatch-protocol.md, epic-orchestration.md) with v2 equivalents across 11 files
- **v1 State Names** — replaced v1 FSM states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE) in pipeline.md; added v1 legacy headers to improvement-proposals.md and analytics.md
- **v1 Directory Paths** — updated CLAUDE.md workspace structure from v1 (01-plans/, 04-engine/) to v2 (plans/, work/)
- **aid-run.md Bloat** — removed ~150 lines of duplicated state descriptions (now references pipeline.md)
- **Pre-Commit Hook** — removed dead case statement (non-functional code from refactoring)
```

**Error Handling:**
- Verify both CHANGELOGs are identical after edit

**Edge Cases:**
- If v2.7.0 already has a Fixed section → append to it
- If no Fixed section → create one after Changed

**Dependencies:**
- Depends on: Steps 1-5 (all fixes must be done before documenting them)

**Acceptance Criteria:**
- [ ] Both CHANGELOGs have identical Fixed section for v2.7.0
- [ ] pipeline.md Last Updated date is 2026-03-16
- [ ] All fix descriptions accurately reflect what was changed

**Effort:** S
**AID Role:** docs

## Testing Strategy

1. **Grep verification** — after each step, run targeted greps to confirm zero remaining dead references
2. **Pre-commit hook test** — re-run the 6-scenario test suite after hook cleanup
3. **Plugin validation** — `/plugin validate .` from repo root
4. **Cross-reference check** — verify every replaced reference points to an existing file

## Constraints

- No architectural changes — only documentation fixes
- Preserve historical CHANGELOG entries
- Preserve v1→v2 migration docs in aid-init.md
- Preserve `.gitignore` v1 entries (needed for upgraded projects)
- All changes under v2.7.0 (no version bump)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Breaking a reference by replacing it wrong | Low | Medium | Verify each replacement points to existing file |
| Removing content from aid-run.md that was unique | Low | High | Diff against pipeline.md before removing |
| Pre-commit hook regression | Low | Medium | Re-run full test suite |

## Success Criteria

- [ ] Zero dead file references in active skills (excluding CHANGELOG and migration docs)
- [ ] Zero v1 state names in pipeline.md and core skills
- [ ] CLAUDE.md shows v2 directory structure
- [ ] `aid-run.md` under 180 lines (from ~330)
- [ ] Pre-commit hook clean, tested
- [ ] Both CHANGELOGs updated

## Next Steps

- [ ] Implement cleanup (single EPIC, 6 steps)
- [ ] Run P027 (visual assets) after cleanup — clean foundation first
- [ ] Consider stale reference scanner as CI check (future)

---

**Last Updated:** 2026-03-16
