#!/usr/bin/env bats
# aid-tier: t1
# P083 Step 4 — a configured regex version pattern that matches nothing must
# be reported by name and never printed (or counted) as `Updated`. Also pins,
# on tracked fixtures, the empirical behavior of the three pattern-escaping
# styles discussed in this plan: bare parentheses (correct), backslash-
# escaped (the shipped, still-broken config form — a MISS, not a corruption),
# and bracket-expression (revision 1's rejected fix — corrupts the line).

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  RELEASE="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/aid-release.sh"
  export RELEASE
}

teardown() {
  teardown_test_evidence_dir
}

# _seed <pattern> — a repo whose version source is plugin.json, with a
# README.md tracked-fixture line and a versioning.files[] regex entry using
# the given pattern (with a literal {VERSION} placeholder).
_seed() {
  local pattern="$1"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" \
           "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin"
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<'EOF'
{"version": "2.83.1"}
EOF
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.83.1] — 2026-08-01

### Added
- The base entry.
EOF
  printf '[Claude Code](https://example.com/foo) — v2.83.1\n' > "$TEST_PROJECT_ROOT/README.md"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<EOF
versioning:
  source: plugins/aid-orchestrator/.claude-plugin/plugin.json
  files:
    - path: plugins/aid-orchestrator/.claude-plugin/plugin.json
      type: json
      field: version
    - path: README.md
      type: regex
      pattern: '${pattern}'
EOF
  ( cd "$TEST_PROJECT_ROOT" \
      && git init -q \
      && git config user.email "t@example.com" \
      && git config user.name "T" \
      && git add -A \
      && git commit -qm "init" )
}

# _write_target_entry <version> — prepends a real (non-placeholder) section
# for <version> ABOVE the existing content, so _release_probe_first's
# first-match-wins scan finds it as the newest header (CHANGELOG convention:
# newest on top).
_write_target_entry() {
  local version="$1"
  local tmp; tmp="$(mktemp)"
  {
    head -3 "$TEST_PROJECT_ROOT/CHANGELOG.md"
    echo ""
    echo "## [${version}] — 2026-08-13"
    echo ""
    echo "### Fixed"
    echo "- **A real entry for ${version}** — not a placeholder."
    tail -n +4 "$TEST_PROJECT_ROOT/CHANGELOG.md"
  } > "$tmp" && mv "$tmp" "$TEST_PROJECT_ROOT/CHANGELOG.md"
}

@test "a pattern matching neither version is reported as MISS, never as Updated" {
  _seed '\[Claude Code\](https://nowhere.example/wrong) — v{VERSION}'
  _write_target_entry 2.83.2
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISS: README.md (regex)"* ]]
  [[ "$output" == *"configured pattern matched neither the current nor the new version"* ]]
  [[ "$output" != *"Updated: README.md (regex)"* ]]
  # README.md untouched; not staged as part of the release.
  [ "$(cat README.md)" = "[Claude Code](https://example.com/foo) — v2.83.1" ]
}

@test "bare-parenthesis pattern substitutes across two consecutive releases with the link intact" {
  _seed '\[Claude Code\](https://example.com/foo) — v{VERSION}'
  _write_target_entry 2.83.2
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated: README.md (regex)"* ]]
  [ "$(cat README.md)" = "[Claude Code](https://example.com/foo) — v2.83.2" ]

  # Second consecutive release: 2.83.2 → 2.83.3.
  _write_target_entry 2.83.3
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated: README.md (regex)"* ]]
  [ "$(cat README.md)" = "[Claude Code](https://example.com/foo) — v2.83.3" ]
}

@test "backslash-escaped parenthesis pattern (shipped config form) MISSES, does not corrupt" {
  _seed '\[Claude Code\]\(https://example.com/foo\) — v{VERSION}'
  _write_target_entry 2.83.2
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"MISS: README.md (regex)"* ]]
  # Unchanged, markdown link intact — a miss, not a corruption.
  [ "$(cat README.md)" = "[Claude Code](https://example.com/foo) — v2.83.1" ]
}

@test "bracket-expression pattern (rejected fix) corrupts the markdown link" {
  _seed '\[Claude Code\][(]https://example.com/foo[)] — v{VERSION}'
  _write_target_entry 2.83.2
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated: README.md (regex)"* ]]
  # Corrupted: the replacement side is literal text, so [(] / [)] survive
  # verbatim instead of being interpreted as "match a literal paren".
  [ "$(cat README.md)" = "[Claude Code][(]https://example.com/foo[)] — v2.83.2" ]
}

@test "suite runs entirely on tracked fixtures — no assertion depends on this working copy" {
  # Sanity: the fixture repo built by _seed is self-contained under
  # TEST_PROJECT_ROOT and does not read the real repository's
  # .aid-o/config/project.yaml or README.md.
  _seed '\[Claude Code\](https://example.com/foo) — v{VERSION}'
  [ -f "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" ]
  [ -f "$TEST_PROJECT_ROOT/README.md" ]
  run grep -c "example.com/foo" "$TEST_PROJECT_ROOT/README.md"
  [ "$output" = "1" ]
}

@test "a row already at the new version is reported 'already current', never as Updated or a miss" {
  _seed '\[Claude Code\](https://example.com/foo) — v{VERSION}'
  _write_target_entry 2.83.2
  cd "$TEST_PROJECT_ROOT"
  # README already carries the NEW version's text before this run — simulates
  # a row someone hand-fixed, or a rerun after a prior successful bump.
  printf '[Claude Code](https://example.com/foo) — v2.83.2\n' > README.md
  git add README.md && git commit -qm "pre-bump README already current"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already current: README.md (regex)"* ]]
  [[ "$output" != *"Updated: README.md (regex)"* ]]
  [[ "$output" != *"MISS: README.md"* ]]
  [ "$(cat README.md)" = "[Claude Code](https://example.com/foo) — v2.83.2" ]
}
