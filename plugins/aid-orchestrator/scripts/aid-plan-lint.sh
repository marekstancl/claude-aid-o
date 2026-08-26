#!/usr/bin/env bash
# =============================================================================
# aid-plan-lint.sh — plan-time Files-shape lint (v1: Files entries only)
#
# Catches malformed **Files:** entries AT PLAN-WRITE TIME, before the plan is
# split into EPICs — instead of letting them blow up phase-by-phase in the
# generation-time D5 allowed_paths_shape gate. It shares the SAME extraction
# (_aid_extract_files_bullets), cleaner (_aid_split_path_entry) and shape
# predicate (_aid_path_shape_ok) as the generator + contract gate via
# lib/aid-scoping.sh, so a plan that passes this lint provably passes the gate.
#
# Two blocking tiers (see _aid_classify_files_bullet) plus one advisory:
#   ERROR  — the shared cleaner yields no path or a bad-shape path. This WILL
#            break EPIC generation, so it is ALWAYS blocking (strict + legacy).
#   STRICT — the cleaner rescues a clean path but the entry is non-canonical
#            (no `backtick` path, or a non-(lines …) parenthetical). Blocking
#            for lifecycle_strict plans (new default); a loud advisory for
#            legacy plans (never a sudden global block of already-working plans).
#   ADVISORY — a backticked, path-shaped token that appears only in an entry's
#            DESCRIPTION, so it is not in the step's allowed_paths (P079 Step 5,
#            IMP-480 — the live P076 drop shape). Never blocking in either mode:
#            a description path is as often a reference as a forgotten scope
#            entry, and only the author can tell them apart.
#
# HUMAN-AUDIENCE SECTIONS (P084 Step 5)
# A plan carrying `## Stakeholder Brief` (or one of three siblings) is carrying
# a hand-written copy of a page that is now rendered from the plan's own facts.
# Same STRICT tier.
#
# TESTING STRATEGY (P084 Step 4)
# The plan must carry a `## Testing Strategy` section with content. It replaces
# the per-step `Test:` bullet as the thing generation cares about: a bullet per
# step measured coverage by counting, which is how a portfolio grows tests
# nobody asked for. Same STRICT tier as below.
#
# BAND-SCOPED STEP OBLIGATIONS (P084 Step 3)
# The lint also checks the per-step fields the plan's ceremony BAND asks for.
# The band comes from lib/aid-plan-band.sh — the same single classification
# aid-cp1-gate.sh enforces on and the plan author writes against (skills/plan-writing.md
# §"Obligations by ceremony band"), never a second derivation here. `full` and
# `medium` owe **Architecture Context**, **Error Handling** and **Edge Cases**
# per step; `light` owes none of them and is checked for none. A band that
# cannot be classified reads as `full`, matching the gate's own fail-closed.
# These findings are STRICT tier: blocking for a lifecycle_strict plan, a loud
# advisory for a legacy one — the same two-tier treatment the Files grammar
# gets, and for the same reason.
#
# Usage: aid-plan-lint.sh <plan.md> [--strict|--legacy] [--quiet]
# Exit:  0 = no blocking violations   1 = blocking violation(s)   2 = usage/IO
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"
# shellcheck source=lib/aid-plan-band.sh
source "${SCRIPT_DIR}/lib/aid-plan-band.sh"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-reuse-verdict.sh
source "${SCRIPT_DIR}/lib/aid-reuse-verdict.sh"
# shellcheck source=lib/aid-standards-map.sh
source "${SCRIPT_DIR}/lib/aid-standards-map.sh"

PLAN=""
FORCE_MODE=""     # "strict" | "legacy" | "" (=auto from frontmatter)
QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) FORCE_MODE="strict"; shift ;;
    --legacy) FORCE_MODE="legacy"; shift ;;
    --quiet)  QUIET=1; shift ;;
    -*) echo "aid-plan-lint: unknown option: $1" >&2; exit 2 ;;
    *)  PLAN="$1"; shift ;;
  esac
done

[[ -n "$PLAN" ]] || { echo "Usage: aid-plan-lint.sh <plan.md> [--strict|--legacy] [--quiet]" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "aid-plan-lint: file not found: $PLAN" >&2; exit 2; }

# Strict cohort = plans that opted into the lifecycle model (new template default).
# Legacy plans (no flag) get advisory-only STRICT handling.
mode="$FORCE_MODE"
if [[ -z "$mode" ]]; then
  if grep -qE '^lifecycle_strict:[[:space:]]*true' "$PLAN" 2>/dev/null; then mode="strict"; else mode="legacy"; fi
fi

errors=0
strict_hits=0
advisories=0

# WHICH BANDS OWE WHICH OF THIS PROGRAM'S OBLIGATIONS — one table, read by the
# four checks below. It used to be four separate `[[ "$band" != "light" ]]`
# tests scattered through the file, which is four places to edit for the next
# obligation and four places for them to disagree.
#
# The CP1 gate reads its half of the ceremony from
# defaults/policies/review-checkpoints.yaml; this half is not yet in that file,
# and moving it there is a real improvement that needs its own schema, reader
# and tests. Recorded rather than half-done: what is fixed here is that the
# matrix has ONE authority inside this program.
_AID_LINT_BAND_OBLIGATIONS=(
  "step_fields:full medium"          # Architecture Context / Error Handling / Edge Cases
  "reuse_check:full medium light"    # every band — founding a duplicate is what small plans do
  "standards:full medium"
  "documentation:full medium"
)

# _band_owes <obligation> — does this plan's band owe it?
_band_owes() {
  local entry
  for entry in "${_AID_LINT_BAND_OBLIGATIONS[@]}"; do
    [[ "${entry%%:*}" == "$1" ]] || continue
    [[ " ${entry#*:} " == *" ${band} "* ]] && return 0
    return 1
  done
  # An obligation absent from the table is owed by everyone: the fail-closed
  # direction, matching the gate's own treatment of an unknown band.
  return 0
}

# _advisory <location-suffix> <message> — the advisory twin of _strict_finding.
# One owner of the counter and the --quiet check, so a new advisory cannot
# half-implement either. `location-suffix` is ":<lineno>" or "".
_advisory() {
  advisories=$((advisories+1))
  [[ "$QUIET" -eq 0 ]] || return 0
  echo "${PLAN}${1}: [ADVISORY] ${2}" >&2
  return 0
}

# _prose_paths <bullet> — P079 Step 5 (IMP-480), the drop shape the live P076
# run actually hit. Its Files bullet was CANONICAL and parsed fine:
#
#   - Test: `…/test-skill-lint.sh` — … plus a grep test in
#     `…/bats/test-instruction-closure.bats` asserting every agent card …
#
# Only the first path is a scope declaration; the second lives in the
# description, so it never reached allowed_paths — and the implementer was
# then forbidden to touch a file the step's own plan text assigned to it.
#
# ADVISORY, never blocking, deliberately: a backticked path after the em dash
# is just as often a legitimate REFERENCE ("mirroring `aid-fsm.sh`'s call
# shape") as a forgotten scope entry, and only the plan author can tell them
# apart. The lint's job here is to say the sentence out loud at plan-write
# time; the hard refusal ships where the answer is unambiguous (generation
# fails on a bullet it cannot parse at all).
#
# Echoes one path per line: backticked, path-shaped tokens found AFTER the
# em dash that are not among the bullet's declared paths.
_prose_paths() {
  local bullet="${1#- }" body prose declared tok
  body="$(_aid_files_bullet_body "$bullet")" || true
  # Nothing after the em dash (or "--") means no description to mine — that
  # early return, and the backtick-pair loop condition below, are the whole
  # precondition. A separate backtick-count precheck was tried and removed: it
  # skipped a bullet whose declared path was unbackticked and whose prose
  # carried the only pair.
  case "$body" in
    *$'\xe2\x80\x94'*) prose="${body#*$'\xe2\x80\x94'}" ;;
    *--*)              prose="${body#*--}" ;;
    *)                 return 0 ;;
  esac
  declared="$(_aid_split_path_entry "$body" 2>/dev/null)" || declared=""
  # What NAMES a file is the shared reader's question (lib/aid-scoping.sh);
  # what makes such a name an advisory is this function's: it is in the prose
  # and not among the bullet's declared paths.
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    # Already declared? Pure-bash membership — one fork per token adds up on a
    # sixty-bullet plan that prints nothing.
    [[ $'\n'"$declared"$'\n' == *$'\n'"$tok"$'\n'* ]] && continue
    printf '%s\n' "$tok"
  done < <(_aid_backtick_paths "$prose")
}

# Reason -> human message.
_reason_msg() {
  case "$1" in
    no-path)            echo "no usable path (prose-only, or verb+path split across two lines — the path is silently dropped)";;
    bad-shape)          echo "path has whitespace/() — a verb, bold wrapper, leading '(', or two-paths-without-'+' leaked in";;
    no-backtick-path)   echo "path is not \`backtick\`-wrapped";;
    non-line-paren)     echo "a parenthetical before '—' is not a (lines ~N-M) range — move the note after '—'";;
    ambiguous-entry)    echo "unparsed text after a path — use \`a\` + \`b\` for multiple paths and put prose after '—'";;
    no-verb-label)      echo "no Create:/Modify:/Test:/Rewrite: label — generation cannot tell what this bullet declares, and the path never reaches allowed_paths";;
    verb-no-path)       echo "a verb label with no path after it";;
    no-command)           echo "the **Reuse check:** field names no search command — a sentence is not evidence; put the command you ran in \`backticks\`";;
    command-not-allowed)  echo "the **Reuse check:** command is not one of grep/rg/ls/find/git grep — the lint replays it, so it runs read-only searches and nothing else";;
    no-reason)            echo "the **Reuse check:** says something already exists but not why it does not suffice — a step that founds a new file over an existing pattern owes that sentence; write it after the result, behind an em dash";;
    no-result)            echo "the **Reuse check:** field states no result after a '→' — write: searched: \`<command>\` → <none | one match | several matching | several conflicting> — <why what exists does not suffice>";;
    command-unsafe)       echo "the **Reuse check:** command pipes, redirects or chains — the lint replays it, so it accepts a single read-only search";;
    command-flag-refused) echo "the **Reuse check:** command carries a flag that runs another program (-exec, --pre, --config and friends) — the lint replays it, so a search must stay a search";;
    *)                  echo "$1";;
  esac
}

# _strict_finding <location-suffix> <message> — the STRICT/legacy emitter every
# obligation below shares. `location-suffix` is ":<lineno>", or "" for a
# whole-file finding. One place owns the counter, the --quiet check and the two
# tiers, so a new obligation cannot half-implement any of the three.
_strict_finding() {
  strict_hits=$((strict_hits+1))
  [[ "$QUIET" -eq 0 ]] || return 0
  if [[ "$mode" == "strict" ]]; then
    echo "${PLAN}${1}: STRICT ${2}" >&2
  else
    echo "${PLAN}${1}: [WARN legacy] ${2}" >&2
  fi
}

# Every Files bullet, once: the grammar pass below walks it, and so does the
# per-step Reuse-check pass (P085), which needs to know WHICH step a bullet
# belongs to. Extracting twice would mean two readers of the same text.
_bullet_lns=(); _bullet_txts=()
while IFS=$'\t' read -r _bl_lineno _bl_bullet; do
  [[ -z "${_bl_bullet:-}" ]] && continue
  _bullet_lns+=("$_bl_lineno"); _bullet_txts+=("$_bl_bullet")
done < <(_aid_extract_files_bullets_numbered < "$PLAN")

for _bi in "${!_bullet_lns[@]}"; do
  lineno="${_bullet_lns[$_bi]}"; bullet="${_bullet_txts[$_bi]}"
  while IFS= read -r prose_path; do
    [[ -n "$prose_path" ]] || continue
    _advisory ":${lineno}" "\`${prose_path}\` is named only in this entry's description, so it will NOT be in the step's allowed_paths — declare it with its own verb bullet if the step edits it: ${bullet}"
  done < <(_prose_paths "$bullet")
  verdict="$(_aid_classify_files_bullet "$bullet")"
  sev="${verdict%%:*}"; reason="${verdict#*:}"
  [[ "$sev" == "clean" ]] && continue
  msg="$(_reason_msg "$reason")"
  if [[ "$sev" == "error" ]]; then
    errors=$((errors+1))
    [[ "$QUIET" -eq 0 ]] && echo "${PLAN}:${lineno}: ERROR ${msg}: ${bullet}" >&2
  else  # strict
    _strict_finding ":${lineno}" "${msg}: ${bullet}"
  fi
done

# ---------------------------------------------------------------------------
# Band-scoped per-step obligations
# ---------------------------------------------------------------------------
# The band comes from the LIB (`aid_plan_band_name`, which already defaults an
# unknown answer to `full`), never from `aid-cp1-gate.sh --classify-only`: this
# lint runs inside generation's pre-flight, where "the CP1 gate is consulted
# exactly once per plan" is an invariant the generation suites assert by
# COUNTING gate invocations. The lib resolves the project root FROM THE PLAN, so
# a lint run from another directory still reads the policy override that plan's
# own workspace carries.

# _missing_step_fields — one line per step that is missing band-scoped fields:
# "<lineno>\t<missing,fields>\t<step heading>". A step's region runs from its
# own `### Step` heading to the next one or to the next `##` section, which is
# how the plan format already separates steps.
_missing_step_fields() {
  # Fenced blocks are blanked first: a plan that QUOTES `### Step 1:` in an
  # example (this repo's own plans about AID do) would otherwise be told its
  # example is missing Error Handling.
  #
  # The field list is ONE string. It used to be three literals repeated in three
  # places inside this program (detection, marking, reporting), so adding a
  # band-scoped field meant four coordinated edits in one awk.
  awk -v fields='Architecture Context|Error Handling|Edge Cases' '
    BEGIN { n = split(fields, want, "|") }
    function report(   i, miss) {
      miss = ""
      for (i = 1; i <= n; i++) if (!have[i]) miss = miss (miss ? "," : "") want[i]
      if (miss != "") print ln "\t" miss "\t" head
      head = ""
    }
    function reset(   i) { for (i = 1; i <= n; i++) have[i] = 0; pending = 0 }
    { gsub(/\r$/, "") }
    /^### Step / { if (head != "") report(); head = $0; ln = NR; reset(); next }
    /^## /       { if (head != "") report(); next }
    # A field counts as present only once something FOLLOWS its label — on the
    # label line itself ("**Error Handling:** none, this is a text edit") or on a
    # later line before the next label. Three empty labels used to satisfy all
    # three obligations while saying nothing.
    head != "" {
      if ($0 ~ /^\*\*[A-Z][^*]*:\*\*/) {
        rest = $0
        sub(/^\*\*[A-Z][^*]*:\*\*[[:space:]]*/, "", rest)
        pending = 0
        for (i = 1; i <= n; i++) if ($0 ~ "^\\*\\*" want[i] ":\\*\\*") pending = i
        if (pending && rest ~ /[^[:space:]]/) { have[pending] = 1; pending = 0 }
        next
      }
      if (pending && $0 ~ /[^[:space:]]/) { have[pending] = 1; pending = 0 }
    }
    END { if (head != "") report() }
  ' < <(_aid_blank_fenced < "$PLAN")
}

# _has_testing_strategy — a `## Testing Strategy` heading with at least one
# non-empty, non-heading line under it (P084 Step 4). The plan states which
# behaviour it verifies and why, instead of scattering one `Test:` bullet per
# step to satisfy a count: measured across six live plans, the Test-items-to-
# steps ratio sat at ~1:1 whatever the plan actually changed.
#
# A heading alone is not a strategy, so the content line is required; judging
# the QUALITY of that answer is the reviewer's job, not a regex's.
_has_testing_strategy() {
  awk '
    /^##[[:space:]]+Testing Strategy[[:space:]]*$/ { inside = 1; next }
    # No {n,m} intervals: mawk (the default awk on Debian) reads them
    # literally, and the check silently found "content" in every later line.
    /^#+[[:space:]]/                               { if ($0 !~ /^###/) inside = 0; next }
    inside && $0 ~ /[^[:space:]]/                  { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$PLAN"
}

if ! _has_testing_strategy; then
  _strict_finding "" "no '## Testing Strategy' section with content — say which behaviour this plan verifies, why that one, and where it goes (new suite / case in an existing suite). A Test: bullet per step is NOT required."
fi

# ---------------------------------------------------------------------------
# Human-audience sections (P084 Step 5)
# ---------------------------------------------------------------------------
# The PM's page is RENDERED from the plan's own facts
# (lib/aid-plan-summary.sh), so a hand-written summary section inside the plan
# is now a second, unverifiable copy of it. Reported here so it does not
# silently survive.
#
# A CLOSED list, deliberately: a heuristic like "a section with no machine-
# readable content" would report Context and Goal, which must stay. The price
# is that a newly-invented human section is not caught until someone adds it
# to this list, and that is the cheaper mistake.
_AID_HUMAN_SECTIONS=(
  "## Stakeholder Brief"
  "## Human Review Summary"
  "## Executive Summary"
  "## Shrnutí pro PM"
)

# ONE grep over the plan for the whole closed list (`-F -x` with an -e per
# heading), not one pass per heading: the matched line comes back with its
# number, so the message needs nothing the loop variable was carrying.
_human_grep_args=()
for _human in "${_AID_HUMAN_SECTIONS[@]}"; do _human_grep_args+=(-e "$_human"); done
while IFS=: read -r _hline _hsection; do
  [[ -n "${_hline:-}" ]] || continue
  _strict_finding ":${_hline}" "'${_hsection}' is written for a human, and the PM page is rendered from the plan instead (lib/aid-plan-summary.sh) — remove the section."
done < <(grep -n -x -F "${_human_grep_args[@]}" "$PLAN" 2>/dev/null || true)

band="$(aid_plan_band_name "$PLAN")"
if _band_owes step_fields; then
  while IFS=$'\t' read -r lineno missing head; do
    [[ -n "${missing:-}" ]] || continue
    _strict_finding ":${lineno}" "band=${band} step is missing ${missing}: ${head}"
  done < <(_missing_step_fields)
fi

# ---------------------------------------------------------------------------
# Reuse evidence on steps that found something (P085 Step 2)
# ---------------------------------------------------------------------------
# A step whose Files carry a `Create:` bullet owes a `**Reuse check:**` field:
# the read-only search it ran, and what that search found. The obligation holds
# in EVERY band, including `light` — founding a duplicate component is exactly
# what a small plan does, and the price here is one command and its output, not
# a dispatch.
#
# The field is REPLAYED, not read: lib/aid-reuse-verdict.sh runs the declared
# command again and compares the number of hits with the declared result, so a
# claim of `none` over a command that finds something today is a finding. Where
# the replay's reach ends, and who picks up there, is stated once in
# skills/review-checkpoint-contracts.md §"Lens: reuse_evidence".
_project_root="$(_aid_band_project_root "$PLAN")" || _project_root=""

# Every path this plan declares anywhere, once: the N+1 verdict asks whether a
# conflicting site already lies inside the plan's reach, and that question is
# about the WHOLE plan, not one step — unifying inside a file another step
# already opens costs no new reach.
# Two forks per bullet, so it is computed at most ONCE and only when something
# actually asks: a plan that founds nothing and has no documentation surface
# never needs the list at all.
# It SETS _AID_DECLARED_PATHS instead of echoing it, for the same reason the
# replay sets AID_REUSE_HITS: `$(_plan_declared_paths)` would build the list in
# a subshell and throw the memo away with it, so the "computed at most once"
# above would be a comment describing something that never happened.
_AID_DECLARED_PATHS=""
_AID_DECLARED_PATHS_DONE=0
_plan_declared_paths() {
  local i body
  [[ "$_AID_DECLARED_PATHS_DONE" -eq 1 ]] && return 0
  for i in "${!_bullet_txts[@]}"; do
    body="$(_aid_files_bullet_body "${_bullet_txts[$i]}")" || continue
    _AID_DECLARED_PATHS+="$(_aid_split_path_entry "$body" 2>/dev/null || true)"$'\n'
  done
  _AID_DECLARED_PATHS_DONE=1
}

while _band_owes reuse_check && IFS=$'\t' read -r _rs _re _rhead; do
  [[ -n "${_rs:-}" ]] || continue
  if ! _reuse_value="$(_aid_plan_step_field "$PLAN" "$_rs" "$_re" "Reuse check")"; then
    _strict_finding ":${_rs}" "step founds a new file (a \`Create:\` bullet) with no **Reuse check:** field — say what you searched for and what it returned: ${_rhead}"
    continue
  fi
  if ! _reuse_parsed="$(aid_reuse_parse "$_reuse_value")"; then
    # `command-not-allowed:<name>` carries the offending command with it, so the
    # refusal can name what it refused instead of describing a category.
    _reuse_reason="${_reuse_parsed#error:}"; _reuse_named="${_reuse_reason#*:}"
    _reuse_reason="${_reuse_reason%%:*}"
    _reuse_suffix=""
    [[ "$_reuse_reason" == "command-not-allowed" ]] && _reuse_suffix=" — refused: \`${_reuse_named}\`"
    _strict_finding ":${_rs}" "$(_reason_msg "$_reuse_reason")${_reuse_suffix}: ${_rhead}"
    continue
  fi
  _reuse_key="${_reuse_parsed%%$'\t'*}"
  _reuse_cmd="${_reuse_parsed#*$'\t'}"
  # The N+1 rule (P085 Step 3). This step founds a file — every step that gets
  # here does — and it declared that what exists is in conflict. Adding one more
  # variant on top of that is allowed exactly once it is ARGUED; what is refused
  # is doing it silently.
  if [[ "$_reuse_key" == "several_conflicting" ]]; then
    if ! aid_reuse_deliberate "$_reuse_value"; then
      _strict_finding ":${_rs}" "**Reuse check:** declares 'several conflicting' and the step still founds another file of the same kind — use one of them, unify them, or write 'deliberately founding a variant' with the reason: ${_rhead}"
    fi
    _plan_declared_paths
    _reuse_verdict="$(aid_reuse_verdict "$_reuse_value" "$_reuse_cmd" "$_AID_DECLARED_PATHS")"
    case "$_reuse_verdict" in
      unify)   _reuse_msg="every conflicting site is already inside this plan's declared paths — unify them here, unless doing so pushes the step past its declared Effort (that half is yours to judge, not the lint's)." ;;
      backlog) _reuse_msg="the field names no conflicting site, so the verdict is out of reach: file a backlog item — but name the paths in it, or nobody can act on it." ;;
      *)       _reuse_msg="conflicting site(s) outside this plan's declared paths: ${_reuse_verdict#*$'\t'} — file a backlog item that LISTS them, never 'unify the components'." ;;
    esac
    _advisory ":${_rs}" "$_reuse_msg"
  fi
  # No project root means no directory the command was meant to run in, so the
  # replay cannot run — but SILENCE there is the fail-open this obligation must
  # never have: an unresolvable root would switch the strongest half of the
  # check off without saying so (Codex wiring review, 2026-08-23). Say it, and
  # let the strict tier decide whether it blocks.
  if [[ -z "$_project_root" ]]; then
    _strict_finding ":${_rs}" "**Reuse check:** not replayed — no project root resolved from the plan's path, so the claim stands unverified: ${_rhead}"
    continue
  fi
  # Called directly, NOT in a command substitution: the replay memoises identical
  # searches across steps, and a subshell would throw that away every time.
  if aid_reuse_replay "$_reuse_cmd" "$_project_root"; then
    _reuse_hits="$AID_REUSE_HITS"
    aid_reuse_result_matches "$_reuse_key" "$_reuse_hits"
    case "$?" in
      1) _strict_finding ":${_rs}" "**Reuse check:** declares '${_reuse_key}' but replaying \`${_reuse_cmd}\` finds ${_reuse_hits} file(s) — the evidence and the claim disagree: ${_rhead}" ;;
      # Right direction, wrong degree. Said out loud, not blocked on: the file
      # count is read out of tool output, and a tool can be asked to print in a
      # shape that reading gets wrong.
      2) _advisory ":${_rs}" "**Reuse check:** declares '${_reuse_key}' and the replay finds ${_reuse_hits} file(s) — same direction, different count; check which of the four results this really is." ;;
    esac
  else
    case "$?" in
      3) _strict_finding ":${_rs}" "**Reuse check:** command \`${_reuse_cmd}\` does not run here — evidence that cannot be re-run is not evidence: ${_rhead}" ;;
      4) _strict_finding ":${_rs}" "**Reuse check:** command \`${_reuse_cmd}\` timed out (20 s) — a search nobody can afford to repeat is not evidence: ${_rhead}" ;;
      # No `timeout` binary is this machine's problem, not the plan's, and an
      # unbounded replay is not a trade this lint makes. Advisory, and loud.
      5) _advisory ":${_rs}" "**Reuse check:** not replayed — no \`timeout\` binary on this machine to bound the search with." ;;
    esac
  fi
done < <(_aid_plan_founding_steps "$PLAN")

# ---------------------------------------------------------------------------
# Standards named against the map (P085 Step 4)
# ---------------------------------------------------------------------------
# The plan names the ecosystem standards that bind the areas its paths reach,
# or says where it departs from one and why. Which standards those are is
# derived from the LIVE map (lib/aid-standards-map.sh) — never from a copy in
# this repository, which would be a second map that disagrees with the first.
#
# THREE states, not two, because two would quietly turn the obligation into a
# decoration: no map configured = the project has no standards and owes nothing
# (recorded, so it does not read as an omission); a map configured but
# unreachable = a broken environment, reported loudly and blocking for a strict
# plan; a map that binds nothing to these paths = the section is not owed, and
# that is a correct answer.
#
# `light` is exempt: a plan that changes a help text or ordinary feature code is
# not where standards compliance is decided, and the band exists precisely so
# that small plans are not asked questions they do not have.

# _deviation_cell <table-row> — the last non-empty cell of a markdown table row.
_deviation_cell() {
  printf '%s' "$1" | awk -F'|' '{
    for (i = NF; i >= 1; i--) {
      cell = $i; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell)
      if (cell != "") { print cell; exit }
    }
  }'
}

if _band_owes standards; then
  _std_derived="$(aid_standards_derive "$PLAN" "${_project_root:-}")"; _std_rc=$?
  case "$_std_rc" in
    1) [[ "$QUIET" -eq 0 ]] && echo "${PLAN}: [NOTE] no standards map configured for this project (project.yaml -> standards.map_path), so no '## Standards' section is owed." >&2 ;;
    2) _strict_finding "" "standards.map_path IS configured but the map cannot be read (missing file, or no yq) — that is a broken environment, not a project without standards; fix the path or unset it." ;;
    0)
      _std_section="$(_aid_plan_section "$PLAN" "Standards")"
      while IFS=$'\t' read -r _std_tag _std_ids; do
        [[ -n "${_std_tag:-}" ]] || continue
        _std_named=""
        IFS=',' read -r -a _std_arr <<< "$_std_ids"
        for _std_id in "${_std_arr[@]}"; do
          [[ "$_std_section" == *"$_std_id"* ]] && { _std_named="$_std_id"; break; }
        done
        if [[ -z "$_std_named" ]]; then
          _strict_finding "" "this plan touches the '${_std_tag}' area but its '## Standards' section names none of: ${_std_ids} — name the one you checked, or say which you depart from and why."
          continue
        fi
        # A named standard whose deviation cell is a bare marker states a
        # deviation without stating a reason, which is the one shape the
        # section must not have.
        while IFS= read -r _std_row; do
          [[ "$_std_row" == \|* ]] || continue
          [[ "$_std_row" == *"$_std_named"* ]] || continue
          [[ "$_std_row" == *---* ]] && continue
          _std_dev="$(_deviation_cell "$_std_row")"
          case "$_std_dev" in
            ""|none|None|"n/a"|-|—|žádná|žádný|zadna|zadny) continue ;;
          esac
          # The cell IS the reason when there is one; a word is not a reason.
          [[ "${#_std_dev}" -ge 12 ]] || _strict_finding "" "'${_std_named}' is marked as a deviation ('${_std_dev}') with no reason — a deviation is reported so it can be fixed in the standard or in the map, and neither is possible without the why."
        done <<< "$_std_section"
      done <<< "$_std_derived"
      # A defect of the MAP, reported so it gets fixed. Never blocking: a plan
      # is not responsible for the map's bookkeeping.
      while IFS= read -r _std_defect; do
        [[ -n "${_std_defect:-}" ]] || continue
        _advisory "" "the standards map uses tag '${_std_defect}', which is missing from its own tag vocabulary — a defect of the map, reported here, not a reason to stop this plan."
      done < <(aid_standards_map_defects "$PLAN" "${_project_root:-}" 2>/dev/null || true)
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Declared concurrency (P085 Step 7) — the writing-time half
# ---------------------------------------------------------------------------
# aid-plan-parallel-check.sh owns the rule; the lint is where a plan author
# hears about it while the plan is still being written. ADVISORY here, BLOCKING
# in aid-generation-readiness.sh — the same two-stage model the Files grammar
# has, and the reason the check has an --advisory mode at all.
#
# Two callers of one program, never two implementations: this passes the output
# through and adds nothing of its own.
# AID_LINT_SKIP_PARALLEL is set by aid-generation-readiness.sh, which runs the
# same program itself in its BLOCKING mode: without it the plan would be parsed
# for waves twice on every readiness run, and the findings printed twice.
# Not gated on --quiet: that flag suppresses OUTPUT, and skipping the run would
# make a quiet lint report fewer advisories than a loud one on the same plan —
# a counter that depends on whether anyone was listening. `_advisory` already
# owns the quiet check.
if [[ -x "${SCRIPT_DIR}/aid-plan-parallel-check.sh" && -z "${AID_LINT_SKIP_PARALLEL:-}" ]]; then
  # The exit code carries "there were findings"; the count comes from the lines
  # themselves. Nothing here parses the other program's summary sentence —
  # rewording user-facing prose must not silently zero a count.
  if ! _par_out="$("${SCRIPT_DIR}/aid-plan-parallel-check.sh" "$PLAN" 2>&1)"; then
    while IFS= read -r _par_line; do
      case "$_par_line" in
        "aid-plan-parallel-check: "*|*"[NOTE]"*) continue ;;
      esac
      [[ -n "$_par_line" ]] && _advisory "" "$_par_line"
    done <<< "$_par_out"
  fi
fi

# ---------------------------------------------------------------------------
# Documentation and help (P085 Step 6)
# ---------------------------------------------------------------------------
# A plan that changes what a user experiences owes a CONCRETE way in: the file
# and section of the in-app help, the page in the docs site. Not "update the
# documentation" — a path, in a Files bullet, like any other work.
#
# What the project HAS is not re-discovered at every plan write. /aid-init and
# /aid-setup record it once in project.yaml (`documentation.in_app_help`,
# `documentation.docusaurus`, `documentation.screenshot_tool`) and the plan
# reads the answer — the same relationship the band has to the classifier.
# A project with neither a help surface nor a docs site owes NOTHING here, and
# the lint says so, so the silence does not read as an omission.
#
# "Changes what a user experiences" is read from the plan's own `type:`:
# `refactor` and `docs` are exempt by definition, `regular` and `bug-fix` are
# not. A proxy, deliberately — the alternative is a regex guessing at intent,
# and the plan already declares this about itself.

# _doc_surfaces <project-root> — the documentation surfaces this project has,
# one "<key>=<path>" per line. THREE answers, the same three the standards map
# has, and for the same reason: "cannot read the configuration" must never be
# rounded down to "this project has no documentation".
#   0  at least one surface, printed
#   1  the configuration is readable and records none — a legitimate state
#   2  there IS a project.yaml but it cannot be read (no yq) — a broken
#      environment, and the caller says so out loud
# THE key under `documentation:` that is NOT a surface. Everything else there
# is one, so a project with a wiki, a man tree or a second help route can make
# the obligation see it without patching this file.
_AID_DOC_NON_SURFACE='screenshot_tool'

_doc_surfaces() {
  local raw rc
  # ONE yq over project.yaml, not one per key: the same pattern _cp1_band_flags
  # and _aid_band_map_eres already use, and the reason this reader is shared.
  raw="$(_aid_project_yaml "$1" ".documentation // {} | to_entries[] | .key + \"=\" + (.value // \"\")")"; rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  printf '%s\n' "$raw" | awk -F= -v skip="$_AID_DOC_NON_SURFACE" '
    NF > 1 && $1 != skip && $2 != "" { print }
  ' | grep . || return 1
}

# _plan_touches <path-prefix> — does the plan declare a path at or under it?
# Over the memoised list, not a fresh walk: the paths were already parsed, and
# "what does this plan touch" must have one answer, not one per question.
_plan_touches() {
  local prefix="$1" p
  _plan_declared_paths
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    [[ "$p" == "${prefix%/}/"* || "$p" == "$prefix" ]] && return 0
  done <<< "$_AID_DECLARED_PATHS"
  return 1
}

# No resolvable project root means no project.yaml to read the surfaces from.
# Saying nothing there would read as "no documentation is owed", which is the
# fail-open direction; the run says what it could not determine instead
# (Codex wiring review, 2026-08-23).
if _band_owes documentation && [[ -z "${_project_root:-}" ]]; then
  _advisory "" "documentation surfaces not checked — no project root resolved from the plan's path, so project.yaml could not be read."
fi
if _band_owes documentation && [[ -n "${_project_root:-}" ]]; then
  _doc_type="$(_aid_fm_get "$PLAN" type)"
  case "$_doc_type" in
    refactor|docs) : ;;   # by definition not a change a user meets
    *)
      _doc_list="$(_doc_surfaces "${_project_root:-}")"; _doc_rc=$?
      case "$_doc_rc" in
        2) _strict_finding "" "this project has a .aid-o/config/project.yaml but it cannot be read (no yq) — that is a broken environment, not a project without documentation; the documentation obligation could not be evaluated." ;;
        1) [[ "$QUIET" -eq 0 ]] && echo "${PLAN}: [NOTE] this project records no in-app help and no documentation site (project.yaml -> documentation), so no documentation step is owed." >&2 ;;
        0)
          # EVERY surface the project has, not the first one found: a plan that
          # updates the docs site and forgets the in-app help has still left
          # half its users on the old behaviour.
          while IFS='=' read -r _doc_key _doc_path; do
            [[ -n "${_doc_path:-}" ]] || continue
            _plan_touches "$_doc_path" && continue
            _strict_finding "" "this plan changes behaviour a user meets (type: ${_doc_type:-regular}) but no step declares a path under '${_doc_path}' (project.yaml -> documentation.${_doc_key}) — name the file and section that has to change, the way any other work is named. A plan that genuinely changes nothing user-visible says so with type: refactor."
          done <<< "$_doc_list"
          ;;
      esac
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# A suite named only in prose (P089 Step 11, IMP-517)
# ---------------------------------------------------------------------------
# `## Testing Strategy` is where a plan says what it verifies, and a suite named
# THERE reads like a promise that the suite will exist. When no `Test:` bullet
# declares it and no file of that name is in the repository, nobody is going to
# write it: the step contract only ever creates what a Files bullet declares.
#
# ADVISORY, and that is the honest weight. A name in prose is a weaker signal
# than a declared path — "we extend test-foo.bats" may be shorthand for a case
# added to a suite that is declared under a different name — so this asks a
# question rather than refusing a plan.
#
# Fenced blocks are blanked first: a suite name inside a code example is an
# illustration, not a promise.
_ts_names() {
  _aid_blank_fenced < "$PLAN" | awk '
    /^##[[:space:]]+Testing Strategy[[:space:]]*$/ { inside = 1; next }
    /^#+[[:space:]]/ { if ($0 !~ /^###/) inside = 0; next }
    inside { print }
  ' | grep -oE '[A-Za-z0-9_.-]+\.(bats|sh)' | sort -u
}

# _declared_in_test_bullet <basename> — is the name in ANY `- Test:` bullet?
_declared_in_test_bullet() {
  grep -qE '^[[:space:]]*-[[:space:]]*Test:' "$PLAN" \
    && grep -E '^[[:space:]]*-[[:space:]]*Test:' "$PLAN" | grep -qF "$1"
}

while IFS= read -r _ts_name; do
  [[ -n "$_ts_name" ]] || continue
  _declared_in_test_bullet "$_ts_name" && continue
  # A suite that ALREADY exists is not a promise — the plan is naming what it
  # extends. Only a name that is neither declared nor on disk is the defect.
  if [[ -n "${_project_root:-}" ]]; then
    if find "$_project_root" -name "$_ts_name" -print -quit 2>/dev/null | grep -q .; then
      continue
    fi
  else
    # No root, no way to look: say nothing rather than guess.
    continue
  fi
  _advisory "" "\`${_ts_name}\` is named in ## Testing Strategy, is in no \`Test:\` bullet and does not exist in the repository — declare it with a Test: bullet and a tier, or say in one sentence why the suite is not being written."
done < <(_ts_names)

# Blocking = any ERROR (both modes), or any STRICT on a strict-cohort plan.
blocking=$errors
[[ "$mode" == "strict" ]] && blocking=$((blocking + strict_hits))

if [[ "$QUIET" -eq 0 ]]; then
  if [[ "$blocking" -gt 0 ]]; then
    echo "aid-plan-lint: FAIL (${errors} error(s)$( [[ "$mode" == "strict" ]] && echo ", ${strict_hits} strict violation(s)" )) — fix the findings above. Canonical Files form: '- <Create|Modify|Test|Rewrite>: \`path\` [ + \`path\`]* [(lines ~N-M)] [— prose]'; band-scoped step fields: skills/plan-writing.md §\"Obligations by ceremony band\"." >&2
  elif [[ "$strict_hits" -gt 0 ]]; then
    echo "aid-plan-lint: PASS with ${strict_hits} legacy advisory warning(s) (non-blocking for this legacy plan; would block a lifecycle_strict plan)." >&2
  else
    echo "aid-plan-lint: PASS — all Files entries are canonical." >&2
  fi
  # ONE counter, so the closing line must not name ONE of the things it counts:
  # since P085 it also carries reuse-degree, standards-map and wave advisories,
  # and calling all of them "description-only path" advisories was a count that
  # contradicted the lines printed right above it.
  [[ "$advisories" -gt 0 ]] && echo "aid-plan-lint: ${advisories} advisory finding(s) above — never blocking, in either mode." >&2
fi

# Telemetry (P084 Step 7): how often this lint STOPS a plan, and on what. The
# question it exists to answer — is a given obligation catching anything — has
# no answer today because nothing was ever counted. Never blocking: without a
# resolvable plan id or workspace, the helper returns 1 and nothing is written.
if _lint_plan_id="$(_aid_plan_id_of "$PLAN")"; then
  _lint_root="${_project_root:-}"
  if [[ -n "$_lint_root" ]] && _lint_tl="$(aid_plan_timeline "$_lint_root" "$_lint_plan_id")"; then
    # `|| true`: the promise above is that telemetry never blocks, and a bare
    # call would make any future non-zero from the logger this lint's verdict.
    log_event "$_lint_tl" "plan_lint_result" \
      band="$band" mode="$mode" errors="$errors" strict="$strict_hits" \
      advisories="$advisories" blocked="$( [[ "$blocking" -gt 0 ]] && echo true || echo false )" || true
  fi
fi

[[ "$blocking" -gt 0 ]] && exit 1
exit 0
