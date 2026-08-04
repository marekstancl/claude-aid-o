#!/usr/bin/env bash
# aid-test-execution-ledger.sh — P072 Step 26.
#
# Did anything run twice? A gate run that executes the same test file under two
# different gates pays for it twice and reports the wall clock as if it had run
# once. This repository does exactly that today.
#
# THE DEFECT THIS EXISTS TO CATCH, AND HOW IT NEARLY MISSED IT
#   `gate:bats_fsm` runs `bats …/test-aid-fsm.bats` directly. That same file is
#   also in the parallel pool, so `gate:bats_all` runs it too, and the `full`
#   and `release` profiles include both gates. The file therefore executes
#   twice on every full run.
#
#   Instrumenting only the three fan-out points — the bats lane, the aggregate
#   runner, the scheduler — would have recorded ONE entry for it and reported
#   zero duplicates. The ledger would have certified as clean the exact defect
#   it was built to detect. So there is a fourth emission path: the gate runner
#   itself appends for any gate whose command is a direct runner invocation it
#   can resolve. That path is not optional.
#
# WHY A GAP IS WORSE THAN A FAILURE
#   A ledger with a missing append is indistinguishable from one showing no
#   duplication, so every failure inside an accounted run is fatal: a lock that
#   cannot be taken, a ledger file that is not there, a write that fails.
#
#   The ONE permitted no-op is a dispatch point with no ledger path at all —
#   a developer invoking a suite by hand, where there is no run to account for.
#   That is the whole exemption. "The path was set but the file is missing" is
#   NOT that case, and used to be treated as though it were.
#
# WHY THERE IS NO MEMBERSHIP EXEMPTION
#   The obvious design is to exempt a pair of gates when one contains the
#   other — `gate:bats_all` does legitimately contain the units its lane runs.
#   That was built, and it immediately silenced the defect above: the pool gate
#   "contained" the file, so a genuine double execution reported as zero
#   duplicates.
#
#   The exemption answers a question that does not arise here. Each dispatch
#   point appends once per execution it actually performs, so two entries under
#   two gate ids ARE two executions. `--contains` is still accepted and
#   recorded, so a reader can see the membership relation at the time, but it
#   suppresses nothing.
#
# Exit codes: 0 ok · 2 usage · 3 unreadable ledger · 7 DOUBLE EXECUTION DETECTED

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_die() { echo "aid-test-execution-ledger.sh: $2" >&2; exit "$1"; }

# The lock discipline the queue writer already uses: a directory rename is
# atomic on every filesystem this runs on, and a stale lock times out loudly.
_ledger_lock() {
  local lockdir="$1.lock" waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.05
    waited=$(( waited + 1 ))
    if [[ "$waited" -gt 200 ]]; then
      _die 3 "could not acquire the ledger lock at '$lockdir' within 10s — refusing to append with a gap rather than recording an execution that may not be in the ledger"
    fi
  done
}
_ledger_unlock() { rmdir "$1.lock" 2>/dev/null || true; }

cmd_open() {
  local path="" run_id="" sha=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)          path="$2"; shift 2 ;;
      --run-id)        run_id="$2"; shift 2 ;;
      --candidate-sha) sha="$2"; shift 2 ;;
      *) _die 2 "open: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$path" && -n "$run_id" && -n "$sha" ]] \
    || _die 2 "open requires --path, --run-id and --candidate-sha"

  mkdir -p "$(dirname "$path")"
  jq -nc --arg r "$run_id" --arg s "$sha" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:"aid-test-execution-ledger-v1", run_id:$r, candidate_sha:$s,
      opened_at:$t, closed_at:null, entries:[]}' > "$path"
  printf '%s\n' "$path"
}

cmd_append() {
  local path="${AID_EXECUTION_LEDGER:-}" unit="" gate="" fp="" point="" kind="${AID_EXECUTION_KIND:-normal}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)        path="$2"; shift 2 ;;
      --run-unit-id) unit="$2"; shift 2 ;;
      --gate-id)     gate="$2"; shift 2 ;;
      --fingerprint) fp="$2"; shift 2 ;;
      --dispatch-point) point="$2"; shift 2 ;;
      --execution-kind) kind="$2"; shift 2 ;;
      *) _die 2 "append: unknown argument '$1'" ;;
    esac
  done

  # OUTSIDE an accounted run there is nothing to account for: a developer
  # invoking a suite by hand has no ledger, and that is not a defect.
  [[ -n "$path" ]] || return 0

  # INSIDE one, a named ledger that is not there is a GAP — and a gap is
  # exactly what this refuses to produce, because a ledger missing an entry is
  # indistinguishable from one showing no duplication. The earlier version
  # returned 0 here, which made "the file vanished" and "nothing ran twice"
  # the same observable outcome.
  [[ -f "$path" ]] || _die 3 "the ledger at '$path' does not exist, but this dispatch is inside an accounted gate run — refusing to execute a unit that no ledger will record"

  [[ -n "$unit" && -n "$gate" && -n "$point" ]] \
    || _die 2 "append requires --run-unit-id, --gate-id and --dispatch-point"
  [[ -n "$fp" ]] || fp="unknown"
  # Only the escalation/retry code paths may declare a repeat deliberate. An
  # unrecognised value is a typo, and a typo must not become a free pass.
  #
  # AID_EXECUTION_KIND is how a whole subprocess declares itself: P069's
  # escalation re-invokes the gate runner with the parent's ledger inherited,
  # so every append underneath it belongs to a rerun somebody asked for. An
  # explicit --execution-kind still wins over the environment.
  case "$kind" in
    normal|retry|escalation) ;;
    *) _die 2 "append: --execution-kind must be normal, retry or escalation (got '$kind')" ;;
  esac

  _ledger_lock "$path"
  local tmp; tmp="$(mktemp)"
  if jq -c --arg u "$unit" --arg g "$gate" --arg f "$fp" --arg p "$point" --arg k "$kind" \
       --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.entries += [{run_unit_id:$u, gate_id:$g, command_fingerprint:$f, dispatch_point:$p, execution_kind:$k, at:$t}]' \
       "$path" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$path"
    _ledger_unlock "$path"
  else
    rm -f "$tmp"; _ledger_unlock "$path"
    _die 3 "could not append to the ledger at '$path'"
  fi
  return 0
}

cmd_close() {
  local path="" contains_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --path)     path="$2"; shift 2 ;;
      --contains) contains_file="$2"; shift 2 ;;
      *) _die 2 "close: unknown argument '$1'" ;;
    esac
  done
  [[ -n "$path" && -f "$path" ]] || _die 3 "close: no ledger at '$path'"

  local contains='[]'
  if [[ -n "$contains_file" && -f "$contains_file" ]]; then
    contains="$(jq -c '.' "$contains_file" 2>/dev/null)" || contains='[]'
  fi

  _ledger_lock "$path"
  local tmp; tmp="$(mktemp)"
  # NO membership exemption. It was tried, and it silenced the exact defect
  # this ledger exists to find: `gate:bats_fsm` runs a file directly while
  # `gate:bats_all` runs it in the pool, and exempting "the pool gate contains
  # it" turned a genuine double execution into zero duplicates.
  #
  # The exemption was answering a question that does not arise here. Each
  # dispatch point appends once per execution it actually performs, so two
  # entries under two gate ids ARE two executions — the containment relation
  # would only matter if one execution were recorded twice, and none is:
  # `gate_runner_direct` appends only for commands that invoke a runner
  # directly, which the lane wrapper is not.
  #
  # `--contains` is still accepted and recorded so a reader can see what the
  # membership relation was at the time, but it does not suppress a finding.
  jq -c --argjson contains "$contains" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .entries as $e
    | ( [ $e[] | .run_unit_id ] | unique ) as $units
    | ( [ $units[] as $u
          | ( [ $e[] | select(.run_unit_id == $u) ] ) as $mine
          | ( [ $mine[] | .gate_id ] | unique ) as $gates
          | select(($gates | length) > 1)
          | { run_unit_id: $u,
              gate_ids: $gates,
              kinds: ([ $mine[] | (.execution_kind // "normal") ] | unique) } ] ) as $repeats
    # A repeat is DELIBERATE only if some execution said so at the time it
    # happened. Nothing can reclassify it afterwards, and the default is
    # `normal`, so silence never counts as a declaration.
    | ( [ $repeats[] | select(.kinds | any(. == "retry" or . == "escalation")) ] ) as $deliberate
    | ( [ $repeats[] | select(.kinds | any(. == "retry" or . == "escalation") | not)
          | {run_unit_id: .run_unit_id, gate_ids: .gate_ids} ] ) as $dups
    | .closed_at = $t
    | .summary = {dispatched: ($e | length), distinct_units: ($units | length),
                  duplicates: $dups, deliberate_repeats: $deliberate}
  ' "$path" > "$tmp" 2>/dev/null || { rm -f "$tmp"; _ledger_unlock "$path"; _die 3 "close: could not evaluate the ledger"; }
  mv "$tmp" "$path"
  _ledger_unlock "$path"

  local n_dup
  n_dup="$(jq -r '.summary.duplicates | length' "$path")"
  local n_del
  n_del="$(jq -r '.summary.deliberate_repeats | length' "$path")"
  echo "aid-test-execution-ledger: dispatched=$(jq -r '.summary.dispatched' "$path") distinct=$(jq -r '.summary.distinct_units' "$path") duplicates=${n_dup} deliberate_repeats=${n_del}"
  if [[ "$n_del" -gt 0 ]]; then
    # Declared, so not a failure — but never invisible. A rerun somebody asked
    # for still costs the wall clock twice, and that has to be readable.
    jq -r '.summary.deliberate_repeats[] | "  deliberate repeat: " + .run_unit_id + " ran under " + (.gate_ids | join(" AND ")) + " (" + (.kinds | join(",")) + ")"' "$path" >&2
  fi

  if [[ "$n_dup" -gt 0 ]]; then
    # Named, never counted: "2 duplicates" sends nobody anywhere.
    jq -r '.summary.duplicates[] | "  DOUBLE EXECUTION: " + .run_unit_id + " ran under " + (.gate_ids | join(" AND "))' "$path" >&2
    _die 7 "${n_dup} run unit(s) executed more than once in this gate run — the wall clock counts them twice and so does the cost"
  fi
  return 0
}

case "${1:-}" in
  open)   shift; cmd_open "$@" ;;
  append) shift; cmd_append "$@" ;;
  close)  shift; cmd_close "$@" ;;
  *) _die 2 "usage: aid-test-execution-ledger.sh {open|append|close} …" ;;
esac
