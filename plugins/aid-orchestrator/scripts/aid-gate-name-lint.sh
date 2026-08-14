#!/usr/bin/env bash
# =============================================================================
# aid-gate-name-lint.sh — a gate's name must say what it checks and how much.
#
# WHY THIS EXISTS. On 2026-08-11 a gate named `bats_all` failed. The PM read
# "gate bats_all failed" and reasonably concluded an agent was running the
# whole test portfolio in front of every merge. It was not: since the tier
# pilot that gate has run `--tier t0 && --tier t1`, i.e. the 13-minute merge
# path. The name was a leftover from when it really did run everything. It
# cost half a day of misdirected diagnosis, and it is the reason the naming
# rules were extended from suites to GATES — /ecosystem/specs/test-standard
# section "Jména bran", rules 6-10.
#
# FOUR CHECKS, all mechanical:
#
#   1. KIND — the name starts with a kind from a fixed vocabulary, so a failure
#      line groups and a reader knows immediately whether a test failed or a
#      shape check did.
#   2. NO TOOL — no tool name in a gate name. The tool gets swapped and the
#      name starts lying; `bats_fsm` survives a move to another runner only as
#      a falsehood.
#   3. TOTALITY IS TRUE — `all`/`full`/`every`/`complete` may appear only when
#      the command really covers that universe. This is the check that would
#      have caught `bats_all` the day tiers landed.
#   4. NO OUTCOME WORDS — `_pass`, `_ok`, `_success` carry nothing: every gate
#      either passes or fails. `tests_pass` says less than `tests_merge_path`.
#
# GRANDFATHERING. Renaming the live gates is ~575 literal occurrences across
# ~60 files (measured 2026-08-11) and is a plan of its own, so existing names
# are listed in an allowlist and reported as ADVISORY. New and renamed gates
# must lint clean.
#
# The rule "a missing allowlist means no exceptions" still holds — but a
# DEFAULT allowlist now ships with the plugin, because the fail-closed rule
# without one made adoption an instant hard failure in a consumer project that
# had inherited perfectly ordinary legacy names (WAN, 2026-08-13, IMP-503).
# Fail-closed was right; shipping nothing to fail closed AGAINST was the
# mistake. A project that genuinely wants zero exceptions writes an empty file,
# which is a decision rather than an accident.
#
# Usage: aid-gate-name-lint.sh [--config <execution.yaml>] [--strict]
#   --strict  treat grandfathered names as failures (use once the rename lands)
# Exit: 0 clean (or only advisory), 1 a violation on a non-grandfathered name.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=""
STRICT=0
# Allowlist resolution, in order: explicit flag/env, then the PROJECT's own
# list, then the SHIPPED default. That last fallback exists because of what
# happened on WAN 2026-08-13: a consumer adopting this lint has no allowlist of
# its own, and "a missing allowlist means no exceptions" — correct inside AID,
# where the list is maintained — turned every inherited gate name into an
# instant violation. Fail-closed is right for the RULE; shipping no default was
# a distribution mistake (IMP-503). A project that wants zero exceptions
# creates an empty file, which is a choice rather than an accident.
ALLOWLIST="${AID_GATE_NAME_ALLOWLIST:-}"
if [[ -z "$ALLOWLIST" ]]; then
  for _al in "${SCRIPT_DIR}/tests/gate-name-allowlist.txt" \
             ".aid-o/config/gate-name-allowlist.txt" \
             "${SCRIPT_DIR}/../defaults/gate-name-allowlist.txt"; do
    [[ -f "$_al" ]] && ALLOWLIST="$_al" && break
  done
  [[ -n "$ALLOWLIST" ]] || ALLOWLIST="${SCRIPT_DIR}/tests/gate-name-allowlist.txt"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --allowlist) ALLOWLIST="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$CONFIG" ]]; then
  for c in .aid-o/config/execution.yaml \
           "${SCRIPT_DIR}/../defaults/execution.yaml"; do
    [[ -f "$c" ]] && CONFIG="$c" && break
  done
fi
[[ -n "$CONFIG" && -f "$CONFIG" ]] || { echo "ERROR: no execution.yaml found (use --config)" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 2; }

KINDS='tests|lint|check|build|review'
TOOLS='bats|jq|yq|awk|sed|grep|npx|npm|ruff|bandit|pytest|vitest|tsc|shell|bash|python'
TOTALITY='all|full|every|complete|vse'
OUTCOME='pass|ok|success|green|prosly'

declare -A GRANDFATHERED=()
if [[ -f "$ALLOWLIST" ]]; then
  while read -r line; do
    line="${line%%#*}"; line="${line// /}"
    [[ -n "$line" ]] && GRANDFATHERED["$line"]=1
  done < "$ALLOWLIST"
fi

violations=0
advisory=0

while read -r gate; do
  [[ -n "$gate" ]] || continue
  cmd="$(yq -r ".gates.\"${gate}\".command // \"\"" "$CONFIG" 2>/dev/null)"
  problems=()

  [[ "$gate" =~ ^(${KINDS})_ ]] || \
    problems+=("nezacina druhem (${KINDS//|/, })")

  [[ "$gate" =~ (^|_)(${TOOLS})(_|$) ]] && \
    problems+=("obsahuje jmeno nastroje — nastroj se vymeni a jmeno zacne lhat")

  if [[ "$gate" =~ (^|_)(${TOTALITY})(_|$) ]]; then
    # The word is allowed only when the command really covers everything:
    # no tier filter, no single-file invocation, no --only.
    if [[ "$cmd" == *"--tier"* || "$cmd" == *"--only"* || "$cmd" == *".bats"* ]]; then
      problems+=("slovo o uplnosti, ale prikaz pousti jen vyber (${cmd:0:48}...)")
    fi
  fi

  [[ "$gate" =~ _(${OUTCOME})$ ]] && \
    problems+=("konci slovem o vysledku — kazda brana bud projde, nebo ne")

  if [[ "${#problems[@]}" -gt 0 ]]; then
    if [[ -n "${GRANDFATHERED[$gate]:-}" && "$STRICT" -eq 0 ]]; then
      printf 'ADVISORY  %-24s %s\n' "$gate" "${problems[*]}"
      advisory=$((advisory + 1))
    else
      printf 'VIOLATION %-24s %s\n' "$gate" "${problems[*]}"
      violations=$((violations + 1))
    fi
  fi
done < <(yq -r '.gates | keys | .[]' "$CONFIG" 2>/dev/null)

total="$(yq -r '.gates | keys | length' "$CONFIG" 2>/dev/null)"
echo "---"
echo "aid-gate-name-lint: ${CONFIG} — ${total} bran, ${violations} porusenych, ${advisory} grandfathered."
if [[ "$violations" -gt 0 ]]; then
  echo "Pravidla: /ecosystem/specs/test-standard → 'Jména bran' (6-10)." >&2
  exit 1
fi
exit 0
