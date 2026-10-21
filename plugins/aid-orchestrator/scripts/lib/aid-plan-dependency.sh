# shellcheck shell=bash
# aid-plan-dependency.sh — a plan that stands on ONE unmerged plan (P117 (3); WAN P112: CP1 prepare checked the
# paths against the main checkout, where the dependency's files do not exist yet, and refused real work).
#
# The plan's paths are checked against the dependency's worktree; the binding (plan, worktree, branch, HEAD) is
# recorded in the state root's evidence and checked again: by every later CP1 round (the dependency must not move
# under a review) and by plan-run (what CP1 reviewed must be on the target branch once the dependency closed).
# Unmerged = its branch plan/<id> exists and is not in the target branch (git decides, not the plan's lifecycle
# record: a plan built outside AID and merged by hand reads legacy-unverifiable, never closed). Its worktree is
# the one git has checked out on that branch. Needs lib/aid-lifecycle.sh (_aid_lc_frontmatter_depends,
# aid_target_branch).
#
#   aid_plan_dep_resolve <state_root> <plan_file>
#       DEP_ROOT = the root to check the plan's paths against (the state root, or the dependency's worktree),
#       DEP_JSON = the binding ({} without an unmerged dependency). Exit 1 with DEP_WHY/DEP_NEXT/DEP_CODE set
#       when there are several unmerged dependencies or the one has no usable worktree.
#   aid_plan_dep_binding_file <state_root> <plan_id>
#   aid_plan_dep_verify <state_root> <plan_id> <when: review|run> — exit 1 (DEP_WHY/DEP_NEXT/DEP_CODE) when the
#       recorded binding no longer holds; 0 without one.

aid_plan_dep_binding_file() { printf '%s/.aid-o/work/evidence/%s/dependency-root.json' "$1" "$2"; }

_aid_pd_unmerged() {   # <root> <plan_id> — its plan branch exists and the target branch does not contain it
  local tb; tb="$(cd "$1" && aid_target_branch 2>/dev/null || echo main)"
  git -C "$1" rev-parse -q --verify "refs/heads/plan/$2" >/dev/null || return 1
  ! git -C "$1" merge-base --is-ancestor "refs/heads/plan/$2" "$tb" 2>/dev/null
}
_aid_pd_worktree() {   # <root> <branch> — the worktree git has on that branch
  git -C "$1" worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$2" '/^worktree /{w=substr($0,10)} $0==b{print w; exit}'
}

aid_plan_dep_resolve() {
  local root="$1" plan="$2" dep open=() wt br head
  DEP_ROOT="$root" DEP_JSON='{}' DEP_WHY="" DEP_NEXT="" DEP_CODE=""
  while IFS= read -r dep; do
    [[ -n "$dep" && "$dep" != null ]] || continue
    _aid_pd_unmerged "$root" "$dep" && open+=("$dep")
  done < <(_aid_lc_frontmatter_depends "$plan")
  (( ${#open[@]} == 0 )) && return 0
  if (( ${#open[@]} > 1 )); then
    DEP_CODE=dependency_roots_many
    DEP_WHY="the plan stands on ${#open[@]} unmerged plans (${open[*]}) — its paths can be checked against one worktree only"
    DEP_NEXT="close all but one of ${open[*]} first, or split the plan so it stands on one"
    return 1
  fi
  dep="${open[0]}"; br="plan/${dep}"; wt="$(_aid_pd_worktree "$root" "$br")"
  if [[ -z "$wt" || ! -d "$wt" ]]; then
    DEP_CODE=dependency_worktree_missing
    DEP_WHY="${dep} is not merged and no worktree has ${br} checked out"
    DEP_NEXT="aid-plan-fsm.sh plan-state ${dep} --recreate-worktree --reason \"<why it went missing>\", then prepare again"
    return 1
  fi
  head="$(git -C "$wt" rev-parse HEAD)"
  DEP_ROOT="$wt"
  DEP_JSON="$(jq -cn --arg p "$dep" --arg w "$wt" --arg b "$br" --arg h "$head" '{plan: $p, worktree: $w, branch: $b, head: $h}')"
}

aid_plan_dep_verify() {
  local root="$1" id="$2" when="$3" f dep wt br head now tb
  DEP_WHY="" DEP_NEXT="" DEP_CODE=""
  f="$(aid_plan_dep_binding_file "$root" "$id")"; [[ -f "$f" ]] || return 0
  dep="$(jq -r .plan "$f")" wt="$(jq -r .worktree "$f")" br="$(jq -r .branch "$f")" head="$(jq -r .head "$f")"
  if [[ "$when" == run ]] && ! _aid_pd_unmerged "$root" "$dep"; then
    tb="$(aid_target_branch 2>/dev/null || echo main)"
    git -C "$root" merge-base --is-ancestor "$head" "$tb" 2>/dev/null && return 0
    DEP_CODE=dependency_moved
    DEP_WHY="CP1 checked ${id} against ${dep} at ${head:0:12}, and ${tb} does not contain that commit — ${dep} changed after the review"
    DEP_NEXT="review ${id} again (CP1) against what ${dep} merged"
    return 1
  fi
  now="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if [[ ! -d "$wt" || "$(git -C "$wt" branch --show-current 2>/dev/null)" != "$br" ]]; then
    DEP_CODE=dependency_worktree_missing
    DEP_WHY="the worktree ${wt} of ${dep}, which CP1 of ${id} checked against, is not there on ${br}"
    DEP_NEXT="aid-plan-fsm.sh plan-state ${dep} --recreate-worktree --reason \"<why>\", then start the review of ${id} again (prepare --round 1 --restart)"
    return 1
  fi
  [[ "$now" == "$head" ]] && return 0
  DEP_CODE=dependency_moved
  DEP_WHY="${dep} moved from ${head:0:12} to ${now:0:12} since CP1 of ${id} was prepared against it"
  DEP_NEXT="start the review of ${id} again against the new state (prepare --round 1 --restart)"
  return 1
}
