---
id: REF-P045
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P045-simplifier-reporter-plan-boundary.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P045

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/agents/simplifier.md` — verbatim content from
- Create: `plugins/aid-orchestrator/agents/reporter.md` — verbatim from
- Create: `plugins/aid-orchestrator/defaults/templates/delivery-report.md` — verbatim
- Modify: `plugins/aid-orchestrator/defaults/check-severity.yaml` — add
- Modify: `plugins/aid-orchestrator/defaults/policies/review-checkpoints.yaml` — add
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` — add `simplifier:` block
- Modify: `plugins/aid-orchestrator/scripts/aid-emit-dispatch.sh` — the focus regex is
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` —
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — (a) §7 "Plan Boundary"
- Modify: `plugins/aid-orchestrator/agents/gate-fixer.md` — add a `simplifier` row to
- Modify: evidence-file list in §7 to include `simplifier-report.md`,
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — extend the PM summary
- Modify: `plugins/aid-orchestrator/defaults/templates/epic.md` — add `.aid-o/reports/`
- Modify: `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` — append the 7
- Modify: `CLAUDE.md` — add the new agents to any agent inventory; add/confirm the
- Create: `docs/extending-aid.md` — sections: (1) the type→instruction-home table
- Modify: `CLAUDE.md` — link to `docs/extending-aid.md` from the plugin-changes section.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-delivery-report.bats` —
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-emit-dispatch.bats` —
- Modify: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — ensure the two
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` (identical) — one
- Modify: the remaining 6 version-registry files via `aid-release.sh minor`.
- Modify: root `README.md` Roadmap.
