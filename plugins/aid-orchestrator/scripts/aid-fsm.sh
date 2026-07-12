#!/usr/bin/env bash
# aid-fsm.sh — AID Orchestrator 6-state FSM controller
# Mechanically enforced: precondition-verified transitions + audit trail
#
# Usage:
#   aid-fsm.sh init <epic_id> <run_id> <total_steps> <mode> <branch> <base_commit> <state_file> [--force]
#   aid-fsm.sh transition <from> <to> <state_file> [--force]
#   aid-fsm.sh advance-to-gates <state_file>
#   aid-fsm.sh get-state <state_file>
#   aid-fsm.sh verify-state <state_file>
#   aid-fsm.sh increment-step <state_file> [--force]
#   aid-fsm.sh get-field <field> <state_file>
#   aid-fsm.sh set-field <field> <value> <state_file>
#   aid-fsm.sh done-advance <from_phase> <to_phase> <state_file>
#   aid-fsm.sh plan-close <epic_id> <evidence_dir> <project_root>
#   aid-fsm.sh promote-check <check_name> <state_file>
#   aid-fsm.sh check-promotion-candidates <state_file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# Shared plan-boundary review signals — _aid_read_toggle + _aid_validate_test_evidence
# (B1: one substrate for the FSM compliance checks AND the C4 release aggregator).
source "${SCRIPT_DIR}/lib/aid-review-signals.sh"
# Controller plugin-cache staleness guard (P060 Step 5) — defines
# run_cache_preflight. Sourced AFTER aid-stage-log.sh so log_event already
# exists (the lib's re-source guard then skips, preserving aid-fsm.sh's die()).
source "${SCRIPT_DIR}/lib/aid-cache-preflight.sh"

VALID_STATES="READY EXECUTE GATES ESCALATION DONE ERROR"

# Valid transitions map: "FROM:TO" pairs
VALID_TRANSITIONS=(
  "READY:EXECUTE"
  "EXECUTE:EXECUTE"
  "EXECUTE:GATES"
  "EXECUTE:ESCALATION"
  "GATES:DONE"
  "GATES:EXECUTE"
  "GATES:ESCALATION"
  "ESCALATION:EXECUTE"
  "ESCALATION:GATES"
  "READY:ERROR"
  "EXECUTE:ERROR"
  "GATES:ERROR"
  "ESCALATION:ERROR"
)

is_valid_state() {
  local state="$1"
  [[ " $VALID_STATES " =~ " $state " ]]
}

is_valid_transition() {
  local from="$1" to="$2"
  local pair="${from}:${to}"
  for t in "${VALID_TRANSITIONS[@]}"; do
    [[ "$t" == "$pair" ]] && return 0
  done
  return 1
}

# Read a flat `key: value` scalar from a YAML-ish file (fsm-state.yaml,
# verifier-output-*.md frontmatter). Pure bash — replaces the grep|awk pattern
# (2 forks per read) that was previously copy-pasted at every field access.
# First match wins; prints empty (exit 0) on missing file/key — set -e safe.
yaml_field() {
  local file=$1 key=$2 line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    if [[ "$line" == "${key}:"* ]]; then
      line=${line#"${key}:"}
      line=${line#"${line%%[![:space:]]*}"}   # strip leading whitespace
      line="${line%%[[:space:]]*}"             # strip trailing whitespace
      # Strip surrounding YAML quotes so _generated_by: "" fails [[ -z ]] checks.
      if [[ ${#line} -ge 2 && "${line:0:1}" == '"' && "${line: -1}" == '"' ]]; then
        line="${line:1:${#line}-2}"
      elif [[ ${#line} -ge 2 && "${line:0:1}" == "'" && "${line: -1}" == "'" ]]; then
        line="${line:1:${#line}-2}"
      fi
      printf '%s\n' "$line"
      return 0
    fi
  done < "$file"
  return 0
}

# Derive timeline.jsonl path from state_file fields (best-effort, never fails)
derive_timeline() {
  local state_file="$1"
  local epic_id run_id
  epic_id=$(yaml_field "$state_file" epic_id)
  run_id=$(yaml_field "$state_file" run_id)
  if [[ -n "$epic_id" && -n "$run_id" ]]; then
    echo ".aid-o/work/evidence/${epic_id}/${run_id}/timeline.jsonl"
  fi
}

# True if the working tree is a git worktree (git_dir under .git/worktrees/).
# Used by PRE-FLIGHT branch enforcement to skip auto-checkout in worktree mode
# where the caller (e.g., superpowers:using-git-worktrees) controls the branch.
is_worktree() {
  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
  [[ "$git_dir" == *.git/worktrees/* ]]
}

# Print a multi-line error to stderr and exit 1.
# Use for unrecoverable PRE-FLIGHT / precondition failures with copy-paste fix.
die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# Fail one cmd_increment_step precondition: print message lines to stderr,
# log fsm_increment_fail with the given reason, exit 1. Reads $state_file and
# $step from caller scope (file convention, see fsm_count_fails_matching).
_increment_fail() {
  local reason=$1; shift
  printf '%s\n' "$@" >&2
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_increment_fail" step="$step" reason="$reason"
  exit 1
}

# ─── P032 Step 3: Grandfather + Repeated-Fail Helpers ────────────────────
# All three read $state_file / $evidence_dir / $epic_id from caller scope
# (matches existing derive_timeline / check_preconditions convention).

# True if fsm-state.yaml.created_at predates the current AID deploy threshold.
# Threshold sources (first non-empty wins):
#   1. AID_DEPLOY_DATE env var (set by PM shell rc or per-invocation)
#   2. ${AID_PLUGIN_PATH}/DEPLOY_DATE file (created in Step 9 release)
# If no marker / no threshold → return 1 (fail-safe to post-deploy strict).
# ISO 8601 UTC lex compare works here because both fields use the same
# `date -u +%Y-%m-%dT%H:%M:%SZ` format (Step 2 cmd_init / Step 9 release).
fsm_check_grandfather() {
  local created_at
  created_at=$(yaml_field "$state_file" created_at)
  [[ -z "$created_at" ]] && return 1
  local deploy_date="${AID_DEPLOY_DATE:-}"
  if [[ -z "$deploy_date" && -n "${AID_PLUGIN_PATH:-}" && -f "${AID_PLUGIN_PATH}/DEPLOY_DATE" ]]; then
    deploy_date=$(<"${AID_PLUGIN_PATH}/DEPLOY_DATE")
  fi
  if [[ -z "$deploy_date" && -f "${SCRIPT_DIR}/../DEPLOY_DATE" ]]; then
    deploy_date=$(<"${SCRIPT_DIR}/../DEPLOY_DATE")
  fi
  [[ -z "$deploy_date" ]] && return 1
  [[ "$created_at" < "$deploy_date" ]]
}

# Core counter for fsm_precondition_fail events: $1 is a jq filter fragment,
# remaining args are jq --arg bindings. Echoes 0 when timeline is missing —
# first-attempt safe. The three wrappers below differ only in their filter.
fsm_count_fails_matching() {
  local filter=$1; shift
  local timeline="${evidence_dir}/timeline.jsonl"
  [[ ! -f "$timeline" ]] && { echo 0; return 0; }
  jq -r "$@" \
     "[inputs | select(.event==\"fsm_precondition_fail\" and (${filter}))] | length" \
     -n < "$timeline" 2>/dev/null || echo 0
}

# Count prior fsm_precondition_fail events on this EPIC matching from/to/reason.
fsm_count_recent_fails() {
  fsm_count_fails_matching '.from==$f and .to==$t and .reason==$r' \
    --arg f "$1" --arg t "$2" --arg r "$3"
}

# Count fsm_precondition_fail events for (same step + same reason) — detects
# "this step is structurally problematic" pattern (≥ 3 = step-level repeated fail).
fsm_count_recent_fails_step() {
  fsm_count_fails_matching '.step==$s and .reason==$r' --arg s "$1" --arg r "$2"
}

# Count fsm_precondition_fail events for (same reason, any step) — detects
# "agent systematically bypasses this check across steps" pattern (≥ 3 = EPIC-level).
fsm_count_recent_fails_epic() {
  fsm_count_fails_matching '.reason==$r' --arg r "$1"
}

# Validate a verifier-output-step-N.md or verifier-output-cp3-{focus}.md file.
# Returns 0 (pass) if file exists + has non-empty _generated_by + _generated_at
# + valid classification. For RUN/FAIL/FULL_REVIEW also requires non-empty
# verdict != "pending" (verifier ran). Aligned with agents/verifier.md canonical
# output contract (E-046-1_3 Step 2 producer→consumer migration).
# Structural gate (v2.35+): behavior_trace_count > 0 when behavior_trace_required: true.
# Gate is opt-in (only fires when behavior_trace_required is explicitly "true").
# CP6 is advisory and never reaches this check via the FSM flow.
fsm_check_verifier_output() {
  local file=$1
  [[ -f "$file" ]] || return 1
  grep -q '^_generated_by:' "$file" || return 1
  grep -q '^_generated_at:' "$file" || return 1
  grep -q '^classification:' "$file" || return 1

  local generated_by generated_at classification
  generated_by=$(yaml_field "$file" _generated_by)
  [[ -z "$generated_by" ]] && return 1  # non-empty: rejects pre-filter placeholder or blank
  generated_at=$(yaml_field "$file" _generated_at)
  [[ -z "$generated_at" ]] && return 1  # non-empty: ensures verifier wrote a real timestamp

  classification=$(yaml_field "$file" classification)
  case "$classification" in
    SKIP)
      grep -q '^reason:' "$file" || return 1
      ;;
    RUN|FAIL|FULL_REVIEW)
      grep -q '^verdict:' "$file" || return 1
      local verdict
      verdict=$(yaml_field "$file" verdict)
      case "$verdict" in
        pass|fail) ;;          # only valid completed verdicts
        pending)   return 1 ;; # pre-filter placeholder: verifier not dispatched
        *)         return 1 ;; # unknown/garbage verdict (e.g. banana, empty, typo)
      esac
      ;;
    *)
      return 1  # unknown classification
      ;;
  esac

  # Structural gate: behavior_trace_count > 0 when required for high-risk diffs (v2.35+).
  # Only fires when verifier output explicitly sets behavior_trace_required: true.
  local behavior_trace_required
  behavior_trace_required=$(yaml_field "$file" behavior_trace_required)
  if [[ "$behavior_trace_required" == "true" ]]; then
    local behavior_trace_count
    behavior_trace_count=$(yaml_field "$file" behavior_trace_count)
    # Fail if count is missing, empty, zero, negative, or non-numeric
    if [[ -z "$behavior_trace_count" || ! "$behavior_trace_count" =~ ^[1-9][0-9]*$ ]]; then
      return 1
    fi
  fi

  return 0
}

# Route a CP3-freshness violation through the enforcement policy (P060 Step 4).
# Emits cp3_freshness_would_block, then: blocking → print recovery, return 1;
# observe → return 0 (logged, non-blocking). Sets _PRECONDITION_FAIL_REASON so
# cmd_transition can group the failure in the timeline (like other preconditions).
# Args: $1 timeline  $2 policy  $3 reason  $4.. stderr recovery lines.
_cp3_freshness_route() {
  local timeline="$1" policy="$2" reason="$3"; shift 3
  [[ -n "$timeline" ]] && log_event "$timeline" "cp3_freshness_would_block" \
    reason="$reason" enforcement="$policy"
  if [[ "$policy" == "blocking" ]]; then
    _PRECONDITION_FAIL_REASON="cp3_stale_review"
    printf '%s\n' "$@" >&2
    return 1
  fi
  return 0
}

# fsm_check_cp3_freshness — P060 Step 4 (OBS-20260702-03), head-side twin of B-008.
# Refuses a STALE CP3 review as DONE evidence. Each CP3 verifier-output records
# `Reviewed-Head: <sha>` = the sha its diff was generated against (see
# agents/verifier.md §Output Format producer contract). If HEAD has moved past
# that sha, the review did not see the current tree — UNLESS the D4 narrow
# exception holds:
#   (a) path scope — every changed path is under */tests/*, */fixtures/*, or the
#       CURRENT run's evidence dir, with verdict-bearing files EXCLUDED
#       (verifier-output-*.md / gates_report.json / fsm-state.yaml are NEVER
#       "bookkeeping", even under tests/); AND
#   (b) explicit marking — every commit past the reviewed head carries a
#       `CP3-Freshness-Exception: <reason>` git trailer.
# On PASS-with-exception the disclosure event `cp3_freshness_exception` carries the
# FULL changed-file list (E10 measures exception abuse; the residual "weakened test
# slips through" risk is deliberate and MEASURED, not hidden).
#
# Policy CP3_FRESHNESS_POLICY (observe|blocking, default BLOCKING per D9 —
# deliberately stricter than sibling observe defaults). observe → emit
# cp3_freshness_would_block, do NOT block. Grandfather is keyed on
# fsm_check_grandfather (run created_at < DEPLOY_DATE), NEVER a self-reported
# _generated_at — a backdated file on a post-deploy run still fails.
# Separate from the shared fsm_check_verifier_output (cp2/cp3/cp4). Enforcement
# principle: AID-v3-principles.md §1.
#
# Args: <evidence_dir> <state_file> [project_root]. state_file is assigned to a
# local so the fsm_check_grandfather call below reads it via dynamic scope.
# Returns 0 (fresh / exception / observe / grandfathered / no-CP3-files),
# 1 (blocking violation).
fsm_check_cp3_freshness() {
  local evidence_dir="$1"
  local state_file="$2"
  local project_root="${3:-$PWD}"
  local timeline="${evidence_dir}/timeline.jsonl"

  # Grandfather: pre-deploy runs are exempt (keyed on run created_at, not file).
  if fsm_check_grandfather; then
    return 0
  fi

  local policy="${CP3_FRESHNESS_POLICY:-blocking}"

  # Collect existing CP3 verifier-output files. Absent files are the domain of
  # the presence check (fsm_check_verifier_output at EXECUTE:GATES), not here.
  local cp3_files=() f
  for f in verifier-output-cp3-code-review.md verifier-output-cp3-security.md; do
    [[ -f "${evidence_dir}/${f}" ]] && cp3_files+=("${evidence_dir}/${f}")
  done
  [[ ${#cp3_files[@]} -eq 0 ]] && return 0

  # Read Reviewed-Head from each CP3 file; missing on any → fail (F4g).
  # P060 per-plan C+A: validate EACH file independently, not last-wins. If two CP3 files
  # disagree on Reviewed-Head (e.g. a stale code-review + a fresh security output), the
  # freshness verdict must NOT be driven by whichever was iterated last — an inconsistent
  # review base is itself stale evidence → fail conservatively.
  local reviewed_head="" rh
  for f in "${cp3_files[@]}"; do
    rh=$(yaml_field "$f" "Reviewed-Head")
    if [[ -z "$rh" ]]; then
      _cp3_freshness_route "$timeline" "$policy" "missing_reviewed_head" \
        "PRECONDITION FAIL: ${f##*/} has no 'Reviewed-Head:' line." \
        "" \
        "Reason: a CP3 verifier output must record the sha its diff was generated" \
        "        against (agents/verifier.md §Output Format). Without it the FSM" \
        "        cannot prove the review saw the current tree (OBS-20260702-03)." \
        "Fix: re-dispatch CP3 (both verifiers) so each writes 'Reviewed-Head: <sha>'." \
        "OR (PM-authorized, audited): rerun the transition with --force --reason '<why>'."
      return $?
    fi
    if [[ -n "$reviewed_head" && "$rh" != "$reviewed_head" ]]; then
      _cp3_freshness_route "$timeline" "$policy" "inconsistent_reviewed_head" \
        "PRECONDITION FAIL: CP3 files disagree on Reviewed-Head (${reviewed_head} vs ${rh})." \
        "Reason: the CP3 verifiers reviewed different HEADs — the review base is inconsistent," \
        "        so the freshness verdict cannot be trusted (one output is stale)." \
        "Fix: re-dispatch BOTH CP3 verifiers against the same current HEAD."
      return $?
    fi
    reviewed_head="$rh"
  done

  local current_head
  current_head=$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo "")
  if [[ -z "$current_head" ]]; then
    _cp3_freshness_route "$timeline" "$policy" "head_unresolved" \
      "PRECONDITION FAIL: cannot resolve current git HEAD to verify CP3 freshness."
    return $?
  fi

  # Fresh: reviewed head == current head.
  [[ "$reviewed_head" == "$current_head" ]] && return 0

  # reviewed_head must be a real, ancestor commit of HEAD; otherwise stale/diverged.
  if ! git -C "$project_root" rev-parse --verify "${reviewed_head}^{commit}" >/dev/null 2>&1 \
     || ! git -C "$project_root" merge-base --is-ancestor "$reviewed_head" "$current_head" 2>/dev/null; then
    _cp3_freshness_route "$timeline" "$policy" "reviewed_head_not_ancestor" \
      "PRECONDITION FAIL: CP3 Reviewed-Head ${reviewed_head} is not an ancestor of HEAD ${current_head}." \
      "Fix: re-dispatch CP3 (both verifiers) against the current HEAD."
    return $?
  fi

  # HEAD is ahead — apply the D4 narrow exception. -z + while-read handles
  # spaces-in-names safely.
  local changed_files=() p
  while IFS= read -r -d '' p; do
    changed_files+=("$p")
  done < <(git -C "$project_root" diff --name-only -z "${reviewed_head}..${current_head}" 2>/dev/null)

  # (a) path scope + verdict-bearing exclusion.
  local violating="" base
  if [[ ${#changed_files[@]} -gt 0 ]]; then
    for p in "${changed_files[@]}"; do
      base="${p##*/}"
      # Verdict-bearing files are NEVER bookkeeping, even under tests/.
      case "$base" in
        verifier-output-*.md|gates_report.json|fsm-state.yaml)
          violating="$p (verdict-bearing)"; break ;;
      esac
      case "$p" in
        */tests/*|tests/*|*/fixtures/*|fixtures/*) : ;;   # test/fixture churn OK
        "$evidence_dir"/*) : ;;                           # current run evidence OK
        *) violating="$p (out-of-scope)"; break ;;
      esac
    done
  fi

  if [[ -n "$violating" ]]; then
    _cp3_freshness_route "$timeline" "$policy" "path_out_of_scope" \
      "PRECONDITION FAIL: commit(s) past reviewed CP3 head touch a non-exempt path: ${violating}." \
      "" \
      "Reason: the D4 CP3-freshness exception permits ONLY test/fixture/evidence" \
      "        churn, and verdict-bearing files (verifier-output-*.md," \
      "        gates_report.json, fsm-state.yaml) never qualify. A production" \
      "        change past the reviewed head means CP3 never saw it (stale review)." \
      "Fix: re-dispatch CP3 (both verifiers) against current HEAD, re-run gates," \
      "     then retry the transition." \
      "OR (PM-authorized override, audited): rerun with --force --reason '<≥20 chars>'."
    return $?
  fi

  # (b) require the CP3-Freshness-Exception trailer on EVERY post-review commit.
  local c missing_trailer="" tr
  while IFS= read -r c; do
    [[ -z "$c" ]] && continue
    tr=$(git -C "$project_root" log -1 \
      --format='%(trailers:key=CP3-Freshness-Exception,valueonly)' "$c" 2>/dev/null)
    [[ -z "$tr" ]] && { missing_trailer="$c"; break; }
  done < <(git -C "$project_root" rev-list "${reviewed_head}..${current_head}" 2>/dev/null)

  if [[ -n "$missing_trailer" ]]; then
    _cp3_freshness_route "$timeline" "$policy" "missing_exception_trailer" \
      "PRECONDITION FAIL: commit ${missing_trailer} past the reviewed CP3 head lacks a" \
      "        'CP3-Freshness-Exception: <reason>' git trailer (D4 condition b)." \
      "Fix: annotate the commit(s) with the trailer, OR re-dispatch CP3 against HEAD."
    return $?
  fi

  # PASS-with-exception: both D4 conditions hold. Disclose the FULL file list.
  local files_csv=""
  if [[ ${#changed_files[@]} -gt 0 ]]; then
    files_csv=$(printf '%s,' "${changed_files[@]}"); files_csv="${files_csv%,}"
  fi
  [[ -n "$timeline" ]] && log_event "$timeline" "cp3_freshness_exception" \
    reviewed_head="$reviewed_head" head="$current_head" \
    changed_file_count="${#changed_files[@]}" changed_files="$files_csv"
  return 0
}

# fsm_check_orphan_dispatches — Component B of P040 (Dispatch Lifecycle Enforcement Bundle).
# Reads <evidence_dir>/pending-dispatches.jsonl and refuses transition if any
# start event lacks matching complete within expected_duration_max (default 600s
# for CP2, 900s for CP3, 600s for CP4, 1200s for CP1, hard ceiling 1800s).
#
# Empirical anchor: NR 8/10/13/14 fabricated provenance class across 4 projects.
# Enforcement principle: AID-v3-principles.md §1.
fsm_check_orphan_dispatches() {
  local evidence_dir="$1"
  local pending_file="${evidence_dir}/pending-dispatches.jsonl"

  # No pending file = clean (no dispatches were started); skip.
  [[ ! -f "$pending_file" ]] && return 0
  # Empty pending file = all dispatches completed cleanly; skip.
  [[ ! -s "$pending_file" ]] && return 0

  local now_ts
  now_ts=$(date -u +%s)

  # Extract orphan focuses (start events whose ts+expected_duration_max < now).
  # Malformed file = fail loud (see error handling below), NOT silent skip.
  # NOTE: jq_rc must be captured via `|| jq_rc=$?` — under `set -euo pipefail`
  # a bare failing command substitution assignment aborts the script before
  # the next statement runs, so the malformed-file handler below never fires.
  local orphan_focuses jq_err_file jq_rc=0
  jq_err_file=$(mktemp -t orphan-jq-err.XXXXXX)
  orphan_focuses=$(TZ=UTC jq -r --argjson now "$now_ts" '
    select(.event == "start") |
    select((.ts | fromdateiso8601) + .expected_duration_max < $now) |
    .focus
  ' "$pending_file" 2>"$jq_err_file") || jq_rc=$?  # TZ=UTC: jq<1.7 fromdateiso8601 honors local TZ even on Z suffix (P037 lesson, see ~L459)
  if [[ $jq_rc -ne 0 ]]; then
    local jq_stderr; jq_stderr=$(<"$jq_err_file"); rm -f "$jq_err_file"
    echo "ERROR: pending-dispatches.jsonl is malformed; refusing to advance step." >&2
    echo "  File: $pending_file" >&2
    echo "  jq error: $jq_stderr" >&2
    echo "  Fix: inspect file, repair JSONL syntax, OR override:" >&2
    echo "    aid-fsm.sh increment-step <state_file> --force --reason '<≥20 chars>' \\" >&2
    echo "        --blocked-checks 'dispatch_orphan_complete'" >&2
    fsm_emit_audit_log "fsm_orphan_dispatch_fail" \
      --evidence-dir "$evidence_dir" --reason "pending_file_malformed"
    die "pending_file_malformed: $pending_file"
  fi
  rm -f "$jq_err_file"
  orphan_focuses=$(echo "$orphan_focuses" | sort -u)

  if [[ -z "$orphan_focuses" ]]; then
    return 0
  fi

  # Build structured stderr error
  echo "ERROR: Orphan dispatch(es) detected — cannot advance step." >&2
  local focus
  while IFS= read -r focus; do
    [[ -z "$focus" ]] && continue
    local entry started max
    entry=$(jq -c --arg f "$focus" 'select(.focus == $f and .event == "start")' "$pending_file" | tail -1)
    started=$(echo "$entry" | jq -r '.ts')
    max=$(echo "$entry" | jq -r '.expected_duration_max')
    echo "  ORPHAN DISPATCH: focus=$focus started=$started max=${max}s" >&2
    echo "  Fix: bash plugins/aid-orchestrator/scripts/aid-emit-dispatch.sh complete \\" >&2
    echo "         --focus $focus --output-file <verifier-output-*.md path> --evidence-dir $evidence_dir" >&2
  done <<< "$orphan_focuses"

  echo "" >&2
  echo "OR (PM-authorized override, audited):" >&2
  echo "  aid-fsm.sh increment-step <state_file> --force --reason '<≥20 chars why this is acceptable>' \\" >&2
  echo "      --blocked-checks 'dispatch_orphan_complete'" >&2

  # Emit audit log
  local focus_csv orphan_count
  focus_csv=$(echo "$orphan_focuses" | paste -sd, -)
  orphan_count=$(echo "$orphan_focuses" | grep -c .)
  fsm_emit_audit_log "fsm_orphan_dispatch_fail" \
    --evidence-dir "$evidence_dir" \
    --orphan-count "$orphan_count" \
    --orphan-focus-list-array "$focus_csv"

  die "missing_dispatch_complete: $(echo "$orphan_focuses" | head -3 | tr '\n' ' ')"
}

# fsm_check_cp4_curator_validation — Component C of P040 (Dispatch Lifecycle
# Enforcement Bundle). Requires verifier-output-cp4-curator-validation.md when
# curator-report.md exists AND any commit in base_commit..HEAD range touches
# production code paths.
#
# Empirical anchor: NR 10 §3B + NR 12 (curator changes production code without
# CP4 review). Enforcement principle: AID-v3-principles.md §1.
fsm_check_cp4_curator_validation() {
  local evidence_dir="$1"
  local project_root="$2"
  local state_file="${3:-}"
  local curator_report="${evidence_dir}/curator-report.md"

  # No curator commit = no CP4 needed; skip silently.
  [[ ! -f "$curator_report" ]] && return 0

  # P040 Component D coordination: streamlined mode treats CP4 as advisory.
  local streamlined
  streamlined=$(yq -r '.streamlined_mode // false' "$state_file" 2>/dev/null || echo "false")
  if [[ "$streamlined" == "true" ]]; then
    fsm_emit_audit_log "cp4_skipped_streamlined_advisory" \
      --evidence-dir "$evidence_dir" --reason "streamlined_mode CP4 advisory per spec"
    return 0
  fi

  # Resolve base_commit from the FSM state file — scan the FULL EPIC range, not
  # just HEAD. The state file is written as fsm-state.yaml in production but some
  # callers/fixtures name it state.yaml; accept either (P040 Step 3 reconciliation).
  local fsm_state_file="${evidence_dir}/fsm-state.yaml"
  [[ ! -f "$fsm_state_file" && -f "${evidence_dir}/state.yaml" ]] && fsm_state_file="${evidence_dir}/state.yaml"
  local base_commit
  base_commit=$(yq -r '.base_commit' "$fsm_state_file" 2>/dev/null)
  [[ -z "$base_commit" || "$base_commit" == "null" ]] && return 0  # fsm-state unreadable; conservative skip

  # Resolve production-code glob (configurable per project; /aid-init auto-detects)
  local prod_paths
  prod_paths=$(yq -r '.cp4_production_paths // "plugins/|scripts/|src/|lib/|api/"' \
                "${project_root}/.aid-o/config/execution.yaml" 2>/dev/null \
                || echo "plugins/|scripts/|src/|lib/|api/")
  [[ -z "$prod_paths" || "$prod_paths" == "null" ]] && prod_paths="plugins/|scripts/|src/|lib/|api/"

  # LOW-1: validate the prod_paths ERE before relying on a no-match result.
  # grep returns 0=match, 1=no-match, >=2=error (e.g. bad ERE). The old pipeline
  # swallowed ALL non-zero exits via `|| true`, so a malformed cp4_production_paths
  # regex looked identical to "no production files touched" → CP4 silently disabled.
  # FAIL CLOSED on malformed ERE: cannot prove production was NOT touched, so CP4
  # is required. Capture grep's raw exit code directly (not via `! ...`, which
  # would rewrite $? to 0/1).
  local grep_probe_rc=0
  printf '' | grep -E "^(${prod_paths})" >/dev/null 2>&1 || grep_probe_rc=$?
  if [[ "$grep_probe_rc" -ge 2 ]]; then
    fsm_emit_audit_log "cp4_glob_invalid" \
      --evidence-dir "$evidence_dir" \
      --glob "$prod_paths" \
      --reason "cp4_production_paths_invalid_ere"
    echo "ERROR: cp4_production_paths is not a valid ERE — cannot evaluate CP4 (production-touch detection)." >&2
    echo "  Glob: ${prod_paths}" >&2
    echo "  Fix the glob in .aid-o/config/execution.yaml, OR override (audited):" >&2
    echo "    aid-fsm.sh done-advance review release <state_file> --force \\" >&2
    echo "        --reason '<≥20 chars why skipping CP4 is acceptable>' \\" >&2
    echo "        --blocked-checks 'cp4_curator_validation'" >&2
    die "cp4_glob_invalid"
  fi

  # Telemetry: log which glob and range were evaluated (cp4_glob_evaluated — previously
  # documented in agent-protocol.md:278 but never emitted; wired in E-046-1_3 Step 4).
  fsm_emit_audit_log "cp4_glob_evaluated" \
    --base "$base_commit" \
    --evidence-dir "$evidence_dir" \
    --glob "$prod_paths"

  # Did ANY commit in base_commit..HEAD touch production paths?
  # `|| true` guards against set -euo pipefail aborting when grep finds no match
  # (exit 1) — the no-touch case is the legitimate skip path, not an error.
  local touched_prod
  touched_prod=$(git -C "$project_root" diff --name-only "${base_commit}..HEAD" 2>/dev/null \
                   | grep -E "^(${prod_paths})" | head -1 || true)

  if [[ -z "$touched_prod" ]]; then
    # No production touch in EPIC range — emit non-blocking telemetry.
    fsm_emit_audit_log "cp4_skip_no_prod_match" \
      --base "$base_commit" \
      --evidence-dir "$evidence_dir" \
      --glob "$prod_paths"
    return 0
  fi

  # Check for CP4 review file and validate its content via the shared verifier validator.
  local cp4_file="${evidence_dir}/verifier-output-cp4-curator-validation.md"
  if [[ -f "$cp4_file" ]]; then
    fsm_check_verifier_output "$cp4_file" || {
      echo "ERROR: verifier-output-cp4-curator-validation.md is present but invalid." >&2
      echo "  Missing or empty: _generated_by, _generated_at, or classification." >&2
      echo "  Re-dispatch CP4 verifier and overwrite the file with a valid output." >&2
      die "cp4_invalid_content"
    }
    return 0
  fi

  # Hard fail with structured error
  echo "ERROR: CP4 (curator-validation) review missing — cannot advance to release." >&2
  echo "  EPIC range examined: ${base_commit}..HEAD" >&2
  echo "  Production-code paths touched: $touched_prod (plus possibly others; first match shown)" >&2
  echo "  Required file: $cp4_file" >&2
  echo "" >&2
  echo "Fix: dispatch curator-validation verifier and write its output to:" >&2
  echo "  $cp4_file" >&2
  echo "" >&2
  echo "OR (PM-authorized override, audited):" >&2
  echo "  aid-fsm.sh done-advance review release <state_file> --force \\" >&2
  echo "      --reason '<≥20 chars why this skip is acceptable>' \\" >&2
  echo "      --blocked-checks 'cp4_curator_validation'" >&2

  fsm_emit_audit_log "cp4_missing_fail" \
    --base "$base_commit" \
    --touched-prod "$touched_prod" \
    --evidence-dir "$evidence_dir"

  # E-059-2_2 Step 5: this die() preempts the C4 dual-run slot in cmd_done_advance
  # (caller `return 1` unreachable — helper dies internally). Observe telemetry
  # (sampling-bias fix) before the hard-exit; no gate behavior change. project_root
  # is param $2 of this function.
  log_event "${evidence_dir}/timeline.jsonl" "release_policy_preempted" \
    gate="cp4_curator" \
    head_sha="$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo unknown)"
  die "missing_cp4_curator_validation"
}

# fsm_check_streamlined_integration_review — Component D of P040. When
# streamlined_mode is true, refuse done-advance review→release unless all three
# integration-review evidence files exist. Closes the documented contract into
# enforcement per AID-v3-principles.md §1 — Detector without Enforcement is Decoration.
# Full mode skips this check (per-step CP2 evidence covers the same surface).
fsm_check_streamlined_integration_review() {
  local evidence_dir="$1"
  local state_file="$2"
  local streamlined
  streamlined=$(yq -r '.streamlined_mode // false' "$state_file" 2>/dev/null || echo "false")
  [[ "$streamlined" != "true" ]] && return 0
  local cp3_code="${evidence_dir}/verifier-output-cp3-code-review.md"
  local cp3_sec="${evidence_dir}/verifier-output-cp3-security.md"
  local gates="${evidence_dir}/gates_report.json"
  local missing=()
  [[ -f "$cp3_code" ]] || missing+=("verifier-output-cp3-code-review.md")
  [[ -f "$cp3_sec" ]]  || missing+=("verifier-output-cp3-security.md")
  [[ -f "$gates" ]]    || missing+=("gates_report.json")
  if [[ ${#missing[@]} -gt 0 ]]; then
    local joined
    joined=$(IFS=', '; echo "${missing[*]}")
    echo "ERROR: Streamlined run missing required integration-review evidence: ${joined}" >&2
    echo "The streamlined contract requires verifier-output-cp3-code-review.md +" >&2
    echo "verifier-output-cp3-security.md + gates_report.json in:" >&2
    echo "  ${evidence_dir}" >&2
    echo "" >&2
    echo "Fix: dispatch CP3 code-review + CP3 security verifiers and run gates, then retry done-advance." >&2
    echo "" >&2
    echo "OR (PM-authorized override, audited):" >&2
    echo "  aid-fsm.sh done-advance review release <state_file> --force \\" >&2
    echo "      --reason '<≥20 chars explaining why missing integration review is acceptable>' \\" >&2
    echo "      --blocked-checks 'streamlined_integration_review'" >&2
    fsm_emit_audit_log "streamlined_integration_review_fail" \
      --evidence-dir "$evidence_dir" --missing "${joined}"
    # E-059-2_2 Step 5: this die() preempts the C4 dual-run slot in cmd_done_advance
    # (the caller's `return 1` is unreachable — this helper dies internally). Observe
    # telemetry (sampling-bias fix) before the hard-exit; no gate behavior change.
    log_event "${evidence_dir}/timeline.jsonl" "release_policy_preempted" \
      gate="streamlined_integration" \
      head_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    die "streamlined_integration_review"
  fi
  return 0
}

# fsm_check_streamlined_abandoned — Component D of P040. When streamlined_mode is
# true, refuse done-advance if timeline.jsonl has <3 events (run claimed streamlined
# but never executed past initial transition).
# Empirical anchor: NR 12 SOUSTO P009. Enforcement: AID-v3-principles.md §1.
fsm_check_streamlined_abandoned() {
  local evidence_dir="$1"
  local state_file="$2"
  local streamlined
  streamlined=$(yq -r '.streamlined_mode // false' "$state_file" 2>/dev/null || echo "false")
  [[ "$streamlined" != "true" ]] && return 0
  local timeline="${evidence_dir}/timeline.jsonl"
  local event_count=0
  [[ -f "$timeline" ]] && event_count=$(wc -l < "$timeline" | tr -d ' ')
  if [[ "$event_count" -lt 3 ]]; then
    echo "ERROR: Streamlined run abandoned — timeline.jsonl has $event_count event(s)." >&2
    echo "A streamlined run requires at least 3 timeline events (init + transition to EXECUTE + at least one step/phase event);" >&2
    echo "fewer indicates the FSM was never executed past the initial transition (NR 12 SOUSTO P009 anchor pattern)." >&2
    echo "" >&2
    echo "Fix: run the EPIC end-to-end via /aid-run, then retry done-advance." >&2
    echo "" >&2
    echo "OR (PM-authorized override, audited):" >&2
    echo "  aid-fsm.sh done-advance review release <state_file> --force \\" >&2
    echo "      --reason '<≥20 chars explaining why abandonment is acceptable>' \\" >&2
    echo "      --blocked-checks 'streamlined_abandoned'" >&2
    fsm_emit_audit_log "streamlined_abandoned_fail" \
      --evidence-dir "$evidence_dir" --event-count "$event_count"
    # E-059-2_2 Step 5: this die() preempts the C4 dual-run slot in cmd_done_advance
    # (caller `return 1` unreachable — helper dies internally). Observe telemetry
    # (sampling-bias fix) before the hard-exit; no gate behavior change.
    log_event "${evidence_dir}/timeline.jsonl" "release_policy_preempted" \
      gate="streamlined_abandoned" \
      head_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    die "streamlined_abandoned"
  fi
  return 0
}

# Unified dispatcher for --force handling across cmd_init / cmd_transition /
# cmd_increment_step / cmd_done_advance. Validates reason, emits extended
# fsm_force_override timeline event with caller field, and writes persistent
# audit log entry. Reads epic_id, run_id, evidence_dir from caller scope.
fsm_handle_force_override() {
  local from="$1" to="$2" state_file="$3" caller_cmd="$4"
  shift 4
  local reason="" blocked_checks="" blocking_epic="" blocking_plan=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      --blocked-checks) blocked_checks="$2"; shift 2 ;;
      --blocking-epic) blocking_epic="$2"; shift 2 ;;
      --blocking-plan) blocking_plan="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Normalize blocked_checks: strip surrounding commas + whitespace (comma-only delimiter)
  blocked_checks="${blocked_checks// /}"
  blocked_checks="${blocked_checks#,}"
  blocked_checks="${blocked_checks%,}"

  if [[ ${#reason} -lt 20 ]]; then
    die "ERROR: --force requires --reason argument with min 20 characters (got ${#reason}).

Reason: AID v3 telemetry needs forensic-grade audit trail of why FSM was bypassed.
        Empty or short reasons defeat the audit purpose.

Examples:
  aid-fsm.sh transition EXECUTE GATES \$state_file --force --reason \\
    'plan.json bug — step 3 AC has typo blocking gates_no_generated_by check, fix in next EPIC'
  aid-fsm.sh transition GATES DONE \$state_file --force --reason \\
    'security_scan false positive on test fixture, manually verified safe in commit abc1234'
  aid-fsm.sh increment-step \$state_file --force --reason \\
    'step verifier dispatch unavailable due to MCP outage, manually reviewed diff in PR #42'
  aid-fsm.sh done-advance review release \$state_file --force --reason \\
    'auditor agent dispatch failed retry-3, applying P1 finding fix manually'

Then retry with --reason."
  fi

  local timeline="${evidence_dir}/timeline.jsonl"
  local operator="${USER:-unknown}"

  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_force_override" \
    from="$from" to="$to" reason="$reason" \
    caller="$caller_cmd" operator="$operator" \
    blocked_checks="$blocked_checks" \
    blocking_epic="$blocking_epic" blocking_plan="$blocking_plan"

  fsm_emit_audit_log "fsm_force_override" \
    --from "$from" --to "$to" \
    --reason "$reason" --caller "$caller_cmd" --operator "$operator" \
    --blocked-checks-array "$blocked_checks" \
    --blocking-epic "$blocking_epic" --blocking-plan "$blocking_plan"

  # E-059-2_2 Step 5: every --force writes a visible protocol-v2 waiver artifact so
  # the C4 aggregator surfaces the override in waivers_applied[] and the PM surface
  # never sees a silent bypass. Reason is already validated >=20 chars above, so the
  # waiver.reason minLength (waiver.schema.json / aid-protocol-validate exit 17) holds.
  # evidence_dir is read from caller scope; at the cmd_init plan-gate force site it may
  # NOT be materialized yet (the arg loop runs before the dir is created), so mkdir -p
  # first (empty-guard). Best-effort — a waiver write failure never aborts the force.
  if [[ -n "${evidence_dir:-}" ]] && command -v jq >/dev/null 2>&1; then
    mkdir -p "$evidence_dir" 2>/dev/null || true
    local _wv_ts _wv_fname_ts _wv_transition _wv_file _wv_head _wv_top _wv_project _wv_check
    _wv_ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    _wv_fname_ts=$(date -u '+%Y%m%dT%H%M%SZ')
    _wv_transition=$(printf '%s-%s' "$from" "$to" | tr -c 'A-Za-z0-9._-' '_')
    _wv_file="${evidence_dir}/waiver-${_wv_transition}-${_wv_fname_ts}.json"
    _wv_head=$(git rev-parse HEAD 2>/dev/null || echo unknown)
    _wv_top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    _wv_project=$(basename "${_wv_top:-unknown}" 2>/dev/null || echo unknown)
    [[ -z "$_wv_project" || "$_wv_project" == "." || "$_wv_project" == "/" ]] && _wv_project="${epic_id:-unknown}"
    _wv_check="$blocked_checks"
    [[ -z "$_wv_check" ]] && _wv_check="${caller_cmd}:${from}->${to}"

    local _wv_payload _wv_hash _wv_json
    _wv_payload=$(jq -n \
      --arg wc "$_wv_check" --arg rs "$reason" --arg wb "$operator" --arg wa "$_wv_ts" \
      '{waived_check:$wc, reason:$rs, waived_by:$wb, waived_at:$wa, scope:"run", visible:true}') || _wv_payload=""
    if [[ -n "$_wv_payload" ]]; then
      _wv_hash=$(printf '%s' "$_wv_payload" | jq -Sc . 2>/dev/null | sha256sum 2>/dev/null | cut -c1-64) \
        || _wv_hash="0000000000000000000000000000000000000000000000000000000000000000"
      _wv_json=$(jq -n \
        --arg created_at "$_wv_ts" \
        --arg project_id "${_wv_project:-unknown}" \
        --arg epic_id "${epic_id:-unknown}" \
        --arg run_id "${run_id:-unknown}" \
        --arg head_sha "$_wv_head" \
        --arg subject_hash "sha256:${_wv_hash:-0}" \
        --argjson waiver "$_wv_payload" \
        '{
          schema_version: "aid-2.0",
          artifact_type: "waiver",
          producer: "aid-fsm.sh@force-override",
          created_at: $created_at,
          control_protocol: "aid-2.0",
          identity: {project_id: $project_id, epic_id: $epic_id, run_id: $run_id, step_id: null},
          subject: {subject_hash: $subject_hash},
          revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
          status: "blocked",
          verdict: {kind: "none", ready: false},
          provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-fsm.sh"},
          waiver: $waiver
        }') || _wv_json=""
      [[ -n "$_wv_json" ]] && { printf '%s\n' "$_wv_json" > "$_wv_file" 2>/dev/null || true; }
    fi
  fi
}

# Write a single entry to the cross-EPIC audit-log.jsonl (append-only).
# Audit log write failure is best-effort — never aborts primary FSM operation.
fsm_emit_audit_log() {
  local event_type="$1"; shift
  # project_root may be unset in callers that don't set it (e.g. cmd_transition
  # --force) — derive from CWD with the :- guard so `set -u` doesn't abort here.
  local audit_log_file="${project_root:-.}/.aid-o/work/audit-log.jsonl"
  bash "${SCRIPT_DIR}/aid-audit-log.sh" append \
    --epic-id "${epic_id:-unknown}" \
    --run-id  "${run_id:-unknown}" \
    --event   "$event_type" \
    "$@" \
    --output  "$audit_log_file" 2>/dev/null || true
}

# P038 Step 3: pure helper that maps a flat checks{} JSON object to a
# failures[] array, looking up severity in the project-level severity
# registry (check-severity.yaml). Returns "[]" when no failures detected or
# yq unavailable / registry file missing — all paths fall through to
# advisory defaults so missing-config is a safe no-op.
#
# Inputs:
#   $1 — checks_json (the JSON object produced by evaluate_compliance_checks)
#   $2 — severity_yaml (absolute path to .aid-o/config/check-severity.yaml)
#
# Behavior:
#   - When checks_json has a .verifier_outputs.provenance_aggregate == "unverifiable"
#     marker, a synthetic verifier_provenance failure entry is prepended (fail-closed
#     at severity: blocking when the registry can't be read — see below).
#   - Each boolean-false top-level scalar in checks_json yields one entry.
#   - severity + promoted_at are enriched from the registry; missing keys
#     default to {severity: "advisory", promoted_at: null}.
#   - Output is always a JSON array (even on internal jq error → "[]").
fsm_build_failures() {
  local checks_json="$1" severity_yaml="$2"
  local registry_json='{}'
  local prov_agg_value
  local failures_json='[]'

  # Step A: load registry into a JSON object (best-effort).
  if [[ -f "$severity_yaml" ]]; then
    if command -v yq >/dev/null 2>&1; then
      registry_json=$(yq -o=json eval '.checks // {}' "$severity_yaml" 2>/dev/null || echo '{}')
      # Guard against yq emitting non-JSON on malformed input.
      if ! echo "$registry_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        log_warn "check-severity.yaml parse error — falling back to advisory defaults"
        registry_json='{}'
      fi
    else
      log_warn "yq not installed — failures[] severities default to advisory (install yq to enable per-check severity)"
    fi
  fi

  # Extract provenance_aggregate marker (synthetic verifier_provenance failure trigger).
  prov_agg_value=$(echo "$checks_json" | jq -r '.verifier_outputs.provenance_aggregate // empty' 2>/dev/null || echo "")

  # Fail-closed notice: if provenance is unverifiable AND the registry could not be
  # read, the synthetic entry below floors at severity: blocking (never advisory).
  if [[ "$prov_agg_value" == "unverifiable" && "$registry_json" == "{}" ]]; then
    log_warn "verifier_provenance unverifiable with no readable severity registry — treating as BLOCKING (fail-closed, AID-046)"
  fi

  # Step B: build failures[] from boolean-false top-level checks +
  # provenance_aggregate unverifiable marker; enrich each entry's severity +
  # promoted_at from the registry, defaulting to advisory when absent.
  failures_json=$(echo "$checks_json" | jq -c \
    --argjson reg "$registry_json" \
    --arg prov_agg "$prov_agg_value" \
    '
    def enrich(entry):
      ($reg[entry.check] // null) as $r |
      entry
      | .severity    = (if $r then ($r.severity    // "advisory") else "advisory" end)
      | .promoted_at = (if $r then ($r.promoted_at // null)       else null       end);

    [
      (to_entries[]
        | select(.value == false)
        | {check: .key,
           severity: "advisory",
           evidence: ("\(.key) returned false"),
           promoted_at: null}
        | enrich(.)),
      (if $prov_agg == "unverifiable" then
        # Integrity check — fail-closed. Default severity is "blocking" (NOT advisory)
        # so an unreadable severity registry (e.g. yq absent → $reg == {}) cannot
        # silently disarm the provenance block. A PM may keep it blocking via the
        # registry, but a MISSING registry entry floors at "blocking", never advisory.
        {check: "verifier_provenance",
         evidence: "provenance_aggregate=unverifiable (1+ verifier outputs could not be verified against the dispatch timeline; integrity signal, not proof of fraud)",
         promoted_at: null}
        | (($reg["verifier_provenance"] // null) as $r
           | .severity    = (if $r then ($r.severity // "blocking") else "blocking" end)
           | .promoted_at = (if $r then ($r.promoted_at // null)    else null       end))
       else empty end)
    ]
    ' 2>/dev/null || echo '[]')

  # Final safety net: if anything went sideways, force empty array.
  if ! echo "$failures_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    failures_json='[]'
  fi

  printf '%s\n' "$failures_json"
}

# ─── P042: Compliance Recovery Detection ─────────────────────────────────────
# fsm_check_compliance_recovery — detect a pending blocking-compliance alert
# that has not yet been paired with a recovery event.
#
# A "pending block" means: the timeline contains at least one
# fsm_done_advance_blocked event, and no fsm_done_advance_recovered event
# appears AFTER the last blocked event (i.e. the block has not been cleared).
#
# Inputs:
#   $1 — timeline_path (path to timeline.jsonl for this EPIC run)
#
# Returns (via exit code):
#   0 — pending block found; echoes comma-joined blocked_checks from the last
#       fsm_done_advance_blocked event to stdout.
#   1 — no pending block (timeline missing / unreadable / no blocked event /
#       a recovered event already follows the last blocked event) or any
#       parse error (soft-fail).
#
# Soft-fail contract: any jq / file error returns 1 (no-alert, never crashes
# the done-advance transition). Never writes to stderr on expected conditions.
fsm_check_compliance_recovery() {
  local timeline_path="$1"

  [[ -f "$timeline_path" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  # Find the positional index (0-based) of the last fsm_done_advance_blocked
  # and fsm_done_advance_recovered events; -1 means "not found".
  local last_blocked_idx last_recovered_idx
  last_blocked_idx=$(jq -s 'to_entries
    | map(select(.value.event == "fsm_done_advance_blocked"))
    | if length == 0 then -1 else last.key end' \
    "$timeline_path" 2>/dev/null)
  last_recovered_idx=$(jq -s 'to_entries
    | map(select(.value.event == "fsm_done_advance_recovered"))
    | if length == 0 then -1 else last.key end' \
    "$timeline_path" 2>/dev/null)

  # Soft-fail on parse error (empty output)
  [[ -z "$last_blocked_idx" || -z "$last_recovered_idx" ]] && return 1

  # No blocked event at all → nothing to recover from
  [[ "$last_blocked_idx" == "-1" ]] && return 1

  # A recovered event exists AND comes after the last blocked event → already cleared
  if [[ "$last_recovered_idx" != "-1" && "$last_recovered_idx" -gt "$last_blocked_idx" ]]; then
    return 1
  fi

  # Pending block found — echo blocked_checks from the last blocked event
  local blocked_checks
  blocked_checks=$(jq -rs --argjson idx "$last_blocked_idx" \
    '.[$idx].blocked_checks // ""' \
    "$timeline_path" 2>/dev/null) || blocked_checks=""
  echo "$blocked_checks"
  return 0
}

# fsm_emit_compliance_recovery — shared emitter for the P042 recovery alert.
# Pairs a pending fsm_done_advance_blocked event with a ✅ Telegram alert +
# fsm_done_advance_recovered timeline event (the dedup marker). Called from
# BOTH review→release resolution paths of cmd_done_advance: the clean re-run
# (zero blocking failures) and the PM --force override (P044 — previously the
# force path skipped recovery entirely, so force-cleared blocks never alerted).
#
# Inputs:
#   $1 — epic_id
#   $2 — timeline path
#   $3 — project_root
#   $4 — alert message prefix ("; Checks: <list>" is appended here)
#
# The timeline event is written unconditionally (dedup marker) — only the
# Telegram alert is gated by execution.yaml alert_on_compliance_recovery
# (default on when key absent). Always returns 0 (best-effort, never blocks
# the transition).
fsm_emit_compliance_recovery() {
  local epic_id="$1" timeline="$2" project_root="$3" message_prefix="$4"
  local recovery_checks
  recovery_checks=$(fsm_check_compliance_recovery "$timeline" 2>/dev/null) || return 0
  local recovery_gate
  recovery_gate=$(grep -E '^    alert_on_compliance_recovery:' "${project_root}/.aid-o/config/execution.yaml" 2>/dev/null \
    | awk '{print $2}' | tr -d '"'"'"' ') || recovery_gate=""
  recovery_gate="${recovery_gate:-true}"
  [[ "$recovery_gate" == "false" ]] || \
    try_telegram_alert "${message_prefix} Checks: ${recovery_checks}"
  [[ -f "$timeline" ]] && log_event "$timeline" "fsm_done_advance_recovered" \
    recovered_checks="$recovery_checks"
  return 0
}

# Best-effort Telegram alert via svc-mcp-tg-bot HTTP transport (port 8817 —
# replaces the legacy svc-mcp-telegram MCP that previously held this port).
# Never fails — if MCP service is unavailable, log info and continue.
# Service deployed in Step 6; this helper works pre-deploy as a no-op.
#
# Test-mode guard: bats fixtures and other test contexts export AID_TEST_MODE=1
# in their setup() to suppress real-world side effects. The same guard pattern
# should be added to any future side-effect helpers (mail, Slack, webhook).
try_telegram_alert() {
  [[ "${AID_TEST_MODE:-0}" == "1" ]] && return 0
  local message=$1
  local payload
  payload=$(jq -nc --arg t "$message" '{text:$t, parse_mode:"HTML"}')
  if curl -fsS -X POST http://localhost:8817/send_message \
       -H "Content-Type: application/json" \
       --data "$payload" \
       --max-time 3 \
       > /dev/null 2>&1; then
    return 0
  fi
  log_info "Telegram alert skipped (svc-mcp-tg-bot not available — non-fatal)"
  return 0
}

# ─── P032 Step 4: Compliance.json Helpers ────────────────────────────────
# evaluate_compliance_checks emits the 6-dimension `checks` object.
# write_compliance_json wraps it with run metadata + overall verdict + writes
# the per-EPIC compliance.json + emits the `compliance_written` timeline event.

# ─── P037 Step 3: Provenance Verification Helper ──────────────────────────
# verify_provenance cross-references a verifier output's _generated_by/_generated_at
# metadata against the actual dispatch evidence:
#   - agent_tool mode (default, P043): CC Agent tool writes no timeline events —
#     returns the non-blocking "agent_tool" sentinel without checking.
#   - subagent mode: timeline.jsonl must show verifier_dispatch_start +
#     verifier_dispatch_complete events for this focus within ±window_s of
#     the claimed _generated_at timestamp.
#   - inline mode: _generated_by must match main-context@<sha>, and the SHA
#     must resolve in the project's git object database.
# Returns one of: "verified", "inline", "agent_tool", "unverifiable", "unknown".
# NOTE: "unverifiable" means the output's provenance could not be confirmed against
# the dispatch timeline (stale / missing / mismatched dispatch records). It is an
# integrity signal, NOT proof of deliberate fraud — a determined main-context
# fabricator could forge the timeline too. The real anti-fabrication defenses are the
# orchestrator's MUST-dispatch / MUST-NOT-self-review instruction (pipeline.md), the
# independent auditor, and the orphan-dispatch check.
verify_provenance() {
  # IMP-103 (v2.20.2): $3 (step_n) is intentionally unused — kept in signature for
  # API stability and future per-step forensics (e.g. error-path attribution by
  # step index). Renamed to _step_n to mark unused without shifting positional args
  # at the 3 call sites (CP2 loop + CP3 code-review + CP3 security).
  local verifier_output_file=$1 focus=$2 _step_n=$3 dispatch_mode=$4 timeline_file=$5 window_s=$6

  local generated_by generated_at
  generated_by=$(yaml_field "$verifier_output_file" _generated_by)
  generated_at=$(yaml_field "$verifier_output_file" _generated_at)

  [[ -z "$generated_by" || -z "$generated_at" ]] && { echo "unverifiable"; return; }

  case "$dispatch_mode" in
    subagent)
      # Interval-bracket provenance (AID-046). The output must have been generated
      # DURING a real dispatch interval for this focus — at/after the earliest
      # verifier_dispatch_start and at/before the latest verifier_dispatch_complete,
      # with a small clock-skew tolerance (window_s) on each side. This is robust to
      # the verification DURATION (minutes). The previous logic required BOTH the start
      # AND the complete event to fall within ±window_s of _generated_at, which flagged
      # any honest run longer than window_s as unverifiable (the start event sits a full
      # verification-duration before _generated_at). That false-positive bit P040's own
      # ship. We now bracket by the real start..complete interval.
      [[ ! -f "$timeline_file" ]] && { echo "unverifiable"; return; }
      local gen_epoch
      gen_epoch=$(date -d "$generated_at" +%s 2>/dev/null || echo "0")
      [[ "$gen_epoch" == "0" ]] && { echo "unverifiable"; return; }

      # TZ=UTC required: jq <1.7 fromdateiso8601 silently honors local TZ even with Z
      # suffix, producing 1-3600s offset on non-UTC hosts (CEST/PST/etc). Discovered
      # during P037 Step 5 bats smoke test (jq 1.6 on CEST host). $gen_epoch is a UTC
      # epoch from `date -d`; force jq to match.
      local start_ts complete_ts
      start_ts=$(TZ=UTC jq -s --arg f "$focus" '
        [.[] | select(.event == "verifier_dispatch_start" and .focus == $f) | (.ts | fromdateiso8601)] | min // empty' "$timeline_file" 2>/dev/null || echo "")
      complete_ts=$(TZ=UTC jq -s --arg f "$focus" '
        [.[] | select(.event == "verifier_dispatch_complete" and .focus == $f) | (.ts | fromdateiso8601)] | max // empty' "$timeline_file" 2>/dev/null || echo "")

      # Require a matched start AND complete pair for this focus.
      if [[ -z "$start_ts" || -z "$complete_ts" ]]; then
        echo "unverifiable"; return
      fi
      local lo=$((start_ts - window_s))
      local hi=$((complete_ts + window_s))
      if (( start_ts <= complete_ts && gen_epoch >= lo && gen_epoch <= hi )); then
        echo "verified"
      else
        echo "unverifiable"
      fi
      ;;
    agent_tool)
      # CC Agent tool writes no timeline events → interval-bracket provenance is
      # structurally unavailable. Non-blocking sentinel; integrity contract is
      # upheld by pipeline.md dispatch rules + independent auditor (rationale in
      # evaluate_compliance_checks below).
      echo "agent_tool"
      ;;
    inline)
      # Validate main-context@<sha> format + SHA exists in repo
      if [[ "$generated_by" =~ ^main-context@([a-f0-9]{7,40})$ ]]; then
        local sha="${BASH_REMATCH[1]}"
        if command -v git >/dev/null 2>&1 && git -C "$project_root" cat-file -e "$sha" 2>/dev/null; then
          echo "inline"
        else
          echo "unverifiable"
        fi
      else
        echo "unverifiable"
      fi
      ;;
    *)
      echo "unverifiable"
      ;;
  esac
}

# ─── P045: delivery_report_present (plan-boundary structural presence check) ──
# Echoes a JSON literal — null | true | false — for the delivery report at the
# plan boundary. Surfaced ONLY through the existing _blocking_count severity gate
# in cmd_done_advance review→release (advisory by default; no die(), no new gate).
#   null  — plan boundary NOT reached for this EPIC (no ca-review-complete marker),
#           or yq unavailable (conservative not-applicable; never a failure).
#   true  — at boundary AND .aid-o/reports/{plan_id}-delivery.md exists AND its
#           _test_evidence[] references >=1 file present on disk under evidence_dir.
#   false — at boundary AND report missing, OR no _test_evidence references a file
#           that exists on disk (advisory failure; release still proceeds).
# plan_id is derived from epic_id (E-045-1_1 -> P045). The report is one plan-level
# fact, so every EPIC of the plan resolves it identically once the marker exists.
fsm_eval_delivery_report_present() {
  local epic_id="$1" evidence_dir="$2" project_root="$3"

  # Plan-boundary signal: ca-review-complete marker in this EPIC's evidence dir.
  # Before the boundary the check is not applicable → null (cannot false-fail a
  # non-final EPIC).
  [[ -f "${evidence_dir}/ca-review-complete" ]] || { echo null; return 0; }

  # Frontmatter inspection needs yq; conservative null if absent.
  command -v yq >/dev/null 2>&1 || { echo null; return 0; }

  # Derive plan_id from epic_id (E-045-1_1 -> P045).
  local plan_num plan_id
  plan_num=""
  [[ "$epic_id" =~ ^E-([0-9]+) ]] && plan_num="${BASH_REMATCH[1]}"
  [[ -z "$plan_num" ]] && { echo null; return 0; }
  plan_id="P${plan_num}"

  local report="${project_root}/.aid-o/reports/${plan_id}-delivery.md"
  [[ -f "$report" ]] || { echo false; return 0; }

  # _test_evidence[] validation lives in the shared lib (B1) so this FSM check and
  # the C4 release aggregator read one substrate. Echoes true|false; the yq guard
  # inside is defensive (this function already returned null above when yq is
  # missing, so the external behavior here is byte-identical to the prior inline
  # block: report present + >=1 in-tree _test_evidence path on disk → true, else false).
  _aid_validate_test_evidence "$report" "$evidence_dir"
}

# ─── Helper: read toggle status from execution.yaml ──────────────────────────
# _aid_read_toggle is now provided by lib/aid-review-signals.sh (sourced at the
# top of this file) — one substrate shared with the C4 release aggregator (B1).
# Callers here (fsm_eval_simplifier_present, cmd_plan_close) are unchanged.

# ─── E-046-2_3 Step 4: simplifier_report_present (plan-boundary measurement) ──
# null  — plan boundary not reached (no ca-review-complete marker), OR
#         simplifier.enabled:false in execution.yaml (N/A; no report expected).
# true  — at boundary AND simplifier-report.md present in evidence_dir.
# false — at boundary AND simplifier-report.md missing (advisory; never blocks).
# MEASUREMENT ONLY — enforcement in a future step.
fsm_eval_simplifier_present() {
  local epic_id="$1" evidence_dir="$2" project_root="$3"

  # Plan-boundary signal: ca-review-complete marker in this EPIC's evidence dir.
  [[ -f "${evidence_dir}/ca-review-complete" ]] || { echo null; return 0; }

  # Respect simplifier.enabled:false toggle in execution.yaml — N/A when disabled.
  local exec_yaml="${project_root}/.aid-o/config/execution.yaml"
  _aid_read_toggle "$exec_yaml" "simplifier" || { echo null; return 0; }

  if [[ -f "${evidence_dir}/simplifier-report.md" ]]; then
    echo true
  else
    echo false
  fi
}

evaluate_compliance_checks() {
  local epic_id=$1 state_file=$2 evidence_dir=$3 project_root=$4

  # P037 Step 3 / P043: dispatch_mode resolution (used by verify_provenance below).
  # Precedence: project .aid-o/config/plugin.yaml `dispatch_mode:` → plugin
  # defaults/orchestration.yaml `dispatch.mode` (single source of the default)
  # → hard fallback "agent_tool" (yq missing / defaults unreadable).
  local dispatch_mode timeline_window_s
  dispatch_mode=$(yq -r '.dispatch_mode' "${project_root}/.aid-o/config/plugin.yaml" 2>/dev/null) || dispatch_mode=""
  if [[ -z "$dispatch_mode" || "$dispatch_mode" == "null" ]]; then
    dispatch_mode=$(yq -r '.dispatch.mode' "${SCRIPT_DIR}/../defaults/orchestration.yaml" 2>/dev/null) || dispatch_mode=""
  fi
  [[ -z "$dispatch_mode" || "$dispatch_mode" == "null" ]] && dispatch_mode="agent_tool"
  timeline_window_s=$(yq -r '.dispatch.timeline_window_seconds // 60' "${SCRIPT_DIR}/../defaults/orchestration.yaml" 2>/dev/null || echo "60")
  [[ -z "$timeline_window_s" || "$timeline_window_s" == "null" ]] && timeline_window_s=60

  # branch_correct: fsm-state.yaml.branch matches Session A naming convention
  # (^task/E-...). Cross-prefix EPICs (B-051, etc.) report false here — out of
  # Session A scope; Sessions B/C may relax the regex.
  local branch_value branch_correct
  branch_value=$(yaml_field "$state_file" branch)
  if [[ "$branch_value" =~ ^task/E- ]]; then
    branch_correct=true
  else
    branch_correct=false
  fi

  # execution_yaml_present: project-level config exists (eager-created by
  # /aid-init or auto-recovered by aid-fsm.sh init in Step 1).
  local exec_yaml_present
  if [[ -f "${project_root}/.aid-o/config/execution.yaml" ]]; then
    exec_yaml_present=true
  else
    exec_yaml_present=false
  fi

  # gates_generated_by: gates_report.json carries the runner's provenance.
  # Hand-written reports (pre-Session-A pattern) lack this field.
  local gates_report="${evidence_dir}/gates/gates_report.json"
  local gates_genby
  if [[ -f "$gates_report" ]] && jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
    gates_genby=true
  else
    gates_genby=false
  fi

  # Session B: verifier_outputs object schema (CP2 per-step + CP3 code-review + security)
  local cp2_dispatched cp2_verdict cp3_cr_d cp3_cr_v cp3_sec_d cp3_sec_v aggregate

  # P037 Step 3: per-step provenance tracking (parallel to dispatched/verdict).
  local -a cp2_provenances=()
  local cp3_cr_provenance="unknown" cp3_sec_provenance="unknown"

  # CP2 per-step: ALL step-*-verify.md must have a valid verifier-output-step-N.md
  local total_steps cp2_passed cp2_failed
  total_steps=$(find "$evidence_dir" -maxdepth 1 -name "step-*-verify.md" 2>/dev/null | wc -l)
  cp2_passed=0; cp2_failed=0
  for v in "$evidence_dir"/step-*-verify.md; do
    [[ -f "$v" ]] || continue
    local step_n
    step_n=$(basename "$v" | grep -oP '\d+' || true)
    [[ -z "$step_n" ]] && continue
    local vo="${evidence_dir}/verifier-output-step-${step_n}.md"
    if [[ -f "$vo" ]] && grep -q '^_generated_by:' "$vo" 2>/dev/null && grep -q '^classification:' "$vo" 2>/dev/null; then
      cp2_passed=$((cp2_passed + 1))
      local _v_status
      _v_status=$(yaml_field "$vo" verdict)
      [[ "$_v_status" == "fail" ]] && cp2_failed=$((cp2_failed + 1))
      # P037 Step 3: provenance cross-reference for this verifier output
      local _prov
      _prov=$(verify_provenance "$vo" "cp2-step-${step_n}" "$step_n" "$dispatch_mode" "${evidence_dir}/timeline.jsonl" "$timeline_window_s")
      cp2_provenances+=("$_prov")
    else
      # Missing or incomplete verifier output → unknown provenance for this step
      cp2_provenances+=("unknown")
    fi
  done

  if (( total_steps == 0 )); then
    cp2_dispatched=null; cp2_verdict=null
  elif (( cp2_passed == total_steps )); then
    cp2_dispatched=true
    if   (( cp2_failed == 0 ));           then cp2_verdict='"pass"'
    elif (( cp2_failed == total_steps )); then cp2_verdict='"fail"'
    else                                       cp2_verdict='"mixed"'; fi
  else
    cp2_dispatched=false; cp2_verdict=null
  fi

  # CP3 verifier outputs (code-review + security) — identical evaluation, two
  # focuses. Echoes "dispatched|verdict_json|provenance" (P037 Step 3 provenance
  # cross-reference included). Reads dispatch_mode/evidence_dir/timeline_window_s
  # from caller scope (file convention, see fsm_count_fails_matching).
  _cp3_check() {
    local file="${evidence_dir}/verifier-output-cp3-${1}.md" focus="cp3-${1}"
    if [[ -f "$file" ]] && grep -q '^_generated_by:' "$file" 2>/dev/null; then
      local v
      v=$(yaml_field "$file" verdict)
      printf 'true|"%s"|%s\n' "${v:-unknown}" \
        "$(verify_provenance "$file" "$focus" "null" "$dispatch_mode" "${evidence_dir}/timeline.jsonl" "$timeline_window_s")"
    else
      printf 'false|null|unknown\n'
    fi
  }
  IFS='|' read -r cp3_cr_d cp3_cr_v cp3_cr_provenance < <(_cp3_check "code-review")
  IFS='|' read -r cp3_sec_d cp3_sec_v cp3_sec_provenance < <(_cp3_check "security")

  # aggregate: all three dispatched = true; null if CP2 is N/A (0 steps)
  if [[ "$cp2_dispatched" == "true" && "$cp3_cr_d" == "true" && "$cp3_sec_d" == "true" ]]; then
    aggregate=true
  elif [[ "$cp2_dispatched" == "null" ]]; then
    aggregate=null
  else
    aggregate=false
  fi

  # P037 Step 3: per-step CP2 provenance as a JSON array (auditable per step).
  local cp2_prov_array_json
  if (( ${#cp2_provenances[@]} == 0 )); then
    cp2_prov_array_json='[]'
  else
    cp2_prov_array_json=$(printf '%s\n' "${cp2_provenances[@]}" | jq -R . | jq -sc .)
  fi

  # P037 Step 3: provenance_aggregate — worst-of summary across all dispatches.
  #   unverifiable > mixed > all_inline > all_verified (unknown if no data at all)
  # Semantics: if any single provenance is "unverifiable", aggregate is "unverifiable".
  # Else if all non-unknown are "verified" → "all_verified".
  # Else if all non-unknown are "inline" → "all_inline".
  # Else "mixed". If everything is unknown → "unknown".
  # agent_tool mode short-circuits to "agent_tool": every per-output value is the
  # agent_tool sentinel (mode is uniform per run), which would otherwise misreport
  # as "mixed" (neither all_verified nor all_inline).
  local all_verified=true all_inline=true any_unverifiable=false any_known=false
  local p
  for p in "${cp2_provenances[@]}" "$cp3_cr_provenance" "$cp3_sec_provenance"; do
    [[ -z "$p" || "$p" == "unknown" ]] && continue
    any_known=true
    [[ "$p" == "unverifiable" ]] && any_unverifiable=true
    [[ "$p" != "verified" ]] && all_verified=false
    [[ "$p" != "inline" ]] && all_inline=false
  done

  local prov_agg
  if [[ "$dispatch_mode" == "agent_tool" ]]; then
    prov_agg='"agent_tool"'
  elif $any_unverifiable; then
    prov_agg='"unverifiable"'
  elif ! $any_known; then
    prov_agg='"unknown"'
  elif $all_verified; then
    prov_agg='"all_verified"'
  elif $all_inline; then
    prov_agg='"all_inline"'
  else
    prov_agg='"mixed"'
  fi

  # Phase 2 (P037) — plan_ac_match dimension
  local plan_ac_match
  local plan_diff_file="${evidence_dir}/plan-diff.json"

  if [[ -f "$plan_diff_file" ]]; then
    # Single jq read for both fields — /simplify efficiency finding (was 2 forks).
    local overall_verdict ac_count
    IFS=$'\t' read -r overall_verdict ac_count < <(
      jq -r '[(.overall_verdict // ""), (.ac_count // 0)] | @tsv' "$plan_diff_file" 2>/dev/null \
        || printf '\t0'
    )

    if [[ "$ac_count" -eq 0 || "$overall_verdict" == "skipped" ]]; then
      plan_ac_match=null  # graceful skip — legacy plan or no AC patterns
    elif [[ "$overall_verdict" == "pass" ]]; then
      plan_ac_match=true
    elif [[ "$overall_verdict" == "fail" ]]; then
      plan_ac_match=false
    else
      plan_ac_match=null  # unknown verdict — conservative skip
    fi
  else
    plan_ac_match=null  # plan-diff.json missing — backward compat, treated as skip
  fi

  # P045: delivery_report_present — plan-boundary structural presence (null/true/false).
  local delivery_report_present
  delivery_report_present=$(fsm_eval_delivery_report_present "$epic_id" "$evidence_dir" "$project_root")

  # E-046-2_3 Step 4: simplifier_report_present — measurement only (advisory).
  local simplifier_report_present
  simplifier_report_present=$(fsm_eval_simplifier_present "$epic_id" "$evidence_dir" "$project_root")

  jq -nc \
    --argjson bc          "$branch_correct" \
    --argjson eyp         "$exec_yaml_present" \
    --argjson ggb         "$gates_genby" \
    --argjson pam         "$plan_ac_match" \
    --argjson cp2_d       "$cp2_dispatched" \
    --argjson cp2_v       "$cp2_verdict" \
    --argjson cp2_prov    "$cp2_prov_array_json" \
    --argjson cp3crd      "$cp3_cr_d" \
    --argjson cp3crv      "$cp3_cr_v" \
    --arg     cp3cr_prov  "$cp3_cr_provenance" \
    --argjson cp3secd     "$cp3_sec_d" \
    --argjson cp3secv     "$cp3_sec_v" \
    --arg     cp3sec_prov "$cp3_sec_provenance" \
    --argjson agg         "$aggregate" \
    --argjson prov_agg    "$prov_agg" \
    --argjson drp         "$delivery_report_present" \
    --argjson srp         "$simplifier_report_present" \
    '{
      branch_correct:         $bc,
      execution_yaml_present: $eyp,
      gates_generated_by:     $ggb,
      plan_ac_match:          $pam,
      memory_substantive:     null,
      verifier_outputs: {
        cp2_per_step_dispatched:    $cp2_d,
        cp2_per_step_verdict:       $cp2_v,
        cp2_per_step_provenance:    $cp2_prov,
        cp3_code_review_dispatched: $cp3crd,
        cp3_code_review_verdict:    $cp3crv,
        cp3_code_review_provenance: $cp3cr_prov,
        cp3_security_dispatched:    $cp3secd,
        cp3_security_verdict:       $cp3secv,
        cp3_security_provenance:    $cp3sec_prov,
        aggregate:                  $agg,
        provenance_aggregate:       $prov_agg
      },
      dod_present: null,
      delivery_report_present: $drp,
      simplifier_report_present: $srp
    }'
}

write_compliance_json() {
  local epic_id=$1 run_id=$2 state_file=$3 evidence_dir=$4 project_root=$5
  local compliance_file="${evidence_dir}/compliance.json"
  local _timeline="${evidence_dir}/timeline.jsonl"

  # Session B: three-tier deploy_era enum (pre-session-a | post-session-a | post-session-b).
  # Session A hardcoded deploy date; Session B date read from DEPLOY_DATE file (Step 10),
  # far-future fallback until that file is written.
  local deploy_era
  local _created_at _session_a_deploy _session_b_deploy
  _created_at=$(yaml_field "$state_file" created_at)
  _session_a_deploy="2026-05-05T16:37:52Z"
  if [[ -f "${SCRIPT_DIR}/../DEPLOY_DATE" ]]; then
    _session_b_deploy=$(cat "${SCRIPT_DIR}/../DEPLOY_DATE" 2>/dev/null || echo "2099-01-01T00:00:00Z")
  else
    _session_b_deploy="2099-01-01T00:00:00Z"
  fi

  if [[ -z "$_created_at" || "$_created_at" < "$_session_a_deploy" ]]; then
    deploy_era="pre-session-a"
  elif [[ "$_created_at" < "$_session_b_deploy" ]]; then
    deploy_era="post-session-a"
  else
    deploy_era="post-session-b"
  fi

  # force_override fields: count + reasons from this EPIC's timeline.jsonl.
  # M6 fallback: pre-Session-B events have no .reason field → substitute marker
  # string so aggregator can identify them as historical noise (not actionable).
  local force_count force_reasons
  if [[ -f "$_timeline" ]]; then
    force_count=$(jq -s '[.[] | select(.event=="fsm_force_override")] | length' "$_timeline" 2>/dev/null || echo "0")
    force_reasons=$(jq -s '[.[] | select(.event=="fsm_force_override") | (.reason // "<pre-session-b legacy>")]' "$_timeline" 2>/dev/null || echo "[]")
  else
    force_count=0
    force_reasons='[]'
  fi

  local checks
  if ! checks=$(evaluate_compliance_checks "$epic_id" "$state_file" "$evidence_dir" "$project_root" 2>&1); then
    # Fallback: write skeleton so the aggregator can still see this EPIC ran;
    # never abort done-advance because of telemetry — primary release path is
    # what matters.
    log_warn "compliance.json evaluation failed: ${checks}"
    jq -nc \
      --arg epic "$epic_id" --arg run "$run_id" --arg ver "v3" \
      --arg era "$deploy_era" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg note "evaluation failed: ${checks}" \
      --argjson fc "$force_count" \
      --argjson fr "$force_reasons" \
      '{
        epic_id: $epic, run_id: $run, aid_version: $ver,
        deploy_era: $era, evaluated_at: $ts,
        checks: {
          branch_correct: null, execution_yaml_present: null, gates_generated_by: null,
          memory_substantive: null, verifier_outputs: null, dod_present: null
        },
        force_override_count: $fc,
        force_override_reasons: $fr,
        overall: "fail",
        notes: [$note]
      }' > "$compliance_file"
    log_event "$_timeline" "compliance_written" deploy_era="$deploy_era" overall="fail" checks_passed="0" checks_failed="0"
    return 0
  fi

  # overall: check the top-level scalar dimensions + verifier_outputs.aggregate.
  # verifier_outputs is now an object — use type-aware extraction for backward compat
  # with any pre-Session-B compliance.json files that have boolean/null there.
  # null counts as pass (= "not yet measured in this era").
  # Phase 2 (P037): plan_ac_match contributes to overall, null = no impact (skip).
  local overall_pre notes_json
  overall_pre=$(echo "$checks" | jq -r '
    [.branch_correct, .execution_yaml_present, .gates_generated_by, .plan_ac_match,
     (.verifier_outputs | if type == "object" then .aggregate else . end)]
    | all(. == true or . == null)
    | if . then "pass" else "fail" end' 2>/dev/null || echo "fail")
  notes_json='[]'

  # P037 Step 3: provenance_aggregate unverifiable override — if any verifier output's
  # provenance can't be verified against the dispatch timeline, force overall=fail.
  local prov_agg_value
  prov_agg_value=$(echo "$checks" | jq -r '.verifier_outputs.provenance_aggregate // empty' 2>/dev/null || echo "")
  if [[ "$prov_agg_value" == "unverifiable" ]]; then
    overall_pre="fail"
    notes_json=$(jq -nc --arg n "provenance_aggregate: unverifiable — at least one verifier output could not be verified against the dispatch timeline (integrity signal, not proof of fraud)" '[$n]')
  fi

  # P038 Step 3: failures[] is built by the shared fsm_build_failures helper
  # so the cmd_done_advance precondition and write_compliance_json share one
  # implementation. Helper is defensive against missing yq / missing registry /
  # malformed yaml — all paths fall through to advisory defaults.
  local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"
  local failures_json
  failures_json=$(fsm_build_failures "$checks" "$severity_yaml")

  # Severity-aware overall (E-047-6 REOPEN #8): `overall` MUST agree with the
  # release gate, which blocks on BLOCKING failures only (cmd_done_advance). A
  # failure recorded at severity "advisory" (e.g. branch_correct on a
  # PM-controlled shared feature branch) is surfaced in failures[] for visibility
  # but MUST NOT flip overall to "fail" — otherwise the record reads overall:fail
  # while the FSM correctly released, a self-contradiction. A detector at advisory
  # severity must not behave like a blocking gate (AID-v3-principles §1). The
  # provenance-unverifiable integrity signal stays blocking (it already forced
  # overall_pre=fail + a note above and is re-asserted here).
  local _blocking_failures
  _blocking_failures=$(echo "$failures_json" | jq '[.[] | select(.severity != "advisory")] | length' 2>/dev/null || echo 0)
  if [[ "${_blocking_failures:-0}" -gt 0 || "$prov_agg_value" == "unverifiable" ]]; then
    overall_pre="fail"
  else
    overall_pre="pass"
  fi

  # P040 Component D: emit coverage_mode + skipped_dimensions so the aggregator
  # can distinguish streamlined runs (which legitimately skip per-step CP2 and
  # CP4 curator validation) from full runs that are missing that evidence.
  local streamlined mode_value skipped_dims
  streamlined=$(yq -r '.streamlined_mode // false' "$state_file" 2>/dev/null || echo "false")
  if [[ "$streamlined" == "true" ]]; then
    mode_value="streamlined"
    skipped_dims='["verifier_outputs.cp2_per_step","verifier_outputs.cp4_curator_validation"]'
  else
    mode_value="full"
    skipped_dims='[]'
  fi

  jq -nc \
    --arg epic "$epic_id" --arg run "$run_id" --arg ver "v3" \
    --arg era "$deploy_era" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson chks "$checks" \
    --argjson fc "$force_count" \
    --argjson fr "$force_reasons" \
    --argjson fls "$failures_json" \
    --arg     ovr "$overall_pre" \
    --argjson nts "$notes_json" \
    --arg     mode "$mode_value" \
    --argjson skipped "$skipped_dims" \
    '{
      epic_id: $epic, run_id: $run, aid_version: $ver,
      deploy_era: $era, evaluated_at: $ts,
      coverage_mode: $mode,
      skipped_dimensions: $skipped,
      checks: $chks,
      failures: $fls,
      force_override_count: $fc,
      force_override_reasons: $fr,
      overall: $ovr,
      notes: $nts
    }' > "$compliance_file" || {
    log_warn "compliance.json write failed for ${compliance_file} — skipping (telemetry is best-effort)"
    return 0
  }

  # Read back overall for the timeline event (avoid duplicate jq computation)
  local overall
  overall=$(jq -r '.overall' "$compliance_file" 2>/dev/null || echo "unknown")

  local checks_passed checks_failed
  checks_passed=$(echo "$checks" | jq '[.branch_correct, .execution_yaml_present, .gates_generated_by, .plan_ac_match, (.verifier_outputs | if type == "object" then .aggregate else . end)] | [.[] | select(. == true)] | length')
  checks_failed=$(echo "$checks" | jq '[.branch_correct, .execution_yaml_present, .gates_generated_by, .plan_ac_match, (.verifier_outputs | if type == "object" then .aggregate else . end)] | [.[] | select(. == false)] | length')

  log_event "$_timeline" "compliance_written" \
    deploy_era="$deploy_era" overall="$overall" \
    checks_passed="$checks_passed" checks_failed="$checks_failed"
}

# ─── Precondition Checks ───────────────────────────────────────────────
# Called inside cmd_transition() AFTER whitelist check, BEFORE state update.
# Returns 0 if preconditions met, 1 with error message if not.

check_preconditions() {
  local from="$1" to="$2" state_file="$3"
  local run_dir epic_id run_id
  run_dir="$(dirname "$state_file")"
  epic_id=$(yaml_field "$state_file" epic_id)
  run_id=$(yaml_field "$state_file" run_id)
  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

  case "${from}:${to}" in
    READY:EXECUTE)
      # PRE-FLIGHT must have run: plan.json exists + total_steps >= 1
      local plan_json="${run_dir}/plan.json"
      [[ -f "$plan_json" ]] || {
        echo "PRECONDITION FAIL: plan.json not found at ${plan_json}. Run PRE-FLIGHT first." >&2
        return 1
      }
      local total
      total=$(yaml_field "$state_file" total_steps)
      [[ "$total" -ge 1 ]] || {
        echo "PRECONDITION FAIL: total_steps=${total}, must be >= 1." >&2
        return 1
      }
      ;;

    EXECUTE:EXECUTE)
      # More steps must remain
      local current total
      current=$(yaml_field "$state_file" current_step)
      total=$(yaml_field "$state_file" total_steps)
      [[ "$current" -lt "$total" ]] || {
        echo "PRECONDITION FAIL: current_step=${current} == total_steps=${total}. All steps done — use EXECUTE→GATES." >&2
        return 1
      }
      ;;

    EXECUTE:GATES)
      # All steps must be completed
      local current total
      current=$(yaml_field "$state_file" current_step)
      total=$(yaml_field "$state_file" total_steps)
      [[ "$current" -ge "$total" ]] || {
        _PRECONDITION_FAIL_REASON="steps_incomplete"
        echo "PRECONDITION FAIL: current_step=${current} < total_steps=${total}. Not all steps completed." >&2
        return 1
      }

      # P032 Step 3: enforce that gates_report.json was produced by aid-run-gates.sh.
      # Hand-written reports lack `_generated_by` and are rejected — closes AID-005
      # (99% of pre-Session-A reports were hand-written with no proof of execution).
      # Pre-deploy EPICs (fsm-state.yaml.created_at < AID_DEPLOY_DATE) skip this check
      # via fsm_check_grandfather().
      if ! fsm_check_grandfather; then
        local gates_report="${evidence_dir}/gates/gates_report.json"
        if [[ ! -f "$gates_report" ]] || ! jq -e '._generated_by' "$gates_report" >/dev/null 2>&1; then
          _PRECONDITION_FAIL_REASON="gates_no_generated_by"
          local attempt_count
          attempt_count=$(fsm_count_recent_fails "$from" "$to" "gates_no_generated_by")
          if (( attempt_count >= 3 )); then
            local timeline="${evidence_dir}/timeline.jsonl"
            log_event "$timeline" "fsm_precondition_repeated_fail" \
              from="$from" to="$to" reason="gates_no_generated_by" attempt_count="$attempt_count"
            try_telegram_alert "Repeated precondition fail (×${attempt_count}): EPIC=${epic_id}, transition=${from}→${to}, reason=gates_no_generated_by"
          fi
          cat <<EOF >&2
PRECONDITION FAIL: gates_report.json missing _generated_by field.

Reason: AID v3 requires gates to be executed by aid-run-gates.sh, not
        hand-written. The _generated_by/_generated_at/_command_log fields
        produced by the runner are forensic evidence the gates actually ran.

Recommended fix (v2.18.3+): use the atomic advance-to-gates command which runs
gates and commits the transition in a single step:

  rm ${gates_report}
  bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates ${state_file}

Manual two-step alternative (debugging / crash recovery):

  rm ${gates_report}
  bash \$AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all \\
    \$AID_PROJECT_ROOT/.aid-o/config/execution.yaml ${epic_id} ${run_id} \\
    --state-file ${state_file} \\
    --report-file ${gates_report} \\
    --plan-json \$AID_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}/plan.json
  bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh transition EXECUTE GATES ${state_file}
EOF
          return 1
        fi

        # P060 Step 2: reconciliation-marker enforcement (OBS-20260702-05).
        # If plan.json exists, the gates_report MUST carry plan_gates_reconciled:true
        # — proof the runner reconciled plan.json.gates[] against execution.yaml.
        # A report produced by bypassing --plan-json (manual run-all without it
        # while plan.json exists) lacks the marker → precondition fail. Skipped
        # when plan.json is absent (nothing to reconcile). Inside the grandfather
        # guard so pre-deploy EPICs are exempt.
        if [[ -f "${evidence_dir}/plan.json" ]]; then
          if [[ ! -f "$gates_report" ]] || ! jq -e '.plan_gates_reconciled == true' "$gates_report" >/dev/null 2>&1; then
            _PRECONDITION_FAIL_REASON="gates_not_reconciled"
            cat <<EOF >&2
PRECONDITION FAIL: gates_report.json missing plan_gates_reconciled marker.

Reason: plan.json exists, so the gates MUST be reconciled against execution.yaml.
        A gate declared in plan.json.gates[] but undefined in execution.yaml
        would otherwise silently never run and still report pass
        (OBS-20260702-05). The plan_gates_reconciled:true marker proves the
        runner ran with --plan-json.

Recommended fix: re-run via the atomic command (passes --plan-json for you):

  bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates ${state_file}

Manual two-step alternative — run-all WITH --plan-json:

  rm ${gates_report}
  bash \$AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all \\
    \$AID_PROJECT_ROOT/.aid-o/config/execution.yaml ${epic_id} ${run_id} \\
    --state-file ${state_file} \\
    --report-file ${gates_report} \\
    --plan-json \$AID_PROJECT_ROOT/.aid-o/work/evidence/${epic_id}/${run_id}/plan.json
  bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh transition EXECUTE GATES ${state_file}
EOF
            return 1
          fi
        fi

        # Session B CP3: verifier-output-cp3 preconditions (file presence + valid _generated_by)
        local cp3_code_review="${evidence_dir}/verifier-output-cp3-code-review.md"
        local cp3_security="${evidence_dir}/verifier-output-cp3-security.md"

        if ! fsm_check_verifier_output "$cp3_code_review"; then
          _PRECONDITION_FAIL_REASON="missing_cp3_code_review"
          cat <<EOF >&2
PRECONDITION FAIL: verifier-output-cp3-code-review.md missing or invalid.

Reason: AID v3 Session B requires CP3 integration review before EXECUTE→GATES.
        Both verifiers (code-review + security) must review the full EPIC diff.

Fix: Dispatch TWO verifiers in parallel (single message, two Agent tool calls):
     a. subagent_type: aid-orchestrator:verifier, focus: code-review
     b. subagent_type: aid-orchestrator:verifier, focus: security
     Each writes its verifier-output-cp3-{focus}.md with _generated_by + verdict.
Then retry: aid-fsm.sh transition EXECUTE GATES ${state_file}
EOF
          return 1
        fi

        if ! fsm_check_verifier_output "$cp3_security"; then
          _PRECONDITION_FAIL_REASON="missing_cp3_security"
          cat <<EOF >&2
PRECONDITION FAIL: verifier-output-cp3-security.md missing or invalid.

Reason: CP3 requires BOTH code-review AND security verifier outputs.
        Security verifier must also be dispatched (mandatory).
Fix: dispatch security verifier (see code-review error above for full instructions).
EOF
          return 1
        fi
      fi
      ;;

    GATES:DONE)
      # gates_report.json must exist with overall: pass
      local report="${evidence_dir}/gates/gates_report.json"
      [[ -f "$report" ]] || {
        echo "PRECONDITION FAIL: gates_report.json not found at ${report}. Run gates first." >&2
        return 1
      }
      if command -v jq &>/dev/null; then
        local overall
        overall=$(jq -r '.overall' "$report" 2>/dev/null)
        [[ "$overall" == "pass" ]] || {
          echo "PRECONDITION FAIL: gates overall=${overall}, must be 'pass' for DONE transition." >&2
          return 1
        }

        # P061 E1 Step 3: plan-gate floor (plan_gate_profile_excluded). ─────────
        # plan.json.gates[] (Step 1) is a hard floor: the active gate profile
        # (Step 2, aid-run-gates.sh --profile) must never silently exclude a
        # gate the PLAN itself declared mandatory. A profile-excluded gate
        # does NOT flip gates_report.json.overall to fail (Step 2, by design —
        # same treatment as a skipped required:false gate), so without this
        # check a plan-required gate could vanish from a run that still
        # reports overall=pass. Cross-reference plan.json.gates[] against
        # gates_report.json.excluded_gates[] (both already read via the same
        # --plan-json / gates_report.json wiring used by the EXECUTE:GATES
        # reconciliation above) and fail loud on any overlap — design (b)
        # fail-loud, chosen over force-running the gate here because aid-fsm.sh
        # is a precondition checker, not a gate executor (that's
        # aid-run-gates.sh's job); re-running gate logic here would duplicate
        # it. Never a silent skip (AID-v3-principles.md §1).
        # E-061-1_6 CP3 security: .gates must be validated as an array (not
        # an object or other type) before iteration. A type-confused shape
        # (e.g. object instead of array) silently produces [] even when a
        # plan-required gate is excluded — fail closed via the existing
        # plan_json_malformed path when .gates is not an array.
        local plan_json_file="${evidence_dir}/plan.json"
        if [[ -f "$plan_json_file" ]]; then
          local plan_gate_floor_violations
          plan_gate_floor_violations=$(jq -n \
            --slurpfile plan "$plan_json_file" \
            --slurpfile rpt "$report" \
            '(($plan[0].gates // []) as $pg_raw
              | ($pg_raw | if type == "array" then . else error("plan.json.gates must be an array, got \(type)") end) as $pg
              | ($rpt[0].excluded_gates // []) as $eg
              | [$pg[] | select(. as $g | $eg | index($g) != null)])' 2>&1)
          if [[ $? -ne 0 ]]; then
            _PRECONDITION_FAIL_REASON="plan_json_malformed"
            echo "PRECONDITION FAIL: plan_json_malformed — plan.json exists but is not valid JSON." >&2
            echo "Error: $plan_gate_floor_violations" >&2
            return 1
          fi

          if jq -e 'length > 0' <<< "$plan_gate_floor_violations" >/dev/null 2>&1; then
            _PRECONDITION_FAIL_REASON="plan_gate_profile_excluded"
            local violations_csv
            violations_csv=$(jq -r 'join(", ")' <<< "$plan_gate_floor_violations" 2>/dev/null)
            cat <<EOF >&2
PRECONDITION FAIL: plan_gate_profile_excluded — plan-required gate(s) excluded by active profile: ${violations_csv}.

Reason: plan.json.gates[] is a hard floor (P061 E1) — a gate the PLAN itself
        declared mandatory must never be silently skipped just because the
        active gate profile (--profile) excludes it. gates_report.json
        recorded these gate(s) under excluded_gates[], which would otherwise
        let the run report overall=pass while a plan-required gate never ran.

Fix: widen the active profile's include[] in execution.yaml.gate_profiles to
     cover: ${violations_csv}
     then re-run gates:
       bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates ${state_file}

OR (PM-authorized override, audited):
  aid-fsm.sh transition GATES DONE ${state_file} --force --reason \\
      '<≥20 chars why excluding a plan-required gate is acceptable>'
EOF
            return 1
          fi
        fi
      else
        # Fail loud, never silent-pass: without jq we cannot verify overall==pass,
        # and a missing verifier must block the DONE transition (OBS-20260708-07).
        echo "PRECONDITION FAIL: jq required to verify gates overall but not found." >&2
        return 1
      fi

      # P060 Step 4: CP3 review freshness (OBS-20260702-03). The probe lives HERE
      # (GATES:DONE) — a stale CP3 review (HEAD moved past its Reviewed-Head) must
      # not pass as DONE evidence unless the D4 narrow exception holds. Grandfather
      # + policy handled inside; default BLOCKING (D9).
      if ! fsm_check_cp3_freshness "$evidence_dir" "$state_file" "$PWD"; then
        _PRECONDITION_FAIL_REASON="${_PRECONDITION_FAIL_REASON:-cp3_stale_review}"
        return 1
      fi
      ;;

    ESCALATION:EXECUTE|ESCALATION:GATES)
      # PM must have recorded a decision
      local decision
      decision=$(yaml_field "$state_file" escalation_decision)
      [[ -n "$decision" ]] || {
        echo "PRECONDITION FAIL: escalation_decision not set in fsm-state.yaml. PM must decide first." >&2
        return 1
      }
      ;;

    # Failure/retry paths — always allowed
    EXECUTE:ESCALATION|GATES:ESCALATION|GATES:EXECUTE) : ;;

    # ERROR transitions — always allowed
    *:ERROR) : ;;
  esac
  return 0
}

# ─── Commands ───────────────────────────────────────────────────────────

cmd_init() {
  local epic_id="$1" run_id="$2" total_steps="$3" mode="$4"
  local branch="$5" base_commit="$6" state_file="$7"

  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

  # Phase 2 (P037) — parse optional named flags after 7 positional args.
  # Detect --plan <path> and --force in either order ($8/$9). Both are optional.
  local plan_path_arg=""
  local force="false"
  local streamlined=false
  local i=8
  while [[ $i -le $# ]]; do
    case "${!i}" in
      --plan)
        i=$((i + 1))
        plan_path_arg="${!i:-}"
        ;;
      --plan=*)
        plan_path_arg="${!i#--plan=}"
        ;;
      --streamlined)
        streamlined=true
        ;;
      --force)
        # Pre-scan: find which prior plan's gate would have been blocking,
        # so the audit record names it (E-046-2_3 Step 3 enrichment).
        local _bepic="" _bplan=""
        local _cur_plan_num=""
        [[ "$epic_id" =~ ^E-([0-9]+) ]] && _cur_plan_num="${BASH_REMATCH[1]}"
        local _cur_plan_prefix="P${_cur_plan_num}"
        while IFS= read -r _ps; do
          local _pe _ppn _pp _pdp _pd
          _pe=$(yaml_field "$_ps" epic_id)
          _ppn=""
          [[ "$_pe" =~ ^E-([0-9]+) ]] && _ppn="${BASH_REMATCH[1]}"
          _pp="P${_ppn}"
          _pdp=$(yaml_field "$_ps" done_phase)
          _pd=$(dirname "$_ps")
          if [[ -n "$_pp" && "$_pp" != "$_cur_plan_prefix" && "$_pdp" == "review" ]]; then
            if [[ -f "${_pd}/audit-report.md" && ! -f "${_pd}/ca-review-complete" ]]; then
              _bepic="$_pe"; _bplan="$_pp"; break
            fi
          fi
        done < <(find .aid-o/work/evidence -name "fsm-state.yaml" 2>/dev/null)
        # Forwards ${@:i+1}; callers must pass --plan before --force when both present
        # (fsm_handle_force_override consumes remaining args as reason payload).
        fsm_handle_force_override "plan-gate" "skip" "$state_file" "init" "${@:$((i+1))}" \
          ${_bepic:+--blocking-epic "$_bepic"} ${_bplan:+--blocking-plan "$_bplan"}
        force="true"
        ;;
      *)
        # Unknown flag at this position — preserved as before; existing callers don't
        # pass anything past $8 unless it's --force, so safe to ignore here.
        ;;
    esac
    i=$((i + 1))
  done

  # P032 Step 9 (deps doc layer extension): preflight guard for jq + git.
  # cmd_init writes JSON timeline events (jq) and runs PRE-FLIGHT branch
  # enforcement (git). Without these, downstream calls fail with cryptic
  # messages; fail fast with concrete install hint.
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git not installed. Install: apt install git / brew install git" >&2
    echo "Run: bash \$AID_PLUGIN_PATH/scripts/aid-check-deps.sh  for full dependency report." >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not installed. Install: apt install jq / brew install jq" >&2
    echo "Run: bash \$AID_PLUGIN_PATH/scripts/aid-check-deps.sh  for full dependency report." >&2
    exit 1
  fi

  if [[ -f "$state_file" ]]; then
    echo "ERROR: state_file already exists: $state_file (prevent duplicate init)" >&2
    exit 1
  fi

  # Plan-level DONE gate: block cross-plan init if previous plan has unreviewed C+A findings
  if [[ "$force" != "true" && -d ".aid-o/work/evidence" ]]; then
    local current_plan_num current_plan_prefix
    current_plan_num=""
    [[ "$epic_id" =~ ^E-([0-9]+) ]] && current_plan_num="${BASH_REMATCH[1]}"
    current_plan_prefix=""
    [[ -n "$current_plan_num" ]] && current_plan_prefix="P${current_plan_num}"

    if [[ -n "$current_plan_prefix" ]]; then
      while IFS= read -r prev_state; do
        local prev_epic prev_plan prev_done_phase prev_dir prev_plan_num
        prev_epic=$(yaml_field "$prev_state" epic_id)
        prev_plan_num=""
        [[ "$prev_epic" =~ ^E-([0-9]+) ]] && prev_plan_num="${BASH_REMATCH[1]}"
        prev_plan=""
        [[ -n "$prev_plan_num" ]] && prev_plan="P${prev_plan_num}"
        prev_done_phase=$(yaml_field "$prev_state" done_phase)
        prev_dir=$(dirname "$prev_state")

        # Only check EPICs from DIFFERENT completed plans
        if [[ -n "$prev_plan" && "$prev_plan" != "$current_plan_prefix" && "$prev_done_phase" == "review" ]]; then
          if [[ -f "${prev_dir}/audit-report.md" && ! -f "${prev_dir}/ca-review-complete" ]]; then
            echo "PRECONDITION FAIL: Plan $prev_plan has unreviewed Curator/Auditor findings." >&2
            echo "EPIC $prev_epic: audit-report exists but ca-review-complete marker missing." >&2
            echo "Review findings, apply S+M+L fixes, then run:" >&2
            echo "  aid-fsm.sh plan-close ${prev_epic} ${prev_dir} <project_root>" >&2
            echo "(Do NOT use touch — plan-close verifies all required reports are present.)" >&2
            local timeline
            timeline=$(derive_timeline "$state_file") || true
            [[ -n "$timeline" ]] && log_event "$timeline" "fsm_init_blocked" reason="unreviewed_ca" blocking_epic="$prev_epic" blocking_plan="$prev_plan"
            exit 1
          fi
        fi
      done < <(find .aid-o/work/evidence -name "fsm-state.yaml" 2>/dev/null)
    fi
  fi

  if [[ "$force" == "true" ]]; then
    echo "WARNING: --force used, skipping plan-level DONE gate check" >&2
  fi

  # ─── PRE-FLIGHT: Branch Enforcement (P032 Step 2) ────────────────────
  # Closes AID-001 (65% of pre-Session-A state.yaml claimed branch=main with
  # no actual task branch, breaking done-advance git merge audit trail).
  #
  # Five HEAD states handled:
  #   worktree    → skip enforcement (caller controls branch)
  #   resume      → HEAD == task/E-{epic_id}/main → log_info, accept
  #   fresh init  → HEAD ∈ {main, master, develop} → auto-checkout
  #   mismatch    → HEAD == task/<other_epic>/main → emit event, hard fail
  #   unusual     → anything else (feat/*, detached, ...) → warn, accept
  #
  # Timeline events for forensic visibility:
  #   fsm_branch_mismatch_detected (hard fail case)
  #   fsm_branch_unusual_detected  (warn case)
  local timeline_path=".aid-o/work/evidence/${epic_id}/${run_id}/timeline.jsonl"
  mkdir -p "$(dirname "$timeline_path")"

  # ─── PRE-FLIGHT: Plugin-cache staleness guard — HARD STOP (P060 Step 5) ──
  # anchor: cache_preflight_init_hardstop
  # Runs BEFORE any git mutation OR the fsm-state.yaml write below. On dogfood
  # skew this aborts here so fsm-state.yaml is never created (scenario f). The
  # state file does not exist yet, so consumer recording is deferred to the
  # post-write call (anchor: cache_preflight_init_record). Covers plugin.json
  # version + scripts/ tree ONLY — see aid-cache-preflight.sh honesty header.
  if ! run_cache_preflight "$state_file" "$timeline_path"; then
    exit 1
  fi

  if is_worktree; then
    log_info "Worktree mode detected (git_dir under .git/worktrees/) — skipping branch enforcement"
  else
    local current_branch expected_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || die "Not in a git repository"
    expected_branch="task/${epic_id}/main"

    case "$current_branch" in
      "$expected_branch")
        log_info "Resume case: HEAD already on $expected_branch"
        ;;
      main|master|develop)
        # P040 Component E: if the EPIC's task branch already exists (e.g. a
        # prior aid-json-to-run.sh generation pass created it, or a re-init of
        # the same EPIC), resume onto it instead of failing on `checkout -b`.
        if git show-ref --verify --quiet "refs/heads/${expected_branch}"; then
          log_info "Resume case: checking out existing $expected_branch"
          git checkout "$expected_branch" >/dev/null 2>&1 \
            || die "Failed to checkout existing branch $expected_branch (check 'git status' for details)"
        else
          log_info "Auto-creating branch: $expected_branch"
          git checkout -b "$expected_branch" >/dev/null 2>&1 \
            || die "Failed to create branch $expected_branch (check 'git status' for details)"
        fi
        ;;
      task/E-*)
        # Different EPIC's task branch — stale workspace from prior session.
        log_event "$timeline_path" "fsm_branch_mismatch_detected" \
          current_branch="$current_branch" expected_branch="$expected_branch" epic_id="$epic_id"
        die "ERROR: Currently on $current_branch, expected $expected_branch.

Reason: AID v3 requires one task branch per EPIC for clean audit trail.
        Different-EPIC branches indicate stale workspace from prior session.

Fix: git checkout main && git branch -d $current_branch
Then retry: aid-fsm.sh init ${epic_id} ..."
        ;;
      *)
        # feat/*, refactor/*, detached HEAD, any non-task pattern.
        # PM context-aware (e.g., manual exploration on feat/ branch) — accept with warning.
        log_event "$timeline_path" "fsm_branch_unusual_detected" \
          current_branch="$current_branch" expected_branch="$expected_branch" epic_id="$epic_id"
        log_warn "Unusual branch: $current_branch (expected $expected_branch). Continuing — PM-controlled context assumed."
        ;;
    esac
  fi

  # Uncommitted changes guard (always runs, even in worktree mode).
  # PRE-FLIGHT must start from clean tree so done-advance merge has a clear
  # diff to attribute to the EPIC.
  #
  # AID's own runtime queue file (.aid-o/config/queue.yaml) is excluded: the
  # auto-pipeline mutates it between phases, and in projects initialized before
  # it was gitignored (v2.1.1) it may be tracked, which would otherwise trip
  # this guard on every multi-phase run. The `^.. ` anchor matches only the
  # two porcelain status columns + space, so it never hides a real file renamed
  # into a queue.yaml name (rename lines contain " -> "). --untracked-files=no
  # preserves the original behaviour of ignoring untracked files; no pathspec is
  # given so the whole repo is scanned regardless of cwd, matching the original
  # `git diff` semantics.
  local _dirty
  _dirty="$(git status --porcelain --untracked-files=no \
    | grep -vE '^.. \.aid-o/config/queue\.yaml$' || true)"
  if [[ -n "$_dirty" ]]; then
    die "Uncommitted changes present. Commit or stash before init:
       git status   # review
       git stash    # or commit"
  fi

  # C3 (PM-authorized): override caller's branch param ($5) with actual git
  # state. Caller convention is to pass 'main' as a placeholder; what matters
  # downstream is the branch we actually ended up on (after auto-checkout or
  # in worktree mode). fsm-state.yaml.branch reflects post-enforcement reality.
  local actual_branch
  actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$branch")
  branch="$actual_branch"

  # Auto-recover execution.yaml if missing (P032 Step 1).
  # Empty-stacks fallback is harmless and idempotent — pre-deploy projects keep
  # their custom config (the [[ ! -f ... ]] guard ensures we never overwrite).
  if [[ ! -f .aid-o/config/execution.yaml ]] && [[ -f "${SCRIPT_DIR}/lib/aid-init-execution-yaml.sh" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/lib/aid-init-execution-yaml.sh"
    local -a _aid_stacks=()
    mapfile -t _aid_stacks < <(detect_stacks "$PWD")
    if compose_execution_yaml "$PWD" ".aid-o/config/execution.yaml" "${_aid_stacks[@]}"; then
      log_info "Lazy-created .aid-o/config/execution.yaml with stacks: ${_aid_stacks[*]:-none}"
    fi
  fi

  mkdir -p "$(dirname "$state_file")"
  local _now_iso
  _now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$state_file" << EOF
epic_id: $epic_id
run_id: $run_id
state: READY
current_step: 0
total_steps: $total_steps
mode: $mode
branch: $branch
base_commit: $base_commit
gate_retries: 0
escalation_count: 0
streamlined_mode: $streamlined
started_at: "${_now_iso}"
created_at: ${_now_iso}
EOF

  # ─── PRE-FLIGHT: cache staleness — consumer controller recording ─────────
  # anchor: cache_preflight_init_record
  # State file now exists. On a consumer's first preflight of this run this
  # appends controller_version + controller_hash (scenario c). Dogfood-match
  # runs already passed the hard-stop above and record nothing here. Appended
  # here (before the steps[] block below) so scalar fields stay grouped and the
  # steps[] sequence remains the trailing YAML node. Never blocks init.
  run_cache_preflight "$state_file" "$timeline_path" || true

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  if [[ -n "$timeline" ]]; then
    mkdir -p "$(dirname "$timeline")"
    log_event "$timeline" "fsm_init" epic_id="$epic_id" run_id="$run_id" total_steps="$total_steps" mode="$mode"
  fi

  # ─── Queue dependency revalidation (P060 Step 7, NEW read path) ──────────
  # OBS-20260709-06: revalidate this EPIC's queue depends_on against LIVE git so
  # a stale "awaiting merge" flag can never hold a dependent EPIC blocked after
  # its dep merged (branch deleted = the norm). This is the FIRST time aid-fsm.sh
  # reads the queue; it is deliberately NON-FATAL to init — a blocked/unresolved
  # dep is a queue-scheduling signal for the consumer (pipeline §12 / /aid-run
  # pre-start), not an init failure. Missing queue / no entry / no deps = no-op.
  if [[ -f .aid-o/config/queue.yaml ]]; then
    queue_revalidate "$epic_id" ".aid-o/config/queue.yaml" "$timeline_path" >/dev/null 2>&1 || true
  fi

  # Validate plan.json step content (warning only)
  local evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  local plan_json="${evidence_dir}/plan.json"
  if [[ -f "$plan_json" ]] && command -v python3 &>/dev/null; then
    local empty_steps
    empty_steps=$(python3 -c "
import json, sys
try:
    d = json.load(open('$plan_json'))
    steps = d.get('steps', [])
    empty = [s.get('id','?') for s in steps if 'objective' not in s or not s.get('objective')]
    if empty: print(','.join(str(e) for e in empty))
except: pass
" 2>/dev/null || true)
    if [[ -n "$empty_steps" ]]; then
      echo "WARNING: plan.json has steps without 'objective': $empty_steps" >&2
    fi
  fi

  # Session B: stamp plan.json sha256 for mid-EPIC tampering detection.
  # Additive key — existing readers tolerate unknown keys via grep-awk pattern.
  if [[ -f "${evidence_dir}/plan.json" ]]; then
    local plan_hash
    plan_hash=$(sha256sum "${evidence_dir}/plan.json" | awk '{print $1}')
    echo "plan_json_hash: $plan_hash" >> "$state_file"
  fi

  # Phase 2 (P037) — write plan_path field with realpath-normalized absolute path or null.
  # Gate command runs via bash -c from unknown cwd; we need absolute paths so
  # aid-plan-diff.sh receives a usable --plan argument. "null" = Fast Mode (no plan).
  local plan_path_value="null"
  if [[ -n "$plan_path_arg" ]]; then
    plan_path_value=$(realpath "$plan_path_arg" 2>/dev/null || echo "$plan_path_arg")
  fi
  echo "plan_path: $plan_path_value" >> "$state_file"

  # P040 Component E: absorb legacy state.yaml steps[] array into fsm-state.yaml
  # (single source of truth — eliminates state.yaml vs fsm-state.yaml drift, NR 10/12/14).
  # Appended AFTER the scalar heredoc + plan_json_hash/plan_path line-anchored
  # appends so it never interferes with grep '^field:' readers. The nested
  # steps: array is yq-parseable while the scalar fields above remain unquoted.
  {
    echo "steps:"
    local _s
    for (( _s=1; _s<=total_steps; _s++ )); do
      echo "  - id: ${_s}"
      echo "    name: \"\""
      echo "    status: pending"
      echo "    started_at: null"
      echo "    completed_at: null"
    done
  } >> "$state_file"

  echo "Initialized state: READY" >&2
}

# read_steps_array — P040 Component E backward-compat reader. Prefers the
# steps[] array in fsm-state.yaml (single source of truth); falls back to a
# sibling legacy state.yaml for runs created before unification. Emits JSON.
read_steps_array() {
  local state_file="$1"
  local evidence_dir; evidence_dir=$(dirname "$state_file")
  local legacy="${evidence_dir}/state.yaml"
  if yq -e '.steps' "$state_file" >/dev/null 2>&1; then
    yq -o=json '.steps' "$state_file"
  elif [[ -f "$legacy" ]] && yq -e '.steps' "$legacy" >/dev/null 2>&1; then
    yq -o=json '.steps' "$legacy"
  else
    echo "[]"
  fi
}

cmd_transition() {
  local from="$1" to="$2" state_file="$3"
  local force="false"
  if [[ "${4:-}" == "--force" ]]; then
    local epic_id run_id evidence_dir
    epic_id=$(yaml_field "$state_file" epic_id)
    run_id=$(yaml_field "$state_file" run_id)
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    fsm_handle_force_override "$from" "$to" "$state_file" "transition" "${@:5}"
    force="true"
  fi

  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found: $state_file" >&2; exit 1; }

  local current_state
  current_state=$(yaml_field "$state_file" state)

  if [[ "$current_state" != "$from" ]]; then
    echo "ERROR: expected state $from but found $current_state" >&2
    exit 1
  fi

  if ! is_valid_state "$to"; then
    echo "ERROR: invalid target state: $to" >&2
    exit 1
  fi

  if ! is_valid_transition "$from" "$to"; then
    echo "ERROR: invalid transition $from → $to" >&2
    exit 1
  fi

  # Precondition checks (skip with --force)
  if [[ "$force" == "true" ]]; then
    echo "WARNING: --force used, skipping precondition checks for $from → $to" >&2
  else
    # P032 Step 3: check_preconditions sets _PRECONDITION_FAIL_REASON before
    # returning 1; we surface it in the timeline event so fsm_count_recent_fails
    # can group repeated failures by reason.
    _PRECONDITION_FAIL_REASON=""
    if ! check_preconditions "$from" "$to" "$state_file"; then
      local timeline reason
      timeline=$(derive_timeline "$state_file") || true
      reason="${_PRECONDITION_FAIL_REASON:-unspecified}"
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_fail" \
        from="$from" to="$to" reason="$reason"
      exit 1
    fi
  fi

  # Increment escalation_count when entering ESCALATION
  if [[ "$to" == "ESCALATION" ]]; then
    local count
    count=$(yaml_field "$state_file" escalation_count)
    sed -i "s/^escalation_count: .*/escalation_count: $((count + 1))/" "$state_file"
  fi

  # Clear escalation_decision when leaving ESCALATION
  if [[ "$from" == "ESCALATION" ]]; then
    sed -i '/^escalation_decision:/d' "$state_file"
  fi

  # Auto-set done_phase when entering DONE
  if [[ "$to" == "DONE" ]]; then
    # Remove any stale done_phase, then set to review
    sed -i '/^done_phase:/d' "$state_file"
    echo "done_phase: review" >> "$state_file"
  fi

  # Update state (atomic via temp file + mv)
  local tmp_file="${state_file}.tmp"
  sed "s/^state: .*/state: $to/" "$state_file" > "$tmp_file"
  mv "$tmp_file" "$state_file"

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_transition" from="$from" to="$to"

  echo "Transition: $from → $to" >&2
}

# Atomic gates run + EXECUTE→GATES transition (P035 Phase 1, v2.18.3).
# Eliminates the chicken-egg precondition fail mode (gates_no_generated_by)
# observed in P020 (8×) and P021 (4×). Routes through cmd_transition for full
# precondition validation — single source of truth remains check_preconditions.
# Atomicity: state changes only on full success path; gates failure leaves
# state at EXECUTE (never modified).
cmd_advance_to_gates() {
  local state_file="${1:?state_file required}"
  [[ ! -f "$state_file" ]] && { echo "ERROR: state file not found: $state_file" >&2; exit 1; }

  local epic_id run_id current_state current_step total_steps evidence_dir timeline
  epic_id=$(yaml_field "$state_file" epic_id)
  run_id=$(yaml_field "$state_file" run_id)
  current_state=$(yaml_field "$state_file" state)
  current_step=$(yaml_field "$state_file" current_step)
  total_steps=$(yaml_field "$state_file" total_steps)
  evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  timeline=$(derive_timeline "$state_file") || true

  # Validate numeric step fields (defensive — malformed fsm-state.yaml caught early).
  if [[ ! "$current_step" =~ ^[0-9]+$ ]] || [[ ! "$total_steps" =~ ^[0-9]+$ ]]; then
    echo "ERROR: malformed fsm-state.yaml — current_step=$current_step total_steps=$total_steps must be integers" >&2
    exit 1
  fi

  # Cheap pre-flight guards (avoid invoking runner if obvious mismatch).
  if [[ "$current_state" != "EXECUTE" ]]; then
    echo "ERROR: advance-to-gates requires state==EXECUTE, found: $current_state" >&2
    exit 1
  fi
  if (( current_step < total_steps )); then
    echo "ERROR: advance-to-gates requires current_step ($current_step) >= total_steps ($total_steps). Not all steps completed." >&2
    exit 1
  fi

  # Resolve execution.yaml + report path (matches /aid-run gate dispatch convention).
  local execution_yaml="${AID_PROJECT_ROOT:-$(pwd)}/.aid-o/config/execution.yaml"
  if [[ ! -f "$execution_yaml" ]]; then
    echo "ERROR: execution.yaml not found at $execution_yaml. Set AID_PROJECT_ROOT or cd to project root." >&2
    exit 1
  fi
  local report_file="${evidence_dir}/gates/gates_report.json"

  # Emit pre-gates audit event (gate runner is about to start).
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_pre_gates" \
    epic_id="$epic_id" run_id="$run_id" \
    execution_yaml="$execution_yaml" report_file="$report_file"

  # P060 Step 2: pass plan.json so the runner reconciles plan.json.gates[]
  # against execution.yaml (undefined_gate detection, OBS-20260702-05). If
  # plan.json is absent, log plan_gates_reconciliation_skipped and invoke
  # WITHOUT --plan-json (behavior unchanged — F4c).
  local plan_json_arg=()
  if [[ -f "${evidence_dir}/plan.json" ]]; then
    plan_json_arg=(--plan-json "${evidence_dir}/plan.json")
  else
    [[ -n "$timeline" ]] && log_event "$timeline" "plan_gates_reconciliation_skipped" \
      epic_id="$epic_id" run_id="$run_id" reason="plan_json_absent"
  fi

  # Invoke runner with explicit FSM signal — Step 2 makes runner accept this.
  local rc=0
  AID_GATES_TRIGGERED_BY_FSM=1 \
    "${SCRIPT_DIR}/aid-run-gates.sh" run-all \
      "$execution_yaml" "$epic_id" "$run_id" \
      --state-file "$state_file" \
      --report-file "$report_file" \
      "${plan_json_arg[@]}" \
    || rc=$?

  if (( rc == 0 )); then
    # Gates passed — route through cmd_transition for full precondition validation.
    # check_preconditions re-validates _generated_by, CP3 outputs, grandfather logic.
    # The runner just wrote gates_report.json with _generated_by, so the check passes.
    if cmd_transition EXECUTE GATES "$state_file"; then
      # D0 gate point — observe-mode delivery gate (E2, E-050).
      # Runs after last EXECUTE step and successful EXECUTE→GATES transition.
      # Non-blocking: never fails the transition regardless of exit code or findings.
      local _d0_script="${SCRIPT_DIR}/aid-delivery-gate.sh"
      local _d0_policy="${SCRIPT_DIR}/../defaults/policies/delivery-gate.yaml"
      if [[ -f "$_d0_script" ]]; then
        local _d0_base_sha _d0_output _d0_exit=0
        _d0_base_sha=$(yaml_field "$state_file" base_commit)
        local _d0_project_root="${AID_PROJECT_ROOT:-$(pwd)}"
        _d0_output=$(
          DELIVERY_GATE_POLICY="$_d0_policy" \
          AID_EVIDENCE_BASE="${_d0_project_root}/.aid-o/work/evidence" \
          AID_PROJECT_ROOT="$_d0_project_root" \
          timeout 300 bash "$_d0_script" \
            --epic "$epic_id" --run "$run_id" \
            --base "${_d0_base_sha:-HEAD~1}" \
            --phase D0 2>&1
        ) || _d0_exit=$?
        [[ -n "$timeline" ]] && log_event "$timeline" "d0_delivery_gate" \
          exit_code="${_d0_exit}" \
          observe="true" \
          epic="${epic_id}" \
          run="${run_id}"
      fi
      # D0 is observe-only — never fail the transition
      echo "advance-to-gates: SUCCESS — gates passed, state=GATES"
      return 0
    else
      # Surface cmd_transition error to user; state stays EXECUTE (transition didn't commit).
      [[ -n "$timeline" ]] && log_event "$timeline" "fsm_advance_to_gates_fail" \
        reason="transition_check_failed_after_gates_pass" runner_exit="$rc"
      echo "ERROR: advance-to-gates: gates passed but cmd_transition refused — see error above" >&2
      return 1
    fi
  else
    # Gates failed — state was never modified, leave at EXECUTE.
    [[ -n "$timeline" ]] && log_event "$timeline" "fsm_advance_to_gates_fail" \
      reason="gates_runner_exit_${rc}" runner_exit="$rc"
    echo "advance-to-gates: FAIL — gates runner exit=$rc, state unchanged (EXECUTE)" >&2
    return "$rc"
  fi
}

cmd_get_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  yaml_field "$state_file" state
}

cmd_verify_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || { echo '{"error":"state_file not found"}'; exit 1; }

  # ─── PRE-FLIGHT: Plugin-cache staleness guard (P060 Step 5) ──────────────
  # anchor: cache_preflight_verify_state
  # verify-state runs on EVERY run start (pipeline.md); cmd_init does NOT re-run
  # on resume, so this covers the resume path. HARD STOP on dogfood skew; on a
  # consumer's first preflight of the run it records controller_version/hash,
  # and on a changed-controller resume it warns via controller_skew_detected
  # (non-blocking). Timeline is derived next to the state file (never stdout —
  # the JSON payload below must stay clean).
  local _cp_timeline
  _cp_timeline="$(dirname "$state_file")/timeline.jsonl"
  if ! run_cache_preflight "$state_file" "$_cp_timeline"; then
    exit 1
  fi

  local state epic_id run_id current_step total_steps
  state=$(yaml_field "$state_file" state)
  epic_id=$(yaml_field "$state_file" epic_id)
  run_id=$(yaml_field "$state_file" run_id)
  current_step=$(yaml_field "$state_file" current_step)
  total_steps=$(yaml_field "$state_file" total_steps)

  # Compute allowed transitions from current state
  local allowed=()
  for t in "${VALID_TRANSITIONS[@]}"; do
    local t_from="${t%%:*}" t_to="${t##*:}"
    [[ "$t_from" == "$state" ]] && allowed+=("\"${t_to}\"")
  done
  local allowed_json="[$(IFS=,; echo "${allowed[*]}")]"

  # Include done_phase if in DONE state
  local done_phase_json=""
  if [[ "$state" == "DONE" ]]; then
    local done_phase
    done_phase=$(yaml_field "$state_file" done_phase); done_phase=${done_phase:-unknown}
    done_phase_json=",\"done_phase\":\"${done_phase}\""
  fi

  echo "{\"state\":\"${state}\",\"epic_id\":\"${epic_id}\",\"run_id\":\"${run_id}\",\"current_step\":${current_step},\"total_steps\":${total_steps},\"allowed_transitions\":${allowed_json}${done_phase_json}}"
}

cmd_increment_step() {
  local state_file="$1"
  local force="false"
  [[ "${2:-}" == "--force" ]] && force="true"

  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }

  # P040 Component B: hoist scope vars to function-top so the reconciliation
  # backstop (and audit logging) can run UNCONDITIONALLY, regardless of --force.
  local step epic_id run_id evidence_dir project_root
  step=$(yaml_field "$state_file" current_step)
  epic_id=$(yaml_field "$state_file" epic_id)
  run_id=$(yaml_field "$state_file" run_id)
  evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
  project_root="$PWD"

  # P040 Component D: streamlined mode skips per-step CP2 verifier enforcement.
  local streamlined
  streamlined=$(yq -r '.streamlined_mode // false' "$state_file" 2>/dev/null || echo "false")

  # P040 Component B: parse --blocked-checks from caller args (positionals 3+),
  # so the orphan check can be explicitly waived by PM (--force --blocked-checks).
  local blocked_checks=""
  local _args=("${@:3}")
  local i
  for (( i=0; i<${#_args[@]}; i++ )); do
    if [[ "${_args[$i]}" == "--blocked-checks" ]]; then
      blocked_checks="${_args[$((i+1))]:-}"
      break
    fi
  done
  blocked_checks="${blocked_checks// /}"; blocked_checks="${blocked_checks#,}"; blocked_checks="${blocked_checks%,}"

  # Precondition: step verification evidence must exist + content checks.
  # Each failure goes through _increment_fail (message → timeline event → exit 1).
  if [[ "$force" != "true" ]]; then
    local verify_file="${evidence_dir}/step-${step}-verify.md"
    [[ -f "$verify_file" ]] || _increment_fail missing_step_verify \
      "PRECONDITION FAIL: Step verification evidence not found." \
      "Expected: ${verify_file}" \
      "Write verification (AC checklist + result) before advancing to next step."

    # Content checks — single file read, bash pattern matches (was 5 grep forks).
    local _verify_content
    _verify_content=$(<"$verify_file")

    [[ "$_verify_content" == *"## Result: PASS"* ]] || _increment_fail step_verify_not_pass \
      "PRECONDITION FAIL: Step verification does not contain '## Result: PASS'." \
      "File: ${verify_file}" \
      "Fix failing AC or mark '## Result: PASS' when all criteria met."

    [[ "$_verify_content" == *"- [x]"* ]] || _increment_fail verify_no_ac_checklist \
      "PRECONDITION FAIL: Step verification has no acceptance criteria checklist." \
      "File: ${verify_file}" \
      "Must contain at least one '- [x] ...' item matching plan AC."

    [[ "$_verify_content" =~ [a-f0-9]{7,} ]] || _increment_fail verify_no_commit_ref \
      "PRECONDITION FAIL: Step verification has no commit reference." \
      "File: ${verify_file}" \
      "Must contain at least one commit hash (7+ hex chars)."

    # Memory sections — line-anchored (^## ...), hence the prepended newline.
    [[ $'\n'"$_verify_content" == *$'\n'"## Memory Used"* ]] || _increment_fail verify_no_memory_used \
      "PRECONDITION FAIL: Step verification missing '## Memory Used' section." \
      "File: ${verify_file}" \
      "List memory entries used (or 'N/A — <reason>' if none applicable)."

    [[ $'\n'"$_verify_content" == *$'\n'"## Memory Written"* ]] || _increment_fail verify_no_memory_written \
      "PRECONDITION FAIL: Step verification missing '## Memory Written' section." \
      "File: ${verify_file}" \
      "List new memory entries proposed (or 'N/A — <reason>' if none applicable)."

    # Visual Anchoring precondition (E161, AID-052): a frontend step carrying visual_refs
    # MUST emit a "## Visual Anchoring" section in its output (the frontend role card
    # requires the layout/colors/typography/components spec BEFORE implementation). We read
    # the step's id/role/visual_refs from plan.json (single jq pass) and use the step's own
    # id for the output path (no index reconstruction → no off-by-one). Skips silently for
    # non-frontend steps, steps without visual_refs, or when plan.json/jq are unavailable.
    local _plan_json="${evidence_dir}/plan.json"
    if [[ -f "$_plan_json" ]] && command -v jq >/dev/null 2>&1; then
      local _srole="" _svisrefs="" _sid=""
      { read -r _srole; read -r _svisrefs; read -r _sid; } < <(
        jq -r --argjson i "$step" \
          '(.steps[$i].role // ""), ((.steps[$i].visual_refs // []) | length), (.steps[$i].id // "")' \
          "$_plan_json" 2>/dev/null
      ) || true
      if [[ "$_srole" == "frontend" && "${_svisrefs:-0}" -gt 0 ]]; then
        local _fe_output="${evidence_dir}/steps/${_sid}/output.md"
        if [[ -z "$_sid" ]] || [[ ! -f "$_fe_output" ]] || ! grep -qE '^## Visual Anchoring' "$_fe_output" 2>/dev/null; then
          _increment_fail frontend_missing_visual_anchoring \
            "PRECONDITION FAIL: frontend step has visual_refs but its output lacks a '## Visual Anchoring' section." \
            "Expected '## Visual Anchoring' in: ${_fe_output}" \
            "The frontend role card requires the Visual Anchoring spec (layout/colors/typography/components from the mockup) before implementation when visual_refs are set."
        fi
      fi
    fi

    # E7B: existing_ui EXECUTE guard (step-local, D6 — not a delivery gate)
    # Reads step.ui_change_mode from plan.json. If existing_ui: checks for
    # steps/{step_id}/ui/verdict.json with result=pass. Missing or non-pass → _increment_fail.
    # Only fires when plan.json and jq are available (graceful degradation otherwise).
    if [[ -f "$_plan_json" ]] && command -v jq >/dev/null 2>&1; then
      local _ui_mode="" _ui_step_id=""
      { read -r _ui_mode; read -r _ui_step_id; } < <(
        jq -r --argjson i "$step" \
          '(.steps[$i].ui_change_mode // "null"), (.steps[$i].id // "")' \
          "$_plan_json" 2>/dev/null
      ) || true
      if [[ "$_ui_mode" == "existing_ui" && -n "$_ui_step_id" ]]; then
        local _verdict_file="${evidence_dir}/steps/${_ui_step_id}/ui/verdict.json"
        local _verdict_result="absent"
        if [[ -f "$_verdict_file" ]]; then
          _verdict_result="$(jq -r '.ui_fidelity.result // "unverifiable"' "$_verdict_file" 2>/dev/null || echo "unverifiable")"
        fi
        if [[ "$_verdict_result" != "pass" ]]; then
          _increment_fail frontend_visual_fidelity_block \
            "PRECONDITION FAIL: existing_ui step requires ui/verdict.json with result=pass." \
            "Expected: ${_verdict_file}" \
            "Got result: ${_verdict_result} (absent|fail|unverifiable all block increment)" \
            "Fix: ensure companion captured baseline + ui-compare.mjs ran and produced result=pass before advancing." \
            "This is a step-local check. Delivery-gate/C4 aggregation is E9."
        fi
      fi
    fi

    # Session B CP2: verifier-output-step-N.md precondition
    # P040 Component D: streamlined mode skips per-step CP2 (covered by
    # integration-review enforcement at done-advance instead).
    if [[ "$streamlined" != "true" ]] && ! fsm_check_grandfather; then
      local verifier_output="${evidence_dir}/verifier-output-step-${step}.md"

      if ! fsm_check_verifier_output "$verifier_output"; then
        local timeline
        timeline=$(derive_timeline "$state_file") || true

        # Repeated-fail telemetry (step-level and epic-level)
        local attempt_step attempt_epic
        attempt_step=$(fsm_count_recent_fails_step "$step" "missing_verifier_output")
        attempt_epic=$(fsm_count_recent_fails_epic "missing_verifier_output")

        if (( attempt_step >= 3 )); then
          [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_repeated_fail_step" \
            step="$step" precondition="missing_verifier_output" attempt_count="$attempt_step"
          try_telegram_alert "Repeated step-level precondition fail (×${attempt_step}): EPIC=${epic_id}, step=${step}, precondition=missing_verifier_output"
        fi
        if (( attempt_epic >= 3 )); then
          [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_repeated_fail_epic" \
            precondition="missing_verifier_output" attempt_count="$attempt_epic"
          try_telegram_alert "Systematic precondition bypass (×${attempt_epic}): EPIC=${epic_id}, precondition=missing_verifier_output across multiple steps"
        fi

        [[ -n "$timeline" ]] && log_event "$timeline" "fsm_precondition_fail" \
          step="$step" reason="missing_verifier_output"

        die "ERROR: verifier-output-step-${step}.md missing or invalid.

Reason: AID v3 Session B requires per-step verifier dispatch (CP2). The pre-filter
        classifies the step diff as SKIP/RUN/FAIL; for RUN/FAIL a verifier subagent
        must run and update the output file before this increment.

Fix:
  1. bash \$AID_PLUGIN_PATH/scripts/aid-prefilter.sh classify ${step} ${evidence_dir}
  2. Based on exit code: 0=skip (already done), 10=run code-review verifier, 20=run security verifier,
     22=range_undetermined (emit step_commit/base_commit, or set CP2_RANGE_POLICY=observe)
  3. If RUN/FAIL, dispatch: subagent_type=aid-orchestrator:verifier with appropriate focus
     Verifier writes verdict + findings to ${verifier_output}
  4. Retry: aid-fsm.sh increment-step ${state_file}"
      fi

      # ── P060 Step 3: cp2 bypass guard (increment call-site ONLY) ──────────
      # The shared fsm_check_verifier_output accepts ANY valid checkpoint
      # (cp3/cp4 consumers at :409/:1566/:1583 legitimately carry checkpoint:
      # cp3|cp4 per agents/verifier.md). Here — and ONLY here — the per-step CP2
      # precondition must be satisfied by a cp2 output: a cp4-produced stub
      # (checkpoint: cp4) or cp3 output must NOT count. Absent checkpoint =
      # backward-compatible (older pre-filter outputs without the field).
      local _cp2_checkpoint
      _cp2_checkpoint=$(yaml_field "$verifier_output" checkpoint)
      if [[ -n "$_cp2_checkpoint" && "$_cp2_checkpoint" != "cp2" ]]; then
        _increment_fail wrong_checkpoint_stub \
          "PRECONDITION FAIL: verifier-output-step-${step}.md carries checkpoint '${_cp2_checkpoint}', expected cp2." \
          "File: ${verifier_output}" \
          "A cp3/cp4-produced output must not satisfy the per-step CP2 increment precondition." \
          "Fix: regenerate the step output via cp2: aid-prefilter.sh classify ${step} ${evidence_dir}"
      fi
    fi

    # Session B: mid-EPIC plan.json tampering check (PM Q2 refinement #2)
    local stored_hash current_hash
    stored_hash=$(yaml_field "$state_file" plan_json_hash) || true
    if [[ -n "$stored_hash" && -f "${evidence_dir}/plan.json" ]]; then
      current_hash=$(sha256sum "${evidence_dir}/plan.json" | awk '{print $1}')
      if [[ "$stored_hash" != "$current_hash" ]]; then
        die "ERROR: plan.json hash mismatch — modified mid-EPIC.
Reason: Mid-EPIC plan.json edits could expand step.outputs to allow scope creep.
        plan.json hash at init: ${stored_hash}
        plan.json hash now:     ${current_hash}
Fix: revert plan.json to init state, OR re-init EPIC if changes are legitimate."
      fi
    fi
  else
    fsm_handle_force_override "step-${step}" "step-$((step + 1))" "$state_file" "increment-step" "${@:3}"
    echo "WARNING: --force used, skipping step verification check" >&2
  fi

  # ---- E5 C2 Semantic Wiring-Gate (observe) ─────────────────────────────
  # Fresh inline impl; NOT a copy of cmd_done_advance (different context and
  # error mechanism: _increment_fail, not the errors counter used there).
  # Reads enforcement from defaults/policies/semantic-review.yaml
  # (env SEMANTIC_REVIEW_POLICY overrides; fail-safe: unreadable → observe).
  local _wiring_report="${evidence_dir}/semantic-review-wiring.json"
  local _semantic_enforcement="observe"

  # Read policy file; fail-safe to observe if missing/unreadable
  local _policy_file="${project_root}/plugins/aid-orchestrator/defaults/policies/semantic-review.yaml"
  if [[ -n "${SEMANTIC_REVIEW_POLICY:-}" ]]; then
    _semantic_enforcement="${SEMANTIC_REVIEW_POLICY}"
  elif [[ -f "$_policy_file" ]] && command -v yq >/dev/null 2>&1; then
    _semantic_enforcement=$(yq -r '.enforcement // "observe"' "$_policy_file" 2>/dev/null || echo "observe")
  fi

  # Count how many C2 modes have been dispatched (dispatch_observed)
  local _c2_modes_dispatched=0
  for _mode in local wiring behavior final; do
    [[ -f "${evidence_dir}/semantic-review-${_mode}.json" ]] && (( _c2_modes_dispatched++ )) || true
  done

  # Check wiring report for unresolved Critical/High findings
  if [[ -f "$_wiring_report" ]] && command -v jq >/dev/null 2>&1; then
    local _unresolved_blockers
    _unresolved_blockers=$(jq -r '
      .semantic_review.findings[]?
      | select(.status != "resolved" and .status != "deferred")
      | select(.severity == "critical" or .severity == "high")
      | .fingerprint
    ' "$_wiring_report" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "${_unresolved_blockers:-0}" -gt 0 ]]; then
      local _timeline
      _timeline=$(derive_timeline "$state_file") || true
      [[ -n "$_timeline" ]] && log_event "$_timeline" "semantic_wiring_would_block" \
        step="$step" unresolved_count="${_unresolved_blockers}" enforcement="${_semantic_enforcement}" \
        dispatch_observed="${_c2_modes_dispatched}"

      if [[ "$_semantic_enforcement" == "blocking" ]]; then
        _increment_fail semantic_wiring_blocked \
          "WIRING-GATE BLOCK: ${_unresolved_blockers} unresolved Critical/High wiring finding(s)." \
          "Wiring report: ${_wiring_report}" \
          "Set SEMANTIC_REVIEW_POLICY=observe to proceed in observe mode (E5 default)." \
          "Blocking mode is reserved for E10."
      fi
      # observe (default E5): log emitted above, increment continues
    fi
  fi
  # ---- end E5 C2 wiring-gate ─────────────────────────────────────────────

  # ---- P040 Component B: reconciliation backstop (orphan dispatch check) ----
  # Run orphan check UNCONDITIONALLY unless PM explicitly waived via BOTH
  # --force AND --blocked-checks dispatch_orphan_complete (HIGH-2 fix).
  #
  # Security rationale: the waiver MUST require --force so the --reason ≥20-char
  # enforcement in fsm_handle_force_override runs (it is invoked from the --force
  # branch above). A bare `--blocked-checks dispatch_orphan_complete` (no --force)
  # would otherwise waive the orphan check with a canned audit reason, bypassing
  # the forensic-grade reason requirement. Force ALONE (without
  # dispatch_orphan_complete in --blocked-checks) still runs the orphan check.
  if [[ "$force" == "true" && ",${blocked_checks}," == *",dispatch_orphan_complete,"* ]]; then
    fsm_emit_audit_log "fsm_orphan_dispatch_waived" \
      --evidence-dir "$evidence_dir" --reason "explicit_blocked_checks_waiver"
  else
    fsm_check_orphan_dispatches "$evidence_dir"   # dies on orphan
  fi

  local tmp="${state_file}.tmp"
  sed "s/^current_step: .*/current_step: $((step + 1))/" "$state_file" > "$tmp"
  mv "$tmp" "$state_file"

  # ── P060 Step 3: step_commit producer (OBS-20260705-01) ──────────────────
  # Log the commit sha at THIS step boundary so the cp2 pre-filter can anchor
  # its next-step diff range to the step (step_commit_sha..HEAD), not HEAD~1
  # (which a bookkeeping commit on top would fool into a docs_only false-green).
  # First introduces the step_commit event; aid-prefilter.sh cp2 consumes it.
  local _step_timeline _step_commit_sha
  _step_timeline=$(derive_timeline "$state_file") || true
  _step_commit_sha=$(git rev-parse HEAD 2>/dev/null || echo unknown)
  [[ -n "$_step_timeline" ]] && log_event "$_step_timeline" "step_commit" \
    step_n="$step" commit_sha="$_step_commit_sha"

  # ── OBS-20260708-04: steps[] array sync (single-source-of-truth drift) ────
  # fsm_init's header comment declares steps[] "single source of truth", but
  # historically only the current_step scalar (updated above, unconditionally)
  # was ever touched on increment — steps[] entries stayed status: pending
  # forever, even on fully DONE runs (VULCAN B-142 ×2, AID's own E-059-2_2
  # self-dogfood run). This block is additive/best-effort: current_step
  # remains the authoritative progress signal either way, so a legacy
  # fsm-state.yaml predating P040 Component E (no steps[] block) — or any
  # other steps[$step] miss — must not crash increment-step.
  if command -v yq >/dev/null 2>&1 && yq -e ".steps[${step}]" "$state_file" >/dev/null 2>&1; then
    local _sync_completed_at _sync_started _sync_expr
    _sync_completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _sync_started=$(yq -r ".steps[${step}].started_at" "$state_file" 2>/dev/null || echo "null")
    _sync_expr=".steps[${step}].status = \"completed\" | .steps[${step}].completed_at = \"${_sync_completed_at}\""
    # Backfill started_at only if it was never set — documents "known finished
    # by this time, exact start wasn't separately tracked" rather than leaving
    # started_at: null on an otherwise-completed step (internally inconsistent).
    if [[ "$_sync_started" == "null" ]]; then
      _sync_expr="${_sync_expr} | .steps[${step}].started_at = \"${_sync_completed_at}\""
    fi
    if yq -i "$_sync_expr" "$state_file" 2>/dev/null; then
      [[ -n "$_step_timeline" ]] && log_event "$_step_timeline" "step_status_synced" \
        step_n="$step" status="completed" completed_at="$_sync_completed_at"
    fi
  fi

  # ── P060 Step 6: commit_scope_violation companion (D7c, OBS-20260709-01/04) ─
  # --no-verify bypasses the pre-commit hook, so re-check scope out-of-band at
  # each step boundary. Diff the range actually committed during the step just
  # completed (prev_step_commit..HEAD) against that step's scope (allowed_paths
  # ∪ evidence dir) and emit a telemetry event for any out-of-scope file. The
  # prev step_commit is read from the timeline (the boundary BEFORE the one we
  # just appended, i.e. the second-to-last step_commit event); it falls back to
  # base_commit for the first step. This is NON-BLOCKING telemetry — never fails
  # the increment; skips silently when jq/plan.json/timeline are unavailable.
  if [[ -n "$_step_timeline" && -f "$_step_timeline" ]] \
     && command -v jq >/dev/null 2>&1 && [[ -f "${evidence_dir}/plan.json" ]]; then
    local _prev_sc
    _prev_sc=$(jq -rs '[.[] | select(.event == "step_commit")]
      | if length >= 2 then .[-2].commit_sha else "" end' "$_step_timeline" 2>/dev/null)
    if [[ -z "$_prev_sc" || "$_prev_sc" == "null" ]]; then
      _prev_sc=$(yaml_field "$state_file" base_commit)
    fi
    if [[ -n "$_prev_sc" && "$_prev_sc" != "unknown" ]]; then
      local -a _scope_paths=("$evidence_dir")
      local _sp _cf _inscope
      while IFS= read -r _sp; do
        [[ -n "$_sp" ]] && _scope_paths+=("$_sp")
      done < <(jq -r --argjson i "$step" '.steps[$i].allowed_paths[]?' \
                 "${evidence_dir}/plan.json" 2>/dev/null)
      local -a _violations=()
      while IFS= read -r -d '' _cf; do
        [[ -z "$_cf" ]] && continue
        _inscope=0
        for _sp in "${_scope_paths[@]}"; do
          [[ -z "$_sp" ]] && continue
          if [[ "$_cf" == "$_sp" || "$_cf" == "$_sp"/* ]]; then _inscope=1; break; fi
        done
        (( _inscope )) || _violations+=("$_cf")
      done < <(git diff --name-only -z "${_prev_sc}..HEAD" 2>/dev/null)
      if [[ ${#_violations[@]} -gt 0 ]]; then
        local _viol_csv
        _viol_csv=$(printf '%s,' "${_violations[@]}"); _viol_csv="${_viol_csv%,}"
        log_event "$_step_timeline" "commit_scope_violation" \
          step_n="$step" range="${_prev_sc}..HEAD" \
          out_of_scope_count="${#_violations[@]}" files="$_viol_csv"
      fi
    fi
  fi

  echo "$((step + 1))"
}

cmd_get_field() {
  local field="$1" state_file="$2"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }
  grep "^${field}:" "$state_file" | awk '{print $2}' | tr -d '"'
}

cmd_set_field() {
  local field="$1" value="$2" state_file="$3"
  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found" >&2; exit 1; }

  # Reserved fields — managed by dedicated commands only
  case "$field" in
    state) echo "ERROR: 'state' is reserved — use 'transition' command" >&2; exit 1 ;;
    done_phase) echo "ERROR: 'done_phase' is reserved — use 'done-advance' command" >&2; exit 1 ;;
  esac

  # Use awk (not sed s///) for the replace: a value containing "/" (e.g. a
  # path — plan_path is the common case) breaks a sed substitution
  # delimited by "/", and "&"/"\" in the value would be misinterpreted as
  # sed replacement-text metacharacters. awk's print performs no such
  # reinterpretation, so the value is written out literally either way.
  #
  # Pass $value via ENVIRON, not `-v v="$value"`: POSIX awk applies C-string
  # escape processing to `-v` assignments, so a value containing a literal
  # backslash sequence (e.g. "\n", "\t", "\\") would be silently rewritten
  # into a real control character instead of staying literal text.
  # Environment variables are read via ENVIRON[] with no such reprocessing.
  if grep -q "^${field}:" "$state_file"; then
    AID_SETFIELD_VALUE="$value" awk -v f="$field" '
      BEGIN { v = ENVIRON["AID_SETFIELD_VALUE"] }
      $0 ~ "^" f ":" { print f ": " v; next }
      { print }
    ' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  else
    echo "${field}: ${value}" >> "$state_file"
  fi
}

# ─── DONE Sub-Phase Advancement ─────────────────────────────────────────
# Phases within DONE: review → release
# Preconditions for review → release:
#   - curator-report exists (curator agent ran)
#   - audit-report exists (auditor agent ran)
#   - pm_decision field set to "merge"

VALID_DONE_PHASES="review release"

# ─── C4 dual-run divergence classifier (E-059-2_2 Step 5) ────────────────
# _c4_divergence_class <match> <c4_ready> <blocker_count> <blocker_ids_newline_sep>
# Maps a (match, C4 release_ready, C4 blocker-set) tuple onto the TOTAL 7-class
# divergence taxonomy, evaluated in strict PRECEDENCE ORDER. MECE + fail-closed:
# it ALWAYS prints exactly one non-empty class (never null/empty), so every
# release_policy_dual_run event carries a divergence_class. Pure function (no
# side effects) → unit-testable by sourcing aid-fsm.sh. blocker_ids are the
# canonical .release_decision.blockers[].input_id literals emitted by
# aid-release-policy.sh (note: semantic_review_final, not semantic_review).
_c4_divergence_class() {
  local match="$1" c4_ready="$2" bcount="$3" blockers="$4"
  # Sanitize bcount → integer (aggregator always emits a number; guard anyway).
  [[ "$bcount" =~ ^[0-9]+$ ]] || bcount=0

  # 1. none — C4 and legacy agree. Evaluated FIRST.
  [[ "$match" == "true" ]] && { printf 'none'; return 0; }

  # 2-5. Sole-blocker classes (exactly one C4 blocker). Pure-bash extraction —
  # no `grep | head` pipe (avoids the pipefail+SIGPIPE trap under set -euo pipefail;
  # this function is called from a command substitution inside cmd_done_advance).
  if [[ "$bcount" == "1" ]]; then
    local sole="$blockers"
    sole="${sole//$'\n'/}"   # single id → strip any surrounding newlines
    sole="${sole// /}"       # and spaces (a canonical input_id has neither)
    case "$sole" in
      verification_report) printf 'verification_only';  return 0 ;;
      reporter)            printf 'reporter_missing';   return 0 ;;
      simplifier)          printf 'simplifier_missing'; return 0 ;;
      review_profile|gates_report|plan_review|delivery_gate|semantic_review_final|acceptance_evidence|curator_report|audit_report)
                           printf 'required_input';     return 0 ;;
      *)                   printf 'unclassified';       return 0 ;;  # e.g. invalidation_map / unknown id
    esac
  fi

  # 6. c4_permissive — C4 says ready, legacy blocked, no C4 blocker.
  if [[ "$bcount" == "0" && "$c4_ready" == "true" ]]; then
    printf 'c4_permissive'; return 0
  fi

  # 7. mixed — 2+ C4 blockers of any categories (incl. same category).
  if [[ "$bcount" -ge 2 ]]; then
    printf 'mixed'; return 0
  fi

  # 8. unclassified — FAIL-CLOSED catch-all (e.g. not-ready + empty blockers).
  printf 'unclassified'; return 0
}

cmd_done_advance() {
  local from_phase="$1" to_phase="$2" state_file="$3"
  local force="false"
  [[ "${4:-}" == "--force" ]] && force="true"

  [[ -f "$state_file" ]] || { echo "ERROR: state_file not found: $state_file" >&2; exit 1; }

  # Must be in DONE state
  local current_state
  current_state=$(yaml_field "$state_file" state)
  [[ "$current_state" == "DONE" ]] || {
    echo "ERROR: done-advance requires state DONE, found: $current_state" >&2
    exit 1
  }

  # Validate current phase matches
  local current_phase
  current_phase=$(yaml_field "$state_file" done_phase)
  [[ "$current_phase" == "$from_phase" ]] || {
    echo "ERROR: expected done_phase=$from_phase but found $current_phase" >&2
    exit 1
  }

  # Validate phases
  [[ " $VALID_DONE_PHASES " =~ " $to_phase " ]] || {
    echo "ERROR: invalid done_phase: $to_phase (valid: $VALID_DONE_PHASES)" >&2
    exit 1
  }

  # Precondition checks (skip with --force)
  if [[ "$force" == "true" ]]; then
    local epic_id run_id evidence_dir
    local project_root="$PWD"
    epic_id=$(yaml_field "$state_file" epic_id)
    run_id=$(yaml_field "$state_file" run_id)
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    fsm_handle_force_override "$from_phase" "$to_phase" "$state_file" "done-advance" "${@:5}"
    echo "WARNING: --force used, skipping precondition checks for done-advance $from_phase → $to_phase" >&2

    # P044: pair a pending 🛑 blocked alert with a ✅ resolution even when the
    # block is cleared via PM force-override — the non-force recovery path in
    # the else-branch below is skipped entirely on --force, so without this
    # call a force-cleared block never emits the recovery alert.
    if [[ "$from_phase" == "review" && "$to_phase" == "release" ]]; then
      fsm_emit_compliance_recovery "$epic_id" "${evidence_dir}/timeline.jsonl" "$project_root" \
        "✅ ${epic_id}: compliance block cleared via PM force-override, release unblocked."
    fi
  else
    # Check preconditions for review → release
    if [[ "$from_phase" == "review" && "$to_phase" == "release" ]]; then
      local epic_id run_id evidence_dir errors=0
      local project_root="$PWD"
      epic_id=$(yaml_field "$state_file" epic_id)
      run_id=$(yaml_field "$state_file" run_id)
      evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"

      # P040 Component D: integration-review file existence (streamlined contract)
      if ! fsm_check_streamlined_integration_review "$evidence_dir" "$state_file"; then
        return 1
      fi
      # P040 Component D: abandoned-but-shipped check (timeline event count)
      if ! fsm_check_streamlined_abandoned "$evidence_dir" "$state_file"; then
        return 1
      fi

      # E2 DG-07 hook: state-consistency delivery check (observe mode by default)
      # Reads enforcement from delivery-gate.yaml policy:
      #   observe  → write delivery_gate_would_block telemetry only (no block)
      #   blocking → block done-advance if DG-07 fails (E10 promotion path)
      # Fail-safe: if policy is missing or unreadable, default to observe (never block).
      local _dg07_enforcement _dg07_policy _dg07_script _dg07_exit _dg07_output
      local _dg07_timeline="${evidence_dir}/timeline.jsonl"
      # DELIVERY_GATE_POLICY env var allows test/CI override of the policy path.
      _dg07_policy="${DELIVERY_GATE_POLICY:-${SCRIPT_DIR}/../defaults/policies/delivery-gate.yaml}"
      _dg07_enforcement="observe"   # fail-safe default
      if [[ -f "$_dg07_policy" ]] && command -v yq >/dev/null 2>&1; then
        local _pol_enforcement
        _pol_enforcement=$(yq e '.enforcement // "observe"' "$_dg07_policy" 2>/dev/null || echo "observe")
        [[ "$_pol_enforcement" == "blocking" ]] && _dg07_enforcement="blocking"
      fi

      _dg07_script="${SCRIPT_DIR}/lib/delivery-checks/dg07-state-consistency.sh"
      if [[ -f "$_dg07_script" ]]; then
        _dg07_exit=0
        _dg07_output=$(AID_PROJECT_ROOT="$project_root" \
                       AID_EPIC_ID="$epic_id" \
                       AID_RUN_ID="$run_id" \
                       bash "$_dg07_script" 2>&1) || _dg07_exit=$?

        if [[ "$_dg07_exit" -eq 1 ]]; then
          # DG-07 detected an inconsistency
          log_event "$_dg07_timeline" "delivery_gate_would_block" \
            check="dg07" enforcement="$_dg07_enforcement" output="$_dg07_output"

          if [[ "$_dg07_enforcement" == "blocking" ]]; then
            echo "ERROR: DG-07 state-consistency check failed (enforcement=blocking):" >&2
            echo "$_dg07_output" >&2
            echo "" >&2
            echo "Run with --force to override (PM-authorized, audited)." >&2
            log_event "$_dg07_timeline" "fsm_done_advance_fail" check="dg07" reason="state_inconsistency"
            exit 2
          else
            log_warn "DG-07 state-consistency would_block (enforcement=observe, delivery_ready will be false)"
          fi
        fi
        # exit 2 (unverifiable) or 0 (pass): no block, no event
      fi
      # End DG-07 E2 hook

      # E3 review_profile hook: missing_lenses observe telemetry
      # REVIEW_PROFILE_POLICY env overrides policy path for test/CI.
      # Fail-safe: missing policy → observe (never block).
      local _rp_enforcement _rp_policy _rp_check_script _rp_exit _rp_output
      local _rp_timeline="${evidence_dir}/timeline.jsonl"
      _rp_policy="${REVIEW_PROFILE_POLICY:-${SCRIPT_DIR}/../defaults/policies/review-profiles.yaml}"
      _rp_enforcement="observe"
      if [[ -f "$_rp_policy" ]] && command -v yq >/dev/null 2>&1; then
        local _pol_rp_enforcement
        _pol_rp_enforcement=$(yq e '.enforcement // "observe"' "$_rp_policy" 2>/dev/null || echo "observe")
        [[ "$_pol_rp_enforcement" == "blocking" ]] && _rp_enforcement="blocking"
      fi

      _rp_check_script="${SCRIPT_DIR}/lib/review-profile-check.sh"
      if [[ -f "$_rp_check_script" ]]; then
        _rp_exit=0
        _rp_output=$(AID_PROJECT_ROOT="$project_root" \
                     AID_EPIC_ID="$epic_id" \
                     AID_RUN_ID="$run_id" \
                     bash "$_rp_check_script" 2>&1) || _rp_exit=$?

        if [[ "$_rp_exit" -eq 1 ]]; then
          log_event "$_rp_timeline" "review_profile_missing_lenses" \
            check="review_profile" enforcement="$_rp_enforcement" missing_lenses="$_rp_output"

          if [[ "$_rp_enforcement" == "blocking" ]]; then
            echo "ERROR: review profile missing lenses (enforcement=blocking):" >&2
            echo "$_rp_output" >&2
            log_event "$_rp_timeline" "fsm_done_advance_fail" check="review_profile" reason="missing_lenses"
            exit 2
          else
            log_warn "review_profile missing_lenses (enforcement=observe, non-blocking): $_rp_output"
          fi
        elif [[ "$_rp_exit" -eq 2 ]]; then
          log_event "$_rp_timeline" "review_profile_missing_lenses" \
            check="review_profile" enforcement="observe" missing_lenses="unverifiable" reason="$_rp_output"
          log_warn "review_profile unverifiable: $_rp_output"
        fi
      fi
      # End E3 review_profile hook

      # ── C3 activation (IMP-177 / E-059-1_2 Step 1): resolve the C3 audit
      # enforcement mode ONCE, then apply it to BOTH the review-profile presence
      # check (below) and the C3 independent-audit hook (further down). The
      # `enforcement:` key (observe|blocking) already lives in c3-audit-policy.yaml
      # since E8 — this is the first caller that reads it. C3_AUDIT_POLICY env
      # overrides the policy PATH (test/CI seam, mirrors DELIVERY_GATE_POLICY);
      # it overrides the enforcement toggle only, not the per-profile c3_required
      # risk-gate below (which stays anchored to the installed default policy).
      # Fail-safe: missing policy / missing yq → observe (never block). The C3
      # gate is staged OBSERVE by default; E10 promotion flips the policy default
      # to blocking. See AID-v3-principles.md §1.
      local c3_default_policy="${PLUGIN_ROOT}/defaults/policies/c3-audit-policy.yaml"
      local c3_enforce_policy="${C3_AUDIT_POLICY:-$c3_default_policy}"
      local c3_enforcement="observe"
      local _c3_timeline="${evidence_dir}/timeline.jsonl"
      if [[ -f "$c3_enforce_policy" ]] && command -v yq >/dev/null 2>&1; then
        local _pol_c3_enf
        _pol_c3_enf=$(yq e '.enforcement // "observe"' "$c3_enforce_policy" 2>/dev/null || echo "observe")
        [[ "$_pol_c3_enf" == "blocking" ]] && c3_enforcement="blocking"
      fi

      # ── C3 activation: review-profile.json presence check (producer wiring). ──
      # review-profile.json is produced in the DONE review sub-phase (pipeline.md,
      # aid-prefilter.sh profile over the full base_commit..HEAD diff). Its ABSENCE
      # means the C3 producer wiring did not run for this EPIC. OBSERVE by default:
      # emit review_profile_would_block telemetry but DO NOT block — grandfather-safe
      # for in-flight EPICs (e.g. E-046-3_3) that predate the producer wiring.
      # enforcement=blocking (E10 / C3_AUDIT_POLICY test override) flips this to a
      # hard precondition failure so the blocking branch stays live, testable code.
      if [[ ! -f "${evidence_dir}/review-profile.json" ]]; then
        log_event "$_c3_timeline" "review_profile_would_block" \
          check="review_profile_presence" enforcement="$c3_enforcement" \
          reason="review-profile.json absent in evidence dir"
        if [[ "$c3_enforcement" == "blocking" ]]; then
          echo "PRECONDITION FAIL: review-profile.json not found in ${evidence_dir}/ — C3 producer hook must run in the DONE review sub-phase (enforcement=blocking)." >&2
          log_event "$_c3_timeline" "fsm_done_advance_fail" check="review_profile_presence" reason="profile_absent"
          exit 2
        else
          log_warn "review_profile presence would_block (enforcement=observe, non-blocking): review-profile.json absent in ${evidence_dir}"
        fi
      fi
      # End C3 activation review-profile presence check

      # ── C3 activation (IMP-177 / E-059-1_2 Step 2): invalidation-map expectation
      # check (OBSERVE). Closes the OTHER half of IMP-177: aid-invalidation-map.sh
      # was registered but never called from the live flow. The pipeline.md post-fix
      # hook now (a) emits a `gate_fixer_fix_applied` timeline event whenever a
      # gate-fixer fix lands at an in-scope dispatch site, and (b) calls
      # aid-invalidation-map.sh, which emits an `invalidation_map_produced` event.
      # This check compares the COUNTS of these two events (not just presence) to
      # detect when a fix was applied but its post-fix hook did not run. Multiple
      # applied fixes without corresponding invalidation_map_produced events
      # ⇒ emit invalidation_map_expected_missing telemetry.
      #
      # OBSERVE by default (transition PASSES). INVALIDATION_MAP_ENFORCEMENT=blocking
      # (E10 promotion / test seam, mirrors the C3_AUDIT_POLICY override convention)
      # flips it to a hard precondition so the blocking branch stays live, testable
      # code rather than decoration. Fail-closed reads: no timeline / no
      # gate_fixer_fix_applied event ⇒ no fix was applied ⇒ this check is a no-op
      # (never manufactures a would_block on runs that applied no fixes).
      local _im_enforcement="${INVALIDATION_MAP_ENFORCEMENT:-observe}"
      local _im_timeline="${evidence_dir}/timeline.jsonl"
      if [[ -f "$_im_timeline" ]]; then
        local _im_applied _im_produced
        # Count gate_fixer_fix_applied events in the timeline (fail-safe to 0).
        # Use -Rc (raw input + compact output) so jq outputs one line per matched event,
        # avoiding pretty-printing inflation that would inflate wc -l count.
        _im_applied=$(jq -Rc 'fromjson? | select(.event=="gate_fixer_fix_applied")' "$_im_timeline" 2>/dev/null | wc -l)
        # Count invalidation_map_produced events in the timeline (fail-safe to 0).
        # Use -Rc (raw input + compact output) so jq outputs one line per matched event.
        _im_produced=$(jq -Rc 'fromjson? | select(.event=="invalidation_map_produced")' "$_im_timeline" 2>/dev/null | wc -l)

        if [[ $_im_applied -gt 0 && $_im_produced -lt $_im_applied ]]; then
          # At least one fix was applied but fewer invalidation-map events were produced.
          log_event "$_im_timeline" "invalidation_map_expected_missing" \
            check="invalidation_map_expected" enforcement="$_im_enforcement" \
            reason="gate_fixer_fix_applied events($_im_applied) > invalidation_map_produced($_im_produced)"
          if [[ "$_im_enforcement" == "blocking" ]]; then
            echo "PRECONDITION FAIL: gate_fixer_fix_applied events($_im_applied) exceeds invalidation_map_produced events($_im_produced) — the invalidation-map post-fix hook (pipeline.md, search: 'Invalidation-Map Post-Fix Hook') must run after every gate-fixer fix (enforcement=blocking)." >&2
            log_event "$_im_timeline" "fsm_done_advance_fail" check="invalidation_map_expected" reason="invalidation_map_event_count_mismatch"
            exit 2
          else
            log_warn "invalidation_map_expected would_block (enforcement=observe, non-blocking): gate_fixer_fix_applied($_im_applied) > invalidation_map_produced($_im_produced) in ${evidence_dir}"
          fi
        fi
      fi
      # End C3 activation invalidation-map expectation check

      # P038 Step 3: tiered severity blocking precondition.
      # Runs ONLY for review→release transition (other done-advance phases unchanged).
      # Evaluates compliance checks inline (no file write), filters severity:blocking
      # failures via the shared fsm_build_failures helper, and aborts with exit 2 +
      # structured error message when any blocking failure is detected.
      # Soft-fail design: missing check-severity.yaml / missing yq / telemetry
      # crash all degrade to "no blocking failures detected" — release proceeds.
      # See AID-v3-principles.md §1 (Detector without Enforcement is Decoration).
      local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"
      local _checks_json _failures_json _blocking_count
      local _timeline="${evidence_dir}/timeline.jsonl"
      if _checks_json=$(evaluate_compliance_checks "$epic_id" "$state_file" "$evidence_dir" "$project_root" 2>/dev/null); then
        _failures_json=$(fsm_build_failures "$_checks_json" "$severity_yaml")
        _blocking_count=$(echo "$_failures_json" | jq '[.[] | select(.severity == "blocking")] | length' 2>/dev/null || echo "0")

        if [[ "${_blocking_count:-0}" -gt 0 ]]; then
          # Persist compliance.json so the failed release leaves an audit trail.
          # Best-effort: write failure is non-fatal (telemetry over correctness).
          write_compliance_json "$epic_id" "$run_id" "$state_file" "$evidence_dir" "$project_root" 2>/dev/null || true

          local _blocking_list _blocking_names
          # MEDIUM-2 trust boundary: _blocking_names and _blocking_list derive from
          # failures[] in compliance.json (generated by FSM, not user input). Safe to echo.
          # Registry key names are constrained by the alphanumeric+underscore pattern
          # validated in cmd_promote_check. If future check names flow from user input,
          # this heredoc would need printf '%q' escaping.
          _blocking_list=$(echo "$_failures_json" | jq -r '
            [.[] | select(.severity == "blocking")] |
            to_entries[] |
            "  [\(.key + 1)] check=\(.value.check) severity=\(.value.severity)\n      evidence: \(.value.evidence)\n      promoted_at: \(.value.promoted_at // "unknown")"' 2>/dev/null || echo "  (failure list unavailable)")
          _blocking_names=$(echo "$_failures_json" | jq -r '[.[] | select(.severity == "blocking") | .check] | join(",")' 2>/dev/null || echo "")

          cat >&2 <<EOF
ERROR: ${_blocking_count} blocking compliance failure(s) detected — cannot advance to release.

${_blocking_list}

Fix: address root cause (re-dispatch verifier subagents OR fix dispatch_mode config OR
correct missing AC evidence), then retry:
  aid-fsm.sh done-advance review release ${state_file}

OR (PM-authorized override, audited):
  aid-fsm.sh done-advance review release ${state_file} \\
    --force \\
    --reason '<≥20 chars explaining why this is acceptable>' \\
    --blocked-checks '${_blocking_names}'

Audit log entry will be appended to .aid-o/work/audit-log.jsonl with the full reason
and blocked_checks list. See AID-v3-principles.md §1 for the enforcement contract.
EOF

          try_telegram_alert "🛑 ${epic_id}: ${_blocking_count} blocking compliance failure(s) — release blocked. Checks: ${_blocking_names}"

          [[ -f "$_timeline" ]] && log_event "$_timeline" "fsm_done_advance_blocked" \
            blocking_count="$_blocking_count" blocked_checks="$_blocking_names"

          # E-059-2_2 Step 5: this hard-exit preempts the C4 dual-run slot below.
          # Observe telemetry (sampling-bias fix) — no gate behavior change.
          log_event "$_timeline" "release_policy_preempted" \
            gate="tiered_compliance" \
            head_sha="$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo unknown)"

          exit 2
        fi

        # P042: Recovery alert — fires when a previously-blocked EPIC now has zero blocking
        # failures. Shared emitter handles the alert gate + dedup marker (see
        # fsm_emit_compliance_recovery; the --force path calls it too, P044).
        fsm_emit_compliance_recovery "$epic_id" "$_timeline" "$project_root" \
          "✅ ${epic_id}: compliance cleared, release unblocked."
      fi
      # End P038/P042 compliance block. Falls through to existing curator/auditor checks.

      # P040 Component C: CP4 enforcement (must run before existing curator-report check)
      if ! fsm_check_cp4_curator_validation "$evidence_dir" "$project_root" "$state_file"; then
        return 1  # die() already called inside
      fi

      # P060 Step 4: CP3 freshness re-check at review→release. The GATES:DONE probe
      # is the primary gate, but CP4 / review-phase commits can land AFTER DONE and
      # move HEAD past the reviewed CP3 head — this re-check catches that class.
      # Grandfather + policy (default BLOCKING, D9) handled inside.
      if ! fsm_check_cp3_freshness "$evidence_dir" "$state_file" "$project_root"; then
        log_event "${evidence_dir}/timeline.jsonl" "fsm_done_advance_fail" \
          check="cp3_freshness" reason="${_PRECONDITION_FAIL_REASON:-cp3_stale_review}"
        return 1
      fi

      # Curator report must exist
      if [[ ! -f "${evidence_dir}/curator-report.yaml" && ! -f "${evidence_dir}/curator-report.md" ]]; then
        echo "PRECONDITION FAIL: Curator report not found in ${evidence_dir}/. Curator agent must run first." >&2
        errors=$((errors + 1))
      fi

      # Auditor report must exist
      if [[ ! -f "${evidence_dir}/audit-report.yaml" && ! -f "${evidence_dir}/audit-report.md" ]]; then
        echo "PRECONDITION FAIL: Auditor report not found in ${evidence_dir}/. Auditor agent must run first." >&2
        errors=$((errors + 1))
      fi

      # Risk-profile resolution (shared by Curator guard and C3 hook).
      # Must run BEFORE the Curator guard to determine if C3 is required.
      # Fail-closed risk-profile gate: resolve risk_profile and decide if hook fires.
      local c3_risk_profile="" c3_hook_fired="false"
      local review_profile_file="${evidence_dir}/review-profile.json"
      local c3_report_file="${evidence_dir}/audit-report.json"

      if [[ -f "$review_profile_file" ]]; then
        if ! command -v jq >/dev/null 2>&1; then
          # jq missing but file exists → ambiguous, fail-closed: treat as unverifiable
          c3_risk_profile="unverifiable"
        else
          # jq available, try to read. If read succeeds, validate that the resolved
          # value is one of the known enum values.
          # CP4 round 3 fix: guard against set -e crash if review-profile.json is valid
          # JSON but .review_profile is not an object (jq errors on the index attempt).
          local resolved_profile="" resolved_exit_code=0
          resolved_profile=$(jq -r '.review_profile.risk_profile // "MISSING"' "$review_profile_file" 2>/dev/null) || resolved_exit_code=$?
          if [[ $resolved_exit_code -eq 0 && "$resolved_profile" != "MISSING" ]]; then
            # jq succeeded in reading a non-null value; check if it's valid enum.
            case "$resolved_profile" in
              docs_trivial|low|medium|high|unverifiable)
                c3_risk_profile="$resolved_profile"
                ;;
              *)
                # Invalid enum value (should not happen from a well-formed schema,
                # but fail-closed: treat as unverifiable).
                c3_risk_profile="unverifiable"
                ;;
            esac
          else
            # jq failed, or read null/missing key → ambiguous, fail-closed.
            c3_risk_profile="unverifiable"
          fi
        fi
      fi

      # Primary trigger: read c3_required from policy file for the resolved risk profile.
      # Fail-closed: if profile is unverifiable, or if policy read fails/is ambiguous,
      # treat as requiring C3.
      if [[ -n "$c3_risk_profile" ]]; then
        local c3_required_from_policy="" policy_read_succeeded="false"
        # Per-profile c3_required risk-gate reads the installed default policy
        # (NOT the C3_AUDIT_POLICY enforcement override) — see c3_default_policy
        # rationale above. Reuses the single definition for DRY (GEN-007).
        local policy_file="$c3_default_policy"

        # Only attempt policy read if both file exists AND yq is available.
        if [[ -f "$policy_file" ]] && command -v yq >/dev/null 2>&1; then
          # Use has() to distinguish "key absent" from "key present but false".
          # Both scenarios yield exit 0 and "false" output with the old // false fallback,
          # making it impossible to distinguish. The fix: check presence first.
          # CP4 round 2 fix: bare `var=$(cmd)` under `set -e` aborts the WHOLE SCRIPT if
          # cmd (yq) exits non-zero (e.g. malformed/unparseable policy YAML) — the `|| ...`
          # guard is mandatory here so a corrupted policy file fails closed with a proper
          # PRECONDITION FAIL message instead of an unhandled script crash.
          local has_profile_key="" has_exit_code=0
          has_profile_key=$(yq -r "(.risk_profiles | has(\"$c3_risk_profile\")) and (.risk_profiles[\"$c3_risk_profile\"] | has(\"c3_required\"))" "$policy_file" 2>/dev/null) || has_exit_code=$?
          if [[ $has_exit_code -eq 0 && "$has_profile_key" == "true" ]]; then
            local c3_required_exit_code=0
            c3_required_from_policy=$(yq -r ".risk_profiles[\"$c3_risk_profile\"].c3_required" "$policy_file" 2>/dev/null) || c3_required_exit_code=$?
            if [[ $c3_required_exit_code -eq 0 && ("$c3_required_from_policy" == "true" || "$c3_required_from_policy" == "false") ]]; then
              policy_read_succeeded="true"
            fi
          fi
        fi

        # Fire hook if:
        #   1. Policy read succeeded AND c3_required is true, OR
        #   2. Policy read failed or was ambiguous for a high-risk profile (fail-closed: can't confirm false), OR
        #   3. Profile is unverifiable (fail-closed for ambiguous/unparseable resolution)
        if [[ "$policy_read_succeeded" == "true" && "$c3_required_from_policy" == "true" ]]; then
          c3_hook_fired="true"
        elif [[ "$policy_read_succeeded" != "true" && "$c3_risk_profile" == "high" ]]; then
          # Policy read failed/ambiguous for high-risk profile → fail-closed
          c3_hook_fired="true"
        elif [[ "$c3_risk_profile" == "unverifiable" ]]; then
          c3_hook_fired="true"
        fi
      fi

      # Secondary independent trigger: if review-profile.json exists (this run went through
      # C3 pipeline) BUT the primary gate didn't fire, AND audit-report.json exists and has
      # a valid .audit_report structure, fire the hook. This closes the case where the primary
      # gate (risk-profile resolution) is somehow fooled but a real C3 report was produced for
      # this run (e.g., review-profile.json corrupted, all detection mechanisms missed it, but
      # the C3 stage still ran and produced a report).
      # NOTE: Must run BEFORE the Curator guard so that c3_hook_fired is fully resolved when
      # the guard consults it (E-057-2_2 Step 1 defense-in-depth fix).
      if [[ "$c3_hook_fired" != "true" && -f "$review_profile_file" && -f "$c3_report_file" ]]; then
        if command -v jq >/dev/null 2>&1; then
          # CP4 round 3 fix: guard against set -e crash if audit-report.json is valid
          # JSON but not an object at the top level (jq errors piping into `.audit_report`).
          local has_audit_report="" has_audit_exit_code=0
          has_audit_report=$(jq -r 'if (.audit_report | type) == "object" and (.audit_report | length) > 0 then "true" else "false" end' "$c3_report_file" 2>/dev/null) || has_audit_exit_code=$?
          if [[ $has_audit_exit_code -eq 0 && "$has_audit_report" == "true" ]]; then
            c3_hook_fired="true"
            # Secondary trigger fired; set risk_profile for error messages below.
            # We don't know the original profile, so use "unverifiable" as the reason.
            c3_risk_profile="unverifiable"
          fi
        fi
      fi

      # E-057-2_2 Step 1: Curator content-ref sequencing guard (risk-gated, JSON).
      # Curator now dual-emits curator-report.json alongside curator-report.md
      # (`agents/curator.md`), carrying `.curator.audit_report_ref` = sha256 of the
      # CONTENT of the audit-report.json it actually consumed — a content hash (not
      # `head_sha`) proves the Curator genuinely ran AFTER the Auditor and ingested
      # that exact audit output, not just at the same commit (L1 fix). This check is
      # ADDITIVE to the .md/.yaml existence checks above (which stay — other code
      # paths rely on that file-existence contract).
      #
      # Risk-gating (mirrors C3 hook pattern at lines ~2725-2799):
      # - When c3_hook_fired == "true" (high/unverifiable risk profile), curator-report.json
      #   is REQUIRED: absence of the whole file is a hard block (fail-closed), because on
      #   a C3-required run, Curator is expected to emit it. This matches agents/curator.md
      #   C3.5 dual-emit contract.
      # - When c3_hook_fired == "false" (other profiles or no review-profile.json), the file
      #   is optional: absence is a silent no-op (pre-C3 Curator runs have no JSON file).
      #
      # When curator-report.json DOES exist, fail-closed validation applies to its contents:
      # missing/unreadable ref, missing audit-report.json, or a hash mismatch all block.
      # Every jq/sha256sum command substitution is guarded against `set -e` (this script
      # runs under `set -euo pipefail`), matching the C3 hook pattern.
      local curator_json="${evidence_dir}/curator-report.json"
      local audit_json="${evidence_dir}/audit-report.json"

      if [[ -f "$curator_json" ]]; then
        # File exists: perform content-ref validation (fail-closed on any anomaly).
        if ! command -v jq >/dev/null 2>&1; then
          echo "PRECONDITION FAIL: jq is required to verify curator-report.json's audit_report_ref and is not available (fail-closed)." >&2
          errors=$((errors + 1))
        elif [[ ! -f "$audit_json" ]]; then
          echo "PRECONDITION FAIL: curator-report.json exists but audit-report.json not found — cannot verify sequencing ref (fail-closed). See: ${curator_json}" >&2
          errors=$((errors + 1))
        else
          local cref="" cref_ec=0 actual_hash="" actual_hash_ec=0
          cref=$(jq -r '.curator.audit_report_ref // empty' "$curator_json" 2>/dev/null) || cref_ec=$?
          [[ $cref_ec -ne 0 ]] && cref=""
          actual_hash=$(sha256sum "$audit_json" 2>/dev/null | awk '{print $1}') || actual_hash_ec=$?
          [[ $actual_hash_ec -ne 0 ]] && actual_hash=""
          local cref_hex="${cref#sha256:}"

          if [[ -z "$cref" ]]; then
            echo "PRECONDITION FAIL: curator-report.json missing .curator.audit_report_ref (sequencing fail-closed). See: ${curator_json}" >&2
            errors=$((errors + 1))
          elif [[ -z "$actual_hash" ]]; then
            echo "PRECONDITION FAIL: could not compute sha256 of ${audit_json} (sequencing fail-closed)." >&2
            errors=$((errors + 1))
          elif [[ "$cref_hex" != "$actual_hash" ]]; then
            echo "PRECONDITION FAIL: curator-report.json .curator.audit_report_ref (${cref}) does not match sha256 of audit-report.json content (sha256:${actual_hash}) — Curator did not consume the current audit output (sequencing violation)." >&2
            errors=$((errors + 1))
          fi
          # cref_hex == actual_hash → passes silently.
        fi
      elif [[ "$c3_hook_fired" == "true" ]]; then
        # File missing but C3 is required: hard block (fail-closed).
        echo "PRECONDITION FAIL: curator-report.json not found (risk profile '${c3_risk_profile}' requires C3 audit and dual-emitted curator report)." >&2
        echo "Curator agent must run after Auditor (C3) and emit both curator-report.md and curator-report.json. See: ${curator_json}" >&2
        errors=$((errors + 1))
      fi
      # If file missing AND c3_hook_fired == "false": silent no-op (pre-C3 run)

      # PM decision must be set to merge
      local pm_decision
      pm_decision=$(yaml_field "$state_file" pm_decision)
      [[ "$pm_decision" == "merge" ]] || {
        echo "PRECONDITION FAIL: pm_decision must be 'merge', found: '${pm_decision:-<not set>}'." >&2
        errors=$((errors + 1))
      }

      # EPIC task file must be archived (moved to tasks/archive/)
      local task_file
      task_file=$(find .aid-o/tasks/ -maxdepth 1 -name "${epic_id}*" 2>/dev/null | head -1)
      if [[ -n "$task_file" ]]; then
        echo "PRECONDITION FAIL: EPIC task file still in tasks/ (not archived): $(basename "$task_file")" >&2
        echo "Move to tasks/archive/ before advancing: mv $task_file .aid-o/tasks/archive/" >&2
        errors=$((errors + 1))
      fi

      # E-057-1_2 Step 4: C3 independent-audit hook (risk-gated, JSON source of truth).
      # Reads `.audit_report.blocking_findings` from audit-report.json (protocol-v2
      # envelope, agents/auditor.md C3 mode, E-057-1_2 Step 2). This REPLACES the legacy
      # yaml_field()-based .md/.yaml blocking_findings read directly below for any run
      # whose risk profile requires C3 — ONE source of truth, not two parallel checks
      # (M2 fix). Risk profile comes from review-profile.json (produced by
      # aid-prefilter.sh profile / skills/pipeline.md's C3 producer hook, E-057-1_2 Step
      # 3); this hook only fires when that profile is "high" or "unverifiable" — the two
      # (and only two) `c3_required: true` profiles in c3-audit-policy.yaml (D8/D9). Any
      # other profile (docs_trivial/low/medium), or a run with no review-profile.json at
      # all (pre-C3 runs never subjected to this pipeline stage), leaves this hook a
      # no-op and falls through unchanged to the legacy blocking_findings check below.
      #
      # Fail-closed (D4): missing/unreadable/unparseable audit-report.json, a missing
      # `.audit_report.input_manifest_hash` (provenance), a `status` of "unverifiable"
      # (independence could not be confirmed), or a stale `revision.head_sha` that no
      # longer matches the run's actual current HEAD (freshness — an audit computed
      # against a prior commit must not authorize release of the current commit,
      # mirroring the E2.5 stale-artifact-acceptance lesson) ALL block. No `// false`
      # jq fallback anywhere below — absence/unreadability is treated as blocking, never
      # as a silent pass.
      #
      # CP2 Fix: Fire hook fail-closed if review-profile.json exists but:
      #   - jq is unavailable (cannot read it), OR
      #   - .review_profile.risk_profile is null/missing/invalid enum (not one of
      #     docs_trivial|low|medium|high|unverifiable from review-profile.schema.json)
      # Also fire hook (secondary independent trigger) if audit-report.json exists and is
      # parseable with a valid .audit_report structure (non-null object), regardless of
      # risk_profile resolution.
      #
      # NOTE: c3_risk_profile and c3_hook_fired are now fully initialized and computed,
      # including secondary trigger at lines ~2711-2735 (shared initialization for Curator
      # guard + C3 hook). The secondary trigger completes resolution before the Curator guard
      # runs, ensuring c3_hook_fired reflects BOTH primary and secondary conditions (E-057-2_2
      # Step 1 defense-in-depth fix).

      if [[ "$c3_hook_fired" == "true" ]]; then
        local c3_block_reason=""

        if ! command -v jq >/dev/null 2>&1; then
          c3_block_reason="jq is required to verify audit-report.json and is not available"
        elif [[ ! -f "$c3_report_file" ]]; then
          c3_block_reason="audit-report.json not found (risk profile '${c3_risk_profile}' requires a C3 audit)"
        elif ! jq -e . "$c3_report_file" >/dev/null 2>&1; then
          c3_block_reason="audit-report.json is not valid/parseable JSON"
        else
          # CP4 round 3 fix: guard all 4 jq reads against set -e crash — audit-report.json
          # passed the `jq -e .` parseability check above, but that only proves the TOP
          # level is valid JSON, not that `.audit_report`/`.revision` are objects. A report
          # where e.g. `.audit_report` is a string/array/scalar makes jq error on `.field`
          # indexing, which would otherwise abort this whole function via set -e instead of
          # falling through to the fail-closed checks below (which already correctly treat
          # empty/MISSING values as blocking — the guard only prevents the crash, it does
          # not change the fail-closed semantics).
          local c3_blocking="" c3_status="" c3_manifest_hash="" c3_head_sha="" c3_current_head=""
          local c3_blocking_ec=0 c3_status_ec=0 c3_manifest_hash_ec=0 c3_head_sha_ec=0
          c3_blocking=$(jq -r 'if (.audit_report.blocking_findings | type) == "boolean" then (.audit_report.blocking_findings | tostring) else "MISSING" end' "$c3_report_file" 2>/dev/null) || c3_blocking_ec=$?
          [[ $c3_blocking_ec -ne 0 ]] && c3_blocking="MISSING"
          c3_status=$(jq -r '.status // "MISSING"' "$c3_report_file" 2>/dev/null) || c3_status_ec=$?
          [[ $c3_status_ec -ne 0 ]] && c3_status="MISSING"
          c3_manifest_hash=$(jq -r '.audit_report.input_manifest_hash // empty' "$c3_report_file" 2>/dev/null) || c3_manifest_hash_ec=$?
          [[ $c3_manifest_hash_ec -ne 0 ]] && c3_manifest_hash=""
          c3_head_sha=$(jq -r '.revision.head_sha // empty' "$c3_report_file" 2>/dev/null) || c3_head_sha_ec=$?
          [[ $c3_head_sha_ec -ne 0 ]] && c3_head_sha=""
          c3_current_head=$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo "")

          if [[ "$c3_blocking" != "false" && "$c3_blocking" != "true" ]]; then
            # Covers missing/null/non-boolean .audit_report.blocking_findings — fail-closed,
            # deliberately NOT `// false` (that is the exact anti-pattern this hook replaces).
            c3_block_reason="audit-report.json .audit_report.blocking_findings is missing or not a boolean (fail-closed)"
          elif [[ "$c3_blocking" == "true" ]]; then
            c3_block_reason="audit-report.json .audit_report.blocking_findings == true (critical/high finding present)"
          elif [[ "$c3_status" == "unverifiable" ]]; then
            c3_block_reason="audit-report.json .status == \"unverifiable\" (required independence level could not be confirmed)"
          elif [[ -z "$c3_manifest_hash" ]]; then
            c3_block_reason="audit-report.json missing .audit_report.input_manifest_hash (provenance fail-closed)"
          elif [[ -z "$c3_head_sha" || -z "$c3_current_head" || "$c3_head_sha" != "$c3_current_head" ]]; then
            c3_block_reason="audit-report.json .revision.head_sha (${c3_head_sha:-<empty>}) != current HEAD (${c3_current_head:-<empty>}) — stale audit (freshness fail-closed)"
          fi
        fi

        if [[ -n "$c3_block_reason" ]]; then
          # IMP-177 / E-059-1_2 Step 1 C3 activation: gate the block on the
          # resolved enforcement mode (c3_enforcement, read from c3-audit-policy.yaml
          # near the top of this branch). Always emit c3_gate_would_block telemetry
          # so the gate is observable whether or not it blocks; then:
          #   observe  → telemetry only, transition continues (staged wake, default)
          #   blocking → today's fail-closed behavior (counts toward errors → exit 1)
          log_event "$_c3_timeline" "c3_gate_would_block" \
            check="c3_independent_audit" enforcement="$c3_enforcement" \
            risk_profile="$c3_risk_profile" reason="$c3_block_reason"
          if [[ "$c3_enforcement" == "blocking" ]]; then
            echo "PRECONDITION FAIL: C3 independent audit block — ${c3_block_reason}." >&2
            echo "Risk profile '${c3_risk_profile}' requires a fresh, clean audit-report.json before release. See: ${c3_report_file}" >&2
            errors=$((errors + 1))
          else
            log_warn "C3 independent audit would_block (enforcement=observe, non-blocking): ${c3_block_reason}"
          fi
        fi
      fi

      # Block release on critical-severity findings via the auditor's CANONICAL top-level
      # `blocking_findings` field (agents/auditor.md: emitted as first line of the YAML,
      # E-046-1_3 Step 3 producer→consumer migration). yaml_field() matches only line-start
      # keys — indented/nested values and prose body lines are INVISIBLE, preventing the
      # old grep-ciE false-positive on negations ("No blocking_findings: true ...").
      # Fail-closed: absent field → field is indented/missing → cannot confirm clean → block.
      # E-057-1_2 Step 4: this legacy .md/.yaml read is SKIPPED when the C3 hook above
      # already fired (risk profile high/unverifiable) — audit-report.json is the single
      # source of truth for those profiles; this remains the only check for all others.
      if [[ "$c3_hook_fired" != "true" ]]; then
      local audit_file=""
      [[ -f "${evidence_dir}/audit-report.md" ]] && audit_file="${evidence_dir}/audit-report.md"
      [[ -f "${evidence_dir}/audit-report.yaml" ]] && audit_file="${evidence_dir}/audit-report.yaml"
      if [[ -n "$audit_file" ]]; then
        local blk
        blk=$(yaml_field "$audit_file" blocking_findings)
        if [[ -z "$blk" ]]; then
          echo "PRECONDITION FAIL: audit-report is missing canonical top-level 'blocking_findings' field (fail-closed)." >&2
          echo "Re-dispatch auditor so it emits 'blocking_findings: false' or 'true' at line start. See: $audit_file" >&2
          errors=$((errors + 1))
        elif [[ "$blk" != "false" ]]; then
          # Fail-closed on any non-false value: true, maybe, "true", comment, garbage.
          # Only exact scalar 'false' (after quote-stripping by yaml_field) is clean.
          echo "PRECONDITION FAIL: blocking_findings value '${blk}' is not 'false' — treating as blocking (fail-closed on any non-false value)." >&2
          echo "Address the finding or correct the field value. See: $audit_file" >&2
          errors=$((errors + 1))
        fi
        # blk == "false" → no blocking findings; passes silently.
      fi
      fi

      # ─── C4 release-decision dual-run hook (E-059-2_2 Step 5) ───────────────
      # Runs the C4 release aggregator (aid-release-policy.sh) HERE — after every
      # legacy check above, so `errors` is the COMPLETE legacy verdict — and logs
      # how the aggregator's release_ready compares to it. Observe-only by default
      # (release-decision-policy.yaml enforcement: observe → transition unaffected).
      #
      # HARD GUARANTEE: an aggregator crash MUST NOT abort done-advance. The call
      # uses the set -euo pipefail-safe `cmd || rc=$?` idiom (same as the aggregator's
      # own evidence-verify call), so a non-zero exit is caught and only logs
      # result=crash — the legacy `errors` tally alone then decides the transition.
      # NOTE: --force takes the sibling branch above (whole gauntlet skipped), so a
      # forced advance structurally NEVER reaches this hook / emits dual_run.
      local _c4_timeline="${evidence_dir}/timeline.jsonl"
      local _c4_head_sha _c4_legacy_errors="$errors" _c4_legacy_ready
      _c4_head_sha=$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo "unknown")
      [[ "$_c4_legacy_errors" -eq 0 ]] && _c4_legacy_ready="true" || _c4_legacy_ready="false"

      # Resolve enforcement (fail-safe observe). RELEASE_DECISION_POLICY = test/CI seam.
      local _rdp_enforcement="observe" _rdp_policy
      _rdp_policy="${RELEASE_DECISION_POLICY:-${SCRIPT_DIR}/../defaults/policies/release-decision-policy.yaml}"
      if [[ -f "$_rdp_policy" ]] && command -v yq >/dev/null 2>&1; then
        local _pol_rdp
        _pol_rdp=$(yq e '.enforcement // "observe"' "$_rdp_policy" 2>/dev/null || echo "observe")
        [[ "$_pol_rdp" == "blocking" ]] && _rdp_enforcement="blocking"
      fi

      # Run the aggregator GUARDED. AID_RELEASE_POLICY_BIN = test seam (default: shipped).
      local _c4_bin _c4_out _c4_rc=0
      _c4_bin="${AID_RELEASE_POLICY_BIN:-${SCRIPT_DIR}/aid-release-policy.sh}"
      _c4_out=$(AID_PROJECT_ROOT="$project_root" bash "$_c4_bin" "$epic_id" "$run_id" 2>&1) || _c4_rc=$?

      if [[ "$_c4_rc" -ne 0 ]]; then
        # Aggregator crashed → observe only, NEVER block (could not obtain a verdict).
        log_event "$_c4_timeline" "release_policy_dual_run" \
          result="crash" match="false" divergence_class="unclassified" \
          legacy_ready="$_c4_legacy_ready" enforcement="$_rdp_enforcement" \
          exit_code="$_c4_rc" head_sha="$_c4_head_sha"
      else
        local _c4_rd="${evidence_dir}/release-decision.json"
        local _c4_ready="unknown" _c4_bcount=0 _c4_blocker_ids=""
        if [[ -f "$_c4_rd" ]] && command -v jq >/dev/null 2>&1; then
          # Boolean-safe read: `.release_ready // "unknown"` is WRONG here — jq's //
          # treats a literal `false` as empty, so a false verdict would misread as
          # "unknown" (breaking match against a legacy false). Map the boolean explicitly.
          _c4_ready=$(jq -r 'if .release_decision.release_ready == true then "true"
                             elif .release_decision.release_ready == false then "false"
                             else "unknown" end' "$_c4_rd" 2>/dev/null || echo "unknown")
          _c4_bcount=$(jq -r '.release_decision.blockers | length' "$_c4_rd" 2>/dev/null || echo "0")
          _c4_blocker_ids=$(jq -r '.release_decision.blockers[]?.input_id' "$_c4_rd" 2>/dev/null || echo "")
        fi
        local _c4_match="false"
        [[ "$_c4_ready" == "$_c4_legacy_ready" ]] && _c4_match="true"
        local _c4_divclass
        _c4_divclass=$(_c4_divergence_class "$_c4_match" "$_c4_ready" "$_c4_bcount" "$_c4_blocker_ids")

        log_event "$_c4_timeline" "release_policy_dual_run" \
          result="compared" match="$_c4_match" divergence_class="$_c4_divclass" \
          legacy_ready="$_c4_legacy_ready" c4_release_ready="$_c4_ready" \
          legacy_errors="$_c4_legacy_errors" blocker_count="$_c4_bcount" \
          enforcement="$_rdp_enforcement" head_sha="$_c4_head_sha"

        # E-060-2_2 Step 8 (contract 5): per-input at-HEAD telemetry. The aggregator is a pure,
        # side-effect-free deterministic producer (no log_event) — the FSM dual-run hook is the
        # NAMED emitter. After reading release-decision.json, emit one c4_head_match_divergence
        # per head_match==false input (a stale artifact that must not look usable), and one
        # c4_head_match_unknown per unknown-basis gating input (uncomputable at-HEAD — surfaced
        # so it is never a silent true). Best-effort telemetry: never affects the transition.
        if [[ -f "$_c4_rd" ]] && command -v jq >/dev/null 2>&1; then
          local _hm_id _hm_val
          while IFS=$'\t' read -r _hm_id _hm_val; do
            [[ -z "$_hm_id" ]] && continue
            if [[ "$_hm_val" == "false" ]]; then
              log_event "$_c4_timeline" "c4_head_match_divergence" \
                input_id="$_hm_id" head_match="false" head_sha="$_c4_head_sha" \
                enforcement="$_rdp_enforcement"
            else
              log_event "$_c4_timeline" "c4_head_match_unknown" \
                input_id="$_hm_id" head_match="unknown" head_sha="$_c4_head_sha" \
                enforcement="$_rdp_enforcement"
            fi
          done < <(jq -r '
            .release_decision.inputs[]?
            | select( (.head_match == false)
                      or (.head_match == "unknown" and .verdict != "advisory" and .verdict != "not_applicable") )
            | [.id, (if .head_match == false then "false" else "unknown" end)] | @tsv' \
            "$_c4_rd" 2>/dev/null)
        fi

        # Divergence → alert (AID_TEST_MODE suppresses the real send inside try_telegram_alert).
        if [[ "$_c4_match" == "false" ]]; then
          try_telegram_alert "⚖️ ${epic_id}: C4 dual-run divergence (class=${_c4_divclass}, legacy_ready=${_c4_legacy_ready}, c4_ready=${_c4_ready}) — observe-mode telemetry."
        fi

        # Enforcement: observe → transition unaffected; blocking → a C4 false stops it.
        if [[ "$_rdp_enforcement" == "blocking" && "$_c4_ready" == "false" ]]; then
          echo "PRECONDITION FAIL: C4 release aggregator release_ready=false (enforcement=blocking)." >&2
          echo "See ${_c4_rd} for the blocker list, or override with --force (PM-authorized, audited)." >&2
          errors=$((errors + 1))
        fi
      fi
      # ─── End C4 dual-run hook ───────────────────────────────────────────────

      if [[ $errors -gt 0 ]]; then
        local timeline
        timeline=$(derive_timeline "$state_file") || true
        [[ -n "$timeline" ]] && log_event "$timeline" "fsm_done_advance_fail" from_phase="$from_phase" to_phase="$to_phase" errors="$errors"
        echo "ERROR: ${errors} precondition(s) failed for done-advance $from_phase → $to_phase." >&2
        exit 1
      fi
    fi
  fi

  # Advance phase
  sed -i "s/^done_phase: .*/done_phase: ${to_phase}/" "$state_file"

  # P032 Step 4 (PM-authorized C4): write compliance.json after sed updates
  # done_phase=release. evaluate_compliance_checks reads post-enforcement
  # fsm-state.yaml.branch (set by Step 2 cmd_init) and the gate runner's
  # provenance fields (set by Step 3 aid-run-gates.sh). Hook is best-effort
  # — failures inside write_compliance_json log_warn but never abort the
  # release path.
  if [[ "$to_phase" == "release" ]]; then
    local epic_id run_id evidence_dir project_root
    epic_id=$(yaml_field "$state_file" epic_id)
    run_id=$(yaml_field "$state_file" run_id)
    evidence_dir=".aid-o/work/evidence/${epic_id}/${run_id}"
    project_root="$PWD"
    write_compliance_json "$epic_id" "$run_id" "$state_file" "$evidence_dir" "$project_root"

    # IMP-090: best-effort epic-summary.md generation after compliance write.
    # Failure logs a warning but never aborts the release path.
    bash "$SCRIPT_DIR/aid-epic-summary.sh" generate "$evidence_dir" \
      2>/dev/null || log_warn "epic-summary.md generation failed (non-fatal)"
  fi

  # Audit trail
  local timeline
  timeline=$(derive_timeline "$state_file") || true
  [[ -n "$timeline" ]] && log_event "$timeline" "fsm_done_advance" from_phase="$from_phase" to_phase="$to_phase"

  echo "Done phase: $from_phase → $to_phase" >&2
}

# ─── Severity promotion (P038 Step 4) ───────────────────────────────────
# Closes the loop on AID-v3-principles.md §1 tiered-severity caveat:
# advisory checks may be promoted to blocking once they demonstrate clean
# operation. `promote-check` is the auditable mutator (writes the registry
# + appends a check_promoted audit-log event). `check-promotion-candidates`
# is the read-only observer (deterministic table; PM judgment input).
# Both touch project-level state (.aid-o/config/check-severity.yaml +
# .aid-o/work/audit-log.jsonl) — NOT FSM state.

# Promote a check from advisory → blocking severity.
# Writes .aid-o/config/check-severity.yaml in place via `yq -i`, appends a
# check_promoted event to audit-log.jsonl. Exits 0 if already blocking
# (idempotent). Requires --reason flag with min 20 characters.
cmd_promote_check() {
  local check_name="${1:-}" flag="${2:-}" reason="${3:-}"

  [[ -z "$check_name" ]] && {
    echo "Usage: aid-fsm.sh promote-check <check_name> --reason '<text ≥20 chars>'" >&2
    exit 1
  }
  [[ "$flag" != "--reason" ]] && {
    echo "ERROR: missing --reason flag" >&2
    exit 1
  }
  [[ ${#reason} -lt 20 ]] && {
    echo "ERROR: --reason must be ≥20 characters (got ${#reason})" >&2
    exit 2
  }

  # Validate check_name against alphanumeric+underscore pattern (defense in depth).
  # Registry keys must be stable identifiers; reject path traversal or shell metacharacters.
  [[ "$check_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
    echo "ERROR: check_name must match ^[a-zA-Z_][a-zA-Z0-9_]*$ (got '$check_name')" >&2
    exit 1
  }

  local project_root="$PWD"
  local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"

  [[ -f "$severity_yaml" ]] || {
    echo "ERROR: $severity_yaml not found — run /aid-init upgrade first" >&2
    exit 1
  }
  command -v yq >/dev/null 2>&1 || {
    echo "ERROR: yq required for promote-check" >&2
    exit 1
  }

  # Escape reason for safe yq interpolation: replace backslash, double-quote, newline.
  # P038 CP3 security finding CRITICAL-1: Prevent yq expression injection via --reason.
  # check_name is already validated against ^[a-zA-Z_][a-zA-Z0-9_]*$, so safe for interpolation.
  local reason_escaped="${reason//\\/\\\\}"  # Escape backslash first
  reason_escaped="${reason_escaped//\"/\\\"}"  # Escape double-quote
  reason_escaped="${reason_escaped//$'\n'/\\n}"  # Escape newline

  local exists
  exists=$(yq -r ".checks | has(\"${check_name}\")" "$severity_yaml" 2>/dev/null || echo "false")
  [[ "$exists" == "true" ]] || {
    echo "ERROR: check '${check_name}' not in registry. Add to ${severity_yaml} first." >&2
    exit 1
  }

  local previous_severity today
  previous_severity=$(yq -r ".checks.${check_name}.severity" "$severity_yaml" 2>/dev/null || echo "advisory")
  today=$(date -u +%Y-%m-%d)

  if [[ "$previous_severity" == "blocking" ]]; then
    local already_at
    already_at=$(yq -r ".checks.${check_name}.promoted_at // \"unknown\"" "$severity_yaml" 2>/dev/null || echo "unknown")
    echo "INFO: ${check_name} is already severity:blocking (promoted_at: ${already_at})" >&2
    exit 0
  fi

  # Update registry with escaped reason.
  # TOCTOU note (MEDIUM-1): yq -i is not atomic; concurrent promote-check invocations
  # on the same check can race. Mitigate via single-operator convention + audit-log.
  # Future: wrap under flock(3) on severity.yaml.lock if multi-operator concurrency required.
  yq -i ".checks.${check_name}.severity = \"blocking\" |
         .checks.${check_name}.promoted_at = \"${today}\" |
         .checks.${check_name}.promoted_reason = \"${reason_escaped}\"" "$severity_yaml" || {
    echo "ERROR: yq write to ${severity_yaml} failed" >&2
    exit 1
  }

  local operator="${USER:-unknown}"
  fsm_emit_audit_log "check_promoted" \
    --check "$check_name" \
    --previous-severity "$previous_severity" \
    --new-severity "blocking" \
    --reason "$reason" \
    --operator "$operator"

  echo "Promoted: ${check_name} severity ${previous_severity} → blocking (reason logged to audit-log.jsonl)" >&2
}

# Scan audit-log.jsonl + compliance.json across EPICs to identify advisory
# checks that meet the AID-v3-principles.md §1 promotion criterion:
#   epic_count >= 5 AND force_override_rate < 0.05
# Read-only: prints a text table. PM eyes-on input for `promote-check`.
cmd_check_promotion_candidates() {
  local project_root="$PWD"
  local severity_yaml="${project_root}/.aid-o/config/check-severity.yaml"
  local audit_log="${project_root}/.aid-o/work/audit-log.jsonl"

  [[ -f "$severity_yaml" ]] || {
    echo "ERROR: $severity_yaml not found" >&2
    exit 0
  }

  command -v yq >/dev/null 2>&1 || {
    echo "ERROR: yq required" >&2
    exit 0
  }
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq required" >&2
    exit 0
  }

  local advisory_checks
  advisory_checks=$(yq -r '.checks | to_entries | map(select(.value.severity == "advisory")) | .[].key' "$severity_yaml" 2>/dev/null || true)

  printf "%-40s %12s %16s %8s %s\n" "check" "epic_count" "override_count" "rate" "candidate"
  printf "%-40s %12s %16s %8s %s\n" "----------------------------------------" "------------" "----------------" "--------" "---------"

  if [[ -z "$advisory_checks" ]]; then
    echo
    echo "(no advisory checks in registry — nothing to evaluate)"
    echo
    echo "Promotion criterion: epic_count >= 5 AND rate < 0.05 (per AID-v3-principles.md §1)"
    echo "To promote: aid-fsm.sh promote-check <name> --reason '<text ≥20 chars>'"
    return 0
  fi

  while IFS= read -r check; do
    [[ -z "$check" ]] && continue

    # epic_count = distinct EPICs whose compliance.json failures[] contains $check
    local epic_count=0
    if [[ -d ".aid-o/work/evidence" ]]; then
      epic_count=$(find .aid-o/work/evidence -maxdepth 3 -name 'compliance.json' 2>/dev/null \
        | while read -r f; do
            jq -r --arg c "$check" 'select((.failures // []) | map(.check) | index($c)) | .epic_id // empty' "$f" 2>/dev/null || true
          done \
        | sort -u | grep -c -v '^$' || true)
      epic_count="${epic_count:-0}"
    fi

    # override_count = audit-log.jsonl entries with event=fsm_force_override AND blocked_checks contains $check
    local override_count=0
    if [[ -f "$audit_log" ]]; then
      override_count=$(jq -s --arg c "$check" '[.[] | select(.event == "fsm_force_override" and ((.blocked_checks // []) | index($c)))] | length' "$audit_log" 2>/dev/null || echo "0")
      override_count="${override_count:-0}"
    fi

    local rate="0.00"
    local candidate="no"
    if [[ "$epic_count" -ge 5 ]]; then
      rate=$(awk -v o="$override_count" -v e="$epic_count" 'BEGIN { printf "%.2f", o/e }')
      if awk -v r="$rate" 'BEGIN { exit !(r < 0.05) }'; then
        candidate="yes"
      fi
    fi

    printf "%-40s %12s %16s %8s %s\n" "$check" "$epic_count" "$override_count" "$rate" "$candidate"
  done <<< "$advisory_checks"

  echo
  echo "Promotion criterion: epic_count >= 5 AND rate < 0.05 (per AID-v3-principles.md §1)"
  echo "To promote: aid-fsm.sh promote-check <name> --reason '<text ≥20 chars>'"
}

# ─── plan-close ─────────────────────────────────────────────────────────
# Verify all required CA reports are present, then write ca-review-complete.
# simplifier-report.md is skipped when simplifier.enabled:false in execution.yaml.
# delivery-report.md  is skipped when reporter.enabled:false  in execution.yaml.
# Skips are logged to audit-log.jsonl with rationale.
# Usage: aid-fsm.sh plan-close <epic_id> <evidence_dir> <project_root>
cmd_plan_close() {
  local epic_id="${1:-}"
  local evidence_dir="${2:-}"
  local project_root="${3:-}"

  [[ -z "$epic_id" ]]       && echo "Missing: epic_id"       >&2 && exit 1
  [[ -z "$evidence_dir" ]]  && echo "Missing: evidence_dir"  >&2 && exit 1
  [[ -z "$project_root" ]]  && echo "Missing: project_root"  >&2 && exit 1

  # Derive plan_id: strip trailing _N run suffix, extract first NNN digit block after E-
  # E-046-2_3 -> stripped=E-046-2 -> nnn=046 -> plan_id=P046
  # E-013-1   -> stripped=E-013-1 -> nnn=013 -> plan_id=P013
  local stripped="${epic_id%%_*}"           # remove _N suffix if present
  local nnn
  nnn=$(echo "$stripped" | grep -oP '(?<=^E-)\d+')
  local plan_id="P${nnn}"

  # Read execution.yaml toggles — grep-only, no yq dependency.
  local exec_yaml="${project_root}/.aid-o/config/execution.yaml"
  local simplifier_enabled=true
  local reporter_enabled=true
  _aid_read_toggle "$exec_yaml" "simplifier" || simplifier_enabled=false
  _aid_read_toggle "$exec_yaml" "reporter" || reporter_enabled=false

  local audit_log="${project_root}/.aid-o/work/audit-log.jsonl"

  local curator_report="${evidence_dir}/curator-report.md"
  local audit_report="${evidence_dir}/audit-report.md"
  local simplifier_report="${evidence_dir}/simplifier-report.md"
  local delivery_report="${project_root}/.aid-o/reports/${plan_id}-delivery.md"

  # Helper: emit standard missing-report error message.
  local _fail_missing
  _fail_missing() {
    echo "PRECONDITION FAIL: required report not found: $1" >&2
    echo "Use 'aid-fsm.sh plan-close' — do NOT create this marker with touch." >&2
    missing=1
  }

  # Always-required reports (no toggle).
  local missing=0
  for required_file in "$curator_report" "$audit_report"; do
    if [[ ! -f "$required_file" ]]; then
      _fail_missing "$required_file"
    fi
  done

  # simplifier-report: required unless simplifier.enabled:false.
  if [[ "$simplifier_enabled" == "false" ]]; then
    log_event "$audit_log" "plan_close_skip" specialist="simplifier" rationale="simplifier.enabled:false in execution.yaml"
  else
    if [[ ! -f "$simplifier_report" ]]; then
      _fail_missing "$simplifier_report"
    fi
  fi

  # delivery-report: required unless reporter.enabled:false.
  if [[ "$reporter_enabled" == "false" ]]; then
    log_event "$audit_log" "plan_close_skip" specialist="reporter" rationale="reporter.enabled:false in execution.yaml"
  else
    if [[ ! -f "$delivery_report" ]]; then
      _fail_missing "$delivery_report"
    fi
  fi

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi

  touch "${evidence_dir}/ca-review-complete"
}

# ─── Queue Dependency Revalidation (P060 Step 7) ─────────────────────────
# OBS-20260709-06: a stale "awaiting merge" flag held a dependent EPIC blocked
# after its dependency had actually merged (and its task branch was deleted —
# the NORM). A human had to catch the false-BLOCK. This is the dual of the
# bookkeeping-staleness class: a stale record producing a false NEGATIVE.
#
# The fix revalidates a queue entry's `depends_on` (the REAL schema field —
# epic IDs, NOT a non-existent `blocked_on`) against LIVE git at start, with a
# 4-output contract per dep (D8):
#   1. dep branch exists + is-ancestor of main/HEAD → unblock
#   2. dep branch exists + NOT ancestor            → blocked (correct)
#   3. dep branch DELETED after merge (the norm)   → merged-detection fallback
#   4. no signal at all                            → fail-loud
#
# New read path: aid-fsm.sh did not read the queue before this (cmd_init only
# excluded queue.yaml from its dirty-tree guard). Registry: queue_dep_revalidation.

# _queue_parse_to_json <file> — awk parser copied from aid-queue-add.sh
# (lines ~104-211). The live dogfood .aid-o/config/queue.yaml is NOT
# yq-parseable (mixed indentation: a top-level `- epic_id:` list with 2-space
# keys, interleaved with a 4-space quoted block). This awk handles both the
# inline `depends_on: ["E-xxx"]` and the multi-line YAML-list form, and emits a
# JSON array of {epic_id,status,depends_on}. Invalid JSON out (jq -e fails) =
# unparseable queue → the caller fail-louds with queue_parse_failed.
_queue_parse_to_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[]"
    return
  fi

  awk '
    function close_entry() {
      if (!in_entry) return
      if (in_depends && !depends_closed) {
        if (dep_count > 0) printf "]"
        else printf "[]"
      }
      printf "}"
    }

    BEGIN {
      entry_count = 0
      in_entry = 0
      in_depends = 0
      depends_closed = 0
      dep_count = 0
      printf "["
    }

    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }

    /^[[:space:]]*-[[:space:]]+epic_id:/ {
      close_entry()
      in_entry = 1
      in_depends = 0
      depends_closed = 0
      dep_count = 0
      entry_count++
      if (entry_count > 1) printf ","

      val = $0
      sub(/^[[:space:]]*-[[:space:]]+epic_id:[[:space:]]*/, "", val)
      gsub(/"/, "", val)
      sub(/[[:space:]]*$/, "", val)
      printf "{\"epic_id\":\"%s\"", val
      next
    }

    in_entry && /^[[:space:]]+[a-z_]+:/ {
      if (in_depends && !depends_closed) {
        if (dep_count > 0) printf "]"
        else printf "[]"
        depends_closed = 1
      }
      in_depends = 0

      line = $0
      sub(/^[[:space:]]+/, "", line)

      colon_pos = index(line, ":")
      key = substr(line, 1, colon_pos - 1)
      val = substr(line, colon_pos + 1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      gsub(/"/, "", val)

      if (key == "status") {
        printf ",\"status\":\"%s\"", val
      } else if (key == "depends_on") {
        printf ",\"depends_on\":"
        in_depends = 1
        depends_closed = 0
        dep_count = 0

        if (val ~ /\[/) {
          inner = val
          gsub(/[\[\]]/, "", inner)
          gsub(/"/, "", inner)
          sub(/^[[:space:]]+/, "", inner)
          sub(/[[:space:]]+$/, "", inner)
          if (inner == "") {
            printf "[]"
          } else {
            printf "["
            n = split(inner, items, ",")
            for (i = 1; i <= n; i++) {
              sub(/^[[:space:]]+/, "", items[i])
              sub(/[[:space:]]+$/, "", items[i])
              if (items[i] != "") {
                if (dep_count > 0) printf ","
                printf "\"%s\"", items[i]
                dep_count++
              }
            }
            printf "]"
          }
          depends_closed = 1
          in_depends = 0
        }
      }
      next
    }

    in_entry && in_depends && !depends_closed && /^[[:space:]]*-[[:space:]]/ {
      val = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", val)
      gsub(/"/, "", val)
      sub(/[[:space:]]*$/, "", val)
      if (dep_count == 0) printf "["
      if (dep_count > 0) printf ","
      printf "\"%s\"", val
      dep_count++
      next
    }

    END {
      close_entry()
      printf "]"
    }
  ' "$file"
}

# _queue_merge_target — echo the ref the dep branch should be an ancestor of.
# Prefers main, then master, else HEAD (detached/CI checkout).
_queue_merge_target() {
  if git show-ref --verify --quiet refs/heads/main; then echo main
  elif git show-ref --verify --quiet refs/heads/master; then echo master
  else echo HEAD; fi
}

# _dep_evidence_state <dep> — echo "DONE" if ANY of the dep's evidence runs is
# state: DONE, else the last-seen state, else empty. Never fails (find on a
# missing dir yields nothing).
_dep_evidence_state() {
  local dep="$1" f st found=""
  while IFS= read -r f; do
    st=$(yaml_field "$f" state)
    if [[ "$st" == "DONE" ]]; then echo "DONE"; return 0; fi
    [[ -z "$found" && -n "$st" ]] && found="$st"
  done < <(find ".aid-o/work/evidence/${dep}" -name fsm-state.yaml 2>/dev/null)
  echo "$found"
}

# _dep_evidence_branch <dep> — echo the branch field from the dep's first
# evidence fsm-state (D8 fallback for a dep whose branch did not follow the
# task/<id>/main convention). Empty when no evidence.
_dep_evidence_branch() {
  local dep="$1" f br
  while IFS= read -r f; do
    br=$(yaml_field "$f" branch)
    [[ -n "$br" ]] && { echo "$br"; return 0; }
  done < <(find ".aid-o/work/evidence/${dep}" -name fsm-state.yaml 2>/dev/null)
  echo ""
}

# _resolve_dep_branch <dep> — echo the LIVE branch to ancestor-check for a dep:
# the task/<dep>/main convention if it exists, else the evidence fsm-state
# branch field if that ref exists (never main/master — a legacy branch:main
# would false-unblock). Empty = branch deleted (merged-detection path).
_resolve_dep_branch() {
  local dep="$1"
  local conv="task/${dep}/main"
  if git show-ref --verify --quiet "refs/heads/${conv}"; then echo "$conv"; return 0; fi
  local ev; ev=$(_dep_evidence_branch "$dep")
  if [[ -n "$ev" && "$ev" != "main" && "$ev" != "master" ]] \
     && git show-ref --verify --quiet "refs/heads/${ev}"; then
    echo "$ev"; return 0
  fi
  echo ""; return 0
}

# _revalidate_one_dep <dep> <queue_json> <timeline_path>
# Implements the D8 4-output contract for a single dependency. Echoes exactly
# one of: unblocked | blocked | failed. Emits the corresponding timeline event.
# All git calls use the rc-capture pattern so a raw git fatal (128) NEVER
# aborts under `set -e` — it falls through to merged-detection.
_revalidate_one_dep() {
  local dep="$1" queue_json="$2" timeline_path="$3"
  local target; target=$(_queue_merge_target)
  local branch; branch=$(_resolve_dep_branch "$dep")

  if [[ -n "$branch" ]]; then
    local rc=0
    git merge-base --is-ancestor "$branch" "$target" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0)  # output 1: branch exists + is ancestor → merged → unblock
        log_event "$timeline_path" "queue_dep_revalidated" \
          epic_id="$dep" resolution="ancestor" branch="$branch"
        echo "unblocked"; return 0 ;;
      1)  # output 2: branch exists + NOT ancestor → genuinely unmerged → blocked
        log_event "$timeline_path" "queue_dep_blocked" \
          epic_id="$dep" branch="$branch"
        echo "blocked"; return 0 ;;
      *)  # 128 = bad-ref/fatal → do NOT crash; fall through to merged-detection
        : ;;
    esac
  fi

  # output 3: branch deleted after merge (the NORM) → merged-detection fallback.
  # Unblock if ANY signal says the dep is done.
  local qstatus
  qstatus=$(echo "$queue_json" | jq -r --arg d "$dep" \
    '[.[] | select(.epic_id==$d) | .status] | .[0] // ""' 2>/dev/null)
  if [[ "$qstatus" == "completed" ]]; then
    log_event "$timeline_path" "queue_dep_revalidated" \
      epic_id="$dep" resolution="merged_completed"
    echo "unblocked"; return 0
  fi

  local evstate; evstate=$(_dep_evidence_state "$dep")
  if [[ "$evstate" == "DONE" ]]; then
    log_event "$timeline_path" "queue_dep_revalidated" \
      epic_id="$dep" resolution="merged_done"
    echo "unblocked"; return 0
  fi

  # P060 per-plan C+A: anchor the epic_id so a hierarchical sibling can't false-unblock
  # (bare --grep="E-016-1" substring-matched "E-016-1_3"). -E with non-[alnum_] boundaries
  # requires the id to appear as a whole token; epic_ids are controller-authored `E-<digits>...`
  # (no regex metacharacters but `-`, which is literal in ERE), so this is safe from injection.
  local hits _dep_re="(^|[^[:alnum:]_])${dep}([^[:alnum:]_]|\$)"
  hits=$(git log --merges -E --grep="$_dep_re" "$target" --oneline 2>/dev/null | head -1 || true)
  if [[ -n "$hits" ]]; then
    log_event "$timeline_path" "queue_dep_revalidated" \
      epic_id="$dep" resolution="merged_log"
    echo "unblocked"; return 0
  fi

  # output 4: no signal at all → fail-loud
  log_event "$timeline_path" "queue_dep_unresolved" epic_id="$dep"
  echo "failed"; return 1
}

# queue_revalidate <epic_id> [queue_file] [timeline_path]
# Revalidate one queue entry's depends_on against live git. Echoes the overall
# revalidated status: unblocked | blocked | failed | noop.
#   - failed if ANY dep is unresolved (fail-loud) — return 1
#   - blocked if ANY dep is genuinely unmerged (and none failed)
#   - unblocked if all deps are merged
#   - noop (no event) for: missing queue, no entry for this epic, or no deps
# Missing-queue / no-entry are NEVER fail-loud (D8): they are a clean no-op.
queue_revalidate() {
  local epic_id="$1"
  local queue_file="${2:-.aid-o/config/queue.yaml}"
  local timeline_path="${3:-.aid-o/work/evidence/${epic_id}/queue-revalidate.jsonl}"

  # scenario f: missing queue file → no-op, no event
  [[ -f "$queue_file" ]] || { echo "noop"; return 0; }

  local queue_json
  queue_json=$(_queue_parse_to_json "$queue_file")
  if ! echo "$queue_json" | jq -e . >/dev/null 2>&1; then
    # scenario e: unparseable queue → fail-loud
    mkdir -p "$(dirname "$timeline_path")"
    log_event "$timeline_path" "queue_parse_failed" queue_file="$queue_file" epic_id="$epic_id"
    echo "failed"; return 1
  fi

  # scenario f: no entry for this epic → no-op, no event
  local present
  present=$(echo "$queue_json" | jq -r --arg e "$epic_id" '[.[] | select(.epic_id==$e)] | length')
  [[ "${present:-0}" -gt 0 ]] || { echo "noop"; return 0; }

  # no depends_on → nothing to revalidate → no-op, no event
  local deps
  deps=$(echo "$queue_json" | jq -r --arg e "$epic_id" \
    '.[] | select(.epic_id==$e) | (.depends_on // []) | .[]' 2>/dev/null)
  [[ -n "$deps" ]] || { echo "noop"; return 0; }

  mkdir -p "$(dirname "$timeline_path")"

  local overall="unblocked" dep res
  while IFS= read -r dep; do
    [[ -n "$dep" ]] || continue
    res=$(_revalidate_one_dep "$dep" "$queue_json" "$timeline_path") || true
    case "$res" in
      failed)    overall="failed"; break ;;
      blocked)   [[ "$overall" != "failed" ]] && overall="blocked" ;;
      unblocked) : ;;
    esac
  done <<< "$deps"

  echo "$overall"
  [[ "$overall" == "failed" ]] && return 1
  return 0
}

# cmd_queue_revalidate — dispatch entrypoint: `aid-fsm.sh queue-revalidate <epic_id>`
# Callable standalone by consumers (pipeline.md §12 queue pickup, /aid-run
# pre-start) BEFORE respecting a blocked queue status. Prints the revalidated
# status to stdout; exit 1 on fail-loud (unresolved dep / unparseable queue).
cmd_queue_revalidate() {
  local epic_id="${1:?Usage: aid-fsm.sh queue-revalidate <epic_id> [queue_file] [timeline_path]}"
  shift
  queue_revalidate "$epic_id" "$@"
}

# ─── Dispatch ───────────────────────────────────────────────────────────
# BASH_SOURCE guard (v2.20.2 — IMP-followup, same pattern as aid-stage-log.sh:78):
# only dispatch when invoked directly (`bash aid-fsm.sh <cmd>`). When sourced
# (`source aid-fsm.sh`), skip the case so test fixtures (e.g. test-anti-
# fabrication.bats `_load_aid_fsm` shim) can pull in cmd_* + verify_provenance
# functions without the unknown-arg exit 1 killing the test process.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    init)              shift; cmd_init "$@" ;;
    transition)        shift; cmd_transition "$@" ;;
    advance-to-gates)  shift; cmd_advance_to_gates "$@" ;;
    get-state)         shift; cmd_get_state "$@" ;;
    verify-state)      shift; cmd_verify_state "$@" ;;
    increment-step)    shift; cmd_increment_step "$@" ;;
    get-field)         shift; cmd_get_field "$@" ;;
    set-field)         shift; cmd_set_field "$@" ;;
    done-advance)               shift; cmd_done_advance "$@" ;;
    promote-check)              shift; cmd_promote_check "$@" ;;
    check-promotion-candidates) shift; cmd_check_promotion_candidates "$@" ;;
    plan-close)                 shift; cmd_plan_close "$@" ;;
    queue-revalidate)           shift; cmd_queue_revalidate "$@" ;;
    *)
      echo "Usage: aid-fsm.sh <init|transition|advance-to-gates|get-state|verify-state|increment-step|get-field|set-field|done-advance|promote-check|check-promotion-candidates|plan-close|queue-revalidate> [args...]" >&2
      exit 1 ;;
  esac
fi
