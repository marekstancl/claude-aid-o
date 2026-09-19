#!/usr/bin/env bats
# aid-tier: t1
# test-review-adjudicate.bats — aid-review-adjudicate.sh on fixture rounds, for
# every checkpoint. The CP1 cases of test-plan-review-adjudicate.bats run here
# through the generic script with --namespace plan_review, asserting the
# fingerprints of the recorded fixture stay byte-identical; then the step
# cases: pre-image evidence, a sha outside the history, a repro/ command
# without its script, trace_missing, distinct namespaces, the line-stripped
# match, and the step check's own findings.
# Origin: P094 Step 5 (step review rebuild); the old suite goes in Step 14.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  ADJ_BIN="$AID_PLUGIN_PATH/scripts/aid-review-adjudicate.sh"
  ADJ() { local d="$1"; shift; "$ADJ_BIN" "$d" --namespace plan_review --plan "$d/packet/plan.md" "$@"; }
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
  run ADJ "$R1" --project-root "$ROOT"
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
  run ADJ "$R1" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | .reason]' "$R1/rejected.json")" = '["evidence_not_found","missing_command","missing_evidence","evidence_not_found","evidence_not_found","evidence_not_found","duplicate"]' ]
  [ "$(jq '.findings | length' "$R1/merged.json")" -eq 1 ]
}
@test "adjudicate: yield counts what each role originated and what survived" {
  _finding "$R1" reuse '.'
  _finding "$R1" reuse '.id = "reuse-2" | .command = "cat x"'
  run ADJ "$R1" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.reuse == {originated: 2, survived: 1, fixed: 0} and .behaviour_edges.originated == 0' "$R1/yield.json"
}
@test "adjudicate: with --previous a finding not reported again is fixed, one whose reporter did not answer stays open" {
  _finding "$R1" reuse '.'
  _finding "$R1" behaviour_edges '.step = 2 | .claim = "another problem entirely here"'
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  _round "$R2" 2 reuse
  run ADJ "$R2" --project-root "$ROOT" --previous "$R1"
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.findings[] | select(.reported_by == ["reuse"]) | .status' "$R1/merged.json")" = fixed ]
  [ "$(jq -r '.findings[] | select(.reported_by == ["behaviour_edges"]) | .status' "$R1/merged.json")" = open ]
  [ "$(jq .reuse.fixed "$R1/yield.json")" -eq 1 ]
}
@test "adjudicate: a disputed status survives a rerun" {
  _finding "$R1" reuse '.'
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  jq '.findings[0].status = "disputed" | .findings[0].dispute = {reason: "wrong"}' "$R1/merged.json" > "$R1/m" && mv "$R1/m" "$R1/merged.json"
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  jq -e '.findings[0].status == "disputed" and .findings[0].dispute.reason == "wrong" and .blockers_open == 1' "$R1/merged.json"
}
@test "adjudicate: an unreadable round is exit 1" {
  run ADJ "$ROOT/nowhere" --project-root "$ROOT"
  [ "$status" -eq 1 ]; [[ "$output" == *"cannot read"* ]]
}
@test "adjudicate: a symlink out of the project, ./.aid-worktrees and a line past the end are evidence_not_found" {
  ln -s / "$ROOT/scripts/lnk"
  _finding "$R1" reuse '.evidence = "scripts/lnk/etc/hostname:1"'
  _finding "$R1" reuse '.id = "reuse-2" | .evidence = "./.aid-worktrees/x/a.sh:1"'
  _finding "$R1" reuse '.id = "reuse-3" | .evidence = "scripts/a.sh:4"'
  run ADJ "$R1" --project-root "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | .reason]' "$R1/rejected.json")" = '["evidence_not_found","evidence_not_found","evidence_not_found"]' ]
}
@test "adjudicate: a minor finding is not marked fixed by a confirmation round that never saw it" {
  _finding "$R1" reuse '.severity = "minor"'
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  _round "$R2" 2 reuse
  ADJ "$R2" --project-root "$ROOT" --previous "$R1" >/dev/null
  [ "$(jq -r '.findings[0].status' "$R1/merged.json")" = open ]
}
@test "adjudicate: the same finding one line lower next round is not marked fixed; two claims at different lines stay two" {
  _finding "$R1" reuse '.evidence = "scripts/a.sh:2"'
  _finding "$R1" reuse '.id = "reuse-2" | .evidence = "scripts/a.sh:3"'
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  [ "$(jq '.findings | length' "$R1/merged.json")" -eq 2 ]
  _round "$R2" 2 reuse
  _finding "$R2" reuse '.evidence = "scripts/a.sh:3"'
  ADJ "$R2" --project-root "$ROOT" --previous "$R1" >/dev/null
  [ "$(jq '[.findings[] | select(.status == "open")] | length' "$R1/merged.json")" -eq 2 ]
}

# ── the generic script beside the CP1 one, and the step namespaces ──────────
_git_root() {  # turn $ROOT into a repository with two commits; prints the first sha
  git -C "$ROOT" init -q -b main; git -C "$ROOT" config user.email t@t; git -C "$ROOT" config user.name t
  git -C "$ROOT" add scripts/a.sh; git -C "$ROOT" commit -qm one; local first; first="$(git -C "$ROOT" rev-parse HEAD)"
  printf 'one\nthree\n' > "$ROOT/scripts/a.sh"; git -C "$ROOT" commit -qam two
  echo "$first"
}
_step_round() {  # <dir> <n> <roles...> — a collected step round (head_sha instead of plan_sha256)
  local dir="$1" n="$2"; shift 2
  mkdir -p "$dir/packet"
  jq -n --argjson n "$n" --arg h "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo x)" '{round: $n, head_sha: $h, reviewers_expected: $ARGS.positional}' --args "$@" > "$dir/round.json"
  jq -n '{valid: $ARGS.positional}' --args "$@" > "$dir/collect.json"
  local r; for r in "$@"; do jq -n --arg r "$r" '{role: $r, checkpoint: "cp2", findings: [], no_findings_reason: "none"}' > "$dir/reviewer-$r.json"; done
}
@test "cp1: the generic script's fingerprints and rejections are byte-identical to aid-plan-review-adjudicate.sh while it exists" {
  local old="$AID_PLUGIN_PATH/scripts/aid-plan-review-adjudicate.sh"
  [ -f "$old" ] || skip "the CP1-only adjudicator is gone (P094 Step 14)"
  _finding "$R1" reuse '.'
  _finding "$R1" reuse '.id = "reuse-2" | .step = 2 | .evidence = "scripts/a.sh:3; plan.md:2" | .claim = "a second claim with different words"'
  _finding "$R1" behaviour_edges '.severity = "major"'
  _finding "$R1" behaviour_edges '.id = "behaviour_edges-2" | .step = null | .evidence = "plan.md:1" | .claim = "plan level claim"'
  _finding "$R1" reuse '.id = "reuse-9" | .evidence = "scripts/missing.sh:1"'
  cp -r "$R1" "$ROOT/round-old"
  "$old" "$ROOT/round-old" --project-root "$ROOT" >/dev/null
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  diff <(jq -S '.findings | map({fingerprint, match, step, severity, reported_by, status})' "$ROOT/round-old/merged.json") \
       <(jq -S '.findings | map({fingerprint, match, step, severity, reported_by, status})' "$R1/merged.json")
  diff "$ROOT/round-old/rejected.json" "$R1/rejected.json"
  diff "$ROOT/round-old/yield.json" "$R1/yield.json"
}
@test "cp2: a pre-image evidence <sha>:path:line resolves; a sha outside the history and a line past the pre-image end do not" {
  local first; first="$(_git_root)"
  _step_round "$R2" 1 step_generalist
  _finding "$R2" step_generalist ".evidence = \"${first}:scripts/a.sh:2\""
  _finding "$R2" step_generalist ".id = \"step_generalist-2\" | .evidence = \"${first}:scripts/a.sh:5\""
  _finding "$R2" step_generalist '.id = "step_generalist-3" | .evidence = "0123456789ab:scripts/a.sh:1"'
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review
  [ "$status" -eq 0 ]
  [ "$(jq '.findings | length' "$R2/merged.json")" -eq 1 ]
  [ "$(jq -c '[.[] | .reason]' "$R2/rejected.json")" = '["evidence_not_found","evidence_not_found"]' ]
  [ "$(jq -r '.head_sha' "$R2/merged.json")" = "$(git -C "$ROOT" rev-parse HEAD)" ]
}
@test "cp2: a repro/ command is accepted only when its script exists under the round's repro/" {
  _git_root >/dev/null
  _step_round "$R2" 1 step_generalist
  _finding "$R2" step_generalist '.command = "bash repro/race-1.sh"'
  _finding "$R2" step_generalist '.id = "step_generalist-2" | .command = "bash repro/absent.sh" | .claim = "another claim about a race"'
  mkdir -p "$R2/repro"; echo 'true' > "$R2/repro/race-1.sh"
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | .reason]' "$R2/rejected.json")" = '["missing_command"]' ]
  [ "$(jq -r '.findings[0].command' "$R2/merged.json")" = "bash repro/race-1.sh" ]
}
@test "cp2: plan.md evidence is evidence_not_found without --plan; trace_missing fires only with a handler pattern, only for a generalist's blocker or major" {
  _git_root >/dev/null
  _step_round "$R2" 1 step_generalist step_security
  _finding "$R2" step_generalist '.evidence = "plan.md:1"'
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review
  [ "$(jq -c '[.[] | .reason]' "$R2/rejected.json")" = '["evidence_not_found"]' ]
  _step_round "$R2" 1 step_generalist step_security
  _finding "$R2" step_generalist '.'
  _finding "$R2" step_generalist '.id = "step_generalist-2" | .severity = "minor" | .claim = "a minor thing elsewhere"'
  _finding "$R2" step_security '.'
  jq -n '{handler_patterns: ["http_route_decorator"], script_findings: []}' > "$ROOT/sc.json"
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review --step-check "$ROOT/sc.json"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | select(.reason == "trace_missing") | .role]' "$R2/rejected.json")" = '["step_generalist"]' ]
  [ "$(jq '.findings | length' "$R2/merged.json")" -eq 2 ]
  _finding "$R2" step_generalist '.id = "step_generalist-4" | .claim = "traced claim about the handler" | .behaviour_trace = [{request: "POST /x", path: "a", sink: "b", branches: [{name: "ok", outcome: "200"}]}]'
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review --step-check "$ROOT/sc.json"
  jq -e '.findings[] | select(.claim | startswith("traced")) | .behaviour_trace | length == 1' "$R2/merged.json"
  jq -n '{handler_patterns: [], script_findings: []}' > "$ROOT/sc.json"
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review --step-check "$ROOT/sc.json"
  [ "$(jq -c '[.[] | select(.reason == "trace_missing")] | length' "$R2/rejected.json")" = 0 ]
}
@test "namespaces: the same claim is a different fingerprint at cp1 and cp2; a cp2 match is the fingerprint without the line; cp3 uses the literal epic" {
  _git_root >/dev/null
  _finding "$R1" reuse '.'
  ADJ "$R1" --project-root "$ROOT" >/dev/null
  _step_round "$R2" 1 step_generalist
  _finding "$R2" step_generalist '.'
  "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review >/dev/null
  [ "$(jq -r '.findings[0].fingerprint' "$R1/merged.json")" != "$(jq -r '.findings[0].fingerprint' "$R2/merged.json")" ]
  source "$AID_PLUGIN_PATH/scripts/lib/aid-finding-fingerprint.sh"
  local key="step one reads a file nothing writes"
  [ "$(jq -r '.findings[0].fingerprint' "$R2/merged.json")" = "$(fingerprint "$(basename "$ROOT")" step_review 1 scripts/a.sh:2 "$key")" ]
  [ "$(jq -r '.findings[0].match' "$R2/merged.json")" = "$(fingerprint "$(basename "$ROOT")" step_review 1 scripts/a.sh "$key")" ]
  R3="$ROOT/round-3"; _step_round "$R3" 1 epic_generalist
  _finding "$R3" epic_generalist '.step = null'
  "$ADJ_BIN" "$R3" --project-root "$ROOT" --namespace epic_review >/dev/null
  [ "$(jq -r '.findings[0].fingerprint' "$R3/merged.json")" = "$(fingerprint "$(basename "$ROOT")" epic_review epic scripts/a.sh:2 "$key")" ]
}
@test "cp2: the step check's own forbidden-path finding enters the list as role step_check without a command" {
  _git_root >/dev/null
  _step_round "$R2" 1 step_generalist
  jq -n '{handler_patterns: [], script_findings: [{id: "step_check-forbidden", checkpoint: "cp2", severity: "blocker", role: "step_check", claim: "the diff touches a forbidden path: secrets/key.txt", evidence: "secrets/key.txt:0", command: "git diff --name-only -- secrets/key.txt", fix: "revert"}]}' > "$ROOT/sc.json"
  run "$ADJ_BIN" "$R2" --project-root "$ROOT" --namespace step_review --step-check "$ROOT/sc.json"
  [ "$status" -eq 0 ]
  jq -e '.findings[0] | .reported_by == ["step_check"] and .severity == "blocker"' "$R2/merged.json"
  [ "$(jq .blockers_open "$R2/merged.json")" -eq 1 ]
}
@test "usage: a missing or unknown namespace is exit 2" {
  run "$ADJ_BIN" "$R1" --project-root "$ROOT"; [ "$status" -eq 2 ]
  run "$ADJ_BIN" "$R1" --project-root "$ROOT" --namespace cp9; [ "$status" -eq 2 ]
}
