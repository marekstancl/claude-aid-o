#!/usr/bin/env bash
# aid-epic-summary.sh — Auto-generate epic-summary.md after done-advance review→release.
# Best-effort: each section is individually guarded; failures log_warn, never abort release.
# Output: <evidence_dir>/epic-summary.md (5 sections, Czech prose, English technical fields).
#
# Usage: aid-epic-summary.sh generate <evidence_dir>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-stage-log.sh
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

die() { echo "ERROR: $*" >&2; exit 1; }

main() {
  local cmd="${1:-}"
  [[ -z "$cmd" ]] && { echo "Usage: aid-epic-summary.sh generate <evidence_dir>" >&2; exit 1; }
  shift
  case "$cmd" in
    generate) cmd_generate "$@" ;;
    *) die "Unknown command: $cmd" ;;
  esac
}

cmd_generate() {
  [[ $# -lt 1 ]] && die "generate requires <evidence_dir>"
  local evidence_dir="$1"
  [[ -d "$evidence_dir" ]] || die "Evidence dir not found: $evidence_dir"

  local state_file="${evidence_dir}/state.yaml"
  [[ -f "$state_file" ]] || die "state.yaml not found: $state_file"

  local epic_id run_id
  epic_id=$(grep '^epic_id:' "$state_file" | awk '{print $2}') || epic_id="unknown"
  run_id=$(grep  '^run_id:'  "$state_file" | awk '{print $2}') || run_id="unknown"

  local output_file="${evidence_dir}/epic-summary.md"
  local timeline="${evidence_dir}/timeline.jsonl"
  local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  {
    emit_header   "$epic_id"    "$state_file" "$evidence_dir" || true
    emit_shipped  "$evidence_dir" "$state_file"               || true
    emit_warnings "$evidence_dir" "$timeline"  "$state_file"  || true
    emit_deferred "$evidence_dir"                              || true
    emit_pm_actions "$evidence_dir" "$timeline"               || true
    emit_trust_signal "$evidence_dir" "$state_file"           || true
    printf '\n---\n_Generated: %s by aid-epic-summary.sh@v2.18.0_\n' "$now"
  } > "$output_file"

  log_info "epic-summary.md written: $output_file" 2>/dev/null || true
}

# ─── Section: header ──────────────────────────────────────────────────────────

emit_header() {
  local epic_id="$1" state_file="$2" evidence_dir="$3"
  local title="EPIC dokončen"

  # Best-effort: try final_report.md first heading after # or Title:
  local final_report="${evidence_dir}/final_report.md"
  if [[ -f "$final_report" ]]; then
    local found
    found=$(grep -m1 -E '^(Title:|# [A-Z])' "$final_report" 2>/dev/null \
      | sed 's/^#* *//' | sed 's/^Title: *//' || true)
    [[ -n "$found" ]] && title="$found"
  fi

  printf '# %s done — %s\n\n' "$epic_id" "$title"
}

# ─── Section 1: What shipped ──────────────────────────────────────────────────

emit_shipped() {
  local evidence_dir="$1" state_file="$2"
  printf '## ✅ Co bylo dodáno\n\n'

  local base_commit
  base_commit=$(grep '^base_commit:' "$state_file" | awk '{print $2}' 2>/dev/null) || base_commit=""

  local log_lines=""
  if [[ -n "$base_commit" && "$base_commit" != "HEAD" ]]; then
    log_lines=$(git log --oneline "${base_commit}..HEAD" 2>/dev/null || true)
  fi

  # Fallback: last total_steps commits when base_commit unavailable
  if [[ -z "$log_lines" ]]; then
    local n
    n=$(grep '^total_steps:' "$state_file" | awk '{print $2}' 2>/dev/null) || n="5"
    log_lines=$(git log --oneline -"${n:-5}" 2>/dev/null || true)
  fi

  if [[ -n "$log_lines" ]]; then
    while IFS= read -r line; do
      printf -- '- `%s`\n' "$line"
    done <<< "$log_lines"
  else
    printf -- '- (git log nedostupný nebo žádné commity od startu EPIC)\n'
  fi
  printf '\n'
}

# ─── Section 2: Warnings ─────────────────────────────────────────────────────

emit_warnings() {
  local evidence_dir="$1" timeline="$2" state_file="$3"
  printf '## ⚠️ Varování a přeskočené kroky\n\n'

  local found_any=false

  if [[ -f "$timeline" ]]; then
    # Branch mismatch
    local n
    n=$(jq -s '[.[] | select(.event=="fsm_branch_mismatch_detected")] | length' "$timeline" 2>/dev/null || echo 0)
    if (( n > 0 )); then
      printf -- '- **⚠️ Větev nesedí:** Detekován mismatch větve při inicializaci (%d×). Audit trail mohl být přerušen.\n' "$n"
      found_any=true
    fi

    # Unusual branch
    n=$(jq -s '[.[] | select(.event=="fsm_branch_unusual_detected")] | length' "$timeline" 2>/dev/null || echo 0)
    if (( n > 0 )); then
      printf -- '- **ℹ️ Neobvyklá větev:** Větev nesplňuje konvenci task/<id>/main, ale pokračovalo se (%d×).\n' "$n"
      found_any=true
    fi

    # force_override events
    n=$(jq -s '[.[] | select(.event=="fsm_force_override")] | length' "$timeline" 2>/dev/null || echo 0)
    if (( n > 0 )); then
      printf -- '- **🔴 Force override:** FSM precondition bylo obejito --force %d×. Zkontroluj audit-log.jsonl.\n' "$n"
      jq -rs '[.[] | select(.event=="fsm_force_override")
               | "  - `" + (.from // "?") + " → " + (.to // "?") + "`: "
                         + (.reason // "<bez důvodu>")] | .[]' \
        "$timeline" 2>/dev/null || true
      found_any=true
    fi

    # Repeated precondition failures
    n=$(jq -s '[.[] | select(.event | test("^fsm_precondition_repeated_fail"))] | length' "$timeline" 2>/dev/null || echo 0)
    if (( n > 0 )); then
      printf -- '- **⚠️ Opakovaná selhání precondition:** %d× — možné systematické obcházení.\n' "$n"
      found_any=true
    fi

    # Increment-step failures (> 5 indicates churn)
    n=$(jq -s '[.[] | select(.event=="fsm_increment_fail")] | length' "$timeline" 2>/dev/null || echo 0)
    if (( n > 5 )); then
      printf -- '- **⚠️ Časté selhání increment-step:** %d× — možné opakované přeskakování verification.\n' "$n"
      found_any=true
    fi
  fi

  # Gate retries from state.yaml
  local gate_retries
  gate_retries=$(grep '^gate_retries:' "$state_file" | awk '{print $2}' 2>/dev/null) || gate_retries=0
  if (( ${gate_retries:-0} > 1 )); then
    printf -- '- **⚠️ Opakované brány:** Quality gates musely být spuštěny %d× před úspěchem.\n' "$gate_retries"
    found_any=true
  fi

  if ! $found_any; then
    printf -- '- Žádná varování. EPIC proběhl bez obcházení nebo opakování.\n'
  fi
  printf '\n'
}

# ─── Section 3: What didn't get done ─────────────────────────────────────────

emit_deferred() {
  local evidence_dir="$1"
  printf '## ❌ Co se nestihlo\n\n'

  local found_any=false

  # Audit report — blocking/deferred findings
  local audit_report=""
  for f in "${evidence_dir}/audit-report.md" "${evidence_dir}/audit-report.yaml"; do
    [[ -f "$f" ]] && { audit_report="$f"; break; }
  done
  if [[ -n "$audit_report" ]]; then
    local blocking
    blocking=$(grep -i -E '(blocking|effort.*L\b|CRITICAL|L-effort)' "$audit_report" 2>/dev/null \
      | grep -v '^#' | head -5 || true)
    if [[ -n "$blocking" ]]; then
      printf 'Z audit reportu — blokující nebo L-effort nálezy:\n'
      while IFS= read -r line; do printf -- '- %s\n' "$line"; done <<< "$blocking"
      found_any=true
    fi
  fi

  # Curator report — deferred/L-effort proposals
  local curator_report=""
  for f in "${evidence_dir}/curator-report.md" "${evidence_dir}/curator-report.yaml"; do
    [[ -f "$f" ]] && { curator_report="$f"; break; }
  done
  if [[ -n "$curator_report" ]]; then
    local deferred
    deferred=$(grep -i -E '(defer|deferred|not.applied|L.effort)' "$curator_report" 2>/dev/null \
      | grep -v '^#' | head -5 || true)
    if [[ -n "$deferred" ]]; then
      printf 'Z curator reportu — odložené návrhy:\n'
      while IFS= read -r line; do printf -- '- %s\n' "$line"; done <<< "$deferred"
      found_any=true
    fi
  fi

  if ! $found_any; then
    printf -- '- Curator a auditor nehlásí žádné blokující nebo odložené položky.\n'
  fi
  printf '\n'
}

# ─── Section 4: PM next actions ──────────────────────────────────────────────

emit_pm_actions() {
  local evidence_dir="$1" timeline="$2"
  printf '## 📋 Co dělat dál (PM akce)\n\n'

  local found_any=false

  if [[ -f "$timeline" ]]; then
    # Escalation events
    local escalations
    escalations=$(jq -rs '[.[] | select(.event=="fsm_escalation")
                           | "- Eskalace: " + (.reason // "?")] | .[]' \
      "$timeline" 2>/dev/null || true)
    if [[ -n "$escalations" ]]; then
      printf '%s\n' "$escalations"
      found_any=true
    fi

    # Force override → audit required
    local fc
    fc=$(jq -s '[.[] | select(.event=="fsm_force_override")] | length' "$timeline" 2>/dev/null || echo 0)
    if (( ${fc:-0} > 0 )); then
      printf -- '- Zkontroluj audit-log.jsonl — %d force override(s) vyžaduje ruční review před dalším EPIC.\n' "$fc"
      found_any=true
    fi
  fi

  # Curator L-effort proposals
  local curator_report=""
  for f in "${evidence_dir}/curator-report.md" "${evidence_dir}/curator-report.yaml"; do
    [[ -f "$f" ]] && { curator_report="$f"; break; }
  done
  if [[ -n "$curator_report" ]]; then
    local l_effort
    l_effort=$(grep -i -E '\bL-effort\b|effort.*:\s*L\b' "$curator_report" 2>/dev/null \
      | grep -v '^#' | head -3 || true)
    if [[ -n "$l_effort" ]]; then
      printf -- '- L-effort návrhy z curatoru (vyžadují vlastní EPIC nebo PM rozhodnutí):\n'
      while IFS= read -r line; do printf '  - %s\n' "$line"; done <<< "$l_effort"
      found_any=true
    fi
  fi

  if ! $found_any; then
    printf -- '- Žádné vyžadované PM akce identifikovány. EPIC je uzavřen.\n'
  fi
  printf '\n'
}

# ─── Section 5: Honest signal ─────────────────────────────────────────────────

emit_trust_signal() {
  local evidence_dir="$1" state_file="$2"
  printf '## 🔍 Honest signal — PM trust level\n\n'

  local force_count=0 gate_retries=0 overall="true" branch_correct="true"
  local trust="HIGH"
  local -a notes=()

  local compliance_file="${evidence_dir}/compliance.json"
  if [[ -f "$compliance_file" ]]; then
    overall=$(jq -r '.overall // true' "$compliance_file" 2>/dev/null || echo "true")
    branch_correct=$(jq -r '.checks.branch_correct // true' "$compliance_file" 2>/dev/null || echo "true")
    force_count=$(jq -r '.force_override_count // 0' "$compliance_file" 2>/dev/null || echo 0)
  fi
  gate_retries=$(grep '^gate_retries:' "$state_file" | awk '{print $2}' 2>/dev/null) || gate_retries=0

  # IMP-089 forward-compat: read branch_convention from project.yaml if it exists
  local branch_convention=""
  local project_yaml="${PWD}/.aid-o/config/project.yaml"
  if [[ -f "$project_yaml" ]]; then
    branch_convention=$(grep '^branch_convention:' "$project_yaml" | awk '{print $2}' 2>/dev/null || true)
  fi

  # Heuristic: branch_correct=false disambiguation
  if [[ "$branch_correct" == "false" ]]; then
    local branch
    branch=$(grep '^branch:' "$state_file" | awk '{print $2}' 2>/dev/null || echo "")
    local is_feature_convention=false
    if [[ "$branch" =~ ^feature/ ]]; then
      is_feature_convention=true
    elif [[ -n "$branch_convention" && "$branch" =~ ^${branch_convention} ]]; then
      is_feature_convention=true
    fi

    if $is_feature_convention; then
      notes+=("branch_correct=false je false alarm: větev '$branch' odpovídá feature/* konvenci (strict metric, skutečná situace OK)")
    else
      notes+=("branch_correct=false: větev '$branch' nesplňuje task/<id>/main ani feature/* konvenci")
      trust="MEDIUM"
    fi
  fi

  if (( ${force_count:-0} > 0 )); then
    notes+=("${force_count} force override(s) použito — zkontroluj důvody v audit-log.jsonl")
    [[ "$trust" == "HIGH" ]] && trust="MEDIUM"
  fi

  if (( ${gate_retries:-0} > 0 )); then
    notes+=("quality gates musely být opakovány ${gate_retries}× — zkontroluj před dalším EPIC")
    [[ "$trust" == "HIGH" ]] && trust="MEDIUM"
  fi

  if [[ "$overall" == "false" ]]; then
    notes+=("compliance.json.overall=false — alespoň jedna compliance dimenze selhala")
    trust="LOW"
  fi

  printf '**Trust: %s**\n\n' "$trust"

  if (( ${#notes[@]} > 0 )); then
    for note in "${notes[@]}"; do printf -- '- %s\n' "$note"; done
  else
    printf -- '- Všechny compliance checks zelené, 0 force overrides, 0 gate retries.\n'
  fi
  printf '\n'
}

main "$@"
