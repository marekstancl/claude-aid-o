#!/usr/bin/env bats
# aid-tier: t0
# test-hook-rules-turn.bats — a turn does not end on a half-done step, and a
# write outside the step's paths is named before it lands (P087 Step 5).
#
# Fixtures only: a state root with one run in EXECUTE, a contract for its
# current step, a transcript with a first timestamp. The handlers are called
# directly and through the real dispatcher (so the registry rows are proved
# to name them). Nothing here proves a harness calls the hook — the canary
# does that.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  HOOK="$AID_PLUGIN_PATH/scripts/aid-hook.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-hook-rules-turn.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/repo"
  mkdir -p "$ROOT/.aid-o/work/evidence/E-1/R-1/steps/step_1_backend"
  (cd "$ROOT" && git init -q -b main 2>/dev/null || git init -q; git -C "$ROOT" config user.email t@t; git -C "$ROOT" config user.name T; : > "$ROOT/README.md"; git -C "$ROOT" add -A; git -C "$ROOT" commit -q -m seed)
  EV="$ROOT/.aid-o/work/evidence/E-1/R-1"
  printf 'epic_id: E-1\nrun_id: R-1\nstate: EXECUTE\ncurrent_step: 0\ntotal_steps: 1\n' > "$EV/fsm-state.yaml"
  printf '{"steps":[{"id":"step_1_backend","role":"backend","objective":"x","outputs":[],"allowed_paths":["src/","docs/readme.md"]}],"dependencies":[]}' > "$EV/plan.json"
  printf '{"version":"abc","step_id":"step_1_backend","allowed_paths":["src/","docs/readme.md"],"evidence_dir":"%s/steps/step_1_backend"}' "$EV" > "$EV/steps/step_1_backend/contract.json"
  # a transcript whose session started an hour ago — the contract is newer
  TRANSCRIPT="$TMP/transcript.jsonl"
  printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n' "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" > "$TRANSCRIPT"
  export AID_HOOK_AUDIT="$TMP/audit.jsonl" AID_SESSION_STORE="$TMP/store"
}
teardown() { rm -rf "$TMP"; }

_say() { printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"text","text":%s}]}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(jq -Rs . <<< "$1")" >> "$TRANSCRIPT"; }
_stop_event() { jq -n --arg c "$ROOT" --arg t "$TRANSCRIPT" '{session_id:"s",cwd:$c,transcript_path:$t,stop_hook_active:false}'; }
_write_event() { jq -n --arg c "$ROOT" --arg p "$1" --arg tool "${2:-Write}" '{session_id:"s",cwd:$c,tool_name:$tool,tool_input:{file_path:$p}}'; }

# ── rule 1: the turn does not end on an open step ───────────────────────────
@test "turn: AC13 — a Stop with a dispatched, un-advanced step is refused, naming the step and the transition to make" {
  _say "done for now"
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"step 0 (step_1_backend) of E-1/R-1"* ]]
  [[ "$output" == *"increment-step"* && "$output" == *"Decision card or a Blocked card"* ]]
}

@test "turn: a step that was advanced past is not open — the Stop passes" {
  sed -i 's/^current_step: 0/current_step: 1/' "$EV/fsm-state.yaml"
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 0 ]
}

@test "turn: a run that left EXECUTE (escalation, paused) does not hold the turn" {
  sed -i 's/^state: EXECUTE/state: ESCALATION/' "$EV/fsm-state.yaml"
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 0 ]
}

@test "turn: an explicit hand-over — a Blocked card or a Decision card as the last message — is honoured" {
  _say $'Zastaveno: the merge conflicts.\nDopad: nothing merged.\nDoporučené řešení: retry.'
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 3 ]
  [[ "$output" == *"hands over explicitly"* ]]
  _say $'I need your decision: which base?\nWhy now: it blocks.\nRecommendation: A — rebase.\nBecause: cheaper.\nAlternatives: B — merge.\nRisk / what is unverified: none.'
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 3 ]
}

@test "turn: another session's open step is not this turn's — the window is the transcript's start" {
  touch -d '-2 hours' "$EV/steps/step_1_backend/contract.json"
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 0 ]
}

@test "turn: AC15 — an unreadable state does not block: no transcript, no workspace, or a malformed state file" {
  run aid_hook_rule_turn_step_open <<< "$(jq -n --arg c "$ROOT" '{cwd:$c}')"
  [ "$status" -eq 3 ]
  run aid_hook_rule_turn_step_open <<< "$(jq -n --arg c "$TMP" --arg t "$TRANSCRIPT" '{cwd:$c,transcript_path:$t}')"
  [ "$status" -eq 3 ]
  printf 'garbage\n' > "$EV/fsm-state.yaml"
  run aid_hook_rule_turn_step_open <<< "$(_stop_event)"
  [ "$status" -eq 0 ]
}

@test "turn: through the real dispatcher the Stop rule refuses only with a canary verdict, and never on stop_hook_active" {
  _say "bye"
  mkdir -p "$TMP/store/hooks"
  run bash "$HOOK" Stop <<< "$(_stop_event)"
  [ "$status" -eq 0 ]
  grep -q '"rule":"turn_step_open","outcome":"deny_suppressed"' "$AID_HOOK_AUDIT"
  printf '{"verified":true,"tool":"bats","version":"fixture","checked_at":"%s"}' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP/store/hooks/trust.json"
  run bash "$HOOK" Stop <<< "$(_stop_event)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"step_1_backend"* ]]
  run bash "$HOOK" Stop <<< "$(_stop_event | jq '.stop_hook_active = true')"
  [ "$status" -eq 0 ]
}

# ── rule 2: a write outside the step's paths is named ───────────────────────
@test "turn: AC14 — a Write outside the open step's allowed paths is named, with the path and the list, and is not blocked" {
  run aid_hook_rule_turn_write_scope <<< "$(_write_event "$ROOT/lib/other.sh")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OUTSIDE"* && "$output" == *"lib/other.sh"* && "$output" == *"src/, docs/readme.md"* ]]
}

@test "turn: a write inside the allowed paths, or into the step's own evidence, says nothing" {
  run aid_hook_rule_turn_write_scope <<< "$(_write_event "$ROOT/src/a.ts")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run aid_hook_rule_turn_write_scope <<< "$(_write_event "docs/readme.md" Edit)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run aid_hook_rule_turn_write_scope <<< "$(_write_event "$EV/steps/step_1_backend/output.md")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "turn: a tool that is not a file write, or a step without a contract, is not applicable" {
  run aid_hook_rule_turn_write_scope <<< "$(_write_event "$ROOT/lib/other.sh" Bash)"
  [ "$status" -eq 3 ]
  rm "$EV/steps/step_1_backend/contract.json"
  run aid_hook_rule_turn_write_scope <<< "$(_write_event "$ROOT/lib/other.sh")"
  [ "$status" -eq 3 ]
}

@test "turn: through the real dispatcher the write notice arrives as injected context under PreToolUse" {
  run bash "$HOOK" PreToolUse <<< "$(_write_event "$ROOT/lib/other.sh")"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<< "$output")" = "PreToolUse" ]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<< "$output")" == *"lib/other.sh"* ]]
  grep -q '"rule":"turn_write_scope","outcome":"inject"' "$AID_HOOK_AUDIT"
}
