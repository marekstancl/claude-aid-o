_generated_by: aid-orchestrator:verifier@s14-aid-orchestrator-E-063-1_1-step1
_generated_at: 2026-09-19T00:00:00Z
classification: FULL_REVIEW
verdict: pass
findings: []

## Review notes

Reviewed diff `ae1f7e42..0bea5bc1` in `/opt/eco/projects/aid-orchestrator` against the stated DoD/AC and in/out-of-scope lists.

### AC7 — `.aid-o/metrics/gate-runtime-baselines.yaml` (+ `.lock`) never block `init`
`plugins/aid-orchestrator/scripts/aid-fsm.sh` extends the existing clean-tree-guard `grep -vE` exclusion list to add `^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$` and the `.lock` sidecar, single-file/non-glob scoped exactly like the pre-existing `queue.yaml`/`audit-log.jsonl` entries. `test-aid-fsm.bats` adds three tests: tracked-and-dirty YAML → does not block, tracked-and-dirty `.lock` → does not block, and an unrelated file under the same directory → still blocked (regression guard against accidentally widening to a directory glob). Confirmed against the real `git status --porcelain` line format used by the guard. Satisfied.

### AC8 — `gates_report.json` gains only additive fields
`run_all_gates` in `aid-run-gates.sh` merges a `runtime_baseline` object into each gate's per-attempt JSON row via `jq --argjson rb "$runtime_baseline_json" ". + {...}"`, which cannot remove/rename existing keys — pure addition. `gate_baseline_report_json` (Step 1 library, unmodified) always returns a well-formed JSON object (never bare `null`), matching the comment's claim; verified its fallback branches (`_gbr_require_deps` failure and no-entry-yet) both return the full documented key set (`samples_count`, `non_censored_samples_count`, `p95_ms`, `timeout_recommended_seconds`, `run_mode_recommended`, `data_sufficient`, `last_attempt_result`, `policy_result`, `retryable`, `operator_action`). New test `test-aid-run-gates.bats::AC8` asserts the full pre-P063 top-level and per-gate key sets survive unchanged in kind, plus the new `runtime_baseline` key with a real (non-stub) sample. Satisfied.

### AC9 — existing (already-initialized) project's local clone gets backfilled
`aid_gate_baseline_ensure_gitignored` (new, in `aid-run-gates.sh`) is called once per `run_all_gates` invocation, uses `git check-ignore -q` to no-op when already excluded (tracked `.gitignore` or prior backfill), otherwise appends `.aid-o/metrics/` and `.aid-o/metrics/*.lock` to `.git/info/exclude` via the new generic, idempotent, append-only `gitignore_exclude_append` helper in `lib/aid-gitignore-backfill.sh`. Correctly no-ops when `AID_GATE_BASELINE_FILE` is set (test isolation seam) or outside a git work tree. `defaults/.gitignore` gets `.aid-o/metrics/` added for brand-new projects. `test-aid-gitignore-backfill.bats` covers both halves end-to-end against a real temp git repo (first-run backfill, missing-`.git/info/exclude` creation, idempotency/no-reorder, already-ignored-via-tracked-`.gitignore` short-circuit, the `AID_GATE_BASELINE_FILE` override no-op, and the brand-new-project fixture) plus unit tests for the two helper functions. Satisfied.

### Scope / forbidden-paths check
- Files touched match `step_outputs` exactly: `aid-run-gates.sh`, `defaults/.gitignore`, new `lib/aid-gitignore-backfill.sh`, `aid-fsm.sh`, new `test-aid-gitignore-backfill.bats` — plus incidental edits to `test-aid-fsm.bats` and `test-aid-run-gates.bats` to add the AC7/AC8 regression coverage and one flaky-threshold fix, both directly serving the declared step_outputs rather than new scope.
- No gate-profile (P061) or gate-selection logic changed.
- No new threshold/timing-based FSM precondition derived from baseline data was added (the FSM change is a fixed-name dirty-tree exclusion, not a timing gate).
- No UI added.
- No historical-run backfill of baseline *data* — only the git-ignore bootstrap; the baseline itself starts empty, matching the constraint.
- The one test change outside strict AC7/AC8/AC9 (`shell_pipeline_smoke` elapsed-time threshold widened 3s→5s in `test-aid-run-gates.bats`) is justified by the added per-gate `gate_baseline_update`/`gate_baseline_report_json` subprocess overhead this step itself introduces — it loosens a threshold to absorb new added-by-this-diff cost, not "speeding up the tests/gates themselves" (the forbidden item is about optimizing gate/test runtime, which this is not).
- `gate_baseline_update` call-site arguments (`$gate_name $cmd $resolved_cmd $baseline_exit_code $baseline_duration_ms $timeout_s`) match the Step 1 library's documented 6-arg signature; all referenced shell variables (`$cmd`, `$resolved_cmd`, `$timeout_s`) are in scope at the call site.

### Minor, non-blocking observation
`aid-gate-runtime-baseline.sh` (Step 1, correctly left untouched per plan.json scoping) still carries a stale `TODO(Step 2): call gate_baseline_ensure_gitignored here` comment referencing a function name (`gate_baseline_ensure_gitignored`) that was in fact implemented under a different name (`aid_gate_baseline_ensure_gitignored`) in `aid-run-gates.sh` instead, per this diff's own documented rationale (Step 1 file is out of scope for Step 2). This is a stale comment in a file this step was correctly forbidden from touching, not a functional defect — flagged only as a documentation-hygiene note for a future step, not a DoD/AC failure.
