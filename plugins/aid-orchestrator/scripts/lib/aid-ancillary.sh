#!/usr/bin/env bash
# =============================================================================
# aid-ancillary.sh — the ONE classifier for ancillary vs delivery paths
# (P073 EPIC 3, Step 14)
#
# WHY THIS EXISTS: the same dirty-worktree exception regex was duplicated
# VERBATIM at four call sites — aid-plan-fsm.sh twice, aid-release.sh, and a
# four-entry variant in aid-fsm.sh — with the codebase's own comment noting the
# shared shape. Four copies of one rule is four places to drift.
#
# ── THIS STEP IS BEHAVIOUR-NEUTRAL, BY CONTRACT ─────────────────────────────
# Every existing caller passes `--mode legacy5` (or `legacy4` for aid-fsm.sh),
# which reproduces its current exception set EXACTLY. The broader `--mode
# policy` exists here but is switched on only by Step 17, at the drift
# detector. That split is what lets this step merge green without touching
# plan-final semantics at all, and it is why the mode argument is MANDATORY:
# no caller may silently inherit a wider set by omitting it.
#
# ── FAIL-CLOSED ─────────────────────────────────────────────────────────────
# An unreadable or malformed policy never widens the filter. It falls back to
# the five legacy runtime paths and warns once per process. Widening on a parse
# error would turn "I could not read the rules" into "everything is ancillary".
#
# **Last Updated:** 2026-08-05
# =============================================================================
[[ -n "${_AID_ANCILLARY_LOADED:-}" ]] && return 0
_AID_ANCILLARY_LOADED=1

# The five legacy runtime paths, in the order the original regexes had them.
# `legacy5` is aid-plan-fsm.sh's and aid-release.sh's set; `legacy4` is
# aid-fsm.sh's, which predates the `plan-state/` entry.
_AID_ANCILLARY_LEGACY5=(
  ".aid-o/config/queue.yaml"
  ".aid-o/work/audit-log.jsonl"
  ".aid-o/metrics/gate-runtime-baselines.yaml"
  ".aid-o/metrics/gate-runtime-baselines.yaml.lock"
  ".aid-o/work/plan-state/**"
)
_AID_ANCILLARY_LEGACY4=(
  ".aid-o/config/queue.yaml"
  ".aid-o/work/audit-log.jsonl"
  ".aid-o/metrics/gate-runtime-baselines.yaml"
  ".aid-o/metrics/gate-runtime-baselines.yaml.lock"
)

# Loaded policy globs, and a once-per-process warn latch.
_AID_ANCILLARY_PATTERNS=()
_AID_ANCILLARY_LOADED_ROOT=""
_AID_ANCILLARY_WARNED=0
_AID_ANCILLARY_POLICY_FILE=""

# ---------------------------------------------------------------------------
# aid_ancillary_load <project_root>
#   Reads the project policy at .aid-o/config/policies/plan-final-policy.yaml
#   when present, else the shipped default. Caches per root so porcelain
#   filtering stays one pass. Fails closed to the five legacy paths.
# ---------------------------------------------------------------------------
aid_ancillary_load() {
  local root="${1:-.}"
  [[ "$_AID_ANCILLARY_LOADED_ROOT" == "$root" && "${#_AID_ANCILLARY_PATTERNS[@]}" -gt 0 ]] && return 0

  local project="${root}/.aid-o/config/policies/plan-final-policy.yaml"
  local shipped="${_AID_ANCILLARY_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/../defaults/policies/plan-final-policy.yaml"
  shipped="$(cd "$(dirname "$shipped")" 2>/dev/null && pwd)/$(basename "$shipped")" 2>/dev/null || true
  local file=""
  if [[ -r "$project" ]]; then
    file="$project"
  elif [[ -r "$shipped" ]]; then
    file="$shipped"
  fi

  _AID_ANCILLARY_PATTERNS=()
  _AID_ANCILLARY_POLICY_FILE="$file"
  if [[ -z "$file" ]] || ! command -v yq >/dev/null 2>&1; then
    _aid_ancillary_fallback "no readable plan-final policy (or yq unavailable)"
    _AID_ANCILLARY_LOADED_ROOT="$root"
    return 0
  fi

  local line
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != "null" ]] || continue
    _AID_ANCILLARY_PATTERNS+=("$line")
  done < <(yq -r '.plan_final.ancillary_paths[]?' "$file" 2>/dev/null)

  if [[ "${#_AID_ANCILLARY_PATTERNS[@]}" -eq 0 ]]; then
    _aid_ancillary_fallback "plan-final policy at ${file} is unparseable or lists no ancillary_paths"
  fi
  _AID_ANCILLARY_LOADED_ROOT="$root"
  return 0
}

_aid_ancillary_fallback() {
  _AID_ANCILLARY_PATTERNS=("${_AID_ANCILLARY_LEGACY5[@]}")
  if [[ "$_AID_ANCILLARY_WARNED" -eq 0 ]]; then
    echo "WARNING: ${1} — falling back to the five legacy runtime paths. The ancillary filter is never widened on a read error." >&2
    _AID_ANCILLARY_WARNED=1
  fi
}

# ---------------------------------------------------------------------------
# _aid_ancillary_glob_match <path> <pattern> [strict]
#   ONE matcher, shared with protected-set matching so the two can never
#   diverge on the same entry. Same technique as gates/scope-check.sh:33-42
#   (a bash `case` glob), plus the pre-commit hook's directory-prefix rule:
#   an entry matches a path that IS it, or that sits under it.
#
#   TWO SEMANTICS, because the legacy modes must reproduce four ANCHORED
#   regexes, not approximate them:
#
#   permissive (default) — the pre-commit hook's rule. A bare entry also
#     covers what is under it, and `<dir>/**` covers the directory itself.
#     This is what the policy globs and the protected set want.
#
#   strict (third argument "strict") — exactly the old `^.. <path>$` anchors.
#     A bare entry matches ONLY that path; `<dir>/**` matches only things
#     UNDER the directory, never the bare directory name. Measured before this
#     split existed, the permissive rule silently exempted three paths the old
#     regexes blocked: `.aid-o/config/queue.yaml/nested.txt`,
#     `.aid-o/work/audit-log.jsonl/foo` and the bare `.aid-o/work/plan-state`.
#     A "behaviour-neutral" refactor that quietly widens an exception set is
#     the exact failure this step exists to prevent.
# ---------------------------------------------------------------------------
_aid_ancillary_glob_match() {
  local path="$1" pattern="$2" strict="${3:-}"
  [[ -n "$pattern" && "$pattern" != \#* ]] || return 1
  # Explicit directory form.
  if [[ "$pattern" == */\*\* ]]; then
    local base="${pattern%/\*\*}"
    if [[ "$strict" == "strict" ]]; then
      # The old regex was a prefix WITH the slash: `\.aid-o/work/plan-state/`.
      [[ "$path" == "$base"/* ]] && return 0
      return 1
    fi
    [[ "$path" == "$base" || "$path" == "$base"/* ]] && return 0
    return 1
  fi
  # shellcheck disable=SC2254
  case "$path" in
    $pattern) return 0 ;;
  esac
  # Directory-prefix rule — permissive only. Under `strict` the old `$` anchor
  # meant a bare entry covered nothing beneath it.
  [[ "$strict" == "strict" ]] && return 1
  [[ "$path" == "$pattern"/* ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# aid_ancillary_match <path> [project_root]
#   0 when <path> is ancillary under the LOADED policy, 1 otherwise.
# ---------------------------------------------------------------------------
aid_ancillary_match() {
  local path="$1" root="${2:-.}" p
  aid_ancillary_load "$root"
  for p in "${_AID_ANCILLARY_PATTERNS[@]}"; do
    _aid_ancillary_glob_match "$path" "$p" && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# aid_ancillary_filter_porcelain --mode <legacy5|legacy4|policy> [--project-root <p>]
#   Reads `git status --porcelain` lines on stdin and prints those that are NOT
#   ancillary — i.e. the genuinely dirty ones, exactly what the four inline
#   `grep -vE` invocations produced.
#
#   THE MODE IS MANDATORY. Defaulting it would let a caller silently inherit a
#   wider exception set than it had, which is the one way this refactor could
#   change behaviour without anyone noticing.
# ---------------------------------------------------------------------------
aid_ancillary_filter_porcelain() {
  local mode="" root="." line path
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --project-root) root="${2:-.}"; shift 2 ;;
      *) shift ;;
    esac
  done
  local -a patterns=()
  # The legacy modes match STRICTLY, so they reproduce the four anchored
  # regexes exactly rather than approximating them.
  local strict=""
  case "$mode" in
    legacy5) patterns=("${_AID_ANCILLARY_LEGACY5[@]}"); strict="strict" ;;
    legacy4) patterns=("${_AID_ANCILLARY_LEGACY4[@]}"); strict="strict" ;;
    policy)  aid_ancillary_load "$root"; patterns=("${_AID_ANCILLARY_PATTERNS[@]}") ;;
    *)
      echo "ERROR: aid_ancillary_filter_porcelain requires --mode <legacy5|legacy4|policy> (got '${mode:-<none>}'). The mode is mandatory so no caller silently inherits a wider exception set." >&2
      return 2
      ;;
  esac

  local p keep
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # Porcelain is `XY <path>`; the path starts at column 4. Newline porcelain
    # only — the existing callers use it and this preserves their exact
    # input/output contract (no -z handling is introduced here).
    path="${line:3}"
    keep=1
    for p in "${patterns[@]}"; do
      if _aid_ancillary_glob_match "$path" "$p" "$strict"; then keep=0; break; fi
    done
    [[ "$keep" -eq 1 ]] && printf '%s\n' "$line"
  done
  return 0
}

# ---------------------------------------------------------------------------
# aid_ancillary_overlap_warn <protected_paths_file> [project_root]
#   Prints one warning per glob/protected-path collision, naming BOTH sides.
#   Overlaps are expected — close-consumed evidence lives under `.aid-o/work/`,
#   which is an ancillary glob — so this documents the precedence rather than
#   rejecting the policy. Rejecting would forbid the shipped defaults.
# ---------------------------------------------------------------------------
aid_ancillary_overlap_warn() {
  local pfile="$1" root="${2:-.}" prot p
  [[ -r "$pfile" ]] || return 0
  aid_ancillary_load "$root"
  while IFS= read -r prot; do
    [[ -n "$prot" ]] || continue
    for p in "${_AID_ANCILLARY_PATTERNS[@]}"; do
      if _aid_ancillary_glob_match "$prot" "$p"; then
        echo "WARNING: ancillary glob '${p}' covers protected path '${prot}' — the protected set wins at the path level, so this path can never ride an ancillary commit." >&2
      fi
    done
  done < "$pfile"
  return 0
}
