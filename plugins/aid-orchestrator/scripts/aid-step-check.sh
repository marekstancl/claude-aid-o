#!/usr/bin/env bash
# =============================================================================
# aid-step-check.sh — everything about a change that needs no model, before a
# reviewer sees it (P094 Step 3).
#
#   aid-step-check.sh --checkpoint cp2|cp3|cp6 --evidence-dir <run dir>
#                     [--step N] [--state-file <fsm-state.yaml>] [--plan-json <plan.json>]
#                     [--worktree] [--dod-file <path>] [--project-root <dir>]
#
# Computes, for the diff of one step (cp2), one EPIC (cp3) or the working tree
# (cp6): the range and where it came from; every changed file classified
# against the step's declared scope (outputs, allowed_paths, forbidden_paths);
# the security patterns of defaults/pre-filter-rules.yaml matched in added
# lines; added and changed test files with their tier tag; size; the handler
# patterns that make a behaviour trace mandatory; and a verdict:
#
#   no_change        the range has no changes
#   skip             small, clean, inside scope (or a streamlined run)
#   review           a reviewer must look
#   review+security  a reviewer and the security role must look
#
# Writes <cp dir>/step-check.json (atomically, with its own sha256), logs a
# `step_check` event into the run's timeline that binds the verdict to HEAD
# and to the file's sha256, and on skip/no_change writes <cp dir>/rounds.json
# — the only writer of that index in those cases. It refuses to overwrite an
# index that already records a closed round: a re-run can never turn a
# recorded `fail` into a skip.
#
# <cp dir> is <run dir>/cp2/step-<N>, <run dir>/cp3 or <run dir>/cp6.
#
# Exit: 0 written; 1 refused (named); 2 tooling (jq/yq/git/rules missing);
#       22 range_undetermined (cp2 without a step_commit or base_commit,
#       cp3 without a base_commit).
#
# Successor of the retired pre-filter classify (P060 range rule kept; the
# verifier-output seed is gone) and of the trivial-skip rule of
# review-checkpoints.yaml. Tested by scripts/tests/bats/test-step-check.bats.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULES_FILE="${AID_PREFILTER_RULES:-$PLUGIN_DIR/defaults/pre-filter-rules.yaml}"
# shellcheck source=lib/aid-stage-log.sh
source "$SCRIPT_DIR/lib/aid-stage-log.sh"
# shellcheck source=lib/aid-ancillary.sh
source "$SCRIPT_DIR/lib/aid-ancillary.sh"
# shellcheck source=lib/aid-test-tier.sh
source "$SCRIPT_DIR/lib/aid-test-tier.sh"

die() { echo "step-check: $*" >&2; exit "${2:-1}"; }
usage() { sed -n '5,9p' "${BASH_SOURCE[0]}" | sed 's/^# *//'; }

CHECKPOINT="" EVID="" STEP="" STATE="" PLAN_JSON="" WORKTREE=0 DOD_FILE="" ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --checkpoint) CHECKPOINT="$2"; shift 2 ;;
    --evidence-dir) EVID="$2"; shift 2 ;;
    --step) STEP="$2"; shift 2 ;;
    --state-file) STATE="$2"; shift 2 ;;
    --plan-json) PLAN_JSON="$2"; shift 2 ;;
    --worktree) WORKTREE=1; shift ;;
    --dod-file) DOD_FILE="$2"; shift 2 ;;
    --project-root) ROOT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option $1 (see --help)" 2 ;;
  esac
done

for t in jq yq git sha256sum; do command -v "$t" >/dev/null 2>&1 || die "$t not installed" 2; done
[[ "$CHECKPOINT" =~ ^cp[236]$ ]] || die "--checkpoint must be cp2, cp3 or cp6" 2
[[ -n "$EVID" ]] || die "--evidence-dir is required" 2
[[ -f "$RULES_FILE" ]] || die "rules file not found: $RULES_FILE" 2
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$ROOT" && -d "$ROOT/.git" || -f "$ROOT/.git" ]] || die "not inside a git repository (or --project-root is not one)" 2
STATE="${STATE:-$EVID/fsm-state.yaml}"
PLAN_JSON="${PLAN_JSON:-$EVID/plan.json}"
TIMELINE="$EVID/timeline.jsonl"
case "$CHECKPOINT" in
  cp2) [[ "$STEP" =~ ^[0-9]+$ ]] || die "--step N is required for cp2" 2; CPDIR="$EVID/cp2/step-$STEP" ;;
  cp3) CPDIR="$EVID/cp3" ;;
  cp6) CPDIR="$EVID/cp6"; WORKTREE=1 ;;
esac
[[ -z "$DOD_FILE" || -f "$DOD_FILE" ]] || die "--dod-file not found: $DOD_FILE"

git_() { git -C "$ROOT" "$@"; }
HEAD_SHA="$(git_ rev-parse HEAD)"

# ── 1. range ────────────────────────────────────────────────────────────────
range_base="" range_source=""
if (( WORKTREE )); then
  range_source=worktree
elif [[ "$CHECKPOINT" == cp2 ]]; then
  # P060 rule: the step boundary, never HEAD~1. The last step_commit event of
  # the previous step, else the run's base_commit, else refuse.
  if [[ -f "$TIMELINE" && "$STEP" -gt 0 ]]; then
    range_base="$(jq -r --argjson s "$((STEP - 1))" 'select(.event == "step_commit" and ((.step_n | tonumber?) == $s)) | .commit_sha' "$TIMELINE" 2>/dev/null | tail -n1 || true)"
    [[ -n "$range_base" && "$range_base" != null ]] && range_source=step_commit
  fi
  if [[ -z "$range_source" && -f "$STATE" ]]; then
    range_base="$(yq -r '.base_commit // ""' "$STATE" 2>/dev/null || true)"
    [[ -n "$range_base" && "$range_base" != null ]] && range_source=base_commit
  fi
else
  [[ -f "$STATE" ]] && range_base="$(yq -r '.base_commit // ""' "$STATE" 2>/dev/null || true)"
  [[ -n "$range_base" && "$range_base" != null ]] && range_source=base_commit
fi
if [[ -z "$range_source" ]]; then
  log_event "$TIMELINE" "step_check_range_undetermined" checkpoint="$CHECKPOINT" step="${STEP:-null}" head_sha="$HEAD_SHA"
  echo "range_undetermined: $CHECKPOINT${STEP:+ step $STEP} has no step_commit event in timeline.jsonl and no base_commit in $(basename "$STATE"); the FSM emits step_commit at every increment-step and base_commit at init. Never hand-write step-check.json." >&2
  exit 22
fi
if (( WORKTREE )); then
  RANGE="worktree"
  mapfile -t FILES < <({ git_ diff --name-only HEAD; git_ ls-files --others --exclude-standard; } | sort -u)
  DIFF="$(git_ diff HEAD; for f in $(git_ ls-files --others --exclude-standard); do git_ diff --no-index /dev/null "$f" || true; done)"
  NUMSTAT="$(git_ diff --numstat HEAD)"
else
  git_ cat-file -e "${range_base}^{commit}" 2>/dev/null || die "range base $range_base does not resolve"
  git_ merge-base --is-ancestor "$range_base" "$HEAD_SHA" 2>/dev/null || die "range base $range_base is not an ancestor of HEAD; the diff would show foreign changes"
  RANGE="${range_base}..${HEAD_SHA}"
  mapfile -t FILES < <(git_ diff --name-only "$RANGE")
  DIFF="$(git_ diff "$RANGE")"
  NUMSTAT="$(git_ diff --numstat "$RANGE")"
fi
LINES="$(awk '{a+=$1+$2} END{print a+0}' <<<"$NUMSTAT")"

# ── 2. scope: the step's declared paths ─────────────────────────────────────
# outputs are plan bullets ("Modify: `path` (lines ~N-M) — text"); the path is
# what is between backticks. allowed_paths and forbidden_paths are globs or
# prose; an entry with no slash, dot or backtick is prose and is recorded, not
# matched.
_paths_of() { jq -r "$1" "$PLAN_JSON" 2>/dev/null | grep -oE '`[^`]+`' | tr -d '`' | grep -vE '^\s*$' || true; }
_globs_of() {
  jq -r "$1" "$PLAN_JSON" 2>/dev/null | while IFS= read -r e; do
    [[ -n "$e" ]] || continue
    if [[ "$e" == *'`'* ]]; then grep -oE '`[^`]+`' <<<"$e" | tr -d '`'
    elif [[ "$e" =~ [/.] && ! "$e" =~ [[:space:]] ]]; then printf '%s\n' "$e"; fi
  done
}
SCOPE_GLOBS=() FORBIDDEN_GLOBS=() SCOPE_DECLARED=1
if [[ "$CHECKPOINT" == cp6 ]]; then
  SCOPE_DECLARED=0
else
  [[ -f "$PLAN_JSON" ]] || die "plan.json not found: $PLAN_JSON"
  if [[ "$CHECKPOINT" == cp2 ]]; then sel=".steps[$STEP]"; else sel=".steps[]"; fi
  jq -e "$sel" "$PLAN_JSON" >/dev/null 2>&1 || die "no step $STEP in $PLAN_JSON"
  mapfile -t SCOPE_GLOBS < <({ _paths_of "$sel.outputs[]?"; _globs_of "$sel.allowed_paths[]?"; } | sort -u)
  mapfile -t FORBIDDEN_GLOBS < <(_globs_of "$sel.forbidden_paths[]?" | sort -u)
fi
in_scope=() outside=() forbidden=()
for f in "${FILES[@]}"; do
  [[ -n "$f" ]] || continue
  hit=0
  for g in "${FORBIDDEN_GLOBS[@]}"; do _aid_ancillary_glob_match "$f" "$g" && { forbidden+=("$f"); hit=1; break; }; done
  (( hit )) && continue
  if (( ! SCOPE_DECLARED )); then in_scope+=("$f"); continue; fi
  for g in "${SCOPE_GLOBS[@]}"; do _aid_ancillary_glob_match "$f" "$g" && { in_scope+=("$f"); hit=1; break; }; done
  (( hit )) || outside+=("$f")
done

# ── 3. security and handler patterns over ADDED lines ───────────────────────
# The rules are written for grep -E (they use \s); bash's =~ is POSIX and would
# read \s as a literal s, so a rule with a space in it never matched. Matched
# case-insensitively: a secret is as much a secret as AWS_SECRET_ACCESS_KEY as
# it is as api_key (both found by the testbed's sabotaged diff, P094 Step 12).
ADDED="$(grep -E '^\+' <<<"$DIFF" | grep -vE '^\+\+\+ ' | cut -c2- || true)"
_matches() { [[ -n "$ADDED" ]] && grep -qiE -- "$1" <<<"$ADDED"; }
matched_rules=() matched_lines=()
while IFS=$'\t' read -r id pattern; do
  [[ -n "$id" && "$id" =~ ^[a-z][a-z0-9_]*$ ]] || continue
  if _matches "$pattern"; then
    matched_rules+=("$id")
    while IFS= read -r l; do matched_lines+=("$id: ${l:0:200}"); (( ${#matched_lines[@]} >= 20 )) && break; done < <(grep -iE -- "$pattern" <<<"$ADDED")
  fi
done < <(yq -r '.fail_rules[] | [.id, .pattern] | join("\t")' "$RULES_FILE")   # not @tsv: it escapes the backslashes of \s
handler_ids=()
while IFS=$'\t' read -r id pattern; do
  [[ -n "$id" ]] || continue
  _matches "$pattern" && handler_ids+=("$id")
done < <(yq -r '.handler_patterns[]? | [.id, .pattern] | join("\t")' "$RULES_FILE")

# ── 4. tests and their tiers ────────────────────────────────────────────────
_is_test() { [[ "$1" =~ (^|/)tests?/ || "$1" =~ (^|/)test[-_][^/]*$ || "$1" =~ \.(test|spec)\.[a-z]+$ || "$1" =~ _test\.[a-z]+$ || "$1" =~ \.bats$ ]]; }
tests_added=() tests_changed=()
while IFS=$'\t' read -r a d f; do
  [[ -n "$f" ]] && _is_test "$f" || continue
  tier="missing"
  if [[ -f "$ROOT/$f" ]]; then tier="$(aid_test_tier_of "$ROOT/$f" 2>/dev/null || echo missing)"; fi
  entry="$(jq -nc --arg p "$f" --arg t "$tier" '{path: $p, tier: $t}')"
  if (( WORKTREE )) || [[ "$(git_ diff --diff-filter=A --name-only "$RANGE" -- "$f" 2>/dev/null)" == "$f" ]]; then tests_added+=("$entry"); else tests_changed+=("$entry"); fi
done <<<"$NUMSTAT"

# ── 5. verdict ──────────────────────────────────────────────────────────────
_cfg() {  # <yq path> <default>: the project's review-checkpoints.yaml first, then the plugin default
  local v="" f
  for f in "$ROOT/.aid-o/config/policies/review-checkpoints.yaml" "$PLUGIN_DIR/defaults/policies/review-checkpoints.yaml"; do
    [[ -f "$f" ]] || continue
    v="$(yq -r "$1 // \"\"" "$f" 2>/dev/null || true)"; [[ -n "$v" && "$v" != null ]] && break; v=""
  done
  printf '%s' "${v:-$2}"
}
MAX_FILES="$(_cfg '.review_checkpoints.step_review.skip_threshold.max_files' 1)"
MAX_LINES="$(_cfg '.review_checkpoints.step_review.skip_threshold.max_lines' 50)"
STREAMLINED=false
[[ -f "$STATE" ]] && STREAMLINED="$(yq -r '.streamlined_mode // false' "$STATE" 2>/dev/null || echo false)"

verdict="" reason=""
if (( ${#FILES[@]} == 0 )); then verdict=no_change; reason="the range $RANGE has no changes"
elif [[ "$STREAMLINED" == true ]]; then verdict=skip; reason="streamlined"
elif (( ${#forbidden[@]} > 0 )); then verdict=review; reason="forbidden path touched: ${forbidden[*]}"
elif (( ${#matched_rules[@]} > 0 )); then verdict="review+security"; reason="security pattern: ${matched_rules[*]}"
elif (( ${#outside[@]} > 0 )); then verdict=review; reason="files outside the step's scope: ${outside[*]}"
elif (( ${#FILES[@]} <= MAX_FILES && LINES <= MAX_LINES )); then verdict=skip; reason="${#FILES[@]} file(s), $LINES line(s), inside scope, no pattern matched"
else verdict=review; reason="${#FILES[@]} file(s), $LINES line(s)"
fi

# ── 6. write, bind, index ───────────────────────────────────────────────────
[[ "$(git_ rev-parse HEAD)" == "$HEAD_SHA" ]] || die "HEAD moved while the check ran; run it again"
mkdir -p "$CPDIR"
_arr() { printf '%s\n' "$@" | jq -R . | jq -s 'map(select(length > 0))'; }
_jarr() { if (( $# )); then printf '%s\n' "$@" | jq -s .; else echo '[]'; fi; }
script_findings='[]'
if (( ${#forbidden[@]} > 0 )); then
  script_findings="$(for f in "${forbidden[@]}"; do jq -nc --arg f "$f" --arg cp "$CHECKPOINT" \
    '{id: "step_check-forbidden", checkpoint: $cp, severity: "blocker", role: "step_check",
      claim: ("the diff touches a forbidden path: " + $f), evidence: ($f + ":0"), command: ("git diff --name-only -- " + $f), fix: "revert the change to this path or amend the step scope"}'; done | jq -s .)"
fi
dod_json='null'; [[ -n "$DOD_FILE" ]] && dod_json="$(jq -Rs . "$DOD_FILE")"
tmp="$(mktemp "$CPDIR/.step-check.XXXXXX")"
jq -n --arg cp "$CHECKPOINT" --argjson step "${STEP:-null}" --arg head "$HEAD_SHA" --arg range "$RANGE" --arg src "$range_source" \
  --argjson in "$(_arr "${in_scope[@]}")" --argjson out "$(_arr "${outside[@]}")" --argjson forb "$(_arr "${forbidden[@]}")" \
  --argjson scope_declared "$SCOPE_DECLARED" \
  --argjson rules "$(_arr "${matched_rules[@]}")" --argjson rlines "$(_arr "${matched_lines[@]}")" \
  --argjson tadded "$(_jarr "${tests_added[@]}")" --argjson tchanged "$(_jarr "${tests_changed[@]}")" \
  --argjson nfiles "${#FILES[@]}" --argjson nlines "$LINES" --argjson handlers "$(_arr "${handler_ids[@]}")" \
  --arg verdict "$verdict" --arg reason "$reason" --argjson sf "$script_findings" --argjson dod "$dod_json" \
  --arg streamlined "$STREAMLINED" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  {checkpoint: $cp, step: $step, head_sha: $head, range: $range, range_source: $src,
   files: {in_scope: $in, outside_files: $out, forbidden_touched: $forb, scope_declared: ($scope_declared == 1)},
   security: {matched_rules: $rules, lines: $rlines},
   tests: {added: $tadded, changed: $tchanged},
   size: {files: $nfiles, lines: $nlines}, handler_patterns: $handlers,
   streamlined: ($streamlined == "true"), script_findings: $sf, dod: $dod,
   verdict: $verdict, reason: $reason, generated_at: $now}' > "$tmp"
sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
jq --arg s "$sha" '. + {sha256: $s}' "$tmp" > "$tmp.2" && mv -f "$tmp.2" "$CPDIR/step-check.json" && rm -f "$tmp"
log_event "$TIMELINE" "step_check" checkpoint="$CHECKPOINT" step="${STEP:-null}" head_sha="$HEAD_SHA" verdict="$verdict" sha256="$sha"

if [[ "$verdict" == skip || "$verdict" == no_change ]]; then
  idx="$CPDIR/rounds.json"
  if [[ -f "$idx" ]]; then
    recorded="$(jq -r '((.rounds // []) | length), (.verdict // "")' "$idx" 2>/dev/null | paste -sd' ')"
    n="${recorded%% *}"; v="${recorded#* }"
    if [[ "${n:-0}" -gt 0 || "$v" == pass || "$v" == fail ]]; then
      die "$idx already records a closed round (verdict ${v:-none}, ${n:-0} round(s)); a re-run cannot replace it with a $verdict"
    fi
  fi
  jq -n --arg v "$verdict" --arg r "$reason" --arg h "$HEAD_SHA" '{verdict: $v, reason: $r, head_sha: $h, rounds: []}' > "$idx"
fi
printf 'verdict: %s (%s)\n' "$verdict" "$reason"
