#!/usr/bin/env bats
# aid-tier: t1
# test-plan-review-round.bats — aid-plan-review-round.sh on small fixture trees.
# prepare builds one packet and one prompt per expected reviewer and refuses a
# stale script report, a second preparation and a round beyond the default.
# Origin: P093 Steps 3, 4 and 6 (plan review rebuild).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  ROUND_SH="$AID_PLUGIN_PATH/scripts/aid-plan-review-round.sh"
  ROOT="$(mktemp -d)"; cd "$ROOT"
  git init -q .
  mkdir -p .aid-o/plans .aid-o/work/evidence/P900 scripts
  printf 'one\ntwo\nthree\n' > scripts/a.sh
  PLAN="$ROOT/.aid-o/plans/p.md"
  EV="$ROOT/.aid-o/work/evidence/P900"
  CP1="$EV/cp1"
  _plan regular
}
teardown() { rm -rf "$ROOT"; }

# _plan <type> — a two-step plan (with a literal {{ in it) and a matching plan-check.json
_plan() {
  printf -- '---\nid: P900\ntype: %s\n---\n# Plan\n\n### Step 1: first\n\nuses {{x}} literally\n\n### Step 2: second\n\ntext\n' "$1" > "$PLAN"
  _check
}
_check() {
  jq -n --arg s "$(sha256sum "$PLAN" | cut -d' ' -f1)" \
    '{plan_sha256: $s, warnings: [{id: "A9", location: "p.md", message: "size"}]}' > "$EV/plan-check.json"
}

@test "prepare: six prompts, the packet, round.json and an index entry" {
  run "$ROUND_SH" prepare "$PLAN" --round 1
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(ls "$CP1/round-1"/prompt-*.md | wc -l)" -eq 6 ]
  [ "$(jq '.files | length' "$CP1/round-1/packet/manifest.json")" -eq 3 ]
  [ "$(jq '.reviewers_expected | length' "$CP1/round-1/round.json")" -eq 6 ]
  [ "$(jq '.min_answers_effective' "$CP1/round-1/round.json")" -eq 4 ]
  [ "$(jq 'length' "$CP1/rounds.json")" -eq 1 ]
  # rendered part has no placeholder; the plan's literal {{x}} is in the packet
  ! sed '/^--- PACKET ---$/q' "$CP1/round-1/prompt-reuse.md" | grep -q '{{'
  grep -q 'uses {{x}} literally' "$CP1/round-1/prompt-reuse.md"
  grep -q '^## Role: reuse$' "$CP1/round-1/prompt-reuse.md"
  grep -q "\"event\":\"plan_review_round_start\"" "$EV/timeline.jsonl"
}
@test "prepare: a stale plan-check.json is refused naming sha256" {
  echo "edited" >> "$PLAN"
  run "$ROUND_SH" prepare "$PLAN" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"plan-check.json does not match plan (sha256"* ]]
  [ ! -d "$CP1/round-1/packet" ]
}
@test "prepare: without plan-check.json it is refused naming aid-plan-check.sh" {
  rm "$EV/plan-check.json"
  run "$ROUND_SH" prepare "$PLAN" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"aid-plan-check.sh"* ]]
}
@test "prepare: a type docs plan gets the two generalists and min_answers_effective 2" {
  _plan docs
  run "$ROUND_SH" prepare "$PLAN" --round 1
  [ "$status" -eq 0 ]
  [ "$(ls "$CP1/round-1"/prompt-*.md | xargs -n1 basename | tr '\n' ' ')" = "prompt-generalist_a.md prompt-generalist_b.md " ]
  [ "$(jq '.min_answers_effective' "$CP1/round-1/round.json")" -eq 2 ]
}
@test "prepare: a second prepare of the same round is refused naming packet/" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  run "$ROUND_SH" prepare "$PLAN" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"already prepared"* ]]
}
@test "prepare: round 3 needs override.json with rounds >= 3" {
  mkdir -p "$CP1/round-2"
  jq -n '{steps_changed: [1], added_outside_fixes: [], pass: true}' > "$CP1/round-2/fix-diff.json"
  jq -n '{findings: [{fingerprint: "f", step: 1, severity: "blocker", status: "open", reported_by: ["reuse"]}], blockers_open: 1}' > "$CP1/round-2/merged.json"
  run "$ROUND_SH" prepare "$PLAN" --round 3
  [ "$status" -eq 1 ]; [[ "$output" == *"override.json"* ]]
  jq -n '{rounds: 3, by: "PM", at: "2026-09-18T00:00:00Z", reason: "PM: send a third round please", plan_sha256_at_issue: "x", recorded_by: "controller"}' > "$CP1/override.json"
  run "$ROUND_SH" prepare "$PLAN" --round 3
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -c '.reviewers_expected' "$CP1/round-3/round.json")" = '["reuse"]' ]
}
@test "prepare: round 2 is refused while the round-1 fix failed fix-check" {
  mkdir -p "$CP1/round-1"
  jq -n '{steps_changed: [2], added_outside_fixes: [{step: 2, kind: "step", text: "new"}], pass: false}' > "$CP1/round-1/fix-diff.json"
  run "$ROUND_SH" prepare "$PLAN" --round 2
  [ "$status" -eq 1 ]; [[ "$output" == *"did not pass fix-check"* ]]
}

# _answer <role> [jq filter] — a valid one-finding answer for <role> in round 1
_answer() {
  jq -n --arg r "$1" '{role: $r, findings: [{id: "\($r)-1", step: 1, severity: "major",
      claim: "step one misses \($r)", command: "grep -n two scripts/a.sh",
      evidence: "scripts/a.sh:2", fix: "say it"}]}' | jq "${2:-.}" > "$CP1/round-1/reviewer-$1.json"
}
_answer_all() { local r; for r in generalist_a generalist_b behaviour_edges feasibility_deps reuse enforcement_tests; do _answer "$r"; done; }

@test "collect: six valid answers make a valid round and run the adjudicator" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer_all
  run "$ROUND_SH" collect "$PLAN" --round 1
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$CP1/round-1/collect.json")" = valid ]
  [ -f "$CP1/round-1/merged.json" ]
  [[ "$output" == *"6 of 6 answered, missing: none"* ]]
}
@test "collect: three answers make an invalid round naming min 4" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer generalist_a; _answer reuse; _answer behaviour_edges
  run "$ROUND_SH" collect "$PLAN" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"invalid: 3 of 6 answered (min 4)"* ]]
  [ "$(jq -r .status "$CP1/round-1/collect.json")" = invalid ]
  [ ! -f "$CP1/round-1/merged.json" ]
}
@test "collect: four answers without a generalist are invalid naming generalist" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer reuse; _answer behaviour_edges; _answer feasibility_deps; _answer enforcement_tests
  run "$ROUND_SH" collect "$PLAN" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"generalist"* ]]
}
@test "collect: a fenced answer is accepted; a mislabelled one is role_mismatch" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer_all
  { echo '```json'; cat "$CP1/round-1/reviewer-reuse.json"; echo '```'; } > "$ROOT/f" && mv "$ROOT/f" "$CP1/round-1/reviewer-reuse.json"
  _answer enforcement_tests '.role = "reuse"'
  run "$ROUND_SH" collect "$PLAN" --round 1
  [ "$status" -eq 0 ]
  [ "$(jq -c .valid "$CP1/round-1/collect.json" | grep -c reuse)" -eq 1 ]
  jq -e '.invalid[] | select(.role == "enforcement_tests" and (.reason | startswith("role_mismatch")))' "$CP1/round-1/collect.json"
  [ -f "$CP1/round-1/reviewer-enforcement_tests.invalid.txt" ]
}
@test "collect: an empty expected set is a valid empty round" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  jq '.reviewers_expected = [] | .min_answers_effective = 0' "$CP1/round-1/round.json" > "$ROOT/r" && mv "$ROOT/r" "$CP1/round-1/round.json"
  run "$ROUND_SH" collect "$PLAN" --round 1
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .status "$CP1/round-1/collect.json")" = valid ]
  [ "$(jq .blockers_open "$CP1/round-1/merged.json")" -eq 0 ]
}
@test "dispatch: a stubbed codex answer lands as reviewer-generalist_b.json with usage; a second dispatch is refused" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  mkdir -p "$ROOT/bin"
  cat > "$ROOT/bin/codex" <<'STUB'
#!/usr/bin/env bash
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == --output-last-message ]] && out="$2"; shift; done
printf '```json\n{"role":"generalist_b","findings":[],"no_findings_reason":"nothing found"}\n```\n' > "$out"
echo '{"type":"thread.started"}'
echo '{"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":90}}'
STUB
  chmod +x "$ROOT/bin/codex"
  PATH="$ROOT/bin:$PATH" run "$ROUND_SH" dispatch "$PLAN" --round 1 --provider codex --role generalist_b
  echo "$output"; [ "$status" -eq 0 ]
  jq -e '.role == "generalist_b"' "$CP1/round-1/reviewer-generalist_b.json"
  [ "$(jq .tokens_in "$CP1/round-1/codex-generalist_b.usage.json")" -eq 1200 ]
  PATH="$ROOT/bin:$PATH" run "$ROUND_SH" dispatch "$PLAN" --round 1 --provider codex --role generalist_b
  [ "$status" -eq 1 ]; [[ "$output" == *"never paid twice"* ]]
}
@test "dispatch: a claude role is refused naming the controller instruction" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  run "$ROUND_SH" dispatch "$PLAN" --round 1 --provider codex --role reuse
  [ "$status" -eq 1 ]; [[ "$output" == *"aid-plan-review-adapter-claude.md"* ]]
}
@test "retry: refused for a valid role, allowed for an invalid one" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer_all; _answer reuse '.findings[0].severity = "critical"'
  "$ROUND_SH" collect "$PLAN" --round 1 >/dev/null
  run "$ROUND_SH" retry "$PLAN" --round 1 --role generalist_a
  [ "$status" -eq 1 ]; [[ "$output" == *"answered validly"* ]]
  run "$ROUND_SH" retry "$PLAN" --round 1 --role reuse
  [ "$status" -eq 0 ]; [ ! -f "$CP1/round-1/reviewer-reuse.json" ]
}
