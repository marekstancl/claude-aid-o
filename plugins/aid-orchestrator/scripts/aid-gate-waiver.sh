#!/usr/bin/env bash
# aid-gate-waiver.sh — Gate-scoped PM waiver (IMP-270).
#
# A gate waiver authorizes exactly ONE gate's failed result to be reported as
# `waived` (never `pass`) for one exact (project, epic, run, HEAD, gate id,
# command fingerprint) tuple. Unlike the FSM `--force` override — which skips
# EVERY precondition of a transition — a waiver waives one gate's result and
# nothing else: all unrelated gates and all other FSM preconditions stay fully
# enforced. Missing, stale, forged, reused or cross-run authorizations fail.
#
# Usage:
#   aid-gate-waiver.sh issue   <gate_id> --evidence-dir <d> --reason '<>=20c>'
#                              [--expires-in <dur>] [--head <sha>]
#                              [--execution-yaml <path>] [--authorized-by <who>]
#                              [--project <id>] [--epic <id>] [--run <id>]
#   aid-gate-waiver.sh check   <gate_id> --evidence-dir <d>
#                              [--head <sha>] [--command-sha <sha256>]
#                              [--project <id>] [--epic <id>] [--run <id>]
#   aid-gate-waiver.sh consume <gate_id> --evidence-dir <d> [--by-run <run_id>]
#
# check prints one machine verdict on stdout and exits 0 only on `valid`:
#   valid | missing | expired | consumed | head_mismatch | command_mismatch | forged
#   (`forged` also covers a genuine-but-out-of-context artifact: a waiver whose
#    bound gate/project/epic/run do not match the context it is checked in —
#    e.g. a file copied into a different run's evidence dir.)
#
# consume atomically marks the waiver consumed (single-use). A second consume
# returns `already_consumed` idempotently (exit 0) — never double-spends.
#
# payload_sha256 integrity: a deterministic self-hash over the 13 BOUND fields
# (schema_version, artifact_type, gate_id, project_id, epic_id, run_id,
# head_sha, command_sha256, authorized_by, reason, issued_at, expires_at,
# single_use), canonicalised with `jq -Sc` over an explicit fixed key set so
# key order and optional-field presence are stable; the hash field itself and
# the mutable `consumed` block are excluded from its own input. Any hand-edit
# to a bound field re-hashes differently → `forged`; consuming only mutates
# `consumed`, so it never invalidates the hash.

set -euo pipefail

# ─── canonical bound-field projection (single source of truth) ──────────────
# Both issue (write) and check (verify) compute payload_sha256 over EXACTLY
# this projection, so the hash is deterministic across invocations.
_WAIVER_PAYLOAD_FILTER='{schema_version,artifact_type,gate_id,project_id,epic_id,run_id,head_sha,command_sha256,authorized_by,reason,issued_at,expires_at,single_use}'

_die() { echo "ERROR: aid-gate-waiver.sh: $*" >&2; exit 2; }

# gate ids reach a filename — charset-lock before any path use.
_validate_gate_id() {
  local g="$1"
  [[ -n "$g" ]] || _die "gate_id is required"
  [[ "$g" =~ ^[A-Za-z0-9._-]+$ ]] || _die "invalid gate_id '$g' (allowed: A-Z a-z 0-9 . _ -)"
}

_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Compute payload_sha256 over the canonical projection of a full waiver JSON doc.
# Reads the doc on stdin, prints the 64-hex digest.
_payload_hash() {
  jq -Sc "$_WAIVER_PAYLOAD_FILTER" | sha256sum | cut -d' ' -f1
}

_waiver_path() {
  local evidence_dir="$1" gate_id="$2"
  printf '%s/waivers/gate-waiver-%s.json' "$evidence_dir" "$gate_id"
}

# Derive project/epic/run context from the evidence dir path (+ git) when the
# caller did not pass explicit values. epic/run come from the path tail
# (.../<epic>/<run>); project from the git toplevel basename (best-effort).
_derive_run() { basename "$1"; }
_derive_epic() { basename "$(dirname "$1")"; }
_derive_project() {
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  [[ -n "$top" ]] && basename "$top" || echo ""
}

# Translate a compact duration (24h / 7d / 30m / 45s) into a `date -d` epoch.
# Prints ISO8601; empty string on parse failure.
_expires_at_from() {
  local dur="$1" n unit
  if [[ "$dur" =~ ^([0-9]+)([smhd])$ ]]; then
    n="${BASH_REMATCH[1]}"; unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) unit="seconds" ;; m) unit="minutes" ;;
      h) unit="hours" ;;   d) unit="days" ;;
    esac
    date -u -d "+${n} ${unit}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo ""
  else
    echo ""
  fi
}

cmd_issue() {
  local gate_id="$1"; shift
  _validate_gate_id "$gate_id"

  local evidence_dir="" reason="" expires_in="" head="" execution_yaml=""
  local authorized_by="PM" project="" epic="" run=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --evidence-dir)   evidence_dir="$2"; shift 2 ;;
      --reason)         reason="$2"; shift 2 ;;
      --expires-in)     expires_in="$2"; shift 2 ;;
      --head)           head="$2"; shift 2 ;;
      --execution-yaml) execution_yaml="$2"; shift 2 ;;
      --authorized-by)  authorized_by="$2"; shift 2 ;;
      --project)        project="$2"; shift 2 ;;
      --epic)           epic="$2"; shift 2 ;;
      --run)            run="$2"; shift 2 ;;
      *) _die "unknown issue arg: $1" ;;
    esac
  done

  [[ -n "$evidence_dir" ]] || _die "issue requires --evidence-dir"
  [[ ${#reason} -ge 20 ]] || _die "issue requires --reason of >=20 chars (got ${#reason})"

  # Resolve the gate command from execution.yaml (read-only) and fingerprint it.
  [[ -z "$execution_yaml" ]] && execution_yaml=".aid-o/config/execution.yaml"
  [[ -f "$execution_yaml" ]] || _die "execution.yaml not found at ${execution_yaml} (pass --execution-yaml)"
  local cmd
  cmd=$(GATE="$gate_id" yq '.gates[strenv(GATE)].command' "$execution_yaml" 2>/dev/null || echo "null")
  [[ -n "$cmd" && "$cmd" != "null" ]] || _die "unknown gate '${gate_id}' — no such key under .gates in ${execution_yaml} (refusing to issue)"
  local command_sha256
  command_sha256=$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)

  # HEAD binding.
  [[ -z "$head" ]] && head=$(git rev-parse HEAD 2>/dev/null || echo "")
  [[ "$head" =~ ^[0-9a-f]{40}$ ]] || _die "cannot resolve a 40-hex HEAD (got '${head}') — pass --head"

  # Context binding.
  [[ -z "$project" ]] && project=$(_derive_project)
  [[ -z "$project" ]] && project="unknown"
  [[ -z "$epic" ]] && epic=$(_derive_epic "$evidence_dir")
  [[ -z "$run" ]]  && run=$(_derive_run "$evidence_dir")

  local expires_at="null"
  if [[ -n "$expires_in" ]]; then
    local exp
    exp=$(_expires_at_from "$expires_in")
    [[ -n "$exp" ]] || _die "invalid --expires-in '${expires_in}' (use e.g. 24h, 7d, 30m, 45s)"
    expires_at="$exp"
  fi

  local waiver_file waiver_dir
  waiver_file=$(_waiver_path "$evidence_dir" "$gate_id")
  waiver_dir=$(dirname "$waiver_file")

  # Refuse to clobber an existing UNCONSUMED waiver (a fresh authorization must
  # be an explicit act, never an accidental overwrite of a live one).
  if [[ -f "$waiver_file" ]]; then
    local prev_consumed
    prev_consumed=$(jq -r '.consumed.at // "null"' "$waiver_file" 2>/dev/null || echo "null")
    [[ "$prev_consumed" == "null" ]] && _die "an unconsumed waiver already exists at ${waiver_file} (refusing to overwrite)"
  fi

  mkdir -p "$waiver_dir"

  # Build the bound payload, hash it, then assemble the full document. reason
  # (and every free string) reaches jq only via --arg (never interpolated).
  local issued_at payload full tmp
  issued_at=$(_now_iso)
  payload=$(jq -nc \
    --arg schema_version "aid-2.0" \
    --arg artifact_type  "gate_waiver" \
    --arg gate_id        "$gate_id" \
    --arg project_id     "$project" \
    --arg epic_id        "$epic" \
    --arg run_id         "$run" \
    --arg head_sha       "$head" \
    --arg command_sha256 "$command_sha256" \
    --arg authorized_by  "$authorized_by" \
    --arg reason         "$reason" \
    --arg issued_at      "$issued_at" \
    --arg expires_at     "$expires_at" \
    "{schema_version:\$schema_version, artifact_type:\$artifact_type, gate_id:\$gate_id, project_id:\$project_id, epic_id:\$epic_id, run_id:\$run_id, head_sha:\$head_sha, command_sha256:\$command_sha256, authorized_by:\$authorized_by, reason:\$reason, issued_at:\$issued_at, expires_at:(if \$expires_at==\"null\" then null else \$expires_at end), single_use:true}")

  local payload_sha256
  payload_sha256=$(printf '%s' "$payload" | _payload_hash)

  full=$(jq -c \
    --arg payload_sha256 "$payload_sha256" \
    '. + {payload_sha256:$payload_sha256, consumed:{at:null, by_run:null}}' \
    <<< "$payload")

  tmp=$(mktemp "${waiver_dir}/.gate-waiver-XXXXXX.tmp")
  printf '%s\n' "$full" > "$tmp"
  mv -f "$tmp" "$waiver_file"
  echo "issued ${waiver_file}" >&2
  echo "$waiver_file"
}

# _print_verdict <word> <exit_code> — stdout is exactly the verdict word.
_print_verdict() { printf '%s\n' "$1"; exit "$2"; }

cmd_check() {
  local gate_id="$1"; shift
  _validate_gate_id "$gate_id"

  local evidence_dir="" head="" command_sha="" project="" epic="" run=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --evidence-dir) evidence_dir="$2"; shift 2 ;;
      --head)         head="$2"; shift 2 ;;
      --command-sha)  command_sha="$2"; shift 2 ;;
      --project)      project="$2"; shift 2 ;;
      --epic)         epic="$2"; shift 2 ;;
      --run)          run="$2"; shift 2 ;;
      *) _die "unknown check arg: $1" ;;
    esac
  done
  [[ -n "$evidence_dir" ]] || _die "check requires --evidence-dir"

  local waiver_file
  waiver_file=$(_waiver_path "$evidence_dir" "$gate_id")
  [[ -f "$waiver_file" ]] || _print_verdict "missing" 3

  # Shape / schema validation → forged on any structural failure.
  jq -e '
    type=="object"
    and .artifact_type=="gate_waiver"
    and (.schema_version|type=="string")
    and (.gate_id|type=="string")
    and (.project_id|type=="string")
    and (.epic_id|type=="string")
    and (.run_id|type=="string")
    and (.head_sha|type=="string")
    and (.command_sha256|type=="string")
    and (.authorized_by|type=="string")
    and (.reason|type=="string")
    and (.issued_at|type=="string")
    and (has("expires_at"))
    and (.single_use|type=="boolean")
    and (.payload_sha256|type=="string")
    and (.consumed|type=="object")
    and (.consumed|has("at"))
    and (.consumed|has("by_run"))
  ' "$waiver_file" >/dev/null 2>&1 || _print_verdict "forged" 4

  # Integrity: recompute the payload hash over the SAME canonical projection.
  local stored_hash recomputed
  stored_hash=$(jq -r '.payload_sha256' "$waiver_file")
  recomputed=$(_payload_hash < "$waiver_file")
  [[ "$stored_hash" == "$recomputed" ]] || _print_verdict "forged" 4

  # Bound-context check — the artifact must match the context it is used in.
  # A genuine (hash-valid) waiver copied into a different gate/run/epic/project
  # is not authentic HERE → forged. gate is authoritative (drives the filename),
  # so a mismatch means the internal id was hand-edited.
  local f_gate f_project f_epic f_run
  f_gate=$(jq -r '.gate_id' "$waiver_file")
  f_project=$(jq -r '.project_id' "$waiver_file")
  f_epic=$(jq -r '.epic_id' "$waiver_file")
  f_run=$(jq -r '.run_id' "$waiver_file")

  [[ "$f_gate" == "$gate_id" ]] || _print_verdict "forged" 4

  local exp_epic exp_run exp_project
  exp_epic="${epic:-$(_derive_epic "$evidence_dir")}"
  exp_run="${run:-$(_derive_run "$evidence_dir")}"
  [[ "$f_epic" == "$exp_epic" ]] || _print_verdict "forged" 4
  [[ "$f_run"  == "$exp_run"  ]] || _print_verdict "forged" 4
  # project is best-effort: enforce only when we have an expected value to compare.
  exp_project="$project"
  [[ -z "$exp_project" ]] && exp_project=$(_derive_project)
  if [[ -n "$exp_project" ]]; then
    [[ "$f_project" == "$exp_project" ]] || _print_verdict "forged" 4
  fi

  # HEAD binding.
  local exp_head="$head"
  [[ -z "$exp_head" ]] && exp_head=$(git rev-parse HEAD 2>/dev/null || echo "")
  local f_head
  f_head=$(jq -r '.head_sha' "$waiver_file")
  [[ "$f_head" == "$exp_head" ]] || _print_verdict "head_mismatch" 5

  # Command binding (only enforced when the caller supplies a fingerprint).
  if [[ -n "$command_sha" ]]; then
    local f_cmd
    f_cmd=$(jq -r '.command_sha256' "$waiver_file")
    [[ "$f_cmd" == "$command_sha" ]] || _print_verdict "command_mismatch" 6
  fi

  # Expiry.
  local f_expires
  f_expires=$(jq -r '.expires_at // "null"' "$waiver_file")
  if [[ "$f_expires" != "null" ]]; then
    local now_epoch exp_epoch
    now_epoch=$(date -u +%s)
    exp_epoch=$(date -u -d "$f_expires" +%s 2>/dev/null || echo "")
    if [[ -n "$exp_epoch" ]] && (( now_epoch > exp_epoch )); then
      _print_verdict "expired" 7
    fi
  fi

  # Single-use consumption. A consumed waiver is spent for any NEW authorization
  # — EXCEPT when it was consumed by THIS very run (the legitimate state after
  # run-gates waived+consumed it during this run): that self-consumption is
  # acceptable evidence, so it re-validates as `valid` (idempotent within a run,
  # while a consumed copy presented in another run stays `consumed`).
  local f_single f_consumed_at f_consumed_by
  f_single=$(jq -r '.single_use' "$waiver_file")
  f_consumed_at=$(jq -r '.consumed.at // "null"' "$waiver_file")
  f_consumed_by=$(jq -r '.consumed.by_run // "null"' "$waiver_file")
  if [[ "$f_single" == "true" && "$f_consumed_at" != "null" ]]; then
    if [[ "$f_consumed_by" == "$exp_run" ]]; then
      _print_verdict "valid" 0
    fi
    _print_verdict "consumed" 8
  fi

  _print_verdict "valid" 0
}

cmd_consume() {
  local gate_id="$1"; shift
  _validate_gate_id "$gate_id"

  local evidence_dir="" by_run=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --evidence-dir) evidence_dir="$2"; shift 2 ;;
      --by-run)       by_run="$2"; shift 2 ;;
      *) _die "unknown consume arg: $1" ;;
    esac
  done
  [[ -n "$evidence_dir" ]] || _die "consume requires --evidence-dir"
  [[ -z "$by_run" ]] && by_run=$(_derive_run "$evidence_dir")

  local waiver_file waiver_dir
  waiver_file=$(_waiver_path "$evidence_dir" "$gate_id")
  [[ -f "$waiver_file" ]] || _die "no waiver to consume at ${waiver_file}"
  waiver_dir=$(dirname "$waiver_file")

  # Serialize consume with an flock on a per-waiver lock file so two concurrent
  # consumers can never both mint a first consumption.
  local lock_file="${waiver_file}.lock"
  exec 9>"$lock_file"
  flock 9

  local consumed_at
  consumed_at=$(jq -r '.consumed.at // "null"' "$waiver_file" 2>/dev/null || echo "null")
  if [[ "$consumed_at" != "null" ]]; then
    # Idempotent replay: return the already-consumed disposition, never re-spend.
    echo "already_consumed"
    return 0
  fi

  local now tmp full
  now=$(_now_iso)
  full=$(jq -c --arg at "$now" --arg by "$by_run" '.consumed = {at:$at, by_run:$by}' "$waiver_file")
  tmp=$(mktemp "${waiver_dir}/.gate-waiver-XXXXXX.tmp")
  printf '%s\n' "$full" > "$tmp"
  mv -f "$tmp" "$waiver_file"
  echo "consumed"
  return 0
}

case "${1:-}" in
  issue)   shift; cmd_issue "$@" ;;
  check)   shift; cmd_check "$@" ;;
  consume) shift; cmd_consume "$@" ;;
  *)
    [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
    echo "Usage: aid-gate-waiver.sh <issue|check|consume> <gate_id> --evidence-dir <d> [...]" >&2
    exit 1 ;;
esac
