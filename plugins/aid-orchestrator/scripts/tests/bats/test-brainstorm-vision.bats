#!/usr/bin/env bats
# aid-tier: t2
# test-brainstorm-vision.bats — the vision step of a brainstorm (P086 Step 7).
#
# THE GROUNDED FAILURE MODE: "agree the shared boundaries before designing" as
# a sentence in a skill is degree 4 on the ecosystem scale — prose. The same
# rule with a transition behind it is a door that does not open. What is proved
# here is the transition: a vision point with nothing that could show it false
# is not accepted, and a phase does not start on a vision the PM has not agreed.
#
# WHERE THE DOOR REALLY CLOSES, stated so no test here is read as more than it
# is: `gate --phase opponent` is called by lib/aid-brainstorm-opponent.sh, so
# for the opponent this is enforcement. `gate --phase design` is called by the
# controller following the skill, so there it is a checkable instruction. Both
# are tested; only one of them is a closed door.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  BS="$PLUGIN_ROOT/scripts/aid-brainstorm-state.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/project"
  mkdir -p "$ROOT/.aid-o/work"
  (
    cd "$ROOT"
    git init -q -b main 2>/dev/null || { git init -q; git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    printf '.aid-o/\n.aid-worktrees/\n' > .gitignore
    printf 'seed\n' > README.md
    git add -A && git commit -q -m seed
  )
  export AID_PROJECT_ROOT="$ROOT"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP"
  return 0
}

vision() { printf '%s\n' "$1" > "$TMP/vision.md"; printf '%s' "$TMP/vision.md"; }

GOOD_VISION='## Vision

- V1: Every rule AID enforces has a mechanism, not a sentence.
  - test: each row of the enforcement registry names a degree and a source.
- V2: A brainstorm produces a page the PM can read in one sitting.
  - test: the rendered page fits the artifact standard ceilings.'

@test "AC21: a vision point with no test is not accepted" {
  bash "$BS" init P900 --scope roadmap --no-worktree
  local f; f="$(vision '## Vision

- V1: Everything should be better.
- V2: A brainstorm produces a page the PM can read.
  - test: the page fits the ceilings.')"
  run bash "$BS" vision-propose P900 --file "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"V1: Everything should be better."* ]]
  [[ "$output" != *"V2:"* ]]
  [[ "$output" == *"slogan"* ]]
}

@test "a vision where every point carries a test is accepted, and then waits for the PM" {
  bash "$BS" init P900 --scope roadmap --no-worktree
  run bash "$BS" vision-propose P900 --file "$(vision "$GOOD_VISION")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs the PM's approval"* ]]
  run bash "$BS" show P900
  [[ "$output" == *'vision_state: "proposed"'* ]]
}

@test "a file with no vision points at all is refused, naming the form" {
  bash "$BS" init P900 --scope roadmap --no-worktree
  run bash "$BS" vision-propose P900 --file "$(vision 'Some prose about the idea.')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"- V1:"* ]]
}

@test "AC23: no phase starts on a vision the PM has not approved" {
  bash "$BS" init P900 --scope roadmap --no-worktree
  run bash "$BS" gate P900 --phase design
  [ "$status" -eq 1 ]
  [[ "$output" == *"is 'none', not approved"* ]]

  bash "$BS" vision-propose P900 --file "$(vision "$GOOD_VISION")"
  run bash "$BS" gate P900 --phase design
  [ "$status" -eq 1 ]
  [[ "$output" == *"'proposed', not approved"* ]]

  bash "$BS" vision-approve P900
  run bash "$BS" gate P900 --phase design
  [ "$status" -eq 0 ]
  run bash "$BS" gate P900 --phase opponent
  [ "$status" -eq 0 ]
}

@test "an unproposed vision cannot be approved into existence" {
  bash "$BS" init P900 --scope roadmap --no-worktree
  run bash "$BS" vision-approve P900
  [ "$status" -eq 1 ]
  [[ "$output" == *"only a proposed vision can be approved"* ]]
}

@test "a rejected vision closes the door again" {
  bash "$BS" init P900 --scope roadmap --no-worktree
  bash "$BS" vision-propose P900 --file "$(vision "$GOOD_VISION")"
  bash "$BS" vision-approve P900
  run bash "$BS" vision-reject P900 --reason "the second point is not ours to decide"
  [ "$status" -eq 0 ]
  run bash "$BS" gate P900 --phase design
  [ "$status" -eq 1 ]
}

@test "AC22: a single short plan has no vision step, and the skip is recorded" {
  run bash "$BS" init P901 --scope single_plan --no-worktree
  [ "$status" -eq 0 ]
  [[ "$output" == *"no vision step"* ]]
  run bash "$BS" show P901
  [[ "$output" == *"vision_required: false"* ]]
  [[ "$output" == *"skip_reason:"* ]]
  [[ "$output" != *'skip_reason: ""'* ]]
  run bash "$BS" gate P901 --phase design
  [ "$status" -eq 0 ]
  [[ "$output" == *"no vision step"* ]]
}

@test "AC4: work a user will notice needs the vision, even as one plan" {
  # The original rule tied the vision to plan COUNT, which is a proxy for what
  # actually matters: whether the two of you can afford to have meant different
  # things. A single plan that changes what a user sees cannot.
  bash "$BS" init P903 --scope user_visible --no-worktree
  run bash "$BS" gate P903 --phase opponent
  [ "$status" -eq 1 ]
  [[ "$output" == *"not approved"* ]]
}

@test "AC5: only work nobody outside the code notices skips it, and says why" {
  run bash "$BS" init P904 --scope single_plan --no-worktree
  [ "$status" -eq 0 ]
  [[ "$output" == *"no vision step"* ]]
  run bash "$BS" show P904
  [[ "$output" == *"no user will notice"* ]]
}

@test "an unknown scope is a usage error, not the cheapest category" {
  run bash "$BS" init P905 --scope whatever --no-worktree
  [ "$status" -eq 2 ]
  [[ "$output" == *"user_visible"* ]]
}

@test "work split across plans needs the vision, same as a roadmap" {
  bash "$BS" init P902 --scope multi_plan --no-worktree
  run bash "$BS" gate P902 --phase design
  [ "$status" -eq 1 ]
}

@test "AC18: starting a run gives it its own working copy and says where it is" {
  run bash "$BS" init P900 --scope roadmap
  [ "$status" -eq 0 ]
  [[ "$output" == *"workdir: $ROOT/.aid-worktrees/brainstorm-P900"* ]]
  [ -d "$ROOT/.aid-worktrees/brainstorm-P900" ]
}

@test "a working copy git will not give out falls back to the primary checkout" {
  git -C "$ROOT" worktree add -q "$TMP/taken" -b brainstorm/P900 main
  run bash "$BS" init P900 --scope roadmap
  [ "$status" -eq 0 ]
  [[ "$output" == *"workdir: $ROOT"* ]]
}

@test "a gate on a run that was never started says how to start it" {
  run bash "$BS" gate P999 --phase design
  [ "$status" -eq 1 ]
  [[ "$output" == *"no brainstorming run for P999"* ]]
}

@test "an unknown scope or phase is a usage error, not a default" {
  run bash "$BS" init P900 --scope whatever --no-worktree
  [ "$status" -eq 2 ]
  bash "$BS" init P900 --scope roadmap --no-worktree
  run bash "$BS" gate P900 --phase whenever
  [ "$status" -eq 2 ]
}

# ── P100 Step 8: the visual companion's door ─────────────────────────────────
_approved() {  # _approved <plan> <init args…> — a started run with an approved vision
  local p="$1"; shift
  bash "$BS" init "$p" --scope user_visible --no-worktree "$@" >/dev/null
  bash "$BS" vision-propose "$p" --file "$(vision "$GOOD_VISION")" >/dev/null
  bash "$BS" vision-approve "$p" >/dev/null
}
@test "P100: a user_visible design gate needs a topic kind, and a UI topic a proposal built from the application" {
  _approved P910
  run bash "$BS" gate P910 --phase design
  [ "$status" -eq 1 ]; [[ "$output" == *"--topic-kind ui|other"* ]]
  _approved P911 --topic-kind ui
  run bash "$BS" gate P911 --phase design
  [ "$status" -eq 1 ]; [[ "$output" == *"aid_ui_proposal_build"* ]]
  ( cd "$ROOT" && source "$PLUGIN_ROOT/scripts/lib/aid-ui-proposal.sh" && aid_ui_proposal_build "$ROOT" "$ROOT/.aid-o/work/brainstorm/P911" >/dev/null )
  run bash "$BS" gate P911 --phase design
  echo "$output"; [ "$status" -eq 0 ]
  _approved P912 --topic-kind other --reason "a CLI flag, nothing is drawn on a screen"
  run bash "$BS" gate P912 --phase design
  [ "$status" -eq 0 ]
  run bash "$BS" init P913 --scope user_visible --no-worktree --topic-kind other
  [ "$status" -eq 2 ]; [[ "$output" == *"--reason of at least 20 characters"* ]]
  # a hand-written proposal without real viewports is not a basis
  _approved P914 --topic-kind ui
  echo '{"basis":"live-screen","viewports":"x"}' > "$ROOT/.aid-o/work/brainstorm/P914/proposal.json"
  run bash "$BS" gate P914 --phase design
  [ "$status" -eq 1 ]
  # the PM declining the real application is recorded on the running run
  run bash "$BS" topic-kind P914 other --reason "the PM wants a sketch, not the app"
  [ "$status" -eq 0 ]
  run bash "$BS" gate P914 --phase design
  [ "$status" -eq 0 ]
}
