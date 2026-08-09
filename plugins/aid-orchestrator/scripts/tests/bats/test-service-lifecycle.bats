#!/usr/bin/env bats
# test-service-lifecycle.bats — P076 Step 10: services wired into a real run.
#
# Everything here drives the REAL aid-run-gates.sh, the REAL aid-fsm.sh, the
# REAL aid-job.sh supervisor and a REAL listening service against a real git
# fixture. The properties under test are process properties — a service that is
# started once, seen by two gates, stopped once, and NOT left running when the
# runner is SIGKILLed — so nothing is simulated with a marker file where a
# process would do, and every "no orphan" assertion is a real check on a real
# pid rather than an assertion about a variable.
#
# Cases:
#   1. two gates, one declared service: exactly ONE up, both gates see it
#      healthy, exactly ONE down — plus the observe-only resource evidence
#   2. a gate whose `needs_services` is unhealthy fails FAST by name, before its
#      job is ever spawned, while every other gate still runs
#   3. an unknown `needs_services` name is refused at config validation, with and
#      without a services block — no gate runs, no service starts
#   4. THE CRASH PATH: a runner SIGKILLed mid-gates leaves a real service
#      running, and the NEXT run-all's ENTRY sweep cancels it before re-acquiring
#   5. `resume` on a STILL-RUNNING job is read-only for services too — the
#      service a live background gate may depend on is left alone
#   6. `resume` on its terminal-collect path sweeps the stale service
#   7. done-advance sweeps against the PROJECT'S execution.yaml, so a stop_cmd
#      planted in the run's own registry is never what executes (CP2 finding 1)
#   8. the same, with a SPACE in the project path — the sweep's yaml argument
#      must not word-split back onto the unreconciled fallback (CP2 finding 1b)
#   9. a second run-all entering a run whose owner is STILL ALIVE refuses,
#      instead of tearing the live run's service down (CP2 finding 2)
#  10. AID_SERVICE_LIFECYCLE_OWNED=1 is RECORDED — a run with declared services
#      and none started must not look like a healthy run (CP2 finding 3)
#
# python3 is a declared dependency of the services feature (per-run ports need a
# real bind probe), so it joins jq/yq/flock in the named-skip list.

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

  command -v jq      >/dev/null 2>&1 || skip "jq is not available"
  command -v yq      >/dev/null 2>&1 || skip "yq is not available"
  command -v flock   >/dev/null 2>&1 || skip "flock is not available"
  command -v python3 >/dev/null 2>&1 || skip "python3 is not available (a declared dependency of the services feature)"

  WORK="$(mktemp -d)"; export WORK
  PROJ="$WORK/project"; export PROJ
  FIX="$WORK/fixtures"; export FIX
  mkdir -p "$PROJ" "$FIX"

  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1
  export AID_RESUME_POLL_SEC=0

  EPIC="E-076-9_9"; export EPIC
  EVID=".aid-o/work/evidence/${EPIC}/R-1"; export EVID
  ABS_EVID="$PROJ/$EVID"; export ABS_EVID
  REG="$ABS_EVID/services.json"; export REG
  RESOURCES="$ABS_EVID/service-resources.jsonl"; export RESOURCES
  ARTIFACT="$ABS_EVID/auto_resume_required.json"; export ARTIFACT
  REPORT="$ABS_EVID/gates/gates_report.json"; export REPORT
  TIMELINE="$ABS_EVID/timeline.jsonl"; export TIMELINE
  JOBS="$ABS_EVID/jobs"; export JOBS
  MAP="$PROJ/.aid-o/work/active-runs.json"; export MAP

  # Every process this test starts carries one of these markers in its argv, so
  # the orphan sweeps below are real `ps` sweeps for THIS test's processes.
  TOKEN="aidsvclc-$$-${RANDOM}-${BATS_TEST_NUMBER}"; export TOKEN
  GTOKEN="aidgatelc-$$-${RANDOM}-${BATS_TEST_NUMBER}"; export GTOKEN

  _write_fixtures
  init_project
}

teardown() {
  # 1. the supervisor's own job process groups
  local d pgid
  for d in "$JOBS"/*/ "$ABS_EVID"/service-jobs/*/*/; do
    [[ -f "${d}job.json" ]] || continue
    pgid="$(jq -r '.pgid // empty' "${d}job.json" 2>/dev/null || true)"
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
  done
  # 2. any runner still polling in this project
  kill_runner
  # 3. hard sweep: nothing carrying THIS test's markers may survive the test
  local p
  for p in $(pgrep -f "$TOKEN" 2>/dev/null || true) $(pgrep -f "$GTOKEN" 2>/dev/null || true); do
    kill -9 "$p" 2>/dev/null || true
  done
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# ── fixtures ────────────────────────────────────────────────────────────────
_write_fixtures() {
  # THE service: binds, listens and serves forever. No SO_REUSEADDR — an
  # ordinary server bind is exactly what a real service does.
  #   $1 port  $2 token (argv marker only)
  cat > "$FIX/listen.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
while True:
    c, _ = s.accept(); c.close()' "$1" "$2"
EOS

  # A service that serves for N seconds and then EXITS — a real service that
  # dies mid-run, which is the only honest way to reach a gate whose dependency
  # is unhealthy (a service that never comes up fails the whole run at acquire).
  #   $1 port  $2 seconds  $3 token
  cat > "$FIX/listen-then-exit.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys,time
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
s.settimeout(0.2)
t0 = time.time()
while time.time() - t0 < float(sys.argv[2]):
    try:
        c, _ = s.accept(); c.close()
    except OSError:
        pass
sys.exit(0)' "$1" "$2" "$3"
EOS

  # THE probe: connect-only, which is exactly right — it asks "is somebody
  # serving", never "may I bind".
  cat > "$FIX/probe.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1.0).close()' "$1"
EOS

  # stop_cmd: appends ONE line per teardown, so "released once" is a line count
  # rather than a belief.
  cat > "$FIX/stop.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "${SVC_PORT:-ENV_WAS_EMPTY}" >> "$1"
EOS

  # A GATE that proves it saw the service: it reads the per-run port out of the
  # run's own registry (the only place it is published) and CONNECTS. A gate
  # that cannot reach the service writes nothing and fails.
  #   $1 marker  $2 registry path  $3 service name
  cat > "$FIX/gate-touch.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
port="$(jq -r --arg n "$3" '.services[$n].port' "$2")"
python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2.0).close()' "$port"
printf '%s\n' "$port" >> "$1"
EOS

  # A gate that marks its own start and then sleeps — the fixture a crash lands
  # in the middle of.
  #   $1 marker  $2 seconds  $3 token
  cat > "$FIX/slow-gate.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
: >> "$1"
exec python3 -c 'import sys,time
time.sleep(float(sys.argv[1]))' "$2" "$3"
EOS

  chmod +x "$FIX"/*.sh
}

init_project() {
  mkdir -p "$ABS_EVID/gates" "$PROJ/.aid-o/work/runs" "$PROJ/.aid-o/config"
  printf 'service lifecycle fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  (
    cd "$PROJ"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email svc@example.com
    git config user.name Svc
    git add README.md .gitignore
    git commit -qm "service lifecycle fixture base"
  )
}

_seed_map() {
  jq -n --arg e "$EPIC" \
    '{($e): {state_file: (".aid-o/work/evidence/" + $e + "/R-1/fsm-state.yaml"),
      run_id: "R-1", state: "GATES", branch: ("task/" + $e + "/main"),
      plan_id: "P076", governs_main: false,
      updated_at: "2026-01-01T00:00:00Z",
      auto_controller: "manual", resume_artifact: null}}' > "$MAP"
}

# The service declaration every case shares, parameterised by start_cmd.
_services_block() {
  cat <<YAML
services:
  api:
    start_cmd: ${1}
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$WORK/stop.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 300
    port_env: SVC_PORT
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

# The runner is identified by what it provably IS — an aid-run-gates.sh run-all
# process whose CWD is THIS test's project — because `$!` is the backgrounded
# subshell, which may or may not be the runner itself.
_runner_pids() {
  local p cwd want
  want="$(readlink -f "$PROJ" 2>/dev/null || echo "$PROJ")"
  for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
    cwd="$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)"
    [[ "$cwd" == "$want" ]] && echo "$p"
  done
  return 0
}

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

_wait_for() { # <seconds> <shell-condition>
  local max="$1" cond="$2" i
  for ((i=0; i<max*10; i++)); do
    if eval "$cond"; then return 0; fi
    sleep 0.1
  done
  return 1
}

_reg_field() { jq -r "${1}" "$REG"; }

# Every pid whose argv carries the service token — the service process itself
# and the supervisor's wrapper running it.
_service_pids() { pgrep -f "$TOKEN" 2>/dev/null | tr '\n' ' ' || true; }

_all_dead() {
  local p
  for p in $1; do kill -0 "$p" 2>/dev/null && return 1; done
  return 0
}

_probe_port() {
  python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1.0).close()' "$1" 2>/dev/null
}

# THE orphan sweep — a real `ps` over the whole process table for this test's
# service token.
_assert_no_service_orphans() {
  local found
  found="$(ps -eo pid,ppid,args 2>/dev/null | grep -F "$TOKEN" | grep -v grep || true)"
  if [[ -n "$found" ]]; then
    echo "ORPHAN SERVICE PROCESSES SURVIVED:" >&2
    echo "$found" >&2
    return 1
  fi
  return 0
}

_job_dir_count() {
  find "$ABS_EVID/service-jobs/${1:-api}" -mindepth 2 -maxdepth 2 -name job.json 2>/dev/null | wc -l
}

# ═══════════════════════════════════════════════════════════════════════════

@test "case 1: two gates, one service — exactly one up, both gates see it healthy, exactly one down" {
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  a_first:
    command: bash "$FIX/gate-touch.sh" "$WORK/a.marker" "$EVID/services.json" api
    required: true
    timeout_seconds: 30
    needs_services: [api]
  b_second:
    command: bash "$FIX/gate-touch.sh" "$WORK/b.marker" "$EVID/services.json" api
    required: true
    timeout_seconds: 30
    needs_services: [api]
YAML
  } > "$PROJ/exec.yaml"

  run run_gates_fg
  [ "$status" -eq 0 ]

  # ── the run itself
  [ "$(jq -r '.overall' "$REPORT")" = "pass" ]
  [ "$(jq -r '.gates.a_first.result' "$REPORT")" = "pass" ]
  [ "$(jq -r '.gates.b_second.result' "$REPORT")" = "pass" ]
  [ "$(jq -r '.gates._integrity // "none"' "$REPORT")" = "none" ]

  # ── UP EXACTLY ONCE: one job directory for the service, one attempt
  [ "$(_job_dir_count api)" -eq 1 ]
  [ "$(_reg_field '.services.api.attempt')" = "1" ]
  [ "$(_reg_field '.services.api.restarts')" = "0" ]

  # ── BOTH GATES SAW THE SAME LIVE SERVICE, on the same per-run port
  local port
  port="$(_reg_field '.services.api.port')"
  [ -f "$WORK/a.marker" ]
  [ -f "$WORK/b.marker" ]
  [ "$(cat "$WORK/a.marker")" = "$port" ]
  [ "$(cat "$WORK/b.marker")" = "$port" ]

  # ── DOWN EXACTLY ONCE: one stop_cmd invocation for two gates, and the
  #    registry's terminal state is the post-teardown one
  [ "$(wc -l < "$WORK/stop.log")" -eq 1 ]
  [ "$(cat "$WORK/stop.log")" = "$port" ]
  [ "$(_reg_field '.services.api.state')" = "stopped" ]
  ! _probe_port "$port"
  _assert_no_service_orphans

  # ── the acquire/release framing is in the timeline, once each
  [ "$(grep -c '"event":"services_acquired"' "$TIMELINE")" -eq 1 ]
  [ "$(grep -c '"event":"services_released"' "$TIMELINE")" -eq 1 ]
  [ "$(grep -c '"event":"service_stale_sweep"' "$TIMELINE" || true)" -eq 0 ]

  # ── OBSERVE-ONLY resource evidence: one line, naming the per-run port
  [ -f "$RESOURCES" ]
  [ "$(wc -l < "$RESOURCES")" -eq 1 ]
  [ "$(jq -r '.kind' "$RESOURCES")" = "external_service" ]
  [ "$(jq -r '.namespace' "$RESOURCES")" = "per-run" ]
  [ "$(jq -r '.id' "$RESOURCES")" = "api:${port}" ]
}

@test "case 2: a gate whose needs_services is unhealthy fails fast by name, before its job is spawned, and the other gates still run" {
  # The service serves for 5s and then exits — a real service that dies mid-run.
  {
    _services_block "bash \"$FIX/listen-then-exit.sh\" \"\$SVC_PORT\" 5 $TOKEN"
    cat <<YAML
gates:
  a_wait:
    command: sleep 9
    required: true
    timeout_seconds: 40
  b_needs:
    command: touch "$WORK/b-ran.marker"
    required: false
    timeout_seconds: 30
    run_mode: background
    needs_services: [api]
  c_after:
    command: touch "$WORK/c-ran.marker"
    required: true
    timeout_seconds: 30
YAML
  } > "$PROJ/exec.yaml"

  run run_gates_fg
  [ "$status" -eq 0 ]

  # the dependent gate failed FAST and by name ...
  [ "$(jq -r '.gates.b_needs.result' "$REPORT")" = "fail" ]
  [ "$(jq -r '.gates.b_needs.reason' "$REPORT")" = "service_unhealthy" ]
  [ "$(jq -r '.gates.b_needs.unhealthy_services | join(",")' "$REPORT")" = "api" ]
  [ "$(jq -r '.gates.b_needs.duration_ms' "$REPORT")" = "0" ]
  [ ! -f "$WORK/b-ran.marker" ]

  # ... and it never reached the supervisor: the health check happens at gate
  # start, BEFORE the job is spawned (the run_mode: background edge case).
  [ ! -d "$JOBS/b_needs-attempt-1" ]

  # every other gate still ran, and the run's accounting still balances
  [ "$(jq -r '.gates.a_wait.result' "$REPORT")" = "pass" ]
  [ "$(jq -r '.gates.c_after.result' "$REPORT")" = "pass" ]
  [ -f "$WORK/c-ran.marker" ]
  [ "$(jq -r '.gates._integrity // "none"' "$REPORT")" = "none" ]
  [ "$(jq -r '.overall' "$REPORT")" = "pass" ]

  _assert_no_service_orphans
}

@test "case 3: an unknown needs_services name is refused at config validation — no gate runs, no service starts" {
  # (a) with a services block that simply does not declare that name
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  g:
    command: touch "$WORK/g-ran.marker"
    required: true
    timeout_seconds: 30
    needs_services: [db]
YAML
  } > "$PROJ/exec.yaml"

  run run_gates_fg
  [ "$status" -ne 0 ]
  [[ "$(cat "$WORK/fg.err")" == *"gate 'g'"* ]]
  [[ "$(cat "$WORK/fg.err")" == *"'db'"* ]]
  [[ "$(cat "$WORK/fg.err")" == *"not a declared service"* ]]
  [ ! -f "$WORK/g-ran.marker" ]
  [ ! -f "$REG" ]
  [ ! -f "$REPORT" ]
  _assert_no_service_orphans

  # (b) with NO services block at all — the loudest case of the same error
  cat > "$PROJ/exec.yaml" <<YAML
gates:
  g:
    command: touch "$WORK/g-ran.marker"
    required: true
    timeout_seconds: 30
    needs_services: [api]
YAML
  run run_gates_fg
  [ "$status" -ne 0 ]
  [[ "$(cat "$WORK/fg.err")" == *"'api'"* ]]
  [[ "$(cat "$WORK/fg.err")" == *"not a declared service"* ]]
  [ ! -f "$WORK/g-ran.marker" ]
}

@test "case 4: THE CRASH PATH — a SIGKILLed runner leaves a real service running, and the next run-all's entry sweep cancels it before re-acquiring" {
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  slow:
    command: bash "$FIX/slow-gate.sh" "$WORK/slow.marker" 40 $GTOKEN
    required: true
    timeout_seconds: 120
YAML
  } > "$PROJ/exec.yaml"

  start_gates_bg
  # the service is up and the gate is running: mid-gates, for real
  _wait_for 60 '[[ "$(jq -r ".services.api.state // \"\"" "$REG" 2>/dev/null)" == "healthy" ]]'
  _wait_for 60 '[[ -f "$WORK/slow.marker" ]]'

  local port1 pids1
  port1="$(_reg_field '.services.api.port')"
  pids1="$(_service_pids)"
  [ -n "$pids1" ]

  kill_runner
  local i; for i in $(seq 1 50); do _runner_alive || break; sleep 0.1; done
  ! _runner_alive

  # THE LEAK IS REAL: the runner is gone and the service is still serving.
  _probe_port "$port1"
  [ "$(_reg_field '.services.api.state')" = "healthy" ]

  # the killed gate's own child is not a service — reaped here so the orphan
  # assertions below are about services and nothing else
  pkill -f "$GTOKEN" 2>/dev/null || true

  # THE RERUN. Same services, a gate that finishes immediately.
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  fast:
    command: bash "$FIX/gate-touch.sh" "$WORK/fast.marker" "$EVID/services.json" api
    required: true
    timeout_seconds: 30
    needs_services: [api]
YAML
  } > "$PROJ/exec.yaml"

  run run_gates_fg
  [ "$status" -eq 0 ]

  # the entry sweep happened, and it happened BEFORE the acquire
  [ "$(grep -c '"event":"service_stale_sweep"' "$TIMELINE")" -ge 1 ]
  local sweep_line acquire_line
  sweep_line="$(grep -n '"event":"service_stale_sweep"' "$TIMELINE" | tail -1 | cut -d: -f1)"
  acquire_line="$(grep -n '"event":"services_acquired"' "$TIMELINE" | tail -1 | cut -d: -f1)"
  [ "$sweep_line" -lt "$acquire_line" ]

  # NO ORPHAN: every process of the crashed run's service is gone ...
  _all_dead "$pids1"
  # ... the rerun's gate ran against a service that was genuinely there ...
  [ -f "$WORK/fast.marker" ]
  [ "$(cat "$WORK/fast.marker")" = "$(_reg_field '.services.api.port')" ]
  # ... a SECOND job directory exists (swept, then started fresh — never a
  # second service beside the first) ...
  [ "$(_job_dir_count api)" -eq 2 ]
  # ... and the rerun released what it acquired.
  [ "$(_reg_field '.services.api.state')" = "stopped" ]
  _assert_no_service_orphans
}

@test "case 5: resume on a STILL-RUNNING job is read-only for services too — a live background gate keeps its dependency" {
  _seed_map
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  bg:
    command: bash "$FIX/slow-gate.sh" "$WORK/bg.marker" 40 $GTOKEN
    required: true
    timeout_seconds: 120
    run_mode: background
    needs_services: [api]
YAML
  } > "$PROJ/exec.yaml"

  start_gates_bg
  _wait_for 60 '[[ "$(jq -r ".services.api.state // \"\"" "$REG" 2>/dev/null)" == "healthy" ]]'
  _wait_for 60 '[[ -f "$JOBS/bg-attempt-1/job.json" ]] && jq -e ".pid != null" "$JOBS/bg-attempt-1/job.json" >/dev/null 2>&1'
  _wait_for 60 '[[ "$(jq -r ".job_id // \"\"" "$ARTIFACT" 2>/dev/null)" == "bg-attempt-1" ]]'

  local port1 pids1
  port1="$(_reg_field '.services.api.port')"
  pids1="$(_service_pids)"

  kill_runner
  local i; for i in $(seq 1 50); do _runner_alive || break; sleep 0.1; done

  # The supervised gate job survives its dead controller — and it may depend on
  # the service, so resume must not touch it.
  [ "$(bash "$JOB_SH" status --jobs-dir "$JOBS" --id bg-attempt-1)" = "running" ]

  run bash -c "cd '$PROJ' && bash '$FSM' resume '$EPIC' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"STILL RUNNING"* ]]

  # READ-ONLY, INCLUDING SERVICES: same state, same port, same processes, still
  # answering. Sweeping here would have killed the live job's dependency.
  [ "$(_reg_field '.services.api.state')" = "healthy" ]
  [ "$(_reg_field '.services.api.port')" = "$port1" ]
  _probe_port "$port1"
  local p; for p in $pids1; do kill -0 "$p"; done
  [ ! -f "$WORK/stop.log" ]
}

@test "case 6: resume on its terminal-collect path sweeps the stale service" {
  _seed_map
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  bg:
    command: bash "$FIX/slow-gate.sh" "$WORK/bg.marker" 40 $GTOKEN
    required: true
    timeout_seconds: 120
    run_mode: background
    needs_services: [api]
YAML
  } > "$PROJ/exec.yaml"

  start_gates_bg
  _wait_for 60 '[[ "$(jq -r ".services.api.state // \"\"" "$REG" 2>/dev/null)" == "healthy" ]]'
  _wait_for 60 '[[ -f "$JOBS/bg-attempt-1/job.json" ]] && jq -e ".pid != null" "$JOBS/bg-attempt-1/job.json" >/dev/null 2>&1'
  _wait_for 60 '[[ "$(jq -r ".job_id // \"\"" "$ARTIFACT" 2>/dev/null)" == "bg-attempt-1" ]]'

  local port1 pids1
  port1="$(_reg_field '.services.api.port')"
  pids1="$(_service_pids)"

  kill_runner
  local i; for i in $(seq 1 50); do _runner_alive || break; sleep 0.1; done

  # The gate job reaches a terminal state — the run is now genuinely dead and
  # there is nothing left of it that could still need the service.
  bash "$JOB_SH" cancel --jobs-dir "$JOBS" --id bg-attempt-1 >/dev/null 2>&1 || true
  _wait_for 30 '[[ "$(bash "$JOB_SH" status --jobs-dir "$JOBS" --id bg-attempt-1)" == "cancelled" ]]'

  # the service is STILL up at this point — the leak resume is about to close
  _probe_port "$port1"

  run bash -c "cd '$PROJ' && bash '$FSM' resume '$EPIC' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelled"* ]]

  [ "$(_reg_field '.services.api.state')" = "stopped" ]
  _all_dead "$pids1"
  ! _probe_port "$port1"
  _assert_no_service_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# CP2 fixes — the sweep's authority, the run's owner, the suppressed lifecycle
# ═══════════════════════════════════════════════════════════════════════════

# A project done-advance can be driven against: a real git repo with the
# `.aid-o` skeleton and the supporting files the release edge reads.
_mk_release_project() {
  local root="$1"
  mkdir -p "$root/.aid-o/plans" "$root/.aid-o/tasks" "$root/.aid-o/config" \
           "$root/.aid-o/work/evidence" "$root/.aid-o/work/runs"
  printf 'counter: 0\n' > "$root/.aid-o/config/counter.yaml"
  : > "$root/.aid-o/work/audit-log.jsonl"
  printf 'plugin_path: "%s"\ndispatch_mode: subagent\n' "$PLUGIN_ROOT" \
    > "$root/.aid-o/config/plugin.yaml"
  printf '.aid-o/\n' > "$root/.gitignore"
  printf 'release fixture\n' > "$root/README.md"
  (
    cd "$root"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email svc@example.com
    git config user.name Svc
    git add README.md .gitignore
    git commit -qm "release fixture base"
  )
}

# A DONE/review state file for <epic>/<run> under <root>, plus the evidence the
# release edge expects. Returns nothing; the caller knows the paths.
_seed_release_run() {
  local root="$1" epic="$2" run="$3" ev="$1/.aid-o/work/evidence/$2/$3"
  mkdir -p "$ev/gates"
  cat > "$ev/fsm-state.yaml" <<YAML
epic_id: $epic
run_id: $run
branch: task/$epic/main
state: DONE
done_phase: review
created_at: 2026-01-01T00:00:00Z
total_steps: 1
current_step: 1
pm_decision: merge
YAML
  printf '{"overall":"pass","_generated_by":"aid-run-gates.sh@test","_generated_at":"2026-01-01T00:00:00Z","_command_log":[]}\n' \
    > "$ev/gates/gates_report.json"
}

# THE PLANT. A registry entry an implementer or a gate-fixer subagent could
# write into the run's own evidence directory, carrying a stop_cmd that is not
# in any declaration. Nothing here is a mock: this is the real registry schema,
# read by the real library.
_plant_hostile_registry() {
  local ev="$1" name="$2" payload="$3"
  jq -n --arg n "$name" --arg stop "touch '$payload'" \
    '{schema:"aid-service-registry/1", updated_at:"2026-01-01T00:00:00Z",
      services: {($n): {service:$n, run_id:"R-1", state:"healthy", job_id:null,
                        port:null, port_env:null, probe_cmd:"false",
                        stop_cmd:$stop, jobs_dir:null, attempt:1,
                        reallocations:0, restarts:0,
                        started_at:"2026-01-01T00:00:00Z",
                        updated_at:"2026-01-01T00:00:00Z",
                        failure_reason:null, violation:null}}}' > "$ev/services.json"
}

# The project's OWN declaration of the same service: a stop_cmd that is
# harmless and observable, so "the declaration won" is a file that exists and
# not merely the absence of one.
_write_declared_config() {
  local root="$1" name="$2" safe="$3"
  cat > "$root/.aid-o/config/execution.yaml" <<YAML
services:
  ${name}:
    start_cmd: sleep 300
    probe_cmd: "false"
    stop_cmd: touch '${safe}'
    startup_deadline_seconds: 10
    max_lifetime_seconds: 60
gates:
  noop:
    command: "true"
    required: true
    timeout_seconds: 10
YAML
}

# done-advance, run from a DIFFERENT git checkout with the project named by
# AID_PROJECT_ROOT — the P074 worktree shape, and the one in which a cwd-relative
# config path silently misses.
_done_advance_from_elsewhere() {
  local root="$1" epic="$2" run="$3" other="$4"
  ( cd "$other" && AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1 AID_PROJECT_ROOT="$root" \
      bash "$FSM" done-advance review release \
        "$root/.aid-o/work/evidence/$epic/$run/fsm-state.yaml" \
        --force --reason "PM-authorized test override to reach the release-edge service sweep" \
      >"$WORK/da.out" 2>"$WORK/da.err" ) 3>&-
}

@test "case 7: done-advance sweeps against the PROJECT'S execution.yaml — a stop_cmd planted in the registry is never what executes" {
  local root="$WORK/relproj" other="$WORK/other"
  _mk_release_project "$root"
  _mk_release_project "$other"
  _seed_release_run "$root" E-076-9_9 R-1
  _write_declared_config "$root" api "$WORK/SAFE"
  _plant_hostile_registry "$root/.aid-o/work/evidence/E-076-9_9/R-1" api "$WORK/PWNED"

  run _done_advance_from_elsewhere "$root" E-076-9_9 R-1 "$other"
  [ "$status" -eq 0 ]

  # THE PROPERTY, asserted first: the registry's own string did NOT run. Before
  # this fix the sweep was handed an empty yaml, fell back to the cwd-relative
  # $AID_SERVICE_CONFIG, found nothing to reconcile against, and ran this.
  [ ! -f "$WORK/PWNED" ]
  # ... and the assertion that keeps the one above from being vacuous: the sweep
  # really did run, and what it ran was the DECLARED command.
  [ -f "$WORK/SAFE" ]
  # the entry is accounted for, not merely skipped
  [ "$(jq -r '.services.api.state' "$root/.aid-o/work/evidence/E-076-9_9/R-1/services.json")" = "stopped" ]
}

@test "case 7b: a registry entry the readable config does NOT declare has its recorded stop_cmd refused, not run" {
  local root="$WORK/relproj2" other="$WORK/other2"
  _mk_release_project "$root"
  _mk_release_project "$other"
  _seed_release_run "$root" E-076-9_9 R-1
  _write_declared_config "$root" api "$WORK/SAFE2"
  # The plant invents a service the config never had — the case passing the
  # yaml alone does not close, because there is no declaration to win.
  _plant_hostile_registry "$root/.aid-o/work/evidence/E-076-9_9/R-1" ghost "$WORK/PWNED2"

  run _done_advance_from_elsewhere "$root" E-076-9_9 R-1 "$other"
  [ "$status" -eq 0 ]

  [ ! -f "$WORK/PWNED2" ]
  [[ "$(cat "$WORK/da.err")" == *"does NOT declare this service"* ]]
  [ "$(jq -r '.services.ghost.state' "$root/.aid-o/work/evidence/E-076-9_9/R-1/services.json")" = "stopped" ]
}

@test "case 8: the sweep's yaml argument survives a SPACE in the project path — no silent fall back to the registry's command" {
  local root="$WORK/rel proj spaced" other="$WORK/other3"
  _mk_release_project "$root"
  _mk_release_project "$other"
  _seed_release_run "$root" E-076-9_9 R-1
  _write_declared_config "$root" api "$WORK/SAFE3"
  _plant_hostile_registry "$root/.aid-o/work/evidence/E-076-9_9/R-1" api "$WORK/PWNED3"

  run _done_advance_from_elsewhere "$root" E-076-9_9 R-1 "$other"
  [ "$status" -eq 0 ]

  [ ! -f "$WORK/PWNED3" ]
  [ -f "$WORK/SAFE3" ]
  # the diagnostic that means the yaml was lost must not appear
  [[ "$(cat "$WORK/da.err")" != *"UNRECONCILED"* ]]
}

@test "case 9: a second run-all against a run whose owner is STILL ALIVE refuses — it does not sweep the live run's service" {
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  slow:
    command: bash "$FIX/slow-gate.sh" "$WORK/slow.marker" 40 $GTOKEN
    required: true
    timeout_seconds: 120
YAML
  } > "$PROJ/exec.yaml"

  start_gates_bg
  _wait_for 60 '[[ "$(jq -r ".services.api.state // \"\"" "$REG" 2>/dev/null)" == "healthy" ]]'
  _wait_for 60 '[[ -f "$WORK/slow.marker" ]]'

  local port1 pids1
  port1="$(_reg_field '.services.api.port')"
  pids1="$(_service_pids)"
  [ -n "$pids1" ]
  # The claim record, read tolerantly: at the commit under test it does not
  # exist at all, and the assertions that matter below are about the LIVE
  # SERVICE, not about this file.
  local owner_pid
  owner_pid="$(jq -r '.pid // empty' "$ABS_EVID/services.owner.json" 2>/dev/null || true)"

  # THE SECOND RUNNER, same epic/run, same registry — a fast gate, so a runner
  # that wrongly proceeds finishes (and tears the live service down) quickly.
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  fast:
    command: "true"
    required: true
    timeout_seconds: 30
YAML
  } > "$PROJ/exec2.yaml"

  run bash -c "cd '$PROJ' && '$RUN_GATES' run-all exec2.yaml '$EPIC' R-1 \
      --report-file '$EVID/gates/gates_report2.json' >'$WORK/second.out' 2>'$WORK/second.err'"

  # THE PROPERTY FIRST: the live run is untouched — same processes, still
  # serving, never stopped, and no sweep even attempted against it. At the
  # commit under test the second runner swept all of this away while the first
  # run's gate was still going.
  local p; for p in $pids1; do kill -0 "$p"; done
  _probe_port "$port1"
  [ "$(_reg_field '.services.api.state')" = "healthy" ]
  [ ! -f "$WORK/stop.log" ]
  [ "$(grep -c '"event":"service_stale_sweep"' "$TIMELINE" || true)" -eq 0 ]

  # ... and it did not happen by luck: the second runner REFUSED, by name.
  [ "$status" -ne 0 ]
  [[ "$(cat "$WORK/second.err")" == *"another gate runner is still managing"* ]]
  [ -n "$owner_pid" ]
  kill -0 "$owner_pid"
  [[ "$(cat "$WORK/second.err")" == *"$owner_pid"* ]]
  [ "$(grep -c '"event":"service_owner_conflict"' "$TIMELINE")" -ge 1 ]

  # And the claim is not a permanent lock: once the owner is gone, the crash
  # recovery of case 4 still applies — proven here by the state the next runner
  # would read rather than by re-running a whole gate suite.
  kill_runner
  local i; for i in $(seq 1 50); do _runner_alive || break; sleep 0.1; done
  ! _runner_alive
  run bash -c "cd '$PROJ' && '$RUN_GATES' run-all exec2.yaml '$EPIC' R-1 \
      --report-file '$EVID/gates/gates_report3.json' >'$WORK/third.out' 2>'$WORK/third.err'"
  [ "$status" -eq 0 ]
  [ "$(grep -c '"event":"service_stale_sweep"' "$TIMELINE")" -ge 1 ]
  _all_dead "$pids1"
  [ "$(_reg_field '.services.api.state')" = "stopped" ]
  [ ! -f "$ABS_EVID/services.owner.json" ]
  _assert_no_service_orphans
}

@test "case 10: AID_SERVICE_LIFECYCLE_OWNED=1 is recorded — a run with declared services and none started cannot look like a healthy one" {
  {
    _services_block "bash \"$FIX/listen.sh\" \"\$SVC_PORT\" $TOKEN"
    cat <<YAML
gates:
  plain:
    command: touch "$WORK/plain.marker"
    required: true
    timeout_seconds: 30
YAML
  } > "$PROJ/exec.yaml"

  run bash -c "cd '$PROJ' && AID_SERVICE_LIFECYCLE_OWNED=1 '$RUN_GATES' run-all exec.yaml '$EPIC' R-1 \
      --report-file '$EVID/gates/gates_report.json' >'$WORK/fg.out' 2>'$WORK/fg.err'"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.overall' "$REPORT")" = "pass" ]
  [ -f "$WORK/plain.marker" ]

  # nothing was started, nothing leaked ...
  [ ! -f "$REG" ]
  [ "$(grep -c '"event":"services_acquired"' "$TIMELINE" || true)" -eq 0 ]
  _assert_no_service_orphans
  # ... and the run's own evidence SAYS SO. Without this line a gate suite that
  # ran against no infrastructure at all is indistinguishable from one that had it.
  [ "$(grep -c '"event":"services_lifecycle_delegated"' "$TIMELINE")" -eq 1 ]
  [[ "$(grep '"event":"services_lifecycle_delegated"' "$TIMELINE")" == *"AID_SERVICE_LIFECYCLE_OWNED"* ]]
}
