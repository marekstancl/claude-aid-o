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
# "`a.md` + `b.md`" dual-file convention). Anything else (a "(...)"
# parenthetical, an em-dash/"--" description, or a later backtick span in a
# prose-heavy bullet) stops the run and is discarded as prose. No leading
# backtick span -> fall back to stripping after the first "--"/em-dash.
# Args: $1 = one RAW Files bullet, label stripped. Output: one cleaned path/line.
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
      break
    fi
  done

  if [[ "$found_backtick_path" -eq 0 ]]; then
    local fallback="$entry"
    fallback="${fallback%%--[[:space:]]*}"
    fallback="$(printf '%s' "$fallback" | sed 's/[[:space:]]*\xe2\x80\x94[[:space:]].*//')"
    fallback="${fallback//\`/}"
    fallback="$(printf '%s' "$fallback" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$fallback" ]] && printf '%s\n' "$fallback"
  fi
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
#   (all three strict:* are canonical only for strict plans, advisory for legacy)
#   clean                    canonical: `path`[ + `path`]* [(lines …)] [— prose]
# Uses ONLY the shared cleaner + shape predicate, so its ERROR verdicts are exactly
# the entries the generation-time gate would reject.
_aid_classify_files_bullet() {
  local bullet="${1#- }"
  local body; body="$(printf '%s' "$bullet" | sed -E 's/^(Create|Modify|Test|Rewrite):[[:space:]]*//')"
  local p count=0 bad_shape=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    count=$((count+1))
    _aid_path_shape_ok "$p" || bad_shape=1
  done < <(_aid_split_path_entry "$body")
  [[ "$bad_shape" -eq 1 ]] && { echo "error:bad-shape"; return; }
  [[ "$count" -eq 0 ]] && { echo "strict:no-path"; return; }
  # Cleaner produced clean path(s). Grammar strictness (cleaner-OK but non-canonical):
  [[ "$body" != '`'* ]] && { echo "strict:no-backtick-path"; return; }
  # Text before the em-dash / "--", with the `backtick path` spans removed: any
  # remaining "(" that is not a (line[s] …) range is prose that belongs after "—".
  local pre="${body%%--*}"
  pre="$(printf '%s' "$pre" | sed 's/\xe2\x80\x94.*//; s/`[^`]*`//g')"
  if [[ "$pre" == *"("* ]]; then
    local pre_nolines; pre_nolines="$(printf '%s' "$pre" | sed -E 's/\((lines?|řádk[^)]*)[^)]*\)//g')"
    [[ "$pre_nolines" == *"("* ]] && { echo "strict:non-line-paren"; return; }
  fi
  echo "clean"
}

# _aid_allowed_paths_from_files_json — derive a step's cleaned allowed_paths
# JSON array from its RAW files[] JSON array (per D2/D4: outputs = files
# verbatim, allowed_paths = cleaned path(s) from the SAME files entries).
# Strips the Create/Modify/Test/Rewrite label from each entry, then runs the
# remainder through _aid_split_path_entry. Order-preserving de-dup.
# Args: $1 = compact JSON array of RAW files[] strings. Output: compact JSON.
_aid_allowed_paths_from_files_json() {
  local files_json="$1"
  local out_json="[]"
  local n idx entry stripped p
  n="$(echo "$files_json" | jq 'length')"
  for (( idx=0; idx<n; idx++ )); do
    entry="$(echo "$files_json" | jq -r --argjson i "$idx" '.[$i]')"
    stripped="$(printf '%s' "$entry" | sed -E 's/^(Create|Modify|Test|Rewrite):[[:space:]]*//')"
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      out_json="$(echo "$out_json" | jq --arg p "$p" 'if index($p) then . else . + [$p] end')"
    done < <(_aid_split_path_entry "$stripped")
  done
  echo "$out_json"
}
