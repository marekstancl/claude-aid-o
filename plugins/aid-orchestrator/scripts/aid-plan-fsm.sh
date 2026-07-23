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
#   aid-plan-fsm.sh plan-start <plan_id> --mode plan_branch|legacy_epic_release_mode
#                    [--project-root <path>] [--op-id <id>]
#     (--mode is MANDATORY — IMP-271; plan_branch is refused until the P068
#      plan-final commands are installed — no override, the refusal lifts
#      automatically when those commands land)
#   aid-plan-fsm.sh epic-start <plan_id> <epic_id> [--run-id <id>]
#                    [--project-root <path>] [--op-id <id>]
#   aid-plan-fsm.sh plan-state <plan_id>
#   aid-plan-fsm.sh plan-state <plan_id> --repair
#   aid-plan-fsm.sh plan-state <plan_id> --attest-source-ref <ref> --reason <text> --epic <epic_id>
#
# P064 EPIC E-064-2_2 (Step 1 = the parent plan's Step 6) adds the merge half:
#   aid-plan-fsm.sh epic-complete <plan_id> <epic_id> [--abandon --reason <text>]
#                    [--supersede-by <epic_id> --reason <text>]
#                    [--full-tests --reason <text>] [--project-root <path>] [--op-id <id>]
#   aid-plan-fsm.sh epic-merge-to-plan <plan_id> <epic_id> [--expected-plan-sha <sha>]
#                    [--project-root <path>] [--op-id <id>]
# — see the dedicated section header above cmd_epic_complete for their model
# (ancestry proof as the only accepted evidence, why epic-complete writes no
# `pending` status and no lifecycle artifact, and the lock discipline).
#
# `--target-ref` (present in the parent plan's own CLI sketch for a LATER
# step's needs) is deliberately NOT implemented here — nothing in this step's
# Acceptance Criteria requires overriding `aid_target_branch()`'s resolved
# branch, and adding it would multiply the branch-identity paths this file
# has to reason about for no tested benefit.
#
# `plan-finalize`, `plan-merge-to-main`, `plan-close-check` and `inventory`
# remain P068/later-step subcommands; this file does not implement them.
# Neither `epic-start` NOR `epic-merge-to-plan` performs a queue write — Step 7
# owns every queue write and wires itself into both (the manifest is the
# authority for EPIC status, the queue a derived view; that one-way edge is
# what keeps Steps 6 and 7 free of a producer/consumer cycle).
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
# **Last Updated:** 2026-07-23
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
  local lineage source_ref recorded_base
  lineage="$(jq -r '.lineage // empty' <<<"$entry_json" 2>/dev/null)"
  source_ref="$(jq -r '.epic_source_ref // empty' <<<"$entry_json" 2>/dev/null)"
  recorded_base="$(jq -r '.epic_base_commit // empty' <<<"$entry_json" 2>/dev/null)"

  if [[ "$lineage" != "proven" ]]; then
    echo "PRECONDITION FAIL: ${task_branch}'s manifest entry has lineage='${lineage:-<empty>}' (must be proven) — refusing to treat it as authoritative." >&2
    return 1
  fi
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

# ---------------------------------------------------------------------------
# _pfsm_plan_final_installed — mechanical probe (IMP-271): does THIS running
# script's own dispatcher recognise BOTH compensating plan-final subcommands
# (`plan-finalize` AND `plan-merge-to-main`)? Until P068 installs them,
# `--mode plan_branch` would create a plan that structurally skips the per-EPIC
# release stack (P064) yet CANNOT be closed — the only commands that could
# close it (plan-finalize / plan-merge-to-main) do not exist. The check reads
# the running script's own source for the two dispatch case arms rather than a
# hardcoded verdict, so when P068 adds the subcommands the refusal in
# cmd_plan_start lifts with NO edit to this guard. Returns 0 iff both arms are
# present, 1 otherwise (including an unreadable source — fail closed).
# ---------------------------------------------------------------------------
_pfsm_plan_final_installed() {
  local self="${BASH_SOURCE[0]}"
  [[ -r "$self" ]] || return 1
  grep -Eq '^[[:space:]]*plan-finalize\)' "$self" || return 1
  grep -Eq '^[[:space:]]*plan-merge-to-main\)' "$self" || return 1
  return 0
}

# =============================================================================
# cmd_plan_start <plan_id> --mode <...> [--project-root ...] [--op-id ...]
#
# `--mode` is MANDATORY (IMP-271): there is deliberately no silent default,
# because a defaulted `plan_branch` would create a plan that skips the per-EPIC
# release stack yet cannot be closed until P068 installs the plan-final
# commands. `--mode plan_branch` is additionally HARD-REFUSED while those
# commands are not installed — there is no override flag (the earlier
# `--allow-incomplete-plan-final` escape hatch was removed: in AUTO mode the
# controller agent supplied it itself, so it was self-asserted, not
# authorization, and bypassed the very refusal it was meant to constrain). The
# refusal lifts automatically, with no edit here, once the mechanical probe
# `_pfsm_plan_final_installed` sees both plan-final subcommands in the
# dispatcher (i.e. when P068 lands them).
# =============================================================================
cmd_plan_start() {
  local plan_id="" mode="" project_root_opt="" op_id_opt=""
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
    echo "Usage: aid-plan-fsm.sh plan-start <plan_id> --mode plan_branch|legacy_epic_release_mode [--project-root <path>] [--op-id <id>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: plan-start: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  # IMP-271: --mode is required, no silent default. Fail BEFORE any root
  # resolution or write, so an omission creates no state file, no branch, no
  # manifest, and commits nothing.
  if [[ -z "$mode" ]]; then
    echo "ERROR: plan-start: --mode is REQUIRED and has no default (IMP-271). Pass '--mode plan_branch' or '--mode legacy_epic_release_mode' explicitly. There is deliberately no default: P064 makes plan_branch structurally skip the per-EPIC release stack, and the compensating plan-final close commands (plan-finalize / plan-merge-to-main) do not exist until P068 — a defaulted plan_branch would create a plan that skips verification yet cannot be closed." >&2
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

  # IMP-271: HARD-REFUSE a plan_branch plan while the compensating plan-final
  # close commands are not installed. There is no override — the earlier
  # `--allow-incomplete-plan-final` escape hatch was removed because in AUTO mode
  # the controller agent minted it itself, so it was self-asserted, not
  # authorization, and defeated this fail-closed refusal. The refusal lifts
  # automatically, with no edit here, once `_pfsm_plan_final_installed` sees both
  # subcommands in the dispatcher (P068). Placed AFTER preflight + the
  # closed-plan check (both read only), so a refusal still creates nothing.
  if [[ "$mode" == "plan_branch" ]] && ! _pfsm_plan_final_installed; then
    echo "PRECONDITION FAIL: plan-start ${plan_id} --mode plan_branch is unavailable (IMP-271): the compensating plan-final commands 'plan-finalize' and 'plan-merge-to-main' are not yet installed in this aid-plan-fsm.sh (they arrive with P068). A plan_branch plan structurally skips the per-EPIC release stack (P064) but can only be closed by those commands — creating one now would strand it (skips verification yet cannot close). Use '--mode legacy_epic_release_mode'. plan_branch becomes available automatically once the P068 plan-final commands are installed; there is deliberately no override." >&2
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
# ── STEP 6 (P064 EPIC E-064-2_2): epic-complete / epic-merge-to-plan ─────────
#
# `epic-complete` finalizes ONE EPIC without any release action; then
# `epic-merge-to-plan` integrates its task branch into `plan/<plan_id>` inside
# one reconcilable transaction. Together they replace the prose merge
# instruction in skills/pipeline.md for plan-branch plans. The critical
# inversion versus the legacy flow: the merge target is `plan/<plan_id>`, and
# the target branch (`main`) is provably never read or written here.
#
# ── ANCESTRY PROOF IS THE ONLY ACCEPTED EVIDENCE ────────────────────────────
# `merged_to_plan` is written if and only if a specific merge commit is
# provably an ancestor of `plan/<plan_id>` (`git merge-base --is-ancestor`).
# `state: DONE` in an EPIC's own FSM state file, a deleted task branch, and a
# queue entry claiming `completed` are explicitly NOT sufficient — that trio
# is exactly what aid-fsm.sh's `_revalidate_one_dep` fallback chain accepts
# today, and what this command replaces for same-plan dependencies. A task
# branch that is gone with no recorded, proven merge commit exits 1
# (`unproven_merge`) rather than silently unblocking anything.
#
# ── WHY `epic-complete` DOES NOT WRITE STATUS `pending` ─────────────────────
# The step spec says epic-complete "sets the manifest entry status to
# `pending` merge". The manifest's status vocabulary
# (`_AID_EPIC_STATUS_TRANSITIONS`, lib/aid-plan-manifest.sh) uses `pending` as
# the PRE-`running` state and has no `running -> pending` edge — writing it
# literally is rejected by the library, which this step must not modify. The
# intent ("finalized, awaiting merge") is therefore recorded as a dedicated
# `merge_status: pending` field on the epic_runs[] entry, leaving `status` at
# `running` until epic-merge-to-plan's ancestry proof moves it to
# `merged_to_plan`. Step 7's queue writer mirrors `status`; `merge_status` is
# the finer-grained fact it can additionally consult.
#
# ── WHY `epic-complete` MAKES NO LIFECYCLE WRITE ────────────────────────────
# An abandoned/superseded EPIC must eventually be re-scoped in the git-tracked
# lifecycle manifest (aid_plan_closure_state requires every `scope: required`
# declared EPIC to carry a delivery binding and an accepted review). But
# `_aid_lc_require_target_branch` refuses every lifecycle write unless HEAD is
# the target branch, and epic-complete runs on a task branch — there is no
# executable path for that write from here. P064 records the terminal status
# and reason in the RUNTIME manifest and stops; P068 carries the deferred
# re-scope as CF1.
#
# ── LOCK DISCIPLINE (same deadlock hazard as epic-start) ────────────────────
# `plan_op_*` take the plan's state-file lock internally, so the explicit hold
# around the Git work is released BEFORE calling them (see this file's header:
# flock(2) treats a second fd on the same file as an independent holder, so a
# nested acquire blocks forever). The plan lock therefore covers exactly
# checkout + merge + checkout-back.
# =============================================================================

# _pfsm_is_ancestor <root> <maybe_ancestor> <descendant> — the ONE ancestry
# primitive both commands accept as proof.
_pfsm_is_ancestor() {
  git -C "$1" merge-base --is-ancestor "$2" "$3" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# _pfsm_require_optval <command> <flag> <remaining_argc>
# A value-taking flag with nothing after it is a USAGE ERROR, never a silent
# no-op: `shift 2` with a single argument left shifts nothing and returns 1,
# and with no `set -e` the enclosing `while [[ $# -gt 0 ]]` loop then
# re-matches the same arm forever (the command hangs instead of exiting 2).
# Used by the two commands in this section; the older commands' option arms
# are deliberately left alone here and carry the same latent bug.
# ---------------------------------------------------------------------------
_pfsm_require_optval() {
  local cmd="$1" flag="$2" argc="$3"
  if [[ "$argc" -lt 2 ]]; then
    echo "ERROR: ${cmd}: ${flag} requires a value." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_restore_head <root> <orig_branch> — put HEAD back where the operator
# left it, and NEVER claim a restoration that did not happen: a swallowed
# checkout-back failure leaves the operator standing on the plan branch
# (possibly with conflict markers) while the message asserts otherwise.
# Returns 1 after naming the branch HEAD is ACTUALLY on.
# ---------------------------------------------------------------------------
_pfsm_restore_head() {
  local root="$1" orig_branch="$2"
  [[ -n "$orig_branch" ]] || return 0
  local out="" rc=0
  out="$(git -C "$root" checkout -q "$orig_branch" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  local now=""
  now="$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null)" || now=""
  if [[ -z "$now" ]]; then
    now="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)" || now="<unresolved>"
  fi
  echo "ERROR: HEAD NOT RESTORED — could not check out '${orig_branch}' (rc=${rc}); HEAD is still on '${now}' in ${root}. Inspect with 'git -C ${root} status', clear whatever blocks the checkout (an unresolved merge needs 'git -C ${root} merge --abort'), then run 'git -C ${root} checkout ${orig_branch}' before any further plan command." >&2
  printf '%s\n' "$out" >&2
  return 1
}

# ---------------------------------------------------------------------------
# _pfsm_check_no_merge_in_progress <root> — refuses when the repository is
# mid-merge. Two independent signals, checked separately so the message names
# the real one: a `MERGE_HEAD` left by an unresolved/unaborted merge, and any
# unmerged (stage != 0) index entry. Runs BEFORE the dirty-worktree check so a
# conflicted tree reports the actual cause rather than generic porcelain.
# ---------------------------------------------------------------------------
_pfsm_check_no_merge_in_progress() {
  local root="$1" git_dir=""
  git_dir="$(git -C "$root" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || git_dir=""
  if [[ -n "$git_dir" && -f "${git_dir}/MERGE_HEAD" ]]; then
    echo "PRECONDITION FAIL: a merge is already in progress (MERGE_HEAD present at ${git_dir}/MERGE_HEAD) — resolve or 'git merge --abort' it before epic-merge-to-plan." >&2
    return 1
  fi
  local unmerged=""
  unmerged="$(git -C "$root" ls-files --unmerged 2>/dev/null)" || unmerged=""
  if [[ -n "$unmerged" ]]; then
    echo "PRECONDITION FAIL: unmerged index entries present — resolve them before epic-merge-to-plan:" >&2
    printf '%s\n' "$unmerged" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_plan_state_set <plan_id> <to> — moves the plan state file to <to>
# along a LEGAL path only (never a new table edge). Already-there is a no-op.
# The one two-hop path: a plan still at OPEN has no direct edge to CONFLICT
# (the table only allows CONFLICT from EPIC_INTEGRATION/PLAN_SYNC/AWAITING_PM/
# PLAN_MERGING), and an EPIC merge is by definition EPIC_INTEGRATION work, so
# it steps through EPIC_INTEGRATION rather than bypassing the machine.
# Returns 1 when no state file exists or no legal path is available — callers
# treat this as best-effort bookkeeping, never as the authoritative record.
# ---------------------------------------------------------------------------
_pfsm_plan_state_set() {
  local plan_id="$1" to="$2" cur="" rc=0
  cur="$(plan_state_get "$plan_id" "plan_state")" || rc=$?
  if [[ "$rc" -ne 0 || -z "$cur" || "$cur" == "not_found" ]]; then
    return 1
  fi
  [[ "$cur" == "$to" ]] && return 0
  if plan_state_transition "$plan_id" "$cur" "$to" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$cur" == "OPEN" ]]; then
    plan_state_transition "$plan_id" "OPEN" "EPIC_INTEGRATION" >/dev/null 2>&1 || return 1
    [[ "$to" == "EPIC_INTEGRATION" ]] && return 0
    plan_state_transition "$plan_id" "EPIC_INTEGRATION" "$to" >/dev/null 2>&1 || return 1
    return 0
  fi
  return 1
}

# _pfsm_epic_entry <plan_id> <epic_id> — the epic_runs[] entry as JSON text
# (empty when absent). epic_id is format-validated by every caller before it
# reaches the jq expression.
_pfsm_epic_entry() {
  plan_manifest_get "$1" ".plan_boundary_manifest.epic_runs[] | select(.epic_id==\"${2}\")"
}

# ---------------------------------------------------------------------------
# _pfsm_entry_update <plan_id> <epic_id> <jq_assignment>
# Applies a jq assignment expression to exactly ONE epic_runs[] entry.
# Values are spliced into the filter as pre-escaped JSON literals by the
# caller (jq -Rn --arg s "$x" '$s'), matching _pfsm_plan_state_attest's
# convention — plan_manifest_update takes a filter string with no --arg
# binding support.
# NEVER used to write `lineage`: the only two sources of lineage:proven remain
# a normal epic-start and an explicit audited attestation.
# ---------------------------------------------------------------------------
_pfsm_entry_update() {
  local plan_id="$1" epic_id="$2" assign="$3"
  local esc_epic; esc_epic="$(jq -Rn --arg s "$epic_id" '$s')"
  plan_manifest_update "$plan_id" \
    "(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == ${esc_epic} then (${assign}) else . end])" \
    >/dev/null
}

# ---------------------------------------------------------------------------
# _pfsm_find_merge_commit <root> <task_ref> <plan_branch>
# For a task branch whose tip is ALREADY an ancestor of the plan branch,
# recovers the merge commit that brought it in: the OLDEST merge on the
# ancestry path whose second parent contains the task tip. Used only to record
# a merge that provably already happened (convergence), never to authorize a
# new one. Returns 1 when the plan branch contains the work through no merge
# commit at all (a fast-forward or an identical tip) — that case is reported
# as `unproven_merge` rather than credited with a fabricated commit.
# ---------------------------------------------------------------------------
_pfsm_find_merge_commit() {
  local root="$1" task_ref="$2" plan_branch="$3"
  local tip=""
  tip="$(git -C "$root" rev-parse --verify --quiet "$task_ref" 2>/dev/null)" || return 1
  [[ -n "$tip" ]] || return 1
  local m p2
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    p2="$(git -C "$root" rev-parse --verify --quiet "${m}^2" 2>/dev/null)" || continue
    [[ -n "$p2" ]] || continue
    if [[ "$p2" == "$tip" ]] || _pfsm_is_ancestor "$root" "$tip" "$p2"; then
      printf '%s' "$m"
      return 0
    fi
  done < <(git -C "$root" rev-list --merges --ancestry-path --reverse "${tip}..${plan_branch}" 2>/dev/null)
  return 1
}

# ---------------------------------------------------------------------------
# _pfsm_record_merged <plan_id> <epic_id> <merge_commit> <current_status>
# The state-only half of a merge: set the manifest status to merged_to_plan
# with its proving commit, then carry the plan branch head forward. Never
# writes lineage. The `current_status` skip is a DEFENSIVE belt only: the
# caller now refuses every re-merge of an already-`merged_to_plan` entry up
# front (merged_to_plan is terminal — no self-edge, no outgoing edge), so
# this function is never reached with that status. Were it reachable, the
# skip would leave `epic_merge_commit` pointing at the OLD merge while the
# caller reported a new one.
# ---------------------------------------------------------------------------
_pfsm_record_merged() {
  local plan_id="$1" epic_id="$2" merge_commit="$3" current_status="$4"
  if [[ "$current_status" != "merged_to_plan" ]]; then
    local src=0
    plan_manifest_set_epic_status "$plan_id" "$epic_id" "merged_to_plan" "$merge_commit" >/dev/null || src=$?
    if [[ "$src" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record merged_to_plan for ${epic_id} (rc=${src}) — the merge stands, the op stays at git_applied, retry converges." >&2
      return "$src"
    fi
  fi
  # Best-effort: keep the manifest's idea of the plan head (and, through
  # _plan_manifest_atomic_mutate's resync, .revision.head_sha) current. A
  # failure here never invalidates the proven merge above.
  local esc; esc="$(jq -Rn --arg s "$merge_commit" '$s')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_branch_head = ${esc}" >/dev/null 2>&1 || true
  return 0
}

# =============================================================================
# cmd_epic_complete <plan_id> <epic_id> [--abandon --reason <text>]
#                    [--supersede-by <epic_id> --reason <text>]
#                    [--full-tests --reason <text>] [--project-root ...] [--op-id ...]
#
# NO Git action whatsoever — this command only finalizes runtime bookkeeping,
# which is why it deliberately runs no worktree-cleanliness preflight: an EPIC
# is completed from its own task branch, where a dirty tree is the operator's
# business and blocking would buy nothing.
# =============================================================================
cmd_epic_complete() {
  local plan_id="" epic_id="" abandon=0 supersede_by="" reason="" full_tests=0 \
        project_root_opt="" op_id_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --abandon) abandon=1; shift ;;
      --supersede-by)
        _pfsm_require_optval "epic-complete" "$1" "$#" || exit 2
        supersede_by="$2"; shift 2 ;;
      --reason)
        _pfsm_require_optval "epic-complete" "$1" "$#" || exit 2
        reason="$2"; shift 2 ;;
      --full-tests) full_tests=1; shift ;;
      --project-root)
        _pfsm_require_optval "epic-complete" "$1" "$#" || exit 2
        project_root_opt="$2"; shift 2 ;;
      --op-id)
        _pfsm_require_optval "epic-complete" "$1" "$#" || exit 2
        op_id_opt="$2"; shift 2 ;;
      --*) echo "ERROR: epic-complete: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1";
        elif [[ -z "$epic_id" ]]; then epic_id="$1";
        else echo "ERROR: epic-complete: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done
  if [[ -z "$plan_id" || -z "$epic_id" ]]; then
    echo "Usage: aid-plan-fsm.sh epic-complete <plan_id> <epic_id> [--abandon --reason <text>] [--supersede-by <epic_id> --reason <text>] [--full-tests --reason <text>] [--project-root <path>] [--op-id <id>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: epic-complete: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  if ! _pfsm_validate_epic_id "$epic_id"; then
    echo "ERROR: epic-complete: epic_id must match ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${epic_id}')" >&2
    exit 2
  fi
  if [[ "$abandon" -eq 1 && -n "$supersede_by" ]]; then
    echo "ERROR: epic-complete: --abandon and --supersede-by are mutually exclusive — an EPIC has exactly one terminal reason." >&2
    exit 2
  fi
  if [[ -n "$supersede_by" ]] && ! _pfsm_validate_epic_id "$supersede_by"; then
    echo "ERROR: epic-complete: --supersede-by must be an EPIC id matching ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${supersede_by}')" >&2
    exit 2
  fi
  if [[ "$abandon" -eq 1 && -z "$reason" ]]; then
    echo "ERROR: epic-complete: --abandon requires --reason <text>." >&2
    exit 2
  fi
  if [[ -n "$supersede_by" && -z "$reason" ]]; then
    echo "ERROR: epic-complete: --supersede-by requires --reason <text>." >&2
    exit 2
  fi
  if [[ "$full_tests" -eq 1 && -z "$reason" ]]; then
    echo "ERROR: epic-complete: --full-tests requires --reason <text> (a PM-approved mid-plan full gate run is recorded as an exception, never silently)." >&2
    exit 2
  fi

  local project_root
  project_root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$project_root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$project_root"

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    echo "PRECONDITION FAIL: no plan-boundary-manifest for ${plan_id} — run plan-start first." >&2
    exit 1
  fi

  local entry_json="" erc=0
  entry_json="$(_pfsm_epic_entry "$plan_id" "$epic_id")" || erc=$?
  if [[ "$erc" -eq 5 ]]; then
    echo "PRECONDITION FAIL: manifest for ${plan_id} is corrupt." >&2
    exit 5
  fi
  if [[ -z "$entry_json" ]]; then
    echo "PRECONDITION FAIL: no epic_runs entry for ${epic_id} in ${plan_id}'s manifest — run epic-start first." >&2
    exit 1
  fi

  local cur_status
  cur_status="$(jq -r '.status // empty' <<<"$entry_json" 2>/dev/null)"

  local now esc_now esc_reason
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  esc_now="$(jq -Rn --arg s "$now" '$s')"
  esc_reason="$(jq -Rn --arg s "$reason" '$s')"

  local op_id="${op_id_opt:-$(plan_op_key "epic-complete" "$plan_id" "-" "0" "$epic_id")}"

  # ── Terminal path: --abandon / --supersede-by ────────────────────────────
  local target_status=""
  [[ "$abandon" -eq 1 ]] && target_status="abandoned"
  [[ -n "$supersede_by" ]] && target_status="superseded"

  if [[ -n "$target_status" ]]; then
    local brc=0
    plan_op_begin "$plan_id" "$op_id" "epic-complete" "$epic_id" "" || brc=$?
    if [[ "$brc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record epic-complete intent for ${epic_id} (rc=${brc})." >&2
      exit "$brc"
    fi

    if [[ "$cur_status" != "$target_status" ]]; then
      local src=0
      plan_manifest_set_epic_status "$plan_id" "$epic_id" "$target_status" >/dev/null || src=$?
      if [[ "$src" -ne 0 ]]; then
        echo "PRECONDITION FAIL: could not set ${epic_id} to ${target_status} (rc=${src}) — status is '${cur_status}'." >&2
        exit "$src"
      fi
    fi

    local assign=".terminal_reason = ${esc_reason} | .terminal_recorded_at = ${esc_now}"
    if [[ -n "$supersede_by" ]]; then
      local esc_sb; esc_sb="$(jq -Rn --arg s "$supersede_by" '$s')"
      assign="${assign} | .superseded_by = ${esc_sb}"
    fi
    local urc=0
    _pfsm_entry_update "$plan_id" "$epic_id" "$assign" || urc=$?
    if [[ "$urc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record the terminal reason for ${epic_id} (rc=${urc}) — retry converges." >&2
      exit "$urc"
    fi

    local crc=0
    plan_op_commit "$plan_id" "$op_id" || crc=$?
    if [[ "$crc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record epic-complete state_committed for ${epic_id} (rc=${crc})." >&2
      exit "$crc"
    fi

    # DELIBERATELY no lifecycle write — see this section's header. The
    # git-tracked re-scope of an abandoned/superseded EPIC is P068's CF1.
    echo "${epic_id} ${target_status}"
    exit 0
  fi

  # ── Normal completion path ───────────────────────────────────────────────
  case "$cur_status" in
    abandoned|superseded)
      echo "PRECONDITION FAIL: ${epic_id} is already '${cur_status}' (terminal) — refusing to complete it." >&2
      exit 1
      ;;
    merged_to_plan)
      echo "${epic_id} merged_to_plan"
      exit 0
      ;;
  esac

  local evidence_dir run_id
  evidence_dir="$(jq -r '.evidence_dir // empty' <<<"$entry_json" 2>/dev/null)"
  run_id="$(jq -r '.run_id // empty' <<<"$entry_json" 2>/dev/null)"
  if [[ -z "$evidence_dir" ]]; then
    echo "PRECONDITION FAIL: ${epic_id}'s manifest entry records no evidence_dir." >&2
    exit 1
  fi

  # The EPIC FSM state file — read from the run's OWN recorded evidence
  # directory only. No search-and-hope fallback across other runs: an
  # unrelated run reporting DONE is precisely the false-completion signal this
  # command exists to stop accepting.
  local state_file="${project_root}/${evidence_dir}/fsm-state.yaml"
  if [[ ! -f "$state_file" ]]; then
    echo "PRECONDITION FAIL: no fsm-state.yaml at ${state_file} for ${epic_id} (run ${run_id}) — cannot confirm the EPIC reached DONE." >&2
    exit 1
  fi
  local epic_state=""
  epic_state="$(yq -r '.state // ""' "$state_file" 2>/dev/null)" || epic_state=""
  if [[ "$epic_state" != "DONE" ]]; then
    echo "PRECONDITION FAIL: ${epic_id}'s FSM state file reports state='${epic_state:-<empty>}' (must be DONE) at ${state_file}." >&2
    exit 1
  fi

  # The run's gate profile. NULLABLE BY DESIGN: aid-run-gates.sh leaves
  # `.profile` null when no --profile was resolved, so an absent/null value is
  # "no risk signal to raise with", not an error.
  local gates_report="${project_root}/${evidence_dir}/gates/gates_report.json"
  [[ -f "$gates_report" ]] || gates_report="${project_root}/${evidence_dir}/gates_report.json"
  local profile=""
  if [[ -f "$gates_report" ]]; then
    profile="$(jq -r '.profile // empty' "$gates_report" 2>/dev/null)" || profile=""
  fi

  # ═══ Plan-final floor (P064 plan Step 8) ═════════════════════════════════
  # The EPIC boundary deliberately runs a CAPPED profile (lib/aid-gate-profile.sh,
  # boundary=epic), so `gates_report.json.profile` is NOT the risk this EPIC
  # carries — it is only the cheapest run that satisfied the EPIC boundary.
  # The risk itself is recomputed here from the EPIC's real diff and recorded
  # as the plan-final floor, which P068's plan-final stage consumes. The
  # resolver returns that floor out-of-band; `--floor-file` is the channel
  # that survives being read from a subshell.
  #
  # ── THE EPIC'S OWN fsm-state IS DELIBERATELY NOT PASSED ──────────────────
  # (CP3 integration review finding 3.) `gate_profile_resolve` reads exactly
  # one field out of an fsm-state file: `done_phase`. `done_phase == release`
  # escalates the UNBOUNDED view — and the unbounded view IS the accumulated
  # floor. But `epic-complete` runs AFTER `done-advance review release`, so
  # this EPIC's state file ALWAYS says `done_phase: release` by the time we get
  # here. Passing it would have recorded the floor `release` for every EPIC
  # whatever its diff: a docs-only EPIC would pin the whole plan at the release
  # suite, `epic_final_profile_floor` would carry no information at all, and
  # the `targeted_tests` exit-3 escalation below could never raise anything
  # because the floor was already at the ceiling by construction.
  #
  # An EPIC's `done_phase: release` describes THAT EPIC's own FSM tail — its
  # release sub-phase — not the PLAN's final release boundary. Nothing is lost
  # by not inheriting it: the plan-final boundary re-adds the release
  # escalation UNCONDITIONALLY (`boundary=plan_final` -> max(accumulated_floor,
  # release), lib/aid-gate-profile.sh), so the plan-final run still executes
  # the release suite. What is recorded here is then exactly what it claims to
  # be: the risk of THIS EPIC's own epic_base_commit..task_branch diff.
  #
  # WHY AN EMPTY fsm-state POSITIONAL rather than a new flag or a different
  # boundary name: "" is already the library's documented "no release-phase
  # signal to inherit" input (its no-fsm-state guard is an explicit, tested
  # fallback), it needs no change to a resolver shared with aid-fsm.sh's two
  # call sites, and it keeps ONE way to express the release escalation instead
  # of a second, boundary-specific one that would have to be kept in sync.
  local final_floor=""
  local _ec_base _ec_task_branch
  _ec_base="$(jq -r '.epic_base_commit // empty' <<<"$entry_json" 2>/dev/null)" || _ec_base=""
  _ec_task_branch="$(jq -r '.task_branch // empty' <<<"$entry_json" 2>/dev/null)" || _ec_task_branch=""
  if [[ -n "$_ec_base" && -n "$_ec_task_branch" ]] \
     && git -C "$project_root" rev-parse --verify --quiet "$_ec_task_branch" >/dev/null 2>&1; then
    local _ec_paths _ec_floor_file _ec_rc=0
    _ec_paths="$(mktemp -t aid-epic-complete-paths.XXXXXX)"
    _ec_floor_file="$(mktemp -t aid-epic-complete-floor.XXXXXX)"
    git -C "$project_root" diff --name-only "${_ec_base}..${_ec_task_branch}" \
      > "$_ec_paths" 2>/dev/null || true
    gate_profile_resolve "$_ec_paths" "" \
      "${project_root}/${evidence_dir}/review-profile.json" epic \
      --floor-file "$_ec_floor_file" >/dev/null 2>/dev/null || _ec_rc=$?
    if [[ "$_ec_rc" -eq 0 ]]; then
      final_floor="$(head -n1 "$_ec_floor_file" 2>/dev/null)" || final_floor=""
    else
      # A usage error from the resolver is a bug in THIS call, never the
      # operator's problem — but it must not silently mean "no floor".
      echo "WARN: epic-complete: could not resolve the plan-final floor for ${epic_id} (rc=${_ec_rc}) — falling back to the run's recorded profile." >&2
    fi
    rm -f "$_ec_paths" "$_ec_floor_file"
  fi

  # An unknown production path (aid-select-tests.sh exit 3, surfaced as the
  # `targeted_tests` gate row) means the selector could not prove WHICH tests
  # cover the change — it can never be classified down to docs/trivial, so the
  # plan-final floor goes to at least `full`.
  local unknown_production_path=false
  if [[ -f "$gates_report" ]]; then
    local _ec_sel_exit
    _ec_sel_exit="$(jq -r '.gates.targeted_tests.exit_code // empty' "$gates_report" 2>/dev/null)" || _ec_sel_exit=""
    if [[ "$_ec_sel_exit" == "3" ]]; then
      unknown_production_path=true
      final_floor="$(gate_profile_max "${final_floor:-quick}" full 2>/dev/null)" || final_floor="full"
    fi
  fi

  # The run's own profile is a lower bound too (it really executed) — but only
  # when it is one of the five canonical names. A project-defined custom
  # profile is legitimate (aid-fsm.sh's own risk_profile_unresolvable branch
  # treats it as unrankable, not illegal), so it is reported and skipped
  # rather than failing an otherwise complete EPIC.
  if [[ -n "$profile" ]]; then
    if gate_profile_rank "$profile" >/dev/null 2>&1; then
      final_floor="$(gate_profile_max "${final_floor:-quick}" "$profile" 2>/dev/null)" || final_floor="$profile"
    else
      echo "NOTE: epic-complete: gates_report.json for ${epic_id} names a non-canonical gate profile '${profile}' (epic_completion_profile_unranked) — it cannot raise the plan-final floor; the floor comes from the resolver instead." >&2
    fi
  fi

  # gate_profiles absent from execution.yaml: the floor is still recorded (it
  # is a property of the DIFF, not of the config), only profile SELECTION is
  # unavailable — the documented legacy behaviour for a project that has not
  # upgraded its execution.yaml yet.
  local _ec_exec_yaml="${project_root}/.aid-o/config/execution.yaml"
  if [[ ! -f "$_ec_exec_yaml" ]] \
     || ! yq -e '.gate_profiles' "$_ec_exec_yaml" >/dev/null 2>&1; then
    echo "NOTE: epic-complete: gate_profiles_absent — no gate_profiles block in ${_ec_exec_yaml}; recording the plan-final floor '${final_floor:-<none>}' without profile selection." >&2
  fi

  # A gate the PLAN declared mandatory that the active profile excluded must
  # never be silently dropped. It cannot even reach this point without a PM
  # `--force` at GATES:DONE (`plan_gate_profile_excluded` blocks otherwise),
  # so recording it as a mandatory plan-final gate is the compensating
  # control for exactly that override.
  local excluded_plan_gates='[]'
  local _ec_plan_json="${project_root}/${evidence_dir}/plan.json"
  if [[ -f "$gates_report" && -f "$_ec_plan_json" ]]; then
    excluded_plan_gates="$(jq -nc \
      --slurpfile p "$_ec_plan_json" --slurpfile r "$gates_report" \
      '[ (($p[0].gates // []) | if type == "array" then . else [] end)[]
         | select(. as $g | (($r[0].excluded_gates // [])) | index($g) != null) ]' \
      2>/dev/null)" || excluded_plan_gates='[]'
    [[ -n "$excluded_plan_gates" ]] || excluded_plan_gates='[]'
  fi

  local brc=0
  plan_op_begin "$plan_id" "$op_id" "epic-complete" "$epic_id" "" || brc=$?
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record epic-complete intent for ${epic_id} (rc=${brc})." >&2
    exit "$brc"
  fi

  if [[ -n "$final_floor" ]]; then
    # Monotonic by construction (plan_manifest_raise_final_profile only ever
    # moves the floor UP), which is what makes `--full-tests` safe to record
    # as an exception "without lowering the plan-final floor": nothing here
    # CAN lower it.
    local prc=0
    plan_manifest_raise_final_profile "$plan_id" "$final_floor" >/dev/null || prc=$?
    if [[ "$prc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not raise ${plan_id}'s plan-final floor to '${final_floor}' for ${epic_id} (rc=${prc})." >&2
      exit 1
    fi
  fi

  # The plan-wide set of gates the plan-final run MUST execute — the union
  # across EPICs, never a replacement (an earlier EPIC's recorded gate can
  # only be added to).
  if [[ "$excluded_plan_gates" != "[]" ]]; then
    local grc=0
    plan_manifest_update "$plan_id" \
      "(.plan_boundary_manifest.plan_final_required_gates = ((.plan_boundary_manifest.plan_final_required_gates // []) + ${excluded_plan_gates} | unique))" \
      >/dev/null || grc=$?
    if [[ "$grc" -ne 0 ]]; then
      # Never `|| true` here: this record IS the compensating control for a
      # plan-required gate that did not run. Losing it silently is the exact
      # "silently dropped" outcome the plan forbids.
      echo "PRECONDITION FAIL: could not record the mandatory plan-final gate(s) ${excluded_plan_gates} for ${epic_id} (rc=${grc}) — retry converges." >&2
      exit "$grc"
    fi
  fi

  local esc_profile="null"
  [[ -n "$profile" ]] && esc_profile="$(jq -Rn --arg s "$profile" '$s')"
  local esc_floor="null"
  [[ -n "$final_floor" ]] && esc_floor="$(jq -Rn --arg s "$final_floor" '$s')"
  local assign=".merge_status = \"pending\" | .epic_completed_at = ${esc_now} | .epic_completion_profile = ${esc_profile} | .epic_final_profile_floor = ${esc_floor} | .unknown_production_path = ${unknown_production_path} | .plan_final_required_gates = ${excluded_plan_gates}"
  if [[ "$full_tests" -eq 1 ]]; then
    # The PM-approved mid-plan broad run, audited: reason + the boundary that
    # requested it. Named `epic_full_test_exception` (plan Step 8) — the
    # `epic_` prefix keeps it distinct from a plan-final exception, which is a
    # different act by a different actor.
    assign="${assign} | .epic_full_test_exception = {reason: ${esc_reason}, at: ${esc_now}, boundary: \"epic\"}"
  fi

  local urc=0
  _pfsm_entry_update "$plan_id" "$epic_id" "$assign" || urc=$?
  if [[ "$urc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record completion for ${epic_id} (rc=${urc}) — retry converges." >&2
    exit "$urc"
  fi

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record epic-complete state_committed for ${epic_id} (rc=${crc})." >&2
    exit "$crc"
  fi

  echo "${epic_id} pending"
  exit 0
}

# =============================================================================
# cmd_epic_merge_to_plan <plan_id> <epic_id> [--expected-plan-sha <sha>]
#                         [--project-root ...] [--op-id ...]
# =============================================================================
cmd_epic_merge_to_plan() {
  local plan_id="" epic_id="" expected_sha="" project_root_opt="" op_id_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --expected-plan-sha)
        _pfsm_require_optval "epic-merge-to-plan" "$1" "$#" || exit 2
        expected_sha="$2"; shift 2 ;;
      --project-root)
        _pfsm_require_optval "epic-merge-to-plan" "$1" "$#" || exit 2
        project_root_opt="$2"; shift 2 ;;
      --op-id)
        _pfsm_require_optval "epic-merge-to-plan" "$1" "$#" || exit 2
        op_id_opt="$2"; shift 2 ;;
      --*) echo "ERROR: epic-merge-to-plan: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1";
        elif [[ -z "$epic_id" ]]; then epic_id="$1";
        else echo "ERROR: epic-merge-to-plan: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done
  if [[ -z "$plan_id" || -z "$epic_id" ]]; then
    echo "Usage: aid-plan-fsm.sh epic-merge-to-plan <plan_id> <epic_id> [--expected-plan-sha <sha>] [--project-root <path>] [--op-id <id>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: epic-merge-to-plan: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  if ! _pfsm_validate_epic_id "$epic_id"; then
    echo "ERROR: epic-merge-to-plan: epic_id must match ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${epic_id}')" >&2
    exit 2
  fi

  local project_root
  project_root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$project_root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$project_root"

  # The checks are about the worktree this command actually CHECKS OUT AND
  # MERGES IN — the main worktree (project_root), not wherever the operator
  # happens to stand (a linked worktree never holds `plan/<plan_id>` here).
  _pfsm_check_detached_head "$project_root" || exit 1
  _pfsm_check_no_merge_in_progress "$project_root" || exit 1
  _pfsm_check_clean_worktree "$project_root" || exit 1

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    echo "PRECONDITION FAIL: no plan-boundary-manifest for ${plan_id} — run plan-start first." >&2
    exit 1
  fi

  local entry_json="" erc=0
  entry_json="$(_pfsm_epic_entry "$plan_id" "$epic_id")" || erc=$?
  if [[ "$erc" -eq 5 ]]; then
    echo "PRECONDITION FAIL: manifest for ${plan_id} is corrupt." >&2
    exit 5
  fi
  if [[ -z "$entry_json" ]]; then
    echo "PRECONDITION FAIL: no epic_runs entry for ${epic_id} in ${plan_id}'s manifest — nothing to merge (run epic-start first)." >&2
    exit 1
  fi

  local cur_status recorded_mc
  cur_status="$(jq -r '.status // empty' <<<"$entry_json" 2>/dev/null)"
  recorded_mc="$(jq -r '.epic_merge_commit // empty' <<<"$entry_json" 2>/dev/null)"

  case "$cur_status" in
    abandoned|superseded)
      echo "PRECONDITION FAIL: ${epic_id} is '${cur_status}' (terminal) — refusing to merge it into plan/${plan_id}." >&2
      exit 1
      ;;
  esac

  local plan_branch="plan/${plan_id}" task_branch="task/${epic_id}/main"
  local plan_head=""
  plan_head="$(git -C "$project_root" rev-parse --verify --quiet "refs/heads/${plan_branch}" 2>/dev/null)" || plan_head=""
  if [[ -z "$plan_head" ]]; then
    echo "PRECONDITION FAIL: ${plan_branch} not found — run plan-start first." >&2
    exit 1
  fi

  # The concurrent-writer guard, BEFORE anything is recorded or merged.
  if [[ -n "$expected_sha" ]]; then
    local expected_norm=""
    expected_norm="$(git -C "$project_root" rev-parse --verify --quiet "${expected_sha}^{commit}" 2>/dev/null)" || expected_norm="$expected_sha"
    if [[ "$expected_norm" != "$plan_head" ]]; then
      echo "PRECONDITION FAIL: --expected-plan-sha ${expected_sha} does not match the observed ${plan_branch} head ${plan_head} — another writer moved the plan branch; refusing before the merge." >&2
      exit 1
    fi
  fi

  # ── `merged_to_plan` IS TERMINAL — converge or refuse, never re-merge ────
  # plan_manifest_set_epic_status's transition table gives merged_to_plan no
  # outgoing edge, so there is no honest way to record a SECOND merge commit
  # behind that status. This command therefore either converges read-only on
  # the fact already recorded (the recorded merge commit is still an ancestor
  # of the plan branch and the task branch, if it still exists, is still
  # contained in it) or refuses outright. Silently creating a second merge
  # commit while `epic_merge_commit` keeps naming the first one — which is
  # what Step 7's queue writer mirrors — is the one outcome not allowed.
  if [[ "$cur_status" == "merged_to_plan" ]]; then
    if [[ -z "$recorded_mc" ]] || ! _pfsm_is_ancestor "$project_root" "$recorded_mc" "$plan_branch"; then
      echo "PRECONDITION FAIL: ${epic_id} is already 'merged_to_plan' but its recorded merge commit '${recorded_mc:-<none>}' is not an ancestor of ${plan_branch} — the manifest status is terminal and this command will not create a second merge; reconcile the manifest against Git by hand." >&2
      exit 1
    fi
    local merged_tip=""
    merged_tip="$(git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" 2>/dev/null)" || merged_tip=""
    if [[ -n "$merged_tip" ]] && ! _pfsm_is_ancestor "$project_root" "$merged_tip" "$plan_branch"; then
      echo "PRECONDITION FAIL: ${epic_id} is already merged_to_plan at ${recorded_mc} but its task branch has moved to ${merged_tip}, which is not contained in ${plan_branch}; the manifest status is terminal and this command will not create a second merge. Land the newer work through its own EPIC." >&2
      exit 1
    fi
    echo "$recorded_mc"
    exit 0
  fi

  # ── Provenance gate ──────────────────────────────────────────────────────
  # EVERY path below this point writes `merged_to_plan`, and that write is
  # what downstream consumers (Step 7's queue writer, aid-fsm.sh's dependency
  # resolution) read as "this EPIC's work is delivered". epic-start already
  # refuses an entry whose lineage is not proven; minting the delivery claim
  # is at least as authoritative, so it refuses too — a true ancestry claim
  # about a branch of unestablished provenance is not a delivery proof.
  # A narrow check on purpose: _pfsm_verify_epic_lineage additionally demands
  # epic_source_ref == plan/<plan_id> and re-derives the merge-base against
  # the plan branch, which is wrong for a branch that is already merged in;
  # weakening THAT helper would weaken epic-start's own guard.
  # DELIBERATELY not applied to the terminal convergence above: that path
  # writes nothing and only reads back a fact the manifest already records,
  # so refusing it would wedge exactly the `plan-state --repair` recovery
  # whose entries are unproven by construction.
  local lineage=""
  lineage="$(jq -r '.lineage // empty' <<<"$entry_json" 2>/dev/null)"
  if [[ "$lineage" != "proven" ]]; then
    echo "PRECONDITION FAIL: epic_lineage_unproven — ${epic_id}'s manifest entry has lineage='${lineage:-<empty>}' (must be proven); refusing to record a merge into ${plan_branch} on unestablished provenance. Sanctioned recovery: attest the origin explicitly — 'aid-plan-fsm.sh plan-state ${plan_id} --attest-source-ref ${plan_branch} --reason <text> --epic ${epic_id}'. Do NOT run 'plan-state --repair' first: attestation's precondition IS an unproven entry, and --repair rebuilds every epic_runs[] entry as unproven with placeholder run_id/evidence_dir, discarding the attestation of healthy siblings." >&2
    exit 1
  fi

  local op_id="${op_id_opt:-$(plan_op_key "epic-merge-to-plan" "$plan_id" "-" "0" "$epic_id")}"

  # ── The task branch is gone ──────────────────────────────────────────────
  # Branch deletion is not evidence by itself, but it does not invalidate a
  # merge that is already proven.
  if ! git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1; then
    if [[ -n "$recorded_mc" ]] && _pfsm_is_ancestor "$project_root" "$recorded_mc" "$plan_branch"; then
      local wrc=0
      _pfsm_record_merged "$plan_id" "$epic_id" "$recorded_mc" "$cur_status" || wrc=$?
      [[ "$wrc" -ne 0 ]] && exit "$wrc"
      echo "$recorded_mc"
      exit 0
    fi
    echo "PRECONDITION FAIL: unproven_merge — ${task_branch} does not exist and no recorded merge commit is an ancestor of ${plan_branch}. A deleted branch, a 'state: DONE' run and a queue entry claiming completion are NOT proof; re-create the branch or record a proven merge." >&2
    exit 1
  fi

  local task_tip
  task_tip="$(git -C "$project_root" rev-parse "$task_branch" 2>/dev/null)" || task_tip=""
  if [[ -z "$task_tip" ]]; then
    echo "PRECONDITION FAIL: cannot resolve ${task_branch}." >&2
    exit 1
  fi

  # ── Crash resume: the Git merge landed, the state write did not ──────────
  local reconcile_status=""
  reconcile_status="$(plan_op_reconcile "$plan_id" "$op_id" 2>/dev/null)" || true
  if [[ "$reconcile_status" == "git_applied" ]]; then
    local resulting_sha=""
    resulting_sha="$(_pfsm_last_resulting_sha "$plan_id" "$op_id")"
    if [[ -z "$resulting_sha" ]] || ! _pfsm_is_ancestor "$project_root" "$resulting_sha" "$plan_branch"; then
      echo "PRECONDITION FAIL: operation record for ${plan_id}/${epic_id} claims git_applied with resulting_sha '${resulting_sha:-<none>}', which is not an ancestor of ${plan_branch} — state/Git divergence, manual reconciliation required." >&2
      exit 5
    fi
    local wrc=0
    _pfsm_record_merged "$plan_id" "$epic_id" "$resulting_sha" "$cur_status" || wrc=$?
    [[ "$wrc" -ne 0 ]] && exit "$wrc"
    local crc=0
    plan_op_commit "$plan_id" "$op_id" || crc=$?
    if [[ "$crc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record epic-merge-to-plan state_committed for ${epic_id} (rc=${crc})." >&2
      exit "$crc"
    fi
    _pfsm_plan_state_set "$plan_id" "EPIC_INTEGRATION" || true
    echo "$resulting_sha"
    exit 0
  fi

  # ── Already merged: converge, never a second merge commit ────────────────
  if _pfsm_is_ancestor "$project_root" "$task_tip" "$plan_branch"; then
    local proven=""
    if [[ -n "$recorded_mc" ]] && _pfsm_is_ancestor "$project_root" "$recorded_mc" "$plan_branch"; then
      proven="$recorded_mc"
    else
      proven="$(_pfsm_find_merge_commit "$project_root" "$task_branch" "$plan_branch")" || proven=""
    fi
    if [[ -z "$proven" ]]; then
      echo "PRECONDITION FAIL: unproven_merge — ${task_branch} is contained in ${plan_branch} but through no merge commit (fast-forward or identical tip), so there is nothing to record as ancestry proof." >&2
      exit 1
    fi
    # Unreachable belt: cur_status == merged_to_plan already returned above.
    if [[ "$cur_status" == "merged_to_plan" && "$recorded_mc" == "$proven" ]]; then
      echo "$proven"
      exit 0
    fi
    local brc=0
    plan_op_begin "$plan_id" "$op_id" "epic-merge-to-plan" "$epic_id" "$plan_head" || brc=$?
    if [[ "$brc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record epic-merge-to-plan intent for ${epic_id} (rc=${brc})." >&2
      exit "$brc"
    fi
    plan_op_mark_git_applied "$plan_id" "$op_id" "$proven" >/dev/null 2>&1 || true
    local wrc=0
    _pfsm_record_merged "$plan_id" "$epic_id" "$proven" "$cur_status" || wrc=$?
    [[ "$wrc" -ne 0 ]] && exit "$wrc"
    local crc=0
    plan_op_commit "$plan_id" "$op_id" || crc=$?
    if [[ "$crc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: could not record epic-merge-to-plan state_committed for ${epic_id} (rc=${crc})." >&2
      exit "$crc"
    fi
    _pfsm_plan_state_set "$plan_id" "EPIC_INTEGRATION" || true
    echo "$proven"
    exit 0
  fi

  # ── The real merge ───────────────────────────────────────────────────────
  local brc=0
  plan_op_begin "$plan_id" "$op_id" "epic-merge-to-plan" "$epic_id" "$plan_head" || brc=$?
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record epic-merge-to-plan intent for ${epic_id} (rc=${brc})." >&2
    exit "$brc"
  fi

  local lock_path; lock_path="$(_pfsm_plan_lock_path "$plan_id")"
  aid_lock_acquire "$lock_path" "$AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S" || {
    echo "PRECONDITION FAIL: could not acquire plan lock for ${plan_id}." >&2
    exit 3
  }
  local fd="$AID_LOCK_FD"

  # Re-read the plan head under the lock — the same concurrent-writer guard,
  # now against a racer that moved the branch since the pre-lock read.
  local locked_head=""
  locked_head="$(git -C "$project_root" rev-parse --verify --quiet "refs/heads/${plan_branch}" 2>/dev/null)" || locked_head=""
  if [[ "$locked_head" != "$plan_head" ]]; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: ${plan_branch} moved from ${plan_head} to ${locked_head:-<gone>} while acquiring the lock — retry." >&2
    exit 1
  fi

  local orig_branch=""
  orig_branch="$(git -C "$project_root" symbolic-ref --short HEAD 2>/dev/null)" || orig_branch=""

  if ! git -C "$project_root" checkout -q "$plan_branch" >/dev/null 2>&1; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: cannot check out ${plan_branch} (checked out in another worktree?) — nothing merged, op stays at intent." >&2
    exit 1
  fi

  local merge_out="" mrc=0
  merge_out="$(git -C "$project_root" merge --no-ff --no-edit \
    -m "merge(epic): ${epic_id} into ${plan_branch}" "$task_branch" 2>&1)" || mrc=$?

  if [[ "$mrc" -ne 0 ]]; then
    # Error Handling: NOT every merge failure is a conflict. A real conflict
    # leaves evidence behind — a MERGE_HEAD, or unmerged (stage != 0) index
    # entries — and is fixed by resolving it. Everything else (an untracked
    # file that would be overwritten, a refusing hook, an unreadable index)
    # leaves nothing to abort and no conflict to resolve, so it must NOT be
    # reported as one and must NOT drive the plan to CONFLICT: an automated
    # controller branching on exit 4 would run a conflict-resolution path
    # against an operator-hygiene problem `git merge --abort` cannot fix.
    local git_dir="" is_conflict=0
    git_dir="$(git -C "$project_root" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || git_dir=""
    if [[ -n "$git_dir" && -f "${git_dir}/MERGE_HEAD" ]]; then
      is_conflict=1
    elif [[ -n "$(git -C "$project_root" ls-files --unmerged 2>/dev/null)" ]]; then
      is_conflict=1
    fi

    if [[ "$is_conflict" -eq 1 ]]; then
      local abort_out="" arc=0
      abort_out="$(git -C "$project_root" merge --abort 2>&1)" || arc=$?
      if [[ "$arc" -ne 0 ]]; then
        echo "ERROR: 'git merge --abort' failed (rc=${arc}) in ${project_root} — the worktree is STILL mid-merge and needs manual cleanup:" >&2
        printf '%s\n' "$abort_out" >&2
      fi
    fi

    # Loud, never swallowed: if HEAD cannot go back, say where it really is.
    _pfsm_restore_head "$project_root" "$orig_branch" || true
    aid_lock_release "$fd"
    # `aborted` has no public plan_op_* setter (the library exposes begin /
    # git_applied / commit only); the append helper is the single writer for
    # every phase, so it is used directly here rather than hand-rolling a
    # second, unlocked JSONL writer.
    _plan_op_append "$plan_id" "$op_id" "epic-merge-to-plan" "$epic_id" "aborted" "" "" || true

    if [[ "$is_conflict" -eq 1 ]]; then
      _pfsm_plan_state_set "$plan_id" "CONFLICT" || true
      echo "MERGE CONFLICT: ${task_branch} does not merge cleanly into ${plan_branch} — plan state is CONFLICT, no completion recorded, ${plan_branch} unchanged." >&2
      printf '%s\n' "$merge_out" >&2
      exit 4
    fi

    echo "MERGE FAILED (not a conflict): git refused to merge ${task_branch} into ${plan_branch} — no MERGE_HEAD and no unmerged index entries, so there is nothing to resolve or abort. The plan state is left where it was, no completion recorded, ${plan_branch} unchanged; fix the repository condition git names below and re-run." >&2
    printf '%s\n' "$merge_out" >&2
    exit 1
  fi

  local merge_commit=""
  merge_commit="$(git -C "$project_root" rev-parse "$plan_branch" 2>/dev/null)" || merge_commit=""
  # A failed restore does not invalidate the merge that just landed, but it is
  # never silent — the operator is told where HEAD actually is.
  _pfsm_restore_head "$project_root" "$orig_branch" || true
  aid_lock_release "$fd"

  if [[ -z "$merge_commit" || "$merge_commit" == "$plan_head" ]]; then
    echo "PRECONDITION FAIL: ${plan_branch} did not advance to a new merge commit (still ${plan_head}) — refusing to record a merge that produced nothing." >&2
    exit 5
  fi

  local grc=0
  plan_op_mark_git_applied "$plan_id" "$op_id" "$merge_commit" || grc=$?
  if [[ "$grc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: merge ${merge_commit} created but could not record git_applied (rc=${grc}) — retry converges." >&2
    exit "$grc"
  fi

  # Ancestry proof — the ONLY accepted evidence, checked against Git itself
  # rather than against what we believe we just did.
  if ! _pfsm_is_ancestor "$project_root" "$merge_commit" "$plan_branch"; then
    echo "PRECONDITION FAIL: ${merge_commit} is not an ancestor of ${plan_branch} after the merge — state/Git divergence, manual reconciliation required." >&2
    exit 5
  fi

  local wrc=0
  _pfsm_record_merged "$plan_id" "$epic_id" "$merge_commit" "$cur_status" || wrc=$?
  [[ "$wrc" -ne 0 ]] && exit "$wrc"

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not record epic-merge-to-plan state_committed for ${epic_id} (rc=${crc})." >&2
    exit "$crc"
  fi

  _pfsm_plan_state_set "$plan_id" "EPIC_INTEGRATION" || true

  echo "$merge_commit"
  exit 0
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
# that ever performs that flip. The only two sources of lineage:proven in the
# whole system are (1) a normal epic-start, which passes the default
# lineage=proven to plan_manifest_add_epic because it observed the branch's
# origin at the moment it created it, and (2) this explicit operator
# attestation, which carries a reason and an op-log audit trail. --repair
# can only ever write unproven (see _pfsm_plan_state_repair) and never
# clears it. Guarded by
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
# SECURITY INVARIANT (P064 E-064-1_2, finding F-2): repair NEVER writes
# `lineage: proven`, on any path, not even transiently. A commit message is
# attacker-controlled free text and can only ever be CANDIDATE DIAGNOSTIC
# information, never authorisation proof — anyone able to push a merge (or
# merely to name a branch confusingly) could otherwise mint a proven lineage
# for a branch cut from anywhere. Every entry repair creates is created
# ALREADY unproven, in the single atomic write that creates it
# (_pfsm_repair_add_unproven below); there is deliberately no
# write-proven-then-flip-to-unproven step, because a crash between those two
# writes would leave a false `proven` on disk. Promotion to proven is only
# ever a normal epic-start or an explicit operator attestation
# (`--attest-source-ref ... --reason ...`, audited in operations.jsonl).
#
# EPIC restoration heuristic (documented here since it is a judgment call,
# not a spec-mandated algorithm): the source of truth for WHICH epics belong
# to this plan is the git-tracked declared_epics[] in
# `.aid-lifecycle/manifests/<plan_id>.yaml` (survives a prune of `.aid-o/`).
# For each declared epic:
#   - a merge commit reachable from `plan/<plan_id>` whose subject line
#     quotes the literal branch name (`'task/<epic_id>/main'`, matching git's
#     own default merge-commit message `Merge branch 'task/<epic_id>/main'
#     [into plan/<plan_id>]`) AND which has `task/<epic_id>/main` as an
#     ancestor is taken as a CANDIDATE record of a merge. Restored as
#     `merged_to_plan` with that `epic_merge_commit` — a status/diagnostic
#     claim, not a lineage claim — but still `lineage: unproven` per the
#     invariant above, with `epic_source_ref: plan/<plan_id>` and
#     `epic_base_commit` reconstructed as `merge-base(<merge_commit>^1,
#     <merge_commit>^2)`, provable from the merge commit's own two parents
#     rather than from anything that could have been pruned. The quoting and
#     the ancestry check are DIAGNOSTIC-ACCURACY hardening (they stop a
#     sibling branch such as `task/<epic_id>/main-fixup`, whose subject
#     merely CONTAINS the victim's name as a substring, from misattributing
#     its merge commit and base to the wrong entry); the lineage invariant,
#     not these checks, is the actual security control.
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
#
# _pfsm_repair_add_unproven <plan_id> <epic_id> <task_branch>
#                           <epic_base_commit> <epic_source_ref>
# (defined immediately below) is the ONE way repair is allowed to create an
# epic_runs[] entry. It hardcodes lineage=unproven, which makes `proven`
# structurally inexpressible inside repair: repair never calls
# plan_manifest_add_epic directly, so no future edit to either of its two
# call sites can accidentally reintroduce an authorisation claim. The write
# is atomic and ALREADY unproven — never proven-then-flipped — so no crash
# window can leave a false `proven` on disk.
# ---------------------------------------------------------------------------
_pfsm_repair_add_unproven() {
  local plan_id="$1" eid="$2" task_branch="$3" base_commit="$4" source_ref="$5"
  plan_manifest_add_epic "$plan_id" "$eid" "R-repaired-${eid}" "$task_branch" \
    "$base_commit" "$source_ref" ".aid-o/work/evidence/${eid}/repaired" "unproven" >/dev/null
}

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

    # Candidate merge commit: the subject must QUOTE the branch name exactly
    # as git's own default merge message does, and the branch must actually
    # be an ancestor of that commit. Both are diagnostic-accuracy checks (see
    # the header) — a subject alone proves nothing, which is why every path
    # below still writes lineage:unproven.
    local merge_commit=""
    merge_commit="$(git -C "$project_root" log --merges --format='%H%x09%s' "$plan_branch" 2>/dev/null \
      | grep -F "'${task_branch}'" | head -1 | cut -f1)" || merge_commit=""

    if [[ -n "$merge_commit" ]]; then
      if ! git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1 \
         || ! git -C "$project_root" merge-base --is-ancestor "refs/heads/${task_branch}" "$merge_commit" >/dev/null 2>&1; then
        # The named branch is gone, or is not reachable through that commit —
        # the subject named it but Git does not corroborate it. Do not credit
        # this entry with a merge commit / base it cannot be shown to own.
        merge_commit=""
      fi
    fi

    if [[ -n "$merge_commit" ]]; then
      local ebc=""
      ebc="$(git -C "$project_root" merge-base "${merge_commit}^1" "${merge_commit}^2" 2>/dev/null)" || ebc=""
      if [[ -n "$ebc" ]]; then
        _pfsm_repair_add_unproven "$plan_id" "$eid" "$task_branch" "$ebc" "$plan_branch" || true
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
      _pfsm_repair_add_unproven "$plan_id" "$eid" "$task_branch" "$ubc" "" || true
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
  plan-start <plan_id> --mode plan_branch|legacy_epic_release_mode [--project-root <path>] [--op-id <id>]
  epic-start <plan_id> <epic_id> [--run-id <id>] [--project-root <path>] [--op-id <id>]
  epic-complete <plan_id> <epic_id> [--abandon --reason <text>] [--supersede-by <epic_id> --reason <text>] [--full-tests --reason <text>] [--project-root <path>] [--op-id <id>]
  epic-merge-to-plan <plan_id> <epic_id> [--expected-plan-sha <sha>] [--project-root <path>] [--op-id <id>]
  plan-state <plan_id> [--repair] [--attest-source-ref <ref> --reason <text> --epic <epic_id>] [--project-root <path>]
EOF
}

main() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    plan-start) cmd_plan_start "$@" ;;
    epic-start) cmd_epic_start "$@" ;;
    epic-complete) cmd_epic_complete "$@" ;;
    epic-merge-to-plan) cmd_epic_merge_to_plan "$@" ;;
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
