#!/usr/bin/env bash
# =============================================================================
# aid-plan-review-adjudicate.sh — turn a round's valid answers into one list.
#
#   aid-plan-review-adjudicate.sh <round_dir> --project-root <dir> [--previous <round_dir>]
#
# Deterministic, no model call. For every finding of every answer that collect
# accepted (collect.json .valid):
#   - a command outside the read-only vocabulary   → rejected: missing_command
#   - an evidence that is not path:line[; path:line] → rejected: missing_evidence
#   - an evidence path outside the project, under .aid-worktrees/, missing, or a
#     line beyond the file's end                    → rejected: evidence_not_found
#   - the same fingerprint twice from one reviewer   → rejected: duplicate
# What survives is merged by fingerprint (step, first evidence file, first
# eight words of the claim): the highest severity wins, every reporter is listed.
#
# Writes <round_dir>/merged.json, rejected.json and yield.json. With --previous,
# a previous open blocker or major (the findings a confirmation round is shown)
# is marked fixed when every reviewer that reported it answered this round and
# none reported it again; minors are not re-checked and stay as they were.
#
# Exit: 0 all outputs written (the blocker count is data, not an exit code),
#       1 unreadable input or a failed write (partial outputs are removed),
#       2 usage.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AID_PLUGIN_PATH="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# shellcheck source=lib/aid-finding-fingerprint.sh
source "${SCRIPT_DIR}/lib/aid-finding-fingerprint.sh"
# shellcheck source=lib/aid-plan-review-packet.sh
source "${SCRIPT_DIR}/lib/aid-plan-review-packet.sh"

DIR="" ROOT="" PREV=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) ROOT="${2:-}"; shift 2 ;;
    --previous)     PREV="${2:-}"; shift 2 ;;
    -*) echo "adjudicate: unknown option $1" >&2; exit 2 ;;
    *)  DIR="$1"; shift ;;
  esac
done
[[ -n "$DIR" && -n "$ROOT" ]] || { echo "Usage: aid-plan-review-adjudicate.sh <round_dir> --project-root <dir> [--previous <round_dir>]" >&2; exit 2; }
[[ -r "${DIR}/round.json" && -r "${DIR}/collect.json" ]] || { echo "adjudicate: cannot read ${DIR}" >&2; exit 1; }
ROOT="$(realpath "$ROOT")"

OUTS=("${DIR}/merged.json" "${DIR}/rejected.json" "${DIR}/yield.json")
_fail() { echo "adjudicate: $1" >&2; rm -f "${OUTS[@]}"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
: > "${WORK}/accepted.jsonl"; : > "${WORK}/rejected.jsonl"; : > "${WORK}/originated.jsonl"
PLAN_LINES="$(wc -l < "${DIR}/packet/plan.md" 2>/dev/null || echo 0)"

# _evidence_found <evidence> — every path:line exists inside the project.
_evidence_found() {
  local item path line abs
  IFS=';' read -ra items <<< "$1"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    path="${item%:*}"; line="${item##*:}"
    (( line >= 1 )) || return 1
    if [[ "$path" == plan.md ]]; then
      (( line <= PLAN_LINES )) || return 1; continue
    fi
    [[ "$path" == /* ]] || path="${ROOT}/${path}"
    # Resolved, so neither `..`, `./` nor a symlink can leave the project.
    abs="$(realpath -e -- "$path" 2>/dev/null)" || return 1
    [[ "$abs" == "$ROOT"/* && "$abs" != "$ROOT"/.aid-worktrees/* && -f "$abs" ]] || return 1
    (( line <= $(awk 'END { print NR }' "$abs") )) || return 1
  done
}

# _claim_key <claim> — first eight words, lower case, single spaces.
_claim_key() { tr '[:upper:]' '[:lower:]' <<< "$1" | tr -s '[:space:]' ' ' | cut -d' ' -f1-8 | sed 's/ *$//'; }

project_id="$(basename "$ROOT")"
mapfile -t VALID < <(jq -r '.valid[]' "${DIR}/collect.json")
for role in "${VALID[@]}"; do
  answer="${DIR}/reviewer-${role}.json"
  [[ -r "$answer" ]] || _fail "cannot read ${answer}"
  declare -A seen=()
  while IFS= read -r f; do
    jq -c --arg r "$role" '{role: $r, id}' <<< "$f" >> "${WORK}/originated.jsonl"
    id="$(jq -r '.id' <<< "$f")"
    reason="$(jq -r --slurpfile s "$AID_PR_SCHEMA" "$(aid_plan_review_proof_jq) proof_error // \"\"" <<< "$f")" \
      || _fail "cannot read a finding of ${answer}"
    if [[ -z "$reason" ]] && ! _evidence_found "$(jq -r '.evidence' <<< "$f")"; then
      reason=evidence_not_found
    fi
    if [[ -z "$reason" ]]; then
      step="$(jq -r '.step // "plan"' <<< "$f")"
      # The first evidence FILE, not its line: a fix that shifts lines must not
      # turn an unresolved finding into a new one.
      first="$(jq -r '.evidence | split(";")[0] | gsub("^\\s+|\\s+$"; "") | sub(":[0-9]+$"; "")' <<< "$f")"
      fp="$(fingerprint "$project_id" plan_review "$step" "$first" "$(_claim_key "$(jq -r '.claim' <<< "$f")")")"
      if [[ -n "${seen[$fp]:-}" ]]; then
        reason=duplicate
      else
        seen[$fp]=1
        jq -c --arg r "$role" --arg fp "$fp" '. + {role: $r, fingerprint: $fp}' <<< "$f" >> "${WORK}/accepted.jsonl"
      fi
    fi
    [[ -n "$reason" ]] && jq -nc --arg r "$role" --arg id "$id" --arg why "$reason" \
      '{role: $r, id: $id, reason: $why}' >> "${WORK}/rejected.jsonl"
  done < <(jq -c '.findings[]' "$answer")
  unset seen
done

# Statuses a finding already carries (disputed, a PM answer) survive a rerun.
prior='{"findings":[]}'; [[ -r "${DIR}/merged.json" ]] && prior="$(cat "${DIR}/merged.json")"

jq -s --argjson round "$(jq '.round' "${DIR}/round.json")" \
      --arg sha "$(jq -r '.plan_sha256' "${DIR}/round.json")" --argjson prior "$prior" '
  def rank: {"blocker": 3, "major": 2, "minor": 1}[.];
  ($prior.findings | map({(.fingerprint): .}) | add // {}) as $old
  | group_by(.fingerprint)
  | map(sort_by(-(.severity | rank)) as $g
        | $g[0] as $top
        | ($old[$top.fingerprint] // {}) as $was
        | {fingerprint: $top.fingerprint, step: $top.step, severity: $top.severity,
           severity_reported: (map({(.role): .severity}) | add),
           claim: $top.claim, command: $top.command, evidence: $top.evidence, fix: $top.fix,
           reported_by: (map(.role) | unique), also_reported_by: (map(.role) | unique | length),
           status: ($was.status // "open")}
        + (if $was.dispute then {dispute: $was.dispute} else {} end))
  | {plan_sha256: $sha, round: $round, findings: .,
     blockers_open: (map(select(.severity == "blocker" and (.status == "open" or .status == "disputed"))) | length)}
' "${WORK}/accepted.jsonl" > "${DIR}/merged.json" || _fail "cannot write merged.json"

jq -s '.' "${WORK}/rejected.jsonl" > "${DIR}/rejected.json" || _fail "cannot write rejected.json"

# yield per expected role; `fixed` is filled in by the next round's --previous.
jq -n --slurpfile o "${WORK}/originated.jsonl" --slurpfile m "${DIR}/merged.json" \
      --argjson roles "$(jq '.reviewers_expected' "${DIR}/round.json")" '
  reduce $roles[] as $r ({};
    .[$r] = {originated: ([$o[] | select(.role == $r)] | length),
             survived: ([$m[0].findings[] | select(.reported_by | index($r))] | length),
             fixed: 0})
' > "${DIR}/yield.json" || _fail "cannot write yield.json"

if [[ -n "$PREV" ]]; then
  [[ -r "${PREV}/merged.json" ]] || _fail "cannot read ${PREV}/merged.json"
  tmp="${WORK}/prev-merged.json"
  jq --slurpfile now "${DIR}/merged.json" --argjson answered "$(jq '.valid' "${DIR}/collect.json")" '
    ($now[0].findings | map(.fingerprint)) as $still
    | .findings |= map(
        if .status == "open" and (.severity == "blocker" or .severity == "major")
           and (.fingerprint | IN($still[]) | not)
           and (.reported_by - $answered | length) == 0
        then .status = "fixed" else . end)
    | .blockers_open = ([.findings[] | select(.severity == "blocker" and (.status == "open" or .status == "disputed"))] | length)
  ' "${PREV}/merged.json" > "$tmp" && mv "$tmp" "${PREV}/merged.json" || _fail "cannot update ${PREV}/merged.json"
  if [[ -r "${PREV}/yield.json" ]]; then
    jq --slurpfile m "${PREV}/merged.json" '
      with_entries(.key as $r | .value.fixed =
        ([$m[0].findings[] | select(.status == "fixed" and (.reported_by | index($r)))] | length))
    ' "${PREV}/yield.json" > "$tmp" && mv "$tmp" "${PREV}/yield.json" || _fail "cannot update ${PREV}/yield.json"
  fi
fi

jq -r '"adjudicated round \(.round): \(.findings | length) findings, \(.blockers_open) blockers open"' "${DIR}/merged.json"
echo "  rejected: $(jq 'length' "${DIR}/rejected.json")"
