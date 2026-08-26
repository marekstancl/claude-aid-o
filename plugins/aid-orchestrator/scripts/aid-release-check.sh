#!/usr/bin/env bash
# =============================================================================
# aid-release-check.sh — the release-scope verdict, printed where it is read
# (P089 Step 9)
#
#   aid-release-check.sh [--root <path>] [--start <rev>] [--end <rev>]
#
# WHY A SEPARATE ENTRY POINT
#   "A warning printed at push time is a warning nobody reads" (the handoff).
#   The pre-push hook has to decide and block; CI has to TELL. This is the same
#   library, the same verdict, printed into a build log where it stays — and it
#   ALWAYS exits 0. It is a notice, not a gate: a repository that wants the
#   decision enforced already has the hook, and turning the notice into a second
#   blocker would mean two places to argue with over one question.
#
# The workflow step that runs it in THIS repository is the reference a consumer
# copies. Without a caller a facade is just a file — the whole point of the step
# is that the verdict lands in the log.
#
# **Last Updated:** 2026-08-26
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-release-scope.sh
source "${SCRIPT_DIR}/lib/aid-release-scope.sh"

ROOT=""; START=""; END="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)  ROOT="${2:-}"; shift 2 ;;
    --start) START="${2:-}"; shift 2 ;;
    --end)   END="${2:-}"; shift 2 ;;
    -h|--help) sed -n '3,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "aid-release-check.sh: unknown argument '$1'" >&2; exit 0 ;;
  esac
done

[[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -n "$START" ]] || START="$(aid_release_scope_start "$ROOT")"

echo "── AID release scope ─────────────────────────────────────────────────"
echo "range: ${START}..${END}"
aid_release_scope_report "$ROOT" "$START" "$END"

case "${_AID_RS_VERDICT:-}" in
  release_required)
    echo "note: this range changes code outside the release-exempt paths. A push of it will be refused until it is released, or until the offending commits carry a 'No-Release: <reason>' footer."
    ;;
  exempt)
    echo "note: every change in this range is inside the release-exempt paths. No release is needed."
    ;;
  no_commits)
    echo "note: nothing in this range asks for a release."
    ;;
  no_config)
    echo "note: this project has no versioning.release_exempt_paths, so the guard is still deciding by commit label. Run '/aid-setup scan' to set the lists."
    ;;
esac
echo "──────────────────────────────────────────────────────────────────────"
exit 0
