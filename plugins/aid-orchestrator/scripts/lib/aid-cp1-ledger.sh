#!/usr/bin/env bash
# =============================================================================
# aid-cp1-ledger.sh — CP1 revision-limit ledger (P065, E-065-7_7 Step 19)
#
# The mechanical CP1 revision-limit AUTHORITY. A per-plan (`plan_id`-keyed)
# review-cycle counter that survives normal evidence-path/verifier changes.
#
# WHY THIS EXISTS: `revision_count` today lives only in adjudicator prose and
# aid-cp1-gate.sh (see that file — read-only reference, NOT modified here)
# never reads it; the gate fails only on `accepted_blockers`. Nothing
# mechanically bounds a runaway CP1 revise-loop. This script is the counting
# primitive that closes that gap.
#
# SCOPE (this step, Step 19, is the FOUNDATION only):
#   - init / increment / read / check-budget, all fail-closed.
#   - Does NOT wire itself into aid-cp1-gate.sh or aid-plan-to-epic.sh — that
#     mechanical GATE enforcement (blocking epic-gen on an exhausted budget)
#     is Step 20's job (a LATER step, not implemented here — no back-dependency
#     from this file onto Step 20's work).
#   - `check-budget` only REPORTS status; it never blocks anything by itself.
#
# NOT COMMITTED: `.aid-o/` (and `**/.aid-o/`) is gitignored (see .gitignore
# root rules) — the ledger is RUNTIME state, created by an explicit `init`.
# P065 BOOTSTRAP: `aid-cp1-ledger.sh init --pre-enforcement P065` is a RUNTIME
# action for the orchestrator to run later against the live P065 workspace —
# it is NOT part of this code-only step and this step does not run it.
#
# HONEST SCOPE: this ledger is resilient to normal evidence-dir/verifier-
# identity churn (its path depends on plan_id ONLY). It does NOT claim to be
# un-deletable — a missing ledger with CP1 evidence already present is FAIL-
# CLOSED (budget-exhausted/init-required), never a silent reset. Recovery is
# an explicit `init` (only valid for a provably-new plan) or a PM override.
#
# CP1 EVIDENCE DIR — how "does this plan already have CP1-deep evidence"
# is determined: aid-cp1-gate.sh (read for this) computes
#   <project_root>/.aid-o/work/evidence/<plan_id>/cp1-deep/
# and requires 4 named files there (cp1-lens-L1-behavior.md, -L2-feasibility.md,
# -L3-enforcement.md, cp1-adjudicator.md) for a high-risk plan to pass. This
# script reuses that EXACT path (`_cp1_evidence_dir`) — plan_id-keyed, no
# separate convention invented — and treats "the dir exists and is non-empty"
# (>=1 entry) as evidence-present, rather than requiring all 4 named files:
# a PARTIAL evidence write (e.g. only L1 written so far, adjudicator crashed
# mid-run) already proves the plan is not "provably new" and must not be
# allowed a silent attempts:0 reset via a bare `init`. Fail-closed leans
# toward the stricter (any-entry) reading here on purpose.
#
# LEDGER FILE — <project_root>/.aid-o/work/cp1-ledger/<plan_id>.yaml
#   schema_version:  "aid-2.0"
#   plan_id:         string
#   attempts:        integer (0 = no revision cycle counted yet)
#   max:             integer, currently 3 (1 initial + 2 revisions)
#   pre_enforcement: boolean (true only for the explicit P065 bootstrap path)
#   pm_override:     {present: boolean, ref: string|null,
#                      claim_artifact: string|null, claim_sha256: string|null}
#     — present/ref/claim_artifact/claim_sha256 are written ONLY by
#     cmd_increment, ONLY when THAT SPECIFIC advance was authorized by
#     atomically claiming a genuine cp1-pm-escalation-override.json (never
#     a standing/sticky flag — cleared to false/null on every increment
#     that does NOT itself claim an override). claim_artifact/claim_sha256
#     bind this record to the actual `.consumed-<epoch>` file the claim
#     produced (DONE-review #5 fix — see cmd_check_budget): a ledger file
#     is a plain, non-tamper-evident file, so `present` being
#     cmd_increment's INTENDED sole writer does not make it the only
#     POSSIBLE one — check-budget re-verifies claim_artifact/claim_sha256
#     against disk before trusting `present`, so a bare hand-edit of
#     `present:true` (with no matching, existing, content-verified
#     .consumed-<epoch> file) is NOT sufficient to grant a bypass.
#   created_at / updated_at: ISO-8601 UTC
#   attempts_log:    [{n, plan_hash, codex_session (string|null), at}, ...]
#
# Usage:
#   aid-cp1-ledger.sh init [--pre-enforcement] [--project-root <path>] <plan_id>
#   aid-cp1-ledger.sh increment [--project-root <path>] [--codex-session <id>] <plan_id> <plan_hash>
#   aid-cp1-ledger.sh read [--project-root <path>] <plan_id>
#   aid-cp1-ledger.sh check-budget [--project-root <path>] <plan_id>
#   aid-cp1-ledger.sh claim-pm-override [--project-root <path>] <plan_id>
#
# Exit codes:
#   init/increment/read: 0 = success, 1 = precondition/fail-closed failure.
#   check-budget: 0 = budget available, 1 = FAIL-CLOSED (exhausted, OR
#     corrupt ledger, OR evidence present but ledger missing), 2 =
#     not_initialized (no ledger AND no CP1 evidence — a genuinely
#     brand-new plan; caller should run `init`). A pm_override.present:true
#     ledger entry is honored ONLY when corroborated by its claim_artifact/
#     claim_sha256 against a genuine, matching .consumed-<epoch> file on
#     disk (see the pm_override field description above) — the sole path
#     that can ever produce such a file is aid-cp1-gate.sh's/this file's
#     shared single-use cp1-pm-escalation-override.json artifact, claimed
#     atomically by cmd_increment.
#
# **Last Updated:** 2026-07-18
# =============================================================================
set -euo pipefail

MAX_ATTEMPTS=3

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: aid-cp1-ledger.sh <subcommand> [args...]

Subcommands:
  init [--pre-enforcement] [--project-root <path>] <plan_id>
      Create a fresh ledger at attempts:0. Without --pre-enforcement, this
      only succeeds when NO CP1-deep evidence dir exists yet for <plan_id>
      (a provably new plan). --pre-enforcement is the explicit, audited
      bootstrap for an ALREADY in-flight plan (e.g. P065) and bypasses the
      evidence check. In both modes, init refuses to overwrite an existing
      ledger (never a silent reset).

  increment [--project-root <path>] [--codex-session <id>] <plan_id> <plan_hash>
      Advance the ledger's attempts counter, but ONLY when <plan_hash>
      differs from the last recorded attempt's plan_hash. A re-run with an
      unchanged plan_hash is a no-op (prints current state, does not touch
      the file). Requires an existing, valid ledger — never auto-creates one.

  read [--project-root <path>] <plan_id>
      Print the ledger as JSON. Fails if the ledger is missing or corrupt.

  check-budget [--project-root <path>] <plan_id>
      Report budget status without mutating anything. See exit codes above.

  claim-pm-override [--project-root <path>] <plan_id>
      Atomically consume a present, valid cp1-pm-escalation-override.json
      (pm_ref >= 20 chars) for <plan_id>, printing {reason, consumed_path}.
      Shared single-use claim primitive — used by cmd_increment above AND
      by other scripts (e.g. aid-c0-plan-review.sh's bounded-loop override)
      that need the SAME real, auditable PM authorization, not a bare env
      var. Fails (exit 1, nothing printed) if no valid override is present.
EOF
}

# ---------------------------------------------------------------------------
# _fail <msg>  — emit a PRECONDITION FAIL message and exit 1.
# ---------------------------------------------------------------------------
_fail() {
  echo "PRECONDITION FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# _validate_plan_id <plan_id>  — non-empty, path-traversal-safe.
# ---------------------------------------------------------------------------
_validate_plan_id() {
  local pid="$1"
  [[ -n "$pid" ]] || _fail "plan_id is empty"
  [[ "$pid" =~ ^[A-Za-z0-9_-]+$ ]] || _fail "plan_id '$pid' contains invalid characters (path traversal guard)"
}

# ---------------------------------------------------------------------------
# _ledger_path <project_root> <plan_id>
# ---------------------------------------------------------------------------
_ledger_path() {
  printf '%s/.aid-o/work/cp1-ledger/%s.yaml' "$1" "$2"
}

# ---------------------------------------------------------------------------
# _cp1_evidence_dir <project_root> <plan_id>  — same convention as
# aid-cp1-gate.sh's evidence_dir (see header comment above).
# ---------------------------------------------------------------------------
_cp1_evidence_dir() {
  printf '%s/.aid-o/work/evidence/%s/cp1-deep' "$1" "$2"
}

# ---------------------------------------------------------------------------
# _cp1_evidence_exists <dir>  — true iff the dir exists and has >=1 entry.
# ---------------------------------------------------------------------------
_cp1_evidence_exists() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  local had_nullglob=0
  shopt -q nullglob && had_nullglob=1
  shopt -s nullglob
  local files=("$dir"/*)
  [[ "$had_nullglob" -eq 1 ]] || shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]]
}

# ---------------------------------------------------------------------------
# _cp1_plan_evidence_root <project_root> <plan_id>
#   Computes the plan-evidence-root directory (parent of cp1-deep/).
#   Mirrors aid-cp1-gate.sh's own computation for consistency.
# ---------------------------------------------------------------------------
_cp1_plan_evidence_root() {
  printf '%s/.aid-o/work/evidence/%s' "$1" "$2"
}

# ---------------------------------------------------------------------------
# _cp1_override_file <plan_evidence_root>
#   Computes the path to the PM-escalation override artifact.
#   Mirrors aid-cp1-gate.sh's implementation exactly.
# ---------------------------------------------------------------------------
_cp1_override_file() {
  printf '%s/cp1-pm-escalation-override.json' "$1"
}

# ---------------------------------------------------------------------------
# _cp1_check_pm_override <plan_evidence_root>
#   READ-ONLY: reports whether a structurally valid PM-escalation override
#   (non-empty pm_ref field, >= 20 chars) is currently present. Never
#   consumes/renames anything. Echoes the pm_ref reason and returns 0 iff
#   valid; returns 1 (nothing echoed) otherwise.
#   Mirrors aid-cp1-gate.sh's implementation exactly.
# ---------------------------------------------------------------------------
_cp1_check_pm_override() {
  local plan_evidence_root="$1" override_file reason
  override_file="$(_cp1_override_file "$plan_evidence_root")"
  [[ -f "$override_file" ]] || return 1
  reason="$(jq -r '.pm_ref // empty' "$override_file" 2>/dev/null || echo "")"
  [[ -n "$reason" && "${#reason}" -ge 20 ]] || return 1
  printf '%s' "$reason"
  return 0
}

# ---------------------------------------------------------------------------
# _cp1_claim_pm_override <plan_evidence_root>
#   Atomically CLAIMS (consumes) a present, valid PM-escalation override —
#   call this ONLY once a caller has determined the override is actually
#   needed (a check alone, via _cp1_check_pm_override, must never trigger
#   consumption). Attempts a no-clobber rename to a `.consumed-<epoch>`
#   sibling and returns 0 (echoing a JSON {reason, consumed_path} — the
#   caller needs consumed_path to bind the ledger's own pm_override record
#   to physical, verifiable evidence of a genuine claim, see cmd_increment
#   and cmd_check_budget below) iff BOTH `mv -n` itself reports success AND
#   the source file is confirmed gone afterward. The claim/consume LOGIC
#   mirrors aid-cp1-gate.sh's implementation exactly (including the round-3
#   fix requiring both mv exit code AND source-gone confirmation); the
#   return SHAPE (JSON, not a bare reason string) is specific to this file's
#   own downstream provenance-binding need.
# ---------------------------------------------------------------------------
_cp1_claim_pm_override() {
  local plan_evidence_root="$1" override_file consumed_file reason
  override_file="$(_cp1_override_file "$plan_evidence_root")"
  [[ -f "$override_file" ]] || return 1
  reason="$(jq -r '.pm_ref // empty' "$override_file" 2>/dev/null || echo "")"
  [[ -n "$reason" && "${#reason}" -ge 20 ]] || return 1

  consumed_file="${override_file}.consumed-$(date -u +%s)"
  if mv -n "$override_file" "$consumed_file" 2>/dev/null && [[ ! -f "$override_file" ]]; then
    jq -nc --arg reason "$reason" --arg consumed_path "$consumed_file" \
      '{reason:$reason, consumed_path:$consumed_path}'
    return 0
  fi
  # Either mv failed outright (a race loser, or a permission error), or it
  # no-op'd on a pre-existing destination (source still present) — we do
  # NOT own this override. Fail closed.
  return 1
}

# ---------------------------------------------------------------------------
# _json_str_or_null <maybe-string>  — JSON string if non-empty, else `null`.
# ---------------------------------------------------------------------------
_json_str_or_null() {
  if [[ -n "$1" ]]; then jq -n --arg s "$1" '$s'; else printf 'null'; fi
}

# ---------------------------------------------------------------------------
# _ledger_read_json <ledger_path> <expected_plan_id>
#   Reads the ledger YAML, converts to JSON, and validates the FULL ledger
#   invariant (8th DONE-review audit, P065 E-065-7_7: "CP1 revision-limit
#   ledger" finding — the prior check only validated TYPES, not VALUES:
#   attempts/max being syntactically numeric said nothing about them being
#   sane integers, matching the fixed policy budget, or internally
#   consistent with attempts_log. A semantically corrupted ledger — e.g.
#   attempts hand-edited to a negative/fractional number, max inflated past
#   MAX_ATTEMPTS, plan_id swapped, or attempts_log de-synced from attempts —
#   passed the old check and check-budget would then treat it as available,
#   silently reopening a budget that should be closed):
#     - attempts: integer (no fractional part), >= 0.
#     - max: integer, EQUAL TO this script's own MAX_ATTEMPTS constant — no
#       ledger may claim a different budget than the fixed policy allows;
#       there is no per-plan override mechanism for max, so any deviation
#       is definitionally tampering, not a legitimate variant.
#     - plan_id: non-empty string, and MUST equal the caller's expected
#       plan_id (catches a ledger file swapped/symlinked under a different
#       plan's path).
#     - attempts_log: an array whose length equals attempts (no silent
#       drift between the counter and its own audit trail), whose entries'
#       `n` values are exactly 1..attempts in order (no gaps, no
#       reordering, no duplicates), and whose every entry has a non-empty
#       string plan_hash (no null/blank hash entries).
#   Echoes the JSON on success; returns non-zero (fail-closed) on missing
#   file, unparseable YAML, or ANY invariant violation. Never partially
#   trusts a corrupt file.
# ---------------------------------------------------------------------------
_ledger_read_json() {
  local path="$1" expected_plan_id="$2"
  [[ -f "$path" ]] || return 1
  local json
  json="$(yq -o=json '.' "$path" 2>/dev/null)" || return 1
  [[ -n "$json" ]] || return 1
  printf '%s' "$json" | jq -e --arg plan_id "$expected_plan_id" --argjson max "$MAX_ATTEMPTS" '
    (.attempts | type == "number" and (. | floor) == . and . >= 0)
    and (.max | type == "number" and (. | floor) == . and . == $max)
    and (.plan_id | type == "string" and length > 0 and . == $plan_id)
    and (.attempts_log | type == "array")
    and ((.attempts_log | length) == .attempts)
    and ((.attempts_log | map(.n)) == [range(1; .attempts + 1)])
    and (.attempts_log | all(.plan_hash | type == "string" and length > 0))
  ' >/dev/null 2>&1 || return 1
  printf '%s' "$json"
}

# ---------------------------------------------------------------------------
# _write_ledger_json <ledger_path> <json>  — atomic temp+mv write, rendered
# as YAML (via yq, matching this project's YAML-state-file convention).
# ---------------------------------------------------------------------------
_write_ledger_json() {
  local path="$1" json="$2" tmp
  tmp="${path}.tmp.$$"
  printf '%s' "$json" | yq -p=json -o=yaml '.' > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$path" || { rm -f "$tmp"; return 1; }
  return 0
}

# ===========================================================================
# cmd_init [--pre-enforcement] [--project-root <path>] <plan_id>
# ===========================================================================
cmd_init() {
  local pre_enforcement=false project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pre-enforcement) pre_enforcement=true; shift ;;
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"
  [[ -d "$project_root" ]] || _fail "project_root not found: $project_root"

  local ledger_path; ledger_path="$(_ledger_path "$project_root" "$plan_id")"

  # Never overwrite an existing ledger — that would be a silent reset.
  if [[ -f "$ledger_path" ]]; then
    _fail "ledger already exists for ${plan_id} at ${ledger_path} — init will not overwrite an existing ledger (silent reset is forbidden). Use 'increment'/'read'/'check-budget', or a PM override to intentionally reset."
  fi

  local evidence_dir; evidence_dir="$(_cp1_evidence_dir "$project_root" "$plan_id")"
  if [[ "$pre_enforcement" != "true" ]]; then
    if _cp1_evidence_exists "$evidence_dir"; then
      _fail "CP1-deep evidence already exists for ${plan_id} at ${evidence_dir} — plan is not provably new. init (without --pre-enforcement) only seeds attempts:0 for a brand-new plan. Use 'init --pre-enforcement' for an explicit, audited bootstrap of an already in-flight plan."
    fi
  fi

  mkdir -p "$(dirname "$ledger_path")" || _fail "cannot create $(dirname "$ledger_path")"

  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local init_json
  init_json="$(jq -n \
    --arg sv "aid-2.0" \
    --arg pid "$plan_id" \
    --argjson max "$MAX_ATTEMPTS" \
    --argjson pre "$pre_enforcement" \
    --arg now "$now" \
    '{
      schema_version: $sv,
      plan_id: $pid,
      attempts: 0,
      max: $max,
      pre_enforcement: $pre,
      pm_override: {present: false, ref: null, claim_artifact: null, claim_sha256: null},
      created_at: $now,
      updated_at: $now,
      attempts_log: []
    }')" || _fail "cannot render initial ledger JSON"

  _write_ledger_json "$ledger_path" "$init_json" || _fail "cannot write ledger to ${ledger_path}"

  echo "$ledger_path"
  return 0
}

# ===========================================================================
# cmd_increment [--project-root <path>] [--codex-session <id>] <plan_id> <plan_hash>
# ===========================================================================
cmd_increment() {
  local project_root="" codex_session="" plan_id="" plan_hash=""
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      --codex-session) codex_session="${2:-}"; shift 2 ;;
      --codex-session=*) codex_session="${1#--codex-session=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *) positional+=("$1"); shift ;;
    esac
  done
  [[ ${#positional[@]} -eq 2 ]] || _fail "increment requires exactly <plan_id> <plan_hash> (got ${#positional[@]} positional args)"
  plan_id="${positional[0]}"
  plan_hash="${positional[1]}"
  _validate_plan_id "$plan_id"
  [[ -n "$plan_hash" ]] || _fail "plan_hash is empty"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local ledger_path; ledger_path="$(_ledger_path "$project_root" "$plan_id")"
  [[ -f "$ledger_path" ]] || _fail "ledger not found for ${plan_id} at ${ledger_path} — run 'init' first (increment never auto-creates a ledger)."

  # CONCURRENCY FIX (7th DONE-review audit, P065 E-065-7_7 — "CP1 ledger
  # concurrency"): everything from the read below through the final write is
  # an unlocked read-modify-write. Two concurrent new-hash `increment` calls
  # for the SAME plan_id could both read attempts=N, both derive new_n=N+1,
  # and the second write would silently clobber the first — losing an
  # attempts_log entry and letting the bounded-review counter under-count,
  # which is exactly the limit this ledger exists to enforce. Locked on a
  # SEPARATE .lock sidecar (not the ledger file itself), matching
  # aid-emit-dispatch.sh's established flock pattern: locking the data file
  # itself would race against _write_ledger_json's mktemp+mv (a concurrent
  # opener landing on the NEW inode after a rotation would acquire a
  # different lock — the sidecar's inode is stable across rotations).
  # `_fail` inside the subshell below only terminates the subshell (`exit 1`
  # scoped to `( ... )`); the `sub_rc` check after the block re-exits the
  # real process with that same code, preserving _fail's existing
  # process-wide-failure contract for every caller/test that checks it.
  local lockfile="${ledger_path}.lock"
  touch "$lockfile"
  (
  flock -x -w 10 200 \
    || { echo "PRECONDITION FAIL: increment lock timeout for ${plan_id} at ${lockfile} (another increment held it >10s)" >&2; exit 2; }

  local ledger_json
  ledger_json="$(_ledger_read_json "$ledger_path" "$plan_id")" \
    || _fail "ledger for ${plan_id} at ${ledger_path} is missing/corrupt/unparseable — cannot safely increment (fail-closed; obtain a PM override or investigate before re-init)."

  # NOTE (design decision, documented per Step-19 process instructions):
  # plan_hash is the sole gate on whether this call advances the counter, per
  # the acceptance criteria ("increment with an unchanged plan_hash is a
  # no-op; a new plan_hash advances the count"). codex_session is recorded as
  # per-attempt metadata (useful evidence for Step 20 / audit trail) but is
  # NOT an additional advance/no-op condition here — requiring both a new
  # plan_hash AND a new codex_session to differ would risk a stuck ledger if
  # a caller re-supplies the prior session id alongside a genuinely new
  # plan_hash. Session-repeat enforcement, if wanted, is Step 20's call.
  local last_hash attempts max
  last_hash="$(printf '%s' "$ledger_json" | jq -r '.attempts_log[-1].plan_hash // ""')"
  attempts="$(printf '%s' "$ledger_json" | jq -r '.attempts')"
  max="$(printf '%s' "$ledger_json" | jq -r '.max')"

  if [[ "$plan_hash" == "$last_hash" ]]; then
    printf '%s\n' "$ledger_json"
    return 0
  fi

  # FINDING 2 FIX: Reject an attempt to increment with a NEW plan_hash when
  # the ledger is already exhausted (attempts >= max). This is the
  # "Exhausted(n>=max) × new-hash increment" edge case that the audit's
  # state-matrix identified as missing. The no-op behavior for an UNCHANGED
  # plan_hash is NOT gated by budget — it's preserved exactly as above (never
  # mutates the ledger regardless of exhaustion).
  #
  # However, a valid PM-escalation override artifact can authorize exactly
  # ONE additional increment past max. Check for and claim it now.
  local override_used=false override_reason="" override_consumed_path="" override_consumed_sha256=""
  if [[ "$attempts" -ge "$max" ]]; then
    # Compute the plan-evidence-root where the override artifact lives.
    local plan_evidence_root
    plan_evidence_root="$(_cp1_plan_evidence_root "$project_root" "$plan_id")"

    # Attempt to claim the override atomically (consume it if present/valid).
    local claim_json
    if claim_json="$(_cp1_claim_pm_override "$plan_evidence_root")"; then
      # Override claim succeeded — permit this ONE increment past max.
      # The override is now consumed (renamed to .consumed-<epoch>), so a
      # SUBSEQUENT increment attempt would need a FRESH override.
      override_used=true
      override_reason="$(jq -r '.reason' <<<"$claim_json")"
      override_consumed_path="$(jq -r '.consumed_path' <<<"$claim_json")"
      # DONE-review #5 finding fix: capture a content hash of the ACTUAL
      # consumed artifact, not just the reason text — check-budget below
      # (and, more importantly, its own copy of this file at a later,
      # separate invocation) needs physical, verifiable evidence that this
      # specific pm_override.present:true entry corresponds to a genuine
      # atomic claim, not a bare hand-edited YAML boolean.
      override_consumed_sha256="sha256:$(sha256sum "$override_consumed_path" | awk '{print $1}')"
    else
      # No valid override present, or it was already consumed elsewhere.
      # Reject exactly as before (fail-closed).
      _fail "increment rejected: budget exhausted (attempts=$attempts >= max=$max) and new plan_hash supplied — cannot advance further. Use PM override if needed."
    fi
  fi

  local attempts new_n now
  attempts="$(printf '%s' "$ledger_json" | jq -r '.attempts')"
  new_n=$(( attempts + 1 ))
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # PERSIST the override decision in the ledger itself (not just the
  # transient artifact consumption) — a live DONE-review audit found the
  # earlier version of this fix consumed the override at THIS layer but
  # left aid-cp1-gate.sh's own SEPARATE check-budget call with no way to
  # know the resulting over-budget state was legitimately authorized (the
  # artifact was already gone by the time the gate read it), so a
  # genuinely clean 4th review still could not reach EPIC generation — the
  # PM's authorization was spent but never actually delivered its effect.
  # Every increment now explicitly records pm_override.present for the
  # CURRENT ledger tip: true only when THIS SPECIFIC advance was
  # override-claimed, false otherwise (clearing any stale true from a
  # PRIOR advance — pm_override always describes only the latest attempt,
  # never a standing/sticky bypass).
  #
  # DONE-review #5 finding fix: a 5th live audit found `present`/`ref` alone
  # is a bare, hand-editable YAML boolean+string with no provenance binding
  # — check-budget (below, and its own separate invocation from
  # aid-cp1-gate.sh) trusted it blindly, so directly hand-editing
  # pm_override.present=true in the ledger file granted the exact same
  # bypass a genuine PM-authorized claim does, with no corroborating
  # evidence required. claim_artifact/claim_sha256 bind this record to the
  # PHYSICAL, already-existing `.consumed-<epoch>` artifact
  # _cp1_claim_pm_override just created via its atomic rename — a real
  # claim always produces a genuine one; a bare boolean-only YAML hand-edit
  # does not.
  #
  # HONEST LIMIT (CP2 round-1 finding on this exact commit): this closes
  # the trivial "flip one boolean" bypass, but does NOT achieve
  # cryptographic unforgeability — a party with the SAME filesystem write
  # access this whole mechanism already trusts (this project's established
  # IMP-250 precedent) can still fabricate a fake .consumed-<epoch> file,
  # compute its real sha256, and hand-write matching claim_artifact/
  # claim_sha256 fields; check-budget cannot distinguish that forged pair
  # from a genuine claim, since it never inspects the artifact's OWN
  # content (e.g. that its pm_ref matches the ledger's recorded ref) or
  # binds it to a specific plan_id/attempt beyond filename+hash. This is a
  # real, acknowledged residual gap, not "solved" — it is accepted for now
  # because it requires understanding and replicating the exact multi-file
  # side effect of a real claim rather than a single-field edit, and stays
  # within the SAME IMP-250 trust boundary (filesystem write access to
  # .aid-o/work/) this project has already accepted elsewhere, not a NEW
  # exposure this fix introduces.
  local override_json
  if [[ "$override_used" == true ]]; then
    override_json="$(jq -nc \
      --arg ref "$override_reason" \
      --arg artifact "$(basename "$override_consumed_path")" \
      --arg sha "$override_consumed_sha256" \
      '{present: true, ref: $ref, claim_artifact: $artifact, claim_sha256: $sha}')"
  else
    override_json='{"present": false, "ref": null, "claim_artifact": null, "claim_sha256": null}'
  fi

  local cs_json new_json
  cs_json="$(_json_str_or_null "$codex_session")"
  new_json="$(printf '%s' "$ledger_json" | jq \
    --arg ph "$plan_hash" \
    --argjson cs "$cs_json" \
    --arg now "$now" \
    --argjson n "$new_n" \
    --argjson pmo "$override_json" \
    '.attempts = $n
     | .updated_at = $now
     | .pm_override = $pmo
     | .attempts_log += [{n: $n, plan_hash: $ph, codex_session: $cs, at: $now}]')" \
    || _fail "cannot compute updated ledger for ${plan_id}"

  _write_ledger_json "$ledger_path" "$new_json" || _fail "cannot write updated ledger to ${ledger_path}"

  printf '%s\n' "$new_json"
  ) 200>"$lockfile"
  local sub_rc=$?
  [[ "$sub_rc" -ne 0 ]] && exit "$sub_rc"
  return 0
}

# ===========================================================================
# cmd_read [--project-root <path>] <plan_id>
# ===========================================================================
cmd_read() {
  local project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local ledger_path; ledger_path="$(_ledger_path "$project_root" "$plan_id")"
  local ledger_json
  ledger_json="$(_ledger_read_json "$ledger_path" "$plan_id")" \
    || _fail "ledger for ${plan_id} at ${ledger_path} is missing or corrupt."

  printf '%s' "$ledger_json" | jq '.'
  return 0
}

# ===========================================================================
# cmd_check_budget [--project-root <path>] <plan_id>
#   Read-only status report. NEVER mutates the ledger or creates one.
# ===========================================================================
cmd_check_budget() {
  local project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local ledger_path evidence_dir evidence_present
  ledger_path="$(_ledger_path "$project_root" "$plan_id")"
  evidence_dir="$(_cp1_evidence_dir "$project_root" "$plan_id")"
  evidence_present="false"
  _cp1_evidence_exists "$evidence_dir" && evidence_present="true"

  # Case 1: no ledger file at all.
  if [[ ! -f "$ledger_path" ]]; then
    if [[ "$evidence_present" == "true" ]]; then
      # FAIL-CLOSED: CP1 evidence exists but no ledger — never auto-create a
      # zero ledger here (that would let deleting the file reset the budget).
      jq -n --arg pid "$plan_id" --argjson ev true \
        '{plan_id: $pid, status: "init_required", evidence_present: $ev, attempts: null, max: null, pm_override: false,
          reason: "CP1-deep evidence exists but no ledger was found. A missing ledger is treated as budget-exhausted, never a silent reset. Run init, or obtain a PM override."}'
      return 1
    fi
    jq -n --arg pid "$plan_id" --argjson ev false \
      '{plan_id: $pid, status: "not_initialized", evidence_present: $ev, attempts: null, max: null, pm_override: false,
        reason: "No ledger and no CP1-deep evidence yet — plan has not started CP1-deep review. Run init to begin tracking."}'
    return 2
  fi

  # Case 2: ledger file exists — validate it.
  local ledger_json
  if ! ledger_json="$(_ledger_read_json "$ledger_path" "$plan_id")"; then
    jq -n --arg pid "$plan_id" --argjson ev "$([[ "$evidence_present" == "true" ]] && echo true || echo false)" \
      '{plan_id: $pid, status: "init_required", evidence_present: $ev, attempts: null, max: null, pm_override: false,
        reason: "Ledger file exists but is corrupt/unparseable — treated as budget-exhausted. PM override required."}'
    return 1
  fi

  local attempts max
  attempts="$(printf '%s' "$ledger_json" | jq -r '.attempts')"
  max="$(printf '%s' "$ledger_json" | jq -r '.max')"
  local ev_bool; ev_bool="$([[ "$evidence_present" == "true" ]] && echo true || echo false)"

  # pm_override.present is SET by cmd_increment ONLY when that specific
  # advance was genuinely authorized by an atomically-claimed, single-use
  # PM-escalation override artifact. But the ledger YAML file itself is a
  # plain, non-tamper-evident file — cmd_increment being the INTENDED sole
  # writer does not mean it is the only POSSIBLE writer. A 5th live
  # DONE-review audit correctly found that check-budget trusted
  # `pm_override.present` blindly, so directly hand-editing that one
  # boolean field in the ledger granted the exact same over-budget bypass
  # as a genuine claim, with zero corroborating evidence — `test-cp1-
  # ledger.bats` and `test-cp1-gate.sh` even asserted this as CORRECT
  # behavior. Fix: do not trust the boolean alone. Require it to be
  # corroborated by the PHYSICAL `.consumed-<epoch>` artifact
  # cmd_increment's own atomic claim always creates (claim_artifact +
  # claim_sha256, written in lockstep with `present` — see cmd_increment).
  # A bare hand-edit of `present:true` with no matching, existing,
  # content-verified consumed-artifact file FAILS this check and falls
  # through to the honest "exhausted" status below — this is the
  # DONE-review #5 fix. This function remains READ-ONLY: it never mutates
  # the ledger or the artifact directory.
  local pm_override_present
  pm_override_present="$(printf '%s' "$ledger_json" | jq -r '.pm_override.present // false')"

  if [[ "$attempts" -ge "$max" ]]; then
    if [[ "$pm_override_present" == "true" ]]; then
      local pm_ref claim_artifact claim_sha256 plan_evidence_root claim_path claim_ok=false
      pm_ref="$(printf '%s' "$ledger_json" | jq -r '.pm_override.ref // ""')"
      claim_artifact="$(printf '%s' "$ledger_json" | jq -r '.pm_override.claim_artifact // ""')"
      claim_sha256="$(printf '%s' "$ledger_json" | jq -r '.pm_override.claim_sha256 // ""')"
      plan_evidence_root="$(_cp1_plan_evidence_root "$project_root" "$plan_id")"

      # Corroboration check: the claimed artifact's filename must match the
      # exact pattern _cp1_claim_pm_override produces (rejects path
      # traversal / pointing at an unrelated file), must exist under this
      # plan's OWN evidence root, and its CURRENT content hash must match
      # what cmd_increment recorded at claim time.
      if [[ -n "$claim_artifact" && -n "$claim_sha256" \
            && "$claim_artifact" == cp1-pm-escalation-override.json.consumed-* \
            && "$claim_artifact" != */* ]]; then
        claim_path="${plan_evidence_root}/${claim_artifact}"
        if [[ -f "$claim_path" ]]; then
          local actual_sha256
          actual_sha256="sha256:$(sha256sum "$claim_path" | awk '{print $1}')"
          [[ "$actual_sha256" == "$claim_sha256" ]] && claim_ok=true
        fi
      fi

      if [[ "$claim_ok" == true ]]; then
        jq -n --arg pid "$plan_id" --argjson attempts "$attempts" --argjson max "$max" --argjson ev "$ev_bool" --arg ref "$pm_ref" \
          '{plan_id: $pid, status: "available", evidence_present: $ev, attempts: $attempts, max: $max, pm_override: true,
            reason: ("attempts (" + ($attempts|tostring) + ") exceeds max (" + ($max|tostring) + ") but the LATEST attempt was PM-escalation-authorized: " + $ref)}'
        return 0
      fi

      jq -n --arg pid "$plan_id" --argjson attempts "$attempts" --argjson max "$max" --argjson ev "$ev_bool" \
        '{plan_id: $pid, status: "exhausted", evidence_present: $ev, attempts: $attempts, max: $max, pm_override: false,
          reason: "attempts >= max — revision budget exhausted. pm_override.present is set but could not be corroborated against a genuine, matching .consumed-<epoch> claim artifact (missing, unreadable, or content mismatch) — treated as untrusted, not a legitimate override. Use a fresh PM-escalation override if needed."}'
      return 1
    fi
    jq -n --arg pid "$plan_id" --argjson attempts "$attempts" --argjson max "$max" --argjson ev "$ev_bool" \
      '{plan_id: $pid, status: "exhausted", evidence_present: $ev, attempts: $attempts, max: $max, pm_override: false,
        reason: "attempts >= max — revision budget exhausted. Use PM-escalation override if needed."}'
    return 1
  fi

  jq -n --arg pid "$plan_id" --argjson attempts "$attempts" --argjson max "$max" --argjson ev "$ev_bool" \
    '{plan_id: $pid, status: "available", evidence_present: $ev, attempts: $attempts, max: $max, pm_override: false,
      reason: "within budget"}'
  return 0
}

# ===========================================================================
# cmd_claim_pm_override [--project-root <path>] <plan_id>
#
# 9th DONE-review audit fix (P065 E-065-7_7: "C0 bounded review lifecycle"
# finding): a thin CLI wrapper exposing THIS file's own `_cp1_claim_pm_override`
# / `_cp1_plan_evidence_root` primitives to OTHER scripts (aid-c0-plan-review.sh)
# that need the SAME single-use PM-escalation-override claim this file already
# uses for cmd_increment — reused verbatim, not reimplemented, per explicit PM
# instruction ("use the same cp1-pm-escalation-override.json / single-use claim
# pattern"). Atomically CONSUMES a present, valid override artifact
# (`<plan_evidence_root>/cp1-pm-escalation-override.json`, `{pm_ref: "<reason,
# >=20 chars>"}`) — a bare 20+-character string is NOT itself sufficient
# (that was the exact bypass this finding flagged elsewhere); the artifact
# must physically exist and be claimable. On success, prints
# `{reason, consumed_path}` (exit 0) — the caller MUST persist consumed_path
# (and its sha256) wherever it records that a bypass occurred, so a LATER,
# separate read can corroborate the claim rather than trust a bare boolean
# (mirrors cmd_increment's own pm_override.claim_artifact/claim_sha256
# binding). On no valid/present override, exits 1 with nothing printed —
# fail-closed, same as every other subcommand here.
# ===========================================================================
cmd_claim_pm_override() {
  local project_root="" plan_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="${2:-}"; shift 2 ;;
      --project-root=*) project_root="${1#--project-root=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) _fail "unknown flag: $1" ;;
      *)
        [[ -z "$plan_id" ]] || _fail "unexpected extra argument: $1"
        plan_id="$1"; shift ;;
    esac
  done
  _validate_plan_id "$plan_id"
  [[ -z "$project_root" ]] && project_root="$(pwd)"

  local plan_evidence_root claim_json
  plan_evidence_root="$(_cp1_plan_evidence_root "$project_root" "$plan_id")"
  if claim_json="$(_cp1_claim_pm_override "$plan_evidence_root")"; then
    printf '%s\n' "$claim_json"
    return 0
  fi
  _fail "no valid PM-escalation override artifact present for plan_id=${plan_id} (need ${plan_evidence_root}/cp1-pm-escalation-override.json with pm_ref >= 20 chars) — cannot claim"
}

# ===========================================================================
# main
# ===========================================================================
main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    _fail "missing subcommand"
  fi
  local sub="$1"; shift
  case "$sub" in
    init)               cmd_init "$@" ;;
    increment)          cmd_increment "$@" ;;
    read)               cmd_read "$@" ;;
    check-budget)       cmd_check_budget "$@" ;;
    claim-pm-override)  cmd_claim_pm_override "$@" ;;
    -h|--help)     usage; exit 0 ;;
    *)
      usage >&2
      _fail "unknown subcommand: $sub" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
