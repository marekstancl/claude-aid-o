#!/usr/bin/env bash
# =============================================================================
# lib/aid-release-scope.sh — does THIS range of work require a release?
# (P089 Step 7)
#
#   aid_release_scope_start    <root>
#   aid_release_scope_evaluate <root> <start> <end>
#   aid_release_scope_report   <root> <start> <end>   → the verdict plus who caused it
#
# WHY THIS EXISTS
#   The pre-push guard decided by the LABEL on a commit message: `fix(tests):`
#   blocked a push that changed no application code at all (WAN, three times in
#   one day), and `chore:` could change the application and sail through. The
#   question a release guard is actually asking is "did what a user runs
#   change?", and a commit subject is a promise about that, not evidence.
#   The evidence is the list of files.
#
#   The same label logic lived twice — here in the hook and again in
#   scripts/aid-release.sh. This library is the one authority both now consume.
#
# THE ORDER IS FIXED, AND IT IS THE SAME IN ALL THREE COPIES
#   1. list the commits in `start..end` and REMOVE those carrying a
#      `No-Release: <reason>` footer;
#   2. over the REMAINING commits, take the UNION of the paths each touched;
#   3. decide over that set — against `release_exempt_paths` ALONE. Everything
#      in the exempt list passes; anything else requires a release, including a
#      path in neither list, because "not proven exempt" is the conservative
#      reading. `app_paths` decides NOTHING here: it is what the housekeeping
#      warning and the anti-drift gate are measured against.
#
#   A UNION OF PATHS, NOT A DIFF. Once commits are removed the remainder is no
#   longer a contiguous range, and `git diff` has nothing to compute over it —
#   two implementations would each invent their own answer. A union is
#   unambiguous and comes out the same in every copy. What that deliberately
#   accepts, and what the tests pin:
#     - a REVERT is an ordinary commit and adds its paths, so a change and its
#       undo still require a release (the conservative direction);
#     - a MERGE COMMIT contributes only its OWN diff along its first parent,
#       which for an ordinary merge is nothing. The commits it brought in are
#       in the range on their own and DO count — deliberately: work merged into
#       the target branch is work being released, and judging the range with
#       `--first-parent` would let an entire feature branch through;
#     - where an exempt and a non-exempt commit touch the same path, the path
#       is in the set, so the non-exempt one wins.
#
# THE `release:` LABEL DOES NOT MOVE THE BOUNDARY
#   The range always starts at the last version tag — a verifiable statement
#   about what was released. Anyone can write a commit whose subject begins
#   `release:` after changing the application, and a guard that let that close
#   the range would be back to trusting labels. Labels survive only for blame
#   and for warnings.
#
# TWO INHERITED EDGES, WRITTEN DOWN RATHER THAN DISCOVERED
#   - NO TAG AT ALL: the range starts at the root of history and `root..HEAD`
#     EXCLUDES the root commit, so a repository that has never been released is
#     judged only on what came after its first commit. Before this library such
#     a repository was waved through unconditionally; this is the same
#     direction, slightly tighter.
#   - A LOCAL TAG THAT WAS NEVER PUSHED narrows the range for everyone who has
#     it and for nobody else. `git describe` is a statement about the local
#     repository, and this library inherits that; it does not consult a remote.
#
# FAIL-OPEN, ON PURPOSE
#   No `yq`, no config, or no `versioning.release_exempt_paths` →
#   `no_config`, and the caller keeps today's label behaviour. A project must
#   never break because it has not been configured yet; it gets one hint line.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-26
# =============================================================================
[[ -n "${_AID_RELEASE_SCOPE_SH_LOADED:-}" ]] && return 0
_AID_RELEASE_SCOPE_SH_LOADED=1

# AID-RELEASE-SCOPE-PORTABLE-START
# Everything between these markers is COPIED VERBATIM into
# defaults/hooks/pre-push, which cannot source this file: it runs inside the
# consumer's repository, where the plugin cache is not on any path it knows.
# Two copies of a decision are how two answers start; the copy is therefore
# byte-compared by test-release-scope.bats, and that test is written first.
#
# Nothing in this region may source another library or read a `.aid-o` path
# through a helper that lives outside it.

# _aid_rs_match <path> <newline-separated globs>
#   Exact path or directory-prefix match — the same shape defaults/hooks/pre-commit
#   already uses for its staged-file scope, so one idea of "is this path in the
#   list" exists in the plugin rather than two.
_aid_rs_match() {
  local _f="$1" _s
  while IFS= read -r _s; do
    [[ -z "$_s" ]] && continue
    [[ "$_f" == "$_s" || "$_f" == "$_s"/* ]] && return 0
  done <<< "$2"
  return 1
}

# _aid_rs_cfg <root> <key> — one list from .aid-o/config/project.yaml's
# `versioning` section, one entry per line. Exit 1 when it cannot be read at
# all: that is the fail-open signal, not an empty list.
_aid_rs_cfg() {
  local root="$1" key="$2" out=""
  command -v yq >/dev/null 2>&1 || return 1
  local cfg="${root%/}/.aid-o/config/project.yaml"
  [[ -f "$cfg" ]] || return 1
  # `.a[]?` alone, never `// empty`: mikefarah yq has no jq `empty`, and the
  # expression it cannot lex makes the whole read fail — which fails OPEN, so
  # a configured project would have silently kept the old label behaviour.
  out="$(yq -r ".versioning.${key}[]?" "$cfg" 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# _aid_rs_commits <root> <start> <end>
#   The commits in the range MINUS the ones carrying a `No-Release:` footer.
#   The footer's value must be non-empty: the point is an auditable reason, and
#   a bare `No-Release:` is a switch, not a reason.
_aid_rs_commits() {
  local root="$1" start="$2" end="$3" sha
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    if git -C "$root" log -1 --format=%B "$sha" 2>/dev/null \
       | grep -qE '^No-Release:[[:space:]]*[^[:space:]]'; then
      continue
    fi
    printf '%s\n' "$sha"
  done < <(git -C "$root" rev-list "${start}..${end}" 2>/dev/null)
}

# _aid_rs_paths <root> <sha> — the paths ONE commit touched.
#   The flags are load-bearing and therefore live in exactly one place:
#   `--first-parent -m` is what makes a merge commit contribute only its own
#   diff, and `--no-renames` is what keeps a rename from looking like an
#   unrelated new path. Written three times, they drift, and then the list of
#   culprits stops agreeing with the verdict it is explaining.
_aid_rs_paths() {
  git -C "$1" show --name-only --no-renames --first-parent -m --format='' "$2" 2>/dev/null \
    | sed '/^$/d'
}

# aid_release_scope_start <root> [rev]
#   The last version tag REACHABLE FROM <rev> — a verifiable statement about
#   what was released at that point. Nothing (exit 1) when the repository has
#   never been tagged.
#
#   `[rev]` is not decoration. `git describe` with no revision answers about
#   HEAD, and a pre-push hook judging `git push origin B:main` asks about B.
#   With a later tag on HEAD, HEAD's tag is not an ancestor of B, so `tag..B`
#   came out EMPTY and the push passed — the range has to be measured from the
#   commit actually being pushed.
aid_release_scope_start() {
  local root="$1" rev="${2:-HEAD}" tag
  tag="$(git -C "$root" describe --tags --abbrev=0 "$rev" 2>/dev/null)" || tag=""
  [[ -n "$tag" ]] || return 1
  printf '%s' "$tag"
}

# aid_release_scope_evaluate <root> <start> <end>
#   Fills three globals and returns 0. Split from the printers so the report
#   and the one-word verdict cannot disagree by being computed twice.
#     _AID_RS_VERDICT    no_config | no_tag | no_commits | exempt | release_required
#     _AID_RS_COMMITS    the commits the range KEPT, one sha per line — published
#                        so a caller that needs them does not re-walk the range
#                        through a private helper of this file
#     _AID_RS_CULPRITS   "<sha> <subject>" lines that put a path in scope
#     _AID_RS_WARNINGS   lines that never block
aid_release_scope_evaluate() {
  local root="$1" start="$2" end="$3"
  _AID_RS_VERDICT=""; _AID_RS_CULPRITS=""; _AID_RS_WARNINGS=""; _AID_RS_COMMITS=""

  # NEVER RELEASED IS ITS OWN ANSWER. An empty `start` used to mean the root of
  # history, and `root..HEAD` EXCLUDES the root commit — so a repository whose
  # single commit was the whole application reported "no commits" and passed.
  # An untagged repository is waved through (the inherited direction, and a
  # first push should not demand a release), but it is now waved through
  # EXPLICITLY, with a verdict a caller can print.
  if [[ -z "$start" ]]; then
    _AID_RS_VERDICT="no_tag"
    _AID_RS_WARNINGS="this repository has no version tag, so there is no released state to compare against; the release guard passes and will start deciding after the first tag."
    return 0
  fi

  local exempt app
  if ! exempt="$(_aid_rs_cfg "$root" release_exempt_paths)"; then
    _AID_RS_VERDICT="no_config"
    _AID_RS_WARNINGS="versioning.release_exempt_paths is not set in .aid-o/config/project.yaml (or yq is unavailable), so the release guard is deciding by commit label as it did before. Run /aid-setup to fill it in."
    return 0
  fi
  app="$(_aid_rs_cfg "$root" app_paths)" || app=""

  local -a shas=()
  local sha
  while IFS= read -r sha; do [[ -n "$sha" ]] && shas+=("$sha"); done < <(_aid_rs_commits "$root" "$start" "$end")
  if (( ${#shas[@]} == 0 )); then
    _AID_RS_VERDICT="no_commits"
    return 0
  fi
  _AID_RS_COMMITS="$(printf '%s\n' "${shas[@]}")"

  # ONE walk of the range. Each commit's paths are read once and kept, because
  # the same three questions — is the union exempt, which commits put a path
  # outside it, which housekeeping commit touched the application — are all
  # asked of the same data. Asking git again per question cost one process per
  # commit per question, on the push path.
  local -A _paths_of=() _outside=()
  local p
  for sha in "${shas[@]}"; do
    _paths_of["$sha"]="$(_aid_rs_paths "$root" "$sha")"
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      _aid_rs_match "$p" "$exempt" || _outside["$p"]=1
    done <<< "${_paths_of[$sha]}"
  done

  if (( ${#_outside[@]} == 0 )); then
    _AID_RS_VERDICT="exempt"
  else
    _AID_RS_VERDICT="release_required"
    # WHO caused it: the commits that touched at least one path outside the
    # exempt list. A refusal that only says "something" is a refusal nobody can
    # act on.
    local subj cp
    for sha in "${shas[@]}"; do
      while IFS= read -r cp; do
        [[ -n "$cp" ]] || continue
        if [[ -n "${_outside[$cp]:-}" ]]; then
          subj="$(git -C "$root" log -1 --format=%s "$sha" 2>/dev/null)"
          _AID_RS_CULPRITS+="${sha:0:8} ${subj}"$'\n'
          break
        fi
      done <<< "${_paths_of[$sha]}"
    done
  fi

  # Warnings never block. The label is kept for exactly this: telling the PM
  # that a commit calling itself housekeeping touched the application.
  if [[ -n "$app" ]]; then
    # The pattern is a VARIABLE, not a literal: an unquoted `(` inside a
    # bracket expression makes bash's `[[ ]]` parser read it as a subshell.
    local msubj mp
    local housekeeping='^(chore|docs|test|style|ci)[(:]'
    for sha in "${shas[@]}"; do
      msubj="$(git -C "$root" log -1 --format=%s "$sha" 2>/dev/null)"
      [[ "$msubj" =~ $housekeeping ]] || continue
      while IFS= read -r mp; do
        [[ -n "$mp" ]] || continue
        if _aid_rs_match "$mp" "$app"; then
          _AID_RS_WARNINGS+="${sha:0:8} calls itself housekeeping (\"${msubj}\") but touched ${mp}"$'\n'
          break
        fi
      done <<< "${_paths_of[$sha]}"
    done
  fi
  return 0
}

# aid_release_scope_report <root> <start> <end> — the verdict plus the reasons.
aid_release_scope_report() {
  aid_release_scope_evaluate "$@" || return 1
  printf 'verdict: %s\n' "$_AID_RS_VERDICT"
  local l
  while IFS= read -r l; do [[ -n "$l" ]] && printf 'commit: %s\n' "$l"; done <<< "$_AID_RS_CULPRITS"
  while IFS= read -r l; do [[ -n "$l" ]] && printf 'warn: %s\n' "$l"; done <<< "$_AID_RS_WARNINGS"
  return 0
}
# AID-RELEASE-SCOPE-PORTABLE-END
