#!/usr/bin/env bats
# aid-tier: t0
# test-brainstorm-opponent.bats — the second model in the room (P086 Step 8).
#
# THE GROUNDED FAILURE MODE: brainstorming was a monologue, and the only
# opponent AID had arrived AFTER the plan was written (the C0 review) — the
# expensive place to discover a wrong premise.
#
# HOW CODEX IS STOOD IN FOR: a `codex` shim on PATH that answers the four
# availability probes lib/aid-audit-independence.sh really makes, and writes a
# last-message file the way the real CLI does. So what is exercised is the
# parsing and the merge that will meet the real tool — not a mock of AID's own
# code.
#
# NOT PROVED HERE, AND NOT PROVABLE ANYWHERE: that two models agreeing are
# right. That is a stated boundary of the design.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  OPP="$PLUGIN_ROOT/scripts/lib/aid-brainstorm-opponent.sh"
  BS="$PLUGIN_ROOT/scripts/aid-brainstorm-state.sh"
  TMP="$(mktemp -d)"
  BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/out"
  PATH_BEFORE="$PATH"
  ROOT="$TMP/project"
  mkdir -p "$ROOT/.aid-o/work"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    printf '.aid-o/\n.aid-worktrees/\n' > .gitignore
    printf 'seed\n' > README.md
    git add -A && git commit -q -m seed
  )
  export AID_PROJECT_ROOT="$ROOT"
  BRIEF="$TMP/brief.md"
  printf '# Topic\n\n- The hook layer enforces; the skill only describes.\n' > "$BRIEF"
  bash "$BS" init P900 --scope roadmap --no-worktree >/dev/null
}

teardown() {
  export PATH="$PATH_BEFORE"
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

approve_vision() {
  cat > "$TMP/vision.md" <<'V'
## Vision

- V1: Every rule AID enforces has a mechanism.
  - test: each enforcement row names a degree and a source.
V
  bash "$BS" vision-propose P900 --file "$TMP/vision.md" >/dev/null
  bash "$BS" vision-approve P900 >/dev/null
}

# fake_codex <answer-heredoc-content>
#   Answers the availability probes truthfully-shaped, then writes <content> to
#   the --output-last-message file the way `codex exec` does.
fake_codex() {
  printf '%s' "$1" > "$TMP/answer.txt"
  cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  login) echo "Logged in as test"; exit 0 ;;
  exec)
    if [[ "$*" == *"--help"* ]]; then
      echo "Usage: codex exec [--json] [--output-schema <file>] [--output-last-message <file>]"
      exit 0
    fi
    last=""
    prev=""
    for a in "$@"; do
      [[ "$prev" == "--output-last-message" ]] && last="$a"
      prev="$a"
    done
    [[ -n "$last" ]] && cat "$ANSWER_FILE" > "$last"
    exit "${FAKE_CODEX_EXIT:-0}"
    ;;
esac
exit 0
EOF
  chmod +x "$BIN/codex"
  export ANSWER_FILE="$TMP/answer.txt"
  export PATH="$BIN:$PATH_BEFORE"
}

run_opponent() { run bash "$OPP" P900 "$BRIEF" "$TMP/out"; }

@test "AC24: what both models agree on is recorded without troubling the PM" {
  approve_vision
  fake_codex '{"agree":[{"point":"A hook without a canary proves nothing","why":"an unapproved hook is skipped in silence"}],"disagree":[],"missing":[]}'
  run_opponent
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agree | length' "$TMP/out/dispute.json")" = "1" ]
  [ "$(jq -r '.to_pm | length' "$TMP/out/dispute.json")" = "0" ]
  [[ "$output" == *"1 agreed, 0 disputed"* ]]
}

@test "AC25: a disagreement reaches the PM with both positions and what it costs" {
  approve_vision
  fake_codex '{"agree":[],"disagree":[{"point":"Where the capsule lives","aid_position":"session store","opponent_position":"the workspace","stake":"a hook writing into a repo breaks the ecosystem rule"}],"missing":["nobody has said what happens on a fork"]}'
  run_opponent
  [ "$status" -eq 0 ]
  local d="$TMP/out/dispute.json"
  [ "$(jq -r '.to_pm | length' "$d")" = "1" ]
  [ "$(jq -r '.to_pm[0].aid_position' "$d")" = "session store" ]
  [ "$(jq -r '.to_pm[0].opponent_position' "$d")" = "the workspace" ]
  [[ "$(jq -r '.to_pm[0].stake' "$d")" == *"ecosystem rule"* ]]
  [ "$(jq -r '.missing | length' "$d")" = "1" ]
}

@test "no more than five disagreements go to the PM; the rest stay in the artifact" {
  approve_vision
  local many='{"agree":[],"missing":[],"disagree":['
  for i in 1 2 3 4 5 6 7; do
    many+="{\"point\":\"p$i\",\"aid_position\":\"a\",\"opponent_position\":\"b\",\"stake\":\"s\"}"
    [[ "$i" -lt 7 ]] && many+=","
  done
  many+=']}'
  fake_codex "$many"
  run_opponent
  [ "$status" -eq 0 ]
  [ "$(jq -r '.to_pm | length' "$TMP/out/dispute.json")" = "5" ]
  [ "$(jq -r '.held_back' "$TMP/out/dispute.json")" = "2" ]
  [ "$(jq -r '.disagree | length' "$TMP/out/dispute.json")" = "7" ]
  [[ "$output" == *"2 beyond the 5"* ]]
}

@test "AC26: an opponent that cannot be reached is recorded as such, never as agreement" {
  approve_vision
  export PATH="/usr/bin:/bin"   # no codex at all
  run_opponent
  [ "$status" -eq 3 ]
  [ "$(jq -r '.opponent' "$TMP/out/dispute.json")" = "unreached" ]
  [ "$(jq -r '.agree | length' "$TMP/out/dispute.json")" = "0" ]
  [[ "$output" == *"monologue"* ]]
}

@test "AC26: an answer outside the required shape is treated as not reached, not as consent" {
  approve_vision
  fake_codex 'I broadly agree with everything you said.'
  run_opponent
  [ "$status" -eq 3 ]
  [ "$(jq -r '.opponent' "$TMP/out/dispute.json")" = "unreached" ]
  [[ "$(jq -r '.reason' "$TMP/out/dispute.json")" == *"cannot be read is not agreement"* ]]
}

@test "a fenced JSON answer is still an answer" {
  approve_vision
  fake_codex '```json
{"agree":[{"point":"x","why":"y"}],"disagree":[],"missing":[]}
```'
  run_opponent
  [ "$status" -eq 0 ]
  [ "$(jq -r '.opponent' "$TMP/out/dispute.json")" = "answered" ]
}

@test "a codex that fails is not reached" {
  approve_vision
  fake_codex '{"agree":[],"disagree":[],"missing":[]}'
  FAKE_CODEX_EXIT=7 run_opponent
  [ "$status" -eq 3 ]
  [ "$(jq -r '.opponent' "$TMP/out/dispute.json")" = "unreached" ]
}

@test "an agree entry that is not an object is not a shape this code accepts" {
  approve_vision
  fake_codex '{"agree":["delete production"],"disagree":[],"missing":[]}'
  run_opponent
  [ "$status" -eq 3 ]
  [ "$(jq -r '.opponent' "$TMP/out/dispute.json")" = "unreached" ]
}

@test "a dispute artifact that cannot be written is a failure, not a recorded monologue" {
  # "The artifact says so" has to be a fact about a file. A run that could not
  # write its record must not report one.
  approve_vision
  export PATH="/usr/bin:/bin"        # opponent unavailable -> the unreached path
  chmod 500 "$TMP/out"
  run_opponent
  chmod 700 "$TMP/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no record of what happened"* ]]
}

@test "the vision gate really stops the dispatch — no opponent runs on an unapproved vision" {
  fake_codex '{"agree":[{"point":"x","why":"y"}],"disagree":[],"missing":[]}'
  run_opponent
  [ "$status" -eq 1 ]
  [[ "$output" == *"not approved"* ]]
  [ ! -f "$TMP/out/dispute.json" ]
}
