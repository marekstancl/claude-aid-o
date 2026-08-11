#!/usr/bin/env bats
# aid-tier: t2
# test-selector-honesty-check.bats — P081 Step 9: gaps are detected, and never
# manufactured.
#
# WHAT THIS SUITE PROVES: the three gap classes are told apart, and the two
# things that must NOT be called gaps stay out of the report — an escalation
# (the selector's own safety net did fire, so the merge ran more than the
# targeted set) and a cross-cutting suite no changed path could ever select.
# A gap report that cries wolf is one nobody reads, which would leave the
# narrowed merge path with no audit at all.
#
# Six cases drive a stub selector so the verdict under test is the one chosen;
# the seventh drives the REAL selector end to end, so the dry-run interface
# this tool depends on cannot drift away underneath it.
#
# Result count after any edit:
#   bats --tap test-selector-honesty-check.bats | grep -cE '^(ok|not ok)'   # == 7

load test-helpers.bash

setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  CHECK="$AID_PLUGIN_PATH/scripts/aid-selector-honesty-check.sh"
  export AID_PLUGIN_PATH CHECK
  TEST_TMPDIR="$(mktemp -d)"
  ROOT="$TEST_TMPDIR/project"
  NIGHTLY_DIR="$TEST_TMPDIR/nightly"
  export TEST_TMPDIR ROOT NIGHTLY_DIR
  mkdir -p "$NIGHTLY_DIR"
  aid_test_mk_repo "$ROOT"
  cd "$ROOT"
  _artifact test-red
}

teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
  return 0
}

# _artifact <failing suite…> — a nightly artifact naming those failures.
_artifact() {
  printf '%s\n' "$@" | jq -Rc 'select(length>0)' | jq -s \
    '{date:"2026-08-10", failed: map({suite: ., streak: 1})}' \
    > "$NIGHTLY_DIR/latest.json"
}

# _merge <path> — a merge commit touching <path>, as a real merge with a first
# parent, because that is what the check diffs against.
_merge() {
  git -C "$ROOT" checkout -q -b feature
  mkdir -p "$ROOT/$(dirname "$1")"
  printf 'change\n' > "$ROOT/$1"
  git -C "$ROOT" add -A && git -C "$ROOT" commit -q -m "touch $1"
  git -C "$ROOT" checkout -q main
  git -C "$ROOT" merge -q --no-ff -m "merge feature" feature
}

# _stub <exit> <selected json> [mentioned basename…] — a selector whose verdict
# this test chooses. Basenames mentioned in it are what the check reads as the
# mapping's reachable set.
_stub() {
  local code="$1" selected="$2"; shift 2
  STUB="$TEST_TMPDIR/stub-select.sh"
  {
    printf '#!/usr/bin/env bash\n'
    local m; for m in "$@"; do printf '# mapping mentions %s\n' "$m"; done
    printf 'printf %%s %s\n' "'{\"selected_tests\":$selected,\"exit_status\":$code}'"
    printf 'exit %s\n' "$code"
  } > "$STUB"
  export AID_SELECT_TESTS="$STUB"
}

_check() { bash "$CHECK" --dir "$NIGHTLY_DIR" --repo "$ROOT" --since-date 2000-01-01; }
_gaps() { jq -c '.gaps' "$NIGHTLY_DIR/2026-08-10-selector-gaps.json"; }

@test "1: a failure the selector would have picked is not a gap" {
  _merge scripts/thing.sh
  _stub 0 '["tests/bats/test-red.bats"]' test-red.bats
  run _check
  [ "$status" -eq 0 ]
  [ "$(_gaps)" = "[]" ]
}

@test "2: a failure the selector picked nothing for is an unmapped gap" {
  _merge scripts/thing.sh
  _stub 0 '[]' test-red.bats
  run _check
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].class' <<<"$(_gaps)")" = "unmapped" ]
  [ "$(jq -r '.[0].suite' <<<"$(_gaps)")" = "test-red" ]
  [[ "$(jq -r '.[0].changed_paths | join(",")' <<<"$(_gaps)")" == *"scripts/thing.sh"* ]]
}

@test "3: a selection that named OTHER suites is mapped_but_thin, not a pass" {
  _merge scripts/thing.sh
  _stub 0 '["tests/bats/test-other.bats"]' test-red.bats test-other.bats
  run _check
  [ "$status" -eq 0 ]
  [ "$(jq -r '.[0].class' <<<"$(_gaps)")" = "mapped_but_thin" ]
}

@test "4: an escalating selector exit is selection, never a manufactured gap" {
  _merge scripts/thing.sh
  _stub 3 '[]' test-red.bats
  run _check
  [ "$status" -eq 0 ]
  [ "$(_gaps)" = "[]" ]
  [[ "$(jq -r '.note' "$NIGHTLY_DIR/2026-08-10-selector-gaps.json")" == *"escalated"* ]]
}

@test "5: no merge since the last nightly is a note, not an error" {
  _stub 0 '[]' test-red.bats
  run _check
  [ "$status" -eq 0 ]
  [ "$(_gaps)" = "[]" ]
  [[ "$(jq -r '.note' "$NIGHTLY_DIR/2026-08-10-selector-gaps.json")" == *"no merge to evaluate"* ]]
}

@test "6: a suite no path could ever select is unmappable, a distinct outcome" {
  _merge scripts/thing.sh
  _stub 0 '[]' test-other.bats
  run _check
  [ "$status" -eq 0 ]
  [ "$(_gaps)" = "[]" ]
  [ "$(jq -r '.unmappable[0]' "$NIGHTLY_DIR/2026-08-10-selector-gaps.json")" = "test-red" ]
}

@test "7: the REAL selector's dry-run answers the check end to end" {
  _artifact test-aid-fsm
  _merge plugins/aid-orchestrator/scripts/aid-fsm.sh
  unset AID_SELECT_TESTS
  run _check
  [ "$status" -eq 0 ]
  [ "$(_gaps)" = "[]" ]
  [[ "$(jq -r '.note' "$NIGHTLY_DIR/2026-08-10-selector-gaps.json")" == *"1 suite(s) were selected"* ]]
}
