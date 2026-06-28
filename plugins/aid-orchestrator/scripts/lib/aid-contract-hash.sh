#!/usr/bin/env bash
# =============================================================================
# aid-contract-hash.sh — Deterministic contract hash functions
#
# Source-only lib. Functions:
#   binding_hash <producer> <consumer> <field>
#       Returns: sha256:<64 hex chars>
#       Uses ASCII 0x1f (unit separator) between fields before hashing.
#
#   manifest_hash <binding_hashes_nl>
#       Returns: sha256:<64 hex chars>
#       Sorts binding hashes lexicographically, joins with 0x1f, then hashes.
#
# Requirements: bash 4.0+, sha256sum, awk
# =============================================================================

# ---------------------------------------------------------------------------
# Guard: must be sourced, not executed directly.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: aid-contract-hash.sh must be sourced, not executed directly." >&2
  echo "Usage: source \"\$(dirname \"\$0\")/lib/aid-contract-hash.sh\"" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# binding_hash <producer> <consumer> <field>
#
# Computes a deterministic SHA-256 hash over three fields joined by ASCII 0x1f
# (unit separator). Input fields must not themselves contain 0x1f.
#
# Output: sha256:<64 lowercase hex chars>
# ---------------------------------------------------------------------------
binding_hash() {
  local producer="$1"
  local consumer="$2"
  local field="$3"
  # Use printf with \x1f (ASCII unit separator, 0x1F) between fields
  printf '%s\x1f%s\x1f%s' "$producer" "$consumer" "$field" \
    | sha256sum \
    | awk '{print "sha256:" $1}'
}

# ---------------------------------------------------------------------------
# manifest_hash <binding_hashes_nl>
#
# Arguments:
#   binding_hashes_nl — newline-separated list of binding hashes
#                       (each in the form "sha256:<64 hex>")
#
# Behavior:
#   1. Sort hashes lexicographically
#   2. Join with ASCII 0x1f (unit separator)
#   3. Hash the resulting byte string
#
# Output: sha256:<64 lowercase hex chars>
#
# Note: If binding_hashes_nl is empty, the hash is computed over an empty
# input (consistent zero-binding behavior).
# ---------------------------------------------------------------------------
manifest_hash() {
  local hashes_nl="$1"

  if [[ -z "$hashes_nl" ]]; then
    # Empty manifest: hash of empty string
    printf '' | sha256sum | awk '{print "sha256:" $1}'
    return
  fi

  # Sort lexicographically, then join with \x1f
  # Use printf '%s\n' to properly emit each hash line
  local sorted_joined
  sorted_joined="$(printf '%s\n' "$hashes_nl" | sort | tr '\n' '\x1f')"

  printf '%s' "$sorted_joined" | sha256sum | awk '{print "sha256:" $1}'
}
