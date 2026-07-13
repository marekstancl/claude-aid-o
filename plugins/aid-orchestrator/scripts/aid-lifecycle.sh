#!/usr/bin/env bash
# =============================================================================
# aid-lifecycle.sh — CLI for the IMP-232 canonical plan-level closure (v2.58.0)
#
# Read-only queries + artifact validation over the git-tracked .aid-lifecycle/
# state. Mutating closure operations (plan-close / plan-reconcile) live in
# aid-fsm.sh. All commands run relative to the current working directory (the
# project root) unless a <root> arg is given.
#
# Usage:
#   aid-lifecycle.sh repo-id [root]                 # print (create if absent) repo UUID
#   aid-lifecycle.sh state <plan_id> [root]         # print closure state
#   aid-lifecycle.sh declared <plan_id> [root]      # print "<epic_id> <scope>" lines
#   aid-lifecycle.sh parse-legacy <plan_id> <file>  # strict legacy EPIC parse
#   aid-lifecycle.sh validate <yaml> <schema_base>  # schema + public-safe (exit 0/1)
#   aid-lifecycle.sh publicsafe <yaml>              # public-safe net only (exit 0/1)
#   aid-lifecycle.sh target-branch                  # configured integration branch
#
# Exit: 0 ok; 1 error/violation; 2 legacy-unverifiable (ambiguous parse);
#       3 plan not found.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aid-lifecycle.sh"

cmd="${1:-}"; shift || true
case "$cmd" in
  repo-id)       aid_repo_id "${1:-.}" ;;
  target-branch) aid_target_branch ;;
  state)         [[ -n "${1:-}" ]] || { echo "usage: state <plan_id> [root]" >&2; exit 1; }
                 aid_plan_closure_state "$1" "${2:-.}" ;;
  declared)      [[ -n "${1:-}" ]] || { echo "usage: declared <plan_id> [root]" >&2; exit 1; }
                 aid_lifecycle_declared_epics "$1" "${2:-.}" ; exit $? ;;
  parse-legacy)  [[ -n "${1:-}" && -n "${2:-}" ]] || { echo "usage: parse-legacy <plan_id> <plan_file>" >&2; exit 1; }
                 aid_lifecycle_parse_legacy_epics "$1" "$2" ; exit $? ;;
  validate)      [[ -n "${1:-}" && -n "${2:-}" ]] || { echo "usage: validate <yaml> <schema_base>" >&2; exit 1; }
                 aid_lifecycle_validate_artifact "$1" "$2" && echo "OK: $1 valid + public-safe" ;;
  publicsafe)    [[ -n "${1:-}" ]] || { echo "usage: publicsafe <yaml>" >&2; exit 1; }
                 aid_lifecycle_publicsafe_check "$1" && echo "OK: $1 public-safe" ;;
  ""|-h|--help)  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *)             echo "unknown command: $cmd (see --help)" >&2; exit 1 ;;
esac
