#!/usr/bin/env bash
# aid-audit-mode.sh — deterministic C3 audit dispatch-mode resolver (IMP-177).
#
# Resolves whether the DONE-review Auditor dispatch should run in `c3`
# (independent audit) or `legacy_health` mode for a given run. The decision is
# a pure function of the run's review-profile.json risk_profile and the
# c3-audit-policy.yaml c3_required flag for that profile — no LLM judgment.
# pipeline.md's DONE review sub-phase consumes this so mode selection is a
# mechanical substrate, not prose reasoning (closes the IMP-177 mode-selection
# gap).
#
# Usage:
#   aid-audit-mode.sh <evidence_dir>
#     <evidence_dir> — run evidence dir that contains review-profile.json
#
# Policy path resolution (mirrors DELIVERY_GATE_POLICY / C3_AUDIT_POLICY seam):
#   $C3_AUDIT_POLICY (test/CI override) → else
#   ${AID_PLUGIN_PATH}/defaults/policies/c3-audit-policy.yaml (default)
#
# Output (stdout): exactly one of "c3" | "legacy_health"
# Exit codes:
#   0 — mode resolved from a present review-profile.json
#   2 — usage error (missing <evidence_dir>)
#   3 — review-profile.json missing/unreadable → emits "c3" (fail-closed
#       direction) + a stderr warning so callers can distinguish this from a
#       profile that genuinely resolved to c3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Named constants (GEN-007: no inline magic strings for config-like values).
# Not `readonly` so the file stays safe to source more than once in a test shell.
C3_MODE_INDEPENDENT="c3"
C3_MODE_LEGACY="legacy_health"
DEFAULT_C3_POLICY="${PLUGIN_ROOT}/defaults/policies/c3-audit-policy.yaml"

# resolve_mode — echo the audit mode for a run and return its exit code.
# Args: $1 = evidence_dir. Fail-closed everywhere: any ambiguity in reading the
# profile or policy resolves toward c3 (never a silent legacy_health downgrade).
resolve_mode() {
  local evidence_dir="${1:-}"
  [[ -n "$evidence_dir" ]] || { echo "usage: aid-audit-mode.sh <evidence_dir>" >&2; return 2; }

  local profile_file="${evidence_dir}/review-profile.json"
  local policy_file="${C3_AUDIT_POLICY:-$DEFAULT_C3_POLICY}"

  # Missing profile → fail-closed direction: request c3 but flag via exit 3 so a
  # caller can tell "no profile at all" apart from a resolved-c3.
  if [[ ! -f "$profile_file" ]]; then
    echo "[WARN] aid-audit-mode: review-profile.json not found in ${evidence_dir} — defaulting to ${C3_MODE_INDEPENDENT} (fail-closed)" >&2
    echo "$C3_MODE_INDEPENDENT"
    return 3
  fi

  # Resolve risk_profile (fail-closed to unverifiable on any read problem).
  local risk_profile="unverifiable"
  if command -v jq >/dev/null 2>&1; then
    local rp rp_ec=0
    rp=$(jq -r '.review_profile.risk_profile // "unverifiable"' "$profile_file" 2>/dev/null) || rp_ec=$?
    if [[ $rp_ec -eq 0 && -n "$rp" && "$rp" != "null" ]]; then
      risk_profile="$rp"
    fi
  fi

  # Validate risk_profile against closed enum to prevent injection (fail-closed to
  # unverifiable on unknown value). Mirrors aid-fsm.sh's cmd_done_advance guard.
  case "$risk_profile" in
    docs_trivial|low|medium|high|unverifiable) ;;
    *) risk_profile="unverifiable" ;;  # unknown/malformed → fail-closed
  esac

  # Look up c3_required for this profile. Fail-closed: any ambiguity → c3.
  local c3_required="false"
  if [[ -f "$policy_file" ]] && command -v yq >/dev/null 2>&1; then
    # has() distinguishes "key absent" (docs_trivial/low/medium → C3 not
    # required) from "key present but false"; a bare read cannot.
    local has_key has_ec=0
    has_key=$(yq -r "(.risk_profiles | has(\"$risk_profile\")) and (.risk_profiles[\"$risk_profile\"] | has(\"c3_required\"))" "$policy_file" 2>/dev/null) || has_ec=$?
    if [[ $has_ec -eq 0 && "$has_key" == "true" ]]; then
      local val val_ec=0
      val=$(yq -r ".risk_profiles[\"$risk_profile\"].c3_required" "$policy_file" 2>/dev/null) || val_ec=$?
      [[ $val_ec -eq 0 && "$val" == "true" ]] && c3_required="true"
    elif [[ "$risk_profile" == "high" || "$risk_profile" == "unverifiable" ]]; then
      # Profile absent from policy but high/unverifiable → fail-closed to c3.
      c3_required="true"
    fi
  else
    # No policy file / no yq → fail-closed for the two C3-required profiles.
    [[ "$risk_profile" == "high" || "$risk_profile" == "unverifiable" ]] && c3_required="true"
  fi

  if [[ "$c3_required" == "true" ]]; then
    echo "$C3_MODE_INDEPENDENT"
  else
    echo "$C3_MODE_LEGACY"
  fi
  return 0
}

# Only run when executed directly (allow sourcing for unit tests). Capture the
# return code explicitly so `set -e` cannot abort before the exit propagates.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _rc=0
  resolve_mode "$@" || _rc=$?
  exit "$_rc"
fi
