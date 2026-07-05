#!/usr/bin/env bash
# aid-contract-validate.sh — Contract validation gate for plan.json (+ optional task/EPIC.md)
# (P058 Step 4, D5 — blocking gate, vzor scope-check.sh: exit 0/1, JSON stdout)
#
# Usage: aid-contract-validate.sh <plan_json_path> [epic_md_path]
#
# Catches the generator defects P058 exists to fix: outputs/allowed_paths
# broadcast to every step instead of scoped per-step, Acceptance Criteria
# fragmented by a `|`-split bug, and prose leaking into allowed_paths.
#
# Checks (all three always run; `checks[]` in the JSON output carries one
# entry per check regardless of pass/fail):
#
#   per_step_scoping    — multi-step plan (>1 step) where EVERY step's
#                         `outputs` array OR EVERY step's `allowed_paths`
#                         array is byte-identical (broadcast from an
#                         EPIC-level flat section instead of being derived
#                         per-step) -> fail. A mere partial overlap is NOT a
#                         violation; only full identity across ALL steps is.
#
#   ac_no_fragments     — PRIMARILY a count check: each step's
#                         acceptance_criteria array length must equal the
#                         count of source AC bullets attributed to that step.
#                         When epic_md_path is given, the source count comes
#                         from (in priority order):
#                           1. the step's own per-step HTML comment block
#                              `<!-- step-N: files=[...]; ac=[...] -->`
#                              (exact — same mechanism as ui_change_mode);
#                           2. fallback: bullets in the flat
#                              `## Acceptance Criteria` section tagged
#                              `[role]` for this step's role (legacy EPICs
#                              that predate the per-step block).
#                         A `|`-split bug always INCREASES array length vs.
#                         the source, so any mismatch is conclusive. When
#                         epic_md_path is omitted, or neither source is
#                         available for a step, the count check is skipped
#                         for that step (noted in `detail`) and only the
#                         heuristic below determines this check's status.
#
#                         Defense-in-depth (always runs, independent of
#                         epic_md_path): flags any acceptance_criteria
#                         string that, OUTSIDE of balanced backtick-delimited
#                         spans, contains a bare `length ==` or `.enforcements`
#                         substring, or that has an odd (unpaired) count of
#                         `'` characters — all three are the textual
#                         signature of a `|`-split mid-fragment (verified
#                         against the real malformed E-058-1_1/E-057-1_2/
#                         E-057-2_2 plan.json files).
#
#   allowed_paths_shape — backstop to the upstream (D4) path-cleaner: flags
#                         any allowed_paths entry containing whitespace, "("
#                         or ")" — real repo paths never contain these; a
#                         hit means a verb-prefix ("Create/Modify: ") or
#                         trailing prose/parenthetical leaked through.
#
# Exit 0 = contract OK ("pass"). Exit 1 = malformed ("fail" — blocking).
# Stdout = JSON: {"result": "pass"|"fail", "checks": [...], "violations": [...]}
#
# Requirements: bash 4.0+, jq, awk, sed, grep
set -euo pipefail

PLAN_JSON="${1:?plan_json_path required}"
EPIC_MD="${2:-}"

# ---------------------------------------------------------------------------
# Fatal input errors — emit minimal JSON, exit 1 immediately.
# ---------------------------------------------------------------------------
_emit_fatal() {
  local msg="$1"
  jq -n --arg r "fail" --arg d "$msg" \
    '{"result": $r, "checks": [], "violations": [$d]}'
  exit 1
}

[[ -f "$PLAN_JSON" ]] || _emit_fatal "plan.json not found: $PLAN_JSON"
jq . "$PLAN_JSON" >/dev/null 2>&1 || _emit_fatal "plan.json is not valid JSON: $PLAN_JSON"

STEP_COUNT="$(jq '(.steps // []) | length' "$PLAN_JSON")"

CHECKS_JSON="[]"
VIOLATIONS=()

_add_check() {
  local id="$1" status="$2" detail="$3"
  CHECKS_JSON="$(jq --arg id "$id" --arg status "$status" --arg detail "$detail" \
    '. + [{"id": $id, "status": $status, "detail": $detail}]' <<< "$CHECKS_JSON")"
}

# ===========================================================================
# Check 1: per_step_scoping
# ===========================================================================
ps_status="pass"
ps_detail="single-step plan or all steps distinctly scoped — nothing broadcast"

if [[ "$STEP_COUNT" -gt 1 ]]; then
  unique_outputs="$(jq '[.steps[].outputs // []] | unique | length' "$PLAN_JSON")"
  unique_allowed="$(jq '[.steps[].allowed_paths // []] | unique | length' "$PLAN_JSON")"
  if [[ "$unique_outputs" -eq 1 || "$unique_allowed" -eq 1 ]]; then
    ps_status="fail"
    ps_detail="all ${STEP_COUNT} steps share identical outputs and/or allowed_paths (broadcast, not per-step): outputs_unique=${unique_outputs} allowed_paths_unique=${unique_allowed}"
    VIOLATIONS+=("per_step_scoping: ${ps_detail}")
  fi
fi
_add_check "per_step_scoping" "$ps_status" "$ps_detail"

# ===========================================================================
# Check 2: ac_no_fragments
# ===========================================================================

# _ac_block_count <epic_md> <step_num>
#   Parses the per-step "<!-- step-N: files=[...]; ac=[...] -->" HTML
#   comment block (same shape aid-epic-to-json.sh's _aid_parse_scoping_line
#   consumes) and echoes the length of its ac=[...] JSON array. Echoes
#   nothing (empty string) if no such block is found for this step, or it
#   doesn't parse — caller treats that as "no block" and falls back.
_ac_block_count() {
  local epic_md="$1" step_num="$2"
  local prefix="<!-- step-${step_num}: files="
  local line body ac_part

  line="$(grep -m1 -F "$prefix" "$epic_md" 2>/dev/null || true)"
  [[ -z "$line" ]] && return 0
  [[ "$line" == "$prefix"* ]] || return 0
  [[ "$line" == *" -->" ]] || return 0

  body="${line%" -->"}"
  body="${body#"$prefix"}"
  [[ "$body" == *"]; ac=["* ]] || return 0
  # Anchor on the LAST occurrence of "; ac=", not the first (`##` = longest
  # matching prefix removal): a files[] value can itself contain that exact
  # literal substring (e.g. prose describing this very block's own syntax —
  # this is exactly what P058's own plan text does, and is why its
  # self-consistency regen surfaced this). Same fix as
  # aid-epic-to-json.sh's _aid_parse_scoping_line — keep both in sync.
  ac_part="${body##*"; ac="}"

  jq 'length' <<< "$ac_part" 2>/dev/null || true
}

# _ac_role_bullet_count <epic_md> <role>
#   Counts top-level "- [ ]"/"- [x]" bullets under the flat
#   "## Acceptance Criteria" section tagged "[role]" (case-insensitive),
#   ignoring code-fenced and nested (indented) bullets. Echoes 0 if none.
_ac_role_bullet_count() {
  local epic_md="$1" role="$2" role_re
  # Escape regex metacharacters in $role before interpolating into grep -E:
  # `role` comes from plan.json (sourced from the EPIC.md Steps table role
  # column, not the more tightly-validated AC-block role tag), so it is not
  # guaranteed to match [a-z_]+ — an unescaped regex metacharacter (e.g. a
  # typo'd "." or "*") would silently make this count check under- or
  # over-match, degrading it to a false PASS on a real AC-fragmentation
  # defect (CP3 security finding).
  role_re="$(printf '%s' "$role" | sed 's/[][\.^$*+?(){}|\\]/\\&/g')"
  awk '
    /^## Acceptance Criteria/ { found=1; next }
    found && /^## / { exit }
    found {
      if ($0 ~ /^```/) { fence = !fence; next }
      if (fence) next
      if ($0 ~ /^- \[[ x]\]/) print
    }
  ' "$epic_md" 2>/dev/null | grep -ciE "^- \\[[ x]\\] \\[${role_re}\\]" || true
}

# _ac_fragment_smell <text>
#   Defense-in-depth heuristic. Returns 0 (smell found) / 1 (clean).
#   Masks balanced backtick-delimited spans first so legitimate inline code
#   (e.g. "`jq '... | length == 3'`") does not false-positive.
_ac_fragment_smell() {
  local text="$1" masked total_quotes word_internal_quotes bare_quotes

  masked="$(sed -E 's/`[^`]*`/``/g' <<< "$text")"

  grep -qF 'length ==' <<< "$masked" && return 0
  grep -qF '.enforcements' <<< "$masked" && return 0

  # Odd (unpaired) count of "'" signals a truncated `'...'` shell/jq string —
  # but English contractions/possessives ("don't", "step 1's own", and
  # PLURAL possessives like "users'"/"workers'") also contain a "'" that
  # isn't a fragment signal, so those are excluded from the count first.
  # Two shapes are treated as safe:
  #   (a) alnum on BOTH sides ("don't", "user's") — contraction/singular
  #       possessive, or a truncation fragment where something happens to
  #       follow immediately (rare enough not to special-case away).
  #   (b) a LETTER (not digit) before, whitespace/punctuation/end-of-line
  #       after ("users' permissions", "workers'" at end-of-string) —
  #       plural possessive.
  # Shape (b) is deliberately restricted to alpha (curator IMP-168): a
  # truncated numeric/field fragment like "count == 3'" or "items == 5'"
  # has the SAME local shape as a plural possessive at end-of-string
  # (alnum immediately before the quote, nothing after) — the only
  # reliable distinguishing signal is that a real plural noun ends in a
  # LETTER, never a digit, so digit-before-quote-at-end stays counted as
  # bare/suspicious. The two literal substring checks above already catch
  # the two concrete known truncation signatures ("length ==",
  # ".enforcements"); this heuristic only needs to backstop OTHER,
  # unnamed truncated fields — this is defense-in-depth, not the
  # authoritative check (that's the AC-count comparison elsewhere).
  #
  # Operate on $masked, not $text: a well-formed, BALANCED backtick-wrapped
  # jq/shell expression (e.g. "`'.foo | length == 3'`") has its quotes
  # entirely inside a paired backtick span, which the masking above already
  # strips to `` — counting quotes from the raw $text would still see both
  # apostrophes and (since one of them sits right after a digit) miscount
  # parity, false-positiving on legitimate inline code exactly like the kind
  # this function's own docstring says masking exists to protect.
  total_quotes="$(tr -cd "'" <<< "$masked" | wc -c)"
  word_internal_quotes="$(grep -oE "[[:alnum:]]'[[:alnum:]]|[[:alpha:]]'([[:space:][:punct:]]|$)" <<< "$masked" | wc -l)"
  bare_quotes=$(( total_quotes - word_internal_quotes ))
  if (( bare_quotes % 2 != 0 )); then
    return 0
  fi
  return 1
}

ac_status="pass"
ac_issues=()
ac_epic_note=""

if [[ -n "$EPIC_MD" && ! -f "$EPIC_MD" ]]; then
  ac_epic_note="task/EPIC.md not found at given path (${EPIC_MD}) — primary count check skipped for all steps"
elif [[ -z "$EPIC_MD" ]]; then
  ac_epic_note="task/EPIC.md not provided — primary count check skipped; only string-fragment heuristic ran (defense-in-depth)"
fi

for (( i=0; i<STEP_COUNT; i++ )); do
  step_id="$(jq -r ".steps[$i].id" "$PLAN_JSON")"
  step_role="$(jq -r ".steps[$i].role" "$PLAN_JSON")"
  ac_len="$(jq "(.steps[$i].acceptance_criteria // []) | length" "$PLAN_JSON")"

  # --- Primary: count-based (only when a usable task/EPIC.md was given) ---
  if [[ -n "$EPIC_MD" && -f "$EPIC_MD" ]]; then
    step_num="$(sed -E 's/^step_([0-9]+)_.*/\1/' <<< "$step_id")"
    block_count=""
    if [[ "$step_num" =~ ^[0-9]+$ ]]; then
      block_count="$(_ac_block_count "$EPIC_MD" "$step_num")"
    fi

    if [[ -n "$block_count" ]]; then
      if [[ "$ac_len" -ne "$block_count" ]]; then
        ac_status="fail"
        ac_issues+=("${step_id}: acceptance_criteria count ${ac_len} != source ac=[] block count ${block_count} (per-step HTML block)")
      fi
    else
      role_count="$(_ac_role_bullet_count "$EPIC_MD" "$step_role")"
      role_count="${role_count:-0}"
      if [[ "$role_count" -gt 0 && "$ac_len" -ne "$role_count" ]]; then
        ac_status="fail"
        ac_issues+=("${step_id}: acceptance_criteria count ${ac_len} != source bullet count ${role_count} for role [${step_role}] (flat AC section, no per-step block)")
      fi
    fi
  fi

  # --- Defense-in-depth: string-fragment heuristic (always runs) ---
  smelly_idx=()
  for (( j=0; j<ac_len; j++ )); do
    ac_text="$(jq -r ".steps[$i].acceptance_criteria[$j]" "$PLAN_JSON")"
    if _ac_fragment_smell "$ac_text"; then
      smelly_idx+=("$j")
    fi
  done
  if [[ "${#smelly_idx[@]}" -gt 0 ]]; then
    ac_status="fail"
    ac_issues+=("${step_id}: fragment-smell in acceptance_criteria[${smelly_idx[*]}] (bare 'length ==' / '.enforcements' / unpaired quote outside backtick spans)")
  fi
done

if [[ "${#ac_issues[@]}" -gt 0 ]]; then
  ac_detail="$(printf '%s; ' "${ac_issues[@]}")"
  ac_detail="${ac_detail%; }"
  for issue in "${ac_issues[@]}"; do VIOLATIONS+=("ac_no_fragments: ${issue}"); done
elif [[ -n "$ac_epic_note" ]]; then
  ac_detail="$ac_epic_note"
else
  ac_detail="acceptance_criteria counts match source bullets; no fragment-smell found"
fi
_add_check "ac_no_fragments" "$ac_status" "$ac_detail"

# ===========================================================================
# Check 3: allowed_paths_shape
# ===========================================================================
aps_status="pass"
aps_issues=()

for (( i=0; i<STEP_COUNT; i++ )); do
  step_id="$(jq -r ".steps[$i].id" "$PLAN_JSON")"
  n_paths="$(jq "(.steps[$i].allowed_paths // []) | length" "$PLAN_JSON")"
  for (( j=0; j<n_paths; j++ )); do
    p="$(jq -r ".steps[$i].allowed_paths[$j]" "$PLAN_JSON")"
    if [[ "$p" =~ [[:space:]] || "$p" == *"("* || "$p" == *")"* ]]; then
      aps_status="fail"
      aps_issues+=("${step_id}.allowed_paths[${j}]=\"${p}\"")
    fi
  done
done

if [[ "${#aps_issues[@]}" -gt 0 ]]; then
  aps_detail="$(printf '%s; ' "${aps_issues[@]}")"
  aps_detail="${aps_detail%; }"
  for issue in "${aps_issues[@]}"; do VIOLATIONS+=("allowed_paths_shape: ${issue}"); done
else
  aps_detail="all allowed_paths entries are path-like (no whitespace/parens)"
fi
_add_check "allowed_paths_shape" "$aps_status" "$aps_detail"

# ===========================================================================
# Aggregate result
# ===========================================================================
result="pass"
if [[ "$ps_status" == "fail" || "$ac_status" == "fail" || "$aps_status" == "fail" ]]; then
  result="fail"
fi

if [[ "${#VIOLATIONS[@]}" -gt 0 ]]; then
  violations_json="$(printf '%s\n' "${VIOLATIONS[@]}" | jq -R . | jq -cs .)"
else
  violations_json="[]"
fi

jq -n --arg result "$result" --argjson checks "$CHECKS_JSON" --argjson violations "$violations_json" \
  '{"result": $result, "checks": $checks, "violations": $violations}'

[[ "$result" == "pass" ]] && exit 0
exit 1
