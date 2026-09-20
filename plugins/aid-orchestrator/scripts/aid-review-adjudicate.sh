#!/usr/bin/env bash
# =============================================================================
# aid-review-adjudicate.sh — turn a review round's valid answers into one list,
# for any checkpoint (P094 Step 5; the CP1-only adjudicator is gone).
#
#   aid-review-adjudicate.sh <round_dir> --project-root <dir> --namespace <ns>
#                            [--plan <packet/plan.md>] [--step-check <step-check.json>]
#                            [--previous <round_dir>]
#
#   <ns>  plan_review (CP1) | step_review (CP2) | epic_review (CP3) | do_review (CP6)
#
# Deterministic, no model call. For every finding of every answer that collect
# accepted (collect.json .valid):
#   - a command outside the read-only vocabulary, or a `bash repro/<x>.sh` whose
#     script is not under the round's repro/          → rejected: missing_command
#   - an evidence that is not [<sha>:]path:line[; …]  → rejected: missing_evidence
#   - an evidence path outside the project, under .aid-worktrees/, missing, a
#     line beyond the file's end, or a pre-image sha that is not an ancestor
#     of HEAD; `plan.md:line` is accepted only with --plan → rejected: evidence_not_found
#   - a generalist's blocker or major without a behaviour trace while the step
#     check reports a handler pattern (--step-check)   → rejected: trace_missing
#   - the same fingerprint twice from one reviewer     → rejected: duplicate
# What survives is merged by fingerprint — the five-argument formula of
# lib/aid-finding-fingerprint.sh: project, namespace, the step (`.step`, or the
# literal "plan"/"epic"/"do" per namespace), the first evidence with its line,
# the first eight words of the claim; the next round matches it by the same
# key without the evidence line. CP1 keeps its `plan_review` namespace and its
# `.step // "plan"` third argument, so fingerprints recorded before this script
# existed do not change. The highest severity wins, every reporter is listed.
# The step check's own findings (forbidden paths) enter the list as role
# `step_check`, no command required: the script is the command.
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

DIR="" ROOT="" PREV="" NS="" PLAN="" STEP_CHECK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) ROOT="${2:-}"; shift 2 ;;
    --previous)     PREV="${2:-}"; shift 2 ;;
    --namespace)    NS="${2:-}"; shift 2 ;;
    --plan)         PLAN="${2:-}"; shift 2 ;;
    --step-check)   STEP_CHECK="${2:-}"; shift 2 ;;
    -*) echo "adjudicate: unknown option $1" >&2; exit 2 ;;
    *)  DIR="$1"; shift ;;
  esac
done
usage() { echo "Usage: aid-review-adjudicate.sh <round_dir> --project-root <dir> --namespace plan_review|step_review|epic_review|do_review [--plan <plan.md>] [--step-check <json>] [--previous <round_dir>]" >&2; exit 2; }
[[ -n "$DIR" && -n "$ROOT" && -n "$NS" ]] || usage
case "$NS" in plan_review|step_review|epic_review|do_review) ;; *) usage ;; esac
[[ -r "${DIR}/round.json" && -r "${DIR}/collect.json" ]] || { echo "adjudicate: cannot read ${DIR}" >&2; exit 1; }
[[ -z "$PLAN" || -r "$PLAN" ]] || { echo "adjudicate: cannot read ${PLAN}" >&2; exit 1; }
[[ -z "$STEP_CHECK" || -r "$STEP_CHECK" ]] || { echo "adjudicate: cannot read ${STEP_CHECK}" >&2; exit 1; }
ROOT="$(realpath "$ROOT")"

OUTS=("${DIR}/merged.json" "${DIR}/rejected.json" "${DIR}/yield.json")
_fail() { echo "adjudicate: $1" >&2; rm -f "${OUTS[@]}"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
: > "${WORK}/accepted.jsonl"; : > "${WORK}/rejected.jsonl"; : > "${WORK}/originated.jsonl"
PLAN_LINES=0; [[ -n "$PLAN" ]] && PLAN_LINES="$(wc -l < "$PLAN")"
HANDLERS=0; [[ -n "$STEP_CHECK" ]] && HANDLERS="$(jq -r '.handler_patterns // [] | length' "$STEP_CHECK" 2>/dev/null || echo 0)"
git_() { git -C "$ROOT" "$@"; }

# _evidence_found <evidence> — every [<sha>:]path:line exists inside the project.
# _evidence_item_ok <item> — one citation resolves: `path:line` at HEAD,
# `<sha>:path:line` at an ancestor commit, `plan.md:line` (CP1), or
# `absent:path` for a file the step should have produced and did not.
_evidence_item_ok() {
  local item="$1" path line abs sha
  item="${item#"${item%%[![:space:]]*}"}"
  if [[ "$item" == absent:* ]]; then
    path="${item#absent:}"
    [[ -n "$path" && "$path" != /* && "$path" != *..* ]] || return 1
    [[ ! -e "${ROOT}/${path}" ]] || return 1
    return 0
  fi
  sha=""
  if [[ "$item" =~ ^([0-9a-f]{7,40}):(.+):([0-9]+)$ ]]; then
    sha="${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"; line="${BASH_REMATCH[3]}"
  else
    path="${item%:*}"; line="${item##*:}"
  fi
  [[ "$line" =~ ^[0-9]+$ ]] || return 1
  if [[ -z "$sha" && "$path" == plan.md ]]; then
    [[ -n "$PLAN" ]] || return 1
    (( line >= 1 && line <= PLAN_LINES )) || return 1; return 0
  fi
  [[ "$path" != /* && "$path" != *..* && "$path" != .aid-worktrees/* ]] || return 1
  if [[ -n "$sha" ]]; then
    # A pre-image: the sha must be history of this checkout and the path must exist in it.
    git_ cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
    git_ merge-base --is-ancestor "$sha" HEAD 2>/dev/null || return 1
    git_ cat-file -e "${sha}:${path}" 2>/dev/null || return 1
    (( line <= $(git_ show "${sha}:${path}" 2>/dev/null | awk 'END { print NR }') )) || return 1
    return 0
  fi
  # Resolved, so neither `..`, `./` nor a symlink can leave the project.
  abs="$(realpath -e -- "${ROOT}/${path}" 2>/dev/null)" || return 1
  [[ "$abs" == "$ROOT"/* && "$abs" != "$ROOT"/.aid-worktrees/* && -f "$abs" ]] || return 1
  (( line <= $(awk 'END { print NR }' "$abs") )) || return 1
}

# _evidence_norm <item> — trims and collapses a range citation `path:N-M` to the
# line it is anchored on, `path:N`; exit 1 on a reversed range.
_evidence_norm() {
  local item="$1"
  item="${item#"${item%%[![:space:]]*}"}"
  if [[ "$item" =~ ^(.+):([0-9]+)-([0-9]+)$ ]]; then
    # 10# or bash aborts the arithmetic on a zero-padded number (`08: value
    # too great for base`), which drops a valid citation AND prints to stderr.
    (( 10#${BASH_REMATCH[2]} <= 10#${BASH_REMATCH[3]} )) || return 1
    item="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
  fi
  printf '%s' "$item"
}

# _evidence_first_ok <evidence> — prints the first citation that resolves, in its
# normalised `path:N` form; a finding stands on ONE resolving citation (P094
# acceptance run: three real defects were lost to one wrong line number among
# several right ones). Exit 1 when none resolves.
_evidence_first_ok() {
  local item norm
  IFS=';' read -ra items <<< "$1"
  for item in "${items[@]}"; do
    norm="$(_evidence_norm "$item")" || continue
    _evidence_item_ok "$norm" && { printf '%s' "$norm"; return 0; }
  done
  return 1
}

# The verbs an inline reproduction may start a segment with. Every one of them
# READS and has no mode that writes: that is the whole criterion, and it is why
# the list is shorter than the one P095 was planned with. An independent review
# of 2026-09-20 walked through what the planned list actually admitted and the
# answer was "anything":
#   - `mkdir`, `touch`, `mktemp`, `cd` and `export` write, or move the ground a
#     later verb stands on (`export PATH=/tmp/evil:$PATH` hijacks every verb
#     after it);
#   - the shell keywords `if then else fi for do done` open a segment whose
#     FIRST word is the keyword, so only the keyword was ever checked and
#     `if true; then rm -rf x; fi` passed;
#   - `find` has `-exec`/`-delete`, `sed` has `-i` and its `w` command, `yq`
#     has `-i`. A verb with a write mode needs a flag vocabulary to be safe,
#     and a flag vocabulary rots.
# A reviewer who needs any of those writes a `repro/<name>.sh` file, which is
# what the file form is for: a human can read it once before running it.
_INLINE_VERBS=" grep rg ls git wc head tail cat printf echo jq test [[ [ "

# _inline_body_ok <body> — a bounded read-only pipeline: every segment starts
# with a verb from the list, nothing redirects, substitutes a command, opens a
# new line, or edits a file in place.
_inline_body_ok() {
  local body="$1" i ch inq=0 seg="" s w n=${#1}
  local -a segs=() words=()
  # A newline is a command separator the segment splitter below cannot see, a
  # backslash can quote one, and both forms of process substitution run code.
  case "$body" in
    *$'\n'*|*\\*|*'$('*|*'`'*|*'<('*|*'>('*) return 1 ;;
  esac
  for (( i=0; i<n; i++ )); do
    ch="${body:i:1}"
    if [[ "$ch" == '"' ]]; then inq=$(( ! inq )); seg+="$ch"; continue; fi
    if (( inq )); then seg+="$ch"; continue; fi
    case "$ch" in
      '>'|'<') return 1 ;;
      ';'|'|'|'&') segs+=("$seg"); seg="" ;;
      *) seg+="$ch" ;;
    esac
  done
  segs+=("$seg")
  for s in "${segs[@]}"; do
    read -ra words <<< "$s"
    (( ${#words[@]} > 0 )) || continue
    w="${words[0]}"
    [[ "$_INLINE_VERBS" == *" $w "* ]] || return 1
    # No in-place flag veto here on purpose: not one verb on the list HAS an
    # in-place mode, and a veto over every word rejected `grep -i`, the most
    # ordinary case-insensitive search there is — throwing a real finding away
    # on form, which is the failure P095 exists to end.
    if [[ "$w" == git ]]; then
      case "${words[1]:-}" in grep|log|show|diff|blame|rev-parse|status) ;; *) return 1 ;; esac
    fi
  done
  return 0
}

# _command_ok <command> — prints the rejection reason and returns 1 when the
# command is not a usable proof: a `bash repro/<x>.sh` whose file is not under
# the round's repro/, or an inline `bash -c '<body>'` that is not read-only.
_command_ok() {
  local cmd="$1" script
  if [[ "$cmd" =~ ^bash\ (repro/[a-z0-9_-]+\.sh)( |$) ]]; then
    script="${BASH_REMATCH[1]}"
    [[ -f "${DIR}/${script}" ]] || { printf missing_command; return 1; }
    return 0
  fi
  if [[ "$cmd" == "bash -c "* ]]; then
    if ! [[ "$cmd" =~ ^bash\ -c\ \'([^\']*)\'[[:space:]]*$ ]] || ! _inline_body_ok "${BASH_REMATCH[1]}"; then
      printf command_not_read_only; return 1
    fi
  fi
  return 0
}

# _claim_key <claim> — first eight words, lower case, single spaces.
_claim_key() { tr '[:upper:]' '[:lower:]' <<< "$1" | tr -s '[:space:]' ' ' | cut -d' ' -f1-8 | sed 's/ *$//'; }
# _third <finding> — the fingerprint's third argument for this namespace.
_third() {
  case "$NS" in
    plan_review) jq -r '.step // "plan"' <<< "$1" ;;
    step_review) jq -r '.step // "step"' <<< "$1" ;;
    epic_review) echo epic ;;
    do_review)   echo do ;;
  esac
}

project_id="$(basename "$ROOT")"

# _adjudicate_role <role> — every finding of one reviewer's answer is accepted
# with its fingerprint or rejected with a reason.
_adjudicate_role() {
  local role="$1" answer f id reason first step key fp match
  local -A seen=()
  answer="${DIR}/reviewer-${role}.json"
  [[ -r "$answer" ]] || _fail "cannot read ${answer}"
  while IFS= read -r f; do
    jq -c --arg r "$role" '{role: $r, id}' <<< "$f" >> "${WORK}/originated.jsonl"
    id="$(jq -r '.id' <<< "$f")"
    reason="$(jq -r --slurpfile s "$AID_PR_SCHEMA" "$(aid_plan_review_proof_jq) proof_error // \"\"" <<< "$f")" \
      || _fail "cannot read a finding of ${answer}"
    [[ -n "$reason" ]] || reason="$(_command_ok "$(jq -r '.command' <<< "$f")" || true)"
    first=""
    if [[ -z "$reason" ]] && ! first="$(_evidence_first_ok "$(jq -r '.evidence' <<< "$f")")"; then
      reason=evidence_not_found
    fi
    if [[ -z "$reason" && "$HANDLERS" -gt 0 && "$role" == *_generalist ]] \
       && jq -e '(.severity == "blocker" or .severity == "major") and ((.behaviour_trace // []) | length == 0)' <<< "$f" >/dev/null; then
      reason=trace_missing
    fi
    if [[ -z "$reason" ]]; then
      step="$(_third "$f")"
      # the fingerprint anchors on the first citation that RESOLVES, not the first written
      key="$(_claim_key "$(jq -r '.claim' <<< "$f")")"
      fp="$(fingerprint "$project_id" "$NS" "$step" "$first" "$key")"
      # The next round is matched without the line: a fix that shifts lines must
      # not turn an unresolved finding into a new one.
      match="$(fingerprint "$project_id" "$NS" "$step" "${first%:*}" "$key")"
      if [[ -n "${seen[$fp]:-}" ]]; then
        reason=duplicate
      else
        seen[$fp]=1
        jq -c --arg r "$role" --arg fp "$fp" --arg m "$match" '. + {role: $r, fingerprint: $fp, match: $m}' <<< "$f" >> "${WORK}/accepted.jsonl"
      fi
    fi
    [[ -n "$reason" ]] && jq -nc --arg r "$role" --arg id "$id" --arg why "$reason" \
      '{role: $r, id: $id, reason: $why}' >> "${WORK}/rejected.jsonl"
  done < <(jq -c '.findings[]' "$answer")
}

mapfile -t VALID < <(jq -r '.valid[]' "${DIR}/collect.json")
for role in "${VALID[@]}"; do
  _adjudicate_role "$role"
done

# The step check's own findings: the script is the command.
if [[ -n "$STEP_CHECK" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    step="$(_third "$f")"
    first="$(jq -r '.evidence' <<< "$f")"
    key="$(_claim_key "$(jq -r '.claim' <<< "$f")")"
    fp="$(fingerprint "$project_id" "$NS" "$step" "$first" "$key")"
    match="$(fingerprint "$project_id" "$NS" "$step" "${first%:*}" "$key")"
    jq -c --arg fp "$fp" --arg m "$match" '. + {role: "step_check", fingerprint: $fp, match: $m}' <<< "$f" >> "${WORK}/accepted.jsonl"
  done < <(jq -c '.script_findings[]?' "$STEP_CHECK")
fi

# Statuses a finding already carries (disputed, a PM answer) survive a rerun.
prior='{"findings":[]}'; [[ -r "${DIR}/merged.json" ]] && prior="$(cat "${DIR}/merged.json")"

jq -s --argjson round "$(jq '.round' "${DIR}/round.json")" --arg ns "$NS" \
      --argjson sha "$(jq '.plan_sha256 // null' "${DIR}/round.json")" \
      --argjson head "$(jq '.head_sha // null' "${DIR}/round.json")" --argjson prior "$prior" '
  def rank: {"blocker": 3, "major": 2, "minor": 1}[.];
  ($prior.findings | map({(.fingerprint): .}) | add // {}) as $old
  | group_by(.fingerprint)
  | map(sort_by(-(.severity | rank)) as $g
        | $g[0] as $top
        | ($old[$top.fingerprint] // {}) as $was
        | {fingerprint: $top.fingerprint, match: $top.match, step: $top.step, severity: $top.severity,
           severity_reported: (map({(.role): .severity}) | add),
           claim: $top.claim, command: $top.command, evidence: $top.evidence, fix: $top.fix,
           reported_by: (map(.role) | unique), also_reported_by: (map(.role) | unique | length),
           status: ($was.status // "open")}
        + (if $top.behaviour_trace then {behaviour_trace: $top.behaviour_trace} else {} end)
        + (if $was.dispute then {dispute: $was.dispute} else {} end))
  | {namespace: $ns, plan_sha256: $sha, head_sha: $head, round: $round, findings: .,
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
    ($now[0].findings | map(.match)) as $still
    | .findings |= map(
        if (.status | IN("open", "disputed", "routed", "carried")) and (.severity == "blocker" or .severity == "major")
           and ((.match // .fingerprint) | IN($still[]) | not)
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
