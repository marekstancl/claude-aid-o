#!/usr/bin/env bash
# =============================================================================
# aid-turn-gate.sh — what a turn produced, checked after the CLI has returned
# (P086 Step 3)
#
#   aid-turn-gate.sh [--card <file> ...] [--plan <file> ...]
#
# WHY A GATE AND NOT ONLY A HOOK
#   The `Stop` event does not exist everywhere. Codex's two review modes never
#   send it, and no run mode of any tool sends it when a session is killed —
#   which is precisely when a turn is most likely to have left something
#   half-finished. A rule that lives only in `Stop` therefore has holes exactly
#   where it is needed.
#
#   So this is the PRIMARY check and the hook rule is the earlier catch of the
#   same defect. It validates FILES, never a transcript: a file is there after
#   the process is gone.
#
# WHAT IT IS NOT
#   Not a quality judgement. It checks that mandatory parts are PRESENT — a
#   card with two options and a reason passes whether or not the options are
#   any good, and a plan's page counts as rendered whether or not the PM read
#   it. Nothing here can tell a good option from a bad one, and a gate that
#   pretended otherwise would be refusing turns on taste.
#
# EXIT CODES
#   0  every check passed — including an input that is not the kind of thing
#      this gate checks (a report that is no decision card, a file that is no
#      numbered plan), which is never a failure
#   1  at least one check failed; every finding is named on stderr
#   2  usage error, which includes being called with NO input at all: a gate
#      invoked with nothing to look at is a mis-invocation, not a pass
#
# **Last Updated:** 2026-08-24
# =============================================================================
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/aid-decision-card.sh
source "${PLUGIN_ROOT}/scripts/lib/aid-decision-card.sh"
# shellcheck source=lib/aid-artifact-obligation.sh
source "${PLUGIN_ROOT}/scripts/lib/aid-artifact-obligation.sh"

usage() {
  echo "Usage: aid-turn-gate.sh [--card <file> ...] [--plan <file> ...]" >&2
}

main() {
  local -a cards=() plans=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --card) cards+=("${2:?--card needs a file}"); shift 2 ;;
      --plan) plans+=("${2:?--plan needs a file}"); shift 2 ;;
      -h|--help) usage; return 2 ;;
      *) echo "ERROR: unknown argument '$1'" >&2; usage; return 2 ;;
    esac
  done

  if [[ ${#cards[@]} -eq 0 && ${#plans[@]} -eq 0 ]]; then
    usage
    return 2
  fi

  # Exit 3 from a check means "this input is not the kind of thing I check" —
  # a report that is not a decision card, a file that is not a numbered plan.
  # It is never a failure: inventing an obligation for something that never
  # incurred one is the false refusal this gate must not make.
  local failed=0 file rc
  for file in ${cards[@]+"${cards[@]}"}; do
    rc=0; aid_decision_card_validate "$file" || rc=$?
    [[ "$rc" -eq 1 ]] && failed=1
  done
  for file in ${plans[@]+"${plans[@]}"}; do
    rc=0; aid_artifact_obligation_check "$file" || rc=$?
    [[ "$rc" -eq 1 ]] && failed=1
  done

  return "$failed"
}

main "$@"
