#!/usr/bin/env bash
# =============================================================================
# aid-auto-pipeline.sh — Master orchestration: Plan -> EPIC -> JSON -> Run -> Queue
#
# Usage:
#   ./aid-auto-pipeline.sh \
#     --plan <path> [--queue-mode <chain|separate|custom>] \
#     [--plugin-dir <path>] [--depends-on <E-xxx,E-yyy>] [--streamlined]
#
# --streamlined (optional, default off): passthrough forwarded to every
# aid-json-to-run.sh invocation (Phase N.c), which in turn forwards it to
# aid-fsm.sh init so each EPIC's FSM carries streamlined_mode: true
# (P040 Component D activation; CP3 gap fix).
#
# Runs the full Plan-to-Queue pipeline for all phases of a plan. This is the
# single entry point called by the /aid-plan-epic command. For each phase it:
#   1. aid-plan-to-epic.sh  — Plan.md  -> EPIC.md
#   2. aid-epic-to-json.sh  — EPIC.md  -> plan.json
#   3. aid-json-to-run.sh   — plan.json -> run.md
#   4. aid-queue-add.sh     — EPIC     -> queue.yaml entry
#
# stdout: JSON manifest { plan_id, plan_path, epics, queue_mode, duration_ms }
# stderr: JSON error on failure; progress messages prefixed with [INFO]
#
# Exit codes: 0=success, 1=validation, 2=dependency/missing sub-script, 3=I/O,
#             4=D5 contract gate returned a FAIL verdict (the contract really is
#               malformed), 5=a gate could not be run to a verdict at all (gate
#               crash/kill — the contract is UNKNOWN, not malformed),
#             6=lifecycle/plan-branch boundary
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
check_prerequisites

# =============================================================================
# P074 Step 1 — state-root resolution. Every .aid-o read/write in this file
# AND every state path handed to a subprocess (aid-plan-to-epic / aid-epic-to-
# json / aid-json-to-run / aid-queue-add / aid-generation-finalize) resolves
# under aid_state_root, so a generation started inside a linked worktree
# writes the PRIMARY checkout's workspace, never a forked one. The resolved
# root is exported once as AID_PROJECT_ROOT so the entire child chain shares
# the same canonical root as a belt-and-braces layer (children still resolve
# through aid-roots.sh themselves).
# =============================================================================
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-roots.sh"
_aid_pipeline_state_root="$(aid_state_root)" \
  || error_exit "not inside a git repository — AID needs a repo root" 2
AID_PROJECT_ROOT="$_aid_pipeline_state_root"
export AID_PROJECT_ROOT

# =============================================================================
# P074 EPIC 3 (Steps 13/15/16) — GENERATION IS ONE TRANSACTION
# =============================================================================
# THE FAILURES THIS REPLACES, all three observed live on 2026-08-04:
#   * the CP1 gate ran once PER PHASE, because aid-plan-to-epic.sh calls it
#     unconditionally per invocation and its one-shot override memo is
#     function-local — a 3-phase plan demanded 3 PM artifacts.
#   * a rerun regenerated from phase 1, silently overwrote outputs, and died
#     on the queue duplicate, leaving phases 2..N stranded.
#   * the receipt's per-EPIC `queue_status` stayed at `pending_receipt`
#     forever, because nothing rewrote it after stage 2.
#
# THE MECHANISM. One plan-scoped decision (`generation-authority.json`) and one
# durable manifest (`transaction.json`) live side by side under
# `.aid-o/work/evidence/<plan_id>/generation/`:
#
#   authority    the SEALED CP1 decision for this plan, bound to the exact plan
#                bytes, the target head, and the phase set. Phase generation
#                VERIFIES it (aid-plan-to-epic.sh --generation-authority)
#                instead of re-running the gate.
#   transaction  identity + one record per phase. STATUS IS NEVER STORED: it is
#                derived by re-hashing the recorded outputs and reading queue
#                membership, so the files and the queue are always the truth and
#                the manifest is only the binding that lets a rerun VERIFY
#                rather than blindly redo.
#
# CONCURRENCY ORDERING (the reason the skeleton is written before the gate):
# the transaction lock is acquired BEFORE the lifecycle-manifest ensure — i.e.
# before anything this pipeline does can move the target branch — and the
# IDENTITY-ONLY skeleton is written under it; only then does the CP1 gate run
# and the authority get written, both still under that same serialization
# point. Two concurrent invocations for one plan can therefore never both
# observe "no transaction" and double-run CP1 or race the fixed authority path,
# and neither can move target_head under the other's sealed identity — the
# loser blocks on the flock, then finds a matching identity and a sealed
# authority, and resumes. See "ONE HOLD FOR THE WHOLE GENERATION" below for
# the interleaving that forced the acquisition point this far up.
#
# HONEST CLASSIFICATION (AID-v3 §1). The authority receipt, like every AID
# artifact, is forgeable by a Bash-capable actor. The enforcement is NOT actor
# impossibility: it is the hash/transaction binding (a forged or replayed
# receipt fails verification against the real plan bytes, the real target head
# and the owning transaction) plus audit detectability.
# =============================================================================
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-lock.sh"

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
# aid-cp1-gate.sh's own documented exit-code contract plus its three literal
# pre-verdict error strings:
#
#   rc 1  a genuine CP1 CONDITION verdict — missing/empty/field-less CP1-deep
#         evidence, an adjudicator `verdict: fail|revise`, surviving accepted
#         blockers, a structurally broken adjudicator key, a missing/
#         unverifiable/still-blocking C0 plan review, an exhausted CP1 ledger.
#         All of these are review evidence a PM may deliberately waive.
#         -> FORCEABLE.
#   rc 2  usage error ("Unknown argument") — the gate was mis-invoked and never
#         evaluated a condition. -> HARD.
#   rc 3  I/O error ("Plan file not found") — same: no verdict was rendered.
#         -> HARD.
#   rc 1, but one of the three PLAN-IDENTITY errors the gate raises BEFORE it
#         ever determines risk: no closing frontmatter `---`, no `id:` field,
#         or an `id` failing the path-traversal guard. These are not review
#         evidence at all; forcing past them would seal an authority whose
#         plan identity is the very thing that is broken. -> HARD.
#
# The three hard rc-1 strings are matched literally because they are literal in
# aid-cp1-gate.sh. If that vocabulary changes, this list changes with it — it
# is a mapping of one script's strings, never an inference about them.
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
    3) printf 'the CP1 gate exited 3 (I/O error) — it could not read what it needed and never evaluated a CP1 condition'; return 0 ;;
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
# that lib is sourced far below, AFTER this block, and sourcing it earlier
# would change the committed-source preflight's behaviour as a side effect.
_gen_target_branch() {
  local orch="${SCRIPT_DIR}/../defaults/orchestration.yaml" tb=""
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
  git -C "$_aid_pipeline_state_root" rev-parse --verify --quiet "$(_gen_target_branch)^{commit}" 2>/dev/null || true
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
  m="$(git -C "$_aid_pipeline_state_root" show "$(_gen_target_branch):.aid-lifecycle/manifests/${pid}.yaml" 2>/dev/null \
       | yq -r '.mode // ""' 2>/dev/null || true)"
  printf '%s' "$m"
}

# ── ID derivation ──────────────────────────────────────────────────────────
# THE derivation lives in lib/aid-generation-ids.sh and is shared with
# aid-plan-to-epic.sh (which re-derives these ids at verify time) and
# aid-epic-to-json.sh. The transaction pre-registers every phase's ids in the
# skeleton, before any generator runs, so the verifier compares a RE-DERIVED id
# against a RECORDED one — two independent inputs — and catches derivation
# drift between plugin versions at verify time instead of at queue time.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-generation-ids.sh"
# The plan's ceremony band, for the sealed authority receipt. A LIBRARY call —
# not aid-cp1-gate.sh, whose invocations this pipeline's suites count.
# shellcheck source=lib/aid-plan-band.sh
source "${SCRIPT_DIR}/lib/aid-plan-band.sh"

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

# _gen_phase_stage1_verified <plan_id> <phase>
#   DERIVED status, never a stored enum: the recorded outputs must exist on
#   disk AND re-hash to the recorded values, and the phase's contract-validation
#   evidence must still be a pass. Anything else means "regenerate this phase".
_gen_phase_stage1_verified() {
  local plan_id="$1" phase="$2" txp epic_path plan_json epic_sha plan_sha cv
  txp="$(_gen_transaction_path "$plan_id")"
  [[ -f "$txp" ]] || return 1
  epic_path="$(jq -r --arg p "$phase" '.phases[$p].epic_path // ""' "$txp" 2>/dev/null)"
  plan_json="$(jq -r --arg p "$phase" '.phases[$p].plan_json // ""' "$txp" 2>/dev/null)"
  epic_sha="$(jq -r --arg p "$phase" '.phases[$p].epic_sha256 // ""' "$txp" 2>/dev/null)"
  plan_sha="$(jq -r --arg p "$phase" '.phases[$p].plan_json_sha256 // ""' "$txp" 2>/dev/null)"
  cv="$(jq -r --arg p "$phase" '.phases[$p].contract_validate // ""' "$txp" 2>/dev/null)"
  [[ -n "$epic_path" && -n "$plan_json" && -n "$epic_sha" && -n "$plan_sha" ]] || return 1
  [[ -f "$epic_path" && -f "$plan_json" ]] || return 1
  [[ "$(_gen_sha256_file "$epic_path")" == "$epic_sha" ]] || return 1
  [[ "$(_gen_sha256_file "$plan_json")" == "$plan_sha" ]] || return 1
  [[ -n "$cv" && -f "$cv" ]] || return 1
  jq -e '.result == "pass"' "$cv" >/dev/null 2>&1 || return 1
  return 0
}

# _gen_queue_status <queue_yaml> <epic_id> — the entry's real status, or "".
_gen_queue_status() {
  [[ -f "$1" ]] || return 0
  awk -v want="$2" '
    /^[[:space:]]*-[[:space:]]*epic_id:/ {
      id = $0; sub(/^[^:]*:[[:space:]]*/, "", id); gsub(/"/, "", id)
      cur = (id == want) ? 1 : 0; next
    }
    cur && /^[[:space:]]*status:/ { s = $0; sub(/^[^:]*:[[:space:]]*/, "", s); gsub(/"/, "", s); print s; exit }
  ' "$1" 2>/dev/null
}

# _gen_tx_complete <plan_id> <total> <queue_yaml> <receipt>
#   A transaction is COMPLETE only when every phase verifies on disk, every
#   phase was QUEUED BY THIS TRANSACTION, AND the receipt's queue-status
#   rewrite has happened. The rewrite is the LAST act of a successful run, so a
#   crash before it always leaves the transaction resumable (never a false
#   "already done").
#
#   WHY `queued` AND NOT LIVE QUEUE MEMBERSHIP. The queue is mutable AFTER a
#   generation finishes — entries complete, get archived, get removed. Deriving
#   completeness from the live file therefore makes a finished generation
#   silently un-finish itself the moment its entries are cleaned up, which in
#   turn makes the automatic rollover unreachable (a rollover requires a
#   COMPLETE predecessor, and a predecessor with live entries is exactly what
#   the rollover precondition refuses — the two conditions could never both
#   hold). `queued: true` is this transaction's own durable record that IT
#   queued that entry, written under the lock right after the successful add,
#   and it does not decay. The live queue is still the truth where it matters:
#   the per-phase resume decision and queue-add's ownership test both read it.
_gen_tx_complete() {
  local plan_id="$1" total="$2" queue_yaml="$3" receipt="$4" p
  for p in $(seq 1 "$total"); do
    _gen_phase_stage1_verified "$plan_id" "$p" || return 1
    jq -e --arg p "$p" '.phases[$p].queued == true' \
      "$(_gen_transaction_path "$plan_id")" >/dev/null 2>&1 || return 1
  done
  [[ -f "$receipt" ]] || return 1
  jq -e '[.epics[].queue_status] | length > 0 and (map(. == "pending_receipt") | any | not)' \
    "$receipt" >/dev/null 2>&1 || return 1
  return 0
}

# _gen_identity_of <file> — the identity tuple as one canonical string.
_gen_identity_of() {
  jq -r '[(.plan_sha256 // ""), (.target_head // ""), ((.phase_derivation_version // 0) | tostring), ((.total_phases // 0) | tostring)] | join("|")' "$1" 2>/dev/null
}

# _gen_archive_pair <plan_id> <suffix> — atomically move the transaction and
# the authority to `<name>.<suffix>` siblings sharing ONE epoch, so the pair is
# identifiable. Nothing is ever deleted.
_gen_archive_pair() {
  local plan_id="$1" suffix="$2" txp auth
  txp="$(_gen_transaction_path "$plan_id")"; auth="$(_gen_authority_path "$plan_id")"
  [[ -f "$txp" ]] && { mv -- "$txp" "${txp}.${suffix}" || return 3; }
  [[ -f "$auth" ]] && { mv -- "$auth" "${auth}.${suffix}" || return 3; }
  return 0
}

# =============================================================================
# P074 Step 16 — supersede-generation recovery (a SEPARATE invocation)
# =============================================================================
# Usage: aid-auto-pipeline.sh supersede-generation --plan <path> --reason "<≥20 chars>"
#
# An INCOMPLETE generation transaction can be explicitly archived by a PM with
# an audited reason, unblocking a changed-identity regeneration without ever
# silently mixing artifacts from two derivations. It DELETES NOTHING: cleanup
# of already-created EPIC files, branches and queue entries stays with the
# existing recovery commands (`aid-plan-fsm.sh plan-rollback`, queue removal).
#
# ACTOR RULE, honestly classified (AID-v3 §1): "PM-only" is INSTRUCTION-ONLY —
# nothing here can tell a PM apart from an agent. The audit record IS the
# enforcement surface.
# =============================================================================
_gen_plan_id_of() {
  local fm; fm="$(parse_frontmatter "$1")" || return 1
  local k v
  while IFS='=' read -r k v; do
    [[ "$k" == "id" ]] && { printf '%s\n' "$v"; return 0; }
  done <<< "$fm"
  return 1
}

# ---------------------------------------------------------------------------
# _gen_supersede_audit_preflight <gdir>
#
# WHY A PREFLIGHT AND NOT "WRITE, THEN CHECK". The three records are the
# enforcement surface for this mechanism
# — the enforcement registry says so — so a supersession that cannot be
# recorded must not happen at all. Two of the three sinks are APPEND-ONLY
# (timeline.jsonl, audit-log.jsonl): once a line is in them it cannot be taken
# back, so "archive, then record, then roll back on failure" would either
# leave an unaudited archive or leave a line describing an archive that never
# happened. Probing the sinks first — a zero-byte append, which proves
# openability without committing any content — lets the refusal happen while
# NOTHING has been touched, which is the state the operator can reason about.
#
# Returns 0 when all three sinks are writable; 3 (naming the sink) otherwise.
# ---------------------------------------------------------------------------
_gen_supersede_audit_preflight() {
  local gdir="$1"
  local alog; alog="$(_gen_audit_log_path)"
  local probe=""
  if ! mkdir -p "$gdir" 2>/dev/null; then
    echo "[ERROR] supersede-generation: the evidence directory ${gdir} cannot be created — the supersession record has nowhere to go." >&2
    return 3
  fi
  if ! probe="$(mktemp "${gdir}/.supersede-probe.XXXXXX" 2>/dev/null)"; then
    echo "[ERROR] supersede-generation: ${gdir} is not writable — the supersession record (generation-superseded-<epoch>.json) cannot be written there." >&2
    return 3
  fi
  rm -f "$probe" 2>/dev/null || true
  if ! : >> "${gdir}/timeline.jsonl" 2>/dev/null; then
    echo "[ERROR] supersede-generation: ${gdir}/timeline.jsonl cannot be appended to — the timeline event cannot be recorded." >&2
    return 3
  fi
  if ! mkdir -p "$(dirname "$alog")" 2>/dev/null || ! : >> "$alog" 2>/dev/null; then
    echo "[ERROR] supersede-generation: ${alog} cannot be appended to — the cross-plan audit-log entry cannot be recorded." >&2
    return 3
  fi
  return 0
}

# ---------------------------------------------------------------------------
# _gen_supersede_record_present <file> <plan_id> <epoch>
#
# "Is THIS plan's supersession for THIS epoch already recorded in <file>?"
#
# KEYED ON plan_id AND epoch AND event, never on epoch alone.
# `audit-log.jsonl` is CROSS-PLAN and the epoch is only
# second-resolution, while two plans superseding at the same moment hold
# DIFFERENT per-plan locks and genuinely run concurrently. An epoch-only match
# therefore let plan B read plan A's line as its own, skip its append, and
# report success with no entry of its own — the exact unaudited supersession
# the fail-closed rewrite exists to prevent.
#
# PARSED, NOT PATTERN-MATCHED. `reason` is free operator text on the same
# line, so a substring match could be satisfied by a reason that merely
# CONTAINS the key. Each line is parsed and its fields compared exactly; a
# line that is not valid JSON is skipped rather than aborting the scan, so one
# pre-existing corrupt line in an append-only log cannot make every later
# supersession unverifiable.
# ---------------------------------------------------------------------------
_gen_supersede_record_present() {
  local file="$1" plan_id="$2" epoch="$3"
  [[ -f "$file" ]] || return 1
  jq -e -nR --arg p "$plan_id" --arg e "$epoch" '
    any(inputs;
      ((try fromjson catch null) // null) as $j
      | $j != null
        and ($j.event? == "generation_superseded")
        and ($j.plan_id? == $p)
        and ((($j.epoch? // "") | tostring) == $e))' "$file" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# _gen_supersede_audit <plan_id> <plan_path> <reason> <operator> <epoch> \
#                      <gdir> <txp> <auth> <identity> <generated_json>
#
# Writes the P073 three-record trail for ONE epoch and VERIFIES each record by
# reading it back (aid-audit-log.sh swallows its own write failures by design
# and always returns 0, so its exit code proves nothing — the forced-authority
# path above solves this the same way). IDEMPOTENT: a record that is already
# present for this epoch is verified, not duplicated, which is what makes the
# half-archived retry path produce one trail rather than two.
#
# Returns 0 only when all three records are durable; 3 (naming the missing
# one) otherwise. Callers must treat 3 as fail-closed.
# ---------------------------------------------------------------------------
_gen_supersede_audit() {
  local plan_id="$1" plan_path="$2" reason="$3" operator="$4" epoch="$5"
  local gdir="$6" txp="$7" auth="$8" identity="$9" generated="${10}"
  local rec_file="${gdir}/generation-superseded-${epoch}.json"
  local tl="${gdir}/timeline.jsonl"
  local alog; alog="$(_gen_audit_log_path)"
  local now; now="$(_gen_now)"
  local head_sha; head_sha="$(git -C "$_aid_pipeline_state_root" rev-parse HEAD 2>/dev/null || echo unknown)"

  # The archived names are deterministic, so the record can be rendered
  # whichever side of the rename we are called from: hash the file under
  # whichever of its two names exists right now.
  local arch_tx="${txp}.superseded-${epoch}" arch_auth="" tx_src="" auth_src=""
  if [[ -e "$arch_tx" ]]; then tx_src="$arch_tx"; elif [[ -f "$txp" ]]; then tx_src="$txp"; fi
  if [[ -e "${auth}.superseded-${epoch}" ]]; then
    auth_src="${auth}.superseded-${epoch}"; arch_auth="${auth}.superseded-${epoch}"
  elif [[ -f "$auth" ]]; then
    auth_src="$auth"; arch_auth="${auth}.superseded-${epoch}"
  fi

  # Record 1 — the authoritative forensic artifact.
  if [[ ! -f "$rec_file" ]]; then
    local rec
    rec="$(jq -n \
      --arg schema "aid-generation-supersede/v1" --arg created_at "$now" \
      --arg plan_id "$plan_id" --arg plan_path "$plan_path" \
      --arg reason "$reason" --arg operator "$operator" --arg head_sha "$head_sha" \
      --arg archived_transaction "$arch_tx" \
      --arg archived_authority "$arch_auth" \
      --arg tx_sha256 "$( [[ -n "$tx_src" ]] && _gen_sha256_file "$tx_src" )" \
      --arg auth_sha256 "$( [[ -n "$auth_src" ]] && _gen_sha256_file "$auth_src" )" \
      --arg archived_identity "$identity" \
      --arg current_identity "$(_gen_sha256_file "$plan_path")|$(_gen_target_head)|${AID_GEN_PHASE_DERIVATION_VERSION}" \
      --argjson generated "$generated" \
      '{schema:$schema, created_at:$created_at, plan_id:$plan_id, plan_path:$plan_path,
        reason:$reason, operator:$operator, head_sha:$head_sha,
        archived_transaction:$archived_transaction, archived_authority:(if $archived_authority == "" then null else $archived_authority end),
        transaction_sha256:$tx_sha256, authority_sha256:(if $auth_sha256 == "" then null else $auth_sha256 end),
        archived_identity:$archived_identity,
        current_identity:$current_identity,
        generated:$generated, deletes_nothing:true, actor_semantics:"instruction_only"}')" || rec=""
    [[ -n "$rec" ]] || { echo "[ERROR] supersede-generation: cannot render the supersession record for epoch ${epoch}." >&2; return 3; }
    _gen_write_atomic "$rec_file" "$rec" \
      || { echo "[ERROR] supersede-generation: cannot write the supersession record ${rec_file}." >&2; return 3; }
  fi
  # Read back keyed on THIS plan, for the same reason the JSONL checks are:
  # a record that belongs to another plan is not this plan's evidence, even
  # when it sits at the expected path.
  jq -e --arg p "$plan_id" '.schema == "aid-generation-supersede/v1" and .plan_id == $p' "$rec_file" >/dev/null 2>&1 \
    || { echo "[ERROR] supersede-generation: the supersession record ${rec_file} could not be read back as a valid record for ${plan_id}." >&2; return 3; }

  # Record 2 — the per-plan timeline event.
  if ! _gen_supersede_record_present "$tl" "$plan_id" "$epoch"; then
    printf '%s\n' "$(jq -nc --arg ts "$now" --arg ev "generation_superseded" --arg plan "$plan_id" \
      --arg reason "$reason" --arg op "$operator" --arg epoch "$epoch" --arg id "$identity" \
      '{ts:$ts, event:$ev, plan_id:$plan, reason:$reason, operator:$op, epoch:$epoch, archived_identity:$id}')" \
      >> "$tl" 2>/dev/null || true
  fi
  _gen_supersede_record_present "$tl" "$plan_id" "$epoch" \
    || { echo "[ERROR] supersede-generation: the generation_superseded timeline event for ${plan_id} epoch ${epoch} could not be read back from ${tl}." >&2; return 3; }

  # Record 3 — the cross-plan audit log, VERIFIED BY READING IT BACK.
  if ! _gen_supersede_record_present "$alog" "$plan_id" "$epoch"; then
    bash "${SCRIPT_DIR}/aid-audit-log.sh" append \
      --epic-id "$plan_id" --run-id "supersede-generation" \
      --event "generation_superseded" \
      --plan-id "$plan_id" --reason "$reason" --operator "$operator" \
      --archived-identity "$identity" --epoch "$epoch" \
      --output "$alog" >/dev/null 2>&1 || true
  fi
  _gen_supersede_record_present "$alog" "$plan_id" "$epoch" \
    || { echo "[ERROR] supersede-generation: the generation_superseded entry for ${plan_id} epoch ${epoch} could not be read back from ${alog}." >&2; return 3; }

  printf '%s' "$rec_file"
  return 0
}

_gen_supersede() {
  local sup_plan="" sup_reason=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan)   sup_plan="$2";   shift 2 ;;
      --reason) sup_reason="$2"; shift 2 ;;
      *) error_exit "Unknown argument for supersede-generation: $1 (usage: supersede-generation --plan <path> --reason \"<at least 20 characters>\")" 1 ;;
    esac
  done
  [[ -z "$sup_plan" ]] && error_exit "Missing required argument: --plan" 1
  [[ ! -f "$sup_plan" ]] && error_exit "Plan file not found: $sup_plan" 3
  if [[ "${#sup_reason}" -lt 20 ]]; then
    error_exit "supersede-generation requires --reason with at least 20 characters (got ${#sup_reason}). The audit record is a forensic artifact; a throwaway reason defeats its whole purpose." 1
  fi

  local sup_plan_id; sup_plan_id="$(_gen_plan_id_of "$sup_plan")" \
    || error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1
  # ABSOLUTE paths throughout: aid_state_path deliberately returns a RELATIVE
  # path when the caller already stands at the state root (stdout byte-identity
  # for primary-checkout invocations), and an audit record naming a path that
  # only resolves from one cwd is not a forensic record.
  local gdir txp auth
  gdir="$(realpath -m -- "$(_gen_dir "$sup_plan_id")")"
  txp="${gdir}/transaction.json"
  auth="${gdir}/generation-authority.json"

  # ── THE GENERATION LOCK ───────────────────────────────────────────────────
  # Archiving the transaction and the authority is a MUTATION OF EXACTLY THE
  # STATE the per-plan generation lock protects, so it takes that same lock,
  # for the whole transaction, with the same bounded timeout and the same
  # named refusal. Without it, this command could rename a running pipeline's
  # live transaction and authority out from under it: the generator would then
  # die on its next manifest update ("manifest disappeared mid-run") having
  # already created EPIC files and queue entries that no transaction records —
  # the interleaving the whole one-transaction contract exists to forbid.
  #
  # `_gen_lock` is re-entrant by depth count and this is the only acquire on
  # this path, so ONE trap that calls `_gen_unlock` is the whole release. This
  # runs before the pipeline's own EXIT traps are installed (the dispatch to
  # this function exits before them), so nothing is being overwritten and
  # nothing double-releases.
  if ! _gen_lock "$sup_plan_id"; then
    error_exit "cannot supersede: a generation is in progress for ${sup_plan_id} (holder pid $(_gen_lock_holder "$sup_plan_id")); waited ${AID_GEN_LOCK_TIMEOUT}s for $(_gen_transaction_path "$sup_plan_id").lock and NOTHING was archived. Archiving the transaction and authority while that run is producing phases would strand artifacts no manifest records. Wait for it to finish (or kill that pid) and re-run. Never delete the .lock file." 3
  fi
  trap '_gen_unlock' EXIT

  # HALF-ARCHIVED PAIR RECOVERY (idempotent). A previous call whose second
  # rename failed leaves one `.superseded-<epoch>` sibling with its partner
  # still live. A repeated call COMPLETES exactly that missing rename under the
  # original epoch instead of archiving a fresh one.
  local half_epoch=""
  local cand
  for cand in "${txp}".superseded-* "${auth}".superseded-*; do
    [[ -e "$cand" ]] || continue
    half_epoch="${cand##*.superseded-}"
  done
  if [[ -n "$half_epoch" ]] && { [[ -f "$txp" && ! -e "${txp}.superseded-${half_epoch}" ]] || [[ -f "$auth" && ! -e "${auth}.superseded-${half_epoch}" ]]; }; then
    # SAME AUDIT AS THE NORMAL PATH. Renaming the remaining file and returning
    # SUCCESS with no forensic record, no timeline event and no audit-log entry
    # would make "first call's second rename fails, operator retries" a
    # supported route to a completely UNAUDITED supersession, in the one
    # mechanism whose enforcement surface IS the audit trail. The trail is
    # written here too, under the original epoch, and idempotently: whatever
    # the failed first call already recorded is verified rather than
    # duplicated.
    _gen_supersede_audit_preflight "$gdir" \
      || error_exit "supersede-generation: the supersession cannot be recorded (see above), so the half-archived pair for ${sup_plan_id} was LEFT AS IT IS — nothing was renamed. Repair the audit sinks and re-run; the retry completes the rename and writes the trail under the original epoch ${half_epoch}." 3
    [[ -f "$txp"  && ! -e "${txp}.superseded-${half_epoch}"  ]] && mv -- "$txp"  "${txp}.superseded-${half_epoch}"
    [[ -f "$auth" && ! -e "${auth}.superseded-${half_epoch}" ]] && mv -- "$auth" "${auth}.superseded-${half_epoch}"

    local half_src="${txp}.superseded-${half_epoch}"
    [[ -f "$half_src" ]] || half_src="$txp"
    local half_identity="" half_generated="[]"
    if [[ -f "$half_src" ]]; then
      half_identity="$(_gen_identity_of "$half_src")"
      half_generated="$(jq -c '[.phases | to_entries[] | {phase: .key, epic_id: .value.epic_id, run_id: .value.run_id, epic_path: (.value.epic_path // null), generated: ((.value.epic_sha256 // "") != "")}] | sort_by(.phase)' "$half_src" 2>/dev/null || echo '[]')"
    fi
    local half_rec=""
    half_rec="$(_gen_supersede_audit "$sup_plan_id" "$sup_plan" "$sup_reason" "${USER:-unknown}" \
      "$half_epoch" "$gdir" "$txp" "$auth" "$half_identity" "$half_generated")" \
      || error_exit "supersede-generation: the half-archived pair for ${sup_plan_id} was completed under epoch ${half_epoch}, but the supersession could NOT be fully recorded (see above). The archive is real and unaudited: repair the audit sinks and re-run — the retry is idempotent and writes only the missing records." 3

    echo "[INFO] supersede-generation: completed the missing rename of a half-archived pair under the original epoch ${half_epoch} — no fresh epoch was created." >&2
    echo "  audit record: ${half_rec}" >&2
    printf 'superseded:%s:%s\n' "$sup_plan_id" "$half_epoch"
    return 0
  fi

  [[ -f "$txp" ]] || error_exit "Nothing to supersede: no generation transaction exists at ${txp} for ${sup_plan_id}." 1

  # The flag must match the archived identity — never a cross-plan archive.
  local recorded_plan; recorded_plan="$(jq -r '.plan_id // ""' "$txp" 2>/dev/null || true)"
  if [[ -n "$recorded_plan" && "$recorded_plan" != "$sup_plan_id" ]]; then
    error_exit "--plan names ${sup_plan_id} but the transaction at ${txp} records ${recorded_plan} — refusing a cross-plan archive. Pass the plan the transaction belongs to." 1
  fi

  local sup_total sup_queue sup_receipt
  sup_total="$(jq -r '.total_phases // 0' "$txp" 2>/dev/null || echo 0)"
  sup_queue="$(aid_state_path ".aid-o/config/queue.yaml")"
  sup_receipt="${gdir}/receipt.json"
  if _gen_tx_complete "$sup_plan_id" "$sup_total" "$sup_queue" "$sup_receipt"; then
    error_exit "The generation transaction for ${sup_plan_id} is COMPLETE — a complete transaction needs no supersession. A changed plan starts fresh by itself: the pipeline's automatic rollover archives the completed authority/transaction pair to '.completed-<epoch>' siblings on the next run with a different identity. Nothing was archived." 1
  fi

  local epoch; epoch="$(date -u +%s)"
  local operator="${USER:-unknown}"
  local identity; identity="$(_gen_identity_of "$txp")"
  local generated
  generated="$(jq -c '[.phases | to_entries[] | {phase: .key, epic_id: .value.epic_id, run_id: .value.run_id, epic_path: (.value.epic_path // null), generated: ((.value.epic_sha256 // "") != "")}] | sort_by(.phase)' "$txp" 2>/dev/null || echo '[]')"

  # AUDIT BEFORE ARCHIVE. The audit trail is this mechanism's
  # enforcement surface, so an unrecordable supersession must not happen.
  # Two of the three sinks are append-only, so the check that CAN fail
  # harmlessly is a preflight, not a rollback — see
  # _gen_supersede_audit_preflight.
  _gen_supersede_audit_preflight "$gdir" \
    || error_exit "supersede-generation: the supersession cannot be recorded (see above), so NOTHING was archived — the transaction and authority for ${sup_plan_id} are exactly as they were. The audit record is this command's enforcement surface; an unrecordable supersession is refused, not performed silently. Repair the sink named above and re-run." 3

  # RENAME, retry the second once, then report the exact mv to finish.
  mv -- "$txp" "${txp}.superseded-${epoch}" \
    || error_exit "cannot archive the transaction manifest: mv ${txp} ${txp}.superseded-${epoch} failed. Nothing was changed." 3
  if [[ -f "$auth" ]] && ! mv -- "$auth" "${auth}.superseded-${epoch}" 2>/dev/null; then
    sleep 1
    if ! mv -- "$auth" "${auth}.superseded-${epoch}" 2>/dev/null; then
      error_exit "HALF-ARCHIVED: the transaction is archived at ${txp}.superseded-${epoch} but the authority could not be moved. Finish it with: mv '${auth}' '${auth}.superseded-${epoch}' — or simply re-run supersede-generation, which completes exactly this missing rename under the same epoch." 3
    fi
  fi

  # AUDIT — the P073 three-record pattern, every record FAIL-CLOSED and
  # VERIFIED BY READING IT BACK (the shape the forced-authority path uses).
  # The three writes used to be `|| true` while the success message still
  # printed an audit-record path, so a supersession could report a forensic
  # artifact that did not exist.
  local rec_file=""
  rec_file="$(_gen_supersede_audit "$sup_plan_id" "$sup_plan" "$sup_reason" "$operator" \
    "$epoch" "$gdir" "$txp" "$auth" "$identity" "$generated")" \
    || error_exit "supersede-generation: the pair for ${sup_plan_id} is archived under epoch ${epoch}, but the supersession could NOT be fully recorded (see above) — the archive is real and unaudited. Repair the sink named above and re-run supersede-generation: it is idempotent, completes nothing that is already done, and writes only the missing records under the same epoch." 3

  echo "[INFO] supersede-generation: archived the incomplete transaction for ${sup_plan_id} (epoch ${epoch})." >&2
  echo "  ${txp}.superseded-${epoch}" >&2
  [[ -e "${auth}.superseded-${epoch}" ]] && echo "  ${auth}.superseded-${epoch}" >&2
  echo "  audit record: ${rec_file}" >&2
  echo "  What this generation had already produced (nothing was deleted):" >&2
  jq -r '.[] | "    phase \(.phase): \(.epic_id) / \(.run_id) — \(if .generated then "generated" else "not generated" end)\(if .epic_path then " (\(.epic_path))" else "" end)"' <<< "$generated" >&2
  echo "  Cleanup of already-created EPIC files, branches and queue entries is NOT done here: use 'aid-plan-fsm.sh plan-rollback' and the queue-removal path for that." >&2
  printf 'superseded:%s:%s\n' "$sup_plan_id" "$epoch"
  return 0
}

if [[ "${1:-}" == "supersede-generation" ]]; then
  shift
  _gen_supersede "$@"
  exit $?
fi

# =============================================================================
# Parse CLI arguments
# =============================================================================
plan=""
queue_mode="chain"
plugin_dir=""
custom_depends=""
streamlined=false   # P040 Component D passthrough → aid-json-to-run.sh → aid-fsm.sh init (CP3 gap fix)
force_init_reason="" # PM-authorized, audited cross-plan force-init reason → aid-json-to-run.sh → aid-fsm.sh init (waives ONLY the false-positive cross-plan ca-review-complete precondition)
force_generation=false # P074 Step 13 — --force over the plan-level CP1 gate
force_reason=""        # P074 Step 13 — --reason for the above (>= 20 chars)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)         plan="$2";           shift 2 ;;
    --queue-mode)   queue_mode="$2";     shift 2 ;;
    --plugin-dir)   plugin_dir="$2";     shift 2 ;;
    --depends-on)   custom_depends="$2"; shift 2 ;;
    --streamlined)  streamlined=true;    shift 1 ;;
    --force-init-reason) force_init_reason="$2"; shift 2 ;;
    # P074 Step 13 — PUBLIC, P073-style force over the plan-level CP1 gate.
    # Invocation-scoped (never an env var, never a stored grant), audited with
    # the full three-record pattern. The PM typing this command IS the
    # authorization; that is instruction-only for actors, and the audit records
    # are what make it detectable.
    --force)        force_generation=true; shift 1 ;;
    --reason)       force_reason="$2";     shift 2 ;;
    *)
      error_exit "Unknown argument: $1" 1
      ;;
  esac
done

# =============================================================================
# Validate required arguments
# =============================================================================
[[ -z "$plan" ]] && error_exit "Missing required argument: --plan" 1
[[ ! -f "$plan" ]] && error_exit "Plan file not found: $plan" 3

# P074 Step 13 — the force contract, validated BEFORE anything else happens.
# Same message shape as P073's _pfsm_handle_force: the receipt is a forensic
# record, and an empty or throwaway reason defeats its whole purpose.
if [[ "$force_generation" == true && "${#force_reason}" -lt 20 ]]; then
  error_exit "--force requires --reason with at least 20 characters (got ${#force_reason}). The force receipt is a forensic record; an empty or throwaway reason defeats its whole purpose." 1
fi
if [[ "$force_generation" != true && -n "$force_reason" ]]; then
  error_exit "--reason was given without --force — it would record nothing. Pass both, or neither." 1
fi

# P074 Step 18 — stage stderr from here (the first point at which this run can
# emit progress chatter) until the CP1 decision is known. The EXIT trap
# guarantees a flush on every path that leaves the window without one; it is
# replaced later by _gen_on_exit, which flushes too.
trap '_gen_flush_stderr' EXIT
_gen_stage_stderr

# =============================================================================
# P073 Step 11 — committed-source preflight (P083)
# =============================================================================
# The only check here used to be "the file exists on disk", and cmd_plan_start
# never sees a path at all. The clean-worktree preflight runs with
# `--untracked-files=no`, so a plan that was never `git add`ed is invisible to
# it too. Generation therefore created a plan branch, task branches and a
# lifecycle manifest from bytes that exist ONLY in one worktree — and the
# manifest's source_plan_sha then bound the whole plan to a source nobody else
# could ever read. That is P083.
#
# SCOPE: the check is about THIS WORKSPACE's repository and the plan's
# relationship to its target branch. Resolving the repo from the plan's own
# directory and hard-failing when no target branch resolves would refuse every
# plan living outside the workspace (the test fixtures, and any shared plan
# library) — an over-block the loosening directive forbids. Three cases are therefore skipped WITH A LOG LINE rather
# than refused, because none of them has a target-branch relationship to
# verify: the workspace is not a git repo, the plan is not inside it, or the
# plan is gitignored. In each the manifest's source_plan_sha IS the binding.
# Containment is decided on the LEXICAL path, with the symlink case refused
# explicitly rather than exempted: deciding it on the canonical path let
# `repo/plans/x.md -> /tmp/x.md` resolve outside the repo and take the "lives
# outside" skip, so a plan invoked through a repository path could still bind
# the lifecycle to local-only bytes.
_p083_repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
_p083_plan_abs="$(realpath -m --no-symlinks -- "$plan" 2>/dev/null || echo "$plan")"
_p083_plan_real="$(realpath -m -- "$plan" 2>/dev/null || echo "$_p083_plan_abs")"
if [[ -z "$_p083_repo_root" ]]; then
  echo "[INFO] plan_source_binding: source_plan_sha (this workspace is not a git repository)" >&2
elif [[ "$_p083_plan_abs" != "$_p083_repo_root"/* ]]; then
  echo "[INFO] plan_source_binding: source_plan_sha (${plan} lives outside this workspace's repository, so it has no target-branch relationship to verify)" >&2
elif [[ "$_p083_plan_real" != "$_p083_plan_abs" && "$_p083_plan_real" != "$_p083_repo_root"/* ]]; then
  error_exit "PRECONDITION FAIL: ${plan} is a repository path but resolves through a symlink to ${_p083_plan_real}, outside the repository — the lifecycle would bind source_plan_sha to bytes this repository does not contain. Commit the plan inside the repository, or gitignore it and accept the source_plan_sha binding deliberately." 1
elif git check-ignore -q -- "$_p083_plan_abs" 2>/dev/null; then
  # DELIBERATE, not a loophole: this very repository gitignores `.aid-o/plans/`,
  # so a hard tracked-only rule would break the plugin's own dogfood workflow.
  echo "[INFO] plan_source_binding: source_plan_sha (${plan} is gitignored — the committed manifest's source_plan_sha is the binding, not a tracked blob)" >&2
else
  # `_gen_target_branch`, NOT `aid_target_branch`: lib/aid-lifecycle.sh is not
  # sourced until far below this preflight (see the _gen_target_branch header
  # at the top of this file, which exists for exactly this reason). Calling the
  # lib name here resolved to "command not found" -> empty -> every TRACKED
  # plan was refused with "target branch '<unresolved>' does not exist", while
  # the check it was written to perform — comparing the tracked plan against
  # the target branch's copy — never ran at all. It went unnoticed because this
  # repository gitignores `.aid-o/plans/`, so the dogfood path takes the
  # gitignored branch above and never reaches this line.
  _p083_target="$(_gen_target_branch 2>/dev/null || echo "")"
  _p083_rel="${_p083_plan_abs#"$_p083_repo_root"/}"
  if [[ -z "$_p083_target" ]] || ! git rev-parse --verify --quiet "$_p083_target" >/dev/null 2>&1; then
    # No integration branch exists to verify against. Refuse only when the plan
    # is already TRACKED — then it is genuinely part of the repository's history
    # and a missing target branch is the fresh-repo case the plan names. An
    # UNTRACKED plan in a workspace with no target branch has nothing to be
    # checked against at all, and refusing it would block every such workspace
    # (found when this broke the branch-restore fixtures).
    if git ls-files --error-unmatch -- "$_p083_plan_abs" >/dev/null 2>&1; then
      error_exit "PRECONDITION FAIL: source plan ${_p083_rel} is tracked but the target branch '${_p083_target:-<unresolved>}' does not exist — create and commit the target branch first, or gitignore the plan if it is deliberately unshared." 1
    fi
    echo "[INFO] plan_source_binding: source_plan_sha (no target branch '${_p083_target:-<unresolved>}' exists to verify ${_p083_rel} against)" >&2
    _p083_target=""
  fi
  if [[ -n "$_p083_target" ]]; then
    if ! git cat-file -e "${_p083_target}:${_p083_rel}" 2>/dev/null \
       || ! git show "${_p083_target}:${_p083_rel}" 2>/dev/null | cmp -s - "$_p083_plan_abs"; then
      error_exit "PRECONDITION FAIL: source plan is not committed on ${_p083_target} (or differs from the worktree copy) — commit the plan on ${_p083_target} and rerun generation." 1
    fi
    echo "[INFO] plan_source_binding: committed blob ${_p083_target}:${_p083_rel} matches the worktree copy byte for byte" >&2
  fi
fi

# =============================================================================
# Verify all 4 sub-scripts exist and are executable
# =============================================================================
sub_scripts=(
  "aid-plan-to-epic.sh"
  "aid-epic-to-json.sh"
  "aid-generation-finalize.sh"
  "aid-json-to-run.sh"
  "aid-queue-add.sh"
)

for script_name in "${sub_scripts[@]}"; do
  script_path="${SCRIPT_DIR}/${script_name}"
  if [[ ! -f "$script_path" ]]; then
    error_exit "Sub-script not found: $script_path" 2
  fi
  if [[ ! -x "$script_path" ]]; then
    error_exit "Sub-script not executable: $script_path (run: chmod +x $script_path)" 2
  fi
done

# =============================================================================
# Resolve plugin directory
# =============================================================================
if [[ -z "$plugin_dir" ]]; then
  # Auto-detect: walk up from SCRIPT_DIR to find the plugin root
  # SCRIPT_DIR is .../plugins/aid-orchestrator/scripts, so parent is the plugin dir
  plugin_dir="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

if [[ ! -d "$plugin_dir" ]]; then
  error_exit "Plugin directory not found: $plugin_dir" 3
fi

# =============================================================================
# Resolve template and config paths
# =============================================================================
epic_template="${plugin_dir}/defaults/templates/epic.md"
plan_schema="${plugin_dir}/defaults/templates/plan.schema.json"

# Find a run template: prefer run-new-feature.md, fall back to any run-*.md
run_template="${plugin_dir}/defaults/templates/run-new-feature.md"
if [[ ! -f "$run_template" ]]; then
  # Find the first available run-*.md template
  run_template=""
  for candidate in "${plugin_dir}"/defaults/templates/run-*.md; do
    if [[ -f "$candidate" ]]; then
      run_template="$candidate"
      break
    fi
  done
  if [[ -z "$run_template" ]]; then
    error_exit "No run template found in ${plugin_dir}/defaults/templates/run-*.md" 2
  fi
fi

# Validate required templates exist
[[ ! -f "$epic_template" ]] && error_exit "EPIC template not found: $epic_template. Run /aid-init to deploy templates." 2
[[ ! -f "$plan_schema" ]]   && error_exit "Plan schema not found: $plan_schema" 2

# Config paths (in the workspace, not the plugin) — state-root resolved (P074)
counter_yaml="$(aid_state_path ".aid-o/config/counter.yaml")"
queue_yaml="$(aid_state_path ".aid-o/config/queue.yaml")"

# Ensure workspace directories exist
mkdir -p "$(aid_state_path ".aid-o/tasks")" 2>/dev/null || error_exit "Cannot create .aid-o/tasks directory" 3
mkdir -p "$(aid_state_path ".aid-o/work/evidence")" 2>/dev/null || error_exit "Cannot create .aid-o/work/evidence directory" 3
mkdir -p "$(aid_state_path ".aid-o/work/runs")" 2>/dev/null || error_exit "Cannot create .aid-o/work/runs directory" 3
mkdir -p "$(dirname "$queue_yaml")" 2>/dev/null || error_exit "Cannot create queue directory" 3

# =============================================================================
# Parse plan frontmatter — extract plan_id
# =============================================================================
frontmatter="$(parse_frontmatter "$plan")"

plan_id=""
while IFS='=' read -r key val; do
  case "$key" in
    id) plan_id="$val" ;;
  esac
done <<< "$frontmatter"

[[ -z "$plan_id" ]] && error_exit "Plan file missing 'id' field in frontmatter. Expected: id: P{NNN}" 1

# =============================================================================
# Detect phase count from plan
#
# Strategy:
#   1. Search for explicit EPIC/Phase markers: **EPIC N:...** or **Phase N...**
#   2. If markers found: count them -> total phases
#   3. If no markers: count ### Step headers, divide into groups of ~5-7
# =============================================================================

# Count explicit EPIC/Phase markers
marker_count=0
while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ "$line" =~ ^\*\*EPIC[[:space:]]+[0-9]+ ]] || [[ "$line" =~ ^\*\*Phase[[:space:]]+[0-9]+ ]]; then
    marker_count=$(( marker_count + 1 ))
  fi
done < "$plan"

# Count step headers — accept multiple formats:
#   ### Step N: ...       (preferred, level 3)
#   ## Task N: ...        (common alternative, level 2)
#   ## Step N: ...        (level 2 variant)
step_count=0
while IFS= read -r line; do
  line="${line//$'\r'/}"
  if [[ "$line" =~ ^###?[[:space:]]+(Step|Task)[[:space:]]+[0-9]+ ]]; then
    step_count=$(( step_count + 1 ))
  fi
done < "$plan"

# Determine total phases
total_phases=0
if [[ "$marker_count" -gt 0 ]]; then
  total_phases="$marker_count"
  echo "[INFO] Detected $total_phases phase(s) from explicit EPIC/Phase markers" >&2
elif [[ "$step_count" -gt 0 ]]; then
  # Divide steps into groups of ~5-7 (target 6 steps per phase)
  steps_per_phase=6
  total_phases=$(( (step_count + steps_per_phase - 1) / steps_per_phase ))
  # Ensure at least 1 phase
  [[ "$total_phases" -lt 1 ]] && total_phases=1
  echo "[INFO] No phase markers found. $step_count steps divided into $total_phases phase(s) (~$steps_per_phase steps each)" >&2
else
  # Check for a high-level steps table (rows in a markdown table under ## High-Level Steps)
  table_row_count="$(awk '
    BEGIN { in_table = 0; count = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^## (High-Level Steps|Implementation Steps)/) { in_table = 1; next }
      if (in_table && $0 ~ /^##[^#]/) exit
      if (in_table && $0 ~ /^\|/ && $0 !~ /^\|[[:space:]]*[-]+/ && $0 !~ /^\|[[:space:]]*(#|Phase|Step)/) {
        count++
      }
    }
    END { print count }
  ' "$plan")"

  if [[ "$table_row_count" -gt 0 ]]; then
    # Each table row = 1 phase (if rows are phase-level) or group them
    if [[ "$table_row_count" -le 7 ]]; then
      total_phases="$table_row_count"
    else
      total_phases=$(( (table_row_count + 5) / 6 ))
    fi
    echo "[INFO] Detected $total_phases phase(s) from $table_row_count table rows" >&2
  fi
fi

if [[ "$total_phases" -eq 0 ]]; then
  error_exit "Cannot detect any phases in plan file. Expected EPIC/Phase markers, ### Step N:, or ## Task N: headers." 1
fi


# =============================================================================
# Start timer
#
# Portable millisecond timing: try date +%s%3N (GNU coreutils), fall back to
# SECONDS variable with second precision.
# =============================================================================
use_ms_timer=true
start_ms="$(date +%s%3N 2>/dev/null)" || use_ms_timer=false

if [[ "$use_ms_timer" == false ]] || [[ ! "$start_ms" =~ ^[0-9]+$ ]]; then
  # Fallback: use bash SECONDS variable (second precision)
  use_ms_timer=false
  SECONDS=0
fi

# =============================================================================
# Main pipeline loop — process each phase
# =============================================================================
epics_json="[]"
prev_epic_id=""

echo "[INFO] Starting pipeline for plan $plan_id ($total_phases phase(s), queue-mode: $queue_mode)" >&2

# P074 generation-integrity: the default path is two-stage.  A complete EPIC
# package is generated and sealed before any FSM init or queue mutation. The
# old interleaved behavior remains opt-in solely for legacy recovery; it is not
# selected by normal callers.
two_stage=true
[[ "${AID_PIPELINE_LEGACY_INTERLEAVED:-0}" == "1" ]] && two_stage=false

_generation_depends_for_epic() {
  local epic_file="$1" previous="$2" result="" raw ext
  case "$queue_mode" in
    chain) result="$previous" ;;
    separate) result="" ;;
    custom) result="$custom_depends" ;;
  esac
  raw="$(awk '
    BEGIN { in_qi = 0 }
    { gsub(/\r$/, ""); if ($0 ~ /^### Queue Implications/) { in_qi=1; next }
      if (in_qi && ($0 ~ /^##/ || $0 ~ /^---/)) exit
      if (in_qi && $0 ~ /^depends_on:/) { sub(/^depends_on:[[:space:]]*/, "", $0); gsub(/[\[\]]/, "", $0); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if ($0 != "") print; exit } }
  ' "$epic_file" 2>/dev/null || true)"
  if [[ -n "$raw" ]]; then
    IFS=',' read -ra _generation_exts <<< "$raw"
    for ext in "${_generation_exts[@]}"; do
      ext="$(echo "$ext" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$ext" || "$ext" == "$previous" ]] && continue
      if [[ -z "$result" ]]; then result="$ext"; elif ! echo ",$result," | grep -q ",$ext,"; then result="${result},${ext}"; fi
    done
  fi
  printf '%s\n' "$result"
}

# =============================================================================
# ONE HOLD FOR THE WHOLE GENERATION (P074 Step 15)
# =============================================================================
# The lock is NOT released once the authority is sealed — holding only the
# skeleton/gate/authority critical section is not enough. The phase work itself
# is NOT idempotent-under-concurrency: two same-identity
# invocations both pass the resume check, then race on the counter, on FSM
# init, on run rendering, and — worst — one hashes an EPIC/plan.json the other
# is in the middle of replacing, recording a hash for bytes that no longer
# exist. "Both verify and converge" holds for the pure re-derivation, never for
# those steps.
#
# WHERE THE HOLD STARTS, AND WHY IT IS HERE RATHER THAN AT THE SEAL. The second
# cut took the lock just before the transaction skeleton — after the lifecycle
# block below. That still lost the race, reproducibly (~1 run in 2), because
# the lifecycle block MUTATES THE TARGET BRANCH: `aid_lifecycle_ensure_manifest`
# commits the manifest, and the mode stamp is a second isolated commit right
# after it. target_head is part of the transaction identity AND is re-checked
# by every phase against the sealed authority. With the hold starting after
# those commits, two invocations interleaved like this:
#
#   A ensure_manifest -> commits, target_head H0 -> H1
#   B reads target_head = H1 and seals its identity on it
#   A mode-stamp commit,          target_head H1 -> H2
#   B takes the lock, writes the skeleton bound to the now-stale H1
#   B's first phase: sealed H1 != current H2  -> "the target branch moved"
#   A takes the lock, derives H2, finds B's H1 transaction -> identity mismatch
#
# Both runs die, no generation happens, and the surviving artifact is a
# transaction bound to a head that no longer exists. Neither run did anything
# wrong under its own hold — the mutation and the read that the hold exists to
# order both happened OUTSIDE it. So the hold starts before the lifecycle
# ensure: the branch-mutating commits, the target_head read, the seal and all
# phase work are one critical section. The loser blocks, and by the time it
# enters, the manifest is already durable (ensure is then a no-op), target_head
# is stable, and its identity matches the winner's — the resume path.
#
# So the hold spans lifecycle ensure -> skeleton -> gate -> authority -> every
# phase -> stage 2 -> receipt rewrite, and is released by an EXIT trap (which
# also covers every error_exit path and any signal-driven death). A second
# invocation blocks for at most AID_GEN_LOCK_TIMEOUT seconds and then refuses
# by name, telling the operator which pid holds it — never interleaves.
# =============================================================================

# P074 Step 18 — the two facts the EXIT hook needs, and nothing more.
#   _gen_gate_passed        AID's own CP1 decision for this run is a PASS (a
#                           fresh passing gate, or a reused authority whose
#                           sealed verdict is `pass`). A FORCED authority does
#                           NOT set it: AID's checks did not pass there.
#   _gen_aid_owned_failure  this run is dying on an AID gate of its own (today:
#                           the D5 contract-validation gate), so the
#                           not-an-AID-gate note would be a lie.
_gen_gate_passed=false
_gen_aid_owned_failure=false

# _gen_on_exit <rc> — release the generation lock, then, when this run is dying
# on something that is NOT one of AID's own gates AFTER AID's own checks had
# passed, append one line saying so. The failing subprocess's stderr already
# reached the terminal verbatim (it is inherited, never captured), so this adds
# information and rewrites nothing. Before the gate passes the note never
# fires: AID cannot claim its checks passed when they had not run yet.
_gen_on_exit() {
  local rc="${1:-0}"
  # Anything still staged goes out BEFORE the note, so the note is never
  # printed above the error it is talking about.
  _gen_flush_stderr
  _gen_unlock
  if [[ "$rc" -ne 0 && "$_gen_gate_passed" == true && "$_gen_aid_owned_failure" != true ]]; then
    printf "note: AID's own checks passed — this failure is not an AID gate\n" >&2
  fi
}

trap '_gen_on_exit $?' EXIT
if ! _gen_lock "$plan_id"; then
  error_exit "generation already in progress for ${plan_id} (holder pid $(_gen_lock_holder "$plan_id")); waited ${AID_GEN_LOCK_TIMEOUT}s for $(_gen_transaction_path "$plan_id").lock and nothing was generated. Wait for that run to finish and re-run — a rerun resumes rather than regenerates. If the holder is gone, the lock is already free (flock drops on process death); raise AID_GEN_LOCK_TIMEOUT if the other run is simply slow. Never delete the .lock file — that lets a second writer in alongside the first." 3
fi

# IMP-232 v2.58.1: create the plan lifecycle manifest at the official scaffold, as
# part of the normal commit flow (repo identity + manifest committed together via
# an isolated index — the user's index is never touched). This is what makes the
# durable denominator exist BEFORE closure, so a new plan never waits for a manual
# reconcile to have a lifecycle manifest. Enforcement is split by plan opt-in:
# lifecycle_strict plans FAIL-CLOSED if the manifest is not durable; legacy plans
# proceed under a loud, audited migration (never a silent skip).
if [[ -f "${SCRIPT_DIR}/lib/aid-lifecycle.sh" ]]; then
  # shellcheck source=lib/aid-lifecycle.sh
  source "${SCRIPT_DIR}/lib/aid-lifecycle.sh"
  # P068 Step 7 — the mode a NEW plan is created with, resolved from
  # defaults/policies/plan-boundary-policy.yaml and GUARDED on the project's
  # gate_profiles table existing. Resolved BEFORE the manifest write, from the
  # policy rather than from the manifest, which avoids the chicken-and-egg of
  # asking a file that has not been written yet what mode it declares.
  _pb_mode_row="$(bash "${SCRIPT_DIR}/aid-plan-fsm.sh" __default-mode --project-root "." 2>/dev/null || true)"
  _pb_default_mode="${_pb_mode_row%%$'\t'*}"
  _pb_mode_reason="${_pb_mode_row#*$'\t'}"
  [[ -z "$_pb_default_mode" ]] && { _pb_default_mode="legacy_epic_release_mode"; _pb_mode_reason="resolver_unavailable"; }
  if [[ "$_pb_default_mode" == "legacy_epic_release_mode" && "$_pb_mode_reason" == *"no_gate_profiles"* ]]; then
    echo "[INFO] plan_branch_unavailable: no_gate_profiles — $plan_id is created in legacy_epic_release_mode. Run the gate-profile bootstrap to enable the plan-final model." >&2
    mkdir -p "$(aid_state_path ".aid-o/work")" 2>/dev/null \
      && printf '{"plan_id":"%s","event":"plan_branch_unavailable","reason":"no_gate_profiles"}\n' "$plan_id" >> "$(aid_state_path ".aid-o/work/lifecycle-migration.log")" 2>/dev/null || true
  fi

  _lc_rc=0; aid_lifecycle_ensure_manifest "$plan_id" "." >/dev/null 2>&1 || _lc_rc=$?
  if [[ "$_lc_rc" -eq 0 ]]; then
    # Stamp the resolved mode into the manifest that was just made durable, then
    # make the STAMP durable too. ensure_manifest commits what it wrote, so a
    # bare `yq -i` here would leave the mode in the worktree only while the
    # COMMITTED copy — the authority every later reader consults, including
    # _fsm_declared_plan_mode, which reads target_branch's tree — carried none.
    # A mode that exists only in an uncommitted file is not a declaration.
    if ! yq -i ".mode = \"${_pb_default_mode}\"" ".aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null; then
      error_exit "Lifecycle manifest for $plan_id was created but its mode could not be stamped — a manifest with no declared mode cannot prove which release model the plan follows." 6
    fi
    # ensure_manifest returns early once the manifest is durable, and rebuilds
    # it from the plan when it is not — either way it neither knows nor preserves
    # `mode`. The stamp therefore has to be committed here, on its own, through
    # the same isolated-index path the lifecycle layer uses (the caller's index
    # is never touched). Verified by reading the committed copy back: a stamp
    # that cannot be read from target_branch's tree is not a declaration.
    _lc_rc2=0
    _aid_lc_isolated_commit "." "lifecycle: declare mode ${_pb_default_mode} for ${plan_id}" \
      ".aid-lifecycle/manifests/${plan_id}.yaml" >/dev/null 2>&1 || _lc_rc2=$?
    _pb_committed_mode="$(git show "$(aid_target_branch):.aid-lifecycle/manifests/${plan_id}.yaml" 2>/dev/null | yq -r '.mode // ""' 2>/dev/null || true)"
    if [[ "$_pb_committed_mode" != "$_pb_default_mode" ]]; then
      if [[ "$_pb_default_mode" == "plan_branch" && "${AID_LIFECYCLE_MIGRATION:-}" != "1" ]]; then
        error_exit "The mode stamp for $plan_id is not readable from $(aid_target_branch)'s committed manifest (rc=$_lc_rc2, read='${_pb_committed_mode:-<none>}') — under plan_branch an undeclared mode in the committed manifest is exactly the silent downgrade this boundary exists to prevent." 6
      fi
      echo "[WARN] lifecycle: the mode stamp for $plan_id is not committed (rc=$_lc_rc2) — the plan runs legacy, which is what the uncommitted state already implies." >&2
    fi
    echo "[INFO] lifecycle manifest ensured for $plan_id (.aid-lifecycle/manifests/${plan_id}.yaml), mode=${_pb_default_mode} (${_pb_mode_reason})" >&2
  elif [[ "$_lc_rc" -eq 3 ]] \
      && { [[ "$_pb_default_mode" == "plan_branch" ]] \
           || grep -qE '^lifecycle_strict:[[:space:]]*true' "$plan" 2>/dev/null; } \
      && { _pb_cur_branch="$(git branch --show-current 2>/dev/null || true)"; \
           _pb_lc_target="$(aid_target_branch)"; \
           [[ "$_pb_cur_branch" != "$_pb_lc_target" ]]; }; then
    # P074 Step 17 — checked FIRST and terminal: rc=3 combined with HEAD not
    # on the lifecycle target branch (_aid_lc_require_target_branch) is a
    # BRANCH problem, diagnosed as exactly that, with NO grammar advice. This
    # holds regardless of AID_LIFECYCLE_MIGRATION: the migration override must
    # not reroute an off-target strict run into a message carrying strict-EPIC
    # grammar advice — being on the wrong branch is not a migration concern. Two deliberate narrowings: (a)
    # ensure_manifest also returns 3 for a plan file it cannot resolve, hence
    # the explicit branch-mismatch re-check — an on-branch rc=3 falls through
    # to the existing messages unchanged; (b) a LEGACY (non-strict,
    # non-plan_branch) plan off target_branch keeps its P073 Step 6 contract
    # of proceeding — but its WARN below is likewise branch-diagnosed and
    # grammar-free on this rc.
    [[ -z "$_pb_cur_branch" ]] && _pb_cur_branch="<detached>"
    error_exit "you are on '${_pb_cur_branch}' but lifecycle writes require '${_pb_lc_target}' — run: git checkout ${_pb_lc_target}, or run generation for a worktree-recorded plan from its plan worktree" 6
  elif [[ "$_pb_default_mode" == "plan_branch" && "${AID_LIFECYCLE_MIGRATION:-}" != "1" ]]; then
    # P068 Step 7 — THE ESCAPE HATCH IS CLOSED UNDER plan_branch.
    # This path used to WARN and proceed whenever the plan did not opt into
    # lifecycle_strict. That is defensible for a legacy plan, but once the
    # default mode is plan_branch it becomes the silent downgrade the whole
    # boundary exists to prevent: no manifest means no mode declaration, which
    # means the plan runs legacy while everyone believes it is plan-branch.
    error_exit "Lifecycle manifest could not be created for $plan_id (rc=$_lc_rc) and the resolved default mode is plan_branch — proceeding would run the plan under the legacy model while its mode is undeclared. Fix the plan's EPIC declaration (strict '**EPIC N: …**' / '**EPIC N / Backlog: …**' grammar) and run on target_branch — or set AID_LIFECYCLE_MIGRATION=1 for an explicit, audited legacy run." 6
  elif grep -qE '^lifecycle_strict:[[:space:]]*true' "$plan" 2>/dev/null && [[ "${AID_LIFECYCLE_MIGRATION:-}" != "1" ]]; then
    # NEW-MODEL plan (opted into strict lifecycle via frontmatter) MUST have a
    # durable, committed manifest before EPIC scaffolding -> FAIL-CLOSED.
    error_exit "Lifecycle manifest could not be created for strict plan $plan_id (rc=$_lc_rc). A lifecycle_strict plan MUST have a durable, committed manifest before EPIC scaffolding. Fix the plan's EPIC declaration (strict '**EPIC N: …**' / '**EPIC N / Backlog: …**' grammar) and run on target_branch — or set AID_LIFECYCLE_MIGRATION=1 for an explicit, audited legacy run." 6
  else
    # Reached by a LEGACY plan (no lifecycle_strict) OR a strict plan explicitly
    # overridden with AID_LIFECYCLE_MIGRATION=1 -> explicit, AUDITED migration: a
    # loud WARN + a logged marker (never a silent skip). Reconcilable after
    # delivery. Message must NOT assert "legacy" — it may be a strict override.
    _lc_mode="legacy"; [[ "${AID_LIFECYCLE_MIGRATION:-}" == "1" ]] && _lc_mode="strict-override"
    _pb_cur_branch="$(git branch --show-current 2>/dev/null || true)"
    _pb_lc_target="$(aid_target_branch)"
    if [[ "$_lc_rc" -eq 3 && "$_pb_cur_branch" != "$_pb_lc_target" ]]; then
      # P074 Step 17 — same rc=3 branch diagnosis as the fail-closed path
      # above, WARN-grade because a legacy plan proceeds here (P073 Step 6
      # contract). The branch message, never grammar advice, on this rc.
      [[ -z "$_pb_cur_branch" ]] && _pb_cur_branch="<detached>"
      echo "[WARN] lifecycle: no durable manifest for plan $plan_id (mode=$_lc_mode, rc=3) — you are on '${_pb_cur_branch}' but lifecycle writes require '${_pb_lc_target}' — run: git checkout ${_pb_lc_target}, or run generation for a worktree-recorded plan from its plan worktree; proceeding in AUDITED migration mode; run 'aid-fsm.sh plan-reconcile $plan_id --apply' after delivery." >&2
    else
      echo "[WARN] lifecycle: no durable manifest for plan $plan_id (mode=$_lc_mode, rc=$_lc_rc) — proceeding in AUDITED migration mode; run 'aid-fsm.sh plan-reconcile $plan_id --apply' after delivery. (New plans use the plan template's 'lifecycle_strict: true' + the strict '**EPIC N:**' grammar for fail-closed guarantees.)" >&2
    fi
    mkdir -p "$(aid_state_path ".aid-o/work")" 2>/dev/null \
      && printf '{"plan_id":"%s","rc":%s,"mode":"lifecycle-migration-pending","migration_mode":"%s"}\n' "$plan_id" "$_lc_rc" "$_lc_mode" >> "$(aid_state_path ".aid-o/work/lifecycle-migration.log")" 2>/dev/null || true
  fi

  # The parent-plan state machine belongs exclusively to plan_branch mode.
  # A legacy plan deliberately retains the pre-P064 EPIC-by-EPIC lifecycle;
  # attempting plan-start without its durable plan-boundary manifest turns a
  # compatible ordinary pipeline into a false blocker. Do not "migrate" it as
  # a side effect of generation. plan_branch remains fail-closed above.
  #
  # Only when a plan-branch plan has no state: an existing plan is never
  # migrated mid-run, and plan-start is a no-op guard rather than a
  # re-initialisation.
  if [[ "$_pb_default_mode" == "plan_branch" && ! -f "$(aid_state_path ".aid-o/work/plan-state/${plan_id}/plan-state.yaml")" ]]; then
    _ps_rc=0
    # P073 Step 11: pass the source plan through so plan-start can verify it is
    # committed and stamp its path. The pipeline's own preflight above already
    # ran the same check, so this is the second, closer-to-the-mutation layer
    # rather than the first line of defence.
    bash "${SCRIPT_DIR}/aid-plan-fsm.sh" plan-start "$plan_id" \
      --mode "$_pb_default_mode" --project-root "." --plan-file "$plan" >/dev/null 2>&1 || _ps_rc=$?
    if [[ "$_ps_rc" -eq 0 ]]; then
      echo "[INFO] plan state initialised for $plan_id (mode=${_pb_default_mode})" >&2
    else
      echo "[WARN] plan-start could not initialise plan state for $plan_id (rc=$_ps_rc) — the lifecycle manifest still carries the declared mode, which is the authority; run 'aid-plan-fsm.sh plan-start $plan_id --mode ${_pb_default_mode}' before the plan boundary." >&2
    fi
  fi
fi

# =============================================================================
# P074 Steps 13 + 15 — TRANSACTION SKELETON, then the ONE CP1 gate, then the
# sealed authority. All three under ONE lock hold (see the header block).
#
# PLACEMENT — after the lifecycle-manifest ensure, before the phase loop, and
# GROUNDED rather than arbitrary. An earlier cut put this block immediately
# after the committed-source preflight, which is where "before any output"
# points; it broke on the very first fixture run, because
# `aid_lifecycle_ensure_manifest` COMMITS the manifest to the target branch.
# target_head therefore moves between the seal and the first phase's
# verification, and every phase died on the target_head check. Sealing after
# the ensure keeps the identity stable both within a run and across reruns
# (the ensure is a no-op once the manifest is durable). No EPIC, plan.json,
# run, FSM state or queue entry exists yet at this point — the gate still runs
# before every artifact this pipeline is here to produce.
#
# The serialization property Step 13 actually requires is untouched: the lock
# is acquired FIRST — before the lifecycle ensure, hence before anything can
# move target_head — the identity is derived and the identity-only skeleton is
# written under it, and only then does the CP1 gate run and the authority get
# written, still under the same hold. Two concurrent invocations can never both
# observe "no transaction", nor derive their identities from two different
# target heads.
# =============================================================================
_gen_plan_sha256="$(_gen_sha256_file "$plan")"
_gen_target_branch_name="$(_gen_target_branch)"
_gen_target_head_sha="$(_gen_target_head)"
_gen_identity="${_gen_plan_sha256}|${_gen_target_head_sha}|${AID_GEN_PHASE_DERIVATION_VERSION}|${total_phases}"
_gen_dir_path="$(_gen_dir "$plan_id")"
_gen_tx_path="$(_gen_transaction_path "$plan_id")"
_gen_auth_path="$(_gen_authority_path "$plan_id")"
mkdir -p "$_gen_dir_path" 2>/dev/null || error_exit "Cannot create the generation evidence directory: $_gen_dir_path" 3

# The generation lock is already held here — it was taken above, before the
# lifecycle-manifest ensure (see "ONE HOLD FOR THE WHOLE GENERATION"). Nothing
# is acquired at this point; the skeleton/gate/authority section below simply
# continues inside that same hold.

_gen_resumed=false
if [[ -f "$_gen_tx_path" ]]; then
  _gen_existing_identity="$(_gen_identity_of "$_gen_tx_path")"
  if [[ "$_gen_existing_identity" == "$_gen_identity" ]]; then
    _gen_resumed=true
    echo "[INFO] generation_transaction: resuming the existing transaction for ${plan_id} (identity unchanged) — verified phases are skipped, only what fails verification is regenerated." >&2
  elif _gen_tx_complete "$plan_id" "$(jq -r '.total_phases // 0' "$_gen_tx_path" 2>/dev/null || echo 0)" "$queue_yaml" "${_gen_dir_path}/receipt.json"; then
    # ROLLOVER PRECONDITION. A new transaction for
    # edited plan bytes derives the SAME epic ids from the same plan file, so
    # the previous generation's queue entries would look adoptable while
    # standing for content from a DIFFERENT identity. The ownership test in the
    # queue writer refuses that, but refusing there means refusing halfway
    # through stage 2, after everything has been regenerated. So it is decided
    # HERE, before anything is archived or regenerated, and it is named.
    #
    # ANY entry with one of those ids blocks, whatever its status. The queue
    # holds ONE entry per EPIC id (that is what the locked writer enforces), so
    # a regenerated EPIC cannot get its own entry while the old one is there —
    # the old entry would simply come to stand for content it was never queued
    # for. Status is irrelevant to that: a `completed` entry is still the one
    # and only row carrying that id.
    _gen_stale_entries=""
    for _gp in $(jq -r '.phases[]?.epic_id // empty' "$_gen_tx_path" 2>/dev/null); do
      _gp_status="$(_gen_queue_status "$queue_yaml" "$_gp")"
      [[ -n "$_gp_status" ]] && _gen_stale_entries="${_gen_stale_entries:+${_gen_stale_entries}, }${_gp} (${_gp_status})"
    done
    if [[ -n "$_gen_stale_entries" ]]; then
      _gen_unlock
      error_exit "the completed generation for ${plan_id} still has queue entries (${_gen_stale_entries}), and this invocation's plan bytes derive the SAME EPIC ids from a DIFFERENT identity ('${_gen_existing_identity}' -> '${_gen_identity}'). The queue holds one entry per EPIC id, so rolling over would leave those entries standing for regenerated content they were never queued for. Nothing was archived or regenerated. Remove those queue entries (finish them first if they are still in flight), then re-run." 1
    fi
    # AUTOMATIC ROLLOVER. A COMPLETE record is never clobbered at its fixed
    # live path: the pair is archived to `.completed-<epoch>` siblings sharing
    # one epoch, and the changed plan starts a fresh transaction.
    _gen_rollover_epoch="$(date -u +%s)"
    _gen_archive_pair "$plan_id" "completed-${_gen_rollover_epoch}" || {
      _gen_unlock
      error_exit "cannot archive the COMPLETED generation pair for ${plan_id} to .completed-${_gen_rollover_epoch} siblings — refusing to clobber a completed record." 3
    }
    echo "[INFO] generation_transaction: the previous transaction for ${plan_id} was COMPLETE and the plan identity changed — archived to .completed-${_gen_rollover_epoch} siblings; starting a fresh transaction." >&2
  else
    _gen_unlock
    error_exit "generation transaction identity mismatch for ${plan_id}: the existing INCOMPLETE transaction records identity '${_gen_existing_identity}' (plan_sha256|target_head|phase_derivation_version|total_phases) but this invocation derives '${_gen_identity}'. Artifacts from two derivations are never mixed. Archive the incomplete transaction first: aid-auto-pipeline.sh supersede-generation --plan '${plan}' --reason \"<at least 20 characters>\"" 1
  fi
fi

if [[ "$_gen_resumed" != true ]]; then
  # IDENTITY-ONLY SKELETON. Every phase's ids are pre-derived here so the phase
  # verifier compares a RE-DERIVED id against a RECORDED one; the two hashes
  # stay absent until each phase's outputs exist (schema allows that).
  _gen_phases_json="{}"
  for _gp in $(seq 1 "$total_phases"); do
    _gp_epic="$(aid_gen_epic_id "$plan_id" "$_gp" "$total_phases")"
    _gen_phases_json="$(jq -c --arg k "$_gp" --arg e "$_gp_epic" --arg r "$(aid_gen_run_id "$_gp_epic")" \
      '. + {($k): {epic_id: $e, run_id: $r}}' <<< "$_gen_phases_json")"
  done
  _gen_skeleton="$(jq -n \
    --arg schema "aid-generation-transaction/v1" \
    --arg plan_id "$plan_id" --arg plan_path "$plan" \
    --arg plan_sha256 "$_gen_plan_sha256" --arg target_branch "$_gen_target_branch_name" \
    --arg target_head "$_gen_target_head_sha" \
    --argjson pdv "$AID_GEN_PHASE_DERIVATION_VERSION" --argjson total "$total_phases" \
    --arg created "$(_gen_now)" --argjson phases "$_gen_phases_json" \
    '{schema:$schema, plan_id:$plan_id, plan_path:$plan_path, plan_sha256:$plan_sha256,
      target_branch:$target_branch, target_head:$target_head,
      phase_derivation_version:$pdv, total_phases:$total,
      authority_sha256:null, phases:$phases, created_at:$created, updated_at:$created}')" || _gen_skeleton=""
  [[ -n "$_gen_skeleton" ]] || { _gen_unlock; error_exit "cannot render the generation transaction skeleton for ${plan_id}" 3; }
  _gen_write_atomic "$_gen_tx_path" "$_gen_skeleton" || { _gen_unlock; error_exit "cannot write the generation transaction skeleton at ${_gen_tx_path}" 3; }
fi

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
  if [[ -f "${SCRIPT_DIR}/aid-cp1-gate.sh" ]]; then
    _gen_cp1_out="$(bash "${SCRIPT_DIR}/aid-cp1-gate.sh" --plan "$plan" --project-root "$_aid_pipeline_state_root" 2>&1)" || _gen_cp1_rc=$?
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
      _gen_err_first "$(printf "%s: the CP1 gate refused generation for %s and nothing was created. Fix the conditions below, or override deliberately with: aid-auto-pipeline.sh --plan %q --queue-mode %q --force --reason %q" \
        "$AID_GEN_LABEL_FORCE_REQUIRED" "$plan_id" "$plan" "$queue_mode" "<why, at least 20 characters>")"
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
      --argjson refs "$(jq -n --arg a "$(aid_state_path ".aid-o/work/evidence/${plan_id}/c0-plan-review.json")" \
                              --arg b "$(aid_state_path ".aid-o/work/evidence/${plan_id}/cp1-deep")" \
        '[{path:$a, sha256:null},{path:$b, sha256:null}]')" \
      '{bypassed_conditions: ($out | split("\n") | map(select(length > 0))), gate_exit: $rc, evidence_refs: $refs}')"
    # Fill the evidence_refs hashes for whatever actually exists (audit
    # provenance at decision time; the gate already validated those files).
    _gen_c0_ref="$(aid_state_path ".aid-o/work/evidence/${plan_id}/c0-plan-review.json")"
    if [[ -f "$_gen_c0_ref" ]]; then
      _gen_cp1_json="$(jq -c --arg p "$_gen_c0_ref" --arg h "$(_gen_sha256_file "$_gen_c0_ref")" \
        '.evidence_refs |= map(if .path == $p then .sha256 = $h else . end)' <<< "$_gen_cp1_json")"
    fi
  elif [[ "$force_generation" == true ]]; then
    # --force on a plan whose gate PASSES: the force is recorded as UNUSED —
    # nothing was bypassed, so no waiver is written (P073 Step 8 semantics).
    _gen_cp1_json='{"verdict":"pass","force_unused":true}'
  fi

  # The band this plan was classified into, recorded on the sealed decision so a
  # later reader can see WHICH ceremony was owed, not only that it passed. Asked
  # of the CLASSIFIER LIBRARY, which is not the gate: "the CP1 gate is consulted
  # exactly once per plan" is an invariant this pipeline's own suites assert by
  # COUNTING gate invocations (bats/generation-fixture.bash gen_cp1_calls), and
  # a pure library call spawns no gate. The earlier version scraped `band=` out
  # of the gate's human-readable stderr, which quietly made the wording of a
  # status line a contract.
  _gen_cp1_json="$(jq -c --arg b "$(aid_plan_band_name "$plan" "$_aid_pipeline_state_root")" \
    '.band = $b' <<< "$_gen_cp1_json")"

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
    bash "${SCRIPT_DIR}/aid-audit-log.sh" append \
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

# NO UNLOCK HERE — the hold continues through every phase, stage 2 and the
# receipt rewrite, and is dropped by the EXIT trap. See the "ONE HOLD FOR THE
# WHOLE GENERATION" note above for why the phase work cannot be run
# concurrently by two same-identity invocations.

for phase in $(seq 1 "$total_phases"); do

  # -------------------------------------------------------------------------
  # P074 Step 15 — RESUME. A phase whose recorded outputs still exist and
  # re-hash to the recorded values (and whose contract validation is still a
  # pass) is NOT regenerated: its manifest entry is rebuilt from the
  # transaction and the loop moves on. Everything else is regenerated in place.
  # -------------------------------------------------------------------------
  if [[ "$two_stage" == true ]] && _gen_phase_stage1_verified "$plan_id" "$phase"; then
    _res="$(jq -c --arg p "$phase" '.phases[$p]' "$_gen_tx_path")"
    epic_id="$(jq -r '.epic_id' <<< "$_res")"
    epic_path="$(jq -r '.epic_path' <<< "$_res")"
    plan_json_path="$(jq -r '.plan_json' <<< "$_res")"
    run_id="$(jq -r '.run_id' <<< "$_res")"
    _c0_dir="$(jq -r '.contract_validate' <<< "$_res")"; _c0_dir="$(dirname "$_c0_dir")"
    _stage_depends="$(_generation_depends_for_epic "$epic_path" "$prev_epic_id")"
    _stage_depends_json="[]"
    if [[ -n "$_stage_depends" ]]; then
      _stage_depends_json="$(printf '%s' "$_stage_depends" | tr ',' '\n' | jq -R . | jq -s .)"
    fi
    epics_json="$(echo "$epics_json" | jq \
      --argjson phase "$phase" --arg epic_id "$epic_id" --arg epic_path "$epic_path" \
      --arg plan_json "$plan_json_path" --arg run_id "$run_id" --arg contract_validate "${_c0_dir}/contract-validate.json" --argjson depends_on "$_stage_depends_json" \
      '. + [{phase:$phase, epic_id:$epic_id, epic_path:$epic_path, plan_json:$plan_json, contract_validate:$contract_validate, run_id:$run_id, queue_status:"pending_receipt", depends_on:$depends_on}]')"
    prev_epic_id="$epic_id"
    echo "[INFO] Phase ${phase}/${total_phases}: ${epic_id} verified against the transaction (hashes match on disk) — regeneration skipped" >&2
    continue
  fi

  # -------------------------------------------------------------------------
  # Phase N.a: Plan -> EPIC
  #
  # P074 Step 14 wiring: the sealed authority + the owning transaction are
  # passed instead of letting the generator re-run the CP1 gate per phase. The
  # generator VERIFIES both (schema, self-hash, plan bytes, target head, phase
  # range, re-derived ids, transaction linkage); a standalone invocation
  # without these flags keeps the full per-invocation gate.
  # -------------------------------------------------------------------------
  epic_path="$("${SCRIPT_DIR}/aid-plan-to-epic.sh" \
    --plan "$plan" \
    --phase "$phase" \
    --total "$total_phases" \
    --epic-template "$epic_template" \
    --output-dir "$(aid_state_path ".aid-o/tasks")" \
    --counter-yaml "$counter_yaml" \
    --generation-authority "$_gen_auth_path" \
    --transaction "$_gen_tx_path" \
    --project-root "$_aid_pipeline_state_root")"

  # Extract epic_id from the generated filename
  epic_basename="$(basename "$epic_path")"
  if [[ "$epic_basename" =~ (E-[A-Za-z0-9][A-Za-z0-9-]*[0-9]+_[0-9]+) ]]; then
    epic_id="${BASH_REMATCH[1]}"
  else
    error_exit "Cannot extract EPIC ID from generated file: $epic_basename" 1
  fi

  # -------------------------------------------------------------------------
  # Phase N.b: EPIC -> plan.json
  # -------------------------------------------------------------------------
  json_result="$("${SCRIPT_DIR}/aid-epic-to-json.sh" \
    --epic "$epic_path" \
    --schema "$plan_schema" \
    --output-dir "$(aid_state_path ".aid-o")" \
    --plan-source "$plan")"

  # Extract plan_json path and run_id from the JSON manifest on stdout
  plan_json_path="$(echo "$json_result" | jq -r '.plan_json')"
  run_id="$(echo "$json_result" | jq -r '.run_id')"

  if [[ -z "$plan_json_path" || "$plan_json_path" == "null" ]]; then
    error_exit "aid-epic-to-json.sh did not return plan_json path for phase $phase" 1
  fi
  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    error_exit "aid-epic-to-json.sh did not return run_id for phase $phase" 1
  fi

  # -------------------------------------------------------------------------
  # Phase N.b5: Contract Validation Gate (blocking, D5) + C0 Plan Contract
  # Gate (observe). Runs after plan.json exists; before FSM init. The
  # contract-validate sub-block below is the one BLOCKING exception in this
  # phase — everything else here is plan-level observe-only evidence.
  # -------------------------------------------------------------------------
  {
    # Determine plan_id from plan filename
    _c0_plan_id="$(basename "$plan" .md)"
    # Each generated EPIC owns its own C0 contract graph and validation
    # evidence. A shared plan-level c0/ directory made phase N overwrite phase
    # N-1, leaving the last graph to masquerade as evidence for the whole plan.
    # The plan-global source graph and C0 bridge remain at their own named
    # generation/ and c0/ paths respectively.
    _c0_dir="$(aid_state_path ".aid-o/work/evidence/${_c0_plan_id}/generation/epics/${epic_id}/c0")"
    mkdir -p "$_c0_dir"

    # -------------------------------------------------------------------------
    # D5: Contract Validation Gate (BLOCKING — deliberately NOT part of the
    # observe-only C0 block below). A malformed generator contract (broadcast
    # outputs/allowed_paths, `|`-split AC fragments, prose leaking into
    # allowed_paths) is a hard error per plan D5 ("Contract-gate blocking +
    # C0 evidence — malformed = hard-fail před /aid-run") and must stop the
    # pipeline before json-to-run / queue-add / branch creation happen below.
    #
    # Persist-before-abort: evidence is keyed by plan AND EPIC, so every
    # generated phase retains its own result. The complete-package finalizer
    # can therefore reason about all phases rather than a misleading final
    # overwrite from the last phase.
    # -------------------------------------------------------------------------
    _cv_exit=0
    _cv_json="$("${SCRIPT_DIR}/gates/aid-contract-validate.sh" "$plan_json_path" "$epic_path" \
      2>>"$_c0_dir/c0-producer.log")" || _cv_exit=$?

    # A VERDICT vs A CRASH — never the same message. The gate speaks in JSON on
    # stdout; a non-zero exit WITH a JSON document is a real finding about the
    # generated contract. A non-zero exit with NOTHING (or unparseable bytes) is
    # the gate itself failing — an interpreter abort, a SIGPIPE inside one of its
    # own pipelines, an OOM kill, a missing dependency. Reporting that as
    # "malformed plan.json/EPIC.md contract" tells the operator their EPIC is
    # broken when in truth nothing at all is known about it, and sends them
    # editing a file that is fine. (Grounded: under CPU load the D5 gate died of
    # SIGPIPE with empty stdout and this branch called it malformed — the abort
    # was even non-deterministic, the very next run passing the same bytes.)
    _cv_spoke=false
    if [[ -n "$_cv_json" ]] && jq -e . >/dev/null 2>&1 <<< "$_cv_json"; then
      _cv_spoke=true
    fi

    if [[ "$_cv_spoke" == true ]]; then
      printf '%s\n' "$_cv_json" > "${_c0_dir}/contract-validate.json"
    else
      # Never leave a blank file where a verdict belongs: the artifact says, in
      # its own bytes, that no verdict was reached and why.
      jq -n --argjson exit_code "$_cv_exit" --arg raw "$_cv_json" \
        --arg stderr_log "${_c0_dir}/c0-producer.log" \
        '{result:"gate_error", checks:[], violations:[],
          detail:"aid-contract-validate.sh exited without emitting a verdict — this file records a GATE failure, NOT a finding about the generated contract",
          gate_exit:$exit_code, gate_stdout:$raw, gate_stderr_log:$stderr_log}' \
        > "${_c0_dir}/contract-validate.json"
    fi

    # No verdict is never a pass either: a gate that exits 0 without saying
    # anything has validated nothing, and letting the phase through on its
    # silence is the same dishonesty in the other direction.
    if [[ "$_cv_exit" -ne 0 || "$_cv_spoke" != true ]]; then
      # This IS one of AID's own gates (D5), so the EXIT hook must not append
      # the not-an-AID-gate note to it.
      _gen_aid_owned_failure=true
      if [[ "$_cv_spoke" == true ]]; then
        error_exit "Contract validation failed for phase ${phase} (${_c0_plan_id}): malformed plan.json/EPIC.md contract — see ${_c0_dir}/contract-validate.json" 4
      fi
      _cv_how="exited ${_cv_exit}"
      if [[ "$_cv_exit" -gt 128 && "$_cv_exit" -lt 165 ]]; then
        _cv_how="was killed by signal $(( _cv_exit - 128 )) (exit ${_cv_exit})"
      fi
      error_exit "Contract validation could NOT BE RUN for phase ${phase} (${_c0_plan_id}): the D5 gate ${_cv_how} without emitting a verdict. This is a failure of the GATE, not a finding about the generated EPIC/plan.json — the contract is UNKNOWN, not malformed, and nothing needs editing. Re-run the generation (it resumes; verified phases are not regenerated). Gate stderr: ${_c0_dir}/c0-producer.log; artifact: ${_c0_dir}/contract-validate.json" 5
    fi

    # Read enforcement policy (fail-safe: default to observe)
    _c0_policy="observe"
    _c0_policy_file="${SCRIPT_DIR}/../defaults/policies/c0-contract.yaml"
    if [[ -n "${C0_CONTRACT_POLICY:-}" ]]; then
      _c0_policy="$C0_CONTRACT_POLICY"
    elif [[ -f "$_c0_policy_file" ]] && command -v yq &>/dev/null; then
      # P062 Step 11 — the sixth reader, through the shared per-control
      # resolver. The C0_CONTRACT_POLICY env override above still wins, so the
      # existing test/CI seam is untouched.
      if [[ -f "${SCRIPT_DIR}/lib/aid-control-enforcement.sh" ]]; then
        # shellcheck source=lib/aid-control-enforcement.sh
        source "${SCRIPT_DIR}/lib/aid-control-enforcement.sh"
      fi
      if declare -F aid_control_enforcement >/dev/null 2>&1; then
        _c0_policy="$(aid_control_enforcement "$_c0_policy_file" "c0_contract")"
      else
        _c0_policy_val="$(yq '.enforcement // "observe"' "$_c0_policy_file" 2>/dev/null)"
        [[ -n "$_c0_policy_val" && "$_c0_policy_val" != "null" ]] && _c0_policy="$_c0_policy_val"
      fi
    fi

    # Run C0 contract producer
    _c0_contract_exit=0
    "${SCRIPT_DIR}/aid-c0-contract.sh" contract "$plan_json_path" "$_c0_dir" \
      2>>"$_c0_dir/c0-producer.log" || _c0_contract_exit=$?

    if [[ $_c0_contract_exit -ne 0 ]]; then
      _c0_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '%s\n' "{\"ts\":\"${_c0_ts}\",\"event\":\"c0_producer_error\",\"plan_id\":\"${_c0_plan_id}\",\"exit\":${_c0_contract_exit}}" \
        >> "$_c0_dir/c0-observe.jsonl"
    fi

    # Run C0 review checker
    _c0_review_exit=0
    "${SCRIPT_DIR}/aid-c0-contract.sh" review "$plan" "$_c0_dir" \
      2>>"$_c0_dir/c0-producer.log" || _c0_review_exit=$?

    if [[ $_c0_review_exit -ne 0 ]]; then
      _c0_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '%s\n' "{\"ts\":\"${_c0_ts}\",\"event\":\"c0_review_error\",\"plan_id\":\"${_c0_plan_id}\",\"exit\":${_c0_review_exit}}" \
        >> "$_c0_dir/c0-observe.jsonl"
    fi

    # Log c0_would_block if any structural or lens findings
    _c0_would_block=false
    if [[ -f "$_c0_dir/plan-review.json" ]]; then
      _c0_finding_count="$(jq '
        ((.plan_review.structural_checks // []) | map(select(.status != "pass")) | length) +
        ((.plan_review.lens_findings // []) | map(select(.verdict == "found")) | length)
      ' "$_c0_dir/plan-review.json" 2>/dev/null || echo 0)"
      if [[ "$_c0_finding_count" -gt 0 ]]; then
        _c0_would_block=true
        _c0_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf '%s\n' "{\"ts\":\"${_c0_ts}\",\"event\":\"c0_would_block\",\"plan_id\":\"${_c0_plan_id}\",\"finding_count\":${_c0_finding_count},\"policy\":\"${_c0_policy}\"}" \
          >> "$_c0_dir/c0-observe.jsonl"
        echo "[C0] would_block: ${_c0_finding_count} findings (policy=${_c0_policy})" >&2
      fi
    fi

    # Enforce policy (blocking mode — E10 / tests only; default is observe)
    if [[ "$_c0_policy" == "blocking" && "$_c0_would_block" == "true" ]]; then
      # AID's OWN gate, named in its own message — the not-an-AID-gate note
      # would flatly contradict it.
      _gen_aid_owned_failure=true
      error_exit "C0 Plan Contract Gate: blocking policy activated with ${_c0_finding_count} findings" 2
    fi

    # NEVER propagate non-zero from C0 block in observe mode
  }

  # Stage 1 ends here on the normal path: no run/FSM/queue state exists until
  # the finalizer has verified every generated phase against the source graph.
  if [[ "$two_stage" == true ]]; then
    # WRITE-AHEAD ORDERING (P074 Step 15): the phase's outputs are on disk and
    # contract-validated, so the transaction records them BEFORE the loop
    # proceeds. A crash after this point resumes at the NEXT phase; a crash
    # before it regenerates this one (the hashes will not verify).
    _gen_tx_update "$plan_id" '.phases[$p] = ((.phases[$p] // {}) + {epic_id:$e, run_id:$r, epic_path:$ep, plan_json:$pj, contract_validate:$cv, epic_sha256:$es, plan_json_sha256:$ps})' \
      --arg p "$phase" --arg e "$epic_id" --arg r "$run_id" \
      --arg ep "$(realpath -m -- "$epic_path")" --arg pj "$(realpath -m -- "$plan_json_path")" \
      --arg cv "$(realpath -m -- "${_c0_dir}/contract-validate.json")" \
      --arg es "$(_gen_sha256_file "$epic_path")" --arg ps "$(_gen_sha256_file "$plan_json_path")"
    _stage_depends="$(_generation_depends_for_epic "$epic_path" "$prev_epic_id")"
    _stage_depends_json="[]"
    if [[ -n "$_stage_depends" ]]; then
      _stage_depends_json="$(printf '%s' "$_stage_depends" | tr ',' '\n' | jq -R . | jq -s .)"
    fi
    epics_json="$(echo "$epics_json" | jq \
      --argjson phase "$phase" --arg epic_id "$epic_id" --arg epic_path "$epic_path" \
      --arg plan_json "$plan_json_path" --arg run_id "$run_id" --arg contract_validate "${_c0_dir}/contract-validate.json" --argjson depends_on "$_stage_depends_json" \
      '. + [{phase:$phase, epic_id:$epic_id, epic_path:$epic_path, plan_json:$plan_json, contract_validate:$contract_validate, run_id:$run_id, queue_status:"pending_receipt", depends_on:$depends_on}]')"
    prev_epic_id="$epic_id"
    echo "[INFO] Phase ${phase}/${total_phases}: ${epic_id} generated; waiting for complete-package receipt" >&2
    continue
  fi

  # -------------------------------------------------------------------------
  # Phase N.c: plan.json -> run.md
  # -------------------------------------------------------------------------
  run_output_dir="$(aid_state_path ".aid-o/work/runs/${run_id}")"
  mkdir -p "$run_output_dir" 2>/dev/null || true

  json_to_run_args=(
    --plan-json "$plan_json_path"
    --run-template "$run_template"
    --epic "$epic_path"
    --output-dir "$run_output_dir"
    --run-id "$run_id"
  )
  [[ "$streamlined" == "true" ]] && json_to_run_args+=(--streamlined)
  [[ -n "$force_init_reason" ]] && json_to_run_args+=(--force-init-reason "$force_init_reason")
  # The plan's identity and resolved mode, so aid-json-to-run.sh can register
  # the EPIC's task branch (epic-start) before init needs it. Generation is the
  # only place both are known: the plan file has been parsed and the mode
  # resolved, while aid-json-to-run.sh sees one plan.json and no plan context.
  json_to_run_args+=(--plan-id "$plan_id" --plan-mode "$(_gen_plan_recorded_mode "$plan_id")")
  # P073 Step 6: exit 4 from aid-json-to-run.sh means generation SUCCEEDED but
  # the checkout could not be restored to the branch this run started on.
  # (4, not 3 — that script already uses 3 for ordinary I/O failures.)
  # Every remaining phase (queue, report, a further EPIC) would otherwise run
  # against a branch the operator never chose, so stop here and pass the
  # recovery instruction through. Any other non-zero status is an ordinary
  # generation failure and keeps its existing meaning.
  _j2r_rc=0
  run_path="$("${SCRIPT_DIR}/aid-json-to-run.sh" "${json_to_run_args[@]}")" || _j2r_rc=$?
  if [[ "$_j2r_rc" -eq 4 ]]; then
    echo "[ERROR] Branch restore failed after EPIC generation — the remaining pipeline phases (queue, report) were NOT run. Follow the 'git checkout' instruction above, then rerun." >&2
    exit 4
  fi
  [[ "$_j2r_rc" -eq 0 ]] || exit "$_j2r_rc"

  # -------------------------------------------------------------------------
  # Phase N.d: Determine depends_on for queue entry
  # -------------------------------------------------------------------------
  depends_on=""
  case "$queue_mode" in
    chain)
      depends_on="$prev_epic_id"
      ;;
    separate)
      depends_on=""
      ;;
    custom)
      depends_on="$custom_depends"
      ;;
  esac

  # Parse EPIC Dependencies -> Queue Implications section for external deps
  # Look for: depends_on: [E-xxx, E-yyy] in the generated EPIC
  queue_deps_raw="$(awk '
    BEGIN { in_qi = 0 }
    {
      gsub(/\r$/, "")
      if ($0 ~ /^### Queue Implications/) { in_qi = 1; next }
      if (in_qi && ($0 ~ /^##/ || $0 ~ /^---/)) exit
      if (in_qi && $0 ~ /^depends_on:/) {
        sub(/^depends_on:[[:space:]]*/, "", $0)
        # Remove brackets
        gsub(/[\[\]]/, "", $0)
        # Trim
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        if ($0 != "") print
        exit
      }
    }
  ' "$epic_path" 2>/dev/null || true)"

  if [[ -n "$queue_deps_raw" ]]; then
    # Merge external deps with existing depends_on (avoid duplicates)
    IFS=',' read -ra ext_deps <<< "$queue_deps_raw"
    for ext_dep in "${ext_deps[@]}"; do
      ext_dep="$(echo "$ext_dep" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$ext_dep" ]] && continue
      # Skip if it is the same as prev_epic_id (already handled by chain mode)
      [[ "$ext_dep" == "$prev_epic_id" ]] && continue
      # Skip self-references
      [[ "$ext_dep" == "$epic_id" ]] && continue
      if [[ -n "$depends_on" ]]; then
        # Check for duplicates before appending
        if ! echo ",$depends_on," | grep -q ",$ext_dep,"; then
          depends_on="${depends_on},${ext_dep}"
        fi
      else
        depends_on="$ext_dep"
      fi
    done
  fi

  # -------------------------------------------------------------------------
  # Phase N.e: EPIC -> queue
  # -------------------------------------------------------------------------
  queue_args=(
    --epic-id "$epic_id"
    --epic-path "$epic_path"
    --priority medium
    --queue-yaml "$queue_yaml"
    --plan-ref "$plan"
  )
  if [[ -n "$depends_on" ]]; then
    queue_args+=(--depends-on "$depends_on")
  fi

  "${SCRIPT_DIR}/aid-queue-add.sh" "${queue_args[@]}" >/dev/null

  # -------------------------------------------------------------------------
  # Phase N.f: Update tracking state
  # -------------------------------------------------------------------------
  prev_epic_id="$epic_id"

  # Build depends_on JSON array for the manifest
  depends_on_json="[]"
  if [[ -n "$depends_on" ]]; then
    IFS=',' read -ra dep_parts <<< "$depends_on"
    for dp in "${dep_parts[@]}"; do
      dp="$(echo "$dp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$dp" ]] && continue
      depends_on_json="$(echo "$depends_on_json" | jq --arg d "$dp" '. + [$d]')"
    done
  fi

  # Append entry to epics manifest
  epics_json="$(echo "$epics_json" | jq \
    --argjson phase "$phase" \
    --arg epic_id "$epic_id" \
    --arg epic_path "$epic_path" \
    --arg plan_json "$plan_json_path" \
    --arg run_path "$run_path" \
    --arg run_id "$run_id" \
    --arg queue_status "pending" \
    --argjson depends_on "$depends_on_json" \
    '. + [{
      phase: $phase,
      epic_id: $epic_id,
      epic_path: $epic_path,
      plan_json: $plan_json,
      run_path: $run_path,
      run_id: $run_id,
      queue_status: $queue_status,
      depends_on: $depends_on
    }]')"

  echo "[INFO] Phase ${phase}/${total_phases}: ${epic_id} -- done" >&2

done

# =============================================================================
# Stage 2 — seal the complete package, then initialise and queue it
# =============================================================================
generation_receipt=""
if [[ "$two_stage" == true ]]; then
  _generation_dir="$(aid_state_path ".aid-o/work/evidence/${plan_id}/generation")"
  mkdir -p "$_generation_dir"
  _generation_manifest="$_generation_dir/generated-epics.json"
  _generation_tmp="${_generation_manifest}.tmp.$$"
  printf '%s\n' "$epics_json" > "$_generation_tmp"
  mv "$_generation_tmp" "$_generation_manifest"
  generation_receipt="$_generation_dir/receipt.json"
  "${SCRIPT_DIR}/aid-generation-finalize.sh" --plan "$plan" --total "$total_phases" \
    --epics-json "$_generation_manifest" --output "$generation_receipt" >/dev/null

  for phase in $(seq 1 "$total_phases"); do
    _entry="$(jq -c --argjson p "$phase" '.[] | select(.phase == $p)' <<< "$epics_json")"
    _epic_id="$(jq -r '.epic_id' <<< "$_entry")"
    _epic_path="$(jq -r '.epic_path' <<< "$_entry")"
    _plan_json_path="$(jq -r '.plan_json' <<< "$_entry")"
    _run_id="$(jq -r '.run_id' <<< "$_entry")"
    _run_output_dir="$(aid_state_path ".aid-o/work/runs/${_run_id}")"
    mkdir -p "$_run_output_dir"
    _j2r_args=(--plan-json "$_plan_json_path" --run-template "$run_template" --epic "$_epic_path" --output-dir "$_run_output_dir" --run-id "$_run_id" --generation-receipt "$generation_receipt")
    [[ "$streamlined" == true ]] && _j2r_args+=(--streamlined)
    [[ -n "$force_init_reason" ]] && _j2r_args+=(--force-init-reason "$force_init_reason")
    _j2r_args+=(--plan-id "$plan_id" --plan-mode "$(_gen_plan_recorded_mode "$plan_id")")
    # P073 Step 6: same hard stop in the batch (post-receipt) loop — a failed
    # restore must not let the NEXT phase initialise on the wrong branch.
    _j2r_rc=0
    _run_path="$("${SCRIPT_DIR}/aid-json-to-run.sh" "${_j2r_args[@]}")" || _j2r_rc=$?
    if [[ "$_j2r_rc" -eq 4 ]]; then
      echo "[ERROR] Branch restore failed after phase ${phase}/${total_phases} (${_epic_id}) — no queue entry was written for it and no further phase was initialised. Follow the 'git checkout' instruction above, then rerun." >&2
      exit 4
    fi
    [[ "$_j2r_rc" -eq 0 ]] || exit "$_j2r_rc"

    # P074 Step 15: `--transaction` turns a duplicate this very transaction
    # already owns into a VERIFIED idempotent skip (the 2026-08-04 live
    # failure: a resumed run died on phase 1's queue duplicate and stranded
    # phases 2..N). A duplicate NOT owned by the transaction keeps its hard fail.
    _queue_args=(--epic-id "$_epic_id" --epic-path "$_epic_path" --priority medium --queue-yaml "$queue_yaml" --plan-ref "$plan" --transaction "$_gen_tx_path")
    _depends_csv="$(jq -r '.depends_on | join(",")' <<< "$_entry")"
    [[ -n "$_depends_csv" ]] && _queue_args+=(--depends-on "$_depends_csv")
    "${SCRIPT_DIR}/aid-queue-add.sh" "${_queue_args[@]}" >/dev/null
    _gen_tx_update "$plan_id" '.phases[$p] = ((.phases[$p] // {}) + {queued: true})' --arg p "$phase"
    _queue_real_status="$(_gen_queue_status "$queue_yaml" "$_epic_id")"
    [[ -n "$_queue_real_status" ]] || _queue_real_status="pending"
    epics_json="$(jq --argjson p "$phase" --arg rp "$_run_path" --arg qs "$_queue_real_status" 'map(if .phase == $p then . + {run_path:$rp, queue_status:$qs} else . end)' <<< "$epics_json")"
    echo "[INFO] Phase ${phase}/${total_phases}: ${_epic_id} initialised and queued after receipt (queue status: ${_queue_real_status})" >&2
  done

  # -------------------------------------------------------------------------
  # P074 Step 15 — REWRITE the receipt with the REAL queue statuses.
  #
  # The grounded defect: the receipt was composed before stage 2, so every
  # per-EPIC `queue_status` stayed at the placeholder `pending_receipt`
  # forever. The rewrite runs after the LAST queue-add, through the SAME
  # composer (single writer, full re-canonicalize, atomic replace), so the
  # receipt is self-consistent and its frozen consumer fields (schema,
  # plan_sha256, per-EPIC plan_json_sha256) are unchanged by construction.
  #
  # This is also the transaction's COMPLETION marker: `_gen_tx_complete`
  # returns false until it has happened, so a crash anywhere before this point
  # always leaves the transaction resumable.
  # -------------------------------------------------------------------------
  printf '%s\n' "$epics_json" > "$_generation_tmp"
  mv "$_generation_tmp" "$_generation_manifest"
  "${SCRIPT_DIR}/aid-generation-finalize.sh" --plan "$plan" --total "$total_phases" \
    --epics-json "$_generation_manifest" --output "$generation_receipt" --rewrite >/dev/null
  echo "[INFO] generation_receipt: queue statuses rewritten to their final values at ${generation_receipt}" >&2
fi

# =============================================================================
# Compute duration
# =============================================================================
duration_ms=0
if [[ "$use_ms_timer" == true ]]; then
  end_ms="$(date +%s%3N 2>/dev/null)" || end_ms=0
  if [[ "$end_ms" =~ ^[0-9]+$ && "$start_ms" =~ ^[0-9]+$ ]]; then
    duration_ms=$(( end_ms - start_ms ))
  fi
else
  duration_ms=$(( SECONDS * 1000 ))
fi

# =============================================================================
# Output JSON manifest to stdout
# =============================================================================
jq -n \
  --arg plan_id "$plan_id" \
  --arg plan_path "$plan" \
  --argjson epics "$epics_json" \
  --arg queue_mode "$queue_mode" \
  --argjson duration_ms "$duration_ms" \
  '{
    plan_id: $plan_id,
    plan_path: $plan_path,
    epics: $epics,
    queue_mode: $queue_mode,
    duration_ms: $duration_ms
  }'
