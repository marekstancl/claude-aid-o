#!/usr/bin/env bats
# aid-tier: t1
# test-plan-diff-step.bats — the brief's points run after every step
# (aid-plan-diff.sh --step N --plan-json, P110 Step 2) and in isolation at the
# close (--isolated --cwd, P110 Step 3). Local commands only (true, false,
# sleep, a local listener); the namespace cases skip where the nested unshare
# probe is refused.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PD="$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh"
  ROOT="$(mktemp -d)"; cd "$ROOT"
  git init -q .; git config user.email t@t; git config user.name t
  echo x > seed; git add seed; git commit -qm seed
  PLAN="$ROOT/plan.md"; EV="$ROOT/ev"; mkdir -p "$EV"
  _plan
}
teardown() { rm -rf "$ROOT"; }

# _blk <cmd> [timeout] — a verification_pattern block under the bullet before it
_blk() {
  printf '  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "%s"\n    expected_exit: 0\n' "$1"
  [[ -n "${2:-}" ]] && printf '    timeout: %s\n' "$2"
  printf '  ```\n'
}
# _plan — five steps; AC3 is named by steps 3 and 5; step 4 closes nothing but
# has its own labelled criterion; step 2 has neither.
_plan() {
  {
    printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n'
    printf '### Step 1: one\n\n- [ ] [backend] step one own check\n'; _blk "test -f one.txt"
    printf '\n**Zavírá:** AC1\n\n'
    printf '### Step 2: two\n\n**Zavírá:** —\n\n'
    printf '### Step 3: three\n\n**Zavírá:** AC3, AC2\n\n'
    printf '### Step 4: four\n\n- [ ] [backend] step four own check\n'; _blk "test -f four.txt"
    printf '\n**Zavírá:** —\n\n'
    printf '### Step 5: five\n\n**Zavírá:** AC3, AC4\n\n'
    printf '## Acceptance Criteria\n\n'
    printf -- '- [ ] AC1: one\n'; _blk "true"
    printf -- '- [ ] AC2: two fails\n'; _blk "false"
    printf -- '- [ ] AC3: three\n'; _blk "true"
    printf -- '- [ ] AC4: slow\n'; _blk "sleep 5" 2
  } > "$PLAN"
}
# _pj <plan_step:zavira>... — a plan.json with one step per argument ("1:AC1", "2:", "3:AC3,AC2")
_pj() {
  local a ps z out='[]'
  for a in "$@"; do
    ps="${a%%:*}"; z="${a#*:}"
    out="$(jq -c --arg ps "$ps" --arg z "$z" '. + [{id: "step_\($ps)_backend", plan_step: (if $ps == "null" then null else ($ps | tonumber) end), zavira: ($z | split(",") | map(select(. != "")))}]' <<< "$out")"
  done
  jq -n --argjson s "$out" '{steps: $s}' > "$ROOT/plan.json"
}
_run() { run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD --plan-json "$ROOT/plan.json" "$@"; }
_out() { cat "$EV/cp2/step-$1/plan-diff.json"; }
# _card <text> [answered] — a Decision card quoting <text>; answered: a PM prompt after it
_card() {
  CARD="$ROOT/card-$RANDOM.md"; echo "Rozhodnutí 1: $1" > "$CARD"; touch -d '-10 seconds' "$CARD"
  export AID_HOOK_AUDIT="$ROOT/audit.jsonl"; : > "$AID_HOOK_AUDIT"
  [[ "${2:-}" == answered ]] && printf '{"ts":"%s","event":"UserPromptSubmit","rule":"pm_reply_marker"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$AID_HOOK_AUDIT"
  return 0
}

@test "step: --step 0 runs the step's brief point and its own criterion and writes cp2/step-0/plan-diff.json bound to HEAD" {
  _pj "1:AC1" "2:" "3:AC3,AC2"
  touch one.txt
  _run --step 0; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r .scope)" = step ] && [ "$(_out 0 | jq -r .plan_step)" = 1 ] && [ "$(_out 0 | jq -r .step)" = 0 ]
  [ "$(_out 0 | jq -r .head_commit)" = "$(git rev-parse HEAD)" ]
  [ "$(_out 0 | jq -c '[.results[] | .verdict]')" = '["present","present"]' ]
  [ "$(_out 0 | jq -r '.results[0].ac_label')" = AC1 ]
}
@test "step: an EPIC whose first step is plan step 4 reads the ### Step 4: section" {
  _pj "4:" "5:AC3,AC4"
  _run --step 0; echo "$output"; [ "$status" -eq 1 ]
  [ "$(_out 0 | jq -r .plan_step)" = 4 ]
  [ "$(_out 0 | jq -r '.results[0].ac_text')" = "step four own check" ]
  [ "$(_out 0 | jq -r '.results[0].verdict')" = absent ]
}
@test "step: a point a later plan step also names is deferred_to_step there, read from the plan file not plan.json" {
  _pj "1:AC1" "2:" "3:AC3,AC2"
  _run --step 2; echo "$output"; [ "$status" -eq 1 ]
  [ "$(_out 2 | jq -r '.results[] | select(.ac_label == "AC3") | .deferred_to_step')" = 5 ]
  [ "$(_out 2 | jq -r '.results[] | select(.ac_label == "AC3") | .verdict')" = skipped ]
  [ "$(_out 2 | jq -r '.results[] | select(.ac_label == "AC2") | .verdict')" = absent ]
}
@test "step: a step with neither points nor own criteria writes unmeasured_step and exits 2" {
  _pj "1:AC1" "2:"
  _run --step 1; echo "$output"; [ "$status" -eq 2 ]
  [ "$(_out 1 | jq -r .unmeasured_step)" = true ]
}
@test "step: a step that closes no point runs its own labelled block" {
  _pj "4:"
  touch four.txt
  _run --step 0; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r '.results | length')" = 1 ] && [ "$(_out 0 | jq -r '.results[0].verdict')" = present ]
}
@test "step: a failing cmd is absent with its exit code" {
  _pj "3:AC2"
  _run --step 0; [ "$status" -eq 1 ]
  [[ "$(_out 0 | jq -r '.results[0].evidence')" == "exit=1"* ]]
}
@test "step: a block's timeout: is used — sleep 5 with timeout 2 is absent (reason=timeout)" {
  _pj "5:AC4"
  _run --step 0; [ "$status" -eq 1 ]
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC4") | .evidence')" == *"timeout after 2s (reason=timeout)"* ]]
}
@test "step: timeout: 2000 is refused by the shared validator, 900 accepted" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-verification-pattern.sh"
  run _aid_vp_validate $'AC1\x1ft\x1fcmd\x1ftrue\x1f\x1f\x1f0\x1f2000'
  [ "$status" -eq 1 ]; [[ "$output" == *"timeout '2000' must be whole seconds from 1 to 1800"* ]]
  run _aid_vp_validate $'AC1\x1ft\x1fcmd\x1ftrue\x1f\x1f\x1f0\x1f900'
  [ "$status" -eq 0 ]
}
@test "step: a deferred.json entry whose card the PM never answered is dropped and the point refuses" {
  _pj "3:AC2"
  _card AC2
  mkdir -p "$EV/cp2/step-0"
  jq -n --arg c "$CARD" '{AC2: {by: "pm", reason: "the PM moved this point to the close", card: $c}}' > "$EV/cp2/step-0/deferred.json"
  _run --step 0; echo "$output"; [ "$status" -eq 1 ]
  [[ "$output" == *"deferral of AC2 not honoured: no PM prompt after"* ]]
  [ "$(_out 0 | jq -r '.results[0].deferred')" = null ]
}
@test "step: an answered deferral is merged into the results after a re-measurement, and the point no longer refuses" {
  _pj "3:AC2"
  _card AC2 answered
  mkdir -p "$EV/cp2/step-0"
  jq -n --arg c "$CARD" '{AC2: {by: "pm", reason: "the PM moved this point to the close", card: $c}}' > "$EV/cp2/step-0/deferred.json"
  _run --step 0; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r '.results[0].verdict')" = absent ]
  [ "$(_out 0 | jq -r '.results[0].deferred.by')" = pm ]
  [ "$(_out 0 | jq -r '.summary.absent_count')" = 0 ]
}

# ── P110 Step 3: the close's measurer runs in isolation ───────────────────
# _iplan <cmd>... — a plan whose AC<k> runs the k-th command
_iplan() {
  local k=0 c
  { printf -- '---\nid: P951\n---\n# Plan\n\n## Acceptance Criteria\n\n'
    for c in "$@"; do k=$((k + 1)); printf -- '- [ ] AC%s: point %s\n' "$k" "$k"
      printf '  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: %s\n    expected_exit: 0\n  ```\n' "$c"; done
  } > "$PLAN"
}
_irun() { run env -u FOO_TEST_DATABASE_URL bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD --isolated "$@"; }
_v() { jq -r --arg l "$1" '.results[] | select(.ac_label == $l) | .verdict' "$EV/plan-diff.json"; }
_e() { jq -r --arg l "$1" '.results[] | select(.ac_label == $l) | .evidence' "$EV/plan-diff.json"; }
_nsprobe() {
  local f; f="$(mktemp)"; echo true > "$f"
  env -i PATH="$PATH" unshare -rn --pid --fork sh -c 'ip link set lo up 2>/dev/null; exec unshare --map-user="$1" --map-group="$2" bash "$3"' _ "$(id -u)" "$(id -g)" "$f" >/dev/null 2>&1 \
    || { rm -f "$f"; skip "unshare --map-user refused on this host"; }
  rm -f "$f"
}
# _listen — a python http server on a free port outside any namespace; sets PORT
_listen() {
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
  python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 & LPID=$!
  for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && return 0; sleep 0.1; done
  return 1
}
_unlisten() { kill "$LPID" 2>/dev/null || true; }

@test "isolation: without verification_env a host listener is unreachable inside, network: unshare is recorded" {
  _nsprobe; _listen
  _iplan "\"curl -sf -o /dev/null http://127.0.0.1:${PORT}/\""
  _irun; _unlisten; echo "$output"
  [ "$(_v AC1)" = absent ]
  [ "$(jq -r .isolation.network "$EV/plan-diff.json")" = unshare ]
}
@test "isolation: a listener started inside the namespace answers (loopback is up)" {
  _nsprobe
  _iplan "\"python3 -m http.server 18766 --bind 127.0.0.1 >/dev/null 2>&1 & for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf -o /dev/null http://127.0.0.1:18766/ && exit 0; sleep 0.3; done; exit 1\""
  _irun; echo "$output"
  [ "$(_v AC1)" = present ]
}
@test "isolation: the caller's uid inside (not 0), and a chmod 000 file is unreadable" {
  _nsprobe
  echo secret > locked.txt; chmod 000 locked.txt
  _iplan "\"test \\\"\$(id -u)\\\" = $(id -u)\"" "\"cat locked.txt\""
  _irun; echo "$output"; chmod 600 locked.txt
  [ "$(_v AC1)" = present ]
  [ "$(_v AC2)" = absent ]
}
@test "isolation: a cmd with nested quotes and \$x reaches bash once (no re-parsing)" {
  _nsprobe
  printf 'a: b\n' > f.yaml
  _iplan "\"yq -e '.a == \\\"b\\\"' f.yaml && for s in 1 2; do test \$s -gt 0; done\""
  _irun; echo "$output"
  [ "$(_v AC1)" = present ]
}
@test "isolation: with verification_env the host listener is reachable, the variable visible, network: host (verification_env)" {
  _listen
  mkdir -p .aid-o/config
  printf 'verification_env:\n  SVC_URL: "http://127.0.0.1:%s/"\n' "$PORT" > .aid-o/config/execution.yaml
  _iplan '"curl -sf -o /dev/null \"$SVC_URL\""'
  _irun; _unlisten; echo "$output"
  [ "$(_v AC1)" = present ]
  [ "$(jq -r .isolation.network "$EV/plan-diff.json")" = "host (verification_env)" ]
  [ "$(jq -c .isolation.env_keys "$EV/plan-diff.json")" = '["SVC_URL"]' ]
}
@test "isolation: without unshare on PATH every cmd is absent (reason=no_isolation), never present, with next:" {
  _iplan '"true"'
  local bin="$ROOT/bin"; mkdir -p "$bin"
  for c in bash env jq yq git date sha256sum cut grep awk sed mktemp head tr cat rm mkdir dirname basename sort timeout id ls; do
    p="$(command -v "$c")" && ln -sf "$p" "$bin/$c"; done
  run env -u FOO_TEST_DATABASE_URL PATH="$bin" bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD --isolated
  echo "$output"
  [ "$(_v AC1)" = absent ]
  [ "$(jq -r '.results[0].reason' "$EV/plan-diff.json")" = no_isolation ]
  [[ "$output" == *"next: install util-linux"* ]]
}
@test "isolation: a cmd naming a database URL without verification_env is absent (reason=no_verification_env)" {
  _nsprobe
  _iplan '"psql postgresql://localhost/x -c 1"'
  _irun
  [ "$(jq -r '.results[0].reason' "$EV/plan-diff.json")" = no_verification_env ]
}
@test "isolation: an undeclared test variable in the host environment makes every cmd absent (env_stripped) with next:" {
  _iplan '"true"'
  run env FOO_TEST_DATABASE_URL=postgresql://x bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD --isolated
  echo "$output"
  [ "$(_v AC1)" = absent ]
  [[ "$(_e AC1)" == *"reason=env_stripped: FOO_TEST_DATABASE_URL"* ]]
  [[ "$output" == *"next: declare FOO_TEST_DATABASE_URL in verification_env"* ]]
}
@test "isolation: a verification_env value naming an unset host variable is absent (verification_env_unset)" {
  mkdir -p .aid-o/config; printf 'verification_env:\n  DB: "${NOPE}"\n' > .aid-o/config/execution.yaml
  _iplan '"true"'
  run env -u NOPE bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD --isolated
  [[ "$(_e AC1)" == *"reason=verification_env_unset: NOPE"* ]]
}
@test "isolation: --cwd on a plain directory exits 3 cwd_not_worktree" {
  _iplan '"true"'
  mkdir -p /tmp/claude-pd-plain-$$
  _irun --cwd /tmp/claude-pd-plain-$$; rmdir /tmp/claude-pd-plain-$$
  [ "$status" -eq 3 ]; [[ "$output" == *"cwd_not_worktree"*"next:"* ]]
}
@test "isolation: --cwd <worktree> takes that worktree's HEAD, reads file points there, records isolation.worktree" {
  _nsprobe
  git worktree add -q -b cand "$ROOT/cand"; echo marker > "$ROOT/cand/only-here.txt"; git -C "$ROOT/cand" add only-here.txt; git -C "$ROOT/cand" commit -qm cand
  { printf -- '---\nid: P952\n---\n# Plan\n\n## Acceptance Criteria\n\n- [ ] AC1: only in the candidate\n'
    printf '  ```yaml\n  verification_pattern:\n    type: must_contain\n    file: only-here.txt\n    regex: marker\n  ```\n'
    printf -- '- [ ] AC2: cmd in the candidate\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "test -f only-here.txt"\n    expected_exit: 0\n  ```\n'; } > "$PLAN"
  _irun --cwd "$ROOT/cand"; echo "$output"
  [ "$(_v AC1)" = present ] && [ "$(_v AC2)" = present ]
  [ "$(jq -r .head_commit "$EV/plan-diff.json")" = "$(git -C "$ROOT/cand" rev-parse HEAD)" ]
  [ "$(jq -r .isolation.worktree "$EV/plan-diff.json")" = "$ROOT/cand" ]
}
@test "isolation: --cwd on a subdirectory of a worktree exits 3 (points run from the worktree's top)" {
  _iplan '"true"'; mkdir -p sub
  _irun --cwd "$ROOT/sub"; [ "$status" -eq 3 ]; [[ "$output" == *"cwd_not_worktree"* ]]
}
@test "isolation: each point's command is kept as cmd-<label>.sh" {
  _nsprobe
  _iplan '"true"' '"test 1 = 1"'
  _irun; [ "$status" -eq 0 ]
  grep -qx 'true' "$EV/cmd-AC1.sh" && grep -qx 'test 1 = 1' "$EV/cmd-AC2.sh"
}
