#!/usr/bin/env bats
# test-lifecycle-reconcile.bats — IMP-232 v2.58.0 plan-close + legacy reconcile +
# interruption safety (§5.8) + repo-local identity isolation. Complements
# test-lifecycle.bats (foundation) and test-aid-fsm.bats (D1 gate).

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  CLI="$AID_PLUGIN_PATH/scripts/aid-lifecycle.sh"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
}
teardown() { rm -rf "$TEST_DIR"; }

# helper: fresh repo on main
_repo() {
  local d="$1"; mkdir -p "$d"; ( cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email t@t.io; git config user.name T
    echo s > s; git add -A; git commit -q -m s )
}
# helper: merge an EPIC into main with audit provenance (reviewed head = merged head)
_merge_epic() { # <root> <epic_id>
  local root="$1" eid="$2"
  ( cd "$root"
    git checkout -q -b "task/$eid"; echo "w-$eid" > "f-$eid"; git add -A; git commit -q -m "w $eid"
    local rhead; rhead="$(git rev-parse HEAD)"
    git checkout -q main; git merge -q --no-ff "task/$eid" -m "merge: $eid — done"
    local ev=".aid-o/work/evidence/$eid/R-1"; mkdir -p "$ev"
    printf '{"revision":{"head_sha":"%s"},"blocking_findings":false}\n' "$rhead" > "$ev/audit-report.json" )
}
# helper: manifest with all-required delivered (forward path)
_manifest_delivered() { # <root> <plan_id>
  local root="$1" pid="$2"; mkdir -p "$root/.aid-lifecycle/manifests"
  cat > "$root/.aid-lifecycle/manifests/${pid}.yaml" <<YML
schema_version: aid-lifecycle-1.0
repo_id: t
plan_id: ${pid}
declared_epics:
  - {id: E-${pid#P}-1_1, scope: required}
depends_on_plans: []
deliveries:
  E-${pid#P}-1_1: {reviewed_sha: aaa, reviewed_verdict: pass, unresolved_blockers: 0, delivery_sha: d1}
YML
}

# ── plan-close (forward path) ────────────────────────────────────────────────
@test "plan-close: delivered-but-unreconciled -> closed (committed, reachable)" {
  _repo r; _manifest_delivered r P900
  run "$CLI" plan-close P900 r
  [ "$status" -eq 0 ]
  [ "$("$CLI" state P900 r)" = "closed" ]
  # git tree clean (receipt committed); no dangling changes
  run bash -c "cd r && git status --porcelain --untracked-files=no"
  [ -z "$output" ]
}

@test "plan-close: active plan fails, writes NO receipt (fail-closed)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n**EPIC 2: b (Steps 2-2)**\n' > r/.aid-o/plans/P902-x.md
  run "$CLI" plan-close P902 r
  [ "$status" -ne 0 ]
  [ ! -f r/.aid-lifecycle/receipts/P902.yaml ]
}

@test "plan-close: idempotent (re-close of a closed plan is a no-op success)" {
  _repo r; _manifest_delivered r P900
  "$CLI" plan-close P900 r
  run "$CLI" plan-close P900 r
  [ "$status" -eq 0 ]
}

# ── legacy reconcile ─────────────────────────────────────────────────────────
@test "reconcile: P061-shaped (E1-E3 merged, E4-E5 not) -> active" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n**EPIC 2: b (Steps 2-2)**\n**EPIC 3: c (Steps 3-3)**\n**EPIC 4: d (Steps 4-4)**\n**EPIC 5: e (Steps 5-5)**\n' > r/.aid-o/plans/P061-x.md
  _merge_epic r E-061-1_5; _merge_epic r E-061-2_5; _merge_epic r E-061-3_5
  run "$CLI" plan-reconcile P061 --apply r
  [ "$status" -eq 0 ]
  [ "$("$CLI" state P061 r)" = "active" ]
  [ ! -f r/.aid-lifecycle/receipts/P061.yaml ]
}

@test "reconcile: isolated fixture, all required merged+accepted -> closed on --apply" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n**EPIC 2: b (Steps 2-2)**\n' > r/.aid-o/plans/P800-x.md
  _merge_epic r E-800-1_2; _merge_epic r E-800-2_2
  run "$CLI" plan-reconcile P800 --apply r
  [ "$status" -eq 0 ]
  [ "$("$CLI" state P800 r)" = "closed" ]
}

@test "reconcile: --dry-run mutates NOTHING (no manifest/receipt/commit)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P800-x.md
  _merge_epic r E-800-1_1
  local head_before; head_before="$(cd r && git rev-parse HEAD)"
  run "$CLI" plan-reconcile P800 --dry-run r
  [ "$status" -eq 0 ]
  [ ! -f r/.aid-lifecycle/manifests/P800.yaml ]
  [ ! -f r/.aid-lifecycle/receipts/P800.yaml ]
  [ "$(cd r && git rev-parse HEAD)" = "$head_before" ]
}

@test "reconcile: fabricated merge without reviewed-head provenance -> NOT closed" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P810-x.md
  ( cd r; git checkout -q -b task/x; echo w>f; git add -A; git commit -q -m w; git checkout -q main
    git merge -q --no-ff task/x -m "merge: E-810-1_1 — trust me it is done" )
  run "$CLI" plan-reconcile P810 --apply r
  [ "$("$CLI" state P810 r)" = "active" ]
  [ ! -f r/.aid-lifecycle/receipts/P810.yaml ]
}

@test "reconcile: audit report OMITTING blocking_findings is NOT accepted -> active (fail-closed)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P760-x.md
  ( cd r; git checkout -q -b task/e; echo w>f; git add -A; git commit -q -m w
    rhead="$(git rev-parse HEAD)"; git checkout -q main
    git merge -q --no-ff task/e -m "merge: E-760-1_1 — done"
    ev=".aid-o/work/evidence/E-760-1_1/R-1"; mkdir -p "$ev"
    # valid ancestor head_sha but NO blocking_findings verdict
    printf '{"revision":{"head_sha":"%s"}}\n' "$rhead" > "$ev/audit-report.json" )
  run "$CLI" plan-reconcile P760 --apply r
  [ "$("$CLI" state P760 r)" = "active" ]
  [ ! -f r/.aid-lifecycle/receipts/P760.yaml ]
}

@test "reconcile: absent plan -> not_found (no synthetic state)" {
  _repo r
  run "$CLI" plan-reconcile P064 --apply r
  [[ "$output" == *"not_found"* ]]
  [ ! -d r/.aid-lifecycle/manifests ] || [ -z "$(ls r/.aid-lifecycle/manifests 2>/dev/null)" ]
}

# ── §5.8 interruption safety ─────────────────────────────────────────────────
@test "interrupt AFTER receipt write, BEFORE commit: untracked receipt does NOT block; recovery closes" {
  _repo r; _manifest_delivered r P900
  # simulate: receipt written to worktree but never committed
  mkdir -p r/.aid-lifecycle/receipts
  ( cd r && source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh" && aid_lifecycle_build_receipt P900 . > .aid-lifecycle/receipts/P900.yaml )
  # state reflects the not-yet-durable receipt
  [ "$("$CLI" state P900 r)" = "closing_pending_commit" ]
  # init's clean-worktree guard ignores untracked files -> NOT blocked
  run bash -c "cd r && git status --porcelain --untracked-files=no"
  [ -z "$output" ]
  # recovery: plan-close commits it -> closed
  run "$CLI" plan-close P900 r
  [ "$status" -eq 0 ]
  [ "$("$CLI" state P900 r)" = "closed" ]
}

@test "interrupt AFTER git add (staged receipt): recovery (re-run) commits it, ends clean+closed" {
  _repo r; _manifest_delivered r P900
  mkdir -p r/.aid-lifecycle/receipts
  ( cd r && source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh" && aid_lifecycle_build_receipt P900 . > .aid-lifecycle/receipts/P900.yaml && git add -- .aid-lifecycle/receipts/P900.yaml )
  # recovery: plan-close is idempotent -> commits the staged receipt
  run "$CLI" plan-close P900 r
  [ "$status" -eq 0 ]
  [ "$("$CLI" state P900 r)" = "closed" ]
  run bash -c "cd r && git status --porcelain --untracked-files=no"
  [ -z "$output" ]
}

@test "plan-close leaves OTHER working changes untouched (pathspec commit)" {
  _repo r; _manifest_delivered r P900
  ( cd r && echo "unrelated" > other.txt && git add other.txt )  # user's staged change
  run "$CLI" plan-close P900 r
  [ "$status" -eq 0 ]
  # the user's staged file is still staged + uncommitted (not swept into the receipt commit)
  run bash -c "cd r && git diff --cached --name-only"
  [[ "$output" == *"other.txt"* ]]
}

# ── repo-local identity isolation ────────────────────────────────────────────
@test "identity: same plan id P061 in two repos resolves independently (no cross-contamination)" {
  _repo r1; _repo r2
  local id1 id2
  id1="$("$CLI" repo-id r1)"; id2="$("$CLI" repo-id r2)"
  [ "$id1" != "$id2" ]                       # unrelated repos differ
  # a closed P061 in r1 must not make r1's P061 look closed from r2's perspective
  _manifest_delivered r1 P061; "$CLI" plan-close P061 r1 >/dev/null
  [ "$("$CLI" state P061 r1)" = "closed" ]
  [ "$("$CLI" state P061 r2)" = "not_found" ]   # r2 has its own (absent) P061
}

@test "identity: stable across a clone (git-tracked .aid-lifecycle/repo-identity.yaml)" {
  _repo r1
  local id1; id1="$("$CLI" repo-id r1)"
  ( cd r1 && git add -A && git commit -q -m "identity" )
  git clone -q r1 r1clone
  [ "$("$CLI" repo-id r1clone)" = "$id1" ]    # clone carries the same identity
}
