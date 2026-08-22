---
id: REF-P015
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/archive/P015-quality-and-robustness.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P015

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` (lines 60-78, 106-126) — refactor `add()`, `start()`, `complete()` to include conflict detection as Step 0
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines ~95-130) — add auto-mode flag creation at session start and deletion at session end
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines 119-124) — change snapshot filename from `auto-mode-state-snapshot-{epic_id}.json` to `interrupted_step_context.json`
- Modify: `plugins/aid-orchestrator/commands/aid-first-aid.md` (lines 1310, 1324) — verify resume detection reads `interrupted_step_context.json` (should already be correct)
- Modify: `plugins/aid-orchestrator/skills/gate-evaluation.md` — search for any references to either filename and align to `interrupted_step_context.json`
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines 222-227) — replace "skip this guardrail" with default baseline logic
- Modify: `plugins/aid-orchestrator/skills/first-aid-controller.md` (lines 205-213) — replace unconditional auto-approve with INTERMEDIATE_GUARDRAIL check
- Modify: `plugins/aid-orchestrator/commands/aid-first-aid.md` (lines 17-18, 30, 92-95) — remove --dry-run from usage docs, update handler to exit with "not implemented" message
- Create: `.aid-o/04-engine/backlog/dry-run-feature.md` — detailed feature specification for future implementation
- Modify: `plugins/aid-orchestrator/skills/knowledge-acquisition.md` (lines 1807-1814 function definition, lines 2018-2024 replace_tool_references calls) — rewrite adapt_example() from 7 steps to 3 steps
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (lines ~1490 area for existing check, plus adding detection logic near the beginning of the setup flow) — add re-run detection and section menu
- Modify: `plugins/aid-orchestrator/skills/planner.md` (lines 683-696) — replace vague algorithm with concrete pseudocode
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines 107-139) — add explicit canonical field list with trusted/untrusted classification
- Modify: `plugins/aid-orchestrator/commands/aid-run-epic.md` (lines 189-241 base template, lines 259-319 re-dispatch template) — verify all untrusted fields are consistently wrapped
- Modify: `plugins/aid-orchestrator/skills/planner.md` (lines 533-538) — replace vague R1 with precise definitions and determination algorithm
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines 220-248) — replace vague Strategy 3 (keyword matching) with concrete algorithm including stopping rule
- Modify: `plugins/aid-orchestrator/skills/epic-state-machine.md` — add formal "ID Format" section near the top with canonical format, components, validation regex, and legacy format documentation
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` — replace any inline ID format examples with cross-reference to epic-state-machine.md
- Modify: `CLAUDE.md` (repository root) — verify any EPIC ID examples use the canonical format
- Modify: `CLAUDE.md` (repository root, lines 16-17) — update hardcoded "13 slash commands" and "21 skills" to actual current counts with verification comments
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` — add count verification check to the Release Sub-Phase
- Modify: `plugins/aid-orchestrator/skills/gate-evaluation.md` (lines 28-34) — replace exact string matching with 6 case-insensitive regex patterns
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` (lines ~19 schema definition, lines 60-78 add() function) — extend schema with depends_on field, add validation to add()
- Modify: `plugins/aid-orchestrator/skills/epic-queue.md` (the `next()` function or equivalent EPIC selection logic) — add dependency eligibility check and READY/WAITING/BLOCKED status computation
