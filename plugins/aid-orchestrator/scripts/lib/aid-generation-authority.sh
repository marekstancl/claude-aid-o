#!/usr/bin/env bash
# =============================================================================
# lib/aid-generation-authority.sh — the generation transaction's duties as a
# library (P111 Step 2): the generation lock, the one transaction file and its
# atomic writer, the target branch and head, the CP1 seal and its verifier, and
# the plan.json-versus-source-graph receipt check.
#
# Moved UNCHANGED from aid-auto-pipeline.sh (229-375, the inline seal
# ~1470-1715) and aid-plan-to-epic.sh (_verify_generation_authority 270-372),
# so the pipeline and `aid-plan-fsm.sh plan-run` hold ONE lock, write ONE
# transaction file and seal through ONE body: the two roads to a run exclude
# each other by mechanism (P111). The pipeline keeps calling the `_gen_*`
# names; the aid_gen_* names below are the library's public interface.
#
# Callers source lib/common.sh (error_exit) first. A caller may set
# _aid_pipeline_state_root; otherwise the state root is resolved here.
# =============================================================================
[[ -n "${_AID_GEN_AUTHORITY_LOADED:-}" ]] && return 0
_AID_GEN_AUTHORITY_LOADED=1
_AID_GEN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The caller's scripts dir, never `lib/..`: a test farm symlinks lib/, and the
# kernel resolves `..` physically — through the link, into the real plugin.
_AID_GEN_SCRIPTS_DIR="${SCRIPT_DIR:-${_AID_GEN_LIB_DIR%/*}}"
# shellcheck source=aid-lock.sh
source "${_AID_GEN_LIB_DIR}/aid-lock.sh"
# shellcheck source=aid-roots.sh
source "${_AID_GEN_LIB_DIR}/aid-roots.sh"
# shellcheck source=aid-generation-ids.sh
source "${_AID_GEN_LIB_DIR}/aid-generation-ids.sh"

# AID_GEN_PHASE_DERIVATION_VERSION is defined with the derivation it versions,
# in lib/aid-generation-ids.sh (sourced below).
AID_GEN_LOCK_TIMEOUT="${AID_GEN_LOCK_TIMEOUT:-60}"
_GEN_LOCK_FD=""

# =============================================================================
# P074 Step 18 — HONEST FAILURE LABELS
# =============================================================================
# Generation owns EXACTLY TWO labels. Both live here, at their only definition
# site, and are emitted from the single gate-failure branch below:
#
#   aid_cp1_blocked              the failed condition class is one --force
#                                CANNOT cover — retyping the command with
#                                --force would fail again in the same place.
#   aid_generation_force_required  the failure IS a CP1 condition verdict, so a
#                                deliberate, audited PM override can proceed;
#                                the exact public command is printed with THIS
#                                invocation's --plan/--queue-mode values.
#
# Everything else that fails is NOT relabelled: the subprocess's own stderr is
# already inherited verbatim, and the EXIT hook only appends a one-line note
# when AID's own checks had already passed (see _gen_on_exit).
#
# WHY THIS CLASSIFICATION IS DECIDABLE (and not guesswork — PM decision 3
# dropped the host-error detector precisely because it was). It is read from
# aid-cp1-gate.sh's own documented exit-code contract:
#
#   rc 1  a plan-review CONDITION — no closed or valid round, a plan changed
#         after its last round, blockers without a second round or without an
#         acceptance criterion quoting them, a round beyond rounds_default
#         without the PM's override. Review evidence a PM may deliberately
#         waive. -> FORCEABLE.
#   rc 2  usage error ("Unknown argument") — the gate was mis-invoked and never
#         evaluated a condition. -> HARD.
#   rc 3  the gate could not trust what it would judge: the plan file or its
#         id, an invalid plan_review config, unreadable round evidence, a round
#         the index lists but that is gone, a malformed override.json. -> HARD.
#   rc 1, but one of three PLAN-IDENTITY strings (no closing frontmatter `---`,
#         no `id:` field, an `id` failing the path-traversal guard): a stub or
#         an older gate may still report those with rc 1, and forcing past them
#         would seal an authority whose plan identity is the very thing that is
#         broken. -> HARD.
#
# The three rc-1 strings are matched literally. If the gate's vocabulary
# changes, this list changes with it — it is a mapping of one script's strings,
# never an inference about them.
AID_GEN_LABEL_BLOCKED="aid_cp1_blocked"
AID_GEN_LABEL_FORCE_REQUIRED="aid_generation_force_required"

# ---------------------------------------------------------------------------
# STDERR STAGING — so the label really is the FIRST line of stderr
# ---------------------------------------------------------------------------
# The contract is "first line", not "somewhere in the output", and the pipeline
# emits [INFO]/[WARN] progress to stderr well before the gate is ever consulted
# ([INFO] Starting pipeline…, plan_source_binding, lifecycle mode, …). Printing
# the label after that chatter is not the contract, it is a near miss.
#
# So the pre-gate window is STAGED: fd 2 is redirected into a temp file, the
# real stderr is held on fd 9, and the staged bytes are flushed IN ORDER the
# moment the gate decision is known. On a refusal the label goes straight to
# fd 9 first, so it lands on line 1 with the run's own chatter beneath it and
# the gate's stderr beneath that. Nothing is dropped and nothing is reordered.
#
# The window is deliberately short (arg validation → gate decision) and every
# exit inside it flushes: explicitly on the labelled paths, via the EXIT trap
# on every other. A SIGKILL inside the window loses staged chatter — an
# accepted trade for a contract that actually holds, and the window contains no
# state-mutating work whose loss would matter.
_gen_stderr_buf=""
_gen_stderr_staged=false

_gen_stage_stderr() {
  _gen_stderr_buf="$(mktemp "${TMPDIR:-/tmp}/aid-generation-stderr.XXXXXX" 2>/dev/null)" || return 0
  exec 9>&2
  exec 2>"$_gen_stderr_buf"
  _gen_stderr_staged=true
  return 0
}

# _gen_flush_stderr — restore the real stderr and emit every staged byte, in
# order. Idempotent: safe to call on the labelled paths AND from the EXIT trap.
_gen_flush_stderr() {
  [[ "$_gen_stderr_staged" == true ]] || return 0
  _gen_stderr_staged=false
  exec 2>&9
  exec 9>&-
  if [[ -s "$_gen_stderr_buf" ]]; then cat "$_gen_stderr_buf" >&2; fi
  rm -f "$_gen_stderr_buf" 2>/dev/null || true
  return 0
}

# _gen_err_first <line> — write one line to the REAL stderr, ahead of anything
# still staged. Falls back to plain stderr when staging never started (mktemp
# failure), so the message is never lost.
_gen_err_first() {
  if [[ "$_gen_stderr_staged" == true ]]; then
    printf '%s\n' "$1" >&9
  else
    printf '%s\n' "$1" >&2
  fi
  return 0
}

# _gen_gate_hard_condition <rc> <gate_output>
#   Echoes the HARD condition (the exit-code reason, or the matched literal
#   line) when --force could not cover this failure; echoes nothing when the
#   failure is a forceable CP1 condition verdict.
#
#   Mixed output — some forceable conditions plus one hard one — resolves to
#   HARD, and the echoed text is the hard condition, so the message names it
#   first: a --force there would not unblock anything.
_gen_gate_hard_condition() {
  local rc="$1" out="$2" line=""
  case "$rc" in
    2) printf 'the CP1 gate exited 2 (usage error) — it was mis-invoked and never evaluated a CP1 condition'; return 0 ;;
    3) printf 'the CP1 gate exited 3 (hard condition) — its input could not be trusted (unreadable or tampered evidence, invalid configuration, missing tool), so no CP1 condition was evaluated'; return 0 ;;
  esac
  while IFS= read -r line; do
    case "$line" in
      *"missing closing '---' for frontmatter"*|\
      *"missing 'id' field in frontmatter"*|\
      *"contains invalid characters (path traversal guard)"*)
        printf '%s' "$line"; return 0 ;;
    esac
  done <<< "$out"
  return 0
}

_gen_dir()              { aid_state_path ".aid-o/work/evidence/${1}/generation"; }
_gen_authority_path()   { printf '%s/generation-authority.json\n' "$(_gen_dir "$1")"; }
_gen_transaction_path() { printf '%s/transaction.json\n' "$(_gen_dir "$1")"; }
_gen_audit_log_path()   { aid_state_path ".aid-o/work/audit-log.jsonl"; }

# _gen_target_branch — the configured integration branch. Deliberately a local
# copy of lib/aid-lifecycle.sh's `aid_target_branch` (same rule, same default):
# aid-auto-pipeline.sh sources that lib far below its committed-source
# preflight, and sourcing it earlier (through this library) would change the
# preflight's behaviour as a side effect — so this library never sources it.
_gen_target_branch() {
  local orch="${_AID_GEN_SCRIPTS_DIR}/../defaults/orchestration.yaml" tb=""
  if [[ -f "$orch" ]] && command -v yq >/dev/null 2>&1; then
    tb="$(yq -r '.lifecycle.target_branch // ""' "$orch" 2>/dev/null || true)"
  fi
  [[ -z "$tb" || "$tb" == "null" ]] && tb="main"
  printf '%s\n' "$tb"
}

# _gen_target_head — the commit the target branch points at, or "" when no such
# branch exists. EMPTY IS A LEGITIMATE VALUE, not an error: fixture repos and
# fresh workspaces have no integration branch, and the verifier compares the
# sealed value against the freshly resolved one, so "" == "" still binds.
_gen_target_head() {
  git -C "${_aid_pipeline_state_root:-$(aid_state_root 2>/dev/null || pwd)}" rev-parse --verify --quiet "$(_gen_target_branch)^{commit}" 2>/dev/null || true
}

# _gen_plan_recorded_mode <plan_id> — the mode THIS plan actually declares, read
# from the committed lifecycle manifest.
#
# Deliberately not `_pb_default_mode`, which answers a different question: the
# mode a NEW plan would be created with, resolved from policy and downgraded to
# legacy when the project has no gate_profiles table. A plan explicitly
# plan-started with `--mode plan_branch` in such a project records plan_branch
# while the default resolver still says legacy — and `init`'s lineage check
# consults the manifest, not the default. Asking the default would put the
# generation chain and init on two different answers.
_gen_plan_recorded_mode() {
  local pid="${1:-}" m=""
  [[ -n "$pid" ]] || { printf ''; return 0; }
  m="$(git -C "${_aid_pipeline_state_root:-$(aid_state_root 2>/dev/null || pwd)}" show "$(_gen_target_branch):.aid-lifecycle/manifests/${pid}.yaml" 2>/dev/null \
       | yq -r '.mode // ""' 2>/dev/null || true)"
  printf '%s' "$m"
}

_gen_sha256_file() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
# Canonical-JSON self-hash. A PLAIN STATED CONVENTION (no in-tree precedent
# hashes an embedded-self-field envelope): canonical JSON via `jq -S -c` with
# the hash field NULLED, piped to sha256sum. Verifiers recompute exactly this.
_gen_self_sha256() { jq -S -c '.self_sha256 = null' "$1" 2>/dev/null | sha256sum | awk '{print $1}'; }

_gen_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── the generation lock ────────────────────────────────────────────────────
# RE-ENTRANT BY DEPTH COUNT, and that is not a nicety: the whole generation
# runs under ONE hold (see the pre-phase block), while `_gen_tx_update` also
# asks for the lock on every manifest write. `flock` is per open file
# DESCRIPTION, not per process — a second `exec {fd}<>` + `flock -x` from the
# same process on the same file DEADLOCKS against our own hold. Nesting is
# therefore counted, and only the outermost release actually drops the flock.
#
# STALE-LOCK RECOVERY: flock is released by the kernel when the last descriptor
# closes, INCLUDING on process death, so a killed generation never leaves a
# lock that blocks the next run. The pid inside the sidecar is informational
# only — it is what a timed-out acquirer reports so a human can see who holds
# it. If a run really is wedged, kill that pid; deleting the `.lock` file is
# never the fix (it would let a second writer in alongside the first).
_GEN_LOCK_DEPTH=0
_gen_lock() {
  if [[ "$_GEN_LOCK_DEPTH" -gt 0 ]]; then
    _GEN_LOCK_DEPTH=$(( _GEN_LOCK_DEPTH + 1 ))
    return 0
  fi
  local lp; lp="$(_gen_transaction_path "$1").lock"
  aid_lock_acquire "$lp" "$AID_GEN_LOCK_TIMEOUT" || return 3
  _GEN_LOCK_FD="$AID_LOCK_FD"
  _GEN_LOCK_DEPTH=1
  return 0
}
_gen_unlock() {
  [[ "$_GEN_LOCK_DEPTH" -gt 0 ]] || return 0
  _GEN_LOCK_DEPTH=$(( _GEN_LOCK_DEPTH - 1 ))
  [[ "$_GEN_LOCK_DEPTH" -eq 0 ]] || return 0
  [[ -n "${_GEN_LOCK_FD:-}" ]] || return 0
  aid_lock_release "$_GEN_LOCK_FD" || true
  _GEN_LOCK_FD=""
}
# _gen_lock_holder <plan_id> — the pid recorded in the sidecar (informational).
_gen_lock_holder() {
  local lp; lp="$(_gen_transaction_path "$1").lock"
  local h; h="$(cat "$lp" 2>/dev/null | tr -d '[:space:]')"
  printf '%s' "${h:-unknown}"
}

# _gen_write_atomic <path> <content> — mktemp + mv, never an in-place rewrite.
_gen_write_atomic() {
  local path="$1" content="$2" tmp=""
  mkdir -p "$(dirname "$path")" 2>/dev/null || return 3
  tmp="$(mktemp "${path}.tmp.XXXXXX" 2>/dev/null)" || return 3
  printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 3; }
  mv -- "$tmp" "$path" 2>/dev/null || { rm -f "$tmp"; return 3; }
  return 0
}

# _gen_tx_update <plan_id> <jq-filter> [jq args...]
#   LOCKED read-modify-write plus atomic tmp+mv, so two pipeline invocations
#   never interleave a lost update. `updated_at` is refreshed on every write.
_gen_tx_update() {
  local plan_id="$1" filter="$2"; shift 2
  local txp; txp="$(_gen_transaction_path "$plan_id")"
  _gen_lock "$plan_id" || error_exit "cannot acquire the generation transaction lock for ${plan_id} (${txp}.lock) — another generation for this plan is running, or flock is unavailable." 3
  if [[ ! -f "$txp" ]]; then
    _gen_unlock
    error_exit "generation transaction manifest disappeared mid-run (${txp}) — it was superseded or removed while this generation was running. Nothing further was recorded. Re-run generation to start a fresh transaction." 3
  fi
  local updated=""
  updated="$(jq "$@" --arg _u "$(_gen_now)" "($filter) | .updated_at = \$_u" "$txp" 2>/dev/null)" || {
    _gen_unlock
    error_exit "cannot update the generation transaction manifest ${txp} (malformed JSON?)" 3
  }
  _gen_write_atomic "$txp" "$updated" || {
    _gen_unlock
    error_exit "cannot write the generation transaction manifest ${txp}" 3
  }
  _gen_unlock
  return 0
}

# aid_gen_seal <plan> <plan_id> <total> <mode> <force:true|false> <force_reason> [<override command>]
#   THE CP1 seal (P074 Steps 15/18), moved unchanged from the pipeline: reuse a
#   valid authority for this identity, or run the CP1 gate ONCE, classify a
#   failure (hard vs forceable), write every audit record of a forced run
#   FIRST and the authority LAST, then bind the transaction to it. The target
#   head it records is _gen_target_head — the current head of the target branch.
#   Must run under _gen_lock; refusals release it and exit. Sets
#   _gen_gate_passed=true when the sealed verdict is pass.
aid_gen_seal() {
  local plan="$1" plan_id="$2" total_phases="$3" queue_mode="$4" force_generation="$5" force_reason="$6" _seal_override="${7:-}"
  local _aid_pipeline_state_root="${_aid_pipeline_state_root:-$(aid_state_root 2>/dev/null || pwd)}"
  [[ -n "$_seal_override" ]] || _seal_override="$(printf "aid-auto-pipeline.sh --plan %q --queue-mode %q --force --reason %q" "$plan" "$queue_mode" "<why, at least 20 characters>")"
  local _gen_plan_sha256 _gen_target_branch_name _gen_target_head_sha _gen_dir_path _gen_tx_path _gen_auth_path
  _gen_plan_sha256="$(_gen_sha256_file "$plan")"
  _gen_target_branch_name="$(_gen_target_branch)"
  _gen_target_head_sha="$(_gen_target_head)"
  _gen_dir_path="$(_gen_dir "$plan_id")"
  _gen_tx_path="$(_gen_transaction_path "$plan_id")"
  _gen_auth_path="$(_gen_authority_path "$plan_id")"
# ── the ONE CP1 gate call, and the sealed authority ────────────────────────
_gen_authority_valid=false
if [[ -f "$_gen_auth_path" ]]; then
  if jq -e --arg s "aid-generation-authority/v1" --arg id "$_gen_plan_sha256" \
       --arg th "$_gen_target_head_sha" --argjson pdv "$AID_GEN_PHASE_DERIVATION_VERSION" \
       --argjson total "$total_phases" \
       '.schema == $s and .plan_sha256 == $id and .target_head == $th
        and .phase_derivation_version == $pdv and .total_phases == $total' \
       "$_gen_auth_path" >/dev/null 2>&1 \
     && [[ "$(jq -r '.self_sha256 // ""' "$_gen_auth_path")" == "$(_gen_self_sha256 "$_gen_auth_path")" ]]; then
    _gen_authority_valid=true
    echo "[INFO] generation_authority: reusing the sealed plan-scoped authority at ${_gen_auth_path} (identity unchanged) — the CP1 gate is NOT re-consulted." >&2
  else
    echo "[WARN] generation_authority: the authority at ${_gen_auth_path} does not bind this identity (or fails its own self-hash) — it is re-sealed from a fresh gate decision." >&2
  fi
fi

if [[ "$_gen_authority_valid" != true ]]; then
  _gen_cp1_out=""; _gen_cp1_rc=0
  if [[ -f "${_AID_GEN_SCRIPTS_DIR}/aid-cp1-gate.sh" ]]; then
    _gen_cp1_out="$(bash "${_AID_GEN_SCRIPTS_DIR}/aid-cp1-gate.sh" --plan "$plan" --project-root "$_aid_pipeline_state_root" 2>&1)" || _gen_cp1_rc=$?
  else
    _gen_cp1_out="cp1 gate script not present — no gate to run"
  fi
  # On a PASS the gate's own output goes out here, as it always has. On a
  # FAILURE it is printed by the labelling branch below INSTEAD — the label has
  # to be the first line of stderr, and the gate stderr always follows it.
  if [[ "$_gen_cp1_rc" -eq 0 ]]; then printf '%s\n' "$_gen_cp1_out" >&2; fi

  _gen_cp1_json='{"verdict":"pass"}'
  _gen_forced=false
  if [[ "$_gen_cp1_rc" -ne 0 ]]; then
    # ══ P074 Step 18: CLASSIFY FIRST, THEN decide what --force may do ══════
    #
    # The classification runs BEFORE the force branch, and that ORDER is the
    # whole enforcement. An earlier cut classified only on the non-forced path,
    # so `aid_cp1_blocked` ("--force does not cover this") was a claim the very
    # next invocation disproved: re-running with --force skipped the
    # classification entirely and sealed a forced authority over the same hard
    # condition. That is AID-v3-principles §1 exactly — a detector whose verdict
    # nothing enforces is decoration. A hard condition is now non-forceable in
    # CODE: --force lands in the same branch, fails in the same place, and says
    # so by name.
    _gen_first_line="$(printf '%s\n' "$_gen_cp1_out" | head -1)"
    _gen_prelabelled=false
    if [[ "$_gen_first_line" == "${AID_GEN_LABEL_BLOCKED}:"* || "$_gen_first_line" == "${AID_GEN_LABEL_FORCE_REQUIRED}:"* ]]; then
      _gen_prelabelled=true
    fi
    _gen_hard="$(_gen_gate_hard_condition "$_gen_cp1_rc" "$_gen_cp1_out")"

    if [[ -n "$_gen_hard" ]]; then
      # HARD — refused whether or not --force was given. No authority, no
      # waiver, no audit record: there is nothing to record a bypass OF,
      # because no bypass happened.
      _gen_unlock
      if [[ "$_gen_prelabelled" == true ]]; then
        _gen_flush_stderr
        printf '%s\n' "$_gen_cp1_out" >&2
        exit 1
      fi
      _gen_force_note=""
      if [[ "$force_generation" == true ]]; then
        _gen_force_note=" --force DOES NOT APPLY to this condition class and changed nothing: no authority was sealed, no waiver was written, and re-running with --force will fail in this same place."
      fi
      _gen_err_first "$(printf '%s: %s. Generation for %s stopped before anything was created.%s Fix the named condition and re-run.' \
        "$AID_GEN_LABEL_BLOCKED" "$_gen_hard" "$plan_id" "$_gen_force_note")"
      _gen_flush_stderr
      printf '%s\n' "$_gen_cp1_out" >&2
      exit 1
    fi

    if [[ "$force_generation" != true ]]; then
      _gen_unlock
      if [[ "$_gen_prelabelled" == true ]]; then
        # A wrapper invoked this pipeline through itself: the gate output is
        # ALREADY labelled. Pass it through untouched — a doubled label reads
        # as two different refusals for one refusal.
        _gen_flush_stderr
        printf '%s\n' "$_gen_cp1_out" >&2
        exit 1
      fi
      # FORCEABLE: the exact public command, with THIS invocation's values,
      # SHELL-QUOTED so the printed line is executable verbatim. printf %q, not
      # hand-written single quotes: a plan path like `/work/PM's plan.md`
      # renders unparseable under naive quoting, and an unquoted queue_mode
      # would word-split.
      _gen_err_first "$(printf "%s: the CP1 gate refused generation for %s and nothing was created. Fix the conditions below, or override deliberately with: %s" \
        "$AID_GEN_LABEL_FORCE_REQUIRED" "$plan_id" "$_seal_override")"
      _gen_flush_stderr
      printf '%s\n' "$_gen_cp1_out" >&2
      exit 1
    fi
    _gen_flush_stderr
    printf '%s\n' "$_gen_cp1_out" >&2
    _gen_forced=true
    # The bypassed conditions, recorded verbatim from the gate's own output —
    # never a paraphrase, and never a rewrite of the CP1 artifacts on disk.
    _gen_cp1_json="$(jq -n --arg out "$_gen_cp1_out" --argjson rc "$_gen_cp1_rc" \
      --argjson refs "$(jq -n --arg a "$(aid_state_path ".aid-o/work/evidence/${plan_id}/cp1/rounds.json")" \
                              --arg b "$(aid_state_path ".aid-o/work/evidence/${plan_id}/cp1")" \
        '[{path:$a, sha256:null},{path:$b, sha256:null}]')" \
      '{bypassed_conditions: ($out | split("\n") | map(select(length > 0))), gate_exit: $rc, evidence_refs: $refs}')"
    # Hash the plan-review round index when it exists (audit provenance at
    # decision time; the round directories it lists are what the gate read).
    _gen_rounds_ref="$(aid_state_path ".aid-o/work/evidence/${plan_id}/cp1/rounds.json")"
    if [[ -f "$_gen_rounds_ref" ]]; then
      _gen_cp1_json="$(jq -c --arg p "$_gen_rounds_ref" --arg h "$(_gen_sha256_file "$_gen_rounds_ref")" \
        '.evidence_refs |= map(if .path == $p then .sha256 = $h else . end)' <<< "$_gen_cp1_json")"
    fi
  elif [[ "$force_generation" == true ]]; then
    # --force on a plan whose gate PASSES: the force is recorded as UNUSED —
    # nothing was bypassed, so no waiver is written (P073 Step 8 semantics).
    _gen_cp1_json='{"verdict":"pass","force_unused":true}'
  fi

  _gen_auth_draft="$(jq -n \
    --arg schema "aid-generation-authority/v1" \
    --arg plan_id "$plan_id" --arg plan_path "$plan" --arg plan_sha256 "$_gen_plan_sha256" \
    --arg target_branch "$_gen_target_branch_name" --arg target_head "$_gen_target_head_sha" \
    --arg mode "$queue_mode" --argjson total "$total_phases" \
    --argjson pdv "$AID_GEN_PHASE_DERIVATION_VERSION" \
    --argjson cp1 "$_gen_cp1_json" --argjson forced "$_gen_forced" \
    --arg reason "$force_reason" --arg invoker "${USER:-unknown}" --arg created "$(_gen_now)" \
    '{schema:$schema, plan_id:$plan_id, plan_path:$plan_path, plan_sha256:$plan_sha256,
      target_branch:$target_branch, target_head:$target_head, mode:$mode,
      total_phases:$total, phase_derivation_version:$pdv, cp1:$cp1,
      forced_override:$forced, force_reason:(if $reason == "" then null else $reason end),
      invoker:$invoker, created_at:$created, self_sha256:null}')" || _gen_auth_draft=""
  [[ -n "$_gen_auth_draft" ]] || { _gen_unlock; error_exit "cannot render the generation authority receipt for ${plan_id}" 3; }
  _gen_auth_self="$(printf '%s\n' "$_gen_auth_draft" | jq -S -c '.self_sha256 = null' | sha256sum | awk '{print $1}')"
  _gen_auth_final="$(jq --arg h "$_gen_auth_self" '.self_sha256 = $h' <<< "$_gen_auth_draft")"

  # ==========================================================================
  # ORDER: EVERY AUDIT RECORD FIRST, THEN THE AUTHORITY
  # ==========================================================================
  # Writing the authority first and treating the timeline and audit-log writes
  # as best-effort (`|| true`, P073's contract for them) is a hole with teeth on
  # a forced run: a kill or an I/O error between the two leaves a VALID
  # `forced_override: true` authority on disk with no P073 trail at all — and
  # resume ACCEPTS a valid authority without re-consulting the gate, so the
  # bypass would become permanent and invisible.
  #
  # The authority is the thing that authorizes generation, so it is now the
  # LAST write of this block: all three records must be durable before it
  # exists. All three are FAIL-CLOSED here — a deliberate divergence from
  # P073's best-effort audit-log contract, where the waiver artifact is the
  # authority and the log is a convenience. Here the receipt being verified
  # downstream IS the authority file, so anything that cannot record the
  # bypass must abort before that file exists.
  #
  # aid-audit-log.sh swallows its own write failures by design ("audit log
  # failure must never abort primary FSM operation") and always returns 0, so
  # its success is verified by READING THE RECORD BACK, not by its exit code.
  if [[ "$_gen_forced" == true ]]; then
    _gen_force_epoch="$(date -u +%Y%m%dT%H%M%SZ)"
    _gen_waiver="${_gen_dir_path}/waiver-generation-${_gen_force_epoch}.json"
    _gen_wn=0
    while [[ -e "$_gen_waiver" ]]; do
      _gen_wn=$(( _gen_wn + 1 ))
      [[ "$_gen_wn" -gt 100 ]] && { _gen_unlock; error_exit "cannot find a free force-receipt name under ${_gen_dir_path} — refusing a silent bypass." 3; }
      _gen_waiver="${_gen_dir_path}/waiver-generation-${_gen_force_epoch}-${_gen_wn}.json"
    done
    _gen_head_sha="$(git -C "$_aid_pipeline_state_root" rev-parse HEAD 2>/dev/null || echo unknown)"
    _gen_waiver_json="$(jq -n \
      --arg created_at "$(_gen_now)" --arg plan_id "$plan_id" \
      --arg head_sha "$_gen_head_sha" --arg reason "$force_reason" \
      --arg by "${USER:-unknown}" --arg subject "sha256:${_gen_auth_self}" \
      --argjson cp1 "$_gen_cp1_json" \
      '{schema_version:"aid-2.0", artifact_type:"waiver",
        producer:"aid-auto-pipeline.sh@generation-force-override",
        created_at:$created_at, control_protocol:"aid-2.0",
        identity:{project_id:null, epic_id:$plan_id, run_id:"generation", step_id:null},
        subject:{subject_hash:$subject},
        revision:{head_sha:$head_sha, head_is_current:true, freshness:"current"},
        status:"blocked", verdict:{kind:"none", ready:false},
        provenance:{dispatch_mode:"deterministic", generated_by_tool:"aid-auto-pipeline.sh"},
        waiver:{waived_check:"aid-auto-pipeline:cp1-gate", reason:$reason, waived_by:$by, waived_at:$created_at, scope:"run", visible:true},
        forced_override:true, records:"precondition_bypass", actor_semantics:"instruction_only",
        bypassed_preconditions:($cp1.bypassed_conditions // [])}')" || _gen_waiver_json=""
    [[ -n "$_gen_waiver_json" ]] || { _gen_unlock; error_exit "cannot render the generation force receipt — refusing a silent bypass." 3; }
    # Record 1 — the HEAD-bound waiver artifact.
    _gen_write_atomic "$_gen_waiver" "$_gen_waiver_json" || { _gen_unlock; error_exit "cannot write the generation force receipt at ${_gen_waiver} — refusing a silent bypass. No authority was sealed." 3; }
    # Record 2 — the timeline event. FAIL-CLOSED.
    if ! printf '%s\n' "$(jq -nc --arg ts "$(_gen_now)" --arg ev "generation_force_override" --arg plan "$plan_id" \
        --arg reason "$force_reason" --arg op "${USER:-unknown}" --arg receipt "$(basename "$_gen_waiver")" \
        --argjson cp1 "$_gen_cp1_json" \
        '{ts:$ts, event:$ev, plan_id:$plan, reason:$reason, operator:$op, receipt:$receipt,
          force_unused:false, bypassed_preconditions:($cp1.bypassed_conditions // [])}')" \
        >> "${_gen_dir_path}/timeline.jsonl" 2>/dev/null; then
      rm -f "$_gen_waiver" 2>/dev/null || true
      _gen_unlock
      error_exit "cannot append the generation_force_override timeline event to ${_gen_dir_path}/timeline.jsonl — refusing a silent bypass. No authority was sealed." 3
    fi
    # Record 3 — the cross-plan audit log, VERIFIED BY READING IT BACK.
    bash "${_AID_GEN_SCRIPTS_DIR}/aid-audit-log.sh" append \
      --epic-id "$plan_id" --run-id "generation" --event "generation_force_override" \
      --plan-id "$plan_id" --reason "$force_reason" --operator "${USER:-unknown}" \
      --receipt "$(basename "$_gen_waiver")" \
      --output "$(_gen_audit_log_path)" >/dev/null 2>&1 || true
    if ! tail -n 5 "$(_gen_audit_log_path)" 2>/dev/null \
         | grep -q "\"event\":\"generation_force_override\".*\"plan_id\":\"${plan_id}\""; then
      rm -f "$_gen_waiver" 2>/dev/null || true
      _gen_unlock
      error_exit "the generation_force_override entry could not be read back from $(_gen_audit_log_path) — the bypass is not durably recorded, so no authority was sealed and nothing was generated. Repair the audit-log path and re-run." 3
    fi
    echo "[WARN] generation_force_override: the CP1 gate was BYPASSED for ${plan_id}. Recorded at ${_gen_waiver}; the CP1 artifacts on disk were NOT rewritten." >&2
  elif [[ "$force_generation" == true ]]; then
    # Nothing was bypassed, so there is no waiver — but the unused force is
    # still recorded, and still before the authority exists.
    if ! printf '%s\n' "$(jq -nc --arg ts "$(_gen_now)" --arg ev "generation_force_override" --arg plan "$plan_id" \
        --arg reason "$force_reason" --arg op "${USER:-unknown}" \
        '{ts:$ts, event:$ev, plan_id:$plan, reason:$reason, operator:$op, force_unused:true, bypassed_preconditions:[]}')" \
        >> "${_gen_dir_path}/timeline.jsonl" 2>/dev/null; then
      _gen_unlock
      error_exit "cannot append the force_unused timeline event to ${_gen_dir_path}/timeline.jsonl — no authority was sealed." 3
    fi
    echo "[INFO] generation_force_override: every CP1 condition passed — --force bypassed nothing and no waiver was written." >&2
  fi

  # NOW, and only now, the authority itself. Every record that explains it is
  # already durable, so a valid authority can never exist without its trail.
  _gen_write_atomic "$_gen_auth_path" "$_gen_auth_final" || { _gen_unlock; error_exit "cannot write the generation authority receipt at ${_gen_auth_path} — no phase output was produced." 3; }
  echo "[INFO] generation_authority: sealed at ${_gen_auth_path} (self_sha256 ${_gen_auth_self})" >&2
fi

# P074 Step 18 — the decision is made, so the staging window closes here and
# the rest of the run streams to stderr live. Idempotent: the refusal paths
# already flushed before they exited, and the authority-reuse path (which never
# consulted the gate at all) is flushed by this call.
_gen_flush_stderr

# P074 Step 18 — from here on, AID's own generation checks are settled, and the
# answer is read from the SEALED authority rather than from a branch variable:
# it is the same answer for a fresh decision and for a resumed run that never
# re-consulted the gate. A forced authority carries no `pass` verdict, so a
# bypassed run never claims AID's checks passed.
if [[ "$(jq -r '.cp1.verdict // ""' "$_gen_auth_path" 2>/dev/null)" == "pass" ]]; then
  _gen_gate_passed=true
fi

# Bind the transaction to the authority it was decided under. Done inside the
# same lock hold, so the pair can never disagree.
_gen_auth_sha="$(jq -r '.self_sha256 // ""' "$_gen_auth_path" 2>/dev/null)"
_gen_tx_bound="$(jq --arg h "$_gen_auth_sha" --arg u "$(_gen_now)" '.authority_sha256 = $h | .updated_at = $u' "$_gen_tx_path")" \
  || { _gen_unlock; error_exit "cannot bind the generation transaction to its authority" 3; }
_gen_write_atomic "$_gen_tx_path" "$_gen_tx_bound" || { _gen_unlock; error_exit "cannot write the generation transaction manifest at ${_gen_tx_path}" 3; }
}

# _validate_against_schema <document> <schema.json> <label>
#   A small, dependency-free draft-07 subset validator: `required`, `type`,
#   `const`, `pattern`, `minimum`, `minLength`, `additionalProperties: false`,
#   and one level of `additionalProperties: {object schema}` (the transaction's
#   phases map). Enough to make "fails its schema" a real statement about these
#   two documents rather than a spot check, and it fails CLOSED if the schema
#   file itself is missing.
_validate_against_schema() {
  local doc="$1" schema="$2" label="$3"
  [[ -f "$schema" ]] \
    || error_exit "cannot validate the ${label}: schema ${schema} is missing — the verifier is fail-closed and will not accept an unvalidated document." 2
  local errs rc=0
  errs="$(jq -r -n --slurpfile d "$doc" --slurpfile s "$schema" '
    def typeok($v; $t):
      if $t == null then true
      elif ($t | type) == "array" then ([ $t[] | typeok($v; .) ] | any)
      elif $t == "integer" then (($v | type) == "number" and (($v | floor) == $v))
      elif $t == "null" then ($v == null)
      else (($v | type) == $t) end;

    # NOT `$sch.additionalProperties // true`: jq treats FALSE as empty for
    # `//`, so the literal `false` this validator exists to honour would
    # silently become `true` and every unknown property would be allowed.
    def ap($sch): if ($sch | has("additionalProperties")) then $sch.additionalProperties else true end;

    def check($val; $sch; $path):
      ( if ($sch | has("const")) and ($val != $sch.const)
          then ["\($path): must be \($sch.const | tojson)"] else [] end )
      + ( if ($sch.type != null) and (typeok($val; $sch.type) | not)
            then ["\($path): expected \($sch.type | tojson), got \($val | type)"] else [] end )
      + ( if ($sch.pattern != null) and (($val | type) == "string") and (($val | test($sch.pattern)) | not)
            then ["\($path): does not match /\($sch.pattern)/"] else [] end )
      + ( if ($sch.minLength != null) and (($val | type) == "string") and (($val | length) < $sch.minLength)
            then ["\($path): shorter than minLength \($sch.minLength)"] else [] end )
      + ( if ($sch.minimum != null) and (($val | type) == "number") and ($val < $sch.minimum)
            then ["\($path): below minimum \($sch.minimum)"] else [] end )
      + ( if ($val | type) == "object"
            then [ ($sch.required // [])[] as $k | select(($val | has($k)) | not)
                   | "\($path).\($k): required property is missing" ]
            else [] end )
      + ( if ($val | type) == "object" and (ap($sch) == false)
            then [ ($val | keys_unsorted[]) as $k | select((($sch.properties // {}) | has($k)) | not)
                   | "\($path).\($k): property is not allowed (additionalProperties: false)" ]
            else [] end )
      + ( if ($val | type) == "object"
            then ( [ ($val | keys_unsorted[]) as $k | select((($sch.properties // {}) | has($k))) | $k ]
                   | map(. as $k | check($val[$k]; $sch.properties[$k]; "\($path).\($k)")) | add // [] )
            else [] end )
      + ( if ($val | type) == "object" and ((ap($sch) | type) == "object")
            then ( [ ($val | keys_unsorted[]) as $k | select((($sch.properties // {}) | has($k)) | not) | $k ]
                   | map(. as $k | check($val[$k]; ap($sch); "\($path).\($k)")) | add // [] )
            else [] end );

    check($d[0]; $s[0]; "$") | unique | join("; ")
  ' 2>/dev/null)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    error_exit "cannot validate the ${label} ${doc} against ${schema} (unreadable or malformed JSON) — the verifier is fail-closed." 1
  fi
  [[ -z "$errs" ]] && return 0
  error_exit "${label} ${doc} fails its schema ($(jq -r '."$id" // "unknown"' "$schema")): ${errs}" 1
}

# aid_gen_verify_authority <auth> <tx> <plan> <plan_id> <total> <phase> <project_root>
#   The sealed authority verified for one phase (P074 Step 14; moved from
#   aid-plan-to-epic.sh by P111): schema, self-hash, plan bytes, target branch
#   and head, phase range, derivation version, transaction linkage, identity
#   tuple, re-derived ids. Fail-closed (error_exit) on any mismatch.
aid_gen_verify_authority() {
  local auth="$1" tx="$2" plan="$3" plan_id="$4" total="$5" phase="$6" _project_root="$7"
  # FAIL-CLOSED BY DEFINITION: no jq, no verification, no generation.
  command -v jq >/dev/null 2>&1 \
    || error_exit "generation authority verification requires jq, which is unavailable — the verifier is fail-closed by definition and will not fall back to gate-less generation." 2
  [[ -f "$auth" ]] || error_exit "generation authority not readable: ${auth} — run generation through aid-auto-pipeline.sh (never a gate-less fallback)." 1
  [[ -f "$tx" ]]   || error_exit "generation transaction not readable: ${tx} — a transaction is never implicitly recreated mid-run. Run generation through aid-auto-pipeline.sh." 1

  # SCHEMA VALIDATION of BOTH documents against the shipped schemas: every
  # `required` key present with the declared type, and `additionalProperties:
  # false` honoured. Field-presence spot checks are not enough — a document
  # could carry an unknown field, a wrong type, or a missing required key and
  # still pass. The schemas are the source of truth;
  # jq walks them so no external validator is required (and a missing
  # validator can never become a silent skip).
  local schema_dir="${_AID_GEN_SCRIPTS_DIR}/../defaults/schemas"
  _validate_against_schema "$auth" "${schema_dir}/generation-authority.schema.json" "generation authority"
  _validate_against_schema "$tx"   "${schema_dir}/generation-transaction.schema.json" "generation transaction"

  # self_sha256 — canonical JSON (`jq -S -c`) with the hash field NULLED.
  local recorded computed
  recorded="$(jq -r '.self_sha256' "$auth")"
  computed="$(jq -S -c '.self_sha256 = null' "$auth" | sha256sum | awk '{print $1}')"
  [[ "$recorded" == "$computed" ]] \
    || error_exit "generation authority self_sha256 mismatch: recorded ${recorded}, recomputed ${computed} — ${auth} was modified after it was sealed." 1

  # plan bytes
  local plan_now; plan_now="$(sha256sum "$plan" | awk '{print $1}')"
  [[ "$(jq -r '.plan_sha256' "$auth")" == "$plan_now" ]] \
    || error_exit "generation authority plan_sha256 does not match the plan on disk (sealed $(jq -r '.plan_sha256' "$auth"), current ${plan_now}) — the plan was edited after the authority was sealed. Supersede the transaction and regenerate." 1

  # target head — resolved the same way aid-auto-pipeline.sh resolves it.
  local orch tb head_now
  orch="${_AID_GEN_SCRIPTS_DIR}/../defaults/orchestration.yaml"; tb=""
  if [[ -f "$orch" ]] && command -v yq >/dev/null 2>&1; then
    tb="$(yq -r '.lifecycle.target_branch // ""' "$orch" 2>/dev/null || true)"
  fi
  [[ -z "$tb" || "$tb" == "null" ]] && tb="main"
  # The BRANCH itself, not only the commit it points at: an authority sealed
  # against a different integration branch that happens to share a head today
  # would otherwise verify.
  [[ "$(jq -r '.target_branch' "$auth")" == "$tb" ]] \
    || error_exit "generation authority target_branch is '$(jq -r '.target_branch' "$auth")' but this workspace's configured integration branch is '${tb}' — the authority was sealed for a different branch. Supersede the transaction and regenerate." 1
  head_now="$(git -C "$_project_root" rev-parse --verify --quiet "${tb}^{commit}" 2>/dev/null || true)"
  [[ "$(jq -r '.target_head' "$auth")" == "$head_now" ]] \
    || error_exit "generation authority target_head does not match ${tb} (sealed $(jq -r '.target_head' "$auth"), current ${head_now:-<unresolved>}) — the target branch moved after the authority was sealed. Supersede the transaction and regenerate." 1

  # phase range + derivation version
  local sealed_total sealed_pdv
  sealed_total="$(jq -r '.total_phases' "$auth")"
  sealed_pdv="$(jq -r '.phase_derivation_version' "$auth")"
  [[ "$sealed_total" == "$total" ]] \
    || error_exit "generation authority total_phases (${sealed_total}) does not match this invocation's --total (${total})." 1
  [[ "$phase" -ge 1 && "$phase" -le "$sealed_total" ]] \
    || error_exit "phase ${phase} is outside the authorized range 1..${sealed_total}." 1
  [[ "$sealed_pdv" == "$AID_GEN_PHASE_DERIVATION_VERSION" ]] \
    || error_exit "generation authority was sealed under phase_derivation_version ${sealed_pdv} but this script derives phases at version ${AID_GEN_PHASE_DERIVATION_VERSION} — plugin upgraded mid-transaction; supersede and regenerate." 1

  # transaction linkage — a leaked authority is useless outside its own
  # transaction, and a foreign transaction cannot adopt it.
  [[ "$(jq -r '.authority_sha256 // ""' "$tx")" == "$recorded" ]] \
    || error_exit "transaction ${tx} is not bound to this authority (transaction.authority_sha256 $(jq -r '.authority_sha256 // "<null>"' "$tx"), authority.self_sha256 ${recorded}) — a replayed or foreign receipt." 1
  [[ "$(jq -r '.plan_id' "$tx")" == "$(jq -r '.plan_id' "$auth")" ]] \
    || error_exit "transaction plan_id $(jq -r '.plan_id' "$tx") does not match authority plan_id $(jq -r '.plan_id' "$auth")." 1

  # THE FULL IDENTITY TUPLE, both documents. The linkage hash alone only proves
  # the transaction NAMES this authority; a transaction whose own recorded
  # identity has drifted (a hand-edited or stale manifest) would otherwise
  # still pass. Identity is (plan_sha256, target_head,
  # phase_derivation_version, total_phases) — the exact tuple the authority
  # seals — so the two can never disagree about what is being generated.
  local a_id t_id
  a_id="$(jq -r '[.plan_sha256, .target_head, (.phase_derivation_version|tostring), (.total_phases|tostring)] | join("|")' "$auth")"
  t_id="$(jq -r '[.plan_sha256, .target_head, (.phase_derivation_version|tostring), (.total_phases|tostring)] | join("|")' "$tx")"
  [[ "$a_id" == "$t_id" ]] \
    || error_exit "transaction identity '${t_id}' does not match authority identity '${a_id}' (plan_sha256|target_head|phase_derivation_version|total_phases) — the pair describes two different generations. Supersede the transaction and regenerate." 1
  [[ "$t_id" == "${plan_now}|${head_now}|${AID_GEN_PHASE_DERIVATION_VERSION}|${total}" ]] \
    || error_exit "the sealed identity '${t_id}' does not describe this invocation ('${plan_now}|${head_now}|${AID_GEN_PHASE_DERIVATION_VERSION}|${total}')." 1

  # per-phase ids: RE-DERIVED here, NOW, from plan_id+phase+total and compared
  # against what the transaction recorded, so derivation drift between plugin
  # versions is caught at verify time rather than at queue time.
  #
  # THE TWO SIDES REMAIN INDEPENDENT even though one function produces both:
  # the recorded id was written by an earlier process from a possibly different
  # plugin version into a file an actor can edit, and the derived id is
  # computed here from this invocation's arguments. The sealed
  # phase_derivation_version (checked above) is what rules out the remaining
  # case — a transaction recorded under a DIFFERENT derivation — before these
  # ids are compared at all.
  local d_epic d_run r_epic r_run
  d_epic="$(aid_gen_epic_id "$plan_id" "$phase" "$total")"
  d_run="$(aid_gen_run_id "$d_epic")"
  r_epic="$(jq -r --arg p "$phase" '.phases[$p].epic_id // ""' "$tx")"
  r_run="$(jq -r --arg p "$phase" '.phases[$p].run_id // ""' "$tx")"
  [[ -n "$r_epic" ]] \
    || error_exit "transaction ${tx} has no record for phase ${phase} — the phase is not part of this transaction." 1
  [[ "$r_epic" == "$d_epic" ]] \
    || error_exit "phase ${phase} epic_id mismatch: transaction records ${r_epic}, this script derives ${d_epic}." 1
  [[ "$r_run" == "$d_run" ]] \
    || error_exit "phase ${phase} run_id mismatch: transaction records ${r_run}, this script derives ${d_run}." 1

  echo "[INFO] generation_authority: verified ${auth} for phase ${phase}/${total} (plan bytes, ${tb} head, phase range, re-derived ids, transaction linkage) — the CP1 gate is not re-run for this phase." >&2
}

# aid_gen_receipt_check <graph-json> <phase> <plan.json> <plan_abs>
#   The plan.json-versus-source-graph half of the generation receipt (moved
#   from aid-generation-finalize.sh, P111): step count, dependency edges and the
#   binding to the source plan file. Prints the first disagreement and returns 1.
aid_gen_receipt_check() {
  local graph="$1" phase="$2" plan_json="$3" plan_abs="$4"
  local expected_steps actual_step_count expected_step_count actual_ids expected_dependencies actual_dependencies source_plan
  expected_steps="$(jq -r --argjson p "$phase" '[.steps[] | select(.epic == $p) | .step] | join(",")' <<< "$graph")"
  actual_step_count="$(jq '.steps | length' "$plan_json")"
  expected_step_count="$(jq --arg s "$expected_steps" '$s | split(",") | map(select(length > 0)) | length' -n)"
  [[ "$actual_step_count" == "$expected_step_count" ]] || {
    echo "ERROR: phase $phase plan.json step count disagrees with source graph" >&2; return 1;
  }
  actual_ids="$(jq -c '.steps | map(.id)' "$plan_json")"
  expected_dependencies="$(jq -c --argjson phase "$phase" --argjson actual "$actual_ids" '
    [.steps[] | select(.epic == $phase) | .step] as $source_steps |
    [(.edges // [])[]
      | . as $raw_edge
      | {before:($raw_edge.before | capture("^step-(?<n>[0-9]+)$").n | tonumber), after:($raw_edge.after | capture("^step-(?<n>[0-9]+)$").n | tonumber)}
      | . as $edge
      | ($source_steps | index($edge.before)) as $before_index
      | ($source_steps | index($edge.after)) as $after_index
      | select($before_index != null and $after_index != null)
      | {before:$actual[$before_index], after:$actual[$after_index]}
    ] | sort_by(.before, .after)
  ' <<< "$graph")"
  actual_dependencies="$(jq -c '[.dependencies[] | {before, after}] | sort_by(.before, .after)' "$plan_json")"
  [[ "$actual_dependencies" == "$expected_dependencies" ]] || {
    echo "ERROR: phase $phase plan.json dependencies disagree with the source-plan graph" >&2; return 1;
  }
  source_plan="$(jq -r '.source_plan // empty' "$plan_json" 2>/dev/null || true)"
  [[ -n "$source_plan" && "$(realpath "$source_plan" 2>/dev/null || true)" == "$plan_abs" ]] || {
    echo "ERROR: phase $phase plan.json is not bound to this source plan" >&2; return 1;
  }
  return 0
}

# ── public names (P111): the library's interface for plan-run ──────────────
aid_gen_dir()                { _gen_dir "$@"; }
aid_gen_authority_path()     { _gen_authority_path "$@"; }
aid_gen_transaction_path()   { _gen_transaction_path "$@"; }
aid_gen_target_branch()      { _gen_target_branch "$@"; }
aid_gen_target_head()        { _gen_target_head "$@"; }
aid_gen_plan_recorded_mode() { _gen_plan_recorded_mode "$@"; }
aid_gen_lock()               { _gen_lock "$@"; }
aid_gen_unlock()             { _gen_unlock "$@"; }
aid_gen_lock_holder()        { _gen_lock_holder "$@"; }
aid_gen_write_atomic()       { _gen_write_atomic "$@"; }
aid_gen_tx_update()          { _gen_tx_update "$@"; }
