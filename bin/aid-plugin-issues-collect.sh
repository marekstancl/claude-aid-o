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
# PŘEVZATO by the old collector is still open. Run by hand:
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
ENTRY_RE='^##+ ([0-9]+\. |[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])'

open=0
for f in "$ROOT"/*/.aid-o/work/aid-plugin-issues.md; do
  [[ -f "$f" ]] || continue
  project="$(basename "$(dirname "$(dirname "$(dirname "$f")")")")"
  [[ "$project" == "aid-orchestrator" ]] && continue     # the owner's own file is not a source
  # Plain awk on purpose: this host runs mawk (no gensub, no interval quantifiers).
  lines="$(awk -v mark_re="$MARK_RE" -v entry_re="$ENTRY_RE" '
    NR == FNR { if (/^## /) last2 = FNR; else if (/^### / && last2) { container[last2] = 1; last2 = 0 }; next }
    function flush() { if (head != "" && !marked) print head_ln ": " head; head = "" }
    /^##/ && (FNR in container) { flush(); next }
    $0 ~ entry_re { flush(); head = $0; sub(/^#+ /, "", head); head_ln = FNR; marked = 0; pending = 1; next }
    /^## / { flush(); next }
    pending && $0 != "" { pending = 0; if ($0 ~ mark_re) marked = 1 }
    END { flush() }
  ' "$f" "$f")"
  if [[ -z "$lines" ]]; then
    printf '%s: nothing open\n' "$project"
    continue
  fi
  printf '%s (%s):\n' "$project" "${f#"$ROOT"/}"
  while IFS= read -r l; do printf '  line %s\n' "$l"; done <<< "$lines"
  open=$((open + $(grep -c '' <<< "$lines")))
done
echo "open entries: ${open}" >&2
