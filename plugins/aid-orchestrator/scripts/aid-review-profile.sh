#!/usr/bin/env bash
# aid-review-profile.sh — the review-profile producer: plan-time + candidate-time
# risk surfaces over a diff range, emitted as review-profile.json (the C3 gate's
# arming input and a REQUIRED release-policy input). Split out of the retired
# pre-filter by P094 Step 14; same arguments, same output, same exit codes.
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
#   2  — malformed rules file
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${AID_PLUGIN_PATH:-${SCRIPT_DIR}/..}/defaults/pre-filter-rules.yaml"

# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

path_matches_glob() {
  # Glob matching with ** support via bash case statement (shopt globstar).
  # NOTE: bash case/**  does NOT match zero directory levels, so "a/**/*.sh"
  # won't match "a/foo.sh". We handle this by also trying with "**/" removed
  # (the direct-child pattern) when the glob contains "/**/".
  # Returns 0 if fpath matches glob, 1 otherwise.
  local fpath="$1" glob="$2"
  local save_globstar
  save_globstar=$(shopt -p globstar 2>/dev/null || echo "shopt -u globstar")
  shopt -s globstar 2>/dev/null || true
  local result=1
  case "$fpath" in
    $glob) result=0 ;;
  esac
  # Fallback: try direct-child match (strip "**/" from glob) for zero-level ** matching
  if [[ $result -ne 0 && "$glob" == *"/**/"* ]]; then
    local direct_glob="${glob/\*\*\//}"
    case "$fpath" in
      $direct_glob) result=0 ;;
    esac
  fi
  eval "$save_globstar" 2>/dev/null || true
  return $result
}

cmd_profile() {
  # CLI: profile <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]
  [[ $# -lt 2 ]] && die "profile requires <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]"
  local plan_path=$1 evidence_dir=$2
  shift 2

  local out_path="" range_arg=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)   [[ $# -lt 2 ]] && die "--out requires a path"; out_path="$2"; shift 2 ;;
      --range) [[ $# -lt 2 ]] && die "--range requires <base..head>"; range_arg="$2"; shift 2 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  if ! command -v yq &>/dev/null; then
    die "yq (mikefarah variant) required — install via: apt install yq / brew install yq"
  fi

  local PROFILES_FILE="${AID_PLUGIN_PATH:-${SCRIPT_DIR}/..}/defaults/policies/review-profiles.yaml"
  local ROOT="${AID_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
  local timeline="${evidence_dir}/timeline.jsonl"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  [[ -f "$PROFILES_FILE" ]] || die "review-profiles.yaml not found: $PROFILES_FILE"
  [[ -d "$evidence_dir" ]] || die "Evidence dir not found: $evidence_dir"

  # Default output path
  [[ -z "$out_path" ]] && out_path="${evidence_dir}/review-profile.json"

  # --- Resolve git diff range ---
  local diff_range=""
  if [[ -n "$range_arg" ]]; then
    diff_range="$range_arg"
  else
    # Try base_commit from fsm-state.yaml in evidence dir
    local fsm_state="${evidence_dir}/fsm-state.yaml"
    if [[ -f "$fsm_state" ]]; then
      local base_commit
      base_commit=$(yq -r '.base_commit // ""' "$fsm_state" 2>/dev/null || echo "")
      if [[ -n "$base_commit" && "$base_commit" != "null" ]]; then
        diff_range="${base_commit}..HEAD"
      fi
    fi
  fi

  # CRITICAL: no silent HEAD~1..HEAD fallback (FC-41)
  if [[ -z "$diff_range" ]]; then
    # Read project_id from fsm-state.yaml for identity field
    local project_id="unknown"
    if [[ -f "$fsm_state" ]]; then
      project_id=$(yq -r '.project_id // "unknown"' "$fsm_state" 2>/dev/null || echo "unknown")
    fi

    local head_sha subject_hash
    head_sha=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
    if [[ "$head_sha" != "unknown" ]]; then
      subject_hash="sha256:$(printf '%s' "$head_sha" | sha256sum | cut -d' ' -f1)"
    else
      subject_hash="sha256:0000000000000000000000000000000000000000000000000000000000000000"
    fi

    local result_json
    result_json=$(jq -n \
      --arg schema_version "aid-2.0" \
      --arg artifact_type "review_profile" \
      --arg producer "aid-prefilter.sh profile" \
      --arg created_at "$now" \
      --arg control_protocol "aid-2.0" \
      --arg project_id "$project_id" \
      --arg subject_hash "$subject_hash" \
      --arg head_sha "$head_sha" \
      --arg status "pass" \
      '{
        schema_version: $schema_version,
        artifact_type: $artifact_type,
        producer: $producer,
        created_at: $created_at,
        control_protocol: $control_protocol,
        identity: {project_id: $project_id},
        subject: {subject_hash: $subject_hash},
        revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
        status: $status,
        verdict: {kind: "none", ready: false},
        provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-prefilter.sh"},
        review_profile: {
          matched_surfaces: [],
          plan_time_surfaces: [],
          candidate_time_surfaces: [],
          required_lenses: [],
          risk_profile: "unverifiable",
          ir_cadence: 3,
          c2_authorities_max: 3,
          llm_authorities_total_max: 5,
          profile_hash: "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        }
      }')
    echo "$result_json" > "$out_path"
    log_event "$timeline" "review_profile_emitted" \
      risk_profile="unverifiable" reason="range_undetermined" out="$out_path"
    echo "range_undetermined: no --range and no base_commit in fsm-state.yaml" >&2
    exit 22
  fi

  # --- Get candidate-time diff (run in $ROOT to target the correct repo) ---
  local diff_files diff_content
  diff_files=$(git -C "$ROOT" diff --name-only "${diff_range}" 2>/dev/null || echo "")
  diff_content=$(git -C "$ROOT" diff "${diff_range}" 2>/dev/null || echo "")

  # --- Load docs_allowlist and surface IDs from policy ---
  local unknown_surface_profile
  unknown_surface_profile=$(yq -r '.unknown_surface_profile // "unverifiable"' "$PROFILES_FILE")

  local surface_ids=()
  mapfile -t surface_ids < <(yq -r '.surfaces | keys | .[]' "$PROFILES_FILE" 2>/dev/null)

  # --- Match candidate-time surfaces (files in diff matching surface globs/signals) ---
  local candidate_surfaces=()
  declare -A candidate_seen
  for sid in "${surface_ids[@]}"; do
    local matched=false

    # Check path_globs against diff files
    local globs_list
    mapfile -t globs_list < <(yq -r ".surfaces[\"${sid}\"].match.path_globs // [] | .[]" "$PROFILES_FILE" 2>/dev/null)
    for glob in "${globs_list[@]}"; do
      [[ -z "$glob" ]] && continue
      while IFS= read -r fpath; do
        [[ -z "$fpath" ]] && continue
        if path_matches_glob "$fpath" "$glob"; then
          matched=true; break 2
        fi
      done <<< "$diff_files"
    done

    # Check content_signals in diff content (only if not already matched by path)
    if [[ "$matched" == "false" && -n "$diff_content" ]]; then
      local signals_list
      mapfile -t signals_list < <(yq -r ".surfaces[\"${sid}\"].match.content_signals // [] | .[]" "$PROFILES_FILE" 2>/dev/null)
      for signal in "${signals_list[@]}"; do
        [[ -z "$signal" ]] && continue
        if grep -qF "$signal" <<< "$diff_content"; then
          matched=true; break
        fi
      done
    fi

    if [[ "$matched" == "true" && -z "${candidate_seen[$sid]:-}" ]]; then
      candidate_seen[$sid]=1
      candidate_surfaces+=("$sid")
    fi
  done

  # --- Plan-time surfaces: parse Files/Allowed files/paths section, match via path_globs ---
  local plan_surfaces=()
  declare -A plan_seen
  if [[ -n "$plan_path" && -f "$plan_path" ]]; then
    local plan_paths=()
    local in_section=false
    while IFS= read -r line; do
      # Detect section headers
      if [[ "$line" =~ \*\*Files:\*\*|^###\ Allowed\ files|^##\ Allowed\ files|^##\ Scope ]]; then
        in_section=true
        continue
      fi
      if [[ "$in_section" == "true" ]]; then
        # Stop at next markdown heading or empty section end indicator
        if [[ "$line" =~ ^#{1,4}[[:space:]] ]]; then
          in_section=false
          continue
        fi
        # Extract path from bullet line: "- `path/to/file`" or "- path/to/file"
        local extracted=""
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+\`([^\`]+)\` ]]; then
          extracted="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+([^[:space:]].+) ]]; then
          extracted="${BASH_REMATCH[1]}"
          # Strip trailing backtick/quote/comment if any
          extracted="${extracted%%\`*}"
          extracted="${extracted%% #*}"
          extracted="${extracted%% —*}"
          extracted="${extracted%%[[:space:]]}"
        fi
        # Only keep if looks like a file path (contains / or has extension)
        if [[ -n "$extracted" && ("$extracted" == *"/"* || "$extracted" == *"."*) ]]; then
          plan_paths+=("$extracted")
        fi
      fi
    done < "$plan_path"

    # Match each plan path against each surface's path_globs
    for ppath in "${plan_paths[@]}"; do
      for sid in "${surface_ids[@]}"; do
        [[ -n "${plan_seen[$sid]:-}" ]] && continue
        local globs
        mapfile -t globs < <(yq -r ".surfaces.${sid}.match.path_globs[]?" "$PROFILES_FILE" 2>/dev/null)
        for glob in "${globs[@]}"; do
          if path_matches_glob "$ppath" "$glob"; then
            plan_seen[$sid]=1
            plan_surfaces+=("$sid")
            break
          fi
        done
      done
    done
  fi

  # --- Monotonic union (FC-41): plan + candidate, never shrink ---
  local matched_surfaces=()
  declare -A seen_surfaces
  for s in "${plan_surfaces[@]}" "${candidate_surfaces[@]}"; do
    if [[ -z "${seen_surfaces[$s]:-}" ]]; then
      seen_surfaces[$s]=1
      matched_surfaces+=("$s")
    fi
  done

  # --- Check for unknown production paths (not in any matched surface or docs_allowlist) ---
  local has_unknown=false
  if [[ -n "$diff_files" ]]; then
    local docs_globs=()
    mapfile -t docs_globs < <(yq -r '.docs_allowlist // [] | .[]' "$PROFILES_FILE" 2>/dev/null)

    while IFS= read -r fpath; do
      [[ -z "$fpath" ]] && continue
      local in_matched=false in_docs=false

      # Check if file matches any matched surface's globs
      for sid in "${matched_surfaces[@]}"; do
        local globs_j=()
        mapfile -t globs_j < <(yq -r ".surfaces[\"${sid}\"].match.path_globs // [] | .[]" "$PROFILES_FILE" 2>/dev/null)
        for glob in "${globs_j[@]}"; do
          [[ -z "$glob" ]] && continue
          if path_matches_glob "$fpath" "$glob"; then
            in_matched=true; break 2
          fi
        done
      done

      # Check if file is in docs_allowlist
      for dglob in "${docs_globs[@]}"; do
        [[ -z "$dglob" ]] && continue
        if path_matches_glob "$fpath" "$dglob"; then
          in_docs=true; break
        fi
      done

      if [[ "$in_matched" == "false" && "$in_docs" == "false" ]]; then
        has_unknown=true; break
      fi
    done <<< "$diff_files"
  fi

  # --- Determine risk_profile (highest of matched surfaces, or unverifiable) ---
  local risk_order=("docs_trivial" "low" "medium" "high")
  local risk_profile="docs_trivial"

  if [[ "$has_unknown" == "true" ]]; then
    risk_profile="$unknown_surface_profile"
  elif [[ ${#matched_surfaces[@]} -eq 0 ]]; then
    risk_profile="$unknown_surface_profile"
  else
    for sid in "${matched_surfaces[@]}"; do
      local srisk
      srisk=$(yq -r ".surfaces[\"${sid}\"].risk // \"low\"" "$PROFILES_FILE" 2>/dev/null)
      local current_idx=0 new_idx=0 i=0
      for r in "${risk_order[@]}"; do
        [[ "$r" == "$risk_profile" ]] && current_idx=$i
        [[ "$r" == "$srisk" ]] && new_idx=$i
        ((i++)) || true
      done
      [[ $new_idx -gt $current_idx ]] && risk_profile="$srisk"
    done
  fi

  # --- Get risk_profile config ---
  local ir_cadence c2_max llm_max
  if yq -e ".risk_profiles | has(\"$risk_profile\")" "$PROFILES_FILE" &>/dev/null; then
    ir_cadence=$(yq -r ".risk_profiles[\"${risk_profile}\"].ir_cadence // 3" "$PROFILES_FILE")
    c2_max=$(yq -r ".risk_profiles[\"${risk_profile}\"].c2_authorities_max // 3" "$PROFILES_FILE")
    llm_max=$(yq -r ".risk_profiles[\"${risk_profile}\"].llm_authorities_total_max // 5" "$PROFILES_FILE")
  else
    ir_cadence=3; c2_max=3; llm_max=5
  fi

  # --- Collect required_lenses (union of all matched surface lenses) ---
  declare -A seen_lenses
  local required_lenses=()
  for sid in "${matched_surfaces[@]}"; do
    local slenses=()
    mapfile -t slenses < <(yq -r ".surfaces[\"${sid}\"].lenses // [] | .[]" "$PROFILES_FILE" 2>/dev/null)
    for l in "${slenses[@]}"; do
      [[ -z "$l" ]] && continue
      if [[ -z "${seen_lenses[$l]:-}" ]]; then
        seen_lenses[$l]=1
        required_lenses+=("$l")
      fi
    done
  done

  # --- Compute profile_hash ---
  local plan_surfaces_str="${plan_surfaces[*]:-}"
  local candidate_surfaces_str="${candidate_surfaces[*]:-}"
  local lenses_str="${required_lenses[*]:-}"

  local HASH_LIB="${SCRIPT_DIR}/lib/aid-profile-hash.sh"
  local profile_hash_val="sha256:0000000000000000000000000000000000000000000000000000000000000000"
  if [[ -f "$HASH_LIB" ]]; then
    # shellcheck source=lib/aid-profile-hash.sh
    source "$HASH_LIB"
    profile_hash_val=$(profile_hash "$(basename "$ROOT")" "$plan_surfaces_str" "$candidate_surfaces_str" "$lenses_str")
  fi

  # --- Build JSON arrays ---
  # grep exits 1 on no-match; under pipefail that would corrupt the $() capture.
  # Use { grep … || true; } to absorb grep's non-zero exit so only jq failures propagate.
  local matched_json plan_json candidate_json required_json
  matched_json=$(printf '%s\n' "${matched_surfaces[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc . 2>/dev/null || echo "[]")
  plan_json=$(printf '%s\n' "${plan_surfaces[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc . 2>/dev/null || echo "[]")
  candidate_json=$(printf '%s\n' "${candidate_surfaces[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc . 2>/dev/null || echo "[]")
  required_json=$(printf '%s\n' "${required_lenses[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc . 2>/dev/null || echo "[]")

  # --- T6 resource accounting: wall time start ---
  local wall_start; wall_start=$(date +%s%3N)

  # --- Read epic_id / run_id from fsm-state.yaml if available ---
  local epic_id="unknown" run_id="unknown" project_id="unknown"
  local fsm_state_f="${evidence_dir}/fsm-state.yaml"
  if [[ -f "$fsm_state_f" ]]; then
    epic_id=$(yq -r '.epic_id // "unknown"' "$fsm_state_f" 2>/dev/null || echo "unknown")
    run_id=$(yq -r '.run_id // "unknown"' "$fsm_state_f" 2>/dev/null || echo "unknown")
    project_id=$(yq -r '.project_id // "unknown"' "$fsm_state_f" 2>/dev/null || echo "unknown")
  fi

  # --- Compute subject hash and producer version ---
  local head_sha subject_hash
  head_sha=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
  # For subject_hash, compute sha256 of the HEAD sha to get 64-char hex
  if [[ "$head_sha" != "unknown" ]]; then
    subject_hash="sha256:$(printf '%s' "$head_sha" | sha256sum | cut -d' ' -f1)"
  else
    subject_hash="sha256:0000000000000000000000000000000000000000000000000000000000000000"
  fi

  local producer_version="$(cd "${AID_PLUGIN_PATH:-.}/.." && git describe --tags --always 2>/dev/null || echo "2.42.0")"
  local producer="aid-prefilter.sh profile@${producer_version}"

  # --- Emit review-profile.json ---
  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "review_profile" \
    --arg producer "$producer" \
    --arg created_at "$now" \
    --arg control_protocol "aid-2.0" \
    --arg project_id "$project_id" \
    --arg subject_hash "$subject_hash" \
    --arg head_sha "$head_sha" \
    --arg status "pass" \
    --argjson matched "$matched_json" \
    --argjson plan "$plan_json" \
    --argjson candidate "$candidate_json" \
    --argjson required "$required_json" \
    --arg risk_profile "$risk_profile" \
    --argjson ir_cadence "$ir_cadence" \
    --argjson c2_max "$c2_max" \
    --argjson llm_max "$llm_max" \
    --arg profile_hash "$profile_hash_val" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: {project_id: $project_id},
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: $status,
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-prefilter.sh"},
      review_profile: {
        matched_surfaces: $matched,
        plan_time_surfaces: $plan,
        candidate_time_surfaces: $candidate,
        required_lenses: $required,
        risk_profile: $risk_profile,
        ir_cadence: $ir_cadence,
        c2_authorities_max: $c2_max,
        llm_authorities_total_max: $llm_max,
        profile_hash: $profile_hash
      }
    }' > "$out_path"

  # --- T6 resource accounting: wall time end ---
  local wall_end; wall_end=$(date +%s%3N)
  local wall_ms=$(( wall_end - wall_start ))
  log_event "$timeline" "review_profile_resource" \
    model_calls=0 input_tokens=0 output_tokens=0 wall_time_ms="$wall_ms"

  log_event "$timeline" "review_profile_emitted" \
    risk_profile="$risk_profile" \
    matched_surfaces="$(IFS=,; echo "${matched_surfaces[*]:-}")" \
    required_lenses="$(IFS=,; echo "${required_lenses[*]:-}")" \
    out="$out_path"

  echo "review-profile.json emitted: $out_path (risk_profile=$risk_profile)"
  exit 0
}

main() {
  [[ "${1:-}" == profile ]] && shift
  [[ $# -ge 2 ]] || { echo "Usage: aid-review-profile.sh <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]" >&2; exit 1; }
  cmd_profile "$@"
}

main "$@"
