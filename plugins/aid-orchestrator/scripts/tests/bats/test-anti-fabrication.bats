#!/usr/bin/env bats
# test-anti-fabrication.bats — Phase 1 (P037) provenance verification smoke test.
#
# Validates the end-to-end anti-fabrication enforcement chain:
#   Step 1 (timeline dispatch events) → Step 3 (verify_provenance + provenance_aggregate)
#   → Step 3 (overall=fail when unverifiable) → Step 1 dispatcher (PM-added regression).
# Provenance verdict vocabulary: verified | inline | unverifiable | unknown
# (AID-046 renamed the old "fabricated" verdict to "unverifiable" — it is an integrity
# signal, not proof of fraud — and replaced the ±60s window with interval-bracket logic).
#
# Sourcing aid-fsm.sh requires a no-op dispatcher arg because the bottom of
# aid-fsm.sh is a top-level `case` that calls `exit 1` on unknown commands.
# We pre-set positional params to `verify-state <state_file>` so the dispatcher
# runs harmlessly (prints JSON to stdout, doesn't exit non-zero) and all
# function definitions persist into the test scope.

setup() {
  # Force UTC for date arithmetic. verify_provenance() mixes GNU `date -d` (which
  # honours `Z` suffix correctly) with jq's `fromdateiso8601` (which, in jq 1.6,
  # silently interprets the parsed epoch through the local TZ). On a CEST host
  # the two sides disagree by 3600s, causing every subagent dispatch to look
  # fabricated. Pinning TZ=UTC keeps both sides in lockstep for these fixtures.
  export TZ=UTC
  TMPDIR_TEST="$(mktemp -d)"
  EVIDENCE_DIR="${TMPDIR_TEST}/.aid-o/work/evidence/E-TEST-1/R-TEST-1"
  mkdir -p "$EVIDENCE_DIR"
  PROJECT_ROOT="$TMPDIR_TEST"
  STATE_FILE="${EVIDENCE_DIR}/fsm-state.yaml"
  cat > "$STATE_FILE" <<EOF
epic_id: E-TEST-1
run_id: R-TEST-1
branch: task/E-TEST/main
state: GATES
created_at: 2026-05-12T14:00:00Z
current_step: 1
total_steps: 5
EOF
  mkdir -p "${TMPDIR_TEST}/.aid-o/config"
  cat > "${TMPDIR_TEST}/.aid-o/config/plugin.yaml" <<EOF
plugin_path: "/tmp/aid"
dispatch_mode: subagent
EOF
  # Satisfy the non-provenance compliance checks so `overall` is driven purely
  # by `provenance_aggregate` in these tests:
  #   - execution_yaml_present requires .aid-o/config/execution.yaml
  #   - gates_generated_by requires evidence_dir/gates/gates_report.json with ._generated_by
  touch "${TMPDIR_TEST}/.aid-o/config/execution.yaml"
  mkdir -p "${EVIDENCE_DIR}/gates"
  printf '{"_generated_by":"aid-run-gates.sh@test-fixture"}\n' > "${EVIDENCE_DIR}/gates/gates_report.json"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# Helper: source aid-fsm.sh safely without triggering its bottom-of-file
# `exit 1` dispatcher. The dispatcher fires on unknown args; `verify-state`
# is a valid command that runs cleanly when given a populated fsm-state.yaml.
# Output (a single JSON line) goes to stdout but is discarded — only the
# function definitions matter for these tests.
_load_aid_fsm() {
  local fsm="${BATS_TEST_DIRNAME}/../../aid-fsm.sh"
  set -- "verify-state" "$STATE_FILE"
  # shellcheck disable=SC1090
  source "$fsm" >/dev/null
}

@test "verified subagent: _generated_at falls within the dispatch start..complete interval" {
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2026-05-12T14:05:00Z
classification: RUN
verdict: pass
EOF
  cat > "${EVIDENCE_DIR}/timeline.jsonl" <<EOF
{"ts":"2026-05-12T14:04:50Z","event":"verifier_dispatch_start","agentId":"aid-orchestrator:verifier","focus":"cp2-step-1","step_n":1,"evidence_dir":"$EVIDENCE_DIR"}
{"ts":"2026-05-12T14:05:30Z","event":"verifier_dispatch_complete","agentId":"aid-orchestrator:verifier","focus":"cp2-step-1","step_n":1,"evidence_dir":"$EVIDENCE_DIR","output_file":"verifier-output-step-1.md"}
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-cp3-code-review.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp3-code-review
_generated_at: 2026-05-12T14:10:00Z
verdict: pass
EOF
  echo '{"ts":"2026-05-12T14:09:50Z","event":"verifier_dispatch_start","agentId":"aid-orchestrator:verifier","focus":"cp3-code-review","step_n":null}' >> "${EVIDENCE_DIR}/timeline.jsonl"
  echo '{"ts":"2026-05-12T14:10:20Z","event":"verifier_dispatch_complete","agentId":"aid-orchestrator:verifier","focus":"cp3-code-review","step_n":null}' >> "${EVIDENCE_DIR}/timeline.jsonl"
  cat > "${EVIDENCE_DIR}/verifier-output-cp3-security.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp3-security
_generated_at: 2026-05-12T14:11:00Z
verdict: pass
EOF
  echo '{"ts":"2026-05-12T14:10:50Z","event":"verifier_dispatch_start","agentId":"aid-orchestrator:verifier","focus":"cp3-security","step_n":null}' >> "${EVIDENCE_DIR}/timeline.jsonl"
  echo '{"ts":"2026-05-12T14:11:20Z","event":"verifier_dispatch_complete","agentId":"aid-orchestrator:verifier","focus":"cp3-security","step_n":null}' >> "${EVIDENCE_DIR}/timeline.jsonl"

  _load_aid_fsm
  cd "$TMPDIR_TEST"  # ensure project_root context for yq lookup of plugin.yaml
  run write_compliance_json "E-TEST-1" "R-TEST-1" "$STATE_FILE" "$EVIDENCE_DIR" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local prov_agg
  prov_agg=$(jq -r '.checks.verifier_outputs.provenance_aggregate' "${EVIDENCE_DIR}/compliance.json")
  [ "$prov_agg" = "all_verified" ]
  local overall
  overall=$(jq -r '.overall' "${EVIDENCE_DIR}/compliance.json")
  [ "$overall" = "pass" ]
}

@test "unverifiable detection: verifier outputs without matching timeline events" {
  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2026-05-12T14:05:00Z
classification: RUN
verdict: pass
EOF
  touch "${EVIDENCE_DIR}/timeline.jsonl"
  cat > "${EVIDENCE_DIR}/verifier-output-cp3-code-review.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp3-code-review
_generated_at: 2026-05-12T14:10:00Z
verdict: pass
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-cp3-security.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp3-security
_generated_at: 2026-05-12T14:11:00Z
verdict: pass
EOF

  _load_aid_fsm
  cd "$TMPDIR_TEST"
  run write_compliance_json "E-TEST-1" "R-TEST-1" "$STATE_FILE" "$EVIDENCE_DIR" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local prov_agg overall
  prov_agg=$(jq -r '.checks.verifier_outputs.provenance_aggregate' "${EVIDENCE_DIR}/compliance.json")
  [ "$prov_agg" = "unverifiable" ]
  overall=$(jq -r '.overall' "${EVIDENCE_DIR}/compliance.json")
  [ "$overall" = "fail" ]
}

@test "AID-046 regression: honest long-running subagent (20 min) verifies via interval bracket" {
  # start at T, complete at T+20min, output generated mid-run at T+10min. The previous
  # ±60s-around-_generated_at logic flagged this as fabricated because the start event
  # sits 10 minutes before _generated_at (outside ±60s). Interval-bracket accepts it:
  # start <= _generated_at <= complete (+ tolerance). This case bit P040's own ship.
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2026-05-12T14:10:00Z
classification: RUN
verdict: pass
EOF
  cat > "${EVIDENCE_DIR}/timeline.jsonl" <<EOF
{"ts":"2026-05-12T14:00:00Z","event":"verifier_dispatch_start","focus":"cp2-step-1","step_n":1}
{"ts":"2026-05-12T14:20:00Z","event":"verifier_dispatch_complete","focus":"cp2-step-1","step_n":1}
EOF

  _load_aid_fsm
  run verify_provenance "${EVIDENCE_DIR}/verifier-output-step-1.md" "cp2-step-1" 1 "subagent" "${EVIDENCE_DIR}/timeline.jsonl" 60
  [ "$status" -eq 0 ]
  [ "$output" = "verified" ]
}

@test "AID-046: _generated_at far outside the dispatch interval is unverifiable" {
  # Output timestamp well before the dispatch even started (beyond tolerance) → cannot
  # have been produced by that dispatch → unverifiable (catches stale/copied outputs).
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: aid-orchestrator:verifier@cp2-step-1
_generated_at: 2026-05-12T09:00:00Z
classification: RUN
verdict: pass
EOF
  cat > "${EVIDENCE_DIR}/timeline.jsonl" <<EOF
{"ts":"2026-05-12T14:00:00Z","event":"verifier_dispatch_start","focus":"cp2-step-1","step_n":1}
{"ts":"2026-05-12T14:20:00Z","event":"verifier_dispatch_complete","focus":"cp2-step-1","step_n":1}
EOF

  _load_aid_fsm
  run verify_provenance "${EVIDENCE_DIR}/verifier-output-step-1.md" "cp2-step-1" 1 "subagent" "${EVIDENCE_DIR}/timeline.jsonl" 60
  [ "$status" -eq 0 ]
  [ "$output" = "unverifiable" ]
}

@test "inline mode: main-context@<sha> with valid SHA passes" {
  sed -i 's/dispatch_mode: subagent/dispatch_mode: inline/' "${TMPDIR_TEST}/.aid-o/config/plugin.yaml"

  command -v git >/dev/null || skip "git not available"
  git -C "$TMPDIR_TEST" init -q
  git -C "$TMPDIR_TEST" config user.email test@test
  git -C "$TMPDIR_TEST" config user.name test
  echo "x" > "${TMPDIR_TEST}/seed.txt"
  git -C "$TMPDIR_TEST" add seed.txt
  git -C "$TMPDIR_TEST" commit -q -m "init"
  local sha
  sha=$(git -C "$TMPDIR_TEST" rev-parse --short=7 HEAD)

  cat > "${EVIDENCE_DIR}/step-1-verify.md" <<EOF
classification: RUN
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-step-1.md" <<EOF
_generated_by: main-context@${sha}
_generated_at: 2026-05-12T14:05:00Z
classification: RUN
verdict: pass
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-cp3-code-review.md" <<EOF
_generated_by: main-context@${sha}
_generated_at: 2026-05-12T14:10:00Z
verdict: pass
EOF
  cat > "${EVIDENCE_DIR}/verifier-output-cp3-security.md" <<EOF
_generated_by: main-context@${sha}
_generated_at: 2026-05-12T14:11:00Z
verdict: pass
EOF

  _load_aid_fsm
  cd "$TMPDIR_TEST"
  run write_compliance_json "E-TEST-1" "R-TEST-1" "$STATE_FILE" "$EVIDENCE_DIR" "$PROJECT_ROOT"
  [ "$status" -eq 0 ]

  local prov_agg overall
  prov_agg=$(jq -r '.checks.verifier_outputs.provenance_aggregate' "${EVIDENCE_DIR}/compliance.json")
  [ "$prov_agg" = "all_inline" ]
  overall=$(jq -r '.overall' "${EVIDENCE_DIR}/compliance.json")
  [ "$overall" = "pass" ]
}

@test "aid-stage-log.sh CLI dispatcher: bash invocation writes valid JSONL event" {
  command -v jq >/dev/null || skip "jq not available"
  local plugin_dir
  plugin_dir="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  local timeline="${TMPDIR_TEST}/dispatcher-test.jsonl"

  # Test 1: dispatcher mode writes valid JSON
  bash "${plugin_dir}/lib/aid-stage-log.sh" log_event "$timeline" "test_event" foo=bar baz=42 nested=true
  [ -s "$timeline" ]  # file is non-empty
  local event_name
  event_name=$(jq -r '.event' "$timeline")
  [ "$event_name" = "test_event" ]
  local foo_val
  foo_val=$(jq -r '.foo' "$timeline")
  [ "$foo_val" = "bar" ]

  # Test 2: unknown function exits non-zero with help message
  run bash "${plugin_dir}/lib/aid-stage-log.sh" emit_event 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown function"* ]]
  [[ "$output" == *"Available:"* ]]
}
