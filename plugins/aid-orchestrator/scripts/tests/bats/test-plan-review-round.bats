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
