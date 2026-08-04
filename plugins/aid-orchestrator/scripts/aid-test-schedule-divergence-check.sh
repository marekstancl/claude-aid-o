#!/usr/bin/env bash
# aid-test-schedule-divergence-check.sh — P069 Step 7.
#
# Runs the SAME selected set of catalog run_units both SEQUENTIALLY (Step
# 5's scheduler, mode=sequential) and via the SCHEDULER (mode=observe_parallel
# or parallel) on the SAME commit, inside ONE fresh disposable CLONE per
# invocation — never the live project checkout, never a reused clone (each
# invocation is a genuinely independent trial). Compares membership and
# verdicts field-by-field; any difference blocks promotion for that run,
# naming the exact unit/field, and is still written with pass:false —
# divergence-evidence.schema.json is the durable, retained record either way.
#
# Force-tracks the written artifact via `git add -f` in the REAL
# project_root (the same, single mechanism P066's aid-test-catalog-approve.sh
# already ships — never a second, divergent implementation). If project_root
# is not a git repository, the artifact is written but not tracked, matching
# that script's own documented non-git-repo behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

DIVERGENCE_SCHEMA="${SCHEMAS_DIR}/divergence-evidence.schema.json"
SCHEDULER_SH="${SCRIPT_DIR}/aid-test-scheduler.sh"

_die() { echo "aid-test-schedule-divergence-check.sh: $2" >&2; exit "$1"; }

# _dc_new_uuid — a genuinely collision-safe UUID (never a monotonic
# counter — Codex/C0 idempotency-lens finding this step's plan section
# names explicitly).
_dc_new_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi
}

_ISO_PROJECT_ROOT=""
_ISO_CURRENT_CLONE=""
_dc_cleanup() {
  [[ -n "$_ISO_CURRENT_CLONE" && -d "$_ISO_CURRENT_CLONE" ]] && rm -rf "$_ISO_CURRENT_CLONE" 2>/dev/null || true
  _ISO_CURRENT_CLONE=""
}
trap _dc_cleanup EXIT

cmd_run() {
  local project_root="" unit_ids_csv="" mode_tested="" commit=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="$2"; shift 2 ;;
      --unit-ids) unit_ids_csv="$2"; shift 2 ;;
      --mode-tested) mode_tested="$2"; shift 2 ;;
      --commit) commit="$2"; shift 2 ;;
      *) _die 2 "run: unknown arg '$1'" ;;
    esac
  done
  [[ -n "$project_root" && -n "$unit_ids_csv" ]] || _die 2 "run: --project-root and --unit-ids are required"
  case "$mode_tested" in observe_parallel|parallel) ;; *) _die 2 "run: --mode-tested must be observe_parallel|parallel" ;; esac

  project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "run: --project-root does not exist"
  git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1 || _die 3 "run: --project-root is not a git repository"
  _ISO_PROJECT_ROOT="$project_root"

  [[ -n "$commit" ]] || commit="HEAD"
  local commit_sha
  commit_sha="$(git -C "$project_root" rev-parse --verify "${commit}^{commit}" -- 2>/dev/null)" \
    || _die 1 "run: --commit '$commit' does not resolve to a real commit object"

  local -a unit_ids=()
  IFS=',' read -r -a unit_ids <<<"$unit_ids_csv"
  [[ ${#unit_ids[@]} -gt 0 ]] || _die 2 "run: --unit-ids must name at least one run_unit_id"
  # Codex review: a duplicate unit_id would collapse in the membership_diff/
  # verdict_diff jq comparison (set semantics / key-overwrite on `add`),
  # silently hiding a genuine per-instance divergence. Reject up front.
  local dup_uids; dup_uids="$(printf '%s\n' "${unit_ids[@]}" | sort | uniq -d)"
  [[ -z "$dup_uids" ]] || _die 2 "run: --unit-ids contains duplicate(s): $(echo "$dup_uids" | tr '\n' ' ')"

  local run_id; run_id="$(_dc_new_uuid)"

  local evidence_dir="${project_root}/.aid-o/work/evidence/scheduler-divergence"
  mkdir -p "$evidence_dir"
  local artifact_path="${evidence_dir}/${commit_sha}-${mode_tested}-${run_id}.json"
  local lock_dir="${artifact_path}.lockdir"
  mkdir "$lock_dir" 2>/dev/null \
    || _die 5 "run: atomicity guard tripped — a file already claims run_id '$run_id' for this commit/mode (vanishingly unlikely genuine UUID collision, or a re-run bug) at $artifact_path"
  # Codex review: the lock dir alone only serializes CONCURRENT claims — a
  # LATER invocation that happens to compute the same UUID (after the first
  # one already finished and released the lock) would still silently
  # overwrite the retained artifact via `> $artifact_path`. Fail closed if
  # the target already exists, even while holding the lock.
  if [[ -e "$artifact_path" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
    _die 5 "run: atomicity guard tripped — $artifact_path already exists (genuine UUID collision) — refusing to overwrite retained evidence"
  fi

  # ── Fresh disposable clone — never the live checkout, never reused
  # across invocations. Codex review: clone_path was previously a SUBDIR of
  # a fresh mktemp -d parent, so removing only clone_path on success left
  # an empty parent directory behind every single invocation; git clone can
  # target the mktemp'd directory itself directly (it accepts an existing
  # EMPTY target), so there is no leftover parent to track or clean.
  local clone_path; clone_path="$(mktemp -d)"
  _ISO_CURRENT_CLONE="$clone_path"
  git clone --quiet "$project_root" "$clone_path" 2>/dev/null \
    || _die 1 "run: git clone failed — failing closed, no live-tree fallback"
  git -C "$clone_path" checkout --quiet "$commit_sha" 2>/dev/null \
    || _die 1 "run: checkout of $commit_sha in the disposable clone failed"

  local catalog_path="${clone_path}/.aid-o/config/test-catalog.yaml"
  [[ -f "$catalog_path" ]] || _die 3 "run: no approved catalog at $catalog_path (in the disposable clone)"
  local catalog_json; catalog_json="$(yq -o=json '.' "$catalog_path")"

  # catalog_fingerprint_set: sha256 over the sorted, newline-joined set of
  # every compared unit's CURRENT (at this commit) runtime.fingerprint.
  local fp_list=""
  local uid
  for uid in "${unit_ids[@]}"; do
    local fp
    fp="$(jq -r --arg id "$uid" '.run_units[] | select(.run_unit_id == $id) | .runtime.fingerprint' <<<"$catalog_json")"
    [[ -n "$fp" ]] || _die 1 "run: run_unit_id '$uid' not found in the disposable clone's catalog"
    fp_list+="${fp}"$'\n'
  done
  local catalog_fingerprint_set
  catalog_fingerprint_set="sha256:$(printf '%s' "$fp_list" | sort | sha256sum | cut -d' ' -f1)"

  # Build the execution-unit membership-verified units_json Step 5's
  # scheduler requires — a bound-catalog_fingerprint stamp against THIS
  # clone's own catalog (no external membership-verification pass needed:
  # this check IS its own closed-world resolution).
  local units_json="[]"
  local now_iso; now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for uid in "${unit_ids[@]}"; do
    local fp cmd
    fp="$(jq -r --arg id "$uid" '.run_units[] | select(.run_unit_id == $id) | .runtime.fingerprint' <<<"$catalog_json")"
    cmd="$(jq -c --arg id "$uid" '.run_units[] | select(.run_unit_id == $id) | .command' <<<"$catalog_json")"
    units_json="$(jq -c --arg u "$uid" --arg fp "$fp" --arg va "$now_iso" --argjson cmd "$cmd" \
      '. + [{unit_id:$u, command:$cmd, deadline_seconds:300, resource_locks:[], parallel_eligible:false, membership_verified:true, dedup:false, membership_binding:{catalog_fingerprint:$fp, verified_at:$va, verifier_run_id:"divergence-check"}}]' \
      <<<"$units_json")"
  done
  local units_file; units_file="$(mktemp)"
  printf '%s' "$units_json" > "$units_file"

  # aid-test-scheduler.sh never `cd`s into --project-root itself — by
  # design, it inherits the caller's cwd, matching how aid-run-gates.sh
  # (Step 14, its real production caller) always already runs from the
  # project root. This check's whole point is dispatching against a
  # DIFFERENT --project-root (the disposable clone), so — same convention
  # Step 6's isolation-experiment script already established — THIS
  # caller is responsible for cd-ing into the clone first. A real,
  # reproduced bug caught while hardening this step: without the explicit
  # `cd`, candidate commands ran in whatever directory this script itself
  # happened to be invoked from, silently writing/reading files OUTSIDE
  # the disposable clone entirely.
  # P069 EPIC 4 whole-diff review: real, measured wall-clock duration
  # around each dispatch — this is the ONLY place a genuinely-measured
  # scheduled-mode runtime figure for an arbitrary (possibly quarantined)
  # gate can ever originate. gate-runtime-baseline's own concurrency_context
  # samples (Step 3) are only ever recorded for a gate actually dispatched
  # through aid-run-gates.sh's scheduler integration (Step 14), which is
  # scoped to the targeted_tests gate alone — never bats_all or any other
  # quarantined gate this check might be run against directly.
  local seq_out sched_out
  local seq_start_ms seq_end_ms sched_start_ms sched_end_ms
  seq_start_ms=$(date +%s%3N)
  seq_out="$(cd "$clone_path" && bash "$SCHEDULER_SH" dispatch --project-root "$clone_path" --run-id "${run_id}-seq" --units-json "$units_file" --mode sequential)" \
    || _die 1 "run: sequential dispatch failed unexpectedly"
  seq_end_ms=$(date +%s%3N)
  sched_start_ms=$(date +%s%3N)
  sched_out="$(cd "$clone_path" && bash "$SCHEDULER_SH" dispatch --project-root "$clone_path" --run-id "${run_id}-sched" --units-json "$units_file" --mode "$mode_tested")" \
    || _die 1 "run: scheduled dispatch failed unexpectedly"
  sched_end_ms=$(date +%s%3N)
  rm -f "$units_file"

  local sequential_duration_ms scheduled_duration_ms
  sequential_duration_ms=$(( seq_end_ms - seq_start_ms ))
  scheduled_duration_ms=$(( sched_end_ms - sched_start_ms ))

  local sequential_verdicts scheduled_verdicts
  sequential_verdicts="$(jq -c '[.units[] | {unit_id, result:(if .state=="terminal_pass" then "pass" else "fail" end)}]' <<<"$seq_out")"
  scheduled_verdicts="$(jq -c '[.units[] | {unit_id, result:(if .state=="terminal_pass" then "pass" else "fail" end)}]' <<<"$sched_out")"

  local membership_diff verdict_diff pass_bool
  membership_diff="$(jq -cn --argjson a "$sequential_verdicts" --argjson b "$scheduled_verdicts" '
    ([$a[].unit_id]) as $au | ([$b[].unit_id]) as $bu
    | (($au - $bu) + ($bu - $au)) | unique | sort
  ')"
  verdict_diff="$(jq -cn --argjson a "$sequential_verdicts" --argjson b "$scheduled_verdicts" '
    (($a | map({(.unit_id): .result}) | add) // {}) as $am
    | (($b | map({(.unit_id): .result}) | add) // {}) as $bm
    | [ ($am | keys[]) as $u | select($bm[$u] != null and $bm[$u] != $am[$u])
        | {unit_id:$u, sequential_result:$am[$u], scheduled_result:$bm[$u]} ]
  ')"
  if [[ "$(jq 'length' <<<"$membership_diff")" -eq 0 && "$(jq 'length' <<<"$verdict_diff")" -eq 0 ]]; then
    pass_bool="true"
  else
    pass_bool="false"
  fi

  local unit_ids_json; unit_ids_json="$(printf '%s\n' "${unit_ids[@]}" | jq -R . | jq -sc .)"
  local evaluated_at; evaluated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local evidence_json
  evidence_json="$(jq -nc \
    --arg run_id "$run_id" --arg cfs "$catalog_fingerprint_set" --arg csha "$commit_sha" \
    --arg mode "$mode_tested" --argjson uids "$unit_ids_json" \
    --argjson seqv "$sequential_verdicts" --argjson schv "$scheduled_verdicts" \
    --argjson mdiff "$membership_diff" --argjson vdiff "$verdict_diff" \
    --argjson pass "$pass_bool" \
    --argjson seqms "$sequential_duration_ms" --argjson schms "$scheduled_duration_ms" \
    --arg eat "$evaluated_at" \
    '{run_id:$run_id, catalog_fingerprint_set:$cfs, commit_sha:$csha, worktree_kind:"disposable_clone",
      mode_tested:$mode, selected_unit_ids:$uids, sequential_verdicts:$seqv, scheduled_verdicts:$schv,
      membership_diff:$mdiff, verdict_diff:$vdiff, pass:$pass,
      sequential_duration_ms:$seqms, scheduled_duration_ms:$schms, evaluated_at:$eat}')"

  adapter_validate_schema "$DIVERGENCE_SCHEMA" "$evidence_json" \
    || _die 1 "run: internal error — produced a schema-invalid divergence artifact, refusing to write"

  printf '%s' "$evidence_json" | jq '.' > "$artifact_path"
  rmdir "$lock_dir" 2>/dev/null || true

  if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
    local rel="${artifact_path#"${project_root}"/}"
    git -C "$project_root" add -f -- "$rel"
    echo "aid-test-schedule-divergence-check.sh: wrote and force-tracked $rel (pass:${pass_bool}, run_id:${run_id})"
  else
    echo "aid-test-schedule-divergence-check.sh: not a git repository, evidence written to $artifact_path but not tracked"
  fi

  # Machine-parseable, ALWAYS-emitted final stdout line (Codex review: the
  # campaign orchestrator previously identified "the artifact this attempt
  # just wrote" via `ls -t | head -1` — a global newest-mtime guess that can
  # misattribute an unrelated pre-existing artifact, especially under
  # concurrent campaigns or equal mtimes. Emitting the EXACT path this
  # invocation wrote removes the guesswork entirely.) — printed on both the
  # pass and fail path, before either exits.
  echo "ARTIFACT_PATH=${artifact_path}"

  if [[ "$pass_bool" != "true" ]]; then
    echo "aid-test-schedule-divergence-check.sh: DIVERGENCE DETECTED — membership_diff=$membership_diff verdict_diff=$verdict_diff" >&2
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    run) shift; cmd_run "$@" ;;
    *)
      echo "Usage: aid-test-schedule-divergence-check.sh run --project-root <path> --unit-ids <id1,id2,...> --mode-tested observe_parallel|parallel [--commit <sha>]" >&2
      exit 1
      ;;
  esac
fi
