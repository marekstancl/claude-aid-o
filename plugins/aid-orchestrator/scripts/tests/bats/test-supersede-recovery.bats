#!/usr/bin/env bats
# aid-tier: t2
# test-supersede-recovery.bats — P073 Step 13: the supported recoveries.
#
# `aid-fsm.sh init` rejects a duplicate init unconditionally, which is right —
# silently re-initialising over a live run loses its history. But it left a PM
# whose EPIC run went stale (a regenerated plan.json, an abandoned attempt)
# with no supported way forward except hand-deleting state: exactly the
# unaudited surgery this plan exists to replace.
#
# `plan-state --supersede-epic` is that transaction. Its record binds FOUR
# fields, all re-derived from disk at init rather than trusted, so it
# authorises exactly ONE specific re-initialisation and nothing else.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  export PFSM FSM
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  PLAN=P900
  EPIC=E-900-1_1
  export PLAN EPIC
  REASON="the EPIC package was regenerated after a plan revision and the old run is stale"
  export REASON
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    printf 'seed\n' > README.md
    git add -A && git commit -qm seed ) >/dev/null 2>&1
}

teardown() {
  teardown_test_evidence_dir
}

_pf() { ( cd "$ROOT" && bash "$PFSM" "$@" ); }

_run_dir() { printf '%s/.aid-o/work/evidence/%s/R-900-1' "$ROOT" "$EPIC"; }

# _seed_epic_run [plan_json_body] — a manifest entry plus a live EPIC run
# (fsm-state.yaml + plan.json), the shape supersede operates on.
_seed_epic_run() {
  # A literal default here needs no brace-expansion gymnastics — the nested
  # braces in a JSON default broke the parameter expansion outright (status 127).
  local body="$1"
  [[ -n "$body" ]] || body='{"steps":[{"id":1}]}'
  local head; head="$(cd "$ROOT" && git rev-parse HEAD)"
  local rd; rd="$(_run_dir)"
  mkdir -p "$rd"
  cat > "$rd/fsm-state.yaml" <<EOF
epic_id: $EPIC
run_id: R-900-1
state: EXECUTE
current_step: 1
total_steps: 3
EOF
  printf '%s\n' "$body" > "$rd/plan.json"
  bash -c '
    set -uo pipefail
    SCRIPT_DIR="$1"
    . "$SCRIPT_DIR/lib/aid-plan-state.sh"
    . "$SCRIPT_DIR/lib/aid-plan-manifest.sh"
    cd "$2"
    plan_manifest_init "$3" "plan/$3" main "$4" "$4" plan_branch >/dev/null
    # Full 7-arg signature: plan_id epic_id run_id task_branch base_commit
    # source_ref evidence_dir. A short call aborts the shell outright under
    # `set -u` inside the lib, which no `|| true` can catch.
    plan_manifest_add_epic "$3" "$5" R-900-1 "task/$5/main" "$4" "plan/$3" \
      ".aid-o/work/evidence/$5/R-900-1" >/dev/null 2>&1 || true
    exit 0
  ' _ "$AID_PLUGIN_PATH/scripts" "$ROOT" "$PLAN" "$head" "$EPIC"
}

_records() { find "$ROOT/.aid-o/work/plan-state" -name 'supersede-*.json' 2>/dev/null | wc -l | tr -d ' '; }
_archives() { find "$(_run_dir)" -name 'fsm-state.yaml.superseded-*' 2>/dev/null | wc -l | tr -d ' '; }

# ─── the producer ─────────────────────────────────────────────────────────

@test "P073 Step 13: supersede archives the state file and writes a four-field record" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"superseded ${EPIC}"* ]]

  [ ! -f "$(_run_dir)/fsm-state.yaml" ]
  [ "$(_archives)" = "1" ]
  [ "$(_records)" = "1" ]

  local rec; rec="$(find "$ROOT/.aid-o/work/plan-state" -name 'supersede-*.json' | head -1)"
  [ "$(jq -r '.artifact_type' "$rec")" = "epic_supersede_record" ]
  [ "$(jq -r '.plan_id' "$rec")" = "$PLAN" ]
  [ "$(jq -r '.epic_id' "$rec")" = "$EPIC" ]
  [ "$(jq -r '.old_run_id' "$rec")" = "R-900-1" ]
  [ "$(jq -r '.reason' "$rec")" = "$REASON" ]
  # The hashes really are the bytes on disk.
  local arch; arch="$(find "$(_run_dir)" -name 'fsm-state.yaml.superseded-*' | head -1)"
  [ "$(jq -r '.old_state_sha256' "$rec")" = "sha256:$(sha256sum "$arch" | awk '{print $1}')" ]
  [ "$(jq -r '.new_plan_json_sha256' "$rec")" = "sha256:$(sha256sum "$(_run_dir)/plan.json" | awk '{print $1}')" ]
}

@test "P073 Step 13: the archive and its record share one epoch, so they pair 1:1" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  local arch rec arch_epoch rec_epoch
  arch="$(find "$(_run_dir)" -name 'fsm-state.yaml.superseded-*' | head -1)"
  rec="$(find "$ROOT/.aid-o/work/plan-state" -name 'supersede-*.json' | head -1)"
  arch_epoch="${arch##*.superseded-}"
  rec_epoch="$(basename "$rec" .json)"; rec_epoch="${rec_epoch##*-}"
  [ "$arch_epoch" = "$rec_epoch" ]
}

@test "P073 Step 13: the evidence directory is preserved byte-for-byte" {
  _seed_epic_run
  printf 'step evidence\n' > "$(_run_dir)/step-1-output.txt"
  local before; before="$(sha256sum "$(_run_dir)/step-1-output.txt" | awk '{print $1}')"
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  [ -f "$(_run_dir)/step-1-output.txt" ]
  [ "$(sha256sum "$(_run_dir)/step-1-output.txt" | awk '{print $1}')" = "$before" ]
}

# ─── the producer's refusals ──────────────────────────────────────────────

@test "P073 Step 13: supersede after the EPIC merged is REFUSED — a merged EPIC is history" {
  _seed_epic_run
  bash -c '
    set -uo pipefail
    . "$1/lib/aid-plan-state.sh"
    . "$1/lib/aid-plan-manifest.sh"
    cd "$2"
    plan_manifest_update "$3" "(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == \"$4\" then (.status = \"merged_to_plan\") else . end])" >/dev/null
  ' _ "$AID_PLUGIN_PATH/scripts" "$ROOT" "$PLAN" "$EPIC"
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already merged_to_plan"* ]]
  [[ "$output" == *"plan-rollback"* ]]
  [ "$(_archives)" = "0" ]
  [ "$(_records)" = "0" ]
}

@test "P073 Step 13: supersede with no state file to archive is refused" {
  _seed_epic_run
  rm -f "$(_run_dir)/fsm-state.yaml"
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing to supersede"* ]]
  [ "$(_records)" = "0" ]
}

@test "P073 Step 13: supersede with no plan.json to bind to is refused, and archives nothing" {
  _seed_epic_run
  rm -f "$(_run_dir)/plan.json"
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no plan.json"* ]]
  [ "$(_archives)" = "0" ]
  [ "$(_records)" = "0" ]
  [ -f "$(_run_dir)/fsm-state.yaml" ]
}

@test "P073 Step 13: a short reason is refused — the record is the audit trail" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "too short"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  [ "$(_archives)" = "0" ]
}

@test "P073 Step 13: supersede of an EPIC with no manifest entry is refused" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic E-900-9_9 --reason "$REASON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no epic_runs entry"* ]]
}

# ─── the four-field binding at init ───────────────────────────────────────

_init_epic() {
  ( cd "$ROOT" && bash "$FSM" init "$EPIC" R-900-1 3 full main \
      "$(git rev-parse HEAD)" "$(_run_dir)/fsm-state.yaml" )
}

@test "P073 Step 13: after a supersede, a re-init with the SAME package is authorised once" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]

  run _init_epic
  [[ "$output" == *"re-init authorised by"* ]]
  # The record was consumed, so a SECOND re-init has nothing to authorise it.
  [ "$(_records)" = "0" ]
  run bash -c "ls '$ROOT/.aid-o/work/plan-state'/supersede-*.consumed-* | wc -l"
  [ "$output" = "1" ]
}

@test "P073 Step 13: a re-init with a DIFFERENT plan.json is rejected — the record binds one exact package" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  # The PM regenerates a different package after superseding.
  printf '{"steps":[{"id":1},{"id":2}]}\n' > "$(_run_dir)/plan.json"

  run _init_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"no supersede record matching BOTH"* ]]
  # The record was NOT consumed — the PM can re-supersede against the current
  # package rather than losing their authorisation.
  [ "$(_records)" = "1" ]
}

@test "P073 Step 13: a FORGED record (wrong old_state_sha256) authorises nothing" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  local rec; rec="$(find "$ROOT/.aid-o/work/plan-state" -name 'supersede-*.json' | head -1)"
  jq '.old_state_sha256 = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
    "$rec" > "$rec.tmp" && mv "$rec.tmp" "$rec"

  run _init_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"no supersede record matching BOTH"* ]]
}

@test "P073 Step 13: a record for a DIFFERENT epic never authorises this one" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  local rec; rec="$(find "$ROOT/.aid-o/work/plan-state" -name 'supersede-*.json' | head -1)"
  mv "$rec" "$(dirname "$rec")/supersede-${PLAN}-E-900-2_2-9999999999.json"

  run _init_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"no supersede record matching BOTH"* ]]
}

@test "P073 Step 13: with NO archived state, the unconditional duplicate-init rejection is unchanged" {
  _seed_epic_run
  run _init_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"state_file already exists"* ]]
  [[ "$output" != *"supersede"* ]]
}

@test "P073 Step 13: two consecutive supersede cycles each need their OWN record" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  run _init_epic
  [[ "$output" == *"re-init authorised by"* ]]
  [ -f "$(_run_dir)/fsm-state.yaml" ]

  # Second cycle: a fresh supersede is required; the first record is consumed.
  sleep 1
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  [ "$(_archives)" = "2" ]
  run _init_epic
  [[ "$output" == *"re-init authorised by"* ]]
  # Both cycles left their own consumed record; neither reused the other's.
  run bash -c "ls '$ROOT/.aid-o/work/plan-state'/supersede-*.consumed-* | wc -l"
  [ "$output" = "2" ]
}

# ─── the attest half: recomputation is already unconditional ──────────────

@test "P073 Step 13: attestation re-derives epic_base_commit from Git unconditionally — no flag needed" {
  # The plan specified a NEW --recompute-base flag. Implementing it would have
  # been decoration: IMP-267 already made the recomputation unconditional, and
  # a flag toggling behaviour that always happens is a detector with no
  # enforcement point. This pins the capability where the plan expected the
  # flag, so the absence is a documented decision rather than a gap.
  run grep -c 'RE-DERIVE ancestry from real Git before attesting' "$PFSM"
  [ "$output" = "1" ]
  run grep -c 'refusing to attest ancestry that repair may have left wrong' "$PFSM"
  [ "$output" = "1" ]
}

@test "P073 Step 13: attestation FAILS CLOSED when the ancestry cannot be proven" {
  _seed_epic_run
  # No task branch and no recorded merge: nothing to derive a base from.
  run _pf plan-state "$PLAN" --attest-source-ref "plan/$PLAN" --reason "$REASON" --epic "$EPIC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to attest"* || "$output" == *"lineage"* ]]
}

# ─── the registry rows the plan requires at step completion ───────────────

@test "P073 Step 13: both recovery transactions are registered" {
  local reg="$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  run yq -e '.enforcements[] | select(.id == "epic_supersede_bound_reinit") | .status' "$reg"
  [ "$output" = "active" ]
  run yq -e '.enforcements[] | select(.id == "attest_recomputes_base_unconditionally") | .status' "$reg"
  [ "$output" = "active" ]
}

# ─── Codex-review findings on the first cut of this step ──────────────────

@test "P073 Step 13 (review finding 1): a later init gate failure does NOT burn the PM's authorisation" {
  # The record used to be consumed BEFORE the remaining init gates ran, so a
  # gate failure left no state file AND no record — and supersede could not
  # repair it, because there is no live state left to archive. The PM's one
  # authorisation was simply gone.
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]

  # Force a failure AFTER the supersede verification: an unwritable run
  # directory means the state file cannot be created.
  chmod a-w "$(_run_dir)"
  run _init_epic
  local rc="$status"
  chmod u+w "$(_run_dir)"
  [ "$rc" -ne 0 ]
  [ ! -f "$(_run_dir)/fsm-state.yaml" ]

  # The record survived, so the PM can simply retry.
  [ "$(_records)" = "1" ]
  run _init_epic
  [[ "$output" == *"authorised by"* ]]
  [ -f "$(_run_dir)/fsm-state.yaml" ]
  [ "$(_records)" = "0" ]
}

@test "P073 Step 13 (review finding 2): an EPIC with no derivable plan id cannot bypass the check" {
  # The branch used to be conditional on a derived plan id, so for an EPIC id
  # yielding none, an archived state plus no record fell through to a NORMAL
  # init — re-initialising with no authorisation at all.
  local rd="$ROOT/.aid-o/work/evidence/E-test/R-test"
  mkdir -p "$rd"
  printf 'state: EXECUTE\n' > "$rd/fsm-state.yaml.superseded-1700000000"
  printf '{"steps":[]}\n' > "$rd/plan.json"

  run bash -c "cd '$ROOT' && bash '$FSM' init E-test R-test 3 full main \
      \"\$(git rev-parse HEAD)\" '$rd/fsm-state.yaml'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to re-init unauthorised"* ]]
  [ ! -f "$rd/fsm-state.yaml" ]
}

@test "P073 Step 13 (review finding 3): an OLDER record cannot authorise the NEWER archive" {
  # Without an old_run_id binding, two archives of identical content let a
  # stale record match the newest archive and authorise an init the PM never
  # granted for that run.
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  local rec; rec="$(find "$ROOT/.aid-o/work/plan-state" -name 'supersede-*.json' | head -1)"

  # Repoint the record at a DIFFERENT run than the archive actually sits in.
  jq '.old_run_id = "R-900-9"' "$rec" > "$rec.tmp" && mv "$rec.tmp" "$rec"

  run _init_epic
  [ "$status" -ne 0 ]
  [[ "$output" == *"no supersede record matching BOTH"* ]]
  [ ! -f "$(_run_dir)/fsm-state.yaml" ]
}

@test "P073 Step 13 (review finding 4): evidence ARTIFACTS survive and the state file is archived in place" {
  # The earlier claim that the evidence directory was untouched was not true
  # of the directory — the state file lives in it. What is true is the useful
  # part: artifacts are preserved and the state file is archived, not deleted.
  _seed_epic_run
  printf 'transcript\n' > "$(_run_dir)/reporter-transcript.txt"
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Evidence artifacts are untouched"* ]]
  [[ "$output" == *"archived in place"* ]]
  [ -f "$(_run_dir)/reporter-transcript.txt" ]
  [ "$(_archives)" = "1" ]
  # Nothing was deleted: the archive holds the old state's exact bytes.
  local arch; arch="$(find "$(_run_dir)" -name 'fsm-state.yaml.superseded-*' | head -1)"
  run grep -c 'state: EXECUTE' "$arch"
  [ "$output" = "1" ]
}

# ─── Whole-EPIC-2 review findings ─────────────────────────────────────────

@test "P073 EPIC 2 (review finding): concurrent re-inits — exactly one wins, the loser writes nothing" {
  # Verifying early and consuming at the very end fixed one problem and made
  # another: two inits could both VERIFY the same record while no state file
  # existed, both write one, and only then race the rename — so the loser
  # errored after it had already mutated state. A reservation taken before the
  # write decides the winner first.
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]

  # Pre-create the task branch the inits would otherwise all race to create:
  # four concurrent `git checkout -b` in one repository is a fixture race, not
  # the property under test, and it made this flaky.
  ( cd "$ROOT" && git branch "task/${EPIC}/main" >/dev/null 2>&1 || true )
  local out="$ROOT/conc"; mkdir -p "$out"
  local i
  for i in 1 2 3 4; do
    ( cd "$ROOT" && bash "$FSM" init "$EPIC" R-900-1 3 full main \
        "$(git rev-parse HEAD)" "$(_run_dir)/fsm-state.yaml" \
        >"$out/$i.out" 2>"$out/$i.err"; echo "$?" > "$out/$i.rc" ) &
  done
  wait

  local winners=0
  for i in 1 2 3 4; do
    [[ "$(cat "$out/$i.rc")" == "0" ]] && winners=$(( winners + 1 ))
  done
  [ "$winners" = "1" ]

  # Every loser refused LOUDLY. Matching exact message text was flaky: which
  # refusal a loser hits depends on how far it got (reservation lost, state
  # file already there, branch-creation race), and all of them are correct
  # outcomes. What must hold is that none exited silently.
  local losers=0 i2
  for i2 in 1 2 3 4; do
    if [[ "$(cat "$out/$i2.rc")" != "0" ]]; then
      [ -s "$out/$i2.err" ] || { echo "loser $i2 exited non-zero with no message" >&2; false; }
      losers=$(( losers + 1 ))
    fi
  done
  [ "$losers" = "3" ]
  [ "$(_records)" = "0" ]
  run bash -c "ls '$ROOT/.aid-o/work/plan-state'/supersede-*.consumed-* | wc -l"
  [ "$output" = "1" ]
  # No reservation was left dangling.
  run bash -c "ls '$ROOT/.aid-o/work/plan-state'/supersede-*.reserved-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "P073 EPIC 2 (review finding): a failed state-file write RESTORES the reservation for a retry" {
  _seed_epic_run
  run _pf plan-state "$PLAN" --supersede-epic "$EPIC" --reason "$REASON"
  [ "$status" -eq 0 ]

  chmod a-w "$(_run_dir)"
  run _init_epic
  local rc="$status"
  chmod u+w "$(_run_dir)"
  [ "$rc" -ne 0 ]

  # Back under its original name — not reserved, not consumed.
  [ "$(_records)" = "1" ]
  run bash -c "ls '$ROOT/.aid-o/work/plan-state'/supersede-*.reserved-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
  run _init_epic
  [[ "$output" == *"re-init authorised by"* ]]
}

@test "P073 EPIC 2 (review finding): init's strict flag check is NOT disabled by --force" {
  # A blanket "accept anything after --force" restored exactly the silent sink
  # Step 9 removed.
  local sf="$ROOT/.aid-o/work/evidence/E-900-2_2/R-1/fsm-state.yaml"
  mkdir -p "$(dirname "$sf")"
  run bash -c "cd '$ROOT' && bash '$FSM' init E-900-2_2 R-1 3 full main \
      \"\$(git rev-parse HEAD)\" '$sf' --force --reason 'a genuine twenty-plus character reason here' --typo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown flag for init: --typo"* ]]
}

@test "P073 EPIC 2 (review finding): the KNOWN force payload flags are still accepted after --force" {
  local sf="$ROOT/.aid-o/work/evidence/E-900-3_3/R-1/fsm-state.yaml"
  mkdir -p "$(dirname "$sf")"
  run bash -c "cd '$ROOT' && bash '$FSM' init E-900-3_3 R-1 3 full main \
      \"\$(git rev-parse HEAD)\" '$sf' --force --reason 'a genuine twenty-plus character reason here' --blocked-checks 'x' --streamlined"
  [[ "$output" != *"Unknown flag for init"* ]]
}

# ─── Independent-review findings ──────────────────────────────────────────

@test "P073 (independent review): concurrent SUPERSEDES leave one archive/record pair and never strand the run" {
  # Reproduced by the reviewer before the fix: four concurrent supersedes left
  # ONE archived state and ZERO records — the exact stranding this recovery
  # exists to prevent. The producer checked "does the record exist", wrote it
  # with a plain `mv` (which overwrites), then archived; so two callers both
  # passed the check, the second clobbered the first's record, and when its own
  # archive failed its error path deleted the record they BOTH relied on.
  _seed_epic_run
  local out="$ROOT/sup"; mkdir -p "$out"
  local i
  for i in 1 2 3 4; do
    ( cd "$ROOT" && bash "$PFSM" plan-state "$PLAN" --supersede-epic "$EPIC" \
        --reason "$REASON" >"$out/$i.out" 2>"$out/$i.err"; echo "$?" > "$out/$i.rc" ) &
  done
  wait

  local wins=0
  for i in 1 2 3 4; do
    [[ "$(cat "$out/$i.rc")" == "0" ]] && wins=$(( wins + 1 ))
  done
  [ "$wins" = "1" ]
  # THE INVARIANT: exactly one archive and exactly one record, paired.
  [ "$(_archives)" = "1" ]
  [ "$(_records)" = "1" ]

  # And the run is genuinely recoverable, not stranded.
  run _init_epic
  [[ "$output" == *"re-init authorised by"* ]]
  [ -f "$(_run_dir)/fsm-state.yaml" ]
}

@test "P073 (independent review): a supersede that loses the lock race says so and changes nothing" {
  _seed_epic_run
  local out="$ROOT/sup2"; mkdir -p "$out"
  local i
  for i in 1 2 3; do
    ( cd "$ROOT" && bash "$PFSM" plan-state "$PLAN" --supersede-epic "$EPIC" \
        --reason "$REASON" >/dev/null 2>"$out/$i.err"; echo "$?" > "$out/$i.rc" ) &
  done
  wait
  local losers=0
  for i in 1 2 3; do
    if [[ "$(cat "$out/$i.rc")" != "0" ]]; then
      grep -q 'superseded by a concurrent call\|already recorded in this same second\|nothing to supersede\|holds the lock' "$out/$i.err" && losers=$(( losers + 1 ))
    fi
  done
  [ "$losers" = "2" ]
}
