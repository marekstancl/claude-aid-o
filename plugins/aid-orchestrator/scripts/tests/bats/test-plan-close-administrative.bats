#!/usr/bin/env bats
# aid-tier: t0
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
  [[ "$block" == *"closing around those would hide them"* ]]
  [[ "$block" == *'printf '"'"'%s'"'"' "$_adm_bad"'* ]]
  [[ "$block" == *"exit 1"* ]]
}

# --- the guard EXERCISED, not merely grepped ------------------------------
# Codex, 2026-09-02: "the added tests are string-presence checks; they do not
# exercise the guard's actual manifest combinations". These call the classifier
# with real check output instead.

# _classify <check_output> — echoes the findings the guard would REFUSE on.
# Mirrors the loop in cmd_plan_close; kept here as the executable statement of
# what "an absence" means, so a change to either side shows up as a red test.
_classify() {
  local ccout="$1" bad="" line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      *"FAIL"*|*"check"[0-9]*)
        case "$line" in
          *"there is nothing to close against"*|\
          *"the plan-final candidate binding is gone"*|\
          *"does not exist and no valid durable close-evidence"*|\
          *"report never generated"*|\
          *"the lifecycle layer resolves to"*|\
          *"has no Head field"*) ;;
          *) bad+="${line}"$'\n' ;;
        esac ;;
    esac
  done <<< "$ccout"
  printf '%s' "$bad"
}

@test "guard: pure absences are accepted" {
  run _classify "check5: the manifest has no candidate_sha — the plan-final candidate binding is gone, close is blocked
check1: reports/P019-delivery.md does not exist — report never generated (report_storage: committed)"
  [ -z "$output" ]
}

@test "guard: a NEGATIVE result is refused, not closed around" {
  # The case Codex constructed: a frozen candidate, a negative verdict, no
  # plan_final_run_id. The old two-field test let this through.
  run _classify "check5: non-terminal EPIC(s): E-019-2_3 — every EPIC must be terminal before the plan closes"
  [[ "$output" == *"non-terminal EPIC"* ]]
}

@test "guard: something WRONG is refused — corrupt manifest, unparseable queue, unprovable ancestry" {
  run _classify "check5: .aid-o/work/plan-state/P019/manifest.json is not a parseable plan-boundary manifest — close is blocked"
  [ -n "$output" ]
  run _classify "check4: queue.yaml is unparseable — cannot revalidate"
  [ -n "$output" ]
  run _classify "check5: EPIC ancestry is not provable against plan/P019: E-019-1_3"
  [ -n "$output" ]
}

@test "guard: unrecognised text refuses, it does not pass" {
  run _classify "check7: something nobody has classified yet"
  [ -n "$output" ]
}

@test "guard: one absence and one real problem together still refuse" {
  run _classify "check5: the plan-final candidate binding is gone, close is blocked
check3: state=DONE but 2 step(s) still status:pending"
  [[ "$output" == *"still status:pending"* ]]
  [[ "$output" != *"candidate binding is gone"* ]]
}
