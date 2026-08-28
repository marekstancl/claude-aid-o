#!/usr/bin/env bash
# aid-control-enforcement.sh — per-control enforcement resolution (P062 Step 11).
#
#   aid_control_enforcement <policy_file> <control_id> [policy_key]
#
# Echoes `observe` or `blocking`. Resolution order:
#   1. controls.<control_id>.enforcement   — the per-control override
#   2. <policy_key>                        — the file-wide default (default key:
#                                            `enforcement`)
#   3. observe                             — every "cannot tell" path
#
# WHY A LIBRARY AND NOT FIVE COPIES
#   aid-fsm.sh reads a global `.enforcement` at five separate sites, one per
#   control. Teaching each of them the override separately is how two of them
#   end up disagreeing in the blocking direction — the P084 incident, where two
#   copies of one classifier drifted and produced a deadlock. One function,
#   five callers.
#
# FAIL-SAFE IS OBSERVE, ALWAYS
#   A missing file, missing yq, unreadable YAML or an out-of-enum value all
#   resolve to `observe`. Promotion is the exceptional state and must be stated
#   explicitly; a parse failure must never be able to switch a control ON.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.

aid_control_enforcement() {
  local policy_file="${1-}" control_id="${2-}" policy_key="${3:-enforcement}"
  local result="observe"

  [[ -n "$policy_file" && -f "$policy_file" ]] || { printf 'observe'; return 0; }
  command -v yq >/dev/null 2>&1 || { printf 'observe'; return 0; }

  # File-wide default first, then let a per-control value override it.
  local file_level
  file_level="$(yq -r ".${policy_key} // \"observe\"" "$policy_file" 2>/dev/null || echo observe)"
  [[ "$file_level" == "blocking" ]] && result="blocking"

  if [[ -n "$control_id" ]]; then
    local per_control
    per_control="$(yq -r ".controls.\"${control_id}\".enforcement // \"\"" "$policy_file" 2>/dev/null || echo "")"
    case "$per_control" in
      blocking) result="blocking" ;;
      observe)  result="observe"  ;;
      # Anything else — absent, null, a typo — leaves the file-level answer in
      # place. A misspelled override must not silently promote OR silently
      # demote; it simply is not an override.
      *) : ;;
    esac
  fi

  printf '%s' "$result"
}

# aid_control_promotable <inventory_file> <control_id>
#   0 when the inventory says this control may be promoted at all. A control
#   absent from the inventory is NOT promotable: the table is the authority on
#   what exists, and an unknown id is a reason to stop rather than to guess.
aid_control_promotable() {
  local inv="${1-}" id="${2-}"
  [[ -n "$inv" && -f "$inv" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 1
  local v
  v="$(yq -r ".controls[] | select(.id == \"${id}\") | .promotable" "$inv" 2>/dev/null || echo "")"
  [[ "$v" == "true" ]]
}
