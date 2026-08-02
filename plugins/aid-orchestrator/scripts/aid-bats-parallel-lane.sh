#!/usr/bin/env bash
# aid-bats-parallel-lane.sh — P071 EPIC E-071-1_1 Step 3 (PM review round 2 rewrite, 2026-08-02).
#
# Thin wrapper invoked as the `gate:bats_all`/`gate:bats_boundary` command
# (execution.yaml). It is NOT a second process supervisor: `bats -j N`
# already owns the parallel process lifecycle for its pool, unlike the
# sequential single-command-at-a-time model aid-job.sh implements.
#
# CLASSIFICATION MODEL (explicit allowlist, opt-in — PM review round 2):
#   A bats file enters the PARALLEL pool ONLY if its exact repo-relative path
#   is listed in the tracked allowlist file (default:
#   defaults/config/bats-parallel-safe-allowlist.txt, relative to this
#   script's own directory — never the caller's cwd). There is no blacklist
#   and no "default safe" fallback: the test catalog's `parallel.status`
#   field is NEVER consulted as a pool-eligibility signal (it is `unknown`
#   for every run_unit today and stays that way regardless of this script —
#   that field belongs to a separate, not-yet-built classification effort).
#   A brand-new bats file, or any file not on the allowlist for any reason,
#   is NEVER auto-parallel — it lands in the sequential UNCLASSIFIED bucket
#   instead (still executed, for full coverage, just one at a time).
#
# Three buckets, always:
#   - SAFE_POOL[]     — on the allowlist, not a known boundary file. Run
#                        together via `bats -j N`.
#   - UNCLASSIFIED[]   — everything else EXCEPT the 2 known boundary files:
#                        not on the allowlist (new file, or simply never
#                        reviewed). Run ONE AT A TIME, sequentially — the
#                        safe default for anything unvetted, never dropped.
#   - BOUNDARY[]       — the 2 files this plan's own diagnostic proved are
#                        individually too expensive/unstable to pool or run
#                        alongside anything else; always sequential, always
#                        alone.
#
# --pool-only    runs SAFE_POOL (parallel) + UNCLASSIFIED (sequential),
#                skips BOUNDARY — this is what `gate:bats_all` uses so it can
#                carry a short, real timeout_seconds without being killed by
#                the 2 boundary files.
# --dedicated-only runs ONLY BOUNDARY — what `gate:bats_boundary` uses
#                (required:false, generous timeout).
# (no flag)      runs all three buckets.
#
# aid-select-tests.sh and aid-run-gates.sh are explicitly OUT OF SCOPE for
# this step (inherited from P066/P070) — this script does not modify or
# reimplement either; it is invoked as a plain gate `command:` and produces
# a single process exit code like any other declared-command gate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The project root that catalog-derived paths are relative to is the CALLER's
# cwd (matching CATALOG_PATH's own cwd-relative default below) — NEVER this
# script's own on-disk location. This script is invoked from the target
# project's root (by aid-run-gates.sh, and by every test fixture that cd's
# into an isolated tmpdir project), which is not necessarily anywhere near
# where the plugin itself is installed.
REPO_ROOT="$(pwd)"
DEFAULT_ALLOWLIST="$SCRIPT_DIR/../defaults/config/bats-parallel-safe-allowlist.txt"

# Boundary files (P071 E-071-1_1 Step 3, 2026-08-02) — both create a real Git
# repository per test and already own a dedicated CI job (run-all-tests.sh
# DELEGATED_SUITES), so they must never run inside the shared -j N pool, in
# the sequential UNCLASSIFIED bucket, nor concurrently with each other.
BOUNDARY_RELATIVE_PATHS=(
  "plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  "plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
)

usage() {
  cat <<EOF
Usage: aid-bats-parallel-lane.sh [--catalog PATH] [--allowlist PATH] [--jobs N]
                                  [--dry-run] [--pool-only | --dedicated-only]

  --catalog PATH     Path to test-catalog.yaml (default: ./.aid-o/config/test-catalog.yaml,
                      relative to the current working directory)
  --allowlist PATH   Path to the approved-safe parallel-pool allowlist (default:
                      $DEFAULT_ALLOWLIST)
  --jobs N           Parallel worker count for the safe pool (default: 4, or
                      \$AID_BATS_PARALLEL_JOBS if set)
  --dry-run          Print the resolved 3-bucket partition and exit 0 without
                      invoking bats
  --pool-only        Run SAFE_POOL (parallel) + UNCLASSIFIED (sequential),
                      skip BOUNDARY entirely
  --dedicated-only   Run ONLY BOUNDARY (sequential), skip SAFE_POOL and
                      UNCLASSIFIED entirely

Exit codes:
  0  catalog + allowlist resolved, partition built, all requested phases passed
     (or --dry-run)
  1  one or more requested phases failed (a real bats test failure)
  2  catalog/allowlist missing or malformed, a catalog-derived path failed
     validation (outside repo root, nonexistent, starts with '-', or a
     duplicate), or --pool-only + --dedicated-only both given — fail closed,
     never a partial or silently-adjusted file list
  3  required dependency missing (yq, bats, or GNU parallel for \`bats -j\`)
EOF
}

CATALOG_PATH="./.aid-o/config/test-catalog.yaml"
ALLOWLIST_PATH="$DEFAULT_ALLOWLIST"
JOBS="${AID_BATS_PARALLEL_JOBS:-4}"
DRY_RUN=0
RUN_POOL=1
RUN_DEDICATED=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog)
      [[ $# -ge 2 ]] || { echo "ERROR: aid-bats-parallel-lane.sh: --catalog requires a value" >&2; exit 2; }
      CATALOG_PATH="$2"
      shift 2
      ;;
    --allowlist)
      [[ $# -ge 2 ]] || { echo "ERROR: aid-bats-parallel-lane.sh: --allowlist requires a value" >&2; exit 2; }
      ALLOWLIST_PATH="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || { echo "ERROR: aid-bats-parallel-lane.sh: --jobs requires a value" >&2; exit 2; }
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

# --jobs must be a positive integer — a malformed/empty value passed straight
# to `bats -j` produces a confusing bats-level usage error instead of naming
# THIS script as the source; fail closed here instead.
if ! [[ "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: --jobs (or \$AID_BATS_PARALLEL_JOBS) must be a positive integer, got '$JOBS'" >&2
  exit 2
fi

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

# --- Allowlist resolution (fail closed) -------------------------------------
if [[ ! -f "$ALLOWLIST_PATH" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: approved-safe allowlist not found at '$ALLOWLIST_PATH' — refusing to guess which files are pool-safe" >&2
  exit 2
fi

declare -A ALLOWED_SET=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue
  ALLOWED_SET["$line"]=1
done < "$ALLOWLIST_PATH"

# --- Path validation (fail closed — an invalid catalog-derived path aborts
# the WHOLE run, never a silent skip or a partial file list) ----------------
declare -A SEEN_PATHS=()
VALIDATION_ERRORS=()
for path in "${BATS_SOURCE_PATHS[@]}"; do
  [[ -z "$path" ]] && continue

  if [[ "$path" == -* ]]; then
    VALIDATION_ERRORS+=("path begins with '-' (argument-injection risk against bats' own CLI): '$path'")
    continue
  fi

  if [[ -n "${SEEN_PATHS[$path]:-}" ]]; then
    VALIDATION_ERRORS+=("duplicate catalog entry: '$path'")
    continue
  fi
  SEEN_PATHS["$path"]=1

  if [[ ! -f "$REPO_ROOT/$path" ]]; then
    VALIDATION_ERRORS+=("file does not exist at '$REPO_ROOT/$path' (path: '$path')")
    continue
  fi

  # Resolve the real absolute path and confirm it is still under REPO_ROOT —
  # catches '../' escapes and symlink escapes alike. realpath is coreutils,
  # already a hard dependency of this codebase's other scripts.
  resolved="$(cd "$REPO_ROOT" && realpath -m -- "$path" 2>/dev/null)"
  case "$resolved" in
    "$REPO_ROOT"/*) : ;; # inside repo root, fine
    *)
      VALIDATION_ERRORS+=("path escapes repo root: '$path' resolves to '$resolved'")
      continue
      ;;
  esac
done

if [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: refusing to run — ${#VALIDATION_ERRORS[@]} invalid catalog-derived path(s):" >&2
  printf '  - %s\n' "${VALIDATION_ERRORS[@]}" >&2
  exit 2
fi

# --- Partition (3 buckets, allowlist-driven, opt-in) -------------------------
is_boundary() {
  local candidate="$1" b
  for b in "${BOUNDARY_RELATIVE_PATHS[@]}"; do
    [[ "$candidate" == "$b" ]] && return 0
  done
  return 1
}

SAFE_POOL=()
UNCLASSIFIED=()
BOUNDARY=()
for path in "${BATS_SOURCE_PATHS[@]}"; do
  [[ -z "$path" ]] && continue
  if is_boundary "$path"; then
    BOUNDARY+=("$path")
  elif [[ -n "${ALLOWED_SET[$path]:-}" ]]; then
    SAFE_POOL+=("$path")
  else
    UNCLASSIFIED+=("$path")
  fi
done

if [[ $DRY_RUN -eq 1 ]]; then
  echo "SAFE_POOL (${#SAFE_POOL[@]}):"
  printf '  %s\n' "${SAFE_POOL[@]}"
  echo "UNCLASSIFIED (${#UNCLASSIFIED[@]}):"
  printf '  %s\n' "${UNCLASSIFIED[@]}"
  echo "BOUNDARY (${#BOUNDARY[@]}):"
  printf '  %s\n' "${BOUNDARY[@]}"
  exit 0
fi

# --- Execute -----------------------------------------------------------------
# --pool-only  -> SAFE_POOL (parallel) + UNCLASSIFIED (sequential)
# --dedicated-only -> BOUNDARY only (sequential)
# (default)    -> all three
POOL_RC=0
UNCLASSIFIED_RC=0
BOUNDARY_RC=0

if [[ $RUN_POOL -eq 1 ]]; then
  if [[ ${#SAFE_POOL[@]} -gt 0 ]]; then
    echo "aid-bats-parallel-lane.sh: running ${#SAFE_POOL[@]} allowlisted bats files in the safe pool (-j $JOBS)" >&2
    bats -j "$JOBS" "${SAFE_POOL[@]}"
    POOL_RC=$?
  else
    echo "WARN: aid-bats-parallel-lane.sh: safe pool is empty (no catalog bats file is on the allowlist)" >&2
  fi

  if [[ ${#UNCLASSIFIED[@]} -gt 0 ]]; then
    echo "aid-bats-parallel-lane.sh: running ${#UNCLASSIFIED[@]} UNCLASSIFIED bats file(s) sequentially (not on the allowlist — safe default, never auto-pooled)" >&2
    for file in "${UNCLASSIFIED[@]}"; do
      echo "aid-bats-parallel-lane.sh: running unclassified file '$file'" >&2
      bats "$file"
      rc=$?
      [[ $rc -ne 0 ]] && UNCLASSIFIED_RC=$rc
    done
  fi
fi

if [[ $RUN_DEDICATED -eq 1 ]]; then
  for file in "${BOUNDARY[@]}"; do
    echo "aid-bats-parallel-lane.sh: running boundary lane file '$file' (not pooled, not unclassified)" >&2
    bats "$file"
    rc=$?
    [[ $rc -ne 0 ]] && BOUNDARY_RC=$rc
  done
fi

if [[ $POOL_RC -ne 0 || $UNCLASSIFIED_RC -ne 0 || $BOUNDARY_RC -ne 0 ]]; then
  echo "aid-bats-parallel-lane.sh: FAILED — pool_exit=$POOL_RC unclassified_exit=$UNCLASSIFIED_RC boundary_exit=$BOUNDARY_RC" >&2
  exit 1
fi

echo "aid-bats-parallel-lane.sh: PASSED — pool_ran=$RUN_POOL (safe=${#SAFE_POOL[@]} unclassified=${#UNCLASSIFIED[@]}) dedicated_ran=$RUN_DEDICATED (boundary=${#BOUNDARY[@]})" >&2
exit 0
