#!/usr/bin/env bash
# aid-review-profile.sh — the review-profile producer: plan-time + candidate-time
# risk surfaces over a diff range, emitted as review-profile.json (the C3 gate's
# arming input and a REQUIRED release-policy input). Split out of the retired
# pre-filter by P094 Step 14; same arguments and exit codes.
#
# Policy: the plugin's defaults/policies/review-profiles.yaml is always
# evaluated. A project's .aid-o/config/policies/review-profiles.yaml is merged on
# top of it (it may add surfaces, globs and signals) and evaluated too; the
# effective verdict is the stricter of the two, so a project can raise its own
# review and never lower it. The file records default_verdict, override_verdict,
# effective and the policy files read.
#
# Usage:
#   aid-review-profile.sh <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]
#   (a leading `profile` word is accepted for the callers written against the old script)
#
# Exit codes:
#   0  — profile emitted
#   22 — range_undetermined (no --range and no base_commit in fsm-state.yaml):
#        an unverifiable profile is emitted and the caller continues
#   1  — error (missing argument, file not found, yq error)
#   2  — malformed policy file, or an override naming an undefined risk level
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
# shellcheck source=lib/aid-review-config.sh
source "${SCRIPT_DIR}/lib/aid-review-config.sh"

# path_matches_glob <path> <glob> — gitignore-style: `*` and `?` stay inside one
# path segment, `**/` is any number of directories including none, a trailing
# `**` is everything beneath.
path_matches_glob() {
  local re="$2"
  re="${re//./\\.}"
  re="${re//\*\*\//<dirs>}"; re="${re//\*\*/<any>}"
  re="${re//\*/[^/]*}";       re="${re//\?/[^/]}"
  re="${re//<dirs>/(.*/)?}";   re="${re//<any>/.*}"
  [[ "$1" =~ ^${re}$ ]]
}

# _emit_profile <out> <project_id> <head_sha> <review_profile_json>
# The one writer of review-profile.json.
_emit_profile() {
  local out="$1" project_id="$2" head_sha="$3" body="$4" subject_hash
  subject_hash="sha256:$(printf '%s' "$head_sha" | sha256sum | cut -d' ' -f1)"
  jq -n --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg project_id "$project_id" \
        --arg subject_hash "$subject_hash" --arg head_sha "$head_sha" --argjson body "$body" \
    '{schema_version: "aid-2.0", artifact_type: "review_profile", producer: "aid-review-profile.sh",
      created_at: $created_at, control_protocol: "aid-2.0",
      identity: {project_id: $project_id}, subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: "pass", verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-review-profile.sh"},
      review_profile: $body}' > "$out"
}

# _evaluate_policy <policy_json> — one policy against the diff and the plan's
# paths (DIFF_FILES, DIFF_CONTENT, PLAN_PATHS of the caller). Prints
# {plan_time_surfaces, candidate_time_surfaces, matched_surfaces, required_lenses, risk_profile}.
# A changed file that neither a matched surface nor the docs allowlist names
# makes the verdict the policy's unknown_surface_profile (fail-closed).
_evaluate_policy() {
  local policy="$1" sid glob signal fpath
  local -A plan_hit=() cand_hit=()
  while IFS=$'\t' read -r sid glob; do
    for fpath in "${DIFF_FILES[@]}"; do path_matches_glob "$fpath" "$glob" && cand_hit[$sid]=1; done
    for fpath in "${PLAN_PATHS[@]}"; do path_matches_glob "$fpath" "$glob" && plan_hit[$sid]=1; done
  done < <(jq -r '.surfaces | to_entries[] | .key as $k | .value.match.path_globs[]? | [$k, .] | @tsv' <<<"$policy")
  if [[ -n "$DIFF_CONTENT" ]]; then
    while IFS=$'\t' read -r sid signal; do
      grep -qF -- "$signal" <<<"$DIFF_CONTENT" && cand_hit[$sid]=1
    done < <(jq -r '.surfaces | to_entries[] | .key as $k | .value.match.content_signals[]? | [$k, .] | @tsv' <<<"$policy")
  fi

  local matched; matched="$(printf '%s\n' "${!plan_hit[@]}" "${!cand_hit[@]}" | jq -Rn '[inputs | select(. != "")] | unique')"
  local has_unknown=false known
  for fpath in "${DIFF_FILES[@]}"; do
    known=false
    while IFS= read -r glob; do
      path_matches_glob "$fpath" "$glob" && { known=true; break; }
    done < <(jq -r --argjson m "$matched" '(.docs_allowlist // [])[], (.surfaces | to_entries[] | select(.key as $k | $m | index($k)) | .value.match.path_globs[]?)' <<<"$policy")
    [[ "$known" == true ]] || { has_unknown=true; break; }
  done

  jq -n --argjson policy "$policy" --argjson matched "$matched" --argjson unknown "$has_unknown" \
        --argjson plan "$(printf '%s\n' "${!plan_hit[@]}" | jq -Rn '[inputs | select(. != "")] | sort')" \
        --argjson cand "$(printf '%s\n' "${!cand_hit[@]}" | jq -Rn '[inputs | select(. != "")] | sort')" \
    --argjson order "$RISK_ORDER" '
    ($policy.unknown_surface_profile // "unverifiable") as $unknown_profile
    | {plan_time_surfaces: $plan, candidate_time_surfaces: $cand, matched_surfaces: $matched,
       required_lenses: ([$matched[] | $policy.surfaces[.].lenses[]?] | unique),
       risk_profile: (if $unknown or ($matched | length) == 0 then $unknown_profile
                      else ([$matched[] | $policy.surfaces[.].risk // "low"] | max_by(. as $r | $order | index($r))) end)}'
}

# Strictness order of the verdicts; unverifiable is the strictest.
RISK_ORDER='["docs_trivial","low","medium","high","unverifiable"]'

cmd_profile() {
  [[ $# -lt 2 ]] && die "profile requires <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]"
  local plan_path=$1 evidence_dir=$2
  shift 2

  local out_path="" diff_range=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)   [[ $# -lt 2 ]] && die "--out requires a path"; out_path="$2"; shift 2 ;;
      --range) [[ $# -lt 2 ]] && die "--range requires <base..head>"; diff_range="$2"; shift 2 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  command -v yq &>/dev/null || die "yq (mikefarah variant) required — install via: apt install yq / brew install yq"
  [[ -d "$evidence_dir" ]] || die "Evidence dir not found: $evidence_dir"
  [[ -n "$out_path" ]] || out_path="${evidence_dir}/review-profile.json"

  local ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
  local timeline="${evidence_dir}/timeline.jsonl" fsm_state="${evidence_dir}/fsm-state.yaml"
  local project_id="unknown" head_sha
  [[ -f "$fsm_state" ]] && project_id=$(yq -r '.project_id // "unknown"' "$fsm_state" 2>/dev/null || echo unknown)
  head_sha=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")

  # --- Policy: the plugin default always, the project file on top when it parses ---
  local default_file="${_AID_RC_PLUGIN}/defaults/policies/review-profiles.yaml"
  [[ -f "$default_file" ]] || die "review-profiles.yaml not found: $default_file"
  local state_root override_file default_policy merged_policy=""
  state_root="$(aid_state_root "$ROOT" 2>/dev/null)" || state_root="$ROOT"
  override_file="$(aid_policy_file "$state_root" review-profiles.yaml .surfaces)"
  default_policy="$(yq -o=json '.' "$default_file")" || { echo "ERROR: malformed $default_file" >&2; exit 2; }
  if [[ "$override_file" != "$default_file" ]]; then
    # Maps merge deeply, lists append: an override adds surfaces, globs and signals.
    merged_policy="$(yq -o=json eval-all '. as $item ireduce ({}; . *+ $item)' "$default_file" "$override_file")"
    local bad_levels
    bad_levels="$(jq -r '(.risk_profiles | keys) as $valid | [.surfaces[] | .risk // "low" | select(. as $r | $valid | index($r) | not)] | unique | join(", ")' <<<"$merged_policy")"
    if [[ -n "$bad_levels" ]]; then
      echo "ERROR: $override_file names an undefined risk level: $bad_levels (valid: $(jq -r '.risk_profiles | keys | join(", ")' <<<"$merged_policy"))" >&2
      exit 2
    fi
  fi

  # --- Range: --range, else base_commit of the run; never a silent HEAD~1 ---
  if [[ -z "$diff_range" && -f "$fsm_state" ]]; then
    local base_commit
    base_commit=$(yq -r '.base_commit // ""' "$fsm_state" 2>/dev/null || echo "")
    [[ -n "$base_commit" && "$base_commit" != "null" ]] && diff_range="${base_commit}..HEAD"
  fi
  if [[ -z "$diff_range" ]]; then
    _emit_profile "$out_path" "$project_id" "$head_sha" "$(jq -n --argjson p "$default_policy" '
      {matched_surfaces: [], plan_time_surfaces: [], candidate_time_surfaces: [], required_lenses: [],
       risk_profile: "unverifiable", default_verdict: "unverifiable", override_verdict: null, effective: "unverifiable",
       policy_files: [], profile_hash: ("sha256:" + ("0" * 64))} + ($p.risk_profiles.unverifiable | {ir_cadence, c2_authorities_max, llm_authorities_total_max})')"
    log_event "$timeline" "review_profile_emitted" risk_profile="unverifiable" reason="range_undetermined" out="$out_path"
    echo "range_undetermined: no --range and no base_commit in fsm-state.yaml" >&2
    exit 22
  fi

  # --- Inputs of the evaluation: the diff, and the paths the plan names ---
  local -a DIFF_FILES=() PLAN_PATHS=()
  mapfile -t DIFF_FILES < <(git -C "$ROOT" diff --name-only "$diff_range" 2>/dev/null)
  local DIFF_CONTENT; DIFF_CONTENT=$(git -C "$ROOT" diff "$diff_range" 2>/dev/null || echo "")
  if [[ -n "$plan_path" && -f "$plan_path" ]]; then
    local in_section=false line extracted
    while IFS= read -r line; do
      if [[ "$line" =~ \*\*Files:\*\*|^###\ Allowed\ files|^##\ Allowed\ files|^##\ Scope ]]; then
        in_section=true; continue
      fi
      [[ "$in_section" == true ]] || continue
      if [[ "$line" =~ ^#{1,4}[[:space:]] ]]; then in_section=false; continue; fi
      extracted=""
      if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+\`([^\`]+)\` ]]; then
        extracted="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+([^[:space:]].+) ]]; then
        extracted="${BASH_REMATCH[1]}"
        extracted="${extracted%%\`*}"; extracted="${extracted%% #*}"; extracted="${extracted%% —*}"
        extracted="${extracted%%[[:space:]]}"
      fi
      [[ -n "$extracted" && ("$extracted" == *"/"* || "$extracted" == *"."*) ]] && PLAN_PATHS+=("$extracted")
    done < "$plan_path"
  fi

  # --- Verdicts: the default alone, the default with the override, the stricter wins ---
  local default_eval override_eval="null" body
  default_eval="$(_evaluate_policy "$default_policy")"
  [[ -n "$merged_policy" ]] && override_eval="$(_evaluate_policy "$merged_policy")"
  body="$(jq -n --argjson d "$default_eval" --argjson o "$override_eval" --argjson order "$RISK_ORDER" \
             --argjson policy "${merged_policy:-$default_policy}" \
             --argjson files "$(printf '%s\n' "$default_file" ${merged_policy:+"$override_file"} | jq -Rn '[inputs]')" '
    ($o // $d) as $e
    | ([$d.risk_profile, $e.risk_profile] | max_by(. as $r | $order | index($r))) as $effective
    | $e + {risk_profile: $effective, default_verdict: $d.risk_profile,
            override_verdict: ($o | if . then .risk_profile else null end), effective: $effective, policy_files: $files}
      + ($policy.risk_profiles[$effective] // {} | {ir_cadence: (.ir_cadence // 3), c2_authorities_max: (.c2_authorities_max // 3), llm_authorities_total_max: (.llm_authorities_total_max // 5)})')"

  # shellcheck source=lib/aid-profile-hash.sh
  source "${SCRIPT_DIR}/lib/aid-profile-hash.sh"
  local hash
  hash=$(profile_hash "$(basename "$ROOT")" "$(jq -r '.plan_time_surfaces | join(" ")' <<<"$body")" \
           "$(jq -r '.candidate_time_surfaces | join(" ")' <<<"$body")" "$(jq -r '.required_lenses | join(" ")' <<<"$body")")
  _emit_profile "$out_path" "$project_id" "$head_sha" "$(jq --arg h "$hash" '. + {profile_hash: $h}' <<<"$body")"

  local risk_profile; risk_profile="$(jq -r '.risk_profile' <<<"$body")"
  log_event "$timeline" "review_profile_emitted" risk_profile="$risk_profile" \
    matched_surfaces="$(jq -r '.matched_surfaces | join(",")' <<<"$body")" \
    required_lenses="$(jq -r '.required_lenses | join(",")' <<<"$body")" out="$out_path"
  echo "review-profile.json emitted: $out_path (risk_profile=$risk_profile)"
  exit 0
}

main() {
  [[ "${1:-}" == profile ]] && shift
  [[ $# -ge 2 ]] || { echo "Usage: aid-review-profile.sh <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]" >&2; exit 1; }
  cmd_profile "$@"
}

main "$@"
