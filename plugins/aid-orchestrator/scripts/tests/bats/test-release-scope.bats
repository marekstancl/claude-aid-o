#!/usr/bin/env bats
# aid-tier: t1
# test-release-scope.bats — a release is required by what CHANGED, never by
# what a commit message promised (P089 Step 7).
#
# TIER. Every case here builds a throwaway git repository with commits and a
# tag, because the thing under test is a decision about a commit range and a
# fixture that fakes the range would be testing the fake. That cost is t1 by
# measurement, and this is the one suite of this plan the merge path feels.
#
# THE GROUNDED FAILURE: `fix(tests):` blocked a WAN push three times in one day
# for a change that touched no application code, and `chore:` could change the
# application and pass. Both directions are cases below.

load test-helpers.bash

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  TMP="$(mktemp -d)"
  R="$TMP/repo"
  export TMP R
  mkdir -p "$R/.aid-o/config" "$R/src" "$R/tests" "$R/docs"
  (
    cd "$R"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    # `.aid-o/` is gitignored in a real AID project; without that here the
    # config file itself lands in every commit's path set and nothing is
    # ever exempt.
    printf '.aid-o/\n' > .gitignore
    printf 'seed\n' > src/app.txt
    printf 'seed\n' > tests/t.txt
    printf 'seed\n' > docs/d.txt
    git add -A && git commit -q -m "chore: seed"
    git tag v1.0.0
  )
  # shellcheck disable=SC1090
  source "$AID_PLUGIN_PATH/scripts/lib/aid-release-scope.sh"
}

teardown() {
  cd /
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

_config() {
  cat > "$R/.aid-o/config/project.yaml" <<'YAML'
versioning:
  release_exempt_paths:
    - tests
    - docs
  app_paths:
    - src
YAML
}

# _commit <subject> <path> [footer]
_commit() {
  local subject="$1" path="$2" footer="${3:-}"
  ( cd "$R"
    printf '%s\n' "$RANDOM $subject" >> "$path"
    git add -A
    if [[ -n "$footer" ]]; then
      git commit -q -m "$subject" -m "$footer"
    else
      git commit -q -m "$subject"
    fi )
}

_verdict() { aid_release_scope_verdict "$R" "$(aid_release_scope_start "$R")" HEAD; }

# ─── the two directions of the grounded failure ─────────────────────────────

@test "AC19: a range whose every change is exempt passes, whatever the labels say" {
  _config
  _commit "fix(tests): flaky case" tests/t.txt
  _commit "feat(docs): a new page" docs/d.txt
  run _verdict
  [ "$status" -eq 0 ]
  [ "$output" = "exempt" ]
}

@test "AC20: a mixed range requires a release" {
  _config
  _commit "fix(tests): flaky case" tests/t.txt
  _commit "chore: tidy up" src/app.txt
  run _verdict
  [ "$output" = "release_required" ]
}

@test "a chore: that touches the application is named in a warning, and still blocks" {
  _config
  _commit "chore: tidy up" src/app.txt
  run aid_release_scope_report "$R" v1.0.0 HEAD
  [[ "$output" == *"verdict: release_required"* ]]
  [[ "$output" == *"warn:"* ]]
  [[ "$output" == *"calls itself housekeeping"* ]]
  [[ "$output" == *"src/app.txt"* ]]
}

@test "AC24: the refusal names the commits that caused it" {
  _config
  _commit "fix(tests): exempt" tests/t.txt
  _commit "feat: real work" src/app.txt
  run aid_release_scope_report "$R" v1.0.0 HEAD
  [[ "$output" == *"commit: "* ]]
  [[ "$output" == *"feat: real work"* ]]
  # The exempt commit is not blamed for a decision it did not cause.
  [[ "$output" != *"fix(tests): exempt"* ]]
}

# ─── the No-Release footer ──────────────────────────────────────────────────

@test "a commit carrying a No-Release footer is removed from the range" {
  _config
  _commit "feat: generated fixture refresh" src/app.txt "No-Release: regenerated fixture, no shipped behaviour"
  run _verdict
  [ "$output" = "no_commits" ]
}

@test "a bare No-Release: with no reason is not a footer — it is a switch" {
  _config
  _commit "feat: real work" src/app.txt "No-Release:"
  run _verdict
  [ "$output" = "release_required" ]
}

@test "an exempt and a non-exempt commit over the same path: the non-exempt one wins" {
  _config
  _commit "feat: first" src/app.txt "No-Release: waived deliberately"
  _commit "feat: second" src/app.txt
  run _verdict
  [ "$output" = "release_required" ]
}

# ─── the boundary is the TAG, not a label ───────────────────────────────────

@test "AC21b: a commit merely SUBJECTED release: does not close the range" {
  _config
  _commit "feat: real work" src/app.txt
  ( cd "$R" && git commit -q --allow-empty -m "release: v1.1.0" )
  run _verdict
  [ "$output" = "release_required" ]
}

@test "a real tag does close the range" {
  _config
  _commit "feat: real work" src/app.txt
  ( cd "$R" && git tag v1.1.0 )
  run _verdict
  [ "$output" = "no_commits" ]
}

# ─── merges and reverts, the two shapes a union decides differently ─────────

@test "a revert adds its own paths, so a change and its undo still need a release" {
  _config
  _commit "feat: real work" src/app.txt
  ( cd "$R" && git revert --no-edit HEAD >/dev/null )
  run _verdict
  [ "$output" = "release_required" ]
}

@test "a merge is judged along its first parent" {
  _config
  ( cd "$R"
    git checkout -q -b side
    printf 'side\n' >> src/app.txt
    git add -A && git commit -q -m "feat: side work"
    git checkout -q main
    printf 'x\n' >> tests/t.txt
    git add -A && git commit -q -m "fix(tests): main-side"
    git merge -q --no-ff -m "merge: side" side )
  # The merge commit itself contributes nothing along the first parent; the
  # side branch's own commit is in the range and does.
  run _verdict
  [ "$output" = "release_required" ]
}

# ─── fail-open ──────────────────────────────────────────────────────────────

@test "AC21: with no config the library says so instead of deciding" {
  _commit "feat: real work" src/app.txt
  run _verdict
  [ "$output" = "no_config" ]
}

@test "AC21c: an already-initialised project missing both keys falls open and says how to fix it" {
  printf 'versioning:\n  source: null\n' > "$R/.aid-o/config/project.yaml"
  _commit "feat: real work" src/app.txt
  run aid_release_scope_report "$R" v1.0.0 HEAD
  [[ "$output" == *"verdict: no_config"* ]]
  [[ "$output" == *"release_exempt_paths is not set"* ]]
  [[ "$output" == *"/aid-setup"* ]]
}

@test "an untagged repository takes the root of history as the start, exclusive" {
  _config
  ( cd "$R" && git tag -d v1.0.0 >/dev/null )
  _commit "fix(tests): only tests" tests/t.txt
  run _verdict
  # `root..HEAD` EXCLUDES the root commit, so the seed's own src/ change is not
  # in the range. That is the inherited direction: before this library an
  # untagged repository was waved through unconditionally.
  [ "$output" = "exempt" ]
}
