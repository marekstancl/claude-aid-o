#!/usr/bin/env bash
# aid-init-upgrade-test-audit.sh — P069 Step 12.
#
# Explicit, non-invasive upgrade path for an EXISTING project's already-
# generated .aid-o/config/execution.yaml: adds the P069 Step 12
# stack-independent targeted_tests gate when it is missing (see
# render_targeted_tests_gate_block in lib/aid-init-execution-yaml.sh, the
# SAME renderer compose_execution_yaml uses for a fresh project, so the two
# paths can never drift). The test_audit.scheduler half of this upgrade was
# REMOVED in P078 with the parallelism machinery (PM decision 2026-08-09).
# Presence is detected by KEY EXISTENCE (`.gates | has("targeted_tests")`),
# never by exact text or a non-null check — a hand-edited
# `targeted_tests: null` placeholder still counts as "already present" (the
# key exists) and is never overwritten (Codex review: an earlier `!= null`
# check misclassified an explicit null value as "missing" and would have
# inserted a shadowing duplicate key next to it).
#
# Confirm-hash convention mirrors aid-test-catalog-confirm-mapping.sh: no
# --confirm-upgrade -> print the proposed diff + hash, exit 0 (preview only,
# no write); wrong/stale hash -> print diff + hash, exit 1 (never silently
# proceeds); matching hash -> write. The hash is bound to BOTH the current
# file's exact content AND the proposed addition text (Codex review: hashing
# only the fixed rendered addition text made the hash identical across any
# two projects missing the same subset, and immune to unrelated edits made
# to the file between preview and confirm — neither of which is "confirming
# THIS exact upgrade").
#
# The write is NOT a blind end-of-file append — targeted_tests is inserted
# as new lines immediately after the EXISTING `^gates:` anchor line. This
# matters because mikefarah/yq (and aid-run-gates.sh's own `.gates` reads)
# resolve a SECOND top-level key of the same name by silently taking the
# LAST occurrence — blindly appending a second `gates:` block would
# silently delete every sibling already defined under the first one
# (verified empirically before writing this). A hand-edited file with MORE
# THAN ONE top-level `gates:` line already (a pre-existing user error this
# script did not create) is refused outright — this script's single-anchor
# insertion technique cannot safely resolve which occurrence is the
# effective one without becoming a full YAML-aware rewrite, which would
# risk reformatting hand-edited values elsewhere in the file.
#
# Usage:
#   aid-init-upgrade-test-audit.sh --project-root <path>
#   aid-init-upgrade-test-audit.sh --project-root <path> --confirm-upgrade <hash>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-init-execution-yaml.sh
source "${SCRIPT_DIR}/lib/aid-init-execution-yaml.sh"

_die() { echo "aid-init-upgrade-test-audit.sh: $2" >&2; exit "$1"; }

project_root="" confirm_hash=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --confirm-upgrade) [[ $# -ge 2 ]] || _die 2 "--confirm-upgrade requires a value"; confirm_hash="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$project_root" ]] || _die 2 "--project-root is required"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"

execution_yaml="${project_root}/.aid-o/config/execution.yaml"
[[ -f "$execution_yaml" ]] || _die 3 "no execution.yaml found at $execution_yaml — run /aid-init first"

# Refuse outright on a pre-existing duplicate top-level anchor — this
# script's single-anchor insertion technique cannot safely determine which
# occurrence is the effective one (yq itself resolves duplicates by taking
# the LAST; a naive insert-after-first would silently target the wrong,
# shadowed mapping).
gates_count="$(grep -c '^gates:' "$execution_yaml" || true)"
(( gates_count <= 1 )) || _die 1 "execution.yaml already has ${gates_count} top-level 'gates:' lines — refusing to upgrade a file with a pre-existing duplicate-key hazard; resolve the duplicate by hand first"

has_gate="$(yq '(.gates // {}) | has("targeted_tests")' "$execution_yaml" 2>/dev/null || echo "false")"

# P078: the test_audit.scheduler half of this upgrade was removed with the
# parallelism machinery — the upgrade now adds only the targeted_tests gate.
if [[ "$has_gate" == "true" ]]; then
  echo "aid-init-upgrade-test-audit.sh: targeted_tests gate already present — nothing to upgrade"
  exit 0
fi

gate_block="$(render_targeted_tests_gate_block)"

# Hash bound to the CURRENT file's exact
# content too (sha256 of the file itself) — so the hash is specific to
# THIS file's current state, not just to which pieces happen to be
# missing: two different projects (or the same project edited between
# preview and confirm) never share a hash merely because they're both
# missing the same subset.
proposed_text="${gate_block}"$'\n'

file_hash="$(sha256sum "$execution_yaml" | cut -d' ' -f1)"
computed_hash="sha256:$(printf '%s\n%s' "$file_hash" "$proposed_text" | sha256sum | cut -d' ' -f1)"

_print_diff() {
  echo "Proposed additions to ${execution_yaml} (nothing else in the file changes):"
  echo "--- current"
  echo "+++ proposed"
  echo "  (inserted as a new member of the existing top-level gates: mapping)"
  printf '%s\n' "$gate_block"
  echo ""
  echo "diff_hash: ${computed_hash}"
  echo ""
  echo "To confirm this exact upgrade, re-run with:"
  echo "  --confirm-upgrade ${computed_hash}"
}

if [[ -z "$confirm_hash" ]]; then
  _print_diff
  exit 0
fi

if [[ "$confirm_hash" != "$computed_hash" ]]; then
  echo "aid-init-upgrade-test-audit.sh: provided --confirm-upgrade hash does not match the current proposed diff (stale or wrong hash) — refusing to write, re-displaying the current diff:" >&2
  _print_diff
  exit 1
fi

# _insert_after_anchor <file> <anchor_regex> <text_to_insert>
#   Splices <text_to_insert> as new lines immediately after the FIRST line
#   matching <anchor_regex> — every byte already in <file> is preserved, in
#   order; only new lines are added. Never appended at file end (see file
#   header for why that would be unsafe for an EXISTING top-level key).
_insert_after_anchor() {
  local file="$1" anchor="$2" text="$3"
  local anchor_line
  anchor_line="$(grep -n "$anchor" "$file" | head -1 | cut -d: -f1)"
  [[ -n "$anchor_line" ]] || _die 1 "internal error: execution.yaml has no '${anchor}' line to insert after"
  local tmp_path="${file}.tmp.$$"
  {
    head -n "$anchor_line" "$file"
    printf '%s\n' "$text"
    tail -n "+$((anchor_line + 1))" "$file"
  } > "$tmp_path"
  mv "$tmp_path" "$file"
}

# ─── Write ──────────────────────────────────────────────────────────────
# targeted_tests gate: inserted immediately after the file's first
# top-level `gates:` line (never a second, duplicate `gates:` key).
_insert_after_anchor "$execution_yaml" '^gates:' "$gate_block"

echo "aid-init-upgrade-test-audit.sh: upgraded ${execution_yaml}"
echo "  + added targeted_tests gate"
exit 0
