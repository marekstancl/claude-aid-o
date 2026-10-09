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
source "$BATS_TEST_DIRNAME/../lib/aid-test-plan-fixture.sh"

# _round <n> <findings-json> [closed=1] [status=valid] — a round as
# aid-review-round.sh --plan leaves it, reviewing the plan as it is now.
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
# _fixcheck <n> — round <n>'s fix passed fix-check (what the second-round rule reads)
_fixcheck() { jq -n '{pass: true, added_outside_fixes: []}' > "$CP1/round-$1/fix-diff.json"; }
_quote_blocker() { sed -i 's/^- \[ \] it also works$/- [ ] it also works\n- [ ] Known risk: step two writes a file nothing reads\n  later, accepted by the PM/' "$PLAN"; }

@test "gate: round 1 closed and valid with zero blockers passes" {
  _round 1 '[]'
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *PASS* ]]
}
@test "gate: no round-1 is hard naming the critic; with a passed critic check it fails naming round-1 and prepare" {
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"no passed critic check for the plan as it is"* ]]; [[ "$output" == *"next: aid_critic_prepare P900"* ]]
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
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
@test "round-2: a blocker surviving round 2 passes when an AC of its step quotes it (multi-line criterion)" {
  _round 1 "$(_blocker_status fixed)"; _fixcheck 1
  _quote_blocker
  _round 2 "$BLOCKER"
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
}
@test "round-2: a surviving blocker nobody quoted fails naming its step" {
  _round 1 "$(_blocker_status fixed)"; _fixcheck 1
  _round 2 "$BLOCKER"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"acceptance criterion of Step 2"* ]]
}
@test "round-2: a disputed blocker without an AC fails naming it" {
  _round 1 "$(_blocker_status fixed)"; _fixcheck 1
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
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
  run "$GATE" --plan "$PLAN" --json "$ROOT/v.json"
  [ "$status" -eq 1 ]; [ "$(jq -r .verdict "$ROOT/v.json")" = fail ]
  [[ "$(jq -r '.failures[0]' "$ROOT/v.json")" == *"round-1"* ]]
}
@test "gate: a project that switched plan review off passes with a notice" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  printf 'review_checkpoints:\n  cp1_plan_review: false\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
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
@test "gate: a round whose collect was invalid is a forceable FAIL naming retry, not a hard exit" {
  _round 1 '[]' 1 invalid
  rm "$CP1/round-1/merged.json"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *retry* ]]
}
@test "gate: --project-root naming a linked worktree of a project that tracks plan-state reads the primary's config (agents P009)" {
  mkdir -p "$ROOT/.aid-o/work/plan-state/P001"; : > "$ROOT/.aid-o/work/plan-state/P001/x"
  ( cd "$ROOT" && git init -q -b main && git config user.email t@t && git config user.name t && git add -A && git commit -qm seed && git worktree add -q "$ROOT/wt" -b wtb )
  # the primary switches plan review off AFTER the worktree was branched
  mkdir -p "$ROOT/.aid-o/config/policies"
  printf 'review_checkpoints:\n  cp1_plan_review: false\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"   # the critic evidence lives in the state root
  run "$GATE" --plan "$ROOT/wt/.aid-o/plans/p.md" --project-root "$ROOT/wt"
  [ "$status" -eq 0 ]; [[ "$output" == *"switched off"* ]]
}

# ── P109 Step 3: the critic is checked hard, against the plan entering round 1 ──
# Defect: P014 — a plan reviewed and generated with no critic at all; a --force
# that waives it.
_bind_round1() { jq --arg c "${1:-$(sha256sum "$PLAN" | cut -d' ' -f1)}" -n '{plan_sha256: $c, files: [], critic_check_sha: $c}' > "$CP1/round-1/packet/manifest.json"; }

@test "critic: a round-1 manifest naming critic_check_sha with no check, a failed check or a foreign sha is hard" {
  _round 1 '[]'; _bind_round1
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"no passed critic check for the plan that entered round 1"* ]]; [[ "$output" == *"evidence missing"* ]]
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
  jq '.passed = false | .reason = "missing heading: level 1"' "$ROOT/.aid-o/work/evidence/P900/critic/plan/check.json" > "$ROOT/c" && mv "$ROOT/c" "$ROOT/.aid-o/work/evidence/P900/critic/plan/check.json"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"the check did not pass: missing heading: level 1"* ]]
  aid_fixture_seed_critic_check "$ROOT" "$PLAN" "$(printf other | sha256sum | cut -d' ' -f1)"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"made for another plan"* ]]
}

@test "critic: the check bound to round 1 passes; a round-1 manifest without the key (before 2.115.0) is not checked" {
  _round 1 '[]'; _bind_round1
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
  rm -rf "$ROOT/.aid-o/work/evidence/P900/critic"
  jq 'del(.critic_check_sha)' "$CP1/round-1/packet/manifest.json" > "$ROOT/m" && mv "$ROOT/m" "$CP1/round-1/packet/manifest.json"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]
}

@test "critic: a plan revised after round 1 still passes — the binding is the plan that entered round 1" {
  _round 1 '[]'; _bind_round1
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
  echo "fixed after round 1" >> "$PLAN"
  cp "$PLAN" "$CP1/round-1/plan-final.md"
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "critic: review switched off and no round — failing against the current plan, passing once the check exists" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  printf 'review_checkpoints:\n  cp1_plan_review: false\n' > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"no passed critic check for the plan as it is"* ]]
  aid_fixture_seed_critic_check "$ROOT" "$PLAN"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]; [[ "$output" == *"switched off"* ]]
}

@test "critic: a missing critic reaches generation as aid_cp1_blocked, never as forceable" {
  ( cd "$ROOT" && git init -q -b main && git config user.email t@t && git config user.name t && printf '.aid-o/\n' > .gitignore && git add -A && git commit -qm seed )
  run bash -c "cd '$ROOT' && bash '$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh' --plan '$PLAN' --force --reason 'the PM forces generation past the gate here'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"aid_cp1_blocked"* ]]
  [[ "$output" != *"aid_generation_force_required"* ]]
}

# ── P109 Step 4: one round by default, the second only after a blocker ──────
# Defect: P014 — three rounds, 45 USD, the softening of point 2 unseen; a
# second round paid for nothing.
MAJOR='[{"fingerprint":"f2","step":1,"severity":"major","claim":"Step one names no test","status":"open","reported_by":["reuse"]}]'

@test "round-2: at rounds_default 1 a clean round 1 passes with no round 2" {
  _round 1 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 0 ]
}

@test "round-2: round 2 after a blocker and a passing fix-check passes without an override" {
  _round 1 "$(_blocker_status fixed)"; _fixcheck 1; _round 2 '[]'
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
}

@test "round-2: round 2 after a major-only round 1, or after a clean one, fails naming the override; so does round 2 without fix-check" {
  _round 1 "$MAJOR"; _fixcheck 1; _round 2 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"round-2 exists without the PM's override.json"* ]]
  rm -rf "$CP1"; _round 1 '[]'; _fixcheck 1; _round 2 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"override.json"* ]]
  rm -rf "$CP1"; _round 1 "$(_blocker_status fixed)"; _round 2 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"override.json"* ]]
}

@test "round-2: round 3 after the allowed second round still needs the override" {
  _round 1 "$(_blocker_status fixed)"; _fixcheck 1; _round 2 "$(_blocker_status fixed)"; _fixcheck 2; _round 3 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"round-3 exists without the PM's override.json"* ]]
}

@test "round-2: second_round_when with another value is refused by name" {
  mkdir -p "$ROOT/.aid-o/config/policies"
  yq '.review_checkpoints.plan_review.second_round_when = "sometimes"' "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" \
    > "$ROOT/.aid-o/config/policies/review-checkpoints.yaml"
  _round 1 '[]'
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"second_round_when must be blocker_and_fix_check (got 'sometimes')"* ]]
}

@test "zadani: a packet whose brief sha differs from the brief the plan names is hard, naming the brief" {
  mkdir -p "$ROOT/.aid-o/plans"; printf 'brief v1\n' > "$ROOT/.aid-o/plans/P900-zadani.md"
  sed -i 's/^type: regular$/type: regular\nzadani: .aid-o\/plans\/P900-zadani.md/' "$PLAN"
  _round 1 '[]'; aid_fixture_seed_critic_check "$ROOT" "$PLAN"
  jq -n --arg z "$(sha256sum "$ROOT/.aid-o/plans/P900-zadani.md" | cut -d' ' -f1)" --arg c "$(sha256sum "$PLAN" | cut -d' ' -f1)" \
    '{plan_sha256: $c, files: [], critic_check_sha: $c, zadani_sha256: $z}' > "$CP1/round-1/packet/manifest.json"
  run "$GATE" --plan "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]
  printf 'brief v2\n' > "$ROOT/.aid-o/plans/P900-zadani.md"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"the brief changed after round 1 (.aid-o/plans/P900-zadani.md"* ]]
  [[ "$output" == *"brief_changed_after_round"* ]]
  # the binding removed from the plan after round 1 is the same change
  printf 'brief v1\n' > "$ROOT/.aid-o/plans/P900-zadani.md"
  sed -i '/^zadani:/d' "$PLAN"; cp "$PLAN" "$CP1/round-1/plan-final.md"
  run "$GATE" --plan "$PLAN"
  [ "$status" -eq 3 ]; [[ "$output" == *"the brief changed after round 1 (the plan names no zadani: now"* ]]
}
