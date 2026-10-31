#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-step-land.sh
# Taking a step over in the background (AID 3.11.0). Defects it catches: the plan's branch moving before the
# step's checks passed, a command criterion left out or run with another command, a failed takeover leaving the
# step's tree off its branch, a refused second takeover overwriting the running one's record, and the script
# fixing anything on its own (scope, contract, files).

load test-helpers.bash

setup() {
  setup_test_evidence_dir E-900-1_1 R-E900-1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1
  LAND="$AID_PLUGIN_PATH/scripts/aid-step-land.sh"; FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-dispatch-contract.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-parallel-dispatch.sh"
  printf '.aid-o/\n.aid-worktrees/\n' > .gitignore; git add .gitignore; git commit -qm ignore
  git checkout -q -b task/E-900-1_1/main
  _plan '`test -f a.txt`'
  printf 'epic_id: E-900-1_1\nrun_id: R-E900-1\nstate: EXECUTE\ncurrent_step: 0\ntotal_steps: 1\n' > "$TEST_EVIDENCE_DIR/fsm-state.yaml"
  S="$TEST_EVIDENCE_DIR/fsm-state.yaml"; D="$TEST_EVIDENCE_DIR/steps/step_1_backend"; REC="$D/land.json"
}
teardown() { teardown_test_evidence_dir; }

# _plan <AC1 command> — one step writing a.txt; AC1 is a command criterion, AC2 is not
_plan() {
  jq -n --arg ac "$1 passes." '{steps: [{id: "step_1_backend", role: "backend", objective: "write a",
    outputs: ["Create: `a.txt` — a"], allowed_paths: ["a.txt"],
    acceptance_criteria: [$ac, "The file says hello (reviewed)."]}], dependencies: []}' > "$TEST_EVIDENCE_DIR/plan.json"
}
# _agent <tree> [content] — the agent's work in <tree> and its output.md with the aid-return block
_agent() {
  mkdir -p "$D"
  aid_dispatch_contract_build "$TEST_EVIDENCE_DIR/plan.json" 0 "$D/contract.json" "$TEST_EVIDENCE_DIR"
  printf '%s\n' "${2:-hello}" > "$1/a.txt"
  { echo "done"; echo '```aid-return'
    jq -nc --arg v "$(jq -r .version "$D/contract.json")" '{contract_version: $v, changed_files: ["a.txt"], gates: [], step_status: "done"}'
    echo '```'; } > "$D/output.md"
}
# _wave — the step's own tree on step/<id>, as a concurrent wave dispatches it
_wave() { WT="$(aid_parallel_step_worktree "$PWD" step_1_backend HEAD .aid-worktrees)"; }

@test "serial: validated, committed, checked and recorded as landed" {
  _agent .
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt'
  [ "$status" -eq 0 ]; [[ "$output" == *"landed"* ]]
  [ "$(git show --name-only --format= HEAD)" = "a.txt" ]
  [ "$(jq -r '.status, .path, .checks[0].ac, .checks[0].exit' "$REC" | tr '\n' ' ')" = "landed serial 1 0 " ]
  [ "$(jq -r .landed_sha "$REC")" = "$(git rev-parse HEAD)" ]
  [ "$(jq -r .return_sha256 "$REC")" = "$(sha256sum "$D/return.json" | cut -d' ' -f1)" ]
}

@test "a command criterion without its check, another command or a non-command criterion is refused before anything changes" {
  _agent .; before="$(git rev-parse HEAD)"
  run bash "$LAND" "$S" 0
  [ "$status" -eq 1 ]; [[ "$output" == *"AC1 is a command criterion and has no --check"* ]]
  run bash "$LAND" "$S" 0 --check '1:test -e a.txt'
  [ "$status" -eq 1 ]; [[ "$output" == *"the command differs from the plan's"* ]]
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt' --check '2:true'
  [ "$status" -eq 1 ]; [[ "$output" == *"AC2 is not a command criterion"* ]]
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt' --check '1:test -f a.txt'
  [ "$status" -eq 1 ]; [[ "$output" == *"AC1 is given twice"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]; [ -n "$(git status --porcelain a.txt)" ]
}

@test "the environment goes in --env, the command stays the plan's" {
  _plan '`test "$GREETING" = hi`'; _agent .
  run bash "$LAND" "$S" 0 --check '1:test "$GREETING" = hi' --env GREETING=hi
  [ "$status" -eq 0 ]; [ "$(jq -r '.env[0]' "$REC")" = "GREETING=hi" ]
}

@test "serial: a failing check is recorded with its output; the commit stays as before 3.11, the step does not land" {
  _plan '`grep -q bye a.txt`'; _agent .
  run bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt'
  [ "$status" -eq 1 ]
  [ "$(jq -r '.status, .checks[0].exit' "$REC" | tr '\n' ' ')" = "check_failed 1 " ]
  [ -f "$(jq -r '.checks[0].log' "$REC")" ]
}

@test "a check over its time limit is stopped and recorded as timed out" {
  _plan '`sleep 30`'; _agent .
  run timeout 20 bash "$LAND" "$S" 0 --check '1:sleep 30' --timeout 1
  [ "$status" -eq 1 ]
  [ "$(jq -r '.status, .checks[0].timed_out' "$REC" | tr '\n' ' ')" = "check_failed true " ]
}

@test "wave: the plan's branch moves only after the checks, to a merge whose first parent is the plan" {
  _wave; base="$(git rev-parse HEAD)"; _agent "$WT"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt'
  [ "$status" -eq 0 ]
  [ "$(jq -r .path "$REC")" = wave ]
  head="$(git rev-parse HEAD)"; [ "$head" = "$(jq -r .landed_sha "$REC")" ]
  [ "$(git rev-parse "$head^1")" = "$base" ]
  [ "$(git rev-parse "$head^2")" = "$(jq -r .step_sha "$REC")" ]
  [ "$(git log -1 --format=%s)" = "Merge branch 'step/step_1_backend' into task/E-900-1_1/main" ]
  [ ! -d "$WT" ]; [ -f a.txt ]
}

@test "wave: a failing check leaves the plan's branch where it was and the step's tree on its branch, clean" {
  _plan '`grep -q bye a.txt`'; _wave; base="$(git rev-parse HEAD)"; _agent "$WT"
  run bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt'
  [ "$status" -eq 1 ]; [ "$(jq -r .status "$REC")" = check_failed ]
  [ "$(git rev-parse HEAD)" = "$base" ]
  [ "$(git -C "$WT" branch --show-current)" = step/step_1_backend ]
  [ -z "$(git -C "$WT" status --porcelain)" ]
  # the step is fixed on its branch and taken over again: it lands
  printf 'bye\n' > "$WT/a.txt"; git -C "$WT" commit -qam fix
  run bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt'
  [ "$status" -eq 0 ]; [ "$(git show HEAD:a.txt)" = bye ]
}

@test "wave: a conflict with the plan's HEAD is aborted, named, and changes nothing" {
  _wave; _agent "$WT"
  printf 'other\n' > a.txt; git add a.txt; git commit -qm "the plan moved"; moved="$(git rev-parse HEAD)"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt'
  [ "$status" -eq 1 ]
  [ "$(jq -r .status "$REC")" = merge_conflict ]; [[ "$(jq -r .reason "$REC")" == *"a.txt"* ]]
  [ "$(git rev-parse HEAD)" = "$moved" ]
  [ "$(git -C "$WT" branch --show-current)" = step/step_1_backend ]
}

@test "wave: when the plan's HEAD moves during the checks, nothing is fast-forwarded" {
  _plan '`git -C ../.. commit -q --allow-empty -m sneaked`'; _wave; base="$(git rev-parse HEAD)"; _agent "$WT"
  run bash "$LAND" "$S" 0 --check '1:git -C ../.. commit -q --allow-empty -m sneaked'
  [ "$status" -eq 1 ]; [ "$(jq -r .status "$REC")" = base_moved ]
  [ "$(git log -1 --format=%s)" = sneaked ]; [ "$(git rev-parse HEAD^)" = "$base" ]
  [ "$(git -C "$WT" branch --show-current)" = step/step_1_backend ]
}

@test "a second takeover while one holds the lock is refused and leaves the running one's record alone" {
  _agent .
  mkdir -p .aid-o/work/locks
  ( exec 9>".aid-o/work/locks/land-E-900-1_1.lock"; flock -x 9; sleep 4 ) &
  sleep 1
  printf '{"status":"running","marker":"first"}\n' > "$REC"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt' --lock-wait 1
  [ "$status" -eq 1 ]; [[ "$output" == *"another takeover"* ]]
  [ "$(jq -r .marker "$REC")" = first ]
  wait
}

@test "steps are taken over in order: another step than the current one is refused" {
  _agent .
  printf 'epic_id: E-900-1_1\nrun_id: R-E900-1\nstate: EXECUTE\ncurrent_step: 1\ntotal_steps: 2\n' > "$S"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt'
  [ "$status" -eq 1 ]; [[ "$output" == *"current step is 1, not 0"* ]]
}

@test "--recheck after a fixer's commit: the same checks on HEAD, a new landed record bound to HEAD" {
  _agent .; bash "$LAND" "$S" 0 --check '1:test -f a.txt' >/dev/null
  first="$(jq -r .landed_sha "$REC")"
  printf 'fixed\n' > a.txt; git commit -qam "review fix"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt' --recheck
  [ "$status" -eq 0 ]
  [ "$(jq -r '.path, .base_sha, .landed_sha' "$REC" | tr '\n' ' ')" = "recheck ${first} $(git rev-parse HEAD) " ]
}

@test "--recheck that fails can be run again after the next fix" {
  _plan '`grep -q bye a.txt`'; _agent . bye; bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt' >/dev/null
  first="$(jq -r .landed_sha "$REC")"
  printf 'oops\n' > a.txt; git commit -qam "review fix breaks it"
  run bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt' --recheck
  [ "$status" -eq 1 ]; [ "$(jq -r '.status, .base_sha' "$REC" | tr '\n' ' ')" = "check_failed ${first} " ]
  printf 'bye\n' > a.txt; git commit -qam "fixed again"
  run bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt' --recheck
  [ "$status" -eq 0 ]; [ "$(jq -r .landed_sha "$REC")" = "$(git rev-parse HEAD)" ]
}

@test "serial: after a failed check the role fixes on top of the step's commit and --recheck lands it" {
  _plan '`grep -q bye a.txt`'; _agent .
  bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt' >/dev/null || true
  step="$(jq -r .step_sha "$REC")"; [ "$(jq -r .status "$REC")" = check_failed ]
  printf 'bye\n' > a.txt; git commit -qam "the role's fix"
  run bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt' --recheck
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status, .base_sha, .landed_sha' "$REC" | tr '\n' ' ')" = "landed ${step} $(git rev-parse HEAD) " ]
}

@test "a run whose timeline cannot be written does not take over: nothing committed, nothing landed" {
  _agent .; before="$(git rev-parse HEAD)"; mkdir "$TEST_EVIDENCE_DIR/timeline.jsonl"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt'
  [ "$status" -eq 1 ]; [[ "$output" == *"timeline"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]; [ "$(jq -r .status "$REC")" != landed ]
}

@test "the script changes nothing but the commit and the merge: contract, plan, state and scope stay as they were" {
  _plan '`grep -q bye a.txt`'; _wave; _agent "$WT"
  sums() { sha256sum "$D/contract.json" "$TEST_EVIDENCE_DIR/plan.json" "$S"; }
  before="$(sums)"
  bash "$LAND" "$S" 0 --check '1:grep -q bye a.txt' >/dev/null || true
  [ "$(sums)" = "$before" ]
  git -C "$WT" diff --quiet; git diff --quiet
}

@test "a takeover stopped by a signal mid-check: the check's group dies, the tree goes back, the record says interrupted, the lock is free" {
  _plan '`sleep 30`'; _wave; base="$(git rev-parse HEAD)"; _agent "$WT"
  bash "$LAND" "$S" 0 --check '1:sleep 30' > "$BATS_TEST_TMPDIR/out" 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do pgrep -f "^sleep 30$" >/dev/null && break; sleep 0.2; done
  kill -TERM "$pid"; wait "$pid" || true
  [ "$(jq -r .status "$REC")" = interrupted ]
  ! pgrep -f "^sleep 30$" >/dev/null
  [ "$(git rev-parse HEAD)" = "$base" ]
  [ "$(git -C "$WT" branch --show-current)" = step/step_1_backend ]
  _plan '`test -n ok`'
  run bash "$LAND" "$S" 0 --check '1:test -n ok' --lock-wait 1
  [ "$status" -eq 0 ]
}

@test "a takeover killed with -9 left the step's tree detached: the next takeover repairs it and lands" {
  _wave; _agent "$WT"; git -C "$WT" add a.txt; git -C "$WT" commit -qm "the step"
  git -C "$WT" checkout -q --detach HEAD
  printf '{"status":"running","pid":1}\n' > "$REC"
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt'
  [ "$status" -eq 0 ]; [ "$(jq -r .status "$REC")" = landed ]
}

@test "a check that rewrites a tracked file leaves the step's tree clean on its branch" {
  _plan '`echo zz > a.txt; false`'; _wave; _agent "$WT"
  run bash "$LAND" "$S" 0 --check '1:echo zz > a.txt; false'
  [ "$status" -eq 1 ]
  [ "$(git -C "$WT" branch --show-current)" = step/step_1_backend ]
  [ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ]
  [ "$(git -C "$WT" show HEAD:a.txt)" = hello ]
}

@test "a check that leaves a process running neither holds the takeover nor survives it" {
  _plan '`(sleep 47 &); true`'; _agent .
  t0=$(date +%s)
  run bash "$LAND" "$S" 0 --check '1:(sleep 47 &); true' --timeout 3
  [ "$status" -eq 0 ]
  (( $(date +%s) - t0 < 10 ))
  sleep 0.5; ! pgrep -f "^sleep 47$"
}

@test "a check that passes but changes a tracked file is not a pass" {
  _plan '`echo zz > a.txt`'; _wave; base="$(git rev-parse HEAD)"; _agent "$WT"
  run bash "$LAND" "$S" 0 --check '1:echo zz > a.txt'
  [ "$status" -eq 1 ]; [[ "$(jq -r .reason "$REC")" == *"changed tracked files: a.txt"* ]]
  [ "$(git rev-parse HEAD)" = "$base" ]
  [ -z "$(git -C "$WT" status --porcelain --untracked-files=no)" ]
}

@test "a takeover killed with -9 mid-check: the next one stops the orphaned check before touching the tree" {
  _plan '`sleep 53`'; _wave; _agent "$WT"
  bash "$LAND" "$S" 0 --check '1:sleep 53' >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 50); do pgrep -f "^sleep 53$" >/dev/null && [ -n "$(jq -r '.check_token // ""' "$REC" 2>/dev/null)" ] && break; sleep 0.2; done
  kill -9 "$pid"; wait "$pid" || true
  pgrep -f "^sleep 53$" >/dev/null                       # the orphan still runs
  _plan '`test -n ok`'
  run bash "$LAND" "$S" 0 --check '1:test -n ok' --lock-wait 2
  [ "$status" -eq 0 ]
  ! pgrep -f "^sleep 53$"
}

@test "a check that commits does not land: HEAD is checked against the record before landed" {
  _plan '`git commit -q --allow-empty -m sneaked`'; _agent .
  run bash "$LAND" "$S" 0 --check '1:git commit -q --allow-empty -m sneaked'
  [ "$status" -eq 1 ]; [ "$(jq -r .status "$REC")" = base_moved ]
}

@test "a check that ignores TERM is killed with the rest of its group" {
  _plan '`(trap "" TERM; sleep 59) & true`'; _agent .
  run bash "$LAND" "$S" 0 --check '1:(trap "" TERM; sleep 59) & true'
  [ "$status" -eq 0 ]
  sleep 0.5; ! pgrep -f "^sleep 59$"
}

@test "a daemon a check starts in another directory and session is stopped too (identity by token)" {
  _plan '`(cd / && setsid sleep 61 &); true`'; _agent .
  run bash "$LAND" "$S" 0 --check '1:(cd / && setsid sleep 61 &); true'
  [ "$status" -eq 0 ]
  sleep 0.5; ! pgrep -f "^sleep 61$"
}

@test "a recheck refused before it starts keeps the record it starts from" {
  _agent .; bash "$LAND" "$S" 0 --check '1:test -f a.txt' >/dev/null
  cp "$REC" "$BATS_TEST_TMPDIR/landed"
  printf 'dirty\n' >> a.txt
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt' --recheck
  [ "$status" -eq 1 ]; [[ "$output" == *"uncommitted changes"* ]]
  cmp "$REC" "$BATS_TEST_TMPDIR/landed"
}

# --- increment-step's side: aid_land_record_verify ------------------------------------------------------------
_verify() {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-land-record.sh"
  aid_land_record_verify "$REC" "$S" "$TEST_EVIDENCE_DIR/plan.json" 0 "$D/contract.json" "$D/return.json"
}
_landed_wave() { _wave; _agent "$WT"; bash "$LAND" "$S" 0 --check '1:test -f a.txt' >/dev/null; }
_edit() { jq "$1" "$REC" > "$REC.t" && mv "$REC.t" "$REC"; }
# _forge_timeline <landed sha> — a controller that also writes the timeline line its forged record needs
_forge_timeline() { printf '{"event":"step_takeover_result","step":0,"status":"landed","landed_sha":"%s"}\n' "$1" >> "$TEST_EVIDENCE_DIR/timeline.jsonl"; }

@test "verify: a landed wave record holds" {
  _landed_wave
  run _verify; [ "$status" -eq 0 ]
}

@test "verify: missing, corrupt, running, failed, foreign or another step's record is refused" {
  _landed_wave; cp "$REC" "$BATS_TEST_TMPDIR/good"
  rm "$REC"; run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"no takeover record"* ]]
  printf '{"version":1,' > "$REC"; run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"not a JSON object"* ]]
  for e in '.status = "running"' '.status = "check_failed"' '.epic_id = "E-901-1_1"' '.step_index = 1' '.version = 2'; do
    cp "$BATS_TEST_TMPDIR/good" "$REC"; _edit "$e"
    run _verify; [ "$status" -eq 1 ] || { echo "accepted after: $e"; false; }
  done
}

@test "verify: a command criterion missing, run twice, with another command or red is refused" {
  _landed_wave; cp "$REC" "$BATS_TEST_TMPDIR/good"
  for e in '.checks = "forged"' '.checks = {}' '.checks = [1]' '.checks[0].exit = "0"' '.checks = []' '.checks += .checks' '.checks[0].command = "true"' '.checks[0].exit = 1' '.checks[0].timed_out = true'; do
    cp "$BATS_TEST_TMPDIR/good" "$REC"; _edit "$e"
    run _verify; [ "$status" -eq 1 ] || { echo "accepted after: $e"; false; }
  done
}

@test "verify: a commit after the takeover, a changed contract or return, or a forged merge is refused" {
  _landed_wave; cp "$REC" "$BATS_TEST_TMPDIR/good"
  git commit -q --allow-empty -m later
  run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"--recheck"* ]]
  git reset -q --hard HEAD^
  printf ' ' >> "$D/contract.json"; run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"contract changed"* ]]
  git checkout -q -- . 2>/dev/null; truncate -s -1 "$D/contract.json"
  printf ' ' >> "$D/return.json"; run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"return changed"* ]]
  truncate -s -1 "$D/return.json"; run _verify; [ "$status" -eq 0 ]
  # the same two parents, another tree: built by hand, put at HEAD, recorded as landed
  base="$(jq -r .base_sha "$REC")"; step="$(jq -r .step_sha "$REC")"
  forged="$(git commit-tree "$(git rev-parse "$base^{tree}")" -p "$base" -p "$step" -m forged)"
  git reset -q --hard "$forged"; _edit ".landed_sha = \"$forged\""
  run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"timeline holds no landed takeover"* ]]
  _forge_timeline "$forged"
  run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"tree differs"* ]]
}

@test "verify: a serial record whose commits do not hang together, or a recheck from a commit no takeover produced, is refused" {
  _agent .; bash "$LAND" "$S" 0 --check '1:test -f a.txt' >/dev/null; cp "$REC" "$BATS_TEST_TMPDIR/good"
  run _verify; [ "$status" -eq 0 ]
  _edit ".base_sha = \"$(git rev-list --max-parents=0 HEAD)\""; run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"does not sit on the base"* ]]
  cp "$BATS_TEST_TMPDIR/good" "$REC"; _edit '.base_sha = "1111111111111111111111111111111111111111"'
  run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"does not exist"* ]]
  # a recheck claiming to start from the plan's first commit: an ancestor of HEAD, but no takeover produced it
  git commit -q --allow-empty -m fix
  cp "$BATS_TEST_TMPDIR/good" "$REC"
  _edit ".path = \"recheck\" | .base_sha = \"$(git rev-list --max-parents=0 HEAD)\" | .landed_sha = \"$(git rev-parse HEAD)\""
  _forge_timeline "$(git rev-parse HEAD)"
  run _verify; [ "$status" -eq 1 ]; [[ "$output" == *"no takeover of step 0 produced"* ]]
}

_verify_file() {  # the bound step-0-verify.md at HEAD
  local h ph; h="$(git rev-parse HEAD)"; ph="$(printf '%s' "$(jq -S -c '.steps[0]' "$TEST_EVIDENCE_DIR/plan.json")" | sha256sum | cut -d' ' -f1)"
  printf '# Step 0 Verification\n\n## Acceptance Criteria\n- [x] AC1 — PASS (land.json)\n\n## Memory Used\n- N/A — none (reason: test)\n\n## Memory Written\n- N/A — none (reason: test)\n\nstep_index: 0\nstep_id: step_1_backend\nplan_step_hash: %s\nreviewed_commit: %s\nidempotency_token: t-%s\n\n## Result: PASS\n' \
    "$ph" "$h" "${h:0:8}" > "$TEST_EVIDENCE_DIR/step-0-verify.md"
}

@test "increment-step: a step whose takeover started cannot advance once its record is deleted" {
  _landed_wave; _verify_file; rm "$REC"
  run bash "$FSM" increment-step "$S"
  [ "$status" -ne 0 ]; [[ "$output" == *"(pipeline.md §When AID refuses: land_record_invalid)"* && "$output" == *"is gone"* ]]
}

@test "increment-step refuses a step whose takeover record does not hold, naming the record" {
  _landed_wave; _edit '.checks[0].exit = 1'
  h="$(git rev-parse HEAD)"; ph="$(printf '%s' "$(jq -S -c '.steps[0]' "$TEST_EVIDENCE_DIR/plan.json")" | sha256sum | cut -d' ' -f1)"
  printf '# Step 0 Verification\n\n## Acceptance Criteria\n- [x] AC1 — PASS (land.json)\n\n## Memory Used\n- N/A — none (reason: test)\n\n## Memory Written\n- N/A — none (reason: test)\n\nstep_index: 0\nstep_id: step_1_backend\nplan_step_hash: %s\nreviewed_commit: %s\nidempotency_token: t-%s\n\n## Result: PASS\n' \
    "$ph" "$h" "${h:0:8}" > "$TEST_EVIDENCE_DIR/step-0-verify.md"
  run bash "$FSM" increment-step "$S"
  [ "$status" -ne 0 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: land_record_invalid)"* ]] || { echo "$output" | tail -15; false; }
  [[ "$output" == *"AC1 did not pass"* ]]
  # the same step with its record intact is not refused for the record (whatever the next precondition says)
  _edit '.checks[0].exit = 0'
  run bash "$FSM" increment-step "$S"
  [[ "$output" != *"land_record_invalid"* ]] || { echo "$output" | tail -8; false; }
}

# ── 3.13.0: which criteria are commands, and a replaced command with its reason ───────────────────────────────
@test "3.13.0: a criterion beginning with a test's name is not a command — the step lands without a --check for it" {
  # WAN P116 28. 10. and P118 30. 10. 2026: `test_regime_…` was demanded as a runnable command, so no takeover
  _plan '`test_regime_override` fails on main and'; _agent .
  run bash "$LAND" "$S" 0; echo "$output"; [ "$status" -eq 0 ]; [ "$(jq -r .status "$REC")" = landed ]
  run _verify; [ "$status" -eq 0 ]
  run bash "$LAND" "$S" 0 --check '1:test_regime_override'
  [ "$status" -eq 1 ]; [[ "$output" == *"AC1 is not a command criterion"* ]]
}

@test "3.13.0: a command written as one (./x, a/b, NAME=v x) stays a command, and a missing program fails the check" {
  _plan '`./check.sh`'; _agent .
  run bash "$LAND" "$S" 0; [ "$status" -eq 1 ]; [[ "$output" == *"AC1 is a command criterion and has no --check: ./check.sh"* ]]
  run bash "$LAND" "$S" 0 --check '1:./check.sh'; [ "$status" -eq 1 ]; [ "$(jq -r .status "$REC")" = check_failed ]
}

@test "3.13.0: another command than the plan's lands only with its reason, which the record keeps and verify checks" {
  _agent .
  run bash "$LAND" "$S" 0 --check '1:test -e a.txt'
  [ "$status" -eq 1 ]; [[ "$output" == *"needs --reason"* ]]
  run bash "$LAND" "$S" 0 --check '1:test -f a.txt' --reason '1:nothing replaced here'
  [ "$status" -eq 1 ]; [[ "$output" == *"has --reason but no replaced --check"* ]]
  run bash "$LAND" "$S" 0 --check '1:test -e a.txt' --reason '1:short'
  [ "$status" -eq 1 ]; [[ "$output" == *"needs --reason"* ]]
  run bash "$LAND" "$S" 0 --check '1:test -e a.txt' --reason '1:the plan measures the main checkout, this the plan tree'
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.checks[0] | "\(.command)|\(.plan_command)|\(.reason)"' "$REC")" = "test -e a.txt|test -f a.txt|the plan measures the main checkout, this the plan tree" ]
  run _verify; [ "$status" -eq 0 ]
  cp "$REC" "$BATS_TEST_TMPDIR/good"
  for e in 'del(.checks[0].reason)' '.checks[0].reason = "x"' '.checks[0].plan_command = "true"' 'del(.checks[0].plan_command)'; do
    cp "$BATS_TEST_TMPDIR/good" "$REC"; _edit "$e"
    run _verify; [ "$status" -eq 1 ] || { echo "accepted after: $e"; false; }
  done
}
