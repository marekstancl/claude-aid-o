#!/usr/bin/env bash
# =============================================================================
# lib/aid-parallel-dispatch.sh — whether a wave runs at once, and how its
# work comes back together (P087 Step 4)
#
#   aid_parallel_decide        <plan.md> <orchestration.yaml> <wave_name> <wave_size> [tree_root]
#   aid_parallel_step_worktree <tree_root> <step_id> <base_ref> [worktree_base]
#   aid_parallel_step_reset    <tree_root> <step_id> <base_ref> [worktree_base]
#   aid_parallel_merge         <tree_root> <step_branch> [worktree_base]
#
# WHY THIS EXISTS
#   The concurrent path was written in 0.2.0 and never ran: `max_parallel: 1`
#   was a TEMPORARY brake with three named reasons, and the reasons are now
#   owned elsewhere — the dispatch contract (Step 1) proves what an agent
#   received and returned, the per-step commit (Step 2) makes a mega-commit
#   impossible, and the wave check (Step 3) proves disjointness in files AND
#   interfaces. What is left is the two decisions the controller has to make
#   by code, not by feel: MAY this wave run at once, and what happens when
#   its branches do not merge cleanly.
#
# THE DECISION NEVER REFUSES A RUN
#   `decide` prints `concurrent slots=<n>` or `serial: <why>` and exits 0
#   either way. Every failure mode — the wave has a collision, the check
#   cannot run, the brake is on, the strategy is not worktrees, git cannot
#   hand out worktrees, a wave of one — degrades
#   to the sequential path that has always worked. A wave that cannot be
#   proved safe is not run blind; it is run in order, and the reason is on
#   stdout for the timeline.
#
# A CONFLICT IS A RETRY, NOT A STOP
#   `merge` brings one step's branch into the tree. A clean merge prints the
#   SHA. A conflict is aborted, the tree is left exactly as before, and exit 1
#   tells the controller to reset THAT step's tree onto the new base and
#   repeat it — isolation
#   turned a corrupted tree into a repeatable event, which is the whole
#   premise. Two failures of the same step are the recovery policy's business
#   (defaults/policies/auto-recovery.yaml), not this file's.
#
# NO top-level `set -e` — sourced under the caller's own strict shell.
#
# **Last Updated:** 2026-08-25
# =============================================================================
[[ -n "${_AID_PARALLEL_DISPATCH_SH_LOADED:-}" ]] && return 0
_AID_PARALLEL_DISPATCH_SH_LOADED=1

_AID_PD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Where a step's worktree lives: `<worktree_base>/step-<step_id>`, the base
# from `dispatch.worktree_base` (default `.aid-worktrees`, gitignored by the
# `/aid-init` template). Derivable from the step id alone.
_AID_PD_DEFAULT_BASE='.aid-worktrees'
_aid_pd_step_worktree_path() { printf '%s/%s/step-%s' "$1" "${3:-$_AID_PD_DEFAULT_BASE}" "$2"; }
_aid_pd_step_branch()        { printf 'step/%s' "$1"; }

# ---------------------------------------------------------------------------
# aid_parallel_decide <plan.md> <orchestration.yaml> <wave_name> <wave_size> [tree_root]
#   stdout: `concurrent slots=<max_parallel>` | `serial: <reason>`
#   exit 0 always (2 = usage)
#
#   `slots` is the ceiling on agents in flight: a wave larger than it is still
#   concurrent, in batches of that many — the controller dispatches the next
#   step of the wave as a slot frees.
# ---------------------------------------------------------------------------
aid_parallel_decide() {
  local plan="${1:?decide: plan file required}" cfg="${2:?decide: orchestration.yaml required}" wave="${3:?decide: wave name required}" size="${4:?decide: wave size required}" root="${5:-.}"
  [[ "$size" =~ ^[0-9]+$ ]] || { echo "decide: wave size must be a number, got '${size}'" >&2; return 2; }

  if (( size < 2 )); then
    echo "serial: a wave of ${size} step(s) has nothing to run alongside"
    return 0
  fi

  local max=1 strategy=""
  if command -v yq >/dev/null 2>&1 && [[ -r "$cfg" ]]; then
    max="$(yq -r '.dispatch.max_parallel // 1' "$cfg" 2>/dev/null)"
    [[ "$max" =~ ^[0-9]+$ ]] || max=1
    strategy="$(yq -r '.dispatch.strategy // "worktrees"' "$cfg" 2>/dev/null)"
  else
    echo "serial: ${cfg} is unreadable or yq is missing — the brake setting cannot be read, so it is treated as on"
    return 0
  fi
  if [[ "$strategy" != "worktrees" ]]; then
    echo "serial: dispatch.strategy is ${strategy} — only worktrees isolate a step"
    return 0
  fi
  if (( max < 2 )); then
    echo "serial: dispatch.max_parallel is ${max}"
    return 0
  fi

  if ! git -C "$root" worktree list >/dev/null 2>&1; then
    echo "serial: ${root} cannot hand out worktrees — no isolation, no concurrency"
    return 0
  fi

  # The wave check, blocking mode, over THIS wave of the plan as it is now.
  # Its own output is the reason: the finding names both steps and what they
  # share.
  local out rc=0
  out="$(bash "${_AID_PD_LIB_DIR}/../aid-plan-parallel-check.sh" "$plan" --group "$wave" 2>&1)" || rc=$?
  case "$rc" in
    0) echo "concurrent slots=${max}"; return 0 ;;
    1) echo "serial: wave ${wave} has a collision — $(printf '%s' "$out" | grep -m1 -E 'not disjoint|shares an interface' || echo 'see aid-plan-parallel-check.sh')"; return 0 ;;
    *) echo "serial: the wave check could not run (exit ${rc}) — never concurrent blind"; return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# aid_parallel_step_worktree <tree_root> <step_id> <base_ref> [worktree_base]
#   Gives one step its own tree on branch `step/<step_id>` AT <base_ref>.
#   Prints the path. A live worktree for the step is returned as it is
#   (idempotent). A branch left over from an earlier run with no live tree is
#   RESET to <base_ref> — a step never starts on another run's leftovers.
#   Exit 1 when git refuses (its message is passed through). Never deletes.
# ---------------------------------------------------------------------------
aid_parallel_step_worktree() {
  local root="${1:?worktree: tree root required}" step="${2:?worktree: step id required}" base="${3:?worktree: base ref required}" wbase="${4:-$_AID_PD_DEFAULT_BASE}"
  local wt branch; wt="$(_aid_pd_step_worktree_path "$root" "$step" "$wbase")"; branch="$(_aid_pd_step_branch "$step")"
  git -C "$root" worktree prune >/dev/null 2>&1 || true
  if [[ -d "$wt" ]] && git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$wt"; return 0
  fi
  mkdir -p "$(dirname "$wt")" 2>/dev/null || true
  local err
  err="$(git -C "$root" worktree add -B "$branch" "$wt" "$base" 2>&1)" \
    || { echo "worktree: git refused ${wt} on ${branch} at ${base}: ${err}" >&2; return 1; }
  printf '%s\n' "$wt"
}

# ---------------------------------------------------------------------------
# aid_parallel_step_reset <tree_root> <step_id> <base_ref> [worktree_base]
#   The retry after a conflict: the step's tree is put back on <base_ref>
#   (the base that moved) so the step can be dispatched again against it.
#   A tree with uncommitted work is NOT reset — it is named and kept, because
#   the work in it has not been looked at yet. Exit 1 in that case or when
#   git refuses.
# ---------------------------------------------------------------------------
aid_parallel_step_reset() {
  local root="${1:?reset: tree root required}" step="${2:?reset: step id required}" base="${3:?reset: base ref required}" wbase="${4:-$_AID_PD_DEFAULT_BASE}"
  local wt branch; wt="$(_aid_pd_step_worktree_path "$root" "$step" "$wbase")"; branch="$(_aid_pd_step_branch "$step")"
  [[ -d "$wt" ]] || { echo "reset: no worktree at ${wt} — create it with aid_parallel_step_worktree" >&2; return 1; }
  if [[ -n "$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" ]]; then
    echo "reset: ${wt} holds uncommitted work — kept for inspection, not reset; commit or discard it by hand first" >&2
    return 1
  fi
  # <base_ref> means what it means in the ROOT tree — `HEAD` in the step's
  # own tree is the commit that just failed to merge.
  local sha err
  sha="$(git -C "$root" rev-parse --verify "${base}^{commit}" 2>/dev/null)" || { echo "reset: ${base} is not a commit in ${root}" >&2; return 1; }
  err="$(git -C "$wt" checkout -q -B "$branch" "$sha" 2>&1)" || { echo "reset: git refused: ${err}" >&2; return 1; }
  git -C "$wt" rev-parse HEAD
}

# ---------------------------------------------------------------------------
# aid_parallel_merge <tree_root> <step_branch> [worktree_base]
#   0  merged — prints the merge SHA; the step's worktree is removed when it
#      is clean (a dirty one is kept and named) and its branch is kept, so the
#      history stays inspectable
#   1  conflict — the merge is ABORTED, the tree is untouched, and the reason
#      names the files; the caller resets the step (aid_parallel_step_reset)
#      and repeats it against the new base
#   2  git refused for another reason (message passed through)
# ---------------------------------------------------------------------------
aid_parallel_merge() {
  local root="${1:?merge: tree root required}" branch="${2:?merge: step branch required}" wbase="${3:-$_AID_PD_DEFAULT_BASE}"
  git -C "$root" show-ref --verify --quiet "refs/heads/${branch}" || { echo "merge: no branch ${branch} in ${root}" >&2; return 2; }
  if ! git -C "$root" diff --quiet || ! git -C "$root" diff --cached --quiet; then
    echo "merge: ${root} has uncommitted changes — the controller merges into a clean tree only" >&2
    return 2
  fi
  local err rc=0
  err="$(git -C "$root" merge --no-ff --no-edit "$branch" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    local conflicted
    conflicted="$(git -C "$root" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')"
    git -C "$root" merge --abort >/dev/null 2>&1 || true
    if [[ -n "$conflicted" ]]; then
      echo "merge: ${branch} conflicts with the current base in: ${conflicted}— aborted, tree untouched; repeat the step against the new base" >&2
      return 1
    fi
    echo "merge: git refused ${branch}: ${err}" >&2
    return 2
  fi
  # The step's tree is removed only when git agrees it is clean; anything the
  # agent left uncommitted stays on disk to be looked at, never deleted.
  local step="${branch#step/}" wt; wt="$(_aid_pd_step_worktree_path "$root" "$step" "$wbase")"
  if [[ -d "$wt" ]] && ! git -C "$root" worktree remove "$wt" >/dev/null 2>&1; then
    echo "merge: ${wt} was kept — it holds uncommitted work; inspect it, then: git worktree remove '${wt}'" >&2
  fi
  git -C "$root" rev-parse HEAD
}
