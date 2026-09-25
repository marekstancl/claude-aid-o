#!/usr/bin/env bash
# =============================================================================
# bin/aid-plugin-issues-collect.sh — what the projects reported and nobody
# has decided yet
#
# Walks every AID workspace under a projects root and LISTS the entries of each
# project's .aid-o/work/aid-plugin-issues.md that carry no decision marker
# (HOTOVO / ZAMÍTNUTO / ČÁSTEČNĚ / UŽ ŘEŠENO) — per project, with the entry's
# heading and line. It writes nothing: the project file is the one record, and
# the plugin owner writes the decision into it (P099; the inbox copy that
# existed before drifted to 90 entries and 0 decisions). An entry marked only
# PŘEVZATO by the old collector is still open. An entry marked ČEKÁ NA DŮKAZ
# (cause not proven yet) is listed apart, with its occurrence count: 1 + every
# `**Další výskyt:**` line in its body; 2+ means "judge it again". Run by hand:
#
#   bin/aid-plugin-issues-collect.sh [--root /opt/eco/projects]
#
# An entry is a heading `## N. …`, `### N. …` or a dated `## YYYY-MM-DD …`;
# its body runs to the next heading. A `##` heading with `###` headings under
# it is a container, never an entry. The marker is a blockquote line right
# under the heading.
# =============================================================================
set -euo pipefail

ROOT="${AID_PROJECTS_ROOT:-/opt/eco/projects}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

MARK_RE='^> \*\*(HOTOVO|ZAMÍTNUTO|ČÁSTEČNĚ|UŽ ŘEŠENO)'
WAIT_RE='^> \*\*ČEKÁ NA DŮKAZ'
ENTRY_RE='^##+ ([0-9]+\. |[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])'

open=0
waiting=0
for f in "$ROOT"/*/.aid-o/work/aid-plugin-issues.md; do
  [[ -f "$f" ]] || continue
  project="$(basename "$(dirname "$(dirname "$(dirname "$f")")")")"
  [[ "$project" == "aid-orchestrator" ]] && continue     # the owner's own file is not a source
  # Plain awk on purpose: this host runs mawk (no gensub, no interval quantifiers).
  all="$(awk -v mark_re="$MARK_RE" -v wait_re="$WAIT_RE" -v entry_re="$ENTRY_RE" '
    NR == FNR { if (/^## /) last2 = FNR; else if (/^### / && last2) { container[last2] = 1; last2 = 0 }; next }
    function flush() {
      if (head != "" && wait) print "W " head_ln ": " head " (výskytů: " occ ")" (occ >= 2 ? " -> posoudit znovu" : "")
      else if (head != "" && !marked) print "O " head_ln ": " head
      head = ""
    }
    /^##/ && (FNR in container) { flush(); next }
    $0 ~ entry_re { flush(); head = $0; sub(/^#+ /, "", head); head_ln = FNR; marked = 0; wait = 0; occ = 1; pending = 1; next }
    /^## / { flush(); next }
    pending && $0 != "" { pending = 0; if ($0 ~ mark_re) marked = 1; else if ($0 ~ wait_re) wait = 1 }
    wait && /^\*\*Další výskyt:\*\*/ { occ++ }
    END { flush() }
  ' "$f" "$f")"
  lines="$(sed -n 's/^O //p' <<< "$all")"
  waits="$(sed -n 's/^W //p' <<< "$all")"
  if [[ -z "$lines" && -z "$waits" ]]; then
    printf '%s: nothing open\n' "$project"
    continue
  fi
  printf '%s (%s):\n' "$project" "${f#"$ROOT"/}"
  if [[ -n "$lines" ]]; then
    while IFS= read -r l; do printf '  line %s\n' "$l"; done <<< "$lines"
    open=$((open + $(grep -c '' <<< "$lines")))
  fi
  if [[ -n "$waits" ]]; then
    printf '  čeká na důkaz:\n'
    while IFS= read -r l; do printf '    line %s\n' "$l"; done <<< "$waits"
    waiting=$((waiting + $(grep -c '' <<< "$waits")))
  fi
done
echo "open entries: ${open}, waiting for evidence: ${waiting}" >&2
