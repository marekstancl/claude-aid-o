#!/usr/bin/env bash
# Authoritative AID protocol v2 validator.
# Usage: aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]
#
# Validates an artifact JSON against the 11 blocking protocol invariants of the AID protocol v2.
# First violation wins. Returns non-zero on any violation.
#
# Exit codes:
#   0  — all checks pass (or legacy_skipped)
#   1  — usage error / dependency missing
#   2  — invalid JSON
#   3  — missing required envelope field
#   4  — bad schema_version
#   5  — bad artifact_type
#   6  — bad created_at format
#   7  — bad subject_hash format
#   8  — bad status or verdict.kind or control_protocol enum
#   9  — bad provenance
#  10  — per-finding invariant violation
#  11  — head freshness mismatch
#  12  — missing type-specific payload key
#  13  — nondeterministic fingerprint
#  14  — missing/invalid required audit_report subfield (provider/model/process_id/
#         input_manifest_hash/reviewed_head/required_independence_level; also enum on
#         required_independence_level & independence_level, boolean type on advisory)
#  15  — release_decision missing release_ready (D11 core state field)
#  16  — release_decision D11 state field missing or bad enum/type
#  17  — waiver reason too short (< 20 chars)
#  18  — pm_decision_brief bad communication_status enum

set -euo pipefail

# ---------------------------------------------------------------------------
# Arg parsing (no eval)
# ---------------------------------------------------------------------------
ARTIFACT_FILE=""
CURRENT_HEAD=""
CHECK_FINGERPRINT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --current-head)
      if [[ $# -lt 2 ]]; then
        echo "usage: aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]" >&2
        exit 1
      fi
      CURRENT_HEAD="$2"
      shift 2
      ;;
    --check-fingerprint)
      CHECK_FINGERPRINT=1
      shift
      ;;
    -*)
      echo "usage: aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]" >&2
      exit 1
      ;;
    *)
      if [[ -z "$ARTIFACT_FILE" ]]; then
        ARTIFACT_FILE="$1"
      else
        echo "usage: aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$ARTIFACT_FILE" ]]; then
  echo "usage: aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]" >&2
  exit 1
fi

if [[ ! -f "$ARTIFACT_FILE" ]]; then
  echo "usage: aid-protocol-validate.sh <artifact.json> [--current-head <sha>] [--check-fingerprint]" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
  echo "jq_required: jq not found in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINGERPRINT_HELPER="${SCRIPT_DIR}/lib/aid-finding-fingerprint.sh"

if [[ "$CHECK_FINGERPRINT" -eq 1 && ! -f "$FINGERPRINT_HELPER" ]]; then
  echo "fingerprint_helper_missing" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: JSON parse
# ---------------------------------------------------------------------------
if ! jq . "$ARTIFACT_FILE" >/dev/null 2>&1; then
  echo "invalid_json" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Step 2: legacy skip
# ---------------------------------------------------------------------------
cp=$(jq -r '.control_protocol // ""' "$ARTIFACT_FILE")
if [[ "$cp" == "legacy" ]]; then
  echo "legacy_skipped"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3: Envelope required fields
# ---------------------------------------------------------------------------
REQUIRED_FIELDS=(
  schema_version
  artifact_type
  producer
  created_at
  control_protocol
  identity
  subject
  revision
  status
  verdict
  provenance
)

for field in "${REQUIRED_FIELDS[@]}"; do
  val=$(jq -r --arg f "$field" '.[$f] // empty' "$ARTIFACT_FILE")
  if [[ -z "$val" ]]; then
    echo "missing_envelope_field:${field}" >&2
    exit 3
  fi
done

# identity.project_id must be non-empty string
project_id=$(jq -r '.identity.project_id // empty' "$ARTIFACT_FILE")
if [[ -z "$project_id" ]]; then
  echo "missing_envelope_field:identity.project_id" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Step 4: schema_version
# ---------------------------------------------------------------------------
schema_version=$(jq -r '.schema_version' "$ARTIFACT_FILE")
if [[ "$schema_version" != "aid-2.0" ]]; then
  echo "bad_schema_version" >&2
  exit 4
fi

# ---------------------------------------------------------------------------
# Step 5: artifact_type enum (20 values)
# ---------------------------------------------------------------------------
VALID_ARTIFACT_TYPES=(
  plan_review
  plan_graph
  contract_manifest
  review_profile
  delivery_gate
  ui_fidelity
  semantic_review
  acceptance_evidence
  consumption_proof
  audit_report
  audit_input_manifest
  release_decision
  pm_decision_brief
  curator
  delivery_report
  verification_report
  invalidation_map
  waiver
  c3_dispatch
  plan_boundary_manifest
)

artifact_type=$(jq -r '.artifact_type' "$ARTIFACT_FILE")
type_valid=0
for t in "${VALID_ARTIFACT_TYPES[@]}"; do
  if [[ "$artifact_type" == "$t" ]]; then
    type_valid=1
    break
  fi
done

if [[ "$type_valid" -eq 0 ]]; then
  echo "bad_artifact_type" >&2
  exit 5
fi

# ---------------------------------------------------------------------------
# Step 6: created_at ISO-8601 UTC format
# ---------------------------------------------------------------------------
created_at=$(jq -r '.created_at' "$ARTIFACT_FILE")
if ! [[ "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "bad_created_at" >&2
  exit 6
fi

# ---------------------------------------------------------------------------
# Step 7: subject_hash format
# ---------------------------------------------------------------------------
subject_hash=$(jq -r '.subject.subject_hash // ""' "$ARTIFACT_FILE")
if ! [[ "$subject_hash" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "bad_subject_hash" >&2
  exit 7
fi

# ---------------------------------------------------------------------------
# Step 8: status and verdict.kind enums
# ---------------------------------------------------------------------------
VALID_STATUS=(pass fail skip unverifiable pending blocked)
status=$(jq -r '.status' "$ARTIFACT_FILE")
status_valid=0
for s in "${VALID_STATUS[@]}"; do
  if [[ "$status" == "$s" ]]; then
    status_valid=1
    break
  fi
done
if [[ "$status_valid" -eq 0 ]]; then
  echo "bad_enum:status" >&2
  exit 8
fi

VALID_VERDICT_KIND=(none delivery_ready release_ready)
verdict_kind=$(jq -r '.verdict.kind // ""' "$ARTIFACT_FILE")
verdict_valid=0
for v in "${VALID_VERDICT_KIND[@]}"; do
  if [[ "$verdict_kind" == "$v" ]]; then
    verdict_valid=1
    break
  fi
done
if [[ "$verdict_valid" -eq 0 ]]; then
  echo "bad_enum:verdict.kind" >&2
  exit 8
fi

# control_protocol must be "aid-2.0" (legacy already handled in step 2)
cp_val=$(jq -r '.control_protocol' "$ARTIFACT_FILE")
if [[ "$cp_val" != "aid-2.0" ]]; then
  echo "bad_enum:control_protocol" >&2
  exit 8
fi

# ---------------------------------------------------------------------------
# Step 9: provenance
# ---------------------------------------------------------------------------
VALID_DISPATCH_MODES=(deterministic agent_tool subagent)
dispatch_mode=$(jq -r '.provenance.dispatch_mode // ""' "$ARTIFACT_FILE")
dispatch_valid=0
for d in "${VALID_DISPATCH_MODES[@]}"; do
  if [[ "$dispatch_mode" == "$d" ]]; then
    dispatch_valid=1
    break
  fi
done
if [[ "$dispatch_valid" -eq 0 ]]; then
  echo "bad_provenance" >&2
  exit 9
fi

generated_by_tool=$(jq -r '.provenance.generated_by_tool // ""' "$ARTIFACT_FILE")
if [[ -z "$generated_by_tool" ]]; then
  echo "bad_provenance" >&2
  exit 9
fi

# ---------------------------------------------------------------------------
# Step 10: per-finding invariants (only if .findings is present and non-empty)
# ---------------------------------------------------------------------------
has_findings=$(jq 'if (.findings | type) == "array" and (.findings | length) > 0 then "yes" else "no" end' "$ARTIFACT_FILE" -r)

if [[ "$has_findings" == "yes" ]]; then
  findings_count=$(jq '.findings | length' "$ARTIFACT_FILE")

  for (( i=0; i<findings_count; i++ )); do
    # fingerprint format
    fp=$(jq -r --argjson i "$i" '.findings[$i].fingerprint // ""' "$ARTIFACT_FILE")
    if ! [[ "$fp" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      echo "bad_finding_fingerprint:index=${i}" >&2
      exit 10
    fi

    # occurrence_id non-empty
    occ=$(jq -r --argjson i "$i" '.findings[$i].occurrence_id // ""' "$ARTIFACT_FILE")
    if [[ -z "$occ" ]]; then
      echo "missing_occurrence_id:index=${i}" >&2
      exit 10
    fi

    # severity enum
    VALID_SEVERITY=(critical high medium low info)
    sev=$(jq -r --argjson i "$i" '.findings[$i].severity // ""' "$ARTIFACT_FILE")
    sev_valid=0
    for sv in "${VALID_SEVERITY[@]}"; do
      if [[ "$sev" == "$sv" ]]; then
        sev_valid=1
        break
      fi
    done
    if [[ "$sev_valid" -eq 0 ]]; then
      echo "bad_finding_severity:index=${i}" >&2
      exit 10
    fi

    # action_owner required for critical/high
    if [[ "$sev" == "critical" || "$sev" == "high" ]]; then
      VALID_ACTION_OWNER=(implementer reviewer pm gate-fixer)
      action_owner=$(jq -r --argjson i "$i" '.findings[$i].action_owner // ""' "$ARTIFACT_FILE")
      ao_valid=0
      for ao in "${VALID_ACTION_OWNER[@]}"; do
        if [[ "$action_owner" == "$ao" ]]; then
          ao_valid=1
          break
        fi
      done
      if [[ "$ao_valid" -eq 0 ]]; then
        echo "blocker_without_action_owner" >&2
        exit 10
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# Step 11: head freshness (only if --current-head was provided)
# ---------------------------------------------------------------------------
if [[ -n "$CURRENT_HEAD" ]]; then
  head_sha=$(jq -r '.revision.head_sha // ""' "$ARTIFACT_FILE")
  head_is_current=$(jq -r '.revision.head_is_current // ""' "$ARTIFACT_FILE")
  freshness=$(jq -r '.revision.freshness // ""' "$ARTIFACT_FILE")

  if [[ "$head_sha" == "$CURRENT_HEAD" ]]; then
    # head matches — head_is_current must be true, freshness must be "current"
    if [[ "$head_is_current" != "true" ]] || [[ "$freshness" != "current" ]]; then
      echo "stale_or_head_mismatch" >&2
      exit 11
    fi
  else
    # head does not match — head_is_current must be false, freshness must be "stale"
    if [[ "$head_is_current" != "false" ]] || [[ "$freshness" != "stale" ]]; then
      echo "stale_or_head_mismatch" >&2
      exit 11
    fi
    # The actual sha doesn't match the current head
    echo "stale_or_head_mismatch" >&2
    exit 11
  fi
fi

# ---------------------------------------------------------------------------
# Step 12: type-specific payload key
# ---------------------------------------------------------------------------
declare -A TYPE_PAYLOAD_MAP
TYPE_PAYLOAD_MAP[plan_review]="plan_review"
TYPE_PAYLOAD_MAP[plan_graph]="plan_graph"
TYPE_PAYLOAD_MAP[contract_manifest]="contract_manifest"
TYPE_PAYLOAD_MAP[review_profile]="review_profile"
TYPE_PAYLOAD_MAP[delivery_gate]="delivery_gate"
TYPE_PAYLOAD_MAP[ui_fidelity]="ui_fidelity"
TYPE_PAYLOAD_MAP[semantic_review]="semantic_review"
TYPE_PAYLOAD_MAP[acceptance_evidence]="acceptance_evidence"
TYPE_PAYLOAD_MAP[consumption_proof]="consumption_proof"
TYPE_PAYLOAD_MAP[audit_report]="audit_report"
TYPE_PAYLOAD_MAP[audit_input_manifest]="audit_input_manifest"
TYPE_PAYLOAD_MAP[release_decision]="release_decision"
TYPE_PAYLOAD_MAP[pm_decision_brief]="pm_decision_brief"
TYPE_PAYLOAD_MAP[curator]="curator"
TYPE_PAYLOAD_MAP[delivery_report]="delivery_report"
TYPE_PAYLOAD_MAP[verification_report]="verification_report"
TYPE_PAYLOAD_MAP[invalidation_map]="invalidation_map"
TYPE_PAYLOAD_MAP[waiver]="waiver"
# P065 E-065-7_7 post-merge fix ("control_protocol envelope" finding, 10th
# DONE-review audit): c3-dispatch.json (aid-c3-dispatch.sh's dispatch-side
# provenance record) declares schema_version:"aid-2.0" and is therefore
# swept into aid-evidence-verify.sh's V2_ARTIFACTS scan unconditionally
# (any JSON file with schema_version=="aid-2.0" and control_protocol!=
# "legacy" gets fully validated — there is no artifact-type allowlist at
# that layer). It was missing the FULL envelope (control_protocol,
# identity, revision, status, verdict — not just control_protocol) AND was
# never registered here, so every real C3-active EPIC's evidence pack has
# always failed aid-evidence-verify.sh's verification_report step — never
# caught because aid-release-policy.sh's verification_report input had
# itself never actually been run for real against a live C3-bridge EPIC
# until this was discovered. "dispatch" (not "c3_dispatch") is deliberately
# reused as the payload key: it is the artifact's existing, already-present
# distinguishing content (invoked/exit_code/outcome/etc.) — no restructuring
# of aid-c3-dispatch.sh's established shape was needed to satisfy this.
TYPE_PAYLOAD_MAP[c3_dispatch]="dispatch"
# P064 E-064-1_2 Step 2: plan-boundary-manifest.json (plan/Pxxx as the
# integration branch for a plan's EPICs) becomes a first-class protocol-v2
# artifact so identity/freshness/payload-presence are validated by this
# generic validator rather than ad-hoc checks. The deeper field-level
# invariants (uniqueness, subset, conditional requireds, path containment,
# profile monotonicity) are enforced by a LATER step (lib/aid-plan-manifest.sh
# via hand-written jq -e checks), not here — this step only proves the
# payload key is present, same as every other type in this map.
TYPE_PAYLOAD_MAP[plan_boundary_manifest]="plan_boundary_manifest"

payload_key="${TYPE_PAYLOAD_MAP[$artifact_type]:-}"
if [[ -n "$payload_key" ]]; then
  payload_present=$(jq -r --arg k "$payload_key" 'if .[$k] != null then "yes" else "no" end' "$ARTIFACT_FILE")
  if [[ "$payload_present" != "yes" ]]; then
    echo "missing_type_payload:${payload_key}" >&2
    exit 12
  fi
fi

# ---------------------------------------------------------------------------
# Step 14: C3 audit_report required subfields (D7 — provider/model/process_id must be
# echoed from audit_trigger, never self-introspected; input_manifest_hash is the
# provenance binding). defaults/schemas/audit-report.schema.json declares these 4
# fields `required` on the .audit_report payload, but Step 12 above only checks that
# the payload KEY is present — it never descends into the payload, so a report missing
# these fields previously passed this validator with exit 0 despite the schema's own
# claim that they're mandatory (E-057-1_2 IMP-174, found by PM review of R-E057-1).
# Only applies to artifact_type == audit_report; other types are untouched.
# ---------------------------------------------------------------------------
if [[ "$artifact_type" == "audit_report" ]]; then
  # P065 E-065-1_7 Step 4: reviewed_head + required_independence_level added to the
  # UNCONDITIONAL required-subfield loop. They are the C3 cross-provider provenance
  # the FSM/verify chain binds to — the exact commit the audit reviewed, and the
  # independence level it was required to run at. All six must be present, string-
  # typed, and non-empty. First missing field wins (exit 14).
  # (codex_brief_hash is validated by the bridge's own `verify` step — a LATER EPIC —
  #  NOT here; input_manifest_hash keeps its legacy provenance-binding meaning.)
  for field in provider model process_id input_manifest_hash reviewed_head required_independence_level; do
    field_present=$(jq -r --arg f "$field" 'if (.audit_report[$f] // null) != null and (.audit_report[$f] | type) == "string" and (.audit_report[$f] | length) > 0 then "yes" else "no" end' "$ARTIFACT_FILE")
    if [[ "$field_present" != "yes" ]]; then
      echo "missing_audit_report_field:${field}" >&2
      exit 14
    fi
  done

  # required_independence_level enum (mandatory field, checked above for presence).
  req_indep=$(jq -r '.audit_report.required_independence_level // ""' "$ARTIFACT_FILE")
  case "$req_indep" in
    context_only|cross_model|cross_provider) ;;
    *) echo "bad_audit_report_enum:required_independence_level" >&2; exit 14 ;;
  esac

  # independence_level enum (OPTIONAL field — the level actually achieved; only
  # enum-checked when the key is present).
  if [[ "$(jq -r 'if (.audit_report | has("independence_level")) then "yes" else "no" end' "$ARTIFACT_FILE")" == "yes" ]]; then
    indep=$(jq -r '.audit_report.independence_level // ""' "$ARTIFACT_FILE")
    case "$indep" in
      context_only|cross_model|cross_provider) ;;
      *) echo "bad_audit_report_enum:independence_level" >&2; exit 14 ;;
    esac
  fi

  # advisory (OPTIONAL) must be a boolean when present.
  if [[ "$(jq -r 'if (.audit_report | has("advisory")) then "yes" else "no" end' "$ARTIFACT_FILE")" == "yes" ]]; then
    advisory_type=$(jq -r '.audit_report.advisory | type' "$ARTIFACT_FILE")
    if [[ "$advisory_type" != "boolean" ]]; then
      echo "bad_audit_report_type:advisory" >&2
      exit 14
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Step 15: release_decision release_ready presence (E-059-2 D11 core state).
# The release_decision payload MUST carry an explicit release_ready boolean —
# the FSM's merge gate reads it directly. Step 12 only proved the .release_decision
# key exists; this descends into the payload. Same Step-14 pattern, distinct code.
# Only applies to artifact_type == release_decision.
# ---------------------------------------------------------------------------
if [[ "$artifact_type" == "release_decision" ]]; then
  release_ready_type=$(jq -r '.release_decision.release_ready | type' "$ARTIFACT_FILE")
  if [[ "$release_ready_type" != "boolean" ]]; then
    echo "missing_release_ready" >&2
    exit 15
  fi
fi

# ---------------------------------------------------------------------------
# Step 16: release_decision D11 explicit state fields (E-059-2). release-decision.json
# must carry all 11 D11 fields with valid enums/types so the FSM merge gate and the PM
# brief never infer state. dual_run is OPTIONAL (FSM-patched in a later step) and is
# NOT checked here. Runs after Step 15 so a missing release_ready reports as exit 15.
# Only applies to artifact_type == release_decision.
# ---------------------------------------------------------------------------
if [[ "$artifact_type" == "release_decision" ]]; then
  # 16a — presence of all 11 D11 fields (delivered_summary_ref is required-but-nullable,
  # so presence is a has() check; its value may legitimately be null).
  for d11_field in merge_mode pm_brief_required pm_brief_status evidence_verified_at_head \
                   evidence_verification_status reporter_status reporter_reason \
                   simplifier_status simplifier_reason delivered_summary_ref summary_for_pm; do
    d11_present=$(jq -r --arg f "$d11_field" 'if (.release_decision | has($f)) then "yes" else "no" end' "$ARTIFACT_FILE")
    if [[ "$d11_present" != "yes" ]]; then
      echo "missing_d11_field:${d11_field}" >&2
      exit 16
    fi
  done

  # 16b — enum validation (single-value fields)
  d11_merge_mode=$(jq -r '.release_decision.merge_mode // ""' "$ARTIFACT_FILE")
  case "$d11_merge_mode" in manual|auto|blocked) ;; *) echo "bad_d11_enum:merge_mode" >&2; exit 16 ;; esac

  d11_pm_brief_status=$(jq -r '.release_decision.pm_brief_status // ""' "$ARTIFACT_FILE")
  case "$d11_pm_brief_status" in pending|generated|failed|incomplete) ;; *) echo "bad_d11_enum:pm_brief_status" >&2; exit 16 ;; esac

  d11_evs=$(jq -r '.release_decision.evidence_verification_status // ""' "$ARTIFACT_FILE")
  case "$d11_evs" in pass|fail|unverifiable) ;; *) echo "bad_d11_enum:evidence_verification_status" >&2; exit 16 ;; esac

  # 16c — enum validation (reporter/simplifier share one enum)
  for d11_status_field in reporter_status simplifier_status; do
    d11_status_val=$(jq -r --arg f "$d11_status_field" '.release_decision[$f] // ""' "$ARTIFACT_FILE")
    case "$d11_status_val" in
      pass|fail|missing|not_applicable|disabled) ;;
      *) echo "bad_d11_enum:${d11_status_field}" >&2; exit 16 ;;
    esac
  done

  # 16d — boolean type validation
  for d11_bool_field in pm_brief_required evidence_verified_at_head; do
    d11_bool_type=$(jq -r --arg f "$d11_bool_field" '.release_decision[$f] | type' "$ARTIFACT_FILE")
    if [[ "$d11_bool_type" != "boolean" ]]; then
      echo "bad_d11_type:${d11_bool_field}" >&2
      exit 16
    fi
  done

  # 16e — non-empty string validation
  for d11_str_field in reporter_reason simplifier_reason summary_for_pm; do
    d11_str_ok=$(jq -r --arg f "$d11_str_field" 'if (.release_decision[$f] | type) == "string" and (.release_decision[$f] | length) > 0 then "yes" else "no" end' "$ARTIFACT_FILE")
    if [[ "$d11_str_ok" != "yes" ]]; then
      echo "bad_d11_type:${d11_str_field}" >&2
      exit 16
    fi
  done

  # 16f — delivered_summary_ref must be string or null (required-but-nullable)
  d11_dsr_type=$(jq -r '.release_decision.delivered_summary_ref | type' "$ARTIFACT_FILE")
  if [[ "$d11_dsr_type" != "string" && "$d11_dsr_type" != "null" ]]; then
    echo "bad_d11_type:delivered_summary_ref" >&2
    exit 16
  fi
fi

# ---------------------------------------------------------------------------
# Step 17: waiver reason minimum length (E-059-2). A waiver is a visible governance
# record; its reason must be substantive (>= 20 chars) so a waiver can never be an
# empty rubber-stamp. Step 12 already proved .waiver exists. Only applies to waiver.
# ---------------------------------------------------------------------------
if [[ "$artifact_type" == "waiver" ]]; then
  waiver_reason_len=$(jq -r '(.waiver.reason // "") | length' "$ARTIFACT_FILE")
  if [[ "$waiver_reason_len" -lt 20 ]]; then
    echo "waiver_reason_too_short:len=${waiver_reason_len}" >&2
    exit 17
  fi
fi

# ---------------------------------------------------------------------------
# Step 18: pm_decision_brief communication_status enum (E-059-2). The brief must
# declare an explicit communication_status so the PM surface never renders an
# ambiguous state. Only applies to artifact_type == pm_decision_brief.
# ---------------------------------------------------------------------------
if [[ "$artifact_type" == "pm_decision_brief" ]]; then
  brief_comm_status=$(jq -r '.pm_decision_brief.communication_status // ""' "$ARTIFACT_FILE")
  case "$brief_comm_status" in
    complete|incomplete) ;;
    *) echo "bad_communication_status" >&2; exit 18 ;;
  esac
fi

# ---------------------------------------------------------------------------
# Step 13: fingerprint determinism (only if --check-fingerprint was provided)
#
# Two formulas, dispatched by artifact_type:
#   - audit_report (C3): fingerprint_audit_report() over occurrence_id/severity/
#     area/finding/recommendation — C3 findings are LLM-derived adversarial
#     discoveries with no check_id/target_path/finding_class (those fields
#     aren't in audit-report.schema.json). See aid-finding-fingerprint.sh for
#     why the universal 5-field formula below doesn't apply to this type.
#   - everything else: the universal fingerprint() formula
#     (project_id/artifact_type/check_id/target_path/finding_class), unchanged.
# ---------------------------------------------------------------------------
if [[ "$CHECK_FINGERPRINT" -eq 1 ]]; then
  # Source the fingerprint helper
  # shellcheck source=lib/aid-finding-fingerprint.sh
  source "$FINGERPRINT_HELPER"

  if [[ "$has_findings" == "yes" ]]; then
    findings_count=$(jq '.findings | length' "$ARTIFACT_FILE")

    for (( i=0; i<findings_count; i++ )); do
      stored_fp=$(jq -r --argjson i "$i" '.findings[$i].fingerprint // ""' "$ARTIFACT_FILE")

      if [[ "$artifact_type" == "audit_report" ]]; then
        occurrence_id_val=$(jq -r --argjson i "$i" '.findings[$i].occurrence_id // ""' "$ARTIFACT_FILE")
        severity_val=$(jq -r --argjson i "$i" '.findings[$i].severity // ""' "$ARTIFACT_FILE")
        area_val=$(jq -r --argjson i "$i" '.findings[$i].area // ""' "$ARTIFACT_FILE")
        finding_val=$(jq -r --argjson i "$i" '.findings[$i].finding // ""' "$ARTIFACT_FILE")
        recommendation_val=$(jq -r --argjson i "$i" '.findings[$i].recommendation // ""' "$ARTIFACT_FILE")
        computed_fp=$(fingerprint_audit_report "$project_id" "$artifact_type" "$occurrence_id_val" "$severity_val" "$area_val" "$finding_val" "$recommendation_val")
      else
        check_id=$(jq -r --argjson i "$i" '.findings[$i].check_id // ""' "$ARTIFACT_FILE")
        target_path=$(jq -r --argjson i "$i" '.findings[$i].target_path // ""' "$ARTIFACT_FILE")
        finding_class=$(jq -r --argjson i "$i" '.findings[$i].finding_class // ""' "$ARTIFACT_FILE")
        computed_fp=$(fingerprint "$project_id" "$artifact_type" "$check_id" "$target_path" "$finding_class")
      fi

      if [[ "$computed_fp" != "$stored_fp" ]]; then
        echo "nondeterministic_fingerprint" >&2
        exit 13
      fi
    done
  fi
fi

# ---------------------------------------------------------------------------
# All checks passed
# ---------------------------------------------------------------------------
exit 0
