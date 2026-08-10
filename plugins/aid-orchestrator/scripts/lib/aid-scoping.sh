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

# _aid_extract_files_bullets — read text on stdin, emit each top-level Files-block
# bullet as "- <bullet>". Byte-identical to the historical inline awk it replaces.
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
