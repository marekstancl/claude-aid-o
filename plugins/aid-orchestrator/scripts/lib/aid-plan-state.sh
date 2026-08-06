#!/usr/bin/env bash
# =============================================================================
# aid-plan-state.sh — durable parent-plan state file + operation record
# (P064 "Plan Branch Substrate", EPIC E-064-1_2, Step 1).
#
# WHY THIS EXISTS: P064 makes `plan/Pxxx` the integration branch for a plan's
# EPICs. Every command that mutates that story (`plan-start`, `epic-start`,
# `epic-merge-to-plan`, ... — `aid-plan-fsm.sh`, a later step) needs (a) a
# durable, plan_id-keyed state file recording which of eleven plan states the
# plan is in, with a fixed legal-transition table so no command can jump the
# state machine, and (b) a durable, append-only operation record so a crashed
# command can resume exactly where it left off instead of either silently
# re-running a Git action or getting stuck believing "nothing happened".
# This file provides both, and touches NEITHER Git NOR the git-tracked
# `.aid-lifecycle/` layer — that separation is deliberate (see Architecture
# Context below) and keeps this layer unit-testable without a repository.
#
# SOURCE OF TRUTH FOR THE DATA MODEL BELOW: `.aid-o/plans/P064-plan-branch-substrate.md`
# → `## Data Model` → "Plan state file" and "Operation record" (this file's
# schema and the `_AID_PLAN_TRANSITIONS` table are a direct, line-for-line
# transcription of that section — read it there for the full narrative,
# including the three transitions that exist for reasons not obvious from
# the table alone: `PLAN_SYNC → PLAN_SYNC`, `AWAITING_PM → PLAN_SYNC`,
# `AWAITING_PM → CONFLICT`, all P068 concerns but wired into the table here
# because a later step must never need to touch this table's shape, only
# consume it).
#
# ── SCOPE (this step, Step 1, is the FOUNDATION only) ────────────────────────
# Implements the eight functions below plus `plan_op_key`. Does NOT implement
# `aid-plan-fsm.sh` itself (a later step), does NOT implement the
# `mode`-authority re-validation against `.aid-lifecycle/manifests/<plan_id>.yaml`
# (a later step's `aid_lifecycle_plan_mode` — see the `plan_state_get` note
# below for exactly what this step's `mode` field is and is not), and does
# NOT implement `plan-boundary-manifest.json` (a later step's
# `aid-plan-manifest.sh`).
#
# ── STATE FILE — .aid-o/work/plan-state/<plan_id>/plan-state.yaml ───────────
#   plan_id            string   matches the caller's plan_id (path-safety
#                                charset only is enforced HERE — the stricter
#                                `^P[0-9]{3}$` format is a manifest-layer
#                                concern, a later step)
#   plan_state         enum     OPEN EPIC_INTEGRATION PLAN_SYNC PLAN_GATES
#                                PLAN_REVIEW PLAN_FIX AWAITING_PM PLAN_MERGING
#                                CLOSED ABORTED CONFLICT
#   mode               enum     plan_branch | legacy_epic_release_mode
#   plan_branch        string   exactly "plan/<plan_id>"
#   target_branch      string   non-empty
#   created_at         string   ISO-8601 UTC
#   current_operation  string|null
#   plan_final_attempt integer  >= 0
#
# `mode` IS NOT AN AUTHORITY HERE. Per the plan doc: "`plan_state.yaml` caches
# it for speed, but `plan_state_get <plan_id> mode` re-reads
# `.aid-lifecycle/manifests/<plan_id>.yaml` and fails closed on a mismatch,
# so a hand-edited or deleted runtime file cannot change which release model
# a plan follows." THIS STEP DOES NOT IMPLEMENT THAT RE-READ — the reader it
# needs (`aid_lifecycle_plan_mode`) does not exist yet (a later step adds it
# to `lib/aid-lifecycle.sh`). `plan_state_get <plan_id> mode` here returns
# only the cached value; a later step is responsible for wiring the
# authoritative fail-closed check on top of it. Do not treat this function's
# `mode` output as authoritative until that wiring lands.
#
# ── OPERATION RECORD — .aid-o/work/plan-state/<plan_id>/operations.jsonl ───
# Append-only, one JSON object per line, written under the plan lock:
#   op_id                 string       see plan_op_key below
#   command                string       plan-start | epic-start | epic-complete
#                                       | epic-merge-to-plan | plan-finalize
#                                       | plan-merge-to-main | plan-close
#     `plan-close` is P068 E-068-1_2 Step 6's ADDITIVE extension of P064's own
#     six-command enum, declared here rather than silently assumed: the close
#     transaction is a durable operation like every other one, keyed
#     `plan-close:<plan_id>:-:<attempt>:<plan_id>`, following the same
#     intent -> git_applied -> state_committed sequence (git_applied is stamped
#     when the lifecycle receipt — or, for an aborted plan, the abort record —
#     commits; state_committed when the plan-close-complete marker is written),
#     so a crash between the two is reconcilable exactly like any other.
#   subject                string       EPIC id for EPIC-scoped commands, else
#                                       plan id
#   phase                  enum         intent | git_applied | state_committed
#                                       | aborted
#   expected_before_sha    string|null  40-hex; the head asserted before acting
#   resulting_sha          string|null  40-hex; written at git_applied
#   at                      string       ISO-8601 UTC
#
# `op_id` default shape: `<command>:<plan_id>:<stage>:<attempt>:<subject>` —
# deterministic, no timestamp/entropy, so a resumed command with no
# `--op-id` derives the SAME id as the crashed original and finds its own
# record (see `plan_op_key`). Because the key is deterministic and this file
# is append-only, a subject legitimately operated on more than once (merge →
# conflict → abort → re-merge) accumulates several records sharing one
# `op_id`; `plan_op_reconcile` reads the LAST one.
#
# ── CONCURRENCY ──────────────────────────────────────────────────────────────
# Every write (state-file init/transition, operation-record append) goes
# through `aid-lock.sh` (sourced below) on ONE per-plan sidecar lock —
# `plan-state.yaml.lock` — covering both the state file and the operation
# log, then `<path>.tmp.$$` + `mv` for the state file (matches
# `aid-cp1-ledger.sh`'s `_write_ledger_json` convention exactly). Reads
# (`plan_state_get`, `plan_op_reconcile`) are lock-free, matching this
# codebase's established read-without-lock convention for state files
# written atomically (`aid-cp1-ledger.sh`'s `cmd_read`/`cmd_check_budget`) —
# an in-progress atomic write is invisible to a concurrent reader (the reader
# either sees the old complete file or the new complete file, never a
# partial one), and `operations.jsonl` appends are handled defensively (see
# Error Handling below) precisely because a reader CAN observe a
# torn/partial line if it reads mid-append.
#
# ── PROJECT ROOT ─────────────────────────────────────────────────────────────
# CWD-relative by default (matches aid-fsm.sh/aid-run-gates.sh's own bare-CWD
# convention, since this library is meant to be sourced directly into those
# scripts' shell) — override with AID_PLAN_STATE_PROJECT_ROOT for tests/
# callers that need an isolated root without a real checkout.
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` — see aid-lock.sh's header for the
# full rationale (this file sources aid-lock.sh below and follows the same
# convention). Every public function returns an explicit code.
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   Sourced (the real, intended usage):
#     source .../lib/aid-plan-state.sh
#     plan_state_init "P064" "plan_branch" "plan/P064" "main"
#     plan_state_get "P064" "plan_state"          # -> OPEN
#     plan_state_transition "P064" "OPEN" "EPIC_INTEGRATION"
#     op_id="$(plan_op_key "epic-merge-to-plan" "P064" "-" "0" "E-064-1_4")"
#     plan_op_begin "P064" "$op_id" "epic-merge-to-plan" "E-064-1_4" "$before_sha"
#     plan_op_mark_git_applied "P064" "$op_id" "$merge_sha"
#     plan_op_commit "P064" "$op_id"
#     plan_op_reconcile "P064" "$op_id"            # -> state_committed
#
#   Standalone (debugging / bats convenience — see `main` below):
#     bash aid-plan-state.sh state-path <plan_id>
#     bash aid-plan-state.sh init <plan_id> <mode> <plan_branch> <target_branch>
#     bash aid-plan-state.sh get <plan_id> <field>
#     bash aid-plan-state.sh transition <plan_id> <from> <to>
#     bash aid-plan-state.sh op-key <command> <plan_id> <stage> <attempt> <subject>
#     bash aid-plan-state.sh op-begin <plan_id> <op_id> <command> <subject> <expected_before_sha>
#     bash aid-plan-state.sh op-git-applied <plan_id> <op_id> <resulting_sha>
#     bash aid-plan-state.sh op-commit <plan_id> <op_id>
#     bash aid-plan-state.sh op-reconcile <plan_id> <op_id>
#
# Exit codes (functions, as `return`; standalone CLI mirrors them as `exit`):
#   0 = success. 1 = precondition/usage failure (invalid transition, missing
#   required arg, no prior record to extend, stale from-state, ...).
#   3 = lock not acquired within the lease window. 5 = corrupt data detected
#   (bad state file, unparseable/truncated operations.jsonl line, op_id/
#   command mismatch across records) — NEVER silently repaired, because a
#   wrong repair could authorize a merge.
#   `plan_state_get`/`plan_op_reconcile` also use 1 for the benign
#   "not_found"/"none" cases — see each function's own doc comment for the
#   exact contract, since "not found" and "corrupt" must stay distinguishable
#   on stdout even though both can return non-zero.
#
# **Last Updated:** 2026-07-20
# =============================================================================

_AID_PLAN_STATE_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_AID_PLAN_STATE_LIBDIR}/aid-lock.sh"
# shellcheck disable=SC1091
source "${_AID_PLAN_STATE_LIBDIR}/aid-roots.sh"   # P074 Step 1 — state-root resolution

AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S=10

# _AID_PLAN_TRANSITIONS — mirrors P064-plan-branch-substrate.md's
# "## Data Model" -> "Legal transitions" table verbatim. FROM:TO pairs; any
# pair not listed here is rejected by plan_state_transition before any
# write. THIS TABLE IS THE FULL, FINAL eleven-state machine (not just the
# subset Step 1's own callers exercise) — later steps (aid-plan-fsm.sh, P068's
# plan-final runner) extend the COMMANDS that drive it, never this table's
# shape.
#
# ── LIFECYCLE CONTRACT (tested in test-aid-plan-release-boundary.bats) ───────
# This state machine defines three classes of edges:
#
#   1. SELF-LOOPS (inverse-illegal test inapplicable):
#      - EPIC_INTEGRATION → EPIC_INTEGRATION
#      - PLAN_SYNC → PLAN_SYNC
#      A state looping to itself is trivially its own inverse; every test
#      that asserts "reverse fails" would be redundant here.
#
#   2. BIDIRECTIONAL PAIRS (inverse-illegal test inapplicable):
#      - EPIC_INTEGRATION ↔ CONFLICT (both EPIC_INTEGRATION→CONFLICT and
#        CONFLICT→EPIC_INTEGRATION are legal)
#      - PLAN_SYNC ↔ CONFLICT (both PLAN_SYNC→CONFLICT and CONFLICT→PLAN_SYNC
#        are legal)
#      In these pairs, both directions are intentionally permitted; there is
#      no "illegal inverse" to test.
#
#   3. ONE-WAY EDGES (inverse-illegal test REQUIRED):
#      Every other edge in the table is one-way: the reverse is NOT legal and
#      must be rejected with PRECONDITION FAIL, leaving state unchanged.
#      Examples: OPEN→EPIC_INTEGRATION (reverse EPIC_INTEGRATION→OPEN illegal),
#                PLAN_GATES→PLAN_REVIEW (reverse PLAN_REVIEW→PLAN_GATES illegal).
#
# TEST COVERAGE: Every one-way edge has a corresponding negative test in
# test-aid-plan-release-boundary.bats § "Lifecycle Contract". Each negative
# test: (1) reaches the destination state via valid path, (2) attempts the
# illegal reverse, (3) asserts non-zero exit and unchanged on-disk state.
# Self-loops and bidirectional pairs are explicitly documented (test comments)
# with "inapplicable" reasoning instead of having redundant/confusing negative
# assertions that would appear to pass but test nothing meaningful.
_AID_PLAN_TRANSITIONS=(
  "OPEN:EPIC_INTEGRATION"
  "OPEN:ABORTED"
  "EPIC_INTEGRATION:EPIC_INTEGRATION"
  "EPIC_INTEGRATION:PLAN_SYNC"
  "EPIC_INTEGRATION:CONFLICT"
  "EPIC_INTEGRATION:ABORTED"
  "CONFLICT:EPIC_INTEGRATION"
  "CONFLICT:PLAN_SYNC"
  "CONFLICT:ABORTED"
  "PLAN_SYNC:PLAN_SYNC"
  "PLAN_SYNC:PLAN_GATES"
  "PLAN_SYNC:CONFLICT"
  "PLAN_SYNC:ABORTED"
  "PLAN_GATES:PLAN_REVIEW"
  "PLAN_GATES:PLAN_FIX"
  "PLAN_GATES:ABORTED"
  "PLAN_REVIEW:AWAITING_PM"
  "PLAN_REVIEW:PLAN_FIX"
  "PLAN_REVIEW:ABORTED"
  "PLAN_FIX:PLAN_SYNC"
  "PLAN_FIX:ABORTED"
  "AWAITING_PM:PLAN_MERGING"
  "AWAITING_PM:PLAN_SYNC"
  "AWAITING_PM:PLAN_FIX"
  "AWAITING_PM:CONFLICT"
  "AWAITING_PM:ABORTED"
  "PLAN_MERGING:CLOSED"
  # P075 dogfood (2026-07-27): a plan that merged and was then correctly reverted
  # has no honest terminal state today. ABORTED is a lie — it merged; CLOSED is a
  # lie — its delivery is not on the target branch. ROLLED_BACK is the third
  # outcome the boundary always had in practice and never had a name for.
  "PLAN_MERGING:ROLLED_BACK"
  "PLAN_MERGING:CONFLICT"
  "PLAN_MERGING:ABORTED"
)

# NOTE: "OPEN:PLAN_MERGING" is deliberately absent — a plan must pass through
# EPIC_INTEGRATION, PLAN_SYNC, PLAN_GATES, PLAN_REVIEW and AWAITING_PM first.
# This is not a special case bolted on for AC2; it falls straight out of the
# real eleven-state machine above.

_AID_PLAN_VALID_STATES=(
  OPEN EPIC_INTEGRATION PLAN_SYNC PLAN_GATES PLAN_REVIEW PLAN_FIX
  AWAITING_PM PLAN_MERGING CLOSED ABORTED CONFLICT ROLLED_BACK
)

_plan_warn() {
  echo "WARN: aid-plan-state.sh: $*" >&2
}

# ---------------------------------------------------------------------------
# _validate_plan_id <plan_id> — non-empty, path-traversal-safe charset.
# (The stricter ^P[0-9]{3}$ format is a manifest-layer concern, a later step.)
# ---------------------------------------------------------------------------
_validate_plan_id() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    _plan_warn "plan_id is empty"
    return 1
  fi
  if ! [[ "$pid" =~ ^[A-Za-z0-9_-]+$ ]]; then
    _plan_warn "plan_id '$pid' contains invalid characters (path traversal guard)"
    return 1
  fi
  return 0
}

_plan_state_require_deps() {
  command -v jq >/dev/null 2>&1 || { _plan_warn "jq not found on PATH"; return 2; }
  command -v yq >/dev/null 2>&1 || { _plan_warn "yq not found on PATH"; return 2; }
  return 0
}

_plan_state_project_root() {
  # P074 Step 1: the dedicated env override stays, but passes through
  # aid_canonicalize_project_root so an override pointing INTO a linked
  # worktree collapses to the primary checkout instead of forking state.
  # An override naming a directory that is NEITHER a repo root NOR carries an
  # .aid-o workspace FAILS LOUDLY (return 2, resolver's message names both
  # accepted forms) — a silent write to an arbitrary path is never allowed.
  if [[ -n "${AID_PLAN_STATE_PROJECT_ROOT:-}" ]]; then
    aid_canonicalize_project_root "$AID_PLAN_STATE_PROJECT_ROOT" || return 2
    return 0
  fi
  # No override: the state root (primary checkout). Outside a git repository
  # the historic $(pwd) fallback is kept so this layer stays unit-testable
  # without a repository (see the header's design note).
  aid_state_root 2>/dev/null || pwd
}

# _plan_state_dir <plan_id> — the per-plan runtime directory (not part of
# the required public API; test suites reconstruct this path independently,
# matching this codebase's existing convention, e.g. test-cp1-ledger.bats's
# own `_ledger_file` helper).
_plan_state_dir() {
  local _psd_root
  _psd_root="$(_plan_state_project_root)" || return 2
  printf '%s/.aid-o/work/plan-state/%s' "$_psd_root" "$1"
}

# plan_state_path <plan_id> — the plan state file's canonical path.
plan_state_path() {
  local _psp_dir
  _psp_dir="$(_plan_state_dir "$1")" || return 2
  printf '%s/plan-state.yaml' "$_psp_dir"
}

_plan_ops_path() {
  printf '%s/operations.jsonl' "$(_plan_state_dir "$1")"
}

_plan_lock_path() {
  printf '%s.lock' "$(plan_state_path "$1")"
}

_plan_state_read_raw_json() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  yq -o=json '.' "$path" 2>/dev/null
}

_plan_state_write_json() {
  local path="$1" json="$2" tmp
  tmp="${path}.tmp.$$"
  printf '%s' "$json" | yq -p=json -o=yaml '.' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv -- "$tmp" "$path" || { rm -f "$tmp"; return 1; }
  return 0
}

# _plan_state_validate_json <json> <plan_id> — the FULL corruption check:
# plan_id present+non-empty, plan_state present and a recognized enum value.
# Prints "PRECONDITION FAIL: ... offending key: <key>" to stderr and returns
# 5 on ANY violation — never partially trusts a corrupt file, never repairs.
_plan_state_validate_json() {
  local json="$1" plan_id="$2"
  local pid state s ok

  pid="$(jq -r '.plan_id // empty' <<<"$json" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    echo "PRECONDITION FAIL: plan state file for $plan_id is corrupt — offending key: plan_id (missing or empty)" >&2
    return 5
  fi

  state="$(jq -r '.plan_state // empty' <<<"$json" 2>/dev/null)"
  if [[ -z "$state" ]]; then
    echo "PRECONDITION FAIL: plan state file for $plan_id is corrupt — offending key: plan_state (missing or empty)" >&2
    return 5
  fi

  ok=1
  for s in "${_AID_PLAN_VALID_STATES[@]}"; do
    if [[ "$s" == "$state" ]]; then
      ok=0
      break
    fi
  done
  if [[ "$ok" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan state file for $plan_id is corrupt — offending key: plan_state (unrecognized value '$state')" >&2
    return 5
  fi

  return 0
}

# ===========================================================================
# plan_state_init <plan_id> <mode> <plan_branch> <target_branch>
#
# Creates a fresh state file at plan_state=OPEN. Refuses to overwrite an
# existing one (never a silent reset — matches aid-cp1-ledger.sh's `init`
# convention). Returns the state file path on stdout on success.
#
# Returns: 0 success, 1 bad args or file already exists, 2 missing jq/yq,
# 3 lock timeout.
# ===========================================================================
plan_state_init() {
  local plan_id="$1" mode="$2" plan_branch="$3" target_branch="$4"

  _plan_state_require_deps || return 2
  _validate_plan_id "$plan_id" || return 1

  case "$mode" in
    plan_branch|legacy_epic_release_mode) ;;
    *)
      _plan_warn "plan_state_init: mode must be 'plan_branch' or 'legacy_epic_release_mode' (got '${mode:-<empty>}')"
      return 1
      ;;
  esac

  if [[ "$plan_branch" != "plan/${plan_id}" ]]; then
    _plan_warn "plan_state_init: plan_branch must be exactly 'plan/${plan_id}' (got '${plan_branch:-<empty>}')"
    return 1
  fi
  if [[ -z "$target_branch" ]]; then
    _plan_warn "plan_state_init: target_branch is required"
    return 1
  fi

  local dir path
  dir="$(_plan_state_dir "$plan_id")"
  path="$(plan_state_path "$plan_id")"

  if [[ -f "$path" ]]; then
    _plan_warn "plan_state_init: state file already exists for $plan_id at $path — refusing to overwrite (never a silent reset)"
    return 1
  fi

  mkdir -p -- "$dir" 2>/dev/null || { _plan_warn "plan_state_init: cannot create $dir"; return 1; }

  local lock_path
  lock_path="$(_plan_lock_path "$plan_id")"
  aid_lock_acquire "$lock_path" "$AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S" || return 3
  local fd="$AID_LOCK_FD"

  # Re-check under the lock — closes the TOCTOU window against a concurrent
  # init winning the race between the check above and acquiring the lock.
  if [[ -f "$path" ]]; then
    aid_lock_release "$fd"
    _plan_warn "plan_state_init: state file appeared for $plan_id while acquiring the lock — refusing to overwrite"
    return 1
  fi

  local now json
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  json="$(jq -n \
    --arg pid "$plan_id" --arg mode "$mode" --arg pb "$plan_branch" \
    --arg tb "$target_branch" --arg now "$now" \
    '{plan_id: $pid, plan_state: "OPEN", mode: $mode, plan_branch: $pb,
      target_branch: $tb, created_at: $now, current_operation: null,
      plan_final_attempt: 0}')"

  if ! _plan_state_write_json "$path" "$json"; then
    aid_lock_release "$fd"
    _plan_warn "plan_state_init: cannot write state file to $path"
    return 1
  fi

  aid_lock_release "$fd"
  echo "$path"
  return 0
}

# ===========================================================================
# plan_state_get <plan_id> <field>
#
# Lock-free read of one field from the state file.
#
# Returns 0 with the value on stdout on success.
# Returns 1 with "not_found" on stdout when the plan's state directory does
#   not exist yet — distinguishable from a read error (Edge Case in the
#   plan spec).
# Returns 1 (nothing on stdout) when the state file exists and is valid but
#   the requested field is absent/null.
# Returns 5 (nothing on stdout, reason on stderr) when the state file is
#   corrupt (see _plan_state_validate_json) — NEVER repaired silently.
#
# `mode` is a CACHE ONLY here — see the file header's dedicated note. This
# function does not re-validate it against `.aid-lifecycle/`.
# ===========================================================================
plan_state_get() {
  local plan_id="$1" field="$2"

  _plan_state_require_deps || return 2
  _validate_plan_id "$plan_id" || return 1
  if [[ -z "$field" ]]; then
    _plan_warn "plan_state_get: field is required"
    return 1
  fi

  local dir path
  dir="$(_plan_state_dir "$plan_id")"
  path="$(plan_state_path "$plan_id")"

  if [[ ! -d "$dir" || ! -f "$path" ]]; then
    echo "not_found"
    return 1
  fi

  local json
  json="$(_plan_state_read_raw_json "$path")"
  if [[ -z "$json" ]]; then
    echo "PRECONDITION FAIL: plan state file for $plan_id at $path is unreadable or unparseable YAML — offending key: plan_state" >&2
    return 5
  fi

  _plan_state_validate_json "$json" "$plan_id" || return 5

  local val
  val="$(jq -r --arg f "$field" '.[$f] // empty' <<<"$json" 2>/dev/null)"
  if [[ -z "$val" ]]; then
    return 1
  fi
  printf '%s\n' "$val"
  return 0
}

# ===========================================================================
# plan_state_transition <plan_id> <from> <to>
#
# Validates "<from>:<to>" against _AID_PLAN_TRANSITIONS BEFORE touching the
# lock or the file. Rejects any pair not present (reason on stderr, nothing
# written, exit 1). If the pair is legal, re-verifies the ON-DISK plan_state
# actually equals <from> (guards a stale caller) before writing <to>.
#
# Returns: 0 success, 1 illegal pair / no state file / stale from-state,
# 3 lock timeout, 5 corrupt state file.
# ===========================================================================
plan_state_transition() {
  local plan_id="$1" from="$2" to="$3"

  _plan_state_require_deps || return 2
  _validate_plan_id "$plan_id" || return 1
  if [[ -z "$from" || -z "$to" ]]; then
    _plan_warn "plan_state_transition: from/to are required"
    return 1
  fi

  local pair="${from}:${to}" found=1 t
  for t in "${_AID_PLAN_TRANSITIONS[@]}"; do
    if [[ "$t" == "$pair" ]]; then
      found=0
      break
    fi
  done
  if [[ "$found" -ne 0 ]]; then
    echo "PRECONDITION FAIL: transition ${from} -> ${to} is not a legal pair in _AID_PLAN_TRANSITIONS for plan_id=$plan_id — rejected before any write" >&2
    return 1
  fi

  local path
  path="$(plan_state_path "$plan_id")"
  if [[ ! -f "$path" ]]; then
    _plan_warn "plan_state_transition: no state file for $plan_id at $path — run plan_state_init first"
    return 1
  fi

  local lock_path
  lock_path="$(_plan_lock_path "$plan_id")"
  aid_lock_acquire "$lock_path" "$AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S" || return 3
  local fd="$AID_LOCK_FD"

  local json rc
  json="$(_plan_state_read_raw_json "$path")"
  if [[ -z "$json" ]]; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: plan state file for $plan_id at $path is unreadable or unparseable YAML — offending key: plan_state" >&2
    return 5
  fi

  _plan_state_validate_json "$json" "$plan_id"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    aid_lock_release "$fd"
    return 5
  fi

  local current
  current="$(jq -r '.plan_state' <<<"$json")"
  if [[ "$current" != "$from" ]]; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: plan_state_transition: on-disk plan_state is '${current}', not the expected from-state '${from}' for plan_id=$plan_id — refusing (stale caller?)" >&2
    return 1
  fi

  local new_json
  new_json="$(jq --arg to "$to" '.plan_state = $to' <<<"$json")"
  if ! _plan_state_write_json "$path" "$new_json"; then
    aid_lock_release "$fd"
    _plan_warn "plan_state_transition: cannot write state file to $path"
    return 1
  fi

  aid_lock_release "$fd"
  return 0
}

# ===========================================================================
# plan_op_key <command> <plan_id> <stage> <attempt> <subject>
#
# Deterministic operation id: "<command>:<plan_id>:<stage>:<attempt>:<subject>".
# No timestamp, no random/entropy component — a resumed invocation with the
# same five inputs always derives the identical key (AC4), and every pair
# differing in ANY one component produces a distinct key (AC6), since none of
# these five fields are expected to contain a literal ':' (command names,
# plan ids, EPIC ids and the literal stage "-" this plan uses never do).
# ===========================================================================
plan_op_key() {
  local command="$1" plan_id="$2" stage="$3" attempt="$4" subject="$5"
  printf '%s:%s:%s:%s:%s\n' "$command" "$plan_id" "$stage" "$attempt" "$subject"
}

_plan_op_append() {
  local plan_id="$1" op_id="$2" command="$3" subject="$4" phase="$5" \
        expected_before_sha="$6" resulting_sha="$7"

  local dir ops_path lock_path
  dir="$(_plan_state_dir "$plan_id")"
  ops_path="$(_plan_ops_path "$plan_id")"
  lock_path="$(_plan_lock_path "$plan_id")"

  mkdir -p -- "$dir" 2>/dev/null || { _plan_warn "_plan_op_append: cannot create $dir"; return 1; }

  aid_lock_acquire "$lock_path" "$AID_PLAN_STATE_DEFAULT_LOCK_TIMEOUT_S" || return 3
  local fd="$AID_LOCK_FD"

  local now line
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="$(jq -nc \
    --arg op_id "$op_id" --arg command "$command" --arg subject "$subject" \
    --arg phase "$phase" --arg ebs "$expected_before_sha" \
    --arg rsha "$resulting_sha" --arg at "$now" \
    '{op_id: $op_id, command: $command, subject: $subject, phase: $phase,
      expected_before_sha: ($ebs | if . == "" then null else . end),
      resulting_sha: ($rsha | if . == "" then null else . end),
      at: $at}')"
  if [[ -z "$line" ]]; then
    aid_lock_release "$fd"
    _plan_warn "_plan_op_append: cannot build JSON record"
    return 1
  fi

  if ! printf '%s\n' "$line" >> "$ops_path"; then
    aid_lock_release "$fd"
    _plan_warn "_plan_op_append: cannot write to $ops_path"
    return 1
  fi

  aid_lock_release "$fd"
  return 0
}

# _plan_op_last_command_subject <plan_id> <op_id> — echoes
# "<command>\t<subject>" for the LAST record matching op_id (any phase).
# Used by plan_op_mark_git_applied/plan_op_commit so every record for one
# op_id carries the same command/subject (see the Edge Cases note in the
# file header about a command/key mismatch being treated as corrupt).
# Returns 1 (nothing on stdout) if no record exists yet, or if all parseable
# records do not match op_id (defensive — a corrupt line elsewhere must not
# block lookup of a valid record for this op_id, matching plan_op_reconcile's
# corruption isolation).
_plan_op_last_command_subject() {
  local plan_id="$1" op_id="$2" ops_path
  ops_path="$(_plan_ops_path "$plan_id")"
  [[ -f "$ops_path" ]] || return 1

  # Check if file ends with newline (to detect truncated final line).
  local ends_with_nl=true
  if [[ -n "$(tail -c1 -- "$ops_path" 2>/dev/null)" ]]; then
    ends_with_nl=false
  fi

  local -a lines=()
  mapfile -t lines < "$ops_path"
  local total="${#lines[@]}"

  local last_found="" i line_no content parsed is_last
  local op_field cmd subj

  for i in "${!lines[@]}"; do
    line_no=$((i + 1))
    content="${lines[$i]}"
    [[ -z "$content" ]] && continue

    is_last=false
    [[ "$line_no" -eq "$total" ]] && is_last=true

    # Truncated final line (crash mid-append) — never trusted, regardless
    # of whether it happens to parse (matches plan_op_reconcile).
    if [[ "$is_last" == true && "$ends_with_nl" == false ]]; then
      continue
    fi

    # Try to parse this line — skip if it fails.
    if ! parsed="$(jq -e -c '.' <<<"$content" 2>/dev/null)"; then
      continue
    fi

    # Check if this line matches our op_id.
    op_field="$(jq -r '.op_id // empty' <<<"$parsed" 2>/dev/null)"
    [[ "$op_field" == "$op_id" ]] || continue

    # Found a matching record — extract command and subject.
    cmd="$(jq -r '.command // empty' <<<"$parsed" 2>/dev/null)"
    subj="$(jq -r '.subject // empty' <<<"$parsed" 2>/dev/null)"
    [[ -n "$cmd" && -n "$subj" ]] && printf -v last_found '%s\t%s' "$cmd" "$subj"
  done

  [[ -n "$last_found" ]] || return 1
  printf '%s' "$last_found"
  return 0
}

# ===========================================================================
# plan_op_begin <plan_id> <op_id> <command> <subject> <expected_before_sha>
#
# Appends an `intent` record. `expected_before_sha` may be an empty string,
# recorded as JSON null.
#
# Returns: 0 success, 1 missing required arg, 3 lock timeout.
# ===========================================================================
plan_op_begin() {
  local plan_id="$1" op_id="$2" command="$3" subject="$4" expected_before_sha="${5:-}"

  _validate_plan_id "$plan_id" || return 1
  if [[ -z "$op_id" || -z "$command" || -z "$subject" ]]; then
    _plan_warn "plan_op_begin: op_id, command and subject are all required"
    return 1
  fi

  _plan_op_append "$plan_id" "$op_id" "$command" "$subject" "intent" "$expected_before_sha" ""
}

# ===========================================================================
# plan_op_mark_git_applied <plan_id> <op_id> <resulting_sha>
#
# Appends a `git_applied` record, reusing the command/subject from the last
# existing record for this op_id (requires plan_op_begin to have run first —
# there is no such thing as a git_applied record with no prior intent).
#
# Returns: 0 success, 1 missing required arg / no prior record for op_id,
# 3 lock timeout.
# ===========================================================================
plan_op_mark_git_applied() {
  local plan_id="$1" op_id="$2" resulting_sha="$3"

  _validate_plan_id "$plan_id" || return 1
  if [[ -z "$op_id" || -z "$resulting_sha" ]]; then
    _plan_warn "plan_op_mark_git_applied: op_id and resulting_sha are required"
    return 1
  fi

  local cs command subject
  if ! cs="$(_plan_op_last_command_subject "$plan_id" "$op_id")"; then
    _plan_warn "plan_op_mark_git_applied: no prior record found for op_id=$op_id (call plan_op_begin first)"
    return 1
  fi
  command="${cs%%$'\t'*}"
  subject="${cs#*$'\t'}"

  _plan_op_append "$plan_id" "$op_id" "$command" "$subject" "git_applied" "" "$resulting_sha"
}

# ===========================================================================
# plan_op_commit <plan_id> <op_id>
#
# Appends a `state_committed` record, reusing command/subject as above.
#
# Returns: 0 success, 1 missing required arg / no prior record for op_id,
# 3 lock timeout.
# ===========================================================================
plan_op_commit() {
  local plan_id="$1" op_id="$2"

  _validate_plan_id "$plan_id" || return 1
  if [[ -z "$op_id" ]]; then
    _plan_warn "plan_op_commit: op_id is required"
    return 1
  fi

  local cs command subject
  if ! cs="$(_plan_op_last_command_subject "$plan_id" "$op_id")"; then
    _plan_warn "plan_op_commit: no prior record found for op_id=$op_id (call plan_op_begin first)"
    return 1
  fi
  command="${cs%%$'\t'*}"
  subject="${cs#*$'\t'}"

  _plan_op_append "$plan_id" "$op_id" "$command" "$subject" "state_committed" "" ""
}

# ===========================================================================
# plan_op_reconcile <plan_id> <op_id>
#
# Lock-free scan of operations.jsonl for the LAST record matching op_id.
# Prints exactly one of: none, intent, git_applied, state_committed, aborted.
#
#   - No operations.jsonl at all, or no record matches op_id: prints "none",
#     returns 0.
#   - Otherwise prints the `phase` of the last matching record, returns 0.
#
# Corruption handling (never silent — see Error Handling in the file
# header):
#   - ANY line in the file (matching this op_id or not) that fails to parse
#     as JSON is skipped for status purposes, but its line number is
#     reported on stderr and the function returns 5 — "skipped for
#     reconciliation" is not the same as "safe to ignore".
#   - A final line with no trailing newline (a crash mid-append) is treated
#     as unparseable-for-this-purpose REGARDLESS of whether its partial
#     content happens to parse, for the same reason: a truncated write must
#     never be trusted at face value. This is how "reported as intent at
#     most, never as state_committed" is enforced for that specific record —
#     it is simply excluded, so the last COMPLETE record for the op_id wins.
#   - Two records sharing one op_id whose `command` fields disagree are
#     impossible by construction (command is part of the default key) —
#     encountering that combination is corruption, and returns 5 immediately.
#
# Returns: 0 clean reconcile (status on stdout), 5 corrupt data detected
# (best-effort status still printed on stdout; reason + line number on
# stderr).
# ===========================================================================
plan_op_reconcile() {
  local plan_id="$1" op_id="$2"

  _validate_plan_id "$plan_id" || return 1
  if [[ -z "$op_id" ]]; then
    _plan_warn "plan_op_reconcile: op_id is required"
    return 1
  fi

  local ops_path
  ops_path="$(_plan_ops_path "$plan_id")"
  if [[ ! -f "$ops_path" ]]; then
    echo "none"
    return 0
  fi

  local ends_with_nl=true
  if [[ -n "$(tail -c1 -- "$ops_path" 2>/dev/null)" ]]; then
    ends_with_nl=false
  fi

  local -a lines=()
  mapfile -t lines < "$ops_path"
  local total="${#lines[@]}"

  local last_phase="" bad_line_no="" seen_command=""
  local i line_no content parsed op_field phase_field command_field is_last

  for i in "${!lines[@]}"; do
    line_no=$((i + 1))
    content="${lines[$i]}"
    [[ -z "$content" ]] && continue

    is_last=false
    [[ "$line_no" -eq "$total" ]] && is_last=true

    if [[ "$is_last" == true && "$ends_with_nl" == false ]]; then
      # Truncated final line (crash mid-append) — never trusted, regardless
      # of whether it happens to parse.
      [[ -z "$bad_line_no" ]] && bad_line_no="$line_no"
      continue
    fi

    if ! parsed="$(jq -e -c '.' <<<"$content" 2>/dev/null)"; then
      [[ -z "$bad_line_no" ]] && bad_line_no="$line_no"
      continue
    fi

    op_field="$(jq -r '.op_id // empty' <<<"$parsed" 2>/dev/null)"
    [[ "$op_field" == "$op_id" ]] || continue

    command_field="$(jq -r '.command // empty' <<<"$parsed" 2>/dev/null)"
    if [[ -n "$command_field" ]]; then
      if [[ -n "$seen_command" && "$seen_command" != "$command_field" ]]; then
        echo "${last_phase:-none}"
        echo "PRECONDITION FAIL: operations.jsonl line $line_no for op_id=$op_id has command='$command_field', which disagrees with an earlier record's command='$seen_command' for the SAME op_id — corrupt (op_id/command pairing must be stable by construction)" >&2
        return 5
      fi
      seen_command="$command_field"
    fi

    phase_field="$(jq -r '.phase // empty' <<<"$parsed" 2>/dev/null)"
    [[ -n "$phase_field" ]] && last_phase="$phase_field"
  done

  if [[ -n "$bad_line_no" ]]; then
    echo "${last_phase:-none}"
    echo "PRECONDITION FAIL: operations.jsonl line $bad_line_no is not valid JSON (or is a truncated final line with no trailing newline) — skipped for reconciliation, but a truncated append must never be read as 'nothing happened'" >&2
    return 5
  fi

  echo "${last_phase:-none}"
  return 0
}

# ===========================================================================
# Standalone CLI — debugging / bats convenience only (see file header).
# ===========================================================================
_aid_plan_state_usage() {
  cat <<'EOF'
Usage: aid-plan-state.sh <subcommand> [args...]

Subcommands:
  state-path <plan_id>
  init <plan_id> <mode> <plan_branch> <target_branch>
  get <plan_id> <field>
  transition <plan_id> <from> <to>
  op-key <command> <plan_id> <stage> <attempt> <subject>
  op-begin <plan_id> <op_id> <command> <subject> <expected_before_sha>
  op-git-applied <plan_id> <op_id> <resulting_sha>
  op-commit <plan_id> <op_id>
  op-reconcile <plan_id> <op_id>
EOF
}

main() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    state-path)      plan_state_path "$@"; exit $? ;;
    init)             plan_state_init "$@"; exit $? ;;
    get)              plan_state_get "$@"; exit $? ;;
    transition)       plan_state_transition "$@"; exit $? ;;
    op-key)           plan_op_key "$@"; exit $? ;;
    op-begin)         plan_op_begin "$@"; exit $? ;;
    op-git-applied)   plan_op_mark_git_applied "$@"; exit $? ;;
    op-commit)        plan_op_commit "$@"; exit $? ;;
    op-reconcile)     plan_op_reconcile "$@"; exit $? ;;
    -h|--help|"")
      _aid_plan_state_usage
      [[ -z "$sub" ]] && exit 2
      exit 0
      ;;
    *)
      _aid_plan_state_usage >&2
      echo "ERROR: unknown subcommand: $sub" >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
