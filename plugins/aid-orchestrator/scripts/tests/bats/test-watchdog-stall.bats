#!/usr/bin/env bats
# aid-tier: t2
# test-watchdog-stall.bats — P076 Step 6: watchdog wiring and visible stalls,
# plus the three review obligations carried into this step.
#
# WHAT IS UNDER TEST. A controller that dies mid-EXECUTE leaves its state file
# exactly where it was, so `active-runs prune` (whose criteria are file-gone /
# terminal-state) keeps that run looking healthy forever. STALLED closes that
# hole WITHOUT storing anything: it is derived at read time by one helper —
# `aid-fsm.sh active-runs stalled` — that both consumers call (the `/aid-status`
# overview render and the AUTO controller loop's liveness step).
#
# Cases:
#   1. an aged non-terminal entry is derived stalled; the map is byte-identical
#      afterwards (nothing is stored, nothing is repaired)
#   2. a fresh entry is not stalled; an aged entry whose run timeline carries a
#      recent heartbeat is not stalled either (the NEWER of the two signals
#      wins); the verdict clears itself on the next live map write
#   3. the `/aid-status` recipes — extracted from commands/aid-status.md, the
#      way that surface's own suite does it — render `STALLED?` plus the resume
#      command for a stalled entry that has a continuation artifact, and render
#      the untouched row for a live one
#   4. prune removes terminal and state-less entries and leaves a stalled one
#      alone (the byte-for-byte comparison with f007069 went when that commit's
#      libraries did; the gate baseline series of old case 5 went with P097)
#   6. AC6 — a MULTI-LINE next action is printed quoted and flagged
#
# FD-3 / process hygiene: cases that start the real gate runner reap it in
# teardown, exactly like test-resume-command.bats does.

setup() {
  export TZ=UTC
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"; export REPO_ROOT
  PLUGIN_ROOT="$REPO_ROOT/plugins/aid-orchestrator"; export PLUGIN_ROOT
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"; export FSM
  RUN_GATES="$PLUGIN_ROOT/scripts/aid-run-gates.sh"; export RUN_GATES
  DOC="$PLUGIN_ROOT/commands/aid-status.md"; export DOC
  AID_PLUGIN_PATH="$PLUGIN_ROOT"; export AID_PLUGIN_PATH

  WORK="$(mktemp -d)"; export WORK
  PROJ="$WORK/project"; export PROJ
  mkdir -p "$PROJ"

  export AID_GATE_POLL_INTERVAL_SEC=1
  export AID_GATE_HEARTBEAT_SEC=1
  export AID_RESUME_POLL_SEC=0

  EPIC="E-076-9_9"; export EPIC
  EVID=".aid-o/work/evidence/${EPIC}/R-1"; export EVID
  ARTIFACT="$PROJ/$EVID/auto_resume_required.json"; export ARTIFACT
  TIMELINE="$PROJ/$EVID/timeline.jsonl"; export TIMELINE
  JOBS="$PROJ/$EVID/jobs"; export JOBS
  ROWS="$PROJ/$EVID/gates_rows"; export ROWS
  MAP="$PROJ/.aid-o/work/active-runs.json"; export MAP
  STATE="$PROJ/$EVID/fsm-state.yaml"; export STATE
}

teardown() {
  if [[ -d "${JOBS:-/nonexistent}" ]]; then
    local d pgid
    for d in "$JOBS"/*/; do
      [[ -f "$d/job.json" ]] || continue
      pgid="$(jq -r '.pgid // empty' "$d/job.json" 2>/dev/null || true)"
      [[ "$pgid" =~ ^[1-9][0-9]*$ ]] && kill -KILL -"$pgid" 2>/dev/null || true
    done
  fi
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

# ─── fixtures ────────────────────────────────────────────────────────────

init_project() {
  mkdir -p "$PROJ/$EVID/gates" "$PROJ/.aid-o/work/runs" "$PROJ/.aid-o/config"
  printf 'stall fixture\n' > "$PROJ/README.md"
  printf '.aid-o/\n' > "$PROJ/.gitignore"
  (
    cd "$PROJ"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email stall@example.com
    git config user.name Stall
    git add README.md .gitignore
    git commit -qm "stall fixture base"
  )
}

# _state_file <epic> <run> <state> — the run's fsm-state.yaml. Its LIVE state
# is what decides "non-terminal", exactly as prune reads it.
_state_file() {
  local epic="$1" run="$2" st="$3" dir
  dir="$PROJ/.aid-o/work/evidence/${epic}/${run}"
  mkdir -p "$dir"
  {
    echo "epic_id: ${epic}"
    echo "run_id: ${run}"
    echo "state: ${st}"
  } > "$dir/fsm-state.yaml"
}

# _map_entry <epic> <run> <entry-state> <updated_at> [resume_artifact]
_map_entry() {
  local epic="$1" run="$2" st="$3" upd="$4" art="${5:-}"
  [[ -f "$MAP" ]] || echo '{}' > "$MAP"
  jq --arg e "$epic" --arg r "$run" --arg s "$st" --arg u "$upd" --arg a "$art" \
    '.[$e] = {state_file: (".aid-o/work/evidence/" + $e + "/" + $r + "/fsm-state.yaml"),
              run_id: $r, state: $s, branch: ("task/" + $e + "/main"),
              plan_id: "P076", governs_main: false, updated_at: $u,
              auto_controller: "active",
              resume_artifact: (if $a == "" then null else $a end)}' \
    "$MAP" > "$MAP.tmp" && mv "$MAP.tmp" "$MAP"
}

_iso_ago() { date -u -d "@$(( $(date -u +%s) - ${1:-0} ))" +"%Y-%m-%dT%H:%M:%SZ"; }

stalled_json() { ( cd "$PROJ" && bash "$FSM" active-runs stalled "$@" ); }

# ─── the /aid-status recipes, extracted from the doc (its own suite's rule:
#     the documented instruction IS the implementation under test) ─────────
_recipes() {
  awk '
    /^# recipe: / { inblk = 1; print; next }
    inblk && /^```$/ { inblk = 0; next }
    inblk { print }
  ' "$DOC"
}

_call() {
  local dir="$1" expr="$2" fn="${2%% *}" body; body="$(_recipes)"
  run bash -c "cd '$dir' && $body
declare -F ${fn} >/dev/null || { echo 'MISSING: ${fn} is not defined by aid-status.md' >&2; exit 1; }
$expr" 3>&-
}

# ─────────────────────────────────────────────────────────────────────────────

@test "case 1: an aged non-terminal entry is DERIVED stalled and the map is left byte-identical" {
  init_project
  _state_file "$EPIC" R-1 EXECUTE
  _map_entry "$EPIC" R-1 EXECUTE "$(_iso_ago 7200)"

  local before; before="$(sha256sum "$MAP" | cut -d' ' -f1)"

  run stalled_json
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "true" ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].reason' <<<"$output")" = "no_progress" ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].threshold_sec' <<<"$output")" = "2100" ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].idle_sec > 2100' <<<"$output")" = "true" ]
  [[ "$(jq -r --arg e "$EPIC" '.[$e].resume_command' <<<"$output")" == *"aid-fsm.sh resume ${EPIC}" ]]

  # DATA KEPT: not one byte of the map moved — the verdict is derived, never
  # stored, and this read never "repairs" anything.
  [ "$(sha256sum "$MAP" | cut -d' ' -f1)" = "$before" ]

  # The threshold is env-overridable in BOTH directions.
  run bash -c "cd '$PROJ' && AID_ACTIVE_RUN_STALL_SEC=99999 bash '$FSM' active-runs stalled"
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "false" ]

  # A run whose LIVE state is terminal is never stalled, and neither is a
  # phantom entry whose state file is gone (that is prune's own criterion).
  _state_file "$EPIC" R-1 DONE
  run stalled_json
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "false" ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].reason' <<<"$output")" = "terminal_state" ]
  rm -f "$STATE"
  run stalled_json
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "false" ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].reason' <<<"$output")" = "no_state_file" ]
}

@test "case 2: a fresh entry and a recent timeline heartbeat are NOT stalled, and the verdict clears on the next live write" {
  init_project
  _state_file "$EPIC" R-1 EXECUTE

  # (a) fresh map write → live
  _map_entry "$EPIC" R-1 EXECUTE "$(_iso_ago 5)"
  run stalled_json
  echo "$output"
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "false" ]
  [ "$(jq -r --arg e "$EPIC" '.[$e].reason' <<<"$output")" = "live" ]

  # (b) an AGED map entry whose run timeline carries a recent heartbeat: the
  # NEWER of the two signals wins, so Step 2's gate_job_heartbeat counts as
  # progress and a healthy long background wait never flags.
  _map_entry "$EPIC" R-1 EXECUTE "$(_iso_ago 7200)"
  run stalled_json
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "true" ]
  mkdir -p "$(dirname "$TIMELINE")"
  printf '{"ts":"%s","event":"gate_job_heartbeat","gate":"bg"}\n' "$(_iso_ago 10)" > "$TIMELINE"
  run stalled_json
  echo "$output"
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "false" ]

  # (c) an AGED timeline does not rescue an aged map entry
  printf '{"ts":"%s","event":"gate_job_heartbeat","gate":"bg"}\n' "$(_iso_ago 7200)" > "$TIMELINE"
  touch -d "@$(( $(date -u +%s) - 7200 ))" "$TIMELINE"
  run stalled_json
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "true" ]

  # (d) the controller wakes up and writes ONE field through the shipped map
  # writer: updated_at refreshes and the verdict flips back by itself. There is
  # no stored flag to clear.
  run bash -c "cd '$PROJ' && bash '$FSM' active-runs set '$EPIC' auto_controller active"
  [ "$status" -eq 0 ]
  run stalled_json
  echo "$output"
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "false" ]

  # --epic selects exactly one entry
  _map_entry "E-076-8_8" R-9 EXECUTE "$(_iso_ago 7200)"
  run stalled_json --epic "$EPIC"
  [ "$(jq -r 'keys | length' <<<"$output")" = "1" ]
}

@test "case 3: the /aid-status recipes render STALLED? plus the resume command for a stalled run" {
  init_project
  _state_file "$EPIC" R-1 EXECUTE
  _state_file "E-076-8_8" R-2 EXECUTE
  _map_entry "$EPIC" R-1 EXECUTE "$(_iso_ago 7200)" "$EVID/auto_resume_required.json"
  _map_entry "E-076-8_8" R-2 EXECUTE "$(_iso_ago 5)"
  mkdir -p "$(dirname "$ARTIFACT")"
  printf '{"schema":"aid-auto-resume/1"}\n' > "$ARTIFACT"

  # the derivation the render consumes agrees about which is which
  run stalled_json
  [ "$(jq -r --arg e "$EPIC" '.[$e].stalled' <<<"$output")" = "true" ]
  [ "$(jq -r '."E-076-8_8".stalled' <<<"$output")" = "false" ]

  _call "$PROJ" 'plan_epics P076'
  echo "$output"
  [ "$status" -eq 0 ]
  # the stalled run: marker on its row, recovery line beneath it
  [[ "$output" == *"${EPIC}  [EXECUTE]"*"STALLED?"* ]]
  [[ "$output" == *"aid-fsm.sh resume ${EPIC}"* ]]
  [[ "$output" == *"if a long foreground gate is running this is expected"* ]]
  # the live run keeps today's untouched row
  [[ "$output" == *"E-076-8_8  [EXECUTE]  run=R-2  branch=task/E-076-8_8/main"* ]]
  run bash -c "printf '%s\n' '$output' | grep -c 'E-076-8_8.*STALLED'"
  [ "$output" = "0" ]

  # and the derived marker disappears the moment the run shows progress —
  # nothing has to be cleared
  run bash -c "cd '$PROJ' && bash '$FSM' active-runs set '$EPIC' auto_controller active"
  [ "$status" -eq 0 ]
  _call "$PROJ" 'plan_epics P076'
  echo "$output"
  [[ "$output" != *"STALLED?"* ]]
}

@test "case 4: prune removes terminal and state-less entries and leaves a stalled one alone" {
  init_project
  # An entry per prune criterion: terminal live state, gone state file, and a
  # healthy one that must survive — plus a STALLED one, which prune must go on
  # ignoring (stall is visibility, never removal).
  _state_file "E-076-1_1" R-1 DONE
  _state_file "E-076-2_2" R-2 EXECUTE
  _state_file "E-076-4_4" R-4 EXECUTE
  _map_entry "E-076-1_1" R-1 EXECUTE "$(_iso_ago 10)"
  _map_entry "E-076-2_2" R-2 EXECUTE "$(_iso_ago 10)"
  _map_entry "E-076-3_3" R-3 EXECUTE "$(_iso_ago 10)"   # state file never created
  _map_entry "E-076-4_4" R-4 EXECUTE "$(_iso_ago 7200)" # stalled, and healthy to prune
  run bash -c "cd '$PROJ' && bash '$FSM' active-runs prune 2>&1"
  [ "$status" -eq 0 ]

  # …and what prune actually did is still the documented behaviour
  [ "$(jq 'has("E-076-1_1")' "$MAP")" = "false" ]
  [ "$(jq 'has("E-076-3_3")' "$MAP")" = "false" ]
  [ "$(jq 'has("E-076-2_2")' "$MAP")" = "true" ]
  [ "$(jq 'has("E-076-4_4")' "$MAP")" = "true" ]   # stalled ≠ prunable
}

@test "case 6: AC6 — a MULTI-LINE next action is printed quoted and flagged, never echoed verbatim" {
  init_project
  jq -n --arg e "$EPIC" \
    '{($e): {state_file: (".aid-o/work/evidence/" + $e + "/R-1/fsm-state.yaml"),
      run_id: "R-1", state: "GATES", branch: ("task/" + $e + "/main"),
      plan_id: "P076", governs_main: false, updated_at: "2026-01-01T00:00:00Z",
      auto_controller: "active", resume_artifact: null}}' > "$MAP"

  # The unit rule first: `[:space:]` admitted the newline, so a two-line string
  # returned rc 0 and was echoed verbatim.
  run bash -c "source '$FSM' >/dev/null 2>&1; _resume_render_command \$'echo one\necho two'"
  echo "rendered: $output / rc=$status"
  [ "$status" -eq 1 ]
  [[ "$output" != *$'\n'* ]]
  # a plain one-line command with spaces and tabs is still passed through
  run bash -c "source '$FSM' >/dev/null 2>&1; _resume_render_command 'bash run.sh --flag a/b.yaml'"
  [ "$status" -eq 0 ]
  [ "$output" = "bash run.sh --flag a/b.yaml" ]

  # …and end to end, through the artifact a dead run leaves behind.
  mkdir -p "$(dirname "$ARTIFACT")"
  jq -n --arg jobs "$EVID/jobs" --arg next "$(printf 'bash run-all.sh gates\nrm -rf /tmp/x')" \
    '{schema:"aid-auto-resume/1", plan_id:"P076", epic_id:"E-076-9_9", run_id:"R-1",
      job_id:"bg-attempt-1", jobs_dir:$jobs, gate:"bg",
      command_fingerprint:"deadbeef",
      expected_terminal_states:["terminal_pass","terminal_fail","timed_out","cancelled"],
      safe_next_action:$next, created_at:"2026-01-01T00:00:00Z"}' > "$ARTIFACT"

  run bash -c "cd '$PROJ' && bash '$FSM' resume '$EPIC' 2>&1"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"shown QUOTED"* ]]
  # the second line never appears at the start of a line — it cannot be pasted
  # as its own command
  run bash -c "printf '%s\n' '$output' | grep -c '^rm -rf'"
  [ "$output" = "0" ]
}
