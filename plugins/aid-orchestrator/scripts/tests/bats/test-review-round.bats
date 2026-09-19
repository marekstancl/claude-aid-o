#!/usr/bin/env bats
# aid-tier: t1
# test-review-round.bats — aid-review-round.sh on small fixture trees, for every
# checkpoint. The CP1 cases of test-plan-review-round.bats run here through the
# generic engine (the plan passed as before); then the step cases: a round from
# a step check at HEAD, the confirmation packet, close bound to HEAD, to a
# token value per claude role and to a recorded dispatch bracket, the stub
# flag, the codex-absent degraded path, retry and override, cp6.
# Origin: P094 Step 6 (step review rebuild); the old suite goes in Step 14.

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
@test "step: a codex role whose launcher is absent counts as provider_absent and the round closes degraded" {
  _repo; _sc
  mkdir -p "$R/.aid-o/config/policies"
  yq '.review_checkpoints.step_review.reviewers += [{"role":"step_security","provider":"codex","model":"gpt-5"}] | .review_checkpoints.step_review.reviewers |= unique_by(.role)' \
     "$AID_PLUGIN_PATH/defaults/policies/review-checkpoints.yaml" > "$R/.aid-o/config/policies/review-checkpoints.yaml"
  yq -i '.review_checkpoints.step_review.reviewers = [{"role":"step_generalist","provider":"claude","model":"opus"},{"role":"step_security","provider":"codex","model":"gpt-5"}]' "$R/.aid-o/config/policies/review-checkpoints.yaml"
  _S prepare --round 1 >/dev/null
  [ "$(jq '.reviewers_expected | length' "$(D 1)/round.json")" -eq 2 ]
  mkdir -p "$ROOT/bin"; printf '#!/usr/bin/env bash\necho "ERROR: You have hit your usage limit" >&2\nexit 1\n' > "$ROOT/bin/codex"; chmod +x "$ROOT/bin/codex"
  PATH="$ROOT/bin:$PATH" run "$ROUND_SH" dispatch --checkpoint cp2 --evidence-dir "$E" --step 0 --project-root "$R" --round 1 --provider codex --role step_security
  [ "$status" -eq 1 ]; [[ "$output" == *rate_limited* ]]
  [ "$(jq -r .reason "$(D 1)/codex-step_security.usage.json")" = rate_limited ]
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
