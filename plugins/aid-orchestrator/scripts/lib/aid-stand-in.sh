# shellcheck shell=bash
# aid-stand-in.sh (lib) — the stand-in's permission for a decision of an --auto run that is not a review finding
# (P117 (11); WAN P110-P112: scope widenings, a step without a change, a technically failed measurement stopped
# the run on the PM although nothing protected was at stake). The command is scripts/aid-stand-in.sh.
#
# Layout: <run evidence>/stand-in/<id>/ {proposal.json, prompt.md, verdict.json, auth.json, status-before}
# id = the first 16 hex of sha256(code + the canonical proposal): the same decision asked twice is one id.
#
#   aid_stand_in_dir <evidence_dir> <id>
#   aid_stand_in_id <code> <proposal.json>
#   aid_stand_in_verify <evidence_dir> <auth.json> <kind> <expect-json> <tree_root>
#       0 when the permission holds NOW: approved, of this kind, its proposal is the file it names (sha) and
#       contains <expect-json> (e.g. {"step":2,"paths":["src/x.py"]}), its verdict is the file it names (sha),
#       the plan's ledger records it, and the protected-impact detector still finds nothing. Else prints why, 1.
# Needs lib/aid-protected.sh and lib/aid-delegate.sh (the ledger).

_AID_SI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -F aid_state_root >/dev/null || source "${_AID_SI_LIB}/aid-roots.sh"
declare -F aid_protected_impact >/dev/null || source "${_AID_SI_LIB}/aid-protected.sh"
declare -F aid_delegate_ledger >/dev/null || source "${_AID_SI_LIB}/aid-delegate.sh"

aid_stand_in_dir() { printf '%s/stand-in/%s' "$1" "$2"; }
aid_stand_in_id() { { printf '%s\n' "$1"; jq -cS . "$2"; } | sha256sum | cut -c1-16; }

aid_stand_in_verify() {
  local ev="$1" auth="$2" kind="$3" expect="$4" troot="$5" why
  aid_stand_in_record_ok "$ev" "$auth" "$kind" "$expect" || return 1
  why="$(aid_protected_impact "$(aid_state_root "$(dirname "$(realpath -m "$ev")")" 2>/dev/null || jq -r .state_root "$auth")" "$troot" "$(dirname "$auth")/proposal.json" "$ev")" || { echo "protected impact — the PM's: ${why}"; return 1; }
  return 0
}

# aid_stand_in_record_ok <evidence_dir> <auth.json> <kind> <expect-json> — the permission's own record holds
# FOR THIS RUN (it lives under <evidence_dir>/stand-in/, names this run's plan, the delegation is in force now),
# approved, of this kind, proposal and verdict by sha, the ledger; the caller adds the detector.
aid_stand_in_record_ok() {
  local ev="$1" auth="$2" kind="$3" expect="$4" d prop verdict sroot pid ledger pp
  [[ -f "$auth" ]] || { echo "no stand-in permission at ${auth}"; return 1; }
  [[ "$(realpath "$auth")" == "$(realpath -m "$ev")/stand-in/"*/auth.json ]] \
    || { echo "the permission ${auth} is not one of this run's (${ev}/stand-in/<id>/auth.json)"; return 1; }
  pp="$(yq -r '.plan_path // ""' "${ev}/fsm-state.yaml" 2>/dev/null)"
  pid="$( [[ -f "$pp" ]] && _aid_fm_get "$pp" id 2>/dev/null)"
  sroot="$(aid_state_root "$(dirname "$(realpath -m "$ev")")" 2>/dev/null || jq -r .state_root "$auth")"
  [[ -n "$pid" && "$(jq -r .plan "$auth")" == "$pid" ]] || { echo "the permission names plan $(jq -r .plan "$auth"), this run is ${pid:-<no plan>}"; return 1; }
  aid_delegate_in_force "$sroot" "$pid" || { echo "no delegation is in force for ${pid} now (the PM stopped the run, or it is not --auto)"; return 1; }
  jq -e '.approved == true' "$auth" >/dev/null 2>&1 || { echo "the stand-in did not approve it (${auth})"; return 1; }
  [[ "$(jq -r .kind "$auth")" == "$kind" ]] || { echo "the permission is for $(jq -r .kind "$auth"), not ${kind}"; return 1; }
  d="$(dirname "$auth")"; prop="${d}/proposal.json"; verdict="${d}/verdict.json"
  [[ "$(sha256sum "$prop" 2>/dev/null | cut -d' ' -f1)" == "$(jq -r .proposal_sha256 "$auth")" ]] \
    || { echo "the proposal ${prop} is not the one the stand-in approved"; return 1; }
  [[ "$(sha256sum "$verdict" 2>/dev/null | cut -d' ' -f1)" == "$(jq -r .verdict_sha256 "$auth")" ]] \
    || { echo "the verdict ${verdict} is not the one recorded"; return 1; }
  # exact: every field of the action equals the approved one, an array as a set (contains() would match strings
  # as substrings — AC12 would cover AC1 — and a subset would let [a, b] authorise a and then b separately)
  jq -e --argjson x "$expect" '. as $p | $x | to_entries | all(.key as $k | .value as $v
      | if ($v | type) == "array" then (($v | unique) == (($p[$k] // []) | unique)) else $p[$k] == $v end)' "$prop" >/dev/null 2>&1 \
    || { echo "the approved proposal does not cover this action (expected ${expect}, approved $(jq -c '{step, paths, criterion, rename}' "$prop"))"; return 1; }
  ledger="$(aid_delegate_ledger "$sroot" "$pid")"
  jq -e -s --arg i "$(jq -r .id "$auth")" --arg s "$(jq -r .verdict_sha256 "$auth")" \
    'any(.[]; .checkpoint == "stand_in" and .id == $i and .verdict_sha256 == $s)' "$ledger" >/dev/null 2>&1 \
    || { echo "the plan's ledger ${ledger} does not record this permission"; return 1; }
  # used once, recorded in the plan's append-only ledger (security review: a file beside the permission could be
  # deleted): a repeat of the SAME action is idempotent, another action is refused
  local used; used="$(jq -c -s --arg i "$(jq -r .id "$auth")" --arg s "$(jq -r .verdict_sha256 "$auth")" \
    '[.[] | select(.checkpoint == "stand_in_used" and .id == $i and .verdict_sha256 == $s) | .action] | first // empty' "$ledger" 2>/dev/null)"
  if [[ -n "$used" && "$(jq -cS . <<< "$used")" != "$(jq -cS . <<< "$expect")" ]]; then
    echo "the permission was already used for ${used}"; return 1
  fi
  return 0
}

# aid_stand_in_consume <evidence_dir> <auth.json> <expect-json> — record in the plan's ledger that the permission
# was used for this action; returns 1 when that cannot be written (the caller refuses — fail closed)
aid_stand_in_consume() {
  local ev="$1" auth="$2" pp pid sroot ledger
  pp="$(yq -r '.plan_path // ""' "${ev}/fsm-state.yaml" 2>/dev/null)"; pid="$( [[ -f "$pp" ]] && _aid_fm_get "$pp" id 2>/dev/null)"
  sroot="$(aid_state_root "$(dirname "$(realpath -m "$ev")")" 2>/dev/null || jq -r .state_root "$auth")"
  ledger="$(aid_delegate_ledger "$sroot" "$pid")"
  jq -e -s --arg i "$(jq -r .id "$auth")" 'any(.[]; .checkpoint == "stand_in_used" and .id == $i)' "$ledger" >/dev/null 2>&1 && return 0
  jq -nc --arg i "$(jq -r .id "$auth")" --arg s "$(jq -r .verdict_sha256 "$auth")" --argjson a "$(jq -cS . <<< "$3")" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{checkpoint: "stand_in_used", id: $i, verdict_sha256: $s, action: $a, at: $at}' >> "$ledger"
}
