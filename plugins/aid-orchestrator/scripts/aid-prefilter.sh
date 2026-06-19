#!/usr/bin/env bash
# aid-prefilter.sh — Deterministic CP2 pre-filter classifier.
# Classifies step git diff as SKIP / RUN / FAIL and writes verifier-output-step-N.md.
#
# Exit codes (non-conflicting with bash convention):
#   0  — SKIP  (docs/config only; verifier-output written; no verifier dispatch needed)
#   10 — RUN   (standard code change; code-review verifier should be dispatched)
#   20 — FAIL  (security-sensitive pattern detected; security verifier must be dispatched)
#   1  — error (missing argument, file not found, yq error)
#   2  — malformed rules file
#
# Usage: aid-prefilter.sh classify <step_n> <evidence_dir> [--checkpoint <cp2|cp3|cp4|cp6>]
#
# --checkpoint flag (v2.35+):
#   Controls the git diff range used for classification. Default (no flag) = cp2 behavior.
#   cp2 — HEAD~1..HEAD (step diff, default, backward-compatible)
#   cp3 — base_commit..HEAD (full EPIC diff; base_commit read from fsm-state.yaml if present,
#          falls back to git merge-base HEAD origin/main)
#   cp4 — HEAD~1..HEAD (C+A applied changes are always the last commit)
#   cp6 — HEAD~1..HEAD (advisory; same range as cp2, evaluated separately from FSM flow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${AID_PLUGIN_PATH:-${SCRIPT_DIR}/..}/defaults/pre-filter-rules.yaml"

# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"


main() {
  local cmd="${1:-}"
  [[ -z "$cmd" ]] && { echo "Usage: aid-prefilter.sh classify <step_n> <evidence_dir> [--checkpoint <cp2|cp3|cp4|cp6>]" >&2; exit 1; }
  shift
  case "$cmd" in
    classify) cmd_classify "$@" ;;
    *) die "Unknown command: $cmd. Use: classify" ;;
  esac
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

  # Resolve diff range based on checkpoint (v2.35+).
  # cp2 (default): HEAD~1..HEAD — most recent step commit
  # cp3: base_commit..HEAD — full EPIC diff since run start
  #      base_commit is read from fsm-state.yaml if present; falls back to
  #      git merge-base HEAD origin/main (approximate when fsm-state unavailable)
  # cp4: HEAD~1..HEAD — curator/auditor changes are always the last commit
  # cp6: HEAD~1..HEAD — advisory, same range as cp2
  local diff_base="HEAD~1"
  if [[ "$checkpoint" == "cp3" ]]; then
    # Attempt to read base_commit from fsm-state.yaml in evidence parent dir
    local fsm_state_file="${evidence_dir%/*}/fsm-state.yaml"
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
  # cp4 and cp6 use HEAD~1 (same as cp2 default)

  # Resolve diff using checkpoint-specific range
  local diff_files diff_content
  diff_files=$(git diff --name-only "${diff_base}" HEAD 2>/dev/null || echo "")
  diff_content=$(git diff "${diff_base}" HEAD 2>/dev/null || echo "")

  if [[ -z "$diff_files" ]]; then
    log_warn "No diff for step $step_n (empty diff or initial commit) — defaulting to RUN (conservative)"
    write_output "$output_file" "$step_n" "RUN" "no_diff" "[]" "$checkpoint"
    log_event "$timeline" "prefilter_classification" step="$step_n" classification="RUN" matched_rules="[]" checkpoint="$checkpoint"
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
    exit 20
  fi

  # Default: RUN
  write_output "$output_file" "$step_n" "RUN" "default" "[]" "$checkpoint"
  log_event "$timeline" "prefilter_classification" step="$step_n" classification="RUN" matched_rules="[]" checkpoint="$checkpoint"
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

main "$@"
