#!/usr/bin/env bats
# test-aid-test-scheduler-report.bats — P069 Step 8.
#
# Proves aid-test-scheduler-report.sh's scheduler_report_merge_gate_row:
#   - two runs with reordered batch completion produce a byte-identical
#     synthesized gate row
#   - a required-gate failure in an early batch does not cause a later,
#     concurrently-dispatched batch's units to be dropped from the row —
#     both batches' data is preserved and reflected
#   - an unresolved unit in EITHER real non-terminal substate
#     (state:"in_flight" or state:"lost") is aggregated as result:"fail",
#     never silently excluded and never treated as pass
#   - a unit with NO receipt at all is aggregated as result:"fail", named
#     in `output`
#   - the row shape matches aid-run-gates.sh's real per-gate fields exactly

setup() {
  export TZ=UTC
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-test-scheduler-report.sh"
  # shellcheck source=/dev/null
  source "$LIB"
}

_receipt() {
  local uid="$1" state="$2"
  jq -nc --arg u "$uid" --arg s "$state" \
    '{unit_id:$u, job_id:($u+"-job"), state:$s, duration_ms:1000, concurrency_context:"sequential", co_scheduled_with:[], stdout_path:null, exit_code:(if $s=="terminal_pass" then 0 else 1 end)}'
}

_batch() {
  local batch_id="$1" started="$2" ended="$3"; shift 3
  local units_json; units_json="$(printf '%s\n' "$@" | jq -s '.')"
  jq -nc --arg bid "$batch_id" --arg sa "$started" --arg ea "$ended" --argjson u "$units_json" \
    '{batch_id:$bid, units:$u, started_at:$sa, ended_at:$ea}'
}

@test "a fully-passing single batch produces result:pass, exit_code:0" {
  local r1 r2 batch expected
  r1="$(_receipt "bats:a" "terminal_pass")"
  r2="$(_receipt "bats:b" "terminal_pass")"
  batch="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r1" "$r2")"
  expected='["bats:a","bats:b"]'
  run scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch]"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.gate=="targeted_tests" and .result=="pass" and .exit_code==0 and .attempts==1 and .duration_ms==5000'
}

@test "two runs with reordered batch completion produce a byte-identical synthesized row" {
  local r1 r2 batch1 batch2 expected
  r1="$(_receipt "bats:a" "terminal_pass")"
  r2="$(_receipt "bats:b" "terminal_pass")"
  # Batch order 1: a then b.
  batch1="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r1" "$r2")"
  # Batch order 2: b then a (identical content, reversed array order).
  batch2="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r2" "$r1")"
  expected='["bats:a","bats:b"]'
  local out1 out2
  out1="$(scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch1]")"
  out2="$(scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch2]")"
  [ "$out1" = "$out2" ]
}

#   Note (Codex review): this step's only deliverable is the pure
#   report-merge library — actual batch-N+1-blocked-while-batch-N-finishes
#   CONTROL FLOW is enforced by the gate-runner integration (Step 14), not
#   here. What this test proves at THIS library's own layer: merging never
#   drops a concurrently-dispatched batch's real data just because an
#   earlier batch failed.
@test "a failure in batch1 does not drop batch2's units from the merged row" {
  local r_fail r_b1_pass r_b2 batch1 batch2 expected
  r_fail="$(_receipt "bats:a" "terminal_fail")"
  batch1="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r_fail")"
  r_b2="$(_receipt "bats:b" "terminal_pass")"
  batch2="$(_batch "b2" "2026-08-02T00:00:01Z" "2026-08-02T00:00:07Z" "$r_b2")"
  expected='["bats:a","bats:b"]'
  run scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch1,$batch2]"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.result=="fail" and .exit_code==1'
  echo "$output" | jq -e '.output | contains("bats:a")'
  # Duration spans BOTH batches (earliest start to latest end).
  echo "$output" | jq -e '.duration_ms==7000'
}

@test "a retried unit (duplicate unit_id across batches) resolves to the MOST RECENT attempt regardless of batch array order (Codex regression)" {
  # attempt1 (batch1, ends earlier) failed; attempt2 (batch2, ends later)
  # re-ran the SAME unit_id and passed — the retry's outcome must win,
  # deterministically, regardless of which batch is listed first.
  local r_fail r_pass batch1 batch2 expected
  r_fail="$(_receipt "bats:a" "terminal_fail")"
  batch1="$(_batch "b1-attempt1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r_fail")"
  r_pass="$(_receipt "bats:a" "terminal_pass")"
  batch2="$(_batch "b1-attempt2" "2026-08-02T00:00:06Z" "2026-08-02T00:00:10Z" "$r_pass")"
  expected='["bats:a"]'

  local out_fwd out_rev
  out_fwd="$(scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch1,$batch2]")"
  out_rev="$(scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch2,$batch1]")"
  [ "$out_fwd" = "$out_rev" ]
  echo "$out_fwd" | jq -e '.result == "pass"'
}

@test "a unit resolved to a non-terminal state (in_flight) is aggregated as fail" {
  local r1 batch expected
  r1="$(_receipt "bats:a" "in_flight")"
  batch="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r1")"
  expected='["bats:a"]'
  run scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch]"
  echo "$output" | jq -e '.result=="fail"'
  echo "$output" | jq -e '.output | contains("bats:a")'
}

@test "a unit resolved to state:lost is aggregated as fail" {
  local r1 batch expected
  r1="$(_receipt "bats:a" "lost")"
  batch="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r1")"
  expected='["bats:a"]'
  run scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch]"
  echo "$output" | jq -e '.result=="fail"'
}

@test "an expected unit with NO receipt at all is aggregated as fail, named in output" {
  local r1 batch expected
  r1="$(_receipt "bats:a" "terminal_pass")"
  batch="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:05Z" "$r1")"
  expected='["bats:a","bats:missing"]'
  run scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch]"
  echo "$output" | jq -e '.result=="fail"'
  echo "$output" | jq -e '.output | contains("bats:missing")'
  echo "$output" | jq -e '.output | contains("no receipt")'
}

@test "the row shape matches aid-run-gates.sh's real per-gate fields exactly" {
  local r1 batch expected
  r1="$(_receipt "bats:a" "terminal_pass")"
  batch="$(_batch "b1" "2026-08-02T00:00:00Z" "2026-08-02T00:00:01Z" "$r1")"
  expected='["bats:a"]'
  run scheduler_report_merge_gate_row "targeted_tests" "$expected" "[$batch]"
  echo "$output" | jq -e '(keys | sort) == (["gate","result","exit_code","duration_ms","output","attempts"] | sort)'
}
