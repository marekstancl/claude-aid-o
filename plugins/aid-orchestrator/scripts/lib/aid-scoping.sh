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
