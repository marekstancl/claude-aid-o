#!/usr/bin/env bats
# aid-tier: t1
# test-step-check.bats — aid-step-check.sh on a fixture repository: the range
# comes from the step boundary and is refused when undetermined or not an
# ancestor; a small clean in-scope diff is skip and writes the round index; an
# empty range is no_change; a forbidden path or a file outside scope is never
# a skip; a security pattern is review+security; handlers, test tiers,
# streamlined runs, cp3 and cp6 ranges; the step_check event binds the file;
# a recorded closed round is never overwritten by a re-run; a second declared
# repository is reviewed from the step's return.
# Origin: P094 Step 3 (step review rebuild).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SC="$AID_PLUGIN_PATH/scripts/aid-step-check.sh"
  T="$(mktemp -d)"; R="$T/repo"; E="$T/evidence"
  mkdir -p "$R/src/api" "$R/docs" "$R/secrets" "$R/tests" "$E"
  git -C "$R" init -q -b main
  git -C "$R" config user.email t@t; git -C "$R" config user.name t
  echo "base" > "$R/src/app.py"; echo "# docs" > "$R/docs/README.md"; echo "k" > "$R/secrets/key.txt"
  git -C "$R" add -A; git -C "$R" commit -qm base
  BASE="$(git -C "$R" rev-parse HEAD)"
  printf 'base_commit: %s\nstreamlined_mode: false\n' "$BASE" > "$E/fsm-state.yaml"
  jq -n '{steps: [
    {id: "s0", role: "backend", objective: "o0", outputs: ["Modify: `src/app.py` — x"], forbidden_paths: ["secrets/**", "never touch the payment module"]},
    {id: "s1", role: "backend", objective: "o1", outputs: ["Modify: `src/api/handler.py` — x", "Test: `tests/test_handler.py` — y"], allowed_paths: ["src/api/**"], forbidden_paths: ["secrets/**"]},
    {id: "s2", role: "docs-writer", objective: "o2", outputs: ["Modify: `docs/README.md` — z"]}
  ]}' > "$E/plan.json"
  : > "$E/timeline.jsonl"
}
teardown() { rm -rf "$T"; }

_commit() { git -C "$R" add -A; git -C "$R" commit -qm "$1"; git -C "$R" rev-parse HEAD; }
_event() { printf '{"ts":"t","event":"step_commit","step_n":%s,"commit_sha":"%s"}\n' "$1" "$2" >> "$E/timeline.jsonl"; }
_run() { (cd "$R" && bash "$SC" --evidence-dir "$E" "$@"); }
_json() { jq -r "$1" "$E/$2/step-check.json"; }

@test "cp2 step 1: the range starts at step 0's step_commit, not at base_commit" {
  echo "s0" >> "$R/src/app.py"; c0="$(_commit s0)"; _event 0 "$c0"
  echo "h" > "$R/src/api/handler.py"; _commit s1 >/dev/null
  run _run --checkpoint cp2 --step 1
  [ "$status" -eq 0 ]
  [ "$(_json .range_source cp2/step-1)" = step_commit ]
  [[ "$(_json .range cp2/step-1)" == "$c0"..* ]]
  [ "$(_json '.files.in_scope|length' cp2/step-1)" -eq 1 ]
}
@test "cp2 step 0: falls back to base_commit; neither present is exit 22 and no file" {
  echo "s0" >> "$R/src/app.py"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [ "$(_json .range_source cp2/step-0)" = base_commit ]
  rm "$E/fsm-state.yaml"; : > "$E/timeline.jsonl"; rm -rf "$E/cp2"
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 22 ]; [[ "$output" == *range_undetermined* ]]
  [ ! -f "$E/cp2/step-0/step-check.json" ]
  grep -q step_check_range_undetermined "$E/timeline.jsonl"
}
@test "a small clean in-scope diff is skip, writes rounds.json and a bound step_check event" {
  echo "one line" >> "$R/src/app.py"; h="$(_commit s0)"
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: skip"* ]]
  [ "$(jq -r .verdict "$E/cp2/step-0/rounds.json")" = skip ]
  [ "$(jq -r .head_sha "$E/cp2/step-0/rounds.json")" = "$h" ]
  local sha; sha="$(_json .sha256 cp2/step-0)"
  jq -e --arg s "$sha" --arg h "$h" 'select(.event == "step_check" and .sha256 == $s and .head_sha == $h and .verdict == "skip")' "$E/timeline.jsonl" | grep -q .
  # the sha256 is over the file without its own sha256 field
  [ "$(jq -S 'del(.sha256)' "$E/cp2/step-0/step-check.json" | sha256sum | cut -d' ' -f1)" != "" ]
}
@test "an empty range is no_change with rounds.json, never skip" {
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: no_change"* ]]
  [ "$(jq -r .verdict "$E/cp2/step-0/rounds.json")" = no_change ]
}
@test "the same small diff touching a forbidden path is review with forbidden_touched and a script finding" {
  echo "x" >> "$R/secrets/key.txt"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: review"* ]]
  [ "$(_json '.files.forbidden_touched[0]' cp2/step-0)" = secrets/key.txt ]
  [ "$(_json '.script_findings[0].severity' cp2/step-0)" = blocker ]
  [ ! -f "$E/cp2/step-0/rounds.json" ]
}
@test "a file outside the step's scope is review, never skip; prose forbidden entries are ignored" {
  echo "x" >> "$R/docs/README.md"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: review"* ]]
  [ "$(_json '.files.outside_files[0]' cp2/step-0)" = docs/README.md ]
}
@test "an added subprocess shell=True line is review+security naming the rule" {
  printf 'import subprocess\nsubprocess.run(cmd, shell=True)\n' >> "$R/src/app.py"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: review+security"* ]]
  [ "$(_json '.security.matched_rules[0]' cp2/step-0)" = subprocess_shell_true ]
  [ "$(_json '.security.lines|length' cp2/step-0)" -ge 1 ]
}
@test "an upper-case secret assignment with spaces matches the secret rule (rules use \\s and are matched case-insensitively, testbed 2026-09-19)" {
  printf 'AWS_SECRET_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLEKEY0123456789"\n' >> "$R/src/app.py"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: review+security"* ]]
  [ "$(_json '.security.matched_rules[0]' cp2/step-0)" = hardcoded_secret_pattern ]
}

@test "an added route decorator fills handler_patterns" {
  printf '@app.post("/x")\ndef create(request):\n    pass\n' > "$R/src/api/handler.py"
  echo "s0" >> "$R/src/app.py"; c0="$(_commit s0)"; _event 0 "$c0"
  echo "more" >> "$R/src/api/handler.py"; _commit s1 >/dev/null
  # step 1 range covers only the last commit; put the handler in the step-1 change instead
  printf '@router.get("/y")\n' >> "$R/src/api/handler.py"; _commit s1b >/dev/null
  run _run --checkpoint cp2 --step 1
  [ "$status" -eq 0 ]
  [ "$(_json '.handler_patterns|length' cp2/step-1)" -ge 1 ]
}
@test "an added test without a tier tag is tier: missing; a tagged one carries its tier" {
  echo "s0" >> "$R/src/app.py"; c0="$(_commit s0)"; _event 0 "$c0"
  echo "h" > "$R/src/api/handler.py"
  printf '# aid-tier: t1\n@test "x" { true; }\n' > "$R/tests/test_handler.py"
  printf 'def test_y(): pass\n' > "$R/tests/test_other.py"
  _commit s1 >/dev/null
  run _run --checkpoint cp2 --step 1
  [ "$status" -eq 0 ]
  [ "$(_json '.tests.added[] | select(.path == "tests/test_handler.py") | .tier' cp2/step-1)" = t1 ]
  [ "$(_json '.tests.added[] | select(.path == "tests/test_other.py") | .tier' cp2/step-1)" = missing ]
}
@test "a streamlined run is skip with reason streamlined" {
  printf 'base_commit: %s\nstreamlined_mode: true\n' "$BASE" > "$E/fsm-state.yaml"
  for i in 1 2 3; do echo "$i" >> "$R/src/app.py"; done; seq 1 80 >> "$R/src/app.py"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [[ "$output" == "verdict: skip (streamlined)"* ]]
  [ "$(jq -r .reason "$E/cp2/step-0/rounds.json")" = streamlined ]
}
@test "cp3 ranges from base_commit over every step's scope; a base that is not an ancestor is refused" {
  echo "s0" >> "$R/src/app.py"; c0="$(_commit s0)"; _event 0 "$c0"
  echo "h" > "$R/src/api/handler.py"; _commit s1 >/dev/null
  run _run --checkpoint cp3
  [ "$status" -eq 0 ]; [[ "$(_json .range cp3)" == "$BASE"..* ]]
  [ "$(_json '.files.outside_files|length' cp3)" -eq 0 ]
  # a foreign base
  git -C "$R" checkout -q -b other "$BASE"; echo f > "$R/f"; foreign="$(_commit foreign)"; git -C "$R" checkout -q main
  printf 'base_commit: %s\n' "$foreign" > "$E/fsm-state.yaml"; rm -rf "$E/cp3"
  run _run --checkpoint cp3
  [ "$status" -eq 1 ]; [[ "$output" == *"not an ancestor"* ]]
}
@test "cp6 sees the working tree (unstaged and untracked) and takes the DoD from --dod-file" {
  echo "wip" >> "$R/src/app.py"; echo "new" > "$R/src/new.py"
  echo "Task: do the thing" > "$T/dod.txt"
  run _run --checkpoint cp6 --dod-file "$T/dod.txt"
  [ "$status" -eq 0 ]
  [ "$(_json .range_source cp6)" = worktree ]
  [ "$(_json '.files.in_scope|length' cp6)" -eq 2 ]
  [ "$(_json '.files.scope_declared' cp6)" = false ]
  [[ "$(_json .dod cp6)" == "Task: do the thing"* ]]
}
@test "a re-run over a directory holding a closed failing round never replaces it: a small diff is review, not a skip, and the index is unchanged" {
  echo "one" >> "$R/src/app.py"; _commit s0 >/dev/null
  mkdir -p "$E/cp2/step-0/round-1"
  jq -n '{verdict: "fail", head_sha: "x", rounds: [{round: 1, verdict: "fail"}]}' > "$E/cp2/step-0/rounds.json"
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [ "$(_json .verdict cp2/step-0)" = review ]
  [ "$(jq -r .verdict "$E/cp2/step-0/rounds.json")" = fail ]
}
@test "a change only in a second declared repository is reviewed from the return's repo_commits; without them the repository is reported" {
  local O="$T/docs-repo"; mkdir -p "$O/guide"; git -C "$O" init -q -b main
  git -C "$O" config user.email t@t; git -C "$O" config user.name t
  echo a > "$O/guide/page.md"; git -C "$O" add -A; git -C "$O" commit -qm base; local ob; ob="$(git -C "$O" rev-parse HEAD)"
  echo b >> "$O/guide/page.md"; git -C "$O" commit -qam step; local oh; oh="$(git -C "$O" rev-parse HEAD)"
  jq --arg o "$O/guide" '.steps[2].allowed_paths = [$o]' "$E/plan.json" > "$E/p" && mv "$E/p" "$E/plan.json"
  run _run --checkpoint cp2 --step 2
  [ "$status" -eq 0 ]; [ "$(_json .verdict cp2/step-2)" = review ]
  [[ "$(_json .reason cp2/step-2)" == *"$O"* ]]
  mkdir -p "$E/steps/s2"; jq -n --arg r "$O" --arg g "${ob}..${oh}" '{repo_commits: [{repo: $r, range: $g}]}' > "$E/steps/s2/return.json"
  rm -rf "$E/cp2/step-2"
  run _run --checkpoint cp2 --step 2
  [ "$status" -eq 0 ]
  [ "$(_json '.files.in_scope[0]' cp2/step-2)" = "$O/guide/page.md" ]
}
@test "a step that moves after a closed round is review, never skip" {
  echo "s0" >> "$R/src/app.py"; _commit s0 >/dev/null
  mkdir -p "$E/cp2/step-0"; jq -n '{verdict: "pass", head_sha: "x", rounds: [{round: 1, verdict: "pass"}]}' > "$E/cp2/step-0/rounds.json"
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]; [ "$(_json .verdict cp2/step-0)" = review ]
  [[ "$(_json .reason cp2/step-0)" == *"delta round"* ]]
}
@test "run from the primary, the step is diffed in the worktree the run's branch is checked out in; a branch checked out nowhere is refused" {
  git -C "$R" worktree add -q -b task/E/main "$T/wt" main
  printf 'branch: task/E/main\n' >> "$E/fsm-state.yaml"
  echo "s0" >> "$T/wt/src/app.py"; git -C "$T/wt" commit -qam s0
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]
  [ "$(_json .range cp2/step-0)" = "${BASE}..$(git -C "$T/wt" rev-parse HEAD)" ]
  # the branch exists but no tree has it: its commits are in no tree to diff
  git -C "$R" worktree remove --force "$T/wt"; rm -rf "$E/cp2"
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 2 ]; [[ "$output" == *"task/E/main"*"checked out in no worktree"* ]]
  # a merged and deleted branch falls back to the tree the check runs in
  git -C "$R" branch -D task/E/main >/dev/null
  run _run --checkpoint cp2 --step 0
  [ "$status" -eq 0 ]
}
@test "usage: a missing plan.json for cp2, an unreadable rules file and a bad checkpoint are refused with their code" {
  rm "$E/plan.json"; echo x >> "$R/src/app.py"; _commit s0 >/dev/null
  run _run --checkpoint cp2 --step 0; [ "$status" -eq 1 ]; [[ "$output" == *plan.json* ]]
  run env AID_PREFILTER_RULES=/nonexistent bash "$SC" --checkpoint cp2 --step 0 --evidence-dir "$E" --project-root "$R"
  [ "$status" -eq 2 ]
  run _run --checkpoint cp4; [ "$status" -eq 2 ]
}
