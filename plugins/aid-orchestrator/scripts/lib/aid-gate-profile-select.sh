#!/usr/bin/env bash
# WHY THIS FILE EXISTS (P097 Step 4): the one resolver over the project's own
# `gate_profiles` table in execution.yaml. The table is an ORDERED list,
# narrowest first; the declaration index is the rank. The FSM, the plan-final
# stage, the plan manifest and the DoD agreement all ask this file for names
# and ranks; none keeps a table of its own.
#
#   gate_profile_table <yaml>                 declared names, one per line, in order
#   gate_profile_exists <yaml> <name>         exit 0 iff declared
#   gate_profile_index <yaml> <name>          0-based declaration index; exit 1 unknown
#   gate_profile_has_required_gate <yaml> <name>  exit 0 iff include[] names a gate that is
#       `required: true`, or carries `required_when` with no explicit `required` (the
#       composer's stack fragments write only required_when; lib/aid-gate-applicability.sh
#       decides at run time whether it applies)
#   gate_profile_wider <yaml> <a> <b>         the higher-indexed of two (an undeclared name loses)
#   gate_profile_for_paths <yaml> <paths file>  the LAST declared profile whose when_paths
#       matches any changed path, else default_profile; prints nothing when the file
#       declares no gate_profiles; exit 2 when gate_profiles exists without a usable
#       default_profile or the answer names no required gate
#   gate_profile_floor_verdict <yaml> <report> [<required>]  "ok", or the refusal
#       reason (risk_profile_unresolvable | profile_table_changed |
#       risk_profile_below_required) followed by ": <detail>"; exit 1 on refusal
#
# Globs use _aid_ancillary_glob_match (lib/aid-ancillary.sh), the same bash
# `case` dialect the old classifier used. No `set -e`: sourced into callers.
# Refusals name the upgrade command so a human can fix the file without a
# source step.
_AID_GPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_AID_GPS_DIR}/aid-ancillary.sh"

gate_profile_upgrade_hint() {
  printf 'upgrade the file with: bash %s/aid-init-execution-yaml.sh upgrade <project root>\n' "$_AID_GPS_DIR"
}

# _gps_json <yaml> — the file as JSON (the one parse every function shares).
_gps_json() {
  [[ -f "$1" ]] || { echo "ERROR: aid-gate-profile-select.sh: no execution.yaml at '${1:-}'" >&2; return 2; }
  yq -o=json '.' "$1" 2>/dev/null || { echo "ERROR: aid-gate-profile-select.sh: ${1} does not parse" >&2; return 2; }
}

gate_profile_table() {
  local j; j="$(_gps_json "$1")" || return $?
  jq -r '.gate_profiles // {} | keys_unsorted[]' <<<"$j"
}

gate_profile_exists() {
  gate_profile_table "$1" | grep -qxF -- "${2:-}"
}

gate_profile_index() {
  local i; i="$(gate_profile_table "$1" | awk -v n="${2:-}" '$0 == n { print NR - 1; exit }')"
  [[ -n "$i" ]] || return 1
  echo "$i"
}

gate_profile_has_required_gate() {
  local j; j="$(_gps_json "$1")" || return $?
  jq -e --arg p "${2:-}" '. as $j | .gate_profiles[$p].include // [] | any(.[]; . as $g | $j.gates[$g] as $r | ($r.required == true) or ($r.required == null and $r.required_when != null))' <<<"$j" >/dev/null
}

gate_profile_wider() {
  local ia ib
  ia="$(gate_profile_index "$1" "$2")" || ia=-1
  ib="$(gate_profile_index "$1" "$3")" || ib=-1
  (( ia < 0 && ib < 0 )) && return 1
  (( ia >= ib )) && echo "$2" || echo "$3"
}

gate_profile_for_paths() {
  local yaml="$1" paths="${2:-}" j table default chosen="" name pattern p
  j="$(_gps_json "$yaml")" || return $?
  table="$(jq -r '.gate_profiles // {} | keys_unsorted[]' <<<"$j")"
  [[ -n "$table" ]] || return 0
  default="$(jq -r '.default_profile // empty' <<<"$j")"
  if [[ -z "$default" ]] || ! grep -qxF -- "$default" <<<"$table"; then
    echo "ERROR: aid-gate-profile-select.sh: ${yaml} declares gate_profiles [$(tr '\n' ' ' <<<"$table")] but no declared default_profile; $(gate_profile_upgrade_hint)" >&2
    return 2
  fi
  # Widest wins: walk the table in declared order and keep the LAST match.
  while IFS= read -r name; do
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        if _aid_ancillary_glob_match "$p" "$pattern"; then chosen="$name"; break 2; fi
      done < <([[ -n "$paths" && -f "$paths" ]] && cat "$paths")
    done < <(jq -r --arg n "$name" '.gate_profiles[$n].when_paths // [] | .[]' <<<"$j")
  done <<<"$table"
  chosen="${chosen:-$default}"
  if ! gate_profile_has_required_gate "$yaml" "$chosen"; then
    echo "ERROR: aid-gate-profile-select.sh: profile '${chosen}' in ${yaml} includes no required gate ($(jq -r --arg n "$chosen" '.gate_profiles[$n].include // [] | join(", ")' <<<"$j")) — a run that can only skip is not a run" >&2
    return 2
  fi
  echo "$chosen"
}

gate_profile_floor_verdict() {
  local yaml="$1" report="$2" required="${3:-}" j table profile rtable ip ir
  j="$(_gps_json "$yaml")" || return $?
  [[ -f "$report" ]] || { echo "risk_profile_unresolvable: no gates report at ${report}"; return 1; }
  table="$(jq -c '.gate_profiles // {} | keys_unsorted' <<<"$j")"
  profile="$(jq -r '.profile // empty' "$report" 2>/dev/null)"
  if [[ "$table" == "[]" ]]; then
    # No table: every declared gate must have a row — that is the only way "none" passes.
    local missing
    missing="$(jq -r --argjson j "$j" '($j.gates // {} | keys) - (.gates // {} | keys) | join(", ")' "$report")"
    [[ -z "$missing" ]] || { echo "risk_profile_unresolvable: no gate_profiles declared and the report has no row for: ${missing}"; return 1; }
    echo ok; return 0
  fi
  [[ -n "$profile" ]] || { echo "risk_profile_unresolvable: the report names no profile while ${yaml} declares gate_profiles ${table}"; return 1; }
  rtable="$(jq -c '.profile_table // []' "$report")"
  [[ "$rtable" == "$table" ]] || { echo "profile_table_changed: the report recorded ${rtable}, the file now declares ${table}"; return 1; }
  ip="$(gate_profile_index "$yaml" "$profile")" || { echo "risk_profile_unresolvable: recorded profile '${profile}' is not declared in ${table}"; return 1; }
  if [[ -n "$required" ]]; then
    ir="$(gate_profile_index "$yaml" "$required")" || { echo "risk_profile_unresolvable: required profile '${required}' is not declared in ${table}"; return 1; }
    (( ip >= ir )) || { echo "risk_profile_below_required: recorded profile '${profile}' (index ${ip}) is narrower than required '${required}' (index ${ir})"; return 1; }
  fi
  echo ok
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    table|exists|index|has-required-gate|wider|for-paths|floor-verdict)
      "gate_profile_${cmd//-/_}" "$@"; exit $? ;;
    *) echo "usage: $0 table|exists|index|has-required-gate|wider|for-paths|floor-verdict <execution.yaml> [args]" >&2; exit 2 ;;
  esac
fi
