#!/usr/bin/env bash
# aid-consumption-proof.sh — Verify contract-manifest.json bindings have evidence
#
# Usage: aid-consumption-proof.sh verify <contract-manifest.json> <evidence_dir> [--out <path>]
#
# Reads contract-manifest.json, checks each binding for evidence in evidence_dir.
# Emits consumption-proof.json (observe mode — no blocking).
# Exit 0 on success (including fail-safe unresolvable), 1 on usage error.
#
# Top-level state:
#   verified     — ALL bindings verified
#   unresolvable — ANY binding unresolvable (or manifest missing/invalid)
#   pending      — bindings[] is empty
#
# **Last Updated:** 2026-06-29

# Note: -e (errexit) is intentionally absent. This script uses explicit exit 0 on all
# fail-safe paths (_emit_unresolvable_manifest) and must not abort on jq soft-failures.
set -uo pipefail

SUBCOMMAND="${1:-}"

if [[ "$SUBCOMMAND" != "verify" ]]; then
  echo "Usage: aid-consumption-proof.sh verify <contract-manifest.json> <evidence_dir> [--out <path>]" >&2
  exit 1
fi

MANIFEST_JSON="${2:-}"
EVIDENCE_DIR="${3:-}"

if [[ -z "$MANIFEST_JSON" || -z "$EVIDENCE_DIR" ]]; then
  echo "Usage: aid-consumption-proof.sh verify <contract-manifest.json> <evidence_dir> [--out <path>]" >&2
  exit 1
fi

# Parse optional --out argument
OUT_PATH=""
shift 3 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_PATH="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -z "$OUT_PATH" ]]; then
  OUT_PATH="${EVIDENCE_DIR}/consumption-proof.json"
fi

# Ensure output directory exists (evidence_dir may not exist yet in edge cases)
mkdir -p "$(dirname "$OUT_PATH")" 2>/dev/null || true

ISO_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Fail-safe: manifest missing or invalid ---
_emit_unresolvable_manifest() {
  local reason="${1:-manifest_not_found}"
  cat > "$OUT_PATH" <<EOF
{
  "artifact_type": "consumption_proof",
  "consumption_proof": {
    "state": "unresolvable",
    "verified_at": null,
    "reason": "${reason}",
    "bindings": []
  }
}
EOF
  exit 0
}

if [[ ! -f "$MANIFEST_JSON" ]]; then
  _emit_unresolvable_manifest "manifest_not_found"
fi

# Validate JSON
if ! command -v jq &>/dev/null; then
  # No jq: can't parse — emit unresolvable
  _emit_unresolvable_manifest "jq_not_available"
fi

if ! jq empty "$MANIFEST_JSON" 2>/dev/null; then
  _emit_unresolvable_manifest "manifest_invalid_json"
fi

# --- Extract bindings[] ---
BINDINGS_COUNT=$(jq 'if .bindings then (.bindings | length) else 0 end' "$MANIFEST_JSON" 2>/dev/null || echo 0)

if [[ "$BINDINGS_COUNT" -eq 0 ]]; then
  # pending state — no bindings
  cat > "$OUT_PATH" <<EOF
{
  "artifact_type": "consumption_proof",
  "consumption_proof": {
    "state": "pending",
    "verified_at": null,
    "bindings": []
  }
}
EOF
  exit 0
fi

# --- Check each binding for evidence ---
# Process bindings one by one using jq indices
ALL_VERIFIED=true
BINDINGS_ARRAY="[]"

for i in $(seq 0 $((BINDINGS_COUNT - 1))); do
  BINDING=$(jq ".bindings[$i]" "$MANIFEST_JSON" 2>/dev/null)

  BINDING_ID=$(echo "$BINDING" | jq -r '.id // ""' 2>/dev/null)
  CONTRACT_REF=$(echo "$BINDING" | jq -r '.contract_ref // .source // ""' 2>/dev/null)

  # --- Evidence check ---
  EVIDENCE_PATH="null"
  STATE="unresolvable"
  REASON='"no_evidence_found"'

  # Strategy 1: grep for binding_id in any file in evidence_dir
  if [[ -n "$BINDING_ID" ]]; then
    FOUND_FILE=$(grep -rl "$BINDING_ID" "$EVIDENCE_DIR" 2>/dev/null | head -1 || true)
    if [[ -n "$FOUND_FILE" ]]; then
      EVIDENCE_PATH="$FOUND_FILE"
      STATE="verified"
      REASON="null"
    fi
  fi

  # Strategy 2: look for named pattern files (contract*, binding*, consumption*)
  if [[ "$STATE" == "unresolvable" ]]; then
    PATTERN_FILE=$(find "$EVIDENCE_DIR" -maxdepth 2 \( \
      -name "*contract*" -o -name "*binding*" -o -name "*consumption*" \
    \) -type f 2>/dev/null | head -1 || true)
    if [[ -n "$PATTERN_FILE" ]]; then
      EVIDENCE_PATH="$PATTERN_FILE"
      STATE="verified"
      REASON="null"
    fi
  fi

  if [[ "$STATE" == "unresolvable" ]]; then
    ALL_VERIFIED=false
  fi

  # Escape paths for JSON
  EVIDENCE_PATH_JSON="null"
  if [[ "$EVIDENCE_PATH" != "null" && -n "$EVIDENCE_PATH" ]]; then
    EVIDENCE_PATH_JSON=$(printf '%s' "$EVIDENCE_PATH" | jq -Rs '.')
  fi

  BINDING_ID_JSON=$(printf '%s' "$BINDING_ID" | jq -Rs '.')
  CONTRACT_REF_JSON=$(printf '%s' "$CONTRACT_REF" | jq -Rs '.')

  BINDING_ENTRY=$(jq -n \
    --argjson bid "$BINDING_ID_JSON" \
    --argjson cref "$CONTRACT_REF_JSON" \
    --arg state "$STATE" \
    --argjson epath "$EVIDENCE_PATH_JSON" \
    --argjson reason "$REASON" \
    '{
      binding_id: $bid,
      contract_ref: $cref,
      state: $state,
      evidence_path: $epath,
      reason: $reason
    }')

  BINDINGS_ARRAY=$(echo "$BINDINGS_ARRAY" | jq ". + [$BINDING_ENTRY]")
done

# --- Determine top-level state ---
if [[ "$ALL_VERIFIED" == "true" ]]; then
  TOP_STATE="verified"
  VERIFIED_AT="\"${ISO_NOW}\""
else
  TOP_STATE="unresolvable"
  VERIFIED_AT="null"
fi

# --- Emit consumption-proof.json ---
jq -n \
  --arg artifact_type "consumption_proof" \
  --arg state "$TOP_STATE" \
  --argjson verified_at "$VERIFIED_AT" \
  --argjson bindings "$BINDINGS_ARRAY" \
  '{
    artifact_type: $artifact_type,
    consumption_proof: {
      state: $state,
      verified_at: $verified_at,
      bindings: $bindings
    }
  }' > "$OUT_PATH"

exit 0
