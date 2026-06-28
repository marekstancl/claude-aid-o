#!/usr/bin/env bash
# =============================================================================
# aid-c0-contract.sh — C0 Plan Contract Gate artifact producer
#
# Usage: aid-c0-contract.sh <subcommand> [args]
#
# Subcommands:
#   contract <plan.json> <c0_evidence_dir> [--out <path>]
#       Reads plan.json, derives dependency bindings, computes per-binding
#       hashes and a manifest_hash, then emits contract-manifest.json and
#       plan-graph.json to the evidence directory.
#       Exit 0 always unless plan.json is missing or invalid JSON (exit 1).
#
#   review   <plan.md>   <c0_evidence_dir> [--out <path>]
#       STUB — Step 3 will implement the 5 structural checks and lens evidence
#       scan. Currently emits a minimal plan-review.json and exits 0.
#
# Protocol v2 envelope fields (contract and plan-graph artifacts):
#   schema_version: aid-2.0
#   control_protocol: aid-2.0
#   producer: aid-c0-contract.sh@<version>
#   status: pending (C0 is observe-only; E5 is authoritative)
#   verdict.kind: none
#
# Requirements: bash 4.0+, jq, sha256sum, awk, git
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate lib directory relative to this script
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# ---------------------------------------------------------------------------
# Protocol v2 envelope constants
# ---------------------------------------------------------------------------
SCHEMA_VERSION="aid-2.0"
CONTROL_PROTOCOL="aid-2.0"
PRODUCER="aid-c0-contract.sh@1.0"

# ---------------------------------------------------------------------------
# Helper: build a minimal protocol v2 envelope around a payload
# Usage: _build_envelope <artifact_type> <payload_key> <payload_json> <project_root>
# Output: complete protocol v2 envelope JSON
# ---------------------------------------------------------------------------
_build_envelope() {
  local artifact_type="$1"
  local payload_key="$2"
  local payload_json="$3"
  local project_root="${4:-$PWD}"

  local created_at
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  local project_id
  project_id="$(basename "$project_root")"

  # Git metadata — gracefully fall back if not in a git repo
  local head_sha
  head_sha="$(git -C "$project_root" rev-parse HEAD 2>/dev/null)" || head_sha="0000000000000000000000000000000000000000"

  # Compute subject_hash from the payload
  local subject_hash
  subject_hash="sha256:$(printf '%s' "$payload_json" | sha256sum | awk '{print $1}')"

  jq -n \
    --arg schema_version     "$SCHEMA_VERSION" \
    --arg artifact_type      "$artifact_type" \
    --arg producer           "$PRODUCER" \
    --arg created_at         "$created_at" \
    --arg control_protocol   "$CONTROL_PROTOCOL" \
    --arg project_id         "$project_id" \
    --arg subject_hash       "$subject_hash" \
    --arg head_sha           "$head_sha" \
    --arg payload_key        "$payload_key" \
    --argjson payload        "$payload_json" \
    '{
      "schema_version":    $schema_version,
      "artifact_type":     $artifact_type,
      "producer":          $producer,
      "created_at":        $created_at,
      "control_protocol":  $control_protocol,
      "identity": {
        "project_id": $project_id
      },
      "subject": {
        "subject_hash": $subject_hash
      },
      "revision": {
        "head_sha":        $head_sha,
        "head_is_current": true,
        "freshness":       "current"
      },
      "status":  "pending",
      "verdict": { "kind": "none", "ready": false },
      "provenance": {
        "dispatch_mode":     "deterministic",
        "generated_by_tool": "aid-c0-contract.sh"
      }
    } + { ($payload_key): $payload }'
}

# ---------------------------------------------------------------------------
# Subcommand dispatch
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: aid-c0-contract.sh <subcommand> [args]" >&2
  echo "  contract <plan.json> <c0_evidence_dir> [--out <path>]" >&2
  echo "  review   <plan.md>   <c0_evidence_dir> [--out <path>]" >&2
  exit 1
fi

SUBCOMMAND="$1"
shift

# ===========================================================================
# Subcommand: contract
# ===========================================================================
cmd_contract() {
  # -------------------------------------------------------------------------
  # Arg parsing
  # -------------------------------------------------------------------------
  local plan_json=""
  local evidence_dir=""
  local out_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --out requires a path argument" >&2
          exit 1
        fi
        out_path="$2"
        shift 2
        ;;
      -*)
        echo "ERROR: Unknown flag: $1" >&2
        exit 1
        ;;
      *)
        if [[ -z "$plan_json" ]]; then
          plan_json="$1"
        elif [[ -z "$evidence_dir" ]]; then
          evidence_dir="$1"
        else
          echo "ERROR: Unexpected argument: $1" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$plan_json" || -z "$evidence_dir" ]]; then
    echo "Usage: aid-c0-contract.sh contract <plan.json> <c0_evidence_dir> [--out <path>]" >&2
    exit 1
  fi

  # -------------------------------------------------------------------------
  # Validate plan.json existence and JSON validity
  # -------------------------------------------------------------------------
  if [[ ! -f "$plan_json" ]]; then
    echo "ERROR: plan.json not found: $plan_json" >&2
    exit 1
  fi

  if ! jq . "$plan_json" >/dev/null 2>&1; then
    echo "ERROR: plan.json is not valid JSON: $plan_json" >&2
    exit 1
  fi

  # -------------------------------------------------------------------------
  # Source helper libs
  # -------------------------------------------------------------------------
  # shellcheck source=lib/aid-contract-hash.sh
  source "${LIB_DIR}/aid-contract-hash.sh"
  # shellcheck source=lib/aid-plan-graph.sh
  source "${LIB_DIR}/aid-plan-graph.sh"

  # -------------------------------------------------------------------------
  # Ensure evidence directory exists
  # -------------------------------------------------------------------------
  mkdir -p "$evidence_dir"

  # -------------------------------------------------------------------------
  # Resolve project root (directory containing plan.json, or its parent git root)
  # -------------------------------------------------------------------------
  local plan_dir
  plan_dir="$(dirname "$(cd "$(dirname "$plan_json")" && pwd)/$(basename "$plan_json")")"
  local project_root
  project_root="$(git -C "$plan_dir" rev-parse --show-toplevel 2>/dev/null)" || project_root="$plan_dir"

  # -------------------------------------------------------------------------
  # Step 1: Extract dependencies from plan.json
  # -------------------------------------------------------------------------
  # Read as "before->after" edge pairs (one per line)
  local deps_nl
  deps_nl="$(jq -r '.dependencies[]? | "\(.before)->\(.after)"' "$plan_json" 2>/dev/null || true)"

  # -------------------------------------------------------------------------
  # Step 2: Build bindings array and collect hashes
  # -------------------------------------------------------------------------
  local bindings_json="[]"
  local all_hashes=""

  if [[ -n "$deps_nl" ]]; then
    while IFS= read -r edge; do
      [[ -z "$edge" ]] && continue

      local producer="${edge%%->*}"
      local consumer="${edge##*->}"
      [[ -z "$producer" || -z "$consumer" ]] && continue

      local field="output"
      local status="pending"
      local provenance="plan_dependency"

      # Compute per-binding hash using \x1f separator
      local bhash
      bhash="$(binding_hash "$producer" "$consumer" "$field")"

      # Accumulate hashes for manifest_hash computation
      if [[ -z "$all_hashes" ]]; then
        all_hashes="$bhash"
      else
        all_hashes="${all_hashes}
${bhash}"
      fi

      # Append binding object to bindings JSON array
      bindings_json="$(printf '%s' "$bindings_json" | jq \
        --arg producer   "$producer" \
        --arg consumer   "$consumer" \
        --arg field      "$field" \
        --arg status     "$status" \
        --arg provenance "$provenance" \
        --arg hash       "$bhash" \
        '. + [{
          "producer":   $producer,
          "consumer":   $consumer,
          "field":      $field,
          "status":     $status,
          "provenance": $provenance,
          "hash":       $hash
        }]')"

    done <<< "$deps_nl"
  fi

  # -------------------------------------------------------------------------
  # Step 3: Compute manifest_hash over all binding hashes (lexicographic sort)
  # -------------------------------------------------------------------------
  local mhash
  mhash="$(manifest_hash "$all_hashes")"

  # -------------------------------------------------------------------------
  # Step 4: Build consumption_proof object
  # -------------------------------------------------------------------------
  # Status is ALWAYS "pending_slot" at C0 — verification is E5's responsibility
  local consumption_proof_json
  consumption_proof_json='{"state":"pending_slot","authoritative_phase":"E5"}'

  # -------------------------------------------------------------------------
  # Step 5: Assemble the inner contract_manifest payload
  # -------------------------------------------------------------------------
  local cm_payload
  cm_payload="$(jq -n \
    --argjson bindings          "$bindings_json" \
    --argjson consumption_proof "$consumption_proof_json" \
    --arg     manifest_hash     "$mhash" \
    '{
      "bindings":          $bindings,
      "consumption_proof": $consumption_proof,
      "manifest_hash":     $manifest_hash
    }')"

  # -------------------------------------------------------------------------
  # Step 6: Wrap in protocol v2 envelope and write contract-manifest.json
  # -------------------------------------------------------------------------
  local contract_manifest_json
  contract_manifest_json="$(_build_envelope "contract_manifest" "contract_manifest" "$cm_payload" "$project_root")"

  local contract_out
  if [[ -n "$out_path" ]]; then
    contract_out="$out_path"
  else
    contract_out="${evidence_dir}/contract-manifest.json"
  fi

  printf '%s\n' "$contract_manifest_json" > "$contract_out"

  # -------------------------------------------------------------------------
  # Step 7: Build plan-graph.json using aid-plan-graph.sh
  # -------------------------------------------------------------------------
  local step_ids_nl
  step_ids_nl="$(jq -r '.steps[]?.id' "$plan_json" 2>/dev/null || true)"

  local edges_nl
  edges_nl="$(jq -r '.dependencies[]? | "\(.before)->\(.after)"' "$plan_json" 2>/dev/null || true)"

  local graph_result=""
  if [[ -n "$step_ids_nl" ]]; then
    graph_result="$(build_plan_graph "$step_ids_nl" "$edges_nl")"
  else
    # No steps — emit empty graph
    graph_result='{"edges":[],"topological_order":[],"cycles":[]}'
  fi

  # Wrap in protocol v2 envelope
  local plan_graph_json
  plan_graph_json="$(_build_envelope "plan_graph" "plan_graph" "$graph_result" "$project_root")"

  local graph_out="${evidence_dir}/plan-graph.json"
  printf '%s\n' "$plan_graph_json" > "$graph_out"

  return 0
}

# ===========================================================================
# Subcommand: review (STUB — Step 3 will implement fully)
# ===========================================================================
cmd_review() {
  # -------------------------------------------------------------------------
  # Arg parsing
  # -------------------------------------------------------------------------
  local plan_md=""
  local evidence_dir=""
  local out_path=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --out requires a path argument" >&2
          exit 1
        fi
        out_path="$2"
        shift 2
        ;;
      -*)
        echo "ERROR: Unknown flag: $1" >&2
        exit 1
        ;;
      *)
        if [[ -z "$plan_md" ]]; then
          plan_md="$1"
        elif [[ -z "$evidence_dir" ]]; then
          evidence_dir="$1"
        else
          echo "ERROR: Unexpected argument: $1" >&2
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$plan_md" || -z "$evidence_dir" ]]; then
    echo "Usage: aid-c0-contract.sh review <plan.md> <c0_evidence_dir> [--out <path>]" >&2
    exit 1
  fi

  mkdir -p "$evidence_dir"

  local review_out
  if [[ -n "$out_path" ]]; then
    review_out="$out_path"
  else
    review_out="${evidence_dir}/plan-review.json"
  fi

  # Minimal stub JSON — Step 3 will replace this with 5 structural checks
  # and lens evidence scan
  printf '%s\n' '{}' > "$review_out"
  exit 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$SUBCOMMAND" in
  contract)
    cmd_contract "$@"
    ;;
  review)
    cmd_review "$@"
    ;;
  *)
    echo "ERROR: Unknown subcommand: $SUBCOMMAND" >&2
    echo "Available subcommands: contract, review" >&2
    exit 1
    ;;
esac
