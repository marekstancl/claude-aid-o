#!/usr/bin/env bats
# aid-tier: t1
# test-cp1-gate.bats — aid-cp1-gate.sh decides from plan-review round evidence.
# Every case is a fixture tree (no model, no network): closed and valid rounds
# pass, a missing or unclosed round fails naming it, open blockers need a
# second round and an acceptance criterion quoting them, a third round needs
# the PM's override, and tampered evidence is a hard condition (exit 3).
# Origin: P093 Step 7 (plan review rebuild); replaces test-cp1-gate.sh.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  GATE="$AID_PLUGIN_PATH/scripts/aid-cp1-gate.sh"
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/.aid-o/plans"
  PLAN="$ROOT/.aid-o/plans/p.md"
  CP1="$ROOT/.aid-o/work/evidence/P900/cp1"
  cat > "$PLAN" <<'MD'
---
id: P900
type: regular
---
# Plan

### Step 1: first

**Acceptance Criteria:**
- [ ] it works

### Step 2: second

**Acceptance Criteria:**
- [ ] it also works

## Success Criteria

- [ ] done
MD
}
teardown() { rm -rf "$ROOT"; }

# _round <n> <findings-json> [closed=1] [status=valid] — a round as
# aid-plan-review-round.sh leaves it, reviewing the plan as it is now.
_round() {
  local n="$1" findings="$2" closed="${3:-1}" status="${4:-valid}" d="$CP1/round-$1"
  mkdir -p "$d/packet"
  cp "$PLAN" "$d/packet/plan.md"
  jq -n --argjson n "$n" --arg sha "$(sha256sum "$PLAN" | cut -d' ' -f1)" \
    '{round: $n, plan_sha256: $sha, reviewers_expected: ["generalist_a"], min_answers_effective: 1}' > "$d/round.json"
  jq -n --arg s "$status" '{valid: ["generalist_a"], invalid: [], missing: [], status: $s}' > "$d/collect.json"
  jq -n --argjson n "$n" --argjson f "$findings" \
    '{round: $n, findings: $f, blockers_open: ([$f[] | select(.severity == "blocker" and (.status == "open" or .status == "disputed"))] | length)}' > "$d/merged.json"
  [[ "$closed" == 1 ]] && jq -n --argjson n "$n" '{round: $n, reviewers: {}}' > "$d/measurement.json"
  [ -f "$CP1/rounds.json" ] || echo '[]' > "$CP1/rounds.json"
  jq --argjson n "$n" '. + [{round: $n}]' "$CP1/rounds.json" > "$CP1/r" && mv "$CP1/r" "$CP1/rounds.json"
}
BLOCKER='[{"fingerprint":"f1","step":2,"severity":"blocker","claim":"Step two writes a file nothing reads later","status":"open","reported_by":["reuse"]}]'
_blocker_status() { jq -c --arg s "$1" '.[0].status = $s' <<< "$BLOCKER"; }
_quote_blocker() { sed -i 's/^- \[ \] it also works$/- [ ] it also works\n- [ ] Known risk: step two writes a file nothing reads\n  later, accepted by the PM/' "$PLAN"; }

@test "gate: round 1 closed and valid with zero blockers passes" {
  _round 1 '[]'
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *PASS* ]]
}
@test "gate: no round-1 fails naming round-1 and prepare" {
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"no plan review round-1"* ]]; [[ "$output" == *"prepare"* ]]
}
@test "gate: a round without measurement.json is not closed" {
  _round 1 '[]' 0
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"measurement.json"* ]]
}
@test "gate: an invalid round fails naming retry" {
  _round 1 '[]' 1 invalid
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"round-1 invalid"* ]]; [[ "$output" == *retry* ]]
}
@test "gate: open blockers after round 1 and no round 2 fail naming round-2" {
  _round 1 "$BLOCKER"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"no round-2"* ]]
}
@test "gate: a blocker surviving round 2 passes when an AC of its step quotes it (multi-line criterion)" {
  _round 1 "$(_blocker_status fixed)"
  _quote_blocker
  _round 2 "$BLOCKER"
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
}
@test "gate: a surviving blocker nobody quoted fails naming its step" {
  _round 1 "$(_blocker_status fixed)"
  _round 2 "$BLOCKER"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"acceptance criterion of Step 2"* ]]
}
@test "gate: a disputed blocker without an AC fails naming it" {
  _round 1 "$(_blocker_status fixed)"
  _round 2 "$(_blocker_status disputed)"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"step two writes a file nothing reads"* ]]
}
@test "gate: override rounds 1 with the open blocker quoted passes after one round" {
  _quote_blocker
  _round 1 "$BLOCKER"
  jq -n '{rounds: 1, by: "PM", at: "x", reason: "PM: one round is enough here", plan_sha256_at_issue: "x", recorded_by: "controller"}' > "$CP1/override.json"
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
}
@test "gate: a round-3 without override.json fails naming override.json" {
  _round 1 "$(_blocker_status fixed)"; _round 2 "$(_blocker_status fixed)"; _round 3 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"override.json"* ]]
  jq -n '{rounds: 3, by: "PM", at: "x", reason: "PM: send a third round please", plan_sha256_at_issue: "x", recorded_by: "controller"}' > "$CP1/override.json"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]
}
@test "gate: the plan changed after the last round fails naming sha256; plan-final.md makes it pass" {
  _round 1 '[]'
  echo "late edit" >> "$PLAN"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"sha256"* ]]
  cp "$PLAN" "$CP1/round-1/plan-final.md"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]
}
@test "gate: a round the index lists but that is gone is hard (exit 3) naming rounds.json" {
  _round 1 '[]'; _round 2 '[]'
  rm -rf "$CP1/round-2"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"rounds.json lists a round that is missing: round-2"* ]]
}
@test "gate: unreadable round evidence and a malformed override are hard" {
  _round 1 '[]'
  echo "not json" > "$CP1/round-1/merged.json"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"round 1 evidence unreadable"* ]]
  rm -rf "$CP1"; _round 1 '[]'
  echo '{"rounds": 7}' > "$CP1/override.json"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"override.json is malformed"* ]]
}
@test "gate: --json carries the same verdict; cp1/manual/ is ignored" {
  mkdir -p "$CP1/manual/20260918T000000Z"
  echo garbage > "$CP1/manual/20260918T000000Z/merged.json"
  _round 1 '[]'
  run "$GATE" --plan "$PLAN" --json "$ROOT/v.json"
  [ "$status" -eq 0 ]; [ "$(jq -r .verdict "$ROOT/v.json")" = pass ]
  rm -rf "$CP1"
  run "$GATE" --plan "$PLAN" --json "$ROOT/v.json"
  [ "$status" -eq 1 ]; [ "$(jq -r .verdict "$ROOT/v.json")" = fail ]
  [[ "$(jq -r '.failures[0]' "$ROOT/v.json")" == *"round-1"* ]]
}
@test "gate: a project that switched plan review off passes with a notice" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  printf 'review_checkpoints:\n  cp1_plan_review: false\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]; [[ "$output" == *"switched off"* ]]
}
@test "gate: a broken plan_review config is hard naming plan_review config" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  yq '.review_checkpoints.plan_review.reviewers[0].provider = "gemini"' "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" \
    > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  _round 1 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"plan_review config:"* ]]
}
@test "gate: an empty round-3 directory without override.json is named as such" {
  _round 1 "$(_blocker_status fixed)"; _round 2 "$(_blocker_status fixed)"
  mkdir -p "$CP1/round-3"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"round-3 exists without the PM's override.json"* ]]
}
