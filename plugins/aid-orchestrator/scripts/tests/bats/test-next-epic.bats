#!/usr/bin/env bats
# aid-tier: t0
# test-next-epic.bats — P090 Step 2.
#
# `next-epic` is the READ half of the queue split as an operator/controller
# command. Two things must hold and both are easy to lose: the exit codes must
# match `claim-next`'s existing table (otherwise a caller has to parse prose),
# and the command must never write the queue — the one-way edge this file's
# subject declares at aid-plan-fsm.sh:89-92.

load test-helpers.bash
load p090-fixture.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  # A committed repo, because `--project-root` is honoured as given only for a
  # root that has one (see _pfsm_resolve_project_root); and the plan-state file,
  # because `next-epic` refuses to answer for a plan this repository has never
  # started rather than reporting it exhausted.
  p090_mk_workspace "$ROOT"
  p090_plan_state "$ROOT" P090
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_next_epic() {
  run bash "$PLAN_FSM" next-epic "$@" --project-root "$ROOT"
}

_timeline() { echo "$ROOT/.aid-o/work/evidence/$1/timeline.jsonl"; }

_write_queue() { cat > "$QUEUE"; }

@test "AC4/AC5: a ready EPIC prints its id, exits 0, and leaves a timeline line" {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: pending
    plan_id: "P090"
    depends_on: []
YAML
  _next_epic P090
  [ "$status" -eq 0 ]
  [ "$output" = "E-090-1_2" ]

  run jq -r '"\(.event) \(.plan_id) \(.result)"' "$(_timeline P090)"
  [ "$status" -eq 0 ]
  [ "$output" = "queue_peek P090 E-090-1_2" ]
  # `ts`, like every other event in this file — the shared writer's field.
  # A hand-rolled copy of this writer stamped `at`, and anything reading the
  # timeline by time would have skipped P090's events.
  run jq -e '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$(_timeline P090)"
  [ "$status" -eq 0 ]
  run jq -e 'has("at") | not' "$(_timeline P090)"
  [ "$status" -eq 0 ]
}

@test "AC6: the command does not write the queue — not one byte" {
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
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"
  _next_epic P090
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]

  # Twice, because the second call is the one that would surface a lock the
  # first never released, and a blocked candidate is the case where `claim`
  # WOULD have written.
  _next_epic P090
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]
}

@test "AC4/AC5: a blocked dependency exits 1 with the reason, and is recorded" {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: running
    plan_id: "P090"
    depends_on: []

  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: ["E-090-1_2"]
YAML
  _next_epic P090
  [ "$status" -eq 1 ]
  [ "$output" = "blocked:E-090-2_2:dependency_unmerged:E-090-1_2" ]
  run jq -r '.result' "$(_timeline P090)"
  [ "$output" = "blocked:E-090-2_2:dependency_unmerged:E-090-1_2" ]
}

@test "AC4/AC5: an exhausted plan exits 1 with none — the ordinary end, not an error" {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: merged_to_plan
    plan_id: "P090"
    depends_on: []
YAML
  _next_epic P090
  [ "$status" -eq 1 ]
  [ "$output" = "none" ]
  run jq -r '.result' "$(_timeline P090)"
  [ "$output" = "none" ]
}

@test "AC4/AC5: a plan with no queue file at all answers none, and says so in the timeline" {
  rm -f "$QUEUE"
  _next_epic P090
  [ "$status" -eq 1 ]
  [ "$output" = "none" ]
  [ -f "$(_timeline P090)" ]
}

@test "AC4: a plan that was never started here is an error (2), never none" {
  # `none` is the word a continuation loop reads as "this plan is finished".
  # A typo in an otherwise well-formed plan id must never produce it.
  _next_epic P999
  [ "$status" -eq 2 ]
  [[ "$output" == *"no plan-state for P999"* ]]
  # Not one line is the bare word a caller parses. (The refusal explains itself
  # by quoting it, which is why this is a per-line check and not a substring
  # check over the whole output.)
  run bash -c 'grep -cx none <<<"$1" || true' _ "$output"
  [ "$output" = "0" ]
  [ ! -f "$(_timeline P999)" ]
}

@test "AC4: a malformed plan id is a usage error (2), never none" {
  _next_epic NOT-A-PLAN
  [ "$status" -eq 2 ]
  [[ "$output" == *"is not a plan id"* ]]
  [[ "$output" != *"none"* ]]
  [ ! -f "$(_timeline NOT-A-PLAN)" ]
}

@test "AC4: a missing plan id, and an unknown option, are both usage errors (2)" {
  run bash "$PLAN_FSM" next-epic --project-root "$ROOT"
  [ "$status" -eq 2 ]
  _next_epic P090 --nonsense
  [ "$status" -eq 2 ]
}

@test "AC4: an unavailable queue lock exits 3 — never 1, never none" {
  # The failure mode this whole plan exists to prevent: "I could not look"
  # read as "there is nothing left", which ends a plan that is not finished.
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: pending
    plan_id: "P090"
    depends_on: []
YAML
  : > "${QUEUE}.lock"
  flock -x "${QUEUE}.lock" -c 'sleep 5' &
  local holder=$!
  sleep 0.3
  AID_QUEUE_WRITE_LOCK_TIMEOUT_S=1 _next_epic P090
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  [ "$status" -eq 3 ]
  [[ "$output" != *"none"* ]]
  [ ! -f "$(_timeline P090)" ]
}

@test "AC5: a timeline that cannot be written is exit 3, not a silent answer" {
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: pending
    plan_id: "P090"
    depends_on: []
YAML
  # A plain FILE where the evidence directory has to be: mkdir -p fails, so
  # the answer cannot be recorded.
  mkdir -p "$ROOT/.aid-o/work/evidence"
  : > "$ROOT/.aid-o/work/evidence/P090"

  _next_epic P090
  [ "$status" -eq 3 ]
  [[ "$output" == *"could not open"* ]]
  [[ "$output" == *"rather than an unrecorded answer"* ]]
}
