#!/usr/bin/env bash
# =============================================================================
# aid-plan-review-round.sh — plan review (CP1), one round at a time.
#
# The controller runs these subcommands in the order commands/aid-plan.md
# "Plan review (CP1)" lists; every one of them loads and validates
# review_checkpoints.plan_review first. Evidence lives under
# .aid-o/work/evidence/<plan_id>/cp1/ (rounds.json, round-N/, override.json).
#
#   prepare <plan> --round N [--only <role>] [--manual]
#       build the packet and one prompt per expected reviewer
#   dispatch <plan> --round N --provider codex --role <r>
#       run one codex reviewer (claude reviewers are dispatched by the controller)
#   collect <plan> --round N
#       validate the answers, decide whether the round is valid, adjudicate
#   close <plan> --round N --tokens <role>=<n|unknown> ...
#       write measurement.json; a round counts only once it is closed
#   retry <plan> --round N --role <r>
#       clear one invalid or missing reviewer so it can answer again
#   fix-check <plan> --round N
#       check the author's fix against the round's packet and fix list
#   dispute <plan> --round N --fingerprint <f> --reason "<text>"
#       mark a finding disputed; it stays open until the PM answers
#   finalize <plan>
#       the one edit after the last round: its fixes plus acceptance criteria
#   override <plan> --rounds 1|3 --reason "<the PM's words>"
#       record the PM's instruction to run one round, or a third
#
# Common options: --project-root <dir> (default: the plan's own workspace).
# Exit: 0 done, 1 refused (reason on stderr), 2 usage or missing tool.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AID_PLUGIN_PATH="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-plan-review-config.sh
source "${SCRIPT_DIR}/lib/aid-plan-review-config.sh"
# shellcheck source=lib/aid-plan-review-packet.sh
source "${SCRIPT_DIR}/lib/aid-plan-review-packet.sh"

usage() { sed -n '4,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }

CMD="${1:-}"; [[ -n "$CMD" && "$CMD" != -h && "$CMD" != --help ]] || usage
shift
PLAN="" ROUND="" ROOT="" ONLY="" MANUAL=0 ROLE="" PROVIDER="" FINGERPRINT="" REASON="" ROUNDS=""
TOKENS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --round)        ROUND="${2:-}"; shift 2 ;;
    --project-root) ROOT="${2:-}"; shift 2 ;;
    --only)         ONLY="${2:-}"; shift 2 ;;
    --manual)       MANUAL=1; shift ;;
    --role)         ROLE="${2:-}"; shift 2 ;;
    --provider)     PROVIDER="${2:-}"; shift 2 ;;
    --fingerprint)  FINGERPRINT="${2:-}"; shift 2 ;;
    --reason)       REASON="${2:-}"; shift 2 ;;
    --rounds)       ROUNDS="${2:-}"; shift 2 ;;
    --tokens)       shift; while [[ $# -gt 0 && "$1" != --* ]]; do TOKENS+=("$1"); shift; done ;;
    -*) echo "${CMD}: unknown option $1" >&2; exit 2 ;;
    *)  PLAN="$1"; shift ;;
  esac
done

_die() { echo "${CMD}: $1" >&2; exit "${2:-1}"; }

for tool in jq yq sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || _die "${tool} not installed" 2
done
[[ -n "$PLAN" && -f "$PLAN" ]] || _die "plan file required (got '${PLAN}')" 2
PLAN="$(realpath "$PLAN")"
[[ -n "$ROOT" ]] || ROOT="$(_aid_plan_project_root "$PLAN")" || _die "the plan is not inside an AID workspace; pass --project-root" 2
PLAN_ID="$(_aid_plan_id_of "$PLAN")" || _die "the plan has no valid frontmatter id" 2
CP1="${ROOT}/.aid-o/work/evidence/${PLAN_ID}/cp1"

aid_plan_review_config_load "$ROOT" || exit 2
aid_plan_review_config_validate || exit 1

_need_round() { [[ "$ROUND" =~ ^[1-9][0-9]*$ ]] || _die "--round N required" 2; }
_round_dir() { printf '%s/round-%s' "$CP1" "$1"; }
_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# _override_rounds — the PM's recorded round count, or nothing.
_override_rounds() { [[ -f "${CP1}/override.json" ]] && jq -r '.rounds // empty' "${CP1}/override.json" 2>/dev/null; }

# _expected_roles <round> — the reviewers a round asks, one per line.
_expected_roles() {
  local n="$1" roles prev fix type
  type="$(_aid_fm_get "$PLAN" type)"
  if [[ "$type" == docs ]]; then roles="$PR_DOCS_REVIEWERS"; else roles="${PR_ROLE[*]}"; fi
  if (( n >= 2 )); then
    # The confirmation round asks only reviewers whose findings touch a changed
    # step, plus every reviewer that reported a blocker.
    prev="$(_round_dir $((n - 1)))/merged.json"; fix="$(_round_dir $((n - 1)))/fix-diff.json"
    local narrow
    narrow="$(jq -r --slurpfile fd "$fix" '
      ($fd[0].steps_changed // []) as $changed
      | [.findings[] | select(.step != null and (.step | IN($changed[]))
                              or (.severity == "blocker" and .status != "fixed"))
         | .reported_by[]] | unique | .[]' "$prev")"
    roles="$(for r in $roles; do grep -qxF "$r" <<<"$narrow" && echo "$r"; done)"
  fi
  if [[ -n "$ONLY" ]]; then
    [[ " ${roles//$'\n'/ } " == *" ${ONLY} "* ]] || _die "role ${ONLY} is not expected in this round"
    roles="$ONLY"
  fi
  printf '%s\n' $roles
}

cmd_prepare() {
  _need_round
  local dir index check
  check="${ROOT}/.aid-o/work/evidence/${PLAN_ID}/plan-check.json"
  [[ -f "$check" ]] || _die "no plan-check.json for ${PLAN_ID}; run aid-plan-check.sh ${PLAN} --json ${check}"

  if (( MANUAL )); then
    dir="${CP1}/manual/$(date -u +%Y%m%dT%H%M%SZ)"
  else
    dir="$(_round_dir "$ROUND")"
    [[ -d "${dir}/packet" ]] && _die "round ${ROUND} already prepared; a retry goes through 'retry', a fresh round through the next number"
    if (( ROUND > PR_ROUNDS_DEFAULT )); then
      local allowed; allowed="$(_override_rounds)"
      [[ -n "$allowed" && "$allowed" -ge "$ROUND" ]] \
        || _die "round ${ROUND} exceeds rounds_default ${PR_ROUNDS_DEFAULT}; it needs the PM's override.json (aid-plan-review-round.sh override)"
    fi
    if (( ROUND >= 2 )); then
      local prev; prev="$(_round_dir $((ROUND - 1)))"
      [[ -f "${prev}/fix-diff.json" ]] || _die "round $((ROUND - 1)) has no fix-diff.json; run fix-check first"
      [[ "$(jq -r '.pass' "${prev}/fix-diff.json")" == true ]] \
        || _die "the fix of round $((ROUND - 1)) did not pass fix-check: $(jq -c '.added_outside_fixes' "${prev}/fix-diff.json")"
      [[ "$(jq '[.findings[] | select(.status != "fixed" and (.severity == "blocker" or .severity == "major"))] | length' "${prev}/merged.json")" -gt 0 ]] \
        || _die "nothing to confirm: round $((ROUND - 1)) left no open blocker or major finding"
    fi
  fi

  mkdir -p "$dir" || _die "cannot create ${dir}"
  aid_plan_review_packet_build "$PLAN" "$ROOT" "$check" "$dir" || { rm -rf "${dir}/packet"; exit 1; }

  local roles=() role
  mapfile -t roles < <(_expected_roles "$ROUND" | grep -v '^$')
  local min=$(( PR_MIN_ANSWERS < ${#roles[@]} ? PR_MIN_ANSWERS : ${#roles[@]} ))
  jq -n --argjson round "$ROUND" --arg sha "$(jq -r .plan_sha256 "${dir}/packet/manifest.json")" \
    --argjson min "$min" --arg at "$(_now)" --argjson degraded "$([[ "$PR_DEGRADED" == 1 ]] && echo true || echo false)" \
    --arg narrow "$( (( ROUND >= 2 )) && echo "round-$((ROUND - 1))/fix-diff.json")" \
    '{round: $round, plan_sha256: $sha, reviewers_expected: $ARGS.positional,
      min_answers_effective: $min, degraded: $degraded, started_at: $at,
      narrow_from: (if $narrow == "" then null else $narrow end)}' \
    --args "${roles[@]}" > "${dir}/round.json"

  for role in "${roles[@]}"; do
    aid_plan_review_prompt_render "$role" "$ROUND" "$dir" || exit 1
  done

  if (( ! MANUAL )); then
    index="${CP1}/rounds.json"
    [[ -f "$index" ]] || echo '[]' > "$index"
    jq --argjson r "$ROUND" --arg sha "$(jq -r .plan_sha256 "${dir}/round.json")" --arg at "$(_now)" \
      '. + [{round: $r, plan_sha256: $sha, prepared_at: $at}]' "$index" > "${index}.tmp" && mv "${index}.tmp" "$index"
    aid_plan_log "$PLAN" plan_review_round_start round="$ROUND" reviewers="${#roles[@]}"
  fi
  echo "prepared round ${ROUND}: ${#roles[@]} reviewers → ${dir}"
  for role in "${roles[@]}"; do echo "  ${dir}/prompt-${role}.md"; done
}

case "$CMD" in
  prepare) cmd_prepare ;;
  *) echo "unknown subcommand: ${CMD}" >&2; usage ;;
esac
