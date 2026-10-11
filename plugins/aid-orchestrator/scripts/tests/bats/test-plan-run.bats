#!/usr/bin/env bats
# aid-tier: t2
# test-plan-run.bats — P111 Steps 2 and 4: the direct run (aid-plan-fsm.sh plan-run).
#
# Every case starts from one fixture project seeded ONCE (setup_file): a
# legacy-mode project (no gate_profiles, as the testbed) with a lint-clean
# two-step plan bound to a brief and a passed CP1 round, copied per case. The
# cases that need a different plan seed their own. t2: each full plan-run
# runs plan-start, readiness, the CP1 gate, the seal and init (~25 s).

load test-helpers.bash

PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
FIXTURE_PLAN="$PLUGIN_DIR/scripts/tests/fixtures/plan-direct-two-step.md"

_mk_project() {   # <root> — a git project the fixture plan can live in
  mkdir -p "$1" && cd "$1" || return 1
  git init -q -b main
  git config user.email t@t; git config user.name t
  mkdir -p src/core prirucka .aid-o/config
  echo "def tally(i): pass" > src/core/counter.py
  echo "# Příručka" > prirucka/README.md
  printf 'gates:\n  docs_updated:\n    command: "true"\n' > .aid-o/config/execution.yaml
  git add -A && git commit -qm init
}

_seed() {   # <root> <plan-source> — the fixture plan, its brief, critic and CP1 round
  ( export AID_PLUGIN_PATH="$PLUGIN_DIR"
    source "$PLUGIN_DIR/scripts/tests/lib/aid-test-plan-fixture.sh"
    aid_fixture_seed_plan "$1" "$2" P900-direct.md >/dev/null )
}

setup_file() {
  export AID_TEST_MODE=1
  TPL="$BATS_FILE_TMPDIR/tpl"
  _mk_project "$TPL" >/dev/null
  _seed "$TPL" "$FIXTURE_PLAN" || return 1
  export TPL
}

setup() {
  export AID_TEST_MODE=1 AID_PLUGIN_PATH="$PLUGIN_DIR"
  R="$BATS_TEST_TMPDIR/p"
  cp -a "$TPL" "$R"
  cd "$R"
  FSM="$PLUGIN_DIR/scripts/aid-fsm.sh"
  PFSM="$PLUGIN_DIR/scripts/aid-plan-fsm.sh"
  PIPE="$PLUGIN_DIR/scripts/aid-auto-pipeline.sh"
  PLAN="$R/.aid-o/plans/P900-direct.md"
  GEN="$R/.aid-o/work/evidence/P900/generation"
  EV="$R/.aid-o/work/evidence/E-900-1_1/R-E900-1"
  MF="$R/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  export R FSM PFSM PIPE PLAN GEN EV MF PLUGIN_DIR
}

_run()  { run bash "$PFSM" plan-run P900 "$@"; }
_pipe() { run bash "$PIPE" --plan "$PLAN" "$@"; }

# ── the start ────────────────────────────────────────────────────────────────

@test "direct: plan-run starts one run on plan/<id> with no EPIC artefact, no queue entry and no task branch" {
  _run
  [ "$status" -eq 0 ]
  [ ! -d "$R/.aid-o/tasks" ] || [ -z "$(ls -A "$R/.aid-o/tasks")" ]
  [ -z "$(find "$GEN" -name 'E-*' 2>/dev/null)" ]
  [ ! -f "$R/.aid-o/config/queue.yaml" ] || ! grep -q 'E-900' "$R/.aid-o/config/queue.yaml"
  [ "$(jq -r '.direct' "$EV/plan.json")" = "true" ]
  [ "$(jq -c '.gates' "$EV/plan.json")" = '["docs_updated"]' ]
  [ "$(jq -c '[.steps[].plan_step]' "$EV/plan.json")" = "[1,2]" ]
  grep -q '^plan_ref: .aid-o/plans/P900-direct.md$' "$EV/epic_input.md"
  [ "$(jq -c '.plan_boundary_manifest.epic_runs[0] | [.task_branch, .direct, .lineage, .epic_source_ref, .status]' "$MF")" = '[null,true,"proven","plan/P900","running"]' ]
  [ "$(yq -r '.branch' "$EV/fsm-state.yaml")" = "plan/P900" ]
  [ "$(yq -r '.direct' "$EV/fsm-state.yaml")" = "true" ]
  [ "$(jq -r 'keys[]' "$R/.aid-o/work/active-runs.json")" = "E-900-1_1" ]
}

@test "direct: init --direct records branch plan/<id> and creates no task/ branch" {
  _run
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$R" branch --list 'task/*')" ]
  [ "$(jq -r '.kind' "$GEN/transaction.json")" = "plan_run" ]
  [ "$(jq -r '.total_phases' "$GEN/transaction.json")" = "1" ]
}

@test "direct: a second plan-run is refused plan_run_already_started" {
  _run; [ "$status" -eq 0 ]
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: plan_run_already_started)"* ]]
  [[ "$output" == *"next: "* ]]
}

@test "direct: the pipeline on a plan with a direct run is refused plan_run_already_started" {
  _run; [ "$status" -eq 0 ]
  _pipe
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_run_already_started"* ]]
}

@test "direct: the pipeline on a plan EDITED after plan-run is refused before the mode stamp and the rollover" {
  _run; [ "$status" -eq 0 ]
  local mode_before; mode_before="$(git -C "$R" show main:.aid-lifecycle/manifests/P900.yaml | yq -r '.mode')"
  echo "edited" >> "$PLAN"
  git -C "$R" add -f "$PLAN" && git -C "$R" commit -qm "the plan edited after plan-run"   # past the committed-source preflight
  _pipe
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_run_already_started"* ]]
  [ "$(jq -r '.kind' "$GEN/transaction.json")" = "plan_run" ]
  [ -z "$(ls "$GEN"/transaction.json.* 2>/dev/null | grep -v lock || true)" ]
  [ "$(git -C "$R" show main:.aid-lifecycle/manifests/P900.yaml | yq -r '.mode')" = "$mode_before" ]
}

# ── the two roads exclude each other, each trace alone ───────────────────────

@test "direct: plan-run is refused generation_already_started by an archived generation transaction alone" {
  mkdir -p "$GEN"; echo '{}' > "$GEN/transaction.json.completed-1"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: generation_already_started)"* ]]
}

@test "direct: plan-run is refused generation_already_started by an EPIC file alone" {
  mkdir -p "$R/.aid-o/tasks"; echo x > "$R/.aid-o/tasks/E-900-1_2-old.md"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"generation_already_started"* && "$output" == *"E-900-1_2-old.md"* ]]
}

@test "direct: plan-run is refused generation_already_started by a non-direct manifest entry alone" {
  run bash "$PFSM" plan-start P900 --mode plan_branch --plan-file "$PLAN" --declared-epics E-900-1_1
  [ "$status" -eq 0 ]
  run bash -c 'source "$PLUGIN_DIR/scripts/lib/aid-plan-manifest.sh"; export AID_PLAN_MANIFEST_PROJECT_ROOT="$R"
    plan_manifest_add_epic P900 E-900-1_2 R-E900-1 task/E-900-1_2/main "$(git -C "$R" rev-parse plan/P900)" plan/P900 .aid-o/work/evidence/E-900-1_2/R-E900-1 proven'
  [ "$status" -eq 0 ]
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"generation_already_started"* && "$output" == *"E-900-1_2"* ]]
}

@test "direct: the lock and the atomic writer's temp file are not generation traces" {
  mkdir -p "$GEN"; : > "$GEN/transaction.json.lock"; : > "$GEN/transaction.json.tmp.abc123"
  _run
  [ "$status" -eq 0 ]
}

@test "direct: the pipeline is refused by a plan_run transaction alone" {
  mkdir -p "$GEN"
  jq -n '{schema:"aid-generation-transaction/v1", kind:"plan_run", plan_id:"P900", plan_sha256:"x", target_head:"", phase_derivation_version:1, total_phases:1, phases:{}}' > "$GEN/transaction.json"
  _pipe
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_run_already_started"* && "$output" == *"plan-run"* ]]
}

@test "direct: the pipeline is refused by a direct manifest entry alone (transaction removed)" {
  _run; [ "$status" -eq 0 ]
  rm -f "$GEN/transaction.json"
  _pipe
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_run_already_started"* && "$output" == *"direct run"* ]]
}

@test "direct: supersede-generation refuses a plan_run transaction" {
  _run; [ "$status" -eq 0 ]
  run bash "$PIPE" supersede-generation --plan "$PLAN" --reason "testing that a plan-run is never superseded"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_run_already_started"* ]]
  [ -f "$GEN/transaction.json" ]
}

# ── the lifecycle declares the one run ───────────────────────────────────────

@test "direct: plan-start --declared-epics declares exactly E-<nnn>-1_1 for a plan with two EPIC markers" {
  local R2="$BATS_TEST_TMPDIR/p2"; _mk_project "$R2" >/dev/null
  sed 's/^\*\*EPIC 1: Steps 1-2\*\*$/**EPIC 1: Steps 1-1**/; s/^### Step 2:/**EPIC 2: Steps 2-2**\n\n### Step 2:/' "$FIXTURE_PLAN" > "$BATS_TEST_TMPDIR/two.md"
  [ "$(grep -c '^\*\*EPIC' "$BATS_TEST_TMPDIR/two.md")" = "2" ]
  _seed "$R2" "$BATS_TEST_TMPDIR/two.md"
  cd "$R2"; run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  [ "$(git -C "$R2" show main:.aid-lifecycle/manifests/P900.yaml | yq -r '[.declared_epics[].id] | join(",")')" = "E-900-1_1" ]
}

@test "direct: plan-start --declared-epics declares exactly E-<nnn>-1_1 for a plan with no EPIC marker" {
  _run
  [ "$status" -eq 0 ]
  [ "$(git -C "$R" show main:.aid-lifecycle/manifests/P900.yaml | yq -r '[.declared_epics[].id] | join(",")')" = "E-900-1_1" ]
  # the template carries one marker; prove the argument, not the parse: no marker
  # at all (a legacy plan — the strict lint owes one marker; without the declared
  # list the lifecycle parse would refuse this plan outright)
  local R2="$BATS_TEST_TMPDIR/p2"; _mk_project "$R2" >/dev/null
  grep -v '^\*\*EPIC\|^lifecycle_strict' "$FIXTURE_PLAN" > "$BATS_TEST_TMPDIR/none.md"
  _seed "$R2" "$BATS_TEST_TMPDIR/none.md"
  cd "$R2"; run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  [ "$(git -C "$R2" show main:.aid-lifecycle/manifests/P900.yaml | yq -r '[.declared_epics[].id] | join(",")')" = "E-900-1_1" ]
}

@test "direct: a plan started earlier without the declared list is refused lifecycle_epics_mismatch and passes after the named repair" {
  local R2="$BATS_TEST_TMPDIR/p2"; _mk_project "$R2" >/dev/null
  sed 's/^\*\*EPIC 1: Steps 1-2\*\*$/**EPIC 1: Steps 1-1**/; s/^### Step 2:/**EPIC 2: Steps 2-2**\n\n### Step 2:/' "$FIXTURE_PLAN" > "$BATS_TEST_TMPDIR/two.md"
  _seed "$R2" "$BATS_TEST_TMPDIR/two.md"
  cd "$R2"
  run bash "$PFSM" plan-start P900 --mode plan_branch --plan-file "$R2/.aid-o/plans/P900-direct.md"
  [ "$status" -eq 0 ]
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: lifecycle_epics_mismatch)"* ]]
  [[ "$output" == *"--declare-epics E-900-1_1"* ]]
  run bash "$PFSM" plan-state P900 --declare-epics E-900-1_1 --reason "direct run: one run per plan"
  [ "$status" -eq 0 ]
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
}

# ── the manifest learns the null task branch only for direct entries ─────────

@test "direct: the manifest validator still refuses a non-direct entry with a null task_branch" {
  _run; [ "$status" -eq 0 ]
  jq '.plan_boundary_manifest.epic_runs[0].direct = false' "$MF" > "$MF.t" && mv "$MF.t" "$MF"
  run bash -c 'source "$PLUGIN_DIR/scripts/lib/aid-plan-manifest.sh"; export AID_PLAN_MANIFEST_PROJECT_ROOT="$R"; plan_manifest_validate P900'
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing required field: task_branch"* ]]
}

@test "direct: plan_manifest_add_epic without direct still refuses an empty task_branch" {
  run bash "$PFSM" plan-start P900 --mode plan_branch --plan-file "$PLAN" --declared-epics E-900-1_1
  [ "$status" -eq 0 ]
  run bash -c 'source "$PLUGIN_DIR/scripts/lib/aid-plan-manifest.sh"; export AID_PLAN_MANIFEST_PROJECT_ROOT="$R"
    plan_manifest_add_epic P900 E-900-1_1 R-E900-1 "" "$(git -C "$R" rev-parse plan/P900)" plan/P900 .aid-o/work/evidence/E-900-1_1/R-E900-1 proven'
  [ "$status" -eq 1 ]
  [[ "$output" == *"task_branch"*"required"* ]]
}

# ── resume ───────────────────────────────────────────────────────────────────

@test "direct: a run interrupted after the seal resumes and finishes" {
  AID_PLAN_FSM_CRASH_AFTER=seal _run
  [ "$status" -eq 99 ]
  [ ! -f "$EV/fsm-state.yaml" ]
  _run
  [ "$status" -eq 0 ]
  [ -f "$EV/fsm-state.yaml" ]
}

@test "direct: a run interrupted after init wrote the state resumes with one state file" {
  AID_PLAN_FSM_CRASH_AFTER=init_written _run
  [ "$status" -eq 99 ]
  [ -f "$EV/fsm-state.yaml" ]
  [ "$(jq '[.stages[].name] | index("init")' "$GEN/transaction.json")" = "null" ]
  _run
  [ "$status" -eq 0 ]
  [ "$(find "$R/.aid-o/work/evidence/E-900-1_1" -name fsm-state.yaml | wc -l | tr -d ' ')" = "1" ]
  [ "$(jq '[.stages[].name] | index("done") != null' "$GEN/transaction.json")" = "true" ]
}

@test "direct: a commit on plan/<id> after the manifest stage re-records the base and init passes its lineage check" {
  AID_PLAN_FSM_CRASH_AFTER=manifest _run
  [ "$status" -eq 99 ]
  local wt="$R/.aid-worktrees/plan-P900"
  echo moved > "$wt/moved.txt"; git -C "$wt" add moved.txt; git -C "$wt" commit -qm "a commit after the manifest stage"
  _run
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.epic_runs[0].epic_base_commit' "$MF")" = "$(git -C "$R" rev-parse plan/P900)" ]
}

@test "direct: a plan edited after the seal is refused plan_changed_since_seal on resume" {
  AID_PLAN_FSM_CRASH_AFTER=seal _run
  [ "$status" -eq 99 ]
  echo "edited after the seal" >> "$PLAN"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: plan_changed_since_seal)"* ]]
  [ ! -f "$EV/fsm-state.yaml" ]
}

@test "direct: a plan.json whose dependencies disagree with the plan's step graph is refused before init" {
  AID_PLAN_FSM_CRASH_AFTER=contract_validate _run
  [ "$status" -eq 99 ]
  jq '.dependencies = []' "$EV/plan.json" > "$EV/t" && mv "$EV/t" "$EV/plan.json"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_json_unverified"* ]]
  [ ! -f "$EV/fsm-state.yaml" ]
}

@test "direct: a plan.json bound to other plan bytes is refused before init" {
  AID_PLAN_FSM_CRASH_AFTER=contract_validate _run
  [ "$status" -eq 99 ]
  jq '.source_plan_sha256 = ("0" * 64)' "$EV/plan.json" > "$EV/t" && mv "$EV/t" "$EV/plan.json"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_json_unverified"* ]]
}

@test "direct: plan-run after the run was abandoned mid-transaction is refused naming the dead run" {
  AID_PLAN_FSM_CRASH_AFTER=manifest _run
  [ "$status" -eq 99 ]
  jq '.plan_boundary_manifest.epic_runs[0].status = "abandoned"' "$MF" > "$MF.t" && mv "$MF.t" "$MF"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_run_already_started"* && "$output" == *"E-900-1_1 was abandoned"* ]]
}

# ── refusals that guard the start ────────────────────────────────────────────

@test "direct: a running holder of the generation lock makes plan-run refuse after the timeout, naming it" {
  mkdir -p "$GEN"
  ( exec 9>"$GEN/transaction.json.lock"; flock -x 9; echo "$$" >&9; sleep 20 ) &
  local holder=$!
  sleep 1
  AID_GEN_LOCK_TIMEOUT=1 _run
  kill "$holder" 2>/dev/null || true
  [ "$status" -eq 3 ]
  [[ "$output" == *"generation_lock_held"* && "$output" == *"holder pid"* ]]
}

@test "direct: a plan whose recorded path lies under .aid-worktrees is refused before init" {
  mkdir -p "$R/.aid-worktrees/scratch"
  mv "$PLAN" "$R/.aid-worktrees/scratch/P900-direct.md"
  ln -s "$R/.aid-worktrees/scratch/P900-direct.md" "$PLAN"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_in_scratch_tree"* ]]
  [ ! -f "$EV/fsm-state.yaml" ]
}

@test "direct: init --direct on a branch other than plan/<id> is refused direct_run_needs_plan_branch" {
  AID_PLAN_FSM_CRASH_AFTER=receipt _run
  [ "$status" -eq 99 ]
  local wt="$R/.aid-worktrees/plan-P900"
  git -C "$wt" checkout -q -b side
  run bash -c "cd '$wt' && bash '$FSM' init E-900-1_1 R-E900-1 2 full plan/P900 \$(git rev-parse plan/P900) '$EV/fsm-state.yaml' --plan '$PLAN' --direct"
  [ "$status" -ne 0 ]
  [[ "$output" == *"direct_run_needs_plan_branch"* ]]
  [ ! -f "$EV/fsm-state.yaml" ]
}

@test "direct: a plan without a passed CP1 round is refused by the gate, nothing sealed" {
  rm -rf "$R/.aid-o/work/evidence/P900/cp1"
  _run
  [ "$status" -ne 0 ]
  [[ "$output" == *"aid_generation_force_required"* || "$output" == *"aid_cp1_blocked"* ]]
  [ ! -f "$GEN/generation-authority.json" ]
  [ ! -f "$EV/fsm-state.yaml" ]
}

# ── P111 Step 4: repo_roots — foreign repositories as worktrees ───────────────
_mk_foreign() {   # <dir> — a foreign git repository with one commit on main
  mkdir -p "$1"; git -C "$1" init -q -b main
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo "# docs" > "$1/index.md"; git -C "$1" add index.md; git -C "$1" commit -qm "foreign init"
}
_seed_rr() {   # <project> <foreign> [base_branch] — the fixture plan declaring the foreign repo
  _mk_project "$1" >/dev/null
  local extra=""; [[ -n "${3:-}" ]] && extra="\n    base_branch: $3"
  sed "s|^lifecycle_strict: true$|lifecycle_strict: true\nrepo_roots:\n  - name: docs\n    path: $2${extra}|" "$FIXTURE_PLAN" > "$BATS_TEST_TMPDIR/rr.md"
  _seed "$1" "$BATS_TEST_TMPDIR/rr.md"
  cd "$1"
}

@test "repo-roots: plan-run gives the foreign repository a worktree on plan/<id>-<project> and plan.json the mapping" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  local wt; wt="$(realpath "$F")/.aid-worktrees/plan-P900--docs"
  [ "$(git -C "$wt" rev-parse --abbrev-ref HEAD)" = "plan/P900-proj" ]
  local pj="$R2/.aid-o/work/evidence/E-900-1_1/R-E900-1/plan.json"
  [ "$(jq -c '.repo_roots[0] | [.name, .worktree, .branch, .base]' "$pj")" = "$(jq -nc --arg w "$wt" --arg b "$(git -C "$F" rev-parse main)" '["docs", $w, "plan/P900-proj", $b]')" ]
}

@test "repo-roots: a commit in the worktree leaves the live checkout without a new commit, and its status clean" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  local before; before="$(git -C "$F" rev-parse main)"
  [ -z "$(git -C "$F" status --porcelain)" ]
  local wt="$F/.aid-worktrees/plan-P900--docs"
  echo change >> "$wt/index.md"; git -C "$wt" commit -qam "a step's foreign commit"
  [ "$(git -C "$F" rev-parse main)" = "$before" ]
  [ "$(git -C "$F" rev-parse plan/P900-proj)" != "$before" ]
  [ -z "$(git -C "$F" status --porcelain)" ]
}

@test "repo-roots: a run interrupted right after the worktree was created resumes by adopting it" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; _seed_rr "$R2" "$F"
  AID_PLAN_FSM_CRASH_AFTER=worktree run bash "$PFSM" plan-run P900
  [ "$status" -eq 99 ]
  [ -d "$F/.aid-worktrees/plan-P900--docs" ]
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  [ "$(git -C "$F" worktree list | grep -c 'plan-P900--docs')" = "1" ]
}

@test "repo-roots: a foreign live checkout on a feature branch still gets its worktree branch from the base branch" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"
  git -C "$F" checkout -q -b feature; echo f > "$F/f.md"; git -C "$F" add f.md; git -C "$F" commit -qm feature
  _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  [ "$(git -C "$F" merge-base plan/P900-proj feature)" = "$(git -C "$F" rev-parse main)" ]
  [ "$(jq -r '.repo_roots[0].base' "$R2/.aid-o/work/evidence/E-900-1_1/R-E900-1/plan.json")" = "$(git -C "$F" rev-parse main)" ]
  [ "$(git -C "$F" rev-parse --abbrev-ref HEAD)" = "feature" ]
}

@test "repo-roots: a plan/<id>-<project> branch that exists without the worktree is refused repo_root_invalid" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; git -C "$F" branch plan/P900-proj
  _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: repo_root_invalid)"* && "$output" == *"plan/P900-proj"* ]]
  [ ! -d "$F/.aid-worktrees/plan-P900--docs" ]
}

@test "repo-roots: another project's plan of the same id names a different branch, so the two never meet" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; git -C "$F" branch plan/P900   # the foreign repository's own plan P900
  _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900
  [ "$status" -eq 0 ]
  [ "$(git -C "$F" rev-parse plan/P900)" = "$(git -C "$F" rev-parse main)" ]
  git -C "$F" rev-parse --verify -q plan/P900-proj >/dev/null
}
