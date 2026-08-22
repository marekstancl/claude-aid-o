---
id: REF-P044
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P044-preconditions-registry-bats-helpers.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P044

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/defaults/preconditions.yaml` — schema header
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~1860-1900) — replace
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (§ EXECUTE, increment-step
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-preconditions-registry.bats` —
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-helpers.bash` (append
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-tiered-severity.bats`
- Modify: `plugins/aid-orchestrator/scripts/tests/test-check-severity-sync.sh`
