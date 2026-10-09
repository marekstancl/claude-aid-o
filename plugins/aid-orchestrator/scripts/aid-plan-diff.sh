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
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"   # aid_state_path — a relative evidence dir lives in the state root
# shellcheck source=lib/aid-verification-pattern.sh
source "${SCRIPT_DIR}/lib/aid-verification-pattern.sh"

PLUGIN_VERSION="${PLUGIN_VERSION:-v2.67.0}"

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

# A relative evidence dir (.aid-o/work/evidence/...) names the state root's, also when this
# runs inside a plan worktree, where .aid-o does not exist (P100 Step 7).
[[ -n "$EVIDENCE_DIR" && "$EVIDENCE_DIR" != /* ]] && EVIDENCE_DIR="$(aid_state_path "$EVIDENCE_DIR")"

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
      "summary": {"present_count": 0, "absent_count": 0, "skipped_count": 1, "reason": $reason,
                  "unmeasured": {"summary_prose": 0, "summary_unparsed": 0, "step_bullets": 0}},
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

# Per-AC command timeout (seconds). A hanging or pathologically slow AC
# verification_pattern must not wedge the whole DONE-review — it is killed after
# this budget and reported absent(reason=timeout). Override via
# AID_PLAN_DIFF_AC_TIMEOUT for a plan with a legitimately long (but bounded) AC.
# Default 120s is ample for grep/jq/git checks and small bats --filter subsets; a
# full unbounded test suite inside a single AC is an anti-pattern — bound it or
# raise this (added 2026-07-10; matches aid-run-gates.sh's per-gate timeout model).
AC_CMD_TIMEOUT="${AID_PLAN_DIFF_AC_TIMEOUT:-120}"

log_event "$TIMELINE_FILE" "plan_diff_start" plan="$PLAN" base_commit="$BASE_COMMIT" head_commit="$HEAD_COMMIT" || true

# Extract AC section + parse verification_pattern blocks. The parser lives in
# lib/aid-verification-pattern.sh (P109): the plan check, the brief lint and the
# plan lint read criteria through the same function this runner does.
parse_ac_blocks() {
  _aid_vp_parse_ac "$PLAN" "Acceptance Criteria|Success Criteria"
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
      # Per-AC timeout + process isolation. `timeout … bash -c` runs the AC cmd in
      # a SEPARATE process so (a) a hanging or pathologically slow AC cannot wedge
      # the whole DONE-review — timeout kills it after AC_CMD_TIMEOUT and we report
      # absent(reason=timeout); and (b) FATAL bash errors (set -u unbound-var
      # expansion aborts) stay contained in the child and remain catchable via the
      # exit code — the guarantee the old ( eval ) sub-subshell gave, now also
      # kill-able (PM fix 2026-07-08; per-AC timeout added 2026-07-10).
      # </dev/null: a command that reads stdin would eat the remaining criteria of
      # the loop's here-string (the same guard run_gate carries).
      timeout "$AC_CMD_TIMEOUT" bash -c "$cmd" </dev/null >/dev/null 2>&1 || actual_exit=$?
      if [[ "$actual_exit" -eq 124 && "$expected_exit" -ne 124 ]]; then
        verdict="absent"; evidence="timeout after ${AC_CMD_TIMEOUT}s (reason=timeout)"
      elif [[ "$actual_exit" -eq "$expected_exit" ]]; then
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
      elif grep -Eiq -- "$regex" "$file" 2>/dev/null; then
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

# What this gate does NOT measure, counted so the plan close can say it aloud
# (2.114.0, agents P010: 13 summary criteria measured against ~57 step-level
# bullets the parser never saw; `status: pass` with `criteria: []` and nobody
# noticed until the final review raised it four rounds running):
#   summary_prose    — summary criteria parsed (AC<N>:/[role]) with no verification_pattern
#   summary_unparsed — bullets under the summary heading the parser does not take (no AC<N>: mark)
#   step_bullets     — bullets under a step's **Acceptance Criteria:** (never measured here)
summary_prose="$(printf '%s\n' "$ac_lines" | awk -F $'\x1f' 'NF > 2 && $3 == "no_verification" {n++} END {print n+0}')"
read -r summary_unparsed step_bullets < <(awk '
  /^## (Acceptance Criteria|Success Criteria)/ { sec=1; step=0; next }
  /^## /  { sec=0 }
  /^### Step [0-9]+/ { step=1; sec=0; inac=0; next }
  sec && /^- / && $0 !~ /^- \[[ x]\] AC[0-9]+:/ && $0 !~ /^- \[[ x]\] \[[a-z_]+\]/ { u++ }
  step && /^\*\*Acceptance Criteria:\*\*/ { inac=1; next }
  step && inac && /^- / { b++; next }
  step && inac && (/^\*\*/ || /^$/ || /^#/) { inac=0 }
  END { printf "%d %d\n", u+0, b+0 }' "$PLAN")
unmeasured_json="$(jq -nc --argjson p "$summary_prose" --argjson u "$summary_unparsed" --argjson b "$step_bullets" '{summary_prose: $p, summary_unparsed: $u, step_bullets: $b}')"

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
      "summary": {"present_count": 0, "absent_count": 0, "skipped_count": 1, "unmeasured": $um},
      "overall_verdict": "skipped"
    }' --argjson um "$unmeasured_json" > "$OUTPUT_FILE"
  log_event "$TIMELINE_FILE" "plan_diff_complete" verdict="skipped" ac_count="0" step_bullets_unmeasured="$step_bullets" || true
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

  # Runner-crash belt: if run_pattern died mid-way (empty fields), record a
  # skipped row instead of passing invalid JSON to --argjson (PM fix 2026-07-08).
  if ! [[ "$duration_ms" =~ ^[0-9]+$ ]]; then
    verdict="skipped"; evidence="runner_error: pattern produced no result"; duration_ms=0
    skipped_count=$((skipped_count + 1))
  fi

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

# `pass` means EVERY criterion was checked and found. A skipped criterion (prose,
# or a pattern that produced no result) makes the run `partial`, however many
# others passed: ACTA P024 read `pass` with 4 of 9 criteria never looked at. A
# criterion with no result row at all is a broken run, never a pass.
overall="pass"
[[ "$skipped_count" -gt 0 ]] && overall="partial"
missing_rows=$(( ac_count - ${#ac_result_lines[@]} ))
if (( missing_rows > 0 )); then
  echo "ERROR: aid-plan-diff: ${missing_rows} of ${ac_count} acceptance criteria produced no result row" >&2
  absent_count=$(( absent_count + missing_rows ))
fi
[[ "$absent_count" -gt 0 ]] && overall="fail"

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
    "summary": {"present_count": $pcnt, "absent_count": $acnt, "skipped_count": $scnt, "unmeasured": $um},
    "overall_verdict": $ov
  }' --argjson um "$unmeasured_json" > "$OUTPUT_FILE"

log_event "$TIMELINE_FILE" "plan_diff_complete" verdict="$overall" ac_count="$ac_count" absent_count="$absent_count" || true

[[ "$absent_count" -gt 0 ]] && exit 1
exit 0
