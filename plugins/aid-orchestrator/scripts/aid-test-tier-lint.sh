#!/usr/bin/env bash
# =============================================================================
# aid-test-tier-lint.sh — the tier tag is complete, honest and unforged
# (P081 Step 3).
#
# THREE CHECKS, one purpose: keep the tag telling the truth once it exists.
#
#   1. DECLARED — every discovered suite carries exactly one valid
#      `# aid-tier:` tag. An untagged suite is the drift back into "everything
#      is cheap"; a doubly-tagged one is a contradiction, never first-wins.
#
#   2. NAMED — no suite filename carries a plan, EPIC or task number. A suite
#      named after the plan that produced it tells a reader nothing about what
#      it proves, and it is the reason nobody ever deletes one. An allowlist
#      file holds sanctioned exceptions; a MISSING allowlist means no
#      exceptions, never "allow everything".
#
#   3. AFFORDABLE — a declared tier is never CHEAPER than the newest
#      measurement supports. The reverse is fine and expected: the scope rule
#      and the aggregate budgets both push suites upward, and a suite that is
#      cheap but cross-component belongs in T2 on purpose.
#
# A suite with no measurement is reported UNVERIFIED and does not fail the
# lint. The standard's rule is that measurement MOVES a tier; the absence of a
# measurement is not evidence that a suite is cheap.
#
# Usage:
#   aid-test-tier-lint.sh [--tests-dir DIR] [--allowlist FILE] [--quiet]
#
# Exit codes: 0 = clean, 1 = violations, 2 = usage.
#
# **Last Updated:** 2026-08-10
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-tier.sh
source "$SCRIPT_DIR/lib/aid-test-tier.sh"
# shellcheck source=lib/aid-test-durations.sh
source "$SCRIPT_DIR/lib/aid-test-durations.sh"

TESTS_DIR=""
ALLOWLIST=""
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests-dir) [[ $# -ge 2 ]] || { echo "aid-test-tier-lint: --tests-dir needs a value" >&2; exit 2; }
                 TESTS_DIR="$2"; shift 2 ;;
    --allowlist) [[ $# -ge 2 ]] || { echo "aid-test-tier-lint: --allowlist needs a value" >&2; exit 2; }
                 ALLOWLIST="$2"; shift 2 ;;
    --quiet)     QUIET=1; shift ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "aid-test-tier-lint: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[[ -n "$TESTS_DIR" ]] || TESTS_DIR="$(aid_test_default_tests_dir)"
[[ -n "$ALLOWLIST" ]] || ALLOWLIST="$TESTS_DIR/tier-lint-allowlist.txt"

# The journal is probed ONCE, loudly. A per-suite read that returns "cannot
# read this" would otherwise be indistinguishable from "never measured", and the
# lint would report a corrupt journal as a clean, merely unverified tree.
if ! aid_durations_readable; then
  echo "aid-test-tier-lint: the durations journal cannot be read — refusing to report tiers as unverified when the real state is unknown" >&2
  exit 2
fi

VIOLATIONS=()
UNVERIFIED=()

_violation() { VIOLATIONS+=("$1"); }
_say() { [[ "$QUIET" -eq 1 ]] || echo "$*"; }

# ─── is_plan_numbered <basename> ────────────────────────────────────────────
#
# SEGMENT-wise, not a raw substring match. The filename is split on `-`, `_`
# and `.`, and a segment is a plan token when it is `p<digits>`, or an `e`/`t`
# immediately followed by a numeric segment (`e-064`, `t-123`).
#
# A substring rule would have condemned `test-cp1-gate.sh`, whose `cp1` is a
# checkpoint, not plan P1 — a lint that renames innocent files teaches people
# to switch it off. Case-insensitive because every live offender is lowercase
# and an uppercase-only class would have matched none of them.
is_plan_numbered() {
  local base="$1" lower seg prev=""
  lower="${base,,}"
  local IFS='-_.'
  for seg in $lower; do
    [[ "$seg" =~ ^p[0-9]+$ ]] && return 0
    [[ "$prev" =~ ^[et]$ && "$seg" =~ ^[0-9]+$ ]] && return 0
    prev="$seg"
  done
  return 1
}

# ─── cost_tier <suite_basename> ─────────────────────────────────────────────
# The cheapest tier the newest measurement allows, or empty when unmeasured.
# Same thresholds as aid-test-tier-assign.sh, cost half only — scope and the
# budgets can only push a tier UP, and this check is about the floor.
cost_tier() {
  local rec
  rec="$(aid_durations_latest_json "$1" 2>/dev/null)" || return 1
  [[ "$(jq -r '.censored' <<<"$rec")" == "true" ]] && return 1
  jq -r 'if .cases > 0 then (.duration_ms / .cases) else .duration_ms end
         | if . < 2000 then "t0" elif . < 30000 then "t1" else "t2" end' <<<"$rec"
}

_tier_rank() { case "$1" in t0) echo 0 ;; t1) echo 1 ;; t2) echo 2 ;; *) echo -1 ;; esac; }

# ─── The allowlist ──────────────────────────────────────────────────────────
declare -A ALLOWED=()
if [[ -f "$ALLOWLIST" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line//[[:space:]]/}"
    [[ -n "$line" ]] && ALLOWED["$line"]=1
  done < "$ALLOWLIST"
fi

# ─── Walk the portfolio ─────────────────────────────────────────────────────
discovered=0
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  discovered=$(( discovered + 1 ))
  base="$(basename "$suite")"

  tier=""; tier_rc=0
  tier="$(aid_test_tier_of "$suite" 2>/dev/null)" || tier_rc=$?
  case "$tier_rc" in
    0) ;;
    1) _violation "$base — no '# aid-tier:' tag; add one (t0/t1/t2) to its leading comment block" ;;
    *) _violation "$base — its aid-tier tag is duplicated or names an unknown tier (accepted: $AID_TEST_TIERS)" ;;
  esac

  if is_plan_numbered "$base" && [[ -z "${ALLOWED[$base]:-}" ]]; then
    _violation "$base — the filename carries a plan/EPIC/task number; rename it after what it proves (or allowlist it in $(basename "$ALLOWLIST"))"
  fi

  if [[ -n "$tier" ]]; then
    floor="$(cost_tier "$base")" || floor=""
    if [[ -z "$floor" ]]; then
      UNVERIFIED+=("$base ($tier)")
    elif [[ "$(_tier_rank "$tier")" -lt "$(_tier_rank "$floor")" ]]; then
      _violation "$base — declares $tier but its newest measurement supports no cheaper than $floor"
    fi
  fi
done < <(aid_test_discover_suites "$TESTS_DIR")

if [[ "$discovered" -eq 0 ]]; then
  echo "aid-test-tier-lint: no suites discovered under '$TESTS_DIR' — refusing to report a clean portfolio that was never read" >&2
  exit 2
fi

_say "aid-test-tier-lint: $discovered suite(s) checked in $TESTS_DIR"
if [[ "${#UNVERIFIED[@]}" -gt 0 ]]; then
  _say ""
  _say "  UNVERIFIED (tag accepted as declared — no measurement to check it against):"
  for u in "${UNVERIFIED[@]}"; do _say "    - $u"; done
fi

if [[ "${#VIOLATIONS[@]}" -gt 0 ]]; then
  echo ""
  echo "  VIOLATIONS (${#VIOLATIONS[@]}):"
  for v in "${VIOLATIONS[@]}"; do echo "    - $v"; done
  echo ""
  echo "RESULT: FAIL"
  exit 1
fi
_say ""
_say "RESULT: PASS"
exit 0
