#!/usr/bin/env bash
# aid-test-adapter-contract.sh — P066 Step 2/3.
#
# Shared interface every test-portfolio adapter (Bats, package-script,
# declared-command — Steps 2-3) implements against. Sourced, never executed
# directly. NO top-level `set -e`/`set -euo pipefail` (matches
# aid-gate-runtime-baseline.sh/aid-gate-profile.sh convention): callers source
# this under their OWN `set -euo pipefail` shell, and an unguarded non-zero
# return here must never kill the caller's shell.
#
# Every function here is a pure helper: no network, no test execution, no
# writes outside stdout. Discovery adapters (aid-test-adapter-*.sh) call these
# to build schema-valid run_unit JSON objects; they never hand-roll the JSON
# shape themselves, so a schema field never drifts between adapters.

# adapter_supports_list_mode <runner> — echoes "true"/"false".
# Bats 1.8.2 (the version this repo has installed) has no --list flag — only
# -c/--count and -f/--filter — so static @test parsing is the supported path,
# never a "fallback". A future Bats version verified to expose a real
# enumerate interface may flip this, version-gated, never assumed present.
adapter_supports_list_mode() {
  local runner="$1"
  case "$runner" in
    bats) echo "false" ;;
    *) echo "false" ;;
  esac
}

# adapter_supports_filter <runner> — echoes "true"/"false".
adapter_supports_filter() {
  local runner="$1"
  case "$runner" in
    bats) echo "true" ;;
    *) echo "false" ;;
  esac
}

# adapter_slug <text> — lowercase, non-alnum runs collapsed to a single "-",
# leading/trailing "-" trimmed. Used for test_case_id, never for run_unit_id
# (which is a pure function of {runner, file path} only). A title made
# entirely of punctuation/non-ASCII characters (e.g. `@test "!!!"`) would
# otherwise slug to an empty string, violating the catalog schema's
# minLength:1 on test_case_id — falls back to a content hash in that case.
adapter_slug() {
  local text="$1" slug
  slug="$(printf '%s' "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$slug" ]]; then
    slug="tc-$(printf '%s' "$text" | sha256sum | cut -c1-12)"
  fi
  printf '%s' "$slug"
}

# adapter_run_unit_json <run_unit_id> <runner> <command_json> <test_cases_json>
#   [source_paths_json] [confidence]
#   Emits one schema-valid run_units[] entry (test-catalog.schema.json) to
#   stdout, with safe closed-enum defaults for every field a Wave-0 scanner
#   cannot yet know (parallel.status: unknown, recommendation: keep,
#   isolation left at "unknown"/empty). Later steps (Step 4's lock-usage
#   grep, Step 11's specialist findings) refine these fields — this helper
#   never invents a non-default value on their behalf.
#
#   <command_json> and <test_cases_json> must be valid JSON (object / array
#   literals respectively) — callers build these with jq themselves.
adapter_run_unit_json() {
  local run_unit_id="$1" runner="$2" command_json="$3" test_cases_json="$4"
  local source_paths_json="${5:-[]}" confidence="${6:-low}"

  local fingerprint
  fingerprint="$(adapter_command_fingerprint "$run_unit_id" "$command_json")" || return 1

  jq -n \
    --arg run_unit_id "$run_unit_id" \
    --arg runner "$runner" \
    --argjson source_paths "$source_paths_json" \
    --arg confidence "$confidence" \
    --argjson command "$command_json" \
    --arg fingerprint "$fingerprint" \
    --argjson test_cases "$test_cases_json" \
    '{
      run_unit_id: $run_unit_id,
      runner: $runner,
      source_paths: $source_paths,
      production_surfaces: $source_paths,
      test_level: "suite",
      risk_tags: [],
      profiles: ["default"],
      behavior_claims: [],
      confidence: $confidence,
      command: $command,
      runtime: { fingerprint: $fingerprint },
      parallel: { status: "unknown", exclusive_resources: [], max_workers: null, internal_parallelism: false },
      isolation: { temp_workspace: "unknown", fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: "static_parse" },
      recommendation: "keep",
      test_cases: $test_cases
    }'
}

# adapter_command_fingerprint <run_unit_id> <command_json>
#   Echoes gate_baseline_fingerprint(run_unit_id, canonical_json(command)),
#   where canonical_json is `jq -cS` (compact, sorted-object-keys)
#   serialization of the command object exactly as stored — never
#   argv-joined-with-spaces, which cannot distinguish ["a","b c"] from
#   ["a b","c"]. Reuses the real, existing gate_baseline_fingerprint function
#   (lib/aid-gate-runtime-baseline.sh:251) — no reimplemented hashing scheme.
adapter_command_fingerprint() {
  local run_unit_id="$1" command_json="$2"
  local canonical
  canonical="$(printf '%s' "$command_json" | jq -cS '.')" || return 1
  gate_baseline_fingerprint "$run_unit_id" "$canonical"
}
