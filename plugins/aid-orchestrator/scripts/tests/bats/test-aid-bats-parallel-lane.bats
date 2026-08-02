#!/usr/bin/env bats
# test-aid-bats-parallel-lane.bats — P071 EPIC E-071-1_1 Step 3.
#
# Covers aid-bats-parallel-lane.sh, the wrapper that replaced the
# `gate:bats_all` quarantine stub (`exit 86`). Two things must be true:
#   1. Partition logic: the 2 known-unsafe boundary files are excluded from
#      the parallel safe pool by default, and a NEW bats file not on that
#      exclusion list lands in the pool automatically (the correct default).
#   2. A real (not mocked) small-scale invocation actually runs `bats -j N`
#      over a safe pool plus a sequential dedicated lane, and the gate's
#      exit code is the logical AND of both phases.
#
# All fixtures are throwaway bats files under a per-test tmpdir mimicking the
# real repo's relative path layout (plugins/aid-orchestrator/scripts/tests/
# bats/...) — the exclusion list in aid-bats-parallel-lane.sh is a literal
# relative-path match, so fixtures must sit at those exact relative paths to
# exercise it for real.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../aid-bats-parallel-lane.sh"
  TMP="$(mktemp -d)"
  PROJECT="$TMP/project"
  BATS_DIR="$PROJECT/plugins/aid-orchestrator/scripts/tests/bats"
  mkdir -p "$BATS_DIR"
  CATALOG="$PROJECT/.aid-o/config/test-catalog.yaml"
  mkdir -p "$(dirname "$CATALOG")"
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
      local id
      id="$(basename "$rel" .bats)"
      echo "  - run_unit_id: bats:${rel%.bats}"
      echo "    runner: bats"
      echo "    source_paths:"
      echo "      - ${rel}"
    done
    echo "  - run_unit_id: declared-command:not-a-bats-file"
    echo "    runner: declared-command"
    echo "    source_paths:"
    echo "      - scripts/some-other-thing.sh"
  } > "$catalog"
}

# --- Partition logic (--dry-run, no real bats execution) -------------------

@test "partition: both boundary files are excluded from the safe pool by default" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local safe2="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-b.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_passing_bats "$PROJECT/$safe2"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1" "$safe2"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --dry-run
  [ "$status" -eq 0 ]
  # boundary files land in DEDICATED, never SAFE_POOL
  [[ "$output" == *"DEDICATED (2):"* ]]
  [[ "$output" == *"$final"* ]]
  [[ "$output" == *"$release"* ]]
  [[ "$output" == *"SAFE_POOL (2):"* ]]
  [[ "$output" == *"$safe1"* ]]
  [[ "$output" == *"$safe2"* ]]

  # boundary paths must not appear in the SAFE_POOL block specifically
  local pool_block
  pool_block="$(printf '%s\n' "$output" | awk '/^SAFE_POOL/{f=1} /^DEDICATED/{f=0} f')"
  [[ "$pool_block" != *"$final"* ]]
  [[ "$pool_block" != *"$release"* ]]
}

@test "partition: a new bats file not on the exclusion list lands in the safe pool automatically" {
  local newfile="plugins/aid-orchestrator/scripts/tests/bats/test-brand-new-suite.bats"
  _write_passing_bats "$PROJECT/$newfile"
  _write_catalog "$CATALOG" "$newfile"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAFE_POOL (1):"* ]]
  [[ "$output" == *"$newfile"* ]]
  [[ "$output" == *"DEDICATED (0):"* ]]
}

@test "partition: declared-command run_units are filtered out (only runner==bats counted)" {
  local safe="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-only.bats"
  _write_passing_bats "$PROJECT/$safe"
  _write_catalog "$CATALOG" "$safe"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"some-other-thing.sh"* ]]
}

# --- Fail-closed catalog handling -------------------------------------------

@test "error handling: missing catalog file fails loudly (exit 2), never an empty run" {
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$PROJECT/.aid-o/config/does-not-exist.yaml" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "error handling: catalog missing a 'status' field is malformed (exit 2)" {
  cat > "$CATALOG" <<'YAML'
schema_version: 1.0.0
run_units: []
YAML
  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --dry-run
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
  run bash "$SCRIPT" --catalog "$CATALOG" --dry-run
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
  run bash "$SCRIPT" --catalog "$CATALOG" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"zero bats run_units"* ]]
}

# --- Real (not mocked) small-scale execution --------------------------------

@test "real run: safe pool (-j N) + dedicated lane both pass -> gate exits 0" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local safe2="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-b.bats"
  local safe3="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-c.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_passing_bats "$PROJECT/$safe2"
  _write_passing_bats "$PROJECT/$safe3"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1" "$safe2" "$safe3"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --jobs 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"running 3 bats files in the safe pool (-j 2)"* ]]
  [[ "$output" == *"dedicated lane file '$final'"* ]]
  [[ "$output" == *"dedicated lane file '$release'"* ]]
  [[ "$output" == *"PASSED"* ]]
}

@test "real run: a failure in the safe pool fails the gate even if the dedicated lane passes" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"
  local safe2="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-fails.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_passing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_failing_bats "$PROJECT/$safe2"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1" "$safe2"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --jobs 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
}

@test "real run: a failure in the dedicated lane fails the gate even if the safe pool passes" {
  local final="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  local release="plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
  local safe1="plugins/aid-orchestrator/scripts/tests/bats/test-fixture-a.bats"

  _write_passing_bats "$PROJECT/$final"
  _write_failing_bats "$PROJECT/$release"
  _write_passing_bats "$PROJECT/$safe1"
  _write_catalog "$CATALOG" "$final" "$release" "$safe1"

  cd "$PROJECT"
  run bash "$SCRIPT" --catalog "$CATALOG" --jobs 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  # both dedicated files still ran despite the first one failing
  [[ "$output" == *"dedicated lane file '$final'"* ]]
  [[ "$output" == *"dedicated lane file '$release'"* ]]
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
