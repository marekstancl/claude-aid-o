#!/usr/bin/env bats
# test-lifecycle-e2e.bats — IMP-232 v2.58.1 END-TO-END wiring proof. Verifies the
# closure model is actually INVOKED by the runtime path (not a library nobody
# calls), via aid-fsm.sh's real subcommands + the post-merge record-delivery hook.
# Maps to the mandatory audit reproductions: manifest at scaffold, pre-merge makes
# no tracked lifecycle commit, real merge records provenance, last required EPIC
# -> committed receipt + closed, clean clone -> same closed, P061 delivered-but-
# unverifiable -> active, and no lifecycle op ever changes the user's index.

setup() {
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH AID_QUIET=1 AID_TEST_MODE=1
  FSM="$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  CLI="$AID_PLUGIN_PATH/scripts/aid-lifecycle.sh"
  LIB="$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
  TEST_DIR="$(mktemp -d)"
  cd "$TEST_DIR"
}
teardown() { rm -rf "$TEST_DIR"; }

_repo() {
  local d="$1"; mkdir -p "$d"; ( cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email t@t.io; git config user.name T
    printf '.aid-o/\n' > .gitignore   # match real AID: gitignored evidence workspace
    echo seed > seed; git add -A; git commit -q -m seed )
}
# merge an EPIC into main with audit provenance (reviewed head = the merged head).
# $3 = review json body ('accepted' | 'unverifiable' | 'none')
_merge_epic() {
  local root="$1" eid="$2" kind="$3"
  ( cd "$root"
    git checkout -q -b "task/$eid"; echo "w-$eid" > "f-$eid"; git add -A; git commit -q -m "w $eid"
    git checkout -q main; git merge -q --no-ff "task/$eid" -m "feat: complete EPIC $eid"
    local sp; sp="$(git rev-parse HEAD^2)"     # the EPIC head, ancestor of the merge
    if [[ "$kind" != "none" ]]; then
      local ev=".aid-o/work/evidence/$eid/R-1"; mkdir -p "$ev"
      case "$kind" in
        accepted)     printf '{"revision":{"head_sha":"%s"},"blocking_findings":false}\n' "$sp" > "$ev/audit-report.json" ;;
        unverifiable) printf '{"status":"unverifiable","revision":{"head_sha":"%s"},"blocking_findings":null}\n' "$sp" > "$ev/audit-report.json" ;;
      esac
    fi )
}

# ── #1: manifest at official scaffold (committed manifest + identity) ─────────
@test "E2E #1: scaffold ensures a committed manifest + identity (pipeline call path)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n**EPIC 2: b (Steps 2-2)**\n' > r/.aid-o/plans/P800-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P800 . )
  run bash -c "cd r && git ls-files .aid-lifecycle/manifests/P800.yaml .aid-lifecycle/repo-identity.yaml"
  [[ "$output" == *"manifests/P800.yaml"* ]]
  [[ "$output" == *"repo-identity.yaml"* ]]
  # and the pipeline actually wires this call
  grep -q 'aid_lifecycle_ensure_manifest' "$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh"
}

# ── #3 + #4: real merge -> recorded provenance; last required -> receipt+closed ─
@test "E2E #3/#4: post-merge record-delivery records provenance; last required -> closed" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n**EPIC 2: b (Steps 2-2)**\n' > r/.aid-o/plans/P800-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P800 . )
  _merge_epic r E-800-1_2 accepted
  run "$FSM" plan-record-delivery E-800-1_2 r
  [[ "$output" == *"delivery=delivered"* ]]
  [ "$("$FSM" plan-state P800 r)" = "active" ]        # not last yet
  # manifest recorded the real delivery SHA
  run bash -c "cd r && yq -r '.deliveries.\"E-800-1_2\".delivery_sha' .aid-lifecycle/manifests/P800.yaml"
  [ -n "$output" ] && [ "$output" != "null" ]
  _merge_epic r E-800-2_2 accepted
  "$FSM" plan-record-delivery E-800-2_2 r
  [ "$("$FSM" plan-state P800 r)" = "closed" ]        # last required -> closed
  run bash -c "cd r && git ls-files .aid-lifecycle/receipts/P800.yaml"
  [[ "$output" == *"receipts/P800.yaml"* ]]
}

# ── #2: pre-merge / non-target usage never falsely closes ────────────────────
@test "E2E #2: record-delivery on a NON-target (task) branch refuses fail-closed (no HEAD/worktree/lifecycle change)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P800-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P800 . )
  _merge_epic r E-800-1_1 accepted
  ( cd r && git checkout -q -b task/side )            # simulate being on a task branch
  local head_before; head_before="$(cd r && git rev-parse HEAD)"
  run "$FSM" plan-record-delivery E-800-1_1 r
  [ "$status" -ne 0 ]                                   # refused (non-zero)
  [ "$(cd r && git rev-parse HEAD)" = "$head_before" ] # HEAD unchanged — NO commit on the task branch
  [ -z "$(cd r && git status --porcelain -- .aid-lifecycle)" ]  # no .aid-lifecycle worktree/index change
  [ ! -f r/.aid-lifecycle/receipts/P800.yaml ]          # no receipt written
  [ "$("$FSM" plan-state P800 r)" != "closed" ]
}

# ── #5: clean clone -> same closed ───────────────────────────────────────────
@test "E2E #5: a closed plan resolves closed after a clean clone" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P800-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P800 . )
  _merge_epic r E-800-1_1 accepted
  "$FSM" plan-record-delivery E-800-1_1 r
  [ "$("$FSM" plan-state P800 r)" = "closed" ]
  git clone -q r rclone
  # the clone has NO gitignored .aid-o evidence — closed must hold from the committed receipt alone
  [ ! -d rclone/.aid-o ]
  [ "$("$FSM" plan-state P800 rclone)" = "closed" ]
}

# ── #6: P061 -> active, delivered but review-unverifiable (never accepted) ────
@test "E2E #6: merged-but-unverifiable EPIC is delivered, review unverifiable, plan active" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n**EPIC 2: b (Steps 2-2)**\n' > r/.aid-o/plans/P061-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P061 . )
  _merge_epic r E-061-1_2 unverifiable
  run "$FSM" plan-record-delivery E-061-1_2 r
  [ "$("$FSM" plan-state P061 r)" = "active" ]
  run bash -c "cd r && yq -r '.deliveries.\"E-061-1_2\" | .delivery + \"/\" + .review' .aid-lifecycle/manifests/P061.yaml"
  [ "$output" = "delivered/unverifiable" ]
  run "$FSM" plan-reconcile P061 --dry-run r
  [[ "$output" == *"DELIVERED but review unverifiable"* ]]
  [ ! -f r/.aid-lifecycle/receipts/P061.yaml ]
}

# ── #8: no lifecycle op changes the user's index (fingerprint), incl. fault ───
# The USER's index fingerprint — deliberately EXCLUDES AID-managed .aid-lifecycle/
# paths (those are the lifecycle's own files; the invariant is that the user's own
# staged/working files are never touched).
_user_index_fp() { ( cd "$1" && { git diff --cached --name-status; echo "--"; git status --porcelain --untracked-files=no; } | grep -vE '\.aid-lifecycle/' || true ); }

@test "E2E #8: record-delivery leaves the user's staged/working index byte-identical" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P800-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P800 . )
  _merge_epic r E-800-1_1 accepted
  # user work: a staged file + an unstaged modification
  ( cd r && echo "user-staged" > u_staged.txt && git add u_staged.txt && echo "mod" >> seed )
  local fp_before; fp_before="$(_user_index_fp r)"
  "$FSM" plan-record-delivery E-800-1_1 r        # writes manifest + receipt (isolated)
  [ "$("$FSM" plan-state P800 r)" = "closed" ]
  local fp_after; fp_after="$(_user_index_fp r)"
  [ "$fp_before" = "$fp_after" ]
}

@test "E2E #8b: interruption after receipt worktree write (uncommitted) leaves user index untouched + recovery closes" {
  _repo r; mkdir -p r/.aid-o/plans r/.aid-lifecycle/receipts
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P800-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P800 . )
  _merge_epic r E-800-1_1 accepted
  # Faithful interrupt: the real record_delivery COMMITS the manifest binding
  # (isolated_commit) BEFORE writing the receipt, then would commit the receipt. So
  # bind + commit the manifest, then leave only the receipt uncommitted. (A manifest
  # binding left uncommitted is a different, git-checkout-recoverable state and is
  # now correctly refused by the entry precheck — see the UNSTAGED-collision test.)
  ( cd r && source "$LIB" && aid_lifecycle_bind_delivery P800 E-800-1_1 . \
      && _aid_lc_isolated_commit . "lifecycle: delivery E-800-1_1 (post-merge)" ".aid-lifecycle/manifests/P800.yaml" )
  ( cd r && echo "user-staged" > u_staged.txt && git add u_staged.txt )
  local fp_before; fp_before="$(_user_index_fp r)"
  # simulate interrupt: receipt written to worktree but NOT committed
  ( cd r && source "$LIB" && aid_lifecycle_build_receipt P800 . > .aid-lifecycle/receipts/P800.yaml )
  # user's staged index unchanged; untracked receipt ignored by --untracked-files=no
  [ "$(_user_index_fp r)" = "$fp_before" ]
  [ "$("$FSM" plan-state P800 r)" = "closing_pending_commit" ]
  # recovery via record-delivery -> closed, user index STILL untouched
  "$FSM" plan-record-delivery E-800-1_1 r
  [ "$("$FSM" plan-state P800 r)" = "closed" ]
  [ "$(_user_index_fp r)" = "$fp_before" ]
}

# ── F1 regression (v2.58.1 audit): ensure_manifest must not report a NON-DURABLE
# manifest as ensured. An on-disk manifest that is not committed on the target
# branch (interrupted commit) must be RE-COMMITTED on recovery, not fast-returned.
@test "E2E F1: ensure_manifest re-commits an on-disk-but-uncommitted manifest (durability, not mere existence)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P810-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P810 . )   # first: durable
  # simulate an interrupted commit: the manifest file survives on disk but is NOT
  # reachable on the target ref (stop tracking it, keep the worktree file).
  ( cd r && git rm -q --cached .aid-lifecycle/manifests/P810.yaml && git commit -q -m "drop manifest tracking" )
  [ -f r/.aid-lifecycle/manifests/P810.yaml ]                          # still on disk
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/manifests/P810.yaml"
  [ "$status" -ne 0 ]                                                  # NOT durable
  # user work must be untouched by the recovery commit
  ( cd r && echo "user-staged" > u_staged.txt && git add u_staged.txt )
  local fp_before; fp_before="$(_user_index_fp r)"
  # recovery: ensure must re-commit (return 0 only if durable) — pre-fix this
  # fast-returned 0 and left the manifest non-durable.
  run bash -c "cd r && source \"$LIB\" && aid_lifecycle_ensure_manifest P810 ."
  [ "$status" -eq 0 ]
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/manifests/P810.yaml"
  [ "$status" -eq 0 ]                                                  # NOW durable
  [ "$(_user_index_fp r)" = "$fp_before" ]                            # user index untouched
}

# F1 corollary: a strict plan's real pipeline must not proceed to EPIC generation
# with a non-durable manifest present on disk.
@test "E2E F1b: a strict plan whose manifest is present-but-uncommitted is re-committed durably at scaffold" {
  _repo r
  _mkplan r '**EPIC 1: a (Steps 1-1)**' strict
  # seed a durable manifest, then break its durability (file on disk, not on ref)
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P900 . )
  ( cd r && git rm -q --cached .aid-lifecycle/manifests/P900.yaml && git commit -q -m "drop tracking" )
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/manifests/P900.yaml"
  [ "$status" -ne 0 ]
  # run the REAL pipeline: it must NOT log 'ensured' over a non-durable manifest;
  # by scaffold end the manifest is durable again.
  run bash -c "cd r && \"$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh\" --plan .aid-o/plans/P900-x.md --queue-mode chain"
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/manifests/P900.yaml"
  [ "$status" -eq 0 ]
}

# ── external-audit regression (v2.58.1): unstaged (not just staged) collisions ──
# The isolated commit builds its tree from the worktree files on disk, so an
# UNSTAGED user edit to a tracked manifest/receipt must be refused, not swept in.
@test "E2E collision: an UNSTAGED user edit to the tracked manifest makes record-delivery refuse (nothing committed, edit preserved)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P820-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P820 . )   # manifest committed (tracked)
  _merge_epic r E-820-1_1 accepted                                    # would otherwise close the plan
  # user edits the tracked manifest but does NOT `git add` it
  ( cd r && printf '\n# USER UNSTAGED EDIT\n' >> .aid-lifecycle/manifests/P820.yaml )
  local head_before manifest_before
  head_before="$(cd r && git rev-parse HEAD)"
  manifest_before="$(sha256sum r/.aid-lifecycle/manifests/P820.yaml | cut -d' ' -f1)"
  run "$FSM" plan-record-delivery E-820-1_1 r
  [ "$status" -ne 0 ]                                                 # refused, not swept in
  [[ "$output" == *"UNSTAGED"* || "$output" == *"collision"* ]]
  [ "$(cd r && git rev-parse HEAD)" = "$head_before" ]               # HEAD unmoved
  [ "$(sha256sum r/.aid-lifecycle/manifests/P820.yaml | cut -d' ' -f1)" = "$manifest_before" ]  # user edit byte-identical
  [ -z "$(cd r && git diff --cached --name-only)" ]                   # user index untouched
  [ "$("$FSM" plan-state P820 r)" != "closed" ]                       # plan did NOT close
}

@test "E2E collision: a DIFFERING untracked receipt is refused, not clobbered (interrupted-run safety)" {
  _repo r; mkdir -p r/.aid-o/plans r/.aid-lifecycle/receipts
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P830-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P830 . )
  _merge_epic r E-830-1_1 accepted
  ( cd r && source "$LIB" && aid_lifecycle_bind_delivery P830 E-830-1_1 . )  # bound => canonical receipt is buildable
  # user drops a DIFFERENT untracked receipt in place (not our interrupted artifact)
  ( cd r && printf 'schema_version: aid-lifecycle-receipt-1.0\n# USER HAND-CRAFTED\n' > .aid-lifecycle/receipts/P830.yaml )
  local before; before="$(sha256sum r/.aid-lifecycle/receipts/P830.yaml | cut -d' ' -f1)"
  run bash -c "cd r && source \"$LIB\" && aid_lifecycle_commit_receipt P830 ."
  [ "$status" -ne 0 ]
  [[ "$output" == *"differs from the canonical receipt"* ]]
  [ "$(sha256sum r/.aid-lifecycle/receipts/P830.yaml | cut -d' ' -f1)" = "$before" ]   # not clobbered
}

@test "E2E collision: an interrupted-run untracked receipt that IS byte-identical to canonical still recovers (no false refusal)" {
  _repo r; mkdir -p r/.aid-o/plans r/.aid-lifecycle/receipts
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P840-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P840 . )
  _merge_epic r E-840-1_1 accepted
  ( cd r && source "$LIB" && aid_lifecycle_bind_delivery P840 E-840-1_1 . )
  # simulate our own interrupted run: the canonical receipt written to disk, uncommitted
  ( cd r && source "$LIB" && aid_lifecycle_build_receipt P840 . > .aid-lifecycle/receipts/P840.yaml )
  run bash -c "cd r && source \"$LIB\" && aid_lifecycle_commit_receipt P840 ."
  [ "$status" -eq 0 ]                                                 # identical => recovery proceeds
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/receipts/P840.yaml"
  [ "$status" -eq 0 ]                                                 # durable
}

# ── v2.58.2 hotfix regressions ──────────────────────────────────────────────
# Fix #1: the MANIFEST gets the same untracked-collision protection as the receipt.
@test "E2E hotfix: a DIFFERING untracked manifest is refused by ensure_manifest, not clobbered" {
  _repo r; mkdir -p r/.aid-o/plans r/.aid-lifecycle/manifests
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P860-x.md
  # a foreign untracked manifest already sits on disk (NOT ours)
  ( cd r && printf 'schema_version: aid-lifecycle-1.0\nplan_id: P860\n# USER HAND-CRAFTED\n' > .aid-lifecycle/manifests/P860.yaml )
  local before; before="$(sha256sum r/.aid-lifecycle/manifests/P860.yaml | cut -d' ' -f1)"
  run bash -c "cd r && source \"$LIB\" && aid_lifecycle_ensure_manifest P860 ."
  [ "$status" -ne 0 ]                                                 # refused, not overwritten
  [[ "$output" == *"differs from the canonical manifest"* ]]
  [ "$(sha256sum r/.aid-lifecycle/manifests/P860.yaml | cut -d' ' -f1)" = "$before" ]   # byte-identical (not clobbered)
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/manifests/P860.yaml"
  [ "$status" -ne 0 ]                                                 # nothing committed
}

# Fix #2: a receipt-commit failure on the last required EPIC must NOT report success.
@test "E2E hotfix: a receipt-commit failure makes record-delivery return non-zero (never a false success)" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P850-x.md
  ( cd r && source "$LIB" && aid_lifecycle_ensure_manifest P850 . )
  _merge_epic r E-850-1_1 accepted
  # git shim: fail ONLY the receipt commit-tree, let the manifest-binding commit succeed
  local realgit; realgit="$(command -v git)"
  mkdir -p "$TEST_DIR/binshim"
  cat > "$TEST_DIR/binshim/git" <<SHIM
#!/usr/bin/env bash
if [[ "\$1" == "commit-tree" && "\$*" == *"receipt"* ]]; then exit 1; fi
exec "$realgit" "\$@"
SHIM
  chmod +x "$TEST_DIR/binshim/git"
  run env PATH="$TEST_DIR/binshim:$PATH" "$FSM" plan-record-delivery E-850-1_1 r
  [ "$status" -ne 0 ]                                                 # NOT a false success
  [[ "$output" == *"receipt NOT committed"* ]]
  [ "$("$FSM" plan-state P850 r)" != "closed" ]                      # honestly not closed
}

# ── real scaffold path (runs the actual pipeline, not a grep) ────────────────
_mkplan() { # <root> <epic-declaration-body> [strict]
  mkdir -p "$1/.aid-o/plans"
  local strict=""; [[ "${3:-}" == "strict" ]] && strict=$'\nlifecycle_strict: true'
  cat > "$1/.aid-o/plans/P900-x.md" <<PLAN
---
id: P900
type: regular
risk: low${strict}
---
# Plan: P900

$2

### Step 1: backend — do alpha
**Files:**
- Create: \`src/a.py\`
PLAN
}

@test "E2E #1b: the REAL pipeline commits the manifest at scaffold for a valid plan" {
  _repo r; _mkplan r '**EPIC 1: alpha (Steps 1-1)**'
  run bash -c "cd r && \"$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh\" --plan .aid-o/plans/P900-x.md --queue-mode chain"
  # (generation may or may not fully complete in this minimal fixture; the scaffold
  #  step runs first) — the manifest must be a durable commit on target_branch.
  run bash -c "cd r && git cat-file -e main:.aid-lifecycle/manifests/P900.yaml && echo OK"
  [[ "$output" == *OK* ]]
}

@test "E2E scaffold FAIL-CLOSED: a lifecycle_strict plan with an ambiguous declaration aborts the real pipeline" {
  _repo r; _mkplan r '**EPIC 1 ambiguous no colon no backlog form**' strict
  run bash -c "cd r && \"$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh\" --plan .aid-o/plans/P900-x.md --queue-mode chain"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MUST have a durable"* ]]
  [ ! -d r/.aid-o/tasks ] || [ -z "$(ls r/.aid-o/tasks 2>/dev/null | grep E- || true)" ]
}

@test "E2E scaffold: a LEGACY (non-strict) ambiguous plan proceeds in loud audited migration (not fail-closed, not silent)" {
  _repo r; _mkplan r '**EPIC 1 ambiguous no colon**'
  run bash -c "cd r && \"$AID_PLUGIN_PATH/scripts/aid-auto-pipeline.sh\" --plan .aid-o/plans/P900-x.md --queue-mode chain"
  [[ "$output" != *"MUST have a durable"* ]]      # not fail-closed at the manifest step
  [[ "$output" == *"AUDITED migration"* ]]         # loud, never silent
  [ -f r/.aid-o/work/lifecycle-migration.log ]     # audit marker recorded
}

# ── entrypoint sanity: the advisory's command actually exists ────────────────
@test "E2E: aid-fsm.sh plan-reconcile (referenced by the init advisory) exists + runs" {
  _repo r; mkdir -p r/.aid-o/plans
  printf '**EPIC 1: a (Steps 1-1)**\n' > r/.aid-o/plans/P800-x.md
  run "$FSM" plan-reconcile P800 --dry-run r
  [ "$status" -eq 0 ]
  [[ "$output" == *"state:"* ]]
  # the advisory string and the dispatcher command agree
  grep -q 'aid-fsm.sh plan-reconcile' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
  grep -qE 'plan-reconcile\)' "$AID_PLUGIN_PATH/scripts/aid-fsm.sh"
}
