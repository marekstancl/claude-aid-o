#!/usr/bin/env bats
# aid-tier: t0
# test-queue-registry-rows.bats — P090 Step 7.
#
# WHY THIS SUITE EXISTS AT ALL. The obvious answer — "the registry checks
# already cover it" — is wrong, and the plan says so: `test-enforcement-registry-cites.sh`
# asserts that citations RESOLVE and that ids are unique, not that any particular
# row exists; and the version-file check is an invocation-time release-boundary
# script, deliberately not a member of any suite. Nothing else would notice if
# these four rows were dropped, or if the two CHANGELOG sections drifted apart.
#
# The four rows are four on purpose. An ASK that only reads, a LOOP that
# decides, a SPAWN that is off until somebody turns it on, and a REMINDER that
# can only speak. Collapsed into one they would read as four guarantees, and the
# next person would lean on the weakest.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  REPO_ROOT="$(cd "$AID_PLUGIN_PATH/../.." && pwd)"
  REG="$AID_PLUGIN_PATH/defaults/enforcement-registry.yaml"
  ROWS="queue_peek_readonly plan_continue_loop plan_continue_spawn queue_continuation_notice"
}

_row() { yq -r ".enforcements[] | select(.id == \"$1\")" "$REG"; }
_field() { yq -r ".enforcements[] | select(.id == \"$1\") | .$2 // \"\"" "$REG"; }

@test "AC16: all four layers have a row, and each one is present exactly once" {
  local id
  for id in $ROWS; do
    run bash -c 'yq -r "[.enforcements[] | select(.id == \"'"$id"'\")] | length" "$1"' _ "$REG"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
  done
}

@test "AC16: every one of them carries every mandatory field, non-empty" {
  # The same field set `scripts/tests/test-enforcement-registry-test-audit.sh`
  # requires — asserted here per row, because that script asks about the file as
  # a whole and would not tell you WHICH row lost a field.
  local id f
  for id in $ROWS; do
    for f in type source description instruction severity surface status verdict test; do
      run bash -c 'yq -r ".enforcements[] | select(.id == \"'"$id"'\") | .'"$f"' // \"\"" "$1"' _ "$REG"
      [ "$status" -eq 0 ]
      [ -n "$output" ]
      [ "$output" != "null" ]
    done
  done
}

@test "AC16: each row states its enforcement degree, and the degrees differ where the layers do" {
  # A degree is the author saying whether the thing enforces or merely delivers.
  [ "$(_field queue_peek_readonly enforcement_degree)" = "1" ]
  [ "$(_field plan_continue_loop enforcement_degree)" = "1" ]
  [ "$(_field plan_continue_spawn enforcement_degree)" = "1" ]
  # The reminder is the odd one, and that is the whole point of listing four.
  [ "$(_field queue_continuation_notice enforcement_degree)" = "3" ]
}

@test "AC16: each row's not_guaranteed is a real sentence, not a placeholder" {
  local id n
  for id in $ROWS; do
    n="$(_field "$id" not_guaranteed)"
    [ -n "$n" ]
    [ "$n" != "null" ]
    # Long enough to be an argument rather than a shrug.
    [ "${#n}" -gt 80 ]
  done
}

@test "AC16: the spawn row says in that sentence that it is OFF by default" {
  local n; n="$(_field plan_continue_spawn not_guaranteed)"
  [[ "$n" == *"defaults to FALSE"* ]]
  [[ "$n" == *"autonomy.spawn_next_epic"* ]]
  # And that the cap is per plan — the choice that would otherwise be an
  # oversight nobody wrote down.
  [[ "$n" == *"PER PLAN"* ]]
}

@test "AC17: the reminder's row says it does not hold a turn, and names why" {
  local n; n="$(_field queue_continuation_notice not_guaranteed)"
  [[ "$n" == *"stop_hook_active"* ]]
  [[ "$n" == *"HOLDS A TURN"* ]]
  # …and its severity matches that: a rule that cannot refuse is not blocking.
  [ "$(_field queue_continuation_notice severity)" = "advisory" ]
}

@test "AC16: every row's named test file exists" {
  # A `test:` pointing at nothing is how a row starts describing a guarantee
  # nobody checks.
  local id t
  for id in $ROWS; do
    t="$(_field "$id" test)"
    [ -f "$AID_PLUGIN_PATH/$t" ]
  done
}

@test "AC16: every row's source anchor exists" {
  local id src f
  for id in $ROWS; do
    src="$(_field "$id" source)"
    f="${src%% (*}"          # strip the "(function)" suffix
    [ -f "$AID_PLUGIN_PATH/$f" ]
  done
}

# _top_version — the newest `## [X.Y.Z]` header in the root CHANGELOG, which is
# the single source of truth for the plugin version. Read rather than hardcoded:
# a version frozen in the test keeps passing over the next release instead of
# tracking it, which is the opposite of what these two cases are for.
_top_version() {
  grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$REPO_ROOT/CHANGELOG.md" \
    | tr -d '#[] '
}

@test "AC18: both CHANGELOGs carry this version's section, character for character" {
  local ver; ver="$(_top_version)"
  [ -n "$ver" ]
  local a="$REPO_ROOT/CHANGELOG.md"
  local b="$AID_PLUGIN_PATH/CHANGELOG.md"
  [ -f "$a" ]
  [ -f "$b" ]

  # The section is everything from this version's header up to the next `## [`.
  run bash -c 'awk "/^## \[$2\]/{f=1} f&&/^## \[/&&!/^## \[$2\]/{exit} f" "$1"' _ "$a" "$ver"
  local sec_a="$output"
  run bash -c 'awk "/^## \[$2\]/{f=1} f&&/^## \[/&&!/^## \[$2\]/{exit} f" "$1"' _ "$b" "$ver"
  local sec_b="$output"

  [ -n "$sec_a" ]
  [ "$sec_a" = "$sec_b" ]
}

@test "AC18: this version's section actually describes P090, not an empty stub" {
  local ver; ver="$(_top_version)"
  [ -n "$ver" ]
  run bash -c 'awk "/^## \[$2\]/{f=1} f&&/^## \[/&&!/^## \[$2\]/{exit} f" "$1"' _ \
      "$REPO_ROOT/CHANGELOG.md" "$ver"
  [[ "$output" == *"queue_peek_next"* ]]
  [[ "$output" == *"aid-plan-continue.sh"* ]]
  [[ "$output" == *"stop_hook_active"* ]]
}

@test "the contributor documentation describes all four layers" {
  # `docs/extending-aid.md` is the tracked exception among the plan documents,
  # so it is the one place a reader outside this working tree can find the
  # reasoning.
  local d="$REPO_ROOT/docs/extending-aid.md"
  grep -q 'The plan continues itself (P090)' "$d"
  grep -q 'queue_peek_next' "$d"
  grep -q 'aid-plan-continue.sh' "$d"
  grep -q 'autonomy.spawn_next_epic' "$d"
  grep -q 'aid-queue-continuation.sh' "$d"
}
