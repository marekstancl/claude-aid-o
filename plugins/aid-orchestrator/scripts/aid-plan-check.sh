#!/usr/bin/env bash
# =============================================================================
# aid-plan-check.sh — the deterministic half of plan review, in one command.
#
# Runs aid-plan-lint.sh and then everything a script can decide about a plan
# WITHOUT a model: the plan's internal consistency (A), the plan against the
# repository (B), and — after a revision — the claims the revision ADDED (C).
# The model reviewers get what is left, plus this report.
#
# Why it exists (2026-09-17, ACTA P025 + Agents P005 pilots): 9 of 16 findings
# of a first review were script-decidable; 19-45 % of new findings per round
# were produced by the fixes themselves; rounds did not converge because fixes
# kept ADDING behaviour. Each check below names the pilot observation it comes
# from. The design record is docs/plans/cp1-skriptove-kontroly.md.
#
# Levels:  BLOCK — exit 1, the plan is not ready for reviewers or generation.
#          WARN  — reported, handed to the reviewers as "look here", exit 0.
#
# Usage:
#   aid-plan-check.sh <plan.md> [--project-root <dir>] [--json <out.json>]
#                     [--snapshot <previous-plan.md> --fixes <steps>]
#                     [--strict|--legacy] [--run-cmds] [--quiet]
#
# --run-cmds  lets B7 EXECUTE each `cmd:` verification pattern (timeout 20 s,
#             cwd = project root) to see whether it already passes on HEAD. Off
#             by default and off in the generation gate: a plan is model-written
#             text, and a `cmd:` may write, migrate or delete. Opt in only when
#             you have read every cmd: in the plan.
#
# Two tiers, the same two the lint has: a plan with `lifecycle_strict: true`
# (the template default) is BLOCKED by every finding marked BLOCK; a legacy plan
# is blocked only by what would break generation (A1 cycle / missing step, A2,
# A6, B8, C5) and hears the rest as "[WARN legacy]". --strict / --legacy force.
#
#   --snapshot  the plan as it was BEFORE the revision being checked (C checks)
#   --fixes     comma-separated step numbers the revision was allowed to touch
#               (e.g. "3,7,12"); required together with --snapshot
#   --json      write a machine-readable report (sha256 of the plan, findings)
#
# Exit: 0 = no BLOCK findings   1 = BLOCK finding(s)   2 = usage / IO error
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"
# shellcheck source=lib/aid-plan-graph.sh
source "${SCRIPT_DIR}/lib/aid-plan-graph.sh"

PLAN="" ROOT="" JSON_OUT="" SNAPSHOT="" FIXES="" QUIET=0 FORCE_MODE="" RUN_CMDS="${AID_PLAN_CHECK_RUN_CMDS:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) ROOT="${2:-}"; shift 2 ;;
    --json)         JSON_OUT="${2:-}"; shift 2 ;;
    --snapshot)     SNAPSHOT="${2:-}"; shift 2 ;;
    --fixes)        FIXES="${2:-}"; shift 2 ;;
    --quiet)        QUIET=1; shift ;;
    --run-cmds)     RUN_CMDS=1; shift ;;
    --strict)       FORCE_MODE="strict"; shift ;;
    --legacy)       FORCE_MODE="legacy"; shift ;;
    -*) echo "aid-plan-check: unknown option: $1" >&2; exit 2 ;;
    *)  PLAN="$1"; shift ;;
  esac
done
[[ -n "$PLAN" ]] || { echo "Usage: aid-plan-check.sh <plan.md> [--project-root <dir>] [--json <out>] [--snapshot <prev.md> --fixes <steps>] [--quiet]" >&2; exit 2; }
[[ -f "$PLAN" ]] || { echo "aid-plan-check: file not found: $PLAN" >&2; exit 2; }
if [[ -n "$SNAPSHOT" || -n "$FIXES" ]]; then
  [[ -n "$SNAPSHOT" && -n "$FIXES" ]] || { echo "aid-plan-check: --snapshot and --fixes go together (C1: no revision without a snapshot and a fix list)" >&2; exit 2; }
  [[ -f "$SNAPSHOT" ]] || { echo "aid-plan-check: snapshot not found: $SNAPSHOT" >&2; exit 2; }
fi
PLAN="$(realpath "$PLAN")"

# Project root: given, else the nearest ancestor holding .aid-o/, else the git
# toplevel of the plan's directory. A plan checked outside any project still
# gets the A checks; B checks then report what they could not verify.
if [[ -z "$ROOT" ]]; then
  d="$(dirname "$PLAN")"
  while [[ "$d" != "/" ]]; do
    [[ -d "$d/.aid-o" ]] && { ROOT="$d"; break; }
    d="$(dirname "$d")"
  done
  [[ -n "$ROOT" ]] || ROOT="$(git -C "$(dirname "$PLAN")" rev-parse --show-toplevel 2>/dev/null || true)"
fi

MODE="$FORCE_MODE"
if [[ -z "$MODE" ]]; then
  if grep -qE '^lifecycle_strict:[[:space:]]*true' "$PLAN" 2>/dev/null; then MODE="strict"; else MODE="legacy"; fi
fi
ALWAYS_BLOCK=" LINT A1 A2 A6 B8 C5 "
BLOCKS=() WARNS=() LEGACY=() UNKNOWN_IDS="" REV_UNKNOWN_IDS=""
_block() {   # id, location, message — downgraded on a legacy plan unless structural
  if [[ "$MODE" == "strict" || "$ALWAYS_BLOCK" == *" $1 "* ]]; then BLOCKS+=("$1	$2	$3"); else LEGACY+=("$1	$2	$3"); fi
}
_warn()  { WARNS+=("$1	$2	$3"); }

# ---------------------------------------------------------------------------
# Plan model: steps, fields, bullets. One read, several consumers.
# ---------------------------------------------------------------------------
BLANKED="$(_aid_blank_fenced < "$PLAN")"
TOTAL_LINES="$(wc -l < "$PLAN")"

declare -a STEP_S=() STEP_E=() STEP_N=() STEP_HEAD=()
while IFS=$'\t' read -r s e head; do
  [[ -n "${s:-}" ]] || continue
  n="$(sed -E 's/^### Step ([0-9]+).*/\1/' <<< "$head")"
  [[ "$n" =~ ^[0-9]+$ ]] || n=""
  STEP_S+=("$s"); STEP_E+=("$e"); STEP_N+=("$n"); STEP_HEAD+=("$head")
done < <(_aid_plan_step_bounds "$PLAN")
NSTEPS="${#STEP_S[@]}"

# _field_lines <s> <e> <label> — raw lines of one **Label:** field (label line
# excluded), ending at the next **Label:** or the step end.
_field_lines() {
  printf '%s\n' "$BLANKED" | awk -v a="$1" -v b="$2" -v label="$3" '
    NR < a || NR > b { next }
    $0 ~ "^\\*\\*" label ":\\*\\*" { inside = 1; rest = $0; sub("^\\*\\*" label ":\\*\\*[[:space:]]*", "", rest); if (rest ~ /[^[:space:]]/) print rest; next }
    inside && /^\*\*[A-Z][^*]*:\*\*/ { inside = 0 }
    inside { print }
  '
}
_step_index_for_line() { local ln="$1" i; for i in "${!STEP_S[@]}"; do (( ln >= STEP_S[i] && ln <= STEP_E[i] )) && { printf '%s' "$i"; return 0; }; done; return 1; }

# Files bullets with line numbers, verb and cleaned paths.
declare -a FB_LN=() FB_VERB=() FB_PATHS=()
while IFS=$'\t' read -r ln bullet; do
  [[ -n "${bullet:-}" ]] || continue
  verb="$(_aid_files_bullet_verb "$bullet")" || verb=""
  body="$(_aid_files_bullet_body "$bullet")" || true
  paths="$(_aid_split_path_entry "$body" 2>/dev/null | tr '\n' ' ')"
  FB_LN+=("$ln"); FB_VERB+=("$verb"); FB_PATHS+=("$paths")
done < <(_aid_extract_files_bullets_numbered < "$PLAN")
ALL_FILES_PATHS="$(printf '%s\n' "${FB_PATHS[@]:-}" | tr ' ' '\n' | grep -v '^$' | sort -u)"
CREATE_PATHS="$(for i in "${!FB_LN[@]}"; do [[ "${FB_VERB[$i]}" == "Create" ]] && printf '%s\n' ${FB_PATHS[$i]}; done | sort -u)"
_in_list() { grep -qxF -- "$1" <<< "$2"; }
# Every file the project has (tracked + untracked-not-ignored), once. Prose names
# files by their tail as often as by their full path (`export/router.py` for
# backend/acta/export/router.py), and the pilots' plans did exactly that.
REPO_FILES=""
if [[ -n "$ROOT" && -d "$ROOT" ]]; then
  # The workspace (.aid-o/) is not the repository: a plan, its evidence and its
  # queue are not files a plan can modify, and a project with nothing else in it
  # has nothing to ground against.
  REPO_FILES="$( (git -C "$ROOT" ls-files -co --exclude-standard 2>/dev/null || find "$ROOT" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -printf '%P\n' 2>/dev/null) | grep -vE '^\.aid-o/' | grep -vxF -- "${PLAN#"$ROOT"/}" )"
fi
_abs() { if [[ "$1" == /* ]]; then printf '%s' "$1"; else printf '%s/%s' "$ROOT" "$1"; fi; }
_exists() { [[ -e "$(_abs "$1")" ]]; }
_esc_re() { printf '%s' "$1" | sed -E 's/[][\\.^$*+?(){}|/]/\\&/g'; }
_known_path() { # exists, or declared in some step's Files, or a repo/declared file ends with it
  local p="$1" re
  [[ "$p" == *"..."* ]] && return 0
  _exists "$p" && return 0
  _in_list "$p" "$ALL_FILES_PATHS" && return 0
  re="(^|/)$(_esc_re "$p")\$"
  grep -qE -- "$re" <<< "$ALL_FILES_PATHS" && return 0
  grep -qE -- "$re" <<< "$REPO_FILES" && return 0
  return 1
}
_created_before_step() { # <path> <step-number> — a Create bullet in a lower-numbered step
  local p="$1" n="$2" i idx
  for i in "${!FB_LN[@]}"; do
    [[ "${FB_VERB[$i]}" == "Create" ]] || continue
    _in_list "$p" "$(tr ' ' '\n' <<< "${FB_PATHS[$i]}")" || continue
    idx="$(_step_index_for_line "${FB_LN[$i]}")" || continue
    [[ -n "${STEP_N[$idx]}" && "${STEP_N[$idx]}" -lt "$n" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# 0. The existing lint, verbatim. Its BLOCKing verdict is ours too.
# ---------------------------------------------------------------------------
LINT_OUT="$(bash "${SCRIPT_DIR}/aid-plan-lint.sh" "$PLAN" 2>&1)"; LINT_RC=$?
if [[ $LINT_RC -eq 1 ]]; then _block "LINT" "$PLAN" "aid-plan-lint.sh reports blocking violation(s) — run it for the list"; fi
[[ $LINT_RC -eq 2 ]] && _warn "LINT" "$PLAN" "aid-plan-lint.sh could not run (rc=2): ${LINT_OUT##*$'\n'}"

# ---------------------------------------------------------------------------
# A. Internal consistency (plan.md only)
# ---------------------------------------------------------------------------
# A2 — step numbers unique and contiguous 1..N; High-Level table agrees.
if (( NSTEPS > 0 )); then
  nums="$(printf '%s\n' "${STEP_N[@]}" | grep -v '^$' | sort -n)"
  dup="$(uniq -d <<< "$nums" | head -1)"
  [[ -n "$dup" ]] && _block "A2" "$PLAN" "step number ${dup} is used twice"
  expected="$(seq 1 "$NSTEPS" | tr '\n' ' ')"; got="$(tr '\n' ' ' <<< "$nums")"
  [[ "$expected" == "$got" ]] || _block "A2" "$PLAN" "step numbers are not 1..${NSTEPS}: found [${got% }]"
  rows="$(_aid_plan_section "$PLAN" "High-Level Steps" | grep -cE '^\| *[0-9]+ *\|' || true)"
  if (( rows > 0 && rows != NSTEPS )); then _warn "A2" "$PLAN" "## High-Level Steps lists ${rows} step row(s) but the plan has ${NSTEPS} ### Step sections"; fi
fi

# A1 — dependency graph: every `Depends on:` names an existing step; no cycles.
if (( NSTEPS > 0 )); then
  ids="$(printf '%s\n' "${STEP_N[@]}" | grep -v '^$')"; edges=""
  for i in "${!STEP_S[@]}"; do
    n="${STEP_N[$i]}"; [[ -n "$n" ]] || continue
    dep="$(_field_lines "${STEP_S[$i]}" "${STEP_E[$i]}" "Dependencies" | grep -i "depends on:" | sed -E 's/.*[Dd]epends on:[[:space:]]*//; s/ *[-—] *[Bb]locks:.*//' | head -1)"
    [[ -z "$dep" || "$dep" =~ ^[[:space:]]*(none|žádné|nic)([[:space:]]|$|[.,]) ]] && continue
    dep="${dep%%—*}"
    # "Step 3", "Step 3, Step 5", "Steps 1-6" — reasons after the numbers are prose.
    for tok in $(grep -oE 'Steps? *[0-9]+( *[-–] *[0-9]+)?' <<< "$dep" | sed -E 's/Steps? *//; s/ //g'); do
      if [[ "$tok" =~ ^([0-9]+)[-–]([0-9]+)$ ]]; then range="$(seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")"; else range="$tok"; fi
      for d in $range; do
        _in_list "$d" "$ids" || { _block "A1" "$PLAN:${STEP_S[$i]}" "Step ${n} depends on Step ${d}, which does not exist"; continue; }
        [[ "$d" == "$n" ]] && { _block "A1" "$PLAN:${STEP_S[$i]}" "Step ${n} depends on itself"; continue; }
        edges+="${d}->${n}"$'\n'
      done
    done
  done
  graph="$(build_plan_graph "$ids" "$edges" 2>/dev/null)" || graph=""
  cyc="$(jq -r '.cycles // [] | join(", ")' <<< "$graph" 2>/dev/null)"
  [[ -n "$cyc" ]] && _block "A1" "$PLAN" "dependency cycle between steps: ${cyc}"
fi

# A3 — M/L steps: at least 3 acceptance criteria and 3 edge cases.
# Items are bullets, numbered lines, or inline (a) (b) (c) markers — the
# pilots' plans used all three shapes.
_count_items() {
  local txt="$1" b n l
  b="$(grep -cE '^[[:space:]]*[-*] ' <<< "$txt" || true)"
  n="$(grep -cE '^[[:space:]]*[0-9]+[.)] ' <<< "$txt" || true)"
  l="$(grep -oE '\([a-z]\)' <<< "$txt" | sort -u | wc -l)"
  local best=$(( b > n ? (b > l ? b : l) : (n > l ? n : l) ))
  # Unmarked prose: count the clauses the author separated with ";" or full stops.
  if (( best == 0 )) && [[ "$txt" =~ [^[:space:]] ]]; then
    best="$(tr '\n' ' ' <<< "$txt" | grep -oE ';|\. [[:upper:]]|\.$' | wc -l)"; (( best == 0 )) && best=1
  fi
  printf '%s' "$best"
}
for i in "${!STEP_S[@]}"; do
  eff="$(_field_lines "${STEP_S[$i]}" "${STEP_E[$i]}" "Effort" | head -1 | awk '{print toupper($1)}')"
  [[ "$eff" == "M" || "$eff" == "L" ]] || continue
  ac="$(_count_items "$(_field_lines "${STEP_S[$i]}" "${STEP_E[$i]}" "Acceptance Criteria")")"
  ec="$(_count_items "$(_field_lines "${STEP_S[$i]}" "${STEP_E[$i]}" "Edge Cases")")"
  (( ac >= 3 )) || _block "A3" "$PLAN:${STEP_S[$i]}" "Step ${STEP_N[$i]} (effort ${eff}) has ${ac} acceptance criteria, needs at least 3"
  (( ec >= 3 )) || _block "A3" "$PLAN:${STEP_S[$i]}" "Step ${STEP_N[$i]} (effort ${eff}) has ${ec} edge cases, needs at least 3"
done

# A4 — forbidden shortcut phrases (skills/plan-writing.md table + Czech twins).
FORBIDDEN=(
  "implement standard error handling" "follow existing patterns" "add appropriate validation"
  "handle edge cases" "update tests accordingly" "see brainstorming notes" "and other necessary changes"
  "as needed" "standard REST/CRUD operations" "proper logging" "handle authentication"
  "refactor as necessary" "configure appropriately" "and so on" "appropriate AC" "edge cases handled"
  "as appropriate" "as the case may be"
  "atd." "apod." "a podobně" "dle potřeby" "podle potřeby" "a další nezbytné" "standardní ošetření chyb"
  "vhodnou validaci" "podle existujících vzorů"
  "případně" "ověřit při implementaci" "ověří se při implementaci" "verify during implementation" "TBD" "TODO:"
)
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  _block "A4" "$PLAN:${hit%%:*}" "forbidden shortcut phrase: ${hit#*:}"
done < <(printf '%s\n' "$BLANKED" | awk -v phrases="$(IFS='|'; printf '%s' "${FORBIDDEN[*]}")" '
  BEGIN { n = split(phrases, p, "|") }
  { low = tolower($0); for (i = 1; i <= n; i++) if (index(low, tolower(p[i]))) { print NR ":" p[i]; break } }
  ' | head -40)
# "etc." and a trailing "..." are the two shortcuts a word list cannot express.
while IFS= read -r ln; do [[ -n "$ln" ]] && _block "A4" "$PLAN:$ln" "forbidden shortcut phrase: etc. / trailing ..."; done < <(printf '%s\n' "$BLANKED" | grep -nE '(\betc\.|[^.]\.\.\.[[:space:]]*$)' | grep -vE '^[0-9]+:[[:space:]]*(\||#)' | cut -d: -f1 | head -20)

# Grounding needs a repository with files in it. A bare directory (a fixture,
# a project scaffolded a minute ago) has nothing to ground against, so A5, A7
# and every B check stay silent there and say so once.
HAS_REPO=0; [[ -n "$ROOT" && -d "$ROOT" && -n "$REPO_FILES" ]] && HAS_REPO=1

# A5 — a path named in acceptance criteria is in some step's Files or exists.
(( HAS_REPO )) && for i in "${!STEP_S[@]}"; do
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    _known_path "$p" && continue
    _block "A5" "$PLAN:${STEP_S[$i]}" "Step ${STEP_N[$i]} acceptance criteria name \`${p}\`, which no step's Files declares and which does not exist"
  done < <(_aid_backtick_paths "$(_field_lines "${STEP_S[$i]}" "${STEP_E[$i]}" "Acceptance Criteria" | tr '\n' ' ')" | sort -u)
done

# A6 — verification_pattern blocks: valid type, required keys, no placeholders.
# (Read from the RAW plan: the blocks live inside fences.)
VP_BLOCKS="$(awk '
  /verification_pattern:/ { inside = 1; start = NR; blk = ""; next }
  inside && /^[[:space:]]*```/ { print start "\t" blk; inside = 0; next }
  inside { gsub(/^[[:space:]]+/, ""); blk = blk $0 "|" }
' "$PLAN")"
while IFS=$'\t' read -r ln blk; do
  [[ -n "${ln:-}" ]] || continue
  typ="$(tr '|' '\n' <<< "$blk" | grep -E '^type:' | head -1 | sed -E 's/^type:[[:space:]]*//; s/["'\'']//g')"
  case "$typ" in
    cmd)            tr '|' '\n' <<< "$blk" | grep -qE '^cmd:' || _block "A6" "$PLAN:$ln" "verification_pattern type cmd without cmd:" ;;
    must_not_exist) tr '|' '\n' <<< "$blk" | grep -qE '^file:' || _block "A6" "$PLAN:$ln" "verification_pattern type must_not_exist without file:" ;;
    must_contain)   { tr '|' '\n' <<< "$blk" | grep -qE '^file:' && tr '|' '\n' <<< "$blk" | grep -qE '^regex:'; } || _block "A6" "$PLAN:$ln" "verification_pattern type must_contain needs file: and regex:" ;;
    *)              _block "A6" "$PLAN:$ln" "verification_pattern type '${typ:-<missing>}' is not one of cmd | must_not_exist | must_contain" ;;
  esac
  grep -qE '<[A-Za-z_ -]+>|\{[A-Za-z_ -]+\}' <<< "$blk" && _block "A6" "$PLAN:$ln" "verification_pattern carries a placeholder (<...> or {...})"
done <<< "$VP_BLOCKS"

# A7 — a Modify:/Rewrite: path that neither exists nor is created by an earlier step.
(( HAS_REPO )) && for i in "${!FB_LN[@]}"; do
  [[ "${FB_VERB[$i]}" == "Modify" || "${FB_VERB[$i]}" == "Rewrite" ]] || continue
  idx="$(_step_index_for_line "${FB_LN[$i]}")" || continue
  n="${STEP_N[$idx]}"
  for p in ${FB_PATHS[$i]}; do
    [[ -n "$ROOT" ]] || { _warn "A7" "$PLAN:${FB_LN[$i]}" "cannot verify \`${p}\` exists: no project root"; continue; }
    _exists "$p" && continue
    _created_before_step "$p" "${n:-0}" && continue
    _block "A7" "$PLAN:${FB_LN[$i]}" "Step ${n} modifies \`${p}\`, which does not exist and no earlier step creates"
  done
done

# A8 — empty ## sections; template placeholders left in prose.
while IFS= read -r ln; do [[ -n "$ln" ]] && _block "A8" "$PLAN:$ln" "empty section: $(sed -n "${ln}p" "$PLAN")"; done < <(printf '%s\n' "$BLANKED" | awk '
  /^## / { if (head != "" && !content) print hl; head = $0; hl = NR; content = 0; next }
  /^# /  { next }
  head != "" && $0 ~ /[^[:space:]]/ { content = 1 }
  END { if (head != "" && !content) print hl }')
while IFS= read -r ln; do [[ -n "$ln" ]] && _warn "A8" "$PLAN:$ln" "template placeholder left in text: $(sed -n "${ln}p" "$PLAN" | grep -oE '\{[A-Z][A-Za-z ]*\}' | head -1)"; done < <(printf '%s\n' "$BLANKED" | grep -nE '\{[A-Z][A-Za-z ]*\}' | cut -d: -f1 | head -10)

# A10 — two Files bullets in one step with the same description (ACTA R5: a
# mechanical split of a multi-file bullet copied the whole text into each half).
for i in "${!STEP_S[@]}"; do
  dupe="$(for j in "${!FB_LN[@]}"; do
            (( FB_LN[j] >= STEP_S[i] && FB_LN[j] <= STEP_E[i] )) || continue
            d="$(sed -n "${FB_LN[$j]}p" "$PLAN")"; d="${d#*—}"; d="${d#*--}"
            [[ ${#d} -ge 60 ]] && printf '%s\n' "$d"
          done | sort | uniq -d | head -1)"
  [[ -n "$dupe" ]] && _block "A10" "$PLAN:${STEP_S[$i]}" "Step ${STEP_N[$i]} has two Files bullets with the same description — say per file what changes there: ${dupe:0:80}…"
done

# A9 — size: the pilots could not review a 16-step / 1200-line plan to a close.
(( NSTEPS > 10 )) && _warn "A9" "$PLAN" "${NSTEPS} steps — plans this size did not converge in the pilots (ACTA P025: 16 steps); consider splitting"
(( TOTAL_LINES > 800 )) && _warn "A9" "$PLAN" "${TOTAL_LINES} lines — consider splitting (see A9 on steps)"

# ---------------------------------------------------------------------------
# B. The plan against the repository (grounding). Needs a project root.
# ---------------------------------------------------------------------------
_grep_repo() { # <fixed-string> — hits in the project's CODE (not markdown, not workspace/vcs dirs)
  grep -rIlF --exclude-dir=.git --exclude-dir=.aid-o --exclude-dir=node_modules --exclude-dir=.aid-worktrees --exclude='*.md' -- "$1" "$ROOT" 2>/dev/null | head -1
}
if (( HAS_REPO )); then
  # B1 — every backticked path in prose exists or is created by a Create bullet.
  FILES_LINES="$(printf '%s\n' "${FB_LN[@]:-}" | grep -v '^$')"
  while IFS=$'\t' read -r ln p; do
    [[ -n "${p:-}" ]] || continue
    _in_list "$ln" "$FILES_LINES" && continue           # Files bullets: lint + A7/B8 own those
    _known_path "$p" && continue
    if [[ "$p" != /* ]] && grep -qE "^${p%%/*}/" <<< "$REPO_FILES"; then
      _block "B1" "$PLAN:$ln" "\`${p}\` does not exist and no step creates it"
    else
      _warn "B1" "$PLAN:$ln" "\`${p}\` is not in this repository (another repo, or a typo?) — say which"
    fi
  done < <(printf '%s\n' "$BLANKED" | awk '{ print NR "\t" $0 }' | while IFS=$'\t' read -r ln line; do
             [[ "$line" == *'`'* ]] || continue
             while IFS= read -r p; do [[ -n "$p" ]] && printf '%s\t%s\n' "$ln" "$p"; done < <(_aid_backtick_paths "$line")
           done | sort -u -t$'\t' -k2,2 -k1,1n)

  # B2 — (lines ~N-M) ranges fit the file.
  for i in "${!FB_LN[@]}"; do
    line="$(sed -n "${FB_LN[$i]}p" "$PLAN")"
    [[ "$line" =~ \(lines[[:space:]]*~?[[:space:]]*([0-9]+)[[:space:]]*[-–][[:space:]]*~?([0-9]+)\) ]] || continue
    hi="${BASH_REMATCH[2]}"
    for p in ${FB_PATHS[$i]}; do
      _exists "$p" || continue
      have="$(wc -l < "$(_abs "$p")")"
      (( hi <= have + 5 )) || _warn "B2" "$PLAN:${FB_LN[$i]}" "\`${p}\` has ${have} lines, the plan cites lines up to ${hi}"
      lo="${BASH_REMATCH[1]}"
      # Symbols named on the same bullet: found in the file, but nowhere near the cited lines?
      for sym in $(grep -oE '`[A-Za-z_][A-Za-z0-9_]{4,}`' <<< "${line#*—}" | tr -d '`' | grep -E '_|[a-z][A-Z]|^[A-Z0-9_]{4,}$' | sort -u | head -6); do
        [[ "$p" == *"$sym"* ]] && continue
        hits="$(grep -nwF -- "$sym" "$(_abs "$p")" | cut -d: -f1)"
        [[ -n "$hits" ]] || continue
        near=0; for h in $hits; do (( h >= lo - 40 && h <= hi + 40 )) && { near=1; break; }; done
        (( near )) || _warn "B2" "$PLAN:${FB_LN[$i]}" "\`${sym}\` is at line $(head -1 <<< "$hits") of \`${p}\`, not near the cited ${lo}-${hi} — stale line range?"
      done
    done
  done

  # B3 — a file the plan promises to remove must exist today.
  while IFS=$'\t' read -r ln blk; do
    [[ -n "${ln:-}" ]] || continue
    f="$(tr '|' '\n' <<< "$blk" | grep -E '^file:' | head -1 | sed -E 's/^file:[[:space:]]*//; s/["'\'']//g')"
    tr '|' '\n' <<< "$blk" | grep -qE '^type:[[:space:]]*"?must_not_exist' || continue
    [[ -n "$f" ]] && ! _exists "$f" && _block "B3" "$PLAN:$ln" "must_not_exist \`${f}\` — the file is already absent, the criterion proves nothing"
  done <<< "$VP_BLOCKS"
  while IFS=$'\t' read -r ln p; do
    [[ -n "${p:-}" ]] || continue
    _exists "$p" || _warn "B3" "$PLAN:$ln" "the plan says to delete \`${p}\`, which does not exist"
  done < <(printf '%s\n' "$BLANKED" | grep -niE '(smazat|smaže|odstranit|delete|remove) +`' | while IFS=: read -r ln rest; do
             while IFS= read -r p; do [[ -n "$p" ]] && printf '%s\t%s\n' "$ln" "$p"; done < <(_aid_backtick_paths "$rest"); done)

  # B4 — what `## Resources Verification` claims EXISTS must exist. The block is
  # the author's own list of presumed helpers / env vars; a name there that no
  # file in the repository contains was invented (Agents P005: 9 of 16 findings).
  # Entries the author marks as new ("nová", "new", "Step N", "zavádí", "vzniká")
  # are claims about the plan, not the repo, and are skipped.
  RES_BLOCK="$(_aid_plan_section "$PLAN" "Resources Verification")"
  RES_TOKENS="$(grep -iE '^- \[.\] *(Functions|Environment|Env|Commands|External)' <<< "$RES_BLOCK" | while IFS= read -r line; do
    rest="${line#*:}"
    while [[ "$rest" == *'`'*'`'* ]]; do
      rest="${rest#*\`}"; tok="${rest%%\`*}"; rest="${rest#*\`}"
      note="${rest%%\`*}"                       # what follows this token up to the next one
      [[ "$tok" =~ ^(--)?[A-Za-z_][A-Za-z0-9_.-]*$ ]] || continue
      grep -qiE '\b(nov[áý]|new|zav[áa]d[íi]|vznik|Step [0-9]+|ruší|zaniká|to be created|mimo repo|outside|external|obraz|image|container|kontejner|docker|compose)\b' <<< "$note" && continue
      tok="${tok##*.}"                          # `module.NAME` → the name is what source code contains
      printf '%s\n' "$tok"
    done
  done | sort -u)"
  if [[ -n "$RES_TOKENS" ]]; then
    found="$(grep -rIohF --exclude-dir=.git --exclude-dir=.aid-o --exclude-dir=node_modules --exclude-dir=.aid-worktrees --exclude="$(basename "$PLAN")" --exclude='*.md' -f <(printf '%s\n' "$RES_TOKENS") "$ROOT" 2>/dev/null | sort -u)"
    # Names the plan itself founds are claims about the plan, not the repo:
    # the stem of any Create:/Test: path, or a name written on a Create: bullet.
    PLAN_OWN_NAMES="$(
      for i in "${!FB_LN[@]}"; do
        [[ "${FB_VERB[$i]}" == "Create" || "${FB_VERB[$i]}" == "Test" ]] || continue
        for p in ${FB_PATHS[$i]}; do b="${p##*/}"; printf '%s\n' "${b%%.*}"; done
        [[ "${FB_VERB[$i]}" == "Create" ]] && sed -n "${FB_LN[$i]}p" "$PLAN" | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`'
      done | sort -u)"
    while IFS= read -r t; do
      [[ -n "$t" ]] || continue
      _in_list "$t" "$found" && continue
      _in_list "$t" "$PLAN_OWN_NAMES" && continue
      command -v "$t" >/dev/null 2>&1 && continue
      _block "B4" "$PLAN" "## Resources Verification lists \`${t}\` as existing, but nothing in the repository contains it"
    done <<< "$RES_TOKENS"
  else
    _warn "B4" "$PLAN" "## Resources Verification names no existing functions / env vars / commands — the reviewers cannot tell what the plan presumes"
  fi
  # B5 — external commands the plan relies on must be on this machine.
  grep -iE '^- \[.\] *(External commands|Commands)' <<< "$RES_BLOCK" | while IFS= read -r line; do
    rest="${line#*:}"
    while [[ "$rest" == *'`'*'`'* ]]; do
      rest="${rest#*\`}"; c="${rest%%\`*}"; rest="${rest#*\`}"; note="${rest%%\`*}"
      [[ "$c" =~ ^[a-z][a-z0-9_.-]*$ ]] || continue
      grep -qiE 'obraz|image|container|kontejner|docker|compose|v CI|in CI' <<< "$note" && continue
      command -v "$c" >/dev/null 2>&1 || printf '%s\n' "$c"
    done
  done | sort -u | while IFS= read -r c; do [[ -n "$c" ]] && _warn "B5" "$PLAN" "external command \`${c}\` is not installed here (Resources Verification lists it; say \"v obrazu <x>\" if it lives in a container)"; done
  # Identifiers in step prose with no hit anywhere in the repo: not a finding
  # (most are the plan's own new names) but handed to the reviewers as a list.
  UNKNOWN_IDS="$(printf '%s\n' "$BLANKED" | grep -oE '`[A-Za-z_][A-Za-z0-9_]*(\(\))?`|`[A-Z][A-Z0-9_]{3,}`' | tr -d '`' | sed 's/()$//' | grep -E '_|^[A-Z0-9_]+$' | sort -u)"
  if [[ -n "$UNKNOWN_IDS" ]]; then
    found="$(grep -rIohF --exclude-dir=.git --exclude-dir=.aid-o --exclude-dir=node_modules --exclude-dir=.aid-worktrees --exclude="$(basename "$PLAN")" --exclude='*.md' -f <(printf '%s\n' "$UNKNOWN_IDS") "$ROOT" 2>/dev/null | sort -u)"
    UNKNOWN_IDS="$(comm -23 <(printf '%s\n' "$UNKNOWN_IDS") <(printf '%s\n' "$found"))"
  fi

  # B6 — backlog ids claimed by a commit in the last 24 h.
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    for id in $(printf '%s\n' "$BLANKED" | grep -oE '\b(T|IMP|B)-[0-9]+\b' | sort -u); do
      sha="$(git -C "$ROOT" log --since='24 hours ago' --all --grep="$id" --format=%h 2>/dev/null | head -1)"
      [[ -n "$sha" ]] && _warn "B6" "$PLAN" "${id} already appears in commit ${sha} (last 24 h) — allocated twice?"
    done
  fi

  # B7 — a criterion that already holds on HEAD proves nothing about the plan.
  while IFS=$'\t' read -r ln blk; do
    [[ -n "${ln:-}" ]] || continue
    typ="$(tr '|' '\n' <<< "$blk" | grep -E '^type:' | head -1 | sed -E 's/^type:[[:space:]]*//; s/["'\'']//g')"
    case "$typ" in
      must_contain)
        f="$(tr '|' '\n' <<< "$blk" | grep -E '^file:' | head -1 | sed -E 's/^file:[[:space:]]*//; s/^"//; s/"$//')"
        rx="$(tr '|' '\n' <<< "$blk" | grep -E '^regex:' | head -1 | sed -E 's/^regex:[[:space:]]*//; s/^"//; s/"$//')"
        [[ -n "$f" && -n "$rx" ]] && _exists "$f" && grep -qE -- "$rx" "$(_abs "$f")" 2>/dev/null && _warn "B7" "$PLAN:$ln" "must_contain already holds on HEAD (\`${f}\` matches /${rx}/) — this criterion passes before any work"
        ;;
      cmd)
        c="$(tr '|' '\n' <<< "$blk" | grep -E '^cmd:' | head -1 | sed -E 's/^cmd:[[:space:]]*//; s/^"//; s/"$//')"
        ex="$(tr '|' '\n' <<< "$blk" | grep -E '^expected_exit:' | head -1 | sed -E 's/^expected_exit:[[:space:]]*//')"
        [[ -n "$c" && "$RUN_CMDS" == "1" ]] || continue
        ( cd "$ROOT" && timeout 20 bash -c "$c" >/dev/null 2>&1 ); rc=$?
        [[ "$rc" == "${ex:-0}" ]] && _warn "B7" "$PLAN:$ln" "cmd criterion already exits ${rc} on HEAD — it passes before any work: ${c}"
        ;;
    esac
  done <<< "$VP_BLOCKS"

  # B8 — a Create: path that already exists (ACTA: migration 0036 taken by another session).
  for i in "${!FB_LN[@]}"; do
    [[ "${FB_VERB[$i]}" == "Create" ]] || continue
    for p in ${FB_PATHS[$i]}; do _exists "$p" && _block "B8" "$PLAN:${FB_LN[$i]}" "Create: \`${p}\` already exists in the repository"; done
  done
  # B9 — a new test file whose basename already exists under a tests/ tree:
  # pytest without __init__.py packages refuses the whole collection (ACTA L3-B1).
  for p in $(for i in "${!FB_LN[@]}"; do [[ "${FB_VERB[$i]}" == "Create" || "${FB_VERB[$i]}" == "Test" ]] && printf '%s\n' ${FB_PATHS[$i]}; done | sort -u); do
    [[ "$p" =~ (^|/)tests?/ ]] || continue
    _exists "$p" && continue
    bn="${p##*/}"
    clash="$(grep -E "(^|/)tests?/.*/${bn//./\\.}$" <<< "$REPO_FILES" | grep -vxF -- "$p" | head -1)"
    [[ -n "$clash" ]] && _warn "B9" "$PLAN" "new test file \`${p}\` shares its basename with \`${clash}\` — pytest rejects duplicate test module names unless both directories are packages"
  done
  # B10 — a file the plan removes that other files still import or reference
  # (ACTA: db/env.py imported a model the plan deleted; four checks found it).
  for f in $(tr '|' '\n' <<< "$VP_BLOCKS" | grep -E '^file:' | sed -E 's/^file:[[:space:]]*//; s/["'"'"']//g' | sort -u); do
    _exists "$f" || continue
    stem="${f##*/}"; stem="${stem%.*}"
    [[ ${#stem} -ge 4 ]] || continue
    parent="$(basename "$(dirname "$f")")"
    case "$stem" in
      models|model|config|router|routers|service|services|index|utils|util|main|types|schema|schemas|api|app|health|test|tests|base|core|common|helpers)
        pat="\b${parent}[./]${stem}\b|from ${parent} import ${stem}\b" ;;
      *) pat="\b${stem}\b" ;;
    esac
    refs="$(grep -rIlE --exclude-dir=.git --exclude-dir=.aid-o --exclude-dir=node_modules --exclude-dir=.aid-worktrees --exclude-dir=.pytest_cache -- "$pat" "$ROOT" 2>/dev/null | grep -vF -- "$(_abs "$f")" | grep -vF -- "$PLAN" | sed "s#^${ROOT}/##" | grep -vxF -f <(printf '%s\n' "$ALL_FILES_PATHS") | grep -vE '^(docs/|CHANGELOG|CLAUDE\.md|\.pytest_cache)' | head -5 | tr '\n' ' ')"
    [[ -n "$refs" ]] && _warn "B10" "$PLAN" "\`${f}\` is to be removed but \`${stem}\` is still referenced by: ${refs}"
  done
else
  _warn "B" "$PLAN" "no repository content under '${ROOT:-<none>}' — the plan-vs-repository checks (A5, A7, B1-B10) did not run"
fi

# ---------------------------------------------------------------------------
# C. After a revision: the claims the revision added.
# ---------------------------------------------------------------------------
if [[ -n "$SNAPSHOT" ]]; then
  ADDED="$(diff --unchanged-line-format= --old-line-format= --new-line-format='%dn	%L' "$SNAPSHOT" "$PLAN")"
  REMOVED="$(diff --unchanged-line-format= --new-line-format= --old-line-format='%L' "$SNAPSHOT" "$PLAN")"
  FIX_STEPS="$(tr ',' '\n' <<< "$FIXES" | tr -d ' ' | grep -v '^$')"
  # C2 — new claims: paths and identifiers on added lines, checked again.
  added_ids=""
  while IFS=$'\t' read -r ln line; do
    [[ -n "${ln:-}" ]] || continue
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      _known_path "$p" && continue
      _block "C2" "$PLAN:$ln" "revision added \`${p}\`, which does not exist and no step creates"
    done < <(_aid_backtick_paths "$line")
    if [[ -n "$ROOT" ]]; then
      for t in $(grep -oE '`[A-Za-z_][A-Za-z0-9_]*(\(\)|\b)`|`[A-Z][A-Z0-9_]{3,}`' <<< "$line" | tr -d '`' | sed 's/()$//' | sort -u); do
        [[ "$t" =~ _ || "$t" =~ ^[A-Z0-9_]+$ ]] || continue
        _in_list "$t" "$added_ids" && continue; added_ids+="$t"$'\n'
        [[ -n "$(_grep_repo "$t")" ]] || REV_UNKNOWN_IDS+="$t"$'\n'
      done
    fi
  done <<< "$ADDED"
  # C3 — a token the revision removed that still stands elsewhere in the plan.
  for t in $(grep -oE '`[A-Za-z0-9_./:-]{5,80}`' <<< "$REMOVED" | grep -E '[_/.]' | sort -u); do
    tok="${t//\`/}"
    grep -qF -- "$t" <<< "$ADDED" && continue        # merely moved/rewritten, not retired
    grep -qF -- "$t" "$PLAN" || continue
    _warn "C3" "$PLAN" "revision removed a mention of \`${tok}\` but the plan still says it elsewhere ($(grep -nF -- "$t" "$PLAN" | head -1 | cut -d: -f1)) — stale twin?"
  done
  # C4 / C5 — which steps the revision touched, and whether it ADDED behaviour.
  declare -A TOUCHED=()
  while IFS=$'\t' read -r ln line; do
    [[ -n "${ln:-}" ]] || continue
    idx="$(_step_index_for_line "$ln")" || continue
    n="${STEP_N[$idx]}"; TOUCHED["$n"]=1
    if ! _in_list "$n" "$FIX_STEPS"; then
      if [[ "$line" =~ ^-\ \[\ \] ]]; then _block "C5" "$PLAN:$ln" "revision added an acceptance criterion to Step ${n}, which is not in the fix list (${FIXES}) — a design change, not a fix: cut it or bring it to the PM"
      elif [[ "$line" =~ ^-\ (Create|Modify|Rewrite|Test): ]]; then _block "C5" "$PLAN:$ln" "revision added a Files entry to Step ${n}, outside the fix list (${FIXES})"
      fi
    fi
  done <<< "$ADDED"
  new_steps="$(comm -13 <(_aid_blank_fenced < "$SNAPSHOT" | grep -oE '^### Step [0-9]+' | sort -u) <(printf '%s\n' "$BLANKED" | grep -oE '^### Step [0-9]+' | sort -u) | tr '\n' ';')"
  [[ -n "$new_steps" ]] && _block "C5" "$PLAN" "revision added step(s): ${new_steps} — a fix does not add steps; split or bring it to the PM"
  for n in "${!TOUCHED[@]}"; do _in_list "$n" "$FIX_STEPS" || _warn "C4" "$PLAN" "revision touched Step ${n}, which is not in the fix list (${FIXES})"; done
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
SHA="$(sha256sum "$PLAN" | cut -d' ' -f1)"
if [[ $QUIET -eq 0 ]]; then
  for f in "${BLOCKS[@]}"; do IFS=$'\t' read -r id loc msg <<< "$f"; echo "BLOCK ${id} ${loc}: ${msg}" >&2; done
  for f in "${LEGACY[@]}"; do IFS=$'\t' read -r id loc msg <<< "$f"; echo "[WARN legacy] ${id} ${loc}: ${msg} (would BLOCK a lifecycle_strict plan)" >&2; done
  for f in "${WARNS[@]}";  do IFS=$'\t' read -r id loc msg <<< "$f"; echo "WARN  ${id} ${loc}: ${msg}" >&2; done
  n_unknown="$(printf '%s\n' "${UNKNOWN_IDS:-}" | grep -c . || true)"
  echo "aid-plan-check [${MODE}]: ${#BLOCKS[@]} blocking, ${#LEGACY[@]} legacy advisory, ${#WARNS[@]} warning(s), ${n_unknown} identifier(s) unknown to the repository (list in --json); lint rc=${LINT_RC}; steps=${NSTEPS}; sha256=${SHA:0:12}" >&2
fi
if [[ -n "$JSON_OUT" ]]; then
  mkdir -p "$(dirname "$JSON_OUT")" || { echo "aid-plan-check: cannot create $(dirname "$JSON_OUT")" >&2; exit 2; }
  _rows() { for f in "$@"; do IFS=$'\t' read -r id loc msg <<< "$f"; jq -cn --arg id "$id" --arg loc "$loc" --arg msg "$msg" '{id:$id,location:$loc,message:$msg}'; done | jq -s '.'; }
  jq -n --arg plan "$PLAN" --arg sha "$SHA" --arg root "$ROOT" --argjson lint "$LINT_RC" --argjson steps "$NSTEPS" \
     --argjson blocks "$(_rows "${BLOCKS[@]}")" --argjson warns "$(_rows "${WARNS[@]}")" --argjson legacy "$(_rows "${LEGACY[@]}")" --arg mode "$MODE" \
     --argjson unknown "$(printf '%s\n' "${UNKNOWN_IDS:-}" | grep -v '^$' | jq -R . | jq -s .)" \
     --argjson revunknown "$(printf '%s\n' "${REV_UNKNOWN_IDS:-}" | grep -v '^$' | sort -u | jq -R . | jq -s .)" \
     '{plan:$plan, plan_sha256:$sha, project_root:$root, mode:$mode, lint_rc:$lint, steps:$steps, blocking:$blocks, legacy_advisory:$legacy, warnings:$warns, unknown_identifiers:$unknown, revision_unknown_identifiers:$revunknown, pass:($blocks|length==0), checked_at:(now|todate)}' > "$JSON_OUT"
fi
(( ${#BLOCKS[@]} == 0 )) && exit 0 || exit 1
