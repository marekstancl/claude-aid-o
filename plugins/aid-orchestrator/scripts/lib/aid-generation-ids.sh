#!/usr/bin/env bash
# =============================================================================
# aid-generation-ids.sh — THE derivation of a generation's per-phase ids.
#
# One definition, sourced by every script that needs it: aid-auto-pipeline.sh
# (which pre-registers every phase's ids in the transaction skeleton, before
# any generator runs), aid-plan-to-epic.sh (which re-derives them at verify
# time and compares them against what the transaction recorded) and
# aid-epic-to-json.sh (which derives the run_id it writes into plan.json).
#
# WHY THE VERIFIER STILL COMPARES. The recorded id and the freshly derived id
# are INDEPENDENT inputs even though one function produces both: the recorded
# one was written by an earlier process, possibly under a different plugin
# version, and lives in a file an actor can edit. Sharing the derivation makes
# the two agree when nothing has drifted; it does not make the comparison
# vacuous. Pair it with AID_GEN_PHASE_DERIVATION_VERSION, which the authority
# seals, so a transaction written under a different derivation is refused
# before any id is even compared.
#
# phase_derivation_version — a LITERAL CONSTANT, bumped only when the phase
# detection algorithm in aid-auto-pipeline.sh ("Detect phase count from plan")
# or any derivation below changes semantically. It exists so a resumed
# transaction can detect that a plugin upgrade changed how phases would be
# derived, instead of silently mixing artifacts from two derivations.
# =============================================================================

AID_GEN_PHASE_DERIVATION_VERSION=1

# aid_gen_plan_num <plan_id> — the bare plan number.
# Strips the leading P, then any leading "-": a plan id like P-TEST-999 would
# otherwise leave "-TEST-999", producing a double-dash epic_id
# "E--TEST-999-..." that breaks aid-auto-pipeline.sh's EPIC-ID regex (curator
# IMP-166; latent while all real plan ids are numeric-only).
aid_gen_plan_num() { printf '%s\n' "$1" | sed 's/^P//; s/^-//'; }

# aid_gen_epic_id <plan_id> <phase> <total>
aid_gen_epic_id() { printf 'E-%s-%s_%s\n' "$(aid_gen_plan_num "$1")" "$2" "$3"; }

# aid_gen_run_id <epic_id> — E-018-1_3 -> R-E018-1
# Format: R-E{plan_num}-{phase} (matches the README directory convention).
# Legacy/non-standard epic ids fall back to a sanitized id plus a run counter.
aid_gen_run_id() {
  local epic_id="$1"
  if [[ "$epic_id" =~ ^E-([0-9]+)-([0-9]+)_([0-9]+)$ ]]; then
    printf 'R-E%s-%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf 'R-%s-1\n' "$(printf '%s' "$epic_id" | sed 's/[^a-zA-Z0-9]//g')"
  fi
}
