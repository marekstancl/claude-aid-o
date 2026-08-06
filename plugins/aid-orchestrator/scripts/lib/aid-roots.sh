#!/usr/bin/env bash
# =============================================================================
# aid-roots.sh — shared invoke-root / state-root resolution (P074 Step 1).
#
# WHY THIS EXISTS: a linked `git worktree` has its OWN working directory, but
# `.aid-o/` is gitignored, so it is NEVER checked out into a linked worktree.
# Every cwd-relative `.aid-o` site invoked from inside a worktree would
# silently create and use a SECOND empty workspace invisible to the primary
# status surfaces. This lib is the one place that resolves "where does AID
# state live" (the PRIMARY checkout — `aid_state_root`) separately from
# "which tree is this command operating on" (`aid_invoke_root`), identically
# from the primary checkout, from any of its subdirectories, and from any
# linked worktree.
#
# This is the EXTRACTED form of the plan FSM's proven resolver
# (`aid-plan-fsm.sh` — `_pfsm_resolve_project_root` / `_pfsm_resolve_invoke_root`,
# including its 2026-07-27 dogfood escape). `aid-plan-fsm.sh` keeps its private
# copy (same contract, cross-referenced there); everything else in the plugin
# shares THIS lib.
#
# CONTRACT
#   aid_state_root [explicit_root]
#     Resolution order: explicit function argument (canonicalized, never
#     cached), then canonicalized $AID_PROJECT_ROOT, then common-dir
#     derivation from $PWD. Prints the absolute primary-checkout top level.
#     Cached per process in _AID_STATE_ROOT_CACHE (env/PWD path only).
#     Outside any git repository: prints
#       "ERROR: not inside a git repository — AID needs a repo root"
#     to stderr and returns 2 — it NEVER falls back to $PWD.
#     A bare repository / detached common dir (common-dir parent without a
#     .git marker) also fails loudly rather than writing state next to a
#     bare repo.
#
#   aid_invoke_root
#     `git rev-parse --show-toplevel` of $PWD — the top level of the tree
#     the command actually runs in (correct for tree operations by
#     definition). Same not-a-repo failure as aid_state_root.
#
#   aid_canonicalize_project_root <dir>
#     Applies the common-dir normalization to an explicit root (the
#     AID_PROJECT_ROOT override): a directory carrying its own
#     `.aid-o/work/plan-state` wins as-given (the dogfood escape — nested
#     fixture repos and the two-checkout dogfood topology depend on it; a
#     fresh linked worktree never has one, `.aid-o/` being gitignored, and a
#     worktree with only a stale `.aid-o/config` fork still canonicalizes to
#     the primary); otherwise the directory must be inside a git repository
#     and collapses to the PRIMARY checkout root, so an override pointing
#     into a linked worktree canonicalizes instead of forking state. A
#     directory with neither form FAILS (exit 2) naming both accepted forms
#     — never a silent write to an arbitrary path.
#
#   aid_state_path <rel>
#     Joins <rel> under aid_state_root. Prints <rel> UNCHANGED when the
#     caller already stands at the state root — this preserves the historic
#     relative-path behaviour (and stdout byte-identity) for every
#     primary-checkout invocation, while worktree/subdirectory invocations
#     get the absolute primary path.
#
# Pure bash + git. No other dependencies. Safe to source multiple times.
#
# **Last Updated:** 2026-08-05
# =============================================================================

if [[ -n "${_AID_ROOTS_SH_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_AID_ROOTS_SH_SOURCED=1

_AID_STATE_ROOT_CACHE=""
# The override value the cache was computed under — a cached root computed
# without (or under a different) AID_PROJECT_ROOT must never shadow a later
# override change within the same process.
_AID_STATE_ROOT_CACHE_KEY=""
_AID_STATE_ROOT_CACHE_SET=""

# _aid_roots_common_root <probe_dir> — prints the primary-checkout top level
# derived from <probe_dir>'s git common dir. Returns 1 when <probe_dir> is not
# inside a git repository, 3 when the common-dir parent carries no .git marker
# (bare repository / detached common dir layout).
_aid_roots_common_root() {
  local probe_dir="$1" common_dir="" root=""
  common_dir="$(git -C "$probe_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common_dir=""
  [[ -n "$common_dir" ]] || return 1
  # Pure-bash dirname (spec: bash + git only): strip the last path segment.
  root="${common_dir%/*}"
  [[ -n "$root" ]] || root="/"
  # A normal checkout's common dir is <root>/.git, so <root> carries a .git
  # marker. A bare repo's common dir is the repo itself — its parent is NOT a
  # worktree, and writing .aid-o state next to a bare repo would be silent
  # corruption. Fail loudly instead.
  [[ -e "${root}/.git" ]] || return 3
  printf '%s\n' "$root"
}

aid_invoke_root() {
  local top=""
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || top=""
  if [[ -z "$top" ]]; then
    echo "ERROR: not inside a git repository — AID needs a repo root" >&2
    return 2
  fi
  printf '%s\n' "$top"
}

aid_canonicalize_project_root() {
  local given="${1:-}" abs="" rc=0
  if [[ -z "$given" ]]; then
    echo "ERROR: aid_canonicalize_project_root: no directory given" >&2
    return 2
  fi
  abs="$(cd "$given" 2>/dev/null && pwd -P)" || {
    echo "ERROR: AID project root '$given' is not an existing directory" >&2
    return 2
  }
  # Dogfood escape (aid-plan-fsm.sh, 2026-07-27 finding): an explicitly named
  # root carrying its own plan runtime state (`.aid-o/work/plan-state`) is
  # honoured AS GIVEN — the two-checkout dogfood topology and nested test
  # fixture repos exist precisely so the tool under test runs against a
  # different tree than its own; collapsing those to a common dir points
  # every write at the wrong tree. DELIBERATELY NARROW (P074 review round 2):
  # the key is plan-state, NOT any `.aid-o` — a linked worktree with a stale
  # local `.aid-o/config` fork must still canonicalize to the primary, never
  # be honoured. Fixture state roots must carry (or create) the plan-state
  # dir to claim the escape.
  if [[ -d "${abs}/.aid-o/work/plan-state" ]]; then
    printf '%s\n' "$abs"
    return 0
  fi
  local root=""
  root="$(_aid_roots_common_root "$abs")" || rc=$?
  case "$rc" in
    0) printf '%s\n' "$root"; return 0 ;;
    3) echo "ERROR: AID project root '$given' resolves to a bare repository / detached common dir (no .git marker above the common dir) — refusing to place state there" >&2
       return 2 ;;
    *) echo "ERROR: AID project root '$given' is neither a git repository root (or worktree of one) nor a directory carrying .aid-o/work/plan-state — pass one of those two forms" >&2
       return 2 ;;
  esac
}

aid_state_root() {
  # Explicit function argument: canonicalized, never cached (nested fixture
  # repos rely on per-call resolution).
  if [[ -n "${1:-}" ]]; then
    aid_canonicalize_project_root "$1"
    return $?
  fi
  # Cache is only valid for the override value it was computed under —
  # setting/changing AID_PROJECT_ROOT after a cached call is honoured.
  if [[ -n "$_AID_STATE_ROOT_CACHE_SET" && "$_AID_STATE_ROOT_CACHE_KEY" == "${AID_PROJECT_ROOT:-}" ]]; then
    printf '%s\n' "$_AID_STATE_ROOT_CACHE"
    return 0
  fi
  local root="" rc=0
  if [[ -n "${AID_PROJECT_ROOT:-}" ]]; then
    root="$(aid_canonicalize_project_root "$AID_PROJECT_ROOT")" || return $?
  else
    root="$(_aid_roots_common_root "$PWD")" || rc=$?
    if [[ "$rc" -eq 3 ]]; then
      echo "ERROR: git common dir for '$PWD' has no worktree above it (bare repository / detached common dir) — refusing to place .aid-o state there" >&2
      return 2
    elif [[ "$rc" -ne 0 ]]; then
      echo "ERROR: not inside a git repository — AID needs a repo root" >&2
      return 2
    fi
  fi
  _AID_STATE_ROOT_CACHE="$root"
  _AID_STATE_ROOT_CACHE_KEY="${AID_PROJECT_ROOT:-}"
  _AID_STATE_ROOT_CACHE_SET=1
  printf '%s\n' "$root"
}

aid_state_path() {
  local rel="${1:?aid_state_path: relative path required}" root=""
  root="$(aid_state_root)" || return $?
  if [[ "$(pwd -P)" == "$root" ]]; then
    printf '%s\n' "$rel"
  else
    printf '%s\n' "${root}/${rel}"
  fi
}
