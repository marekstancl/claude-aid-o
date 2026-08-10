#!/usr/bin/env bats
# test-cache-preflight.bats — P060 Step 5: controller plugin-cache staleness guard.
# Covers the 7 F4 scenarios of aid-cache-preflight.sh + its wiring into aid-fsm.sh:
#   (a) dogfood + skew   → hard stop, exit != 0
#   (b) dogfood + match  → ok (MANDATORY — else every dogfood run dies)
#   (c) consumer init    → controller_version/hash written to fsm-state + event
#   (d) consumer resume  → changed controller → warn + controller_skew_detected
#   (e) override env      → continues with logged event
#   (f) end-to-end        → aid-fsm.sh init on dogfood-skew fixture → exit != 0
#                           AND fsm-state.yaml NOT created (kills lib-green/wiring-missing)
#   (g) determinism       → two path-different, content-identical trees → identical hash
# Plus a bonus wiring test for cmd_verify_state (F3 resume path).
#
# Harness style mirrors test-aid-fsm.bats / test-helpers.bash (temp git repo).

setup() {
  export AID_TEST_MODE=1
  export AID_DEPLOY_DATE="2026-04-01T00:00:00Z"
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT
  export AID_PLUGIN_PATH="$PLUGIN_ROOT"
  LIB="$PLUGIN_ROOT/scripts/lib/aid-cache-preflight.sh"
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  export LIB FSM
  RUNNING_VERSION="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  export RUNNING_VERSION
  WORK="$(mktemp -d)"
  export WORK
  cd "$WORK"
  unset AID_CACHE_PREFLIGHT_OVERRIDE
}

teardown() {
  cd /
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# make_dogfood_fixture <dir> <skew|match>
#   Creates <dir>/plugins/aid-orchestrator/.claude-plugin/plugin.json so the dir
#   is detected as dogfood (name == running plugin name). match copies the real
#   plugin.json + scripts/ tree (→ identical version+hash); skew bumps version.
make_dogfood_fixture() {
  local dir="$1" mode="$2"
  mkdir -p "$dir/plugins/aid-orchestrator/.claude-plugin"
  if [[ "$mode" == "match" ]]; then
    cp "$PLUGIN_ROOT/.claude-plugin/plugin.json" "$dir/plugins/aid-orchestrator/.claude-plugin/plugin.json"
    cp -r "$PLUGIN_ROOT/scripts" "$dir/plugins/aid-orchestrator/scripts"
  else
    cat > "$dir/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<EOF
{ "name": "aid-orchestrator", "version": "9.9.9-stale" }
EOF
  fi
}

# init_git_repo <dir>  — git repo on main with an initial commit (clean tree).
init_git_repo() {
  local dir="$1"
  ( cd "$dir" && git init -q -b main 2>/dev/null || git init -q
    git config user.email "test@test.local"; git config user.name "Test"
    [[ -e .gitkeep ]] || echo init > .gitkeep
    git add -A && git commit -q -m initial )
}

# ─── (a) dogfood + skew → hard stop, exit != 0 ───────────────────────────────
@test "F4a: dogfood + version skew → HARD STOP (exit != 0) + skew_dogfood event" {
  local repo="$WORK/skewrepo"
  make_dogfood_fixture "$repo" skew
  init_git_repo "$repo"
  cd "$repo"
  run bash "$LIB" "$repo/nonexistent-state.yaml" "$WORK/tl.jsonl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD STOP"* ]]
  jq -se 'any(.[]; .event == "cache_preflight_skew_dogfood")' "$WORK/tl.jsonl" | grep -q '^true$'
}

# ─── (b) dogfood + match → ok (mandatory) ────────────────────────────────────
@test "F4b: dogfood + match → ok (exit 0, no hard stop) + cache_preflight_ok event" {
  local repo="$WORK/matchrepo"
  make_dogfood_fixture "$repo" match
  init_git_repo "$repo"
  cd "$repo"
  run bash "$LIB" "$repo/nonexistent-state.yaml" "$WORK/tl.jsonl"
  [ "$status" -eq 0 ]
  jq -se 'any(.[]; .event == "cache_preflight_ok")' "$WORK/tl.jsonl" | grep -q '^true$'
}

# ─── (c) consumer init → record controller_version/hash + event ──────────────
@test "F4c: consumer init (aid-fsm.sh) → controller_version/hash written + event" {
  init_git_repo "$WORK"
  local state="$WORK/.aid-o/work/evidence/E-c/R-c/fsm-state.yaml"
  run bash "$FSM" init E-c R-c 3 manual main HEAD "$state"
  [ "$status" -eq 0 ]
  [ -f "$state" ]
  grep -q "^controller_version: ${RUNNING_VERSION}$" "$state"
  grep -q "^controller_hash: [0-9a-f]\{64\}$" "$state"
  local tl="$WORK/.aid-o/work/evidence/E-c/R-c/timeline.jsonl"
  jq -se 'any(.[]; .event == "controller_recorded")' "$tl" | grep -q '^true$'
}

# ─── (d) consumer resume with changed controller → warn + skew event ─────────
@test "F4d: consumer resume with stale recorded controller → warn + controller_skew_detected (non-blocking)" {
  # Non-dogfood cwd (plain temp dir, no plugins/aid-orchestrator) → consumer path.
  local state="$WORK/fsm-state.yaml"
  cat > "$state" <<EOF
epic_id: E-d
run_id: R-d
state: EXECUTE
controller_version: 9.9.9-old
controller_hash: deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
EOF
  run bash "$LIB" "$state" "$WORK/tl.jsonl"
  [ "$status" -eq 0 ]                      # non-blocking
  [[ "$output" == *"consumer skew"* ]]
  jq -se 'any(.[]; .event == "controller_skew_detected")' "$WORK/tl.jsonl" | grep -q '^true$'
}

# ─── (e) override env → continues with logged event ──────────────────────────
@test "F4e: AID_CACHE_PREFLIGHT_OVERRIDE=1 on dogfood skew → continues (exit 0) + override event" {
  local repo="$WORK/skewrepo"
  make_dogfood_fixture "$repo" skew
  init_git_repo "$repo"
  cd "$repo"
  AID_CACHE_PREFLIGHT_OVERRIDE=1 run bash "$LIB" "$repo/nonexistent-state.yaml" "$WORK/tl.jsonl"
  [ "$status" -eq 0 ]
  jq -se 'any(.[]; .event == "cache_preflight_override")' "$WORK/tl.jsonl" | grep -q '^true$'
}

# ─── (f) end-to-end: init on dogfood skew → exit != 0 AND state file NOT created
@test "F4f: aid-fsm.sh init on dogfood-skew repo → exit != 0 AND fsm-state.yaml NOT created" {
  local repo="$WORK/skewrepo"
  make_dogfood_fixture "$repo" skew
  init_git_repo "$repo"
  cd "$repo"
  local state="$repo/.aid-o/work/evidence/E-f/R-f/fsm-state.yaml"
  run bash "$FSM" init E-f R-f 3 manual main HEAD "$state"
  [ "$status" -ne 0 ]
  [ ! -f "$state" ]
}

# ─── (g) determinism: two path-different, content-identical trees → same hash ─
@test "F4g: tree hash is deterministic across two path-different identical trees" {
  # shellcheck disable=SC1090
  source "$LIB"
  local a="$WORK/treeA" b="$WORK/nested/treeB"
  mkdir -p "$a/sub" "$b/sub"
  printf 'alpha\n' > "$a/one.txt";      printf 'alpha\n' > "$b/one.txt"
  printf 'beta\n'  > "$a/sub/two.txt";  printf 'beta\n'  > "$b/sub/two.txt"
  local ha hb
  ha="$(_aid_cp_tree_hash "$a")"
  hb="$(_aid_cp_tree_hash "$b")"
  [ -n "$ha" ]
  [ "$ha" == "$hb" ]
  # A content change must change the hash (guards against a constant/no-op hash).
  printf 'gamma\n' >> "$b/sub/two.txt"
  local hc
  hc="$(_aid_cp_tree_hash "$b")"
  [ "$ha" != "$hc" ]
}

# ─── bonus: cmd_verify_state wiring runs the preflight on a consumer resume ───
@test "wiring: aid-fsm.sh verify-state records controller on first call (consumer)" {
  init_git_repo "$WORK"
  local state="$WORK/fsm-state.yaml"
  cat > "$state" <<EOF
epic_id: E-w
run_id: R-w
state: READY
current_step: 0
total_steps: 3
EOF
  run bash "$FSM" verify-state "$state"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"state":"READY"'* ]]     # JSON stdout intact (preflight is stderr/timeline only)
  grep -q "^controller_version: ${RUNNING_VERSION}$" "$state"
}

# ─── P079 Step 8 (IMP-477): the EPIC's own work is not a stale cache ─────────
#
# THE LIVE FAILURE: the dogfood reference resolves to the INVOKING tree's
# plugins/ copy, so an EPIC that modifies the plugin always "skews" against
# itself. The check hard-stopped the plugin's own runs on the difference that
# WAS the work. The downgrade is narrow on purpose — the three cases below pin
# both what it now tolerates and everything it still stops.

# make_plan_worktree <primary> <plan_id> — a linked worktree at the registered
# plan-worktree path, carrying a skewed dogfood plugin copy.
make_plan_worktree() {
  local primary="$1" plan_id="$2" wt="$1/.aid-worktrees/plan-$2"
  git -C "$primary" worktree add -q "$wt" -b "plan/${plan_id}"
  make_dogfood_fixture "$wt" skew
  git -C "$wt" add -A
  git -C "$wt" -c user.email=t@e -c user.name=t commit -q -m "the EPIC's own plugin work"
  printf '%s' "$wt"
}

@test "P079 Step 8: a plan worktree whose diff touches plugins/ WARNS and continues (skew_wip event)" {
  local primary="$WORK/primary" wt
  make_dogfood_fixture "$primary" match
  init_git_repo "$primary"
  wt="$(make_plan_worktree "$primary" P900)"

  run bash -c "cd '$wt' && exec bash '$LIB' '$wt/nonexistent-state.yaml' '$WORK/tl.jsonl'" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"the EPIC's own work"* ]]
  [[ "$output" != *"HARD STOP"* ]]
  jq -se 'any(.[]; .event == "cache_preflight_skew_wip")' "$WORK/tl.jsonl" | grep -q '^true$'
}

@test "P079 Step 8: a plan worktree with NO plugins/ diff still HARD STOPS (real staleness is still caught)" {
  local primary="$WORK/primary" wt="$WORK/primary/.aid-worktrees/plan-P900"
  make_dogfood_fixture "$primary" skew
  init_git_repo "$primary"
  git -C "$primary" worktree add -q "$wt" -b plan/P900
  # A worktree that changed nothing under plugins/ — the skew is genuinely the
  # cache, not the work.
  printf 'notes\n' > "$wt/NOTES.md"
  git -C "$wt" add -A
  git -C "$wt" -c user.email=t@e -c user.name=t commit -q -m "docs only"

  run bash -c "cd '$wt' && exec bash '$LIB' '$wt/nonexistent-state.yaml' '$WORK/tl.jsonl'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD STOP"* ]]
  jq -se 'any(.[]; .event == "cache_preflight_skew_dogfood")' "$WORK/tl.jsonl" | grep -q '^true$'
}

@test "P079 Step 8: the PRIMARY checkout hard stop is untouched, even with plugins/ changes" {
  local repo="$WORK/primaryskew"
  make_dogfood_fixture "$repo" skew
  init_git_repo "$repo"
  printf 'x\n' > "$repo/plugins/aid-orchestrator/newfile.txt"
  ( cd "$repo" && git add -A && git commit -q -m "plugin change on the primary checkout" )

  run bash -c "cd '$repo' && exec bash '$LIB' '$repo/nonexistent-state.yaml' '$WORK/tl.jsonl'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD STOP"* ]]
}

@test "P079 Step 8: a linked worktree OUTSIDE the plan-worktree convention hard stops (the downgrade is not a blanket worktree escape)" {
  local primary="$WORK/primary" wt="$WORK/elsewhere"
  make_dogfood_fixture "$primary" match
  init_git_repo "$primary"
  git -C "$primary" worktree add -q "$wt" -b feature/whatever
  make_dogfood_fixture "$wt" skew
  git -C "$wt" add -A
  git -C "$wt" -c user.email=t@e -c user.name=t commit -q -m "plugin work outside a plan worktree"

  run bash -c "cd '$wt' && exec bash '$LIB' '$wt/nonexistent-state.yaml' '$WORK/tl.jsonl'" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"HARD STOP"* ]]
}
