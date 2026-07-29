#!/usr/bin/env bash
# aid-test-inventory.sh — P066 Step 4.
#
# Wave 0: the single controller-owned preflight scanner. Zero LLM dispatch.
# Orchestrates all three adapters (Bats, package-script, declared-command),
# validates no cross-adapter run_unit_id collision, statically greps
# flock/.lock usage into every Bats run_unit's isolation.lock_usage[], and
# emits inventory.json + test-catalog.proposed.yaml under
# .aid-o/work/test-audits/<audit-id>/ (gitignored, evidence-only — never the
# tracked .aid-o/config/test-catalog.yaml path).
#
# Usage:
#   aid-test-inventory.sh --project-root <path> --audit-id <id> \
#                          --output-dir <dir> [--execution-yaml <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"
# shellcheck source=lib/aid-test-adapter-bats.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-bats.sh"
# shellcheck source=lib/aid-test-adapter-package-script.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-package-script.sh"
# shellcheck source=lib/aid-test-adapter-declared-command.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-declared-command.sh"

_usage() {
  cat <<'EOF'
Usage: aid-test-inventory.sh --project-root <path> --audit-id <id> --output-dir <dir> [--execution-yaml <path>]
EOF
}

# _aid_test_inventory_lock_usage_for_file <file>
#   Statically greps flock/.lock usage. Heuristic, deterministic: extracts
#   the first quoted string on a matching line as lock_target;
#   resolved_scope is "per-test-mktemp" when that target references
#   TEST_TMPDIR/mktemp, "shared-or-unresolved" otherwise — Step 7's own audit
#   (not this scanner) does the deeper per-target resolution/fix.
_aid_test_inventory_lock_usage_for_file() {
  local file="$1"
  local entries_json="[]"
  local line trimmed target scope

  while IFS= read -r line; do
    trimmed="$(sed -E 's/^[[:space:]]+//' <<<"$line")"
    [[ "$trimmed" == \#* ]] && continue
    target="$(grep -oE '"[^"]*"' <<<"$line" | head -1 | tr -d '"')"
    [[ -n "$target" ]] || target="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    if [[ "$target" == *TEST_TMPDIR* || "$target" == *mktemp* ]]; then
      scope="per-test-mktemp"
    else
      scope="shared-or-unresolved"
    fi
    entries_json="$(jq -c --arg t "$target" --arg s "$scope" '. + [{lock_target: $t, resolved_scope: $s}]' <<<"$entries_json")"
  done < <(grep -E 'flock|\.lock\b' "$file" 2>/dev/null || true)

  printf '%s\n' "$entries_json"
}

# _aid_test_inventory_annotate_lock_usage <project_root> <units_json>
#   For every bats-runner run_unit, statically greps flock/.lock usage in
#   its underlying file into isolation.lock_usage[].
_aid_test_inventory_annotate_lock_usage() {
  local project_root="$1" units_json="$2"
  local count idx runner rel_path abs_path lock_json
  count="$(jq 'length' <<<"$units_json")"
  for ((idx = 0; idx < count; idx++)); do
    runner="$(jq -r ".[$idx].runner" <<<"$units_json")"
    [[ "$runner" == "bats" ]] || continue
    rel_path="$(jq -r ".[$idx].source_paths[0] // empty" <<<"$units_json")"
    [[ -n "$rel_path" ]] || continue
    abs_path="${project_root%/}/${rel_path}"
    [[ -f "$abs_path" ]] || continue
    lock_json="$(_aid_test_inventory_lock_usage_for_file "$abs_path")"
    units_json="$(jq -c --argjson lk "$lock_json" --argjson i "$idx" \
      '.[$i].isolation.lock_usage = $lk | .' <<<"$units_json")"
  done
  printf '%s\n' "$units_json"
}

project_root="" audit_id="" output_dir="" execution_yaml=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) project_root="$2"; shift 2 ;;
    --audit-id) audit_id="$2"; shift 2 ;;
    --output-dir) output_dir="$2"; shift 2 ;;
    --execution-yaml) execution_yaml="$2"; shift 2 ;;
    -h|--help) _usage; exit 0 ;;
    *) echo "aid-test-inventory.sh: unknown option '$1'" >&2; _usage >&2; exit 2 ;;
  esac
done

[[ -n "$project_root" && -d "$project_root" ]] || { echo "aid-test-inventory.sh: --project-root is required and must exist" >&2; exit 2; }
[[ -n "$audit_id" ]] || { echo "aid-test-inventory.sh: --audit-id is required" >&2; exit 2; }
[[ -n "$output_dir" ]] || { echo "aid-test-inventory.sh: --output-dir is required" >&2; exit 2; }
[[ -n "$execution_yaml" ]] || execution_yaml="${project_root%/}/.aid-o/config/execution.yaml"

mkdir -p "$output_dir"

# ─── Wave 0: run all three adapters ─────────────────────────────────────────
bats_units="$(bats_adapter_discover "$project_root")"
pkgscript_units="$(package_script_adapter_discover "$project_root")"
combined_units="$(jq -c -s 'add' <(printf '%s' "$bats_units") <(printf '%s' "$pkgscript_units"))"
combined_units="$(declared_command_adapter_discover "$execution_yaml" "$combined_units" "$project_root")"

# ─── Lock-usage static grep (Bats run_units only) ───────────────────────────
combined_units="$(_aid_test_inventory_annotate_lock_usage "$project_root" "$combined_units")"

# Discovery uncertainty is always confidence:low, never silently upgraded —
# this is Wave 0's own contract regardless of what an individual adapter set
# (an adapter's higher confidence reflects its own internal certainty about
# WHAT it found, e.g. "this really is the declared gate command", not
# license to skip Wave 0's blanket "purely static discovery" caveat).
combined_units="$(jq -c 'map(.confidence = "low")' <<<"$combined_units")"

# ─── Collision detection: two adapters claiming the same run_unit_id ───────
collisions="$(adapter_check_run_unit_id_collisions "$combined_units")"
if [[ -n "$collisions" ]]; then
  echo "aid-test-inventory.sh: run_unit_id collision(s) detected:" >&2
  echo "$collisions" >&2
  exit 1
fi

# ─── Emit inventory.json ────────────────────────────────────────────────────
# combined_units can be arbitrarily large (a big monorepo's full portfolio) —
# passed via a temp file + --slurpfile, never --argjson on argv, which would
# exceed the OS ARG_MAX for a big enough catalog ("Argument list too long").
units_file="$(mktemp)"
trap 'rm -f "$units_file"' EXIT
printf '%s' "$combined_units" > "$units_file"

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
runner_families_json="$(jq -c '[.[].runner] | unique' <<<"$combined_units")"
inventory_json="$(jq -n \
  --arg gen "$generated_at" \
  --argjson families "$runner_families_json" \
  --slurpfile units_wrap "$units_file" \
  '{
    schema_version: "1.0.0",
    generated_at: $gen,
    runner_families: $families,
    entries: [$units_wrap[0][] | {run_unit_id, runner, adapter: (.provenance[0] // .runner), confidence, isolation: {lock_usage: .isolation.lock_usage}}]
  }')"
printf '%s\n' "$inventory_json" > "${output_dir%/}/inventory.json"

# ─── Emit test-catalog.proposed.yaml (always status: proposed) ─────────────
catalog_json="$(jq -n \
  --arg gen "$generated_at" \
  --slurpfile units_wrap "$units_file" \
  '{
    schema_version: "1.0.0",
    generated_at: $gen,
    status: "proposed",
    run_units: $units_wrap[0],
    source_pattern_mappings: [],
    mapping_approval: {status: "proposed"}
  }')"
printf '%s' "$catalog_json" | yq -o=yaml -P '.' > "${output_dir%/}/test-catalog.proposed.yaml"

if [[ "$(jq 'length' <<<"$combined_units")" -eq 0 ]]; then
  echo "aid-test-inventory.sh: empty-portfolio (zero discoverable run_units) — inventory/catalog written, this is not a failure" >&2
fi

echo "$output_dir"
