#!/usr/bin/env bats
# test-aid-bats-parallel-lane.bats — P071 EPIC E-071-1_1 Step 3 (PM review
# round 2 rewrite, 2026-08-02).
#
# Covers aid-bats-parallel-lane.sh, the wrapper that replaced the
# `gate:bats_all` quarantine stub (`exit 86`).
#
# P072 Step 17 moved the classification model: pool eligibility comes from the
# CATALOG's `parallel.status`, resolved through its provenance, and the
# separate text allowlist is retired. The direction of the default is
# unchanged — anything not proven safe runs sequentially — so most of this
# suite is untouched. The fixtures below now express eligibility in the
# catalog rather than in a list.
#   1. Partition logic (3 buckets): SAFE_POOL is ONLY what the catalog says is
#      safe AND still bound to its verified content; a brand-new bats file has
#      no provenance, resolves to `unknown`, and lands in the sequential
#      UNCLASSIFIED bucket — NEVER auto-parallel. The 2 known boundary files
#      always land in BOUNDARY regardless of their catalog status.
#   2. Fail-closed path validation: a catalog-derived path that doesn't
#      exist, escapes the repo root, starts with '-', or duplicates another
#      entry aborts the WHOLE run (exit 2) before any bats invocation.
#   3. A real (not mocked) small-scale invocation actually runs `bats -j N`
#      over an allowlisted pool plus sequential phases, and the gate's exit
#      code is the logical AND of all requested phases.
#
# All fixtures are throwaway bats files under a per-test tmpdir mimicking the
# real repo's relative path layout (plugins/aid-orchestrator/scripts/tests/
# bats/...) — the boundary list and path-validation logic in
# aid-bats-parallel-lane.sh operate on literal relative-path matches, so
# fixtures must sit at those exact relative paths to exercise it for real.
# Each test writes its OWN throwaway catalog so tests never depend on (or
# mutate) this repository's real one.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../aid-bats-parallel-lane.sh"
  TMP="$(mktemp -d)"
  PROJECT="$TMP/project"
  BATS_DIR="$PROJECT/plugins/aid-orchestrator/scripts/tests/bats"
  mkdir -p "$BATS_DIR"
  CATALOG="$PROJECT/.aid-o/config/test-catalog.yaml"
  mkdir -p "$(dirname "$CATALOG")"
  ALLOWLIST="$TMP/allowlist.txt"
  : > "$ALLOWLIST"
  # shellcheck disable=SC1090
  source "${BATS_TEST_DIRNAME}/../../lib/aid-test-catalog-provenance.sh"
  ALLOWED_UNITS=()
}

# _allow <relative_path>... — mark these paths pool-eligible.
#
# Eligibility now lives in the catalog, so this records the paths and
# _write_catalog binds each one to its real source hash and resource digest —
# the same shape a migrated or piloted entry has. Writing `status: safe` with
# no provenance would not work, and should not: an unbound status is not
# evidence.
_allow() {
  local rel
  for rel in "$@"; do
    ALLOWED_UNITS+=("$rel")
  done
  # Order-independent: several existing tests call this AFTER writing the
  # catalog, which was harmless when eligibility lived in a separate file. Now
  # it does not, so mark and bind immediately when the catalog already exists.
  [[ -f "${CATALOG:-}" ]] && _mark_allowed_in_catalog "$CATALOG"
  return 0
}

# _mark_allowed_in_catalog <catalog> — set status and bind provenance for every
# recorded path. An unbound `safe` resolves to `unknown`, correctly, so the
# binding is what makes these fixtures exercise anything.
_mark_allowed_in_catalog() {
  local catalog="$1" rel uid h d
  for rel in "${ALLOWED_UNITS[@]:-}"; do
    [[ -z "$rel" ]] && continue
    uid="bats:${rel%.bats}"
    jq -e --arg id "$uid" '.run_units[] | select(.run_unit_id == $id)' \
      <(yq -o=json '.' "$catalog" 2>/dev/null) >/dev/null 2>&1 || continue
    h="$(aid_test_catalog_provenance_hash "$uid" "$catalog" "$PROJECT" 2>/dev/null)"
    d="$(aid_test_catalog_provenance_resource_digest "$uid" "$catalog" "$PROJECT" 2>/dev/null)"
    [[ "$h" =~ ^[0-9a-f]{64}$ ]] || continue
    B_ID="$uid" B_H="$h" B_D="$d" yq -i '
      (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.status) = "safe"
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.evidence_ref) = "fixture-pilot"
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.verified_at) = "2026-08-02T00:00:00Z"
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.method) = "resource_map_plus_pilot"
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.source_sha256) = strenv(B_H)
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.resource_digest) = strenv(B_D)' \
      "$catalog"
  done
  return 0
}

_is_allowed() {
  local rel="$1" a
  for a in "${ALLOWED_UNITS[@]:-}"; do [[ "$a" == "$rel" ]] && return 0; done
  return 1
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
}

# _write_passing_bats <path>
#
# NOTE: the "@test" marker is built via concatenation ("@" + "test"), not
# written literally in this file — bats' own test-count scanner statically
# greps *.bats files for "@test" lines, so a literal occurrence inside this
# heredoc would be miscounted as an extra test in THIS suite's own plan.
_write_passing_bats() {
  {
    echo "#!/usr/bin/env bats"
    printf '%stest "always passes" {\n' "@"
    echo "  true"
    echo "}"
  } > "$1"
}

# _write_failing_bats <path>
_write_failing_bats() {
  {
    echo "#!/usr/bin/env bats"
    printf '%stest "always fails" {\n' "@"
    echo "  false"
    echo "}"
  } > "$1"
}

# _write_catalog <catalog_path> <bats_relative_path>...
# Writes a minimal approved catalog whose run_units are the given bats
# files (runner: bats) plus one unrelated declared-command run_unit, to
# prove the runner=="bats" filter actually filters.
_write_catalog() {
  local catalog="$1"
  shift
  {
    echo "schema_version: 1.0.0"
    echo "generated_at: \"2026-08-02T00:00:00Z\""
    echo "status: approved"
    echo "run_units:"
    for rel in "$@"; do
      echo "  - run_unit_id: bats:${rel%.bats}"
      echo "    runner: bats"
      echo "    source_paths:"
      echo "      - ${rel}"
      echo "    parallel:"
      if _is_allowed "$rel"; then
        echo "      status: safe"
      else
        echo "      status: unknown"
      fi
      echo "      exclusive_resources: []"
      echo "      max_workers: null"
      echo "      internal_parallelism: false"
      echo "      provenance:"
      if _is_allowed "$rel"; then
        echo "        evidence_ref: \"fixture-pilot\""
        echo "        verified_at: \"2026-08-02T00:00:00Z\""
        echo "        method: resource_map_plus_pilot"
        echo "        source_sha256: \"PLACEHOLDER\""
        echo "        resource_digest: \"PLACEHOLDER\""
      else
        echo "        evidence_ref: null"
        echo "        verified_at: null"
        echo "        method: null"
        echo "        source_sha256: null"
        echo "        resource_digest: null"
      fi
    done
    echo "  - run_unit_id: declared-command:not-a-bats-file"
    echo "    runner: declared-command"
    echo "    source_paths:"
    echo "      - scripts/some-other-thing.sh"
  } > "$catalog"

  _mark_allowed_in_catalog "$catalog"
}

# --- Partition logic (--dry-run, no real bats execution) -------------------

@test "partition: both boundary files always land in BOUNDARY regardless of catalog status" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local safe2="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-b.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_passing_bats "$PROJECT/$safe2"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1" "$safe2"
  # Deliberately mark the boundary files safe too — BOUNDARY must win anyway,
  # because their exclusion is a cost decision, not a safety one.
  _allow "$final" "$release" "$safe1" "$safe2"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"BOUNDARY (2):"* ]]
  [[ "$output" == *"SAFE_POOL (2):"* ]]
  [[ "$output" == *"UNCLASSIFIED (0):"* ]]

  local pool_block
  pool_block="$(printf '%s\n' "$output" | awk '/^SAFE_POOL/{f=1} /^UNCLASSIFIED/{f=0} f')"
  [[ "$pool_block" != *"$final"* ]]
  [[ "$pool_block" != *"$release"* ]]
  [[ "$pool_block" == *"$safe1"* ]]
  [[ "$pool_block" == *"$safe2"* ]]
}

@test "REGRESSION: a bats file the catalog does not call safe never enters SAFE_POOL — lands in UNCLASSIFIED instead" {
  local allowed="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-allowed.bats"
  local newfile="plugins/aid-orchestrator/scripts/tests/bats/test-brand-new-suite.bats"

  _write_passing_bats "$PROJECT/$allowed"
  _write_passing_bats "$PROJECT/$newfile"
  _write_catalog "$CATALOG" "$allowed" "$newfile"
  _allow "$allowed"
  # $newfile is deliberately NOT added to the allowlist.

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_POOL (1):"* ]]
  [[ "$output" == *"UNCLASSIFIED (1):"* ]]

  local pool_block unclassified_block
  pool_block="$(printf '%s\n' "$output" | awk '/^SAFE_POOL/{f=1} /^UNCLASSIFIED/{f=0} f')"
  unclassified_block="$(printf '%s\n' "$output" | awk '/^UNCLASSIFIED/{f=1} /^BOUNDARY/{f=0} f')"
  [[ "$pool_block" == *"$allowed"* ]]
  [[ "$pool_block" != *"$newfile"* ]]
  [[ "$unclassified_block" == *"$newfile"* ]]
  [[ "$unclassified_block" != *"$allowed"* ]]
}

@test "REGRESSION (PM review round 2): the catalog's parallel.status field is never consulted — an 'unknown'-status file still requires an explicit allowlist entry" {
  # This catalog fixture mirrors the real catalog shape: every run_unit
  # carries parallel.status: unknown. The script must classify purely off
  # the allowlist, never off this field (it doesn't even read it).
  local unknown="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-unknown-status.bats"
  _write_passing_bats "$PROJECT/$unknown"
  {
    echo "schema_version: 1.0.0"
    echo "status: approved"
    echo "run_units:"
    echo "  - run_unit_id: bats:${unknown%.bats}"
    echo "    runner: bats"
    echo "    source_paths:"
    echo "      - ${unknown}"
    echo "    parallel:"
    echo "      status: unknown"
  } > "$CATALOG"
  # Not on the allowlist.

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_POOL (0):"* ]]
  [[ "$output" == *"UNCLASSIFIED (1):"* ]]
  [[ "$output" == *"$unknown"* ]]
}

@test "partition: declared-command run_units are filtered out (only runner==bats counted)" {
  local safe="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-only.bats"
  _write_passing_bats "$PROJECT/$safe"
  _write_catalog "$CATALOG" "$safe"
  _allow "$safe"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"some-other-thing.sh"* ]]
}

@test "partition: with nothing marked safe, every non-boundary file lands in UNCLASSIFIED" {
  local a="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local b="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-b.bats"
  _write_passing_bats "$PROJECT/$a"
  _write_passing_bats "$PROJECT/$b"
  _write_catalog "$CATALOG" "$a" "$b"
  # $ALLOWLIST stays empty (from setup()).

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_POOL (0):"* ]]
  [[ "$output" == *"UNCLASSIFIED (2):"* ]]
}

# --- Fail-closed catalog/allowlist handling ---------------------------------

@test "error handling: missing catalog file fails loudly (exit 2), never an empty run" {
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$PROJECT/.aid-o/config/does-not-exist.yaml" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "error handling: a missing allowlist file is no longer fatal — it is not read at all" {
  # P072 Step 17 retired that authority. A caller still passing --allowlist is
  # told plainly that it is ignored, rather than being failed on a file whose
  # contents would not have been used anyway.
  local safe="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  _write_passing_bats "$PROJECT/$safe"
  _write_catalog "$CATALOG" "$safe"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$TMP/does-not-exist-allowlist.txt" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"retired"* ]]
}

@test "error handling: catalog missing a 'status' field is malformed (exit 2)" {
  cat > "$CATALOG" <<'YAML'
schema_version: 1.0.0
run_units: []
YAML
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"malformed"* ]]
}

@test "error handling: catalog status not 'approved' is refused (exit 2)" {
  cat > "$CATALOG" <<'YAML'
schema_version: 1.0.0
status: proposed
run_units:
  - run_unit_id: bats:x
    runner: bats
    source_paths:
      - plugins/aid-orchestrator/scripts/tests/bats/test-x.bats
YAML
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"not 'approved'"* ]]
}

@test "error handling: catalog with zero bats run_units fails loudly (exit 2)" {
  cat > "$CATALOG" <<'YAML'
schema_version: 1.0.0
status: approved
run_units:
  - run_unit_id: declared-command:only
    runner: declared-command
    source_paths:
      - scripts/some-other-thing.sh
YAML
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"zero bats run_units"* ]]
}

# --- Fail-closed path validation (PM review round 2) ------------------------

@test "path validation: a catalog entry pointing at a nonexistent file fails loudly (exit 2)" {
  local ghost="plugins/aid-orchestrator/scripts/tests/bats/test-does-not-exist-on-disk.bats"
  _write_catalog "$CATALOG" "$ghost"
  # Deliberately never create $PROJECT/$ghost on disk.

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not exist"* ]]
  [[ "$output" == *"$ghost"* ]]
}

@test "path validation: a catalog entry escaping the repo root via '../' fails loudly (exit 2)" {
  local escape="../etc/test-outside-repo.bats"
  # Create the file so only the traversal check (not existence) can fail it.
  mkdir -p "$TMP/etc"
  _write_passing_bats "$TMP/etc/test-outside-repo.bats"
  _write_catalog "$CATALOG" "$escape"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"escapes repo root"* ]]
}

@test "path validation: a catalog entry starting with '-' fails loudly (exit 2) — never reaches bats as a flag" {
  # This path is deliberately never created on disk either; the '-' check
  # must fire (and be reported) before the existence check would matter.
  local dashy="-j999"
  _write_catalog "$CATALOG" "$dashy"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"begins with '-'"* ]]
  [[ "$output" == *"$dashy"* ]]
}

@test "path validation: a duplicate catalog entry fails loudly (exit 2)" {
  local dup="plugins/aid-orchestrator/scripts/tests/bats/test-duplicated.bats"
  _write_passing_bats "$PROJECT/$dup"
  # Hand-craft a catalog with the SAME source_path listed under two distinct
  # run_unit_ids (a real-world catalog bug this must still catch).
  {
    echo "schema_version: 1.0.0"
    echo "status: approved"
    echo "run_units:"
    echo "  - run_unit_id: bats:dup-1"
    echo "    runner: bats"
    echo "    source_paths:"
    echo "      - ${dup}"
    echo "  - run_unit_id: bats:dup-2"
    echo "    runner: bats"
    echo "    source_paths:"
    echo "      - ${dup}"
  } > "$CATALOG"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate catalog entry"* ]]
  [[ "$output" == *"$dup"* ]]
}

@test "path validation: multiple invalid paths are ALL reported, not just the first" {
  local ghost="plugins/aid-orchestrator/scripts/tests/bats/test-ghost.bats"
  local dashy="-x"
  {
    echo "schema_version: 1.0.0"
    echo "status: approved"
    echo "run_units:"
    echo "  - run_unit_id: bats:ghost"
    echo "    runner: bats"
    echo "    source_paths:"
    echo "      - ${ghost}"
    echo "  - run_unit_id: bats:dashy"
    echo "    runner: bats"
    echo "    source_paths:"
    echo "      - ${dashy}"
  } > "$CATALOG"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"2 invalid catalog-derived path(s)"* ]]
  [[ "$output" == *"$ghost"* ]]
  [[ "$output" == *"$dashy"* ]]
}

# --- Fail-closed CLI value validation ----------------------------------------

@test "usage: --jobs with a non-numeric value fails loudly (exit 2)" {
  local safe="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  _write_passing_bats "$PROJECT/$safe"
  _write_catalog "$CATALOG" "$safe"
  _allow "$safe"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --jobs banana --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "usage: --jobs 0 fails loudly (exit 2) — not a silently-clamped minimum" {
  local safe="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  _write_passing_bats "$PROJECT/$safe"
  _write_catalog "$CATALOG" "$safe"
  _allow "$safe"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --jobs 0 --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "usage: --catalog with no value fails loudly instead of crashing on an unbound argument" {
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "usage: --jobs with no value fails loudly instead of crashing on an unbound argument" {
  cd "$PROJECT"
  run bash "$SCRIPT" --jobs
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "usage: --allowlist with no value fails loudly instead of crashing on an unbound argument" {
  cd "$PROJECT"
  run bash "$SCRIPT" --allowlist
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a value"* ]]
}

@test "usage: unknown argument fails loudly (exit 2)" {
  cd "$PROJECT"
  run bash "$SCRIPT" --bogus-flag
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "usage: -h/--help exits 0 and prints usage" {
  cd "$PROJECT"
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "usage: --pool-only and --dedicated-only together are mutually exclusive (exit 2)" {
  local safe="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  _write_passing_bats "$PROJECT/$safe"
  _write_catalog "$CATALOG" "$safe"
  _allow "$safe"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --pool-only --dedicated-only --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# --- Real (not mocked) small-scale execution --------------------------------

@test "real run: allowlisted pool + unclassified + boundary all pass -> gate exits 0" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local safe2="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-b.bats"
  local unclassified="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-unclassified.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_passing_bats "$PROJECT/$safe2"
  _write_passing_bats "$PROJECT/$unclassified"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1" "$safe2" "$unclassified"
  _allow "$safe1" "$safe2"
  # $unclassified deliberately NOT allowlisted.

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --jobs 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"running 2 catalog-approved bats files in the safe pool (-j 2)"* ]]
  [[ "$output" == *"running unclassified file '$unclassified'"* ]]
  [[ "$output" == *"boundary lane file '$final'"* ]]
  [[ "$output" == *"boundary lane file '$release'"* ]]
  [[ "$output" == *"PASSED"* ]]
}

@test "real run: a failure in the allowlisted pool fails the gate even if everything else passes" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local safe2="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-fails.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_failing_bats "$PROJECT/$safe2"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1" "$safe2"
  _allow "$safe1" "$safe2"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --jobs 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
}

@test "real run: a failure in the UNCLASSIFIED sequential lane fails the gate" {
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local unclassified_fail="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-unclassified-fails.bats"

  _write_passing_bats "$PROJECT/$safe1"
  _write_failing_bats "$PROJECT/$unclassified_fail"
  _write_catalog "$CATALOG" "$safe1" "$unclassified_fail"
  _allow "$safe1"
  # $unclassified_fail deliberately NOT allowlisted.

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --pool-only --jobs 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  [[ "$output" == *"unclassified_exit=1"* ]]
}

@test "real run: a failure in the boundary lane fails the gate even if the pool passes" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_failing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1"
  _allow "$safe1"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --jobs 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  # both boundary files still ran despite the first one failing
  [[ "$output" == *"boundary lane file '$final'"* ]]
  [[ "$output" == *"boundary lane file '$release'"* ]]
}

@test "real run: --pool-only skips BOUNDARY entirely (boundary files never invoked)" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1"
  _allow "$safe1"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --pool-only --jobs 2
  [ "$status" -eq 0 ]
  [[ "$output" != *"boundary lane file"* ]]
}

@test "real run: --dedicated-only skips the pool AND unclassified entirely" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1"
  _allow "$safe1"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --allowlist "$ALLOWLIST" --dedicated-only --jobs 2
  [ "$status" -eq 0 ]
  [[ "$output" != *"safe pool"* ]]
  [[ "$output" != *"unclassified file"* ]]
  [[ "$output" == *"boundary lane file '$final'"* ]]
  [[ "$output" == *"boundary lane file '$release'"* ]]
}
