#!/usr/bin/env bash
# =============================================================================
# lib/aid-ac-command.sh — is an acceptance criterion a command criterion? (AID 3.13.0)
#
#   AID_AC_COMMAND_JQ   a jq definition: `ac_command` on a criterion (string) gives its command, or null
#
# A criterion is a command criterion when its text BEGINS with a backticked text that is written as a command:
# it holds a space or a slash (`pytest -q x`, `./check.sh`, `scripts/check.sh`, `VAR=v cmd`). One word without a
# space or a slash is a NAME, never a command (`test_regime_x`, `a::b`, `check.sh`, `pytest`, `NAME=value`),
# whatever is installed: WAN P116 28. 10. and P118 30. 10. 2026 had criteria beginning with
# a test's name, and the takeover demanded that name as a runnable command. Read by aid-step-land.sh and
# lib/aid-land-record.sh, so the takeover and increment-step decide the same way.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_AC_COMMAND_SH_LOADED:-}" ]] && return 0
_AID_AC_COMMAND_SH_LOADED=1

# shellcheck disable=SC2016
AID_AC_COMMAND_JQ='
def ac_command:
  if type != "string" then null else
    ((first(capture("^`(?<c>[^`]+)`")) | .c) // null) as $c
    | if $c == null then null
      elif ($c | test("[ /]")) then $c
      else null end
  end;
'
