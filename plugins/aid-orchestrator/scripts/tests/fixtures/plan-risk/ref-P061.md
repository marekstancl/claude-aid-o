---
id: REF-P061
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P061-gate-profiles-test-cost-reduction.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P061

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` — `gates[].items` z
- Modify: `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` (oba výskyty: extrakční filtr
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — scénář: fixture
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` — `--profile <name>` flag,
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — min. 3 nové
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — plan-required floor: `plan.json.gates[]`
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — CHECKPOINT 1
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádek pro
- Modify: `plugins/aid-orchestrator/skills/pipeline.md`, `plugins/aid-orchestrator/commands/aid-run.md`
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh`, `plugins/aid-orchestrator/defaults/execution-stacks/*.yaml` — generický profilový substrát pro
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` — fixture scénář pro
- Modify: `plugins/aid-orchestrator/commands/aid-init.md`, `plugins/aid-orchestrator/commands/aid-setup.md`
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init.bats` — fixture scénář pro
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` — deterministické
- Create: `plugins/aid-orchestrator/scripts/lib/aid-gate-profile.sh` — sdílená risk-klasifikační
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-profile.bats` — testy
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (`advance-to-gates`) — volá resolver ze
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádek pro risk-upgrade
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — CHECKPOINT 2
- Create: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` — čte changed paths (git diff
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests.bats` — testy na
- Modify: `.aid-o/config/execution.yaml` — přidat `gates.targeted_tests` definici (command:
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates.bats` — integrační
- Modify: `.aid-o/config/execution.yaml` — self-host `gate_profile_defaults` + `gate_profiles`.
- **Do NOT modify** `plugins/aid-orchestrator/defaults/execution.yaml` s `bats_fsm`/`bats_all`/
- Modify: `plugins/aid-orchestrator/commands/aid-do.md` — risk check ve DVOU bodech, ne jednom
- Modify: `plugins/aid-orchestrator/scripts/aid-release.sh` NEBO `aid-fsm.sh` (release precondition)
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — řádky pro oba mechanismy.
