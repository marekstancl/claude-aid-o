#!/usr/bin/env bash
# =============================================================================
# aid-cp1-gate.sh — the plan review (CP1) gate before EPIC generation
#
# Usage:
#   aid-cp1-gate.sh --plan <path> [--project-root <path>] [--json <out>]
#
# Reads only the round evidence aid-review-round.sh --plan writes under
# .aid-o/work/evidence/<plan_id>/cp1/ (cp1/manual/ is never read) and passes
# when all of these hold:
#   - review_checkpoints.plan_review is valid (lib/aid-review-config.sh);
#   - every round cp1/rounds.json lists has its directory;
#   - round 1 exists, is closed (measurement.json) and was valid (collect.json);
#   - every round that exists is closed and valid;
#   - the plan is byte-identical to what the last round reviewed, or to the
#     round's plan-final.md written by `finalize`;
#   - round 1 left no open blocker, or round 2 ran, or the PM's
#     cp1/override.json says one round;
#   - a round beyond rounds_default exists only with override.json allowing it;
#   - every blocker still open or disputed in any round is quoted (its first
#     eight words) in an acceptance criterion of its step, or under
#     "## Success Criteria" for a plan-level finding.
# review_checkpoints.enabled or cp1_plan_review set to false passes with a
# notice; a plan outside any .aid-o/ workspace is not gated.
#
# Exit: 0 pass
#       1 a review condition fails (forceable by the PM through
#         aid-auto-pipeline.sh --force; every failure is named)
#       2 usage error
#       3 a hard condition --force must not cover: jq or yq missing, the plan file or its id,
#         an invalid plan_review config, unreadable round evidence, a round the
#         index lists but that is gone, a malformed override.json
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AID_PLUGIN_PATH="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-review-config.sh
source "${SCRIPT_DIR}/lib/aid-review-config.sh"
_roles_skill="${SCRIPT_DIR}/../skills/plan-review-roles.md"
# shellcheck source=lib/aid-ac-extract.sh
source "${SCRIPT_DIR}/lib/aid-ac-extract.sh"

plan="" project_root="" json_out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)          plan="${2:-}";         shift 2 ;;
    --project-root)  project_root="${2:-}"; shift 2 ;;
    --json)          json_out="${2:-}";     shift 2 ;;
    --help|-h) sed -n '4,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) error_exit "Unknown argument: $1" 2 ;;
  esac
done

[[ -z "$plan" ]] && error_exit "Missing required argument: --plan" 2
[[ ! -f "$plan" ]] && error_exit "Plan file not found: $plan" 3
if [[ -z "$project_root" ]]; then
  project_root="$(_aid_plan_project_root "$plan")" || project_root="$(pwd)"
fi
# The id becomes a directory name below; a plan without a usable one is a hard
# condition, never a review verdict.
plan_id="$(_aid_plan_id_of "$plan")" \
  || error_exit "Plan file missing a usable 'id' in its frontmatter (expected: id: P{NNN}, letters/digits/-/_ only)." 3

_cp1_log() { aid_plan_log "$plan" "$@"; }

if [[ ! -d "${project_root}/.aid-o" ]]; then
  echo "CP1-gate: no .aid-o/ workspace at ${project_root} — not an AID project, not gated." >&2
  exit 0
fi

# The outcome is logged once, from the exit trap, whichever way the gate leaves.
_cp1_result="fail"
trap '_cp1_log cp1_gate_result result="$_cp1_result" exit_code="$?"' EXIT

CP1="${project_root}/.aid-o/work/evidence/${plan_id}/cp1"
FAILS=() HARD=()
_fail() { FAILS+=("$1"); }
_hard() { HARD+=("$1"); }

# _finish — print the verdict, write --json, exit with the contract's code.
_finish() {
  local verdict=pass rc=0 line
  if (( ${#HARD[@]} )); then verdict=hard; rc=3
  elif (( ${#FAILS[@]} )); then verdict=fail; rc=1; fi
  for line in "${HARD[@]}";  do echo "CP1-gate HARD: ${line}" >&2; done
  for line in "${FAILS[@]}"; do echo "CP1-gate FAIL: ${line}" >&2; done
  (( rc == 0 )) && echo "CP1-gate: plan ${plan_id} PASS${1:+ — $1}" >&2
  if [[ -n "$json_out" ]]; then
    jq -n --arg v "$verdict" --arg id "$plan_id" --arg note "${1:-}" \
      --argjson fails "$(jq -nc '$ARGS.positional' --args "${FAILS[@]}")" \
      --argjson hard "$(jq -nc '$ARGS.positional' --args "${HARD[@]}")" \
      '{verdict: $v, plan_id: $id, failures: $fails, hard: $hard} + (if $note == "" then {} else {note: $note} end)' > "$json_out"
  fi
  [[ "$verdict" == pass ]] && _cp1_result=pass
  exit "$rc"
}

for tool in jq yq; do
  command -v "$tool" >/dev/null 2>&1 || { _hard "${tool} not installed"; _finish; }
done
_cfg_err="$(aid_review_config_load "$project_root" plan_review "$_roles_skill" 2>&1 && aid_review_config_validate 2>&1)" \
  || { _hard "$(grep 'plan_review config:' <<< "$_cfg_err" | tail -1)"; _finish; }
aid_review_config_load "$project_root" plan_review "$_roles_skill" 2>/dev/null
if [[ "$RC_ENABLED" != 1 ]]; then
  _finish "plan review is switched off (review_checkpoints.enabled or cp1_plan_review is false)"
fi

_round_dir() { printf '%s/round-%s' "$CP1" "$1"; }
_prepare_hint="run: aid-review-round.sh prepare --plan ${plan} --round 1 (commands/aid-plan.md, Plan review (CP1))"

# --- the round index and the round directories -----------------------------
if [[ -f "${CP1}/rounds.json" ]]; then
  jq -e 'type == "array"' "${CP1}/rounds.json" >/dev/null 2>&1 \
    || { _hard "round evidence unreadable: ${CP1}/rounds.json"; _finish; }
  for n in $(jq -r '.[].round' "${CP1}/rounds.json" | sort -un); do
    [[ -d "$(_round_dir "$n")" ]] || _hard "rounds.json lists a round that is missing: round-${n}"
  done
fi
override_rounds=""
if [[ -f "${CP1}/override.json" ]]; then
  override_rounds="$(jq -r 'if (.rounds | type) == "number" and .rounds >= 1 and .rounds <= 3
                             and ((.reason // "") | length) >= 20 then .rounds else "" end' "${CP1}/override.json" 2>/dev/null)"
  [[ -n "$override_rounds" ]] || _hard "override.json is malformed: ${CP1}/override.json"
fi
(( ${#HARD[@]} )) && _finish

rounds=()
for d in "${CP1}"/round-*/; do
  [[ -d "$d" ]] || continue
  n="${d%/}"; n="${n##*-}"; [[ "$n" =~ ^[0-9]+$ ]] && rounds+=("$n")
done
mapfile -t rounds < <(printf '%s\n' "${rounds[@]}" | grep -v '^$' | sort -n)
if [[ ! -d "$(_round_dir 1)" ]]; then
  _fail "no plan review round-1 for ${plan_id}; ${_prepare_hint}"
  _finish
fi

last=""
allowed="${override_rounds:-$RC_ROUNDS_DEFAULT}"
for n in "${rounds[@]}"; do
  d="$(_round_dir "$n")"
  (( n > RC_ROUNDS_DEFAULT && n > allowed )) \
    && _fail "round-${n} exists without the PM's override.json allowing ${n} rounds"
  if [[ ! -f "${d}/measurement.json" ]]; then
    _fail "round-${n} is not closed (measurement.json missing): run collect and close for round ${n}"
    continue
  fi
  for f in collect.json round.json; do
    jq -e . "${d}/${f}" >/dev/null 2>&1 || _hard "round ${n} evidence unreadable: ${d}/${f}"
  done
  if [[ "$(jq -r .status "${d}/collect.json" 2>/dev/null)" == valid ]]; then
    jq -e . "${d}/merged.json" >/dev/null 2>&1 || _hard "round ${n} evidence unreadable: ${d}/merged.json"
  else
    _fail "round-${n} invalid: $(jq -r '.reason // "too few answers"' "${d}/collect.json" 2>/dev/null); retry the missing roles with aid-review-round.sh retry --plan <plan>, then collect and close"
  fi
  last="$n"
done
(( ${#HARD[@]} )) && _finish
[[ -n "$last" ]] || _finish

# --- the plan is what the last round reviewed, or its finalized snapshot -----
last_dir="$(_round_dir "$last")"
plan_sha="$(sha256sum "$plan" | cut -d' ' -f1)"
reviewed_sha="$(jq -r '.plan_sha256' "${last_dir}/round.json")"
if [[ "$plan_sha" != "$reviewed_sha" ]]; then
  if [[ -f "${last_dir}/plan-final.md" ]]; then
    cmp -s "$plan" "${last_dir}/plan-final.md" \
      || _fail "the plan changed after finalize (sha256 ${plan_sha:0:12} differs from round-${last}/plan-final.md); run finalize again"
  else
    _fail "the plan changed after round ${last} (sha256 ${plan_sha:0:12}, reviewed ${reviewed_sha:0:12}); fix what the round found and run aid-review-round.sh finalize --plan <plan>"
  fi
fi

# --- a second round when the first left blockers ------------------------------
if (( last == 1 )) && [[ "$override_rounds" != 1 && -f "$(_round_dir 1)/merged.json" ]]; then
  open1="$(jq '.blockers_open' "$(_round_dir 1)/merged.json")"
  (( open1 > 0 )) && _fail "round-1 left ${open1} blocker(s) open and there is no round-2: fix the plan, run fix-check, then prepare --round 2"
fi
[[ "$override_rounds" == 1 ]] && (( last > 1 )) \
  && echo "CP1-gate: override.json says one round, but round ${last} ran; the later round decides" >&2

# --- every blocker still open is quoted in an acceptance criterion ----------
_norm() { tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
# _criteria <step|null> — the criteria of one step, or the Success Criteria bullets.
_criteria() {
  if [[ "$1" == null ]]; then
    awk '/^## Success Criteria/{on=1; next} on && /^## /{exit} on && /^- /{sub(/^- (\[[ x]\] )?/, ""); print}' "$plan"
    return
  fi
  local s e head
  while IFS=$'\t' read -r s e head; do
    [[ "$head" =~ ^###\ Step\ ${1}[^0-9] || "$head" == "### Step ${1}" ]] || continue
    sed -n "${s},${e}p" "$plan" | aid_ac_extract_criteria
  done < <(_aid_plan_step_bounds "$plan")
}
while IFS=$'\t' read -r n step claim; do
  [[ -n "$n" ]] || continue
  claim="$(base64 -d <<< "$claim")"
  key="$(cut -d' ' -f1-8 <<< "$(_norm <<< "$claim")")"
  if ! _criteria "$step" | _norm | grep -qF -- "$key"; then
    where="Step ${step}"; [[ "$step" == null ]] && where="## Success Criteria"
    _fail "round-${n} blocker still open is not quoted in an acceptance criterion of ${where}: \"${key}\""
  fi
done < <(for n in "${rounds[@]}"; do
           [[ -f "$(_round_dir "$n")/measurement.json" && -f "$(_round_dir "$n")/merged.json" ]] || continue
           jq -r --arg n "$n" '.findings[] | select(.severity == "blocker" and (.status == "open" or .status == "disputed"))
                               | [$n, (.step | tostring), (.claim | @base64)] | @tsv' "$(_round_dir "$n")/merged.json"
         done)

_finish "round ${last} closed$([[ "$RC_DEGRADED" == 1 ]] && echo ', degraded: both generalists on one model')"
