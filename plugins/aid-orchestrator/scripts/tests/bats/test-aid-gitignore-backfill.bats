#!/usr/bin/env bats
# aid-tier: t0
# test-aid-gitignore-backfill.bats — aid-gitignore-backfill.sh, the per-line
# gitignore backfill substrate /aid-init sources inline (commands/aid-init.md).
#
# Unit tests for gitignore_exclude_has_entry / gitignore_exclude_append —
# generic over WHICH file they operate on, exercised against BOTH a
# plain-`.gitignore`-style fixture and a `.git/info/exclude`-style fixture
# (same two functions, different target paths — no duplicated logic anywhere).
# The end-to-end case that drove the gate runner's one-time exclude bootstrap
# left with that bootstrap (P097 Step 5: no script sources this library at
# run time any more).
#
# Covers:
#   Edge case 2 — hand-edited unrelated lines -> only appended at EOF, never
#                 reordered/rewritten.
#   Edge case 3 — running the backfill a second time -> idempotent no-op.
#   Edge case 5 — .git/info/exclude doesn't exist yet -> created on demand.

load test-helpers.bash

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export PLUGIN_ROOT
  LIB="$PLUGIN_ROOT/scripts/lib/aid-gitignore-backfill.sh"
  export LIB
  WORK="$(mktemp -d)"
  export WORK
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"
}

# ─── Unit tests: gitignore_exclude_has_entry ────────────────────────────────

@test "has_entry: file does not exist -> false" {
  run gitignore_exclude_has_entry "$WORK/does-not-exist" ".aid-o/metrics/"
  [ "$status" -ne 0 ]
}

@test "has_entry (.gitignore-style fixture): entry present -> true" {
  local f="$WORK/.gitignore"
  printf 'node_modules/\n.aid-o/metrics/\ndist/\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -eq 0 ]
}

@test "has_entry (.gitignore-style fixture): entry absent among unrelated lines -> false" {
  local f="$WORK/.gitignore"
  printf 'node_modules/\ndist/\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -ne 0 ]
}

@test "has_entry (.git/info/exclude-style fixture): entry present -> true" {
  local f="$WORK/exclude"
  printf '# git ls-files --others --exclude-from=.git/info/exclude\n.aid-o/metrics/*.lock\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/*.lock"
  [ "$status" -eq 0 ]
}

@test "has_entry: exact-line match only — a substring/prefix does NOT count as present" {
  local f="$WORK/.gitignore"
  printf '.aid-o/metrics/extra-suffix\n' > "$f"
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -ne 0 ]
}

# ─── Unit tests: gitignore_exclude_append ───────────────────────────────────

@test "append (.gitignore-style): file absent -> created with parent dir, entry written" {
  local f="$WORK/nested/dir/.gitignore"
  [ ! -e "$f" ]
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  [ -f "$f" ]
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -eq 0 ]
}

@test "append (.git/info/exclude-style): file absent -> created on demand (edge case 5)" {
  local f="$WORK/git-info/exclude"
  [ ! -e "$f" ]
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  gitignore_exclude_append "$f" ".aid-o/metrics/*.lock"
  [ -f "$f" ]
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/"
  [ "$status" -eq 0 ]
  run gitignore_exclude_has_entry "$f" ".aid-o/metrics/*.lock"
  [ "$status" -eq 0 ]
}

@test "append: hand-edited unrelated lines are preserved, entry only appended at EOF (edge case 2)" {
  local f="$WORK/.gitignore"
  printf '# hand-written header\nnode_modules/\n*.log\n' > "$f"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  # Original lines untouched, in original order.
  [ "$(sed -n '1p' "$f")" = "# hand-written header" ]
  [ "$(sed -n '2p' "$f")" = "node_modules/" ]
  [ "$(sed -n '3p' "$f")" = "*.log" ]
  # New entry appended at EOF, exactly once.
  [ "$(sed -n '4p' "$f")" = ".aid-o/metrics/" ]
  [ "$(wc -l < "$f")" -eq 4 ]
}

@test "append: running twice is idempotent — no duplicate line (edge case 3)" {
  local f="$WORK/.git-info-exclude"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  local count
  count=$(grep -cxF ".aid-o/metrics/" "$f")
  [ "$count" -eq 1 ]
}

@test "append: two different entries against the same file both land, in call order" {
  local f="$WORK/.gitignore"
  gitignore_exclude_append "$f" ".aid-o/metrics/"
  gitignore_exclude_append "$f" ".aid-o/metrics/*.lock"
  [ "$(sed -n '1p' "$f")" = ".aid-o/metrics/" ]
  [ "$(sed -n '2p' "$f")" = ".aid-o/metrics/*.lock" ]
}

