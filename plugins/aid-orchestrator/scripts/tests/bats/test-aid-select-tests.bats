#!/usr/bin/env bats
# test-aid-select-tests.bats — aid-select-tests.sh targeted test selector
# (P061 EPIC 3 Step 9). Covers the Initial mapping, CHECKPOINT 3 (a single
# aid-plan-diff.sh change selects ONLY test-plan-diff.sh), the D-selector-1
# unknown-production-path fail case, the docs-only no-op case, JSON summary
# shape, --evidence-file, multi-path union/dedup, and real fail-exit-code
# propagation from a selected test.
#
# Test-execution isolation: AID_SELECT_TESTS_PLUGIN_ROOT (a seam the script
# itself documents, mirroring AID_GATE_BASELINE_FILE / AID_CHANGED_PATHS
# elsewhere in this plugin) redirects where the selector goes to EXECUTE a
# mapped test file, without touching the hardcoded production
# path -> test-path mapping in aid-select-tests.sh itself (that mapping is
# always the real one — this file only fakes what lives at those relative
# locations, so the suite stays fast and deterministic instead of running
# the real multi-minute suites like test-release-policy.bats).

load test-helpers.bash

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  TEST_PROJECT="$TEST_TMPDIR/project"
  mkdir -p "$TEST_PROJECT"
  cd "$TEST_PROJECT"
  git init -q -b main
  git config user.email "test@test.local"
  git config user.name "Test"
  mkdir -p plugins/aid-orchestrator/scripts \
           plugins/aid-orchestrator/defaults/schemas \
           plugins/aid-orchestrator/defaults/policies \
           plugins/aid-orchestrator/lib/ui-fidelity
  echo "base" > README.md
  git add -A
  git commit -q -m "base"
  BASE_SHA="$(git rev-parse HEAD)"
  export BASE_SHA

  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  SELECTOR="$AID_PLUGIN_PATH/scripts/aid-select-tests.sh"
  export SELECTOR

  # Fast-stub root: aid-select-tests.sh's own production mapping still
  # decides WHICH relative test path a changed path selects; this root only
  # supplies fast fake content at those relative paths for execution speed.
  STUB_ROOT="$TEST_TMPDIR/stub-plugin-root"
  export STUB_ROOT
  export AID_SELECT_TESTS_PLUGIN_ROOT="$STUB_ROOT"
  mkdir -p "$STUB_ROOT/scripts/tests/bats"
}

teardown() {
  cd /
  unset AID_SELECT_TESTS_PLUGIN_ROOT
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# stub_bash <relpath> <exit_code> — writes a fast bash test stub under
# STUB_ROOT at the given PLUGIN_PREFIX-stripped relative path.
stub_bash() {
  local relpath="$1" code="${2:-0}"
  mkdir -p "$STUB_ROOT/$(dirname "$relpath")"
  cat > "$STUB_ROOT/$relpath" <<EOF
#!/usr/bin/env bash
exit ${code}
EOF
  chmod +x "$STUB_ROOT/$relpath"
}

# stub_bats <relpath> <pass|fail> — writes a fast one-assertion bats stub.
# NOTE: the literal token "@test" is built from $at at write-time (never
# appears verbatim at start-of-line in THIS source file) — bats-core's own
# test-file scanner is a simple line-anchored grep for ^@test, so a literal
# occurrence inside this heredoc would be miscounted as a 26th test in THIS
# suite (observed: it shifted every subsequent test's index by one).
stub_bats() {
  local relpath="$1" outcome="${2:-pass}"
  mkdir -p "$STUB_ROOT/$(dirname "$relpath")"
  local assertion="[ 1 -eq 1 ]"
  [[ "$outcome" == "fail" ]] && assertion="[ 1 -eq 2 ]"
  local at="@"
  cat > "$STUB_ROOT/$relpath" <<EOF
#!/usr/bin/env bats
${at}test "stub" {
  ${assertion}
}
EOF
}

commit_change() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  echo "changed" >> "$file"
  git add -A
  git commit -q -m "touch $file"
}

# ─── CHECKPOINT 3 (mandatory) ───────────────────────────────────────────────

@test "CHECKPOINT 3: fixture touching ONLY aid-plan-diff.sh selects ONLY test-plan-diff.sh" {
  stub_bash "scripts/tests/test-plan-diff.sh" 0
  commit_change "plugins/aid-orchestrator/scripts/aid-plan-diff.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/test-plan-diff.sh"]' ]
}

# ─── Initial mapping coverage ───────────────────────────────────────────────

@test "aid-release-policy.sh change selects test-release-policy.bats, not the surface-check suite" {
  stub_bats "scripts/tests/bats/test-release-policy.bats" pass
  commit_change "plugins/aid-orchestrator/scripts/aid-release-policy.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/bats/test-release-policy.bats"]' ]
}

@test "aid-fsm.sh change selects test-aid-fsm.bats" {
  stub_bats "scripts/tests/bats/test-aid-fsm.bats" pass
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats"]' ]
}

@test "aid-prefilter.sh change selects test-aid-prefilter.bats" {
  stub_bats "scripts/tests/bats/test-aid-prefilter.bats" pass
  commit_change "plugins/aid-orchestrator/scripts/aid-prefilter.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/bats/test-aid-prefilter.bats"]' ]
}

@test "aid-evidence-verify.sh change selects test-evidence-verify.sh" {
  stub_bash "scripts/tests/test-evidence-verify.sh" 0
  commit_change "plugins/aid-orchestrator/scripts/aid-evidence-verify.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/test-evidence-verify.sh"]' ]
}

@test "defaults/schemas/** change selects test-protocol-validate.sh" {
  stub_bash "scripts/tests/test-protocol-validate.sh" 0
  commit_change "plugins/aid-orchestrator/defaults/schemas/aid-protocol-v2.schema.json"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/test-protocol-validate.sh"]' ]
}

@test "delivery-gate.yaml change selects test-delivery-gate.sh" {
  stub_bash "scripts/tests/test-delivery-gate.sh" 0
  commit_change "plugins/aid-orchestrator/defaults/policies/delivery-gate.yaml"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/test-delivery-gate.sh"]' ]
}

@test "lib/ui-fidelity/** change selects both ui-fidelity guard-chain suites" {
  stub_bash "scripts/tests/test-ui-fidelity-e2e.sh" 0
  stub_bash "scripts/tests/test-fsm-ui-fidelity.sh" 0
  commit_change "plugins/aid-orchestrator/lib/ui-fidelity/ui-compare.mjs"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  run jq -e '(.selected_tests | length) == 2
    and (.selected_tests | index("plugins/aid-orchestrator/scripts/tests/test-ui-fidelity-e2e.sh") != null)
    and (.selected_tests | index("plugins/aid-orchestrator/scripts/tests/test-fsm-ui-fidelity.sh") != null)' <<< "$output"
  [ "$status" -eq 0 ]
}

# ─── D-selector-1: unknown production path is a deliberate fail ───────────

@test "unknown production path fails loud with the D-selector-1 reason string (not a silent skip)" {
  printf 'plugins/aid-orchestrator/scripts/aid-brand-new-thing.sh\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 3 ]
  [[ "$output" == *"unverifiable: unknown production path plugins/aid-orchestrator/scripts/aid-brand-new-thing.sh — upgrade to standard/full profile"* ]]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '[]' ]
}

@test "unknown production path alongside a mapped path still runs the mapped test, but overall stays failed" {
  stub_bash "scripts/tests/test-plan-diff.sh" 0
  printf 'plugins/aid-orchestrator/scripts/aid-plan-diff.sh\nplugins/aid-orchestrator/scripts/aid-brand-new-thing.sh\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 3 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '["plugins/aid-orchestrator/scripts/tests/test-plan-diff.sh"]' ]
}

# ─── Docs-only / non-production no-op ──────────────────────────────────────

@test "docs-only change: exit 0, selected_tests empty, reasoning explains why nothing ran" {
  printf 'README.md\nplugins/aid-orchestrator/skills/pipeline.md\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '[]' ]
  selector_output="$output"
  run jq -e '.reasoning | length >= 2' <<< "$selector_output"
  [ "$status" -eq 0 ]
}

@test "path outside scripts/ and defaults/ (e.g. unmapped lib/ subtree) is treated as no-op, not unverifiable" {
  printf 'plugins/aid-orchestrator/lib/brainstorm-server/server.js\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 0 ]
  selected="$(jq -c '.selected_tests' <<< "$output")"
  [ "$selected" = '[]' ]
}

@test "no changed paths at all: exit 0, empty selection, reasoning non-empty" {
  : > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 0 ]
  run jq -e '(.selected_tests == []) and (.reasoning | length > 0)' <<< "$output"
  [ "$status" -eq 0 ]
}

# ─── JSON summary shape ─────────────────────────────────────────────────────

@test "JSON summary always has selected_tests, reasoning, exit_status keys" {
  printf 'README.md\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  run jq -e 'has("selected_tests") and has("reasoning") and has("exit_status")' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "--evidence-file writes the same JSON summary to disk" {
  local evfile="$TEST_TMPDIR/evidence/summary.json"
  printf 'README.md\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt" --evidence-file "$evfile"
  [ "$status" -eq 0 ]
  [ -f "$evfile" ]
  run jq -e 'has("selected_tests") and has("reasoning") and has("exit_status")' "$evfile"
  [ "$status" -eq 0 ]
}

# ─── Union / dedup across multiple changed paths ───────────────────────────

@test "two changed paths mapping to different tests both appear, deduped and unioned" {
  stub_bash "scripts/tests/test-plan-diff.sh" 0
  stub_bats "scripts/tests/bats/test-aid-fsm.bats" pass
  commit_change "plugins/aid-orchestrator/scripts/aid-plan-diff.sh"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  run jq -e '(.selected_tests | length) == 2' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "changing the same mapped path twice does not duplicate the selected test" {
  stub_bash "scripts/tests/test-plan-diff.sh" 0
  printf 'plugins/aid-orchestrator/scripts/aid-plan-diff.sh\nplugins/aid-orchestrator/scripts/aid-plan-diff.sh\n' > "$TEST_TMPDIR/paths.txt"

  run "$SELECTOR" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 0 ]
  run jq -e '(.selected_tests | length) == 1' <<< "$output"
  [ "$status" -eq 0 ]
}

# ─── Real gate-command behavior: aggregate exit code reflects test outcome ─

@test "aggregate exit status is non-zero (1) when a selected bash test actually fails" {
  stub_bash "scripts/tests/test-plan-diff.sh" 1
  commit_change "plugins/aid-orchestrator/scripts/aid-plan-diff.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 1 ]
  run jq -e '.test_results[0].result == "fail"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "aggregate exit status is non-zero (1) when a selected bats test actually fails" {
  stub_bats "scripts/tests/bats/test-aid-fsm.bats" fail
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 1 ]
  run jq -e '.test_results[0].result == "fail"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "aggregate exit status is 0 when all selected tests actually pass" {
  stub_bash "scripts/tests/test-plan-diff.sh" 0
  stub_bats "scripts/tests/bats/test-aid-fsm.bats" pass
  commit_change "plugins/aid-orchestrator/scripts/aid-plan-diff.sh"
  commit_change "plugins/aid-orchestrator/scripts/aid-fsm.sh"

  run "$SELECTOR" --base "$BASE_SHA"
  [ "$status" -eq 0 ]
  run jq -e '[.test_results[].result] == ["pass","pass"]' <<< "$output"
  [ "$status" -eq 0 ]
}

# ─── CLI validation ─────────────────────────────────────────────────────────

@test "CLI: --base and --paths-file together is a usage error (exit 10)" {
  printf 'README.md\n' > "$TEST_TMPDIR/paths.txt"
  run "$SELECTOR" --base "$BASE_SHA" --paths-file "$TEST_TMPDIR/paths.txt"
  [ "$status" -eq 10 ]
}

@test "CLI: neither --base nor --paths-file is a usage error (exit 10)" {
  run "$SELECTOR"
  [ "$status" -eq 10 ]
}

@test "CLI: --paths-file pointing at a missing file is a usage error (exit 10)" {
  run "$SELECTOR" --paths-file "$TEST_TMPDIR/does-not-exist.txt"
  [ "$status" -eq 10 ]
}

@test "CLI: --base with an unresolvable ref is a usage error (exit 10), not a hang or false pass" {
  run "$SELECTOR" --base "not-a-real-ref-0000"
  [ "$status" -eq 10 ]
}
