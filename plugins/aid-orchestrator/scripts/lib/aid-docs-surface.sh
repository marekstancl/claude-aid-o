# shellcheck shell=bash
# aid-docs-surface.sh — which paths are DOCUMENTATION a reader reads, not behaviour (P117 (15), (16), (18)).
# One definition for the CP7 confirmation round (a fix of documentation only) and the CP2 final_claims role (a
# step that touches documentation). An allow-list, anchored: CHANGELOG*/README* at any depth, docs/** with a
# documentation extension, and the help the project declares (execution.yaml help_paths: globs). Never
# documentation: markdown that drives behaviour (agents/, skills/, commands/, prompts/, templates/, defaults/,
# .aid-o/ — the plan and its brief are the criteria, not claims) — security review of P117.
#
#   aid_docs_surface <path> [execution.yaml]   0 when the path is documentation

aid_docs_surface() {
  local p="${1#./}" ex="${2:-}" g
  case "/$p" in
    */agents/*|*/skills/*|*/commands/*|*/prompts/*|*/templates/*|*/defaults/*|/.aid-o/*|*/.aid-o/*) return 1 ;;
  esac
  case "${p##*/}" in
    CHANGELOG|CHANGELOG.md|CHANGELOG-*.md|CHANGELOG.*.md|README|README.md|README.*.md) return 0 ;;
  esac
  [[ "$p" =~ ^docs/.+\.(md|mdx|rst|txt|adoc)$ ]] && return 0
  if [[ -n "$ex" && -f "$ex" ]]; then
    while IFS= read -r g; do
      [[ -n "$g" ]] || continue
      # shellcheck disable=SC2053  # a glob on purpose
      [[ "$p" == $g ]] && return 0
    done < <(yq -r '(.help_paths // [])[]' "$ex" 2>/dev/null)
  fi
  return 1
}

# aid_docs_only <fix-class.json> — 0 when the fix changed at least one path and every changed, non-ancillary path
# is documentation by the BUILT-IN list alone (and nothing feeds the criteria: the plan). The project's help_paths
# do not count here: they come from the state root's working copy, and a confirmation round is less review
# (security review of P117); they only ADD the final_claims role in CP2.
aid_docs_only() {
  local fc="$1" p n=0
  [[ -f "$fc" ]] || return 1
  jq -e '.reason == null and ((.invalidated_feeds // []) | index("criteria") | not)' "$fc" >/dev/null 2>&1 || return 1
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue; n=$((n + 1))
    [[ "${p##*/}" == execution.yaml ]] && return 1
    aid_docs_surface "$p" || return 1
  done < <(jq -r '.changed_paths[] | select((.feeds // []) | length > 0) | .path' "$fc")
  (( n > 0 ))
}
