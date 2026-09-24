#!/usr/bin/env bash
# =============================================================================
# aid-test-tier-assign.sh — propose a tier for every suite, from its MEASURED
# cost and its scope (P081 Step 2).
#
# WHY THIS EXISTS: a tier assigned from opinion is the defect the test standard
# was written to prevent. This tool supplies the mechanical half so the only
# human judgement left is scope — does this suite cross components — and even
# that has a mechanical default (a suite whose subject resolves to no file is
# cross-component by the standard's own rule).
#
# IT PROPOSES, IT NEVER EDITS. No suite is written by this script; the stamping
# is a reviewed diff.
#
# THE RULE, both halves:
#   cost   — per case  <2 s ⇒ t0,  <30 s ⇒ t1,  otherwise t2. The comparison
#            is strictly `<`, so a suite sitting exactly on a threshold falls
#            into the MORE EXPENSIVE tier.
#   scope  — a suite whose subject cannot be resolved to an existing file is
#            t2 whatever it costs.
#   budget — the measured sums must fit AID_TIER_T0_BUDGET_MS and
#            AID_TIER_T1_BUDGET_MS (lib/aid-test-tier.sh: 90 s and 390 s, so
#            the real T0 + T1 run stays under the standard's 10 minutes). While
#            a tier overflows, its most expensive member is demoted and the
#            demotion is printed with its reason; the core (tests/tier-core.txt)
#            is never demoted to t2. The standard forbids tolerating an
#            overflow quietly.
#
# UNMEASURED IS NEVER A TIER. A suite with no record, or whose newest record
# is censored (a run cut short — a partial duration), is listed separately and
# the tool exits non-zero, so a caller cannot mistake a partial table for a
# complete one.
#
# Usage:
#   aid-test-tier-assign.sh [--tests-dir DIR] [--format tsv|md]
#
# Exit codes: 0 = every discovered suite is tiered, 1 = some are unmeasured,
#             2 = usage / unreadable inputs.
#
# **Last Updated:** 2026-09-24
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-tier.sh
source "$SCRIPT_DIR/lib/aid-test-tier.sh"
# shellcheck source=lib/aid-test-durations.sh
source "$SCRIPT_DIR/lib/aid-test-durations.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS_DIR=""
FORMAT="tsv"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tests-dir) [[ $# -ge 2 ]] || { echo "aid-test-tier-assign: --tests-dir needs a value" >&2; exit 2; }
                 TESTS_DIR="$2"; shift 2 ;;
    --format)    [[ $# -ge 2 ]] || { echo "aid-test-tier-assign: --format needs a value" >&2; exit 2; }
                 FORMAT="$2"; shift 2 ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# Exit codes:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "aid-test-tier-assign: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
case "$FORMAT" in
  tsv|md) ;;
  *) echo "aid-test-tier-assign: --format must be tsv or md" >&2; exit 2 ;;
esac

# ─── Subject resolution ─────────────────────────────────────────────────────
#
# `test-<stem>.{bats,sh}` names <stem> as its subject; the subject is resolved
# by looking for a real file of that name in the places the plugin keeps its
# units. This is DELIBERATELY mechanical and deliberately unclever: the
# grounding measured that 119 of 191 suites name a concept rather than a file,
# and inventing a cleverer rule to shrink that number would only produce
# confident wrong subjects. An unresolved subject is an honest answer with a
# defined consequence (t2), not a failure.
resolve_subject() {
  local base="$1" stem candidate
  stem="${base#test-}"; stem="${stem%.bats}"; stem="${stem%.sh}"
  for candidate in \
    "scripts/${stem}.sh" "scripts/lib/${stem}.sh" \
    "scripts/aid-${stem}.sh" "scripts/lib/aid-${stem}.sh" \
    "skills/${stem}.md" "commands/${stem}.md" "agents/${stem}.md"; do
    if [[ -f "$PLUGIN_ROOT/$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'unresolvable\n'
}

# ─── Gather one row per discovered suite ────────────────────────────────────
rows="$(mktemp)"; unmeasured="$(mktemp)"
trap 'rm -f "$rows" "$unmeasured"' EXIT

LATEST="$(aid_durations_latest_all)" || exit 2
discovered=0
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  discovered=$(( discovered + 1 ))
  base="$(basename "$suite")"
  runner="bats"; [[ "$base" == *.sh ]] && runner="sh"

  rec="$(jq -c --arg s "$base" '.[$s] // empty' <<<"$LATEST")"
  if [[ -z "$rec" ]]; then
    printf '%s\tno measurement in the durations journal\n' "$base" >> "$unmeasured"
    continue
  fi
  if [[ "$(jq -r '.censored' <<<"$rec")" == "true" ]]; then
    printf '%s\tnewest measurement is censored (the run was cut short)\n' "$base" >> "$unmeasured"
    continue
  fi

  jq -c --arg suite "$base" --arg runner "$runner" \
        --arg subject "$(resolve_subject "$base")" \
    '{suite:$suite, runner:$runner, subject:$subject,
      duration_ms:.duration_ms, cases:.cases, exit_code:.exit_code,
      host:(.host // "unknown"), at:.at}' <<<"$rec" >> "$rows"
done < <(aid_test_discover_suites "$TESTS_DIR")

if [[ "$discovered" -eq 0 ]]; then
  echo "aid-test-tier-assign: no suites discovered — refusing to publish an empty assignment" >&2
  exit 2
fi

# ─── The core: suites the budget never pushes off the merge path ────────────
# `tier-core.txt` next to the suites, one suite name per line (`#` comments).
# A pinned suite guards the flow every plan runs through; it stays on the merge
# path whatever its subject, and the budget demotes the most expensive
# UNPINNED suite instead. Cost still rules: a pinned suite at 30 s or more per
# case is t2 like any other. PM, 2026-09-24.
CORE_FILE="${TESTS_DIR:-$(aid_test_default_tests_dir)}/tier-core.txt"
core_json='[]'
[[ -f "$CORE_FILE" ]] && core_json="$(sed 's/#.*//; s/[[:space:]]//g; /^$/d' "$CORE_FILE" | jq -R . | jq -sc .)"

# ─── Classify, then enforce the aggregate budgets ───────────────────────────
assigned="$(jq -sc --argjson t0 "$AID_TIER_T0_MAX_MS" --argjson t1 "$AID_TIER_T1_MAX_MS" --argjson core "$core_json" --argjson b0 "$AID_TIER_T0_BUDGET_MS" --argjson b1 "$AID_TIER_T1_BUDGET_MS" '
  def per_case: if .cases > 0 then (.duration_ms / .cases) else .duration_ms end;
  def secs($ms): ($ms / 1000 | tostring);
  def base_tier:
    if .subject == "unresolvable" and (.pinned | not)
      then {tier:"t2", reason:"unresolvable subject — cross-component by the standard scope rule"}
    elif (per_case < $t0) then {tier:"t0", reason:("under " + secs($t0) + "s per case")}
    elif (per_case < $t1) then {tier:"t1", reason:("under " + secs($t1) + "s per case")}
    else                       {tier:"t2", reason:(secs($t1) + "s or more per case")}
    end;
  def total($t): ([.[] | select(.tier == $t) | .duration_ms] | add) // 0;
  def demote($from; $to; $budget; $why):
    # A pinned suite may move T0 -> T1 (both are the merge path), never to T2.
    def movable: .tier == $from and ($to != "t2" or (.pinned | not));
    until(total($from) <= $budget or ([.[] | select(movable)] | length) == 0;
      (map(select(movable)) | max_by(.duration_ms) | .suite) as $s
      | map(if .suite == $s
            then .tier = $to | .demoted_from = $from | .reason = $why
            else . end));

  map(. + {pinned: (.suite as $n | any($core[]; . == $n))})
  | map(. + base_tier + {demoted_from: null, ms_per_case: (per_case | floor)})
  | map(if .pinned then .reason += " (core, pinned)" else . end)
  | demote("t0"; "t1"; $b0; "demoted: the T0 budget of 2 min was exceeded")
  | demote("t1"; "t2"; $b1; "demoted: the T1 budget of 10 min was exceeded")
  | sort_by(.tier, -.duration_ms)
' "$rows")" || { echo "aid-test-tier-assign: could not classify the measured suites" >&2; exit 2; }

# The core alone over the T1 budget is a proposal lint will refuse: say so.
over="$(jq -r --argjson b1 "$AID_TIER_T1_BUDGET_MS" '([.[] | select(.tier == "t1") | .duration_ms] | add // 0) as $t
  | if $t > $b1 then "\($t / 1000 | floor)" else empty end' <<<"$assigned")"
if [[ -n "$over" ]]; then
  echo "aid-test-tier-assign: T1 stays at ${over}s after every movable suite was demoted — the core in $CORE_FILE alone exceeds the T1 budget of $(( AID_TIER_T1_BUDGET_MS / 1000 ))s; shorten it" >&2
  exit 1
fi

n_unmeasured=0
[[ -s "$unmeasured" ]] && n_unmeasured="$(grep -c '' "$unmeasured")"

emit_tsv() {
  printf 'suite\trunner\tsubject\tduration_ms\tcases\tms_per_case\ttier\treason\tdemoted_from\n'
  jq -r '.[] | [.suite, .runner, .subject, .duration_ms, .cases, .ms_per_case,
                .tier, .reason, (.demoted_from // "-")] | @tsv' <<<"$assigned"
}

emit_md() {
  local host at
  host="$(jq -r '[.[].host] | unique | join(", ")' <<<"$assigned")"
  at="$(jq -r '[.[].at] | max' <<<"$assigned")"
  printf '## Measured tier assignment\n\n'
  printf -- '- Measured on: `%s`\n' "$host"
  printf -- '- Newest measurement: `%s`\n' "$at"
  printf -- '- Suites discovered: %d — tiered %d, unmeasured %d\n' \
    "$discovered" "$(jq 'length' <<<"$assigned")" "$n_unmeasured"
  local t
  for t in $AID_TEST_TIERS; do
    printf -- '- %s: %d suite(s), %d ms total\n' "${t^^}" \
      "$(jq --arg t "$t" '[.[] | select(.tier == $t)] | length' <<<"$assigned")" \
      "$(jq --arg t "$t" '[.[] | select(.tier == $t) | .duration_ms] | add // 0' <<<"$assigned")"
  done
  printf '\n| Suite | Runner | Subject | ms | Cases | ms/case | Tier | Reason | Demoted from |\n'
  printf -- '|---|---|---|---|---|---|---|---|---|\n'
  jq -r '.[] | "| `\(.suite)` | \(.runner) | `\(.subject)` | \(.duration_ms) | \(.cases) | \(.ms_per_case) | **\(.tier)** | \(.reason) | \(.demoted_from // "-") |"' <<<"$assigned"
  if [[ "$n_unmeasured" -gt 0 ]]; then
    printf '\n### Unmeasured — never defaulted into a tier\n\n'
    while IFS=$'\t' read -r s why; do printf -- '- `%s` — %s\n' "$s" "$why"; done < "$unmeasured"
  fi
}

case "$FORMAT" in
  tsv) emit_tsv ;;
  md)  emit_md ;;
esac

if [[ "$n_unmeasured" -gt 0 ]]; then
  {
    echo ""
    echo "aid-test-tier-assign: $n_unmeasured of $discovered discovered suite(s) have no usable measurement:"
    while IFS=$'\t' read -r s why; do echo "  - $s — $why"; done < "$unmeasured"
    echo "This table is PARTIAL. Measure them (run-all-tests.sh --timing) before tiering."
  } >&2
  exit 1
fi
exit 0
