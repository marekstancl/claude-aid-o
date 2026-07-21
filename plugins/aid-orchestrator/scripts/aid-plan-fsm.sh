#!/usr/bin/env bash
# =============================================================================
# aid-plan-fsm.sh — the parent-plan FSM CLI (P064 "Plan Branch Substrate",
# EPIC E-064-1_2, Step 4).
#
# WHY THIS EXISTS: E-064-1_2 makes `plan/Pxxx` the integration branch for a
# plan's EPICs. Steps 1-3 built the state/op-record library
# (lib/aid-plan-state.sh), the plan_boundary_manifest protocol-v2 artifact
# type, and the manifest producer/reader/validator (lib/aid-plan-manifest.sh)
# — none of them touch Git. THIS file is the first component that does: it
# creates the plan branch and task branches with exact, provable lineage.
#
# THE NEGATIVE REQUIREMENT IS THE POINT: a task branch created from `main`,
# from a stale plan head, from another plan, or by hand must fail before any
# work starts — a wrong base commit silently corrupts every later diff range
# (the C2 review range, risk-profile recomputation, the plan-final C2 range
# `plan_base_commit..candidate_sha`; none of that machinery exists yet in
# this repo — this file only has to make lineage PROVABLE, not consume it).
#
# ── SUBCOMMANDS (this step implements exactly these three) ──────────────────
#   aid-plan-fsm.sh plan-start <plan_id> [--mode plan_branch|legacy_epic_release_mode]
#                    [--project-root <path>] [--op-id <id>]
#   aid-plan-fsm.sh epic-start <plan_id> <epic_id> [--run-id <id>]
#                    [--project-root <path>] [--op-id <id>]
#   aid-plan-fsm.sh plan-state <plan_id>
#   aid-plan-fsm.sh plan-state <plan_id> --repair
#   aid-plan-fsm.sh plan-state <plan_id> --attest-source-ref <ref> --reason <text> --epic <epic_id>
#
# `--target-ref` (present in the parent plan's own CLI sketch for a LATER
# step's needs) is deliberately NOT implemented here — nothing in this step's
# Acceptance Criteria requires overriding `aid_target_branch()`'s resolved
# branch, and adding it would multiply the branch-identity paths this file
# has to reason about for no tested benefit.
#
# `epic-complete`, `epic-merge-to-plan`, `plan-finalize`, `plan-merge-to-main`,
# `plan-close-check` and `inventory` are P068/later-step subcommands; this
# file does not implement them and its own tests assert none of them exist.
# `epic-start` performs NO queue write (a later step's job).
#
# ── LINEAGE MODEL ─────────────────────────────────────────────────────────
# `plan-start` creates `plan/<plan_id>` from EXACTLY `target_branch_head_at_start
# = git rev-parse <target_branch>`. `epic-start` creates `task/<epic_id>/main`
# from EXACTLY the plan head read ONCE inside the plan lock. Both record the
# base SHA they used — `plan_base_commit` (manifest) / `epic_base_commit`
# (epic_runs[] entry) — as the SOLE authority a later re-verification checks
# against. On an EXISTING branch, the check is: does `git merge-base
# <branch> <parent-branch>` equal the RECORDED base? A branch whose actual
# base doesn't match — created from `main`, from a stale plan SHA, from
# another plan, or by hand — fails BEFORE any state or evidence is written.
#
# The one case SHA comparison alone cannot resolve: the FIRST EPIC of a plan,
# where `plan/Pxxx` and the target branch point at the identical SHA. A
# branch created from `main` is then indistinguishable from a legitimate one
# by SHA alone — so the check is always on the manifest's `epic_runs[]`
# entry (specifically `epic_source_ref`), never on SHA equality alone. A
# branch with no manifest entry at all is unproven regardless of SHA.
#
# ── CRASH RESUME ─────────────────────────────────────────────────────────────
# Both commands use Step 1's op record (plan_op_begin -> ... -> plan_op_commit)
# with a DETERMINISTIC op_id (stage "-", attempt "0", subject = plan_id for
# plan-start / epic_id for epic-start) so a re-invocation after a crash
# derives the identical id and finds its own record. `git branch` runs inside
# a narrow, EXPLICIT hold of the plan's own state-file lock (the same lock
# path Step 1's plan_op_* functions use internally) — held ONLY around the
# head-read + branch-create, then released BEFORE calling into
# plan_op_mark_git_applied/plan_manifest_add_epic (which each take that same
# lock internally for their own writes). Holding it across BOTH would
# deadlock: flock(2) treats file descriptors opened on the same file
# independently even within one process, so a nested acquire on an
# already-held lock via a second fd blocks forever, not just "waits its
# turn". If `git branch` fails (name collision, permission), the op record
# is left at `intent` — a retry starts clean.
#
# A crash between branch creation (git_applied) and the manifest/state write
# converges on re-run: `plan_op_reconcile` reports `git_applied`, the
# existing branch's SHA is verified against the resulting_sha THAT git_applied
# record carries, and only the remaining write is repeated — never a second
# `git branch`.
#
# ── DIRTY WORKTREE / DETACHED HEAD (Error Handling) ─────────────────────────
# Both commands refuse before creating anything: a detached HEAD (prints the
# resolved SHA) and a dirty worktree, using the SAME porcelain-check shape as
# `aid-fsm.sh` (`git status --porcelain --untracked-files=no`) and its
# four-path exclusion list, EXTENDED with a fifth: `.aid-o/work/plan-state/`
# (this plan's own gitignored runtime area — always "dirty" by design, not a
# real blocker). Neither check special-cases a linked worktree — the whole
# point of the plan-boundary substrate is that lineage checks must hold
# IDENTICALLY inside one (unlike the per-EPIC FSM's `is_worktree()` skip of
# its OWN branch enforcement, which is precisely why THIS layer must not
# mirror that skip).
#
# ── SOURCEABLE-SAFE CONVENTION, INVERTED FOR THIS FILE ──────────────────────
# lib/aid-plan-state.sh and lib/aid-plan-manifest.sh both deliberately avoid
# `set -e` because they're SOURCED into other scripts' shells. This file is a
# STANDALONE CLI (matches aid-fsm.sh's own shape) and every branch below
# explicitly captures and checks return codes rather than relying on
# a top-level `set -e` to abort — deliberately: this file's control flow
# threads through many "try X, if that specific failure mode, do Y instead"
# branches (existing-branch verification, crash resume, corruption) where an
# auto-abort would make the intended recovery path unreachable. `set -uo
# pipefail` (no `-e`) still guards against unset variables and swallowed
# pipeline failures wherever a pipeline's exit code IS checked below.
#
# **Last Updated:** 2026-07-21
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-plan-state.sh"      # also sources lib/aid-lock.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-plan-manifest.sh"   # also sources lib/aid-lock.sh + lib/aid-gate-profile.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-lifecycle.sh"

# ---------------------------------------------------------------------------
# _pfsm_resolve_invoke_root [given] — `--project-root` if given (resolved to
# an absolute path), else `pwd`. This is where the OPERATOR actually stands
# — used only for the preflight checks (detached HEAD / dirty worktree),
# which are properly about THAT location's state, not the plan's shared
# runtime root (see _pfsm_resolve_project_root below).
# ---------------------------------------------------------------------------
_pfsm_resolve_invoke_root() {
  local given="${1:-}"
  if [[ -n "$given" ]]; then
    (cd "$given" 2>/dev/null && pwd) || printf '%s' "$given"
    return 0
  fi
  pwd
}

# ---------------------------------------------------------------------------
# _pfsm_resolve_project_root [given] — the root ALL plan-scoped runtime state
# (.aid-o/work/plan-state/<plan_id>/) and every git ref/branch operation in
# this file resolve against. Deliberately NOT simply the invoke root: a
# linked worktree has its OWN working directory, but `.aid-o/work/plan-state`
# is gitignored, so it is NEVER checked out into a linked worktree — and the
# plan-boundary manifest is inherently PLAN-scoped, shared across every EPIC's
# task branch (and therefore potentially every worktree), not per-worktree
# data. So this always normalizes to the MAIN worktree's root via
# `git rev-parse --git-common-dir` (the one git-native path that resolves
# identically no matter which worktree it is queried from), using the invoke
# root only as the probe location to FIND the repository. This is what makes
# "the same lineage checks fail identically inside a linked worktree" (Edge
# Case) actually reachable — a worktree invocation still sees the plan's real
# manifest, not a trivially-empty one.
# ---------------------------------------------------------------------------
_pfsm_resolve_project_root() {
  local probe_dir; probe_dir="$(_pfsm_resolve_invoke_root "${1:-}")"
  local common_dir=""
  common_dir="$(git -C "$probe_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common_dir=""
  if [[ -n "$common_dir" ]]; then
    dirname "$common_dir"
    return 0
  fi
  printf '%s' "$probe_dir"
}

# _pfsm_validate_plan_id <plan_id> — the strict ^P[0-9]{3}$ format (this CLI
# is the manifest-layer boundary aid-plan-state.sh's own header refers to;
# both plan_state_init and plan_manifest_init enforce it too, but failing
# fast here gives a clearer error before any lock/lookup happens).
_pfsm_validate_plan_id() {
  [[ "${1:-}" =~ ^P[0-9]{3}$ ]]
}

# _pfsm_validate_epic_id <epic_id> — mirrors the manifest invariant's own
# epic-id pattern exactly (_pm_check_invariants in aid-plan-manifest.sh).
_pfsm_validate_epic_id() {
  [[ "${1:-}" =~ ^E-[0-9]{3}-[0-9]+_[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# _pfsm_check_detached_head <project_root> — exit-worthy check (returns 1),
# printing the resolved SHA per the Error Handling contract.
# ---------------------------------------------------------------------------
_pfsm_check_detached_head() {
  local root="$1"
  if git -C "$root" symbolic-ref -q HEAD >/dev/null 2>&1; then
    return 0
  fi
  local sha=""
  sha="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || sha="<unresolved>"
  echo "PRECONDITION FAIL: detached HEAD at ${sha} — plan-start/epic-start must run on a branch, not a detached HEAD." >&2
  return 1
}

# ---------------------------------------------------------------------------
# _pfsm_check_clean_worktree <project_root> — same porcelain-check SHAPE as
# aid-fsm.sh's own dirty-worktree guard (search that file for
# `git status --porcelain`), same four-path exclusion list, EXTENDED with a
# fifth: `.aid-o/work/plan-state/` (this plan's own gitignored runtime area).
# ---------------------------------------------------------------------------
_pfsm_check_clean_worktree() {
  local root="$1"
  local dirty
  dirty="$(git -C "$root" status --porcelain --untracked-files=no \
    | grep -vE '^.. \.aid-o/config/queue\.yaml$|^.. \.aid-o/work/audit-log\.jsonl$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml\.lock$|^.. \.aid-o/work/plan-state/' || true)"
  if [[ -n "$dirty" ]]; then
    echo "PRECONDITION FAIL: uncommitted changes present — commit or stash before plan-start/epic-start:" >&2
    printf '%s\n' "$dirty" >&2
    return 1
  fi
  return 0
}

# _pfsm_preflight <project_root> — the shared pair of checks both commands
# run before creating anything.
_pfsm_preflight() {
  local root="$1"
  _pfsm_check_detached_head "$root" || return 1
  _pfsm_check_clean_worktree "$root" || return 1
  return 0
}

# _pfsm_plan_lock_path <plan_id> — reconstructed independently from the
# PUBLIC plan_state_path, matching this codebase's established convention
# (e.g. aid-plan-state.sh's own internal `_plan_lock_path`, and this suite's
# `_state_file`/`_ops_file` test helpers) rather than reaching into
# aid-plan-state.sh's private functions.
_pfsm_plan_lock_path() {
  printf '%s.lock' "$(plan_state_path "$1")"
}

# _pfsm_ops_path <plan_id> — same reconstruction for operations.jsonl.
_pfsm_ops_path() {
  printf '%s/operations.jsonl' "$(dirname "$(plan_state_path "$1")")"
}

# _pfsm_last_resulting_sha <plan_id> <op_id> — best-effort lock-free read of
# the LAST resulting_sha recorded for op_id (the git_applied record — no
# other phase sets it). Used only to verify a crash-resumed branch's SHA
# against what THIS run's own git_applied record claims to have created;
# never treated as an independent proof of anything beyond that narrow
# reconciliation.
_pfsm_last_resulting_sha() {
  local plan_id="$1" op_id="$2" ops_path
  ops_path="$(_pfsm_ops_path "$plan_id")"
  [[ -f "$ops_path" ]] || { echo ""; return 0; }
  local out=""
  out="$(jq -r --arg id "$op_id" 'select(.op_id == $id) | .resulting_sha // empty' "$ops_path" 2>/dev/null | tail -1)" || out=""
  printf '%s' "$out"
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_verify_epic_lineage <project_root> <plan_id> <epic_id> <task_branch>
#                            <entry_json>
# The lineage check for an ALREADY-EXISTING task branch. `entry_json` is the
# epic_runs[] entry object (as JSON text) already looked up by the caller.
# Prints the task branch on success.
# ---------------------------------------------------------------------------
_pfsm_verify_epic_lineage() {
  local root="$1" plan_id="$2" epic_id="$3" task_branch="$4" entry_json="$5"
  local expect_ref="plan/${plan_id}"
  local source_ref recorded_base
  source_ref="$(jq -r '.epic_source_ref // empty' <<<"$entry_json" 2>/dev/null)"
  recorded_base="$(jq -r '.epic_base_commit // empty' <<<"$entry_json" 2>/dev/null)"

  if [[ "$source_ref" != "$expect_ref" ]]; then
    echo "PRECONDITION FAIL: ${task_branch}'s manifest entry has epic_source_ref='${source_ref:-<null>}' (unproven or foreign lineage) — refusing to treat it as authoritative." >&2
    return 1
  fi
  if [[ -z "$recorded_base" ]]; then
    echo "PRECONDITION FAIL: ${task_branch}'s manifest entry has no epic_base_commit recorded." >&2
    return 1
  fi

  local actual_base=""
  actual_base="$(git -C "$root" merge-base "$task_branch" "plan/${plan_id}" 2>/dev/null)" || actual_base=""
  if [[ -z "$actual_base" ]]; then
    echo "PRECONDITION FAIL: cannot compute merge-base(${task_branch}, plan/${plan_id})." >&2
    return 1
  fi
  if [[ "$actual_base" != "$recorded_base" ]]; then
    echo "PRECONDITION FAIL: ${task_branch}'s actual base (${actual_base}) does not match its recorded epic_base_commit (${recorded_base}) — lineage broken (stale/foreign base)." >&2
    return 1
  fi

  echo "$task_branch"
  return 0
}

# _pfsm_epic_finish_write <plan_id> <epic_id> <run_id> <task_branch>
#                          <epic_base_commit> <plan_branch> <evidence_dir> <op_id>
# The shared "write the manifest entry, then commit the op record" tail used
# by both the fresh-creation path and the crash-resume path (Edge Case: a
# crash between branch creation and manifest write repeats ONLY this).
_pfsm_epic_finish_write() {
  local plan_id="$1" epic_id="$2" run_id="$3" task_branch="$4" \
        epic_base_commit="$5" plan_branch_ref="$6" evidence_dir="$7" op_id="$8"

  local arc=0
  plan_manifest_add_epic "$plan_id" "$epic_id" "$run_id" "$task_branch" \
    "$epic_base_commit" "$plan_branch_ref" "$evidence_dir" >/dev/null || arc=$?
  if [[ "$arc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not write manifest entry for ${epic_id} (rc=${arc}) — op remains at git_applied, retry to converge." >&2
    return "$arc"
  fi

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record epic-start state_committed for ${epic_id} (rc=${crc})." >&2
    return "$crc"
  fi

  echo "$task_branch"
  return 0
}

# =============================================================================
# cmd_plan_start <plan_id> [--mode ...] [--project-root ...] [--op-id ...]
# =============================================================================
cmd_plan_start() {
  local plan_id="" mode="plan_branch" project_root_opt="" op_id_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --project-root) project_root_opt="${2:-}"; shift 2 ;;
      --op-id) op_id_opt="${2:-}"; shift 2 ;;
      --*) echo "ERROR: plan-start: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"; else echo "ERROR: plan-start: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done
  if [[ -z "$plan_id" ]]; then
    echo "Usage: aid-plan-fsm.sh plan-start <plan_id> [--mode plan_branch|legacy_epic_release_mode] [--project-root <path>] [--op-id <id>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: plan-start: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  case "$mode" in
    plan_branch|legacy_epic_release_mode) ;;
    *) echo "ERROR: plan-start: --mode must be 'plan_branch' or 'legacy_epic_release_mode' (got '${mode}')" >&2; exit 2 ;;
  esac

  local invoke_root project_root
  invoke_root="$(_pfsm_resolve_invoke_root "$project_root_opt")"
  project_root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$project_root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$project_root"

  _pfsm_preflight "$invoke_root" || exit 1

  # Edge Case: a CLOSED plan is not reopened.
  local cur_state="" src=0
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || src=$?
  if [[ "$src" -eq 5 ]]; then
    echo "PRECONDITION FAIL: plan-state.yaml for ${plan_id} is corrupt — refusing plan-start." >&2
    exit 5
  fi
  if [[ "$src" -eq 0 && "$cur_state" == "CLOSED" ]]; then
    echo "PRECONDITION FAIL: plan ${plan_id} is CLOSED — a closed plan is not reopened by plan-start." >&2
    exit 1
  fi

  local target_branch plan_branch="plan/${plan_id}"
  target_branch="$(aid_target_branch)"

  local op_id="${op_id_opt:-$(plan_op_key "plan-start" "$plan_id" "-" "0" "$plan_id")}"
  local target_head=""

  local branch_exists=1
  if git -C "$project_root" rev-parse --verify --quiet "refs/heads/${plan_branch}" >/dev/null 2>&1; then
    branch_exists=0
  fi

  if [[ "$branch_exists" -eq 0 ]]; then
    # ── Existing plan branch: idempotent-resume verification ──────────────
    local manifest_base="" mrc=0
    manifest_base="$(plan_manifest_get "$plan_id" ".plan_boundary_manifest.plan_base_commit")" || mrc=$?
    if [[ "$mrc" -eq 5 ]]; then
      echo "PRECONDITION FAIL: manifest for ${plan_id} is corrupt — cannot verify existing ${plan_branch}." >&2
      exit 5
    fi
    if [[ "$mrc" -eq 0 ]]; then
      local actual_base=""
      actual_base="$(git -C "$project_root" merge-base "$plan_branch" "$target_branch" 2>/dev/null)" || actual_base=""
      if [[ -z "$actual_base" ]]; then
        echo "PRECONDITION FAIL: cannot compute merge-base(${plan_branch}, ${target_branch})." >&2
        exit 1
      fi
      if [[ "$actual_base" == "$manifest_base" ]]; then
        echo "$plan_branch"
        exit 0
      fi
      echo "PRECONDITION FAIL: existing ${plan_branch} has base ${actual_base}; recorded plan_base_commit is ${manifest_base} — refusing (lineage mismatch)." >&2
      exit 1
    fi

    # No manifest yet — the only legitimate reason a branch can exist without
    # one is a prior run crashing between branch creation and the writes
    # below. Verify via THIS run's own op record, not by trusting the SHA.
    local reconcile_status=""
    reconcile_status="$(plan_op_reconcile "$plan_id" "$op_id" 2>/dev/null)" || true
    if [[ "$reconcile_status" == "git_applied" ]]; then
      local resulting_sha="" branch_sha=""
      resulting_sha="$(_pfsm_last_resulting_sha "$plan_id" "$op_id")"
      branch_sha="$(git -C "$project_root" rev-parse "$plan_branch" 2>/dev/null)" || branch_sha=""
      if [[ -n "$resulting_sha" && "$branch_sha" == "$resulting_sha" ]]; then
        target_head="$branch_sha"
        # fall through to the shared write tail below.
      else
        echo "PRECONDITION FAIL: ${plan_branch} exists but its SHA does not match the crash-recorded resulting_sha for op ${op_id} — cannot verify lineage." >&2
        exit 1
      fi
    else
      echo "PRECONDITION FAIL: ${plan_branch} already exists with no manifest and no matching in-flight operation record — cannot verify lineage (manually created?)." >&2
      exit 1
    fi
  else
    # ── Fresh path ──────────────────────────────────────────────────────────
    local reconcile_status=""
    reconcile_status="$(plan_op_reconcile "$plan_id" "$op_id" 2>/dev/null)" || true
    if [[ "$reconcile_status" == "git_applied" || "$reconcile_status" == "state_committed" ]]; then
      echo "PRECONDITION FAIL: operation record for ${plan_id} plan-start claims '${reconcile_status}' but ${plan_branch} does not exist — manual reconciliation required." >&2
      exit 5
    fi

    local brc=0
    plan_op_begin "$plan_id" "$op_id" "plan-start" "$plan_id" "" || brc=$?
    if [[ "$brc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record plan-start intent for ${plan_id} (rc=${brc})." >&2
      exit "$brc"
    fi

    local lock_path; lock_path="$(_pfsm_plan_lock_path "$plan_id")"
    aid_lock_acquire "$lock_path" "$AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S" || {
      echo "PRECONDITION FAIL: could not acquire plan lock for ${plan_id}." >&2
      exit 3
    }
    local fd="$AID_LOCK_FD"

    target_head="$(git -C "$project_root" rev-parse "$target_branch" 2>/dev/null)" || target_head=""
    if [[ -z "$target_head" ]]; then
      aid_lock_release "$fd"
      echo "PRECONDITION FAIL: cannot resolve target branch '${target_branch}'." >&2
      exit 1
    fi

    if git -C "$project_root" rev-parse --verify --quiet "refs/heads/${plan_branch}" >/dev/null 2>&1; then
      aid_lock_release "$fd"
      echo "PRECONDITION FAIL: ${plan_branch} appeared concurrently while acquiring the lock — retry." >&2
      exit 1
    fi

    if ! git -C "$project_root" branch "$plan_branch" "$target_head" >/dev/null 2>&1; then
      aid_lock_release "$fd"
      echo "PRECONDITION FAIL: git branch ${plan_branch} ${target_head} failed (name collision or permission) — op record stays at intent, retry when resolved." >&2
      exit 1
    fi

    aid_lock_release "$fd"

    local grc=0
    plan_op_mark_git_applied "$plan_id" "$op_id" "$target_head" || grc=$?
    if [[ "$grc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: ${plan_branch} created but could not record git_applied (rc=${grc}) — retry to converge." >&2
      exit "$grc"
    fi
  fi

  # ── Shared tail (both fresh and crash-resumed paths land here with
  #    target_head set and the op record at git_applied) ────────────────────
  local lc_rc=0
  aid_lifecycle_set_plan_mode "$plan_id" "$mode" "$project_root" || lc_rc=$?
  if [[ "$lc_rc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: aid_lifecycle_set_plan_mode failed for ${plan_id} (rc=${lc_rc}) — op remains at git_applied, retry converges." >&2
    exit "$lc_rc"
  fi

  if [[ ! -f "$(plan_state_path "$plan_id")" ]]; then
    local sirc=0
    plan_state_init "$plan_id" "$mode" "$plan_branch" "$target_branch" >/dev/null || sirc=$?
    if [[ "$sirc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: plan_state_init failed for ${plan_id} (rc=${sirc})." >&2
      exit "$sirc"
    fi
  fi

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    local mirc=0
    plan_manifest_init "$plan_id" "$plan_branch" "$target_branch" "$target_head" "$target_head" "$mode" >/dev/null || mirc=$?
    if [[ "$mirc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: plan_manifest_init failed for ${plan_id} (rc=${mirc})." >&2
      exit "$mirc"
    fi
  fi

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record plan-start state_committed for ${plan_id} (rc=${crc})." >&2
    exit "$crc"
  fi

  echo "$plan_branch"
  exit 0
}

# =============================================================================
# cmd_epic_start <plan_id> <epic_id> [--run-id ...] [--project-root ...] [--op-id ...]
# =============================================================================
cmd_epic_start() {
  local plan_id="" epic_id="" run_id_opt="" project_root_opt="" op_id_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id_opt="${2:-}"; shift 2 ;;
      --project-root) project_root_opt="${2:-}"; shift 2 ;;
      --op-id) op_id_opt="${2:-}"; shift 2 ;;
      --*) echo "ERROR: epic-start: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1";
        elif [[ -z "$epic_id" ]]; then epic_id="$1";
        else echo "ERROR: epic-start: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done
  if [[ -z "$plan_id" || -z "$epic_id" ]]; then
    echo "Usage: aid-plan-fsm.sh epic-start <plan_id> <epic_id> [--run-id <id>] [--project-root <path>] [--op-id <id>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: epic-start: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  if ! _pfsm_validate_epic_id "$epic_id"; then
    echo "ERROR: epic-start: epic_id must match ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${epic_id}')" >&2
    exit 2
  fi

  local invoke_root project_root
  invoke_root="$(_pfsm_resolve_invoke_root "$project_root_opt")"
  project_root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$project_root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$project_root"

  _pfsm_preflight "$invoke_root" || exit 1

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    echo "PRECONDITION FAIL: no plan-boundary-manifest for ${plan_id} — run plan-start first." >&2
    exit 1
  fi

  local run_id="${run_id_opt:-R-${epic_id}-plan}"
  local task_branch="task/${epic_id}/main"
  local plan_branch="plan/${plan_id}"
  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  local op_id="${op_id_opt:-$(plan_op_key "epic-start" "$plan_id" "-" "0" "$epic_id")}"

  # Existing epic_runs[] entry, if any (lock-free read — direct file read
  # mirrors plan_manifest_get's own convention; a single call is used here
  # because more than one field of the SAME entry is needed, which
  # plan_manifest_get's one-jq_path-per-call contract does not return).
  local entry_json="" erc=0
  entry_json="$(plan_manifest_get "$plan_id" ".plan_boundary_manifest.epic_runs[] | select(.epic_id==\"${epic_id}\")")" || erc=$?
  if [[ "$erc" -eq 5 ]]; then
    echo "PRECONDITION FAIL: manifest for ${plan_id} is corrupt." >&2
    exit 5
  fi

  local branch_exists=1
  if git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1; then
    branch_exists=0
  fi

  if [[ "$branch_exists" -eq 0 ]]; then
    if [[ -n "$entry_json" ]]; then
      _pfsm_verify_epic_lineage "$project_root" "$plan_id" "$epic_id" "$task_branch" "$entry_json" || exit 1
      exit 0
    fi

    # No manifest entry — the only legitimate reason the branch can exist
    # anyway is a prior run crashing between branch creation and the
    # manifest write (Edge Case). Verify via THIS run's own op record.
    local reconcile_status=""
    reconcile_status="$(plan_op_reconcile "$plan_id" "$op_id" 2>/dev/null)" || true
    if [[ "$reconcile_status" == "git_applied" ]]; then
      local resulting_sha="" branch_sha=""
      resulting_sha="$(_pfsm_last_resulting_sha "$plan_id" "$op_id")"
      branch_sha="$(git -C "$project_root" rev-parse "$task_branch" 2>/dev/null)" || branch_sha=""
      if [[ -n "$resulting_sha" && "$branch_sha" == "$resulting_sha" ]]; then
        local wrc=0
        _pfsm_epic_finish_write "$plan_id" "$epic_id" "$run_id" "$task_branch" "$branch_sha" "$plan_branch" "$evidence_dir" "$op_id" || wrc=$?
        exit "$wrc"
      fi
    fi

    echo "PRECONDITION FAIL: ${task_branch} exists with no manifest entry for ${plan_id} and no matching in-flight operation record — cannot prove lineage (manually created, or belongs to a different plan)." >&2
    exit 1
  fi

  # ── Branch does not exist — fresh creation path ──────────────────────────
  local reconcile_status=""
  reconcile_status="$(plan_op_reconcile "$plan_id" "$op_id" 2>/dev/null)" || true
  if [[ "$reconcile_status" == "git_applied" || "$reconcile_status" == "state_committed" ]]; then
    echo "PRECONDITION FAIL: operation record for ${plan_id}/${epic_id} epic-start claims '${reconcile_status}' but ${task_branch} does not exist — manual reconciliation required." >&2
    exit 5
  fi

  local brc=0
  plan_op_begin "$plan_id" "$op_id" "epic-start" "$epic_id" "" || brc=$?
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record epic-start intent for ${epic_id} (rc=${brc})." >&2
    exit "$brc"
  fi

  local lock_path; lock_path="$(_pfsm_plan_lock_path "$plan_id")"
  aid_lock_acquire "$lock_path" "$AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S" || {
    echo "PRECONDITION FAIL: could not acquire plan lock for ${plan_id}." >&2
    exit 3
  }
  local fd="$AID_LOCK_FD"

  # Read the plan head ONCE inside the plan lock.
  local plan_head=""
  plan_head="$(git -C "$project_root" rev-parse --verify --quiet "$plan_branch" 2>/dev/null)" || plan_head=""
  if [[ -z "$plan_head" ]]; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: ${plan_branch} not found — run plan-start first." >&2
    exit 1
  fi

  if git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: ${task_branch} appeared concurrently while acquiring the lock — retry." >&2
    exit 1
  fi

  if ! git -C "$project_root" branch "$task_branch" "$plan_head" >/dev/null 2>&1; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: git branch ${task_branch} ${plan_head} failed (name collision or permission) — op record stays at intent, retry when resolved." >&2
    exit 1
  fi

  aid_lock_release "$fd"

  local grc=0
  plan_op_mark_git_applied "$plan_id" "$op_id" "$plan_head" || grc=$?
  if [[ "$grc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: ${task_branch} created but could not record git_applied (rc=${grc}) — retry to converge." >&2
    exit "$grc"
  fi

  local wrc=0
  _pfsm_epic_finish_write "$plan_id" "$epic_id" "$run_id" "$task_branch" "$plan_head" "$plan_branch" "$evidence_dir" "$op_id" || wrc=$?
  exit "$wrc"
}

# =============================================================================
# cmd_plan_state <plan_id> [--repair] [--attest-source-ref <ref> --reason <text> --epic <epic_id>]
#                [--project-root ...]
# =============================================================================
cmd_plan_state() {
  local plan_id="" repair=0 attest_ref="" attest_reason="" attest_epic="" project_root_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repair) repair=1; shift ;;
      --attest-source-ref) attest_ref="${2:-}"; shift 2 ;;
      --reason) attest_reason="${2:-}"; shift 2 ;;
      --epic) attest_epic="${2:-}"; shift 2 ;;
      --project-root) project_root_opt="${2:-}"; shift 2 ;;
      --*) echo "ERROR: plan-state: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"; else echo "ERROR: plan-state: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done
  if [[ -z "$plan_id" ]]; then
    echo "Usage: aid-plan-fsm.sh plan-state <plan_id> [--repair] [--attest-source-ref <ref> --reason <text> --epic <epic_id>] [--project-root <path>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: plan-state: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi

  local project_root
  project_root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$project_root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$project_root"

  if [[ -n "$attest_ref" || -n "$attest_reason" || -n "$attest_epic" ]]; then
    local arc=0
    _pfsm_plan_state_attest "$plan_id" "$project_root" "$attest_ref" "$attest_reason" "$attest_epic" || arc=$?
    exit "$arc"
  fi

  if [[ "$repair" -eq 1 ]]; then
    local rrc=0
    _pfsm_plan_state_repair "$plan_id" "$project_root" || rrc=$?
    exit "$rrc"
  fi

  local path; path="$(plan_manifest_path "$plan_id")"
  if [[ ! -f "$path" ]]; then
    echo "not_found"
    exit 1
  fi
  jq -c '{plan_state: .plan_boundary_manifest.plan_state, mode: .plan_boundary_manifest.mode, candidate_sha: .plan_boundary_manifest.candidate_sha, plan_final_run_id: .plan_boundary_manifest.plan_final_run_id}' "$path"
  exit 0
}

# ---------------------------------------------------------------------------
# _pfsm_plan_state_attest <plan_id> <project_root> <ref> <reason> <epic_id>
#
# Promotes ONE epic_runs[] entry from lineage:unproven to lineage:proven.
# THE ONLY code path in this file (or anywhere else in the manifest library)
# that ever performs that flip — plan_manifest_add_epic always writes
# lineage:proven (a fresh epic-start), and --repair only ever WRITES
# unproven, never removes it (see _pfsm_plan_state_repair). Guarded by
# requiring the on-disk lineage to already BE unproven before touching
# anything, so re-attesting an already-proven entry, or an entry that was
# never marked unproven, is rejected rather than silently no-op'd.
# ---------------------------------------------------------------------------
_pfsm_plan_state_attest() {
  local plan_id="$1" project_root="$2" ref="$3" reason="$4" epic_id="$5"

  if [[ -z "$ref" || -z "$reason" || -z "$epic_id" ]]; then
    echo "ERROR: plan-state --attest-source-ref requires --reason and --epic, all non-empty." >&2
    return 2
  fi
  if ! _pfsm_validate_epic_id "$epic_id"; then
    echo "ERROR: plan-state --epic must match ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${epic_id}')" >&2
    return 2
  fi

  local path; path="$(plan_manifest_path "$plan_id")"
  if [[ ! -f "$path" ]]; then
    echo "PRECONDITION FAIL: no manifest for ${plan_id} — nothing to attest." >&2
    return 1
  fi

  local entry_json="" erc=0
  entry_json="$(plan_manifest_get "$plan_id" ".plan_boundary_manifest.epic_runs[] | select(.epic_id==\"${epic_id}\")")" || erc=$?
  if [[ "$erc" -eq 5 ]]; then
    echo "PRECONDITION FAIL: manifest for ${plan_id} is corrupt." >&2
    return 5
  fi
  if [[ -z "$entry_json" ]]; then
    echo "PRECONDITION FAIL: no epic_runs entry for ${epic_id} in ${plan_id}'s manifest." >&2
    return 1
  fi

  local lineage=""
  lineage="$(jq -r '.lineage // empty' <<<"$entry_json" 2>/dev/null)"
  if [[ "$lineage" != "unproven" ]]; then
    echo "PRECONDITION FAIL: ${epic_id}'s lineage is '${lineage:-<empty>}', not 'unproven' — attestation only ever promotes an unproven entry." >&2
    return 1
  fi

  local op_id; op_id="$(plan_op_key "plan-state-attest" "$plan_id" "-" "0" "$plan_id")"
  local brc=0
  plan_op_begin "$plan_id" "$op_id" "plan-state-attest" "$plan_id" "" || brc=$?
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record attest intent for ${plan_id} (rc=${brc})." >&2
    return "$brc"
  fi

  # Values are spliced into the jq PROGRAM text as pre-escaped JSON string
  # literals (jq -Rn --arg s "$x" '$s' -> a syntactically valid, safely
  # escaped JSON string token) — plan_manifest_update takes one filter
  # string with no --arg binding support, so this is the safe way to embed
  # arbitrary --reason / --attest-source-ref text without risking a filter
  # injection via an embedded quote/backslash.
  local esc_ref esc_reason esc_epic esc_now now
  esc_ref="$(jq -Rn --arg s "$ref" '$s')"
  esc_reason="$(jq -Rn --arg s "$reason" '$s')"
  esc_epic="$(jq -Rn --arg s "$epic_id" '$s')"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  esc_now="$(jq -Rn --arg s "$now" '$s')"

  local filter="(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == ${esc_epic} then (.epic_source_ref = ${esc_ref} | .lineage = \"proven\" | .attestation_reason = ${esc_reason} | .attested_at = ${esc_now}) else . end])"

  local urc=0
  plan_manifest_update "$plan_id" "$filter" >/dev/null || urc=$?
  if [[ "$urc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: attestation write failed for ${epic_id} (rc=${urc}) — op remains at intent, retry converges." >&2
    return "$urc"
  fi

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record attest state_committed for ${plan_id} (rc=${crc})." >&2
    return "$crc"
  fi

  echo "attested ${epic_id} -> ${ref}"
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_plan_state_repair <plan_id> <project_root>
#
# Rebuilds the runtime manifest for a plan whose `.aid-o/` tree was pruned,
# checked out fresh, or never populated. Reconstructs ONLY what Git (and the
# git-tracked `.aid-lifecycle/manifests/<plan_id>.yaml`) can prove; never
# fabricates lineage.
#
# Refuses to run while the cached plan_state is past PLAN_SYNC — a repaired
# manifest must never be able to invent a candidate binding (PLAN_GATES and
# later stages depend on `candidate_sha`, which repair has no way to
# reconstruct honestly).
#
# EPIC restoration heuristic (documented here since it is a judgment call,
# not a spec-mandated algorithm): the source of truth for WHICH epics belong
# to this plan is the git-tracked declared_epics[] in
# `.aid-lifecycle/manifests/<plan_id>.yaml` (survives a prune of `.aid-o/`).
# For each declared epic:
#   - a merge commit reachable from `plan/<plan_id>` whose subject line
#     contains the literal branch name `task/<epic_id>/main` is taken as
#     proof of a merge — git's own default merge-commit message embeds the
#     source branch name (`Merge branch 'task/<epic_id>/main' [into
#     plan/<plan_id>]`). Restored as `merged_to_plan`, `lineage: proven`,
#     `epic_source_ref: plan/<plan_id>`, `epic_base_commit` reconstructed as
#     `merge-base(<merge_commit>^1, <merge_commit>^2)` — provable from the
#     merge commit's own two parents, not from anything that could have been
#     pruned.
#   - otherwise, if `task/<epic_id>/main` still exists as a live branch, it
#     is restored as `running`, `lineage: unproven`, `epic_source_ref: null`
#     — its TRUE origin cannot be reconstructed (the queue records
#     `plan_id`/`merge_target`, not the original source ref), so repair
#     records that honestly instead of guessing. `epic_base_commit` is still
#     populated (the schema requires a real 40-hex sha regardless of
#     lineage) with `merge-base(task_branch, plan_branch)` as a best-effort,
#     NON-authoritative value — `lineage: unproven` is what actually blocks
#     a future lineage check (Step 5), not the presence/absence of this
#     field.
#   - otherwise (no merge, no live branch) the epic has no Git evidence of
#     ever having started and is left OUT of epic_runs[] entirely, matching
#     epic-start's own behavior (an entry exists only once an EPIC has
#     actually started).
# `run_id`/`evidence_dir` for every repaired entry are synthetic
# placeholders (`R-repaired-<epic_id>` / `.aid-o/work/evidence/<epic_id>/repaired`)
# — the originals are lost with the prune; only the LINEAGE fields carry
# real evidentiary weight.
# ---------------------------------------------------------------------------
_pfsm_plan_state_repair() {
  local plan_id="$1" project_root="$2"
  local plan_branch="plan/${plan_id}"

  if ! git -C "$project_root" rev-parse --verify --quiet "refs/heads/${plan_branch}" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: ${plan_branch} not found — cannot repair a plan that was never started." >&2
    return 1
  fi

  local target_branch; target_branch="$(aid_target_branch)"

  local cur_state="" src=0
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || src=$?
  if [[ "$src" -eq 0 ]]; then
    case "$cur_state" in
      PLAN_GATES|PLAN_REVIEW|PLAN_FIX|AWAITING_PM|PLAN_MERGING|CLOSED|ABORTED)
        echo "PRECONDITION FAIL: plan ${plan_id} is past PLAN_SYNC (state=${cur_state}) — repair refuses to run (would risk fabricating a candidate binding)." >&2
        return 1
        ;;
    esac
  fi

  local mode; mode="$(aid_lifecycle_plan_mode "$plan_id" "$project_root")"

  local base_sha=""
  base_sha="$(git -C "$project_root" merge-base "$plan_branch" "$target_branch" 2>/dev/null)" || base_sha=""
  if [[ -z "$base_sha" ]]; then
    echo "PRECONDITION FAIL: cannot compute merge-base(${plan_branch}, ${target_branch})." >&2
    return 1
  fi

  local op_id; op_id="$(plan_op_key "plan-state-repair" "$plan_id" "-" "0" "$plan_id")"
  local brc=0
  plan_op_begin "$plan_id" "$op_id" "plan-state-repair" "$plan_id" "" || brc=$?
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record repair intent for ${plan_id} (rc=${brc})." >&2
    return "$brc"
  fi

  if [[ ! -f "$(plan_state_path "$plan_id")" ]]; then
    plan_state_init "$plan_id" "$mode" "$plan_branch" "$target_branch" >/dev/null || {
      echo "PRECONDITION FAIL: plan_state_init failed while repairing ${plan_id}." >&2
      return 1
    }
  fi

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    plan_manifest_init "$plan_id" "$plan_branch" "$target_branch" "$base_sha" "$base_sha" "$mode" >/dev/null || {
      echo "PRECONDITION FAIL: plan_manifest_init failed while repairing ${plan_id}." >&2
      return 1
    }
  fi

  # Repair always fully recomputes epic bookkeeping from Git — never layers
  # incrementally on top of a possibly-stale prior epic_runs[].
  plan_manifest_update "$plan_id" \
    '.plan_boundary_manifest.epics = [] | .plan_boundary_manifest.active_epics = [] | .plan_boundary_manifest.total_epics = 0 | .plan_boundary_manifest.epic_runs = []' \
    >/dev/null || {
      echo "PRECONDITION FAIL: could not reset epic bookkeeping while repairing ${plan_id}." >&2
      return 1
    }

  local lifecycle_manifest; lifecycle_manifest="$(aid_manifest_path "$plan_id" "$project_root")"
  local -a declared_epics=()
  if [[ -f "$lifecycle_manifest" ]]; then
    mapfile -t declared_epics < <(yq -r '.declared_epics[].id' "$lifecycle_manifest" 2>/dev/null)
  fi

  local eid
  for eid in "${declared_epics[@]:-}"; do
    [[ -z "$eid" ]] && continue
    local task_branch="task/${eid}/main"

    local merge_commit=""
    merge_commit="$(git -C "$project_root" log --merges --format='%H%x09%s' "$plan_branch" 2>/dev/null \
      | grep -F "$task_branch" | head -1 | cut -f1)" || merge_commit=""

    if [[ -n "$merge_commit" ]]; then
      local ebc=""
      ebc="$(git -C "$project_root" merge-base "${merge_commit}^1" "${merge_commit}^2" 2>/dev/null)" || ebc=""
      if [[ -n "$ebc" ]]; then
        plan_manifest_add_epic "$plan_id" "$eid" "R-repaired-${eid}" "$task_branch" "$ebc" "$plan_branch" ".aid-o/work/evidence/${eid}/repaired" >/dev/null || true
        plan_manifest_set_epic_status "$plan_id" "$eid" "merged_to_plan" "$merge_commit" >/dev/null || true
        continue
      fi
      # A merge commit matched by name but isn't a real two-parent merge
      # (e.g. squashed) — fall through to the unproven/no-evidence paths
      # below rather than fabricating a base.
    fi

    if git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1; then
      local ubc=""
      ubc="$(git -C "$project_root" merge-base "$task_branch" "$plan_branch" 2>/dev/null)" || ubc=""
      [[ -z "$ubc" ]] && continue
      plan_manifest_add_epic "$plan_id" "$eid" "R-repaired-${eid}" "$task_branch" "$ubc" "" ".aid-o/work/evidence/${eid}/repaired" >/dev/null || true
      # plan_manifest_add_epic always writes lineage:proven for a supplied
      # (even empty->null) epic_source_ref — flip it explicitly. This is
      # the ONLY place other than a hand-authored fixture that ever WRITES
      # unproven; attest (above) is the only place that ever clears it.
      local esc_eid; esc_eid="$(jq -Rn --arg s "$eid" '$s')"
      local flip_filter="(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == ${esc_eid} then (.lineage = \"unproven\") else . end])"
      plan_manifest_update "$plan_id" "$flip_filter" >/dev/null || true
    fi
  done

  # Only advance plan_state past OPEN if Git evidence actually showed epic
  # activity — never fabricate progress.
  local total_epics=""
  total_epics="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.total_epics')" || total_epics="0"
  if [[ -n "$total_epics" && "$total_epics" =~ ^[0-9]+$ && "$total_epics" -gt 0 ]]; then
    local live_state=""
    live_state="$(plan_state_get "$plan_id" "plan_state")" || live_state=""
    if [[ "$live_state" == "OPEN" ]]; then
      plan_state_transition "$plan_id" "OPEN" "EPIC_INTEGRATION" >/dev/null || true
    fi
    plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_state = "EPIC_INTEGRATION"' >/dev/null || true
  fi

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record repair state_committed for ${plan_id} (rc=${crc})." >&2
    return "$crc"
  fi

  jq -c '{plan_state: .plan_boundary_manifest.plan_state, mode: .plan_boundary_manifest.mode, epics: .plan_boundary_manifest.epics, epic_runs: .plan_boundary_manifest.epic_runs}' "$(plan_manifest_path "$plan_id")"
  return 0
}

# =============================================================================
# Dispatch — mirrors aid-fsm.sh's own top-level `case "$sub" in ...` shape,
# kept much smaller (three subcommands).
# =============================================================================
_aid_plan_fsm_usage() {
  cat <<'EOF'
Usage: aid-plan-fsm.sh <subcommand> [args...]

Subcommands:
  plan-start <plan_id> [--mode plan_branch|legacy_epic_release_mode] [--project-root <path>] [--op-id <id>]
  epic-start <plan_id> <epic_id> [--run-id <id>] [--project-root <path>] [--op-id <id>]
  plan-state <plan_id> [--repair] [--attest-source-ref <ref> --reason <text> --epic <epic_id>] [--project-root <path>]
EOF
}

main() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    plan-start) cmd_plan_start "$@" ;;
    epic-start) cmd_epic_start "$@" ;;
    plan-state) cmd_plan_state "$@" ;;
    -h|--help|"")
      _aid_plan_fsm_usage
      [[ -z "$sub" ]] && exit 2
      exit 0
      ;;
    *)
      _aid_plan_fsm_usage >&2
      echo "ERROR: unknown subcommand: $sub" >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
