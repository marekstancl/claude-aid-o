#!/usr/bin/env bats
# aid-tier: t2
#
# `plan-close --administrative` — closing a plan that has no evidence chain.
#
# The PM asked for this for two real cases (2026-09-02): a plan written in AID
# but developed outside it, and a plugin defect that strands a plan for hours.
# ACTA's P019 showed why `--force` cannot serve either: force unlocks a CHECK
# over data that is real, and there the data was absent or said `fail`, so
# forcing would have meant inventing a candidate, a run id and a verdict. The
# reporting agent refused to fabricate them even with the PM's blessing.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FSM="$PLUGIN_ROOT/scripts/aid-plan-fsm.sh"
}

@test "the flag exists and is documented as different from --force" {
  grep -q -- '--administrative) _PFSM_ADMIN_CLOSE=1' "$FSM"
  local block
  block="$(sed -n '/ADMINISTRATIVE CLOSE — a different thing from --force/,/--administrative)/p' "$FSM")"
  [[ "$block" == *"unlocks a CHECK over data that is real"* ]]
  [[ "$block" == *"fabricating evidence"* ]]
}

@test "--administrative and --force are refused together" {
  local block
  block="$(sed -n '/An administrative close is a PM decision on the record/,/^  fi/p' "$FSM")"
  [[ "$block" == *"say different things"* ]]
  [[ "$block" == *"pick one"* ]]
  [[ "$block" == *"exit 2"* ]]
}

@test "a reason of at least 20 characters is required" {
  local block
  block="$(sed -n '/An administrative close is a PM decision on the record/,/^  fi/p' "$FSM")"
  [[ "$block" == *'lt 20'* ]]
  [[ "$block" == *"recorded verbatim"* ]]
}

@test "it records what could not be confirmed instead of asserting it" {
  grep -q '_PFSM_ADMIN_MISSING=' "$FSM"
  grep -q 'what could not be confirmed' "$FSM"
}

@test "the close never reads as an ordinary one" {
  grep -q 'CLOSED ADMINISTRATIVELY' "$FSM"
  grep -q 'closed_administrative' "$FSM"
  local block
  block="$(sed -n '/CLOSED ADMINISTRATIVELY/,/elif/p' "$FSM")"
  [[ "$block" == *"does not count as it"* ]]
}

@test "no candidate, run id or verdict is written by this path" {
  local block
  block="$(sed -n '/ADMINISTRATIVE CLOSE: .* is being closed WITHOUT evidence/,/ccrc=0/p' "$FSM")"
  [[ "$block" == *"nothing below fabricates a candidate"* ]]
}

# --- Codex's two high findings on the implementation, 2026-09-02 -----------

@test "the guard classifies findings; it does not test two manifest fields" {
  # The first cut asked whether candidate_sha and plan_final_run_id were both
  # present and called "not both" an absence of evidence. A frozen candidate
  # with a negative verdict and no final run passed that test (Codex,
  # 2026-09-02). The decision is now per finding.
  local block
  block="$(sed -n '/WHAT THIS CLOSES IS DECIDED POSITIVELY/,/ccrc=0/p' "$FSM")"
  [[ "$block" == *"EVERY ONE of them has to"* ]]
  [[ "$block" == *"A finding that says something"* ]]   # …went WRONG is not an absence
  [[ "$block" == *"EVERY ONE of them has to"* ]]
  [[ "$block" != *'plan_boundary_manifest.candidate_sha'* ]]
}

@test "unrecognised findings refuse, in the code as well as in the tests" {
  local block
  block="$(sed -n '/WHAT THIS CLOSES IS DECIDED POSITIVELY/,/ccrc=0/p' "$FSM")"
  [[ "$block" == *"Unrecognised text refuses too"* ]]
  [[ "$block" == *"guesses in the permissive direction"* ]]
}

@test "the refusal prints the findings it objected to" {
  local block
  block="$(sed -n '/WHAT THIS CLOSES IS DECIDED POSITIVELY/,/ccrc=0/p' "$FSM")"
  [[ "$block" == *"could be closing around what it concluded"* ]]
  [[ "$block" == *'_adm_bad'* ]]
  [[ "$block" == *"exit 1"* ]]
}

# --- the guard EXERCISED, not merely grepped ------------------------------
# Codex, 2026-09-02: "the added tests are string-presence checks; they do not
# exercise the guard's actual manifest combinations". These call the classifier
# with real check output instead.

# THE TEST IS NOW ABOUT EVIDENCE ON DISK, not about wording.
# Six rounds of classifying the close check's prose each ended with a new string
# that slipped through; the guard no longer reads prose at all. These call the
# production function that decides.
_evidence() {
  MANIFEST_STUB="${MANIFEST_STUB:-}" bash -c "
    plan_manifest_get() { printf '%s' \"\${MANIFEST_STUB:-}\"; }
    plan_manifest_path() { printf '%s' \"\$1/.aid-o/work/plan-state/\$2/plan-boundary-manifest.json\"; }
    eval \"\$(sed -n '/^_pfsm_admin_close_evidence()/,/^}/p' '$FSM')\"
    _pfsm_admin_close_evidence \"\$1\" \"\$2\"" _ "$1" "$2"
}

@test "evidence: a plan with nothing recorded and nothing on disk may be closed" {
  local root="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$root/.aid-o/work/evidence/P019"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -z "$output" ]
}

@test "evidence: an audit report on disk refuses the close, and is named" {
  local root="$BATS_TEST_TMPDIR/withaudit"
  mkdir -p "$root/.aid-o/work/evidence/P019/R-P019-final-1"
  printf '{"status":"fail"}' > "$root/.aid-o/work/evidence/P019/R-P019-final-1/audit-report.json"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -n "$output" ]
  [[ "$output" == *"audit-report.json"* ]]
}

@test "evidence: a closed whole-plan round, a release decision or an older curator report each refuse" {
  local root="$BATS_TEST_TMPDIR/each" f
  for f in cp7/rounds.json release-decision.json curator-report.json; do
    rm -rf "$root"; mkdir -p "$root/.aid-o/work/evidence/P019/R-1/cp7"
    printf '{}' > "$root/.aid-o/work/evidence/P019/R-1/$f"
    MANIFEST_STUB="" run _evidence "$root" P019
    [ -n "$output" ]
  done
}

@test "evidence: a recorded candidate refuses even with an empty evidence tree" {
  local root="$BATS_TEST_TMPDIR/cand"
  mkdir -p "$root/.aid-o/work/evidence/P019"
  MANIFEST_STUB="abc123" run _evidence "$root" P019
  [ -n "$output" ]
  [[ "$output" == *"manifest."* ]]
}

@test "evidence: the refusal cannot be talked around — no wording is consulted" {
  # The inputs that defeated six rounds of prose classification: none of them is
  # read any more. What decides is whether the artifacts exist.
  local root="$BATS_TEST_TMPDIR/prose"
  mkdir -p "$root/.aid-o/work/evidence/P019"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -z "$output" ]                      # no evidence -> may close, whatever any message said
  printf '{}' > "$root/.aid-o/work/evidence/P019/x.json"
  mkdir -p "$root/.aid-o/work/evidence/P019/R-1"
  printf '{}' > "$root/.aid-o/work/evidence/P019/R-1/audit-report.json"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -n "$output" ]                      # evidence -> refuses, whatever any message said
}

@test "evidence: a corrupt manifest is broken, not absent — it blocks" {
  local root="$BATS_TEST_TMPDIR/corrupt"
  mkdir -p "$root/.aid-o/work/plan-state/P019" "$root/.aid-o/work/evidence/P019"
  printf '{ this is not json' > "$root/.aid-o/work/plan-state/P019/plan-boundary-manifest.json"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -n "$output" ]
  [[ "$output" == *"not parseable"* ]]
}

@test "evidence: work still in progress blocks — it is unfinished, not absent" {
  local root="$BATS_TEST_TMPDIR/running"
  mkdir -p "$root/.aid-o/work/evidence/P019/R-1"
  printf 'state: EXECUTE\n' > "$root/.aid-o/work/evidence/P019/R-1/fsm-state.yaml"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -n "$output" ]
  [[ "$output" == *"still in progress"* ]]
}

@test "evidence: a terminal run with no verdict artifacts does not block" {
  local root="$BATS_TEST_TMPDIR/terminal"
  mkdir -p "$root/.aid-o/work/evidence/P019/R-1"
  printf 'state: DONE\n' > "$root/.aid-o/work/evidence/P019/R-1/fsm-state.yaml"
  MANIFEST_STUB="" run _evidence "$root" P019
  [ -z "$output" ]
}

# --- P099 Step 3: the "plan delivered" message ------------------------------
# The block runs in the close's merge branch only, after the close is durable.
# It is exercised here with a stubbed sender (a full merge close needs the whole
# plan-final chain, which test-aid-plan-final-boundary.bats owns).
_delivered() {
  local block; block="$(sed -n '/The PM.s second message (P099 Step 3)/,/|| true$/p' "$FSM")"
  bash -c "set -euo pipefail; SCRIPT_DIR='$PLUGIN_ROOT/scripts' root='$1' plan_id=P900 run_dir_rel=ev/P900
           _PFSM_FORCE='${2:-0}'; close() { $block
           }; close; echo closed-ok"
}
@test "delivered: a close sends plan-delivered once, says forced, and a failed send leaves the close untouched" {
  local t="$BATS_TEST_TMPDIR"; mkdir -p "$t/p"; git -C "$t/p" init -q
  printf 'send_alert() { echo "$3|$4" >> "%s/sent"; }\n' "$t" > "$t/tg.sh"
  AID_TEST_MODE=1 AID_TELEGRAM_LIB="$t/tg.sh" AID_SESSION_STORE="$t/store" run _delivered "$t/p" 1
  [[ "$output" == *closed-ok* ]]
  [ "$(cat "$t/sent")" = "plan-delivered|P900 dodán (uzavřen vynuceně)" ]
  printf 'send_alert() { return 9; }\n' > "$t/tg.sh"
  AID_TEST_MODE=1 AID_TELEGRAM_LIB="$t/tg.sh" AID_SESSION_STORE="$t/store2" run _delivered "$t/p" 0
  [ "$status" -eq 0 ]; [[ "$output" == *closed-ok* ]]
  # the abort branch sends nothing: the block sits inside `close_mode == merge`
  [ "$(sed -n '/if \[\[ "\$close_mode" == "merge" \]\]; then/,/The PM.s second message/p' "$FSM" | tail -3 | grep -c 'second message')" -eq 1 ]
}

# --- P100 Step 9: a plan merged by hand, stopped in PLAN_GATES ---------------
# _gates_plan <root> — P900 on plan_branch, moved to PLAN_GATES, its branch merged
# into main by hand; a wave's step tree and branch, and a brainstorm scratch tree.
_gates_plan() {
  local R="$1"
  git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  printf '.aid-o/work/\n.aid-worktrees/\n' > "$R/.gitignore"; git -C "$R" add -A; git -C "$R" commit -qm base
  local base; base="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" branch plan/P900
  ( cd "$R" && export AID_PLAN_STATE_PROJECT_ROOT="$R" AID_PLAN_MANIFEST_PROJECT_ROOT="$R"
    source "$PLUGIN_ROOT/scripts/lib/aid-plan-state.sh"; source "$PLUGIN_ROOT/scripts/lib/aid-plan-manifest.sh"
    plan_state_init P900 plan_branch plan/P900 main >/dev/null
    for s in EPIC_INTEGRATION PLAN_SYNC PLAN_GATES; do plan_state_transition P900 "$(plan_state_get P900 plan_state)" "$s" >/dev/null; done
    plan_manifest_init P900 plan/P900 main "$base" "$base" plan_branch >/dev/null )
  git -C "$R" worktree add -q -b step/s1 "$R/.aid-worktrees/step-s1" plan/P900
  git -C "$R/.aid-worktrees/step-s1" commit -q --allow-empty -m "step 1"
  git -C "$R" checkout -q plan/P900; git -C "$R" merge -q --no-edit step/s1; git -C "$R" checkout -q main
  git -C "$R" merge -q --no-edit plan/P900
  git -C "$R" worktree add -q --detach "$R/.aid-worktrees/brainstorm-P900" main
  git -C "$R" worktree add -q --detach "$R/.aid-worktrees/generation-P900" main
  echo wip > "$R/.aid-worktrees/generation-P900/wip.txt"
  git -C "$R" worktree add -q -b step/s9 "$R/.aid-worktrees/step-s9" main
  git -C "$R/.aid-worktrees/step-s9" commit -q --allow-empty -m "an abandoned retry"
  git -C "$R" branch step/other main          # another plan's wave, just started
  mkdir -p "$R/.aid-o/work/evidence/E-900-1_1/R-1"
  echo '{"steps":[{"id":"s1"},{"id":"s9"}]}' > "$R/.aid-o/work/evidence/E-900-1_1/R-1/plan.json"
}

@test "P100: --administrative closes a hand-merged plan from PLAN_GATES, cleans what it contains, keeps and names the rest; a normal close is refused there" {
  local R="$BATS_TEST_TMPDIR/p"; mkdir -p "$R"; _gates_plan "$R"
  run bash -c "cd '$R' && AID_TEST_MODE=1 bash '$FSM' plan-close P900 --project-root '$R'"
  [ "$status" -ne 0 ]; [[ "$output" == *"--administrative"* ]]
  run bash -c "cd '$R' && AID_TEST_MODE=1 bash '$FSM' plan-close P900 --project-root '$R' --administrative --reason 'P900 was merged by hand outside plan-finalize'"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(yq -r .plan_state "$R/.aid-o/work/plan-state/P900/plan-state.yaml")" = CLOSED ]
  [ -z "$(git -C "$R" branch --list 'step/s1')" ]
  [ ! -d "$R/.aid-worktrees/step-s1" ] && [ ! -d "$R/.aid-worktrees/brainstorm-P900" ]
  [ -n "$(git -C "$R" branch --list 'step/s9')" ] && [ -n "$(git -C "$R" branch --list 'step/other')" ]
  jq -e '[.kept[].path] | index("step/s9") != null' "$R/.aid-o/work/evidence/P900/cleanup.json"
  jq -e '(.removed | length) >= 3' "$R/.aid-o/work/evidence/P900/cleanup.json"
  jq -e '.kept[] | select(.path | endswith("generation-P900")) | .why == "uncommitted work"' "$R/.aid-o/work/evidence/P900/cleanup.json"
  [[ "$output" == *"kept: $R/.aid-worktrees/generation-P900 — uncommitted work"* ]]
}

# --- 2.107.1: a hand-merged plan WITH a lifecycle manifest (the P101 shape) -----
# _lifecycle_manifest <root> — the tracked manifest a real AID plan carries: two
# required EPICs, no deliveries (the hand merge never bound any).
_lifecycle_manifest() {
  local R="$1"
  mkdir -p "$R/.aid-lifecycle/manifests"
  printf 'schema_version: aid-lifecycle-1.0\nrepo_id: 0663532a-3dd2-40cb-91fc-5dac362bfcc0\nplan_id: P900\nsource_plan_sha: sha256:%064d\ndeclared_epics:\n  - {id: E-900-1_2, scope: required}\n  - {id: E-900-2_2, scope: required}\ndepends_on_plans: []\nmode: plan_branch\n' 0 \
    > "$R/.aid-lifecycle/manifests/P900.yaml"
  git -C "$R" add -f .aid-lifecycle; git -C "$R" commit -qm "lifecycle: manifest for P900"
}

@test "2.107.1: a hand-merged plan with a lifecycle manifest closes administratively with a receipt that says so, hash refs only; unmerged, no receipt" {
  local R="$BATS_TEST_TMPDIR/p"; mkdir -p "$R"; _gates_plan "$R"; _lifecycle_manifest "$R"
  local reason='merged by hand as 2.106.0 on /opt/x, token: none — PM 25. 9.'
  run bash -c "cd '$R' && AID_TEST_MODE=1 bash '$FSM' plan-close P900 --project-root '$R' --administrative --reason '$reason'"
  echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" != *"is active"* && "$output" == *"lifecycle: receipt_administrative"* ]]
  local receipt rec; receipt="$(git -C "$R" show main:.aid-lifecycle/receipts/P900.yaml)"
  rec="$R/.aid-o/work/evidence/P900/plan-close-administrative.json"
  [ "$(yq -r '[.epics[].verdict] | unique | join(",")' <<<"$receipt")" = administrative ]
  # every EPIC names the merge and the PM's record by digest, never by its words
  [ "$(yq -r '[.epics[].waivers[0]] | unique | .[]' <<<"$receipt")" = "administrative-close:$(git -C "$R" rev-parse plan/P900):sha256:$(sha256sum "$rec" | cut -d' ' -f1)" ]
  [[ "$receipt" != *"/opt/x"* && "$receipt" != *"token"* ]]
  [ "$(jq -r .reason "$rec")" = "$reason" ]
  run bash -c "cd '$R' && bash '$PLUGIN_ROOT/scripts/aid-lifecycle.sh' state P900 ."
  [ "$output" = closed ]
}

@test "2.107.1: the lifecycle library refuses an administrative close whose commit is not in the target branch" {
  local R="$BATS_TEST_TMPDIR/p"; mkdir -p "$R"; _gates_plan "$R"; _lifecycle_manifest "$R"
  git -C "$R" checkout -q -b elsewhere; git -C "$R" commit -q --allow-empty -m "not merged"
  local stray; stray="$(git -C "$R" rev-parse HEAD)"; git -C "$R" checkout -q main
  run bash -c "cd '$R' && source '$PLUGIN_ROOT/scripts/lib/aid-lifecycle.sh' && aid_lifecycle_plan_close P900 . '' '$stray' 'sha256:$(printf %064d 0)'"
  [ "$status" -ne 0 ]; [[ "$output" == *"is active"* ]]
  run bash -c "cd '$R' && source '$PLUGIN_ROOT/scripts/lib/aid-lifecycle.sh' && aid_lifecycle_plan_close P900 ."
  [ "$status" -ne 0 ]
  [ -z "$(git -C "$R" ls-tree main .aid-lifecycle/receipts/P900.yaml)" ]
}


# ── P111 Step 5: cancellation reaches the FSM and active-runs.json ──────────
_ab_project() {
  export AID_TEST_MODE=1 AID_PLUGIN_PATH="$PLUGIN_ROOT"
  AB="$BATS_TEST_TMPDIR/p"; mkdir -p "$AB"; cd "$AB"
  git init -q -b main; git config user.email t@t; git config user.name t
  echo x > a; git add a; git commit -qm init
  AFSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  MAP="$AB/.aid-o/work/active-runs.json"
  source "$PLUGIN_ROOT/scripts/tests/lib/aid-test-plan-fixture.sh"
}

# _ab_two_epics — plan P920 (plan_branch) with two EPIC runs READY in the FSM,
# the map and the manifest (the P080 shape before its close).
_ab_two_epics() {
  _ab_project
  mkdir -p .aid-o/plans .aid-o/config
  printf 'gates: {}\n' > .aid-o/config/execution.yaml
  printf -- '---\nid: P920\n---\n\n# Plan: two runs\n\n**EPIC 1: one**\n\n### Step 1: a\n\n**AID Role:** backend\n\n**EPIC 2: two**\n\n### Step 2: b\n\n**AID Role:** backend\n' > .aid-o/plans/P920-two.md
  git add -f .aid-o; git commit -qm plan
  bash "$FSM" plan-start P920 --mode plan_branch --project-root "$AB" >/dev/null 2>&1
  local tip e r; tip="$(git rev-parse plan/P920)"
  echo '{}' > "$MAP"
  for e in E-920-1_2 E-920-2_2; do
    r="R-E920-${e:6:1}"
    mkdir -p ".aid-o/work/evidence/$e/$r"
    printf 'epic_id: %s\nrun_id: %s\nstate: READY\ncurrent_step: 0\ntotal_steps: 1\nmode: full\nbranch: task/%s/main\nbase_commit: %s\n' "$e" "$r" "$e" "$tip" > ".aid-o/work/evidence/$e/$r/fsm-state.yaml"
    ( export AID_PLAN_MANIFEST_PROJECT_ROOT="$AB"; source "$PLUGIN_ROOT/scripts/lib/aid-plan-manifest.sh"
      plan_manifest_add_epic P920 "$e" "$r" "task/$e/main" "$tip" plan/P920 ".aid-o/work/evidence/$e/$r" proven >/dev/null )
    jq --arg e "$e" --arg sf ".aid-o/work/evidence/$e/$r/fsm-state.yaml" --arg r "$r" \
      '.[$e] = {state_file: $sf, run_id: $r, state: "READY", branch: ("task/" + $e + "/main"), plan_id: "P920"}' "$MAP" > "$MAP.t" && mv "$MAP.t" "$MAP"
  done
  MF="$AB/.aid-o/work/plan-state/P920/plan-boundary-manifest.json"
  SF1="$AB/.aid-o/work/evidence/E-920-1_2/R-E920-1/fsm-state.yaml"
  SF2="$AB/.aid-o/work/evidence/E-920-2_2/R-E920-2/fsm-state.yaml"
}
_st() { yq -r ".$2" "$1"; }

@test "abandon: an administrative close ends both READY runs in the FSM and removes them from active-runs.json" {
  _ab_two_epics
  run bash "$FSM" plan-close P920 --administrative --reason "the plan was replaced by a new plan, P921"
  for sf in "$SF1" "$SF2"; do
    [ "$(_st "$sf" state)" = "ERROR" ]; [ "$(_st "$sf" abandoned)" = "true" ]
    [ "$(_st "$sf" abandon_reason)" = "the plan was replaced by a new plan, P921" ]
    grep -q '"event":"abandoned"' "$(dirname "$sf")/timeline.jsonl"
  done
  [ "$(jq 'length' "$MAP")" = "0" ]
  [ "$(jq -c '[.plan_boundary_manifest.epic_runs[].status]' "$MF")" = '["abandoned","abandoned"]' ]
}

@test "abandon: an administrative close abandons only the running run, never the merged one" {
  _ab_two_epics
  ( export AID_PLAN_MANIFEST_PROJECT_ROOT="$AB"; source "$PLUGIN_ROOT/scripts/lib/aid-plan-manifest.sh"
    plan_manifest_set_epic_status P920 E-920-1_2 merged_to_plan "$(git rev-parse plan/P920)" >/dev/null )
  run bash "$FSM" plan-close P920 --administrative --reason "closing after a hand merge of the first run"
  [ "$(jq -r '.plan_boundary_manifest.epic_runs[0].status' "$MF")" = "merged_to_plan" ]
  [ "$(_st "$SF1" state)" = "READY" ]
  [ "$(_st "$SF2" state)" = "ERROR" ]; [ "$(_st "$SF2" abandoned)" = "true" ]
}

@test "abandon: epic-complete --abandon ends that one run only" {
  _ab_two_epics
  run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "superseded by a later design"
  [ "$status" -eq 0 ]
  [ "$(_st "$SF2" state)" = "ERROR" ]; [ "$(_st "$SF1" state)" = "READY" ]
  [ "$(jq -r 'keys | join(",")' "$MAP")" = "E-920-1_2" ]
}

@test "abandon: --abandon with an empty reason is refused abandon_needs_reason before any write" {
  _ab_two_epics
  run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"(pipeline.md §When AID refuses: abandon_needs_reason)"* ]]
  [ "$(jq -r '.plan_boundary_manifest.epic_runs[1].status' "$MF")" = "running" ]
  [ "$(_st "$SF2" state)" = "READY" ]
  run bash "$AFSM" abandon "$SF2" --reason ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"abandon_needs_reason"* ]]
}

@test "abandon: interrupted after the manifest write, the same epic-complete --abandon completes FSM and map with the same reason" {
  _ab_two_epics
  AID_PLAN_FSM_CRASH_AFTER=manifest run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "first reason recorded"
  [ "$status" -eq 99 ]
  [ "$(_st "$SF2" state)" = "READY" ]; [ "$(jq -r 'has("E-920-2_2")' "$MAP")" = "true" ]
  run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "a different reason on the rerun"
  [ "$status" -eq 0 ]
  [ "$(_st "$SF2" state)" = "ERROR" ]; [ "$(_st "$SF2" abandon_reason)" = "first reason recorded" ]
  [ "$(jq -r 'has("E-920-2_2")' "$MAP")" = "false" ]
}

@test "abandon: interrupted after the manifest write, plan-close --administrative selects the abandoned entry by its unfinished FSM and completes it" {
  _ab_two_epics
  AID_PLAN_FSM_CRASH_AFTER=manifest run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "abandoned before the close ran"
  [ "$status" -eq 99 ]
  run bash "$FSM" plan-close P920 --administrative --reason "closing the plan administratively now"
  [ "$(_st "$SF2" state)" = "ERROR" ]; [ "$(_st "$SF2" abandon_reason)" = "abandoned before the close ran" ]
  [ "$(jq 'length' "$MAP")" = "0" ]
}

@test "abandon: interrupted after the FSM write only the map entry is left, and the rerun removes it" {
  _ab_two_epics
  AID_PLAN_FSM_CRASH_AFTER=fsm run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "abandon in two halves"
  [ "$status" -eq 99 ]
  [ "$(_st "$SF2" state)" = "ERROR" ]; [ "$(jq -r 'has("E-920-2_2")' "$MAP")" = "true" ]
  run bash "$FSM" epic-complete P920 E-920-2_2 --abandon --reason "abandon in two halves"
  [ "$status" -eq 0 ]
  [ "$(jq -r 'has("E-920-2_2")' "$MAP")" = "false" ]
}

@test "abandon: the P080 shape — a plan CLOSED with its marker and two READY runs — gets both abandoned before ALREADY CLOSED" {
  _ab_two_epics
  ( export AID_PLAN_STATE_PROJECT_ROOT="$AB"; source "$PLUGIN_ROOT/scripts/lib/aid-plan-state.sh"
    f="$(plan_state_path P920)"; yq -i '.plan_state = "CLOSED"' "$f" )
  local marker; marker="$(bash -c "source '$PLUGIN_ROOT/scripts/aid-plan-fsm.sh' >/dev/null 2>&1; export AID_PLAN_STATE_PROJECT_ROOT='$AB' AID_PLAN_MANIFEST_PROJECT_ROOT='$AB'; _pfsm_close_marker_path P920" 2>/dev/null || true)"
  [ -n "$marker" ] || marker="$AB/.aid-o/work/plan-state/P920/plan-closed"
  mkdir -p "$(dirname "$marker")"; : > "$marker"
  run bash "$FSM" plan-close P920 --administrative --reason "the P080 shape: closed, runs left READY"
  [[ "$output" == *"ALREADY CLOSED"* ]]
  [ "$(_st "$SF1" state)" = "ERROR" ]; [ "$(_st "$SF2" state)" = "ERROR" ]
  [ "$(jq 'length' "$MAP")" = "0" ]
}

@test "abandon: a direct run's abandon prints its foreign worktrees from plan.json and copies nothing into the state" {
  _ab_project
  local sf; sf="$(aid_fixture_direct_run "$AB" P910 EXECUTE)"
  jq '.repo_roots = [{name: "docs", path: "/x/docs", worktree: "/x/docs/.aid-worktrees/plan-P910--docs", branch: "plan/P910-p", base: "b"}]' \
    "$(dirname "$sf")/plan.json" > "$(dirname "$sf")/p" && mv "$(dirname "$sf")/p" "$(dirname "$sf")/plan.json"
  run bash "$FSM" epic-complete P910 E-910-1_1 --abandon --reason "the direct run is stopped by the PM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"foreign worktrees to remove by hand: /x/docs/.aid-worktrees/plan-P910--docs"* ]]
  ! grep -q 'worktree' "$sf"
}

@test "abandon: a direct run in DONE with done_phase review is abandoned, and the hook then refuses its branch" {
  _ab_project
  local sf; sf="$(aid_fixture_direct_run "$AB" P910 DONE review)"
  run bash "$AFSM" abandon "$sf" --reason "stopped after its last gate"
  [ "$status" -eq 0 ]
  [ "$(_st "$sf" state)" = "ERROR" ]; [ "$(_st "$sf" abandoned)" = "true" ]
  local wt="$AB/.aid-worktrees/plan-P910"
  echo y > "$wt/late.txt"; git -C "$wt" add late.txt
  run bash -c "cd '$wt' && AID_PROJECT_ROOT='$AB' bash '$PLUGIN_ROOT/defaults/hooks/pre-commit'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run_abandoned"* ]]
}

@test "abandon: a run at done_phase release is finished and refused by abandon (DONE)" {
  _ab_project
  local sf; sf="$(aid_fixture_direct_run "$AB" P910 DONE release)"
  run bash "$AFSM" abandon "$sf" --reason "too late to abandon"
  [ "$status" -eq 1 ]
  [[ "$output" == *"finished"* ]]
  [ "$(_st "$sf" state)" = "DONE" ]
}
