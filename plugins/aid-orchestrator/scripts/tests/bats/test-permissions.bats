#!/usr/bin/env bats
# aid-tier: t0
# test-permissions.bats — aid_autonomous_mode, the ONE reader of auto-vs-manual
# (lib/aid-permissions.sh, declared as such by P090).
#
# THE GROUNDED FAILURE MODE: /aid-run --auto and /aid-stop both name
# .aid-o/work/auto-mode-state.yaml, and until P095 no script wrote it, so every
# later decision point of an AUTO run read "manual" (ACTA P024). The file is now
# written by `aid-fsm.sh auto-mode set` and read here — and a PM stop in it beats
# a controller that exported AID_AUTO_MODE=1, because a stop that can be
# overridden by the thing it stops is not a stop.
# Origin: P095 Step 7.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FSM="$PLUGIN_ROOT/scripts/aid-fsm.sh"
  source "$PLUGIN_ROOT/scripts/lib/aid-permissions.sh"
  ROOT="$(mktemp -d)"
  git -C "$ROOT" init -q .
  mkdir -p "$ROOT/.aid-o/config" "$ROOT/.aid-o/work"
  unset AID_AUTO_MODE
}
teardown() { rm -rf "$ROOT"; }

_set() { AID_PROJECT_ROOT="$ROOT" bash "$FSM" auto-mode "$@" >/dev/null; }

@test "a state file written by auto-mode set auto is read as auto, with no AID_AUTO_MODE" {
  _set set auto --by "aid-run --auto"
  [ "$(aid_autonomous_mode "$ROOT")" = auto ]
  [ "$(AID_PROJECT_ROOT="$ROOT" bash "$FSM" auto-mode get)" = auto ]
}

@test "mode: manual in the state file wins over permissions.yaml allowing auto" {
  printf 'autonomous_mode: true\n' > "$ROOT/.aid-o/config/permissions.yaml"
  [ "$(aid_autonomous_mode "$ROOT")" = auto ]
  _set set manual --by pm --reason "/aid-stop command"
  [ "$(aid_autonomous_mode "$ROOT")" = manual ]
}

@test "a PM stop wins over an exported AID_AUTO_MODE=1" {
  _set set manual --by pm --reason "/aid-stop command"
  AID_AUTO_MODE=1
  export AID_AUTO_MODE
  [ "$(aid_autonomous_mode "$ROOT")" = manual ]
}

@test "auto-mode set refuses an unknown mode and a missing --by; get on no file is manual" {
  [ "$(AID_PROJECT_ROOT="$ROOT" bash "$FSM" auto-mode get)" = manual ]
  run env AID_PROJECT_ROOT="$ROOT" bash "$FSM" auto-mode set sideways --by pm
  [ "$status" -eq 2 ]
  run env AID_PROJECT_ROOT="$ROOT" bash "$FSM" auto-mode set auto
  [ "$status" -eq 2 ]; [[ "$output" == *"--by"* ]]
}

@test "a manual state file keeps the three fields /aid-stop used to write by hand" {
  _set set manual --by pm --reason "/aid-stop command"
  grep -q '^stopped_by: "pm"' "$ROOT/.aid-o/work/auto-mode-state.yaml"
  grep -q '^stop_reason: "/aid-stop command"' "$ROOT/.aid-o/work/auto-mode-state.yaml"
  grep -q '^stopped_at:' "$ROOT/.aid-o/work/auto-mode-state.yaml"
}
