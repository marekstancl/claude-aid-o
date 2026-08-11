#!/usr/bin/env bats
# aid-tier: t2
# Tests for aid-release.sh

setup() {
  TEST_DIR=$(mktemp -d)
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  RELEASE="$REPO_ROOT/plugins/aid-orchestrator/scripts/aid-release.sh"

  # Set up minimal fake repo structure
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create package.json files
  echo '{"name":"root","version":"1.7.0"}' > package.json
  mkdir -p packages/aid-gui packages/aid-server "plugins/aid-orchestrator/.claude-plugin"
  echo '{"name":"aid-gui","version":"1.7.0"}' > packages/aid-gui/package.json
  echo '{"name":"aid-server","version":"1.7.0"}' > packages/aid-server/package.json
  echo '{"name":"aid-orchestrator","version":"1.7.0"}' > "plugins/aid-orchestrator/.claude-plugin/plugin.json"

  # Create CHANGELOG.md
  echo -e "# Changelog\n\n## [1.7.0] — 2026-02-28\n\n### Changed\n- Previous release" > CHANGELOG.md

  git add -A
  git commit -m "initial" -q
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# --- dry-run ---

@test "dry-run outputs new version without changing files" {
  cd "$TEST_DIR"
  run "$RELEASE" patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.7.0 → 1.7.1" ]]
  [[ "$output" =~ "[DRY RUN]" ]]
  # No file changes
  run jq -r .version package.json
  [ "$output" = "1.7.0" ]
}

@test "dry-run minor outputs correct version" {
  cd "$TEST_DIR"
  run "$RELEASE" minor --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.7.0 → 1.8.0" ]]
}

@test "dry-run major outputs correct version" {
  cd "$TEST_DIR"
  run "$RELEASE" major --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "1.7.0 → 2.0.0" ]]
}

# --- invalid input ---

@test "invalid bump type exits 1" {
  cd "$TEST_DIR"
  run "$RELEASE" invalid
  [ "$status" -eq 1 ]
  [[ "$output" =~ "ERROR" ]]
}

@test "missing package.json exits 1" {
  cd /tmp
  run "$RELEASE" patch --dry-run
  [ "$status" -eq 1 ]
}

# --- real bump (no git push) ---

@test "patch bump updates version in package.json" {
  cd "$TEST_DIR"
  run "$RELEASE" patch
  [ "$status" -eq 0 ]
  run jq -r .version package.json
  [ "$output" = "1.7.1" ]
}

@test "patch bump updates all version files" {
  cd "$TEST_DIR"
  "$RELEASE" patch
  run jq -r .version packages/aid-gui/package.json
  [ "$output" = "1.7.1" ]
  run jq -r .version packages/aid-server/package.json
  [ "$output" = "1.7.1" ]
  run jq -r .version plugins/aid-orchestrator/.claude-plugin/plugin.json
  [ "$output" = "1.7.1" ]
}

@test "patch bump creates git commit" {
  cd "$TEST_DIR"
  "$RELEASE" patch
  run git log --oneline -1
  # aid-release.sh commits as "release: vX.Y.Z — <last feat>" (line 376).
  [[ "$output" =~ "release: v1.7.1" ]]
}

@test "patch bump creates annotated git tag" {
  cd "$TEST_DIR"
  "$RELEASE" patch
  run git tag -l "v1.7.1"
  [ "$output" = "v1.7.1" ]
}

@test "patch bump prepends version section to CHANGELOG.md" {
  cd "$TEST_DIR"
  "$RELEASE" patch
  run head -1 CHANGELOG.md
  [ "$output" = "# Changelog" ]
  run grep "## \[1.7.1\]" CHANGELOG.md
  [ "$status" -eq 0 ]
}
