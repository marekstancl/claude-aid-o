#!/usr/bin/env bash
# =============================================================================
# aid-cp1-gate.sh — CP1-deep evidence gate for high-risk plans
#
# Usage:
#   ./aid-cp1-gate.sh --plan <path> [--project-root <path>]
#
# For low-risk plans: exits 0 immediately (no evidence required).
# For high-risk plans: verifies that all 4 CP1-deep evidence files exist,
# that the adjudicator verdict has no unresolved accepted blockers, that a
# verified C0 cross-provider Codex plan review exists with no surviving
# blocking findings, and that the CP1 revision-limit ledger has budget left
# (P065 E-065-7_7 Step 20 — see "C0 review + CP1 ledger gate" below).
#
# Ceremony band (P084 Step 1) — full | medium | light
#
# The band is classified from the paths the plan's steps DECLARE in their
# **Files:** blocks, read with the SAME parser the generator and the plan lint
# use (lib/aid-scoping.sh), matched against the curated path map
# defaults/policies/risk-paths.yaml. It is NOT a grep over the document: the
# earlier whole-file pattern scan matched Context, Architecture and prose, so
# every plan came out high-risk (measured 2026-08-16: 5-33 hits on each of six
# live plans) and the ceremony was never proportional to anything.
#
#   full   — the plan touches decision machinery (state machines, gate runner,
#            generation chain, release boundary, plan contract, auth, migrations,
#            dependency manifests). Today's behaviour, unchanged.
#   medium — the DATA those decisions read: policies, schemas, templates,
#            machine-read config, CI. NOT tests and not ordinary code: those
#            are `light` and are reviewed per step, against a real diff.
#   light  — documentation, help, commands, skills: no evidence required.
#
# Two rules decide correctness, both deliberate:
#   1. Release/ceremony files (CHANGELOG.md, README.md, marketplace.json,
#      plugin.json) are EXCLUDED before matching — every plan ends in a release,
#      so counting them as reach would reproduce the very defect above.
#   2. Frontmatter `risk: high` raises the band to `full`, and nothing lowers a
#      band except changing the declared paths.
#
# What each band REQUIRES is not decided here: aid-cp1-gate.sh reads it from
# defaults/policies/review-checkpoints.yaml -> review_checkpoints.ceremony_bands
# (cp1_deep_lenses / c0_cross_provider / cp1_ledger). `full` requires all three
# and is today's behaviour unchanged; `medium` keeps the CP1-deep lenses and
# adjudicator but owes no cross-provider C0 review and no ledger; `light` owes
# nothing and the gate exits at once.
#
# Fail-closed cases, all landing on `full`: a plan that declares no path at all
# (`no_files_declared`), a missing path map (`no_risk_map`), an unparseable one
# (`unreadable_risk_map`) and a host without yq (`no_yq`). There is deliberately
# NO "guess from the prose" fallback: the whole-document scan this replaced
# returns `light` for a plan that declares aid-run-gates.sh but says nothing
# alarming in prose, which is the one direction that must never happen.
#
# Evidence dir: <project_root>/.aid-o/work/evidence/<plan_id>/cp1-deep/
# Required files (all 4 must exist, be non-empty, and contain required fields):
#   cp1-lens-L1-behavior.md     — L1: behavior/user-flow/edge cases; must have stop_rule_blockers:
#   cp1-lens-L2-feasibility.md  — L2: feasibility/file-contracts/producer→consumer; must have stop_rule_blockers:
#   cp1-lens-L3-enforcement.md  — L3: enforcement/CI/artifact-visibility/testability; must have stop_rule_blockers:
#   cp1-adjudicator.md          — adjudicator verdict; must have verdict: at line-start
#
# Adjudicator check: reads cp1-adjudicator.md and fails if verdict is fail|revise
# or if accepted_blockers: is non-empty. Empty accepted_blockers + verdict:pass = pass.
#
# ---------------------------------------------------------------------------
# C0 review + CP1 ledger gate (P065 E-065-7_7 Step 20)
# ---------------------------------------------------------------------------
# For a high-risk plan, AFTER the 4-file CP1-deep evidence + adjudicator
# checks above pass, two further mechanical requirements are enforced,
# mirroring the C3 fix->reverify loop's terminal-outcome guard pattern
# (aid-c3-dispatch.sh / pipeline.md §6a) at plan level:
#
#   1. C0 cross-provider plan review — a real second-provider (Codex) pass
#      over the FINAL plan MUST exist and MUST be provably genuine:
#        - <plan_evidence_root>/c0-plan-review.json must be present
#        - its review_status must NOT be "unverifiable"
#        - its blocking_findings must NOT be true
#        - `aid-c0-plan-review.sh verify <plan_evidence_root>` (the SAME
#          verify subcommand aid-c0-plan-review.sh ships, Step 18) must exit
#          0 — this is what makes the provenance/raw-binding check a CODE
#          gate, not prose: a hand-edited or stale c0-plan-review.json fails
#          `verify` even if its top-level fields look clean.
#      <plan_evidence_root> is `.aid-o/work/evidence/<plan_id>/` — the SAME
#      root aid-c0-plan-review.sh writes/reads (one level ABOVE cp1-deep/).
#
#   2. CP1 revision-limit ledger budget — `aid-cp1-ledger.sh check-budget`
#      must report an available budget (exit 0). A missing/corrupt ledger
#      with CP1-deep evidence already present is FAIL-CLOSED by that script
#      (never a silent reset) and therefore blocks here too.
#
# Either requirement's failure can be bypassed ONLY by an explicit,
# ONE-SHOT PM-escalation override artifact at
# `<plan_evidence_root>/cp1-pm-escalation-override.json` — see
# `_cp1_check_pm_override` / `_cp1_claim_pm_override` below. Once consumed to bypass a failure, the
# override file is renamed to `<...>.consumed-<epoch>` so it cannot silently
# authorize a second bypass (mirrors "the override permits exactly one more
# attempt", plan Error Handling section).
#
# Test seams (mirror aid-c0-plan-review.sh's AID_C0_INDEPENDENCE_BIN/
# AID_C0_RENDER_BIN convention): AID_CP1_GATE_C0_REVIEW_BIN /
# AID_CP1_GATE_LEDGER_BIN let tests substitute a stub for the real scripts
# without needing a full git+codex fixture. Production callers never set
# these — the real scripts are always used.
#
# stdout: human-readable status lines
# stderr: JSON error on failure (consistent with other AID scripts)
# Exit codes: 0=pass or not-applicable, 1=gate failure, 2=usage error, 3=I/O error
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/aid-plan-band.sh
source "${SCRIPT_DIR}/lib/aid-plan-band.sh"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

CP1_CHECKPOINTS_DEFAULT="${AID_PLUGIN_PATH:-${SCRIPT_DIR}/..}/defaults/policies/review-checkpoints.yaml"

CP1_GATE_C0_REVIEW_BIN="${AID_CP1_GATE_C0_REVIEW_BIN:-${SCRIPT_DIR}/lib/aid-c0-plan-review.sh}"
CP1_GATE_LEDGER_BIN="${AID_CP1_GATE_LEDGER_BIN:-${SCRIPT_DIR}/lib/aid-cp1-ledger.sh}"

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
plan=""
project_root=""
classify_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)          plan="$2";         shift 2 ;;
    --project-root)  project_root="$2"; shift 2 ;;
    --classify-only) classify_only=1;   shift ;;
    --help|-h)
      echo "Usage: $(basename "$0") --plan <path> [--project-root <path>] [--classify-only]"
      echo ""
      echo "Options:"
      echo "  --plan <path>          Path to the plan .md file (required)"
      echo "  --project-root <path>  Project root containing .aid-o/ (default: cwd)"
      echo "  --classify-only        Print the ceremony band (full|medium|light) on"
      echo "                         stdout and exit 0 without running the gate"
      echo "  --help                 Show this help"
      exit 0
      ;;
    *)
      error_exit "Unknown argument: $1" 2
      ;;
  esac
done

[[ -z "$plan" ]] && error_exit "Missing required argument: --plan" 2
[[ ! -f "$plan" ]] && error_exit "Plan file not found: $plan" 3

# Default project root to cwd
[[ -z "$project_root" ]] && project_root="$(pwd)"

# ---------------------------------------------------------------------------
# Step 1: Extract plan ID from frontmatter
# ---------------------------------------------------------------------------
plan_id=""

# State machine: only read inside the YAML frontmatter block (first --- to closing ---).
# Plans without a closing --- are treated as having no frontmatter (body is not parsed as FM).
in_frontmatter=0
frontmatter_done=0
while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ "$in_frontmatter" -eq 0 ]]; then
    [[ "$line" == "---" ]] && in_frontmatter=1
    continue
  fi
  # Inside frontmatter: stop at closing ---
  if [[ "$line" == "---" ]]; then
    frontmatter_done=1
    break
  fi
  if [[ "$line" =~ ^id:[[:space:]]*(.+)$ ]]; then
    plan_id="${BASH_REMATCH[1]}"
    plan_id="$(echo "$plan_id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
done < "$plan"

# Require a properly closed frontmatter block.
[[ "$frontmatter_done" -eq 0 ]] && error_exit "Plan file missing closing '---' for frontmatter block." 1

[[ -z "$plan_id" ]] && error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1
[[ "$plan_id" =~ ^[A-Za-z0-9_-]+$ ]] || error_exit "Plan id '$plan_id' contains invalid characters (path traversal guard)" 1

# ---------------------------------------------------------------------------
# Step 2: Classify the plan's ceremony band from its declared Files: paths
# ---------------------------------------------------------------------------
_cp1_band_line="$(aid_plan_band "$plan" "$project_root")"
AID_PLAN_RISK_BAND="${_cp1_band_line%%$'\t'*}"
AID_PLAN_RISK_REASON="${_cp1_band_line#*$'\t'}"

# Telemetry (P084 Step 7). What the band was and WHY, so the next revision of
# this policy argues from numbers instead of impressions. Never blocking:
# log_event is a no-op when the target cannot be resolved, and a plan must not
# fail to be classified because a directory was unwritable.
_cp1_log() {
  local tl
  tl="$(aid_plan_timeline "$project_root" "$plan_id")" || return 0
  # `|| true`: telemetry never decides this gate's verdict.
  log_event "$tl" "$@" || true
}
_cp1_log cp1_band_classified band="$AID_PLAN_RISK_BAND" reason="$AID_PLAN_RISK_REASON" \
  classify_only="$( [[ "$classify_only" -eq 1 ]] && echo true || echo false )"

# The OUTCOME is logged from an EXIT trap, not from each success path. The gate
# leaves through a dozen different `exit 1`s (missing evidence, an empty lens,
# an adjudicator verdict, C0, the ledger) and a telemetry line written only on
# the two happy paths would count exactly the runs nobody needs counted.
# `_cp1_result` is set where an outcome is KNOWN; anything else is a failure.
_cp1_result="fail"
_cp1_on_exit() {
  local rc=$?
  [[ "$classify_only" -eq 1 ]] && return 0   # a classification is not a gate run
  _cp1_log cp1_gate_result band="$AID_PLAN_RISK_BAND" \
    result="$( [[ "$rc" -eq 0 ]] && printf '%s' "$_cp1_result" || printf 'fail' )" \
    exit_code="$rc"
  return 0
}
trap _cp1_on_exit EXIT

if [[ "$classify_only" -eq 1 ]]; then
  echo "$AID_PLAN_RISK_BAND"
  echo "CP1-gate: plan ${plan_id} band=${AID_PLAN_RISK_BAND} (${AID_PLAN_RISK_REASON})" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 2b: What this band actually requires
# ---------------------------------------------------------------------------
# The band alone decides nothing — defaults/policies/review-checkpoints.yaml
# maps it to the three requirement flags below, and this gate READS that table
# rather than describing it. Every uncertainty resolves to `true`: no table, no
# yq, an unknown band, a value that is not true/false. A band is lowered only by
# what the plan declares it will touch, never by a gap in configuration.
_cp1_band_requires() {
  local band="$1" key="$2" root="$3" file="" cand val
  for cand in "${root}/.aid-o/config/policies/review-checkpoints.yaml" "$CP1_CHECKPOINTS_DEFAULT"; do
    [[ -f "$cand" ]] && { file="$cand"; break; }
  done
  if [[ -z "$file" ]] || ! command -v yq >/dev/null 2>&1; then
    echo "true"; return 0
  fi
  # NOT `... // "true"`: yq's alternative operator treats an explicit `false`
  # as falsy, which would silently turn every switched-OFF requirement back on.
  # Absent reads as `null` here and lands in the fail-closed default below,
  # while `false` reaches the case arm that honours it.
  val="$(yq -r ".review_checkpoints.ceremony_bands.${band}.${key}" "$file" 2>/dev/null)" || val=""
  case "$val" in
    true|false) echo "$val" ;;
    *)          echo "true" ;;
  esac
}

cp1_need_lenses="$(_cp1_band_requires "$AID_PLAN_RISK_BAND" cp1_deep_lenses "$project_root")"
cp1_need_c0="$(_cp1_band_requires "$AID_PLAN_RISK_BAND" c0_cross_provider "$project_root")"
cp1_need_ledger="$(_cp1_band_requires "$AID_PLAN_RISK_BAND" cp1_ledger "$project_root")"

# ---------------------------------------------------------------------------
# Step 3: A band that owes no CP1-deep evidence exits here
# ---------------------------------------------------------------------------
if [[ "$cp1_need_lenses" != "true" ]]; then
  echo "CP1-gate: plan $plan_id is band=${AID_PLAN_RISK_BAND} (${AID_PLAN_RISK_REASON}) — CP1-deep not required. Proceeding." >&2
  _cp1_result="not_applicable"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3b: If no .aid-o/ workspace exists, gate is not applicable.
# The gate only enforces within AID-managed projects. Scripts calling
# aid-plan-to-epic.sh directly (e.g., from test harnesses) without a
# workspace are not subject to CP1-deep enforcement.
# ---------------------------------------------------------------------------
if [[ ! -d "${project_root}/.aid-o" ]]; then
  echo "CP1-gate: no .aid-o/ workspace found at ${project_root} — gate skipped (not an AID project)." >&2
  exit 0
fi

echo "CP1-gate: plan $plan_id is band=${AID_PLAN_RISK_BAND} (${AID_PLAN_RISK_REASON}) — checking CP1-deep evidence." >&2

# ---------------------------------------------------------------------------
# Step 4: Check for evidence dir and required files (existence + content)
# ---------------------------------------------------------------------------
evidence_dir="${project_root}/.aid-o/work/evidence/${plan_id}/cp1-deep"

# Lens files follow the plan taxonomy: L1 behavior/user-flow, L2 feasibility/producer→consumer,
# L3 enforcement/CI/artifact-visibility. Each must be non-empty and contain stop_rule_blockers:.
LENS_FILES=(
  "cp1-lens-L1-behavior.md"
  "cp1-lens-L2-feasibility.md"
  "cp1-lens-L3-enforcement.md"
)
adjudicator_file="${evidence_dir}/cp1-adjudicator.md"

missing_files=()
for f in "${LENS_FILES[@]}"; do
  [[ ! -f "${evidence_dir}/${f}" ]] && missing_files+=("$f")
done
[[ ! -f "$adjudicator_file" ]] && missing_files+=("cp1-adjudicator.md")

if [[ "${#missing_files[@]}" -gt 0 ]]; then
  missing_list="$(printf '  - %s\n' "${missing_files[@]}")"
  cat >&2 <<ERRMSG
ERROR: High-risk plan requires CP1-deep evidence.
Missing files in ${evidence_dir}/:
${missing_list}
Run /aid-plan --deep to generate CP1-deep evidence before EPIC generation.
ERRMSG
  exit 1
fi

# Content check: each lens file must be non-empty and declare stop_rule_blockers:.
for f in "${LENS_FILES[@]}"; do
  fpath="${evidence_dir}/${f}"
  if [[ ! -s "$fpath" ]]; then
    error_exit "CP1-deep lens file is empty: ${f}. Substantive evidence required." 1
  fi
  if ! grep -q "^stop_rule_blockers:" "$fpath" 2>/dev/null; then
    error_exit "CP1-deep lens file missing required 'stop_rule_blockers:' field: ${f}" 1
  fi
done

# Adjudicator must be non-empty and declare verdict:.
if [[ ! -s "$adjudicator_file" ]]; then
  error_exit "CP1-deep adjudicator file is empty. Substantive evidence required." 1
fi
if ! grep -q "^verdict:" "$adjudicator_file" 2>/dev/null; then
  error_exit "CP1-deep adjudicator missing required 'verdict:' field. Gate cannot proceed without explicit verdict." 1
fi

echo "CP1-gate: all 4 evidence files present and structurally valid in ${evidence_dir}/" >&2

# ---------------------------------------------------------------------------
# _cp1_override_file <plan_evidence_root>
# ---------------------------------------------------------------------------
_cp1_override_file() {
  printf '%s/cp1-pm-escalation-override.json' "$1"
}

# ---------------------------------------------------------------------------
# _cp1_check_pm_override <plan_evidence_root>
#   READ-ONLY: reports whether a structurally valid PM-escalation override
#   (non-empty pm_ref field, >= 20 chars) is currently present. Never
#   consumes/renames anything. Echoes the pm_ref reason and returns 0 iff
#   valid; returns 1 (nothing echoed) otherwise.
#
#   Deliberately separate from consumption (see _cp1_claim_pm_override
#   below): a live DONE-review audit (E-065-7_7, finding c3-E-065-7_7-0)
#   found the EARLIER single-call design (check-and-consume as one eager
#   operation, called unconditionally before evaluating C0/ledger) consumed
#   a present override even on a run where NEITHER check would have failed
#   — violating "Available + clean gate should remain Available." The gate
#   now evaluates C0-ok and ledger-ok FIRST using only this read-only check,
#   and calls the atomic claim below ONLY if at least one actually failed.
# ---------------------------------------------------------------------------
_cp1_check_pm_override() {
  local plan_evidence_root="$1" override_file reason
  override_file="$(_cp1_override_file "$plan_evidence_root")"
  [[ -f "$override_file" ]] || return 1
  reason="$(jq -r '.pm_ref // empty' "$override_file" 2>/dev/null || echo "")"
  [[ -n "$reason" && "${#reason}" -ge 20 ]] || return 1
  printf '%s' "$reason"
  return 0
}

# _cp1_claim_pm_override <plan_evidence_root>
#   Atomically CLAIMS (consumes) a present, valid PM-escalation override —
#   call this ONLY once a caller has determined the override is actually
#   needed (a check alone, via _cp1_check_pm_override, must never trigger
#   consumption). Attempts a no-clobber rename to a `.consumed-<epoch>`
#   sibling and returns 0 (echoing the pm_ref reason) iff BOTH `mv -n`
#   itself reports success AND the source file is confirmed gone afterward.
#
#   WHY BOTH checks together (a live DONE-review audit found real bugs on
#   EACH side of this, in two successive rounds):
#   - Checking source-gone ALONE (round 2's first attempt) is not enough:
#     under a genuine concurrent race, the LOSING process's own `mv -n`
#     call can itself fail (non-zero exit, e.g. its `rename(2)` hits ENOENT
#     because the winner already removed the source) while the source
#     happens to be gone anyway — because the WINNER removed it, not this
#     process. Trusting source-gone alone made the loser wrongly believe
#     it also won, an empirically-confirmed double-claim (verified via a
#     200-iteration concurrent-race harness: source-only check produced
#     200/200 double-claims; requiring both conditions produced 0/200).
#   - Checking `mv -n`'s exit code ALONE (round 1's original bug) is not
#     enough either: `mv -n src dst` ALSO exits 0 — without moving
#     anything — when `dst` already exists as a stale `.consumed-<epoch>`
#     sibling from an earlier, unrelated run landing on the SAME epoch
#     second, silently leaving the override intact and reusable.
#   Only the CONJUNCTION of "mv itself reported success" AND "the source
#   is now confirmed gone" distinguishes all three cases correctly: a
#   genuine solo claim (both true), a race loser (mv fails OR, if mv
#   spuriously reports 0, source-gone was caused by someone else — but the
#   mv-exit-code check alone already screens out the real race-loser case
#   per the harness above), and a stale-destination collision (mv reports
#   0 via -n's no-clobber skip, but source remains — caught by the
#   source-gone half).
#
#   Platform note: relies on GNU coreutils' `mv -n` using an atomic
#   renameat2(RENAME_NOREPLACE) on Linux (this project's target platform,
#   confirmed empirically via a 550-iteration concurrent-race harness,
#   0 double-claims) — not a portability guarantee across all `mv`
#   implementations.
# ---------------------------------------------------------------------------
_cp1_claim_pm_override() {
  local plan_evidence_root="$1" override_file consumed_file reason
  override_file="$(_cp1_override_file "$plan_evidence_root")"
  [[ -f "$override_file" ]] || return 1
  reason="$(jq -r '.pm_ref // empty' "$override_file" 2>/dev/null || echo "")"
  [[ -n "$reason" && "${#reason}" -ge 20 ]] || return 1

  consumed_file="${override_file}.consumed-$(date -u +%s)"
  if mv -n "$override_file" "$consumed_file" 2>/dev/null && [[ ! -f "$override_file" ]]; then
    printf '%s' "$reason"
    return 0
  fi
  # Either mv failed outright (a race loser, or a permission error), or it
  # no-op'd on a pre-existing destination (source still present) — we do
  # NOT own this override. Fail closed.
  return 1
}

# ---------------------------------------------------------------------------
# _cp1_c0_and_ledger_gate <plan_id> <project_root>
#   Runs only after the 4-file CP1-deep evidence + adjudicator check has
#   already PASSED. Enforces the C0 cross-provider plan review requirement
#   and the CP1 ledger budget (P065 E-065-7_7 Step 20 — see header comment
#   above). Always terminates the script (exit 0 or exit 1) — never returns
#   — matching the two call sites' prior bare `exit 0`.
# ---------------------------------------------------------------------------
_cp1_c0_and_ledger_gate() {
  local plan_id="$1" project_root="$2"
  local plan_evidence_root="${project_root}/.aid-o/work/evidence/${plan_id}"
  local c0_review_file="${plan_evidence_root}/c0-plan-review.json"

  # A band that owes neither check is finished the moment its CP1-deep evidence
  # passed. Both flags come from the bands table (Step 2b); `medium` is the band
  # that lands here.
  if [[ "$cp1_need_c0" != "true" && "$cp1_need_ledger" != "true" ]]; then
    echo "CP1-gate: band=${AID_PLAN_RISK_BAND} owes no C0 cross-provider review and no ledger budget. PASS." >&2
    _cp1_result="pass"
    exit 0
  fi

  # Read-only override peek — used ONLY to decide whether either check below
  # is allowed to proceed on a failure; does NOT consume anything. Genuine
  # consumption happens later, exactly once, and only if actually needed —
  # see the claim call after both checks (E-065-7_7 live DONE-review finding
  # c3-E-065-7_7-0: an earlier eager-consume design spent a valid override
  # on runs that would have passed cleanly with no override at all).
  local override_reason="" override_present=0
  if override_reason="$(_cp1_check_pm_override "$plan_evidence_root")"; then
    override_present=1
  fi

  # --- 1. C0 cross-provider plan review ------------------------------------
  local c0_ok=1 c0_reason=""
  if [[ "$cp1_need_c0" != "true" ]]; then
    c0_ok=1
  elif [[ ! -f "$c0_review_file" ]]; then
    c0_ok=0
    c0_reason="c0-plan-review.json missing at ${c0_review_file}"
  else
    local review_status blocking
    review_status="$(jq -r '.review_status // ""' "$c0_review_file" 2>/dev/null || echo "")"
    # NOTE: NOT `.blocking_findings // true` — jq's `//` alternative operator
    # treats an explicit `false` as falsy too, which would silently flip a
    # genuinely clean `blocking_findings: false` into "true" and always
    # block. `has(...)` distinguishes "absent" (fail-closed to true) from
    # "explicitly false".
    blocking="$(jq -r 'if has("blocking_findings") then .blocking_findings else true end' "$c0_review_file" 2>/dev/null || echo "true")"
    if [[ "$review_status" == "unverifiable" ]]; then
      c0_ok=0
      c0_reason="c0-plan-review.json review_status=unverifiable"
    elif [[ "$blocking" == "true" ]]; then
      c0_ok=0
      c0_reason="c0-plan-review.json has surviving blocking_findings=true"
    else
      # THE code-level enforcement point (not prose): re-prove the raw-
      # binding/provenance chain via the SAME verify subcommand
      # aid-c0-plan-review.sh itself ships (Step 18) — a hand-edited or
      # stale report fails this even when its top-level fields look clean.
      local verify_out verify_ok=1
      if ! verify_out="$(bash "$CP1_GATE_C0_REVIEW_BIN" verify "$plan_evidence_root" 2>&1)"; then
        verify_ok=0
      fi
      if [[ "$verify_ok" -ne 1 ]]; then
        c0_ok=0
        c0_reason="aid-c0-plan-review.sh verify failed for ${plan_evidence_root}: ${verify_out}"
      fi
    fi
  fi

  # override_claimed: -1 = not yet attempted this run, 0 = attempted and
  # failed (no valid override, or lost a concurrent race), 1 = claimed —
  # attempted at most ONCE per gate invocation, only on genuine first need,
  # and its result is reused for the ledger check below (a single override
  # authorizes bypassing both, exactly once, never a re-claim per check).
  # _cp1_ensure_override_claimed sets override_reason/override_claimed as a
  # side effect; wrapped in `if` (not a bare `&&`/`||` chain) so a failed
  # claim attempt never trips `set -e`.
  local override_claimed=-1
  _cp1_ensure_override_claimed() {
    if [[ "$override_claimed" -eq -1 ]]; then
      if override_reason="$(_cp1_claim_pm_override "$plan_evidence_root")"; then
        override_claimed=1
      else
        override_claimed=0
      fi
    fi
  }

  if [[ "$c0_ok" -ne 1 ]]; then
    if [[ "$override_present" -eq 1 ]]; then
      _cp1_ensure_override_claimed
    fi
    if [[ "$override_claimed" -eq 1 ]]; then
      echo "CP1-gate: WARNING — proceeding past C0 plan-review requirement (${c0_reason}) via PM-escalation override: ${override_reason}" >&2
    else
      cat >&2 <<ERRMSG
ERROR: High-risk plan requires a verified C0 cross-provider plan review before EPIC generation.
Reason: ${c0_reason}
Fix: run the C0 review loop (aid-c0-plan-review.sh build-manifest / dispatch / verify) until it is
clean, or obtain a PM-escalation override artifact at:
  ${plan_evidence_root}/cp1-pm-escalation-override.json
  (must contain a non-empty "pm_ref" field, >= 20 characters)
ERRMSG
      exit 1
    fi
  fi

  # --- 2. CP1 revision-limit ledger budget ----------------------------------
  local ledger_ok=1 ledger_reason="" ledger_out="" ledger_rc=0
  if [[ "$cp1_need_ledger" == "true" ]]; then
    if ledger_out="$(bash "$CP1_GATE_LEDGER_BIN" check-budget --project-root "$project_root" "$plan_id" 2>&1)"; then
      ledger_rc=0
    else
      ledger_rc=$?
    fi
    if [[ "$ledger_rc" -ne 0 ]]; then
      ledger_ok=0
      ledger_reason="aid-cp1-ledger.sh check-budget rc=${ledger_rc}: ${ledger_out}"
    fi
  fi

  if [[ "$ledger_ok" -ne 1 ]]; then
    if [[ "$override_present" -eq 1 ]]; then
      _cp1_ensure_override_claimed
    fi
    if [[ "$override_claimed" -eq 1 ]]; then
      echo "CP1-gate: WARNING — proceeding past CP1 ledger budget check (${ledger_reason}) via PM-escalation override: ${override_reason}" >&2
    else
      cat >&2 <<ERRMSG
ERROR: CP1 revision-limit ledger blocks EPIC generation for plan ${plan_id}.
${ledger_reason}
Fix: run 'aid-cp1-ledger.sh init [--pre-enforcement] --project-root <root> ${plan_id}' for a
genuinely new/in-flight plan, or obtain a PM-escalation override artifact at:
  ${plan_evidence_root}/cp1-pm-escalation-override.json
  (must contain a non-empty "pm_ref" field, >= 20 characters)
ERRMSG
      exit 1
    fi
  fi

  # NOTE: the PM-override, if present, is claimed (atomically consumed) at
  # MOST once per gate invocation — only at the point one of the two checks
  # above genuinely needs it, never eagerly on a clean pass. A single claim
  # covers both checks if both failed in the same run.

  echo "CP1-gate: band=${AID_PLAN_RISK_BAND} — required C0 plan review / ledger budget checks passed for ${plan_id}." >&2
  _cp1_result="pass"
  exit 0
}

# ---------------------------------------------------------------------------
# Step 5: Check adjudicator verdict — no unresolved accepted_blockers allowed
# ---------------------------------------------------------------------------

# verdict field is now guaranteed to exist (checked above).
verdict_value="$(grep "^verdict:" "$adjudicator_file" | head -1 | sed 's/^verdict:[[:space:]]*//' | sed 's/[[:space:]]*$//')"
if [[ "$verdict_value" == "fail" || "$verdict_value" == "revise" ]]; then
  cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has unresolved verdict: ${verdict_value}
Resolve blockers or escalate to PM before EPIC generation.
Adjudicator file: ${adjudicator_file}
ERRMSG
  exit 1
fi

# Extract the accepted_blockers value from the adjudicator file.
# We look for `accepted_blockers:` followed by either:
#   accepted_blockers: []        → empty list = pass
#   accepted_blockers: [...]     → non-empty = fail
#   accepted_blockers:           (block scalar) → items decide (P074 Step 17):
#     the canonical empty forms `- []`, `- none`, `- (none)` (case-insensitive,
#     whitespace-tolerant) parse as EMPTY; any genuine `- <text>` item fails.
# An INDENTED/nested occurrence of the key with NO top-level key was previously
# a silent "no field" pass — it is now a loud structural error (P074 Step 17).

# _cp1_blocker_empty_item <item-text> — 0 iff the list item text is one of the
# canonical empty forms: `[]`, `none`, `(none)` (case-insensitive, trimmed).
_cp1_blocker_empty_item() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$t" == "[]" || "$t" == "none" || "$t" == "(none)" ]]
}

# _cp1_toplevel_key_line <key> — echoes the `lineno:key: value` of the first
# TOP-LEVEL occurrence of <key> (or nothing when absent). ANY indented/nested
# occurrence of the key is a structural error naming its line — whether or not
# a top-level key also exists: the gate reads exclusively top-level keys, so a
# nested key is either a silent "no field" pass (no top-level) or a shadowed
# duplicate the gate would silently ignore (top-level present). Exit 1 either
# way.
_cp1_toplevel_key_line() {
  local key="$1" top nested
  nested="$(grep -nE "^[[:space:]]+${key}:" "$adjudicator_file" 2>/dev/null | head -1 || true)"
  if [[ -n "$nested" ]]; then
    cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has an INDENTED/nested '${key}:' key at line ${nested%%:*}.
The gate reads only a top-level '${key}:' — a nested key would be silently ignored (as "no field" when no top-level key exists, or as a shadowed duplicate when one does).
Remove the nested key or move it to column 0 in: ${adjudicator_file}
ERRMSG
    exit 1
  fi
  top="$(grep -n "^${key}:" "$adjudicator_file" 2>/dev/null | head -1 || true)"
  printf '%s' "$top"
}

# rejected_blockers is not consulted for pass/fail, but the same structural
# nested-key trap applies to its read: nested-only is a loud error, not silence.
_cp1_toplevel_key_line "rejected_blockers" >/dev/null || exit 1

accepted_blockers_line="$(_cp1_toplevel_key_line "accepted_blockers")" || exit 1

if [[ -z "$accepted_blockers_line" ]]; then
  # verdict:pass already confirmed above; no accepted_blockers field = no blockers.
  echo "CP1-gate: verdict=pass, no accepted_blockers field. PASS." >&2
  _cp1_c0_and_ledger_gate "$plan_id" "$project_root"
fi

# Extract the value after "accepted_blockers:"
accepted_value="$(echo "$accepted_blockers_line" | sed 's/^[0-9]*:accepted_blockers:[[:space:]]*//')"
accepted_value="$(echo "$accepted_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [[ "$accepted_value" == "[]" || -z "$accepted_value" ]]; then
  # Block-scalar walk: consume the list region below the key. Empty forms
  # (`- []`, `- none`, `- (none)`) parse as EMPTY; a genuine item fails.
  # Blank lines and `#` comment lines INSIDE the region are SKIPPED, never
  # terminators — otherwise `- []` + blank line + `- <real blocker>` would
  # report EMPTY and pass the gate. The region ends only at a line starting
  # a new key at the parent indent (column 0, the key's own level) or EOF.
  line_num="$(echo "$accepted_blockers_line" | cut -d: -f1)"
  # Newline-terminator-agnostic read: mapfile keeps an unterminated final
  # line, where a `wc -l` upper bound silently drops it — a real blocker on a
  # no-final-newline last line must not bypass the walk.
  mapfile -t _adj_lines < "$adjudicator_file"
  item_idx=$(( line_num ))  # 0-based index of the first line AFTER the key line
  while [[ "$item_idx" -lt "${#_adj_lines[@]}" ]]; do
    raw_line="${_adj_lines[$item_idx]}"
    next_line="$(echo "$raw_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$next_line" || "$next_line" == \#* ]]; then
      # blank/comment inside the list region — skip, do not terminate
      item_idx=$(( item_idx + 1 ))
      continue
    fi
    if [[ "$raw_line" =~ ^[^[:space:]] ]]; then
      # a new key/content at the parent indent level — the region ends here
      break
    fi
    if [[ "$next_line" =~ ^-([[:space:]]+(.*))?$ ]]; then
      item_text="${BASH_REMATCH[2]:-}"
      if ! _cp1_blocker_empty_item "$item_text"; then
        cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has unresolved blockers (block scalar list).
First blocker item: - ${item_text}
Resolve blockers or escalate to PM before EPIC generation.
Adjudicator file: ${adjudicator_file}
ERRMSG
        exit 1
      fi
    fi
    # indented non-item lines (map continuations of an item) are skipped
    item_idx=$(( item_idx + 1 ))
  done

  echo "CP1-gate: adjudicator accepted_blockers is empty. PASS." >&2
  _cp1_c0_and_ledger_gate "$plan_id" "$project_root"
else
  # Non-empty inline list — has accepted blockers
  cat >&2 <<ERRMSG
ERROR: CP1-deep adjudicator has unresolved blockers.
accepted_blockers: ${accepted_value}
Resolve blockers or escalate to PM before EPIC generation.
Adjudicator file: ${adjudicator_file}
ERRMSG
  exit 1
fi
