#!/usr/bin/env bats
# test-run-mode-advice.bats — P076 Step 3: the observe-only run_mode advice.
#
# Every case drives the REAL aid-run-gates.sh over a real fixture repo and a
# real (pre-seeded) runtime-baseline file. Nothing is stubbed: the advice is
# asserted on the real timeline the runner writes, and the recommendation it
# keys on is the real library's, computed from real samples.
#
# The baseline library's own rules (lib/aid-gate-runtime-baseline.sh,
# _gbr_calc_run_mode_rec) are the only thresholds in play:
#   * fewer than 5 non-censored samples  -> no recommendation at all
#   * p95_ms > 600000 (10 min)           -> "background"
#   * otherwise                          -> "foreground"
# The three cases below sit on either side of exactly those two rules.
#
#   1. Over threshold + no declared run_mode -> exactly ONE advice event with
#      the exact, copy-pasteable edit string.
#   2. An explicit run_mode (background OR foreground) -> suppressed.
#   3. Under threshold / under-sampled -> nothing.
#   4. An unreadable baseline -> no advice and no failure (fail open).

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"
  export PLUGIN_ROOT
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"
  export RUN_GATES
  BASELINE_LIB="$PLUGIN_ROOT/scripts/lib/aid-gate-runtime-baseline.sh"
  export BASELINE_LIB

  WORK="$(mktemp -d)"
  export WORK
  PROJ="$WORK/project"
  export PROJ
  mkdir -p "$PROJ"

  # Isolated runtime-baseline store — never the real clone's .aid-o/metrics.
  export AID_GATE_BASELINE_FILE="$WORK/baseline.yaml"
  # Seed document, built up gate by gate by seed_gate below.
  SEED_JSON='{"gates":{}}'

  # Fast polling, in case a case declares a background gate (case 2 does).
  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1

  EVID=".aid-o/work/evidence/E-ADV/R-1"
  export EVID
  REPORT="$PROJ/$EVID/gates/gates_report.json"
  export REPORT
  TIMELINE="$PROJ/$EVID/timeline.jsonl"
  export TIMELINE
  JOBS="$PROJ/$EVID/jobs"
  export JOBS
}

teardown() {
  # Case 2 declares a background gate, whose supervisor is setsid-detached and
  # group-owned: it outlives its caller by design, so the suite that started it
  # is the one that has to reap it (same reason, same loop, as the Step 2
  # background suite's own teardown).
  if [[ -d "${JOBS:-/nonexistent}" ]]; then
    local d pgid
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      pgid="$(jq -r '.pgid // empty' "$d/job.json" 2>/dev/null || true)"
      [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
    done
  fi
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
  return 0
}

init_project() {
  mkdir -p "$PROJ/$EVID/gates"
  git -C "$PROJ" init -q
  git -C "$PROJ" config user.email advice@example.com
  git -C "$PROJ" config user.name Advice
  printf 'advice fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  git -C "$PROJ" add README.md .gitignore
  git -C "$PROJ" commit -qm "advice fixture base"
}

run_gates() {
  ( cd "$PROJ" && "$RUN_GATES" run-all exec.yaml E-ADV R-1 \
      --report-file "$EVID/gates/gates_report.json" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt" )
}

# seed_gate <gate> <command_template> <sample_count> <duration_ms>
# Writes a REAL baseline series for the gate: the real command fingerprint (so
# the runner's own sample APPENDS instead of resetting the series) plus N
# non-censored samples of the given duration.
seed_gate() {
  local gate="$1" cmd="$2" n="$3" dur="$4" fp samples i
  fp="$(bash "$BASELINE_LIB" fingerprint "$gate" "$cmd")"
  samples='[]'
  for ((i = 0; i < n; i++)); do
    samples="$(jq -c --argjson d "$dur" \
      '. + [{duration_ms:$d, exit_code:0, timeout_seconds:3600, censored:false, recorded_at:"2026-08-01T00:00:00.000Z"}]' \
      <<<"$samples")"
  done
  SEED_JSON="$(jq -c --arg g "$gate" --arg fp "$fp" --arg cmd "$cmd" --argjson s "$samples" \
    '.gates[$g] = {command_fingerprint:$fp, command_template:$cmd, recent_samples:$s}' \
    <<<"$SEED_JSON")"
  yq -p=json -o=yaml '.' <<<"$SEED_JSON" > "$AID_GATE_BASELINE_FILE"
}

# advice_count — how many advice events this run left on the timeline.
advice_count() {
  jq -s '[.[] | select(.event == "gate_run_mode_advice")] | length' "$TIMELINE"
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: an over-threshold gate with no declared run_mode gets exactly one advice event with the exact edit" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  slow_suite:
    command: "echo slow-suite-ok"
    required: true
    timeout_seconds: 3600
    max_retries: 2
YAML
  # 5 non-censored samples at 15 min: over the 10-min p95 rule, at the 5-sample
  # sufficiency rule. The runner's own fast sample makes it 6 — nearest-rank p95
  # over [fast, 900000 x5] is still 900000.
  seed_gate slow_suite "echo slow-suite-ok" 5 900000

  run run_gates
  [ "$status" -eq 0 ]

  # (a) The recommendation really is "background" — the premise, not assumed.
  run jq -r '.gates.slow_suite.runtime_baseline.run_mode_recommended' "$REPORT"
  [ "$output" = "background" ]

  # (b) EXACTLY one advice event — not one per attempt, not one per retry.
  run advice_count
  [ "$output" = "1" ]

  # (c) The exact, copy-pasteable edit string — no absolute paths, gate name only.
  run jq -sr '[.[] | select(.event == "gate_run_mode_advice")][0].edit' "$TIMELINE"
  [ "$output" = "set gates.slow_suite.run_mode: background in .aid-o/config/execution.yaml" ]
  run jq -sr '[.[] | select(.event == "gate_run_mode_advice")][0].gate' "$TIMELINE"
  [ "$output" = "slow_suite" ]
  run jq -sr '[.[] | select(.event == "gate_run_mode_advice")][0].p95_ms' "$TIMELINE"
  [ "$output" -gt 600000 ]

  # (d) Observe-only: the gate still ran in the foreground — no job record.
  run jq -r '.gates.slow_suite.result' "$REPORT"
  [ "$output" = "pass" ]
  run jq -r '.gates.slow_suite.job_id // "none"' "$REPORT"
  [ "$output" = "none" ]
  [ ! -d "$PROJ/$EVID/jobs/slow_suite-attempt-1" ]
}

@test "case 2: an explicit run_mode (background OR foreground) suppresses the advice" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  declared_bg:
    command: "echo declared-bg-ok"
    required: false
    timeout_seconds: 3600
  declared_fg:
    command: "echo declared-fg-ok"
    required: false
    timeout_seconds: 3600
YAML
  # Both gates are seeded OVER the threshold, so the only thing that can keep
  # them quiet is the declaration itself.
  seed_gate declared_bg "echo declared-bg-ok" 5 900000
  seed_gate declared_fg "echo declared-fg-ok" 5 900000

  # Declared only now, so the seeded fingerprints (command-only) still match.
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  declared_bg:
    command: "echo declared-bg-ok"
    required: false
    timeout_seconds: 3600
    run_mode: background
  declared_fg:
    command: "echo declared-fg-ok"
    required: false
    timeout_seconds: 3600
    run_mode: foreground
YAML

  run run_gates
  [ "$status" -eq 0 ]

  # (a) Both gates really are over threshold — the suppression is the point.
  run jq -r '.gates.declared_bg.runtime_baseline.run_mode_recommended' "$REPORT"
  [ "$output" = "background" ]
  run jq -r '.gates.declared_fg.runtime_baseline.run_mode_recommended' "$REPORT"
  [ "$output" = "background" ]

  # (b) And neither produced advice.
  run advice_count
  [ "$output" = "0" ]
}

@test "case 3: under-threshold and under-sampled gates emit nothing" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  quick_suite:
    command: "echo quick-ok"
    required: false
    timeout_seconds: 3600
  young_suite:
    command: "echo young-ok"
    required: false
    timeout_seconds: 3600
YAML
  # quick_suite: plenty of samples, p95 well under the 10-min rule.
  seed_gate quick_suite "echo quick-ok" 8 60000
  # young_suite: way over the duration rule, but only 3 + this run's 1 = 4
  # non-censored samples, under the 5-sample sufficiency rule.
  seed_gate young_suite "echo young-ok" 3 900000

  run run_gates
  [ "$status" -eq 0 ]

  run jq -r '.gates.quick_suite.runtime_baseline.run_mode_recommended' "$REPORT"
  [ "$output" = "foreground" ]
  run jq -r '.gates.young_suite.runtime_baseline.non_censored_samples_count' "$REPORT"
  [ "$output" -eq 4 ]
  run jq -r '.gates.young_suite.runtime_baseline.run_mode_recommended' "$REPORT"
  [ "$output" = "null" ]

  run advice_count
  [ "$output" = "0" ]
}

@test "case 4: an unreadable baseline yields no advice and no failure" {
  init_project
  cat > "$PROJ/exec.yaml" <<'YAML'
gates:
  some_suite:
    command: "echo some-ok"
    required: true
    timeout_seconds: 3600
YAML
  # Not YAML at all, and not writable either — the library must fail open.
  printf '\t: [unbalanced\n' > "$AID_GATE_BASELINE_FILE"

  run run_gates
  [ "$status" -eq 0 ]
  run jq -r '.gates.some_suite.result' "$REPORT"
  [ "$output" = "pass" ]
  run advice_count
  [ "$output" = "0" ]
}
