#!/usr/bin/env bash
# aid-e10-preflight.sh — E10's bookkeeping hygiene gate (P062 Step 1, D7).
#
# E10 measures how well the control stack catches defects. It must not measure a
# messy bookkeeping layer and attribute the mess to the controls, so this runs
# FIRST and refuses to let calibration proceed over known-stale bookkeeping.
#
# Usage:
#   aid-e10-preflight.sh [--project-root <path>] [--out <file>]
#                        [--exclude <class>:<reason>]...
#
#   --exclude   PM risk acceptance for ONE class, e.g.
#               --exclude reports_stale:"P080 reports are private by policy"
#               The reason is mandatory and must be >= 20 characters. An
#               excluded class is reported as `excluded`, NEVER as clean.
#
# Exit: 0 = every class clean or explicitly excluded; 1 = at least one dirty
#       class with no exclusion; 2 = usage/environment error.
#
# WHY THIS SCRIPT IS THIN, AND MUST STAY THIN
#   Three of its four classes are already implemented by
#   aid-plan-close-check.sh — it was written for exactly this family of
#   defects (untracked/stale reports, DONE-with-pending steps, queue/active
#   claiming a merge that already happened). Reimplementing them here would
#   have produced a second copy that drifts from the first, and the two would
#   then disagree in front of the PM. This script therefore CONSUMES that one
#   through its `--json` mode and adds only what E10 needs on top: a sweep over
#   every plan rather than one, the PM exclusion mechanism, and the verdict
#   artefact. If a check needs fixing, it gets fixed there, once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOSE_CHECK="${SCRIPT_DIR}/aid-plan-close-check.sh"

PROJECT_ROOT="$(pwd)"
OUT_FILE=""
declare -a EXCLUSIONS=()

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || usage; PROJECT_ROOT="$2"; shift 2 ;;
    --out)          [[ $# -ge 2 ]] || usage; OUT_FILE="$2";     shift 2 ;;
    --exclude)      [[ $# -ge 2 ]] || usage; EXCLUSIONS+=("$2"); shift 2 ;;
    -h|--help)      usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
[[ -f "$CLOSE_CHECK" ]] || { echo "ERROR: aid-plan-close-check.sh not found at ${CLOSE_CHECK}" >&2; exit 2; }
cd "$PROJECT_ROOT" || { echo "ERROR: cannot enter project root: ${PROJECT_ROOT}" >&2; exit 2; }
[[ -d .aid-o ]] || { echo "ERROR: no .aid-o workspace in ${PROJECT_ROOT}" >&2; exit 2; }

OUT_FILE="${OUT_FILE:-.aid-o/work/evidence/P062/e10/e10-preflight.json}"

# ── the four classes ────────────────────────────────────────────────────────
#
# Each maps to the close-check ids that decide it. `audit_log_self_block` maps
# to NOTHING on purpose — see its grounding note below.
_checks_for_class() {
  case "$1" in
    reports_stale)        echo "check1 check2" ;;
    steps_pending_at_done) echo "check3" ;;
    queue_active_stale)   echo "check4" ;;
    audit_log_self_block) echo "" ;;
    *) return 1 ;;
  esac
}

# GROUNDED 2026-08-15, and the answer is that this class is NOT LIVE.
#
# The plan asked for `aid-fsm init --force` self-blocking on the audit log it
# had just written, and required grounding before any check was built. The
# guard at aid-fsm.sh:4901 filters its `git status` through
# aid_ancillary_filter_porcelain --mode legacy4, and that mode's list carries
# `.aid-o/work/audit-log.jsonl` (lib/aid-ancillary.sh:34) precisely so the
# force override it writes cannot dirty its own tree. The exclusion's own
# comment describes this exact scenario.
#
# So there is no defect to detect. The class is reported `not_grounded` with
# this citation rather than fabricated into a check that can never fire — a
# check that cannot fail is indistinguishable from one that is not wired.
_AUDIT_LOG_NOTE="not a live defect at this HEAD: aid-fsm.sh:4901 filters the init dirty guard through aid_ancillary_filter_porcelain --mode legacy4, whose list carries .aid-o/work/audit-log.jsonl (lib/aid-ancillary.sh:34) so init --force cannot self-block on the entry it just wrote"

# ── PM exclusions ───────────────────────────────────────────────────────────
declare -A EXCLUDED_REASON=()
for e in "${EXCLUSIONS[@]+"${EXCLUSIONS[@]}"}"; do
  cls="${e%%:*}"; reason="${e#*:}"
  if [[ "$cls" == "$e" || -z "$reason" ]]; then
    echo "ERROR: --exclude needs <class>:<reason>, got: ${e}" >&2; exit 2
  fi
  if ! _checks_for_class "$cls" >/dev/null 2>&1; then
    echo "ERROR: unknown class in --exclude: ${cls}" >&2; exit 2
  fi
  if (( ${#reason} < 20 )); then
    echo "ERROR: exclusion reason for '${cls}' is ${#reason} chars; at least 20 required — an exclusion is PM risk acceptance and must say why" >&2
    exit 2
  fi
  EXCLUDED_REASON["$cls"]="$reason"
done

# ── run close-check once per plan that has evidence ─────────────────────────
mapfile -t PLANS < <(
  ls -1 .aid-o/plans/ 2>/dev/null \
    | sed -n 's/^\(P[0-9]\{3\}\)-.*\.md$/\1/p' | sort -u
)
if (( ${#PLANS[@]} == 0 )); then
  echo "ERROR: no plans found under .aid-o/plans/ — nothing to check" >&2; exit 2
fi

all_results="[]"
for plan in "${PLANS[@]}"; do
  out=""
  # A plan whose check cannot produce usable JSON is NOT treated as clean: its
  # failure is recorded so the class it belonged to cannot come out green by
  # silence.
  #
  # The JSON is validated on EVERY path, not only when the exit code is
  # non-zero (cross-model review, 2026-08-15). close-check exits 1 for ordinary
  # blocking findings — a perfectly good run — and could exit 0 while emitting
  # nothing usable; the earlier version only looked at the output when the exit
  # was non-zero, so an exit-0-with-garbage fell through to `--argjson` below
  # and killed the whole sweep under `set -e`, producing no verdict artefact at
  # all. Exit code and parseability are separate questions and are asked
  # separately.
  out="$(bash "$CLOSE_CHECK" "$plan" --json 2>/dev/null || true)"
  if [[ -z "$out" ]] || ! jq -e 'type == "object" and has("results")' >/dev/null 2>&1 <<<"$out"; then
    all_results="$(jq -c --arg p "$plan" \
      '. + [{plan_id:$p, status:"fail", check:"unrunnable", message:"aid-plan-close-check.sh produced no usable JSON for this plan"}]' \
      <<<"$all_results")"
    continue
  fi
  all_results="$(jq -c --argjson r "$out" \
    '. + ($r.results | map(. + {plan_id: $r.plan_id}))' <<<"$all_results")"
done

# ── decide each class ───────────────────────────────────────────────────────
classes_json="[]"
overall_rc=0
for cls in reports_stale steps_pending_at_done queue_active_stale audit_log_self_block; do
  ids="$(_checks_for_class "$cls")"
  reason="${EXCLUDED_REASON[$cls]:-}"

  if [[ "$cls" == "audit_log_self_block" ]]; then
    classes_json="$(jq -c --arg c "$cls" --arg n "$_AUDIT_LOG_NOTE" \
      '. + [{class:$c, status:"not_grounded", note:$n, failures:[]}]' <<<"$classes_json")"
    continue
  fi

  failures="$(jq -c --arg ids "$ids" \
    '[ .[] | select(.status == "fail") | select(.check as $c | ($ids | split(" ")) | index($c)) ]' \
    <<<"$all_results")"
  n="$(jq -r 'length' <<<"$failures")"

  if (( n == 0 )); then
    status="clean"
  elif [[ -n "$reason" ]]; then
    status="excluded"
  else
    status="dirty"; overall_rc=1
  fi

  classes_json="$(jq -c --arg c "$cls" --arg s "$status" --arg r "$reason" --argjson f "$failures" \
    '. + [{class:$c, status:$s, failures:$f} + (if $r == "" then {} else {exclusion_reason:$r} end)]' \
    <<<"$classes_json")"
done

# A close-check that could not RUN is not a close-check that found nothing.
# Its plan contributes no rows, so every class it would have decided came out
# `clean` by silence — the exact shape of the failure this whole gate exists to
# refuse. It gets its own verdict, because "we found no mess" and "we could not
# look" are different facts and only one of them is reassuring.
unrunnable="$(jq -c '[ .[] | select(.check == "unrunnable") ]' <<<"$all_results")"
n_unrunnable="$(jq -r 'length' <<<"$unrunnable")"

verdict="clean"
if (( n_unrunnable > 0 )); then
  verdict="unproven"; overall_rc=1
elif (( overall_rc != 0 )); then
  verdict="dirty"
elif jq -e 'any(.[]; .status == "excluded")' >/dev/null <<<"$classes_json"; then
  verdict="excluded_by_pm"
fi

mkdir -p "$(dirname "$OUT_FILE")"
jq -n \
  --arg verdict "$verdict" \
  --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  --argjson checked "$classes_json" \
  --argjson unrunnable "$unrunnable" \
  '{schema_version: "aid-2.0",
    artifact_type: "e10_preflight",
    generated_by: "aid-e10-preflight.sh",
    head: $head,
    verdict: $verdict,
    checked: $checked,
    unrunnable: $unrunnable,
    exclusions: [ $checked[] | select(.status == "excluded")
                  | {item: .class, reason: .exclusion_reason} ]}' > "$OUT_FILE"

echo "aid-e10-preflight: verdict=${verdict} → ${OUT_FILE}"
jq -r '.checked[] | "  \(.status | ascii_upcase)  \(.class)\(if (.failures|length) > 0 then " (\(.failures|length) failing)" else "" end)"' "$OUT_FILE"
jq -r '.unrunnable[] | "  UNRUNNABLE  plan \(.plan_id) — \(.message)"' "$OUT_FILE"
exit "$overall_rc"
