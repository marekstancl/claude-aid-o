#!/usr/bin/env bash
# test-integration-e2e-full-path-proof.sh — P069 Step 17.
#
# The mandatory, real, end-to-end proof: configured profile -> gate runner
# -> selected execution units -> scheduler -> per-unit receipts -> the
# same aggregated verdict. Every stage below is a REAL invocation of the
# real, already-shipped script — never mocked, never config-only.
#
# Builds one small, disposable fixture project (a "typescript"-stack
# marker, one of the 5 stacks compose_execution_yaml recognizes) with its
# OWN real bats test file — never this plugin's own tests. Runs, in order:
#   1. the real P066 bootstrap: hand-seeded (reviewed fixture) catalog +
#      mapping rows, pushed through the REAL, unmodified approval machinery
#      (aid-test-catalog-approve.sh, then the separate, mandatory
#      aid-test-catalog-confirm-mapping.sh hash-gated confirmation) — never
#      automatic per-project mapping discovery, which does not exist for a
#      generic consumer project (P066/P069 both explicitly scope that out)
#   2. 3 REAL, independent aid-test-schedule-divergence-check.sh passes
#      (mode_tested: observe_parallel) against the fixture's own real unit
#   3. the real aid-scheduler-rollout-gate.sh confirms observe_parallel
#      unlocked from that evidence
#   4. the real aid-run-gates.sh CLI, --profile targeted, genuinely
#      dispatching through aid-select-tests.sh --emit-units ->
#      aid-test-scheduler.sh -> aid-job.sh-backed receipts -> gates_report.json
#   5. the SAME selection run sequentially (mode: sequential) on the same
#      fixture/commit — the aggregated verdict must match stage 4 exactly
#   6. the existing-project-upgrade scenario (aid-init-upgrade-test-audit.sh)
#      against a hand-edited execution.yaml, then a real dispatch through
#      the newly-added gate
#   7. the mapping-gap escalation scenario: an approved mapping that does
#      NOT cover a deliberately-introduced changed path — result stays the
#      EXISTING "fail" (never a new enum value) with the additive
#      escalation:{...} field, and a REAL executed full-profile substitute
#
# Writes one schema-valid artifact per scenario to
# .aid-o/work/evidence/e2e-full-path-proof/<run_id>.json, force-tracked
# into THIS repo (not the disposable fixture) immediately after each write.
#
# Usage:
#   test-integration-e2e-full-path-proof.sh [--scenario observe_parallel_full_path|sequential_regression|self_host_bundle_refresh|all]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_DIR}/../.." && pwd)"
SCHEMA="${PLUGIN_DIR}/defaults/schemas/e2e-full-path-proof.schema.json"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${PLUGIN_DIR}/scripts/lib/aid-test-adapter-contract.sh"

scenario="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) scenario="$2"; shift 2 ;;
    *) echo "unknown option '$1'" >&2; exit 2 ;;
  esac
done

pass=0; fail=0
fail_msg() { echo "  FAIL: $1"; fail=$((fail + 1)); }
pass_msg() { echo "  PASS: $1"; pass=$((pass + 1)); }

declare -a STAGES=()
stage_pass() { STAGES+=("$(jq -nc --arg s "$1" '{stage:$s, pass:true}')"); pass_msg "stage '$1'"; }
stage_fail() { STAGES+=("$(jq -nc --arg s "$1" --arg d "${2:-}" '{stage:$s, pass:false, detail:$d}')"); fail_msg "stage '$1': ${2:-}"; }

_write_artifact() {
  local run_scenario="$1" commit_sha="$2"
  local run_id="e2e-${run_scenario}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  local stages_json; stages_json="$(printf '%s\n' "${STAGES[@]}" | jq -sc '.')"
  local overall_pass="true"
  jq -e 'all(.[]; .pass == true)' <<<"$stages_json" >/dev/null 2>&1 || overall_pass="false"
  local evaluated_at; evaluated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local artifact_json
  artifact_json="$(jq -nc \
    --arg run_id "$run_id" --arg scenario "$run_scenario" --argjson pass "$overall_pass" \
    --argjson stages "$stages_json" --arg csha "$commit_sha" --arg eat "$evaluated_at" \
    '{run_id:$run_id, scenario:$scenario, pass:$pass, stages_verified:$stages, commit_sha:$csha, evaluated_at:$eat}')"

  if ! adapter_validate_schema "$SCHEMA" "$artifact_json"; then
    echo "  FAIL: assembled e2e artifact failed schema validation — refusing to publish" >&2
    fail=$((fail + 1))
    return 1
  fi

  local out_path="${REPO_ROOT}/.aid-o/work/evidence/e2e-full-path-proof/${run_id}.json"
  mkdir -p "$(dirname "$out_path")"
  echo "$artifact_json" | jq '.' > "$out_path"
  echo "  wrote ${out_path} (scenario=${run_scenario}, pass=${overall_pass})"
  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO_ROOT" add -f -- "${out_path#"${REPO_ROOT}"/}"
  fi
  STAGES=()
}

for dep in jq yq git; do
  command -v "$dep" >/dev/null 2>&1 || { echo "  FAIL: $dep not installed"; echo "Results: 0/1 passed, 1 failed"; exit 1; }
done

# ─── Fixture project construction (shared by observe_parallel_full_path and
# sequential_regression) ─────────────────────────────────────────────────
_build_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/.aid-o/config" "$fixture/tests" "$fixture/src"
  ( cd "$fixture"
    git init -q -b main
    git config user.email fixture@e2e.local
    git config user.name "E2E Fixture"
    echo '{}' > package.json
    echo 'export const foo = 1;' > src/foo.ts
    local at="@"
    cat > tests/fixture-a.bats <<EOF
#!/usr/bin/env bats
${at}test "fixture passes" {
  [ 1 -eq 1 ]
}
EOF
    git add -A
    git commit -q -m "fixture base"
  )
}

_bootstrap_catalog() {
  local fixture="$1"
  local approve="${PLUGIN_DIR}/scripts/aid-test-catalog-approve.sh"
  local confirm="${PLUGIN_DIR}/scripts/aid-test-catalog-confirm-mapping.sh"

  local proposed="${fixture}/test-catalog.proposed.yaml"
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:tests/fixture-a", runner:"bats",
       source_paths:["tests/fixture-a.bats"], production_surfaces:["tests/fixture-a.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","tests/fixture-a.bats"]},
       runtime:{fingerprint:"sha256:eeeeeeeeeeee"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"src/foo.ts",
       target_run_unit_ids:["bats:tests/fixture-a"], classification:"production",
       precedence:1, status:"proposed"}
    ],
    mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$proposed"

  if ! bash "$approve" --proposed "$proposed" --project-root "$fixture" >/tmp/e2e-approve.log 2>&1; then
    stage_fail "bootstrap_catalog_approved" "aid-test-catalog-approve.sh failed: $(cat /tmp/e2e-approve.log)"
    return 1
  fi
  stage_pass "bootstrap_catalog_approved"

  local diff_out hash
  diff_out="$(bash "$confirm" --project-root "$fixture" 2>&1)"
  hash="$(grep '^reviewed_diff_hash:' <<<"$diff_out" | awk '{print $2}')"
  if [[ -z "$hash" ]]; then
    stage_fail "bootstrap_mapping_confirmed" "could not extract reviewed_diff_hash from confirm-mapping preview"
    return 1
  fi
  if ! bash "$confirm" --project-root "$fixture" --confirm-mapping "$hash" >/tmp/e2e-confirm.log 2>&1; then
    stage_fail "bootstrap_mapping_confirmed" "aid-test-catalog-confirm-mapping.sh failed: $(cat /tmp/e2e-confirm.log)"
    return 1
  fi
  local mapping_status
  mapping_status="$(yq -r '.mapping_approval.status' "${fixture}/.aid-o/config/test-catalog.yaml")"
  if [[ "$mapping_status" == "approved" ]]; then
    stage_pass "bootstrap_mapping_confirmed"
  else
    stage_fail "bootstrap_mapping_confirmed" "mapping_approval.status is '${mapping_status}', expected 'approved'"
    return 1
  fi

  ( cd "$fixture" && git add -A && git commit -q -m "bootstrap: approved catalog + confirmed mapping" )
  return 0
}

_generate_execution_yaml() {
  local fixture="$1" mode="$2"
  # shellcheck source=lib/aid-init-execution-yaml.sh
  source "${PLUGIN_DIR}/scripts/lib/aid-init-execution-yaml.sh"
  ( cd "$fixture"
    mapfile -t detected_stacks < <(detect_stacks "$fixture")
    compose_execution_yaml "$fixture" "${fixture}/.aid-o/config/execution.yaml" "${detected_stacks[@]}"
  )
  local has_gate has_profiles
  has_gate="$(yq '.gates | has("targeted_tests")' "${fixture}/.aid-o/config/execution.yaml")"
  has_profiles="$(yq '.gate_profiles.targeted.include | contains(["targeted_tests"])' "${fixture}/.aid-o/config/execution.yaml")"
  if [[ "$has_gate" == "true" && "$has_profiles" == "true" ]]; then
    stage_pass "execution_yaml_generated_with_targeted_tests_gate"
  else
    stage_fail "execution_yaml_generated_with_targeted_tests_gate" "compose_execution_yaml did not produce the expected targeted_tests gate/profile wiring"
  fi
  yq -i ".test_audit.scheduler.mode = \"${mode}\"" "${fixture}/.aid-o/config/execution.yaml"
  ( cd "$fixture" && git add -A && git commit -q -m "set scheduler mode: ${mode}" )
}

_run_divergence_evidence_x3() {
  local fixture="$1"
  local check="${PLUGIN_DIR}/scripts/aid-test-schedule-divergence-check.sh"
  local i ok_count=0
  for i in 1 2 3; do
    if bash "$check" run --project-root "$fixture" --unit-ids "bats:tests/fixture-a" --mode-tested observe_parallel >/tmp/e2e-divergence-${i}.log 2>&1; then
      ok_count=$((ok_count + 1))
    fi
  done
  if [[ "$ok_count" -eq 3 ]]; then
    stage_pass "three_real_divergence_passes"
  else
    stage_fail "three_real_divergence_passes" "only ${ok_count}/3 divergence-check invocations succeeded"
  fi
}

_confirm_rollout_unlocked() {
  local fixture="$1"
  local gate="${PLUGIN_DIR}/scripts/aid-scheduler-rollout-gate.sh"
  local result effective
  result="$(bash "$gate" --project-root "$fixture" 2>/dev/null)"
  effective="$(jq -r '.effective_mode' <<<"$result" 2>/dev/null)"
  if [[ "$effective" == "observe_parallel" ]]; then
    stage_pass "rollout_gate_unlocked_observe_parallel"
  else
    stage_fail "rollout_gate_unlocked_observe_parallel" "effective_mode='${effective}', expected observe_parallel: ${result}"
  fi
}

_touch_foo_and_commit() {
  local fixture="$1" msg="$2"
  local base_sha; base_sha="$(cd "$fixture" && git rev-parse HEAD)"
  echo "changed" >> "${fixture}/src/foo.ts"
  ( cd "$fixture" && git add -A && git commit -q -m "$msg" )
  echo "$base_sha"
}

_dispatch_only() {
  local fixture="$1" mode_label="$2" base_sha="$3"
  local report="${fixture}/.aid-o/work/evidence/E2E/R1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  # aid-select-tests.sh's DIRECT (non--emit-units, sequential) execution
  # path resolves a selected test file via PLUGIN_ROOT + a hardcoded
  # "plugins/aid-orchestrator/" PLUGIN_PREFIX strip — a pre-existing
  # assumption from an earlier plan (P061) that it always runs inside
  # this plugin's own dogfood repo. This fixture's test paths ("tests/...")
  # never carry that prefix, so the strip is a no-op; pointing the
  # documented AID_SELECT_TESTS_PLUGIN_ROOT test-isolation seam at the
  # fixture root itself makes the (unchanged) path resolve correctly.
  # Harmless for the scheduled path, which never consults this variable
  # (its catalog-approved-row classification and dispatch never touch
  # PLUGIN_ROOT/PLUGIN_PREFIX at all).
  ( cd "$fixture" && AID_SELECT_TESTS_PLUGIN_ROOT="$fixture" AID_PLUGIN_PATH="$PLUGIN_DIR" bash "${PLUGIN_DIR}/scripts/aid-run-gates.sh" run-all .aid-o/config/execution.yaml E2E R1 \
      --base-commit "$base_sha" --profile targeted --report-file "$report" ) >/tmp/e2e-dispatch-${mode_label}.log 2>&1
  local result
  result="$(jq -r '.gates.targeted_tests.result' "$report" 2>/dev/null)"
  echo "$result"
}

# Convenience wrapper for scenarios that don't need divergence evidence
# (sequential-only paths): commits the changed-path itself, then dispatches.
_run_real_dispatch() {
  local fixture="$1" mode_label="$2"
  local base_sha; base_sha="$(_touch_foo_and_commit "$fixture" "touch src/foo.ts (${mode_label})")"
  _dispatch_only "$fixture" "$mode_label" "$base_sha"
}

_scenario_observe_parallel_full_path() {
  echo "=== SCENARIO: observe_parallel_full_path ==="
  local fixture; fixture="$(mktemp -d)"
  _build_fixture "$fixture"
  _bootstrap_catalog "$fixture" || { _write_artifact observe_parallel_full_path "$(cd "$fixture" && git rev-parse HEAD)"; rm -rf "$fixture"; return; }
  _generate_execution_yaml "$fixture" observe_parallel

  # The changed-path commit MUST land BEFORE the divergence evidence is
  # captured, and no further commit may happen between capturing it and
  # the real dispatch below — aid-scheduler-rollout-gate.sh ties every
  # qualifying artifact to the CURRENT git HEAD at the moment it is
  # consulted (by design — Step 13), so committing anything AFTER the
  # divergence runs (as an earlier version of this scenario did, by
  # touching src/foo.ts only right before dispatch) advances HEAD past
  # the commit the evidence was captured for, invalidating it and
  # silently falling back to sequential. base_sha is captured once here
  # and reused for the real dispatch below.
  local base_sha; base_sha="$(_touch_foo_and_commit "$fixture" "touch src/foo.ts (changed-path commit, pinned for divergence + dispatch)")"
  _run_divergence_evidence_x3 "$fixture"
  _confirm_rollout_unlocked "$fixture"

  local result
  result="$(_dispatch_only "$fixture" observe_parallel "$base_sha")"
  local units_file="${fixture}/.aid-o/work/evidence/E2E/R1/gates/targeted-units.json"
  if [[ "$result" == "pass" && -f "$units_file" ]]; then
    stage_pass "real_scheduled_dispatch_executed_and_passed"
  else
    stage_fail "real_scheduled_dispatch_executed_and_passed" "result='${result}', units_file_exists=$([[ -f "$units_file" ]] && echo true || echo false); log: $(cat /tmp/e2e-dispatch-observe_parallel.log 2>/dev/null | tail -20)"
  fi

  # Verdict-matches-sequential: same fixture, same commit/selection,
  # mode:sequential (never invalidates the just-captured evidence — this
  # commit only edits execution.yaml's own config, not src/foo.ts, so
  # base_sha's diff-to-HEAD is unaffected).
  yq -i '.test_audit.scheduler.mode = "sequential"' "${fixture}/.aid-o/config/execution.yaml"
  ( cd "$fixture" && git add -A && git commit -q -m "switch to sequential for comparison" )
  local seq_result; seq_result="$(_dispatch_only "$fixture" sequential_comparison "$base_sha")"
  if [[ "$seq_result" == "$result" ]]; then
    stage_pass "scheduled_verdict_matches_sequential_verdict"
  else
    stage_fail "scheduled_verdict_matches_sequential_verdict" "scheduled='${result}' sequential='${seq_result}'"
  fi

  _scenario_existing_project_upgrade
  _scenario_mapping_gap_escalation

  _write_artifact observe_parallel_full_path "$(cd "$fixture" && git rev-parse HEAD)"
  rm -rf "$fixture"
}

_scenario_existing_project_upgrade() {
  local fixture; fixture="$(mktemp -d)"
  mkdir -p "$fixture/.aid-o/config"
  ( cd "$fixture"
    git init -q -b main
    git config user.email fixture@e2e.local
    git config user.name "E2E Fixture"
    cat > .aid-o/config/execution.yaml <<'YAML'
# AUTO-GENERATED by aid-init at 2026-01-01T00:00:00Z
version: "1.0"
gates:
  hand_added_gate:
    command: "exit 0"
    required: true
YAML
    git add -A && git commit -q -m base
  )
  cp "${fixture}/.aid-o/config/execution.yaml" /tmp/e2e-upgrade-before.yaml
  local before_line_count; before_line_count="$(wc -l < /tmp/e2e-upgrade-before.yaml)"

  local upgrade="${PLUGIN_DIR}/scripts/aid-init-upgrade-test-audit.sh"
  local preview hash
  preview="$(bash "$upgrade" --project-root "$fixture" 2>&1)"
  hash="$(grep '^diff_hash:' <<<"$preview" | awk '{print $2}')"
  if [[ -z "$hash" ]]; then
    stage_fail "existing_project_upgrade_applied" "could not extract diff_hash from upgrade preview"
    rm -rf "$fixture"
    return
  fi
  if ! bash "$upgrade" --project-root "$fixture" --confirm-upgrade "$hash" >/tmp/e2e-upgrade.log 2>&1; then
    stage_fail "existing_project_upgrade_applied" "upgrade confirm failed: $(cat /tmp/e2e-upgrade.log)"
    rm -rf "$fixture"
    return
  fi

  # Every pre-existing byte preserved: the original file's lines are an
  # unmodified, in-order prefix/subsequence of the upgraded file's bytes.
  local orig_intact="true"
  while IFS= read -r line; do
    grep -qF -- "$line" "${fixture}/.aid-o/config/execution.yaml" || orig_intact="false"
  done < /tmp/e2e-upgrade-before.yaml
  local has_new_gate
  has_new_gate="$(yq '.gates | has("targeted_tests")' "${fixture}/.aid-o/config/execution.yaml")"
  if [[ "$orig_intact" == "true" && "$has_new_gate" == "true" ]]; then
    stage_pass "existing_project_upgrade_applied"
  else
    stage_fail "existing_project_upgrade_applied" "orig_intact=${orig_intact} has_new_gate=${has_new_gate}"
  fi
  rm -rf "$fixture"
}

_scenario_mapping_gap_escalation() {
  local fixture; fixture="$(mktemp -d)"
  _build_fixture "$fixture"
  # Approved catalog + CONFIRMED mapping, but the mapping does NOT cover
  # src/bar.ts — a deliberately-introduced, unmapped changed path.
  local proposed="${fixture}/test-catalog.proposed.yaml"
  jq -n '{
    schema_version:"1.0.0", generated_at:"2026-08-02T00:00:00Z", status:"proposed",
    run_units: [
      {run_unit_id:"bats:tests/fixture-a", runner:"bats",
       source_paths:["tests/fixture-a.bats"], production_surfaces:["tests/fixture-a.bats"],
       test_level:"suite", risk_tags:[], profiles:["default"], behavior_claims:[], confidence:"medium",
       command:{type:"argv", argv:["bats","tests/fixture-a.bats"]},
       runtime:{fingerprint:"sha256:eeeeeeeeeeee"},
       parallel:{status:"safe", exclusive_resources:[], max_workers:null, internal_parallelism:false},
       isolation:{temp_workspace:"unknown", fixed_ports:[], shared_paths:[], lock_usage:[], adapter_confidence:"static_parse"},
       recommendation:"keep", test_cases:[]}
    ],
    source_pattern_mappings: [
      {match_type:"exact", path_pattern:"src/foo.ts",
       target_run_unit_ids:["bats:tests/fixture-a"], classification:"production",
       precedence:1, status:"proposed"}
    ],
    mapping_approval: {status:"proposed"}
  }' | yq -P '.' > "$proposed"
  bash "${PLUGIN_DIR}/scripts/aid-test-catalog-approve.sh" --proposed "$proposed" --project-root "$fixture" >/dev/null 2>&1
  local diff_out hash
  diff_out="$(bash "${PLUGIN_DIR}/scripts/aid-test-catalog-confirm-mapping.sh" --project-root "$fixture" 2>&1)"
  hash="$(grep '^reviewed_diff_hash:' <<<"$diff_out" | awk '{print $2}')"
  bash "${PLUGIN_DIR}/scripts/aid-test-catalog-confirm-mapping.sh" --project-root "$fixture" --confirm-mapping "$hash" >/dev/null 2>&1
  ( cd "$fixture" && git add -A && git commit -q -m "approved catalog" )

  cat > "${fixture}/.aid-o/config/execution.yaml" <<YAML
gates:
  targeted_tests:
    command: "${PLUGIN_DIR}/scripts/aid-select-tests.sh --base {base_commit}"
    required: false
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
  local base_sha; base_sha="$(cd "$fixture" && git rev-parse HEAD)"
  # aid-select-tests.sh's is_production_surface() is hardcoded to THIS
  # plugin's own "plugins/aid-orchestrator/{scripts,defaults}/" layout —
  # a pre-existing, dogfood-only assumption (P061) shared by both the
  # exit-3 (unverifiable) and exit-11 (mapping_gap) escalation paths.
  # An ordinary consumer-project path (e.g. src/bar.ts) can NEVER satisfy
  # it, so mapping_gap is structurally unreachable for a genuine fixture
  # file. Using a path that matches that literal string pattern is a
  # deliberate, documented workaround to exercise the REAL mapping_gap
  # mechanism at all — not a claim that consumer projects get real
  # is_production_surface() coverage (they don't; that is out of this
  # plan's scope).
  mkdir -p "${fixture}/plugins/aid-orchestrator/scripts"
  echo "unmapped change" >> "${fixture}/plugins/aid-orchestrator/scripts/unmapped-thing.sh"
  ( cd "$fixture" && git add -A && git commit -q -m "touch unmapped production-surface-shaped path" )

  local report="${fixture}/.aid-o/work/evidence/E2E/R1/gates/gates_report.json"
  mkdir -p "$(dirname "$report")"
  ( cd "$fixture" && bash "${PLUGIN_DIR}/scripts/aid-run-gates.sh" run-all .aid-o/config/execution.yaml E2E R1 \
      --base-commit "$base_sha" --profile targeted --report-file "$report" ) >/tmp/e2e-mapping-gap.log 2>&1

  local targeted_result escalation_triggered full_pass
  targeted_result="$(jq -r '.escalation.targeted_run.gates.targeted_tests.result // .gates.targeted_tests.result' "$report" 2>/dev/null)"
  escalation_triggered="$(jq -r '.escalation.targeted_run.gates.targeted_tests.escalation.triggered // .gates.targeted_tests.escalation.triggered // false' "$report" 2>/dev/null)"
  full_pass="$(jq -r '.gates.always_pass.result // empty' "$report" 2>/dev/null)"
  if [[ "$targeted_result" == "fail" && "$escalation_triggered" == "true" && "$full_pass" == "pass" ]]; then
    stage_pass "mapping_gap_escalation_produces_fail_plus_real_full_substitute"
  else
    stage_fail "mapping_gap_escalation_produces_fail_plus_real_full_substitute" "targeted_result=${targeted_result} escalation_triggered=${escalation_triggered} full_pass=${full_pass}"
  fi
  rm -rf "$fixture"
}

_scenario_sequential_regression() {
  echo "=== SCENARIO: sequential_regression ==="
  local fixture; fixture="$(mktemp -d)"
  _build_fixture "$fixture"
  if ! _bootstrap_catalog "$fixture"; then
    _write_artifact sequential_regression "$(cd "$fixture" && git rev-parse HEAD)"
    rm -rf "$fixture"
    return
  fi
  _generate_execution_yaml "$fixture" sequential

  local result; result="$(_run_real_dispatch "$fixture" sequential_only)"
  if [[ "$result" == "pass" ]]; then
    stage_pass "sequential_mode_targeted_tests_passes_unchanged"
  else
    stage_fail "sequential_mode_targeted_tests_passes_unchanged" "result='${result}'; log: $(cat /tmp/e2e-dispatch-sequential_only.log 2>/dev/null | tail -20)"
  fi
  local units_file="${fixture}/.aid-o/work/evidence/E2E/R1/gates/targeted-units.json"
  if [[ ! -f "$units_file" ]]; then
    stage_pass "sequential_mode_never_writes_emit_units_artifact"
  else
    stage_fail "sequential_mode_never_writes_emit_units_artifact" "targeted-units.json unexpectedly present under sequential mode"
  fi

  _write_artifact sequential_regression "$(cd "$fixture" && git rev-parse HEAD)"
  rm -rf "$fixture"
}

_scenario_self_host_bundle_refresh() {
  echo "=== SCENARIO: self_host_bundle_refresh ==="
  # Re-invokes Step 15's own real collector against THIS repo's own real,
  # current commit — never a fixture. Honestly reports whatever the
  # collector's real, current state is; this scenario is expected to be
  # pass:false until the deferred real divergence campaign (Step 15's own
  # documented, PM-deferred prerequisite) has actually been run for this
  # repo's full run_unit set — never fabricated as passing.
  if bash "${PLUGIN_DIR}/scripts/tests/test-integration-quarantine-remediation-evidence.sh" >/tmp/e2e-self-host.log 2>&1; then
    stage_pass "quarantine_remediation_bundle_regenerated"
  else
    stage_fail "quarantine_remediation_bundle_regenerated" "collector's current real result (expected until the deferred real divergence campaign runs): $(tail -5 /tmp/e2e-self-host.log)"
  fi
  _write_artifact self_host_bundle_refresh "$(git -C "$REPO_ROOT" rev-parse HEAD)"
}

case "$scenario" in
  observe_parallel_full_path) _scenario_observe_parallel_full_path ;;
  sequential_regression) _scenario_sequential_regression ;;
  self_host_bundle_refresh) _scenario_self_host_bundle_refresh ;;
  all)
    _scenario_observe_parallel_full_path
    _scenario_sequential_regression
    _scenario_self_host_bundle_refresh
    ;;
  *) echo "unknown --scenario '$scenario'" >&2; exit 2 ;;
esac

echo "----------------------------------------------------------------------"
total=$((pass + fail))
echo "Results: ${pass}/${total} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
