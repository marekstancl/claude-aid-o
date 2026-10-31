#!/usr/bin/env bash
# =============================================================================
# lib/aid-follow-up.sh — what a CP7 confirmation round leaves for after the close (AID 3.12.0)
#
#   aid_follow_up_added_lines <fix.patch>              "path:line" of every line the fix added or changed (+ side)
#   aid_follow_up_mark <round dir> <run dir> <root>    marks follow_up findings in merged.json, appends them to
#                                                      evidence/<plan>/follow-ups.jsonl; prints how many
#   aid_follow_up_live <plan evidence dir>             the lines of follow-ups.jsonl still owed: minus every match the
#                                                      newest attempt's last cp7 round reports as anything else
#
# A confirmation round (round.json mode: confirmation, with packet/fix.patch) reviews the fix, not the plan again.
# A NEW finding there — its match is not among the confirmed round's open findings — becomes `follow_up` (does not
# block the close; recorded for the project's backlog) only when ALL hold:
#   - it is not a blocker (a blocker always blocks);
#   - it is not a finding still open in the confirmed round said again: not its match, its rule or its first file;
#   - it is not the brief's: no `final_criteria` among its reporters, its first citation neither `zadani.md:*` nor
#     the plan file (.aid-o/plans/…) — a brief point weakened by a fix counts wherever it shows;
#   - its first citation is `path:line` or `path:a-b` of a file in the candidate's repository, and NO line of it is a
#     line the fix added or changed. A `<sha>:path:line`, an `absent:path`, a path of another repository, or a round
#     without a fix.patch never yields a follow-up.
# Statuses that count findings as open never include `follow_up`; a follow_up is protected like any other verdict
# (close records merged.json in stage-writes.jsonl).
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_FOLLOW_UP_SH_LOADED:-}" ]] && return 0
_AID_FOLLOW_UP_SH_LOADED=1

aid_follow_up_added_lines() {
  # A hunk is read by its @@ counts, so an added line that itself starts with "++ " is a line, not a file header.
  awk '
    function cnt(x, a) { split(x, a, ","); return (a[2] == "" ? 1 : a[2] + 0) }
    !inh && /^\+\+\+ / { f = $0; sub(/^\+\+\+ (b\/)?/, "", f); next }
    !inh && /^--- /    { next }
    /^@@ / { n = substr($3, 2); sub(/,.*/, "", n); n += 0; ro = cnt(substr($2, 2)); rn = cnt(substr($3, 2)); inh = (ro + rn > 0); next }
    inh && /^\+/ { if (f != "/dev/null") print f ":" n; n++; rn-- }
    inh && /^-/  { ro-- }
    inh && /^ /  { n++; ro--; rn-- }
    inh && ro <= 0 && rn <= 0 { inh = 0 }
  ' "$1"
}

aid_follow_up_mark() {
  local rd="$1" run="$2" root="$3" patch n
  [[ "$(jq -r '.mode // "full"' "${rd}/round.json" 2>/dev/null)" == confirmation ]] || { echo 0; return 0; }
  patch="${rd}/packet/fix.patch"
  [[ -f "$patch" && -f "${rd}/packet/open-findings.json" && -f "${rd}/merged.json" ]] || { echo 0; return 0; }
  # both lists go to jq through files: a repository of thousands of files does not fit on a command line
  # (`jq: Argument list too long`, WAN P116 28. 10. and P118 30. 10. 2026 — no follow-up was ever marked there)
  # the lists in a directory of their own outside the evidence: an interrupted run leaves nothing in the round
  local tmp="${rd}/merged.json.fu.$$" head lists; lists="$(mktemp -d)" || return 1
  aid_follow_up_added_lines "$patch" | jq -R . | jq -s . > "${lists}/added" || { rm -rf "$lists"; return 1; }
  # the reviewed candidate's files (its tree, not the checkout's index): a citation of another repository's file is never a follow-up
  head="$(jq -r '.head_sha // "HEAD"' "${rd}/round.json")"
  git -C "$root" ls-tree -r --name-only "$head" | jq -R . | jq -s . > "${lists}/tracked" || { rm -rf "$lists"; return 1; }
  jq --slurpfile added "${lists}/added" --slurpfile tracked "${lists}/tracked" --slurpfile open "${rd}/packet/open-findings.json" \
     --arg round "$(basename "$rd")" --arg run "$(basename "$run")" '
    ([$open[0].findings[]?.match] | map(select(. != null))) as $openm
    # a finding still open there, reworded or cited at another place, is that finding, not a new one: its rule or the
    # file of its first citation keeps any new finding with the same rule or file open (whole-change review, 3.12.0)
    | ([$open[0].findings[]? | .rule // empty | select(. != "")]) as $openr
    | ([$open[0].findings[]? | ((.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; "") | sub(":[0-9].*$"; ""))
        | select(. != "")]) as $openf
    | ($added[0] | map({(.): true}) | add // {}) as $isadd
    | ($tracked[0] | map({(.): true}) | add // {}) as $istr
    | def first_cit: ((.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; ""));
      def fu_ok:
        (first(first_cit | capture("^(?<p>[^:\\s]+):(?<a>[0-9]+)(-(?<b>[0-9]+))?$")) // null) as $c   # no match = null, never empty: an empty here would DROP the finding
        | $c != null and ($c.p | startswith("/") | not) and ($c.p != "zadani.md") and ($c.p | startswith(".aid-o/plans/") | not)
          and ($istr[$c.p] // false)
          and ((($c.b // $c.a) | tonumber) >= ($c.a | tonumber))
          and ([range(($c.a | tonumber); (($c.b // $c.a) | tonumber) + 1)] | all(. as $l | ($isadd["\($c.p):\($l)"] // false) | not));
    .findings |= map(
      if .status == "open" and .severity != "blocker" and (.settled_by == null)
         and ((.match // "") | IN($openm[]) | not)
         and ((.rule // "") as $r | $r == "" or ($r | IN($openr[]) | not))
         and (first_cit | sub(":[0-9].*$"; "") | IN($openf[]) | not)
         and ((.reported_by // []) | index("final_criteria") | not)
         and fu_ok
      then .status = "follow_up" | .follow_up = {round: $round, run: $run} else . end)
  ' "${rd}/merged.json" > "$tmp" || { rm -f "$tmp"; rm -rf "$lists"; return 1; }
  rm -rf "$lists"; mv "$tmp" "${rd}/merged.json" || { rm -f "$tmp"; return 1; }
  # the plan's list, one line per thing (match), for the close card and the project's backlog
  local list; list="$(dirname "$run")/follow-ups.jsonl"
  jq -c --arg round "$(basename "$rd")" --arg run "$(basename "$run")" '
    def first_cit: ((.evidence // "") | split(";")[0] | gsub("^\\s+|\\s+$"; ""));
    .findings[] | select(.status == "follow_up")
    | {fingerprint, match, severity, claim, evidence, first_citation: first_cit, fix, round: $round, run: $run}' "${rd}/merged.json" \
  | while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      [[ -f "$list" ]] && jq -e -s --arg m "$(jq -r .match <<< "$line")" 'any(.[]; .match == $m)' "$list" >/dev/null 2>&1 && continue
      printf '%s\n' "$line" >> "$list"
    done
  n="$(jq '[.findings[] | select(.status == "follow_up")] | length' "${rd}/merged.json")"
  echo "$n"
}

aid_follow_up_live() {
  local f="$1/follow-ups.jsonl" last run
  [[ -s "$f" ]] || return 0
  run="$(ls -d "$1"/R-*-final-* 2>/dev/null | grep -E -- '-final-[0-9]+$' | sort -V | tail -1)"
  last="$(ls -d "${run}"/cp7/round-* 2>/dev/null | grep -E '/round-[0-9]+$' | sort -V | tail -1)"
  if [[ -n "$last" && -f "${last}/merged.json" ]]; then
    jq -c --slurpfile m "${last}/merged.json" \
      '([$m[0].findings[] | select(.status != "follow_up") | .match]) as $gone | select(.match | IN($gone[]) | not)' "$f"
  else
    cat "$f"
  fi
}
