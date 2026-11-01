#!/usr/bin/env bash
# =============================================================================
# lib/aid-roadmap.sh — a plan that belongs to a roadmap keeps its progress page (AID 3.14.0)
#
#   aid_roadmap_brief_check <brief.md> <project root>
#       prints one "ERROR <code>: …" / "WARN <code>: …" line per finding; exit 1 when an ERROR was printed.
#       roadmapa_dokument: <path> in the brief's frontmatter names the roadmap document (from the project root);
#       it must have its page (aid-roadmap-page.sh init). The older free-text `roadmapa:` binds nothing; a path in it
#       to a document that has a page only draws a WARN (the briefs P113, P114, P117 stay as they are).
#   aid_roadmap_refreshed <project root> <state root> <document> <plan> <merge commit>
#       0 when <plan> published the page from the data as they are in <merge commit> (plan-close), 1 not, 2 bad path
# Path rules, data schema and the record: lib/aid_roadmap_page.py (one place).
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_ROADMAP_SH_LOADED:-}" ]] && return 0
_AID_ROADMAP_SH_LOADED=1
_AID_ROADMAP_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/aid_roadmap_page.py"

# shellcheck source=aid-roots.sh
declare -F _aid_fm_get >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/aid-roots.sh"

aid_roadmap_brief_check() {
  local brief="$1" project="$2" doc rc=0 err free p
  doc="$(_aid_fm_get "$brief" roadmapa_dokument)"
  if [[ -n "$doc" ]]; then
    err="$(python3 -I "$_AID_ROADMAP_PY" check "$project" "$doc" 2>&1 >/dev/null)" || rc=$?
    case "$rc" in
      0) return 0 ;;
      1) printf 'ERROR roadmap_page_missing: %s. next: aid-roadmap-page.sh init %s --title "<topic>" and commit the document with its .prubeh.json (pipeline.md §When AID refuses: roadmap_page_missing)\n' "${err#aid-roadmap-page: }" "$doc" ;;
      *) printf 'ERROR roadmap_path_invalid: %s. next: name the roadmap document by its path from the project root, inside the project, no link on the way (pipeline.md §When AID refuses: roadmap_path_invalid)\n' "${err#aid-roadmap-page: }" ;;
    esac
    return 1
  fi
  free="$(_aid_fm_get "$brief" roadmapa)"
  p="$(grep -oE '[A-Za-z0-9_./-]+\.md' <<< "$free" | head -1)"
  if [[ -n "$p" ]] && python3 -I "$_AID_ROADMAP_PY" check "$project" "$p" >/dev/null 2>&1; then
    printf 'WARN roadmap_document_unnamed: roadmapa: names %s, which has a progress page — add roadmapa_dokument: %s so the plan refreshes it\n' "$p" "$p"
  fi
  return 0
}

aid_roadmap_refreshed() { python3 -I "$_AID_ROADMAP_PY" refreshed "$@"; }
