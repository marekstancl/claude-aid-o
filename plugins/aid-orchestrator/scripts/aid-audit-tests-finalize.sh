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
audit_mode=""
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
if [[ "$write_plan" == "true" && -z "$audit_mode" ]]; then
  _die 2 "--write-plan requires --mode static|measure|full (the decision gate applies to full only, and this script never guesses which audit ran)"
fi

# ─── Stage 1: consolidate (Step 14) — fails closed on any incomplete/
#     mismatched/undeclared wave artifact; produces NO output on failure.
if ! bash "${SCRIPT_DIR}/aid-test-audit-consolidate.sh" \
    --audit-id "$audit_id" --wave-artifacts-dir "$wave_artifacts_dir" \
    --dispatch-manifest "$dispatch_manifest" --output-dir "$output_dir" >/dev/null; then
  _die 1 "consolidation failed — refusing to render a chat turn or persist a durable record over an incomplete/invalid audit (no consolidated-findings.json was produced)"
fi

findings_path="${output_dir%/}/consolidated-findings.json"
[[ -f "$findings_path" ]] || _die 1 "internal error: consolidate.sh exited 0 but ${findings_path} does not exist"

# ─── Stage 2: render the mandatory chat summary (Step 15) — persists the
#     durable record as a side effect; fails closed if that persist fails.
# "" for $2 keeps the renderer's own default changed_text (it uses :- so an
# empty string falls back); the mode is $3.
chat_text="$(aid_test_audit_render_chat_summary "$findings_path" "" "$audit_mode")" \
  || _die 1 "chat summary render failed — no durable record, no chat turn: ${chat_text}"

printf '%s\n' "$chat_text"

# ─── Stage 3 (optional): the write-plan bridge check — same-conversation
#     continuation and --write-plan both resolve to this identical call.
if [[ "$write_plan" == "true" ]]; then
  bridge_result="$(aid_test_audit_write_plan_bridge_check "$output_dir" "$catalog_path" "$audit_mode")"
  printf '%s\n' "$bridge_result"
fi
