---
id: REF-P069
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P069-scheduler-gate-integration.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P069

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/defaults/schemas/execution-unit.schema.json` — `unit_id`
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-execution-unit.sh` — given one execution
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-execution-unit.bats` — a hung
- Create: `plugins/aid-orchestrator/scripts/lib/aid-execution-unit-membership.sh` — given a
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-execution-unit-membership.bats` — one
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-gate-runtime-baseline.sh` (lines ~37-52) — in
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-runtime-baseline-concurrency.bats`
- Create: `plugins/aid-orchestrator/defaults/schemas/execution-unit-receipt.schema.json` — per-unit
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-execution-unit-receipt-schema.bats` —
- Create: `plugins/aid-orchestrator/defaults/schemas/scheduler-parallel-overlay.schema.json` —
- Create: `plugins/aid-orchestrator/scripts/aid-scheduler-overlay-approve.sh` — the mandatory,
- Create: `plugins/aid-orchestrator/scripts/aid-test-scheduler.sh` — **effective-status
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-scheduler.bats` — an all-
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-scheduler-overlay-approve.bats` — a
- Create: `plugins/aid-orchestrator/scripts/aid-test-isolation-experiment.sh` — runs a candidate N
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-isolation-experiment.bats` — a
- Create: `plugins/aid-orchestrator/defaults/schemas/divergence-evidence.schema.json` — **new,
- Create: `plugins/aid-orchestrator/scripts/aid-test-schedule-divergence-check.sh` — runs the same
- Create: `plugins/aid-orchestrator/scripts/aid-test-divergence-campaign.sh` — **bounded orchestrator,
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-schedule-divergence-check.bats`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-divergence-campaign.bats` — a
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-scheduler-report.sh` — merges per-batch
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-scheduler-report.bats` — two
- Modify: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` (lines ~265-313) — add
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests-emit-units.bats` — the
- Modify: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` (lines ~154-221) — `map_path_to_
- Modify: `plugins/aid-orchestrator/scripts/aid-select-tests.sh` — same region; add a new exit
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-select-tests-catalog-convergence.bats`
- Modify: `plugins/aid-orchestrator/scripts/aid-test-catalog-approve.sh` — the P066 script;
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-selector-mappings-real-seed.bats` —
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~104-119) — in
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh` (lines ~293) — in
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh`
- Create: `plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh`
- Create: `plugins/aid-orchestrator/scripts/aid-init-upgrade-test-audit.sh` — the explicit,
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-compose-execution-yaml-scheduler-block.bats`
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-init-upgrade-test-audit.bats` — a
- Create: `plugins/aid-orchestrator/scripts/aid-scheduler-rollout-gate.sh` — reads EVERY divergence-
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-scheduler-rollout-gate.bats` — a
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (lines ~186) — in `run_all_gates()`,
- Modify: `plugins/aid-orchestrator/scripts/aid-run-gates.sh` (line ~457) — at the existing
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-run-gates-scheduler-dispatch.bats` —
- Create: `plugins/aid-orchestrator/defaults/schemas/quarantine-remediation-evidence.schema.json`
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-quarantine-remediation-evidence.sh`
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — add rows (full required
- Modify: `plugins/aid-orchestrator/README.md` — document the scheduler's opt-in config and rollout
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-scheduler.sh` — each row's
- Create: `.aid-o/work/evidence/e2e-full-path-proof/<run_id>.json` — named output artifact, added
- Create: `plugins/aid-orchestrator/defaults/schemas/quarantine-decision.schema.json` — **new,
- Create: `plugins/aid-orchestrator/scripts/aid-quarantine-decision-record.sh` — validates BOTH
- Test: `plugins/aid-orchestrator/scripts/tests/test-integration-quarantine-pm-decision.sh` —
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` + `CHANGELOG.md` — new version entry, `Added`
- Modify: `plugins/aid-orchestrator/README.md` + `README.md` — version-file registry sync (8
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — the existing checker
