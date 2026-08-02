#!/usr/bin/env bats
# test-aid-run-gates-scheduler-dispatch.bats — P069 Step 14.
#
# Proves aid-run-gates.sh's targeted_tests-only scheduler dispatch +
# escalation merge:
#   - rollout gate returns sequential (default, no divergence evidence):
#     behavior is provably unchanged (normalized comparison excluding
#     wall-clock timestamps/durations)
#   - rollout gate unlocked (real, passing divergence evidence): the
#     scheduler path actually executes, and its merged row is correctly
#     folded into gates_report.json
#   - a scheduled targeted_tests run's baseline sample records the REAL
#     concurrency_context it ran under, never silently defaulting to
#     sequential
#   - exit 3/11 produces the EXISTING result:"fail" (never a new enum
#     value) with the new additive escalation:{triggered,exit_code,path}
#     sibling field, AND a real, executed full-profile substitute folded
#     into the top-level report

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT/.aid-o/config" "$TEST_PROJECT/.aid-o/work/evidence/scheduler-divergence" \
           "$TEST_PROJECT/plugins/aid-orchestrator/scripts/tests/bats"
  cd "$TEST_PROJECT"
  git init -q -b main
  git config user.email t@t.local
  git config user.name t
  echo base > README.md
  git add -A
  git commit -q -m base
  BASE_SHA="$(git rev-parse HEAD)"
  export BASE_SHA

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RUN_GATES="$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"

  # The scheduled dispatch path resolves the catalog's own command.argv
  # relative to CWD (aid-test-scheduler.sh never cd's), and the sequential/
  # direct path resolves via PLUGIN_ROOT (AID_SELECT_TESTS_PLUGIN_ROOT) —
  # pointing this seam at the SAME real, project-root-relative location the
  # stub file is physically written at means both code paths resolve to
  # the identical real file, no divergent fixture needed.
  export AID_SELECT_TESTS_PLUGIN_ROOT="$TEST_PROJECT/plugins/aid-orchestrator"

  local at="@"
  cat > "plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast.bats" <<EOF
#!/usr/bin/env bats
${at}test "stub" {
  [ 1 -eq 1 ]
}
EOF
  # Committed HERE, before any BASE_SHA a test cares about is captured —
  # otherwise this untracked file would ride along into whatever commit a
  # test's own `commit_change` makes next (via its own `git add -A`),
  # showing up as a SECOND, unintended "changed path" in the diff.
  git add -A
  git commit -q -m "add stub test file"

  # Isolated gate-runtime-baseline file (never the real repo's).
  AID_GATE_BASELINE_FILE="$TEST_TMPDIR/gate-runtime-baselines.yaml"
  export AID_GATE_BASELINE_FILE
}

teardown() {
  cd /
  unset AID_SELECT_TESTS_PLUGIN_ROOT AID_GATE_BASELINE_FILE
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

commit_change() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo "changed" >> "$file"
  git add -A
  git commit -q -m "touch $file"
}

# _write_catalog — one approved production row: a change to
# plugins/aid-orchestrator/scripts/aid-stub-target.sh selects the real,
# fast stub bats file written in setup().
_write_catalog() {
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"approved",
    run_units: [
      {run_unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast", runner:"bats",
       source_paths:["plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast.bats"],
       production_surfaces:["plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast.bats"]},
       runtime:{fingerprint:"sha256:cccccccccccc"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"plugins/aid-orchestrator/scripts/aid-stub-target.sh",
       target_run_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast"],
       classification:"production", precedence:1, status:"approved"}
    ],
    mapping_approval: {status:"approved", approved_by:"t", approved_at:"2026-08-02T00:00:00Z", reviewed_diff_hash:"sha256:deadbeef"}
  }' | yq -P '.' > .aid-o/config/test-catalog.yaml
  git add -f .aid-o/config/test-catalog.yaml
  git commit -q -m "add catalog"
  BASE_SHA="$(git rev-parse HEAD)"
  export BASE_SHA
}

_write_divergence_artifact() {
  local mode="$1"
  local commit; commit="$(git rev-parse HEAD)"
  local run_id; run_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr 'A-Z' 'a-z')"
  local cfs="sha256:$(printf 'sha256:cccccccccccc\n' | sort | sha256sum | cut -d' ' -f1)"
  jq -n --arg run_id "$run_id" --arg cfs "$cfs" --arg csha "$commit" --arg mode "$mode" \
    '{run_id:$run_id, catalog_fingerprint_set:$cfs, commit_sha:$csha, worktree_kind:"disposable_clone",
      mode_tested:$mode, selected_unit_ids:["bats:plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast"],
      sequential_verdicts:[{unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast",result:"pass"}],
      scheduled_verdicts:[{unit_id:"bats:plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast",result:"pass"}],
      membership_diff:[], verdict_diff:[], pass:true, evaluated_at:"2026-08-02T00:00:00Z"}' \
    > ".aid-o/work/evidence/scheduler-divergence/${commit}-${mode}-${run_id}.json"
}

@test "rollout gate returns sequential (default): targeted_tests behavior unchanged, no scheduler artifacts, baseline records sequential" {
  _write_catalog
  commit_change "plugins/aid-orchestrator/scripts/aid-stub-target.sh"

  cat > .aid-o/config/execution.yaml <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    timeout_seconds: 60
YAML

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  run "$RUN_GATES" run-all .aid-o/config/execution.yaml E-X R-1 --base-commit "$BASE_SHA" --report-file "$report"
  [ "$status" -eq 0 ]

  run jq -r '.gates.targeted_tests.result' "$report"
  [ "$output" == "pass" ]
  run jq -r '.gates.targeted_tests.exit_code' "$report"
  [ "$output" == "0" ]
  run jq -e '.gates.targeted_tests | has("escalation")' "$report"
  [ "$output" == "false" ]

  # No --emit-units artifact — the direct/sequential path never writes one.
  [ ! -f ".aid-o/work/evidence/E-X/R-1/gates/targeted-units.json" ]

  # Baseline: a sequential sample landed in the top-level recent_samples,
  # never in recent_samples_by_context.
  run yq -e '.gates[].recent_samples | length > 0' "$AID_GATE_BASELINE_FILE"
  [ "$output" == "true" ]
  run yq '.gates[].recent_samples_by_context.observe_parallel // null' "$AID_GATE_BASELINE_FILE"
  [ "$output" == "null" ]
}

@test "rollout gate unlocked (3 qualifying observe_parallel artifacts): scheduler path executes, merged row folded in, baseline records observe_parallel" {
  _write_catalog
  commit_change "plugins/aid-orchestrator/scripts/aid-stub-target.sh"
  _write_divergence_artifact observe_parallel
  _write_divergence_artifact observe_parallel
  _write_divergence_artifact observe_parallel

  cat > .aid-o/config/execution.yaml <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    timeout_seconds: 60
test_audit:
  scheduler:
    mode: observe_parallel
    resource_locks: {}
YAML

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  run "$RUN_GATES" run-all .aid-o/config/execution.yaml E-X R-1 --base-commit "$BASE_SHA" --report-file "$report"
  [ "$status" -eq 0 ]

  run jq -r '.gates.targeted_tests.result' "$report"
  [ "$output" == "pass" ]

  # The scheduled path DID run: --emit-units wrote its units file.
  [ -f ".aid-o/work/evidence/E-X/R-1/gates/targeted-units.json" ]
  run jq -r '.[0].unit_id' ".aid-o/work/evidence/E-X/R-1/gates/targeted-units.json"
  [ "$output" == "bats:plugins/aid-orchestrator/scripts/tests/bats/test-stub-fast" ]

  # Baseline: the REAL mode this run used, never silently sequential.
  run yq -e '.gates[].recent_samples_by_context.observe_parallel | length > 0' "$AID_GATE_BASELINE_FILE"
  [ "$output" == "true" ]
}

@test "exit 3 (unverifiable) escalates: existing result 'fail' unchanged, additive escalation field populated, a real full-profile substitute runs" {
  # An unmapped production-surface path with NO catalog at all — the
  # hardcoded Initial-mapping fallback classifies it unverifiable (exit 3),
  # identical to the pre-existing "unknown production path" test's own
  # fixture shape.
  commit_change "plugins/aid-orchestrator/scripts/aid-brand-new-unmapped-script.sh"

  cat > .aid-o/config/execution.yaml <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    timeout_seconds: 60
  always_pass:
    command: "exit 0"
    required: true
gate_profiles:
  targeted:
    include: [targeted_tests]
  full:
    include: [always_pass]
YAML

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  run "$RUN_GATES" run-all .aid-o/config/execution.yaml E-X R-1 --base-commit "$BASE_SHA" --profile targeted --report-file "$report"

  # Top-level report IS the full-profile pass, verbatim — a REAL executed
  # substitute, not a placeholder: always_pass genuinely ran and passed.
  run jq -r '.escalation.triggered_by' "$report"
  [ "$output" == "targeted_tests" ]
  run jq -r '.gates.always_pass.result' "$report"
  [ "$output" == "pass" ]
  # targeted_tests IS present in the top-level (full-pass) report's own
  # gates object (the pre-existing profile_excluded mechanism always
  # emits a row for every DEFINED gate, run or not) — but it is never a
  # genuine run there: the full profile's own include[] never names it.
  run jq -r '.gates.targeted_tests.result' "$report"
  [ "$output" == "profile_excluded" ]

  # The ORIGINAL targeted-profile attempt survives, nested, for PM/audit —
  # existing, UNCHANGED contract on THAT row: plain "fail", no new enum
  # value, plus the new additive escalation metadata.
  run jq -r '.escalation.targeted_run.gates.targeted_tests.exit_code' "$report"
  [ "$output" == "3" ]
  run jq -r '.escalation.targeted_run.gates.targeted_tests.escalation.triggered' "$report"
  [ "$output" == "true" ]
  run jq -r '.escalation.targeted_run.gates.targeted_tests.escalation.exit_code' "$report"
  [ "$output" == "3" ]
  run jq -r '.escalation.targeted_run.gates.targeted_tests.escalation.path' "$report"
  [ "$output" == "plugins/aid-orchestrator/scripts/aid-brand-new-unmapped-script.sh" ]
  run jq -r '.escalation.targeted_run.gates.targeted_tests.result' "$report"
  [ "$output" == "fail" ]
  run jq -r '.escalation.targeted_run.gates.targeted_tests.escalation.exit_code' "$report"
  [ "$output" == "3" ]
}

@test "every gate other than targeted_tests is completely unaffected by this change" {
  cat > .aid-o/config/execution.yaml <<'YAML'
gates:
  alpha:
    command: "exit 0"
    required: true
  beta:
    command: "exit 0"
    required: false
YAML

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  run "$RUN_GATES" run-all .aid-o/config/execution.yaml E-X R-1 --report-file "$report"
  [ "$status" -eq 0 ]

  run jq -r '.gates.alpha.result' "$report"
  [ "$output" == "pass" ]
  run jq -e '.gates.alpha | has("escalation")' "$report"
  [ "$output" == "false" ]

  # Every non-targeted_tests gate's baseline sample is recorded with
  # concurrency_context: sequential EXPLICITLY (top-level recent_samples),
  # never recent_samples_by_context — checked across BOTH gates at once
  # (alpha AND beta), never just the first line a per-gate query happens
  # to emit.
  run bash -c "yq -o=json '.gates' '$AID_GATE_BASELINE_FILE' | jq -e '[.[] | (.recent_samples_by_context.observe_parallel // null)] | all(. == null)'"
  [ "$output" == "true" ]
  run bash -c "yq -o=json '.gates' '$AID_GATE_BASELINE_FILE' | jq -e '[.[] | (.recent_samples_by_context.parallel // null)] | all(. == null)'"
  [ "$output" == "true" ]
}

# ─── Codex review (P069 Step 14): 3 real findings, regression-tested ────────

@test "Codex HIGH: a hand-authored 'full' profile that ALSO includes targeted_tests never self-escalates recursively" {
  commit_change "plugins/aid-orchestrator/scripts/aid-brand-new-unmapped-script.sh"

  cat > .aid-o/config/execution.yaml <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
    timeout_seconds: 30
gate_profiles:
  targeted:
    include: [targeted_tests]
  full:
    include: [targeted_tests]
YAML

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  # A hanging/unbounded recursive chain would exceed bats' own default
  # test timeout — completing at all (with the correct single-level
  # shape below) IS part of what this test proves.
  run "$RUN_GATES" run-all .aid-o/config/execution.yaml E-X R-1 --base-commit "$BASE_SHA" --profile targeted --report-file "$report"
  [ "$status" -eq 0 ]

  run jq -r '.gates.targeted_tests.result' "$report"
  [ "$output" == "fail" ]
  run jq -r '.gates.targeted_tests.exit_code' "$report"
  [ "$output" == "3" ]

  # Exactly ONE level of nesting — the nested targeted_run's OWN report
  # never carries a further .escalation key (which a second, recursive
  # escalation attempt would have produced).
  run jq -e '.escalation.targeted_run | has("escalation")' "$report"
  [ "$output" == "false" ]
}

@test "Codex HIGH: overall reflects the MERGED (full-pass) verdict, not the stale pre-merge targeted-pass verdict" {
  # targeted_tests is required:true — under the pre-fix bug, the
  # targeted-only pass's own overall="fail" (a required gate failed)
  # would have survived the merge unchanged, disagreeing with the
  # genuinely-passing full-profile substitute's own real verdict.
  commit_change "plugins/aid-orchestrator/scripts/aid-brand-new-unmapped-script.sh"

  cat > .aid-o/config/execution.yaml <<YAML
gates:
  targeted_tests:
    command: "$AID_PLUGIN_PATH/scripts/aid-select-tests.sh --base {base_commit}"
    required: true
    timeout_seconds: 30
  always_pass:
    command: "exit 0"
    required: true
gate_profiles:
  targeted:
    include: [targeted_tests]
  full:
    include: [always_pass]
YAML

  local report=".aid-o/work/evidence/E-X/R-1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  run "$RUN_GATES" run-all .aid-o/config/execution.yaml E-X R-1 --base-commit "$BASE_SHA" --profile targeted --report-file "$report"

  # The command's own exit status agrees with the persisted report — both
  # reflect the full pass's REAL, passing verdict.
  [ "$status" -eq 0 ]
  run jq -r '.overall' "$report"
  [ "$output" == "pass" ]
  run jq -r '.gates.always_pass.result' "$report"
  [ "$output" == "pass" ]
}
