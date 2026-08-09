#!/usr/bin/env bash
# =============================================================================
# aid-recovery-ladder.sh — THE RECOVERY LADDER RECORD (P076 EPIC 2, Step 13)
#
# Provides (sourced, never executed):
#   aid_recovery_policy_load  [<explicit_policy_path>]
#   aid_recovery_ladder_append <run_evidence_dir> <json_line>
#   aid_ladder_emit           <run_evidence_dir> <stop_class> <emitter> [detail]
#   aid_ladder_attempt        <run_evidence_dir> <stop_class> <action>
#   aid_ladder_outcome        <run_evidence_dir> <stop_class> <action> <attempt_n> <outcome>
#   aid_ladder_escalate       <run_evidence_dir> <stop_class> [<epic_id>]
#   aid_ladder_last_accepted_action <run_evidence_dir> <stop_class>
#
# ── WHAT THIS FILE IS ───────────────────────────────────────────────────────
# `defaults/policies/auto-recovery.yaml` shipped in Step 11 as a policy with no
# runtime: it declared seven stop classes, six reversible actions, a per-class
# budget and a terminus, and NOTHING read it. This file is the loader and the
# record writer that policy named in its own `loader_contract` — which is why
# the path and the function name `aid_recovery_policy_load` are not free
# choices: `test-auto-recovery-policy.bats` case 9 DERIVES "is the ladder
# wired" from a function of that name being defined in this file, in a file
# that really reads auto-recovery.yaml. Renaming either without editing the
# policy's `loader_contract` turns that suite red, by design.
#
# ── WHAT IT DOES NOT DO — three boundaries, all load-bearing ────────────────
#  1. IT NEVER REPLACES A VERDICT. The gate runner's fail + streak + policy
#     block, aid-service's restart exhaustion, the FSM's orphan-dispatch die:
#     all keep their exact prior behaviour. The ladder RECORDS that the stop
#     happened and ROUTES what the AUTO loop does next. Every emitter call site
#     is `>/dev/null 2>&1 || true` and writes nothing to its caller's stdout,
#     because several of those callers' stdout IS a gate row.
#  2. IT NEVER EXECUTES AN ACTION. `aid_ladder_attempt` returns permission; the
#     CALLER performs the action and reports back through `aid_ladder_outcome`.
#     In particular `restart_service_once` is not a free action: nothing in this
#     file starts, restarts, signals or supervises a process, so the only code
#     that can restart a service is still aid-service.sh's own restart path,
#     which spends the ONE restart only when the declaration says
#     `restart_authorized: true` and only once per service
#     (`[[ "$restart_auth" == "true" ]] && (( restart_used == 0 ))`). A ladder
#     action therefore cannot smuggle authority the declaration withheld — not
#     because it promises not to, but because it has no mechanism to.
#  3. IT NEVER GOVERNS THE EXISTING LOOPS. The gate fix loop, CP2/CP3, the C3
#     fix loop, the CP1 ledger and per-gate `max_retries` keep their own budgets
#     in their own files (the policy's `existing_loops` table declares them).
#     The ladder governs only the stop that happens AFTER such a loop declares
#     itself terminal, and records that as REVIEW_EXHAUSTED.
#
# ── THE TERMINUS IS NOT A BYPASS ────────────────────────────────────────────
# Over budget → `adjudicate`. Adjudication returning `escalate` → the FSM
# ESCALATION state, whose ESCALATION→EXECUTE/GATES transition already refuses
# mechanically without `escalation_decision`, plus `auto_controller:
# blocked_for_pm` on the active-runs entry so the map stops claiming a live
# autonomous controller. Continuation past a refused terminal state is the P073
# `--force` surface — an audited human act. There is deliberately NO function
# here that continues past a terminus, and adding one would be the bypass this
# whole ladder exists to prevent.
#
# ── THE RECORD ──────────────────────────────────────────────────────────────
# `<run_evidence_dir>/recovery-ladder.jsonl`, append-only JSONL, one object per
# line, EVERY line carrying `ts` and `class` (so two classes interleaving in one
# run stay legible as two threads). `event` is a closed vocabulary:
#
#   recovery_stop         a named emitter site observed a stop of this class.
#                         outcome: "detected". Written in manual runs too — the
#                         evidence is worth having; only the ROUTING below is
#                         auto-only (in a manual run the human is the
#                         adjudicator).
#   recovery_attempt      a budget decision. outcome: "started" (permission
#                         granted, and the ONLY outcome that consumes budget) or
#                         one of the refusals: "budget_exhausted",
#                         "wall_clock_exhausted", "refused_action_not_allowed",
#                         "refused_policy_unreadable", "refused_unknown_class",
#                         "refused_unreadable_record".
#   recovery_outcome      what the caller's action actually did.
#                         outcome: "succeeded" | "failed".
#   recovery_terminus     outcome: "escalated".
#   recovery_adjudication written by lib/aid-recovery-adjudicate.sh through
#                         `aid_recovery_ladder_append` below (it uses this
#                         function when this file is sourced, its own plain
#                         append when it is not). `verdict` is that lib's field.
#
# READING THE RECORD — `revoked_unrecorded` is authoritative. The adjudication
# lib appends its ladder line BEFORE the timeline line, and revokes it with a
# compensating `verdict: "revoked_unrecorded"` line if the timeline append then
# fails. That compensating append is itself best-effort, so a naive "last
# accepted wins" query can return an action the adjudicator never actually
# returned. `aid_ladder_last_accepted_action` therefore drops any accepted line
# whose (class, attempt) a later `revoked_unrecorded` line names. Any other
# reader of this file must do the same.
#
# ── CONCURRENCY ─────────────────────────────────────────────────────────────
# The budget COUNT and the APPEND are one critical section, under a single
# `lib/aid-lock.sh` flock on `<record>.lock`. Counting outside the lock was the
# TOCTOU this design closes: two concurrent stops of the same class would each
# read "0 attempts used" and each write a `started` line, spending a 1-attempt
# budget twice.
#
# ── FAIL CLOSED ─────────────────────────────────────────────────────────────
# Unreadable policy, undeclared class, unparseable record, unwritable evidence
# dir, lock timeout: every one of them ends at `adjudicate`, never at "proceed".
# A broken policy must not license unbounded retries. The one asymmetry is
# `aid_ladder_emit`, which is evidence and not permission: it fails quietly (its
# callers are verdict-producing paths that must not change behaviour because a
# record could not be written) and returns non-zero for a caller that cares.
#
# Environment (optional):
#   AID_RECOVERY_POLICY   — explicit effective policy path (test seam, same name
#                           the adjudication lib uses).
#   AID_RECOVERY_FSM_BIN  — path to aid-fsm.sh (test seam).
#   AID_LADDER_LOCK_TIMEOUT_S — flock wait, default 10.
#
# **Last Updated:** 2026-08-09
# =============================================================================

_AID_LADDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=aid-lock.sh
source "$_AID_LADDER_DIR/aid-lock.sh"

# Resolved, not composed with `/../..`: this path is COMPARED (to a project
# override, and by the suites) and printed, and two spellings of one file read
# as two files.
_AID_LADDER_POLICY_DEFAULT="$(cd "$_AID_LADDER_DIR/../.." 2>/dev/null && pwd)/defaults/policies/auto-recovery.yaml"
_AID_LADDER_FSM_DEFAULT="$_AID_LADDER_DIR/../aid-fsm.sh"
AID_LADDER_RECORD_BASENAME="recovery-ladder.jsonl"

# The effective policy path resolved by the last aid_recovery_policy_load.
AID_RECOVERY_POLICY_EFFECTIVE=""
# The attempt number granted by the last successful aid_ladder_attempt.
AID_LADDER_ATTEMPT_N=""

_aid_ladder_warn() { echo "WARN: aid-recovery-ladder.sh: $*" >&2; }

_aid_ladder_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── THE TWO CLOSED SETS ─────────────────────────────────────────────────────
# Literals, deliberately NOT read from the policy: the policy is the thing being
# bounded. Same discipline as lib/aid-recovery-adjudicate.sh's six action
# constants, and `test-recovery-ladder.bats` pins lib == policy == schema so
# drift is loud rather than silent.
_aid_ladder_action_constants() {
  printf '%s\n' \
    wait_and_resume \
    retry_once \
    restart_service_once \
    rerun_targeted \
    resume_missing_lenses \
    collect_and_continue
}

_aid_ladder_class_constants() {
  printf '%s\n' \
    GATE_TIMEOUT \
    SERVICE_UNHEALTHY \
    JOB_LOST \
    TRANSIENT_INFRA \
    DISPATCH_ORPHANED \
    REVIEW_EXHAUSTED \
    UNCLASSIFIED
}

# _aid_ladder_in_set <name> <set-producing function>
_aid_ladder_in_set() {
  local want="$1" fn="$2" x
  [[ -n "$want" ]] || return 1
  while IFS= read -r x; do
    [[ "$x" == "$want" ]] && return 0
  done < <("$fn")
  return 1
}

_aid_ladder_is_action() { _aid_ladder_in_set "$1" _aid_ladder_action_constants; }
_aid_ladder_is_class()  { _aid_ladder_in_set "$1" _aid_ladder_class_constants; }

# ---------------------------------------------------------------------------
# _aid_ladder_policy_usable <path> — structural verdict on a policy file, on
# stdout: EMPTY iff it may be trusted, else the first reason it may not.
#
# This is the `loader_contract`'s refusals, implemented: `unknown_action` ("a
# schema error, refused at load"), the closed class set, and the terminus order
# (`pm_force` reordered to the front would invert the whole ladder). It is pure
# bash+yq on purpose — a JSON Schema validator is optional equipment on a host,
# and a check that silently skips where python3 is missing or broken is not a
# check. Always returns 0; the reason IS the answer.
# ---------------------------------------------------------------------------
_aid_ladder_policy_usable() {
  local policy="${1:-}" a c t
  [[ -n "$policy" && -f "$policy" && -r "$policy" ]] || {
    printf 'policy is missing or unreadable: %s\n' "$policy"; return 0; }
  command -v yq >/dev/null 2>&1 || { printf 'yq is unavailable — the policy cannot be read\n'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf 'jq is unavailable — no ladder record could be written\n'; return 0; }
  yq -o=json '.' "$policy" >/dev/null 2>&1 || {
    printf 'policy is not parseable YAML: %s\n' "$policy"; return 0; }

  local declared expected
  declared="$(yq -r '.action_vocabulary // {} | keys | .[]' "$policy" 2>/dev/null | LC_ALL=C sort | tr '\n' ',')"
  expected="$(_aid_ladder_action_constants | LC_ALL=C sort | tr '\n' ',')"
  [[ "$declared" == "$expected" ]] || {
    printf 'policy action_vocabulary is not the closed set of six this ladder enforces\n'; return 0; }

  declared="$(yq -r '.stop_classes // {} | keys | .[]' "$policy" 2>/dev/null | LC_ALL=C sort | tr '\n' ',')"
  expected="$(_aid_ladder_class_constants | LC_ALL=C sort | tr '\n' ',')"
  [[ "$declared" == "$expected" ]] || {
    printf 'policy stop_classes is not the closed set of seven this ladder enforces\n'; return 0; }

  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    _aid_ladder_is_action "$a" || {
      printf 'a stop class declares an action outside the vocabulary (schema error, refused at load)\n'; return 0; }
  done < <(yq -r '[.stop_classes // {} | .[] | .allowed_actions // [] | .[]] | .[]' "$policy" 2>/dev/null)

  # The terminus ORDER, type-aware and COUNTED. `join` on a non-array is a yq
  # ERROR, not an empty result: with stderr suppressed the earlier form emitted
  # no lines at all and this loop passed VACUOUSLY, so `terminus:` written as a
  # plain string was accepted. That is the same "unverifiable is not invalid"
  # trap the check exists to close, one type level down. So: every terminus that
  # is not an array of strings is normalised to the literal INVALID, and the
  # number of verdict lines must equal the number of declared classes —
  # anything else (a yq/jq error, a class that is not a map) refuses.
  local class_n t_out t_rc=0 t_n=0
  class_n="$(yq -r '.stop_classes // {} | keys | length' "$policy" 2>/dev/null)" || class_n=""
  [[ "$class_n" =~ ^[0-9]+$ ]] || {
    printf 'policy stop_classes could not be counted — the terminus check cannot be trusted\n'; return 0; }
  t_out="$(yq -o=json '.' "$policy" 2>/dev/null | jq -r '
      (.stop_classes // {}) | to_entries[] | .value as $v
      | if ($v | type) != "object" then "INVALID"
        elif (($v.terminus // null) | type) != "array" then "INVALID"
        elif ([$v.terminus[] | type] | unique) != ["string"] then "INVALID"
        else ($v.terminus | join(">")) end' 2>/dev/null)" || t_rc=1
  # `if`, not `[[ … ]] && …`: an AND-OR list whose test fails would leave a
  # nonzero status behind, and this function's whole contract is that its
  # STDOUT is the verdict — a status that aborts under a caller's `set -e`
  # would read as the empty (= usable) verdict. Fail closed, never by accident.
  if [[ -n "$t_out" ]]; then t_n="$(printf '%s\n' "$t_out" | wc -l)"; fi
  if (( t_rc != 0 )) || (( t_n != class_n )); then
    printf 'the terminus of every stop class could not be read — refusing rather than passing it unverified\n'; return 0
  fi
  while IFS= read -r t; do
    [[ "$t" == "adjudicate>escalation>pm_force" ]] || {
      printf 'a stop class declares a terminus other than adjudicate>escalation>pm_force\n'; return 0; }
  done <<< "$t_out"

  while IFS= read -r c; do
    [[ "$c" =~ ^[0-9]+\ [0-9]+$ ]] || {
      printf 'a stop class has a non-integer budget (attempts / wall_clock_seconds)\n'; return 0; }
  done < <(yq -r '.stop_classes // {} | .[] | ((.budget.attempts // "x") | tostring) + " " + ((.budget.wall_clock_seconds // "x") | tostring)' "$policy" 2>/dev/null)

  printf ''
  return 0
}

# ---------------------------------------------------------------------------
# aid_recovery_policy_load [<explicit_policy_path>]
#
# THE LOADER the policy's `loader_contract` names (see the header: this
# function's NAME and this FILE's path are pinned by
# test-auto-recovery-policy.bats). Resolves the effective
# defaults/policies/auto-recovery.yaml, prints its path, and sets
# AID_RECOVERY_POLICY_EFFECTIVE.
#
# Resolution order, and the contract each step implements:
#   1. an explicit argument, or $AID_RECOVERY_POLICY — the explicit seam. It is
#      used as given and still structurally validated.
#   2. the PROJECT override `.aid-o/config/policies/auto-recovery.yaml`
#      (`loader_contract.project_override_path`). Unreadable or structurally
#      invalid → NOT fatal and NOT silently accepted: a named warning naming the
#      path and the first error, then fall back to the shipped policy
#      (fail-closed to known-good).
#   3. the shipped defaults policy.
#
# `per_plan_override`: refused BY CONSTRUCTION — this function takes no plan
# argument and consults no plan-scoped path, because the recovery policy is
# PROJECT-scoped (two P074 plan worktrees of one project share it). The env name
# a caller might reach for is refused by name rather than ignored.
#
# rc 0 with the path on stdout; rc 3 when nothing usable could be resolved (the
# caller must then fail closed to adjudication — see aid_ladder_attempt).
# ---------------------------------------------------------------------------
aid_recovery_policy_load() {
  local explicit="${1:-${AID_RECOVERY_POLICY:-}}"
  AID_RECOVERY_POLICY_EFFECTIVE=""

  if [[ -n "${AID_RECOVERY_POLICY_PER_PLAN:-}" ]]; then
    _aid_ladder_warn "AID_RECOVERY_POLICY_PER_PLAN is refused: the recovery policy is PROJECT-scoped by design (one project, one recovery policy — two plans running concurrently in one project share it)"
    return 3
  fi

  local candidate="" err=""
  if [[ -n "$explicit" ]]; then
    candidate="$explicit"
    err="$(_aid_ladder_policy_usable "$candidate")"
    if [[ -n "$err" ]]; then
      _aid_ladder_warn "explicit recovery policy '${candidate}' is unusable: ${err}"
      return 3
    fi
    AID_RECOVERY_POLICY_EFFECTIVE="$candidate"
    printf '%s\n' "$candidate"
    return 0
  fi

  local root=""
  if declare -F aid_state_root >/dev/null 2>&1; then
    root="$(aid_state_root 2>/dev/null || true)"
  fi
  [[ -n "$root" ]] || root="${AID_PROJECT_ROOT:-$PWD}"
  local override="${root}/.aid-o/config/policies/auto-recovery.yaml"
  if [[ -e "$override" ]]; then
    err="$(_aid_ladder_policy_usable "$override")"
    if [[ -z "$err" ]]; then
      AID_RECOVERY_POLICY_EFFECTIVE="$override"
      printf '%s\n' "$override"
      return 0
    fi
    _aid_ladder_warn "project recovery-policy override '${override}' is not usable (${err}) — falling back to the shipped policy"
  fi

  err="$(_aid_ladder_policy_usable "$_AID_LADDER_POLICY_DEFAULT")"
  if [[ -n "$err" ]]; then
    _aid_ladder_warn "shipped recovery policy is unusable: ${err}"
    return 3
  fi
  AID_RECOVERY_POLICY_EFFECTIVE="$_AID_LADDER_POLICY_DEFAULT"
  printf '%s\n' "$_AID_LADDER_POLICY_DEFAULT"
  return 0
}

# _aid_ladder_record_path <run_evidence_dir>
_aid_ladder_record_path() { printf '%s/%s' "${1%/}" "$AID_LADDER_RECORD_BASENAME"; }

# ---------------------------------------------------------------------------
# aid_recovery_ladder_append <run_evidence_dir> <json_line>
#
# The ONE writer of the ladder record, and the function
# lib/aid-recovery-adjudicate.sh calls by name when this file is sourced. It
# REFUSES rather than writes when the line is not a JSON object naming a
# declared class — an unvalidated append would let a caller put anything on the
# audit surface, and the adjudication lib's ordering discipline (ladder first,
# timeline second) is built on this being the writer that CAN refuse.
#
# rc 0 appended; 1 refused / unwritable; 2 usage.
# ---------------------------------------------------------------------------
aid_recovery_ladder_append() {
  local dir="${1:-}" line="${2:-}"
  [[ -n "$dir" && -n "$line" ]] || { _aid_ladder_warn "aid_recovery_ladder_append <run_evidence_dir> <json_line>"; return 2; }
  [[ -d "$dir" ]] || { _aid_ladder_warn "run evidence dir not found: $dir"; return 1; }
  command -v jq >/dev/null 2>&1 || { _aid_ladder_warn "jq is required to write the ladder record"; return 1; }

  local cls
  cls="$(jq -r 'if type == "object" then (.class // "") else "" end' <<<"$line" 2>/dev/null)" || cls=""
  if [[ -z "$cls" ]]; then
    _aid_ladder_warn "refusing a ladder line that is not a JSON object naming a class"
    return 1
  fi
  if ! _aid_ladder_is_class "$cls"; then
    # A class the ladder does not know is recorded UNDER the class it really is
    # — nothing is silently dropped, and nothing invents a class either.
    line="$(jq -c --arg c "$cls" '. + {class:"UNCLASSIFIED", reported_class:$c}' <<<"$line" 2>/dev/null)" || return 1
  fi
  # One line, whatever the input's whitespace was.
  line="$(jq -c '.' <<<"$line" 2>/dev/null)" || return 1

  local rec; rec="$(_aid_ladder_record_path "$dir")"
  local fd rc=0
  aid_lock_acquire "${rec}.lock" "${AID_LADDER_LOCK_TIMEOUT_S:-10}" || {
    _aid_ladder_warn "could not lock ${rec}.lock — nothing appended"; return 1; }
  fd="$AID_LOCK_FD"
  printf '%s\n' "$line" >> "$rec" 2>/dev/null || rc=1
  aid_lock_release "$fd"
  (( rc == 0 )) || _aid_ladder_warn "could not append to ${rec}"
  return "$rc"
}

# _aid_ladder_line <class> <event> <outcome> [k=v ...] — one record line, built
# by jq so every value is escaped, never by string concatenation.
_aid_ladder_line() {
  local class="$1" event="$2" outcome="$3"; shift 3
  local -a args=(-nc --arg ts "$(_aid_ladder_now)" --arg class "$class"
                 --arg event "$event" --arg outcome "$outcome"
                 --arg auto "${AID_AUTO_MODE:-0}")
  local filter='{ts:$ts, event:$event, class:$class, outcome:$outcome, auto:($auto == "1")}'
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    [[ -n "$k" && "$k" != "$kv" ]] || continue
    # The VALUE always travels as `--arg` (jq escapes it); the KEY is the one
    # part that becomes filter TEXT, so it is restricted to a plain identifier.
    # Every key this file passes is a literal, and this keeps it that way even
    # if a future caller is careless.
    [[ "$k" =~ ^[a-z][a-z0-9_]*$ ]] || continue
    args+=(--arg "f_${k}" "$v")
    filter="${filter} + {${k}: \$f_${k}}"
  done
  jq "${args[@]}" "$filter" 2>/dev/null
}

# ---------------------------------------------------------------------------
# aid_ladder_emit <run_evidence_dir> <stop_class> <emitter> [detail]
#
# A named emitter site recording that a stop of this class HAPPENED. Evidence,
# never permission and never a verdict: it grants nothing, changes no caller's
# result, and is safe to call from a path whose stdout is a gate row (it prints
# nothing on stdout). Records in manual runs too — the `auto` field says which.
# rc 0 recorded; non-zero not recorded (callers use `|| true`).
# ---------------------------------------------------------------------------
aid_ladder_emit() {
  local dir="${1:-}" class="${2:-}" emitter="${3:-}" detail="${4:-}"
  [[ -n "$dir" && -n "$class" && -n "$emitter" ]] || return 2
  [[ -d "$dir" ]] || return 1
  _aid_ladder_is_class "$class" || { _aid_ladder_warn "unknown stop class '${class}' — recorded as UNCLASSIFIED"; }
  local line
  line="$(_aid_ladder_line "$class" recovery_stop detected "emitter=${emitter}" "detail=${detail}")" || return 1
  [[ -n "$line" ]] || return 1
  aid_recovery_ladder_append "$dir" "$line"
}

# _aid_ladder_epoch <iso8601> — epoch seconds, or nothing.
_aid_ladder_epoch() {
  local ts="${1:-}"
  [[ -n "$ts" && "$ts" != "null" ]] || return 0
  date -u -d "$ts" +%s 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# aid_ladder_attempt <run_evidence_dir> <stop_class> <action>
#
# The budget decision, and the only function here that grants anything.
#
#   stdout `proceed <attempt_n>`, rc 0 — within budget. The line
#     {class, action, attempt_n, ts, outcome:"started"} is on disk BEFORE this
#     returns. THE CALLER performs the action and then calls
#     aid_ladder_outcome. Nothing here executes anything.
#   stdout `adjudicate <reason>`, rc 4 — refused. The refusal is recorded with
#     the same reason. Every refusal path lands here: over attempts
#     (`budget_exhausted`), past the class's wall clock, an action the class
#     does not allow (named), an undeclared class, an unreadable policy, an
#     unparseable record. The caller routes to aid_recovery_adjudicate; if that
#     returns `escalate`, to aid_ladder_escalate.
#   rc 2 — usage error (stdout `adjudicate usage`).
#
# The count and the append are ONE critical section under a flock on
# `<record>.lock`; only `outcome:"started"` lines consume budget, and the wall
# clock runs from the class's FIRST line in the record (an emitter line counts —
# the clock starts when the stop was first seen, not when recovery was first
# attempted). Budgets are strictly per class, so two classes interleaving in one
# run never spend one another's.
#
# AUTO vs manual: this is the AUTO loop's routing function. A manual run's
# emitters still record (see aid_ladder_emit) but the human is the adjudicator,
# so nothing calls this on their behalf; the `auto` field on every line it
# writes says which kind of run produced it.
# ---------------------------------------------------------------------------
aid_ladder_attempt() {
  local dir="${1:-}" class="${2:-}" action="${3:-}"
  AID_LADDER_ATTEMPT_N=""

  if [[ -z "$dir" || -z "$class" || -z "$action" ]]; then
    echo "ERROR: usage: aid_ladder_attempt <run_evidence_dir> <stop_class> <action>" >&2
    echo "adjudicate usage"
    return 2
  fi
  if [[ ! -d "$dir" ]]; then
    echo "ERROR: aid_ladder_attempt: run evidence dir not found: ${dir} — an unrecordable attempt is not attempted." >&2
    echo "adjudicate unrecordable"
    return 4
  fi

  # -- the policy, fail-closed --------------------------------------------
  local policy=""
  policy="$(aid_recovery_policy_load 2>/dev/null || true)"
  if [[ -z "$policy" || ! -f "$policy" ]]; then
    _aid_ladder_record_refusal "$dir" "$class" "$action" refused_policy_unreadable \
      "the recovery policy could not be loaded; a broken policy must never license an unbounded retry"
    echo "adjudicate refused_policy_unreadable"
    return 4
  fi

  # -- the class must be one the policy declares --------------------------
  local known=0 k
  while IFS= read -r k; do [[ "$k" == "$class" ]] && known=1; done \
    < <(yq -r '.stop_classes // {} | keys | .[]' "$policy" 2>/dev/null)
  if (( ! known )); then
    _aid_ladder_record_refusal "$dir" "$class" "$action" refused_unknown_class \
      "the effective policy declares no such stop class — it routes as UNCLASSIFIED, straight to adjudication"
    echo "adjudicate refused_unknown_class"
    return 4
  fi

  # -- the action must be one THIS CLASS allows ---------------------------
  # Two filters, both required: the closed set compiled into this file, and the
  # class's own allowlist. The class travels as DATA (strenv), never as query
  # text, so a hostile class name cannot rewrite the expression that computes
  # its own allowlist.
  local allowed=0 a
  if _aid_ladder_is_action "$action"; then
    while IFS= read -r a; do
      [[ "$a" == "$action" ]] && allowed=1
    done < <(AID_LADDER_CLASS="$class" yq -r \
               '.stop_classes[strenv(AID_LADDER_CLASS)].allowed_actions[]' "$policy" 2>/dev/null)
  fi
  if (( ! allowed )); then
    _aid_ladder_record_refusal "$dir" "$class" "$action" refused_action_not_allowed \
      "action '${action}' is not in allowed_actions for class ${class}"
    echo "adjudicate refused_action_not_allowed"
    return 4
  fi

  local max_attempts max_wall
  max_attempts="$(AID_LADDER_CLASS="$class" yq -r '.stop_classes[strenv(AID_LADDER_CLASS)].budget.attempts' "$policy" 2>/dev/null)"
  max_wall="$(AID_LADDER_CLASS="$class" yq -r '.stop_classes[strenv(AID_LADDER_CLASS)].budget.wall_clock_seconds' "$policy" 2>/dev/null)"
  [[ "$max_attempts" =~ ^[0-9]+$ ]] || max_attempts=0
  [[ "$max_wall"     =~ ^[0-9]+$ ]] || max_wall=0

  # ── ONE CRITICAL SECTION: count, decide, append ─────────────────────────
  local rec; rec="$(_aid_ladder_record_path "$dir")"
  local fd
  aid_lock_acquire "${rec}.lock" "${AID_LADDER_LOCK_TIMEOUT_S:-10}" || {
    echo "ERROR: aid_ladder_attempt: could not lock ${rec}.lock — refusing rather than spending an uncounted attempt." >&2
    echo "adjudicate unrecordable"
    return 4; }
  fd="$AID_LOCK_FD"

  local used=0 first_ts="" parse_ok=1
  if [[ -s "$rec" ]]; then
    used="$(jq -rn --arg c "$class" '[inputs | select(.event == "recovery_attempt" and .class == $c and .outcome == "started")] | length' "$rec" 2>/dev/null)" || parse_ok=0
    first_ts="$(jq -rn --arg c "$class" '[inputs | select(.class == $c) | .ts] | (first // "")' "$rec" 2>/dev/null)" || parse_ok=0
  fi
  [[ "$used" =~ ^[0-9]+$ ]] || parse_ok=0

  local outcome="" detail="" attempt_n=0
  if (( ! parse_ok )); then
    outcome="refused_unreadable_record"
    detail="the ladder record could not be parsed; the spent budget is unknown, so no further attempt is granted"
  else
    local now first_epoch elapsed=0
    now="$(date -u +%s)"
    first_epoch="$(_aid_ladder_epoch "$first_ts")"
    [[ "$first_epoch" =~ ^[0-9]+$ ]] && elapsed=$(( now - first_epoch ))
    (( elapsed < 0 )) && elapsed=0

    if [[ -n "$first_ts" ]] && (( elapsed > max_wall )); then
      outcome="wall_clock_exhausted"
      detail="class ${class} first appeared ${elapsed}s ago; its wall_clock_seconds budget is ${max_wall} (attempts used ${used} of ${max_attempts})"
    elif (( used >= max_attempts )); then
      outcome="budget_exhausted"
      detail="class ${class} has spent ${used} of ${max_attempts} attempts"
    else
      attempt_n=$(( used + 1 ))
      outcome="started"
      detail="attempt ${attempt_n} of ${max_attempts}"
    fi
  fi

  local line rc_append=0
  line="$(_aid_ladder_line "$class" recovery_attempt "$outcome" \
            "action=${action}" "detail=${detail}" "attempt_n=${attempt_n}")"
  if [[ -n "$line" ]]; then
    line="$(jq -c --argjson n "$attempt_n" '.attempt_n = $n' <<<"$line" 2>/dev/null)" || line=""
  fi
  if [[ -z "$line" ]] || ! printf '%s\n' "$line" >> "$rec" 2>/dev/null; then
    rc_append=1
  fi
  aid_lock_release "$fd"

  if (( rc_append )); then
    echo "ERROR: aid_ladder_attempt: could not append to ${rec} — an unrecorded attempt is refused." >&2
    echo "adjudicate unrecordable"
    return 4
  fi

  if [[ "$outcome" == "started" ]]; then
    AID_LADDER_ATTEMPT_N="$attempt_n"
    echo "proceed ${attempt_n}"
    return 0
  fi
  echo "adjudicate ${outcome}"
  return 4
}

# _aid_ladder_record_refusal — a refusal that happens BEFORE the critical
# section (no counting involved). Best-effort by construction: the caller is
# already returning `adjudicate`, and a failed record never upgrades that.
_aid_ladder_record_refusal() {
  local dir="$1" class="$2" action="$3" outcome="$4" detail="$5" line
  line="$(_aid_ladder_line "$class" recovery_attempt "$outcome" \
            "action=${action}" "detail=${detail}" )" || return 0
  [[ -n "$line" ]] || return 0
  line="$(jq -c '.attempt_n = 0' <<<"$line" 2>/dev/null)" || return 0
  aid_recovery_ladder_append "$dir" "$line" >/dev/null 2>&1 || true
  return 0
}

# ---------------------------------------------------------------------------
# aid_ladder_outcome <run_evidence_dir> <stop_class> <action> <attempt_n> <outcome>
#   outcome ∈ {succeeded, failed}. What the caller's action actually did, for
#   the attempt aid_ladder_attempt granted. Never consumes budget (only
#   `started` does) and never grants anything.
# ---------------------------------------------------------------------------
aid_ladder_outcome() {
  local dir="${1:-}" class="${2:-}" action="${3:-}" n="${4:-}" outcome="${5:-}"
  [[ -n "$dir" && -n "$class" && -n "$action" && -n "$n" && -n "$outcome" ]] || {
    _aid_ladder_warn "aid_ladder_outcome <dir> <class> <action> <attempt_n> <succeeded|failed>"; return 2; }
  case "$outcome" in
    succeeded|failed) ;;
    *) _aid_ladder_warn "aid_ladder_outcome: outcome must be 'succeeded' or 'failed' (got '${outcome}')"; return 2 ;;
  esac
  [[ "$n" =~ ^[0-9]+$ ]] || { _aid_ladder_warn "aid_ladder_outcome: attempt_n must be an integer"; return 2; }
  local line
  line="$(_aid_ladder_line "$class" recovery_outcome "$outcome" "action=${action}")" || return 1
  line="$(jq -c --argjson n "$n" '.attempt_n = $n' <<<"$line" 2>/dev/null)" || return 1
  aid_recovery_ladder_append "$dir" "$line"
}

# ---------------------------------------------------------------------------
# aid_ladder_escalate <run_evidence_dir> <stop_class> [<epic_id>]
#
# THE TERMINUS, and the only thing it does is make the stop VISIBLE to a person:
#   • a `recovery_terminus` / `escalated` line in the record;
#   • `auto_controller: blocked_for_pm` on the run's active-runs entry, through
#     aid-fsm.sh's ONE writer (which owns the closed vocabulary — it accepts
#     blocked_for_pm and refuses the derived awaiting_host_resume).
#
# It does NOT transition the FSM. Entering ESCALATION and LEAVING it are two
# different acts with two different authorities: leaving already requires
# `escalation_decision` in fsm-state.yaml (aid-fsm.sh's ESCALATION→EXECUTE/GATES
# precondition), and that requirement is exactly what must not be routed around
# from inside a recovery ladder. The transition command is PRINTED for the
# controller; continuation past a refused terminal state remains the audited
# P073 `--force` surface.
#
# rc 0 the map was updated; 1 it was not (the record line still stands).
# ---------------------------------------------------------------------------
aid_ladder_escalate() {
  local dir="${1:-}" class="${2:-}" epic="${3:-}"
  [[ -n "$dir" && -n "$class" ]] || { _aid_ladder_warn "aid_ladder_escalate <run_evidence_dir> <stop_class> [<epic_id>]"; return 2; }

  local line
  line="$(_aid_ladder_line "$class" recovery_terminus escalated \
            "detail=adjudication returned escalate; the run stops advancing and is surfaced for a person")"
  [[ -n "$line" ]] && aid_recovery_ladder_append "$dir" "$line" >/dev/null 2>&1 || true

  if [[ -z "$epic" ]]; then
    local sf="$dir/fsm-state.yaml"
    [[ -f "$sf" ]] || sf="$dir/state.yaml"
    [[ -f "$sf" ]] && epic="$(sed -n 's/^epic_id:[[:space:]]*//p' "$sf" 2>/dev/null | head -1 | tr -d '"'"'"' ')"
  fi
  if [[ -z "$epic" ]]; then
    _aid_ladder_warn "no epic_id for ${dir} — auto_controller not set to blocked_for_pm (the ladder record still carries the escalation)"
    return 1
  fi

  local fsm="${AID_RECOVERY_FSM_BIN:-$_AID_LADDER_FSM_DEFAULT}"
  if [[ ! -f "$fsm" ]]; then
    _aid_ladder_warn "aid-fsm.sh not found at ${fsm} — auto_controller not set to blocked_for_pm"
    return 1
  fi
  if ! bash "$fsm" active-runs set "$epic" auto_controller blocked_for_pm >/dev/null 2>&1; then
    _aid_ladder_warn "could not set auto_controller=blocked_for_pm for ${epic}"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# aid_ladder_last_accepted_action <run_evidence_dir> <stop_class>
#
# The most recent adjudicated action for the class that was NOT revoked — empty
# when there is none. See the header: the adjudication lib's compensating
# `revoked_unrecorded` append is best-effort, so a bare `accepted` line can
# outlive an outcome its writer never returned. This reader drops every
# `accepted` line whose (class, attempt) a later `revoked_unrecorded` line
# names. A "last accepted wins" query without that step returns a revoked
# action, and acting on it would execute a decision nobody made.
# ---------------------------------------------------------------------------
aid_ladder_last_accepted_action() {
  local dir="${1:-}" class="${2:-}"
  [[ -n "$dir" && -n "$class" ]] || return 2
  local rec; rec="$(_aid_ladder_record_path "$dir")"
  [[ -s "$rec" ]] || { printf ''; return 0; }
  jq -rn --arg c "$class" '
    [inputs | select(.event == "recovery_adjudication" and .class == $c)] as $all
    | ([$all[] | select(.verdict == "revoked_unrecorded") | (.attempt // -1)]) as $revoked
    | [ $all[]
        | select(.verdict == "accepted")
        | select((.attempt // -1) as $a | ($revoked | index($a)) == null) ]
    | (last // {}) | (.action // "")
  ' "$rec" 2>/dev/null || printf ''
  return 0
}
