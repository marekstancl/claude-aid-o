#!/usr/bin/env bash
# =============================================================================
# aid-plan-parallel-check.sh — do the steps a plan says can run TOGETHER stay
# out of each other's files? (P085 Step 7)
#
# `Parallel Group` has existed in the EPIC table since P039 and the generator
# writes it into plan.json (aid-epic-to-json.sh) — but nothing ever produced a
# value and nothing ever checked one. This is the producer's other half: the
# plan declares a wave per step, and this program proves the declaration is
# safe by the only mechanical measure there is — two steps in one wave must not
# name the same file.
#
# It lives beside aid-generation-readiness.sh rather than inside the plan lint,
# because disjointness is a property of the step GRAPH, and that is what the
# readiness check already builds and grades (dependencies, cycles).
#
# Two severities, the same two-stage model the Files grammar has: ADVISORY while
# a plan is being written (--advisory), BLOCKING before generation (default).
#
# With max_parallel: 1 nothing actually runs concurrently today. That does not
# make this decoration: it is the evidence of safety for the moment the brake
# comes off, and evidence gathered after the fact is evidence nobody trusts.
#
# Usage: aid-plan-parallel-check.sh <plan.md> [--advisory] [--quiet]
# Exit:  0 = no blocking finding   1 = collision(s)   2 = usage/IO
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"
# shellcheck source=lib/aid-plan-band.sh
source "${SCRIPT_DIR}/lib/aid-plan-band.sh"

PLAN=""; ADVISORY=0; QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --advisory) ADVISORY=1; shift ;;
    --quiet)    QUIET=1; shift ;;
    -*) echo "aid-plan-parallel-check: unknown option: $1" >&2; exit 2 ;;
    *)  PLAN="$1"; shift ;;
  esac
done
[[ -n "$PLAN" ]] || { echo "Usage: aid-plan-parallel-check.sh <plan.md> [--advisory] [--quiet]" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "aid-plan-parallel-check: file not found: $PLAN" >&2; exit 2; }

# THE group vocabulary: a wave name, or the standalone marker. `---` is the same
# "nothing here" marker the dependency grammar already uses, so a plan has one
# spelling for it, not two.
_AID_PARALLEL_STANDALONE='---'
_AID_PARALLEL_GROUP_RE='^[A-Za-z0-9_-]+$'

band="$(aid_plan_band_name "$PLAN")"
findings=0
notes=0

# _report <severity> <message> — one emitter, so the advisory/blocking split
# cannot be half-implemented per finding.
_report() {
  case "$1" in
    finding) findings=$((findings+1)); [[ "$QUIET" -eq 0 ]] && echo "${PLAN}: ${2}" >&2 ;;
    note)    notes=$((notes+1));       [[ "$QUIET" -eq 0 ]] && echo "${PLAN}: [NOTE] ${2}" >&2 ;;
  esac
  return 0
}

# Bullets once; steps once. Same readers the plan lint uses, so a step this
# program sees is a step that program saw.
_lns=(); _txts=()
while IFS=$'\t' read -r _ln _bullet; do
  [[ -z "${_bullet:-}" ]] && continue
  _lns+=("$_ln"); _txts+=("$_bullet")
done < <(_aid_extract_files_bullets_numbered < "$PLAN")

step_names=(); step_groups=(); step_paths=()
while IFS=$'\t' read -r s e head; do
  [[ -n "${s:-}" ]] || continue
  group="$(_aid_plan_step_field "$PLAN" "$s" "$e" "Parallel group")" || group=""
  # The value may carry an explanation after the name; only the first word is
  # the group, the same way `Depends on:` grades the references and ignores the
  # annotation.
  group="${group%%[[:space:]]*}"
  if [[ -z "$group" ]]; then
    if [[ "$band" == "light" ]]; then
      # The safe default: a step nobody placed runs alone.
      group="$_AID_PARALLEL_STANDALONE"
    else
      _report finding "${head}: no **Parallel group:** field. A ${band}-band plan declares concurrency deliberately — write a wave name, or \`${_AID_PARALLEL_STANDALONE}\` for a step that runs alone."
      group="$_AID_PARALLEL_STANDALONE"
    fi
  elif [[ "$group" != "$_AID_PARALLEL_STANDALONE" && ! "$group" =~ $_AID_PARALLEL_GROUP_RE ]]; then
    _report finding "${head}: '**Parallel group:** ${group}' is not a group name — expected a single word ([A-Za-z0-9_-]) or \`${_AID_PARALLEL_STANDALONE}\`."
    group="$_AID_PARALLEL_STANDALONE"
  fi
  # This step's declared paths, joined into one space-separated field.
  paths=""
  for i in "${!_lns[@]}"; do
    (( _lns[i] >= s && _lns[i] <= e )) || continue
    body="$(_aid_files_bullet_body "${_txts[$i]}")" || continue
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      paths="${paths:+$paths }${p}"
    done < <(_aid_split_path_entry "$body" 2>/dev/null || true)
  done
  step_names+=("$head"); step_groups+=("$group"); step_paths+=("$paths")
done < <(_aid_plan_step_bounds "$PLAN")

[[ "${#step_names[@]}" -gt 0 ]] || _report note "no \`### Step\` sections found — nothing to check."

# Every pair inside a group. O(n²) over steps, which is a plan-sized number.
for i in "${!step_names[@]}"; do
  g="${step_groups[$i]}"
  [[ "$g" == "$_AID_PARALLEL_STANDALONE" ]] && continue
  for (( j=i+1; j<${#step_names[@]}; j++ )); do
    [[ "${step_groups[$j]}" == "$g" ]] || continue
    shared=""
    for p in ${step_paths[$i]}; do
      [[ " ${step_paths[$j]} " == *" $p "* ]] && shared="${shared:+$shared, }${p}"
    done
    [[ -n "$shared" ]] && _report finding "group '${g}' is not disjoint: '${step_names[$i]}' and '${step_names[$j]}' both declare ${shared}. Steps in one wave run at the same time; move one to another wave."
  done
done

# A group of one is valid and does nothing. Worth saying, never worth failing:
# it is usually the residue of moving a step out, not a mistake in itself.
for g in $(printf '%s\n' "${step_groups[@]+"${step_groups[@]}"}" | grep -v -x -F -- "$_AID_PARALLEL_STANDALONE" | sort -u); do
  n=0
  for i in "${!step_groups[@]}"; do [[ "${step_groups[$i]}" == "$g" ]] && n=$((n+1)); done
  [[ "$n" -eq 1 ]] && _report note "group '${g}' has one step — valid, but it is the same as \`${_AID_PARALLEL_STANDALONE}\`."
done

if [[ "$QUIET" -eq 0 ]]; then
  if [[ "$findings" -gt 0 && "$ADVISORY" -eq 1 ]]; then
    echo "aid-plan-parallel-check: ${findings} finding(s) — advisory while writing; the same findings BLOCK before EPIC generation." >&2
  elif [[ "$findings" -gt 0 ]]; then
    echo "aid-plan-parallel-check: FAIL (${findings} finding(s)) — a wave whose steps share a file is not a wave." >&2
  else
    echo "aid-plan-parallel-check: PASS — every declared wave is disjoint." >&2
  fi
fi

[[ "$findings" -gt 0 && "$ADVISORY" -eq 0 ]] && exit 1
exit 0
