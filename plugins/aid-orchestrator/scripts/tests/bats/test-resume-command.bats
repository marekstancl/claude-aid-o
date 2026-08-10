#!/usr/bin/env bats
# test-resume-command.bats — P076 Step 5: `aid-fsm.sh resume <epic_id>`.
#
# The mechanical half of the continuation, and nothing more: claim the
# continuation artifact EXACTLY ONCE, collect the referenced job's terminal
# result, checkpoint it as a durable gate row, and PRINT the next action it
# cannot itself execute. Everything here drives the REAL aid-run-gates.sh, the
# REAL aid-job.sh supervisor and the REAL aid-fsm.sh against a real git
# fixture — no mocks, no hand-written job records except where the fixture IS
# the point (the pid-less wedge).
#
# Cases:
#   1. resume after SIGKILL collects the finished job, writes the row, updates
#      the map, prints the next action, and claims the artifact exactly once
#   2. the row resume writes is IDENTICAL to the in-line path's (diff-asserted)
#   3. the next run-all assembles that row into the report
#   4. parallel double-resume: one winner, every loser names the winner's file
#   5. a still-running job is a READ-ONLY status report — the artifact is
#      byte-identical across two consecutive resumes, and a later resume works
#   6. no artifact → idempotent status report, exit 0, nothing claimed
#   7. a stale result (tree moved) never enters the report as current
#   8. missing job records are a truthful dead end, never a fabricated result
#   9. AC4 — a hostile safe_next_action is printed inert, never executed
#  10. AC5 — a pid-less `started` job has a defined, honest escape, and the
#      live-job refusal is NOT weakened
#  11. resume works from a linked worktree as well as the primary checkout

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  JOB_SH="$PLUGIN_ROOT/scripts/aid-job.sh"
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  export RUN_GATES JOB_SH FSM

  WORK="$(mktemp -d)"; export WORK
  PROJ="$WORK/project"; export PROJ
  mkdir -p "$PROJ"

  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1
  # The courtesy poll is a UX affordance, not a mechanism under test: every
  # case drives an explicit job state, so it is disabled unless a case says
  # otherwise.
  export AID_RESUME_POLL_SEC=0

  EPIC="E-076-9_9"; export EPIC
  EVID=".aid-o/work/evidence/${EPIC}/R-1"; export EVID
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
  # Every runner this test started, however bash arranged the processes.
  local p want
  want="$(readlink -f "${PROJ:-/nonexistent}" 2>/dev/null || true)"
  if [[ -n "$want" ]]; then
    for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
      [[ "$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)" == "$want" ]] && kill -KILL "$p" 2>/dev/null || true
    done
  fi
  [[ -n "${BG_RUNNER_PID:-}" ]] && kill -KILL "$BG_RUNNER_PID" 2>/dev/null || true
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
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

_seed_map() {
  jq -n --arg ac "${1:-manual}" --arg e "$EPIC" \
    '{($e): {state_file: (".aid-o/work/evidence/" + $e + "/R-1/fsm-state.yaml"),
      run_id: "R-1", state: "GATES", branch: ("task/" + $e + "/main"),
      plan_id: "P076", governs_main: false,
      updated_at: "2026-01-01T00:00:00Z",
      auto_controller: $ac, resume_artifact: null}}' > "$MAP"
}

write_exec_yaml() {
  local cmd="$1" timeout="${2:-120}"
  cat > "$PROJ/exec.yaml" <<YAML
gates:
  bg:
    command: "${cmd}"
    required: true
    timeout_seconds: ${timeout}
    run_mode: background
YAML
}

run_gates_fg() {
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml "$EPIC" R-1 \
      --report-file "$EVID/gates/gates_report.json" \
      >"$WORK/fg.out" 2>"$WORK/fg.err" )
}

start_gates_bg() {
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml "$EPIC" R-1 \
      --report-file "$EVID/gates/gates_report.json" ) >"$WORK/bg.out" 2>"$WORK/bg.err" &
  BG_RUNNER_PID=$!
}

# `$!` is the backgrounded SUBSHELL; aid-run-gates.sh may be that process or a
# child of it depending on whether bash exec-optimises the subshell, and
# SIGKILLing only the pid bash reports leaves the runner polling. That silently
# turned "the controller died" fixtures into "the controller is alive"
# (observed: heartbeats continuing 10s past the kill, and a live runner
# deleting the continuation artifact out from under the test).
#
# So the runner is identified by what it provably IS: an aid-run-gates.sh
# run-all process whose CWD is THIS test's project. That is topology-independent
# and safe under parallel bats runs (every test has its own project dir). The
# supervised job runs `bash -c <gate command>` and does not match.
_runner_pids() {
  local p cwd want
  want="$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")"
  for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
    cwd="$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)"
    [[ "$cwd" == "$want" ]] && echo "$p"
  done
  return 0
}

# A killed process lingers as a zombie until it is reaped, and a zombie is not
# a runner — only a live (non-Z) process counts.
_runner_alive() {
  local p st
  for p in $(_runner_pids); do
    st="$(ps -o stat= -p "$p" 2>/dev/null | tr -d ' ')"
    [[ -z "$st" || "$st" == Z* ]] && continue
    return 0
  done
  return 1
}

kill_runner() {
  local p
  for p in $(_runner_pids); do kill -KILL "$p" 2>/dev/null || true; done
  [[ -n "${BG_RUNNER_PID:-}" ]] && kill -KILL "$BG_RUNNER_PID" 2>/dev/null || true
  [[ -n "${BG_RUNNER_PID:-}" ]] && wait "$BG_RUNNER_PID" 2>/dev/null || true
  BG_RUNNER_PID=""
  return 0
}

wait_for_job_pid() {
  local d="$1" i
  for i in $(seq 1 200); do
    [[ -f "$d/job.json" ]] && jq -e '.pid != null' "$d/job.json" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

wait_for_artifact_job() {
  local want="$1" i
  for i in $(seq 1 200); do
    [[ "$(jq -r '.job_id // ""' "$ARTIFACT" 2>/dev/null || true)" == "$want" ]] && return 0
    sleep 0.1
  done
  return 1
}

wait_for_result() {
  local d="$1" i
  for i in $(seq 1 400); do
    [[ -f "$d/result.json" ]] && return 0
    sleep 0.1
  done
  return 1
}

resume() {
  ( cd "$PROJ" && bash "$FSM" resume "$EPIC" "$@" )
}

claim_files() {
  ls -1 "$ARTIFACT".claimed-* 2>/dev/null || true
}

# The exact scenario every case below is a variation of: a controller starts a
# background gate, dies without cleanup, the supervised job outlives it and
# finishes on its own.
kill_controller_after_spawn() {
  start_gates_bg
  wait_for_job_pid "$JOBS/bg-attempt-1"
  wait_for_artifact_job "bg-attempt-1"
  kill_runner
  # Proof the fixture is the one it claims to be: no runner is left polling.
  local i
  for i in $(seq 1 50); do _runner_alive || break; sleep 0.1; done
  ! _runner_alive
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: resume after SIGKILL collects the finished job, records the row, updates the map and prints the next action" {
  init_project
  _seed_map manual
  export AID_AUTO_MODE=1
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  [ -f "$ARTIFACT" ]
  wait_for_result "$JOBS/bg-attempt-1"

  run resume
  echo "$output"
  [ "$status" -eq 0 ]

  # Three lines: what was found, what is recorded, the next action.
  [ "$(printf '%s\n' "$output" | grep -c "^resume ${EPIC}: ")" -eq 3 ]
  [[ "$output" == *"terminal_pass"* ]]
  [[ "$output" == *"gate row 'bg' = pass"* ]]
  [[ "$output" == *"aid-run-gates.sh run-all"* ]]
  [[ "$output" == *"run it — this command cannot"* ]]

  # The row landed in the durable checkpoint — and ONLY there. resume never
  # edits a final report in place; there is no report yet at all.
  [ -f "$ROWS/bg.json" ]
  run jq -r '[.gate,.result,.exit_code,.job_id,.job_state,.attempts] | join("|")' "$ROWS/bg.json"
  [ "$output" = "bg|pass|0|bg-attempt-1|terminal_pass|1" ]
  run jq -e '._checkpoint.head != null and ._checkpoint.written_at != null' "$ROWS/bg.json"
  [ "$status" -eq 0 ]

  # Claimed exactly once, and the artifact is gone from its live path.
  [ ! -f "$ARTIFACT" ]
  [ "$(claim_files | wc -l)" -eq 1 ]

  # The map went through the ONE writer: pointer cleared, AUTO controller
  # re-asserted, every other field of the entry untouched.
  run jq -r ".\"${EPIC}\".resume_artifact" "$MAP"
  [ "$output" = "null" ]
  run jq -r ".\"${EPIC}\".auto_controller" "$MAP"
  [ "$output" = "active" ]
  run jq -r ".\"${EPIC}\" | [.run_id,.plan_id,.state] | join(\"|\")" "$MAP"
  [ "$output" = "R-1|P076|GATES" ]
}

@test "case 2: the row resume writes is identical to the in-line path's (diff-asserted)" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 2; echo bg-done"

  # (a) the in-line path, start to finish, in one live runner.
  run run_gates_fg
  echo "inline stderr: $(cat "$WORK/fg.err")"
  [ "$status" -eq 0 ]
  [ -f "$ROWS/bg.json" ]
  cp "$ROWS/bg.json" "$WORK/row-inline.json"

  # Reset to the same starting conditions: same repo, same HEAD, same command,
  # same (empty) runtime baseline. Only the WRITER differs.
  rm -rf "$ROWS" "$JOBS" "$PROJ/$EVID/gates/gates_report.json" "$AID_GATE_BASELINE_FILE"
  _seed_map manual

  # (b) the resume path: controller dies, job finishes alone, resume records it.
  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"
  run resume
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$ROWS/bg.json" ]
  cp "$ROWS/bg.json" "$WORK/row-resume.json"

  # Both are ONE compact line — the shape the restore pass reads.
  [ "$(wc -l < "$WORK/row-inline.json")" -eq 1 ]
  [ "$(wc -l < "$WORK/row-resume.json")" -eq 1 ]

  # KEY SETS first, including nested: an extra or missing field is a shape
  # difference the normalisation below could otherwise hide.
  run bash -c "diff <(jq -S 'paths|join(\".\")' '$WORK/row-inline.json') <(jq -S 'paths|join(\".\")' '$WORK/row-resume.json')"
  echo "key diff: $output"
  [ "$status" -eq 0 ]

  # VALUES, with only the four genuinely time-varying measurements pinned:
  # the wall-clock duration, the checkpoint timestamp, and the two baseline
  # figures derived from that duration. Everything else — gate, result,
  # exit_code, output, job_id, job_state, attempts, sample counts, the
  # recorded HEAD — must match byte for byte.
  local norm='.duration_ms = 0
              | ._checkpoint.written_at = "PINNED"
              | .runtime_baseline.p95_ms = 0
              | .runtime_baseline.timeout_recommended_seconds = 0'
  run bash -c "diff <(jq -S '$norm' '$WORK/row-inline.json') <(jq -S '$norm' '$WORK/row-resume.json')"
  echo "value diff: $output"
  [ "$status" -eq 0 ]

  # The pinned fields are PRESENT and real in the resume row, not absent.
  run jq -e '.duration_ms >= 0 and (._checkpoint.written_at | test("^[0-9]{4}-"))' "$WORK/row-resume.json"
  [ "$status" -eq 0 ]
  # Bound to the CURRENT revision — the restore pass refuses anything else.
  run jq -r '._checkpoint.head' "$WORK/row-resume.json"
  [ "$output" = "$(cd "$PROJ" && git rev-parse HEAD)" ]
}

@test "case 3: the next run-all assembles the resume-written row into the report" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"
  run resume
  [ "$status" -eq 0 ]
  [ -f "$ROWS/bg.json" ]

  # The next run-all, with `bg` DEFINED but never iterated — the shape a runner
  # killed mid-loop leaves behind, and the only state in which the restore pass
  # is reachable (every ordinary path emits its own row). The job records are
  # removed too, so nothing but the checkpoint can produce this gate's result.
  rm -rf "$JOBS"
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  alpha:
    command: "echo alpha-ok"
    required: true
    timeout_seconds: 30
  bg:
    command: "sleep 3; echo bg-done"
    required: true
    timeout_seconds: 120
    run_mode: background
YAML
  AID_TEST_DROP_GATE_RESTORE=bg run run_gates_fg
  echo "stderr: $(cat "$WORK/fg.err")"
  [ "$status" -eq 0 ]

  # Assembled verbatim from what resume wrote — result, binding and all.
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  run jq -r '.gates.bg.job_id' "$REPORT"
  [ "$output" = "bg-attempt-1" ]
  run jq -r '.gates.bg.output' "$REPORT"
  [ "$output" = "bg-done" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ]
  # Restored, not refused: the row resume wrote carries a valid revision
  # binding, so the freshness check accepts it.
  run jq -se 'any(.[]; .event == "gate_row_restored" and .gate == "bg")' "$TIMELINE"
  [[ "$output" == *true* ]]
  run grep -c 'gate_row_stale' "$TIMELINE"
  [ "$status" -ne 0 ]
}

@test "case 4: parallel double-resume — exactly one claim winner, every loser names the winner's claim file" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"

  # A start barrier so the racers reach the claim together rather than in
  # sequence — the interleaving the single-use primitive exists for.
  local i
  for i in 1 2 3 4; do
    ( while [[ ! -f "$WORK/go" ]]; do sleep 0.02; done
      cd "$PROJ" && bash "$FSM" resume "$EPIC" >"$WORK/race$i.out" 2>&1 ) &
  done
  sleep 0.4
  touch "$WORK/go"
  wait

  cat "$WORK"/race*.out

  # Exactly ONE claim happened.
  [ "$(cat "$WORK"/race*.out | grep -c 'pointer claimed as')" -eq 1 ]
  [ "$(claim_files | wc -l)" -eq 1 ]
  local winner; winner="$(claim_files)"
  [ -n "$winner" ]

  # Every racer that did NOT win names the winner's claim file — whether it
  # lost the mv race or arrived after it was over.
  local f losers=0
  for f in "$WORK"/race*.out; do
    if grep -q 'pointer claimed as' "$f"; then continue; fi
    losers=$((losers + 1))
    grep -q "$(basename "$winner")" "$f" || {
      echo "loser output does not name the winner: $(cat "$f")"; return 1; }
    grep -q 'recorded — nothing by this invocation' "$f" || {
      echo "loser claims to have recorded something: $(cat "$f")"; return 1; }
  done
  [ "$losers" -eq 3 ]
}

@test "case 5: a still-running job is a READ-ONLY status report — the artifact is untouched and still claimable later" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 12; echo bg-done" 120

  kill_controller_after_spawn

  local before; before="$(sha256sum "$ARTIFACT" | cut -d' ' -f1)"

  run resume
  echo "1st: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STILL RUNNING"* ]]
  [[ "$output" == *"deadline remaining:"* ]]
  [[ "$output" == *"a status look never claims"* ]]

  run resume
  echo "2nd: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STILL RUNNING"* ]]

  # Two consecutive running-state resumes see the SAME artifact bytes, and no
  # claim file was ever created: the live-job-has-exactly-one-artifact
  # invariant holds through every status look.
  local after; after="$(sha256sum "$ARTIFACT" | cut -d' ' -f1)"
  [ "$before" = "$after" ]
  [ "$(claim_files | wc -l)" -eq 0 ]
  [ ! -f "$ROWS/bg.json" ]

  # And a LATER resume, once the job is terminal, still works — the artifact
  # was never spent by the status looks.
  wait_for_result "$JOBS/bg-attempt-1"
  run resume
  echo "3rd: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate row 'bg' = pass"* ]]
  [ "$(claim_files | wc -l)" -eq 1 ]
}

@test "case 6: resume with no artifact is an idempotent status report, exit 0, nothing claimed" {
  init_project
  _seed_map manual

  run resume
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no continuation artifact"* ]]
  [[ "$output" == *"FSM state GATES (run R-1)"* ]]
  [[ "$output" == *"nothing to resume"* ]]

  run resume
  [ "$status" -eq 0 ]
  [[ "$output" == *"no continuation artifact"* ]]

  [ "$(claim_files | wc -l)" -eq 0 ]
  [ ! -d "$ROWS" ]
  # Nothing was written to the map either.
  run jq -r ".\"${EPIC}\".updated_at" "$MAP"
  [ "$output" = "2026-01-01T00:00:00Z" ]
}

@test "case 7: a stale result (the tree moved) is reported verbatim and never enters the report as current" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"

  # The tree moves after the job produced its result.
  ( cd "$PROJ" && printf 'moved\n' >> README.md && git add README.md \
      && git commit -qm "tree moves after the job finished" )

  run resume
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STALE"* ]]
  [[ "$output" == *"stale result is not current evidence"* ]]
  [[ "$output" == *"rerun the gate at the current revision"* ]]

  # No row: a stale result is never patched in.
  [ ! -f "$ROWS/bg.json" ]
  # The claim still happened — the result was consumed (and refused).
  [ "$(claim_files | wc -l)" -eq 1 ]
}

@test "case 8: missing job records are a truthful dead end — no row, no fabricated result" {
  init_project
  _seed_map manual
  export AID_AUTO_MODE=1
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"
  # Evidence wiped: the pointer survives, the job records do not.
  rm -rf "$JOBS"

  run resume
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"job records missing"* ]]
  [[ "$output" == *"rerun the gate"* ]]
  [[ "$output" == *"a missing record is never a result"* ]]
  [ ! -f "$ROWS/bg.json" ]
  [ "$(claim_files | wc -l)" -eq 1 ]
  run jq -r ".\"${EPIC}\".auto_controller" "$MAP"
  [ "$output" = "active" ]
}

@test "case 9: AC4 — a hostile safe_next_action is printed inert and nothing executes it" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"

  # The writer forbids '<' and nothing more: ';', backticks and $(...) pass
  # both the writer and the schema today. resume is the command that PRINTS
  # that string for a human to paste.
  local hostile='bash /x/aid-run-gates.sh run-all e.yaml E R; touch '"$WORK"'/PWNED; $(touch '"$WORK"'/PWNED2)'
  local tmp="$WORK/art.json"
  jq --arg n "$hostile" '.safe_next_action = $n' "$ARTIFACT" > "$tmp"
  mv "$tmp" "$ARTIFACT"

  run resume
  echo "$output"
  [ "$status" -eq 0 ]

  # Nothing ran.
  [ ! -e "$WORK/PWNED" ]
  [ ! -e "$WORK/PWNED2" ]
  # It was rendered inert (printf %q) rather than pasted raw, and said so.
  [[ "$output" == *"shown QUOTED"* ]]

  # The claim + row still happened — the hostile string changes what is
  # PRINTED, never whether the mechanical core did its job.
  [ -f "$ROWS/bg.json" ]
  run jq -r '.result' "$ROWS/bg.json"
  [ "$output" = "pass" ]
}

@test "case 10: AC5 — a pid-less 'started' job has a defined escape, and a genuinely live job is still refused" {
  init_project
  _seed_map manual

  # A job whose wrapper launched but never recorded a pid: `status` reads
  # `started` forever, and Step 4's init preflight refuses the EPIC while it
  # does. Handcrafted deliberately — this state cannot be produced on demand.
  mkdir -p "$JOBS/bg-attempt-1"
  local old=$(( $(date -u +%s) - 3600 ))
  jq -n --arg d "$JOBS/bg-attempt-1" --arg repo "$PROJ" --argjson se "$old" \
    '{schema:"aid-job/1", id:"bg-attempt-1", label:"bg", owner:"", repo:$repo,
      state:"started", command_fingerprint:"0000000000000000000000000000000000000000000000000000000000000000",
      start_head:"none", start_tree:"none",
      started_at:"2026-01-01T00:00:00Z", started_epoch:$se,
      expected_p95_sec:0, deadline_sec:600, polarity:"", expect:"", filter:"",
      stdout_path:($d+"/stdout.log"), result_path:($d+"/result.json"),
      pid:null, pgid:null, proc_starttime:null, cookie:null,
      command:["bash","-c","echo hi"]}' > "$JOBS/bg-attempt-1/job.json"
  jq -n --arg jobs "$EVID/jobs" \
    '{schema:"aid-auto-resume/1", plan_id:"P076", epic_id:"E-076-9_9", run_id:"R-1",
      job_id:"bg-attempt-1", jobs_dir:$jobs, gate:"bg",
      command_fingerprint:"0000000000000000000000000000000000000000000000000000000000000000",
      expected_terminal_states:["terminal_pass","terminal_fail","timed_out","cancelled"],
      safe_next_action:"bash /x/aid-run-gates.sh run-all e.yaml E-076-9_9 R-1",
      created_at:"2026-01-01T00:00:00Z"}' > "$ARTIFACT"

  run bash -c "cd '$PROJ' && bash '$JOB_SH' status --jobs-dir '$JOBS' --id bg-attempt-1"
  [ "$output" = "started" ]

  # Today that wedges init: the preflight refuses, and there is no --force.
  run bash -c "cd '$PROJ' && source '$FSM' >/dev/null 2>&1; _fsm_resume_artifact_preflight '$EPIC'"
  echo "preflight before: $status / $output"
  [ "$status" -eq 2 ]

  # Default resume: reports truthfully, offers the resolution, claims NOTHING.
  run resume
  echo "default: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"without ever recording a pid"* ]]
  [[ "$output" == *"--resolve-pidless"* ]]
  [[ "$output" == *"does not cancel a job behind your back"* ]]
  [ -f "$ARTIFACT" ]
  [ "$(claim_files | wc -l)" -eq 0 ]

  # On request it resolves it — a RECORDED terminal cancellation, never a
  # fabricated gate result, and never a gate row.
  cp "$ARTIFACT" "$WORK/artifact-copy.json"
  run resume --resolve-pidless
  echo "resolve: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrapper never came up"* ]]
  [[ "$output" == *"terminal CANCELLED job record"* ]]
  [[ "$output" == *"did not run"* ]]
  [ ! -f "$ROWS/bg.json" ]
  [ "$(claim_files | wc -l)" -eq 1 ]

  run bash -c "cd '$PROJ' && bash '$JOB_SH' status --jobs-dir '$JOBS' --id bg-attempt-1"
  [ "$output" = "cancelled" ]

  # The wedge is gone: with the same artifact back in place the preflight now
  # PROCEEDS (archiving it) instead of refusing.
  cp "$WORK/artifact-copy.json" "$ARTIFACT"
  run bash -c "cd '$PROJ' && source '$FSM' >/dev/null 2>&1; _fsm_resume_artifact_preflight '$EPIC'"
  echo "preflight after: $status / $output"
  [ "$status" -eq 0 ]

  # And the live-job refusal itself is NOT weakened: a genuinely running job
  # still refuses init, and resume still will not claim its artifact.
  rm -rf "$JOBS" "$ARTIFACT" "$ARTIFACT".claimed-* "$ARTIFACT".superseded-*
  write_exec_yaml "sleep 12; echo bg-done" 120
  start_gates_bg
  wait_for_job_pid "$JOBS/bg-attempt-1"
  wait_for_artifact_job "bg-attempt-1"
  run bash -c "cd '$PROJ' && source '$FSM' >/dev/null 2>&1; _fsm_resume_artifact_preflight '$EPIC'"
  echo "preflight live: $status / $output"
  [ "$status" -eq 2 ]
  run resume --resolve-pidless
  echo "live resume: $output"
  [[ "$output" == *"STILL RUNNING"* ]]
  [ -f "$ARTIFACT" ]
}

@test "case 11: resume works from a linked worktree as well as from the primary checkout" {
  init_project
  _seed_map manual
  write_exec_yaml "sleep 3; echo bg-done"

  kill_controller_after_spawn
  wait_for_result "$JOBS/bg-attempt-1"

  ( cd "$PROJ" && git worktree add -q -b wt-branch "$WORK/wt" HEAD )

  # Same state, resolved through aid-roots from a completely different CWD.
  run bash -c "cd '$WORK/wt' && bash '$FSM' resume '$EPIC'"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gate row 'bg' = pass"* ]]
  # The row landed in the PRIMARY checkout's workspace, not the worktree's.
  [ -f "$ROWS/bg.json" ]
  [ ! -e "$WORK/wt/.aid-o" ]
  [ "$(claim_files | wc -l)" -eq 1 ]
}
