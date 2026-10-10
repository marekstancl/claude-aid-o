#!/usr/bin/env bash
# =============================================================================
# lib/aid-critic.sh — the independent critic's prompt and its answer check
#
#   aid_critic_prepare <plan_id> --moment brainstorm|plan [--plan <path>] [--root <dir>]
#   aid_critic_check   <plan_id> --moment brainstorm|plan [--plan <path>] [--root <dir>]
#   aid_critic_rebind  <plan_id> --plan <path> [--root <dir>]   after the plan was revised for the accepted items
#   aid_critic_dispatch <plan_id> --moment brainstorm|plan [--provider codex|claude] [--root <dir>]
#                      runs the critic (Codex through the shared transport), or prints STAND-IN
#   aid_critic_verdict <plan_id> <plan_sha> [--root <dir>]   is there a passed plan-moment check for
#                      exactly this plan? The review packet and the CP1 gate both ask here (P109)
#
# WHY: the critic was tried twice on the same plan in the agents project (P010,
# 2026-09-28). With cost figures in its context it returned "do not build"; with
# the purpose, the stakes and "assume it is built" it found five defects two CP1
# rounds had missed. Those two ingredients are therefore assembled by code, and
# the answer's shape (two levels, at most five items, no verdict, every item
# answered) is checked by code, so neither can be left out by a controller
# writing a prompt by hand.
#
# Evidence: <state root>/.aid-o/work/evidence/<plan_id>/critic/<moment>/
#   prompt.md · critic.md (the critic) · critic-response.md (the author) · check.json
# NO top-level `set -e` — sourced under the caller's own strict shell.
# =============================================================================
[[ -n "${_AID_CRITIC_SH_LOADED:-}" ]] && return 0
_AID_CRITIC_SH_LOADED=1
_AID_CRITIC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-roots.sh
source "${_AID_CRITIC_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-scoping.sh
source "${_AID_CRITIC_LIB_DIR}/aid-scoping.sh"
# shellcheck source=aid-stage-log.sh
source "${_AID_CRITIC_LIB_DIR}/aid-stage-log.sh"
# shellcheck source=aid-zadani.sh
source "${_AID_CRITIC_LIB_DIR}/aid-zadani.sh"

AID_CRITIC_ROLE_FILE="${_AID_CRITIC_LIB_DIR}/../../skills/critic.md"
AID_CRITIC_ASSUME='Předpokládej, že se to staví.'
# Cost figures never reach the critic (see WHY above).
AID_CRITIC_COST_RE='USD|Kč|\$[0-9]|[[:space:]]token(s|ů|y)?([[:space:][:punct:]]|$)'
AID_CRITIC_SECTION_BRIEF='Zadání PM'
AID_CRITIC_SECTION_STAKES='Účel a co je v sázce'
AID_CRITIC_SECTION_PROPOSAL='Návrh'
AID_CRITIC_L1_RE='^### (Úroveň 1|Level 1)'
AID_CRITIC_L2_RE='^### (Úroveň 2|Level 2)'
AID_CRITIC_ITEM_RE='^\*\*[0-9]+\.'
# A verdict line: an optional item/list prefix, then the forbidden phrase.
AID_CRITIC_VERDICT_RE='^[[:space:]]*(\*\*[0-9]+\.[[:space:]]*|[-*][[:space:]]+|[0-9]+\.[[:space:]]+)?(nestavět|nedělat|nestavte|do not build|don'"'"'?t build)'

_aid_critic_args() {
  # sets: _ac_plan_id _ac_moment _ac_plan _ac_root
  _ac_plan_id="${1-}"; shift || true
  _ac_moment=""; _ac_plan=""; _ac_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --moment) _ac_moment="${2-}"; shift 2 ;;
      --plan)   _ac_plan="${2-}"; shift 2 ;;
      --root)   _ac_root="${2-}"; shift 2 ;;
      *) echo "critic: unknown argument '$1'" >&2; return 1 ;;
    esac
  done
  [[ "$_ac_plan_id" =~ ^P[0-9]+$ ]] || { echo "critic: <plan_id> must look like P107 (got '${_ac_plan_id}')" >&2; return 1; }
  case "$_ac_moment" in brainstorm|plan) ;; *) echo "critic: --moment must be brainstorm or plan (got '${_ac_moment}')" >&2; return 1 ;; esac
  _ac_root="$(aid_state_root "${_ac_root:-${AID_PROJECT_ROOT:-$PWD}}")" || return 1
  if [[ "$_ac_moment" == "plan" && -z "$_ac_plan" ]]; then
    _ac_plan="$(aid_plan_files "${_ac_root}/.aid-o/plans" "$_ac_plan_id" | head -1)"
    [[ -n "$_ac_plan" ]] || { echo "critic: --moment plan needs --plan <path> (no .aid-o/plans/${_ac_plan_id}-*.md found)" >&2; return 1; }
  fi
  return 0
}

_aid_critic_dir() { printf '%s/.aid-o/work/evidence/%s/critic/%s' "$1" "$2" "$3"; }

# _aid_critic_heading_count <file> <name> — how many `## <name>` headings (same
# rule as _aid_plan_section: the name must end at a non-word character).
_aid_critic_heading_count() {
  _aid_blank_fenced < "$1" | awk -v want="## $2" '
    index($0, want) == 1 && substr($0, length(want) + 1, 1) !~ /[A-Za-z0-9]/ { n++ }
    END { print n + 0 }'
}

# _aid_critic_section <interim> <name> — sets _acs_body (the section with cost
# lines stripped) and _acs_stripped (how many). Called directly, never in a
# command substitution: a subshell would lose both. Returns 3 when the section
# is absent or duplicated (the reader would concatenate duplicates).
_aid_critic_section() {
  local file="$1" name="$2" n body kept
  n="$(_aid_critic_heading_count "$file" "$name")"
  if [[ "$n" -eq 0 ]]; then
    echo "critic: interim has no \"## ${name}\" section — write it first" >&2; return 3
  elif [[ "$n" -gt 1 ]]; then
    echo "critic: interim has ${n} \"## ${name}\" headings — merge them (the section reader returns every match)" >&2; return 3
  fi
  body="$(_aid_plan_section "$file" "$name")"
  kept="$(printf '%s\n' "$body" | grep -Ev "$AID_CRITIC_COST_RE" || true)"
  _acs_stripped=$(( $(printf '%s\n' "$body" | grep -c '') - $(printf '%s\n' "$kept" | grep -c '') ))
  _acs_body="$kept"
  return 0
}

# _aid_critic_brief_file <plan> <root> — the brief file the plan names, resolved
# against the project root; nothing when it names none or the file is absent.
_aid_critic_brief_file() {
  local z; z="$(_aid_fm_get "$1" zadani)"
  [[ -n "$z" ]] || return 1
  [[ "$z" == /* ]] || z="$2/$z"
  [[ -f "$z" ]] || return 1
  printf '%s' "$z"
}

# _aid_critic_strip_cost <text> — sets _acs_body/_acs_stripped like _aid_critic_section.
_aid_critic_strip_cost() {
  local kept
  kept="$(printf '%s\n' "$1" | grep -Ev "$AID_CRITIC_COST_RE" || true)"
  _acs_stripped=$(( $(printf '%s\n' "$1" | grep -c '') - $(printf '%s\n' "$kept" | grep -c '') ))
  _acs_body="$kept"
}

aid_critic_prepare() {
  local _ac_plan_id _ac_moment _ac_plan _ac_root
  _aid_critic_args "$@" || return 1
  local interim="${_ac_root}/.aid-o/work/interim-${_ac_plan_id}.md" dir brief stakes subject="" _acs_body _acs_stripped total=0
  local zfile="" source_sha=""
  [[ -f "$AID_CRITIC_ROLE_FILE" ]] || { echo "critic: role text missing at ${AID_CRITIC_ROLE_FILE}" >&2; return 2; }
  # At the plan moment a plan bound to a brief is criticised against the BRIEF
  # FILE (P109): the interim is deleted after CP1, the brief is not, so a
  # critic rerun after a brief change needs no interim.
  # A plan that NAMES a brief the critic cannot read is refused: falling back
  # to an interim would criticise the plan against other input than it names.
  if [[ "$_ac_moment" == "plan" && -f "$_ac_plan" && -n "$(_aid_fm_get "$_ac_plan" zadani)" ]] \
     && ! _aid_critic_brief_file "$_ac_plan" "$_ac_root" >/dev/null; then
    echo "critic: the plan names the brief '$(_aid_fm_get "$_ac_plan" zadani)', which does not exist — fix zadani: or write the brief (aid-plan-lint.sh --zadani)" >&2
    return 2
  fi
  if [[ "$_ac_moment" == "plan" && -f "$_ac_plan" ]] && zfile="$(_aid_critic_brief_file "$_ac_plan" "$_ac_root")"; then
    _aid_critic_strip_cost "$(_aid_plan_section "$zfile" "${AID_ZADANI_HEADINGS[0]}" | awk '/^\*\*Co je v sázce:\*\*/ { exit } { print }')"
    brief="$_acs_body"; total=$(( total + _acs_stripped ))
    _aid_critic_strip_cost "$(aid_zadani_stakes "$zfile")" || true
    [[ -n "${_acs_body// /}" ]] || { echo "critic: the brief ${zfile} has no **Co je v sázce:** paragraph — aid-plan-lint.sh --zadani ${zfile}" >&2; return 3; }
    stakes="$_acs_body"; total=$(( total + _acs_stripped ))
    source_sha="$(sha256sum "$zfile" | cut -d' ' -f1)"
  else
    [[ -f "$interim" ]] || { echo "critic: no interim for ${_ac_plan_id} at ${interim}$( [[ "$_ac_moment" == plan ]] && echo ' (and the plan names no brief file — zadani:)')" >&2; return 2; }
    _aid_critic_section "$interim" "$AID_CRITIC_SECTION_BRIEF" || return 3
    brief="$_acs_body"; total=$(( total + _acs_stripped ))
    _aid_critic_section "$interim" "$AID_CRITIC_SECTION_STAKES" || return 3
    stakes="$_acs_body"; total=$(( total + _acs_stripped ))
    source_sha="$(sha256sum "$interim" | cut -d' ' -f1)"
  fi
  if [[ "$_ac_moment" == "brainstorm" ]]; then
    _aid_critic_section "$interim" "$AID_CRITIC_SECTION_PROPOSAL" || return 3
    subject="$_acs_body"; total=$(( total + _acs_stripped ))
  else
    [[ -f "$_ac_plan" ]] || { echo "critic: plan file not found: ${_ac_plan}" >&2; return 2; }
  fi
  dir="$(_aid_critic_dir "$_ac_root" "$_ac_plan_id" "$_ac_moment")"
  if [[ -f "${dir}/prompt.md" ]]; then
    local keep; keep="$(mktemp -d "${dir}.superseded-$(date -u +%Y%m%dT%H%M%SZ)-XXXX")" || return 2
    rmdir "$keep" && mv "$dir" "$keep" || { echo "critic: could not set aside the previous run at ${dir}" >&2; return 2; }
  fi
  mkdir -p "$dir" || return 2
  {
    echo "# Kritik — ${_ac_plan_id}, okamžik: ${_ac_moment}"
    echo
    # the role without its frontmatter
    awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 { if (/^---$/) fm=2; next } { print }' "$AID_CRITIC_ROLE_FILE"
    echo
    echo "## Zadání PM (doslova)"
    echo
    printf '%s\n' "$brief"
    echo
    echo "## Účel a co je v sázce"
    echo
    printf '%s\n' "$stakes"
    echo
    if [[ "$_ac_moment" == "brainstorm" ]]; then
      echo "## Předmět kritiky: návrh (z interim)"
      echo
      printf '%s\n' "$subject"
    else
      echo "## Předmět kritiky: plán"
      echo
      echo "Plán je v souboru \`${_ac_plan}\`. Přečti ho celý. Kritika z konce brainstormu a odpověď autora, pokud existují, jsou v \`$(_aid_critic_dir "$_ac_root" "$_ac_plan_id" brainstorm)/\` — nehlas totéž znovu, ověř, že plán přijaté výtky nese."
    fi
    echo
    echo "## Předpoklad"
    echo
    echo "$AID_CRITIC_ASSUME"
    echo
    echo "## Kam psát"
    echo
    echo "AID_CRITIC_OUTPUT_LINE"
    [[ "$total" -gt 0 ]] && echo "" && echo "<!-- ${total} cost line(s) stripped from the $( [[ -n "$zfile" ]] && echo brief || echo interim) sections -->"
  } > "${dir}/prompt.tmpl"
  # Two renderings of one prompt: a Claude agent writes the file; Codex runs in
  # a read-only sandbox and cannot, so it prints (9. 10. 2026: `-o` saved its
  # complaint about the sandbox instead of a critique).
  sed "s#^AID_CRITIC_OUTPUT_LINE\$#Odpověď zapiš do \`${dir}/critic.md\` přesně se dvěma nadpisy popsanými výše. Nic jiného neměň.#" "${dir}/prompt.tmpl" > "${dir}/prompt.md"
  sed "s#^AID_CRITIC_OUTPUT_LINE\$#Celou odpověď v předepsaném tvaru (dva nadpisy popsané výše) vypiš jako svou závěrečnou zprávu. Žádný soubor nepiš ani neměň.#" "${dir}/prompt.tmpl" > "${dir}/prompt-codex.md"
  rm -f "${dir}/prompt.tmpl"
  jq -n --arg m "$_ac_moment" --arg plan "${_ac_plan:-}" \
        --arg ps "$( [[ -n "$_ac_plan" ]] && sha256sum "$_ac_plan" | cut -d' ' -f1 || echo '' )" \
        --arg is "$source_sha" --arg src "$( [[ -n "$zfile" ]] && echo brief || echo interim)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{moment:$m, plan:$plan, plan_sha256:$ps, source:$src, source_sha256:$is, prepared_at:$at}
         + (if $src == "interim" then {interim_sha256:$is} else {zadani_sha256:$is} end)' > "${dir}/prepare.json"
  echo "${dir}/prompt.md"
  return 0
}

# _aid_critic_between <file> <from_re> <to_re> — the lines after the first line
# matching <from_re> up to (not including) the first later line matching <to_re>.
_aid_critic_between() {
  awk -v from="$2" -v to="$3" '
    !on && $0 ~ from { on = 1; next }
    on && $0 ~ to { exit }
    on { print }' "$1"
}

_aid_critic_nonblank() { printf '%s\n' "$1" | grep -c '[^[:space:]]' || true; }

aid_critic_check() {
  local _ac_plan_id _ac_moment _ac_plan _ac_root
  _aid_critic_args "$@" || return 1
  local dir answer response l1 l2 items n_items level1_empty=false level2_empty=false rows expected got sha_plan="" reason=""
  dir="$(_aid_critic_dir "$_ac_root" "$_ac_plan_id" "$_ac_moment")"
  answer="${dir}/critic.md"; response="${dir}/critic-response.md"
  [[ -f "${dir}/prompt.md" && -f "${dir}/prepare.json" ]] || { echo "critic: nothing prepared at ${dir} — run aid_critic_prepare first" >&2; return 2; }
  [[ -f "$answer" ]] || { echo "critic: the critic did not write ${answer}" >&2; return 4; }
  # prepare hashed the plan and the prompt names its path; the critic reads the
  # file when it runs. The check judges the FORM of the answer and the response,
  # so a plan that differs from the prepare hash at check time is not "checked
  # against nothing": either the author edited it before the critic ran (the
  # critic then read the edited plan) or after the critique (the one revision
  # the author may make for the accepted items — what a rebind records). Both
  # end in the same state, so the check records the current hash as that one
  # revision (2.114.0, P108: refusing it cost a second critic run of ~115k
  # tokens for the order of two commands). A rebind after that is refused as
  # the second revision it would be.
  local revised=""
  if [[ "$_ac_moment" == "plan" ]]; then
    sha_plan="$(jq -r '.plan_sha256 // ""' "${dir}/prepare.json")"
    local plan_now=""; [[ -f "$_ac_plan" ]] && plan_now="$(sha256sum "$_ac_plan" | cut -d' ' -f1)"
    [[ -n "$plan_now" ]] || reason="plan file not found: ${_ac_plan}"
    [[ -z "$reason" && "$plan_now" != "$sha_plan" ]] && revised="$plan_now"
  fi
  [[ -z "$reason" ]] && { grep -Eq "$AID_CRITIC_L1_RE" "$answer" || reason="missing heading: level 1"; }
  [[ -z "$reason" ]] && { grep -Eq "$AID_CRITIC_L2_RE" "$answer" || reason="missing heading: level 2"; }
  if [[ -z "$reason" ]]; then
    local l1_at l2_at
    l1_at="$(grep -nE "$AID_CRITIC_L1_RE" "$answer" | head -1 | cut -d: -f1)"
    l2_at="$(grep -nE "$AID_CRITIC_L2_RE" "$answer" | head -1 | cut -d: -f1)"
    (( l1_at < l2_at )) || reason="level 2 comes before level 1"
  fi
  if [[ -z "$reason" ]]; then
    l1="$(_aid_critic_between "$answer" "$AID_CRITIC_L1_RE" "$AID_CRITIC_L2_RE")"
    l2="$(_aid_critic_between "$answer" "$AID_CRITIC_L2_RE" '^### ')"
    items="$(printf '%s\n' "$l1" | grep -E "$AID_CRITIC_ITEM_RE" || true)"
    n_items="$( [[ -n "$items" ]] && printf '%s\n' "$items" | grep -c '' || echo 0 )"
    if [[ "$n_items" -gt 5 ]]; then
      reason="level 1 has ${n_items} items, at most five"
    elif [[ "$n_items" -eq 0 ]]; then
      if [[ "$(_aid_critic_nonblank "$l1")" -eq 1 ]] && printf '%s\n' "$l1" | grep -Eiq 'nic|nenašel|nenalezl|nothing|no (finding|item|defect)'; then level1_empty=true
      elif [[ "$(_aid_critic_nonblank "$l1")" -eq 0 ]]; then reason="level 1 is blank — one sentence saying nothing was found, or the items"
      else reason="level 1 not in the prescribed item format (**N. claim** lines)"; fi
    else
      local numbered; numbered="$(printf '%s\n' "$items" | sed -E 's/^\*\*([0-9]+)\..*/\1/' | tr '\n' ' ')"
      [[ "$numbered" == "$(seq 1 "$n_items" | tr '\n' ' ')" ]] || reason="level 1 items are numbered [${numbered% }], expected 1..${n_items} in order"
    fi
    if [[ -z "$reason" ]]; then
      local before_l2
      before_l2="$(awk -v to="$AID_CRITIC_L2_RE" '$0 ~ to { exit } { print }' "$answer")"
      if printf '%s\n' "$before_l2" | grep -Eiq "$AID_CRITIC_VERDICT_RE"; then
        reason="a verdict outside level 2: $(printf '%s\n' "$before_l2" | grep -Ei "$AID_CRITIC_VERDICT_RE" | head -1)"
      fi
    fi
    if [[ -z "$reason" ]]; then
      [[ "$(_aid_critic_nonblank "$l2")" -le 2 && ! "$l2" =~ (^|$'\n')[[:space:]]*[-*] ]] && level2_empty=true
    fi
  fi
  if [[ -z "$reason" ]]; then
    [[ -f "$response" ]] || reason="the author did not write ${response}"
  fi
  if [[ -z "$reason" ]]; then
    rows="$(grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$response" || true)"
    got="$( [[ -n "$rows" ]] && printf '%s\n' "$rows" | sed -E 's/^\|[[:space:]]*([0-9]+).*/\1/' | sort -n | tr '\n' ' ' || echo '' )"
    expected="$( [[ "$n_items" -gt 0 ]] && seq 1 "$n_items" | tr '\n' ' ' || echo '' )"
    if [[ "$got" != "$expected" ]]; then
      reason="response rows [${got% }] do not answer items [${expected% }] exactly once each"
    else
      # an accepted row (verdict column) names the file or command the claim
      # was checked against (the last column) — a backtick elsewhere does not count
      local bad
      bad="$(printf '%s\n' "$rows" | awk -F'|' '$4 ~ /PŘIJATO|přijato|Přijato|accepted|ACCEPTED|Accepted/ && $5 !~ /`/ { print; exit }')"
      [[ -n "$bad" ]] && reason="an accepted row names no checked file or command in its last column: $(printf '%s' "$bad" | cut -c1-80)"
    fi
  fi
  if [[ "$_ac_moment" == "plan" && -f "$_ac_plan" ]]; then sha_plan="$(sha256sum "$_ac_plan" | cut -d' ' -f1)"; fi
  local passed=true; [[ -n "$reason" ]] && passed=false
  jq -n --arg moment "$_ac_moment" --arg plan_sha "$sha_plan" \
     --arg p "$(sha256sum "${dir}/prompt.md" | cut -d' ' -f1)" \
     --arg a "$(sha256sum "$answer" | cut -d' ' -f1)" \
     --arg r "$( [[ -f "$response" ]] && sha256sum "$response" | cut -d' ' -f1 || echo '' )" \
     --argjson items "${n_items:-0}" --argjson l1e "$level1_empty" --argjson l2e "$level2_empty" \
     --argjson rows "$( [[ -n "${rows:-}" ]] && printf '%s\n' "$rows" | grep -c '' || echo 0 )" \
     --argjson passed "$passed" --arg reason "$reason" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg rev "$revised" \
     '{moment:$moment, plan_sha256:$plan_sha, prompt_sha256:$p, answer_sha256:$a, response_sha256:$r,
       headings_ok:($reason|startswith("missing heading")|not), level1_items:$items, level1_empty:$l1e, level2_empty:$l2e,
       verdict_forbidden:($reason|startswith("a verdict")), response_rows:$rows, passed:$passed, reason:$reason, checked_at:$at}
      + (if ($rev != "" and $passed) then {plan_sha256_revised:$rev, rebound_at:$at, revised_before_check:true} else {} end)' \
     > "${dir}/check.json"
  local tl
  if tl="$(aid_plan_timeline "$_ac_root" "$_ac_plan_id")"; then
    jq -nc --arg m "$_ac_moment" --argjson passed "$passed" --arg reason "$reason" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{event:"critic_checked", moment:$m, passed:$passed, reason:$reason, timestamp:$at}' >> "$tl"
  fi
  if [[ -n "$reason" ]]; then
    echo "critic: check FAILED — ${reason}" >&2; return 5
  fi
  if [[ -n "$revised" ]]; then
    if tl="$(aid_plan_timeline "$_ac_root" "$_ac_plan_id")"; then
      jq -nc --arg s "$revised" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{event:"critic_rebound", moment:"plan", plan_sha256_revised:$s, revised_before_check:true, timestamp:$at}' >> "$tl"
    fi
    echo "critic: the plan changed since prepare (${sha_plan:0:12} → ${revised:0:12}); recorded as the one revision — no aid_critic_rebind needed, a further edit needs a new critic run"
  fi
  echo "critic: ${_ac_moment} check passed (${n_items} item(s), level1_empty=${level1_empty}, level2_empty=${level2_empty}) → ${dir}/check.json"
  return 0
}

# aid_critic_rebind <plan_id> --plan <path> — the author revised the plan for the
# accepted items; record the revised plan's hash in check.json so the CP1
# packet carries the checked response for THAT plan. Only after a passed
# check at the plan moment, and only once per check (a second revision needs
# a new critic run: the response no longer describes the plan).
aid_critic_rebind() {
  local _ac_plan_id _ac_moment _ac_plan _ac_root
  _aid_critic_args "$1" --moment plan "${@:2}" || return 1
  local dir; dir="$(_aid_critic_dir "$_ac_root" "$_ac_plan_id" plan)"
  [[ -f "${dir}/check.json" ]] || { echo "critic: no check to rebind at ${dir}" >&2; return 2; }
  [[ "$(jq -r '.passed' "${dir}/check.json")" == "true" ]] || { echo "critic: the check did not pass — fix the answer or the response first" >&2; return 5; }
  [[ "$(jq -r '.plan_sha256_revised // ""' "${dir}/check.json")" == "" ]] || { echo "critic: already rebound once — a further revision needs a new critic run (aid_critic_prepare)" >&2; return 5; }
  [[ -f "$_ac_plan" ]] || { echo "critic: plan file not found: ${_ac_plan}" >&2; return 2; }
  local rsha now; rsha="$(jq -r '.response_sha256' "${dir}/check.json")"
  [[ "$rsha" == "$(sha256sum "${dir}/critic-response.md" | cut -d' ' -f1)" ]] || { echo "critic: critic-response.md was edited after the check — run aid_critic_check again" >&2; return 5; }
  now="$(sha256sum "$_ac_plan" | cut -d' ' -f1)"
  jq --arg s "$now" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {plan_sha256_revised: $s, rebound_at: $at}' "${dir}/check.json" > "${dir}/check.json.tmp" && mv "${dir}/check.json.tmp" "${dir}/check.json"
  local tl
  if tl="$(aid_plan_timeline "$_ac_root" "$_ac_plan_id")"; then
    jq -nc --arg s "$now" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{event:"critic_rebound", moment:"plan", plan_sha256_revised:$s, timestamp:$at}' >> "$tl"
  fi
  echo "critic: response rebound to the revised plan ${now:0:12} → ${dir}/check.json"
}

# aid_critic_verdict <plan_id> <plan_sha> [--root <dir>] — exit 0 when the plan
# moment's check.json passed, its response is unedited since, and it was made
# for <plan_sha> (the checked plan or its one rebound revision); otherwise exit
# 1 printing the reason. ONE answer for the CP1 packet and the CP1 gate (P109):
# two readers of check.json would drift on what "passed for this plan" means.
aid_critic_verdict() {
  local plan_id="${1-}" want="${2-}" root="" dir c
  shift 2 || true
  [[ "${1-}" == --root ]] && root="${2-}"
  root="${root:-${AID_PROJECT_ROOT:-$PWD}}"
  # a project that is not a git repository (a fixture) is its own state root, as in the gate
  root="$(aid_state_root "$root" 2>/dev/null || printf '%s' "$root")"
  dir="$(_aid_critic_dir "$root" "$plan_id" plan)"; c="${dir}/check.json"
  [[ -d "$dir" ]] || { echo "evidence missing — the critic did not run at the plan moment (${dir})"; return 1; }
  [[ -f "$c" ]] || { echo "no check.json — aid_critic_check was not run"; return 1; }
  [[ "$(jq -r '.passed // false' "$c" 2>/dev/null)" == true ]] || { echo "the check did not pass: $(jq -r '.reason // "unreadable"' "$c" 2>/dev/null)"; return 1; }
  [[ -f "${dir}/critic-response.md" && "$(jq -r '.response_sha256 // ""' "$c")" == "$(sha256sum "${dir}/critic-response.md" | cut -d' ' -f1)" ]] \
    || { echo "critic-response.md was edited after the check"; return 1; }
  if [[ "$(jq -r '.plan_sha256 // ""' "$c")" != "$want" && "$(jq -r '.plan_sha256_revised // ""' "$c")" != "$want" ]]; then
    echo "the check was made for another plan ($(jq -r '.plan_sha256 // ""' "$c" | cut -c1-12)) — aid_critic_rebind after the one revision, or a new critic run"
    return 1
  fi
  return 0
}

# aid_critic_dispatch <plan_id> --moment brainstorm|plan [--provider codex|claude] [--root <dir>]
#   codex (default): one fresh read-only Codex through _run_codex_isolated with
#   prompt-codex.md (print, do not write); its last message IS critic.md, inside
#   the dispatch bracket. A non-zero exit (124 = timeout), an unusable probe or
#   fewer than two level headings in the answer → the STAND-IN line and exit 4,
#   as the brainstorm opponent does: the controller dispatches prompt.md to a
#   Claude agent at the policy's stand_in_model. claude: prints that line, exit 4.
aid_critic_dispatch() {
  local plan_id="${1-}" moment="" provider=codex root="" dir rc=0 why=""
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --moment) moment="${2-}"; shift 2 ;;
      --provider) provider="${2-}"; shift 2 ;;
      --root) root="${2-}"; shift 2 ;;
      *) echo "critic: unknown argument '$1'" >&2; return 1 ;;
    esac
  done
  [[ "$plan_id" =~ ^P[0-9]+$ ]] || { echo "critic: <plan_id> must look like P107" >&2; return 1; }
  case "$moment" in brainstorm|plan) ;; *) echo "critic: --moment must be brainstorm or plan" >&2; return 1 ;; esac
  root="$(aid_state_root "${root:-${AID_PROJECT_ROOT:-$PWD}}")" || return 1
  dir="$(_aid_critic_dir "$root" "$plan_id" "$moment")"
  [[ -f "${dir}/prompt.md" && -f "${dir}/prompt-codex.md" ]] || { echo "critic: nothing prepared at ${dir} — run aid_critic_prepare first" >&2; return 2; }
  local stand_in=opus
  # shellcheck source=aid-review-config.sh
  source "${_AID_CRITIC_LIB_DIR}/aid-review-config.sh"
  if aid_review_config_load "$root" plan_review "${_AID_CRITIC_LIB_DIR}/../../skills/plan-review-roles.md" >/dev/null 2>&1; then
    stand_in="${RC_STAND_IN_MODEL:-opus}"
    local i; for i in "${!RC_PROVIDER[@]}"; do
      [[ "${RC_PROVIDER[$i]}" == codex ]] && { CODEX_MODEL="${RC_MODEL[$i]}"; CODEX_EFFORT="${RC_EFFORT[$i]}"; break; }
    done
  fi
  _aid_critic_stand_in() {
    echo "STAND-IN: ${1}; dispatch ${dir}/prompt.md to a general-purpose agent at model ${stand_in} (it writes ${dir}/critic.md), then write critic-response.md and run aid_critic_check" >&2
    return 4
  }
  [[ "$provider" == claude ]] && { _aid_critic_stand_in "provider claude asked"; return 4; }
  [[ "$provider" == codex ]] || { echo "critic: --provider must be codex or claude" >&2; return 1; }
  # shellcheck source=aid-codex-transport.sh
  source "${_AID_CRITIC_LIB_DIR}/aid-codex-transport.sh"
  local probe; probe="$(AID_PROJECT_ROOT="$root" aid_codex_probe 2>/dev/null)"
  if [[ "$(jq -r '.available // false' <<< "$probe" 2>/dev/null)" != true ]]; then
    _aid_critic_stand_in "codex is unavailable ($(jq -r '.reason // "unknown"' <<< "$probe" 2>/dev/null))"; return 4
  fi
  local emit="${_AID_CRITIC_LIB_DIR}/../aid-emit-dispatch.sh"
  bash "$emit" start --focus "critic-${moment}" --agent-id "codex:${CODEX_MODEL}" --evidence-dir "$dir" >/dev/null 2>&1 || true
  rm -f "${dir}/critic.md"
  _run_codex_isolated "$root" "${dir}/prompt-codex.md" "${dir}/codex-events.jsonl" "${dir}/codex-stderr.log" "${dir}/critic.md" || rc=$?
  [[ -f "${dir}/critic.md" ]] || : > "${dir}/critic.md"
  bash "$emit" complete --focus "critic-${moment}" --output-file "${dir}/critic.md" --evidence-dir "$dir" >/dev/null 2>&1 || true
  if (( rc != 0 )); then
    why="codex exited ${rc}$( (( rc == 124 )) && echo ' (timeout)')"
  elif ! grep -qE "$AID_CRITIC_L1_RE" "${dir}/critic.md" || ! grep -qE "$AID_CRITIC_L2_RE" "${dir}/critic.md"; then
    why="codex answered without the two level headings (a refusal or a complaint is not a critique)"
  fi
  if [[ -n "$why" ]]; then
    mv "${dir}/critic.md" "${dir}/critic-codex-rejected.md" 2>/dev/null || true
    _aid_critic_stand_in "$why"; return 4
  fi
  echo "critic: Codex answered → ${dir}/critic.md; write critic-response.md, then aid_critic_check ${plan_id} --moment ${moment}"
  return 0
}
