#!/usr/bin/env bash
# aid-acceptance-evidence.sh — Reconstruct acceptance-evidence.json from plan.json AC arrays
# and LLM-determined coverage signals in verifier step outputs.
#
# Usage:
#   aid-acceptance-evidence.sh reconstruct <plan.json> <evidence_dir> [--out <path>]
#
# Exit codes:
#   0 — success (acceptance-evidence.json emitted)
#   1 — error (missing argument, file not found, jq error)
#
# COVERAGE DETERMINATION (D3 — LLM matching, bash aggregates):
# The 'covered' field is determined by LLM (verifier agent) during CP2/CP3.
# This script reads those LLM-determined coverage signals and aggregates them
# into acceptance-evidence.json. Bash does NOT judge semantic coverage itself.
# If no LLM signal exists for an AC, covered=false (conservative default).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# reconstruct()
#
# Reads plan.json acceptance_criteria from each step, reads LLM matching
# results from verifier step outputs, and emits acceptance-evidence.json.
#
# Parameters:
#   $1 — path to plan.json
#   $2 — evidence directory (contains verifier-output-step-NN.md files)
#   $3 — (optional) --out <path> to override output path
# ---------------------------------------------------------------------------
reconstruct() {
  local plan_json="${1:-}"
  local evidence_dir="${2:-}"
  local out_path=""

  # Parse --out flag from remaining args
  shift 2 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        out_path="${2:-}"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  # Validate inputs
  if [[ -z "$plan_json" ]]; then
    echo "Error: plan.json path is required" >&2
    return 1
  fi
  if [[ ! -f "$plan_json" ]]; then
    echo "Error: plan.json not found: $plan_json" >&2
    return 1
  fi
  if [[ -z "$evidence_dir" ]]; then
    echo "Error: evidence_dir is required" >&2
    return 1
  fi
  if [[ ! -d "$evidence_dir" ]]; then
    echo "Error: evidence_dir not found: $evidence_dir" >&2
    return 1
  fi

  # Default output path
  if [[ -z "$out_path" ]]; then
    out_path="${evidence_dir}/acceptance-evidence.json"
  fi

  # Check jq dependency
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not found in PATH" >&2
    return 1
  fi
  if ! command -v sha256sum &>/dev/null; then
    echo "Error: sha256sum is required but not found in PATH" >&2
    return 1
  fi

  # Collect all acceptance criteria across steps
  # Returns a JSON array of {ac_text, step_idx} objects
  local criteria_json
  criteria_json=$(jq -r '
    .steps // [] | to_entries[] |
    . as $step_entry |
    ($step_entry.key) as $step_idx |
    ($step_entry.value.acceptance_criteria // []) | to_entries[] |
    {
      ac_text: .value,
      step_idx: $step_idx
    }
  ' "$plan_json" 2>/dev/null) || {
    echo "Error: Failed to parse plan.json with jq" >&2
    return 1
  }

  # Collect envelope fields (needed for both empty and full emit)
  local HEAD_SHA HEAD_SHORT PROJECT_ID CREATED_AT SUBJECT_HASH
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  HEAD_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  PROJECT_ID=$(grep -m1 'project_id:' "$(dirname "$plan_json")/../../../config/project.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
  if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "unknown" ]]; then
    PROJECT_ID=$(grep -m1 'project_id:' "$(find "$(dirname "$plan_json")" -name "project.yaml" 2>/dev/null | head -1)" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
  fi
  CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # Derive a valid sha256 64-hex subject_hash from HEAD_SHA
  SUBJECT_HASH=$(printf '%s' "$HEAD_SHA" | sha256sum | cut -c1-64)

  if [[ -z "$criteria_json" ]]; then
    # No acceptance criteria found — emit empty but valid structure with protocol-v2 envelope
    jq -n \
      --arg schema_version "aid-2.0" \
      --arg artifact_type "acceptance_evidence" \
      --arg producer "aid-acceptance-evidence.sh@2.44.0" \
      --arg created_at "$CREATED_AT" \
      --arg control_protocol "aid-2.0" \
      --arg project_id "$PROJECT_ID" \
      --arg subject_hash "sha256:${SUBJECT_HASH}" \
      --arg head_sha "$HEAD_SHA" \
      '{
        schema_version: $schema_version,
        artifact_type: $artifact_type,
        producer: $producer,
        created_at: $created_at,
        control_protocol: $control_protocol,
        identity: {project_id: $project_id},
        subject: {subject_hash: $subject_hash},
        revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
        status: "pass",
        verdict: {kind: "none", ready: false},
        provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-acceptance-evidence.sh"},
        acceptance_evidence: {
          coverage_mode: "llm_match",
          criteria: []
        }
      }' > "$out_path"
    echo "acceptance-evidence.json emitted (no AC found): $out_path" >&2
    return 0
  fi

  # Build criteria array with coverage signals
  # Process each AC: compute ac_id, look up LLM coverage from verifier output
  local criteria_array="[]"

  while IFS= read -r entry; do
    local ac_text step_idx
    ac_text=$(echo "$entry" | jq -r '.ac_text')
    step_idx=$(echo "$entry" | jq -r '.step_idx')

    # Compute ac_id: sha256[:12]_<step_num> where step_num is 1-indexed
    local hash step_num ac_id
    hash=$(printf '%s' "$ac_text" | sha256sum | cut -c1-12)
    step_num=$((step_idx + 1))
    ac_id="${hash}_${step_num}"

    # Evidence file for this step (1-indexed, no zero-padding)
    local evidence_ref
    evidence_ref="verifier-output-step-${step_num}.md"
    local evidence_file="${evidence_dir}/${evidence_ref}"

    # COVERAGE DETERMINATION (D3):
    # Read LLM-determined coverage signal from verifier output.
    # Bash only reads and aggregates — it does NOT evaluate semantic coverage.
    local covered deviation
    covered="false"
    deviation="missing"

    if [[ -f "$evidence_file" ]]; then
      # Look for ## AC Coverage section in verifier output
      if grep -q "## AC Coverage" "$evidence_file" 2>/dev/null; then
        # Extract covered field for this specific ac_id (LLM-generated)
        # Pattern: look for ac_id match then read covered: true/false on nearby line
        local ac_block
        ac_block=$(awk "/ac_id: \"${ac_id}\"/,/deviation:/" "$evidence_file" 2>/dev/null || true)

        if [[ -n "$ac_block" ]]; then
          local covered_val
          covered_val=$(echo "$ac_block" | grep -m1 'covered:' | awk '{print $2}' | tr -d '"' | tr -d "'" || true)
          if [[ "$covered_val" == "true" ]]; then
            covered="true"
            deviation="none"
          elif [[ "$covered_val" == "false" ]]; then
            covered="false"
            # Check for "changed" or "drift" mention in the block (LLM signal)
            if echo "$ac_block" | grep -qi 'changed\|drift' 2>/dev/null; then
              deviation="changed"
            else
              deviation="missing"
            fi
          fi
        else
          # AC section exists but this specific ac_id not listed — conservative default
          covered="false"
          # Check for global "changed" or "drift" mention for this AC text in file
          if grep -qi 'changed\|drift' "$evidence_file" 2>/dev/null; then
            deviation="changed"
          else
            deviation="missing"
          fi
        fi
      else
        # No ## AC Coverage section — no LLM signal available
        # covered=false is the conservative default (documented in D3 comment above)
        covered="false"
        deviation="missing"
      fi
    fi
    # If evidence file does not exist: covered=false, deviation=missing (already set)

    # Append to criteria array using jq
    local entry_json
    entry_json=$(jq -n \
      --arg ac_id "$ac_id" \
      --arg source "$ac_text" \
      --argjson covered "$covered" \
      --arg evidence_ref "$evidence_ref" \
      --arg deviation "$deviation" \
      '{
        ac_id: $ac_id,
        source: $source,
        covered: $covered,
        evidence_ref: $evidence_ref,
        deviation: $deviation
      }')

    criteria_array=$(echo "$criteria_array" | jq ". + [$entry_json]")

  done < <(echo "$criteria_json" | jq -c '.')

  # Emit acceptance-evidence.json with protocol-v2 envelope
  # observe — no blocking (D5)
  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "acceptance_evidence" \
    --arg producer "aid-acceptance-evidence.sh@2.44.0" \
    --arg created_at "$CREATED_AT" \
    --arg control_protocol "aid-2.0" \
    --arg project_id "$PROJECT_ID" \
    --arg subject_hash "sha256:${SUBJECT_HASH}" \
    --arg head_sha "$HEAD_SHA" \
    --argjson criteria "$criteria_array" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: {project_id: $project_id},
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: "pass",
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-acceptance-evidence.sh"},
      acceptance_evidence: {
        coverage_mode: "llm_match",
        criteria: $criteria
      }
    }' > "$out_path"

  echo "acceptance-evidence.json emitted (observe/best-effort): $out_path" >&2
  return 0
}

# ---------------------------------------------------------------------------
# main entry point — BASH_SOURCE guard for sourceable use
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"
  if [[ -z "$cmd" ]]; then
    echo "Usage: aid-acceptance-evidence.sh <command> [args]" >&2
    echo "Commands:" >&2
    echo "  reconstruct <plan.json> <evidence_dir> [--out <path>]" >&2
    exit 1
  fi

  case "$cmd" in
    reconstruct)
      shift
      reconstruct "$@"
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      echo "Usage: aid-acceptance-evidence.sh reconstruct <plan.json> <evidence_dir> [--out <path>]" >&2
      exit 1
      ;;
  esac
fi
