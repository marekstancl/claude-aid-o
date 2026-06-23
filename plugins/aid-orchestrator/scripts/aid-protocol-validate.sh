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
# Step 5: artifact_type enum (14 values)
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
  audit_report
  audit_input_manifest
  release_decision
  pm_decision_brief
  curator
  delivery_report
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
TYPE_PAYLOAD_MAP[audit_report]="audit_report"
TYPE_PAYLOAD_MAP[audit_input_manifest]="audit_input_manifest"
TYPE_PAYLOAD_MAP[release_decision]="release_decision"
TYPE_PAYLOAD_MAP[pm_decision_brief]="pm_decision_brief"
TYPE_PAYLOAD_MAP[curator]="curator"
TYPE_PAYLOAD_MAP[delivery_report]="delivery_report"

payload_key="${TYPE_PAYLOAD_MAP[$artifact_type]:-}"
if [[ -n "$payload_key" ]]; then
  payload_present=$(jq -r --arg k "$payload_key" 'if .[$k] != null then "yes" else "no" end' "$ARTIFACT_FILE")
  if [[ "$payload_present" != "yes" ]]; then
    echo "missing_type_payload:${payload_key}" >&2
    exit 12
  fi
fi

# ---------------------------------------------------------------------------
# Step 13: fingerprint determinism (only if --check-fingerprint was provided)
# ---------------------------------------------------------------------------
if [[ "$CHECK_FINGERPRINT" -eq 1 ]]; then
  # Source the fingerprint helper
  # shellcheck source=lib/aid-finding-fingerprint.sh
  source "$FINGERPRINT_HELPER"

  if [[ "$has_findings" == "yes" ]]; then
    findings_count=$(jq '.findings | length' "$ARTIFACT_FILE")

    for (( i=0; i<findings_count; i++ )); do
      stored_fp=$(jq -r --argjson i "$i" '.findings[$i].fingerprint // ""' "$ARTIFACT_FILE")
      check_id=$(jq -r --argjson i "$i" '.findings[$i].check_id // ""' "$ARTIFACT_FILE")
      target_path=$(jq -r --argjson i "$i" '.findings[$i].target_path // ""' "$ARTIFACT_FILE")
      finding_class=$(jq -r --argjson i "$i" '.findings[$i].finding_class // ""' "$ARTIFACT_FILE")

      computed_fp=$(fingerprint "$project_id" "$artifact_type" "$check_id" "$target_path" "$finding_class")
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
