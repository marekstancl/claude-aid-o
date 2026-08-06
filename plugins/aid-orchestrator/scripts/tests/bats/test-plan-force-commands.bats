#!/usr/bin/env bats
# test-plan-force-commands.bats — P073 Step 8: --force wired into the public
# plan-lifecycle commands.
#
# The PM decision was UNIVERSALITY OF THE FLAG with a BOUNDED scope of what it
# can bypass. So this suite asserts two separate things:
#   1. every one of the eight state-TRANSITION commands PARSES --force and its
#      reason flag — none of them rejects it as an unknown flag, which is the
#      P082 stranding this step exists to end;
#   2. where a precondition is routed through the forceable classifier, a
#      forced run gets past it and mints exactly one audited receipt, while an
#      unforced run still refuses.
#
# CLI GRAMMAR NOTE. `--force-reason` works on ALL eight commands and is never
# ambiguous. `--reason` is accepted as a synonym only where the command has no
# business `--reason` of its own. The plan named plan-rollback as the single
# collision; epic-complete is a SECOND one (its --reason belongs to
# --abandon/--supersede-by/--full-tests), found while wiring. Both therefore
# take --force-reason only.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  export PFSM
  ROOT="$TEST_PROJECT_ROOT"
  export ROOT
  ( cd "$ROOT"
    git init -q
    git config user.email t@e.com
    git config user.name T
    git checkout -q -b main 2>/dev/null || git branch -m main
    printf 'seed\n' > README.md
    git add -A && git commit -qm seed )
  REASON="the lifecycle manifest was corrupted by an interrupted merge and must be finished"
  export REASON
}

teardown() {
  teardown_test_evidence_dir
}

_pf() { ( cd "$ROOT" && bash "$PFSM" "$@" ); }

# SCOPE NOTE. plan-start's LATER lifecycle write (aid_lifecycle_set_plan_mode)
# needs project identity this bare fixture does not provide, so a plan-start
# here ends non-zero for a reason that has nothing to do with force. That is
# fine and is asserted around rather than papered over: what this step must
# prove is that the FORCE path behaved — the precondition printed its own
# recovery, the bypass was taken and named, and exactly one audited receipt
# exists (or none, when nothing was bypassed). The end-to-end forced-close
# story belongs to Step 19's integration fixture.

# _dirty — make the worktree dirty in a way the clean-worktree check sees
# (a tracked file, since the check runs with --untracked-files=no).
# P074 Step 5 NOTE: plan-start/epic-start no longer run that check at all —
# where a test below needs a REFUSING forceable precondition on plan-start it
# uses the KEPT committed_source_plan preflight (_uncommitted_plan) instead,
# preserving what each test verifies (refusal, receipt shape, audit records).
_dirty() { printf 'uncommitted\n' >> "$ROOT/README.md"; }

# _uncommitted_plan — a TRACKED but uncommitted source plan: the kept,
# forceable committed_source_plan preflight refuses it (P073 Step 11), which
# is the re-anchor for the force-path tests after P074 Step 5 removed the
# plan-start/epic-start clean-worktree preflight.
_uncommitted_plan() {
  mkdir -p "$ROOT/docs"
  printf '# Plan\n' > "$ROOT/docs/plan.md"
  ( cd "$ROOT" && git add docs/plan.md )
}

# _seed_lifecycle — the plan source + git-tracked lifecycle manifest
# plan-start's own lifecycle write needs; with it seeded, plan-start and
# epic-start complete rc=0 in this fixture (the SCOPE NOTE seam above), so
# the P074 headline assertions can demand full success.
_seed_lifecycle() {
  mkdir -p "$ROOT/.aid-o/plans"
  printf '# P900\n\n**EPIC 1: the delivered one**\n' > "$ROOT/.aid-o/plans/P900-lifecycle.md"
  ( source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
    aid_lifecycle_ensure_manifest P900 "$ROOT" >/dev/null )
}

_receipts() { find "$ROOT/.aid-o" -name 'waiver-plan-*.json' 2>/dev/null | wc -l | tr -d ' '; }

# ─── 1. universality: every command PARSES the flag ───────────────────────
# A command that rejects --force with "unknown flag" is the stranding this
# step ends. These assert the flag is understood — not that the command then
# succeeds, which depends on its own state.

@test "P073 Step 8: all eight lifecycle commands accept --force (none rejects it as an unknown flag)" {
  local cmd
  for cmd in plan-start epic-start epic-complete epic-merge-to-plan \
             plan-finalize plan-merge-to-main plan-close plan-rollback; do
    run _pf "$cmd" P900 --force --force-reason "$REASON"
    [[ "$output" != *"unknown flag: --force"* ]] || {
      echo "command '$cmd' rejected --force" >&2
      false
    }
    [[ "$output" != *"unknown flag: --force-reason"* ]] || {
      echo "command '$cmd' rejected --force-reason" >&2
      false
    }
  done
}

@test "P073 Step 8: --reason is a force synonym only where the command owns no business --reason" {
  local cmd
  for cmd in plan-start epic-start epic-merge-to-plan plan-finalize \
             plan-merge-to-main plan-close; do
    run _pf "$cmd" P900 --force --reason "$REASON"
    [[ "$output" != *"unknown flag: --reason"* ]]
  done
}

@test "P073 Step 8: epic-complete and plan-rollback keep --reason for their own meaning" {
  # Their business --reason must still be accepted, and must NOT be silently
  # repurposed as the force reason.
  run _pf epic-complete P900 E-900-1_1 --abandon --reason "abandoned for a documented business reason"
  [[ "$output" != *"unknown flag: --reason"* ]]
  run _pf plan-rollback P900 --reason "rolled back for a documented business reason"
  [[ "$output" != *"unknown flag: --reason"* ]]
}

# ─── 2. the forceable path: refuse without --force, pass with it ──────────

@test "P073 Step 8 / P074 Step 5: plan-start ignores a dirty worktree, but a kept forceable precondition still REFUSES without --force" {
  _dirty
  _uncommitted_plan
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md"
  [ "$status" -ne 0 ]
  # The refusal is the KEPT committed-source preflight, never the removed
  # dirty-tree one.
  [[ "$output" != *"uncommitted changes present"* ]]
  [[ "$output" == *"source plan is not committed"* ]]
  [ "$(_receipts)" = "0" ]
}

@test "P073 Step 8 / P074 Step 5: plan-start PASSES the kept committed-source refusal under --force and mints exactly one receipt" {
  _uncommitted_plan
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md" --force --force-reason "$REASON"
  # The check still printed its own recovery first — the normal path is never
  # hidden behind the force.
  [[ "$output" == *"source plan is not committed"* ]]
  [[ "$output" == *"FORCE: bypassing precondition 'committed_source_plan'"* ]]
  [[ "$output" == *"FORCE: recorded at"* ]]
  [ "$(_receipts)" = "1" ]
}

@test "P073 Step 8 / P074 Step 5: the forced plan-start receipt names the command and the bypass" {
  _uncommitted_plan
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md" --force --force-reason "$REASON"
  local w; w="$(find "$ROOT/.aid-o" -name 'waiver-plan-plan-start-*.json' | head -1)"
  [ -n "$w" ]
  [ "$(jq -r '.forced_override' "$w")" = "true" ]
  [ "$(jq -r '.bypassed_preconditions | join(",")' "$w")" = "committed_source_plan" ]
  [ "$(jq -r '.waiver.waived_check' "$w")" = "plan-fsm:plan-start" ]
  [ "$(jq -r '.waiver.reason' "$w")" = "$REASON" ]
}

@test "P073 Step 8: --force without a reason dies naming the requirement, and changes nothing" {
  _dirty
  run _pf plan-start P900 --mode legacy_epic_release_mode --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  [ "$(_receipts)" = "0" ]
  # No plan branch was created by the refused command.
  run bash -c "cd '$ROOT' && git branch --list 'plan/P900'"
  [ -z "$output" ]
}

@test "P073 Step 8: a reason under 20 characters is refused exactly like aid-fsm.sh" {
  _dirty
  run _pf plan-start P900 --mode legacy_epic_release_mode --force --force-reason "too short"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 20 characters"* ]]
  [ "$(_receipts)" = "0" ]
}

@test "P073 Step 8: --force on a command whose preconditions all pass writes NO receipt" {
  # A no-op flag must not litter waivers_applied[] with a receipt for nothing.
  run _pf plan-start P900 --mode legacy_epic_release_mode --force --force-reason "$REASON"
  [[ "$output" == *"bypassed nothing"* ]]
  [ "$(_receipts)" = "0" ]
}

@test "P073 Step 8 / P074 Step 5: a forced run mints exactly ONE receipt even though the handler is called after each precondition group" {
  # BOTH seams at once: the committed-source group is bypassed (one receipt),
  # and the dirty tree — a non-event since P074 — must not add a second one.
  _uncommitted_plan
  _dirty
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md" --force --force-reason "$REASON"
  [ "$(_receipts)" = "1" ]
}

# ─── epic-start ───────────────────────────────────────────────────────────

@test "P074 Step 5: epic-start SUCCEEDS on a dirty worktree without --force, and a --force there bypasses nothing" {
  _seed_lifecycle
  run _pf plan-start P900 --mode legacy_epic_release_mode
  [ "$status" -eq 0 ]
  _dirty

  # The P074 headline behavior: the removed preflight no longer refuses, and
  # nothing else in epic-start minds the unrelated tracked edit.
  run _pf epic-start P900 E-900-1_1
  [ "$status" -eq 0 ]
  [[ "$output" != *"uncommitted changes present"* ]]
  [ "$(_receipts)" = "0" ]

  # With nothing left to bypass, a forced epic-start says so and mints
  # NO receipt — the no-op-flag contract, same as plan-start's.
  run _pf epic-start P900 E-900-2_1 --force --force-reason "$REASON"
  [[ "$output" == *"bypassed nothing"* ]]
  [ "$(_receipts)" = "0" ]
}

# ─── the audit trail is complete for every forced run ─────────────────────

@test "P073 Step 8 / P074 Step 5: every forced run appends to the cross-plan audit log" {
  _uncommitted_plan
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md" --force --force-reason "$REASON"
  [ -s "$ROOT/.aid-o/work/audit-log.jsonl" ]
  run grep -c 'plan_force_override' "$ROOT/.aid-o/work/audit-log.jsonl"
  [ "$output" -ge 1 ]
}

@test "P073 Step 8: an unforced successful run writes no force records at all" {
  run _pf plan-start P900 --mode legacy_epic_release_mode
  [ "$(_receipts)" = "0" ]
  if [[ -f "$ROOT/.aid-o/work/audit-log.jsonl" ]]; then
    run grep -c 'plan_force_override' "$ROOT/.aid-o/work/audit-log.jsonl"
    [ "$output" = "0" ]
  fi
}

# ─── Codex-review findings on the first cut of this step ──────────────────

@test "P073 Step 8 (review finding 1): --force on a command with no routed precondition SAYS SO instead of pretending" {
  # The flag is universal by PM decision, but on these three commands nothing
  # is wired to the forceable classifier yet. An operator must never believe
  # they forced something that was never forceable.
  local cmd
  for cmd in epic-complete plan-close plan-rollback; do
    run _pf "$cmd" P900 --force --force-reason "$REASON"
    [[ "$output" == *"will bypass NOTHING and write no receipt"* ]] || {
      echo "command '$cmd' forced silently" >&2
      false
    }
  done
  [ "$(_receipts)" = "0" ]
}

@test "P073 Step 8 (review finding 1): --force requires a reason on EVERY command, routed or not" {
  local cmd
  for cmd in plan-start epic-start epic-complete epic-merge-to-plan \
             plan-finalize plan-merge-to-main plan-close plan-rollback; do
    run _pf "$cmd" P900 --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a reason of at least 20 characters"* ]] || {
      echo "command '$cmd' accepted --force with no reason" >&2
      false
    }
  done
}

@test "P073 Step 8 (review finding 2): a force reason WITHOUT --force is an error, not a silently discarded argument" {
  # Previously --reason/--force-reason parsed fine on their own and were
  # ignored, so the invocation looked accepted while forcing nothing.
  local cmd
  for cmd in plan-start epic-start epic-merge-to-plan plan-finalize \
             plan-merge-to-main plan-close; do
    run _pf "$cmd" P900 --reason "$REASON"
    [ "$status" -ne 0 ]
    [[ "$output" == *"force reason was supplied without --force"* ]] || {
      echo "command '$cmd' silently ignored a lone --reason" >&2
      false
    }
  done
}

@test "P073 Step 8 (review finding 2): --force-reason alone is refused on the commands that own --reason too" {
  local cmd
  for cmd in epic-complete plan-rollback; do
    run _pf "$cmd" P900 --force-reason "$REASON"
    [ "$status" -ne 0 ]
    [[ "$output" == *"force reason was supplied without --force"* ]]
  done
}

@test "P073 Step 8 (review finding 2): the business --reason on epic-complete and plan-rollback is untouched by the guard" {
  # Their own --reason must not trip the force guard.
  run _pf epic-complete P900 E-900-1_1 --abandon --reason "abandoned for a documented business reason"
  [[ "$output" != *"force reason was supplied without --force"* ]]
  run _pf plan-rollback P900 --reason "rolled back for a documented business reason"
  [[ "$output" != *"force reason was supplied without --force"* ]]
}

@test "P073 Step 8 (review finding 3): the receipt states it records a BYPASS, never that the command completed" {
  # A receipt minted before a later, unrouted precondition fails must not read
  # as "this operation happened". (P074 Step 5: re-anchored from the removed
  # dirty-tree preflight to the kept committed-source one.)
  _uncommitted_plan
  run _pf plan-start P900 --mode legacy_epic_release_mode --plan-file "$ROOT/docs/plan.md" --force --force-reason "$REASON"
  local w; w="$(find "$ROOT/.aid-o" -name 'waiver-plan-plan-start-*.json' | head -1)"
  [ -n "$w" ]
  [ "$(jq -r '.records' "$w")" = "precondition_bypass" ]
  [ "$(jq -r '.status' "$w")" = "blocked" ]
  [ "$(jq -r '.verdict.ready' "$w")" = "false" ]
}
