---
id: REF-P017
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/archive/P017-flow-optimization.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P017

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/skills/token-estimator.md` — skill document defining the `estimateTokens(text)` function signature, encoding choice (cl100k_base), and usage protocol
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~42-88) — add reference to token-estimator skill in the dispatch assembly section
- Create: `plugins/aid-orchestrator/defaults/policies/dispatch-config.yaml` — model tiers, context defaults, budget alerts as defined in the Data Model section
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (lines ~72-77) — verify dynamic scanning includes new file (it should automatically since aid-init scans `defaults/policies/*`)
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` (lines ~33-113) — add `model` and `context_scope` properties to the step object definition
- Modify: `plugins/aid-orchestrator/skills/planner.md` — add dispatch-config.yaml reading logic and step field population in the plan generation section
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~42-102) — add token estimation before dispatch, usage logging after dispatch completion
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (lines ~82-86) — aggregate usage into `plan_progress.json` at DONE state
- No code changes — this is an execution and measurement step
- Output: `.aid-o/04-engine/evidence/{benchmark_epic_id}/{run_id}/baseline-report.md` — structured benchmark report
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~332) — add model parameter to Task tool dispatch call
- Modify: `plugins/aid-orchestrator/skills/parallel-dispatch.md` (lines ~169-173) — add model parameter to parallel Task tool dispatch calls
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~82-86) — wrap knowledge/memory injection in context_scope checks
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~44-55) — replace full EPIC/plan injection with step-scoped summary
- No code changes — execution and measurement step
- Output: `.aid-o/04-engine/evidence/{benchmark_epic_id}/{run_id}/optimization-report.md` — comparison report
- Modify: `plugins/aid-orchestrator/agents/auditor.md` — add "Token Efficiency" audit section with usage data analysis
- Modify: `plugins/aid-orchestrator/commands/aid-audit.md` (lines ~11-26) — add "efficiency" to audit types list
- Modify: `CHANGELOG.md` — add new version entry with P017 features
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical copy
- Modify: `.claude-plugin/marketplace.json` — bump `metadata.version` and `plugins[0].version`
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — bump `version`
- Modify: `plugins/aid-orchestrator/README.md` — bump version line
- Modify: `README.md` — update Roadmap section
- Modify: `plugins/aid-orchestrator/skills/token-estimator.md` — add `**Last Updated:**` footer
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` — update `**Last Updated:**` footer
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` — update `**Last Updated:**` footer
- Modify: `plugins/aid-orchestrator/skills/planner.md` — update `**Last Updated:**` footer
