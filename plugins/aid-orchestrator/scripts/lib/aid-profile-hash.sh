#!/usr/bin/env bash
# aid-profile-hash.sh — Deterministic review profile hash helper.
#
# Usage (subcommand): aid-profile-hash.sh profile_hash <project_id> <plan_surfaces> <candidate_surfaces> <lenses>
#   <plan_surfaces>, <candidate_surfaces>, <lenses> — space-separated lists
#   Output: sha256:<64 hex chars>
#
# Sourceable: source this file and call profile_hash() directly.

profile_hash() {
  if [[ $# -lt 4 ]]; then
    echo "Usage: profile_hash <project_id> <plan_surfaces> <candidate_surfaces> <lenses>" >&2
    return 1
  fi

  if ! command -v sha256sum &>/dev/null; then
    echo "sha256_required: sha256sum not found in PATH" >&2
    return 1
  fi

  local pid="$1"
  # Convert space-separated lists to sorted, newline-joined canonical strings
  local plan_nl candidate_nl lens_nl
  plan_nl=$(tr ' ' '\n' <<< "$2" | sort -u | grep -v '^$' | paste -sd $'\n' - || true)
  candidate_nl=$(tr ' ' '\n' <<< "$3" | sort -u | grep -v '^$' | paste -sd $'\n' - || true)
  lens_nl=$(tr ' ' '\n' <<< "$4" | sort -u | grep -v '^$' | paste -sd $'\n' - || true)

  local hex
  hex=$(printf '%s\x1f%s\x1f%s\x1f%s' "$pid" "$plan_nl" "$candidate_nl" "$lens_nl" | sha256sum | cut -d' ' -f1 | cut -c1-64)
  printf 'sha256:%s\n' "$hex"
}

# Subcommand dispatch
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    profile_hash) shift; profile_hash "$@" ;;
    *) echo "Usage: $(basename "$0") profile_hash <project_id> <plan_surfaces> <candidate_surfaces> <lenses>" >&2; exit 1 ;;
  esac
fi
