#!/usr/bin/env bats
# test-release-detection.bats — P073 Step 2: fail-loud optional probes in
# aid-release.sh.
#
# aid-release.sh runs under `set -euo pipefail`. Three version-detection
# probes were bare `VAR=$(grep ... | head -1)` pipelines, so a grep that
# simply found nothing returned 1 and killed the script BEFORE its own
# explicit three-way header handling or its "Cannot detect version"
# diagnostic could run. The operator saw a silent abort instead of an
# actionable message.
#
# Each test below drives one of the three no-match cases and asserts the run
# reaches the script's OWN diagnostic path rather than dying at the probe.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  RELEASE="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/aid-release.sh"
  export RELEASE
}

teardown() {
  teardown_test_evidence_dir
}

# _init_fixture_repo — a committed git repo, since aid-release.sh resolves
# REPO_ROOT via `git rev-parse --show-toplevel`.
_init_fixture_repo() {
  ( cd "$TEST_PROJECT_ROOT" \
      && git init -q \
      && git config user.email "t@example.com" \
      && git config user.name "T" \
      && git add -A \
      && git commit -qm "init" )
}

@test "P073 Step 2: no CHANGELOG version header + a plugin.json version — detection succeeds via the JSON source instead of aborting at the probe" {
  mkdir -p "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin"
  # A CHANGELOG that is a landing page: no `## [X.Y.Z]` ledger at all, so the
  # header probe finds nothing.
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'EOF'
# Changelog

Release notes live in the GitHub Releases page for this project.
EOF
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<'EOF'
{"version": "2.70.3"}
EOF
  _init_fixture_repo

  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Version source: plugin.json (2.70.3)"* ]]
  [[ "$output" == *"2.70.3"*"2.70.4"* ]]
}

@test "P073 Step 2: no version source anywhere exits non-zero with the explicit 'Cannot detect version' diagnostic, not a silent abort" {
  # No CHANGELOG, no plugin.json/marketplace.json/package.json, no pyproject.
  printf 'placeholder\n' > "$TEST_PROJECT_ROOT/README.md"
  _init_fixture_repo

  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot detect version"* ]]
}

@test "P073 Step 2: a pyproject.toml WITHOUT a top-level version line falls through to the diagnostic instead of aborting at the pyproject probe" {
  # This is the probe that used to kill the run: the file exists (so the
  # branch is entered) but the grep matches nothing.
  cat > "$TEST_PROJECT_ROOT/pyproject.toml" <<'EOF'
[tool.poetry]
name = "fixture"
description = "no top-level version = \"X.Y.Z\" line here"
EOF
  _init_fixture_repo

  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch --dry-run
  [ "$status" -ne 0 ]
  # Proof it reached the script's OWN diagnostic (lines 225-228) rather than
  # dying at the probe with no output at all.
  [[ "$output" == *"Cannot detect version"* ]]
}

@test "P073 Step 2: a CHANGELOG with no version header still reaches update_changelog's prepend branch (the third probe)" {
  # VERSION_SOURCE is plugin.json here, so update_changelog runs over BOTH
  # CHANGELOGs; the one without a header exercises the third probe.
  mkdir -p "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin"
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'EOF'
# Changelog

Format follows Keep a Changelog.
EOF
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<'EOF'
{"version": "2.70.3"}
EOF
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<'EOF'
versioning:
  source: CHANGELOG.md
  files:
    - path: plugins/aid-orchestrator/.claude-plugin/plugin.json
      type: json
      field: version
EOF
  _init_fixture_repo

  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  # The headerless CHANGELOG got a prepended entry rather than aborting.
  run grep -c '## \[2.70.4\]' "$TEST_PROJECT_ROOT/CHANGELOG.md"
  [ "$output" -ge 1 ]
}
