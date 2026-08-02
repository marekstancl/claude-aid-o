#!/usr/bin/env bash
# aid-bats-parallel-lane.sh — P071 EPIC E-071-1_1 Step 3.
#
# Thin wrapper invoked as the `gate:bats_all` command (execution.yaml). It is
# NOT a second process supervisor: `bats -j N` already owns the parallel
# process lifecycle for its pool, unlike the sequential single-command-at-a-
# time model aid-job.sh implements. This script does exactly three things:
#
#   1. Resolve the approved test catalog (.aid-o/config/test-catalog.yaml)
#      and filter run_units to runner == "bats".
#   2. Partition those run_units into:
#        - $SAFE_POOL[]  — everything except the 2 known-unsafe boundary
#                          files, run together via `bats -j N`.
#        - $DEDICATED[]  — the 2 boundary files, each run in its own
#                          sequential `bats` invocation (never pooled,
#                          never concurrent with each other or the pool).
#   3. Exit non-zero if either phase fails (logical AND of both phases).
#
# The exclusion list below is NOT sourced from the catalog's `parallel.status`
# field (currently `unknown` for all 87 run_units as of the catalog this step
# reads) — it is the 2 specific files this plan's own diagnostic verified
# unsafe to pool (real git repos per test, dedicated CI jobs already exist for
# both — see run-all-tests.sh's DELEGATED_SUITES). A new bats file added to
# the catalog later lands in $SAFE_POOL automatically unless it is explicitly
# added to this exclusion list — that is the intended default.
#
# aid-select-tests.sh and aid-run-gates.sh are explicitly OUT OF SCOPE for
# this step (inherited from P066/P070) — this script does not modify or
# reimplement either; it is invoked as a plain gate `command:` and produces
# a single process exit code like any other declared-command gate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Boundary files excluded from the parallel pool (P071 E-071-1_1 Step 3,
# 2026-08-02) — both create a real Git repository per test and already own a
# dedicated CI job (run-all-tests.sh DELEGATED_SUITES), so they must never
# run inside the shared -j N pool nor concurrently with each other.
EXCLUDED_RELATIVE_PATHS=(
  "plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  "plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
)

usage() {
  cat <<'EOF'
Usage: aid-bats-parallel-lane.sh [--catalog PATH] [--jobs N] [--dry-run]
                                  [--pool-only | --dedicated-only]

  --catalog PATH     Path to test-catalog.yaml (default: ./.aid-o/config/test-catalog.yaml,
                      relative to the current working directory)
  --jobs N           Parallel worker count for the safe pool (default: 4, or
                      $AID_BATS_PARALLEL_JOBS if set)
  --dry-run          Print the resolved partition (safe pool + dedicated lane)
                      and exit 0 without invoking bats
  --pool-only        Run ONLY the safe pool phase, skip the dedicated lane
                      entirely (P071 Step 3 CP2 fix: lets `gate:bats_all`
                      carry a short, real timeout_seconds without being
                      killed by the 2 known-slow boundary files, which get
                      their own separate, non-required gate instead)
  --dedicated-only   Run ONLY the dedicated lane (the 2 boundary files,
                      sequential), skip the safe pool entirely

Exit codes:
  0  catalog resolved, partition built, all requested phases passed (or --dry-run)
  1  one or more requested phases (pool or dedicated) failed
  2  catalog missing or malformed (fail closed — never falls back to a
     partial or empty file list), or --pool-only + --dedicated-only both given
  3  required dependency missing (yq, bats, or GNU parallel for `bats -j`)
EOF
}

CATALOG_PATH="./.aid-o/config/test-catalog.yaml"
JOBS="${AID_BATS_PARALLEL_JOBS:-4}"
DRY_RUN=0
RUN_POOL=1
RUN_DEDICATED=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog)
      CATALOG_PATH="$2"
      shift 2
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --pool-only)
      RUN_DEDICATED=0
      shift
      ;;
    --dedicated-only)
      RUN_POOL=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: aid-bats-parallel-lane.sh: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $RUN_POOL -eq 0 && $RUN_DEDICATED -eq 0 ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: --pool-only and --dedicated-only are mutually exclusive" >&2
  exit 2
fi

# --- Dependency checks (fail loudly, never silently degrade) ---------------
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: aid-bats-parallel-lane.sh: required dependency 'yq' not found on PATH" >&2
  exit 3
fi
if ! command -v bats >/dev/null 2>&1; then
  echo "ERROR: aid-bats-parallel-lane.sh: required dependency 'bats' not found on PATH" >&2
  exit 3
fi
if ! command -v parallel >/dev/null 2>&1; then
  echo "ERROR: aid-bats-parallel-lane.sh: 'bats -j' requires GNU parallel, which was not found on PATH — refusing to silently fall back to serial execution" >&2
  exit 3
fi

# --- Catalog resolution (fail closed) ---------------------------------------
if [[ ! -f "$CATALOG_PATH" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog not found at '$CATALOG_PATH' — refusing to run with a partial or empty file list" >&2
  exit 2
fi

CATALOG_STATUS="$(yq -r '.status // ""' "$CATALOG_PATH" 2>/dev/null)"
if [[ -z "$CATALOG_STATUS" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog at '$CATALOG_PATH' is malformed (no top-level 'status' field)" >&2
  exit 2
fi
if [[ "$CATALOG_STATUS" != "approved" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog at '$CATALOG_PATH' has status='$CATALOG_STATUS', not 'approved' — refusing to run against an unapproved catalog" >&2
  exit 2
fi

mapfile -t BATS_SOURCE_PATHS < <(
  yq -r '.run_units[] | select(.runner == "bats") | .source_paths[0]' "$CATALOG_PATH" 2>/dev/null
)

if [[ ${#BATS_SOURCE_PATHS[@]} -eq 0 ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog at '$CATALOG_PATH' yielded zero bats run_units — refusing to run with an empty file list" >&2
  exit 2
fi

# --- Partition ---------------------------------------------------------------
is_excluded() {
  local candidate="$1"
  local excluded
  for excluded in "${EXCLUDED_RELATIVE_PATHS[@]}"; do
    [[ "$candidate" == "$excluded" ]] && return 0
  done
  return 1
}

SAFE_POOL=()
DEDICATED=()
for path in "${BATS_SOURCE_PATHS[@]}"; do
  [[ -z "$path" ]] && continue
  if is_excluded "$path"; then
    DEDICATED+=("$path")
  else
    SAFE_POOL+=("$path")
  fi
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "SAFE_POOL (${#SAFE_POOL[@]}):"
  printf '  %s\n' "${SAFE_POOL[@]}"
  echo "DEDICATED (${#DEDICATED[@]}):"
  printf '  %s\n' "${DEDICATED[@]}"
  exit 0
fi

# --- Execute: safe pool first (parallel), then dedicated lane (sequential) --
# Each phase only runs if requested (RUN_POOL/RUN_DEDICATED) — --pool-only and
# --dedicated-only let this script back two SEPARATE gates (P071 Step 3 CP2
# fix) so the fast, currently-reliable pool phase can carry a short required
# timeout without being killed by the 2 known-slow boundary files.
POOL_RC=0
if [[ $RUN_POOL -eq 1 ]]; then
  if [[ ${#SAFE_POOL[@]} -gt 0 ]]; then
    echo "aid-bats-parallel-lane.sh: running ${#SAFE_POOL[@]} bats files in the safe pool (-j $JOBS)" >&2
    bats -j "$JOBS" "${SAFE_POOL[@]}"
    POOL_RC=$?
  else
    echo "WARN: aid-bats-parallel-lane.sh: safe pool is empty (all bats run_units excluded)" >&2
  fi
fi

DEDICATED_RC=0
if [[ $RUN_DEDICATED -eq 1 ]]; then
  for file in "${DEDICATED[@]}"; do
    echo "aid-bats-parallel-lane.sh: running dedicated lane file '$file' (not pooled)" >&2
    bats "$file"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      DEDICATED_RC=$rc
    fi
  done
fi

if [[ $POOL_RC -ne 0 || $DEDICATED_RC -ne 0 ]]; then
  echo "aid-bats-parallel-lane.sh: FAILED — pool_exit=$POOL_RC dedicated_exit=$DEDICATED_RC" >&2
  exit 1
fi

echo "aid-bats-parallel-lane.sh: PASSED — pool_ran=$RUN_POOL (${#SAFE_POOL[@]} files) dedicated_ran=$RUN_DEDICATED (${#DEDICATED[@]} files)" >&2
exit 0
