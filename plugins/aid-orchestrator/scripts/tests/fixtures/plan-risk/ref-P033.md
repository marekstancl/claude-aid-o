---
id: REF-P033
type: plan
status: draft
---

<!-- Reference fixture for the plan ceremony-band classifier (P084 Step 1).
     Source: .aid-o/plans/P033-aid-v3-session-b.md (a real plan of this repo; .aid-o/ is gitignored, so the
     Files declarations are reproduced here to keep the reference runnable).
     The frontmatter risk: field is deliberately NOT reproduced — this fixture
     exercises the path map, and the frontmatter raise has its own case. -->

# Reference fixture P033

## Implementation Steps

### Step 1: the source plan's declared files

**Files:**
- Create: `plugins/aid-orchestrator/defaults/pre-filter-rules.yaml` — versioned regex rule table per Data Schemas section.
- Create: `plugins/aid-orchestrator/scripts/aid-prefilter.sh` (~150 lines) — bash classifier with `classify <step_n> <evidence_dir>` subcommand, exit codes 0/10/20.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-stage-log.sh` (add helper for prefilter events emission).
- Modify: `plugins/aid-orchestrator/agents/verifier.md` (lines TBD — append new section near top describing context handed to verifier).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_increment_step` (current location lines 689-783 per CP1 codebase grounding; append precondition block after existing step-N-verify.md checks, before line 778 increment commit).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — add `fsm_check_verifier_output()` helper.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — extend `fsm_count_recent_fails()` (existing Session A helper) to track step + precondition combinations for `_step` vs `_epic` classification.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — extend `check_preconditions()` EXECUTE→GATES case (lines 297-342 per CP1 codebase grounding) by appending CP3 verifier-output checks after the existing `gates_no_generated_by` check. Note: Session A `_generated_by` precondition lives in `check_preconditions`, not `cmd_transition` directly (CP1 finding); plan references `cmd_transition` semantically — actual edit is in the precondition function.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (§CP3 rewrite to instruct parallel dispatch pattern explicitly).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — add `fsm_handle_force_override()` dispatcher near top of file (after existing helpers like `fsm_check_grandfather` at line 91). New function ~25 LOC.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_init` (line 387 area) — replace inline `[[ "${8:-}" == "--force" ]] && force="true"` + existing `fsm_force_override` event with call to `fsm_handle_force_override "INIT" "READY" "$state_file" "init" "$@"` + propagate force=true to downstream logic.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_transition` (line 578 area) — same refactor pattern with caller="transition".
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_increment_step` (line 692 area) — same with caller="increment-step".
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::cmd_done_advance` (line 820 area) — same with caller="done-advance".
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — add `fsm_emit_audit_log()` helper invoking aid-audit-log.sh.
- Create: `plugins/aid-orchestrator/scripts/aid-audit-log.sh` (~60 lines) — append-only writer for `.aid-o/work/audit-log.jsonl`.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::evaluate_compliance_checks` (extend to populate verifier_outputs object + force fields).
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh::write_compliance_json` (deploy_era enum extension).
- Modify: `plugins/aid-orchestrator/scripts/aid-compliance-report.sh` (extend argument parsing + add --compare logic + reflect updates).
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — three subsection rewrites: §CP2 (pre-filter classification + per-step verifier-output enforcement), §CP3 (parallel dispatch enforcement), §force_override usage policy.
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` — Completeness Gate check #18 + forbidden phrase gate vague DoD entries.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats` (~130 lines, 6 assertions).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` (extend +5 assertions).
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-compliance.bats` (~150 lines incl. test boilerplate — file does not exist per CP1 codebase grounding M1; load test-helpers.bash, setup/teardown for compliance.json fixture EPICs, then 4 assertions).
- Modify: root `CHANGELOG.md` — add `## [2.18.0]` section with Added entries.
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical content (byte-identical per CLAUDE.md).
- Modify: `.claude-plugin/marketplace.json` — `metadata.version: "2.18.0"` + `plugins[0].version: "2.18.0"`.
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — `version: "2.18.0"`.
- Modify: `plugins/aid-orchestrator/README.md` — `Plugin: 2.18.0`.
- Modify: root `README.md` — Roadmap update (v2.18.0 prepended, v2.17.0 moved to history).
- Modify: `plugins/aid-orchestrator/DEPLOY_DATE` — refresh ISO 8601 timestamp to release time.
