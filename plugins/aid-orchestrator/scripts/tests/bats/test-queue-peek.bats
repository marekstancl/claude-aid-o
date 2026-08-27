#!/usr/bin/env bats
# aid-tier: t0
# test-queue-peek.bats — P090 Step 1.
#
# The whole of P090 stands on ONE property: you can ask the queue what is next
# WITHOUT taking it. Before this step `queue_claim_next` selected and claimed in
# the same breath, so every question consumed an entry — and a turn that then
# ended left it `running` with nothing running. These cases assert the split
# holds: same answer, zero bytes changed.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  QW_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  QUEUE="$TEST_TMPDIR/queue.yaml"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _qw <subcommand> [args...] — the real CLI, never a sourced "test mode".
_qw() {
  run bash "$QW_LIB" "$@" --queue "$QUEUE" --project-root "$TEST_TMPDIR"
}

# A queue with no git anywhere in it: every entry is a legacy entry (no
# merge_target), so dependency readiness is decided by the status field alone
# and this suite stays t0 — no repository, no commits, milliseconds.
_write_queue() {
  cat > "$QUEUE"
}

_ready_queue() {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: pending
    plan_id: "P090"
    depends_on: []

  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: ["E-090-1_2"]
YAML
}

@test "AC1: peek prints what claim would take, and does not change one byte" {
  _ready_queue
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"

  _qw peek-next P090
  [ "$status" -eq 0 ]
  [ "$output" = "E-090-1_2" ]

  local after; after="$(sha256sum "$QUEUE" | cut -d' ' -f1)"
  [ "$before" = "$after" ]

  # …and the claim that follows takes exactly the entry the peek named.
  _qw claim-next P090
  [ "$status" -eq 0 ]
  [ "$output" = "E-090-1_2" ]
}

@test "AC1: a second peek answers the same — the lock is really released" {
  # Not a duplicate of the case above. `_queue_scan_next` was extracted out of
  # `queue_claim_next`, and the extraction had to keep `$(...)` rather than
  # `< <(...)`: a process substitution's subshell inherits a duplicate of the
  # lock fd and flock only drops on the LAST descriptor, so the lock would
  # outlive aid_lock_release. A single peek can never show that — it takes the
  # lock when nobody holds it. The SECOND peek is the probe.
  _ready_queue
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"

  _qw peek-next P090
  [ "$status" -eq 0 ]
  [ "$output" = "E-090-1_2" ]

  AID_QUEUE_WRITE_LOCK_TIMEOUT_S=3 _qw peek-next P090
  [ "$status" -eq 0 ]
  [ "$output" = "E-090-1_2" ]

  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]
}

@test "AC1: a blocked dependency is reported with its reason and STILL nothing is written" {
  # The difference from claim is visible here: claim records `status: blocked`
  # on the candidate; peek reports the same string and writes nothing.
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: pending
    plan_id: "P090"
    depends_on: []

  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: ["E-090-1_2"]
YAML
  # Claim the first one so it is `running` — i.e. not merged — which blocks
  # its dependent.
  _qw claim-next P090
  [ "$status" -eq 0 ]

  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"
  _qw peek-next P090
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-090-2_2:dependency_unmerged:E-090-1_2" ]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]
  # Proof that peek did NOT do claim's durable write.
  [ "$(bash "$QW_LIB" get E-090-2_2 status --queue "$QUEUE" --project-root "$TEST_TMPDIR")" = "pending" ]

  # …and claim, over the same state, answers identically (while writing).
  _qw claim-next P090
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-090-2_2:dependency_unmerged:E-090-1_2" ]
  [ "$(bash "$QW_LIB" get E-090-2_2 status --queue "$QUEUE" --project-root "$TEST_TMPDIR")" = "blocked" ]
}

@test "AC1: an exhausted plan answers none — the ordinary end of a plan, exit 1" {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: merged_to_plan
    plan_id: "P090"
    depends_on: []

  - epic_id: E-089-1_1
    status: pending
    plan_id: "P089"
    depends_on: []
YAML
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"
  _qw peek-next P090
  [ "$status" -eq 1 ]
  [ "$output" = "none" ]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]
}

@test "AC2: a lock it cannot take is an error (3), never the empty-queue answer" {
  # "I could not look" must never read as "there is nothing there": a
  # continuation loop reading `none` would declare the plan finished.
  _ready_queue
  local lock="${QUEUE}.lock"
  : > "$lock"

  # Hold the lock from another process for longer than the peek will wait.
  flock -x "$lock" -c 'sleep 5' &
  local holder=$!
  sleep 0.3

  AID_QUEUE_WRITE_LOCK_TIMEOUT_S=1 _qw peek-next P090
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  [ "$status" -eq 3 ]
  [ "$output" != "none" ]
  [[ "$output" != *"none"* ]]
}

@test "AC1: a malformed epic_id is skipped by peek exactly as by claim" {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: "../../etc/passwd"
    status: pending
    plan_id: "P090"
    depends_on: []

  - epic_id: E-090-1_2
    status: pending
    plan_id: "P090"
    depends_on: []
YAML
  _qw peek-next P090
  [ "$status" -eq 0 ]
  # `run` folds stderr into $output, and the skip is deliberately announced.
  [ "${lines[-1]}" = "E-090-1_2" ]
  [[ "$output" == *"skipping malformed epic_id"* ]]
}

@test "AC3: the status-enum comment names the function that actually writes running" {
  # The header used to credit `aid-plan-fsm.sh epic-start` with writing
  # `running`. It does not, and never did — the write is in queue_claim_next's
  # body, and the plan FSM deliberately does not touch the queue at all.
  local enum_line
  enum_line="$(grep -n '^#   running ' "$QW_LIB")"
  [[ "$enum_line" == *"queue_claim_next"* ]]
  [[ "$enum_line" != *"epic-start"* ]]

  # The write is where the comment now says it is.
  run bash -c 'sed -n "/^queue_claim_next()/,/^}/p" "$1" | grep -c "status=running"' _ "$QW_LIB"
  [ "$output" = "1" ]
}
