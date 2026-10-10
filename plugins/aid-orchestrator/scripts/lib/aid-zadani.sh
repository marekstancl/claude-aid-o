#!/usr/bin/env bash
# =============================================================================
# lib/aid-zadani.sh — the ONE reader of a brief file `.aid-o/plans/P<NNN>-zadani.md`
# (P109 Step 1; template defaults/templates/zadani.md)
#
#   aid_zadani_sections <file>   the six `## ` headings in order, one per line;
#                                exit 2 naming a missing, doubled, misordered or empty one
#   aid_zadani_stakes <file>     the `**Co je v sázce:**` paragraph of section 1; exit 2 when absent
#   aid_zadani_points <file>     one record per done-when point, in the format of
#                                _aid_vp_parse_ac (label, text, type, cmd, file, regex,
#                                expected_exit — 0x1F-separated); exit 2 on a gap, a
#                                duplicate, a point without a block within 5 lines,
#                                or a block _aid_vp_validate refuses
#   aid_zadani_sha256 <file>     sha256 of the whole file
#
# Every refusal prints `zadani: <file>:<line>: <what is wrong>` to stderr. No
# other script parses a brief: the plan lint, the critic and the review packet
# come here.
#
# WHY: in the P014 experiment (8. 10. 2026) the brief lived only in the interim,
# the plan rewrote point 2, and nothing compared the two. A brief that is a
# file with numbered points is something the lint, the review and fix-check
# can hold the plan to.
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_ZADANI_SH_LOADED:-}" ]] && return 0
_AID_ZADANI_SH_LOADED=1
_AID_ZADANI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-scoping.sh
source "${_AID_ZADANI_LIB_DIR}/aid-scoping.sh"
# shellcheck source=aid-verification-pattern.sh
source "${_AID_ZADANI_LIB_DIR}/aid-verification-pattern.sh"

# The contract: these six headings, in this order. The template is the authority;
# a second language set would be a second parser.
AID_ZADANI_HEADINGS=(
  "1. Co PM chce"
  "2. Změřený výchozí stav"
  "3. Co udělat"
  "4. Kde co je"
  "5. Pravidla práce"
  "6. Hotovo, když"
)
AID_ZADANI_DONE_HEADING="6\\. Hotovo, když"

_aid_zadani_err() { echo "zadani: $1" >&2; }

# _aid_zadani_strip_comments — stdin without <!-- … --> (also multi-line): the
# template's guidance comments are not content.
_aid_zadani_strip_comments() {
  awk '{
    line = $0; out = ""
    while (1) {
      if (inc) { e = index(line, "-->"); if (!e) { line = ""; break } line = substr(line, e + 3); inc = 0 }
      s = index(line, "<!--"); if (!s) { out = out line; break }
      out = out substr(line, 1, s - 1); line = substr(line, s + 4); inc = 1
    }
    print out
  }'
}

aid_zadani_sections() {
  local f="$1" bad=0 i want ln count prev=0 body
  [[ -f "$f" ]] || { _aid_zadani_err "$f: not found"; return 2; }
  for i in "${!AID_ZADANI_HEADINGS[@]}"; do
    want="${AID_ZADANI_HEADINGS[$i]}"
    # line numbers of headings that are this one (fence-blanked: a quoted
    # heading inside an example is not a section)
    ln="$(_aid_blank_fenced < "$f" | awk -v w="## $want" '
      index($0, w) == 1 && substr($0, length(w) + 1, 1) !~ /[[:alnum:]]/ { print NR }')"
    count="$(grep -c . <<< "$ln")"
    if [[ "$count" -eq 0 ]]; then
      _aid_zadani_err "$f: section \"## $want\" is missing"; bad=1; continue
    fi
    if [[ "$count" -gt 1 ]]; then
      _aid_zadani_err "$f:$(sed -n 2p <<< "$ln"): section \"$want\" appears twice"; bad=1; continue
    fi
    if [[ "$ln" -lt "$prev" ]]; then
      _aid_zadani_err "$f:$ln: section \"$want\" is out of order (the six sections go 1 to 6)"; bad=1
    fi
    prev="$ln"
    body="$(_aid_plan_section "$f" "$want" | _aid_zadani_strip_comments | grep -v '^[[:space:]]*$')"
    [[ -n "$body" ]] || { _aid_zadani_err "$f:$ln: section \"$want\" is empty"; bad=1; }
  done
  (( bad )) && return 2
  printf '%s\n' "${AID_ZADANI_HEADINGS[@]}"
}

aid_zadani_stakes() {
  local f="$1" out
  [[ -f "$f" ]] || { _aid_zadani_err "$f: not found"; return 2; }
  out="$(_aid_plan_section "$f" "${AID_ZADANI_HEADINGS[0]}" | _aid_zadani_strip_comments | awk '
    /^\*\*Co je v sázce:\*\*/ { on = 1 }
    on && /^[[:space:]]*$/ { exit }
    on')"
  [[ -n "$out" ]] || { _aid_zadani_err "$f: section 1 has no paragraph starting **Co je v sázce:**"; return 2; }
  # the label alone is not a paragraph
  [[ -n "$(sed '1s/^\*\*Co je v sázce:\*\*//' <<< "$out" | tr -d '[:space:]')" ]] \
    || { _aid_zadani_err "$f: the **Co je v sázce:** paragraph is empty — say who pays what when this goes wrong"; return 2; }
  printf '%s\n' "$out"
}

aid_zadani_points() {
  local f="$1" bad=0 rec label text type acl bl n expect=1 msg out="" blk ln
  local -A seen=()
  [[ -f "$f" ]] || { _aid_zadani_err "$f: not found"; return 2; }
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    IFS=$'\x1f' read -r label text type _ _ _ _ acl bl <<< "$rec"
    if [[ ! "$label" =~ ^AC([0-9]+)$ ]]; then
      continue   # reported below with the other checkboxes that carry no AC<n>
    fi
    n="${BASH_REMATCH[1]}"
    if [[ -n "${seen[$n]:-}" ]]; then
      _aid_zadani_err "$f:$acl: AC$n appears twice (first at line ${seen[$n]})"; bad=1; continue
    fi
    seen[$n]="$acl"
    if [[ "$n" -ne "$expect" ]]; then
      _aid_zadani_err "$f:$acl: AC$n follows AC$((expect - 1)) — the points are numbered AC1, AC2, … without a gap"; bad=1
    fi
    expect=$((n + 1))
    [[ -n "${text// /}" ]] || { _aid_zadani_err "$f:$acl: AC$n has no text — say what is true when it is done"; bad=1; }
    if [[ "$type" == no_verification || "$bl" -eq 0 || $((bl - acl)) -gt 5 ]]; then
      _aid_zadani_err "$f:$acl: AC$n has no verification_pattern block within 5 lines"; bad=1; continue
    fi
    # the block itself, raw: its first key and, for cmd, an explicit expected_exit
    blk="$(awk -v s="$bl" 'NR > s && /^[[:space:]]*```/ { exit } NR > s { sub(/^[[:space:]]+/, ""); print }' "$f")"
    [[ "$(grep -v '^$' <<< "$blk" | head -1)" == verification_pattern:* ]] \
      || { _aid_zadani_err "$f:$bl: AC$n: the block's first key must be verification_pattern:"; bad=1; }
    if [[ "$type" == cmd ]] && ! grep -qE '^expected_exit:' <<< "$blk"; then
      _aid_zadani_err "$f:$bl: AC$n: a cmd block names its expected_exit"; bad=1
    fi
    while IFS= read -r msg; do
      [[ -n "$msg" ]] && { _aid_zadani_err "$f:$bl: AC$n: $msg"; bad=1; }
    done < <(_aid_vp_validate "$rec")
    out+="$(cut -d$'\x1f' -f1-7 <<< "$rec")"$'\n'
  done < <(_aid_vp_parse_ac "$f" "$AID_ZADANI_DONE_HEADING" --lines)
  # a checkbox the parser does not take (no AC<n>) is a point nobody can reference
  while IFS=: read -r ln _; do
    [[ -n "$ln" ]] && { _aid_zadani_err "$f:$ln: a done-when point must be \"- [ ] AC<n>: <text>\""; bad=1; }
  done < <(_aid_blank_fenced < "$f" | awk -v w="## ${AID_ZADANI_HEADINGS[5]}" '
      index($0, w) == 1 { on = 1; next } /^## / { on = 0 }
      on && /^- \[[ x]\] / && $0 !~ /^- \[[ x]\] AC[0-9]+:/ { print NR ":" }')
  if [[ "$expect" -eq 1 ]]; then
    _aid_zadani_err "$f: section \"${AID_ZADANI_HEADINGS[5]}\" has no point \"- [ ] AC1: …\""; bad=1
  fi
  (( bad )) && return 2
  printf '%s' "$out"
}

aid_zadani_sha256() {
  [[ -f "$1" ]] || { _aid_zadani_err "$1: not found"; return 2; }
  sha256sum "$1" | cut -d' ' -f1
}
