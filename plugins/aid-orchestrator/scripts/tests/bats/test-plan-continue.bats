#!/usr/bin/env bats
# aid-tier: t1
# test-plan-continue.bats — P090 Step 3.
#
# TIER. The plan proposed t0. The measurement says otherwise: proving an EPIC is
# merged is a question about Git, so the cases that exercise the whole chain
# need a real repository, a real plan branch and a real merge — seconds, not
# milliseconds. Tier follows measured cost, never intent, so this is t1. The
# cheap cases still avoid `plan-start` (five-plus seconds on its own) and build
# only the git shape they need.
#
# WHAT IS ACTUALLY BEING ASSERTED: that the continuation is a PROGRAM. Every
# case here drives the real script or the real merge command; none of them
# assert that a document describes the sequence, which is all a test could have
# done while the sequence lived in `pipeline.md`.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_FSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  CONTINUE="$AID_PLUGIN_PATH/scripts/aid-plan-continue.sh"
  QW="$AID_PLUGIN_PATH/scripts/lib/aid-queue-write.sh"
  export AID_TEST_MODE=1
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  ROOT="$TEST_TMPDIR/project"
  QUEUE="$ROOT/.aid-o/config/queue.yaml"
  mkdir -p "$ROOT/.aid-o/plans" "$ROOT/.aid-o/config"
  git init -q -b main "$ROOT"
  git -C "$ROOT" config user.email "test@test.local"
  git -C "$ROOT" config user.name "Test"
  printf '**EPIC 1: first**\n' > "$ROOT/.aid-o/plans/P090-test.md"
  git -C "$ROOT" add -A
  git -C "$ROOT" commit -qm "initial"
}

teardown() {
  if [[ -n "${ROOT:-}" && -d "$ROOT" ]]; then
    git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' \
      | while read -r w; do [[ "$w" == "$ROOT" ]] || git -C "$ROOT" worktree remove --force "$w" 2>/dev/null; done
  fi
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

_continue() { run bash "$CONTINUE" "$@" --project-root "$ROOT"; }
_qfield()   { bash "$QW" get "$1" "$2" --queue "$QUEUE" --project-root "$ROOT"; }
_write_queue() { cat > "$QUEUE"; }

# _plan_state_stub — the minimal plan-state file `plan-start` writes. The light
# fixtures need it because `next-epic` refuses to answer for a plan this
# repository has never started — `none` for an unknown plan is exactly the
# answer that would end a plan prematurely.
_plan_state_stub() {
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

# _light_merged <epic_id> — the git shape a finished EPIC leaves behind, built
# by hand: a task branch with a commit, merged into plan/P090. No plan-state, no
# manifest, no lifecycle — this is for the cases that never reach `epic-start`.
_light_merged() {
  local epic_id="$1"
  _plan_state_stub
  git -C "$ROOT" show-ref --verify --quiet refs/heads/plan/P090 \
    || git -C "$ROOT" branch plan/P090 main
  git -C "$ROOT" branch "task/${epic_id}/main" main
  git -C "$ROOT" checkout -q "task/${epic_id}/main"
  echo "$epic_id" > "$ROOT/work-${epic_id}.txt"
  # Never `add -A`: `.aid-o/work/` is untracked runtime state here, and
  # committing it onto the task branch would make `git checkout main` delete it.
  git -C "$ROOT" add "work-${epic_id}.txt"
  git -C "$ROOT" commit -qm "${epic_id}: work"
  git -C "$ROOT" checkout -q main
  git -C "$ROOT" branch -f plan/P090 "task/${epic_id}/main"
}

# _light_unmerged <epic_id> — the same, WITHOUT folding it into plan/P090.
_light_unmerged() {
  local epic_id="$1"
  _plan_state_stub
  git -C "$ROOT" show-ref --verify --quiet refs/heads/plan/P090 \
    || git -C "$ROOT" branch plan/P090 main
  git -C "$ROOT" branch "task/${epic_id}/main" main
  git -C "$ROOT" checkout -q "task/${epic_id}/main"
  echo "$epic_id" > "$ROOT/work-${epic_id}.txt"
  # Never `add -A`: `.aid-o/work/` is untracked runtime state here, and
  # committing it onto the task branch would make `git checkout main` delete it.
  git -C "$ROOT" add "work-${epic_id}.txt"
  git -C "$ROOT" commit -qm "${epic_id}: work"
  git -C "$ROOT" checkout -q main
}

# _real_epic <epic_id> — the production lifecycle for one EPIC, up to (not
# including) the merge: epic-start, a commit on its task branch, epic-complete.
_real_epic() {
  local epic_id="$1"
  run bash "$PLAN_FSM" epic-start P090 "$epic_id" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  git -C "$ROOT" checkout -q "task/${epic_id}/main"
  echo "work" > "$ROOT/work-${epic_id}.txt"
  # Never `add -A` here: plan-start leaves an execution worktree at
  # .aid-worktrees/plan-P090, and adding it would embed a git repository.
  git -C "$ROOT" add "work-${epic_id}.txt"
  git -C "$ROOT" commit -qm "${epic_id}: work"
  git -C "$ROOT" checkout -q main
  local d="$ROOT/.aid-o/work/evidence/${epic_id}/R-${epic_id}-plan"
  mkdir -p "$d/gates"
  printf 'epic_id: %s\nstate: DONE\ndone_phase: release\n' "$epic_id" > "$d/fsm-state.yaml"
  run bash "$PLAN_FSM" epic-complete P090 "$epic_id" --project-root "$ROOT"
  [ "$status" -eq 0 ]
}

_two_epic_queue() {
  _write_queue <<'YAML'
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
    depends_on: ["E-090-1_2"]
YAML
}

# ───────────────────────────────────────────────────────────────────────────
@test "AC7/AC7b: a real merge of an autonomous plan advances it — proof, mirror, ask, claim, start, with no flag anywhere" {
  # The end-to-end case, and the only one that proves the WIRING: nothing here
  # passes --continue. The plan says it is autonomous and that is enough.
  run bash "$PLAN_FSM" plan-start P090 --mode plan_branch --autonomy auto --project-root "$ROOT"
  [ "$status" -eq 0 ]
  _two_epic_queue
  _real_epic E-090-1_2

  run bash "$PLAN_FSM" epic-merge-to-plan P090 E-090-1_2 --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"proof:"* ]]
  [[ "$output" == *"mirror:  E-090-1_2 running -> merged_to_plan"* ]]
  [[ "$output" == *"ask:     next is E-090-2_2"* ]]
  [[ "$output" == *"claim:   E-090-2_2"* ]]
  [[ "$output" == *"start:   E-090-2_2 is registered"* ]]

  # The state really moved: the queue mirrors both facts and the next EPIC's
  # branch exists.
  [ "$(_qfield E-090-1_2 status)" = "merged_to_plan" ]
  [ "$(_qfield E-090-2_2 status)" = "running" ]
  git -C "$ROOT" show-ref --verify --quiet refs/heads/task/E-090-2_2/main
}

@test "AC7b: --no-continue suppresses it, and a manual plan never starts it" {
  # Sourced rather than merged three more times: the decision is one function,
  # and re-running a five-second plan-start to observe a branch of an if is a
  # cost with no extra evidence in it.
  local stubdir="$TEST_TMPDIR/stub"
  mkdir -p "$stubdir"
  cat > "$stubdir/aid-plan-continue.sh" <<STUB
#!/usr/bin/env bash
echo "CONTINUED \$*" >> "$TEST_TMPDIR/continued.log"
STUB
  chmod +x "$stubdir/aid-plan-continue.sh"

  run bash "$PLAN_FSM" plan-start P090 --mode plan_branch --autonomy auto --project-root "$ROOT"
  [ "$status" -eq 0 ]

  # shellcheck disable=SC1090
  source "$PLAN_FSM"
  SCRIPT_DIR="$stubdir"
  export AID_PLAN_STATE_PROJECT_ROOT="$ROOT"

  # autonomous + no flag → continues
  _pfsm_maybe_continue "$ROOT" P090 E-090-1_2 "" 2>/dev/null
  [ -f "$TEST_TMPDIR/continued.log" ]
  [ "$(wc -l < "$TEST_TMPDIR/continued.log")" = "1" ]

  # autonomous + --no-continue → does not
  _pfsm_maybe_continue "$ROOT" P090 E-090-1_2 "no" 2>/dev/null
  [ "$(wc -l < "$TEST_TMPDIR/continued.log")" = "1" ]

  # manual plan + no flag → does not
  sed -i 's/^autonomy: auto$/autonomy: manual/' "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml"
  _pfsm_maybe_continue "$ROOT" P090 E-090-1_2 "" 2>/dev/null
  [ "$(wc -l < "$TEST_TMPDIR/continued.log")" = "1" ]

  # manual plan + --continue → does, because the caller asked explicitly
  _pfsm_maybe_continue "$ROOT" P090 E-090-1_2 "yes" 2>/dev/null
  [ "$(wc -l < "$TEST_TMPDIR/continued.log")" = "2" ]
}

@test "AC7b: EVERY success of the merge command reaches the continuation, and none of them is behind a flag" {
  # The structural half of AC7b, and the case that would have caught the real
  # defect: `cmd_epic_merge_to_plan` has SIX successful exits, not one — a fresh
  # merge plus five convergence paths, two of which (crash recovery from an
  # operation record, and "the tip is already contained") are exactly what a
  # resumed controller hits. Wiring only the fresh-merge exit left those back on
  # "somebody has to remember".
  #
  # An earlier version of this case grepped for the call and asserted the
  # matching line held no `if`. `grep` returns only the matching line, so a
  # guard written on the line ABOVE would have passed it. This asks the two
  # questions that actually matter instead.
  local body="$TEST_TMPDIR/merge-body.sh"
  sed -n '/^cmd_epic_merge_to_plan()/,/^}$/p' "$PLAN_FSM" > "$body"
  [ -s "$body" ]

  # 1. Not one bare `exit 0` remains: every success leaves through the shared
  #    door, so a seventh convergence path cannot silently skip the handover.
  run grep -c '^[[:space:]]*exit 0[[:space:]]*$' "$body"
  [ "$output" = "0" ]

  # 2. The door is used, more than once, and every use passes the SAME four
  #    arguments — no call site quietly drops $continue_opt.
  run grep -c '_pfsm_merge_success "\$project_root" "\$plan_id" "\$epic_id" "\$continue_opt"' "$body"
  [ "$status" -eq 0 ]
  [ "$output" -ge 6 ]

  # 3. Inside the door, the handover is unconditional — no flag, no `if`.
  local door="$TEST_TMPDIR/door.sh"
  sed -n '/^_pfsm_merge_success()/,/^}$/p' "$PLAN_FSM" > "$door"
  [ -s "$door" ]
  run grep -c 'if\|&&\|||' "$door"
  [ "$output" = "0" ]
  grep -q '_pfsm_maybe_continue "\$root" "\$plan_id" "\$epic_id" "\$opt"' "$door"
}

@test "AC7c: without proof that the EPIC merged, nothing is written" {
  # The finding this link exists for: a queue entry with no merge_target is
  # judged by its status alone, so an unearned merged_to_plan there falsely
  # unblocks its dependent.
  _light_unmerged E-090-1_2
  _two_epic_queue
  local before; before="$(sha256sum "$QUEUE" | cut -d' ' -f1)"

  _continue P090 E-090-1_2
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not an ancestor of plan/P090"* ]]
  [ "$(sha256sum "$QUEUE" | cut -d' ' -f1)" = "$before" ]
}

@test "AC8: an exhausted plan ends cleanly and names the three closing commands" {
  _light_merged E-090-1_2
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: running
    plan_id: "P090"
    merge_target: "plan/P090"
    depends_on: []
YAML
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"ask:     none"* ]]
  [[ "$output" == *"plan-finalize P090"* ]]
  [[ "$output" == *"plan-merge-to-main P090"* ]]
  [[ "$output" == *"plan-close P090"* ]]
  # It named them; it did not run them.
  [ ! -d "$ROOT/.aid-o/work/evidence/P090/R-P090-final-1" ]
  [ "$(_qfield E-090-1_2 status)" = "merged_to_plan" ]
}

@test "AC8: a blocked successor ends without error and the queue is NOT claimed" {
  _light_merged E-090-1_2
  # E-090-2_2 depends on E-090-3_2, which is not even in the queue — so it is
  # the ONLY candidate, and it is not ready. (A second, ready candidate would
  # make this case measure the scan's fallthrough instead of the block.)
  _write_queue <<'YAML'
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
    depends_on: ["E-090-3_2"]
YAML
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"ask:     blocked:E-090-2_2:"* ]]
  [[ "$output" == *"not an error"* ]]
  # Nothing was claimed, and nothing was recorded `blocked` either: the ask
  # goes through `peek`, which writes nothing, and the claim was never reached.
  [ "$(_qfield E-090-2_2 status)" = "pending" ]
}

@test "the dependency that has no merge_target: mirroring is what unblocks it" {
  # A legacy entry (no merge_target) is judged by status alone. Its dependent
  # waits on `running` forever unless the finished EPIC is mirrored — which is
  # exactly what link 1 does, and why link 0 must earn the right to do it.
  _light_merged E-090-1_2
  _write_queue <<'YAML'
paused: false
last_modified: "2026-01-01T00:00:00Z"

queue:
  - epic_id: E-090-1_2
    status: running
    plan_id: "P090"
    depends_on: []

  - epic_id: E-090-2_2
    status: pending
    plan_id: "P090"
    depends_on: ["E-090-1_2"]
YAML
  # Before: the successor is blocked on a `running` predecessor.
  run bash "$PLAN_FSM" next-epic P090 --project-root "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == "blocked:E-090-2_2:dependency_unmerged:E-090-1_2" ]]

  # The run mirrors, then claims. epic-start has no manifest to write to here,
  # so the chain fails at the last link — deliberately: this case is about
  # links 0-3, and the failure path is the next case's subject.
  _continue P090 E-090-1_2
  [[ "$output" == *"mirror:  E-090-1_2 running -> merged_to_plan"* ]]
  [[ "$output" == *"ask:     next is E-090-2_2"* ]]
}

@test "AC9b: a start that fails after a successful claim puts the entry back to pending, and says so" {
  # There is no plan-state and no manifest in this fixture, so epic-start
  # cannot succeed — the honest way to reach the failure path without
  # sabotaging the command under test.
  _light_merged E-090-1_2
  _two_epic_queue

  _continue P090 E-090-1_2
  [ "$status" -eq 1 ]
  [[ "$output" == *"claim:   E-090-2_2"* ]]
  [[ "$output" == *"epic-start failed for E-090-2_2"* ]]
  [[ "$output" == *"back to pending"* ]]
  [ "$(_qfield E-090-2_2 status)" = "pending" ]

  # …and it is in the plan's timeline, not only on the terminal.
  run jq -r 'select(.event == "continue_start_failed") | .epic_id' \
      "$ROOT/.aid-o/work/evidence/P090/timeline.jsonl"
  [ "$output" = "E-090-2_2" ]
}

@test "running it twice over the same finished EPIC is harmless — it keys on the queue, not on a memory" {
  _light_merged E-090-1_2
  _two_epic_queue

  _continue P090 E-090-1_2
  [[ "$output" == *"mirror:  E-090-1_2 running -> merged_to_plan"* ]]

  _continue P090 E-090-1_2
  [[ "$output" == *"mirror:  E-090-1_2 already merged_to_plan — skipped"* ]]
  [ "$(_qfield E-090-1_2 status)" = "merged_to_plan" ]
}

@test "AC12: an entry stuck at running is released only by the explicit, human --reclaim" {
  _light_merged E-090-1_2
  _two_epic_queue
  # Simulate the crash between claim and start.
  bash "$QW" set-status E-090-2_2 running --queue "$QUEUE" --project-root "$ROOT"

  # The ordinary run does NOT take it: peek skips `running` entries.
  _continue P090 E-090-1_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"ask:     none"* ]]
  [ "$(_qfield E-090-2_2 status)" = "running" ]

  # The explicit door does.
  _continue --reclaim E-090-2_2
  [ "$status" -eq 0 ]
  [[ "$output" == *"running -> pending"* ]]
  [ "$(_qfield E-090-2_2 status)" = "pending" ]

  # And it refuses anything that is not stuck at running.
  _continue --reclaim E-090-2_2
  [ "$status" -eq 1 ]
  [[ "$output" == *"only releases an entry stuck at 'running'"* ]]
}

@test "usage: a bad plan id, a bad epic id and a missing argument are all exit 2" {
  _continue NOTAPLAN E-090-1_2
  [ "$status" -eq 2 ]
  _continue P090 "not an epic"
  [ "$status" -eq 2 ]
  _continue P090
  [ "$status" -eq 2 ]
}
