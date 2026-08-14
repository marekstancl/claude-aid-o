#!/usr/bin/env bash
# aid-tier: t0
# =============================================================================
# test-tier-ci-topology.sh — the tier tag and the CI workflows must agree
#
# THIS FILE REPLACES test-run-all-delegation.sh, whose subject (a suite
# "delegated" to a dedicated CI job) was deleted on 2026-08-14. It keeps that
# test's real purpose — a suite that is run by NOTHING must be impossible —
# and adds the check whose absence caused the incident:
#
#   Five suites were tagged `# aid-tier: t2` AND had a dedicated job running on
#   every push and PR. The ecosystem test standard says T2 runs in the nightly
#   cron and NEVER on the merge path. The jobs were added 2026-07-25, when the
#   heaviest suite took ~22 min and tiers did not exist; tiers arrived
#   2026-08-11 and changed what the RUNNER selects, not what GitHub schedules.
#   Nothing compared the two, so by 2026-08-14 CI had been failing on every
#   push for days against a 35-minute limit the suite needed 199 minutes to
#   satisfy. Two authorities, no arbiter.
#
# WHAT THIS IS, HONESTLY: a static coverage contract over workflow files and
# the runner's own `--list`. It is NOT proof that arbitrary shell executes a
# suite. It reads DIRECT `run:` commands of jobs in workflows whose own `on:`
# block carries push/pull_request, and it REFUSES rather than guesses when a
# workflow uses indirection it cannot follow (`workflow_call`, `workflow_run`,
# or a run command built from an expression) — a check that quietly skips what
# it cannot parse is worth less than no check.
#
# Assertions:
#   1. every discovered suite carries exactly one tier tag (delegated to
#      aid-test-tier-lint.sh's own rules — here only presence is asserted)
#   2. every discovered suite appears exactly once in `run-all-tests.sh --list`
#      — the "run by nothing" guard the old test existed for
#   3. no T2 suite is named in a push/PR-triggered workflow command
#   4. the nightly workflow is schedule-triggered and has AT LEAST ONE untiered
#      runner invocation, so T2 suites are covered by something (it also runs
#      each tier separately, to measure the budgets — that is not a violation)
#   5. no unparseable indirection in push/PR workflows (fail closed)
#
# Exit: 0 all pass, 1 any fail.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
RUNNER="$SCRIPT_DIR/run-all-tests.sh"
# AID_TOPOLOGY_WORKFLOW_DIR is a TEST SEAM, not a production knob: it lets
# bats/test-tier-ci-topology-guard.bats point this check at fixture workflows and
# prove it actually catches each shape. A guard nobody has watched fail is a
# guard nobody should trust. Production callers never set it.
WORKFLOW_DIR="${AID_TOPOLOGY_WORKFLOW_DIR:-$REPO_ROOT/.github/workflows}"
NIGHTLY="$WORKFLOW_DIR/nightly-tests.yml"

PASS=0; FAIL=0
_pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
_fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }

[[ -f "$RUNNER" ]] || { echo "FAIL: run-all-tests.sh not found at $RUNNER" >&2; exit 1; }
[[ -d "$WORKFLOW_DIR" ]] || { echo "FAIL: no .github/workflows at $WORKFLOW_DIR" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "FAIL: yq is required (workflows are parsed, not grepped)" >&2; exit 1; }

# ── the suites, and their tiers, read from the files themselves ─────────────
declare -A TIER=()
SUITES=()
while IFS= read -r f; do
  bn="$(basename "$f")"
  SUITES+=("$bn")
  # The tag lives in the leading comment block; take the first, and count them
  # so "exactly one" is a fact rather than first-wins.
  n_tags="$(grep -cE '^#[[:space:]]*aid-tier:[[:space:]]*t[012][[:space:]]*$' "$f")"
  tag="$(grep -m1 -oE 'aid-tier:[[:space:]]*t[012]' "$f" | grep -oE 't[012]')"
  if [[ "$n_tags" -ne 1 ]]; then
    _fail "$bn carries $n_tags tier tags — exactly one is required"
    continue
  fi
  TIER["$bn"]="$tag"
done < <(find "$SCRIPT_DIR" -maxdepth 2 \( -name 'test-*.sh' -o -name 'test-*.bats' \) | sort)
[[ ${#SUITES[@]} -gt 0 ]] || { echo "FAIL: discovered no suites at all" >&2; exit 1; }
_pass "every one of ${#SUITES[@]} discovered suites carries exactly one tier tag"

# ── 1+2. run by SOMETHING: the runner lists each suite exactly once ─────────
listing="$(bash "$RUNNER" --list 2>&1)" || true
missing=0 duplicated=0
for bn in "${SUITES[@]}"; do
  n="$(grep -cE "^INLINE: ${bn} " <<<"$listing")"
  case "$n" in
    1) ;;
    0) _fail "$bn appears in NO line of the runner's listing — it is run by nothing"; missing=$((missing+1)) ;;
    *) _fail "$bn appears on $n listing lines"; duplicated=$((duplicated+1)) ;;
  esac
done
[[ "$missing" -eq 0 && "$duplicated" -eq 0 ]] && \
  _pass "every discovered suite is listed exactly once by run-all-tests.sh --list"

# ── 3+5. no T2 suite on a push/PR-triggered job ────────────────────────────
for wf in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [[ -f "$wf" ]] || continue
  triggers="$(yq e -o=json '.on | keys' "$wf" 2>/dev/null)" || {
    _fail "$(basename "$wf") could not be parsed by yq — refusing to assume it is safe"
    continue
  }
  # Indirection this check cannot follow. Fail closed, never skip silently.
  if grep -qE '"(workflow_call|workflow_run)"' <<<"$triggers"; then
    _fail "$(basename "$wf") uses workflow_call/workflow_run — this check cannot establish its merge-path status; extend the check or state an exception"
    continue
  fi
  grep -qE '"(push|pull_request)"' <<<"$triggers" || continue

  # Every direct `run:` string of every job in a merge-path workflow, with
  # SHELL COMMENTS STRIPPED and LINE CONTINUATIONS JOINED. Comments: a run block
  # that merely explains why a suite skips when a package is missing is prose,
  # not an invocation, and counting it made this check's first run report two
  # suites that no job runs. Continuations: a command whose flags sit on the
  # next line would otherwise be judged on its first line alone, which is how
  # `run-all-tests.sh \<newline> --tier t2` would read as untiered.
  cmds="$(yq e -r '.jobs[].steps[]?.run // ""' "$wf" 2>/dev/null | sed 's/#.*$//' \
          | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}')"
  if grep -qE '\$\{\{' <<<"$cmds"; then
    _fail "$(basename "$wf") builds a run command from an expression — this check cannot read it"
  fi
  offenders=0
  # A merge-path job does not have to NAME a t2 suite to run one. Three shapes
  # run the whole portfolio (or the t2 half of it) without a single basename,
  # and a guard that only matched basenames would wave all three through —
  # which is the same "the check looks right and sees nothing" failure that let
  # the five dedicated jobs live for three days.
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    # MENTIONING the runner is not RUNNING it. `chmod +x .../run-all-tests.sh`
    # names the script on its own line, and reading that as an untiered
    # invocation made this check fail its own workflow twice.
    first_tok="${line#"${line%%[![:space:]]*}"}"; first_tok="${first_tok%% *}"
    case "$first_tok" in
      chmod|echo|cat|printf|ls|rm|cp|mv|sed|grep|awk|git|mkdir|touch|export) continue ;;
    esac
    case "$line" in
      *run-all-tests.sh*--tier[[:space:]]t2*)
        _fail "$(basename "$wf") runs the runner with --tier t2 on push/PR — T2 never blocks a merge"
        offenders=$((offenders+1)) ;;
      *run-all-tests.sh*--list*|*run-all-tests.sh*--only*) ;;   # enumerates / one named suite
      *run-all-tests.sh*)
        grep -q -- '--tier' <<<"$line" || {
          _fail "$(basename "$wf") runs the runner UNTIERED on push/PR — an untiered run is the full portfolio, T2 included"
          offenders=$((offenders+1)); }
        ;;
    esac
    # A raw glob over the suite directory sweeps every tier at once.
    case "$line" in
      *bats*tests/bats/test-\**|*bats*tests/bats/*\*.bats*)
        _fail "$(basename "$wf") runs a bats GLOB over the suite directory on push/PR — that includes every t2 suite"
        offenders=$((offenders+1)) ;;
    esac
  done <<< "$cmds"
  for bn in "${SUITES[@]}"; do
    [[ "${TIER[$bn]:-}" == "t2" ]] || continue
    if grep -qF "$bn" <<<"$cmds"; then
      _fail "$bn is tagged t2 but is named by a job in $(basename "$wf"), which runs on push/PR — T2 never blocks a merge (ecosystem test standard)"
      offenders=$((offenders+1))
    fi
  done
  [[ "$offenders" -eq 0 ]] && _pass "$(basename "$wf") (push/PR) names no t2 suite"
done

# ── 4. the nightly really does cover T2 ────────────────────────────────────
if [[ ! -f "$NIGHTLY" ]]; then
  _fail "no nightly workflow at $NIGHTLY — nothing runs the T2 suites"
else
  n_trig="$(yq e -o=json '.on | keys' "$NIGHTLY" 2>/dev/null)"
  if grep -qE '"schedule"' <<<"$n_trig"; then
    _pass "the nightly workflow is schedule-triggered"
  else
    _fail "the nightly workflow has no schedule trigger — the T2 suites would run only by hand"
  fi
  n_cmds="$(yq e -r '.jobs[].steps[]?.run // ""' "$NIGHTLY" 2>/dev/null | sed 's/#.*$//' \
            | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba' -e '}')"
  runner_lines="$(grep -F 'run-all-tests.sh' <<<"$n_cmds" || true)"
  # AT LEAST ONE untiered invocation — not "no tiered invocation". The nightly
  # legitimately ALSO runs `--tier t0` and `--tier t1` separately, because the
  # standard requires each tier's budget to be verified by a real run rather
  # than by summing suite times. Only the absence of an UNTIERED run would
  # leave T2 uncovered.
  if [[ -z "${runner_lines//[[:space:]]/}" ]]; then
    _fail "the nightly workflow never invokes run-all-tests.sh"
  elif grep -F 'run-all-tests.sh' <<<"$runner_lines" | grep -qv -- '--tier'; then
    _pass "the nightly has at least one untiered run-all-tests.sh invocation (the full portfolio)"
  else
    _fail "every nightly run-all-tests.sh invocation carries --tier — nothing runs the full portfolio, so T2 is uncovered"
  fi
fi

echo "---"
# The aggregate runner PARSES this line; a suite whose result it cannot read is
# counted as 0/0 and reported UNPARSED (which is how this file failed its own
# first merge-path run). Shape taken from run-all-tests.sh's documented list.
echo "Results: $((PASS+FAIL)) run, $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
