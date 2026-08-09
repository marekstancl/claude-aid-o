#!/usr/bin/env bats
# test-gate-background.bats — P076 Step 2: the background gate path.
#
# Every case here drives the REAL aid-run-gates.sh over a real fixture repo and
# a real aid-job.sh supervisor. Nothing is stubbed — a suite that asserted
# against test-local helpers would prove the helpers work, not the runner.
#
#   1. A background gate produces a job record + terminal result bound to the
#      start HEAD/tree, a gate row carrying job_id + job_state, and heartbeat
#      progress events while it polls.
#   2. A SIGKILLed runner leaves the job alive; the rerun RE-ATTACHES (one job
#      dir, gate_job_reattached logged) and completes the report WITHOUT
#      re-executing the suite.
#   3. A background timeout maps to the existing fail + streak accounting
#      (synthesized 124 → censored samples → timeout_policy_block).
#   4. Child processes of a timed-out background gate are dead (group kill).
#   5. Command drift supersedes the stale job dir instead of re-attaching it.
#   6. GOLDEN: a foreground-only execution.yaml produces a gates_report
#      identical to the committed pre-P076 reference on the same fixture.
#   7. CP2 carry-over: the REAL runner rejects an invalid run_mode loudly,
#      before any gate command is spawned.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  export RUN_GATES
  JOB_SH="$PLUGIN_ROOT/scripts/aid-job.sh"
  export JOB_SH
  GOLDEN="$PLUGIN_ROOT/scripts/tests/fixtures/p076/golden-gates-report.json"
  export GOLDEN

  WORK="$(mktemp -d)"
  export WORK
  PROJ="$WORK/project"
  export PROJ
  mkdir -p "$PROJ"

  # Isolated runtime-baseline store — never the real clone's .aid-o/metrics.
  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"

  # Seconds instead of minutes: the shipped cadence is 5 s poll / 60 s
  # heartbeat / 30 s grace, and these env seams exist so a test can exercise a
  # complete poll-and-heartbeat cycle without waiting a minute for it.
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1

  EVID=".aid-o/work/evidence/E-BG/R-1"
  export EVID
  REPORT="$PROJ/$EVID/gates/gates_report.json"
  export REPORT
  TIMELINE="$PROJ/$EVID/timeline.jsonl"
  export TIMELINE
  JOBS="$PROJ/$EVID/jobs"
  export JOBS
}

teardown() {
  # Kill anything this test's supervisor still owns before removing the tree —
  # a stray `sleep 300` outliving the suite is exactly what this step exists to
  # prevent, and a test that leaks one has no standing to assert about it.
  if [[ -d "${JOBS:-/nonexistent}" ]]; then
    local d pgid
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      pgid="$(jq -r '.pgid // empty' "$d/job.json" 2>/dev/null || true)"
      [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
    done
  fi
  [[ -n "${BG_RUNNER_PID:-}" ]] && kill -KILL "$BG_RUNNER_PID" 2>/dev/null || true
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

# init_project — a real git repo with a real evidence directory.
init_project() {
  mkdir -p "$PROJ/$EVID/gates"
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email bg@example.com
  git -C "$PROJ" config user.name Background
  printf 'bg fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  git -C "$PROJ" add README.md .gitignore
  git -C "$PROJ" commit -qm "bg fixture base"
}

run_gates() {
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-BG R-1 \
      --report-file "$EVID/gates/gates_report.json" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt" )
}

# wait_for_job_pid <job_dir> — block until the supervisor recorded a live pid.
wait_for_job_pid() {
  local d="$1" i
  for i in $(seq 1 150); do
    [[ -f "$d/job.json" ]] && jq -e '.pid != null' "$d/job.json" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

# ── golden fixture + normalizer ──────────────────────────────────────────────
# Copied VERBATIM from the capture procedure that produced
# fixtures/p076/golden-gates-report.json against the PRE-Step-2 runner. If
# either drifts, case 6 fails — which is the whole point of a golden.
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

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: a background gate runs under aid-job.sh with a HEAD/tree-bound record and a job-bound row" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "sleep 3; echo bg-done"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  run run_gates
  [ "$status" -eq 0 ]

  # (a) A real supervised job dir, at the deterministic flat id.
  [ -d "$JOBS/bg-attempt-1" ]
  [ -f "$JOBS/bg-attempt-1/job.json" ]
  [ -f "$JOBS/bg-attempt-1/result.json" ]

  # (b) The result is bound to the HEAD/tree the job STARTED from.
  local head; head="$(git -C "$PROJ" rev-parse HEAD)"
  run jq -r '.start_head' "$JOBS/bg-attempt-1/result.json"
  [ "$output" = "$head" ]
  run jq -r '.start_tree' "$JOBS/bg-attempt-1/result.json"
  [ -n "$output" ]
  [ "$output" != "null" ]
  run jq -r '.state' "$JOBS/bg-attempt-1/result.json"
  [ "$output" = "terminal_pass" ]

  # (c) The gate row carries the job binding and the composed duration.
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  run jq -r '.gates.bg.job_id' "$REPORT"
  [ "$output" = "bg-attempt-1" ]
  run jq -r '.gates.bg.job_state' "$REPORT"
  [ "$output" = "terminal_pass" ]
  run jq -r '.gates.bg.exit_code' "$REPORT"
  [ "$output" = "0" ]
  run jq -r '.gates.bg.duration_ms' "$REPORT"
  [ "$output" -ge 2000 ]
  run jq -r '.gates.bg.output' "$REPORT"
  [[ "$output" == *"bg-done"* ]]

  # (d) The report schema stays intact and additive.
  run jq -e 'has("_generated_by") and has("_command_log") and has("overall")' "$REPORT"
  [ "$status" -eq 0 ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ]

  # (e) The delegation and the progress signal are both on the timeline.
  run jq -se 'any(.[]; .event == "gate_job_started" and .job_id == "bg-attempt-1")' "$TIMELINE"
  [[ "$output" == *true* ]]
  run jq -se '[.[] | select(.event == "gate_job_heartbeat")] | length' "$TIMELINE"
  [ "$output" -ge 1 ]

  # (f) The durable per-gate row checkpoint was written.
  [ -f "$PROJ/$EVID/gates_rows/bg.json" ]
  run jq -r '.job_id' "$PROJ/$EVID/gates_rows/bg.json"
  [ "$output" = "bg-attempt-1" ]
}

@test "case 2: a SIGKILLed runner leaves the job alive and the rerun re-attaches without re-executing" {
  init_project
  MARKER="$WORK/executions.txt"
  cat > "$PROJ/exec.yaml" <<YAML
gates:
  bg:
    command: "echo ran >> '$MARKER'; sleep 8; echo bg-done"
    required: true
    timeout_seconds: 120
    run_mode: background
YAML

  # Run the gate runner as a child we can kill mid-poll.
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-BG R-1 \
      --report-file "$EVID/gates/gates_report.json" ) >"$WORK/r1.out" 2>"$WORK/r1.err" &
  BG_RUNNER_PID=$!

  wait_for_job_pid "$JOBS/bg-attempt-1"
  [ -f "$JOBS/bg-attempt-1/job.json" ]

  # SIGKILL the runner — no trap, no cleanup, the harshest possible death.
  kill -KILL "$BG_RUNNER_PID" 2>/dev/null || true
  wait "$BG_RUNNER_PID" 2>/dev/null || true

  # The job is setsid-detached and group-owned, so it survives its caller.
  run bash "$JOB_SH" status --jobs-dir "$JOBS" --id bg-attempt-1
  [ "$output" = "running" ]

  # It has ALREADY executed the suite once at this point.
  [ -f "$MARKER" ]
  run wc -l < "$MARKER"
  [ "$output" -eq 1 ]

  # The rerun: same command, same HEAD → re-attach.
  run run_gates
  [ "$status" -eq 0 ]

  # (a) Exactly ONE job dir — no second job was started for this attempt.
  run bash -c "ls -d '$JOBS'/bg-attempt-* 2>/dev/null | wc -l"
  [ "$output" -eq 1 ]
  run bash -c "ls -d '$JOBS'/*.superseded-* 2>/dev/null | wc -l"
  [ "$output" -eq 0 ]

  # (b) The re-attach is on the record.
  run jq -se 'any(.[]; .event == "gate_job_reattached" and .job_id == "bg-attempt-1")' "$TIMELINE"
  [[ "$output" == *true* ]]

  # (c) The suite ran exactly ONCE across both invocations — the crash cost
  #     zero re-execution.
  run wc -l < "$MARKER"
  [ "$output" -eq 1 ]

  # (d) And the report is complete, built from the collected terminal result.
  [ -f "$REPORT" ]
  run jq -r '.gates.bg.result' "$REPORT"
  [ "$output" = "pass" ]
  run jq -r '.gates.bg.job_id' "$REPORT"
  [ "$output" = "bg-attempt-1" ]
  run jq -r '.gates.bg.job_state' "$REPORT"
  [ "$output" = "terminal_pass" ]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ]
}

@test "case 3: a background timeout maps to fail + the existing 124 streak accounting" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  slow:
    command: "sleep 60"
    required: false
    timeout_seconds: 2
    max_retries: 2
    run_mode: background
YAML

  run run_gates
  [ "$status" -eq 0 ]

  # (a) The row is a plain fail with the SYNTHESIZED 124 the timeout consumers
  #     key on, and the real kill signal preserved beside it.
  run jq -r '.gates.slow.result' "$REPORT"
  [ "$output" = "fail" ]
  run jq -r '.gates.slow.exit_code' "$REPORT"
  [ "$output" = "124" ]
  run jq -r '.gates.slow.job_state' "$REPORT"
  [ "$output" = "timed_out" ]
  run jq -r '.gates.slow.job_exit_code' "$REPORT"
  [ "$output" != "124" ]
  [ "$output" != "null" ]

  # (b) Streak accounting is unchanged: 124 → censored samples → after three
  #     censored attempts the repeated-timeout policy block fires, exactly as
  #     it does for a foreground gate.
  run jq -r '.gates.slow.runtime_baseline.last_attempt_result' "$REPORT"
  [ "$output" = "timeout" ]
  run jq -r '.gates.slow.runtime_baseline.samples_count' "$REPORT"
  [ "$output" -eq 3 ]
  run jq -r '.gates.slow.runtime_baseline.non_censored_samples_count' "$REPORT"
  [ "$output" -eq 0 ]
  run jq -r '.gates.slow.reason' "$REPORT"
  [ "$output" = "timeout_policy_block" ]
  run jq -r '.gates.slow.recommendation' "$REPORT"
  [ "$output" = "increase_timeout_or_background" ]

  # (c) Each retry got its OWN deterministic job id — a failed terminal job is
  #     never re-attached as the next attempt's result.
  [ -d "$JOBS/slow-attempt-1" ]
  [ -d "$JOBS/slow-attempt-2" ]
  [ -d "$JOBS/slow-attempt-3" ]
  run jq -r '.state' "$JOBS/slow-attempt-1/result.json"
  [ "$output" = "timed_out" ]
  run jq -r '.state' "$JOBS/slow-attempt-3/result.json"
  [ "$output" = "timed_out" ]
}

@test "case 4: child processes of a timed-out background gate are dead (group kill)" {
  init_project
  cat > "$WORK/spawn-children.sh" <<'SH'
#!/usr/bin/env bash
# Spawn a grandchild that would outlive a naive `timeout` kill, record its pid,
# then block. Only a PROCESS GROUP kill reaches the grandchild.
sleep 300 &
echo "$!" > "$1"
sleep 300
SH
  chmod +x "$WORK/spawn-children.sh"

  cat > "$PROJ/exec.yaml" <<YAML
gates:
  spawner:
    command: "bash '$WORK/spawn-children.sh' '$WORK/child.pid'"
    required: false
    timeout_seconds: 3
    max_retries: 0
    run_mode: background
YAML

  run run_gates
  [ "$status" -eq 0 ]

  [ -f "$WORK/child.pid" ]
  CHILD_PID="$(cat "$WORK/child.pid")"
  [[ "$CHILD_PID" =~ ^[0-9]+$ ]]

  # The supervisor group-kills on a timeout; give the reap a moment, then
  # assert ZERO surviving child pids.
  local i alive=1
  for i in $(seq 1 100); do
    if ! kill -0 "$CHILD_PID" 2>/dev/null; then alive=0; break; fi
    sleep 0.1
  done
  [ "$alive" -eq 0 ]

  run jq -r '.gates.spawner.job_state' "$REPORT"
  [ "$output" = "timed_out" ]
  run jq -r '.gates.spawner.exit_code' "$REPORT"
  [ "$output" = "124" ]
}

@test "case 5: a changed command supersedes the stale job dir instead of re-attaching it" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "echo first-command"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML
  run run_gates
  [ "$status" -eq 0 ]
  run jq -r '.gates.bg.output' "$REPORT"
  [[ "$output" == *"first-command"* ]]
  FIRST_FP="$(jq -r '.command_fingerprint' "$JOBS/bg-attempt-1/job.json")"

  # Same gate, different command → different fingerprint → config drift.
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  bg:
    command: "echo second-command"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML
  run run_gates
  [ "$status" -eq 0 ]

  # (a) The stale job dir was ARCHIVED, freeing the deterministic id, and the
  #     cancel+archive happened under a named log beside it.
  run bash -c "find '$JOBS' -maxdepth 1 -type d -name 'bg-attempt-1.superseded-*' | wc -l"
  [ "$output" -eq 1 ]
  run bash -c "find '$JOBS' -maxdepth 1 -type f -name 'bg-attempt-1.superseded-*.log' | wc -l"
  [ "$output" -eq 1 ]

  # (b) A FRESH job ran under the same id, with the new command's fingerprint.
  [ -d "$JOBS/bg-attempt-1" ]
  run jq -r '.command_fingerprint' "$JOBS/bg-attempt-1/job.json"
  [ "$output" != "$FIRST_FP" ]
  run jq -r '.gates.bg.output' "$REPORT"
  [[ "$output" == *"second-command"* ]]

  # (c) It is on the record as a supersede, not a re-attach.
  run jq -se 'any(.[]; .event == "gate_job_superseded" and .reason == "command_fingerprint_mismatch")' "$TIMELINE"
  [[ "$output" == *true* ]]
}

@test "case 6: GOLDEN — a foreground-only execution.yaml is byte-identical to the pre-P076 report" {
  [ -f "$GOLDEN" ]
  GPROJ="$WORK/golden"
  mkdir -p "$GPROJ"
  golden_build_fixture "$GPROJ"

  ( cd "$GPROJ" && "$RUN_GATES" run-all exec.yaml E-P076 R-1 \
      --report-file ".aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" \
      >/dev/null 2>"$WORK/golden.err" ) || true

  [ -f "$GPROJ/.aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" ]
  golden_normalize "$GPROJ/.aid-o/work/evidence/E-P076/R-1/gates/gates_report.json" \
    > "$WORK/golden-actual.json"

  run diff -u "$GOLDEN" "$WORK/golden-actual.json"
  [ "$status" -eq 0 ]
}

@test "case 8: two background gates with IDENTICAL commands never cross-attach" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  twin_a:
    command: "echo same-command"
    required: true
    timeout_seconds: 60
    run_mode: background
  twin_b:
    command: "echo same-command"
    required: true
    timeout_seconds: 60
    run_mode: background
YAML

  run run_gates
  [ "$status" -eq 0 ]

  # Same fingerprint, but the jobs dir is keyed per GATE in the flat topology,
  # so each gate got its own job and its own row.
  run jq -r '.command_fingerprint' "$JOBS/twin_a-attempt-1/job.json"
  FP_A="$output"
  run jq -r '.command_fingerprint' "$JOBS/twin_b-attempt-1/job.json"
  [ "$output" = "$FP_A" ]

  run jq -r '.gates.twin_a.job_id' "$REPORT"
  [ "$output" = "twin_a-attempt-1" ]
  run jq -r '.gates.twin_b.job_id' "$REPORT"
  [ "$output" = "twin_b-attempt-1" ]
  run jq -se 'any(.[]; .event == "gate_job_reattached")' "$TIMELINE"
  [[ "$output" == *false* ]]
  run jq -r '.overall' "$REPORT"
  [ "$output" = "pass" ]
}

@test "case 7: the REAL runner rejects an invalid run_mode loudly, before any command is spawned" {
  init_project
  # `early` is defined FIRST and would leave a marker if it ever ran; the typo
  # is on a LATER gate, so a validation that happened per-gate instead of
  # upfront would be caught here.
  cat > "$PROJ/exec.yaml" <<YAML
gates:
  early:
    command: "touch '$WORK/early-ran'"
    required: false
    timeout_seconds: 30
  typo_gate:
    command: "touch '$WORK/typo-ran'"
    required: false
    timeout_seconds: 30
    run_mode: backgroud
YAML

  run run_gates
  # (a) Non-zero — never a silent degrade to the foreground default.
  [ "$status" -ne 0 ]

  # (b) NOTHING was spawned: neither gate's command ran.
  [ ! -f "$WORK/early-ran" ]
  [ ! -f "$WORK/typo-ran" ]
  [ ! -f "$REPORT" ]

  # (c) The failure names the gate, the offending value, and BOTH accepted forms.
  ERR="$(cat "$WORK/stderr.txt")"
  [[ "$ERR" == *"typo_gate"* ]]
  [[ "$ERR" == *"backgroud"* ]]
  [[ "$ERR" == *"foreground"* ]]
  [[ "$ERR" == *"background"* ]]
}
