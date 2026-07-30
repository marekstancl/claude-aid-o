#!/usr/bin/env bash
# aid-test-audit-chat-summary.sh — P066 Step 15.
#
# Renders the mandatory 5-part plain-language chat message from
# consolidated-findings.json: (1) verdict, (2) up to 5 evidenced reasons —
# one per top finding, NEVER fabricated/padded to reach a minimum count
# (Codex review: a "3-5" phrasing read as a hard floor is dishonest for a
# sparse, 1-2-finding result — a real audit with 1 genuine finding gets
# exactly 1 real reason, not 2 invented ones), (3) what changed, (4) one
# plain-language next action, (5) residual risk/PM-decision-needed.
# Verdict classification is a PURE FUNCTION of consolidated-findings.json's
# severity/recommendation fields — reproducible, never an LLM judgment call.
#
# Testability boundary, stated explicitly: this renderer's OUTPUT TEXT is
# ordinary, deterministic code — fully Bats-testable. The controller's act of
# presenting that text as the session's actual final turn is a live,
# session-level behavior verified once at release (Step 24 Part B), never
# claimed as covered by this script's own test suite.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_TACS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-test-adapter-contract.sh
source "${_TACS_LIB_DIR}/aid-test-adapter-contract.sh"
# shellcheck source=aid-test-audit-write-plan-bridge.sh
source "${_TACS_LIB_DIR}/aid-test-audit-write-plan-bridge.sh"
_TACS_FINDINGS_SCHEMA="${_TACS_LIB_DIR}/../../defaults/schemas/test-audit-consolidated-findings.schema.json"

# _tacs_classify_verdict <findings_json>
#   Pure function: "remediation recommended" if any Medium+ finding
#   recommends fix/split/merge/remove/quarantine; else "needs measurement"
#   if any finding recommends "measure" (inconclusive without real data);
#   else "clean". A static-mode-only run can still reach "remediation
#   recommended" from static analysis alone.
_tacs_classify_verdict() {
  local findings_json="$1"
  local has_actionable has_measure
  has_actionable="$(jq -r '
    [.[] | select(.severity != "low" and (.recommendation | IN("fix","split","merge","remove","quarantine")))] | length > 0
  ' <<<"$findings_json")"
  if [[ "$has_actionable" == "true" ]]; then
    echo "remediation recommended"
    return 0
  fi
  has_measure="$(jq -r '[.[] | select(.recommendation == "measure")] | length > 0' <<<"$findings_json")"
  if [[ "$has_measure" == "true" ]]; then
    echo "needs measurement"
    return 0
  fi
  echo "clean"
}

# aid_test_audit_render_chat_summary <consolidated_findings_path> [changed_text]
#   Echoes the 5-part message. A missing/malformed findings file produces an
#   explicit "audit did not complete cleanly" statement, never a fabricated
#   "clean" verdict.
aid_test_audit_render_chat_summary() {
  local findings_path="$1" changed_text="${2:-nothing (no separately approved step ran)}"

  if [[ ! -f "$findings_path" ]]; then
    echo "**Audit did not complete cleanly** — no consolidated findings file was produced ($findings_path missing). This is not a clean result; something failed before consolidation."
    return 1
  fi

  local whole_doc
  whole_doc="$(jq -e '.' "$findings_path" 2>/dev/null)" || {
    echo "**Audit did not complete cleanly** — $findings_path is not valid JSON. This is not a clean result."
    return 1
  }

  # Schema-validate the WHOLE document before classification — Codex
  # review: a syntactically-valid-JSON-but-wrong-shape file (e.g.
  # findings: {} instead of an array) previously slipped past a bare
  # `.findings` extraction and was silently treated as empty, producing a
  # fabricated "clean" verdict over a corrupted/incompatible consolidation
  # output instead of failing closed.
  adapter_validate_schema "$_TACS_FINDINGS_SCHEMA" "$whole_doc" || {
    echo "**Audit did not complete cleanly** — $findings_path failed schema validation (test-audit-consolidated-findings.schema.json). This is not a clean result."
    return 1
  }

  local findings_json
  findings_json="$(jq -c '.findings' <<<"$whole_doc")"

  local verdict
  verdict="$(_tacs_classify_verdict "$findings_json")"

  # 3-5 evidenced reasons: top findings by severity (critical>high>medium>low), then finding_id.
  local reasons_text
  reasons_text="$(jq -r '
    def sev_rank: {"critical":0,"high":1,"medium":2,"low":3}[.severity] // 4;
    [.[]] | sort_by([sev_rank, .finding_id]) | .[0:5] | to_entries |
    map("\(.key + 1). [\(.value.severity)] \(.value.category) on `\(.value.run_unit_id)` → \(.value.recommendation) (evidence: \(.value.evidence_refs | join(", ")))") |
    join("\n")
  ' <<<"$findings_json")"
  [[ -n "$reasons_text" ]] || reasons_text="(no findings to report)"

  local next_action
  case "$verdict" in
    "remediation recommended")
      next_action="Reply \"vytvoř plán oprav\" (or run \`--write-plan\`) to generate a remediation plan from this audit's findings."
      ;;
    "needs measurement")
      next_action="Re-run with \`--mode measure\` (or \`--mode full\`) to get real measured data before deciding anything further."
      ;;
    *)
      next_action="No action needed."
      ;;
  esac

  local has_conflict residual_risk
  has_conflict="$(jq -r '[.[] | select(.unresolved_conflict == true)] | length > 0' <<<"$findings_json")"
  if [[ "$has_conflict" == "true" ]]; then
    residual_risk="One or more findings disagree with each other (unresolved_conflict) — this needs a PM decision on which to trust."
  else
    residual_risk="No PM decision required."
  fi

  # Persist the durable record for the same-conversation continuation /
  # --write-plan bridge (Codex review: this renderer previously had no
  # production caller of aid_test_audit_write_plan_bridge_persist, so a
  # normal completed audit never created durable-record.json and the
  # handoff could never be reached no matter how the audit concluded).
  local audit_id
  audit_id="$(jq -r '.audit_id' <<<"$whole_doc")"
  aid_test_audit_write_plan_bridge_persist "$(dirname "$findings_path")" "$audit_id" "$verdict" "$next_action"

  cat <<EOF
**Verdict:** ${verdict}

**Reasons:**
${reasons_text}

**Changed:** ${changed_text}

**Next action:** ${next_action}

**Residual risk / PM decision:** ${residual_risk}
EOF
}
