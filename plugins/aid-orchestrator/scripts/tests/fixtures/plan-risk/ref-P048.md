---
id: REF-P048
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P048-ui-design-to-code-fidelity-mvp.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P048

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/lib/ui-fidelity/package.json` — a STANDARD Node manifest (name
- Create: `plugins/aid-orchestrator/lib/ui-fidelity/package-lock.json` — pinned lockfile for `npm ci`.
- Create: `plugins/aid-orchestrator/lib/ui-fidelity/ui-capture.mjs` — Playwright capture script.
- Test: `plugins/aid-orchestrator/scripts/tests/test-ui-capture.sh` — runs the script against the hermetic
- Create: `plugins/aid-orchestrator/defaults/templates/ui-change-contract.schema.json` — JSON-Schema doc (reference/documentation form).
- Create: `plugins/aid-orchestrator/scripts/gates/ui-contract-check.sh` — bash+yq validator modeled on `scripts/gates/scope-check.sh`.
- Create: `plugins/aid-orchestrator/defaults/templates/ui-change-contract.example.yaml` — a filled `existing_ui` example used by tests and docs.
- Test: `plugins/aid-orchestrator/scripts/tests/test-ui-contract-check.sh` — valid and invalid contracts, asserts pass/fail and exit codes.
- Create: `plugins/aid-orchestrator/lib/ui-fidelity/ui-capture-fixtures.mjs` — resolves a `state_fixture`
- Modify: `plugins/aid-orchestrator/lib/ui-fidelity/ui-capture.mjs` (option-parsing + pre-navigation block) —
- Test: `plugins/aid-orchestrator/scripts/tests/fixtures/ui/sample-table.html` — a hermetic fixture page
- Create: `plugins/aid-orchestrator/lib/ui-fidelity/ui-compare.mjs` — Node + pixelmatch/pngjs comparator.
- Modify: `plugins/aid-orchestrator/lib/ui-fidelity/package.json` (dependencies) — add `pixelmatch`, `pngjs`; refresh `package-lock.json`.
- Test: `plugins/aid-orchestrator/scripts/tests/test-ui-compare.sh` — asserts PASS on a correctly-applied delta, FAIL on an UN-applied delta, FAIL on a locked change, PASS on an in-bounds affected shift; skips-with-notice if deps absent.
- Modify: `plugins/aid-orchestrator/skills/visual-companion/SKILL.md` (lines ~48-98, "Refactoring or
- Modify: `plugins/aid-orchestrator/skills/visual-companion/SKILL.md` (lines ~340-343) — point the 1:1 size rule at captured `baseline-computed.json`, not sizes "read from code".
- Test: `plugins/aid-orchestrator/scripts/tests/test-companion-contract-output.sh` — asserts the companion flow writes a contract that passes `ui-contract-check.sh` for the hermetic fixture.
- Modify: `plugins/aid-orchestrator/skills/role-cards.md` (lines ~119-160, `## Role: frontend`) — add a `## UI Change Contract` protocol.
- Modify: `plugins/aid-orchestrator/skills/agent-protocol.md` (frontend dispatch context that injects `visual_refs`) — inject the `ui_change_contract` path + implementation-reference.
- Test: `plugins/aid-orchestrator/scripts/tests/test-role-cards-ui-contract.sh` — greps the frontend card for the typed-delta and no-redesign rules and the contract reference.
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` — TWO objects: (1) `visual_assets.source_type` enum (line 237) — add `companion`; (2) the **step object** (`steps[].properties`, closes `additionalProperties:false` at line 141) — add optional `ui_change_mode` (enum `existing_ui|greenfield|none`) + `ui_change_contract` (string path).
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` — carry `ui_change_mode` + `ui_change_contract` from the plan step into the generated EPIC `.md` step block (today it drops them).
- Modify: `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` — parse those two fields and emit them into the step object in `plan.json` (today it assembles only `num/role/objective/depends/parallel`, lines 137-141/212-216).
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (the `## UI Design` / `## Visual Specification` section, lines ~119-131) — document the per-step contract reference + the positive assertion.
- Test: `plugins/aid-orchestrator/scripts/tests/test-ui-contract-transport.sh` — a plan with a frontend `existing_ui` step → `aid-plan-to-epic.sh` → `aid-epic-to-json.sh` → assert `plan.json` step carries `ui_change_mode` + `ui_change_contract`.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (Visual verification protocol, lines ~399-415) — for `existing_ui` steps run capture+compare; the verdict gates the step; capture/compare unavailable is BLOCKED, not warn+skip; the Controller no longer judges the locked/affected/delta verdict; the gestalt remains an explicit recorded PM approval.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (the `increment-step` frontend check around `frontend_missing_visual_anchoring`) — for `ui_change_mode: existing_ui` steps, require a PASS `verdict.json` + present `gestalt_approval`; hard-fail `ui_contract_verdict_fail` / `ui_capture_unavailable` / `ui_contract_missing` / `ui_gestalt_unapproved`.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-fsm-ui-fidelity.bats` — FSM blocks on FAIL verdict, on capture-absent, and on missing/mismatched gestalt approval; passes on PASS.
- Modify: `plugins/aid-orchestrator/defaults/.gitignore` — ignore `.aid-o/work/**/ui/` capture artifacts.
- Create: `plugins/aid-orchestrator/defaults/config/ui-fixtures.example.yaml` — `state_fixture` descriptor format + the fixture-not-production rule.
- Create: `.github/workflows/ui-fidelity.yml` (**repo root** — GitHub Actions only runs workflows under the
- Create: `plugins/aid-orchestrator/lib/ui-fidelity/setup.sh` — one-shot bootstrap (`npm ci` +
- Modify: root `README.md` + `plugins/aid-orchestrator/README.md` + both `CHANGELOG.md` (identical `### Added` entry) — document the feature.
- Modify: `docs/extending-aid.md` (repo root) + `docs/plans/AID-audit-2026-06/enforcement-registry.yaml` (repo root) — register the two enforcements.
- Create: `plugins/aid-orchestrator/scripts/tests/test-ui-fidelity-e2e.sh` — E2E driver chaining capture → contract-check → transport (plan→epic→json) → compare → FSM gate over the hermetic fixture; distinct from the Step 4 unit test.
- Modify: `.github/workflows/ui-fidelity.yml` (repo root, created in Step 9) — APPEND the e2e invocation to the mandatory job so the full chain runs in CI with Chromium installed.
