#!/usr/bin/env bash
# aid-bats-parallel-lane.sh — P071 EPIC E-071-1_1 Step 3 (PM review round 2 rewrite, 2026-08-02).
#
# Thin wrapper invoked as the `gate:bats_all`/`gate:bats_boundary` command
# (execution.yaml). It is NOT a second process supervisor: `bats -j N`
# already owns the parallel process lifecycle for its pool, unlike the
# sequential single-command-at-a-time model aid-job.sh implements.
#
# CLASSIFICATION MODEL (catalog provenance — P072 Step 17, 2026-08-03):
#   A bats file enters the PARALLEL pool only when the test catalog's
#   `parallel.status` for its run unit resolves to `safe` THROUGH
#   `aid_test_catalog_provenance_effective_status` — which means the status is
#   backed by evidence AND still bound to the content it was verified against.
#   A source change that alters the unit's resources reverts it to `unknown`,
#   and it drops out of the pool without anyone editing a list.
#
#   The verified bytes are re-checked immediately before dispatch, so a file
#   rewritten between classification and execution aborts the run rather than
#   entering the pool unverified. That narrows, but does not eliminate, the
#   window: only running from a private snapshot would, and this script
#   deliberately executes the caller's checkout.
#
#   This replaces a separate text allowlist. Until P072 Step 17 there were two
#   authorities over one question: the catalog carried `parallel.status` that
#   nothing read, and this script read a file the catalog knew nothing about.
#   Two authorities is how a promotion outlives the evidence behind it — the
#   list cannot know that the file it names has since acquired a lock.
#
#   The direction of the default is unchanged: anything not proven safe runs
#   sequentially. A brand-new bats file has no provenance, resolves to
#   `unknown`, and lands in the sequential bucket.
#
# Three buckets, always:
#   - SAFE_POOL[]     — effective status `safe`, not a known boundary file.
#                        Run together via `bats -j N`.
#   - UNCLASSIFIED[]   — everything else EXCEPT the 2 known boundary files:
#                        no provenance, stale provenance, or a non-`safe`
#                        status. Run ONE AT A TIME, sequentially — the safe
#                        default for anything unvetted, never dropped.
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
# shellcheck source=lib/aid-test-catalog-provenance.sh
source "$SCRIPT_DIR/lib/aid-test-catalog-provenance.sh"

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
Usage: aid-bats-parallel-lane.sh [--catalog PATH] [--jobs N]
                                  [--dry-run] [--pool-only | --dedicated-only]

  --catalog PATH     Path to test-catalog.yaml (default: ./.aid-o/config/test-catalog.yaml,
                      relative to the current working directory). Pool
                      eligibility comes from each unit's parallel.status as
                      resolved through its provenance — there is no separate
                      allowlist file.
  --jobs N           Parallel worker count for the safe pool (default: 4, or
                      \$AID_BATS_PARALLEL_JOBS if set)
  --dry-run          Print the resolved 3-bucket partition and exit 0 without
                      invoking bats
  --pool-only        Run SAFE_POOL (parallel) + UNCLASSIFIED (sequential),
                      skip BOUNDARY entirely
  --dedicated-only   Run ONLY BOUNDARY (sequential), skip SAFE_POOL and
                      UNCLASSIFIED entirely

Exit codes:
  0  catalog resolved, partition built, all requested phases passed
     (or --dry-run)
  1  one or more requested phases failed (a real bats test failure)
  2  catalog missing or malformed, a catalog-derived path failed
     validation (outside repo root, nonexistent, starts with '-', or a
     duplicate), or --pool-only + --dedicated-only both given — fail closed,
     never a partial or silently-adjusted file list
  3  required dependency missing (yq, bats, or GNU parallel for \`bats -j\`)
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
      [[ $# -ge 2 ]] || { echo "ERROR: aid-bats-parallel-lane.sh: --catalog requires a value" >&2; exit 2; }
      CATALOG_PATH="$2"
      shift 2
      ;;
    --allowlist)
      # Accepted and ignored, with a loud note: a caller still passing this is
      # relying on an authority that no longer exists, and silently honouring
      # nothing would leave them believing a list still governs the pool.
      [[ $# -ge 2 ]] || { echo "ERROR: aid-bats-parallel-lane.sh: --allowlist requires a value" >&2; exit 2; }
      echo "WARN: aid-bats-parallel-lane.sh: --allowlist is retired (P072 Step 17). Pool eligibility now comes from the catalog's parallel.status via its provenance; '$2' is not read." >&2
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

# ONE read of the catalog, into an immutable snapshot, before any decision is
# taken from it. The status check, the file list, the unit ids and the
# provenance resolution all come from THIS text. Reading the file four times
# meant a concurrent rewrite could pair a path from one version with a verdict
# from another.
CATALOG_SNAPSHOT="$(yq -o=json '.' "$CATALOG_PATH" 2>/dev/null)" || CATALOG_SNAPSHOT=""
if [[ -z "$CATALOG_SNAPSHOT" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: could not read the catalog at '$CATALOG_PATH'" >&2
  exit 2
fi
# The snapshot is written to a file so the resolver reads the same bytes rather
# than re-opening the live path.
CATALOG_FROZEN="$(mktemp)"
trap 'rm -f "$CATALOG_FROZEN"' EXIT
printf '%s' "$CATALOG_SNAPSHOT" | yq -P -o=yaml '.' > "$CATALOG_FROZEN" 2>/dev/null || {
  echo "ERROR: aid-bats-parallel-lane.sh: could not freeze the catalog snapshot" >&2
  exit 2
}

CATALOG_STATUS="$(jq -r '.status // ""' <<<"$CATALOG_SNAPSHOT")"
if [[ -z "$CATALOG_STATUS" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog at '$CATALOG_PATH' is malformed (no top-level 'status' field)" >&2
  exit 2
fi
if [[ "$CATALOG_STATUS" != "approved" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog at '$CATALOG_PATH' has status='$CATALOG_STATUS', not 'approved' — refusing to run against an unapproved catalog" >&2
  exit 2
fi

mapfile -t BATS_SOURCE_PATHS < <(
  jq -r '.run_units[] | select(.runner == "bats") | .source_paths[0]' <<<"$CATALOG_SNAPSHOT" 2>/dev/null
)

if [[ ${#BATS_SOURCE_PATHS[@]} -eq 0 ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: test catalog at '$CATALOG_PATH' yielded zero bats run_units — refusing to run with an empty file list" >&2
  exit 2
fi

# --- Pool eligibility, from the catalog (fail closed) -----------------------
# One call per unit, through the single function that applies the reversion
# rule. Reading `.parallel.status` directly would skip that rule, which is
# exactly the mistake having one authority is meant to prevent.
# ONE snapshot of the catalog, read once. Re-reading it per unit meant the
# eligibility decision and the unit-to-file mapping could come from two
# different versions of the file: a concurrent rewrite between the two reads
# could attach a `safe` verdict to a different path than the one it was made
# about.
CATALOG_SNAPSHOT="$(yq -o=json '.' "$CATALOG_PATH" 2>/dev/null)" || CATALOG_SNAPSHOT=""
if [[ -z "$CATALOG_SNAPSHOT" ]]; then
  echo "ERROR: aid-bats-parallel-lane.sh: could not read the catalog at '$CATALOG_PATH'" >&2
  exit 2
fi

declare -A ALLOWED_SET=()
declare -A ALLOWED_HASH=()
while IFS=$'\t' read -r unit_id ufile; do
  [[ -z "$unit_id" ]] && continue
  # The FROZEN snapshot, not the live path: the verdict and the path it is
  # about must come from the same bytes.
  eff="$(aid_test_catalog_provenance_effective_status "$unit_id" "$CATALOG_FROZEN" "$REPO_ROOT" 2>/dev/null || echo unknown)"
  [[ "$eff" == "safe" ]] || continue
  [[ -n "$ufile" ]] || continue
  ALLOWED_SET["$ufile"]=1
  # Remembered so the file can be re-checked immediately before dispatch.
  ALLOWED_HASH["$ufile"]="$(sha256sum "$REPO_ROOT/$ufile" 2>/dev/null | cut -d' ' -f1)"
done < <(jq -r '.run_units[] | select(.runner == "bats")
                | .run_unit_id + "\t" + ((.source_paths // [])[0] // "")' <<<"$CATALOG_SNAPSHOT")

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
    # Re-hash immediately before dispatch. Eligibility was decided from the
    # bytes on disk at partition time; anything that rewrites a file between
    # then and now (a concurrent checkout, a generator, a replaced symlink)
    # would put content into the pool that nothing ever verified. This does not
    # close the window entirely — nothing short of running from a private
    # snapshot could — but it narrows it from the whole partition pass to the
    # moment of dispatch, and a change inside it aborts rather than proceeds.
    RECHECK_FAILED=()
    for pooled in "${SAFE_POOL[@]}"; do
      now_hash="$(sha256sum "$REPO_ROOT/$pooled" 2>/dev/null | cut -d' ' -f1)"
      [[ "$now_hash" == "${ALLOWED_HASH[$pooled]:-}" ]] || RECHECK_FAILED+=("$pooled")
    done
    if [[ ${#RECHECK_FAILED[@]} -gt 0 ]]; then
      echo "ERROR: aid-bats-parallel-lane.sh: ${#RECHECK_FAILED[@]} pooled file(s) changed between classification and dispatch — refusing to run unverified content concurrently:" >&2
      printf '  - %s\n' "${RECHECK_FAILED[@]}" >&2
      exit 2
    fi
    echo "aid-bats-parallel-lane.sh: running ${#SAFE_POOL[@]} catalog-approved bats files in the safe pool (-j $JOBS)" >&2
    bats -j "$JOBS" "${SAFE_POOL[@]}"
    POOL_RC=$?
  else
    # An empty pool is a valid, safe state — not an error. It means no unit's
    # recorded status currently survives its own provenance check.
    echo "WARN: aid-bats-parallel-lane.sh: safe pool is empty (no catalog bats unit has an effective parallel status of 'safe') — running everything sequentially" >&2
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
