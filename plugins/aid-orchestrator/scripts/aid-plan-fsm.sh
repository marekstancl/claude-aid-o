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
# P068 EPIC E-068-1_2 Step 1 adds the FIRST plan-final subcommand:
#   aid-plan-fsm.sh plan-finalize <plan_id> --stage <sync|freeze>
#                    [--frozen-at <rfc3339>] [--project-root <path>]
# P068 Step 2 adds the third stage — the ONE plan-final gate run:
#   aid-plan-fsm.sh plan-finalize <plan_id> --stage gates
#                    [--execution-yaml <path>]
#                    [--substitute-receipt <gate_id>=<receipt path>]...
# — see the section header above `_pfsm_finalize_gates` for the profile
# selection (release, or its pre-declared release-derived substitute when a
# gate carries a `quarantine:` block), the post-run assertions, and why
# `plan_diff` is plan-required with `pass` (never its Fast Mode exit-2 skip).
# P068 Step 3 adds the fourth stage — the plan-level review boundary:
#   aid-plan-fsm.sh plan-finalize <plan_id> --stage review
#                    [--execution-yaml <path>]
# — see the section header above `_pfsm_finalize_review`. It DISPATCHES NOTHING:
# it declares the required outputs (`review-requirements.json`), blocks with
# exit 7 until they exist, refuses a stale/wrong-subject output with exit 1, and
# invalidates the candidate with exit 6 when a tracked write proves a fix was
# accepted. On success: PLAN_REVIEW -> AWAITING_PM.
# P068 Step 4 adds the fifth and sixth stages — the plan-mode C4 decision and
# the plan-level PM summary:
#   aid-plan-fsm.sh plan-finalize <plan_id> --stage c4
#   aid-plan-fsm.sh plan-finalize <plan_id> --stage summary
# — see the section header above `_pfsm_finalize_c4`. Both run out of
# AWAITING_PM and make NO state transition: `c4` produces ONE release decision
# via `aid-release-policy.sh --plan` (the same aggregator, plan resolution) plus
# dual-run evidence, and `summary` renders the PM plan-final summary via
# `aid-pm-brief.sh`, keeping reviewed candidate / approved target / final merge
# SHA / tag status as four distinct fields. The merge and the release/tag stay
# with Step 5's PM-authorized `plan-merge-to-main`.
# — see the dedicated section header above cmd_plan_finalize for the order it
# enforces (sync → version preparation → freeze) and why an invalidation
# clears the whole candidate binding at once.
#
# `plan-merge-to-main`, `plan-close-check` and `inventory` remain later-step
# subcommands; this file does not implement them yet. That matters beyond
# bookkeeping: `_pfsm_plan_final_installed` requires BOTH `plan-finalize` AND
# `plan-merge-to-main` in the dispatcher before `--mode plan_branch` is
# allowed, so adding only the first one deliberately does NOT lift the
# plan-start refusal — a plan_branch plan still could not be CLOSED.
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
# **Last Updated:** 2026-07-25
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

  # DOGFOOD FINDING (2026-07-27, P067 live run). Collapsing to the git common
  # dir is right when the root is INFERRED — a linked worktree shares the plan's
  # runtime state with the main checkout, so inferring per-worktree roots would
  # scatter it. It is wrong when the caller NAMES a root: the two-checkout
  # dogfood topology exists precisely so the tool under test runs against a
  # different working tree than its own, and collapsing that back to the main
  # checkout silently pointed every lifecycle write at the wrong tree (it
  # refused on branch task/E-068-2_2/main while the caller had asked for a
  # checkout sitting on main). An explicitly named worktree root is honoured as
  # given; everything else keeps the previous behaviour.
  # An explicitly named worktree root is honoured — but ONLY when the plan
  # runtime state actually lives there. `.aid-o/work/plan-state/` is gitignored,
  # so a linked worktree does not get one checked out: for those, the shared
  # common-dir root is the correct answer and always was. Honouring the name
  # unconditionally broke exactly that (the P064 suite's linked-worktree case
  # went looking for a manifest in a tree that never had one). Both callers are
  # now served: the dogfood, which names a separate checkout carrying its own
  # .aid-o/, resolves there; an ordinary worktree still shares the main
  # checkout's state.
  if [[ -n "${1:-}" && -e "${probe_dir}/.git" && -d "${probe_dir}/.aid-o/work/plan-state" ]]; then
    printf '%s' "$probe_dir"
    return 0
  fi

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

  # IMP-265: epic-start is the legitimate producer that observed this branch's
  # origin at creation time, so it asserts lineage=proven EXPLICITLY — the
  # 8th positional is no longer defaulted (an omitted lineage now fails closed
  # to "unproven" in plan_manifest_add_epic).
  local arc=0
  plan_manifest_add_epic "$plan_id" "$epic_id" "$run_id" "$task_branch" \
    "$epic_base_commit" "$plan_branch_ref" "$evidence_dir" "proven" >/dev/null || arc=$?
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
  # CP2 F1 (2026-07-25): callers pass a DETACHED-HEAD sha here as well as a branch
  # name. `git checkout <sha>` restores a detached HEAD exactly, so nothing below
  # needs to distinguish the two. An empty value still means "nothing to restore".
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
  # F2 (2026-07-27, found by the P067 dogfood): completion must be bound to the
  # exact task-branch tip it verified. `merge_status: pending` alone says "this
  # EPIC completed at some point"; it does not say WHAT completed, so work
  # pushed onto the task branch after the check would ride into the plan branch
  # on the strength of a verification that never saw it. The tip is recorded
  # here and re-checked at merge time; a moved tip is `epic_completion_stale`.
  local _ec_tip="" esc_tip="null"
  if [[ -n "$_ec_task_branch" ]]; then
    _ec_tip="$(git -C "$project_root" rev-parse --verify --quiet "refs/heads/${_ec_task_branch}" 2>/dev/null || true)"
  fi
  if [[ -z "$_ec_tip" ]]; then
    echo "PRECONDITION FAIL: epic-complete: cannot resolve the task branch tip for ${epic_id} (branch '${_ec_task_branch:-<unset>}') — completion cannot be bound to a commit, so no merge authorization is issued." >&2
    exit 1
  fi
  esc_tip="$(jq -Rn --arg s "$_ec_tip" '$s')"
  local esc_evd="null"
  [[ -n "$evidence_dir" ]] && esc_evd="$(jq -Rn --arg s "$evidence_dir" '$s')"

  local assign=".merge_status = \"pending\" | .epic_completed_at = ${esc_now} | .epic_completion_sha = ${esc_tip} | .epic_completion_evidence_dir = ${esc_evd} | .epic_completion_run_id = $(jq -Rn --arg s "$run_id" '$s') | .epic_completion_profile = ${esc_profile} | .epic_final_profile_floor = ${esc_floor} | .unknown_production_path = ${unknown_production_path} | .plan_final_required_gates = ${excluded_plan_gates}"
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

  # ─────────────────────────────────────────────────────────────────────────
  # F2 (2026-07-27) — THE COMPLETION GATE, before any Git mutation.
  #
  # Found by the P067 live dogfood: `epic-complete` refused an EPIC ("cannot
  # confirm the EPIC reached DONE") and this command merged it into the plan
  # branch anyway, because `pending -> merged_to_plan` was a permitted
  # transition and nothing here asked whether completion had ever succeeded.
  # An unfinished EPIC therefore reached the candidate, and the only thing that
  # noticed was C4, four stages downstream. The check at the door was missing:
  # a status, a lineage record and an existing task branch are not completion
  # proof.
  #
  # Completion proof is all four of these, together:
  #   1. the EPIC is `running` — `pending` never completed anything;
  #   2. `merge_status` is `pending`, which only a successful epic-complete writes;
  #   3. that epic-complete's operation record reached `state_committed`;
  #   4. the task tip TODAY equals the tip epic-complete verified.
  # (4) is what makes the authorization about a commit rather than about a
  # branch name: work pushed after the check was never verified, and merging it
  # would launder it into the candidate.
  # ─────────────────────────────────────────────────────────────────────────
  if [[ "$cur_status" != "merged_to_plan" ]]; then
    if [[ "$cur_status" != "running" ]]; then
      echo "PRECONDITION FAIL: epic_completion_missing: ${epic_id} is '${cur_status}', not 'running' — only an EPIC that started and then completed may merge into plan/${plan_id}. Run epic-start, finish the EPIC, then epic-complete." >&2
      exit 1
    fi
    local _mg_ms _mg_csha _mg_run
    _mg_ms="$(jq -r '.merge_status // empty' <<<"$entry_json" 2>/dev/null)" || _mg_ms=""
    _mg_csha="$(jq -r '.epic_completion_sha // empty' <<<"$entry_json" 2>/dev/null)" || _mg_csha=""
    _mg_run="$(jq -r '.epic_completion_run_id // .run_id // empty' <<<"$entry_json" 2>/dev/null)" || _mg_run=""
    if [[ "$_mg_ms" != "pending" ]]; then
      echo "PRECONDITION FAIL: epic_completion_missing: ${epic_id} carries merge_status '${_mg_ms:-<unset>}', not 'pending' — only a SUCCESSFUL epic-complete writes that, so this EPIC has no merge authorization. Nothing was merged." >&2
      exit 1
    fi
    if [[ -z "$_mg_csha" ]]; then
      echo "PRECONDITION FAIL: epic_completion_missing: ${epic_id} records no epic_completion_sha — its completion is not bound to any commit, so there is nothing to verify the task branch against. Re-run epic-complete. Nothing was merged." >&2
      exit 1
    fi
    # The epic-complete operation must have REACHED state_committed. A record
    # stuck at intent/git_applied means completion was interrupted, and an
    # interrupted verification is not a verification.
    local _mg_ops _mg_phase=""
    _mg_ops="$(_pfsm_ops_path "$plan_id")"
    if [[ -f "$_mg_ops" ]]; then
      _mg_phase="$(jq -rs --arg e "$epic_id" \
        '[ .[] | select(type == "object" and .command == "epic-complete" and .subject == $e) ]
         | if length == 0 then "" else (.[-1].phase // "") end' "$_mg_ops" 2>/dev/null || true)"
    fi
    if [[ "$_mg_phase" != "state_committed" ]]; then
      echo "PRECONDITION FAIL: epic_completion_missing: the epic-complete operation for ${epic_id} is recorded at phase '${_mg_phase:-<none>}', not 'state_committed' — an interrupted completion is not a completion. Re-run epic-complete. Nothing was merged." >&2
      exit 1
    fi
    # The EPIC's own FSM must still say DONE. Two fail-open holes were closed
    # here on 2026-07-27, both found by review rather than by a test:
    #
    #   (a) the check only ran when the state file EXISTED, so deleting it after
    #       completion skipped the check entirely — the one thing an attacker or
    #       a careless cleanup would do to make an unfinished EPIC mergeable;
    #   (b) the path was DERIVED from the run id instead of read from the
    #       `epic_completion_evidence_dir` completion recorded, which was written
    #       and then never used. A derived path can point somewhere completion
    #       never looked.
    #
    # Both the run id and the evidence dir are now required, must still match the
    # manifest entry, and the FSM is read ONLY from the recorded directory. A
    # missing state file is `epic_completion_stale`, not a skipped check.
    local _mg_evd _mg_entry_run _mg_entry_evd
    _mg_evd="$(jq -r '.epic_completion_evidence_dir // empty' <<<"$entry_json" 2>/dev/null)" || _mg_evd=""
    _mg_entry_run="$(jq -r '.run_id // empty' <<<"$entry_json" 2>/dev/null)" || _mg_entry_run=""
    _mg_entry_evd="$(jq -r '.evidence_dir // empty' <<<"$entry_json" 2>/dev/null)" || _mg_entry_evd=""
    if [[ -z "$_mg_run" || -z "$_mg_evd" ]]; then
      echo "PRECONDITION FAIL: epic_completion_missing: ${epic_id} records no epic_completion_run_id/epic_completion_evidence_dir (run='${_mg_run:-<unset>}', dir='${_mg_evd:-<unset>}') — completion that names no evidence cannot be re-checked, so it authorizes nothing. Re-run epic-complete. Nothing was merged." >&2
      exit 1
    fi
    if [[ -n "$_mg_entry_run" && "$_mg_run" != "$_mg_entry_run" ]] \
       || [[ -n "$_mg_entry_evd" && "$_mg_evd" != "$_mg_entry_evd" ]]; then
      echo "PRECONDITION FAIL: epic_completion_stale: ${epic_id}'s completion names run '${_mg_run}' / dir '${_mg_evd}', but the manifest entry now records run '${_mg_entry_run}' / dir '${_mg_entry_evd}' — the EPIC was re-run since completion, so that completion describes a different run. Re-run epic-complete. Nothing was merged." >&2
      exit 1
    fi
    local _mg_state_file="${project_root}/${_mg_evd}/fsm-state.yaml"
    if [[ ! -f "$_mg_state_file" ]]; then
      echo "PRECONDITION FAIL: epic_completion_stale: ${epic_id}'s FSM state file is missing at ${_mg_evd}/fsm-state.yaml — the completion this merge relies on can no longer be verified. An absent file is never a passed check. Nothing was merged." >&2
      exit 1
    fi
    local _mg_st; _mg_st="$(grep -E '^state:' "$_mg_state_file" 2>/dev/null | awk '{print $2}' | head -1)"
    if [[ "$_mg_st" != "DONE" ]]; then
      echo "PRECONDITION FAIL: epic_completion_stale: ${epic_id}'s FSM now reports state '${_mg_st:-<empty>}', not DONE — the completion this merge relies on no longer holds. Nothing was merged." >&2
      exit 1
    fi
    # The tip TODAY must be the tip completion verified.
    local _mg_tip=""
    _mg_tip="$(git -C "$project_root" rev-parse --verify --quiet "refs/heads/task/${epic_id}/main" 2>/dev/null || true)"
    if [[ -z "$_mg_tip" ]]; then
      echo "PRECONDITION FAIL: epic_completion_stale: task/${epic_id}/main does not resolve, so the completed commit ${_mg_csha:0:8} cannot be confirmed as its tip. Nothing was merged." >&2
      exit 1
    fi
    if [[ "$_mg_tip" != "$_mg_csha" ]]; then
      echo "PRECONDITION FAIL: epic_completion_stale: task/${epic_id}/main is at ${_mg_tip:0:8} but epic-complete verified ${_mg_csha:0:8} — work landed after the completion check and has never been verified. Re-run epic-complete against the current tip. Nothing was merged." >&2
      exit 1
    fi
  fi

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
    echo "PRECONDITION FAIL: epic_lineage_unproven — ${epic_id}'s manifest entry has lineage='${lineage:-<empty>}' (must be proven); refusing to record a merge into ${plan_branch} on unestablished provenance. Sanctioned recovery: attest the origin explicitly — 'aid-plan-fsm.sh plan-state ${plan_id} --attest-source-ref ${plan_branch} --reason <text> --epic ${epic_id}'. You do not need '--repair' first: attestation's precondition IS an unproven entry. (Since IMP-265, --repair is a byte-identical no-op on a healthy manifest and preserves proven siblings' attestation — it only reconstructs genuinely damaged entries, always as unproven; it is neither required nor harmful here, but attestation is the direct fix.)" >&2
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
  _pfsm_crash_seam intent
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
  _pfsm_crash_seam git_applied
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
# ─── P068 Step 1: the plan-final boundary — `plan-finalize` ──────────────────
#
# `plan-finalize` opens the plan-final cycle in a FIXED order that the rest of
# the boundary depends on:
#
#     --stage sync   : every EPIC is terminal → merge target_branch into the
#                      plan branch → PLAN_SYNC
#     (the release script's prepare-plan subcommand runs HERE, still in PLAN_SYNC —
#      it makes the version commit on the plan branch)
#     --stage freeze : freeze ONE immutable candidate at the resulting plan
#                      head, allocate its run directory → PLAN_GATES
#
# The order is load-bearing. Version preparation happens BEFORE the freeze so
# the frozen candidate already contains the release metadata and nothing has
# to be committed once the reviews start. And because `prepare-plan` runs
# while the state is still PLAN_SYNC, it never needs a `candidate_sha` that
# does not yet exist.
#
# A MERGE, NOT A REBASE (roadmap resolved decision 4): `--stage sync` uses
# `git merge --no-ff`. A rebase would rewrite the plan branch's commits, so
# every recorded SHA in the manifest (`plan_base_commit`, every
# `epic_base_commit`, every `epic_merge_commit`) would name a commit that no
# longer exists — resume and audit both stop being deterministic.
# =============================================================================

# ---------------------------------------------------------------------------
# _pfsm_plan_final_run_dir_rel <plan_id> <n> — the repo-relative run directory
# for attempt n. Kept in one place because BOTH the allocator and the manifest
# write must agree with the manifest's own containment invariant
# (.aid-o/work/evidence/<plan_id>/...).
# ---------------------------------------------------------------------------
_pfsm_plan_final_run_dir_rel() {
  printf '.aid-o/work/evidence/%s/R-%s-final-%s' "$1" "$1" "$2"
}

# ---------------------------------------------------------------------------
# _pfsm_next_plan_final_attempt <root> <plan_id>
#
# The attempt allocator. Derived from what is ON DISK — the highest existing
# `R-<plan_id>-final-<N>` directory plus one — rather than from a counter in
# the manifest, and that is deliberate: an invalidation CLEARS the manifest's
# plan-final fields, so a counter stored there would be cleared with them and
# the next freeze would re-allocate `-1` on top of a directory that already
# exists. Deriving from disk makes "prior run directories are never deleted or
# overwritten" (roadmap resolved decision 8) structural rather than a promise.
# Echoes 1 when none exist.
# ---------------------------------------------------------------------------
_pfsm_next_plan_final_attempt() {
  local root="$1" plan_id="$2"
  local base="${root}/.aid-o/work/evidence/${plan_id}"
  local max=0 d n
  if [[ -d "$base" ]]; then
    for d in "$base"/R-"${plan_id}"-final-*; do
      [[ -d "$d" ]] || continue
      n="${d##*-final-}"
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      [[ "$n" -gt "$max" ]] && max="$n"
    done
  fi
  printf '%s' "$((max + 1))"
}

# ---------------------------------------------------------------------------
# plan_final_invalidate <plan_id> <reason> <target_state>
#
# ONE function for every candidate invalidation. It clears `candidate_sha`,
# `candidate_frozen_at`, `target_branch_head_at_candidate_freeze`,
# `plan_final_run_id` and `plan_final_evidence_dir` in a SINGLE atomic manifest
# write (lib/aid-plan-manifest.sh's plan_manifest_clear_candidate), records the
# reason, and transitions the plan to the CALLER-SUPPLIED target state.
#
# The target state is a parameter, not a constant, because the same field
# clearing serves two recovery paths that land in different states: `PLAN_FIX`
# for a review fix, `PLAN_SYNC` for a stale-authorization or conflict
# resynchronisation. Both are legal from `AWAITING_PM` in P064's transition
# table. An earlier draft hard-coded PLAN_FIX and simply could not express the
# resync path.
#
# It never deletes a run directory: each freeze allocates a fresh one, so the
# prior attempt's evidence stays byte-identical and auditable.
# ---------------------------------------------------------------------------
plan_final_invalidate() {
  local plan_id="$1" reason="$2" target_state="$3"

  # ── The transition must be legal BEFORE anything is cleared ──────────────
  # The manifest write and the plan-state file are two artifacts, and the
  # manifest is written first. If the caller-supplied target were illegal from
  # the current state, the manifest would record it while the state file kept
  # the old value — an invisible divergence between the two records of the
  # same fact. So legality is checked against the SAME table plan_state_transition
  # uses, up front, and an illegal target is a refusal that writes nothing.
  # (PLAN_FIX is legal from PLAN_GATES/PLAN_REVIEW/AWAITING_PM; PLAN_SYNC is
  # the resync target and is legal from AWAITING_PM/PLAN_FIX/CONFLICT — which
  # is exactly why the target is a parameter.)
  local cur="" crc=0
  cur="$(plan_state_get "$plan_id" "plan_state")" || crc=$?
  if [[ "$crc" -ne 0 || -z "$cur" || "$cur" == "not_found" ]]; then
    echo "PRECONDITION FAIL: cannot read the plan state for ${plan_id} — refusing to invalidate a candidate without knowing the state it would move from." >&2
    return 1
  fi
  if [[ "$cur" != "$target_state" ]]; then
    local t legal=0
    for t in "${_AID_PLAN_TRANSITIONS[@]}"; do
      [[ "$t" == "${cur}:${target_state}" ]] && { legal=1; break; }
    done
    if [[ "$legal" -ne 1 ]]; then
      echo "PRECONDITION FAIL: ${cur} -> ${target_state} is not a legal plan-state transition — refusing to invalidate the candidate for ${plan_id}; nothing was cleared. (PLAN_FIX is the review-fix target, PLAN_SYNC the resync target; they are reachable from different states.)" >&2
      return 1
    fi
  fi

  local rc=0
  plan_manifest_clear_candidate "$plan_id" "$reason" "$target_state" >/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: could not clear the plan-final fields for ${plan_id} (rc=${rc}) — the candidate binding is UNCHANGED; nothing was half-cleared." >&2
    return "$rc"
  fi
  # F1 (controller review, 2026-07-25): do NOT swallow this write. The manifest
  # is already cleared and moved to <target_state> by the time we get here, so a
  # silently-failed state-file write leaves exactly the manifest/state-file
  # divergence the legality pre-check above exists to prevent — and the caller
  # would see exit 0 and believe the invalidation completed. Same class as
  # IMP-258 (per-write failures must propagate, never `|| true`). Report loudly
  # and name the reconciliation, rather than pretending success.
  if ! _pfsm_plan_state_set "$plan_id" "$target_state"; then
    echo "PRECONDITION FAIL: the plan-final fields for ${plan_id} were cleared and the manifest moved to ${target_state}, but the plan STATE FILE could not be moved — the two records now disagree. Reconcile with 'aid-plan-fsm.sh plan-state ${plan_id}' before finalizing again; the candidate binding is already gone, so re-run '--stage sync' rather than assuming a candidate exists." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_finalize_sync <root> <plan_id>  — the `--stage sync` body.
# ---------------------------------------------------------------------------
_pfsm_finalize_sync() {
  local root="$1" plan_id="$2"
  local plan_branch="plan/${plan_id}"

  local target_branch=""
  target_branch="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch')" || target_branch=""
  if [[ -z "$target_branch" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage sync: no target_branch recorded for ${plan_id} — run plan-start first." >&2
    return 1
  fi

  # ── CONFLICT resolution invalidates the frozen candidate (P068 Step 5) ───
  # `CONFLICT` is not terminal. The operator resolves a plan-merge conflict by
  # re-synchronising the target branch into the plan branch — i.e. by running
  # THIS stage — and that necessarily produces a new plan branch head. So the
  # frozen candidate is discarded here rather than silently re-pointed: there is
  # deliberately NO path from CONFLICT back to a merge against the old
  # candidate, and a PM decision bound to it must not survive the resolution.
  local pre_state=""
  pre_state="$(plan_state_get "$plan_id" "plan_state")" || pre_state=""
  if [[ "$pre_state" == "CONFLICT" ]]; then
    local held=""
    held="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || held=""
    if [[ -n "$held" && "$held" != "null" && "$held" != "not_found" ]]; then
      local circ=0
      plan_final_invalidate "$plan_id" "conflict_resync" "PLAN_SYNC" || circ=$?
      [[ "$circ" -ne 0 ]] && return "$circ"
      echo "CANDIDATE INVALIDATED: ${plan_id} was in CONFLICT and the resolution re-synchronises ${plan_branch}, which necessarily moves its head — the frozen candidate ${held} and every plan-final field are cleared, and any PM decision bound to it is void. Re-run '--stage freeze' onwards after this sync." >&2
    fi
  fi

  # ── Every EPIC must be terminal ─────────────────────────────────────────
  # `pending` or `running` means work is still outstanding: syncing and then
  # freezing a candidate would seal a plan that does not contain it. The
  # offending EPIC is NAMED, because "some EPIC is not done" is not actionable.
  local unfinished=""
  unfinished="$(plan_manifest_get "$plan_id" \
    '[.plan_boundary_manifest.epic_runs[] | select(.status == "pending" or .status == "running" or .status == "blocked") | .epic_id + " (" + .status + ")"] | join(", ")')" || unfinished=""
  if [[ -n "$unfinished" && "$unfinished" != "not_found" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage sync: ${plan_id} still has non-terminal EPICs — ${unfinished}. Every EPIC must be merged_to_plan, abandoned or superseded before the plan branch is synced." >&2
    return 1
  fi

  # ── An abandoned/superseded EPIC must carry a recorded PM reason ─────────
  # Abandonment is a decision, and an undocumented decision is indistinguish-
  # able from an EPIC that was simply dropped (roadmap §12).
  local unreasoned=""
  unreasoned="$(plan_manifest_get "$plan_id" \
    '[.plan_boundary_manifest.epic_runs[] | select((.status == "abandoned" or .status == "superseded") and ((.terminal_reason // "") == "")) | .epic_id + " (" + .status + ")"] | join(", ")')" || unreasoned=""
  if [[ -n "$unreasoned" && "$unreasoned" != "not_found" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage sync: ${plan_id} has terminal EPICs with no recorded reason — ${unreasoned}. Abandonment requires a reason; record it with 'aid-plan-fsm.sh epic-complete ${plan_id} <epic_id> --abandon --reason <text>'." >&2
    return 1
  fi

  local plan_head=""
  plan_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${plan_branch}" 2>/dev/null)" || plan_head=""
  if [[ -z "$plan_head" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage sync: ${plan_branch} not found — run plan-start first." >&2
    return 1
  fi
  local target_head=""
  target_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null)" || target_head=""
  if [[ -z "$target_head" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage sync: target branch ${target_branch} not found." >&2
    return 1
  fi

  # ── Already contained: nothing to merge, the sync is a no-op ─────────────
  if _pfsm_is_ancestor "$root" "$target_head" "$plan_branch"; then
    _pfsm_plan_state_set "$plan_id" "PLAN_SYNC" || true
    echo "$plan_head"
    return 0
  fi

  local orig_branch=""
  orig_branch="$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null)" || orig_branch=""
  # CP2 F1 (2026-07-25): on a DETACHED HEAD `symbolic-ref` fails, which left
  # orig_branch empty — the checkout below still ran, but the guarded restore was
  # skipped, silently stranding the caller on the plan branch. Fall back to the
  # exact commit; `git checkout <sha>` restores a detached HEAD faithfully.
  [[ -n "$orig_branch" ]] || orig_branch="$(git -C "${root}" rev-parse HEAD 2>/dev/null || echo "")"
  if ! git -C "$root" checkout -q "$plan_branch" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-finalize --stage sync: cannot check out ${plan_branch} (checked out in another worktree?) — nothing merged." >&2
    return 1
  fi

  local merge_out="" mrc=0
  merge_out="$(git -C "$root" merge --no-ff --no-edit \
    -m "merge(plan-final): ${target_branch} into ${plan_branch}" "$target_branch" 2>&1)" || mrc=$?

  if [[ "$mrc" -ne 0 ]]; then
    # Same discrimination as epic-merge-to-plan: only a REAL conflict (a
    # MERGE_HEAD or unmerged index entries) drives the plan to CONFLICT and
    # exits 4. Everything else — a refusing hook, an untracked file in the
    # way — leaves nothing to resolve and must not send an automated
    # controller down the conflict-resolution path.
    local git_dir="" is_conflict=0
    git_dir="$(git -C "$root" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || git_dir=""
    if [[ -n "$git_dir" && -f "${git_dir}/MERGE_HEAD" ]]; then
      is_conflict=1
    elif [[ -n "$(git -C "$root" ls-files --unmerged 2>/dev/null)" ]]; then
      is_conflict=1
    fi
    if [[ "$is_conflict" -eq 1 ]]; then
      git -C "$root" merge --abort >/dev/null 2>&1 || true
    fi
    _pfsm_restore_head "$root" "$orig_branch" || true
    if [[ "$is_conflict" -eq 1 ]]; then
      _pfsm_plan_state_set "$plan_id" "CONFLICT" || true
      echo "MERGE CONFLICT: ${target_branch} does not merge cleanly into ${plan_branch} — plan state is CONFLICT, ${plan_branch} unchanged." >&2
      printf '%s\n' "$merge_out" >&2
      return 4
    fi
    echo "MERGE FAILED (not a conflict): git refused to merge ${target_branch} into ${plan_branch} — no MERGE_HEAD and no unmerged index entries, so there is nothing to resolve or abort. The plan state is left where it was." >&2
    printf '%s\n' "$merge_out" >&2
    return 1
  fi

  local new_head=""
  new_head="$(git -C "$root" rev-parse "$plan_branch" 2>/dev/null)" || new_head=""
  _pfsm_restore_head "$root" "$orig_branch" || true
  if [[ -z "$new_head" ]]; then
    echo "PRECONDITION FAIL: cannot resolve ${plan_branch} after the merge." >&2
    return 5
  fi

  local esc; esc="$(jq -Rn --arg s "$new_head" '$s')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_branch_head = ${esc}" >/dev/null 2>&1 || true
  _pfsm_plan_state_set "$plan_id" "PLAN_SYNC" || true
  echo "$new_head"
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_finalize_freeze <root> <plan_id> [frozen_at]  — the `--stage freeze` body.
# ---------------------------------------------------------------------------
_pfsm_finalize_freeze() {
  local root="$1" plan_id="$2" frozen_at="${3:-}"
  local plan_branch="plan/${plan_id}"

  local target_branch=""
  target_branch="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch')" || target_branch=""
  if [[ -z "$target_branch" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage freeze: no target_branch recorded for ${plan_id} — run plan-start first." >&2
    return 1
  fi

  local plan_head="" target_head=""
  plan_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${plan_branch}" 2>/dev/null)" || plan_head=""
  target_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null)" || target_head=""
  if [[ -z "$plan_head" || -z "$target_head" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage freeze: cannot resolve ${plan_branch} and/or ${target_branch}." >&2
    return 1
  fi

  local cur_candidate=""
  cur_candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || cur_candidate=""

  # ── A candidate already exists: it is either still exact, or it changed ──
  # The candidate is IMMUTABLE. If the plan branch has moved off it, the thing
  # that was reviewed no longer exists at the branch tip, so the binding is
  # discarded wholesale rather than silently re-pointed at the new head: every
  # plan-final field is cleared together and the plan goes to PLAN_FIX for the
  # fix cycle to re-sync and re-freeze.
  if [[ -n "$cur_candidate" && "$cur_candidate" != "not_found" ]]; then
    if [[ "$cur_candidate" == "$plan_head" ]]; then
      local run_dir=""
      run_dir="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir=""
      # CP2 M1 (2026-07-25): this idempotent branch is also the RECOVERY path for a
      # freeze whose manifest write landed but whose state-file write did not. It
      # must therefore reconcile the state file rather than return 0 on the
      # manifest's word alone — otherwise the divergence is permanent, because
      # every re-run lands right here. _pfsm_plan_state_set is a no-op when the
      # state file already reads PLAN_GATES.
      if ! _pfsm_plan_state_set "$plan_id" "PLAN_GATES"; then
        echo "PRECONDITION FAIL: ${plan_id} is frozen at ${cur_candidate} in the manifest, but the plan STATE FILE could not be reconciled to PLAN_GATES — the two records disagree and this re-run could not repair it. Inspect with 'aid-plan-fsm.sh plan-state ${plan_id}'." >&2
        return 1
      fi
      echo "$cur_candidate"
      [[ -n "$run_dir" && "$run_dir" != "not_found" ]] && echo "already frozen at ${cur_candidate} (${run_dir}) — no second candidate minted; state file reconciled to PLAN_GATES." >&2
      return 0
    fi
    # DOGFOOD FINDING (P075, 2026-07-27): the invalidation target depends on
    # where the plan currently IS. PLAN_FIX is reachable from the review-side
    # states, but NOT from PLAN_SYNC — and freeze is exactly the stage a plan
    # reaches from PLAN_SYNC. Targeting PLAN_FIX unconditionally wedged the plan:
    # the drift was detected, the invalidation was refused as an illegal
    # transition, and re-freezing became impossible with no way forward that did
    # not hand-edit state. A plan whose candidate drifted while it sits in
    # PLAN_SYNC simply stays there — that is already the re-sync state.
    local _fz_state _fz_target="PLAN_FIX"
    _fz_state="$(plan_state_get "$plan_id" "plan_state" 2>/dev/null || true)"
    [[ "$_fz_state" == "PLAN_SYNC" ]] && _fz_target="PLAN_SYNC"
    local irc=0
    plan_final_invalidate "$plan_id" "candidate_changed_after_freeze" "$_fz_target" || irc=$?
    [[ "$irc" -ne 0 ]] && return "$irc"
    echo "CANDIDATE INVALIDATED: ${plan_branch} moved from the frozen candidate ${cur_candidate} to ${plan_head} — all plan-final fields cleared and the plan is now ${_fz_target}. Re-run --stage sync then --stage freeze to mint a new candidate; the previous run directory is left byte-identical." >&2
    return 6
  fi

  # ── State precondition: freeze only out of PLAN_SYNC ─────────────────────
  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""
  if [[ "$cur_state" != "PLAN_SYNC" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage freeze: ${plan_id} is in state '${cur_state:-<none>}' — freeze runs only out of PLAN_SYNC (run '--stage sync' first, then the release script's prepare-plan subcommand)." >&2
    return 1
  fi

  # ── Target drift between sync and freeze — REFUSE, never freeze anyway ───
  # If the target branch has advanced since the sync merge (a hotfix,
  # typically), its head is no longer contained in the plan branch. Recording
  # the NEWER head and freezing anyway would bind a candidate that does NOT
  # contain the hotfix to a target head that DOES: Step 5's compare-and-swap
  # would still be exact, and would still merge a candidate missing the
  # hotfix. So the plan returns to PLAN_SYNC and the drift is merged in first.
  # PLAN_SYNC → PLAN_SYNC is a legal self-edge precisely for this loop.
  if ! _pfsm_is_ancestor "$root" "$target_head" "$plan_branch"; then
    _pfsm_plan_state_set "$plan_id" "PLAN_SYNC" || true
    echo "PRECONDITION FAIL: target_drift_during_freeze — ${target_branch} advanced to ${target_head}, which ${plan_branch} does not contain. Nothing was frozen; the plan stays in PLAN_SYNC. Re-run '--stage sync' to merge the drift in, then freeze." >&2
    return 1
  fi

  # ── Allocate the next attempt and create its immutable run directory ─────
  local attempt run_dir_rel run_dir_abs run_id
  attempt="$(_pfsm_next_plan_final_attempt "$root" "$plan_id")"
  run_dir_rel="$(_pfsm_plan_final_run_dir_rel "$plan_id" "$attempt")"
  run_id="R-${plan_id}-final-${attempt}"
  run_dir_abs="${root}/${run_dir_rel}"
  if [[ -e "$run_dir_abs" ]]; then
    echo "PRECONDITION FAIL: ${run_dir_rel} already exists — refusing to reuse or overwrite a prior plan-final run directory." >&2
    return 1
  fi
  mkdir -p "$run_dir_abs" || {
    echo "PRECONDITION FAIL: cannot create ${run_dir_rel}." >&2
    return 1
  }

  # P068 Step 5: `prepare-plan` runs BEFORE this stage, so it cannot write into
  # a run directory that does not exist yet — it records the resolved version
  # (or the literal `none`) in the plan's runtime state directory. Copy that
  # record into the attempt's evidence now, so "tag or no tag" is auditable
  # against THIS attempt. plan-merge-to-main reads this copy first and falls
  # back to the canonical record; a missing record means `none` (no tag).
  local prep_src="${root}/.aid-o/work/plan-state/${plan_id}/release-prep.json"
  if [[ -s "$prep_src" ]]; then
    cp -p "$prep_src" "${run_dir_abs}/release-prep.json" 2>/dev/null || true
  fi

  # ── The atomic two-field freeze write ───────────────────────────────────
  # candidate_sha + candidate_frozen_at land in the SAME manifest write (with
  # the target head, the run id/dir and plan_state), so the manifest is never
  # observable with one of the pair set and the other absent.
  local wrc=0
  plan_manifest_freeze_candidate "$plan_id" "$plan_head" "$target_head" \
    "$run_id" "$run_dir_rel" "$frozen_at" >/dev/null || wrc=$?
  if [[ "$wrc" -ne 0 ]]; then
    rmdir "$run_dir_abs" 2>/dev/null || true
    echo "PRECONDITION FAIL: could not record the candidate freeze for ${plan_id} (rc=${wrc}) — NO candidate is recorded; nothing was half-written." >&2
    return "$wrc"
  fi

  # CP2 M1 (2026-07-25): do NOT swallow this write. The manifest already records
  # PLAN_GATES + the candidate pair, so a silently-failed state-file write leaves
  # the same manifest/state-file divergence `plan_final_invalidate` refuses to
  # leave one function above — and here it would ALSO never self-heal on its own,
  # because a re-run short-circuits on the "already frozen at the same head"
  # branch. Fail closed and name the repair; the candidate itself is durable.
  if ! _pfsm_plan_state_set "$plan_id" "PLAN_GATES"; then
    echo "PRECONDITION FAIL: the candidate for ${plan_id} was recorded (manifest is at PLAN_GATES with the candidate pair), but the plan STATE FILE could not be moved to PLAN_GATES — the two records now disagree. Re-run '--stage freeze': it reconciles the state file from the recorded candidate. Do not proceed to the gate run until both read PLAN_GATES." >&2
    return 1
  fi
  echo "$plan_head"
  return 0
}

# =============================================================================
# P068 Step 2 — `plan-finalize --stage gates`: EXACTLY ONE plan-final gate run
# =============================================================================
#
# One resolved release-derived gate profile, run ONCE against the frozen
# candidate, producing a plan-scoped gates_report.json that PROVES no required
# gate was excluded and no broad suite ran twice.
#
# WHAT THIS STAGE IS NOT: it is not a change to the gate runner's semantics.
# `aid-run-gates.sh` has no quarantine awareness and this stage adds none — the
# quarantine handling here is a PROFILE SELECTION (run `release_quarantine`
# instead of `release`) plus post-run assertions over the report the runner
# wrote. The runner still just runs the gates in a profile's include[].
#
# THE VACUOUS-RUN TRAP (found by the C0 cross-provider review; four
# same-provider rounds missed it): `aid-run-gates.sh` substitutes {base_commit}
# and {plan_path} into gate commands and, before Step 2, sourced BOTH only from
# `--state-file` — an EPIC-scoped fsm-state.yaml a plan-final run does not
# have. With neither supplied, `plan_diff` receives `--plan null`, takes its
# documented Fast Mode graceful skip (exit 2), and execution.yaml's
# pass_criteria for that gate ACCEPTS exit 2 — so the single release gate run
# for an entire plan would report success while verifying nothing about the
# plan's acceptance criteria. Hence `--base-commit` / `--plan-path` (added to
# the runner by this same step) are passed here, and hence `plan_diff` is
# treated as PLAN-REQUIRED regardless of its `required: false` default, with
# `result` asserted to be `pass` — an exit-2 skip fails the stage.
#
# A REQUIRED GATE IS NEVER SATISFIED BY A SKIP, and a QUARANTINED GATE IS NEVER
# GREEN: a gate carrying `quarantine.enabled: true` is EXPECTED to be excluded
# (its own row stays profile_excluded/waived/unverifiable, never rewritten to
# `pass`) and must instead carry a marked targeted-substitute receipt, recorded
# in the report's top-level `quarantine_substitutes[]`. A waiver is a separate,
# additional PM risk-acceptance record — a waiver ALONE, with no substitute
# receipt, does not satisfy the gate.
# ---------------------------------------------------------------------------

# _pfsm_gates_yq / _pfsm_gates_jq — hard tool preconditions for this stage.
_pfsm_gates_require_tools() {
  local missing=""
  command -v yq >/dev/null 2>&1 || missing="yq"
  command -v jq >/dev/null 2>&1 || missing="${missing:+${missing}, }jq"
  command -v sha256sum >/dev/null 2>&1 || missing="${missing:+${missing}, }sha256sum"
  if [[ -n "$missing" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage gates requires ${missing} — refusing to run the plan-final gates without the tools that read and verify their own report." >&2
    return 1
  fi
  return 0
}

# _pfsm_profile_include <execution_yaml> <profile> — the profile's include[]
# gate ids, one per line. Empty output for an unknown profile.
_pfsm_profile_include() {
  PROFILE="$2" yq -r '.gate_profiles[strenv(PROFILE)].include // [] | .[]' "$1" 2>/dev/null || true
}

# _pfsm_quarantined_gates <execution_yaml> — gate ids carrying a DECLARED
# `quarantine.enabled: true` block. This is the ONLY definition of "quarantined"
# this stage accepts: a profile named "*_quarantine" proves nothing, and a gate
# without the block is an ordinary gate (notably `plan_diff`, which is NOT
# quarantined and has no substitute path).
_pfsm_quarantined_gates() {
  yq -r '.gates | to_entries | map(select(.value.quarantine.enabled == true)) | .[].key' "$1" 2>/dev/null || true
}

# _pfsm_required_gates <execution_yaml> — gate ids with `required: true`.
_pfsm_required_gates() {
  yq -r '.gates | to_entries | map(select(.value.required == true)) | .[].key' "$1" 2>/dev/null || true
}

# _pfsm_in_list <needle> <newline-separated haystack>
_pfsm_in_list() {
  local needle="$1" hay="$2" line
  while IFS= read -r line; do
    [[ "$line" == "$needle" ]] && return 0
  done <<< "$hay"
  return 1
}

# ---------------------------------------------------------------------------
# _pfsm_validate_substitute_receipt <receipt_file> <candidate_sha> <root>
#
# The IMP-269 targeted-run receipt contract, applied to a plan-final quarantine
# substitute. Fail-closed on every violation; prints the precise reason.
#
#   command / command_sha256 — command_sha256 MUST equal sha256(.command), or
#     the fingerprint is decorative and a receipt could name one command while
#     claiming another ran.
#   log / log_sha256 — .log must name a real, in-repo file next to the receipt
#     whose sha256 equals log_sha256; that is what proves the run ACTUALLY ran
#     rather than that someone typed 64 hex characters.
#   head binding — every present head field must equal <candidate_sha>. A
#     substitute bound to any other head is stale or forged evidence.
#   exit_code == 0 and failed == 0 — a substitute may only stand in for a broad
#     gate when its own targeted run genuinely passed.
# ---------------------------------------------------------------------------
_pfsm_validate_substitute_receipt() {
  local f="$1" head="$2" root="$3"
  [[ -f "$f" && -r "$f" ]] || { echo "substitute receipt unreadable: $f" >&2; return 1; }
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 \
    || { echo "substitute receipt is not a single JSON object: $f" >&2; return 1; }
  jq -e --arg head "$head" '
      (.command        | type == "string" and (length > 0))
      and (.command_sha256 | type == "string" and test("^(sha256:)?[0-9a-f]{64}$"))
      and (.log_sha256     | type == "string" and test("^(sha256:)?[0-9a-f]{64}$"))
      and (.exit_code | type == "number")
      and (.passed    | type == "number")
      and (.failed    | type == "number")
      and (([.head_sha, .head_sha_before, .head_sha_after] | map(select(. != null))) as $heads
           | ($heads | length > 0) and ($heads | all(. == $head)))
  ' "$f" >/dev/null 2>&1 \
    || { echo "substitute receipt malformed, or not bound to the frozen candidate (${head}): $f" >&2; return 1; }

  local claimed actual cmd
  cmd="$(jq -r '.command' "$f")"
  claimed="$(jq -r '.command_sha256' "$f" | sed 's/^sha256://')"
  actual="$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)"
  if [[ "$claimed" != "$actual" ]]; then
    echo "substitute receipt command_sha256 is not sha256(.command) — the fingerprint is not of the recorded command: $f" >&2
    return 1
  fi

  local logrel logabs logdir
  logrel="$(jq -r '.log // ""' "$f")"
  [[ -n "$logrel" ]] || { echo "substitute receipt has no .log — log_sha256 is unbacked, so the run is unproven: $f" >&2; return 1; }
  logdir="$(cd "$(dirname "$f")" && pwd)" || { echo "cannot resolve receipt directory: $f" >&2; return 1; }
  case "$logrel" in
    /*) logabs="$logrel" ;;
    *)  logabs="${logdir}/${logrel}" ;;
  esac
  logabs="$(realpath -m -- "$logabs" 2>/dev/null || echo "")"
  [[ -n "$logabs" ]] || { echo "cannot resolve receipt .log path ('${logrel}'): $f" >&2; return 1; }
  local root_abs; root_abs="$(realpath -m -- "$root" 2>/dev/null || echo "$root")"
  case "$logabs" in
    "$root_abs"/*) ;;
    *) echo "substitute receipt .log escapes the repository (path traversal / absolute path rejected): ${logrel}" >&2; return 1 ;;
  esac
  [[ -f "$logabs" && -r "$logabs" ]] \
    || { echo "substitute receipt .log not found or unreadable ('${logrel}') — cannot verify log_sha256: $f" >&2; return 1; }
  local lclaimed lactual
  lclaimed="$(jq -r '.log_sha256' "$f" | sed 's/^sha256://')"
  lactual="$(sha256sum "$logabs" | awk '{print $1}')"
  if [[ "$lclaimed" != "$lactual" ]]; then
    echo "substitute receipt log_sha256 is not sha256(.log) — the recorded hash is not of the named log ('${logrel}'): $f" >&2
    return 1
  fi

  # Genuine green: a red targeted run can never stand in for a broad gate.
  if ! jq -e '.exit_code == 0 and .failed == 0' "$f" >/dev/null 2>&1; then
    echo "substitute receipt is not a passing run (exit_code must be 0 and failed must be 0): $f" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_finalize_gates <root> <plan_id> <execution_yaml> [<gate_id>=<receipt>...]
# ---------------------------------------------------------------------------
_pfsm_finalize_gates() {
  local root="$1" plan_id="$2" execution_yaml="$3"; shift 3
  local -a subs=("$@")

  _pfsm_gates_require_tools || return 1
  [[ -f "$execution_yaml" ]] || {
    echo "PRECONDITION FAIL: plan-finalize --stage gates: execution config not found: ${execution_yaml}" >&2
    return 1
  }

  local plan_branch="plan/${plan_id}"
  local candidate base_commit run_id run_dir_rel required_profile
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  base_commit="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_base_commit')" || base_commit=""
  run_id="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || run_id=""
  run_dir_rel="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir_rel=""
  required_profile="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_required_profile')" || required_profile=""
  for v in candidate base_commit run_id run_dir_rel; do
    if [[ -z "${!v}" || "${!v}" == "null" || "${!v}" == "not_found" ]]; then
      echo "PRECONDITION FAIL: plan-finalize --stage gates: ${plan_id} has no frozen candidate (${v} is unset) — run '--stage sync' then '--stage freeze' first. The plan-final gates run against ONE immutable candidate, never against a moving branch head." >&2
      return 1
    fi
  done
  [[ "$required_profile" == "null" || "$required_profile" == "not_found" ]] && required_profile="standard"

  # ── State precondition, and the RESUME path ──────────────────────────────
  # PLAN_REVIEW means this stage already completed for this candidate; say so
  # and do nothing rather than mint a second broad run.
  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""
  if [[ "$cur_state" == "PLAN_REVIEW" ]]; then
    echo "already in PLAN_REVIEW for candidate ${candidate} — the plan-final gate run is complete; gates were NOT re-run." >&2
    echo "$candidate"
    return 0
  fi
  if [[ "$cur_state" != "PLAN_GATES" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage gates: ${plan_id} is in state '${cur_state:-<none>}' — the gate stage runs only out of PLAN_GATES (freeze puts it there)." >&2
    return 1
  fi

  # ── The candidate must still be the plan branch head ─────────────────────
  local plan_head=""
  plan_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${plan_branch}" 2>/dev/null)" || plan_head=""
  if [[ "$plan_head" != "$candidate" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage gates: ${plan_branch} is at ${plan_head:-<unresolvable>} but the frozen candidate is ${candidate} — refusing to gate a head that is not the candidate. Re-run '--stage freeze' (it invalidates the stale binding) before gating." >&2
    return 1
  fi

  # The gate commands are relative to the repository root and the runner stamps
  # revision.head_sha from `git rev-parse HEAD` — so the working tree must BE
  # the candidate while they run. Check out the plan branch when it is not
  # already checked out, and put HEAD back afterwards either way.
  local orig_branch="" head_now=""
  head_now="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || head_now=""
  if [[ "$head_now" != "$candidate" ]]; then
    orig_branch="$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null)" || orig_branch=""
  # CP2 F1 (2026-07-25): on a DETACHED HEAD `symbolic-ref` fails, which left
  # orig_branch empty — the checkout below still ran, but the guarded restore was
  # skipped, silently stranding the caller on the plan branch. Fall back to the
  # exact commit; `git checkout <sha>` restores a detached HEAD faithfully.
    [[ -n "$orig_branch" ]] || orig_branch="$(git -C "${root}" rev-parse HEAD 2>/dev/null || echo "")"
    if ! git -C "$root" checkout -q "$plan_branch" 2>/dev/null; then
      echo "PRECONDITION FAIL: plan-finalize --stage gates: cannot check out ${plan_branch} (checked out in another worktree?) — no gates were run." >&2
      return 1
    fi
  fi

  local rc=0
  _pfsm_finalize_gates_body "$root" "$plan_id" "$execution_yaml" "$candidate" \
    "$base_commit" "$run_id" "$run_dir_rel" "$required_profile" "${subs[@]+"${subs[@]}"}" || rc=$?

  if [[ -n "$orig_branch" ]]; then
    _pfsm_restore_head "$root" "$orig_branch" || rc="${rc:-1}"
  fi
  return "$rc"
}

# _pfsm_finalize_gates_body — everything that runs WITH the candidate checked
# out. Split out so the HEAD restore above happens on every exit path.
_pfsm_finalize_gates_body() {
  local root="$1" plan_id="$2" execution_yaml="$3" candidate="$4" \
        base_commit="$5" run_id="$6" run_dir_rel="$7" required_profile="$8"
  shift 8
  local -a subs=("$@")

  # ── Profile resolution: max(plan_final_required_profile, release) ────────
  # gate_profile_max comes from lib/aid-gate-profile.sh (P064 Step 8); this
  # stage CONSUMES the table, it does not define one.
  local resolved=""
  resolved="$(gate_profile_max "$required_profile" release)" || {
    echo "PRECONDITION FAIL: plan-finalize --stage gates: cannot resolve the plan-final profile from '${required_profile}'." >&2
    return 1
  }

  local release_include quarantined
  release_include="$(_pfsm_profile_include "$execution_yaml" "$resolved")"
  if [[ -z "$release_include" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage gates: profile '${resolved}' has an empty or missing include[] in ${execution_yaml}." >&2
    return 1
  fi
  quarantined="$(_pfsm_quarantined_gates "$execution_yaml")"

  # Only a quarantined gate that is actually IN the resolved profile matters.
  local -a quarantined_in_profile=()
  local g
  while IFS= read -r g; do
    [[ -z "$g" ]] && continue
    if _pfsm_in_list "$g" "$release_include"; then quarantined_in_profile+=("$g"); fi
  done <<< "$quarantined"

  # ── Substitute profile selection (NOT a runner transformation) ───────────
  local effective_profile="$resolved"
  if (( ${#quarantined_in_profile[@]} > 0 )); then
    effective_profile="${resolved}_quarantine"
    local sub_include
    sub_include="$(_pfsm_profile_include "$execution_yaml" "$effective_profile")"
    if [[ -z "$sub_include" ]]; then
      echo "PRECONDITION FAIL: gate(s) ${quarantined_in_profile[*]} in profile '${resolved}' carry a declared quarantine block, but no pre-declared substitute profile '${effective_profile}' exists in ${execution_yaml}. The substitute must be DECLARED, never improvised at run time." >&2
      return 1
    fi
    # SET EQUALITY, not "is a subset": the substitute must be the release
    # profile minus exactly the quarantined gates. This is what stops
    # `bats_all_quarantine` (which also omits shell_pipeline_smoke) from being
    # used here and silently dropping a non-quarantined release gate.
    local expected_json actual_json
    expected_json="$(printf '%s\n' "$release_include" | jq -R . | jq -s --argjson q "$(printf '%s\n' "${quarantined_in_profile[@]}" | jq -R . | jq -s .)" 'map(select(. as $x | ($q | index($x)) | not)) | sort')"
    actual_json="$(printf '%s\n' "$sub_include" | jq -R . | jq -s 'sort')"
    if [[ "$expected_json" != "$actual_json" ]]; then
      echo "PRECONDITION FAIL: substitute profile '${effective_profile}' is not '${resolved}' minus the quarantined gate(s) ${quarantined_in_profile[*]}. Expected ${expected_json}, found ${actual_json} — a substitute that drops a NON-quarantined release gate would silently shrink the plan-final evidence." >&2
      return 1
    fi
  fi

  # ── The plan-required gate floor ────────────────────────────────────────
  # required:true in execution.yaml, UNION the manifest's accumulated
  # plan_final_required_gates[] (written by epic-complete, P064 Step 8), UNION
  # `plan_diff` — which this stage treats as plan-required for the plan-final
  # run regardless of its `required: false` default, because the whole point of
  # the run is to evaluate the plan's acceptance criteria against the candidate.
  local plan_required
  plan_required="$(_pfsm_required_gates "$execution_yaml")"
  local manifest_gates=""
  manifest_gates="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_required_gates[]?' 2>/dev/null)" || manifest_gates=""
  [[ "$manifest_gates" == "not_found" ]] && manifest_gates=""
  plan_required="$(printf '%s\n%s\nplan_diff\n' "$plan_required" "$manifest_gates" | grep -v '^$' | sort -u)"

  # ── The plan file the gates evaluate against ────────────────────────────
  local plan_path="" cand
  for cand in "${root}/.aid-o/plans/${plan_id}"*.md; do
    [[ -f "$cand" ]] || continue
    plan_path="$cand"; break
  done
  if [[ -z "$plan_path" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage gates: no plan file matching .aid-o/plans/${plan_id}*.md — without it plan_diff would run against '--plan null', take its Fast Mode exit-2 skip and report a green gate that verified nothing. Refusing the vacuous run." >&2
    return 1
  fi

  local run_dir_abs="${root}/${run_dir_rel}"
  local report_file="${run_dir_abs}/gates_report.json"
  local timeline_file="${run_dir_abs}/timeline.jsonl"
  mkdir -p "$run_dir_abs" || {
    echo "PRECONDITION FAIL: cannot create ${run_dir_rel}." >&2
    return 1
  }

  # ── Resume: the report is already written, only the transition is missing ─
  # Re-read the existing report and complete the transition; NEVER re-run the
  # gates (that would be the second broad run this stage exists to forbid).
  local ran_now=0
  if [[ -f "$report_file" ]]; then
    echo "gates_report.json already exists for ${run_id} — re-reading it and completing only the transition; gates were NOT re-run." >&2
  else
    ran_now=1
    local grc=0
    ( cd "$root" && "${SCRIPT_DIR}/aid-run-gates.sh" run-all "$execution_yaml" \
        "$plan_id" "$run_id" "$timeline_file" \
        --report-file "$report_file" \
        --profile "$effective_profile" \
        --base-commit "$base_commit" \
        --plan-path "$plan_path" ) >/dev/null || grc=$?
    if [[ ! -f "$report_file" ]]; then
      echo "PRECONDITION FAIL: the plan-final gate run produced no report at ${run_dir_rel}/gates_report.json (runner rc=${grc}) — the plan stays in PLAN_GATES." >&2
      return 1
    fi
    if [[ "$grc" -ne 0 ]]; then
      echo "GATES FAILED: the plan-final gate run for ${plan_id} did not pass (runner rc=${grc}); see ${run_dir_rel}/gates_report.json. The plan stays in PLAN_GATES — a failing candidate is shown to the PM, never silently retried." >&2
      return 1
    fi
  fi

  # ── quarantine_substitutes[]: the ONLY accepted evidence for a quarantined
  #    gate. Built from PM-supplied receipts, validated, then written into the
  #    report as a top-level array. ────────────────────────────────────────
  local subs_json="[]"
  if (( ${#quarantined_in_profile[@]} > 0 )); then
    local qg entry receipt_path receipt_abs found
    for qg in "${quarantined_in_profile[@]}"; do
      found=""
      local s
      for s in ${subs[@]+"${subs[@]}"}; do
        [[ "${s%%=*}" == "$qg" ]] && { found="${s#*=}"; break; }
      done
      if [[ -z "$found" ]]; then
        echo "PRECONDITION FAIL: quarantined gate '${qg}' was excluded from the plan-final run but no targeted-substitute receipt was supplied (--substitute-receipt ${qg}=<path>). A quarantined gate is never green and never simply absent: it must carry marked targeted-substitute evidence. A waiver alone does NOT satisfy it." >&2
        return 1
      fi
      receipt_abs="$(realpath -m -- "$found" 2>/dev/null || echo "$found")"
      if ! _pfsm_validate_substitute_receipt "$receipt_abs" "$candidate" "$root"; then
        echo "PRECONDITION FAIL: the targeted-substitute receipt for '${qg}' is not acceptable (reason above) — the plan stays in PLAN_GATES." >&2
        return 1
      fi
      # Same-gate only: one receipt can never satisfy a different gate. When the
      # receipt names a gate_id, it must be THIS gate.
      local rgate
      rgate="$(jq -r '.gate_id // ""' "$receipt_abs")"
      if [[ -n "$rgate" && "$rgate" != "$qg" ]]; then
        echo "PRECONDITION FAIL: the receipt supplied for '${qg}' declares gate_id '${rgate}' — one receipt can never satisfy a different gate." >&2
        return 1
      fi
      receipt_path="$(realpath -m --relative-to="$run_dir_abs" -- "$receipt_abs" 2>/dev/null || echo "$receipt_abs")"
      local receipt_sha cmd_sha
      receipt_sha="$(sha256sum "$receipt_abs" | awk '{print $1}')"
      cmd_sha="$(jq -r '.command_sha256' "$receipt_abs" | sed 's/^sha256://')"
      entry="$(jq -nc \
        --arg gate "$qg" \
        --arg rp "$receipt_path" \
        --arg rs "sha256:${receipt_sha}" \
        --arg cs "sha256:${cmd_sha}" \
        --arg base "$base_commit" \
        --arg head "$candidate" \
        --arg scope "targeted bats suites covering the candidate range, in place of the quarantined ${qg} aggregate" \
        --argjson ec "$(jq '.exit_code' "$receipt_abs")" \
        --argjson failed "$(jq '.failed' "$receipt_abs")" \
        '{gate_id:$gate, targeted_substitute:"accepted", receipt_path:$rp,
          receipt_sha256:$rs, command_sha256:$cs, base_sha:$base, head_sha:$head,
          substitute_scope:$scope, exit_code:$ec, failed:$failed}')"
      subs_json="$(jq -c --argjson e "$entry" '. + [$e]' <<< "$subs_json")"
    done
    local tmp_report="${report_file}.subs.tmp"
    jq --argjson s "$subs_json" '. + {quarantine_substitutes: $s}' "$report_file" > "$tmp_report" \
      && mv "$tmp_report" "$report_file" || {
        rm -f "$tmp_report"
        echo "PRECONDITION FAIL: could not record quarantine_substitutes[] into ${run_dir_rel}/gates_report.json." >&2
        return 1
      }
  fi

  # ── POST-RUN ASSERTIONS, read back from the report itself ───────────────
  # Every one of these exits 1 and leaves the plan in PLAN_GATES.
  local fails=0
  _gassert() { echo "PLAN-FINAL GATE ASSERTION FAILED: $1" >&2; fails=$((fails+1)); }

  jq -e 'type == "object"' "$report_file" >/dev/null 2>&1 || {
    echo "PLAN-FINAL GATE ASSERTION FAILED: ${run_dir_rel}/gates_report.json is not a JSON object." >&2
    return 1
  }

  local r_profile r_head r_overall
  r_profile="$(jq -r '.profile // ""' "$report_file")"
  r_head="$(jq -r '.revision.head_sha // ""' "$report_file")"
  r_overall="$(jq -r '.overall // ""' "$report_file")"
  [[ "$r_profile" == "$effective_profile" ]] \
    || _gassert "report profile is '${r_profile}', expected the resolved release-derived profile '${effective_profile}'."
  [[ "$r_head" == "$candidate" ]] \
    || _gassert "report revision.head_sha is '${r_head}', expected the frozen candidate '${candidate}'."
  [[ "$r_overall" == "pass" ]] \
    || _gassert "report overall is '${r_overall}', not 'pass'."

  # _command_log non-empty, every entry with a non-null duration_ms.
  jq -e '(._command_log | type == "array") and (._command_log | length > 0)' "$report_file" >/dev/null 2>&1 \
    || _gassert "_command_log is empty — the run recorded no executed gate."
  jq -e '(._command_log // []) | all(.duration_ms != null)' "$report_file" >/dev/null 2>&1 \
    || _gassert "a _command_log entry has a null duration_ms."

  # No plan-required / required:true gate may be excluded — EXCEPT a gate whose
  # quarantine block is enabled, which is expected to be excluded and must
  # instead carry its substitute evidence (checked below).
  local ex
  while IFS= read -r ex; do
    [[ -z "$ex" ]] && continue
    if _pfsm_in_list "$ex" "$plan_required"; then
      if ! _pfsm_in_list "$ex" "$quarantined"; then
        _gassert "excluded_gates contains '${ex}', which is required:true or plan-declared and carries no quarantine block."
      fi
    fi
  done < <(jq -r '.excluded_gates // [] | .[]' "$report_file")

  # Every NON-quarantined gate of the include list must have a real result.
  local inc
  while IFS= read -r inc; do
    [[ -z "$inc" ]] && continue
    if _pfsm_in_list "$inc" "$quarantined"; then continue; fi
    local res
    res="$(jq -r --arg g "$inc" '.gates[$g].result // "<absent>"' "$report_file")"
    if [[ "$res" == "<absent>" || "$res" == "profile_excluded" ]]; then
      _gassert "release gate '${inc}' has result '${res}' — a non-quarantined gate of the resolved profile must appear with a real result (notably shell_pipeline_smoke, which the EPIC-scoped bats_all_quarantine profile omits)."
    elif [[ "$res" == "skip" ]] && _pfsm_in_list "$inc" "$plan_required"; then
      _gassert "required gate '${inc}' reported result 'skip' — a required gate is never satisfied by a skip."
    fi
  done <<< "$release_include"

  # plan_diff specifically: a REAL evaluation, not the Fast-Mode exit-2 skip.
  local pd
  pd="$(jq -r '.gates.plan_diff.result // "<absent>"' "$report_file")"
  [[ "$pd" == "pass" ]] \
    || _gassert "plan_diff result is '${pd}', expected 'pass' — an exit-2 Fast Mode skip against '--plan null' does not evaluate the plan's acceptance criteria. plan_diff is plan-required for the plan-final run and has no substitute path (it carries no quarantine block)."

  # Quarantined gates: never `pass`, and each must carry a matching substitute.
  local qg2
  for qg2 in ${quarantined_in_profile[@]+"${quarantined_in_profile[@]}"}; do
    local qres
    qres="$(jq -r --arg g "$qg2" '.gates[$g].result // "profile_excluded"' "$report_file")"
    case "$qres" in
      pass) _gassert "quarantined gate '${qg2}' is reported 'pass' — a quarantined gate is never green." ;;
      waived|profile_excluded|unverifiable|fail) ;;
      *) _gassert "quarantined gate '${qg2}' has unexpected result '${qres}'." ;;
    esac
    jq -e --arg g "$qg2" --arg h "$candidate" --arg b "$base_commit" '
      (.quarantine_substitutes // []) | any(
        .gate_id == $g and .targeted_substitute == "accepted"
        and (.receipt_path | type == "string" and length > 0)
        and (.receipt_sha256 | test("^sha256:[0-9a-f]{64}$"))
        and (.command_sha256 | test("^sha256:[0-9a-f]{64}$"))
        and .head_sha == $h and .base_sha == $b
        and (.substitute_scope | type == "string" and length > 0)
        and .exit_code == 0 and .failed == 0)
    ' "$report_file" >/dev/null 2>&1 \
      || _gassert "quarantined gate '${qg2}' has no valid quarantine_substitutes[] entry bound to the candidate (${candidate}) and base (${base_commit})."
  done

  # Exactly ONE gate_runner_start for this plan-final run — the structural
  # no-duplicate-broad-run proof. `release` is a superset of `full`, so one
  # invocation covers everything and a second would mean a `full` run smuggled
  # in under another label.
  if [[ -f "$timeline_file" ]]; then
    local starts
    starts="$(grep -c '"event":"gate_runner_start"' "$timeline_file" 2>/dev/null || true)"
    [[ -z "$starts" ]] && starts=0
    if [[ "$starts" -ne 1 ]]; then
      _gassert "timeline has ${starts} gate_runner_start events for ${run_id}, expected exactly 1 (no second broad run under a 'full' label)."
    fi
  elif [[ "$ran_now" -eq 1 ]]; then
    _gassert "no timeline at ${run_dir_rel}/timeline.jsonl — the single-run assertion cannot be made."
  fi

  if [[ "$fails" -gt 0 ]]; then
    echo "PRECONDITION FAIL: ${fails} plan-final gate assertion(s) failed for ${plan_id}; the plan stays in PLAN_GATES and no transition was made. Fix the candidate or the evidence and re-run." >&2
    return 1
  fi

  # ── The transition (a P064-legal edge: PLAN_GATES → PLAN_REVIEW) ─────────
  local op_id crc=0
  op_id="$(plan_op_key "plan-finalize-gates" "$plan_id" "-" "0" "$plan_id")"
  plan_op_begin "$plan_id" "$op_id" "plan-finalize-gates" "$plan_id" "$candidate" >/dev/null 2>&1 || true
  if ! _pfsm_plan_state_set "$plan_id" "PLAN_REVIEW"; then
    echo "PRECONDITION FAIL: the plan-final gate report for ${plan_id} passed every assertion, but the plan STATE FILE could not be moved PLAN_GATES -> PLAN_REVIEW. The report is durable at ${run_dir_rel}/gates_report.json; re-run '--stage gates' — it re-reads the passing report and completes only the transition (gates are NOT re-run)." >&2
    return 1
  fi
  plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_state = "PLAN_REVIEW"' >/dev/null 2>&1 || true
  plan_op_commit "$plan_id" "$op_id" >/dev/null 2>&1 || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "WARN: could not record the plan-finalize-gates state_committed op for ${plan_id} (rc=${crc}); the state transition itself landed." >&2
  fi

  echo "$candidate"
  echo "plan-final gates PASSED for ${plan_id} at ${candidate} (profile ${effective_profile}) — ${run_dir_rel}/gates_report.json; ${plan_id} is now PLAN_REVIEW." >&2
  return 0
}

# =============================================================================
# P068 Step 3 — `plan-finalize --stage review`: the plan-level review boundary
# =============================================================================
#
# THE SHELL FSM DOES NOT DISPATCH LLM AGENTS. It declares which outputs must
# exist, validates them against the frozen candidate, and blocks until they do.
# That division already exists for C3 (`aid-fsm.sh` validates a dispatch record
# the controller produced) and is preserved here verbatim. What changes is the
# SUBJECT: the review range is `plan_base_commit..candidate_sha` — the whole
# plan — not one EPIC's diff.
#
# The stage writes `review-requirements.json` into the plan-final run directory
# (the machine-readable contract of what the controller must produce), then:
#
#   exit 7  `awaiting_review_outputs` — one or more required outputs are ABSENT.
#           This is NOT an error: it is the state the controller resolves by
#           dispatching the agents and re-running the stage.
#   exit 1  a required output is PRESENT but STALE or WRONG-SUBJECT (wrong head,
#           wrong plan, wrong audit hash, wrong ordering) or fails
#           `aid-protocol-validate.sh`. Never accepted with a warning — a stale
#           review is exactly the failure this boundary exists to prevent.
#   exit 6  the CANDIDATE CHANGED (a tracked write by a utility or a specialist
#           fix). `plan_final_invalidate` fires, the plan returns to PLAN_FIX,
#           the gate report and every review output are invalidated with it.
#   exit 0  every output present, fresh and bound → PLAN_REVIEW -> AWAITING_PM.
#
# WHY EVERY OUTPUT LANDS OUTSIDE THE CANDIDATE TREE: the run directory lives
# under `.aid-o/work/evidence/<plan_id>/` — gitignored runtime area — so a full
# review pass writes nothing tracked and `candidate_sha` is provably unchanged
# when it finishes. A specialist that writes a TRACKED file has, by definition,
# proposed a fix; that is the invalidation path above, not a review result.
# ---------------------------------------------------------------------------

# The four plan-boundary specialist agents whose dispatch count is asserted.
_AID_PLAN_FINAL_AGENTS=(auditor curator simplifier reporter)

# The default registry of plan-boundary UTILITIES. Today exactly one: the
# Scanner memory scan described in skills/pipeline.md ("Plan Boundary: Scanner
# Memory Scan"). Overridable per project via execution.yaml's
# `plan_final_utilities:` list, so registering a new utility is a config edit
# rather than a code edit — but it is never IMPLICIT: an unregistered utility
# that runs is not counted, and a registered one that does not run blocks.
_AID_PLAN_FINAL_DEFAULT_UTILITIES=(scanner_memory_scan)

# _pfsm_plan_final_utilities <execution_yaml> — the registered utility ids.
_pfsm_plan_final_utilities() {
  local ey="$1" out=""
  if [[ -f "$ey" ]] && command -v yq >/dev/null 2>&1; then
    out="$(yq -r '.plan_final_utilities // [] | .[]' "$ey" 2>/dev/null || true)"
  fi
  if [[ -n "$out" ]]; then printf '%s\n' "$out"; else printf '%s\n' "${_AID_PLAN_FINAL_DEFAULT_UTILITIES[@]}"; fi
}

# _pfsm_review_required_outputs — "<filename>|<artifact_type>|<binding>" rows.
# `-` in the artifact_type column means "not a protocol-v2 JSON artifact", so
# aid-protocol-validate.sh is not run over it (markdown, and the dispatch
# record, which is a controller bookkeeping file rather than a review result).
_pfsm_review_required_outputs() {
  cat <<'ROWS'
semantic-review-final.json|semantic_review|revision.head_sha == candidate_sha and the recorded range covers plan_base_commit..candidate_sha
audit-report.json|audit_report|audit_report.reviewed_head == candidate_sha and input_manifest_hash present
curator-report.json|curator|curator.audit_report_ref sha256 matches audit-report.json
simplifier-report.md|-|a `Head:` provenance line equal to candidate_sha
delivery-report.json|delivery_report|identity.plan_id set and revision.head_sha == candidate_sha; written LAST (after every other output)
review-profile.json|review_profile|produced over plan_base_commit..candidate_sha; carries review_profile.required_lenses (arms the C3 gate)
delivery-gate.json|delivery_gate|identity.epic_id == null, identity.plan_id set, sources[] lists every contributing EPIC
acceptance-evidence.json|acceptance_evidence|identity.epic_id == null, identity.plan_id set, sources[] lists every contributing EPIC
dispatch-record.json|-|one dispatch per plan-boundary agent and per registered utility, bound to candidate_sha AND this attempt's run_id
ROWS
}

# ---------------------------------------------------------------------------
# _pfsm_review_candidate_drift <root> <plan_id> <candidate>
#
# The detection half of the invalidation trigger, run at the START of every
# stage invocation: `git rev-parse plan/<plan_id>` compared against
# candidate_sha, PLUS a `git status --porcelain` check for uncommitted TRACKED
# changes. Returns 0 when the candidate is intact, 1 with the reason on stdout
# when it is not.
#
# Untracked files are deliberately NOT drift: the run directory itself is
# untracked, and every review output lands in it. Only a TRACKED write is a
# candidate-changing fix.
# ---------------------------------------------------------------------------
_pfsm_review_candidate_drift() {
  local root="$1" plan_id="$2" candidate="$3"
  local plan_head=""
  plan_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/plan/${plan_id}" 2>/dev/null)" || plan_head=""
  if [[ "$plan_head" != "$candidate" ]]; then
    printf 'plan/%s moved from the frozen candidate %s to %s' "$plan_id" "$candidate" "${plan_head:-<unresolvable>}"
    return 1
  fi
  local dirty=""
  dirty="$(git -C "$root" status --porcelain --untracked-files=no \
    | grep -vE '^.. \.aid-o/config/queue\.yaml$|^.. \.aid-o/work/audit-log\.jsonl$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml\.lock$|^.. \.aid-o/work/plan-state/' || true)"
  if [[ -n "$dirty" ]]; then
    printf 'uncommitted TRACKED changes against the candidate %s: %s' "$candidate" "$(printf '%s' "$dirty" | tr '\n' ';')"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_finalize_review <root> <plan_id> <execution_yaml>
# ---------------------------------------------------------------------------
_pfsm_finalize_review() {
  local root="$1" plan_id="$2" execution_yaml="$3"

  command -v jq >/dev/null 2>&1 || {
    echo "PRECONDITION FAIL: plan-finalize --stage review requires jq — refusing to validate review outputs without the tool that reads them." >&2
    return 1
  }
  command -v sha256sum >/dev/null 2>&1 || {
    echo "PRECONDITION FAIL: plan-finalize --stage review requires sha256sum — the Curator's audit_report_ref binding cannot be verified without it." >&2
    return 1
  }

  local candidate base_commit run_id run_dir_rel v
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  base_commit="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_base_commit')" || base_commit=""
  run_id="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || run_id=""
  run_dir_rel="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir_rel=""
  for v in candidate base_commit run_id run_dir_rel; do
    if [[ -z "${!v}" || "${!v}" == "null" || "${!v}" == "not_found" ]]; then
      echo "PRECONDITION FAIL: plan-finalize --stage review: ${plan_id} has no frozen candidate (${v} is unset) — the plan-level reviews run against ONE immutable candidate. Run '--stage sync', '--stage freeze' and '--stage gates' first." >&2
      return 1
    fi
  done

  # ── The invalidation trigger, BEFORE anything else ──────────────────────
  # Any tracked write produced by a utility or by an accepted specialist fix is
  # a candidate-changing fix: the candidate binding, the gate report and every
  # review output are invalidated together and the plan returns to PLAN_FIX.
  # This runs first so a fix accepted between two review passes can never be
  # papered over by re-validating outputs that describe the OLD candidate.
  local drift=""
  if ! drift="$(_pfsm_review_candidate_drift "$root" "$plan_id" "$candidate")"; then
    local irc=0
    plan_final_invalidate "$plan_id" "candidate_changed_during_review" "PLAN_FIX" || irc=$?
    [[ "$irc" -ne 0 ]] && return "$irc"
    echo "CANDIDATE INVALIDATED: ${drift}. Every plan-final field is cleared, the gate report and all review outputs for ${run_id} are no longer authoritative, and ${plan_id} is now PLAN_FIX. Commit the fix, then re-run '--stage sync', '--stage freeze', '--stage gates' and '--stage review' against the NEW candidate — the previous run directory is left byte-identical." >&2
    return 6
  fi

  # ── State precondition, and the idempotent resume ────────────────────────
  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""
  if [[ "$cur_state" == "AWAITING_PM" ]]; then
    echo "already in AWAITING_PM for candidate ${candidate} — the plan-level review boundary is complete; no agent was re-dispatched and no output was re-validated into a second pass." >&2
    echo "$candidate"
    return 0
  fi
  if [[ "$cur_state" != "PLAN_REVIEW" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage review: ${plan_id} is in state '${cur_state:-<none>}' — the review stage runs only out of PLAN_REVIEW (the gate stage puts it there)." >&2
    return 1
  fi

  # ── CP2 F1 (2026-07-25): the worktree must BE the candidate ─────────────
  # `--stage gates` documents why ("the working tree must BE the candidate while
  # they run"), checks out plan/<plan_id> and restores HEAD afterwards. This stage
  # did neither, so in the normal gates -> review flow it ran with HEAD on whatever
  # branch preceded gates — typically the target branch. Two costs: the
  # `git status` half of the drift check was baselined against the WRONG tree (a
  # "fix" rewriting a file to the version already on that branch reads as clean),
  # and the four specialists were dispatched against a tree that is not the
  # candidate, so any agent reading the worktree silently reviewed the wrong code.
  # Refuse rather than silently check out: the controller dispatches BETWEEN the
  # exit-7 and the validating invocation, so it — not this stage — must place the
  # worktree on the candidate and keep it there for the whole review boundary.
  local head_now=""
  head_now="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ "$head_now" != "$candidate" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage review requires the worktree to BE the frozen candidate, but HEAD is ${head_now:-<unknown>} and the candidate is ${candidate}. The plan-level specialists review this worktree, and the drift check is baselined on it. Run 'git -C ${root} checkout plan/${plan_id}' (the candidate is its head) before dispatching the reviewers, and stay there until '--stage review' returns 0." >&2
    return 1
  fi


  local run_dir_abs="${root}/${run_dir_rel}"
  mkdir -p "$run_dir_abs" || {
    echo "PRECONDITION FAIL: cannot create ${run_dir_rel}." >&2
    return 1
  }

  local -a utilities=()
  local u
  while IFS= read -r u; do [[ -n "$u" ]] && utilities+=("$u"); done < <(_pfsm_plan_final_utilities "$execution_yaml")

  # ── review-requirements.json: the machine-readable dispatch contract ─────
  local reqs_json="[]" row fname atype binding
  while IFS='|' read -r fname atype binding; do
    [[ -z "$fname" ]] && continue
    reqs_json="$(jq -c --arg p "${run_dir_rel}/${fname}" --arg t "$atype" --arg b "$binding" \
      '. + [{path:$p, artifact_type:(if $t == "-" then null else $t end), binding:$b}]' <<< "$reqs_json")"
  done < <(_pfsm_review_required_outputs)
  local req_file="${run_dir_abs}/review-requirements.json"
  jq -n --arg plan "$plan_id" --arg run "$run_id" --arg cand "$candidate" --arg base "$base_commit" \
        --argjson reqs "$reqs_json" \
        --argjson agents "$(printf '%s\n' "${_AID_PLAN_FINAL_AGENTS[@]}" | jq -R . | jq -s .)" \
        --argjson utils "$(printf '%s\n' "${utilities[@]}" | jq -R . | jq -s .)" \
    '{plan_id:$plan, run_id:$run, candidate_sha:$cand, plan_base_commit:$base,
      review_range:($base + ".." + $cand),
      required_outputs:$reqs, required_agent_dispatches:$agents,
      registered_utilities:$utils}' > "${req_file}.tmp" \
    && mv "${req_file}.tmp" "$req_file" || {
      rm -f "${req_file}.tmp"
      echo "PRECONDITION FAIL: could not write ${run_dir_rel}/review-requirements.json." >&2
      return 1
    }

  # ── Presence: exit 7, listing exactly what the controller must dispatch ──
  local -a missing=()
  while IFS='|' read -r fname atype binding; do
    [[ -z "$fname" ]] && continue
    [[ -f "${run_dir_abs}/${fname}" ]] || missing+=("$fname")
  done < <(_pfsm_review_required_outputs)
  if (( ${#missing[@]} > 0 )); then
    echo "awaiting_review_outputs: ${plan_id} is blocked in PLAN_REVIEW until the following plan-final outputs exist in ${run_dir_rel}/ — ${missing[*]}. This is a DISPATCH state, not an error: the FSM does not dispatch agents; the controller does, then re-runs '--stage review'. The full contract (expected path, artifact type, subject binding) is in ${run_dir_rel}/review-requirements.json; the review range is ${base_commit}..${candidate}." >&2
    return 7
  fi

  # ── Protocol validation, then per-output subject binding ────────────────
  local fails=0
  _rassert() { echo "PLAN-FINAL REVIEW ASSERTION FAILED: $1" >&2; fails=$((fails+1)); }

  while IFS='|' read -r fname atype binding; do
    [[ -z "$fname" || "$atype" == "-" ]] && continue
    local vrc=0 vout=""
    # CP2 F3 (2026-07-25): aid-protocol-validate.sh returns 0 with `legacy_skipped`
    # for any artifact declaring control_protocol: "legacy", BEFORE the envelope,
    # provenance and type-specific checks — including the audit-report independence
    # check. Accepting that here would let the one artifact whose independence is
    # the entire point of the audit opt out of proving it. A plan-final review
    # output must be a real protocol-v2 artifact.
    local proto
    proto="$(jq -r '.control_protocol // ""' "${run_dir_abs}/${fname}" 2>/dev/null || echo "")"
    if [[ "$proto" == "legacy" ]]; then
      _rassert "${fname} declares control_protocol: \"legacy\", which short-circuits aid-protocol-validate.sh before the envelope, provenance and type-specific checks (for an audit report, before the independence check). A plan-final review output must be a real protocol-v2 artifact."
      continue
    fi
    # CP2 F5: pass the candidate as the current head so the validator's freshness
    # cross-check (revision.head_is_current / revision.freshness) actually runs
    # instead of being skipped for an empty CURRENT_HEAD.
    vout="$(bash "${SCRIPT_DIR}/aid-protocol-validate.sh" "${run_dir_abs}/${fname}" --current-head "$candidate" 2>&1)" || vrc=$?
    if [[ "$vrc" -ne 0 ]]; then
      _rassert "${fname} fails aid-protocol-validate.sh (validator exit ${vrc}: ${vout})."
      continue
    fi
    local decl
    decl="$(jq -r '.artifact_type // ""' "${run_dir_abs}/${fname}")"
    [[ "$decl" == "$atype" ]] \
      || _rassert "${fname} declares artifact_type '${decl}', expected '${atype}'."
  done < <(_pfsm_review_required_outputs)

  # Every JSON review output must be bound to THIS candidate and THIS plan.
  # An EPIC evidence pack copied into the run directory fails right here:
  # identity.plan_id is absent (or names another plan) and the head is an EPIC
  # head, not the candidate.
  local f
  for f in semantic-review-final.json audit-report.json curator-report.json \
           delivery-report.json review-profile.json delivery-gate.json \
           acceptance-evidence.json; do
    local h p
    h="$(jq -r '.revision.head_sha // ""' "${run_dir_abs}/${f}")"
    [[ "$h" == "$candidate" ]] \
      || _rassert "${f} records revision.head_sha '${h}', expected the frozen candidate '${candidate}' — a review of any other head is stale evidence."
    # CP2 F2 (2026-07-25): bind to the ATTEMPT, not only the candidate. Without
    # this, an invalidation that is REVERTED rather than fixed re-freezes the SAME
    # commit into a new run directory, and `cp -p` of the previous attempt's
    # outputs satisfies every other check — heads match, the curator ref is
    # self-consistent because the audit report was copied alongside it, and cp -p
    # preserves mtimes so the Reporter-last ordering still holds. The stage would
    # return 0 having validated a review nobody performed on this attempt.
    local rid_out
    rid_out="$(jq -r '.identity.run_id // ""' "${run_dir_abs}/${f}")"
    [[ "$rid_out" == "$run_id" ]] \
      || _rassert "${f} records identity.run_id '${rid_out}', expected this attempt's '${run_id}' — an output carried over from a previous plan-final attempt is not a review of THIS attempt, even when the candidate sha happens to match."
    p="$(jq -r '.identity.plan_id // ""' "${run_dir_abs}/${f}")"
    [[ "$p" == "$plan_id" ]] \
      || _rassert "${f} records identity.plan_id '${p}', expected '${plan_id}' — this output does not belong to this plan (an EPIC evidence pack copied in fails here)."
  done

  # semantic-review-final.json: the RANGE must cover the whole plan.
  local sr_base
  sr_base="$(jq -r '.revision.base_sha // ""' "${run_dir_abs}/semantic-review-final.json")"
  [[ "$sr_base" == "$base_commit" ]] \
    || _rassert "semantic-review-final.json records revision.base_sha '${sr_base}', expected plan_base_commit '${base_commit}' — the C2 final review must cover ${base_commit}..${candidate}, so a defect introduced by the FIRST EPIC is still in range after the last one is integrated."
  local sr_range
  sr_range="$(jq -r '.semantic_review.range // ""' "${run_dir_abs}/semantic-review-final.json")"
  if [[ -n "$sr_range" && "$sr_range" != "${base_commit}..${candidate}" ]]; then
    _rassert "semantic-review-final.json records semantic_review.range '${sr_range}', expected '${base_commit}..${candidate}'."
  fi

  # audit-report.json: reviewed_head + input_manifest_hash.
  local a_head a_hash
  a_head="$(jq -r '.audit_report.reviewed_head // ""' "${run_dir_abs}/audit-report.json")"
  a_hash="$(jq -r '.audit_report.input_manifest_hash // ""' "${run_dir_abs}/audit-report.json")"
  [[ "$a_head" == "$candidate" ]] \
    || _rassert "audit-report.json records audit_report.reviewed_head '${a_head}', expected the frozen candidate '${candidate}'."
  [[ -n "$a_hash" ]] \
    || _rassert "audit-report.json has no audit_report.input_manifest_hash — the audit's own input set is unproven."

  # curator-report.json: audit_report_ref must be sha256(audit-report.json).
  local c_ref c_actual
  c_ref="$(jq -r '(.curator.audit_report_ref // "") | if type == "object" then (.sha256 // "") else . end' "${run_dir_abs}/curator-report.json")"
  c_ref="${c_ref#sha256:}"
  c_actual="$(sha256sum "${run_dir_abs}/audit-report.json" | awk '{print $1}')"
  [[ "$c_ref" == "$c_actual" ]] \
    || _rassert "curator-report.json's curator.audit_report_ref (${c_ref:-<absent>}) is not sha256 of the audit report in this run directory (${c_actual}) — the Curator reviewed a DIFFERENT audit report."

  # simplifier-report.md: the `Head:` provenance line.
  if ! grep -Eq "^[[:space:]]*[*_]{0,2}Head:?[*_]{0,2}[[:space:]]*:?[[:space:]]*${candidate}[[:space:]]*$" \
        "${run_dir_abs}/simplifier-report.md"; then
    _rassert "simplifier-report.md has no 'Head: ${candidate}' provenance line — the Simplifier's subject is unproven, so it may have read any tree."
  fi

  # review-profile.json: the C3 gate arming input.
  jq -e '(.review_profile.required_lenses | type == "array")' "${run_dir_abs}/review-profile.json" >/dev/null 2>&1 \
    || _rassert "review-profile.json has no review_profile.required_lenses[] — lib/review-profile-check.sh reports 'unverifiable' on it, so the C3 gate would never be armed for the plan-level C4 run."
  local rp_base
  rp_base="$(jq -r '.revision.base_sha // ""' "${run_dir_abs}/review-profile.json")"
  [[ "$rp_base" == "$base_commit" ]] \
    || _rassert "review-profile.json records revision.base_sha '${rp_base}', expected plan_base_commit '${base_commit}' — the profile must be derived over the whole plan range."

  # ── The plan-level aggregates: delivery-gate + acceptance-evidence ──────
  # `identity.epic_id` MUST be null: these are the PLAN's aggregates, and an
  # EPIC id here would make them indistinguishable from a per-EPIC artifact
  # (the delivery-gate schema was widened to string-or-null in this step so
  # the plan-level shape is schema-valid rather than merely tolerated).
  local contributing
  contributing="$(plan_manifest_get "$plan_id" '[.plan_boundary_manifest.epic_runs[] | select(.status == "merged_to_plan") | .epic_id] | sort | join(" ")' 2>/dev/null)" || contributing=""
  [[ "$contributing" == "not_found" ]] && contributing=""
  local agg
  for agg in delivery-gate.json acceptance-evidence.json; do
    local eid
    eid="$(jq -r '.identity.epic_id // "null"' "${run_dir_abs}/${agg}")"
    [[ "$eid" == "null" ]] \
      || _rassert "${agg} records identity.epic_id '${eid}' — the plan-level aggregate is bound to the PLAN (epic_id null, plan_id set), never to one EPIC."
    local srcs missing_e=""
    srcs="$(jq -r '[(.sources // [])[] | if type == "object" then (.epic_id // "") else . end] | sort | join(" ")' "${run_dir_abs}/${agg}")"
    if [[ -z "$srcs" ]]; then
      _rassert "${agg} has an empty sources[] — the aggregate must name the EPIC runs it was aggregated from (epic_runs[].evidence_dir)."
    else
      local e
      for e in $contributing; do
        [[ " ${srcs} " == *" ${e} "* ]] || missing_e="${missing_e:+${missing_e}, }${e}"
      done
      [[ -z "$missing_e" ]] \
        || _rassert "${agg} is missing a per-EPIC contribution for: ${missing_e}. A plan-level aggregate that silently omits an EPIC would report the plan green on partial evidence."
    fi
  done

  # ── dispatch-record.json: exactly one dispatch per agent and per utility ─
  local dr="${run_dir_abs}/dispatch-record.json"
  jq -e 'type == "object"' "$dr" >/dev/null 2>&1 \
    || _rassert "dispatch-record.json is not a JSON object."
  local dr_cand
  dr_cand="$(jq -r '.candidate_sha // ""' "$dr" 2>/dev/null || echo "")"
  [[ "$dr_cand" == "$candidate" ]] \
    || _rassert "dispatch-record.json records candidate_sha '${dr_cand}', expected '${candidate}' — a dispatch record for another candidate proves nothing about THIS attempt."
  # CP2 F2: the candidate alone does not identify the attempt — a re-freeze of the
  # same commit gets a NEW run id, and a copied dispatch record would otherwise
  # still match.
  local dr_run
  dr_run="$(jq -r '.run_id // ""' "$dr" 2>/dev/null || echo "")"
  [[ "$dr_run" == "$run_id" ]] \
    || _rassert "dispatch-record.json records run_id '${dr_run}', expected this attempt's '${run_id}' — a dispatch record copied from a previous attempt proves nothing about THIS one."
  local ag n
  local counts_json="{}" utils_json="[]"
  for ag in "${_AID_PLAN_FINAL_AGENTS[@]}"; do
    n="$(jq -r --arg a "$ag" '[(.dispatches // [])[] | select(.agent == $a) | (.count // 1)] | add // 0' "$dr" 2>/dev/null || echo 0)"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if [[ "$n" -ne 1 ]]; then
      _rassert "dispatch-record.json records ${n} dispatch(es) of '${ag}' on this attempt, expected exactly 1 — every plan-boundary specialist runs once against the frozen candidate."
    fi
    counts_json="$(jq -c --arg a "$ag" --argjson n "${n:-0}" '. + {($a): $n}' <<< "$counts_json")"
  done
  local ut
  for ut in "${utilities[@]}"; do
    n="$(jq -r --arg u "$ut" '[(.utilities // [])[] | select(.id == $u) | (.count // 1)] | add // 0' "$dr" 2>/dev/null || echo 0)"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if [[ "$n" -ne 1 ]]; then
      _rassert "dispatch-record.json records ${n} run(s) of the registered plan-boundary utility '${ut}', expected exactly 1 — every registered utility is counted EXPLICITLY, never assumed."
    fi
    utils_json="$(jq -c --arg u "$ut" --argjson n "${n:-0}" '. + [{id:$u, count:$n}]' <<< "$utils_json")"
  done

  # ── The Reporter runs LAST — after the final non-mutating pass ──────────
  # Its authoritative output is this protocol-v2 JSON; the human
  # `.aid-o/reports/<plan_id>-delivery.md` is a PROJECTION and is explicitly
  # not release authority. Ordering is asserted from the on-disk mtimes: a
  # delivery report older than any other review output describes a state of
  # the review that no longer holds (e.g. a Simplifier fix accepted after it).
  local dr_mtime other_mtime
  dr_mtime="$(stat -c %Y "${run_dir_abs}/delivery-report.json" 2>/dev/null || echo 0)"
  while IFS='|' read -r fname atype binding; do
    [[ -z "$fname" || "$fname" == "delivery-report.json" || "$fname" == "dispatch-record.json" ]] && continue
    other_mtime="$(stat -c %Y "${run_dir_abs}/${fname}" 2>/dev/null || echo 0)"
    if [[ "$dr_mtime" -lt "$other_mtime" ]]; then
      _rassert "delivery-report.json is OLDER than ${fname} — the Reporter must be dispatched last, after the final non-mutating pass. Re-dispatch the Reporter against the current outputs."
    fi
  done < <(_pfsm_review_required_outputs)

  if [[ "$fails" -gt 0 ]]; then
    echo "PRECONDITION FAIL: ${fails} plan-final review assertion(s) failed for ${plan_id}; the plan stays in PLAN_REVIEW and no transition was made. A stale, wrong-plan or wrong-candidate output is NEVER accepted with a warning." >&2
    return 1
  fi

  # ── The candidate must STILL be intact after all validation ─────────────
  # Cheap, and it closes the window in which a background specialist commits
  # while this stage is reading its outputs.
  if ! drift="$(_pfsm_review_candidate_drift "$root" "$plan_id" "$candidate")"; then
    local irc2=0
    plan_final_invalidate "$plan_id" "candidate_changed_during_review" "PLAN_FIX" || irc2=$?
    [[ "$irc2" -ne 0 ]] && return "$irc2"
    echo "CANDIDATE INVALIDATED (post-validation): ${drift}. The outputs validated moments ago describe a candidate that no longer exists; ${plan_id} is now PLAN_FIX." >&2
    return 6
  fi

  # ── Record the pass, then transition PLAN_REVIEW -> AWAITING_PM ─────────
  local outputs_json="{}"
  while IFS='|' read -r fname atype binding; do
    [[ -z "$fname" ]] && continue
    outputs_json="$(jq -c --arg f "$fname" \
      --arg s "sha256:$(sha256sum "${run_dir_abs}/${fname}" | awk '{print $1}')" \
      '. + {($f): $s}' <<< "$outputs_json")"
  done < <(_pfsm_review_required_outputs)

  local review_json
  review_json="$(jq -nc --arg cand "$candidate" --arg base "$base_commit" --arg run "$run_id" \
    --argjson outputs "$outputs_json" --argjson counts "$counts_json" --argjson utils "$utils_json" \
    '{candidate_sha:$cand, review_range:($base + ".." + $cand), run_id:$run,
      outputs:$outputs, dispatch_counts:$counts, utilities_run:$utils}')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_final_review = ${review_json}" >/dev/null || {
    echo "PRECONDITION FAIL: every plan-final review output for ${plan_id} validated, but the result could not be recorded in the manifest — refusing to transition on an unrecorded pass. Re-run '--stage review'; it re-validates the same durable outputs." >&2
    return 1
  }

  local op_id crc=0
  op_id="$(plan_op_key "plan-finalize-review" "$plan_id" "-" "0" "$plan_id")"
  plan_op_begin "$plan_id" "$op_id" "plan-finalize-review" "$plan_id" "$candidate" >/dev/null 2>&1 || true
  if ! _pfsm_plan_state_set "$plan_id" "AWAITING_PM"; then
    echo "PRECONDITION FAIL: the plan-final review for ${plan_id} passed every assertion and is recorded in the manifest, but the plan STATE FILE could not be moved PLAN_REVIEW -> AWAITING_PM. Re-run '--stage review' — the outputs are durable and it re-validates them without re-dispatching anything." >&2
    return 1
  fi
  plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_state = "AWAITING_PM"' >/dev/null 2>&1 || true
  plan_op_commit "$plan_id" "$op_id" >/dev/null 2>&1 || crc=$?
  if [[ "$crc" -ne 0 ]]; then
    echo "WARN: could not record the plan-finalize-review state_committed op for ${plan_id} (rc=${crc}); the state transition itself landed." >&2
  fi

  # ── The SPLIT marker (P068 Step 6) ───────────────────────────────────────
  # `plan-review-complete` says exactly what it means: every plan-final review
  # is complete and the PM decision is still PENDING. It is deliberately NOT
  # `plan-close-complete` — that second marker is written only after the PM
  # decision exists AND the merge (or a recorded abort) has happened AND the
  # lifecycle receipt is committed, so a closed plan can never be reported
  # before the release actually occurred.
  local _pr_marker="${root}/.aid-o/work/plan-state/${plan_id}/plan-review-complete"
  mkdir -p "$(dirname "$_pr_marker")" 2>/dev/null || true
  printf 'run_id=%s\ncandidate_sha=%s\nreviews_complete_at=%s\npm_decision=pending\n' \
    "$run_id" "$candidate" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${_pr_marker}.tmp" 2>/dev/null \
    && mv -f "${_pr_marker}.tmp" "$_pr_marker" 2>/dev/null || rm -f "${_pr_marker}.tmp" 2>/dev/null

  echo "$candidate"
  echo "plan-final review PASSED for ${plan_id} at ${candidate} over ${base_commit}..${candidate} — every required output in ${run_dir_rel}/ is present, protocol-valid and bound to the candidate; ${plan_id} is now AWAITING_PM." >&2
  return 0
}

# =============================================================================
# P068 Step 4 — `plan-finalize --stage c4` and `--stage summary`
# =============================================================================
#
# `--stage c4` produces EXACTLY ONE plan-mode release decision, bound to the
# frozen candidate AND to the approved target head, into the plan-final run
# directory. It is the plan-level analogue of the FSM's review->release C4 hook
# for EPICs, and it reuses the SAME aggregator (`aid-release-policy.sh`) in its
# new `--plan` mode — no second decision engine.
#
# `--stage summary` renders the PM plan-final summary from that decision (via
# `aid-pm-brief.sh`, which reads release-decision.json and nothing else).
#
# STATE: both stages run out of AWAITING_PM and make NO state transition.
# `--stage review` is what moves PLAN_REVIEW -> AWAITING_PM (Step 3), and the
# plan state table in lib/aid-plan-state.sh has no state between them. Adding
# one would be a state-machine change, which this step deliberately does not
# make; instead both stages are idempotent and re-runnable inside AWAITING_PM,
# and `--stage summary` ASSERTS the plan is in AWAITING_PM rather than moving it
# there a second time. The PM authorization + merge remain Step 5's job.
#
# DUAL RUN: before E10, C4 keeps its configured mode from
# defaults/policies/release-decision-policy.yaml (`enforcement: observe` today)
# and emits dual-run evidence exactly as aid-fsm.sh does for EPICs — the
# comparison is recorded, and only `enforcement: blocking` lets a
# release_ready=false actually fail the stage.
# ---------------------------------------------------------------------------

# _pfsm_c4_enforcement — echoes observe|blocking. Fail-safe: anything unreadable
# degrades to `observe` (never blocks), mirroring the aid-fsm.sh hook.
_pfsm_c4_enforcement() {
  local pf="${RELEASE_DECISION_POLICY:-${SCRIPT_DIR}/../defaults/policies/release-decision-policy.yaml}"
  local v=""
  if [[ -f "$pf" ]] && command -v yq >/dev/null 2>&1; then
    v="$(yq -r '.enforcement // "observe"' "$pf" 2>/dev/null || echo observe)"
  fi
  case "$v" in blocking) echo blocking ;; *) echo observe ;; esac
}

# ---------------------------------------------------------------------------
# _pfsm_finalize_c4 <root> <plan_id>
# ---------------------------------------------------------------------------
_pfsm_finalize_c4() {
  local root="$1" plan_id="$2"

  command -v jq >/dev/null 2>&1 || {
    echo "PRECONDITION FAIL: plan-finalize --stage c4 requires jq — refusing to produce a release decision without the tool that reads its inputs." >&2
    return 1
  }

  local candidate base_commit run_id run_dir_rel target_branch target_head v
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  base_commit="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_base_commit')" || base_commit=""
  run_id="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || run_id=""
  run_dir_rel="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir_rel=""
  target_branch="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch')" || target_branch=""
  target_head="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch_head_at_candidate_freeze')" || target_head=""
  for v in candidate base_commit run_id run_dir_rel target_branch target_head; do
    if [[ -z "${!v}" || "${!v}" == "null" || "${!v}" == "not_found" ]]; then
      echo "PRECONDITION FAIL: plan-finalize --stage c4: ${plan_id} has no frozen candidate (${v} is unset) — the plan-level release decision is bound to ONE immutable candidate and to the target head recorded at its freeze. Run '--stage sync', '--stage freeze', '--stage gates' and '--stage review' first." >&2
      return 1
    fi
  done

  # The same invalidation trigger the review stage runs, for the same reason: a
  # tracked write between the review and the decision means the decision would
  # describe a candidate that no longer exists.
  local drift=""
  if ! drift="$(_pfsm_review_candidate_drift "$root" "$plan_id" "$candidate")"; then
    local irc=0
    plan_final_invalidate "$plan_id" "candidate_changed_during_c4" "PLAN_FIX" || irc=$?
    [[ "$irc" -ne 0 ]] && return "$irc"
    echo "CANDIDATE INVALIDATED: ${drift}. No release decision was produced; ${plan_id} is now PLAN_FIX. Re-run the whole plan-final cycle against the NEW candidate." >&2
    return 6
  fi

  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""
  if [[ "$cur_state" != "AWAITING_PM" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage c4: ${plan_id} is in state '${cur_state:-<none>}' — the plan-level C4 decision runs only out of AWAITING_PM (the review stage puts it there)." >&2
    return 1
  fi

  # Same worktree rule as `--stage review`: the decision's inputs are read at the
  # candidate, and aid-evidence-verify.sh --at-head compares against the worktree.
  local head_now=""
  head_now="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo "")"
  if [[ "$head_now" != "$candidate" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage c4 requires the worktree to BE the frozen candidate, but HEAD is ${head_now:-<unknown>} and the candidate is ${candidate}. Run 'git -C ${root} checkout plan/${plan_id}' before the C4 stage." >&2
    return 1
  fi

  local run_dir_abs="${root}/${run_dir_rel}"
  local decision="${run_dir_abs}/release-decision.json"
  mkdir -p "$run_dir_abs" || { echo "PRECONDITION FAIL: cannot create ${run_dir_rel}." >&2; return 1; }

  # ── The one plan-mode C4 run ────────────────────────────────────────────
  local arc=0 aout=""
  aout="$(AID_PROJECT_ROOT="$root" bash "${SCRIPT_DIR}/aid-release-policy.sh" \
    --plan "$plan_id" --run-id "$run_id" --evidence-dir "$run_dir_rel" \
    --candidate-sha "$candidate" --target-ref "$target_branch" --target-head-sha "$target_head" \
    --out "$decision" 2>&1)" || arc=$?
  if [[ "$arc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage c4: the plan-mode release aggregator exited ${arc} for ${plan_id} — no release decision was recorded. Aggregator output: ${aout}" >&2
    return 1
  fi
  if ! jq -e '.release_decision | type == "object"' "$decision" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-finalize --stage c4: ${run_dir_rel}/release-decision.json is not a release_decision artifact." >&2
    return 1
  fi

  local release_ready blockers_n
  release_ready="$(jq -r '.release_decision.release_ready' "$decision")"
  blockers_n="$(jq -r '.release_decision.blockers | length' "$decision")"

  # ── The relocated legacy release checks, run ONCE in this same stage ─────
  # At the plan boundary the legacy stack is the plan-final gate report plus the
  # recorded plan-final review — the two things that, before C4 existed, were the
  # whole basis for "this is releasable". Both are already durable, so this is a
  # read, not a re-run.
  local legacy_gates="fail" legacy_review="fail" legacy_verdict="false"
  local gr="${run_dir_abs}/gates_report.json"
  if [[ -f "$gr" ]] && jq -e '(.overall // .gates_report.result // .status // "") == "pass"' "$gr" >/dev/null 2>&1; then
    legacy_gates="pass"
  fi
  if [[ "$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_review.run_id')" == "$run_id" ]]; then
    legacy_review="pass"
  fi
  [[ "$legacy_gates" == "pass" && "$legacy_review" == "pass" ]] && legacy_verdict="true"

  local match="false" divergence="none"
  [[ "$release_ready" == "$legacy_verdict" ]] && match="true"
  if [[ "$match" != "true" ]]; then
    if [[ "$release_ready" == "false" ]]; then divergence="c4_stricter"; else divergence="c4_permissive"; fi
  fi

  local enforcement; enforcement="$(_pfsm_c4_enforcement)"
  local dual="${run_dir_abs}/release-decision-dual-run.json"
  jq -n --arg plan "$plan_id" --arg run "$run_id" --arg cand "$candidate" \
        --arg tref "$target_branch" --arg thead "$target_head" \
        --arg enf "$enforcement" --arg div "$divergence" \
        --arg lg "$legacy_gates" --arg lr "$legacy_review" \
        --argjson rr "$release_ready" --argjson lv "$legacy_verdict" --argjson m "$match" \
    '{event:"release_policy_dual_run", plan_id:$plan, run_id:$run, candidate_sha:$cand,
      target_ref:$tref, target_head_sha:$thead, head_sha:$cand,
      enforcement:$enf, c4_release_ready:$rr,
      legacy_verdict:$lv, legacy_checks:{gates_report:$lg, plan_final_review:$lr},
      match:$m, divergence_class:$div}' > "${dual}.tmp" \
    && mv "${dual}.tmp" "$dual" || {
      rm -f "${dual}.tmp"
      echo "PRECONDITION FAIL: plan-finalize --stage c4: could not write ${run_dir_rel}/release-decision-dual-run.json — a C4 run whose dual-run evidence is not durable is not recorded." >&2
      return 1
    }

  local c4_json
  c4_json="$(jq -nc --arg run "$run_id" --arg cand "$candidate" --arg thead "$target_head" \
    --arg enf "$enforcement" --argjson rr "$release_ready" --argjson bn "$blockers_n" \
    --argjson m "$match" --arg div "$divergence" \
    '{run_id:$run, candidate_sha:$cand, target_head_sha:$thead, enforcement:$enf,
      release_ready:$rr, blockers:$bn, dual_run:{match:$m, divergence_class:$div}}')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_final_c4 = ${c4_json}" >/dev/null || {
    echo "PRECONDITION FAIL: the plan-final C4 decision for ${plan_id} was written to ${run_dir_rel}/release-decision.json, but the result could not be recorded in the manifest. Re-run '--stage c4' — the aggregator is deterministic at a fixed candidate." >&2
    return 1
  }

  if [[ "$enforcement" == "blocking" && "$release_ready" != "true" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage c4: release_ready=false with ${blockers_n} blocker(s) and release-decision-policy enforcement=blocking. The decision is durable at ${run_dir_rel}/release-decision.json; resolve the blockers listed there." >&2
    return 1
  fi

  echo "$candidate"
  echo "plan-final C4 decision recorded for ${plan_id} at ${candidate} (release_ready=${release_ready}, blockers=${blockers_n}, enforcement=${enforcement}, dual_run match=${match}/${divergence}). ${plan_id} stays AWAITING_PM; run '--stage summary' next." >&2
  return 0
}

# ---------------------------------------------------------------------------
# _pfsm_finalize_summary <root> <plan_id>
# ---------------------------------------------------------------------------
_pfsm_finalize_summary() {
  local root="$1" plan_id="$2"

  command -v jq >/dev/null 2>&1 || {
    echo "PRECONDITION FAIL: plan-finalize --stage summary requires jq." >&2
    return 1
  }

  local candidate run_id run_dir_rel v
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  run_id="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || run_id=""
  run_dir_rel="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir_rel=""
  for v in candidate run_id run_dir_rel; do
    if [[ -z "${!v}" || "${!v}" == "null" || "${!v}" == "not_found" ]]; then
      echo "PRECONDITION FAIL: plan-finalize --stage summary: ${plan_id} has no frozen candidate (${v} is unset)." >&2
      return 1
    fi
  done

  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""
  if [[ "$cur_state" != "AWAITING_PM" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage summary: ${plan_id} is in state '${cur_state:-<none>}' — the PM summary is rendered for a plan that is AWAITING_PM (the review stage puts it there, the C4 stage keeps it there)." >&2
    return 1
  fi

  local run_dir_abs="${root}/${run_dir_rel}"
  local decision="${run_dir_abs}/release-decision.json"
  if [[ ! -s "$decision" ]] || ! jq -e '.release_decision | type == "object"' "$decision" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-finalize --stage summary: no plan-mode release decision at ${run_dir_rel}/release-decision.json — run '--stage c4' first. The PM summary REPORTS the decision; it never substitutes for it." >&2
    return 1
  fi
  # A decision produced in EPIC mode (or carried over) cannot be summarised as this
  # plan's: the plan-level sections are rendered from `release_decision.plan_summary`,
  # which only plan mode emits, and the identity must name this plan and this attempt.
  local d_plan d_run d_epic
  d_plan="$(jq -r '.identity.plan_id // ""' "$decision")"
  d_run="$(jq -r '.identity.run_id // ""' "$decision")"
  d_epic="$(jq -r '.identity.epic_id // "null"' "$decision")"
  if [[ "$d_plan" != "$plan_id" || "$d_run" != "$run_id" || "$d_epic" != "null" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage summary: ${run_dir_rel}/release-decision.json is bound to plan '${d_plan:-<absent>}' / run '${d_run:-<absent>}' / epic '${d_epic}', expected plan '${plan_id}' / run '${run_id}' / epic null. A PM summary must never be able to imply an intermediate EPIC was released." >&2
    return 1
  fi
  if ! jq -e '.release_decision.plan_summary | type == "object"' "$decision" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-finalize --stage summary: the decision carries no release_decision.plan_summary — it was not produced in plan mode, so the plan-level sections (EPICs, skips, gates, specialist review, backlog, merge decision) cannot be rendered." >&2
    return 1
  fi

  local brc=0 bout=""
  bout="$(bash "${SCRIPT_DIR}/aid-pm-brief.sh" "$run_dir_abs" 2>&1)" || brc=$?
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage summary: aid-pm-brief.sh exited ${brc} for ${plan_id} — the PM summary is NOT complete. Output: ${bout}" >&2
    return 1
  fi
  local md="${run_dir_abs}/pm-summary.md"
  [[ -s "$md" ]] || {
    echo "PRECONDITION FAIL: plan-finalize --stage summary: ${run_dir_rel}/pm-summary.md was not written." >&2
    return 1
  }
  # The four fields roadmap §8 requires to be DISTINCT and labelled. Asserted here so a
  # renderer regression cannot silently collapse "reviewed" into "released".
  local lbl missing_lbl=""
  for lbl in "Reviewed candidate SHA:" "Approved target SHA:" "Final main merge SHA:" "Release / tag status:"; do
    grep -Fq "$lbl" "$md" || missing_lbl="${missing_lbl:+${missing_lbl}, }${lbl}"
  done
  if [[ -n "$missing_lbl" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage summary: pm-summary.md is missing the required labelled field(s): ${missing_lbl}. The reviewed candidate, the approved target, the final merge SHA and the tag status are four distinct facts and must each be rendered." >&2
    return 1
  fi

  local sum_json
  sum_json="$(jq -nc --arg run "$run_id" --arg cand "$candidate" \
    --arg md "${run_dir_rel}/pm-summary.md" --arg brief "${run_dir_rel}/pm-decision-brief.json" \
    '{run_id:$run, candidate_sha:$cand, pm_summary:$md, pm_decision_brief:$brief}')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_final_summary = ${sum_json}" >/dev/null || {
    echo "PRECONDITION FAIL: the PM plan-final summary for ${plan_id} was rendered at ${run_dir_rel}/pm-summary.md but could not be recorded in the manifest. Re-run '--stage summary' — it re-renders from the same durable decision." >&2
    return 1
  }

  echo "$candidate"
  echo "plan-final PM summary rendered for ${plan_id} at ${run_dir_rel}/pm-summary.md (+ pm-decision-brief.json); ${plan_id} is AWAITING_PM — the merge and the release/tag are Step 5's PM-authorized actions, not this stage's." >&2
  return 0
}

# =============================================================================
# cmd_plan_finalize <plan_id> --stage <sync|freeze|gates|review|c4|summary> [--frozen-at <rfc3339>]
#                    [--execution-yaml <path>] [--substitute-receipt <gate>=<path>]
#                    [--project-root <path>]
# =============================================================================
cmd_plan_finalize() {
  local plan_id="" stage="" project_root_opt="" frozen_at="" execution_yaml_opt=""
  local -a substitute_receipts=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --execution-yaml)
        _pfsm_require_optval "plan-finalize" "$1" "$#" || exit 2
        execution_yaml_opt="$2"; shift 2 ;;
      --substitute-receipt)
        _pfsm_require_optval "plan-finalize" "$1" "$#" || exit 2
        if [[ "$2" != *=* ]]; then
          echo "ERROR: plan-finalize: --substitute-receipt expects <gate_id>=<receipt_path> (got '$2')" >&2
          exit 2
        fi
        substitute_receipts+=("$2"); shift 2 ;;
      --stage)
        _pfsm_require_optval "plan-finalize" "$1" "$#" || exit 2
        stage="$2"; shift 2 ;;
      --frozen-at)
        _pfsm_require_optval "plan-finalize" "$1" "$#" || exit 2
        frozen_at="$2"; shift 2 ;;
      --project-root)
        _pfsm_require_optval "plan-finalize" "$1" "$#" || exit 2
        project_root_opt="$2"; shift 2 ;;
      --*) echo "ERROR: plan-finalize: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"
        else echo "ERROR: plan-finalize: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done

  if [[ -z "$plan_id" || -z "$stage" ]]; then
    echo "Usage: aid-plan-fsm.sh plan-finalize <plan_id> --stage <sync|freeze|gates|review|c4|summary> [--frozen-at <rfc3339>] [--execution-yaml <path>] [--substitute-receipt <gate_id>=<path>] [--project-root <path>]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: plan-finalize: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  case "$stage" in
    sync|freeze|gates|inputs|review|c4|summary) ;;
    *) echo "ERROR: plan-finalize: --stage must be 'sync', 'freeze', 'gates', 'inputs', 'review', 'c4' or 'summary' (got '${stage}')" >&2; exit 2 ;;
  esac
  if [[ "$stage" != "gates" && ${#substitute_receipts[@]} -gt 0 ]]; then
    echo "ERROR: plan-finalize: --substitute-receipt is only meaningful for --stage gates." >&2
    exit 2
  fi

  local project_root
  project_root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$project_root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$project_root"

  # The checks are about the worktree this command actually merges in and
  # freezes FROM — the main worktree, not wherever the operator stands.
  # A dirty tree blocks BOTH stages: a half-applied `prepare-plan` (a version
  # file written, the CHANGELOG edit failed) leaves the tree dirty, and
  # refusing here is what guarantees no candidate is frozen over it.
  _pfsm_check_detached_head "$project_root" || exit 1
  _pfsm_check_no_merge_in_progress "$project_root" || exit 1
  # `--stage review` deliberately does NOT take the generic dirty-tree refusal.
  # For sync/freeze/gates a dirty tree is an operator mistake to be corrected
  # before anything is frozen. During the review boundary it is a SIGNAL with a
  # defined meaning: a utility or an accepted specialist fix wrote a tracked
  # file, i.e. the candidate changed. Exiting 1 here would hide that behind
  # "commit or stash first"; instead `_pfsm_finalize_review` detects it and
  # calls `plan_final_invalidate`, so the plan returns to PLAN_FIX and every
  # review output is invalidated together with the candidate.
  # `c4` and `summary` join `review` in the dirty-tree exemption for the same reason:
  # inside the review->decision->summary boundary a tracked write MEANS the candidate
  # changed, and `_pfsm_finalize_c4` turns that into an invalidation rather than a
  # "commit or stash first" that would hide it.
  if [[ "$stage" != "review" && "$stage" != "c4" && "$stage" != "summary" ]]; then
    _pfsm_check_clean_worktree "$project_root" || exit 1
  fi

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    echo "PRECONDITION FAIL: no plan-boundary-manifest for ${plan_id} — run plan-start first." >&2
    exit 1
  fi

  local rc=0
  case "$stage" in
    sync)   _pfsm_finalize_sync "$project_root" "$plan_id" || rc=$? ;;
    freeze) _pfsm_finalize_freeze "$project_root" "$plan_id" "$frozen_at" || rc=$? ;;
    gates)
      local execution_yaml="${execution_yaml_opt:-${project_root}/.aid-o/config/execution.yaml}"
      _pfsm_finalize_gates "$project_root" "$plan_id" "$execution_yaml" \
        "${substitute_receipts[@]+"${substitute_receipts[@]}"}" || rc=$?
      ;;
    review)
      local execution_yaml_r="${execution_yaml_opt:-${project_root}/.aid-o/config/execution.yaml}"
      _pfsm_finalize_review "$project_root" "$plan_id" "$execution_yaml_r" || rc=$?
      ;;
    inputs)
      # The producer for the three C4 inputs. Runs between `gates` and `review`:
      # the candidate must already be frozen (the profile is derived over the
      # plan range against it) and the review stage validates what this writes.
      local _in_cand _in_base _in_run _in_dir
      _in_cand="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || _in_cand=""
      _in_base="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_base_commit')" || _in_base=""
      _in_run="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || _in_run=""
      _in_dir="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || _in_dir=""
      for v in _in_cand _in_base _in_run _in_dir; do
        if [[ -z "${!v}" || "${!v}" == "null" || "${!v}" == "not_found" ]]; then
          echo "PRECONDITION FAIL: plan-finalize --stage inputs: ${plan_id} has no frozen candidate binding (${v#_in_} is unset) — run '--stage sync' then '--stage freeze' first. The three C4 inputs are derived over the frozen candidate, never over a moving head." >&2
          rc=1; break
        fi
      done
      [[ "$rc" -eq 0 ]] && { _pfsm_finalize_inputs "$plan_id" "$project_root" \
        "${project_root}/${_in_dir}" "$_in_cand" "$_in_base" "$_in_run" || rc=$?; }
      ;;
    c4)      _pfsm_finalize_c4 "$project_root" "$plan_id" || rc=$? ;;
    summary) _pfsm_finalize_summary "$project_root" "$plan_id" || rc=$? ;;
  esac
  exit "$rc"
}

# =============================================================================
# P068 Step 5 — `plan-merge-to-main`: the ONE place in AID where the target
# branch moves
# =============================================================================
#
# It replaces the prose merge in skills/pipeline.md AND the version/tag ceremony
# aid-release.sh performs per EPIC today. Under `plan_branch` mode nothing else
# advances the target branch: no EPIC merges into it, and no intermediate EPIC
# creates a version commit or a tag.
#
# ── WHY THE PUBLISH AND THE LIFECYCLE COMMIT ARE TWO STAGES ─────────────────
# They have CONFLICTING requirements, and one code path cannot satisfy both:
#
#   The merge must NOT check out the target branch. `git checkout <target>` +
#   head check + `git merge` leaves a TOCTOU window in which another process
#   moves the ref between the check and the merge — and in the normal case the
#   checkout is not even possible, because the target branch is checked out in
#   another linked worktree and Git refuses the same branch twice.
#
#   The lifecycle write must be ON the target branch:
#   `_aid_lc_require_target_branch` tests `git branch --show-current`.
#
# The sequence resolves both:
#
#   Stage 1 — build the merge commit in ISOLATION (`git merge-tree --write-tree`
#   for the tree, `git commit-tree` with first parent <target_head_sha> and
#   second parent <candidate_sha>) without moving ANY ref, then publish with
#   `git update-ref refs/heads/<target> <merge> <target_head_sha>`. That is a
#   compare-and-swap: it fails atomically if the ref no longer points at the
#   expected old value, leaving the target branch byte-identical. THE RELEASE IS
#   NOW PUBLISHED and the CAS window is closed.
#
#   Stage 2 — only then the lifecycle commit: the delivery bindings and the CF1
#   re-scope, NOT the receipt. Built with `git commit-tree` (parent = the
#   published merge commit) and published with another compare-and-swap
#   `update-ref` — no worktree, no HEAD. See lib/aid-lifecycle.sh's PLAN MODE
#   header for the five binding-path functions this required.
#
# The receipt is Step 6's (`plan-close`): the split is deliberate so a single
# owner writes each artifact. Step 5 makes the plan CLOSABLE (every required
# EPIC delivered and reviewed, abandoned ones re-scoped); Step 6 verifies
# closure and commits the receipt. If the process dies between the two stages
# the merge STANDS, and the resumed run re-applies the missing binding
# idempotently — never a second merge.
#
# ── TAGGING IS CONDITIONAL ON A VERSION BUMP ────────────────────────────────
# `prepare-plan --bump auto` may resolve to NO bump (only chore:/docs: commits
# since the last tag). The candidate's version then equals the already-released
# one, and `tag-plan --version <that version>` would fail because the tag exists
# on an older commit. So `prepare-plan` records the resolved version — or the
# literal `none` — in release-prep.json, and this command calls `tag-plan` ONLY
# when a new version was prepared. A no-bump plan merges and closes with NO new
# tag: a legal, tested outcome, not a `tag-plan` failure.
#
# ── PUSH ────────────────────────────────────────────────────────────────────
# Publishing to a remote is OPT-IN (`--push`), never a side effect of merging.
# The push is guarded the same way the tag is: it checks whether the remote ref
# already contains the merge commit and pushes at most once.
# ---------------------------------------------------------------------------

# _pfsm_rfc3339_epoch <ts> — echo the epoch seconds of a STRICT RFC 3339 UTC
# instant, or return 1. Deliberately strict and fail-closed: this feeds the
# freeze-time comparison, where "could not parse, assume it is old enough" is
# exactly the degenerate acceptance AC3 forbids.
_pfsm_rfc3339_epoch() {
  local ts="${1:-}"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]] || return 1
  local e=""
  e="$(date -u -d "$ts" +%s 2>/dev/null)" || return 1
  [[ -n "$e" ]] || return 1
  printf '%s' "$e"
}

# _pfsm_validate_json_schema <json_file> <schema_basename> — fail-closed schema
# validation for a runtime (gitignored) JSON artifact. Mirrors
# aid_lifecycle_schema_validate's contract: no python3/jsonschema means the
# artifact is NOT validated, and an unvalidated PM authorization must never
# authorize a merge, so that is exit 1 too.
_pfsm_validate_json_schema() {
  local f="$1" schema_base="$2"
  local schema="${SCRIPT_DIR}/../defaults/schemas/${schema_base}"
  [[ -f "$f" ]] || { echo "schema: artifact not found: $f" >&2; return 1; }
  [[ -f "$schema" ]] || { echo "schema: schema not found: $schema" >&2; return 1; }
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
    echo "schema: validator unavailable (python3 + jsonschema are required to validate ${schema_base}) — refusing to act on an unvalidated artifact." >&2
    return 1
  fi
  python3 -c '
import sys, json, jsonschema
schema = json.load(open(sys.argv[1]))
try:
    inst = json.load(open(sys.argv[2]))
except Exception as e:
    print("schema: artifact is not valid JSON: %s" % e, file=sys.stderr); sys.exit(1)
try:
    jsonschema.validate(inst, schema)
except jsonschema.ValidationError as e:
    print("schema: %s" % e.message, file=sys.stderr); sys.exit(1)
' "$schema" "$f"
}

# _pfsm_release_prep_version <root> <plan_id> <run_dir_rel> — echo the version
# `prepare-plan` resolved, or the literal `none`. Reads the run-directory copy
# first (the attempt's own evidence) and falls back to the canonical record in
# the plan's runtime state directory. A MISSING record is `none`: a plan that
# never ran prepare-plan prepared no version, so it gets no tag.
_pfsm_release_prep_version() {
  local root="$1" plan_id="$2" run_dir_rel="$3"
  local f v
  for f in "${root}/${run_dir_rel}/release-prep.json" \
           "${root}/.aid-o/work/plan-state/${plan_id}/release-prep.json"; do
    [[ -s "$f" ]] || continue
    v="$(jq -r '.version // "none"' "$f" 2>/dev/null || echo none)"
    [[ -z "$v" || "$v" == "null" ]] && v="none"
    printf '%s' "$v"
    return 0
  done
  printf 'none'
  return 0
}

# _pfsm_terminal_rescope <plan_id> — echo "<epic_id>=<abandoned|superseded>"
# lines from the RUNTIME plan-boundary manifest's epic_runs[]. This is CF1's
# input: P064 could only record the terminal status in the runtime manifest,
# because `epic-complete` runs on a task branch and lifecycle writes are refused
# there. Here we are past the merge, so the git-tracked re-scope is legal.
_pfsm_terminal_rescope() {
  local plan_id="$1"
  plan_manifest_get "$plan_id" \
    '[.plan_boundary_manifest.epic_runs[] | select(.status == "abandoned" or .status == "superseded") | .epic_id + "=" + .status] | join("\n")' \
    2>/dev/null || true
}

# ---------------------------------------------------------------------------
# cmd_plan_merge_to_main <plan_id> --decision <path> [--project-root <path>]
#                        [--op-id <id>] [--push]
# ---------------------------------------------------------------------------
cmd_plan_merge_to_main() {
  local plan_id="" decision_file="" project_root_opt="" op_id_opt="" do_push=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --decision)
        _pfsm_require_optval "plan-merge-to-main" "$1" "$#" || exit 2
        decision_file="$2"; shift 2 ;;
      --project-root)
        _pfsm_require_optval "plan-merge-to-main" "$1" "$#" || exit 2
        project_root_opt="$2"; shift 2 ;;
      --op-id)
        _pfsm_require_optval "plan-merge-to-main" "$1" "$#" || exit 2
        op_id_opt="$2"; shift 2 ;;
      --push) do_push=1; shift ;;
      --*) echo "ERROR: plan-merge-to-main: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"
        else echo "ERROR: plan-merge-to-main: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done

  if [[ -z "$plan_id" || -z "$decision_file" ]]; then
    echo "Usage: aid-plan-fsm.sh plan-merge-to-main <plan_id> --decision <path> [--project-root <path>] [--op-id <id>] [--push]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: plan-merge-to-main: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  command -v jq >/dev/null 2>&1 || {
    echo "PRECONDITION FAIL: plan-merge-to-main requires jq." >&2; exit 1; }

  local root; root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$root"

  _pfsm_check_no_merge_in_progress "$root" || exit 1
  _pfsm_check_clean_worktree "$root" || exit 1

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    echo "PRECONDITION FAIL: no plan-boundary-manifest for ${plan_id} — run plan-start first." >&2
    exit 1
  fi

  # ── The candidate binding this merge is authorized against ───────────────
  local target_branch candidate frozen_at target_head_frozen run_id run_dir_rel v
  target_branch="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch')" || target_branch=""
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  frozen_at="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_frozen_at')" || frozen_at=""
  target_head_frozen="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch_head_at_candidate_freeze')" || target_head_frozen=""
  run_id="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || run_id=""
  run_dir_rel="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir_rel=""
  for v in target_branch candidate target_head_frozen run_id run_dir_rel; do
    if [[ -z "${!v}" || "${!v}" == "null" || "${!v}" == "not_found" ]]; then
      echo "PRECONDITION FAIL: plan-merge-to-main: ${plan_id} has no frozen candidate (${v} is unset) — there is nothing a PM could have authorized. Run the plan-final stages first." >&2
      exit 1
    fi
  done

  # ── AC3 (fail-closed freeze time): a manifest with no candidate_frozen_at, or
  #    one that is not a strict RFC 3339 UTC instant, is a DEGENERATE input and
  #    exits 1 — never "assume the decision is old enough". ─────────────────
  local frozen_epoch=""
  if [[ -z "$frozen_at" || "$frozen_at" == "null" || "$frozen_at" == "not_found" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the RUNTIME plan-boundary manifest for ${plan_id} carries no candidate_frozen_at — the PM decision's freshness cannot be established, so no merge is authorized. Re-freeze the candidate." >&2
    exit 1
  fi
  if ! frozen_epoch="$(_pfsm_rfc3339_epoch "$frozen_at")"; then
    echo "PRECONDITION FAIL: plan-merge-to-main: candidate_frozen_at '${frozen_at}' is not a valid RFC 3339 UTC instant — refusing to compare a PM decision against an unparseable freeze time." >&2
    exit 1
  fi

  # ── The PM decision artifact ─────────────────────────────────────────────
  if [[ ! -s "$decision_file" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: no PM decision at '${decision_file}' — ${target_branch} is unchanged. The merge is PM-authorized; it never proceeds on an absent authorization." >&2
    exit 1
  fi
  if ! jq -e '.' "$decision_file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-merge-to-main: '${decision_file}' is not parseable JSON — ${target_branch} is unchanged." >&2
    exit 1
  fi
  local vout="" vrc=0
  vout="$(_pfsm_validate_json_schema "$decision_file" "pm-plan-decision.schema.json" 2>&1)" || vrc=$?
  if [[ "$vrc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the PM decision at '${decision_file}' fails pm-plan-decision.schema.json — ${target_branch} is unchanged and NO Git action was taken. ${vout}" >&2
    exit 1
  fi

  local d_plan d_run d_decision d_cand d_target d_thead d_at
  d_plan="$(jq -r '.plan_id' "$decision_file")"
  d_run="$(jq -r '.plan_final_run_id' "$decision_file")"
  d_decision="$(jq -r '.decision' "$decision_file")"
  d_cand="$(jq -r '.candidate_sha' "$decision_file")"
  d_target="$(jq -r '.target_branch' "$decision_file")"
  d_thead="$(jq -r '.target_head_sha' "$decision_file")"
  d_at="$(jq -r '.decided_at' "$decision_file")"

  if [[ "$d_plan" != "$plan_id" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the decision authorizes plan '${d_plan}', not '${plan_id}' — ${target_branch} is unchanged and no Git action was taken." >&2
    exit 1
  fi
  if [[ "$d_run" != "$run_id" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the decision is bound to plan-final run '${d_run}', but ${plan_id}'s current attempt is '${run_id}' — a decision about an earlier attempt cannot authorize this one. ${target_branch} is unchanged." >&2
    exit 1
  fi
  local decided_epoch=""
  if ! decided_epoch="$(_pfsm_rfc3339_epoch "$d_at")"; then
    echo "PRECONDITION FAIL: plan-merge-to-main: decided_at '${d_at}' is not a valid RFC 3339 UTC instant — refusing to accept an authorization whose timestamp cannot be compared with candidate_frozen_at. ${target_branch} is unchanged." >&2
    exit 1
  fi
  if [[ "$decided_epoch" -lt "$frozen_epoch" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the decision was made at ${d_at}, BEFORE the candidate was frozen at ${frozen_at} — it cannot be a decision about this candidate (a re-freeze rewrites candidate_frozen_at precisely so a decision bound to the pre-refreeze candidate fails here). ${target_branch} is unchanged." >&2
    exit 1
  fi

  # ── The plan state this command is legal from ────────────────────────────
  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""
  case "$cur_state" in
    AWAITING_PM|PLAN_MERGING) ;;
    *)
      echo "PRECONDITION FAIL: plan-merge-to-main: ${plan_id} is in state '${cur_state:-<none>}' — the merge runs out of AWAITING_PM (PLAN_MERGING is the crash-resume re-entry). ${target_branch} is unchanged." >&2
      exit 1
      ;;
  esac

  # ── FIX / ABORT: refuse the merge, record the outcome ────────────────────
  if [[ "$d_decision" != "MERGE" ]]; then
    local reason; reason="$(jq -r '.reason // ""' "$decision_file")"
    local to=""
    case "$d_decision" in
      FIX)   to="PLAN_FIX" ;;
      ABORT) to="ABORTED" ;;
    esac
    if [[ "$d_decision" == "ABORT" ]]; then
      plan_manifest_update "$plan_id" ".plan_boundary_manifest.terminal_reason = $(jq -Rn --arg s "${reason:-pm_abort}" '$s')" >/dev/null 2>&1 || true
    fi
    if ! _pfsm_plan_state_set "$plan_id" "$to"; then
      echo "PRECONDITION FAIL: plan-merge-to-main: the PM decided ${d_decision}, but ${plan_id} could not be moved to ${to}. ${target_branch} is unchanged; reconcile with 'aid-plan-fsm.sh plan-state ${plan_id}'." >&2
      exit 1
    fi
    # F3 (2026-07-27, found while closing the P067 dogfood): `plan-state` reports
    # from the RUNTIME manifest's plan_state mirror, not from the authoritative
    # plan-state.yaml. The merge path mirrors its CLOSED transition; this path
    # did not, so an aborted plan kept reporting AWAITING_PM — the command said
    # "P067 is now ABORTED" and the very next query disagreed with it. A mirror
    # that only some writers maintain is worse than no mirror: every reader
    # trusts it.
    plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_state = $(jq -Rn --arg s "$to" '$s')" >/dev/null 2>&1 \
      || echo "WARN: plan-merge-to-main: ${plan_id} is ${to} in plan-state.yaml, but the runtime manifest's plan_state mirror could not be updated — 'plan-state' will under-report until it is reconciled." >&2
    echo "PM DECISION ${d_decision}: no merge was performed for ${plan_id}; ${target_branch} is unchanged and ${plan_id} is now ${to}${reason:+ (reason: ${reason})}." >&2
    exit 3
  fi

  # ── The candidate must be exactly what the PM approved, and still be the
  #    plan branch head ────────────────────────────────────────────────────
  local plan_branch="plan/${plan_id}"
  local plan_head=""
  plan_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${plan_branch}" 2>/dev/null)" || plan_head=""
  if [[ -z "$plan_head" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: ${plan_branch} not found — ${target_branch} is unchanged." >&2
    exit 1
  fi
  if [[ "$d_cand" != "$candidate" || "$plan_head" != "$candidate" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: candidate mismatch — the decision names ${d_cand}, the manifest's frozen candidate is ${candidate}, and ${plan_branch} is at ${plan_head}. All three must be identical. ${target_branch} is unchanged and no Git action was taken." >&2
    exit 1
  fi
  if [[ "$d_target" != "$target_branch" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the decision authorizes a merge into '${d_target}', but ${plan_id}'s target branch is '${target_branch}'. Nothing was merged." >&2
    exit 1
  fi

  local target_head=""
  target_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null)" || target_head=""
  if [[ -z "$target_head" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: target branch ${target_branch} not found." >&2
    exit 1
  fi
  if [[ "$d_thead" != "$target_head_frozen" ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the decision approved target head ${d_thead}, but the candidate was frozen against ${target_head_frozen} — the authorization does not describe this candidate binding. ${target_branch} is unchanged." >&2
    exit 1
  fi

  # ── Crash resume: has THIS op already published its merge? ────────────────
  # CP2 M2 (2026-07-26): the key used to be plan-id-only, so a SECOND legitimate
  # plan-final attempt (new candidate, fresh decision) reconciled against the
  # FIRST attempt's op log entry and was read as a crash resume — it then skipped
  # merging the new candidate. The ancestry check still made that fail closed, but
  # the reported diagnosis was false. Key on the candidate being merged instead:
  # a resume of the same candidate keeps the identical key (determinism holds),
  # while a different candidate is a different operation. The candidate sha never
  # contains ':', so the key stays parseable.
  local op_id="${op_id_opt:-$(plan_op_key "plan-merge-to-main" "$plan_id" "-" "0" "$candidate")}"
  local phase="none" prc=0
  phase="$(plan_op_reconcile "$plan_id" "$op_id")" || prc=$?
  local resumed_merge=""
  if [[ "$phase" == "git_applied" || "$phase" == "state_committed" ]]; then
    resumed_merge="$(_pfsm_last_resulting_sha "$plan_id" "$op_id")"
  fi

  # ── The stale-authorization case: the target branch advanced while the PM
  #    was deciding. This is NOT merely a mismatch — the plan must go back and
  #    re-synchronise, so the candidate binding is invalidated and the plan
  #    returns to PLAN_SYNC. (Skipped on a resumed run whose merge is already
  #    published: the target head has legitimately moved to OUR merge.) ─────
  # CP2 M1 (2026-07-26): a recorded resulting_sha alone must NOT disarm this
  # guard. It was disarmed whenever the op log held ANY resulting_sha — including
  # when the resume branch is then NOT taken because that recorded merge is no
  # longer an ancestor of the target (a rewound target branch). Control fell
  # through and CAS-published against the LIVE head, which is not the head the PM
  # approved. Disarm only when OUR OWN published merge genuinely explains where
  # the target head now is.
  local resume_explains_head="false"
  if [[ -n "$resumed_merge" ]]; then
    if [[ "$target_head" == "$resumed_merge" ]] \
       || git -C "$root" merge-base --is-ancestor "$resumed_merge" "$target_head" 2>/dev/null; then
      resume_explains_head="true"
    fi
  fi
  if [[ "$resume_explains_head" != "true" && "$target_head" != "$target_head_frozen" ]]; then
    plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_final_merge = {"result":"stale_authorization"}' >/dev/null 2>&1 || true
    local irc=0
    plan_final_invalidate "$plan_id" "stale_authorization" "PLAN_SYNC" || irc=$?
    echo "STALE AUTHORIZATION: ${target_branch} advanced from the approved ${target_head_frozen} to ${target_head} while the PM was deciding. NOTHING was merged, ${target_branch} is unchanged, the candidate binding is cleared and ${plan_id} is back in PLAN_SYNC. Re-run '--stage sync' onwards and obtain a fresh decision." >&2
    [[ "$irc" -ne 0 ]] && exit "$irc"
    exit 1
  fi

  # ─────────────────────────────────────────────────────────────────────────
  # STAGE 1 — build the merge in isolation, publish with a compare-and-swap
  # ─────────────────────────────────────────────────────────────────────────
  local brc=0
  plan_op_begin "$plan_id" "$op_id" "plan-merge-to-main" "$plan_id" "$target_head" || brc=$?
  _pfsm_crash_seam intent
  if [[ "$brc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: could not record the operation intent for ${plan_id} (rc=${brc}) — nothing was merged." >&2
    exit 1
  fi

  local merge_commit="" merged_tree=""
  if [[ -n "$resumed_merge" ]] && git -C "$root" rev-parse --verify --quiet "${resumed_merge}^{commit}" >/dev/null 2>&1 \
     && git -C "$root" merge-base --is-ancestor "$resumed_merge" "$target_branch" 2>/dev/null; then
    # Already published by an earlier attempt of THIS op — never a second merge.
    merge_commit="$resumed_merge"
    merged_tree="$(git -C "$root" rev-parse "${merge_commit}^{tree}" 2>/dev/null)"
    echo "RESUME: the plan merge ${merge_commit} is already published on ${target_branch} — skipping the merge and continuing with the lifecycle bindings, the tag and the push." >&2
  else
    # Merge TREE first — no ref moves, no worktree is touched, no MERGE_HEAD is
    # created, so a conflict costs nothing and leaves nothing to abort.
    local mt_out="" mt_rc=0
    mt_out="$(git -C "$root" merge-tree --write-tree --no-messages "$target_head" "$candidate" 2>&1)" || mt_rc=$?
    if [[ "$mt_rc" -ne 0 ]]; then
      _pfsm_plan_state_set "$plan_id" "CONFLICT" || true
      echo "MERGE CONFLICT: ${plan_branch} (${candidate}) does not merge cleanly into ${target_branch} (${target_head}). NOTHING was merged — ${target_branch} is still at ${target_head} — and ${plan_id} is now CONFLICT. Resolve by re-synchronising the target branch into the plan branch ('plan-finalize --stage sync'), which necessarily produces a NEW plan branch head and therefore INVALIDATES the frozen candidate: there is no path from CONFLICT back to a merge against the old candidate." >&2
      printf '%s\n' "$mt_out" >&2
      exit 4
    fi
    merged_tree="$(printf '%s' "$mt_out" | head -1 | tr -d '[:space:]')"
    if ! [[ "$merged_tree" =~ ^[0-9a-f]{40}$ ]]; then
      echo "PRECONDITION FAIL: plan-merge-to-main: git merge-tree did not produce a tree object for ${plan_id} — ${target_branch} is unchanged. Output: ${mt_out}" >&2
      exit 1
    fi

    local msg="merge(plan): ${plan_id} — ${plan_branch} into ${target_branch}"
    merge_commit="$(git -C "$root" commit-tree "$merged_tree" -p "$target_head" -p "$candidate" -m "$msg" 2>/dev/null)" || merge_commit=""
    if [[ -z "$merge_commit" ]]; then
      echo "PRECONDITION FAIL: plan-merge-to-main: could not build the merge commit for ${plan_id} — no ref was moved and ${target_branch} is unchanged." >&2
      exit 1
    fi
    # Still nothing published: the commit exists as a dangling object only.
    if ! git -C "$root" update-ref "refs/heads/${target_branch}" "$merge_commit" "$target_head" 2>/dev/null; then
      echo "PRECONDITION FAIL: plan-merge-to-main: the compare-and-swap publish was REJECTED — ${target_branch} no longer points at the expected ${target_head}, so another process advanced it between the head check and the publish. NOTHING was published; ${target_branch} is byte-identical. Re-run: the revalidation will detect the advance as a stale authorization." >&2
      exit 1
    fi
  fi

  local grc=0
  plan_op_mark_git_applied "$plan_id" "$op_id" "$merge_commit" || grc=$?
  _pfsm_crash_seam git_applied
  [[ "$grc" -ne 0 ]] && echo "WARN: plan-merge-to-main: the merge ${merge_commit} IS published on ${target_branch}, but the git_applied record could not be written (rc=${grc}) — a resumed run will re-verify from the ref itself." >&2

  # ── Tree identity + reachability, between publish and lifecycle commit ────
  local actual_tree=""
  actual_tree="$(git -C "$root" rev-parse "${merge_commit}^{tree}" 2>/dev/null)" || actual_tree=""
  if [[ "$actual_tree" != "$merged_tree" ]]; then
    echo "TREE VERIFICATION FAILED: the published merge commit ${merge_commit} has tree ${actual_tree:-<unresolved>}, not the expected merged tree ${merged_tree}. ${target_branch} has ALREADY MOVED and this command will NOT attempt an automatic reset — published history is repaired by a new revert or hotfix, never destructively. Inspect manually before any further plan command." >&2
    exit 5
  fi
  if ! git -C "$root" merge-base --is-ancestor "$candidate" "$target_branch" 2>/dev/null; then
    echo "TREE VERIFICATION FAILED: the candidate ${candidate} is not reachable from ${target_branch} after the merge ${merge_commit}. ${target_branch} has ALREADY MOVED; inspect manually — no automatic reset is attempted." >&2
    exit 5
  fi

  # ─────────────────────────────────────────────────────────────────────────
  # STAGE 2 — the lifecycle commit, by plumbing, on top of the published merge
  # ─────────────────────────────────────────────────────────────────────────
  local -a rescope=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" && "$line" != "not_found" && "$line" != "null" ]] && rescope+=("$line")
  done < <(_pfsm_terminal_rescope "$plan_id")

  local run_dir_abs="${root}/${run_dir_rel}"
  local lrc=0 lout=""
  lout="$(aid_lifecycle_plan_merge_bind "$plan_id" "$root" "$merge_commit" "$run_dir_abs" \
            ${rescope[@]+"${rescope[@]}"} 2>&1)" || lrc=$?
  if [[ "$lrc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan-merge-to-main: the merge ${merge_commit} IS published on ${target_branch}, but the lifecycle delivery bindings / CF1 re-scope were not committed (rc=${lrc}). The merge stands — do NOT re-merge; re-run this command (or plan-close-check) to re-apply the bindings idempotently. Detail: ${lout}" >&2
    exit 1
  fi

  # ── The ONE conditional tag (bindings first, so a crash between them cannot
  #    produce a tagged release with no closure path) ───────────────────────
  local version tag_status="none"
  version="$(_pfsm_release_prep_version "$root" "$plan_id" "$run_dir_rel")"
  if [[ "$version" != "none" ]]; then
    local trc=0 tout=""
    tout="$(bash "${SCRIPT_DIR}/aid-release.sh" tag-plan "$plan_id" \
              --merge-sha "$merge_commit" --version "$version" --project-root "$root" 2>&1)" || trc=$?
    if [[ "$trc" -ne 0 ]]; then
      echo "PRECONDITION FAIL: plan-merge-to-main: the merge and the lifecycle bindings are published, but tag-plan failed for v${version} (rc=${trc}). The merge stands; resolve the tag and re-run. Detail: ${tout}" >&2
      exit 1
    fi
    tag_status="v${version}"
  else
    echo "NO TAG: prepare-plan resolved no version bump for ${plan_id} (release-prep.json records 'none'), so no tag is created. A no-bump plan merges and closes without a new tag." >&2
  fi

  # ── Push (opt-in, guarded, at most once) ─────────────────────────────────
  local push_status="skipped"
  if [[ "$do_push" -eq 1 ]]; then
    local remote=""
    remote="$(git -C "$root" config --get "branch.${target_branch}.remote" 2>/dev/null || true)"
    [[ -z "$remote" ]] && remote="$(git -C "$root" remote 2>/dev/null | head -1 || true)"
    if [[ -z "$remote" ]]; then
      push_status="no_remote"
      echo "NO PUSH: --push was given but this repository has no remote configured." >&2
    else
      local remote_sha=""
      remote_sha="$(git -C "$root" ls-remote "$remote" "refs/heads/${target_branch}" 2>/dev/null | awk '{print $1}' | head -1 || true)"
      if [[ -n "$remote_sha" ]] && git -C "$root" merge-base --is-ancestor "$merge_commit" "$remote_sha" 2>/dev/null; then
        push_status="already_pushed"
        echo "PUSH SKIPPED: ${remote}/${target_branch} already contains ${merge_commit}." >&2
      else
        local push_rc=0
        git -C "$root" push "$remote" "refs/heads/${target_branch}:refs/heads/${target_branch}" >/dev/null 2>&1 || push_rc=$?
        if [[ "$push_rc" -ne 0 ]]; then
          echo "PRECONDITION FAIL: plan-merge-to-main: the merge, bindings and tag are LOCAL and durable, but the push to ${remote} failed (rc=${push_rc}). Re-run with --push once the remote is reachable; the push guard makes it idempotent." >&2
          exit 1
        fi
        push_status="pushed"
        if [[ "$tag_status" != "none" ]]; then
          git -C "$root" push "$remote" "refs/tags/${tag_status}" >/dev/null 2>&1 || true
        fi
      fi
    fi
  fi

  # ── The PM authorization, durable in the attempt's own evidence ──────────
  # P068 Step 6: plan-close has to prove a PM authorized THIS merge, and the
  # decision artifact lives wherever the PM happened to write it (a --decision
  # path this command does not own and cannot re-find later). Copying the
  # already-VALIDATED artifact into the attempt's run directory makes the
  # authorization part of the evidence the close attests to, so removing it
  # blocks close (AC7) instead of silently degrading to "the merge record
  # implies someone must have approved it".
  cp -f -- "$decision_file" "${run_dir_rel:+${root}/${run_dir_rel}}/pm-plan-decision.json" 2>/dev/null || \
    echo "WARN: plan-merge-to-main: could not copy the PM decision into ${run_dir_rel}/ — plan-close will refuse until it is present." >&2

  # ── Record + transition ──────────────────────────────────────────────────
  local merge_json
  merge_json="$(jq -nc --arg run "$run_id" --arg cand "$candidate" --arg tb "$target_branch" \
    --arg thead "$target_head_frozen" --arg mc "$merge_commit" --arg tree "$merged_tree" \
    --arg tag "$tag_status" --arg push "$push_status" \
    '{result:"merged", run_id:$run, candidate_sha:$cand, target_branch:$tb,
      target_head_before:$thead, merge_commit:$mc, merged_tree:$tree,
      tag:$tag, push:$push}')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_final_merge = ${merge_json}" >/dev/null 2>&1 || \
    echo "WARN: plan-merge-to-main: the merge ${merge_commit} is published but could not be recorded in the runtime manifest." >&2

  if ! _pfsm_plan_state_set "$plan_id" "PLAN_MERGING"; then
    echo "PRECONDITION FAIL: plan-merge-to-main: ${merge_commit} is published on ${target_branch} and the bindings are committed, but ${plan_id} could not be moved to PLAN_MERGING. Reconcile with 'aid-plan-fsm.sh plan-state ${plan_id}' before plan-close." >&2
    exit 1
  fi
  # DOGFOOD FINDING (P075, 2026-07-27): mirror the transition into the runtime
  # manifest too. `plan-state` — and every other reader of the manifest — answers
  # from that mirror, so a merge that moved only plan-state.yaml left the plan
  # reporting AWAITING_PM while it was actually PLAN_MERGING. Same defect class
  # as the abort path's (F3): a mirror only some writers maintain is worse than
  # no mirror, because every reader trusts it.
  plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_state = "PLAN_MERGING"' >/dev/null 2>&1 \
    || echo "WARN: plan-merge-to-main: ${plan_id} is PLAN_MERGING in plan-state.yaml, but the runtime manifest's plan_state mirror could not be updated — 'plan-state' will under-report until it is reconciled." >&2

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  [[ "$crc" -ne 0 ]] && echo "WARN: plan-merge-to-main: could not append the state_committed record for ${op_id} (rc=${crc})." >&2

  echo "$merge_commit"
  echo "MERGED: ${plan_id} candidate ${candidate} is published on ${target_branch} as ${merge_commit} (tag=${tag_status}, push=${push_status}); ${plan_id} is now PLAN_MERGING. The closure receipt is plan-close's." >&2
  return 0
}

# =============================================================================
# P068 E-068-1_2 Step 6 — `plan-close`, the mechanical close transaction.
#
# WHY THIS EXISTS: two plan-state systems have coexisted and neither read the
# other — the legacy `ca-review-complete` marker plus the gitignored
# `.aid-o/reports/*` (aid-fsm.sh's own `cmd_plan_close`), and the git-tracked
# `.aid-lifecycle/manifests|receipts` layer. A plan could therefore be
# "closed" in one world while the other had no durable proof of anything. This
# command is the ONE place they are reconciled, and it is a real gate: it can
# only pass after the merge or a recorded abort.
#
# TRANSACTION SHAPE — identical to every other durable operation in this file:
#   1. acquire the close lock (see the OWNED-LOCK EXCEPTION below);
#   2. run every precondition through aid-plan-close-check.sh --plan-branch —
#      the checks live there, next to the legacy checks they must agree with;
#   3. `intent`      — plan_op_begin, key plan-close:<plan_id>:-:<attempt>:<plan_id>;
#   4. `git_applied` — the lifecycle receipt commits (merge close), or the abort
#      record + `status: aborted` commit (abort close);
#   5. `state_committed` — the `plan-close-complete` marker is written, and the
#      plan transitions to CLOSED (merge close only; ABORTED is already
#      terminal and the transition table has no ABORTED -> CLOSED edge).
# A crash between 4 and 5 is reconciled by finding the committed receipt and
# writing only the marker — never a second receipt, never a second merge.
#
# OWNED-LOCK EXCEPTION: the close transaction holds its own lock for the whole
# transaction, so a naive "no relevant lock is held" probe would contend with
# its OWN descriptor and always fail — and releasing it before the receipt and
# the marker are durable would destroy the very transaction boundary this
# command exists to provide. The probe therefore excludes exactly ONE path: the
# close lock, passed explicitly as `--exclude-lock`. The exclusion is by exact
# canonical path, not "any lock this process holds", so a DIFFERENT lock held by
# the same process still blocks. The close lock is a DEDICATED sidecar
# (`plan-close.lock`) rather than the plan-state lock, because `flock` is
# per-open-file-description: re-acquiring the plan-state lock from this same
# process inside plan_op_begin / plan_state_transition would deadlock against
# our own hold. The lock is released only after the receipt and the marker are
# durably written.
#
# THE MARKER IS HEAD-BOUND AND ATOMIC: written via mktemp + `mv` (one rename,
# never a partially-visible file) and carrying the merge commit (or the
# unchanged target head, for an abort), the candidate and the attempt — so a
# marker left over from an earlier, no-longer-valid state is detectable rather
# than merely present. On resume the command REVALIDATES everything rather than
# trusting an existing marker: an existing `plan-close-complete` whose
# preconditions no longer hold is reported as `close_marker_invalid`, exit 1.
#
# Usage:
#   aid-plan-fsm.sh plan-close <plan_id> [--project-root <path>] [--op-id <id>]
# =============================================================================

# _pfsm_close_lock_path <plan_id> — the close transaction's OWN sidecar.
_pfsm_close_lock_path() {
  printf '%s/plan-close.lock' "$(dirname "$(plan_state_path "$1")")"
}

# _pfsm_close_marker_path <plan_id>
_pfsm_close_marker_path() {
  printf '%s/plan-close-complete' "$(dirname "$(plan_state_path "$1")")"
}

# _pfsm_lock_held <path> — 0 iff a non-blocking flock acquire FAILS, i.e. the
# advisory lock is still held by a live open file description. Existence of the
# sidecar is deliberately NOT the signal (flock releases on descriptor close,
# not on unlink, so the sidecars persist by design).
_pfsm_lock_held() {
  local p="$1" fd
  command -v flock >/dev/null 2>&1 || return 1
  [[ -e "$p" ]] || return 1
  exec {fd}<>"$p" 2>/dev/null || return 1
  if flock -n "$fd" 2>/dev/null; then
    flock -u "$fd" 2>/dev/null || true
    eval "exec ${fd}>&-" 2>/dev/null || true
    return 1
  fi
  eval "exec ${fd}>&-" 2>/dev/null || true
  return 0
}

# _pfsm_close_lock_contended <plan_id> <excluded_path>... — echoes the first
# RELEVANT sidecar that is still HELD, skipping the excluded canonical paths.
# Returns 1 when one is contended, 0 when none are. Extracted as its own
# function so the owned-lock exception is directly testable: the path-scoped
# nature of the exclusion (case c: a different lock held by the SAME process
# still blocks) cannot be exercised through a subprocess.
_pfsm_close_lock_contended() {
  local plan_id="$1"; shift
  local -a excl=("$@")
  local dir; dir="$(dirname "$(plan_state_path "$plan_id")")"
  [[ -d "$dir" ]] || return 0
  local lp e skip canon
  while IFS= read -r lp; do
    [[ -n "$lp" ]] || continue
    canon="$(readlink -f -- "$lp" 2>/dev/null || printf '%s' "$lp")"
    skip=0
    for e in ${excl[@]+"${excl[@]}"}; do
      [[ "$canon" == "$(readlink -f -- "$e" 2>/dev/null || printf '%s' "$e")" ]] && skip=1
    done
    [[ "$skip" -eq 1 ]] && continue
    if _pfsm_lock_held "$lp"; then
      printf '%s (pid recorded in the sidecar: %s)' "$lp" "$(tr -d '\n' < "$lp" 2>/dev/null || echo unknown)"
      return 1
    fi
  done < <(find "$dir" -maxdepth 1 -name '*.lock' 2>/dev/null | sort)
  return 0
}

cmd_plan_close() {
  local plan_id="" project_root_opt="" op_id_opt="" skip_delivery_report=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)
        _pfsm_require_optval "plan-close" "$1" "$#" || exit 2
        project_root_opt="$2"; shift 2 ;;
      --op-id)
        _pfsm_require_optval "plan-close" "$1" "$#" || exit 2
        op_id_opt="$2"; shift 2 ;;
      # CP2 M5: forwarded by aid-fsm.sh when execution.yaml sets reporter.enabled:false.
      # It relaxes the delivery-report EXISTENCE requirement only; every other
      # check still runs, exactly as the legacy path already treats this toggle.
      --skip-delivery-report) skip_delivery_report=1; shift ;;
      --*) echo "ERROR: plan-close: unknown flag: $1" >&2; exit 2 ;;
      *)
        if [[ -z "$plan_id" ]]; then plan_id="$1"
        else echo "ERROR: plan-close: unexpected argument: $1" >&2; exit 2; fi
        shift ;;
    esac
  done

  if [[ -z "$plan_id" ]]; then
    echo "Usage: aid-plan-fsm.sh plan-close <plan_id> [--project-root <path>] [--op-id <id>] [--skip-delivery-report]" >&2
    exit 2
  fi
  if ! _pfsm_validate_plan_id "$plan_id"; then
    echo "ERROR: plan-close: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')" >&2
    exit 2
  fi
  command -v jq >/dev/null 2>&1 || {
    echo "PRECONDITION FAIL: plan-close requires jq." >&2; exit 1; }

  local root; root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$root"

  if [[ ! -f "$(plan_manifest_path "$plan_id")" ]]; then
    echo "PRECONDITION FAIL: plan-close: no plan-boundary-manifest for ${plan_id} — there is nothing to close." >&2
    exit 1
  fi

  local marker; marker="$(_pfsm_close_marker_path "$plan_id")"
  local cur_state=""
  cur_state="$(plan_state_get "$plan_id" "plan_state")" || cur_state=""

  local close_mode="merge"
  case "$cur_state" in
    PLAN_MERGING) close_mode="merge" ;;
    ABORTED)      close_mode="abort" ;;
    CLOSED)
      if [[ -f "$marker" ]]; then
        echo "ALREADY CLOSED: ${plan_id} is CLOSED and ${marker} is present — plan-close is a no-op." >&2
        exit 0
      fi
      close_mode="merge" ;;
    *)
      echo "PRECONDITION FAIL: plan-close: ${plan_id} is in state '${cur_state:-<none>}' — close runs out of PLAN_MERGING (after the merge) or ABORTED (a recorded abort). No marker was written." >&2
      exit 1
      ;;
  esac

  local target_branch candidate run_id run_dir_rel
  target_branch="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch')" || target_branch=""
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  run_id="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || run_id=""
  run_dir_rel="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_evidence_dir')" || run_dir_rel=""

  # ── 1. the close lock ─────────────────────────────────────────────────────
  local close_lock; close_lock="$(_pfsm_close_lock_path "$plan_id")"
  if ! aid_lock_acquire "$close_lock" 10; then
    echo "PRECONDITION FAIL: plan-close: another close transaction holds ${close_lock} — nothing was written." >&2
    exit 1
  fi
  local close_fd="$AID_LOCK_FD"
  _pfsm_close_release() { [[ -n "${close_fd:-}" ]] && aid_lock_release "$close_fd" >/dev/null 2>&1; close_fd=""; return 0; }

  # ── 2. every precondition, in one place, with the owned lock excluded ─────
  # The operation key is derived HERE rather than at step 3 because the check's
  # "no unfinished operation record" guard must exclude exactly THIS transaction
  # and nothing else (CP2 M2) — it cannot do that without being told which one.
  local attempt="${run_id##*-final-}"
  [[ "$attempt" =~ ^[0-9]+$ ]] || attempt=0
  local op_id="${op_id_opt:-$(plan_op_key "plan-close" "$plan_id" "-" "$attempt" "$plan_id")}"

  local ccrc=0 ccout=""
  local -a _cc_args=("$plan_id" --project-root "$root" --plan-branch
                     --close-mode "$close_mode" --exclude-lock "$close_lock"
                     --close-op-id "$op_id")
  [[ "$skip_delivery_report" -eq 1 ]] && _cc_args+=(--skip-delivery-report)
  ccout="$(bash "${SCRIPT_DIR}/aid-plan-close-check.sh" "${_cc_args[@]}" 2>&1)" || ccrc=$?
  if [[ "$ccrc" -ne 0 ]]; then
    _pfsm_close_release
    if [[ -f "$marker" ]]; then
      echo "close_marker_invalid: ${plan_id} carries a plan-close-complete marker whose preconditions NO LONGER HOLD — the marker is not trusted and close is refused. Resolve the failures below, then re-run plan-close." >&2
    else
      echo "PRECONDITION FAIL: plan-close: aid-plan-close-check.sh reported a blocking failure for ${plan_id} — NO marker was written and nothing was committed." >&2
    fi
    printf '%s\n' "$ccout" >&2
    exit 1
  fi

  # ── 3. intent (op_id was derived above, for the check's exclusion) ────────
  local phase="none" prc=0
  phase="$(plan_op_reconcile "$plan_id" "$op_id")" || prc=$?
  if [[ "$phase" != "git_applied" && "$phase" != "state_committed" ]]; then
    local brc=0
    plan_op_begin "$plan_id" "$op_id" "plan-close" "$plan_id" "$candidate" || brc=$?
    _pfsm_crash_seam intent
    if [[ "$brc" -ne 0 ]]; then
      _pfsm_close_release
      echo "PRECONDITION FAIL: plan-close: could not record the operation intent for ${plan_id} (rc=${brc}) — nothing was committed." >&2
      exit 1
    fi
  fi

  # ── 4. git_applied: the durable closure proof ─────────────────────────────
  local target_head="" applied_sha="" lifecycle_note=""
  target_head="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null)" || target_head=""
  if [[ -z "$target_head" ]]; then
    _pfsm_close_release
    echo "PRECONDITION FAIL: plan-close: the target branch ${target_branch} does not resolve — no receipt was written." >&2
    exit 1
  fi
  local lc_manifest="${root}/.aid-lifecycle/manifests/${plan_id}.yaml"

  if [[ "$close_mode" == "merge" ]]; then
    if [[ ! -f "$lc_manifest" ]]; then
      # CP3 (2026-07-26): keyed on the FILE rather than the MODE, this was an
      # escape hatch after all — deleting the tracked manifest turned a
      # plan-branch plan's MANDATORY receipt into an optional one and closed the
      # plan with no durable proof. This command only ever closes plan-branch
      # plans, so the absence is a blocking defect, not a legacy shape.
      _pfsm_close_release
      echo "PRECONDITION FAIL: plan-close: ${plan_id} has no .aid-lifecycle manifest at ${lc_manifest}, but the receipt is MANDATORY for a plan-branch close — refusing to declare the plan closed with no durable proof. NO marker was written and ${plan_id} stays ${cur_state}." >&2
      exit 1
    else
      local lrc=0 lout=""
      lout="$(aid_lifecycle_plan_close "$plan_id" "$root" "$target_head" 2>&1)" || lrc=$?
      if [[ "$lrc" -ne 0 ]]; then
        _pfsm_close_release
        echo "PRECONDITION FAIL: plan-close: the lifecycle receipt for ${plan_id} was NOT committed (rc=${lrc}) — for a plan_branch plan the receipt is MANDATORY, not best-effort, so NO close marker was written and ${plan_id} stays ${cur_state}. Detail: ${lout}" >&2
        exit 1
      fi
      applied_sha="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null)" || applied_sha="$target_head"
      lifecycle_note="receipt_committed"
    fi
  else
    # ── The abort close ────────────────────────────────────────────────────
    # An aborted plan writes NO lifecycle receipt: aid_lifecycle_plan_close
    # refuses while any required EPIC is undelivered, which is ALWAYS true
    # before a merge, so demanding one here would make an abort unclosable.
    # The durable proof is an abort record in the attempt's run directory plus
    # `status: aborted` on the tracked lifecycle manifest.
    local reason; reason="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.terminal_reason')" || reason=""
    local abort_rec="${root}/${run_dir_rel}/plan-close-abort.json"
    mkdir -p "$(dirname "$abort_rec")" 2>/dev/null || true
    if ! jq -n --arg p "$plan_id" --arg r "${reason:-unrecorded}" --arg c "$candidate" \
              --arg run "$run_id" --arg tb "$target_branch" --arg th "$target_head" \
              --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         '{plan_id:$p, result:"aborted", terminal_reason:$r, abandoned_candidate_sha:$c,
           plan_final_run_id:$run, target_branch:$tb, target_head_unchanged:$th, recorded_at:$at}' \
         > "${abort_rec}.tmp" 2>/dev/null; then
      rm -f "${abort_rec}.tmp" 2>/dev/null || true
      _pfsm_close_release
      echo "PRECONDITION FAIL: plan-close: could not write the abort record at ${abort_rec} — no marker was written." >&2
      exit 1
    fi
    mv -f "${abort_rec}.tmp" "$abort_rec"

    if [[ -f "$lc_manifest" ]]; then
      local mrc=0
      # Plan-mode plumbing, exactly like the receipt: the target branch may be
      # checked out in another worktree, and an abort never moves it.
      aid_lc_plan_mode_begin "" "" "$target_head"
      ( cd "$root" && yq -i '.status = "aborted"' ".aid-lifecycle/manifests/${plan_id}.yaml" ) || mrc=$?
      if [[ "$mrc" -eq 0 ]]; then
        aid_lifecycle_validate_artifact "$lc_manifest" "plan-lifecycle-manifest.schema.json" >/dev/null 2>&1 || mrc=1
      fi
      if [[ "$mrc" -eq 0 ]]; then
        _aid_lc_isolated_commit "$root" "lifecycle: ${plan_id} aborted" ".aid-lifecycle/manifests/${plan_id}.yaml" || mrc=$?
      fi
      aid_lc_plan_mode_end
      if [[ "$mrc" -ne 0 ]]; then
        git -C "$root" checkout -q HEAD -- ".aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null || true
        _pfsm_close_release
        echo "PRECONDITION FAIL: plan-close: could not mark the lifecycle manifest for ${plan_id} as aborted (rc=${mrc}) — the tracked manifest is restored and NO close marker was written." >&2
        exit 1
      fi
      lifecycle_note="manifest_aborted"
    else
      lifecycle_note="lifecycle_manifest_absent"
    fi
    applied_sha="$target_head"
  fi

  local grc=0
  plan_op_mark_git_applied "$plan_id" "$op_id" "$applied_sha" || grc=$?
  _pfsm_crash_seam git_applied
  [[ "$grc" -ne 0 ]] && echo "WARN: plan-close: the durable closure proof for ${plan_id} IS committed, but the git_applied record could not be written (rc=${grc}) — a resumed run re-verifies from the artifacts themselves." >&2

  # ── 5. state_committed: the ONE atomic, head-bound marker ────────────────
  local merge_commit=""
  merge_commit="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_merge.merge_commit')" || merge_commit=""
  [[ "$merge_commit" == "null" || "$merge_commit" == "not_found" ]] && merge_commit=""
  mkdir -p "$(dirname "$marker")" 2>/dev/null || true
  if ! printf 'plan_id=%s\nresult=%s\nplan_final_run_id=%s\ncandidate_sha=%s\ntarget_branch=%s\ntarget_head=%s\nmerge_commit=%s\nlifecycle=%s\nclosed_at=%s\n' \
        "$plan_id" "$close_mode" "$run_id" "$candidate" "$target_branch" "$applied_sha" \
        "${merge_commit:-none}" "$lifecycle_note" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        > "${marker}.tmp" 2>/dev/null; then
    rm -f "${marker}.tmp" 2>/dev/null || true
    _pfsm_close_release
    echo "PRECONDITION FAIL: plan-close: the closure proof for ${plan_id} is committed, but the close marker could not be written. Re-run plan-close — it revalidates and converges." >&2
    exit 1
  fi
  mv -f "${marker}.tmp" "$marker"

  if [[ "$close_mode" == "merge" ]]; then
    if ! _pfsm_plan_state_set "$plan_id" "CLOSED"; then
      _pfsm_close_release
      echo "PRECONDITION FAIL: plan-close: the receipt is committed and ${marker} is written, but ${plan_id} could not be moved to CLOSED. Reconcile with 'aid-plan-fsm.sh plan-state ${plan_id}'." >&2
      exit 1
    fi
    plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_state = "CLOSED"' >/dev/null 2>&1 || true
  fi

  local crc=0
  plan_op_commit "$plan_id" "$op_id" || crc=$?
  [[ "$crc" -ne 0 ]] && echo "WARN: plan-close: could not append the state_committed record for ${op_id} (rc=${crc})." >&2

  _pfsm_close_release

  echo "$marker"
  if [[ "$close_mode" == "merge" ]]; then
    echo "CLOSED: ${plan_id} is closed (${lifecycle_note}); the merge ${merge_commit:-<none>} is published on ${target_branch} and the close marker is bound to ${applied_sha}." >&2
  else
    echo "CLOSED (ABORTED): ${plan_id} closed by abort (${lifecycle_note}); ${target_branch} is unchanged at ${applied_sha}, the abandoned candidate was ${candidate}, and the abort record is in ${run_dir_rel}/." >&2
  fi
  return 0
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
  # F3 (2026-07-27, found while closing the P067 dogfood): report the
  # AUTHORITATIVE state, not the runtime manifest's mirror of it.
  #
  # The mirror is maintained by some writers and not others — plan_state_transition
  # does not touch it — so it drifts, and it drifted silently: after P067's abort
  # the command printed "P067 is now ABORTED" and the very next `plan-state`
  # answered AWAITING_PM, while the state file said ABORTED and a fixture that
  # had transitioned through plan_state_transition reported PLAN_GATES. Patching
  # one writer would have left the others; the guarantee belongs at the reader.
  # The mirror is still reported when the state file cannot be read, so a
  # workspace with only a manifest degrades rather than going blank.
  local _ps_auth=""
  _ps_auth="$(plan_state_get "$plan_id" "plan_state" 2>/dev/null || true)"
  [[ "$_ps_auth" == "null" || "$_ps_auth" == "not_found" ]] && _ps_auth=""
  if [[ -n "$_ps_auth" ]]; then
    jq -c --arg s "$_ps_auth" '{plan_state: $s, mode: .plan_boundary_manifest.mode, candidate_sha: .plan_boundary_manifest.candidate_sha, plan_final_run_id: .plan_boundary_manifest.plan_final_run_id}' "$path"
  else
    jq -c '{plan_state: .plan_boundary_manifest.plan_state, mode: .plan_boundary_manifest.mode, candidate_sha: .plan_boundary_manifest.candidate_sha, plan_final_run_id: .plan_boundary_manifest.plan_final_run_id}' "$path"
  fi
  exit 0
}

# ---------------------------------------------------------------------------
# _pfsm_plan_state_attest <plan_id> <project_root> <ref> <reason> <epic_id>
#
# Promotes ONE epic_runs[] entry from lineage:unproven to lineage:proven.
# THE ONLY code path in this file (or anywhere else in the manifest library)
# that ever performs that flip. The only two sources of lineage:proven in the
# whole system are (1) a normal epic-start, which passes lineage=proven
# EXPLICITLY to plan_manifest_add_epic (IMP-265: the default is now the
# fail-closed "unproven") because it observed the branch's origin at the
# moment it created it, and (2) this explicit operator attestation, which
# carries a reason and an op-log audit trail AND (IMP-267) re-derives the
# ancestry fields from real Git before promoting. --repair can only ever
# write unproven (see _pfsm_plan_state_repair) and never clears it. Guarded by
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

  # ── IMP-267: RE-DERIVE ancestry from real Git before attesting ───────────
  # The stored epic_merge_commit / epic_base_commit may have been reconstructed
  # by --repair and can be wrong (e.g. a misattributed merge). Attestation is
  # the point at which an entry becomes authoritative (lineage:proven), so it
  # MUST NOT carry ancestry it cannot prove from Git. We re-derive both fields
  # with the SAME primitives epic-merge-to-plan uses (git rev-parse /
  # merge-base / --is-ancestor) and FAIL CLOSED when the ancestry cannot be
  # proven — the operator display below is a courtesy, the mechanical
  # derivation is the gate.
  local plan_branch="plan/${plan_id}" task_branch="task/${epic_id}/main"
  local stored_mc=""; stored_mc="$(jq -r '.epic_merge_commit // empty' <<<"$entry_json" 2>/dev/null)"
  local derived_base="" derived_mc=""
  if [[ -n "$stored_mc" ]]; then
    # A stored merge commit must be a real two-parent merge, reachable from the
    # plan branch, and (if the task branch still exists) contain it — otherwise
    # it is not a merge we can vouch for.
    if ! git -C "$project_root" rev-parse -q --verify "${stored_mc}^2" >/dev/null 2>&1 \
       || ! _pfsm_is_ancestor "$project_root" "$stored_mc" "$plan_branch"; then
      echo "PRECONDITION FAIL: ${epic_id}'s recorded epic_merge_commit '${stored_mc}' cannot be proven from Git (not a two-parent merge reachable from ${plan_branch}) — refusing to attest ancestry that repair may have left wrong." >&2
      return 1
    fi
    if git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1 \
       && ! _pfsm_is_ancestor "$project_root" "refs/heads/${task_branch}" "$stored_mc"; then
      echo "PRECONDITION FAIL: ${epic_id}'s recorded epic_merge_commit '${stored_mc}' does not contain ${task_branch} — refusing to attest a misattributed merge." >&2
      return 1
    fi
    derived_mc="$stored_mc"
    derived_base="$(git -C "$project_root" merge-base "${stored_mc}^1" "${stored_mc}^2" 2>/dev/null)" || derived_base=""
  else
    # No merge recorded: the base is the merge-base of the task branch and the
    # plan branch, which requires the task branch to still exist.
    if ! git -C "$project_root" rev-parse --verify --quiet "refs/heads/${task_branch}" >/dev/null 2>&1; then
      echo "PRECONDITION FAIL: cannot re-derive ${epic_id}'s ancestry — no epic_merge_commit recorded and ${task_branch} no longer exists; refusing to attest on unprovable ancestry." >&2
      return 1
    fi
    derived_base="$(git -C "$project_root" merge-base "$task_branch" "$plan_branch" 2>/dev/null)" || derived_base=""
  fi
  if ! [[ "$derived_base" =~ ^[0-9a-f]{40}$ ]]; then
    echo "PRECONDITION FAIL: could not re-derive a valid epic_base_commit for ${epic_id} from Git (got '${derived_base:-<empty>}') — failing closed rather than attesting a stored value." >&2
    return 1
  fi
  # Operator display of the EXACT ancestry being attested (courtesy, not gate).
  echo "attesting ${epic_id}: source_ref=${ref} epic_base_commit=${derived_base} epic_merge_commit=${derived_mc:-<none>}" >&2

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
  local esc_ref esc_reason esc_epic esc_now now esc_base esc_mc
  esc_ref="$(jq -Rn --arg s "$ref" '$s')"
  esc_reason="$(jq -Rn --arg s "$reason" '$s')"
  esc_epic="$(jq -Rn --arg s "$epic_id" '$s')"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  esc_now="$(jq -Rn --arg s "$now" '$s')"
  # IMP-267: persist the RE-DERIVED ancestry (never the stored value). A null
  # merge commit is written as the JSON literal `null` (invariant: a non-null
  # epic_merge_commit requires status merged_to_plan, which the stored value
  # already satisfied whenever it was non-null).
  esc_base="$(jq -Rn --arg s "$derived_base" '$s')"
  if [[ -n "$derived_mc" ]]; then esc_mc="$(jq -Rn --arg s "$derived_mc" '$s')"; else esc_mc="null"; fi

  local filter="(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == ${esc_epic} then (.epic_source_ref = ${esc_ref} | .lineage = \"proven\" | .epic_base_commit = ${esc_base} | .epic_merge_commit = ${esc_mc} | .attestation_reason = ${esc_reason} | .attested_at = ${esc_now}) else . end])"

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
      PLAN_GATES|PLAN_REVIEW|PLAN_FIX|AWAITING_PM|PLAN_MERGING|CLOSED|ABORTED|ROLLED_BACK)
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

  # ── IMP-265b: healthy repair is a NON-DESTRUCTIVE no-op ──────────────────
  # Repair exists to reconstruct a runtime tree that was pruned/checked-out
  # fresh — NOT to overwrite an intact one. A manifest that already passes the
  # full three-layer invariant validator (and a plan-state file that already
  # exists) is not damaged, so repair must round-trip it BYTE-FOR-BYTE: it must
  # never degrade a healthy `proven` entry to `unproven`, and never discard
  # valid attestation metadata (epic_source_ref / attestation_reason /
  # attested_at). We decide this BEFORE recording any repair intent — a no-op
  # is not an operation. When only PART of the tree is damaged (e.g. the
  # manifest is healthy but plan-state.yaml was pruned) we still reconstruct
  # the missing part below, but leave the healthy manifest untouched (see the
  # `manifest_healthy` guard around the epic-bookkeeping rebuild).
  local manifest_healthy=0
  if [[ -f "$(plan_manifest_path "$plan_id")" ]] \
     && plan_manifest_validate "$plan_id" >/dev/null 2>&1; then
    manifest_healthy=1
  fi
  if [[ "$manifest_healthy" -eq 1 && -f "$(plan_state_path "$plan_id")" ]]; then
    # Fully healthy — reconstruct nothing, mint nothing, record nothing. Emit
    # the same summary shape as a real repair for a stable caller contract.
    jq -c '{plan_state: .plan_boundary_manifest.plan_state, mode: .plan_boundary_manifest.mode, epics: .plan_boundary_manifest.epics, epic_runs: .plan_boundary_manifest.epic_runs}' "$(plan_manifest_path "$plan_id")"
    return 0
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

  # IMP-265b: only a DAMAGED manifest is rebuilt from Git. A healthy manifest
  # (validated above) is preserved as-is — repair never resets its
  # epic_runs[]/epics bookkeeping and never re-derives (and thus never
  # downgrades) an entry it did not have to reconstruct. The rebuild below is
  # deliberately fail-CLOSED (IMP-258): every per-entry manifest write is
  # checked, and a write that could not durably land aborts the whole repair
  # with a precise reason and a non-zero exit — repair must NEVER report
  # success over a partially-written manifest.
  if [[ "$manifest_healthy" -eq 0 ]]; then
    # A damaged manifest is fully recomputed from Git — never layered
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
          # IMP-258: propagate — a swallowed failure here would leave the merged
          # entry silently absent while repair still claimed success.
          if ! _pfsm_repair_add_unproven "$plan_id" "$eid" "$task_branch" "$ebc" "$plan_branch"; then
            echo "PRECONDITION FAIL: repair could not durably write the merged epic_runs[] entry for ${eid} in ${plan_id}'s manifest — refusing to report success over a partially-written manifest." >&2
            return 1
          fi
          if ! plan_manifest_set_epic_status "$plan_id" "$eid" "merged_to_plan" "$merge_commit" >/dev/null; then
            echo "PRECONDITION FAIL: repair wrote the ${eid} entry but could not durably record its merged_to_plan status in ${plan_id}'s manifest — refusing to report success over a partially-written manifest." >&2
            return 1
          fi
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
        # IMP-258: propagate the live-branch entry write failure identically.
        if ! _pfsm_repair_add_unproven "$plan_id" "$eid" "$task_branch" "$ubc" ""; then
          echo "PRECONDITION FAIL: repair could not durably write the live-branch epic_runs[] entry for ${eid} in ${plan_id}'s manifest — refusing to report success over a partially-written manifest." >&2
          return 1
        fi
      fi
    done
  fi

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


# ---------------------------------------------------------------------------
# _pfsm_crash_seam <phase>
# P068 Step 8 — the ONE test seam for the resilience matrix.
#
# Every transactional command in this plan is specified as
# `intent -> git_applied -> state_committed`. That specification is only worth
# something if a crash at each boundary is actually exercised, and a crash
# cannot be exercised honestly by mocking: the process has to die after the
# record lands and before the next one does. When AID_PLAN_FSM_CRASH_AFTER
# names a phase, the command exits 99 the instant that phase is recorded.
#
# It is a SEAM, not a feature: it is inert unless the variable is set, it can
# only ever cause an exit (never a state change of its own), and 99 is outside
# every meaningful exit code this script uses, so a test cannot mistake an
# induced crash for a real failure.
# ---------------------------------------------------------------------------
_pfsm_crash_seam() {
  local phase="$1"
  [[ -n "${AID_PLAN_FSM_CRASH_AFTER:-}" ]] || return 0
  [[ "${AID_PLAN_FSM_CRASH_AFTER}" == "$phase" ]] || return 0
  echo "CRASH SEAM: AID_PLAN_FSM_CRASH_AFTER=${phase} — exiting 99 immediately after the '${phase}' record. This is a test seam; nothing further was written." >&2
  exit 99
}

# ═══════════════════════════════════════════════════════════════════════════
# plan-finalize --stage inputs — the PRODUCER for the three C4 inputs.
#
# Closes `plan_finalize_c4_reader_gap`. Until this existed, the review and c4
# stages VALIDATED review-profile.json, delivery-gate.json and
# acceptance-evidence.json while nothing in the plan produced them: a reader
# with no writer, which meant the plan-final boundary could not complete
# end-to-end and the gap had to be recorded in the enforcement registry rather
# than closed.
#
# Production is real, not fabrication. The review profile comes from the
# existing `aid-prefilter.sh profile` producer run over the WHOLE plan range.
# The two aggregates are built from each contributing EPIC's own evidence pack:
# an EPIC that has an artifact contributes its content hash, and one that does
# not is recorded as `absent` — visible in the artifact rather than silently
# dropped, because "no EPIC produced this" is a fact the PM should see, not one
# the aggregate should hide.
# ═══════════════════════════════════════════════════════════════════════════
_pfsm_finalize_inputs() {
  local plan_id="$1" root="$2" run_dir_abs="$3" candidate="$4" base_commit="$5" run_id="$6"

  mkdir -p "$run_dir_abs" 2>/dev/null || {
    echo "PRECONDITION FAIL: plan-finalize --stage inputs: cannot create ${run_dir_abs}." >&2; return 1; }

  # CP2 (2026-07-27): this stage OVERWRITES the three artifacts. Once
  # `--stage review` has recorded their sha256 in the manifest, re-running it
  # would change files whose hashes are already bound, and plan-close would then
  # report "a required review output was altered" — a true statement with a
  # misleading diagnosis, since nobody tampered with anything: a producer was
  # simply run twice. A producer that can silently invalidate a completed review
  # is worse than one that refuses, so it refuses.
  #
  # The exception is a RE-FROZEN candidate: the recorded review then describes a
  # candidate that no longer exists and is already void, so producing fresh
  # inputs for the new one is exactly right.
  local _rec_cand=""
  _rec_cand="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_review.candidate_sha')" 2>/dev/null || _rec_cand=""
  [[ "$_rec_cand" == "null" || "$_rec_cand" == "not_found" ]] && _rec_cand=""
  if [[ -n "$_rec_cand" && "$_rec_cand" == "$candidate" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage inputs: ${plan_id} already has a RECORDED plan-final review bound to candidate ${candidate:0:8}, whose outputs are hash-bound in the manifest. Re-producing them now would alter files the review already attested to, and close would report them as altered. Nothing was written. If the candidate genuinely changed, re-freeze first — the recorded review is void from that moment and this stage will run." >&2
    return 1
  fi

  local project_id; project_id="$(basename "$root")"
  local plan_file; plan_file="$(aid_lifecycle_plan_file "$plan_id" "$root" || true)"

  # ── 1. review-profile.json, over plan_base_commit..candidate_sha ─────────
  # The range matters: the review stage asserts revision.base_sha equals the
  # plan base, because a profile derived over one EPIC would arm the C3 gate for
  # a fraction of what is about to be released.
  local rp="${run_dir_abs}/review-profile.json" rprc=0
  if [[ -n "$plan_file" && -x "${SCRIPT_DIR}/aid-prefilter.sh" ]]; then
    bash "${SCRIPT_DIR}/aid-prefilter.sh" profile "$plan_file" "$run_dir_abs" \
      --range "${base_commit}..${candidate}" --out "$rp" >/dev/null 2>&1 || rprc=$?
  else
    rprc=127
  fi
  if [[ "$rprc" -ne 0 || ! -s "$rp" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage inputs: the review profile producer did not emit ${rp} (rc=${rprc}). The C3 gate cannot be armed for the plan-level run without it, and a hand-written profile would be a claim rather than a derivation." >&2
    return 1
  fi
  # The producer is EPIC-shaped by origin; the plan-level run is bound to the
  # plan, so the identity is corrected here rather than left ambiguous.
  local rptmp; rptmp="$(mktemp)"
  jq --arg p "$plan_id" --arg r "$run_id" --arg b "$base_commit" --arg h "$candidate" \
     '.identity = ((.identity // {}) + {epic_id: null, plan_id: $p, run_id: $r})
      | .revision = ((.revision // {}) + {base_sha: $b, head_sha: $h})' \
     "$rp" > "$rptmp" 2>/dev/null && mv -f "$rptmp" "$rp" || { rm -f "$rptmp"; 
    echo "PRECONDITION FAIL: plan-finalize --stage inputs: could not bind ${rp} to the plan." >&2; return 1; }

  # ── 2 + 3. the two aggregates, built from the contributing EPICs ─────────
  local contributing
  contributing="$(plan_manifest_get "$plan_id" '[.plan_boundary_manifest.epic_runs[] | select(.status == "merged_to_plan") | .epic_id] | sort | join(" ")' 2>/dev/null)" || contributing=""
  [[ "$contributing" == "not_found" || "$contributing" == "null" ]] && contributing=""
  if [[ -z "$contributing" ]]; then
    echo "PRECONDITION FAIL: plan-finalize --stage inputs: ${plan_id} records no EPIC in status merged_to_plan, so there is nothing to aggregate. An aggregate over zero sources would assert a delivery nobody made." >&2
    return 1
  fi

  local agg base_name key
  for agg in delivery-gate acceptance-evidence; do
    case "$agg" in
      delivery-gate)      key="delivery_gate" ;;
      acceptance-evidence) key="acceptance_evidence" ;;
    esac
    local sources_json="[]" e edir efile ehash estatus
    for e in $contributing; do
      edir="$(plan_manifest_get "$plan_id" "[.plan_boundary_manifest.epic_runs[] | select(.epic_id == \"${e}\") | .evidence_dir][0] // \"\"" 2>/dev/null)" || edir=""
      [[ "$edir" == "not_found" || "$edir" == "null" ]] && edir=""
      efile=""; ehash=""; estatus="absent"
      if [[ -n "$edir" && -s "${root}/${edir}/${agg}.json" ]]; then
        efile="${edir}/${agg}.json"
        ehash="sha256:$(sha256sum "${root}/${efile}" | awk '{print $1}')"
        estatus="aggregated"
      fi
      sources_json="$(jq -c --arg e "$e" --arg d "${edir}" --arg f "$efile" \
        --arg h "$ehash" --arg st "$estatus" \
        '. + [{epic_id: $e, evidence_dir: $d, artifact: $f, sha256: $h, status: $st}]' \
        <<< "$sources_json")"
    done

    local body
    if [[ "$agg" == "delivery-gate" ]]; then
      # DOGFOOD FINDING (P075, 2026-07-27): the aggregate must carry the
      # enforcement interpretation. `aid-evidence-verify.sh --at-head` fails
      # `observe_blocking_interpretation` when `delivery_gate.summary.enforcement`
      # is absent, and that failure blocks C4 — so a delivery gate that does not
      # say HOW it is enforced is not a usable input, however complete it looks.
      # The value is read from the policy in force rather than hardcoded: writing
      # "observe" into an artifact while the project enforces "blocking" would be
      # the aggregate lying about its own weight.
      local _dg_enf=""
      local _dg_pol="${SCRIPT_DIR}/../defaults/policies/delivery-gate.yaml"
      [[ -f "${root}/.aid-o/config/policies/delivery-gate.yaml" ]] \
        && _dg_pol="${root}/.aid-o/config/policies/delivery-gate.yaml"
      [[ -f "$_dg_pol" ]] && _dg_enf="$(yq -r '.enforcement // ""' "$_dg_pol" 2>/dev/null || true)"
      case "$_dg_enf" in
        observe|dual_run|blocking) ;;
        *) _dg_enf="observe" ;;   # the conservative reading when the policy is silent
      esac
      # Under `observe` the gate must also record what it WOULD have blocked —
      # that is the entire content of an observing gate, and the evidence
      # verifier requires the boolean. The honest derivation for an aggregate:
      # it would block when it cannot show every contributing EPIC's gate,
      # because "I have no evidence for this EPIC" is not the same as "this EPIC
      # passed". Under `blocking` the same condition is what actually blocks.
      body="$(jq -nc --argjson s "$sources_json" --arg enf "$_dg_enf" \
        '{phase: "plan-final", profile: "plan_aggregate",
          summary: {enforcement: $enf,
                    would_block: ([$s[] | select(.status == "absent")] | length > 0)},
          checks: [], aggregated_from: ($s | length),
          aggregated_absent: ([$s[] | select(.status == "absent")] | length)}')"
    else
      body="$(jq -nc --argjson s "$sources_json" \
        '{criteria: [], aggregated_from: ($s | length),
          aggregated_absent: ([$s[] | select(.status == "absent")] | length)}')"
    fi

    local absent_n; absent_n="$(jq -r '[.[] | select(.status == "absent")] | length' <<< "$sources_json")"
    local verdict="aggregated"; [[ "$absent_n" -gt 0 ]] && verdict="aggregated_with_gaps"

    # The subject hash is the aggregate's identity as a REVIEW SUBJECT: it must
    # be reproducible from what was aggregated, not a random id. It is the
    # sha256 of the plan id, the candidate and the ordered source list, so two
    # runs over the same inputs produce the same hash and a changed source set
    # produces a different one. `aid-protocol-validate.sh` requires the
    # `sha256:<64 hex>` shape (exit 7) and rejects anything else.
    local subject_hash
    subject_hash="sha256:$(printf '%s\n%s\n%s' "$plan_id" "$candidate" \
      "$(jq -S -c '[.[] | {epic_id, sha256, status}]' <<< "$sources_json")" \
      | sha256sum | awk '{print $1}')"
    # verdict.kind is a closed enum (none|delivery_ready|release_ready). The
    # aggregate does not decide readiness — C4 does — so it is `none`, with the
    # aggregation outcome carried in a sibling field rather than smuggled into
    # the enum.
    jq -n --arg pid "$project_id" --arg p "$plan_id" --arg r "$run_id" \
          --arg h "$candidate" --arg b "$base_commit" --arg at "$agg" \
          --arg k "$key" --argjson body "$body" --argjson s "$sources_json" \
          --arg v "$verdict" --arg sh "$subject_hash" \
      '{schema_version: "aid-2.0", artifact_type: ($at | gsub("-"; "_")),
        producer: "aid-plan-fsm.sh@plan-finalize-inputs",
        created_at: (now | todate | sub("\\.[0-9]+Z$"; "Z")),
        control_protocol: "aid-2.0",
        identity: {project_id: $pid, epic_id: null, plan_id: $p, run_id: $r},
        subject: {plan_id: $p, candidate_sha: $h, subject_hash: $sh},
        revision: {base_sha: $b, head_sha: $h,
                   head_is_current: true, freshness: "current"},
        status: "pass", verdict: {kind: "none", aggregation: $v},
        provenance: {dispatch_mode: "deterministic",
                     generated_by_tool: "aid-plan-fsm.sh",
                     aggregated_at_boundary: "plan-final"},
        sources: $s}
       | .[$k] = $body' > "${run_dir_abs}/${agg}.json" || {
      echo "PRECONDITION FAIL: plan-finalize --stage inputs: could not write ${agg}.json." >&2
      return 1; }
  done

  echo "INPUTS PRODUCED: ${plan_id} — review-profile.json over ${base_commit:0:8}..${candidate:0:8}, and the plan-level delivery-gate.json + acceptance-evidence.json aggregated from: ${contributing}. Written to ${run_dir_abs}." >&2
  return 0
}


# ═══════════════════════════════════════════════════════════════════════════
# P068 Step 7 — in-flight inventory and the default mode flip
# ═══════════════════════════════════════════════════════════════════════════

# _pfsm_policy_path — the plan-boundary policy shipped with the plugin, or the
# project's own copy if it has one (a target project may opt out without
# patching the plugin, which is the entire reason this is a file and not a
# constant).
_pfsm_policy_path() {
  local root="${1:-.}"
  local local_copy="${root}/.aid-o/config/policies/plan-boundary-policy.yaml"
  [[ -f "$local_copy" ]] && { printf '%s' "$local_copy"; return 0; }
  printf '%s/../defaults/policies/plan-boundary-policy.yaml' "$SCRIPT_DIR"
}

# _pfsm_policy_get <key> [root] — one scalar from the policy, or empty. Never
# aborts under `set -e`; an unreadable policy yields empty and every caller
# treats that as "no opinion", falling back to the conservative legacy default.
_pfsm_policy_get() {
  local key="$1" root="${2:-.}" f v
  f="$(_pfsm_policy_path "$root")"
  [[ -f "$f" ]] || { printf ''; return 0; }
  v="$(yq -r ".${key} // \"\"" "$f" 2>/dev/null || true)"
  [[ "$v" == "null" ]] && v=""
  printf '%s' "$v"
}

# _pfsm_has_gate_profiles [root] — 0 iff the project's execution.yaml declares a
# gate_profiles table.
#
# THE GUARD ON THE FLIP. plan_branch mode's gates stage resolves against this
# table. P064 adds it to THIS repository's self-host execution.yaml, not to the
# defaults/execution.yaml that /aid-init distributes, so a consumer project that
# merely upgrades the plugin would flip to plan_branch and resolve its gates
# against nothing at all. Absence of the table is therefore not a detail — it is
# the difference between a mode that works and one that silently has no gates.
_pfsm_has_gate_profiles() {
  local root="${1:-.}"
  local ey="${root}/.aid-o/config/execution.yaml"
  [[ -f "$ey" ]] || return 1
  if command -v yq >/dev/null 2>&1; then
    local n; n="$(yq -r '.gate_profiles | length' "$ey" 2>/dev/null || echo 0)"
    [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] && return 0
    return 1
  fi
  grep -qE '^gate_profiles:' "$ey" 2>/dev/null
}

# _pfsm_default_mode [root] — the mode a NEW plan is created with.
# Prints "<mode>\t<reason>". The policy value is a CEILING, never a promise:
# plan_branch is granted only when the gate table exists, otherwise the caller
# gets legacy_epic_release_mode and the reason `plan_branch_unavailable:
# no_gate_profiles`, which is a logged fact rather than a silent downgrade.
_pfsm_default_mode() {
  local root="${1:-.}" want
  want="$(_pfsm_policy_get default_mode "$root")"
  [[ -z "$want" ]] && want="legacy_epic_release_mode"
  case "$want" in
    plan_branch)
      if _pfsm_has_gate_profiles "$root"; then
        printf 'plan_branch\tpolicy_default\n'
      else
        printf 'legacy_epic_release_mode\tplan_branch_unavailable: no_gate_profiles\n'
      fi
      ;;
    legacy_epic_release_mode)
      printf 'legacy_epic_release_mode\tpolicy_default\n'
      ;;
    *)
      # An unknown value in the policy is a configuration error, not a licence
      # to guess. Fail closed to the conservative mode and say why.
      printf 'legacy_epic_release_mode\tunknown_policy_default: %s\n' "$want"
      ;;
  esac
}

# _pfsm_inv_plan_ids [root] — every plan id with a plan file or a queue entry.
_pfsm_inv_plan_ids() {
  local root="${1:-.}" f id
  {
    for f in "${root}"/.aid-o/plans/P*.md; do
      [[ -e "$f" ]] || continue
      id="$(basename "$f")"; id="${id%%-*}"
      [[ "$id" =~ ^P[0-9]+$ ]] && printf '%s\n' "$id"
    done
    if [[ -f "${root}/.aid-o/config/queue.yaml" ]]; then
      grep -oE '"?P[0-9]{3}[^"/]*"?' "${root}/.aid-o/config/queue.yaml" 2>/dev/null \
        | grep -oE '^"?P[0-9]{3}' | tr -d '"' || true
    fi
  } | sort -u
}

# _pfsm_inv_epic_states <plan_id> [root] — "<total> <terminal> <nonterminal>"
# read from the queue, the ONE place EPIC status is script-written.
_pfsm_inv_epic_states() {
  local plan_id="$1" root="${2:-.}"
  local q="${root}/.aid-o/config/queue.yaml"
  local total=0 terminal=0 nonterminal=0
  if [[ -f "$q" ]] && command -v yq >/dev/null 2>&1; then
    local nnn="${plan_id#P}" line st
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      st="$line"
      total=$((total + 1))
      case "$st" in
        done|completed|merged|released_to_main|abandoned|superseded|cancelled) terminal=$((terminal + 1)) ;;
        *) nonterminal=$((nonterminal + 1)) ;;
      esac
    done < <(yq -r ".queue[]? | select(.epic_id | test(\"^E-${nnn}\")) | .status // \"\"" "$q" 2>/dev/null || true)
  fi
  printf '%s %s %s' "$total" "$terminal" "$nonterminal"
}

# _pfsm_inv_mode <plan_id> [root] — the plan's currently declared mode, read
# from the git-tracked lifecycle manifest (the authority), else the runtime
# plan-state file, else "none".
_pfsm_inv_mode() {
  local plan_id="$1" root="${2:-.}" m=""
  local lm="${root}/.aid-lifecycle/manifests/${plan_id}.yaml"
  if [[ -f "$lm" ]] && command -v yq >/dev/null 2>&1; then
    m="$(yq -r '.mode // ""' "$lm" 2>/dev/null || true)"
    [[ "$m" == "null" ]] && m=""
  fi
  if [[ -z "$m" ]]; then
    local ps="${root}/.aid-o/work/plan-state/${plan_id}/plan-state.yaml"
    if [[ -f "$ps" ]] && command -v yq >/dev/null 2>&1; then
      m="$(yq -r '.mode // ""' "$ps" 2>/dev/null || true)"
      [[ "$m" == "null" ]] && m=""
    fi
  fi
  printf '%s' "${m:-none}"
}

# ---------------------------------------------------------------------------
# aid-plan-fsm.sh inventory [--apply] [--plan <id>] [--project-root <path>]
#
# Roadmap D11 bounds this migration deliberately: no algorithm, no inference —
# an inventory and an explicit stamp. Listing is read-only. `--apply` writes
# `mode: legacy_epic_release_mode` into each plan's LIFECYCLE MANIFEST, the
# git-tracked authority; a legacy plan that has no schema-valid manifest is
# stamped in its runtime plan-state file instead and recorded
# `legacy-unverifiable`, because plan-lifecycle-manifest.schema.json is
# additionalProperties:false and requires four fields a legacy plan cannot
# supply. No invalid manifest is ever fabricated, no plan branch is created and
# no plan is migrated mid-run.
# ---------------------------------------------------------------------------
cmd_inventory() {
  local apply=0 only_plan="" project_root_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) apply=1; shift ;;
      --plan)
        _pfsm_require_optval "inventory" "$1" "$#" || exit 2
        only_plan="$2"; shift 2 ;;
      --project-root)
        _pfsm_require_optval "inventory" "$1" "$#" || exit 2
        project_root_opt="$2"; shift 2 ;;
      --*) echo "ERROR: inventory: unknown flag: $1" >&2; exit 2 ;;
      *) echo "ERROR: inventory: unexpected argument: $1" >&2; exit 2 ;;
    esac
  done

  local root; root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$root"

  if [[ -n "$only_plan" ]] && ! _pfsm_validate_plan_id "$only_plan"; then
    exit 2
  fi

  local -a ids=()
  local id
  while IFS= read -r id; do [[ -n "$id" ]] && ids+=("$id"); done < <(_pfsm_inv_plan_ids "$root")

  if [[ -n "$only_plan" ]]; then
    local found=0
    for id in ${ids[@]+"${ids[@]}"}; do [[ "$id" == "$only_plan" ]] && found=1; done
    if [[ "$found" -eq 0 ]]; then
      echo "ERROR: inventory: no plan file or queue entry matches ${only_plan} — refusing to invent one." >&2
      exit 1
    fi
    ids=("$only_plan")
  fi

  local dm_row dm dm_reason
  dm_row="$(_pfsm_default_mode "$root")"
  dm="${dm_row%%$'\t'*}"; dm_reason="${dm_row#*$'\t'}"; dm_reason="${dm_reason%$'\n'}"
  echo "default_mode for NEW plans: ${dm} (${dm_reason})"
  printf '%-8s %-28s %-7s %-9s %s\n' "PLAN" "MODE" "EPICS" "ACTIVE" "DISPOSITION"

  local rc=0 stamped=0
  for id in ${ids[@]+"${ids[@]}"}; do
    local counts total terminal nonterminal mode disposition
    counts="$(_pfsm_inv_epic_states "$id" "$root")"
    total="${counts%% *}"; terminal="$(echo "$counts" | awk '{print $2}')"
    nonterminal="$(echo "$counts" | awk '{print $3}')"
    mode="$(_pfsm_inv_mode "$id" "$root")"

    if [[ "$mode" != "none" && "$mode" != "plan_branch" && "$mode" != "legacy_epic_release_mode" ]]; then
      echo "ERROR: inventory: ${id} declares an unknown mode '${mode}' — refusing to operate on it. Nothing was mutated." >&2
      rc=1; continue
    fi

    if [[ "$mode" != "none" ]]; then
      disposition="already_stamped"
    elif [[ "$nonterminal" -gt 0 ]]; then
      disposition="active_unstamped"
    elif [[ "$total" -gt 0 ]]; then
      disposition="unclosed_legacy"
    else
      disposition="no_epics"
    fi

    if [[ "$apply" -eq 1 && "$mode" == "none" ]]; then
      # Existing plans are stamped LEGACY and never migrated: D11 is explicit
      # that this step inventories and stamps, it does not convert.
      local lm="${root}/.aid-lifecycle/manifests/${id}.yaml"
      if [[ -f "$lm" ]]; then
        # CP3: the stamp has to be COMMITTED. The lifecycle manifest is the
        # git-tracked authority precisely because a worktree file proves nothing
        # — _fsm_declared_plan_mode answers from the target branch's tree, so a
        # `yq -i` alone would leave every "stamped" plan still declaring nothing
        # where it counts. Same defect this EPIC already fixed once in the
        # auto-pipeline; it is not allowed to survive here.
        if ( cd "$root" && yq -i '.mode = "legacy_epic_release_mode"' ".aid-lifecycle/manifests/${id}.yaml" ) 2>/dev/null; then
          local _inv_crc=0
          if declare -F _aid_lc_isolated_commit >/dev/null 2>&1; then
            ( cd "$root" && _aid_lc_isolated_commit "." "lifecycle: stamp mode legacy_epic_release_mode for ${id}" \
                ".aid-lifecycle/manifests/${id}.yaml" >/dev/null 2>&1 ) || _inv_crc=$?
          else
            _inv_crc=127
          fi
          local _inv_read=""
          _inv_read="$(git -C "$root" show "$(aid_target_branch):.aid-lifecycle/manifests/${id}.yaml" 2>/dev/null | yq -r '.mode // ""' 2>/dev/null || true)"
          if [[ "$_inv_read" == "legacy_epic_release_mode" ]]; then
            disposition="stamped_legacy(manifest,committed)"; stamped=$((stamped + 1)); mode="legacy_epic_release_mode"
          else
            disposition="stamp_not_durable(rc=${_inv_crc})"
            echo "ERROR: inventory: ${id} was stamped in the worktree but the stamp is NOT readable from $(aid_target_branch)'s committed manifest (rc=${_inv_crc}) — an uncommitted mode declares nothing to any later reader. Commit .aid-lifecycle/manifests/${id}.yaml, or re-run on the target branch." >&2
            rc=1
          fi
        else
          echo "ERROR: inventory: could not stamp the lifecycle manifest for ${id} — nothing was written for this plan." >&2
          rc=1
        fi
      else
        local ps="${root}/.aid-o/work/plan-state/${id}/plan-state.yaml"
        if [[ -f "$ps" ]]; then
          if ( cd "$root" && yq -i '.mode = "legacy_epic_release_mode"' ".aid-o/work/plan-state/${id}/plan-state.yaml" ) 2>/dev/null; then
            disposition="stamped_legacy(legacy-unverifiable)"; stamped=$((stamped + 1)); mode="legacy_epic_release_mode"
          else
            echo "ERROR: inventory: could not stamp the runtime plan state for ${id}." >&2
            rc=1
          fi
        else
          disposition="unstampable(no manifest, no plan state)"
        fi
      fi
    fi

    printf '%-8s %-28s %-7s %-9s %s\n' "$id" "$mode" "$total" "$nonterminal" "$disposition"
  done

  if [[ "$apply" -eq 1 ]]; then
    echo "stamped ${stamped} plan(s) legacy_epic_release_mode (no plan was migrated, no branch was created)"
  else
    echo "(read-only: re-run with --apply to stamp unstamped plans legacy_epic_release_mode)"
  fi
  return "$rc"
}


# ═══════════════════════════════════════════════════════════════════════════
# plan-rollback — the sanctioned post-merge rollback close (P075 dogfood)
#
# A plan that merged and was then correctly reverted had no honest terminal
# state. `abort` refuses it, and rightly so — an aborted plan never merged, and
# the close check says exactly that. `CLOSED` would be worse: it asserts the
# delivery is on the target branch when it has been taken back off. So P075 sat
# in PLAN_MERGING forever, having done everything right.
#
# ROLLED_BACK is that missing state. It is not a softer CLOSED: it records the
# four SHAs that make the story checkable — the candidate that was approved, the
# target head it was approved against, the merge that published it, and the
# revert that took it back — and it VERIFIES them against Git rather than
# accepting them as claims. In particular it requires that the merge is STILL
# reachable: a rollback is a revert forward, never a rewrite, and a rollback
# record that cannot find its own merge is describing a history someone edited.
# ═══════════════════════════════════════════════════════════════════════════
cmd_plan_rollback() {
  local plan_id="" project_root_opt="" revert_commit="" reason="" op_id_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) _pfsm_require_optval "plan-rollback" "$1" "$#" || exit 2
                      project_root_opt="$2"; shift 2 ;;
      --revert-commit) _pfsm_require_optval "plan-rollback" "$1" "$#" || exit 2
                      revert_commit="$2"; shift 2 ;;
      --reason)       _pfsm_require_optval "plan-rollback" "$1" "$#" || exit 2
                      reason="$2"; shift 2 ;;
      --op-id)        _pfsm_require_optval "plan-rollback" "$1" "$#" || exit 2
                      op_id_opt="$2"; shift 2 ;;
      --*) echo "ERROR: plan-rollback: unknown flag: $1" >&2; exit 2 ;;
      *) if [[ -z "$plan_id" ]]; then plan_id="$1"
         else echo "ERROR: plan-rollback: unexpected argument: $1" >&2; exit 2; fi
         shift ;;
    esac
  done
  if [[ -z "$plan_id" || -z "$revert_commit" ]]; then
    echo "Usage: aid-plan-fsm.sh plan-rollback <plan_id> --revert-commit <sha> [--reason <text>] [--project-root <path>] [--op-id <id>]" >&2
    exit 2
  fi
  _pfsm_validate_plan_id "$plan_id" || exit 2

  local root; root="$(_pfsm_resolve_project_root "$project_root_opt")"
  export AID_PLAN_STATE_PROJECT_ROOT="$root"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$root"

  local cur_state; cur_state="$(plan_state_get "$plan_id" "plan_state" 2>/dev/null || true)"
  if [[ "$cur_state" != "PLAN_MERGING" ]]; then
    echo "PRECONDITION FAIL: plan-rollback: ${plan_id} is '${cur_state:-<none>}' — a rollback closes a plan whose merge WAS published, which is PLAN_MERGING. Nothing was written." >&2
    exit 1
  fi

  # ── The four SHAs, read from the record and VERIFIED against Git ─────────
  local candidate target_branch target_before merge_commit
  candidate="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.candidate_sha')" || candidate=""
  target_branch="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.target_branch')" || target_branch=""
  merge_commit="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_merge.merge_commit')" || merge_commit=""
  target_before="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_merge.target_head_before')" || target_before=""
  local v
  for v in candidate target_branch merge_commit target_before; do
    local val="${!v}"
    if [[ -z "$val" || "$val" == "null" || "$val" == "not_found" ]]; then
      echo "PRECONDITION FAIL: plan-rollback: ${plan_id} records no ${v} — a rollback record that cannot name what was merged proves nothing. Nothing was written." >&2
      exit 1
    fi
  done

  local mr; mr="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_merge.result')" || mr=""
  if [[ "$mr" != "merged" ]]; then
    echo "PRECONDITION FAIL: plan-rollback: ${plan_id}'s merge record says '${mr:-<none>}', not 'merged' — there is nothing to roll back. An abort is the close for a plan that never merged. Nothing was written." >&2
    exit 1
  fi

  local rev_norm=""
  rev_norm="$(git -C "$root" rev-parse --verify --quiet "${revert_commit}^{commit}" 2>/dev/null)" || rev_norm=""
  if [[ -z "$rev_norm" ]]; then
    echo "PRECONDITION FAIL: plan-rollback: the revert commit '${revert_commit}' does not resolve in this repository. Nothing was written." >&2
    exit 1
  fi
  local target_now=""
  target_now="$(git -C "$root" rev-parse --verify --quiet "refs/heads/${target_branch}" 2>/dev/null)" || target_now=""
  if [[ -z "$target_now" ]]; then
    echo "PRECONDITION FAIL: plan-rollback: ${target_branch} does not resolve. Nothing was written." >&2
    exit 1
  fi

  # (1) The merge must still be reachable. A rollback is a revert FORWARD; a
  #     merge that has vanished from the target branch means history was
  #     rewritten, and no record should bless that.
  if ! git -C "$root" merge-base --is-ancestor "$merge_commit" "$target_now" 2>/dev/null; then
    echo "PRECONDITION FAIL: plan-rollback: the merge ${merge_commit:0:8} is NOT an ancestor of ${target_branch} (${target_now:0:8}) — the history was rewritten rather than reverted forward. A rollback record must describe a history that still contains what it rolled back. Nothing was written." >&2
    exit 1
  fi
  # (2) The revert must be on the target branch, and (3) must come AFTER the
  #     merge — otherwise it reverted something else.
  if ! git -C "$root" merge-base --is-ancestor "$rev_norm" "$target_now" 2>/dev/null; then
    echo "PRECONDITION FAIL: plan-rollback: the revert ${rev_norm:0:8} is not an ancestor of ${target_branch} — it is not part of the published history. Nothing was written." >&2
    exit 1
  fi
  if ! git -C "$root" merge-base --is-ancestor "$merge_commit" "$rev_norm" 2>/dev/null; then
    echo "PRECONDITION FAIL: plan-rollback: the merge ${merge_commit:0:8} is not an ancestor of the revert ${rev_norm:0:8} — that revert cannot be undoing this merge. Nothing was written." >&2
    exit 1
  fi
  # (4) The delivery must actually be gone. Comparing the target head BEFORE the
  #     merge with the target head NOW is the whole claim of a rollback: if the
  #     plan's files are still there, nothing was rolled back.
  # `.aid-lifecycle/` is deliberately EXEMPT. The merge also commits the delivery
  # bindings, and reverting the merge does not — and must not — erase them: the
  # record that the merge happened is the audit trail a rollback is supposed to
  # preserve, not something it is supposed to clean up. What a rollback claims is
  # that the DELIVERY is gone, so that is what is checked.
  # THE REVERT ITSELF must be the commit that restored the content — not merely
  # any later descendant that happens to sit on a branch whose tip looks right.
  # Comparing only the tip would accept a decoy: revert properly, commit
  # something else, then name THAT as the revert. So the named commit's OWN tree
  # is compared against the pre-merge tree.
  local rev_diff=""
  rev_diff="$(git -C "$root" diff --name-only "${target_before}" "${rev_norm}" 2>/dev/null \
    | grep -v '^\.aid-lifecycle/' | head -20 || true)"
  # A commit made BEFORE the revert cannot restore anything; a commit made after
  # it may legitimately add unrelated files, so the comparison that matters is
  # the plan's own paths. Anything else here is not this plan's business.
  if [[ -n "$rev_diff" ]]; then
    local _rd kept=""
    while IFS= read -r _rd; do
      [[ -n "$_rd" ]] || continue
      git -C "$root" diff --quiet "${target_before}" "${merge_commit}" -- "$_rd" 2>/dev/null \
        || kept="${kept}${_rd}
"
    done <<< "$rev_diff"
    rev_diff="$kept"
  fi
  # Matching content is necessary but NOT sufficient: every commit after the real
  # revert also matches, because the revert already restored things. What makes a
  # commit THE revert is that IT is the one that changed those paths. Otherwise
  # the drill could be performed properly and then a later, innocent commit named
  # as the revert — a true-looking record pointing at the wrong commit.
  local rev_own=""
  rev_own="$(git -C "$root" diff --name-only "${rev_norm}^" "${rev_norm}" 2>/dev/null \
    | grep -v '^\.aid-lifecycle/' || true)"
  local touched_plan_paths=0 _ro
  if [[ -n "$rev_own" ]]; then
    while IFS= read -r _ro; do
      [[ -n "$_ro" ]] || continue
      git -C "$root" diff --quiet "${target_before}" "${merge_commit}" -- "$_ro" 2>/dev/null \
        || touched_plan_paths=1
    done <<< "$rev_own"
  fi
  if [[ "$touched_plan_paths" -eq 0 ]]; then
    echo "PRECONDITION FAIL: plan-rollback: ${rev_norm:0:8} does not itself restore the plan's paths — its own diff touches none of them, so it is a commit that happens to sit after the revert rather than the revert itself. Name the commit that removed the delivery. Nothing was written." >&2
    exit 1
  fi
  if [[ -n "$rev_diff" ]]; then
    echo "PRECONDITION FAIL: plan-rollback: the commit named as the revert (${rev_norm:0:8}) does not itself restore the pre-merge content of ${target_before:0:8} — these paths still differ AT THAT COMMIT, so it is not the revert (lifecycle bookkeeping under .aid-lifecycle/ is exempt and expected to remain):" >&2
    printf '  %s\n' $rev_diff >&2
    echo "Nothing was written." >&2
    exit 1
  fi
  # And the branch must not have re-introduced THE PLAN'S OWN paths afterwards.
  # Scoping matters: comparing the whole branch would reject every later
  # unrelated commit, which has nothing to do with whether the delivery came
  # back. The plan's paths are the ones its merge introduced.
  local delivered still=""
  delivered="$(git -C "$root" diff --name-only "${target_before}" "${merge_commit}" 2>/dev/null \
    | grep -v '^\.aid-lifecycle/' || true)"
  if [[ -n "$delivered" ]]; then
    local dp
    while IFS= read -r dp; do
      [[ -n "$dp" ]] || continue
      if ! git -C "$root" diff --quiet "${target_before}" "${target_now}" -- "$dp" 2>/dev/null; then
        still="${still}${dp}
"
      fi
    done <<< "$delivered"
  fi
  if [[ -n "$still" ]]; then
    echo "PRECONDITION FAIL: plan-rollback: ${target_branch} carries the plan's delivery again relative to its pre-merge state ${target_before:0:8} — the revert happened, but something after it re-introduced these paths:" >&2
    printf '  %s\n' $still >&2
    echo "Nothing was written." >&2
    exit 1
  fi

  # ── The transaction: lock, then intent -> git_applied -> state_committed ──
  # Without this a crash between the manifest write and the state change left a
  # plan recording a rollback it was not in, with nothing to reconcile from.
  local rb_lock; rb_lock="$(_pfsm_close_lock_path "$plan_id")"
  rb_lock="${rb_lock%plan-close.lock}plan-rollback.lock"
  if ! aid_lock_acquire "$rb_lock" 10; then
    echo "PRECONDITION FAIL: plan-rollback: another rollback holds ${rb_lock} — nothing was written." >&2
    exit 1
  fi
  local rb_fd="$AID_LOCK_FD"
  _pfsm_rb_release() { [[ -n "${rb_fd:-}" ]] && aid_lock_release "$rb_fd" >/dev/null 2>&1; rb_fd=""; return 0; }

  local rb_run
  rb_run="$(plan_manifest_get "$plan_id" '.plan_boundary_manifest.plan_final_run_id')" || rb_run=""
  [[ "$rb_run" == "null" || "$rb_run" == "not_found" ]] && rb_run=""
  local rb_attempt="${rb_run##*-final-}"
  [[ "$rb_attempt" =~ ^[0-9]+$ ]] || rb_attempt=0
  local rb_op="${op_id_opt:-$(plan_op_key "plan-rollback" "$plan_id" "-" "$rb_attempt" "$rev_norm")}"
  local rb_phase="none"
  rb_phase="$(plan_op_reconcile "$plan_id" "$rb_op" 2>/dev/null || echo none)"
  if [[ "$rb_phase" != "git_applied" && "$rb_phase" != "state_committed" ]]; then
    if ! plan_op_begin "$plan_id" "$rb_op" "plan-rollback" "$plan_id" "$rev_norm"; then
      _pfsm_rb_release
      echo "PRECONDITION FAIL: plan-rollback: could not record the rollback intent for ${plan_id} — nothing was written." >&2
      exit 1
    fi
  fi
  _pfsm_crash_seam intent

  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local rb_json
  rb_json="$(jq -nc --arg c "$candidate" --arg tb "$target_branch" --arg tbefore "$target_before" \
    --arg mc "$merge_commit" --arg rc "$rev_norm" --arg at "$now" --arg rs "${reason:-pm_rollback}" \
    '{result:"rolled_back", candidate_sha:$c, target_branch:$tb,
      target_head_before_merge:$tbefore, merge_commit:$mc, revert_commit:$rc,
      rolled_back_at:$at, reason:$rs,
      verified:{merge_still_reachable:true, revert_on_target:true,
                revert_after_merge:true, target_restored_to_pre_merge:true}}')"
  plan_manifest_update "$plan_id" ".plan_boundary_manifest.plan_final_rollback = ${rb_json}" >/dev/null 2>&1 \
    || { _pfsm_rb_release; echo "PRECONDITION FAIL: plan-rollback: could not record the rollback for ${plan_id}. Nothing was written." >&2; exit 1; }

  # ── git_applied: the DURABLE record, on the target branch ────────────────
  # The runtime marker lives under gitignored .aid-o/, so without this a fresh
  # clone would read `deliveries` and conclude the plan was delivered while the
  # local workspace said it had been rolled back. Two truths — exactly what this
  # boundary exists to remove. The write goes through the same plumbing path the
  # merge bindings use (commit-tree + CAS update-ref, no checkout) and is READ
  # BACK from the target ref: a record that cannot be read from git is not
  # durable, whatever the worktree says.
  local lc_rel=".aid-lifecycle/manifests/${plan_id}.yaml"
  if [[ ! -f "${root}/${lc_rel}" ]]; then
    # FAIL-CLOSED. A plan-branch plan with no lifecycle manifest cannot record a
    # durable rollback, and a LOCAL-only ROLLED_BACK is the very two-truths state
    # this work exists to remove: the workspace would say rolled back while the
    # git ledger still read the plan as delivered. Refusing is the only honest
    # outcome — better a plan stuck in PLAN_MERGING than a lie in the books.
    _pfsm_rb_release
    echo "PRECONDITION FAIL: plan-rollback: ${plan_id} has no ${lc_rel}, so the rollback cannot be made durable — and a rollback recorded only in gitignored .aid-o/ would leave a fresh clone reading this plan as delivered. NOTHING was written; ${plan_id} stays ${cur_state}." >&2
    exit 1
  fi
  if true; then
    # Idempotent by read-back: a resumed run finds the record already durable and
    # writes nothing further. Committing it twice would put a second, identical
    # lifecycle commit on the target branch for one rollback.
    local rb_already=""
    # The resume check compares the same five fields, not just the revert: a
    # partial match is a different record, and skipping the write on it would
    # leave the wrong one durable.
    rb_already="$(git -C "$root" show "${target_branch}:${lc_rel}" 2>/dev/null \
      | yq -r '[(.status // ""), (.rollback.candidate_sha // ""), (.rollback.target_head_before_merge // ""), (.rollback.merge_commit // ""), (.rollback.revert_commit // "")] | join("|")' 2>/dev/null || true)"
    if [[ "$rb_already" == "rolled_back|${candidate}|${target_before}|${merge_commit}|${rev_norm}" ]]; then
      echo "NOTE: plan-rollback: the durable rollback record for ${plan_id} is already on ${target_branch} naming ${rev_norm:0:8} — this is a resume, so nothing was re-committed." >&2
    else
    # NO free-text `reason` here. publicsafe_check forbids a `reason` key in a
    # git-tracked artifact, and it was only ever accepted because this path
    # skipped validation. The human reason lives in the runtime marker and the
    # operation log; what the ledger carries is a technical pointer to it.
    # BASE THE EDIT ON THE LEDGER, not on the worktree copy. The controller sits
    # on the plan branch, whose manifest can be OLDER than the target's — it
    # predates the delivery bindings the merge itself just committed. Editing
    # that stale copy and publishing the whole file would silently delete the
    # fresh `deliveries` and anything else the target has and the plan branch
    # does not. Materialising the target's content first means every existing
    # field survives, because it is what we started from.
    local rb_base_rc=0
    ( cd "$root" && git show "${target_branch}:${lc_rel}" > "$lc_rel" ) 2>/dev/null || rb_base_rc=$?
    if [[ "$rb_base_rc" -ne 0 ]]; then
      ( cd "$root" && git checkout -q HEAD -- "$lc_rel" 2>/dev/null ) || true
      _pfsm_rb_release
      echo "PRECONDITION FAIL: plan-rollback: could not read ${target_branch}:${lc_rel} to base the rollback record on (rc=${rb_base_rc}) — editing the plan branch's possibly-stale copy could drop deliveries the ledger already records. Nothing was written." >&2
      exit 1
    fi

    local rb_yrc=0
    ( cd "$root" && yq -i ".status = \"rolled_back\"
        | .rollback = {\"candidate_sha\": \"${candidate}\",
                       \"target_head_before_merge\": \"${target_before}\",
                       \"merge_commit\": \"${merge_commit}\",
                       \"revert_commit\": \"${rev_norm}\",
                       \"rolled_back_at\": \"${now}\",
                       \"decision_ref\": \"${rb_op}\"}" "$lc_rel" ) || rb_yrc=$?
    if [[ "$rb_yrc" -ne 0 ]]; then
      _pfsm_rb_release
      echo "PRECONDITION FAIL: plan-rollback: could not write the durable rollback record into ${lc_rel} — without it a fresh clone would still read this plan as delivered. Nothing further was written." >&2
      exit 1
    fi
    # PLAN MODE, for the same reason the merge bindings and the close receipt use
    # it: the controller's worktree sits on the plan branch, not on the target,
    # and an ordinary commit would be refused by the target-branch guard. Plan
    # mode publishes with commit-tree + a CAS update-ref onto the target ref —
    # no checkout, no HEAD move.
    # VALIDATE BEFORE COMMITTING — the mandatory step this path skipped, which is
    # the only reason a forbidden key ever reached a tracked file. A failure here
    # must stop the commit AND leave the local state untouched.
    if ! aid_lifecycle_validate_artifact "${root}/${lc_rel}" "plan-lifecycle-manifest.schema.json"; then
      ( cd "$root" && git checkout -q HEAD -- "$lc_rel" 2>/dev/null ) || true
      _pfsm_rb_release
      echo "PRECONDITION FAIL: plan-rollback: the rollback record for ${plan_id} does not validate against plan-lifecycle-manifest.schema.json / the public-safe contract — the worktree edit is reverted, nothing was committed and ${plan_id} stays ${cur_state}." >&2
      exit 1
    fi
    local rb_crc=0
    aid_lc_plan_mode_begin "" "" "$target_now"
    ( cd "$root" && _aid_lc_isolated_commit "." "lifecycle: ${plan_id} rolled back (merge ${merge_commit:0:8}, revert ${rev_norm:0:8})" "$lc_rel" >/dev/null 2>&1 ) || rb_crc=$?
    aid_lc_plan_mode_end
    # The read-back compares the STATUS AND ALL FOUR SHAs. Checking only the
    # status would pass a record whose SHAs were wrong or missing — the report
    # would claim four verified SHAs while one field had been verified.
    local rb_read="" rb_mismatch=""
    rb_read="$(git -C "$root" show "${target_branch}:${lc_rel}" 2>/dev/null \
      | yq -r '[(.status // ""), (.rollback.candidate_sha // ""), (.rollback.target_head_before_merge // ""), (.rollback.merge_commit // ""), (.rollback.revert_commit // "")] | join("|")' 2>/dev/null || true)"
    local rb_want="rolled_back|${candidate}|${target_before}|${merge_commit}|${rev_norm}"
    [[ "$rb_read" != "$rb_want" ]] && rb_mismatch="1"
    if [[ -n "$rb_mismatch" ]]; then
      ( cd "$root" && git checkout -q HEAD -- "$lc_rel" 2>/dev/null ) || true
      _pfsm_rb_release
      echo "PRECONDITION FAIL: plan-rollback: the durable rollback record read back from ${target_branch}:${lc_rel} does not match what was written (rc=${rb_crc})." >&2
      echo "  expected: ${rb_want}" >&2
      echo "  read:     ${rb_read:-<none>}" >&2
      echo "The worktree edit is reverted and nothing else was written. A rollback a clean clone cannot read, or reads differently, is not a rollback." >&2
      exit 1
    fi
    fi
  fi
  # The worktree path was borrowed to carry the ledger's content into the
  # commit; put the plan branch's own copy back so the borrow leaves no trace.
  ( cd "$root" && git checkout -q HEAD -- "$lc_rel" 2>/dev/null ) || true
  plan_op_mark_git_applied "$plan_id" "$rb_op" "$rev_norm" >/dev/null 2>&1 || true
  _pfsm_crash_seam git_applied

  if ! _pfsm_plan_state_set "$plan_id" "ROLLED_BACK"; then
    _pfsm_rb_release
    echo "PRECONDITION FAIL: plan-rollback: the rollback is recorded for ${plan_id}, but the plan could not be moved to ROLLED_BACK. Reconcile with 'aid-plan-fsm.sh plan-state ${plan_id}'." >&2
    exit 1
  fi
  plan_manifest_update "$plan_id" '.plan_boundary_manifest.plan_state = "ROLLED_BACK"' >/dev/null 2>&1 \
    || echo "WARN: plan-rollback: ${plan_id} is ROLLED_BACK in plan-state.yaml, but the runtime manifest mirror could not be updated." >&2

  local marker; marker="$(_pfsm_close_marker_path "$plan_id")"
  marker="${marker%plan-close-complete}plan-rollback-complete"
  mkdir -p "$(dirname "$marker")" 2>/dev/null || true
  printf 'plan_id=%s\nresult=rolled_back\ncandidate_sha=%s\ntarget_branch=%s\ntarget_head_before_merge=%s\nmerge_commit=%s\nrevert_commit=%s\nreason=%s\nrolled_back_at=%s\n' \
    "$plan_id" "$candidate" "$target_branch" "$target_before" "$merge_commit" "$rev_norm" "${reason:-pm_rollback}" "$now" \
    > "${marker}.tmp" && mv -f "${marker}.tmp" "$marker"

  plan_op_commit "$plan_id" "$rb_op" >/dev/null 2>&1 || true
  _pfsm_rb_release
  echo "ROLLED BACK: ${plan_id} merged as ${merge_commit:0:8} and was reverted by ${rev_norm:0:8}; ${target_branch} is back at its pre-merge tree (${target_before:0:8}) with both commits still reachable, and the rollback is durable in ${lc_rel} on ${target_branch}. The plan is ROLLED_BACK — not aborted, which would deny the merge, and not closed, which would claim a delivery that is no longer there." >&2
  return 0
}

_aid_plan_fsm_usage() {
  cat <<'EOF'
Usage: aid-plan-fsm.sh <subcommand> [args...]

Subcommands:
  plan-start <plan_id> --mode plan_branch|legacy_epic_release_mode [--project-root <path>] [--op-id <id>]
  epic-start <plan_id> <epic_id> [--run-id <id>] [--project-root <path>] [--op-id <id>]
  epic-complete <plan_id> <epic_id> [--abandon --reason <text>] [--supersede-by <epic_id> --reason <text>] [--full-tests --reason <text>] [--project-root <path>] [--op-id <id>]
  epic-merge-to-plan <plan_id> <epic_id> [--expected-plan-sha <sha>] [--project-root <path>] [--op-id <id>]
  plan-finalize <plan_id> --stage <sync|freeze|gates|inputs|review|c4|summary> [--frozen-at <rfc3339>] [--execution-yaml <path>] [--substitute-receipt <gate_id>=<path>] [--project-root <path>]
  plan-merge-to-main <plan_id> --decision <path> [--project-root <path>] [--op-id <id>] [--push]
  plan-close <plan_id> [--project-root <path>] [--op-id <id>] [--skip-delivery-report]
  plan-rollback <plan_id> --revert-commit <sha> [--reason <text>] [--project-root <path>] [--op-id <id>]
  inventory [--apply] [--plan <id>] [--project-root <path>]
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
    plan-finalize) cmd_plan_finalize "$@" ;;
    plan-merge-to-main) cmd_plan_merge_to_main "$@" ;;
    plan-close) cmd_plan_close "$@" ;;
    plan-rollback) cmd_plan_rollback "$@" ;;
    plan-state) cmd_plan_state "$@" ;;
    inventory) cmd_inventory "$@" ;;
    # Internal: the resolved default mode for NEW plans, as "<mode>\t<reason>".
    # Deliberately undocumented in the usage text — it is a resolver other
    # scripts consult, not an operator command.
    __default-mode)
      local __dm_root=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --project-root) __dm_root="${2:-}"; shift 2 ;;
          *) shift ;;
        esac
      done
      _pfsm_default_mode "$(_pfsm_resolve_project_root "$__dm_root")"
      ;;
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
