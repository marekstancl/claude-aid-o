#!/usr/bin/env bash
# aid-test-catalog-approve.sh — P066 Step 17.
#
# Explicit, PM-invoked action (never automatic): copies a reviewed
# test-catalog.proposed.yaml to .aid-o/config/test-catalog.yaml (flipping
# only the document-root `status` field to "approved"), then force-tracks
# it into git via `git add -f` — the same mechanism this repo already
# relies on for 47 other files under the blanket `.aid-o/`/`**/.aid-o/`
# .gitignore rule (round 1->2 correction: a directory-negation line cannot
# re-include a file under an already-ignored parent; `git add -f` can).
#
# This script NEVER flips mapping_approval.status — approving the catalog
# file as a whole must never make source_pattern_mappings[] look
# authoritative (PM feedback item 2; see aid-test-catalog-confirm-mapping.sh
# for the separate, mandatory gate that does that).
#
# The approved catalog target is ALWAYS the canonical
# ${project_root}/.aid-o/config/test-catalog.yaml — never a PM-supplied
# override path. PM whole-EPIC-3 review, real gap: an earlier version
# accepted an arbitrary --approved-path checked only by a textual
# ${project_root}/* prefix, which a relative traversal
# (.aid-o/../../escape) or a symlink could defeat AFTER the prefix check —
# the check ran on the pre-resolution string, not the path that `mv`
# actually followed. Narrowing to one fixed, non-configurable target
# removes the escape surface entirely instead of trying to out-guess every
# traversal/symlink shape.
#
# Usage:
#   aid-test-catalog-approve.sh --proposed <path> --project-root <path>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMAS_DIR="$(cd "${SCRIPT_DIR}/../defaults/schemas" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

CATALOG_SCHEMA="${SCHEMAS_DIR}/test-catalog.schema.json"

_die() { echo "aid-test-catalog-approve.sh: $2" >&2; exit "$1"; }

proposed_path="" project_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proposed) [[ $# -ge 2 ]] || _die 2 "--proposed requires a value"; proposed_path="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$proposed_path" ]] || _die 2 "--proposed is required"
[[ -n "$project_root" ]] || _die 2 "--project-root is required"
[[ -f "$proposed_path" ]] || _die 3 "--proposed '$proposed_path' does not exist"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"

# The ONLY approved-catalog target this script will ever write — never
# configurable (see file header: removes the traversal/symlink escape
# surface an --approved-path override previously had).
approved_path="${project_root}/.aid-o/config/test-catalog.yaml"

proposed_json="$(yq -o=json '.' "$proposed_path" 2>/dev/null)" \
  || _die 1 "--proposed '$proposed_path' is not valid YAML"
[[ -n "$proposed_json" && "$proposed_json" != "null" ]] \
  || _die 1 "--proposed '$proposed_path' parsed to an empty/null document"

adapter_validate_schema "$CATALOG_SCHEMA" "$proposed_json" \
  || _die 1 "--proposed '$proposed_path' failed schema validation before approval — refusing to publish an unvalidated catalog"

# Flip ONLY the document-root status. mapping_approval and every
# source_pattern_mappings[] row's own status are copied through unchanged —
# this action alone never approves the routing map.
approved_json="$(jq -c '.status = "approved"' <<<"$proposed_json")"

adapter_validate_schema "$CATALOG_SCHEMA" "$approved_json" \
  || _die 1 "internal error: setting status=approved produced a schema-invalid document — refusing to publish"

mkdir -p "$(dirname "$approved_path")"

# Atomic publish: tmp-file-then-mv, same discipline as every other artifact
# writer in this plan.
tmp_path="${approved_path}.tmp.$$"
yq -P '.' <<<"$approved_json" > "$tmp_path"
mv "$tmp_path" "$approved_path"

# Force-track — safe to call unconditionally: re-force-adding an
# already-tracked file is a documented git no-op (verified: a second
# approval run issues the identical `git add -f`).
if git -C "$project_root" rev-parse --git-dir >/dev/null 2>&1; then
  rel_approved="${approved_path#"${project_root}"/}"
  git -C "$project_root" add -f -- "$rel_approved"
  echo "aid-test-catalog-approve.sh: approved and force-tracked $rel_approved (mapping_approval.status unchanged)"
else
  echo "aid-test-catalog-approve.sh: not a git repository, catalog written to $approved_path but not tracked"
fi
