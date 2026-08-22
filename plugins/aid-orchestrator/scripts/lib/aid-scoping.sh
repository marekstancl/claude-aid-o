#!/usr/bin/env bash
# =============================================================================
# lib/aid-scoping.sh — shared per-step scoping helpers (single source of truth)
#
# Extracted (v2.58.0, IMP-232 commit 1) from aid-epic-to-json.sh so that BOTH
# the generator (aid-epic-to-json.sh, which DERIVES a step's allowed_paths from
# its per-step block) AND the contract gate (gates/aid-contract-validate.sh,
# which VERIFIES the generated allowed_paths against that same block) clean paths
# with identical logic. Keeping one copy removes the drift hazard the
# per_step_scoping check's "two independent stages" note warns about.
#
# Pure functions (jq + sed only). Idempotent double-source guard.
# =============================================================================
[[ -n "${_AID_SCOPING_SH_LOADED:-}" ]] && return 0
_AID_SCOPING_SH_LOADED=1

# _aid_parse_scoping_line — split a per-step scoping HTML-comment line into its
# files=[...] and ac=[...] JSON-array substrings (D2).
# Shape (frozen by aid-plan-to-epic.sh / E-TEST-005 fixture, P058 Step 2):
#   <!-- step-N: files=["Create: `path` — desc", ...]; ac=["AC text", ...] -->
# Anchors the split on the LAST "; ac=[" (a files[] value may itself contain
# that literal). Returns 1 if the line does not match the expected shape
# (caller treats that as "no block for this step").
# Args: $1 = raw matched line; $2 = step number N. Output: files-JSON, ac-JSON.
_aid_parse_scoping_line() {
  local line="$1"
  local step_n="$2"
  local prefix="<!-- step-${step_n}: files="

  [[ "$line" == "$prefix"* ]] || return 1
  local body="${line#"$prefix"}"

  [[ "$body" == *" -->" ]] || return 1
  body="${body% -->}"

  [[ "$body" == *"]; ac=["* ]] || return 1
  local files_part="${body%; ac=[*}"
  local ac_part="${body##*; ac=}"

  printf '%s\n%s\n' "$files_part" "$ac_part"
}

# _aid_split_path_entry — D4 cleaner for a single RAW Files bullet (label
# already stripped). The path declaration sits immediately after the label as
# ONE backtick-wrapped span, or several joined by literal " + `" (the
# "`a.md` + `b.md`" dual-file convention). After the last path span, only an
# optional (lines ~N-M)/(řádky ...) range and/or an em-dash/"--" description
# is accepted. Any other remainder (notably a comma/conjunction-separated
# path list, or stray prose) is a FAILURE — this is the D4 boundary the P071
# bugfix hardened: a prior version silently stopped at the first
# unparseable span and returned only the path(s) already found, which meant
# "`a.md`, `b.md`" silently narrowed a step's allowed_paths to `a.md` alone
# instead of surfacing the malformed entry. Callers MUST check the return
# code and treat non-zero as a hard parse failure, never as "zero paths".
# No leading backtick span -> fall back to stripping after the first
# "--"/em-dash (unchanged legacy tolerance for non-backtick-first prose).
# Args: $1 = one RAW Files bullet, label stripped. Output: one cleaned
# path per line. Returns 1 on an ambiguous/unparseable entry.
_aid_split_path_entry() {
  local entry="$1"
  local rest="$entry"
  local candidate found_backtick_path=0 first_span=1

  while true; do
    if [[ "$first_span" -eq 1 ]]; then
      [[ "$rest" == '`'* ]] || break
    else
      [[ "$rest" == ' + `'* ]] || break
      rest="${rest# + }"
    fi
    rest="${rest#\`}"           # drop the opening backtick
    candidate="${rest%%\`*}"    # everything up to the next backtick
    rest="${rest#*\`}"          # drop through the closing backtick
    if [[ -n "$candidate" && "$candidate" != *[[:space:]]* ]]; then
      printf '%s\n' "$candidate"
      found_backtick_path=1
      first_span=0
    else
      echo "aid-scoping: invalid path span in Files entry: ${entry}" >&2
      return 1
    fi
  done

  if [[ "$found_backtick_path" -eq 1 ]]; then
    rest="$(printf '%s' "$rest" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$rest" || "$rest" == "—"* || "$rest" == --* ]]; then
      return 0
    fi
    local paren_re='^\([^)]*\)([[:space:]]*(—|--).*)?$'
    if [[ "$rest" =~ $paren_re ]]; then
      return 0
    fi
    echo "aid-scoping: unparsed text after path declaration: ${rest}. Use \`a\` + \`b\` for multiple paths and put prose after '—'." >&2
    return 1
  fi

  local fallback="$entry"
  fallback="${fallback%%--[[:space:]]*}"
  fallback="$(printf '%s' "$fallback" | sed 's/[[:space:]]*\xe2\x80\x94[[:space:]].*//')"
  fallback="${fallback//\`/}"
  fallback="$(printf '%s' "$fallback" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$fallback" ]] && printf '%s\n' "$fallback"
  return 0
}

# _aid_path_shape_ok <path> — the D5 allowed_paths_shape predicate as ONE shared
# function: return 0 if a cleaned path has a valid shape, 1 if it contains
# whitespace, "(" or ")" (real repo paths never do — a hit means a verb-prefix or
# trailing prose/parenthetical leaked through the cleaner). gates/aid-contract-
# validate.sh and scripts/aid-plan-lint.sh both call this so the plan-time lint
# and the generation-time gate can never disagree on what a valid path is.
_aid_path_shape_ok() {
  local p="$1"
  [[ "$p" =~ [[:space:]] || "$p" == *"("* || "$p" == *")"* ]] && return 1
  return 0
}

# _AID_FILES_BULLETS_AWK — the ONE awk program that finds top-level **Files:** block
# bullets. Shared by aid-plan-to-epic.sh (which turns them into a step's block
# files[]) and scripts/aid-plan-lint.sh, so "which lines count as a Files entry"
# can never drift between the generator and the lint. A Files entry is a line whose
# "-" sits at column 0 INSIDE a **Files:** block; a further-indented "-" is prose
# continuation of the entry above it, NOT a separate file. With emit_lineno=1 each
# match is prefixed "<lineno>\t" (for the lint's diagnostics); with 0 the output is
# byte-identical to aid-plan-to-epic.sh's historical inline extraction.
read -r -d '' _AID_FILES_BULLETS_AWK <<'AWK' || true
BEGIN { in_files = 0 }
{
  gsub(/\r$/, "")
  if ($0 ~ /^\*\*Files:\*\*/) { in_files = 1; next }
  if (in_files && $0 ~ /^\*\*/) { in_files = 0 }
  if (in_files && $0 ~ /^-[[:space:]]/) {
    ln = NR
    sub(/^-[[:space:]]*/, "", $0)
    if ($0 != "") { if (emit_lineno) print ln "\t- " $0; else print "- " $0 }
  }
}
AWK

# _aid_blank_fenced — read a plan on stdin, emit it with every line inside a
# ``` fenced block replaced by an EMPTY line.
#
# Blanked, not deleted, so line numbers survive: every reader downstream reports
# `file:lineno` and a stripped stream would name the wrong line. Readers that
# scan for `### Step N:` or `**EPIC N:**` need this — AID's own plans and skills
# quote that syntax inside fences, and a meta-plan then counts steps it does not
# have. aid-plan-to-epic.sh:445 has carried the same in_fence toggle since P039
# for exactly this reason; this is that rule as something other files can call.
_aid_blank_fenced() {
  awk '
    /^[[:space:]]*```/ { in_fence = !in_fence; print ""; next }
    { if (in_fence) print ""; else print }
  '
}

# _aid_extract_files_bullets — read text on stdin, emit each top-level Files-block
# bullet as "- <bullet>". Byte-identical to the historical inline awk it replaces.
# Handles Files bullets ONLY — for Acceptance Criteria bullets (which need
# continuation-line joining, not just top-level bullet extraction), see
# aid_ac_extract_criteria in aid-ac-extract.sh.
_aid_extract_files_bullets() { awk -v emit_lineno=0 "$_AID_FILES_BULLETS_AWK"; }

# _aid_extract_files_bullets_numbered — same, but each line is "<lineno>\t- <bullet>".
_aid_extract_files_bullets_numbered() { awk -v emit_lineno=1 "$_AID_FILES_BULLETS_AWK"; }

# _aid_classify_files_bullet <bullet> — classify ONE raw Files bullet (leading "- "
# optional). Echoes exactly one of:
#   error:bad-shape          a cleaned path fails _aid_path_shape_ok -> WILL break
#                            the generation-time D5 gate -> ALWAYS blocking.
#   strict:no-path           the cleaner yields NO path (e.g. the verb+path split
#                            across two lines, whose path the generator silently
#                            drops). The shape gate tolerates it (no bad path), so
#                            this is NOT a hard gate-breaker — but it is a real
#                            defect (a dropped allowed_path), hence strict-tier.
#   strict:no-backtick-path  cleaner rescued a clean path but the entry does not
#                            start with a `backtick-wrapped` path.
#   strict:non-line-paren    a parenthetical before the "—" is not a (lines …) range.
#   error:ambiguous-entry    the cleaner rejected unparsed trailing text (e.g. a
#                            comma/conjunction-separated path list) instead of
#                            silently keeping only the path(s) found before it.
#   (all three strict:* are canonical only for strict plans, advisory for legacy)
#   clean                    canonical: `path`[ + `path`]* [(lines …)] [— prose]
# Uses ONLY the shared cleaner + shape predicate, so its ERROR verdicts are exactly
# the entries the generation-time gate would reject.
# THE Files-bullet verb vocabulary. Every reader and the generator match
# against this one pattern, so adding a verb is one edit, not four.
_AID_FILES_VERB_RE='^(Create|Modify|Test|Rewrite):[[:space:]]*(.*)$'

# _aid_files_bullet_body <bullet> — the bullet with its leading "- " and verb
# label stripped. Returns 1 (and echoes the bullet unchanged) when there is NO
# verb label, so callers can branch on "is this labelled at all" without a
# second function or a second copy of the vocabulary.
_aid_files_bullet_body() {
  local b="${1#- }"
  if [[ "$b" =~ $_AID_FILES_VERB_RE ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
    return 0
  fi
  printf '%s' "$b"
  return 1
}

# _aid_files_bullet_verb <bullet> — the bullet's verb label (Create/Modify/Test/
# Rewrite), or nothing plus return 1 when it carries none. Same vocabulary, same
# regex as _aid_files_bullet_body; callers that need to know WHAT a bullet
# declares (P085: "does this step found anything?") ask here instead of
# re-matching the label themselves.
_aid_files_bullet_verb() {
  local b="${1#- }"
  [[ "$b" =~ $_AID_FILES_VERB_RE ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# _aid_plan_section <plan> <heading-name> — the body of one `## <name>` section:
# every line after the heading up to the next `## `, verbatim.
#
# A heading MATCHES when it starts with `## <name>` and what follows the name is
# not a word character — so `## Standards (V3)` IS the Standards section (real
# plans annotate their headings) and `## Goals for later` is NOT `## Goal`.
# Three private awks answered this one question about the plan format before
# this existed, and two of them already disagreed about annotated headings.
_aid_plan_section() {
  _aid_blank_fenced < "$1" | awk -v want="## $2" '
    index($0, want) == 1 && substr($0, length(want) + 1, 1) !~ /[A-Za-z0-9]/ { inside = 1; next }
    /^## / { inside = 0 }
    inside
  '
}

# _aid_project_yaml <project-root> <yq-expression> — one scalar (or one block)
# out of `.aid-o/config/project.yaml`. THREE answers, and the third is the whole
# reason this is shared:
#   0  the value, printed
#   1  there is no project.yaml, or the expression yields nothing — a project
#      that simply does not have this setting
#   2  there IS a project.yaml and it could not be read (no yq, unparseable) —
#      a BROKEN ENVIRONMENT, which callers must never round down to "has none"
#
# Rounding 2 down to 1 is how an obligation silently stops applying on a machine
# with no yq, and it is a mistake this codebase has now made twice.
_aid_project_yaml() {
  local cfg="$1/.aid-o/config/project.yaml" out
  [[ -f "$cfg" ]] || return 1
  command -v yq >/dev/null 2>&1 || return 2
  out="$(yq -r "$2" "$cfg" 2>/dev/null)" || return 2
  [[ -n "$out" && "$out" != "null" ]] || return 1
  printf '%s' "$out"
}

# _aid_backtick_paths <text> — every `backtick`-wrapped token in <text> that
# looks like a real repo file: at least one directory segment, a file
# extension, no placeholder brackets, no trailing slash. Directories
# (`<evidence_dir>/jobs/`), command fragments and prose punctuation are not
# file references and must not come back.
#
# Pure bash, deliberately: a grep with PCRE would make this quietly stop
# working on a machine whose grep has none. Two readers share it — the plan
# lint's description-path advisory and the reuse verdict's list of conflicting
# sites — and they must agree on what counts as naming a file.
_aid_backtick_paths() {
  local rest="$1" tok
  while [[ "$rest" == *'`'*'`'* ]]; do
    rest="${rest#*\`}"
    tok="${rest%%\`*}"
    rest="${rest#*\`}"
    [[ "$tok" =~ ^[A-Za-z0-9._/-]+/[A-Za-z0-9._-]+\.[A-Za-z0-9]+$ ]] || continue
    _aid_path_shape_ok "$tok" || continue
    printf '%s\n' "$tok"
  done
}

# _aid_plan_step_bounds <plan> — one line per `### Step` section:
#   "<first-line>\t<last-line>\t<heading>"
# Fence-blanked first, so a plan that QUOTES `### Step 1:` in an example (AID's
# own plans about AID do) is not read as having that step. A section ends at the
# next `### Step` heading, the next `## ` section, or EOF.
#
# This is the join key every per-step obligation needs: the existing
# _aid_extract_files_bullets_numbered already emits "<lineno>\t- <bullet>", so a
# caller buckets bullets into steps by line number instead of re-parsing the
# plan. One reader of the plan's step structure, several consumers (P085).
_aid_plan_step_bounds() {
  _aid_blank_fenced < "$1" | awk '
    function flush() { if (head != "") print start "\t" (NR - 1) "\t" head; head = "" }
    { gsub(/\r$/, "") }
    /^### Step / { flush(); head = $0; start = NR; next }
    /^## /       { flush(); next }
    END { if (head != "") print start "\t" NR "\t" head }
  '
}

# _aid_plan_founding_steps <plan> — the steps that FOUND something: one
# "<first-line>\t<last-line>\t<heading>" per step whose Files block carries a
# `Create:` bullet.
#
# The join between _aid_plan_step_bounds and the numbered bullet stream lives
# here rather than in each caller: three programs needed "which steps found
# something" (the plan lint, the PM page, and any future obligation about
# founding), and three copies of the array-plus-range idiom had already started
# to differ on whether to stop at the first `Create:`.
_aid_plan_founding_steps() {
  local plan="$1" lns=() txts=() ln bullet s e head i verb
  while IFS=$'\t' read -r ln bullet; do
    [[ -z "${bullet:-}" ]] && continue
    lns+=("$ln"); txts+=("$bullet")
  done < <(_aid_extract_files_bullets_numbered < "$plan")
  while IFS=$'\t' read -r s e head; do
    [[ -n "${s:-}" ]] || continue
    for i in "${!lns[@]}"; do
      (( lns[i] >= s && lns[i] <= e )) || continue
      verb="$(_aid_files_bullet_verb "${txts[$i]}")" || continue
      [[ "$verb" == "Create" ]] || continue
      printf '%s\t%s\t%s\n' "$s" "$e" "$head"
      break
    done
  done < <(_aid_plan_step_bounds "$plan")
}

# _aid_plan_step_field <plan> <first-line> <last-line> <label> — the value of one
# `**<label>:**` field inside a step's line range, with its continuation lines
# folded into a single space-separated line (empty output + return 1 when the
# field is absent or carries nothing).
#
# "Carries nothing" is the same rule the band-scoped field check applies: a bare
# label satisfies nothing. The value ends at the next `**Field:**` label, so a
# multi-line answer — which a real Reuse check is — arrives whole.
_aid_plan_step_field() {
  local out
  out="$(_aid_blank_fenced < "$1" | awk -v a="$2" -v b="$3" -v label="$4" '
    NR < a || NR > b { next }
    { gsub(/\r$/, "") }
    $0 ~ "^\\*\\*" label ":\\*\\*" {
      line = $0
      sub("^\\*\\*" label ":\\*\\*[[:space:]]*", "", line)
      val = line; inside = 1; next
    }
    inside && /^\*\*[A-Z][^*]*:\*\*/ { inside = 0 }
    inside { val = val " " $0 }
    END { gsub(/[[:space:]]+/, " ", val); sub(/^ /, "", val); sub(/ $/, "", val); print val }
  ')"
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

_aid_classify_files_bullet() {
  local bullet="${1#- }"
  # P079 Step 5: the two shapes GENERATION refuses outright (aid-plan-to-epic.sh
  # — an unlabelled bullet, and a verb with no path) are ERROR tier here, or
  # this lint would green-light a plan the generator then rejects, which is the
  # one promise this file's header makes.
  local body
  if ! body="$(_aid_files_bullet_body "$bullet")"; then
    echo "error:no-verb-label"
    return
  fi
  if [[ -z "${body//[[:space:]]/}" ]]; then
    echo "error:verb-no-path"
    return
  fi
  local p count=0 bad_shape=0 parsed
  if ! parsed="$(_aid_split_path_entry "$body" 2>/dev/null)"; then
    echo "error:ambiguous-entry"
    return
  fi
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    count=$((count+1))
    _aid_path_shape_ok "$p" || bad_shape=1
  done <<< "$parsed"
  [[ "$bad_shape" -eq 1 ]] && { echo "error:bad-shape"; return; }
  [[ "$count" -eq 0 ]] && { echo "strict:no-path"; return; }
  # Cleaner produced clean path(s). Grammar strictness (cleaner-OK but non-canonical):
  [[ "$body" != '`'* ]] && { echo "strict:no-backtick-path"; return; }
  # Text before the em-dash / "--", with the `backtick path` spans removed: any
  # remaining "(" that is not a (line[s] …) range is prose that belongs after "—".
  local pre="${body%%--*}"
  pre="$(printf '%s' "$pre" | sed 's/\xe2\x80\x94.*//; s/`[^`]*`//g')"
  if [[ "$pre" == *"("* ]]; then
    # `(tier: tN)` joins `(lines …)` in the parenthetical vocabulary (P081
    # Step 10). It goes HERE rather than in the prose after the em-dash for the
    # same reason the line range does: generation has to read it mechanically,
    # and prose is not a place a generator can read anything from.
    local pre_nolines; pre_nolines="$(printf '%s' "$pre" \
      | sed -E 's/\((lines?|řádk[^)]*)[^)]*\)//g; s/\([[:space:]]*tier:[[:space:]]*t[0-2][[:space:]]*\)//g')"
    [[ "$pre_nolines" == *"("* ]] && { echo "strict:non-line-paren"; return; }
  fi
  echo "clean"
}

# _aid_files_bullet_tier <bullet> — the tier a `Test:` bullet declares, or
# nothing plus return 1 when it declares none (P081 Step 10).
#
# ONE authority: generation, the plan lint and any later reader all ask here,
# so the accepted spelling is defined in exactly one place. An unknown value is
# NOT silently ignored — it returns 2, because `(tier: t9)` is a declaration
# somebody meant and the caller must say so rather than treat it as absent.
_aid_files_bullet_tier() {
  local bullet="${1#- }" body decl
  body="$(_aid_files_bullet_body "$bullet")" || body="$bullet"
  if [[ ! "$body" =~ \([[:space:]]*tier:[[:space:]]*([A-Za-z0-9]+)[[:space:]]*\) ]]; then
    return 1
  fi
  decl="${BASH_REMATCH[1]}"
  case "$decl" in
    t0|t1|t2) printf '%s' "$decl"; return 0 ;;
    *) printf '%s' "$decl"; return 2 ;;
  esac
}

# _aid_allowed_paths_from_files_json — derive a step's cleaned allowed_paths
# JSON array from its RAW files[] JSON array (per D2/D4: outputs = files
# verbatim, allowed_paths = cleaned path(s) from the SAME files entries).
# Strips the Create/Modify/Test/Rewrite label from each entry, then runs the
# remainder through _aid_split_path_entry. Order-preserving de-dup.
# Args: $1 = compact JSON array of RAW files[] strings. Output: compact JSON.
# Returns 1 (no JSON printed) if any entry is ambiguous/unparseable — callers
# MUST check the return code; a prior version silently kept whatever path(s)
# were found before the unparseable remainder instead of failing.
_aid_allowed_paths_from_files_json() {
  local files_json="$1"
  local out_json="[]"
  local n idx entry stripped p parsed
  n="$(echo "$files_json" | jq 'length')"
  for (( idx=0; idx<n; idx++ )); do
    entry="$(echo "$files_json" | jq -r --argjson i "$idx" '.[$i]')"
    stripped="$(printf '%s' "$entry" | sed -E 's/^(Create|Modify|Test|Rewrite):[[:space:]]*//')"
    if ! parsed="$(_aid_split_path_entry "$stripped")"; then
      echo "aid-scoping: invalid Files entry at array index ${idx}: ${entry}" >&2
      return 1
    fi
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      out_json="$(echo "$out_json" | jq --arg p "$p" 'if index($p) then . else . + [$p] end')"
    done <<< "$parsed"
  done
  echo "$out_json"
}
