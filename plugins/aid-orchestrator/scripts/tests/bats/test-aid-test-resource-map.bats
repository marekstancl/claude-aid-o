#!/usr/bin/env bats
# test-aid-test-resource-map.bats — P072 Step 14.
#
# The map's value is that a `shared` verdict can be checked and a `per-test`
# verdict can be attributed. So the cases below are mostly about the two ways
# a static reader gets this wrong:
#
#   a FALSE `shared` keeps a unit out of every pool forever, on the strength of
#   a word appearing somewhere;
#   a FALSE `per-test` puts a genuinely shared resource into a parallel pool.
#
# The first is what P066's audit produced. The second is what a pattern matcher
# produces when the isolation it credits lives in a file it never opened.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  MAP="$PLUGIN_DIR/scripts/aid-test-resource-map.sh"
  # Fixtures are written through this rather than as literal text: Bats scans
  # the ENTIRE file for the @test marker, heredoc bodies included, so a fixture
  # containing one would be collected as a test of this suite.
  AT='@'"test"
  SCHEMA="$PLUGIN_DIR/defaults/schemas/test-resource-map.schema.json"
  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/tests"
}

teardown() { teardown_test_evidence_dir; }

# A catalog with one unit whose source_paths are whatever we pass.
_catalog() {
  local id="$1"; shift
  {
    echo 'schema_version: "1.0.0"'
    echo 'status: approved'
    echo 'run_units:'
    echo "  - run_unit_id: \"$id\""
    echo '    runner: bats'
    echo '    source_paths:'
    for p in "$@"; do echo "      - \"$p\""; done
  } > "$PROJ/catalog.yaml"
}

_map() { bash "$MAP" --run-unit-id "$1" --catalog "$PROJ/catalog.yaml" --project-root "$PROJ" "${@:2}"; }

_validate() {
  python3 - "$SCHEMA" <<PY
import json, sys
from jsonschema.validators import Draft202012Validator
schema = json.load(open(sys.argv[1]))
inst = json.loads('''$1''')
errs = list(Draft202012Validator(schema).iter_errors(inst))
for e in errs:
    print("/".join(str(x) for x in e.path) or "(root)", e.message)
sys.exit(1 if errs else 0)
PY
}

# ─── The two error classes ─────────────────────────────────────────────────

@test "a test merely NAMED after a lock is not a lock user" {
  # The literal false positive P066's audit produced: the word appeared, so the
  # unit was called unsafe. Nothing here acquires anything.
  cat > "$PROJ/tests/a.bats" <<EOF
${AT} "the queue lock is released on failure" {
  run bash -c 'echo lock'
  [ "\$status" -eq 0 ]
}
EOF
  _catalog "bats:tests/a" "tests/a.bats"
  local doc; doc="$(_map "bats:tests/a")"
  [ "$(jq -r '[.resources[] | select(.kind == "lock")] | length' <<<"$doc")" = "0" ]
}

@test "an actual flock IS a lock, and shared" {
  cat > "$PROJ/tests/b.bats" <<EOF
${AT} "writes under a lock" {
  flock /var/lock/thing.lock echo hi
}
EOF
  _catalog "bats:tests/b" "tests/b.bats"
  local doc; doc="$(_map "bats:tests/b")"
  [ "$(jq -r '[.resources[] | select(.kind == "lock" and .namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}

@test "isolation living in a SOURCED helper is followed, credited and cited" {
  # The plan's central case. The mktemp is in another file, reached by `load`,
  # and called from setup() — so it is per-test, and the entry names the helper
  # that guarantees it.
  cat > "$PROJ/tests/helpers.bash" <<EOF
make_root() {
  MY_TMP=\$(mktemp -d)
  export MY_TMP
}
EOF
  cat > "$PROJ/tests/c.bats" <<EOF
load helpers.bash
setup() { make_root; }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/c" "tests/c.bats"
  local doc; doc="$(_map "bats:tests/c")"
  local e; e="$(jq -c '[.resources[] | select(.kind == "temp_path")][0]' <<<"$doc")"
  [ "$(jq -r '.namespace' <<<"$e")" = "per-test" ]
  [[ "$(jq -r '.location' <<<"$e")" == tests/helpers.bash:* ]]
  [ "$(jq -r '.via' <<<"$e")" = "helpers.bash" ]
}

@test "a git command AFTER a cd into a temp root is not a shared mutation" {
  # The false positive this script produced on its own first run: `git config`
  # two lines below `cd "$TEST_PROJECT_ROOT"` was called a shared mutation
  # because the cd was invisible to it.
  cat > "$PROJ/tests/helpers.bash" <<EOF
prepare() {
  TEST_TMPDIR=\$(mktemp -d)
  cd "\$TEST_TMPDIR"
  git init -q
  git config user.email "t@t"
  git commit -q --allow-empty -m init
}
EOF
  cat > "$PROJ/tests/d.bats" <<EOF
load helpers.bash
setup() { prepare; }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/d" "tests/d.bats"
  local doc; doc="$(_map "bats:tests/d")"
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and .namespace == "shared")] | length' <<<"$doc")" = "0" ]
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and .namespace == "per-test")] | length' <<<"$doc")" -ge 1 ]
}

@test "a git mutation with NO temp root in scope IS shared" {
  cat > "$PROJ/tests/e.bats" <<EOF
${AT} "tags the repository" {
  git tag some-tag
}
EOF
  _catalog "bats:tests/e" "tests/e.bats"
  local doc; doc="$(_map "bats:tests/e")"
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and .namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}

@test "git worktree add is shared even when its checkout lands in a temp dir" {
  # A worktree registers itself in the surrounding repository's object store,
  # so the temp destination does not make it private. This is a real finding in
  # this repository's own test-helpers.bash.
  cat > "$PROJ/tests/f.bats" <<EOF
setup() { TEST_TMPDIR=\$(mktemp -d); }
${AT} "makes a worktree" {
  local wt="\$TEST_TMPDIR/wt"
  git worktree add -q "\$wt" -b b
}
EOF
  _catalog "bats:tests/f" "tests/f.bats"
  local doc; doc="$(_map "bats:tests/f")"
  [ "$(jq -r '[.resources[] | select(.kind == "git_worktree" and .namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}

# ─── The helper-plus-literal case the design warns about ───────────────────

@test "a unit using the helper AND writing one literal path emits BOTH" {
  # It must not be called isolated on the strength of the helper alone. The
  # write is an ABSOLUTE path outside the temp root on purpose: a relative path
  # written after a cd into temp really is per-test, so asserting `shared` on
  # one would be asserting a bug.
  cat > "$PROJ/tests/helpers.bash" <<EOF
prepare() { TEST_TMPDIR=\$(mktemp -d); cd "\$TEST_TMPDIR"; }
EOF
  cat > "$PROJ/tests/g.bats" <<EOF
load helpers.bash
setup() { prepare; }
${AT} "also writes a shared fixture" {
  touch /var/tmp/aid-shared-fixture.txt
}
EOF
  _catalog "bats:tests/g" "tests/g.bats"
  local doc; doc="$(_map "bats:tests/g")"
  [ "$(jq -r '[.resources[] | select(.kind == "temp_path")] | length' <<<"$doc")" -ge 1 ]
  [ "$(jq -r '[.resources[] | select(.kind == "fixed_path" and .namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}

# ─── Refusing to guess ─────────────────────────────────────────────────────

@test "an unresolvable source caps the WHOLE unit at unknown" {
  # A unit whose dependencies cannot be read cannot be shown isolated, whatever
  # its own body looks like. Keeping the readable half's confident answers
  # would be reporting a conclusion the missing file might have overturned.
  cat > "$PROJ/tests/h.bats" <<EOF
source "\$SOME_COMPUTED_DIR/helpers.bash"
setup() { TEST_TMPDIR=\$(mktemp -d); }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/h" "tests/h.bats"
  local doc; doc="$(_map "bats:tests/h")"
  [ "$(jq -r '.capped_at_unknown' <<<"$doc")" = "true" ]
  [ "$(jq -r '.unresolved_sources | length' <<<"$doc")" -ge 1 ]
  [ "$(jq -r '[.resources[] | select(.namespace != "unknown")] | length' <<<"$doc")" = "0" ]
  [[ "$(jq -r '.unresolved_sources[0].location' <<<"$doc")" == tests/h.bats:* ]]
}

@test "a resource inside a function nobody cd'd in is unknown, not shared" {
  # The working directory is the caller's, and this cannot see the caller.
  # Guessing `shared` here would be the pattern-match verdict again.
  cat > "$PROJ/tests/i.bats" <<EOF
helper_fn() {
  git commit -q --allow-empty -m x
}
${AT} "works" { true; }
EOF
  _catalog "bats:tests/i" "tests/i.bats"
  local doc; doc="$(_map "bats:tests/i")"
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and .namespace == "unknown")] | length' <<<"$doc")" -ge 1 ]
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and .namespace == "shared")] | length' <<<"$doc")" = "0" ]
}

@test "a cd to a LITERAL path is resolved, not reported as a limitation" {
  # `cd /` in a teardown is ordinary. Recording it as unresolvable would claim
  # a blind spot this does not have.
  cat > "$PROJ/tests/j.bats" <<EOF
teardown() { cd /; }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/j" "tests/j.bats"
  local doc; doc="$(_map "bats:tests/j")"
  [ "$(jq -r '[.resources[] | select(.kind == "working_dir" and .namespace == "unknown")] | length' <<<"$doc")" = "0" ]
}

# ─── Contract ──────────────────────────────────────────────────────────────

@test "every emitted resource carries a justifying file:line" {
  cat > "$PROJ/tests/k.bats" <<EOF
setup() { TEST_TMPDIR=\$(mktemp -d); cd "\$TEST_TMPDIR"; git init -q; }
${AT} "works" { flock /tmp/x.lock true; }
EOF
  _catalog "bats:tests/k" "tests/k.bats"
  local doc; doc="$(_map "bats:tests/k")"
  [ "$(jq -r '.resources | length' <<<"$doc")" -gt 0 ]
  [ "$(jq -r '[.resources[] | select((.location // "") | test("^[^:]+:[0-9]+$") | not)] | length' <<<"$doc")" = "0" ]
}

@test "the emitted map validates against its schema" {
  cat > "$PROJ/tests/l.bats" <<EOF
setup() { TEST_TMPDIR=\$(mktemp -d); cd "\$TEST_TMPDIR"; git init -q; }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/l" "tests/l.bats"
  local doc; doc="$(_map "bats:tests/l")"
  run _validate "$doc"
  [ "$status" -eq 0 ]
}

@test "a shared classification with no location is rejected by the schema" {
  # The schema cannot check that a location is CORRECT, but it can refuse an
  # entry that names none — and `shared` is the value that must never be
  # unevidenced.
  run _validate '{"schema_version":"aid-test-resource-map-v1","run_unit_id":"x","source_paths":[],"follow_depth_cap":3,"unresolved_sources":[],"capped_at_unknown":false,"resources":[{"kind":"lock","namespace":"shared","detail":"d"}]}'
  [ "$status" -ne 0 ]
}

@test "the depth cap is recorded, not merely applied" {
  # A reader must be able to tell whether a helper three levels down was read
  # or simply out of reach.
  cat > "$PROJ/tests/m.bats" <<EOF
${AT} "works" { true; }
EOF
  _catalog "bats:tests/m" "tests/m.bats"
  local doc; doc="$(_map "bats:tests/m" --depth-cap 1)"
  [ "$(jq -r '.follow_depth_cap' <<<"$doc")" = "1" ]
}

@test "a helper BEYOND the depth cap is not silently credited" {
  # Its guarantee was never read, so it cannot be cited.
  cat > "$PROJ/tests/deep.bash" <<EOF
deep_fn() { DEEP_TMP=\$(mktemp -d); }
EOF
  cat > "$PROJ/tests/mid.bash" <<EOF
source "/dev/null"
load deep.bash
EOF
  cat > "$PROJ/tests/n.bats" <<EOF
load mid.bash
setup() { deep_fn; }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/n" "tests/n.bats"
  local doc; doc="$(_map "bats:tests/n" --depth-cap 1)"
  [ "$(jq -r '[.source_paths[] | select(. == "tests/deep.bash")] | length' <<<"$doc")" = "0" ]
}

# ─── It reads; it does not run ─────────────────────────────────────────────

@test "the builder executes nothing from the unit under inspection" {
  # A sentinel the unit would create if any of it were executed. Static
  # inspection that quietly runs the thing it inspects is not static
  # inspection, and this whole component's safety argument rests on it.
  cat > "$PROJ/tests/o.bats" <<EOF
setup() { touch "$TEST_TMPDIR/EXECUTED"; }
${AT} "works" { touch "$TEST_TMPDIR/EXECUTED_TEST"; }
EOF
  _catalog "bats:tests/o" "tests/o.bats"
  _map "bats:tests/o" >/dev/null
  [ ! -f "$TEST_TMPDIR/EXECUTED" ]
  [ ! -f "$TEST_TMPDIR/EXECUTED_TEST" ]
}

# ─── Refusals ──────────────────────────────────────────────────────────────

@test "REFUSAL: a unit absent from the catalog exits 3" {
  _catalog "bats:tests/p" "tests/p.bats"
  run _map "bats:tests/nope"
  [ "$status" -eq 3 ]
}

@test "REFUSAL: a declared source path that does not exist exits 4" {
  # A map built over a missing file would describe nothing while looking like
  # a clean result.
  _catalog "bats:tests/q" "tests/gone.bats"
  run _map "bats:tests/q"
  [ "$status" -eq 4 ]
  [[ "$output" == *"describe nothing"* ]]
}

@test "REFUSAL: a unit declaring no source_paths exits 3" {
  {
    echo 'schema_version: "1.0.0"'
    echo 'status: approved'
    echo 'run_units:'
    echo '  - run_unit_id: "bats:tests/r"'
    echo '    runner: bats'
    echo '    source_paths: []'
  } > "$PROJ/catalog.yaml"
  run _map "bats:tests/r"
  [ "$status" -eq 3 ]
  [[ "$output" == *"touches nothing"* ]]
}

# ─── The working directory never makes an anchored path private ────────────
#
# All four cases below come from an adversarial review of the first
# implementation, which reported every one of them as per-test. In a pooling
# decision a false private is the corrupting direction, so each must land on
# `unknown` or `shared` — never on a private namespace.

@test "git -C against a real repository is NOT private just because cwd is temp" {
  # `git -C` selects the repository explicitly. The working directory is
  # irrelevant to it.
  cat > "$PROJ/tests/gc.bats" <<EOF
setup() { cd "\$BATS_TEST_TMPDIR"; }
${AT} "tags the real repo" {
  git -C "\$BATS_TEST_DIRNAME/.." tag parallel-corruption
}
EOF
  _catalog "bats:tests/gc" "tests/gc.bats"
  local doc; doc="$(_map "bats:tests/gc")"
  local ns; ns="$(jq -r '[.resources[] | select(.kind == "git_repo")][0].namespace' <<<"$doc")"
  [ "$ns" != "per-test" ]
  [ "$ns" != "per-run" ]
}

@test "GIT_DIR and --git-dir are treated as repository selectors too" {
  cat > "$PROJ/tests/gd.bats" <<EOF
setup() { cd "\$BATS_TEST_TMPDIR"; }
${AT} "uses GIT_DIR" {
  GIT_DIR=/srv/real/.git git tag parallel-corruption
}
EOF
  _catalog "bats:tests/gd" "tests/gd.bats"
  local doc; doc="$(_map "bats:tests/gd")"
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and .namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}

@test "an ABSOLUTE path is not made private by a temp working directory" {
  cat > "$PROJ/tests/abs.bats" <<EOF
setup() { cd "\$BATS_TEST_TMPDIR"; }
${AT} "writes global state" {
  printf x > /var/tmp/aid-global-state
}
EOF
  _catalog "bats:tests/abs" "tests/abs.bats"
  local doc; doc="$(_map "bats:tests/abs")"
  [ "$(jq -r '[.resources[] | select(.namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}

@test "cd - after a temp cd returns the directory to unknown, not to temp" {
  # The LAST cd wins. Treating the first one as permanent marked everything
  # after it private.
  cat > "$PROJ/tests/cdb.bats" <<EOF
setup() {
  cd "\$BATS_TEST_TMPDIR"
  cd - >/dev/null
}
${AT} "mutates the repository" { git tag parallel-corruption; }
EOF
  _catalog "bats:tests/cdb" "tests/cdb.bats"
  local doc; doc="$(_map "bats:tests/cdb")"
  local ns; ns="$(jq -r '[.resources[] | select(.kind == "git_repo")][0].namespace' <<<"$doc")"
  [ "$ns" != "per-test" ]
  [ "$ns" != "per-run" ]
}

@test "a conditional cd is not assumed to have taken effect" {
  cat > "$PROJ/tests/ccd.bats" <<EOF
setup() { cd "\$BATS_TEST_TMPDIR/does-not-exist" || true; }
${AT} "mutates the repository" { git tag parallel-corruption; }
EOF
  _catalog "bats:tests/ccd" "tests/ccd.bats"
  local doc; doc="$(_map "bats:tests/ccd")"
  local ns; ns="$(jq -r '[.resources[] | select(.kind == "git_repo")][0].namespace' <<<"$doc")"
  [ "$ns" != "per-test" ]
  [ "$ns" != "per-run" ]
}

@test "one source file's setup does NOT establish the directory for another" {
  # Bats does not run tests/a.bats's setup before tests/b.bats's tests. A
  # global "did any setup cd into temp" flag credited one file's isolation to
  # its sibling.
  cat > "$PROJ/tests/s1.bats" <<EOF
setup() { cd "\$BATS_TEST_TMPDIR"; }
${AT} "fine" { true; }
EOF
  cat > "$PROJ/tests/s2.bats" <<EOF
${AT} "mutates the repository" { git tag parallel-corruption; }
EOF
  _catalog "bats:tests/s" "tests/s1.bats" "tests/s2.bats"
  local doc; doc="$(_map "bats:tests/s")"
  local shared_or_unknown
  shared_or_unknown="$(jq -r '[.resources[] | select(.kind == "git_repo" and (.namespace == "shared" or .namespace == "unknown"))] | length' <<<"$doc")"
  [ "$shared_or_unknown" -ge 1 ]
  [ "$(jq -r '[.resources[] | select(.kind == "git_repo" and (.namespace == "per-test" or .namespace == "per-run"))] | length' <<<"$doc")" = "0" ]
}

@test "a helper beyond the depth cap CAPS the unit rather than vanishing" {
  # It exists and was never read, so it could contain any shared mutation.
  # Silence is not a safe classification.
  cat > "$PROJ/tests/deep2.bash" <<EOF
deep_mutate() { git tag parallel-corruption; }
EOF
  cat > "$PROJ/tests/mid2.bash" <<EOF
load deep2.bash
EOF
  cat > "$PROJ/tests/dc2.bats" <<EOF
load mid2.bash
setup() { deep_mutate; }
${AT} "works" { true; }
EOF
  _catalog "bats:tests/dc2" "tests/dc2.bats"
  local doc; doc="$(_map "bats:tests/dc2" --depth-cap 1)"
  [ "$(jq -r '.capped_at_unknown' <<<"$doc")" = "true" ]
  [[ "$(jq -r '.unresolved_sources[0].reason' <<<"$doc")" == *"depth cap"* ]]
}

@test "a write outside the repository is recorded, not ignored" {
  # Recognising writes only under a few repository prefixes made a conflicting
  # global cache invisible to the pooling decision.
  cat > "$PROJ/tests/cache.bats" <<EOF
${AT} "uses a global cache" {
  rm -rf /var/tmp/aid-integration-state
}
EOF
  _catalog "bats:tests/cache" "tests/cache.bats"
  local doc; doc="$(_map "bats:tests/cache")"
  [ "$(jq -r '[.resources[] | select(.namespace == "shared")] | length' <<<"$doc")" -ge 1 ]
}
