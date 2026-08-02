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

# ── Pre-approval zero-gap re-verification (P069 Step 11) ───────────────────
# Additive PRECONDITION only — never changes what mapping_approval.status:
# approved MEANS, never bypasses aid-test-catalog-confirm-mapping.sh's own
# separate, later gate (untouched). Re-runs P066's own read-only
# selector-snapshot script fresh (never a stale/cached snapshot) and
# requires the proposed document's source_pattern_mappings[] to reproduce
# it — a gap introduced since the proposal was generated (a new unmapped
# production path, or a stale/missing row) blocks approval, naming exactly
# what differs.
#
# DOGFOOD-ONLY GUARD: aid-test-catalog-selector-snapshot.sh is itself
# dogfood-only (hardcoded to
# "${project_root}/plugins/aid-orchestrator/scripts/aid-select-tests.sh" —
# this plugin's own repo layout, never a consumer project's). This script
# is shared by every consumer project's own catalog approval, so the
# re-verification only ever RUNS when that exact dogfood path exists; for
# every other project it is silently a no-op — never a hard failure for a
# mechanism that structurally cannot apply there yet (no equivalent
# consumer-project re-verification exists as of this plan).
#
# Codex review (accepted, not fixed): the snapshot script `eval`s function
# bodies extracted from that same aid-select-tests.sh file, so a file-
# existence check alone doesn't cryptographically prove "this is really
# the trusted plugin's own file" versus a decoy at the same path. This is
# NOT a new attack surface, though: aid-select-tests.sh already lives
# under plugins/aid-orchestrator/scripts/ — the SAME trust tier as every
# other plugin script — and is ALREADY executed directly and routinely as
# a real gate command (Steps 9/10). Anyone able to plant a malicious file
# at this exact path already has write access to the plugin's own code and
# could compromise the system far more directly (e.g. editing
# aid-run-gates.sh or any other gate command). No new privilege boundary
# is crossed; a stronger "is this really the trusted plugin" check would
# require repo-identity/signing infrastructure that exists nowhere else in
# this codebase and is out of this step's own scope.
SNAPSHOT_SCRIPT="${SCRIPT_DIR}/aid-test-catalog-selector-snapshot.sh"
if [[ -f "${project_root}/plugins/aid-orchestrator/scripts/aid-select-tests.sh" ]]; then
  snapshot_json="$(bash "$SNAPSHOT_SCRIPT" --project-root "$project_root" 2>/dev/null)" \
    || _die 1 "pre-approval selector-snapshot re-verification failed to run — refusing to approve"

  # The snapshot's own classification conflates "no case arm covers this
  # probe path" with "not production" — a row derived from a REAL, targeted
  # case arm (non-empty target_run_unit_ids) is always production,
  # regardless of what is_production_surface says about the reconstructed
  # probe path (that function only recognizes scripts/ and defaults/ as
  # production roots; lib/ui-fidelity/** is a real, additional
  # Initial-mapping production root the probe-path heuristic was never
  # taught). Corrected at THIS consumption layer only — the snapshot
  # script's own parsing/extraction logic is never touched.
  # Selector-gap findings become exact-match unknown_production rows —
  # Step 10's own real classification (exit 3), never left absent (which
  # Step 10 would otherwise classify as mapping_gap, exit 11) — precedence
  # placed after every real case-arm row; an exact match can never collide
  # with a broader prefix/glob row for the SAME path (if one existed, the
  # gap finding for that exact path would never have been raised at all).
  expected_mappings_json="$(jq -c '
    [.source_pattern_mappings[] | if ((.target_run_unit_ids | length) > 0) then .classification = "production" else . end]
  ' <<<"$snapshot_json")"
  # Codex review: an explicit case arm that (hypothetically) resolves to
  # zero targets would otherwise get BOTH its own real row AND an
  # auto-seeded gap row for the identical path_pattern — the real row,
  # sorted first, would make the seeded row unreachable, silently
  # defeating the "never left absent" guarantee. Exclude any finding whose
  # path already has an explicit row (does not occur against the real
  # selector today — verified — but never assumed to be structurally
  # impossible).
  existing_patterns_json="$(jq -c '[.[].path_pattern]' <<<"$expected_mappings_json")"
  gap_rows_json="$(jq -c --argjson existing "$existing_patterns_json" '
    [.findings[] | select(.category == "selector-gap") |
      (.evidence_refs[0] | sub("^selector-snapshot:"; "")) as $p
      | select(($existing | index($p)) == null)
      | { match_type: "exact",
          path_pattern: $p,
          target_run_unit_ids: [],
          classification: "unknown_production",
          precedence: 1000,
          status: "proposed" }
    ]
  ' <<<"$snapshot_json")"
  expected_mappings_json="$(jq -c --argjson gaps "$gap_rows_json" '. + $gaps' <<<"$expected_mappings_json")"

  # Canonical comparison: ORDER-preserved tuples of the fields that
  # actually determine Step 10's classification behavior — sorted by
  # (precedence, path_pattern), NEVER by the literal precedence NUMBER
  # alone (Codex review: the schema permits duplicate precedence values —
  # e.g. every auto-seeded gap row shares precedence 1000 — so sorting by
  # precedence alone left tied rows in caller/iteration-dependent order,
  # making two semantically-identical mapping sets compare unequal merely
  # because two exact-match gap rows were listed in a different order).
  # path_pattern is a stable, always-present tiebreak; the literal
  # precedence number itself and the per-row status (proposed vs approved)
  # are excluded from the compared tuple entirely — neither is this
  # check's concern.
  # Sort by (precedence, path_pattern) BEFORE canonicalizing — precedence
  # ordering is preserved across DIFFERENT precedence values (it changes
  # real matching behavior for overlapping prefix/glob rows), while
  # path_pattern only ever breaks ties WITHIN the same precedence value
  # (true collisions only occur among auto-seeded gap rows here, which are
  # all mutually non-overlapping exact matches, so this tiebreak never
  # changes behavior — only removes iteration-order noise).
  _canon_mappings() {
    jq -cS '[.[] | {match_type, path_pattern, target_run_unit_ids: (.target_run_unit_ids | sort), classification}]'
  }
  expected_canon="$(_canon_mappings <<<"$(jq -c 'sort_by([.precedence, .path_pattern])' <<<"$expected_mappings_json")")"
  actual_mappings_json="$(jq -c '[.source_pattern_mappings[]] | sort_by([.precedence, .path_pattern])' <<<"$proposed_json")"
  actual_canon="$(_canon_mappings <<<"$actual_mappings_json")"

  if [[ "$actual_canon" != "$expected_canon" ]]; then
    echo "aid-test-catalog-approve.sh: refusing to approve — --proposed source_pattern_mappings[] does not match a fresh selector-snapshot re-verification (drift since the proposal was generated):" >&2
    echo "  expected (fresh snapshot, corrected + gap rows seeded):" >&2
    jq -r '.[] | "    " + .path_pattern + " -> " + .classification' <<<"$expected_mappings_json" >&2
    echo "  actual (--proposed file):" >&2
    jq -r '.[] | "    " + .path_pattern + " -> " + .classification' <<<"$actual_mappings_json" >&2
    exit 1
  fi
fi

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
