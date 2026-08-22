---
id: REF-P062
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P062-e10-calibration-promotion.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P062

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-e10-preflight.sh` — kontroluje 4 třídy: (a)
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-preflight.bats` — red-green:
- Modify: `plugins/aid-orchestrator/scripts/lib/` (nový `aid-agent-freshness.sh`) — dispatch-time
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — dispatch/konzumpce hook (kde se
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-agent-freshness.bats` — red-green:
- Modify: `plugins/aid-orchestrator/scripts/aid-evidence-verify.sh` + `aid-release-policy.sh` —
- Modify: `plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml` — pokud se
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-evidence-freshness-exception.bats` —
- Create: `plugins/aid-orchestrator/scripts/aid-control-metrics.sh` — vstup: run-evidence dirs
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-control-metrics.bats` — red-green na
- Modify: `plugins/aid-orchestrator/scripts/aid-control-metrics.sh` (+ lib) — speed sekce:
- Modify: FSM/gate-runner instrumentace (pokud chybí timestamp granularita) — zajistit, že timeline
- Create/extend: `test-control-metrics.bats` — red-green: speed sekce spočítá dispatch count +
- Create: `plugins/aid-orchestrator/scripts/tests/fixtures/e10-calibration/` — fixtury:
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-calibration-dataset.bats` —
- Create: `plugins/aid-orchestrator/scripts/aid-dual-run.sh` — pro dataset/run porovná nový verdikt
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-dual-run.bats` — red-green: fixtura
- Modify: `plugins/aid-orchestrator/scripts/aid-release-policy.sh` — per-input **5-stavová**
- Modify: `plugins/aid-orchestrator/defaults/schemas/release-decision.schema.json` — input status
- Modify: `plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml` —
- Create/extend: `test-release-policy.bats` — red-green: REQUIRED present+valid-but-content-fails →
- Modify: `plugins/aid-orchestrator/scripts/aid-control-metrics.sh` — profile-kalibrační sekce:
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-profile-calibration.bats` —
- Create: `plugins/aid-orchestrator/scripts/aid-e10-decision-table.sh` — vstup: control-metrics.json
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-e10-decision-table.bats` — red-green:
- Modify: příslušné policy soubory (`c3-audit-policy.yaml`, `release-decision-policy.yaml`,
- Modify: `plugins/aid-orchestrator/scripts/` audit dispatch (Auditor) — **Codex honesty guard
- Modify: `enforcement-registry.yaml` (nové řádky: e10_preflight, agent_freshness_check,
- **D10 guard:** žádný legacy check se v E10 nemaže; `disabled-for-calibration` JEN s explicitním
