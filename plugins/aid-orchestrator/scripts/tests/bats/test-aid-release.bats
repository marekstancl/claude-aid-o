#!/usr/bin/env bats
# aid-release.sh — IMP-093 fix: CHANGELOG header detection + prepend logic.
# Verifies the script does not silently collapse a pre-written CHANGELOG entry
# when bumping the version (3x-observed bug across v2.18.3 + v2.19.0 releases).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  RELEASE="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/aid-release.sh"
  export RELEASE
}

teardown() {
  teardown_test_evidence_dir
}

# Build a minimal repo fixture (project.yaml versioning + plugin.json + CHANGELOG.md)
seed_release_fixture() {
  local released="$1"            # version in plugin.json (= last released)
  local changelog_header="$2"    # version in newest CHANGELOG header
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" \
           "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin"
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<EOF
{"version": "$released"}
EOF
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<EOF
# Changelog

Format follows Keep a Changelog.

## [$changelog_header] — 2026-05-10

### Added
- Test fixture entry for $changelog_header.
EOF
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<EOF
versioning:
  source: CHANGELOG.md
  files:
    - path: plugins/aid-orchestrator/.claude-plugin/plugin.json
      type: json
      field: version
EOF
  ( cd "$TEST_PROJECT_ROOT" && git init -q && git add -A && git commit -qm "init" )
}

@test "aid-release: header == released → bump existing CHANGELOG header (existing behavior)" {
  seed_release_fixture "2.19.0" "2.19.0"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  # Header should be bumped 2.19.0 → 2.19.1 (sed-replace path)
  local header
  header=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$TEST_PROJECT_ROOT/CHANGELOG.md" | head -1)
  [ "$header" = "2.19.1" ]
  # No "prepended" message
  ! [[ "$output" =~ "prepended" ]]
}

@test "aid-release: pre-written newer header → prepend new entry (does NOT rename pre-written)" {
  # Released 2.19.0, but PM/agent pre-wrote ## [2.20.0] — script must not rename it.
  seed_release_fixture "2.19.0" "2.20.0"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  # P073 interaction: the prepend path writes the generated placeholder as the
  # new section's only bullet, so the release is now REFUSED on exactly that
  # (an unfilled entry must never reach a commit or a tag) and the whole run's
  # edits are rolled back so a rerun bumps from the same base. What this test
  # is about — that the prepend branch ran and did NOT rename the pre-written
  # entry — is asserted from the script's own report plus the untouched
  # pre-written section.
  [ "$status" -ne 0 ]
  [[ "$output" == *"replace the placeholder"* ]]
  [[ "$output" == *"prepended new 2.19.1 entry"* ]]
  [[ "$output" == *"Rolled back this run's version-file edits"* ]]
  # The pre-written [2.20.0] entry was never renamed, and no 2.19.1 section
  # was left behind by the rolled-back run.
  grep -q '^## \[2.20.0\] — ' "$TEST_PROJECT_ROOT/CHANGELOG.md"
  ! grep -q '^## \[2.19.1\]' "$TEST_PROJECT_ROOT/CHANGELOG.md"
}

@test "aid-release: header == new_version (already pre-written for upcoming) → skip rename, no-op" {
  # Released 2.19.0, PM pre-wrote ## [2.19.1] — script bumps to 2.19.1 and finds header matches: skip rename.
  seed_release_fixture "2.19.0" "2.19.1"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  # Header stays at 2.19.1 (not double-bumped to 2.19.2)
  local header
  header=$(grep -oP '## \[\K[0-9]+\.[0-9]+\.[0-9]+' "$TEST_PROJECT_ROOT/CHANGELOG.md" | head -1)
  [ "$header" = "2.19.1" ]
  # No 2.19.2 entry
  ! grep -q '^## \[2.19.2\]' "$TEST_PROJECT_ROOT/CHANGELOG.md"
  # Skipped message
  [[ "$output" == *"already"* ]] || [[ "$output" == *"Skipped"* ]]
}
