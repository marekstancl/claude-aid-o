#!/usr/bin/env bats
# aid-tier: t2
# test-aid-release-seal.bats — P079 Step 10 (IMP-482): a released version's
# CHANGELOG heading is immutable.
#
# THE MECHANISM UNDER TEST: both CHANGELOG retitle sites in aid-release.sh are
# a blind `sed 's/## \[$CURRENT\].*/## [$NEW_VERSION]/'`. On a version that
# never shipped that is a correction. On one that DID ship it is a rename: the
# new release inherits the old entry's content and the old release's history
# disappears under a version number it does not describe. The v2.80.0 heading
# in this repository is hand-set with a comment about exactly that hazard.
#
# A git tag is the repository's own record that a version was published, so the
# seal keys on it: tagged means append, never rewrite.
#
# The tagged and untagged cases are asserted as a PAIR — the untagged retitle
# still happening is what proves the seal is the tag, not a blanket disabling.
#
# FD-3 HYGIENE: every release invocation runs with `3>&-`. After any edit:
#   bats --tap test-aid-release-seal.bats | grep -cE '^(ok|not ok)'   # == 6

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  RELEASE="$AID_PLUGIN_PATH/scripts/aid-release.sh"
  export RELEASE
  TEST_TMPDIR="$(mktemp -d)"
  REPO="$TEST_TMPDIR/repo"
  export TEST_TMPDIR REPO
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

RELEASED_LINE='- **A shipped feature** — the sentence that belongs to 1.0.0 and to no other version'

# _changelog <path> <version>
_changelog() {
  cat > "$1" <<EOF
# Changelog

All notable changes are documented here.
Format follows Keep a Changelog.

## [${2}] — 2026-08-01

### Added
${RELEASED_LINE}
EOF
}

# _mk_repo <version> [--tagged]
_mk_repo() {
  local ver="$1" tagged="${2:-}"
  mkdir -p "$REPO"
  _changelog "$REPO/CHANGELOG.md" "$ver"
  aid_test_mk_repo "$REPO"
  if [[ "$tagged" == "--tagged" ]]; then git -C "$REPO" tag "v${ver}"; fi
  return 0
}

_release() { bash -c "cd '$REPO' && exec bash '$RELEASE' patch" 3>&-; }

# ─── the seal, and the correction case it must not swallow ─────────────────

@test "P079 Step 10: a TAGGED version's heading is preserved and a new entry is prepended instead" {
  _mk_repo 1.0.0 --tagged

  run _release
  [[ "$output" == *"Sealed: v1.0.0 is tagged"* ]]

  # The released entry still says what it said, under the number it shipped as.
  grep -q '^## \[1\.0\.0\] — 2026-08-01$' "$REPO/CHANGELOG.md"
  grep -qF -- "$RELEASED_LINE" "$REPO/CHANGELOG.md"
  # Nothing was published under a number whose entry was never written: the
  # P073 completeness gate refuses the placeholder and rolls the run back.
  [ -z "$(git -C "$REPO" tag -l v1.0.1)" ]
}

@test "P079 Step 10: an UNTAGGED current version still retitles — the seal is the tag, not a blanket stop" {
  _mk_repo 1.0.0

  run _release
  [[ "$output" == *"header 1.0.0 → 1.0.1"* ]]
  [[ "$output" != *"Sealed"* ]]
  grep -q '^## \[1\.0\.1\]' "$REPO/CHANGELOG.md"
  ! grep -q '^## \[1\.0\.0\]' "$REPO/CHANGELOG.md"
}

@test "P079 Step 10: the no-config fallback seals SECONDARY changelogs the same way" {
  _mk_repo 1.0.0 --tagged
  mkdir -p "$REPO/plugins/x"
  _changelog "$REPO/plugins/x/CHANGELOG.md" 1.0.0
  ( cd "$REPO" && git add -A && git commit -q -m "second changelog" )

  run _release
  # It gets the SAME treatment as the primary CHANGELOG — heading preserved and
  # a new entry prepended — not merely skipped, which would leave a canonical
  # changelog behind at the old version while the release moved on. (Both are
  # then rolled back by the P073 completeness gate, as the primary one is.)
  [[ "$output" == *"$REPO/plugins/x/CHANGELOG.md keeps its heading; prepended a new 1.0.1 entry"* ]]
  grep -q '^## \[1\.0\.0\] — 2026-08-01$' "$REPO/plugins/x/CHANGELOG.md"
  grep -qF -- "$RELEASED_LINE" "$REPO/plugins/x/CHANGELOG.md"
}

@test "P079 Step 10: an untagged SECONDARY changelog is still retitled by the fallback" {
  _mk_repo 1.0.0
  mkdir -p "$REPO/plugins/x"
  _changelog "$REPO/plugins/x/CHANGELOG.md" 1.0.0
  ( cd "$REPO" && git add -A && git commit -q -m "second changelog" )

  run _release
  grep -q '^## \[1\.0\.1\]' "$REPO/plugins/x/CHANGELOG.md"
}

@test "P079 Step 10: a heading already at the NEW version is a no-op (the P076 hand-set case)" {
  _mk_repo 1.0.1 --tagged
  # CURRENT is read from the CHANGELOG, so a hand-set 1.0.1 makes CURRENT=1.0.1
  # and the bump target 1.0.2 — the seal branch is never reached, and the
  # entry's own content is what gets released.

  run _release
  grep -q '^## \[1\.0\.1\] — 2026-08-01$' "$REPO/CHANGELOG.md"
  grep -qF -- "$RELEASED_LINE" "$REPO/CHANGELOG.md"
}

# ─── the identity assertion that was assumed to exist ──────────────────────

@test "P079 Step 10: verify-version-files.sh FAILS when the two CHANGELOG sections differ" {
  local vv="$AID_PLUGIN_PATH/scripts/tests/verify-version-files.sh"
  mkdir -p "$REPO/plugins/aid-orchestrator"
  printf '# Changelog\n\nx\ny\n\n## [9.9.9] — 2026-08-10\n\n### Added\n- **Root wording** — one sentence\n' \
    > "$REPO/CHANGELOG.md"
  printf '# Changelog\n\nx\ny\n\n## [9.9.9] — 2026-08-10\n\n### Added\n- **Plugin wording** — a DIFFERENT sentence\n' \
    > "$REPO/plugins/aid-orchestrator/CHANGELOG.md"

  run bash -c "cd '$REPO' && exec bash '$vv' 9.9.9" 3>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"sections of CHANGELOG.md"* ]]

  # Make them identical: that specific failure goes away.
  cp "$REPO/CHANGELOG.md" "$REPO/plugins/aid-orchestrator/CHANGELOG.md"
  run bash -c "cd '$REPO' && exec bash '$vv' 9.9.9" 3>&-
  [[ "$output" == *"byte-identical"* ]]
}

# ─── P089 Step 9: the SCOPE decides the bump, not the commit subject ────────
#
# The duplicated label logic this file's subject used to carry lived at
# aid-release.sh:122-147 and could disagree with the pre-push hook over the same
# range: a push the hook let through would still be told here that it owed a
# bump. Both cases below drive `auto`, which is the only mode that resolves a
# bump type at all.

_scoped_repo() {
  _mk_repo 1.0.0 --tagged
  mkdir -p "$REPO/.aid-o/config" "$REPO/tests" "$REPO/src"
  cat > "$REPO/.aid-o/config/project.yaml" <<'YAML'
versioning:
  release_exempt_paths:
    - tests
  app_paths:
    - src
YAML
  printf '.aid-o/\n' >> "$REPO/.gitignore"
  printf 'seed\n' > "$REPO/tests/t.txt"
  printf 'seed\n' > "$REPO/src/app.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "chore: fixture paths"
  git -C "$REPO" tag -f v1.0.0 >/dev/null 2>&1
}

_release_auto() { bash -c "cd '$REPO' && exec bash '$RELEASE' auto" 3>&-; }

@test "AC27: an exempt fix: does not drive a bump" {
  _scoped_repo
  printf 'x\n' >> "$REPO/tests/t.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "fix(tests): flaky case"

  run _release_auto
  [ "$status" -eq 0 ]
  [[ "$output" == *"inside the release-exempt paths"* ]]
  [[ "$output" == *"no version bump needed"* ]]
  [ -z "$(git -C "$REPO" tag -l v1.0.1)" ]
}

@test "a feat: carrying a No-Release footer does not choose the bump type either" {
  _scoped_repo
  printf 'x\n' >> "$REPO/src/app.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "feat: regenerated fixture" -m "No-Release: fixture refresh, nothing ships"

  run _release_auto
  [ "$status" -eq 0 ]
  [[ "$output" == *"no version bump needed"* ]]
}

@test "AC25: aid-release.sh carries no second copy of the label rule" {
  # The old block decided HAS_FEAT/HAS_FIX/HAS_RELEASE for the RANGE, in
  # parallel with the hook. What remains is the bump-TYPE choice, which is a
  # different question and has only ever lived here.
  run grep -c 'HAS_RELEASE' "$AID_PLUGIN_PATH/scripts/aid-release.sh"
  [ "$output" = "0" ]
  # And it asks the library exactly once. Counted as a CALL, not as a string:
  # the prose around it names the function too.
  run grep -cE '^[[:space:]]*aid_release_scope_evaluate ' "$AID_PLUGIN_PATH/scripts/aid-release.sh"
  [ "$output" = "1" ]
}
