#!/usr/bin/env bash
# aid-review-config.sh — the one reader of a review_checkpoints.<block>
# reviewer block: plan_review (CP1), step_review (CP2, CP6), epic_review (CP3),
# final_review (CP7).
#
# Precedence: the project's .aid-o/config/policies/review-checkpoints.yaml when
# it carries the block, otherwise the plugin default. The roles a block may
# name are the `## Role:` headings of the checkpoint's roles skill, so the
# config, the skill and the answer schema cannot disagree about which roles
# exist. The skill's frontmatter carries the block's invariants as data:
#   required_roles: all|none   — `all`: every role of the skill must be listed
#                                (the plan-review rule); `none`: any subset
#   distinct_models: [a, b]    — the round is degraded when a and b share a model
#
# aid_review_config_load <project_root> <block> <roles_skill>
#   Exports RC_BLOCK, RC_CONFIG_FILE, RC_ENABLED (0 when the master switch
#   review_checkpoints.enabled OR the checkpoint's own toggle is false; both are
#   read from the project file first, then the default), RC_ROUNDS_DEFAULT,
#   RC_MIN_ANSWERS (the block's min_answers when it declares one, else the
#   number of unconditional roles), RC_BANNED_MODELS (space-separated), arrays
#   RC_ROLE[], RC_PROVIDER[], RC_MODEL[], RC_EFFORT[], RC_WHEN[] (same index =
#   same reviewer; RC_EFFORT is low|medium|high, medium when unset; RC_WHEN is ""
#   or the step-check verdict that enables the role),
#   RC_DEGRADED, RC_EXTRA_DOCS_TYPE_REVIEWERS (space-separated),
#   RC_EXTRA_SKIP_THRESHOLD_FILES, RC_EXTRA_SKIP_THRESHOLD_LINES.
#   Returns 2 without yq, 1 on unreadable YAML, a missing block or a missing
#   roles skill.
# aid_review_config_validate
#   Refuses a loaded config that breaks an invariant; prints
#   "<block> config: <reason>" and returns 1.
# aid_review_role_index <role> — prints the index of a role in RC_ROLE[].
# aid_review_config_floor <expected_count> — the round's answer floor:
#   min(RC_MIN_ANSWERS, expected_count).
#
# The toggle key of each block: plan_review → cp1_plan_review,
# step_review → cp2_step_review (cp6_fast_mode_review when RC_CHECKPOINT=cp6),
# epic_review → cp3_integration_review, final_review → cp7_plan_final_review.
#
# One reader for every checkpoint (P094 Step 4); registry row
# review_config_valid; tested by scripts/tests/bats/test-review-config.bats.

_AID_RC_PLUGIN="${AID_PLUGIN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
_AID_RC_KNOWN_KEYS="rounds_default min_answers docs_type_reviewers banned_models reviewers skip_threshold stand_in_model"
_AID_RC_LEGACY_KEYS="ceremony_bands cp1_codex_review fix_loop skip_trivial trivial_threshold pre_filter"

# aid_policy_file <project_root> <basename> [<yq probe>] [<warning label>]
#   Prints the policy file to read: the project's .aid-o/config/policies/<basename>
#   when it exists and the probe (a yq path that must resolve) succeeds, else the
#   plugin default, with "<label>: using plugin default" on stderr when a project
#   file was passed over.
aid_policy_file() {
  local project="${1}/.aid-o/config/policies/${2}" probe="${3:-.}" label="${4:-$2}"
  if [[ -f "$project" ]]; then
    if yq -e "$probe" "$project" >/dev/null 2>&1; then
      echo "$project"; return 0
    fi
    echo "${label}: using plugin default" >&2
  fi
  echo "${_AID_RC_PLUGIN}/defaults/policies/${2}"
}

# aid_review_switched_off <project_root> <toggle> — the ONE reader of the two
# review switches (`enabled` and the checkpoint's own key). Per switch the first
# file that sets it decides, the project's before the plugin default. Prints
# "<switch>\t<file>" and returns 0 when one of them is false; returns 1 otherwise.
aid_review_switched_off() {
  local flag file value
  for flag in enabled "$2"; do
    [[ -n "$flag" ]] || continue
    value=""
    for file in "${1}/.aid-o/config/policies/review-checkpoints.yaml" "${_AID_RC_PLUGIN}/defaults/policies/review-checkpoints.yaml"; do
      [[ -f "$file" ]] || continue
      value="$(yq -r ".review_checkpoints.${flag}" "$file" 2>/dev/null)"
      [[ "$value" == true || "$value" == false ]] && break
    done
    [[ "$value" == false ]] && { printf '%s\t%s\n' "$flag" "$file"; return 0; }
  done
  return 1
}

_aid_rc_toggle_key() {
  case "$1" in
    plan_review) echo cp1_plan_review ;;
    step_review) [[ "${RC_CHECKPOINT:-}" == cp6 ]] && echo cp6_fast_mode_review || echo cp2_step_review ;;
    epic_review) echo cp3_integration_review ;;
    final_review) echo cp7_plan_final_review ;;
    *) echo "" ;;
  esac
}

aid_review_config_load() {
  local root="${1:?aid_review_config_load: project root required}"
  local block="${2:?aid_review_config_load: block required}"
  local skill="${3:?aid_review_config_load: roles skill required}"
  command -v yq >/dev/null 2>&1 || { echo "${block} config: yq not installed" >&2; return 2; }
  [[ -f "$skill" ]] || { echo "${block} config: roles skill not found: ${skill}" >&2; return 1; }
  RC_BLOCK="$block"; RC_ROLES_SKILL="$skill"

  local project="${root}/.aid-o/config/policies/review-checkpoints.yaml"
  RC_CONFIG_FILE="$(aid_policy_file "$root" review-checkpoints.yaml ".review_checkpoints.${block}" "${block} config")"

  local err
  if ! err="$(yq -e ".review_checkpoints.${block}" "$RC_CONFIG_FILE" 2>&1 >/dev/null)"; then
    printf '%s config: cannot read %s from %s\n%s\n' "$block" "$block" "$RC_CONFIG_FILE" "$err" >&2
    return 1
  fi

  local key
  for key in $(yq -r ".review_checkpoints.${block} | keys | .[]" "$RC_CONFIG_FILE"); do
    [[ " $_AID_RC_KNOWN_KEYS " == *" $key "* ]] || echo "${block} config: ignored unknown key ${block}.${key}" >&2
  done
  # Only a project file is the PM's to clean up; the plugin default is not.
  if [[ "$RC_CONFIG_FILE" == "$project" ]]; then
    for key in $_AID_RC_LEGACY_KEYS; do
      yq -e ".review_checkpoints.${key}" "$RC_CONFIG_FILE" >/dev/null 2>&1 \
        && echo "${block} config: ignored legacy key ${key}" >&2
    done
  fi

  local b=".review_checkpoints.${block}"
  RC_ROUNDS_DEFAULT="$(yq -r "${b}.rounds_default // \"\"" "$RC_CONFIG_FILE")"
  RC_BANNED_MODELS="$(yq -r "${b}.banned_models // [] | .[]" "$RC_CONFIG_FILE" | tr '\n' ' ')"
  RC_EXTRA_DOCS_TYPE_REVIEWERS="$(yq -r "${b}.docs_type_reviewers // [] | .[]" "$RC_CONFIG_FILE" | tr '\n' ' ')"
  RC_EXTRA_SKIP_THRESHOLD_FILES="$(yq -r "${b}.skip_threshold.max_files // \"\"" "$RC_CONFIG_FILE")"
  RC_EXTRA_SKIP_THRESHOLD_LINES="$(yq -r "${b}.skip_threshold.max_lines // \"\"" "$RC_CONFIG_FILE")"
  RC_ROLE=(); RC_PROVIDER=(); RC_MODEL=(); RC_EFFORT=(); RC_WHEN=()
  local role provider model effort when unconditional=0
  while IFS=$'\t' read -r role provider model effort when; do
    [[ -n "$role" ]] || continue
    RC_ROLE+=("$role"); RC_PROVIDER+=("$provider"); RC_MODEL+=("$model"); RC_EFFORT+=("$effort"); RC_WHEN+=("$when")
    [[ -z "$when" ]] && unconditional=$((unconditional + 1))
  done < <(yq -r "${b}.reviewers // [] | .[] | [.role, .provider, .model, (.effort // \"medium\"), (.when // \"\")] | @tsv" "$RC_CONFIG_FILE")
  # The model a Claude stand-in runs at when a codex role gives no answer.
  RC_STAND_IN_MODEL="$(yq -r "${b}.stand_in_model // \"opus\"" "$RC_CONFIG_FILE")"
  RC_MIN_ANSWERS="$(yq -r "${b}.min_answers // \"\"" "$RC_CONFIG_FILE")"
  [[ -n "$RC_MIN_ANSWERS" ]] || RC_MIN_ANSWERS="$unconditional"

  # The two switches are read where the PM sets them: the project file first,
  # whether or not it carries the block. Either one off is off.
  RC_ENABLED=1
  aid_review_switched_off "$root" "$(_aid_rc_toggle_key "$block")" >/dev/null && RC_ENABLED=0

  RC_DEGRADED=0
  local pair a b_
  pair="$(yq --front-matter=extract -r '.distinct_models // [] | .[]' "$skill" 2>/dev/null | tr '\n' ' ')"
  if [[ -n "${pair// /}" ]]; then
    set -- $pair
    a="$(aid_review_role_index "$1")" && b_="$(aid_review_role_index "$2")" \
      && [[ "${RC_MODEL[$a]}" == "${RC_MODEL[$b_]}" ]] && RC_DEGRADED=1
  fi
  export RC_BLOCK RC_CONFIG_FILE RC_ROUNDS_DEFAULT RC_MIN_ANSWERS RC_BANNED_MODELS RC_DEGRADED RC_ENABLED \
         RC_EXTRA_DOCS_TYPE_REVIEWERS RC_EXTRA_SKIP_THRESHOLD_FILES RC_EXTRA_SKIP_THRESHOLD_LINES RC_ROLES_SKILL
  return 0
}

aid_review_role_index() {
  local i
  for i in "${!RC_ROLE[@]}"; do
    [[ "${RC_ROLE[$i]}" == "$1" ]] && { echo "$i"; return 0; }
  done
  return 1
}

aid_review_config_floor() {
  local expected="${1:?expected count required}"
  (( RC_MIN_ANSWERS < expected )) && echo "$RC_MIN_ANSWERS" || echo "$expected"
}

_aid_rc_fail() { echo "${RC_BLOCK:-review} config: $1" >&2; }

aid_review_config_validate() {
  local expected role i seen=" " required unconditional=0
  expected="$(grep -oE '^## Role: [a-z_]+' "$RC_ROLES_SKILL" | sed 's/^## Role: //' | sort | tr '\n' ' ')"
  required="$(yq --front-matter=extract -r '.required_roles // "none"' "$RC_ROLES_SKILL" 2>/dev/null)"

  for i in "${!RC_ROLE[@]}"; do
    role="${RC_ROLE[$i]}"
    [[ "$seen" == *" $role "* ]] && { _aid_rc_fail "duplicate role ${role}"; return 1; }
    seen+="${role} "
    [[ " $expected" == *" $role "* ]] || { _aid_rc_fail "unknown role ${role} (roles of $(basename "$RC_ROLES_SKILL"): ${expected% })"; return 1; }
    case "${RC_PROVIDER[$i]}" in
      claude|codex) ;;
      *) _aid_rc_fail "role ${role}: provider must be claude or codex (got '${RC_PROVIDER[$i]}')"; return 1 ;;
    esac
    [[ -n "${RC_MODEL[$i]}" ]] || { _aid_rc_fail "role ${role}: model is empty"; return 1; }
    [[ " $RC_BANNED_MODELS " == *" ${RC_MODEL[$i]} "* ]] \
      && { _aid_rc_fail "role ${role}: model ${RC_MODEL[$i]} is in banned_models"; return 1; }
    case "${RC_EFFORT[$i]}" in
      low|medium|high) ;;
      *) _aid_rc_fail "role ${role}: effort must be low, medium or high (got '${RC_EFFORT[$i]}')"; return 1 ;;
    esac
    case "${RC_WHEN[$i]}" in
      "") unconditional=$((unconditional + 1)) ;;
      review+security) ;;
      *) _aid_rc_fail "role ${role}: when must be review+security (got '${RC_WHEN[$i]}')"; return 1 ;;
    esac
  done
  [[ " $RC_BANNED_MODELS " == *" $RC_STAND_IN_MODEL "* ]] \
    && { _aid_rc_fail "stand_in_model ${RC_STAND_IN_MODEL} is in banned_models"; return 1; }
  (( unconditional > 0 )) || { _aid_rc_fail "no unconditional role (every reviewer carries a when)"; return 1; }
  if [[ "$required" == all ]]; then
    for role in $expected; do
      [[ "$seen" == *" $role "* ]] || { _aid_rc_fail "missing role ${role}"; return 1; }
    done
  fi
  local roles_n="${#RC_ROLE[@]}"
  [[ "$RC_MIN_ANSWERS" =~ ^[0-9]+$ ]] && (( RC_MIN_ANSWERS >= 1 && RC_MIN_ANSWERS <= (roles_n > 6 ? roles_n : 6) )) \
    || { _aid_rc_fail "min_answers must be 1..6 (got '${RC_MIN_ANSWERS}')"; return 1; }
  [[ "$RC_ROUNDS_DEFAULT" =~ ^[1-3]$ ]] || { _aid_rc_fail "rounds_default must be 1..3 (got '${RC_ROUNDS_DEFAULT}')"; return 1; }
  for role in $RC_EXTRA_DOCS_TYPE_REVIEWERS; do
    [[ "$seen" == *" $role "* ]] || { _aid_rc_fail "docs_type_reviewers names ${role}, which is not a reviewer"; return 1; }
  done
  return 0
}
