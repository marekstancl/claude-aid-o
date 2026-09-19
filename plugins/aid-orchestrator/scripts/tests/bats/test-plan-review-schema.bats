#!/usr/bin/env bats
# aid-tier: t0
# test-plan-review-schema.bats — the plan reviewer's answer contract.
# A valid answer passes; each broken shape rule is refused with the field named;
# each unproven finding gets its rejection reason; the example answers in
# skills/plan-review-roles.md pass; the prompt template renders through the
# sanctioned renderer.
# Origin: P093 Step 1 (plan review rebuild).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-packet.sh"
  TEST_DIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_DIR"; }

# _proof <finding.json> — the adjudicator's per-finding proof check; prints the
# rejection reason, nothing for a proven finding.
_proof() {
  local r; r="$(jq -r --slurpfile s "$AID_PR_SCHEMA" "$(aid_plan_review_proof_jq) proof_error" "$1")"
  [[ -z "$r" ]] || { echo "$r"; return 1; }
}

# _answer <jq-filter applied to a valid answer> — writes $TEST_DIR/a.json
_answer() {
  jq -n '{role: "reuse", findings: [{id: "reuse-1", step: 3, severity: "major",
          claim: "c", command: "grep -n x scripts/a.sh", evidence: "scripts/a.sh:4; plan.md:10",
          fix: "f"}]}' | jq "$1" > "$TEST_DIR/a.json"
}

@test "answer: a valid answer passes" {
  _answer '.'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "proof: a finding without command is missing_command" {
  _answer '.findings[0] | del(.command)'
  run _proof "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [ "$output" = missing_command ]
}
@test "proof: a finding without evidence is missing_evidence" {
  _answer '.findings[0] | del(.evidence)'
  run _proof "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [ "$output" = missing_evidence ]
}
@test "proof: evidence without a line number is missing_evidence" {
  _answer '.findings[0] | .evidence = "scripts/a.sh"'
  run _proof "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [ "$output" = missing_evidence ]
}
@test "proof: a write command is missing_command; a read-only one passes" {
  _answer '.findings[0] | .command = "sed -i s/a/b/ scripts/a.sh"'
  run _proof "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [ "$output" = missing_command ]
  _answer '.findings[0]'
  run _proof "$TEST_DIR/a.json"
  [ "$status" -eq 0 ]
}
@test "answer: a finding without its claim is refused naming the field" {
  _answer 'del(.findings[0].claim)'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"missing claim"* ]]
}
@test "answer: empty findings without a reason is refused" {
  _answer '.findings = []'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"no_findings_reason"* ]]
}
@test "answer: an unknown role and an unknown severity are refused" {
  _answer '.role = "lens_l1"'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"role must be one of"* ]]
  _answer '.findings[0].severity = "critical"'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"severity"* ]]
}
@test "answer: a fenced answer passes after unfencing" {
  _answer '.'
  { echo '```json'; cat "$TEST_DIR/a.json"; echo '```'; } > "$TEST_DIR/fenced.txt"
  aid_plan_review_unfence "$TEST_DIR/fenced.txt" "$TEST_DIR/b.json"
  run aid_plan_review_answer_error "$TEST_DIR/b.json"
  [ "$status" -eq 0 ]
}
@test "skill: both example answers in plan-review-roles.md pass" {
  awk '/^```json$/{on=1; n++; next} /^```$/{on=0} on{print > (dir "/ex" n ".json")}' \
    dir="$TEST_DIR" "$AID_PLUGIN_PATH/skills/plan-review-roles.md"
  [ -f "$TEST_DIR/ex1.json" ] && [ -f "$TEST_DIR/ex2.json" ]
  run aid_plan_review_answer_error "$TEST_DIR/ex1.json"; [ "$status" -eq 0 ]
  run aid_plan_review_answer_error "$TEST_DIR/ex2.json"; [ "$status" -eq 0 ]
}
@test "skill: six role sections, each with Questions and a Stop rule" {
  local s="$AID_PLUGIN_PATH/skills/plan-review-roles.md"
  [ "$(grep -c '^## Role: ' "$s")" -eq 6 ]
  [ "$(grep -c '^### Questions$' "$s")" -eq 6 ]
  [ "$(grep -c '^### Stop rule$' "$s")" -eq 6 ]
  # the role ids are exactly the schema's enum
  diff <(grep '^## Role: ' "$s" | sed 's/^## Role: //' | sort) \
       <(jq -r '.["$defs"].roles_cp1.enum[]' "$AID_PR_SCHEMA" | sort)
}
@test "template: renders from three string variables with nothing left unresolved" {
  jq -n '{role_section: "## Role: reuse", round: "1", output_path: "/tmp/x.json"}' > "$TEST_DIR/vars.json"
  run bash "$AID_PLUGIN_PATH/scripts/lib/aid-render-prompt.sh" \
    --template "$AID_PLUGIN_PATH/defaults/prompts/plan-review-prompt-v1.md" \
    --vars-json "$TEST_DIR/vars.json" --output "$TEST_DIR/prompt.md"
  [ "$status" -eq 0 ]
  ! grep -q '{{' "$TEST_DIR/prompt.md"
  grep -q '^# Plan review, round 1$' "$TEST_DIR/prompt.md"
}
@test "adapter: every role's focus and the agent id pass the dispatch wrapper's allowlists" {
  local emit="$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" role focus
  grep -q 'aid-emit-dispatch.sh" start --focus <focus>' "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-adapter-claude.md"
  for role in $(jq -r '.["$defs"].roles_cp1.enum[]' "$AID_PR_SCHEMA"); do
    focus="cp1-${role//_/-}"
    bash "$emit" start --focus "$focus" --agent-id aid-orchestrator:plan-review --evidence-dir "$TEST_DIR"
    echo '{}' > "$TEST_DIR/reviewer-$role.json"
    bash "$emit" complete --focus "$focus" --output-file "$TEST_DIR/reviewer-$role.json" --evidence-dir "$TEST_DIR"
  done
  [ ! -s "$TEST_DIR/pending-dispatches.jsonl" ]
}
@test "adapter: commands/aid-plan.md quotes the claude adapter instruction byte for byte" {
  local cmd="$AID_PLUGIN_PATH/commands/aid-plan.md"
  diff <(awk '/^<!-- adapter:end -->$/{on=0} on{print} /^<!-- adapter:begin -->$/{on=1}' "$cmd") \
       "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-adapter-claude.md"
}
@test "command: the CP1 section names every round subcommand inside a fenced block" {
  local sec
  sec="$(awk '/^## Plan review \(CP1\)$/{on=1} on && /^## / && !/Plan review/{exit} on' "$AID_PLUGIN_PATH/commands/aid-plan.md" \
         | awk '/^ *```/{f=!f; next} f')"
  for sub in prepare dispatch collect close fix-check finalize dispute retry override; do
    grep -qE "aid-plan-review-round.sh\"? ${sub} |\"\\\$R\" ${sub} " <<< "$sec" || { echo "missing: $sub"; return 1; }
  done
}
@test "answer: a whitespace-only claim is refused" {
  _answer '.findings[0].claim = "   "'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]
}
