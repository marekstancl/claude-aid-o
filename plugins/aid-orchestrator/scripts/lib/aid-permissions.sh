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
# **Last Updated:** 2026-08-27
# =============================================================================
[[ -n "${_AID_PERMISSIONS_SH_LOADED:-}" ]] && return 0
_AID_PERMISSIONS_SH_LOADED=1

# aid_autonomous_mode <project_root> — `auto` or `manual`, never empty.
#
# One `yq` invocation, not two: the type and the value come back together, so
# the reader costs one process rather than the two every hand-rolled copy spent.
aid_autonomous_mode() {
  local perm="${1%/}/.aid-o/config/permissions.yaml"
  [[ -f "$perm" ]] || { echo manual; return 0; }
  command -v yq >/dev/null 2>&1 || { echo manual; return 0; }
  local pair
  pair="$(yq -r '[(.autonomous_mode | type), (.autonomous_mode | tostring)] | join("\t")' \
          "$perm" 2>/dev/null)" || { echo manual; return 0; }
  local vtype="${pair%%$'\t'*}" vval="${pair##*$'\t'}"
  [[ "$vtype" == "!!bool" && "$vval" == "true" ]] && echo auto || echo manual
  return 0
}
