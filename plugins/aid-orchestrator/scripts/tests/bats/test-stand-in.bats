#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-stand-in.sh
# P117 (11): in an --auto run the independent stand-in decides a technical decision that is not a review
# finding (a scope widening, a step without a change, a technically failed measurement), and a PROTECTED impact
# goes to the PM whatever the verdict says. Defect it catches: the run stopping on the PM for a technical
# decision (WAN P110-P112, eight stops in two days), or a stand-in waving through a protected change.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; export AID_PLUGIN_PATH AID_TEST_MODE=1
  SI="$AID_PLUGIN_PATH/scripts/aid-stand-in.sh"; EMIT="$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh"
  R="$BATS_TEST_TMPDIR/r"; mkdir -p "$R" && cd "$R"
  git init -q -b main .; git config user.email t@t; git config user.name t
  mkdir -p .aid-o/plans .aid-o/work/plan-state/P950 src; echo a > src/a.py
  printf -- '---\nid: P950\nzadani: .aid-o/plans/P950-zadani.md\n---\n# Plan\n' > .aid-o/plans/P950-x.md
  printf -- '# Zadání\n' > .aid-o/plans/P950-zadani.md
  printf '.aid-o/\n' > .gitignore; git add -A; git commit -qm init
  printf 'plan_id: P950\nautonomy: auto\n' > .aid-o/work/plan-state/P950/plan-state.yaml
  EV="$R/.aid-o/work/evidence/E-950-1_1/R-E950-1"; mkdir -p "$EV"
  printf 'plan_path: %s\n' "$R/.aid-o/plans/P950-x.md" > "$EV/fsm-state.yaml"
  jq -n '{zadani: ".aid-o/plans/P950-zadani.md", steps: [{id: "s1"}, {id: "s2"}]}' > "$EV/plan.json"
  : > "$EV/timeline.jsonl"
  echo '{"available": false, "reason": "codex_absent"}' > "$BATS_TEST_TMPDIR/probe.json"; export AID_CODEX_PROBE_STUB="$BATS_TEST_TMPDIR/probe.json"
}

_prop() { echo "$1" > "$BATS_TEST_TMPDIR/prop.json"; }
_ask() { run bash "$SI" ask --evidence-dir "$EV" --code "${1:-amend_scope_no_brief_point}" --proposal "$BATS_TEST_TMPDIR/prop.json" --tree-root "$R"; }
# _claude <answer> <class> — the stand-in Claude agent answers inside its bracket
_claude() {
  ID="$(grep -oE 'stand-in-[0-9a-f]{16}' <<< "$output" | head -1 | sed 's/^stand-in-//')"; D="$EV/stand-in/$ID"
  bash "$EMIT" start --focus "stand-in-$ID" --agent-id claude:stand-in --evidence-dir "$EV" >/dev/null
  jq -n --arg i "$ID" --arg a "$1" --arg c "$2" '{id: $i, answer: $a, class: $c, reason: "the path serves the step and nothing protected", provider: "claude"}' > "$D/verdict.json"
  bash "$EMIT" complete --focus "stand-in-$ID" --output-file "$D/verdict.json" --evidence-dir "$EV" >/dev/null
}
_record() { run bash "$SI" record --evidence-dir "$EV" --id "$ID" --verdict "$D/verdict.json" --tree-root "$R"; }
_verify() {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-stand-in.sh'; aid_stand_in_verify '$EV' '$D/auth.json' '$1' '$2' '$R' && echo PERMITTED"
}

@test "stand-in: a scope widening in an --auto run — Codex out, a Claude stand-in in its bracket approves, the permission and the ledger line hold" {
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["src/new.py"], "why": "the step needs a helper module"}'
  _ask; echo "$output"; [ "$status" -eq 4 ]; [[ "$output" == *"STAND-IN"*"claude:stand-in"* ]]
  _claude approve technical; _record; echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"approve by claude"* ]]
  [ "$(jq -r '.approved' "$D/auth.json")" = true ]
  [ "$(jq -r '"\(.checkpoint) \(.kind) \(.answer)"' "$R/.aid-o/work/evidence/P950/delegated-disputes.jsonl")" = "stand_in scope_extension approve" ]
  _verify scope_extension '{"step": 1, "paths": ["src/new.py"]}'; [ "$output" = PERMITTED ]
  _verify scope_extension '{"step": 0, "paths": ["src/new.py"]}'; [[ "$output" == *"does not cover this action"* ]]
  _verify scope_extension '{"step": 1, "paths": ["src/other.py"]}'; [[ "$output" == *"does not cover this action"* ]]
  _verify no_change_step '{"step": 1}'; [[ "$output" == *"is for scope_extension"* ]]
  # a permission for two paths does not cover one of them alone (Codex review: no piecemeal reuse)
  jq '.paths = ["src/new.py", "src/second.py"]' "$D/proposal.json" > /dev/null
  # asked again: the same decision, nothing dispatched
  _ask; [ "$status" -eq 0 ]; [[ "$output" == *"already decided"* ]]
  # the approved proposal edited afterwards is no permission
  jq '.paths += [".env"]' "$D/proposal.json" > "$D/p" && mv "$D/p" "$D/proposal.json"
  _verify scope_extension '{"step": 1, "paths": ["src/new.py"]}'; [[ "$output" == *"not the one the stand-in approved"* ]]
}

@test "stand-in: every protected impact goes to the PM before anyone is asked (exit 3), whatever a verdict would say" {
  local p
  for p in '{"kind": "scope_extension", "step": 1, "paths": [".env.local"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": ["deploy/prod.sh"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": ["config/db_credentials.json"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": [".aid-o/config/execution.yaml"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": [".aid-o/plans/P950-zadani.md"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": ["/etc/other-repo/x"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": ["src/../../x"]}' \
           '{"kind": "scope_extension", "step": 1, "paths": ["src/x.py"], "external": ["api.openai.com"]}' \
           '{"kind": "lower_gate", "step": 1}'; do
    _prop "$p"; _ask; echo "$p → $output"; [ "$status" -eq 3 ]; [[ "$output" == *"PROTECTED"*"the PM decides"* ]]
  done
  [ ! -d "$EV/stand-in" ] || [ -z "$(find "$EV/stand-in" -name verdict.json)" ]
  # the project's own protected_paths count too
  mkdir -p .aid-o/config; printf 'protected_paths:\n  - "billing/**"\n' > .aid-o/config/execution.yaml
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["billing/rates.py"]}'; _ask; [ "$status" -eq 3 ]
}

@test "stand-in: a bracket closed over another file vouches for nothing; a permission for [a, b] does not cover a alone; a blocked step is the stand-in's in --auto" {
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["src/new.py", "src/second.py"]}'; _ask; [ "$status" -eq 4 ]
  ID="$(grep -oE 'stand-in-[0-9a-f]{16}' <<< "$output" | head -1 | sed 's/^stand-in-//')"; D="$EV/stand-in/$ID"
  bash "$EMIT" start --focus "stand-in-$ID" --agent-id claude:stand-in --evidence-dir "$EV" >/dev/null
  echo '{"harmless": true}' > "$BATS_TEST_TMPDIR/other.json"
  bash "$EMIT" complete --focus "stand-in-$ID" --output-file "$BATS_TEST_TMPDIR/other.json" --evidence-dir "$EV" >/dev/null
  jq -n --arg i "$ID" '{id: $i, answer: "approve", class: "technical", reason: "x", provider: "claude"}' > "$D/verdict.json"
  _record; [ "$status" -eq 1 ]; [[ "$output" == *"stand_in_verdict_unbound"* ]]
  # the verdict changed after its own bracket closed: refused too
  bash "$EMIT" start --focus "stand-in-$ID" --agent-id claude:stand-in --evidence-dir "$EV" >/dev/null
  bash "$EMIT" complete --focus "stand-in-$ID" --output-file "$D/verdict.json" --evidence-dir "$EV" >/dev/null
  jq '.reason = "edited later"' "$D/verdict.json" > "$D/v" && mv "$D/v" "$D/verdict.json"
  _record; [ "$status" -eq 1 ]; [[ "$output" == *"stand_in_verdict_unbound"* ]]
  _claude approve technical; _record; [ "$status" -eq 0 ]
  _verify scope_extension '{"step": 1, "paths": ["src/new.py"]}'; [[ "$output" == *"does not cover this action"* ]]
  _verify scope_extension '{"step": 1, "paths": ["src/second.py", "src/new.py"]}'; [ "$output" = PERMITTED ]
  _prop '{"kind": "blocked_step", "step": 1, "action": "rename"}'; _ask contract_return_not_done; [ "$status" -eq 3 ]   # its own kind
  printf 'current_step: 1\nstate: EXECUTE\n' >> "$EV/fsm-state.yaml"; mkdir -p "$EV/steps/s2"
  echo '{"step_status": "blocked"}' > "$EV/steps/s2/return.json"
  local rs; rs="$(sha256sum "$EV/steps/s2/return.json" | cut -d' ' -f1)"
  _prop "{\"kind\": \"blocked_step\", \"step\": 1, \"action\": \"redispatch\", \"return_sha256\": \"$rs\", \"why\": \"the agent ran out of context twice\"}"
  _ask contract_return_not_done; [ "$status" -eq 4 ]; _claude approve technical; _record; [ "$status" -eq 0 ]
  # the consumer: the blocked return is set aside, the step goes out again — once per blocked return
  local auth="$D/auth.json"
  run bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" step-redispatch "$EV/fsm-state.yaml" --stand-in "$auth" --reason "the agent ran out of context twice"
  echo "$output"; [ "$status" -eq 0 ]; [ ! -f "$EV/steps/s2/return.json" ]; ls "$EV/steps/s2/"return.blocked-*.json
  echo '{"step_status": "blocked", "note": "again"}' > "$EV/steps/s2/return.json"
  run bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" step-redispatch "$EV/fsm-state.yaml" --stand-in "$auth" --reason "the agent ran out of context twice"
  [ "$status" -ne 0 ]                                                  # a new blocked return: a new decision
  echo '{"step_status": "done", "gates": []}' > "$EV/steps/s2/return.json"
  run bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" step-redispatch "$EV/fsm-state.yaml" --stand-in "$auth" --reason "the agent ran out of context twice"
  [ "$status" -ne 0 ]; [[ "$output" == *"has a done return"* ]]      # a done return is advanced, not dispatched again
  grep -q '"checkpoint":"stand_in_used"' "$R/.aid-o/work/evidence/P950/delegated-disputes.jsonl"
}

@test "docs surface: CHANGELOG, README and docs/ with a documentation extension, and the project's help_paths, are documentation; skills, agents, commands, the plan and docs code are not" {
  run bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-docs-surface.sh'; mkdir -p '$R/.aid-o/config'; printf 'help_paths:\n  - "ui/src/help/**"\n' > '$R/.aid-o/config/execution.yaml'
    for p in CHANGELOG.md README.md plugins/x/README.md docs/a/b.md docs/x.rst ui/src/help/page.md skills/run.md plugins/x/agents/a.md commands/c.md docs/tool.py .aid-o/plans/P1-zadani.md src/app.py README.sh; do
      aid_docs_surface \"\$p\" '$R/.aid-o/config/execution.yaml' && echo \"\$p yes\" || echo \"\$p no\"; done"
  echo "$output"
  [[ "$output" == *"CHANGELOG.md yes"*"README.md yes"*"plugins/x/README.md yes"*"docs/a/b.md yes"*"docs/x.rst yes"*"ui/src/help/page.md yes"* ]]
  [[ "$output" == *"skills/run.md no"*"plugins/x/agents/a.md no"*"commands/c.md no"*"docs/tool.py no"*".aid-o/plans/P1-zadani.md no"*"src/app.py no"*"README.sh no"* ]]
}

@test "stand-in: a verdict classing it protected goes to the PM; a Claude verdict without its bracket, or one that left a file, is refused" {
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["src/new.py"]}'; _ask; [ "$status" -eq 4 ]
  _claude approve brief; _record; [ "$status" -eq 3 ]; [[ "$output" == *"classed it brief"* ]]; [ ! -f "$D/auth.json" ]
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["src/b.py"]}'; _ask; [ "$status" -eq 4 ]
  ID="$(grep -oE 'stand-in-[0-9a-f]{16}' <<< "$output" | head -1 | sed 's/^stand-in-//')"; D="$EV/stand-in/$ID"
  jq -n --arg i "$ID" '{id: $i, answer: "approve", class: "technical", reason: "x", provider: "claude"}' > "$D/verdict.json"
  _record; [ "$status" -eq 1 ]; [[ "$output" == *"stand_in_verdict_unbound"* ]]
  _claude approve technical; echo leftover > "$R/src/stray.txt"
  _record; [ "$status" -eq 1 ]; [[ "$output" == *"delegation_left_files"*"src/stray.txt"* ]]
  rm "$R/src/stray.txt"; _record; [ "$status" -eq 0 ]
}

@test "stand-in: a code that is not the stand-in's, or a run without delegation, is refused; a technically failed measurement only when it really was technical" {
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["src/new.py"]}'
  _ask abandon_needs_reason; [ "$status" -eq 1 ]; [[ "$output" == *"stand_in_not_allowed"* ]]
  printf 'plan_id: P950\nautonomy: manual\n' > .aid-o/work/plan-state/P950/plan-state.yaml
  _ask; [ "$status" -eq 1 ]; [[ "$output" == *"delegation_missing"* ]]
  printf 'plan_id: P950\nautonomy: auto\n' > .aid-o/work/plan-state/P950/plan-state.yaml
  mkdir -p "$EV/cp2/step-1"
  jq -n '{results: [{ac_label: "AC3", verdict: "absent", reason: "timeout", evidence: "neměřeno: limit 120 s"}, {ac_label: "AC4", verdict: "absent", evidence: "exit=1"}]}' > "$EV/cp2/step-1/plan-diff.json"
  _prop '{"kind": "measurement_failed", "step": 1, "criterion": "AC4"}'; _ask step_criteria_failed
  [ "$status" -eq 3 ]; [[ "$output" == *"brief: AC4 was measured"* ]]
  _prop '{"kind": "measurement_failed", "step": 1, "criterion": "AC3"}'; _ask step_criteria_failed; [ "$status" -eq 4 ]
  _claude approve technical; _record; [ "$status" -eq 0 ]
  _verify measurement_failed '{"step": 1, "criterion": "AC3"}'; [ "$output" = PERMITTED ]
  _verify measurement_failed '{"step": 1, "criterion": "AC33"}'; [[ "$output" == *"does not cover"* ]]
}

@test "stand-in: a step the plan says calls an outside service (**External:**) is protected whatever the proposal declares" {
  jq '.steps[1].external = ["api.openai.com"]' "$EV/plan.json" > "$EV/p" && mv "$EV/p" "$EV/plan.json"
  _prop '{"kind": "scope_extension", "step": 1, "paths": ["src/new.py"]}'; _ask; [ "$status" -eq 3 ]; [[ "$output" == *"money"*"api.openai.com"* ]]
  _prop '{"kind": "scope_extension", "step": 0, "paths": ["src/new.py"]}'; _ask; [ "$status" -eq 4 ]
}
