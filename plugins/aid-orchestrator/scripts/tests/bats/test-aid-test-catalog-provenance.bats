#!/usr/bin/env bats
# test-aid-test-catalog-provenance.bats — P072 Step 16.
#
# `parallel.status` decides whether a test file runs concurrently with others.
# These cases pin the rule that makes that field checkable rather than
# declarative: a status is bound to the content it was verified against, and it
# reverts when that content's RESOURCES change.
#
# The two-tier design is the point. One tier — revert on any byte change —
# would cost a full pilot for a comment fix, and a rule that expensive stops
# being obeyed. Two tiers keep the cheap case cheap without letting a real
# change through.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-catalog-provenance.sh"
  SCHEMA="$PLUGIN_DIR/defaults/schemas/test-catalog.schema.json"
  AT='@'"test"
  PROJ="$TEST_TMPDIR/proj"
  mkdir -p "$PROJ/tests" "$PROJ/.aid-o/config"
  CAT="$PROJ/.aid-o/config/test-catalog.yaml"
}

teardown() { teardown_test_evidence_dir; }

# _unit_file <name> <body>
_unit_file() { printf '%s' "$2" > "$PROJ/tests/$1.bats"; }

# _catalog <name> <status> <source_sha> <resource_digest>
_catalog() {
  local n="$1" st="$2" sha="$3" rd="$4"
  {
    echo 'schema_version: "1.0.0"'
    echo 'status: approved'
    echo 'run_units:'
    echo "  - run_unit_id: \"bats:tests/$n\""
    echo '    runner: bats'
    echo "    source_paths: [\"tests/$n.bats\"]"
    echo "    command: {type: argv, argv: [\"bats\", \"tests/$n.bats\"]}"
    echo '    parallel:'
    echo "      status: $st"
    echo '      exclusive_resources: []'
    echo '      max_workers: null'
    echo '      internal_parallelism: false'
    echo '      provenance:'
    echo "        evidence_ref: \"audit-x\""
    echo '        verified_at: "2026-08-01T00:00:00Z"'
    echo '        method: resource_map_plus_pilot'
    echo "        source_sha256: \"$sha\""
    echo "        resource_digest: \"$rd\""
  } > "$CAT"
}

_hash()   { aid_test_catalog_provenance_hash "bats:tests/$1" "$CAT" "$PROJ"; }
_digest() { aid_test_catalog_provenance_resource_digest "bats:tests/$1" "$CAT" "$PROJ"; }
_effective() { aid_test_catalog_provenance_effective_status "bats:tests/$1" "$CAT" "$PROJ" "${2:-}"; }

# ─── The hash binds a status to real content ───────────────────────────────

@test "the hash is computed over the unit's declared sources" {
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe deadbeef deadbeef
  local h; h="$(_hash a)"
  [[ "$h" =~ ^[0-9a-f]{64}$ ]]
}

@test "a DELETED source path yields missing_source, never a hash over nothing" {
  # A hash computed over content that is gone would keep a unit pooled on the
  # strength of a file nobody can read.
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe deadbeef deadbeef
  rm "$PROJ/tests/a.bats"
  [ "$(_hash a)" = "missing_source" ]
  [ "$(_effective a)" = "unknown" ]
}

@test "source_paths ORDER is part of the identity" {
  # A reordered composition is a different composition; a reversion that costs
  # one re-verification is the safe direction.
  printf 'alpha\n' > "$PROJ/tests/one.bats"
  printf 'beta\n'  > "$PROJ/tests/two.bats"
  {
    echo 'schema_version: "1.0.0"'; echo 'status: approved'; echo 'run_units:'
    echo '  - run_unit_id: "bats:tests/multi"'
    echo '    runner: bats'
    echo '    source_paths: ["tests/one.bats", "tests/two.bats"]'
  } > "$CAT"
  local h1; h1="$(aid_test_catalog_provenance_hash "bats:tests/multi" "$CAT" "$PROJ")"
  {
    echo 'schema_version: "1.0.0"'; echo 'status: approved'; echo 'run_units:'
    echo '  - run_unit_id: "bats:tests/multi"'
    echo '    runner: bats'
    echo '    source_paths: ["tests/two.bats", "tests/one.bats"]'
  } > "$CAT"
  local h2; h2="$(aid_test_catalog_provenance_hash "bats:tests/multi" "$CAT" "$PROJ")"
  [ "$h1" != "$h2" ]
}

# ─── The reversion rule, tier by tier ──────────────────────────────────────

@test "an unchanged source keeps its recorded status" {
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe placeholder placeholder
  local h d; h="$(_hash a)"; d="$(_digest a)"
  _catalog a safe "$h" "$d"
  [ "$(aid_test_catalog_provenance_verify "bats:tests/a" "$CAT" "$PROJ")" = "match" ]
  [ "$(_effective a)" = "safe" ]
}

@test "a COMMENT-only change keeps the status: bytes moved, resources did not" {
  # The case that makes two tiers necessary. Reverting here would cost a pilot
  # for a typo fix.
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe placeholder placeholder
  local h d; h="$(_hash a)"; d="$(_digest a)"
  _catalog a safe "$h" "$d"

  _unit_file a "# a newly added explanatory comment
${AT} \"a\" { true; }"
  [ "$(aid_test_catalog_provenance_verify "bats:tests/a" "$CAT" "$PROJ")" = "mismatch" ]
  [ "$(_effective a)" = "safe" ]
}

@test "a change that ADDS a shared resource reverts the unit to unknown" {
  # The digest, not the hash, is what decides.
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe placeholder placeholder
  local h d; h="$(_hash a)"; d="$(_digest a)"
  _catalog a safe "$h" "$d"

  _unit_file a "${AT} \"a\" { flock /var/lock/x.lock true; }"
  [ "$(_effective a)" = "unknown" ]
}

@test "an edit that changes BOTH a comment and the resources still reverts" {
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe placeholder placeholder
  local h d; h="$(_hash a)"; d="$(_digest a)"
  _catalog a safe "$h" "$d"

  _unit_file a "# explanatory comment
${AT} \"a\" { flock /var/lock/x.lock true; }"
  [ "$(_effective a)" = "unknown" ]
}

@test "a status with NO provenance is not evidence" {
  # A catalog written before this rule existed carries no provenance. It loads,
  # and it is effectively unknown — not silently trusted.
  _unit_file a "${AT} \"a\" { true; }"
  {
    echo 'schema_version: "1.0.0"'; echo 'status: approved'; echo 'run_units:'
    echo '  - run_unit_id: "bats:tests/a"'
    echo '    runner: bats'
    echo '    source_paths: ["tests/a.bats"]'
    echo '    parallel: {status: safe, exclusive_resources: [], max_workers: null, internal_parallelism: false}'
  } > "$CAT"
  [ "$(aid_test_catalog_provenance_verify "bats:tests/a" "$CAT" "$PROJ")" = "no_provenance" ]
  [ "$(_effective a)" = "unknown" ]
}

@test "an already-unknown status stays unknown without any work" {
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a unknown deadbeef deadbeef
  [ "$(_effective a)" = "unknown" ]
}

@test "a recheck that cannot finish in its budget fails CLOSED" {
  # A status this did not verify is a status it may not echo.
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe placeholder placeholder
  local h d; h="$(_hash a)"; d="$(_digest a)"
  _catalog a safe "$h" "$d"
  _unit_file a "# changed
${AT} \"a\" { true; }"
  # A budget no recomputation can meet.
  [ "$(_effective a 1)" = "unknown" ]
}

# ─── The refresh side effect ───────────────────────────────────────────────

@test "refresh writes the current hash and a new verified_at, in place" {
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe placeholder placeholder
  local h; h="$(_hash a)"
  aid_test_catalog_provenance_refresh "bats:tests/a" "$CAT" "$PROJ"
  local written
  written="$(yq -r '.run_units[0].parallel.provenance.source_sha256' "$CAT")"
  [ "$written" = "$h" ]
  [ "$(yq -r '.run_units[0].parallel.provenance.verified_at' "$CAT")" != "2026-08-01T00:00:00Z" ]
}

@test "refresh leaves the recorded STATUS alone — it is not a promotion" {
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a constrained placeholder placeholder
  aid_test_catalog_provenance_refresh "bats:tests/a" "$CAT" "$PROJ"
  [ "$(yq -r '.run_units[0].parallel.status' "$CAT")" = "constrained" ]
}

# ─── The schema ────────────────────────────────────────────────────────────

_validate_catalog() {
  python3 - "$SCHEMA" "$CAT" <<'PY'
import json,sys,subprocess
schema=json.load(open(sys.argv[1]))
inst=json.loads(subprocess.run(["yq","-o=json",".",sys.argv[2]],capture_output=True,text=True).stdout)
from jsonschema.validators import Draft202012Validator
errs=list(Draft202012Validator(schema).iter_errors(inst))
for e in errs: print("/".join(str(x) for x in e.path) or "(root)", e.message[:200])
sys.exit(1 if errs else 0)
PY
}

@test "a non-unknown status with a NULL provenance field is rejected" {
  # This field decides whether a file runs concurrently with others. A claim
  # with no way to check it is not admissible.
  _unit_file a "${AT} \"a\" { true; }"
  {
    echo 'schema_version: "1.0.0"'
    echo 'generated_at: "2026-08-03T00:00:00Z"'
    echo 'status: approved'
    echo 'run_units:'
    echo '  - run_unit_id: "bats:tests/a"'
    echo '    runner: bats'
    echo '    source_paths: ["tests/a.bats"]'
    echo '    production_surfaces: []'
    echo '    test_level: suite'
    echo '    risk_tags: []'
    echo '    profiles: [default]'
    echo '    behavior_claims: []'
    echo '    confidence: low'
    echo '    command: {type: argv, argv: ["bats", "tests/a.bats"]}'
    echo '    runtime: {fingerprint: "sha256:000000000000"}'
    echo '    parallel:'
    echo '      status: safe'
    echo '      exclusive_resources: []'
    echo '      max_workers: null'
    echo '      internal_parallelism: false'
    echo '      provenance:'
    echo '        evidence_ref: null'
    echo '        verified_at: null'
    echo '        method: null'
    echo '        source_sha256: null'
    echo '        resource_digest: null'
    echo '    isolation: {temp_workspace: unknown, fixed_ports: [], shared_paths: [], lock_usage: [], adapter_confidence: static_parse}'
    echo '    recommendation: keep'
    echo '    test_cases: []'
    echo 'source_pattern_mappings: []'
    echo 'mapping_approval: {status: proposed}'
  } > "$CAT"
  run _validate_catalog
  [ "$status" -ne 0 ]
}

@test "a method outside the three-value enum is rejected" {
  # A migrated entry must never be indistinguishable from a freshly piloted
  # one, and neither may be forged by inventing a third word.
  _unit_file a "${AT} \"a\" { true; }"
  _catalog a safe "$(printf '%064d' 1)" "$(printf '%064d' 2)"
  yq -i '.run_units[0].parallel.provenance.method = "trust_me"' "$CAT"
  yq -i '.generated_at = "2026-08-03T00:00:00Z"' "$CAT"
  run _validate_catalog
  [ "$status" -ne 0 ]
}
