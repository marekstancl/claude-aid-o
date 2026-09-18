#!/usr/bin/env bash
# aid-plan-review-config.sh — the one reader of review_checkpoints.plan_review.
#
# Precedence: the project's .aid-o/config/policies/review-checkpoints.yaml when
# it carries a plan_review block, otherwise the plugin default. The six role ids
# come from defaults/schemas/plan-review-finding.schema.json, so the config, the
# roles skill and the answer check cannot disagree about which roles exist.
#
# aid_plan_review_config_load <project_root>
#   Exports PR_CONFIG_FILE, PR_ROUNDS_DEFAULT, PR_MIN_ANSWERS, PR_DOCS_REVIEWERS
#   (space-separated), PR_BANNED_MODELS (space-separated), arrays PR_ROLE[],
#   PR_PROVIDER[], PR_MODEL[] (same index = same reviewer), PR_DEGRADED
#   (1 when both generalists use the same model) and PR_ENABLED (0 when the
#   project switched review_checkpoints.enabled or cp1_plan_review off).
#   Returns 2 without yq, 1 on unreadable YAML or a missing block.
# aid_plan_review_config_validate
#   Refuses a loaded config that breaks an invariant; prints
#   "plan_review config: <reason>" and returns 1.
# aid_plan_review_role_index <role> — prints the index of a role in PR_ROLE[].
#
# Enforcement: every aid-plan-review-round.sh subcommand and aid-cp1-gate.sh
# call load + validate first (registry row plan_review_config_valid).

_AID_PRC_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
_AID_PRC_KNOWN_KEYS="rounds_default min_answers docs_type_reviewers banned_models reviewers"
_AID_PRC_LEGACY_KEYS="ceremony_bands cp1_codex_review"

aid_plan_review_config_load() {
  local root="${1:?aid_plan_review_config_load: project root required}"
  command -v yq >/dev/null 2>&1 || { echo "plan_review config: yq not installed" >&2; return 2; }

  local default="${_AID_PRC_PLUGIN}/defaults/policies/review-checkpoints.yaml"
  local project="${root}/.aid-o/config/policies/review-checkpoints.yaml"
  PR_CONFIG_FILE="$default"
  if [[ -f "$project" ]]; then
    if yq -e '.review_checkpoints.plan_review' "$project" >/dev/null 2>&1; then
      PR_CONFIG_FILE="$project"
    else
      echo "plan_review config: using plugin default" >&2
    fi
  fi

  local err
  if ! err="$(yq -e '.review_checkpoints.plan_review' "$PR_CONFIG_FILE" 2>&1 >/dev/null)"; then
    printf 'plan_review config: cannot read plan_review from %s\n%s\n' "$PR_CONFIG_FILE" "$err" >&2
    return 1
  fi

  local key
  for key in $(yq -r '.review_checkpoints.plan_review | keys | .[]' "$PR_CONFIG_FILE"); do
    [[ " $_AID_PRC_KNOWN_KEYS " == *" $key "* ]] || echo "plan_review config: ignored unknown key plan_review.${key}" >&2
  done
  # Only a project file is the PM's to clean up; the plugin default is not.
  for key in $_AID_PRC_LEGACY_KEYS; do
    if [[ "$PR_CONFIG_FILE" == "$project" ]] && yq -e ".review_checkpoints.${key}" "$PR_CONFIG_FILE" >/dev/null 2>&1; then
      echo "plan_review config: ignored legacy key ${key}" >&2
    fi
  done

  PR_ROUNDS_DEFAULT="$(yq -r '.review_checkpoints.plan_review.rounds_default // ""' "$PR_CONFIG_FILE")"
  PR_MIN_ANSWERS="$(yq -r '.review_checkpoints.plan_review.min_answers // ""' "$PR_CONFIG_FILE")"
  PR_DOCS_REVIEWERS="$(yq -r '.review_checkpoints.plan_review.docs_type_reviewers // [] | .[]' "$PR_CONFIG_FILE" | tr '\n' ' ')"
  PR_BANNED_MODELS="$(yq -r '.review_checkpoints.plan_review.banned_models // [] | .[]' "$PR_CONFIG_FILE" | tr '\n' ' ')"
  PR_ROLE=(); PR_PROVIDER=(); PR_MODEL=()
  local role provider model
  while IFS=$'\t' read -r role provider model; do
    [[ -n "$role" ]] || continue
    PR_ROLE+=("$role"); PR_PROVIDER+=("$provider"); PR_MODEL+=("$model")
  done < <(yq -r '.review_checkpoints.plan_review.reviewers // [] | .[] | [.role, .provider, .model] | @tsv' "$PR_CONFIG_FILE")

  # The two switches are read where the PM sets them: the project file first,
  # whether or not it carries a plan_review block.
  PR_ENABLED=1
  local flag file value
  for flag in enabled cp1_plan_review; do
    value=""
    for file in "$project" "$default"; do
      [[ -f "$file" ]] || continue
      value="$(yq -r ".review_checkpoints.${flag}" "$file" 2>/dev/null)"
      [[ "$value" == true || "$value" == false ]] && break
    done
    [[ "$value" == false ]] && PR_ENABLED=0
  done

  PR_DEGRADED=0
  local a b
  a="$(aid_plan_review_role_index generalist_a)" && b="$(aid_plan_review_role_index generalist_b)" \
    && [[ "${PR_MODEL[$a]}" == "${PR_MODEL[$b]}" ]] && PR_DEGRADED=1
  export PR_CONFIG_FILE PR_ROUNDS_DEFAULT PR_MIN_ANSWERS PR_DOCS_REVIEWERS PR_BANNED_MODELS PR_DEGRADED PR_ENABLED
  return 0
}

aid_plan_review_role_index() {
  local i
  for i in "${!PR_ROLE[@]}"; do
    [[ "${PR_ROLE[$i]}" == "$1" ]] && { echo "$i"; return 0; }
  done
  return 1
}

_aid_prc_fail() { echo "plan_review config: $1" >&2; }

aid_plan_review_config_validate() {
  local schema="${_AID_PRC_PLUGIN}/defaults/schemas/plan-review-finding.schema.json"
  local expected role i seen=" "
  expected="$(jq -r '.properties.role.enum[]' "$schema" | sort | tr '\n' ' ')"

  for i in "${!PR_ROLE[@]}"; do
    role="${PR_ROLE[$i]}"
    [[ "$seen" == *" $role "* ]] && { _aid_prc_fail "duplicate role ${role}"; return 1; }
    seen+="${role} "
    [[ " $expected" == *" $role "* ]] || { _aid_prc_fail "unknown role ${role} (roles: ${expected% })"; return 1; }
    case "${PR_PROVIDER[$i]}" in
      claude|codex) ;;
      *) _aid_prc_fail "role ${role}: provider must be claude or codex (got '${PR_PROVIDER[$i]}')"; return 1 ;;
    esac
    [[ -n "${PR_MODEL[$i]}" ]] || { _aid_prc_fail "role ${role}: model is empty"; return 1; }
    [[ " $PR_BANNED_MODELS " == *" ${PR_MODEL[$i]} "* ]] \
      && { _aid_prc_fail "role ${role}: model ${PR_MODEL[$i]} is in banned_models"; return 1; }
  done
  for role in $expected; do
    [[ "$seen" == *" $role "* ]] || { _aid_prc_fail "missing role ${role}"; return 1; }
  done
  [[ "$PR_MIN_ANSWERS" =~ ^[1-6]$ ]] || { _aid_prc_fail "min_answers must be 1..6 (got '${PR_MIN_ANSWERS}')"; return 1; }
  [[ "$PR_ROUNDS_DEFAULT" =~ ^[1-3]$ ]] || { _aid_prc_fail "rounds_default must be 1..3 (got '${PR_ROUNDS_DEFAULT}')"; return 1; }
  for role in $PR_DOCS_REVIEWERS; do
    [[ "$seen" == *" $role "* ]] || { _aid_prc_fail "docs_type_reviewers names ${role}, which is not a reviewer"; return 1; }
  done
  return 0
}
