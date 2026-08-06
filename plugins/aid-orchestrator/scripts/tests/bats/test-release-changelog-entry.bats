#!/usr/bin/env bats
# test-release-changelog-entry.bats — P073 Step 3: no release commit or
# plan-candidate preparation may succeed while the TARGET version's CHANGELOG
# section is missing, empty, or still the generated placeholder.
#
# `update_changelog` writes the literal line `- _PM/agent: fill in entry
# content_` whenever it prepends a new section, and nothing ever read it back
# — a release could be committed, tagged and published with that as its whole
# user-facing description. `cmd_prepare_plan` is the high-value hook because
# its commit becomes the frozen, reviewed candidate.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  RELEASE="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/aid-release.sh"
  export RELEASE
  PLACEHOLDER='- _PM/agent: fill in entry content_'
  export PLACEHOLDER
}

teardown() {
  teardown_test_evidence_dir
}

# _seed <released-version> <changelog-body-file-content>
# Builds a repo whose plugin.json is the version source, so CURRENT is
# deterministic and NEW_VERSION is a patch bump of it.
_seed() {
  local released="$1" changelog="$2"
  mkdir -p "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin" \
           "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/plugins/aid-orchestrator/.claude-plugin/plugin.json" <<EOF
{"version": "$released"}
EOF
  printf '%s' "$changelog" > "$TEST_PROJECT_ROOT/CHANGELOG.md"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<'EOF'
versioning:
  source: CHANGELOG.md
  files:
    - path: plugins/aid-orchestrator/.claude-plugin/plugin.json
      type: json
      field: version
EOF
  ( cd "$TEST_PROJECT_ROOT" \
      && git init -q \
      && git config user.email "t@example.com" \
      && git config user.name "T" \
      && git add -A \
      && git commit -qm "init" )
}

# A CHANGELOG whose TARGET (2.0.1) section is the generated placeholder.
_changelog_placeholder_target() {
  cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Changed

- _PM/agent: fill in entry content_

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
}

# Same, but the target section carries a real bullet.
_changelog_complete_target() {
  cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Fixed

- **Release Entry Validation** — a release can no longer ship a placeholder.

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
}

# Target complete, but an OLD section still carries the placeholder (debt).
_changelog_historical_placeholder() {
  cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Fixed

- **Release Entry Validation** — a release can no longer ship a placeholder.

## [2.0.0] — 2026-07-01

### Added

- _PM/agent: fill in entry content_
EOF
}

# ─── legacy path: aid-release.sh <patch|minor|major> ──────────────────────

@test "P073 Step 3: a placeholder in the TARGET section blocks the legacy release — no commit, no tag" {
  _seed "2.0.0" "$(_changelog_placeholder_target)"
  cd "$TEST_PROJECT_ROOT"
  local commits_before; commits_before="$(git rev-list --count HEAD)"

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"CHANGELOG.md"* ]]
  [[ "$output" == *"2.0.1"* ]]
  [[ "$output" == *"replace the placeholder"* ]]

  # No new commit and no tag were created.
  [ "$(git rev-list --count HEAD)" = "$commits_before" ]
  [ -z "$(git tag -l 'v2.0.1')" ]
}

@test "P073 Step 3: a completed TARGET section releases normally" {
  _seed "2.0.0" "$(_changelog_complete_target)"
  cd "$TEST_PROJECT_ROOT"
  local commits_before; commits_before="$(git rev-list --count HEAD)"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [ "$(git rev-list --count HEAD)" -gt "$commits_before" ]
  [ -n "$(git tag -l 'v2.0.1')" ]
}

@test "P073 Step 3: a placeholder in an OLD section is debt — warned on stderr, never blocking" {
  _seed "2.0.0" "$(_changelog_historical_placeholder)"
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  [[ "$output" == *"historical placeholder"* ]]
  [[ "$output" == *"2.0.0"* ]]
  [[ "$output" != *"PRECONDITION FAIL"* ]]
}

@test "P073 Step 3: a TARGET section with only a heading and no bullet is blocked" {
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Changed

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"the section has no content"* ]]
}

@test "P073 Step 3: a CHANGELOG whose headings this script cannot locate is blocked, naming the expected form (never a silent pass)" {
  # The version source is plugin.json, so detection succeeds; the CHANGELOG
  # itself uses a non-standard heading, so update_changelog PREPENDS a
  # standard `## [2.0.1]` section — which is then the placeholder case. To
  # isolate "target section unlocatable" we hand the checker a file whose
  # target section really is absent after the update: an unwritable CHANGELOG
  # is not it, so instead assert the checker directly.
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Version 2.0.0 (2026-07-01)
--------------------------
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  # Source the script's function without running its dispatcher.
  run bash -c "
    UPDATED=()
    source_only() { :; }
    # shellcheck disable=SC1090
    . <(sed -n '/^_RELEASE_CHANGELOG_PLACEHOLDER=/,/^# ─── Git commit + tag/p' '$RELEASE')
    _release_validate_changelog_entry '$TEST_PROJECT_ROOT/CHANGELOG.md' '2.0.1'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"## [2.0.1]"* ]]
  [[ "$output" == *"exact heading form"* ]]
}

# ─── prepare-plan path (the frozen, reviewed candidate) ───────────────────

@test "P073 Step 3: prepare-plan refuses a placeholder entry and stages nothing" {
  _seed "2.0.0" "$(_changelog_placeholder_target)"
  cd "$TEST_PROJECT_ROOT"
  git checkout -q -b plan/P900
  local commits_before; commits_before="$(git rev-list --count HEAD)"

  run bash "$RELEASE" prepare-plan P900 --bump patch --plan-branch plan/P900 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PRECONDITION FAIL"* ]]
  [[ "$output" == *"nothing was staged or committed"* ]]

  # Proof: no prepare commit, and nothing left in the index.
  [ "$(git rev-list --count HEAD)" = "$commits_before" ]
  [ -z "$(git diff --cached --name-only)" ]
}

@test "P073 Step 3: prepare-plan proceeds when the target entry is real" {
  _seed "2.0.0" "$(_changelog_complete_target)"
  cd "$TEST_PROJECT_ROOT"
  git checkout -q -b plan/P900
  local commits_before; commits_before="$(git rev-list --count HEAD)"

  run bash "$RELEASE" prepare-plan P900 --bump patch --plan-branch plan/P900 --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(git rev-list --count HEAD)" -gt "$commits_before" ]
  # prepare-plan never tags.
  [ -z "$(git tag -l 'v2.0.1')" ]
}

@test "P073 Step 3: the placeholder wording quoted inside a real bullet does not block (exact-line match only)" {
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Added

- **Release Entry Validation** — blocks a section still containing `- _PM/agent: fill in entry content_`.

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
}

# ─── Codex-review finding on the first cut of this step ────────────────────
# The adversarial review found the original `^- [^_[:space:]]` bullet test
# rejected legitimate Markdown: a nested list, a table, or a bullet whose
# first word is italic. A false refusal is exactly what this plan's loosening
# directive forbids, so the check is now format-agnostic — any non-blank,
# non-heading line is content.

@test "P073 Step 3 (review finding): a section whose content is a NESTED list is legitimate and releases" {
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Fixed

  - Nested bullet describing the fix.

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
}

@test "P073 Step 3 (review finding): a section whose content is a TABLE is legitimate and releases" {
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Changed

| Component | Effect |
|-----------|--------|
| Releases  | Entry validation added. |

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
}

@test "P073 Step 3 (review finding): a bullet whose first word is italic is legitimate and releases" {
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Changed

- _Breaking_: the release path now validates its own CHANGELOG entry.

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
}

@test "P073 Step 3 (review finding): a heading-only section is STILL blocked — the loosening did not open a hole" {
  _seed "2.0.0" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.0.1] — 2026-08-04

### Changed

#### Sub-heading with nothing under it

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"the section has no content"* ]]
}

# ─── Whole-EPIC review finding: the refusal must be rerunnable ─────────────
# Step 3's gate refuses AFTER _release_update_files has already rewritten the
# version files, and this script derives CURRENT from those very files. The
# refusal therefore used to leave a half-applied bump: the operator wrote the
# 2.0.1 entry the message asked for, reran, and the tool released 2.0.2 —
# silently orphaning the entry they had just written. Measured on a fixture.

# _seed_prepend <released> — a CHANGELOG with a PRE-WRITTEN newer header, which
# is the only shape that drives update_changelog's placeholder-generating
# prepend branch (the rename branch reuses real content and never trips the
# gate).
_seed_prepend() {
  _seed "$1" "$(cat <<'EOF'
# Changelog

Format follows Keep a Changelog.

## [2.2.0] — 2026-09-01

### Added
- A pre-written entry for a future release.

## [2.0.0] — 2026-07-01

### Added
- The first real release.
EOF
)"
}

@test "P073 EPIC 1 (review finding): a refused release rolls back its own version-file edits" {
  _seed_prepend "2.0.0"
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rolled back this run's version-file edits"* ]]

  # The version source is back at the base, and the worktree is clean.
  [ "$(jq -r '.version' plugins/aid-orchestrator/.claude-plugin/plugin.json)" = "2.0.0" ]
  [ -z "$(git status --porcelain)" ]
  run grep -c '## \[2.0.1\]' CHANGELOG.md
  [ "$output" = "0" ]
}

@test "P073 EPIC 1 (review finding): the rerun after writing the entry releases THAT version, not the next one" {
  _seed_prepend "2.0.0"
  cd "$TEST_PROJECT_ROOT"

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]

  # The operator does exactly what the message asks: authors the 2.0.1 section.
  python3 - <<'PY'
import io
s = io.open('CHANGELOG.md', encoding='utf-8').read()
s = s.replace("Format follows Keep a Changelog.\n",
              "Format follows Keep a Changelog.\n\n## [2.0.1] — 2026-08-05\n\n### Fixed\n\n- **A real entry** — written by the operator after the refusal.\n")
io.open('CHANGELOG.md', 'w', encoding='utf-8').write(s)
PY
  run bash "$RELEASE" patch
  [ "$status" -eq 0 ]
  # 2.0.1 was released — NOT 2.0.2, and the operator's entry was not orphaned.
  [ "$(jq -r '.version' plugins/aid-orchestrator/.claude-plugin/plugin.json)" = "2.0.1" ]
  [ -n "$(git tag -l 'v2.0.1')" ]
  [ -z "$(git tag -l 'v2.0.2')" ]
  run grep -c 'written by the operator after the refusal' CHANGELOG.md
  [ "$output" = "1" ]
}

@test "P073 EPIC 1 (review finding): a file the operator had ALREADY edited is never rolled back" {
  _seed_prepend "2.0.0"
  cd "$TEST_PROJECT_ROOT"
  printf '{"version": "2.0.0", "operatorEdit": true}\n' > plugins/aid-orchestrator/.claude-plugin/plugin.json

  run bash "$RELEASE" patch
  [ "$status" -ne 0 ]
  # The pre-existing edit survives; only paths this run made dirty are reverted.
  run grep -c 'operatorEdit' plugins/aid-orchestrator/.claude-plugin/plugin.json
  [ "$output" = "1" ]
}
