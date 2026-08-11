#!/usr/bin/env bats
# aid-tier: t2
# test-aid-service.bats — P076 Step 9, lib/aid-service.sh.
#
# Real listeners, real ports, real SIGKILLs, real orphan sweeps. Nothing here is
# simulated with a marker file where a process would do, because the properties
# under test ARE process properties: that a crash in any window leaves a record
# every teardown path can see, that a deadline leaves nothing running, and that
# a start_cmd which hands off to a child is refused by name rather than
# reported healthy.
#
# The fixture service is a python3 one-line listener. bash's /dev/tcp is
# connect-only — it can neither LISTEN nor genuinely bind-probe — so python3
# joins yq/jq/flock in the named-skip list when it is absent.
#
# Every test carries a unique TOKEN in its listener's argv, so the orphan sweeps
# below are real `ps` sweeps for THIS test's processes and cannot be satisfied
# by an assertion about a variable.

setup() {
  export TZ=UTC
  LIB="${BATS_TEST_DIRNAME}/../../lib/aid-service.sh"
  JOB_SH="${BATS_TEST_DIRNAME}/../../aid-job.sh"
  command -v jq    >/dev/null 2>&1 || skip "jq is not available"
  command -v yq    >/dev/null 2>&1 || skip "yq is not available"
  command -v flock >/dev/null 2>&1 || skip "flock is not available"
  [ -f "$LIB" ]    || skip "lib/aid-service.sh not found"

  TMP="$(mktemp -d)"
  REPO="$TMP/project"
  EV="$REPO/.aid-o/work/evidence/E-076-2_3/run-1"
  FIX="$TMP/fixtures"
  YAML="$TMP/execution.yaml"
  TOKEN="aidsvcfix-$$-${RANDOM}-${BATS_TEST_NUMBER}"

  mkdir -p "$REPO" "$FIX" "$EV"
  cd "$REPO"
  git init -q -b main
  git config user.email test@test.local
  git config user.name Test
  echo seed > file.txt
  git add file.txt
  git commit -q -m initial

  _write_fixtures
}

teardown() {
  # 1. best-effort teardown through the lib itself
  bash "$DRIVE" "$LIB" aid_service_down_all "$EV" >/dev/null 2>&1 || true
  # 2. hard sweep: nothing carrying THIS test's token may survive the test
  local p
  for p in $(pgrep -f "$TOKEN" 2>/dev/null || true); do
    kill -9 "$p" 2>/dev/null || true
  done
  [[ -n "${HOLDPID:-}" ]] && kill -9 "$HOLDPID" 2>/dev/null
  [[ -n "${UPPID:-}"   ]] && kill -9 "$UPPID"   2>/dev/null
  cd /
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

_need_python3() {
  command -v python3 >/dev/null 2>&1 \
    || skip "python3 is not available (a declared dependency of the services feature)"
}

# ── fixtures ────────────────────────────────────────────────────────────────
_write_fixtures() {
  DRIVE="$TMP/drive.sh"
  cat > "$DRIVE" <<'EOS'
#!/usr/bin/env bash
# Sources the lib under the same `set -euo pipefail` a real caller uses, then
# invokes ONE of its functions. Proves the lib is safe to source into a strict
# shell as well as exercising it.
set -euo pipefail
lib="$1"; shift
source "$lib"
"$@"
EOS

  # THE listener: a python3 one-liner that binds, listens and serves forever.
  # No SO_REUSEADDR — the point is an ordinary server bind, so a port already
  # held by another LISTEN produces a genuine EADDRINUSE.
  #   $1 port  $2 pre-bind delay seconds  $3 token (argv marker only)
  cat > "$FIX/listen.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys,time
time.sleep(float(sys.argv[2]))
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
while True:
    c, _ = s.accept(); c.close()' "$1" "$2" "$3"
EOS

  # THE probe: connect-only is exactly right for a probe (it asks "is somebody
  # serving", not "may I bind").
  cat > "$FIX/probe.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1.0).close()' "$1"
EOS

  # THE stop command: records the port it was handed, so a test can prove the
  # value came from the registry rather than from an inherited environment.
  cat > "$FIX/stop.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "${SVC_PORT:-ENV_WAS_EMPTY}" >> "$1"
EOS

  # A port HOLDER: allocates a port, writes it out, and keeps LISTENing on it.
  cat > "$FIX/hold.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys
s = socket.socket()
s.bind(("127.0.0.1", 0))
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
s.listen(8)
while True:
    c, _ = s.accept(); c.close()' "$1" "$2"
EOS

  # A start_cmd that collides on its FIRST invocation only: it binds the
  # already-held port instead of the one it was allocated. The collision is a
  # real EADDRINUSE from a real pre-bound LISTEN — only WHICH port it reaches
  # for is steered, so the reallocation path is exercised for real.
  #   $1 marker  $2 held-port file  $3 token
  cat > "$FIX/collide.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
if [[ -f "$1" ]]; then
  port="$SVC_PORT"
else
  : > "$1"
  port="$(cat "$2")"
fi
exec python3 -c 'import socket,sys
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
while True:
    c, _ = s.accept(); c.close()' "$port" "$3"
EOS

  # A start_cmd that DAEMONISES INSIDE ITSELF — the residual the execution.yaml
  # syntactic lint says plainly it cannot catch. There is no `&`, no `nohup`,
  # no `disown`: it forks, the child serves, the parent returns 0.
  #
  # The ordering is DETERMINISTIC, not lucky, and deliberately in the direction
  # that is hardest for the lib: the parent returns 0 immediately, and the child
  # waits to be REPARENTED (proof the parent is gone) plus a settable delay
  # (time for the supervisor to record the terminal result) before it binds. So
  # there is no instant at which the probe can succeed while the job is still
  # running — the only way the lib can reach the right verdict is by continuing
  # to probe AFTER the job has ended.
  #
  # $3 is the POST-REPARENT DELAY, and it is a parameter rather than a constant
  # because the interesting question is not "does the lib notice a fast hand-off"
  # but "how late may a hand-off be and still be named". Test 6 uses the fast
  # form; test 18 uses one that binds long after any fixed grace window.
  #   $1 port  $2 token  $3 post-reparent delay seconds (default 0.5)
  cat > "$FIX/daemonize.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import os,socket,sys,time
if os.fork() > 0:
    sys.exit(0)                      # start_cmd returns AT ONCE
ppid = os.getppid()
while os.getppid() == ppid:          # ... wait until we are reparented
    time.sleep(0.05)
time.sleep(float(sys.argv[3]))       # ... and the job record says terminal
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
while True:
    c, _ = s.accept(); c.close()' "$1" "$2" "${3:-0.5}"
EOS

  # A process that lives but never becomes healthy.
  cat > "$FIX/idle.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import time,sys
time.sleep(600)' "$1"
EOS

  chmod +x "$FIX"/*.sh "$DRIVE"
}

# _yaml <<'EOF' ... EOF — write execution.yaml from stdin.
_yaml() { cat > "$YAML"; }

_reg() { jq -r "$1" "$EV/services.json"; }

_job_dirs() {
  local n="$1"
  find "$EV/${2:-service-jobs}/$n" -mindepth 2 -maxdepth 2 -name job.json 2>/dev/null | wc -l
}

# THE orphan sweep. A real `ps` over the whole process table for this test's
# token — not a variable, not an assertion about intent.
_assert_no_orphans() {
  local found
  found="$(ps -eo pid,ppid,args 2>/dev/null | grep -F "$TOKEN" | grep -v grep || true)"
  if [[ -n "$found" ]]; then
    echo "ORPHAN PROCESSES SURVIVED:" >&2
    echo "$found" >&2
    return 1
  fi
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

# ═══════════════════════════════════════════════════════════════════════════
# 1. absent -> starting -> healthy, with the allocated port recorded
# ═══════════════════════════════════════════════════════════════════════════
@test "1: a declared service goes absent -> starting -> healthy with its allocated port recorded" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 3 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop-port.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  # ── absent: no registry, no entry
  run bash "$DRIVE" "$LIB" aid_service_status api "$EV"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.state == "absent"'
  [ ! -f "$EV/services.json" ]

  # ── starting: observed WHILE up_all is still probing (the listener sleeps 3 s
  #    before binding), and it already carries the real job id.
  bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML" & UPPID=$!
  _wait_for 20 '[[ -f "$EV/services.json" ]] && [[ "$(jq -r ".services.api.job_id // \"\"" "$EV/services.json")" != "" ]]'
  [ "$(_reg '.services.api.state')" = "starting" ]
  starting_job="$(_reg '.services.api.job_id')"
  [ -n "$starting_job" ]
  starting_port="$(_reg '.services.api.port')"
  [ "$starting_port" -gt 0 ]

  # ── healthy
  wait "$UPPID"; UPPID=""
  [ "$(_reg '.services.api.state')" = "healthy" ]
  [ "$(_reg '.services.api.job_id')" = "$starting_job" ]
  [ "$(_reg '.services.api.port')" = "$starting_port" ]
  [ "$(_reg '.services.api.reallocations')" = "0" ]
  [ "$(_reg '.services.api.restarts')" = "0" ]

  # the recorded port is genuinely being served, right now
  run bash "$FIX/probe.sh" "$starting_port"
  [ "$status" -eq 0 ]

  run bash "$DRIVE" "$LIB" aid_service_status api "$EV"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --argjson p "$starting_port" '.state == "healthy" and .port == $p'

  bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 2. the accepted crash window: SIGKILL between spawn and the healthy flip
# ═══════════════════════════════════════════════════════════════════════════
@test "2: a SIGKILL between spawn and the healthy flip leaves a 'starting' entry that down_all cancels" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 30 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop-port.log"
    startup_deadline_seconds: 60
    max_lifetime_seconds: 300
    port_env: SVC_PORT
EOF

  bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML" & UPPID=$!
  _wait_for 30 '[[ -f "$EV/services.json" ]] && [[ "$(jq -r ".services.api.job_id // \"\"" "$EV/services.json")" != "" ]]'

  job_id="$(_reg '.services.api.job_id')"
  [ "$(_reg '.services.api.state')" = "starting" ]

  # SIGKILL the up_all process itself — no trap, no chance to tidy up. This is
  # the crash window the eager two-phase write exists for.
  kill -9 "$UPPID" 2>/dev/null || true
  wait "$UPPID" 2>/dev/null || true
  UPPID=""

  # What a teardown finds on disk: a starting entry naming a LIVE job.
  [ "$(_reg '.services.api.state')" = "starting" ]
  run bash "$JOB_SH" status --jobs-dir "$EV/service-jobs/api" --id "$job_id"
  [ "$output" = "running" ]
  run pgrep -f "$TOKEN"
  [ "$status" -eq 0 ]                      # the service really is alive

  # down_all, in a fresh process that never saw the startup, reads the registry
  # and cancels it.
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  [ "$(_reg '.services.api.state')" = "stopped" ]
  run bash "$JOB_SH" status --jobs-dir "$EV/service-jobs/api" --id "$job_id"
  [[ "$output" =~ ^(cancelled|terminal_fail|timed_out)$ ]]
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. one reallocation on a real bind collision, then success
# ═══════════════════════════════════════════════════════════════════════════
@test "3: a pre-bound port triggers exactly one reallocation and then comes up healthy" {
  _need_python3
  bash "$FIX/hold.sh" "$TMP/held.port" "${TOKEN}-hold" >/dev/null 2>&1 & HOLDPID=$!
  _wait_for 15 '[[ -s "$TMP/held.port" ]]'
  held="$(cat "$TMP/held.port")"
  [ "$held" -gt 0 ]
  run bash "$FIX/probe.sh" "$held"
  [ "$status" -eq 0 ]                      # the port really is held, LISTENing

  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/collide.sh" "$TMP/collide.mark" "$TMP/held.port" $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    # Short on purpose: a job that has ended is now probed for the REST of its
    # declared startup budget (that is what makes the daemonize verdict a
    # property of the declaration rather than of a private 5 s timer), so the
    # budget is also what a failing attempt costs before the reallocation.
    startup_deadline_seconds: 8
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "was taken between allocation and bind" ]]

  [ "$(_reg '.services.api.state')" = "healthy" ]
  [ "$(_reg '.services.api.reallocations')" = "1" ]
  [ "$(_reg '.services.api.attempt')" = "2" ]
  final_port="$(_reg '.services.api.port')"
  [ "$final_port" != "$held" ]

  # exactly one reallocation: two job directories, no more
  [ "$(_job_dirs api)" -eq 2 ]

  # and one of the two jobs really did die on a genuine EADDRINUSE
  run grep -lE "[Aa]ddress already in use" "$EV/service-jobs/api"/*/stdout.log
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]    # exactly one collided, not both

  bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  kill -9 "$HOLDPID" 2>/dev/null || true; HOLDPID=""
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 4. deadline expiry: cancel AND stop_cmd, and nothing left running
# ═══════════════════════════════════════════════════════════════════════════
@test "4: max_lifetime expiry cancels the job, runs stop_cmd, and leaves no orphan" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 300 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop-port.log"
    # See test 3: the post-terminal probe window runs to the declared startup
    # budget, so this is kept just wide enough to outlast max_lifetime.
    startup_deadline_seconds: 8
    max_lifetime_seconds: 3
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "its job was cancelled and stop_cmd run" ]]
  [ "$(_reg '.services.api.state')" = "timed_out" ]

  # stop_cmd genuinely ran, with the registry's port in hand
  [ -f "$TMP/stop-port.log" ]
  [ "$(head -1 "$TMP/stop-port.log")" = "$(_reg '.services.api.port')" ]

  # THE sweep: a real ps over the process table, printed if it finds anything.
  _assert_no_orphans
  run bash "$JOB_SH" status --jobs-dir "$EV/service-jobs/api" --id "$(_reg '.services.api.job_id')"
  [ "$output" = "timed_out" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 5. exactly one authorized restart, then a named failure
# ═══════════════════════════════════════════════════════════════════════════
@test "5: an unhealthy service with restart_authorized restarts exactly once, then fails by name" {
  _need_python3
  _yaml <<EOF
services:
  worker:
    start_cmd: bash "$FIX/idle.sh" $TOKEN
    probe_cmd: /bin/false
    startup_deadline_seconds: 2
    max_lifetime_seconds: 120
    restart_authorized: true
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "spending the ONE authorized restart" ]]
  [[ "$output" =~ "still unhealthy after the one authorized restart" ]]

  [ "$(_reg '.services.worker.restarts')" = "1" ]
  [ "$(_reg '.services.worker.state')" = "timed_out" ]
  [ "$(_reg '.services.worker.attempt')" = "2" ]
  [ "$(_job_dirs worker)" -eq 2 ]          # exactly one restart, not a loop
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 6. the daemonising start_cmd refusal
# ═══════════════════════════════════════════════════════════════════════════
@test "6: a start_cmd that daemonises internally is refused by name" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/daemonize.sh" "\$SVC_PORT" $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    startup_deadline_seconds: 30
    max_lifetime_seconds: 120
    log_hint: docker logs api
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "start_cmd must remain its job's foreground process" ]]
  [[ "$output" =~ "while the probe still reports healthy" ]]
  [[ "$output" =~ "docker logs api" ]]     # log_hint surfaced to the human

  [ "$(_reg '.services.api.state')" = "unhealthy" ]
  [ "$(_reg '.services.api.failure_reason')" = "daemonized_start_cmd" ]
  [ "$(_job_dirs api)" -eq 1 ]             # never retried

  # THE HONEST LIMIT, asserted rather than claimed: the refusal names the
  # violation, but the orphaned child is not the supervisor's to reap — its
  # job already reached a terminal state, so cancel signals nothing. This is
  # precisely why the contract is a MUST and not a preference.
  run pgrep -f "$TOKEN"
  [ "$status" -eq 0 ]
  pkill -9 -f "$TOKEN" || true
}

# ═══════════════════════════════════════════════════════════════════════════
# 7. stop reads the port back from the registry, not from the environment
# ═══════════════════════════════════════════════════════════════════════════
@test "7: down_all re-exports the RECORDED port with the environment cleared" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop-port.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  run env -u SVC_PORT bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  port="$(_reg '.services.api.port')"
  [ "$port" -gt 0 ]

  # The allocating process is GONE. This one never saw the port, and SVC_PORT
  # is explicitly removed from its environment — the registry is the only way
  # the stop command can learn the number.
  run env -u SVC_PORT bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$TMP/stop-port.log")" = "$port" ]
  [ "$(_reg '.services.api.state')" = "stopped" ]
  _assert_no_orphans

  # Same for status: the port it reports came from the registry.
  run env -u SVC_PORT bash "$DRIVE" "$LIB" aid_service_status api "$EV"
  echo "$output" | jq -e --argjson p "$port" '.port == $p'
}

# ═══════════════════════════════════════════════════════════════════════════
# 8. the registry survives concurrent writers (flock)
# ═══════════════════════════════════════════════════════════════════════════
@test "8: a registry write WAITS for the exclusive lock, and concurrent writers lose nothing" {
  cat > "$TMP/hammer.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
ev="$2"; name="$3"; n="$4"; barrier="${5:-}"
# All writers wait on the same barrier file so they contend from the same
# instant rather than politely queueing behind one another's start-up cost.
if [[ -n "$barrier" ]]; then
  while [[ ! -e "$barrier" ]]; do sleep 0.02; done
fi
for ((i=1; i<=n; i++)); do
  _aid_svc_registry_put "$ev" "$name" "$(jq -nc --argjson i "$i" '{state:"starting", attempt:$i}')"
done
EOS
  chmod +x "$TMP/hammer.sh"

  # ── half 1: the DETERMINISTIC half ──────────────────────────────────────
  # The previous version of this test was a pure race: mutation-tested with
  # `flock` stubbed to a no-op it passed clean about 4 runs in 10, so a
  # regression that removed the locking would have survived CI. The property
  # that actually matters is not statistical — it is that a writer BLOCKS while
  # someone else holds the lock — and that can be asserted head-on by holding
  # the lock from the test and watching the writer not write.
  local FLOCK; FLOCK="$(command -v flock)"
  : >> "$EV/.services.lock"
  ( exec 9>>"$EV/.services.lock"; "$FLOCK" -x 9; sleep 4 ) & local holder=$!
  sleep 0.7                                  # the holder certainly has it now

  ( bash "$TMP/hammer.sh" "$LIB" "$EV" gamma 1 && : > "$TMP/gamma.done" ) & local writer=$!
  sleep 2                                    # ... and the writer certainly wants it

  # Held for 4 s, asked for at 0.7 s, checked at 2.7 s: nothing may have been
  # written yet. Without the lock this file already exists — every time.
  [ ! -e "$TMP/gamma.done" ]
  if [[ -f "$EV/services.json" ]]; then
    [ "$(jq -r '.services.gamma // "absent"' "$EV/services.json")" = "absent" ]
  fi

  wait "$holder"
  wait "$writer"
  [ -e "$TMP/gamma.done" ]                   # and it completes once released
  [ "$(_reg '.services.gamma.attempt')" = "1" ]

  # ── half 2: real contention, no lost updates ────────────────────────────
  local i pids=()
  for i in 1 2 3 4 5 6; do
    bash "$TMP/hammer.sh" "$LIB" "$EV" "w$i" 40 "$TMP/go" & pids+=("$!")
  done
  # a concurrent READER hammering the same file the whole time
  ( for i in $(seq 1 200); do
      [[ -f "$EV/services.json" ]] && { jq -e . "$EV/services.json" >/dev/null || exit 1; }
      sleep 0.05
    done ) & local reader=$!
  : > "$TMP/go"

  for i in "${pids[@]}"; do wait "$i"; done
  wait "$reader"                             # a reader that saw torn JSON fails here

  jq -e . "$EV/services.json" >/dev/null     # still valid JSON
  for i in 1 2 3 4 5 6; do
    [ "$(_reg ".services.w$i.attempt")" = "40" ]
  done
  [ "$(_reg '.services | length')" = "7" ]   # six writers plus gamma, none clobbered
}

# ═══════════════════════════════════════════════════════════════════════════
# 9. no services declared: cheap no-ops that touch nothing
# ═══════════════════════════════════════════════════════════════════════════
@test "9: no services declared means all three functions are cheap no-ops" {
  _yaml <<'EOF'
gates:
  lint:
    command: "true"
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  # nothing created: no registry, no lock, no job root
  [ ! -e "$EV/services.json" ]
  [ ! -e "$EV/.services.lock" ]
  [ ! -e "$EV/service-jobs" ]

  # status is a health QUESTION, so its exit code answers "is it healthy" —
  # `absent` is reported as such and is not a pass.
  run bash "$DRIVE" "$LIB" aid_service_status api "$EV"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.state == "absent"'
  [ ! -e "$EV/services.json" ]

  # an empty `services:` block is the same as no block at all
  _yaml <<'EOF'
services:
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  [ ! -e "$EV/services.json" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 10. idempotent rerun: a healthy service is verified and reused
# ═══════════════════════════════════════════════════════════════════════════
@test "10: a rerun verifies the healthy entry with one probe and starts no second job" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop-port.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  first_job="$(_reg '.services.api.job_id')"
  first_port="$(_reg '.services.api.port')"
  [ "$(_job_dirs api)" -eq 1 ]

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "reused, not restarted" ]]
  [ "$(_reg '.services.api.job_id')" = "$first_job" ]
  [ "$(_reg '.services.api.port')" = "$first_port" ]
  [ "$(_job_dirs api)" -eq 1 ]             # NO second job dir — the AC

  bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 11. the belt-and-braces sweep: a live job the registry does not name
# ═══════════════════════════════════════════════════════════════════════════
@test "11: down_all cancels a live job that has no registry entry" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]

  # An UNRECORDED job in the supervisor's own one-job-one-dir layout — the
  # shape a retry whose teardown never completed would leave behind.
  #
  # CP3: created the way the RUN creates one — spawn ledger first, then the
  # supervisor — because that ordering is now what separates an orphan of ours
  # from a job dir that merely appeared. `_aid_svc_up_one` writes the ledger line
  # before it asks aid-job.sh for anything, so every real retry orphan is
  # vouched for and still reaped here; a fixture that skipped the ledger was
  # indistinguishable from the planted job.json of case 25, and would now be
  # reported rather than signalled. The behaviour under test is unchanged; the
  # fixture is what had stopped being faithful.
  jq -nc --arg s api --arg j ghost-1 --arg at "2026-01-01T00:00:00Z" \
    '{service:$s, job_id:$j, run_id:null, at:$at}' >> "$EV/services.spawned.jsonl"
  orphan_id="$(bash "$JOB_SH" run --jobs-dir "$EV/service-jobs/api" \
      --id "ghost-1" --deadline 300 -- bash "$FIX/idle.sh" "${TOKEN}-ghost")"
  _wait_for 15 '[[ "$(bash "$JOB_SH" status --jobs-dir "$EV/service-jobs/api" --id ghost-1)" == "running" ]]'

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "the registry does not name it" ]]
  run bash "$JOB_SH" status --jobs-dir "$EV/service-jobs/api" --id "$orphan_id"
  [[ "$output" =~ ^(cancelled|terminal_fail|timed_out)$ ]]
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 12. fail-closed: a corrupt registry is refused, never clobbered
# ═══════════════════════════════════════════════════════════════════════════
@test "12: a registry that is not a registry is refused rather than overwritten" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    startup_deadline_seconds: 25
    port_env: SVC_PORT
EOF
  printf 'this is not json at all\n' > "$EV/services.json"

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "refusing to overwrite it" ]]
  [[ "$output" =~ "refusing to start a service the run would have no record of" ]]
  # untouched, and NO job was spawned
  [ "$(cat "$EV/services.json")" = "this is not json at all" ]
  [ ! -d "$EV/service-jobs/api" ] || [ "$(_job_dirs api)" -eq 0 ]
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 13. fail-closed inspection: "I could not look" is not "there is nothing"
# ═══════════════════════════════════════════════════════════════════════════
@test "13: an unreadable execution.yaml refuses with rc 2 instead of assuming no services" {
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$TMP/does-not-exist.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing rather than assuming there are no services" ]]

  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: /bin/true
    startup_deadline_seconds: 5
    port_env: SVC_PORT
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$TMP/no-such-evidence-dir" "$YAML"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "nothing here creates an evidence directory" ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# 14. python3 is a DECLARED dependency, refused by name
# ═══════════════════════════════════════════════════════════════════════════
@test "14: a port_env service without python3 is a named refusal, not a mystery failure" {
  _yaml <<EOF
services:
  api:
    start_cmd: /bin/true
    probe_cmd: /bin/true
    startup_deadline_seconds: 5
    port_env: SVC_PORT
EOF
  # A full PATH with python3 REMOVED — every other tool still present, so the
  # refusal can only be about the named dependency.
  mkdir -p "$TMP/bin"
  local d f
  for d in /usr/local/bin /usr/bin /bin; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
      [[ -x "$f" ]] || continue
      ln -sf "$f" "$TMP/bin/$(basename "$f")" 2>/dev/null || true
    done
  done
  # tools that live outside those dirs on this box must still be reachable
  for f in yq jq flock bats git; do
    p="$(command -v "$f" 2>/dev/null || true)"
    [[ -n "$p" ]] && ln -sf "$p" "$TMP/bin/$f"
  done
  rm -f "$TMP/bin"/python "$TMP/bin"/python3 "$TMP/bin"/python3.*
  run env PATH="$TMP/bin" bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "declares port_env but python3 is not installed" ]]
  [[ "$output" =~ "can only CONNECT" ]]
  [ ! -e "$EV/services.json" ]

  # A service WITHOUT port_env needs no python3 at all.
  _yaml <<'EOF'
services:
  worker:
    start_cmd: /bin/sleep 30
    probe_cmd: /bin/true
    startup_deadline_seconds: 5
EOF
  run env PATH="$TMP/bin" bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  [ "$(_reg '.services.worker.state')" = "healthy" ]

  # THE HONEST LIMIT of down_all's new exit code, asserted rather than dodged:
  # this worker's probe_cmd is `/bin/true`, so it "passes" whether or not
  # anything is serving. down_all reports rc 1 and says so in as many words —
  # a probe that cannot fail cannot prove a teardown succeeded, and the exit
  # code is a statement about the probe, never more than the probe can carry.
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "readiness probe still passes after teardown" ]]
  [[ "$output" =~ "a probe that cannot fail proves nothing about a teardown" ]]
  [ "$(_reg '.services.worker.state')" = "stopped" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 15. the registry is not a command channel when a declaration exists
# ═══════════════════════════════════════════════════════════════════════════
@test "15: a registry stop_cmd that contradicts the declaration is NOT the one that runs" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop-port.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]

  # Anything that can write one JSON file into the run's evidence directory
  # rewrites the recorded stop_cmd into its own command. The registry is
  # authoritative for what this run ALLOCATED; it is not authoritative for what
  # to execute, and a declaration is available here to say so.
  jq --arg c "touch $TMP/OWNED" '.services.api.stop_cmd = $c' \
     "$EV/services.json" > "$TMP/reg.json"
  mv "$TMP/reg.json" "$EV/services.json"

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [ ! -e "$TMP/OWNED" ]                    # the injected command never ran
  [[ "$output" =~ "the DECLARATION wins" ]]
  [ -f "$TMP/stop-port.log" ]              # the declared stop_cmd did
  _assert_no_orphans
}

# ═══════════════════════════════════════════════════════════════════════════
# 16. a registry jobs_dir may never leave this run's evidence directory
# ═══════════════════════════════════════════════════════════════════════════
@test "16: a registry jobs_dir outside the evidence directory cannot cancel another run's job" {
  _need_python3
  local victim="$TMP/victim-run/service-jobs/api"
  mkdir -p "$victim"
  bash "$JOB_SH" run --jobs-dir "$victim" --id victim-1 --deadline 300 \
      -- bash "$FIX/idle.sh" "${TOKEN}-victim" >/dev/null
  _wait_for 15 '[[ "$(bash "$JOB_SH" status --jobs-dir "'"$victim"'" --id victim-1)" == "running" ]]'
  run bash "$JOB_SH" status --jobs-dir "$victim" --id victim-1
  [ "$output" = "running" ]

  # A hand-written registry naming ANOTHER run's job directory. The service IS
  # declared: `aid_service_down_all` refuses outright when the declarations
  # cannot be read at all (P076 Step 16 — see case 31), so reaching the jobs_dir
  # guard requires getting PAST that floor. The declaration is deliberately
  # minimal and names no jobs_dir: the registry is the only place this teardown
  # can learn one, which is exactly the channel under test.
  _yaml <<'EOF'
services:
  api:
    start_cmd: /bin/true
    probe_cmd: /bin/false
EOF
  jq -nc --arg s aid-service-registry/1 --arg jd "$victim" \
    '{schema:$s, updated_at:null,
      services:{api:{service:"api", state:"starting", job_id:"victim-1",
                     jobs_dir:$jd, port:null, port_env:null,
                     probe_cmd:"/bin/false", stop_cmd:null}}}' > "$EV/services.json"

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [[ "$output" =~ "does not resolve inside this run's evidence directory" ]]

  # THE assertion: the other run's job is exactly where it was.
  run bash "$JOB_SH" status --jobs-dir "$victim" --id victim-1
  [ "$output" = "running" ]

  bash "$JOB_SH" cancel --jobs-dir "$victim" --id victim-1 >/dev/null 2>&1 || true
  pkill -9 -f "${TOKEN}-victim" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════
# 17. status fails CLOSED on a registry value it cannot use
# ═══════════════════════════════════════════════════════════════════════════
@test "17: a registry port that is not a number is refused, never reported healthy" {
  jq -nc --arg s aid-service-registry/1 \
    '{schema:$s, updated_at:null,
      services:{api:{service:"api", state:"healthy", job_id:null, jobs_dir:null,
                     port:"not-a-number", port_env:"SVC_PORT",
                     probe_cmd:"/bin/true", stop_cmd:null}}}' > "$EV/services.json"

  # A LOOSE caller on purpose. The suite's usual driver runs under
  # `set -euo pipefail`, and that is precisely what hid this: there a jq crash
  # aborts, while an ordinary sourced caller fell through to `return 0`.
  cat > "$TMP/loose.sh" <<'EOS'
#!/usr/bin/env bash
source "$1"; shift
aid_service_status "$@"
printf 'rc=%s\n' "$?"
EOS
  run bash "$TMP/loose.sh" "$LIB" api "$EV"
  echo "$output"
  [[ "$output" =~ "rc=1" ]]
  [[ ! "$output" =~ \"state\":\"healthy\" ]]
  [[ "$output" =~ "not a port number" ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# 18. the daemonize refusal is bounded by the DECLARED budget, not by 5 s
# ═══════════════════════════════════════════════════════════════════════════
@test "18: a hand-off that binds long after any fixed grace is still named daemonized" {
  _need_python3
  # 9 s after reparenting — far outside the 5 s terminal-grace floor, far
  # inside the declared 25 s startup budget. Nothing about the declaration
  # changed; only how late the child is.
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/daemonize.sh" "\$SVC_PORT" $TOKEN 9
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "start_cmd must remain its job's foreground process" ]]
  [ "$(_reg '.services.api.failure_reason')" = "daemonized_start_cmd" ]
  [ "$(_job_dirs api)" -eq 1 ]             # still never retried

  # Same honest limit as test 6: the orphan is not the supervisor's to reap.
  run pgrep -f "$TOKEN"
  [ "$status" -eq 0 ]
  pkill -9 -f "$TOKEN" || true
}

# ═══════════════════════════════════════════════════════════════════════════
# 19. the export guard denies exactly what the declaration validator denies
# ═══════════════════════════════════════════════════════════════════════════
@test "19: the port export guard refuses every family the declaration validator refuses" {
  cat > "$TMP/exports.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
source "$1"; shift
for v in "$@"; do
  ( _aid_svc_export_port "$v" 41234 2>/dev/null
    printf '%s=%s\n' "$v" "$(printenv "$v" 2>/dev/null || true)" )
done
EOS
  run bash "$TMP/exports.sh" "$LIB" \
      PATH BASH_ENV LD_PRELOAD AID_FOO \
      PYTHONPATH PYTHONSTARTUP PERL5OPT NODE_OPTIONS CLASSPATH JAVA_TOOL_OPTIONS \
      GIT_SSH_COMMAND GIT_EXTERNAL_DIFF GIT_DIR \
      SVC_PORT
  echo "$output"
  # Whole-line matching, deliberately: `PYTHONPATH=41234` CONTAINS the string
  # `PATH=41234`, and a substring assertion here would have passed for the wrong
  # reason (it did, on the first run of this test).
  local v
  for v in PATH BASH_ENV LD_PRELOAD AID_FOO \
           PYTHONPATH PYTHONSTARTUP PERL5OPT NODE_OPTIONS CLASSPATH JAVA_TOOL_OPTIONS \
           GIT_SSH_COMMAND GIT_EXTERNAL_DIFF GIT_DIR; do
    if printf '%s\n' "$output" | grep -Fxq -- "${v}=41234"; then
      echo "EXPORTED: $v" >&2; return 1
    fi
  done
  printf '%s\n' "$output" | grep -Fxq -- "SVC_PORT=41234"   # ordinary name still works

  # ONE definition: this file must not carry an enumeration of its own.
  run grep -c 'PYTHONSTARTUP' "$LIB"
  [ "$output" = "0" ]
  run grep -c 'aid_env_name_denied' "$LIB"
  [ "$output" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 20. a service name is a path component, so it is validated as one
# ═══════════════════════════════════════════════════════════════════════════
@test "20: a service name that is a path traversal creates nothing outside the evidence tree" {
  _yaml <<'EOF'
services:
  "../../../../pwned-svc":
    start_cmd: /bin/true
    probe_cmd: /bin/true
    startup_deadline_seconds: 5
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "invalid service name" ]]
  # `mkdir -p` on the derived jobs_dir would have landed HERE.
  [ ! -e "$REPO/.aid-o/work/pwned-svc" ]
  [ ! -e "$EV/service-jobs" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 21. an unparseable services: block is a refusal, not "nothing to do"
# ═══════════════════════════════════════════════════════════════════════════
@test "21: a services: block that is not a map refuses with rc 2" {
  _yaml <<'EOF'
services:
  - api
  - worker
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "is not a map of service name" ]]
  [ ! -e "$EV/services.json" ]

  # A scalar is the same misunderstanding wearing a different hat.
  _yaml <<'EOF'
services: "api"
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# 22. teardown says so when something is still answering
# ═══════════════════════════════════════════════════════════════════════════
@test "22: down_all reports a service still answering its probe after teardown" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/daemonize.sh" "\$SVC_PORT" $TOKEN 0.5
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 1 ]
  run pgrep -f "$TOKEN"
  [ "$status" -eq 0 ]                      # the orphan really is still serving

  # Teardown is still best-effort and still attempts everything — but "I tried
  # everything" and "everything is down" are different answers, and a caller
  # gating on the exit code is entitled to the difference.
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "readiness probe still passes after teardown" ]]
  pkill -9 -f "$TOKEN" || true
}

# ═══════════════════════════════════════════════════════════════════════════
# 23. a denylisted port_env is a named refusal at up time
# ═══════════════════════════════════════════════════════════════════════════
@test "23: a service declaring a denylisted port_env is refused by name, not started silently" {
  _yaml <<EOF
services:
  api:
    start_cmd: /bin/true
    probe_cmd: /bin/true
    startup_deadline_seconds: 5
    port_env: NODE_OPTIONS
EOF

  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "NODE_OPTIONS" ]]
  [[ "$output" =~ "Refusing to start it with its port variable unset" ]]
  [ ! -e "$EV/service-jobs/api" ] || [ "$(_job_dirs api)" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# CP3 fixes — the owner gate, the vouched sweep, the bounded commands
# ═══════════════════════════════════════════════════════════════════════════

# A process that is provably alive and provably NOT ours to kill: its own
# session and process group (setsid), so a group signal aimed at it cannot also
# hit this test. It is the victim of the planted-job.json repro below.
_start_victim() {
  setsid bash -c 'exec sleep 300' "$1" >/dev/null 2>&1 &
  VICTIM_PID=$!
  local i
  for ((i=0; i<50; i++)); do
    [[ "$(ps -o pgid= -p "$VICTIM_PID" 2>/dev/null | tr -d ' ')" == "$VICTIM_PID" ]] && return 0
    sleep 0.1
  done
  return 1
}

# A claim record naming a live process. `sleep` is a real, live, unrelated pid —
# the point of the gate is that it asks the OPERATING SYSTEM, not a state string.
_plant_owner() {
  local pid="$1" st boot host
  st="$(awk '{ n=split($0, a, ") "); print a[n] }' "/proc/${pid}/stat" 2>/dev/null | awk '{print $20}')"
  boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  host="$(hostname 2>/dev/null || true)"
  jq -n --argjson pid "$pid" --arg st "$st" --arg b "$boot" --arg h "$host" \
    '{schema:"aid.services.owner/1", pid:$pid, starttime:$st, boot_id:$b,
      host:$h, run_id:"R-OTHER", claimed_at:"2026-01-01T00:00:00Z"}' \
    > "$EV/services.owner.json"
}

@test "24: down_all REFUSES while a different, provably live process holds the ownership claim" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$TMP/stop.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]
  local port; port="$(_reg '.services.api.port')"

  # A live claim held by somebody else. This is the evidence the FSM's sweep
  # never read: a live runner mid-foreground-gate leaves exactly this behind.
  sleep 300 & OWNERPID=$!
  _plant_owner "$OWNERPID"

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "REFUSING to tear down" ]]
  [[ "$output" =~ "R-OTHER" ]]

  # NOTHING happened: the service still serves, its state is untouched, and the
  # stop_cmd never ran. That is the whole point — two gates that would have
  # passed were being reported failed against infrastructure the sweep removed.
  [ "$(_reg '.services.api.state')" = "healthy" ]
  bash "$FIX/probe.sh" "$port"
  [ ! -f "$TMP/stop.log" ]

  # The owner dies → the claim is provably stale → the same call now sweeps.
  kill -9 "$OWNERPID" 2>/dev/null || true
  wait "$OWNERPID" 2>/dev/null || true
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(_reg '.services.api.state')" = "stopped" ]
  _assert_no_orphans
}

@test "25: the orphan sweep will not signal a job this run cannot vouch for" {
  _start_victim "$TOKEN-victim"

  # A perfectly well-formed job.json carrying the victim's REAL pid and pgid —
  # copied out of /proc, so every self-consistency check aid-job.sh can make
  # passes. Validation answers "is this well-formed"; it cannot answer "did we
  # write it".
  mkdir -p "$EV/service-jobs/api/planted"
  jq -n --argjson pid "$VICTIM_PID" --argjson pgid "$VICTIM_PID" \
     --arg st "$(awk '{ n=split($0, a, ") "); print a[n] }' "/proc/${VICTIM_PID}/stat" | awk '{print $20}')" \
    '{schema:"aid-job/1", id:"planted", state:"running", pid:$pid, pgid:$pgid,
      proc_starttime:$st, cookie:"x", started_at:"2026-01-01T00:00:00Z",
      started_epoch:1767225600, deadline_seconds:0, label:"service:api",
      command_fingerprint:"x", start_head:"none", start_tree:"none", repo:null}' \
    > "$EV/service-jobs/api/planted/job.json"

  _yaml <<EOF
services:
  api:
    start_cmd: /bin/true
    probe_cmd: /bin/false
EOF

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "NOTHING this run wrote vouches for it" ]]
  [[ "$output" =~ "REPORTED, not signalled" ]]
  # The operator gets the exact command, because "we will not do this for you"
  # is only useful with "here is how, if it is yours".
  [[ "$output" =~ "cancel --jobs-dir" ]]

  # THE assertion: an unrelated process group was not TERMed by a plain teardown.
  kill -0 "$VICTIM_PID"
  kill -9 -"$VICTIM_PID" 2>/dev/null || true
}

@test "26: a job this run DID spawn is still swept, on the strength of the spawn ledger" {
  _need_python3
  _yaml <<EOF
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" 0 $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 120
    port_env: SVC_PORT
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]

  # The ledger vouches for the id BEFORE the spawn — eagerly, like the registry's
  # phase 1 — so there is no window in which a job we created is unvouchable.
  local jid; jid="$(_reg '.services.api.job_id')"
  run jq -r --arg j "$jid" 'select(.job_id == $j) | .service' "$EV/services.spawned.jsonl"
  [ "$output" = "api" ]

  # Erase the registry's memory of the job id — the ledger alone must still
  # authorise the cancel, which is the superseded-retry orphan case.
  jq '.services.api.job_id = null' "$EV/services.json" > "$EV/services.json.t"
  mv "$EV/services.json.t" "$EV/services.json"

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [[ "$output" =~ "this run vouches for it" ]]
  _assert_no_orphans
}

@test "27: startup_deadline_seconds bounds a probe_cmd that never returns" {
  # THE repro: the loop probed and only THEN looked at the clock, so a blocking
  # probe was never interrupted — deadline 3 s, probe `sleep 600`, still running
  # at 25 s. A deadline a command can hold open is not a deadline.
  _yaml <<EOF
services:
  api:
    start_cmd: sleep 120
    probe_cmd: sleep 600
    startup_deadline_seconds: 3
EOF
  local t0 t1
  t0="$(date +%s)"
  run timeout 60 bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  t1="$(date +%s)"
  echo "$output"
  echo "elapsed=$(( t1 - t0 ))s"
  [ "$status" -eq 1 ]                       # a named failure, not a hang
  [ "$(( t1 - t0 ))" -lt 30 ]               # bounded — it used to run past this
  [[ "$output" =~ "startup_deadline_seconds=3" ]]
  [ "$(_reg '.services.api.state')" = "timed_out" ]
}

@test "28: a stop_cmd that never returns cannot hang the teardown" {
  _yaml <<EOF
services:
  api:
    start_cmd: sleep 120
    probe_cmd: /bin/true
    stop_cmd: sleep 600
    startup_deadline_seconds: 5
EOF
  run bash "$DRIVE" "$LIB" aid_service_up_all "$EV" "$YAML"
  [ "$status" -eq 0 ]

  local t0 t1
  t0="$(date +%s)"
  AID_SERVICE_STOP_TIMEOUT_SEC=3 run timeout 60 bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  t1="$(date +%s)"
  echo "elapsed=$(( t1 - t0 ))s"
  [ "$(( t1 - t0 ))" -lt 45 ]
}

@test "29: down_all refuses rather than running a registry-recorded stop_cmd with no yq" {
  # `up_all` has refused a missing yq since it shipped. `down_all` had not, so a
  # host without yq dropped it onto the UNRECONCILED branch — where the command
  # that runs is a string read out of the subagent-writable evidence directory.
  mkdir -p "$EV"
  jq -n '{schema:"aid-service-registry/1", updated_at:null,
          services:{api:{service:"api", state:"healthy", job_id:null,
                         stop_cmd:"touch /tmp/aid-should-never-run", port:null}}}' \
    > "$EV/services.json"
  _yaml <<EOF
services: {}
EOF
  local stub="$TMP/nobin"; mkdir -p "$stub"
  run env PATH="$stub:/usr/bin:/bin" bash -c '
    command -v yq >/dev/null 2>&1 && exit 99
    source "$1"; aid_service_down_all "$2" "$3"' _ "$LIB" "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "yq is not available" ]]
  [[ "$output" =~ "UNRECONCILED" ]]
}

# The constraint this EPIC works under, made grep-guarded rather than promised:
# aid-job.sh is the ONE process owner, and no session/process-group arithmetic
# may appear anywhere else. `timeout` bounds a foreground command; it owns
# nothing, records nothing and is not a supervisor.
@test "30: aid-service.sh still contains no process-group management of its own" {
  # CODE only — this file discusses setsid at length in its header, and a guard
  # that a comment can turn red is a guard nobody keeps.
  run bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -nE "\b(setsid|pkill|nohup|disown|setpgid)\b|kill[[:space:]]+-[A-Za-z0-9]+[[:space:]]+-"' _ "$LIB"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
}

# ═══════════════════════════════════════════════════════════════════════════
# 31. the OTHER door into the unreconciled branch (P076 Step 16, CP3 MEDIUM)
# ═══════════════════════════════════════════════════════════════════════════
@test "31: down_all refuses rather than running a registry-recorded stop_cmd with the execution.yaml absent" {
  # Case 29 closed one door: no yq means `_aid_svc_declares` cannot answer, so
  # every service fell onto the UNRECONCILED branch and the registry's RECORDED
  # stop_cmd — a string from a file inside the subagent-writable evidence
  # directory — is what ran. The preflight was the right shape guarding ONE of
  # the two doors into that branch. `_aid_svc_declares` also cannot answer when
  # the declarations themselves are unreadable, and that door was open: with yq
  # present and execution.yaml simply ABSENT, the recorded command executed.
  #
  # The proof is a side effect, not a message: the recorded stop_cmd creates a
  # file, and the assertion is that the file does not exist.
  mkdir -p "$EV"
  local canary="$TMP/RECORDED_STOP_CMD_RAN"
  jq -n --arg c "touch '$canary'" \
     '{schema:"aid-service-registry/1", updated_at:null,
       services:{api:{service:"api", state:"healthy", job_id:null,
                      stop_cmd:$c, port:null}}}' > "$EV/services.json"

  local missing="$TMP/does-not-exist/execution.yaml"
  [ ! -f "$missing" ]

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$missing"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "cannot be read" ]]
  [[ "$output" =~ "UNRECONCILED" ]]

  # NOTHING EXECUTED, and nothing was written: the registry entry is untouched,
  # exactly as it is on the no-yq path.
  [ ! -e "$canary" ]
  [ "$(_reg '.services.api.state')" = "healthy" ]

  # Same door, second latch: a yaml that EXISTS but cannot be read is equally
  # unable to answer, and is refused the same way. (Skipped for a caller that
  # can read anything — root's `test -r` is always true.)
  _yaml <<'EOF'
services: {}
EOF
  chmod 000 "$YAML"
  if [ -r "$YAML" ]; then
    chmod 644 "$YAML"
    skip "this user can read a mode-000 file (running as root), so 'unreadable' cannot be constructed here"
  fi
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  chmod 644 "$YAML"
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" =~ "cannot be read" ]]
  [ ! -e "$canary" ]

  # AND THE FLOOR IS NOT A WALL: with the declarations readable the teardown
  # proceeds — and, because the declaration does not name `api`, it still
  # refuses the RECORDED stop_cmd rather than running it. The canary never runs
  # on any path.
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV" "$YAML"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "does NOT declare this service" ]]
  [ ! -e "$canary" ]
  [ "$(_reg '.services.api.state')" = "stopped" ]
}
