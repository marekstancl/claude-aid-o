#!/usr/bin/env bash
# =============================================================================
# aid-repo-roots.sh — the ONE mapping of a plan's foreign repositories (P112).
#
# A plan that declares `repo_roots` works in each foreign repository through a
# worktree `<path>/.aid-worktrees/plan-<id>--<name>` on the branch
# `plan/<id>-<project>` (P111). Every reader of a step's files or of a brief
# point — the step contract, the step check, the review packets, the measurer
# and the lint — asks this file which worktree a path lives in, so none of them
# can read the live checkout by forgetting the rewrite (Agents P016, 12. 10. 2026).
#
#   aid_rr_entries <src> [<plan_id> <project>]  TSV name\tpath\tworktree\tbranch
#       <src> is a plan.json (its repo_roots[]) or a plan file (its frontmatter;
#       plan_id defaults to its `id:`, project to the state root's basename).
#   aid_rr_load <src> [<plan_id> <project>]     caches the entries in this shell
#   aid_rr_phys_repo <path>                     physical toplevel of the repo a
#                                               (maybe not yet existing) path is in
#   aid_rr_path <src> <path>                    the same path in the worktree;
#                                               exit 3 when that worktree is gone
#   aid_rr_text <src> <text>                    every declared path in a command
#                                               text rewritten, longest first
#   aid_rr_resolve <plan.json> <slug>           "<worktree>\t<branch>"
#   aid_rr_rewrite_files <plan.json> <paths-json>  the step contract's rewrite
#
# Sources nothing that writes; needs jq, yq, git, realpath.
# =============================================================================

[[ -n "${_AID_RR_LOADED:-}" ]] && return 0
_AID_RR_LOADED=1
_AID_RR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_RR_LIB_DIR}/aid-roots.sh"   # aid_state_root

_AID_RR_CACHE_KEY=""
_AID_RR_CACHE=""

# aid_plan_repo_roots_raw <plan> — the frontmatter `repo_roots` list as JSON
# ([] when absent).
aid_plan_repo_roots_raw() {
  local out
  out="$(yq --front-matter=extract -o=json '.repo_roots // []' "$1" 2>/dev/null)" || out="[]"
  [[ -n "$out" && "$out" != "null" ]] || out="[]"
  jq -c 'if type == "array" then . else [] end' <<< "$out" 2>/dev/null || echo '[]'
}

# aid_plan_repo_base_branch <path> [<base_branch>] — the foreign base branch:
# the declared one, else what origin/HEAD points at, else main.
aid_plan_repo_base_branch() {
  local path="$1" bb="${2:-}"
  if [[ -z "$bb" ]]; then
    bb="$(git -C "$path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || bb=""
    [[ -n "$bb" ]] || bb="main"
  fi
  printf '%s\n' "$bb"
}

# _aid_rr_derive <path> <plan_id> <name> <project> — "<worktree>\t<branch>",
# the one spelling plan-run creates and every reader expects.
_aid_rr_derive() {
  printf '%s\t%s\n' "${1}/.aid-worktrees/plan-${2}--${3}" "plan/${2}-${4}"
}

# aid_rr_phys_repo <path> — the physical toplevel of the git repository a
# (possibly not yet existing) path lies in, or nothing.
aid_rr_phys_repo() {
  local d="$1"
  while [[ -n "$d" && ! -d "$d" ]]; do d="${d%/*}"; done
  [[ -n "$d" ]] || d=/
  # "or nothing" includes a path outside any repository: under pipefail the failed rev-parse must not
  # fail the caller (aid-step-check.sh exited 128 with no word, aidlab-apps 16. 10. 2026)
  ( cd "$d" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null ) | xargs -r realpath 2>/dev/null || true
}

# aid_rr_entries <src> [<plan_id> <project>] — see the header. A declared path
# that is not a git repository prints nothing for it, a line on stderr, exit 1
# (the lint and plan-run refuse that plan as repo_root_invalid; readers never
# guess). No repo_roots → no output, exit 0.
aid_rr_entries() {
  local src="$1" pid="${2:-}" proj="${3:-}" first raw n i name path rc=0
  [[ -r "$src" ]] || return 0
  first="$(head -c 1 "$src" 2>/dev/null)"
  if [[ "$first" == "{" ]]; then
    jq -r '.repo_roots[]? | [.name, .path, .worktree, .branch] | @tsv' "$src" 2>/dev/null
    return 0
  fi
  raw="$(aid_plan_repo_roots_raw "$src")"
  n="$(jq 'length' <<< "$raw")"
  (( n > 0 )) || return 0
  [[ -n "$pid" ]] || pid="$(yq --front-matter=extract -r '.id // ""' "$src" 2>/dev/null)"
  [[ -n "$proj" ]] || proj="$(basename "$(aid_state_root 2>/dev/null || pwd)")"
  for (( i=0; i<n; i++ )); do
    name="$(jq -r --argjson i "$i" '.[$i].name // ""' <<< "$raw")"
    path="$(jq -r --argjson i "$i" '.[$i].path // ""' <<< "$raw")"
    if ! path="$(realpath -e "$path" 2>/dev/null)" || [[ "$(aid_rr_phys_repo "$path")" != "$path" ]]; then
      echo "repo_roots '${name}': $(jq -r --argjson i "$i" '.[$i].path // ""' <<< "$raw") is not the top of a git repository" >&2
      rc=1; continue
    fi
    printf '%s\t%s\t%s\n' "$name" "$path" "$(_aid_rr_derive "$path" "$pid" "$name" "$proj")"
  done
  return "$rc"
}

# aid_rr_load <src> [<plan_id> <project>] — computes the entries once for this
# shell; aid_rr_path/aid_rr_text with the same <src> reuse them (a measurer
# rewrites every point of a plan).
aid_rr_load() {
  _AID_RR_CACHE="$(aid_rr_entries "$@")" || { _AID_RR_CACHE_KEY=""; return 1; }
  _AID_RR_CACHE_KEY="$1"
}

_aid_rr_get() {
  if [[ -n "$_AID_RR_CACHE_KEY" && "$1" == "$_AID_RR_CACHE_KEY" ]]; then
    printf '%s' "$_AID_RR_CACHE"
  else
    aid_rr_entries "$1" 2>/dev/null
  fi
}

# aid_rr_path <src> <path> — a path whose physical repository is a declared
# one → the same relative path under its worktree; any other path unchanged.
# Exit 3 (path still printed) when the mapped worktree does not exist, so a
# reader fails closed instead of reading the live checkout.
aid_rr_path() {
  local src="$1" p="$2" repo name path wt br pp hit=""
  [[ "$p" == /* ]] || { printf '%s\n' "$p"; return 0; }
  repo="$(aid_rr_phys_repo "$p")"
  if [[ -n "$repo" ]]; then
    while IFS=$'\t' read -r name path wt br; do
      [[ -n "$name" && "$repo" == "$path" ]] || continue
      pp="$(realpath -m "$p")"
      hit="${wt}${pp#"$path"}"
      [[ "$p" == */ ]] && hit="${hit%/}/"
      break
    done <<< "$(_aid_rr_get "$src")"
  fi
  if [[ -z "$hit" ]]; then printf '%s\n' "$p"; return 0; fi
  printf '%s\n' "$hit"
  [[ -d "$wt" ]] || return 3
}

# aid_rr_text <src> <text> — every occurrence of a declared path as a whole
# path (not preceded by a path character, followed by `/`, a character that
# cannot be part of a name, or the end) replaced by its worktree, longest path
# first, in one pass: `/x/docs-backup/f` and `/tmp/archive/x/docs/f` stay when
# only `/x/docs` is declared. Exit 3 (text still printed) when a rewritten
# path's worktree is gone.
aid_rr_text() {
  local src="$1" text="$2" ents name path wt br i rc=0 res t pre post prev next k
  local -a paths=() wts=()
  ents="$(_aid_rr_get "$src")"
  [[ -n "$ents" ]] || { printf '%s\n' "$text"; return 0; }
  while IFS=$'\t' read -r _ path wt; do paths+=("$path"); wts+=("$wt"); done \
    < <(while IFS=$'\t' read -r name path wt br; do
          [[ -n "$name" ]] && printf '%d\t%s\t%s\n' "${#path}" "$path" "$wt"
        done <<< "$ents" | sort -t$'\t' -k1,1nr)
  t="$text"
  # Each match becomes a token \001<k>\001 (no path character in it, so a
  # shorter path can neither match inside it nor across it), then tokens → worktrees.
  for (( k=0; k<${#paths[@]}; k++ )); do
    path="${paths[$k]}"; res=""
    while [[ "$t" == *"$path"* ]]; do
      pre="${t%%"$path"*}"; post="${t#*"$path"}"
      prev="${pre: -1}"; next="${post:0:1}"
      if [[ ! "$prev" =~ [A-Za-z0-9._/-] && ! "$next" =~ [A-Za-z0-9._-] ]]; then
        res+="${pre}"$'\001'"${k}"$'\001'
      else
        res+="${pre}${path}"
      fi
      t="$post"
    done
    t="${res}${t}"
  done
  for (( k=0; k<${#paths[@]}; k++ )); do
    if [[ "$t" == *$'\001'"${k}"$'\001'* ]]; then
      [[ -d "${wts[$k]}" ]] || rc=3
      t="${t//$'\001'"${k}"$'\001'/${wts[$k]}}"
    fi
  done
  printf '%s\n' "$t"
  return "$rc"
}

# aid_rr_resolve <plan.json> <slug> — prints "<worktree>\t<branch>" of the
# repo_roots entry named <slug>. Exit 1 when the plan declares none.
aid_rr_resolve() {
  local out
  out="$(jq -r --arg n "$2" 'first(.repo_roots[]? | select(.name == $n) | [.worktree, .branch] | @tsv) // empty' "$1" 2>/dev/null)"
  [[ -n "$out" ]] || return 1
  printf '%s\n' "$out"
}

# aid_rr_rewrite_files <plan.json> <paths-json> — the paths with every one
# under a declared repo_roots path rewritten to its worktree. Refuses (exit 1,
# foreign_repo_undeclared) a path in a foreign git repository the plan does not
# declare, and a declared one whose worktree is gone.
aid_rr_rewrite_files() {
  local plan="$1" paths="$2" rr own out="[]" p repo n i rp wt hit
  rr="$(jq -c '.repo_roots // []' "$plan" 2>/dev/null || echo '[]')"
  own="$(aid_rr_phys_repo "$(dirname "$(realpath "$plan")")")"
  n="$(jq 'length' <<< "$rr")"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ "$p" != /* ]]; then out="$(jq -c --arg p "$p" '. + [$p]' <<< "$out")"; continue; fi
    repo="$(aid_rr_phys_repo "$p")"
    if [[ -z "$repo" || "$repo" == "$own" ]]; then out="$(jq -c --arg p "$p" '. + [$p]' <<< "$out")"; continue; fi
    hit=""
    for (( i=0; i<n; i++ )); do
      rp="$(realpath -m "$(jq -r --argjson i "$i" '.[$i].path' <<< "$rr")")"
      [[ "$repo" == "$rp" ]] || continue
      wt="$(jq -r --argjson i "$i" '.[$i].worktree' <<< "$rr")"
      if [[ ! -d "$wt" ]]; then
        echo "contract: the worktree ${wt} of repo_roots '$(jq -r --argjson i "$i" '.[$i].name' <<< "$rr")' is gone — no step is sent into ${rp}'s live checkout instead." >&2
        echo "next: recreate it on its recorded branch: git -C ${rp} worktree add ${wt} $(jq -r --argjson i "$i" '.[$i].branch' <<< "$rr")" >&2
        echo "(pipeline.md §When AID refuses: foreign_repo_undeclared)" >&2
        return 1
      fi
      # the physical spelling of p (symlinks, trailing slash), then the tail under the repo
      local pp; pp="$(realpath -m "$p")"
      hit="${wt}${pp#"$rp"}"
      [[ "$p" == */ ]] && hit="${hit%/}/"
      break
    done
    if [[ -z "$hit" ]]; then
      echo "contract: ${p} lies in ${repo}, a git repository outside the project that the plan does not declare in repo_roots — a direct run works in a foreign repository only through its worktree." >&2
      echo "next: declare it in the plan's frontmatter (repo_roots: [{name: <slug>, path: ${repo}}]) and restart the run, or drop the path from the step" >&2
      echo "(pipeline.md §When AID refuses: foreign_repo_undeclared)" >&2
      return 1
    fi
    out="$(jq -c --arg p "$hit" '. + [$p]' <<< "$out")"
  done < <(jq -r '.[]' <<< "$paths")
  printf '%s\n' "$out"
}
