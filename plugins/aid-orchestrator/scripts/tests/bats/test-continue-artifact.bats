#!/usr/bin/env bats
# aid-tier: t1
# test-continue-artifact.bats — P090 Step 4.
#
# The continuation runs inside a turn. When the turn ends some other way — lost
# context, a timeout, a model's own decision — what was in flight has to be
# recoverable. That is all this file is: the guidance is written, it is read,
# and it is never obeyed blindly.
#
# TIER: t1, not the t0 the plan proposed — these cases need a real plan branch
# and real task branches, because "is this EPIC actually merged" is a question
# about Git.

load test-helpers.bash
load p090-fixture.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CONTINUE="$AID_PLUGIN_PATH/scripts/aid-plan-continue.sh"
  QW="$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"
  TEST_TMPDIR="$(mktemp -d)"; export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  GUIDE="$ROOT/.aid-o/work/evidence/P090/continue-state.json"
  p090_mk_workspace "$ROOT"
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_continue() { run bash "$CONTINUE" "$@" --project-root "$ROOT"; }

_epic_branch() { p090_plan_state "$ROOT" P090; p090_task_branch "$ROOT" "$1" "${2:-merged}"; }

_queue_two() {
  p090_queue "$QUEUE" P090 "E-090-1_2:running" "E-090-2_2:pending:E-090-1_2"
}


@test "AC10: a run leaves a guidance naming what it finished and what it left in flight" {
  _epic_branch E-090-1_2
  _queue_two
  # A run that fails at `start` STILL leaves a record — the run that failed is
  # exactly the one somebody comes back to — but `next_epic` stays empty,
  # because naming an EPIC that was never started as "in flight" would be a lie.
  _continue P090 E-090-1_2
  [ "$status" -eq 1 ]
  [ -f "$GUIDE" ]
  run jq -r '"\(.last_result) [\(.next_epic)] jobs=\(.spawned_count)"' "$GUIDE"
  [ "$output" = "start_failed_rc1 [] jobs=0" ]

  # A run that ENDS cleanly does write one.
  git -C "$ROOT" branch -f plan/P090 "task/E-090-1_2/main"
  bash "$QW" set-status E-090-2_2 merged_to_plan --queue "$QUEUE" --project-root "$ROOT"
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [ -f "$GUIDE" ]
  run jq -r '"\(.schema) \(.plan_id) \(.last_completed_epic) \(.last_result)"' "$GUIDE"
  [ "$output" = "aid-plan-continue/1 P090 E-090-1_2 none" ]
  # The four Step 6 fields are part of the schema even when nothing was
  # spawned: after an interruption they are the only way to find this plan's
  # own job, and a cap that did not survive a restart would be no cap.
  run jq -r '[.job_id, .jobs_dir, .job_fingerprint, (.spawned_count|tostring)] | join("|")' "$GUIDE"
  [ "$output" = "|||0" ]
  # Nothing half-written is left behind. The observable half of atomicity is
  # that no partial file survives a completed write; a grep for `mv --` in the
  # source used to stand in for the rest of it and asserted nothing a reader
  # could not see by looking.
  run bash -c 'ls "$1"/.aid-o/work/evidence/P090/ | grep -c "\.tmp\." || true' _ "$ROOT"
  [ "$output" = "0" ]
  # …and the file that IS there parses as one whole object, never a prefix.
  run jq -e '.schema == "aid-plan-continue/1"' "$GUIDE"
  [ "$status" -eq 0 ]
}

@test "AC10: a missing guidance is announced, and the run proceeds from the queue alone" {
  _epic_branch E-090-1_2
  _queue_two
  [ ! -f "$GUIDE" ]
  _continue P090 E-090-1_2
  [[ "$output" == *"guide:   none — this run starts from the queue alone"* ]]
  [[ "$output" == *"ask:     next is E-090-2_2"* ]]
}

@test "AC10: a corrupt or foreign guidance is never half-interpreted" {
  _epic_branch E-090-1_2
  _queue_two
  mkdir -p "$(dirname "$GUIDE")"

  printf '{ this is not json' > "$GUIDE"
  _continue P090 E-090-1_2
  [[ "$output" == *"unreadable, not aid-plan-continue/1, or not about P090"* ]]
  [[ "$output" == *"ask:     next is E-090-2_2"* ]]

  # Well-formed JSON of somebody ELSE's schema is equally not ours.
  printf '{"schema":"aid-auto-resume/1","next_epic":"E-090-9_9"}' > "$GUIDE"
  _continue P090 E-090-1_2
  [[ "$output" == *"unreadable, not aid-plan-continue/1, or not about P090"* ]]
  [[ "$output" != *"E-090-9_9"* ]]

  # …and so is OUR schema carrying ANOTHER plan's answer. A guide copied from
  # P091 names P091's unfinished EPIC, and obeying it would refuse P090's mirror
  # for a reason that has nothing to do with P090.
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P091", last_completed_epic:"E-091-1_2",
          last_result:"E-091-2_2", next_epic:"E-091-2_2", at:"2026-08-27T00:00:00Z",
          job_id:"", jobs_dir:"", job_fingerprint:"", spawned_count:0}' > "$GUIDE"
  _continue P090 E-090-1_2
  [[ "$output" == *"or not about P090"* ]]
  [[ "$output" != *"E-091-2_2"* ]]

  # A guide of our schema and our plan but MISSING a required field is not
  # half-read either.
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P090", next_epic:"E-090-9_9"}' > "$GUIDE"
  _continue P090 E-090-1_2
  [[ "$output" == *"or not about P090"* ]]
  [[ "$output" != *"E-090-9_9"* ]]
}

@test "AC11: the guidance is checked against Git, not obeyed — a stale one is simply superseded" {
  # It names an EPIC as in flight that has since been merged. That is the
  # ordinary shape after a lost turn, and it must not stop anything: the run
  # asks the queue again, which is the whole reason the guidance is a guidance.
  _epic_branch E-090-1_2
  _epic_branch E-090-2_2
  _queue_two
  mkdir -p "$(dirname "$GUIDE")"
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P090", last_completed_epic:"E-090-0_2",
          last_result:"E-090-2_2", next_epic:"E-090-2_2", at:"2026-08-27T00:00:00Z",
          job_id:"", jobs_dir:"", job_fingerprint:"", spawned_count:0}' > "$GUIDE"

  _continue P090 E-090-1_2
  [[ "$output" == *"left E-090-2_2 in flight"* ]]
  [[ "$output" == *"mirror:  E-090-1_2 running -> merged_to_plan"* ]]
}

@test "AC11: a guidance naming an UNFINISHED EPIC refuses an out-of-sequence mirror" {
  # The guidance says E-090-2_2 was started and Git agrees it is not merged, yet
  # this run claims E-090-1_2 finished. In a plan that runs one EPIC at a time
  # both cannot be true, and mirroring on that basis is how a dependent gets
  # unblocked on work that never landed.
  _epic_branch E-090-1_2
  _epic_branch E-090-2_2 unmerged
  _queue_two
  mkdir -p "$(dirname "$GUIDE")"
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P090", last_completed_epic:"E-090-0_2",
          last_result:"E-090-2_2", next_epic:"E-090-2_2", at:"2026-08-27T00:00:00Z",
          job_id:"", jobs_dir:"", job_fingerprint:"", spawned_count:0}' > "$GUIDE"
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"

  _continue P090 E-090-1_2
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot both be true"* ]]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]
}

@test "AC12: an entry left at running is reported by name, with the command that releases it" {
  _epic_branch E-090-1_2
  _queue_two
  bash "$QW" set-status E-090-2_2 running --queue "$QUEUE" --project-root "$ROOT"

  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"stuck:   E-090-2_2 is 'running'"* ]]
  [[ "$output" == *"--reclaim E-090-2_2"* ]]
  # Reported, NOT collected.
  [ "$(bash "$QW" get E-090-2_2 status --queue "$QUEUE" --project-root "$ROOT")" = "running" ]
}

@test "AC12: an orphan is named even when the run has a ready EPIC to get on with" {
  # Codex review, EPIC 1: with the report tied to the `none`/`blocked:` endings,
  # a plan holding one orphaned `running` entry AND one ready entry started the
  # ready one and never mentioned the orphan. The report belongs after the
  # mirror, on every path.
  _epic_branch E-090-1_2
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: running
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []

  - epic_id: E-090-2_2
    status: running
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []

  - epic_id: E-090-3_2
    status: pending
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []
YAML
  _continue P090 E-090-1_2
  # It got on with E-090-3_2 (start fails here — no manifest — which is not the
  # subject) AND it named the orphan.
  [[ "$output" == *"claim:   E-090-3_2"* ]]
  [[ "$output" == *"stuck:   E-090-2_2 is 'running'"* ]]
}

@test "AC12b: aid-auto-resume/1 keeps its own producer, consumer and schema — nothing was folded into it" {
  # The existing resume artifact is about an unfinished GATE: aid-run-gates.sh
  # writes it and aid-fsm.sh reads it. Extending it would have changed a schema
  # somebody else parses, which is why P090 has its own.
  grep -q 'aid-auto-resume/1' "$AID_PLUGIN_PATH/scripts/aid-run-gates.sh"
  # aid-fsm.sh is its consumer by POINTER, not by schema name: the run record
  # carries `resume_artifact`, which is the path to whatever aid-run-gates.sh
  # wrote.
  grep -q 'resume_artifact' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  # The new one is nowhere near either of them…
  run grep -l 'aid-plan-continue/1' "$AID_PLUGIN_PATH/scripts/aid-run-gates.sh" "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  [ "$status" -ne 0 ]
  # …and the continuation never writes the other one.
  run grep -c 'aid-auto-resume' "$CONTINUE"
  [ "$output" = "1" ]   # the header sentence explaining why, and nothing else
}
