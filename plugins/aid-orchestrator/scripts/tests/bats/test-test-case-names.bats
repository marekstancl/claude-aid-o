#!/usr/bin/env bats
# aid-tier: t0
# aid_test_names_plan_refs (lib/aid-test-tier.sh): a test case added since a
# base may not carry a plan, review-finding or backlog number in its name —
# the name says what it guards. Declarations are written through printf here
# so this file's own lines never look like the cases they describe.

setup() {
  # shellcheck disable=SC1091
  source "$BATS_TEST_DIRNAME/../../lib/aid-test-tier.sh"
  REPO="$(mktemp -d)"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  mkdir -p "$REPO/tests/fixtures" "$REPO/src"
  printf '%s "P094 old case keeps its name" {\n}\n' '@test' > "$REPO/tests/test-old.bats"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm base
  BASE="$(git -C "$REPO" rev-parse HEAD)"
}

teardown() { rm -rf "$REPO"; }

_commit() { git -C "$REPO" add -A; git -C "$REPO" commit -qm change; }

@test "names citing a plan, a finding or a backlog item are reported, in every declaration form" {
  {
    printf '%s "P123 refuses X" {\n}\n' '@test'
    printf "%s 'cp2 f3: keeps Y' {\n}\n" '@test'
    printf '%s "IMP-612 Z holds" {\n}\n' '@test'
  } > "$REPO/tests/test-new.bats"
  printf 'def test_p123_x():\n    pass\n' > "$REPO/tests/test_new.py"
  printf '%s("prints \\"ok\\" for P123", () => {});\n' 'it.each' > "$REPO/src/thing.test.ts"
  mkdir -p "$REPO/tests/odd dir"
  printf '%s "a quoted path, IMP-612" {\n}\n' '@test' > "$REPO/tests/odd dir/test-\"q\".bats"
  _commit
  run aid_test_names_plan_refs "$REPO" "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *$'tests/test-new.bats\tP123 refuses X'* ]]
  [[ "$output" == *$'tests/test-new.bats\tcp2 f3: keeps Y'* ]]
  [[ "$output" == *$'tests/test-new.bats\tIMP-612 Z holds'* ]]
  [[ "$output" == *$'tests/test_new.py\ttest_p123_x'* ]]
  [[ "$output" == *$'src/thing.test.ts\tprints \\"ok\\" for P123'* ]]
  [[ "$output" == *"a quoted path, IMP-612"* ]]
  [ "$(wc -l <<<"$output")" -eq 6 ]
}

@test "behaviour names, step numbers, look-alike numbers, untouched old cases and fixtures pass" {
  {
    printf '%s "refuses X" {\n}\n' '@test'
    printf '%s "step 0 runs the coverage check" {\n}\n' '@test'
    printf '%s "XP123 and P1234 are not plan numbers" {\n}\n' '@test'
    printf '%s "P123foo, cp2f3x and IMP-612a are not references" {\n}\n' '@test'
    printf '%s "an unclosed name with P123 {\n}\n' '@test'
  } > "$REPO/tests/test-new.bats"
  printf '%s "P123 in a fixture" {\n}\n' '@test' > "$REPO/tests/fixtures/test-sample.bats"
  printf '%s "P123 outside any test file" {\n}\n' '@test' > "$REPO/src/notes.bats.txt"
  _commit
  run aid_test_names_plan_refs "$REPO" "$BASE"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an uncommitted edit of a tracked test file counts — release would sweep it in" {
  printf '%s "P200 edited in place" {\n}\n' '@test' >> "$REPO/tests/test-old.bats"
  run aid_test_names_plan_refs "$REPO" "$BASE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P200 edited in place"* ]]
  [[ "$output" != *"P094"* ]]
}

@test "a base that does not resolve cannot be checked and says so (2), it never reads as clean" {
  run aid_test_names_plan_refs "$REPO" no-such-ref
  [ "$status" -eq 2 ]
  run aid_test_names_plan_refs "$REPO/nowhere" "$BASE"
  [ "$status" -eq 2 ]
}

@test "a deleted declaration and a file renamed without edits are not new cases" {
  printf '%s "P095 to be removed" {\n}\n' '@test' > "$REPO/tests/test-gone.bats"
  _commit
  local mid; mid="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" rm -q tests/test-gone.bats
  git -C "$REPO" mv tests/test-old.bats tests/test-renamed.bats
  _commit
  run aid_test_names_plan_refs "$REPO" "$mid"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
