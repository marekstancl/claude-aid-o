#!/usr/bin/env bash
# =============================================================================
# aid-gate-profile.sh — Shared gate-profile risk-classification resolver
# (P061 EPIC 2/6, plan Step 7 / plan.json step_1_backend)
#
# WHY: aid-run-gates.sh --profile <name> (P061 EPIC 1) can already RUN a named
# gate subset, but nothing yet CHOOSES that name automatically. This file is
# the one shared resolver both callers will use:
#   - aid-fsm.sh          (this EPIC's Step 2 / "Step 8" — full /aid-run
#                          context, fsm-state.yaml always present)
#   - a future EPIC 5 /aid-do wiring (NO fsm-state.yaml at all — Fast Mode
#                          bypasses the FSM entirely)
# Two independent CP1-deep review passes on EPIC 1 flagged the "no
# fsm-state.yaml" input-contract gap explicitly — this file closes it, not
# leaves it implicit (see "NO-FSM-STATE CONTRACT" below).
#
# ── PUBLIC API (sourceable) ─────────────────────────────────────────────────
#   gate_profile_rank <name>
#       Echoes the integer rank of a known profile name; returns 1 (no
#       stdout) if <name> is not one of the 5 known profiles.
#   gate_profile_max <a> <b>
#       Echoes whichever of <a>/<b> has the higher-or-equal rank (ties go to
#       <a>). Returns 1 if either name is unknown — THE single place
#       CHECKPOINT 2 (this EPIC's next step) compares "active >= required".
#   gate_profile_is_high_risk_path <path>
#   gate_profile_is_docs_path <path>
#       Path predicates backing the classification rules below.
#   gate_profile_classify_paths [path ...]
#       Base classification (quick|standard|full) from changed paths alone —
#       no fsm-state, no review-profile, no override. See "CLASSIFICATION
#       RULES" below.
#   gate_profile_review_floor <review_profile_json_path>
#       Echoes the profile floor implied by review-profile.json's
#       `.review_profile.risk_profile`, or "" if the file is absent (not
#       "if present" → nothing to apply). NEVER echoes empty for a file that
#       DOES exist and fails to parse — that fails closed to "full" instead
#       (see "REVIEW-PROFILE FLOOR" below).
#   gate_profile_resolve <changed_paths_file|-> [<fsm_state_file>] [<review_profile_json>]
#       The full resolver. Prints exactly one profile name to stdout. Never
#       fails (always exit 0) — every input is optional/guardable by design.
#       Honors AID_GATE_PROFILE_OVERRIDE / AID_GATE_PROFILE_FORCE /
#       AID_GATE_PROFILE_FORCE_REASON (see "MANUAL OVERRIDE" below).
#
# ── PROFILE ORDERING (the named hierarchy CHECKPOINT 2 needs) ───────────────
#   quick=0 < targeted=1 < standard=2 < full=3 < release=4
# This table lives ONLY in _AID_GATE_PROFILE_RANK below — gate_profile_rank /
# gate_profile_max are the sole accessors. No other file should hardcode a
# competing ordering.
#
# ── CLASSIFICATION RULES (gate_profile_classify_paths) ──────────────────────
#   1. ANY changed path matches a high-risk pattern → "full" (short-circuits;
#      one high-risk file is enough, regardless of what else changed).
#      High-risk patterns (mirrors this EPIC's plan "Risk Upgrade Rules"):
#        */aid-fsm.sh, */aid-run-gates.sh, */aid-release-policy.sh,
#        */aid-evidence-verify.sh, */defaults/schemas/*, */defaults/policies/*,
#        */agents/*.md
#   2. Else, if the changed-path set is empty OR every path matches the docs
#      allowlist (mirrors defaults/policies/review-profiles.yaml's
#      docs_allowlist: docs/**, README.md, CHANGELOG.md, the plugin's own
#      README/CHANGELOG) → "quick".
#   3. Else → "standard".
#   DESIGN CHOICE — why "standard" and not "targeted" for the ordinary case:
#   "targeted" is reserved for two narrower producers instead: (a) the
#   review-profile floor below (a verified-low-risk EPIC maps to
#   "targeted", giving the rank real meaning), and (b) a future per-STEP
#   (not per-EPIC-diff) caller such as EPIC 5's /aid-do, which can pass a
#   single small changed-file set through this same function and — if ever
#   needed — a `scope` parameter without breaking this contract. Defaulting
#   the plain "changed real code, nothing special" case straight to
#   "standard" keeps EPIC-level (aid-fsm.sh) classification conservative by
#   default, matching this plan step's explicit goal of NOT weakening
#   defaults yet (that is EPIC 4, deliberately much later).
#
# ── RELEASE BOUNDARY ─────────────────────────────────────────────────────────
# If (and only if) an fsm_state_file is given AND exists AND its `done_phase`
# field reads "release", the resolved profile is raised (via gate_profile_max,
# never a separate branch) to at least "release". `plan.json` today has no
# epic-index/total-epics field, so a "this is the LAST EPIC of the plan"
# signal is NOT available — per the plan's explicit instruction, v1 does NOT
# invent one. It relies on this done_phase=release signal plus the high-risk
# path upgrade above instead.
#
# ── NO-FSM-STATE CONTRACT (the gap both CP1 review passes flagged) ─────────
# fsm_state_file is OPTIONAL. Missing arg, empty arg, or a path that doesn't
# exist on disk are all treated identically: the release-boundary check above
# is simply skipped (fixed, documented fallback = "step-level, non-final
# phase") — never a crash, never undefined behavior. This is the exact shape
# a future EPIC 5 /aid-do call has: no fsm-state.yaml exists at all in Fast
# Mode, so it can call gate_profile_resolve with only its changed-paths file
# and get a well-defined "full" or "standard"/"quick" answer.
#
# ── REVIEW-PROFILE FLOOR (tighten-only) ─────────────────────────────────────
# review-profile.json (produced in the DONE review sub-phase, C3 activation —
# see pipeline.md §"Produce review-profile.json") carries a DIFFERENT risk
# taxonomy (`.review_profile.risk_profile`: docs_trivial|low|medium|high|
# unverifiable — defaults/policies/review-profiles.yaml). This resolver maps
# that onto its OWN 5-value ordering as a FLOOR, combined via gate_profile_max
# (never an independent branch, never able to lower the path-derived result):
#   docs_trivial → quick   |   low → targeted   |   medium → standard
#   high → full             |   unverifiable OR unparseable/missing field
#                              OR the file itself unreadable → full
#                              (fails CLOSED — a review-profile.json that
#                              exists but can't be trusted must never
#                              silently apply no floor at all)
# If review_profile_json is not given, or the path doesn't exist, the floor
# is "" (not applicable) — this is the ONLY case nothing is tightened, matching
# "review-profile.json (POKUD existuje)".
#
# ── MANUAL OVERRIDE ──────────────────────────────────────────────────────────
#   AID_GATE_PROFILE_OVERRIDE=<name>  — requested profile.
#   AID_GATE_PROFILE_FORCE=1          — waiver marker (with reason, below).
#   AID_GATE_PROFILE_FORCE_REASON=<reason, >=20 chars> — mirrors aid-fsm.sh's
#     existing `--force --reason '<>=20 chars>'` convention used everywhere
#     else in this plugin (see aid-fsm.sh die() messages) — one convention,
#     not a competing one.
#   Rules:
#     - Unknown/unset override name → ignored (warning to stderr), no effect.
#     - Upward or equal-rank override (requested rank >= computed rank) →
#       ALWAYS applied. A PM asking for MORE gates never needs a waiver.
#     - Downward override (requested rank < computed rank) while the computed
#       profile sits at the high-risk tier (full or release) → REQUIRES both
#       AID_GATE_PROFILE_FORCE=1 and a >=20-char AID_GATE_PROFILE_FORCE_REASON.
#       Without both, the override is REJECTED (computed profile kept, warning
#       to stderr) — never silently applied.
#     - Downward override while computed is BELOW the high-risk tier (e.g.
#       standard -> targeted) is allowed without a waiver — the AC only
#       requires waiver-gating for the high-risk case; broader waiver
#       coverage for every downward step is a candidate hardening left as an
#       improvement_note, not invented here.
#
# ── USAGE ────────────────────────────────────────────────────────────────────
#   Sourced:
#     source .../lib/aid-gate-profile.sh
#     profile=$(gate_profile_resolve "$changed_paths_file" "$fsm_state" "$review_profile_json")
#   Standalone:
#     bash aid-gate-profile.sh resolve <changed_paths_file|-> [<fsm_state_file>] [<review_profile_json>]
#     bash aid-gate-profile.sh rank <name>
#     bash aid-gate-profile.sh max <a> <b>
#     bash aid-gate-profile.sh classify-paths <changed_paths_file|->
#
# Callable standalone AND sourceable (sibling idiom: aid-cache-preflight.sh /
# aid-stage-log.sh). No top-level `set -e` (would leak into sourcing shells —
# aid-fsm.sh sources this under its OWN `set -euo pipefail`, so every helper
# here is written to never fail as a bare `var=$(...)` assignment; the only
# functions that can return 1 — gate_profile_rank / gate_profile_max — are
# only ever called from inside an `if` in this file, which is `set -e`-safe).
# =============================================================================

# ─── Profile ordering table (single source of truth) ───────────────────────
declare -gA _AID_GATE_PROFILE_RANK=(
  [quick]=0
  [targeted]=1
  [standard]=2
  [full]=3
  [release]=4
)

# gate_profile_rank <name> — echo integer rank; return 1 (no stdout) if unknown.
gate_profile_rank() {
  local name="${1:-}"
  if [[ -z "${_AID_GATE_PROFILE_RANK[$name]+set}" ]]; then
    return 1
  fi
  echo "${_AID_GATE_PROFILE_RANK[$name]}"
  return 0
}

# gate_profile_max <a> <b> — echo the higher-ranked of the two (ties → <a>).
# Returns 1 + stderr message if either name is unknown.
gate_profile_max() {
  local a="${1:-}" b="${2:-}" ra rb
  if ! ra="$(gate_profile_rank "$a")"; then
    echo "ERROR: aid-gate-profile.sh: gate_profile_max: unknown profile '${a}'" >&2
    return 1
  fi
  if ! rb="$(gate_profile_rank "$b")"; then
    echo "ERROR: aid-gate-profile.sh: gate_profile_max: unknown profile '${b}'" >&2
    return 1
  fi
  if (( ra >= rb )); then
    echo "$a"
  else
    echo "$b"
  fi
  return 0
}

# ─── Path predicates ────────────────────────────────────────────────────────

# gate_profile_is_high_risk_path <path> — see header "CLASSIFICATION RULES".
gate_profile_is_high_risk_path() {
  local p="${1:-}"
  case "$p" in
    aid-fsm.sh|*/aid-fsm.sh) return 0 ;;
    aid-run-gates.sh|*/aid-run-gates.sh) return 0 ;;
    aid-release-policy.sh|*/aid-release-policy.sh) return 0 ;;
    aid-evidence-verify.sh|*/aid-evidence-verify.sh) return 0 ;;
    defaults/schemas/*|*/defaults/schemas/*) return 0 ;;
    defaults/policies/*|*/defaults/policies/*) return 0 ;;
    agents/*.md|*/agents/*.md) return 0 ;;
  esac
  return 1
}

# gate_profile_is_docs_path <path> — mirrors review-profiles.yaml docs_allowlist.
gate_profile_is_docs_path() {
  local p="${1:-}"
  case "$p" in
    docs/*|*/docs/*) return 0 ;;
    README.md|*/README.md) return 0 ;;
    CHANGELOG.md|*/CHANGELOG.md) return 0 ;;
    plugins/aid-orchestrator/README.md) return 0 ;;
    plugins/aid-orchestrator/CHANGELOG.md) return 0 ;;
  esac
  return 1
}

# gate_profile_classify_paths [path ...] — base classification, no fsm-state /
# review-profile / override layers. Always echoes one of quick|standard|full,
# always returns 0 (empty input → "quick", documented — nothing changed is the
# safest, least-surprising default, distinct from the no-fsm-state fallback).
gate_profile_classify_paths() {
  local p any_high=false any_nondocs=false n=0
  for p in "$@"; do
    [[ -z "$p" ]] && continue
    n=$((n + 1))
    if gate_profile_is_high_risk_path "$p"; then
      any_high=true
    fi
    if ! gate_profile_is_docs_path "$p"; then
      any_nondocs=true
    fi
  done
  if $any_high; then
    echo full
  elif (( n == 0 )); then
    echo quick
  elif $any_nondocs; then
    echo standard
  else
    echo quick
  fi
  return 0
}

# ─── review-profile.json floor ──────────────────────────────────────────────

# gate_profile_review_floor <review_profile_json_path>
# Echoes "" if the path is empty or the file doesn't exist (nothing to apply).
# Otherwise ALWAYS echoes a known profile name — fails CLOSED to "full" on any
# parse/read problem (see header "REVIEW-PROFILE FLOOR"). Always returns 0.
gate_profile_review_floor() {
  local rp_file="${1:-}"
  if [[ -z "$rp_file" || ! -f "$rp_file" ]]; then
    echo ""
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo full   # can't parse without jq — fail closed, never silently skip
    return 0
  fi
  local risk
  risk="$(jq -r '.review_profile.risk_profile // empty' "$rp_file" 2>/dev/null || true)"
  case "$risk" in
    docs_trivial) echo quick ;;
    low) echo targeted ;;
    medium) echo standard ;;
    high) echo full ;;
    *) echo full ;;   # unverifiable, empty (missing field), or unknown value
  esac
  return 0
}

# _aid_gp_apply_floor <base> <floor> — echo max(base, floor); floor="" → base
# unchanged (nothing to apply). Both inputs are always from this file's own
# controlled vocabulary by construction, so gate_profile_max never fails here.
_aid_gp_apply_floor() {
  local base="${1:-}" floor="${2:-}"
  if [[ -z "$floor" ]]; then
    echo "$base"
    return 0
  fi
  gate_profile_max "$base" "$floor"
}

# ─── fsm-state.yaml reader (self-contained, no dependency on aid-fsm.sh's own
# yaml_field — this file must work standalone, before it is ever sourced BY
# aid-fsm.sh). First match wins; prints empty (exit 0) on missing file/key. ──
_aid_gp_yaml_field() {
  local file="${1:-}" key="${2:-}" line
  [[ -f "$file" ]] || return 0
  while IFS= read -r line; do
    if [[ "$line" == "${key}:"* ]]; then
      line="${line#"${key}:"}"
      line="${line#"${line%%[![:space:]]*}"}"    # strip leading ws
      line="${line%"${line##*[![:space:]]}"}"     # strip trailing ws
      printf '%s\n' "$line"
      return 0
    fi
  done < "$file"
  return 0
}

# _aid_gp_read_paths <changed_paths_file|-> — reads newline-delimited paths
# into the caller-provided array name (nameref). Missing/empty file → empty
# array (documented fallback, matches gate_profile_classify_paths' n==0 path).
_aid_gp_read_paths() {
  local -n _gp_out="$1"
  local src="${2:-}" line
  _gp_out=()
  if [[ "$src" == "-" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && _gp_out+=("$line")
    done
  elif [[ -n "$src" && -f "$src" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && _gp_out+=("$line")
    done < "$src"
  fi
  return 0
}

# ─── The resolver ───────────────────────────────────────────────────────────

# gate_profile_resolve <changed_paths_file|-> [<fsm_state_file>] [<review_profile_json>]
# Prints exactly one profile name to stdout. Always returns 0. See header
# "MANUAL OVERRIDE" for the AID_GATE_PROFILE_* env contract.
gate_profile_resolve() {
  local paths_input="${1:-}" fsm_state_file="${2:-}" review_profile_json="${3:-}"

  local -a paths=()
  _aid_gp_read_paths paths "$paths_input"

  local base
  base="$(gate_profile_classify_paths "${paths[@]}")"

  # Release boundary — ONLY evaluated when fsm_state_file is given AND exists.
  # No-fsm-state guard: anything else (unset/empty/nonexistent path) skips
  # this block entirely — documented fallback, not a crash.
  if [[ -n "$fsm_state_file" && -f "$fsm_state_file" ]]; then
    local done_phase
    done_phase="$(_aid_gp_yaml_field "$fsm_state_file" done_phase)"
    if [[ "$done_phase" == "release" ]]; then
      base="$(gate_profile_max "$base" release)"
    fi
  fi

  # review-profile.json floor (tighten-only, via max — never an independent
  # branch that could lower the path-derived result).
  local floor
  floor="$(gate_profile_review_floor "$review_profile_json")"
  local computed
  computed="$(_aid_gp_apply_floor "$base" "$floor")"

  # Manual override.
  local final="$computed"
  local override="${AID_GATE_PROFILE_OVERRIDE:-}"
  local force="${AID_GATE_PROFILE_FORCE:-}"
  local force_reason="${AID_GATE_PROFILE_FORCE_REASON:-}"

  if [[ -n "$override" ]]; then
    local ov_rank comp_rank full_rank
    if ov_rank="$(gate_profile_rank "$override")"; then
      comp_rank="$(gate_profile_rank "$computed")"
      full_rank="$(gate_profile_rank full)"
      if (( ov_rank >= comp_rank )); then
        # Upward (or equal) — always allowed, no waiver needed.
        final="$override"
      elif (( comp_rank >= full_rank )); then
        # Downward from a high-risk-tier computed profile — waiver required.
        if [[ "$force" == "1" && ${#force_reason} -ge 20 ]]; then
          final="$override"
        else
          echo "WARN: aid-gate-profile.sh: downward override to '${override}' rejected — computed profile '${computed}' is high-risk tier (full/release); set AID_GATE_PROFILE_FORCE=1 and AID_GATE_PROFILE_FORCE_REASON ('<>=20 chars>') to waive." >&2
          final="$computed"
        fi
      else
        # Downward from a non-high-risk computed profile — allowed, no waiver.
        final="$override"
      fi
    else
      echo "WARN: aid-gate-profile.sh: AID_GATE_PROFILE_OVERRIDE='${override}' is not a known profile (quick|targeted|standard|full|release) — ignoring." >&2
      final="$computed"
    fi
  fi

  echo "$final"
  return 0
}

# ── Standalone dispatch (skipped when sourced) ──────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    rank)
      if ! gate_profile_rank "${2:-}"; then
        echo "ERROR: unknown gate profile '${2:-}'" >&2
        exit 1
      fi
      ;;
    max)
      gate_profile_max "${2:-}" "${3:-}"
      ;;
    classify-paths)
      _gp_cli_paths=()
      _aid_gp_read_paths _gp_cli_paths "${2:-}"
      gate_profile_classify_paths "${_gp_cli_paths[@]}"
      ;;
    resolve)
      gate_profile_resolve "${2:-}" "${3:-}" "${4:-}"
      ;;
    *)
      echo "Usage: aid-gate-profile.sh {resolve <changed_paths_file|-> [fsm_state_file] [review_profile_json] | rank <name> | max <a> <b> | classify-paths <changed_paths_file|->}" >&2
      exit 1
      ;;
  esac
fi
