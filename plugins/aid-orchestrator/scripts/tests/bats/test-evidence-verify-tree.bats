#!/usr/bin/env bats
# aid-tier: t0
#
# Which TREE aid-evidence-verify.sh judges.
#
# ACTA, 2026-08-31: the plan's candidate sat in its own worktree, and the tool
# reported main's head and failed `git_clean` on another session's unrelated
# work — because evidence root and working tree were one value. C4 is
# `enforcement: observe`, which is the only reason that was survivable; as a
# blocking check it could never have verified a plan-branch candidate at all.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TOOL="$PLUGIN_ROOT/scripts/aid-evidence-verify.sh"
  TMP="$(mktemp -d)"
  DIRTY="$TMP/dirty"; CLEAN="$TMP/clean"
  for d in "$DIRTY" "$CLEAN"; do
    mkdir -p "$d"
    git -C "$d" init -q .
    git -C "$d" config user.email t@t; git -C "$d" config user.name T
    printf 'seed\n' > "$d/tracked.txt"
    git -C "$d" add tracked.txt
    git -C "$d" commit -q -m seed
  done
  printf 'changed\n' > "$DIRTY/tracked.txt"          # only this tree is dirty
}

# _pack <root> <epic> <run> <head> — a one-artifact v2 evidence pack under <root>
_pack() {
  local d="$1/.aid-o/work/evidence/$2/$3"
  mkdir -p "$d"
  printf 'base_commit: %s\n' "$4" > "$d/fsm-state.yaml"
  jq -n --arg h "$4" '{schema_version: "aid-2.0", control_protocol: "v2", artifact_type: "dispatch_record",
                       revision: {head_sha: $h}}' > "$d/dispatch-record.json"
}
teardown() { rm -rf "$TMP"; }

@test "--tree decides which working tree is judged, not the evidence root" {
  run env AID_PROJECT_ROOT="$DIRTY" bash "$TOOL" --tree "$CLEAN"
  [[ "$output" == *"git_clean"* ]]
  [[ "$output" == *"pass"* ]]
  [[ "$output" != *"$DIRTY has uncommitted"* ]]
}

@test "the dirty tree still fails when it IS the tree under judgement" {
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" --tree "$DIRTY"
  [[ "$output" == *"has uncommitted changes"* ]]
}

@test "the report names the tree it looked at, and where that came from" {
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" --tree "$DIRTY"
  [[ "$output" == *"$DIRTY"* ]]
  [[ "$output" == *"tree from --tree"* ]]
}

@test "the pack is found from a worktree whose AID_PROJECT_ROOT is the worktree itself" {
  local wt="$TMP/wt"
  git -C "$CLEAN" worktree add -q -b plan/x "$wt"
  _pack "$CLEAN" P900 run-1 "$(git -C "$wt" rev-parse HEAD)"
  run env AID_PROJECT_ROOT="$wt" bash "$TOOL" P900 run-1 --tree "$wt" --out "$TMP/r.json"
  echo "$output"
  [[ "$output" != *"no evidence packs found"* ]]
  [[ "$output" != *"evidence directory not found"* ]]
  git -C "$CLEAN" worktree remove --force "$wt"
}

@test "an untracked directory in the judged tree is not dirt" {
  mkdir -p "$CLEAN/.aid-o/work"; printf 'x\n' > "$CLEAN/.aid-o/work/runtime.json"
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" --tree "$CLEAN"
  [[ "$output" != *"has uncommitted changes"* ]]
}

@test "--candidate is what freshness is measured against, while HEAD is elsewhere" {
  local wt="$TMP/wt2"
  git -C "$CLEAN" worktree add -q -b plan/y "$wt"
  ( cd "$wt" && printf 'more\n' >> tracked.txt && git add -A && git -c user.email=t@t -c user.name=T commit -q -m candidate )
  local cand; cand="$(git -C "$wt" rev-parse HEAD)"
  _pack "$CLEAN" P901 run-1 "$cand"
  # the pack's head is the candidate, not the primary checkout's HEAD
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" P901 run-1 --at-head --tree "$wt" --out "$TMP/r2.json"
  echo "$output"
  [ "$(jq -r '.verification_report.checks[] | select(.id == "artifact_head_freshness") | .status' "$TMP/r2.json")" = pass ]
  # without the candidate, judged against the worktree HEAD, it still passes;
  # judged against a DIFFERENT head it does not
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" P901 run-1 --at-head --tree "$wt" \
    --candidate "$(git -C "$CLEAN" rev-parse HEAD)" --out "$TMP/r3.json"
  [ "$(jq -r '.verification_report.checks[] | select(.id == "artifact_head_freshness") | .status' "$TMP/r3.json")" = fail ]
  git -C "$CLEAN" worktree remove --force "$wt"
}

@test "a candidate that is not reachable is unverifiable, naming the sha" {
  _pack "$CLEAN" P902 run-1 "$(git -C "$CLEAN" rev-parse HEAD)"
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" P902 run-1 --at-head --tree "$CLEAN" \
    --candidate 0000000000000000000000000000000000000000 --out "$TMP/r4.json"
  [ "$(jq -r '.verification_report.checks[] | select(.id == "artifact_head_freshness") | .status' "$TMP/r4.json")" = unverifiable ]
  [[ "$(jq -r '.verification_report.checks[] | select(.id == "artifact_head_freshness") | .detail' "$TMP/r4.json")" == *0000000* ]]
}

@test "no pack and no --out writes no report and exits 1" {
  local marker="$TMP/marker"; touch "$marker"
  run env AID_PROJECT_ROOT="$CLEAN" bash "$TOOL" --tree "$CLEAN"
  [ "$status" -eq 1 ]
  [ -z "$(find "$CLEAN" "$TMP" -name verification-report.json -newer "$marker" 2>/dev/null)" ]
}

# ── ancillary-filtered cleanliness (one definition of "clean" for the boundary) ──

# _track_counter <repo> — a tracked, then modified, .aid-o/config/counter.yaml
_track_counter() {
  mkdir -p "$1/.aid-o/config"; printf 'plan: 1\n' > "$1/.aid-o/config/counter.yaml"
  git -C "$1" add -f .aid-o/config/counter.yaml; git -C "$1" commit -q -m counter
  printf 'plan: 2\n' > "$1/.aid-o/config/counter.yaml"
}
# _git_clean <repo> <field> — run the verifier on <repo> with a pack, print one field of the git_clean check
_git_clean() {
  _pack "$1" P902 run-1 "$(git -C "$1" rev-parse HEAD)"
  env AID_PROJECT_ROOT="$1" bash "$TOOL" P902 run-1 --tree "$1" --out "$TMP/clean.json" >/dev/null 2>&1 || true
  jq -r --arg f "$2" '.. | objects | select(.id? == "git_clean") | .[$f]' "$TMP/clean.json"
}

@test "a modified counter.yaml and an untracked runtime directory are not dirt, in the verifier and in the plan FSM's strict list" {
  _track_counter "$CLEAN"; mkdir -p "$CLEAN/.aid-o/work/run"; : > "$CLEAN/.aid-o/work/run/x.json"
  [ "$(_git_clean "$CLEAN" status)" = pass ]
  [[ "$(_git_clean "$CLEAN" evidence)" == *"counter.yaml"* ]]      # the report says what it did not count
  # the list behind _pfsm_check_clean_worktree and the drift detector's fallback
  run bash -c "source '$PLUGIN_ROOT/scripts/lib/aid-ancillary.sh'; git -C '$CLEAN' status --porcelain --untracked-files=no | aid_ancillary_filter_porcelain --mode legacy5"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "a modified tracked source file still fails beside an ancillary one" {
  _track_counter "$DIRTY"
  [ "$(_git_clean "$DIRTY" status)" = fail ]
  [[ "$(_git_clean "$DIRTY" evidence)" == *"tracked.txt"* ]]
}

@test "a project policy that lists a delivery path as ancillary is refused naming the entry" {
  mkdir -p "$DIRTY/.aid-o/config/policies"
  printf 'plan_final:\n  ancillary_paths:\n    - ".aid-o/work/**"\n    - "tracked.txt"\n' > "$DIRTY/.aid-o/config/policies/plan-final-policy.yaml"
  [ "$(_git_clean "$DIRTY" status)" = fail ]
  [[ "$(_git_clean "$DIRTY" detail)" == *"policy is refused"* ]]
  [[ "$(_git_clean "$DIRTY" evidence)" == *"'tracked.txt'"* ]]
}

@test "a protected path of the plan is dirt even when an ancillary glob matches it" {
  mkdir -p "$CLEAN/.aid-o/work/plan-state/P902" "$CLEAN/.aid-o/work/notes"
  printf 'v1\n' > "$CLEAN/.aid-o/work/notes/handover.md"
  git -C "$CLEAN" add -f .aid-o/work/notes/handover.md; git -C "$CLEAN" commit -q -m notes
  printf 'v2\n' > "$CLEAN/.aid-o/work/notes/handover.md"
  [ "$(_git_clean "$CLEAN" status)" = pass ]                        # ancillary while nothing protects it
  jq -n '{plan_boundary_manifest: {protected_paths: [".aid-o/work/notes/handover.md"]}}' \
    > "$CLEAN/.aid-o/work/plan-state/P902/plan-boundary-manifest.json"
  [ "$(_git_clean "$CLEAN" status)" = fail ]
}
