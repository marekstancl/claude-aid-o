#!/usr/bin/env bash
# aid-promote-checks.sh — PM-facing markdown report of promotion candidates.
# Thin wrapper around `aid-fsm.sh check-promotion-candidates`.
#
# Renders the text table produced by check-promotion-candidates as a markdown
# table suitable for pasting into a PR comment, EPIC review, or ops review.
# Use --format text to get the raw text-table output instead.
#
# Per AID-v3-principles.md §1 tiered-severity caveat: advisory checks may be
# promoted to blocking once they accumulate ≥5 EPICs of clean operation with
# force-override-rate <0.05. This wrapper exists so PM can run a single
# command from the project root without recalling subcommand syntax.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
FORMAT="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) FORMAT="$2"; shift 2 ;;
    --help|-h)
      cat <<EOF
Usage: aid-promote-checks.sh [--format text|markdown]

Renders advisory→blocking promotion candidates as a table.
Defaults to markdown. Use --format text for raw text-table.

Run this from the project root after a series of EPICs to check whether any
advisory checks have accumulated enough clean operation (per AID-v3-principles.md §1)
to merit promotion.

To promote a candidate, use:
  aid-fsm.sh promote-check <name> --reason '<text ≥20 chars>'
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

RAW=$(bash "${SCRIPT_DIR}/aid-fsm.sh" check-promotion-candidates 2>&1 || true)

if [[ "$FORMAT" == "text" ]]; then
  echo "$RAW"
  exit 0
fi

echo "# Promotion Candidates Report"
echo
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "| Check | EPICs | Force Overrides | Rate | Candidate |"
echo "|-------|-------|-----------------|------|-----------|"

# Filter to data rows: skip header (rows 1-2), the trailing criterion/usage
# lines, separator lines, and blank lines. Match only rows with 5 columns
# starting with an alphanumeric check name (advisory check identifiers are
# snake_case identifiers).
echo "$RAW" | awk '
  NR <= 2 { next }                                 # skip header + separator
  /^Promotion criterion/ { next }
  /^To promote/ { next }
  /^\(no advisory checks/ { next }
  NF < 5 { next }
  $1 ~ /^[a-zA-Z_]/ {
    printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5
  }
'

echo
echo "_Promotion criterion: epic_count >= 5 AND rate < 0.05 (per AID-v3-principles.md §1)_"
echo
echo "_To promote a candidate:_"
echo '```'
echo "aid-fsm.sh promote-check <name> --reason '<text ≥20 chars>'"
echo '```'
