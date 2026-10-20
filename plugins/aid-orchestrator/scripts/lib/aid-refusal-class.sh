# shellcheck shell=bash
# aid-refusal-class.sh — the ONE reader of defaults/refusal-classes.yaml (P117 (1)): aid-fsm.sh (_fsm_refusal_next,
# the class line every refusal prints) and aid-stand-in.sh (which codes a stand-in decides) read it here.
_AID_RFC_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/defaults/refusal-classes.yaml"

# _aid_rfc_field <code> <field> — a field of a code; a code carrying a number (gates_runner_exit_1) is registered
# once with <n>
_aid_rfc_field() {
  local c g
  c="$(C="$1" F="$2" yq -r '.codes[strenv(C)][strenv(F)] // ""' "$_AID_RFC_FILE" 2>/dev/null)" || c=""
  if [[ -z "$c" && "$1" =~ ^(.*_)[0-9]+$ ]]; then
    g="${BASH_REMATCH[1]}<n>"; c="$(C="$g" F="$2" yq -r '.codes[strenv(C)][strenv(F)] // ""' "$_AID_RFC_FILE" 2>/dev/null)" || c=""
  fi
  printf '%s' "$c"
}
# aid_refusal_class <code> — its class; unknown or unreadable = pm (fail-closed)
aid_refusal_class() { local c; c="$(_aid_rfc_field "$1" class)"; printf '%s\n' "${c:-pm}"; }
# aid_refusal_class_how <code> — what happens to it
aid_refusal_class_how() { _aid_rfc_field "$1" how; }
