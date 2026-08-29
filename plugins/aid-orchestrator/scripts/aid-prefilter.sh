#!/usr/bin/env bash
# aid-prefilter.sh — Deterministic pre-filter for classify and profile commands.
# classify: classifies step git diff as SKIP / RUN / FAIL, writes verifier-output-step-N.md.
# profile: computes plan-time + candidate-time surfaces, emits review-profile.json.
#
# Exit codes (non-conflicting with bash convention):
#   0  — SKIP (classify) or profile success
#   10 — RUN   (standard code change; code-review verifier should be dispatched)
#   20 — FAIL  (security-sensitive pattern detected; security verifier must be dispatched)
#   22 — range_undetermined (profile: no --range and no base_commit in fsm-state.yaml;
#          classify cp2: no step_commit in timeline and no base_commit — blocking policy)
#   1  — error (missing argument, file not found, yq error)
#   2  — malformed rules file
#
# Usage:
#   aid-prefilter.sh classify <step_n> <evidence_dir> [--checkpoint <cp2|cp3|cp4|cp6>]
#   aid-prefilter.sh profile <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]
#
# --checkpoint flag (v2.35+):
#   Controls the git diff range used for classification. Default (no flag) = cp2 behavior.
#   cp2 — step-boundary diff (P060 Step 3, OBS-20260705-01). Range resolution order:
#          1. last step_commit event in timeline.jsonl → step_commit_sha..HEAD
#          2. absent → base_commit from evidence_dir/fsm-state.yaml → base_commit..HEAD (wider, fail-safe)
#          3. neither → exit 22 range_undetermined (blocking), NEVER a silent HEAD~1.
#          Emergency valve CP2_RANGE_POLICY=observe|blocking (default blocking):
#          observe = emit cp2_range_fallback event + LOUD stderr, then classify with HEAD~1..HEAD.
#   cp3 — base_commit..HEAD (full EPIC diff; base_commit read from evidence_dir/fsm-state.yaml if present,
#          falls back to git merge-base HEAD origin/main)
#   cp4 — HEAD~1..HEAD (C+A applied changes are always the last commit)
#   cp6 — HEAD~1..HEAD (fast mode: no fsm-state/timeline by design; advisory, evaluated outside FSM flow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${AID_PLUGIN_PATH:-${SCRIPT_DIR}/..}/defaults/pre-filter-rules.yaml"

# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"


main() {
  local cmd="${1:-}"
  if [[ -z "$cmd" ]]; then
    echo "Usage: aid-prefilter.sh <command> [args]" >&2
    echo "Commands:" >&2
    echo "  classify <step_n> <evidence_dir> [--checkpoint <cp2|cp3|cp4|cp6>]" >&2
    echo "  profile <plan_or_epic_path> <evidence_dir> [--out <path>] [--range <base..head>]" >&2
    exit 1
  fi
  shift
  case "$cmd" in
    classify) cmd_classify "$@" ;;
    profile)  cmd_profile "$@" ;;
    *) die "Unknown command: $cmd. Use: classify, profile" ;;
  esac
}

# _classify_say <classification> <step> <reason> <exit_code> — the one line a
# caller sees; every classification exit goes through here so the branches
# cannot drift (the result used to be visible only in the file and the exit code).
_classify_say() {
  printf 'classify: %s step=%s reason=%s (exit %s)\n' "$1" "$2" "$3" "$4"
}

cmd_classify() {
  [[ $# -lt 2 ]] && die "classify requires <step_n> <evidence_dir> [--checkpoint <cp2|cp3|cp4|cp6>]"
  local step_n=$1 evidence_dir=$2
  shift 2

  # Parse optional --checkpoint flag (v2.35+)
  local checkpoint="cp2"  # default: step diff (backward-compatible)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --checkpoint)
        [[ $# -lt 2 ]] && die "--checkpoint requires an argument (cp2|cp3|cp4|cp6)"
        checkpoint="$2"
        case "$checkpoint" in
          cp2|cp3|cp4|cp6) ;;
          *) die "Unknown checkpoint '$checkpoint'. Valid values: cp2 cp3 cp4 cp6" ;;
        esac
        shift 2
        ;;
      *) die "Unknown argument: $1" ;;
    esac
  done

  [[ -d "$evidence_dir" ]] || die "Evidence dir not found: $evidence_dir"

  if ! command -v yq &>/dev/null; then
    die "yq (mikefarah variant) required — install via:
  apt install yq         (Debian/Ubuntu, provides mikefarah yq)
  brew install yq        (macOS)
  pacman -S go-yq        (Arch)
  go install github.com/mikefarah/yq/v4@latest
NOT the Python yq PyPI package (incompatible CLI)."
  fi

  [[ -f "$RULES_FILE" ]] || die "Rules file not found: $RULES_FILE"

  # Validate rule IDs conform to ^[a-z][a-z0-9_]*$ (prevents shell injection via matched_rules)
  validate_rule_ids || die "Rules file has invalid rule IDs: $RULES_FILE"

  local timeline="${evidence_dir}/timeline.jsonl"
  local output_file="${evidence_dir}/verifier-output-step-${step_n}.md"

  # Resolve diff range based on checkpoint.
  # cp2 (default): step-boundary diff (P060 Step 3, OBS-20260705-01). D6 order below.
  # cp3: base_commit..HEAD — full EPIC diff since run start
  #      base_commit is read from evidence_dir/fsm-state.yaml if present; falls back to
  #      git merge-base HEAD origin/main (approximate when fsm-state unavailable)
  # cp4: HEAD~1..HEAD — curator/auditor changes are always the last commit
  # cp6: HEAD~1..HEAD — fast mode: no fsm-state/timeline by design (advisory)
  local diff_base="HEAD~1"  # cp4, cp6 (fast mode: no fsm-state by design) use this
  if [[ "$checkpoint" == "cp2" ]]; then
    # ── P060 Step 3: cp2 classifies from the STEP boundary, not the last commit ──
    # OBS-20260705-01: a production step with a bookkeeping commit on top was
    # false-green'd docs_only because HEAD~1..HEAD only saw the last commit.
    # D6 resolution order (fail-safe WIDER, never a silent HEAD~1):
    #   1. last step_commit event in timeline → step_commit_sha..HEAD
    #   2. base_commit in evidence_dir/fsm-state.yaml → base_commit..HEAD
    #   3. neither → exit 22 (blocking) OR loud HEAD~1 fallback (observe policy)
    local cp2_policy="${CP2_RANGE_POLICY:-blocking}"
    local step_commit_sha=""
    if [[ -f "$timeline" ]] && command -v jq &>/dev/null; then
      # LAST step_commit event's commit_sha (producer: aid-fsm.sh cmd_increment_step)
      step_commit_sha=$(jq -r 'select(.event == "step_commit") | .commit_sha' "$timeline" 2>/dev/null | tail -n1 || echo "")
    fi
    if [[ -n "$step_commit_sha" && "$step_commit_sha" != "null" && "$step_commit_sha" != "unknown" ]]; then
      diff_base="$step_commit_sha"
    else
      local base_commit=""
      local fsm_state_file="${evidence_dir}/fsm-state.yaml"
      if [[ -f "$fsm_state_file" ]] && command -v yq &>/dev/null; then
        base_commit=$(yq -r '.base_commit // ""' "$fsm_state_file" 2>/dev/null || echo "")
      fi
      if [[ -n "$base_commit" && "$base_commit" != "null" ]]; then
        diff_base="$base_commit"
      elif [[ "$cp2_policy" == "observe" ]]; then
        # Emergency valve: loud fallback to HEAD~1..HEAD, still classify (do not block).
        diff_base="HEAD~1"
        log_event "$timeline" "cp2_range_fallback" step="$step_n" \
          reason="range_undetermined" policy="observe" fallback="HEAD~1..HEAD"
        echo "WARNING [CP2_RANGE_POLICY=observe]: cp2 step $step_n range_undetermined \
(no step_commit in timeline, no base_commit in fsm-state.yaml) — LOUD FALLBACK to \
HEAD~1..HEAD. Classification may miss production changes hidden behind bookkeeping \
commits (OBS-20260705-01). Emit step_commit/base_commit to restore step-boundary range." >&2
      else
        # blocking (default): no determinable range — refuse to classify, no SKIP stub.
        log_event "$timeline" "cp2_range_undetermined" step="$step_n" policy="blocking"
        echo "range_undetermined: cp2 step $step_n has no step_commit event in timeline.jsonl \
and no base_commit in fsm-state.yaml. Emit step_commit (FSM increment) or base_commit, or set \
CP2_RANGE_POLICY=observe to fall back to HEAD~1..HEAD. NEVER hand-craft the output file." >&2
        _classify_say NONE "$step_n" range_undetermined 22
        exit 22
      fi
    fi
  elif [[ "$checkpoint" == "cp3" ]]; then
    # Attempt to read base_commit from fsm-state.yaml in the RUN dir (= evidence_dir).
    # P060 Step 3 fix: fsm-state.yaml lives in evidence_dir, NOT the parent dir.
    local fsm_state_file="${evidence_dir}/fsm-state.yaml"
    if [[ -f "$fsm_state_file" ]] && command -v yq &>/dev/null; then
      local base_commit
      base_commit=$(yq -r '.base_commit // ""' "$fsm_state_file" 2>/dev/null || echo "")
      if [[ -n "$base_commit" && "$base_commit" != "null" ]]; then
        diff_base="$base_commit"
      else
        # Fallback: approximate with git merge-base (may differ from EPIC start)
        diff_base=$(git merge-base HEAD origin/main 2>/dev/null || echo "HEAD~5")
        log_warn "cp3: base_commit not in fsm-state.yaml; using merge-base approximation ($diff_base)"
      fi
    else
      diff_base=$(git merge-base HEAD origin/main 2>/dev/null || echo "HEAD~5")
      log_warn "cp3: fsm-state.yaml not found; using merge-base approximation ($diff_base)"
    fi
  fi
  # cp4 and cp6 use HEAD~1 (fast mode: no fsm-state by design)

  # Resolve diff using checkpoint-specific range
  local diff_files diff_content
  diff_files=$(git diff --name-only "${diff_base}" HEAD 2>/dev/null || echo "")
  diff_content=$(git diff "${diff_base}" HEAD 2>/dev/null || echo "")

  if [[ -z "$diff_files" ]]; then
    log_warn "No diff for step $step_n (empty diff or initial commit) — defaulting to RUN (conservative)"
    write_output "$output_file" "$step_n" "RUN" "no_diff" "[]" "$checkpoint"
    log_event "$timeline" "prefilter_classification" step="$step_n" classification="RUN" matched_rules="[]" checkpoint="$checkpoint"
    _classify_say RUN "$step_n" no_diff 10
    exit 10
  fi

  # Apply skip_rules first (all files must match for SKIP to trigger)
  local skip_ids
  mapfile -t skip_ids < <(yq -r '.skip_rules[].id' "$RULES_FILE" 2>/dev/null)
  for rule_id in "${skip_ids[@]}"; do
    if matches_skip "$rule_id" "$diff_files"; then
      local matched_json="[\"${rule_id}\"]"
      write_output "$output_file" "$step_n" "SKIP" "$rule_id" "$matched_json" "$checkpoint"
      log_event "$timeline" "prefilter_classification" step="$step_n" classification="SKIP" matched_rules="$matched_json" checkpoint="$checkpoint"
      _classify_say SKIP "$step_n" "$rule_id" 0
      exit 0
    fi
  done

  # Apply fail_rules (conservative bias: any match → FAIL; false positive OK)
  local fail_ids
  mapfile -t fail_ids < <(yq -r '.fail_rules[].id' "$RULES_FILE" 2>/dev/null)
  local matched_fail=()
  for rule_id in "${fail_ids[@]}"; do
    if matches_fail "$rule_id" "$diff_content"; then
      matched_fail+=("$rule_id")
    fi
  done

  if (( ${#matched_fail[@]} > 0 )); then
    local matched_json
    matched_json=$(printf '%s\n' "${matched_fail[@]}" | jq -R . | jq -sc .)
    write_output "$output_file" "$step_n" "FAIL" "${matched_fail[*]}" "$matched_json" "$checkpoint"
    log_event "$timeline" "prefilter_classification" step="$step_n" classification="FAIL" matched_rules="$matched_json" checkpoint="$checkpoint"
    _classify_say FAIL "$step_n" "${matched_fail[*]// /,}" 20
    exit 20
  fi

  # Default: RUN
  write_output "$output_file" "$step_n" "RUN" "default" "[]" "$checkpoint"
  log_event "$timeline" "prefilter_classification" step="$step_n" classification="RUN" matched_rules="[]" checkpoint="$checkpoint"
  _classify_say RUN "$step_n" default 10
  exit 10
}

validate_rule_ids() {
  local all_ids
  mapfile -t all_ids < <(yq -r '(.skip_rules // [] | .[].id), (.fail_rules // [] | .[].id)' "$RULES_FILE" 2>/dev/null)
  for id in "${all_ids[@]}"; do
    [[ "$id" =~ ^[a-z][a-z0-9_]*$ ]] || { log_error "Invalid rule ID: '$id' (must match ^[a-z][a-z0-9_]*$)"; return 1; }
  done
  return 0
}

matches_skip() {
  local rule_id=$1 diff_files=$2
  local pattern match_all
  pattern=$(yq -r ".skip_rules[] | select(.id == \"${rule_id}\") | .pattern" "$RULES_FILE" 2>/dev/null)
  match_all=$(yq -r ".skip_rules[] | select(.id == \"${rule_id}\") | .match_all_files // false" "$RULES_FILE" 2>/dev/null)

  [[ -z "$pattern" ]] && return 1

  if [[ "$match_all" == "true" ]]; then
    # ALL files must match the pattern for skip to apply
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if ! [[ "$f" =~ $pattern ]]; then
        return 1  # at least one file does not match → no skip
      fi
    done <<< "$diff_files"
    return 0  # all files matched
  else
    [[ "$diff_files" =~ $pattern ]]
  fi
}

matches_fail() {
  local rule_id=$1 diff_content=$2
  local pattern
  pattern=$(yq -r ".fail_rules[] | select(.id == \"${rule_id}\") | .pattern" "$RULES_FILE" 2>/dev/null)
  [[ -z "$pattern" ]] && return 1
  # bash ERE via [[ =~ ]] — requires bash 5+ for \b word boundaries (verified in setup)
  [[ "$diff_content" =~ $pattern ]]
}

write_output() {
  local file=$1 step_n=$2 classification=$3 reason=$4 matched_rules=$5 checkpoint=${6:-cp2}
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local verdict
  case "$classification" in
    SKIP) verdict="skip" ;;
    *)    verdict="pending" ;;  # RUN/FAIL — verifier dispatch will overwrite with pass/fail
  esac

  # Emit behavior_trace_required=false for SKIP (trivial diff — no handler tracing needed).
  # For RUN/FAIL the verifier is responsible for emitting behavior_trace fields based on
  # whether the diff matches high-risk patterns (see skills/review-checkpoint-contracts.md).
  local trace_fields=""
  if [[ "$classification" == "SKIP" ]]; then
    trace_fields="checkpoint: ${checkpoint}
behavior_trace_count: 0
behavior_trace_required: false
behavior_trace_skip_reason: \"classification SKIP — ${reason}\""
  else
    trace_fields="checkpoint: ${checkpoint}"
  fi

  mkdir -p "$(dirname "$file")"
  # A COMPLETED report of an earlier iteration (verdict pass|fail, not the
  # pre-filter's own pending/skip) is archived, not overwritten: the fix loop
  # re-classifies, and iteration 1's findings used to vanish before anyone
  # read them (agents #4). Collision-safe name; increment-step still reads
  # the canonical file.
  if [[ -f "$file" ]]; then
    local _old_verdict; _old_verdict="$(grep -m1 -E '^verdict:' "$file" 2>/dev/null | awk '{print tolower($2)}')"
    if [[ "$_old_verdict" == "pass" || "$_old_verdict" == "fail" || "$_old_verdict" == "skip" ]]; then
      local _arch
      _arch="$(mktemp "${file%.md}.iter-$(date -u +%Y%m%dT%H%M%SZ)-XXXX")" \
        || die "prefilter: cannot create an archive name for the previous report ${file} — refusing to overwrite it"
      mv -f "$file" "$_arch" || die "prefilter: could not archive the previous report ${file} → ${_arch}; refusing to overwrite it"
      mv -f "$_arch" "${_arch}.md" 2>/dev/null && _arch="${_arch}.md"
      echo "prefilter: archived the completed report of the previous iteration as $(basename "$_arch")" >&2
    fi
  fi
  cat > "$file" <<EOF
# Verifier output step ${step_n}

_generated_by: aid-pre-filter.sh
_generated_at: ${now}
classification: ${classification}
verdict: ${verdict}
reason: ${reason}
matched_rules: ${matched_rules}
${trace_fields}

## Findings

(populated by verifier dispatch — empty if SKIP)
EOF
}

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

main "$@"
