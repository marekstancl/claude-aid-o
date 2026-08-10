#!/usr/bin/env bash
# =============================================================================
# aid-cache-preflight.sh — Controller plugin-cache staleness guard (P060 Step 5)
#
# WHY (IMP-179): Claude Code caches installed plugins as shallow git clones in
# ~/.claude/plugins/marketplaces/. The `plugin update` command may fetch without
# updating the working tree, so a controller run can silently execute from a
# STALE cache. This has bitten this project repeatedly (OBS-20260708-02 version
# skew; three independent Auditor/Curator "didn't know their own protocol"
# occurrences). This preflight makes a forgotten cache update FAIL LOUD.
#
# ── HONESTY / COVERAGE (read before trusting this) ──────────────────────────
# This preflight REPLACES the *manual VERIFY step* of the release workflow (a
# forgotten update now fails loud). It does NOT replace the update itself — the
# update stays manual (`claude plugin update ...` / cache force-refresh).
#
# It covers ONLY:  plugin.json `version`  +  a deterministic sha256 of the
#                  `scripts/` tree.
# It does NOT cover: stale `skills/`, `defaults/`, `agents/`. Those staleness
# classes are NOT solved here — IMP-179 and its neighbours remain E10 blockers.
# Do not read a green preflight as "the whole plugin cache is fresh".
#
# ── D5 CONTRACT ─────────────────────────────────────────────────────────────
#   Compares the RUNNING (version, scripts-tree-hash) against a reference:
#     • dogfood  — the repo we're standing in ships this same plugin;
#                  reference = that repo's plugin (version, hash).
#     • consumer — reference = (controller_version, controller_hash) recorded
#                  into fsm-state at an EARLIER preflight of the SAME run.
#   Three states:  ok | skew_consumer | skew_dogfood
#   Enforcement:   HARD STOP (exit != 0) ONLY on skew_dogfood.
#                  skew_consumer → warn + non-blocking event.
#   Dogfood WITH match → ok (must NOT hard-stop — else every dogfood run,
#                  including P060 itself, would be killed).
#   Env override:  AID_CACHE_PREFLIGHT_OVERRIDE=1 → continue + logged event.
#
# Deterministic tree hash (EXACT — relative paths, fixed C locale):
#   cd <tree> && find . -type f -print0 | LC_ALL=C sort -z \
#     | xargs -0 sha256sum | sha256sum   (leading hash field)
#
# Dogfood detection: the running plugin's `.name` (read from the running
# script's own plugin.json) is looked up at
#   $(git rev-parse --show-toplevel)/plugins/<name>/.claude-plugin/plugin.json
# and confirmed dogfood iff that file exists AND its `.name` == the running
# name. (Name match — NOT remote-URL, NOT top-level path comparison.)
#
# Usage:
#   source .../lib/aid-cache-preflight.sh   # defines run_cache_preflight, ...
#   run_cache_preflight <state_file> [timeline_file]
# Standalone:
#   bash aid-cache-preflight.sh <state_file> [timeline_file]
#   bash aid-cache-preflight.sh --tree-hash <dir>
#
# Callable standalone AND sourceable (sibling idiom: aid-stage-log.sh). No
# top-level `set -e` (would leak into sourcing shells) and no `die` definition
# (would clobber aid-fsm.sh's multi-line die).
# =============================================================================

# Resolve the RUNNING plugin from THIS lib's own location (correct whether
# sourced by aid-fsm.sh or executed standalone). lib lives at scripts/lib/.
_AID_CP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AID_CP_RUNNING_SCRIPTS_DIR="$(cd "${_AID_CP_LIB_DIR}/.." && pwd)"
_AID_CP_RUNNING_PLUGIN_JSON="${_AID_CP_RUNNING_SCRIPTS_DIR}/../.claude-plugin/plugin.json"

# Pull in log_event only if the sourcing context hasn't already (aid-fsm.sh
# sources aid-stage-log.sh before us, so this is a no-op there — and the guard
# prevents re-sourcing from clobbering aid-fsm.sh's own die()).
if ! declare -F log_event >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "${_AID_CP_LIB_DIR}/aid-stage-log.sh" 2>/dev/null || true
fi

_aid_cp_warn()  { echo "[WARN] $*"  >&2; }
_aid_cp_error() { echo "[ERROR] $*" >&2; }

# Timeline logging shim — best-effort, never fails, no stdout.
_aid_cp_log() {
  local tl="$1"; shift
  [[ -n "$tl" ]] || return 0
  if declare -F log_event >/dev/null 2>&1; then
    log_event "$tl" "$@" || true
  fi
  return 0
}

# Deterministic sha256 of a directory's file tree (relative paths, C locale).
# Prints the leading hash field. Empty string if dir missing.
_aid_cp_tree_hash() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" ]] || { printf '%s' ""; return 0; }
  ( cd "$dir" && find . -type f -print0 | LC_ALL=C sort -z \
      | xargs -0 sha256sum | sha256sum ) 2>/dev/null | awk '{print $1}'
}

# Read one flat `key: value` scalar from a YAML-ish state file (self-contained
# so the lib works standalone without aid-fsm.sh's yaml_field). First match wins.
_aid_cp_yaml() {
  local file="$1" key="$2" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    if [[ "$line" == "${key}:"* ]]; then
      line="${line#"${key}:"}"
      line="${line#"${line%%[![:space:]]*}"}"   # strip leading ws
      line="${line%"${line##*[![:space:]]}"}"    # strip trailing ws
      printf '%s\n' "$line"
      return 0
    fi
  done < "$file"
  return 0
}

# run_cache_preflight <state_file> [timeline_file]
#   Returns 0 on ok / skew_consumer / override; returns 1 on skew_dogfood.
# ─── Is this the plugin's own work in progress? (P079 Step 8, IMP-477) ──────
#
# Three conditions, all cheap, deliberately conjunctive, and FAIL CLOSED: any
# one of them failing to answer leaves the hard stop in place. Uncertainty is
# never a reason to downgrade a staleness check.
#
#   1. the invocation is in a LINKED worktree (its git dir is not the common one)
#   2. that worktree is the plan's registered execution worktree — the recorded
#      path when plan-state can be read, the `.aid-worktrees/plan-*` convention
#      otherwise
#   3. its diff against the plan branch actually touches `plugins/`
#
# _aid_cp_wip_base <toplevel> — the commit to diff against: the merge-base with
# the worktree's own branch point. Falls back to a bounded HEAD~20 so a shallow
# or freshly-cut branch still answers.
_aid_cp_wip_base() {
  local top="$1" branch base
  branch="$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 1
  base="$(git -C "$top" merge-base "$branch" "$(_aid_cp_wip_parent "$top" "$branch")" 2>/dev/null)" || base=""
  [[ -n "$base" ]] || base="$(git -C "$top" rev-parse --verify --quiet 'HEAD~20' 2>/dev/null)" || base=""
  [[ -n "$base" ]] || return 1
  printf '%s' "$base"
}

# _aid_cp_wip_parent <toplevel> <branch> — what a plan worktree's branch was cut
# from: `main` when it exists, else the branch itself (making the diff empty and
# the downgrade not fire, which is the fail-closed direction).
_aid_cp_wip_parent() {
  local top="$1" branch="$2"
  if git -C "$top" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then
    printf 'main'
  else
    printf '%s' "$branch"
  fi
}

_aid_cp_wip_count() {
  local top="$1" base
  base="$(_aid_cp_wip_base "$top")" || { printf '0'; return 0; }
  git -C "$top" diff --name-only "${base}..HEAD" -- plugins/ 2>/dev/null | grep -c . || printf '0'
}

_aid_cp_is_plugin_wip() {
  local top="${1:-}"
  [[ -n "$top" ]] || return 1

  # 1. a linked worktree
  local gd cd_
  gd="$(git -C "$top" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  cd_="$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$gd" && -n "$cd_" && "$gd" != "$cd_" ]] || return 1

  # 2. THE plan's registered execution worktree.
  #
  # The path convention is only the FALLBACK for when there is no registry to
  # ask (no plan-state library, or a directory name that is not a plan id). When
  # a registry CAN be asked, its answer is authoritative and a failed lookup is
  # a refusal — otherwise a hand-made worktree at the conventional path, or a
  # transient read error, would downgrade a genuinely stale cache.
  local phys recorded="" plan_id="" rc=0
  phys="$(cd "$top" 2>/dev/null && pwd -P)" || return 1
  plan_id="$(basename "$phys")"; plan_id="${plan_id#plan-}"
  if [[ -f "${_AID_CP_LIB_DIR}/aid-plan-state.sh" && "$plan_id" =~ ^P[0-9]{3}$ ]]; then
    # The state root is the parent of the shared git dir — the primary
    # checkout, which is where `.aid-o` lives.
    local state_root="${cd_%/.git}"
    recorded="$(AID_PLAN_STATE_PROJECT_ROOT="$state_root" \
      bash "${_AID_CP_LIB_DIR}/aid-plan-state.sh" get "$plan_id" worktree_path 2>/dev/null)" || rc=$?
    # rc > 1 is an UNREADABLE registry (missing yq, corrupt state, lock
    # timeout) — the one case that must never be read as permission.
    [[ "$rc" -le 1 ]] || return 1
    [[ "$recorded" == "not_found" || "$recorded" == "null" ]] && recorded=""
  fi
  if [[ -n "$recorded" ]]; then
    # A recorded worktree is authoritative: this must BE it, not merely sit at
    # a path that looks like it.
    [[ "$(cd "$recorded" 2>/dev/null && pwd -P)" == "$phys" ]] || return 1
  else
    # No record to consult (a plan-state-less project, or a worktree made by
    # hand for plugin work — how this repository's own EPICs run). The path
    # convention is the fallback, and it is still one of three conditions.
    [[ "$phys" == */.aid-worktrees/plan-* ]] || return 1
  fi

  # 3. the diff actually touches plugins/
  [[ "$(_aid_cp_wip_count "$top")" -gt 0 ]]
}

run_cache_preflight() {
  local state_file="${1:-}"
  local timeline="${2:-}"

  # ── Running (version, name, tree-hash) ────────────────────────────────────
  local running_name running_version running_hash
  running_name="$(jq -r '.name // ""'    "${_AID_CP_RUNNING_PLUGIN_JSON}" 2>/dev/null || true)"
  running_version="$(jq -r '.version // ""' "${_AID_CP_RUNNING_PLUGIN_JSON}" 2>/dev/null || true)"
  running_hash="$(_aid_cp_tree_hash "${_AID_CP_RUNNING_SCRIPTS_DIR}" || true)"

  # ── Env override: continue regardless, with an audit event ────────────────
  if [[ "${AID_CACHE_PREFLIGHT_OVERRIDE:-}" == "1" ]]; then
    _aid_cp_log "$timeline" "cache_preflight_override" \
      running_version="$running_version" running_hash="$running_hash"
    _aid_cp_warn "cache-preflight OVERRIDE active (AID_CACHE_PREFLIGHT_OVERRIDE=1) — staleness enforcement skipped."
    return 0
  fi

  # ── Dogfood detection (plugin.json .name match at git toplevel) ───────────
  local toplevel="" dogfood="false" dogfood_pj="" dogfood_scripts=""
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$toplevel" && -n "$running_name" ]]; then
    dogfood_pj="${toplevel}/plugins/${running_name}/.claude-plugin/plugin.json"
    if [[ -f "$dogfood_pj" ]]; then
      local dogfood_name
      dogfood_name="$(jq -r '.name // ""' "$dogfood_pj" 2>/dev/null || true)"
      if [[ "$dogfood_name" == "$running_name" ]]; then
        dogfood="true"
        dogfood_scripts="${toplevel}/plugins/${running_name}/scripts"
      fi
    fi
  fi

  # ── DOGFOOD path: compare running vs the dogfood repo's plugin ────────────
  if [[ "$dogfood" == "true" ]]; then
    local dogfood_version dogfood_hash
    dogfood_version="$(jq -r '.version // ""' "$dogfood_pj" 2>/dev/null || true)"
    dogfood_hash="$(_aid_cp_tree_hash "$dogfood_scripts" || true)"

    if [[ "$running_version" == "$dogfood_version" && "$running_hash" == "$dogfood_hash" ]]; then
      _aid_cp_log "$timeline" "cache_preflight_ok" mode="dogfood" \
        running_version="$running_version"
      return 0
    fi

    # ── The EPIC's own work is not staleness (P079 Step 8, IMP-477) ────────
    # The dogfood reference resolves to the INVOKING tree's plugins/ copy, so
    # an EPIC that modifies the plugin always "skews" against itself: the
    # difference the check reports IS the work in progress. That is a false
    # positive by construction, and it hard-stopped the plugin's own runs.
    #
    # Downgraded to a warning ONLY when all three hold — a linked worktree, at
    # the registered plan-worktree path, whose diff against the plan branch
    # actually touches plugins/. The primary-checkout hard stop is untouched,
    # and a worktree with NO plugin changes still hard-stops, so real staleness
    # is still caught in both places. What the downgrade costs is stated
    # plainly: for this one run, controller tooling from a genuinely stale
    # cache would go unreported. The gates themselves execute the tree's own
    # scripts, so the risk window is the controller layer only.
    if _aid_cp_is_plugin_wip "$toplevel"; then
      _aid_cp_log "$timeline" "cache_preflight_skew_wip" \
        running_version="$running_version" cache_version="$dogfood_version" \
        running_hash="$running_hash" cache_hash="$dogfood_hash"
      _aid_cp_warn "cache-preflight downgraded: $(_aid_cp_wip_count "$toplevel") file(s) under plugins/ differ from the plan branch — this is the EPIC's own work, not a stale cache. Controller tooling staleness is NOT verified for this run."
      return 0
    fi

    # skew_dogfood → HARD STOP
    _aid_cp_log "$timeline" "cache_preflight_skew_dogfood" \
      running_version="$running_version" cache_version="$dogfood_version" \
      running_hash="$running_hash" cache_hash="$dogfood_hash"
    _aid_cp_error "AID cache-preflight HARD STOP — controller is running from a STALE plugin cache."
    _aid_cp_error "  running: version=${running_version} scripts=${running_hash:0:12}"
    _aid_cp_error "  cache:   version=${dogfood_version} scripts=${dogfood_hash:0:12}"
    _aid_cp_error "  The scripts/ currently executing differ from this repo's installed plugin."
    _aid_cp_error "  Fix (update the cache, then retry):"
    _aid_cp_error "    claude plugin update aid-orchestrator@claude-aid-o"
    _aid_cp_error "    # or: git -C ~/.claude/plugins/marketplaces/claude-aid-o fetch origin \\"
    _aid_cp_error "    #     && git -C ~/.claude/plugins/marketplaces/claude-aid-o reset --hard origin/main"
    _aid_cp_error "  Override (NOT recommended): AID_CACHE_PREFLIGHT_OVERRIDE=1"
    _aid_cp_error "  NOTE: covers plugin.json version + scripts/ only — skills/defaults/agents NOT covered."
    return 1
  fi

  # ── CONSUMER path: track the controller across the run via fsm-state ──────
  # No state file yet (e.g. cmd_init BEFORE the fsm-state write) → nothing to
  # record/compare; not dogfood, so this is ok.
  if [[ -z "$state_file" || ! -f "$state_file" ]]; then
    _aid_cp_log "$timeline" "cache_preflight_ok" mode="consumer_init_pre_state" \
      running_version="$running_version"
    return 0
  fi

  local rec_version rec_hash
  rec_version="$(_aid_cp_yaml "$state_file" controller_version)"
  rec_hash="$(_aid_cp_yaml "$state_file" controller_hash)"

  # First preflight of the run (init) → RECORD controller identity + event.
  if [[ -z "$rec_version" && -z "$rec_hash" ]]; then
    printf 'controller_version: %s\n' "$running_version" >> "$state_file"
    printf 'controller_hash: %s\n'    "$running_hash"    >> "$state_file"
    _aid_cp_log "$timeline" "controller_recorded" \
      controller_version="$running_version" controller_hash="$running_hash"
    return 0
  fi

  # Resume with a changed controller → warn (NON-blocking) + event.
  if [[ "$rec_version" != "$running_version" || "$rec_hash" != "$running_hash" ]]; then
    _aid_cp_log "$timeline" "controller_skew_detected" \
      recorded_version="$rec_version" running_version="$running_version" \
      recorded_hash="$rec_hash" running_hash="$running_hash"
    _aid_cp_warn "controller changed mid-run (consumer skew, non-blocking): recorded ${rec_version}/${rec_hash:0:12} != running ${running_version}/${running_hash:0:12}"
    return 0
  fi

  _aid_cp_log "$timeline" "cache_preflight_ok" mode="consumer" \
    running_version="$running_version"
  return 0
}

# ── Standalone dispatch (skipped when sourced) ──────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --tree-hash) shift; _aid_cp_tree_hash "${1:?--tree-hash requires a dir}" ;;
    *)           run_cache_preflight "${1:-}" "${2:-}" ;;
  esac
fi
