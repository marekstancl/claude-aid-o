#!/usr/bin/env bats
# test-auto-resume-artifact.bats — P076 Step 4: the eager continuation pointer,
# the live active-runs writer, and the freshness binding on checkpointed rows.
#
# THE GROUNDED FAILURE MODE (F6): a controller that dies mid-EXECUTE is
# invisible today — nothing it left behind says "a background job is out there
# and somebody has to come back for it". So the pointer is written EAGERLY,
# BEFORE the job is spawned, and is deleted only when the run's last background
# job has been collected. Nothing here depends on a watchdog loop that may
# never run, and `awaiting_host_resume` is never STORED by anyone: it is
# derived from (artifact exists) AND (no liveness signal).
#
# Everything drives the REAL aid-run-gates.sh, the REAL aid-job.sh supervisor
# and the REAL aid-fsm.sh writer against a real git fixture. The schema check
# is the real shipped schema, validated by jsonschema.
#
# Cases:
#   1. artifact appears at background start and validates against the schema
#   2. clean collect deletes it and puts auto_controller back to `active`
#   3. SIGKILL mid-run leaves the artifact AND the map fields pointing at it
#   4. a corrupt map is never clobbered (fail-closed regression)
#   5. two sequential background gates share ONE artifact path
#   6. an unwritable evidence dir refuses BEFORE the job is spawned
#   7. init refuses while the referenced job is live, and names `resume`
#   8. init archives (never deletes) a stale artifact
#   9. the restore pass restores a bound row, re-derives overall, and keeps
#      defined==processed
#  10. a row bound to a MOVED head is refused, not restored as a pass
#  11. a row with no revision binding at all is refused the same way
#  12. update_active_run_field rejects the derived state and unknown fields

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  JOB_SH="$PLUGIN_ROOT/scripts/aid-job.sh"
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  SCHEMA="$PLUGIN_ROOT/defaults/schemas/auto-resume-required.schema.json"
  export RUN_GATES JOB_SH FSM SCHEMA

  WORK="$(mktemp -d)"; export WORK
  PROJ="$WORK/project"; export PROJ
  mkdir -p "$PROJ"

  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1

  EVID=".aid-o/work/evidence/E-076-9_9/R-1"; export EVID
  ARTIFACT="$PROJ/$EVID/auto_resume_required.json"; export ARTIFACT
  REPORT="$PROJ/$EVID/gates/gates_report.json"; export REPORT
  TIMELINE="$PROJ/$EVID/timeline.jsonl"; export TIMELINE
  JOBS="$PROJ/$EVID/jobs"; export JOBS
  ROWS="$PROJ/$EVID/gates_rows"; export ROWS
  MAP="$PROJ/.aid-o/work/active-runs.json"; export MAP
}

teardown() {
  # Reap anything the supervisor still owns — a leaked `sleep` outliving the
  # suite is exactly what this mechanism exists to prevent.
  if [[ -d "${JOBS:-/nonexistent}" ]]; then
    local d pgid
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      pgid="$(jq -r '.pgid // empty' "$d/job.json" 2>/dev/null || true)"
      [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
    done
  fi
  kill_runner
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# `$!` is the backgrounded SUBSHELL; aid-run-gates.sh may be that process or a
# child of it depending on whether bash exec-optimises the subshell, so killing
# only the pid bash reports leaves the real runner polling — reparented to PID 1,
# still holding bats' inherited fds until its gate deadline expires. (Observed:
# runners alive long after this suite reported complete.) The runner is therefore
# identified by what it provably IS: an aid-run-gates.sh run-all process whose
# CWD is THIS test's project. Topology-independent, and safe under parallel bats
# runs because every test has its own project dir.
_runner_pids() {
  local p want
  want="$(readlink -f "${PROJ:-/nonexistent}" 2>/dev/null || echo "${PROJ:-/nonexistent}")"
  for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
    [[ "$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)" == "$want" ]] && echo "$p"
  done
  return 0
}

kill_runner() {
  local p
  for p in $(_runner_pids); do kill -KILL "$p" 2>/dev/null || true; done
  [[ -n "${BG_RUNNER_PID:-}" ]] && kill -KILL "$BG_RUNNER_PID" 2>/dev/null || true
  [[ -n "${BG_RUNNER_PID:-}" ]] && wait "$BG_RUNNER_PID" 2>/dev/null || true
  BG_RUNNER_PID=""
  return 0
}

init_project() {
  mkdir -p "$PROJ/$EVID/gates" "$PROJ/.aid-o/work/runs" "$PROJ/.aid-o/config" \
           "$PROJ/.aid-o/plans" "$PROJ/.aid-o/tasks"
  printf 'counter: 0\n' > "$PROJ/.aid-o/config/counter.yaml"
  printf 'resume fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  (
    cd "$PROJ"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email resume@example.com
    git config user.name Resume
    git add README.md .gitignore
    git commit -qm "resume fixture base"
  )
}

# _seed_map <auto_controller> — an active-runs entry in upsert_active_run's
# exact shape, so the live writer is exercised against a real map.
_seed_map() {
  jq -n --arg ac "${1:-manual}" \
    '{"E-076-9_9": {state_file: ".aid-o/work/evidence/E-076-9_9/R-1/fsm-state.yaml",
      run_id: "R-1", state: "GATES", branch: "task/E-076-9_9/main",
      plan_id: "P076", governs_main: false,
      updated_at: "2026-01-01T00:00:00Z",
      auto_controller: $ac, resume_artifact: null}}' > "$MAP"
}

run_gates() {
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-076-9_9 R-1 \
      --report-file "$EVID/gates/gates_report.json" \
      >"$WORK/stdout.txt" 2>"$WORK/stderr.txt" )
}

# wait_for_artifact_job <job_id> — block until the POST-SPAWN rewrite has
# landed. Before it does, the pointer legitimately reads `pending` (that is the
# pre-spawn write doing its job), so a timing-blind assertion on the id would
# be testing the scheduler, not the mechanism.
wait_for_artifact_job() {
  local want="$1" i
  for i in $(seq 1 200); do
    [[ "$(jq -r '.job_id // ""' "$ARTIFACT" 2>/dev/null || true)" == "$want" ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_for_job_pid() {
  local d="$1" i
  for i in $(seq 1 150); do
    [[ -f "$d/job.json" ]] && jq -e '.pid != null' "$d/job.json" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

# _validate <instance> — the real shipped schema, a real validator.
_validate() {
  python3 - "$SCHEMA" "$1" <<'PY'
import json,sys
from jsonschema.validators import Draft202012Validator
schema=json.load(open(sys.argv[1])); inst=json.load(open(sys.argv[2]))
errs=list(Draft202012Validator(schema).iter_errors(inst))
for e in errs: print("/".join(str(x) for x in e.path) or "(root)", e.message)
sys.exit(1 if errs else 0)
PY
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: the artifact exists WHILE the background job runs and validates against the schema" {
  init_project
  _seed_map manual
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "sleep 6; echo bg-done"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-076-9_9 R-1 \
      --report-file "$EVID/gates/gates_report.json" ) >"$WORK/r1.out" 2>"$WORK/r1.err" &
  BG_RUNNER_PID=$!
  wait_for_job_pid "$JOBS/bg-attempt-1"

  # Written BEFORE the spawn (job_id "pending"), rewritten with the real id
  # immediately after it — both writes land on the SAME single path.
  [ -f "$ARTIFACT" ]
  wait_for_artifact_job "bg-attempt-1"
  run _validate "$ARTIFACT"
  echo "schema errors: $output"
  [ "$status" -eq 0 ]

  run jq -r '[.schema,.plan_id,.epic_id,.run_id,.job_id,.gate] | join("|")' "$ARTIFACT"
  [ "$output" = "aid-auto-resume/1|P076|E-076-9_9|R-1|bg-attempt-1|bg" ]

  # The fingerprint is the supervisor's OWN, not a private re-computation.
  local fp; fp="$(bash "$JOB_SH" fingerprint -- bash -c "sleep 6; echo bg-done")"
  run jq -r '.command_fingerprint' "$ARTIFACT"
  [ "$output" = "$fp" ]

  # aid-job.sh's terminal vocabulary, verbatim.
  run jq -c '.expected_terminal_states' "$ARTIFACT"
  [ "$output" = '["terminal_pass","terminal_fail","timed_out","cancelled"]' ]

  # Fully resolved — no placeholder can survive (the schema forbids '<').
  run jq -r '.safe_next_action' "$ARTIFACT"
  [[ "$output" != *"<"* ]]
  [[ "$output" == *"aid-run-gates.sh run-all"* ]]
  [[ "$output" == *"E-076-9_9 R-1"* ]]

  wait "$BG_RUNNER_PID" || true
}

@test "case 2: a clean collect deletes the artifact and puts auto_controller back to active" {
  init_project
  _seed_map manual
  export AID_AUTO_MODE=1
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "echo bg-done"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"
  [ "$status" -eq 0 ]

  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  # The pointer is gone — nothing is outstanding, so nothing has to be resumed.
  [ ! -f "$ARTIFACT" ]
  run jq -r '."E-076-9_9".auto_controller' "$MAP"
  [ "$output" = "active" ]
  run jq -r '."E-076-9_9".resume_artifact' "$MAP"
  [ "$output" = "null" ]
  # The map is still a valid entry, not a wholesale replacement.
  run jq -r '."E-076-9_9" | [.run_id,.plan_id,.state] | join("|")' "$MAP"
  [ "$output" = "R-1|P076|GATES" ]
}

@test "case 3: SIGKILL mid-run leaves the artifact AND the map pointing at it" {
  init_project
  _seed_map manual
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "sleep 30; echo bg-done"
    required: true
    timeout_seconds: 120
    run_mode: background
YAML

  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-076-9_9 R-1 \
      --report-file "$EVID/gates/gates_report.json" ) >"$WORK/r1.out" 2>"$WORK/r1.err" &
  BG_RUNNER_PID=$!
  wait_for_job_pid "$JOBS/bg-attempt-1"
  wait_for_artifact_job "bg-attempt-1"

  # The harshest possible death: no trap, no cleanup, nothing written on the
  # way out. Everything a resume can learn, it learns from what was already
  # on disk BEFORE the death.
  kill_runner

  [ -f "$ARTIFACT" ]
  run _validate "$ARTIFACT"
  echo "schema errors: $output"
  [ "$status" -eq 0 ]

  # The pointer names a job that is genuinely still live.
  local jid; jid="$(jq -r '.job_id' "$ARTIFACT")"
  [ "$jid" = "bg-attempt-1" ]
  run bash "$JOB_SH" status --jobs-dir "$JOBS" --id "$jid"
  [ "$output" = "running" ]

  # The map carries the POINTER, and nothing has stored a derived state.
  run jq -r '."E-076-9_9".resume_artifact' "$MAP"
  [ "$output" = "$EVID/auto_resume_required.json" ]
  run jq -r '."E-076-9_9".auto_controller' "$MAP"
  [ "$output" = "manual" ]
  run grep -c awaiting_host_resume "$MAP"
  [ "$output" = "0" ]

  # And the jobs_dir + fingerprint are enough to find the job WITHOUT the id.
  local fp; fp="$(jq -r '.command_fingerprint' "$ARTIFACT")"
  run jq -r '.command_fingerprint' "$JOBS/bg-attempt-1/job.json"
  [ "$output" = "$fp" ]
}

@test "case 4: a corrupt active-runs map is refused, never clobbered" {
  init_project
  printf '{ this is not json' > "$MAP"
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "echo bg-done"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  run run_gates
  [ "$status" -eq 0 ]

  # The map is byte-for-byte untouched — a corrupt file is never repaired,
  # normalized, or overwritten by a best-effort writer.
  run cat "$MAP"
  [ "$output" = "{ this is not json" ]

  # The gate itself still ran and the ARTIFACT (authoritative) was handled.
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  [ ! -f "$ARTIFACT" ]

  # Direct writer call: fail-closed, rc 1, and it says which file.
  run bash -c "cd '$PROJ' && '$FSM' active-runs set E-076-9_9 auto_controller active"
  [ "$status" -ne 0 ]
  [[ "$output" == *"active-runs.json"* ]]
  run cat "$MAP"
  [ "$output" = "{ this is not json" ]
}

@test "case 5: two sequential background gates share ONE artifact path" {
  init_project
  _seed_map manual
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg_one:
    command: "echo one"
    required: true
    timeout_seconds: 60
    run_mode: background
  bg_two:
    command: "sleep 6; echo two"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-076-9_9 R-1 \
      --report-file "$EVID/gates/gates_report.json" ) >"$WORK/r1.out" 2>"$WORK/r1.err" &
  BG_RUNNER_PID=$!

  # While the SECOND background gate is in flight: the first one is long since
  # collected, and the one and only artifact path now names the second job.
  wait_for_artifact_job "bg_two-attempt-1"
  [ -f "$JOBS/bg_one-attempt-1/result.json" ]
  run bash -c "ls -1 '$PROJ/$EVID' | grep -c '^auto_resume_required\.json$'"
  [ "$output" = "1" ]
  run jq -r '[.gate,.job_id] | join("|")' "$ARTIFACT"
  [ "$output" = "bg_two|bg_two-attempt-1" ]
  run _validate "$ARTIFACT"
  echo "schema errors: $output"
  [ "$status" -eq 0 ]

  wait "$BG_RUNNER_PID"
  echo "stderr: $(cat "$WORK/r1.err")"

  # Exactly one artifact path ever existed — the second start REWROTE it, and
  # the final collect removed it.
  run bash -c "ls -1 '$PROJ/$EVID' | grep -c auto_resume_required"
  [ "$output" = "0" ]
  run jq -r '.gates.bg_one.result + "/" + .gates.bg_two.result' "$REPORT"
  [ "$output" = "pass/pass" ]
  # Both jobs really ran under the supervisor.
  [ -f "$JOBS/bg_one-attempt-1/result.json" ]
  [ -f "$JOBS/bg_two-attempt-1/result.json" ]

  # And a second run of the same shape sees no leftovers.
  run bash -c "ls -1 '$PROJ/$EVID'/*.superseded-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "case 6: an unwritable evidence dir refuses the gate BEFORE spawning the job" {
  init_project
  _seed_map manual
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "sleep 30"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  # Make the evidence directory itself unwritable, while leaving the two files
  # the runner needs for its own bookkeeping reachable: the timeline already
  # exists (append-only), the report lives in the writable gates/ subdir, and
  # the execution ledger is pointed elsewhere. What CANNOT be created is the
  # continuation pointer — the exact condition under test.
  : > "$PROJ/$EVID/timeline.jsonl"
  export AID_EXECUTION_LEDGER="$WORK/ledger.json"
  chmod a-w "$PROJ/$EVID"
  run run_gates
  chmod u+w "$PROJ/$EVID"

  [ "$status" -ne 0 ]
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "fail" ]
  run jq -r '.gates.bg.reason' "$REPORT"
  [ "$output" = "resume_artifact_write_failed" ]
  # NOTHING was spawned: no job dir, and no stray sleep.
  [ ! -d "$JOBS/bg-attempt-1" ]
  run grep -c "refusing to spawn a background job nothing can resume" "$WORK/stderr.txt"
  [ "$output" -ge 1 ]
}

@test "case 7: init REFUSES while the referenced job is live and names resume" {
  init_project
  mkdir -p "$JOBS"
  bash "$JOB_SH" run --jobs-dir "$JOBS" --id live-job --label live -- sleep 60 >/dev/null
  jq -n --arg jd "$JOBS" \
    '{schema:"aid-auto-resume/1", plan_id:"P076", epic_id:"E-076-9_9",
      run_id:"R-1", job_id:"live-job", jobs_dir:$jd, gate:"bg",
      command_fingerprint:"0000000000000000000000000000000000000000000000000000000000000000",
      expected_terminal_states:["terminal_pass","terminal_fail","timed_out","cancelled"],
      safe_next_action:"bash /x/aid-run-gates.sh run-all exec.yaml E-076-9_9 R-1",
      created_at:"2026-01-01T00:00:00Z"}' > "$ARTIFACT"

  run bash -c "cd '$PROJ' && '$FSM' init E-076-9_9 R-2 1 manual main HEAD '$EVID/fsm-state.yaml'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"LIVE background job"* ]]
  [[ "$output" == *"resume"* ]]
  # The artifact was NOT archived — the run it points at is still real.
  [ -f "$ARTIFACT" ]

  bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id live-job >/dev/null 2>&1 || true
}

@test "case 8: init ARCHIVES a stale artifact instead of deleting it" {
  init_project
  mkdir -p "$JOBS"
  jq -n '{schema:"aid-auto-resume/1", plan_id:"P076", epic_id:"E-076-9_9",
      run_id:"R-1", job_id:"pending", jobs_dir:".aid-o/work/evidence/E-076-9_9/R-1/jobs",
      gate:"bg",
      command_fingerprint:"0000000000000000000000000000000000000000000000000000000000000000",
      expected_terminal_states:["terminal_pass"],
      safe_next_action:"bash /x/aid-run-gates.sh run-all exec.yaml E-076-9_9 R-1",
      created_at:"2026-01-01T00:00:00Z"}' > "$ARTIFACT"

  run bash -c "cd '$PROJ' && '$FSM' init E-076-9_9 R-2 1 manual main HEAD '.aid-o/work/evidence/E-076-9_9/R-2/fsm-state.yaml'" 3>&-
  echo "$output"
  [ "$status" -eq 0 ]
  [ ! -f "$ARTIFACT" ]
  run bash -c "ls -1 '$PROJ/$EVID'/auto_resume_required.json.superseded-* | wc -l"
  [ "$output" = "1" ]
  # Archived, not emptied: the record of what the dead controller waited for.
  run bash -c "jq -r '.job_id' '$PROJ/$EVID'/auto_resume_required.json.superseded-*"
  [ "$output" = "pending" ]
}

# ── AC5: the restore pass, exercised for the first time ─────────────────────

@test "case 9: a revision-bound checkpoint row is RESTORED, re-derives overall, and keeps defined==processed" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  alpha:
    command: "echo alpha-ok"
    required: true
    timeout_seconds: 30
  ghost:
    command: "echo ghost-failed-earlier >&2; exit 1"
    required: true
    timeout_seconds: 30
YAML

  # The row under test is written by THE RUNNER ITSELF, in an earlier
  # invocation — not by hand. That is the whole point of the binding: a row is
  # restorable only when this run's own writers produced it, so a fixture that
  # hand-wrote one would be testing the forgery the binding exists to refuse
  # (and, before CP3, would have passed for exactly that reason).
  run run_gates
  [ -f "$ROWS/ghost.json" ]
  run jq -r '.result' "$ROWS/ghost.json"
  [ "$output" = "fail" ]
  run jq -e '._checkpoint.head != null and ._checkpoint.tree != null and ._checkpoint.key != null' "$ROWS/ghost.json"
  [ "$status" -eq 0 ]

  # `ghost` stays DEFINED (only defined gates are restorable) but is not
  # ITERATED — the shape a runner killed mid-loop leaves behind, and the only
  # way to reach the restore branch, since every ordinary path emits a row.
  AID_TEST_DROP_GATE_RESTORE=ghost run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"

  run jq -r '.gates.ghost.result' "$REPORT"
  [ "$output" = "fail" ]
  run jq -r '.gates.ghost.output' "$REPORT"
  [[ "$output" == *"ghost-failed-earlier"* ]]
  # A restored FAILING required row still drives overall.
  run jq -r '.overall' "$REPORT"
  [ "$output" = "fail" ]
  # …and it counted, so the integrity assert stays satisfied.
  run jq -e '.gates | has("_integrity")' "$REPORT"
  [ "$status" -ne 0 ]
  run jq -se 'any(.[]; .event == "gate_row_restored" and .gate == "ghost")' "$TIMELINE"
  [[ "$output" == *true* ]]
}

@test "case 10: a row bound to a MOVED head is refused, never replayed as a pass" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  alpha:
    command: "echo alpha-ok"
    required: true
    timeout_seconds: 30
  ghost:
    command: "echo never-runs"
    required: true
    timeout_seconds: 30
YAML

  mkdir -p "$ROWS"
  # A PASSING row produced at a revision that is no longer current — exactly
  # the replay this binding exists to stop.
  jq -n '{gate:"ghost", result:"pass", exit_code:0, duration_ms:5, attempts:1,
      output:"green at an older tree",
      _checkpoint:{head:"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
                   written_at:"2026-01-01T00:00:00Z"}}' > "$ROWS/ghost.json"

  AID_TEST_DROP_GATE_RESTORE=ghost run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"

  run jq -r '.gates.ghost.result' "$REPORT"
  [ "$output" = "fail" ]
  run jq -r '.gates.ghost.reason' "$REPORT"
  [ "$output" = "gate_row_stale" ]
  run jq -r '.gates.ghost.stale_reason' "$REPORT"
  [ "$output" = "start_head_moved" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "fail" ]
  # Still counted — the run is a refusal, not a silently short report.
  run jq -e '.gates | has("_integrity")' "$REPORT"
  [ "$status" -ne 0 ]
  run jq -se 'any(.[]; .event == "gate_row_stale" and .gate == "ghost")' "$TIMELINE"
  [[ "$output" == *true* ]]
  run jq -se 'any(.[]; .event == "gate_row_restored" and .gate == "ghost")' "$TIMELINE"
  [[ "$output" == *false* ]]
}

@test "case 11: a row with no revision binding is refused the same way" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  alpha:
    command: "echo alpha-ok"
    required: false
    timeout_seconds: 30
  ghost:
    command: "echo never-runs"
    required: false
    timeout_seconds: 30
YAML

  mkdir -p "$ROWS"
  # Pre-Step-4 shape: no `_checkpoint` envelope at all.
  jq -n '{gate:"ghost", result:"pass", exit_code:0, duration_ms:5, attempts:1,
      output:"unbound legacy row"}' > "$ROWS/ghost.json"

  AID_TEST_DROP_GATE_RESTORE=ghost run run_gates

  run jq -r '.gates.ghost.result' "$REPORT"
  [ "$output" = "fail" ]
  run jq -r '.gates.ghost.stale_reason' "$REPORT"
  [ "$output" = "row_not_bound_to_a_revision" ]
  # required:false, so the run's verdict is unchanged — but the row is not a pass.
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ]
}

@test "case 12: the live writer rejects the DERIVED state and unknown fields" {
  init_project
  _seed_map manual

  run bash -c "cd '$PROJ' && '$FSM' active-runs set E-076-9_9 auto_controller awaiting_host_resume"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DERIVED state"* ]]

  run bash -c "cd '$PROJ' && '$FSM' active-runs set E-076-9_9 auto_controller nonsense"
  [ "$status" -ne 0 ]

  run bash -c "cd '$PROJ' && '$FSM' active-runs set E-076-9_9 governs_main false"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an updatable entry field"* ]]

  # Nothing above touched the entry.
  run jq -r '."E-076-9_9" | [.auto_controller,(.governs_main|tostring)] | join("|")' "$MAP"
  [ "$output" = "manual|false" ]

  # The sanctioned values do land, one key at a time.
  run bash -c "cd '$PROJ' && '$FSM' active-runs set E-076-9_9 auto_controller blocked_for_pm"
  [ "$status" -eq 0 ]
  run jq -r '."E-076-9_9" | [.auto_controller,.run_id,.plan_id] | join("|")' "$MAP"
  [ "$output" = "blocked_for_pm|R-1|P076" ]
}
