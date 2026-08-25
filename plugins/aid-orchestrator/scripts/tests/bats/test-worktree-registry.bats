#!/usr/bin/env bats
# aid-tier: t0
# test-worktree-registry.bats — a plan's execution worktree is recorded when
# it is made, cleared when the plan finishes, and after a crash the record
# outlives the tree and OFFERS a cleanup that nothing performs (P087 Step 7).
#
# The record is plan-state's `worktree_path` (P074); what this suite pins is
# the reader — the scan and the SessionStart notice — and its one promise:
# no tree is ever deleted by anything here.

bats_require_minimum_version 1.5.0
load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  HOOK="$AID_PLUGIN_PATH/scripts/aid-hook.sh"
  PFSM="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-worktree-registry.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/repo"
  aid_test_mk_repo "$ROOT" .aid-o/work/plan-state
  export AID_PLAN_STATE_PROJECT_ROOT="$ROOT" AID_HOOK_AUDIT="$TMP/audit.jsonl" AID_SESSION_STORE="$TMP/store"
  plan_state_init P901 plan_branch plan/P901 main >/dev/null
  WT="$ROOT/.aid-worktrees/plan-P901"
  git -C "$ROOT" worktree add -q -b plan/P901 "$WT" >/dev/null 2>&1
}
teardown() { rm -rf "$TMP"; }

_event() { jq -n --arg c "$ROOT" '{session_id:"s",cwd:$c,source:"startup"}'; }

@test "registry: AC19 — a recorded live tree scans as live, and a cleared record scans as nothing" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  run aid_worktree_registry_scan "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == P901$'\t'OPEN$'\t'"$WT"$'\t'live$'\t' ]]
  plan_state_set_worktree_path P901 "" >/dev/null
  run aid_worktree_registry_scan "$ROOT"
  [ -z "$output" ]
}

@test "registry: AC20 — after a crash the record outlives the tree, the scan says missing and offers the audited repair" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  rm -rf "$WT"
  run aid_worktree_registry_scan "$ROOT"
  [[ "$output" == P901$'\t'OPEN$'\t'"$WT"$'\t'missing$'\t'*"--recreate-worktree"* ]]
  run aid_hook_rule_worktree_registry <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P901 (OPEN): missing"* && "$output" == *"--recreate-worktree"* ]]
  # the record is still there — the notice changed nothing
  [ "$(plan_state_get P901 worktree_path)" = "$WT" ]
}

@test "registry: a terminal plan whose tree is still on disk is a leftover — plan-close is offered, the tree stays" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  sed -i 's/^plan_state: .*/plan_state: CLOSED/' "$(plan_state_path P901)"
  run aid_worktree_registry_scan "$ROOT"
  [[ "$output" == P901$'\t'CLOSED$'\t'"$WT"$'\t'leftover$'\t'*"plan-close P901"* ]]
  [ -d "$WT" ]
}

@test "registry: AC21 — nothing here deletes a tree: scan and notice leave a missing record, a leftover tree and a live tree exactly as they were" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  printf 'unfinished\n' > "$WT/wip.txt"
  before="$(find "$ROOT/.aid-worktrees" -type f | sort | md5sum)"
  aid_worktree_registry_scan "$ROOT" >/dev/null
  aid_hook_rule_worktree_registry <<< "$(_event)" >/dev/null 2>&1
  bash "$PFSM" worktrees --project-root "$ROOT" >/dev/null 2>&1 || true
  [ "$(find "$ROOT/.aid-worktrees" -type f | sort | md5sum)" = "$before" ]
  [ -f "$WT/wip.txt" ]
  refute_grep -E 'worktree remove|rm -rf' "$AID_PLUGIN_PATH/scripts/lib/aid-worktree-registry.sh"
}

@test "registry: every record live means a silent SessionStart — no notice is injected" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  run --separate-stderr aid_hook_rule_worktree_registry <<< "$(_event)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"0 worktree record(s)"* ]]
}

@test "registry: the CLI form prints the same scan for the controller" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  rm -rf "$WT"
  run bash "$PFSM" worktrees --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"P901"*"missing"* ]]
}

@test "registry: through the real dispatcher the notice arrives on SessionStart as injected context" {
  plan_state_set_worktree_path P901 "$WT" >/dev/null
  rm -rf "$WT"
  run bash "$HOOK" SessionStart <<< "$(_event)"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<< "$output")" == *"P901 (OPEN): missing"* ]]
  grep -q '"rule":"worktree_registry_notice","outcome":"inject"' "$AID_HOOK_AUDIT"
}
