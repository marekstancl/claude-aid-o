#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/lib/aid-hook-rules-turn.sh
# The two transcript readers every AID Stop runs. Defects they catch: reading a long session's whole
# transcript on every Stop (186 MB in WAN on 25. 10. 2026: 13 s per turn end), and a faster reader that
# answers differently — another last message, or a background call missed or invented.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH
  source "$AID_PLUGIN_PATH/scripts/lib/aid-auto-continuation.sh"
  source "$AID_PLUGIN_PATH/scripts/lib/aid-hook-rules-turn.sh"
  T="$BATS_TEST_TMPDIR/t.jsonl"; : > "$T"
}
_say()  { jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >> "$T"; }
_tool() { jq -nc --arg id "$1" --argjson bg "${2:-false}" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:"x",run_in_background:$bg}}]}}' >> "$T"; }
_note() { printf '{"type":"user","message":{"content":"<task-notification><tool-use-id>%s</tool-use-id></task-notification>"}}\n' "$1" >> "$T"; }

@test "the last message is the last assistant entry's text, read from the end" {
  _say "první"; _say "AID-WAIT: brána"; printf '{"type":"user","message":{"content":"ok"}}\n' >> "$T"
  run _aid_hrt_last_message "$T"
  [ "$status" -eq 0 ]; [ "$output" = "AID-WAIT: brána" ]
}

@test "a last assistant entry without text gives an empty message, not an older one" {
  _say "starší text"; _tool toolu_1
  run _aid_hrt_last_message "$T"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "a corrupt line after the last assistant entry is a failure; one before it no longer blinds the rule" {
  _say "konec"; printf '{"type":"assist\n' >> "$T"
  run _aid_hrt_last_message "$T"
  [ "$status" -ne 0 ]
  : > "$T"; printf '{"type":"assist\n' >> "$T"; _say "konec"
  run _aid_hrt_last_message "$T"
  [ "$status" -eq 0 ]; [ "$output" = "konec" ]
}

@test "a background call nobody answered is pending; an answered one is not; spaced JSON is still read" {
  _tool toolu_a true
  run _aid_qc_bg_pending "$T"; [ "$status" -eq 0 ]
  _note toolu_a
  run _aid_qc_bg_pending "$T"; [ "$status" -ne 0 ]
  printf '{"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "toolu_b", "name": "Bash", "input": {"run_in_background": true}}]}}\n' >> "$T"
  run _aid_qc_bg_pending "$T"; [ "$status" -eq 0 ]
}

@test "an Agent launched in the background without the flag is pending until its hand-back" {
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"toolu_g",name:"Agent",input:{prompt:"p"}}]}}' >> "$T"
  jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"toolu_g",content:[{type:"text",text:"Async agent launched successfully."}]}]}}' >> "$T"
  run _aid_qc_bg_pending "$T"; [ "$status" -eq 0 ]
  _note toolu_g
  run _aid_qc_bg_pending "$T"; [ "$status" -ne 0 ]
}

@test "any spacing and tabs in the JSON are read the same (the pre-filter is a superset)" {
  printf '{"type" :  "assistant", "message":{"content":[{"type":"tool_use","id":"toolu_s","name" :\t"Bash","input":{"run_in_background" :\t  true}}]}}\n' >> "$T"
  run _aid_qc_bg_pending "$T"; [ "$status" -eq 0 ]
  : > "$T"
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_t","name":  "Agent","input":{}}]}}\n' >> "$T"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_t","content":"Async agent launched successfully."}]}}\n' >> "$T"
  run _aid_qc_bg_pending "$T"; [ "$status" -eq 0 ]
}

@test "a corrupt line between a launch and its notification is skipped, the lines after it still count" {
  _tool toolu_c true; printf '{"type":"user","mess\n' >> "$T"; _note toolu_c
  run _aid_qc_bg_pending "$T"; [ "$status" -ne 0 ]
  printf '{"type":"assistant","bro\n' >> "$T"; _tool toolu_d true
  run _aid_qc_bg_pending "$T"; [ "$status" -eq 0 ]
}

@test "a long transcript under pipefail: the last message comes back with status 0 (tac's broken pipe is no failure)" {
  for i in $(seq 1 3000); do printf '{"type":"assistant","message":{"content":[{"type":"text","text":"turn %s %s"}]}}\n' "$i" "$(head -c 2000 /dev/zero | tr '\0' x)"; done >> "$T"
  _say "AID-WAIT: konec"
  run bash -c 'set -euo pipefail; source "$AID_PLUGIN_PATH/scripts/lib/aid-hook-rules-turn.sh"; last="$(_aid_hrt_last_message "$1")"; echo "rc=$? [$last]"' _ "$T"
  [ "$status" -eq 0 ]; [ "$output" = "rc=0 [AID-WAIT: konec]" ]
}
