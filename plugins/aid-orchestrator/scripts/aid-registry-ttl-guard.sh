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
# candidate1/candidate2 declared at outer scope so the error handler below can
# reference them regardless of which branch set registry_path.
candidate1=""
candidate2=""

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
  if [[ -n "${1:-}" ]]; then
    # Explicit path was given but the file does not exist.
    echo "  Explicit path not found: $registry_path" >&2
  else
    echo "  Searched: ${candidate1:-<not checked>}, ${candidate2:-<not checked>}" >&2
  fi
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
# Supports two YAML styles used in the registry:
#
# Flow-style (one line):
#   - {id: foo, status: planned, deadline: "2026-09-01", ...}
#
# Block-style (multi-line):
#   - id: foo
#     status: planned
#     deadline: "2026-09-01"
#     deferred_until: "2026-12-31"
#
# Strategy:
# - Flow-style: all fields on one line → extract inline.
# - Block-style: accumulate fields per entry; an entry starts at "  - id:" or
#   "- id:" and ends when the next entry starts or EOF.

stale_count=0
stale_rows=()

# Helper: evaluate one complete entry's worth of extracted fields.
_eval_entry() {
  local eid="$1" estatus="$2" edeadline="$3" edeferred="$4"
  [[ "$estatus" == "planned" ]] || return 0
  [[ -n "$edeadline" ]] || return 0          # opt-in: no deadline → skip
  if date_compare "$TODAY" "$edeadline"; then
    if [[ -n "$edeferred" ]] && ! date_compare "$TODAY" "$edeferred"; then
      return 0  # valid future deferral
    fi
    stale_count=$((stale_count + 1))
    stale_rows+=("  id=${eid:-<unknown>} deadline=$edeadline deferred_until=${edeferred:-<none>}")
  fi
}

# State for block-style accumulation
blk_id="" blk_status="" blk_deadline="" blk_deferred="" blk_active=false

_flush_block() {
  if $blk_active; then
    _eval_entry "$blk_id" "$blk_status" "$blk_deadline" "$blk_deferred"
  fi
  blk_id="" blk_status="" blk_deadline="" blk_deferred="" blk_active=false
}

while IFS= read -r line; do
  # ── Flow-style: entire entry on one line ─────────────────────────────────
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\{ ]]; then
    _flush_block  # close any open block entry
    local_status="" local_id="" local_deadline="" local_deferred=""
    [[ "$line" =~ status:[[:space:]]*([a-z_]+) ]]               && local_status="${BASH_REMATCH[1]}"
    [[ "$line" =~ id:[[:space:]]*([^,}[:space:]]+) ]]           && local_id="${BASH_REMATCH[1]}"
    [[ "$line" =~ deadline:[[:space:]]*\"?([0-9]{4}-[0-9]{2}-[0-9]{2})\"? ]] \
                                                                  && local_deadline="${BASH_REMATCH[1]}"
    [[ "$line" =~ deferred_until:[[:space:]]*\"?([0-9]{4}-[0-9]{2}-[0-9]{2})\"? ]] \
                                                                  && local_deferred="${BASH_REMATCH[1]}"
    _eval_entry "$local_id" "$local_status" "$local_deadline" "$local_deferred"
    continue
  fi

  # ── Block-style: entry starts with "  - id: <value>" ────────────────────
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]id:[[:space:]]*(.+) ]]; then
    _flush_block  # close previous block entry
    blk_id="${BASH_REMATCH[1]}"
    blk_active=true
    continue
  fi

  # ── Block-style: continuation lines (indented key: value) ────────────────
  if $blk_active; then
    if [[ "$line" =~ ^[[:space:]]+status:[[:space:]]*([a-z_]+) ]]; then
      blk_status="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]+deadline:[[:space:]]*\"?([0-9]{4}-[0-9]{2}-[0-9]{2})\"? ]]; then
      blk_deadline="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]+deferred_until:[[:space:]]*\"?([0-9]{4}-[0-9]{2}-[0-9]{2})\"? ]]; then
      blk_deferred="${BASH_REMATCH[1]}"
    fi
  fi
done < "$registry_path"

_flush_block  # handle last entry

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
