#!/usr/bin/env bash
# aid-plan-diff.sh — P037 Phase 2 — Plan AC executable verification
#
# Parses plan.md ## Acceptance Criteria section, runs verification_pattern per AC,
# emits plan-diff.json with per-AC verdict (present|absent).
#
# Usage:
#   aid-plan-diff.sh --plan <path> --evidence-dir <path> --base-commit <sha>
#
# Exit codes:
#   0  — all ACs present (gate pass)
#   1  — ≥1 AC absent (gate fail)
#   2  — graceful skip: Fast Mode (--plan empty or "null") OR plan has no AC section / no verification_pattern blocks
#   10 — input validation error (evidence_dir missing or plan path provided but file not found)
#
# Security note: pattern `cmd:` arguments are author-controlled (plan.md) and trusted
# at same level as plan content itself. eval() is used by design. Do not feed
# user-supplied or external content here — patterns must originate from versioned plan files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

PLUGIN_VERSION="${PLUGIN_VERSION:-v2.20.2}"

usage() {
  cat <<EOF
Usage: aid-plan-diff.sh --plan <path> --evidence-dir <path> --base-commit <sha>

Options:
  --plan <path>           Path to plan.md (e.g., .aid-o/plans/P037-*.md)
  --evidence-dir <path>   Run evidence directory (output written here as plan-diff.json)
  --base-commit <sha>     Git base commit for diff context (recorded in output)
EOF
}

# Parse CLI
PLAN=""; EVIDENCE_DIR=""; BASE_COMMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    --base-commit) BASE_COMMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 10 ;;
  esac
done

# Fast Mode / manual EPIC handling: empty or literal "null" plan_path → graceful skip
if [[ -z "$PLAN" || "$PLAN" == "null" ]]; then
  [[ -z "$EVIDENCE_DIR" ]] && { usage; exit 10; }
  mkdir -p "$EVIDENCE_DIR" 2>/dev/null || true
  GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" \
    --arg ga "$GEN_AT" \
    --arg reason "fast-mode EPIC (plan_path is null in fsm-state.yaml; no plan to verify)" \
    '{
      "_generated_by": $gb,
      "_generated_at": $ga,
      "plan_path": null,
      "base_commit": null,
      "head_commit": null,
      "ac_count": 0,
      "results": [],
      "summary": {"present_count": 0, "absent_count": 0, "skipped_count": 1, "reason": $reason},
      "overall_verdict": "skipped"
    }' > "${EVIDENCE_DIR}/plan-diff.json"
  exit 2
fi

[[ -z "$EVIDENCE_DIR" ]] && { usage; exit 10; }
[[ ! -f "$PLAN" ]] && { echo "Plan not found: $PLAN" >&2; exit 10; }
[[ ! -d "$EVIDENCE_DIR" ]] && { echo "Evidence dir not found: $EVIDENCE_DIR" >&2; exit 10; }
[[ -z "$BASE_COMMIT" ]] && BASE_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

HEAD_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
TIMELINE_FILE="${EVIDENCE_DIR}/timeline.jsonl"
OUTPUT_FILE="${EVIDENCE_DIR}/plan-diff.json"
GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log_event "$TIMELINE_FILE" "plan_diff_start" plan="$PLAN" base_commit="$BASE_COMMIT" head_commit="$HEAD_COMMIT" || true

# Extract AC section + parse verification_pattern blocks
parse_ac_blocks() {
  # NOTE: Uses portable awk (mawk-compatible) — no gensub(). Helper functions
  # extract_label / extract_text / extract_yaml_val use sub() + substr() so the
  # parser works on both gawk and mawk (default awk on Debian).
  #
  # Output field separator is ASCII Unit Separator (0x1F, "\x1f"). We cannot use
  # `|` because cmd: values commonly contain shell pipes which would corrupt
  # downstream `IFS='|' read` splitting and break field alignment.
  awk -v US=$'\x1f' '
    function extract_label(s,   tmp) {
      tmp = s
      sub(/^- \[[ x]\] /, "", tmp)
      sub(/:.*$/, "", tmp)
      return tmp
    }
    function extract_text(s,   tmp) {
      tmp = s
      sub(/^- \[[ x]\] AC[0-9]+: */, "", tmp)
      return tmp
    }
    function extract_text_role(s,   tmp) {
      tmp = s
      sub(/^- \[[ x]\] \[[a-z_]+\] */, "", tmp)
      return tmp
    }
    function extract_yaml_val(s, key,   tmp, prefix) {
      tmp = s
      prefix = ".*" key ":[[:space:]]*"
      sub(prefix, "", tmp)
      # Strip leading quote
      sub(/^"/, "", tmp)
      # Strip trailing quote
      sub(/"[[:space:]]*$/, "", tmp)
      # Strip trailing whitespace
      sub(/[[:space:]]+$/, "", tmp)
      # Unescape YAML double-quoted-scalar escape sequences: \" -> " and
      # \\ -> \. Without this, a cmd value containing embedded double
      # quotes or backslash-escaped single quotes (e.g. verification_pattern
      # shell commands with nested quoting, as used throughout P052-P058
      # own Success Criteria) is later handed to eval still carrying
      # literal backslashes, which corrupts the command actual quoting
      # and produces a bash syntax error (exit 2) or a jq compile error
      # (exit 3) instead of running the intended check, silently reporting
      # absent for a criterion that would otherwise pass. Order matters:
      # protect literal double-backslash behind a placeholder BEFORE
      # unescaping the quote form, so an escaped-backslash-then-escaped-
      # quote sequence is not misread as one combined escape.
      gsub(/\\\\/, "\001", tmp)
      gsub(/\\"/, "\"", tmp)
      gsub(/\001/, "\\", tmp)
      return tmp
    }
    function flush_no_verify(  ) {
      if (ac_label != "" && !ac_flushed) {
        printf "%s%s%s%s%s%s%s%s%s%s%s%s%s\n", \
          ac_label, US, ac_text, US, "no_verification", US, "", US, "", US, "", US, "0"
        ac_flushed=1
      }
    }
    # AC-section flag: turns on at "## Acceptance Criteria" OR "## Success Criteria"
    # (P052-P058-era plans use "Success Criteria" as the heading for the same
    # verification_pattern-bearing bullets) and turns off at the next "## " heading.
    # A start/end range pattern (start = the AC heading; end = a heading whose
    # first letter is not "A") is NOT used here on purpose: a "Success Criteria"
    # heading itself starts with "S", so that not-"A" terminator would match it
    # as an end-of-range marker on the very next occurrence and collapse the
    # whole section to zero AC rows (empirically confirmed 0 AC
    # false-negative). The flag-based form below has no such collision.
    /^## (Acceptance Criteria|Success Criteria)/ { f=1; next }
    /^## / { f=0 }
    f {
      if ($0 ~ /^- \[[ x]\] AC[0-9]+:/ || $0 ~ /^- \[[ x]\] \[[a-z_]+\]/) {
        flush_no_verify()
        ac_label=extract_label($0)
        if ($0 ~ /^- \[[ x]\] AC[0-9]+:/) {
          ac_text=extract_text($0)
        } else {
          ac_text=extract_text_role($0)
        }
        in_yaml=0; ac_flushed=0
        ac_type=""; ac_cmd=""; ac_file=""; ac_regex=""; ac_expected_exit="0"
      }
      if ($0 ~ /^[[:space:]]*```yaml/) { in_yaml=1; next }
      if ($0 ~ /^[[:space:]]*```$/ && in_yaml) {
        in_yaml=0
        if (ac_type != "") {
          printf "%s%s%s%s%s%s%s%s%s%s%s%s%s\n", ac_label, US, ac_text, US, ac_type, US, ac_cmd, US, ac_file, US, ac_regex, US, ac_expected_exit
          ac_flushed=1
        }
        next
      }
      if (in_yaml) {
        if ($0 ~ /type:/)          ac_type=extract_yaml_val($0, "type")
        if ($0 ~ /cmd:/)           ac_cmd=extract_yaml_val($0, "cmd")
        if ($0 ~ /file:/)          ac_file=extract_yaml_val($0, "file")
        if ($0 ~ /regex:/)         ac_regex=extract_yaml_val($0, "regex")
        if ($0 ~ /expected_exit:/) ac_expected_exit=extract_yaml_val($0, "expected_exit")
      }
    }
    END { flush_no_verify() }
  ' "$PLAN"
}

# Run a single verification_pattern, output verdict + evidence.
# Supported types: cmd (exit code), must_not_exist (file absent), must_contain (regex match).
run_pattern() {
  local type=$1 cmd=$2 file=$3 regex=$4 expected_exit=$5

  local start_ms end_ms duration_ms
  start_ms=$(date +%s%3N)

  local verdict evidence
  # Defensive: expected_exit must be an integer. Coerce non-numeric / empty to 0.
  if ! [[ "$expected_exit" =~ ^[0-9]+$ ]]; then
    expected_exit=0
  fi
  case "$type" in
    cmd)
      local actual_exit=0
      eval "$cmd" >/dev/null 2>&1 || actual_exit=$?
      if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        verdict="present"; evidence="exit=$actual_exit"
      else
        verdict="absent"; evidence="exit=$actual_exit (expected $expected_exit)"
      fi
      ;;
    must_not_exist)
      if [[ -e "$file" ]]; then
        verdict="absent"; evidence="file still exists at $file"
      else
        verdict="present"; evidence="file absent"
      fi
      ;;
    must_contain)
      if [[ ! -f "$file" ]]; then
        verdict="absent"; evidence="file not found: $file"
      elif grep -E -q -- "$regex" "$file" 2>/dev/null; then
        verdict="present"; evidence="regex matched in $file"
      else
        verdict="absent"; evidence="regex not found in $file"
      fi
      ;;
    no_verification)
      verdict="skipped"; evidence="no verification_pattern block — prose AC, cannot auto-verify"
      ;;
    *)
      verdict="absent"; evidence="unknown pattern type: $type"
      ;;
  esac

  end_ms=$(date +%s%3N)
  duration_ms=$((end_ms - start_ms))

  # Use ASCII Unit Separator (0x1f) — `evidence` may contain "|" or ":".
  printf '%s\x1f%s\x1f%s\n' "$verdict" "$evidence" "$duration_ms"
}

# Main loop
ac_lines="$(parse_ac_blocks)"
# Count rows containing the Unit Separator delimiter.
ac_count="$(printf '%s' "$ac_lines" | grep -c $'\x1f' || true)"
ac_count="${ac_count:-0}"

if [[ "$ac_count" -eq 0 ]]; then
  # Graceful skip — no AC blocks
  jq -n \
    --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" \
    --arg ga "$GEN_AT" \
    --arg pl "$PLAN" \
    --arg bc "$BASE_COMMIT" \
    --arg hc "$HEAD_COMMIT" \
    '{
      "_generated_by": $gb,
      "_generated_at": $ga,
      "plan_path": $pl,
      "base_commit": $bc,
      "head_commit": $hc,
      "ac_count": 0,
      "results": [],
      "summary": {"present_count": 0, "absent_count": 0, "skipped_count": 1},
      "overall_verdict": "skipped"
    }' > "$OUTPUT_FILE"
  log_event "$TIMELINE_FILE" "plan_diff_complete" verdict="skipped" ac_count="0" || true
  exit 2
fi

present_count=0; absent_count=0; skipped_count=0
# Collect per-AC NDJSON lines for batched slurp (avoids O(n) growing-payload
# re-parse per AC — measurable at 44+ ACs per /simplify efficiency review).
ac_result_lines=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Split on ASCII Unit Separator (0x1f) — cmd: values often contain | so we
  # cannot use that as field delimiter (would corrupt expected_exit, causing
  # `[[ N -eq <garbage> ]]` arithmetic failure under set -u).
  IFS=$'\x1f' read -r ac_label ac_text pat_type cmd file regex expected_exit <<< "$line"

  IFS=$'\x1f' read -r verdict evidence duration_ms <<< "$(run_pattern "$pat_type" "$cmd" "$file" "$regex" "$expected_exit")"

  [[ "$verdict" == "present" ]] && present_count=$((present_count + 1))
  [[ "$verdict" == "absent"  ]] && absent_count=$((absent_count + 1))
  [[ "$verdict" == "skipped" ]] && skipped_count=$((skipped_count + 1))

  # NOTE: jq reserves `label` as a keyword (label/break syntax), so we pass it
  # as $lbl. Same for `verdict` — rename to $vrd defensively.
  ac_result_lines+=("$(jq -nc \
    --arg lbl "$ac_label" \
    --arg text "$ac_text" \
    --arg ptype "$pat_type" \
    --arg vrd "$verdict" \
    --arg evidence "$evidence" \
    --argjson dur "$duration_ms" \
    '{ac_label: $lbl, ac_text: $text, pattern_type: $ptype, verdict: $vrd, evidence: $evidence, duration_ms: $dur}')")
done <<< "$ac_lines"

# Single jq slurp builds final results array — O(1) jq invocation vs O(n).
if (( ${#ac_result_lines[@]} == 0 )); then
  results_json="[]"
else
  results_json=$(printf '%s\n' "${ac_result_lines[@]}" | jq -sc '.')
fi

overall="pass"
[[ "$absent_count" -gt 0 ]] && overall="fail"
[[ "$overall" == "pass" && "$skipped_count" -gt 0 && "$present_count" -eq 0 ]] && overall="partial"

jq -n \
  --arg gb "aid-plan-diff.sh@${PLUGIN_VERSION}" \
  --arg ga "$GEN_AT" \
  --arg pl "$PLAN" \
  --arg bc "$BASE_COMMIT" \
  --arg hc "$HEAD_COMMIT" \
  --argjson cnt "$ac_count" \
  --argjson res "$results_json" \
  --argjson pcnt "$present_count" \
  --argjson acnt "$absent_count" \
  --argjson scnt "$skipped_count" \
  --arg ov "$overall" \
  '{
    "_generated_by": $gb,
    "_generated_at": $ga,
    "plan_path": $pl,
    "base_commit": $bc,
    "head_commit": $hc,
    "ac_count": $cnt,
    "results": $res,
    "summary": {"present_count": $pcnt, "absent_count": $acnt, "skipped_count": $scnt},
    "overall_verdict": $ov
  }' > "$OUTPUT_FILE"

log_event "$TIMELINE_FILE" "plan_diff_complete" verdict="$overall" ac_count="$ac_count" absent_count="$absent_count" || true

[[ "$absent_count" -gt 0 ]] && exit 1
exit 0
