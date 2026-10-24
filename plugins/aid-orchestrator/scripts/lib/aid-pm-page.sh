#!/usr/bin/env bash
# =============================================================================
# lib/aid-pm-page.sh — where the PM's pages go (AID 3.10.0)
#
#   aid_pm_page_publisher_set        0 when a publisher is configured (AID_PM_PAGE_PUBLISHER)
#   aid_pm_page_receipt <page>       the delivery record next to a page: <page>.published.json
#   aid_pm_page_delivered <page>     0 when the page needs no delivery record (no publisher: the Artifact tool, as
#                                    before) or its record matches the page's bytes; 1 with the reason on stderr
#
# A page AID renders for the PM (the plan after CP1, the close, the brainstorm) is published by
# scripts/aid-pm-page-publish.sh: with no publisher configured it stays a claude.ai artifact; with one, the page
# goes to that service and a record of the delivery is written next to it. The obligations that ask for the page
# ask for that record too, so a page that was rendered but never reached the PM is not a delivered page.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_PM_PAGE_SH_LOADED:-}" ]] && return 0
_AID_PM_PAGE_SH_LOADED=1

aid_pm_page_publisher_set() { [[ -n "${AID_PM_PAGE_PUBLISHER:-}" ]]; }

aid_pm_page_receipt() { printf '%s.published.json' "$1"; }

aid_pm_page_delivered() {
  local page="$1" rec sha
  aid_pm_page_publisher_set || return 0
  rec="$(aid_pm_page_receipt "$page")"
  if [[ ! -f "$rec" ]]; then
    echo "the page ${page} is rendered but was not published to the PM (no ${rec##*/}) — publish it: bash \"\$AID_PLUGIN_PATH/scripts/aid-pm-page-publish.sh\" \"${page}\" --plan <Pnnn> --kind plan|close|brainstorm --title \"<title>\"" >&2
    return 1
  fi
  sha="$(sha256sum "$page" | awk '{print $1}')"
  if [[ "$(jq -r '.page_sha256 // ""' "$rec" 2>/dev/null)" != "$sha" ]]; then
    echo "the page ${page} changed after it was published (${rec##*/} names other bytes) — publish it again: bash \"\$AID_PLUGIN_PATH/scripts/aid-pm-page-publish.sh\" \"${page}\" --plan <Pnnn> --kind plan|close|brainstorm --title \"<title>\"" >&2
    return 1
  fi
  return 0
}
