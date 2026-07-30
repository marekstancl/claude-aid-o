#!/usr/bin/env bash
# aid-test-catalog-confirm-mapping.sh — P066 Step 17.
#
# The MANDATORY, SEPARATE mapping-confirmation gate PM feedback item 2
# requires: approving the catalog file as a whole (aid-test-catalog-approve.sh)
# must never also approve source_pattern_mappings[] — only this script,
# given the EXACT hash of the diff it just displayed, can do that.
#
# Operates ONLY on the canonical, already-approved catalog at
# ${project_root}/.aid-o/config/test-catalog.yaml — same fixed target as
# aid-test-catalog-approve.sh, never a caller-supplied path.
#
# Re-stages after confirming (PM whole-EPIC-3 review, real gap): approve.sh
# force-adds the catalog BEFORE mapping confirmation, but this script
# previously rewrote the file to mapping_approval:approved WITHOUT ever
# re-running `git add -f` — the index kept the OLDER (mapping:proposed)
# blob, so a commit made right after confirming could silently commit the
# stale, unconfirmed mapping. This script now force-adds the same file
# again after its own atomic write, then verifies the index and working
# tree agree (`git diff --cached --quiet`) before reporting success.
#
# Usage:
#   # Step 1 — display the diff and its hash, make no changes:
#   aid-test-catalog-confirm-mapping.sh --project-root <path>
#
#   # Step 2 — confirm with the exact hash just shown:
#   aid-test-catalog-confirm-mapping.sh --project-root <path> \
#     --confirm-mapping <reviewed_diff_hash> [--approved-by <name>]
#
# A missing or mismatched --confirm-mapping hash always fails closed,
# re-displaying the current diff — never silently proceeds. Rows added or
# changed to the catalog AFTER a confirmation revert (by construction —
# reviewed_diff_hash is recomputed from the CURRENT rows every invocation)
# to requiring a fresh hash: a stale hash from a prior document state will
# not match the freshly-computed one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

CATALOG_SCHEMA="${SCHEMAS_DIR}/test-catalog.schema.json"

_die() { echo "aid-test-catalog-confirm-mapping.sh: $2" >&2; exit "$1"; }

project_root="" confirm_hash="" approved_by="operator"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --confirm-mapping) [[ $# -ge 2 ]] || _die 2 "--confirm-mapping requires a value"; confirm_hash="$2"; shift 2 ;;
    --approved-by) [[ $# -ge 2 ]] || _die 2 "--approved-by requires a value"; approved_by="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$project_root" ]] || _die 2 "--project-root is required"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"

catalog_path="${project_root}/.aid-o/config/test-catalog.yaml"
[[ -f "$catalog_path" ]] || _die 3 "no approved catalog found at $catalog_path — run aid-test-catalog-approve.sh first"

catalog_json="$(yq -o=json '.' "$catalog_path" 2>/dev/null)" || _die 1 "$catalog_path is not valid YAML"
adapter_validate_schema "$CATALOG_SCHEMA" "$catalog_json" \
  || _die 1 "$catalog_path failed schema validation"

# The reviewed diff is EVERY row's full displayed shape (match_type,
# path_pattern, classification, target_run_unit_ids, precedence) — a
# canonical, sorted-key JSON array — hashed exactly as displayed. Rows
# added/changed after a confirmation recompute to a DIFFERENT hash, so a
# stale --confirm-mapping value never matches. Codex review: match_type and
# precedence were previously excluded from the hash, so changing e.g. an
# exact rule to a prefix rule (both routing-relevant and both shown in the
# diff) would still pass a stale --confirm-mapping value.
diff_rows_json="$(jq -cS '[.source_pattern_mappings[] | {match_type, path_pattern, classification, target_run_unit_ids, precedence}]' <<<"$catalog_json")"
computed_hash="sha256:$(printf '%s' "$diff_rows_json" | sha256sum | cut -d' ' -f1)"

_print_diff() {
  echo "Reviewed diff (source_pattern_mappings[] — pattern, classification, target run_unit_ids):"
  jq -r '.source_pattern_mappings[] | "  [\(.precedence)] \(.match_type) \(.path_pattern) -> \(.classification) -> \(.target_run_unit_ids | join(", "))"' <<<"$catalog_json"
  echo ""
  echo "reviewed_diff_hash: ${computed_hash}"
  echo ""
  echo "To confirm this exact mapping, re-run with:"
  echo "  --confirm-mapping ${computed_hash}"
}

if [[ -z "$confirm_hash" ]]; then
  _print_diff
  exit 0
fi

if [[ "$confirm_hash" != "$computed_hash" ]]; then
  echo "aid-test-catalog-confirm-mapping.sh: provided --confirm-mapping hash does not match the current reviewed diff (stale or wrong hash) — refusing to approve, re-displaying the current diff:" >&2
  _print_diff
  exit 1
fi

approved_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

updated_json="$(jq -c \
  --arg by "$approved_by" \
  --arg at "$approved_at" \
  --arg hash "$computed_hash" \
  '
  .mapping_approval = {status: "approved", approved_by: $by, approved_at: $at, reviewed_diff_hash: $hash}
  | .source_pattern_mappings = [.source_pattern_mappings[] | .status = "approved"]
  ' <<<"$catalog_json")"

adapter_validate_schema "$CATALOG_SCHEMA" "$updated_json" \
  || _die 1 "internal error: confirming the mapping produced a schema-invalid document — refusing to publish"

tmp_path="${catalog_path}.tmp.$$"
yq -P '.' <<<"$updated_json" > "$tmp_path"
mv "$tmp_path" "$catalog_path"

row_count="$(jq '.source_pattern_mappings | length' <<<"$updated_json")"

# Re-stage: approve.sh force-added this file BEFORE mapping confirmation
# ever happened, so the index still holds the pre-confirmation (mapping:
# proposed) blob until this script stages the just-written bytes itself.
if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
  rel_catalog=".aid-o/config/test-catalog.yaml"
  git -C "$project_root" add -f -- "$rel_catalog"
  # Plain `git diff` (NOT --cached) compares the INDEX against the WORKING
  # TREE for this path — exit 0 means the just-written bytes are exactly
  # what's staged. (--cached compares index against HEAD, which legitimately
  # differs here since the file just changed vs the last commit.)
  if ! git -C "$project_root" diff --quiet -- "$rel_catalog"; then
    _die 1 "internal error: index and working tree diverge for $rel_catalog after staging — mapping confirmation not safely committable"
  fi
  echo "aid-test-catalog-confirm-mapping.sh: mapping confirmed and re-staged (reviewed_diff_hash: ${computed_hash}) — ${row_count} source_pattern_mappings rows approved"
else
  echo "aid-test-catalog-confirm-mapping.sh: mapping confirmed locally (reviewed_diff_hash: ${computed_hash}) — ${row_count} source_pattern_mappings rows approved; not a git repository, nothing tracked"
fi
