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
# Shared gate-profile risk-classification resolver (P061 E2 Step 1) — defines
# gate_profile_resolve / gate_profile_rank / gate_profile_max. Used by both
# cmd_advance_to_gates (auto-resolve, this EPIC's Step 2 / "Step 8") and the
# GATES:DONE risk-upgrade precondition below (D4 enforcement, not advisory).
source "${SCRIPT_DIR}/lib/aid-gate-profile.sh"
source "${SCRIPT_DIR}/lib/aid-lifecycle.sh"  # IMP-232 v2.58.0 — canonical plan-level closure + D1 cross-plan gate
# P064 E-064-1_2 Step 5 — plan-boundary-manifest reader (plan_manifest_path/
# plan_manifest_get), for the new init-time plan-branch lineage precondition
# below. Guarded (existence check + `|| true` on the source itself) rather
# than an unconditional source: a missing/broken lib must NEVER abort this
# entire CLI for every EPIC — only the new precondition's own runtime check
# (`declare -F plan_manifest_path`) fails closed, and ONLY for plan_branch-
# mode plans. Legacy-mode / no-manifest plans must stay unaffected even if
# this file is absent.
if [[ -f "${SCRIPT_DIR}/lib/aid-plan-manifest.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/aid-plan-manifest.sh" || true
fi

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

# ─── epic-id -> plan-id digits (ONE derivation, portable) ───────────────────
# _fsm_epic_plan_nnn <epic_id> — echoes the NNN digit block of an EPIC id
# ("E-064-2_2" -> "064"), or nothing for an ad-hoc id with no digits after
# "E-" (e.g. "E-test"). Always exits 0, so every caller can stay `set -e` safe
# without an `|| true` dance.
#
# WHY NOT `grep -oP` (CP3 integration review, "also fix while you are here").
# Every call site used to spell this as
# `printf '%s' "${id%%_*}" | grep -oP '(?<=^E-)\d+'`. `-P` is a GNU-grep build
# option: on a grep without PCRE support (BusyBox, macOS/BSD grep, a minimal
# container image) it does not "not match", it FAILS — and because the two mode
# helpers swallowed that with `|| true`, three controls (the gate-profile cap,
# the release-mode block, cmd_init's lineage precondition) silently degraded to
# their legacy/no-op branch on a host where no EPIC id could ever derive a plan.
# A bash-native match has no external dependency to probe at all.
_fsm_epic_plan_nnn() {
  local id="${1:-}"
  id="${id%%_*}"
  [[ "$id" =~ ^E-([0-9]+) ]] || return 0
  printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

# ─── Gate-profile boundary selector (P064 plan Step 8) ──────────────────────
# _fsm_gate_profile_boundary <epic_id> — echoes the `boundary` positional to
# hand gate_profile_resolve for THIS EPIC: "epic" when the EPIC belongs to a
# plan whose DECLARED release model is `plan_branch`, "" (legacy, byte-identical
# to pre-Step-8 behaviour) otherwise. Always exits 0 — this is a routing
# decision, never an enforcement point.
#
# WHY MODE-GATED. boundary=epic caps the resolved profile at `standard`,
# which is only safe because a plan_branch plan has a plan-final run that
# still executes the accumulated floor (recorded by `aid-plan-fsm.sh
# epic-complete`, consumed by the plan-final stage). A legacy
# `legacy_epic_release_mode` plan has no such second run: capping there would
# silently drop `bats_all` and suppress the done_phase=release escalation
# with nothing downstream to make up for it — a coverage regression, not a
# split. Every "cannot tell" path therefore returns "" (no cap, more gates),
# the conservative direction — the opposite of cmd_init's lineage check,
# which fails CLOSED because there "cannot tell" would skip a security proof.
#
# ── ONE AUTHORITY (CP3 integration review finding 2, adjudicated action A3) ──
# This function computes NOTHING of its own: it asks `_fsm_declared_plan_mode`
# (below, the release-routing resolver) and maps its verdict. It USED to read
# the gitignored RUNTIME manifest `plan-boundary-manifest.json` while
# `_fsm_declared_plan_mode` read the git-tracked DECLARATION
# `.aid-lifecycle/manifests/<plan_id>.yaml` — two sources that go stale
# independently and could therefore disagree while BOTH returned a confident,
# non-error answer:
#   * runtime=plan_branch + declaration absent -> gates capped at `standard`
#     while the LEGACY release stack merged the EPIC into the target branch and
#     ran the bump/tag/push. A high-risk EPIC shipped with reduced verification,
#     and the accumulated floor was discarded (only `epic-complete` writes one,
#     and the legacy path never reaches it).
#   * an UNTRACKED declaration saying plan_branch confidently silenced all nine
#     AID_PLAN_BRANCH_SKIPPED_STAGES with nothing committed anywhere.
# The runtime manifest is no longer a mode input anywhere in this file. The two
# helpers still REACT differently to "cannot tell" — here "" (no cap => MORE
# gates), there a hard block — but that is a difference in CONSEQUENCE, chosen
# per call site, never a difference in the verdict.
#
# BOTH gate_profile_resolve call sites in this file MUST route through this
# one helper: advance-to-gates picks the profile a run executes and the
# GATES:DONE precondition recomputes the requirement it is measured against.
# If they disagreed, an EPIC that correctly ran the capped `standard` would
# be compared against an uncapped `full` and could never reach DONE.
_fsm_gate_profile_boundary() {
  local epic_id="${1:-}" _gb_mode="" _gb_plan="" _gb_reason=""
  # `|| true`: the read itself is never allowed to abort a routing decision.
  IFS=$'\t' read -r _gb_mode _gb_plan _gb_reason \
    < <(_fsm_declared_plan_mode "$epic_id") || true
  if [[ "$_gb_mode" == "plan_branch" ]]; then
    echo "epic"
  else
    # legacy_epic_release_mode AND every `unresolved` reason land here: no cap.
    echo ""
  fi
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

# active_run_pointer_path — canonical location of the single "which run
# currently governs main" pointer (OBS-20260712-01 hotfix). Consumed by
# defaults/hooks/pre-commit's commit-scope guard for its two main-fallback
# checks (EXECUTE/GATES rogue-commit block, DONE/release version whitelist)
# — a historical evidence directory must never act as an IMPLICIT pointer to
# "the" active run; this file is the only EXPLICIT one.
active_run_pointer_path() {
  echo ".aid-o/work/active-run-pointer.json"
}

# write_active_run_pointer <state_file> — (re)points the single active-run
# slot at this run. Called once, at the very end of cmd_init. Single global
# slot, always OVERWRITTEN by the next run's init — self-expiring by
# construction (a run superseded by a newer init can never re-emerge as "the"
# active run again, however long its own evidence directory survives on
# disk). Best-effort: a write failure here must never block init itself.
write_active_run_pointer() {
  local state_file="$1"
  local ptr; ptr=$(active_run_pointer_path)
  local epic_id run_id
  epic_id=$(yaml_field "$state_file" epic_id)
  run_id=$(yaml_field "$state_file" run_id)
  local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$(dirname "$ptr")" 2>/dev/null || true
  jq -n --arg sf "$state_file" --arg e "$epic_id" --arg r "$run_id" --arg t "$now" \
    '{state_file: $sf, epic_id: $e, run_id: $r, written_at: $t}' > "$ptr" 2>/dev/null || true
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

  # At init-time the arg-parse loop reaches --force BEFORE cmd_init mkdir's the
  # evidence dir, so without this the fsm_force_override timeline event would be
  # written into a nonexistent directory and silently lost (the audit-log +
  # waiver survive because they mkdir first). Best-effort; a mkdir failure never
  # aborts the force. For non-init callers (transition/increment/done-advance)
  # the dir already exists, so this is a harmless no-op.
  [[ -n "$timeline" ]] && mkdir -p "$(dirname "$timeline")" 2>/dev/null || true

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

        # IMP-270: gate-scoped waiver re-validation (defense in depth). ─────────
        # A gate row with result=="waived" was accepted by aid-run-gates.sh in
        # place of a pass. overall=="pass" alone is NOT sufficient proof — a
        # forged report could hand-write result:waived + overall:pass. So the
        # FSM re-validates EVERY waived row here, at read time, against the
        # report's own revision.head_sha: the row MUST carry a non-empty
        # waiver_ref AND aid-gate-waiver.sh check must return `valid` for the
        # exact (project, epic, run, HEAD, gate) tuple. The waiver is
        # single-use and was consumed by THIS run during the gate run, so check
        # accepts it as self-consumed evidence; a stale HEAD, a forged/tampered
        # waiver, a cross-run copy, or a missing waiver_ref each fail closed.
        # This waives exactly one gate's result — every OTHER precondition below
        # (plan-gate floor, risk profile, cp3 freshness) stays fully enforced.
        local waived_rows report_head
        report_head=$(jq -r '.revision.head_sha // empty' "$report" 2>/dev/null)
        waived_rows=$(jq -r '(.gates // {}) | to_entries[] | select(.value.result == "waived") | .key' "$report" 2>/dev/null)
        if [[ -n "$waived_rows" ]]; then
          # IMP-270 (PM review 2026-07-24): a waived row is re-validated against
          # the report's OWN revision.head_sha. If that is absent or not a 40-hex
          # sha, FAIL CLOSED here — do NOT pass an empty head to aid-gate-waiver.sh,
          # whose --head fallback would then resolve the CURRENT HEAD and validate
          # the waiver against whatever is checked out now, silently bypassing the
          # report's revision binding. A report that cannot name its reviewed
          # revision cannot have its waiver trusted.
          if [[ ! "$report_head" =~ ^[0-9a-f]{40}$ ]]; then
            _PRECONDITION_FAIL_REASON="waiver_report_head_missing"
            echo "PRECONDITION FAIL: report declares waived gate(s) but its .revision.head_sha is missing or not a 40-hex sha (got '${report_head:-<empty>}') — refusing to re-validate a waiver against an unbound revision (a missing report HEAD must not fall back to the current HEAD)." >&2
            return 1
          fi
          local waived_gate wv_ref wv_verdict wv_rc
          while IFS= read -r waived_gate; do
            [[ -z "$waived_gate" ]] && continue
            wv_ref=$(jq -r --arg g "$waived_gate" '.gates[$g].waiver_ref // empty' "$report" 2>/dev/null)
            if [[ -z "$wv_ref" ]]; then
              _PRECONDITION_FAIL_REASON="waived_row_no_ref"
              echo "PRECONDITION FAIL: gate '${waived_gate}' is reported result:waived but carries no waiver_ref — refusing to trust a bare waived row." >&2
              return 1
            fi
            wv_rc=0
            wv_verdict=$("${SCRIPT_DIR}/aid-gate-waiver.sh" check "$waived_gate" \
              --evidence-dir "$evidence_dir" --head "$report_head" \
              --epic "$epic_id" --run "$run_id" 2>/dev/null) || wv_rc=$?
            if [[ "$wv_rc" -ne 0 || "$wv_verdict" != "valid" ]]; then
              _PRECONDITION_FAIL_REASON="waiver_revalidation_failed"
              cat <<EOF >&2
PRECONDITION FAIL: waiver_revalidation_failed — gate '${waived_gate}' is reported result:waived, but its waiver did not re-validate (verdict: ${wv_verdict:-error}).

Reason: IMP-270 — a waived required gate is accepted only when its gate-scoped
        waiver still validates against the report's HEAD (${report_head:-<none>}). A
        moved HEAD, a tampered/forged waiver, a cross-run copy, or a missing
        waiver all fail closed here. A waiver waives exactly one gate — it never
        bypasses any other precondition.

Fix: re-issue a valid waiver for '${waived_gate}' at the current HEAD and re-run
     gates, or genuinely fix the gate so it passes. As a last resort a
     non-gate-scoped PM override remains:
  aid-fsm.sh transition GATES DONE ${state_file} --force --reason \\
      '<≥20 chars why bypassing every precondition is acceptable>'
EOF
              return 1
            fi
          done <<< "$waived_rows"
        fi

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

        # P061 E2 Step 2 ("Step 8"): risk-upgrade FSM enforcement (D4). ───────
        # plan_gate_floor (above) guards "did the plan's own required gates
        # survive the active profile". THIS check guards a different gap: the
        # active profile ITSELF (gates_report.json.profile, whatever --profile
        # aid-run-gates.sh was actually invoked with for this run) must be no
        # weaker than the RISK-REQUIRED profile the shared resolver (Step 1,
        # aid-gate-profile.sh) computes from this run's actual base_commit..HEAD
        # diff. Recomputed HERE (not trusted from advance-to-gates' earlier
        # auto-resolve) because the gates could have been (re-)run manually
        # with a different/weaker --profile after auto-resolve last ran —
        # trusting the resolver's own SUGGESTION at run-time would make this a
        # detector, not enforcement (AID-v3-principles.md §1). A missing
        # `profile` field means no --profile was ever passed for this run
        # (legacy execution.yaml without gate_profiles, or a project that
        # hasn't opted in) — D9: behaves exactly like today, no-op (every
        # defined gate already ran, nothing weaker to catch).
        #
        # P064 plan Step 8: the recompute is BOUNDARY-AWARE. It passes the
        # same boundary advance-to-gates used (via the single
        # _fsm_gate_profile_boundary helper), so an EPIC that correctly ran
        # the capped EPIC-boundary profile is compared against the
        # EPIC-boundary requirement — not against the unbounded plan-final
        # floor, which would hard-fail every high-risk EPIC at GATES:DONE.
        # The plan-final floor is recorded into the plan-boundary manifest by
        # `aid-plan-fsm.sh epic-complete`, not enforced at this transition.
        local active_profile
        active_profile=$(jq -r '.profile // empty' "$report" 2>/dev/null)
        if [[ -n "$active_profile" ]]; then
          local risk_base_commit required_profile="" _gp_boundary=""
          risk_base_commit=$(yaml_field "$state_file" base_commit)
          _gp_boundary="$(_fsm_gate_profile_boundary "$(yaml_field "$state_file" epic_id)")"
          if [[ -n "$risk_base_commit" ]]; then
            local _gp_paths_file
            _gp_paths_file=$(mktemp -t aid-gate-profile-risk.XXXXXX)
            git -C "$PWD" diff --name-only "${risk_base_commit}..HEAD" > "$_gp_paths_file" 2>/dev/null || true
            required_profile=$(gate_profile_resolve "$_gp_paths_file" "$state_file" "${evidence_dir}/review-profile.json" "$_gp_boundary")
            rm -f "$_gp_paths_file"
          fi
          # risk_base_commit empty (fsm-state unreadable/malformed) → required_profile
          # stays "" — conservative no-op, same fallback fsm_check_cp4_curator_validation
          # uses; we cannot prove a floor we cannot compute, never guess or fail loud on it.

          if [[ -n "$required_profile" ]]; then
            local active_rank required_rank
            if active_rank=$(gate_profile_rank "$active_profile" 2>/dev/null) \
               && required_rank=$(gate_profile_rank "$required_profile" 2>/dev/null); then
              if (( active_rank < required_rank )); then
                _PRECONDITION_FAIL_REASON="risk_profile_below_required"
                cat <<EOF >&2
PRECONDITION FAIL: risk_profile_below_required — active gate profile '${active_profile}' (rank ${active_rank}) is weaker than the risk-required profile '${required_profile}' (rank ${required_rank}) for this EPIC's actual diff (${risk_base_commit}..HEAD).

Reason: D4 (P061) — a high-risk changed path (e.g. aid-fsm.sh, aid-run-gates.sh,
        aid-release-policy.sh, aid-evidence-verify.sh, defaults/schemas/*,
        defaults/policies/*, agents/*.md) upgrades the REQUIRED gate profile
        for this run. This precondition VERIFIES and ENFORCES that floor at
        GATES:DONE — it does not just recommend it (a detector without
        enforcement is decoration, AID-v3-principles.md §1).

Fix: re-run gates so the recorded profile is >= '${required_profile}':
       bash \$AID_PLUGIN_PATH/scripts/aid-fsm.sh advance-to-gates ${state_file}
     (auto-resolves the risk-required profile for you), or explicitly:
       bash \$AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all ... --profile ${required_profile}

OR (PM-authorized override, audited):
  aid-fsm.sh transition GATES DONE ${state_file} --force --reason \\
      '<≥20 chars why completing under a weaker profile is acceptable>'
EOF
                return 1
              fi
            else
              # Active profile name isn't one of the 5 known ranks (a custom
              # project-defined gate_profiles key) — cannot compare, cannot
              # enforce. For high-risk diffs, this is a blocking failure
              # (fail-closed: we cannot verify the active profile is sufficient).
              # For low-risk diffs, non-blocking telemetry only.
              local req_rank
              if req_rank=$(gate_profile_rank "$required_profile" 2>/dev/null); then
                if (( req_rank > 0 )); then
                  # Required profile is above 'quick' (high-risk) — must fail
                  # because we cannot verify an unrecognized active profile meets it.
                  _PRECONDITION_FAIL_REASON="risk_profile_unresolvable"
                  cat <<EOF >&2
PRECONDITION FAIL: risk_profile_unresolvable — the recorded active gate profile '${active_profile}' is not recognized (not in the canonical profile ranks: quick/targeted/standard/full/release). The risk-required profile for this EPIC's diff is '${required_profile}' (rank ${req_rank}), which is above 'quick' — we cannot verify that an unrecognized profile name meets this requirement.

Reason: D4 (P061) — a high-risk changed path upgrades the REQUIRED gate profile
        for this run. This precondition VERIFIES and ENFORCES that floor at
        GATES:DONE — it does not just recommend it (a detector without
        enforcement is decoration, AID-v3-principles.md §1).

Fix: Either extend your execution.yaml.gate_profiles to define '${active_profile}' with a documented rank, or re-run gates with a recognized profile name:
       bash \$AID_PLUGIN_PATH/scripts/aid-run-gates.sh run-all ... --profile ${required_profile}

OR (PM-authorized override, audited):
  aid-fsm.sh transition GATES DONE ${state_file} --force --reason \\
      '<≥20 chars why using an unrecognized profile is acceptable>'
EOF
                  return 1
                else
                  # Required profile is 'quick' — low-risk, unrecognized active
                  # profile is acceptable. Non-blocking telemetry only.
                  fsm_emit_audit_log "risk_profile_rank_unresolvable" \
                    --evidence-dir "$evidence_dir" \
                    --active-profile "$active_profile" \
                    --required-profile "$required_profile"
                fi
              else
                # required_profile rank lookup itself failed — should not happen
                # (we computed required_profile ourselves from the resolver), but
                # fall back to non-blocking telemetry as a safety measure.
                fsm_emit_audit_log "risk_profile_rank_unresolvable" \
                  --evidence-dir "$evidence_dir" \
                  --active-profile "$active_profile" \
                  --required-profile "$required_profile"
              fi
            fi
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

    GATES:EXECUTE)
      # P063 Step 3: repeated-timeout policy block precondition. A gate that
      # aid-run-gates.sh's retry loop marked retryable:false (via
      # gate_baseline_mark_policy_block, after 3+ consecutive timeouts each
      # recorded at >= the currently-configured timeout_seconds — see
      # gate_baseline_policy_check in aid-gate-runtime-baseline.sh) has
      # nothing for gate-fixer to act on: the gate never got a chance to run
      # to completion, so re-entering EXECUTE to "fix" it is pointless.
      # Refuse the transition so the orchestrator routes to GATES:ESCALATION
      # instead (AID-v3-principles.md §1 — a gates_report.json field nobody
      # reads before retrying anyway is decoration, not enforcement).
      local gates_report="${evidence_dir}/gates/gates_report.json"
      if [[ -f "$gates_report" ]] && command -v jq &>/dev/null; then
        local blocked_gate
        blocked_gate=$(jq -r '(.gates // {}) | to_entries[] | select(.value.runtime_baseline.retryable == false) | .key' "$gates_report" 2>/dev/null | head -1)
        if [[ -n "$blocked_gate" ]]; then
          local blocked_action
          blocked_action=$(jq -r --arg g "$blocked_gate" '.gates[$g].runtime_baseline.operator_action // "unknown"' "$gates_report" 2>/dev/null)
          _PRECONDITION_FAIL_REASON="timeout_policy_block"
          cat <<EOF >&2
PRECONDITION FAIL: gate '${blocked_gate}' is retryable:false (timeout_policy_block) — refusing GATES→EXECUTE.

Reason: gate '${blocked_gate}' has already timed out repeatedly at the currently
        configured timeout_seconds (see gates_report.json.gates.${blocked_gate}.runtime_baseline)
        — gate-fixer has nothing to act on since the gate never runs to
        completion. Recommended operator action: ${blocked_action}.

Fix: address the blocking gate directly (${blocked_action}: e.g. raise
     execution.yaml.gates.${blocked_gate}.timeout_seconds, or switch it to a
     background run mode), re-run gates, then retry — OR route this run to
     GATES:ESCALATION instead of retrying EXECUTE:
       aid-fsm.sh transition GATES ESCALATION ${state_file}

OR (PM-authorized override, audited):
  aid-fsm.sh transition GATES EXECUTE ${state_file} --force --reason \\
      '<≥20 chars why re-entering EXECUTE for this gate is acceptable>'
EOF
          return 1
        fi
      fi
      ;;

    # Failure/retry paths — always allowed
    EXECUTE:ESCALATION|GATES:ESCALATION) : ;;

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
        # D1 (IMP-232 v2.58.0): the old global cross-plan ca-review pre-scan is
        # obsolete — the only init hard-block --force now waives is a STRUCTURED
        # depends_on_plans target that is not closed. Name it in the audit record
        # if present (else the override is recorded without a named blocker).
        local _bepic="" _bplan=""
        local _cur_plan_num=""
        [[ "$epic_id" =~ ^E-([0-9]+) ]] && _cur_plan_num="${BASH_REMATCH[1]}"
        local _cur_plan_prefix="P${_cur_plan_num}"
        if [[ -n "$_cur_plan_num" ]]; then
          local _mf _d
          _mf="$(aid_manifest_path "$_cur_plan_prefix" ".")"
          if [[ -f "$_mf" ]]; then
            while IFS= read -r _d; do
              [[ -z "$_d" || "$_d" == "null" ]] && continue
              if [[ "$(aid_plan_closure_state "$_d" ".")" != "closed" ]]; then _bplan="$_d"; break; fi
            done < <(yq -r '.depends_on_plans[]' "$_mf" 2>/dev/null)
          fi
        fi
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

  # ── P064 E-064-1_2 Step 5: plan-branch lineage precondition ───────────────
  # Runs BEFORE the duplicate-state guard below (not after) so a resumed run
  # on a wrong branch is caught too, not silently allowed to hit the generic
  # "prevent duplicate init" error first. Deliberately does NOT reuse the
  # PRE-FLIGHT branch enforcement's own `expected_branch` local — that var is
  # computed further down, only inside the non-worktree arm — so it is empty
  # on every worktree invocation. This block computes its own branch name so
  # it fires identically inside a linked worktree too (mirrors
  # aid-plan-fsm.sh's own worktree-independent lineage check, unlike THIS
  # file's PRE-FLIGHT branch enforcement, which intentionally skips itself in
  # a worktree via is_worktree()).
  #
  # Mode-gated: a no-op for `legacy_epic_release_mode` AND for an EPIC id that
  # derives no plan id / a plan id with no lifecycle manifest at all (ad-hoc
  # EPICs, every plan predating the lifecycle layer) — `aid_lifecycle_plan_mode`
  # already documents "no manifest => legacy_epic_release_mode", so both cases
  # collapse into the same no-op path.
  #
  # Fail-closed for a DECLARED `plan_branch` plan only: every way of "not
  # knowing" (lib not sourced, runtime manifest missing, runtime manifest
  # unparseable) is a hard block, never a silent downgrade to legacy behavior.
  local _plan_expected_branch="task/${epic_id}/main"
  local _pb_nnn=""
  # Same epic-id -> plan-id derivation as _fsm_declared_plan_mode and
  # _fsm_gate_profile_boundary — ONE helper (`_fsm_epic_plan_nnn`, top of this
  # file), not three copies of a `grep -oP` that fails outright on a grep
  # without PCRE support. Empty for an epic_id with no digits after "E-"
  # (ad-hoc EPIC, e.g. a bare "E-test" fixture id), and the block below is then
  # skipped entirely.
  _pb_nnn="$(_fsm_epic_plan_nnn "$epic_id")"
  local _pb_plan_id=""
  [[ -n "$_pb_nnn" ]] && _pb_plan_id="P${_pb_nnn}"

  if [[ -n "$_pb_plan_id" ]]; then
    # Resolve the plan's DECLARED release mode through the ONE committed-tree,
    # fail-closed authority — `_fsm_declared_plan_mode` (bottom of this file) —
    # the exact resolver `done-advance` uses (registry row
    # plan_mode_single_authority). cmd_init PREVIOUSLY called
    # `aid_lifecycle_plan_mode` directly, which fails OPEN: a missing `yq`, an
    # unparseable manifest, or an out-of-enum `mode` value all collapsed to
    # legacy_epic_release_mode, silently skipping THIS security precondition
    # (the plan-branch lineage check) while done-advance's stronger reader would
    # have blocked on the same repository state. Routing through the authority
    # makes every "cannot determine the mode" outcome `unresolved` -> a hard
    # block with the same audited --force --reason override this block already
    # uses for its other reasons, never a silent legacy downgrade.
    #
    # The authority reads target_branch's COMMITTED tree via `git cat-file` /
    # `git show` (an untracked working-tree-only manifest is `unresolved`, never
    # an answer — a tightening over the old reader, which treated it as legacy),
    # so the happy paths are unchanged: a committed `mode: plan_branch` still
    # returns plan_branch regardless of what task branch cmd_init has checked
    # out, and genuine absence (no plan id, no manifest anywhere, no `mode` key)
    # still returns legacy_epic_release_mode -> no-op. It derives its own plan id
    # from epic_id with the same `_fsm_epic_plan_nnn` helper this block used, so
    # its verdict and `_pb_plan_id` always name the same plan.
    local _pb_mode="" _pb_mode_plan="" _pb_mode_reason=""
    IFS=$'\t' read -r _pb_mode _pb_mode_plan _pb_mode_reason \
      < <(_fsm_declared_plan_mode "$epic_id") || true

    if [[ "$_pb_mode" == "unresolved" ]]; then
      local _pb_reason="plan_mode_unresolved"
      local _pb_detail="Could not determine the release mode for ${_pb_plan_id} (resolver reason: ${_pb_mode_reason:-<none>}) while a plan_branch declaration may exist — refusing to guess legacy_epic_release_mode, since that would silently skip lineage verification for a plan that may actually be plan_branch. Fix the underlying cause (install yq, or repair/commit .aid-lifecycle/manifests/${_pb_plan_id}.yaml on the target branch) rather than overriding."
      local _pb_timeline="${evidence_dir}/timeline.jsonl"
      mkdir -p "$(dirname "$_pb_timeline")" 2>/dev/null || true
      if [[ "$force" == "true" ]]; then
        echo "WARNING: --force used, skipping the plan-branch lineage precondition (reason would have been: ${_pb_reason})." >&2
        log_event "$_pb_timeline" "fsm_init_blocked" reason="$_pb_reason" epic_id="$epic_id" plan_id="$_pb_plan_id" mode_reason="$_pb_mode_reason" overridden="true"
      else
        echo "PRECONDITION FAIL: plan-branch lineage check failed for ${epic_id} (plan ${_pb_plan_id}, reason: ${_pb_reason})." >&2
        echo "${_pb_detail}" >&2
        echo "Override (audited): aid-fsm.sh init ${epic_id} ... --force --reason '<why this override is safe>'" >&2
        log_event "$_pb_timeline" "fsm_init_blocked" reason="$_pb_reason" epic_id="$epic_id" plan_id="$_pb_plan_id" mode_reason="$_pb_mode_reason"
        exit 1
      fi
    elif [[ "$_pb_mode" == "plan_branch" ]]; then
      local _pb_reason="" _pb_detail=""

      if ! declare -F plan_manifest_path >/dev/null 2>&1; then
        _pb_reason="plan_manifest_unavailable"
        _pb_detail="lib/aid-plan-manifest.sh could not be sourced (expected at ${SCRIPT_DIR}/lib/aid-plan-manifest.sh) — cannot verify plan-branch lineage for a plan declared plan_branch."
      else
        local _pb_manifest_path=""
        _pb_manifest_path="$(plan_manifest_path "$_pb_plan_id")"
        if [[ ! -f "$_pb_manifest_path" ]]; then
          _pb_reason="plan_manifest_missing"
          _pb_detail="Runtime plan-boundary-manifest.json missing for ${_pb_plan_id} at ${_pb_manifest_path} (mode=plan_branch is declared in .aid-lifecycle/manifests/${_pb_plan_id}.yaml, which survives this deletion). Repair with: aid-plan-fsm.sh plan-state ${_pb_plan_id} --repair (note: repaired entries ALWAYS have lineage=unproven — repair can never mint proven — and must be attested separately with 'aid-plan-fsm.sh plan-state ${_pb_plan_id} --attest-source-ref <ref> --reason \"<reason>\" --epic ${epic_id}')"
        else
          # Validate epic_id format BEFORE jq interpolation to prevent injection.
          # Must match the manifest invariant's own epic-id pattern (mirrors
          # _pfsm_validate_epic_id in aid-plan-fsm.sh).
          if ! [[ "$epic_id" =~ ^E-[0-9]{3}-[0-9]+_[0-9]+$ ]]; then
            _pb_reason="epic_id_invalid_format"
            _pb_detail="epic_id must match format ^E-[0-9]{3}-[0-9]+_[0-9]+\$ (got '${epic_id}'). This check prevents jq injection and ensures consistent lineage tracking."
          else
            local _pb_entry="" _pb_get_rc=0
            _pb_entry="$(plan_manifest_get "$_pb_plan_id" ".plan_boundary_manifest.epic_runs[] | select(.epic_id==\"${epic_id}\")" 2>/dev/null)" || _pb_get_rc=$?
          if [[ "$_pb_get_rc" -eq 5 ]]; then
            _pb_reason="plan_manifest_corrupt"
            _pb_detail="Runtime plan-boundary-manifest.json for ${_pb_plan_id} at ${_pb_manifest_path} is present but unparseable."
          elif [[ -z "$_pb_entry" ]]; then
            _pb_reason="plan_manifest_missing"
            _pb_detail="No epic_runs[] entry for ${epic_id} in ${_pb_plan_id}'s plan-boundary-manifest.json (never epic-started under this plan, or the entry was lost). Run 'aid-plan-fsm.sh epic-start ${_pb_plan_id} ${epic_id}' first, or repair with: aid-plan-fsm.sh plan-state ${_pb_plan_id} --repair"
          else
            local _pb_status="" _pb_task_branch="" _pb_base="" _pb_lineage="" _pb_epic_source_ref=""
            _pb_status="$(jq -r '.status // empty' <<<"$_pb_entry" 2>/dev/null)" || true
            _pb_task_branch="$(jq -r '.task_branch // empty' <<<"$_pb_entry" 2>/dev/null)" || true
            _pb_base="$(jq -r '.epic_base_commit // empty' <<<"$_pb_entry" 2>/dev/null)" || true
            _pb_lineage="$(jq -r '.lineage // empty' <<<"$_pb_entry" 2>/dev/null)" || true
            _pb_epic_source_ref="$(jq -r '.epic_source_ref // empty' <<<"$_pb_entry" 2>/dev/null)" || true

            if [[ "$_pb_status" == "abandoned" ]]; then
              _pb_reason="epic_abandoned"
              _pb_detail="${epic_id} is recorded status=abandoned in ${_pb_plan_id}'s plan-boundary-manifest.json — restarting an abandoned EPIC without a PM decision would silently resurrect it."
            elif [[ "$_pb_lineage" != "proven" || "$_pb_epic_source_ref" != "plan/${_pb_plan_id}" ]]; then
              _pb_reason="epic_lineage_unproven"
              _pb_detail="${epic_id}'s manifest entry has lineage='${_pb_lineage:-<empty>}' and epic_source_ref='${_pb_epic_source_ref:-<empty>}' — refusing to treat it as authoritative (must be proven with epic_source_ref=plan/${_pb_plan_id} to execute within this plan). Use 'aid-plan-fsm.sh epic-start ${_pb_plan_id} ${epic_id}' to create a new proven entry, or attest this entry with 'aid-plan-fsm.sh plan-state ${_pb_plan_id} --attest-source-ref <ref> --reason \"<reason>\" --epic ${epic_id}'."
            elif [[ "$_pb_task_branch" != "$_plan_expected_branch" ]]; then
              _pb_reason="plan_branch_mismatch"
              _pb_detail="${_pb_plan_id}'s manifest records task_branch=${_pb_task_branch:-<empty>} for ${epic_id}, but this run expects ${_plan_expected_branch}."
            else
              local _pb_actual_base=""
              _pb_actual_base="$(git merge-base "$_plan_expected_branch" "plan/${_pb_plan_id}" 2>/dev/null)" || _pb_actual_base=""
              if [[ -z "$_pb_actual_base" ]]; then
                _pb_reason="plan_branch_mismatch"
                _pb_detail="Cannot compute merge-base(${_plan_expected_branch}, plan/${_pb_plan_id}) — lineage unverifiable."
              elif [[ "$_pb_actual_base" != "$_pb_base" ]]; then
                _pb_reason="plan_branch_mismatch"
                _pb_detail="${_plan_expected_branch}'s actual base (${_pb_actual_base}) does not match its recorded epic_base_commit (${_pb_base:-<empty>}) in ${_pb_plan_id}'s plan-boundary-manifest.json — lineage broken (stale/foreign base, or the branch was not created via aid-plan-fsm.sh epic-start)."
              fi
            fi
          fi
          fi
        fi
      fi

      if [[ -n "$_pb_reason" ]]; then
        # Use evidence_dir/timeline.jsonl directly (already known from cmd_init's
        # own $epic_id/$run_id, computed before arg-parsing) rather than
        # derive_timeline "$state_file" — at THIS point in cmd_init the state
        # file legitimately does not exist yet on a fresh init (derive_timeline
        # reads epic_id/run_id FROM the state file, so it would silently resolve
        # to nothing here), which would make a --force override on a fresh run
        # go unrecorded. mkdir -p mirrors fsm_handle_force_override's own
        # same-situation safety net (evidence dir not yet materialized this
        # early in cmd_init).
        local _pb_timeline="${evidence_dir}/timeline.jsonl"
        mkdir -p "$(dirname "$_pb_timeline")" 2>/dev/null || true
        if [[ "$force" == "true" ]]; then
          echo "WARNING: --force used, skipping the plan-branch lineage precondition (reason would have been: ${_pb_reason})." >&2
          log_event "$_pb_timeline" "fsm_init_blocked" reason="$_pb_reason" epic_id="$epic_id" plan_id="$_pb_plan_id" overridden="true"
        else
          echo "PRECONDITION FAIL: plan-branch lineage check failed for ${epic_id} (plan ${_pb_plan_id}, reason: ${_pb_reason})." >&2
          echo "${_pb_detail}" >&2
          echo "Override (audited): aid-fsm.sh init ${epic_id} ... --force --reason '<why this override is safe>'" >&2
          log_event "$_pb_timeline" "fsm_init_blocked" reason="$_pb_reason" epic_id="$epic_id" plan_id="$_pb_plan_id"
          exit 1
        fi
      fi
    fi
  fi

  if [[ -f "$state_file" ]]; then
    echo "ERROR: state_file already exists: $state_file (prevent duplicate init)" >&2
    exit 1
  fi

  # ── D1 (IMP-232 v2.58.0): dependency-scoped init gate + advisory ──────────
  # An independent plan's state NEVER hard-blocks another plan's init. A hard
  # block occurs ONLY when THIS plan declares a STRUCTURED depends_on_plans
  # target that is not `closed`. Legacy prose `depends_on:` is advisory-only.
  # Separately, a single actionable advisory summarizes unreconciled plans
  # (suppressed in CI). This replaces the old global cross-plan ca-review-complete
  # hard-block that coupled every independent plan (the root of the P065 pain).
  local _cur_plan_num _cur_plan=""
  _cur_plan_num=""
  [[ "$epic_id" =~ ^E-([0-9]+) ]] && _cur_plan_num="${BASH_REMATCH[1]}"
  [[ -n "$_cur_plan_num" ]] && _cur_plan="P${_cur_plan_num}"

  # Hard block: structured depends_on_plans with an unclosed target (skippable
  # via the sanctioned --force override).
  if [[ "$force" != "true" && -n "$_cur_plan" ]]; then
    local _manifest _dep _dep_state
    _manifest="$(aid_manifest_path "$_cur_plan" ".")"
    if [[ -f "$_manifest" ]]; then
      while IFS= read -r _dep; do
        [[ -z "$_dep" || "$_dep" == "null" ]] && continue
        _dep_state="$(aid_plan_closure_state "$_dep" ".")"
        if [[ "$_dep_state" != "closed" ]]; then
          echo "PRECONDITION FAIL: ${_cur_plan} declares depends_on_plans: ${_dep}, which is not closed (state: ${_dep_state})." >&2
          echo "Close ${_dep} first (all required EPICs delivered + review-accepted), or override (audited):" >&2
          echo "  aid-fsm.sh init ${epic_id} ... --force --reason '<why ${_dep} need not be closed first>'" >&2
          local timeline
          timeline=$(derive_timeline "$state_file") || true
          [[ -n "$timeline" ]] && log_event "$timeline" "fsm_init_blocked" reason="depends_on_unclosed" blocking_plan="$_dep"
          exit 1
        fi
      done < <(yq -r '.depends_on_plans[]' "$_manifest" 2>/dev/null)
    fi
  fi

  # Advisory (non-blocking): ONE actionable summary of plans that are delivered
  # but not yet reconciled, plus a count of legacy-unverifiable plans. Suppressed
  # in machine/CI mode. Never per-EPIC, never a hard block.
  if [[ -z "${AID_CI:-}" && "${AID_QUIET:-}" != "1" && -d ".aid-o/plans" ]]; then
    local _pf _pid _pstate _unrec="" _legacy_n=0
    while IFS= read -r _pf; do
      _pid="$(basename "$_pf" | sed -E 's/^(P[0-9]+)-.*/\1/')"
      [[ "$_pid" =~ ^P[0-9]+$ ]] || continue
      [[ "$_pid" == "$_cur_plan" ]] && continue
      _pstate="$(aid_plan_closure_state "$_pid" "." 2>/dev/null || echo unknown)"
      case "$_pstate" in
        delivered-but-unreconciled) _unrec+=" ${_pid}";;
        legacy-unverifiable)        _legacy_n=$((_legacy_n+1));;
      esac
    done < <(ls .aid-o/plans/P*-*.md 2>/dev/null)
    if [[ -n "$_unrec" ]]; then
      echo "ADVISORY: plan(s) delivered but not reconciled:${_unrec}. Reconcile with:" >&2
      echo "  aid-fsm.sh plan-reconcile <PNN> --apply" >&2
    fi
    [[ "$_legacy_n" -gt 0 ]] && echo "ADVISORY: ${_legacy_n} plan(s) in legacy-unverifiable state (see plan-reconcile --dry-run)." >&2
  fi

  if [[ "$force" == "true" ]]; then
    echo "WARNING: --force used, skipping the depends_on_plans init gate (D1). Branch/clean-worktree/duplicate-state guards still apply." >&2
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
  #
  # .aid-o/work/audit-log.jsonl is excluded for the same reason: it is an
  # append-only FSM audit artefact, and `init --force` itself writes the
  # fsm_force_override entry to it (via fsm_handle_force_override, above)
  # before this guard runs. In projects where it is tracked, an unexcluded
  # guard would make `init --force` dirty its own tree and then fail on that
  # same change on the very next invocation.
  #
  # .aid-o/metrics/gate-runtime-baselines.yaml (+ its .lock sidecar) get the
  # same treatment (P063 Step 2): the gitignore/.git-info-exclude backfill
  # (aid-run-gates.sh's aid_gate_baseline_ensure_gitignored) is the PRIMARY
  # defense against these files ever showing up as tracked, but this guard is
  # defense-in-depth, independent of whether that bootstrap succeeded in a
  # given clone — a project where either file is unusually git-tracked must
  # still not have its own runtime metrics writes block `init`. Same
  # single-file, non-glob scoping as the two entries above (never a
  # directory-wide glob).
  local _dirty
  _dirty="$(git status --porcelain --untracked-files=no \
    | grep -vE '^.. \.aid-o/config/queue\.yaml$|^.. \.aid-o/work/audit-log\.jsonl$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml$|^.. \.aid-o/metrics/gate-runtime-baselines\.yaml\.lock$' || true)"
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

  # OBS-20260712-01 hotfix: this run becomes the sole explicit pointer the
  # commit-scope guard consults for main-fallback governance. Never fails init.
  write_active_run_pointer "$state_file"

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
  shift
  # Optional --profile <name>: an EXPLICIT profile passed by advance-to-gates'
  # own caller (e.g. a future PM/pipeline override) always wins over auto-
  # resolve below — same "manual override is authoritative" convention Step 1
  # already established for AID_GATE_PROFILE_OVERRIDE. Auto-resolve only fires
  # when the caller did NOT specify one (P061 E2 Step 2 / "Step 8" design
  # decision — see block below for the full rationale).
  local explicit_profile=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile) explicit_profile="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
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

  # ─── P061 E2 Step 2 ("Step 8"): gate-profile auto-resolve ─────────────────
  # DESIGN DECISION: advance-to-gates ALWAYS resolves a profile — either the
  # caller's explicit --profile (wins outright, no resolver call at all) or,
  # when none was given, the Step 1 shared resolver (aid-gate-profile.sh's
  # gate_profile_resolve) run against THIS run's base_commit..HEAD diff. The
  # resolved name is only actually passed to aid-run-gates.sh as --profile
  # when it is a key under execution.yaml.gate_profiles — this is the D9
  # legacy-preservation guard: a project that has never defined gate_profiles
  # (the overwhelming majority today, INCLUDING this plugin's own
  # execution.yaml at the time of writing) must keep running every defined
  # gate exactly as before. Without this guard, auto-resolve would hand
  # aid-run-gates.sh a --profile name with no matching gate_profiles key,
  # which is a hard, fail-loud error there (P061 E1 Step 2) — i.e. it would
  # BREAK every project that hasn't opted in, including the very EPIC that
  # produced this code. An explicit caller --profile is passed through
  # unconditionally instead: the caller asked for it by name, so an unknown
  # key is the caller's own mistake and should fail loud (same as calling
  # aid-run-gates.sh directly with a bad --profile).
  local profile_arg=()
  if [[ -n "$explicit_profile" ]]; then
    profile_arg=(--profile "$explicit_profile")
    [[ -n "$timeline" ]] && log_event "$timeline" "gate_profile_selected" \
      profile="$explicit_profile" source="explicit_caller"
  else
    # P064 plan Step 8: resolve at the EPIC BOUNDARY (mode-gated — see
    # _fsm_gate_profile_boundary). In plan_branch mode this caps the run at
    # `standard`, so no EPIC starts a broad suite on its own; the accumulated
    # plan-final floor is recorded separately by `aid-plan-fsm.sh
    # epic-complete`. The GATES:DONE risk precondition recomputes through the
    # SAME helper, so the two can never disagree.
    local _gp_base_commit _gp_paths_file _gp_resolved _gp_defined _gp_boundary
    _gp_base_commit=$(yaml_field "$state_file" base_commit)
    _gp_boundary="$(_fsm_gate_profile_boundary "$epic_id")"
    _gp_paths_file=$(mktemp -t aid-gate-profile-paths.XXXXXX)
    if [[ -n "$_gp_base_commit" ]]; then
      git -C "$PWD" diff --name-only "${_gp_base_commit}..HEAD" > "$_gp_paths_file" 2>/dev/null || true
    fi
    _gp_resolved=$(gate_profile_resolve "$_gp_paths_file" "$state_file" "${evidence_dir}/review-profile.json" "$_gp_boundary")
    rm -f "$_gp_paths_file"

    _gp_defined=$(PROFILE="$_gp_resolved" yq '.gate_profiles[strenv(PROFILE)]' "$execution_yaml" 2>/dev/null || echo "")
    if [[ -n "$_gp_defined" && "$_gp_defined" != "null" ]]; then
      profile_arg=(--profile "$_gp_resolved")
      [[ -n "$timeline" ]] && log_event "$timeline" "gate_profile_selected" \
        profile="$_gp_resolved" source="auto_resolved" boundary="${_gp_boundary:-legacy}"
    else
      [[ -n "$timeline" ]] && log_event "$timeline" "gate_profile_auto_resolve_skipped" \
        resolved="$_gp_resolved" reason="not_defined_in_gate_profiles" boundary="${_gp_boundary:-legacy}"
    fi
  fi

  # Invoke runner with explicit FSM signal — Step 2 makes runner accept this.
  local rc=0
  AID_GATES_TRIGGERED_BY_FSM=1 \
    "${SCRIPT_DIR}/aid-run-gates.sh" run-all \
      "$execution_yaml" "$epic_id" "$run_id" \
      --state-file "$state_file" \
      --report-file "$report_file" \
      "${plan_json_arg[@]}" \
      "${profile_arg[@]}" \
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

# ─── IMP-263: idempotent, step-bound step-transition helpers ────────────────
# Canonical sha256 of plan.json steps[idx] (sorted keys, compact) — the hash a
# step-verify binding pins itself to. Empty (exit 0) when plan.json/jq/idx are
# unavailable, so every caller stays set -e safe and degrades gracefully.
_increment_plan_step_hash() {
  local plan_json="${1:-}" idx="${2:-}"
  [[ -f "$plan_json" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [[ "$idx" =~ ^[0-9]+$ ]] || return 0
  local canon
  canon=$(jq -S -c --argjson i "$idx" '.steps[$i] // null' "$plan_json" 2>/dev/null) || return 0
  [[ -z "$canon" || "$canon" == "null" ]] && return 0
  printf '%s' "$canon" | sha256sum | awk '{print $1}'
}

# Look up an idempotency token in the append-only transition ledger. Prints the
# LAST matching entry's "from<TAB>to" (empty when absent / jq unavailable / no
# ledger). Last-wins so a legitimately re-appended token reads its final target.
_increment_ledger_lookup() {
  local ledger="${1:-}" token="${2:-}"
  [[ -n "$token" && -f "$ledger" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -rs --arg t "$token" \
    'map(select(.token == $t)) | last
     | if . == null then "" else "\(.from)\t\(.to)" end' \
    "$ledger" 2>/dev/null || return 0
}

# IMP-263 fail-closed: pure predicate (0 = verified, 1 = not) that returns TRUE
# only when `vf` carries a COMPLETE binding — all five fields present — whose
# idempotency_token == `token`, step_index == `step`, step_id + plan_step_hash
# match the live plan.json step, and reviewed_commit == current HEAD. It logs
# nothing and never exits, so callers stay set -e safe. The crash-recovery
# self-heal is gated on this: a genuine crash leaves a valid step-verify.md
# behind, whereas a hand-inserted ledger row does not — so a forged row can
# never advance current_step without real, step-bound evidence.
_increment_binding_verified() {
  local vf="${1:-}" token="${2:-}" step="${3:-}" plan_json="${4:-}"
  [[ -f "$vf" ]] || return 1
  local bi bid bh bc bt
  bi=$(yaml_field "$vf" step_index)
  bid=$(yaml_field "$vf" step_id)
  bh=$(yaml_field "$vf" plan_step_hash)
  bc=$(yaml_field "$vf" reviewed_commit)
  bt=$(yaml_field "$vf" idempotency_token)
  [[ -n "$bi" && -n "$bid" && -n "$bh" && -n "$bc" && -n "$bt" ]] || return 1
  [[ "$bt" == "$token" ]] || return 1
  [[ "$bi" == "$step" ]] || return 1
  # step_id + plan_step_hash MUST verify against the live plan — no plan, no trust.
  [[ -f "$plan_json" ]] && command -v jq >/dev/null 2>&1 || return 1
  local live_id live_hash
  live_id=$(jq -r --argjson i "$step" '.steps[$i].id // ""' "$plan_json" 2>/dev/null || echo "")
  live_hash=$(_increment_plan_step_hash "$plan_json" "$step")
  [[ -n "$live_id" && "$bid" == "$live_id" ]] || return 1
  [[ -n "$live_hash" && "$bh" == "$live_hash" ]] || return 1
  # reviewed_commit MUST be the current HEAD — no HEAD, no trust.
  local head_commit
  head_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
  [[ -n "$head_commit" && "$bc" == "$head_commit" ]] || return 1
  return 0
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

  # ── IMP-263: idempotent, step-bound transition (replay + crash recovery) ────
  # The transition ledger records every applied step advance keyed by the
  # idempotency_token carried in the step-verify evidence. This short-circuit
  # runs BEFORE the preconditions and mutation, for BOTH --force and normal
  # calls, so:
  #   * A REPLAY (the E-064-1_2 double-advance: the controller misread the old
  #     bare-numeric stdout as an error and re-invoked; a copied prior verify
  #     file carried the SAME already-applied token) returns `already_applied`
  #     with exit 0 and NEVER advances current_step again.
  #   * CRASH RECOVERY: if a prior invocation appended the ledger entry but died
  #     before the current_step bump, current_step still reads `from`. We repair
  #     it to the recorded `to` (self-heal) and report already_applied — so the
  #     ledger-then-state pair is effectively atomic (old-valid or new-valid),
  #     never a double advance, and never requires manual fsm-state.yaml editing.
  local _idem_verify="${evidence_dir}/step-${step}-verify.md"
  local _idem_ledger="${evidence_dir}/step-transition-ledger.jsonl"
  local _idem_token _idem_hit
  _idem_token=$(yaml_field "$_idem_verify" idempotency_token)
  _idem_hit=$(_increment_ledger_lookup "$_idem_ledger" "$_idem_token")
  if [[ -n "$_idem_hit" ]]; then
    local _idem_from="${_idem_hit%%$'\t'*}" _idem_to="${_idem_hit##*$'\t'}"
    if [[ "$_idem_to" =~ ^[0-9]+$ && "$step" == "$_idem_to" ]]; then
      # PURE REPLAY: current_step is already at the recorded target. No mutation
      # happens here, so even a forged ledger row cannot cause an advance — this
      # is a safe idempotent no-op (the E-064-1_2 double-invoke case).
      echo "status=already_applied step=${_idem_to} token=${_idem_token}"
      return 0
    fi
    # CRASH-RECOVERY SELF-HEAL mutates current_step, so it must be EVIDENCE-backed,
    # never ledger-alone (PM review 2026-07-24). A hand-inserted single-step row
    # {token,from,to} must not masquerade as recovery. Require, together:
    #   * step == from and to == from+1 (no step-skipping — review MEDIUM guard);
    #   * a COMPLETE, live-verified binding in step-${step}-verify.md matching
    #     this token/step/plan/HEAD. A genuine crash leaves that file behind; a
    #     forged ledger row does not.
    if [[ "$_idem_from" =~ ^[0-9]+$ && "$_idem_to" =~ ^[0-9]+$ \
          && "$step" == "$_idem_from" && "$_idem_to" -eq $(( _idem_from + 1 )) ]] \
       && _increment_binding_verified "$_idem_verify" "$_idem_token" "$step" "${evidence_dir}/plan.json"; then
      local _heal_tmp="${state_file}.tmp"
      sed "s/^current_step: .*/current_step: ${_idem_to}/" "$state_file" > "$_heal_tmp" && mv "$_heal_tmp" "$state_file"
      local _idem_tl; _idem_tl=$(derive_timeline "$state_file") || true
      [[ -n "$_idem_tl" ]] && log_event "$_idem_tl" "step_transition_recovered" \
        token="$_idem_token" from="$_idem_from" to="$_idem_to"
      echo "status=already_applied step=${_idem_to} token=${_idem_token}"
      return 0
    fi
    # Ledger hit but no valid recovery basis (forged/partial row, or the live
    # binding does not verify) → do NOT trust it. Fall through to the normal
    # fail-closed preconditions below; a strict run rejects the unverifiable state.
  fi

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

    # ── IMP-263: step-bound evidence binding (fresh, non-replay token) ────────
    # Validate the binding carried in step-${step}-verify.md against the LIVE
    # plan.json + fsm-state BEFORE any mutation. Filename + `## Result: PASS` are
    # not sufficient: a step-0 verify copied to step-1-verify.md fails here
    # because its step_index / step_id / plan_step_hash / reviewed_commit still
    # name step 0. (A copied file whose token was already applied never reaches
    # this point — the idempotency short-circuit returned already_applied first.)
    #
    # STRICT BY DEFAULT for new runs (PM review 2026-07-24). A non-grandfathered
    # (post-deploy) run is strict automatically — the default is `strict`, not
    # `observe`; only a genuinely grandfathered run (created before the deploy
    # threshold) or an explicit AID_STEP_BINDING=observe downgrades it. Three
    # cases, all fail-closed for new runs:
    #   * ALL FIVE fields absent  → strict: reject (missing binding); else: legacy
    #     observe path (log step_binding_absent, advance).
    #   * PARTIAL binding (1..4 of 5) → ALWAYS reject, regardless of mode. A
    #     token-only binding must never skip the id/hash/commit checks (those were
    #     `-n`-guarded and so evadable); all-or-nothing closes that.
    #   * ALL FIVE present → validated field-by-field below.
    local _bind_index _bind_id _bind_hash _bind_commit _bind_token
    _bind_index=$(yaml_field "$verify_file" step_index)
    _bind_id=$(yaml_field "$verify_file" step_id)
    _bind_hash=$(yaml_field "$verify_file" plan_step_hash)
    _bind_commit=$(yaml_field "$verify_file" reviewed_commit)
    _bind_token=$(yaml_field "$verify_file" idempotency_token)

    local _bind_mode="${AID_STEP_BINDING:-strict}"
    fsm_check_grandfather && _bind_mode="observe"
    local _bind_absent="false" _bind_present="false"
    [[ -z "$_bind_index" && -z "$_bind_id" && -z "$_bind_hash" && -z "$_bind_commit" && -z "$_bind_token" ]] && _bind_absent="true"
    [[ -n "$_bind_index" && -n "$_bind_id" && -n "$_bind_hash" && -n "$_bind_commit" && -n "$_bind_token" ]] && _bind_present="true"

    if [[ "$_bind_absent" == "true" ]]; then
      if [[ "$_bind_mode" == "strict" ]]; then
        _increment_fail missing_step_binding \
          "PRECONDITION FAIL: step verification carries no IMP-263 binding (strict mode)." \
          "File: ${verify_file}" \
          "Required fields: step_index, step_id, plan_step_hash, reviewed_commit, idempotency_token." \
          "A strict run must bind evidence to the exact plan step and reviewed commit."
      fi
      local _bind_tl; _bind_tl=$(derive_timeline "$state_file") || true
      [[ -n "$_bind_tl" ]] && log_event "$_bind_tl" "step_binding_absent" step="$step" mode="$_bind_mode"
    elif [[ "$_bind_present" != "true" ]]; then
      # PARTIAL binding — reject unconditionally; an incomplete binding can neither
      # be trusted nor allowed to bypass the id/hash/commit verification below.
      _increment_fail incomplete_step_binding \
        "PRECONDITION FAIL: step binding is incomplete — all five fields are required." \
        "File: ${verify_file}" \
        "Required: step_index, step_id, plan_step_hash, reviewed_commit, idempotency_token." \
        "Present: step_index=${_bind_index:+y} step_id=${_bind_id:+y} plan_step_hash=${_bind_hash:+y} reviewed_commit=${_bind_commit:+y} idempotency_token=${_bind_token:+y}"
    else

      # step_index must name the CURRENT step (rejects a copied/renamed file for
      # another step, and any stale/future-step evidence).
      if [[ -n "$_bind_index" && "$_bind_index" != "$step" ]]; then
        _increment_fail binding_step_index_mismatch \
          "PRECONDITION FAIL: binding step_index=${_bind_index} != current_step=${step}." \
          "File: ${verify_file}" \
          "A verify file bound to another step (e.g. a copied step-${_bind_index} file) cannot complete step ${step}."
      fi

      # step_id + plan_step_hash must match the LIVE plan.json step (rejects
      # wrong-plan / mismatched-step evidence). Skipped only when plan.json/jq
      # are unavailable — step_index + token still bind in that degraded case.
      if [[ -f "$_plan_json" ]] && command -v jq >/dev/null 2>&1; then
        local _live_id _live_hash
        _live_id=$(jq -r --argjson i "$step" '.steps[$i].id // ""' "$_plan_json" 2>/dev/null || echo "")
        _live_hash=$(_increment_plan_step_hash "$_plan_json" "$step")
        if [[ -n "$_bind_id" && -n "$_live_id" && "$_bind_id" != "$_live_id" ]]; then
          _increment_fail binding_step_id_mismatch \
            "PRECONDITION FAIL: binding step_id='${_bind_id}' != plan step ${step} id='${_live_id}'." \
            "File: ${verify_file}" \
            "The evidence is bound to a different plan step (stale/copied/wrong-plan)."
        fi
        if [[ -n "$_bind_hash" && -n "$_live_hash" && "$_bind_hash" != "$_live_hash" ]]; then
          _increment_fail binding_plan_step_hash_mismatch \
            "PRECONDITION FAIL: binding plan_step_hash does not match plan.json step ${step}." \
            "File: ${verify_file}" \
            "binding hash: ${_bind_hash}" \
            "live hash:    ${_live_hash}" \
            "The evidence is bound to a different plan-step definition (wrong-plan / mutated step)."
        fi
      fi

      # reviewed_commit must be the current HEAD (the step's own commit) —
      # rejects wrong-commit / stale evidence bound to an earlier step's commit.
      # Skipped when HEAD is unresolvable (no git / detached) — degraded, other
      # bindings still hold.
      if [[ -n "$_bind_commit" ]]; then
        local _head_commit
        _head_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
        if [[ -n "$_head_commit" && "$_bind_commit" != "$_head_commit" ]]; then
          _increment_fail binding_wrong_commit \
            "PRECONDITION FAIL: binding reviewed_commit=${_bind_commit} is not current HEAD=${_head_commit}." \
            "File: ${verify_file}" \
            "The reviewed commit must be this step's commit at HEAD (wrong-commit / stale evidence rejected)."
        fi
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

  # ── IMP-263: record the transition in the ledger, THEN bump current_step ────
  # By the time control reaches here on the non-force path the binding is either
  # legitimately absent (legacy/grandfathered — token empty, so NO row is written
  # by the `-n "$_rec_token"` guard) or FULLY VALIDATED above. So every ledger row
  # written is validated, and it is written before — and is a precondition of —
  # the current_step bump, never after it.
  # Ledger append first (durable temp+mv → never a partially-written ledger),
  # current_step bump second. A crash BETWEEN the two is repaired on the next
  # invocation by the idempotency short-circuit above (ledger → state self-heal),
  # so the pair is effectively atomic: old-valid or new-valid, never a double
  # advance. Force transitions are ledgered too, so a forced replay is idempotent.
  # Only runs when the evidence carries a token and step is numeric.
  if [[ "$step" =~ ^[0-9]+$ ]] && command -v jq >/dev/null 2>&1; then
    local _rec_verify="${evidence_dir}/step-${step}-verify.md"
    local _rec_ledger="${evidence_dir}/step-transition-ledger.jsonl"
    local _rec_token
    _rec_token=$(yaml_field "$_rec_verify" idempotency_token)
    if [[ -n "$_rec_token" ]]; then
      local _rec_id _rec_hash _rec_commit _rec_line _rec_tmp
      _rec_id=$(yaml_field "$_rec_verify" step_id)
      _rec_hash=$(yaml_field "$_rec_verify" plan_step_hash)
      _rec_commit=$(yaml_field "$_rec_verify" reviewed_commit)
      _rec_line=$(jq -cn --arg tok "$_rec_token" --argjson si "$step" --arg sid "$_rec_id" \
        --arg ph "$_rec_hash" --arg rc "$_rec_commit" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{token:$tok, step_index:$si, step_id:$sid, plan_step_hash:$ph, reviewed_commit:$rc, from:$si, to:($si + 1), applied_at:$at}' 2>/dev/null) || _rec_line=""
      if [[ -n "$_rec_line" ]]; then
        _rec_tmp="${_rec_ledger}.tmp.$$"
        { [[ -f "$_rec_ledger" ]] && cat "$_rec_ledger"; printf '%s\n' "$_rec_line"; } > "$_rec_tmp" && mv "$_rec_tmp" "$_rec_ledger"
      fi
    fi
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
  #
  # SECURITY (CP3 re-review, E-061-2_6): $step is interpolated into three yq
  # expressions below. yaml_field never validates current_step is numeric, so
  # an operator/tooling bug that sets it to e.g. "0,1" (still valid in the
  # $((step + 1)) arithmetic above, AND valid as yq multi-index syntax) could
  # forge multiple steps[] entries to status:completed in one call — the same
  # yq-expression-injection class as the --profile and --auto-annotate fixes
  # elsewhere in this file. The numeric guard below closes it: a non-digit
  # current_step skips this best-effort block entirely (matching its own
  # "must not crash" design), same as the legacy-no-steps[] case already did.
  if [[ "$step" =~ ^[0-9]+$ ]] && command -v yq >/dev/null 2>&1 && yq -e ".steps[${step}]" "$state_file" >/dev/null 2>&1; then
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

  # ── IMP-263: machine-readable stdout contract ────────────────────────────
  # Was `echo "$((step + 1))"` — a bare integer the controller misread as an
  # exit/error code (the E-064-1_2 double-advance trigger). The result is now a
  # stable key=value line; the controller parses `status=`, never bare stdout.
  # Exit code stays 0 here; preconditions exit non-zero via _increment_fail/die.
  echo "status=advanced advanced_from=${step} advanced_to=$((step + 1))"
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

# ─── Plan-branch release-stack skip list (P064 plan Step 9) ──────────────────
# THE single source of truth for which review→release stages cmd_done_advance
# skips when the completing EPIC's owning plan is DECLARED `plan_branch`. The
# spy test (scripts/tests/bats/test-aid-plan-release-boundary.bats) parses THIS
# array out of THIS file and asserts the `done_advance_plan_branch_mode`
# timeline event lists exactly these names — it never keeps its own copy, so
# the emitted list can never drift from what the code actually skips.
#
# Order = execution order inside cmd_done_advance's review→release arm.
#
# WHAT IS NOT HERE, ON PURPOSE. The EPIC-LOCAL validations still run in
# plan_branch mode: the streamlined integration review (which, under
# `streamlined_mode: true`, still HARD-REQUIRES this EPIC's own CP3 code-review
# + CP3 security outputs — only the CP3 FRESHNESS RE-CHECK is skipped, never
# the CP3 pair itself), the abandoned-but-shipped check, the DG-07 delivery
# gate, the tiered-severity compliance precondition (which is what reads the
# run's CP2 verifier outputs), `pm_decision == merge`, the archived-task-file
# check, and the auditor's `blocking_findings` verdict when an audit-report
# exists at all (Step 4 CP2 finding 1 — a PM-blessed mid-plan Auditor run must
# still be able to block). The skip is scoped to the per-EPIC RELEASE stack —
# the stages that only make sense once, at the plan boundary — not to local
# verification.
AID_PLAN_BRANCH_SKIPPED_STAGES=(
  c3_review_profile_presence
  cp4_curator_validation
  cp3_freshness_recheck
  curator_report_presence
  auditor_report_presence
  c3_independent_audit
  curator_content_ref_sequencing
  c3_dispatch_provenance
  c4_release_decision_dual_run
)

# _fsm_declared_plan_mode <epic_id> — echoes `<mode>\t<plan_id>\t<reason>`.
#   mode ∈ { plan_branch, legacy_epic_release_mode, unresolved }
# Always exits 0; the CALLER decides what to do with `unresolved`.
#
# THIS IS THE SINGLE AUTHORITY FOR THE PLAN'S RELEASE MODE (CP3 integration
# review finding 2, adjudicated action A3). It resolves through
# `aid_lifecycle_plan_mode` (lib/aid-lifecycle.sh), whose only input is the
# git-tracked `.aid-lifecycle/manifests/<plan_id>.yaml` — the PM's durable
# declaration of which release model the plan follows. `_fsm_gate_profile_boundary`
# (top of this file) now DELEGATES here instead of reading the gitignored
# RUNTIME manifest `plan-boundary-manifest.json`, so the two can no longer
# return confidently different answers for the same repository state; see that
# function's header for the two disagreement directions this closed. The
# runtime manifest is no longer a mode input anywhere in this file.
#
# ── THE DECLARATION ONLY COUNTS WHEN IT IS COMMITTED ────────────────────────
# The answer is read out of `target_branch`'s COMMITTED tree, and nowhere else.
# A working-tree-only (untracked) manifest is `unresolved`, never an answer:
# it is not durable, not auditable, not visible to any other clone, and
# `cmd_init`'s dirty-tree guard uses `--untracked-files=no`, so nothing else
# would catch it either — an untracked file must not be able to silence the
# nine `AID_PLAN_BRANCH_SKIPPED_STAGES`. The committed manifest is what
# `aid_lifecycle_set_plan_mode` writes (atomically, on target_branch), so the
# intended workflow already satisfies this.
#
# The working tree is still READ, as a GUARD rather than as a source: a
# manifest that is present there but unreadable/unparseable makes the whole
# resolution `unresolved`. Resolving it silently from the committed copy would
# be exactly the "an unreadable manifest is silently satisfied from elsewhere"
# hazard the previous working-tree-preference existed to avoid. A working-tree
# copy that IS readable and parseable is then ignored — including when it
# differs from the committed one: the committed declaration is the authority,
# and a local edit that has not been committed has not been declared.
#
# RESIDUAL RISK, NAMED: an incorrect (or maliciously) COMMITTED declaration
# remains authoritative here. That is a code-review/branch-protection problem,
# not one this resolver can close.
#
# WHY THE "CANNOT TELL" SPLIT IS WHERE IT IS.
#   -> legacy_epic_release_mode (documented default, never a block):
#      * epic_id derives no plan id (ad-hoc EPIC — it belongs to no plan, so
#        no plan can have declared plan_branch for it; identical to cmd_init's
#        and _fsm_gate_profile_boundary's own handling of this input);
#      * NO manifest anywhere — none on target_branch and none in the working
#        tree, or no Git repository at all and none in the working tree.
#        `aid_lifecycle_plan_mode`'s own file header documents absence as "not
#        yet declared plan_branch", the pre-P064 model, which is unambiguous
#        rather than unknown;
#      * a committed manifest that parses but carries no `mode` key (same
#        reason).
#   -> unresolved (hard block at the caller):
#      every case where a DECLARATION MAY EXIST AND WE CANNOT HONESTLY READ IT
#      — the lifecycle lib is not sourced; the manifest exists in the working
#      tree but is NOT COMMITTED on target_branch (it was never declared, only
#      typed); it is present in the working tree but unreadable or not a
#      regular file; mktemp gave us nowhere to extract the committed copy; the
#      extracted copy is unreadable; `yq` is absent; the manifest does not
#      parse; or it declares a `mode` value outside the known enum.
#      Guessing legacy for any of these would route the controller into
#      skills/pipeline.md's legacy action 15 — `git merge task/{epic_id}/main`
#      into the target branch — i.e. it would ship an individual EPIC to main,
#      which is precisely what P064 exists to prevent. Fail closed.
_fsm_declared_plan_mode() {
  local epic_id="${1:-}" nnn="" plan_id="" tb="" root="" manifest="" relpath=""
  local cleanup_root="" raw="" wt_present=false
  # Same epic-id -> plan-id derivation as cmd_init's lineage check,
  # cmd_plan_close and _fsm_gate_profile_boundary — ONE helper, reused.
  nnn="$(_fsm_epic_plan_nnn "$epic_id")"
  [[ -n "$nnn" ]] || { printf 'legacy_epic_release_mode\t\tno_plan_id_derivable\n'; return 0; }
  plan_id="P${nnn}"
  relpath=".aid-lifecycle/manifests/${plan_id}.yaml"

  declare -F aid_lifecycle_plan_mode >/dev/null 2>&1 || {
    printf 'unresolved\t%s\tlifecycle_lib_unavailable\n' "$plan_id"; return 0; }

  # ── STEP 1: the working tree is a GUARD, never a source ──────────────────
  # A manifest sitting in the working tree that we cannot read or cannot parse
  # makes the whole resolution `unresolved`. It is NOT answered from the
  # committed copy: "there is a declaration here and I cannot read it" is
  # exactly the state where guessing is unsafe, and silently satisfying it from
  # elsewhere is the hazard the old working-tree preference existed to avoid.
  # A readable, parseable working-tree copy contributes nothing beyond passing
  # this guard — Step 2 is the only place an ANSWER comes from.
  if [[ -e "$relpath" ]]; then
    wt_present=true
    if [[ ! -f "$relpath" || ! -r "$relpath" ]]; then
      printf 'unresolved\t%s\tmanifest_unreadable\n' "$plan_id"; return 0
    fi
    if ! command -v yq >/dev/null 2>&1; then
      printf 'unresolved\t%s\tyq_unavailable\n' "$plan_id"; return 0
    fi
    if ! yq -r '.' "$relpath" >/dev/null 2>&1; then
      printf 'unresolved\t%s\tmanifest_unparseable\n' "$plan_id"; return 0
    fi
  fi

  # ── STEP 2: the ANSWER comes from target_branch's COMMITTED tree ─────────
  # cmd_init checks out task/<epic_id>/main and LEAVES it checked out for the
  # rest of the EPIC's lifecycle, and the manifest is committed on
  # target_branch only — so a CWD-relative read would misreport every
  # plan_branch EPIC as legacy at exactly this decision point. Reading
  # target_branch's tree is therefore both the correct source AND the
  # committed-only rule: an untracked file cannot be in it.
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    if [[ "$wt_present" == "true" ]]; then
      # A manifest exists here but there is no repository to have committed it
      # in: it is a typed file, not a declaration.
      printf 'unresolved\t%s\tmanifest_not_committed_no_repo\n' "$plan_id"; return 0
    fi
    # No repository at all and no manifest in the working tree — nothing was
    # ever declared.
    printf 'legacy_epic_release_mode\t%s\tno_manifest_no_repo\n' "$plan_id"; return 0
  fi
  tb="$(aid_target_branch 2>/dev/null)" || tb=""
  [[ -n "$tb" ]] || tb="main"
  if ! git cat-file -e "${tb}:${relpath}" 2>/dev/null; then
    if [[ "$wt_present" == "true" ]]; then
      printf 'unresolved\t%s\tmanifest_not_committed_on_%s\n' "$plan_id" "$tb"; return 0
    fi
    printf 'legacy_epic_release_mode\t%s\tno_manifest_on_%s\n' "$plan_id" "$tb"; return 0
  fi
  root="$(mktemp -d 2>/dev/null)" || root=""
  [[ -n "$root" ]] || { printf 'unresolved\t%s\tmode_root_unavailable\n' "$plan_id"; return 0; }
  cleanup_root="$root"
  if ! mkdir -p "${root}/.aid-lifecycle/manifests" 2>/dev/null \
     || ! git show "${tb}:${relpath}" > "${root}/${relpath}" 2>/dev/null; then
    rm -rf "$cleanup_root" 2>/dev/null || true
    printf 'unresolved\t%s\tmanifest_unreadable\n' "$plan_id"; return 0
  fi
  manifest="${root}/${relpath}"

  if [[ ! -r "$manifest" ]]; then
    [[ -n "$cleanup_root" ]] && rm -rf "$cleanup_root" 2>/dev/null
    printf 'unresolved\t%s\tmanifest_unreadable\n' "$plan_id"; return 0
  fi
  if ! command -v yq >/dev/null 2>&1; then
    [[ -n "$cleanup_root" ]] && rm -rf "$cleanup_root" 2>/dev/null
    printf 'unresolved\t%s\tyq_unavailable\n' "$plan_id"; return 0
  fi
  if ! yq -r '.' "$manifest" >/dev/null 2>&1; then
    [[ -n "$cleanup_root" ]] && rm -rf "$cleanup_root" 2>/dev/null
    printf 'unresolved\t%s\tmanifest_unparseable\n' "$plan_id"; return 0
  fi
  raw="$(yq -r '.mode // ""' "$manifest" 2>/dev/null)" || raw="__yq_read_failed__"
  case "$raw" in
    ""|null|plan_branch|legacy_epic_release_mode) ;;
    *)
      # Untrusted manifest content: never echo it raw into a timeline payload.
      local safe="${raw//[^A-Za-z0-9_.-]/_}"
      [[ -n "$cleanup_root" ]] && rm -rf "$cleanup_root" 2>/dev/null
      printf 'unresolved\t%s\tmode_unknown_value_%s\n' "$plan_id" "${safe:0:40}"; return 0
      ;;
  esac

  # Delegate the actual answer to the authoritative reader — its parsing and
  # defaulting logic is reused verbatim, this function only supplies the right
  # root and refuses the inputs it cannot honestly hand over.
  local resolved=""
  resolved="$(aid_lifecycle_plan_mode "$plan_id" "$root" 2>/dev/null)" || resolved=""
  [[ -n "$cleanup_root" ]] && rm -rf "$cleanup_root" 2>/dev/null
  case "$resolved" in
    plan_branch|legacy_epic_release_mode) printf '%s\t%s\t\n' "$resolved" "$plan_id" ;;
    *) printf 'unresolved\t%s\tmode_reader_returned_no_answer\n' "$plan_id" ;;
  esac
  return 0
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

  # SECURITY/CORRECTNESS FIX (E-065-5_7 DONE-review C3 finding): the checks
  # above only verify from_phase matches the CURRENT phase and to_phase is a
  # KNOWN phase name — neither enforces a directional edge, so
  # `done-advance release review <state>` previously reached the final write,
  # regressing done_phase backward with no negative test catching it. DONE
  # phases only ever move forward: review -> release is the ONLY legal edge.
  [[ "$from_phase" == "review" && "$to_phase" == "release" ]] || {
    echo "ERROR: illegal done_phase transition: $from_phase -> $to_phase (only review -> release is allowed)" >&2
    exit 1
  }

  # ── P064 plan Step 9: resolve the owning plan's DECLARED release model ────
  # Runs on the review→release edge and nowhere else (it is the only legal
  # edge, checked immediately above). `plan_branch` means this is an
  # INTERMEDIATE EPIC completion inside an open plan: the per-EPIC release
  # stack in AID_PLAN_BRANCH_SKIPPED_STAGES is not merely optional here, it is
  # structurally skipped, because those stages belong to the plan-final run.
  # `unresolved` is a hard block — see _fsm_declared_plan_mode's header for why
  # falling back to legacy would be the unsafe direction.
  local _pb_mode="" _pb_mode_plan="" _pb_mode_reason="" _pb_plan_branch="false"
  local _pb_epic_id _pb_run_id _pb_mode_timeline
  _pb_epic_id=$(yaml_field "$state_file" epic_id)
  _pb_run_id=$(yaml_field "$state_file" run_id)
  _pb_mode_timeline=".aid-o/work/evidence/${_pb_epic_id}/${_pb_run_id}/timeline.jsonl"
  IFS=$'\t' read -r _pb_mode _pb_mode_plan _pb_mode_reason \
    < <(_fsm_declared_plan_mode "$_pb_epic_id") || true
  [[ "$_pb_mode" == "plan_branch" ]] && _pb_plan_branch="true"

  if [[ "$_pb_mode" == "unresolved" ]]; then
    mkdir -p "$(dirname "$_pb_mode_timeline")" 2>/dev/null || true
    if [[ "$force" == "true" ]]; then
      echo "WARNING: --force used, advancing with an UNRESOLVED release mode for plan ${_pb_mode_plan} (reason: ${_pb_mode_reason})." >&2
      log_event "$_pb_mode_timeline" "plan_mode_unresolved" \
        epic_id="$_pb_epic_id" plan_id="$_pb_mode_plan" reason="$_pb_mode_reason" overridden="true"
      # Step 4 CP2 finding 5: the run timeline above is not the surface a PM
      # audits. fsm_handle_force_override (called further down) writes
      # .aid-o/work/audit-log.jsonl with a GENERIC force carrying whatever
      # --blocked-checks the operator happened to type, so an audit of that file
      # alone could not tell that THIS advance happened without knowing whether
      # the EPIC was supposed to merge to the target branch at all. Emit the
      # named override into the audit log directly — a SEPARATE, additional
      # entry, leaving fsm_handle_force_override's contract untouched for the
      # many other callers that share it. Best-effort like every other
      # fsm_emit_audit_log call; it never aborts the advance.
      #
      # epic_id/run_id/project_root are read from caller scope by
      # fsm_emit_audit_log and are not declared until the force branch below, so
      # bind them here (both branches re-declare + reassign them from the state
      # file afterwards, so this cannot leak a stale value into them).
      local epic_id="$_pb_epic_id" run_id="$_pb_run_id" project_root="$PWD"
      fsm_emit_audit_log "plan_mode_unresolved_override" \
        --from "$from_phase" --to "$to_phase" --caller "done-advance" \
        --operator "${USER:-unknown}" \
        --plan-id "$_pb_mode_plan" --unresolved-reason "$_pb_mode_reason"
    else
      echo "PRECONDITION FAIL: plan_mode_unresolved — cannot determine the declared release model for plan ${_pb_mode_plan} (EPIC ${_pb_epic_id}, reason: ${_pb_mode_reason})." >&2
      echo "Refusing to guess. A wrong guess of legacy_epic_release_mode here routes the controller into merging task/${_pb_epic_id}/main straight into the target branch, which a plan_branch plan must never do." >&2
      echo "Fix: restore/repair .aid-lifecycle/manifests/${_pb_mode_plan}.yaml on the target branch (or install the missing tool), then retry." >&2
      echo "Override (audited): aid-fsm.sh done-advance ${from_phase} ${to_phase} ${state_file} --force --reason '<why this override is safe>'" >&2
      log_event "$_pb_mode_timeline" "plan_mode_unresolved" \
        epic_id="$_pb_epic_id" plan_id="$_pb_mode_plan" reason="$_pb_mode_reason"
      exit 1
    fi
  fi

  if [[ "$_pb_plan_branch" == "true" ]]; then
    # Routing telemetry, emitted BEFORE the skipped stages would have run so it
    # is present even when a RETAINED local check later blocks the transition.
    # The payload lists AID_PLAN_BRANCH_SKIPPED_STAGES verbatim — the spy test
    # asserts against that same array read out of this file.
    local _pb_stages_json
    if command -v jq >/dev/null 2>&1; then
      _pb_stages_json="$(printf '%s\n' "${AID_PLAN_BRANCH_SKIPPED_STAGES[@]}" \
        | jq -Rsc 'split("\n") | map(select(length > 0))')"
    else
      # No jq: hand-build the JSON array rather than emitting a comma-joined
      # STRING (Step 4 CP2 finding 4). log_event (lib/aid-stage-log.sh) passes a
      # value through as raw JSON only when its first character is '[' or '{';
      # the old `c3_review_profile_presence,cp4_...` form started with 'c', so it
      # was emitted as a QUOTED STRING and every consumer doing
      # `.skipped_stages[]` — including AC4's own assertion — broke on a
      # jq-less host. The array holds a fixed list of [a-z0-9_] identifiers
      # written literally three lines apart in this same file, so plain quoting
      # is sufficient; there is no escaping case to get wrong.
      local _pb_stage _pb_sep=""
      _pb_stages_json="["
      for _pb_stage in "${AID_PLAN_BRANCH_SKIPPED_STAGES[@]}"; do
        _pb_stages_json+="${_pb_sep}\"${_pb_stage}\""
        _pb_sep=","
      done
      _pb_stages_json+="]"
    fi
    mkdir -p "$(dirname "$_pb_mode_timeline")" 2>/dev/null || true
    log_event "$_pb_mode_timeline" "done_advance_plan_branch_mode" \
      epic_id="$_pb_epic_id" plan_id="$_pb_mode_plan" mode="plan_branch" \
      forced="$force" skipped_stages="$_pb_stages_json"
  fi

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
      # P064 plan Step 9 — SKIPPED in plan_branch mode (`c3_review_profile_presence`
      # in AID_PLAN_BRANCH_SKIPPED_STAGES).
      #
      # PRECISION (Step 4 CP2 finding 2): what an intermediate plan-branch EPIC
      # stops producing is the C3 PRODUCER HOOK's `review-profile.json` (the
      # aid-prefilter.sh risk profile over the full base_commit..HEAD diff that
      # feeds the plan-final C3/Curator/Auditor chain) — NOT the CP3 verifier
      # pair. The CP3 code-review + CP3 security verifiers are still dispatched
      # per EPIC in plan_branch mode, and under `streamlined_mode: true`
      # fsm_check_streamlined_integration_review (above the skip guard, retained
      # in both modes) still hard-`die`s when their two outputs are absent. Only
      # this presence check and the CP3 FRESHNESS re-check are skipped, so that
      # under enforcement=blocking a plan-branch EPIC is not failed for missing
      # an artifact the mode deliberately stopped producing.
      if [[ "$_pb_plan_branch" != "true" ]]; then
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
      fi
      # End C3 activation review-profile presence check (+ plan_branch skip guard)

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

      # ── EPIC-LOCAL checks that run in BOTH modes ────────────────────────────
      # Relocated here by P064 plan Step 9 from inside the release stack below
      # (they used to sit between the Curator sequencing guard and the C3
      # audit hook). Neither depends on a Curator/Auditor/C3/C4 artifact, and
      # both are exactly as meaningful for an EPIC merging into `plan/Pxxx` as
      # for one merging into the target branch — so the mode fork must not
      # swallow them. Pure `errors` contributors: order-independent.

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

      # ── The auditor's `blocking_findings` verdict (EPIC-LOCAL, BOTH modes) ───
      # HOISTED out of the release stack by the Step 4 CP2 review (finding 1). It
      # used to sit inside the skip guard while appearing in NEITHER the skipped
      # list nor the "WHAT IS NOT HERE" list — so a PM-blessed mid-plan Auditor
      # run (skills/pipeline.md, `mid_plan_specialist_review_exception`) that
      # reported a critical finding was silently ungated for an intermediate
      # plan-branch EPIC: it merged into `plan/{plan_id}` with the finding
      # unaddressed and nothing named the bypass. The verdict is about THIS
      # EPIC's own diff, not about the plan boundary, so it belongs here with
      # the other EPIC-local checks and is deliberately NOT in
      # AID_PLAN_BRANCH_SKIPPED_STAGES.
      #
      # NO-OP WHEN NO REPORT EXISTS. An intermediate plan-branch EPIC normally
      # produces no audit-report at all; absence remains exactly what it was
      # before the hoist — silence, never a new hard failure. Only the PRESENCE
      # of audit-report.md/.yaml arms the fail-closed read.
      #
      # Blocks on the auditor's CANONICAL top-level `blocking_findings` field
      # (agents/auditor.md: emitted as the first line of the YAML, E-046-1_3 Step
      # 3 producer→consumer migration). yaml_field() matches only line-start keys
      # — indented/nested values and prose body lines are INVISIBLE, preventing
      # the old grep-ciE false-positive on negations ("No blocking_findings: true
      # ..."). Fail-closed: report present + field absent → cannot confirm clean
      # → block.
      #
      # C3 SSOT PRECEDENCE (E-057-1_2 Step 4) — PRESERVED, BUT SCOPED. In legacy
      # mode this .md/.yaml read still defers to the C3 independent-audit hook
      # further down, which reads `.audit_report.blocking_findings` out of
      # audit-report.json: ONE source of truth, not two parallel checks. The
      # deferral is now scoped to the case where that hook CAN actually run.
      #   * plan_branch mode → the whole C3 chain is skipped, so deferring to it
      #     would leave the verdict ungated. This read always applies there.
      #   * legacy mode → defer exactly when the C3 hook's own secondary trigger
      #     would fire (review-profile.json AND a non-empty `.audit_report`
      #     object in audit-report.json). A run whose PRIMARY risk-gate fires
      #     without a readable audit-report.json no longer skips this read: the
      #     C3 hook has no JSON verdict to substitute, so the .md/.yaml verdict
      #     is the only one there is (fail-closed direction, deliberate).
      local audit_file=""
      [[ -f "${evidence_dir}/audit-report.md" ]] && audit_file="${evidence_dir}/audit-report.md"
      [[ -f "${evidence_dir}/audit-report.yaml" ]] && audit_file="${evidence_dir}/audit-report.yaml"

      local _bf_json_is_ssot="false"
      if [[ "$_pb_plan_branch" != "true" \
            && -f "${evidence_dir}/review-profile.json" \
            && -f "${evidence_dir}/audit-report.json" ]] && command -v jq >/dev/null 2>&1; then
        # Same shape probe as the C3 hook's secondary trigger below (a non-empty
        # `.audit_report` OBJECT is what makes that hook adopt the JSON as SSOT).
        # Guarded against `set -euo pipefail` abort like every other jq read here.
        local _bf_shape="" _bf_shape_ec=0
        _bf_shape=$(jq -r 'if (.audit_report | type) == "object" and (.audit_report | length) > 0 then "true" else "false" end' \
          "${evidence_dir}/audit-report.json" 2>/dev/null) || _bf_shape_ec=$?
        [[ $_bf_shape_ec -eq 0 && "$_bf_shape" == "true" ]] && _bf_json_is_ssot="true"
      fi

      if [[ -n "$audit_file" && "$_bf_json_is_ssot" != "true" ]]; then
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

      # ══ P064 plan Step 9: THE per-EPIC RELEASE STACK ════════════════════════
      # Everything from here to "End of the plan_branch-skipped release stack"
      # is the stack an INTERMEDIATE plan-branch EPIC completion must be
      # structurally incapable of invoking: CP4 curator validation, the CP3
      # freshness re-check, the Curator/Auditor report requirements, the C3
      # independent-audit chain, the C3 dispatch-provenance hook and the
      # EPIC-scoped C4 dual run. Their names are listed, in this order, in
      # AID_PLAN_BRANCH_SKIPPED_STAGES near the top of cmd_done_advance's
      # section of this file — that array is the single source of truth the
      # timeline event and the spy test both read.
      #
      # The body below is UNINDENTED on purpose: this guard is a pure skip, and
      # re-indenting ~625 lines would bury the behavioural change in whitespace
      # and make every future `git blame` on the release stack point at Step 9.
      if [[ "$_pb_plan_branch" != "true" ]]; then

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

      # (P064 plan Step 9 moved the pm_decision and task-file-archived checks OUT
      # of this block to just ABOVE the plan_branch skip guard — they are
      # EPIC-local validations, not release-stack stages, and must keep running
      # in both modes. Search: "EPIC-LOCAL checks that run in BOTH modes".)

      # E-057-1_2 Step 4: C3 independent-audit hook (risk-gated, JSON source of truth).
      # Reads `.audit_report.blocking_findings` from audit-report.json (protocol-v2
      # envelope, agents/auditor.md C3 mode, E-057-1_2 Step 2). For any run whose risk
      # profile requires C3, this REPLACES the legacy yaml_field()-based .md/.yaml
      # blocking_findings read — ONE source of truth, not two parallel checks
      # (M2 fix). Risk profile comes from review-profile.json (produced by
      # aid-prefilter.sh profile / skills/pipeline.md's C3 producer hook, E-057-1_2 Step
      # 3); this hook only fires when that profile is "high" or "unverifiable" — the two
      # (and only two) `c3_required: true` profiles in c3-audit-policy.yaml (D8/D9). Any
      # other profile (docs_trivial/low/medium), or a run with no review-profile.json at
      # all (pre-C3 runs never subjected to this pipeline stage), leaves this hook a
      # no-op — and the legacy blocking_findings check has ALREADY RUN by then. The
      # P064 Step 9 CP2 review HOISTED it ~250 lines ABOVE this block, out of the
      # release stack and into the EPIC-local checks that execute in BOTH modes, so it
      # is no longer "below" as the comments here used to say (search: "The auditor's
      # `blocking_findings` verdict (EPIC-LOCAL, BOTH modes)").
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
      #
      # P065 Step 16 (E-065-6_7) — CANONICAL-report confirmation, documentation only, NO
      # functional change here. pipeline.md's C3 fix→reverify loop (bounded at
      # `c3-audit-policy.yaml` → `c3_fix_loop.max_rechecks`) re-runs build-manifest/dispatch/
      # verify IN PLACE on every recheck — each iteration overwrites this same
      # `$evidence_dir/audit-report.json` (and `c3/c3-dispatch.json`) rather than writing a
      # per-attempt file. That means this hook, reading `$c3_report_file` at the evidence root
      # exactly as it always has, is ALREADY reading the CANONICAL (last-attempt) report —
      # whatever the loop's final outcome (clean, or still-blocking at recheck-budget
      # exhaustion), the content checks below see that final state. Per-attempt evidence
      # layering (a distinct file per attempt, preserving earlier attempts for audit trail) is
      # Step 17's job, not this hook's — no change needed here for that. `c3_recheck_count`
      # (if the run entered the fix loop) is read below, best-effort, purely to enrich the
      # `c3_gate_would_block` telemetry event below with how many rechecks preceded a block —
      # it does not participate in any pass/fail decision in this hook.

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

          # P065 Step 15 (E-065-5_7) — ADDITIVE ONLY: detect a degraded_advisory
          # same-provider Claude fallback report (agents/auditor.md `c3_advisory` mode,
          # dispatched by pipeline.md when c3-audit-policy.yaml's c3_on_unavailable ==
          # degraded_advisory). Read alongside the fields above so the elif chain below can
          # give it a MORE SPECIFIC reason than the generic unverifiable check — it does not
          # change what blocks, only how precisely the reason is reported.
          local c3_advisory="" c3_independence_level=""
          local c3_advisory_ec=0 c3_independence_level_ec=0
          c3_advisory=$(jq -r 'if (.audit_report.advisory | type) == "boolean" then (.audit_report.advisory | tostring) else "false" end' "$c3_report_file" 2>/dev/null) || c3_advisory_ec=$?
          [[ $c3_advisory_ec -ne 0 ]] && c3_advisory="false"
          c3_independence_level=$(jq -r '.audit_report.independence_level // ""' "$c3_report_file" 2>/dev/null) || c3_independence_level_ec=$?
          [[ $c3_independence_level_ec -ne 0 ]] && c3_independence_level=""

          if [[ "$c3_blocking" != "false" && "$c3_blocking" != "true" ]]; then
            # Covers missing/null/non-boolean .audit_report.blocking_findings — fail-closed,
            # deliberately NOT `// false` (that is the exact anti-pattern this hook replaces).
            c3_block_reason="audit-report.json .audit_report.blocking_findings is missing or not a boolean (fail-closed)"
          elif [[ "$c3_blocking" == "true" ]]; then
            c3_block_reason="audit-report.json .audit_report.blocking_findings == true (critical/high finding present)"
          elif [[ "$c3_advisory" == "true" || "$c3_independence_level" == "context_only" ]]; then
            # P065 Step 15 — checked BEFORE the generic unverifiable check below on purpose: an
            # advisory report always ALSO has status: unverifiable (see agents/auditor.md
            # "C3 Advisory Mode"), so without this branch first it would only ever surface the
            # generic reason, never this more actionable one. A genuine (non-advisory) c3 report
            # never sets .advisory:true or independence_level:context_only — c3-audit-policy.yaml
            # requires cross_model/cross_provider for the two c3_required profiles, so this
            # branch cannot fire on a real Codex pass/fail/unverifiable result.
            c3_block_reason="c3_advisory_not_independent: audit-report.json .audit_report.advisory=${c3_advisory} / .audit_report.independence_level=${c3_independence_level:-<empty>} (same-provider Claude fallback review — not an independent cross-provider/cross-model C3 audit)"
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
          #
          # P065 Step 16 — best-effort read of c3_recheck_count from fsm-state.yaml
          # (set via `aid-fsm.sh set-field c3_recheck_count <n> <state_file>` by
          # pipeline.md's fix→reverify loop; absent on any run that never entered the
          # loop, e.g. a clean first audit). Purely additive telemetry enrichment — it
          # does not affect c3_block_reason or the enforcement decision above/below.
          local c3_recheck_count
          c3_recheck_count=$(yaml_field "$state_file" c3_recheck_count)
          [[ -z "$c3_recheck_count" ]] && c3_recheck_count="0"
          log_event "$_c3_timeline" "c3_gate_would_block" \
            check="c3_independent_audit" enforcement="$c3_enforcement" \
            risk_profile="$c3_risk_profile" reason="$c3_block_reason" \
            c3_recheck_count="$c3_recheck_count"
          if [[ "$c3_enforcement" == "blocking" ]]; then
            echo "PRECONDITION FAIL: C3 independent audit block — ${c3_block_reason}." >&2
            echo "Risk profile '${c3_risk_profile}' requires a fresh, clean audit-report.json before release. See: ${c3_report_file}" >&2
            errors=$((errors + 1))
          else
            log_warn "C3 independent audit would_block (enforcement=observe, non-blocking): ${c3_block_reason}"
          fi
        fi
      fi

      # ── C3 dispatch-provenance enforcement hook (P065 Step 9 / E-065-3_7) ────
      # THE enforcement point P065 exists to build: under `enforcement: blocking`
      # a C3-required run may advance ONLY when c3/c3-dispatch.json proves a REAL,
      # verified Codex run at HEAD. This block is strictly ADDITIVE to the C3
      # independent-audit hook above — it does NOT replace or weaken any check
      # there. That hook validates the report's CONTENT
      # (blocking_findings/status/manifest/freshness); THIS hook validates the
      # DISPATCH PROVENANCE (that Codex genuinely ran) and — check #5, the
      # critical new enforcement — SHELLS OUT to `aid-c3-dispatch.sh verify` so
      # the full report↔raw faithful-transform binding (raw re-validation +
      # tuple/fingerprint equality) becomes part of the deterministic
      # MERGE-BLOCKING gate, not merely prose in pipeline.md. An edited/fabricated
      # report whose otherwise-intact c3-dispatch.json would pass checks 1–4 now
      # FAILS at the verify shell-out and can no longer pass this gate.
      #
      # Reasons are computed IN ORDER (first failing reason wins):
      #   1. c3/c3-dispatch.json absent (covers legacy pre-P065 runs — c3/ absent).
      #   2. dispatch did not genuinely succeed cross_provider (invoked!=true OR
      #      exit_code!=0 OR outcome!="dispatched" OR events_valid!=true OR empty
      #      codex_session_id).
      #   3. audit-report.json .audit_report.process_id != dispatch codex_session_id.
      #   4. audit-report.json .audit_report.reviewed_head != current HEAD (stale).
      #   5. `aid-c3-dispatch.sh verify <evidence_dir>` exits non-zero
      #      (report↔raw faithful-transform binding broken).
      #
      # Enforcement-gated exactly like the hook above (c3_enforcement, resolved
      # from c3-audit-policy.yaml near the top of this branch; C3_AUDIT_POLICY is
      # the test/CI seam). blocking → errors++ with the first failing reason;
      # observe → emit c3_dispatch_would_block telemetry only, no errors++.
      # Fail-closed under blocking: jq missing, or c3/c3-dispatch.json absent, is a
      # block reason (file existence alone is not proof). Every jq/verify command
      # substitution is guarded against `set -euo pipefail` abort.
      if [[ "$c3_hook_fired" == "true" ]]; then
        local c3_dispatch_block_reason=""
        local c3_dispatch_json="${evidence_dir}/c3/c3-dispatch.json"

        # P065 E-065-7_7 DONE-review Finding B follow-up (found by CP2 while
        # verifying the Finding B fix itself): AID_C3_ATTEMPT layering
        # (Step 17) writes c3-dispatch.json under c3/attempt-NN/c3/, never
        # mirroring it to this legacy root path — the exact same
        # evidence_dir/work_evidence_dir confusion Finding B fixed inside
        # aid-c3-dispatch.sh's own cmd_verify, but this hook reads the file
        # directly instead of going through cmd_verify for checks 1-4. Check
        # 5 below already shells out to `verify`, which is attempt-aware
        # since the Finding B fix and remains the authoritative validator
        # regardless of this resolution's own correctness — this snippet
        # only needs to get checks 1-4's PATH right, not re-validate
        # anything. Mirrors cmd_verify's own Step 0 resolution exactly
        # (same loop-summary.json current_attempt field, same zero-pad).
        if [[ -f "${evidence_dir}/c3/loop-summary.json" ]] && command -v jq >/dev/null 2>&1; then
          local _c3_hook_cur_attempt
          # Guarded like every other jq substitution in this function (see the
          # header comment above: "every jq/verify command substitution is
          # guarded against set -euo pipefail abort") — a malformed/partial
          # loop-summary.json (e.g. a truncated write) must fall through to
          # the legacy path below, not crash the whole done-advance call.
          _c3_hook_cur_attempt=$(jq -r '.current_attempt // empty' "${evidence_dir}/c3/loop-summary.json" 2>/dev/null) \
            || _c3_hook_cur_attempt=""
          if [[ "$_c3_hook_cur_attempt" =~ ^[1-9][0-9]*$ ]]; then
            local _c3_hook_cur_nn
            _c3_hook_cur_nn=$(printf '%02d' "$_c3_hook_cur_attempt")
            c3_dispatch_json="${evidence_dir}/c3/attempt-${_c3_hook_cur_nn}/c3/c3-dispatch.json"
          fi
        fi

        if ! command -v jq >/dev/null 2>&1; then
          # jq missing → cannot read provenance → fail-closed.
          c3_dispatch_block_reason="jq is required to verify c3-dispatch.json provenance and is not available"
        elif [[ ! -f "$c3_dispatch_json" ]]; then
          # Check 1: absent provenance (also the legacy pre-P065 run case — c3/ absent).
          c3_dispatch_block_reason="c3/c3-dispatch.json not found — no proof a real Codex audit was dispatched at HEAD"
        elif ! jq -e . "$c3_dispatch_json" >/dev/null 2>&1; then
          c3_dispatch_block_reason="c3/c3-dispatch.json is not valid/parseable JSON"
        else
          # Guard all reads against set -e abort (this script runs set -euo pipefail).
          local _d_invoked _d_exit _d_outcome _d_events _d_session
          local _di_ec=0 _de_ec=0 _do_ec=0 _dev_ec=0 _ds_ec=0
          _d_invoked=$(jq -r '.dispatch.invoked | tostring' "$c3_dispatch_json" 2>/dev/null) || _di_ec=$?
          [[ $_di_ec -ne 0 ]] && _d_invoked="MISSING"
          _d_exit=$(jq -r '.dispatch.exit_code | tostring' "$c3_dispatch_json" 2>/dev/null) || _de_ec=$?
          [[ $_de_ec -ne 0 ]] && _d_exit="MISSING"
          _d_outcome=$(jq -r '.dispatch.outcome // "MISSING"' "$c3_dispatch_json" 2>/dev/null) || _do_ec=$?
          [[ $_do_ec -ne 0 ]] && _d_outcome="MISSING"
          _d_events=$(jq -r '.dispatch.events_valid | tostring' "$c3_dispatch_json" 2>/dev/null) || _dev_ec=$?
          [[ $_dev_ec -ne 0 ]] && _d_events="MISSING"
          _d_session=$(jq -r '.dispatch.codex_session_id // ""' "$c3_dispatch_json" 2>/dev/null) || _ds_ec=$?
          [[ $_ds_ec -ne 0 ]] && _d_session=""

          # audit-report.json provenance fields (process_id / reviewed_head).
          local _r_pid _r_reviewed_head _rp_ec=0 _rrh_ec=0 _c3_dp_head=""
          _r_pid=$(jq -r '.audit_report.process_id // ""' "$c3_report_file" 2>/dev/null) || _rp_ec=$?
          [[ $_rp_ec -ne 0 ]] && _r_pid=""
          _r_reviewed_head=$(jq -r '.audit_report.reviewed_head // ""' "$c3_report_file" 2>/dev/null) || _rrh_ec=$?
          [[ $_rrh_ec -ne 0 ]] && _r_reviewed_head=""
          _c3_dp_head=$(git -C "$project_root" rev-parse HEAD 2>/dev/null || echo "")

          if [[ "$_d_invoked" != "true" || "$_d_exit" != "0" || "$_d_outcome" != "dispatched" \
                || "$_d_events" != "true" || -z "$_d_session" || "$_d_session" == "null" ]]; then
            # Check 2: dispatch did not genuinely succeed (covers rate_limited /
            # unavailable / timeout outcomes, invoked:false, events_valid:false, ...).
            c3_dispatch_block_reason="c3-dispatch.json does not prove a successful Codex run (invoked=${_d_invoked}, exit_code=${_d_exit}, outcome=${_d_outcome}, events_valid=${_d_events}, session='${_d_session}')"
          elif [[ -z "$_r_pid" || "$_r_pid" != "$_d_session" ]]; then
            # Check 3: report's process_id must bind to the dispatch session.
            c3_dispatch_block_reason="audit-report.json .audit_report.process_id ('${_r_pid}') != c3-dispatch.json codex_session_id ('${_d_session}')"
          elif [[ -z "$_r_reviewed_head" || -z "$_c3_dp_head" || "$_r_reviewed_head" != "$_c3_dp_head" ]]; then
            # Check 4: report must have reviewed the CURRENT HEAD (freshness).
            c3_dispatch_block_reason="audit-report.json .audit_report.reviewed_head ('${_r_reviewed_head:-<empty>}') != current HEAD ('${_c3_dp_head:-<empty>}') — stale audit"
          else
            # Check 5 (THE enforcement fix): shell out to the verify command — the
            # full report↔raw faithful-transform binding. A fabricated/edited report
            # whose c3-dispatch.json would pass checks 1–4 FAILS here. Guarded so a
            # non-zero exit is treated as a block reason, never a set -e crash.
            local _c3_verify_bin="${AID_C3_DISPATCH_BIN:-${SCRIPT_DIR}/lib/aid-c3-dispatch.sh}"
            local _c3_verify_out="" _c3_verify_rc=0
            _c3_verify_out=$(bash "$_c3_verify_bin" verify "$evidence_dir" 2>&1) || _c3_verify_rc=$?
            if [[ "$_c3_verify_rc" -ne 0 ]]; then
              c3_dispatch_block_reason="aid-c3-dispatch.sh verify failed (report↔raw faithful-transform binding broken, exit ${_c3_verify_rc}): ${_c3_verify_out}"
            fi
          fi
        fi

        if [[ -n "$c3_dispatch_block_reason" ]]; then
          # Always emit c3_dispatch_would_block so the gate is observable in both
          # modes; then blocking → errors++, observe → telemetry only (matches the
          # C3 independent-audit hook's would_block convention above).
          log_event "$_c3_timeline" "c3_dispatch_would_block" \
            check="c3_dispatch_provenance" enforcement="$c3_enforcement" \
            risk_profile="$c3_risk_profile" reason="$c3_dispatch_block_reason"
          if [[ "$c3_enforcement" == "blocking" ]]; then
            echo "PRECONDITION FAIL: C3 dispatch provenance block — ${c3_dispatch_block_reason}." >&2
            echo "Risk profile '${c3_risk_profile}' requires a verified Codex dispatch (c3/c3-dispatch.json) proving a real, faithful audit at HEAD. See: ${c3_dispatch_json}" >&2
            errors=$((errors + 1))
          else
            log_warn "C3 dispatch provenance would_block (enforcement=observe, non-blocking): ${c3_dispatch_block_reason}"
          fi
        fi
      fi

      # (Step 4 CP2 finding 1 moved the legacy `blocking_findings` .md/.yaml read
      # OUT of this block to just ABOVE the plan_branch skip guard, beside the
      # pm_decision and task-file-archived checks — it is an EPIC-LOCAL verdict
      # about this EPIC's own diff and must keep blocking in BOTH modes. Its C3
      # SSOT deferral is preserved there, scoped to the legacy path where the C3
      # hook above actually runs. Search: "the auditor's `blocking_findings`
      # verdict (EPIC-LOCAL, BOTH modes)".)

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

      fi
      # ══ End of the plan_branch-skipped release stack (P064 plan Step 9) ═════
      # `errors` below is still the complete verdict: in plan_branch mode the
      # retained EPIC-local checks are the only contributors to it, and every
      # one of them either sets `errors` or hard-exits on its own.

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

  # Derive plan_id through the ONE shared helper (`_fsm_epic_plan_nnn`, top of
  # this file): E-046-2_3 -> 046 -> P046, E-013-1 -> 013 -> P013. This used to
  # be a fourth copy of `grep -oP '(?<=^E-)\d+'`, which FAILS (not "no match")
  # on a grep without PCRE support — here that surfaced as a bare grep error
  # under `set -e`. An id that derives no digits is now refused by name.
  local nnn; nnn="$(_fsm_epic_plan_nnn "$epic_id")"
  [[ -n "$nnn" ]] || { echo "ERROR: plan-close: cannot derive a plan id from epic_id '${epic_id}' (expected E-<NNN>-...)." >&2; exit 1; }
  local plan_id="P${nnn}"

  # ── P068 E-068-1_2 Step 6: delegate the PLAN BOUNDARY to the plan layer ───
  # For a `plan_branch` plan the real close is a transaction, not a marker: it
  # reconciles the legacy marker world this function owns with the git-tracked
  # `.aid-lifecycle` receipt world, and it may only pass after the merge or a
  # recorded abort. `aid-plan-fsm.sh plan-close` is that transaction.
  #
  # The delegation is DELIBERATELY scoped to a plan that has actually reached
  # its boundary (PLAN_MERGING / ABORTED / CLOSED). An INTERMEDIATE EPIC of a
  # plan_branch plan merges into `plan/<plan_id>` long before the plan boundary
  # exists, and it still needs this function's ordinary per-EPIC report checks;
  # delegating for it would fail the EPIC on a plan-level precondition that is
  # not yet meant to hold. On success the EPIC's own `ca-review-complete` marker
  # is still written, so nothing downstream of this function changes shape.
  # The MODE comes from the ONE declared source (`_fsm_declared_plan_mode`, the
  # git-tracked lifecycle manifest on target_branch) — never from the runtime
  # plan-boundary manifest. CP3-F2 made that a structural invariant precisely so
  # two mode sources can never disagree, and plan-close is not an exception.
  # Read execution.yaml toggles — grep-only, no yq dependency. Read BEFORE the
  # plan-layer delegation (CP2 M5): the delegated path used to return before
  # this, so a project with reporter.enabled:false hard-failed the plan layer's
  # Check 1 ("report never generated") with no reachable remedy.
  local exec_yaml="${project_root}/.aid-o/config/execution.yaml"
  local simplifier_enabled=true
  local reporter_enabled=true
  _aid_read_toggle "$exec_yaml" "simplifier" || simplifier_enabled=false
  _aid_read_toggle "$exec_yaml" "reporter" || reporter_enabled=false

  local _pb_plan_layer_closed=0

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

  # ── The plan-layer close transaction — AFTER the evidence gate above ──────
  # Ordering is the whole point. The plan-layer close is IRREVERSIBLE: it commits
  # a lifecycle receipt, writes plan-close-complete and moves the plan to CLOSED.
  # Running it before the required-report checks meant a plan could be
  # permanently closed in the books and only then fail on a missing Curator or
  # Auditor report — the exact split between recorded state and reality that this
  # whole plan boundary exists to prevent. Nothing durable is written until every
  # required report for this EPIC is present.
  local _pb_mode_row _pb_mode=""
  _pb_mode_row="$(_fsm_declared_plan_mode "$epic_id" 2>/dev/null || true)"
  _pb_mode="${_pb_mode_row%%$'\t'*}"
  if [[ "$_pb_mode" == "plan_branch" ]]; then
    local _pb_state_file="${project_root}/.aid-o/work/plan-state/${plan_id}/plan-state.yaml"
    local _pb_state=""
    [[ -f "$_pb_state_file" ]] && _pb_state="$(yaml_field "$_pb_state_file" plan_state)"
    case "$_pb_state" in
      ROLLED_BACK)
        # A rolled-back plan is already terminal and was closed by plan-rollback,
        # which has its own marker and its own durable record. Sending it to
        # plan-close would refuse (close runs out of PLAN_MERGING or a recorded
        # abort) and, worse, would imply the plan still owed a closure it has
        # already had. The EPIC's own evidence is still checked below — the plan
        # being rolled back says nothing about whether this EPIC did its work.
        echo "NOTE: plan-close: ${plan_id} is ROLLED_BACK — its plan-layer closure is the rollback record, so no plan-close is attempted. The EPIC's own required reports are still checked." >&2
        _pb_plan_layer_closed=1
        ;;
      PLAN_MERGING|ABORTED|CLOSED)
        local -a _pb_close_args=("$plan_id" --project-root "$project_root")
        [[ "$reporter_enabled" == "false" ]] && _pb_close_args+=(--skip-delivery-report)
        if ! "${SCRIPT_DIR}/aid-plan-fsm.sh" plan-close "${_pb_close_args[@]}"; then
          echo "PRECONDITION FAIL: plan-close: the plan-layer close transaction refused ${plan_id} — no EPIC marker was written." >&2
          exit 1
        fi
        # The plan-layer close is a PRECONDITION for the EPIC marker, never a
        # substitute for the EPIC's own evidence (CP2 M4). It is idempotent, so a
        # crash between it and the marker below converges on re-run: the second
        # pass finds the plan already CLOSED, writes no second receipt, and
        # completes the marker.
        _pb_plan_layer_closed=1
        ;;
    esac
  fi

  # Mechanical plan-close self-check (aid-plan-close-check.sh) — replaces the
  # PM's repeated manual audits (stale/untracked reports, DONE-but-pending
  # fsm-state, stale queue/active.md) with a hard gate here. --auto-annotate
  # only lets the script's own Check 2 fix the safe docs-only-stale-report
  # case; it is not a general cleanup pass. A failure here blocks
  # ca-review-complete exactly like a missing report above.
  #
  # The checker ALWAYS runs, even when reporter.enabled:false — skipping it
  # entirely would also skip Checks 2-4 (Head freshness, fsm-state DONE-
  # pending, queue/active revalidation), none of which have anything to do
  # with the delivery report. Only the delivery-report existence requirement
  # (Check 1) is relaxed via --skip-delivery-report, matching the toggle this
  # function already honors a few lines up without widening the skip.
  local -a _plan_close_check_flags=(--auto-annotate)
  if [[ "$reporter_enabled" == "false" ]]; then
    _plan_close_check_flags+=(--skip-delivery-report)
    log_event "$audit_log" "plan_close_skip" specialist="plan-close-check-delivery-report" rationale="reporter.enabled:false in execution.yaml (delivery-report existence only; Checks 2-4 still run)"
  fi
  if [[ "$_pb_plan_layer_closed" -eq 1 ]]; then
    log_event "$audit_log" "plan_close_skip" specialist="plan-close-check-rerun" rationale="the plan-layer close transaction already ran aid-plan-close-check.sh --plan-branch, which is a strict superset of this invocation"
  elif ! "${SCRIPT_DIR}/aid-plan-close-check.sh" "$plan_id" --project-root "$project_root" "${_plan_close_check_flags[@]}"; then
    echo "PRECONDITION FAIL: aid-plan-close-check.sh reported a blocking issue for ${plan_id}" >&2
    echo "Use 'aid-fsm.sh plan-close' — do NOT create this marker with touch." >&2
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
#
# P064 Step 7 amends outputs 1-3 for an entry that declares a `merge_target`
# (written by lib/aid-queue-write.sh): ancestry is checked against THAT ref
# instead of the main|master|HEAD guess, and outputs 3's evidence-based
# fallback chain is unavailable — a plan-branch dependency is proven by
# ancestry or it is blocked. Registry: plan_branch_merge_target.

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
      } else if (key == "plan_id" || key == "merge_target") {
        # P064 Step 7 — the two fields lib/aid-queue-write.sh adds. Emitted as
        # strings exactly like `status` (the YAML literal `null` therefore
        # arrives as the four-character string "null", which the bash side
        # treats as absent — see _queue_entry_merge_target).
        printf ",\"%s\":\"%s\"", key, val
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
#
# P064 Step 7 NOTE: this is now the FALLBACK only, used for a queue entry that
# declares no `merge_target`. It is exactly the guess that made an EPIC merged
# into `plan/Pxxx` but not yet released report `blocked` forever — see
# _queue_entry_merge_target below for the declared-target path that supersedes
# it.
_queue_merge_target() {
  if git show-ref --verify --quiet refs/heads/main; then echo main
  elif git show-ref --verify --quiet refs/heads/master; then echo master
  else echo HEAD; fi
}

# _queue_entry_merge_target <dep> <queue_json> — the ref THIS dependency
# declares it was (or will be) merged into: `plan/<plan_id>` while its plan is
# open, the target branch once the plan is released to main. Empty when the
# entry carries no merge_target (a legacy, pre-P064 entry) — that empty answer
# is what re-enables the fallback chain below.
_queue_entry_merge_target() {
  local dep="$1" queue_json="$2" mt
  mt=$(echo "$queue_json" | jq -r --arg d "$dep" \
    '[.[] | select(.epic_id==$d) | (.merge_target // "")] | .[0] // ""' 2>/dev/null)
  [[ "$mt" == "null" || "$mt" == "~" ]] && mt=""
  printf '%s' "$mt"
}

# _queue_entry_plan_id <dep> <queue_json> — the `plan_id` THIS dependency
# declares it belongs to. Empty when the entry carries no plan_id, or carries
# the YAML literal `null` (which _queue_parse_to_json emits as the four-char
# string "null" — see the awk block above). Used only to decide, in
# _dep_merge_target_authorized, whether a declared `plan/<x>` target names the
# entry's OWN plan.
_queue_entry_plan_id() {
  local dep="$1" queue_json="$2" pid
  pid=$(echo "$queue_json" | jq -r --arg d "$dep" \
    '[.[] | select(.epic_id==$d) | (.plan_id // "")] | .[0] // ""' 2>/dev/null)
  [[ "$pid" == "null" || "$pid" == "~" ]] && pid=""
  printf '%s' "$pid"
}

# _dep_merge_target_authorized <declared> <dep> — IMP-272 (+ HIGH hardening).
#
# A `merge_target` is read straight out of the hand-editable queue file, and
# ancestry is proven AGAINST it — so a value the attacker controls is the ref
# the proof is anchored to. `_dep_valid_branch_ref` only asks "is this a legal
# ref name?"; it happily accepts the dependency's OWN task branch, whose
# ancestry against itself is trivially true, so pointing a dependency at
# `task/<its own id>/main` self-satisfied the check and unblocked work that was
# provably never in `plan/<plan>`. This predicate constrains the value to the
# only two refs the substrate ever legitimately writes there:
#   * `plan/<id-derived plan>` — a same-plan dependency, still on its plan branch;
#   * the resolved target branch (`_queue_merge_target`) — a cross-plan
#     dependency already released to main/master.
# Any OTHER ref that resolves (an EPIC task branch, another plan's branch, an
# arbitrary feature branch) is refused fail-loud by the caller, never treated
# as proof. An entry with `plan_id: null` has no owning plan, so `plan/<...>` is
# impossible for it and only the target branch is legal.
#
# IMP-272 HARDENING (post-review HIGH): the owning plan MUST be derived from
# the dependency's epic id — the record KEY, bound to the very identity the
# ancestry check runs against — NOT read from the entry's own `plan_id` field.
# Both `merge_target` and `plan_id` are hand-editable values in the same entry,
# so trusting `plan_id` let an attacker set `plan_id: P999` + `merge_target:
# plan/P999` and have the substrate agree `plan/P999` was "its own" plan branch,
# self-authorizing the anchor again one field over. `_dep_derived_plan` derives
# `P<nnn>` from the epic id (empty for an ad-hoc id that names no plan), and the
# entry's declared `plan_id`, when present, is fail-closed cross-checked against
# that derivation by the caller — a disagreement is corruption/attack, refused.
#
# CONTRACT TWIN of lib/aid-queue-write.sh:_queue_merge_target_authorized, which
# enforces the same rule for the WRITE side (queue_claim_next). CHANGE BOTH.
_dep_derived_plan() {
  local nnn; nnn="$(_fsm_epic_plan_nnn "${1:-}")"
  [[ -n "$nnn" ]] && printf 'P%s' "$nnn"
}
_dep_merge_target_authorized() {
  local declared="$1" dep="$2"
  [[ "$declared" == "$(_queue_merge_target)" ]] && return 0
  local derived; derived="$(_dep_derived_plan "$dep")"
  [[ -n "$derived" && "$declared" == "plan/${derived}" ]] && return 0
  return 1
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

# _dep_valid_branch_ref <ref> — is <ref> a name git itself accepts?
#
# CONTRACT TWIN of lib/aid-queue-write.sh:_queue_valid_branch_ref, byte for
# byte in behaviour (CP2 iteration 2, finding 2). The writer used to apply a
# hand-rolled `^[A-Za-z0-9][A-Za-z0-9._/-]*$` here and this reader applied
# NOTHING, so for a dep that ran on a git-legal but regex-illegal branch — the
# verifier's repro is `_wip` — `queue-revalidate` said `unblocked` while
# `queue_claim_next` wrote `dependency_no_ancestry_proof` on the same fact.
# `git check-ref-format` is the authority precisely so neither half can drift
# from git again. On top of it: a leading `-` is refused (git accepts it as a
# ref name, but `git merge-base --is-ancestor "$ref" …` would read it as an
# OPTION), as is a `"`/backslash/control character, so the name stays safe if
# it is ever written back into the queue as a YAML scalar. CHANGE BOTH.
_dep_valid_branch_ref() {
  local r="${1:-}"
  [[ -n "$r" ]]                     || return 1
  [[ "$r" != -* ]]                  || return 1
  [[ "$r" != *'"'* ]]               || return 1
  [[ "$r" != *'\'* ]]               || return 1
  [[ "$r" != *[$'\001'-$'\037']* ]] || return 1
  [[ "$r" != *$'\177'* ]]           || return 1
  git check-ref-format "refs/heads/${r}" >/dev/null 2>&1
}

# _resolve_dep_branch <dep> — echo the LIVE branch to ancestor-check for a dep:
# the task/<dep>/main convention if it exists, else the evidence fsm-state
# branch field if that ref exists (never main/master — a legacy branch:main
# would false-unblock). Empty = branch deleted (merged-detection path).
#
# CONTRACT TWIN: lib/aid-queue-write.sh:_queue_resolve_dep_branch implements
# this same rule for the WRITE side (queue_claim_next). The two halves must
# answer the same question the same way — a writer that knew only the
# task/<dep>/main convention wrote `blocked:…:dependency_no_ancestry_proof` on
# a dep this reader reported `unblocked`, leaving the dependent unclaimable
# through the queue while the FSM said it was ready (CP2 finding 3). aid-fsm.sh
# is a command script, not a sourceable library, so the rule is duplicated
# rather than shared: CHANGE BOTH.
_resolve_dep_branch() {
  local dep="$1"
  local conv="task/${dep}/main"
  if _dep_valid_branch_ref "$conv" \
     && git show-ref --verify --quiet "refs/heads/${conv}"; then echo "$conv"; return 0; fi
  local ev; ev=$(_dep_evidence_branch "$dep")
  if [[ -n "$ev" && "$ev" != "main" && "$ev" != "master" ]] \
     && _dep_valid_branch_ref "$ev" \
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

  # ── P064 Step 7: a DECLARED merge_target changes both the ref and the rules ─
  # For an entry that carries `merge_target`, ancestry against THAT ref is the
  # only accepted answer. The evidence-based fallback chain further down (queue
  # `status: completed`, an evidence `state: DONE`, a merge-log grep) is
  # unavailable to it — every one of those is a claim ABOUT a merge rather than
  # the merge itself, and `status: completed` in particular has only ever been
  # written by hand. A queue entry is a derived view, never evidence.
  local declared; declared=$(_queue_entry_merge_target "$dep" "$queue_json")

  local target
  if [[ -n "$declared" ]]; then
    # A merge_target read out of the hand-editable queue file is untrusted
    # input (CP2 iteration 2, LOW note): validate it with the same predicate as
    # the writer BEFORE it becomes an argv element of `git`, where a leading
    # `-` would be read as an option. An unusable target is the same broken
    # record as a non-resolving one — reported, never treated as proof.
    if ! _dep_valid_branch_ref "$declared"; then
      log_event "$timeline_path" "queue_dep_unresolved" \
        epic_id="$dep" reason="merge_target_invalid"
      echo "failed"; return 1
    fi
    if ! git rev-parse --verify --quiet "${declared}^{commit}" >/dev/null 2>&1; then
      # A declared target that does not resolve is a broken record, not a
      # "blocked" answer — treating it as blocked would hide it forever.
      log_event "$timeline_path" "queue_dep_unresolved" \
        epic_id="$dep" reason="merge_target_missing" merge_target="$declared"
      echo "failed"; return 1
    fi
    # IMP-272: syntactic legality is not authorization. A merge_target may only
    # be the entry's own plan branch or the resolved target branch; any OTHER
    # resolvable ref (the dep's own task branch, another plan's branch, a
    # feature branch) would self-satisfy the ancestry check, so it is refused
    # fail-loud rather than believed. reason names the illegal value class.
    # ORDER MATTERS (IMP-272 review finding): resolvability is checked FIRST,
    # exactly like the writer twin (_queue_dep_state), so a target that is both
    # unauthorized and non-resolving yields the SAME reason class on both
    # halves (target_missing/merge_target_missing), never divergent codes for
    # one queue state. CHANGE BOTH.
    # Fail-closed cross-check (post-review HIGH): if the entry declares a
    # plan_id, it MUST agree with the id-derived plan; a disagreement means the
    # hand-editable plan_id was set to launder an unauthorized merge_target and
    # is refused. An absent plan_id (legacy entry) skips this and relies on the
    # derivation-based authorization below.
    local _decl_pid _der_plan
    _decl_pid="$(_queue_entry_plan_id "$dep" "$queue_json")"
    _der_plan="$(_dep_derived_plan "$dep")"
    if [[ -n "$_decl_pid" && "$_decl_pid" != "$_der_plan" ]]; then
      log_event "$timeline_path" "queue_dep_unresolved" \
        epic_id="$dep" reason="merge_target_unauthorized" merge_target="$declared" \
        declared_plan="$_decl_pid" derived_plan="$_der_plan"
      echo "failed"; return 1
    fi
    # IMP-272: syntactic legality is not authorization. A merge_target may only
    # be the entry's own (id-DERIVED) plan branch or the resolved target branch;
    # any OTHER resolvable ref (the dep's own task branch, another plan's branch,
    # a feature branch) would self-satisfy the ancestry check, so it is refused
    # fail-loud rather than believed. The owning plan is derived from the epic
    # id, never read from the entry's own plan_id field. ORDER MATTERS (IMP-272
    # review finding): resolvability is checked FIRST, exactly like the writer
    # twin (_queue_dep_state), so a target that is both unauthorized and
    # non-resolving yields the SAME reason class on both halves. CHANGE BOTH.
    if ! _dep_merge_target_authorized "$declared" "$dep"; then
      log_event "$timeline_path" "queue_dep_unresolved" \
        epic_id="$dep" reason="merge_target_unauthorized" merge_target="$declared"
      echo "failed"; return 1
    fi
    target="$declared"
  else
    target=$(_queue_merge_target)
  fi

  local branch; branch=$(_resolve_dep_branch "$dep")

  if [[ -n "$branch" ]]; then
    local rc=0
    git merge-base --is-ancestor "$branch" "$target" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0)  # output 1: branch exists + is ancestor → merged → unblock
        log_event "$timeline_path" "queue_dep_revalidated" \
          epic_id="$dep" resolution="ancestor" branch="$branch" merge_target="$target"
        echo "unblocked"; return 0 ;;
      1)  # output 2: branch exists + NOT ancestor → genuinely unmerged → blocked
        log_event "$timeline_path" "queue_dep_blocked" \
          epic_id="$dep" branch="$branch" merge_target="$target"
        echo "blocked"; return 0 ;;
      *)  # 128 = bad-ref/fatal → do NOT crash; fall through to merged-detection
        if [[ -n "$declared" ]]; then
          log_event "$timeline_path" "queue_dep_unresolved" \
            epic_id="$dep" reason="ancestry_check_failed" merge_target="$target" branch="$branch"
          echo "failed"; return 1
        fi
        : ;;
    esac
  fi

  if [[ -n "$declared" ]]; then
    # Declared target, no live branch to prove ancestry with. A deleted branch
    # is not proof, and neither is a hand-edited `completed`. This is a
    # determinate "not merged", not a fail-loud: the answer is knowable and it
    # is "no".
    log_event "$timeline_path" "queue_dep_blocked" \
      epic_id="$dep" merge_target="$target" reason="no_ancestry_proof"
    echo "blocked"; return 0
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
    # IMP-232 lifecycle (v2.58.1) — delegate to the sourced lib so the surface the
    # init advisory + docs reference actually exists on aid-fsm.sh.
    plan-reconcile)             shift
                                _pr_id="${1:-}"; shift || true; _pr_apply=false; _pr_root="."
                                for _a in "$@"; do case "$_a" in --apply) _pr_apply=true ;; --dry-run) _pr_apply=false ;; *) _pr_root="$_a" ;; esac; done
                                [[ -n "$_pr_id" ]] || { echo "Usage: aid-fsm.sh plan-reconcile <plan_id> [--dry-run|--apply] [root]" >&2; exit 1; }
                                aid_lifecycle_plan_reconcile "$_pr_id" "$_pr_root" "$_pr_apply" ;;
    plan-record-delivery)       shift
                                [[ -n "${1:-}" ]] || { echo "Usage: aid-fsm.sh plan-record-delivery <epic_id> [root]" >&2; exit 1; }
                                aid_lifecycle_record_delivery "$1" "${2:-.}" ;;
    plan-state)                 shift
                                [[ -n "${1:-}" ]] || { echo "Usage: aid-fsm.sh plan-state <plan_id> [root]" >&2; exit 1; }
                                aid_plan_closure_state "$1" "${2:-.}" ;;
    *)
      echo "Usage: aid-fsm.sh <init|transition|advance-to-gates|get-state|verify-state|increment-step|get-field|set-field|done-advance|promote-check|check-promotion-candidates|plan-close|plan-reconcile|plan-record-delivery|plan-state|queue-revalidate> [args...]" >&2
      exit 1 ;;
  esac
fi
