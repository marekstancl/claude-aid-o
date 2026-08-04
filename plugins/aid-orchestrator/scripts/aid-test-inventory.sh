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
# Both emitted artifacts are schema-validated (test-audit-inventory.schema.json
# / test-catalog.schema.json) BEFORE publish, and published atomically
# (tmp-file-then-mv, same discipline as aid-gate-runtime-baseline.sh) — a
# crash/kill mid-write, or a document that fails its own schema, must never
# leave a partial or invalid artifact at the real path (PM feedback, E1
# re-review).
#
# Usage:
#   aid-test-inventory.sh --project-root <path> --audit-id <id> \
#                          --output-dir <dir> [--execution-yaml <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/aid-test-adapter-contract.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-contract.sh"
# shellcheck source=lib/aid-test-adapter-bats.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-bats.sh"
# shellcheck source=lib/aid-test-adapter-package-script.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-package-script.sh"
# shellcheck source=lib/aid-test-adapter-shell-suite.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-shell-suite.sh"
# shellcheck source=lib/aid-test-adapter-declared-command.sh
source "${SCRIPT_DIR}/lib/aid-test-adapter-declared-command.sh"

INVENTORY_SCHEMA="${PLUGIN_ROOT}/defaults/schemas/test-audit-inventory.schema.json"
CATALOG_SCHEMA="${PLUGIN_ROOT}/defaults/schemas/test-catalog.schema.json"

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
#
#   Linear (NDJSON-buffered), not O(n^2): an earlier version re-read AND
#   re-wrote the WHOLE units array on every single bats run_unit
#   (`.[$i].isolation.lock_usage = $lk`), so annotating N files cost O(n^2)
#   total — the 300-file performance-regression test became a minute-scale
#   aggregate. Now streams one unit object at a time (each read/write is
#   O(1) in the array's size) and slurps the final array exactly once.
_aid_test_inventory_annotate_lock_usage() {
  local project_root="$1" units_json="$2"
  local ndjson_file
  ndjson_file="$(adapter_ndjson_start)"
  local unit runner rel_path abs_path lock_json meta

  while IFS= read -r unit; do
    # ONE jq call for BOTH runner and source_paths[0] (tab-separated), not
    # two — jq's own process-startup cost dominates wall-clock time at
    # portfolio scale far more than its actual work (PM feedback,
    # performance). Skips the merge-write entirely for non-bats units and
    # for bats units with no detected lock usage (isolation.lock_usage is
    # already "[]" from construction — writing "[]" over "[]" is a no-op).
    meta="$(jq -r '[.runner, (.source_paths[0] // "")] | @tsv' <<<"$unit")"
    runner="${meta%%$'\t'*}"
    rel_path="${meta#*$'\t'}"
    if [[ "$runner" == "bats" && -n "$rel_path" ]]; then
      abs_path="${project_root%/}/${rel_path}"
      if [[ -f "$abs_path" ]]; then
        lock_json="$(_aid_test_inventory_lock_usage_for_file "$abs_path")"
        if [[ "$lock_json" != "[]" ]]; then
          unit="$(jq -c --argjson lk "$lock_json" '.isolation.lock_usage = $lk' <<<"$unit")"
        fi
      fi
    fi
    adapter_ndjson_append "$ndjson_file" "$unit"
  done < <(jq -c '.[]' <<<"$units_json")

  adapter_ndjson_finish "$ndjson_file"
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
# P072 Step 7 — the fifth adapter. Classification between this one and the
# bats adapter is by SHEBANG, so the 7 `test-*.sh` files carrying
# `#!/usr/bin/env bats` land in bats_units and are run with `bats`, not here.
shell_skipped_file="${output_dir%/}/shell-suite-skipped.json"
shell_units="$(shell_suite_adapter_discover "$project_root" "$project_root" "$shell_skipped_file")"
combined_units="$(jq -c -s 'add' <(printf '%s' "$bats_units") <(printf '%s' "$pkgscript_units") <(printf '%s' "$shell_units"))"
combined_units="$(declared_command_adapter_discover "$execution_yaml" "$combined_units" "$project_root")"

# ─── Lock-usage static grep (Bats run_units only) ───────────────────────────
combined_units="$(_aid_test_inventory_annotate_lock_usage "$project_root" "$combined_units")"

# Discovery uncertainty is always confidence:low, never silently upgraded —
# this is Wave 0's own contract regardless of what an individual adapter set
# (an adapter's higher confidence reflects its own internal certainty about
# WHAT it found, e.g. "this really is the declared gate command", not
# license to skip Wave 0's blanket "purely static discovery" caveat).
combined_units="$(jq -c 'map(.confidence = "low")' <<<"$combined_units")"

# ─── P072 Step 10: cross-runner reconciliation ─────────────────────────────
#
# Two things this must NOT do, both learned the hard way:
#
#   * It must not treat a declared gate's `source_paths` as a test-file
#     identity. A gate's source_paths names the file that DECLARES it — all 8
#     declared-command units in this repository share
#     `.aid-o/config/execution.yaml` — so a naive path-identity map sees eight
#     same-runner units claiming one path and fails this very repository.
#     The relation a gate has with the tests it runs lives in `command.argv`.
#
#   * It must not silently de-duplicate. A file claimed by two adapters, or an
#     id emitted twice, is a defect to report, not an inconvenience to smooth
#     over — the disposition reconciliation downstream counts on ids being
#     exactly as unique as they claim.
_aid_inventory_reconcile() {
  local units_json="$1"

  # (1) Path identity over the runners whose source_paths really is the test
  #     file. `declared-command` is excluded by construction.
  local dupe_same_runner
  dupe_same_runner="$(jq -r '
    [ .[] | select(.runner != "declared-command")
      | {runner, path: (.source_paths[0] // ""), id: .run_unit_id}
      | select(.path != "") ]
    | group_by([.path, .runner])
    | map(select(length > 1))
    | .[0] // empty
    | "\(.[0].path) claimed twice by runner \(.[0].runner): \(map(.id) | join(", "))"
  ' <<<"$units_json")"
  if [[ -n "$dupe_same_runner" ]]; then
    echo "aid-test-inventory.sh: $dupe_same_runner" >&2
    echo "  Two units of the SAME runner cannot claim one file — this is an adapter defect, and resolving it by an arbitrary tie-break would hide it." >&2
    exit 9
  fi

  # (2) Cross-runner overlap, resolved by a fixed precedence: a package-script
  #     invocation is what the project actually runs, so it outranks a bare
  #     shell discovery of the same file. bats and sh cannot overlap after the
  #     shebang classification, so an overlap between THEM is a defect.
  local overlaps_json
  overlaps_json="$(jq -c '
    [ .[] | select(.runner != "declared-command")
      | {runner, path: (.source_paths[0] // ""), id: .run_unit_id}
      | select(.path != "") ]
    | group_by(.path)
    | map(select(length > 1))
    | map({ path: .[0].path, ids: map(.id), runners: map(.runner) })
  ' <<<"$units_json")"

  local bad_overlap
  bad_overlap="$(jq -r '
    [ .[] | select((.runners | index("bats")) != null and (.runners | index("sh")) != null) ]
    | .[0] // empty | .path // empty' <<<"$overlaps_json")"
  if [[ -n "$bad_overlap" ]]; then
    echo "aid-test-inventory.sh: '$bad_overlap' was claimed by BOTH the bats and sh adapters — shebang classification should make that impossible, so this is an adapter defect rather than something to resolve by precedence." >&2
    exit 9
  fi

  # (3) contains[] — derived from each declared gate's argv, never from its
  #     source_paths. This is the relation that tells a later double-execution
  #     check the difference between "gate X legitimately runs unit Y" and
  #     "unit Y was reached twice by two independent gates".
  local contains_json
  contains_json="$(jq -c '
    (. | map(select(.runner == "bats" or .runner == "sh"))) as $tests
    | [ .[] | select(.runner == "declared-command")
        | . as $g
        # Declared gates carry `type: shell` with a `.command.shell` string,
        # not an argv array — reading only argv found nothing and produced an
        # empty contains[], which would have looked like "no gate runs any
        # test" rather than like a bug.
        | (if (.command.argv // null) != null
           then (.command.argv | join(" "))
           else (.command.shell // "") end) as $cmd
        | if ($cmd | test("\\{[a-z_]+\\}")) then
            {gate: $g.run_unit_id, kind: "context_required",
             partition: "all", membership: "exact", run_unit_ids: []}
          elif ($cmd | test("run-all-tests\\.sh")) then
            # The aggregate runner skips suites delegated to their own CI job,
            # so its real membership is also decided at runtime.
            {gate: $g.run_unit_id, kind: "aggregate_runner",
             partition: "all", membership: "runtime_partitioned",
             run_unit_ids: ($tests | map(.run_unit_id))}
          elif ($cmd | test("aid-bats-parallel-lane\\.sh")) then
            # The lane PARTITIONS the bats units — `--pool-only` runs the
            # pool, `--dedicated-only` runs the boundary files — so the two
            # gates are complementary, not overlapping. Claiming both contain
            # every bats unit produced 105 false double-execution reports.
            # Which unit lands in which bucket is a RUNTIME fact (it depends
            # on the catalog/allowlist at dispatch time), so the candidate set
            # is recorded with membership: "runtime_partitioned" rather than
            # asserted as exact.
            {gate: $g.run_unit_id, kind: "catalog_pool_runner",
             partition: (if ($cmd | test("--dedicated-only")) then "dedicated"
                         elif ($cmd | test("--pool-only")) then "pool"
                         else "all" end),
             membership: "runtime_partitioned",
             run_unit_ids: ($tests | map(select(.runner == "bats") | .run_unit_id))}
          else
            # Plain substring containment, not a regex: a source path is full
            # of `/` and `.`, which as a pattern would match far more than the
            # file it names.
            ($tests | map(select(.source_paths[0] as $p | ($cmd | contains($p)))) | map(.run_unit_id)) as $direct
            | if ($direct | length) > 0
              then {gate: $g.run_unit_id, kind: "direct_invocation",
                    partition: "all", membership: "exact", run_unit_ids: $direct}
              else empty end
          end ]
  ' <<<"$units_json")"

  # (4) The arithmetic must close. A unit that vanished between discovery and
  #     publication is exactly what nobody would otherwise notice.
  local per_runner_json total_units files_seen emitted
  per_runner_json="$(jq -c '[.[] | .runner] | group_by(.) | map({(.[0]): length}) | add // {}' <<<"$units_json")"
  total_units="$(jq 'length' <<<"$units_json")"
  emitted="$(jq '[.[] | .runner] | length' <<<"$units_json")"
  files_seen="$(jq '[.[] | select(.runner != "declared-command") | .source_paths[0] // empty] | unique | length' <<<"$units_json")"
  if [[ "$total_units" -ne "$emitted" ]]; then
    echo "aid-test-inventory.sh: run-unit arithmetic does not close ($total_units published vs $emitted emitted) — a unit vanished between discovery and publication" >&2
    exit 8
  fi

  jq -nc \
    --argjson per_runner "$per_runner_json" \
    --argjson overlaps "$overlaps_json" \
    --argjson contains "$contains_json" \
    --argjson total "$total_units" \
    --argjson files "$files_seen" \
    '{per_runner_counts: $per_runner, total_run_units: $total, files_seen: $files,
      overlaps: $overlaps, contains: $contains}'
}

# ─── Collision detection: two adapters claiming the same run_unit_id ───────
collisions="$(adapter_check_run_unit_id_collisions "$combined_units")"
if [[ -n "$collisions" ]]; then
  echo "aid-test-inventory.sh: run_unit_id collision(s) detected:" >&2
  echo "$collisions" >&2
  exit 1
fi

# ─── Build inventory.json + test-catalog.proposed.yaml (not yet published) ─
# combined_units can be arbitrarily large (a big monorepo's full portfolio) —
# passed via a temp file + --slurpfile, never --argjson on argv, which would
# exceed the OS ARG_MAX for a big enough catalog ("Argument list too long").
units_file="$(mktemp)"
trap 'rm -f "$units_file"' EXIT
printf '%s' "$combined_units" > "$units_file"

reconciliation_json="$(_aid_inventory_reconcile "$combined_units")"

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
runner_families_json="$(jq -c '[.[].runner] | unique' <<<"$combined_units")"
inventory_json="$(jq -n \
  --arg gen "$generated_at" \
  --argjson families "$runner_families_json" \
  --argjson reconciliation "$reconciliation_json" \
  --slurpfile units_wrap "$units_file" \
  '{
    schema_version: "1.0.0",
    generated_at: $gen,
    runner_families: $families,
    reconciliation: $reconciliation,
    entries: [$units_wrap[0][] | {run_unit_id, runner, adapter: (.provenance[0] // .runner), confidence, isolation: {lock_usage: .isolation.lock_usage}}]
  }')"

# The routing map the approver will re-derive and require. Writing `[]` here
# unconditionally is what made a freshly-proposed catalog unapprovable: the
# approver re-derives this from a fresh selector snapshot and refuses anything
# that does not reproduce it, so producer and consumer disagreed about the same
# field. Both now call the same function. Where the dogfood selector does not
# exist, `[]` remains correct and the approver's guard is a no-op too.
# shellcheck source=lib/aid-test-catalog-selector-mappings.sh
source "${SCRIPT_DIR}/lib/aid-test-catalog-selector-mappings.sh"
mappings_json="[]"
if aid_test_catalog_selector_applies "$project_root"; then
  mappings_json="$(aid_test_catalog_expected_mappings "$project_root" \
    "${SCRIPT_DIR}/aid-test-catalog-selector-snapshot.sh")" \
    || { echo "aid-test-inventory.sh: the selector snapshot this project's catalog approval requires could not be produced — refusing to propose a catalog whose routing map is a guess" >&2; exit 1; }
fi

catalog_json="$(jq -n \
  --argjson mappings "$mappings_json" \
  --arg gen "$generated_at" \
  --slurpfile units_wrap "$units_file" \
  '{
    schema_version: "1.0.0",
    generated_at: $gen,
    status: "proposed",
    run_units: $units_wrap[0],
    source_pattern_mappings: $mappings,
    mapping_approval: {status: "proposed"}
  }')"
catalog_yaml="$(printf '%s' "$catalog_json" | yq -o=yaml -P '.')"

# ─── Validate BEFORE publish — never write an invalid artifact to its real
# path, even transiently. Fails closed (adapter_validate_schema's own
# contract) if the validator itself is unavailable.
if ! adapter_validate_schema "$INVENTORY_SCHEMA" "$inventory_json"; then
  echo "aid-test-inventory.sh: generated inventory.json failed schema validation — refusing to publish" >&2
  exit 1
fi
if ! adapter_validate_schema "$CATALOG_SCHEMA" "$catalog_json"; then
  echo "aid-test-inventory.sh: generated test-catalog.proposed.yaml failed schema validation — refusing to publish" >&2
  exit 1
fi

# ─── Atomic publish: tmp-file-then-mv for BOTH artifacts, same discipline as
# aid-gate-runtime-baseline.sh — a crash/kill between the tmp write and the
# mv leaves the real files exactly as they were (never a torn/partial write).
inventory_tmp="${output_dir%/}/inventory.json.tmp.$$"
catalog_tmp="${output_dir%/}/test-catalog.proposed.yaml.tmp.$$"
printf '%s\n' "$inventory_json" > "$inventory_tmp"
printf '%s' "$catalog_yaml" > "$catalog_tmp"
mv "$inventory_tmp" "${output_dir%/}/inventory.json"
mv "$catalog_tmp" "${output_dir%/}/test-catalog.proposed.yaml"

if [[ "$(jq 'length' <<<"$combined_units")" -eq 0 ]]; then
  echo "aid-test-inventory.sh: empty-portfolio (zero discoverable run_units) — inventory/catalog written, this is not a failure" >&2
fi

echo "$output_dir"
