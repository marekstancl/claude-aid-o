#!/usr/bin/env bash
# aid-pm-brief.sh — deterministic PM decision brief from a C4 release-decision (E-059-2_2 Step 6).
#
# PURE bash/jq — NO LLM. Reads exactly ONE evidence input: <evidence_dir>/release-decision.json
# (the protocol-v2 `release_decision` artifact emitted by aid-release-policy.sh, Step 4). From it,
# and ONLY it, this script emits the PM machine handoff:
#
#   pm-decision-brief.json  — protocol-v2 `pm_decision_brief` artifact that ECHOES the decision's
#                             release_ready + blockers + waivers_applied + the D11 state fields
#                             (merge_mode, evidence_verification_status, evidence_verified_at_head,
#                             reporter_status/reason, simplifier_status/reason, summary_for_pm,
#                             delivered_summary_ref). Validates against pm-decision-brief.schema.json
#                             via aid-protocol-validate.sh (exit 0) for a complete decision.
#   pm-summary.md           — human template rendered from the same fields. Mechanical honesty:
#                             it legibly shows evidence/Reporter/Simplifier/waiver status even in an
#                             auto-merge run, so an auto-merge is never silent.
#
# CYCLE-BREAK (D6/D9): the brief is derived deterministically from release-decision.json and NOTHING
# else. It reads NO sibling evidence files — not epic-summary.md, not final_report.md, not gates.
# `delivered_summary_ref` is an ALREADY-RESOLVED path inside release-decision.json (the aggregator
# resolved it in Step 4); this script only ECHOES that string — it never opens or re-derives it.
#
# PATCH-BACK (D11) — the SINGLE, named exception to "the brief only reads": after successfully
# writing both output files, this script does one idempotent `jq` patch of the `pm_brief_status`
# field BACK into release-decision.json (mechanical, no LLM, one field, no further evidence reads):
#     generated  — brief written AND faithfully echoes a complete decision
#     failed     — brief could not be written (see --out-dir seam below)
#     incomplete — decision missing required state, or the echo self-check found an inconsistency
# `failed` is reachable ONLY for the write-failure class. A wholesale read-only evidence_dir blocks
# the patch-back itself, so the field stays `pending` — a KNOWN, NAMED limit: `pending` observed
# after a completed done-advance is itself a failure signal (the brief step never ran to completion).
#
# TEST SEAM: --out-dir <path> overrides where the two brief files are written (pattern mirrors
# `--out` on aid-release-policy.sh). The patch-back ALWAYS targets <evidence_dir>/release-decision.json
# regardless of --out-dir. A test points --out-dir at a non-writable dir while the evidence dir stays
# writable → the brief write fails but the patch-back succeeds, writing `failed`.
#
# HONEST LIMITATION (AID-v3-principles §1): this generator DETECTS and RECORDS state; it does not
# ENFORCE anything. Nothing here (or in aid-fsm.sh) blocks a merge that lacks a brief — "auto-merge
# never silent" is an E9 pipeline convention, not a structural guarantee. Enforcement (--validate
# gating MERGE) is deferred to E10. E9 delivers the field + generator + patch-back only.
#
# Usage:
#   aid-pm-brief.sh <evidence_dir> [--out-dir <path>]     # generate brief (+ patch-back)
#   aid-pm-brief.sh <evidence_dir> [--out-dir <path>] --validate
#                                                         # verify an existing brief echoes decision
#
# Exit codes:
#   0  — brief generated; communication_status: complete; pm_brief_status → generated
#   2  — usage error
#   3  — --validate: release-decision.json missing/unparseable
#   4  — --validate: pm-decision-brief.json missing/unparseable
#   5  — --validate: brief does NOT faithfully echo the decision (optimism/tamper caught)
#   6  — generate: brief write failed; pm_brief_status → failed (if decision writable)
#   7  — generate: incomplete (decision missing/malformed, or echo self-check inconsistent);
#                  pm_brief_status → incomplete (if decision writable, else stays pending)
#
# NOTE (D6/D11): patching pm_brief_status leaves the decision's stored subject_hash technically
# stale relative to the mutated payload. This is intentional and inconsequential — pm_brief_status
# is a required-mutable D11 field; nothing re-derives the decision's subject_hash (the FSM dual-run
# hook re-runs the aggregator fresh, the protocol validator checks subject_hash FORMAT only). We
# patch the ONE field per the design contract, no more.

set -uo pipefail

# ---------------------------------------------------------------------------
# The 12 fields the brief ECHOES from release_decision (single source of truth,
# shared by the payload builder + both echo-consistency checks so they never drift).
# communication_status + human_summary_path are brief-specific, NOT echoes.
# ---------------------------------------------------------------------------
ECHO_FIELDS_JSON='["release_ready","blockers","waivers_applied","merge_mode","evidence_verification_status","evidence_verified_at_head","reporter_status","reporter_reason","simplifier_status","simplifier_reason","summary_for_pm","delivered_summary_ref"]'

usage() {
  echo "Usage: aid-pm-brief.sh <evidence_dir> [--out-dir <path>] [--validate]" >&2
}

# _is_json <file> — present, non-empty AND parseable JSON (fail-closed presence+parse gate).
_is_json() {
  local f="$1"
  [[ -s "$f" ]] || return 1                              # missing OR 0-byte → fail-closed (was -f: accepts empty)
  command -v jq >/dev/null 2>&1 || return 0              # no jq → presence-only (unchanged)
  [[ -n "$(jq -c . "$f" 2>/dev/null)" ]] && jq -e . "$f" >/dev/null 2>&1
}

# decision_complete <decision_file> — 0 iff release_decision is an object carrying release_ready
# (boolean) plus all remaining echoed fields present. Drives communication_status + patch-back.
decision_complete() {
  local decision="$1" res=""
  _is_json "$decision" || return 1
  res="$(jq -r '
    (.release_decision) as $r
    | if ($r | type) != "object" then "no"
      elif ($r.release_ready | type) != "boolean" then "no"
      elif (["blockers","waivers_applied","merge_mode","evidence_verification_status",
             "evidence_verified_at_head","reporter_status","reporter_reason",
             "simplifier_status","simplifier_reason","summary_for_pm","delivered_summary_ref"]
            | all(. as $k | ($r | has($k)))) then "yes"
      else "no" end
  ' "$decision" 2>/dev/null)" || res="no"
  [[ "$res" == "yes" ]]
}

# build_brief_payload <decision_file> <comm_status> <human_path> — prints the pm_decision_brief
# payload object. Echoes release_decision faithfully; defaults ONLY fill in a schema-valid
# placeholder when the decision is missing/malformed (that run is flagged communication_status:
# incomplete anyway, so the defaults never masquerade as real state).
build_brief_payload() {
  local decision="$1" comm="$2" human="$3" rd_input="null"
  if _is_json "$decision"; then
    rd_input="$(jq -c '.release_decision // null' "$decision" 2>/dev/null || echo null)"
  fi
  jq -cn --argjson rd "$rd_input" --arg comm "$comm" --arg human "$human" '
    ($rd // {}) as $r
    | {
        communication_status: $comm,
        release_ready: ($r.release_ready // false),
        blockers: ($r.blockers // []),
        waivers_applied: ($r.waivers_applied // []),
        human_summary_path: $human,
        merge_mode: ($r.merge_mode // "blocked"),
        evidence_verification_status: ($r.evidence_verification_status // "unverifiable"),
        evidence_verified_at_head: ($r.evidence_verified_at_head // false),
        reporter_status: ($r.reporter_status // "missing"),
        reporter_reason: ($r.reporter_reason // "release-decision.json missing or malformed — reporter status unavailable"),
        simplifier_status: ($r.simplifier_status // "missing"),
        simplifier_reason: ($r.simplifier_reason // "release-decision.json missing or malformed — simplifier status unavailable"),
        summary_for_pm: ($r.summary_for_pm // "PM brief incomplete: release-decision.json missing or malformed in evidence dir."),
        delivered_summary_ref: ($r.delivered_summary_ref // null)
      }'
}

# emit_full_brief <payload> <decision_file> <comm_status> <out_json> — wraps the payload in the
# protocol-v2 envelope and writes it. Returns non-zero iff the write fails (the redirect is the
# LAST statement, so its status is the function's status → write-failure is detectable).
emit_full_brief() {
  local payload="$1" decision="$2" comm="$3" out_json="$4"
  local created_at status ph subject_hash id_input="null" rev_input="null"
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if [[ "$comm" == "complete" ]]; then status="pass"; else status="fail"; fi
  ph="$(printf '%s' "$payload" | jq -Sc . 2>/dev/null | sha256sum | cut -d' ' -f1 | cut -c1-64)"
  subject_hash="sha256:${ph}"
  if _is_json "$decision"; then
    id_input="$(jq -c '.identity // null' "$decision" 2>/dev/null || echo null)"
    rev_input="$(jq -c '.revision // null' "$decision" 2>/dev/null || echo null)"
  fi
  jq -n \
    --arg schema_version "aid-2.0" \
    --arg artifact_type "pm_decision_brief" \
    --arg producer "aid-pm-brief.sh@1.0" \
    --arg created_at "$created_at" \
    --arg control_protocol "aid-2.0" \
    --arg subject_hash "$subject_hash" \
    --arg status "$status" \
    --argjson id "$id_input" \
    --argjson rev "$rev_input" \
    --argjson payload "$payload" \
    '{
      schema_version: $schema_version,
      artifact_type: $artifact_type,
      producer: $producer,
      created_at: $created_at,
      control_protocol: $control_protocol,
      identity: {
        project_id: (($id.project_id // "unknown") | if (. | type) == "string" and (. | length) > 0 then . else "unknown" end),
        epic_id: ($id.epic_id // null),
        run_id: ($id.run_id // null),
        step_id: null
      },
      subject: {subject_hash: $subject_hash},
      revision: {
        head_sha: (($rev.head_sha // "unknown") | tostring),
        head_is_current: ($rev.head_is_current // false),
        freshness: (($rev.freshness // "stale") | tostring)
      },
      status: $status,
      verdict: {kind: "none", ready: false},
      provenance: {dispatch_mode: "deterministic", generated_by_tool: "aid-pm-brief.sh"},
      pm_decision_brief: $payload
    }' > "$out_json"
}

# build_brief_md <decision_file> <comm_status> — prints the human pm-summary.md. Reads ONLY the
# decision file. Always shows evidence/Reporter/Simplifier/blocker/waiver status (mechanical
# honesty); adds an explicit auto-merge-never-silent note when merge_mode == auto.
build_brief_md() {
  local decision="$1" comm="$2" rd_input="null" id_input="null"
  if _is_json "$decision"; then
    rd_input="$(jq -c '.release_decision // null' "$decision" 2>/dev/null || echo null)"
    id_input="$(jq -c '.identity // null' "$decision" 2>/dev/null || echo null)"
  fi
  jq -rn --argjson rd "$rd_input" --argjson id "$id_input" --arg comm "$comm" '
    def yn(b): if b == true then "yes" elif b == false then "no" else "unknown" end;
    ($rd // {}) as $r
    | ($id // {}) as $i
    | ([
        "# PM Decision Brief" + (if (($i.epic_id // "") | tostring) != "" then " — " + ($i.epic_id | tostring) else "" end),
        "",
        "> Communication status: **" + $comm + "** — deterministic brief generated by `aid-pm-brief.sh` from `release-decision.json` (no LLM).",
        "> Canonical machine artifact: `pm-decision-brief.json` (protocol-v2 `pm_decision_brief`); this human summary echoes it 1:1.",
        "",
        "## Release readiness",
        "",
        "- **Release ready:** " + yn($r.release_ready),
        "- **Merge mode:** " + (($r.merge_mode // "unknown") | tostring),
        "- **Evidence verification:** " + (($r.evidence_verification_status // "unknown") | tostring) + " (verified at HEAD: " + yn($r.evidence_verified_at_head) + ")"
      ]
      + (if (($r.merge_mode // "") | tostring) == "auto" then
          [ "",
            "> **Auto-merge run.** This brief is generated after EVERY successful done-advance, INCLUDING",
            "> auto-merge / FIRST AID mode — the review signals below are shown in full so an auto-merge is",
            "> never silent. (E9 convention; structural enforcement of \"no merge without a brief\" is deferred to E10.)" ]
        else [] end)
      + [
          "",
          "## Review signals",
          "",
          "- **Reporter:** " + (($r.reporter_status // "unknown") | tostring) + " — " + (($r.reporter_reason // "") | tostring),
          "- **Simplifier:** " + (($r.simplifier_status // "unknown") | tostring) + " — " + (($r.simplifier_reason // "") | tostring),
          "",
          "## At-HEAD verification warnings",
          ""
        ]
      + (( ($r.inputs // [])
           | map(select((.head_match == "unknown")
                        and (.verdict != "advisory") and (.verdict != "not_applicable"))) ) as $unk
         | if ($unk | length) == 0 then [ "_All gating inputs verified at HEAD (no unknown head_match)._" ]
           else ($unk | map("- **" + ((.id // "?") | tostring)
                             + "** — head_match could not be verified (unknown): "
                             + ((.reason // "") | tostring)))
           end)
      + [
          "",
          "## Blockers",
          ""
        ]
      + (if (($r.blockers // []) | length) == 0 then [ "_None._" ]
         else ($r.blockers | map("- **" + ((.input_id // "?") | tostring) + "** (" + ((.severity // "?") | tostring) + ") — " + ((.reason // "") | tostring)))
         end)
      + [
          "",
          "## Waivers applied",
          ""
        ]
      + (if (($r.waivers_applied // []) | length) == 0 then [ "_None._" ]
         else ($r.waivers_applied | map("- `" + (. | tostring) + "`"))
         end)
      + [
          "",
          "## What was delivered",
          "",
          (if ($r.delivered_summary_ref // null) == null
             then "_No delivered-summary reference recorded (delivered_summary_ref: null)._"
             else "Delivered summary reference (echoed from release-decision, not re-derived): `" + ($r.delivered_summary_ref | tostring) + "`" end),
          "",
          "## Summary for PM",
          "",
          (($r.summary_for_pm // "_No summary available._") | tostring),
          "",
          "---",
          "_Generated by `aid-pm-brief.sh` from `release-decision.json` only. Deterministic, no LLM, no sibling-file reads._"
        ])
    | join("\n")
  '
}

# echo_consistent_files <brief_file> <decision_file> — 0 iff the on-disk brief echoes the decision
# for all 12 echoed fields. Used by --validate (catches post-hoc optimism/tampering).
echo_consistent_files() {
  local brief="$1" decision="$2" res=""
  res="$(jq -n --argjson keys "$ECHO_FIELDS_JSON" \
    --slurpfile b "$brief" --slurpfile d "$decision" '
    ($b[0].pm_decision_brief // {}) as $pb
    | ($d[0].release_decision // {}) as $rd
    | ($keys | map($pb[.] == $rd[.]) | all)
  ' 2>/dev/null)" || res="false"
  [[ "$res" == "true" ]]
}

# echo_consistent_payload <payload_string> <decision_file> — same check against the in-memory
# payload (generation self-check — no brief-file read, keeps generation reading ONLY the decision).
echo_consistent_payload() {
  local payload="$1" decision="$2" res=""
  res="$(jq -n --argjson keys "$ECHO_FIELDS_JSON" \
    --argjson pb "$payload" --slurpfile d "$decision" '
    ($d[0].release_decision // {}) as $rd
    | ($keys | map($pb[.] == $rd[.]) | all)
  ' 2>/dev/null)" || res="false"
  [[ "$res" == "true" ]]
}

# patch_back <decision_file> <status> — idempotent one-field jq patch of pm_brief_status. Returns
# non-zero (leaving the field untouched → stays pending) if the decision is unwritable/unparseable.
patch_back() {
  local decision="$1" newstatus="$2" tmp=""
  _is_json "$decision" || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/aid-pmbrief-patch-XXXXXX.json" 2>/dev/null)" || return 1
  if jq --arg s "$newstatus" '.release_decision.pm_brief_status = $s' "$decision" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$decision" 2>/dev/null && return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local evidence_dir="" out_dir="" validate=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out-dir)
        [[ $# -lt 2 ]] && { echo "aid-pm-brief: --out-dir requires a path" >&2; usage; exit 2; }
        out_dir="$2"; shift 2 ;;
      --validate) validate=1; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "aid-pm-brief: unknown option: $1" >&2; usage; exit 2 ;;
      *)
        if [[ -z "$evidence_dir" ]]; then evidence_dir="$1"; shift
        else echo "aid-pm-brief: unexpected argument: $1" >&2; usage; exit 2; fi ;;
    esac
  done
  if [[ -z "$evidence_dir" ]]; then usage; exit 2; fi
  if ! command -v jq >/dev/null 2>&1; then echo "aid-pm-brief: jq not found in PATH" >&2; exit 2; fi

  [[ -z "$out_dir" ]] && out_dir="$evidence_dir"
  local decision="${evidence_dir}/release-decision.json"
  local brief_json="${out_dir}/pm-decision-brief.json"
  local brief_md="${out_dir}/pm-summary.md"

  # --- validate mode: compare an existing brief against the decision (no generation) ---
  if [[ "$validate" -eq 1 ]]; then
    if ! _is_json "$decision"; then
      echo "aid-pm-brief: --validate: release-decision.json missing or unparseable at $decision" >&2; exit 3
    fi
    if ! _is_json "$brief_json"; then
      echo "aid-pm-brief: --validate: pm-decision-brief.json missing or unparseable at $brief_json" >&2; exit 4
    fi
    if echo_consistent_files "$brief_json" "$decision"; then
      echo "aid-pm-brief: --validate OK — brief faithfully echoes release-decision"
      exit 0
    fi
    echo "aid-pm-brief: --validate FAIL — brief does not faithfully echo release-decision (optimism/tamper)" >&2
    exit 5
  fi

  # --- generation mode ---
  local comm="incomplete"
  if _is_json "$decision" && decision_complete "$decision"; then comm="complete"; fi

  mkdir -p "$out_dir" 2>/dev/null || true

  local payload write_failed=false
  payload="$(build_brief_payload "$decision" "$comm" "pm-summary.md")"

  emit_full_brief "$payload" "$decision" "$comm" "$brief_json" || write_failed=true
  build_brief_md "$decision" "$comm" > "$brief_md" 2>/dev/null || write_failed=true

  if [[ "$write_failed" == "true" ]]; then
    patch_back "$decision" "failed" || true
    echo "aid-pm-brief: ERROR — failed to write brief to $out_dir (pm_brief_status=failed)" >&2
    exit 6
  fi

  # Write succeeded → decide generated vs incomplete and patch pm_brief_status back.
  if [[ "$comm" == "complete" ]] && echo_consistent_payload "$payload" "$decision"; then
    patch_back "$decision" "generated" || true   # RO decision dir → stays pending (named limit)
    echo "aid-pm-brief: wrote $brief_json + $brief_md (communication_status=complete, pm_brief_status=generated)" >&2
    exit 0
  fi

  patch_back "$decision" "incomplete" || true
  echo "aid-pm-brief: wrote $brief_json + $brief_md (communication_status=incomplete, pm_brief_status=incomplete)" >&2
  exit 7
}

main "$@"
