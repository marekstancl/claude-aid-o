#!/usr/bin/env bats
# aid-tier: t0
# test-continuity-capsule.bats — surviving a compaction (P086 Step 5).
#
# THE GROUNDED FAILURE MODE: after a compaction a session's own bearings —
# which plan, which run, which tree, and what it owes the PM — are gone, and
# are found again by hand.
#
# THE CLAIM THESE TESTS DO NOT MAKE: that the model uses what is injected.
# SessionStart injection is degree 3 on the ecosystem scale — a delivery, not a
# guarantee — and in Codex an unapproved hook is skipped in silence, so it may
# not even be delivered. Nothing here is evidence that the contract is in force;
# the gate that inserts it on the normal path stays the mechanism, and this is
# cover for the runs that did not pass through it.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TMP="$(mktemp -d)"
  export AID_SESSION_STORE="$TMP/state-store"
  ROOT="$TMP/project"
  mkdir -p "$ROOT/.aid-o/work/plan-state/P900" "$ROOT/.aid-o/work/evidence/E-900-1_1/R-E900-1"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    printf '.aid-o/\n.aid-worktrees/\n' > .gitignore
    printf 'seed\n' > README.md
    git add -A && git commit -q -m seed
  )
  cat > "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml" <<'Y'
plan_id: P900
plan_state: EPIC_INTEGRATION
mode: plan_branch
worktree_path: /somewhere/.aid-worktrees/plan-P900
Y
  cat > "$ROOT/.aid-o/work/evidence/E-900-1_1/R-E900-1/fsm-state.yaml" <<'Y'
epic_id: E-900-1_1
run_id: R-E900-1
state: EXECUTE
current_step: 2
total_steps: 5
Y
  cat > "$ROOT/.aid-o/work/active-runs.json" <<Y
{"E-900-1_1": {"state_file": "$ROOT/.aid-o/work/evidence/E-900-1_1/R-E900-1/fsm-state.yaml",
  "run_id": "R-E900-1", "state": "EXECUTE", "plan_id": "P900"}}
Y
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && chmod -R u+rwX "$TMP" 2>/dev/null
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

capsule() { printf '%s' "$AID_SESSION_STORE/continuity/$1.json"; }

# The rule runs without AID_PROJECT_ROOT — a hook gets its bearings from the
# event's cwd, and leaving the override set would never exercise that.
rule() { # rule <function> <event_json>
  run env -u AID_PROJECT_ROOT bash -c \
    "printf '%s' '$2' | bash -c 'source \"$PLUGIN_ROOT/scripts/lib/aid-continuity-capsule.sh\"; $1'"
}

@test "AC14: the capsule carries the contract, the state and the next allowed step" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 0 ]
  local f; f="$(capsule s1)"
  [ -f "$f" ]
  [[ "$(jq -r .contract "$f")" == *"skills/communication.md"* ]]
  [ "$(jq -r '.plans[0].plan_id' "$f")" = "P900" ]
  [ "$(jq -r '.plans[0].plan_state' "$f")" = "EPIC_INTEGRATION" ]
  [ "$(jq -r '.runs[0].state' "$f")" = "EXECUTE" ]
  # Asked of the FSM, not re-derived here — a second transition table in a hook
  # is a second authority.
  [ "$(jq -r '.runs[0].allowed_transitions | index("GATES")' "$f")" != "null" ]
}

@test "a closed plan is not carried into the next session as if it were open" {
  sed -i 's/plan_state: EPIC_INTEGRATION/plan_state: CLOSED/' "$ROOT/.aid-o/work/plan-state/P900/plan-state.yaml"
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  [ "$(jq -r '.plans | length' "$(capsule s1)")" = "0" ]
}

@test "AC15: the capsule names the working copy the session was in, not just the state root" {
  git -C "$ROOT" worktree add -q "$TMP/wt" -b plan/P900 main
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$TMP/wt\"}"
  [ "$status" -eq 0 ]
  local f; f="$(capsule s1)"
  [ "$(cd "$(jq -r .invoke_root "$f")" && pwd -P)" = "$(cd "$TMP/wt" && pwd -P)" ]
  [ "$(cd "$(jq -r .state_root "$f")" && pwd -P)" = "$(cd "$ROOT" && pwd -P)" ]
  # And the state it read is the primary checkout's, from inside the worktree.
  [ "$(jq -r '.plans[0].plan_id' "$f")" = "P900" ]
}

@test "AC17: the capsule lies outside every working tree" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  [ -f "$(capsule s1)" ]
  [[ "$(capsule s1)" != "$ROOT"* ]]
  # Nothing of the capsule's landed in the tree — not under .aid-o/ either,
  # which is a working tree even though it is gitignored.
  run find "$ROOT" -name 's1.json'
  [ -z "$output" ]
  run git -C "$ROOT" status --porcelain
  [ -z "$output" ]
}

@test "AC16: a session store that cannot be written does not hold up the compaction" {
  mkdir -p "$AID_SESSION_STORE"
  chmod 500 "$AID_SESSION_STORE"
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  # 3 is "not applicable"; 2 would be a refusal, and a refusal here would block
  # a compaction because a snapshot failed.
  [ "$status" -eq 3 ]
  [[ "$output" == *"not held up"* ]]
}

@test "a cwd outside any workspace captures nothing and refuses nothing" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$TMP\"}"
  [ "$status" -eq 3 ]
}

@test "the capsule is restored on a continuation, with its age visible" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  rule aid_hook_rule_continuity_restore '{"session_id":"s1","source":"compact"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"AID continuity"* ]]
  [[ "$output" == *"minute(s) ago"* ]]
  [[ "$output" == *"P900 — EPIC_INTEGRATION"* ]]
  [[ "$output" == *"next allowed: EXECUTE/GATES/ESCALATION/ERROR"* ]]
  [[ "$output" == *"snapshot, not the current state"* ]]
}

@test "an old capsule is restored with its age stated, not silently" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  local f; f="$(capsule s1)"
  jq '.written_at = "2020-01-01T00:00:00Z"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  rule aid_hook_rule_continuity_restore '{"session_id":"s1","source":"resume"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"2020-01-01T00:00:00Z"* ]]
  [[ "$output" != *"unknown minute"* ]]
}

@test "a fresh start restores nothing" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  rule aid_hook_rule_continuity_restore '{"session_id":"s1","source":"startup"}'
  [ "$status" -eq 3 ]
  [[ "$output" == *"not a continuation"* ]]
}

@test "a continuation with no capsule of its own says so instead of borrowing one" {
  rule aid_hook_rule_continuity_capture "{\"session_id\":\"s1\",\"cwd\":\"$ROOT\"}"
  rule aid_hook_rule_continuity_restore '{"session_id":"s2","source":"fork"}'
  [ "$status" -eq 3 ]
  [[ "$output" == *"no capsule for session s2"* ]]
}

@test "an event with no session id captures nothing — the capsule is per session" {
  rule aid_hook_rule_continuity_capture "{\"cwd\":\"$ROOT\"}"
  [ "$status" -eq 3 ]
  [[ "$output" == *"per session"* ]]
}
