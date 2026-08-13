#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 3 — a rolled-back release must leave no file on the new version.
# Exercises the FALLBACK bookkeeping path explicitly (no .aid-o/config/
# project.yaml): that file is gitignored, so any clone or worktree — where
# plan-final releases actually run — takes this path, not the config path.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  RELEASE="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/aid-release.sh"
  export RELEASE
}

teardown() {
  teardown_test_evidence_dir
}

# _seed_fallback <released-version> <changelog-body>
# NO project.yaml — forces the fallback path. marketplace.json carries BOTH
# .metadata.version AND .plugins[0].version (no top-level .version), which is
# this repository's own real marketplace.json shape and the exact case the
# round-5-fixed "Don't double-add" bug silently dropped from UPDATED[].
_seed_fallback() {
  local released="$1" changelog="$2"
  mkdir -p "$TEST_PROJECT_ROOT/.claude-plugin"
  cat > "$TEST_PROJECT_ROOT/.claude-plugin/marketplace.json" <<EOF
{
  "metadata": {"version": "$released"},
  "plugins": [{"version": "$released"}]
}
EOF
  printf '%s' "$changelog" > "$TEST_PROJECT_ROOT/CHANGELOG.md"
  ( cd "$TEST_PROJECT_ROOT" \
      && git init -q \
      && git config user.email "t@example.com" \
      && git config user.name "T" \
      && git add -A \
      && git commit -qm "init" )
}

_changelog_mismatched_header() {
  cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [1.0.0] — 2026-07-01

### Added
- The first real release.
EOF
}

@test "aborted prepare (fallback path): every file clean beforehand is clean again" {
  _seed_fallback "2.0.0" "$(_changelog_mismatched_header)"
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rolled back this run's version-file edits"* ]]
  [ -z "$(git status --porcelain)" ]
  [ "$(jq -r '.metadata.version' .claude-plugin/marketplace.json)" = "2.0.0" ]
  [ "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)" = "2.0.0" ]
}

@test "aborted prepare (fallback path): a file with two version fields is counted and restored once" {
  _seed_fallback "2.0.0" "$(_changelog_mismatched_header)"
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]

  # The printed count is the number of DISTINCT files edited: marketplace.json
  # (once, not twice for its two version fields) + CHANGELOG.md.
  [[ "$output" == *"Updated 2 files total."* ]]

  # marketplace.json restored fully (both fields), not left stranded on 2.0.1.
  [ "$(jq -r '.metadata.version' .claude-plugin/marketplace.json)" = "2.0.0" ]
  [ "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)" = "2.0.0" ]
}

@test "aborted prepare (fallback path): a file already dirty before the run is named, not silently skipped" {
  _seed_fallback "2.0.0" "$(_changelog_mismatched_header)"
  cd "$TEST_PROJECT_ROOT"
  printf '{"metadata": {"version": "2.0.0"}, "plugins": [{"version": "2.0.0"}], "operatorEdit": true}\n' \
    > .claude-plugin/marketplace.json

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKIPPED (already dirty before this run, left as-is): .claude-plugin/marketplace.json"* ]]
  # The pre-existing edit survives — only paths this run made dirty are reverted.
  run grep -c 'operatorEdit' .claude-plugin/marketplace.json
  [ "$output" = "1" ]
}

@test "a repo with project.yaml present is unaffected (config path untouched by this step)" {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" \
           "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin"
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<EOF
{"version": "2.0.0"}
EOF
  printf '%s' "$(_changelog_mismatched_header)" > "$TEST_PROJECT_ROOT/CHANGELOG.md"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<'EOF'
versioning:
  source: CHANGELOG.md
  files:
    - path: plugins/aid-orchestrator/.claude-plugin/plugin.json
      type: json
      field: version
EOF
  ( cd "$TEST_PROJECT_ROOT" && git init -q \
      && git config user.email "t@example.com" && git config user.name "T" \
      && git add -A && git commit -qm "init" )
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rolled back this run's version-file edits"* ]]
  [ -z "$(git status --porcelain)" ]
}
