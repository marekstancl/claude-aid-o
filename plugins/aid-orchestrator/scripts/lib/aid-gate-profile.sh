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
#   gate_profile_resolve <changed_paths_file|-> [<fsm_state_file>]
#                        [<review_profile_json>] [<boundary>] [--floor-file <p>]
#       The full resolver. Prints exactly one profile name to stdout. Returns
#       0 for every real input combination; the ONLY non-zero return is 2, a
#       USAGE error (unknown boundary, --floor-file without a boundary,
#       unknown flag, too many positionals, unwritable floor file).
#       Honors AID_GATE_PROFILE_OVERRIDE / AID_GATE_PROFILE_FORCE /
#       AID_GATE_PROFILE_FORCE_REASON (see "MANUAL OVERRIDE" below).
#       Also sets AID_GATE_PROFILE_FLOOR (see "BOUNDARY SPLIT" below).
#
# ── BOUNDARY SPLIT (P064 plan Step 8) ───────────────────────────────────────
# One call answers TWO questions:
#   (1) stdout — what THIS boundary should run. EXACTLY ONE LINE, always: both
#       production callers (aid-fsm.sh's advance-to-gates auto-resolve and its
#       GATES:DONE risk precondition) capture all of stdout into one variable
#       and use it as a `gate_profiles` key / a `--profile` value, so a second
#       line would make the active profile invalid and could stop a high-risk
#       EPIC from ever reaching DONE.
#   (2) the ACCUMULATED FLOOR — what the plan-final run must be at minimum.
#       Returned OUT-OF-BAND: the shell variable AID_GATE_PROFILE_FLOOR (any
#       sourcing caller can read it, provided it did not call this function
#       inside a command substitution — that runs in a subshell) and, when
#       `--floor-file <path>` is given, that file. A caller that ignores both
#       — i.e. every caller that existed before this change — sees behaviour
#       byte-identical to before.
#
# `boundary` is the optional FOURTH positional, `epic` or `plan_final`:
#   (omitted/empty) LEGACY — byte-identical to the pre-Step-8 resolver: no
#                   cap, release escalation applied to stdout as before.
#   epic            The EPIC's own gate run. The release-boundary escalation
#                   below is SUPPRESSED for stdout and the result is capped at
#                   `standard` — an EPIC boundary never starts a broad suite;
#                   a mid-plan broad run is a PM act recorded as an exception
#                   at `aid-plan-fsm.sh epic-complete --full-tests`, not
#                   something an env var can talk this resolver into. The cap
#                   is applied AFTER the override layer, so an upward
#                   AID_GATE_PROFILE_OVERRIDE cannot bypass it either, while
#                   the override's own waiver gating still sees the TRUE
#                   (uncapped) risk tier.
#   plan_final      The plan-final run: max(accumulated floor, release).
# The floor is always computed UNBOUNDED (release escalation included, cap not
# applied) and is never lowered by a downward override — a waiver at the EPIC
# boundary buys a cheaper EPIC run, never a cheaper plan-final run.
#
# Flags follow the positionals and are parsed only after them. `--floor-file`
# is the sole flag and is valid ONLY together with an explicit boundary;
# passing it without one is a usage error (exit 2) rather than a silent no-op.
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
#     # boundary split, floor read back through a file (works from a subshell):
#     profile=$(gate_profile_resolve "$paths" "$fsm_state" "$rp" epic --floor-file "$f")
#   Standalone:
#     bash aid-gate-profile.sh resolve <changed_paths_file|-> [<fsm_state_file>] [<review_profile_json>] [<boundary>] [--floor-file <path>]
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

# _aid_gp_cap <value> <ceiling> — echo whichever of the two has the LOWER rank
# (the boundary cap; the mirror image of gate_profile_max). An unknown name on
# either side echoes <value> unchanged — capping is a tightening convenience,
# never a place to lose the caller's answer.
_aid_gp_cap() {
  local v="${1:-}" c="${2:-}" rv rc
  rv="$(gate_profile_rank "$v")" || { echo "$v"; return 0; }
  rc="$(gate_profile_rank "$c")" || { echo "$v"; return 0; }
  if (( rv > rc )); then echo "$c"; else echo "$v"; fi
  return 0
}

# _aid_gp_apply_override <computed> [<risk_tier>] — the MANUAL OVERRIDE layer,
# unchanged in behaviour and extracted verbatim except for the second
# argument, which defaults to <computed> (i.e. to exactly today's semantics).
# The boundary split passes the TRUE, unsuppressed risk profile as <risk_tier>
# so the waiver gating below keeps meaning "is this diff high-risk" rather
# than "is what this boundary would run high-risk". Echoes the result.
_aid_gp_apply_override() {
  local computed="${1:-}" risk_tier="${2:-${1:-}}"
  local final="$computed"
  local override="${AID_GATE_PROFILE_OVERRIDE:-}"
  local force="${AID_GATE_PROFILE_FORCE:-}"
  local force_reason="${AID_GATE_PROFILE_FORCE_REASON:-}"

  if [[ -n "$override" ]]; then
    local ov_rank comp_rank full_rank risk_rank
    if ov_rank="$(gate_profile_rank "$override")"; then
      comp_rank="$(gate_profile_rank "$computed")"
      full_rank="$(gate_profile_rank full)"
      risk_rank="$(gate_profile_rank "$risk_tier")" || risk_rank="$comp_rank"
      if (( ov_rank >= comp_rank )); then
        # Upward (or equal) — always allowed, no waiver needed.
        final="$override"
      elif (( risk_rank >= full_rank )); then
        # Downward from a high-risk-tier computed profile — waiver required.
        if [[ "$force" == "1" && ${#force_reason} -ge 20 ]]; then
          final="$override"
        else
          echo "WARN: aid-gate-profile.sh: downward override to '${override}' rejected — computed profile '${risk_tier}' is high-risk tier (full/release); set AID_GATE_PROFILE_FORCE=1 and AID_GATE_PROFILE_FORCE_REASON ('<>=20 chars>') to waive." >&2
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

# gate_profile_resolve <changed_paths_file|-> [<fsm_state_file>]
#                      [<review_profile_json>] [<boundary>] [--floor-file <p>]
# Prints exactly one profile name to stdout and sets AID_GATE_PROFILE_FLOOR.
# Returns 0 except for usage errors, which return 2. See the header sections
# "BOUNDARY SPLIT" and "MANUAL OVERRIDE".
gate_profile_resolve() {
  # ── argument parsing: positionals first, flags after (header contract) ──
  local -a _pos=()
  local floor_file="" flags_started=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --floor-file)
        flags_started=true
        if [[ $# -lt 2 ]]; then
          echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: --floor-file requires a <path> argument." >&2
          return 2
        fi
        floor_file="$2"
        shift 2
        ;;
      --*)
        echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: unknown flag '$1' (the only defined flag is --floor-file <path>)." >&2
        return 2
        ;;
      *)
        if $flags_started; then
          echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: positional argument '$1' appears after a flag — positionals come first." >&2
          return 2
        fi
        if (( ${#_pos[@]} >= 4 )); then
          echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: too many positional arguments (max 4: <changed_paths_file|-> [fsm_state_file] [review_profile_json] [boundary])." >&2
          return 2
        fi
        _pos+=("$1")
        shift
        ;;
    esac
  done

  local paths_input="${_pos[0]:-}" fsm_state_file="${_pos[1]:-}"
  local review_profile_json="${_pos[2]:-}" boundary="${_pos[3]:-}"

  case "$boundary" in
    ""|epic|plan_final) ;;
    *)
      echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: unknown boundary '${boundary}' (expected 'epic' or 'plan_final')." >&2
      return 2
      ;;
  esac
  if [[ -n "$floor_file" && -z "$boundary" ]]; then
    echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: --floor-file is only valid together with an explicit boundary ('epic' or 'plan_final') as the 4th positional." >&2
    return 2
  fi

  local -a paths=()
  _aid_gp_read_paths paths "$paths_input"

  local base
  base="$(gate_profile_classify_paths "${paths[@]}")"

  # Release boundary — ONLY evaluated when fsm_state_file is given AND exists.
  # No-fsm-state guard: anything else (unset/empty/nonexistent path) skips
  # this block entirely — documented fallback, not a crash. The signal always
  # feeds the accumulated FLOOR; it is suppressed only for what boundary=epic
  # prints (an EPIC boundary never runs the release suite on its own).
  local release_boundary=false
  if [[ -n "$fsm_state_file" && -f "$fsm_state_file" ]]; then
    local done_phase
    done_phase="$(_aid_gp_yaml_field "$fsm_state_file" done_phase)"
    if [[ "$done_phase" == "release" ]]; then
      release_boundary=true
    fi
  fi

  # review-profile.json floor (tighten-only, via max — never an independent
  # branch that could lower the path-derived result).
  local rp_floor
  rp_floor="$(gate_profile_review_floor "$review_profile_json")"

  # UNBOUNDED view — what the risk really demands, cap and suppression aside.
  local unbounded="$base"
  if $release_boundary; then
    unbounded="$(gate_profile_max "$unbounded" release)"
  fi
  unbounded="$(_aid_gp_apply_floor "$unbounded" "$rp_floor")"

  # BOUNDARY view — identical to `unbounded` except at boundary=epic, where
  # the release escalation is suppressed (the cap below handles the rest).
  local computed="$base"
  if [[ "$boundary" != "epic" ]] && $release_boundary; then
    computed="$(gate_profile_max "$computed" release)"
  fi
  computed="$(_aid_gp_apply_floor "$computed" "$rp_floor")"

  # Manual override, evaluated against the boundary view but waiver-gated on
  # the TRUE risk tier (see _aid_gp_apply_override).
  local final
  final="$(_aid_gp_apply_override "$computed" "$unbounded")"
  if [[ "$boundary" == "epic" ]]; then
    # The cap is absolute and applied LAST: not even an upward
    # AID_GATE_PROFILE_OVERRIDE may start a broad suite at an EPIC boundary.
    # The sanctioned way to run one mid-plan is the audited PM exception at
    # `aid-plan-fsm.sh epic-complete --full-tests --reason "<text>"`.
    final="$(_aid_gp_cap "$final" standard)"
  fi

  # The accumulated floor: never below the unbounded risk, never lowered by a
  # downward override, raised by an upward one.
  local accumulated_floor
  accumulated_floor="$(gate_profile_max "$unbounded" "$final")"

  local result="$final"
  if [[ "$boundary" == "plan_final" ]]; then
    result="$(gate_profile_max "$accumulated_floor" release)"
  fi

  AID_GATE_PROFILE_FLOOR="$accumulated_floor"
  if [[ -n "$floor_file" ]]; then
    if ! printf '%s\n' "$accumulated_floor" > "$floor_file" 2>/dev/null; then
      echo "ERROR: aid-gate-profile.sh: gate_profile_resolve: could not write the accumulated floor to '${floor_file}'." >&2
      return 2
    fi
  fi

  echo "$result"
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
      # Forward EVERY remaining argument (boundary positional + --floor-file)
      # instead of the fixed three — the standalone path is the one a
      # non-sourcing caller uses, which is exactly who needs --floor-file.
      shift
      gate_profile_resolve "$@"
      ;;
    *)
      echo "Usage: aid-gate-profile.sh {resolve <changed_paths_file|-> [fsm_state_file] [review_profile_json] [boundary: epic|plan_final] [--floor-file <path>] | rank <name> | max <a> <b> | classify-paths <changed_paths_file|->}" >&2
      exit 1
      ;;
  esac
fi
