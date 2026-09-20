#!/usr/bin/env bash
# =============================================================================
# lib/aid-permissions.sh — THE reader for what a workspace has authorised
# (P090 simplify pass)
#
#   aid_autonomous_mode <project_root>   echoes `auto` or `manual`
#
# WHY IT EXISTS. The same five lines had been written four times — in
# `aid-release-policy.sh` (`_read_autonomous_mode`), in `aid-config-summary.sh`,
# and twice more by P090 — and each copy's comment named one of the others as
# the original it was following. That is the honest signature of a missed
# extraction, and this is security-shaped logic: it answers "may this workspace
# act without a human". Four independent implementations of that question is
# how three of them silently drift the day the key moves or gains a nested
# form.
#
# FAIL-CLOSED, AND THE ASYMMETRY IS THE POINT. Only a real YAML boolean
# `autonomous_mode: true` is `auto`. A missing file, a missing `yq`, a missing
# key, the STRING "true", a number, an unreadable file — all `manual`. Reading
# manual as auto costs a workspace that acts without being asked; reading auto
# as manual costs a workspace that waits.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-09-20
# =============================================================================
[[ -n "${_AID_PERMISSIONS_SH_LOADED:-}" ]] && return 0
_AID_PERMISSIONS_SH_LOADED=1

# aid_autonomous_mode <project_root> — `auto` or `manual`, never empty.
#
# One `yq` invocation, not two: the type and the value come back together, so
# the reader costs one process rather than the two every hand-rolled copy spent.
# Precedence, highest first (P095):
#   1. auto-mode-state.yaml says manual — a PM stop always wins, including over
#      a controller that already exported AID_AUTO_MODE=1;
#   2. AID_AUTO_MODE=1 — this controller announced itself;
#   3. auto-mode-state.yaml says auto — a run that announced itself earlier;
#   4. permissions.yaml, as before.
# The file is a persisted INPUT of this one reader, never a second reader.
aid_autonomous_mode() {
  local root="${1%/}"
  local perm="${root}/.aid-o/config/permissions.yaml"
  local state="${root}/.aid-o/work/auto-mode-state.yaml"
  local smode=""
  if [[ -f "$state" ]]; then
    smode="$(sed -nE 's/^mode:[[:space:]]*"?([a-z]+)"?[[:space:]]*$/\1/p' "$state" | head -1)"
  fi
  [[ "$smode" == manual ]] && { echo manual; return 0; }
  [[ "${AID_AUTO_MODE:-}" == "1" ]] && { echo auto; return 0; }
  [[ "$smode" == auto ]] && { echo auto; return 0; }
  [[ -f "$perm" ]] || { echo manual; return 0; }
  command -v yq >/dev/null 2>&1 || { echo manual; return 0; }
  local pair
  pair="$(yq -r '[(.autonomous_mode | type), (.autonomous_mode | tostring)] | join("\t")' \
          "$perm" 2>/dev/null)" || { echo manual; return 0; }
  local vtype="${pair%%$'\t'*}" vval="${pair##*$'\t'}"
  [[ "$vtype" == "!!bool" && "$vval" == "true" ]] && echo auto || echo manual
  return 0
}
