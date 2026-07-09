#!/usr/bin/env bash
# aid-review-signals.sh — shared plan-boundary review-signal helpers.
#
# Sourceable library (B1, E-059-2_2 Step 4). Provides the two review-signal
# substrate functions consumed by BOTH the FSM compliance checks
# (fsm_eval_delivery_report_present / fsm_eval_simplifier_present in aid-fsm.sh)
# AND the C4 release aggregator (aid-release-policy.sh):
#
#   _aid_read_toggle <exec_yaml> <section>        — returns 0 (enabled) / 1 (disabled)
#   _aid_validate_test_evidence <report> <ev_dir> — echoes true|false
#
# Both were extracted VERBATIM from aid-fsm.sh so the FSM check and the C4
# aggregator read ONE substrate (no divergence between the two callers). This
# file has NO top-level `set -e` (it must never force that option onto a script
# that sources it) and performs NO side-effect at source time other than defining
# functions — it is safe to source from anywhere.

# ─── Helper: read toggle status from execution.yaml ──────────────────────────
# Returns 0 (enabled) or 1 (disabled) based on the specified section in execution.yaml.
# Usage: _aid_read_toggle "$exec_yaml" "simplifier" && enabled=true || enabled=false
_aid_read_toggle() {
  local exec_yaml="$1" section_name="$2"
  [[ ! -f "$exec_yaml" ]] && return 0  # file missing → enabled by default
  if grep -qP "^\s{0,4}${section_name}:\s*$" "$exec_yaml" && \
     grep -A5 "${section_name}:" "$exec_yaml" | grep -qP '^\s+enabled:\s+false\s*$'; then
    return 1
  fi
  return 0
}

# ─── Helper: validate _test_evidence[] frontmatter references exist on disk ───
# Echoes `true` if the report's YAML frontmatter _test_evidence[] lists >=1 path
# that exists on disk under evidence_dir, else `false`. Conservative `false` when
# yq is unavailable or the report is unreadable (its true|false contract has no
# not-applicable value — the FSM's yq→null guard stays in the caller). Path
# traversal (`..`) and absolute paths are rejected before the existence test
# because _test_evidence is author-controlled and must not be satisfiable by
# pointing at an arbitrary host file.
# Usage: valid=$(_aid_validate_test_evidence "$report" "$evidence_dir")
_aid_validate_test_evidence() {
  local report_file="$1" evidence_dir="$2"

  # Frontmatter inspection needs yq; conservative false if absent.
  command -v yq >/dev/null 2>&1 || { echo false; return 0; }
  [[ -f "$report_file" ]] || { echo false; return 0; }

  # Extract the YAML frontmatter (lines strictly between the 1st and 2nd '---',
  # tolerating a leading HTML comment block) and read _test_evidence[].
  local ev_paths
  ev_paths=$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit; next} c==1{print}' "$report_file" \
    | yq -r '._test_evidence[]?' 2>/dev/null || true)
  [[ -z "$ev_paths" ]] && { echo false; return 0; }

  # >=1 referenced artifact must exist on disk under the run evidence dir.
  # _test_evidence is author-controlled, so reject path-traversal (`..`) and
  # absolute paths before the existence test — the check must not be satisfiable
  # by pointing at an arbitrary host file (matters especially once promoted to
  # blocking). Only paths that stay under the run evidence dir count.
  local one_exists=false line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" == /* || "$line" == *..* ]] && continue
    if [[ -f "${evidence_dir}/${line}" ]]; then one_exists=true; break; fi
  done <<< "$ev_paths"

  if $one_exists; then echo true; else echo false; fi
}

# ─── CLI dispatcher (tests / standalone) ─────────────────────────────────────
# Only runs on direct invocation (`bash aid-review-signals.sh <fn> <args>`).
# Source-mode (BASH_SOURCE != $0) skips this entirely, so the function defs load
# cleanly into aid-fsm.sh / aid-release-policy.sh without the dispatcher firing.
# Mirrors the guarded dispatcher in lib/aid-stage-log.sh.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ $# -gt 0 ]]; then
  fn="$1"; shift
  case "$fn" in
    read_toggle)
      if _aid_read_toggle "$@"; then echo "enabled"; exit 0; else echo "disabled"; exit 1; fi
      ;;
    validate_test_evidence)
      _aid_validate_test_evidence "$@"
      ;;
    *)
      echo "ERROR: unknown function: $fn" >&2
      echo "Available: read_toggle <exec_yaml> <section>, validate_test_evidence <report_file> <evidence_dir>" >&2
      exit 1
      ;;
  esac
fi
