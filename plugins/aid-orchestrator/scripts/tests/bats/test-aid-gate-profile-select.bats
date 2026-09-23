#!/usr/bin/env bats
# aid-tier: t0
# WHY THIS FILE EXISTS (P097 Step 4): lib/aid-gate-profile-select.sh is the one
# resolver over a project's own gate_profiles table. This suite proves the
# selection rule (widest match wins, else default_profile), the refusals
# (unknown name, no default_profile, a profile with no required gate), the
# rank-by-declaration-index, and the GATES:DONE floor verdict on the merge
# path (test-aid-fsm.bats is t2): a report with no profile, a narrower index,
# and a table that changed since the run. It also replays the resolver on the
# ACTA and WAN fixtures upgraded by Step 3 (see the last two cases).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT AID_PLUGIN_PATH="$PLUGIN_ROOT"
  SEL="$PLUGIN_ROOT/scripts/lib/aid-gate-profile-select.sh"
  UPG="$PLUGIN_ROOT/scripts/lib/aid-init-execution-yaml.sh"
  export SEL UPG
  WORK="$(mktemp -d)"
  export WORK
  YAML="$WORK/execution.yaml"
  cat > "$YAML" <<'YAML'
gates:
  lint:
    command: "true"
    required: false
  unit:
    command: "true"
    required: true
  e2e:
    command: "true"
    required: true
default_profile: standard
gate_profiles:
  targeted:
    include: [lint, unit]
    when_paths: ["src/*"]
  standard:
    include: [unit]
  full:
    include: [unit, e2e]
    when_paths: ["*/aid-fsm.sh", "defaults/schemas/*"]
  release:
    include: [unit, e2e, lint]
YAML
}

teardown() { [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"; }

_paths() { local f="$WORK/paths"; : > "$f"; printf '%s\n' "$@" >> "$f"; echo "$f"; }

# _report <profile|""> <table json> [gate ...] — a minimal gates_report.json.
_report() {
  local profile="$1" table="$2"; shift 2
  local rows="{}" g
  for g in "$@"; do rows="$(jq -c --arg g "$g" '.[$g] = {status: "pass"}' <<<"$rows")"; done
  jq -nc --arg p "$profile" --argjson t "$table" --argjson rows "$rows" \
    '{profile: (if $p == "" then null else $p end), profile_table: $t, gates: $rows}' > "$WORK/report.json"
  echo "$WORK/report.json"
}

_upgraded_fixture() {  # <project> — the Step 3 upgrade applied to the fixture copy
  local f="$WORK/$1.yaml" hash
  cp "$PLUGIN_ROOT/scripts/tests/fixtures/gates/projects/$1.yaml" "$f"
  hash="$(bash "$UPG" upgrade "$f" | sed -n 's/^diff_hash: //p')"
  bash "$UPG" upgrade "$f" --confirm-upgrade "$hash" >/dev/null
  echo "$f"
}

@test "widest match wins: a src path picks targeted, a high-risk path anywhere in the set picks full" {
  run bash "$SEL" for-paths "$YAML" "$(_paths src/a.ts)"
  [ "$status" -eq 0 ]; [ "$output" = "targeted" ]
  run bash "$SEL" for-paths "$YAML" "$(_paths src/a.ts docs/x.md plugins/aid-orchestrator/scripts/aid-fsm.sh)"
  [ "$status" -eq 0 ]; [ "$output" = "full" ]
}

@test "no match, an empty set and a missing paths file all fall to default_profile" {
  run bash "$SEL" for-paths "$YAML" "$(_paths docs/readme.md)"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
  run bash "$SEL" for-paths "$YAML" "$(_paths)"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
  run bash "$SEL" for-paths "$YAML" "$WORK/does-not-exist"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
}

@test "a profile without when_paths (release) is never auto-selected" {
  run bash "$SEL" for-paths "$YAML" "$(_paths src/a.ts plugins/aid-orchestrator/scripts/aid-fsm.sh anything/else)"
  [ "$status" -eq 0 ]; [ "$output" = "full" ]
}

@test "gate_profiles without default_profile → exit 2 naming the upgrade command" {
  yq -i 'del(.default_profile)' "$YAML"
  run bash "$SEL" for-paths "$YAML" "$(_paths docs/x.md)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"default_profile"* ]]
  [[ "$output" == *"aid-init-execution-yaml.sh upgrade"* ]]
  # an undeclared default is the same refusal
  yq -i '.default_profile = "nope"' "$YAML"
  run bash "$SEL" for-paths "$YAML" "$(_paths docs/x.md)"
  [ "$status" -eq 2 ]
}

@test "a file with no gate_profiles resolves to nothing (exit 0, empty) — every gate runs" {
  yq -i 'del(.gate_profiles) | del(.default_profile)' "$YAML"
  run bash "$SEL" for-paths "$YAML" "$(_paths plugins/aid-orchestrator/scripts/aid-fsm.sh)"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash "$SEL" table "$YAML"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "unknown name → exit 1 from index/exists; index is the declaration order of a four-profile table" {
  run bash "$SEL" index "$YAML" nope
  [ "$status" -eq 1 ]; [ -z "$output" ]
  run bash "$SEL" exists "$YAML" nope
  [ "$status" -eq 1 ]
  run bash "$SEL" table "$YAML"
  [ "$output" = $'targeted\nstandard\nfull\nrelease' ]
  [ "$(bash "$SEL" index "$YAML" targeted)" = 0 ]
  [ "$(bash "$SEL" index "$YAML" standard)" = 1 ]
  [ "$(bash "$SEL" index "$YAML" full)" = 2 ]
  [ "$(bash "$SEL" index "$YAML" release)" = 3 ]
  [ "$(bash "$SEL" wider "$YAML" standard full)" = full ]
  [ "$(bash "$SEL" wider "$YAML" release standard)" = release ]
  [ "$(bash "$SEL" wider "$YAML" nope standard)" = standard ]
  run bash "$SEL" wider "$YAML" nope also-nope
  [ "$status" -eq 1 ]
}

@test "a profile with no required gate is refused at resolve, naming the gates" {
  yq -i '.gate_profiles.standard.include = ["lint"]' "$YAML"
  run bash "$SEL" for-paths "$YAML" "$(_paths docs/x.md)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"standard"* ]]; [[ "$output" == *"lint"* ]]; [[ "$output" == *"no required gate"* ]]
  run bash "$SEL" has-required-gate "$YAML" standard
  [ "$status" -ne 0 ]
  run bash "$SEL" has-required-gate "$YAML" full
  [ "$status" -eq 0 ]
  # a matched when_paths profile is refused the same way — never an all-skip pass
  yq -i '.gate_profiles.targeted.include = []' "$YAML"
  run bash "$SEL" for-paths "$YAML" "$(_paths src/a.ts)"
  [ "$status" -eq 2 ]; [[ "$output" == *"targeted"* ]]
}

@test "only required: true counts as required (required_when is dead since P097 Step 6; the composer writes required: true)" {
  yq -i '.gates.unit = {"command": "true", "required": true}' "$YAML"
  run bash "$SEL" has-required-gate "$YAML" standard
  [ "$status" -eq 0 ]
  yq -i '.gates.unit = {"command": "true", "required_when": "*.ts exists"}' "$YAML"
  run bash "$SEL" has-required-gate "$YAML" standard
  [ "$status" -ne 0 ]
  yq -i '.gates.unit = {"command": "true", "required": false}' "$YAML"
  run bash "$SEL" has-required-gate "$YAML" standard
  [ "$status" -ne 0 ]
}

@test "floor: a report with no profile fails risk_profile_unresolvable when the file declares gate_profiles" {
  local rep; rep="$(_report "" '["targeted","standard","full","release"]' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep" standard
  [ "$status" -eq 1 ]
  [[ "$output" == risk_profile_unresolvable:* ]]
  [[ "$output" == *"names no profile"* ]]
}

@test "floor: a narrower index than the resolver's answer fails risk_profile_below_required; equal or wider passes" {
  local rep; rep="$(_report standard '["targeted","standard","full","release"]' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep" full
  [ "$status" -eq 1 ]; [[ "$output" == risk_profile_below_required:* ]]
  run bash "$SEL" floor-verdict "$YAML" "$rep" standard
  [ "$status" -eq 0 ]; [ "$output" = ok ]
  rep="$(_report release '["targeted","standard","full","release"]' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep" full
  [ "$status" -eq 0 ]; [ "$output" = ok ]
  # no required (base_commit unknown): the recorded name and table still have to hold
  rep="$(_report standard '["targeted","standard","full","release"]' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep"
  [ "$status" -eq 0 ]
}

@test "floor: a profile_table that differs from the file's order fails profile_table_changed" {
  local rep; rep="$(_report full '["standard","targeted","full","release"]' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep" standard
  [ "$status" -eq 1 ]; [[ "$output" == profile_table_changed:* ]]
  # a legacy report with no profile_table at all is the same refusal
  rep="$(_report full 'null' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep" standard
  [ "$status" -eq 1 ]; [[ "$output" == profile_table_changed:* ]]
  # a recorded profile the table no longer declares is unresolvable
  rep="$(_report gone '["targeted","standard","full","release"]' unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep"
  [ "$status" -eq 1 ]; [[ "$output" == risk_profile_unresolvable:* ]]
}

@test "floor without a table: 'none' passes only when every declared gate has a row" {
  yq -i 'del(.gate_profiles) | del(.default_profile)' "$YAML"
  local rep; rep="$(_report "" '[]' lint unit e2e)"
  run bash "$SEL" floor-verdict "$YAML" "$rep"
  [ "$status" -eq 0 ]; [ "$output" = ok ]
  rep="$(_report "" '[]' lint unit)"
  run bash "$SEL" floor-verdict "$YAML" "$rep"
  [ "$status" -eq 1 ]; [[ "$output" == risk_profile_unresolvable:* ]]; [[ "$output" == *"e2e"* ]]
}

@test "usage: a missing file is exit 2, an unknown subcommand is exit 2" {
  run bash "$SEL" for-paths "$WORK/nope.yaml" /dev/null
  [ "$status" -eq 2 ]
  run bash "$SEL" bogus "$YAML"
  [ "$status" -eq 2 ]
}

# ── Replay on the ACTA and WAN fixtures upgraded by Step 3 ──────────────────
# The recovered changed-path sets of the sample EPIC runs (the 17 ACTA and 6
# WAN runs in fixtures/gates/gates-sample.json, base_commit..head_sha from the
# project checkouts) contain no path matching the classifier's high-risk list;
# the old resolver's timeline event for each of them says `standard`
# (ACTA's recorded `full` came from an explicit caller flag, profile_source
# cli_flag). The replay is therefore: an ordinary path set → standard, and a
# set containing a high-risk path → full (ACTA) / standard (WAN, no `full`
# profile), and `release` is never returned.
@test "replay: upgraded ACTA fixture — standard for the sample runs' shape, full on a high-risk path, never release" {
  local f; f="$(_upgraded_fixture acta)"
  run bash "$SEL" table "$f"
  [ "$output" = $'targeted\nstandard\nfull\nrelease\nrelease_quarantine' ]
  run bash "$SEL" for-paths "$f" "$(_paths backend/app/models.py frontend/src/App.tsx docs/x.md)"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
  run bash "$SEL" for-paths "$f" "$(_paths backend/app/models.py .aid-o/config/policies/x.yaml plugins/aid-orchestrator/agents/implementer.md)"
  [ "$status" -eq 0 ]; [ "$output" = "full" ]
  run bash "$SEL" for-paths "$f" "$(_paths .aid-o/plans/P099-x.md CHANGELOG.md)"
  [ "$output" = "standard" ]
  # release and release_quarantine carry no when_paths
  [ "$(yq '.gate_profiles.release | has("when_paths")' "$f")" = false ]
  [ "$(yq '.gate_profiles.release_quarantine | has("when_paths")' "$f")" = false ]
}

@test "replay: upgraded WAN fixture — standard everywhere (no full profile), never release" {
  local f; f="$(_upgraded_fixture wan)"
  run bash "$SEL" table "$f"
  [ "$output" = $'standard\nrelease' ]
  run bash "$SEL" for-paths "$f" "$(_paths wan/app.py tests/test_x.py)"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
  run bash "$SEL" for-paths "$f" "$(_paths plugins/aid-orchestrator/scripts/aid-run-gates.sh)"
  [ "$status" -eq 0 ]; [ "$output" = "standard" ]
}
