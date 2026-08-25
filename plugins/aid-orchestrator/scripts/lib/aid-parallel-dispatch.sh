#!/usr/bin/env bash
# =============================================================================
# lib/aid-parallel-dispatch.sh — whether a wave runs at once, and how its
# work comes back together (P087 Step 4)
#
#   aid_parallel_decide        <plan.md> <orchestration.yaml> <wave_size> [tree_root]
#   aid_parallel_step_worktree <tree_root> <step_id> <base_ref>
#   aid_parallel_merge         <tree_root> <step_branch>
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
#   `decide` prints `concurrent` or `serial: <why>` and exits 0 either way.
#   Every failure mode — the check finds a collision, the check cannot run,
#   the brake is on, git cannot hand out worktrees, a wave of one — degrades
#   to the sequential path that has always worked. A wave that cannot be
#   proved safe is not run blind; it is run in order, and the reason is on
#   stdout for the timeline.
#
# A CONFLICT IS A RETRY, NOT A STOP
#   `merge` brings one step's branch into the tree. A clean merge prints the
#   SHA. A conflict is aborted, the tree is left exactly as before, and exit 1
#   tells the controller to repeat THAT step against the new base — isolation
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

# Where a step's worktree lives, beside the plan worktrees and gitignored by
# the same `/aid-init` template line. Derivable from the step id alone.
_aid_pd_step_worktree_path() { printf '%s/.aid-worktrees/step-%s' "$1" "$2"; }
_aid_pd_step_branch()        { printf 'step/%s' "$1"; }

# ---------------------------------------------------------------------------
# aid_parallel_decide <plan.md> <orchestration.yaml> <wave_size> [tree_root]
#   stdout: `concurrent` | `serial: <reason>`     exit 0 always (2 = usage)
# ---------------------------------------------------------------------------
aid_parallel_decide() {
  local plan="${1:?decide: plan file required}" cfg="${2:?decide: orchestration.yaml required}" size="${3:?decide: wave size required}" root="${4:-.}"
  [[ "$size" =~ ^[0-9]+$ ]] || { echo "decide: wave size must be a number, got '${size}'" >&2; return 2; }

  if (( size < 2 )); then
    echo "serial: a wave of ${size} step(s) has nothing to run alongside"
    return 0
  fi

  local max=1
  if command -v yq >/dev/null 2>&1 && [[ -r "$cfg" ]]; then
    max="$(yq -r '.dispatch.max_parallel // 1' "$cfg" 2>/dev/null)"
    [[ "$max" =~ ^[0-9]+$ ]] || max=1
  else
    echo "serial: ${cfg} is unreadable or yq is missing — the brake setting cannot be read, so it is treated as on"
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

  # The wave check, blocking mode, over the plan AS IT IS NOW. Its own output
  # is the reason: the finding names both steps and what they share.
  local out rc=0
  out="$(bash "${_AID_PD_LIB_DIR}/../aid-plan-parallel-check.sh" "$plan" 2>&1)" || rc=$?
  case "$rc" in
    0) echo "concurrent"; return 0 ;;
    1) echo "serial: the wave check found a collision — $(printf '%s' "$out" | grep -m1 -E 'not disjoint|shares an interface' || echo 'see aid-plan-parallel-check.sh')"; return 0 ;;
    *) echo "serial: the wave check could not run (exit ${rc}) — never concurrent blind"; return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# aid_parallel_step_worktree <tree_root> <step_id> <base_ref>
#   Gives one step its own tree on branch `step/<step_id>` at <base_ref>.
#   Prints the path. Idempotent for an existing registration; exit 1 when git
#   refuses (its message is passed through). Never deletes anything.
# ---------------------------------------------------------------------------
aid_parallel_step_worktree() {
  local root="${1:?worktree: tree root required}" step="${2:?worktree: step id required}" base="${3:?worktree: base ref required}"
  local wt branch; wt="$(_aid_pd_step_worktree_path "$root" "$step")"; branch="$(_aid_pd_step_branch "$step")"
  git -C "$root" worktree prune >/dev/null 2>&1 || true
  if [[ -d "$wt" ]] && git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "$wt"; return 0
  fi
  mkdir -p "$(dirname "$wt")" 2>/dev/null || true
  local err
  if git -C "$root" show-ref --verify --quiet "refs/heads/${branch}"; then
    err="$(git -C "$root" worktree add "$wt" "$branch" 2>&1)" || { echo "worktree: git refused ${wt} on ${branch}: ${err}" >&2; return 1; }
  else
    err="$(git -C "$root" worktree add -b "$branch" "$wt" "$base" 2>&1)" || { echo "worktree: git refused ${wt} on new ${branch} at ${base}: ${err}" >&2; return 1; }
  fi
  printf '%s\n' "$wt"
}

# ---------------------------------------------------------------------------
# aid_parallel_merge <tree_root> <step_branch>
#   0  merged — prints the merge SHA; the step's worktree is removed when it
#      is clean (a dirty one is kept and named) and its branch is kept, so the
#      history stays inspectable
#   1  conflict — the merge is ABORTED, the tree is untouched, and the reason
#      names the files; the caller repeats the step against the new base
#   2  git refused for another reason (message passed through)
# ---------------------------------------------------------------------------
aid_parallel_merge() {
  local root="${1:?merge: tree root required}" branch="${2:?merge: step branch required}"
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
  local step="${branch#step/}" wt; wt="$(_aid_pd_step_worktree_path "$root" "$step")"
  if [[ -d "$wt" ]] && ! git -C "$root" worktree remove "$wt" >/dev/null 2>&1; then
    echo "merge: ${wt} was kept — it holds uncommitted work; inspect it, then: git worktree remove '${wt}'" >&2
  fi
  git -C "$root" rev-parse HEAD
}
