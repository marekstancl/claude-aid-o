#!/usr/bin/env bash
# aid-audit-tests-finalize.sh — P066 Step 24 (E4 release blocker item 4).
#
# THE single, mandatory production entrypoint for the audit's closing
# chain: consolidate -> render_chat_summary (persists the durable record)
# -> [optional] write-plan bridge check. Before this script existed, that
# chain was described only in commands/aid-audit-tests.md's prose — a
# controller could, in principle, call the chat renderer directly and skip
# the completeness-checked consolidator, or skip persisting the durable
# record entirely. This script IS the enforcement: the controller must
# call THIS script, never the individual Step 14/15/16 functions directly,
# to reach the mandatory final chat turn.
#
# Fails closed at every stage:
#   - consolidate.sh (Step 14 + E3 fix-loop) refuses to run over an
#     incomplete wave set (missing/extra/mismatched artifact vs the
#     dispatch manifest) — no consolidated-findings.json is ever produced,
#     so this script exits non-zero with NO chat text and NO durable record.
#   - render_chat_summary (Step 15) refuses to print a chat verdict if the
#     durable-record persist fails (E4 dogfood-adjacent fix) — no chat text
#     is emitted without the durable record actually landing on disk.
#   - the optional --write-plan bridge check (Step 16) can only ever see
#     {ready:true,...} if a durable record with verdict "remediation
#     recommended" and a schema-valid, hash-matched, non-stale brief all
#     exist — there is no path to {ready:true} without the whole chain
#     above having genuinely succeeded first.
#
# Usage:
#   aid-audit-tests-finalize.sh --audit-id <id> --wave-artifacts-dir <dir> \
#     --dispatch-manifest <path> --output-dir <dir> [--catalog <path>] \
#     [--write-plan]
#
# Prints the 5-part chat text to stdout (the controller's own final turn,
# verbatim). With --write-plan, ALSO prints a second JSON line: the bridge
# check's {ready:...} result.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/aid-test-audit-chat-summary.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-chat-summary.sh"
# shellcheck source=lib/aid-test-audit-write-plan-bridge.sh
source "${SCRIPT_DIR}/lib/aid-test-audit-write-plan-bridge.sh"

_die() { echo "aid-audit-tests-finalize.sh: $2" >&2; exit "$1"; }

audit_id="" wave_artifacts_dir="" dispatch_manifest="" output_dir="" catalog_path="" write_plan="false"
# P072 Step 3 — the audit mode reaches the write-plan bridge so its decision
# gate can apply to `full` only. REQUIRED whenever --write-plan is used: the
# bridge refuses to guess a mode, and so does this script.
audit_mode="" inventory_path="" project_root="" profiles_dir="" profile_selection=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audit-id) [[ $# -ge 2 ]] || _die 2 "--audit-id requires a value"; audit_id="$2"; shift 2 ;;
    --wave-artifacts-dir) [[ $# -ge 2 ]] || _die 2 "--wave-artifacts-dir requires a value"; wave_artifacts_dir="$2"; shift 2 ;;
    --dispatch-manifest) [[ $# -ge 2 ]] || _die 2 "--dispatch-manifest requires a value"; dispatch_manifest="$2"; shift 2 ;;
    --output-dir) [[ $# -ge 2 ]] || _die 2 "--output-dir requires a value"; output_dir="$2"; shift 2 ;;
    --catalog) [[ $# -ge 2 ]] || _die 2 "--catalog requires a value"; catalog_path="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || _die 2 "--mode requires a value"
      case "$2" in
        static|measure|full) audit_mode="$2" ;;
        *) _die 2 "--mode must be static|measure|full (got '$2')" ;;
      esac
      shift 2 ;;
    --inventory) [[ $# -ge 2 ]] || _die 2 "--inventory requires a value"; inventory_path="$2"; shift 2 ;;
    --project-root) [[ $# -ge 2 ]] || _die 2 "--project-root requires a value"; project_root="$2"; shift 2 ;;
    --profiles-dir) [[ $# -ge 2 ]] || _die 2 "--profiles-dir requires a value"; profiles_dir="$2"; shift 2 ;;
    --profile-selection) [[ $# -ge 2 ]] || _die 2 "--profile-selection requires a value"; profile_selection="$2"; shift 2 ;;
    --resource-maps-dir|--pilots-dir) _die 2 "$1 was removed in P078 with the parallelism machinery" ;;
    --write-plan) write_plan="true"; shift ;;
    *) _die 2 "unknown option '$1'" ;;
  esac
done

[[ -n "$audit_id" ]] || _die 2 "--audit-id is required"
[[ -n "$wave_artifacts_dir" ]] || _die 2 "--wave-artifacts-dir is required"
[[ -n "$dispatch_manifest" ]] || _die 2 "--dispatch-manifest is required"
[[ -n "$output_dir" ]] || _die 2 "--output-dir is required"
# Codex review: this was previously checked only at Stage 3, AFTER
# consolidation, durable-record persistence, and printing a seemingly
# successful chat summary — a scripted caller invoking --write-plan without
# --catalog would see completed side effects followed by an argument error.
# Validate every argument combination up front, before any stage runs.
if [[ "$write_plan" == "true" && -z "$catalog_path" ]]; then
  _die 2 "--write-plan requires --catalog"
fi
# --mode is required for EVERY invocation, not only --write-plan: an omitted
# mode used to reach the consolidator as its own `measure` default and the
# renderer as an empty string, which is the same silent downgrade the command
# doc already tells the controller not to perform.
if [[ -z "$audit_mode" ]]; then
  _die 2 "--mode static|measure|full is required (the decision gate applies to full only, and this script never guesses which audit ran)"
fi

# The audit-state record, when present, is what the AUDIT wrote about itself;
# the argument is what whoever is finalizing claims. The record outranks the
# claim, so a full audit cannot be finalized as `measure` to skip the gate.
# A PRESENT state file is authoritative and is treated as such: it is either
# readable, about this audit, and carrying a mode — or finalization refuses.
# The earlier version swallowed jq's failure with `|| true`, so a corrupt
# state produced an empty mode and the guard fell through to the caller's
# claim. An authority that fails open is not an authority; a state file that
# cannot be read is a reason to stop, not a reason to trust the argument.
#
# An ABSENT state file is still allowed: finalize is reachable from fixtures
# and from a resumed audit whose state lives elsewhere. Absence means "no
# corroboration", not "corroborated".
_state_file="${output_dir%/}/audit-state.json"
if [[ -f "$_state_file" ]]; then
  if ! _state_json="$(jq -e '.' "$_state_file" 2>/dev/null)"; then
    _die 2 "audit-state.json at ${_state_file} is present but not valid JSON — refusing to finalize against an unreadable authority (delete it if this audit has no state, rather than leaving a corrupt one)"
  fi
  _recorded_mode="$(jq -r '.mode // empty' <<<"$_state_json")"
  [[ -n "$_recorded_mode" ]] \
    || _die 2 "audit-state.json at ${_state_file} records no .mode — refusing to fall back to the caller's claim"
  case "$_recorded_mode" in
    static|measure|full) ;;
    *) _die 2 "audit-state.json records an unrecognised mode '$_recorded_mode'" ;;
  esac
  _recorded_audit_id="$(jq -r '.audit_id // empty' <<<"$_state_json")"
  [[ -n "$_recorded_audit_id" ]] \
    || _die 2 "audit-state.json at ${_state_file} records no .audit_id — it cannot be shown to belong to this audit"
  [[ "$_recorded_audit_id" == "$audit_id" ]] \
    || _die 2 "audit-state.json belongs to audit '${_recorded_audit_id}', not '${audit_id}' — refusing to finalize against another audit's state"
  [[ "$_recorded_mode" == "$audit_mode" ]] \
    || _die 2 "audit mode mismatch: audit-state.json records '$_recorded_mode', this invocation claims '$audit_mode' — refusing to finalize an audit as a mode it did not run in"
fi
# A full audit owes a decision artifact, and the consolidator cannot build one
# without the inventory (its denominator) and the project root (where the
# unresolved-fraction threshold lives). Validate up front, before Stage 1 runs
# and long before a chat turn is printed: rendering a successful-looking
# summary over an audit that then cannot decide anything is precisely the
# misleading outcome this plan exists to remove.
if [[ "$audit_mode" == "full" ]]; then
  [[ -n "$inventory_path" ]] || _die 2 "--mode full requires --inventory (the consolidator measures coverage against it; it never guesses the denominator)"
  [[ -f "$inventory_path" ]] || _die 2 "--inventory '$inventory_path' does not exist"
  [[ -n "$project_root" ]] || _die 2 "--mode full requires --project-root (the unresolved-fraction threshold is read from that project's test-audit.yaml)"
  [[ -d "$project_root" ]] || _die 2 "--project-root '$project_root' does not exist"
fi

# ─── Profiles ───────────────────────────────────────────────────────────────
#
# A measure or full audit that profiled anything writes its receipts under the
# audit's own output directory. Passing the directory explicitly is allowed;
# when it is not passed, the conventional location is used IF IT EXISTS.
#
# What is deliberately NOT done here: inventing an empty directory so the
# consolidator has something to read. An absent profiles directory means no
# unit was profiled, which is a real and reportable state. A present one that
# fails validation stops the audit inside the consolidator — see
# lib/aid-test-profile-validate.sh.
if [[ -z "$profiles_dir" && "$audit_mode" != "static" ]]; then
  _conventional="${output_dir%/}/profiles"
  [[ -d "$_conventional" ]] && profiles_dir="$_conventional"
fi
# The selection, likewise: conventional location when not named, and it is the
# artifact that makes "this audit skipped its own diagnosis" a hard failure
# rather than a thing a reader would have to notice.
if [[ -z "$profile_selection" && "$audit_mode" != "static" ]]; then
  _conventional_sel="${output_dir%/}/profile-selection.json"
  [[ -f "$_conventional_sel" ]] && profile_selection="$_conventional_sel"
fi
if [[ -n "$profile_selection" ]]; then
  [[ -f "$profile_selection" ]] \
    || _die 2 "--profile-selection '$profile_selection' does not exist"
  [[ "$audit_mode" != "static" ]] \
    || _die 2 "--mode static cannot carry a profile selection: a static audit measures nothing to select from"
fi
if [[ -n "$profiles_dir" ]]; then
  [[ -d "$profiles_dir" ]] \
    || _die 2 "--profiles-dir '$profiles_dir' does not exist — an audit that names a profiles directory must have one"
  [[ "$audit_mode" != "static" ]] \
    || _die 2 "--mode static cannot carry profiles: a static audit runs nothing, so a profiling receipt under it did not come from this audit"
fi

# ─── Stage 1: consolidate (Step 14) — fails closed on any incomplete/
#     mismatched/undeclared wave artifact; produces NO output on failure.
consolidate_args=(
  --audit-id "$audit_id" --wave-artifacts-dir "$wave_artifacts_dir"
  --dispatch-manifest "$dispatch_manifest" --output-dir "$output_dir"
)
# Without these three the consolidator falls back to its own `measure`
# default and never writes decision.json — so a real full audit produced no
# decision at all and --write-plan then failed with decision_artifact_missing.
# The gate was built, tested and unreachable from the production entrypoint.
[[ -n "$audit_mode" ]] && consolidate_args+=(--mode "$audit_mode")
[[ -n "$inventory_path" ]] && consolidate_args+=(--inventory "$inventory_path")
[[ -n "$project_root" ]] && consolidate_args+=(--project-root "$project_root")
# Bound by audit id and by each receipt's evidence-log hash, both re-checked
# inside the consolidator rather than assumed from the path.
[[ -n "$profiles_dir" ]] && consolidate_args+=(--profiles-dir "$profiles_dir")
[[ -n "$profile_selection" ]] && consolidate_args+=(--profile-selection "$profile_selection")

if ! bash "${SCRIPT_DIR}/aid-test-audit-consolidate.sh" "${consolidate_args[@]}" >/dev/null; then
  _die 1 "consolidation failed — refusing to render a chat turn or persist a durable record over an incomplete/invalid audit (no consolidated-findings.json was produced)"
fi

findings_path="${output_dir%/}/consolidated-findings.json"
[[ -f "$findings_path" ]] || _die 1 "internal error: consolidate.sh exited 0 but ${findings_path} does not exist"

# ─── Stage 1b (full mode only): the decision artifact must exist and be
#     readable BEFORE Stage 2 renders a chat turn or persists a durable
#     record. Both of those are outward-facing and effectively irreversible —
#     a user has read the summary, and the record is what a continuation reply
#     resolves against — so discovering a missing or corrupt decision at the
#     bridge, after both have happened, is too late.
#
#     `incomplete` is NOT a failure here and must still be rendered: telling
#     the user what remains unproved is the renderer's job, and the bridge is
#     what refuses the remediation handoff.
if [[ "$audit_mode" == "full" ]]; then
  decision_path="${output_dir%/}/decision.json"
  [[ -f "$decision_path" ]] \
    || _die 1 "full-mode consolidation exited 0 but produced no decision.json — refusing to render a chat turn over an audit that decided nothing"
  # shellcheck source=lib/aid-test-audit-decision.sh
  source "${SCRIPT_DIR}/lib/aid-test-audit-decision.sh"
  if ! aid_test_audit_decision_status "$decision_path" >/dev/null 2>&1; then
    _die 1 "full-mode decision artifact at ${decision_path} does not validate — refusing to render a chat turn or persist a durable record over it"
  fi
  decision_audit_id="$(jq -r '.audit_id // empty' "$decision_path" 2>/dev/null || true)"
  [[ "$decision_audit_id" == "$audit_id" ]] \
    || _die 1 "decision artifact belongs to audit '${decision_audit_id}', not '${audit_id}' — refusing to finalize over a foreign decision"
fi

  # ─── Stage 1c: the evidence reaches the catalog ──────────────────────────
  # Without this the audit proved parallel safety into decision.json and NOTHING
  # carried it into the catalog, which is the file every consumer reads. A
  # freshly proposed catalog therefore came out with every unit `unknown` no
  # matter how much evidence had been gathered, and approving it traded a
  # 27-minute concurrent test run for a 55-minute serial one. The proof existed
  # and had nowhere to go.
  #
  # Advisory on purpose: a catalog that cannot be updated must not sink an
  # otherwise complete audit, and the operator still has to approve whatever
  # comes out. But it is never silent.
  # ─── Stage 1c2: deterministic content scan — mechanical checks, no LLM ───
  # Duplicates, weak oracles, gate overlap, unreferenced files. These sections
  # of the report had no collector: the findings existed exactly once, made by
  # hand after the owner asked where they were. Mechanical work is not left to
  # an analyst's diligence — the same lesson as the whole abstention problem.
  if ! bash "${SCRIPT_DIR}/aid-test-content-scan.sh" \
       --project-root "${project_root:-.}" \
       --inventory "${output_dir%/}/inventory.json" \
       --catalog "${project_root:-.}/.aid-o/config/test-catalog.yaml" \
       --output "${output_dir%/}/content-scan.json" >/dev/null 2>&2; then
    echo "WARN: aid-audit-tests-finalize.sh: content scan failed — the report's quality and overlap sections will say so instead of standing empty" >&2
  fi

  # ─── Stage 1d: the report page — the ONE fixed-form output ───────────────
  # Four days of fragments taught the lesson: the owner gets one page, all
  # nine sections, every time. A failure here is loud but does not kill the
  # audit — the decision artifact already exists, and a presentation bug must
  # never eat a completed audit again.
  if ! bash "${SCRIPT_DIR}/aid-test-audit-report.sh" \
       --audit-dir "$output_dir" --project-root "${project_root:-.}" >/dev/null 2>&2; then
    echo "WARN: aid-audit-tests-finalize.sh: report.html could not be generated — the audit stands, but the fixed-form page is missing; run aid-test-audit-report.sh by hand and report the error" >&2
  fi

# ─── Stage 2: render the mandatory chat summary (Step 15) — persists the
#     durable record as a side effect; fails closed if that persist fails.
# "" for $2 keeps the renderer's own default changed_text (it uses :- so an
# empty string falls back); the mode is $3.
# $4 is the decision artifact: in full mode the renderer must let
# `audit_status: incomplete` outrank whatever the findings happen to say.
chat_text="$(aid_test_audit_render_chat_summary "$findings_path" "" "$audit_mode" "${decision_path:-}")" \
  || _die 1 "chat summary render failed — no durable record, no chat turn: ${chat_text}"

printf '%s\n' "$chat_text"

# ─── Stage 3 (optional): the write-plan bridge check — same-conversation
#     continuation and --write-plan both resolve to this identical call.
if [[ "$write_plan" == "true" ]]; then
  bridge_result="$(aid_test_audit_write_plan_bridge_check "$output_dir" "$catalog_path" "$audit_mode")"
  printf '%s\n' "$bridge_result"
fi
