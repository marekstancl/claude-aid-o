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
# Usage: aid-prefilter.sh classify <step_n> <evidence_dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${AID_PLUGIN_PATH:-${SCRIPT_DIR}/..}/defaults/pre-filter-rules.yaml"

# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"


main() {
  local cmd="${1:-}"
  [[ -z "$cmd" ]] && { echo "Usage: aid-prefilter.sh classify <step_n> <evidence_dir>" >&2; exit 1; }
  shift
  case "$cmd" in
    classify) cmd_classify "$@" ;;
    *) die "Unknown command: $cmd. Use: classify" ;;
  esac
}

cmd_classify() {
  [[ $# -lt 2 ]] && die "classify requires <step_n> <evidence_dir>"
  local step_n=$1 evidence_dir=$2

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

  # Resolve diff: HEAD~1..HEAD for last commit (most recent step commit)
  local diff_files diff_content
  diff_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
  diff_content=$(git diff HEAD~1 HEAD 2>/dev/null || echo "")

  if [[ -z "$diff_files" ]]; then
    log_warn "No diff for step $step_n (empty diff or initial commit) — defaulting to RUN (conservative)"
    write_output "$output_file" "$step_n" "RUN" "no_diff" "[]"
    log_event "$timeline" "prefilter_classification" step="$step_n" classification="RUN" matched_rules="[]"
    exit 10
  fi

  # Apply skip_rules first (all files must match for SKIP to trigger)
  local skip_ids
  mapfile -t skip_ids < <(yq -r '.skip_rules[].id' "$RULES_FILE" 2>/dev/null)
  for rule_id in "${skip_ids[@]}"; do
    if matches_skip "$rule_id" "$diff_files"; then
      local matched_json="[\"${rule_id}\"]"
      write_output "$output_file" "$step_n" "SKIP" "$rule_id" "$matched_json"
      log_event "$timeline" "prefilter_classification" step="$step_n" classification="SKIP" matched_rules="$matched_json"
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
    write_output "$output_file" "$step_n" "FAIL" "${matched_fail[*]}" "$matched_json"
    log_event "$timeline" "prefilter_classification" step="$step_n" classification="FAIL" matched_rules="$matched_json"
    exit 20
  fi

  # Default: RUN
  write_output "$output_file" "$step_n" "RUN" "default" "[]"
  log_event "$timeline" "prefilter_classification" step="$step_n" classification="RUN" matched_rules="[]"
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
  local file=$1 step_n=$2 classification=$3 reason=$4 matched_rules=$5
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local verdict
  case "$classification" in
    SKIP) verdict="skip" ;;
    *)    verdict="pending" ;;  # RUN/FAIL — verifier dispatch will overwrite with pass/fail
  esac

  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
# Verifier output step ${step_n}

_generated_by: aid-pre-filter.sh@v2.18.0
_generated_at: ${now}
classification: ${classification}
verdict: ${verdict}
reason: ${reason}
matched_rules: ${matched_rules}

## Findings

(populated by verifier dispatch — empty if SKIP)
EOF
}

main "$@"
