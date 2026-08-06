#!/usr/bin/env bats
# test-active-runs-map.bats — P074 Step 4: multi-run active-runs map.
#
# THE GROUNDED FAILURE MODE UNDER TEST: the single-slot
# `active-run-pointer.json` was always OVERWRITTEN by the next run's init
# (aid-fsm.sh, pre-P074 `write_active_run_pointer`), and its only consumer is
# the pre-commit main-fallback guard — so run B's init made run A INVISIBLE
# to that guard and a rogue main commit passed while A was still
# mid-EXECUTE. `active-runs.json` is a map keyed by epic_id: both runs stay
# visible, and a main commit is blocked while EITHER has governs_main and a
# guard-active live state. The legacy pointer file is tolerated READ-ONLY
# for one release (fallback when the map is absent/unparseable) and is never
# written, migrated or deleted by the new code.
#
# Hook scenarios drive REAL `git commit` invocations against INSTALLED hooks
# (fixture style from test-hooks-worktree.bats) — proving the guard with
# git's own cwd/stdin contract, not just when hand-invoked.
#
# FD-3 HYGIENE: every FSM invocation / `git commit` spawns children that must
# not hold bats' report fd — run them with `3>&-`. After any edit verify:
#   bats --tap test-active-runs-map.bats | grep -cE '^(ok|not ok)'   # == 15

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  PRECOMMIT="$AID_PLUGIN_PATH/defaults/hooks/pre-commit"
  export FSM PRECOMMIT
  TEST_TMPDIR="$(mktemp -d)"
  export TEST_TMPDIR
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT AID_PLAN_MANIFEST_PROJECT_ROOT
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# _mk_primary <dir> — committed primary checkout with the .aid-o skeleton
# cmd_init expects; .aid-o/ gitignored exactly like a real AID project.
_mk_primary() {
  local d="$1"
  mkdir -p "$d/.aid-o/plans" "$d/.aid-o/tasks" "$d/.aid-o/config" \
           "$d/.aid-o/work/evidence" "$d/.aid-o/work/runs"
  printf 'counter: 0\n' > "$d/.aid-o/config/counter.yaml"
  printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed primary"
  )
}

# _install_hook <dir> — install the pre-commit template, as /aid-init does.
_install_hook() {
  cp "$PRECOMMIT" "$1/.git/hooks/pre-commit"
  chmod +x "$1/.git/hooks/pre-commit"
}

# _seed_state <primary> <epic> <run> <state> [branch] — minimal fsm-state.yaml.
_seed_state() {
  local d="$1" epic="$2" run="$3" state="$4" branch="${5:-task/$2/main}"
  local ev="$d/.aid-o/work/evidence/$epic/$run"
  mkdir -p "$ev"
  {
    echo "epic_id: $epic"
    echo "run_id: $run"
    echo "state: $state"
    echo "current_step: 0"
    echo "total_steps: 1"
    echo "branch: $branch"
    echo "base_commit: HEAD"
  } > "$ev/fsm-state.yaml"
}

# _seed_two_run_map <primary> — hand-written map matching upsert_active_run's
# schema: TWO runs of DIFFERENT plans, both governs_main. Live state comes
# from the state files (_seed_state), which each test sets per scenario.
_seed_two_run_map() {
  local d="$1"
  mkdir -p "$d/.aid-o/work"
  cat > "$d/.aid-o/work/active-runs.json" <<'JSON'
{
  "E-801-1_1": {"state_file": ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml", "run_id": "R-A", "state": "EXECUTE", "branch": "task/E-801-1_1/main", "plan_id": "P801", "governs_main": true, "updated_at": "2026-01-01T00:00:00Z"},
  "E-802-1_1": {"state_file": ".aid-o/work/evidence/E-802-1_1/R-B/fsm-state.yaml", "run_id": "R-B", "state": "EXECUTE", "branch": "task/E-802-1_1/main", "plan_id": "P802", "governs_main": true, "updated_at": "2026-01-01T00:00:00Z"}
}
JSON
}

# _seed_legacy_pointer <primary> <state_file> — the pre-P074 single slot,
# byte-shape of the retired write_active_run_pointer().
_seed_legacy_pointer() {
  local d="$1" sf="$2"
  mkdir -p "$d/.aid-o/work"
  jq -n --arg sf "$sf" \
    '{state_file: $sf, epic_id: "E-legacy", run_id: "R-legacy", written_at: "2026-01-01T00:00:00Z"}' \
    > "$d/.aid-o/work/active-run-pointer.json"
}

# _stage_in <tree> <file> — create + git add <file> inside <tree>.
_stage_in() {
  mkdir -p "$1/$(dirname "$2")"
  printf 'x\n' > "$1/$2"
  git -C "$1" add "$2"
}

# ─── AC1: two-run visibility ─────────────────────────────────────────────

@test "two inits of different plans BOTH appear in the map (single slot regression closed at the writer)" {
  _mk_primary "$TEST_TMPDIR/primary"
  # cmd_init auto-checkouts task/<epic>/main and refuses to start from
  # another EPIC's task branch — return to main between the two inits, as a
  # real second concurrent session (own worktree/checkout) effectively does.
  run bash -c "cd '$TEST_TMPDIR/primary' \
    && '$FSM' init E-901-1_1 R-A 1 manual main HEAD '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml' \
    && git checkout -q main \
    && '$FSM' init E-902-1_1 R-B 1 manual main HEAD '.aid-o/work/evidence/E-902-1_1/R-B/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]
  local map="$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  [ -f "$map" ]
  run jq -r 'keys | sort | join(",")' "$map"
  [ "$output" = "E-901-1_1,E-902-1_1" ]
  # Entry contract: the fields the consumer (hook) and Step 6 rely on.
  run jq -r '."E-901-1_1" | [.run_id, .branch, .plan_id, (.governs_main|tostring), .state, .state_file] | join("|")' "$map"
  [ "$output" = "R-A|task/E-901-1_1/main|P901|true|READY|.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml" ]
  run jq -r '."E-902-1_1".run_id' "$map"
  [ "$output" = "R-B" ]
}

@test "main commit BLOCKED while run A is EXECUTE and a later run B is READY (run-B-hides-run-A regression closed at the guard)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE
  _seed_state "$TEST_TMPDIR/primary" E-802-1_1 R-B READY
  _seed_two_run_map "$TEST_TMPDIR/primary"
  # The OLD single slot would hold only B (the LATER init) — seed the legacy
  # pointer exactly so, pointing at READY run B: the pre-P074 guard read only
  # this and PASSED. The map must win and block on A.
  _seed_legacy_pointer "$TEST_TMPDIR/primary" ".aid-o/work/evidence/E-802-1_1/R-B/fsm-state.yaml"
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue on main'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
  [[ "$output" == *"EXECUTE"* ]]
  run git -C "$TEST_TMPDIR/primary" log --oneline -1
  [[ "$output" == *"seed primary"* ]]
}

@test "main commit BLOCKED when the OTHER entry is the guard-active one (B EXECUTE, A READY)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A READY
  _seed_state "$TEST_TMPDIR/primary" E-802-1_1 R-B EXECUTE
  _seed_two_run_map "$TEST_TMPDIR/primary"
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue on main'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
  [[ "$output" == *"EXECUTE"* ]]
}

# ─── AC2: legacy-only repo + first upsert ────────────────────────────────

@test "legacy-only repo: no map, pointer to an EXECUTE run still blocks main (read-only fallback works)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE
  _seed_legacy_pointer "$TEST_TMPDIR/primary" ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml"
  [ ! -e "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json" ]
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue on main'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
}

@test "first upsert on a legacy-only repo CREATES the map and leaves the legacy pointer file byte-identical" {
  _mk_primary "$TEST_TMPDIR/primary"
  _seed_legacy_pointer "$TEST_TMPDIR/primary" ".aid-o/work/evidence/E-legacy/R-legacy/fsm-state.yaml"
  cp "$TEST_TMPDIR/primary/.aid-o/work/active-run-pointer.json" "$TEST_TMPDIR/pointer.before"
  run bash -c "cd '$TEST_TMPDIR/primary' \
    && '$FSM' init E-901-1_1 R-A 1 manual main HEAD '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]
  local map="$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  [ -f "$map" ]
  run jq -r 'keys | join(",")' "$map"
  [ "$output" = "E-901-1_1" ]
  # Never migrated, never deleted, never rewritten — byte-identical.
  cmp "$TEST_TMPDIR/pointer.before" "$TEST_TMPDIR/primary/.aid-o/work/active-run-pointer.json"
}

# ─── AC3: done-advance removes exactly its own entry ─────────────────────

@test "done-advance review→release removes exactly ITS OWN entry; the concurrent run keeps its slot" {
  _mk_primary "$TEST_TMPDIR/primary"
  run bash -c "cd '$TEST_TMPDIR/primary' \
    && '$FSM' init E-901-1_1 R-A 1 manual main HEAD '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml' \
    && git checkout -q main \
    && '$FSM' init E-902-1_1 R-B 1 manual main HEAD '.aid-o/work/evidence/E-902-1_1/R-B/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]
  local sfA="$TEST_TMPDIR/primary/.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml"
  sed -i 's/^state: READY/state: DONE/' "$sfA"
  echo "done_phase: review" >> "$sfA"
  run bash -c "cd '$TEST_TMPDIR/primary' && '$FSM' done-advance review release \
    '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml' \
    --force --reason 'PM-authorized test override to reach the map removal path'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"active-runs: removed entry E-901-1_1"* ]]
  run jq -r 'keys | join(",")' "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  [ "$output" = "E-902-1_1" ]
}

# ─── AC3: prune sweeps stale entries ─────────────────────────────────────

@test "active-runs prune removes gone-state-file and terminal entries, keeps the live one, and names what it removed" {
  _mk_primary "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE     # live — must survive
  _seed_state "$TEST_TMPDIR/primary" E-803-1_1 R-C DONE        # terminal
  mkdir -p "$TEST_TMPDIR/primary/.aid-o/work"
  cat > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json" <<'JSON'
{
  "E-801-1_1": {"state_file": ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml", "run_id": "R-A", "state": "EXECUTE", "branch": "task/E-801-1_1/main", "plan_id": "P801", "governs_main": true, "updated_at": "2026-01-01T00:00:00Z"},
  "E-802-1_1": {"state_file": ".aid-o/work/evidence/E-802-1_1/R-B/fsm-state.yaml", "run_id": "R-B", "state": "EXECUTE", "branch": "task/E-802-1_1/main", "plan_id": "P802", "governs_main": true, "updated_at": "2026-01-01T00:00:00Z"},
  "E-803-1_1": {"state_file": ".aid-o/work/evidence/E-803-1_1/R-C/fsm-state.yaml", "run_id": "R-C", "state": "GATES", "branch": "task/E-803-1_1/main", "plan_id": "P803", "governs_main": true, "updated_at": "2026-01-01T00:00:00Z"}
}
JSON
  # E-802's state file was deleted manually / by a killed run's cleanup:
  [ ! -e "$TEST_TMPDIR/primary/.aid-o/work/evidence/E-802-1_1/R-B/fsm-state.yaml" ]
  run bash -c "cd '$TEST_TMPDIR/primary' && '$FSM' active-runs prune" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed E-802-1_1 (state file gone:"* ]]
  [[ "$output" == *"removed E-803-1_1 (terminal state DONE)"* ]]
  [[ "$output" != *"removed E-801-1_1"* ]]
  run jq -r 'keys | join(",")' "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  [ "$output" = "E-801-1_1" ]
}

# ─── Error handling: corruption fails closed at the writer, open at the guard ─

@test "corrupt map: the writer refuses (init still succeeds; garbage left byte-identical; error names the file)" {
  _mk_primary "$TEST_TMPDIR/primary"
  mkdir -p "$TEST_TMPDIR/primary/.aid-o/work"
  echo "{this is not json" > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  cp "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json" "$TEST_TMPDIR/map.before"
  run bash -c "cd '$TEST_TMPDIR/primary' \
    && '$FSM' init E-901-1_1 R-A 1 manual main HEAD '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]   # best-effort: a map failure must never block init
  [[ "$output" == *"active-runs.json is not a parseable JSON object"* ]]
  cmp "$TEST_TMPDIR/map.before" "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
}

@test "corrupt map at the guard: falls back to the legacy pointer (EXECUTE → still blocks)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE
  _seed_legacy_pointer "$TEST_TMPDIR/primary" ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml"
  echo "{this is not json" > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue on main'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
}

@test "corrupt map + no usable legacy pointer: fail-open WITH a warning (never a false block)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  echo "{this is not json" > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  _stage_in "$TEST_TMPDIR/primary" src/anything.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'plain commit on main'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"active-runs map"*"unparseable"* ]]
  [[ "$output" == *"failing open"* ]]
}

@test "20 PARALLEL upserts of distinct epics all land in the map — no lost update under the flock" {
  _mk_primary "$TEST_TMPDIR/primary"
  local i
  for i in $(seq -w 1 20); do
    _seed_state "$TEST_TMPDIR/primary" "E-8${i}-1_1" "R-${i}" EXECUTE
  done
  # upsert_active_run is init's internal writer — drive it directly (sourcing
  # aid-fsm.sh is a supported fixture path, see test-anti-fabrication's shim)
  # so the 20 processes genuinely contend on the map's sidecar flock instead
  # of being serialized by init's branch checkouts.
  for i in $(seq -w 1 20); do
    bash -c "cd '$TEST_TMPDIR/primary' && source '$FSM' \
      && upsert_active_run '.aid-o/work/evidence/E-8${i}-1_1/R-${i}/fsm-state.yaml'" \
      > "$TEST_TMPDIR/up.$i" 2>&1 3>&- &
  done
  wait
  # No upsert failed silently...
  for i in $(seq -w 1 20); do
    [ ! -s "$TEST_TMPDIR/up.$i" ]
  done
  # ...and all 20 entries landed (a lost read-modify-write would drop one).
  local map="$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  run jq -r 'keys | length' "$map"
  [ "$output" = "20" ]
  run jq -r '."E-807-1_1".run_id + " " + ."E-820-1_1".run_id' "$map"
  [ "$output" = "R-07 R-20" ]
}

@test "zero-byte map is UNPARSEABLE, not empty: guard falls back to the legacy pointer (EXECUTE → blocks)" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE
  _seed_legacy_pointer "$TEST_TMPDIR/primary" ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml"
  : > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"   # truncated write
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue on main'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
}

@test "zero-byte map at the writer: refuses fail-closed naming the file (init still succeeds; file stays zero-byte)" {
  _mk_primary "$TEST_TMPDIR/primary"
  mkdir -p "$TEST_TMPDIR/primary/.aid-o/work"
  : > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  run bash -c "cd '$TEST_TMPDIR/primary' \
    && '$FSM' init E-901-1_1 R-A 1 manual main HEAD '.aid-o/work/evidence/E-901-1_1/R-A/fsm-state.yaml'" 3>&-
  [ "$status" -eq 0 ]   # best-effort: a map failure must never block init
  [[ "$output" == *"active-runs.json is not a parseable JSON object"* ]]
  [ -e "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json" ]
  [ ! -s "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json" ]
}

@test "mixed map (one junk non-object value) does NOT hide the valid entry: main commit still blocked" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE
  mkdir -p "$TEST_TMPDIR/primary/.aid-o/work"
  # "bad" sorts BEFORE "E-801-1_1" in to_entries order concerns aside — the
  # point is a per-entry jq error must not abort the whole enumeration.
  cat > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json" <<'JSON'
{
  "bad": "not-an-object",
  "E-801-1_1": {"state_file": ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml", "run_id": "R-A", "state": "EXECUTE", "branch": "task/E-801-1_1/main", "plan_id": "P801", "governs_main": true, "updated_at": "2026-01-01T00:00:00Z"}
}
JSON
  _stage_in "$TEST_TMPDIR/primary" src/rogue.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'rogue on main'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HEAD is 'main'"* ]]
  [[ "$output" == *"EXECUTE"* ]]
}

@test "present-but-empty map {} is AUTHORITATIVE: guard passes even though a legacy EXECUTE pointer still exists" {
  _mk_primary "$TEST_TMPDIR/primary"
  _install_hook "$TEST_TMPDIR/primary"
  _seed_state "$TEST_TMPDIR/primary" E-801-1_1 R-A EXECUTE
  _seed_legacy_pointer "$TEST_TMPDIR/primary" ".aid-o/work/evidence/E-801-1_1/R-A/fsm-state.yaml"
  echo '{}' > "$TEST_TMPDIR/primary/.aid-o/work/active-runs.json"
  _stage_in "$TEST_TMPDIR/primary" src/anything.txt
  run bash -c "cd '$TEST_TMPDIR/primary' && git commit -m 'plain commit on main'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" != *"unparseable"* ]]
  run git -C "$TEST_TMPDIR/primary" log --oneline -1
  [[ "$output" == *"plain commit on main"* ]]
}
