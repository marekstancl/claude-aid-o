#!/usr/bin/env bash
# =============================================================================
# lib/aid-decision-ledger.sh — decisions about the whole-plan review (CP7) that hold for the THING, not for one
# wording of it (AID 3.12.0)
#
#   aid_decision_ledger_path <final run dir>                 evidence/<plan>/pm-decisions.jsonl
#   aid_decision_ledger_append <run dir> <round dir> <fingerprint> <source pm|delegate> <words> <card|verdict file>
#   aid_decision_ledger_revoke <run dir> <round dir> <fingerprint> <words> <card|verdict> [pm|delegate]
#                                                                     a later NO (--pm rejected, the delegate's rejected/fix)
#   aid_decision_ledger_live <ledger>                         the decisions still in force (settle and the review packet)
#   aid_decision_ledger_settle <merged.json> <ledger>        rewrites merged.json; prints how many it settled
#   aid_decision_ledger_verify <run dir>                     0, or 1 with the first reason on stdout
#
# Why: a CP7 finding is fingerprinted by its first citation and the first eight words of its claim. The next round
# words the same problem differently, gets a new fingerprint, and the PM was asked the same question again — three
# times for one brief point in Trading P004 (25. 10. 2026). A PM answer (`dispute --pm accepted`) or a technical
# verdict of the delegate that settles a finding is now ALSO written here, and later rounds and attempts of the
# plan settle the same thing with it:
#   - the same `match` (fingerprint without the citation's line) — PM and delegate decisions — the finding not more
#     severe than the decided one (a blocker only by a decision about a blocker);
#   - PM decisions only: the same FIRST citation `zadani.md:N` (the brief is locked during the close), the finding
#     not a blocker and not more severe than the one the PM decided.
# The LAST entry for a match counts: a later `--pm rejected` revokes it. A finding that already carries a PM answer
# or a delegate's verdict is never rewritten. A delegate's settlement is recorded as the delegate's, not the PM's.
# A settled finding carries `settled_by: <decision id>`. decide checks each settlement against this file AND against
# the plan's own rounds: the decision's finding exists in a cp7 round of the plan with the same answer, card or
# verdict, match, severity and first citation; the card (or verdict) is unchanged; a card quotes the finding; a
# verdict is the delegate's file for that finding (a PM card is copied to evidence/<plan>/decision-cards/ when the
# answer is recorded, so a later card written to the same path cannot unmake it), technical, accepted or dismiss. A line written by hand passes none.
# An accepted RISK (`accept-risk`) is not here: it stays bound to its candidate (P117 (14)).
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_DECISION_LEDGER_SH_LOADED:-}" ]] && return 0
_AID_DECISION_LEDGER_SH_LOADED=1

# the last entry per match wins: a later revocation of the same match — or, for the brief, of the same zadani.md line —
# cancels the decision. One definition, read by settle and by the review packet.
AID_DECISION_LIVE_JQ='def live($all): . as $e
  | ([$all[] | select(.revokes != null) | {k: .revokes, c: (.revokes_first_citation // ""), at: .at}
      | select((.k == $e.match or (.c != "" and (.c | startswith("zadani.md:")) and .c == $e.first_citation)) and .at >= $e.at)]
     | length) == 0;'
# aid_decision_ledger_live <ledger> — the decisions still in force, one JSON line each
aid_decision_ledger_live() {
  [[ -s "$1" ]] || return 0
  jq -c -s "${AID_DECISION_LIVE_JQ}"' . as $d | .[] | select(.revokes == null) | select(live($d))' "$1"
}

aid_decision_ledger_path() { printf '%s/pm-decisions.jsonl' "$(dirname "$1")"; }

aid_decision_ledger_append() {
  local run="$1" rd="$2" fp="$3" src="$4" words="$5" ref="$6" ledger finding first n
  ledger="$(aid_decision_ledger_path "$run")"
  finding="$(jq -c --arg f "$fp" 'first(.findings[] | select(.fingerprint == $f)) // empty' "${rd}/merged.json" 2>/dev/null)"
  [[ -n "$finding" ]] || { echo "decision ledger: no finding ${fp} in ${rd}/merged.json" >&2; return 1; }
  [[ -f "$ref" ]] || { echo "decision ledger: no ${src} record ${ref}" >&2; return 1; }
  local card_was=""
  if [[ "$src" == pm ]]; then
    # the PM's card is kept in the evidence: a later card written to the same path must not unmake the decision
    card_was="$ref"; mkdir -p "$(dirname "$ledger")/decision-cards" || return 1
    ref="$(realpath -m "$(dirname "$ledger")")/decision-cards/$(date -u +%Y%m%dT%H%M%S)-${fp:7:16}.md"; cp "$card_was" "$ref" || return 1
  fi
  first="$(jq -r '(.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; "")' <<< "$finding")"
  n=0; [[ -f "$ledger" ]] && n="$(grep -c '' "$ledger")"
  jq -nc --arg id "d$((n + 1))-${fp:7:12}" --arg plan "$(basename "$(dirname "$run")")" --arg src "$src" \
     --arg w "$words" --arg ref "$ref" --arg rs "$(sha256sum "$ref" | cut -d' ' -f1)" --argjson f "$finding" \
     --arg first "$first" --arg run "$(basename "$run")" --arg round "$(basename "$rd")" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cw "$card_was" \
    '{id: $id, plan: $plan, source: $src, at: $at, words: $w, ref: $ref, ref_sha256: $rs, run: $run, round: $round,
      fingerprint: $f.fingerprint, match: $f.match, severity: $f.severity, rule: ($f.rule // null), claim: $f.claim,
      first_citation: $first} + (if $cw == "" then {} else {card: $cw} end)' >> "$ledger"
}

aid_decision_ledger_revoke() {
  local run="$1" rd="$2" fp="$3" words="$4" ref="$5" ledger m
  ledger="$(aid_decision_ledger_path "$run")"
  [[ -s "$ledger" ]] || return 0
  local fc
  m="$(jq -r --arg f "$fp" 'first(.findings[] | select(.fingerprint == $f)) | .match // empty' "${rd}/merged.json" 2>/dev/null)"
  fc="$(jq -r --arg f "$fp" 'first(.findings[] | select(.fingerprint == $f)) | (.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; "")' "${rd}/merged.json" 2>/dev/null)"
  [[ -n "$m" ]] || return 0
  jq -e -s --arg m "$m" --arg c "$fc" 'any(.[]; .revokes == null and (.match == $m or (.first_citation == $c and ($c | startswith("zadani.md:")))))' "$ledger" >/dev/null 2>&1 || return 0
  jq -nc --arg plan "$(basename "$(dirname "$run")")" --arg m "$m" --arg c "$fc" --arg w "$words" --arg ref "$ref" --arg fp "$fp" \
     --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg src "${6:-pm}" \
    '{id: ("r-" + $fp[7:19]), plan: $plan, source: $src, revokes: $m, revokes_first_citation: $c, at: $at, words: $w, ref: $ref, fingerprint: $fp}' >> "$ledger"
}

aid_decision_ledger_settle() {
  local merged="$1" ledger="$2" tmp n
  [[ -s "$ledger" && -f "$merged" ]] || { echo 0; return 0; }
  tmp="${merged}.settle.$$"
  jq --slurpfile d "$ledger" '
    def rank: {"blocker": 3, "major": 2, "minor": 1}[.] // 0;
    def first_cit: ((.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; ""));
    # the last entry per match wins: a later revocation cancels the decision
    '"${AID_DECISION_LIVE_JQ}"' [$d[] | select(.revokes == null) | select(live($d))] as $dec
    | .findings |= map(
      if (.status | IN("open", "form_invalid")) and (.settled_by == null) and (.dispute.pm == null)
         and (.dispute.delegated == null) and (.delegated == null) and (.dispute.handed_to_confirmation == null) then
        . as $x
        | ([$dec[] | select(.match == $x.match and ($x.severity | rank) <= (.severity | rank))]
           + [$dec[] | select(.source == "pm" and (.first_citation | startswith("zadani.md:"))
                     and .first_citation == ($x | first_cit)
                     and $x.severity != "blocker" and ($x.severity | rank) <= (.severity | rank))]) as $m
        | if ($m | length) == 0 then .
          elif $m[0].source == "pm" then
            .status = "fixed" | .settled_by = $m[0].id
            | .dispute.pm = {answer: "accepted", words: $m[0].words, at: $m[0].at, card: $m[0].ref, settled_by: $m[0].id}
          else
            .status = "fixed" | .settled_by = $m[0].id
            | .dispute.delegated = {answer: "accepted", class: "technical", reason: $m[0].words, verdict_file: $m[0].ref,
                                    verdict_sha256: $m[0].ref_sha256, at: $m[0].at, settled_by: $m[0].id}
          end
      else . end)
    | .blockers_open = ([.findings[] | select(.severity == "blocker" and (.status == "open" or .status == "disputed"))] | length)
  ' "$merged" > "$tmp" || { rm -f "$tmp"; return 1; }
  n="$(jq '[.findings[] | select(.settled_by != null)] | length' "$tmp")"
  mv "$tmp" "$merged" && echo "$n"
}

aid_decision_ledger_verify() {
  local run="$1" ledger plan_dir m fp sb e ref src orig
  ledger="$(aid_decision_ledger_path "$run")"; plan_dir="$(dirname "$run")"
  declare -F aid_delegate_fp16 >/dev/null || aid_delegate_fp16() { local f="${1#sha256:}"; printf '%s' "${f:0:16}"; }
  for m in "$run"/cp7/round-*/merged.json; do
    [[ -f "$m" ]] || continue
    while IFS=$'\t' read -r fp sb; do
      [[ -n "$sb" ]] || continue
      e="$(jq -sc --arg id "$sb" 'first(.[] | select(.id == $id and .revokes == null)) // empty' "$ledger" 2>/dev/null)"
      [[ -n "$e" ]] || { echo "finding ${fp:0:23} is settled by decision ${sb}, which ${ledger##*/} does not hold"; return 1; }
      [[ "$(jq -r .plan <<< "$e")" == "$(basename "$plan_dir")" ]] || { echo "decision ${sb} belongs to another plan"; return 1; }
      ref="$(jq -r .ref <<< "$e")"; src="$(jq -r .source <<< "$e")"
      [[ -f "$ref" && "$(sha256sum "$ref" | cut -d' ' -f1)" == "$(jq -r .ref_sha256 <<< "$e")" ]] \
        || { echo "the record of decision ${sb} (${ref}) is gone or changed after it was given"; return 1; }
      # the decided finding itself, in a cp7 round of this plan, with this very answer
      orig="$(cat "$plan_dir"/*/cp7/round-*/merged.json 2>/dev/null | jq -sc --argjson e "$e" '
        def first_cit: ((.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; ""));
        [.[].findings[]? | select(.fingerprint == $e.fingerprint and .match == $e.match
           and (.settled_by // .dispute.pm.settled_by // .dispute.delegated.settled_by) == null
           and .severity == $e.severity and first_cit == $e.first_citation)
         | select(if $e.source == "pm" then (.dispute.pm.answer == "accepted" and (.dispute.pm.card | IN($e.card, $e.ref)))
                  else (((.delegated // .dispute.delegated) // {}) | .verdict_file == $e.ref and .verdict_sha256 == $e.ref_sha256) end)]
        | length')"
      [[ "${orig:-0}" -ge 1 ]] || { echo "decision ${sb} names a finding that no cp7 round of the plan decided that way"; return 1; }
      local later
      later="$(cat "$plan_dir"/*/cp7/round-*/merged.json 2>/dev/null | jq -sc --argjson e "$e" '
        [.[].findings[]? | select(.match == $e.match and ((.dispute.pm.answer == "rejected" and .dispute.pm.at > $e.at)
           or (((.delegated // .dispute.delegated) // {}) | (.answer | IN("rejected", "fix")) and .at > $e.at)))] | length')"
      [[ "${later:-0}" == 0 ]] || { echo "decision ${sb} was revoked later in the plan (a later NO on the same finding)"; return 1; }
      if [[ "$src" == pm ]]; then
        grep -qwF -- "$(jq -r .fingerprint <<< "$e")" "$ref" \
          || { echo "the card of decision ${sb} does not quote the finding it decided ($(jq -r '.fingerprint[0:23]' <<< "$e"))"; return 1; }
      else
        [[ "$(basename "$ref")" == "adjudicator-delegated-$(aid_delegate_fp16 "$(jq -r .fingerprint <<< "$e")").json" ]] \
          && jq -e '.class == "technical" and (.answer | IN("accepted", "dismiss"))' "$ref" >/dev/null 2>&1 \
          || { echo "decision ${sb}: ${ref##*/} is not the delegate's technical verdict for that finding"; return 1; }
      fi
    done < <(jq -r '.findings[] | (.settled_by // .dispute.pm.settled_by // .dispute.delegated.settled_by) as $s
                    | select($s != null) | "\(.fingerprint)\t\($s)"' "$m")
  done
  return 0
}
