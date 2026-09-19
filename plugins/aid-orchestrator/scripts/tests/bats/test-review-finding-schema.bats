#!/usr/bin/env bats
# aid-tier: t0
# test-review-finding-schema.bats — the reviewer's answer contract shared by
# every review checkpoint (review-finding.schema.json) and the one review
# prompt template. A cp2 answer with pre-image evidence or a reproduction
# passes; the role set follows the checkpoint; a behaviour trace must be
# complete; every example answer of both roles skills passes; the template
# renders for cp1 and cp2 with the same header; the controller adapter is
# quoted byte for byte by the commands that dispatch reviewers.
# Origin: P094 Step 2 (step review rebuild); the CP1 cases stay in
# test-plan-review-schema.bats until P094 Step 14 deletes that suite.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  source "$AID_PLUGIN_PATH/scripts/lib/aid-plan-review-packet.sh"
  SCHEMA="$AID_PLUGIN_PATH/defaults/schemas/review-finding.schema.json"
  TEMPLATE="$AID_PLUGIN_PATH/defaults/prompts/review-prompt-v1.md"
  TEST_DIR="$(mktemp -d)"
}
teardown() { rm -rf "$TEST_DIR"; }

# _proof <answer.json> — the adjudicator's per-finding proof check over the
# first finding; prints the rejection reason, nothing for a proven finding.
_proof() {
  local r; r="$(jq -r --slurpfile s "$SCHEMA" "$(aid_plan_review_proof_jq) .findings[0] | proof_error" "$1")"
  [[ -z "$r" ]] || { echo "$r"; return 1; }
}
# _shape <answer.json> — the answer-shape check of the schema itself, as jq
# reads it: role against the checkpoint's role list, finding keys, trace shape.
# Mirrors what the round's collect enforces through the schema; the bats suite
# asserts the SCHEMA, not a validator library, so it uses jq alone.
_shape() {
  jq -e --slurpfile s "$SCHEMA" '
    ($s[0]) as $schema
    | (if (.checkpoint // "cp1") == "cp1" then $schema["$defs"].roles_cp1.enum else $schema["$defs"].roles_step.enum end) as $roles
    | ($schema["$defs"].finding.properties | keys) as $fkeys
    | ($schema["$defs"].finding.required) as $freq
    | (.role | IN($roles[]))
      and ((.checkpoint // "cp1") | IN($schema["$defs"].checkpoint.enum[]))
      and (.findings | all(
            (keys - $fkeys | length == 0)
            and ([$freq[] as $k | has($k)] | all)
            and (.behaviour_trace == null or (.behaviour_trace | length > 0 and all(
                  has("request") and has("path") and has("sink") and (.branches | length > 0 and all(has("name") and has("outcome"))))))))
      and ((.findings | length) > 0 or ((.no_findings_reason // "") != ""))
  ' "$1" >/dev/null
}
_cp2() {  # a valid cp2 answer, then a jq filter applied to it
  jq -n '{role: "step_generalist", checkpoint: "cp2",
          findings: [{id: "step_generalist-1", checkpoint: "cp2", step: 3, severity: "major",
                      claim: "c", command: "grep -n x scripts/a.sh", evidence: "scripts/a.sh:4", fix: "f"}]}' \
    | jq "$1" > "$TEST_DIR/a.json"
}

@test "cp2: a valid answer passes the shape and the proof" {
  _cp2 '.'
  _shape "$TEST_DIR/a.json"
  run _proof "$TEST_DIR/a.json"; [ "$status" -eq 0 ]
}
@test "cp2: pre-image evidence <sha>:path:line passes; a bare path does not" {
  _cp2 '.findings[0].evidence = "1a2b3c4d:scripts/a.sh:4; scripts/b.sh:9"'
  run _proof "$TEST_DIR/a.json"; [ "$status" -eq 0 ]
  _cp2 '.findings[0].evidence = "scripts/a.sh"'
  run _proof "$TEST_DIR/a.json"; [ "$status" -eq 1 ]; [ "$output" = missing_evidence ]
}
@test "cp2: a reproduction under repro/ is a command; a script elsewhere is not" {
  _cp2 '.findings[0].command = "bash repro/race-1.sh"'
  run _proof "$TEST_DIR/a.json"; [ "$status" -eq 0 ]
  _cp2 '.findings[0].command = "bash /tmp/x.sh"'
  run _proof "$TEST_DIR/a.json"; [ "$status" -eq 1 ]; [ "$output" = missing_command ]
}
@test "roles follow the checkpoint: a step role is refused on a cp1 answer and a plan role on a cp2 answer" {
  _cp2 '.checkpoint = "cp1" | .findings[0].checkpoint = "cp1"'
  ! _shape "$TEST_DIR/a.json"
  _cp2 '.role = "reuse"'
  ! _shape "$TEST_DIR/a.json"
  _cp2 'del(.checkpoint) | .role = "reuse" | del(.findings[0].checkpoint)'
  _shape "$TEST_DIR/a.json"
}
@test "cp1: the answer-shape check of the CP1 round refuses a step role, as before" {
  _cp2 'del(.checkpoint) | del(.findings[0].checkpoint)'
  run aid_plan_review_answer_error "$TEST_DIR/a.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"role must be one of"* ]]
}
@test "trace: a behaviour trace with a branch lacking its outcome is refused; a complete one passes" {
  _cp2 '.findings[0].behaviour_trace = [{request: "POST /x", path: "a → b", sink: "db", branches: [{name: "ok"}]}]'
  ! _shape "$TEST_DIR/a.json"
  _cp2 '.findings[0].behaviour_trace = [{request: "POST /x", path: "a → b", sink: "db", branches: [{name: "ok", outcome: "200"}]}]'
  _shape "$TEST_DIR/a.json"
}
@test "unknown checkpoint and empty findings without a reason are refused" {
  _cp2 '.checkpoint = "cp4"'
  ! _shape "$TEST_DIR/a.json"
  _cp2 '.findings = []'
  ! _shape "$TEST_DIR/a.json"
}
@test "skills: every example answer in both roles skills passes the shape" {
  local n=0 f s
  for s in plan-review-roles step-review-roles; do
    awk -v dir="$TEST_DIR/$s" 'BEGIN{system("mkdir -p " dir)} /^```json$/{on=1; n++; next} /^```$/{on=0} on{print > (dir "/ex" n ".json")}' \
      "$AID_PLUGIN_PATH/skills/$s.md"
    for f in "$TEST_DIR/$s"/ex*.json; do _shape "$f" || { echo "fails: $f"; return 1; }; n=$((n+1)); done
  done
  [ "$n" -eq 4 ]
}
@test "skills: five step roles with Questions and a Stop rule, matching the schema's step role list" {
  local s="$AID_PLUGIN_PATH/skills/step-review-roles.md"
  [ "$(grep -c '^## Role: ' "$s")" -eq 5 ]
  [ "$(grep -c '^### Questions$' "$s")" -eq 5 ]
  [ "$(grep -c '^### Stop rule$' "$s")" -eq 5 ]
  diff <(grep '^## Role: ' "$s" | sed 's/^## Role: //' | sort) <(jq -r '.["$defs"].roles_step.enum[]' "$SCHEMA" | sort)
  diff <(grep '^## Role: ' "$AID_PLUGIN_PATH/skills/plan-review-roles.md" | sed 's/^## Role: //' | sort) \
       <(jq -r '.["$defs"].roles_cp1.enum[]' "$SCHEMA" | sort)
}
@test "template: renders for cp1 and cp2 from seven string variables, same header text above the first variable" {
  local vars="$TEST_DIR/vars.json" cp
  for cp in cp1 cp2; do
    jq -n --arg cp "$cp" '{role_section: "## Role: x", checkpoint: $cp, round: "1", output_path: "/tmp/x.json",
                            evidence_forms: "path:line", packet_name: "a thing", confirmation_note: ""}' > "$vars"
    run bash "$AID_PLUGIN_PATH/scripts/lib/aid-render-prompt.sh" --template "$TEMPLATE" --vars-json "$vars" --output "$TEST_DIR/prompt-$cp.md"
    [ "$status" -eq 0 ]
    ! grep -q '{{' "$TEST_DIR/prompt-$cp.md"
    grep -q "^# $cp review, round 1$" "$TEST_DIR/prompt-$cp.md"
  done
  # everything above "## Your role" except the title line is identical for both checkpoints
  diff <(sed -n '1,/^## Your role$/p' "$TEST_DIR/prompt-cp1.md" | grep -v '^# cp1 review') \
       <(sed -n '1,/^## Your role$/p' "$TEST_DIR/prompt-cp2.md" | grep -v '^# cp2 review')
}
@test "template: the CP1 packet library renders through the shared template with its cp1 values" {
  mkdir -p "$TEST_DIR/round-1"
  aid_plan_review_prompt_render reuse 1 "$TEST_DIR/round-1" 2>/dev/null || true
  # the packet append needs a packet; the rendered part above the marker is what this asserts
  [ -f "$TEST_DIR/round-1/vars-reuse.json" ]
  [ "$(jq -r .checkpoint "$TEST_DIR/round-1/vars-reuse.json")" = cp1 ]
  [ "$(jq -r .packet_name "$TEST_DIR/round-1/vars-reuse.json")" != "" ]
}
@test "adapter: commands/aid-plan.md quotes the claude adapter instruction byte for byte" {
  local cmd="$AID_PLUGIN_PATH/commands/aid-plan.md" adapter
  adapter="$AID_PLUGIN_PATH/scripts/lib/aid-review-adapter-claude.md"
  diff <(awk '/^<!-- adapter:end -->$/{on=0} on{print} /^<!-- adapter:begin -->$/{on=1}' "$cmd") "$adapter"
}
@test "adapter: commands/aid-run.md quotes the same adapter byte for byte" {
  local cmd="$AID_PLUGIN_PATH/commands/aid-run.md"
  grep -q '^<!-- adapter:begin -->$' "$cmd"   # P094 Step 10 wrote the section; no skip any more
  diff <(awk '/^<!-- adapter:end -->$/{on=0} on{print} /^<!-- adapter:begin -->$/{on=1}' "$cmd") \
       "$AID_PLUGIN_PATH/scripts/lib/aid-review-adapter-claude.md"
}
