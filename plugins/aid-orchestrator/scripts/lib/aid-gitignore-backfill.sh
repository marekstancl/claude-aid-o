#!/usr/bin/env bash
# =============================================================================
# aid-gitignore-backfill.sh — generic gitignore-style line helper.
#
# WHY THIS FILE EXISTS: /aid-init backfills a consumer project's tracked
# `.gitignore` per line (commands/aid-init.md, "Base manifest") — append an
# entry only when its exact line is absent, never reorder or rewrite what a
# person wrote. That logic lives here once; the command sources this file
# inline. No script sources it at run time (P097 Step 5 removed the gate
# runner's one-time `.git/info/exclude` bootstrap along with the runtime
# baseline it existed for).
#
# ── GENERIC OVER WHICH FILE ──────────────────────────────────────────────────
# This file has NO knowledge of any particular entry or target — it operates
# on any "one gitignore-pattern-per-line" file at an arbitrary path. Its bats
# suite (test-aid-gitignore-backfill.bats) exercises the same two functions
# against a plain `.gitignore`-style fixture and a `.git/info/exclude`-style
# one — there is exactly one place this append-only-at-EOF, never-reorder
# logic lives, not two copies that could drift.
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` (matches
# aid-cache-preflight.sh): a caller may source this under its own strict
# shell. Every function below returns 0 even when the underlying mkdir/append
# fails (fail open, warn to stderr).
#
# ── USAGE ─────────────────────────────────────────────────────────────────
#   source .../lib/aid-gitignore-backfill.sh
#   gitignore_exclude_has_entry ".gitignore" ".aid-o/work/"
#   gitignore_exclude_append   ".gitignore" ".aid-o/work/"
# =============================================================================

# gitignore_exclude_has_entry <path> <entry>
#   Returns 0 (true) iff <entry> already exists as an EXACT line in the file
#   at <path> (grep -qxF — literal string match, never a glob/regex
#   interpretation of <entry>). Returns 1 if the file doesn't exist yet, or
#   the entry simply isn't present. Never writes anything.
gitignore_exclude_has_entry() {
  local path="$1" entry="$2"
  [[ -f "$path" ]] || return 1
  grep -qxF -- "$entry" "$path" 2>/dev/null
}

# gitignore_exclude_append <path> <entry>
#   Appends <entry> as a new line at EOF of the file at <path> — ONLY if
#   gitignore_exclude_has_entry says it's absent (idempotent: a second call
#   with the same args is a no-op, never a duplicate line). Creates <path>
#   (and any missing parent directory) on demand — a plain file, not a
#   special git object, so this works identically for `.gitignore` and
#   `.git/info/exclude`. NEVER reorders, rewrites, or truncates any existing
#   line — pure append, or nothing. Always returns 0 (fails open): the
#   (rare) mkdir/write failure is warned to stderr, never propagated as a
#   hard error to the caller's gate run.
gitignore_exclude_append() {
  local path="$1" entry="$2"

  if gitignore_exclude_has_entry "$path" "$entry"; then
    return 0
  fi

  local dir
  dir="$(dirname -- "$path")"
  if [[ -n "$dir" && "$dir" != "." && ! -d "$dir" ]]; then
    mkdir -p -- "$dir" 2>/dev/null || {
      echo "WARN: aid-gitignore-backfill.sh: could not create directory '$dir' for '$path' — skipping append of '$entry'" >&2
      return 0
    }
  fi

  printf '%s\n' "$entry" >> "$path" 2>/dev/null || {
    echo "WARN: aid-gitignore-backfill.sh: could not append '$entry' to '$path'" >&2
    return 0
  }
  return 0
}
