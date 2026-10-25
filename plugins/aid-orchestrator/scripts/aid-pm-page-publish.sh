#!/usr/bin/env bash
# =============================================================================
# aid-pm-page-publish.sh — publish a page AID rendered for the PM (AID 3.10.0)
#
#   aid-pm-page-publish.sh <page.html> --plan <Pnnn> --kind plan|close|brainstorm --title "<title>" [--project-root <r>]
#                          [--on-request]   the PM asked for this page: publish it even when AID_PM_PAGES=off
#
# Prints ONE line for the controller:
#   none <page>         AID_PM_PAGES=off and not --on-request: publish nothing, the card alone goes to the chat (exit 0)
#   artifact <page>     no publisher configured: publish the page with the Artifact tool, as before (exit 0)
#   link <https://…>    published; the controller adds "Stránka: <link>" under the chat card (exit 0)
# and on failure exits 1 with one sentence on stderr — never "artifact": a page a configured publisher refused is
# not quietly sent elsewhere (the controller adds "Stránka se nezveřejnila: <reason>" under the card).
#
# THE PUBLISHER PROTOCOL (for anyone wiring their own service):
#   AID_PM_PAGE_PUBLISHER              path to an executable (never evaluated by a shell)
#   AID_PM_PAGE_PUBLISHER_SUBCOMMAND   optional single word passed first (e.g. publish-for-pm)
#   argv  [<subcommand>] --key <project-id>/<plan>/<kind> (project-id = <dir slug>-<8 hex of repo_id or root path>) --title <title> --project <display name> [--logo <svg>]
#   stdin the page exactly as the renderer wrote it (an HTML body with inline CSS, no external assets)
#   stdout exit 0 and exactly one line, the https:// link the PM opens; anything on stderr is relayed to stderr
#   The same key must give the same link: the page is replaced, the PM keeps one link per page.
# What goes out: the rendered page (secrets were redacted by the renderer), the project's display name and its
# logo. Whoever knows the page's address sees the name and the logo before the key; the content needs the key.
#
# On success a delivery record <page>.published.json (page_sha256, key, kind, at — never the link, which carries the
# PM's key and goes to the chat only) is written next to the
# page; the obligations that ask for the page (lib/aid-artifact-obligation.sh, aid-brainstorm-state.sh approve)
# ask for this record when a publisher is configured and the pages are not off (lib/aid-pm-page.sh).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-roots.sh
source "${SCRIPT_DIR}/lib/aid-roots.sh"
# shellcheck source=lib/aid-pm-page.sh
source "${SCRIPT_DIR}/lib/aid-pm-page.sh"

MAX_BYTES=$((2 * 1024 * 1024))   # share's own page limit (share/publish_check.py MAX_HTML)
LOGO_MAX=8192

_die() { echo "aid-pm-page-publish: $1" >&2; exit "${2:-1}"; }

page="" plan="" kind="" title="" root="" on_request=0
[[ $# -ge 1 && "$1" != --* ]] && { page="$1"; shift; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; plan="${2:-}"; shift 2 ;;
    --kind) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; kind="${2:-}"; shift 2 ;;
    --title) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; title="${2:-}"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || { echo "${0##*/}: ${1:-} needs a value" >&2; return 2 2>/dev/null || exit 2; }; root="${2:-}"; shift 2 ;;
    --on-request) on_request=1; shift ;;
    *) _die "unknown argument: $1" 2 ;;
  esac
done
[[ -n "$page" && -f "$page" && -r "$page" ]] || _die "no readable page: ${page:-<none>}" 2
[[ "$plan" =~ ^P[0-9]{3,}$ ]] || _die "--plan must be P<number>, got '${plan}'" 2
[[ "$kind" =~ ^(plan|close|brainstorm)$ ]] || _die "--kind must be plan, close or brainstorm, got '${kind}'" 2
title="${title//[$'\t\r\n']/ }"
[[ -n "${title// /}" ]] || _die "--title is required" 2

# the PM switched the automatic pages off: nothing goes out unless the PM asked for this page
if aid_pm_pages_auto_off && (( ! on_request )); then
  printf 'none %s\n' "$page"
  exit 0
fi

# no publisher: the page stays a claude.ai artifact, exactly as before
if ! aid_pm_page_publisher_set; then
  printf 'artifact %s\n' "$page"
  exit 0
fi

pub="$AID_PM_PAGE_PUBLISHER"
[[ -x "$pub" && ! -d "$pub" ]] || _die "AID_PM_PAGE_PUBLISHER is not an executable file: ${pub}"
sub="${AID_PM_PAGE_PUBLISHER_SUBCOMMAND:-}"
[[ -z "$sub" || "$sub" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || _die "AID_PM_PAGE_PUBLISHER_SUBCOMMAND must be one word, got '${sub}'"

size="$(wc -c < "$page")"
(( size <= MAX_BYTES )) || _die "the page is ${size} bytes, over the ${MAX_BYTES} a published page may have"

[[ -n "$root" ]] || root="$(aid_state_root 2>/dev/null || pwd)"
root="$(realpath "$root")"
pyaml="${root}/.aid-o/config/project.yaml"

# the key's project id: a readable slug of the state root's directory AND a short digest of what identifies the
# project uniquely — its lifecycle repo_id (.aid-lifecycle/repo-identity.yaml, tracked, never created here), else the
# root's real path. A slug alone let two projects of the same directory name overwrite each other's page (security
# review, 24. 10. 2026). The display name may change freely; the key does not.
slug="$(basename "$root" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-48)"
[[ -n "$slug" ]] || slug="project"
ident=""
[[ -f "${root}/.aid-lifecycle/repo-identity.yaml" ]] && ident="$(yq -r '.repo_id // ""' "${root}/.aid-lifecycle/repo-identity.yaml" 2>/dev/null || true)"
[[ -n "$ident" && "$ident" != null ]] || ident="$root"
pid="${slug}-$(printf '%s' "$ident" | sha256sum | cut -c1-8)"
name=""
[[ -f "$pyaml" ]] && name="$(yq -r '.project_name // .name // ""' "$pyaml" 2>/dev/null || true)"
[[ -n "$name" && "$name" != null ]] || name="$(basename "$root")"
name="$(printf '%s' "$name" | tr -d '\000-\037' | cut -c1-60)"

# the logo: pm_page.logo in project.yaml (an error when unusable), else the first usable common favicon
_logo_ok() {   # <path> — inside the root, a regular file, at most 8 KiB, an SVG
  local p="$1" real
  real="$(realpath -e -- "$p" 2>/dev/null)" || return 1
  [[ "$real" == "$root"/* && -f "$real" ]] || return 1   # decided on the resolved path: a link inside the project is fine
  (( $(wc -c < "$real") <= LOGO_MAX )) || return 1
  grep -qi '<svg' "$real" || return 1
  printf '%s' "$real"
}
logo="" cfg_logo=""
[[ -f "$pyaml" ]] && cfg_logo="$(yq -r '.pm_page.logo // ""' "$pyaml" 2>/dev/null || true)"
if [[ -n "$cfg_logo" && "$cfg_logo" != null ]]; then
  [[ "$cfg_logo" == /* ]] || cfg_logo="${root}/${cfg_logo}"
  logo="$(_logo_ok "$cfg_logo")" || _die "pm_page.logo in ${pyaml} is not a usable logo (inside the project, a regular SVG file of at most ${LOGO_MAX} bytes): ${cfg_logo}"
else
  for c in frontend/public/favicon.svg ui/public/favicon.svg public/favicon.svg src/app/favicon.svg; do
    [[ -e "${root}/${c}" ]] || continue
    if logo="$(_logo_ok "${root}/${c}")"; then break; fi
    echo "aid-pm-page-publish: ${c} is not a usable logo (an SVG of at most ${LOGO_MAX} bytes inside the project) — skipped" >&2
    logo=""
  done
fi

key="${pid}/${plan}/${kind}"
args=()
[[ -n "$sub" ]] && args+=("$sub")
args+=(--key "$key" --title "$title" --project "$name")
[[ -n "$logo" ]] && args+=(--logo "$logo")

out="$(mktemp)" err="$(mktemp)"
trap 'rm -f "$out" "$err"' EXIT
rc=0
"$pub" "${args[@]}" < "$page" > "$out" 2> "$err" || rc=$?
[[ -s "$err" ]] && sed 's/^/  publisher: /' "$err" | head -20 >&2
if (( rc != 0 )); then
  _die "the publisher refused the page (exit ${rc}): $(grep -m1 . "$err" | cut -c1-200)"
fi
# exactly one physical line, the whole of it a link — nothing normalised away
nl="$(wc -l < "$out")"; link="$(cat "$out")"
[[ "$nl" == 1 && "$link" != *$'\n'* ]] || _die "the publisher printed ${nl} lines on stdout, not exactly one link"
[[ "$link" =~ ^https://[^[:space:]]+$ ]] || _die "the publisher printed no https:// link: ${link:0:120}"

rec="$(aid_pm_page_receipt "$page")"
# the link carries the PM's key: it goes to the chat only, never into a file (the share rule) — the record holds
# what proves the delivery, not the way in
jq -n --arg s "$(sha256sum "$page" | awk '{print $1}')" --arg k "$key" --arg d "$kind" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{page_sha256: $s, key: $k, kind: $d, at: $at}' > "${rec}.tmp" \
  && mv -f "${rec}.tmp" "$rec" || _die "the page was published (${link}) but its delivery record could not be written: ${rec}"
printf 'link %s\n' "$link"
