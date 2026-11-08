#!/usr/bin/env bats
# aid-tier: t1
# test-ac-substitute.bats — aid-ac-substitute.sh and its use in aid-plan-diff.sh (3.16.0, K7): a point whose
# measuring command is defective is measured by an approved substitute while the plan stays byte for byte.
# Proves: plan_diff uses the substitute and says so; an edited entry, a changed plan command, a stand-in entry
# without a valid permission are ignored; the PM path needs the PM's words; aid_protected_impact lets kind
# ac_command through only with criterion, cmd_old and a different cmd_new.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_QUIET=1
  SUB="$AID_PLUGIN_PATH/scripts/aid-ac-substitute.sh"; PD="$AID_PLUGIN_PATH/scripts/aid-plan-diff.sh"
  ROOT="$(mktemp -d)"; cd "$ROOT"
  git init -q -b main .; git config user.email t@t; git config user.name t
  mkdir -p .aid-o/plans .aid-o/work/evidence/E-1/R-1 src
  echo 'marker `x`' > src/a.txt
  PLAN="$ROOT/.aid-o/plans/P960-x.md"
  # AC1's command looks in the wrong file: the point (the marker is there) is met, its command cannot pass
  printf -- '---\nid: P960\n---\n# Plan\n\n## Acceptance Criteria\n\n- [ ] AC1: the marker is there\n  ```yaml\n  verification_pattern:\n    type: cmd\n    cmd: "grep -q marker src/b.txt"\n    expected_exit: 0\n  ```\n' > "$PLAN"
  git add -A; git commit -qm init
  RUN="$ROOT/.aid-o/work/evidence/E-1/R-1"; printf 'plan_path: %s\n' "$PLAN" > "$RUN/fsm-state.yaml"
  EV="$ROOT/ev"; mkdir -p "$EV"
  F="$ROOT/.aid-o/work/evidence/P960/ac-substitutes.json"
  printf 'grep -q "marker" src/a.txt' > "$ROOT/new.cmd"
}
teardown() { cd /; rm -rf "$ROOT"; }
_pd() { run bash "$PD" --plan "$PLAN" --evidence-dir "$EV" --base-commit HEAD; }
_v() { jq -r '.results[0].verdict' "$EV/plan-diff.json"; }

@test "substitute: the PM's substitute measures the point, the result says so, the plan is unchanged" {
  local before; before="$(sha256sum "$PLAN")"
  _pd; [ "$(_v)" = absent ]
  run bash "$SUB" add --evidence-dir "$RUN" --criterion AC1 --cmd-file "$ROOT/new.cmd" --pm "PM 8. 11.: měř to tím opraveným grepem"; echo "$output"
  [ "$status" -eq 0 ]
  _pd; echo "$output"; [ "$(_v)" = present ]
  [ "$(jq -r '.results[0] | "\(.measured_with) \(.substitute_by)"' "$EV/plan-diff.json")" = "substitute pm" ]
  [[ "$(jq -r '.results[0].evidence' "$EV/plan-diff.json")" == *"the plan's: grep -q"* ]]
  [ "$(sha256sum "$PLAN")" = "$before" ]
}

@test "substitute: an edited entry or a changed plan command falls back to the plan's own command" {
  bash "$SUB" add --evidence-dir "$RUN" --criterion AC1 --cmd-file "$ROOT/new.cmd" --pm "PM 8. 11.: měř to tím opraveným grepem" >/dev/null
  jq '.[0].cmd_new = "true"' "$F" > f.t && mv f.t "$F"
  _pd; [ "$(_v)" = absent ]
  bash "$SUB" add --evidence-dir "$RUN" --criterion AC1 --cmd-file "$ROOT/new.cmd" --pm "PM 8. 11.: měř to tím opraveným grepem" >/dev/null
  sed -i 's|src/b.txt"|src/b.txt -s"|' "$PLAN"
  _pd; [ "$(_v)" = absent ]
}

@test "substitute: an entry written by hand (no line in the plan's ledger) is ignored" {
  bash "$SUB" add --evidence-dir "$RUN" --criterion AC1 --cmd-file "$ROOT/new.cmd" --pm "PM 8. 11.: měř to tím opraveným grepem" >/dev/null
  _pd; [ "$(_v)" = present ]
  : > "$ROOT/.aid-o/work/evidence/P960/delegated-disputes.jsonl"
  _pd; [ "$(_v)" = absent ]
}

@test "substitute: the PM path needs the PM's words; a stand-in entry without a valid permission is ignored" {
  run bash "$SUB" add --evidence-dir "$RUN" --criterion AC1 --cmd-file "$ROOT/new.cmd" --pm "ok"
  [ "$status" -eq 1 ]; [[ "$output" == *ac_substitute_pm_words* ]]
  local os; os="$(bash -c 'source "$1/scripts/lib/aid-verification-pattern.sh"; _aid_vp_parse_ac "$2" "Acceptance Criteria" | cut -d$'"'"'\x1f'"'"' -f4 | tr -d "\n" | sha256sum | cut -d" " -f1' _ "$AID_PLUGIN_PATH" "$PLAN")"
  mkdir -p "$(dirname "$F")"
  jq -n --arg os "$os" --arg n "$(cat "$ROOT/new.cmd")" --arg ns "$(printf '%s' "$(cat "$ROOT/new.cmd")" | sha256sum | cut -d' ' -f1)" \
    '[{criterion: "AC1", cmd_plan_sha256: $os, cmd_new: $n, cmd_new_sha256: $ns, by: "stand_in", auth: "/nowhere/stand-in/x/auth.json"}]' > "$F"
  _pd; [ "$(_v)" = absent ]
}

@test "protected: kind ac_command passes with criterion, cmd_old and a different cmd_new, else unevaluable" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-protected.sh"
  jq -n '{kind: "ac_command", criterion: "AC1", cmd_old: "grep a", cmd_new: "grep b", reason: "x"}' > p.json
  run aid_protected_impact "$ROOT" "$ROOT" p.json "$RUN"; [ "$status" -eq 0 ]
  jq '.cmd_new = "grep a"' p.json > p2.json
  run aid_protected_impact "$ROOT" "$ROOT" p2.json "$RUN"; [ "$status" -eq 1 ]; [[ "$output" == unevaluable:* ]]
  jq 'del(.criterion)' p.json > p3.json
  run aid_protected_impact "$ROOT" "$ROOT" p3.json "$RUN"; [ "$status" -eq 1 ]
}

@test "protected: a substitute is a read-only command from the allowlist naming no protected path, anything else is the PM's" {
  source "$AID_PLUGIN_PATH/scripts/lib/aid-protected.sh"
  local c
  for c in 'cat .env' 'grep -q x config/secrets.yml' 'grep -q x .aid-o/config/execution.yaml' 'grep -q x .e""nv' 'grep -q x .e*v' \
           'grep -q x $(echo .env)' 'bash -c "cat .env"' 'f=.env; grep -q x $f' 'grep -q x .aid-o/./config/execution.yaml' \
           'grep -q x .aid-o//config/execution.yaml' "python3 -c 'print(1)'" 'grep -r TOKEN .' "grep -q x \$'a'" 'grep -q x {a,b}' \
           'git show HEAD:.env' 'sh -xc x' 'grep -q x a > out'; do
    jq -n --arg c "$c" '{kind: "ac_command", criterion: "AC1", cmd_old: "grep a", cmd_new: $c, reason: "x"}' > p.json
    run aid_protected_impact "$ROOT" "$ROOT" p.json "$RUN"; echo "$c → $output"
    [ "$status" -eq 1 ]; [[ "$output" == security:* || "$output" == gate:* || "$output" == unevaluable:* ]]
  done
  # an ordinary measuring command with quotes and a regex stays technical
  jq -n '{kind: "ac_command", criterion: "AC1", cmd_old: "grep a", cmd_new: "grep -qE '"'"'foo.*bar|[`]x'"'"' src/a.txt", reason: "x"}' > p.json
  run aid_protected_impact "$ROOT" "$ROOT" p.json "$RUN"; echo "$output"; [ "$status" -eq 0 ]
}

@test "substitute: an entry that does not hold says why in the point's evidence" {
  bash "$SUB" add --evidence-dir "$RUN" --criterion AC1 --cmd-file "$ROOT/new.cmd" --pm "PM 8. 11.: měř to tím opraveným grepem" >/dev/null
  : > "$ROOT/.aid-o/work/evidence/P960/delegated-disputes.jsonl"
  _pd; [ "$(_v)" = absent ]
  [[ "$(jq -r '.results[0].evidence' "$EV/plan-diff.json")" == *"no record in the plan's ledger"* ]]
}
