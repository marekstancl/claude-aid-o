#!/usr/bin/env bats
# aid-tier: t1
# test-aid-test-adapter-shell-suite.bats — P072 Step 7.
#
# Classification is by SHEBANG, never by filename and never by the executable
# bit. Both halves matter: a `test-*.sh` carrying `#!/usr/bin/env bats` is a
# Bats suite that `run-all-tests.sh:140` already dispatches with `bats`, so
# claiming it here would run it with the wrong runner; and 6 of this
# repository's 7 such files are non-executable while one is, so the executable
# bit correlates with nothing.

load test-helpers.bash

setup() {
  setup_test_evidence_dir
  PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-gate-runtime-baseline.sh" 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-adapter-contract.sh"
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-adapter-shell-suite.sh"

  ROOT="$TEST_TMPDIR/proj"
  mkdir -p "$ROOT/tests"
}

teardown() { teardown_test_evidence_dir; }

_write() {
  local path="$ROOT/$1"; shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$@" > "$path"
}

SKIPPED_OUT=""
_discover() {
  SKIPPED_OUT="$TEST_TMPDIR/skipped.json"
  shell_suite_adapter_discover "$ROOT" "$ROOT" "$SKIPPED_OUT"
}
_skipped() { cat "$TEST_TMPDIR/skipped.json"; }
_ids() { _discover | jq -r '.[].run_unit_id' | sort; }
_bats_owned() {
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-adapter-bats.sh"
  bats_adapter_discover "$ROOT" | jq -r '.[].run_unit_id' | sort
}
_argv_for() { _discover | jq -r --arg id "$1" '.[] | select(.run_unit_id==$id) | .command.argv | join(" ")'; }

@test "a bash-shebang suite becomes an sh: run unit invoked with bash" {
  _write tests/test-alpha.sh '#!/usr/bin/env bash' 'echo hi'

  run _ids
  [ "$status" -eq 0 ]
  [ "$output" = "sh:tests/test-alpha" ]

  run _argv_for "sh:tests/test-alpha"
  [ "$output" = "bash tests/test-alpha.sh" ]
}

@test "a plain /bin/sh shebang is also claimed" {
  _write tests/test-posix.sh '#!/bin/sh' 'echo hi'
  run _ids
  [ "$output" = "sh:tests/test-posix" ]
}

@test "a BATS-shebang .sh file is NOT claimed — the bats adapter owns it" {
  _write tests/test-batsy.sh '#!/usr/bin/env bats' '@test "x" { true; }'

  run _discover
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" = "0" ]
}

@test "declining a bats-shebang file is RECORDED, not silent" {
  _write tests/test-batsy.sh '#!/usr/bin/env bats' '@test "x" { true; }'
  _discover >/dev/null

  run jq -r '.[] | "\(.path)\t\(.reason)"' <<<"$(_skipped)"
  [[ "$output" == *"tests/test-batsy.sh"* ]]
  [[ "$output" == *"claimed_by_bats_adapter"* ]]
}

@test "a file with NO shebang is excluded and recorded with its reason" {
  _write tests/test-helpers-like.sh 'some_function() { :; }'

  run _discover
  [ "$(jq 'length' <<<"$output")" = "0" ]

  run jq -r '.[] | "\(.path)\t\(.reason)"' <<<"$(_skipped)"
  [[ "$output" == *"no_shell_shebang"* ]]
}

@test "the executable bit does NOT decide: a NON-executable bash suite is claimed" {
  _write tests/test-nonexec.sh '#!/usr/bin/env bash' 'echo hi'
  chmod -x "$ROOT/tests/test-nonexec.sh"
  run _ids
  [ "$output" = "sh:tests/test-nonexec" ]
}

@test "the executable bit does NOT decide: an EXECUTABLE bats suite is still declined" {
  # This is test-scope-check.sh's exact shape in the real repository: bats
  # shebang AND the executable bit set. An executable-bit rule would have
  # admitted it and run a Bats suite with bash.
  _write tests/test-execbats.sh '#!/usr/bin/env bats' '@test "x" { true; }'
  chmod +x "$ROOT/tests/test-execbats.sh"

  run _discover
  [ "$(jq 'length' <<<"$output")" = "0" ]
}

@test "two same-basename suites in different directories get distinct ids" {
  _write a/test-x.sh '#!/usr/bin/env bash' 'echo a'
  _write b/test-x.sh '#!/usr/bin/env bash' 'echo b'

  run _ids
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"sh:a/test-x"* ]]
  [[ "$output" == *"sh:b/test-x"* ]]
}

@test "fixture and node_modules trees are not scanned" {
  _write tests/fixtures/test-fixture.sh '#!/usr/bin/env bash' 'echo fixture'
  _write node_modules/pkg/test-vendored.sh '#!/usr/bin/env bash' 'echo vendored'
  _write tests/test-real.sh '#!/usr/bin/env bash' 'echo real'

  run _ids
  [ "$output" = "sh:tests/test-real" ]
}

@test "a project with zero shell suites yields an empty array and exit 0" {
  run _discover
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "an emitted unit carries no invented test_cases" {
  # A shell suite has no statically enumerable case list. An empty array is
  # the honest answer; deriving cases from echo lines would be a guess
  # presented as structure.
  _write tests/test-alpha.sh '#!/usr/bin/env bash' 'echo hi'
  [ "$(_discover | jq -r '.[0].test_cases | length')" = "0" ]
}

@test "every emitted unit validates against the real catalog schema" {
  _write tests/test-alpha.sh '#!/usr/bin/env bash' 'echo hi'
  _write tests/test-beta.sh '#!/bin/sh' 'echo hi'

  local units; units="$(_discover)"
  run python3 - "$PLUGIN_DIR" <<PY
import json, sys
from jsonschema import Draft202012Validator, RefResolver
units = json.loads('''$units''')
s = json.load(open(sys.argv[1] + "/defaults/schemas/test-catalog.schema.json"))
cat = {"schema_version":"1.0.0","generated_at":"2026-08-03T00:00:00Z","status":"proposed",
       "run_units":units,"source_pattern_mappings":[],"mapping_approval":{"status":"proposed"}}
errs = list(Draft202012Validator(s, resolver=RefResolver.from_schema(s)).iter_errors(cat))
print("\n".join(e.message for e in errs) if errs else "valid")
PY
  [ "$output" = "valid" ]
}

# ─── Against the real repository ───────────────────────────────────────────

@test "REAL REPO: every shell suite present is either discovered or declined with a reason" {
  # This used to assert the fixed numbers 36 and 7. Both were true when they
  # were written and both were stale within the same plan — this plan ADDS
  # suites, so a frozen count fails for the one reason that is not a defect.
  #
  # The invariant that actually matters is reconciliation: every `test-*.sh`
  # in the tests directory is accounted for exactly once, either as a
  # discovered shell unit or as an explicitly declined one. That holds at any
  # portfolio size, and unlike a count it fails when a file goes MISSING from
  # both sides — which is the real defect a count was standing in for.
  local repo; repo="$(cd "$PLUGIN_DIR/../.." && pwd)"
  local led="$TEST_TMPDIR/repo-skipped.json"
  local units; units="$(shell_suite_adapter_discover "$repo" "$repo" "$led")"

  local present discovered declined accounted
  present="$(find "$repo/plugins/aid-orchestrator/scripts/tests" -maxdepth 1 -name 'test-*.sh' | wc -l)"
  discovered="$(jq 'length' <<<"$units")"
  declined="$(jq '[.[] | select((.path // .source_path // "") | test("/tests/test-[^/]*\\.sh$"))] | length' "$led")"
  accounted=$(( discovered + declined ))

  # Reported, so a failure says WHICH way the books do not balance.
  echo "present=${present} discovered=${discovered} declined=${declined} accounted=${accounted}" >&3
  [ "$accounted" -eq "$present" ]
  [ "$discovered" -gt 0 ]
}

@test "REAL REPO: a declined suite always carries WHY it was declined" {
  # A decline with no reason is indistinguishable from a file the scanner
  # simply lost.
  local repo; repo="$(cd "$PLUGIN_DIR/../.." && pwd)"
  local led="$TEST_TMPDIR/repo-skipped-reasons.json"
  shell_suite_adapter_discover "$repo" "$repo" "$led" >/dev/null
  [ "$(jq '[.[] | select((.reason // "") == "")] | length' "$led")" = "0" ]
  # And the bats adapter is the reason we expect to see most of, since the two
  # adapters partition the same tree.
  [ "$(jq '[.[] | select(.reason == "claimed_by_bats_adapter")] | length' "$led")" -gt 0 ]
}

@test "REAL REPO: no sh: unit is emitted for a file the bats adapter also claims" {
  local repo; repo="$(cd "$PLUGIN_DIR/../.." && pwd)"
  # shellcheck disable=SC1090
  source "$PLUGIN_DIR/scripts/lib/aid-test-adapter-bats.sh"

  local sh_paths bats_paths overlap
  sh_paths="$(shell_suite_adapter_discover "$repo" "$repo" "$TEST_TMPDIR/ov.json" | jq -r '.[].source_paths[0]' | sort)"
  bats_paths="$(bats_adapter_discover "$repo" | jq -r '.[].source_paths[0]' | sort)"
  overlap="$(comm -12 <(printf '%s\n' "$sh_paths") <(printf '%s\n' "$bats_paths"))"
  [ -z "$overlap" ]
}

# ─── The shared classifier must not misfire (Codex review) ─────────────────

@test "a substring-bats shebang is NOT claimed as bats by either adapter" {
  # `#!/bin/batsman` contains "bats" but is not bats. A substring rule claimed
  # it, which would have run it with the wrong runner.
  _write tests/test-batsman.sh '#!/bin/batsman' 'echo hi'
  run _discover
  [ "$(jq 'length' <<<"$output")" = "0" ]
  run _bats_owned
  [ -z "$output" ]
  run jq -r '.[].reason' <<<"$(_skipped)"
  [[ "$output" == *"no_shell_shebang"* ]]
}

@test "a shell shebang mentioning bats in a comment stays a SHELL suite" {
  _write tests/test-commented.sh '#!/bin/bash # bats' 'echo hi'
  run _ids
  [ "$output" = "sh:tests/test-commented" ]
}

@test "env with extra spaces still resolves to bats" {
  _write tests/test-spaced.sh '#!/usr/bin/env  bats' '@test "x" { true; }'
  run _discover
  [ "$(jq 'length' <<<"$output")" = "0" ]
  run jq -r '.[].reason' <<<"$(_skipped)"
  [[ "$output" == *"claimed_by_bats_adapter"* ]]
}

@test "a bash shebang with flags is a shell suite" {
  _write tests/test-flagged.sh '#!/bin/bash -e' 'echo hi'
  run _ids
  [ "$output" = "sh:tests/test-flagged" ]
}

@test "NO FILE is claimed by both adapters, and every candidate is accounted for" {
  _write tests/test-shell.sh   '#!/usr/bin/env bash' 'echo hi'
  _write tests/test-batsy.sh   '#!/usr/bin/env bats' '@test "x" { true; }'
  _write tests/test-nothing.sh 'no shebang here'

  local sh_ids bats_ids
  sh_ids="$(_ids)"
  bats_ids="$(_bats_owned)"
  # disjoint
  [ -z "$(comm -12 <(printf '%s\n' "$sh_ids") <(printf '%s\n' "$bats_ids"))" ]
  # and 3 candidates == 1 sh + 1 bats + 1 recorded skip
  [ "$(printf '%s\n' "$sh_ids" | grep -c .)" = "1" ]
  [ "$(printf '%s\n' "$bats_ids" | grep -c .)" = "1" ]
  [ "$(jq 'length' <<<"$(_skipped)")" = "2" ]
}

@test "a .bats file and a bats-shebang .sh file with the SAME stem get distinct ids" {
  # Stripping both extensions would give them one id, which the reconciliation
  # would later report as a duplicate disposition for a unit nobody duplicated.
  _write tests/test-twin.bats '@test "x" { true; }'
  _write tests/test-twin.sh   '#!/usr/bin/env bats' '@test "y" { true; }'

  run _bats_owned
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"bats:tests/test-twin"* ]]
  [[ "$output" == *"bats:tests/test-twin.sh"* ]]
  [ "$(printf '%s\n' "$output" | sort -u | wc -l)" = "2" ]
}

@test "a symlinked suite is excluded but RECORDED, never silently dropped" {
  _write tests/test-real.sh '#!/usr/bin/env bash' 'echo hi'
  ln -s test-real.sh "$ROOT/tests/test-link.sh"

  run _ids
  [ "$output" = "sh:tests/test-real" ]
  run jq -r '.[] | select(.reason=="symlink_not_followed") | .path' <<<"$(_skipped)"
  [[ "$output" == *"tests/test-link.sh"* ]]
}

@test "omitting the ledger path is refused — an unrecorded skip is a silent drop" {
  _write tests/test-alpha.sh '#!/usr/bin/env bash' 'echo hi'
  run shell_suite_adapter_discover "$ROOT" "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required"* ]]
}

# ─── Packaging: a documented entrypoint must be runnable as documented ──────

@test "REAL REPO: every top-level script is committed executable" {
  # Seven were committed 0644, so invoking them exactly as the docs and command
  # files write them — without a `bash` prefix — exited 126. An installed
  # plugin keeps the committed mode, so this reached consumers.
  #
  # Scoped to scripts/ itself: everything under scripts/lib/ is sourced, never
  # invoked, and does not need the bit.
  local repo; repo="$(cd "$PLUGIN_DIR/../.." && pwd)"
  local non_exec
  non_exec="$(git -C "$repo" ls-files -s plugins/aid-orchestrator/scripts/ \
    | awk '$1=="100644" && $4 ~ /\.sh$/ && $4 !~ /\/lib\//  {print $4}')"
  [ -z "$non_exec" ] || echo "not executable: $non_exec" >&3
  [ -z "$non_exec" ]
}

@test "REAL REPO: every script a command file names actually exists at that path" {
  # Six command-file references named top-level scripts that only exist under
  # scripts/lib/. Somebody following the documentation gets "No such file".
  # Cheap to check, and it had gone unchecked across the whole command set.
  local repo; repo="$(cd "$PLUGIN_DIR/../.." && pwd)"
  local missing=""
  local f s
  for f in "$repo"/plugins/aid-orchestrator/commands/*.md; do
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      [ -e "$repo/plugins/aid-orchestrator/scripts/$s" ] \
        || missing="${missing}$(basename "$f"): $s"$'\n'
    done < <(grep -oE '`(lib/)?aid-[a-z0-9-]+\.sh`' "$f" 2>/dev/null | tr -d '`' | sort -u)
  done
  [ -z "$missing" ] || echo "$missing" >&3
  [ -z "$missing" ]
}
