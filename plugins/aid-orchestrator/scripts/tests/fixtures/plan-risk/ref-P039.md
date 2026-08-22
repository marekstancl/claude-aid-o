---
id: REF-P039
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P039-section-validation.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P039

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` (line 333 — insert after the `---` that
- Modify: `plugins/aid-orchestrator/agents/verifier.md` (lines 13-17 — focus registry list; line 3
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` (lines 267-276 — Design Validation
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines 88-90 — Step 7 block; line 366 —
- Modify: `CHANGELOG.md` (top — new `## [2.23.0]` section) — root changelog entry.
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` (top) — identical copy of the root entry.
- Modify: `.claude-plugin/marketplace.json` (`metadata.version` and `plugins[0].version`) — bump to
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` (`version`) — bump to 2.23.0.
- Modify: `plugins/aid-orchestrator/README.md` (`**Plugin:** ` line) — bump to 2.23.0.
- Modify: `README.md` (`**vX.Y.Z** (current)` roadmap line + the version tagline line at line 3,
