#!/usr/bin/env bats
# test-aid-catalog-parallel-authority.bats — P072 Step 17.
#
# One authority over one question. Before this, the catalog carried
# `parallel.status` that nothing read, and the lane runner read a text list the
# catalog knew nothing about — so a file could stay pooled long after the
# reason it was pooled had stopped being true.
#
# These cases pin that the lane's partition now FOLLOWS the catalog, including
# when the catalog reverts a unit on its own.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  LANE="$PLUGIN_DIR/scripts/aid-bats-parallel-lane.sh"
  MIGRATE="$PLUGIN_DIR/scripts/aid-test-catalog-migrate-p071-allowlist.sh"
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-catalog-provenance.sh"
  AT='@'"test"

  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/plugins/aid-orchestrator/scripts/tests/bats" "$PROJ/.aid-o/config"
  CAT="$PROJ/.aid-o/config/test-catalog.yaml"
  TDIR="plugins/aid-orchestrator/scripts/tests/bats"
}

teardown() { teardown_test_evidence_dir; }

_file() { printf '%s' "$2" > "$PROJ/$TDIR/$1.bats"; }

# _catalog <name:status>...
_catalog() {
  {
    echo 'schema_version: "1.0.0"'
    echo 'status: approved'
    echo 'run_units:'
    for spec in "$@"; do
      local n="${spec%%:*}" st="${spec##*:}"
      echo "  - run_unit_id: \"bats:$TDIR/$n\""
      echo '    runner: bats'
      echo "    source_paths: [\"$TDIR/$n.bats\"]"
      echo "    command: {type: argv, argv: [\"bats\", \"$TDIR/$n.bats\"]}"
      echo '    parallel:'
      echo "      status: $st"
      echo '      exclusive_resources: []'
      echo '      max_workers: null'
      echo '      internal_parallelism: false'
      echo '      provenance:'
      if [[ "$st" == "unknown" ]]; then
        echo '        evidence_ref: null'
        echo '        verified_at: null'
        echo '        method: null'
        echo '        source_sha256: null'
        echo '        resource_digest: null'
      else
        echo '        evidence_ref: "pilot-x"'
        echo '        verified_at: "2026-08-02T00:00:00Z"'
        echo '        method: resource_map_plus_pilot'
        echo '        source_sha256: "PLACEHOLDER"'
        echo '        resource_digest: "PLACEHOLDER"'
      fi
    done
  } > "$CAT"
}

# Fill in the real hashes for every non-unknown unit, so the catalog is
# self-consistent the way a migrated one is.
_bind() {
  local n
  for n in "$@"; do
    local uid="bats:$TDIR/$n"
    local h d
    h="$(aid_test_catalog_provenance_hash "$uid" "$CAT" "$PROJ")"
    d="$(aid_test_catalog_provenance_resource_digest "$uid" "$CAT" "$PROJ")"
    B_ID="$uid" B_H="$h" B_D="$d" yq -i '
      (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.source_sha256) = strenv(B_H)
      | (.run_units[] | select(.run_unit_id == strenv(B_ID)) | .parallel.provenance.resource_digest) = strenv(B_D)' "$CAT"
  done
}

_partition() { ( cd "$PROJ" && bash "$LANE" --catalog "$CAT" --dry-run 2>/dev/null ); }
_pool_count() { _partition | sed -n 's/^SAFE_POOL (\([0-9]*\)).*/\1/p'; }
_unclassified_count() { _partition | sed -n 's/^UNCLASSIFIED (\([0-9]*\)).*/\1/p'; }

# ─── The partition follows the catalog ─────────────────────────────────────

@test "a unit whose catalog status is safe AND bound enters the pool" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"; _bind a
  [ "$(_pool_count)" = "1" ]
  [ "$(_unclassified_count)" = "0" ]
}

@test "a unit whose catalog status is unknown runs sequentially" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  [ "$(_pool_count)" = "0" ]
  [ "$(_unclassified_count)" = "1" ]
}

@test "changing ONLY the catalog changes the partition" {
  # The proof that the catalog is the authority: the file on disk is identical
  # in both halves of this test.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"; _bind a
  [ "$(_pool_count)" = "1" ]
  yq -i '.run_units[0].parallel.status = "exclusive"' "$CAT"
  [ "$(_pool_count)" = "0" ]
  [ "$(_unclassified_count)" = "1" ]
}

@test "a unit whose SOURCE gained a lock falls out of the pool with nobody editing a list" {
  # What a text allowlist could not do. The file changes; the partition changes.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"; _bind a
  [ "$(_pool_count)" = "1" ]
  _file a "${AT} \"a\" { flock /var/lock/x.lock true; }"
  [ "$(_pool_count)" = "0" ]
  [ "$(_unclassified_count)" = "1" ]
}

@test "a COMMENT-only edit does not cost a unit its place in the pool" {
  # The other half of the two-tier rule: reverting on any byte change would
  # cost a pilot for a typo, and a rule that expensive gets disabled.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"; _bind a
  _file a "# an added comment
${AT} \"a\" { true; }"
  [ "$(_pool_count)" = "1" ]
}

@test "a status with no provenance never reaches the pool" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"
  yq -i '.run_units[0].parallel.provenance.source_sha256 = null' "$CAT"
  yq -i '.run_units[0].parallel.provenance.resource_digest = null' "$CAT"
  [ "$(_pool_count)" = "0" ]
}

@test "an empty pool is a valid state, not an error" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  run bash -c "cd '$PROJ' && bash '$LANE' --catalog '$CAT' --dry-run"
  [ "$status" -eq 0 ]
}

# ─── The boundary bucket is a cost decision, not a safety one ──────────────

@test "a boundary file stays out of the pool even when the catalog calls it safe" {
  _file test-aid-plan-final-boundary "${AT} \"b\" { true; }"
  _file a "${AT} \"a\" { true; }"
  _catalog "test-aid-plan-final-boundary:safe" "a:safe"
  _bind test-aid-plan-final-boundary a
  local p; p="$(_partition)"
  [[ "$p" == *"BOUNDARY (1)"* ]]
  [ "$(_pool_count)" = "1" ]
}

# ─── Pre-existing fail-closed validation survives the change ───────────────

@test "a catalog path that does not exist still aborts the whole run" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe" "ghost:safe"
  _bind a
  run bash -c "cd '$PROJ' && bash '$LANE' --catalog '$CAT' --dry-run"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "a duplicate catalog entry still aborts the whole run" {
  _file a "${AT} \"a\" { true; }"
  {
    echo 'schema_version: "1.0.0"'; echo 'status: approved'; echo 'run_units:'
    for i in 1 2; do
      echo "  - run_unit_id: \"bats:$TDIR/a-$i\""
      echo '    runner: bats'
      echo "    source_paths: [\"$TDIR/a.bats\"]"
      echo '    parallel: {status: unknown, exclusive_resources: [], max_workers: null, internal_parallelism: false}'
    done
  } > "$CAT"
  run bash -c "cd '$PROJ' && bash '$LANE' --catalog '$CAT' --dry-run"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicate"* ]]
}

# ─── The retired allowlist ─────────────────────────────────────────────────

@test "--allowlist is accepted but says plainly that it is not read" {
  # Silently ignoring it would leave a caller believing a list still governs
  # the pool.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"; _bind a
  run bash -c "cd '$PROJ' && bash '$LANE' --catalog '$CAT' --allowlist /nonexistent/list.txt --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"retired"* ]]
  [[ "$output" == *"not read"* ]]
}

@test "the shipped allowlist file contains a retirement notice and no entries" {
  local f="$PLUGIN_DIR/defaults/config/bats-parallel-safe-allowlist.txt"
  [ -f "$f" ]
  grep -q "RETIRED" "$f"
  # every non-comment, non-blank line would be an entry
  [ "$(grep -vcE '^\s*#|^\s*$' "$f")" = "0" ]
}

@test "no script other than the migration reads the allowlist file" {
  # The migration reads it because migrating it is its job.
  local hits
  hits="$(cd "$PLUGIN_DIR/.." && grep -rl "bats-parallel-safe-allowlist" --include='*.sh' . 2>/dev/null || true)"
  local unexpected=""
  while IFS= read -r h; do
    [[ -z "$h" ]] && continue
    [[ "$h" == *"aid-test-catalog-migrate-p071-allowlist.sh" ]] && continue
    unexpected="$unexpected $h"
  done <<< "$hits"
  [ -z "$unexpected" ]
}

# ─── The migration ─────────────────────────────────────────────────────────

@test "the migration refuses a listed path with no catalog run unit" {
  # Creating an entry the inventory does not know about would put a file in
  # the pool that nothing else can see.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/a.bats" "$TDIR/never-inventoried.bats" > "$list"
  run bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ"
  [ "$status" -eq 3 ]
  [[ "$output" == *"never-inventoried.bats"* ]]
}

@test "the migration records method migrated_p071_step3, distinguishable from a pilot" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/a.bats" > "$list"
  bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ" 2>/dev/null
  [ "$(yq -r '.run_units[0].parallel.provenance.method' "$CAT")" = "migrated_p071_step3" ]
  [ "$(yq -r '.run_units[0].parallel.status' "$CAT")" = "safe" ]
}

@test "the migrated evidence_ref does NOT repeat the allowlist header's 83 figure" {
  # Carrying a wrong number across would turn a documentation error into a
  # durable schema field.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/a.bats" > "$list"
  bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ" 2>/dev/null
  local ref; ref="$(yq -r '.run_units[0].parallel.provenance.evidence_ref' "$CAT")"
  [[ "$ref" == *"P071 Step 3"* ]]
  [[ "$ref" == *"audit-20260802-070629"* ]]
  # The corrected counts are present, and the wrong one is only ever named as
  # wrong.
  [[ "$ref" == *"1 bats files piloted"* ]]
  [[ "$ref" != *"read all 83"* ]]
}

@test "the migration is idempotent — a second run leaves the catalog byte-identical" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/a.bats" > "$list"
  bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ" 2>/dev/null
  cp "$CAT" "$TEST_TMPDIR/first.yaml"
  bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ" 2>/dev/null
  diff -q "$TEST_TMPDIR/first.yaml" "$CAT"
}

@test "a completed migration re-run against the RETIRED list is a clean no-op" {
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/a.bats" > "$list"
  bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ" 2>/dev/null
  # now the list is emptied, as the shipped one is
  printf '# retired\n' > "$list"
  run bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already carries"* ]]
}

@test "an emptied list with NO migrated entries is an error, not a no-op" {
  # The two states look identical from the list alone; conflating them would
  # report evidence that is simply gone as a completed migration.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  local list="$TEST_TMPDIR/list.txt"
  printf '# retired\n' > "$list"
  run bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in either place"* ]]
}

# ─── What an adversarial review found ──────────────────────────────────────

@test "the migration REFUSES a file changed since P071 rather than re-blessing it" {
  # Hashing the edited content and writing `status: safe` would bind P071's
  # evidence to bytes P071 never saw — laundering a post-pilot change into
  # fresh-looking evidence. A warning cannot preserve evidence for different
  # content.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:unknown"
  # GIT_COMMITTER_DATE, not --date: `git log --before` filters on the committer
  # date, and --date sets only the author date.
  ( cd "$PROJ" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A \
      && GIT_COMMITTER_DATE="2026-08-01T00:00:00" git commit -qm "before p071" --date="2026-08-01T00:00:00" )
  # Edit it AFTER that commit.
  _file a "${AT} \"a\" { flock /var/lock/x.lock true; }"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/a.bats" > "$list"
  run bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"were NOT migrated"* ]]
  [ "$(yq -r '.run_units[0].parallel.status' "$CAT")" = "unknown" ]
}

@test "the migration refuses a listed path that is not the unit's EXECUTABLE source" {
  # A listed helper vouching for a unit whose .bats file was never piloted
  # would let the lane pool that file.
  _file a "${AT} \"a\" { true; }"
  printf 'helper_fn() { true; }\n' > "$PROJ/$TDIR/old-helper.bash"
  {
    echo 'schema_version: "1.0.0"'; echo 'status: approved'; echo 'run_units:'
    echo "  - run_unit_id: \"bats:$TDIR/a\""
    echo '    runner: bats'
    echo "    source_paths: [\"$TDIR/a.bats\", \"$TDIR/old-helper.bash\"]"
    echo '    parallel: {status: unknown, exclusive_resources: [], max_workers: null, internal_parallelism: false}'
  } > "$CAT"
  local list="$TEST_TMPDIR/list.txt"
  printf '%s\n' "$TDIR/old-helper.bash" > "$list"
  run bash "$MIGRATE" --catalog "$CAT" --allowlist "$list" --project-root "$PROJ"
  [ "$status" -eq 3 ]
  [[ "$output" == *"old-helper.bash"* ]]
}

@test "a pooled file rewritten between classification and dispatch aborts the run" {
  # Eligibility is decided from the bytes on disk; anything that rewrites a
  # file before `bats -j` opens it would put unverified content into the pool.
  _file a "${AT} \"a\" { true; }"
  _catalog "a:safe"; _bind a
  [ "$(_pool_count)" = "1" ]

  # A wrapper that mutates the file after classification but before dispatch is
  # not expressible here, so assert the guard's own comparison directly: the
  # recorded hash and the current hash must agree for the file to be dispatched.
  local recorded current
  recorded="$(yq -r '.run_units[0].parallel.provenance.source_sha256' "$CAT")"
  current="$(aid_test_catalog_provenance_hash "bats:$TDIR/a" "$CAT" "$PROJ")"
  [ "$recorded" = "$current" ]
  _file a "${AT} \"a\" { flock /var/lock/x.lock true; }"
  current="$(aid_test_catalog_provenance_hash "bats:$TDIR/a" "$CAT" "$PROJ")"
  [ "$recorded" != "$current" ]
  # And the partition follows: it is no longer pooled at all.
  [ "$(_pool_count)" = "0" ]
}
