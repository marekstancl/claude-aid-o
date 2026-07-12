#!/usr/bin/env bash
# =============================================================================
# aid-gitignore-backfill.sh — generic gitignore-style line helper (P063 EPIC
# "Gate Runtime Baselines", Step 2/4).
#
# WHY: aid-run-gates.sh must never let `.aid-o/metrics/` dirty an
# already-initialized existing project's git tree. Brand-new projects get
# `.aid-o/metrics/` for free via the shipped `defaults/.gitignore` (copied by
# /aid-init into the project's tracked `.gitignore`). Already-initialized
# projects need a LOCAL-ONLY, lazy, automatic backfill into
# `.git/info/exclude` (per-clone, never committed, needs no manual re-init)
# — see `aid-gate-runtime-baseline.sh`'s `gate_baseline_ensure_gitignored`,
# the sole production caller of the functions in this file.
#
# ── GENERIC OVER WHICH FILE ──────────────────────────────────────────────────
# This file has NO knowledge of `.aid-o/metrics/` or `.git/info/exclude`
# specifically — it operates on any "one gitignore-pattern-per-line" file at
# an arbitrary path. The runtime caller targets `.git/info/exclude`; this
# file's own bats suite (test-aid-gitignore-backfill.bats) exercises the
# exact same two functions against a plain `.gitignore`-style fixture too —
# there is exactly one place this append-only-at-EOF, never-reorder logic
# lives, not two copies that could drift.
#
# ── SOURCEABLE-SAFE CONVENTION ───────────────────────────────────────────────
# NO top-level `set -e`/`set -euo pipefail` (matches
# aid-gate-runtime-baseline.sh / aid-gate-profile.sh / aid-cache-preflight.sh
# / aid-delivery-profile.sh / aid-review-signals.sh). This file is sourced
# directly into aid-gate-runtime-baseline.sh's shell, which is itself sourced
# into aid-run-gates.sh's `set -euo pipefail` shell — an unguarded non-zero
# return here would abort the caller's gate loop. Every function below
# returns 0 even when the underlying mkdir/append fails (fail open, warn to
# stderr) — a metrics-bootstrap side effect must never block a real gate run.
#
# ── USAGE ─────────────────────────────────────────────────────────────────
#   source .../lib/aid-gitignore-backfill.sh
#   gitignore_exclude_has_entry ".git/info/exclude" ".aid-o/metrics/"
#   gitignore_exclude_append   ".git/info/exclude" ".aid-o/metrics/"
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
