# shellcheck shell=bash
# aid-amend-contract.sh — a rename inside a frozen plan (P117 (13); WAN P110/P111: the plan named a test after
# itself, the project's lint refused it, and no allowed command could rename the expected artifact).
#
#   aid_amend_contract_rename <state_file> <old> <new> <reason> <stand_in auth | ""> <pm card | "">
#
# A pure token swap of the whole path (the same string everywhere, nothing else in any command changes) in:
# plan.json, the step's contract (its old version recorded as superseded, so a return quoting it stays valid),
# the plan file and the brief (verze + 1). Then the fingerprints are refreshed in order (brief → plan frontmatter
# → plan file → plan.json → fsm-state plan_json_hash → the plan-run seal), the step's measurement and review are
# moved aside, and the plan check and readiness run again — any failure puts every file back.
# Refused: a path outside the current step or another directory, .. or an absolute path, a collision (the new
# path already named, or both paths on disk), no permission (the stand-in's kind rename, or the PM's card).
# Sourced by aid-fsm.sh (yaml_field, log_event, fsm_emit_audit_log, aid_invoke_root are the caller's).

_AID_AC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _aid_ac_swap <file> <old> <new> — replace the whole-path token; prints the number of replacements
_aid_ac_swap() {
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
f, old, new = sys.argv[1:4]
s = open(f, encoding="utf-8").read()
pat = re.compile(r"(?<![A-Za-z0-9_./-])" + re.escape(old) + r"(?![A-Za-z0-9_/-]|\.[A-Za-z0-9])")
t, n = pat.subn(lambda m: new, s)   # the new path literally, never a regex template
if n: open(f, "w", encoding="utf-8").write(t)
print(n)
PY
}
_aid_ac_has() { [[ "$(python3 -c 'import re,sys; s=open(sys.argv[1],encoding="utf-8").read(); print(len(re.findall(r"(?<![A-Za-z0-9_./-])"+re.escape(sys.argv[2])+r"(?![A-Za-z0-9_/-]|\.[A-Za-z0-9])", s)))' "$1" "$2" 2>/dev/null)" != 0 ]]; }

aid_amend_contract_rename() {
  local sf="$1" old="$2" new="$3" reason="$4" auth="$5" card="$6"
  local ev pj cs total sid plan troot sroot cdir contract zrel zf why
  ev="$(cd "$(dirname "$sf")" && pwd)"; pj="${ev}/plan.json"
  _ac_fail() { echo "REFUSED ($1): amend-contract --rename ${old}=${new}: $2" >&2; echo "next: $3" >&2; echo "(pipeline.md §When AID refuses: $1)" >&2; exit 1; }
  [[ -f "$pj" ]] || _ac_fail rename_refused "no plan.json in ${ev}" "run it from the run's state file"
  case "$(yaml_field "$sf" state)" in EXECUTE|GATES) ;; *) _ac_fail rename_refused "the run is not in EXECUTE or GATES" "rename while the step is being worked";; esac
  (( ${#reason} >= 20 )) || _ac_fail rename_refused "--reason needs at least 20 characters (the audit record)" "say why the name changes"
  [[ -n "$old" && -n "$new" && "$old" != "$new" ]] || _ac_fail rename_refused "--rename takes <old>=<new>, two different paths" "--rename old/path=new/path"
  [[ "$old" != /* && "$new" != /* && "$old$new" != *..* ]] || _ac_fail rename_refused "absolute paths and .. are not renamed here" "a path relative to the repository"
  # a path, nothing else: no whitespace, quotes, backslashes or shell characters can ride into a command (security review)
  [[ "$old" =~ ^[A-Za-z0-9._/-]+$ && "$new" =~ ^[A-Za-z0-9._/-]+$ ]] || _ac_fail rename_refused "a path of letters, digits and . _ / - only" "rename to a plain path"
  # the same rename again after it applied: done, nothing changes (an idempotent retry)
  if jq -e --arg o "$old" --arg n "$new" 'any(.[]; .rename.old == $o and .rename.new == $n)' "${ev}/steps/"*/contract-amendments.json >/dev/null 2>&1 \
     && ! _aid_ac_has "$pj" "$old"; then
    echo "already renamed ${old} → ${new}; nothing changed"; return 0
  fi
  [[ "$(dirname "$old")" == "$(dirname "$new")" ]] || _ac_fail rename_outside_step "the new name moves the file to another directory ($(dirname "$new"))" "rename in place; a move is a scope change (amend-scope)"
  cs="$(yaml_field "$sf" current_step)"; total="$(jq '.steps | length' "$pj")"; (( cs >= total && total > 0 )) && cs=$(( total - 1 ))
  sid="$(jq -r --argjson i "$cs" '.steps[$i].id' "$pj")"
  local stepf; stepf="$(mktemp)"; jq --argjson i "$cs" '.steps[$i]' "$pj" > "$stepf"
  local _in=1; _aid_ac_has "$stepf" "$old" && _in=0; rm -f "$stepf"; (( _in == 0 )) \
    || _ac_fail rename_outside_step "${old} is not a path of the current step $((cs + 1)) (${sid})" "only a path of the step being worked is renamed"
  troot="$(aid_invoke_root 2>/dev/null || pwd)"; sroot="$(aid_state_root 2>/dev/null || pwd)"
  plan="$(yq -r '.plan_path // ""' "$sf")"; [[ -f "$plan" ]] || plan=""
  zrel="$(jq -r '.zadani // ""' "$pj")"; zf=""; [[ -n "$zrel" && -f "${sroot}/${zrel}" ]] && zf="${sroot}/${zrel}"
  cdir="${ev}/steps/${sid}"; contract="${cdir}/contract.json"
  local f; for f in "$pj" ${plan:+"$plan"} ${zf:+"$zf"}; do
    _aid_ac_has "$f" "$new" && _ac_fail rename_collision "${new} is already named in ${f}" "choose a name nothing names yet"
  done
  [[ -e "${troot}/${old}" && -e "${troot}/${new}" ]] && _ac_fail rename_collision "both ${old} and ${new} exist in the worktree" "remove one first"

  # the permission: the stand-in's (kind rename, this step, exactly this pair) or the PM's card quoting both
  local decision
  if [[ -n "$auth" ]]; then
    declare -F aid_stand_in_verify >/dev/null || source "${_AID_AC_LIB}/aid-stand-in.sh"
    why="$(aid_stand_in_verify "$ev" "$auth" rename "$(jq -nc --argjson s "$cs" --arg o "$old" --arg n "$new" '{step: $s, rename: {old: $o, new: $n}}')" "$troot")" \
      || _ac_fail rename_refused "--stand-in ${auth}: ${why}" "ask the stand-in for this rename, or the PM"
    decision="$(jq -nc --arg a "$auth" --arg s "$(jq -r .verdict_sha256 "$auth")" '{stand_in: $a, verdict_sha256: $s}')"
    local si_expect; si_expect="$(jq -nc --argjson s "$cs" --arg o "$old" --arg n "$new" '{step: $s, rename: {old: $o, new: $n}}')"
    # used before anything changes: a rename cannot be taken back safely afterwards (fail closed)
    aid_stand_in_consume "$ev" "$auth" "$si_expect" || _ac_fail rename_refused "the use of ${auth} could not be recorded in the plan's ledger" "fix the disk, then rename again"
  elif [[ -n "$card" ]]; then
    declare -F aid_pm_card_check >/dev/null || source "${_AID_AC_LIB}/aid-decision-card.sh"
    for f in "$old" "$new"; do why="$(aid_pm_card_check "$card" "$f")" || _ac_fail rename_refused "--pm-card: ${why}" "the PM's answered card quotes both paths"; done
    decision="$(jq -nc --arg c "$card" --arg s "$(sha256sum "$card" | cut -d' ' -f1)" '{card: $c, card_sha256: $s}')"
  else
    _ac_fail rename_refused "no permission" "in an --auto run: aid-stand-in.sh ask --code contract_return_rejected --proposal {\"kind\": \"rename\", \"step\": ${cs}, \"rename\": {\"old\": \"${old}\", \"new\": \"${new}\"}} then --stand-in <auth.json>; otherwise --pm-card <the PM's card>"
  fi

  # the plan check and readiness BEFORE: the rename is refused only for what IT breaks
  _ac_plan_ok() {
    bash "${_AID_AC_LIB}/../aid-plan-check.sh" "$plan" --project-root "$troot" --quiet >/dev/null 2>&1 \
      && bash "${_AID_AC_LIB}/../aid-generation-readiness.sh" "$plan" --total 1 --project-root "$troot" >/dev/null 2>&1
  }

  # the transaction: every file is backed up first and put back on any failure
  local bk; bk="$(mktemp -d)"; local -a files=("$pj" "$sf"); [[ -f "$contract" ]] && files+=("$contract")
  [[ -n "$plan" ]] && files+=("$plan"); [[ -n "$zf" ]] && files+=("$zf")
  local seal=""; if declare -F aid_gen_transaction_path >/dev/null; then seal="$(aid_gen_transaction_path "$(_aid_fm_get "$plan" id 2>/dev/null)" 2>/dev/null)"; fi
  [[ -n "$seal" && -f "$seal" ]] && files+=("$seal")
  local i; for i in "${!files[@]}"; do cp -p "${files[$i]}" "${bk}/${i}"; done
  _ac_undo() { local j; for j in "${!files[@]}"; do cp -p "${bk}/${j}" "${files[$j]}"; done; rm -rf "$bk"; }

  local n_pj n_plan=0 n_z=0 n_c=0
  n_pj="$(_aid_ac_swap "$pj" "$old" "$new")"
  [[ -f "$contract" ]] && n_c="$(_aid_ac_swap "$contract" "$old" "$new")"
  [[ -n "$plan" ]] && n_plan="$(_aid_ac_swap "$plan" "$old" "$new")"
  [[ -n "$zf" ]] && n_z="$(_aid_ac_swap "$zf" "$old" "$new")"
  # fingerprints, in dependency order
  if (( n_z > 0 )); then
    local v; v="$(_aid_fm_get "$zf" verze)"; [[ "$v" =~ ^[0-9]+$ ]] || { _ac_undo; _ac_fail rename_refused "the brief ${zf} has no integer verze" "fix the brief"; }
    sed -i "0,/^verze: ${v}\$/s//verze: $((v + 1))/" "$zf"
    if [[ -n "$plan" ]]; then
      sed -i "0,/^zadani_verze: .*/s//zadani_verze: $((v + 1))/; 0,/^zadani_sha256: .*/s//zadani_sha256: $(sha256sum "$zf" | cut -d' ' -f1)/" "$plan"
    fi
    jq --arg s "$(sha256sum "$zf" | cut -d' ' -f1)" '.zadani_sha256 = $s' "$pj" > "${pj}.tmp" && mv "${pj}.tmp" "$pj"
  fi
  [[ -n "$plan" ]] && { jq --arg s "$(sha256sum "$plan" | cut -d' ' -f1)" '.source_plan_sha256 = $s' "$pj" > "${pj}.tmp" && mv "${pj}.tmp" "$pj"; }
  if [[ -f "$contract" ]]; then
    local oldv newv; oldv="$(jq -r .version "$contract")"
    declare -F _aid_dc_version >/dev/null || source "${_AID_AC_LIB}/aid-dispatch-contract.sh"
    newv="$(_aid_dc_version "$(jq -c 'del(.version, .return_shape, .superseded_versions, .amendments)' "$contract")")"
    jq --arg o "$oldv" --arg n "$newv" '.version = $n | .superseded_versions = ((.superseded_versions // []) + [$o])' "$contract" > "${contract}.tmp" && mv "${contract}.tmp" "$contract"
  fi
  sed -i "s/^plan_json_hash: .*/plan_json_hash: $(sha256sum "$pj" | cut -d' ' -f1)/" "$sf"
  [[ -n "$seal" && -f "$seal" && -n "$plan" ]] && { jq --arg s "$(sha256sum "$plan" | cut -d' ' -f1)" '.plan_sha256 = $s' "$seal" > "${seal}.tmp" && mv "${seal}.tmp" "$seal"; }

  # the plan still passes its check and readiness, or nothing changed
  # the plan passes its check and readiness after the rename, or nothing changed (Codex review: always, not only
  # when it passed before — a plan inside a run passed both at its start)
  if [[ -n "$plan" ]] && ! _ac_plan_ok; then
    local out; out="$(bash "${_AID_AC_LIB}/../aid-plan-check.sh" "$plan" --project-root "$troot" 2>&1; bash "${_AID_AC_LIB}/../aid-generation-readiness.sh" "$plan" --total 1 --project-root "$troot" 2>&1)"
    _ac_undo; _ac_fail rename_breaks_plan "after the rename the plan does not pass its check and readiness: $(grep -E 'BLOCK|FAIL' <<< "$out" | head -3 | tr '\n' ' ')" "choose another name"
  fi
  rm -rf "$bk"

  # the measurement and review of every step that names the path (the current one, and any other that reads it)
  # were of the old name: moved aside, never deleted
  local at k sf2 moved=""; at="$(date -u +%Y%m%dT%H%M%SZ)"; sf2="$(mktemp)"
  for (( k=0; k<total; k++ )); do
    jq --argjson i "$k" '.steps[$i]' "$pj" > "$sf2"
    if (( k == cs )) || _aid_ac_has "$sf2" "$new"; then
      [[ -d "${ev}/cp2/step-${k}" ]] && { mv "${ev}/cp2/step-${k}" "${ev}/cp2/step-${k}.renamed-${at}"; moved+=" $((k + 1))"; }
    fi
  done
  rm -f "$sf2"
  mkdir -p "$cdir"
  local rec="${cdir}/contract-amendments.json"; [[ -f "$rec" ]] || echo '[]' > "$rec"
  jq --arg o "$old" --arg n "$new" --arg r "$reason" --argjson d "$decision" --arg at "$at" \
     --argjson c "{\"plan_json\": ${n_pj:-0}, \"contract\": ${n_c:-0}, \"plan\": ${n_plan:-0}, \"brief\": ${n_z:-0}}" \
     '. + [{rename: {old: $o, new: $n}, reason: $r, decision: $d, replacements: $c, at: $at}]' "$rec" > "${rec}.tmp" && mv "${rec}.tmp" "$rec"
  log_event "${ev}/timeline.jsonl" contract_renamed step="$cs" old="$old" new="$new" reason="$reason" || true
  declare -F fsm_emit_audit_log >/dev/null && fsm_emit_audit_log "contract_renamed" --evidence-dir "$ev" --reason "${old} → ${new}: ${reason}" >/dev/null 2>&1 || true
  echo "renamed ${old} → ${new} in step $((cs + 1)): plan.json ${n_pj}, contract ${n_c}, plan ${n_plan}, brief ${n_z} (verze +$(( n_z > 0 ? 1 : 0 ))); measurement and review start again for step(s)${moved:- none} (${rec})"
}
