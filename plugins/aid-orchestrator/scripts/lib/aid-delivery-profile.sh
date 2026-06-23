#!/usr/bin/env bash
# =============================================================================
# aid-delivery-profile.sh — Delivery profile resolver library
#
# Source this file; exports resolve_profile() and select_commands()
#
# Usage:
#   source aid-delivery-profile.sh
#   resolve_profile <project_root> [<changed_paths_file>]
#   select_commands <policy_file> <profile> <check_id>
#
# resolve_profile:
#   Detects the ecosystem profile for <project_root> by evaluating detection
#   conditions declared in delivery-gate.yaml.  Prints the profile name on
#   stdout (e.g. "plugin-bash", "npm-workspaces+plugin-bash", "unverifiable").
#   Exits 0 on success, 1 on malformed policy.
#
# select_commands:
#   Resolves the argv array for <check_id> under <profile>.
#   Prints one argument per line (empty output = empty array = unverifiable).
#   NEVER returns a shell string — always line-delimited argv elements.
#   Exits 0 always (empty output is valid; caller decides unverifiable).
#
# Environment:
#   DELIVERY_GATE_POLICY — path to delivery-gate.yaml
#                          default: <plugin_root>/defaults/policies/delivery-gate.yaml
#
# Requirements: yq v4+, bash 4.0+
# Portability:  Linux + macOS
#
# Constraints (EPIC E-050):
#   - No eval, no shell expansion of command strings (injection safe)
#   - Malformed policy → exit 1, error to stderr (never silent fallback)
#   - Must be sourceable (no set -e at top level)
#   - Wrapper propagates real exit; inner check fail never reported as pass
# =============================================================================

# Guard: prevent direct execution — this file must be sourced, not run.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: aid-delivery-profile.sh must be sourced, not executed directly." >&2
  echo "Usage: source \"\$(dirname \"\$0\")/lib/aid-delivery-profile.sh\"" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# _delivery_profile_policy_file()
#
# Returns the canonical path to delivery-gate.yaml.
# Uses DELIVERY_GATE_POLICY env var if set, otherwise derives from script dir.
# ---------------------------------------------------------------------------
_delivery_profile_policy_file() {
  if [[ -n "${DELIVERY_GATE_POLICY:-}" ]]; then
    echo "$DELIVERY_GATE_POLICY"
    return
  fi
  # Derive plugin root from this file's location:
  #   <plugin_root>/scripts/lib/aid-delivery-profile.sh
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "${script_dir}/../../defaults/policies/delivery-gate.yaml"
}

# ---------------------------------------------------------------------------
# _delivery_profile_validate_policy(policy_file)
#
# Validate that the policy file exists and is parseable by yq.
# Prints error to stderr and returns 1 on failure.
# ---------------------------------------------------------------------------
_delivery_profile_validate_policy() {
  local policy_file="$1"

  if [[ ! -f "$policy_file" ]]; then
    echo "ERROR: delivery-gate policy not found: ${policy_file}" >&2
    return 1
  fi

  # Attempt to parse; yq exits non-zero on malformed YAML
  if ! yq e '.' "$policy_file" >/dev/null 2>&1; then
    echo "ERROR: malformed YAML in delivery-gate policy: ${policy_file}" >&2
    return 1
  fi

  # Confirm the policy has a profiles key (minimum structure check)
  local profiles_count
  profiles_count=$(yq e '.profiles | length' "$policy_file" 2>/dev/null) || {
    echo "ERROR: could not read .profiles from policy: ${policy_file}" >&2
    return 1
  }
  if [[ -z "$profiles_count" || "$profiles_count" == "null" || "$profiles_count" -eq 0 ]]; then
    echo "ERROR: delivery-gate policy has no profiles defined: ${policy_file}" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# _delivery_profile_check_detect(project_root, policy_file, profile_name)
#
# Evaluates all detect conditions for <profile_name> in <policy_file>.
# ALL conditions must be true (AND semantics).
# Returns 0 if profile matches, 1 if it does not.
# ---------------------------------------------------------------------------
_delivery_profile_check_detect() {
  local project_root="$1"
  local policy_file="$2"
  local profile_name="$3"

  # Get number of detect conditions for this profile
  local detect_count
  detect_count=$(yq e ".profiles.${profile_name}.detect | length" "$policy_file" 2>/dev/null)

  # Profile with empty detect array matches nothing (used for generic fallback)
  if [[ -z "$detect_count" || "$detect_count" == "null" || "$detect_count" -eq 0 ]]; then
    return 1
  fi

  # Check each detect condition — all must pass
  local i
  for (( i=0; i<detect_count; i++ )); do
    local file_path
    file_path=$(yq e ".profiles.${profile_name}.detect[${i}].file // \"\"" "$policy_file" 2>/dev/null)
    local contains_str
    contains_str=$(yq e ".profiles.${profile_name}.detect[${i}].contains // \"\"" "$policy_file" 2>/dev/null)

    if [[ -z "$file_path" || "$file_path" == "null" ]]; then
      # No file key — skip this condition (unknown condition type = not met)
      return 1
    fi

    local full_path="${project_root}/${file_path}"

    # file: condition — file must exist
    if [[ ! -f "$full_path" ]]; then
      return 1
    fi

    # contains: condition — file must contain the string (if specified)
    if [[ -n "$contains_str" && "$contains_str" != "null" ]]; then
      if ! grep -qF "$contains_str" "$full_path" 2>/dev/null; then
        return 1
      fi
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# resolve_profile(project_root, [changed_paths_file])
#
# Detect the ecosystem profile for project_root.
# Detection order: profiles declared in the YAML, in declaration order.
# Multiple matches → union ("A+B"). Zero matches → "unverifiable".
# generic profile (detect: []) is excluded from match evaluation.
#
# Output (stdout): profile name string
# Exit: 0 on success, 1 on malformed/missing policy
# ---------------------------------------------------------------------------
resolve_profile() {
  local project_root="${1:?resolve_profile requires project_root}"
  # changed_paths_file is accepted but not used in detection (reserved for
  # future changed_paths_match conditions in detect blocks)
  # local changed_paths_file="${2:-}"

  local policy_file
  policy_file="$(_delivery_profile_policy_file)"

  _delivery_profile_validate_policy "$policy_file" || return 1

  # Get all profile names in declaration order
  local profile_names
  mapfile -t profile_names < <(yq e '.profiles | keys | .[]' "$policy_file" 2>/dev/null)

  if [[ ${#profile_names[@]} -eq 0 ]]; then
    echo "ERROR: no profiles found in policy" >&2
    return 1
  fi

  local matched_profiles=()

  local profile_name
  for profile_name in "${profile_names[@]}"; do
    # Skip generic — it has empty detect and is the explicit fallback
    if [[ "$profile_name" == "generic" ]]; then
      continue
    fi

    if _delivery_profile_check_detect "$project_root" "$policy_file" "$profile_name"; then
      matched_profiles+=("$profile_name")
    fi
  done

  if [[ ${#matched_profiles[@]} -eq 0 ]]; then
    echo "unverifiable"
    return 0
  fi

  # Join with "+" for union profiles
  local IFS='+'
  echo "${matched_profiles[*]}"
  return 0
}

# ---------------------------------------------------------------------------
# select_commands(policy_file, profile, check_id)
#
# Resolve the argv array for <check_id> under <profile>.
# Prints one argument per line (NUL-separated would require process
# substitution at call site; newline-per-arg is sufficient for bash arrays
# as long as args contain no newlines — standard for CLI commands).
#
# Rules:
#   1. profile == "unverifiable" → empty output
#   2. Union profile ("A+B") → prefer A's cmd; if A has empty cmd, use B's
#   3. Look up profiles.<profile>.commands.<check_id>.cmd
#   4. If key missing or cmd is [] → empty output (→ unverifiable in dispatcher)
#   5. NEVER return a shell string — always line-delimited argv elements
#
# Output (stdout): one arg per line, or empty if no command
# Exit: 0 always (empty output is valid)
# ---------------------------------------------------------------------------
select_commands() {
  local policy_file="${1:?select_commands requires policy_file}"
  local profile="${2:?select_commands requires profile}"
  local check_id="${3:?select_commands requires check_id}"

  # Rule 1: unverifiable → empty
  if [[ "$profile" == "unverifiable" ]]; then
    return 0
  fi

  if [[ ! -f "$policy_file" ]]; then
    echo "ERROR: policy file not found: ${policy_file}" >&2
    return 0
  fi

  # Validate policy parseable
  if ! yq e '.' "$policy_file" >/dev/null 2>&1; then
    echo "ERROR: malformed policy: ${policy_file}" >&2
    return 0
  fi

  # Rule 2: union profile — try each component in order
  # Split on "+" to get profile components
  local -a profile_parts
  IFS='+' read -ra profile_parts <<< "$profile"

  local cmd_array_json=""
  local part
  for part in "${profile_parts[@]}"; do
    # Look up profiles.<part>.commands.<check_id>.cmd
    local raw
    raw=$(yq e ".profiles.${part}.commands.${check_id}.cmd // \"__MISSING__\"" "$policy_file" 2>/dev/null) || continue

    if [[ "$raw" == "__MISSING__" || "$raw" == "null" ]]; then
      # Key missing in this profile component — try next
      continue
    fi

    # Get as JSON array to check if it's non-empty
    local cmd_json
    cmd_json=$(yq e -o=json ".profiles.${part}.commands.${check_id}.cmd" "$policy_file" 2>/dev/null) || continue

    if [[ "$cmd_json" == "null" || "$cmd_json" == "[]" ]]; then
      # Empty array in this profile component — try next (union fallback)
      continue
    fi

    # Found a non-empty command — use it
    cmd_array_json="$cmd_json"
    break
  done

  if [[ -z "$cmd_array_json" || "$cmd_array_json" == "null" || "$cmd_array_json" == "[]" ]]; then
    # No command found across all profile components → empty (unverifiable)
    return 0
  fi

  # Print each element on its own line (injection-safe: no eval, no shell expansion)
  # jq -r outputs each string element without JSON quoting
  echo "$cmd_array_json" | jq -r '.[]'
  return 0
}
