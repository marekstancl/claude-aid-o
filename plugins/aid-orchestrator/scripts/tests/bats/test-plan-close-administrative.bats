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

@test "evidence: a curator report, a release decision or a delivery gate each refuse" {
  local root="$BATS_TEST_TMPDIR/each" f
  for f in curator-report.json release-decision.json delivery-gate.json; do
    rm -rf "$root"; mkdir -p "$root/.aid-o/work/evidence/P019/R-1"
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
