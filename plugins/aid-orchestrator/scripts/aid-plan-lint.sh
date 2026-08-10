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
# Usage: aid-plan-lint.sh <plan.md> [--strict|--legacy] [--quiet]
# Exit:  0 = no blocking violations   1 = blocking violation(s)   2 = usage/IO
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-scoping.sh
source "${SCRIPT_DIR}/lib/aid-scoping.sh"

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
  local bullet="${1#- }" body prose declared tok
  body="$(printf '%s' "$bullet" | sed -E 's/^(Create|Modify|Test|Rewrite):[[:space:]]*//')"
  # Nothing after the em dash (or "--") means no description to mine.
  case "$body" in
    *$'\xe2\x80\x94'*) prose="${body#*$'\xe2\x80\x94'}" ;;
    *--*)              prose="${body#*--}" ;;
    *)                 return 0 ;;
  esac
  declared="$(_aid_split_path_entry "$body" 2>/dev/null)" || declared=""
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    # A real repo file, deliberately narrow: at least one directory segment and
    # a file extension, no placeholder brackets, no trailing slash. Directories
    # (`<evidence_dir>/jobs/`),command fragments and prose punctuation are not
    # scope declarations and must not generate noise.
    [[ "$tok" =~ ^[A-Za-z0-9._/-]+/[A-Za-z0-9._-]+\.[A-Za-z0-9]+$ ]] || continue
    _aid_path_shape_ok "$tok" || continue
    grep -qxF "$tok" <<<"$declared" && continue        # already in scope
    printf '%s\n' "$tok"
  done < <(printf '%s\n' "$prose" | grep -oP '(?<=`)[^`]+(?=`)' 2>/dev/null || true)
}

# Reason -> human message.
_reason_msg() {
  case "$1" in
    no-path)            echo "no usable path (prose-only, or verb+path split across two lines — the path is silently dropped)";;
    bad-shape)          echo "path has whitespace/() — a verb, bold wrapper, leading '(', or two-paths-without-'+' leaked in";;
    no-backtick-path)   echo "path is not \`backtick\`-wrapped";;
    non-line-paren)     echo "a parenthetical before '—' is not a (lines ~N-M) range — move the note after '—'";;
    ambiguous-entry)    echo "unparsed text after a path — use \`a\` + \`b\` for multiple paths and put prose after '—'";;
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

# Blocking = any ERROR (both modes), or any STRICT on a strict-cohort plan.
blocking=$errors
[[ "$mode" == "strict" ]] && blocking=$((blocking + strict_hits))

if [[ "$QUIET" -eq 0 ]]; then
  if [[ "$blocking" -gt 0 ]]; then
    echo "aid-plan-lint: FAIL (${errors} error(s)$( [[ "$mode" == "strict" ]] && echo ", ${strict_hits} strict violation(s)" )) — fix the Files entries above. Canonical form: '- <Create|Modify|Test|Rewrite>: \`path\` [ + \`path\`]* [(lines ~N-M)] [— prose]'." >&2
  elif [[ "$strict_hits" -gt 0 ]]; then
    echo "aid-plan-lint: PASS with ${strict_hits} legacy advisory warning(s) (non-blocking for this legacy plan; would block a lifecycle_strict plan)." >&2
  else
    echo "aid-plan-lint: PASS — all Files entries are canonical." >&2
  fi
  [[ "$advisories" -gt 0 ]] && echo "aid-plan-lint: ${advisories} description-only path advisory/-ies (never blocking — declare them as their own bullets if the step edits them)." >&2
fi

[[ "$blocking" -gt 0 ]] && exit 1
exit 0
