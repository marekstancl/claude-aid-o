#!/usr/bin/env bash
# =============================================================================
# aid-ac-substitute.sh — a plan point measured by a corrected command, the plan left as it is (3.16.0, K7)
#
#   aid-ac-substitute.sh add --evidence-dir <run> --criterion AC<n> --stand-in <auth.json>
#   aid-ac-substitute.sh add --evidence-dir <run> --criterion AC<n> --cmd-file <file> --pm "<the PM's words>"
#   aid-ac-substitute.sh check --plan <plan.md> --criterion AC<n> --cmd <the plan's cmd>   (prints the substitute)
#
# WHY: agents P017 AC13 — the point was met, its command could never pass in the isolated measurement (`\``),
# and the only way on was to change the approved plan: a card for the PM and six hours of waiting overnight.
# Now the plan stays byte for byte; the point is measured by the command an independent stand-in judged to measure
# the same thing (aid-stand-in.sh ask --code ac_command_defective, kind ac_command, {criterion, cmd_old, cmd_new,
# reason}), or the PM's words outside --auto. The entry binds the plan's command and the new one by sha256: when the
# plan's command changes, or the entry is edited, plan_diff ignores it. The point's TEXT is never touched.
#
# Entries: <state root>/.aid-o/work/evidence/<plan id>/ac-substitutes.json (an array). Exit 0 written / found,
# 1 refused (the reason on stderr), 2 usage, 3 no substitute (check).
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aid-roots.sh"
source "${SCRIPT_DIR}/lib/aid-verification-pattern.sh"

CMD="${1:-}"; shift || true
EVID="" CRIT="" AUTH="" CMDFILE="" PMWORDS="" PLAN="" PLANCMD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence-dir|--criterion|--stand-in|--cmd-file|--pm|--plan|--cmd)
      [[ $# -ge 2 ]] || { echo "${0##*/}: $1 needs a value" >&2; exit 2; } ;;&
    --evidence-dir) EVID="$2"; shift 2 ;;
    --criterion)    CRIT="$2"; shift 2 ;;
    --stand-in)     AUTH="$2"; shift 2 ;;
    --cmd-file)     CMDFILE="$2"; shift 2 ;;
    --pm)           PMWORDS="$2"; shift 2 ;;
    --plan)         PLAN="$2"; shift 2 ;;
    --cmd)          PLANCMD="$2"; shift 2 ;;
    *) echo "${0##*/}: unknown argument $1" >&2; exit 2 ;;
  esac
done
_sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
_refuse() { echo "aid-ac-substitute ${CMD}: REFUSED ($1): $2" >&2; echo "next: $3" >&2; echo "(pipeline.md §When AID refuses: $1)" >&2; exit 1; }

# _file <plan.md> — the plan's substitutes file (state root, plan id from the frontmatter)
_file() {
  local pid sroot; pid="$(_aid_plan_id_of "$1" 2>/dev/null)" || return 1
  sroot="$(aid_state_root "$(dirname "$(realpath -m "$1")")" 2>/dev/null)" || return 1
  printf '%s/.aid-o/work/evidence/%s/ac-substitutes.json\n' "$sroot" "$pid"
}
# _plan_cmd <plan.md> <AC<n>> — the point's cmd as the plan states it (the parser the measurement uses)
_plan_cmd() {
  local l t ty c
  while IFS=$'\x1f' read -r l t ty c _; do
    [[ "$l" == "$2" && "$ty" == cmd ]] && { printf '%s' "$c"; return 0; }
  done < <(_aid_vp_parse_ac "$1" "Acceptance Criteria")
  return 1
}

cmd_add() {
  [[ -n "$EVID" && -d "$EVID" && "$CRIT" =~ ^AC[0-9]+$ ]] || { echo "add needs --evidence-dir <run> and --criterion AC<n>" >&2; exit 2; }
  EVID="$(cd "$EVID" && pwd)"
  local plan; plan="$(yq -r '.plan_path // ""' "${EVID}/fsm-state.yaml" 2>/dev/null)"
  [[ -f "$plan" ]] || _refuse ac_substitute_no_plan "the run ${EVID} names no readable plan (fsm-state.yaml plan_path)" "run from the plan's direct run"
  local old new by words="" auth_rel=""
  old="$(_plan_cmd "$plan" "$CRIT")" || _refuse ac_substitute_not_cmd "${CRIT} of ${plan} is not a cmd point" "only a measuring command can be substituted"
  if [[ -n "$AUTH" ]]; then
    source "${SCRIPT_DIR}/lib/aid-stand-in.sh"
    new="$(jq -r '.cmd_new // ""' "$(dirname "$AUTH")/proposal.json" 2>/dev/null)"
    [[ -n "$new" ]] || _refuse ac_substitute_unbound "the permission's proposal has no cmd_new" "ask the stand-in with kind ac_command"
    [[ "$(jq -r '.cmd_old // ""' "$(dirname "$AUTH")/proposal.json")" == "$old" ]] \
      || _refuse ac_substitute_unbound "the approved cmd_old is not ${CRIT}'s command in the plan now" "ask again with the plan's command"
    local expect why; expect="$(jq -nc --arg c "$CRIT" --arg o "$old" --arg n "$new" '{criterion: $c, cmd_old: $o, cmd_new: $n}')"
    why="$(aid_stand_in_verify "$EVID" "$AUTH" ac_command "$expect" "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")" \
      || _refuse ac_substitute_unbound "$why" "aid-stand-in.sh ask --code ac_command_defective with kind ac_command"
    aid_stand_in_consume "$EVID" "$AUTH" "$expect" || _refuse ac_substitute_unbound "the use could not be recorded in the plan's ledger" "record again"
    by=stand_in; auth_rel="$(realpath "$AUTH")"
  elif [[ -n "$PMWORDS" ]]; then
    (( ${#PMWORDS} >= 20 )) || _refuse ac_substitute_pm_words "the PM's words are under 20 characters" "quote what the PM said"
    # in an --auto run the stand-in decides, never words the controller types (security review 3.16.0)
    source "${SCRIPT_DIR}/lib/aid-delegate.sh"
    ! aid_delegate_in_force "$(aid_state_root "$(dirname "$(realpath -m "$plan")")")" "$(_aid_plan_id_of "$plan")" \
      || _refuse ac_substitute_unbound "an --auto run: the substitute is the stand-in's decision, not a --pm entry" "aid-stand-in.sh ask --code ac_command_defective"
    [[ -f "$CMDFILE" ]] || _refuse ac_substitute_unbound "--pm needs --cmd-file with the new command" "write it to a file"
    new="$(cat "$CMDFILE")"; by=pm; words="$PMWORDS"
  else
    echo "add needs --stand-in <auth.json> or --pm \"<words>\" --cmd-file <file>" >&2; exit 2
  fi
  [[ -n "$new" && "$new" != "$old" ]] || _refuse ac_substitute_unbound "the new command is empty or the plan's own" "nothing to substitute"
  local f; f="$(_file "$plan")" || _refuse ac_substitute_no_plan "cannot tell the plan id or state root of ${plan}" "run from the plan's run"
  mkdir -p "$(dirname "$f")"; [[ -f "$f" ]] || echo '[]' > "$f"
  jq --arg c "$CRIT" --arg os "$(_sha "$old")" --arg n "$new" --arg ns "$(_sha "$new")" --arg b "$by" --arg w "$words" \
     --arg a "$auth_rel" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     'map(select(.criterion != $c)) + [{criterion: $c, cmd_plan_sha256: $os, cmd_new: $n, cmd_new_sha256: $ns, by: $b,
        pm_words: (if $w == "" then null else $w end), auth: (if $a == "" then null else $a end), at: $at}]' "$f" > "${f}.tmp" \
    && mv "${f}.tmp" "$f" || _refuse ac_substitute_write "cannot write ${f}" "check the evidence directory"
  # the plan's append-only ledger holds the binding; check trusts an entry only with its line there
  source "${SCRIPT_DIR}/lib/aid-delegate.sh"
  jq -nc --arg c "$CRIT" --arg os "$(_sha "$old")" --arg ns "$(_sha "$new")" --arg b "$by" --arg w "$words" --arg a "$auth_rel" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{checkpoint: "ac_substitute", criterion: $c, cmd_plan_sha256: $os, cmd_new_sha256: $ns, by: $b, pm_words: $w, auth: $a, at: $at}' \
    >> "$(aid_delegate_ledger "$(aid_state_root "$(dirname "$(realpath -m "$plan")")")" "$(_aid_plan_id_of "$plan")")" \
    || _refuse ac_substitute_write "cannot record the substitute in the plan's ledger" "check the evidence directory"
  echo "${CRIT}: measured by the substitute command from now on (${by}); the plan is unchanged — ${f}"
}

# cmd_check — the substitute for this plan's point and command, verified; nothing (exit 3) when there is none
cmd_check() {
  [[ -f "$PLAN" && "$CRIT" =~ ^AC[0-9]+$ ]] || exit 2
  local f e; f="$(_file "$PLAN")" || exit 3
  [[ -f "$f" ]] || exit 3
  e="$(jq -c --arg c "$CRIT" --arg os "$(_sha "$PLANCMD")" 'first(.[]? | select(.criterion == $c and .cmd_plan_sha256 == $os)) // empty' "$f" 2>/dev/null)"
  [[ -n "$e" ]] || exit 3
  local new; new="$(jq -r .cmd_new <<< "$e")"
  [[ "$(_sha "$new")" == "$(jq -r .cmd_new_sha256 <<< "$e")" ]] || { echo "ac-substitutes: ${CRIT}'s entry was edited (sha) — ignored" >&2; exit 3; }
  source "${SCRIPT_DIR}/lib/aid-delegate.sh"
  local ledger; ledger="$(aid_delegate_ledger "$(aid_state_root "$(dirname "$(realpath -m "$PLAN")")")" "$(_aid_plan_id_of "$PLAN")")"
  jq -e -s --arg c "$CRIT" --arg os "$(_sha "$PLANCMD")" --arg ns "$(_sha "$new")" --arg b "$(jq -r .by <<< "$e")" \
    'any(.[]; .checkpoint == "ac_substitute" and .criterion == $c and .cmd_plan_sha256 == $os and .cmd_new_sha256 == $ns and .by == $b)' \
    "$ledger" >/dev/null 2>&1 || { echo "ac-substitutes: ${CRIT}: no record in the plan's ledger — ignored" >&2; exit 3; }
  case "$(jq -r .by <<< "$e")" in
    pm) [[ "$(jq -r '.pm_words // "" | length' <<< "$e")" -ge 20 ]] || { echo "ac-substitutes: ${CRIT}: a PM entry without the PM's words — ignored" >&2; exit 3; }
        # the same rule as add: while an --auto delegation holds, only the stand-in's permission counts. The PM's
        # words are recorded by the controller, as everywhere in AID (dispute --pm, standing): no signature.
        ! aid_delegate_in_force "$(aid_state_root "$(dirname "$(realpath -m "$PLAN")")")" "$(_aid_plan_id_of "$PLAN")" \
          || { echo "ac-substitutes: ${CRIT}: a PM entry in an --auto run — ignored (the stand-in decides)" >&2; exit 3; } ;;
    stand_in)
      local auth ev; auth="$(jq -r '.auth // ""' <<< "$e")"; ev="${auth%/stand-in/*}"
      source "${SCRIPT_DIR}/lib/aid-stand-in.sh"
      aid_stand_in_record_ok "$ev" "$auth" ac_command "$(jq -nc --arg c "$CRIT" --arg o "$PLANCMD" --arg n "$new" '{criterion: $c, cmd_old: $o, cmd_new: $n}')" >/dev/null 2>&1 \
        || { echo "ac-substitutes: ${CRIT}: the stand-in's permission does not hold — ignored" >&2; exit 3; } ;;
    *) exit 3 ;;
  esac
  printf '%s\x1f%s\n' "$(jq -r .by <<< "$e")" "$new"
}

case "$CMD" in
  add) cmd_add ;;
  check) cmd_check ;;
  *) echo "usage: ${0##*/} add|check …" >&2; exit 2 ;;
esac
