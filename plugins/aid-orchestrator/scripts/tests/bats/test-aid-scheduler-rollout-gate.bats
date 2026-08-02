#!/usr/bin/env bats
# test-aid-scheduler-rollout-gate.bats — P069 Step 13.
#
# Proves aid-scheduler-rollout-gate.sh's staged-rollout resolution:
#   - a config claiming observe_parallel/parallel with fewer than 3
#     qualifying artifacts for the TARGET mode is forced to sequential
#   - 3 qualifying observe_parallel-tested artifacts unlock observe_parallel
#     but never parallel
#   - parallel requires 3 qualifying observe_parallel-tested artifacts AND
#     3 SEPARATE qualifying parallel-tested artifacts (cross-mode evidence
#     substitution rejected)
#   - a catalog fingerprint change invalidates prior evidence entirely
#     (never stale-but-acceptable)
#   - a single pass:false artifact disqualifies only itself, never averaged
#   - execution.yaml's test_audit.scheduler.mode is the only mode source

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT/.aid-o/config" "$TEST_PROJECT/.aid-o/work/evidence/scheduler-divergence"
  cd "$TEST_PROJECT"
  git init -q -b main
  git config user.email t@t.local
  git config user.name t
  echo base > README.md
  git add -A
  git commit -q -m base
  COMMIT_SHA="$(git rev-parse HEAD)"
  export COMMIT_SHA

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  GATE="$AID_PLUGIN_PATH/scripts/aid-scheduler-rollout-gate.sh"

  # A minimal approved catalog with 2 run_units, real fingerprints.
  cat > .aid-o/config/test-catalog.yaml <<'YAML'
schema_version: "1.0.0"
generated_at: "2026-08-02T00:00:00Z"
status: approved
run_units:
  - run_unit_id: "bats:suite-a"
    runner: bats
    source_paths: ["a.bats"]
    production_surfaces: ["a.bats"]
    test_level: suite
    risk_tags: []
    profiles: [default]
    behavior_claims: []
    confidence: medium
    command: {type: argv, argv: ["bats", "a.bats"]}
    runtime: {fingerprint: "sha256:aaaaaaaaaaaa"}
    parallel: {status: unknown, exclusive_resources: [], max_workers: null, internal_parallelism: false}
    isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: static_parse}
    recommendation: keep
    test_cases: []
  - run_unit_id: "bats:suite-b"
    runner: bats
    source_paths: ["b.bats"]
    production_surfaces: ["b.bats"]
    test_level: suite
    risk_tags: []
    profiles: [default]
    behavior_claims: []
    confidence: medium
    command: {type: argv, argv: ["bats", "b.bats"]}
    runtime: {fingerprint: "sha256:bbbbbbbbbbbb"}
    parallel: {status: unknown, exclusive_resources: [], max_workers: null, internal_parallelism: false}
    isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: static_parse}
    recommendation: keep
    test_cases: []
source_pattern_mappings: []
mapping_approval: {status: approved, approved_by: t, approved_at: "2026-08-02T00:00:00Z", reviewed_diff_hash: "sha256:deadbeef"}
YAML

  git add -f .aid-o/config/test-catalog.yaml
  git commit -q -m "add catalog"
  COMMIT_SHA="$(git rev-parse HEAD)"
  export COMMIT_SHA
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

_set_configured_mode() {
  cat > .aid-o/config/execution.yaml <<YAML
version: "1.0"
gates: {}
test_audit:
  scheduler:
    mode: $1
    resource_locks: {}
YAML
}

# _write_artifact <mode_tested> <pass> [fp_a] [fp_b] [commit_sha]
#   Writes a qualifying (by default) divergence-evidence artifact naming
#   both catalog run_units, using their REAL current fingerprints unless
#   overridden — a caller can pass a DIFFERENT fp to simulate catalog drift.
_write_artifact() {
  local mode="$1" pass="$2"
  local fp_a="${3:-sha256:aaaaaaaaaaaa}"
  local fp_b="${4:-sha256:bbbbbbbbbbbb}"
  local commit="${5:-$COMMIT_SHA}"
  local run_id; run_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr 'A-Z' 'a-z')"
  local cfs="sha256:$(printf '%s\n%s\n' "$fp_a" "$fp_b" | sort | sha256sum | cut -d' ' -f1)"
  local artifact=".aid-o/work/evidence/scheduler-divergence/${commit}-${mode}-${run_id}.json"
  jq -n \
    --arg run_id "$run_id" --arg cfs "$cfs" --arg csha "$commit" --arg mode "$mode" --argjson pass "$pass" \
    '{run_id:$run_id, catalog_fingerprint_set:$cfs, commit_sha:$csha, worktree_kind:"disposable_clone",
      mode_tested:$mode, selected_unit_ids:["bats:suite-a","bats:suite-b"],
      sequential_verdicts:[{unit_id:"bats:suite-a",result:"pass"},{unit_id:"bats:suite-b",result:"pass"}],
      scheduled_verdicts:[{unit_id:"bats:suite-a",result:"pass"},{unit_id:"bats:suite-b",result:"pass"}],
      membership_diff:[], verdict_diff:[], pass:$pass, evaluated_at:"2026-08-02T00:00:00Z"}' \
    > "$artifact"
}

@test "configured sequential: no evidence required, always allowed" {
  _set_configured_mode sequential
  run "$GATE" --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  run jq -r '.effective_mode' <<< "$output"
  [ "$output" == "sequential" ]
  run jq -r '.forced' <<< "$(echo "$output")"
}

@test "no execution.yaml at all: defaults to configured=sequential, effective=sequential" {
  rm -f .aid-o/config/execution.yaml
  run "$GATE" --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  run jq -r '.configured_mode' <<< "$output"
  [ "$output" == "sequential" ]
}

@test "observe_parallel configured with ZERO evidence: forced to sequential, shortfall named" {
  _set_configured_mode observe_parallel
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
  run jq -r '.forced' <<< "$out"
  [ "$output" == "true" ]
  run jq -r '.reason' <<< "$out"
  [[ "$output" == *"0"* ]]
}

@test "observe_parallel configured with exactly 2 qualifying artifacts (one short of 3): still forced to sequential" {
  _set_configured_mode observe_parallel
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
  run jq -r '.observe_parallel_qualifying_count' <<< "$out"
  [ "$output" == "2" ]
}

@test "observe_parallel configured with 3 qualifying artifacts: allowed through" {
  _set_configured_mode observe_parallel
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "observe_parallel" ]
  run jq -r '.forced' <<< "$out"
  [ "$output" == "false" ]
}

@test "3 qualifying observe_parallel artifacts with config claiming parallel: forced BACK to observe_parallel, not parallel (cross-mode reuse rejected)" {
  _set_configured_mode parallel
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "observe_parallel" ]
  run jq -r '.forced' <<< "$out"
  [ "$output" == "true" ]
}

@test "parallel configured with 3 qualifying observe_parallel AND 3 separate qualifying parallel artifacts: allowed through to parallel" {
  _set_configured_mode parallel
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact parallel true
  _write_artifact parallel true
  _write_artifact parallel true
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "parallel" ]
  run jq -r '.forced' <<< "$out"
  [ "$output" == "false" ]
}

@test "parallel configured with only 3 parallel-tested artifacts, no observe_parallel-tested ones: insufficient, forced to sequential" {
  _set_configured_mode parallel
  _write_artifact parallel true
  _write_artifact parallel true
  _write_artifact parallel true
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
}

@test "STALE (fingerprint-mismatched) artifacts, however many, are treated as zero qualifying — never stale-but-acceptable" {
  _set_configured_mode observe_parallel
  # Wrong fingerprint for suite-a — simulates a catalog change since capture.
  _write_artifact observe_parallel true "sha256:cccccccccccc" "sha256:bbbbbbbbbbbb"
  _write_artifact observe_parallel true "sha256:cccccccccccc" "sha256:bbbbbbbbbbbb"
  _write_artifact observe_parallel true "sha256:cccccccccccc" "sha256:bbbbbbbbbbbb"
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
  run jq -r '.observe_parallel_qualifying_count' <<< "$out"
  [ "$output" == "0" ]
}

@test "a single pass:false artifact among candidates disqualifies only itself, never averaged with passing ones" {
  _set_configured_mode observe_parallel
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel false
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.observe_parallel_qualifying_count' <<< "$out"
  [ "$output" == "3" ]
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "observe_parallel" ]
}

@test "evidence for a DIFFERENT commit_sha never counts, even if otherwise qualifying" {
  _set_configured_mode observe_parallel
  _write_artifact observe_parallel true "sha256:aaaaaaaaaaaa" "sha256:bbbbbbbbbbbb" "0000000000000000000000000000000000000000"
  _write_artifact observe_parallel true "sha256:aaaaaaaaaaaa" "sha256:bbbbbbbbbbbb" "0000000000000000000000000000000000000000"
  _write_artifact observe_parallel true "sha256:aaaaaaaaaaaa" "sha256:bbbbbbbbbbbb" "0000000000000000000000000000000000000000"
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.observe_parallel_qualifying_count' <<< "$out"
  [ "$output" == "0" ]
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
}

@test "execution.yaml's test_audit.scheduler.mode is the only mode source read — a project-level test-audit.yaml scheduler key (if present) is never consulted" {
  _set_configured_mode observe_parallel
  cat > .aid-o/config/test-audit.yaml <<'YAML'
budget_minutes_default: 30
max_read_only_audit_agents: 4
allowed_runners: [bats]
scheduler:
  mode: parallel
YAML
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  # configured_mode reflects execution.yaml's own value (observe_parallel),
  # NOT test-audit.yaml's scheduler.mode: parallel — proving the latter is
  # never consulted, even when present and set to a different value.
  run jq -r '.configured_mode' <<< "$out"
  [ "$output" == "observe_parallel" ]
}

@test "unrecognized test_audit.scheduler.mode value fails closed to sequential" {
  cat > .aid-o/config/execution.yaml <<'YAML'
version: "1.0"
gates: {}
test_audit:
  scheduler:
    mode: ci-fast-mode
    resource_locks: {}
YAML
  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
  run jq -r '.forced' <<< "$out"
  [ "$output" == "true" ]
}

@test "--project-root is required and must exist" {
  run "$GATE"
  [ "$status" -eq 2 ]
  run "$GATE" --project-root "$TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 3 ]
}

# ─── Codex review (P069 Step 13): 3 real findings, regression-tested ────────

@test "Codex HIGH: copying ONE qualifying artifact to multiple filenames (same run_id) never counts as multiple distinct runs" {
  _set_configured_mode observe_parallel
  _write_artifact observe_parallel true
  # Copy the single artifact just written to 2 more filenames — same run_id,
  # same content, just duplicated on disk.
  local src
  src="$(ls .aid-o/work/evidence/scheduler-divergence/*.json | head -1)"
  cp "$src" "${src%.json}-copy1.json"
  cp "$src" "${src%.json}-copy2.json"

  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.observe_parallel_qualifying_count' <<< "$out"
  [ "$output" == "1" ]
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
}

@test "Codex HIGH: a malformed artifact (JSON array instead of object) is skipped, never crashes the resolver" {
  _set_configured_mode observe_parallel
  echo '[]' > .aid-o/work/evidence/scheduler-divergence/malformed-array.json
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true

  run "$GATE" --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  run jq -r '.effective_mode' <<< "$output"
  [ "$output" == "observe_parallel" ]
}

@test "Codex HIGH: an artifact missing required fields (JSON object, but incomplete) is skipped, never crashes the resolver" {
  _set_configured_mode observe_parallel
  echo '{"commit_sha":"deadbeef"}' > .aid-o/work/evidence/scheduler-divergence/incomplete.json
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true
  _write_artifact observe_parallel true

  run "$GATE" --project-root "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  run jq -r '.effective_mode' <<< "$output"
  [ "$output" == "observe_parallel" ]
}

@test "Codex HIGH: a catalog run_unit with a missing/null runtime.fingerprint never qualifies as a matching 'null' fingerprint" {
  _set_configured_mode observe_parallel
  # A catalog whose unit has NO runtime.fingerprint at all (null).
  cat > .aid-o/config/test-catalog.yaml <<'YAML'
schema_version: "1.0.0"
generated_at: "2026-08-02T00:00:00Z"
status: approved
run_units:
  - run_unit_id: "bats:suite-a"
    runner: bats
    source_paths: ["a.bats"]
    production_surfaces: ["a.bats"]
    test_level: suite
    risk_tags: []
    profiles: [default]
    behavior_claims: []
    confidence: medium
    command: {type: argv, argv: ["bats", "a.bats"]}
    runtime: {}
    parallel: {status: unknown, exclusive_resources: [], max_workers: null, internal_parallelism: false}
    isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: static_parse}
    recommendation: keep
    test_cases: []
source_pattern_mappings: []
mapping_approval: {status: approved, approved_by: t, approved_at: "2026-08-02T00:00:00Z", reviewed_diff_hash: "sha256:deadbeef"}
YAML

  # sha256 of the literal string "null\n" — what a naive `jq -r` render of a
  # missing/null fingerprint would produce, if it were (wrongly) accepted.
  local null_hash; null_hash="sha256:$(printf 'null\n' | sha256sum | cut -d' ' -f1)"
  local run_id; run_id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr 'A-Z' 'a-z')"
  jq -n --arg run_id "$run_id" --arg cfs "$null_hash" --arg csha "$COMMIT_SHA" \
    '{run_id:$run_id, catalog_fingerprint_set:$cfs, commit_sha:$csha, worktree_kind:"disposable_clone",
      mode_tested:"observe_parallel", selected_unit_ids:["bats:suite-a"],
      sequential_verdicts:[{unit_id:"bats:suite-a",result:"pass"}],
      scheduled_verdicts:[{unit_id:"bats:suite-a",result:"pass"}],
      membership_diff:[], verdict_diff:[], pass:true, evaluated_at:"2026-08-02T00:00:00Z"}' \
    > ".aid-o/work/evidence/scheduler-divergence/${COMMIT_SHA}-observe_parallel-${run_id}.json"

  run "$GATE" --project-root "$TEST_PROJECT"
  out="$output"
  run jq -r '.observe_parallel_qualifying_count' <<< "$out"
  [ "$output" == "0" ]
  run jq -r '.effective_mode' <<< "$out"
  [ "$output" == "sequential" ]
}
