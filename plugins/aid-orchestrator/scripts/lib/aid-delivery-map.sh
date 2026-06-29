#!/usr/bin/env bash
# =============================================================================
# aid-delivery-map.sh — C1 delivery-map.yaml accessor library
#
# Provides a stable interface to read sections from the project's delivery-map.yaml.
# Callers MUST source this file before calling its functions.
#
# IMPORTANT: probes MUST check $?, not stdout emptiness; yq prints literal 'null'
# for missing keys. get_section: present+non-null → JSON stdout, exit 0;
# absent/null → empty stdout, exit 2.
#
# Usage:
#   source aid-delivery-map.sh
#   get_section routes        # exit 0 + JSON if present, exit 2 if absent/null
#   get_section oracle_baselines
#   map_status                # prints meta.status or "unknown"
#
# Environment:
#   AID_DELIVERY_MAP    — override path to delivery-map.yaml (optional)
#   AID_PROJECT_ROOT    — project root used to locate default map path (optional)
#
# Requirements: yq v4+, bash 4.0+
# =============================================================================

# ---------------------------------------------------------------------------
# _aid_delivery_map_path() → prints resolved absolute path to delivery-map.yaml
#
# Resolution order:
#   1. $AID_DELIVERY_MAP if set and non-empty
#   2. ${AID_PROJECT_ROOT}/.aid-o/config/delivery-map.yaml
#   3. $(git rev-parse --show-toplevel)/.aid-o/config/delivery-map.yaml
#   4. ./.aid-o/config/delivery-map.yaml (last resort)
#
# Returns:
#   exit 0 + path printed if file exists
#   exit 2 if file not found at any candidate location
# ---------------------------------------------------------------------------
_aid_delivery_map_path() {
  local candidate

  # 1. Explicit override
  if [[ -n "${AID_DELIVERY_MAP:-}" ]]; then
    candidate="$AID_DELIVERY_MAP"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    return 2
  fi

  # 2. AID_PROJECT_ROOT
  if [[ -n "${AID_PROJECT_ROOT:-}" ]]; then
    candidate="${AID_PROJECT_ROOT}/.aid-o/config/delivery-map.yaml"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    return 2
  fi

  # 3. git toplevel
  local git_root
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [[ -n "$git_root" ]]; then
    candidate="${git_root}/.aid-o/config/delivery-map.yaml"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
    return 2
  fi

  # 4. Last resort: cwd-relative
  candidate="./.aid-o/config/delivery-map.yaml"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi

  return 2
}

# ---------------------------------------------------------------------------
# get_section <area>
#
# Reads a top-level section from delivery-map.yaml and prints it as JSON.
#
# CRITICAL: yq v4 prints the literal string "null" for missing or null keys.
# This function checks for that string explicitly and converts it to exit 2.
# Callers MUST check $?, NOT stdout emptiness.
#
# Arguments:
#   area — dot-path segment for the top-level key (e.g. "routes", "meta",
#           "oracle_baselines")
#
# Returns:
#   exit 0 + JSON on stdout if section is present and non-null
#   exit 2 + empty stdout if section is absent, null, or delivery-map not found
# ---------------------------------------------------------------------------
get_section() {
  local area="$1"

  if [[ -z "$area" ]]; then
    return 2
  fi

  local map_file
  map_file="$(_aid_delivery_map_path)" || return 2

  # yq v4: for missing key returns literal string "null"
  local raw
  raw="$(yq e ".${area}" "$map_file" -o=json 2>/dev/null)"
  local yq_exit=$?

  if [[ $yq_exit -ne 0 || -z "$raw" || "$raw" == "null" ]]; then
    return 2
  fi

  echo "$raw"
  return 0
}

# ---------------------------------------------------------------------------
# map_status() → prints the status field from meta, or "unknown" if not set
# ---------------------------------------------------------------------------
map_status() {
  local section_json
  section_json="$(get_section "meta" 2>/dev/null)" || {
    echo "unknown"
    return 0
  }

  local status
  status="$(echo "$section_json" | jq -r '.status // empty' 2>/dev/null)"

  if [[ -z "$status" ]]; then
    echo "unknown"
  else
    echo "$status"
  fi
  return 0
}
