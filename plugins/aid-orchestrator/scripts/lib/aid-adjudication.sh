# aid-adjudication.sh — shared resolver for D5/IMP-468 formal Curator
# adjudication of Auditor findings, used by BOTH the plan-final review
# boundary (aid-plan-fsm.sh's _pfsm_finalize_review) and the .aid-lifecycle
# plan-review classifier (lib/aid-lifecycle.sh's _aid_lc_plan_review_status).
#
# WHY a shared function: a raw Auditor blocker (severity critical|high in
# audit-report.json's findings[]) is never resolved by a bare
# curator.blocking_findings:false — it needs a schema-bound entry in
# curator.adjudications[], bound to THIS exact audit report hash / candidate
# / run. Before this file existed, aid-lifecycle.sh's classifier had NO idea
# adjudications existed at all: it read audit-report.json's raw
# blocking_findings and returned "rejected" unconditionally, even for a plan
# whose review had ALREADY passed the plan-final boundary's own (correct,
# stricter) adjudication gate — permanently misclassifying a legitimately
# adjudicated plan as rejected in the git-tracked .aid-lifecycle layer, with
# no path back to "closed" for it. One resolver, read by both, closes that
# gap structurally rather than by re-deriving the same jq twice and letting
# them drift.
#
# aid_adjudication_resolve <audit_report_file> <curator_report_file>
#                           <candidate_sha> <run_id>
# Echoes a JSON object: {adj_total, adj_valid, unadj_count, unadj_list,
# illegal_fp_count} — the caller decides what each field means for its own
# purpose (aid-plan-fsm.sh blocks the review boundary with a detailed
# message per field; aid-lifecycle.sh only needs unadj_count==0 and
# illegal_fp_count==0 AND adj_total==adj_valid to treat the plan as not
# blocked by adjudication). Returns 1 (echoing nothing) if either file
# cannot be read as JSON.
aid_adjudication_resolve() {
  local audit_file="$1" curator_file="$2" candidate="$3" run_id="$4"
  [[ -f "$audit_file" && -f "$curator_file" ]] || return 1
  local audit_hash; audit_hash="sha256:$(sha256sum "$audit_file" 2>/dev/null | awk '{print $1}')"
  jq -n --slurpfile audit "$audit_file" --slurpfile cur "$curator_file" \
    --arg h "$audit_hash" --arg c "$candidate" --arg r "$run_id" '
    ($audit[0].findings // []) as $findings |
    ($cur[0].curator.adjudications // []) as $adjs |
    ($findings | map(select(.severity == "critical" or .severity == "high"))) as $blocking |
    ($adjs | map(select(
        (.audit_report_sha256 == $h) and (.candidate_sha == $c) and (.run_id == $r) and
        (.disposition == "confirmed" or .disposition == "fixed_in_new_candidate" or .disposition == "false_positive" or .disposition == "requires_pm") and
        (.finding_fingerprint | type == "string") and (.finding_occurrence_id | type == "string") and
        (.evidence_ref | type == "string" and length > 0)
      ))) as $valid_adjs |
    ($blocking | map(
        . as $bf |
        select(
          ([$valid_adjs[] | select(.finding_fingerprint == $bf.fingerprint and .finding_occurrence_id == $bf.occurrence_id)] | length) != 1
        ) | $bf.fingerprint
      )) as $unadjudicated |
    ($blocking | map(
        . as $f | ($valid_adjs[] | select(.finding_fingerprint == $f.fingerprint and .finding_occurrence_id == $f.occurrence_id)) as $adj |
        select(($f.severity == "critical" or $f.action_owner == "pm") and $adj.disposition == "false_positive")
      )) as $illegal_fp |
    {adj_total: ($adjs | length), adj_valid: ($valid_adjs | length),
     unadj_count: ($unadjudicated | length), unadj_list: $unadjudicated,
     illegal_fp_count: ($illegal_fp | length)}
  ' 2>/dev/null
}

# aid_adjudication_fully_resolved <audit_report_file> <curator_report_file>
#                                  <candidate_sha> <run_id>
# Convenience boolean wrapper: 0 (true) iff every critical|high finding is
# validly, exactly adjudicated AND no adjudication entry is malformed/stale
# AND no illegal false_positive disposition was used. 1 otherwise, including
# when either file is unreadable (fail-closed — an unresolvable input is
# never treated as "resolved").
aid_adjudication_fully_resolved() {
  local audit_file="$1" curator_file="$2" candidate="$3" run_id="$4"
  local result; result="$(aid_adjudication_resolve "$audit_file" "$curator_file" "$candidate" "$run_id")" || return 1
  [[ -n "$result" ]] || return 1
  jq -e '(.adj_total == .adj_valid) and (.unadj_count == 0) and (.illegal_fp_count == 0)' \
    <<<"$result" >/dev/null 2>&1
}
