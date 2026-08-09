#!/usr/bin/env bash
# =============================================================================
# aid-recovery-adjudicate.sh — CODEX RECOVERY ADJUDICATION (P076 EPIC 2, Step 12)
#
# Provides (sourced, never executed):
#   aid_recovery_adjudicate <run_evidence_dir> <stop_class> <facts_file>
#
# ── THE SPECIFICATION (moved here verbatim from commands/aid-run.md) ────────
# Until this file existed, `commands/aid-run.md` carried the rule as prose, as
# an explicitly TEMPORARY dispatch convention:
#
#   "Until a dedicated adjudicator command is available, use the existing
#    isolated Codex transport. Give it only: verified facts, current FSM state,
#    attempted recoveries, an explicit allowlist of reversible in-scope actions,
#    and forbidden authority-expanding actions. Require one selected action plus
#    a short rationale and risk note. Reject an answer outside the allowlist,
#    append the accepted decision and evidence paths to `timeline.jsonl`, and
#    continue."
#
# This file is that convention codified — not redesigned. The paragraph in
# aid-run.md now points here, because a convention that only a reader can
# follow is enforced by nobody.
#
# ── THE AUTHORITY CEILING, ENFORCED BY CONSTRUCTION ─────────────────────────
# aid-run.md's own contract: "The adjudicator may choose among already-authorized
# technical recovery paths; it cannot grant PM authority or waive security risk."
#
# That ceiling is NOT implemented by asking Codex nicely. It is implemented by
# the shape of this function:
#
#   1. The set of actions this function can ever return is the class's
#      `allowed_actions` list read out of `defaults/policies/auto-recovery.yaml`.
#      The reply does not contribute to that set — it can only SELECT from it.
#   2. The validator compares the reply's action token against that list with
#      an exact string match. Everything else — an unknown token, a token from
#      a different class, two tokens, no token at all, prose asking for a
#      waiver, an override request, silence — returns `escalate`.
#   3. `escalate` is not an action. It is not in the vocabulary, no caller can
#      execute it, and it is the ONLY other thing this function can print.
#
# So a compromised, confused or hostile adjudicator cannot widen its own remit:
# the widest thing it can say is "one of the actions the policy already
# authorised for this class", and anything wider is mechanically not an answer.
# `test-recovery-adjudicate.bats` proves this against a reply that explicitly
# demands PM authority.
#
# ── FAIL-CLOSED PATHS (every one of these ends at `escalate`) ───────────────
#   • missing / unreadable run evidence dir, or a non-appendable timeline
#   • missing, unreadable or EMPTY facts file  (an adjudication without facts
#     is theater — refused BEFORE any dispatch)
#   • unreadable policy, missing yq/jq, unknown stop class → treated as
#     UNCLASSIFIED, whose allowlist is empty by policy
#   • an EMPTY allowlist (UNCLASSIFIED, REVIEW_EXHAUSTED) → short-circuits to
#     `escalate` WITHOUT dispatching at all
#   • transport unavailable / non-zero / absent function → `escalate` with the
#     transport error attached to the artifact
#   • a reply that is empty, ambiguous (two action tokens), rationale-less, or
#     out of allowlist → ONE retry with the rejection quoted back, then
#     `escalate`
# Nothing here can end at an action except a single, in-allowlist, rationale-
# bearing reply. Silence, emptiness and ambiguity are never consent.
#
# ── TRANSPORT ───────────────────────────────────────────────────────────────
# `_run_codex_isolated` from `aid-c3-dispatch.sh` — the SAME isolated transport
# the C3 bridge and the C0 plan review use, reused by `source`, never
# reimplemented. Sourcing it is safe: its bottom guard
# (`BASH_SOURCE[0] == $0`) means only definitions are pulled in.
#
# ── AUDIT ───────────────────────────────────────────────────────────────────
# Every exchange — including the refusals that never dispatch — writes
#   <run_evidence_dir>/recovery-adjudication-<ts>-<attempt>.json
# carrying prompt hash, prompt path, raw reply, verdict and transport error,
# plus the rendered prompt beside it as `.prompt.md`. An adjudication with no
# record did not happen.
#
# DIVERGENCE FROM THE PLAN TEXT — stated, not silently applied: the plan names
# the artifact `recovery-adjudication-<ts>.json`. A retry is a SECOND exchange
# in the same second, so the attempt number is part of the name; otherwise the
# retry would overwrite the rejected exchange that justifies it, and the audit
# trail would lose exactly the record that matters.
#
# The accepted decision (and the refusals) are appended to
# `<run_evidence_dir>/timeline.jsonl` and to the ladder record
# `<run_evidence_dir>/recovery-ladder.jsonl`. The ladder lib (next step of this
# EPIC) owns that file's writer; if it is already sourced, its
# `aid_recovery_ladder_append` is used instead of the local append.
#
# Output:  the selected action on stdout (one of the class's allowed actions),
#          or the literal `escalate`.
# Returns: 0 when an action was selected, 3 for `escalate` (not a crash — a
#          verdict), 2 for a usage error. A caller that ignores the exit code
#          still cannot act on `escalate`: it is not an executable action name.
#
# Environment (optional):
#   AID_RECOVERY_POLICY  — path to the effective recovery policy (test seam;
#                          default: the shipped defaults/policies/auto-recovery.yaml).
#                          The project-override resolution declared in that
#                          file's `loader_contract` belongs to the ladder lib.
#   AID_RECOVERY_FSM_BIN — path to aid-fsm.sh (test seam).
#
# **Last Updated:** 2026-08-09
# =============================================================================

# shellcheck source=aid-c3-dispatch.sh
_AID_RA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_AID_RA_DIR/aid-c3-dispatch.sh"

_AID_RA_POLICY_DEFAULT="$_AID_RA_DIR/../../defaults/policies/auto-recovery.yaml"
_AID_RA_FSM_DEFAULT="$_AID_RA_DIR/../aid-fsm.sh"

# The forbidden list. A CONSTANT, not a computed one: it names the categories
# no allowlist may ever contain, so it cannot drift with the policy.
_aid_ra_forbidden_block() {
  cat <<'EOF'
FORBIDDEN — you may not select, request, imply or negotiate any of these:
  - granting, assuming or delegating PM authority
  - waiving, weakening, skipping, deferring or overriding any gate, review or security risk
  - --force, pm_force, or any FSM override or state edit
  - editing plan.json, fsm-state.yaml, step verification files, gate reports or timelines
  - any action not printed in ALLOWED ACTIONS above, including "widen the allowlist"
Asking for any of these is not a decision. It is rejected mechanically, whatever the wording,
and the stop escalates to a human.
EOF
}

# _aid_ra_yaml_list <policy> <class> — prints the class's allowed actions, one
# per line. Prints nothing (success) for an unknown class or an unreadable
# policy: "no allowlist" is the fail-closed answer, and the caller short-circuits.
_aid_ra_allowlist() {
  local policy="$1" class="$2"
  [[ -f "$policy" ]] || return 0
  command -v yq >/dev/null 2>&1 || return 0
  # mikefarah/yq: `[]` over a missing/empty node yields nothing and exits 0 —
  # an unknown class is therefore "no allowlist", not an error.
  yq -r ".stop_classes.\"${class}\".allowed_actions[]" "$policy" 2>/dev/null || true
}

# _aid_ra_vocabulary <policy> — the closed six. Used for AMBIGUITY detection:
# a reply naming two action tokens is rejected even when only one of them is
# allowed for this class.
_aid_ra_vocabulary() {
  local policy="$1"
  [[ -f "$policy" ]] || return 0
  command -v yq >/dev/null 2>&1 || return 0
  yq -r '.action_vocabulary | keys | .[]' "$policy" 2>/dev/null || true
}

_aid_ra_sha256() {
  [[ -f "$1" ]] || { printf ''; return 0; }
  printf 'sha256:%s' "$(sha256sum "$1" | awk '{print $1}')"
}

# _aid_ra_tokens <reply_file> <vocab...> — distinct action tokens present in the
# reply, whole-word, one per line.
_aid_ra_tokens() {
  local reply="$1"; shift
  local t out=""
  for t in "$@"; do
    if grep -qE "(^|[^A-Za-z0-9_])${t}([^A-Za-z0-9_]|$)" "$reply" 2>/dev/null; then
      out+="${t}"$'\n'
    fi
  done
  printf '%s' "$out"
}

# _aid_ra_record <evidence_dir> <class> <action> <rationale> <verdict> <artifact> <attempt>
# Appends the ladder/timeline line. Returns 1 if the timeline cannot be written
# — an unrecordable decision is not a decision.
_aid_ra_record() {
  local dir="$1" class="$2" action="$3" rationale="$4" verdict="$5" artifact="$6" attempt="$7"
  local ts line
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  line="$(jq -nc \
    --arg ts "$ts" --arg class "$class" --arg action "$action" \
    --arg rationale "$rationale" --arg verdict "$verdict" \
    --arg artifact "$artifact" --argjson attempt "$attempt" \
    '{ts:$ts, event:"recovery_adjudication", class:$class, action:$action,
      rationale:$rationale, verdict:$verdict, artifact:$artifact, attempt:$attempt}')" || return 1
  printf '%s\n' "$line" >> "$dir/timeline.jsonl" || return 1
  if declare -F aid_recovery_ladder_append >/dev/null 2>&1; then
    aid_recovery_ladder_append "$dir" "$line" || return 1
  else
    printf '%s\n' "$line" >> "$dir/recovery-ladder.jsonl" || return 1
  fi
  return 0
}

# _aid_ra_artifact <out> <class> <attempt> <prompt_file> <reply_file> <verdict>
#                  <action> <rationale> <dispatched> <transport_error>
_aid_ra_artifact() {
  local out="$1" class="$2" attempt="$3" prompt_file="$4" reply_file="$5"
  local verdict="$6" action="$7" rationale="$8" dispatched="$9" terr="${10}"
  local raw="" ph=""
  [[ -f "$reply_file" ]] && raw="$(cat "$reply_file" 2>/dev/null || true)" || true
  ph="$(_aid_ra_sha256 "$prompt_file")"
  jq -n \
    --arg schema "aid.recovery_adjudication.v1" \
    --arg producer "aid-recovery-adjudicate.sh" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg class "$class" --argjson attempt "$attempt" \
    --arg prompt_path "$prompt_file" --arg prompt_sha256 "$ph" \
    --arg raw_reply "$raw" --arg verdict "$verdict" \
    --arg action "$action" --arg rationale "$rationale" \
    --argjson dispatched "$dispatched" --arg transport_error "$terr" \
    '{schema_version:$schema, artifact_type:"recovery_adjudication",
      producer:$producer, created_at:$created_at,
      stop_class:$class, attempt:$attempt, dispatched:$dispatched,
      prompt_path:$prompt_path, prompt_sha256:$prompt_sha256,
      raw_reply:$raw_reply, verdict:$verdict, action:$action,
      rationale:$rationale, transport_error:$transport_error}' \
    > "${out}.tmp" 2>/dev/null || return 1
  mv -f "${out}.tmp" "$out" || return 1
  return 0
}

# ---------------------------------------------------------------------------
# aid_recovery_adjudicate <run_evidence_dir> <stop_class> <facts_file>
# ---------------------------------------------------------------------------
aid_recovery_adjudicate() {
  local dir="${1:-}" class="${2:-}" facts="${3:-}"

  if [[ -z "$dir" || -z "$class" || -z "$facts" ]]; then
    echo "ERROR: usage: aid_recovery_adjudicate <run_evidence_dir> <stop_class> <facts_file>" >&2
    echo "escalate"
    return 2
  fi
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: run evidence dir not found: $dir — nothing can be recorded, so nothing is decided." >&2
    echo "escalate"
    return 3
  fi
  if ! : >> "$dir/timeline.jsonl" 2>/dev/null; then
    echo "ERROR: cannot append to $dir/timeline.jsonl — an unrecordable adjudication is refused." >&2
    echo "escalate"
    return 3
  fi

  local policy="${AID_RECOVERY_POLICY:-$_AID_RA_POLICY_DEFAULT}"
  local fsm_bin="${AID_RECOVERY_FSM_BIN:-$_AID_RA_FSM_DEFAULT}"
  local ts; ts="$(date -u +%Y%m%dT%H%M%SZ)"

  # -- allowlist first: an empty one means there is nothing to ask about ------
  local allow_lines; allow_lines="$(_aid_ra_allowlist "$policy" "$class")"
  local vocab_lines; vocab_lines="$(_aid_ra_vocabulary "$policy")"
  local -a allow=() vocab=()
  [[ -n "$allow_lines" ]] && mapfile -t allow <<< "$allow_lines" || true
  [[ -n "$vocab_lines" ]] && mapfile -t vocab <<< "$vocab_lines" || true

  local art="$dir/recovery-adjudication-${ts}-1.json"

  if [[ ${#allow[@]} -eq 0 ]]; then
    _aid_ra_artifact "$art" "$class" 1 "" "" "refused_empty_allowlist" "escalate" \
      "the policy authorises no recovery action for this class — nothing to choose from, so nothing is asked" \
      false "" || true
    _aid_ra_record "$dir" "$class" "escalate" \
      "empty allowlist for class ${class}: no dispatch" "refused_empty_allowlist" "$art" 1 || {
        echo "ERROR: could not record the refusal" >&2; echo "escalate"; return 3; }
    echo "escalate"
    return 3
  fi

  # -- facts: refuse BEFORE dispatching --------------------------------------
  if [[ ! -f "$facts" || ! -s "$facts" ]]; then
    _aid_ra_artifact "$art" "$class" 1 "" "" "refused_no_facts" "escalate" \
      "facts file missing or empty: ${facts}" false "" || true
    _aid_ra_record "$dir" "$class" "escalate" \
      "facts file missing or empty: ${facts}" "refused_no_facts" "$art" 1 || {
        echo "ERROR: could not record the refusal" >&2; echo "escalate"; return 3; }
    echo "escalate"
    return 3
  fi

  # -- context ---------------------------------------------------------------
  local state_file="$dir/fsm-state.yaml"
  [[ -f "$state_file" ]] || state_file="$dir/state.yaml"
  local fsm_state="unknown"
  if [[ -f "$state_file" && -x "$fsm_bin" ]]; then
    fsm_state="$(bash "$fsm_bin" get-state "$state_file" 2>/dev/null || echo unknown)"
  fi
  [[ -n "$fsm_state" ]] || fsm_state="unknown"

  local ladder="$dir/recovery-ladder.jsonl"
  local ladder_text="(no ladder record yet)"
  [[ -s "$ladder" ]] && ladder_text="$(cat "$ladder")" || true

  local project_root; project_root="$(cd "$_AID_RA_DIR/../../../.." && pwd)"

  # -- the loop: attempt 1, one retry, then escalate --------------------------
  local attempt rejection="" reply_prev=""
  for attempt in 1 2; do
    art="$dir/recovery-adjudication-${ts}-${attempt}.json"
    local prompt_file="$dir/recovery-adjudication-${ts}-${attempt}.prompt.md"
    local reply_file="$dir/.recovery-adjudication-${ts}-${attempt}.reply"
    local events_file="$dir/.recovery-adjudication-${ts}-${attempt}.events.jsonl"
    local stderr_file="$dir/.recovery-adjudication-${ts}-${attempt}.stderr"
    rm -f "$reply_file" "$events_file" "$stderr_file"

    {
      echo "# AID AUTO-MODE RECOVERY ADJUDICATION"
      echo
      echo "You are adjudicating ONE stop in an autonomous run. You are not the PM."
      echo "You may only choose among recovery paths the project has ALREADY authorised."
      echo
      echo "STOP CLASS: ${class}"
      echo "FSM STATE:  ${fsm_state}"
      echo
      echo "## VERIFIED FACTS"
      cat "$facts"
      echo
      echo "## LADDER RECORD SO FAR (attempted recoveries)"
      echo "$ladder_text"
      echo
      echo "## ALLOWED ACTIONS"
      printf '  - %s\n' "${allow[@]}"
      echo
      _aid_ra_forbidden_block
      echo
      if [[ -n "$rejection" ]]; then
        echo "## YOUR PREVIOUS REPLY WAS REJECTED"
        echo "Reason: ${rejection}"
        echo "Rejected reply (verbatim):"
        echo "-----"
        printf '%s\n' "$reply_prev"
        echo "-----"
        echo "This is the final attempt. A second invalid reply escalates to a human."
        echo
      fi
      echo "## REQUIRED REPLY FORMAT"
      echo "ACTION: <exactly one name copied from ALLOWED ACTIONS>"
      echo "RATIONALE: <one or two sentences, including the risk note>"
      echo "Name exactly ONE action. Naming two, naming none, or naming anything"
      echo "outside ALLOWED ACTIONS is rejected."
    } > "$prompt_file"

    # -- transport (shared, never reimplemented) -----------------------------
    if ! declare -F _run_codex_isolated >/dev/null 2>&1; then
      _aid_ra_artifact "$art" "$class" "$attempt" "$prompt_file" "" "transport_error" "escalate" \
        "" true "isolated Codex transport unavailable: _run_codex_isolated is not defined" || true
      _aid_ra_record "$dir" "$class" "escalate" \
        "transport unavailable" "transport_error" "$art" "$attempt" || true
      echo "escalate"
      return 3
    fi

    local rc=0
    _run_codex_isolated "$project_root" "$prompt_file" "$events_file" "$stderr_file" "$reply_file" || rc=$?

    if [[ "$rc" -ne 0 ]]; then
      local terr="codex transport exit ${rc}"
      [[ -s "$stderr_file" ]] && terr="${terr}: $(head -c 2000 "$stderr_file")" || true
      _aid_ra_artifact "$art" "$class" "$attempt" "$prompt_file" "$reply_file" \
        "transport_error" "escalate" "" true "$terr" || true
      _aid_ra_record "$dir" "$class" "escalate" "$terr" "transport_error" "$art" "$attempt" || true
      echo "escalate"
      return 3
    fi

    [[ -f "$reply_file" ]] || : > "$reply_file"
    local raw; raw="$(cat "$reply_file" 2>/dev/null || true)"

    # -- validation ---------------------------------------------------------
    local verdict="" action="" rationale=""
    local tokens; tokens="$(_aid_ra_tokens "$reply_file" "${vocab[@]}" "${allow[@]}" | sort -u)"
    local n_tokens=0
    [[ -n "$tokens" ]] && n_tokens="$(printf '%s\n' "$tokens" | grep -c .)" || true

    if [[ "$n_tokens" -eq 0 ]]; then
      verdict="rejected_empty"
      rejection="the reply named no action at all (an empty or action-free reply is never consent)"
    elif [[ "$n_tokens" -gt 1 ]]; then
      verdict="rejected_ambiguous"
      rejection="the reply named ${n_tokens} action tokens ($(printf '%s' "$tokens" | tr '\n' ' ')); exactly one is required"
    else
      action="$tokens"
      local ok=0 a
      for a in "${allow[@]}"; do if [[ "$a" == "$action" ]]; then ok=1; fi; done
      if [[ "$ok" -ne 1 ]]; then
        verdict="rejected_out_of_allowlist"
        rejection="'${action}' is not in the allowlist for class ${class}"
        action=""
      else
        rationale="$(grep -m1 -iE '^[[:space:]]*RATIONALE:' "$reply_file" 2>/dev/null \
                     | sed -E 's/^[[:space:]]*[Rr][Aa][Tt][Ii][Oo][Nn][Aa][Ll][Ee]:[[:space:]]*//' || true)"
        if [[ -z "$rationale" ]]; then
          verdict="rejected_no_rationale"
          rejection="the reply selected '${action}' but gave no RATIONALE line"
          action=""
        else
          verdict="accepted"
        fi
      fi
    fi

    _aid_ra_artifact "$art" "$class" "$attempt" "$prompt_file" "$reply_file" \
      "$verdict" "${action:-escalate}" "${rationale:-$rejection}" true "" || {
        echo "ERROR: could not write the adjudication artifact — refusing the decision." >&2
        echo "escalate"; return 3; }

    if [[ "$verdict" == "accepted" ]]; then
      _aid_ra_record "$dir" "$class" "$action" "$rationale" "accepted" "$art" "$attempt" || {
        echo "ERROR: could not record the accepted decision — refusing it." >&2
        echo "escalate"; return 3; }
      echo "$action"
      return 0
    fi

    _aid_ra_record "$dir" "$class" "escalate" "$rejection" "$verdict" "$art" "$attempt" || {
      echo "ERROR: could not record the rejection." >&2; echo "escalate"; return 3; }

    reply_prev="$raw"
  done

  echo "escalate"
  return 3
}
