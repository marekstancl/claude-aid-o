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
  local bullet="${1#- }" body prose declared rest tok
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
  # Backtick spans, read the way the shared cleaner reads them: pure bash, so
  # the advisory does not quietly disappear on a grep without PCRE support.
  rest="$prose"
  while [[ "$rest" == *'`'*'`'* ]]; do
    rest="${rest#*\`}"
    tok="${rest%%\`*}"
    rest="${rest#*\`}"
    # A real repo file, deliberately narrow: at least one directory segment and
    # a file extension, no placeholder brackets, no trailing slash. Directories
    # (`<evidence_dir>/jobs/`), command fragments and prose punctuation are not
    # scope declarations and must not generate noise.
    [[ "$tok" =~ ^[A-Za-z0-9._/-]+/[A-Za-z0-9._-]+\.[A-Za-z0-9]+$ ]] || continue
    _aid_path_shape_ok "$tok" || continue
    # Already declared? Pure-bash membership — one fork per token adds up on a
    # sixty-bullet plan that prints nothing.
    [[ $'\n'"$declared"$'\n' == *$'\n'"$tok"$'\n'* ]] && continue
    printf '%s\n' "$tok"
  done
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
    *)                  echo "$1";;
  esac
}

while IFS=$'\t' read -r lineno bullet; do
  [[ -z "${bullet:-}" ]] && continue
  while IFS= read -r prose_path; do
    [[ -n "$prose_path" ]] || continue
    advisories=$((advisories+1))
    [[ "$QUIET" -eq 0 ]] && echo "${PLAN}:${lineno}: [ADVISORY] \`${prose_path}\` is named only in this entry's description, so it will NOT be in the step's allowed_paths — declare it with its own verb bullet if the step edits it: ${bullet}" >&2
  done < <(_prose_paths "$bullet")
  verdict="$(_aid_classify_files_bullet "$bullet")"
  sev="${verdict%%:*}"; reason="${verdict#*:}"
  [[ "$sev" == "clean" ]] && continue
  msg="$(_reason_msg "$reason")"
  if [[ "$sev" == "error" ]]; then
    errors=$((errors+1))
    [[ "$QUIET" -eq 0 ]] && echo "${PLAN}:${lineno}: ERROR ${msg}: ${bullet}" >&2
  else  # strict
    strict_hits=$((strict_hits+1))
    if [[ "$mode" == "strict" ]]; then
      [[ "$QUIET" -eq 0 ]] && echo "${PLAN}:${lineno}: STRICT ${msg}: ${bullet}" >&2
    else
      [[ "$QUIET" -eq 0 ]] && echo "${PLAN}:${lineno}: [WARN legacy] ${msg}: ${bullet}" >&2
    fi
  fi
done < <(_aid_extract_files_bullets_numbered < "$PLAN")

# ---------------------------------------------------------------------------
# Band-scoped per-step obligations
# ---------------------------------------------------------------------------
# _plan_band — the plan's ceremony band from the one classifier
# (lib/aid-plan-band.sh, shared with aid-cp1-gate.sh). Anything unexpected
# reads as `full`: the lint must never be the reason a plan is checked for less.
# Deliberately the LIB and not `aid-cp1-gate.sh --classify-only`: this lint runs
# inside generation's pre-flight, where "the CP1 gate is consulted exactly once
# per plan" is an invariant asserted by counting gate invocations. The project
# root is resolved by the lib FROM THE PLAN, never from this process's cwd — a
# lint run from elsewhere must still read the same policy override the gate
# reads for that plan.
_plan_band() {
  local line band
  line="$(aid_plan_band "$PLAN")" || line=""
  band="${line%%$'\t'*}"
  case "$band" in
    full|medium|light) printf '%s' "$band" ;;
    *)                 printf 'full' ;;
  esac
}

# _missing_step_fields — one line per step that is missing band-scoped fields:
# "<lineno>\t<missing,fields>\t<step heading>". A step's region runs from its
# own `### Step` heading to the next one or to the next `##` section, which is
# how the plan format already separates steps.
_missing_step_fields() {
  awk '
    function mark(which) {
      if (which == "arch") arch = 1
      else if (which == "err") err = 1
      else if (which == "edge") edge = 1
    }
    function report(   miss) {
      miss = ""
      if (!arch) miss = miss (miss ? "," : "") "Architecture Context"
      if (!err)  miss = miss (miss ? "," : "") "Error Handling"
      if (!edge) miss = miss (miss ? "," : "") "Edge Cases"
      if (miss != "") print ln "\t" miss "\t" head
      head = ""
    }
    { gsub(/\r$/, "") }
    /^### Step / { if (head != "") report(); head = $0; ln = NR; arch = 0; err = 0; edge = 0; pending = ""; next }
    /^## /       { if (head != "") report(); next }
    # A field counts as present only once something FOLLOWS its label — either
    # on the label line itself ("**Error Handling:** none, this is a text edit")
    # or on a later line before the next label. Three empty labels used to
    # satisfy all three obligations while saying nothing.
    head != "" {
      if ($0 ~ /^\*\*[A-Z][^*]*:\*\*/) {
        rest = $0
        sub(/^\*\*[A-Z][^*]*:\*\*[[:space:]]*/, "", rest)
        pending = ""
        if ($0 ~ /^\*\*Architecture Context:\*\*/) pending = "arch"
        if ($0 ~ /^\*\*Error Handling:\*\*/)       pending = "err"
        if ($0 ~ /^\*\*Edge Cases:\*\*/)           pending = "edge"
        if (pending != "" && rest ~ /[^[:space:]]/) { mark(pending); pending = "" }
        next
      }
      if (pending != "" && $0 ~ /[^[:space:]]/) { mark(pending); pending = "" }
    }
    END { if (head != "") report() }
  ' "$PLAN"
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
  strict_hits=$((strict_hits+1))
  if [[ "$QUIET" -eq 0 ]]; then
    if [[ "$mode" == "strict" ]]; then
      echo "${PLAN}: STRICT no '## Testing Strategy' section with content — say which behaviour this plan verifies, why that one, and where it goes (new suite / case in an existing suite). A Test: bullet per step is NOT required." >&2
    else
      echo "${PLAN}: [WARN legacy] no '## Testing Strategy' section with content — a Test: bullet per step does not replace saying what is verified and why." >&2
    fi
  fi
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
  strict_hits=$((strict_hits+1))
  if [[ "$QUIET" -eq 0 ]]; then
    if [[ "$mode" == "strict" ]]; then
      echo "${PLAN}:${_hline}: STRICT '${_hsection}' is written for a human, and the PM page is rendered from the plan instead (lib/aid-plan-summary.sh) — remove the section." >&2
    else
      echo "${PLAN}:${_hline}: [WARN legacy] '${_hsection}' is written for a human; the PM page is now rendered from the plan (lib/aid-plan-summary.sh)." >&2
    fi
  fi
done < <(grep -n -x -F "${_human_grep_args[@]}" "$PLAN" 2>/dev/null || true)

band="$(_plan_band)"
if [[ "$band" != "light" ]]; then
  while IFS=$'\t' read -r lineno missing head; do
    [[ -n "${missing:-}" ]] || continue
    strict_hits=$((strict_hits+1))
    if [[ "$QUIET" -eq 0 ]]; then
      if [[ "$mode" == "strict" ]]; then
        echo "${PLAN}:${lineno}: STRICT band=${band} step is missing ${missing}: ${head}" >&2
      else
        echo "${PLAN}:${lineno}: [WARN legacy] band=${band} step is missing ${missing}: ${head}" >&2
      fi
    fi
  done < <(_missing_step_fields)
fi

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
  [[ "$advisories" -gt 0 ]] && echo "aid-plan-lint: ${advisories} description-only path advisory/-ies (never blocking — declare them as their own bullets if the step edits them)." >&2
fi

# Telemetry (P084 Step 7): how often this lint STOPS a plan, and on what. The
# question it exists to answer — is a given obligation catching anything — has
# no answer today because nothing was ever counted. Never blocking: without a
# resolvable plan id or workspace, the helper returns 1 and nothing is written.
if _lint_plan_id="$(_aid_plan_id_of "$PLAN")"; then
  _lint_root="$(_aid_band_project_root "$PLAN")" || _lint_root=""
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
