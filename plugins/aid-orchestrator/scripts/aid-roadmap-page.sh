#!/usr/bin/env bash
# =============================================================================
# aid-roadmap-page.sh — the progress page of a roadmap (AID 3.14.0, PM 30. 10. 2026: every roadmap has one; every plan
# and every /aid-do on the same thing refreshes it, and a plan does not close until it did)
#
#   aid-roadmap-page.sh init <docs/plans/<roadmap>.md> --title "<topic>"     page line in the document, the data file
#                                                                            <roadmap>.prubeh.json, the first publish
#   aid-roadmap-page.sh publish <docs/plans/<roadmap>.md> --plan P<n>         after the plan wrote its change in the data
#   aid-roadmap-page.sh publish <docs/plans/<roadmap>.md> --aid-do            after a /aid-do on a roadmap item
#
# The agent writes only <roadmap>.prubeh.json (the fields: skills/plan-writing.md §The roadmap's progress page).
# Published through aid-pm-page-publish.sh --kind roadmap, also when AID_PM_PAGES=off; prints `link <url>` (the link
# goes to the chat only) or `local <page>` when no publisher is configured. Implementation: lib/aid_roadmap_page.py.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
step="${1:-}"; doc="${2:-}"
[[ "$step" =~ ^(init|publish)$ && -n "$doc" ]] || { echo "usage: aid-roadmap-page.sh init <doc> --title \"<topic>\" | publish <doc> (--plan P<n> | --aid-do)" >&2; exit 2; }
shift 2
project="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "aid-roadmap-page: not inside a git repository" >&2; exit 2; }
state="$(aid_state_root "$project" 2>/dev/null || printf '%s' "$project")"
exec python3 -I "${SCRIPT_DIR}/lib/aid_roadmap_page.py" "$step" "$project" "$state" "$doc" "$@"
