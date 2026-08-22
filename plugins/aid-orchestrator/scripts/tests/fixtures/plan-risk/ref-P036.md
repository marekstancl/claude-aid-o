---
id: REF-P036
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P036-plan-quality-enforcement.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P036

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~545-547, mezi 17 grounding existing + 18 step outputs concreteness) — přidat 17e sub-check s detection algorithm + REVISE_REQUIRED semantics
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~547-562, mezi STEP OUTPUTS CONCRETENESS check #18 a EVALUATION) — přidat new check #19 s aktivačním pravidlem `type: bug-fix` a 3 questions semantic protocol
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.md` — extend frontmatter spec o `type:` field (4 enum values) + přidat `## Plan Type` documentation sekci s tabulkou explaining each value
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines 157-171, Mode: Write Plan section) — přidat Step 9 jako mirror brainstorm Step 9 (lines 97-156); update step counter z 8 na 9
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines ~97-135, Step 9 Codebase grounding pass section) — rozšířit verifier dispatch prompt o "EVIDENCE REQUIREMENT" sekci
- Create: `plugins/aid-orchestrator/scripts/tests/test-plan-quality-enforcement.sh` — smoke test s 4 sub-tests, každý cílí na 1 layer
- Modify: `CHANGELOG.md` — přidat `## [2.20.0] — 2026-05-XX` entry s Added (4 enforcement layers + smoke test) sekcí
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identický CHANGELOG entry (must match byte-for-byte)
- Modify: `.claude-plugin/marketplace.json` — `metadata.version` + `plugins[0].version` na "2.20.0"
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — `version` na "2.20.0"
- Modify: `plugins/aid-orchestrator/README.md` — `**Plugin:** 2.20.0`
- Modify: `README.md` — Roadmap entry `- **v2.20.0** (current) — plan quality enforcement (CLI grounding, design defeat, CP1 lifecycle)...` + `Multi-agent orchestration plugin for [Claude Code]... v2.20.0`
