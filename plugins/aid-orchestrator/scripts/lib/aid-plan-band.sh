#!/usr/bin/env bash
# =============================================================================
# lib/aid-plan-band.sh — the ceremony band of a plan, classified ONCE, here
# (P084 Step 1).
#
# The band answers "how much ceremony does this plan owe" and it is derived
# from the paths the plan's steps DECLARE in their **Files:** blocks, read with
# the same parser the generator and the plan lint use (lib/aid-scoping.sh),
# matched against the curated map defaults/policies/risk-paths.yaml.
#
# WHY A LIB AND NOT JUST THE GATE'S `--classify-only`
#   Two consumers need the band: aid-cp1-gate.sh (which enforces what the band
#   owes) and aid-plan-lint.sh (which checks the plan against band-scoped
#   obligations at write time). The lint CANNOT shell out to the gate: "the CP1
#   gate is consulted exactly once per plan" is an invariant the generation
#   suites assert by COUNTING gate invocations
#   (scripts/tests/bats/generation-fixture.bash `gen_cp1_calls`), and the lint
#   runs inside generation's own pre-flight. One implementation, two callers,
#   no second gate call — and `aid-cp1-gate.sh --classify-only` stays available
#   for session-level consumers (commands/aid-plan.md) that are outside the
#   generation transaction.
#
# Pure: reads the plan file and the map, writes nothing. Idempotent
# double-source guard.
#
# Contract: aid_plan_band <plan_file> <project_root> echoes "<band>\t<reason>",
# band being full|medium|light. Every uncertainty resolves to `full`.
#
# **Last Updated:** 2026-08-22
# =============================================================================
[[ -n "${_AID_PLAN_BAND_SH_LOADED:-}" ]] && return 0
_AID_PLAN_BAND_SH_LOADED=1

_AID_BAND_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-scoping.sh
source "${_AID_BAND_LIB_DIR}/aid-scoping.sh"

AID_BAND_RISK_PATHS_DEFAULT="${AID_PLUGIN_PATH:-${_AID_BAND_LIB_DIR}/../..}/defaults/policies/risk-paths.yaml"

# _aid_band_declared_paths <plan> — every cleaned path the plan's **Files:** blocks
# declare, one per line. Uses the shared extractor + cleaner, so the set is
# byte-identical to the one the generator turns into allowed_paths. Bullets the
# cleaner rejects are SKIPPED, not fatal: refusing a malformed Files entry is
# aid-plan-lint.sh's job, and a gate that died here would block on a defect it
# is not the authority for.
_aid_band_declared_paths() {
  local bullet body
  while IFS= read -r bullet; do
    [[ -n "$bullet" ]] || continue
    body="$(_aid_files_bullet_body "$bullet")" || continue
    _aid_split_path_entry "$body" 2>/dev/null || true
  done < <(_aid_extract_files_bullets < "$1")
}

# _aid_band_map_ere <map_file> <key> — the map's list under <key> joined into ONE
# ERE. An absent key or an empty list yields an empty ERE, which _aid_band_re_match
# treats as "matches nothing" rather than as a match-everything empty pattern.
# Returns 1 when yq itself failed (unparseable map): the caller must fall back,
# never read a read-failure as "this map lists nothing".
_aid_band_map_ere() {
  local out
  out="$(yq -r ".${2}[]?" "$1" 2>/dev/null)" || return 1
  printf '%s' "$out" | paste -sd '|' -
}

_aid_band_re_match() {
  local path="$1" ere="$2"
  [[ -n "$ere" ]] || return 1
  [[ "$path" =~ $ere ]]
}

# _aid_band_project_root <plan> — the project whose policy override applies to
# this plan: the nearest ancestor of the PLAN that holds a `.aid-o/`. Callers
# that know their root (the gate) pass it; callers that do not (the lint, run
# from anywhere) must not fall back to `pwd`, or the two would read different
# maps for the same plan and the "one classification" promise would be false.
_aid_band_project_root() {
  local dir
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || return 1
  while [[ -n "$dir" && "$dir" != "/" ]]; do
    [[ -d "${dir}/.aid-o" ]] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

# _aid_band_frontmatter_risk <plan> — the `risk:` value from the plan's own
# frontmatter block, or nothing. Read HERE, not in each caller: the escalation
# below is part of the classification, and a caller that forgot it would check
# a `risk: high` plan for less than the gate demands of it.
_aid_band_frontmatter_risk() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && $0 ~ /^risk:/ {
      sub(/^risk:[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit
    }
  ' "$1"
}

# aid_plan_band <plan> [project_root] — echoes "<band>\t<reason>".
# The reason names WHY, so telemetry and PM both get more than a verdict.
aid_plan_band() {
  local plan="$1" project_root="${2:-}"
  local map="" cand
  [[ -n "$project_root" ]] || project_root="$(_aid_band_project_root "$plan")" || project_root=""
  for cand in "${project_root}/.aid-o/config/policies/risk-paths.yaml" "$AID_BAND_RISK_PATHS_DEFAULT"; do
    [[ -f "$cand" ]] && { map="$cand"; break; }
  done
  if [[ -z "$map" ]]; then
    printf 'full\tno_risk_map'
    return 0
  fi
  if ! command -v yq >/dev/null 2>&1; then
    printf 'full\tno_yq'
    return 0
  fi

  local full_ere medium_ere excluded_ere
  if ! full_ere="$(_aid_band_map_ere "$map" full_paths)" \
    || ! medium_ere="$(_aid_band_map_ere "$map" medium_paths)" \
    || ! excluded_ere="$(_aid_band_map_ere "$map" excluded_paths)"; then
    printf 'full\tunreadable_risk_map'
    return 0
  fi

  # Frontmatter `risk: high` RAISES the band and nothing lowers one, so it is
  # decided before any path is read — the paths can only agree with it.
  if [[ "$(_aid_band_frontmatter_risk "$plan")" == "high" ]]; then
    printf 'full\tfrontmatter_risk_high'
    return 0
  fi

  local band="light" reason="no_mapped_path" declared=0 considered=0 path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    declared=$(( declared + 1 ))
    _aid_band_re_match "$path" "$excluded_ere" && continue
    considered=$(( considered + 1 ))
    if _aid_band_re_match "$path" "$full_ere"; then
      printf 'full\tfull_path:%s' "$path"
      return 0
    fi
    if [[ "$band" != "medium" ]] && _aid_band_re_match "$path" "$medium_ere"; then
      band="medium"
      reason="medium_path:${path}"
    fi
  done < <(_aid_band_declared_paths "$plan")

  # No declared path at all: nothing to classify FROM, so the gate must not
  # guess low. aid-plan-lint.sh already refuses such a plan, and this is the
  # gate refusing to depend on someone else's check.
  if [[ "$declared" -eq 0 ]]; then
    printf 'full\tno_files_declared'
    return 0
  fi
  # Every declared path was a release/ceremony file: that is a real `light`
  # (AC4), not an absence of information.
  if [[ "$considered" -eq 0 ]]; then
    printf 'light\tonly_excluded_paths'
    return 0
  fi
  printf '%s\t%s' "$band" "$reason"
}

