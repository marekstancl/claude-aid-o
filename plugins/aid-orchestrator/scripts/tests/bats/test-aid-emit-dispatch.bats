#!/usr/bin/env bats
# test-aid-emit-dispatch.bats — Component A of P040 coverage.
#
# Proves the pending-ledger semantics of aid-emit-dispatch.sh start/complete:
#   - both artifacts written (timeline audit trail + pending reconciliation ledger)
#   - start+complete pair clears the ledger
#   - orphan complete and fabricated output_file are rejected (exit 2)
#   - agent_id invariant enforced (exit 1, no partial state)
#   - expected_duration_max clamped at 1800s ceiling
#   - flock serialization + .lock sidecar survives inode rotation under concurrency
#
# TZ pinned to UTC so date arithmetic is host-independent (matches
# test-anti-fabrication.bats rationale).

setup() {
  export TZ=UTC
  SCRIPT="${BATS_TEST_DIRNAME}/../../aid-emit-dispatch.sh"
  TMPDIR_TEST="$(mktemp -d)"
  EVID="${TMPDIR_TEST}/evidence"
  mkdir -p "$EVID"
  PENDING="${EVID}/pending-dispatches.jsonl"
  TIMELINE="${EVID}/timeline.jsonl"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# 1. start-only emits both artifacts
@test "start-only emits timeline + pending entries" {
  run bash "$SCRIPT" start --focus cp2-step-1 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  [ "$status" -eq 0 ]

  [ -f "$TIMELINE" ]
  grep -q 'verifier_dispatch_start' "$TIMELINE"

  [ -f "$PENDING" ]
  run jq -e 'select(.event == "start" and .focus == "cp2-step-1")' "$PENDING"
  [ "$status" -eq 0 ]
}

# 2. start+complete pair clears pending
@test "start+complete pair clears pending ledger" {
  bash "$SCRIPT" start --focus cp2-step-1 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  touch "${TMPDIR_TEST}/out.md"

  run bash "$SCRIPT" complete --focus cp2-step-1 --output-file "${TMPDIR_TEST}/out.md" --evidence-dir "$EVID"
  [ "$status" -eq 0 ]

  # Pending file exists but is empty (0 lines after the single start removed)
  [ -f "$PENDING" ]
  run bash -c "grep -c . '$PENDING' || true"
  [ "$output" = "0" ]

  grep -q 'verifier_dispatch_start' "$TIMELINE"
  grep -q 'verifier_dispatch_complete' "$TIMELINE"
}

# 3. complete without matching start exits 2
@test "complete without matching start exits 2 (orphan)" {
  touch "${TMPDIR_TEST}/out.md"
  # Seed a pending file for an unrelated focus so we reach the orphan path,
  # not the missing-pending-file path.
  bash "$SCRIPT" start --focus cp2-step-9 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"

  run bash "$SCRIPT" complete --focus cp2-step-1 --output-file "${TMPDIR_TEST}/out.md" --evidence-dir "$EVID"
  [ "$status" -eq 2 ]
  [[ "$output" == *"orphan complete"* ]]
}

# 4. ceiling capped at 1800s
@test "expected-duration-max clamped at 1800s ceiling" {
  run bash "$SCRIPT" start --focus cp2-step-1 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID" --expected-duration-max 9999
  [ "$status" -eq 0 ]

  run jq -r '.expected_duration_max' "$PENDING"
  [ "$output" = "1800" ]
}

# 5. concurrent flock contention serializes (2 parallel starts → 2 clean lines)
@test "concurrent starts serialize without corruption" {
  bash "$SCRIPT" start --focus cp2-step-1 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID" &
  bash "$SCRIPT" start --focus cp2-step-2 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID" &
  wait

  # Exactly 2 lines, each valid JSON (no interleaved/corrupt write)
  run bash -c "grep -c . '$PENDING'"
  [ "$output" = "2" ]
  run bash -c "jq -e . '$PENDING' >/dev/null"
  [ "$status" -eq 0 ]
}

# 6. complete with missing output_file exits 2 (anti-fabrication), ledger intact
@test "complete with missing output_file exits 2 and keeps ledger" {
  bash "$SCRIPT" start --focus cp2-step-1 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"

  run bash "$SCRIPT" complete --focus cp2-step-1 --output-file "/tmp/does-not-exist-$$.md" --evidence-dir "$EVID"
  [ "$status" -eq 2 ]
  [[ "$output" == *"output_file does not exist"* ]]

  # Start entry NOT removed — fabrication must not clear the ledger
  run jq -e 'select(.event == "start" and .focus == "cp2-step-1")' "$PENDING"
  [ "$status" -eq 0 ]
  run bash -c "grep -c . '$PENDING'"
  [ "$output" = "1" ]
}

# 7. start with malformed agent_id exits 1 (invariant enforcement), no partial state
@test "malformed agent_id exits 1 and creates no pending file" {
  run bash "$SCRIPT" start --focus cp2-step-1 --agent-id FOO_bar --evidence-dir "$EVID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent_id does not match required format"* ]]

  # No pending file created (no partial state)
  [ ! -f "$PENDING" ]
}

# 8. concurrent start + complete survives inode swap (H11 race)
@test "concurrent start + complete survives inode rotation" {
  touch "${TMPDIR_TEST}/out.md"
  # Two starts then a complete. Completes=1, starts=2 → final line count == 1.
  # The complete's mktemp+mv rotates the $pending inode while another start may
  # be racing for the .lock sidecar; the sidecar inode is stable so no write is
  # lost.
  bash "$SCRIPT" start --focus cp2-step-1 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  bash "$SCRIPT" start --focus cp2-step-2 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID" &
  bash "$SCRIPT" complete --focus cp2-step-1 --output-file "${TMPDIR_TEST}/out.md" --evidence-dir "$EVID" &
  wait

  # starts(2) − completes(1) == 1 surviving pending line, file still valid JSON
  run bash -c "grep -c . '$PENDING'"
  [ "$output" = "1" ]
  run bash -c "jq -e . '$PENDING' >/dev/null"
  [ "$status" -eq 0 ]
}
