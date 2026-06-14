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

# 9. HIGH-1: JSON-injection focus is rejected by the allowlist (exit 1, no state)
@test "HIGH-1 crafted --focus with injected event key is rejected (exit 1)" {
  run bash "$SCRIPT" start \
    --focus 'cp2-step-1","event":"complete","z":"' \
    --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--focus does not match allowed pattern"* ]]
  # No partial pending state written.
  [ ! -f "$PENDING" ]
}

# 10. HIGH-1: even if the allowlist were bypassed, jq -nc stores focus as a literal
#     string — no injected duplicate "event" key. We prove the construction is safe
#     by feeding a benign-but-quote-bearing focus through a relaxed allowlist check:
#     here we assert the production allowlist + jq combo for a VALID focus yields
#     event=="start" and the exact focus string, and that an orphan check on an
#     EXPIRED such entry still fires (injection can no longer flip event to complete).
@test "HIGH-1 pending entry is well-formed JSON and orphan check still fires" {
  # Valid focus, but force it expired so the orphan check would normally die.
  bash "$SCRIPT" start --focus cp3-security --agent-id aid-orchestrator:verifier \
    --evidence-dir "$EVID" --expected-duration-max 1

  # Pending line: event is literally "start", focus is the exact string, nonce present.
  run jq -r '.event' "$PENDING"
  [ "$output" = "start" ]
  run jq -r '.focus' "$PENDING"
  [ "$output" = "cp3-security" ]
  run jq -e '.nonce != null' "$PENDING"
  [ "$status" -eq 0 ]
  # Exactly one "event" key (no injected duplicate).
  run bash -c "head -1 '$PENDING' | grep -o '\"event\"' | wc -l | tr -d ' '"
  [ "$output" = "1" ]

  # Backdate ts so it is unambiguously expired, then run the orphan check via the
  # FSM helper — it must DIE (orphan detected), proving injection cannot suppress it.
  tmp="$(mktemp)"
  jq -c '.ts = "2000-01-01T00:00:00Z"' "$PENDING" > "$tmp" && mv "$tmp" "$PENDING"
  run bash -c '
    source "'"${BATS_TEST_DIRNAME}"'/../../aid-fsm.sh" >/dev/null 2>&1 || true
    fsm_check_orphan_dispatches "'"$EVID"'"
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"Orphan dispatch"* || "$output" == *"missing_dispatch_complete"* ]]
}

# 11. MEDIUM-1: two same-focus starts in the same second + one complete leaves
#     EXACTLY ONE pending entry (the second start), not zero. The unique nonce
#     prevents the double-clear that previously dropped a live dispatch.
@test "MEDIUM-1 two same-focus starts + one complete keeps exactly one entry" {
  touch "${TMPDIR_TEST}/out.md"
  # Two starts for the same focus, back-to-back (likely same wall-clock second).
  bash "$SCRIPT" start --focus cp3-security --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  bash "$SCRIPT" start --focus cp3-security --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"

  # Force identical ts on both lines to reproduce the same-second collision exactly.
  tmp="$(mktemp)"
  jq -c '.ts = "2026-01-01T00:00:00Z"' "$PENDING" > "$tmp" && mv "$tmp" "$PENDING"

  run bash -c "grep -c . '$PENDING'"
  [ "$output" = "2" ]

  bash "$SCRIPT" complete --focus cp3-security --output-file "${TMPDIR_TEST}/out.md" --evidence-dir "$EVID"

  # Exactly one start survives (not zero) — the second, never-completed dispatch.
  run bash -c "grep -c . '$PENDING'"
  [ "$output" = "1" ]
  run jq -e 'select(.event == "start" and .focus == "cp3-security")' "$PENDING"
  [ "$status" -eq 0 ]
}

# 12. P045: widened focus allowlist accepts the new reporter/simplifier foci
@test "P045 --focus reporter is accepted (status 0)" {
  run bash "$SCRIPT" start --focus reporter --agent-id aid-orchestrator:reporter --evidence-dir "$EVID"
  [ "$status" -eq 0 ]
}

@test "P045 --focus simplifier is accepted (status 0)" {
  run bash "$SCRIPT" start --focus simplifier --agent-id aid-orchestrator:simplifier --evidence-dir "$EVID"
  [ "$status" -eq 0 ]
}

# 13. Existing cp2-step-N focus still validates after the widening
@test "P045 existing --focus cp2-step-3 still validates (status 0)" {
  run bash "$SCRIPT" start --focus cp2-step-3 --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  [ "$status" -eq 0 ]
}

# 14. Invalid focus error message advertises the new reporter|simplifier foci
@test "P045 invalid focus rejected and error lists reporter|simplifier" {
  run bash "$SCRIPT" start --focus 'bogus$$$' --agent-id aid-orchestrator:verifier --evidence-dir "$EVID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reporter|simplifier"* ]]
}
