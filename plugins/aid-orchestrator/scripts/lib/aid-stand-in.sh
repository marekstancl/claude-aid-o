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
declare -F aid_protected_impact >/dev/null || source "${_AID_SI_LIB}/aid-protected.sh"
declare -F aid_delegate_ledger >/dev/null || source "${_AID_SI_LIB}/aid-delegate.sh"

aid_stand_in_dir() { printf '%s/stand-in/%s' "$1" "$2"; }
aid_stand_in_id() { { printf '%s\n' "$1"; jq -cS . "$2"; } | sha256sum | cut -c1-16; }

aid_stand_in_verify() {
  local ev="$1" auth="$2" kind="$3" expect="$4" troot="$5" why
  aid_stand_in_record_ok "$auth" "$kind" "$expect" || return 1
  why="$(aid_protected_impact "$(jq -r .state_root "$auth")" "$troot" "$(dirname "$auth")/proposal.json" "$ev")" || { echo "protected impact — the PM's: ${why}"; return 1; }
  return 0
}

# aid_stand_in_record_ok <auth.json> <kind> <expect-json> — the permission's own record holds (approved, kind,
# proposal and verdict by sha, the ledger); the caller adds the detector (aid_stand_in_verify does).
aid_stand_in_record_ok() {
  local auth="$1" kind="$2" expect="$3" d prop verdict sroot pid ledger
  [[ -f "$auth" ]] || { echo "no stand-in permission at ${auth}"; return 1; }
  jq -e '.approved == true' "$auth" >/dev/null 2>&1 || { echo "the stand-in did not approve it (${auth})"; return 1; }
  [[ "$(jq -r .kind "$auth")" == "$kind" ]] || { echo "the permission is for $(jq -r .kind "$auth"), not ${kind}"; return 1; }
  d="$(dirname "$auth")"; prop="${d}/proposal.json"; verdict="${d}/verdict.json"
  [[ "$(sha256sum "$prop" 2>/dev/null | cut -d' ' -f1)" == "$(jq -r .proposal_sha256 "$auth")" ]] \
    || { echo "the proposal ${prop} is not the one the stand-in approved"; return 1; }
  [[ "$(sha256sum "$verdict" 2>/dev/null | cut -d' ' -f1)" == "$(jq -r .verdict_sha256 "$auth")" ]] \
    || { echo "the verdict ${verdict} is not the one recorded"; return 1; }
  # exact: an array of the action is a subset of the approved one, every other field equal (contains() would
  # match strings as substrings — AC12 would cover AC1)
  jq -e --argjson x "$expect" '. as $p | $x | to_entries | all(.key as $k | .value as $v
      | if ($v | type) == "array" then (($v - ($p[$k] // [])) | length) == 0 else $p[$k] == $v end)' "$prop" >/dev/null 2>&1 \
    || { echo "the approved proposal does not cover this action (expected ${expect}, approved $(jq -c '{step, paths, criterion, rename}' "$prop"))"; return 1; }
  sroot="$(jq -r .state_root "$auth")"; pid="$(jq -r .plan "$auth")"; ledger="$(aid_delegate_ledger "$sroot" "$pid")"
  jq -e -s --arg i "$(jq -r .id "$auth")" --arg s "$(jq -r .verdict_sha256 "$auth")" \
    'any(.[]; .checkpoint == "stand_in" and .id == $i and .verdict_sha256 == $s)' "$ledger" >/dev/null 2>&1 \
    || { echo "the plan's ledger ${ledger} does not record this permission"; return 1; }
  return 0
}
