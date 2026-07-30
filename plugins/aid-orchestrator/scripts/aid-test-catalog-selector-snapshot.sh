#!/usr/bin/env bash
# aid-test-catalog-selector-snapshot.sh — P066 Step 17.
#
# READ-ONLY. Never writes to aid-select-tests.sh — that stays deferred
# entirely to P069 (this script only produces descriptive audit data about
# its EXISTING routing table).
#
# Extracts the real, current `map_path_to_tests()` and `is_production_surface()`
# function bodies verbatim from aid-select-tests.sh (never a hand-written
# reimplementation — that would drift) and calls them, under this script's
# own subshell, against every real file under scripts/ and defaults/ to:
#   1. Reconstruct source_pattern_mappings[] rows (status: proposed) for
#      every path the Initial mapping DOES cover.
#   2. Surface every production-surface path the Initial mapping does NOT
#      cover as a recommendation:fix finding (category: selector-gap) — this
#      is how the known 5-path gap (aid-plan-fsm.sh, lib/aid-queue-write.sh,
#      lib/aid-gate-profile.sh, aid-queue-add.sh,
#      defaults/enforcement-registry.yaml) is sourced from the real
#      function, not a hand-written comment.
#
# Usage:
#   aid-test-catalog-selector-snapshot.sh --project-root <path> [--output <path>]
#   (omit --output to print to stdout)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"

_die() { echo "aid-test-catalog-selector-snapshot.sh: $2" >&2; exit "$1"; }

project_root="" output_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || _die 2 "--output requires a value"; output_path="$2"; shift 2 ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$project_root" ]] || _die 2 "--project-root is required"
project_root="$(cd "$project_root" 2>/dev/null && pwd -P)" || _die 3 "--project-root '$project_root' does not exist (or is not a directory)"

SELECTOR_SCRIPT="${project_root}/plugins/aid-orchestrator/scripts/aid-select-tests.sh"
[[ -f "$SELECTOR_SCRIPT" ]] || _die 3 "aid-select-tests.sh not found under --project-root ($SELECTOR_SCRIPT)"

before_hash="$(sha256sum "$SELECTOR_SCRIPT" | cut -d' ' -f1)"

# Extract the two function bodies VERBATIM — never reimplemented — so this
# snapshot can never drift from the selector's real, current logic.
map_fn_src="$(sed -n '/^map_path_to_tests() {/,/^}/p' "$SELECTOR_SCRIPT")"
prod_fn_src="$(sed -n '/^is_production_surface() {/,/^}/p' "$SELECTOR_SCRIPT")"
[[ -n "$map_fn_src" ]] || _die 1 "could not extract map_path_to_tests() from $SELECTOR_SCRIPT — selector shape changed, snapshot is stale"
[[ -n "$prod_fn_src" ]] || _die 1 "could not extract is_production_surface() from $SELECTOR_SCRIPT — selector shape changed, snapshot is stale"

PLUGIN_PREFIX="$(grep -m1 '^PLUGIN_PREFIX=' "$SELECTOR_SCRIPT" | cut -d'"' -f2)"
[[ -n "$PLUGIN_PREFIX" ]] || _die 1 "could not extract PLUGIN_PREFIX from $SELECTOR_SCRIPT"

# shellcheck disable=SC1090,SC2294
eval "$map_fn_src"
# shellcheck disable=SC1090,SC2294
eval "$prod_fn_src"

# ─── Reconstruct source_pattern_mappings[] from the Initial mapping's own
#     case arms — regex-extracted (not executed as data) since the case
#     patterns themselves, not just their outcomes, are what a mapping row
#     records (path_pattern, match_type).
mappings_ndjson="$(mktemp)"
precedence=0
while IFS= read -r pattern_line; do
  precedence=$((precedence + 1))
  trimmed_line="$(sed -E 's/^\s+//; s/\s+$//' <<<"$pattern_line")"
  if [[ "$trimmed_line" =~ ^\"([^\"]*)\"(\*?)\)$ ]]; then
    raw_pattern="${BASH_REMATCH[1]}"
    has_star="${BASH_REMATCH[2]}"
  else
    _die 1 "internal error: unrecognized case-arm pattern shape in map_path_to_tests(): $pattern_line"
  fi
  path_pattern="${raw_pattern//\$\{PLUGIN_PREFIX\}/${PLUGIN_PREFIX}}"
  if [[ -n "$has_star" ]]; then
    match_type="prefix"
    probe_path="${path_pattern}sample-probe-file"
  else
    match_type="exact"
    probe_path="$path_pattern"
  fi
  targets_json="[]"
  while IFS=$'\t' read -r runner test_path; do
    [[ -z "$runner" ]] && continue
    case "$runner" in
      bats) ruid="bats:${test_path%.bats}" ;;
      *) ruid="sh:${test_path%.sh}" ;;
    esac
    targets_json="$(jq -c --arg r "$ruid" '. + [$r]' <<<"$targets_json")"
  done < <(map_path_to_tests "$probe_path")
  classification="production"
  if ! is_production_surface "$probe_path"; then
    classification="docs_non_production"
  fi
  row_json="$(jq -nc \
    --arg match_type "$match_type" \
    --arg path_pattern "$path_pattern" \
    --argjson target_run_unit_ids "$targets_json" \
    --arg classification "$classification" \
    --argjson precedence "$precedence" \
    '{match_type:$match_type, path_pattern:$path_pattern, target_run_unit_ids:$target_run_unit_ids, classification:$classification, precedence:$precedence, status:"proposed"}')"
  printf '%s\n' "$row_json" >> "$mappings_ndjson"
done < <(sed -n '/^map_path_to_tests() {/,/^}/p' "$SELECTOR_SCRIPT" | grep -E '^\s*"\$\{PLUGIN_PREFIX\}' )

mappings_json="$(jq -cs '.' "$mappings_ndjson")"
rm -f "$mappings_ndjson"

# ─── Surface every real production-surface path the Initial mapping does
#     NOT cover as a recommendation:fix, category:selector-gap finding.
findings_ndjson="$(mktemp)"
while IFS= read -r -d '' abs_path; do
  rel="${abs_path#"${project_root}"/}"
  # Only scripts/ and defaults/ files ever reach is_production_surface==true
  # by construction of the glob below, but call it anyway to stay driven by
  # the real function rather than the glob's own assumption.
  is_production_surface "$rel" || continue
  mapped_lines="$(map_path_to_tests "$rel")"
  if [[ -z "$mapped_lines" ]]; then
    finding_id="sha256:$(printf 'selector-gap:%s' "$rel" | sha256sum | cut -c1-12)"
    # Codex review: the falsification_check previously called
    # map_path_to_tests() with the "selector-snapshot:"-prefixed evidence_ref
    # string instead of the real path — that synthetic string can never
    # resolve even after the real gap is fixed, so the finding could never
    # actually be falsified. evidence_refs keeps the "selector-snapshot:"
    # label; falsification_check uses the real, checkable path.
    finding_json="$(jq -nc \
      --arg fid "$finding_id" \
      --arg ruid "selector-gap:${rel}" \
      --arg ref "selector-snapshot:${rel}" \
      --arg rel "$rel" \
      '{finding_id:$fid, run_unit_id:$ruid, category:"selector-gap", severity:"medium", evidence_refs:[$ref], recommendation:"fix", confidence:"high", falsification_check:("map_path_to_tests(\"" + $rel + "\") returns zero lines against the real aid-select-tests.sh")}')"
    printf '%s\n' "$finding_json" >> "$findings_ndjson"
  fi
done < <(find "${project_root}/plugins/aid-orchestrator/scripts" "${project_root}/plugins/aid-orchestrator/defaults" -type f \( -name '*.sh' -o -path '*/defaults/*' \) ! -path '*/scripts/tests/*' -print0 2>/dev/null | sort -z)

findings_json="$(jq -cs '.' "$findings_ndjson")"
rm -f "$findings_ndjson"

after_hash="$(sha256sum "$SELECTOR_SCRIPT" | cut -d' ' -f1)"
if [[ "$before_hash" != "$after_hash" ]]; then
  _die 1 "internal error: aid-select-tests.sh bytes changed during snapshot — this script must be strictly read-only"
fi

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
result_json="$(jq -nc \
  --arg generated_at "$generated_at" \
  --argjson mappings "$mappings_json" \
  --argjson findings "$findings_json" \
  '{schema_version:"1.0.0", generated_at:$generated_at, source_pattern_mappings:$mappings, findings:$findings}')"

if [[ -n "$output_path" ]]; then
  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "$result_json" > "$output_path"
else
  printf '%s\n' "$result_json"
fi
