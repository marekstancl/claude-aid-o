#!/usr/bin/env bash
# aid-test-isolation-experiment.sh — P069 Step 6.
#
# The mechanical implementation of "no design may claim parallel-safe
# without attached isolation evidence." Runs a CANDIDATE SET of catalog
# run_units N times (default 5) CONCURRENTLY, strictly inside a disposable
# `git worktree` — NEVER the live project checkout — and promotes to
# safe/constrained ONLY on zero shared-state assertion failures (every
# trial's per-unit outcome matches that unit's own solo baseline) and no
# timing-order dependence (alternating launch order across trials never
# changes any outcome).
#
# Every solo baseline AND every trial gets its OWN fresh worktree (Codex
# review, real finding: a single worktree reused across all runs lets one
# run's leftover files/mutations contaminate the next, producing false
# promotions or false divergences — the very thing this step exists to
# prevent).
#
# Never writes to the approved, force-tracked
# .aid-o/config/test-scheduler-parallel-overlay.yaml — only to its own
# gitignored .aid-o/work/test-audits/<run-id>/scheduler-overlay.proposed.json
# (status: proposed), conforming to Step 5's
# scheduler-parallel-overlay.schema.json. aid-scheduler-overlay-approve.sh
# (Step 5) is the ONLY path to status: approved.
#
# Disposable-worktree creation failure fails closed as `unknown` (exit
# nonzero, no promotion) — never falls back to probing the live tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"
# shellcheck source=lib/aid-test-execution-unit.sh
source "${SCRIPT_DIR}/lib/aid-test-execution-unit.sh"

OVERLAY_SCHEMA="${SCHEMAS_DIR}/scheduler-parallel-overlay.schema.json"

_die() { echo "aid-test-isolation-experiment.sh: $2" >&2; exit "$1"; }

# ── Cleanup bookkeeping — GLOBAL, never `local` (Codex review: a `local`
# variable referenced by a trap can go out of scope, e.g. becoming an
# unbound-variable error under `set -u`, once the function that declared it
# has already returned by the time the trap actually fires — the exact bug
# hit and fixed in Step 5). The trap handler below is a real function
# reading only these globals, never a synthesized shell-source string
# (Codex review: interpolating $project_root/$worktree_path directly into a
# trap's command STRING re-parses them as shell source when the trap
# fires — a path containing a `"`, backtick, or `$(...)` would inject
# arbitrary commands into the cleanup step itself).
_ISO_PROJECT_ROOT=""
_ISO_CURRENT_WORKTREE=""
_ISO_CURRENT_JOBS_DIR=""

_iso_cleanup() {
  # Cancel every still-outstanding job under the CURRENT jobs dir before
  # removing the worktree those jobs are running inside of (Codex review:
  # an unexpected error must never force-remove a worktree out from under
  # still-live candidate processes — cancel them first, wait for each to
  # reach a terminal aid-job.sh receipt, exactly like Step 5's scheduler).
  if [[ -n "$_ISO_CURRENT_JOBS_DIR" && -d "$_ISO_CURRENT_JOBS_DIR" ]]; then
    local d
    for d in "$_ISO_CURRENT_JOBS_DIR"/*/; do
      [[ -f "${d}job.json" ]] || continue
      [[ -f "${d}result.json" ]] && continue
      local jid; jid="$(basename "$d")"
      bash "$_AID_JOB_SH" cancel --jobs-dir "$_ISO_CURRENT_JOBS_DIR" --id "$jid" >/dev/null 2>&1 || true
    done
  fi
  if [[ -n "$_ISO_CURRENT_WORKTREE" && -n "$_ISO_PROJECT_ROOT" ]]; then
    git -C "$_ISO_PROJECT_ROOT" worktree remove --force "$_ISO_CURRENT_WORKTREE" >/dev/null 2>&1 || true
  fi
  _ISO_CURRENT_WORKTREE=""
  _ISO_CURRENT_JOBS_DIR=""
}
trap _iso_cleanup EXIT

# _iso_new_worktree <path> <commit> — creates a FRESH disposable worktree at
# <path> from the (already-resolved, real) <commit>, and registers it (plus
# its jobs dir, set by the caller right after) with the global cleanup
# state. Fails closed — no live-tree fallback.
_iso_new_worktree() {
  local path="$1" commit="$2"
  git -C "$_ISO_PROJECT_ROOT" worktree add -q --detach "$path" "$commit" 2>/dev/null \
    || return 1
  _ISO_CURRENT_WORKTREE="$path"
}

# _iso_remove_worktree — explicit, IMMEDIATE teardown (in addition to the
# EXIT trap's own unconditional coverage) so worktrees never accumulate
# across a multi-trial run even on the happy path.
_iso_remove_worktree() {
  [[ -n "$_ISO_CURRENT_WORKTREE" ]] || return 0
  git -C "$_ISO_PROJECT_ROOT" worktree remove --force "$_ISO_CURRENT_WORKTREE" >/dev/null 2>&1 || true
  _ISO_CURRENT_WORKTREE=""
  _ISO_CURRENT_JOBS_DIR=""
}

# _iso_run_set <worktree_path> <jobs_dir> <unit_ids_csv_in_launch_order> <unit_command_map_ref> — helper: launches every named unit_id in the given
# order inside <worktree_path> (cwd), waits for each to reach a terminal
# receipt, and echoes a JSON object {unit_id: state, ...}.
_iso_run_set() {
  local worktree_path="$1" jobs_dir="$2"; shift 2
  local -a ordered_ids=("$@")
  _ISO_CURRENT_JOBS_DIR="$jobs_dir"
  mkdir -p "$jobs_dir"

  local -A job_of=()
  local uid
  for uid in "${ordered_ids[@]}"; do
    local unit_json job_id
    unit_json="$(jq -nc --arg u "$uid" --argjson cmd "${_ISO_UNIT_COMMAND[$uid]}" '{unit_id:$u, command:$cmd, deadline_seconds:300}')"
    job_id="$(_execution_unit_sanitize_id "$uid")"
    job_of["$uid"]="$job_id"
    ( cd "$worktree_path" && execution_unit_run "$unit_json" "$jobs_dir" "$job_id" >/dev/null )
  done

  local states_json="{}"
  for uid in "${ordered_ids[@]}"; do
    local job_id="${job_of[$uid]}"
    while [[ ! -f "${jobs_dir}/${job_id}/result.json" ]]; do sleep 0.2; done
    local observed; observed="$(jq -r '.state' "${jobs_dir}/${job_id}/result.json")"
    states_json="$(jq -c --arg u "$uid" --arg s "$observed" '. + {($u): $s}' <<<"$states_json")"
  done
  echo "$states_json"
}

cmd_run() {
  local project_root="" run_id="" unit_ids_csv="" n=5 commit=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="$2"; shift 2 ;;
      --run-id) run_id="$2"; shift 2 ;;
      --unit-ids) unit_ids_csv="$2"; shift 2 ;;
      --n) n="$2"; shift 2 ;;
      --commit) commit="$2"; shift 2 ;;
      *) _die 2 "run: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$project_root" && -n "$run_id" && -n "$unit_ids_csv" ]] || _die 2 "run: --project-root, --run-id, --unit-ids are required"
  [[ "$run_id" =~ ^[A-Za-z0-9._-]{1,128}$ && "$run_id" != *..* ]] || _die 2 "run: --run-id must match ^[A-Za-z0-9._-]{1,128}\$ and not contain '..'"
  [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 ]] || _die 2 "run: --n must be a positive integer"

  project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "run: --project-root does not exist"
  git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1 || _die 3 "run: --project-root is not a git repository"
  _ISO_PROJECT_ROOT="$project_root"

  # Codex review: an unresolved --commit was passed directly to `git
  # worktree add`, so a value beginning with '-' (e.g. "--help") is parsed
  # as a git OPTION, not a revision — argument injection / denial of the
  # experiment. Resolve to a real, existing commit object FIRST; only the
  # resolved 40-hex SHA is ever used from here on, never the raw input.
  [[ -n "$commit" ]] || commit="HEAD"
  local resolved_commit
  resolved_commit="$(git -C "$project_root" rev-parse --verify "${commit}^{commit}" -- 2>/dev/null)" \
    || _die 1 "run: --commit '$commit' does not resolve to a real commit object in --project-root"
  commit="$resolved_commit"

  local -a unit_ids=()
  IFS=',' read -r -a unit_ids <<<"$unit_ids_csv"
  [[ ${#unit_ids[@]} -gt 0 ]] || _die 2 "run: --unit-ids must name at least one run_unit_id"

  local catalog_path="${project_root}/.aid-o/config/test-catalog.yaml"
  [[ -f "$catalog_path" ]] || _die 3 "run: no approved catalog at $catalog_path"
  local catalog_json; catalog_json="$(yq -o=json '.' "$catalog_path")"

  local run_dir="${project_root}/.aid-o/work/test-audits/${run_id}"
  mkdir -p "$run_dir"

  # Resolve each candidate's command + current runtime.fingerprint. Fail
  # closed (never silently drop a candidate) if any id is absent. Populates
  # the GLOBAL _ISO_UNIT_COMMAND map _iso_run_set reads (a bash 4
  # associative array can't be passed by reference into a function cleanly
  # across all supported bash versions here, so it's shared, not local).
  declare -gA _ISO_UNIT_COMMAND=()
  local -A unit_fingerprint=() unit_locks=()
  local uid
  for uid in "${unit_ids[@]}"; do
    local ru
    ru="$(jq -c --arg id "$uid" '.run_units[] | select(.run_unit_id == $id)' <<<"$catalog_json")"
    [[ -n "$ru" ]] || _die 1 "run: run_unit_id '$uid' not found in the catalog"
    _ISO_UNIT_COMMAND["$uid"]="$(jq -c '.command' <<<"$ru")"
    unit_fingerprint["$uid"]="$(jq -r '.runtime.fingerprint' <<<"$ru")"
    unit_locks["$uid"]="$(jq -c '.isolation.lock_usage // []' <<<"$ru")"
  done

  # ── Solo baselines: each candidate run ALONE once, in its OWN fresh
  # worktree — never sharing a checkout with any other baseline or trial.
  local -A solo_state=()
  for uid in "${unit_ids[@]}"; do
    local wt="${run_dir}/isolation-worktree-solo-$(_execution_unit_sanitize_id "$uid")"
    _iso_new_worktree "$wt" "$commit" \
      || _die 1 "run: git worktree add failed for solo baseline of '$uid' — failing closed as unknown, no live-tree fallback"
    local states_json
    states_json="$(_iso_run_set "$wt" "${run_dir}/isolation-jobs/solo-$(_execution_unit_sanitize_id "$uid")" "$uid")"
    solo_state["$uid"]="$(jq -r --arg u "$uid" '.[$u]' <<<"$states_json")"
    _iso_remove_worktree
  done

  # ── N trials, alternating launch order — each in its OWN fresh worktree.
  # A shared-state failure OR a timing-order dependence is any trial whose
  # per-unit outcome does not match that unit's own solo baseline.
  local -a failure_reasons=()
  local trial
  for ((trial = 1; trial <= n; trial++)); do
    local -a ordered_ids=("${unit_ids[@]}")
    if (( trial % 2 == 0 )); then
      local -a reversed=()
      local i
      for ((i = ${#ordered_ids[@]} - 1; i >= 0; i--)); do reversed+=("${ordered_ids[$i]}"); done
      ordered_ids=("${reversed[@]}")
    fi

    local wt="${run_dir}/isolation-worktree-trial${trial}"
    _iso_new_worktree "$wt" "$commit" \
      || _die 1 "run: git worktree add failed for trial ${trial} — failing closed as unknown, no live-tree fallback"
    local states_json
    states_json="$(_iso_run_set "$wt" "${run_dir}/isolation-jobs/trial${trial}" "${ordered_ids[@]}")"
    _iso_remove_worktree

    for uid in "${ordered_ids[@]}"; do
      local observed; observed="$(jq -r --arg u "$uid" '.[$u]' <<<"$states_json")"
      if [[ "$observed" != "${solo_state[$uid]}" ]]; then
        failure_reasons+=("trial ${trial}: unit '${uid}' observed '${observed}' but its solo baseline was '${solo_state[$uid]}' (shared-state or timing-order dependence)")
      fi
    done
  done

  if [[ ${#failure_reasons[@]} -gt 0 ]]; then
    echo "aid-test-isolation-experiment.sh: promotion REFUSED for [${unit_ids[*]}] — ${#failure_reasons[@]} divergence(s) from solo baseline:" >&2
    printf '  - %s\n' "${failure_reasons[@]}" >&2
    exit 1
  fi

  # ── Promotion: safe if the unit declares no known exclusive resources of
  # its own (isolation.lock_usage empty), else constrained — the isolation
  # experiment proves no UNDECLARED conflict; an already-declared lock need
  # is still respected, never silently discarded by a passing experiment.
  local now_iso; now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local overlay_entries="[]"
  for uid in "${unit_ids[@]}"; do
    local promoted_status="safe"
    [[ "$(jq 'length' <<<"${unit_locks[$uid]}")" -gt 0 ]] && promoted_status="constrained"
    overlay_entries="$(jq -c --arg u "$uid" --arg ps "$promoted_status" --arg fp "${unit_fingerprint[$uid]}" \
      --arg pa "$now_iso" --arg er "$run_id" \
      '. + [{run_unit_id:$u, promoted_status:$ps, catalog_fingerprint_at_promotion:$fp, promoted_at:$pa, evidence_run_id:$er}]' \
      <<<"$overlay_entries")"
  done

  local proposed_json
  proposed_json="$(jq -nc --argjson overlay "$overlay_entries" '{schema_version:"1.0.0", status:"proposed", overlay:$overlay}')"
  adapter_validate_schema "$OVERLAY_SCHEMA" "$proposed_json" \
    || _die 1 "run: internal error — produced a schema-invalid proposed overlay, refusing to write"

  local proposed_path="${run_dir}/scheduler-overlay.proposed.json"
  local tmp="${proposed_path}.tmp.$$"
  printf '%s' "$proposed_json" | jq '.' > "$tmp"
  mv "$tmp" "$proposed_path"

  echo "aid-test-isolation-experiment.sh: promoted [${unit_ids[*]}] after ${n} trials with zero divergence from solo baselines — proposed overlay written to $proposed_path"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    run) shift; cmd_run "$@" ;;
    *)
      echo "Usage: aid-test-isolation-experiment.sh run --project-root <path> --run-id <id> --unit-ids <id1,id2,...> [--n 5] [--commit <sha>]" >&2
      exit 1
      ;;
  esac
fi
