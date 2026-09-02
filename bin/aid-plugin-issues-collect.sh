#!/usr/bin/env bash
# =============================================================================
# bin/aid-plugin-issues-collect.sh — the plugin owner's inbox
#
# Walks every AID workspace under a projects root, takes the entries of each
# project's .aid-o/work/aid-plugin-issues.md that carry NO decision marker yet
# (PŘEVZATO / HOTOVO / ZAMÍTNUTO / ČÁSTEČNĚ / UŽ ŘEŠENO), appends them to
# docs/plans/plugin-issues-inbox.md here, and marks them PŘEVZATO <date> in the
# project file so the next run skips them. Nothing is deleted anywhere: the
# project file stays the project's record; the inbox is where decisions are
# made. Run by hand, by the owner, when it is time to decide:
#
#   bin/aid-plugin-issues-collect.sh [--root /opt/eco/projects] [--dry-run]
#
# An entry is a heading `## N. …` or `### N. …`; its body runs to the next
# heading of the same or higher level. The marker is a blockquote line right
# under the heading — the same shape the owner has been writing by hand.
# =============================================================================
set -euo pipefail

ROOT="${AID_PROJECTS_ROOT:-/opt/eco/projects}"
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "$0")/.." && pwd)"
INBOX="${HERE}/docs/plans/plugin-issues-inbox.md"
TODAY="$(date -u +%Y-%m-%d)"
MARK_RE='^> \*\*(PŘEVZATO|HOTOVO|ZAMÍTNUTO|ČÁSTEČNĚ|UŽ ŘEŠENO)'

taken=0; projects=0; out=""
for f in "$ROOT"/*/.aid-o/work/aid-plugin-issues.md; do
  [[ -f "$f" ]] || continue
  project="$(basename "$(dirname "$(dirname "$(dirname "$f")")")")"
  [[ "$project" == "aid-orchestrator" ]] && continue     # the owner's own file is not an inbox source
  projects=$((projects+1))
  # awk: emit each unmarked entry as a block; rewrite the file with a marker
  # under each heading it took.
  tmp="$(mktemp)"; blocks="$(mktemp)"
  # Line numbers of `##` headings that have a deeper heading under them. Those
  # are CONTAINERS, never entries: WAN writes `## 2026-08-27, generování EPICů`
  # and puts `### 1. …` reports beneath it, while ACTA writes
  # `## 2026-08-31 — …` with the report in its own body. Nothing in the heading
  # text separates the two — judging by a comma or a dash took three WAN section
  # headers as reports, which test-plugin-issues caught before the inbox did.
  # Plain awk on purpose: this host runs mawk, which has no gensub.
  container_lines="$(awk '
    /^## / { last2 = NR; next }
    /^### / { if (last2 != 0) { print last2; last2 = 0 } }
  ' "$f" 2>/dev/null | sort -u | tr "\n" " ")"
  awk -v today="$TODAY" -v mark_re="$MARK_RE" -v blocks="$blocks" -v project="$project" \
      -v container_lines="$container_lines" '
    BEGIN { _n = split(container_lines, _cl, " ")
            for (_i = 1; _i <= _n; _i++) if (_cl[_i] != "") container[_cl[_i]+0] = 1 }
    function flush(   v) {
      if (inentry && !marked) {
        v = "plugin: not recorded"
        if (match(body, /\*\*Plugin:\*\* *v?[0-9][0-9.]*/)) { v = substr(body, RSTART, RLENGTH); sub(/^\*\*Plugin:\*\* */, "plugin v", v); sub(/vv/, "v", v) }
        printf "\n---\n\n#### %s — %s (%s)\n\n%s\n", project, headline, v, body >> blocks
        taken++
      }
    }
    BEGIN { inentry=0; marked=0 }
    # AN ENTRY IS A NUMBERED **OR** A DATED HEADING. The date is spelled out
    # digit by digit on purpose: this awk does not take interval quantifiers
    # (`{4}`) without --re-interval, and a pattern that silently matches
    # nothing is exactly the failure being fixed.
    # AN ENTRY IS A NUMBERED **OR** A DATED HEADING. Projects number their
    # entries while a list is being kept and switch to dates once it is a
    # running log — ACTA did exactly that on 2026-08-30, and the collector then
    # reported "nothing new" for 19 real reports over three days, because it
    # only ever looked for `## N.`. A collector that silently sees nothing is
    # worse than no collector: it answers the question it was asked with a
    # confident, wrong "no".
    # A CONTAINER IS A CONTAINER WHATEVER ITS HEADING SAYS. Restricting this to
    # dated headings left `## 1. …` with `### …` children matching the ordinary
    # entry rule, which is the same false positive one level down (Codex,
    # 2026-09-02).
    (NR in container) && /^##+ ([0-9]+\. |[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])/ {
      flush(); inentry=0; marked=0; print; next
    }
    /^##+ ([0-9]+\. |[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])/ {
      flush()
      inentry=1; marked=0; headline=$0; sub(/^#+ /, "", headline); body=""
      print; pending=1; next
    }
    /^## / && !/^##+ ([0-9]+\. |[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])/ { flush(); inentry=0; marked=0; print; next }
    {
      if (inentry && pending) {
        # the marker may sit right under the heading or after a blank line
        if ($0 == "") { print; next }
        pending=0
        if ($0 ~ mark_re) { marked=1; print; next }
        # first non-blank line after an unmarked heading: insert the marker here
        print "> **PŘEVZATO " today " (aid-orchestrator)**"
        print ""
      }
      if (inentry) body = body $0 "\n"
      print
    }
    END {
      # an entry that is only a heading at EOF still gets its marker
      if (inentry && pending && !marked) { print "> **PŘEVZATO " today " (aid-orchestrator)**" }
      flush(); print taken+0 > countfile
    }
  ' countfile="$blocks.n" "$f" > "$tmp"
  n="$(cat "$blocks.n" 2>/dev/null || echo 0)"
  if [[ "$n" -gt 0 ]]; then
    out+="$(cat "$blocks")"$'\n'
    taken=$((taken+n))
    if [[ "$DRY" -eq 0 ]]; then cp "$tmp" "$f"; fi
    echo "${project}: ${n} entr$( [[ "$n" -eq 1 ]] && echo y || echo ies) taken" >&2
  else
    echo "${project}: nothing new" >&2
  fi
  rm -f "$tmp" "$blocks" "$blocks.n"
done

if [[ "$taken" -eq 0 ]]; then
  echo "inbox: nothing new across ${projects} project(s)" >&2
  exit 0
fi
if [[ "$DRY" -eq 1 ]]; then
  printf '%s\n' "$out"
  echo "dry run: ${taken} entr$( [[ "$taken" -eq 1 ]] && echo y || echo ies) would be taken; nothing written" >&2
  exit 0
fi
mkdir -p "$(dirname "$INBOX")"
[[ -f "$INBOX" ]] || printf '# AID plugin issues — inbox\n\nCollected by `bin/aid-plugin-issues-collect.sh` from every project'"'"'s `.aid-o/work/aid-plugin-issues.md`. Decide here; mark the project file HOTOVO / ZAMÍTNUTO when done.\n' > "$INBOX"
{ printf '\n## Collected %s — %s entr%s from %s project(s)\n' "$TODAY" "$taken" "$( [[ "$taken" -eq 1 ]] && echo y || echo ies)" "$projects"; printf '%s\n' "$out"; } >> "$INBOX"
echo "inbox: ${taken} entr$( [[ "$taken" -eq 1 ]] && echo y || echo ies) appended to ${INBOX#${HERE}/}" >&2
