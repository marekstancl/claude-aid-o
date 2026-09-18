#!/usr/bin/env bats
# aid-tier: t1
# test-plan-review-adjudicate.bats — aid-plan-review-adjudicate.sh on fixture rounds.
# Unproven findings are rejected with their reason, identical findings from two
# reviewers merge, yield is counted, and the next round marks what was fixed.
# Origin: P093 Step 5 (plan review rebuild).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  ADJ="$AID_PLUGIN_PATH/scripts/aid-plan-review-adjudicate.sh"
  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/scripts" "$ROOT/.aid-worktrees/x"
  printf 'one\ntwo\nthree\n' > "$ROOT/scripts/a.sh"
  printf 'x\n' > "$ROOT/.aid-worktrees/x/a.sh"
  R1="$ROOT/round-1"; R2="$ROOT/round-2"
  _round "$R1" 1 reuse behaviour_edges
}
teardown() { rm -rf "$ROOT"; }

# _round <dir> <n> <roles...> — a collected round whose valid reviewers are <roles>
_round() {
  local dir="$1" n="$2"; shift 2
  mkdir -p "$dir/packet"
  printf 'l1\nl2\nl3\nl4\n' > "$dir/packet/plan.md"
  jq -n --argjson n "$n" '{round: $n, plan_sha256: "abc", reviewers_expected: $ARGS.positional}' --args "$@" > "$dir/round.json"
  jq -n '{valid: $ARGS.positional}' --args "$@" > "$dir/collect.json"
  local r; for r in "$@"; do jq -n --arg r "$r" '{role: $r, findings: [], no_findings_reason: "none"}' > "$dir/reviewer-$r.json"; done
}
# _finding <dir> <role> <jq filter over one finding> — appends a finding to the role's answer
_finding() {
  local f="$1/reviewer-$2.json"
  jq --arg r "$2" --argjson x "$(jq -n "{id: \"$2-1\", step: 1, severity: \"blocker\", claim: \"Step one reads a file nothing writes\", command: \"grep -n two scripts/a.sh\", evidence: \"scripts/a.sh:2\", fix: \"f\"} | $3")" \
    '.findings += [$x]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

@test "adjudicate: the same finding from two reviewers merges with also_reported_by 2" {
  _finding "$R1" reuse '.'
  _finding "$R1" behaviour_edges '.severity = "major"'
  run "$ADJ" "$R1" --project-root "$ROOT"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq '.findings | length' "$R1/merged.json")" -eq 1 ]
  jq -e '.findings[0] | .also_reported_by == 2 and .reported_by == ["behaviour_edges", "reuse"] and .severity == "blocker"' "$R1/merged.json"
  [ "$(jq .blockers_open "$R1/merged.json")" -eq 1 ]
}
@test "adjudicate: each unproven finding is rejected with its reason" {
  _finding "$R1" reuse '.evidence = "scripts/missing.sh:1"'
  _finding "$R1" reuse '.id = "reuse-2" | .command = "cat scripts/a.sh"'
  _finding "$R1" reuse '.id = "reuse-3" | .evidence = "scripts/a.sh"'
  _finding "$R1" reuse '.id = "reuse-4" | .evidence = ".aid-worktrees/x/a.sh:1"'
  _finding "$R1" reuse '.id = "reuse-5" | .evidence = "../etc/passwd:1"'
  _finding "$R1" reuse '.id = "reuse-6" | .evidence = "plan.md:9"'
  _finding "$R1" reuse '.id = "reuse-7" | .evidence = "plan.md:3"'
  _finding "$R1" reuse '.id = "reuse-8" | .evidence = "plan.md:3"'
  run "$ADJ" "$R1" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | .reason]' "$R1/rejected.json")" = '["evidence_not_found","missing_command","missing_evidence","evidence_not_found","evidence_not_found","evidence_not_found","duplicate"]' ]
  [ "$(jq '.findings | length' "$R1/merged.json")" -eq 1 ]
}
@test "adjudicate: yield counts what each role originated and what survived" {
  _finding "$R1" reuse '.'
  _finding "$R1" reuse '.id = "reuse-2" | .command = "cat x"'
  run "$ADJ" "$R1" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.reuse == {originated: 2, survived: 1, fixed: 0} and .behaviour_edges.originated == 0' "$R1/yield.json"
}
@test "adjudicate: with --previous a finding not reported again is fixed, one whose reporter did not answer stays open" {
  _finding "$R1" reuse '.'
  _finding "$R1" behaviour_edges '.step = 2 | .claim = "another problem entirely here"'
  "$ADJ" "$R1" --project-root "$ROOT" >/dev/null
  _round "$R2" 2 reuse
  run "$ADJ" "$R2" --project-root "$ROOT" --previous "$R1"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.findings[] | select(.reported_by == ["reuse"]) | .status' "$R1/merged.json")" = fixed ]
  [ "$(jq -r '.findings[] | select(.reported_by == ["behaviour_edges"]) | .status' "$R1/merged.json")" = open ]
  [ "$(jq .reuse.fixed "$R1/yield.json")" -eq 1 ]
}
@test "adjudicate: a disputed status survives a rerun" {
  _finding "$R1" reuse '.'
  "$ADJ" "$R1" --project-root "$ROOT" >/dev/null
  jq '.findings[0].status = "disputed" | .findings[0].dispute = {reason: "wrong"}' "$R1/merged.json" > "$R1/m" && mv "$R1/m" "$R1/merged.json"
  "$ADJ" "$R1" --project-root "$ROOT" >/dev/null
  jq -e '.findings[0].status == "disputed" and .findings[0].dispute.reason == "wrong" and .blockers_open == 1' "$R1/merged.json"
}
@test "adjudicate: an unreadable round is exit 1" {
  run "$ADJ" "$ROOT/nowhere" --project-root "$ROOT"
  [ "$status" -eq 1 ]; [[ "$output" == *"cannot read"* ]]
}
@test "adjudicate: a symlink out of the project, ./.aid-worktrees and a line past the end are evidence_not_found" {
  ln -s / "$ROOT/scripts/lnk"
  _finding "$R1" reuse '.evidence = "scripts/lnk/etc/hostname:1"'
  _finding "$R1" reuse '.id = "reuse-2" | .evidence = "./.aid-worktrees/x/a.sh:1"'
  _finding "$R1" reuse '.id = "reuse-3" | .evidence = "scripts/a.sh:4"'
  run "$ADJ" "$R1" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | .reason]' "$R1/rejected.json")" = '["evidence_not_found","evidence_not_found","evidence_not_found"]' ]
}
@test "adjudicate: a minor finding is not marked fixed by a confirmation round that never saw it" {
  _finding "$R1" reuse '.severity = "minor"'
  "$ADJ" "$R1" --project-root "$ROOT" >/dev/null
  _round "$R2" 2 reuse
  "$ADJ" "$R2" --project-root "$ROOT" --previous "$R1" >/dev/null
  [ "$(jq -r '.findings[0].status' "$R1/merged.json")" = open ]
}
