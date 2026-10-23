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
  # _run_ok and the fixed project path are per file: parallel cases would share them
  [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -eq 1 ]] || { echo "test-plan-run.bats needs serial bats (--jobs 1)" >&2; return 1; }
  export AID_TEST_MODE=1
  TPL="$BATS_FILE_TMPDIR/tpl"
  _mk_project "$TPL" >/dev/null
  _seed "$TPL" "$FIXTURE_PLAN" || return 1
  export TPL
}

setup() {
  export AID_TEST_MODE=1 AID_PLUGIN_PATH="$PLUGIN_DIR"
  # one fixed path per file, so the state _run_ok saves (absolute paths, the plan's
  # worktree inside the project) is valid when the next case restores it
  R="$BATS_FILE_TMPDIR/p"
  cd /; rm -rf "$R"
  cp -a "$TPL" "$R"
  cd "$R"
  FSM="$PLUGIN_DIR/scripts/aid-fsm.sh"
  PFSM="$PLUGIN_DIR/scripts/aid-plan-fsm.sh"
  PLAN="$R/.aid-o/plans/P900-direct.md"
  GEN="$R/.aid-o/work/evidence/P900/generation"
  EV="$R/.aid-o/work/evidence/E-900-1_1/R-E900-1"
  MF="$R/.aid-o/work/plan-state/P900/plan-boundary-manifest.json"
  export R FSM PFSM PLAN GEN EV MF PLUGIN_DIR
}

_run()  { run bash "$PFSM" plan-run P900 "$@"; }
# _run_ok — a plain plan-run on the untouched template, which must succeed. The first case
# runs it (~25 s) and publishes the project with its output; every later case restores that
# copy (state, worktree and output), so only the cases about the run itself pay for it.
# Refused when the project is no longer the template or a crash point is set: the copy is
# the result of exactly one input.
_run_ok() {
  local saved="$BATS_FILE_TMPDIR/after-run"
  [[ $# -eq 0 && -z "${AID_PLAN_FSM_CRASH_AFTER:-}" ]] || { echo "_run_ok: a plain run only" >&2; return 1; }
  diff -rq "$TPL" "$R" >/dev/null || { echo "_run_ok: the project is not the template — call _run" >&2; return 1; }
  if [[ -d "$saved" ]]; then
    [[ -d "$saved/p" && -f "$saved/output" ]] || { echo "_run_ok: incomplete saved run" >&2; return 1; }
    cd /; rm -rf "$R"; cp -a "$saved/p" "$R" || return 1; cd "$R"
    output="$(cat "$saved/output")" || return 1
    status=0; lines=(); mapfile -t lines <<<"$output"
  else
    _run; [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    local staging="$saved.staging.$$"
    rm -rf "$staging"; mkdir -p "$staging"
    cp -a "$R" "$staging/p" && printf '%s' "$output" > "$staging/output" && mv "$staging" "$saved" \
      || { echo "_run_ok: publishing the saved run failed" >&2; return 1; }
  fi
}
# _page — re-render the PM page after a test edits the plan (plan-run refuses a stale page, as production does)
_page() { ( source "$PLUGIN_DIR/scripts/lib/aid-plan-summary.sh" && aid_plan_summary_render "$PLAN" "$R/.aid-o/work/evidence/P900/plan-summary-artifact.html" >/dev/null 2>&1 ); }

# ── the start ────────────────────────────────────────────────────────────────

@test "direct: plan-run starts one run on plan/<id> with no EPIC artefact, no queue entry and no task branch" {
  _run_ok
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

@test "direct: a host where the close could measure no cmd point is refused before anything is created" {
  mkdir -p "$R/fakebin"; printf '#!/bin/sh\nexit 1\n' > "$R/fakebin/unshare"; chmod +x "$R/fakebin/unshare"
  PATH="$R/fakebin:$PATH" _run
  echo "$output"; [ "$status" -ne 0 ]
  [[ "$output" == *"no_isolation"* && "$output" == *"util-linux"* ]]
  [[ "$output" == *"class: incident"* || "$output" == *"When AID refuses: no_isolation"* ]]
  ! git -C "$R" rev-parse -q --verify plan/P900 >/dev/null
  [ ! -d "$EV" ]
}

@test "direct: init --direct records branch plan/<id> and creates no task/ branch" {
  _run_ok
  [ "$status" -eq 0 ]
  [ -z "$(git -C "$R" branch --list 'task/*')" ]
  [ "$(jq -r '.kind' "$GEN/transaction.json")" = "plan_run" ]
  [ "$(jq -r '.total_phases' "$GEN/transaction.json")" = "1" ]
}

@test "direct: a second plan-run is refused plan_run_already_started" {
  _run_ok; [ "$status" -eq 0 ]
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: plan_run_already_started)"* ]]
  [[ "$output" == *"next: "* ]]
}



# ── the two roads exclude each other, each trace alone ───────────────────────

@test "direct: plan-run is refused epic_path_removed by an archived generation transaction alone" {
  mkdir -p "$GEN"; echo '{}' > "$GEN/transaction.json.completed-1"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: epic_path_removed)"* ]]
}

@test "direct: plan-run is refused epic_path_removed by an EPIC file alone" {
  mkdir -p "$R/.aid-o/tasks"; echo x > "$R/.aid-o/tasks/E-900-1_2-old.md"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"epic_path_removed"* && "$output" == *"E-900-1_2-old.md"* ]]
}

@test "direct: plan-run is refused epic_path_removed by a non-direct manifest entry alone" {
  run bash "$PFSM" plan-start P900 --mode plan_branch --plan-file "$PLAN" --declared-epics E-900-1_1
  [ "$status" -eq 0 ]
  run bash -c 'source "$PLUGIN_DIR/scripts/lib/aid-plan-manifest.sh"; export AID_PLAN_MANIFEST_PROJECT_ROOT="$R"
    plan_manifest_add_epic P900 E-900-1_2 R-E900-1 task/E-900-1_2/main "$(git -C "$R" rev-parse plan/P900)" plan/P900 .aid-o/work/evidence/E-900-1_2/R-E900-1 proven'
  [ "$status" -eq 0 ]
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"epic_path_removed"* && "$output" == *"E-900-1_2"* ]]
}

@test "direct: the lock and the atomic writer's temp file are not generation traces" {
  mkdir -p "$GEN"; : > "$GEN/transaction.json.lock"; : > "$GEN/transaction.json.tmp.abc123"
  _run
  [ "$status" -eq 0 ]
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
  _run_ok
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
  _run_ok; [ "$status" -eq 0 ]
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

# _break_plan — the seeded plan turned broadcast-shaped AFTER its CP1 round (a round is not prepared over a plan
# readiness refuses, since 2.116), its page re-rendered so the page check passes and readiness is what refuses
_break_plan() {
  sed -i 's|^- Modify: `prirucka/README.md` — .*|- Create: `src/core/lengths.py` — funkce `tally_by_length(items)`|' "$PLAN"   # both steps broadcast one output
  _page
}

@test "direct: a broadcast-shaped plan never starts a run — readiness refuses it before the seal (D5 shifted left)" {
  _break_plan
  _run
  [ "$status" -eq 7 ]
  [[ "$output" == *"nothing was written"* ]]
  [ ! -f "$GEN/generation-authority.json" ] && [ ! -f "$EV/fsm-state.yaml" ]
}

# _snap — what a refused first plan-run must leave exactly as it was (3.9.1, ACTA P027)
_snap() {
  _snapraw | sha256sum
}
_snapraw() {
  git -C "$R" rev-parse HEAD; git -C "$R" for-each-ref --format='%(refname) %(objectname)'; git -C "$R" worktree list --porcelain
  local d; for d in "$R/.aid-o/work/plan-state" "$R/.aid-lifecycle/manifests" "$GEN" "$R/.aid-o/work/evidence/E-900-1_1"; do
    echo "== $d"; [[ -d "$d" ]] && ls -A "$d"; done; return 0
}

@test "direct: a plan the CP1 gate refuses changes nothing — no transaction, no commit, no plan state, no branch (ACTA P027)" {
  rm -rf "$R/.aid-o/work/evidence/P900/cp1"            # no CP1 round: the gate refuses
  local before; before="$(_snap)"
  _run
  echo "$output"; [ "$status" -ne 0 ]
  [[ "$output" == *"cp1_not_passed"* ]]
  [ "$(_snap)" = "$before" ]
  [ ! -f "$GEN/transaction.json" ]
}

@test "direct: a plan readiness refuses changes nothing either — no directory, no lock (3.9.1)" {
  _break_plan
  local before; before="$(_snap)"
  _run
  [ "$status" -eq 7 ]; [ "$(_snap)" = "$before" ]
}

@test "direct: --force over a HARD CP1 refusal (unreadable round evidence) changes nothing (3.9.1)" {
  echo '{not json' > "$R/.aid-o/work/evidence/P900/cp1/rounds.json"
  local before; before="$(_snap)"
  run bash "$PFSM" plan-run P900 --force --reason "test: the PM overrides the CP1 gate for this plan"
  echo "$output"; [ "$status" -ne 0 ]
  [[ "$output" == *"aid_cp1_blocked"* && "$output" == *"cp1_not_passed"* ]]
  [ "$(_snap)" = "$before" ]; [ ! -f "$GEN/transaction.json" ]
}

@test "direct: --force over a FORCEABLE CP1 refusal (no round) goes on to the seal, which records the override (3.9.1)" {
  rm -rf "$R/.aid-o/work/evidence/P900/cp1"
  run bash "$PFSM" plan-run P900 --force --reason "test: the PM overrides the CP1 gate for this plan"
  echo "$output"; [ "$status" -eq 0 ]                         # the run starts
  [[ "$output" != *"cp1_not_passed"* ]]
  [ -f "$GEN/transaction.json" ]                                # past the read-only check
  [ "$(jq -r '.forced_override' "$GEN/generation-authority.json")" = true ]
  [ "$(jq -r '.force_reason' "$GEN/generation-authority.json")" = "test: the PM overrides the CP1 gate for this plan" ]
}

@test "direct: a plan started earlier (plan-start, no plan-run transaction) is checked before plan-run writes anything (3.9.1)" {
  bash "$PFSM" plan-start P900 --mode plan_branch --project-root "$R" --plan-file "$PLAN" --declared-epics E-900-1_1 >/dev/null 2>&1 || skip "plan-start refused the fixture"
  rm -f "$R/.aid-o/work/evidence/P900/plan-summary-artifact.html"
  local before; before="$(_snap)"
  _run
  echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"plan_page_missing"* ]]
  [ "$(_snap)" = "$before" ]; [ ! -f "$GEN/transaction.json" ]
}

@test "direct: a plan whose PM page is missing changes nothing either (3.9.1)" {
  rm -f "$R/.aid-o/work/evidence/P900/plan-summary-artifact.html"
  local before; before="$(_snap)"
  _run
  echo "$output"; [ "$status" -ne 0 ]; [[ "$output" == *"plan_page_missing"* ]]
  [ "$(_snap)" = "$before" ]
}

@test "direct: a failing D5 contract check stops plan-run before init and keeps its evidence" {
  local sh="$BATS_TEST_TMPDIR/plugin" f   # a shadow plugin whose contract check fails
  mkdir -p "$sh/scripts/gates"
  for f in "$PLUGIN_DIR/scripts"/*; do [[ "$(basename "$f")" =~ ^(tests|gates)$ ]] || ln -s "$f" "$sh/scripts/"; done
  for f in "$PLUGIN_DIR/scripts/gates"/*; do ln -s "$f" "$sh/scripts/gates/"; done
  for f in "$PLUGIN_DIR"/*; do [[ "$(basename "$f")" == scripts ]] || ln -s "$f" "$sh/"; done
  rm "$sh/scripts/gates/aid-contract-validate.sh"
  printf '#!/usr/bin/env bash\necho %s; exit 1\n' "'{\"result\":\"fail\"}'" > "$sh/scripts/gates/aid-contract-validate.sh"
  run env AID_PLUGIN_PATH="$sh" bash "$sh/scripts/aid-plan-fsm.sh" plan-run P900
  [ "$status" -eq 4 ]
  [[ "$output" == *"the D5 contract check failed"* ]]
  [ "$(jq -r .result "$GEN/c0/contract-validate.json")" = fail ]
  [ ! -f "$EV/fsm-state.yaml" ]
}

@test "direct: a resume after the seal still refuses when the PM page went missing" {
  AID_PLAN_FSM_CRASH_AFTER=seal _run
  [ "$status" -eq 99 ]
  rm -f "$R/.aid-o/work/evidence/P900/plan-summary-artifact.html"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: plan_page_missing)"* ]]
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

# ── review of steps 2-4: the recoveries the refusals name, and the binding ──
@test "direct: the plan_changed_since_seal recovery (archive the plan-run transaction) leads to a fresh start" {
  AID_PLAN_FSM_CRASH_AFTER=seal _run
  [ "$status" -eq 99 ]
  echo "edited after the seal" >> "$PLAN"
  git -C "$R" add -f "$PLAN" && git -C "$R" commit -qm "edited plan"
  ( export AID_PLUGIN_PATH="$PLUGIN_DIR"; source "$PLUGIN_DIR/scripts/tests/lib/aid-test-plan-fixture.sh"; aid_fixture_seed_plan_review "$R" "$PLAN" >/dev/null ); _page
  _run
  [ "$status" -eq 1 ]; [[ "$output" == *plan_changed_since_seal* ]]
  mv "$GEN/transaction.json" "$GEN/transaction.json.superseded-1"
  _run
  [ "$status" -eq 0 ]
  [[ "$output" != *epic_path_removed* ]]
}

@test "direct: plan-run resumed from another directory (the plan worktree) passes its receipt check" {
  AID_PLAN_FSM_CRASH_AFTER=receipt _run
  [ "$status" -eq 99 ]
  run bash -c "cd '$R/.aid-worktrees/plan-P900' && bash '$PFSM' plan-run P900 --project-root '$R'"
  [ "$status" -eq 0 ]
  [ -f "$EV/fsm-state.yaml" ]
}

@test "direct: a plan.json widened after the plan_json stage is refused before init (its hash is the stage's)" {
  AID_PLAN_FSM_CRASH_AFTER=contract_validate _run
  [ "$status" -eq 99 ]
  jq '.steps[0].allowed_paths += ["**"] | .gates = []' "$EV/plan.json" > "$EV/t" && mv "$EV/t" "$EV/plan.json"
  _run
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan_json_unverified"* ]]
  [ ! -f "$EV/fsm-state.yaml" ]
}

@test "direct: --force-init-reason with spaces reaches init as one reason" {
  _run --force-init-reason "approved lineage recovery; with spaces & a semicolon"
  [ "$status" -eq 0 ]
  grep -q 'approved lineage recovery; with spaces & a semicolon' "$EV/timeline.jsonl" \
    || grep -rq 'approved lineage recovery; with spaces & a semicolon' "$R/.aid-o/work/audit-log.jsonl"
}

# ── P112 Step 5: plan-run --restart — a run that made no step starts again ────
WHY="the run needs the corrected plan before step 1"
_rs()   { run bash "$PFSM" plan-run P900 --restart --reason "$WHY" "$@"; }
_sr()   { ls -d "$R/.aid-o/work/superseded-runs/P900-"* 2>/dev/null | tail -1; }
_states() { find "$R/.aid-o/work/evidence" -name fsm-state.yaml | wc -l; }
_ev_add() { printf '{"ts":"%s","event":"%s"}\n' "${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" "$1" >> "$EV/timeline.jsonl"; }

@test "restart: a run that made no step restarts — one READY state, one map entry, the old run abandoned under superseded-runs/" {
  _run_ok; [ "$status" -eq 0 ]
  _rs; echo "$output"; [ "$status" -eq 0 ]
  local sr; sr="$(_sr)"; [ -n "$sr" ]
  [ "$(yq -r .state "$EV/fsm-state.yaml")" = READY ]
  [ "$(_states)" = 1 ]                                                    # the set-aside run is invisible to evidence readers
  [ "$(jq -r 'keys | join(",")' "$R/.aid-o/work/active-runs.json")" = "E-900-1_1" ]
  [ "$(yq -r .abandoned "$sr/evidence-E-900-1_1-R-E900-1/fsm-state.yaml")" = true ]
  [ -f "$sr/transaction.json" ] && [ "$(jq -r .state "$sr/restart.json")" = done ]
  [ "$(jq -r .restarted_from "$GEN/transaction.json")" = "${sr#"$R/"}" ]
  [ "$(jq -r .reason "$sr/restart.json")" = "$WHY" ]
}
@test "restart: the restart leaves the audit record, the timeline event and the audit-log line supersede-generation leaves" {
  _run_ok; _rs; [ "$status" -eq 0 ]
  local ep; ep="$(jq -r .epoch "$(_sr)/restart.json")"
  jq -e '.schema == "aid-generation-supersede/v1" and .plan_id == "P900" and (.reason | startswith("restart: "))' "$GEN/generation-superseded-${ep}.json"
  grep -q "\"event\":\"generation_superseded\".*\"epoch\":\"${ep}\"" "$GEN/timeline.jsonl"
  grep -q '"event":"generation_superseded"' "$R/.aid-o/work/audit-log.jsonl"
  [ "$(jq -r .archived_transaction "$GEN/generation-superseded-${ep}.json")" = "$(_sr)/transaction.json" ]
}
@test "restart: a plan edited between the runs (repo_roots added, CP1 again) restarts and creates the foreign worktree" {
  _run_ok; [ "$status" -eq 0 ]
  local F="$BATS_TEST_TMPDIR/docs"; _mk_foreign "$F"
  sed -i "s|^lifecycle_strict: true$|lifecycle_strict: true\nrepo_roots:\n  - name: docs\n    path: $F|" "$PLAN"
  git -C "$R" add -f "$PLAN" && git -C "$R" commit -qm "the plan declares its foreign repository"
  ( export AID_PLUGIN_PATH="$PLUGIN_DIR"; source "$PLUGIN_DIR/scripts/tests/lib/aid-test-plan-fixture.sh"; aid_fixture_seed_plan_review "$R" "$PLAN" >/dev/null ); _page
  _rs; echo "$output"; [ "$status" -eq 0 ]
  [ "$(git -C "$F/.aid-worktrees/plan-P900--docs" rev-parse --abbrev-ref HEAD)" = "plan/P900-p" ]
  [ "$(jq -r '.repo_roots[0].name' "$EV/plan.json")" = docs ]
}
@test "restart: a run past its first step is refused restart_after_step and nothing moves" {
  _run_ok; yq -i '.current_step = 1' "$EV/fsm-state.yaml"
  _rs; [ "$status" -eq 1 ]
  [[ "$output" == *"current_step is 1"*"(pipeline.md §When AID refuses: restart_after_step)"* && "$output" == *"next: "* ]]
  [ -z "$(_sr)" ] && [ -f "$GEN/transaction.json" ]
}
@test "restart: a step_commit in the timeline is refused restart_after_step" {
  _run_ok; _ev_add step_commit
  _rs; [ "$status" -eq 1 ]; [[ "$output" == *"step_commit"*"restart_after_step"* ]]
}
@test "restart: a return naming repo_commits without increment-step is refused restart_after_step" {
  _run_ok; mkdir -p "$EV/steps/step_1_backend"; echo '{"repo_commits":[{"repo":"docs","range":"a..b"}]}' > "$EV/steps/step_1_backend/return.json"
  _rs; [ "$status" -eq 1 ]; [[ "$output" == *"repo_commits"*"restart_after_step"* ]]
}
@test "restart: a DONE run is refused restart_after_step" {
  _run_ok; yq -i '.state = "DONE"' "$EV/fsm-state.yaml"
  _rs; [ "$status" -eq 1 ]; [[ "$output" == *"DONE"*"restart_after_step"* ]]
}
@test "restart: an uncommitted edit in the plan's worktree is refused restart_plan_dirty" {
  _run_ok; echo dirt > "$R/.aid-worktrees/plan-P900/dirt.txt"
  _rs; [ "$status" -eq 1 ]; [[ "$output" == *"(pipeline.md §When AID refuses: restart_plan_dirty)"* ]]
}
@test "restart: a commit on plan/<id> above the run's base made outside a step is refused restart_plan_dirty" {
  _run_ok; local W="$R/.aid-worktrees/plan-P900"
  echo x > "$W/hand.txt"; git -C "$W" add hand.txt; git -C "$W" commit -qm "by hand"
  _rs; [ "$status" -eq 1 ]; [[ "$output" == *"1 commit(s) above the run's base"*"restart_plan_dirty"* ]]
}
@test "restart: a foreign worktree with an untracked file is refused restart_foreign_dirty" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900; [ "$status" -eq 0 ]
  echo u > "$F/.aid-worktrees/plan-P900--docs/untracked.md"
  run bash "$PFSM" plan-run P900 --restart --reason "$WHY"; [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes"*"(pipeline.md §When AID refuses: restart_foreign_dirty)"* ]]
}
@test "restart: a foreign branch with a commit above its base is refused restart_foreign_dirty" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900; [ "$status" -eq 0 ]
  local W="$F/.aid-worktrees/plan-P900--docs"; echo c >> "$W/index.md"; git -C "$W" commit -qam "foreign work"
  run bash "$PFSM" plan-run P900 --restart --reason "$WHY"; [ "$status" -eq 1 ]
  [[ "$output" == *"commits above its base"*"restart_foreign_dirty"* ]]
}
@test "restart: an adopted foreign worktree keeps its fork point as base when the base branch moved on" {
  local F="$BATS_TEST_TMPDIR/docs" R2="$BATS_TEST_TMPDIR/proj"
  _mk_foreign "$F"; _seed_rr "$R2" "$F"
  run bash "$PFSM" plan-run P900; [ "$status" -eq 0 ]
  local fork; fork="$(git -C "$F" rev-parse main)"
  echo later > "$F/later.md"; git -C "$F" add later.md; git -C "$F" commit -qm "main moves on"
  run bash "$PFSM" plan-run P900 --restart --reason "$WHY"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.repo_roots[0].base' "$R2/.aid-o/work/evidence/E-900-1_1/R-E900-1/plan.json")" = "$fork" ]
  [ "$(git -C "$F" worktree list | grep -c 'plan-P900--docs')" = 1 ]
}
@test "restart: a run whose controller is active with a fresh timeline event is refused restart_controller_live" {
  _run_ok
  jq '.["E-900-1_1"].auto_controller = "active"' "$R/.aid-o/work/active-runs.json" > m.t && mv m.t "$R/.aid-o/work/active-runs.json"
  _ev_add heartbeat
  _rs; [ "$status" -eq 1 ]; [[ "$output" == *"(pipeline.md §When AID refuses: restart_controller_live)"* ]]
}
@test "restart: the same active controller whose last event is an hour old (the P016 case) restarts" {
  _run_ok
  jq '.["E-900-1_1"].auto_controller = "active"' "$R/.aid-o/work/active-runs.json" > m.t && mv m.t "$R/.aid-o/work/active-runs.json"
  _ev_add heartbeat "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)"
  _rs; echo "$output"; [ "$status" -eq 0 ]
}
@test "restart: --restart without a reason of 20 characters is refused before anything moves" {
  _run_ok
  run bash "$PFSM" plan-run P900 --restart; [ "$status" -eq 2 ]
  run bash "$PFSM" plan-run P900 --restart --reason "too short"; [ "$status" -eq 2 ]; [[ "$output" == *"nothing was moved"* ]]
  [ -z "$(_sr)" ] && [ -f "$EV/fsm-state.yaml" ]
}
@test "restart: plan_run_already_started on a run without a step names --restart in its next:" {
  _run_ok; _run
  [ "$status" -eq 1 ]; [[ "$output" == *"next: "*"plan-run P900 --restart --reason"* ]]
}
@test "restart: nothing to restart without a transaction" {
  _rs; [ "$status" -eq 2 ]; [[ "$output" == *"nothing to restart"* ]]
}
@test "restart: interrupted after the evidence moved, the same command finishes the restart" {
  _run_ok
  AID_PLAN_FSM_CRASH_AFTER=restart_moved_evidence _rs; [ "$status" -eq 99 ]
  [ "$(jq -r .state "$(_sr)/restart.json")" = moving ] && [ -f "$GEN/transaction.json" ]
  _rs; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_states)" = 1 ] && [ "$(jq -r .state "$(_sr)/restart.json")" = done ]
  [ "$(ls -d "$R/.aid-o/work/superseded-runs/P900-"* | wc -l)" = 1 ]
}
@test "restart: interrupted after the transaction moved, the same command finishes the restart" {
  _run_ok
  AID_PLAN_FSM_CRASH_AFTER=restart_moved_tx _rs; [ "$status" -eq 99 ]
  [ ! -f "$GEN/transaction.json" ]
  _rs; echo "$output"; [ "$status" -eq 0 ]
  [ "$(yq -r .state "$EV/fsm-state.yaml")" = READY ] && [ "$(jq -r .state "$(_sr)/restart.json")" = done ]
}

# ── P114 Step 3: a direct plan needs no EPIC marker ──────────────────────────
@test "no-epic: plan-run starts a plan that has no EPIC marker" {
  local R2="$BATS_TEST_TMPDIR/noepic"
  _mk_project "$R2" >/dev/null
  sed '/^\*\*EPIC 1: Steps 1-2\*\*$/d' "$FIXTURE_PLAN" > "$BATS_TEST_TMPDIR/noepic.md"
  ! grep -q '^\*\*EPIC' "$BATS_TEST_TMPDIR/noepic.md"
  _seed "$R2" "$BATS_TEST_TMPDIR/noepic.md"
  cd "$R2"
  run bash "$PFSM" plan-run P900; echo "$output"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.direct' "$R2/.aid-o/work/evidence/E-900-1_1/R-E900-1/fsm-state.yaml")" = true ]
  [ "$(jq '.steps | length' "$R2/.aid-o/work/evidence/E-900-1_1/R-E900-1/plan.json")" = 2 ]
}
