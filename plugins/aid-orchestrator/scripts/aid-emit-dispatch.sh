#!/usr/bin/env bash
# aid-emit-dispatch.sh — Component A of P040 (Dispatch Lifecycle Enforcement Bundle)
#
# Wrapper script the orchestrator (LLM following pipeline.md §4) MUST call before
# and after every Agent({subagent_type, prompt}) dispatch. Writes timeline events
# (audit trail) AND maintains pending-dispatches.jsonl (reconciliation ledger
# consumed by aid-fsm.sh cmd_increment_step via fsm_check_orphan_dispatches).
#
# Per AID-v3-principles.md §1 — Detector without Enforcement is Decoration. This
# script is the emitter half; aid-fsm.sh:fsm_check_orphan_dispatches is the
# enforcement half.
#
# Empirical anchor: NR 8/10/13/14 fabricated provenance across 4 projects (P038,
# VULCAN P052/P054, AID-self P039); 5 weeks of evidence 2026-05-26 to 2026-05-31.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/aid-stage-log.sh"

usage() {
  cat >&2 <<EOF
Usage:
  aid-emit-dispatch.sh start --focus <id> --agent-id <id> --evidence-dir <path> [--expected-duration-max <seconds>]
  aid-emit-dispatch.sh complete --focus <id> --output-file <path> --evidence-dir <path>
EOF
  exit 1
}

# Focus default duration table (resolved when --expected-duration-max not given).
default_duration_for_focus() {
  local focus="$1"
  case "$focus" in
    cp1*)  echo 1200 ;;
    cp2-*) echo 600 ;;
    cp3-*) echo 900 ;;
    cp4-*) echo 600 ;;
    *)     echo 600 ;;
  esac
}

# Hard ceiling enforcement: no dispatch may declare an expected duration above
# 1800s. Anything larger is clamped.
clamp_duration() {
  local d="$1"
  [[ "$d" -gt 1800 ]] && echo 1800 || echo "$d"
}

cmd_start() {
  # Parse args ...
  local focus="" agent_id="" evidence_dir="" exp_dur=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --focus)                 focus="$2"; shift 2 ;;
      --agent-id)              agent_id="$2"; shift 2 ;;
      --evidence-dir)          evidence_dir="$2"; shift 2 ;;
      --expected-duration-max) exp_dur="$2"; shift 2 ;;
      *) echo "ERROR: unknown arg $1" >&2; exit 1 ;;
    esac
  done

  [[ -z "$focus" || -z "$agent_id" || -z "$evidence_dir" ]] && usage
  [[ ! -d "$evidence_dir" ]] && { echo "ERROR: evidence_dir does not exist: $evidence_dir" >&2; exit 1; }

  # Enforce agent_id invariant from Data Model line 440 (^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$).
  # Empirical anchor: P052 fabrication used agent_id strings that did not match
  # any real subagent type. Without regex enforcement the Data Model invariant is
  # decoration — see AID-v3-principles.md §1 (Detector without Enforcement is Decoration).
  if [[ ! "$agent_id" =~ ^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR: agent_id does not match required format <plugin>:<role> (got: $agent_id)" >&2
    exit 1
  fi

  # HIGH-1 defense-in-depth: allowlist the --focus value. A crafted focus such as
  # 'cp2-step-1","event":"complete","z":"' previously survived raw printf
  # interpolation and produced VALID JSONL with a duplicate "event" key, which
  # jq's last-key-wins resolved to event="complete" — making fsm_check_orphan_dispatches
  # skip a real expired orphan. The jq -nc construction below already neutralizes
  # injection, but we reject malformed focuses outright so they never enter the ledger.
  # Allowlist covers: cp1, cp2-step-N, cp3-code-review, cp3-security, cp4-curator-validation, reporter, simplifier.
  if [[ ! "$focus" =~ ^(cp[1-4](-step-[0-9]+|-[a-z][a-z0-9-]*)?|reporter|simplifier)$ ]]; then
    echo "ERROR: --focus does not match allowed pattern ^(cp[1-4](-step-[0-9]+|-[a-z][a-z0-9-]*)?|reporter|simplifier)\$ (got: $focus)" >&2
    exit 1
  fi

  [[ -z "$exp_dur" ]] && exp_dur=$(default_duration_for_focus "$focus")
  exp_dur=$(clamp_duration "$exp_dur")

  # Parse step_n from focus
  local step_n="null"
  if [[ "$focus" =~ ^cp2-step-([0-9]+)$ ]]; then
    step_n="${BASH_REMATCH[1]}"
  fi

  local ts pending="${evidence_dir}/pending-dispatches.jsonl"
  local lockfile="${pending}.lock"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # MEDIUM-1: per-entry collision-safe nonce. cmd_complete removes ONLY the line
  # with this exact nonce, so two same-focus starts in the same wall-clock second
  # plus one complete no longer double-clear (which previously dropped the second,
  # never-completed dispatch and let the orphan check pass). $RANDOM is 0..32767;
  # concatenating two draws plus nanosecond time makes within-run collision
  # vanishingly unlikely.
  local nonce
  nonce="${RANDOM}${RANDOM}-$(date +%s%N)"

  # Emit timeline event
  log_event "${evidence_dir}/timeline.jsonl" "verifier_dispatch_start" \
    focus="$focus" agent_id="$agent_id" step_n="$step_n" \
    evidence_dir="$evidence_dir" expected_duration_max="$exp_dur"

  # Build the pending-ledger line with jq -nc + --arg/--argjson so EVERY field is
  # RFC-8259-escaped (HIGH-1 fix). Raw printf interpolation of --focus/--evidence-dir
  # let a crafted value inject a duplicate "event" key and defeat the orphan check.
  # step_n is pre-validated upstream (regex capture is digits-only, else literal
  # `null`), so --argjson safely emits a JSON number or null — never a quoted string.
  local pending_line
  pending_line=$(jq -nc \
    --arg     ts        "$ts" \
    --arg     focus     "$focus" \
    --arg     agent_id  "$agent_id" \
    --argjson step_n    "$step_n" \
    --arg     evidence_dir "$evidence_dir" \
    --argjson expected_duration_max "$exp_dur" \
    --arg     nonce     "$nonce" \
    '{ts: $ts, event: "start", focus: $focus, agent_id: $agent_id,
      step_n: $step_n, evidence_dir: $evidence_dir,
      expected_duration_max: $expected_duration_max, nonce: $nonce}')

  # Append to pending ledger under flock on SEPARATE .lock sidecar.
  # Anti-race rationale (H11): cmd_complete swaps the inode of $pending via
  # mktemp + mv. If we locked the data file itself, a concurrent process opening
  # $pending after the mv would land on a NEW inode and acquire a different lock
  # — race window. The .lock sidecar inode is stable across data-file rotation.
  touch "$lockfile"
  (
    flock -x -w 5 200 || { echo "ERROR: flock timeout on $lockfile" >&2; exit 2; }
    printf '%s\n' "$pending_line" >> "$pending"
  ) 200>"$lockfile"
}

cmd_complete() {
  # Parse args ...
  local focus="" output_file="" evidence_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --focus)         focus="$2"; shift 2 ;;
      --output-file)   output_file="$2"; shift 2 ;;
      --evidence-dir)  evidence_dir="$2"; shift 2 ;;
      *) echo "ERROR: unknown arg $1" >&2; exit 1 ;;
    esac
  done

  [[ -z "$focus" || -z "$output_file" || -z "$evidence_dir" ]] && usage

  # Anti-fabrication (P037 lesson): output_file MUST exist on disk before we
  # accept the complete. Without this check, a fabricated path passes
  # reconciliation — the exact NR 8/10/13 failure mode P040 exists to prevent.
  [[ ! -f "$output_file" ]] && { echo "ERROR: output_file does not exist: $output_file" >&2; exit 2; }

  local pending="${evidence_dir}/pending-dispatches.jsonl"
  [[ ! -f "$pending" ]] && { echo "ERROR: no pending file at $pending" >&2; exit 2; }

  # Acquire flock, find + remove matching start entry
  local now_ts duration_sec agent_id step_n start_ts
  now_ts=$(date -u +%s)

  local lockfile="${pending}.lock"
  touch "$lockfile"

  # The flock-protected critical section runs in a plain subshell so the fd-200
  # redirect attaches to the lock sidecar exactly as in cmd_start (a command
  # substitution would not inherit fd 200 reliably). Variables set inside the
  # subshell do not survive into the parent, so the subshell writes the resolved
  # start_ts/agent_id/step_n to a result file we read afterward. Subshell exit
  # code (orphan=2, flock timeout=2) propagates via `set -e`.
  local resultf="${pending}.result.$$"
  rm -f "$resultf"
  (
    flock -x -w 5 200 || { echo "ERROR: flock timeout on $lockfile" >&2; exit 2; }

    # Find most recent unmatched start for this focus
    match=$(jq -c --arg f "$focus" 'select(.focus == $f and .event == "start")' "$pending" | tail -1)
    if [[ -z "$match" ]]; then
      echo "ERROR: orphan complete — no matching start for focus=$focus in $pending" >&2
      exit 2
    fi

    s_ts=$(echo "$match" | jq -r '.ts')
    a_id=$(echo "$match" | jq -r '.agent_id')
    s_n=$(echo "$match" | jq -r '.step_n')
    # MEDIUM-1: capture the matched entry's unique nonce so we remove EXACTLY one
    # line. Legacy entries (pre-nonce) yield "null" here; for those we fall back to
    # the old focus+ts predicate so old ledgers still drain.
    s_nonce=$(echo "$match" | jq -r '.nonce // "null"')

    # Remove matching line from pending file (atomic via temp + rename).
    # Inode of $pending changes here — that is why the flock must be on the
    # SEPARATE .lock sidecar (H11 fix), not on the data file itself.
    tmp=$(mktemp "${pending}.XXXXXX")
    if [[ "$s_nonce" == "null" ]]; then
      # Legacy entry without a nonce — preserve original focus+ts removal.
      jq -c --arg f "$focus" --arg ts "$s_ts" 'select(.focus != $f or .ts != $ts)' "$pending" > "$tmp"
    else
      # Remove ONLY the line carrying this exact nonce (one entry), so concurrent
      # same-focus+same-ts dispatches are not both cleared.
      jq -c --arg n "$s_nonce" 'select((.nonce // "") != $n)' "$pending" > "$tmp"
    fi
    mv "$tmp" "$pending"

    printf '%s\t%s\t%s\n' "$s_ts" "$a_id" "$s_n" > "$resultf"
  ) 200>"$lockfile"

  IFS=$'\t' read -r start_ts agent_id step_n < "$resultf"
  rm -f "$resultf"

  local start_epoch
  start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || echo "0")
  duration_sec=$((now_ts - start_epoch))

  # Emit timeline event (outside flock — log_event is independent append)
  local late_flag=""
  [[ "$duration_sec" -gt 1800 ]] && late_flag=" (LATE: >1800s ceiling)"

  log_event "${evidence_dir}/timeline.jsonl" "verifier_dispatch_complete" \
    focus="$focus" agent_id="$agent_id" step_n="$step_n" \
    evidence_dir="$evidence_dir" output_file="$output_file" \
    duration_sec="$duration_sec"

  if [[ -n "$late_flag" ]]; then
    echo "WARNING: dispatch complete arrived late$late_flag" >&2
  fi
  return 0
}

case "${1:-}" in
  start)    shift; cmd_start "$@" ;;
  complete) shift; cmd_complete "$@" ;;
  *)        usage ;;
esac
