#!/usr/bin/env bats
# aid-tier: t1
# test-continue-spawn.bats — P090 Step 6.
#
# THE STUB IS LOAD-BEARING. `claude` is replaced on PATH by a script that writes
# a marker file, and every case that expects a spawn INSISTS on that marker. If
# PATH ever drifted and the suite reached the real binary, these cases must go
# red rather than quietly pass — a suite that silently launches real sessions
# runs on the merge path and in the nightly, and would cost money and minutes on
# every single run.
#
# What is measured here is the DECISION and the RECORD: switched off, switched
# on, capped, already running, bad configuration, and the self-exclusion that
# keeps a chain longer than one. The real `claude` is not the subject.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_TEST_MODE=1
  CONTINUE="$AID_PLUGIN_PATH/scripts/aid-plan-continue.sh"
  QW="$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"
  TEST_TMPDIR="$(mktemp -d)"; export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  GUIDE="$ROOT/.aid-o/work/evidence/P090/continue-state.json"
  JOBS="$ROOT/.aid-o/work/jobs"
  MARKER="$TEST_TMPDIR/claude-was-called"
  mkdir -p "$ROOT/.aid-o/config"
  git init -q -b main "$ROOT"
  git -C "$ROOT" config user.email t@t
  git -C "$ROOT" config user.name T
  echo init > "$ROOT/init.txt"
  git -C "$ROOT" add init.txt
  git -C "$ROOT" commit -qm initial
  git -C "$ROOT" branch plan/P090 main

  # The stub. It records its argv and exits 0 — it never contacts anything.
  STUBDIR="$TEST_TMPDIR/bin"
  mkdir -p "$STUBDIR"
  cat > "$STUBDIR/claude" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$MARKER"
printf 'AID_JOB_ID=%s\n' "\${AID_JOB_ID:-<unset>}" >> "$MARKER"
exit 0
STUB
  chmod +x "$STUBDIR/claude"
  PATH="$STUBDIR:$PATH"
  export PATH
}

teardown() {
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_continue() { run bash "$CONTINUE" "$@" --project-root "$ROOT"; }

_plan_state() {
  mkdir -p "$ROOT/.aid-o/work/plan-state/P090"
  cat > "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml" <<'YML'
plan_id: P090
plan_state: OPEN
mode: plan_branch
plan_branch: plan/P090
target_branch: main
created_at: "2026-08-27T00:00:00Z"
current_operation: null
plan_final_attempt: 0
autonomy: auto
YML
}

# A fixture in which link 4 (`epic-start`) SUCCEEDS without a real plan-start:
# a stub CLI whose epic-start is a no-op, so this suite measures link 5 and
# nothing else. Every other link is the real code.
_stub_plan_fsm() {
  local sdir="$TEST_TMPDIR/fsm"
  mkdir -p "$sdir"
  ln -sfn "$AID_PLUGIN_PATH/scripts/lib" "$sdir/lib"
  ln -sfn "$AID_PLUGIN_PATH/scripts/aid-job.sh" "$sdir/aid-job.sh"
  cp "$AID_PLUGIN_PATH/scripts/aid-plan-continue.sh" "$sdir/aid-plan-continue.sh"
  sed 's|    epic-start) cmd_epic_start "$@" ;;|    epic-start) echo "stub epic-start $*"; exit 0 ;;|' \
    "$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh" > "$sdir/aid-plan-fsm.sh"
  CONTINUE="$sdir/aid-plan-continue.sh"
}

_merged_epic() {
  local epic_id="$1"
  git -C "$ROOT" branch "task/${epic_id}/main" plan/P090
  git -C "$ROOT" checkout -q "task/${epic_id}/main"
  echo "$epic_id" > "$ROOT/work-${epic_id}.txt"
  git -C "$ROOT" add "work-${epic_id}.txt"
  git -C "$ROOT" commit -qm "${epic_id}: work"
  git -C "$ROOT" checkout -q main
  git -C "$ROOT" branch -f plan/P090 "task/${epic_id}/main"
}

_queue() {
  cat > "$QUEUE" <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: running
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []

  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []
YAML
}

_config() { printf 'autonomy:\n%s\n' "$1" > "$ROOT/.aid-o/config/project.yaml"; }
_permissions_auto() { printf 'autonomous_mode: true\n' > "$ROOT/.aid-o/config/permissions.yaml"; }

_ready() { _plan_state; _stub_plan_fsm; _merged_epic E-090-1_2; _queue; }

# ───────────────────────────────────────────────────────────────────────────
@test "AC19: with the switch off — the default — nothing is started and the state is exactly as before Step 6" {
  _ready
  _permissions_auto           # deliberately present: it is not what decides
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"claim:   E-090-2_2"* ]]
  [[ "$output" == *"spawn:   off (autonomy.spawn_next_epic is false — the default)"* ]]
  [ ! -f "$MARKER" ]
  [ ! -d "$JOBS" ] || [ -z "$(ls -A "$JOBS")" ]
  # The plan still moved: that is the pre-Step-6 behaviour, unchanged.
  [ "$(bash "$QW" get E-090-2_2 status --queue "$QUEUE" --project-root "$ROOT")" = "running" ]
}

@test "AC20: switched on, exactly one supervised job is started, for exactly the EPIC that was claimed" {
  _ready
  _permissions_auto
  _config '  spawn_next_epic: true'
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"spawn:   started p090-P090-E-090-2_2-1 for E-090-2_2"* ]]

  # The stub really ran — and with the slash form AC21c's experiment chose.
  [ -f "$MARKER" ]
  grep -q -- '-p /aid-run --auto --epic E-090-2_2' "$MARKER"
  # Exactly one job directory, and it is the pre-allocated id.
  run bash -c 'ls "$1" | wc -l' _ "$JOBS"
  [ "$output" = "1" ]
  [ -d "$JOBS/p090-P090-E-090-2_2-1" ]

  # …and the guidance carries what a later `collect` needs.
  run jq -r '[.job_id, (.jobs_dir | test("/.aid-o/work/jobs$") | tostring), (.job_fingerprint|length > 0|tostring), (.spawned_count|tostring)] | join("|")' "$GUIDE"
  [ "$output" = "p090-P090-E-090-2_2-1|true|true|1" ]
}

@test "AC21d: the spawned session is handed its own AID_JOB_ID, and that id is excluded from the running check" {
  # The chain would otherwise have length one: the session started here reaches
  # its own merge, calls this script again, and sees as 'a job already running'
  # the job it is running INSIDE. Nothing would restart it — aid-job.sh is a
  # supervisor, not a daemon.
  _ready
  _permissions_auto
  _config '  spawn_next_epic: true'
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  grep -q 'AID_JOB_ID=p090-P090-E-090-2_2-1' "$MARKER"

  # Now play the second link of the chain: a run INSIDE that job, whose
  # guidance names it. It must not refuse on account of itself.
  _merged_epic E-090-2_2
  bash "$QW" set-status E-090-2_2 running --queue "$QUEUE" --project-root "$ROOT" >/dev/null
  cat >> "$QUEUE" <<'YAML'

  - epic_id: E-090-3_2
    status: pending
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []
YAML
  # Pretend the first job is still alive by leaving its record in place; what
  # decides is that AID_JOB_ID matches it.
  AID_JOB_ID=p090-P090-E-090-2_2-1 _continue P090 E-090-2_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"claim:   E-090-3_2"* ]]
  [[ "$output" != *"is still alive"* ]]
  grep -q -- '-p /aid-run --auto --epic E-090-3_2' "$MARKER"
}

@test "AC21: the cap stops the chain, and says how many it started" {
  _ready
  _permissions_auto
  _config '  spawn_next_epic: true
  max_spawned_epics: 1'
  mkdir -p "$(dirname "$GUIDE")"
  jq -n '{schema:"aid-plan-continue/1", plan_id:"P090", last_completed_epic:"E-090-0_2",
          last_result:"", next_epic:"", at:"2026-08-27T00:00:00Z",
          job_id:"", jobs_dir:"", job_fingerprint:"", spawned_count:1}' > "$GUIDE"

  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"cap reached"* ]]
  [[ "$output" == *"already started 1 session(s)"* ]]
  [[ "$output" == *"autonomy.max_spawned_epics is 1"* ]]
  [ ! -f "$MARKER" ]
  # A cap is a normal end, not a failure — and the EPIC is still claimed.
  [ "$(bash "$QW" get E-090-2_2 status --queue "$QUEUE" --project-root "$ROOT")" = "running" ]
  # The count survives into the next guidance: a cap that resets on restart is no cap.
  run jq -r '.spawned_count' "$GUIDE"
  [ "$output" = "1" ]
}

@test "AC21: a job of this plan that is still alive stops a second one" {
  _ready
  _permissions_auto
  _config '  spawn_next_epic: true'
  # A job record whose process is this very shell: alive, and not ours.
  mkdir -p "$JOBS/older-job"
  jq -n --arg pid "$$" --arg st "$(awk '{print $22}' "/proc/$$/stat")" \
     '{id:"older-job", state:"running", pid:($pid|tonumber), proc_starttime:$st,
       start_head:"x", start_tree:"y"}' > "$JOBS/older-job/job.json"
  mkdir -p "$(dirname "$GUIDE")"
  jq -n --arg jd "$JOBS" '{schema:"aid-plan-continue/1", plan_id:"P090",
      last_completed_epic:"E-090-0_2", last_result:"", next_epic:"",
      at:"2026-08-27T00:00:00Z", job_id:"older-job", jobs_dir:$jd,
      job_fingerprint:"", spawned_count:0}' > "$GUIDE"

  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"job older-job for this plan is still alive"* ]]
  [ ! -f "$MARKER" ]
}

@test "AC21b: a missing configuration defaults; a broken one is an error naming the key" {
  _ready
  _permissions_auto
  # No project.yaml at all → the documented default (off), and it says so.
  _continue P090 E-090-1_2
  [[ "$output" == *"spawn_next_epic is false — the default"* ]]

  # A present but unusable value is NEVER silently defaulted: that is how a cap
  # of 3 becomes no cap.
  #
  # The guidance is cleared between attempts and the claim is undone, because
  # that is the state a real retry starts from: the run above claimed
  # E-090-2_2 and recorded it as in flight, and re-running the SAME finished
  # EPIC against that record is (correctly) refused as out of sequence.
  rm -f "$GUIDE"
  _config '  spawn_next_epic: maybe'
  bash "$QW" set-status E-090-2_2 pending --queue "$QUEUE" --project-root "$ROOT" >/dev/null
  _continue P090 E-090-1_2
  [ "$status" -eq 4 ]
  [[ "$output" == *"autonomy.spawn_next_epic"* ]]
  [[ "$output" == *"must be true or false"* ]]
  [ ! -f "$MARKER" ]

  rm -f "$GUIDE"
  _config '  spawn_next_epic: true
  max_spawned_epics: 0'
  bash "$QW" set-status E-090-2_2 pending --queue "$QUEUE" --project-root "$ROOT" >/dev/null
  _continue P090 E-090-1_2
  [ "$status" -eq 4 ]
  [[ "$output" == *"autonomy.max_spawned_epics"* ]]
  [[ "$output" == *"at least 1"* ]]
  [ ! -f "$MARKER" ]
}

@test "AC21b: --spawn and --no-spawn override the configuration, in both directions" {
  _ready
  _permissions_auto
  # config off, flag on → it starts
  _continue P090 E-090-1_2 --spawn
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
  [[ "$output" == *"spawn:   started"* ]]

  # config on, flag off → it does not
  rm -f "$MARKER"
  _merged_epic E-090-2_2
  cat >> "$QUEUE" <<'YAML'

  - epic_id: E-090-3_2
    status: pending
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []
YAML
  _config '  spawn_next_epic: true'
  _continue P090 E-090-2_2 --no-spawn
  [ "$status" -eq 0 ]
  [[ "$output" == *"spawn:   off (--no-spawn)"* ]]
  [ ! -f "$MARKER" ]
}

@test "spawning without autonomous_mode is refused BEFORE anything starts, and the EPIC stays claimed" {
  _ready
  _config '  spawn_next_epic: true'
  # permissions.yaml absent — and a `false` reads the same way.
  _continue P090 E-090-1_2
  [ "$status" -eq 4 ]
  [[ "$output" == *"does not say 'autonomous_mode: true'"* ]]
  [ ! -f "$MARKER" ]
  [ "$(bash "$QW" get E-090-2_2 status --queue "$QUEUE" --project-root "$ROOT")" = "running" ]

  rm -f "$GUIDE"
  printf 'autonomous_mode: "true"\n' > "$ROOT/.aid-o/config/permissions.yaml"
  bash "$QW" set-status E-090-2_2 pending --queue "$QUEUE" --project-root "$ROOT" >/dev/null
  _continue P090 E-090-1_2
  [ "$status" -eq 4 ]
  [[ "$output" == *"does not say 'autonomous_mode: true'"* ]]
  [ ! -f "$MARKER" ]
}

@test "AC21c: the prompt form is the one the recorded experiment chose" {
  # The plan refused to ASSUME that a slash command under `claude -p` is
  # dispatched rather than echoed as prose, and prepared a fallback sentence in
  # case it was not. One run decided it — `claude -p "/aid-help"` answered with
  # the skill's own output, 44 matches of `/aid-[a-z-]*` against a declared
  # predicate of 2 — so the slash form is what ships.
  #
  # THIS CASE DOES NOT ASSERT THE RAW TRANSCRIPT. It lives under `.aid-o/`,
  # which is gitignored, so a suite that required it would be red in every
  # checkout but the author's. What is asserted is what is tracked: the code
  # sends the chosen form, the fallback is absent, and the verdict is written
  # down where a reader will find it.
  local cont="$AID_PLUGIN_PATH/scripts/aid-plan-continue.sh"
  grep -q 'local prompt="/aid-run --auto --epic ${epic_id}"' "$cont"

  # `--auto --epic`, never the bare form: bare `/aid-run <epic>` is MANUAL mode,
  # a session recorded manual would not continue the plan after its own merge,
  # and the chain would stop — a second time, by another route.
  # Every `/aid-run` this file can send carries `--auto --epic`; none is bare.
  run bash -c 'grep -o "/aid-run[^\"]*" "$1" | grep -vc -- "--auto --epic" || true' _ "$cont"
  [ "$output" = "0" ]

  # The verdict is recorded in a tracked file, not only in the ignored evidence.
  grep -q 'aid-run --auto --epic' "$AID_PLUGIN_PATH/../../docs/extending-aid.md"
}
