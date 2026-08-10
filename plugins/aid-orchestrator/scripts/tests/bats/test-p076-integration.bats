#!/usr/bin/env bats
# test-p076-integration.bats — P076 Step 16: the plan's acceptance instrument.
#
# Every other suite in this plan proves one mechanism. This one proves the
# CHAIN: that the pieces built across three EPICs hold together end to end,
# under a real SIGKILL, with real processes, on a real repository.
#
#   PHASE 1  KILL IT      — run-all brings a declared service up and hands a
#                           background gate to the supervisor; the controller is
#                           SIGKILLed mid-poll. The supervised job survives, the
#                           continuation artifact is on disk and schema-valid,
#                           and `/aid-status`'s RENDER RECIPES derive
#                           `awaiting_host_resume` from those two facts —
#                           nothing stored it, and the writer refuses to.
#   PHASE 2  RESUME IT    — `aid-fsm.sh resume` (driven from inside a linked
#                           worktree, the edge case the plan names) claims the
#                           artifact EXACTLY ONCE, collects the finished job and
#                           checkpoints the row. The rerun assembles that row,
#                           runs the remaining gate, and takes the service down.
#                           NO RE-EXECUTION is proved by a side-effect counter —
#                           the gate command appends one line per execution and
#                           the file has exactly one line at the end.
#   PHASE 3  EXHAUST IT   — a forced GATE_TIMEOUT drives the ladder to budget
#                           exhaustion; a STUBBED adjudication returns
#                           `escalate`; the terminus lands `blocked_for_pm` on
#                           the map, and leaving ESCALATION still requires the
#                           decision field.
#   PHASE 4  GOLDEN       — the same runner over a foreground-only config with
#                           no services is byte-identical, after normalizing the
#                           volatile fields, to the COMMITTED pre-P076 reference.
#   REGISTRY              — every mechanism this plan shipped has a row in
#                           defaults/enforcement-registry.yaml (grep-asserted).
#                           UN-SKIPPABLE: it is pure grep and `yq` over a file in
#                           this repository, so no environment can excuse it.
#
# SKIPS, AND WHERE THEY MAY LIVE. `jq` and `yq` are hard dependencies of the
# shipped runner and their absence FAILS setup(); the process facilities
# (`setsid`, `flock`, `timeout`, `python3`, `/proc`) skip only the three phases
# that genuinely drive processes, through `_require_process_facilities`. They
# used to sit in setup(), where one absent binary skipped all four tests —
# including the registry check, which needs none of them — and bats reports a
# skip as `ok`. The two closure suites of this EPIC were built un-skippable after
# that failure mode bit once; this suite is now as un-skippable as its
# dependencies allow.
#
# Codex is never reached: phase 3 redefines `_run_codex_isolated` after sourcing
# the adjudication lib, exactly as test-recovery-adjudicate.bats does.
#
# FIXTURE CONSTRUCTION reuses the idioms of the suites it integrates
# (test-gate-background, test-resume-command, test-service-lifecycle,
# test-recovery-ladder): a real git repo, a python3 listener, a connect-only
# probe, per-test argv TOKENs so every orphan sweep is a real `ps` sweep.
#
# EVERY assertion names its phase and the artifact under test (`_fail`), because
# a red line in an integration suite is worthless if it does not say which link
# of the chain broke.
#
# HYGIENE: the status render runs in a child shell — invoked with `3>&-`.
# After any edit verify:
#   bats --tap test-p076-integration.bats </dev/null | grep -cE '^(ok|not ok)'  # == 4

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  # `/aid-status` is a prose-driven surface: the recipes in this file ARE the
  # implementation phase 1 exercises, and they resolve the plugin through this.
  AID_PLUGIN_PATH="$PLUGIN_ROOT"
  export AID_PLUGIN_PATH
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  JOB_SH="$PLUGIN_ROOT/scripts/aid-job.sh"
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  LADDER_LIB="$PLUGIN_ROOT/scripts/lib/aid-recovery-ladder.sh"
  ADJ_LIB="$PLUGIN_ROOT/scripts/lib/aid-recovery-adjudicate.sh"
  STATUS_DOC="$PLUGIN_ROOT/commands/aid-status.md"
  REGISTRY="$PLUGIN_ROOT/defaults/enforcement-registry.yaml"
  GOLDEN="$PLUGIN_ROOT/scripts/tests/fixtures/p076/golden-gates-report.json"
  export RUN_GATES JOB_SH FSM LADDER_LIB ADJ_LIB STATUS_DOC REGISTRY GOLDEN

  # HARD DEPENDENCIES — a FAILURE, never a skip. `jq` and `yq` are hard deps of
  # the shipped runner itself, not environment quirks: a checkout that cannot
  # run them cannot run AID, so reporting green here would be a lie about the
  # whole plan. Seven skips used to sit in this function, which meant ONE absent
  # binary skipped all four tests — bats prints a skip as `ok`, the file exits 0,
  # and the plan's own acceptance instrument reported success while checking
  # nothing. That is the exact silent-skip failure mode this plan was written to
  # eliminate, and the two closure suites were deliberately built un-skippable
  # after it bit once already. This suite now inherits that property.
  command -v jq >/dev/null 2>&1 \
    || { echo "FATAL: jq is not available — it is a hard dependency of the shipped gate runner, not an environment quirk; a skip here would report this plan's acceptance instrument as green while checking nothing" >&2; return 1; }
  command -v yq >/dev/null 2>&1 \
    || { echo "FATAL: yq is not available — the service declarations and the status render both read it; see the note on jq above" >&2; return 1; }

  WORK="$(mktemp -d)"; export WORK
  PROJ="$WORK/project"; export PROJ
  FIX="$WORK/fixtures"; export FIX
  mkdir -p "$PROJ" "$FIX"

  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  # Seconds instead of minutes: the shipped cadence is 5 s poll / 60 s
  # heartbeat, and these seams exist so a test can drive a complete cycle.
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1
  export AID_RESUME_POLL_SEC=0

  EPIC="E-076-9_9"; export EPIC
  EVID=".aid-o/work/evidence/${EPIC}/R-1"; export EVID
  ABS_EVID="$PROJ/$EVID"; export ABS_EVID
  ARTIFACT="$ABS_EVID/auto_resume_required.json"; export ARTIFACT
  REPORT="$ABS_EVID/gates/gates_report.json"; export REPORT
  TIMELINE="$ABS_EVID/timeline.jsonl"; export TIMELINE
  JOBS="$ABS_EVID/jobs"; export JOBS
  ROWS="$ABS_EVID/gates_rows"; export ROWS
  REG="$ABS_EVID/services.json"; export REG
  MAP="$PROJ/.aid-o/work/active-runs.json"; export MAP
  # THE side-effect counter: one line per EXECUTION of the background gate's
  # command. Duration proves nothing (a fast machine and a replayed result look
  # alike); a counter the command itself increments cannot be faked by a replay.
  MARKER="$WORK/executions.txt"; export MARKER

  # Unique argv markers, so every orphan sweep below is a real `ps` sweep for
  # THIS test's processes and resolves to exact pids.
  TOKEN="aidp076int-$$-${RANDOM}-${BATS_TEST_NUMBER}"; export TOKEN

  _write_fixtures
}

# _require_process_facilities — the PROCESS dependencies, named and skipped in
# the phases that actually use them, never in setup().
#
# These five are genuine environment facilities rather than AID dependencies:
# `setsid` is how a supervised job outlives its caller, `/proc` is how this
# suite identifies a runner by its CWD rather than by a pattern match, `python3`
# is how the services half allocates a real port by BIND probe, and `flock` and
# `timeout(1)` bound the ladder's critical section and every probe. A machine
# without them cannot run the crash-survival phases at all — but it can still
# run the registry assertion, which is pure grep and `yq` over a YAML file in
# this repository and needs no process facility whatsoever. Keeping these skips
# in setup() meant a missing `setsid` silently skipped that check too.
_require_process_facilities() {
  command -v flock   >/dev/null 2>&1 || skip "flock is not available"
  command -v setsid  >/dev/null 2>&1 || skip "setsid is not available — a supervised job cannot be detached into its own session, so the crash-survival phases cannot be run"
  command -v python3 >/dev/null 2>&1 || skip "python3 is not available (a declared dependency of the services feature)"
  command -v timeout >/dev/null 2>&1 || skip "timeout(1) is not available"
  [ -d /proc ] || skip "/proc is not available — this suite identifies runners and services by real process facts, never by a pattern match"
}

# teardown — nothing this suite starts may outlive it, and everything is killed
# BY EXACT PID: a `pkill -f` pattern sweep in a sibling suite killed a live run
# earlier in this plan, so pids are resolved first (from job records, from
# /proc/<pid>/cwd, from the token) and signalled individually.
teardown() {
  local d pgid p
  # 1. the supervisor's own process groups — gate jobs and service jobs alike
  for d in "$JOBS"/*/ "$ABS_EVID"/service-jobs/*/*/ "$WORK"/*/.aid-o/work/evidence/*/*/jobs/*/; do
    [[ -f "${d}job.json" ]] || continue
    pgid="$(jq -r '.pgid // empty' "${d}job.json" 2>/dev/null || true)"
    [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
  done
  # 2. any runner still polling in this test's project
  kill_runner
  # 3. anything still carrying this test's argv token, by exact pid.
  # THE GUARD IS LOAD-BEARING: bats runs teardown() even when setup() died
  # BEFORE line ~125 set TOKEN, and `pgrep -f ""` matches every process on the
  # box (measured: 671) — which this loop would then feed to `kill -KILL` one
  # exact pid at a time. A missing `jq` in setup() is enough to reach it.
  if [[ -n "${TOKEN:-}" ]]; then
    for p in $(pgrep -f "$TOKEN" 2>/dev/null || true); do
      kill -KILL "$p" 2>/dev/null || true
    done
  fi
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# ── failure vocabulary ──────────────────────────────────────────────────────
# _fail <phase> <artifact> <what should have been true>
_fail() {
  echo "PHASE $1 FAILED — artifact under test: $2 — $3" >&2
  return 1
}

# ── fixtures ────────────────────────────────────────────────────────────────
_write_fixtures() {
  # THE service: an ordinary server bind, listening forever. $1 port $2 token.
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

  # THE probe: connect-only — it asks "is somebody serving", never "may I bind".
  cat > "$FIX/probe.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
exec python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1.0).close()' "$1"
EOS

  # stop_cmd: one line per teardown, so "released" is a count, not a belief.
  cat > "$FIX/stop.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "${SVC_PORT:-ENV_WAS_EMPTY}" >> "$1"
EOS

  # THE background gate: a controlled sleep-loop, deterministic by construction
  # so a fast CI cannot make it finish before the SIGKILL lands. It appends ONE
  # line to the execution counter before it starts sleeping.
  #   $1 counter  $2 seconds  $3 token
  cat > "$FIX/slow-gate.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf 'ran\n' >> "$1"
exec python3 -c 'import sys,time
end = time.time() + float(sys.argv[1])
while time.time() < end:
    time.sleep(0.1)
print("bg-done")' "$2" "$3"
EOS

  # A gate that PROVES it saw the service: it reads the per-run port out of the
  # run registry (the only place it is published) and connects.
  #   $1 marker  $2 registry  $3 service name
  cat > "$FIX/gate-touch.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
port="$(jq -r --arg n "$3" '.services[$n].port' "$2")"
python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2.0).close()' "$port"
printf '%s\n' "$port" >> "$1"
EOS

  chmod +x "$FIX"/*.sh
}

init_project() {
  mkdir -p "$ABS_EVID/gates" "$PROJ/.aid-o/work/runs" "$PROJ/.aid-o/config"
  printf 'p076 integration fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  (
    cd "$PROJ"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email p076@example.com
    git config user.name P076
    git add README.md .gitignore
    git commit -qm "p076 integration fixture base"
  )
}

# The map entry `aid-fsm.sh init` would have written. `updated_at` is old, which
# is what makes the stall derivation in phase 1 deterministic alongside the
# threshold override — a live controller writes progress, a dead one cannot.
_seed_map() {
  mkdir -p "$PROJ/.aid-o/work"
  jq -n --arg e "$EPIC" \
    '{($e): {state_file: (".aid-o/work/evidence/" + $e + "/R-1/fsm-state.yaml"),
      run_id: "R-1", state: "GATES", branch: ("task/" + $e + "/main"),
      plan_id: "P076", governs_main: false,
      updated_at: "2026-01-01T00:00:00Z",
      auto_controller: "active", resume_artifact: null}}' > "$MAP"
  printf 'epic_id: %s\nrun_id: R-1\nstate: GATES\nmode: auto\n' "$EPIC" \
    > "$ABS_EVID/fsm-state.yaml"
}

# THE execution.yaml phases 1 and 2 share: one declared service, one background
# gate (SIGKILLed mid-poll), one foreground gate that needs the service and has
# not run yet when the controller dies.
_write_exec_yaml() {
  cat > "$PROJ/exec.yaml" <<YAML
services:
  api:
    start_cmd: bash "$FIX/listen.sh" "\$SVC_PORT" $TOKEN
    probe_cmd: bash "$FIX/probe.sh" "\$SVC_PORT"
    stop_cmd: bash "$FIX/stop.sh" "$WORK/stop.log"
    startup_deadline_seconds: 25
    max_lifetime_seconds: 300
    port_env: SVC_PORT
gates:
  slow_bg:
    command: bash "$FIX/slow-gate.sh" "$MARKER" 12 $TOKEN
    required: true
    timeout_seconds: 180
    run_mode: background
  after_fg:
    command: bash "$FIX/gate-touch.sh" "$WORK/after.marker" "$EVID/services.json" api
    required: true
    timeout_seconds: 30
    needs_services: [api]
YAML
}

# ── driving the runner ──────────────────────────────────────────────────────
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
# child of it depending on whether bash exec-optimises the subshell, so killing
# only the pid bash reports leaves the real runner polling — and a live runner
# deletes the continuation artifact out from under the phase that is asserting
# about it. The runner is therefore identified by what it provably IS: an
# aid-run-gates.sh run-all process whose CWD is THIS test's project. Every pid
# is resolved first and signalled individually.
_runner_pids() {
  local p want
  want="$(readlink -f "${PROJ:-/nonexistent}" 2>/dev/null || echo "${PROJ:-/nonexistent}")"
  for p in $(pgrep -f "aid-run-gates.sh run-all" 2>/dev/null || true); do
    [[ "$(readlink -f "/proc/$p/cwd" 2>/dev/null || true)" == "$want" ]] && echo "$p"
  done
  return 0
}

# A killed process lingers as a zombie until reaped, and a zombie is not a
# runner — only a live (non-Z) process counts.
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

_reg_field() { jq -r "${1}" "$REG" 2>/dev/null || true; }

# THE orphan sweep — a real `ps` over the whole process table for this test's
# service/gate token.
_assert_no_orphans() { # _assert_no_orphans <phase>
  local found
  found="$(ps -eo pid,ppid,args 2>/dev/null | grep -F "$TOKEN" | grep -v grep || true)"
  if [[ -n "$found" ]]; then
    echo "$found" >&2
    _fail "$1" "the process table" "no process carrying this run's token may survive its run — the ones above did"
    return 1
  fi
  return 0
}

_probe_port() {
  python3 -c 'import socket,sys
socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1.0).close()' "$1" 2>/dev/null
}

claim_files() { ls -1 "$ARTIFACT".claimed-* 2>/dev/null || true; }

# ── the /aid-status render, extracted from the doc that IS its implementation ─
# `/aid-status` has no script by design: the ```bash fences in commands/
# aid-status.md whose first line is `# recipe: <name>` are what an agent
# executes. Phase 1 must prove `awaiting_host_resume` is DERIVED, and the only
# honest way to prove that is to run the derivation an operator actually runs.
_recipes() {
  awk '
    /^# recipe: / { inblk = 1; print; next }
    inblk && /^```$/ { inblk = 0; next }
    inblk { print }
  ' "$STATUS_DOC"
}

# _status_row <epic> <state> — ONE rendered row (plus its note lines) for that
# epic, produced by the doc's own controller_facts + epic_row.
#
# AID_ACTIVE_RUN_STALL_SEC is pinned to 0 IN THE CHILD ONLY: the stall half of
# the derivation is "no liveness signal within the threshold", and a test that
# waited 2100 s to prove it would be a test nobody runs. Zero makes "the
# controller is dead" true immediately and is exported because `stalled_json`
# asks aid-fsm.sh, in a further child, for the one shared derivation.
#
# A missing function is turned into a NAMED rc 1 before it is called: with fd 3
# closed (mandatory — a recipe child inheriting it breaks bats' reporter and the
# whole file's results vanish) a bare 127 would lose its own red.
_status_row() {
  local body; body="$(_recipes)"
  run bash -c "cd '$PROJ' && export AID_ACTIVE_RUN_STALL_SEC=0 && $body
declare -F controller_facts >/dev/null || { echo 'MISSING: controller_facts is not defined by aid-status.md' >&2; exit 1; }
declare -F epic_row        >/dev/null || { echo 'MISSING: epic_row is not defined by aid-status.md' >&2; exit 1; }
_f=\"\$(controller_facts)\"
epic_row '    ' '$1' '$2' R-1 'task/$1/main' '' \"\$_f\"" 3>&-
}

# ── the golden fixture + normalizer ─────────────────────────────────────────
# Copied VERBATIM from the capture procedure that produced
# fixtures/p076/golden-gates-report.json against the PRE-Step-2 runner, and
# shared byte-for-byte with test-gate-background.bats case 6. If either drifts,
# phase 4 fails — which is the whole point of a golden.
golden_build_fixture() {
  local root="$1"
  mkdir -p "$root/.aid-o/work/evidence/E-P076/R-1/gates"
  git -C "$root" init -q
  git -C "$root" config user.email golden@example.com
  git -C "$root" config user.name Golden
  printf 'golden fixture\n' > "$root/README.md"
  printf '.aid-o/\n' > "$root/.gitignore"
  git -C "$root" add README.md .gitignore
  git -C "$root" commit -qm "golden fixture base"
  cat > "$root/exec.yaml" <<'YAML'
gates:
  alpha:
    command: "echo alpha-ok"
    required: true
    timeout_seconds: 30
  beta:
    command: "printf 'beta-ok'"
    required: false
    timeout_seconds: 30
  gamma:
    command: "echo gamma-broke >&2; exit 1"
    required: false
    timeout_seconds: 30
  delta_nocmd:
    required: false
YAML
}

# Volatile fields, and why each one is volatile:
#   completed_at / _generated_at    — wall-clock stamps
#   revision.head_sha               — the fixture repo's fresh commit sha
#   gates[].duration_ms             — measured wall clock
#   gates[].runtime_baseline.p95_ms — derived from that same wall clock
#   _command_log[].duration_ms      — measured wall clock
# Everything else — results, exit codes, outputs, attempts, ordering, the whole
# schema — is compared.
golden_normalize() {
  jq -S '
      .completed_at = "NORMALIZED"
    | ._generated_at = "NORMALIZED"
    | .revision.head_sha = "NORMALIZED"
    | .gates |= with_entries(
        if (.value | type) == "object" then
          .value |= (
              (if has("duration_ms") then .duration_ms = 0 else . end)
            | (if (.runtime_baseline | type) == "object"
               then .runtime_baseline.p95_ms = 0 else . end)
          )
        else . end)
    | ._command_log |= map(.duration_ms = 0)
  ' "$1"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 1 + 2 — one continuous story, because that is what it has to prove:
# the state phase 2 resumes from is the state phase 1's crash produced, not a
# state a test constructed.
# ═══════════════════════════════════════════════════════════════════════════

@test "phases 1-2: a SIGKILLed controller derives awaiting_host_resume, resume claims it once, and the rerun finishes the run without re-executing anything" {
  _require_process_facilities
  init_project
  _seed_map
  _write_exec_yaml

  # ── PHASE 1 ───────────────────────────────────────────────────────────────
  start_gates_bg
  _wait_for 60 '[[ -f "$JOBS/slow_bg-attempt-1/job.json" ]] && jq -e ".pid != null" "$JOBS/slow_bg-attempt-1/job.json" >/dev/null 2>&1' \
    || _fail 1 "$JOBS/slow_bg-attempt-1/job.json" "the supervisor never recorded a pid for the background gate"
  _wait_for 60 '[[ "$(jq -r ".job_id // \"\"" "$ARTIFACT" 2>/dev/null || true)" == "slow_bg-attempt-1" ]]' \
    || _fail 1 "$ARTIFACT" "the continuation pointer was not written EAGERLY, before the job was handed off"

  # The service is up and answering on the port this run allocated: a declared
  # service LIVES with its run.
  [ -f "$REG" ] || _fail 1 "$REG" "no service registry was written for a run that declares a service"
  [ "$(_reg_field '.services.api.state')" = "healthy" ] \
    || _fail 1 "$REG" "the declared service is not healthy while its run is in flight"
  local port; port="$(_reg_field '.services.api.port')"
  [[ "$port" =~ ^[1-9][0-9]*$ ]] \
    || _fail 1 "$REG" "no per-run port was recorded for the declared service"
  _probe_port "$port" \
    || _fail 1 "$REG" "the recorded per-run port answers nothing — the service is not actually serving"

  # THE CRASH: SIGKILL, no trap, no cleanup, every process that IS the runner.
  kill_runner
  _wait_for 10 '! _runner_alive' \
    || _fail 1 "the process table" "a runner is still polling after the SIGKILL — the fixture is not the one it claims to be"

  # (1a) The supervised job outlived its caller.
  run bash "$JOB_SH" status --jobs-dir "$JOBS" --id slow_bg-attempt-1
  [ "$output" = "running" ] \
    || _fail 1 "$JOBS/slow_bg-attempt-1" "the supervised job did not survive the death of the controller that started it (state: $output)"

  # (1b) The continuation artifact is on disk and SCHEMA-VALID: every field the
  #      chain promises, and a safe_next_action with no unresolved placeholder.
  [ -f "$ARTIFACT" ] || _fail 1 "$ARTIFACT" "the continuation artifact is missing after the crash"
  run jq -e '
       .schema == "aid-auto-resume/1"
   and (.epic_id | type == "string" and length > 0)
   and (.run_id  | type == "string" and length > 0)
   and (.job_id  | type == "string" and length > 0)
   and (.jobs_dir | type == "string" and length > 0)
   and (.gate == "slow_bg")
   and (.command_fingerprint | type == "string" and length > 0)
   and (.expected_terminal_states | type == "array" and length == 4)
   and (.safe_next_action | type == "string" and length > 0 and (contains("<") | not))
   and (.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' "$ARTIFACT"
  [ "$status" -eq 0 ] \
    || _fail 1 "$ARTIFACT" "the continuation artifact is not schema-valid: $(cat "$ARTIFACT")"

  # (1c) THE DERIVED STATE, THROUGH THE RENDER. Nothing stored
  #      `awaiting_host_resume` — the writer refuses the value outright — so the
  #      only way to prove the rule is to run the derivation an operator runs.
  run grep -c awaiting_host_resume "$MAP"
  [ "$output" = "0" ] \
    || _fail 1 "$MAP" "the string awaiting_host_resume appears in the stored map; it is a DERIVED state and must be stored nowhere"
  run bash -c "cd '$PROJ' && bash '$FSM' active-runs set '$EPIC' auto_controller awaiting_host_resume"
  [ "$status" -ne 0 ] \
    || _fail 1 "$MAP" "the map writer ACCEPTED awaiting_host_resume — a dying controller cannot write its own epitaph, so the writer must refuse it"
  [[ "$output" == *"DERIVED"* ]] \
    || _fail 1 "$MAP" "the writer's refusal does not say the value is derived: $output"

  _status_row "$EPIC" GATES
  [ "$status" -eq 0 ] || _fail 1 "commands/aid-status.md" "the status render failed: $output"
  [[ "$output" == *"ctl=awaiting_host_resume"* ]] \
    || _fail 1 "commands/aid-status.md" "the RENDER did not derive awaiting_host_resume from (artifact on disk) AND (no liveness signal); it rendered: $output"
  [[ "$output" == *"STALLED?"* ]] \
    || _fail 1 "commands/aid-status.md" "the row claims awaiting_host_resume without the stall marker its own second fact implies: $output"
  [[ "$output" == *"auto_resume_required.json is still on disk"* ]] \
    || _fail 1 "commands/aid-status.md" "the recovery line does not name the artifact it derived the state from: $output"
  [[ "$output" == *"aid-fsm.sh resume ${EPIC}"* ]] \
    || _fail 1 "commands/aid-status.md" "the row offers no claim command for a renderable epic id: $output"

  # THE NEGATIVE CONTROL, and the proof it is derived rather than read: move the
  # artifact aside and NOTHING stored changes — yet the same render stops saying
  # awaiting_host_resume. Put it back and the state returns.
  mv "$ARTIFACT" "$WORK/artifact.parked"
  _status_row "$EPIC" GATES
  [ "$status" -eq 0 ] || _fail 1 "commands/aid-status.md" "the status render failed with the artifact parked: $output"
  [[ "$output" != *"awaiting_host_resume"* ]] \
    || _fail 1 "commands/aid-status.md" "the render still claims awaiting_host_resume with no artifact on disk — it is reading a stored value, not deriving one: $output"
  [[ "$output" == *"ctl=active"* ]] \
    || _fail 1 "commands/aid-status.md" "with fact 1 gone the row must fall back to the RECORDED controller value: $output"
  mv "$WORK/artifact.parked" "$ARTIFACT"
  _status_row "$EPIC" GATES
  [[ "$output" == *"ctl=awaiting_host_resume"* ]] \
    || _fail 1 "commands/aid-status.md" "restoring the artifact did not restore the derived state: $output"

  # (1d) The gate command has been executed EXACTLY ONCE at this point.
  [ -f "$MARKER" ] || _fail 1 "$MARKER" "the background gate command never executed"
  [ "$(wc -l < "$MARKER")" -eq 1 ] \
    || _fail 1 "$MARKER" "the background gate command executed $(wc -l < "$MARKER") times before the crash; expected exactly 1"

  # ── PHASE 2 ───────────────────────────────────────────────────────────────
  _wait_for 120 '[[ -f "$JOBS/slow_bg-attempt-1/result.json" ]]' \
    || _fail 2 "$JOBS/slow_bg-attempt-1/result.json" "the orphaned job never reached a terminal result on its own"

  # THE WORKTREE EDGE CASE, asserted once: `.aid-o/` is gitignored and therefore
  # absent from a linked worktree, so a cwd-relative read from inside one would
  # see an empty workspace. resume resolves state through lib/aid-roots.sh and
  # must find the PRIMARY checkout's evidence and collect identically.
  ( cd "$PROJ" && git worktree add -q -b p076-int-wt "$WORK/wt" HEAD )
  run bash -c "cd '$WORK/wt' && bash '$FSM' resume '$EPIC'"
  echo "$output"
  [ "$status" -eq 0 ] \
    || _fail 2 "aid-fsm.sh resume" "resume from inside a linked worktree failed: $output"
  [[ "$output" == *"gate row 'slow_bg' = pass"* ]] \
    || _fail 2 "$ROWS/slow_bg.json" "resume did not record the collected terminal result as a gate row: $output"
  [ ! -e "$WORK/wt/.aid-o" ] \
    || _fail 2 "$WORK/wt/.aid-o" "resume created a workspace inside the linked worktree instead of resolving the primary checkout's"
  [ -f "$ROWS/slow_bg.json" ] \
    || _fail 2 "$ROWS/slow_bg.json" "the durable row checkpoint landed somewhere other than the primary checkout's evidence"
  run jq -r '[.gate,.result,.exit_code,.job_id,.job_state] | join("|")' "$ROWS/slow_bg.json"
  [ "$output" = "slow_bg|pass|0|slow_bg-attempt-1|terminal_pass" ] \
    || _fail 2 "$ROWS/slow_bg.json" "the checkpointed row is not the one the job earned: $output"

  # THE SINGLE-USE CLAIM: one claim file, artifact gone from its live path, and
  # a second resume takes nothing and NAMES the winner rather than claiming again.
  [ ! -f "$ARTIFACT" ] \
    || _fail 2 "$ARTIFACT" "the continuation artifact survived its own claim — the claim is not single-use"
  [ "$(claim_files | wc -l)" -eq 1 ] \
    || _fail 2 "$ARTIFACT.claimed-*" "expected exactly one claim file, found $(claim_files | wc -l)"
  local first_claim; first_claim="$(claim_files)"
  run bash -c "cd '$PROJ' && bash '$FSM' resume '$EPIC'"
  [ "$status" -eq 0 ] \
    || _fail 2 "aid-fsm.sh resume" "a second resume must be an idempotent status report, not a failure: $output"
  [[ "$output" == *"already claimed"* ]] \
    || _fail 2 "$ARTIFACT.claimed-*" "the second resume did not report the artifact as already claimed: $output"
  [[ "$output" == *"$(basename "$first_claim")"* ]] \
    || _fail 2 "$ARTIFACT.claimed-*" "the loser does not name the winner's claim file: $output"
  [ "$(claim_files | wc -l)" -eq 1 ] \
    || _fail 2 "$ARTIFACT.claimed-*" "the second resume created a second claim file"

  # NO RE-EXECUTION — the counter, not the clock.
  [ "$(wc -l < "$MARKER")" -eq 1 ] \
    || _fail 2 "$MARKER" "resume RE-RAN the background gate: $(wc -l < "$MARKER") executions, expected 1"

  # ── the rerun: the remaining gate runs, the run completes, services go down ─
  run run_gates_fg
  echo "stderr: $(cat "$WORK/fg.err")"
  [ "$status" -eq 0 ] \
    || _fail 2 "$REPORT" "the rerun did not complete: $(cat "$WORK/fg.err")"

  [ -f "$REPORT" ] || _fail 2 "$REPORT" "no gates report was assembled by the rerun"
  run jq -r '.gates.slow_bg.result' "$REPORT"
  [ "$output" = "pass" ] \
    || _fail 2 "$REPORT" "the crashed background gate is not a pass in the assembled report: $output"
  run jq -r '.gates.slow_bg.job_id' "$REPORT"
  [ "$output" = "slow_bg-attempt-1" ] \
    || _fail 2 "$REPORT" "the assembled row lost its job binding: $output"
  run jq -r '.gates.after_fg.result' "$REPORT"
  [ "$output" = "pass" ] \
    || _fail 2 "$REPORT" "the gate that had not run when the controller died did not run on the rerun: $output"
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ] \
    || _fail 2 "$REPORT" "the run did not complete green: $output"

  # STILL exactly one execution, across a crash, a resume and a rerun.
  [ "$(wc -l < "$MARKER")" -eq 1 ] \
    || _fail 2 "$MARKER" "the background gate was re-executed by the rerun: $(wc -l < "$MARKER") executions, expected 1"

  # The remaining gate genuinely reached the service on a per-run port.
  [ -f "$WORK/after.marker" ] \
    || _fail 2 "$WORK/after.marker" "the dependent gate never connected to the declared service"
  [[ "$(cat "$WORK/after.marker")" =~ ^[1-9][0-9]*$ ]] \
    || _fail 2 "$WORK/after.marker" "the dependent gate did not record the per-run port it connected to"

  # ── the service DIES with its run, leaving no orphan ──────────────────────
  [ "$(_reg_field '.services.api.state')" = "stopped" ] \
    || _fail 2 "$REG" "the registry's terminal state for the declared service is not 'stopped' after the run finished"
  [ -f "$WORK/stop.log" ] \
    || _fail 2 "$WORK/stop.log" "the declared stop_cmd never ran"
  ! _probe_port "$(cat "$WORK/after.marker")" \
    || _fail 2 "the process table" "the service is still answering its port after the run released it"
  _assert_no_orphans 2
  run grep -c '"event":"services_released"' "$TIMELINE"
  [ "$status" -eq 0 ] \
    || _fail 2 "$TIMELINE" "the release edge is not on the record"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 3 — a real timeout, a real budget, a stubbed adjudication, a PM stop.
# ═══════════════════════════════════════════════════════════════════════════

@test "phase 3: a forced GATE_TIMEOUT exhausts the ladder budget, the stubbed adjudication escalates, and the run is blocked for a person" {
  _require_process_facilities
  local P3EPIC="E-076-8_8"
  local P3EVID_REL=".aid-o/work/evidence/${P3EPIC}/R-1"
  local P3PROJ="$WORK/p3" P3EVID
  P3EVID="$P3PROJ/$P3EVID_REL"
  mkdir -p "$P3EVID/gates" "$P3PROJ/.aid-o/work"
  git -C "$P3PROJ" init -q
  git -C "$P3PROJ" config user.email p076e3@example.com
  git -C "$P3PROJ" config user.name P076E3
  printf 'phase 3 fixture\n' > "$P3PROJ/README.md"
  printf '.aid-o/\n' > "$P3PROJ/.gitignore"
  git -C "$P3PROJ" add README.md .gitignore
  git -C "$P3PROJ" commit -qm "phase 3 fixture base"

  # THE FORCED TIMEOUT: a background gate whose command cannot finish inside its
  # declared deadline. Deterministic by construction — the deadline is 2 s and
  # the command sleeps 60.
  cat > "$P3PROJ/exec.yaml" <<'YAML'
gates:
  slow:
    command: "sleep 60"
    required: false
    timeout_seconds: 2
    max_retries: 2
    run_mode: background
YAML

  ( cd "$P3PROJ" && AID_GATE_BASELINE_FILE="$WORK/baseline-p3.yaml" \
      "$RUN_GATES" run-all exec.yaml "$P3EPIC" R-1 \
      --report-file "$P3EVID_REL/gates/gates_report.json" \
      >"$WORK/p3.out" 2>"$WORK/p3.err" )

  local REC="$P3EVID/recovery-ladder.jsonl"

  # (3a) the REAL runner classified the stop and wrote the mechanical entry
  [ -f "$REC" ] \
    || _fail 3 "$REC" "a gate that timed out wrote no ladder entry — the emitter did not fire: $(cat "$WORK/p3.err")"
  run jq -r -s '[.[] | select(.class=="GATE_TIMEOUT" and .emitter=="timeout_policy_block")] | length' "$REC"
  [ "$output" -ge 1 ] \
    || _fail 3 "$REC" "no GATE_TIMEOUT stop was recorded by the timeout_policy_block emitter: $(cat "$REC")"
  run jq -r -s '.[0] | [.event, .class, .outcome] | join("|")' "$REC"
  [ "$output" = "recovery_stop|GATE_TIMEOUT|detected" ] \
    || _fail 3 "$REC" "the emitted stop line is not the pinned shape: $output"

  # (3b) THE BUDGET. GATE_TIMEOUT ships attempts: 1 — the first is granted, the
  #      second is refused IN THE SAME SECOND, so the wall clock is not what
  #      refused it, and the refusal routes to adjudication.
  local drive="$WORK/ladder.sh"
  cat > "$drive" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "$LADDER_LIB"
"$@"
SH
  run bash "$drive" aid_ladder_attempt "$P3EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 0 ] && [ "$output" = "proceed 1" ] \
    || _fail 3 "$REC" "the first recovery attempt inside budget was not granted: rc=$status out=$output"
  run bash "$drive" aid_ladder_attempt "$P3EVID" GATE_TIMEOUT rerun_targeted
  [ "$status" -eq 4 ] \
    || _fail 3 "$REC" "the budget-th + 1 attempt was not refused (rc $status) — the budget is not enforced"
  [ "$output" = "adjudicate budget_exhausted" ] \
    || _fail 3 "$REC" "the refusal does not route to adjudication by name: $output"
  run jq -r -s '[.[] | select(.event=="recovery_attempt") | .outcome] | join(",")' "$REC"
  [ "$output" = "started,budget_exhausted" ] \
    || _fail 3 "$REC" "the refusal was not recorded, or spent an attempt of its own: $output"

  # (3c) ADJUDICATION, STUBBED. `_run_codex_isolated` is redefined AFTER the lib
  #      is sourced, so nothing in this suite can reach the real codex CLI.
  #
  #      The stub replies with the one thing an adjudicator is most likely to
  #      reach for when its budget is gone and most certainly may not have: PM
  #      authority to force past the stop. `escalate` is deliberately NOT in the
  #      action vocabulary — no caller can execute it — so this is the ceiling
  #      working: the reply is rejected mechanically, the retry quotes the
  #      rejection, the second reply is rejected too, and the FUNCTION returns
  #      `escalate`. That is the route into the terminus below.
  printf 'gate slow exceeded its 2s deadline three times; the GATE_TIMEOUT budget is spent.\n' \
    > "$P3EVID/facts.md"
  local adj="$WORK/adjudicate.sh"
  cat > "$adj" <<'SH'
#!/usr/bin/env bash
source "$ADJ_LIB"
_run_codex_isolated() {
  local events="$3" last="$5"
  printf 'ACTION: pm_force\nRATIONALE: the budget is spent; grant me PM authority to force the gate through.\n' > "$last"
  echo '{"type":"thread.started","thread_id":"t-stub"}' > "$events"
  echo x >> "$STUB_COUNT"
  return 0
}
aid_recovery_adjudicate "$@"
SH
  export STUB_COUNT="$WORK/stub-dispatches.txt"
  run bash -c "cd '$P3PROJ' && bash '$adj' '$P3EVID' GATE_TIMEOUT '$P3EVID/facts.md'"
  echo "$output"
  [ "$status" -eq 3 ] \
    || _fail 3 "$P3EVID/timeline.jsonl" "an adjudication that reaches escalate must say so in its exit code: rc=$status"
  [ "$output" = "escalate" ] \
    || _fail 3 "$P3EVID/timeline.jsonl" "the stubbed adjudication did not conclude escalate: $output"
  run jq -r -s '[.[] | select(.event=="recovery_adjudication")] | last | [.class,.action] | join("|")' "$P3EVID/timeline.jsonl"
  [ "$output" = "GATE_TIMEOUT|escalate" ] \
    || _fail 3 "$P3EVID/timeline.jsonl" "the escalation was not recorded against its stop class: $output"
  run jq -r -s '[.[] | select(.event=="recovery_adjudication")] | last | .verdict' "$P3EVID/timeline.jsonl"
  [[ "$output" == rejected_* ]] \
    || _fail 3 "$P3EVID/timeline.jsonl" "a demand for PM authority was not REJECTED — the ceiling did not hold: $output"
  # It was asked twice and refused twice; it never widened its own remit.
  [ "$(wc -l < "$STUB_COUNT")" -eq 2 ] \
    || _fail 3 "$P3EVID/timeline.jsonl" "expected exactly one rejection + one quoted retry, saw $(wc -l < "$STUB_COUNT") dispatches"

  # (3d) THE TERMINUS: blocked_for_pm lands on the map, through aid-fsm.sh's ONE
  #      writer — the map stops claiming a live autonomous controller.
  jq -n --arg e "$P3EPIC" \
    '{($e): {state_file: (".aid-o/work/evidence/" + $e + "/R-1/fsm-state.yaml"),
      run_id:"R-1", state:"ESCALATION", branch:("task/" + $e + "/main"),
      auto_controller:"active", resume_artifact:null,
      updated_at:"2026-08-09T00:00:00Z"}}' > "$P3PROJ/.aid-o/work/active-runs.json"
  printf 'epic_id: %s\nrun_id: R-1\nstate: ESCALATION\n' "$P3EPIC" > "$P3EVID/fsm-state.yaml"

  run bash -c "set -euo pipefail; cd '$P3PROJ'; export AID_PROJECT_ROOT='$P3PROJ'; source '$LADDER_LIB'; aid_ladder_escalate '$P3EVID' GATE_TIMEOUT"
  [ "$status" -eq 0 ] \
    || _fail 3 "$P3PROJ/.aid-o/work/active-runs.json" "the escalation terminus failed: $output"
  run jq -r --arg e "$P3EPIC" '.[$e].auto_controller' "$P3PROJ/.aid-o/work/active-runs.json"
  [ "$output" = "blocked_for_pm" ] \
    || _fail 3 "$P3PROJ/.aid-o/work/active-runs.json" "the map does not show the run blocked for a person: $output"
  run jq -r -s '[.[] | select(.event=="recovery_terminus")] | .[0] | [.class,.outcome] | join("|")' "$REC"
  [ "$output" = "GATE_TIMEOUT|escalated" ] \
    || _fail 3 "$REC" "the terminus is not in the ladder record: $output"

  # (3e) AND THE CEILING HOLDS: reaching ESCALATION automatically did NOT make
  #      it leavable. The transition still refuses without escalation_decision,
  #      and accepts once a person has recorded one.
  run bash -c "cd '$P3PROJ' && bash '$FSM' transition ESCALATION GATES '$P3EVID/fsm-state.yaml'"
  [ "$status" -ne 0 ] \
    || _fail 3 "$P3EVID/fsm-state.yaml" "ESCALATION was leavable without a PM decision — the ladder smuggled authority it must not have"
  [[ "$output" == *"escalation_decision"* ]] \
    || _fail 3 "$P3EVID/fsm-state.yaml" "the refusal does not name the field it requires: $output"
  printf 'escalation_decision: proceed\n' >> "$P3EVID/fsm-state.yaml"
  run bash -c "cd '$P3PROJ' && bash '$FSM' transition ESCALATION GATES '$P3EVID/fsm-state.yaml'"
  [ "$status" -eq 0 ] \
    || _fail 3 "$P3EVID/fsm-state.yaml" "with the PM decision recorded the transition should proceed: $output"
}

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 4 — the invariance proof: everything above changed nothing for a
# project that declares no services and runs every gate in the foreground.
# ═══════════════════════════════════════════════════════════════════════════

@test "phase 4: GOLDEN — a foreground-only config with no services is byte-identical to the committed pre-P076 reference" {
  _require_process_facilities
  [ -f "$GOLDEN" ] \
    || _fail 4 "$GOLDEN" "the committed pre-P076 reference is missing — phase 4 has nothing to compare against and must never regenerate it"

  local GPROJ="$WORK/golden"
  mkdir -p "$GPROJ"
  golden_build_fixture "$GPROJ"

  ( cd "$GPROJ" && AID_GATE_BASELINE_FILE="$WORK/baseline-golden.yaml" \
      "$RUN_GATES" run-all exec.yaml E-P076 R-1 \
      --report-file ".aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" \
      >/dev/null 2>"$WORK/golden.err" ) || true

  local actual="$GPROJ/.aid-o/work/evidence/E-P076/R-1/gates/gates_report.json"
  [ -f "$actual" ] \
    || _fail 4 "$actual" "the runner produced no report for the golden fixture: $(cat "$WORK/golden.err")"
  golden_normalize "$actual" > "$WORK/golden-actual.json"

  run diff -u "$GOLDEN" "$WORK/golden-actual.json"
  [ "$status" -eq 0 ] \
    || _fail 4 "$GOLDEN" "the report drifted from the committed pre-P076 reference:
$output"

  # And no service state was created for a project that declares none.
  [ ! -e "$GPROJ/.aid-o/work/evidence/E-P076/R-1/services.json" ] \
    || _fail 4 "services.json" "a project that declares no services got a service registry"
  [ ! -e "$GPROJ/.aid-o/work/evidence/E-P076/R-1/service-jobs" ] \
    || _fail 4 "service-jobs/" "a project that declares no services got a service jobs root"
  [ ! -e "$GPROJ/.aid-o/work/evidence/E-P076/R-1/auto_resume_required.json" ] \
    || _fail 4 "auto_resume_required.json" "a run with no background gate wrote a continuation pointer"
}

# ═══════════════════════════════════════════════════════════════════════════
# THE REGISTRY — AID-v3 principle #1: a detection capability without a recorded
# enforcement is decoration. Every mechanism this plan shipped has a row.
# ═══════════════════════════════════════════════════════════════════════════

@test "registry: every mechanism this plan shipped has an enforcement-registry row" {
  [ -f "$REGISTRY" ] || _fail 4 "$REGISTRY" "the enforcement registry is missing"

  local id
  for id in \
    gate_run_mode_contract \
    gate_background_eager_artifact \
    resume_single_use_claim \
    active_run_stall_derivation \
    instruction_closure_structural_check \
    service_declaration_schema \
    service_registry_eager_write \
    service_lifecycle_acquire_release \
    service_teardown_declaration_preflight \
    gate_needs_services_fail_fast \
    auto_recovery_policy_contract \
    recovery_adjudication_allowlist \
    recovery_ladder_budget_refusal \
    recovery_escalation_terminus
  do
    grep -qE "^  - id: ${id}\$" "$REGISTRY" \
      || _fail 4 "$REGISTRY" "no enforcement row with id '${id}' — a mechanism this plan shipped is unregistered"
  done

  # Every row this plan added carries an `instruction:` that a reader other than
  # its author can actually follow: a TRACKED source-doc section, a skill or
  # command heading, or the literal `n/a` for an internal guard. NEVER a plan
  # file — `.aid-o/plans/`, `docs/plans/` and `docs/design/` are gitignored, so a
  # citation into one resolves to nothing for every reader but the author's own
  # working tree.
  #
  # SCOPED TO THIS PLAN'S BLOCK, deliberately and honestly: four PRE-EXISTING
  # rows (one P041-era, three P069) do cite gitignored plan files. Repairing
  # other steps' rows is not this step's business and a whole-file assertion
  # would either fail on debt it did not create or force a silent edit of rows
  # nobody reviewed here. The block boundary is the P076 banner comment.
  run bash -c "awk '/^  # ══ P076:/{p=1} p' '$REGISTRY' | grep -nE '^    instruction: ' | grep -E 'docs/plans/|[.]aid-o/plans/|docs/design/'"
  [ "$status" -ne 0 ] \
    || _fail 4 "$REGISTRY" "a P076 instruction: field cites a gitignored plan/design file, which resolves to nothing for any other reader:
$output"

  # EVERY FILE A P076 `instruction:` CITES MUST EXIST, AND EVERY `grep:` TOKEN
  # IT PROMISES MUST BE FINDABLE THERE.
  #
  # THE REGRESSION THIS CLOSES. Two rows anchored the declared-services lifecycle
  # to "commands/aid-run.md + skills/pipeline.md (the gate-run section)". Neither
  # half existed: `grep -ci service commands/aid-run.md` was 0, and pipeline.md's
  # only hits were the SERVICE_UNHEALTHY stop-class name and a docker-compose
  # scan. The registry asserted DOCUMENTATION that did not exist — the exact
  # defect, inverted, that the banner three lines above these rows says the
  # registry is the single most damaging place for. The gitignore check above
  # cannot see it: a citation into a TRACKED file that says nothing about the
  # mechanism passes it. Existence plus the promised token is what closes it.
  local ins path tok plugin_rel found
  local -a toks
  while IFS= read -r ins; do
    for path in $(grep -oE '(commands|skills|agents|defaults|scripts)/[A-Za-z0-9._/-]+\.(md|ya?ml|json|sh)|docs/[A-Za-z0-9._/-]+\.md' <<<"$ins" | sort -u); do
      case "$path" in
        docs/*) plugin_rel="$REPO_ROOT/$path" ;;
        *)      plugin_rel="$PLUGIN_ROOT/$path" ;;
      esac
      [ -f "$plugin_rel" ] \
        || _fail 4 "$REGISTRY" "a P076 instruction: cites '$path', which does not exist — a reader following this anchor finds nothing:
$ins"
    done
    # `grep: 'token'` inside an anchor is a PROMISE about the file beside it.
    #
    # EVERY promise, not just the last one. The extraction was
    # `sed -n "s/.*grep: '\(...\)'.*/\1/p"`, whose leading `.*` is GREEDY: on an
    # instruction promising two tokens it returned only the SECOND, and the
    # first went unverified. No P076 row promises two today, so this was latent —
    # which is exactly when it is cheap to fix.
    mapfile -t toks < <(grep -oE "grep: '[^']*'" <<<"$ins" | sed "s/^grep: '//; s/'\$//")
    for tok in ${toks+"${toks[@]}"}; do
      [ -n "$tok" ] || continue
      found=0
      for path in $(grep -oE '(commands|skills|agents|defaults|scripts)/[A-Za-z0-9._/-]+\.(md|ya?ml|json|sh)|docs/[A-Za-z0-9._/-]+\.md' <<<"$ins" | sort -u); do
        case "$path" in
          docs/*) plugin_rel="$REPO_ROOT/$path" ;;
          *)      plugin_rel="$PLUGIN_ROOT/$path" ;;
        esac
        grep -qF -- "$tok" "$plugin_rel" && { found=1; break; }
      done
      [ "$found" = 1 ] \
        || _fail 4 "$REGISTRY" "a P076 instruction: promises grep: '$tok' but no file it cites contains that string:
$ins"
    done
  done < <(awk '/^  # ══ P076:/{p=1} p' "$REGISTRY" | grep -E '^    instruction: ')

  # EXISTENCE IS NOT SUBSTANCE — the anchor must land where the mechanism is
  # actually described. Both files the two broken rows cited EXIST, so an
  # existence check alone passes on the very defect this closes (verified: the
  # check above stays green when the broken anchor is restored). Each row
  # therefore declares ONE distinctive token of its own mechanism, IN THE ONE
  # FILE that token is supposed to be found in.
  #
  # TWO WEAKNESSES THIS TABLE PREVIOUSLY HAD, both found by a redundancy sweep
  # while every row was green:
  #
  #   1. THE ANCHOR WAS NOT THE ANCHOR. The old loop walked every file the row
  #      cites and `break`ed on the first hit, and `sort -u` puts `defaults/…`
  #      ahead of `skills/…` — so `service_lifecycle_acquire_release` was
  #      satisfied by `defaults/execution.yaml` and `skills/role-cards.md`, the
  #      document that row is actually ABOUT, was never opened. A check that can
  #      be satisfied by a file other than the one under discussion does not pin
  #      the anchor. Each row now names its file, and the token must be there.
  #
  #   2. THE TOKENS WERE WEAK TO VACUOUS. `resume_single_use_claim` asked for
  #      `resume` (23 hits in aid-run.md — no plausible edit removes it);
  #      `recovery_ladder_budget_refusal` asked for `budget` against a policy
  #      whose own key IS `budget:`, so it self-satisfied; `service_registry_
  #      eager_write` reused `start_cmd` verbatim from the row above it, proving
  #      the services block exists and saying nothing about eager writing;
  #      `recovery_adjudication_allowlist` asked for the FILENAME
  #      `auto-recovery.yaml` rather than `allowed_actions`, the mechanism-
  #      distinctive key. A token is only worth asserting if deleting the
  #      mechanism's description would delete the token — that is the bar every
  #      entry below is chosen against, and the third column records it.
  local triple rid tfile want cited
  for triple in \
    "gate_run_mode_contract|docs/extending-aid.md|### The owned-job contract" \
    "gate_background_eager_artifact|commands/aid-run.md|awaiting_host_resume" \
    "resume_single_use_claim|commands/aid-run.md|exactly once" \
    "active_run_stall_derivation|commands/aid-status.md|recipe: stalled-runs" \
    "instruction_closure_structural_check|skills/agent-protocol.md|Controller boundary" \
    "service_declaration_schema|defaults/execution.yaml|service-declaration.schema.json" \
    "gate_needs_services_fail_fast|defaults/execution.yaml|needs_services" \
    "service_registry_eager_write|defaults/execution.yaml|no self-daemonising fork" \
    "service_lifecycle_acquire_release|skills/role-cards.md|declare it, never improvise it" \
    "service_teardown_declaration_preflight|docs/extending-aid.md|Teardown reconciles commands against the declaration" \
    "auto_recovery_policy_contract|commands/aid-run.md|auto-recovery.yaml" \
    "recovery_adjudication_allowlist|defaults/policies/auto-recovery.yaml|allowed_actions" \
    "recovery_ladder_budget_refusal|defaults/policies/auto-recovery.yaml|wall_clock_seconds" \
    "recovery_escalation_terminus|skills/pipeline.md|blocked_for_pm"
  do
    rid="${triple%%|*}"; want="${triple##*|}"; tfile="${triple#*|}"; tfile="${tfile%%|*}"
    ins="$(awk -v id="  - id: ${rid}" '$0 == id {f=1; next} f && /^    instruction: /{print; exit}' "$REGISTRY")"
    [ -n "$ins" ] || _fail 4 "$REGISTRY" "row '${rid}' has no instruction: field"
    # THE ROW MUST STILL CITE THE FILE ITS TOKEN IS PINNED IN — otherwise this
    # table could drift into asserting things about documents the registry no
    # longer sends anyone to.
    cited="$(grep -oE '(commands|skills|agents|defaults|scripts)/[A-Za-z0-9._/-]+\.(md|ya?ml|json|sh)|docs/[A-Za-z0-9._/-]+\.md' <<<"$ins" | sort -u | tr '\n' ' ')"
    [[ " $cited" == *" $tfile "* ]] \
      || _fail 4 "$REGISTRY" "row '${rid}' no longer cites '${tfile}', the file this suite pins its mechanism token in — it cites [${cited% }]:
$ins"
    case "$tfile" in
      docs/*) plugin_rel="$REPO_ROOT/$tfile" ;;
      *)      plugin_rel="$PLUGIN_ROOT/$tfile" ;;
    esac
    grep -qF -- "$want" "$plugin_rel" \
      || _fail 4 "$REGISTRY" "row '${rid}' anchors its instruction to '${tfile}', but that file does not mention '${want}' — the anchor names a document that does not describe the mechanism, which is the defect the banner above these rows says the registry is the worst place for:
$ins"
  done

  # THE BANNER'S OWN CLAIM ABOUT ITSELF MUST BE TRUE.
  #
  # THE REGRESSION THIS CLOSES. The banner said "Two rows below are honestly
  # labelled as carrying no shipped enforcement of their own (`surface:
  # internal-guard`)". FIVE rows carried that surface, and three of the five had
  # real shipped runtime enforcement — the sentence asserting the pass's honesty
  # was itself wrong in both directions, and it redefined a field 100+ other rows
  # already use with a different meaning. `surface:` now means what the schema
  # header says (WHERE the rule is stated, not how strong the enforcement is),
  # and the banner's count is asserted against the rows rather than trusted.
  #
  # `|| true` IS LOAD-BEARING: `grep -c` prints `0` and EXITS 1 on no match, so
  # under bats' `set -e` the assignment aborted the test before the message
  # below could print — in exactly the case it exists to report. The check could
  # only ever say "too many", never "none".
  local ig_count ig_ids
  ig_count="$(awk '/^  # ══ P076:/{p=1} p' "$REGISTRY" | grep -c '^    surface: internal-guard' || true)"
  ig_ids="$(awk '/^  # ══ P076:/{p=1} p' "$REGISTRY" \
            | awk '/^  - id: /{id=$3} /^    surface: internal-guard$/{print id}')"
  [ "$ig_count" = "1" ] \
    || _fail 4 "$REGISTRY" "the P076 banner states that exactly ONE row carries surface: internal-guard, but ${ig_count} do (${ig_ids//$'\n'/, }) — the banner is describing itself falsely, which is the one thing this registry pass exists to prevent"
  [ "$ig_ids" = "service_teardown_declaration_preflight" ] \
    || _fail 4 "$REGISTRY" "the P076 banner names service_teardown_declaration_preflight as the one internal-guard row; the file says: ${ig_ids//$'\n'/, }"
  grep -q 'Exactly ONE row below is `internal-guard`' "$REGISTRY" \
    || _fail 4 "$REGISTRY" "the P076 banner no longer states how many internal-guard rows it has, so nothing holds its self-description to the rows"

  # And every P076 row carries the five fields the schema requires.
  local missing
  missing="$(yq -r '
      .enforcements[]
      | select(.description // "" | test("^P076"))
      | select((.type == null) or (.source == null) or (.instruction == null)
               or (.severity == null) or (.surface == null))
      | .id' "$REGISTRY")"
  [ -z "$missing" ] \
    || _fail 4 "$REGISTRY" "these P076 rows are missing one of type/source/instruction/severity/surface: $missing"

  # The registry stays parseable and the declared total matches reality.
  run yq -r '.enforcements | length' "$REGISTRY"
  [ "$status" -eq 0 ] \
    || _fail 4 "$REGISTRY" "the registry no longer parses as YAML: $output"
  local n="$output" declared
  declared="$(yq -r '.totals.enforcements' "$REGISTRY")"
  [ "$n" = "$declared" ] \
    || _fail 4 "$REGISTRY" "totals.enforcements says ${declared} but the file holds ${n} rows"
}
