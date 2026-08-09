#!/usr/bin/env bats
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
  # waits to be REPARENTED (proof the parent is gone) plus half a second (time
  # for the supervisor to record the terminal result) before it binds. So there
  # is no instant at which the probe can succeed while the job is still running
  # — the only way the lib can reach the right verdict is by continuing to probe
  # AFTER the job has ended.
  #   $1 port  $2 token
  cat > "$FIX/daemonize.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import os,socket,sys,time
if os.fork() > 0:
    sys.exit(0)                      # start_cmd returns AT ONCE
ppid = os.getppid()
while os.getppid() == ppid:          # ... wait until we are reparented
    time.sleep(0.05)
time.sleep(0.5)                      # ... and the job record says terminal
s = socket.socket()
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
while True:
    c, _ = s.accept(); c.close()' "$1" "$2"
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

  bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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
    startup_deadline_seconds: 20
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

  bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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
    startup_deadline_seconds: 40
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
  run env -u SVC_PORT bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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
@test "8: concurrent registry writers never corrupt or lose an entry (flock)" {
  cat > "$TMP/hammer.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
ev="$2"; name="$3"; n="$4"
for ((i=1; i<=n; i++)); do
  _aid_svc_registry_put "$ev" "$name" "$(jq -nc --argjson i "$i" '{state:"starting", attempt:$i}')"
done
EOS
  chmod +x "$TMP/hammer.sh"

  bash "$TMP/hammer.sh" "$LIB" "$EV" alpha 30 & a=$!
  bash "$TMP/hammer.sh" "$LIB" "$EV" beta  30 & b=$!
  # a concurrent READER hammering the same file the whole time
  ( for i in $(seq 1 60); do
      [[ -f "$EV/services.json" ]] && { jq -e . "$EV/services.json" >/dev/null || exit 1; }
      sleep 0.05
    done ) & c=$!

  wait "$a"; wait "$b"
  wait "$c"                                # a reader that saw torn JSON fails here

  jq -e . "$EV/services.json" >/dev/null    # still valid JSON
  [ "$(_reg '.services.alpha.attempt')" = "30" ]
  [ "$(_reg '.services.beta.attempt')"  = "30" ]
  [ "$(_reg '.services | length')" = "2" ]  # neither writer clobbered the other
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
  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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

  bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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
  orphan_id="$(bash "$JOB_SH" run --jobs-dir "$EV/service-jobs/api" \
      --id "ghost-1" --deadline 300 -- bash "$FIX/idle.sh" "${TOKEN}-ghost")"
  _wait_for 15 '[[ "$(bash "$JOB_SH" status --jobs-dir "$EV/service-jobs/api" --id ghost-1)" == "running" ]]'

  run bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
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
  bash "$DRIVE" "$LIB" aid_service_down_all "$EV"
}
