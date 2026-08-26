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

# The one-word verdict, for the cases that only care about it. It calls the
# same entry point production does; there is no verdict-only function to keep
# in step with this one.
_verdict() {
  aid_release_scope_evaluate "$R" "$(aid_release_scope_start "$R" HEAD || true)" HEAD || return 1
  printf '%s\n' "$_AID_RS_VERDICT"
}

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

@test "an untagged repository says NEVER RELEASED, explicitly (Codex, P089)" {
  _config
  ( cd "$R" && git tag -d v1.0.0 >/dev/null )
  _commit "feat: application work" src/app.txt
  run aid_release_scope_report "$R" "$(aid_release_scope_start "$R" HEAD || true)" HEAD
  # It PASSES — a first push must not demand a release — but it now says which
  # answer it gave. The earlier shape started at the root of history, and
  # `root..HEAD` excludes the root commit, so a repository whose single commit
  # WAS the whole application reported "no commits" and passed by accident.
  [[ "$output" == *"verdict: no_tag"* ]]
  [[ "$output" == *"no version tag"* ]]
}

@test "the start is measured from the sha being judged, not from HEAD (Codex, P089)" {
  _config
  _commit "feat: application work" src/app.txt
  local b; b="$(git -C "$R" rev-parse HEAD)"
  # A LATER tag on HEAD is not an ancestor of B, so asking about HEAD's tag
  # made the range B..B — empty — and the push passed unjudged.
  _commit "chore: later" docs/d.txt
  ( cd "$R" && git tag v2.0.0 )
  run bash -c 'true'
  aid_release_scope_evaluate "$R" "$(aid_release_scope_start "$R" "$b")" "$b"
  output="$_AID_RS_VERDICT"
  [ "$output" = "release_required" ]
}

@test "a merged feature branch is in the range and counts (Codex, P089)" {
  _config
  ( cd "$R"
    git checkout -q -b feature
    printf 'work\n' >> src/app.txt
    git add -A && git commit -q -m "feat: side work"
    git checkout -q main
    git merge -q --no-ff -m "merge: feature" feature )
  # Judging the RANGE with --first-parent would let the whole branch through.
  # The merge commit itself contributes nothing; its commits contribute their
  # own paths, which is the conservative and correct direction.
  run _verdict
  [ "$output" = "release_required" ]
}

# ─── the hook carries a COPY, and the copy is the same code ─────────────────
#
# The hook runs inside the consumer's repository, where the plugin cache is not
# on any path it knows, so it cannot source the library — the functions live in
# it as a copy. Two copies of a decision are how two answers start, so this is
# written as a byte comparison and not as a promise.

_region() { # _region <file>
  sed -n '/^# AID-RELEASE-SCOPE-PORTABLE-START$/,/^# AID-RELEASE-SCOPE-PORTABLE-END$/p' "$1"
}

@test "AC22: the copy in the pre-push hook is byte-identical to the library" {
  local lib="$AID_PLUGIN_PATH/scripts/lib/aid-release-scope.sh"
  local hook="$AID_PLUGIN_PATH/defaults/hooks/pre-push"
  local a b
  a="$(_region "$lib")"
  b="$(_region "$hook")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

# _push <ref> <sha> — drive the hook exactly as git does.
_push() {
  ( cd "$R" && printf '%s %s %s %s\n' "$1" "$2" "$1" "0000000" \
      | bash "$AID_PLUGIN_PATH/defaults/hooks/pre-push" origin git@example:repo.git )
}

@test "the hook refuses a push whose range leaves the exempt paths, and names the commits" {
  _config
  _commit "feat: real work" src/app.txt
  run _push refs/heads/main "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"changes code outside the release-exempt paths"* ]]
  [[ "$output" == *"feat: real work"* ]]
  [[ "$output" == *"No-Release:"* ]]
}

@test "the hook lets through a push whose range is entirely exempt" {
  _config
  _commit "fix(tests): flaky case" tests/t.txt
  run _push refs/heads/main "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "AC23: plan/* and task/* stay exempt" {
  _config
  _commit "feat: real work" src/app.txt
  run _push refs/heads/plan/P900 "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "an older sha is what the range ends at, not HEAD" {
  _config
  _commit "fix(tests): exempt" tests/t.txt
  local old; old="$(git -C "$R" rev-parse HEAD)"
  _commit "feat: real work, not being pushed" src/app.txt
  run _push refs/heads/main "$old"
  [ "$status" -eq 0 ]
  [[ "$output" != *"real work"* ]]
}

@test "each pushed ref is judged on its own" {
  _config
  _commit "feat: real work" src/app.txt
  local head; head="$(git -C "$R" rev-parse HEAD)"
  run bash -c "cd '$R' && printf 'refs/heads/plan/P900 %s refs/heads/plan/P900 0000000\nrefs/heads/main %s refs/heads/main 0000000\n' '$head' '$head' \
      | bash '$AID_PLUGIN_PATH/defaults/hooks/pre-push' origin git@example:repo.git"
  # The plan ref alone would have passed; main in the same push still blocks.
  [ "$status" -eq 1 ]
  [[ "$output" == *"refs/heads/main"* ]]
}

@test "AC21 in the COPY: a project with no config meets the old label behaviour inside the hook" {
  # The fail-open branch is measured HERE and not only in the library, because
  # inside the hook is where almost every consumer meets it.
  _commit "fix: a real fix" src/app.txt
  run _push refs/heads/main "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"without a version bump"* ]]
  [[ "$output" == *"release_exempt_paths is not set"* ]]
}

@test "AC21 in the COPY: with no config a chore-only range still passes, as it did before" {
  _commit "chore: tidy" src/app.txt
  run _push refs/heads/main "$(git -C "$R" rev-parse HEAD)"
  [ "$status" -eq 0 ]
}

@test "a deleted ref is skipped" {
  _config
  _commit "feat: real work" src/app.txt
  run _push refs/heads/main "0000000000000000000000000000000000000000"
  [ "$status" -eq 0 ]
}

@test "an exempt LOCAL ref pushed onto a guarded remote ref is still judged" {
  # `git push origin plan/P900:main` — the local side is exempt, what lands on
  # the remote is not. The whole-push pre-pass has read both sides since P068;
  # the per-ref loop now agrees with it instead of reading the remote alone.
  _config
  _commit "feat: real work" src/app.txt
  local head; head="$(git -C "$R" rev-parse HEAD)"
  run bash -c "cd '$R' && printf 'refs/heads/plan/P900 %s refs/heads/main 0000000\n' '$head' \
      | bash '$AID_PLUGIN_PATH/defaults/hooks/pre-push' origin git@example:repo.git"
  [ "$status" -eq 1 ]
}
