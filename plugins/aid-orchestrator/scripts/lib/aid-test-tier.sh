#!/usr/bin/env bash
# =============================================================================
# aid-test-tier.sh — the ONE authority on which suites exist and what tier
# each declares (P081 Steps 2-3).
#
# WHY ONE AUTHORITY: the tier assigner, the tier lint, the runner's `--tier`
# filter and the plan-time check all need the same two answers. Two readers
# eventually disagree, and a suite that one of them cannot see is a suite that
# silently never runs — the exact failure the tier work exists to prevent.
#
# THE MECHANISM: a tier is declared by a header comment, `# aid-tier: t1`,
# in the suite's LEADING COMMENT BLOCK. A tag costs nothing to move a suite
# between tiers and breaks none of the ~420 literal path references that tier
# DIRECTORIES would have broken (enforcement-registry `test:` fields, catalog
# `run_unit_id` join keys, gate commands, CI jobs).
#
# CONTRACT
#   aid_test_discover_suites [tests_dir]
#     Prints every discovered suite path, `test-*.sh` first and then
#     `bats/test-*.bats`, in exactly the order and by exactly the globs
#     `run-all-tests.sh` itself uses. Non-suite helpers (`run-all-tests.sh`,
#     `verify-version-files.sh`, …) do not match, and `fixtures/` is not
#     reached — the globs are not recursive.
#
#   aid_test_tier_of <suite_path>
#     Prints the declared tier and returns 0; prints nothing and returns 1
#     when the file carries no tag; returns 2 when it carries more than one
#     or an unknown value (never first-wins, never a guess).
#
#   aid_test_tier_list <tier> [tests_dir]
#     Prints every discovered suite carrying <tier>.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (aid-test-adapter-contract.sh header convention).
#
# Dependencies: bash only.
#
# **Last Updated:** 2026-08-10
# =============================================================================

if [[ -n "${_AID_TEST_TIER_SH_SOURCED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_AID_TEST_TIER_SH_SOURCED=1

_AID_TT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The plugin's own tests directory, used when a caller names none.
AID_TEST_TIERS="t0 t1 t2"

aid_test_default_tests_dir() {
  printf '%s\n' "$(cd "${_AID_TT_LIB_DIR}/../tests" && pwd)"
}

aid_test_discover_suites() {
  local dir="${1:-}"
  [[ -n "$dir" ]] || dir="$(aid_test_default_tests_dir)"
  local f
  for f in "$dir"/test-*.sh; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  for f in "$dir"/bats/test-*.bats; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  return 0
}

# _aid_tt_header <file> — the leading comment block: the consecutive `#` lines
# following an optional shebang, HOWEVER LONG.
#
# Not a fixed window. Measured on this tree: eight bats suites and
# `test-cp1-gate.sh` open with headers of 40-47+ lines, so a ten-line scan
# would have read every one of them as untagged and the lint would have
# demanded a second tag on files that already carry one.
_aid_tt_header() {
  local file="$1" line first=1
  while IFS= read -r line; do
    if [[ "$first" -eq 1 ]]; then
      first=0
      [[ "$line" == '#!'* ]] && continue
    fi
    [[ "$line" == '#'* ]] || break
    printf '%s\n' "$line"
  done < "$file"
}

aid_test_tier_of() {
  local file="${1:?aid_test_tier_of: suite path required}"
  [[ -f "$file" ]] || return 1

  local tags count
  # The tag is looked for in the WHOLE file, not only the header: a second tag
  # further down is a contradiction that must be reported, not hidden by a
  # scan that stops early.
  tags="$(grep -nE '^[[:space:]]*#[[:space:]]*aid-tier:' "$file" || true)"
  [[ -n "$tags" ]] || return 1
  count="$(printf '%s\n' "$tags" | grep -c '')"
  if [[ "$count" -ne 1 ]]; then
    echo "aid-test-tier: '$file' declares $count tiers, at line(s) $(printf '%s\n' "$tags" | cut -d: -f1 | tr '\n' ' ')— a suite has exactly one tier" >&2
    return 2
  fi

  # A tag outside the leading comment block is not a header declaration.
  if ! _aid_tt_header "$file" | grep -qE '^[[:space:]]*#[[:space:]]*aid-tier:'; then
    echo "aid-test-tier: '$file' carries an aid-tier tag outside its leading comment block — the tag is a header declaration" >&2
    return 2
  fi

  local tier
  tier="$(printf '%s\n' "$tags" | sed -E 's/^[0-9]+:[[:space:]]*#[[:space:]]*aid-tier:[[:space:]]*//' | tr -d '[:space:]')"
  case " $AID_TEST_TIERS " in
    *" $tier "*) printf '%s\n' "$tier"; return 0 ;;
    *)
      echo "aid-test-tier: '$file' declares tier '$tier', which is not one of: $AID_TEST_TIERS" >&2
      return 2 ;;
  esac
}

aid_test_tier_list() {
  local want="${1:?aid_test_tier_list: tier required}" dir="${2:-}"
  local suite tier
  while IFS= read -r suite; do
    tier="$(aid_test_tier_of "$suite" 2>/dev/null)" || continue
    [[ "$tier" == "$want" ]] && printf '%s\n' "$suite"
  done < <(aid_test_discover_suites "$dir")
  return 0
}
