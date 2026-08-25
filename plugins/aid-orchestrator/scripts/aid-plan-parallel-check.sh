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
# a plan is being written (--advisory, how aid-plan-lint.sh calls it), BLOCKING
# before generation (default, how aid-generation-readiness.sh calls it).
#
# THE SECOND DIMENSION (P087 Step 3): two steps can have disjoint files and
# still change the SAME INTERFACE — an endpoint, a schema, a config key, a
# registered name. Git raises no conflict and the result does not work. A step
# may therefore declare `**Shared interfaces:** a, b` and two steps of one wave
# naming the same interface (after normalisation: case, surrounding slashes,
# whitespace) are a collision exactly like a shared path. An absent field means
# "none", which is the honest answer for most steps.
#
# The field's grammar, the wave-planning rules and why this is worth checking
# are stated for the plan author in skills/plan-writing.md §"Declaring what can
# run at the same time" — one copy, on the surface the author actually reads.
#
# Usage: aid-plan-parallel-check.sh <plan.md> [--advisory] [--quiet] [--group <wave>]
#   --group  judge ONE wave only — how the dispatch decision asks, so a
#            collision elsewhere in the plan cannot serialise a safe wave
#
# **Last Updated:** 2026-08-25
#
# Exit:  0 = no blocking finding   1 = collision(s)   2 = usage/IO
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"
# shellcheck source=lib/aid-plan-band.sh
source "${SCRIPT_DIR}/lib/aid-plan-band.sh"

PLAN=""; ADVISORY=0; QUIET=0; ONLY_GROUP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --advisory) ADVISORY=1; shift ;;
    --quiet)    QUIET=1; shift ;;
    --group)    ONLY_GROUP="${2:-}"; [[ -n "$ONLY_GROUP" ]] || { echo "aid-plan-parallel-check: --group needs a wave name" >&2; exit 2; }; shift 2 ;;
    -*) echo "aid-plan-parallel-check: unknown option: $1" >&2; exit 2 ;;
    *)  PLAN="$1"; shift ;;
  esac
done
[[ -n "$PLAN" ]] || { echo "Usage: aid-plan-parallel-check.sh <plan.md> [--advisory] [--quiet]" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "aid-plan-parallel-check: file not found: $PLAN" >&2; exit 2; }

# THE group vocabulary: a wave name, or the standalone marker (`---`, the same
# marker the dependency grammar uses — see the skill for why).
_AID_PARALLEL_STANDALONE='---'
_AID_PARALLEL_GROUP_RE='^[A-Za-z0-9_-]+$'

band="$(aid_plan_band_name "$PLAN")"
findings=0

# _report <severity> <message> — one emitter, so the advisory/blocking split
# cannot be half-implemented per finding. Notes are emitted, never counted:
# nothing decides anything from how many there were.
_report() {
  case "$1" in
    finding) findings=$((findings+1)); [[ "$QUIET" -eq 0 ]] && echo "${PLAN}: ${2}" >&2 ;;
    note)    [[ "$QUIET" -eq 0 ]] && echo "${PLAN}: [NOTE] ${2}" >&2 ;;
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

# _aid_parallel_norm_iface <text> — one interface name, normalised so that
# `/api/x`, `api/x/` and `API/X` are the same declaration.
_aid_parallel_norm_iface() {
  local v="$1"
  v="${v,,}"; v="${v//\`/}"
  v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
  v="${v#/}"; v="${v%/}"
  printf '%s' "$v"
}

step_names=(); step_groups=(); step_paths=(); step_ifaces=()
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
  # The step's declared interfaces, normalised, space-separated. Commas split
  # them; an interface name with a space in it is not one name.
  ifaces=""
  if raw="$(_aid_plan_step_field "$PLAN" "$s" "$e" "Shared interfaces")"; then
    while IFS= read -r one; do
      one="$(_aid_parallel_norm_iface "$one")"
      [[ -n "$one" ]] || continue
      ifaces="${ifaces:+$ifaces }${one// /_}"
    done < <(printf '%s\n' "${raw//,/$'\n'}")
  fi
  step_names+=("$head"); step_groups+=("$group"); step_paths+=("$paths"); step_ifaces+=("$ifaces")
done < <(_aid_plan_step_bounds "$PLAN")

[[ "${#step_names[@]}" -gt 0 ]] || _report note "no \`### Step\` sections found — nothing to check."
if [[ -n "$ONLY_GROUP" ]]; then
  _seen=0
  for g in "${step_groups[@]}"; do [[ "$g" == "$ONLY_GROUP" ]] && _seen=1; done
  if (( ! _seen )); then
    echo "aid-plan-parallel-check: no step declares **Parallel group:** ${ONLY_GROUP} — a wave that is not in the plan cannot be judged" >&2
    exit 2
  fi
fi

# Every pair inside a group. O(n²) over steps, which is a plan-sized number.
for i in "${!step_names[@]}"; do
  g="${step_groups[$i]}"
  [[ "$g" == "$_AID_PARALLEL_STANDALONE" ]] && continue
  [[ -n "$ONLY_GROUP" && "$g" != "$ONLY_GROUP" ]] && continue
  for (( j=i+1; j<${#step_names[@]}; j++ )); do
    [[ "${step_groups[$j]}" == "$g" ]] || continue
    shared=""
    for p in ${step_paths[$i]}; do
      [[ " ${step_paths[$j]} " == *" $p "* ]] && shared="${shared:+$shared, }${p}"
    done
    [[ -n "$shared" ]] && _report finding "group '${g}' is not disjoint: '${step_names[$i]}' and '${step_names[$j]}' both declare ${shared}. Steps in one wave run at the same time; move one to another wave."
    shared=""
    for p in ${step_ifaces[$i]}; do
      [[ " ${step_ifaces[$j]} " == *" $p "* ]] && shared="${shared:+$shared, }${p}"
    done
    [[ -n "$shared" ]] && _report finding "group '${g}' shares an interface: '${step_names[$i]}' and '${step_names[$j]}' both name ${shared} under **Shared interfaces:**. Disjoint files do not make disjoint work — run them in sequence."
  done
done

# A group of one is valid and does nothing. Worth saying, never worth failing:
# it is usually the residue of moving a step out, not a mistake in itself.
# Counted in ONE pass with an associative array — the earlier shape forked
# grep+sort and then re-walked every step per group, and re-stated the "skip
# `---`" rule a second way while doing it.
declare -A _group_size=()
for i in "${!step_groups[@]}"; do
  g="${step_groups[$i]}"
  [[ "$g" == "$_AID_PARALLEL_STANDALONE" ]] && continue
  _group_size["$g"]=$(( ${_group_size["$g"]:-0} + 1 ))
done
for g in "${!_group_size[@]}"; do
  [[ "${_group_size[$g]}" -eq 1 ]] && _report note "group '${g}' has one step — valid, but it is the same as \`${_AID_PARALLEL_STANDALONE}\`."
done

if [[ "$QUIET" -eq 0 ]]; then
  if [[ "$findings" -gt 0 && "$ADVISORY" -eq 1 ]]; then
    echo "aid-plan-parallel-check: ${findings} finding(s) — advisory while writing; the same findings BLOCK before EPIC generation." >&2
  elif [[ "$findings" -gt 0 ]]; then
    echo "aid-plan-parallel-check: FAIL (${findings} finding(s)) — a wave whose steps share a file or an interface is not a wave." >&2
  else
    echo "aid-plan-parallel-check: PASS — every declared wave is disjoint in files and interfaces." >&2
  fi
fi

[[ "$findings" -gt 0 && "$ADVISORY" -eq 0 ]] && exit 1
exit 0
