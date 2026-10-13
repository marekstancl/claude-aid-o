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

# The generation lock, the transaction writer, the target branch/head and the
# CP1 seal live in lib/aid-generation-authority.sh (P111) — shared with
# `aid-plan-fsm.sh plan-run`, so both roads hold ONE lock and write ONE
# transaction file. AID_GEN_PHASE_DERIVATION_VERSION: lib/aid-generation-ids.sh.
source "${SCRIPT_DIR}/lib/aid-generation-authority.sh"

# ── ID derivation ──────────────────────────────────────────────────────────
# THE derivation lives in lib/aid-generation-ids.sh and is shared with
# aid-plan-to-epic.sh (which re-derives these ids at verify time) and
# aid-epic-to-json.sh. The transaction pre-registers every phase's ids in the
# skeleton, before any generator runs, so the verifier compares a RE-DERIVED id
# against a RECORDED one — two independent inputs — and catches derivation
# drift between plugin versions at verify time instead of at queue time.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/aid-generation-ids.sh"
# shellcheck source=lib/aid-queue-write.sh
source "${SCRIPT_DIR}/lib/aid-queue-write.sh"   # queue_entry_delivered
source "${SCRIPT_DIR}/lib/aid-scoping.sh"       # _aid_blank_fenced

# _gen_phase_delivered <epic_id> — an earlier generation delivered this EPIC
# (queue_entry_delivered): it is not generated again, not re-queued and not
# bound to the current plan bytes — its work is already in git (P100 Step 5).
_gen_phase_delivered() { queue_entry_delivered "$1" "$queue_yaml" "$_aid_pipeline_state_root"; }

# _gen_refuse_plan_run <plan_id> — P111: a plan with a direct run (plan-run's
# `kind: plan_run` transaction, or a `direct: true` entry in its plan manifest)
# is never generated, superseded or rolled over: the two roads never mix on one
# plan. Called right after the generation lock is taken, before anything moves.
_gen_refuse_plan_run() {
  local pid="$1" txp mf why=""
  txp="$(_gen_transaction_path "$pid")"
  mf="$(aid_state_path ".aid-o/work/plan-state/${pid}/plan-boundary-manifest.json")"
  if [[ -f "$txp" && "$(jq -r '.kind // ""' "$txp" 2>/dev/null)" == "plan_run" ]]; then
    why="its generation transaction is a plan-run (${txp})"
  elif [[ -f "$mf" ]] && jq -e 'any(.plan_boundary_manifest.epic_runs[]?; .direct == true)' "$mf" >/dev/null 2>&1; then
    why="its plan manifest records a direct run"
  fi
  [[ -n "$why" ]] || return 0
  _gen_unlock
  _gen_flush_stderr
  echo "PRECONDITION FAIL: ${pid} already has a direct run — ${why}; it is never generated the EPIC way." >&2
  echo "next: continue it with /aid-run --resume ${pid} (aid-plan-fsm.sh plan-run ${pid}), or close it administratively and write a new plan" >&2
  echo "(pipeline.md §When AID refuses: plan_run_already_started)" >&2
  exit 1
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

# The archive and the three-record audit trail (aidaid_gen_archive_pair,
# aidaid_gen_supersede_audit_preflight, aidaid_gen_supersede_record_present,
# aid_gen_supersede_audit) live in lib/aid-generation-authority.sh (P112: the
# direct run's restart leaves the same trail).

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
  _gen_refuse_plan_run "$sup_plan_id"

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
    aid_gen_supersede_audit_preflight "$gdir" \
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
    half_rec="$(aid_gen_supersede_audit "$sup_plan_id" "$sup_plan" "$sup_reason" "${USER:-unknown}" \
      "$half_epoch" "$gdir" "$txp" "$auth" "$half_identity" "$half_generated" "$_aid_pipeline_state_root")" \
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
  # aid_gen_supersede_audit_preflight.
  aid_gen_supersede_audit_preflight "$gdir" \
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
  rec_file="$(aid_gen_supersede_audit "$sup_plan_id" "$sup_plan" "$sup_reason" "$operator" \
    "$epoch" "$gdir" "$txp" "$auth" "$identity" "$generated" "$_aid_pipeline_state_root")" \
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
done < <(_aid_blank_fenced < "$plan")   # a fenced example is no phase, as plan-to-epic and the lifecycle parser read it

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
# P111: checked FIRST under the lock — before the lifecycle mode re-stamp and
# the rollover below, either of which would change a direct plan's state.
_gen_refuse_plan_run "$plan_id"

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
    error_exit "you are on '${_pb_cur_branch}' but lifecycle writes require '${_pb_lc_target}' — the plan file and .aid-lifecycle/manifests/${plan_id}.yaml must be COMMITTED on '${_pb_lc_target}' (plan-start commits them on the plan branch only): commit them there, then run: git checkout ${_pb_lc_target} and generate again" 6
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
      _gen_phase_delivered "$_gp" && continue   # delivered: kept, never regenerated
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
    aid_gen_archive_pair "$plan_id" "completed-${_gen_rollover_epoch}" || {
      _gen_unlock
      error_exit "cannot archive the COMPLETED generation pair for ${plan_id} to .completed-${_gen_rollover_epoch} siblings — refusing to clobber a completed record." 3
    }
    echo "[INFO] generation_transaction: the previous transaction for ${plan_id} was COMPLETE and the plan identity changed — archived to .completed-${_gen_rollover_epoch} siblings; starting a fresh transaction." >&2
  elif jq -e '[.phases[]? | .epic_sha256 // ""] | all(. == "")' "$_gen_tx_path" >/dev/null 2>&1; then
    # AN EMPTY TRANSACTION SUPERSEDES ITSELF. A run that failed before any
    # phase was generated holds no artifact that could be mixed with the new
    # derivation; its authority was sealed to the old plan bytes, which is why
    # the identity no longer matches after a plan fix. It is archived the way
    # supersede-generation archives (same siblings, same three audit records,
    # under the lock this run already holds) and generation goes on.
    _gen_ae="$(date -u +%s)"
    _gen_ad="$(realpath -m -- "$_gen_dir_path")"
    { aid_gen_supersede_audit_preflight "$_gen_ad" \
        && aid_gen_archive_pair "$plan_id" "superseded-${_gen_ae}" \
        && aid_gen_supersede_audit "$plan_id" "$plan" "automatic: the incomplete transaction generated no phase and the plan identity changed" \
             "${USER:-unknown}" "$_gen_ae" "$_gen_ad" "${_gen_ad}/transaction.json" "${_gen_ad}/generation-authority.json" \
             "$_gen_existing_identity" '[]' "$_aid_pipeline_state_root" >/dev/null; } || {
      _gen_unlock
      error_exit "the incomplete transaction for ${plan_id} generated nothing, but archiving it automatically failed (see above). Archive it by hand: aid-auto-pipeline.sh supersede-generation --plan '${plan}' --reason \"<at least 20 characters>\"" 3
    }
    echo "[INFO] generation_transaction: the previous transaction for ${plan_id} generated no phase and the plan identity changed — archived to .superseded-${_gen_ae} siblings (audited); starting a fresh transaction." >&2
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

# ── the ONE CP1 gate call, the sealed authority and the binding of the
# transaction to it: lib/aid-generation-authority.sh (aid_gen_seal, P111 —
# the same body plan-run seals through).
aid_gen_seal "$plan" "$plan_id" "$total_phases" "$queue_mode" "$force_generation" "$force_reason"

# NO UNLOCK HERE — the hold continues through every phase, stage 2 and the
# receipt rewrite, and is dropped by the EXIT trap. See the "ONE HOLD FOR THE
# WHOLE GENERATION" note above for why the phase work cannot be run
# concurrently by two same-identity invocations.

for phase in $(seq 1 "$total_phases"); do

  # P100 Step 5 — a phase whose EPIC an earlier generation delivered (proven by
  # git) is recorded as delivered and skipped: resuming a half-delivered plan
  # regenerates only what is not in git yet (ACTA #10, #11).
  _gp_e="$(jq -r --arg p "$phase" '.phases[$p].epic_id // ""' "$_gen_tx_path" 2>/dev/null)"
  if [[ "$two_stage" == true && -n "$_gp_e" ]] && _gen_phase_delivered "$_gp_e"; then
    epics_json="$(jq --argjson phase "$phase" --arg e "$_gp_e" --arg qs "$(_gen_queue_status "$queue_yaml" "$_gp_e")" \
      '. + [{phase:$phase, epic_id:$e, status:"delivered", proven_by:"git", queue_status:$qs, depends_on:[]}]' <<< "$epics_json")"
    prev_epic_id="$_gp_e"
    echo "[INFO] Phase ${phase}/${total_phases}: ${_gp_e} is delivered (its merge is in git) — not generated again" >&2
    continue
  fi

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
  # Phase N.b5: Contract Validation Gate (blocking, D5). Runs after plan.json
  # exists; before FSM init.
  # -------------------------------------------------------------------------
  {
    # Determine plan_id from plan filename
    _c0_plan_id="$(basename "$plan" .md)"
    # Each generated EPIC owns its own contract validation evidence (the c0/
    # directory name is historical). A shared plan-level directory made phase N
    # overwrite phase N-1, leaving the last result to masquerade as evidence for
    # the whole plan.
    _c0_dir="$(aid_state_path ".aid-o/work/evidence/${_c0_plan_id}/generation/epics/${epic_id}/c0")"
    mkdir -p "$_c0_dir"

    # -------------------------------------------------------------------------
    # D5: Contract Validation Gate (BLOCKING). A malformed generator contract (broadcast
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
    [[ "$(jq -r '.status // ""' <<< "$_entry")" == delivered ]] && continue
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
