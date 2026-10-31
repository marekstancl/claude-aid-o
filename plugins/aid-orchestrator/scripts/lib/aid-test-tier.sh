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

# THE TAG'S ONE SPELLING. A second regex for the same tag is a second opinion
# about what counts as a declaration.
AID_TEST_TIER_TAG_RE='^[[:space:]]*#[[:space:]]*aid-tier:'

# THE COST HALF OF THE TIER RULE, in one place. The assigner (which PROPOSES a
# tier) and the lint (which checks a DECLARED tier against its floor) both read
# these. They used to be two jq programs agreeing by comment, which is not a
# mechanism: moving the T1 boundary would have made the lint disagree with the
# tool that produced the tags it checks.
AID_TIER_T0_MAX_MS="${AID_TIER_T0_MAX_MS:-2000}"
AID_TIER_T1_MAX_MS="${AID_TIER_T1_MAX_MS:-30000}"
# Budgets of the merge path, as sums of measured suites. The standard allows
# T0 + T1 together 10 minutes of REAL run; the runner adds its own time per suite
# (night of 15. 10. 2026: 791 s of suites ran 919 s, 1.5 s for each of 83 suites).
# With 62 suites on the merge path that is ~95 s, so T0 30 s (the static checks)
# + T1 450 s + 95 s = 575 s leaves 25 s of margin. The lint reads the night's
# measurements, 7 % slower than the day's; the real run is what counts, and the
# nightly measures it and says when it is over.
AID_TIER_T0_BUDGET_MS="${AID_TIER_T0_BUDGET_MS:-30000}"
AID_TIER_T1_BUDGET_MS="${AID_TIER_T1_BUDGET_MS:-450000}"

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

  local tags count header
  # The tag is looked for in the WHOLE file, not only the header: a second tag
  # further down is a contradiction that must be reported, not hidden by a
  # scan that stops early.
  tags="$(grep -nE "$AID_TEST_TIER_TAG_RE" "$file" || true)"
  [[ -n "$tags" ]] || return 1
  count="$(printf '%s\n' "$tags" | grep -c '' || true)"
  if [[ "$count" -ne 1 ]]; then
    echo "aid-test-tier: '$file' declares $count tiers, at line(s) $(printf '%s\n' "$tags" | cut -d: -f1 | tr '\n' ' ')— a suite has exactly one tier" >&2
    return 2
  fi

  # A tag outside the leading comment block is not a header declaration.
  #
  # NOT `_aid_tt_header "$file" | grep -qE …`. `grep -q` exits at the first
  # match and closes the pipe; the header writer then takes SIGPIPE and exits
  # 141, and under a caller's `pipefail` THAT becomes the pipeline's status —
  # so this branch fired on perfectly well-formed files, and only sometimes,
  # because whether the writer had finished first is a race. It reported
  # between 25 and 32 violations over the same clean tree on consecutive runs.
  # The header is materialised first; no pipeline, no signal, no race.
  header="$(_aid_tt_header "$file")"
  if ! grep -qE "$AID_TEST_TIER_TAG_RE" <<<"$header"; then
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

# aid_test_names_plan_refs <repo> <base> [<end commit>|worktree]
#   Test cases ADDED since <base> — commits, index and the working tree of
#   tracked files, which is what `git add -u` would sweep in — whose NAME cites
#   a plan (P123), a review finding (CP2 F3) or a backlog item (IMP-612). A
#   name says what the test guards; where it came from is in git log. Prints
#   "<file>\t<name>"; 0 none, 1 found, 2 cannot tell (bad base, git failed) —
#   callers refuse on 2 as on 1. Declarations read: bats `@test`, pytest
#   `def test_`, JS/TS `it|test|describe[.each|only|skip|todo|concurrent]("…"`,
#   one line each, under a test path, never under fixtures/. The step number is
#   NOT a plan reference: "step 0" is a domain word here.
# ponytail: one-line literal names only; multi-line or computed names pass unread.
aid_test_names_plan_refs() {
  # [<end>] (AID 3.13.0, the step check): a commit = base..end exactly as reviewed; `worktree` = the uncommitted change
  # against base INCLUDING new untracked files. Without it: base against the working tree's tracked files (the gates).
  local repo="$1" base="$2" end="${3:-}" diff hits f
  git -C "$repo" rev-parse -q --verify "${base}^{commit}" >/dev/null 2>&1 || return 2
  if [[ -n "$end" && "$end" != worktree ]]; then
    git -C "$repo" rev-parse -q --verify "${end}^{commit}" >/dev/null 2>&1 || return 2
    diff="$(git -C "$repo" -c core.quotePath=false diff -M --unified=0 --no-color --no-ext-diff "$base" "$end" -- 2>/dev/null)" || return 2
  else
    diff="$(git -C "$repo" -c core.quotePath=false diff -M --unified=0 --no-color --no-ext-diff "$base" -- 2>/dev/null)" || return 2
    if [[ "$end" == worktree ]]; then
      while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        # --no-index exits 1 when the files differ, which is always here
        diff+=$'\n'"$(cd "$repo" && git -c core.quotePath=false diff --no-index --unified=0 --no-color -- /dev/null "$f" 2>/dev/null; true)"
      done < <(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null)
    fi
  fi
  hits="$(awk '
    # the name inside the quote q that opens at r[1]; "" when it never closes
    function lit(r, q,   i, c) {
      for (i = 1; i <= length(r); i++) {
        c = substr(r, i, 1)
        if (c == "\\") { i++; continue }
        if (c == q) return substr(r, 1, i - 1)
      }
      return ""
    }
    /^\+\+\+ / { f = substr($0, 5); sub(/\t$/, "", f)
                 if (f ~ /^".*"$/) f = substr(f, 2, length(f) - 2)
                 sub(/^b\//, "", f)
                 t = (f != "/dev/null" && f !~ /(^|\/)fixtures\// &&
                      (f ~ /(^|\/)(test|tests|spec|__tests__)\// || f ~ /(^|\/)test[-_][^\/]*$/ ||
                       f ~ /_test\.[^\/]*$/ || f ~ /\.(test|spec)\.[^\/]*$/ || f ~ /\.bats$/)); next }
    !t || !/^\+/ { next }
    { l = substr($0, 2); n = "" }
    match(l, /^[ \t]*@test[ \t]+["\047]/) ||
    match(l, /^[ \t]*(it|test|describe)(\.(each|only|skip|todo|concurrent))?\([ \t]*["\047`]/) {
      n = lit(substr(l, RLENGTH + 1), substr(l, RLENGTH, 1))
    }
    n == "" && match(l, /^[ \t]*(async[ \t]+)?def[ \t]+test_[A-Za-z0-9_]*/) {
      n = substr(l, RSTART, RLENGTH); sub(/^.*def[ \t]+/, "", n)
    }
    n == "" { next }
    { m = tolower(n)
      if (m ~ /(^|[^a-z0-9])p[0-9][0-9][0-9]([^a-z0-9]|$)/ ||
          m ~ /(^|[^a-z0-9])cp[0-9]+[ _\/-]?f[0-9]+([^a-z0-9]|$)/ ||
          m ~ /(^|[^a-z0-9])imp-[0-9]+([^a-z0-9]|$)/) printf "%s\t%s\n", f, n }
  ' <<<"$diff")" || return 2
  [[ -z "$hits" ]] && return 0
  printf '%s\n' "$hits"
  return 1
}
