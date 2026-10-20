#!/usr/bin/env bash
# =============================================================================
# aid-stand-in.sh — an --auto run's decision that is not a review finding, made by the independent stand-in
# instead of the PM (P117 (11); review findings stay with aid-review-round.sh delegate, P112).
#
#   aid-stand-in.sh ask    --evidence-dir <run> --code <refusal code> --proposal <file.json> [--tree-root <dir>]
#   aid-stand-in.sh record --evidence-dir <run> --id <id> --verdict <file.json> [--tree-root <dir>]
#
# ask: the code's class must be stand_in or agent_fix_then_stand_in (defaults/refusal-classes.yaml), the
# PM's delegation in force for the plan (an --auto plan, or standing --delegate), and the proposal no
# protected impact (lib/aid-protected.sh; protected → exit 3, the PM's card). Then Codex decides through the
# shared transport; when it cannot, exit 4 with a STAND-IN line: a Claude agent inside a dispatch bracket.
# A Codex verdict is recorded at once.
# record: checks the verdict (shape, its origin — the runner's event for Codex, the closed bracket for Claude —,
# a worktree the stand-in left as it found it), the detector again, then writes auth.json (the permission
# amend-scope / increment-step take as --stand-in) and one ledger line in the plan's delegated-disputes.jsonl.
# Exit: 0 decided (approve or reject, printed), 1 refused, 2 usage, 3 protected → PM, 4 stand-in needed.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aid-roots.sh"
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
source "${SCRIPT_DIR}/lib/aid-stand-in.sh"

CMD="${1:-}"; shift || true
EVID="" CODE="" PROPOSAL="" ID="" VERDICT="" TROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence-dir) EVID="${2:-}"; shift 2 ;;
    --code)         CODE="${2:-}"; shift 2 ;;
    --proposal)     PROPOSAL="${2:-}"; shift 2 ;;
    --id)           ID="${2:-}"; shift 2 ;;
    --verdict)      VERDICT="${2:-}"; shift 2 ;;
    --tree-root)    TROOT="${2:-}"; shift 2 ;;
    *) echo "aid-stand-in: unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -n "$EVID" && -d "$EVID" ]] || { echo "aid-stand-in: --evidence-dir <the run's evidence directory> required" >&2; exit 2; }
EVID="$(cd "$EVID" && pwd)"
[[ -n "$TROOT" ]] || TROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SROOT="$(aid_state_root "$TROOT" 2>/dev/null || echo "$TROOT")"
PLAN_PATH="$(yq -r '.plan_path // ""' "${EVID}/fsm-state.yaml" 2>/dev/null)"
PID="$( [[ -f "$PLAN_PATH" ]] && _aid_plan_id_of "$PLAN_PATH" || true)"
TL="${EVID}/timeline.jsonl"

_refuse() {   # <code> <why> <next>
  echo "aid-stand-in ${CMD}: REFUSED ($1): $2" >&2; echo "next: $3" >&2; echo "(pipeline.md §When AID refuses: $1)" >&2; exit 1
}
_to_pm() {
  echo "aid-stand-in ${CMD}: PROTECTED ($1) — the PM decides: render the Decision card quoting it (lib/aid-decision-card.sh), whatever a stand-in would say" >&2
  echo "(pipeline.md §When AID refuses: stand_in_protected)" >&2
  log_event "$TL" stand_in_protected id="${ID:-}" code="${CODE:-}" why="$1" || true
  exit 3
}
_tree_state() {   # the worktree as a stand-in must leave it (the delegate's record, P112 F14)
  { git -C "$TROOT" status --porcelain --untracked-files=all --ignored=traditional 2>/dev/null | grep -v '^.. \.aid-o/' || true
    printf '## head %s\n' "$(git -C "$TROOT" rev-parse HEAD 2>/dev/null)"
    printf '## tracked-content %s\n' "$(git -C "$TROOT" diff HEAD --binary 2>/dev/null | sha256sum | cut -d' ' -f1)"; } | sort
}

cmd_ask() {
  [[ -n "$CODE" && -f "$PROPOSAL" ]] || { echo "ask needs --code and --proposal <file>" >&2; exit 2; }
  local class; class="$(C="$CODE" yq -r '.codes[strenv(C)].class // ""' "${SCRIPT_DIR}/../defaults/refusal-classes.yaml" 2>/dev/null)"
  [[ "$class" == stand_in || "$class" == agent_fix_then_stand_in ]] \
    || _refuse stand_in_not_allowed "${CODE} is class ${class:-pm (unknown code)}, not one a stand-in decides" "follow the refusal's own next: line"
  [[ -n "$PID" ]] || _refuse delegation_missing "cannot tell the plan of ${EVID} (fsm-state.yaml plan_path)" "run from the plan's run"
  aid_delegate_in_force "$SROOT" "$PID" \
    || _refuse delegation_missing "no delegation is in force for ${PID} (its plan state is not autonomy: auto, or the PM stopped the run)" "the PM decides on a Decision card"
  ID="$(aid_stand_in_id "$CODE" "$PROPOSAL")"
  local d; d="$(aid_stand_in_dir "$EVID" "$ID")"; mkdir -p "$d"
  if [[ -f "${d}/auth.json" ]]; then echo "stand-in ${ID}: already decided — $(jq -r '"\(if .approved then "approved" else "rejected" end): \(.reason)"' "${d}/auth.json") (${d}/auth.json)"; return 0; fi
  jq -S . "$PROPOSAL" > "${d}/proposal.json"; jq -n --arg c "$CODE" '{code: $c}' > "${d}/meta.json"
  # the runner's record of the question: record accepts a verdict only for a decision asked through here
  log_event "$TL" stand_in_asked id="$ID" code="$CODE" proposal_sha256="$(sha256sum "${d}/proposal.json" | cut -d' ' -f1)" || true
  local why; why="$(aid_protected_impact "$SROOT" "$TROOT" "${d}/proposal.json" "$EVID")" || _to_pm "$why"
  local brief; brief="$(jq -r '.zadani // ""' "${EVID}/plan.json" 2>/dev/null)"
  {
    cat "${SCRIPT_DIR}/../defaults/templates/stand-in-decision.md"
    printf '\n## The decision\n\nRefusal: `%s` (class %s): %s\n\nRun evidence: %s\nPlan: %s\nBrief (the PM'"'"'s points of done): %s\n\n' \
      "$CODE" "$class" "$(C="$CODE" yq -r '.codes[strenv(C)].how // ""' "${SCRIPT_DIR}/../defaults/refusal-classes.yaml")" "$EVID" "$PLAN_PATH" "${brief:-none}"
    printf '## The proposal\n\n```json\n'; cat "${d}/proposal.json"; printf '```\n\n'
    printf 'Your final message is ONE JSON object and nothing else: {"id": "%s", "answer": "approve"|"reject", "class": "technical"|"brief"|"money"|"data"|"security"|"production"|"foreign_api"|"foreign_repo"|"gate", "reason": "<one sentence the PM can check>", "provider": "codex"|"claude"}.\n' "$ID"
    printf 'In a read-only sandbox do not write a file: your final message is saved to %s. A stand-in that can write files writes that object there.\n' "${d}/verdict.json"
    printf 'Leave nothing behind in the repository.\n'
  } > "${d}/prompt.md"
  _tree_state > "${d}/status-before"
  local probe='{}' rc=0
  if [[ -n "${AID_CODEX_PROBE_STUB:-}" || -n "$(command -v codex 2>/dev/null)" ]]; then
    probe="$( source "${SCRIPT_DIR}/lib/aid-codex-transport.sh"; aid_codex_probe 2>/dev/null )" || true
  fi
  if [[ "$(jq -r '.available // false' <<< "$probe" 2>/dev/null)" == true ]]; then
    ( source "${SCRIPT_DIR}/lib/aid-codex-transport.sh"; CODEX_EFFORT=medium
      _run_codex_isolated "$TROOT" "${d}/prompt.md" "${d}/codex.events.jsonl" "${d}/codex.stderr.txt" "${d}/codex.last.txt" ) || rc=$?
    if [[ -s "${d}/codex.last.txt" ]] && sed -e '/^```/d' "${d}/codex.last.txt" | jq -e 'type == "object"' >/dev/null 2>&1; then
      sed -e '/^```/d' "${d}/codex.last.txt" | jq '.provider = "codex"' > "${d}/verdict.json"
      log_event "$TL" stand_in_codex_verdict id="$ID" sha256="$(sha256sum "${d}/verdict.json" | cut -d' ' -f1)" || true
      VERDICT="${d}/verdict.json"; cmd_record; return $?
    fi
  fi
  echo "STAND-IN: no codex verdict; dispatch ${d}/prompt.md to an independent general-purpose agent at model opus inside the bracket stand-in-${ID} (aid-emit-dispatch.sh start --focus stand-in-${ID} --agent-id claude:stand-in --evidence-dir ${EVID}; complete --focus stand-in-${ID} --output-file ${d}/verdict.json --evidence-dir ${EVID}), have it write ${d}/verdict.json with \"provider\": \"claude\", then: aid-stand-in.sh record --evidence-dir ${EVID} --id ${ID} --verdict ${d}/verdict.json"
  exit 4
}

cmd_record() {
  [[ -n "$ID" ]] || { echo "record needs --id" >&2; exit 2; }
  local d; d="$(aid_stand_in_dir "$EVID" "$ID")"
  [[ -f "${d}/proposal.json" ]] || _refuse stand_in_missing "no proposal for ${ID} under ${d}" "aid-stand-in.sh ask first"
  # the same gates as ask (security review of P117): a code the stand-in may decide, the delegation in force,
  # the id of THIS code and proposal, and the runner's record that ask asked it
  CODE="$(jq -r '.code // ""' "${d}/meta.json" 2>/dev/null)"
  local _cl; _cl="$(C="$CODE" yq -r '.codes[strenv(C)].class // ""' "${SCRIPT_DIR}/../defaults/refusal-classes.yaml" 2>/dev/null)"
  [[ "$_cl" == stand_in || "$_cl" == agent_fix_then_stand_in ]] || _refuse stand_in_not_allowed "${CODE:-<no code>} is not a code the stand-in decides" "ask through aid-stand-in.sh ask"
  [[ -n "$PID" ]] && aid_delegate_in_force "$SROOT" "$PID" || _refuse delegation_missing "no delegation is in force for ${PID:-<no plan>}" "the PM decides on a Decision card"
  [[ "$(aid_stand_in_id "$CODE" "${d}/proposal.json")" == "$ID" ]] || _refuse stand_in_missing "${ID} is not the id of its code and proposal (edited after ask?)" "ask again"
  jq -e -nR --arg i "$ID" --arg s "$(sha256sum "${d}/proposal.json" | cut -d' ' -f1)" 'any(inputs; (try fromjson catch null) as $j | $j != null and $j.event? == "stand_in_asked" and $j.id? == $i and $j.proposal_sha256? == $s)' "$TL" >/dev/null 2>&1 \
    || _refuse stand_in_missing "the run's timeline has no stand_in_asked record for ${ID} with this proposal" "aid-stand-in.sh ask"
  [[ -f "$VERDICT" && "$(realpath "$VERDICT")" == "$(realpath -m "${d}/verdict.json")" ]] \
    || _refuse stand_in_missing "the verdict of ${ID} is ${d}/verdict.json" "have the stand-in write it there, then record"
  local f
  jq -e 'type == "object"' "$VERDICT" >/dev/null 2>&1 || _refuse stand_in_verdict_invalid "the verdict is not one JSON object" "ask again"
  for f in id answer class reason provider; do
    jq -e --arg f "$f" '(.[$f] // "") | type == "string" and length > 0' "$VERDICT" >/dev/null 2>&1 \
      || _refuse stand_in_verdict_invalid "the verdict has no ${f}" "the stand-in writes all five fields"
  done
  [[ "$(jq -r .id "$VERDICT")" == "$ID" ]] || _refuse stand_in_verdict_invalid "the verdict names $(jq -r .id "$VERDICT"), not ${ID}" "ask again"
  jq -e '.answer | IN("approve", "reject")' "$VERDICT" >/dev/null || _refuse stand_in_verdict_invalid "answer is approve or reject" "ask again"
  jq -e '.class | IN("technical","brief","money","data","security","production","foreign_api","foreign_repo","gate")' "$VERDICT" >/dev/null \
    || _refuse stand_in_verdict_invalid "class is not one of the closed list" "ask again"
  local provider sha; provider="$(jq -r .provider "$VERDICT")"; sha="$(sha256sum "$VERDICT" | cut -d' ' -f1)"
  if [[ "$provider" == codex ]]; then
    jq -e -nR --arg i "$ID" --arg s "$sha" 'any(inputs; (try fromjson catch null) as $j | $j != null and $j.event? == "stand_in_codex_verdict" and $j.id? == $i and $j.sha256? == $s)' "$TL" >/dev/null 2>&1 \
      || _refuse stand_in_verdict_unbound "a codex verdict without the runner's record (no stand_in_codex_verdict event with this sha256 in ${TL})" "let aid-stand-in.sh ask run Codex"
  elif [[ "$provider" == claude ]]; then
    # the bracket closed over THIS file with THIS content (Codex review of P117 D: a bracket over another file vouched for nothing)
    jq -e -s --arg f "stand-in-${ID}" --arg o "$(realpath "$VERDICT")" --arg s "$sha" \
      'any(.[]; .event == "verifier_dispatch_start" and .focus == $f and .agent_id == "claude:stand-in")
       and any(.[]; .event == "verifier_dispatch_complete" and .focus == $f and .output_sha256 == $s
                    and ((.output_file // "") as $p | ($p == $o) or ($p | endswith("/stand-in/" + ($f | ltrimstr("stand-in-")) + "/verdict.json"))))' "$TL" >/dev/null 2>&1 \
      || _refuse stand_in_verdict_unbound "a Claude verdict without its closed bracket stand-in-${ID} (agent claude:stand-in) over this verdict file and its content" "dispatch inside the bracket, write the verdict, complete the bracket with --output-file ${VERDICT}, then record"
    [[ -f "${d}/status-before" ]] || _refuse delegation_left_files "no record of the worktree before the stand-in ran (${d}/status-before)" "ask again (it records the tree first)"
    local left; left="$(comm -13 "${d}/status-before" <(_tree_state) | sed 's/^...//' | head -20 || true)"
    [[ -z "$left" ]] || _refuse delegation_left_files "the stand-in left files in ${TROOT}: $(tr '\n' ' ' <<< "$left")" "remove them, then record again"
  else
    _refuse stand_in_verdict_invalid "provider is codex or claude" "ask again"
  fi
  local why; why="$(aid_protected_impact "$SROOT" "$TROOT" "${d}/proposal.json" "$EVID")" || _to_pm "$why"
  local class answer approved=false; class="$(jq -r .class "$VERDICT")"; answer="$(jq -r .answer "$VERDICT")"
  [[ "$class" == technical ]] || _to_pm "the stand-in classed it ${class}: $(jq -r .reason "$VERDICT")"
  [[ "$answer" == approve ]] && approved=true
  jq -n --arg id "$ID" --arg code "$(jq -r '.code // ""' "${d}/meta.json" 2>/dev/null)" --arg kind "$(jq -r .kind "${d}/proposal.json")" \
    --arg ps "$(sha256sum "${d}/proposal.json" | cut -d' ' -f1)" --arg vs "$sha" --arg p "$provider" --argjson ok "$approved" \
    --arg r "$(jq -r .reason "$VERDICT")" --arg sr "$SROOT" --arg pid "$PID" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id: $id, code: $code, kind: $kind, approved: $ok, reason: $r, provider: $p, proposal_sha256: $ps, verdict_sha256: $vs, state_root: $sr, plan: $pid, at: $at}' > "${d}/auth.json.tmp" \
    && mv "${d}/auth.json.tmp" "${d}/auth.json" || _refuse stand_in_write_failed "${d}/auth.json could not be written" "fix the disk, then record again"
  local ledger; ledger="$(aid_delegate_ledger "$SROOT" "$PID")"; mkdir -p "$(dirname "$ledger")"
  jq -nc --arg id "$ID" --arg k "$(jq -r .kind "${d}/proposal.json")" --arg a "$answer" --arg c "$class" --arg r "$(jq -r .reason "$VERDICT")" \
    --arg p "$provider" --arg v "$(realpath "$VERDICT")" --arg vs "$sha" --arg run "$EVID" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{checkpoint: "stand_in", id: $id, kind: $k, answer: $a, class: $c, reason: $r, provider: $p, verdict_file: $v, verdict_sha256: $vs, run: $run, at: $at}' >> "$ledger" \
    || { rm -f "${d}/auth.json"; _refuse stand_in_write_failed "the ledger ${ledger} could not be written; the permission is withdrawn" "fix the disk, then record again"; }
  log_event "$TL" stand_in_recorded id="$ID" answer="$answer" provider="$provider" || true
  echo "stand-in ${ID}: ${answer} by ${provider} — $(jq -r .reason "$VERDICT") (permission: ${d}/auth.json)"
}

case "$CMD" in
  ask) cmd_ask ;;
  record) cmd_record ;;
  *) echo "usage: aid-stand-in.sh ask|record …" >&2; exit 2 ;;
esac
