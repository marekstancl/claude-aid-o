#!/usr/bin/env bash
# aid-unmeasured.sh — which brief points were NOT measured (P112 Step 2).
#
# A point the measurer could not run (no isolation, no verification env, a
# stripped or unset variable, or its time limit ran out) keeps verdict
# `absent` in plan-diff.json but is UNMEASURED: increment-step and the close
# name it as such, never as a missing change and never as verified. One list,
# read by aid-plan-diff.sh, aid-release-policy.sh and aid-fsm.sh.

AID_PD_UNMEASURED_RE='^(no_isolation|no_verification_env|verification_env_unset|env_stripped|timeout)'

# aid_pd_unmeasured_line <row-json> — the one sentence for an unmeasured row.
aid_pd_unmeasured_line() {
  jq -r 'if .reason == "timeout" then
      "\(.ac_label) (timeout: neměřeno, limit \(.timeout_s // "?") s nestačil — změř znovu s delším limitem: AID_PLAN_DIFF_AC_TIMEOUT_FLOOR=<s> (max 1800) před aid-review-round.sh prepare --checkpoint cp2 --step <N> (po kroku) nebo aid-plan-fsm.sh plan-finalize <plán> --stage produce (při uzávěru); plán se za běhu neupravuje, příští plán dá bodu timeout:)"
    else "\(.ac_label) (\(.reason))" end' <<< "$1"
}
