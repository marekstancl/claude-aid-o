#!/usr/bin/env bash
# aid-registry-ttl-guard.sh — exits non-zero when a `status: planned` row in
# the enforcement registry is past its `deadline` without promotion to `active`
# or a valid future `deferred_until` date.
#
# Purpose: prevent deferred enforcement from silently rotting (the P045 failure
# mode where a detector was planned but never wired and nobody noticed).
#
# Usage:
#   aid-registry-ttl-guard.sh [registry_path]
#
# Arguments:
#   registry_path  Path to enforcement-registry.yaml (default: auto-discover from
#                  plugin defaults/ or project .aid-o/config/)
#
# Exit codes:
#   0   All planned rows are either not-yet-past-deadline or have a valid
#       future deferred_until date.
#   1   One or more planned rows are stale (past deadline, no valid deferral).
#   2   Registry not found or not readable.
#
# Schema fields checked (per EPIC E-046-1_3 Step 5):
#   deadline       ISO 8601 date (YYYY-MM-DD); optional per row; if present and
#                  today >= deadline the row is stale unless deferred.
#   deferred_until ISO 8601 date (YYYY-MM-DD); if present and today < deferred_until
#                  the row is not stale regardless of deadline.
#   deferred_by    free text; informational only.
#   deferred_reason free text; informational only.
#
# Rows with status: active or status: dead are NEVER checked (only status: planned).
# Rows with no deadline field are skipped (guard is opt-in per row).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODAY=$(date -u +%Y-%m-%d)

# ── Registry discovery ────────────────────────────────────────────────────────

registry_path="${1:-}"

if [[ -z "$registry_path" ]]; then
  # Try distributed defaults/ first, then project .aid-o/config/
  candidate1="$(cd "$SCRIPT_DIR/.." && pwd)/defaults/enforcement-registry.yaml"
  candidate2=".aid-o/config/enforcement-registry.yaml"
  if [[ -f "$candidate1" ]]; then
    registry_path="$candidate1"
  elif [[ -f "$candidate2" ]]; then
    registry_path="$candidate2"
  fi
fi

if [[ -z "$registry_path" || ! -f "$registry_path" ]]; then
  echo "ERROR: enforcement-registry.yaml not found." >&2
  echo "  Searched: ${candidate1:-<not checked>}, ${candidate2:-<not checked>}" >&2
  echo "  Pass the path explicitly: aid-registry-ttl-guard.sh <path>" >&2
  exit 2
fi

# ── YAML parser helpers (pure bash, no yq dependency) ────────────────────────

# date_compare A B → 0 if A >= B (both YYYY-MM-DD), 1 otherwise
date_compare() {
  local a="${1//-/}" b="${2//-/}"  # strip hyphens → YYYYMMDD integers
  [[ "$a" -ge "$b" ]]
}

# ── Parse the registry ────────────────────────────────────────────────────────
# We need to find blocks of lines that form a single entry (flow style on one
# line or block style). The registry uses flow-style entries:
#   - {id: foo, status: planned, deadline: 2026-09-01, ...}
# We scan line by line, extract status + deadline + deferred_until per entry.

stale_count=0
stale_rows=()

while IFS= read -r line; do
  # Only process lines that look like registry entries (start with optional spaces + "- {")
  [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\{ ]] || continue

  # Extract status field
  local_status=""
  if [[ "$line" =~ status:[[:space:]]*([a-z_]+) ]]; then
    local_status="${BASH_REMATCH[1]}"
  fi

  # Only check planned rows
  [[ "$local_status" == "planned" ]] || continue

  # Extract id for error messages
  local_id=""
  if [[ "$line" =~ id:[[:space:]]*([^,}[:space:]]+) ]]; then
    local_id="${BASH_REMATCH[1]}"
  fi

  # Extract deadline field
  local_deadline=""
  if [[ "$line" =~ deadline:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    local_deadline="${BASH_REMATCH[1]}"
  fi

  # No deadline → not subject to TTL guard (opt-in)
  [[ -n "$local_deadline" ]] || continue

  # Extract deferred_until field
  local_deferred_until=""
  if [[ "$line" =~ deferred_until:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    local_deferred_until="${BASH_REMATCH[1]}"
  fi

  # Check: if deadline is past (today >= deadline)
  if date_compare "$TODAY" "$local_deadline"; then
    # Stale — check for valid deferral
    if [[ -n "$local_deferred_until" ]] && ! date_compare "$TODAY" "$local_deferred_until"; then
      # Has a future deferred_until — not stale
      continue
    fi
    # Stale with no valid deferral
    stale_count=$((stale_count + 1))
    stale_rows+=("  id=$local_id deadline=$local_deadline deferred_until=${local_deferred_until:-<none>}")
  fi
done < "$registry_path"

# ── Report ────────────────────────────────────────────────────────────────────

if [[ "$stale_count" -gt 0 ]]; then
  echo "ENFORCEMENT REGISTRY TTL GUARD: $stale_count stale planned row(s) found." >&2
  echo "  Registry: $registry_path" >&2
  echo "  Today: $TODAY" >&2
  echo "" >&2
  echo "Stale rows (past deadline, no valid deferral):" >&2
  for row in "${stale_rows[@]}"; do
    echo "  $row" >&2
  done
  echo "" >&2
  echo "Fix options:" >&2
  echo "  1. Wire the enforcement (set status: active, update source:)" >&2
  echo "  2. Extend deadline: update the deadline field to a future date" >&2
  echo "  3. Defer: add deferred_until: YYYY-MM-DD (+ deferred_by + deferred_reason)" >&2
  exit 1
fi

echo "Enforcement registry TTL guard: OK (no stale planned rows)" >&2
exit 0
