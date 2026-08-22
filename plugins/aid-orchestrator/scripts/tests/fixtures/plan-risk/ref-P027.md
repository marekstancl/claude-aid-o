---
id: REF-P027
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/archive/P027-visual-assets.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P027

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` (lines ~36-80, step properties) — add `visual_refs` array field
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~104-108, conditional sections) — add `## Visual Specification` section
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~199-244, step template) — add `visual_refs` field
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` — add mockup detection in Step 1 (Context) and mockup association in Step 5 (Design)
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~148-161, Context assembly section) — add visual context as item 8
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~165-210, Agent Dispatch Protocol) — add visual dispatch rule
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` — frontend role card section, add Visual Anchoring capability/constraint
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` — input format YAML template, add `visual_refs` field
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~215-240, Output verification section) — expand Visual Check section with concrete protocol
