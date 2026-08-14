#!/usr/bin/env bash
# aid-human-step.sh — the one renderer for a step number shown to a human.
#
# WHY THIS IS ITS OWN FILE
#   The helper was defined inside aid-fsm.sh, so the only surfaces that could
#   use it were aid-fsm.sh's own three messages. Every other place a PM reads a
#   step number — the delivery checks first among them — either printed the raw
#   0-based field or would have needed a second copy of the wording, which is
#   exactly the drift the single-definition rule exists to prevent. Moving it
#   here changes no behaviour and no name: aid-fsm.sh sources this file and its
#   three call sites are untouched.
#
# `current_step` is 0-BASED and counts COMPLETED steps, so an operator reading
# "current_step=2" for the third step has to do the arithmetic themselves — and
# repeatedly got it wrong. Machine surfaces (fsm-state.yaml, `verify-state`
# JSON, evidence filenames) stay 0-based and are frozen compatibility surfaces;
# only the human-facing MESSAGES gain a suffix, appended AFTER the machine
# values so existing greps on those messages still match.
#
# _fsm_human_step <current> <total> — echoes " (human: ...)" or nothing.
#   current >= total  -> "all T steps complete" (all done; there is no N+1)
#   total == 0        -> nothing (degenerate plan: machine values only)
#   non-integer input -> nothing (the caller's own malformed-state error fires)
#
# P080 Step 13: the wording carries the DISAMBIGUATOR ("is next" / "complete")
# because the underlying field is 0-based and a bare "Plan Step N of T" cannot
# be read against it. The authoritative definition of this wording lives in the
# "Step rendering rule" section of skills/pipeline.md; every prose surface
# references that section instead of restating it.
#
# NO top-level `set -e`/`set -euo pipefail` — sourced under the caller's own
# strict shell (see aid-test-adapter-contract.sh header convention).

_fsm_human_step() {
  local current="${1:-}" total="${2:-}"
  [[ "$current" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ ]] || return 0
  [[ "$total" -gt 0 ]] || return 0
  if [[ "$current" -ge "$total" ]]; then
    printf ' (human: all %s steps complete)' "$total"
  else
    printf ' (human: Plan Step %s of %s is next)' "$((current + 1))" "$total"
  fi
}
