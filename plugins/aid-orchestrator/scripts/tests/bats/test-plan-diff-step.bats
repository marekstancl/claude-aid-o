#!/usr/bin/env bats
# aid-tier: t1
# aid-subject: scripts/aid-plan-diff.sh
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
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC4") | .evidence')" == *"neměřeno: limit 2 s (reason=timeout)"* ]]
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
@test "isolation: --cwd on a directory that does not exist exits 3 cwd_not_worktree" {
  _iplan '"true"'
  _irun --cwd /nonexistent-p110; [ "$status" -eq 3 ]; [[ "$output" == *"cwd_not_worktree"* ]]
}

# ── foreign repositories (P112 Step 2) ───────────────────────────────────────
# _foreign [repo_roots] — a second repository F declared in repo_roots (unless
# "bare"), its plan worktree WT holding only-wt.md (absent from the live
# checkout) and lacking gone.md (present live); three points name the LIVE path.
_foreign() {
  FAR="$(mktemp -d)"; F="$FAR/docs"; mkdir -p "$F"; git -C "$F" init -q -b main
  git -C "$F" config user.email t@t; git -C "$F" config user.name t
  echo live > "$F/gone.md"; git -C "$F" add gone.md; git -C "$F" commit -qm init
  WT="$F/.aid-worktrees/plan-P953--docs"
  git -C "$F" worktree add -q -b "plan/P953-$(basename "$ROOT")" "$WT" main
  echo marker > "$WT/only-wt.md"; git -C "$WT" rm -q gone.md; git -C "$WT" add only-wt.md; git -C "$WT" commit -qm work
  local rr=""; [[ "${1:-}" == bare ]] || rr="repo_roots: [{name: docs, path: $F}]"
  { printf -- '---\nid: P953\n%s\n---\n# Plan\n\n### Step 1: one\n\n**Zavírá:** AC1, AC2, AC3\n\n## Acceptance Criteria\n\n' "$rr"
    printf -- '- [ ] AC1: in the worktree\n  ```yaml\n  verification_pattern:\n    type: must_contain\n    file: %s/only-wt.md\n    regex: marker\n  ```\n' "$F"
    printf -- '- [ ] AC2: deleted in the worktree\n  ```yaml\n  verification_pattern:\n    type: must_not_exist\n    file: %s/gone.md\n  ```\n' "$F"
    printf -- '- [ ] AC3: a command on the live path\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "grep -q marker %s/only-wt.md && test ! -e %s/gone.md"\n    expected_exit: 0\n  ```\n' "$F" "$F"
  } > "$PLAN"
}
_verdicts() { jq -c '[.results[] | .verdict]' "$1"; }

@test "foreign-read: after a step (plan.json with repo_roots) every point is measured in the plan's worktree" {
  _foreign
  jq -n --arg f "$F" --arg wt "$WT" --arg br "plan/P953-$(basename "$ROOT")" \
    '{repo_roots: [{name: "docs", path: $f, worktree: $wt, branch: $br}], steps: [{id: "step_1_backend", plan_step: 1, zavira: ["AC1", "AC2", "AC3"]}]}' > "$ROOT/plan.json"
  _run --step 0; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_verdicts "$EV/cp2/step-0/plan-diff.json")" = '["present","present","present"]' ]
  [[ "$(_out 0 | jq -r '.results[0].evidence')" == *"$WT/only-wt.md"*"plan's worktree"* ]]
  [ ! -e "$F/only-wt.md" ] && [ -e "$F/gone.md" ]     # the live checkout is untouched
  rm -rf "$FAR"
}
@test "foreign-read: the plan-scope measurement maps from the plan file's own repo_roots" {
  _foreign
  run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_verdicts "$EV/plan-diff.json")" = '["present","present","present"]' ]
  rm -rf "$FAR"
}
@test "foreign-read: at the close (--isolated --cwd <candidate>) the points read the foreign worktree too" {
  _nsprobe; _foreign
  git worktree add -q -b cand "$ROOT/cand"
  _irun --cwd "$ROOT/cand"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_verdicts "$EV/plan-diff.json")" = '["present","present","present"]' ]
  grep -q "$WT/only-wt.md" "$EV/cmd-AC3.sh" && ! grep -q "$F/only-wt.md" "$EV/cmd-AC3.sh"   # the isolated command file carries the rewrite
  [[ "$(_e AC2)" == *"read $WT/gone.md"* && "$(_e AC3)" == *"read in: $WT"* ]]                # the evidence names what was read
  rm -rf "$FAR"
}
@test "foreign-read: a declared repository whose worktree is gone gives foreign_worktree_missing, never a live read" {
  _foreign
  git -C "$F" worktree remove --force "$WT"
  echo marker > "$F/only-wt.md"; rm "$F/gone.md"        # the live checkout would pass
  run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD; [ "$status" -eq 1 ]
  [ "$(jq -r '[.results[] | .reason] | unique | join(",")' "$EV/plan-diff.json")" = foreign_worktree_missing ]
  rm -rf "$FAR"
}
@test "foreign-read: a plan without repo_roots measures the live path as before" {
  _foreign bare
  run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD; [ "$status" -eq 1 ]
  [ "$(_verdicts "$EV/plan-diff.json")" = '["absent","absent","absent"]' ]
  rm -rf "$FAR"
}
@test "timeout: the floor raises a point's own timeout: 1 so sleep 2 is measured present" {
  { printf -- '---\nid: P954\n---\n# Plan\n\n## Acceptance Criteria\n\n- [ ] AC1: slow\n'; _blk "sleep 2" 1; } > "$PLAN"
  AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=5 run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD; echo "$output"; [ "$status" -eq 0 ]
  [ "$(jq -r '.results[0].verdict' "$EV/plan-diff.json")" = present ]
  AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=2000 run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD; [ "$status" -eq 10 ]
}

@test "verification_env: the step measurement runs with the project's verification_env (names in the result, never values) — the same reader as the close" {
  mkdir -p .aid-o/config; printf 'verification_env:\n  WAN_TEST_DOCKER_MODE: run\n' > .aid-o/config/execution.yaml
  _pj "1:AC1"
  { printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n### Step 1: one\n\n**Zavírá:** AC1\n\n## Acceptance Criteria\n\n- [ ] AC1: env\n'; _blk 'test \"$WAN_TEST_DOCKER_MODE\" = run'; } > "$PLAN"
  _run --step 0; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r '.results[0].verdict')" = present ]
  [ "$(_out 0 | jq -c .env_keys)" = '["WAN_TEST_DOCKER_MODE"]' ]
  ! grep -q '"run"' "$EV/cp2/step-0/plan-diff.json"
}

@test "effective timeout: a point without timeout: gets the plan_diff gate's timeout_seconds, its own timeout: wins, the floor raises, 1800 is the ceiling" {
  mkdir -p .aid-o/config; printf 'gates:\n  plan_diff:\n    timeout_seconds: 600\n' > .aid-o/config/execution.yaml
  _pj "1:AC1,AC4"
  { printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n### Step 1: one\n\n**Zavírá:** AC1, AC4\n\n## Acceptance Criteria\n\n- [ ] AC1: plain\n'; _blk "true"; printf -- '- [ ] AC4: own\n'; _blk "true" 7; } > "$PLAN"
  _run --step 0; [ "$status" -eq 0 ]
  [ "$(_out 0 | jq -r .ac_timeout_default_s)" = 600 ]
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC1") | .evidence')" == *"limit 600 s"* ]]
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC4") | .evidence')" == *"limit 7 s"* ]]
  AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=30 _run --step 0
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC4") | .evidence')" == *"limit 30 s"* ]]
  printf 'gates:\n  plan_diff:\n    timeout_seconds: 5000\n' > .aid-o/config/execution.yaml
  _run --step 0; [ "$(_out 0 | jq -r .ac_timeout_default_s)" = 1800 ]
  printf 'gates:\n  plan_diff:\n    timeout_seconds: 600\n' > .aid-o/config/execution.yaml
  AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=900 _run --step 0
  [[ "$(_out 0 | jq -r '.results[] | select(.ac_label == "AC1") | .evidence')" == *"limit 900 s"* ]]
  AID_PLAN_DIFF_AC_TIMEOUT=50 _run --step 0; [ "$(_out 0 | jq -r .ac_timeout_default_s)" = 600 ]   # the env replaces the 120 base, a larger gate still wins
  AID_PLAN_DIFF_AC_TIMEOUT=900 _run --step 0; [ "$(_out 0 | jq -r .ac_timeout_default_s)" = 900 ]
  rm .aid-o/config/execution.yaml
  _run --step 0; [ "$(_out 0 | jq -r .ac_timeout_default_s)" = 120 ]
}

@test "redact: a failing point's output is kept (8 KiB per stream, truncation said), the verification_env value and token-shaped strings never reach the disk" {
  mkdir -p .aid-o/config; printf 'verification_env:\n  DB_PASSWORD: hunter2-canary\n' > .aid-o/config/execution.yaml
  _pj "1:AC1"
  { printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n### Step 1: one\n\n**Zavírá:** AC1\n\n## Acceptance Criteria\n\n- [ ] AC1: fails loudly\n'; _blk 'echo pw=$DB_PASSWORD; echo Bearer abc.def.ghi; echo ghp_ABCDEFGHIJKLMNOPQRSTUV >&2; head -c 20000 /dev/zero | tr "\\\\0" a; echo; echo tail=$DB_PASSWORD; printf x=hunter2-; sleep 0.2; printf "canary\\n"; printf "Bearer " >&2; head -c 20000 /dev/zero | tr "\\\\0" Q >&2; echo >&2; echo end >&2; exit 2'; } > "$PLAN"
  _run --step 0
  local ev; ev="$(_out 0 | jq -r '.results[0].evidence')"; echo "$ev"
  [[ "$ev" == *"exit=2"*"output: ac-output/"* ]]
  local f="$EV/cp2/step-0/${ev##*output: }"; [ -f "$f" ]
  ! grep -q 'hunter2-canary' "$f"; ! grep -q 'abc.def.ghi' "$f"; ! grep -q 'ghp_ABCDEF' "$f"
  grep -q 'last 8192 shown' "$f"; grep -q '\[redigováno\]' "$f"
  grep -q 'tail=\[redigováno\]' "$f"   # the value after 20 KB of output, in the kept tail, is redacted too
  grep -q 'x=\[redigováno\]' "$f"      # and so is one written in two pieces (two reads of the filter)
  ! grep -q 'QQQQ' "$f"; grep -q '^end' "$f"   # a token longer than the kept tail: its prefix-less end is dropped
  # a connection string: the value of a *_URL variable with a password, and userinfo in any URL (security review)
  export APP_DATABASE_URL="postgres://app:pw-canary-77@db:5432/app"
  { printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n### Step 1: one\n\n**Zavírá:** AC1\n\n## Acceptance Criteria\n\n- [ ] AC1: urls\n'; _blk 'echo db=$APP_DATABASE_URL; echo other=redis://bob:pw-canary-88@cache:6379; exit 3'; } > "$PLAN"
  _run --step 0; ev="$(_out 0 | jq -r '.results[0].evidence')"; f="$EV/cp2/step-0/${ev##*output: }"
  ! grep -q 'pw-canary-77' "$f"; ! grep -q 'pw-canary-88' "$f"; grep -q 'redis://\[redigováno\]@cache' "$f"
  unset APP_DATABASE_URL
  # while the point runs, no file anywhere it could land (temp dir, evidence) holds the raw value (Codex, P117 A+C)
  mkdir -p "$ROOT/tmp"; export TMPDIR="$ROOT/tmp" SCAN="$ROOT"
  { printf -- '---\nid: P950\n---\n# Plan\n\n## Implementation Steps\n\n### Step 1: one\n\n**Zavírá:** AC1\n\n## Acceptance Criteria\n\n- [ ] AC1: scans\n'; _blk 'echo pw=$DB_PASSWORD; echo e=$DB_PASSWORD >&2; sleep 0.3; c=hunter2-; grep -rla --exclude-dir=.aid-o --exclude=execution.yaml "${c}canary" "$SCAN" "$TMPDIR" >&2 && exit 7; exit 2'; } > "$PLAN"
  _run --step 0
  ev="$(_out 0 | jq -r '.results[0].evidence')"; echo "$ev"; cat "$EV/cp2/step-0/${ev##*output: }"
  [[ "$ev" == *"exit=2"* ]]   # 7 = the command found the raw value in a file while it ran
  ! grep -rqa --exclude-dir=.aid-o --exclude=execution.yaml hunter2-canary "$ROOT" "$TMPDIR"
}
