#!/usr/bin/env bash
# aid-release-policy.sh — C4 release-readiness aggregator (E-059-2_2 Step 4).
#
# Reads every evidence input per the Data Model contract — fail-closed and
# deterministically — and emits a protocol-v2 `release_decision` artifact carrying
# the release_ready verdict, per-input verdicts, blockers, and the 11 D11 state
# fields the FSM merge gate + PM brief read DIRECTLY (never inferring state).
#
# Usage (EPIC mode — UNCHANGED, positional):
#   aid-release-policy.sh <epic_id> <run_id> [--out <path>]
#
# Usage (PLAN mode — P068 E-068-1_2 Step 4, flag-driven, mutually exclusive with the
# positional form):
#   aid-release-policy.sh --plan <plan_id> --run-id <run_id> --evidence-dir <path>
#                         --candidate-sha <sha> --target-ref <ref> --target-head-sha <sha>
#                         [--out <path>]
#
# PLAN MODE is the plan-final release boundary (P064 roadmap D10). It replaces the
# RESOLUTION layer only — every compute_* function, every verdict rule and the whole
# envelope shape are reused. What differs:
#   * identity            — {project_id, plan_id, run_id, epic_id: null, step_id: null}
#   * EVIDENCE_DIR        — the plan-final run directory, taken from the manifest
#   * the comparison head — the FROZEN CANDIDATE, not the worktree HEAD
#   * plan_review         — the plan's OWN C0 review at
#                           .aid-o/work/evidence/<plan_id>/c0-plan-review.json (the path
#                           aid-c0-plan-review.sh actually writes), NOT the epic_input.md
#                           plan_ref hop, which has no meaning without an EPIC input
#   * reporter/simplifier — MANDATORY at this boundary. The EPIC-mode `ca-review-complete`
#                           marker does not exist by construction here, so the EPIC branch
#                           would return a non-blocking `not_applicable` — exactly inverting
#                           their purpose. In plan mode the run directory's own
#                           delivery-report.json / simplifier-report.md ARE the boundary
#                           condition; missing or stale is a blocker, never a skip.
#   * epic roll-up        — every EPIC merged into the plan must be named in the
#                           plan-level delivery-gate/acceptance-evidence sources[] and
#                           have its evidence directory on disk; otherwise a blocker
#                           `epic_rollup:<epic_id>` NAMING that EPIC.
#
# IDENTITY VALIDATION (plan mode, before any evidence read — exit 1, never a degraded
# decision): the plan-boundary manifest must declare the same plan_id, the same
# plan_final_run_id, a candidate_sha equal to --candidate-sha, a
# target_branch_head_at_candidate_freeze equal to --target-head-sha, and a
# plan_final_evidence_dir equal to --evidence-dir. This is a P064-owned invariant, not a
# policy-mode question: passing an EPIC evidence directory fails here even when it is a
# complete, valid EPIC pack. A COPY of an EPIC pack placed at the plan path survives this
# check by construction (the path is right) and is caught one layer down: every required
# plan-mode artifact must carry identity.plan_id == <plan_id>, identity.run_id == <run_id>
# and identity.epic_id == null, or it is `blocked` with a blocker.
#
# Data Model (REQUIRED / PROFILE-GATED / ADVISORY / CONDITIONAL / OPTIONAL):
#   REQUIRED (missing → blocked): review-profile, delivery-gate, semantic-review-final,
#     acceptance-evidence, gates_report (root, fallback gates/), plan-review (plan_ref hop),
#     verification-report (aid-evidence-verify.sh --at-head; fail OR unverifiable both block).
#   PROFILE-GATED (required only when the C3 audit gate is active): curator-report, audit-report.
#   ADVISORY (missing → advisory, never blocks): invalidation-map.
#   CONDITIONAL (marker→toggle→file): reporter (.aid-o/reports/<Pnum>-delivery.md, reporter.enabled),
#     simplifier (<evidence_dir>/simplifier-report.md, simplifier.enabled).
#   OPTIONAL: waiver-*.json → waivers_applied[] (Waived != pass).
#
# Exit codes:
#   0  — release_decision artifact produced (regardless of the release_ready value)
#   2  — usage error
#
# Determinism: two runs at the same HEAD produce byte-identical payloads after
# `jq 'del(.created_at)'` — created_at is the only time-varying field.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${AID_PLUGIN_PATH:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
EVIDENCE_VERIFY="${SCRIPT_DIR}/aid-evidence-verify.sh"
PROTOCOL_VALIDATE="${SCRIPT_DIR}/aid-protocol-validate.sh"
C3_POLICY_FILE="${PLUGIN_ROOT}/defaults/policies/c3-audit-policy.yaml"

# Shared review-signal substrate (B1) — _aid_read_toggle + _aid_validate_test_evidence.
# The SAME functions fsm_eval_delivery_report_present / fsm_eval_simplifier_present read,
# so the aggregator and the FSM compliance checks never diverge on the reporter/simplifier
# substrate.
# shellcheck source=lib/aid-review-signals.sh
source "${SCRIPT_DIR}/lib/aid-review-signals.sh"

# ---------------------------------------------------------------------------
# Accumulators (globals mutated by add_input / add_blocker / waiver loop)
# ---------------------------------------------------------------------------
INPUTS_JSON="[]"
BLOCKERS_JSON="[]"
WAIVERS_JSON="[]"
WAIVER_FINDINGS_JSON="[]"   # E-060-2_2 Step 8 — per-waiver disposition (applied | orphan_waiver)

# Reporter / Simplifier CONDITIONAL results (set by compute_reporter/compute_simplifier)
REPORTER_STATUS="not_applicable"
REPORTER_REASON="not_plan_boundary"
REPORTER_ARTIFACT=".aid-o/reports/delivery.md"
SIMPLIFIER_STATUS="not_applicable"
SIMPLIFIER_REASON="not_plan_boundary"
SIMPLIFIER_ARTIFACT="simplifier-report.md"

# ---------------------------------------------------------------------------
# Small deterministic helpers
# ---------------------------------------------------------------------------

# add_input <id> <artifact> <verdict> <reason> <head_match>
# head_match (5th arg) is a JSON-ENCODED value — `true`, `false`, or the quoted JSON string
# `"unknown"` (E-060-2_2 Step 8). It is passed via --argjson, so a bare `unknown` would crash
# jq: callers MUST pass either a bare boolean or `'"unknown"'`. The head_match helpers below
# already echo the JSON-encoded form (true | false | "unknown").
# jq -n (null input) — the row is built purely from --arg/--argjson; without -n jq would
# block reading stdin.
add_input() {
  INPUTS_JSON="$(jq -cn \
    --argjson arr "$INPUTS_JSON" \
    --arg id "$1" --arg artifact "$2" --arg verdict "$3" --arg reason "$4" \
    --argjson head_match "$5" \
    '$arr + [{id:$id, artifact:$artifact, verdict:$verdict, reason:$reason, head_match:$head_match}]')"
}

# add_blocker <input_id(canonical)> <severity> <reason>
add_blocker() {
  BLOCKERS_JSON="$(jq -cn \
    --argjson arr "$BLOCKERS_JSON" \
    --arg input_id "$1" --arg severity "$2" --arg reason "$3" \
    '$arr + [{input_id:$input_id, severity:$severity, reason:$reason}]')"
}

# _is_json <file> — present AND parseable JSON (fail-closed presence+parse gate).
_is_json() {
  local f="$1"
  [[ -s "$f" ]] || return 1                              # missing OR 0-byte → fail-closed (was -f: accepts empty)
  command -v jq >/dev/null 2>&1 || return 0              # no jq → presence-only (unchanged)
  [[ -n "$(jq -c . "$f" 2>/dev/null)" ]] && jq -e . "$f" >/dev/null 2>&1
}

# _artifact_head_match <file> [mode] — echoes the JSON-encoded at-HEAD basis: true | false | "unknown".
# E-060-2_2 Step 8 — the per-input comparison basis (contract 2). An UNCOMPUTABLE basis is ALWAYS
# the declared string "unknown", NEVER a silent true (the pre-Step-8 default `→true` is the class
# L1-B3 bug where a stale/unstamped artifact looked usable).
#   mode=direct   (default): .revision.head_sha == CURRENT_HEAD → true; present-but-differs → false;
#                            no stamp → "unknown" (e.g. a legacy gates_report the Step-2 runner
#                            never stamped — cannot be judged, so declare unknown).
#   mode=ancestry (plan_review): .revision.head_sha is an ANCESTOR of CURRENT_HEAD → true (a
#                            plan-time artifact is stale by construction; correct lineage → basis
#                            met, and it STAYS true after HEAD moves on with release commits);
#                            non-ancestor (rebase / foreign branch) → false; no stamp → "unknown".
# Missing file → false (a required-but-absent artifact is definitively not at-HEAD).
_artifact_head_match() {
  local f="$1" mode="${2:-direct}" hs rc=0
  [[ -f "$f" ]] || { echo false; return 0; }
  command -v jq >/dev/null 2>&1 || { echo '"unknown"'; return 0; }   # uncomputable → declared unknown
  hs="$(jq -r '.revision.head_sha // ""' "$f" 2>/dev/null)" || rc=$?
  { [[ $rc -ne 0 ]] || [[ -z "$hs" ]]; } && { echo '"unknown"'; return 0; }
  # P060 per-plan C+A: validate the stamped sha is a hex object name BEFORE it reaches any
  # git command (mirrors _markdown_head_match). A non-hex value is uncomputable → "unknown",
  # never a git arg (defense-in-depth against a malformed/garbage revision.head_sha).
  [[ "$hs" =~ ^[0-9a-fA-F]{7,40}$ ]] || { echo '"unknown"'; return 0; }
  if [[ "$mode" == "ancestry" ]]; then
    [[ -z "${CURRENT_HEAD:-}" ]] && { echo '"unknown"'; return 0; }
    if git -C "${PROJECT_ROOT:-.}" merge-base --is-ancestor "$hs" "$CURRENT_HEAD" 2>/dev/null; then
      echo true
    else
      echo false
    fi
    return 0
  fi
  # direct
  [[ -z "${CURRENT_HEAD:-}" ]] && { echo '"unknown"'; return 0; }
  [[ "$hs" == "${CURRENT_HEAD}" ]] && echo true || echo false
}

# _markdown_head_match <file> — at-HEAD basis for our OWN markdown producers (reporter delivery
# report, simplifier-report.md), which have NO JSON `revision` block. E-060-2_2 Step 8 contract 3:
# mtime is NEVER a basis; the binding is the producer provenance line `Head: <sha>`. sha matches
# CURRENT_HEAD (full or as a prefix) → true; present-but-differs → false; NO provenance line → the
# declared string "unknown" (git-log binding is impossible — .aid-o/reports/ is gitignored).
_markdown_head_match() {
  local f="$1" sha=""
  [[ -f "$f" ]] || { echo '"unknown"'; return 0; }
  sha="$(grep -iE '^[[:space:]]*Head:[[:space:]]*[0-9a-fA-F]{7,40}([[:space:]]|$)' "$f" 2>/dev/null \
        | head -1 | sed -E 's/^[[:space:]]*[Hh][Ee][Aa][Dd]:[[:space:]]*//; s/[[:space:]].*$//')" || sha=""
  [[ -z "$sha" ]] && { echo '"unknown"'; return 0; }
  [[ -z "${CURRENT_HEAD:-}" ]] && { echo '"unknown"'; return 0; }
  # Accept an abbreviated sha (>=7) that is a prefix of the full CURRENT_HEAD, or an exact match.
  if [[ "$CURRENT_HEAD" == "$sha" || ( "${#sha}" -ge 7 && "$CURRENT_HEAD" == "$sha"* ) ]]; then
    echo true
  else
    echo false
  fi
}

# _is_canonical_input <id> — membership test for the 12 canonical release-decision input ids
# (mirrors the blockers.input_id enum in release-decision.schema.json). Used by the waiver→input
# mapping (contract 6).
_is_canonical_input() {
  case "$1" in
    review_profile|delivery_gate|semantic_review_final|acceptance_evidence|gates_report|\
curator_report|plan_review|verification_report|audit_report|invalidation_map|reporter|simplifier)
      return 0 ;;
    *) return 1 ;;
  esac
}

# _plan_identity_reason <file> — echoes an empty string when the artifact is bound to THIS
# plan and THIS plan-final attempt, or a human reason when it is not. Plan mode only.
#
# This is the check that catches a COPY (or symlink) of a genuine, complete EPIC evidence
# pack dropped at the plan-final path: the directory identity check upstream passes (the
# path is the recorded one), but an EPIC artifact carries identity.epic_id and either no
# identity.plan_id or another plan's, and its run_id is the EPIC's run.
_plan_identity_reason() {
  local f="$1" pid rid eid
  pid="$(jq -r '.identity.plan_id // ""' "$f" 2>/dev/null || echo "")"
  rid="$(jq -r '.identity.run_id // ""' "$f" 2>/dev/null || echo "")"
  eid="$(jq -r '.identity.epic_id // "null"' "$f" 2>/dev/null || echo "null")"
  if [[ "$pid" != "$PLAN_ID" ]]; then
    printf 'identity.plan_id is %s, expected %s' "${pid:-<absent>}" "$PLAN_ID"; return 0
  fi
  if [[ "$rid" != "$RUN_ID" ]]; then
    printf 'identity.run_id is %s, expected this plan-final attempt %s' "${rid:-<absent>}" "$RUN_ID"; return 0
  fi
  if [[ "$eid" != "null" ]]; then
    printf 'identity.epic_id is %s, expected null (a plan-level artifact is bound to the PLAN)' "$eid"; return 0
  fi
  printf ''
}

# check_required_present <id> <blocker_id> <file> — REQUIRED file rows.
# present+parseable → pass; missing/unreadable → blocked + blocker.
# In PLAN mode a present, parseable artifact must ALSO be bound to this plan and this
# attempt — otherwise a copied EPIC pack would satisfy the requirement.
check_required_present() {
  local id="$1" bid="$2" file="$3"
  if _is_json "$file"; then
    if [[ "${MODE:-epic}" == "plan" ]]; then
      local ireason; ireason="$(_plan_identity_reason "$file")"
      if [[ -n "$ireason" ]]; then
        add_input "$id" "$(basename "$file")" "blocked" "present but not bound to this plan-final attempt: ${ireason}" false
        add_blocker "$bid" "blocking" "$(basename "$file") is not bound to this plan-final attempt: ${ireason}"
        return 0
      fi
    fi
    add_input "$id" "$(basename "$file")" "pass" "present and parseable" "$(_artifact_head_match "$file")"
  else
    add_input "$id" "$(basename "$file")" "blocked" "required artifact missing or unreadable" false
    add_blocker "$bid" "blocking" "required artifact missing or unreadable: $(basename "$file")"
  fi
}

# _extract_plan_ref <epic_input.md> — echoes the frontmatter plan_ref value (or empty).
_extract_plan_ref() {
  local epic_input="$1" raw
  [[ -f "$epic_input" ]] || { echo ""; return 0; }
  raw="$(awk '
    /^---[[:space:]]*$/ { c++; if (c==2) exit; next }
    c==1 && $0 ~ /^[[:space:]]*plan_ref[[:space:]]*:/ {
      line=$0
      sub(/^[[:space:]]*plan_ref[[:space:]]*:[[:space:]]*/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      print line
      exit
    }
  ' "$epic_input" 2>/dev/null || true)"
  # trim surrounding whitespace and quotes (bash param expansion — no extra forks)
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  raw="${raw#\"}"; raw="${raw%\"}"
  raw="${raw#\'}"; raw="${raw%\'}"
  echo "$raw"
}

# _c3_gate_active — returns 0 (C3 audit gate active) or 1 (inactive).
# Mirrors fsm_eval / done-advance c3_hook_fired (aid-fsm.sh ~2725-2824): fail-closed to
# ACTIVE for an unverifiable/high profile, and the secondary audit-report.json trigger.
_c3_gate_active() {
  local evidence_dir="$1"
  local review_profile_file="${evidence_dir}/review-profile.json"
  local audit_report_file="${evidence_dir}/audit-report.json"

  # No review-profile.json → this run never entered the C3 pipeline → inactive.
  [[ -f "$review_profile_file" ]] || return 1

  # Resolve risk profile (fail-closed to "unverifiable" on any ambiguity).
  local risk_profile=""
  if ! command -v jq >/dev/null 2>&1; then
    risk_profile="unverifiable"
  else
    local resolved="" rc=0
    resolved="$(jq -r '.review_profile.risk_profile // "MISSING"' "$review_profile_file" 2>/dev/null)" || rc=$?
    if [[ $rc -eq 0 && "$resolved" != "MISSING" ]]; then
      case "$resolved" in
        docs_trivial|low|medium|high|unverifiable) risk_profile="$resolved" ;;
        *) risk_profile="unverifiable" ;;
      esac
    else
      risk_profile="unverifiable"
    fi
  fi

  # Primary trigger: policy c3_required for the resolved profile.
  local policy_read_succeeded="false" c3_required_from_policy=""
  if [[ -f "$C3_POLICY_FILE" ]] && command -v yq >/dev/null 2>&1; then
    local has_key="" hrc=0
    has_key="$(yq -r "(.risk_profiles | has(\"$risk_profile\")) and (.risk_profiles[\"$risk_profile\"] | has(\"c3_required\"))" "$C3_POLICY_FILE" 2>/dev/null)" || hrc=$?
    if [[ $hrc -eq 0 && "$has_key" == "true" ]]; then
      local crc=0
      c3_required_from_policy="$(yq -r ".risk_profiles[\"$risk_profile\"].c3_required" "$C3_POLICY_FILE" 2>/dev/null)" || crc=$?
      if [[ $crc -eq 0 && ("$c3_required_from_policy" == "true" || "$c3_required_from_policy" == "false") ]]; then
        policy_read_succeeded="true"
      fi
    fi
  fi

  if [[ "$policy_read_succeeded" == "true" && "$c3_required_from_policy" == "true" ]]; then
    return 0
  elif [[ "$policy_read_succeeded" != "true" && "$risk_profile" == "high" ]]; then
    return 0   # fail-closed: cannot confirm c3_required=false for a high profile
  elif [[ "$risk_profile" == "unverifiable" ]]; then
    return 0   # fail-closed
  fi

  # Secondary trigger: a real audit-report.json for this run fires the hook even if the
  # primary gate did not (mirrors the FSM defense-in-depth trigger).
  if [[ -f "$audit_report_file" ]] && command -v jq >/dev/null 2>&1; then
    local has_audit="" arc=0
    has_audit="$(jq -r 'if (.audit_report | type) == "object" and (.audit_report | length) > 0 then "true" else "false" end' "$audit_report_file" 2>/dev/null)" || arc=$?
    if [[ $arc -eq 0 && "$has_audit" == "true" ]]; then
      return 0
    fi
  fi

  return 1
}

# process_profile_gated <id> <file> — curator-report / audit-report rows.
# C3 active + missing → blocked (+ blocker); C3 inactive + missing → advisory (no block).
process_profile_gated() {
  local id="$1" file="$2"
  if _is_json "$file"; then
    add_input "$id" "$(basename "$file")" "pass" "present" "$(_artifact_head_match "$file")"
  elif [[ "$C3_ACTIVE" == "true" ]]; then
    add_input "$id" "$(basename "$file")" "blocked" "required when C3 audit gate active; missing" false
    add_blocker "$id" "blocking" "$(basename "$file") required (C3 audit gate active) but missing"
  else
    add_input "$id" "$(basename "$file")" "advisory" "not required (C3 audit gate inactive); absent" true
  fi
}

# _read_autonomous_mode — echoes auto|manual from .aid-o/config/permissions.yaml.
# ONLY a real YAML boolean `autonomous_mode: true` → auto; everything else (false, null,
# missing key, non-boolean, missing file, no yq, preset-model file) → manual (fail-closed).
_read_autonomous_mode() {
  local perm="${PROJECT_ROOT}/.aid-o/config/permissions.yaml"
  [[ -f "$perm" ]] || { echo manual; return 0; }
  command -v yq >/dev/null 2>&1 || { echo manual; return 0; }
  local vtype vval
  vtype="$(yq -r '.autonomous_mode | type' "$perm" 2>/dev/null)" || { echo manual; return 0; }
  [[ "$vtype" == "!!bool" ]] || { echo manual; return 0; }
  vval="$(yq -r '.autonomous_mode' "$perm" 2>/dev/null)" || { echo manual; return 0; }
  [[ "$vval" == "true" ]] && echo auto || echo manual
}

# _status_to_verdict / _status_headmatch — map a reporter/simplifier 5-enum status onto the
# inputs[] verdict enum + head_match field.
_status_to_verdict() {
  case "$1" in
    pass) echo pass ;;
    fail) echo fail ;;
    missing) echo blocked ;;
    disabled|not_applicable) echo advisory ;;
    *) echo advisory ;;
  esac
}
_status_headmatch() {
  case "$1" in pass|disabled|not_applicable) echo true ;; *) echo false ;; esac
}

# compute_reporter — CONDITIONAL: marker → toggle(reporter.enabled) → file → _test_evidence.
# Reporter delivery-report plan_id is P<num> derived from epic_id (byte-identical to
# fsm_eval_delivery_report_present), so the shared-lib substrate cross-checks 1:1.
compute_reporter() {
  # ── PLAN mode: the plan-final run IS the boundary ────────────────────────
  # There is no `ca-review-complete` marker at the plan boundary (it is an EPIC
  # done-advance marker), and EPIC_ID is empty so the `^E-([0-9]+)` plan-number
  # derivation below has nothing to match. Falling through would return a
  # NON-BLOCKING `not_applicable / not_plan_boundary` at the ONE boundary where the
  # Reporter is mandatory. The authoritative artifact here is the run-scoped
  # protocol-v2 delivery-report.json — never the committed Markdown projection.
  if [[ "${MODE:-epic}" == "plan" ]]; then
    local preport="${EVIDENCE_DIR}/delivery-report.json"
    REPORTER_ARTIFACT="delivery-report.json"
    if [[ ! -f "$preport" ]]; then
      REPORTER_STATUS="missing"
      REPORTER_REASON="delivery-report.json missing in the plan-final run directory (${RUN_ID}) — the Reporter is MANDATORY at the plan boundary"
      return 0
    fi
    if ! _is_json "$preport"; then
      REPORTER_STATUS="fail"
      REPORTER_REASON="delivery-report.json present but empty or unparseable"
      return 0
    fi
    local pir; pir="$(_plan_identity_reason "$preport")"
    if [[ -n "$pir" ]]; then
      REPORTER_STATUS="fail"
      REPORTER_REASON="delivery-report.json is not bound to this plan-final attempt: ${pir}"
      return 0
    fi
    local phead; phead="$(jq -r '.revision.head_sha // ""' "$preport" 2>/dev/null || echo "")"
    if [[ "$phead" != "$CANDIDATE_SHA" ]]; then
      REPORTER_STATUS="fail"
      REPORTER_REASON="delivery-report.json records revision.head_sha '${phead:-<absent>}', expected the frozen candidate '${CANDIDATE_SHA}' — a delivery report for another head is stale"
      return 0
    fi
    REPORTER_STATUS="pass"
    REPORTER_REASON="run-scoped delivery-report.json present, protocol-shaped, bound to plan ${PLAN_ID}, attempt ${RUN_ID} and the frozen candidate"
    return 0
  fi

  local marker="${EVIDENCE_DIR}/ca-review-complete"
  local exec_yaml="${PROJECT_ROOT}/.aid-o/config/execution.yaml"
  local plan_num="" report_plan_id=""
  [[ "$EPIC_ID" =~ ^E-([0-9]+) ]] && plan_num="${BASH_REMATCH[1]}"
  if [[ -z "$plan_num" ]]; then
    REPORTER_STATUS="not_applicable"
    REPORTER_REASON="not_plan_boundary (epic_id carries no plan number)"
    REPORTER_ARTIFACT=".aid-o/reports/delivery.md"
    return 0
  fi
  report_plan_id="P${plan_num}"
  REPORTER_ARTIFACT=".aid-o/reports/${report_plan_id}-delivery.md"
  local report="${PROJECT_ROOT}/.aid-o/reports/${report_plan_id}-delivery.md"

  if [[ ! -f "$marker" ]]; then
    REPORTER_STATUS="not_applicable"; REPORTER_REASON="not_plan_boundary"; return 0
  fi
  local enabled=true
  _aid_read_toggle "$exec_yaml" "reporter" || enabled=false
  if [[ "$enabled" == "false" ]]; then
    REPORTER_STATUS="disabled"; REPORTER_REASON="reporter.enabled:false in execution.yaml"; return 0
  fi
  if [[ ! -f "$report" ]]; then
    REPORTER_STATUS="missing"; REPORTER_REASON="delivery report missing at ${REPORTER_ARTIFACT}"; return 0
  fi
  local valid
  valid="$(_aid_validate_test_evidence "$report" "$EVIDENCE_DIR")"
  if [[ "$valid" == "true" ]]; then
    REPORTER_STATUS="pass"; REPORTER_REASON="delivery report present with >=1 in-tree _test_evidence path on disk"
  else
    REPORTER_STATUS="fail"; REPORTER_REASON="delivery report _test_evidence references no in-tree file on disk"
  fi
}

# compute_simplifier — CONDITIONAL: marker → toggle(simplifier.enabled) → file existence.
# simplifier-report.md has no _test_evidence frontmatter (agents/simplifier.md), so the
# content gate is file existence + non-empty — the existence substrate matches
# fsm_eval_simplifier_present; an empty file is a content 'fail'.
compute_simplifier() {
  # ── PLAN mode: mandatory, same reasoning as compute_reporter ─────────────
  # The `Head:` provenance line is the Simplifier's only subject binding (its report
  # has no JSON envelope), so at the plan boundary it must name the frozen candidate.
  if [[ "${MODE:-epic}" == "plan" ]]; then
    local preport="${EVIDENCE_DIR}/simplifier-report.md"
    SIMPLIFIER_ARTIFACT="simplifier-report.md"
    if [[ ! -f "$preport" ]]; then
      SIMPLIFIER_STATUS="missing"
      SIMPLIFIER_REASON="simplifier-report.md missing in the plan-final run directory (${RUN_ID}) — the Simplifier is MANDATORY at the plan boundary"
      return 0
    fi
    if [[ ! -s "$preport" ]]; then
      SIMPLIFIER_STATUS="fail"
      SIMPLIFIER_REASON="simplifier-report.md present but empty"
      return 0
    fi
    if [[ "$(_markdown_head_match "$preport")" != "true" ]]; then
      SIMPLIFIER_STATUS="fail"
      SIMPLIFIER_REASON="simplifier-report.md has no 'Head: ${CANDIDATE_SHA}' provenance line — the Simplifier's subject is unproven, so it may have read any tree"
      return 0
    fi
    SIMPLIFIER_STATUS="pass"
    SIMPLIFIER_REASON="simplifier-report.md present, non-empty and carrying a Head: provenance line equal to the frozen candidate"
    return 0
  fi

  local marker="${EVIDENCE_DIR}/ca-review-complete"
  local exec_yaml="${PROJECT_ROOT}/.aid-o/config/execution.yaml"
  local report="${EVIDENCE_DIR}/simplifier-report.md"
  SIMPLIFIER_ARTIFACT="simplifier-report.md"

  if [[ ! -f "$marker" ]]; then
    SIMPLIFIER_STATUS="not_applicable"; SIMPLIFIER_REASON="not_plan_boundary"; return 0
  fi
  local enabled=true
  _aid_read_toggle "$exec_yaml" "simplifier" || enabled=false
  if [[ "$enabled" == "false" ]]; then
    SIMPLIFIER_STATUS="disabled"; SIMPLIFIER_REASON="simplifier.enabled:false in execution.yaml"; return 0
  fi
  if [[ ! -f "$report" ]]; then
    SIMPLIFIER_STATUS="missing"; SIMPLIFIER_REASON="simplifier-report.md missing in evidence dir"; return 0
  fi
  if [[ -s "$report" ]]; then
    SIMPLIFIER_STATUS="pass"; SIMPLIFIER_REASON="simplifier-report.md present and non-empty"
  else
    SIMPLIFIER_STATUS="fail"; SIMPLIFIER_REASON="simplifier-report.md present but empty"
  fi
}

# run_verification_input — call aid-evidence-verify.sh --at-head, map to a single verdict.
# Sets VERIFICATION_VERDICT (pass|fail|unverifiable) and VERIFICATION_REASON.
# NEVER crashes: tool exit 2/10/20 → unverifiable+reason; per-check fail → fail (git-dirty
# and --at-head mismatch are `fail`, NOT unverifiable); per-check unverifiable → unverifiable.
#
# TEST-ONLY STUB SEAM (added to fix test-cost blocker during P061 EPIC1 GATES, 2026-07-11):
# the real `aid-evidence-verify.sh --at-head` subprocess costs ~9s per call against a
# non-trivial fixture (real git init + real artifact hashing), which made
# test-release-policy.bats's 78 tests (57 of which build a "healthy" real fixture purely to
# reach a release_ready:true baseline for UNRELATED assertions) take 5-15+ minutes. This seam
# lets bats short-circuit that subprocess call for tests that don't examine verification's own
# behavior. It is double-gated (AID_TEST_MODE=1 AND the stub var set) so it can NEVER activate
# outside a test harness that has explicitly opted in on both counts, and an invalid stub value
# fails loud rather than silently mapping to a pass. Production/default behavior (both unset) is
# byte-for-byte unchanged from before this seam existed — the real subprocess call below is
# untouched.
run_verification_input() {
  VERIFICATION_VERDICT="unverifiable"
  VERIFICATION_REASON="verifier_tool_error harness_unavailable"

  if [[ "${AID_TEST_MODE:-}" == "1" && -n "${AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB:-}" ]]; then
    case "${AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB}" in
      pass)
        VERIFICATION_VERDICT="pass"
        VERIFICATION_REASON="all evidence checks passed at HEAD (stubbed: AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass, AID_TEST_MODE)"
        ;;
      fail)
        VERIFICATION_VERDICT="fail"
        VERIFICATION_REASON="one or more evidence checks failed at HEAD (stubbed: AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=fail, AID_TEST_MODE)"
        ;;
      unverifiable)
        VERIFICATION_VERDICT="unverifiable"
        VERIFICATION_REASON="one or more evidence checks unverifiable (stubbed: AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=unverifiable, AID_TEST_MODE)"
        ;;
      *)
        echo "aid-release-policy: invalid AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB value: '${AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB}' (must be pass|fail|unverifiable)" >&2
        exit 2
        ;;
    esac
    return 0
  fi

  [[ -f "$EVIDENCE_VERIFY" ]] || return 0

  local vr_tmp="" vr_exit=0 worst=""
  vr_tmp="$(mktemp "${TMPDIR:-/tmp}/aid-relpol-vr-XXXXXX.json" 2>/dev/null)" || vr_tmp=""
  [[ -z "$vr_tmp" ]] && { VERIFICATION_REASON="verifier_tool_error mktemp_failed"; return 0; }

  # The verifier resolves its pack as .aid-o/work/evidence/<id>/<run_id>, which is exactly
  # the plan-final run directory's shape when <id> is the plan id — so plan mode passes the
  # PLAN id here rather than an empty EPIC_ID (which would resolve to a non-existent pack
  # and be recorded as `unverifiable`, i.e. a blocker, rather than skipped).
  local _verify_subject="$EPIC_ID"
  [[ "${MODE:-epic}" == "plan" ]] && _verify_subject="$PLAN_ID"
  AID_PROJECT_ROOT="$PROJECT_ROOT" bash "$EVIDENCE_VERIFY" "$_verify_subject" "$RUN_ID" \
    --out "$vr_tmp" --at-head >/dev/null 2>&1 || vr_exit=$?

  case "$vr_exit" in
    2|10|20)
      VERIFICATION_VERDICT="unverifiable"
      VERIFICATION_REASON="verifier_tool_error exit=${vr_exit}"
      ;;
    *)
      if [[ -f "$vr_tmp" ]] && _is_json "$vr_tmp"; then
        worst="$(jq -r '
          [.verification_report.checks[]?.status] as $s
          | if ($s | any(. == "fail")) then "fail"
            elif ($s | any(. == "unverifiable")) then "unverifiable"
            else "pass" end' "$vr_tmp" 2>/dev/null)" || worst=""
        case "$worst" in
          fail)         VERIFICATION_VERDICT="fail";         VERIFICATION_REASON="one or more evidence checks failed at HEAD" ;;
          unverifiable) VERIFICATION_VERDICT="unverifiable"; VERIFICATION_REASON="one or more evidence checks unverifiable" ;;
          pass)         VERIFICATION_VERDICT="pass";         VERIFICATION_REASON="all evidence checks passed at HEAD" ;;
          *)            VERIFICATION_VERDICT="unverifiable"; VERIFICATION_REASON="verifier_tool_error unparseable_report" ;;
        esac
      else
        VERIFICATION_VERDICT="unverifiable"
        VERIFICATION_REASON="verifier_tool_error report_missing (exit=${vr_exit})"
      fi
      ;;
  esac

  rm -f "$vr_tmp" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
_usage_both() {
  echo "Usage (EPIC mode): aid-release-policy.sh <epic_id> <run_id> [--out <path>]" >&2
  echo "Usage (PLAN mode): aid-release-policy.sh --plan <plan_id> --run-id <run_id> --evidence-dir <path> --candidate-sha <sha> --target-ref <ref> --target-head-sha <sha> [--out <path>]" >&2
}

main() {
  # --- Arg parsing (no eval) ---
  local out_path="" _positional=()
  local plan_opt="" run_id_opt="" evidence_dir_opt="" candidate_opt="" target_ref_opt="" target_head_opt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --out requires a path" >&2; exit 2; }
        out_path="$2"; shift 2 ;;
      --plan)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --plan requires a plan id" >&2; _usage_both; exit 2; }
        plan_opt="$2"; shift 2 ;;
      --run-id)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --run-id requires a run id" >&2; _usage_both; exit 2; }
        run_id_opt="$2"; shift 2 ;;
      --evidence-dir)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --evidence-dir requires a path" >&2; _usage_both; exit 2; }
        evidence_dir_opt="$2"; shift 2 ;;
      --candidate-sha)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --candidate-sha requires a sha" >&2; _usage_both; exit 2; }
        candidate_opt="$2"; shift 2 ;;
      --target-ref)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --target-ref requires a ref" >&2; _usage_both; exit 2; }
        target_ref_opt="$2"; shift 2 ;;
      --target-head-sha)
        [[ $# -lt 2 ]] && { echo "aid-release-policy: --target-head-sha requires a sha" >&2; _usage_both; exit 2; }
        target_head_opt="$2"; shift 2 ;;
      -*)
        echo "aid-release-policy: unknown option: $1" >&2
        _usage_both
        exit 2 ;;
      *)
        _positional+=("$1"); shift ;;
    esac
  done

  # --- Mode selection: `--plan` is the ONLY switch. EPIC mode is byte-identical ---
  MODE="epic"
  [[ -n "$plan_opt" ]] && MODE="plan"
  PLAN_ID=""; CANDIDATE_SHA=""; TARGET_REF=""; TARGET_HEAD_SHA=""

  # --- Root resolution (mirror aid-evidence-verify) — shared by both modes ---
  if [[ -n "${AID_PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$AID_PROJECT_ROOT"
  else
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || PROJECT_ROOT="."
  fi

  if [[ "$MODE" == "plan" ]]; then
    if [[ "${#_positional[@]}" -ne 0 ]]; then
      echo "aid-release-policy: plan mode takes no positional arguments (got '${_positional[*]}') — the EPIC positional form and the plan flag form are mutually exclusive" >&2
      _usage_both; exit 2
    fi
    local _m
    for _m in run_id_opt evidence_dir_opt candidate_opt target_ref_opt target_head_opt; do
      if [[ -z "${!_m}" ]]; then
        echo "aid-release-policy: plan mode requires --plan, --run-id, --evidence-dir, --candidate-sha, --target-ref and --target-head-sha (missing --${_m%_opt} / ${_m})" >&2
        _usage_both; exit 2
      fi
    done
    PLAN_ID="$plan_opt"; RUN_ID="$run_id_opt"; EPIC_ID=""
    CANDIDATE_SHA="$candidate_opt"; TARGET_REF="$target_ref_opt"; TARGET_HEAD_SHA="$target_head_opt"
    if [[ ! "$PLAN_ID" =~ ^P[0-9]{3}$ ]]; then
      echo "aid-release-policy: invalid plan id '$PLAN_ID' (must match ^P[0-9]{3}\$)" >&2; exit 2
    fi
    if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "aid-release-policy: invalid RUN_ID '$RUN_ID' (must match [A-Za-z0-9._-]+)" >&2; exit 2
    fi
    command -v jq >/dev/null 2>&1 || {
      echo "aid-release-policy: plan mode requires jq — the identity validation below reads the plan-boundary manifest, and plan mode NEVER degrades to a decision it could not bind." >&2
      exit 1
    }

    # ── Identity validation, BEFORE any evidence read (P064-owned invariant) ──
    local manifest="${PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
    if ! _is_json "$manifest"; then
      echo "aid-release-policy: plan mode: cannot read the plan-boundary manifest at ${manifest#"${PROJECT_ROOT}/"} — plan mode NEVER falls back to EPIC resolution." >&2
      exit 1
    fi
    local m_plan m_run m_cand m_thead m_evdir PLAN_BASE_SHA
    m_plan="$(jq -r '.plan_boundary_manifest.plan_id // ""' "$manifest")"
    m_run="$(jq -r '.plan_boundary_manifest.plan_final_run_id // ""' "$manifest")"
    m_cand="$(jq -r '.plan_boundary_manifest.candidate_sha // ""' "$manifest")"
    m_thead="$(jq -r '.plan_boundary_manifest.target_branch_head_at_candidate_freeze // ""' "$manifest")"
    m_evdir="$(jq -r '.plan_boundary_manifest.plan_final_evidence_dir // ""' "$manifest")"
    PLAN_BASE_SHA="$(jq -r '.plan_boundary_manifest.plan_base_commit // ""' "$manifest")"
    local idfail=""
    [[ "$m_plan"  == "$PLAN_ID" ]]         || idfail="${idfail}manifest plan_id '${m_plan}' != --plan '${PLAN_ID}'; "
    [[ "$m_run"   == "$RUN_ID" ]]          || idfail="${idfail}manifest plan_final_run_id '${m_run}' != --run-id '${RUN_ID}'; "
    [[ "$m_cand"  == "$CANDIDATE_SHA" ]]   || idfail="${idfail}manifest candidate_sha '${m_cand}' != --candidate-sha '${CANDIDATE_SHA}'; "
    [[ "$m_thead" == "$TARGET_HEAD_SHA" ]] || idfail="${idfail}manifest target_branch_head_at_candidate_freeze '${m_thead}' != --target-head-sha '${TARGET_HEAD_SHA}'; "
    # The evidence directory must BE the recorded plan-final run directory. This is what
    # makes "pass an EPIC evidence directory" fail regardless of how complete and valid
    # that EPIC pack is: it is not the directory this plan's manifest recorded.
    local _abs_given _abs_recorded
    case "$evidence_dir_opt" in /*) _abs_given="$evidence_dir_opt" ;; *) _abs_given="${PROJECT_ROOT}/${evidence_dir_opt}" ;; esac
    _abs_given="${_abs_given%/}"
    _abs_recorded="${PROJECT_ROOT}/${m_evdir%/}"
    [[ -n "$m_evdir" && "$_abs_given" == "$_abs_recorded" ]] \
      || idfail="${idfail}--evidence-dir '${evidence_dir_opt}' is not the plan-final run directory recorded in the manifest ('${m_evdir:-<unset>}'); "
    if [[ -n "$idfail" ]]; then
      echo "aid-release-policy: plan mode IDENTITY MISMATCH for ${PLAN_ID}: ${idfail}This is a P064 identity invariant, not a policy-mode question — no decision was produced and no evidence was read." >&2
      exit 1
    fi

    EVIDENCE_DIR="$_abs_recorded"
    # The subject of a plan-final decision is the FROZEN CANDIDATE, not whatever the
    # worktree happens to be at. Every at-HEAD basis helper (_artifact_head_match,
    # _markdown_head_match) compares against CURRENT_HEAD, so binding it to the candidate
    # makes the whole staleness substrate candidate-relative with no per-call branching.
    CURRENT_HEAD="$CANDIDATE_SHA"
  else
    if [[ "${#_positional[@]}" -ne 2 ]]; then
      _usage_both
      exit 2
    fi
    EPIC_ID="${_positional[0]}"
    RUN_ID="${_positional[1]}"
    if [[ ! "$EPIC_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "aid-release-policy: invalid EPIC_ID '$EPIC_ID' (must match [A-Za-z0-9._-]+)" >&2; exit 2
    fi
    if [[ ! "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "aid-release-policy: invalid RUN_ID '$RUN_ID' (must match [A-Za-z0-9._-]+)" >&2; exit 2
    fi
    EVIDENCE_DIR="${PROJECT_ROOT}/.aid-o/work/evidence/${EPIC_ID}/${RUN_ID}"
    CURRENT_HEAD="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || CURRENT_HEAD=""
  fi

  # --- REQUIRED presence rows ---
  check_required_present review_profile        review_profile        "${EVIDENCE_DIR}/review-profile.json"
  check_required_present delivery_gate         delivery_gate         "${EVIDENCE_DIR}/delivery-gate.json"
  check_required_present semantic_review_final semantic_review_final "${EVIDENCE_DIR}/semantic-review-final.json"
  check_required_present acceptance_evidence   acceptance_evidence   "${EVIDENCE_DIR}/acceptance-evidence.json"

  # IMP-464 (D2): C3 consumes the plan AC command/verdict evidence explicitly.
  # It is not interchangeable with a green gate aggregate: a missing or
  # malformed per-criterion record is blocking in plan mode. Whether an
  # honest "skipped" verdict is acceptable depends on whether an AC lens
  # (ac_to_test_identity / requirement_test_drift) is ARMED by this run's
  # review-profile.json required_lenses[] — required_present above already
  # guarantees review-profile.json exists in plan mode.
  if [[ "$MODE" == "plan" ]]; then
    local ac_lens_required_rp="false"
    jq -e '.review_profile.required_lenses // [] | any(. == "ac_to_test_identity" or . == "requirement_test_drift")' \
      "${EVIDENCE_DIR}/review-profile.json" >/dev/null 2>&1 && ac_lens_required_rp="true"
    local pd="${EVIDENCE_DIR}/plan-diff.json" pd_base="" pd_head="" pd_verdict=""
    if [[ ! -s "$pd" ]] || ! _is_json "$pd"; then
      add_input plan_diff "plan-diff.json" "blocked" "plan-diff.json missing or invalid" false
      add_blocker plan_diff "blocking" "plan-diff.json missing or invalid"
    else
      pd_base="$(jq -r '.base_commit // ""' "$pd" 2>/dev/null || true)"
      pd_head="$(jq -r '.head_commit // ""' "$pd" 2>/dev/null || true)"
      pd_verdict="$(jq -r '.overall_verdict // ""' "$pd" 2>/dev/null || true)"
      # aid-plan-diff.sh's OVERALL vocabulary is pass/fail/partial/skipped
      # (present/absent are its PER-AC verdicts, one level down). This check
      # originally required present/absent here — a vocabulary that the
      # producer never emits at this level — so every real plan-diff, verdict
      # "pass" included, was blocked as unbound. Caught by AC4 of the boundary
      # suite once CI's red streak was finally read.
      local pd_verdict_ok=0
      if [[ "$ac_lens_required_rp" == "true" ]]; then
        # an armed AC lens demands a REAL evaluation: pass or fail,
        # never a skipped/partial non-answer
        [[ "$pd_verdict" == "pass" || "$pd_verdict" == "fail" ]] && pd_verdict_ok=1
      else
        case "$pd_verdict" in pass|fail|partial|skipped) pd_verdict_ok=1 ;; esac
      fi
      if [[ "$pd_base" != "$PLAN_BASE_SHA" || "$pd_head" != "$CANDIDATE_SHA" ]] \
         || [[ "$pd_verdict_ok" -ne 1 ]] \
         || ! jq -e '(.results | type == "array") and (.summary | type == "object")' "$pd" >/dev/null 2>&1; then
        add_input plan_diff "plan-diff.json" "blocked" "plan-diff is not a complete verdict for this plan base/candidate" false
        add_blocker plan_diff "blocking" "plan-diff is not bound to the frozen plan candidate"
      else
        # "skipped"/"partial" are legitimate, non-blocking classifications when
        # no AC lens is armed — but neither is a passed AC check, and recording
        # one as verdict "pass" is exactly the silent upgrade the contract
        # forbids. Only a real "pass" verdict is reported as a pass; "fail" is
        # reported as blocked (the blocker below is what actually stops the
        # release, but the row itself must not claim "pass" either).
        local pd_row_verdict="pass"
        case "$pd_verdict" in
          skipped|partial) pd_row_verdict="not_required_skipped" ;;
          fail)            pd_row_verdict="blocked" ;;
        esac
        add_input plan_diff "plan-diff.json" "$pd_row_verdict" "bound plan AC verdict=${pd_verdict} (ac_lens_required=${ac_lens_required_rp})" true
        case "$pd_verdict" in
          pass|skipped|partial) : ;;
          *) add_blocker plan_diff "blocking" "plan-diff reports absent acceptance criteria" ;;
        esac
      fi
    fi
  fi

  # --- gates_report (root, fallback gates/) ---
  local gates_report_path=""
  if [[ -f "${EVIDENCE_DIR}/gates_report.json" ]]; then
    gates_report_path="${EVIDENCE_DIR}/gates_report.json"
  elif [[ -f "${EVIDENCE_DIR}/gates/gates_report.json" ]]; then
    gates_report_path="${EVIDENCE_DIR}/gates/gates_report.json"
  fi
  if [[ -n "$gates_report_path" ]] && _is_json "$gates_report_path"; then
    # gates_report is OUT of evidence-verify's --at-head coverage (contract 1), so a stale stamp
    # is a NET-NEW blocker here: direct compare of the Step-2-stamped .revision.head_sha vs HEAD.
    # No stamp (legacy report) → "unknown" → never blocks (surfaced to the PM brief instead).
    local gates_hm
    gates_hm="$(_artifact_head_match "$gates_report_path" direct)"
    if [[ "$gates_hm" == "false" ]]; then
      add_input gates_report "gates_report.json" "blocked" "gates_report.json stale: revision.head_sha != HEAD (out-of-pack; not covered by --at-head verification)" false
      add_blocker gates_report "blocking" "gates_report.json stale (head_match=false): recorded head_sha != current HEAD"
    else
      add_input gates_report "gates_report.json" "pass" "present at ${gates_report_path#"${EVIDENCE_DIR}/"}" "$gates_hm"
    fi
  else
    add_input gates_report "gates_report.json" "blocked" "gates_report.json missing (checked root and gates/ subdir)" false
    add_blocker gates_report "blocking" "gates_report.json missing (checked root and gates/ subdir)"
  fi

  # --- plan-review (plan_ref hop via epic_input.md frontmatter) ---
  local epic_input="${EVIDENCE_DIR}/epic_input.md"
  local plan_ref plan_review_ok=false plan_review_reason="" plan_review_hm=false
  if [[ "$MODE" == "plan" ]]; then
    # PLAN mode: there is no epic_input.md, so the plan_ref hop has no meaning. The input
    # resolves DIRECTLY to the plan's own C0 review at the canonical path
    # aid-c0-plan-review.sh actually writes (.aid-o/work/evidence/<plan_id>/c0-plan-review.json).
    # The EPIC-mode path this replaces (<evidence>/c0/plan-review.json) is NOT inherited:
    # the C0 producer never writes it, so plan mode would have a permanently-missing REQUIRED
    # input and release_ready could never become true. EPIC mode is untouched.
    local plan_c0="${PROJECT_ROOT}/.aid-o/work/evidence/${PLAN_ID}/c0-plan-review.json"
    if _is_json "$plan_c0"; then
      plan_review_ok=true
      plan_review_reason="present at .aid-o/work/evidence/${PLAN_ID}/c0-plan-review.json (plan-mode: the plan's OWN C0 review)"
      plan_review_hm="$(_artifact_head_match "$plan_c0" ancestry)"
    else
      plan_review_reason="c0-plan-review.json missing at .aid-o/work/evidence/${PLAN_ID}/ — the plan's own C0 review is a REQUIRED input at the plan-final boundary"
    fi
  elif plan_ref="$(_extract_plan_ref "$epic_input")"; [[ -z "$plan_ref" || "$plan_ref" == "null" ]]; then
    plan_review_reason="cannot resolve plan_ref from epic_input.md frontmatter"
  else
    local planref_base planref_id plan_review_file
    planref_base="$(basename "$plan_ref")"
    planref_id="${planref_base%.md}"
    plan_review_file="${PROJECT_ROOT}/.aid-o/work/evidence/${planref_id}/c0/plan-review.json"
    if _is_json "$plan_review_file"; then
      plan_review_ok=true
      plan_review_reason="present at .aid-o/work/evidence/${planref_id}/c0/plan-review.json"
      # ANCESTRY basis (contract 2): a plan-time artifact is stale by construction, so a direct
      # equality check would block EVERY EPIC once HEAD moves. Instead its OWN recorded head_sha
      # must be an ANCESTOR of HEAD (correct lineage). Ancestor → true (stays true through release
      # commits); non-ancestor (rebase/foreign branch) → false; no stamp → "unknown".
      plan_review_hm="$(_artifact_head_match "$plan_review_file" ancestry)"
    else
      plan_review_reason="plan-review.json missing at .aid-o/work/evidence/${planref_id}/c0/"
    fi
  fi
  if [[ "$plan_review_ok" == "true" ]]; then
    if [[ "$plan_review_hm" == "false" ]]; then
      # Present but NOT in HEAD's ancestry → stale/foreign lineage. plan_review is out of
      # evidence-verify coverage (contract 1), so this is a NET-NEW blocker (the F1 class the
      # E-059-2_2 merge review actually hit).
      add_input plan_review "plan-review.json" "blocked" "${plan_review_reason} but STALE: recorded revision.head_sha is not an ancestor of HEAD (rebase/foreign lineage)" false
      add_blocker plan_review "blocking" "plan-review.json stale (head_match=false): recorded head_sha not in HEAD's ancestry"
    else
      add_input plan_review "plan-review.json" "pass" "$plan_review_reason" "$plan_review_hm"
    fi
  else
    add_input plan_review "plan-review.json" "blocked" "$plan_review_reason" false
    add_blocker plan_review "blocking" "$plan_review_reason"
  fi

  # --- verification-report (aid-evidence-verify.sh --at-head) ---
  run_verification_input
  local evidence_verified_at_head=false vr_head_match=false
  [[ "$VERIFICATION_VERDICT" == "pass" ]] && { evidence_verified_at_head=true; vr_head_match=true; }
  add_input verification_report "aid-evidence-verify.sh@--at-head" "$VERIFICATION_VERDICT" "$VERIFICATION_REASON" "$vr_head_match"
  if [[ "$VERIFICATION_VERDICT" != "pass" ]]; then
    add_blocker verification_report "blocking" "verification (--at-head) ${VERIFICATION_VERDICT}: ${VERIFICATION_REASON}"
  fi

  # --- profile-gated curator-report + audit-report (same C3 gate for both) ---
  C3_ACTIVE=false
  _c3_gate_active "$EVIDENCE_DIR" && C3_ACTIVE=true
  process_profile_gated curator_report "${EVIDENCE_DIR}/curator-report.json"
  process_profile_gated audit_report   "${EVIDENCE_DIR}/audit-report.json"

  # --- invalidation-map (ADVISORY — never blocks) ---
  local inv_map="${EVIDENCE_DIR}/invalidation-map.json"
  if _is_json "$inv_map"; then
    add_input invalidation_map "invalidation-map.json" "advisory" "present (advisory)" "$(_artifact_head_match "$inv_map")"
  else
    add_input invalidation_map "invalidation-map.json" "advisory" "advisory-missing (does not block)" true
  fi

  # --- Reporter / Simplifier CONDITIONAL ---
  compute_reporter
  compute_simplifier

  # head_match for our own markdown producers (contract 3): when the CONDITIONAL status is `pass`
  # the report is present+valid, so its at-HEAD basis is the `Head: <sha>` provenance line
  # (mtime NEVER). No provenance → "unknown" (never blocks). For non-pass statuses the status
  # itself drives the row/blocker, so keep the mechanical status→head_match mapping.
  local reporter_hm simplifier_hm reporter_verdict simplifier_verdict
  local reporter_reason_final="$REPORTER_REASON" simplifier_reason_final="$SIMPLIFIER_REASON"
  reporter_verdict="$(_status_to_verdict "$REPORTER_STATUS")"
  simplifier_verdict="$(_status_to_verdict "$SIMPLIFIER_STATUS")"
  if [[ "$REPORTER_STATUS" == "pass" && "$MODE" == "plan" ]]; then
    # Plan mode's Reporter artifact is the run-scoped protocol-v2 JSON, so its at-HEAD
    # basis is the JSON revision stamp, not a Markdown provenance line.
    reporter_hm="$(_artifact_head_match "${EVIDENCE_DIR}/delivery-report.json")"
  elif [[ "$REPORTER_STATUS" == "pass" ]]; then
    reporter_hm="$(_markdown_head_match "${PROJECT_ROOT}/${REPORTER_ARTIFACT}")"
  else
    reporter_hm="$(_status_headmatch "$REPORTER_STATUS")"
  fi
  if [[ "$SIMPLIFIER_STATUS" == "pass" ]]; then
    simplifier_hm="$(_markdown_head_match "${EVIDENCE_DIR}/simplifier-report.md")"
  else
    simplifier_hm="$(_status_headmatch "$SIMPLIFIER_STATUS")"
  fi

  # NET-NEW stale blocking (contract 1): a report that is present+valid (status pass) but provably
  # stale (provenance Head != HEAD → head_match false) must NOT look usable. "unknown" never blocks.
  if [[ "$REPORTER_STATUS" == "pass" && "$reporter_hm" == "false" ]]; then
    reporter_verdict="blocked"
    reporter_reason_final="${REPORTER_REASON}; but STALE: delivery-report provenance Head != HEAD (out-of-pack; not covered by --at-head verification)"
  fi
  if [[ "$SIMPLIFIER_STATUS" == "pass" && "$simplifier_hm" == "false" ]]; then
    simplifier_verdict="blocked"
    simplifier_reason_final="${SIMPLIFIER_REASON}; but STALE: simplifier-report.md provenance Head != HEAD (out-of-pack; not covered by --at-head verification)"
  fi

  add_input reporter    "$REPORTER_ARTIFACT"    "$reporter_verdict"    "$reporter_reason_final"    "$reporter_hm"
  add_input simplifier  "$SIMPLIFIER_ARTIFACT"  "$simplifier_verdict"  "$simplifier_reason_final"  "$simplifier_hm"
  case "$REPORTER_STATUS" in
    missing|fail) add_blocker reporter "blocking" "reporter ${REPORTER_STATUS}: ${REPORTER_REASON}" ;;
    pass) [[ "$reporter_hm" == "false" ]] && add_blocker reporter "blocking" "reporter delivery report stale (head_match=false): provenance Head != HEAD" ;;
  esac
  case "$SIMPLIFIER_STATUS" in
    missing|fail) add_blocker simplifier "blocking" "simplifier ${SIMPLIFIER_STATUS}: ${SIMPLIFIER_REASON}" ;;
    pass) [[ "$simplifier_hm" == "false" ]] && add_blocker simplifier "blocking" "simplifier-report.md stale (head_match=false): provenance Head != HEAD" ;;
  esac

  # --- PLAN mode: the per-EPIC roll-up (one input row + blocker PER EPIC) --------
  # The plan-level delivery-gate.json / acceptance-evidence.json are AGGREGATES; a
  # plan-level green built on a silently-omitted EPIC is exactly the failure this
  # boundary exists to prevent. So every EPIC merged into the plan must (a) still have
  # its per-EPIC evidence directory on disk and (b) be NAMED in both aggregates'
  # sources[]. A missing contribution is a blocker whose input_id NAMES that EPIC
  # (`epic_rollup:<epic_id>`), never a generic aggregate failure.
  PLAN_EPICS_JSON="[]"
  if [[ "$MODE" == "plan" ]]; then
    local manifest_p="${PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
    PLAN_EPICS_JSON="$(jq -c '[.plan_boundary_manifest.epic_runs[]? | {epic_id, run_id, status, evidence_dir, terminal_reason: (.terminal_reason // null)}]' "$manifest_p" 2>/dev/null)" || PLAN_EPICS_JSON="[]"
    [[ -z "$PLAN_EPICS_JSON" ]] && PLAN_EPICS_JSON="[]"
    local dg_srcs="" ae_srcs=""
    if _is_json "${EVIDENCE_DIR}/delivery-gate.json"; then
      dg_srcs="$(jq -r '[(.sources // [])[] | if type == "object" then (.epic_id // "") else . end] | join(" ")' "${EVIDENCE_DIR}/delivery-gate.json" 2>/dev/null || echo "")"
    fi
    if _is_json "${EVIDENCE_DIR}/acceptance-evidence.json"; then
      ae_srcs="$(jq -r '[(.sources // [])[] | if type == "object" then (.epic_id // "") else . end] | join(" ")' "${EVIDENCE_DIR}/acceptance-evidence.json" 2>/dev/null || echo "")"
    fi
    local _eid _edir _reasons
    while IFS=$'\t' read -r _eid _edir; do
      [[ -z "$_eid" ]] && continue
      _reasons=""
      [[ -d "${PROJECT_ROOT}/${_edir}" ]] || _reasons="${_reasons}per-EPIC evidence directory ${_edir} is absent; "
      [[ " ${dg_srcs} " == *" ${_eid} "* ]] || _reasons="${_reasons}not named in the plan-level delivery-gate.json sources[]; "
      [[ " ${ae_srcs} " == *" ${_eid} "* ]] || _reasons="${_reasons}not named in the plan-level acceptance-evidence.json sources[]; "
      if [[ -n "$_reasons" ]]; then
        add_input "epic_rollup:${_eid}" "${_edir}" "blocked" "roll-up contribution missing for ${_eid}: ${_reasons%; }" false
        add_blocker "epic_rollup:${_eid}" "blocking" "the plan-level roll-up is missing ${_eid}'s contribution: ${_reasons%; }"
      else
        add_input "epic_rollup:${_eid}" "${_edir}" "pass" "contribution present on disk and named in both plan-level aggregates" true
      fi
    done < <(jq -r '.[] | select(.status == "merged_to_plan") | [.epic_id, .evidence_dir] | @tsv' <<<"$PLAN_EPICS_JSON" 2>/dev/null)

    # CP2 M2 (2026-07-25): the loop above only sees `merged_to_plan`. Every OTHER
    # entry used to fall through as "skipped" with no reason and no blocker, so an
    # EPIC recorded with a typo'd or unknown status — or still non-terminal at the
    # release boundary — vanished from the completeness check silently. Walk the
    # remaining entries explicitly and classify against the manifest's OWN status
    # vocabulary (lib/aid-plan-manifest.sh _AID_EPIC_STATUS_TRANSITIONS):
    #   abandoned | superseded → legitimately out of the roll-up, reason recorded;
    #   pending | running | blocked → non-terminal at a release boundary → blocker;
    #   anything else → unknown vocabulary → blocker (never a silent skip).
    local _eid2 _est
    while IFS=$'\t' read -r _eid2 _est; do
      [[ -n "$_eid2" ]] || continue
      case "$_est" in
        merged_to_plan) ;;  # handled above
        abandoned|superseded)
          add_input "epic_rollup:${_eid2}" "-" "not_applicable" "EPIC is ${_est}: deliberately outside the plan-level roll-up" true
          ;;
        pending|running|blocked)
          add_input "epic_rollup:${_eid2}" "-" "blocked" "EPIC is still ${_est} at the plan-final boundary — a release candidate cannot be built while an EPIC is non-terminal" false
          add_blocker "epic_rollup:${_eid2}" "blocking" "EPIC ${_eid2} is ${_est}, not terminal — the plan-final roll-up cannot be complete"
          ;;
        *)
          add_input "epic_rollup:${_eid2}" "-" "blocked" "EPIC carries an unrecognised status '${_est}' — outside the manifest status vocabulary" false
          add_blocker "epic_rollup:${_eid2}" "blocking" "EPIC ${_eid2} carries an unrecognised status '${_est}'; a status outside the manifest vocabulary must never silently drop an EPIC from the roll-up"
          ;;
      esac
    done < <(jq -r '.[] | select(.status != "merged_to_plan") | [.epic_id, (.status // "")] | @tsv' <<<"$PLAN_EPICS_JSON" 2>/dev/null)
  fi

  # --- waivers (OPTIONAL) → waivers_applied[] + waiver→input mapping (contract 6) ---
  # A waiver NEVER unblocks: the release_ready tally below reads BLOCKERS_JSON, which the waiver
  # loop never touches, so a mapped blocked→waived flip on the inputs[] ROW leaves the blocker
  # (and release_ready, and the D11 *_status fields) UNCHANGED. The waiver only DOCUMENTS.
  local wf
  for wf in "${EVIDENCE_DIR}"/waiver-*.json; do
    [[ -f "$wf" ]] || continue
    local wbase; wbase="$(basename "$wf")"
    WAIVERS_JSON="$(jq -cn --argjson arr "$WAIVERS_JSON" --arg w "$wbase" '$arr + [$w]')"

    # Resolve the canonical input_id: payload .waiver.waived_check first, then the filename
    # fallback waiver-<input_id>.json.
    local wc="" fromfile="" mapped=""
    if _is_json "$wf"; then
      wc="$(jq -r '.waiver.waived_check // .waiver.scope // ""' "$wf" 2>/dev/null || echo "")"
    fi
    fromfile="${wbase#waiver-}"; fromfile="${fromfile%.json}"
    if _is_canonical_input "$wc"; then
      mapped="$wc"
    elif _is_canonical_input "$fromfile"; then
      mapped="$fromfile"
    fi

    local finding="orphan_waiver" freason=""
    if [[ -n "$mapped" ]]; then
      local cur_verdict
      cur_verdict="$(jq -r --arg id "$mapped" 'first(.[] | select(.id==$id) | .verdict) // "absent"' <<<"$INPUTS_JSON" 2>/dev/null)" || cur_verdict="absent"
      if [[ "$cur_verdict" == "blocked" ]]; then
        # blocked → waived on the inputs[] ROW ONLY (blocker line stays; release_ready unchanged).
        INPUTS_JSON="$(jq -c --arg id "$mapped" --arg w "$wbase" '
          map(if .id == $id and .verdict == "blocked"
              then .verdict = "waived"
                 | .reason = (.reason + " [waived by " + $w + "; blocker retained — a waiver documents, it does not unblock]")
              else . end)' <<<"$INPUTS_JSON")"
        finding="applied"
        freason="waiver mapped to blocked input '${mapped}'; inputs[] row blocked->waived, blocker retained, release_ready unchanged"
      else
        finding="orphan_waiver"
        freason="waiver maps to input '${mapped}' but it is not blocked (verdict=${cur_verdict}); no verdict change"
      fi
    else
      finding="orphan_waiver"
      freason="waiver '${wbase}' has no canonical input mapping (waived_check='${wc}'); no verdict change"
    fi
    WAIVER_FINDINGS_JSON="$(jq -cn --argjson arr "$WAIVER_FINDINGS_JSON" \
      --arg w "$wbase" --arg m "$mapped" --arg f "$finding" --arg r "$freason" \
      '$arr + [{waiver:$w, mapped_input:(if $m=="" then null else $m end), finding:$f, reason:$r}]')"
  done
  local waiver_count
  waiver_count="$(jq 'length' <<<"$WAIVERS_JSON")"

  # --- profile_hash_freshness (review-profile ↔ semantic-review; field optional) ---
  local rp="${EVIDENCE_DIR}/review-profile.json" sr="${EVIDENCE_DIR}/semantic-review-final.json"
  local rp_hash="" sr_hash="" profile_hash_freshness="not_evaluated"
  _is_json "$rp" && rp_hash="$(jq -r '.review_profile.profile_hash // ""' "$rp" 2>/dev/null || echo "")"
  _is_json "$sr" && sr_hash="$(jq -r '.semantic_review.profile_hash // ""' "$sr" 2>/dev/null || echo "")"
  if [[ -z "$rp_hash" || -z "$sr_hash" ]]; then
    profile_hash_freshness="not_evaluated"
  elif [[ "$rp_hash" == "$sr_hash" ]]; then
    profile_hash_freshness="evaluated"
  else
    profile_hash_freshness="mismatch"
  fi

  # --- release_ready + merge_mode ---
  local blocker_count release_ready=false merge_mode
  blocker_count="$(jq 'length' <<<"$BLOCKERS_JSON")"
  if [[ "$blocker_count" -eq 0 && "$evidence_verified_at_head" == "true" ]]; then
    release_ready=true
  fi
  if [[ "$release_ready" == "true" ]]; then
    merge_mode="$(_read_autonomous_mode)"   # auto | manual
  else
    merge_mode="blocked"
  fi

  # --- delivered_summary_ref (epic-summary.md → final_report.md → null) ---
  local dsr="" delivered_summary_ref_json="null"
  if [[ -f "${EVIDENCE_DIR}/epic-summary.md" ]]; then
    dsr="${EVIDENCE_DIR}/epic-summary.md"
  elif [[ -f "${EVIDENCE_DIR}/final_report.md" ]]; then
    dsr="${EVIDENCE_DIR}/final_report.md"
  fi
  if [[ -n "$dsr" ]]; then
    local dsr_rel="${dsr#"${PROJECT_ROOT}/"}"
    delivered_summary_ref_json="$(jq -n --arg p "$dsr_rel" '$p')"
  fi

  # --- summary_for_pm (mechanical template — no LLM) ---
  local summary_for_pm
  summary_for_pm="release_ready=${release_ready}; evidence=${VERIFICATION_VERDICT}; reporter=${REPORTER_STATUS}; simplifier=${SIMPLIFIER_STATUS}; waivers=${waiver_count}; blockers=${blocker_count}; merge_mode=${merge_mode}"
  if [[ "$MODE" == "plan" ]]; then
    summary_for_pm="plan=${PLAN_ID}; run=${RUN_ID}; reviewed_candidate=${CANDIDATE_SHA}; target=${TARGET_REF}@${TARGET_HEAD_SHA}; ${summary_for_pm}"
  fi

  # --- plan_summary (PLAN mode only) — the PM-summary substrate --------------
  # aid-pm-brief.sh renders the PM summary from release-decision.json and NOTHING else
  # (the D6/D9 cycle-break). The plan-level sections roadmap §8 requires — which EPICs
  # ran, what was skipped and why, the plan-final gate result, the specialist review,
  # the four SHA/tag fields — are therefore materialised HERE, from the manifest, so the
  # renderer still reads exactly one file.
  #
  # `final_merge_sha` is null until Step 5 records the main merge, and
  # `release_tag_status` is "not_tagged" until the release step runs. They are DISTINCT
  # fields from reviewed_candidate_sha / approved_target_sha precisely so a PM summary
  # can never imply an intermediate EPIC (or the candidate itself) was released.
  local plan_summary_json="null"
  if [[ "$MODE" == "plan" ]]; then
    local manifest_s="${PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
    local gates_result="unknown"
    if [[ -n "$gates_report_path" ]] && _is_json "$gates_report_path"; then
      gates_result="$(jq -r '(.overall // .gates_report.result // .status // "unknown")' "$gates_report_path" 2>/dev/null || echo unknown)"
    fi
    plan_summary_json="$(jq -n \
      --slurpfile m "$manifest_s" \
      --arg plan "$PLAN_ID" --arg run "$RUN_ID" \
      --arg cand "$CANDIDATE_SHA" --arg tref "$TARGET_REF" --arg thead "$TARGET_HEAD_SHA" \
      --arg gres "$gates_result" --arg gpath "${gates_report_path#"${PROJECT_ROOT}/"}" \
      --argjson epics "$PLAN_EPICS_JSON" '
      ($m[0].plan_boundary_manifest // {}) as $b
      | {
          plan_id: $plan,
          plan_final_run_id: $run,
          reviewed_candidate_sha: $cand,
          approved_target_sha: $thead,
          target_ref: $tref,
          final_merge_sha: ($b.plan_final_merge.merge_commit_sha // $b.merge_commit_sha // null),
          release_tag_status: ($b.plan_final_release.tag_status // "not_tagged"),
          epics: ($epics | map({epic_id, run_id, status, evidence_dir,
                                skipped: ((.status != "merged_to_plan")),
                                reason: (.terminal_reason // null)})),
          plan_final_gates: {report: $gpath, result: $gres,
                             quarantine_substitutes: ($b.quarantine_substitutes // [])},
          specialist_review: ($b.plan_final_review // null),
          remaining_backlog: ($b.plan_final_backlog // [])
        }')" || plan_summary_json="null"
    [[ -z "$plan_summary_json" ]] && plan_summary_json="null"
  fi

  # --- envelope-derived fields ---
  local created_at project_id status verdict_kind verdict_ready head_sha
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  project_id="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null | sed 's|.*[/:]||;s|\.git$||')" || project_id=""
  [[ -z "$project_id" ]] && project_id="$(basename "$PROJECT_ROOT" 2>/dev/null)"
  [[ -z "$project_id" || "$project_id" == "/" || "$project_id" == "." ]] && project_id="unknown"
  if [[ "$release_ready" == "true" ]]; then
    status="pass"; verdict_kind="release_ready"; verdict_ready=true
  else
    status="blocked"; verdict_kind="none"; verdict_ready=false
  fi
  head_sha="${CURRENT_HEAD:-unknown}"

  # --- release_decision payload (built first, for the subject_hash) ---
  local release_decision_payload
  release_decision_payload="$(jq -n \
    --argjson release_ready "$release_ready" \
    --arg decided_by "C4" \
    --argjson inputs "$INPUTS_JSON" \
    --argjson blockers "$BLOCKERS_JSON" \
    --argjson waivers "$WAIVERS_JSON" \
    --argjson waiver_findings "$WAIVER_FINDINGS_JSON" \
    --arg profile_hash_freshness "$profile_hash_freshness" \
    --arg merge_mode "$merge_mode" \
    --argjson pm_brief_required true \
    --arg pm_brief_status "pending" \
    --argjson evidence_verified_at_head "$evidence_verified_at_head" \
    --arg evidence_verification_status "$VERIFICATION_VERDICT" \
    --arg reporter_status "$REPORTER_STATUS" \
    --arg reporter_reason "$REPORTER_REASON" \
    --arg simplifier_status "$SIMPLIFIER_STATUS" \
    --arg simplifier_reason "$SIMPLIFIER_REASON" \
    --argjson delivered_summary_ref "$delivered_summary_ref_json" \
    --arg summary_for_pm "$summary_for_pm" \
    --argjson plan_summary "$plan_summary_json" \
    '{
      release_ready: $release_ready,
      decided_by: $decided_by,
      inputs: $inputs,
      blockers: $blockers,
      waivers_applied: $waivers,
      waiver_findings: $waiver_findings,
      profile_hash_freshness: $profile_hash_freshness,
      merge_mode: $merge_mode,
      pm_brief_required: $pm_brief_required,
      pm_brief_status: $pm_brief_status,
      evidence_verified_at_head: $evidence_verified_at_head,
      evidence_verification_status: $evidence_verification_status,
      reporter_status: $reporter_status,
      reporter_reason: $reporter_reason,
      simplifier_status: $simplifier_status,
      simplifier_reason: $simplifier_reason,
      delivered_summary_ref: $delivered_summary_ref,
      summary_for_pm: $summary_for_pm
    }
    | if $plan_summary == null then . else . + {plan_summary: $plan_summary} end')"

  local payload_hash subject_hash
  payload_hash="$(jq -Sc . <<<"$release_decision_payload" | sha256sum | cut -d' ' -f1 | cut -c1-64)"
  subject_hash="sha256:${payload_hash}"

  # --- full protocol-v2 envelope ---
  # identity: EPIC mode is byte-identical to before. PLAN mode adds plan_id and pins
  # epic_id to null — a plan-final decision belongs to the PLAN, and an epic_id here
  # would make it indistinguishable from a per-EPIC decision (the exact confusion the
  # PM summary must never create).
  local identity_json
  if [[ "$MODE" == "plan" ]]; then
    identity_json="$(jq -cn --arg p "$project_id" --arg plan "$PLAN_ID" --arg r "$RUN_ID" \
      '{project_id:$p, plan_id:$plan, epic_id:null, run_id:$r, step_id:null}')"
  else
    identity_json="$(jq -cn --arg p "$project_id" --arg e "$EPIC_ID" --arg r "$RUN_ID" \
      '{project_id:$p, epic_id:$e, run_id:$r, step_id:null}')"
  fi
  local final_json
  final_json="$(jq -n \
    --argjson identity "$identity_json" \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "release_decision" \
    --arg producer "aid-release-policy.sh@1.0" \
    --arg created_at "$created_at" \
    --arg control_protocol "aid-2.0" \
    --arg project_id "$project_id" \
    --arg epic_id "$EPIC_ID" \
    --arg run_id "$RUN_ID" \
    --arg subject_hash "$subject_hash" \
    --arg head_sha "$head_sha" \
    --arg status "$status" \
    --arg verdict_kind "$verdict_kind" \
    --argjson verdict_ready "$verdict_ready" \
    --argjson release_decision "$release_decision_payload" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: $identity,
      subject: {subject_hash: $subject_hash},
      revision: {head_sha: $head_sha, head_is_current: true, freshness: "current"},
      status: $status,
      verdict: {kind: $verdict_kind, ready: $verdict_ready},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-release-policy.sh"},
      release_decision: $release_decision
    }')"

  # --- write output ---
  local final_out="${out_path:-${EVIDENCE_DIR}/release-decision.json}"
  mkdir -p "$(dirname "$final_out")" 2>/dev/null || true
  printf '%s\n' "$final_json" > "$final_out"

  # --- self-validate against the Step-3 schema (advisory warn; never blocks exit 0) ---
  if [[ -f "$PROTOCOL_VALIDATE" ]]; then
    if ! bash "$PROTOCOL_VALIDATE" "$final_out" >/dev/null 2>&1; then
      echo "aid-release-policy: WARNING: emitted release-decision.json failed protocol validation" >&2
    fi
  fi

  echo "aid-release-policy: wrote $final_out (release_ready=${release_ready}, merge_mode=${merge_mode})" >&2
  exit 0
}

main "$@"
