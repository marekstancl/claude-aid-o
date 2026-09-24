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
  [ -n "$(git -C "$R" branch --list 'step/s9')" ]
  jq -e '(.removed | length) >= 3' "$R/.aid-o/work/evidence/P900/cleanup.json"
  jq -e '.kept[] | select(.path | endswith("generation-P900")) | .why == "uncommitted work"' "$R/.aid-o/work/evidence/P900/cleanup.json"
  [[ "$output" == *"kept: $R/.aid-worktrees/generation-P900 — uncommitted work"* ]]
}
