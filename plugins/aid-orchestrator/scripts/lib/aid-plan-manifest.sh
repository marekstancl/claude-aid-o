#!/usr/bin/env bash
# =============================================================================
# aid-plan-manifest.sh — plan-boundary-manifest.json producer/reader/updater +
# invariant enforcer (P064 "Plan Branch Substrate", EPIC E-064-1_2, Step 3).
#
# WHY THIS EXISTS: E-064-1_2 makes `plan/Pxxx` the integration branch for a
# plan's EPICs. `plan-boundary-manifest.json` is the C0 plan contract for that
# boundary — the artifact that lets the FSM, the gate resolver, the plan-final
# runner, C4 and the Reporter agree on what plan they are operating on after a
# context loss. Step 2 registered `plan_boundary_manifest` as a first-class
# AID protocol v2 artifact type (envelope + payload-key presence only, via
# `aid-protocol-validate.sh`) and its descriptive schema
# (`defaults/schemas/plan-boundary-manifest.schema.json`) — DELIBERATELY
# non-enforcing beyond that (every conditional field-level rule in that schema
# is annotated "NOT enforced here — see Step 3"). This file is that Step 3: it
# produces/reads/updates the manifest AND hand-writes every one of those
# deferred `jq -e` invariant checks (see "INVARIANT ENFORCEMENT" below).
#
# ── WHERE THE MANIFEST LIVES (deliberately NOT git-tracked) ─────────────────
#   .aid-o/work/plan-state/<plan_id>/plan-boundary-manifest.json
# Gitignored runtime area — same directory Step 1's plan-state.yaml and
# operations.jsonl live in, a sibling file, not a merge of the three. Writing
# it can therefore never move `candidate_sha` (a git-tracked artifact would
# make every manifest write a commit on the very branch this file describes
# the state of — a layering cycle this plan explicitly avoids). The manifest
# is a full AID protocol v2 artifact (envelope + `plan_boundary_manifest`
# payload key), NOT a plain YAML state file like plan-state.yaml — it is
# produced for downstream *consumers* (C4, Reporter, gate resolver), not only
# for this plan's own crash-resume bookkeeping.
#
# ── DATA MODEL (payload — see plan-boundary-manifest.schema.json for the
#    full descriptive shape; this file is the runtime source of truth for
#    which of those descriptive rules are actually enforced) ────────────────
#   plan_id, plan_branch, target_branch                  — identity/branching
#   plan_base_commit, target_branch_head_at_start,
#   target_branch_head_at_candidate_freeze, plan_branch_head, candidate_sha
#                                                          — the SHAs this
#                                                            plan's branch
#                                                            lifecycle tracks
#   plan_state, mode                                      — mirrors Step 1's
#                                                            plan-state.yaml
#                                                            enums (this file
#                                                            does not
#                                                            transition
#                                                            plan_state itself
#                                                            — a later step's
#                                                            aid-plan-fsm.sh
#                                                            owns that; this
#                                                            file only carries
#                                                            it forward via
#                                                            plan_manifest_update.
#                                                            The ONE exception,
#                                                            added by P068
#                                                            Step 1: the
#                                                            candidate
#                                                            freeze/clear pair
#                                                            below MUST move
#                                                            plan_state in the
#                                                            same atomic write
#                                                            as candidate_sha,
#                                                            because the
#                                                            candidate_sha
#                                                            invariant depends
#                                                            on it — split
#                                                            across two writes,
#                                                            either order fails
#                                                            validation or
#                                                            leaves a lie on
#                                                            disk. The
#                                                            plan-state.yaml
#                                                            file itself is
#                                                            still transitioned
#                                                            only by
#                                                            aid-plan-fsm.sh.)
#   epics, active_epics, total_epics                      — the EPIC set +
#                                                            currently-running
#                                                            subset
#   is_plan_final, epic_required_profile,
#   plan_final_required_profile                           — gate-profile
#                                                            state (see
#                                                            plan_manifest_raise_final_profile)
#   epic_runs[]                                            — one entry per
#                                                            EPIC's task-branch
#                                                            lifecycle
#   plan_final_run_id, plan_final_evidence_dir             — set together or
#                                                            not at all
#   candidate_frozen_at                                    — P068 Step 1. The
#                                                            RFC 3339 UTC
#                                                            instant of the
#                                                            freeze, written
#                                                            and cleared ONLY
#                                                            together with
#                                                            candidate_sha (see
#                                                            plan_manifest_freeze_candidate
#                                                            / _clear_candidate).
#                                                            This runtime field
#                                                            — NOT the
#                                                            .aid-lifecycle
#                                                            manifest — is the
#                                                            authoritative
#                                                            freeze time a PM
#                                                            decision's
#                                                            decided_at is
#                                                            checked against;
#                                                            only this write
#                                                            path can be atomic
#                                                            with candidate_sha.
#   candidate_invalidation_reason                          — P068 Step 1. Why
#                                                            the last candidate
#                                                            was discarded;
#                                                            informational.
#
# ── INVARIANT ENFORCEMENT (this file, NOT aid-protocol-validate.sh, NOT the
#    descriptive schema) ─────────────────────────────────────────────────────
# `plan_manifest_validate` runs three layers, first violation wins:
#   1. envelope + payload-key presence, by shelling out to the REAL
#      `aid-protocol-validate.sh` (Step 2) — never re-implemented here.
#   2. cross-field identity: payload.plan_id == identity.plan_id == the
#      plan_id argument, and plan_branch == "plan/" + plan_id.
#   3. the full invariant table (hand-written `jq -e` checks) + path
#      containment for every `evidence_dir` / `plan_final_evidence_dir`.
# See `_pm_check_invariants` below for the exhaustive, ordered list — it is
# the line-for-line implementation of this step's invariant table.
#
# ── ATOMICITY (every mutation) ───────────────────────────────────────────────
#   acquire lock (aid-lock.sh, sourced below) -> read (INSIDE the lock, so a
#   concurrent update can never lose a write — see `_plan_manifest_atomic_mutate`)
#   -> apply the jq filter -> write to `mktemp` IN THE SAME DIRECTORY -> run
#   the FULL `plan_manifest_validate` three-layer check against the temp file
#   -> `mv` only on success -> release lock. A jq filter that fails (bad
#   syntax, `error(...)` call, or produces non-JSON) leaves the canonical file
#   BYTE-IDENTICAL and returns 1 with the filter echoed to stderr. A temp file
#   that fails validation is discarded (never mv'd) and the function returns 1
#   (or 5 — see Error Handling). The canonical manifest is NEVER left on disk
#   in an invalid state by any function in this file.
#
# ── REVISION RESYNC (why every mutator, not just plan_manifest_get, touches
#    `.revision`) ─────────────────────────────────────────────────────────────
# `plan_manifest_validate --current-head <sha>` forwards to
# `aid-protocol-validate.sh`'s own `--current-head` check, which requires
# `.revision.head_sha` to equal the given sha (with `head_is_current`/
# `freshness` as a consistency sanity check on top) — so for that flag to mean
# anything at all, the manifest's envelope must stay in sync with the
# payload's own idea of "the head this reflects" (`plan_branch_head`).
# `_plan_manifest_atomic_mutate` therefore ALWAYS resyncs
# `.revision.head_sha = .plan_boundary_manifest.plan_branch_head` (and marks
# it current) as the last step of every jq filter it applies — a caller never
# has to remember to do this themselves.
#
# ── ERROR HANDLING (verbatim from the plan) ───────────────────────────────────
#   - A `jq` filter that produces invalid JSON leaves the original file in
#     place and returns 1 with the filter echoed to stderr.
#   - A manifest read for a plan that has no manifest returns `not_found` on
#     stdout and exit 1 — distinguishable from "corrupt" (exit 5).
#   - If `aid-protocol-validate.sh` is missing or non-executable, this
#     library returns 5 (fail CLOSED) rather than treating the manifest as
#     valid.
#
# ── EDGE CASES (verbatim from the plan) ───────────────────────────────────────
#   - `plan_manifest_add_epic` called twice for the same `epic_id` — the
#     second call updates the existing `epic_runs[]` entry in place (upsert),
#     never appends a duplicate.
#   - `plan_manifest_set_epic_status ... merged_to_plan` with NO merge_commit
#     argument — rejected, exit 1, before any write.
#   - A manifest hand-edited to point `plan_final_evidence_dir` at another
#     plan's directory — the containment check in `plan_manifest_validate`
#     fails, exit 1 (never silently trusted).
#   - Concurrent `plan_manifest_update` calls — serialized by the per-plan
#     lock; the second call re-reads the file INSIDE the lock, so it can never
#     clobber/lose the first call's write.
#
# ── PROJECT ROOT ─────────────────────────────────────────────────────────────
# CWD-relative by default, override with AID_PLAN_MANIFEST_PROJECT_ROOT (falls
# back to AID_PLAN_STATE_PROJECT_ROOT, then `pwd`) — matches Step 1's
# aid-plan-state.sh convention exactly (same runtime directory tree, same
# test-isolation knob), so a caller/test that already sets
# AID_PLAN_STATE_PROJECT_ROOT gets a consistent root for both libraries
# without having to set two variables.
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` — matches aid-plan-state.sh /
# aid-lock.sh / aid-gate-profile.sh. Every public function returns an
# explicit code.
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   Sourced (the real, intended usage):
#     source .../lib/aid-plan-manifest.sh
#     plan_manifest_init "P064" "plan/P064" "main" "$base_sha" "$head_sha" "plan_branch"
#     plan_manifest_add_epic "P064" "E-064-1_2" "R-E064-1" "task/E-064-1_2/main" \
#       "$epic_base_sha" "plan/P064" ".aid-o/work/evidence/E-064-1_2/"
#     plan_manifest_set_epic_status "P064" "E-064-1_2" "merged_to_plan" "$merge_sha"
#     plan_manifest_raise_final_profile "P064" "full"
#     plan_manifest_validate "P064" --current-head "$head_sha"
#
#   Standalone (debugging / bats convenience — see `main` below):
#     bash aid-plan-manifest.sh path <plan_id>
#     bash aid-plan-manifest.sh init <plan_id> <plan_branch> <target_branch> <base_sha> <target_head_sha> <mode>
#     bash aid-plan-manifest.sh get <plan_id> <jq_path>
#     bash aid-plan-manifest.sh update <plan_id> <jq_filter>
#     bash aid-plan-manifest.sh add-epic <plan_id> <epic_id> <run_id> <task_branch> <epic_base_commit> <epic_source_ref> <evidence_dir>
#     bash aid-plan-manifest.sh set-epic-status <plan_id> <epic_id> <status> [merge_commit]
#     bash aid-plan-manifest.sh raise-final-profile <plan_id> <profile>
#     bash aid-plan-manifest.sh validate <plan_id> [--current-head <sha>]
#
# Exit codes (functions, as `return`; standalone CLI mirrors them as `exit`):
#   0 = success (or a documented no-op, e.g. a downward profile "raise").
#   1 = precondition/usage failure (bad args, illegal status transition,
#       missing prior epic_runs entry, jq filter failure, invariant
#       violation, ...).
#   2 = missing jq on PATH.
#   3 = lock not acquired within the lease window.
#   5 = corrupt data detected (unparseable manifest JSON) OR
#       `aid-protocol-validate.sh` missing/non-executable (fail-closed) —
#       NEVER silently repaired or treated as valid.
#   `plan_manifest_get`/`plan_manifest_validate` also use 1 for the benign
#   "not_found" case (manifest doesn't exist yet) — see each function's own
#   doc comment for the exact stdout contract.
#
# **Last Updated:** 2026-07-25
# =============================================================================

_AID_PLAN_MANIFEST_LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_AID_PLAN_MANIFEST_LIBDIR}/aid-lock.sh"
# shellcheck disable=SC1091
source "${_AID_PLAN_MANIFEST_LIBDIR}/aid-gate-profile.sh"

AID_PLAN_MANIFEST_DEFAULT_LOCK_TIMEOUT_S=10
AID_PLAN_MANIFEST_PRODUCER="aid-plan-manifest.sh@1.0.0"

_pm_warn() {
  echo "WARN: aid-plan-manifest.sh: $*" >&2
}

# ---------------------------------------------------------------------------
# _pm_validate_plan_id_charset <plan_id> — non-empty, path-traversal-safe
# charset (mirrors aid-plan-state.sh's own guard). Used by every function
# that turns plan_id into a filesystem path. The STRICTER ^P[0-9]{3}$ format
# (this IS "the manifest layer" plan-state.sh's header refers to) is enforced
# separately in `plan_manifest_init` and as part of the invariant table in
# `plan_manifest_validate` — a caller reading/updating an already-existing
# manifest is not re-validated against the strict format on every call, only
# at creation and at the payload-invariant layer.
# ---------------------------------------------------------------------------
_pm_validate_plan_id_charset() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    _pm_warn "plan_id is empty"
    return 1
  fi
  if ! [[ "$pid" =~ ^[A-Za-z0-9_-]+$ ]]; then
    _pm_warn "plan_id '$pid' contains invalid characters (path traversal guard)"
    return 1
  fi
  return 0
}

_plan_manifest_require_jq() {
  command -v jq >/dev/null 2>&1 || { _pm_warn "jq not found on PATH"; return 2; }
  return 0
}

_plan_manifest_project_root() {
  printf '%s' "${AID_PLAN_MANIFEST_PROJECT_ROOT:-${AID_PLAN_STATE_PROJECT_ROOT:-$(pwd)}}"
}

# _plan_manifest_dir <plan_id> — the per-plan runtime directory (same
# directory Step 1's plan-state.yaml/operations.jsonl live in; not part of
# the required public API, matching aid-plan-state.sh's own `_plan_state_dir`
# convention).
_plan_manifest_dir() {
  printf '%s/.aid-o/work/plan-state/%s' "$(_plan_manifest_project_root)" "$1"
}

# plan_manifest_path <plan_id> — the manifest's canonical path.
plan_manifest_path() {
  printf '%s/plan-boundary-manifest.json' "$(_plan_manifest_dir "$1")"
}

_pm_lock_path() {
  printf '%s.lock' "$(plan_manifest_path "$1")"
}

# _pm_project_id [root] — best-effort project_id for the envelope's
# `identity.project_id` (the protocol validator rejects an empty one).
# Mirrors the established grep-based convention used elsewhere in this
# plugin (aid-invalidation-map.sh, aid-acceptance-evidence.sh,
# aid-consumption-proof.sh) rather than introducing a new lookup path.
_pm_project_id() {
  local root="${1:-$(_plan_manifest_project_root)}"
  local py pid=""
  py="$(find "$root" -path '*/.aid-o/config/project.yaml' -print -quit 2>/dev/null || true)"
  if [[ -n "$py" && -f "$py" ]]; then
    pid="$(grep -m1 'project_id:' "$py" 2>/dev/null | awk '{print $2}' | tr -d '"' || true)"
  fi
  [[ -z "$pid" || "$pid" == "null" ]] && pid="unknown"
  printf '%s' "$pid"
}

# ===========================================================================
# _pm_build_init_json <plan_id> <plan_branch> <target_branch> <base_sha>
#                      <target_head_sha> <mode>
# Emits the FULL protocol-v2 envelope + `plan_boundary_manifest` payload for
# a freshly-initialized plan (no EPICs yet). Echoes the JSON on stdout, or
# nothing on a jq build failure (caller checks emptiness).
# ===========================================================================
_pm_build_init_json() {
  local plan_id="$1" plan_branch="$2" target_branch="$3" base_sha="$4" \
        target_head_sha="$5" mode="$6"
  local now project_id subject_hash
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  project_id="$(_pm_project_id)"
  subject_hash="sha256:$(printf 'plan-boundary-manifest:%s' "$plan_id" | sha256sum | cut -d' ' -f1)"

  jq -n \
    --arg producer "$AID_PLAN_MANIFEST_PRODUCER" \
    --arg created_at "$now" \
    --arg project_id "$project_id" \
    --arg plan_id "$plan_id" \
    --arg subject_hash "$subject_hash" \
    --arg plan_branch "$plan_branch" \
    --arg target_branch "$target_branch" \
    --arg base_sha "$base_sha" \
    --arg target_head_sha "$target_head_sha" \
    --arg mode "$mode" \
    '{
      schema_version: "aid-2.0",
      artifact_type: "plan_boundary_manifest",
      producer: $producer,
      created_at: $created_at,
      control_protocol: "aid-2.0",
      identity: {project_id: $project_id, plan_id: $plan_id},
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $base_sha, head_is_current: true, freshness: "current"},
      status: "pass",
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-plan-manifest.sh"},
      plan_boundary_manifest: {
        plan_id: $plan_id,
        plan_branch: $plan_branch,
        target_branch: $target_branch,
        plan_base_commit: $base_sha,
        target_branch_head_at_start: $target_head_sha,
        target_branch_head_at_candidate_freeze: null,
        plan_branch_head: $base_sha,
        candidate_sha: null,
        candidate_frozen_at: null,
        candidate_invalidation_reason: null,
        plan_state: "OPEN",
        mode: $mode,
        epics: [],
        active_epics: [],
        total_epics: 0,
        is_plan_final: false,
        epic_required_profile: "standard",
        plan_final_required_profile: "standard",
        epic_runs: [],
        plan_final_run_id: null,
        plan_final_evidence_dir: null,
        plan_final_evidence_ref: null,
        plan_final_evidence_receipt_sha256: null,
        plan_final_close_evidence_ref: null,
        plan_final_close_evidence_receipt_sha256: null
      }
    }'
}

# ===========================================================================
# _pm_check_invariants <plan_id> <file>
#
# The hand-written `jq -e` implementation of this step's ENTIRE invariant
# table (see file header "INVARIANT ENFORCEMENT"). First violation wins;
# prints "PRECONDITION FAIL: ... offending field: <field>" (or an equivalent
# descriptive message) to stderr and returns 1. Called ONLY from
# `_plan_manifest_validate_file`, after envelope (Layer 1) and cross-field
# identity (Layer 2) have both already passed — every check below may assume
# `.plan_boundary_manifest` exists and is an object.
# ===========================================================================
_pm_check_invariants() {
  local plan_id="$1" file="$2"
  local f

  # ── required fields present (non-null) ──────────────────────────────────
  local -a required_fields=(
    plan_id plan_branch target_branch plan_base_commit
    target_branch_head_at_start plan_branch_head plan_state mode
    epics active_epics total_epics is_plan_final
    epic_required_profile plan_final_required_profile epic_runs
  )
  for f in "${required_fields[@]}"; do
    if ! jq -e --arg f "$f" '.plan_boundary_manifest[$f] != null' "$file" >/dev/null 2>&1; then
      echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: $f (missing)" >&2
      return 1
    fi
  done

  # ── required fields non-empty (strings) + well-formed IDs ───────────────
  local -a nonempty_string_fields=(
    plan_id plan_branch target_branch plan_state mode
    epic_required_profile plan_final_required_profile
  )
  for f in "${nonempty_string_fields[@]}"; do
    if ! jq -e --arg f "$f" '(.plan_boundary_manifest[$f] | type == "string") and (.plan_boundary_manifest[$f] | length > 0)' "$file" >/dev/null 2>&1; then
      echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: $f (empty or non-string)" >&2
      return 1
    fi
  done
  if ! jq -e '.plan_boundary_manifest.plan_id | test("^P[0-9]{3}$")' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: plan_id (must match ^P[0-9]{3}\$)" >&2
    return 1
  fi
  if ! jq -e '.plan_boundary_manifest.plan_branch | test("^plan/P[0-9]{3}$")' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: plan_branch (must match ^plan/P[0-9]{3}\$)" >&2
    return 1
  fi

  # ── SHA fields match ^[0-9a-f]{40}$ ──────────────────────────────────────
  local -a required_sha_fields=(plan_base_commit target_branch_head_at_start plan_branch_head)
  for f in "${required_sha_fields[@]}"; do
    if ! jq -e --arg f "$f" '(.plan_boundary_manifest[$f] // "") | test("^[0-9a-f]{40}$")' "$file" >/dev/null 2>&1; then
      echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: $f (must match ^[0-9a-f]{40}\$)" >&2
      return 1
    fi
  done
  local -a nullable_sha_fields=(candidate_sha target_branch_head_at_candidate_freeze)
  for f in "${nullable_sha_fields[@]}"; do
    if ! jq -e --arg f "$f" '(.plan_boundary_manifest[$f] == null) or ((.plan_boundary_manifest[$f] | type == "string") and (.plan_boundary_manifest[$f] | test("^[0-9a-f]{40}$")))' "$file" >/dev/null 2>&1; then
      echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: $f (non-null must match ^[0-9a-f]{40}\$)" >&2
      return 1
    fi
  done

  # ── epics: unique, well-formed IDs ───────────────────────────────────────
  if ! jq -e '(.plan_boundary_manifest.epics | length) == (.plan_boundary_manifest.epics | unique | length)' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — epics array has a duplicate" >&2
    return 1
  fi
  if ! jq -e '[.plan_boundary_manifest.epics[] | test("^E-[0-9]{3}-[0-9]+_[0-9]+$")] | all' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — epics contains a malformed EPIC id" >&2
    return 1
  fi

  # ── active_epics ⊆ epics ──────────────────────────────────────────────────
  if ! jq -e '(.plan_boundary_manifest.active_epics - .plan_boundary_manifest.epics | length) == 0' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — active_epics is not a subset of epics" >&2
    return 1
  fi

  # ── total_epics == epics length ──────────────────────────────────────────
  if ! jq -e '.plan_boundary_manifest.total_epics == (.plan_boundary_manifest.epics | length)' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — total_epics != (epics | length)" >&2
    return 1
  fi

  # ── candidate_sha non-null requires a late plan_state ────────────────────
  # F3 (2026-07-27, PM-authorized scope extension): ABORTED belongs in this set.
  # An aborted plan RETAINS its abandoned candidate on purpose — it is the proof
  # of what was refused, the abort message names it, and the close record asserts
  # the target branch is unchanged against it. Excluding ABORTED here meant the
  # abort path could not mirror its own transition into the manifest, so
  # `plan-state` kept reporting AWAITING_PM for a plan the authoritative
  # plan-state.yaml had already marked ABORTED. The alternatives were both worse:
  # clearing the candidate destroys the evidence, and tolerating the stale mirror
  # leaves every reader with a false answer. ROLLED_BACK (2026-07-27) is here for
  # the same reason: a rolled-back plan keeps the candidate that WAS merged and
  # then reverted — that SHA is half the rollback record.
  if ! jq -e '(.plan_boundary_manifest.candidate_sha == null) or (.plan_boundary_manifest.plan_state as $s | ["PLAN_GATES","PLAN_REVIEW","AWAITING_PM","PLAN_MERGING","CLOSED","ABORTED","ROLLED_BACK"] | index($s) != null)' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — candidate_sha is set while plan_state is too early (not in PLAN_GATES/PLAN_REVIEW/AWAITING_PM/PLAN_MERGING/CLOSED/ABORTED/ROLLED_BACK)" >&2
    return 1
  fi

  # ── candidate_frozen_at: null, or an RFC 3339 UTC instant ────────────────
  # P068 Step 1. Deliberately strict: only the `Z` (UTC) form is accepted, so
  # a freeze time can never be recorded in a local offset a later comparison
  # (Step 5's decided_at check) would have to normalise. The regex also pins
  # the field length, which rejects the "2026-07-25" date-only shape.
  if ! jq -e '(.plan_boundary_manifest.candidate_frozen_at == null) or ((.plan_boundary_manifest.candidate_frozen_at | type == "string") and (.plan_boundary_manifest.candidate_frozen_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — offending field: candidate_frozen_at (non-null must be an RFC 3339 UTC instant, e.g. 2026-07-25T09:31:04Z)" >&2
    return 1
  fi

  # ── candidate_sha / candidate_frozen_at are null or non-null TOGETHER ─────
  # The freeze binding is the PAIR, never either half: a candidate with no
  # freeze time cannot be validated against a PM decision's decided_at, and a
  # freeze time with no candidate names an instant at which nothing was
  # frozen. Enforced in BOTH directions so neither a partial freeze nor a
  # partial invalidation can ever reach disk (P068 Step 1).
  if ! jq -e '.plan_boundary_manifest as $m | (($m.candidate_sha == null) and ($m.candidate_frozen_at == null)) or (($m.candidate_sha != null) and ($m.candidate_frozen_at != null))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — candidate_sha and candidate_frozen_at must be null/non-null together (the freeze binding is the pair; a half-written freeze or half-cleared invalidation is rejected before it reaches disk)" >&2
    return 1
  fi

  # ── plan-final runtime binding and durable receipt are complete tuples ───
  # The ignored run directory is only a working projection.  Once review
  # passes, its technical receipt is sealed in a separate Git ref; keeping a
  # half-pointer would recreate the exact worktree-loss ambiguity this layer
  # exists to prevent.
  if ! jq -e '((.plan_boundary_manifest.plan_final_run_id == null) and (.plan_boundary_manifest.plan_final_evidence_dir == null) and (.plan_boundary_manifest.plan_final_evidence_ref == null) and (.plan_boundary_manifest.plan_final_evidence_receipt_sha256 == null)) or ((.plan_boundary_manifest.plan_final_run_id != null) and (.plan_boundary_manifest.plan_final_evidence_dir != null) and (.plan_boundary_manifest.plan_final_evidence_ref == null) and (.plan_boundary_manifest.plan_final_evidence_receipt_sha256 == null)) or ((.plan_boundary_manifest.plan_final_run_id != null) and (.plan_boundary_manifest.plan_final_evidence_dir != null) and (.plan_boundary_manifest.plan_final_evidence_ref != null) and (.plan_boundary_manifest.plan_final_evidence_receipt_sha256 != null))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — runtime run/directory must be paired; durable receipt ref/hash are either both absent before review or both present after review" >&2
    return 1
  fi
  # ── P073 Step 15: the protected set is bound to the CANDIDATE ────────────
  # It is non-empty exactly when a candidate is frozen, and cleared with it.
  # A half-cleared manifest — a protected set with no candidate, or a
  # candidate with none — would let Step 16's equivalence predicate reason
  # about a surface nobody froze, which is worse than having no predicate.
  # LEGACY TOLERANCE: a manifest frozen before this field existed has neither,
  # and Step 16 reports "equivalence unavailable" for it rather than guessing.
  if ! jq -e '
      .plan_boundary_manifest as $m
      | ($m.protected_paths == null and $m.protected_paths_complete == null)
        or (($m.candidate_sha != null)
            and ($m.protected_paths | type == "array")
            and ($m.protected_paths | length > 0)
            and ($m.protected_paths_complete | type == "boolean"))
    ' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — protected_paths must be a non-empty array with a boolean protected_paths_complete exactly when candidate_sha is set, and cleared together with it" >&2
    return 1
  fi
  # accepted_head (Step 16) may exist only alongside a frozen candidate, and
  # its receipt path/hash travel together — the manifest binding names the
  # authoritative receipt, never a directory listing.
  if ! jq -e '
      .plan_boundary_manifest as $m
      | ($m.accepted_head == null)
        or (($m.candidate_sha != null)
            and ($m.accepted_head | type == "string")
            and ($m.accepted_head | test("^[0-9a-f]{40}$"))
            and ($m.equivalence_receipt_path | type == "string")
            and ($m.equivalence_receipt_path | length > 0)
            and ($m.equivalence_receipt_sha256 | type == "string")
            and ($m.equivalence_receipt_sha256 | test("^(sha256:)?[0-9a-f]{64}$")))
    ' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — accepted_head requires a frozen candidate and a receipt path+sha256 recorded with it" >&2
    return 1
  fi
  if ! jq -e '(.plan_boundary_manifest.plan_final_evidence_ref == null) or (.plan_boundary_manifest.plan_final_evidence_ref as $r | ($r | type == "string") and ($r | test("^refs/heads/aid-evidence/P[0-9]{3}/[0-9a-f]{40}/[A-Za-z0-9._-]+$")))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_evidence_ref is malformed" >&2
    return 1
  fi
  if ! jq -e '(.plan_boundary_manifest.plan_final_evidence_receipt_sha256 == null) or (.plan_boundary_manifest.plan_final_evidence_receipt_sha256 as $r | ($r | type == "string") and ($r | test("^sha256:[0-9a-f]{64}$")))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_evidence_receipt_sha256 is malformed" >&2
    return 1
  fi
  # ── the CLOSE-time durable receipt: paired, well-formed, and never present
  #    without the review receipt it comes after (IMP-466 item 4) ──────────
  if ! jq -e '((.plan_boundary_manifest.plan_final_close_evidence_ref == null) and (.plan_boundary_manifest.plan_final_close_evidence_receipt_sha256 == null)) or ((.plan_boundary_manifest.plan_final_close_evidence_ref != null) and (.plan_boundary_manifest.plan_final_close_evidence_receipt_sha256 != null) and (.plan_boundary_manifest.plan_final_evidence_ref != null))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_close_evidence_ref/receipt_sha256 must be null/non-null together and never present without the review receipt" >&2
    return 1
  fi
  if ! jq -e '(.plan_boundary_manifest.plan_final_close_evidence_ref == null) or (.plan_boundary_manifest.plan_final_close_evidence_ref as $r | ($r | type == "string") and ($r | test("^refs/heads/aid-evidence-close/P[0-9]{3}/[0-9a-f]{40}/[A-Za-z0-9._-]+$")))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_close_evidence_ref is malformed" >&2
    return 1
  fi
  if ! jq -e '(.plan_boundary_manifest.plan_final_close_evidence_receipt_sha256 == null) or (.plan_boundary_manifest.plan_final_close_evidence_receipt_sha256 as $r | ($r | type == "string") and ($r | test("^sha256:[0-9a-f]{64}$")))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_close_evidence_receipt_sha256 is malformed" >&2
    return 1
  fi

  # ── IMP-464 (D2): the C3 plan-diff input hash, when present, must be
  # well-formed AND bound to THIS manifest's current candidate — a value left
  # over from a prior candidate is not a producer/review-time-atomic binding,
  # it is a stale claim. ────────────────────────────────────────────────────
  if ! jq -e '
    (.plan_boundary_manifest.plan_final_inputs == null) or (
      .plan_boundary_manifest.plan_final_inputs as $pi |
      ($pi | type == "object") and
      ($pi.plan_diff_sha256 | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      ($pi.candidate_sha | type == "string" and test("^[0-9a-f]{40}$")) and
      ($pi.run_id | type == "string" and length > 0) and
      (.plan_boundary_manifest.candidate_sha == null or $pi.candidate_sha == .plan_boundary_manifest.candidate_sha) and
      (.plan_boundary_manifest.plan_final_run_id == null or $pi.run_id == .plan_boundary_manifest.plan_final_run_id) and
      ($pi.ac_lens_required | type == "boolean") and
      ($pi.plan_diff_verdict | type == "string" and (. == "present" or . == "absent" or . == "skipped"))
    )
  ' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_inputs is malformed or bound to a stale candidate" >&2
    return 1
  fi

  # ── epic_runs[]: required subfields present ──────────────────────────────
  local -a epic_run_required=(epic_id run_id task_branch epic_base_commit lineage evidence_dir status)
  for f in "${epic_run_required[@]}"; do
    if ! jq -e --arg f "$f" '[.plan_boundary_manifest.epic_runs[] | .[$f] != null] | all' "$file" >/dev/null 2>&1; then
      echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — an epic_runs[] entry is missing required field: $f" >&2
      return 1
    fi
  done

  # ── epic_runs[].epic_base_commit is a 40-hex sha ─────────────────────────
  if ! jq -e '[.plan_boundary_manifest.epic_runs[].epic_base_commit] | all(test("^[0-9a-f]{40}$"))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — an epic_runs[].epic_base_commit is not a 40-hex sha" >&2
    return 1
  fi

  # ── epic_runs[].epic_merge_commit: null or 40-hex sha ────────────────────
  if ! jq -e '[.plan_boundary_manifest.epic_runs[] | (.epic_merge_commit == null) or ((.epic_merge_commit | type == "string") and (.epic_merge_commit | test("^[0-9a-f]{40}$")))] | all' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — an epic_runs[].epic_merge_commit is non-null and not a 40-hex sha" >&2
    return 1
  fi

  # ── epic_merge_commit non-null requires status: merged_to_plan ──────────
  if ! jq -e '[.plan_boundary_manifest.epic_runs[] | (.epic_merge_commit == null) or (.status == "merged_to_plan")] | all' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — an epic_runs[] entry has epic_merge_commit set but status != merged_to_plan" >&2
    return 1
  fi

  # ── every epic_runs[].epic_id is a member of epics ───────────────────────
  if ! jq -e '[.plan_boundary_manifest.epic_runs[].epic_id] as $ids | ($ids - .plan_boundary_manifest.epics | length) == 0' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — an epic_runs[].epic_id is not a member of epics" >&2
    return 1
  fi

  # ── path containment: plan_final_evidence_dir ────────────────────────────
  # NOTE: `.plan_final_evidence_dir | startswith(<expr using .plan_id>)`
  # would be WRONG — once piped into `.plan_final_evidence_dir`, `.` inside
  # the startswith(...) argument is the evidence_dir STRING, not the root
  # object, so `.plan_boundary_manifest.plan_id` would try to index a
  # string. Bind the payload with `as $m` FIRST so both sides of the
  # comparison read from the original object, not the post-pipe value.
  if ! jq -e '.plan_boundary_manifest as $m | ($m.plan_final_evidence_dir == null) or (($m.plan_final_evidence_dir | startswith(".aid-o/work/evidence/" + $m.plan_id + "/")) and (($m.plan_final_evidence_dir | test("\\.\\.")) | not))' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — plan_final_evidence_dir fails containment (must start with .aid-o/work/evidence/<plan_id>/ and contain no ..)" >&2
    return 1
  fi

  # ── path containment: epic_runs[].evidence_dir ───────────────────────────
  # Same `as $e` binding for the same reason: .evidence_dir and .epic_id
  # must both be read from the ORIGINAL entry, not from the post-pipe string.
  if ! jq -e '[.plan_boundary_manifest.epic_runs[] | . as $e | ($e.evidence_dir | startswith(".aid-o/work/evidence/" + $e.epic_id + "/")) and (($e.evidence_dir | test("\\.\\.")) | not)] | all' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest invariant violated for plan_id=$plan_id — an epic_runs[].evidence_dir fails containment (must start with .aid-o/work/evidence/<epic_id>/ and contain no ..)" >&2
    return 1
  fi

  return 0
}

# ===========================================================================
# _plan_manifest_validate_file <plan_id> <file> [--current-head <sha>]
#
# The three-layer check (see file header), applied to an ARBITRARY file path
# — used both by the public `plan_manifest_validate` (against the canonical
# path) and internally by every mutator (against its mktemp candidate, BEFORE
# `mv`). Assumes <file> exists and the caller already knows it does (an
# absent canonical path is handled by the public wrapper as "not_found").
#
# Returns: 0 valid, 1 any layer-1/2/3 violation, 5 unparseable JSON OR
# aid-protocol-validate.sh missing/non-executable (fail-closed).
# ===========================================================================
_plan_manifest_validate_file() {
  local plan_id="$1" file="$2"; shift 2
  local current_head=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --current-head) current_head="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  if ! jq -e . "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest.json for $plan_id at $file is not valid JSON" >&2
    return 5
  fi

  # Layer 1: envelope + payload-key presence, via the REAL validator.
  local validator="${_AID_PLAN_MANIFEST_LIBDIR}/../aid-protocol-validate.sh"
  if [[ ! -f "$validator" || ! -x "$validator" ]]; then
    echo "PRECONDITION FAIL: aid-protocol-validate.sh missing or non-executable at $validator — failing CLOSED, NOT treating the manifest as valid" >&2
    return 5
  fi
  local validate_out rc=0
  if [[ -n "$current_head" ]]; then
    validate_out="$(bash "$validator" "$file" --current-head "$current_head" 2>&1)" || rc=$?
  else
    validate_out="$(bash "$validator" "$file" 2>&1)" || rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan-boundary-manifest envelope validation failed for plan_id=$plan_id: ${validate_out}" >&2
    return 1
  fi

  # Layer 2: cross-field identity.
  if ! jq -e --arg pid "$plan_id" '.identity.plan_id == $pid and .plan_boundary_manifest.plan_id == .identity.plan_id' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest identity mismatch for plan_id=$plan_id — payload.plan_id must equal identity.plan_id" >&2
    return 1
  fi
  if ! jq -e '.plan_boundary_manifest.plan_branch == ("plan/" + .plan_boundary_manifest.plan_id)' "$file" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest plan_branch must equal 'plan/' + plan_id for plan_id=$plan_id" >&2
    return 1
  fi

  # Layer 3: the full invariant table + containment.
  _pm_check_invariants "$plan_id" "$file" || return 1

  return 0
}

# ===========================================================================
# plan_manifest_init <plan_id> <plan_branch> <target_branch> <base_sha>
#                     <target_head_sha> <mode>
#
# Creates a fresh manifest (no EPICs yet, plan_state=OPEN). Refuses to
# overwrite an existing one (never a silent reset — matches
# plan_state_init's own convention). Prints the manifest path on success.
#
# Returns: 0 success, 1 bad args / already exists / build or validate
# failure, 2 missing jq, 3 lock timeout, 5 corrupt-on-write (should be
# unreachable for a freshly-built manifest; surfaced rather than swallowed).
# ===========================================================================
plan_manifest_init() {
  local plan_id="$1" plan_branch="$2" target_branch="$3" base_sha="$4" \
        target_head_sha="$5" mode="$6"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1

  if ! [[ "$plan_id" =~ ^P[0-9]{3}$ ]]; then
    _pm_warn "plan_manifest_init: plan_id must match ^P[0-9]{3}\$ (got '${plan_id}')"
    return 1
  fi
  if [[ "$plan_branch" != "plan/${plan_id}" ]]; then
    _pm_warn "plan_manifest_init: plan_branch must be exactly 'plan/${plan_id}' (got '${plan_branch:-<empty>}')"
    return 1
  fi
  if [[ -z "$target_branch" ]]; then
    _pm_warn "plan_manifest_init: target_branch is required"
    return 1
  fi
  if ! [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]]; then
    _pm_warn "plan_manifest_init: base_sha must match ^[0-9a-f]{40}\$ (got '${base_sha:-<empty>}')"
    return 1
  fi
  if ! [[ "$target_head_sha" =~ ^[0-9a-f]{40}$ ]]; then
    _pm_warn "plan_manifest_init: target_head_sha must match ^[0-9a-f]{40}\$ (got '${target_head_sha:-<empty>}')"
    return 1
  fi
  case "$mode" in
    plan_branch|legacy_epic_release_mode) ;;
    *)
      _pm_warn "plan_manifest_init: mode must be 'plan_branch' or 'legacy_epic_release_mode' (got '${mode:-<empty>}')"
      return 1
      ;;
  esac

  local dir path
  dir="$(_plan_manifest_dir "$plan_id")"
  path="$(plan_manifest_path "$plan_id")"

  if [[ -f "$path" ]]; then
    _pm_warn "plan_manifest_init: manifest already exists for $plan_id at $path — refusing to overwrite (never a silent reset)"
    return 1
  fi

  mkdir -p -- "$dir" 2>/dev/null || { _pm_warn "plan_manifest_init: cannot create $dir"; return 1; }

  local lock_path fd
  lock_path="$(_pm_lock_path "$plan_id")"
  aid_lock_acquire "$lock_path" "$AID_PLAN_MANIFEST_DEFAULT_LOCK_TIMEOUT_S" || return 3
  fd="$AID_LOCK_FD"

  # Re-check under the lock — closes the TOCTOU window against a concurrent
  # init winning the race between the check above and acquiring the lock.
  if [[ -f "$path" ]]; then
    aid_lock_release "$fd"
    _pm_warn "plan_manifest_init: manifest appeared for $plan_id while acquiring the lock — refusing to overwrite"
    return 1
  fi

  local json
  json="$(_pm_build_init_json "$plan_id" "$plan_branch" "$target_branch" "$base_sha" "$target_head_sha" "$mode")"
  if [[ -z "$json" ]]; then
    aid_lock_release "$fd"
    _pm_warn "plan_manifest_init: cannot build initial manifest JSON"
    return 1
  fi

  local tmp="${path}.tmp.$$"
  printf '%s' "$json" > "$tmp" 2>/dev/null || { rm -f "$tmp"; aid_lock_release "$fd"; _pm_warn "plan_manifest_init: cannot write $tmp"; return 1; }

  local vrc=0
  _plan_manifest_validate_file "$plan_id" "$tmp" || vrc=$?
  if [[ "$vrc" -ne 0 ]]; then
    rm -f "$tmp"
    aid_lock_release "$fd"
    return "$vrc"
  fi

  if ! mv -- "$tmp" "$path"; then
    rm -f "$tmp"
    aid_lock_release "$fd"
    _pm_warn "plan_manifest_init: cannot move $tmp to $path"
    return 1
  fi

  aid_lock_release "$fd"
  echo "$path"
  return 0
}

# ===========================================================================
# plan_manifest_get <plan_id> <jq_path>
#
# Lock-free read of one jq expression against the FULL manifest JSON (e.g.
# ".plan_boundary_manifest.plan_state") — matches plan_state_get's
# lock-free-read convention (an atomic mktemp+mv write is torn-safe against a
# concurrent reader).
#
# Returns 0 with the value on stdout on success. Returns 1 with "not_found"
# on stdout when no manifest exists yet. Returns 1 (nothing on stdout) when
# the manifest is valid JSON but the expression evaluates to null/empty.
# Returns 5 (nothing on stdout, reason on stderr) when the manifest is not
# valid JSON, or the jq_path expression itself fails to evaluate.
# ===========================================================================
plan_manifest_get() {
  local plan_id="$1" jq_path="$2"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if [[ -z "$jq_path" ]]; then
    _pm_warn "plan_manifest_get: jq_path is required"
    return 1
  fi

  local path; path="$(plan_manifest_path "$plan_id")"
  if [[ ! -f "$path" ]]; then
    echo "not_found"
    return 1
  fi

  if ! jq -e . "$path" >/dev/null 2>&1; then
    echo "PRECONDITION FAIL: plan-boundary-manifest.json for $plan_id at $path is not valid JSON" >&2
    return 5
  fi

  local val rc=0
  val="$(jq -r "$jq_path" "$path" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "PRECONDITION FAIL: plan_manifest_get: jq_path '$jq_path' failed against $path: ${val}" >&2
    return 5
  fi
  if [[ -z "$val" || "$val" == "null" ]]; then
    return 1
  fi
  printf '%s\n' "$val"
  return 0
}

# ===========================================================================
# _plan_manifest_atomic_mutate <plan_id> <jq_filter> [jq_extra_args...]
#
# THE shared write path every mutator (plan_manifest_update,
# plan_manifest_add_epic, plan_manifest_set_epic_status,
# plan_manifest_raise_final_profile) funnels through. `jq_extra_args` are
# passed straight to `jq` BEFORE the filter (e.g. `--arg epic_id "$epic_id"
# --argjson entry "$entry_json"`) — callers bind their own variables this way
# instead of string-interpolating into the filter, so there is no
# quoting/injection concern anywhere in this file.
#
# acquire lock -> re-check existence INSIDE the lock (not_found is only ever
# reported here, never assumed from a pre-lock check — see Edge Cases in the
# header) -> apply filter (+ the `.revision` resync, see header) -> write
# mktemp -> validate mktemp (full three-layer plan_manifest_validate) -> mv
# only on success -> release lock.
# ===========================================================================
_plan_manifest_atomic_mutate() {
  local plan_id="$1" jq_filter="$2"; shift 2
  local -a jq_extra_args=("$@")

  local path; path="$(plan_manifest_path "$plan_id")"

  if [[ ! -f "$path" ]]; then
    echo "not_found"
    return 1
  fi

  local lock_path fd
  lock_path="$(_pm_lock_path "$plan_id")"
  aid_lock_acquire "$lock_path" "$AID_PLAN_MANIFEST_DEFAULT_LOCK_TIMEOUT_S" || return 3
  fd="$AID_LOCK_FD"

  # Re-check under the lock (TOCTOU-safe) AND re-read the canonical file
  # INSIDE the lock — this is what makes concurrent updates safe: the second
  # of two racing callers reads the FIRST caller's already-written result,
  # never the pre-lock snapshot (Edge Case, file header).
  if [[ ! -f "$path" ]]; then
    aid_lock_release "$fd"
    echo "not_found"
    return 1
  fi

  local full_filter="( ${jq_filter} ) | .revision.head_sha = .plan_boundary_manifest.plan_branch_head | .revision.head_is_current = true | .revision.freshness = \"current\""

  local new_json jrc=0
  new_json="$(jq "${jq_extra_args[@]}" "$full_filter" "$path" 2>&1)" || jrc=$?
  if [[ "$jrc" -ne 0 ]]; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: jq filter failed for plan_id=$plan_id — filter: ${jq_filter}" >&2
    echo "jq error: ${new_json}" >&2
    return 1
  fi
  if [[ -z "$new_json" ]] || ! jq -e . >/dev/null 2>&1 <<<"$new_json"; then
    aid_lock_release "$fd"
    echo "PRECONDITION FAIL: jq filter produced invalid/empty JSON for plan_id=$plan_id — filter: ${jq_filter}" >&2
    return 1
  fi

  local tmp="${path}.tmp.$$"
  printf '%s' "$new_json" > "$tmp" 2>/dev/null || { rm -f "$tmp"; aid_lock_release "$fd"; _pm_warn "cannot write $tmp"; return 1; }

  local vrc=0
  _plan_manifest_validate_file "$plan_id" "$tmp" || vrc=$?
  if [[ "$vrc" -ne 0 ]]; then
    rm -f "$tmp"
    aid_lock_release "$fd"
    [[ "$vrc" -eq 5 ]] && return 5
    return 1
  fi

  if ! mv -- "$tmp" "$path"; then
    rm -f "$tmp"
    aid_lock_release "$fd"
    _pm_warn "cannot move $tmp to $path"
    return 1
  fi

  aid_lock_release "$fd"
  return 0
}

# ===========================================================================
# plan_manifest_update <plan_id> <jq_filter>
#
# The generic public mutator — applies an arbitrary jq_filter (operating on
# the FULL envelope+payload JSON, e.g.
# `.plan_boundary_manifest.plan_state = "PLAN_SYNC"`) atomically.
#
# Returns: 0 success, 1 bad args / not_found / jq failure / invariant
# violation, 2 missing jq, 3 lock timeout, 5 corrupt / validator missing.
# ===========================================================================
plan_manifest_update() {
  local plan_id="$1" jq_filter="$2"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if [[ -z "$jq_filter" ]]; then
    _pm_warn "plan_manifest_update: jq_filter is required"
    return 1
  fi

  _plan_manifest_atomic_mutate "$plan_id" "$jq_filter"
}

# ===========================================================================
# plan_manifest_add_epic <plan_id> <epic_id> <run_id> <task_branch>
#                         <epic_base_commit> <epic_source_ref> <evidence_dir>
#                         [lineage]
#
# Upserts one `epic_runs[]` entry (Edge Case: a second call for the SAME
# epic_id updates the existing entry in place, never appends a duplicate),
# and ensures `epics`/`active_epics`/`total_epics` reflect it. New entries
# start `status: running`, `epic_merge_commit: null`.
#
# The OPTIONAL 8th positional `lineage` defaults to "unproven" (IMP-265:
# fail-closed by default). An omitted lineage argument is NOT an authorisation
# claim — only the legitimate producer that actually observed the branch's
# origin at branch-creation time (epic-start, via `_pfsm_epic_finish_write`)
# may assert "proven", and it now does so EXPLICITLY by passing the 8th
# positional. A forgetful or future caller that omits it gets "unproven", so a
# missing argument can never silently mint provenance. Callers that cannot
# authorise a lineage claim — repair above all — also pass "unproven"
# explicitly, so the entry is created ALREADY unproven in a single atomic
# write. Writing proven first and flipping afterwards is forbidden: a crash
# between the two writes would leave a false `proven` on disk, which is
# exactly the authorisation state an attacker wants. Only "proven" and
# "unproven" are accepted; anything else (including a malformed value) returns
# 1 and writes nothing — never coerced to proven.
#
# Returns: 0 success, 1 bad args / not_found / invariant violation, 2
# missing jq, 3 lock timeout, 5 corrupt / validator missing.
# ===========================================================================
plan_manifest_add_epic() {
  local plan_id="$1" epic_id="$2" run_id="$3" task_branch="$4" \
        epic_base_commit="$5" epic_source_ref="$6" evidence_dir="$7" \
        lineage="${8:-unproven}"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if [[ -z "$epic_id" || -z "$run_id" || -z "$task_branch" || -z "$epic_base_commit" || -z "$evidence_dir" ]]; then
    _pm_warn "plan_manifest_add_epic: epic_id, run_id, task_branch, epic_base_commit and evidence_dir are all required"
    return 1
  fi
  if [[ "$lineage" != "proven" && "$lineage" != "unproven" ]]; then
    _pm_warn "plan_manifest_add_epic: lineage must be exactly 'proven' or 'unproven' (got '${lineage}') — nothing written"
    return 1
  fi

  local entry
  entry="$(jq -n \
    --arg epic_id "$epic_id" --arg run_id "$run_id" --arg task_branch "$task_branch" \
    --arg epic_base_commit "$epic_base_commit" --arg evidence_dir "$evidence_dir" \
    --arg epic_source_ref "$epic_source_ref" --arg lineage "$lineage" \
    '{epic_id: $epic_id, run_id: $run_id, task_branch: $task_branch,
      epic_base_commit: $epic_base_commit,
      epic_source_ref: (if $epic_source_ref == "" then null else $epic_source_ref end),
      lineage: $lineage, epic_merge_commit: null,
      evidence_dir: $evidence_dir, status: "running"}')"
  if [[ -z "$entry" ]]; then
    _pm_warn "plan_manifest_add_epic: cannot build epic_runs entry JSON"
    return 1
  fi

  local filter
  filter='
    .plan_boundary_manifest.epics = (if (.plan_boundary_manifest.epics | index($epic_id)) then .plan_boundary_manifest.epics else .plan_boundary_manifest.epics + [$epic_id] end)
    | .plan_boundary_manifest.epic_runs = (
        (.plan_boundary_manifest.epic_runs // []) as $runs
        | if any($runs[]; .epic_id == $epic_id)
          then [$runs[] | if .epic_id == $epic_id then $entry else . end]
          else $runs + [$entry]
          end
      )
    | .plan_boundary_manifest.total_epics = (.plan_boundary_manifest.epics | length)
    | .plan_boundary_manifest.active_epics = (if (.plan_boundary_manifest.active_epics | index($epic_id)) then .plan_boundary_manifest.active_epics else .plan_boundary_manifest.active_epics + [$epic_id] end)
  '

  _plan_manifest_atomic_mutate "$plan_id" "$filter" --arg epic_id "$epic_id" --argjson entry "$entry"
}

# ===========================================================================
# EPIC STATUS TRANSITION TABLE — defines legal state-machine edges
#
# Epic status lifecycle: pending → running → merged_to_plan/abandoned/superseded/blocked.
# Blocked is a temporary hold (runnable again). Terminal states (merged_to_plan,
# abandoned, superseded) have no outgoing edges — once an epic is merged/abandoned/
# superseded, it does not transition further within this plan.
#
# The table below lists EVERY legal "from:to" pair. plan_manifest_set_epic_status
# rejects any transition not in this table, leaving the entry unchanged, before
# taking the lock or touching the file.
#
# CLASSIFICATION (tested via negative tests in bats suite):
#   - Terminal states (no outgoing edges): merged_to_plan, abandoned, superseded
#   - Active/temporary: pending, running, blocked (have legal outgoing edges)
#
# The one existing real caller (_pfsm_plan_state_repair) invokes
# plan_manifest_set_epic_status with status=merged_to_plan from running, which
# MUST remain legal — confirmed by AC7/AC8/--repair tests.
# ===========================================================================
_AID_EPIC_STATUS_TRANSITIONS=(
  "pending:running"
  "pending:blocked"
  "pending:abandoned"
  "pending:superseded"
  # F2 (2026-07-27): "pending:merged_to_plan" REMOVED. A pending EPIC never
  # completed anything, so allowing it to become merged_to_plan let unfinished
  # work into the plan candidate — the P067 dogfood did exactly that. The only
  # route into merged_to_plan is now from `running`, and epic-merge-to-plan
  # additionally requires a successful, task-SHA-bound epic-complete.
  "running:merged_to_plan"
  "running:blocked"
  "running:abandoned"
  "running:superseded"
  "blocked:running"
  "blocked:abandoned"
  "blocked:superseded"
)

# ===========================================================================
# plan_manifest_set_epic_status <plan_id> <epic_id> <status> [merge_commit]
#
# Sets an EXISTING epic_runs[] entry's status (rejected — exit 1, no write —
# if epic_id has no prior entry; use plan_manifest_add_epic first). Validates
# the status transition against _AID_EPIC_STATUS_TRANSITIONS BEFORE taking the
# lock or touching the file — rejects any illegal transition (reason on stderr,
# nothing written, exit 1). If the transition is legal, reads the current on-disk
# status, re-validates it matches the expected "from" state, then writes the
# new status.
#
# Also keeps `active_epics` in sync: `status: running` adds epic_id (if absent),
# any other status removes it (if present).
#
# Edge Case: `status: merged_to_plan` with NO merge_commit argument is
# rejected, exit 1, before any write. `merge_commit` may ONLY be given
# together with `status: merged_to_plan` (rejected otherwise, matching the
# invariant `plan_manifest_validate` would enforce anyway — caught here
# earlier, before touching the lock).
#
# Returns: 0 success, 1 bad args / unknown epic_id / illegal transition /
# invariant violation, 2 missing jq, 3 lock timeout, 5 corrupt / validator missing.
# ===========================================================================
plan_manifest_set_epic_status() {
  local plan_id="$1" epic_id="$2" status="$3" merge_commit="${4:-}"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if [[ -z "$epic_id" ]]; then
    _pm_warn "plan_manifest_set_epic_status: epic_id is required"
    return 1
  fi

  # CRITICAL (Bug Fix #2): Validate epic_id format BEFORE any jq-filter-text
  # interpolation to prevent injection attacks. Must match the manifest
  # invariant's epic-id pattern.
  if ! [[ "$epic_id" =~ ^E-[0-9]{3}-[0-9]+_[0-9]+$ ]]; then
    _pm_warn "plan_manifest_set_epic_status: epic_id must match format ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${epic_id}'). This check prevents jq injection."
    return 1
  fi

  case "$status" in
    pending|running|merged_to_plan|abandoned|superseded|blocked) ;;
    *)
      _pm_warn "plan_manifest_set_epic_status: unknown status '${status:-<empty>}'"
      return 1
      ;;
  esac
  if [[ "$status" == "merged_to_plan" && -z "$merge_commit" ]]; then
    _pm_warn "plan_manifest_set_epic_status: status=merged_to_plan requires a merge_commit argument"
    return 1
  fi
  if [[ "$status" != "merged_to_plan" && -n "$merge_commit" ]]; then
    _pm_warn "plan_manifest_set_epic_status: merge_commit may only be given together with status=merged_to_plan"
    return 1
  fi

  local mc_json
  if [[ -n "$merge_commit" ]]; then
    mc_json="$(jq -n --arg mc "$merge_commit" '$mc')"
  else
    mc_json="null"
  fi

  # CRITICAL FIX for Bug #1 (TOCTOU race): The transition-legality decision
  # must happen INSIDE the jq filter (which runs under the lock, after re-reading
  # the file) — NOT in bash BEFORE taking the lock. This prevents a race where
  # two concurrent callers read the same stale current_status, both decide their
  # transition is legal, and the second write clobbers the first even if that
  # clobber violates the transition table.
  #
  # The jq filter below inlines the legal transitions table and checks:
  #   1. The epic_id exists in epic_runs[]
  #   2. Its current status (read under the lock) pairs validly with the target status
  #   3. Only if valid, update the status and active_epics list
  #   4. If invalid, error out (leaving the file untouched), caught by
  #      _plan_manifest_atomic_mutate's error trap
  #
  # This is the same pattern used in plan_manifest_raise_final_profile (commit
  # 02c4d75): comparison logic inlined into the jq filter, running under the lock.
  local filter='
    # Define the legal transitions as an array of "from:to" strings
    ["pending:running", "pending:blocked", "pending:abandoned", "pending:superseded", "running:merged_to_plan", "running:blocked", "running:abandoned", "running:superseded", "blocked:running", "blocked:abandoned", "blocked:superseded"] as $legal_transitions |
    if (.plan_boundary_manifest.epic_runs | any(.epic_id == $epic_id))
    then
      # Found the epic entry — now extract its current status and validate the transition
      (.plan_boundary_manifest.epic_runs[] | select(.epic_id == $epic_id) | .status) as $current_status |
      ($current_status + ":" + $status) as $transition_pair |
      if ($legal_transitions | index($transition_pair)) != null
      then
        # Transition is legal — proceed with the update
        .plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == $epic_id then (.status = $status | .epic_merge_commit = $merge_commit) else . end]
        | .plan_boundary_manifest.active_epics = (
            if $status == "running"
            then (if (.plan_boundary_manifest.active_epics | index($epic_id)) then .plan_boundary_manifest.active_epics else .plan_boundary_manifest.active_epics + [$epic_id] end)
            else [.plan_boundary_manifest.active_epics[] | select(. != $epic_id)]
            end
          )
      else
        # Transition is illegal — reject with a clear error message
        error("plan_manifest_set_epic_status: transition " + $current_status + " -> " + $status + " is not a legal pair for epic_id " + $epic_id)
      end
    else
      error("plan_manifest_set_epic_status: epic_id not found in epic_runs: " + $epic_id)
    end
  '

  _plan_manifest_atomic_mutate "$plan_id" "$filter" --arg epic_id "$epic_id" --arg status "$status" --argjson merge_commit "$mc_json"
}

# ===========================================================================
# plan_manifest_raise_final_profile <plan_id> <profile>
#
# Raises `plan_final_required_profile` to max(current, profile) — the profile
# can only move UP the rank table (quick=0 < targeted=1 < standard=2 <
# full=3 < release=4). A lower-or-equal-ranked `profile` is a documented
# NO-OP (no write) — never an error.
#
# The rank comparison happens INSIDE the jq filter passed to
# _plan_manifest_atomic_mutate, i.e. under the lock, against the file's LIVE
# value at write time — not via a lock-free bash-side pre-computation. This
# is required for correctness: two concurrent callers racing to raise the
# profile to different targets must never let the lower one clobber the
# higher one once it lands (see the "Regression: concurrent
# raise_final_profile calls never downgrade" bats test). Every call
# therefore takes the lock, including a call whose outcome turns out to be a
# no-op — the no-op is decided under the lock, not before it.
#
# Returns: 0 success or no-op, 1 bad profile name / not_found / corrupt
# propagated from the read, 2 missing jq, 3 lock timeout, 5 corrupt /
# validator missing.
# ===========================================================================
plan_manifest_raise_final_profile() {
  local plan_id="$1" profile="$2"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if ! gate_profile_rank "$profile" >/dev/null 2>&1; then
    _pm_warn "plan_manifest_raise_final_profile: unknown profile '${profile:-<empty>}'"
    return 1
  fi

  # CRITICAL FIX for race condition: The profile comparison and max-computation
  # must happen INSIDE the jq filter (which runs under the lock, after re-reading
  # the file) — NOT in bash BEFORE taking the lock. This prevents a downgrade
  # when two concurrent callers race (B writes "release", then A writes "full",
  # downgrading the value from "release" to "full").
  #
  # The jq filter below inlines the profile rank table and does the comparison
  # against the file's LIVE value at write time, under the lock. The filter is
  # idempotent: if the target profile is already at or below the current rank,
  # the filter leaves the file unchanged (via the `else .` branch).
  #
  # Profile rank table (matching aid-gate-profile.sh): quick=0 < targeted=1
  # < standard=2 < full=3 < release=4.
  local filter='
    {quick:0,targeted:1,standard:2,full:3,release:4} as $ranks |
    ((.plan_boundary_manifest.plan_final_required_profile as $current | $ranks[$current]) // 0) as $current_rank |
    ($ranks[$profile] // 0) as $new_rank |
    if $new_rank > $current_rank
    then .plan_boundary_manifest.plan_final_required_profile = $profile
    else .
    end
  '

  _plan_manifest_atomic_mutate "$plan_id" "$filter" --arg profile "$profile"
}

# ===========================================================================
# plan_manifest_freeze_candidate <plan_id> <candidate_sha> <target_head_sha>
#                                 <plan_final_run_id> <plan_final_evidence_dir>
#                                 [frozen_at]
#
# P068 Step 1 — THE candidate freeze write, and the only sanctioned way to set
# `candidate_sha`. It is ONE `_plan_manifest_atomic_mutate` call, so every
# field that makes a candidate meaningful lands in the same temp-file →
# validate → rename, or none of them does:
#
#   candidate_sha, candidate_frozen_at,
#   target_branch_head_at_candidate_freeze,
#   plan_final_run_id, plan_final_evidence_dir,
#   plan_state = PLAN_GATES, candidate_invalidation_reason = null
#
# WHY the timestamp is written HERE and nowhere else: this library already
# owns `candidate_sha`, so this is the only write path that can make the pair
# atomic. Putting the freeze time in the `.aid-lifecycle` manifest instead
# would put it behind a DIFFERENT artifact's write path, where a crash between
# the two writes leaves a candidate with no freeze time (or a freeze time with
# no candidate) — exactly the state Step 5's decided_at check cannot
# adjudicate. The pair invariant in _pm_check_invariants makes that
# unreachable: a half-written freeze fails validation on the temp file and is
# never renamed into place.
#
# `plan_state` MUST move in the same write because the manifest's own
# candidate_sha invariant requires a late plan_state — writing the SHA first
# and the state second would fail validation, and the reverse order would
# leave PLAN_GATES recorded with no candidate.
#
# `frozen_at` defaults to now (UTC, RFC 3339 `Z`); it is a parameter only so
# tests and a crash-resume can reproduce an exact instant. A malformed value
# is rejected here AND again by the invariant.
#
# Returns: 0 success, 1 bad args / not_found / invariant violation, 2 missing
# jq, 3 lock timeout, 5 corrupt / validator missing.
# ===========================================================================
plan_manifest_freeze_candidate() {
  local plan_id="$1" candidate_sha="$2" target_head="$3" run_id="$4" \
        evidence_dir="$5" frozen_at="${6:-}" protected_file="${7:-}" \
        protected_complete="${8:-true}"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1

  if ! [[ "$candidate_sha" =~ ^[0-9a-f]{40}$ ]]; then
    _pm_warn "plan_manifest_freeze_candidate: candidate_sha must be a 40-hex sha (got '${candidate_sha:-<empty>}')"
    return 1
  fi
  if ! [[ "$target_head" =~ ^[0-9a-f]{40}$ ]]; then
    _pm_warn "plan_manifest_freeze_candidate: target_branch_head_at_candidate_freeze must be a 40-hex sha (got '${target_head:-<empty>}')"
    return 1
  fi
  if [[ -z "$run_id" || -z "$evidence_dir" ]]; then
    _pm_warn "plan_manifest_freeze_candidate: plan_final_run_id and plan_final_evidence_dir are both required"
    return 1
  fi

  [[ -n "$frozen_at" ]] || frozen_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! [[ "$frozen_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    _pm_warn "plan_manifest_freeze_candidate: frozen_at must be an RFC 3339 UTC instant (got '${frozen_at}')"
    return 1
  fi

  # P073 Step 15: the PROTECTED PATH SET is written in the SAME atomic mutate
  # as the candidate pair. It is the delivery surface the frozen review
  # describes — every step's plan.json allowed_paths, the source plan, the
  # lifecycle manifest, the close-consumed receipts — and Step 16's equivalence
  # predicate refuses any commit that touches it. Storing it here rather than
  # recomputing at read time is what makes it a property OF THIS FREEZE: a
  # later plan.json edit cannot retroactively change what was protected.
  #
  # The caller passes a NUL-DELIMITED file. Paths are arbitrary strings: an
  # argv list breaks on the first odd one, and newline delimiting corrupts a
  # path that CONTAINS a newline — one delivery path silently becomes two
  # entries, neither of which is the real path (adversarial-review finding).
  # NUL is the only separator git itself guarantees cannot occur in a path.
  local protected_json='[]'
  if [[ -z "$protected_file" ]]; then
    # The pre-P073 six-argument call. Accepting it silently would store a
    # deliberately too-small protected set and mark the freeze complete, so it
    # is refused by name instead.
    _pm_warn "plan_manifest_freeze_candidate: a protected-paths file is REQUIRED (7th argument). A freeze with no protected set cannot support review equivalence and must not look as if it does."
    return 1
  fi
  if [[ ! -r "$protected_file" ]]; then
    _pm_warn "plan_manifest_freeze_candidate: protected-paths file '${protected_file}' is not readable"
    return 1
  fi
  protected_json="$(jq -sR '[splits("\u0000") | select(length > 0)] | sort | unique' < "$protected_file" 2>/dev/null)" || protected_json='[]'
  if [[ -z "$protected_json" ]]; then protected_json='[]'; fi
  case "$protected_complete" in
    true|false) ;;
    *) _pm_warn "plan_manifest_freeze_candidate: protected_paths_complete must be true or false (got '${protected_complete}')"; return 1 ;;
  esac
  # The three lifecycle paths are the FLOOR: the set is never silently empty,
  # because an empty protected set would make every commit look ancillary.
  if [[ "$(jq 'length' <<<"$protected_json")" -eq 0 ]]; then
    protected_json="$(jq -n --arg p "$plan_id" '[
        (".aid-lifecycle/manifests/" + $p + ".yaml"),
        (".aid-lifecycle/receipts/" + $p + ".yaml")
      ] | sort | unique')"
    protected_complete=false
  fi

  local filter='
    .plan_boundary_manifest.candidate_sha = $candidate_sha
    | .plan_boundary_manifest.candidate_frozen_at = $frozen_at
    | .plan_boundary_manifest.target_branch_head_at_candidate_freeze = $target_head
    | .plan_boundary_manifest.plan_final_run_id = $run_id
    | .plan_boundary_manifest.plan_final_evidence_dir = $evidence_dir
    | .plan_boundary_manifest.protected_paths = $protected_paths
    | .plan_boundary_manifest.protected_paths_complete = ($protected_complete == "true")
    | .plan_boundary_manifest.accepted_head = null
    | .plan_boundary_manifest.equivalence_receipt_path = null
    | .plan_boundary_manifest.equivalence_receipt_sha256 = null
    | .plan_boundary_manifest.candidate_invalidation_reason = null
    | .plan_boundary_manifest.plan_state = "PLAN_GATES"
  '

  _plan_manifest_atomic_mutate "$plan_id" "$filter" \
    --argjson protected_paths "$protected_json" \
    --arg protected_complete "$protected_complete" \
    --arg candidate_sha "$candidate_sha" \
    --arg frozen_at "$frozen_at" \
    --arg target_head "$target_head" \
    --arg run_id "$run_id" \
    --arg evidence_dir "$evidence_dir"
}

# ===========================================================================
# plan_manifest_clear_candidate <plan_id> <reason> <target_plan_state>
#
# P068 Step 1 — the exact inverse of plan_manifest_freeze_candidate, and the
# only sanctioned way to clear `candidate_sha`. One atomic write clears ALL
# FIVE plan-final fields together (candidate_sha, candidate_frozen_at,
# target_branch_head_at_candidate_freeze, plan_final_run_id,
# plan_final_evidence_dir), records `candidate_invalidation_reason` and moves
# `plan_state` to the CALLER-SUPPLIED target.
#
# The target state is a parameter, not a constant: the same field-clearing
# serves two recovery paths that land in different states — PLAN_FIX (a review
# fix) and PLAN_SYNC (a stale-authorization or conflict resynchronisation).
# Hard-coding PLAN_FIX would make the resync path inexpressible.
#
# Clearing `candidate_frozen_at` in the SAME write is what makes a PM decision
# bound to the previous candidate unable to satisfy the next one: after an
# invalidation there is no freeze time at all, and the next freeze mints a new
# one, so a `decided_at` from before the invalidation can never fall after it.
#
# NOTE: this function does NOT delete the run directory the cleared
# `plan_final_evidence_dir` pointed at. Prior run directories are immutable by
# construction — each freeze allocates a fresh `R-<plan_id>-final-<N>`.
#
# Returns: 0 success, 1 bad args / not_found / illegal target state /
# invariant violation, 2 missing jq, 3 lock timeout, 5 corrupt.
# ===========================================================================
plan_manifest_clear_candidate() {
  local plan_id="$1" reason="$2" target_state="$3"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if [[ -z "$reason" ]]; then
    _pm_warn "plan_manifest_clear_candidate: a reason is required — an unexplained invalidation is not recordable"
    return 1
  fi
  case "$target_state" in
    PLAN_FIX|PLAN_SYNC) ;;
    *)
      _pm_warn "plan_manifest_clear_candidate: target_plan_state must be PLAN_FIX or PLAN_SYNC (got '${target_state:-<empty>}')"
      return 1
      ;;
  esac

  local filter='
    .plan_boundary_manifest.candidate_sha = null
    | .plan_boundary_manifest.candidate_frozen_at = null
    | .plan_boundary_manifest.target_branch_head_at_candidate_freeze = null
    | .plan_boundary_manifest.plan_final_run_id = null
    | .plan_boundary_manifest.plan_final_evidence_dir = null
    | .plan_boundary_manifest.plan_final_evidence_ref = null
    | .plan_boundary_manifest.plan_final_evidence_receipt_sha256 = null
    | .plan_boundary_manifest.plan_final_close_evidence_ref = null
    | .plan_boundary_manifest.plan_final_close_evidence_receipt_sha256 = null
    | .plan_boundary_manifest.plan_final_inputs = null
    | .plan_boundary_manifest.protected_paths = null
    | .plan_boundary_manifest.protected_paths_complete = null
    | .plan_boundary_manifest.accepted_head = null
    | .plan_boundary_manifest.equivalence_receipt_path = null
    | .plan_boundary_manifest.equivalence_receipt_sha256 = null
    | .plan_boundary_manifest.candidate_invalidation_reason = $reason
    | .plan_boundary_manifest.plan_state = $target_state
  '

  _plan_manifest_atomic_mutate "$plan_id" "$filter" \
    --arg reason "$reason" --arg target_state "$target_state"
}

# ===========================================================================
# plan_manifest_set_accepted_head <plan_id> <accepted_head> <receipt_path>
#                                  <receipt_sha256>
#
# P073 Step 16 — the ONE sanctioned mutator for review-equivalence acceptance.
# All three fields move together in a single atomic mutate: the manifest
# binding is what names the AUTHORITATIVE receipt, so a head without its
# receipt (or a receipt hash that does not travel with the path) would leave
# the merge unable to tell which of several receipt files authorised it.
#
# candidate_sha is deliberately NOT touched. The PM authorised a review of
# that exact commit; equivalence asserts the review still describes the
# delivery, never that something else was reviewed.
#
# Returns: 0 success, 1 bad args / invariant violation, 2 missing jq,
# 3 lock timeout, 5 corrupt.
# ===========================================================================
plan_manifest_set_accepted_head() {
  local plan_id="$1" head="$2" receipt_path="$3" receipt_sha="$4"
  # COMPARE-AND-SWAP inputs. `_plan_manifest_atomic_mutate` re-reads the file
  # under its lock, so a guard expressed in the jq filter is a true CAS: the
  # second of two racing acceptances sees the first one's committed result and
  # refuses instead of overwriting it. Callers that pass neither degrade to the
  # old unguarded set, so the guard is opt-in but the FSM always passes it.
  local expect_candidate="${5:-}" expect_prior="${6:-}"

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1
  if ! [[ "$head" =~ ^[0-9a-f]{40}$ ]]; then
    _pm_warn "plan_manifest_set_accepted_head: accepted_head must be a 40-hex sha (got '${head:-<empty>}')"
    return 1
  fi
  if [[ -z "$receipt_path" ]]; then
    _pm_warn "plan_manifest_set_accepted_head: a receipt path is required — the manifest binding is what names the authoritative receipt"
    return 1
  fi
  if ! [[ "$receipt_sha" =~ ^(sha256:)?[0-9a-f]{64}$ ]]; then
    _pm_warn "plan_manifest_set_accepted_head: receipt sha256 is malformed (got '${receipt_sha:-<empty>}')"
    return 1
  fi

  local guard=""
  if [[ -n "$expect_candidate" ]]; then
    guard='
    (if (.plan_boundary_manifest.candidate_sha // "") != $ecand
       then error("CAS FAILED: candidate_sha is now \(.plan_boundary_manifest.candidate_sha // "null"), not the \($ecand) this acceptance was decided against")
       else . end)
    | (if ((.plan_boundary_manifest.accepted_head // "") != $eprior)
       then error("CAS FAILED: accepted_head is now \(.plan_boundary_manifest.accepted_head // "null"), not the \(if $eprior == "" then "null" else $eprior end) this acceptance saw — another acceptance won the race")
       else . end)
    | '
  fi

  # The write touches ONLY the three acceptance fields. candidate_sha,
  # protected_paths and the frozen review binding are read by the guard and
  # never assigned — an acceptance must not be able to move the thing it is
  # being compared against.
  local filter="${guard}"'
    .plan_boundary_manifest.accepted_head = $head
    | .plan_boundary_manifest.equivalence_receipt_path = $rpath
    | .plan_boundary_manifest.equivalence_receipt_sha256 = $rsha
  '
  _plan_manifest_atomic_mutate "$plan_id" "$filter" \
    --arg head "$head" --arg rpath "$receipt_path" --arg rsha "$receipt_sha" \
    --arg ecand "$expect_candidate" --arg eprior "$expect_prior"
}

# ===========================================================================
# plan_manifest_validate <plan_id> [--current-head <sha>]
#
# The public three-layer validator (see file header "INVARIANT ENFORCEMENT")
# against the CANONICAL manifest path for plan_id.
#
# Returns: 0 valid, 1 not_found ("not_found" on stdout) / any layer
# violation, 2 missing jq, 5 unparseable JSON / aid-protocol-validate.sh
# missing or non-executable (fail-closed).
# ===========================================================================
plan_manifest_validate() {
  local plan_id="$1"; shift
  local current_head=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --current-head) current_head="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  _plan_manifest_require_jq || return 2
  _pm_validate_plan_id_charset "$plan_id" || return 1

  local path; path="$(plan_manifest_path "$plan_id")"
  if [[ ! -f "$path" ]]; then
    echo "not_found"
    return 1
  fi

  if [[ -n "$current_head" ]]; then
    _plan_manifest_validate_file "$plan_id" "$path" --current-head "$current_head"
  else
    _plan_manifest_validate_file "$plan_id" "$path"
  fi
}

# ===========================================================================
# Standalone CLI — debugging / bats convenience only (see file header).
# ===========================================================================
_aid_plan_manifest_usage() {
  cat <<'EOF'
Usage: aid-plan-manifest.sh <subcommand> [args...]

Subcommands:
  path <plan_id>
  init <plan_id> <plan_branch> <target_branch> <base_sha> <target_head_sha> <mode>
  get <plan_id> <jq_path>
  update <plan_id> <jq_filter>
  add-epic <plan_id> <epic_id> <run_id> <task_branch> <epic_base_commit> <epic_source_ref> <evidence_dir>
  set-epic-status <plan_id> <epic_id> <status> [merge_commit]
  raise-final-profile <plan_id> <profile>
  freeze-candidate <plan_id> <candidate_sha> <target_head_sha> <run_id> <evidence_dir> [frozen_at]
  clear-candidate <plan_id> <reason> <PLAN_FIX|PLAN_SYNC>
  validate <plan_id> [--current-head <sha>]
EOF
}

main() {
  local sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    path)                 plan_manifest_path "$@"; exit $? ;;
    init)                 plan_manifest_init "$@"; exit $? ;;
    get)                  plan_manifest_get "$@"; exit $? ;;
    update)                plan_manifest_update "$@"; exit $? ;;
    add-epic)              plan_manifest_add_epic "$@"; exit $? ;;
    set-epic-status)       plan_manifest_set_epic_status "$@"; exit $? ;;
    raise-final-profile)   plan_manifest_raise_final_profile "$@"; exit $? ;;
    freeze-candidate)      plan_manifest_freeze_candidate "$@"; exit $? ;;
    clear-candidate)       plan_manifest_clear_candidate "$@"; exit $? ;;
    validate)              plan_manifest_validate "$@"; exit $? ;;
    -h|--help|"")
      _aid_plan_manifest_usage
      [[ -z "$sub" ]] && exit 2
      exit 0
      ;;
    *)
      _aid_plan_manifest_usage >&2
      echo "ERROR: unknown subcommand: $sub" >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
