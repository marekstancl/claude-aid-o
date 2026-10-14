#!/usr/bin/env bats
# aid-tier: t1
# test-auto-continuation.bats — P099 Step 5; renamed by P114 (3.0.0), when the
# queue and the SessionStart reminder built on it left with the EPIC path.
#
# Stop keeps the session that drives an autonomous plan working: it refuses a
# turn that ends with work left, up to a budget the PM's reply resets, and lets
# it end on a card, on a declared wait for a live background job, or at the
# budget — the last two cases with one "agent is waiting" message.

load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  HOOK="$AID_PLUGIN_PATH/scripts/aid-hook.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-auto-continuation.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/repo"
  aid_test_mk_repo "$ROOT" "$ROOT/.aid-o/work/plan-state"
  git -C "$ROOT" branch plan/P090 main
  export AID_HOOK_AUDIT="$TMP/audit.jsonl" AID_SESSION_STORE="$TMP/store"
}
teardown() { rm -rf "$TMP"; }

# _plan <plan_id> [autonomy] [plan_state] — the file plan-start writes.
_plan() {
  mkdir -p "$ROOT/.aid-o/work/plan-state/$1"
  printf 'plan_id: %s\nplan_state: %s\nmode: plan_branch\nplan_branch: plan/%s\ntarget_branch: main\nautonomy: %s\n' \
    "$1" "${3:-OPEN}" "$1" "${2:-auto}" > "$ROOT/.aid-o/work/plan-state/$1/plan-state.yaml"
}

# _bind <plan> <session> — the plan-state record `/aid-run --auto` leaves.
_bind() { printf 'auto_session: %s\n' "$2" >> "$ROOT/.aid-o/work/plan-state/$1/plan-state.yaml"; }
# _turn <last message> — a transcript whose last assistant message is that text.
_turn() {
  jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$TMP/t.jsonl"
  printf '%s' "$TMP/t.jsonl"
}
# _stop <session> <last message> [stop_hook_active] — a Stop event.
_stop() {
  jq -n --arg c "$ROOT" --arg s "$1" --arg t "$(_turn "$2")" --argjson a "${3:-false}" \
    '{session_id:$s,cwd:$c,transcript_path:$t,stop_hook_active:$a}'
}
_sink() {
  printf 'send_alert() { echo "$3" >> "%s/sent"; }\n' "$TMP" > "$TMP/tg.sh"
  export AID_TELEGRAM_LIB="$TMP/tg.sh"
}
_sent() { grep -c "${1:-agent-waiting}" "$TMP/sent" 2>/dev/null || echo 0; }

@test "auto-continue: the bound session is refused while work is left, a second time too, and another session never" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "Krok 2 hotový, pokračuji.")"
  [ "$status" -eq 2 ]
  [[ "$output" == *"outcome=refused plan=P090"* ]]
  [[ "$output" == *"continuation 1 of 40"* ]]
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "Pokračuji." true)"
  [ "$status" -eq 2 ]; [[ "$output" == *"continuation 2 of 40"* ]]
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop T9 "Hotovo.")"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=not_auto"* ]]
  [ "$(_sent)" -eq 0 ]
}

@test "auto-continue: a Blocked card ends the turn with one waiting message; the PM's reply re-arms it and resets the count" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "Pokračuji.")" 2>/dev/null || true
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 $'Zastaveno: brána padá\nDůvod: x')"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=handed_over"* ]]
  aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 $'Zastaveno: brána padá')" 2>/dev/null || true
  [ "$(_sent)" -eq 1 ]
  run aid_hook_rule_pm_reply_marker <<< "$(jq -n --arg c "$ROOT" '{session_id:"S1",cwd:$c}')"
  [[ "$output" == *"1 plan(s) re-armed"* ]]
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "Pokračuji.")"
  [[ "$output" == *"continuation 1 of 40"* ]]
  aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 $'Zastaveno: znovu')" 2>/dev/null || true
  [ "$(_sent)" -eq 2 ]
}

@test "auto-continue: AID-WAIT ends the turn uncounted only while an AID background job is live" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  local jd="$ROOT/.aid-o/work/evidence/E-090-1_2/R-1/jobs/j1"; mkdir -p "$jd"
  sleep 30 & local pid=$!
  jq -n --argjson p "$pid" --arg st "$(awk '{print $22}' /proc/$pid/stat)" '{pid:$p, proc_starttime:$st}' > "$jd/job.json"
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 $'Brány běží.\nAID-WAIT: bats_all')"
  kill "$pid"; wait "$pid" 2>/dev/null || true
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=wait"* ]]
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 $'AID-WAIT: bats_all')"
  [ "$status" -eq 2 ]; [[ "$output" == *"continuation 1 of 40"* ]]
}

@test "auto-continue: AID-WAIT ends the turn while a background agent it launched has not reported, and not after" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  local t="$TMP/bg.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_A",name:"Agent",input:{run_in_background:true}}]}}' > "$t"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"AID-WAIT: CP2 reviewer"}]}}' >> "$t"
  local ev; ev="$(jq -n --arg c "$ROOT" --arg t "$t" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  run aid_hook_rule_auto_continuation_stop <<< "$ev"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=wait"* ]]
  jq -nc '{type:"user",message:{content:"<task-notification>\n<task-id>a1</task-id>\n<tool-use-id>toolu_A</tool-use-id>\n<status>completed</status>\n</task-notification>"}}' >> "$t"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"AID-WAIT: CP2 reviewer"}]}}' >> "$t"
  run aid_hook_rule_auto_continuation_stop <<< "$ev"
  [ "$status" -eq 2 ]; [[ "$output" == *"outcome=refused"* ]]
}

@test "auto-continue: an Agent launched in the background WITHOUT the run_in_background flag counts as a live wait; a foreground Agent does not (P103)" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  local t="$TMP/bg2.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_B",name:"Agent",input:{prompt:"x"}}]}}' > "$t"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_B",content:[{type:"text",text:"Async agent launched successfully. The agent is working in the background."}]}]}}' >> "$t"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"AID-WAIT: CP3 reviewer"}]}}' >> "$t"
  local ev; ev="$(jq -n --arg c "$ROOT" --arg t "$t" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  run aid_hook_rule_auto_continuation_stop <<< "$ev"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=wait"* ]]
  # a foreground Agent: its result is the agent's output, nothing is pending
  local f="$TMP/fg.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_C",name:"Agent",input:{prompt:"x"}}]}}' > "$f"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_C",content:"the review found nothing"}]}}' >> "$f"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"AID-WAIT: CP3 reviewer"}]}}' >> "$f"
  run aid_hook_rule_auto_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$f" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  [ "$status" -eq 2 ]
  # another tool's output that merely QUOTES the phrase is not a background agent
  local q="$TMP/quote.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_D",name:"Bash",input:{command:"cat log"}}]}}' > "$q"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_D",content:"Async agent launched successfully (quoted from a log)"}]}}' >> "$q"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"AID-WAIT: CP3 reviewer"}]}}' >> "$q"
  run aid_hook_rule_auto_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$q" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  [ "$status" -eq 2 ]
}

@test "auto-continue: the rule never refuses without knowing: an unparsable transcript or plan-state, or another plan's live job" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  printf 'not json\n' > "$TMP/bad.jsonl"
  run aid_hook_rule_auto_continuation_stop <<< "$(jq -n --arg c "$ROOT" --arg t "$TMP/bad.jsonl" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  [ "$status" -eq 3 ]; [[ "$output" == *"transcript does not parse"* ]]
  # another plan's live job does not excuse this plan's AID-WAIT
  local jd="$ROOT/.aid-o/work/evidence/E-091-1_2/R-1/jobs/j1"; mkdir -p "$jd"
  sleep 30 & local pid=$!
  jq -n --argjson p "$pid" --arg st "$(awk '{print $22}' /proc/$pid/stat)" '{pid:$p, proc_starttime:$st}' > "$jd/job.json"
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 $'AID-WAIT: bats_all')"
  kill "$pid"; wait "$pid" 2>/dev/null || true
  [ "$status" -eq 2 ]
  printf 'plan_id: [broken\nautonomy: auto\nplan_state: EPIC_INTEGRATION\nauto_session: S1\n' > "$ROOT/.aid-o/work/plan-state/P090/plan-state.yaml"
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "x")"
  [ "$status" -eq 3 ]; [[ "$output" == *"does not parse"* ]]
}

@test "auto-continue: at the budget the turn ends with one waiting message; budget 0 disables the refusal" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  mkdir -p "$ROOT/.aid-o/config"; printf 'autonomy:\n  continuation_budget: 1\n' > "$ROOT/.aid-o/config/orchestration.yaml"
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "x")"; [ "$status" -eq 2 ]
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "x")"
  [ "$status" -eq 3 ]; [[ "$output" == *"outcome=budget_spent"* ]]
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "x")"; [ "$status" -eq 3 ]
  [ "$(_sent)" -eq 1 ]
  printf 'autonomy:\n  continuation_budget: 0\n' > "$ROOT/.aid-o/config/orchestration.yaml"
  rm -rf "$AID_SESSION_STORE/continuation"
  run aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "x")"; [ "$status" -eq 3 ]
}

@test "auto-continue: two workspaces with the same plan id keep separate counters" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  local other="$TMP/other"; aid_test_mk_repo "$other" "$other/.aid-o/work/plan-state"; ROOT="$other" _plan P090 auto EPIC_INTEGRATION
  printf 'auto_session: S1\n' >> "$other/.aid-o/work/plan-state/P090/plan-state.yaml"
  aid_hook_rule_auto_continuation_stop <<< "$(_stop S1 "x")" 2>/dev/null || true
  run aid_hook_rule_auto_continuation_stop <<< "$(jq -n --arg c "$other" --arg t "$(_turn x)" '{session_id:"S1",cwd:$c,transcript_path:$t}')"
  [[ "$output" == *"continuation 1 of 40"* ]]
}

@test "auto-continue: through the real dispatcher the refusal holds under stop_hook_active, and neither event writes into the tree" {
  _plan P090 auto EPIC_INTEGRATION; _bind P090 S1; _sink
  mkdir -p "$TMP/store/hooks"
  printf '{"verified":true,"tool":"bats","version":"fixture","checked_at":"%s"}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TMP/store/hooks/trust.json"
  local before; before="$(find "$ROOT/.aid-o" -type f -exec sha256sum {} + | sort)"
  run bash "$HOOK" Stop <<< "$(_stop S1 "x" true)"
  [ "$status" -eq 2 ]; [[ "$output" == *"Continue the /aid-run --auto procedure"* ]]
  grep -q '"rule":"queue_continuation_notice","outcome":"deny","reason":"outcome=refused plan=P090' "$AID_HOOK_AUDIT"
  # The PM's prompt is audited too, and neither event writes into the tree.
  run bash "$HOOK" UserPromptSubmit <<< "$(jq -n --arg c "$ROOT" '{session_id:"S1",cwd:$c,prompt:"ok"}')"
  [ "$status" -eq 0 ]
  grep -q '"event":"UserPromptSubmit","session_id":"S1".*"rule":"pm_reply_marker"' "$AID_HOOK_AUDIT"
  [ "$(find "$ROOT/.aid-o" -type f -exec sha256sum {} + | sort)" = "$before" ]
}

@test "auto-continue: the registry row refuses (degree 2, closed) and bounds its own loop" {
  run yq -r '.rules[] | select(.id == "queue_continuation_notice") | "\(.event) \(.degree) \(.failure) \(.blocks_when_active)"' "$AID_PLUGIN_PATH/defaults/hook-registry.yaml"
  [ "$output" = "Stop 2 closed true" ]
}

