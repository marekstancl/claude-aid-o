#!/usr/bin/env bats
# aid-tier: t1
# test-review-round.bats — aid-review-round.sh on small fixture trees, for every
# checkpoint. The CP1 cases of test-plan-review-round.bats run here through the
# generic engine (the plan passed as before); then the step cases: a round from
# a step check at HEAD, the confirmation packet, close bound to HEAD, to a
# token value per claude role and to a recorded dispatch bracket, the stub
# flag, the codex-absent degraded path, retry and override, cp6.
# Origin: P094 Step 6 (step review rebuild); the old suite goes in Step 14.

load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  ROUND_SH="$AID_PLUGIN_PATH/scripts/aid-review-round.sh"
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
# --version and the probe's one-token prompt: what aid_codex_probe asks before
# a real dispatch is paid for.
[[ "$1" == --version ]] && { echo "codex-cli 9.9.9"; exit 0; }
[[ "${*: -1}" == ok ]] && exit 0
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
@test "dispatch: with no codex reachable, the CP1 role generalist_b is stood in for by claude" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  jq -n '{available: false, binary: "", version: "", reason: "codex_absent", probed_at: "2026-09-20T00:00:00Z"}' > "$ROOT/probe.json"
  AID_CODEX_PROBE_STUB="$ROOT/probe.json" run "$ROUND_SH" dispatch "$PLAN" --round 1 --provider codex --role generalist_b
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"STAND-IN"* ]]; [[ "$output" == *opus* ]]
  [ "$(jq -r '.fallback' "$CP1/round-1/codex-generalist_b.usage.json")" = claude ]
  _answer_all; _answer generalist_b '.provider = "claude"'
  run "$ROUND_SH" collect "$PLAN" --round 1
  echo "$output"; [ "$status" -eq 0 ]
  jq -e '.valid | index("generalist_b")' "$CP1/round-1/collect.json"
}
@test "dispatch: a claude role is refused naming the controller instruction" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  run "$ROUND_SH" dispatch "$PLAN" --round 1 --provider codex --role reuse
  [ "$status" -eq 1 ]; [[ "$output" == *"aid-review-adapter-claude.md"* ]]
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

# _round1_closed [answer-filter-for-reuse] — round 1 prepared, answered, collected, closed
_round1_closed() {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer_all; _answer reuse "${1:-.findings[0].severity = \"blocker\"}"
  "$ROUND_SH" collect "$PLAN" --round 1 >/dev/null
  "$ROUND_SH" close "$PLAN" --round 1 --tokens generalist_a=100 behaviour_edges=100 feasibility_deps=100 reuse=100 enforcement_tests=unknown >/dev/null
}

@test "close: refused without a value for an expected claude role; unknown is written as the string" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer_all
  "$ROUND_SH" collect "$PLAN" --round 1 >/dev/null
  run "$ROUND_SH" close "$PLAN" --round 1 --tokens generalist_a=100
  [ "$status" -eq 1 ]; [[ "$output" == *"no --tokens value for behaviour_edges"* ]]
  run "$ROUND_SH" close "$PLAN" --round 1 --tokens generalist_a=100 behaviour_edges=1 feasibility_deps=1 reuse=1 enforcement_tests=unknown
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.reviewers.enforcement_tests.tokens' "$CP1/round-1/measurement.json")" = unknown ]
  [ "$(jq -r '.reviewers.generalist_b | "\(.provider) \(.tokens) \(.reason)"' "$CP1/round-1/measurement.json")" = "codex unknown null" ]
  run "$ROUND_SH" close "$PLAN" --round 1 --tokens generalist_a=5
  [ "$status" -eq 1 ]; [[ "$output" == *"already closed"* ]]
  run "$ROUND_SH" close "$PLAN" --round 1 --tokens enforcement_tests=77
  [ "$status" -eq 0 ]; [ "$(jq '.reviewers.enforcement_tests.tokens' "$CP1/round-1/measurement.json")" -eq 77 ]
}
@test "fix-check: a fix that adds a Files entry outside the fix list fails, and prepare --round 2 quotes it" {
  _round1_closed
  sed -i 's/^text$/text\n\n- Create: `scripts\/new.sh` — more/' "$PLAN"; _check
  run "$ROUND_SH" fix-check "$PLAN" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"Step 2 (file)"* ]]
  [ "$(jq -r .pass "$CP1/round-1/fix-diff.json")" = false ]
  run "$ROUND_SH" prepare "$PLAN" --round 2
  [ "$status" -eq 1 ]; [[ "$output" == *"scripts/new.sh"* ]]
}
@test "fix-check: only plan-level findings run with --fixes none and pass when nothing changed" {
  _round1_closed
  jq '.findings[].step = null' "$CP1/round-1/merged.json" > "$ROOT/m" && mv "$ROOT/m" "$CP1/round-1/merged.json"
  run "$ROUND_SH" fix-check "$PLAN" --round 1
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .fix_list "$CP1/round-1/fix-diff.json")" = none ]
}
@test "override: rounds 3 is recorded with six keys and lets round 3 be prepared; a second override is refused" {
  run "$ROUND_SH" override "$PLAN" --rounds 3 --reason "PM: send a third round, please"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'keys' "$CP1/override.json")" = '["at","by","plan_sha256_at_issue","reason","recorded_by","rounds"]' ]
  run "$ROUND_SH" override "$PLAN" --rounds 1 --reason "PM: actually only one round"
  [ "$status" -eq 1 ]; [[ "$output" == *"already exists"* ]]
}
@test "override: rounds 1 before round 1 is closed, and a short reason, are refused" {
  run "$ROUND_SH" override "$PLAN" --rounds 1 --reason "PM: one round is enough here"
  [ "$status" -eq 1 ]; [[ "$output" == *"after round 1 is closed"* ]]
  run "$ROUND_SH" override "$PLAN" --rounds 3 --reason "short"
  [ "$status" -eq 2 ]
}
@test "close, dispute, finalize in order; finalize accepts AC additions, refuses a new file; dispute after finalize is refused" {
  _round1_closed
  fp="$(jq -r '.findings[] | select(.severity == "blocker") | .fingerprint' "$CP1/round-1/merged.json" | head -1)"
  run "$ROUND_SH" dispute "$PLAN" --round 1 --fingerprint "$fp" --reason "the reviewer misread step one entirely"
  [ "$status" -eq 0 ]; [[ "$output" == *disputed* ]]
  [ "$(jq .blockers_open "$CP1/round-1/merged.json")" -ge 1 ]
  printf '\n**Acceptance Criteria:**\n- [ ] step two quotes the open blocker\n' >> "$PLAN"
  run "$ROUND_SH" finalize "$PLAN"
  echo "$output"; [ "$status" -eq 0 ]; [ -f "$CP1/round-1/plan-final.md" ]
  run "$ROUND_SH" dispute "$PLAN" --round 1 --fingerprint "$fp" --reason "another dispute after finalize"
  [ "$status" -eq 1 ]; [[ "$output" == *"plan-final.md"* ]]
  printf -- '- Create: `scripts/other.sh` — x\n' >> "$PLAN"
  run "$ROUND_SH" finalize "$PLAN"
  [ "$status" -eq 1 ]; [[ "$output" == *"outside the fix list"* ]]
}
@test "dispute: the PM's accepted answer closes a disputed blocker" {
  _round1_closed
  fp="$(jq -r '.findings[] | select(.severity == "blocker") | .fingerprint' "$CP1/round-1/merged.json" | head -1)"
  "$ROUND_SH" dispute "$PLAN" --round 1 --fingerprint "$fp" --reason "the reviewer misread step one entirely" >/dev/null
  run "$ROUND_SH" dispute "$PLAN" --round 1 --fingerprint "$fp" --pm accepted --reason "PM: agreed, the finding is wrong"
  [ "$status" -eq 0 ]
  jq -e --arg f "$fp" '.findings[] | select(.fingerprint == $f) | .status == "fixed" and .dispute.pm.answer == "accepted"' "$CP1/round-1/merged.json"
}
@test "close: an invalid round is refused, so retry stays possible" {
  "$ROUND_SH" prepare "$PLAN" --round 1 >/dev/null
  _answer generalist_a
  "$ROUND_SH" collect "$PLAN" --round 1 >/dev/null 2>&1 || true
  run "$ROUND_SH" close "$PLAN" --round 1 --tokens generalist_a=1 behaviour_edges=1 feasibility_deps=1 reuse=1 enforcement_tests=1
  [ "$status" -eq 1 ]; [[ "$output" == *"invalid"* ]]
  run "$ROUND_SH" retry "$PLAN" --round 1 --role reuse
  [ "$status" -eq 0 ]
}
@test "prepare: the confirmation round asks the reporter of an open major on an unchanged step" {
  _round1_closed '.findings[0].severity = "major" | .findings[0].step = null'
  "$ROUND_SH" fix-check "$PLAN" --round 1 >/dev/null
  run "$ROUND_SH" prepare "$PLAN" --round 2
  [ "$status" -eq 0 ]
  [ "$(jq '.reviewers_expected | length' "$CP1/round-2/round.json")" -gt 0 ]
}
@test "dispute: allowed again once the plan was edited after finalize" {
  _round1_closed
  fp="$(jq -r '.findings[0].fingerprint' "$CP1/round-1/merged.json")"
  "$ROUND_SH" finalize "$PLAN" >/dev/null
  printf '\nmore\n' >> "$PLAN"
  run "$ROUND_SH" dispute "$PLAN" --round 1 --fingerprint "$fp" --reason "a reason that is long enough here"
  [ "$status" -eq 0 ]
}
@test "prepare: a confirmation-round prompt carries the open findings and the fix diff" {
  _round1_closed
  sed -i 's/^text$/text changed by the fix/' "$PLAN"; _check
  "$ROUND_SH" fix-check "$PLAN" --round 1 >/dev/null
  "$ROUND_SH" prepare "$PLAN" --round 2 >/dev/null
  local p="$CP1/round-2/prompt-reuse.md"
  grep -q '^## This is a confirmation round$' "$p"
  grep -q 'step one misses reuse' "$p"
  grep -q '^+text changed by the fix$' "$p"
}

# ── step rounds (cp2, cp3, cp6) ────────────────────────────────────────────
# _repo — a fixture repository with a step-0 diff that needs review (2 files, > 50 lines),
# plan.json, fsm-state.yaml and an empty timeline; sets R (repo) and E (run evidence dir)
_repo() {
  R="$ROOT/repo"; E="$ROOT/run"; mkdir -p "$R/src" "$R/secrets" "$E"
  git -C "$ROOT" init -q "$R" >/dev/null; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  echo base > "$R/src/app.py"; echo k > "$R/secrets/key.txt"; git -C "$R" add -A; git -C "$R" commit -qm base
  printf 'base_commit: %s\nstreamlined_mode: false\n' "$(git -C "$R" rev-parse HEAD)" > "$E/fsm-state.yaml"
  jq -n '{steps: [{id: "s0", role: "backend", objective: "add the thing", acceptance_criteria: ["it works"], outputs: ["Modify: `src/app.py` — x", "Create: `src/new.py` — y"], forbidden_paths: ["secrets/**"]}]}' > "$E/plan.json"
  : > "$E/timeline.jsonl"
  seq 1 60 >> "$R/src/app.py"; echo new > "$R/src/new.py"; git -C "$R" add -A; git -C "$R" commit -qm s0
}
_sc() { (cd "$R" && bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint "${1:-cp2}" --step "${2:-0}" --evidence-dir "$E" "${@:3}") >/dev/null; }
_S() { "$ROUND_SH" "$1" --checkpoint cp2 --evidence-dir "$E" --step 0 --project-root "$R" "${@:2}"; }
D() { printf '%s/cp2/step-0/round-%s' "$E" "$1"; }
# _sanswer <round> <role> [jq filter] — a valid one-finding cp2 answer
_sanswer() {
  jq -n --arg r "$2" '{role: $r, checkpoint: "cp2", findings: [{id: "\($r)-1", checkpoint: "cp2", step: 0, severity: "major",
      claim: "the new file is never imported by \($r)", command: "grep -n new src/app.py", evidence: "src/app.py:3", fix: "import it"}]}' \
    | jq "${3:-.}" > "$(D "$1")/reviewer-$2.json"
}
# _bracket <round> <role> — the dispatch bracket the controller records for a claude role
_bracket() {
  local d; d="$(D "$1")"; local f="cp2-step-0-${2//_/-}"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus "$f" --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus "$f" --output-file "$d/reviewer-$2.json" --evidence-dir "$d" >/dev/null
}

@test "step: prepare needs a step check at HEAD and a review verdict; one prompt for review, two for review+security" {
  _repo
  run _S prepare --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"no step-check.json"* ]]
  _sc
  run _S prepare --round 1
  echo "$output"; [ "$status" -eq 0 ]
  [ "$(ls "$(D 1)"/prompt-*.md | wc -l)" -eq 1 ]
  [ "$(jq -r .head_sha "$(D 1)/round.json")" = "$(git -C "$R" rev-parse HEAD)" ]
  [ "$(jq -r .confirmation_of "$(D 1)/round.json")" = null ]
  [ "$(jq '.files | length' "$(D 1)/packet/manifest.json")" -eq 4 ]
  grep -q '^# cp2 review, round 1$' "$(D 1)/prompt-step_generalist.md"
  grep -q 'the new file is never\|Definition of Done' "$(D 1)/prompt-step_generalist.md"
  [[ "$output" == *"focus cp2-step-0-step-generalist"* ]]
  jq -e 'select(.event == "review_round_start")' "$E/timeline.jsonl" | grep -q .
  [ "$(jq -r '.rounds | length' "$E/cp2/step-0/rounds.json")" -eq 1 ]
  # a security match adds the second role
  printf 'import subprocess\nsubprocess.run(x, shell=True)\n' >> "$R/src/app.py"; git -C "$R" commit -qam sec
  rm -rf "$E/cp2"; _sc
  run _S prepare --round 1; [ "$status" -eq 0 ]
  [ "$(ls "$(D 1)"/prompt-*.md | wc -l)" -eq 2 ]
  [ "$(jq '.min_answers_effective' "$(D 1)/round.json")" -eq 2 ]
}
@test "step: a stale step check, a skip verdict and a second prepare are refused; a packet without round.json is re-prepared" {
  _repo; _sc
  echo more >> "$R/src/app.py"; git -C "$R" commit -qam moved
  run _S prepare --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"stale"* ]]
  _sc
  _S prepare --round 1 >/dev/null
  run _S prepare --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"already prepared"* ]]
  rm "$(D 1)/round.json"
  run _S prepare --round 1; [ "$status" -eq 0 ]
  # a skip verdict has no round
  rm -rf "$E/cp2"; git -C "$R" checkout -q -- .; printf 'base_commit: %s\n' "$(git -C "$R" rev-parse HEAD)" > "$E/fsm-state.yaml"
  echo tiny >> "$R/src/app.py"; git -C "$R" commit -qam tiny; _sc
  run _S prepare --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"verdict is skip"* ]]
}
@test "step: collect needs every expected role; close is bound to HEAD, to a token value and to a dispatch bracket; verdict fail with an open major" {
  _repo; printf 'import subprocess\nsubprocess.run(x, shell=True)\n' >> "$R/src/app.py"; git -C "$R" commit -qam sec; _sc
  _S prepare --round 1 >/dev/null
  _sanswer 1 step_generalist
  run _S collect --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"1 of 2 answered (min 2)"* ]]
  _sanswer 1 step_security '.findings = [] | .no_findings_reason = "fixture only"'
  run _S collect --round 1; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq .blockers_open "$(D 1)/merged.json")" -eq 0 ]
  run _S close --round 1 --tokens step_generalist=10 step_security=5
  [ "$status" -eq 1 ]; [[ "$output" == *no_dispatch_record* ]]
  _bracket 1 step_generalist; _bracket 1 step_security
  run _S close --round 1 --tokens step_generalist=10
  [ "$status" -eq 1 ]; [[ "$output" == *"no --tokens value for step_security"* ]]
  run env AID_REVIEW_DISPATCH_STUB=1 "$ROUND_SH" close --checkpoint cp2 --evidence-dir "$E" --step 0 --project-root "$R" --round 1 --tokens step_generalist=10 step_security=5
  [ "$status" -eq 0 ]
  [ "$(jq -r .verdict "$(D 1)/measurement.json")" = fail ]
  [ "$(jq -r .dispatch_check "$(D 1)/measurement.json")" = recorded ]
  [ "$(jq -r .verdict "$E/cp2/step-0/rounds.json")" = fail ]
  [ "$(jq -r '.rounds[0].verdict' "$E/cp2/step-0/rounds.json")" = fail ]
  [ "$(jq -r '.closed_at != null and .routed_at != null' "$(D 1)/round.json")" = true ]
  run _S close --round 1 --tokens step_generalist=11; [ "$status" -eq 1 ]; [[ "$output" == *"already closed"* ]]
  run _S retry --round 1 --role step_security; [ "$status" -eq 1 ]
  # HEAD moved before close → refused
  rm -rf "$E/cp2"; _sc; _S prepare --round 1 >/dev/null; _sanswer 1 step_generalist; _sanswer 1 step_security '.findings = [] | .no_findings_reason = "x"'
  _S collect --round 1 >/dev/null; _bracket 1 step_generalist; _bracket 1 step_security
  echo later >> "$R/src/app.py"; git -C "$R" commit -qam later
  run _S close --round 1 --tokens step_generalist=1 step_security=1
  [ "$status" -eq 1 ]; [[ "$output" == *"head moved during round"* ]]
}
@test "step: the confirmation round asks only the reporters of what stayed open and shows them the open findings and the fix diff; pass closes the index" {
  _repo; _sc; _S prepare --round 1 >/dev/null
  _sanswer 1 step_generalist; _S collect --round 1 >/dev/null; _bracket 1 step_generalist
  _S close --round 1 --tokens step_generalist=10 >/dev/null
  run _S prepare --round 2; [ "$status" -eq 1 ]; [[ "$output" == *"HEAD has not moved"* ]]
  echo "import new" >> "$R/src/app.py"; git -C "$R" commit -qam "fix(review): import"
  _sc
  run _S prepare --round 2; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .confirmation_of "$(D 2)/round.json")" = round-1 ]
  [ "$(jq -c .reviewers_expected "$(D 2)/round.json")" = '["step_generalist"]' ]
  [ -f "$(D 2)/packet/open-findings.json" ] && [ -f "$(D 2)/packet/fix.patch" ]
  grep -q 'This is a confirmation round' "$(D 2)/prompt-step_generalist.md"
  grep -q 'import new' "$(D 2)/packet/fix.patch"
  _sanswer 2 step_generalist '.findings = [] | .no_findings_reason = "fixed"'
  _S collect --round 2 >/dev/null; _bracket 2 step_generalist
  run _S close --round 2 --tokens step_generalist=7 --fixer backend=opus:100:20
  [ "$status" -eq 0 ]
  [ "$(jq -r .verdict "$E/cp2/step-0/rounds.json")" = pass ]
  [ "$(jq -r '.findings[0].status' "$(D 1)/merged.json")" = fixed ]
  [ "$(jq -r '.fixer.model' "$(D 2)/measurement.json")" = opus ]
  run _S prepare --round 3; [ "$status" -eq 1 ]; [[ "$output" == *"override.json"* ]]
}
@test "step: a stub round skips the dispatch check and records it; the flag comes from prepare, never from the environment" {
  _repo; _sc; _S prepare --round 1 --stub >/dev/null
  [ "$(jq -r .stub "$(D 1)/round.json")" = true ]
  _sanswer 1 step_generalist; _S collect --round 1 >/dev/null
  run _S close --round 1 --tokens step_generalist=1
  [ "$status" -eq 0 ]; [[ "$output" == *"stub"* ]]
  [ "$(jq -r .dispatch_check "$(D 1)/measurement.json")" = stubbed ]
  [ "$(jq -r .dispatch_check "$E/cp2/step-0/rounds.json")" = stubbed ]
}
# _codex_role — a cp2 config of one claude generalist and one codex security role
_codex_role() {
  mkdir -p "$R/.aid-o/config/policies"
  cp "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" "$R/.aid-o/config/policies/review-checkpoints.yaml"
  yq -i '.review_checkpoints.step_review.reviewers = [{"role":"step_generalist","provider":"claude","model":"opus"},{"role":"step_security","provider":"codex","model":"gpt-5"}]' "$R/.aid-o/config/policies/review-checkpoints.yaml"
}
# _probe <available> [reason] — the canned probe result the dispatch reads
_probe() {
  jq -n --argjson a "$1" --arg r "${2:-none}" \
    '{available: $a, binary: "/usr/bin/codex", version: "9.9.9", reason: $r, probed_at: "2026-09-20T00:00:00Z"}' > "$ROOT/probe.json"
  export AID_CODEX_PROBE_STUB="$ROOT/probe.json"
}

@test "step: a codex role no codex can answer is stood in for by claude, and the round closes undegraded" {
  _repo; _sc; _codex_role
  _S prepare --round 1 >/dev/null
  [ "$(jq '.reviewers_expected | length' "$(D 1)/round.json")" -eq 2 ]
  _probe false rate_limited
  run "$ROUND_SH" dispatch --checkpoint cp2 --evidence-dir "$E" --step 0 --project-root "$R" --round 1 --provider codex --role step_security
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"STAND-IN"* ]]; [[ "$output" == *sonnet* ]]
  [ "$(jq -r '.fallback' "$(D 1)/codex-step_security.usage.json")" = claude ]

  # a stand-in that was asked for and never dispatched does not close the round
  _sanswer 1 step_generalist
  run _S collect --round 1; [ "$status" -eq 1 ]
  [ "$(jq -c .missing "$(D 1)/collect.json")" = '["step_security"]' ]

  _sanswer 1 step_security '.provider = "claude"'
  _S collect --round 1 >/dev/null
  [ "$(jq -c .valid "$(D 1)/collect.json")" = '["step_generalist","step_security"]' ]
  _bracket 1 step_generalist; _bracket 1 step_security
  run _S close --round 1 --tokens step_generalist=3 step_security=7; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .degraded "$(D 1)/measurement.json")" = false ]
  [ "$(jq -r '.reviewers.step_security | "\(.provider) \(.model) \(.tokens) \(.fallback_reason)"' "$(D 1)/measurement.json")" = "claude sonnet 7 rate_limited" ]
}

@test "step: a claude answer for a codex role without a stand-in record is unexpected_provider" {
  _repo; _sc; _codex_role
  _S prepare --round 1 >/dev/null
  _sanswer 1 step_generalist; _sanswer 1 step_security '.provider = "claude"'
  run _S collect --round 1; [ "$status" -eq 1 ]
  [[ "$(jq -r '.invalid[0].reason' "$(D 1)/collect.json")" == unexpected_provider* ]]
}

@test "step: retry on a stood-in role keeps the record so the retried answer is not a stranger" {
  _repo; _sc; _codex_role
  _S prepare --round 1 >/dev/null
  _probe false codex_absent
  "$ROUND_SH" dispatch --checkpoint cp2 --evidence-dir "$E" --step 0 --project-root "$R" --round 1 --provider codex --role step_security >/dev/null
  _sanswer 1 step_generalist; _sanswer 1 step_security '.provider = "claude" | .findings[0].severity = "critical"'
  _S collect --round 1 || true
  run _S retry --round 1 --role step_security
  echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"STAND-IN"* ]]
  [ "$(jq -r '.fallback' "$(D 1)/codex-step_security.usage.json")" = claude ]
  [ ! -f "$(D 1)/reviewer-step_security.json" ]
}

@test "step: a legacy record with no stand-in still counts as provider_absent and closes degraded" {
  _repo; _sc; _codex_role
  _S prepare --round 1 >/dev/null
  # the shape dispatch wrote before P095: no fallback key
  jq -n '{answered: false, reason: "rate_limited"}' > "$(D 1)/codex-step_security.usage.json"
  _sanswer 1 step_generalist; _S collect --round 1 >/dev/null
  [ "$(jq -c .provider_absent "$(D 1)/collect.json")" = '["step_security"]' ]
  _bracket 1 step_generalist
  run _S close --round 1 --tokens step_generalist=3; [ "$status" -eq 0 ]
  [ "$(jq -r .degraded "$(D 1)/measurement.json")" = true ]
  [ "$(jq -r '.reviewers.step_security.reason' "$(D 1)/measurement.json")" = rate_limited ]
}
@test "step: override --rounds 3 records the head sha and unlocks round 3; the dispatch ledger keeps two steps apart" {
  _repo; _sc
  run _S override --rounds 3 --reason "PM: run a third round on this step"
  [ "$status" -eq 0 ]; [ "$(jq -r .head_sha_at_issue "$E/cp2/step-0/override.json")" = "$(git -C "$R" rev-parse HEAD)" ]
  local d="$ROOT/ledger"; mkdir -p "$d"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus cp2-step-1-step-generalist --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus cp2-step-2-step-generalist --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  echo x > "$d/reviewer-step_generalist.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus cp2-step-2-step-generalist --output-file "$d/reviewer-step_generalist.json" --evidence-dir "$d" >/dev/null
  [ "$(jq -r 'select(.event == "verifier_dispatch_start") | .step_n' "$d/timeline.jsonl" | tr '\n' ' ')" = "1 2 " ]
  [ "$(jq -r '.focus' "$d/pending-dispatches.jsonl")" = cp2-step-1-step-generalist ]
  run bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus cp2-step-1 --agent-id aid-orchestrator:review --evidence-dir "$d"
  [ "$status" -eq 1 ]
}
@test "cp6: a round is prepared under the fast-mode evidence dir from a worktree step check; fix-check is refused for step rounds" {
  _repo; D6="$ROOT/do"; mkdir -p "$D6"; : > "$D6/timeline.jsonl"
  seq 1 60 >> "$R/src/app.py"; echo "Task: tidy" > "$ROOT/task.txt"
  (cd "$R" && bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp6 --evidence-dir "$D6" --dod-file "$ROOT/task.txt") >/dev/null
  run "$ROUND_SH" prepare --checkpoint cp6 --evidence-dir "$D6" --project-root "$R" --round 1
  echo "$output"; [ "$status" -eq 0 ]
  [ -f "$D6/cp6/round-1/prompt-step_generalist.md" ]
  grep -q 'Task: tidy' "$D6/cp6/round-1/packet/dod.md"
  [[ "$output" == *"focus cp6-step-generalist"* ]]
  run "$ROUND_SH" fix-check --checkpoint cp6 --evidence-dir "$D6" --project-root "$R" --round 1
  [ "$status" -eq 2 ]; [[ "$output" == *"plan-review (CP1) subcommand"* ]]
}

# ── Step 7: what stays open after the last round, and the cp3 semantic file ──
# _erepo — like _repo, but the run lives under evidence/E-900-1_2/R-1 so the
# round knows its EPIC and plan (P900); a second step covers src/later.py.
_erepo() {
  _repo
  E="$ROOT/ev/E-900-1_2/R-1"; mkdir -p "$E"
  printf 'base_commit: %s\nstreamlined_mode: false\n' "$(git -C "$R" rev-parse HEAD~1)" > "$E/fsm-state.yaml"
  jq -n '{steps: [{id: "s0", role: "backend", objective: "add the thing", acceptance_criteria: ["it works"], outputs: ["Modify: `src/app.py` — x", "Create: `src/new.py` — y"], allowed_paths: ["src/app.py", "src/new.py"]},
                  {id: "s1", role: "backend", objective: "later", outputs: ["Modify: `src/new.py` — z"], allowed_paths: ["src/new.py"]}]}' > "$E/plan.json"
  : > "$E/timeline.jsonl"
  # cp3 with one claude role and one round, so the last round is round 1 and no codex launcher is needed
  mkdir -p "$R/.aid-o/config/policies"
  yq '.review_checkpoints.epic_review.rounds_default = 1 | .review_checkpoints.epic_review.reviewers = [{"role":"epic_generalist","provider":"claude","model":"opus"}]' \
     "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" > "$R/.aid-o/config/policies/review-checkpoints.yaml"
}
_J() { printf '%s/.aid-o/work/plan-state/P900/%s' "$R" "$1"; }
# _close1 <checkpoint> [answer jq] — one round: prepare, one generalist answer, bracket, collect, close
_close1() {
  local cp="$1" role=step_generalist f="cp2-step-0-step-generalist"; [[ "$cp" == cp3 ]] && { role=epic_generalist; f="cp3-epic-generalist"; }
  local args=(--checkpoint "$cp" --evidence-dir "$E" --project-root "$R"); [[ "$cp" == cp2 ]] && args+=(--step 0)
  "$ROUND_SH" prepare "${args[@]}" --round "${ROUND_N:-1}" >/dev/null || return 1
  local d="$E/${cp}$([[ "$cp" == cp2 ]] && echo /step-0)/round-${ROUND_N:-1}"
  jq -n --arg r "$role" --arg cp "$cp" '{role: $r, checkpoint: $cp, findings: [
      {id: "g-1", checkpoint: $cp, step: 0, severity: "blocker", claim: "app never imports new", command: "grep -n new src/app.py", evidence: "src/app.py:3", fix: "import it"},
      {id: "g-2", checkpoint: $cp, step: 0, severity: "major", claim: "new.py contract unmet", command: "grep -n new src/new.py", evidence: "src/new.py:1", fix: "finish it"},
      {id: "g-3", checkpoint: $cp, step: 0, severity: "minor", claim: "naming", command: "grep -n x src/new.py", evidence: "src/new.py:1", fix: "rename"}]}' \
    | jq "${2:-.}" > "$d/reviewer-${role}.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus "$f" --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus "$f" --output-file "$d/reviewer-${role}.json" --evidence-dir "$d" >/dev/null
  "$ROUND_SH" collect "${args[@]}" --round "${ROUND_N:-1}" >/dev/null || return 1
  "$ROUND_SH" close "${args[@]}" --round "${ROUND_N:-1}" --tokens ${role}=5
}
@test "routing: close of the last cp2 round routes the uncovered blocker, carries the major a later step covers, and a second close adds nothing" {
  _erepo; _sc
  # round 1 of rounds_default 2: nothing is written yet
  run _close1 cp2; echo "$output"; [ "$status" -eq 0 ]
  [ ! -f "$(_J routed-findings.jsonl)" ]
  echo "import new" >> "$R/src/app.py"; git -C "$R" commit -qam "fix(review): partial"; _sc
  ROUND_N=2 run _close1 cp2; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"1 carried, 1 routed"* ]]
  local fp_a fp_b
  fp_a="$(jq -r '.findings[] | select(.claim | startswith("app never")) | .fingerprint' "$(D 2)/merged.json")"
  fp_b="$(jq -r '.findings[] | select(.claim | startswith("new.py")) | .fingerprint' "$(D 2)/merged.json")"
  [ "$(jq -r --arg f "$fp_a" '.findings[] | select(.fingerprint == $f) | .status' "$(D 2)/merged.json")" = routed ]
  [ "$(jq -r --arg f "$fp_b" '.findings[] | select(.fingerprint == $f) | .status' "$(D 2)/merged.json")" = carried ]
  # the journal reader sees the route to this EPIC; the obligation is a followup
  run bash -c "cd '$R' && source '$AID_PLUGIN_PATH/scripts/lib/aid-routed-findings.sh' && aid_finding_open_for_epic P900 E-900-1_2"
  [ "$status" -eq 0 ]; [[ "$output" == "${fp_a}"$'\t'"cp2"$'\t'"epic:E-900-1_2" ]]
  [ "$(jq -r 'select(.op == "add") | .severity' "$(_J carried-obligations.jsonl)")" = followup ]
  grep -qF "$fp_b" "$(_J carried-obligations.jsonl)"
  [ "$(wc -l < "$(_J routed-findings.jsonl)")" -eq 1 ]
  # an interrupted close (no measurement.json, no closed_at) is run again: no second entry
  jq 'del(.closed_at, .routed_at)' "$(D 2)/round.json" > "$(D 2)/r.tmp" && mv "$(D 2)/r.tmp" "$(D 2)/round.json"; rm "$(D 2)/measurement.json"
  run "$ROUND_SH" close --checkpoint cp2 --evidence-dir "$E" --step 0 --project-root "$R" --round 2 --tokens step_generalist=5
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$(_J routed-findings.jsonl)")" -eq 1 ]
  [ "$(grep -c '"op":"add"' "$(_J carried-obligations.jsonl)")" -eq 1 ]
}
@test "routing: the last cp3 round routes every open blocker or major to the EPIC; a run of no plan and fast mode leave them open and say so" {
  _erepo; _sc cp3 ""
  run _close1 cp3; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"2 routed"* ]]
  [ "$(wc -l < "$(_J routed-findings.jsonl)")" -eq 2 ]
  [ "$(jq -r '.source_checkpoint' "$(_J routed-findings.jsonl)" | sort -u)" = cp3 ]
  [ "$(jq -r '.findings[] | select(.severity == "minor") | .status' "$E/cp3/round-1/merged.json")" = open ]
  # an EPIC that belongs to no plan
  _repo; E="$ROOT/ev/adhoc/R-1"; mkdir -p "$E"; : > "$E/timeline.jsonl"
  jq -n '{steps: [{id: "s0", role: "backend", objective: "x", outputs: ["Modify: `src/app.py` — x"]}]}' > "$E/plan.json"
  printf 'base_commit: %s\n' "$(git -C "$R" rev-parse HEAD~1)" > "$E/fsm-state.yaml"
  _sc cp3 ""
  run _close1 cp3; [ "$status" -eq 0 ]; [[ "$output" == *"belongs to no plan"* ]]
  [ "$(jq -r '.findings[0].status' "$E/cp3/round-1/merged.json")" = open ]
}
@test "collect: an answer naming a role outside the round is invalid with unknown_role" {
  _repo; _sc; _S prepare --round 1 >/dev/null
  _sanswer 1 step_generalist '.role = "epic_behaviour"'
  run _S collect --round 1
  jq -e '.invalid[] | select(.role == "step_generalist" and (.reason | startswith("unknown_role")))' "$(D 1)/collect.json"
}
@test "cp3 close refuses a semantic file whose lens is not a reviewer of the round" {
  _erepo; _sc cp3 ""
  local args=(--checkpoint cp3 --evidence-dir "$E" --project-root "$R" --round 1)
  "$ROUND_SH" prepare "${args[@]}" >/dev/null
  local d="$E/cp3/round-1"
  jq -n '{role: "epic_generalist", checkpoint: "cp3", findings: [{id: "g-1", checkpoint: "cp3", step: 0, severity: "minor",
      claim: "naming", command: "grep -n x src/new.py", evidence: "src/new.py:1", fix: "rename"}]}' > "$d/reviewer-epic_generalist.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus cp3-epic-generalist --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus cp3-epic-generalist --output-file "$d/reviewer-epic_generalist.json" --evidence-dir "$d" >/dev/null
  "$ROUND_SH" collect "${args[@]}" >/dev/null
  jq '.findings |= map(.reported_by = ["merge_integrity"])' "$d/merged.json" > "$d/m" && mv "$d/m" "$d/merged.json"
  run "$ROUND_SH" close "${args[@]}" --tokens epic_generalist=5
  [ "$status" -ne 0 ]; [[ "$output" == *"merge_integrity"* ]]
  [ ! -f "$E/semantic-review-final.json" ]
}
@test "cp3 close writes <run>/semantic-review-final.json in the protocol shape, valid against its schema, and refuses to close when it cannot" {
  _erepo; _sc cp3 ""
  run _close1 cp3; [ "$status" -eq 0 ]
  local f="$E/semantic-review-final.json"; [ -f "$f" ]
  [ "$(jq -r .artifact_type "$f")" = semantic_review ]
  [ "$(jq -r .revision.base_sha "$f")" = "$(git -C "$R" rev-parse HEAD~1)" ]
  [ "$(jq -r .revision.head_sha "$f")" = "$(git -C "$R" rev-parse HEAD)" ]
  [ "$(jq -r .semantic_review.mode "$f")" = final ]
  [ "$(jq -r .semantic_review.range "$f")" = "$(jq -r .range "$E/cp3/step-check.json")" ]
  [ "$(jq -c .semantic_review.lenses_run "$f")" = '["epic_generalist"]' ]
  [ "$(jq -r '.semantic_review.findings | map(.severity) | sort | join(",")' "$f")" = "critical,low,medium" ]
  [ "$(jq -r '.semantic_review.findings[] | select(.severity == "critical") | .target_path' "$f")" = src/app.py ]
  [ "$(jq -r '.semantic_review.findings[] | select(.severity == "low") | .status' "$f")" = open ]
  jq -e '.semantic_review.findings | all(.fingerprint | test("^sha256:[0-9a-f]{64}$"))' "$f" >/dev/null
  # every finding carries the schema's required keys
  jq -e --slurpfile s "$AID_PLUGIN_PATH/defaults/schemas/semantic-review.schema.json" \
    '($s[0].properties.semantic_review.properties.findings.items.required) as $req | .semantic_review.findings | all(. as $x | $req | all(. as $k | $x | has($k)))' "$f" >/dev/null
  # round 2 (PM override) after a fix: the fixed finding is resolved, the routed one open, the file rewritten
  "$ROUND_SH" override --checkpoint cp3 --evidence-dir "$E" --project-root "$R" --rounds 2 --reason "PM: confirm the fix in a second round" >/dev/null
  echo "import new" >> "$R/src/app.py"; git -C "$R" commit -qam "fix(review): import"; _sc cp3 ""
  ROUND_N=2 run _close1 cp3 '.findings |= map(select(.id != "g-1"))'; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.semantic_review.findings[] | select(.severity == "critical") | .status' "$f")" = resolved ]
  [ "$(jq -r '.semantic_review.findings[] | select(.severity == "medium") | .status' "$f")" = open ]
  # the fixed finding's route is resolved in the journal; the still-open major keeps its route
  local fp_fixed; fp_fixed="$(jq -r '.findings[] | select(.severity == "blocker") | .fingerprint' "$E/cp3/round-1/merged.json")"
  [ "$(jq -r --arg fp "$fp_fixed" 'select(.op == "resolve" and .fingerprint == $fp) | .resolution' "$(_J routed-findings.jsonl)" | head -c 6)" = "fixed:" ]
  run bash -c "cd '$R' && source '$AID_PLUGIN_PATH/scripts/lib/aid-routed-findings.sh' && aid_finding_open_for_epic P900 E-900-1_2 | wc -l"
  [ "${output##* }" -eq 1 ]
  [ "$(jq -r '.revision.head_sha' "$f")" = "$(git -C "$R" rev-parse HEAD)" ]
  # a write that cannot satisfy the schema fails close before closed_at
  rm -rf "$E/cp3" "$f"; _sc cp3 ""
  "$ROUND_SH" prepare --checkpoint cp3 --evidence-dir "$E" --project-root "$R" --round 1 >/dev/null
  jq -n '{role: "epic_generalist", checkpoint: "cp3", findings: [], no_findings_reason: "none"}' > "$E/cp3/round-1/reviewer-epic_generalist.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus cp3-epic-generalist --agent-id aid-orchestrator:review --evidence-dir "$E/cp3/round-1" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus cp3-epic-generalist --output-file "$E/cp3/round-1/reviewer-epic_generalist.json" --evidence-dir "$E/cp3/round-1" >/dev/null
  "$ROUND_SH" collect --checkpoint cp3 --evidence-dir "$E" --project-root "$R" --round 1 >/dev/null
  mv "$AID_PLUGIN_PATH/defaults/schemas/semantic-review.schema.json" "$ROOT/schema.bak"
  jq '.properties.semantic_review.properties.mode.enum = ["local"]' "$ROOT/schema.bak" > "$AID_PLUGIN_PATH/defaults/schemas/semantic-review.schema.json"
  run "$ROUND_SH" close --checkpoint cp3 --evidence-dir "$E" --project-root "$R" --round 1 --tokens epic_generalist=1
  mv "$ROOT/schema.bak" "$AID_PLUGIN_PATH/defaults/schemas/semantic-review.schema.json"
  [ "$status" -eq 1 ]; [[ "$output" == *"semantic_review.mode"* ]]
  [ ! -f "$f" ]; [ "$(jq -r '.closed_at // "none"' "$E/cp3/round-1/round.json")" = none ]
}

# ── Step 9: fast mode on the same mechanism ──
@test "cp6: a second prepare of the same fast-mode id is refused, a re-run of the step check over a closed index too, and a switched-off checkpoint prepares nothing (exit 3)" {
  _repo; D6="$ROOT/do/20260919T100000Z-abc1234"; mkdir -p "$D6"; : > "$D6/timeline.jsonl"
  seq 1 60 >> "$R/src/app.py"; echo "Task: tidy" > "$D6/task.md"
  (cd "$R" && bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp6 --worktree --evidence-dir "$D6" --dod-file "$D6/task.md") >/dev/null
  "$ROUND_SH" prepare --checkpoint cp6 --evidence-dir "$D6" --project-root "$R" --round 1 >/dev/null
  run "$ROUND_SH" prepare --checkpoint cp6 --evidence-dir "$D6" --project-root "$R" --round 1
  [ "$status" -eq 1 ]; [[ "$output" == *"already prepared"* ]]
  # a closed index is never replaced by a re-run of the step check that would skip
  jq -n '{verdict: "fail", head_sha: "x", rounds: [{round: 1, verdict: "fail"}]}' > "$D6/cp6/rounds.json"
  git -C "$R" checkout -q -- src/app.py; echo tiny >> "$R/src/app.py"
  run bash -c "cd '$R' && bash '$AID_PLUGIN_PATH/scripts/aid-step-check.sh' --checkpoint cp6 --worktree --evidence-dir '$D6' --dod-file '$D6/task.md'"
  [ "$status" -ne 0 ]; [[ "$output" == *"already records a closed round"* ]]
  # the PM's switch
  mkdir -p "$R/.aid-o/config/policies"
  printf 'review_checkpoints:\n  cp6_fast_mode_review: false\n' > "$R/.aid-o/config/policies/review-checkpoints.yaml"
  run "$ROUND_SH" prepare --checkpoint cp6 --evidence-dir "$D6" --project-root "$R" --round 2
  [ "$status" -eq 3 ]; [[ "$output" == *"switched off"* ]]
}
@test "cp6: a fast-mode round closed with verdict fail leaves the FSM unaffected (no FSM path reads evidence/do)" {
  [ "$(grep -c 'evidence/do' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh")" -eq 0 ]
  _repo; D6="$E/../do/20260919T100000Z-abc1234"; mkdir -p "$D6/cp6/round-1"
  jq -n '{verdict: "fail", head_sha: "x", rounds: [{round: 1, verdict: "fail"}]}' > "$D6/cp6/rounds.json"
  # the run's own cp2 evidence decides; the fast-mode directory beside it is invisible to the check
  (cd "$R" && aid_fixture_seed_step_review "$E" cp2 0 pass)
  run bash -c "cd '$R' && source '$AID_PLUGIN_PATH/scripts/aid-fsm.sh' && fsm_check_review_round '$E' cp2 0"
  [ "$status" -eq 0 ]
}

# ── cp7: one round over the whole plan, no plan.json anywhere ─────────────────
# _frepo — a repository with a plan range (base..HEAD), a plan-final run
# directory holding what `produce` writes, and final_review on claude roles only.
_frepo() {
  R="$ROOT/frepo"; E="$R/.aid-o/work/evidence/P901/R-P901-final-1"; mkdir -p "$R/src" "$R/.aid-o/plans" "$E" "$R/.aid-o/config/policies"
  git -C "$ROOT" init -q "$R" >/dev/null; git -C "$R" config user.email t@t; git -C "$R" config user.name t
  echo '.aid-o/' > "$R/.gitignore"; echo base > "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm base
  FBASE="$(git -C "$R" rev-parse HEAD)"
  seq 1 60 >> "$R/src/app.py"; echo "- **New thing** — the app now imports new" > "$R/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm "feat: the plan's work"
  printf -- '---\nid: P901\ntype: feature\n---\n# Plan\n\n### Step 1: first\n\n**Acceptance Criteria:**\n- [ ] the app imports new\n\n**Effort:** S\n\n## Success Criteria\n\n- it works end to end\n' > "$R/.aid-o/plans/P901-x.md"
  echo '{"gates": {"tests_pass": {"gate": "tests_pass", "result": "pass"}}, "overall_status": "pass"}' > "$E/gates_report.json"
  echo '{"criteria": []}' > "$E/plan-diff.json"; : > "$E/timeline.jsonl"
  yq '.review_checkpoints.final_review.reviewers |= map(.provider = "claude" | .model = "sonnet")' \
     "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" > "$R/.aid-o/config/policies/review-checkpoints.yaml"
  bash -c "source '$AID_PLUGIN_PATH/scripts/lib/aid-step-review-packet.sh' && aid_final_review_inputs_build '$R' '$E' '$R/.aid-o/plans/P901-x.md' P901"
}
_fsc() { bash "$AID_PLUGIN_PATH/scripts/aid-step-check.sh" --checkpoint cp7 --base "$FBASE" --evidence-dir "$E" --project-root "$R" >/dev/null; }
_F() { "$ROUND_SH" "$1" --checkpoint cp7 --evidence-dir "$E" --project-root "$R" "${@:2}"; }
FD() { printf '%s/cp7/round-%s' "$E" "$1"; }
# _fanswer <round> <role> [jq filter] — a cp7 answer with no findings, bracketed like a dispatched agent
_fanswer() {
  local d; d="$(FD "$1")"
  jq -n --arg r "$2" '{role: $r, checkpoint: "cp7", findings: [], no_findings_reason: "fixture"}' | jq "${3:-.}" > "$d/reviewer-$2.json"
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" start --focus "cp7-${2//_/-}" --agent-id aid-orchestrator:review --evidence-dir "$d" >/dev/null
  bash "$AID_PLUGIN_PATH/scripts/aid-emit-dispatch.sh" complete --focus "cp7-${2//_/-}" --output-file "$d/reviewer-$2.json" --evidence-dir "$d" >/dev/null
}
_BLOCKER='.findings = [{id: "c-1", checkpoint: "cp7", step: null, severity: "blocker", claim: "the changelog claims an import the app never makes", command: "grep -n import src/app.py", evidence: "src/app.py:1", fix: "import new"}] | del(.no_findings_reason)'

@test "cp7: produce's inputs hold the plan's criteria and the EPIC findings; prepare prints three prompts with cp7 foci" {
  _frepo; _fsc
  grep -q "the app imports new" "$E/cp7/criteria.md"; grep -q "it works end to end" "$E/cp7/criteria.md"
  [ "$(jq -c .epics "$E/cp7/epic-findings.json")" = "[]" ]
  [ ! -e "$E/plan.json" ]
  run _F prepare --round 1; echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" == *"focus cp7-final-criteria"* && "$output" == *"focus cp7-final-claims"* && "$output" == *"focus cp7-final-generalist"* ]]
  grep -q "CHANGELOG" "$(FD 1)/packet/claims.patch"
  grep -q "every EPIC together" "$(FD 1)/prompt-final_claims.md"
}

@test "cp7: a closed round writes rounds.json and a schema-shaped semantic file over base..candidate, lenses = the round's roles" {
  _frepo; _fsc; _F prepare --round 1 >/dev/null
  local r; for r in final_criteria final_claims final_generalist; do _fanswer 1 "$r"; done
  _F collect --round 1 >/dev/null
  run _F close --round 1 --tokens final_criteria=5 final_claims=5 final_generalist=5; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r .verdict "$E/cp7/rounds.json")" = pass ]
  [ "$(jq -r .head_sha "$E/cp7/rounds.json")" = "$(git -C "$R" rev-parse HEAD)" ]
  local f="$E/semantic-review-final.json"
  [ "$(jq -r .semantic_review.range "$f")" = "${FBASE}..$(git -C "$R" rev-parse HEAD)" ]
  [ "$(jq -r .revision.base_sha "$f")" = "$FBASE" ]
  [ "$(jq -c '.semantic_review.lenses_run | sort' "$f")" = '["final_claims","final_criteria","final_generalist"]' ]
  [ "$(jq -r .generated_by "$f")" = "aid-review-round.sh close cp7" ]
  run bash -c "cd '$R' && source '$AID_PLUGIN_PATH/scripts/aid-fsm.sh' && fsm_check_review_round '$E' cp7"
  [ "$status" -eq 0 ]
}

@test "cp7: the FSM check names the next command when no round exists" {
  _frepo
  run bash -c "cd '$R' && source '$AID_PLUGIN_PATH/scripts/aid-fsm.sh' && fsm_check_review_round '$E' cp7"
  [ "$status" -eq 1 ]; [[ "$output" == *"--checkpoint cp7"* ]]
}

@test "cp7: prepare refuses when HEAD moved past the commit the check was computed at, and without produce's files" {
  _frepo; _fsc
  echo more >> "$R/src/app.py"; git -C "$R" commit -qam "later work"
  run _F prepare --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"stale"* ]]
  _fsc; rm "$E/cp7/criteria.md"
  run _F prepare --round 1; [ "$status" -eq 1 ]; [[ "$output" == *"--stage produce"* ]]
}

@test "cp7: close refuses a reviewer file nobody dispatched" {
  _frepo; _fsc; _F prepare --round 1 >/dev/null
  _fanswer 1 final_criteria; _fanswer 1 final_claims
  jq -n '{role: "final_generalist", checkpoint: "cp7", findings: [], no_findings_reason: "hand-written"}' > "$(FD 1)/reviewer-final_generalist.json"
  _F collect --round 1 >/dev/null
  run _F close --round 1 --tokens final_criteria=5 final_claims=5 final_generalist=5
  [ "$status" -eq 1 ]; [[ "$output" == *"no_dispatch_record"* ]]
}

@test "cp7: an open blocker fails the round and stays open; the confirmation round carries it and the fix diff, and asks only its reporter" {
  _frepo; _fsc; _F prepare --round 1 >/dev/null
  _fanswer 1 final_criteria; _fanswer 1 final_generalist; _fanswer 1 final_claims "$_BLOCKER"
  _F collect --round 1 >/dev/null
  run _F close --round 1 --tokens final_criteria=5 final_claims=5 final_generalist=5; [ "$status" -eq 0 ]
  [ "$(jq -r .verdict "$E/cp7/rounds.json")" = fail ]
  [ "$(jq -r '.findings[0].status' "$(FD 1)/merged.json")" = open ]
  run bash -c "cd '$R' && source '$AID_PLUGIN_PATH/scripts/aid-fsm.sh' && fsm_check_review_round '$E' cp7"; [ "$status" -eq 1 ]
  sed -i '1i import new' "$R/src/app.py"; git -C "$R" commit -qam "fix(review): import"; _fsc
  run _F prepare --round 2; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -c .reviewers_expected "$(FD 2)/round.json")" = '["final_claims"]' ]
  [ -s "$(FD 2)/packet/fix.patch" ]; [ "$(jq '.findings | length' "$(FD 2)/packet/open-findings.json")" -eq 1 ]
}

@test "cp7: a finding of a final role validates against the finding schema's checkpoint and role lists" {
  jq -e '."$defs".checkpoint.enum | index("cp7")' "$AID_PLUGIN_PATH/defaults/schemas/review-finding.schema.json"
  jq -e '."$defs".roles_step.enum | (index("final_criteria") and index("final_claims") and index("final_generalist"))' "$AID_PLUGIN_PATH/defaults/schemas/review-finding.schema.json"
}
