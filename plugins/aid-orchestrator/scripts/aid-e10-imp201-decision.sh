#!/usr/bin/env bash
# aid-e10-imp201-decision.sh — records E10's IMP-201 disposition (P062 Step 3).
#
# Usage: aid-e10-imp201-decision.sh [--project-root <path>] [--out <file>]
#
# Exit: 0 = decision written; 2 = usage/environment error.
#
# WHY THIS IS DERIVED AND NOT A CHECKED-IN ANSWER
#   The disposition is "fixed" or "observe_hold", and the difference is a fact
#   about the CODE, not an opinion: IMP-201 is closed exactly when the D4
#   freshness classifier is shared, so that aid-release-policy.sh's head_match
#   path adjudicates a trailing cosmetic commit the same way aid-fsm.sh's CP3
#   check already does. A hand-written decision file would keep saying
#   `observe_hold` for a year after someone closed it, or — far worse — keep
#   saying `fixed` after a refactor removed the sharing. So the disposition is
#   READ OFF the repository every time, and the policy value is read from the
#   policy file rather than restated here.
#
#   Adjudicated 2026-08-15 (cross-model, escalated per PM instruction): HOLD.
#   Extracting the classifier means surgery on a blocking precondition inside
#   aid-fsm.sh and widening a permissive exception on a release gate. That gap
#   should PREVENT a promotion rather than travel inside one. What it costs is
#   recorded, not hidden: C4 freshness cannot be promoted to blocking for the
#   trailing-commit class in E10.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || { echo "--project-root needs a path" >&2; exit 2; }; PROJECT_ROOT="$2"; shift 2 ;;
    --out)          [[ $# -ge 2 ]] || { echo "--out needs a path" >&2; exit 2; };          OUT_FILE="$2";     shift 2 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
cd "$PROJECT_ROOT" || { echo "ERROR: cannot enter ${PROJECT_ROOT}" >&2; exit 2; }
OUT_FILE="${OUT_FILE:-.aid-o/work/evidence/P062/e10/imp201-decision.json}"

POLICY="${RELEASE_DECISION_POLICY:-plugins/aid-orchestrator/defaults/policies/release-decision-policy.yaml}"
RELEASE_POLICY_SH="plugins/aid-orchestrator/scripts/aid-release-policy.sh"

# ── is IMP-201 closed? ──────────────────────────────────────────────────────
# Closed means aid-release-policy.sh's head_match path consults the SHARED D4
# classifier. The marker is that function's name; a private re-implementation
# deliberately does not count, because two copies of this classifier is the
# defect P084 already recorded once.
shared_classifier="aid_freshness_exception_applies"
fixed=false
if [[ -f "$RELEASE_POLICY_SH" ]] && grep -q "$shared_classifier" "$RELEASE_POLICY_SH" 2>/dev/null; then
  fixed=true
fi

enforcement="unknown"
if [[ -f "$POLICY" ]] && command -v yq >/dev/null 2>&1; then
  enforcement="$(yq -r '.evidence_pack_freshness_policy // "unknown"' "$POLICY" 2>/dev/null || echo unknown)"
fi

if [[ "$fixed" == "true" ]]; then
  decision="fixed"
  reason="the shared D4 freshness classifier (${shared_classifier}) is consulted by aid-release-policy.sh, so the trailing-commit class is adjudicated identically on both sides"
  covered=true
else
  decision="observe_hold"
  reason="IMP-201 deliberately NOT fixed under E10 (cross-model adjudication 2026-08-15): the fix means surgery on a blocking precondition in aid-fsm.sh and widens a permissive exception on a release gate, which should prevent a promotion rather than ride inside one"
  covered=false
fi

mkdir -p "$(dirname "$OUT_FILE")"
jq -n \
  --arg decision "$decision" \
  --arg reason "$reason" \
  --argjson covered "$covered" \
  --arg enforcement "$enforcement" \
  --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  '{schema_version: "aid-2.0",
    artifact_type: "imp201_decision",
    generated_by: "aid-e10-imp201-decision.sh",
    head: $head,
    decision: $decision,
    reason: $reason,
    trailing_commit_case_covered: $covered,
    c4_freshness_enforcement: $enforcement,
    promotion_consequence: (if $decision == "observe_hold"
      then "C4 freshness must NOT be promoted to blocking for the trailing-commit class; the decision table records an explicit non-promotion with IMP-201 as the closure condition"
      else "C4 freshness is eligible for promotion on this class, subject to the remaining gates" end)}' > "$OUT_FILE"

# An observe_hold whose policy is NOT observe is a contradiction: the record
# would claim a hold that the policy is not holding. Refuse it rather than
# write a decision nobody is honouring.
if [[ "$decision" == "observe_hold" && "$enforcement" != "observe" ]]; then
  echo "ERROR: decision is observe_hold but evidence_pack_freshness_policy is '${enforcement}' — the hold is not actually in force" >&2
  exit 2
fi

echo "aid-e10-imp201-decision: ${decision} (policy=${enforcement}) → ${OUT_FILE}"
