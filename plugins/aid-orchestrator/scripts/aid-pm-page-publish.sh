#!/usr/bin/env bash
# =============================================================================
# aid-pm-page-publish.sh — publish a page AID rendered for the PM (AID 3.10.0)
#
#   aid-pm-page-publish.sh <page.html> --plan <Pnnn> --kind plan|close|brainstorm --title "<title>" [--project-root <r>]
#
# Prints ONE line for the controller:
#   artifact <page>     no publisher configured: publish the page with the Artifact tool, as before (exit 0)
#   link <https://…>    published; the controller adds "Stránka: <link>" under the chat card (exit 0)
# and on failure exits 1 with one sentence on stderr — never "artifact": a page a configured publisher refused is
# not quietly sent elsewhere (the controller adds "Stránka se nezveřejnila: <reason>" under the card).
#
# THE PUBLISHER PROTOCOL (for anyone wiring their own service):
#   AID_PM_PAGE_PUBLISHER              path to an executable (never evaluated by a shell)
#   AID_PM_PAGE_PUBLISHER_SUBCOMMAND   optional single word passed first (e.g. publish-for-pm)
#   argv  [<subcommand>] --key <project-id>/<plan>/<kind> --title <title> --project <display name> [--logo <svg>]
#   stdin the page exactly as the renderer wrote it (an HTML body with inline CSS, no external assets)
#   stdout exit 0 and exactly one line, the https:// link the PM opens; anything on stderr is relayed to stderr
#   The same key must give the same link: the page is replaced, the PM keeps one link per page.
# What goes out: the rendered page (secrets were redacted by the renderer), the project's display name and its
# logo. Whoever knows the page's address sees the name and the logo before the key; the content needs the key.
#
# On success a delivery record <page>.published.json (page_sha256, key, kind, at — never the link, which carries the
# PM's key and goes to the chat only) is written next to the
# page; the obligations that ask for the page (lib/aid-artifact-obligation.sh, aid-brainstorm-state.sh approve)
# ask for this record when a publisher is configured (lib/aid-pm-page.sh).
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

page="" plan="" kind="" title="" root=""
[[ $# -ge 1 && "$1" != --* ]] && { page="$1"; shift; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) plan="${2:-}"; shift 2 ;;
    --kind) kind="${2:-}"; shift 2 ;;
    --title) title="${2:-}"; shift 2 ;;
    --project-root) root="${2:-}"; shift 2 ;;
    *) _die "unknown argument: $1" 2 ;;
  esac
done
[[ -n "$page" && -f "$page" && -r "$page" ]] || _die "no readable page: ${page:-<none>}" 2
[[ "$plan" =~ ^P[0-9]{3,}$ ]] || _die "--plan must be P<number>, got '${plan}'" 2
[[ "$kind" =~ ^(plan|close|brainstorm)$ ]] || _die "--kind must be plan, close or brainstorm, got '${kind}'" 2
title="${title//[$'\t\r\n']/ }"
[[ -n "${title// /}" ]] || _die "--title is required" 2

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

# the key's project id: the state root's directory (stable), narrowed; the display name may change freely
pid="$(basename "$root" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-60)"
[[ -n "$pid" ]] || pid="project"
name=""
[[ -f "$pyaml" ]] && name="$(yq -r '.project_name // .name // ""' "$pyaml" 2>/dev/null || true)"
[[ -n "$name" && "$name" != null ]] || name="$(basename "$root")"
name="$(printf '%s' "$name" | tr -d '\000-\037' | cut -c1-60)"

# the logo: pm_page.logo in project.yaml (an error when unusable), else the first usable common favicon
_logo_ok() {   # <path> — inside the root, a regular file, at most 8 KiB, an SVG
  local p="$1" real
  real="$(realpath -e -- "$p" 2>/dev/null)" || return 1
  [[ "$real" == "$root"/* && -f "$real" && ! -L "$p" ]] || return 1
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
link="$(grep -c . "$out" || true)"
[[ "$link" == 1 ]] || _die "the publisher printed $(grep -c . "$out" || echo 0) lines on stdout, not exactly one link"
link="$(grep -m1 . "$out" | tr -d '[:space:]')"
[[ "$link" =~ ^https://[^[:space:]]+$ ]] || _die "the publisher printed no https:// link: $(cut -c1-120 "$out")"

rec="$(aid_pm_page_receipt "$page")"
# the link carries the PM's key: it goes to the chat only, never into a file (the share rule) — the record holds
# what proves the delivery, not the way in
jq -n --arg s "$(sha256sum "$page" | awk '{print $1}')" --arg k "$key" --arg d "$kind" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{page_sha256: $s, key: $k, kind: $d, at: $at}' > "${rec}.tmp" \
  && mv -f "${rec}.tmp" "$rec" || _die "the page was published (${link}) but its delivery record could not be written: ${rec}"
printf 'link %s\n' "$link"
