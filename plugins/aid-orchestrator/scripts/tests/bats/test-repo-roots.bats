#!/usr/bin/env bats
# aid-tier: t1
# test-repo-roots.bats — the one mapping of a plan's foreign repositories
# (P112 Step 1): which worktree a declared path lives in, for a plan file and
# a plan.json alike, and the rewrite of a command text.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  TEST_DIR="$(mktemp -d)"; TEST_DIR="$(realpath "$TEST_DIR")"; cd "$TEST_DIR"
  git init -q -b main proj; git -C proj commit -q --allow-empty -m seed
  _repo() { mkdir -p "$1"; git -C "$1" init -q -b main; git -C "$1" -c user.email=t@t -c user.name=T commit -q --allow-empty -m init; }
  X="$TEST_DIR/x"; _repo "$X/docs"; _repo "$X/docs-api"; _repo "$X/docs-backup"
  cat > proj/plan.md <<EOF
---
id: P900
repo_roots: [{name: docs, path: $X/docs/}, {name: api, path: $X/docs-api}]
---
# Plan
EOF
  source "$AID_PLUGIN_PATH/scripts/lib/aid-repo-roots.sh"
  aid_rr_entries proj/plan.md P900 proj > ents.tsv
  jq -Rn --rawfile t ents.tsv '{repo_roots: ($t | split("\n") | map(select(length>0) | split("\t") | {name: .[0], path: .[1], worktree: .[2], branch: .[3]}))}' > plan.json
  WD="$X/docs/.aid-worktrees/plan-P900--docs"; WA="$X/docs-api/.aid-worktrees/plan-P900--api"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "rr: entries from a plan file and from its plan.json agree (physical path, worktree, branch)" {
  [ "$(cat ents.tsv)" = "$(printf 'docs\t%s\t%s\tplan/P900-proj\napi\t%s\t%s\tplan/P900-proj' "$X/docs" "$WD" "$X/docs-api" "$WA")" ]
  [ "$(aid_rr_entries plan.json)" = "$(cat ents.tsv)" ]
}

@test "rr: a path inside a declared repository maps into its worktree (plain, trailing slash, symlinked spelling)" {
  run aid_rr_path plan.json "$X/docs/a/b.md"
  [ "$output" = "$WD/a/b.md" ] && [ "$status" -eq 3 ]          # worktree not created yet → 3
  git -C "$X/docs" worktree add -q -b plan/P900-proj "$WD"
  run aid_rr_path plan.json "$X/docs/a/"
  [ "$output" = "$WD/a/" ] && [ "$status" -eq 0 ]
  ln -s "$X/docs" link
  run aid_rr_path plan.json "$TEST_DIR/link/new.md"
  [ "$output" = "$WD/new.md" ]
  run aid_rr_path plan.json "$X/docs-api/f"
  [ "$output" = "$WA/f" ]
}

@test "rr: a path in an undeclared repository, in the project or relative stays unchanged" {
  run aid_rr_path plan.json "$X/docs-backup/f";  [ "$output" = "$X/docs-backup/f" ] && [ "$status" -eq 0 ]
  run aid_rr_path plan.json "$TEST_DIR/proj/f";  [ "$output" = "$TEST_DIR/proj/f" ]
  run aid_rr_path plan.json "docs/f";            [ "$output" = "docs/f" ]
  run aid_rr_path plan.json "/tmp/nowhere/f";    [ "$output" = "/tmp/nowhere/f" ]
}

@test "rr: aid_rr_text rewrites nested declared prefixes to the right worktrees, longest first" {
  run aid_rr_text plan.json "cat $X/docs/f $X/docs-api/g $X/docs"
  [ "$output" = "cat $WD/f $WA/g $WD" ]
}

@test "rr: aid_rr_text leaves a longer sibling and a path that only contains the declared one" {
  run aid_rr_text plan.json "ls $X/docs-backup/f /tmp/archive$X/docs/f ${X}/docsy"
  [ "$output" = "ls $X/docs-backup/f /tmp/archive$X/docs/f ${X}/docsy" ]
}

@test "rr: aid_rr_text rewrites through shell punctuation" {
  run aid_rr_text plan.json "grep -q x $X/docs/f; (cat $X/docs/f)|wc -l && test -f \"$X/docs/f\" && echo '$X/docs-api'>o"
  [ "$output" = "grep -q x $WD/f; (cat $WD/f)|wc -l && test -f \"$WD/f\" && echo '$WA'>o" ]
}

@test "rr: a plan without repo_roots returns nothing and rewrites nothing" {
  printf -- '---\nid: P901\n---\n# P\n' > proj/bare.md
  run aid_rr_entries proj/bare.md;                      [ "$status" -eq 0 ] && [ -z "$output" ]
  echo '{"steps":[]}' > bare.json
  run aid_rr_text bare.json "cat $X/docs/f";            [ "$output" = "cat $X/docs/f" ]
  run aid_rr_path bare.json "$X/docs/f";                [ "$output" = "$X/docs/f" ]
}

@test "rr: a declared path that is not the top of a git repository (none, or a subdirectory) is named and fails" {
  printf -- '---\nid: P902\nrepo_roots: [{name: gone, path: %s/none}]\n---\n' "$X" > proj/bad.md
  run aid_rr_entries proj/bad.md P902 proj
  [ "$status" -eq 1 ] && [[ "$output" == *"repo_roots 'gone'"*"not the top of a git repository"* ]]
  mkdir -p "$X/docs/sub"
  printf -- '---\nid: P903\nrepo_roots: [{name: sub, path: %s/docs/sub}]\n---\n' "$X" > proj/sub.md
  run aid_rr_entries proj/sub.md P903 proj
  [ "$status" -eq 1 ] && [[ "$output" == *"repo_roots 'sub'"*"not the top"* ]]
}

@test "rr: aid_rr_load caches the mapping for the shell" {
  aid_rr_load plan.json
  [ "$_AID_RR_CACHE_KEY" = plan.json ]
  [ "$(aid_rr_text plan.json "$X/docs/f")" = "$WD/f" ]
}
