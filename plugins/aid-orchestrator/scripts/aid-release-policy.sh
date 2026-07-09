#!/usr/bin/env bash
# aid-release-policy.sh — C4 release-readiness aggregator (E-059-2_2 Step 4).
#
# Reads every evidence input per the Data Model contract — fail-closed and
# deterministically — and emits a protocol-v2 `release_decision` artifact carrying
# the release_ready verdict, per-input verdicts, blockers, and the 11 D11 state
# fields the FSM merge gate + PM brief read DIRECTLY (never inferring state).
#
# Usage: aid-release-policy.sh <epic_id> <run_id> [--out <path>]
#
# Data Model (REQUIRED / PROFILE-GATED / ADVISORY / CONDITIONAL / OPTIONAL):
#   REQUIRED (missing → blocked): review-profile, delivery-gate, semantic-review-final,
#     acceptance-evidence, gates_report (root, fallback gates/), plan-review (plan_ref hop),
#     verification-report (aid-evidence-verify.sh --at-head; fail OR unverifiable both block).
#   PROFILE-GATED (required only when the C3 audit gate is active): curator-report, audit-report.
#   ADVISORY (missing → advisory, never blocks): invalidation-map.
#   CONDITIONAL (marker→toggle→file): reporter (.aid-o/reports/<Pnum>-delivery.md, reporter.enabled),
#     simplifier (<evidence_dir>/simplifier-report.md, simplifier.enabled).
#   OPTIONAL: waiver-*.json → waivers_applied[] (Waived != pass).
#
# Exit codes:
#   0  — release_decision artifact produced (regardless of the release_ready value)
#   2  — usage error
#
# Determinism: two runs at the same HEAD produce byte-identical payloads after
# `jq 'del(.created_at)'` — created_at is the only time-varying field.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
EVIDENCE_VERIFY="${SCRIPT_DIR}/aid-evidence-verify.sh"
PROTOCOL_VALIDATE="${SCRIPT_DIR}/aid-protocol-validate.sh"
C3_POLICY_FILE="${PLUGIN_ROOT}/defaults/policies/c3-audit-policy.yaml"

# Shared review-signal substrate (B1) — _aid_read_toggle + _aid_validate_test_evidence.
# The SAME functions fsm_eval_delivery_report_present / fsm_eval_simplifier_present read,
# so the aggregator and the FSM compliance checks never diverge on the reporter/simplifier
# substrate.
# shellcheck source=lib/aid-review-signals.sh
source "${SCRIPT_DIR}/lib/aid-review-signals.sh"

# ---------------------------------------------------------------------------
# Accumulators (globals mutated by add_input / add_blocker / waiver loop)
# ---------------------------------------------------------------------------
INPUTS_JSON="[]"
BLOCKERS_JSON="[]"
WAIVERS_JSON="[]"

# Reporter / Simplifier CONDITIONAL results (set by compute_reporter/compute_simplifier)
REPORTER_STATUS="not_applicable"
REPORTER_REASON="not_plan_boundary"
REPORTER_ARTIFACT=".aid-o/reports/delivery.md"
SIMPLIFIER_STATUS="not_applicable"
SIMPLIFIER_REASON="not_plan_boundary"
SIMPLIFIER_ARTIFACT="simplifier-report.md"

# ---------------------------------------------------------------------------
# Small deterministic helpers
# ---------------------------------------------------------------------------

# add_input <id> <artifact> <verdict> <reason> <head_match(true|false)>
# jq -n (null input) — the row is built purely from --arg/--argjson; without -n jq would
# block reading stdin.
add_input() {
  INPUTS_JSON="$(jq -cn \
    --argjson arr "$INPUTS_JSON" \
    --arg id "$1" --arg artifact "$2" --arg verdict "$3" --arg reason "$4" \
    --argjson head_match "$5" \
    '$arr + [{id:$id, artifact:$artifact, verdict:$verdict, reason:$reason, head_match:$head_match}]')"
}

# add_blocker <input_id(canonical)> <severity> <reason>
add_blocker() {
  BLOCKERS_JSON="$(jq -cn \
    --argjson arr "$BLOCKERS_JSON" \
    --arg input_id "$1" --arg severity "$2" --arg reason "$3" \
    '$arr + [{input_id:$input_id, severity:$severity, reason:$reason}]')"
}

# _is_json <file> — present AND parseable JSON (fail-closed presence+parse gate).
_is_json() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 0   # no jq → presence-only (best effort)
  jq -e . "$f" >/dev/null 2>&1
}

# _artifact_head_match <file> — echoes true|false from .revision.head_sha vs CURRENT_HEAD.
# Missing file → false; no revision.head_sha (n/a) → true (do not penalise non-v2 artifacts).
_artifact_head_match() {
  local f="$1" hs rc=0
  [[ -f "$f" ]] || { echo false; return 0; }
  command -v jq >/dev/null 2>&1 || { echo true; return 0; }
  hs="$(jq -r '.revision.head_sha // ""' "$f" 2>/dev/null)" || rc=$?
  { [[ $rc -ne 0 ]] || [[ -z "$hs" ]]; } && { echo true; return 0; }
  [[ "$hs" == "${CURRENT_HEAD:-}" ]] && echo true || echo false
}

# check_required_present <id> <blocker_id> <file> — REQUIRED file rows.
# present+parseable → pass; missing/unreadable → blocked + blocker.
check_required_present() {
  local id="$1" bid="$2" file="$3"
  if _is_json "$file"; then
    add_input "$id" "$(basename "$file")" "pass" "present and parseable" "$(_artifact_head_match "$file")"
  else
    add_input "$id" "$(basename "$file")" "blocked" "required artifact missing or unreadable" false
    add_blocker "$bid" "blocking" "required artifact missing or unreadable: $(basename "$file")"
  fi
}

# _extract_plan_ref <epic_input.md> — echoes the frontmatter plan_ref value (or empty).
_extract_plan_ref() {
  local epic_input="$1" raw
  [[ -f "$epic_input" ]] || { echo ""; return 0; }
  raw="$(awk '
    /^---[[:space:]]*$/ { c++; if (c==2) exit; next }
    c==1 && $0 ~ /^[[:space:]]*plan_ref[[:space:]]*:/ {
      line=$0
      sub(/^[[:space:]]*plan_ref[[:space:]]*:[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      print line
      exit
    }
  ' "$epic_input" 2>/dev/null || true)"
  # trim surrounding whitespace and quotes (bash param expansion — no extra forks)
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  raw="${raw#\"}"; raw="${raw%\"}"
  raw="${raw#\'}"; raw="${raw%\'}"
  echo "$raw"
}

# _c3_gate_active — returns 0 (C3 audit gate active) or 1 (inactive).
# Mirrors fsm_eval / done-advance c3_hook_fired (aid-fsm.sh ~2725-2824): fail-closed to
# ACTIVE for an unverifiable/high profile, and the secondary audit-report.json trigger.
_c3_gate_active() {
  local evidence_dir="$1"
  local review_profile_file="${evidence_dir}/review-profile.json"
  local audit_report_file="${evidence_dir}/audit-report.json"

  # No review-profile.json → this run never entered the C3 pipeline → inactive.
  [[ -f "$review_profile_file" ]] || return 1

  # Resolve risk profile (fail-closed to "unverifiable" on any ambiguity).
  local risk_profile=""
  if ! command -v jq >/dev/null 2>&1; then
    risk_profile="unverifiable"
  else
    local resolved="" rc=0
    resolved="$(jq -r '.review_profile.risk_profile // "MISSING"' "$review_profile_file" 2>/dev/null)" || rc=$?
    if [[ $rc -eq 0 && "$resolved" != "MISSING" ]]; then
      case "$resolved" in
        docs_trivial|low|medium|high|unverifiable) risk_profile="$resolved" ;;
        *) risk_profile="unverifiable" ;;
      esac
    else
      risk_profile="unverifiable"
    fi
  fi

  # Primary trigger: policy c3_required for the resolved profile.
  local policy_read_succeeded="false" c3_required_from_policy=""
  if [[ -f "$C3_POLICY_FILE" ]] && command -v yq >/dev/null 2>&1; then
    local has_key="" hrc=0
    has_key="$(yq -r "(.risk_profiles | has(\"$risk_profile\")) and (.risk_profiles[\"$risk_profile\"] | has(\"c3_required\"))" "$C3_POLICY_FILE" 2>/dev/null)" || hrc=$?
    if [[ $hrc -eq 0 && "$has_key" == "true" ]]; then
      local crc=0
      c3_required_from_policy="$(yq -r ".risk_profiles[\"$risk_profile\"].c3_required" "$C3_POLICY_FILE" 2>/dev/null)" || crc=$?
      if [[ $crc -eq 0 && ("$c3_required_from_policy" == "true" || "$c3_required_from_policy" == "false") ]]; then
        policy_read_succeeded="true"
      fi
    fi
  fi

  if [[ "$policy_read_succeeded" == "true" && "$c3_required_from_policy" == "true" ]]; then
    return 0
  elif [[ "$policy_read_succeeded" != "true" && "$risk_profile" == "high" ]]; then
    return 0   # fail-closed: cannot confirm c3_required=false for a high profile
  elif [[ "$risk_profile" == "unverifiable" ]]; then
    return 0   # fail-closed
  fi

  # Secondary trigger: a real audit-report.json for this run fires the hook even if the
  # primary gate did not (mirrors the FSM defense-in-depth trigger).
  if [[ -f "$audit_report_file" ]] && command -v jq >/dev/null 2>&1; then
    local has_audit="" arc=0
    has_audit="$(jq -r 'if (.audit_report | type) == "object" and (.audit_report | length) > 0 then "true" else "false" end' "$audit_report_file" 2>/dev/null)" || arc=$?
    if [[ $arc -eq 0 && "$has_audit" == "true" ]]; then
      return 0
    fi
  fi

  return 1
}

# process_profile_gated <id> <file> — curator-report / audit-report rows.
# C3 active + missing → blocked (+ blocker); C3 inactive + missing → advisory (no block).
process_profile_gated() {
  local id="$1" file="$2"
  if _is_json "$file"; then
    add_input "$id" "$(basename "$file")" "pass" "present" "$(_artifact_head_match "$file")"
  elif [[ "$C3_ACTIVE" == "true" ]]; then
    add_input "$id" "$(basename "$file")" "blocked" "required when C3 audit gate active; missing" false
    add_blocker "$id" "blocking" "$(basename "$file") required (C3 audit gate active) but missing"
  else
    add_input "$id" "$(basename "$file")" "advisory" "not required (C3 audit gate inactive); absent" true
  fi
}

# _read_autonomous_mode — echoes auto|manual from .aid-o/config/permissions.yaml.
# ONLY a real YAML boolean `autonomous_mode: true` → auto; everything else (false, null,
# missing key, non-boolean, missing file, no yq, preset-model file) → manual (fail-closed).
_read_autonomous_mode() {
  local perm="${PROJECT_ROOT}/.aid-o/config/permissions.yaml"
  [[ -f "$perm" ]] || { echo manual; return 0; }
  command -v yq >/dev/null 2>&1 || { echo manual; return 0; }
  local vtype vval
  vtype="$(yq -r '.autonomous_mode | type' "$perm" 2>/dev/null)" || { echo manual; return 0; }
  [[ "$vtype" == "!!bool" ]] || { echo manual; return 0; }
  vval="$(yq -r '.autonomous_mode' "$perm" 2>/dev/null)" || { echo manual; return 0; }
  [[ "$vval" == "true" ]] && echo auto || echo manual
}

# _status_to_verdict / _status_headmatch — map a reporter/simplifier 5-enum status onto the
# inputs[] verdict enum + head_match field.
_status_to_verdict() {
  case "$1" in
    pass) echo pass ;;
    fail) echo fail ;;
    missing) echo blocked ;;
    disabled|not_applicable) echo advisory ;;
    *) echo advisory ;;
  esac
}
_status_headmatch() {
  case "$1" in pass|disabled|not_applicable) echo true ;; *) echo false ;; esac
}

# compute_reporter — CONDITIONAL: marker → toggle(reporter.enabled) → file → _test_evidence.
# Reporter delivery-report plan_id is P<num> derived from epic_id (byte-identical to
# fsm_eval_delivery_report_present), so the shared-lib substrate cross-checks 1:1.
compute_reporter() {
  local marker="${EVIDENCE_DIR}/ca-review-complete"
  local exec_yaml="${PROJECT_ROOT}/.aid-o/config/execution.yaml"
  local plan_num="" report_plan_id=""
  [[ "$EPIC_ID" =~ ^E-([0-9]+) ]] && plan_num="${BASH_REMATCH[1]}"
  if [[ -z "$plan_num" ]]; then
    REPORTER_STATUS="not_applicable"
    REPORTER_REASON="not_plan_boundary (epic_id carries no plan number)"
    REPORTER_ARTIFACT=".aid-o/reports/delivery.md"
    return 0
  fi
  report_plan_id="P${plan_num}"
  REPORTER_ARTIFACT=".aid-o/reports/${report_plan_id}-delivery.md"
  local report="${PROJECT_ROOT}/.aid-o/reports/${report_plan_id}-delivery.md"

  if [[ ! -f "$marker" ]]; then
    REPORTER_STATUS="not_applicable"; REPORTER_REASON="not_plan_boundary"; return 0
  fi
  local enabled=true
  _aid_read_toggle "$exec_yaml" "reporter" || enabled=false
  if [[ "$enabled" == "false" ]]; then
    REPORTER_STATUS="disabled"; REPORTER_REASON="reporter.enabled:false in execution.yaml"; return 0
  fi
  if [[ ! -f "$report" ]]; then
    REPORTER_STATUS="missing"; REPORTER_REASON="delivery report missing at ${REPORTER_ARTIFACT}"; return 0
  fi
  local valid
  valid="$(_aid_validate_test_evidence "$report" "$EVIDENCE_DIR")"
  if [[ "$valid" == "true" ]]; then
    REPORTER_STATUS="pass"; REPORTER_REASON="delivery report present with >=1 in-tree _test_evidence path on disk"
  else
    REPORTER_STATUS="fail"; REPORTER_REASON="delivery report _test_evidence references no in-tree file on disk"
  fi
}

# compute_simplifier — CONDITIONAL: marker → toggle(simplifier.enabled) → file existence.
# simplifier-report.md has no _test_evidence frontmatter (agents/simplifier.md), so the
# content gate is file existence + non-empty — the existence substrate matches
# fsm_eval_simplifier_present; an empty file is a content 'fail'.
compute_simplifier() {
  local marker="${EVIDENCE_DIR}/ca-review-complete"
  local exec_yaml="${PROJECT_ROOT}/.aid-o/config/execution.yaml"
  local report="${EVIDENCE_DIR}/simplifier-report.md"
  SIMPLIFIER_ARTIFACT="simplifier-report.md"

  if [[ ! -f "$marker" ]]; then
    SIMPLIFIER_STATUS="not_applicable"; SIMPLIFIER_REASON="not_plan_boundary"; return 0
  fi
  local enabled=true
  _aid_read_toggle "$exec_yaml" "simplifier" || enabled=false
  if [[ "$enabled" == "false" ]]; then
    SIMPLIFIER_STATUS="disabled"; SIMPLIFIER_REASON="simplifier.enabled:false in execution.yaml"; return 0
  fi
  if [[ ! -f "$report" ]]; then
    SIMPLIFIER_STATUS="missing"; SIMPLIFIER_REASON="simplifier-report.md missing in evidence dir"; return 0
  fi
  if [[ -s "$report" ]]; then
    SIMPLIFIER_STATUS="pass"; SIMPLIFIER_REASON="simplifier-report.md present and non-empty"
  else
    SIMPLIFIER_STATUS="fail"; SIMPLIFIER_REASON="simplifier-report.md present but empty"
  fi
}

# run_verification_input — call aid-evidence-verify.sh --at-head, map to a single verdict.
# Sets VERIFICATION_VERDICT (pass|fail|unverifiable) and VERIFICATION_REASON.
# NEVER crashes: tool exit 2/10/20 → unverifiable+reason; per-check fail → fail (git-dirty
# and --at-head mismatch are `fail`, NOT unverifiable); per-check unverifiable → unverifiable.
run_verification_input() {
  VERIFICATION_VERDICT="unverifiable"
  VERIFICATION_REASON="verifier_tool_error harness_unavailable"
  [[ -f "$EVIDENCE_VERIFY" ]] || return 0

  local vr_tmp="" vr_exit=0 worst=""
  vr_tmp="$(mktemp "${TMPDIR:-/tmp}/aid-relpol-vr-XXXXXX.json" 2>/dev/null)" || vr_tmp=""
  [[ -z "$vr_tmp" ]] && { VERIFICATION_REASON="verifier_tool_error mktemp_failed"; return 0; }

  AID_PROJECT_ROOT="$PROJECT_ROOT" bash "$EVIDENCE_VERIFY" "$EPIC_ID" "$RUN_ID" \
    --out "$vr_tmp" --at-head >/dev/null 2>&1 || vr_exit=$?

  case "$vr_exit" in
    2|10|20)
      VERIFICATION_VERDICT="unverifiable"
      VERIFICATION_REASON="verifier_tool_error exit=${vr_exit}"
      ;;
    *)
      if [[ -f "$vr_tmp" ]] && _is_json "$vr_tmp"; then
        worst="$(jq -r '
          [.verification_report.checks[]?.status] as $s
          | if ($s | any(. == "fail")) then "fail"
            elif ($s | any(. == "unverifiable")) then "unverifiable"
            else "pass" end' "$vr_tmp" 2>/dev/null)" || worst=""
        case "$worst" in
          fail)         VERIFICATION_VERDICT="fail";         VERIFICATION_REASON="one or more evidence checks failed at HEAD" ;;
          unverifiable) VERIFICATION_VERDICT="unverifiable"; VERIFICATION_REASON="one or more evidence checks unverifiable" ;;
          pass)         VERIFICATION_VERDICT="pass";         VERIFICATION_REASON="all evidence checks passed at HEAD" ;;
          *)            VERIFICATION_VERDICT="unverifiable"; VERIFICATION_REASON="verifier_tool_error unparseable_report" ;;
        esac
      else
        VERIFICATION_VERDICT="unverifiable"
        VERIFICATION_REASON="verifier_tool_error report_missing (exit=${vr_exit})"
      fi
      ;;
  esac

  rm -f "$vr_tmp" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  # --- Arg parsing (no eval) ---
  local out_path="" _positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --out requires a path" >&2; exit 2; }
        out_path="$2"; shift 2 ;;
      -*)
        echo "aid-release-policy: unknown option: $1" >&2
        echo "Usage: aid-release-policy.sh <epic_id> <run_id> [--out <path>]" >&2
        exit 2 ;;
      *)
        _positional+=("$1"); shift ;;
    esac
  done
  if [[ "${#_positional[@]}" -ne 2 ]]; then
    echo "Usage: aid-release-policy.sh <epic_id> <run_id> [--out <path>]" >&2
    exit 2
  fi
  EPIC_ID="${_positional[0]}"
  RUN_ID="${_positional[1]}"
  if [[ ! "$EPIC_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "aid-release-policy: invalid EPIC_ID '$EPIC_ID' (must match [A-Za-z0-9._-]+)" >&2; exit 2
  fi
  if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "aid-release-policy: invalid RUN_ID '$RUN_ID' (must match [A-Za-z0-9._-]+)" >&2; exit 2
  fi

  # --- Root + HEAD resolution (mirror aid-evidence-verify) ---
  if [[ -n "${AID_PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$AID_PROJECT_ROOT"
  else
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || PROJECT_ROOT="."
  fi
  EVIDENCE_DIR="${PROJECT_ROOT}/.aid-o/work/evidence/${EPIC_ID}/${RUN_ID}"
  CURRENT_HEAD="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || CURRENT_HEAD=""

  # --- REQUIRED presence rows ---
  check_required_present review_profile        review_profile        "${EVIDENCE_DIR}/review-profile.json"
  check_required_present delivery_gate         delivery_gate         "${EVIDENCE_DIR}/delivery-gate.json"
  check_required_present semantic_review_final semantic_review_final "${EVIDENCE_DIR}/semantic-review-final.json"
  check_required_present acceptance_evidence   acceptance_evidence   "${EVIDENCE_DIR}/acceptance-evidence.json"

  # --- gates_report (root, fallback gates/) ---
  local gates_report_path=""
  if [[ -f "${EVIDENCE_DIR}/gates_report.json" ]]; then
    gates_report_path="${EVIDENCE_DIR}/gates_report.json"
  elif [[ -f "${EVIDENCE_DIR}/gates/gates_report.json" ]]; then
    gates_report_path="${EVIDENCE_DIR}/gates/gates_report.json"
  fi
  if [[ -n "$gates_report_path" ]] && _is_json "$gates_report_path"; then
    add_input gates_report "gates_report.json" "pass" "present at ${gates_report_path#"${EVIDENCE_DIR}/"}" "$(_artifact_head_match "$gates_report_path")"
  else
    add_input gates_report "gates_report.json" "blocked" "gates_report.json missing (checked root and gates/ subdir)" false
    add_blocker gates_report "blocking" "gates_report.json missing (checked root and gates/ subdir)"
  fi

  # --- plan-review (plan_ref hop via epic_input.md frontmatter) ---
  local epic_input="${EVIDENCE_DIR}/epic_input.md"
  local plan_ref plan_review_ok=false plan_review_reason="" plan_review_hm=false
  plan_ref="$(_extract_plan_ref "$epic_input")"
  if [[ -z "$plan_ref" || "$plan_ref" == "null" ]]; then
    plan_review_reason="cannot resolve plan_ref from epic_input.md frontmatter"
  else
    local planref_base planref_id plan_review_file
    planref_base="$(basename "$plan_ref")"
    planref_id="${planref_base%.md}"
    plan_review_file="${PROJECT_ROOT}/.aid-o/work/evidence/${planref_id}/c0/plan-review.json"
    if _is_json "$plan_review_file"; then
      plan_review_ok=true
      plan_review_reason="present at .aid-o/work/evidence/${planref_id}/c0/plan-review.json"
      plan_review_hm="$(_artifact_head_match "$plan_review_file")"
    else
      plan_review_reason="plan-review.json missing at .aid-o/work/evidence/${planref_id}/c0/"
    fi
  fi
  if [[ "$plan_review_ok" == "true" ]]; then
    add_input plan_review "plan-review.json" "pass" "$plan_review_reason" "$plan_review_hm"
  else
    add_input plan_review "plan-review.json" "blocked" "$plan_review_reason" false
    add_blocker plan_review "blocking" "$plan_review_reason"
  fi

  # --- verification-report (aid-evidence-verify.sh --at-head) ---
  run_verification_input
  local evidence_verified_at_head=false vr_head_match=false
  [[ "$VERIFICATION_VERDICT" == "pass" ]] && { evidence_verified_at_head=true; vr_head_match=true; }
  add_input verification_report "aid-evidence-verify.sh@--at-head" "$VERIFICATION_VERDICT" "$VERIFICATION_REASON" "$vr_head_match"
  if [[ "$VERIFICATION_VERDICT" != "pass" ]]; then
    add_blocker verification_report "blocking" "verification (--at-head) ${VERIFICATION_VERDICT}: ${VERIFICATION_REASON}"
  fi

  # --- profile-gated curator-report + audit-report (same C3 gate for both) ---
  C3_ACTIVE=false
  _c3_gate_active "$EVIDENCE_DIR" && C3_ACTIVE=true
  process_profile_gated curator_report "${EVIDENCE_DIR}/curator-report.json"
  process_profile_gated audit_report   "${EVIDENCE_DIR}/audit-report.json"

  # --- invalidation-map (ADVISORY — never blocks) ---
  local inv_map="${EVIDENCE_DIR}/invalidation-map.json"
  if _is_json "$inv_map"; then
    add_input invalidation_map "invalidation-map.json" "advisory" "present (advisory)" "$(_artifact_head_match "$inv_map")"
  else
    add_input invalidation_map "invalidation-map.json" "advisory" "advisory-missing (does not block)" true
  fi

  # --- Reporter / Simplifier CONDITIONAL ---
  compute_reporter
  compute_simplifier
  add_input reporter    "$REPORTER_ARTIFACT"    "$(_status_to_verdict "$REPORTER_STATUS")"    "$REPORTER_REASON"    "$(_status_headmatch "$REPORTER_STATUS")"
  add_input simplifier  "$SIMPLIFIER_ARTIFACT"  "$(_status_to_verdict "$SIMPLIFIER_STATUS")"  "$SIMPLIFIER_REASON"  "$(_status_headmatch "$SIMPLIFIER_STATUS")"
  case "$REPORTER_STATUS" in
    missing|fail) add_blocker reporter "blocking" "reporter ${REPORTER_STATUS}: ${REPORTER_REASON}" ;;
  esac
  case "$SIMPLIFIER_STATUS" in
    missing|fail) add_blocker simplifier "blocking" "simplifier ${SIMPLIFIER_STATUS}: ${SIMPLIFIER_REASON}" ;;
  esac

  # --- waivers (OPTIONAL) → waivers_applied[] ---
  local wf
  for wf in "${EVIDENCE_DIR}"/waiver-*.json; do
    [[ -f "$wf" ]] || continue
    WAIVERS_JSON="$(jq -cn --argjson arr "$WAIVERS_JSON" --arg w "$(basename "$wf")" '$arr + [$w]')"
  done
  local waiver_count
  waiver_count="$(jq 'length' <<<"$WAIVERS_JSON")"

  # --- profile_hash_freshness (review-profile ↔ semantic-review; field optional) ---
  local rp="${EVIDENCE_DIR}/review-profile.json" sr="${EVIDENCE_DIR}/semantic-review-final.json"
  local rp_hash="" sr_hash="" profile_hash_freshness="not_evaluated"
  _is_json "$rp" && rp_hash="$(jq -r '.review_profile.profile_hash // ""' "$rp" 2>/dev/null || echo "")"
  _is_json "$sr" && sr_hash="$(jq -r '.semantic_review.profile_hash // ""' "$sr" 2>/dev/null || echo "")"
  if [[ -z "$rp_hash" || -z "$sr_hash" ]]; then
    profile_hash_freshness="not_evaluated"
  elif [[ "$rp_hash" == "$sr_hash" ]]; then
    profile_hash_freshness="evaluated"
  else
    profile_hash_freshness="mismatch"
  fi

  # --- release_ready + merge_mode ---
  local blocker_count release_ready=false merge_mode
  blocker_count="$(jq 'length' <<<"$BLOCKERS_JSON")"
  if [[ "$blocker_count" -eq 0 && "$evidence_verified_at_head" == "true" ]]; then
    release_ready=true
  fi
  if [[ "$release_ready" == "true" ]]; then
    merge_mode="$(_read_autonomous_mode)"   # auto | manual
  else
    merge_mode="blocked"
  fi

  # --- delivered_summary_ref (epic-summary.md → final_report.md → null) ---
  local dsr="" delivered_summary_ref_json="null"
  if [[ -f "${EVIDENCE_DIR}/epic-summary.md" ]]; then
    dsr="${EVIDENCE_DIR}/epic-summary.md"
  elif [[ -f "${EVIDENCE_DIR}/final_report.md" ]]; then
    dsr="${EVIDENCE_DIR}/final_report.md"
  fi
  if [[ -n "$dsr" ]]; then
    local dsr_rel="${dsr#"${PROJECT_ROOT}/"}"
    delivered_summary_ref_json="$(jq -n --arg p "$dsr_rel" '$p')"
  fi

  # --- summary_for_pm (mechanical template — no LLM) ---
  local summary_for_pm
  summary_for_pm="release_ready=${release_ready}; evidence=${VERIFICATION_VERDICT}; reporter=${REPORTER_STATUS}; simplifier=${SIMPLIFIER_STATUS}; waivers=${waiver_count}; blockers=${blocker_count}; merge_mode=${merge_mode}"

  # --- envelope-derived fields ---
  local created_at project_id status verdict_kind verdict_ready head_sha
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  project_id="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null | sed 's|.*[/:]||;s|\.git$||')" || project_id=""
  [[ -z "$project_id" ]] && project_id="$(basename "$PROJECT_ROOT" 2>/dev/null)"
  [[ -z "$project_id" || "$project_id" == "/" || "$project_id" == "." ]] && project_id="unknown"
  if [[ "$release_ready" == "true" ]]; then
    status="pass"; verdict_kind="release_ready"; verdict_ready=true
  else
    status="blocked"; verdict_kind="none"; verdict_ready=false
  fi
  head_sha="${CURRENT_HEAD:-unknown}"

  # --- release_decision payload (built first, for the subject_hash) ---
  local release_decision_payload
  release_decision_payload="$(jq -n \
    --argjson release_ready "$release_ready" \
    --arg decided_by "C4" \
    --argjson inputs "$INPUTS_JSON" \
    --argjson blockers "$BLOCKERS_JSON" \
    --argjson waivers "$WAIVERS_JSON" \
    --arg profile_hash_freshness "$profile_hash_freshness" \
    --arg merge_mode "$merge_mode" \
    --argjson pm_brief_required true \
    --arg pm_brief_status "pending" \
    --argjson evidence_verified_at_head "$evidence_verified_at_head" \
    --arg evidence_verification_status "$VERIFICATION_VERDICT" \
    --arg reporter_status "$REPORTER_STATUS" \
    --arg reporter_reason "$REPORTER_REASON" \
    --arg simplifier_status "$SIMPLIFIER_STATUS" \
    --arg simplifier_reason "$SIMPLIFIER_REASON" \
    --argjson delivered_summary_ref "$delivered_summary_ref_json" \
    --arg summary_for_pm "$summary_for_pm" \
    '{
      release_ready: $release_ready,
      decided_by: $decided_by,
      inputs: $inputs,
      blockers: $blockers,
      waivers_applied: $waivers,
      profile_hash_freshness: $profile_hash_freshness,
      merge_mode: $merge_mode,
      pm_brief_required: $pm_brief_required,
      pm_brief_status: $pm_brief_status,
      evidence_verified_at_head: $evidence_verified_at_head,
      evidence_verification_status: $evidence_verification_status,
      reporter_status: $reporter_status,
      reporter_reason: $reporter_reason,
      simplifier_status: $simplifier_status,
      simplifier_reason: $simplifier_reason,
      delivered_summary_ref: $delivered_summary_ref,
      summary_for_pm: $summary_for_pm
    }')"

  local payload_hash subject_hash
  payload_hash="$(jq -Sc . <<<"$release_decision_payload" | sha256sum | cut -d' ' -f1 | cut -c1-64)"
  subject_hash="sha256:${payload_hash}"

  # --- full protocol-v2 envelope ---
  local final_json
  final_json="$(jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "release_decision" \
    --arg producer "aid-release-policy.sh@1.0" \
    --arg created_at "$created_at" \
    --arg control_protocol "aid-2.0" \
    --arg project_id "$project_id" \
    --arg epic_id "$EPIC_ID" \
    --arg run_id "$RUN_ID" \
    --arg subject_hash "$subject_hash" \
    --arg head_sha "$head_sha" \
    --arg status "$status" \
    --arg verdict_kind "$verdict_kind" \
    --argjson verdict_ready "$verdict_ready" \
    --argjson release_decision "$release_decision_payload" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: {project_id: $project_id, epic_id: $epic_id, run_id: $run_id, step_id: null},
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: $status,
      verdict: {kind: $verdict_kind, ready: $verdict_ready},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-release-policy.sh"},
      release_decision: $release_decision
    }')"

  # --- write output ---
  local final_out="${out_path:-${EVIDENCE_DIR}/release-decision.json}"
  mkdir -p "$(dirname "$final_out")" 2>/dev/null || true
  printf '%s\n' "$final_json" > "$final_out"

  # --- self-validate against the Step-3 schema (advisory warn; never blocks exit 0) ---
  if [[ -f "$PROTOCOL_VALIDATE" ]]; then
    if ! bash "$PROTOCOL_VALIDATE" "$final_out" >/dev/null 2>&1; then
      echo "aid-release-policy: WARNING: emitted release-decision.json failed protocol validation" >&2
    fi
  fi

  echo "aid-release-policy: wrote $final_out (release_ready=${release_ready}, merge_mode=${merge_mode})" >&2
  exit 0
}

main "$@"
