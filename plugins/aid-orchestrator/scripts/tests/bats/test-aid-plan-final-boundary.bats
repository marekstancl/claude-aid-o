#!/usr/bin/env bats
# aid-tier: t2
# test-aid-plan-final-boundary.bats — P068 "Plan-final release boundary"
# (EPIC E-068-1_2). THE single mandatory integration suite for this plan (see
# .aid-o/plans/P068-plan-final-release-boundary.md — this file is named and
# owned by the plan itself, not invented per-step). Every later step in this
# plan ADDS test blocks here rather than creating a sibling suite — keep new
# coverage inside the matching `# ─── <Command/Library> ───` describe-block
# below, adding a new block only for a genuinely new command under test.
#
# Step 1 seeds it with the boundary's opening half:
#   - aid-plan-fsm.sh plan-finalize --stage sync   (EPIC terminality + merge)
#   - aid-plan-fsm.sh plan-finalize --stage freeze (the immutable candidate)
#   - lib/aid-plan-manifest.sh's candidate freeze/clear pair (the atomic
#     candidate_sha + candidate_frozen_at write)
#   - aid-release.sh prepare-plan (version preparation, no tag, no sweep)
#
# Like test-aid-plan-release-boundary.bats, this suite creates a REAL Git
# repository per test. It is `# aid-tier: t2`, so it runs in the NIGHTLY
# portfolio and never on the merge path. It used to have a dedicated
# push-triggered CI job (`plan-final-tests`) and a DELEGATED exclusion in
# run-all-tests.sh; both were removed 2026-08-14 — a t2 suite blocking a merge
# contradicted the ecosystem test standard, and by then the job could not pass
# at all (199 min against a 35-minute limit).

load test-helpers.bash

# ─── IMP-505: fixtures are BUILT once per file and RESTORED per case ────────
#
# Measured before this change: 199 min for 261 cases (47% of the whole test
# portfolio), 46 s/case. The cost was never the number of production commands
# the cases run — the fast sibling suite runs twice as many — it was that 198
# cases replayed an entire plan lifecycle in their fixture. Per case:
# `_seed_closable` = 69 s, of which `_seed_merge_project` 42 s (`_bootstrap`
# 4 s + `_seed_plan_final_evidence` 14 s + 24 s of real sync/freeze/transitions)
# and `_merge` 13 s.
#
# So each distinct fixture is built ONCE (through the SAME builder as before —
# the builders stay the single source of truth and are not reimplemented) and
# every later case gets a byte copy of it.
#
# WHY A FIXED DIRECTORY. The built state contains ABSOLUTE paths, so a copy is
# only valid at the path it was built at (backlog IMP-505 option 3; options 1
# and 2 were `sed`-rewriting paths — silently breaks when a new path-bearing
# field appears — and one shared tree for the file, which destroys the per-case
# isolation this suite depends on). Hence a fixed live directory here instead of
# test-helpers' per-case `mktemp -d`, which in turn means this suite MUST run
# serially — guarded loudly in `_snap_setup_live`, never assumed.
#
# WHAT A COPY CANNOT CARRY (cross-model review, 2026-08-14): a filesystem
# snapshot restores no shell state — no exported env, no cwd, and none of bats'
# `run` globals. The seeds used to leave `$status`/`$output` set as a side
# effect (`_seed_closable` asserted its own `_merge` result), so a restore
# POISONS them: any case that silently leaned on the builder's leaked success
# now fails loudly instead of passing for the wrong reason.
_snap_root() { printf '%s' "$BATS_FILE_TMPDIR/snap"; }
_snap_live() { printf '%s' "$(_snap_root)/live"; }
_snap_tpl()  { printf '%s' "$(_snap_root)/tpl/$1"; }

# _snap_setup_live — test-helpers' setup_test_evidence_dir at a FIXED path.
# Deliberately a local twin rather than a change to the shared helper: every
# other suite keeps its per-case mktemp isolation.
_snap_setup_live() {
  if [[ "${BATS_NUMBER_OF_PARALLEL_JOBS:-1}" -ne 1 ]]; then
    echo "test-aid-plan-final-boundary.bats: fixed-path snapshot fixtures require serial bats (--jobs 1)." >&2
    echo "A template built for one job slot restored into another IS the absolute-path bug in a new form." >&2
    return 1
  fi
  export AID_TEST_MODE=1
  local live; live="$(_snap_live)"
  cd /
  rm -rf "$live"
  mkdir -p "$live"
  # Physical, canonical spelling: a path-bearing state file may hold either
  # spelling, and the template is only reusable at a byte-identical path.
  live="$(cd "$live" && pwd -P)"
  export TEST_TMPDIR="$live"
  export TEST_PROJECT_ROOT="$live/project"
  export TEST_EVIDENCE_DIR="$TEST_PROJECT_ROOT/.aid-o/work/evidence/E-test/R-test"
  mkdir -p "$TEST_EVIDENCE_DIR"
  cd "$TEST_PROJECT_ROOT"
  git init -q -b main 2>/dev/null || git init -q
  git config user.email "test@test.local"
  git config user.name "Test"
  echo "init" > .gitkeep
  git add .gitkeep
  git commit -q -m "initial"
}

# _snap_eligible — refuse to snapshot a tree carrying transient or
# path-bearing-elsewhere git state. Nothing here is "normalized": a `git gc` /
# `update-index --refresh` / `worktree prune` would paper over exactly the state
# a case might be asserting on.
_snap_eligible() {
  local g="$TEST_PROJECT_ROOT/.git"
  local lock
  for lock in index.lock HEAD.lock packed-refs.lock; do
    [[ -e "$g/$lock" ]] && { echo "_snap: refusing to snapshot, $lock present" >&2; return 1; }
  done
  # A linked worktree's admin files point at an EXTERNAL directory; copying only
  # the primary tree would produce a repo whose worktree registration lies.
  local wt_count
  wt_count="$(git -C "$TEST_PROJECT_ROOT" worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)"
  [[ "$wt_count" -le 1 ]] || { echo "_snap: refusing to snapshot, $wt_count linked worktrees registered" >&2; return 1; }
  return 0
}

# _SNAP_ENV_VARS — the env vars a builder sets or reads as a SIDE EFFECT, and
# which therefore (a) change what the builder produces, so they belong in the
# template key, and (b) are shell state a file copy cannot carry, so they are
# saved beside the template and restored with it. `_bootstrap` alone branches on
# two of them: AID_TEST_SEED_LIFECYCLE decides whether the git-tracked lifecycle
# manifest exists at all, AID_TEST_DECLARED_PLAN_MODE whether a declared mode is
# written. A template keyed without them would hand one fixture's tree to a case
# asking for the other — green, and testing the wrong plan.
_SNAP_ENV_VARS=(AID_TEST_SEED_LIFECYCLE AID_TEST_DECLARED_PLAN_MODE AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB)

# _snap_env_key — the current values of the above, as a key fragment.
_snap_env_key() {
  local v out=""
  for v in "${_SNAP_ENV_VARS[@]}"; do out+="${v}=${!v-<unset>};"; done
  printf '%s' "$out" | sha256sum | cut -c1-12
}

# _snap_env_save <file> / _snap_env_load <file> — carry those vars across the
# copy explicitly. `unset` is preserved as unset, never collapsed to empty.
_snap_env_save() {
  local v
  : > "$1"
  for v in "${_SNAP_ENV_VARS[@]}"; do
    if [[ -v $v ]]; then printf 'export %s=%q\n' "$v" "${!v}" >> "$1"
    else printf 'unset %s\n' "$v" >> "$1"; fi
  done
}
# Returns 1 when the sidecar is missing: the caller decides, and it refuses.
_snap_env_load() { [[ -f "$1" ]] || return 1; . "$1"; }

# _snap_contract — the shell state a copy cannot carry, re-established
# explicitly rather than inherited from whichever builder ran last.
_snap_contract() {
  export AID_TEST_MODE=1
  export TEST_TMPDIR TEST_PROJECT_ROOT TEST_EVIDENCE_DIR
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  cd "$TEST_PROJECT_ROOT"
  # A restore ran no command. Poison, do not merely clear: an EMPTY $output can
  # accidentally satisfy an assertion, a poisoned one cannot.
  status=97
  output='__SNAPSHOT_RESTORE_DID_NOT_RUN_A_COMMAND__'
  lines=("$output")
  BATS_RUN_COMMAND='__SNAPSHOT_RESTORE__'
}

# _snap_fixture <key> <builder> [builder args…] — restore fixture <key>,
# building it once (through the real builder, in the live tree) on first use.
# The builder path ends in the SAME poisoned contract as the restore path, so
# the first case in a file is not quietly privileged over the other 260.
# _SNAP_LAST_ACTION — "restore" or "build", set by every _snap_fixture call.
# Without it the equivalence tests below could not tell the two paths apart: a
# test that builds, wipes the live tree and calls the wrapper takes the BUILD
# branch whenever no template happens to exist yet, and then compares two fresh
# builds while appearing to compare a restore against a build. Cross-model
# review caught exactly that.
_SNAP_LAST_ACTION=""
_snap_fixture() {
  local key="$1"; shift
  key="${key}.$(_snap_env_key)"
  local tpl live; tpl="$(_snap_tpl "$key")"; live="$(_snap_live)"
  # A template DIRECTORY is not a template. Publication is atomic — built
  # aside, then moved into place with its env sidecar already written — so an
  # interrupted build can never leave a half-tree that the next case restores
  # as if it were complete. And every step of the restore is checked: `cp -a`
  # failing, or a missing `.env`, used to return success, poison the run state
  # and hand the case a partial world. Fail-open in a fixture is the same
  # disease as fail-open in a gate.
  if [[ -d "$tpl" ]]; then
    _SNAP_LAST_ACTION="restore"
    cd /
    rm -rf "$live"
    cp -a "$tpl" "$live" || { echo "_snap: restoring template $key failed" >&2; return 1; }
    [[ -f "${tpl}.env" ]] || { echo "_snap: template $key has no .env sidecar — refusing a partial restore" >&2; return 1; }
    _snap_env_load "${tpl}.env"
  else
    _SNAP_LAST_ACTION="build"
    "$@"
    _snap_eligible || return 1
    mkdir -p "$(dirname "$tpl")"
    local staging="${tpl}.staging.$$"
    rm -rf "$staging"
    cp -a "$live" "$staging" || { echo "_snap: staging template $key failed" >&2; return 1; }
    _snap_env_save "${tpl}.env"
    mv "$staging" "$tpl" || { echo "_snap: publishing template $key failed" >&2; return 1; }
  fi
  _snap_contract
}

# _snap_fingerprint — the fixture's SHAPE, for the builder-vs-restore
# equivalence test below.
#
# Deliberately not a byte comparison, and this is the honest reason rather than
# a convenience: a freshly built fixture can never be byte-identical to one
# built a minute earlier. Commit objects carry their author/committer time, so
# every commit SHA differs, and the manifest records a real `candidate_frozen_at`
# instant. Comparing bytes would therefore fail for a correct restore and prove
# nothing about a wrong one.
#
# So volatile values are MASKED and everything else must match exactly: which
# refs exist (by name), where HEAD points, the porcelain status, the worktree
# registration, and — for every file outside .git — its path and its
# SHA-masked, timestamp-masked content. That catches what actually goes wrong
# with a snapshot: a missing file, a state field that came out different, a
# branch that is not checked out, a dirty tree.
#
# .git is covered through refs/status/worktree rather than as a file list: its
# object names ARE the content-addressed SHAs that legitimately differ, so
# listing them would reintroduce the noise the masking removes.
_snap_mask() {
  sed -E -e 's/\b[0-9a-f]{64}\b/<SHA256>/g' \
         -e 's/\b[0-9a-f]{40}\b/<SHA1>/g' \
         -e 's/\b[0-9a-f]{7,12}\b/<SHORTSHA>/g' \
         -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<TS>/g'
}
_snap_fingerprint() {
  # Everything goes through the mask, REF NAMES INCLUDED: this suite names an
  # evidence ref after the commit it is bound to
  # (refs/heads/aid-evidence/P068/<sha>/<run>), so two correct builds differ
  # there for the same reason their commits do. The masked comparison still
  # catches a ref that is MISSING, renamed or pointing somewhere else.
  {
    # NAME **and** TARGET. Names alone would compare equal for a restore whose
    # evidence ref survived but points at the wrong commit — which is precisely
    # the claim the paragraph above makes, and could not keep with names alone.
    # The target is masked like every other sha, so two correct builds still
    # agree while a ref pointing somewhere ELSE relative to its own tree does not.
    git -C "$TEST_PROJECT_ROOT" for-each-ref --format='ref %(refname) -> %(objectname)'
    echo "head $(git -C "$TEST_PROJECT_ROOT" symbolic-ref -q HEAD || echo detached)"
    git -C "$TEST_PROJECT_ROOT" status --porcelain | sed 's/^/status /'
    git -C "$TEST_PROJECT_ROOT" worktree list --porcelain | grep '^worktree ' | sed "s|$TEST_PROJECT_ROOT|<ROOT>|"
    local f
    while IFS= read -r -d '' f; do
      printf 'file %s %s\n' "$f" "$(_snap_mask < "$f" | sha256sum | cut -d' ' -f1)"
    done < <(cd "$TEST_PROJECT_ROOT" && find . -path ./.git -prune -o -type f -print0 | sort -z)
  } | _snap_mask
}

setup() {
  _snap_setup_live
  AID_PLUGIN_PATH="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export AID_PLUGIN_PATH
  PLAN_STATE_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-state.sh"
  PLAN_MANIFEST_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-plan-manifest.sh"
  PLAN_FSM_CLI="$AID_PLUGIN_PATH/scripts/aid-plan-fsm.sh"
  RELEASE_CLI="$AID_PLUGIN_PATH/scripts/aid-release.sh"
  export PLAN_STATE_LIB PLAN_MANIFEST_LIB PLAN_FSM_CLI RELEASE_CLI

  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"

  # shellcheck disable=SC1090
  source "$PLAN_STATE_LIB"
  # shellcheck disable=SC1090
  source "$PLAN_MANIFEST_LIB"
  LIFECYCLE_LIB="$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
  export LIFECYCLE_LIB
  # shellcheck disable=SC1090
  source "$LIFECYCLE_LIB"
}

teardown() {
  teardown_test_evidence_dir
}

# ─── fixtures ────────────────────────────────────────────────────────────

PLAN_ID="P068"

# _manifest_field <plan_id> <field> — raw payload field, "null" when absent.
_manifest_field() {
  jq -r --arg f "$2" '.plan_boundary_manifest[$f]' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${1}/plan-boundary-manifest.json"
}

# _bootstrap <plan_id> — a plan branch + manifest + state file, built through
# the REAL library entry points (never a hand-written fixture manifest), so a
# drift between what the library writes and what these tests assume is caught
# by the bootstrap rather than hidden by it.
# _bootstrap — snapshot-backed (IMP-505): the builder below is unchanged and
# runs once per file; every later case restores its byte copy.
_bootstrap() { _snap_fixture "bootstrap${1:+:$1}" _bootstrap_build "$@"; }

_bootstrap_build() {
  local plan_id="${1:-$PLAN_ID}"
  # Mirror production: `.aid-o/work/` is gitignored, so branch switching never
  # deletes the plan state or the manifest out from under the CLI.
  # `.aid-o/reports/` is gitignored here for the same reason production
  # projects gitignore it: the human report projection is private. Step 6's
  # close-check reads that mode (report_storage: private/gitignored) and never
  # lets the Markdown projection alone make close pass.
  printf '.aid-o/work/\n.aid-o/reports/\n' > "$TEST_PROJECT_ROOT/.gitignore"
  git -C "$TEST_PROJECT_ROOT" add -- .gitignore
  git -C "$TEST_PROJECT_ROOT" commit -q -m "gitignore the runtime area"
  # P068 Step 5 (opt-in): the GIT-TRACKED lifecycle manifest the plan merge binds
  # deliveries into. It has to exist on the TARGET branch BEFORE the plan branch
  # is cut — a later commit on main would advance the target head past the one
  # the candidate is frozen against, which plan-merge-to-main correctly rejects
  # as a stale authorization. Built through the REAL entry point
  # (aid_lifecycle_ensure_manifest + its strict legacy EPIC parse), never a
  # hand-written fixture manifest.
  if [[ "${AID_TEST_SEED_LIFECYCLE:-0}" == "1" ]]; then
    mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
    # Success Criteria: --stage produce derives the acceptance evidence from them.
    printf '# %s\n\n**EPIC 1: the delivered one**\n\n**EPIC 2: the abandoned one**\n\n## Success Criteria\n\n- [ ] the delivered EPIC is merged\n' "$plan_id" \
      > "$TEST_PROJECT_ROOT/.aid-o/plans/${plan_id}-lifecycle.md"
    aid_lifecycle_ensure_manifest "$plan_id" "$TEST_PROJECT_ROOT" >/dev/null
    # The DECLARED mode, written durably while main is still the checked-out
    # branch and before any candidate freeze — a later write would advance the
    # target head past the frozen one and be rejected as a stale authorization.
    if [[ -n "${AID_TEST_DECLARED_PLAN_MODE:-}" ]]; then
      aid_lifecycle_set_plan_mode "$plan_id" "$AID_TEST_DECLARED_PLAN_MODE" "$TEST_PROJECT_ROOT" >/dev/null
    fi
  fi
  local base; base="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  git -C "$TEST_PROJECT_ROOT" branch "plan/${plan_id}" "$base"
  plan_state_init "$plan_id" "plan_branch" "plan/${plan_id}" "main"
  plan_manifest_init "$plan_id" "plan/${plan_id}" "main" "$base" "$base" "plan_branch"
}

# _add_epic <plan_id> <epic_id> — one epic_runs[] entry, lineage proven.
_add_epic() {
  local plan_id="$1" epic_id="$2"
  local base; base="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/${plan_id}")"
  local ev=".aid-o/work/evidence/${epic_id}/R-${epic_id}-1"
  plan_manifest_add_epic "$plan_id" "$epic_id" "R-${epic_id}-1" \
    "task/${epic_id}/main" "$base" "plan/${plan_id}" \
    "$ev" "proven"
  # P073 Step 15/18: a real EPIC run leaves a plan.json in its evidence dir,
  # and the freeze reads every one of them to compute the protected surface.
  # Without it the freeze correctly records protected_paths_complete:false and
  # review equivalence is unavailable — which is right, but it means this
  # fixture could never exercise the equivalence path at all.
  mkdir -p "$TEST_PROJECT_ROOT/$ev"
  jq -n --arg e "$epic_id" \
    '{schema_version:"aid-2.0", epic_id:$e,
      steps:[{step_id:"S1", allowed_paths:["epic-work.txt","scripts/**"]}]}' \
    > "$TEST_PROJECT_ROOT/$ev/plan.json"
}

# _commit_on <branch> <file> <text> — one real commit, HEAD restored.
_commit_on() {
  local branch="$1" file="$2" text="$3" orig
  orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$branch"
  printf '%s\n' "$text" > "$TEST_PROJECT_ROOT/$file"
  git -C "$TEST_PROJECT_ROOT" add -- "$file"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "$text"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# _finalize <plan_id> <stage> [extra...] — the CLI under test.
_finalize() {
  local plan_id="$1" stage="$2"; shift 2
  run bash "$PLAN_FSM_CLI" plan-finalize "$plan_id" --stage "$stage" \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# =============================================================================
# ─── plan-finalize --stage freeze, first half: the sync ───────────────────
# =============================================================================

# ─── AC3: sync refuses to proceed while any EPIC is pending or running,
#          NAMING it ────────────────────────────────────────────────────────
@test "AC3: the sync of --stage freeze refuses while an EPIC is still running, and names it" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"     # created as `running`

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"non-terminal EPICs"* ]]
  [[ "$output" == *"E-068-1_2"* ]]
  [[ "$output" == *"running"* ]]

  # Nothing moved and nothing was frozen.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "PLAN_SYNC" ] && [ "$output" != "PLAN_GATES" ]
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
}

@test "AC3: the sync of --stage freeze names a pending EPIC too (not only a running one)" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  # running → blocked is legal; blocked is equally non-terminal.
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "blocked"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"E-068-1_2"* ]]
  [[ "$output" == *"blocked"* ]]
}

@test "the sync of --stage freeze proceeds once every EPIC is terminal, and freezes the candidate (PLAN_GATES)" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  # A real merge commit is required for merged_to_plan; the plan branch head
  # is a legitimate commit to name here (this test is about sync, not about
  # re-proving epic-merge-to-plan's ancestry rules).
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "merged_to_plan" "$mc"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── Edge case: an abandoned EPIC with no recorded PM reason ──────────────
@test "the sync of --stage freeze refuses an abandoned EPIC that carries no recorded reason" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  # Set the status directly, WITHOUT going through epic-complete --reason —
  # i.e. exactly the undocumented abandonment this guard exists to catch.
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "abandoned"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"no recorded reason"* ]]
  [[ "$output" == *"E-068-1_2"* ]]
}

@test "the sync of --stage freeze accepts an abandoned EPIC once a terminal_reason is recorded" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "abandoned"
  plan_manifest_update "$PLAN_ID" \
    '(.plan_boundary_manifest.epic_runs = [.plan_boundary_manifest.epic_runs[] | if .epic_id == "E-068-1_2" then (.terminal_reason = "superseded by a different approach") else . end])'

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── The merge is a MERGE, not a rebase (roadmap resolved decision 4) ─────
@test "the sync of --stage freeze merges the target branch into the plan branch with --no-ff and preserves prior plan commits" {
  _bootstrap
  _commit_on "plan/$PLAN_ID" "plan-work.txt" "plan side work"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  _commit_on "main" "main-work.txt" "target side work"
  local target_head; target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  local plan_after; plan_after="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  [ "$plan_after" != "$plan_before" ]

  # A merge commit: two parents, and BOTH prior heads are ancestors — a rebase
  # would have rewritten (and orphaned) the plan-side commit.
  run git -C "$TEST_PROJECT_ROOT" rev-parse "${plan_after}^2"
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$plan_before" "$plan_after"
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$target_head" "$plan_after"
  [ "$status" -eq 0 ]

  # HEAD is back where the operator left it.
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]
}

@test "the sync of --stage freeze on a conflicting target transitions the plan to CONFLICT and exits 4" {
  _bootstrap
  _commit_on "plan/$PLAN_ID" "contested.txt" "plan version"
  _commit_on "main" "contested.txt" "target version"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 4 ]
  [[ "$output" == *"MERGE CONFLICT"* ]]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CONFLICT" ]

  # No merge left half-done, and HEAD is restored.
  [ ! -f "$TEST_PROJECT_ROOT/.git/MERGE_HEAD" ]
  run git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD
  [ "$output" = "main" ]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage freeze ────────────────────────
# =============================================================================

# ─── AC4: after freeze, both SHAs are exact 40-hex and a new immutable run
#          directory exists ────────────────────────────────────────────────
@test "AC4: --stage freeze records candidate_sha + target_branch_head_at_candidate_freeze as exact 40-hex and creates the run directory" {
  _bootstrap

  local plan_head target_head
  plan_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  run _manifest_field "$PLAN_ID" candidate_sha
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
  [ "$output" = "$plan_head" ]

  run _manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
  [ "$output" = "$target_head" ]

  run _manifest_field "$PLAN_ID" plan_final_run_id
  [ "$output" = "R-${PLAN_ID}-final-1" ]
  run _manifest_field "$PLAN_ID" plan_final_evidence_dir
  [ "$output" = ".aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-1" ]
  [ -d "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-1" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
  run _manifest_field "$PLAN_ID" plan_state
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC5: the SAME freeze write records candidate_frozen_at, atomically with
#          candidate_sha; the manifest is never valid with one set and the
#          other absent, in EITHER direction ────────────────────────────────
@test "AC5: the freeze write records candidate_frozen_at as an RFC 3339 UTC instant in the RUNTIME manifest" {
  _bootstrap
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  run _manifest_field "$PLAN_ID" candidate_frozen_at
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]

  # It lives in the RUNTIME plan-boundary manifest, deliberately NOT in the
  # .aid-lifecycle manifest (a different artifact with its own write path,
  # which cannot establish atomicity with the candidate write).
  if [[ -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml" ]]; then
    run grep -c "candidate_frozen_at" "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
    [ "$output" = "0" ]
  fi
}

@test "AC5: a manifest with candidate_sha set but candidate_frozen_at null is REJECTED by the validator" {
  _bootstrap
  # Reach past the public mutator on purpose: the invariant must hold against
  # any writer, including a hand edit or a future careless caller.
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  local head; head="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  jq --arg h "$head" '.plan_boundary_manifest.candidate_sha = $h
                      | .plan_boundary_manifest.candidate_frozen_at = null
                      | .plan_boundary_manifest.plan_state = "PLAN_GATES"' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"

  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_sha and candidate_frozen_at must be null/non-null together"* ]]
}

@test "AC5: a manifest with candidate_frozen_at set but candidate_sha null is REJECTED too (both directions)" {
  _bootstrap
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  jq '.plan_boundary_manifest.candidate_frozen_at = "2026-07-25T10:00:00Z"
      | .plan_boundary_manifest.candidate_sha = null' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"

  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_sha and candidate_frozen_at must be null/non-null together"* ]]
}

@test "AC5: a non-UTC / malformed candidate_frozen_at is refused by the writer AND by the invariant" {
  _bootstrap
  local head; head="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  # Writer: a local-offset instant is not accepted.
  run plan_manifest_freeze_candidate "$PLAN_ID" "$head" "$head" "R-x-1" \
    ".aid-o/work/evidence/${PLAN_ID}/R-x-1" "2026-07-25T10:00:00+02:00"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RFC 3339 UTC instant"* ]]
  # And nothing was written.
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]

  # Invariant: the same value planted directly is rejected on validate.
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  jq --arg h "$head" '.plan_boundary_manifest.candidate_sha = $h
                      | .plan_boundary_manifest.candidate_frozen_at = "2026-07-25"
                      | .plan_boundary_manifest.plan_state = "PLAN_GATES"' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate_frozen_at"* ]]
}

# ─── AC1 (freeze/invalidation): a candidate change after freeze goes to
#          PLAN_FIX and clears ALL FOUR plan-final fields (plus the freeze
#          time, which is cleared with candidate_sha) ────────────────────────
@test "AC1: a candidate change after freeze mints a new attempt in the same call and records what the fix touched" {
  _bootstrap
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local first_candidate; first_candidate="$(_manifest_field "$PLAN_ID" candidate_sha)"
  [[ "$first_candidate" =~ ^[0-9a-f]{40}$ ]]

  # The candidate CHANGES: the plan branch moves off the frozen commit.
  _commit_on "plan/$PLAN_ID" "late.txt" "a commit after the freeze"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")" ]
  [ "$(_manifest_field "$PLAN_ID" plan_final_run_id)" = "R-${PLAN_ID}-final-2" ]
  local fc; fc="$(_run_dir)/fix-class.json"
  [ "$(jq -r .previous_candidate "$fc")" = "$first_candidate" ]
  [ "$(jq -r .class "$fc")" = delivery ]
  [ "$(jq -c .invalidated_feeds "$fc")" = '["diff"]' ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

@test "AC5: an invalidation clears candidate_sha and candidate_frozen_at TOGETHER — never one without the other" {
  _bootstrap
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  # Walk to AWAITING_PM — the state the stale-authorization resync is
  # discovered from, and the one PLAN_SYNC is legally reachable from.
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_REVIEW"
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "AWAITING_PM"

  # plan_final_invalidate lives in the CLI script, so it is sourced into a
  # subshell rather than into this bats process (the CLI sets `set -uo
  # pipefail`, which must not leak into the rest of the suite). Sourcing is
  # safe: the script only runs main() when executed directly.
  run bash -c 'source "$1"; plan_final_invalidate "$2" "$3" "$4"' \
    _ "$PLAN_FSM_CLI" "$PLAN_ID" "stale_pm_authorization" "PLAN_SYNC"
  [ "$status" -eq 0 ]

  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
  run _manifest_field "$PLAN_ID" candidate_frozen_at
  [ "$output" = "null" ]
  # The target state is a PARAMETER: the same clearing serves the resync path.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
  run _manifest_field "$PLAN_ID" candidate_invalidation_reason
  [ "$output" = "stale_pm_authorization" ]

  # And the manifest is still fully valid after the clear.
  run plan_manifest_validate "$PLAN_ID"
  [ "$status" -eq 0 ]
}

@test "plan_final_invalidate refuses an illegal target state and clears NOTHING" {
  _bootstrap
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local sha1; sha1="$(_manifest_field "$PLAN_ID" candidate_sha)"

  # PLAN_GATES → PLAN_SYNC is not a legal edge. Refusing (rather than writing
  # the manifest and silently failing the state transition) is what keeps the
  # two records of the same fact from diverging.
  run bash -c 'source "$1"; plan_final_invalidate "$2" "$3" "$4"' \
    _ "$PLAN_FSM_CLI" "$PLAN_ID" "wrong_target" "PLAN_SYNC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a legal plan-state transition"* ]]

  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$sha1" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

@test "a refreeze rewrites candidate_sha and candidate_frozen_at TOGETHER (both change, neither is stale)" {
  _bootstrap
  _finalize "$PLAN_ID" freeze --frozen-at "2026-07-25T10:00:00Z"
  [ "$status" -eq 0 ]
  local sha1 at1
  sha1="$(_manifest_field "$PLAN_ID" candidate_sha)"
  at1="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  [ "$at1" = "2026-07-25T10:00:00Z" ]

  _commit_on "plan/$PLAN_ID" "late.txt" "moves the candidate"
  _finalize "$PLAN_ID" freeze --frozen-at "2026-07-25T11:00:00Z"
  [ "$status" -eq 0 ]

  local sha2 at2
  sha2="$(_manifest_field "$PLAN_ID" candidate_sha)"
  at2="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  [ "$sha2" != "$sha1" ]
  [ "$at2" != "$at1" ]
  [ "$at2" = "2026-07-25T11:00:00Z" ]
}

# ─── AC7: a second freeze creates R-<plan_id>-final-2 and leaves final-1
#          byte-identical ──────────────────────────────────────────────────
@test "AC7: a second freeze allocates R-<plan_id>-final-2 and leaves R-<plan_id>-final-1 byte-identical" {
  _bootstrap
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  local ev="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}"
  [ -d "$ev/R-${PLAN_ID}-final-1" ]
  printf 'attempt one evidence\n' > "$ev/R-${PLAN_ID}-final-1/report.txt"
  local before; before="$(sha256sum "$ev/R-${PLAN_ID}-final-1/report.txt" | awk '{print $1}')"

  _commit_on "plan/$PLAN_ID" "fix.txt" "the review fix"
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  [ -d "$ev/R-${PLAN_ID}-final-2" ]
  run _manifest_field "$PLAN_ID" plan_final_run_id
  [ "$output" = "R-${PLAN_ID}-final-2" ]

  # Attempt 1 is untouched — never deleted, never overwritten.
  [ -f "$ev/R-${PLAN_ID}-final-1/report.txt" ]
  local after; after="$(sha256sum "$ev/R-${PLAN_ID}-final-1/report.txt" | awk '{print $1}')"
  [ "$after" = "$before" ]
}

# ─── AC8: a target branch that advanced is merged in before the freeze ─────
@test "AC8: freeze merges a target branch that advanced, so the candidate contains the hotfix" {
  _bootstrap
  _commit_on "main" "hotfix.txt" "an urgent hotfix"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" "$cand"
  [ "$status" -eq 0 ]
  [ "$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" ]
}

@test "--stage freeze refuses a dirty worktree, so a half-applied prepare-plan can never be frozen over" {
  _bootstrap

  # Simulate prepare-plan having written one version file and then failed.
  printf 'half-written\n' > "$TEST_PROJECT_ROOT/.gitkeep"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes present"* ]]
  run _manifest_field "$PLAN_ID" candidate_sha
  [ "$output" = "null" ]
}

@test "--stage freeze re-run at the SAME plan head is an idempotent no-op — no second candidate, no second run dir" {
  _bootstrap
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  local sha1 at1
  sha1="$(_manifest_field "$PLAN_ID" candidate_sha)"
  at1="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$sha1" ]
  [ "$(_manifest_field "$PLAN_ID" candidate_frozen_at)" = "$at1" ]
  [ ! -d "$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}/R-${PLAN_ID}-final-2" ]
}

# =============================================================================
# ─── aid-release.sh prepare-plan ─────────────────────────────────────────
# =============================================================================

# _seed_version_project — a minimal but REAL version registry: a CHANGELOG,
# a plugin.json and .aid-o/config/project.yaml `versioning.files[]`, all
# committed on the plan branch.
_seed_version_project() {
  local plan_id="${1:-$PLAN_ID}"
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${plan_id}"

  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_PROJECT_ROOT/pkg"
  cat > "$TEST_PROJECT_ROOT/CHANGELOG.md" <<'MD'
# Changelog

All notable changes.

## [1.2.3] — 2026-07-01

### Added

- Something.
MD
  printf '{\n  "version": "1.2.3"\n}\n' > "$TEST_PROJECT_ROOT/pkg/plugin.json"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/project.yaml" <<'YML'
versioning:
  files:
    - path: pkg/plugin.json
      type: json
      field: version
    - path: CHANGELOG.md
      type: changelog
YML
  printf 'untouched\n' > "$TEST_PROJECT_ROOT/unrelated.txt"
  # Explicit paths, never `git add -A`: `.aid-o/work/` is the gitignored
  # runtime area in production, and committing it here would delete the plan
  # state and the manifest from the worktree on the next `git checkout main`.
  git -C "$TEST_PROJECT_ROOT" add -- CHANGELOG.md pkg/plugin.json \
    .aid-o/config/project.yaml unrelated.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "seed version registry"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# _prepare <plan_id> [extra...] — run prepare-plan ON the plan branch.
_prepare() {
  local plan_id="$1"; shift
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${plan_id}"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$plan_id" --bump patch \
    --plan-branch "plan/${plan_id}" --project-root "$TEST_PROJECT_ROOT" "$@"
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig" || true
}

# ─── AC6: tag-once — prepare-plan commits the version edits and creates NO
#          tag; tagging happens once, later, at merge time ──────────────────
@test "AC6: prepare-plan commits the version edits on the plan branch and creates NO tag" {
  _bootstrap
  _seed_version_project

  local tags_before; tags_before="$(git -C "$TEST_PROJECT_ROOT" tag | wc -l)"
  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]

  # The commit exists on the plan branch, with the contracted message.
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s "plan/$PLAN_ID"
  [ "$output" = "release: prepare v1.2.4 for ${PLAN_ID}" ]

  # No tag was created — this is the tag-once guarantee.
  local tags_after; tags_after="$(git -C "$TEST_PROJECT_ROOT" tag | wc -l)"
  [ "$tags_after" -eq "$tags_before" ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse -q --verify "refs/tags/v1.2.4"
  [ "$status" -ne 0 ]

  # And the version files really moved.
  run git -C "$TEST_PROJECT_ROOT" show "plan/${PLAN_ID}:pkg/plugin.json"
  [[ "$output" == *"1.2.4"* ]]
}

@test "AC6: prepare-plan stages ONLY the version files — an unrelated modification is refused, never swept in" {
  _bootstrap
  _seed_version_project

  # Dirt in the worktree that the legacy path's `git add -u` would have
  # folded into the release commit.
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  printf 'accidental edit\n' > "$TEST_PROJECT_ROOT/unrelated.txt"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump patch \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refuses to run with modified tracked files"* ]]
  [[ "$output" == *"unrelated.txt"* ]]

  # No commit was made.
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s
  [ "$output" = "seed version registry" ]
  git -C "$TEST_PROJECT_ROOT" checkout -q -- unrelated.txt
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

@test "AC6: prepare-plan is idempotent under crash-resume — a second run reuses the existing commit and does not bump again" {
  _bootstrap
  _seed_version_project

  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]
  local head1; head1="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already prepared"* ]]
  local head2; head2="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  [ "$head2" = "$head1" ]

  # Still 1.2.4 — a naive re-run would have produced 1.2.5.
  run git -C "$TEST_PROJECT_ROOT" show "plan/${PLAN_ID}:pkg/plugin.json"
  [[ "$output" == *"1.2.4"* ]]
  [[ "$output" != *"1.2.5"* ]]
}

@test "prepare-plan refuses to run anywhere but on the named plan branch (it never moves HEAD for you)" {
  _bootstrap
  _seed_version_project
  cd "$TEST_PROJECT_ROOT"   # still on main
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump patch \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must run on plan/${PLAN_ID}"* ]]
}

# ─── Edge case: the bump resolves to "no bump" ────────────────────────────
@test "prepare-plan with --bump auto refuses a plan whose commits carry no type (step commits), naming the explicit bump" {
  _bootstrap
  _seed_version_project
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  git -C "$TEST_PROJECT_ROOT" tag -a "v1.2.3" -m "Release v1.2.3"
  printf 'x\n' > "$TEST_PROJECT_ROOT/cmd.txt"
  git -C "$TEST_PROJECT_ROOT" add cmd.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "step 1: the new command"
  local head_before; head_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump auto \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"carry no conventional type"* && "$output" == *"next: "*"--bump minor|patch"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)" = "$head_before" ]
}

@test "prepare-plan with --bump auto and only chore/docs commits makes NO commit and exits 0" {
  _bootstrap
  _seed_version_project

  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  git -C "$TEST_PROJECT_ROOT" tag -a "v1.2.3" -m "Release v1.2.3"
  printf 'docs\n' > "$TEST_PROJECT_ROOT/docs.txt"
  git -C "$TEST_PROJECT_ROOT" add docs.txt
  git -C "$TEST_PROJECT_ROOT" commit -q -m "docs: a documentation-only change"
  local head_before; head_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"

  cd "$TEST_PROJECT_ROOT"
  run bash "$RELEASE_CLI" prepare-plan "$PLAN_ID" --bump auto \
    --plan-branch "plan/$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no version bump needed"* ]]

  # No commit — the candidate is simply the current plan head.
  local head_after; head_after="$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD)"
  [ "$head_after" = "$head_before" ]
  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# ─── Regression: the LEGACY entry point is unchanged by the restructure ────
@test "regression: the legacy aid-release.sh <bump> entry point still works exactly as before" {
  _bootstrap
  _seed_version_project
  local orig; orig="$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  cd "$TEST_PROJECT_ROOT"

  # --dry-run: reports the bump, writes nothing.
  run bash "$RELEASE_CLI" patch --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bumping: 1.2.3 → 1.2.4 (patch)"* ]]
  [[ "$output" == *"[DRY RUN]"* ]]
  run git -C "$TEST_PROJECT_ROOT" status --porcelain
  [ -z "$output" ]

  # A bad bump type is still rejected with the original message.
  run bash "$RELEASE_CLI" nonsense
  [ "$status" -eq 1 ]
  [[ "$output" == *"bump type must be auto|patch|minor|major"* ]]

  # The real legacy run still commits AND tags (unlike prepare-plan).
  run bash "$RELEASE_CLI" patch
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" rev-parse -q --verify "refs/tags/v1.2.4"
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" log -1 --format=%s
  [[ "$output" == "release: v1.2.4"* ]]

  git -C "$TEST_PROJECT_ROOT" checkout -q "$orig"
}

# =============================================================================
# ─── the order: prepare-plan, then freeze (which syncs first) ───────────
# =============================================================================

@test "the frozen candidate CONTAINS the version commit — prepare, then freeze" {
  _bootstrap
  _seed_version_project

  # prepare-plan runs BEFORE the freeze — it never needs a candidate_sha that
  # does not exist yet.
  _prepare "$PLAN_ID"
  [ "$status" -eq 0 ]
  local prepare_commit; prepare_commit="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]

  # The candidate IS the prepare commit: the release metadata is already
  # inside the thing that will be reviewed, so nothing must be committed once
  # the reviews start.
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  [ "$cand" = "$prepare_commit" ]
  run git -C "$TEST_PROJECT_ROOT" show "${cand}:pkg/plugin.json"
  [[ "$output" == *"1.2.4"* ]]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-finalize --stage gates (Step 2) ────────────────
# =============================================================================
#
# AC2 — exactly ONE plan-final gate profile run against the frozen candidate,
# with a gates_report.json that PROVES no required gate was excluded, no broad
# suite ran twice, plan_diff really evaluated the plan, and no quarantined gate
# came back green.
#
# The fixture execution.yaml below is deliberately a MINIATURE of the real one
# (a required gate, a quarantined required gate, a non-quarantined
# `shell_pipeline_smoke`, `plan_diff` with the exit-2 Fast Mode convention, and
# `docs_updated`) — same shapes, sub-second commands. The gate ids that the
# stage treats specially (`plan_diff`, `shell_pipeline_smoke`) keep their real
# names; everything else is generic on purpose, so the test proves the
# MECHANISM rather than one hard-coded gate list.

# _write_exec_yaml [substitute_include_override]
#   Writes .aid-o/config/execution.yaml into the test project. When the first
#   argument is given it REPLACES the release_quarantine include[] block, so a
#   test can prove that a substitute which drops a non-quarantined release gate
#   is refused.
_write_exec_yaml() {
  local sub_include="${1:-}"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml" <<'YAML'
version: '1.0'
gates:
  bats_fsm:
    command: "true"
    required: true
    timeout_seconds: 30
    max_retries: 0
  bats_all:
    quarantine:
      enabled: true
      authorized_by: "PM test"
      tracked_by: "P066"
      original_command: "bats tests/"
    command: "echo QUARANTINED >&2; exit 86"
    required: true
    timeout_seconds: 10
    max_retries: 0
  shell_pipeline_smoke:
    command: "true"
    required: false
    timeout_seconds: 30
    max_retries: 0
  plan_diff:
    command: "echo '{plan_path}' '{base_commit}' > .aid-o/work/plan_diff_args.txt; test '{plan_path}' != 'null' && test -f '{plan_path}' && git rev-parse --verify --quiet {base_commit} >/dev/null || exit 2"
    required: false
    pass_criteria: "exit 0 (all present) or exit 2 (Fast Mode graceful skip)"
    timeout_seconds: 30
    max_retries: 0
  docs_updated:
    command: "true"
    required: false
    timeout_seconds: 30
    max_retries: 0
gate_profiles:
  release:
    include:
      - bats_fsm
      - bats_all
      - shell_pipeline_smoke
      - plan_diff
      - docs_updated
  release_quarantine:
    include:
      - bats_fsm
      - shell_pipeline_smoke
      - plan_diff
      - docs_updated
YAML
  if [[ -n "$sub_include" ]]; then
    # Replace everything from the release_quarantine include marker onward.
    local f="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
    local keep; keep="$(awk '/^  release_quarantine:/{exit} {print}' "$f")"
    { printf '%s\n' "$keep"; printf '  release_quarantine:\n    include:\n'; printf '%s' "$sub_include"; } > "$f"
  fi
}

# _seed_gates_project — a plan branch whose candidate carries the plan file the
# gates evaluate, plus a gitignored runtime area.
# _seed_gates_project — snapshot-backed (IMP-505): the builder below is unchanged and
# runs once per file; every later case restores its byte copy.
_seed_gates_project() { _snap_fixture "gates_project${1:+:$1}" _seed_gates_project_build "$@"; }

_seed_gates_project_build() {
  _bootstrap
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# %s\n\n## Acceptance Criteria\n- [ ] something\n' "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  git -C "$TEST_PROJECT_ROOT" add -- ".aid-o/plans/${PLAN_ID}-test-plan.md"
  git -C "$TEST_PROJECT_ROOT" commit -q -m "the plan file"
  git -C "$TEST_PROJECT_ROOT" branch -f "plan/${PLAN_ID}" main
  _finalize "$PLAN_ID" freeze
}

# _run_dir — the frozen candidate's plan-final evidence directory (absolute).
_run_dir() {
  printf '%s/%s' "$TEST_PROJECT_ROOT" "$(_manifest_field "$PLAN_ID" plan_final_evidence_dir)"
}

# _write_receipt <gate_id> [head_override] [exit_code] [failed]
#   A valid IMP-269-shaped targeted-run receipt (command_sha256 == sha256(cmd),
#   log_sha256 == sha256 of a real in-repo log) bound to the frozen candidate.
#   Echoes the receipt path.
_write_receipt() {
  local gate="$1" head="${2:-}" ec="${3:-0}" failed="${4:-0}"
  local dir; dir="$(_run_dir)/gates"
  mkdir -p "$dir"
  [[ -z "$head" ]] && head="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local cmd="bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-final-boundary.bats"
  printf 'ok 1 targeted substitute\n' > "$dir/${gate}-substitute.log"
  local csha lsha
  csha="$(printf '%s' "$cmd" | sha256sum | cut -d' ' -f1)"
  lsha="$(sha256sum "$dir/${gate}-substitute.log" | awk '{print $1}')"
  jq -nc --arg g "$gate" --arg c "$cmd" --arg cs "$csha" --arg h "$head" \
         --arg l "${gate}-substitute.log" --arg ls "$lsha" \
         --argjson ec "$ec" --argjson failed "$failed" \
    '{gate_id:$g, command:$c, command_sha256:$cs, head_sha:$h, log:$l,
      log_sha256:$ls, exit_code:$ec, passed:1, failed:$failed}' \
    > "$dir/${gate}-substitute.receipt.json"
  printf '%s' "$dir/${gate}-substitute.receipt.json"
}

# _gates [extra args...] — the stage under test.
_gates() {
  run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage gates \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# _report — the plan-final gates_report.json path.
_report() { printf '%s/gates_report.json' "$(_run_dir)"; }

# ─── AC2.1 + AC2.5: the resolved release-derived profile, head_sha ==
#     candidate, and NO non-quarantined release gate dropped ────────────────
@test "AC2: the plan-final report carries the release-derived profile, the candidate head, and every non-quarantined release gate" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run jq -r '.profile' "$(_report)"
  [ "$output" = "release_quarantine" ]
  run jq -r '.revision.head_sha' "$(_report)"
  [ "$output" = "$cand" ]
  run jq -r '.overall' "$(_report)"
  [ "$output" = "pass" ]

  # Every non-quarantined release gate has a REAL result — notably
  # shell_pipeline_smoke, which the EPIC-scoped bats_all_quarantine profile omits.
  local g
  for g in bats_fsm shell_pipeline_smoke plan_diff docs_updated; do
    run jq -r --arg g "$g" '.gates[$g].result' "$(_report)"
    [ "$output" = "pass" ]
  done

  # ...and the stage transitioned PLAN_GATES -> PLAN_REVIEW.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_REVIEW" ]
}

# ─── AC2.7: plan_diff runs FOR REAL — not `--plan null`, not the exit-2 skip ─
@test "AC2: plan_diff evaluates the real plan file and the candidate range (never the Fast Mode exit-2 skip)" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  # `pass`, not `skip`: a skip is what an exit-2 `--plan null` would produce.
  run jq -r '.gates.plan_diff.result' "$(_report)"
  [ "$output" = "pass" ]
  run jq -r '.gates.plan_diff.exit_code' "$(_report)"
  [ "$output" = "0" ]
  # The gate SAW the real plan file and the real base commit — recorded by the
  # gate command itself, i.e. AFTER token substitution (the report's
  # _command_log keeps the raw, pre-substitution command by design).
  local base; base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  run cat "$TEST_PROJECT_ROOT/.aid-o/work/plan_diff_args.txt"
  [[ "$output" == *"${PLAN_ID}-test-plan.md"* ]]
  [[ "$output" == *"$base"* ]]
  [[ "$output" != *"null"* ]]
}

# ─── AC2.7 (negative): without the new flags the SAME gate is vacuous ───────
# This is the finding the C0 cross-provider review made, pinned as a test: with
# no --base-commit/--plan-path and no --state-file, plan_diff resolves to
# `--plan null`, exits 2, and execution.yaml's pass_criteria ACCEPTS it. The
# stage must never be able to reach that state.
@test "AC2: a plan-final gate run WITHOUT --plan-path degrades plan_diff to the accepted exit-2 skip (the vacuity the flags close)" {
  _seed_gates_project
  _write_exec_yaml
  local rd; rd="$(_run_dir)"
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  run bash -c "cd '$TEST_PROJECT_ROOT' && '$AID_PLUGIN_PATH/scripts/aid-run-gates.sh' run-all \
      '$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml' '$PLAN_ID' 'R-vacuous' \
      '$rd/vacuous-timeline.jsonl' --report-file '$rd/vacuous.json' \
      --profile release_quarantine"
  run jq -r '.gates.plan_diff.result' "$rd/vacuous.json"
  [ "$output" = "skip" ]
  run jq -r '.gates.plan_diff.exit_code' "$rd/vacuous.json"
  [ "$output" = "2" ]
  # The gate literally received the string "null" as its plan.
  run cat "$TEST_PROJECT_ROOT/.aid-o/work/plan_diff_args.txt"
  [[ "$output" == "null "* ]]
}

# ─── AC2.9: existing EPIC-scoped callers are unaffected when the flags are
#     absent — the state file still supplies both tokens ────────────────────
@test "AC2: --base-commit/--plan-path are additive — omitted, the runner still reads the state file" {
  _seed_gates_project
  _write_exec_yaml
  local rd; rd="$(_run_dir)"
  local base; base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  local plan="$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-test-plan.md"
  cat > "$rd/fsm-state.yaml" <<EOF
state: GATES
base_commit: $base
plan_path: $plan
EOF
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  run bash -c "cd '$TEST_PROJECT_ROOT' && '$AID_PLUGIN_PATH/scripts/aid-run-gates.sh' run-all \
      '$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml' '$PLAN_ID' 'R-legacy' \
      '$rd/legacy-timeline.jsonl' --state-file '$rd/fsm-state.yaml' \
      --report-file '$rd/legacy.json' --profile release_quarantine"
  run jq -r '.gates.plan_diff.result' "$rd/legacy.json"
  [ "$output" = "pass" ]
  run cat "$TEST_PROJECT_ROOT/.aid-o/work/plan_diff_args.txt"
  [[ "$output" == *"${PLAN_ID}-test-plan.md"* ]]
  [[ "$output" == *"$base"* ]]
}

# ─── AC2.3 + AC2.4: the quarantined gate is never green, and is satisfied
#     ONLY by a matching, candidate-bound, genuinely-green substitute ───────
@test "AC2: the quarantined gate is excluded, never 'pass', and carries a bound quarantine_substitutes[] entry" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"

  run jq -r '.gates.bats_all.result // "profile_excluded"' "$(_report)"
  [ "$output" != "pass" ]
  run jq -r '.excluded_gates | index("bats_all") != null' "$(_report)"
  [ "$output" = "true" ]

  run jq -r '.quarantine_substitutes | length' "$(_report)"
  [ "$output" = "1" ]
  run jq -r '.quarantine_substitutes[0].gate_id' "$(_report)"
  [ "$output" = "bats_all" ]
  run jq -r '.quarantine_substitutes[0].targeted_substitute' "$(_report)"
  [ "$output" = "accepted" ]
  run jq -r '.quarantine_substitutes[0].head_sha' "$(_report)"
  [ "$output" = "$cand" ]
  run jq -r '.quarantine_substitutes[0].base_sha' "$(_report)"
  [ "$output" = "$base" ]
  run jq -e '.quarantine_substitutes[0]
             | (.receipt_sha256 | test("^sha256:[0-9a-f]{64}$"))
               and (.command_sha256 | test("^sha256:[0-9a-f]{64}$"))
               and (.receipt_path | length > 0)
               and (.substitute_scope | length > 0)
               and .exit_code == 0 and .failed == 0' "$(_report)"
  [ "$status" -eq 0 ]

  # receipt_sha256 is the SEALED hash of the receipt file itself.
  local actual; actual="$(sha256sum "$receipt" | awk '{print $1}')"
  run jq -r '.quarantine_substitutes[0].receipt_sha256' "$(_report)"
  [ "$output" = "sha256:${actual}" ]
}

# ─── AC2.4 (negative): no receipt at all — a quarantined gate is NOT satisfied
#     by simply being excluded, and a waiver alone would not help either ────
@test "AC2: a quarantined gate with NO substitute receipt fails the stage and leaves the plan in PLAN_GATES" {
  _seed_gates_project
  _write_exec_yaml

  _gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"no targeted-substitute receipt was supplied"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.4 (negative): a receipt for a DIFFERENT gate never satisfies this one ─
@test "AC2: a substitute receipt whose gate_id does not match is rejected (one receipt cannot satisfy another gate)" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_fsm)"   # wrong gate_id inside

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"one receipt can never satisfy a different gate"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.4 (negative): head_sha != candidate_sha is rejected ────────────────
@test "AC2: a substitute receipt bound to any head other than the frozen candidate is rejected" {
  _seed_gates_project
  _write_exec_yaml
  local other; other="$(git -C "$TEST_PROJECT_ROOT" rev-parse main~1)"
  local receipt; receipt="$(_write_receipt bats_all "$other")"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not bound to the frozen candidate"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.4 (negative): a RED substitute never stands in for a broad gate ────
@test "AC2: a substitute receipt with a non-zero exit_code or failed>0 is rejected" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all "" 1 2)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a passing run"* ]]
}

# ─── AC2.4 (negative): a tampered receipt (command_sha256 no longer of
#     .command) is rejected — the fingerprint is not decorative ─────────────
@test "AC2: a substitute receipt whose command_sha256 is not sha256(.command) is rejected" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"
  jq '.command = "echo something else entirely"' "$receipt" > "${receipt}.t" && mv "${receipt}.t" "$receipt"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"command_sha256 is not sha256(.command)"* ]]
}

# ─── AC2.5: the substitute profile MUST be release-derived — a profile that
#     drops a non-quarantined release gate is refused BEFORE any gate runs ──
@test "AC2: a substitute profile that drops a non-quarantined release gate (shell_pipeline_smoke) is refused" {
  _seed_gates_project
  # Exactly the bats_all_quarantine shape: release minus bats_all AND minus
  # shell_pipeline_smoke. Correct-looking, silently one gate short.
  _write_exec_yaml "$(printf '      - bats_fsm\n      - plan_diff\n      - docs_updated\n')"
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not 'release' minus the quarantined gate"* ]]
  [[ "$output" == *"shell_pipeline_smoke"* ]]
  # Nothing ran: no report was written.
  [ ! -f "$(_report)" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── AC2.6: EXACTLY ONE gate_runner_start — no second broad run ────────────
@test "AC2: exactly one gate_runner_start event exists for the plan-final run" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]

  run grep -c '"event":"gate_runner_start"' "$(_run_dir)/timeline.jsonl"
  [ "$output" = "1" ]

  # A resume re-reads the passing report and completes ONLY the transition —
  # it never mints a second broad run.
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "PLAN_GATES" >/dev/null 2>&1 || \
    plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "PLAN_FIX" >/dev/null 2>&1
  _gates --substitute-receipt "bats_all=${receipt}"
  run grep -c '"event":"gate_runner_start"' "$(_run_dir)/timeline.jsonl"
  [ "$output" = "1" ]
}

# ─── AC2.8: a required gate reporting `skip` fails the stage ───────────────
#
# This USED to be one test that gave a required gate a null command and expected
# the stage to refuse with "never satisfied by a skip". It had been red on main
# for days, unnoticed because this suite's dedicated CI job timed out before
# finishing and its nightly never completed either. The reason it is red is not
# a regression: aid-run-gates.sh now refuses a profile-included gate with NO
# command EARLIER, as a configuration error — so the null-command route can no
# longer reach the skip assertion at all, and the old test was asserting a
# message that its own setup made unreachable.
#
# Both behaviours are real and both are worth a test, so there are now two, each
# exercising a path that exists.
@test "AC2: a profile-included gate with no command is refused as a configuration error, before any gate runs" {
  _seed_gates_project
  _write_exec_yaml
  yq -i '.gates.bats_fsm.command = null' "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  local receipt; receipt="$(_write_receipt bats_all)"

  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has no command"* ]]
  [[ "$output" == *"configuration error, not a silent skip"* ]]
  # Nothing ran: no report was written, and the plan did not move.
  [ ! -f "$(_report)" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

@test "AC2: a report in which a required gate says skip fails the stage rather than counting as satisfied" {
  _seed_gates_project
  _write_exec_yaml
  local receipt; receipt="$(_write_receipt bats_all)"

  # A real, passing run first — so the report this test then edits is the
  # runner's own product and not a hand-invented shape.
  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -eq 0 ]
  [ -f "$(_report)" ]
  run jq -r '.gates.bats_fsm.result' "$(_report)"
  [ "$output" = "pass" ]

  # Now the one thing under test: a REQUIRED gate carrying status "skip"
  # (P097 Step 2: the version-2 row; `result` is only the derived field).
  local tmp; tmp="$(mktemp)"
  jq '.gates.bats_fsm.status = "skip" | .gates.bats_fsm.result = "skip" | .gates.bats_fsm.reason = "no_command"' "$(_report)" > "$tmp"
  mv "$tmp" "$(_report)"

  # Re-enter the stage against that report. PLAN_REVIEW -> PLAN_GATES is not a
  # transition the table allows; the way back is through PLAN_FIX and PLAN_SYNC
  # (lib/aid-plan-state.sh). The stage then RE-READS the existing report rather
  # than minting a second broad run — which is exactly what puts the edited row
  # in front of the assertion under test.
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "PLAN_FIX"  >/dev/null
  plan_state_transition "$PLAN_ID" "PLAN_FIX"    "PLAN_SYNC" >/dev/null
  plan_state_transition "$PLAN_ID" "PLAN_SYNC"   "PLAN_GATES" >/dev/null
  _gates --substitute-receipt "bats_all=${receipt}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"never satisfied by a skip"* ]]
}

# ─── the candidate binding: the stage refuses a head that is not the
#     frozen candidate, and refuses to run at all before the freeze ─────────
# ─── Gate reuse across attempts ─────────────────────────────────────────────
# _reuse_project — a passed first attempt whose gates count their executions and
# declare inputs: bats_fsm reads everything but docs/, docs_updated reads docs/.
_reuse_project() {
  _seed_gates_project
  _write_exec_yaml
  local y="$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  yq -i '.gates.bats_fsm.command = "echo x >> .aid-o/work/ran_bats_fsm" | .gates.bats_fsm.inputs = ["**", "!docs/**"]
       | .gates.docs_updated.command = "echo x >> .aid-o/work/ran_docs_updated" | .gates.docs_updated.inputs = ["docs/**"]' "$y"
  RECEIPT_ARGS=(--substitute-receipt "bats_all=$(_write_receipt bats_all)")
  _gates "${RECEIPT_ARGS[@]}"; [ "$status" -eq 0 ]
}
# _second_attempt <file> <text> — a fix on the plan branch, a new freeze, the gates again
_second_attempt() {
  mkdir -p "$TEST_PROJECT_ROOT/$(dirname "$1")"
  _commit_on "plan/${PLAN_ID}" "$1" "$2"
  _finalize "$PLAN_ID" freeze; echo "$output"; [ "$status" -eq 0 ]
  RECEIPT_ARGS=(--substitute-receipt "bats_all=$(_write_receipt bats_all)")
  _gates "${RECEIPT_ARGS[@]}"
}
_ran() { wc -l < "$TEST_PROJECT_ROOT/.aid-o/work/ran_$1" | tr -d ' '; }

@test "reuse: after a docs-only fix the second attempt copies the gate whose inputs exclude docs and re-runs the docs gate" {
  _reuse_project
  _second_attempt docs/notes.md "a docs fix"; echo "$output"; [ "$status" -eq 0 ]
  [ "$(_ran bats_fsm)" -eq 1 ]; [ "$(_ran docs_updated)" -eq 2 ]
  [ "$(jq -r '.gates.bats_fsm.reused_from' "$(_report)")" = "R-${PLAN_ID}-final-1" ]
  [ "$(jq -r '.gates.docs_updated.reused_from // "executed"' "$(_report)")" = executed ]
  [ "$(jq -r '.revision.head_sha' "$(_report)")" = "$(_manifest_field "$PLAN_ID" candidate_sha)" ]
  [ "$(jq -r '.gates.bats_fsm.result' "$(_report)")" = pass ]
  # every copied row names a run directory that exists
  local from; for from in $(jq -r '.gates[] | .reused_from // empty' "$(_report)" | sort -u); do [ -d "$(dirname "$(_run_dir)")/$from" ]; done
  grep -q '"event":"gate_reused"' "$(_run_dir)/timeline.jsonl"
}

@test "reuse: a gate without declared inputs is copied only when the tree did not change; a code fix re-runs it" {
  _reuse_project
  _second_attempt src-fix.txt "a code fix"; [ "$status" -eq 0 ]
  [ "$(_ran bats_fsm)" -eq 2 ]                                   # its inputs changed
  [ "$(jq -r '.gates.shell_pipeline_smoke.reused_from // "executed"' "$(_report)")" = executed ]   # no inputs = the whole tree
  [ "$(jq -r '.gates.docs_updated.reused_from' "$(_report)")" = "R-${PLAN_ID}-final-1" ]
}

@test "reuse: a row that did not pass, or whose gate definition changed, is executed again" {
  _reuse_project
  yq -i '.gates.bats_fsm.timeout_seconds = 31' "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  _second_attempt docs/notes.md "a docs fix"; [ "$status" -eq 0 ]
  [ "$(_ran bats_fsm)" -eq 2 ]
  [ "$(jq -r '.gates.bats_all.reused_from // "never"' "$(_report)")" = never ]   # quarantined: never pass, never copied
}

@test "reuse: a previous attempt whose report is gone, or is not the runner's, reuses nothing" {
  _reuse_project
  local first; first="$(_run_dir)"
  jq '._generated_by = "someone-else"' "$first/gates_report.json" > "$first/g" && mv "$first/g" "$first/gates_report.json"
  _second_attempt docs/notes.md "a docs fix"; [ "$status" -eq 0 ]
  [ "$(_ran bats_fsm)" -eq 2 ]
  [ "$(jq '[.gates[] | select(.reused_from != null)] | length' "$(_report)")" -eq 0 ]
}

@test "AC2: --stage gates refuses when the plan branch has moved off the frozen candidate" {
  _seed_gates_project
  _write_exec_yaml
  _commit_on "plan/${PLAN_ID}" drift.txt "drift"

  _gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not the candidate"* ]]
  [ ! -f "$(_report)" ]
}

@test "AC2: --stage gates refuses out of any state other than PLAN_GATES" {
  _bootstrap
  _write_exec_yaml

  _gates
  [ "$status" -eq 1 ]
  [[ "$output" == *"no frozen candidate"* ]]
}

# =============================================================================
# The review and decision of a plan are covered end to end, on the real stages,
# by test-plan-final-decide.bats (freeze, gates, produce, the cp7 round, decide,
# the sabotage set, fix classes, the waiver, the integrity journal). This suite
# keeps what surrounds them: the freeze and gate stages above, the merge and the
# close below, which start from a SEEDED decided plan (_seed_plan_final_evidence).

# _write_plan_review [head_override] — the plan's sealed generation authority, which
# carries the plan review (CP1) verdict the aggregator reads. Its target_head is
# plan_base_commit by default: a plan-time artifact is stale by construction, so
# the aggregator's basis for it is ANCESTRY, not equality.
_write_plan_review() {
  local dir="$TEST_PROJECT_ROOT/.aid-o/work/evidence/${PLAN_ID}/generation"
  mkdir -p "$dir"
  local h="${1:-$(_manifest_field "$PLAN_ID" plan_base_commit)}"
  jq -n --arg h "$h" '{cp1: {verdict: "pass"}, target_head: $h}' > "$dir/generation-authority.json"
}
_decision() { printf '%s/release-decision.json' "$(_run_dir)"; }

# =============================================================================
# ─── aid-plan-fsm.sh plan-merge-to-main (Step 5) ─────────────────────────
#     + aid-release.sh tag-plan + defaults/hooks/pre-push
# =============================================================================
#
# AC5/AC6 — the ONE place in AID where the target branch moves. Every test here
# asserts what happened to `main`, because "the merge was refused" is only a
# real guarantee if the target branch is provably byte-identical afterwards.

# _seed_merge_project — a plan at AWAITING_PM, at a frozen candidate, with the
# git-tracked lifecycle manifest already on main (see _bootstrap's opt-in) and a
# SECOND declared EPIC recorded as abandoned in the RUNTIME manifest — the CF1
# input plan-merge-to-main re-scopes.
#
# It reaches AWAITING_PM through the REAL sync + freeze stages and then walks the
# REAL plan-state transition table (PLAN_GATES -> PLAN_REVIEW -> AWAITING_PM)
# rather than re-running the gate and review stages: those two stages are Step 2
# and Step 3's own, exhaustively covered above, and each costs a full release
# gate profile run. What plan-merge-to-main actually consumes from them is the
# frozen candidate and the PLAN-LEVEL audit/curator reports, and both are set up
# here explicitly — so nothing this seed skips is a precondition this command
# reads.
# _seed_merge_project — snapshot-backed (IMP-505): the builder below is unchanged and
# runs once per file; every later case restores its byte copy.
_seed_merge_project() { _snap_fixture "merge_project${1:+:$1}" _seed_merge_project_build "$@"; }

_seed_merge_project_build() {
  export AID_TEST_SEED_LIFECYCLE=1
  _bootstrap
  # REAL work on the plan branch. Without it the candidate IS the target head,
  # and `git commit-tree -p <target> -p <candidate>` collapses two identical
  # parents into one — the two-parent assertion would then be testing a
  # degenerate plan (one with no commits), not a plan.
  _commit_on "plan/${PLAN_ID}" epic-work.txt "feat: the EPIC's work"
  _add_epic "$PLAN_ID" "E-068-1_2"
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "merged_to_plan" "$mc"
  # The SECOND declared EPIC, terminated without delivery — CF1's input.
  _add_epic "$PLAN_ID" "E-068-2_2"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-2_2" "abandoned"
  plan_manifest_update "$PLAN_ID" \
    '(.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-2_2") | .terminal_reason) = "PM dropped it"' >/dev/null

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_REVIEW" >/dev/null
  plan_state_transition "$PLAN_ID" "PLAN_REVIEW" "AWAITING_PM" >/dev/null

  # The controller keeps the worktree on the candidate across the PM boundary.
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
  _seed_plan_final_evidence
}

# _seed_merge_project_pre_review — identical to _seed_merge_project up to a
# frozen candidate in PLAN_REVIEW, WITHOUT a decision: where `--stage produce`
# runs (AC11).
# _seed_merge_project_pre_review — snapshot-backed (IMP-505): the builder below is unchanged and
# runs once per file; every later case restores its byte copy.
_seed_merge_project_pre_review() { _snap_fixture "merge_project_pre_review${1:+:$1}" _seed_merge_project_pre_review_build "$@"; }

_seed_merge_project_pre_review_build() {
  export AID_TEST_SEED_LIFECYCLE=1
  _bootstrap
  _commit_on "plan/${PLAN_ID}" epic-work.txt "feat: the EPIC's work"
  _add_epic "$PLAN_ID" "E-068-1_2"
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-1_2" "merged_to_plan" "$mc"
  _add_epic "$PLAN_ID" "E-068-2_2"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-2_2" "abandoned"
  plan_manifest_update "$PLAN_ID" \
    '(.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-2_2") | .terminal_reason) = "PM dropped it"' >/dev/null

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_REVIEW" >/dev/null
  # The controller keeps the worktree ON the candidate for every plan-final
  # stage (--stage produce's aid-plan-diff.sh reads HEAD to bind head_commit).
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/${PLAN_ID}"
}

# _merge_commit — the published plan merge SHA, read from the RUNTIME manifest.
# NOT from $output: bats `run` folds stderr into stdout, and this command writes
# a deliberately loud operator narrative to stderr.
_merge_commit() {
  jq -r '.plan_boundary_manifest.plan_final_merge.merge_commit' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
}

# _poke_manifest <jq_expr> — edit the RUNTIME manifest JSON DIRECTLY, bypassing
# plan_manifest_update's invariant enforcement. That bypass is the point: the
# fail-closed freeze-time tests need a DEGENERATE on-disk manifest (a missing or
# malformed candidate_frozen_at), and the writer correctly refuses to produce
# one — the paired-nullable invariant is exactly what keeps it from happening
# through the sanctioned path. Hand corruption is therefore the only honest way
# to prove plan-merge-to-main does not trust the file it reads.
_poke_manifest() {
  local f="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  local t="${f}.poke"
  jq "$1" "$f" > "$t" && mv "$t" "$f"
}

# _main_sha / _plan_sha — the two refs every assertion here is about.
_main_sha() { git -C "$TEST_PROJECT_ROOT" rev-parse main; }
_plan_sha() { git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID"; }

# _decision_file [jq_override] — a VALID PM MERGE decision bound to this plan,
# this attempt, this candidate and this target head. The override corrupts
# exactly one field so each refusal test isolates one cause.
_decision_file() {
  local override="${1:-.}"
  local f="$TEST_TMPDIR/pm-decision.json"
  # The decision time is derived from the manifest's ACTUAL candidate_frozen_at,
  # never a wall-clock literal: a hardcoded date silently becomes "before the
  # freeze" once real time passes it, and every refusal test then fails on the
  # freshness guard instead of the cause it isolates (observed 2026-07-26).
  local _frozen; _frozen="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  jq -n --arg p "$PLAN_ID" \
        --arg r "$(_manifest_field "$PLAN_ID" plan_final_run_id)" \
        --arg c "$(_manifest_field "$PLAN_ID" candidate_sha)" \
        --arg t "$(_manifest_field "$PLAN_ID" target_branch_head_at_candidate_freeze)" \
        --arg at "$_frozen" \
    '{schema_version:"aid-pm-plan-decision-1.0", artifact_type:"pm_plan_decision",
      producer:"aid-test@1.0", created_at:$at,
      plan_id:$p, plan_final_run_id:$r, decision:"MERGE",
      candidate_sha:$c, target_branch:"main", target_head_sha:$t,
      decided_at:$at, decided_by:"pm"}' \
    | jq "$override" > "$f"
  printf '%s' "$f"
}

# _merge [decision_file] [extra args...] — the command under test.
_merge() {
  local d="${1:-$(_decision_file)}"; shift || true
  run bash "$PLAN_FSM_CLI" plan-merge-to-main "$PLAN_ID" --decision "$d" \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# ─── AC5.1: every refusal leaves the target branch unchanged ───────────────

@test "AC5: a MISSING decision file exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  _merge "$TEST_TMPDIR/nope.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PM decision"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "IMP-466: failed evidence publication leaves the local target untouched before CAS" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  git -C "$TEST_PROJECT_ROOT" remote add evidence-reject "$TEST_TMPDIR/nonexistent-remote"
  git -C "$TEST_PROJECT_ROOT" config branch.main.remote evidence-reject
  _merge "$(_decision_file)" --push
  [ "$status" -ne 0 ]
  [[ "$output" == *"evidence ref"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a MALFORMED decision file exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  printf 'not json at all' > "$TEST_TMPDIR/bad.json"
  _merge "$TEST_TMPDIR/bad.json"
  [ "$status" -eq 1 ]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision that fails pm-plan-decision.schema.json is rejected BEFORE any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  # A verdict outside the enum — structurally parseable, contractually invalid.
  local d; d="$(_decision_file '.decision = "MAYBE"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pm-plan-decision.schema.json"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision missing a REQUIRED contract field is rejected by the schema" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file 'del(.target_head_sha)')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pm-plan-decision.schema.json"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision for a DIFFERENT plan exits 1 before any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.plan_id = "P999"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"authorizes plan 'P999'"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision bound to a DIFFERENT plan-final run id exits 1 before any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.plan_final_run_id = "R-P068-final-99"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"earlier attempt"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision naming the WRONG candidate exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.candidate_sha = "0000000000000000000000000000000000000000"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"candidate mismatch"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision naming the WRONG approved target head exits 1 with main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.target_head_sha = "0000000000000000000000000000000000000000"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"approved target head"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: decision FIX refuses the merge, moves the plan to PLAN_FIX and leaves main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.decision = "FIX" | .reason = "one more pass"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_FIX" ]
}

@test "AC5: decision ABORT refuses the merge, moves the plan to ABORTED with the reason recorded, main unchanged" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.decision = "ABORT" | .reason = "superseded by P069"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]
  [ "$(_manifest_field "$PLAN_ID" terminal_reason)" = "superseded by P069" ]
}

@test "AC5: a STALE authorization (main advanced while the PM decided) merges nothing and returns the plan to PLAN_SYNC" {
  _seed_merge_project
  local d; d="$(_decision_file)"
  # main advances after the freeze and after the decision was written.
  _commit_on main hotfix.txt "hotfix on main"
  local before; before="$(_main_sha)"

  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE AUTHORIZATION"* ]]
  # main is byte-identical to its advanced state — no merge was published.
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_SYNC" ]
  # the candidate binding is gone, so no decision can be replayed against it
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "null" ]
}

# ─── AC5.2 + AC5.3: freeze-time validation, fail-closed on every degenerate
#     input ────────────────────────────────────────────────────────────────

@test "AC5: a decision whose decided_at PRECEDES candidate_frozen_at is rejected before any Git action" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file '.decided_at = "2000-01-01T00:00:00Z"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BEFORE the candidate was frozen"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a manifest MISSING candidate_frozen_at exits 1 — never 'assume old enough'" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file)"
  _poke_manifest '.plan_boundary_manifest.candidate_frozen_at = null'
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no candidate_frozen_at"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a candidate_frozen_at that is not valid RFC 3339 UTC exits 1" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  local d; d="$(_decision_file)"
  _poke_manifest '.plan_boundary_manifest.candidate_frozen_at = "yesterday-ish"'
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid RFC 3339 UTC instant"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decided_at that matches the pattern but is not a real instant exits 1" {
  _seed_merge_project
  local before; before="$(_main_sha)"
  # Pattern-valid (schema passes), calendar-invalid (date -d refuses) — the
  # exact input a regex-only check would wave through.
  local d; d="$(_decision_file '.decided_at = "2026-13-45T99:99:99Z"')"
  _merge "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"decided_at"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "AC5: a decision bound to a PRE-REFREEZE candidate fails against the rewritten candidate_frozen_at" {
  _seed_merge_project
  local old_decision; old_decision="$(_decision_file)"
  # A refreeze rewrites BOTH candidate_sha and candidate_frozen_at. Simulate the
  # rewritten freeze time being LATER than the old decision.
  _poke_manifest '.plan_boundary_manifest.candidate_frozen_at = "2099-01-01T00:00:00Z"'
  local before; before="$(_main_sha)"
  _merge "$old_decision"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BEFORE the candidate was frozen"* ]]
  [ "$(_main_sha)" = "$before" ]
}

# ─── AC5.4 + AC5.5: the compare-and-swap publish ───────────────────────────

@test "AC5: the merge commit is built without moving any ref, and a rejected update-ref leaves the target byte-identical" {
  _seed_merge_project
  local cand target; cand="$(_plan_sha)"; target="$(_main_sha)"

  # Stage 1 exactly as the command performs it: tree, then commit, then publish.
  local tree; tree="$(git -C "$TEST_PROJECT_ROOT" merge-tree --write-tree --no-messages "$target" "$cand")"
  local mc; mc="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -p "$target" -p "$cand" -m "merge(plan): probe")"
  # NOTHING has moved: main is still exactly where it was.
  [ "$(_main_sha)" = "$target" ]

  # A concurrent advance between the head check and the publish.
  _commit_on main racer.txt "another process moved main"
  local raced; raced="$(_main_sha)"
  [ "$raced" != "$target" ]

  # The compare-and-swap must REJECT, and main must be byte-identical to the
  # racer's state — the losing merge publishes nothing.
  run git -C "$TEST_PROJECT_ROOT" update-ref refs/heads/main "$mc" "$target"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$raced" ]
}

# ─── AC5.6 + AC5.10 + AC5.11: the happy path, the lifecycle commit and CF1 ──

@test "AC5: a MERGE decision publishes exactly one merge commit whose parents are the approved target head and the candidate" {
  _seed_merge_project
  local cand target; cand="$(_plan_sha)"; target="$(_main_sha)"

  _merge
  [ "$status" -eq 0 ]

  local mc; mc="$(_merge_commit)"
  [[ "$mc" =~ ^[0-9a-f]{40}$ ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "${mc}^1")" = "$target" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "${mc}^2")" = "$cand" ]
  # The candidate is reachable from main, and main is at (or above) the merge.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$cand" main
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$mc" main
  [ "$status" -eq 0 ]
  # Exactly ONE merge commit naming this plan.
  [ "$(git -C "$TEST_PROJECT_ROOT" log main --merges --grep "merge(plan): ${PLAN_ID}" --pretty=%H | wc -l)" -eq 1 ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_MERGING" ]
}

@test "plan-record-decision writes the MERGE the merge accepts, into the attempt's directory, and the merge takes it from there" {
  _seed_merge_project
  run bash "$PLAN_FSM_CLI" plan-record-decision "$PLAN_ID" MERGE --by pm --reason "PM: merge it" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local d="${output##*$'\n'}"
  [ -s "$d" ]; [[ "$d" == */pm-plan-decision.json ]]
  [ "$(jq -r '.decision + " " + .decided_by + " " + .candidate_sha' "$d")" = "MERGE pm $(_plan_sha)" ]
  _merge "$d"
  echo "$output"; [ "$status" -eq 0 ]
  [[ "$output" != *"could not copy the PM decision"* ]]
  # no frozen candidate, no decision
  run bash "$PLAN_FSM_CLI" plan-record-decision P999 MERGE --by pm --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
}

@test "AC5: the lifecycle commit lands on main by plumbing — every non-abandoned EPIC is bound to the plan merge commit" {
  _seed_merge_project
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"

  # The manifest is read from the TARGET branch, not the worktree: the whole
  # point is that the commit landed on main while HEAD stayed on the plan branch.
  local m; m="$TEST_TMPDIR/manifest-on-main.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
  [ "$(yq -r '.deliveries."E-068-1_2".delivery' "$m")" = "delivered" ]
  [ "$(yq -r '.deliveries."E-068-1_2".review' "$m")" = "accepted" ]

  # HEAD never left the plan branch, and the plan branch is not left dirty.
  [ "$(git -C "$TEST_PROJECT_ROOT" symbolic-ref --short HEAD)" = "plan/${PLAN_ID}" ]
  run git -C "$TEST_PROJECT_ROOT" diff --quiet -- .aid-lifecycle
  [ "$status" -eq 0 ]
}

@test "AC5 (CF1): the abandoned EPIC is re-scoped in the SAME commit as the bindings, and stops counting as required" {
  _seed_merge_project
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"

  local m; m="$TEST_TMPDIR/manifest-on-main.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.declared_epics[] | select(.id == "E-068-2_2") | .scope' "$m")" = "abandoned" ]
  # ONE commit for both facts: the re-scope and the bindings are in the same tree.
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
  # An abandoned EPIC is never bound as delivered.
  [ "$(yq -r '.deliveries."E-068-2_2".delivery_sha // "absent"' "$m")" = "absent" ]

  # And it is excluded from the closure denominator. The closure state MUST be
  # evaluated on the TARGET branch, not from the plan worktree: the lifecycle
  # commit landed on main by plumbing and the plan branch's own copy of the
  # manifest is deliberately restored, so reading it there would answer a
  # question about the wrong branch. Step 6 (plan-close) runs on the target
  # branch for exactly this reason.
  git -C "$TEST_PROJECT_ROOT" worktree add -q "$TEST_TMPDIR/closure-wt" main
  run aid_plan_closure_state "$PLAN_ID" "$TEST_TMPDIR/closure-wt"
  [ "$output" != "active" ]
  [ "$output" != "legacy-unverifiable" ]
}

@test "AC5: the lifecycle commit succeeds with the TARGET BRANCH CHECKED OUT IN ANOTHER WORKTREE" {
  _seed_merge_project
  # The normal production shape: main is checked out in a linked worktree, so
  # `git checkout main` from the plan worktree is impossible — Git refuses the
  # same branch twice. The plumbing path must not care.
  git -C "$TEST_PROJECT_ROOT" worktree add -q "$TEST_TMPDIR/main-wt" main
  run git -C "$TEST_PROJECT_ROOT" checkout main
  [ "$status" -ne 0 ]        # proof the legacy checkout path is genuinely blocked

  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  local m; m="$TEST_TMPDIR/manifest-on-main.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
}

@test "AC5: a crash between the publish and the lifecycle commit is resolved by re-applying the bindings, never a second merge" {
  _seed_merge_project
  local cand; cand="$(_plan_sha)"
  local target; target="$(_main_sha)"

  # Publish the merge exactly as stage 1 does, then stop — the crash point.
  local tree mc
  tree="$(git -C "$TEST_PROJECT_ROOT" merge-tree --write-tree --no-messages "$target" "$cand")"
  mc="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -p "$target" -p "$cand" -m "merge(plan): ${PLAN_ID} — crashed run")"
  git -C "$TEST_PROJECT_ROOT" update-ref refs/heads/main "$mc" "$target"

  # Resume: the binding pass alone, idempotently, on top of the published merge.
  run aid_lifecycle_plan_merge_bind "$PLAN_ID" "$TEST_PROJECT_ROOT" "$mc" \
    "$(_run_dir)" "E-068-2_2=abandoned"
  [ "$status" -eq 0 ]
  local m; m="$TEST_TMPDIR/m1.yaml"
  git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml" > "$m"
  [ "$(yq -r '.deliveries."E-068-1_2".delivery_sha' "$m")" = "$mc" ]
  local after_first; after_first="$(_main_sha)"

  # A SECOND resume is a no-op: no duplicate commit, no second merge.
  run aid_lifecycle_plan_merge_bind "$PLAN_ID" "$TEST_PROJECT_ROOT" "$mc" \
    "$(_run_dir)" "E-068-2_2=abandoned"
  [ "$status" -eq 0 ]
  [ "$(_main_sha)" = "$after_first" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" log main --merges --grep "merge(plan): ${PLAN_ID}" --pretty=%H | wc -l)" -eq 1 ]
}

# ─── AC5.7 + AC5.8: the ONE tag, and resume without duplicates ─────────────

@test "AC5: a no-bump plan merges and closes with NO tag, and tag-plan is never called" {
  _seed_merge_project
  # release-prep.json records `none` — prepare-plan resolved no version bump.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  jq -n '{schema_version:"aid-release-prep-1.0", version:"none"}' \
    > "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/release-prep.json"

  _merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO TAG"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 0 ]
}

@test "AC5: a plan WITH a prepared version creates exactly ONE tag, on the final merge commit" {
  _seed_merge_project
  jq -n '{schema_version:"aid-release-prep-1.0", version:"9.9.9"}' \
    > "$(_run_dir)/release-prep.json"

  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 1 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'v9.9.9^{commit}')" = "$mc" ]
  # No intermediate EPIC produced a version commit or a tag: the ONLY tag in the
  # repository is this one, on the plan merge.
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l)" = "v9.9.9" ]
}

@test "AC5: a resumed run after full success creates no duplicate merge, no duplicate lifecycle commit and no duplicate tag" {
  _seed_merge_project
  jq -n '{schema_version:"aid-release-prep-1.0", version:"9.9.9"}' \
    > "$(_run_dir)/release-prep.json"

  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  local after; after="$(_main_sha)"

  _merge
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESUME"* ]]
  [ "$(_main_sha)" = "$after" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" log main --merges --grep "merge(plan): ${PLAN_ID}" --pretty=%H | wc -l)" -eq 1 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 1 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'v9.9.9^{commit}')" = "$mc" ]
}

# ─── Error handling: a conflicting candidate ───────────────────────────────

@test "AC5: a merge conflict against the target branch exits 4, moves the plan to CONFLICT and leaves main unchanged" {
  _seed_merge_project
  # Both sides change the SAME file differently. main's advance is then recorded
  # as the approved target head so the stale-authorization guard does not fire
  # first — this test is about the conflict path itself.
  _commit_on "plan/${PLAN_ID}" clash.txt "plan side"
  # keep the candidate == plan head
  _poke_manifest ".plan_boundary_manifest.candidate_sha = \"$(_plan_sha)\""
  _commit_on main clash.txt "main side"
  _poke_manifest ".plan_boundary_manifest.target_branch_head_at_candidate_freeze = \"$(_main_sha)\""
  # The durable receipt is bound to the ORIGINAL candidate/target head; a
  # hand-poked manifest binding a DIFFERENT candidate must reseal it too, or
  # merge would (correctly) refuse on a receipt mismatch before ever reaching
  # the conflict path this test is actually about.
  _seed_plan_final_evidence
  local before; before="$(_main_sha)"

  _merge
  [ "$status" -eq 4 ]
  [[ "$output" == *"MERGE CONFLICT"* ]]
  [ "$(_main_sha)" = "$before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CONFLICT" ]
  # No MERGE_HEAD was ever created — the merge happened entirely in object space.
  [ ! -f "$TEST_PROJECT_ROOT/.git/MERGE_HEAD" ]
}

@test "AC5: resolving a CONFLICT by freezing again INVALIDATES the held candidate and mints a new attempt" {
  _seed_merge_project
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  # Drive the plan into CONFLICT the way plan-merge-to-main does.
  plan_state_transition "$PLAN_ID" "AWAITING_PM" "CONFLICT" >/dev/null
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CONFLICT" ]

  local run_before; run_before="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  [[ "$output" == *"CANDIDATE INVALIDATED"* ]]
  [ "$(_manifest_field "$PLAN_ID" plan_final_run_id)" != "$run_before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
}

# ─── aid-release.sh tag-plan ───────────────────────────────────────────────

@test "AC5: tag-plan is idempotent — an existing tag on the SAME merge SHA exits 0 without acting" {
  _seed_merge_project
  local sha; sha="$(_main_sha)"
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$sha" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$sha" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 1 ]
}

@test "AC5: tag-plan exits 1 when the tag exists on a DIFFERENT commit, and never moves it" {
  _seed_merge_project
  local other; other="$(_main_sha)"
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$other" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local elsewhere; elsewhere="$(_plan_sha)"
  [ "$elsewhere" != "$other" ]
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$elsewhere" --version 3.2.1 \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"immutable"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'v3.2.1^{commit}')" = "$other" ]
}

@test "AC5: tag-plan refuses the literal 'none' as a version (a no-bump plan must not call it)" {
  _seed_merge_project
  run bash "$RELEASE_CLI" tag-plan "$PLAN_ID" --merge-sha "$(_main_sha)" --version none \
    --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 2 ]
  [ "$(git -C "$TEST_PROJECT_ROOT" tag -l | wc -l)" -eq 0 ]
}

@test "AC5: prepare-plan records the resolved version in release-prep.json, and 'none' when no bump was needed" {
  _bootstrap
  _seed_version_project
  _prepare "$PLAN_ID" --bump minor
  [ "$status" -eq 0 ]
  local rec="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/release-prep.json"
  [ -s "$rec" ]
  [ "$(jq -r '.version' "$rec")" = "1.3.0" ]

  # A chore-only follow-up resolves to no bump and records the literal `none`.
  git -C "$TEST_PROJECT_ROOT" tag -a "v1.3.0" -m "released" "plan/${PLAN_ID}" >/dev/null 2>&1   # the released commit
  _commit_on "plan/${PLAN_ID}" chore.txt "chore: tidy"
  _prepare "$PLAN_ID" --bump auto
  [ "$status" -eq 0 ]
  [ "$(jq -r '.version' "$rec")" = "none" ]
}

# ─── defaults/hooks/pre-push: plan/* and task/* are exempt, main is not ─────

@test "AC5: pushing plan/* or task/* with feat:/fix: commits and no release: commit is allowed, while main in the same state is blocked" {
  _bootstrap
  local hook="$AID_PLUGIN_PATH/defaults/hooks/pre-push"
  # A tag, then a feat: commit and no release: commit — the exact state the
  # guard blocks. Made on main so LAST_TAG..HEAD sees it from any branch.
  git -C "$TEST_PROJECT_ROOT" tag -a v1.0.0 -m base
  _commit_on main feature.txt "feat: a plan-branch feature"

  # main: still blocked.
  run bash -c "cd '$TEST_PROJECT_ROOT' && printf 'refs/heads/main %s refs/heads/main %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000 | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]

  # plan/*: exempt.
  run bash -c "cd '$TEST_PROJECT_ROOT' && printf 'refs/heads/plan/${PLAN_ID} %s refs/heads/plan/${PLAN_ID} %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000 | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 0 ]

  # task/*: exempt.
  run bash -c "cd '$TEST_PROJECT_ROOT' && printf 'refs/heads/task/E-068-1_2/main %s refs/heads/task/E-068-1_2/main %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000 | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 0 ]

  # A push carrying BOTH a plan branch and main is still checked.
  run bash -c "cd '$TEST_PROJECT_ROOT' && { printf 'refs/heads/plan/${PLAN_ID} %s refs/heads/plan/${PLAN_ID} %s\n' \
    \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000; \
    printf 'refs/heads/main %s refs/heads/main %s\n' \"\$(git rev-parse main)\" 0000000000000000000000000000000000000000; } | bash '$hook' origin git@example:x.git"
  [ "$status" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# CP2 regressions (2026-07-26) — the publish/recovery invariant.
# Each of these reproduces a defect the step-5 review found and the fix closes.
# ═══════════════════════════════════════════════════════════════════════════

_ops_jsonl() { printf '%s/.aid-o/work/plan-state/%s/operations.jsonl' "$TEST_PROJECT_ROOT" "$1"; }

# ─── M4: the pre-push exemption is about the REMOTE target, not the local ref ─

@test "CP2 M4: a plan/* or task/* ref pushed AT main is blocked; same-name pushes stay exempt" {
  _bootstrap
  local hook="$AID_PLUGIN_PATH/defaults/hooks/pre-push"
  git -C "$TEST_PROJECT_ROOT" tag -a v1.0.0 -m base
  _commit_on main feature.txt "feat: an unreleased feature"
  local sha; sha="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  local zero=0000000000000000000000000000000000000000

  _push() {
    run bash -c "cd '$TEST_PROJECT_ROOT' && printf '%s %s %s %s\n' '$1' '$sha' '$2' '$zero' \
      | bash '$hook' origin git@example:x.git"
  }

  # The attack: an exempt-looking LOCAL ref aimed at the guarded remote branch.
  _push "refs/heads/plan/${PLAN_ID}" "refs/heads/main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]

  _push "refs/heads/task/E-068-1_2/main" "refs/heads/main"
  [ "$status" -eq 1 ]

  # The legitimate pushes are untouched.
  _push "refs/heads/plan/${PLAN_ID}" "refs/heads/plan/${PLAN_ID}"
  [ "$status" -eq 0 ]

  _push "refs/heads/task/E-068-1_2/main" "refs/heads/task/E-068-1_2/main"
  [ "$status" -eq 0 ]
}

# ─── M1: a recorded resulting_sha must not disarm the stale-auth guard ───────

@test "CP2 M1: after the target is REWOUND past our merge, a re-run publishes nothing and returns to PLAN_SYNC" {
  _seed_merge_project
  local before_main; before_main="$(_main_sha)"
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"
  [ -n "$mc" ]

  # The target branch is rewound PAST our merge to a commit that is neither the
  # approved head nor a descendant of the merge: the op log still holds our
  # resulting_sha, but it no longer explains where main is. This is the exact
  # shape that used to fall through and CAS-publish against the live head.
  # (Rewinding to exactly the approved head is a different, benign case: the
  # decision still describes that head, so re-converging there is correct.)
  local earlier; earlier="$(git -C "$TEST_PROJECT_ROOT" rev-parse "${before_main}~1")"
  [ -n "$earlier" ]
  git -C "$TEST_PROJECT_ROOT" branch -f main "$earlier"
  local rewound; rewound="$(_main_sha)"
  [ "$rewound" != "$before_main" ]

  _merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"STALE AUTHORIZATION"* ]]
  [ "$(_main_sha)" = "$rewound" ]
  # The plan is no longer in a state that authorizes a publish, and a further
  # attempt refuses again rather than converging onto the rewound head.
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [[ "$output" != *"AWAITING_PM"* ]]
  _merge
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$rewound" ]
}

@test "CP2 M1: a target advance that still CONTAINS our merge resumes without a second merge" {
  _seed_merge_project
  _merge
  [ "$status" -eq 0 ]
  local mc; mc="$(_merge_commit)"

  # main moves forward, but our merge remains an ancestor — a legitimate resume.
  _commit_on main later.txt "chore: unrelated later work"
  local advanced; advanced="$(_main_sha)"
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$mc" "$advanced"
  [ "$status" -eq 0 ]

  _merge
  [[ "$output" != *"STALE AUTHORIZATION"* ]]
  # Exactly one merge of this candidate exists on main.
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | grep -c '^${mc}$'"
  [ "${output}" = "1" ]
}

# ─── M2: the operation key identifies the candidate, not just the plan ───────

@test "CP2 M2: the merge operation key is bound to the candidate, so a new candidate is a new operation" {
  _seed_merge_project
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  _merge
  [ "$status" -eq 0 ]

  # The recorded op_id names THIS candidate. Before the fix it was plan-id-only,
  # so a later attempt with a different candidate reconciled against this very
  # entry and was misreported as a crash resume.
  local ops; ops="$(jq -r 'select(.command == "plan-merge-to-main") | .op_id' "$(_ops_jsonl "$PLAN_ID")" | sort -u)"
  [ -n "$ops" ]
  [[ "$ops" == *"$cand"* ]]
  # And it is not the plan-id-only shape any more.
  [[ "$ops" != *"plan-merge-to-main:${PLAN_ID}:-:0:${PLAN_ID}"* ]]
}

# ─── M3: a failed lifecycle bind leaves NO dirty tracked file ────────────────

@test "CP2 M3: a lifecycle bind that fails mid-way restores the tracked manifest byte-identically" {
  _seed_merge_project
  local relpath=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  local manifest="${TEST_PROJECT_ROOT}/${relpath}"
  [ -f "$manifest" ]
  local before; before="$(sha256sum "$manifest" | awk '{print $1}')"

  # One VALID re-scope (which really rewrites the file) followed by an INVALID
  # one (which fails). Before the fix the valid write stayed on disk and the
  # tracked file was left dirty, deadlocking the prescribed re-run.
  run bash -c "cd '$TEST_PROJECT_ROOT' && source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh' && \
    aid_lifecycle_plan_merge_bind '$PLAN_ID' '$TEST_PROJECT_ROOT' \
      \"\$(git rev-parse main)\" '$(_run_dir)' 'E-068-2_2=abandoned' 'E-068-1_2=not-a-scope'"
  [ "$status" -ne 0 ]

  local after; after="$(sha256sum "$manifest" | awk '{print $1}')"
  [ "$before" = "$after" ]

  # And the tracked tree is clean, so the printed remedy is actually runnable.
  run bash -c "git -C '$TEST_PROJECT_ROOT' status --porcelain -- '$relpath'"
  [ -z "$output" ]
}

# =============================================================================
# ─── aid-plan-fsm.sh plan-close (Step 6) ──────────────────────────────────
# =============================================================================
#
# AC7 — "plan close is truly final and recoverable". Every test here asserts one
# of two things: that ONE individually removed or corrupted precondition BLOCKS
# the close (and leaves no marker), or that a close which does pass leaves
# exactly one atomic, head-bound marker AND a committed `.aid-lifecycle`
# receipt. The negative half is the point: a close that cannot be blocked is not
# a gate, it is a rubber stamp.

_marker() { printf '%s/.aid-o/work/plan-state/%s/plan-close-complete' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_state_lock() { printf '%s/.aid-o/work/plan-state/%s/plan-state.yaml.lock' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_manifest_lock() { printf '%s/.aid-o/work/plan-state/%s/plan-boundary-manifest.json.lock' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_close_lock() { printf '%s/.aid-o/work/plan-state/%s/plan-close.lock' "$TEST_PROJECT_ROOT" "$PLAN_ID"; }
_receipt_rel() { printf '.aid-lifecycle/receipts/%s.yaml' "$PLAN_ID"; }

# _close — the command under test.
_close() {
  run bash "$PLAN_FSM_CLI" plan-close "$PLAN_ID" \
    --project-root "$TEST_PROJECT_ROOT" "$@"
}

# _seed_plan_final_evidence — the plan-final review + C4 records the close
# transaction attests to. Built by writing REAL files into the attempt's run
# directory and recording their REAL sha256 in the manifest, exactly as
# `--stage review` does — so a later corruption of any one of them is detected
# by the same hash comparison production uses, not by a test-only shortcut.
# (The review and C4 STAGES themselves are Step 2/3/4's own exhaustive
# coverage above; re-running them here would cost a full release gate profile
# per test and prove nothing about close.)
# _seed_closable — a merged plan with its plan-final evidence, ready to close.
# (Removed by P096 while 58 cases still called it; restored 2026-09-24.)
_seed_closable() { _snap_fixture "closable${1:+:$1}" _seed_closable_build "$@"; }
_seed_closable_build() {
  _seed_merge_project
  _seed_plan_final_evidence
  _merge
  [ "$status" -eq 0 ]
}

_seed_plan_final_evidence() {
  aid_fixture_seed_plan_decided "$TEST_PROJECT_ROOT" "$PLAN_ID" || return 1
  # The private, gitignored human projection. Its Head is the candidate, which
  # IS the worktree HEAD across the close (the close moves the TARGET ref by
  # plumbing and never touches HEAD), so Check 2 sees a fresh report.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/reports"
  printf -- '---\nHead: %s\n---\n\n# %s delivery\n' "$(_manifest_field "$PLAN_ID" candidate_sha)" "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/reports/${PLAN_ID}-delivery.md"
}

@test "IMP-466: a deleted plan-final runtime projection recovers uniquely from the sealed receipt" {
  _seed_merge_project
  local state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" plan_state
  [ "$output" = "AWAITING_PM" ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/${PLAN_ID}")" ]
}

@test "IMP-466: receipt recovery refuses an ambiguous sidecar set (two genuinely distinct valid receipts)" {
  _seed_merge_project
  local cand base target target_head frozen_at run2 outputs sealed state_dir
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  frozen_at="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  outputs="$(jq -c '.plan_boundary_manifest.plan_final_review.outputs' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  run2="R-${PLAN_ID}-final-2"
  # A SECOND, independently valid, correctly-placed receipt for the SAME plan
  # and candidate under a different run id — real ambiguity, not a relocated
  # copy of the same object under a foreign name.
  sealed="$(bash -c 'source "$1"; _pfsm_seal_plan_final_review "$2" "$3" "$4" "$5" main "$6" "$7" "$8" "$9"' \
    _ "$PLAN_FSM_CLI" "$TEST_PROJECT_ROOT" "$PLAN_ID" "$base" "$cand" "$target_head" "$frozen_at" "$run2" "$outputs")"
  [[ -n "$sealed" ]]
  state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly one valid public receipt"* ]]
}

@test "IMP-466: a receipt whose content disagrees with the ref location it was found at is refused, not silently trusted or relocated" {
  _seed_merge_project
  local ref cand forged tmp blob tree commit state_dir
  ref="$(_manifest_field "$PLAN_ID" plan_final_evidence_ref)"
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  forged="$(git -C "$TEST_PROJECT_ROOT" show "${ref}:receipt.json" | \
    jq -c --arg r "R-${PLAN_ID}-final-999" --arg ref "refs/heads/aid-evidence/${PLAN_ID}/${cand}/R-${PLAN_ID}-final-999" \
      '.run_id = $r | .evidence_ref = $ref')"
  tmp="$TEST_TMPDIR/forged-receipt.json"; printf '%s\n' "$forged" > "$tmp"
  blob="$(git -C "$TEST_PROJECT_ROOT" hash-object -w "$tmp")"
  tree="$(printf '100644 blob %s\treceipt.json\n' "$blob" | git -C "$TEST_PROJECT_ROOT" mktree)"
  commit="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree" -m forged)"
  # Placed at the REAL canonical location for this plan/candidate/run, but its
  # own content claims a DIFFERENT run — the location/content binding fails.
  git -C "$TEST_PROJECT_ROOT" update-ref "$ref" "$commit"
  state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly one valid public receipt"* ]]
}

@test "IMP-466: an extra file in the sidecar ref tree is refused during recovery" {
  _seed_merge_project
  local ref tree blob2 tree2 commit2 state_dir
  ref="$(_manifest_field "$PLAN_ID" plan_final_evidence_ref)"
  tree="$(git -C "$TEST_PROJECT_ROOT" rev-parse "${ref}^{tree}")"
  blob2="$(printf 'extra' | git -C "$TEST_PROJECT_ROOT" hash-object -w --stdin)"
  tree2="$( { git -C "$TEST_PROJECT_ROOT" ls-tree "$tree"; printf '100644 blob %s\textra.txt\n' "$blob2"; } | git -C "$TEST_PROJECT_ROOT" mktree)"
  commit2="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$tree2" -m "tampered: extra file")"
  git -C "$TEST_PROJECT_ROOT" update-ref "$ref" "$commit2"
  state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exactly one valid public receipt"* ]]
}

@test "IMP-466: sealing refuses a receipt whose output inventory is missing a required key" {
  _seed_merge_project
  local base cand target_head frozen_at outputs incomplete before_ref
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  frozen_at="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  outputs="$(jq -c '.plan_boundary_manifest.plan_final_review.outputs' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  incomplete="$(jq -c 'del(.["plan-diff.json"])' <<< "$outputs")"
  before_ref="$(git -C "$TEST_PROJECT_ROOT" for-each-ref --format='%(refname)' "refs/heads/aid-evidence/${PLAN_ID}/" | wc -l)"
  run bash -c 'source "$1"; _pfsm_seal_plan_final_review "$2" "$3" "$4" "$5" main "$6" "$7" "R-'"${PLAN_ID}"'-final-incomplete" "$8"' \
    _ "$PLAN_FSM_CLI" "$TEST_PROJECT_ROOT" "$PLAN_ID" "$base" "$cand" "$target_head" "$frozen_at" "$incomplete"
  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete or expanded"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" for-each-ref --format='%(refname)' "refs/heads/aid-evidence/${PLAN_ID}/" | wc -l)" -eq "$before_ref" ]
}

@test "IMP-466: sealing refuses a receipt whose output inventory carries an extra key" {
  _seed_merge_project
  local base cand target_head frozen_at outputs extra
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  target_head="$(git -C "$TEST_PROJECT_ROOT" rev-parse main)"
  frozen_at="$(_manifest_field "$PLAN_ID" candidate_frozen_at)"
  outputs="$(jq -c '.plan_boundary_manifest.plan_final_review.outputs' \
    "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  extra="$(jq -c '. + {"unexpected-file.json":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}' <<< "$outputs")"
  run bash -c 'source "$1"; _pfsm_seal_plan_final_review "$2" "$3" "$4" "$5" main "$6" "$7" "R-'"${PLAN_ID}"'-final-extra" "$8"' \
    _ "$PLAN_FSM_CLI" "$TEST_PROJECT_ROOT" "$PLAN_ID" "$base" "$cand" "$target_head" "$frozen_at" "$extra"
  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete or expanded"* ]]
}

@test "IMP-466: a FRESH CLONE (remote-tracking refs only, no local branches) recovers the receipt and restores AWAITING_PM" {
  _seed_merge_project
  # _seed_merge_project leaves the source worktree checked out on plan/<id>
  # (the controller keeps the candidate checked out across the PM boundary);
  # a clone's default/checked-out branch mirrors the SOURCE's HEAD, so it must
  # be moved to main first or the clone would materialise plan/<id> locally
  # too — defeating the point of this test.
  git -C "$TEST_PROJECT_ROOT" checkout -q main
  local clone="$TEST_TMPDIR/clone"
  git clone -q "$TEST_PROJECT_ROOT" "$clone"
  # A plain clone checks out only the default branch; every other branch this
  # plan needs (plan/<id>, the evidence ref) exists ONLY as refs/remotes/origin/*.
  run git -C "$clone" rev-parse --verify --quiet "refs/heads/plan/${PLAN_ID}"
  [ -z "$output" ]
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$clone"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.plan_state' "$clone/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")" = "AWAITING_PM" ]
  [ "$(jq -r '.plan_boundary_manifest.candidate_sha' "$clone/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/${PLAN_ID}")" ]
}

@test "IMP-466: repair from a NEW LINKED WORKTREE (no .aid-o/work of its own) recovers the shared runtime state" {
  _seed_merge_project
  local wt="$TEST_TMPDIR/worktree"
  git -C "$TEST_PROJECT_ROOT" worktree add -q --detach "$wt" main
  [ ! -d "$wt/.aid-o/work" ]
  # An ordinary linked worktree with no .aid-o/work of its own shares the
  # main checkout's runtime state by design (_pfsm_resolve_project_root's
  # git-common-dir fallback) — so the loss this test proves recovery from is
  # the SHARED state itself being gone, invoked from the worktree path.
  local state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$wt"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.plan_state' "$state_dir/plan-boundary-manifest.json")" = "AWAITING_PM" ]
}

@test "IMP-466: recovery -> merge -> close succeeds end to end after a deleted runtime projection" {
  _seed_merge_project
  local state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  _merge
  [ "$status" -eq 0 ]
  _close
  [ "$status" -eq 0 ]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = "CLOSED" ]
}

@test "IMP-466: post-merge loss of the runtime projection recovers into PLAN_MERGING and closes" {
  _seed_closable
  local state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = "PLAN_MERGING" ]
  [ "$(jq -r '.plan_boundary_manifest.plan_final_merge.result' "$state_dir/plan-boundary-manifest.json")" = "merged" ]
  _close
  [ "$status" -eq 0 ]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = "CLOSED" ]
}

@test "IMP-466 item 4: post-merge recovery closes even with the ENTIRE run directory gone (via the durable close-evidence receipt)" {
  _seed_closable
  local run_dir; run_dir="$(_run_dir)"
  local state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir" "$run_dir"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = "PLAN_MERGING" ]
  [ "$(_manifest_field "$PLAN_ID" plan_final_close_evidence_ref)" != "null" ]
  _close
  [ "$status" -eq 0 ]
  [ "$(plan_state_get "$PLAN_ID" plan_state)" = "CLOSED" ]
}

@test "D1 fix: --push publishes the close-evidence ref to the remote ALONGSIDE main, not as an afterthought" {
  _seed_merge_project
  local bare="$TEST_TMPDIR/bare-d1.git"
  git init -q --bare -b main "$bare"
  git -C "$TEST_PROJECT_ROOT" remote add origin "$bare"
  git -C "$TEST_PROJECT_ROOT" config branch.main.remote origin
  local cand run_id close_ref
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run_id="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  close_ref="refs/heads/aid-evidence-close/${PLAN_ID}/${cand}/${run_id}"
  _merge "$(_decision_file)" --push
  [ "$status" -eq 0 ]
  local remote_close_sha; remote_close_sha="$(git --git-dir="$bare" rev-parse --verify --quiet "$close_ref" 2>/dev/null || true)"
  [ -n "$remote_close_sha" ]
  [ "$remote_close_sha" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse "$close_ref")" ]
  # main and the tag (if any) reached the remote too — the close-evidence
  # push happens BEFORE main's, never instead of it.
  local remote_main; remote_main="$(git --git-dir="$bare" rev-parse --verify --quiet refs/heads/main 2>/dev/null || true)"
  [ "$remote_main" = "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" ]
}

@test "D1 fix: a FRESH CLONE of the pushed remote, after ALL local runtime evidence is gone, recovers close proof and closes" {
  _seed_merge_project
  local bare="$TEST_TMPDIR/bare-d1-fresh.git"
  git init -q --bare -b main "$bare"
  git -C "$TEST_PROJECT_ROOT" remote add origin "$bare"
  git -C "$TEST_PROJECT_ROOT" config branch.main.remote origin
  _merge "$(_decision_file)" --push
  [ "$status" -eq 0 ]
  # A genuinely independent clone of the REMOTE (not of TEST_PROJECT_ROOT) —
  # this is the auditor's exact scenario: the only durable copy of the
  # close-evidence ref left in existence is the one on origin.
  local clone="$TEST_TMPDIR/fresh-clone-d1"
  git clone -q "$bare" "$clone"
  # A clone inherits no LOCAL git config from its source (only --global config
  # would carry over, and CI runners have none) — plan-close commits inside
  # this clone (the lifecycle-bind receipt), so it needs its own identity or
  # it fails "Please tell me who you are" the moment it tries.
  git -C "$clone" config user.email "test@test.local"
  git -C "$clone" config user.name "Test"
  run git -C "$clone" rev-parse --verify --quiet "refs/heads/aid-evidence-close/${PLAN_ID}"
  [ -z "$output" ]
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$clone"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.plan_state' "$clone/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")" = "PLAN_MERGING" ]
  # The human delivery report is deliberately PRIVATE/gitignored (see
  # _bootstrap) — by design it is never git-tracked, so a real `git clone`
  # never carries it over, unlike the durable evidence refs this test is
  # actually about. Recreate it in the clone's own working tree, exactly as
  # an operator recovering a plan from a fresh clone would have to.
  # The clone's default checkout is main (the only branch AID ever pushes),
  # unlike the source repo where the controller keeps HEAD on the candidate
  # across the PM boundary — so Check 2's freshness baseline here is main's
  # ACTUAL post-merge tip (which now also carries the lifecycle-bind
  # commit), not the pre-merge candidate. Stamp the report against that
  # real current HEAD, exactly as a regenerated/re-annotated report would
  # be in a genuine post-clone recovery — this is Check 2 doing its real
  # job, unrelated to D1's evidence-receipt recovery this test targets.
  local clone_head; clone_head="$(git -C "$clone" rev-parse HEAD)"
  mkdir -p "$clone/.aid-o/reports"
  printf -- '---\nHead: %s\n---\n\n# %s delivery\n' "$clone_head" "$PLAN_ID" \
    > "$clone/.aid-o/reports/${PLAN_ID}-delivery.md"
  run bash "$PLAN_FSM_CLI" plan-close "$PLAN_ID" --project-root "$clone"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.plan_boundary_manifest.plan_state' "$clone/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")" = "CLOSED" ]
}

@test "D1 fix: a REJECTED close-evidence push (remote already has a DIFFERENT object at that ref) refuses to push main — target unchanged" {
  _seed_merge_project
  local bare="$TEST_TMPDIR/bare-d1-reject.git"
  git init -q --bare -b main "$bare"
  git -C "$TEST_PROJECT_ROOT" remote add origin "$bare"
  git -C "$TEST_PROJECT_ROOT" config branch.main.remote origin
  # Seed the bare remote's main first so we can observe it staying put.
  git -C "$TEST_PROJECT_ROOT" push -q origin main
  local before_remote_main; before_remote_main="$(git --git-dir="$bare" rev-parse refs/heads/main)"
  local cand run_id close_ref
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  run_id="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  close_ref="refs/heads/aid-evidence-close/${PLAN_ID}/${cand}/${run_id}"
  # A DIFFERENT, unrelated object already sits at the exact ref this attempt
  # will try to seal and push — the remote push is a plain (non-force)
  # update, so it is rejected exactly like a forged/relocated evidence ref
  # would be.
  local bogus; bogus="$(git -C "$TEST_PROJECT_ROOT" commit-tree "$(git -C "$TEST_PROJECT_ROOT" rev-parse HEAD^{tree})" -m "unrelated")"
  git -C "$TEST_PROJECT_ROOT" push -q origin "${bogus}:${close_ref}"
  _merge "$(_decision_file)" --push
  [ "$status" -ne 0 ]
  [[ "$output" == *"close-evidence ref"* ]]
  [ "$(git --git-dir="$bare" rev-parse refs/heads/main)" = "$before_remote_main" ]
}

@test "IMP-466: target advancing past its frozen head with NO discoverable merge of this candidate refuses recovery" {
  _seed_merge_project
  local state_dir="$TEST_PROJECT_ROOT/.aid-o/work/plan-state/${PLAN_ID}"
  rm -rf "$state_dir"
  _commit_on main unrelated.txt "chore: unrelated advance of main"
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither the frozen pre-merge state nor a discoverable merge"* ]]
}

# ─── lib/aid-lifecycle.sh: the plan-level review verdict is the sealed cp7 index ──
# _lc_status <verdict> [edit] — a run directory whose cp7/rounds.json says
# <verdict>, sealed into a real receipt; [edit] changes the index AFTER the seal.
_lc_status() {
  _seed_merge_project
  local dir cand run base; dir="$(_run_dir)"
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"; run="$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"
  git -C "$TEST_PROJECT_ROOT" update-ref -d "$(_manifest_field "$PLAN_ID" plan_final_evidence_ref)"
  jq -n --arg v "$1" --arg h "$cand" '{verdict: $v, head_sha: $h, rounds: []}' > "$dir/cp7/rounds.json"
  local outputs; outputs="$(cd "$dir" && for f in acceptance-evidence.json cp7/rounds.json gates_report.json plan-diff.json release-decision.json review-profile.json semantic-review-final.json; do
      jq -n --arg k "$f" --arg v "sha256:$(sha256sum "$f" | cut -d' ' -f1)" '{($k): $v}'; done | jq -sc add)"
  bash -c 'source "$1"; _pfsm_seal_plan_final_review "$2" "$3" "$4" "$5" main "$6" "$7" "$8" "$9"' _ "$PLAN_FSM_CLI" \
    "$TEST_PROJECT_ROOT" "$PLAN_ID" "$base" "$cand" "$(git -C "$TEST_PROJECT_ROOT" rev-parse main)" "$(_manifest_field "$PLAN_ID" candidate_frozen_at)" "$run" "$outputs" >/dev/null
  [[ -z "${2:-}" ]] || { jq "$2" "$dir/cp7/rounds.json" > "$dir/cp7/r" && mv "$dir/cp7/r" "$dir/cp7/rounds.json"; }
  run bash -c 'source "$1"; _AID_LC_PLAN_RUN_DIR="$2" _aid_lc_plan_review_status "$3" "$4"' _ "$LIFECYCLE_LIB" "$dir" "$TEST_PROJECT_ROOT" "$PLAN_ID"
}

@test "lifecycle: a passed whole-plan round sealed in the receipt reads accepted; a failed one rejected; a waived one accepted" {
  _lc_status pass;   [ "$output" = accepted ]
  _lc_status fail;   [ "$output" = rejected ]
  _lc_status waived; [ "$output" = accepted ]
}

@test "lifecycle: an index edited after the seal, or one naming another candidate, is unverifiable; no index is none" {
  _lc_status fail '.verdict = "pass"'; [ "$output" = unverifiable ]
  _lc_status pass '.head_sha = "0000000000000000000000000000000000000000"'; [ "$output" = unverifiable ]
  run bash -c 'source "$1"; _AID_LC_PLAN_RUN_DIR="$2" _aid_lc_plan_review_status "$3" "$4"' _ "$LIFECYCLE_LIB" "$TEST_TMPDIR/nowhere" "$TEST_PROJECT_ROOT" "$PLAN_ID"
  [ "$output" = none ]
}

# ─── AC7: the happy path ───────────────────────────────────────────────────

@test "AC7: a merged plan closes — exactly one head-bound marker, a committed .aid-lifecycle receipt, and state CLOSED" {
  _seed_closable
  [ ! -f "$(_marker)" ]
  local main_before; main_before="$(_main_sha)"

  _close
  [ "$status" -eq 0 ]

  # Exactly ONE marker, and it is bound to the published merge.
  run bash -c "find '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID' -maxdepth 1 -name 'plan-close-complete*' | wc -l"
  [ "$output" = "1" ]
  run grep -c '^merge_commit=' "$(_marker)"
  [ "$output" = "1" ]
  run grep "^merge_commit=$(_merge_commit)$" "$(_marker)"
  [ "$status" -eq 0 ]

  # The receipt is COMMITTED on the target branch (not merely on disk).
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -eq 0 ]
  # ...and the target ref advanced by exactly that plumbing commit.
  [ "$(_main_sha)" != "$main_before" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CLOSED" ]
}

@test "AC7: a plan whose .lock sidecars EXIST but are not held closes normally (and the close takes its own lock)" {
  _seed_closable
  # The sidecars are on disk by design — flock releases on descriptor close,
  # not on unlink — so requiring their ABSENCE would make close unsatisfiable.
  [ -f "$(_state_lock)" ]
  [ -f "$(_manifest_lock)" ]
  _close
  [ "$status" -eq 0 ]
  # The close transaction's OWN sidecar exists afterwards, proving it held a
  # lock across the transaction while the probe still passed (owned-lock case a).
  [ -f "$(_close_lock)" ]
}

# ─── AC7: plan-close-complete is absent until the merge or a recorded abort ──

@test "AC7: plan-close-complete is absent before the merge — a close out of AWAITING_PM is refused" {
  _seed_merge_project
  _seed_plan_final_evidence
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"AWAITING_PM"* ]]
  [ ! -f "$(_marker)" ]
}

# ─── AC7: the corruption matrix — each item INDIVIDUALLY blocks ─────────────

@test "AC7: removing the runtime manifest blocks close and writes no marker" {
  _seed_closable
  rm -f "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-boundary-manifest.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to close"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the final gate report blocks close" {
  _seed_closable
  rm -f "$(_run_dir)/gates_report.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"gate report"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing a required review output blocks close" {
  _seed_closable
  rm -f "$(_run_dir)/semantic-review-final.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"semantic-review-final.json"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: CORRUPTING a required review output blocks close (the recorded hash no longer matches)" {
  _seed_closable
  printf '{"tampered":true}\n' > "$(_run_dir)/review-profile.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"review-profile.json"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: corrupting the final SHA binding (plan_final_review.candidate_sha) blocks close" {
  _seed_closable
  _poke_manifest '.plan_boundary_manifest.plan_final_review.candidate_sha = "0000000000000000000000000000000000000000"'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"not to this attempt"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the plan-final decision blocks close" {
  _seed_closable
  rm -f "$(_run_dir)/release-decision.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan-final decision"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a decision that does not say release_ready blocks close" {
  _seed_closable
  local d; d="$(_run_dir)/release-decision.json"
  jq '.release_decision.release_ready = false' "$d" > "${d}.t" && mv "${d}.t" "$d"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"release_ready: true"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the PM decision blocks close" {
  _seed_closable
  [ -f "$(_run_dir)/pm-plan-decision.json" ]
  rm -f "$(_run_dir)/pm-plan-decision.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"no PM decision recorded"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: removing the merge record blocks close" {
  _seed_closable
  _poke_manifest 'del(.plan_boundary_manifest.plan_final_merge)'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"no published plan merge"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: corrupting EPIC ancestry blocks close" {
  _seed_closable
  # A commit that RESOLVES but is NOT an ancestor of the plan branch — built as
  # a parentless dangling commit with `commit-tree`, so no ref moves and the
  # worktree is untouched (an orphan-branch checkout would fight the untracked
  # gitignored fixture files for no benefit).
  local foreign
  foreign="$(git -C "$TEST_PROJECT_ROOT" commit-tree \
    "$(git -C "$TEST_PROJECT_ROOT" rev-parse 'main^{tree}')" -m "foreign, unreachable")"
  _poke_manifest "(.plan_boundary_manifest.epic_runs[] | select(.epic_id == \"E-068-1_2\") | .epic_merge_commit) = \"${foreign}\""
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an ancestor"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: UNKNOWN ancestry blocks rather than passing" {
  _seed_closable
  _poke_manifest '(.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-1_2") | .epic_merge_commit) = "dead0000dead0000dead0000dead0000dead0000"'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"ancestry UNKNOWN"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a stale queue state blocks close" {
  _seed_closable
  # The EPIC's task branch really IS merged (it points at the candidate, which
  # the plan merge published on main), while the queue still claims blocked.
  git -C "$TEST_PROJECT_ROOT" branch "task/E-068-1_2/main" "$(_manifest_field "$PLAN_ID" candidate_sha)"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-068-1_2
  path: p
  status: blocked
  depends_on: []
YAML
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"check4"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a stale active.md state blocks close" {
  _seed_closable
  git -C "$TEST_PROJECT_ROOT" branch "task/E-068-1_2/main" "$(_manifest_field "$PLAN_ID" candidate_sha)"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config" "$TEST_PROJECT_ROOT/.aid-o/work"
  cat > "$TEST_PROJECT_ROOT/.aid-o/config/queue.yaml" <<'YAML'
- epic_id: E-068-1_2
  path: p
  status: queued
  depends_on: []
YAML
  printf 'E-068-1_2 is waiting for merge\n' > "$TEST_PROJECT_ROOT/.aid-o/work/active.md"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"check4"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: a missing release/tag record blocks close" {
  _seed_closable
  # prepare-plan resolved a version, but no tag exists on the merge.
  jq -n '{version:"9.9.9"}' > "$(_run_dir)/release-prep.json"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"v9.9.9"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: an unfinished operation record blocks close" {
  _seed_closable
  printf '{"op_id":"epic-merge-to-plan:%s:-:0:E-068-1_2","command":"epic-merge-to-plan","subject":"E-068-1_2","phase":"git_applied","expected_before_sha":null,"resulting_sha":null,"at":"2026-07-26T00:00:00Z"}\n' \
    "$PLAN_ID" >> "$(_ops_jsonl "$PLAN_ID")"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"unfinished operation record"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: an in-progress merge (MERGE_HEAD) blocks close" {
  _seed_closable
  printf '%s\n' "$(_main_sha)" > "$TEST_PROJECT_ROOT/.git/MERGE_HEAD"
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"MERGE_HEAD"* ]]
  [ ! -f "$(_marker)" ]
  rm -f "$TEST_PROJECT_ROOT/.git/MERGE_HEAD"
}

# ─── AC7: the owned-lock exception ─────────────────────────────────────────

@test "AC7: a SEPARATE live process holding another relevant sidecar blocks close, and is NAMED" {
  _seed_closable
  local lock; lock="$(_manifest_lock)"
  setsid flock -x "$lock" -c 'sleep 60' >/dev/null 2>&1 &
  local holder=$!
  # Wait until the lock is genuinely held before probing.
  local i=0
  while [ "$i" -lt 50 ] && flock -n "$lock" true 2>/dev/null; do sleep 0.1; i=$((i+1)); done

  _close
  local st="$status" out="$output"
  pkill -P "$holder" 2>/dev/null || true
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  [ "$st" -eq 1 ]
  [[ "$out" == *"still HELD"* ]]
  [[ "$out" == *"plan-boundary-manifest.json.lock"* ]]
  [ ! -f "$(_marker)" ]
}

@test "AC7: the owned-lock exception is PATH-scoped — a different lock held by the SAME process still blocks" {
  _seed_closable
  # Source the CLI so the probe runs IN THIS process: the "same process holds a
  # different lock" case cannot be produced through a subprocess.
  # shellcheck disable=SC1090
  source "$PLAN_FSM_CLI"
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"

  # (a) Holding ONLY our own close lock: the probe passes.
  aid_lock_acquire "$(_close_lock)" 5
  local own_fd="$AID_LOCK_FD"
  run _pfsm_close_lock_contended "$PLAN_ID" "$(_close_lock)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # (c) The SAME process additionally holds a DIFFERENT lock: still blocked.
  aid_lock_acquire "$(_manifest_lock)" 5
  local other_fd="$AID_LOCK_FD"
  run _pfsm_close_lock_contended "$PLAN_ID" "$(_close_lock)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan-boundary-manifest.json.lock"* ]]

  aid_lock_release "$other_fd" || true
  aid_lock_release "$own_fd" || true
}

# ─── AC7: crash resume ─────────────────────────────────────────────────────

@test "AC7: re-running after a simulated crash between the receipt and the marker writes exactly ONE marker and no second receipt" {
  _seed_closable
  _close
  [ "$status" -eq 0 ]
  local main_after_close; main_after_close="$(_main_sha)"
  local receipt_blob; receipt_blob="$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")"

  # Simulate the crash: the receipt IS committed (git_applied happened), but the
  # marker was never written and the plan never reached CLOSED.
  rm -f "$(_marker)"
  yq -i '.plan_state = "PLAN_MERGING"' "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-state.yaml"

  _close
  [ "$status" -eq 0 ]

  # Exactly ONE marker...
  run bash -c "find '$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID' -maxdepth 1 -name 'plan-close-complete*' | wc -l"
  [ "$output" = "1" ]
  # ...no second receipt commit (the target ref did not move again)...
  [ "$(_main_sha)" = "$main_after_close" ]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")" = "$receipt_blob" ]
  # ...and the plan is CLOSED again.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CLOSED" ]
}

@test "AC7: an existing close marker whose preconditions no longer hold is reported as close_marker_invalid" {
  _seed_closable
  _close
  [ "$status" -eq 0 ]
  [ -f "$(_marker)" ]

  # The marker stays, but the evidence it attests to is destroyed and the plan
  # is put back at the boundary. A resumed close must REVALIDATE, not trust it.
  rm -f "$(_run_dir)/gates_report.json"
  yq -i '.plan_state = "PLAN_MERGING"' "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-state.yaml"

  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"close_marker_invalid"* ]]
}

# ─── AC7: the abort close ──────────────────────────────────────────────────

@test "AC7: a plan closed by ABORT writes the marker with the terminal reason, an abort record, NO receipt, and leaves the target unchanged" {
  _seed_merge_project
  _seed_plan_final_evidence
  local main_before; main_before="$(_main_sha)"
  local d; d="$(_decision_file '.decision = "ABORT" | .reason = "PM stopped the plan"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]

  _close
  [ "$status" -eq 0 ]
  [ -f "$(_marker)" ]
  run grep '^result=abort$' "$(_marker)"
  [ "$status" -eq 0 ]

  # An abort record naming the abandoned candidate and the unchanged target.
  run jq -r '.result + " " + .terminal_reason + " " + .abandoned_candidate_sha' "$(_run_dir)/plan-close-abort.json"
  [ "$status" -eq 0 ]
  [[ "$output" == "aborted PM stopped the plan "* ]]

  # NO lifecycle receipt, and main is byte-identical apart from the manifest's
  # own `status: aborted` commit (which is the abort's durable record).
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -ne 0 ]
  run git -C "$TEST_PROJECT_ROOT" show "main:.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  [[ "$output" == *"aborted"* ]]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$main_before" main
  [ "$status" -eq 0 ]
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$(_manifest_field "$PLAN_ID" candidate_sha)" main
  [ "$status" -ne 0 ]
}

@test "AC7: an abort close with NO recorded terminal reason is refused" {
  _seed_merge_project
  _seed_plan_final_evidence
  local d; d="$(_decision_file '.decision = "ABORT" | .reason = "PM stopped the plan"')"
  _merge "$d"
  [ "$status" -eq 3 ]
  _poke_manifest 'del(.plan_boundary_manifest.terminal_reason)'
  _close
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminal_reason"* ]]
  [ ! -f "$(_marker)" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC7 — the aid-fsm.sh delegation (CP3 pre-review finding, 2026-07-26).
# cmd_plan_close ran the IRREVERSIBLE plan-layer close (receipt + CLOSED +
# marker) BEFORE checking the EPIC's required Curator/Auditor reports, so a
# missing report failed the command only after the plan was already closed in
# the books. These tests hold the ordering.
# ═══════════════════════════════════════════════════════════════════════════

_EPIC_ID="E-068-1_2"
_epic_dir() { printf '%s/.aid-o/work/evidence/%s/R-%s-1' "$TEST_PROJECT_ROOT" "$_EPIC_ID" "$_EPIC_ID"; }

# _seed_delegated_close [--no-curator|--no-audit] — a plan closable through the
# FSM entry point: the declared mode says plan_branch, the plan is merged, and
# the EPIC carries its required reports unless one is deliberately withheld.
_seed_delegated_close() {
  local omit="${1:-}"
  export AID_TEST_DECLARED_PLAN_MODE=plan_branch
  _seed_closable
  local d; d="$(_epic_dir)"
  mkdir -p "$d"
  [[ "$omit" == "--no-curator" ]] || echo "curator report" > "${d}/curator-report.md"
  [[ "$omit" == "--no-audit" ]]   || printf 'blocking_findings: false\n' > "${d}/audit-report.md"
  # Both optional specialists are switched OFF so the test isolates the two
  # ALWAYS-required reports rather than re-testing the toggles.
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  printf 'simplifier:\n  enabled: false\nreporter:\n  enabled: false\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
}

_fsm_close() {
  run bash "$AID_PLUGIN_PATH/scripts/aid-fsm.sh" plan-close \
    "$_EPIC_ID" "$(_epic_dir)" "$TEST_PROJECT_ROOT"
}

@test "AC7: with complete evidence the delegation closes once — one receipt, both markers, CLOSED" {
  _seed_delegated_close

  _fsm_close
  [ "$status" -eq 0 ]

  # Exactly one receipt commit on the target branch.
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list main -- '$(_receipt_rel)' | wc -l"
  [ "$output" = "1" ]

  # Both markers: the plan-level close record and the EPIC's CA signal.
  [ -f "$(_marker)" ]
  [ -f "$(_epic_dir)/ca-review-complete" ]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "CLOSED" ]
}

@test "AC7: a crash after the plan-layer close but before the CA marker converges on re-run — no second receipt" {
  _seed_delegated_close

  _fsm_close
  [ "$status" -eq 0 ]
  local receipt_blob; receipt_blob="$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")"

  # Simulate the crash window: the plan is closed and its receipt committed, but
  # the EPIC's CA marker never landed.
  rm -f "$(_epic_dir)/ca-review-complete"

  _fsm_close
  [ "$status" -eq 0 ]
  [ -f "$(_epic_dir)/ca-review-complete" ]

  # The receipt is untouched — the re-run completed the marker, it did not
  # close the plan a second time.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:$(_receipt_rel)")" = "$receipt_blob" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list main -- '$(_receipt_rel)' | wc -l"
  [ "$output" = "1" ]
}

@test "AC7: removing the tracked lifecycle manifest BLOCKS a plan-branch close — the receipt is mandatory, not conditional on the file" {
  _seed_closable
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  local main_before; main_before="$(_main_sha)"

  # The manifest is removed from the WORKTREE — the shape an accidental clean or
  # a checkout of a pre-lifecycle revision produces. Before the fix this dropped
  # the close into the legacy "no receipt required" path and it SUCCEEDED.
  rm -f "${TEST_PROJECT_ROOT}/${rel}"

  _close
  [ "$status" -ne 0 ]
  [[ "$output" == *"MANDATORY"* ]]

  [ ! -f "$(_marker)" ]
  run git -C "$TEST_PROJECT_ROOT" cat-file -e "main:$(_receipt_rel)"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$main_before" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "CLOSED" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC8 — in-flight inventory and the default mode flip (E-068-2_2 Step 1).
# The migration is deliberately unclever: an inventory and an explicit stamp,
# never inference and never a mid-run conversion.
# ═══════════════════════════════════════════════════════════════════════════

_inv() { run bash "$PLAN_FSM_CLI" inventory --project-root "$TEST_PROJECT_ROOT" "$@"; }

# _seed_plan_file — inventory enumerates plans from .aid-o/plans/P*.md and the
# queue. A fixture with neither has no plans to inventory, which is correct
# behaviour and useless as a test subject.
_seed_plan_file() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  printf '# %s\n\n**EPIC 1: the one**\n' "$PLAN_ID" \
    > "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-inventory-subject.md"
}

# _seed_lifecycle_manifest [mode] — a schema-shaped manifest, optionally stamped.
_seed_lifecycle_manifest() {
  local mode="${1:-}"
  local lm="${TEST_PROJECT_ROOT}/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  mkdir -p "$(dirname "$lm")"
  printf 'schema_version: "aid-2.0"\nrepo_id: t\nplan_id: %s\ndeclared_epics: []\n' "$PLAN_ID" > "$lm"
  [[ -n "$mode" ]] && printf 'mode: %s\n' "$mode" >> "$lm"
  printf '%s' "$lm"
}
_default_mode() { run bash "$PLAN_FSM_CLI" __default-mode --project-root "$TEST_PROJECT_ROOT"; }

# _seed_gate_profiles [yes|no] — the project execution.yaml the mode resolver
# reads. `plan_branch` is granted only when a gate_profiles table is present.
_seed_gate_profiles() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config"
  if [[ "${1:-yes}" == "yes" ]]; then
    printf 'gates:\n  bats_fsm:\n    required: true\ngate_profiles:\n  quick:\n    include:\n      - bats_fsm\n' \
      > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  else
    printf 'gates:\n  bats_fsm:\n    required: true\n' \
      > "$TEST_PROJECT_ROOT/.aid-o/config/execution.yaml"
  fi
}

@test "AC8: new plans default to plan_branch when the project declares a gate_profiles table" {
  _bootstrap
  _seed_gate_profiles yes
  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == plan_branch* ]]
  [[ "$output" == *"policy_default"* ]]
}

@test "AC8: with NO gate_profiles table the default falls back to legacy and says why" {
  _bootstrap
  _seed_gate_profiles no
  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == legacy_epic_release_mode* ]]
  # The fallback is a LOGGED fact, never a silent downgrade — plan_branch mode's
  # gates stage resolves against that table, so without it the mode would have
  # no gates at all.
  [[ "$output" == *"plan_branch_unavailable"* ]]
  [[ "$output" == *"no_gate_profiles"* ]]
}

@test "AC8: inventory LISTS without mutating — a read-only run stamps nothing" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest)"
  local before; before="$(sha256sum "$lm" | awk '{print $1}')"

  _inv
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PLAN_ID"* ]]
  [[ "$output" == *"read-only"* ]]
  [ "$(sha256sum "$lm" | awk '{print $1}')" = "$before" ]
}

@test "AC8: --apply stamps an existing plan legacy_epic_release_mode, never migrates it" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest)"
  # _bootstrap's plan_state_init already stamps the RUNTIME state plan_branch,
  # and the mode reader legitimately falls back to it when the manifest carries
  # none — so an "unstamped plan" fixture has to clear it, or the subject is
  # already stamped and the test proves nothing.
  yq -i 'del(.mode)' "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml"

  _inv --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.mode' "$lm")" = "legacy_epic_release_mode" ]
  # Stamping is NOT migration: no plan branch was created for it.
  [[ "$output" == *"no plan was migrated"* ]]
}

@test "AC8: --apply on an ALREADY stamped plan is a no-op, not an error" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest plan_branch)"

  _inv --apply
  [ "$status" -eq 0 ]
  [ "$(yq -r '.mode' "$lm")" = "plan_branch" ]
  [[ "$output" == *"already_stamped"* ]]
}

@test "AC8: an UNKNOWN declared mode exits non-zero and mutates nothing" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  local lm; lm="$(_seed_lifecycle_manifest banana)"
  local before; before="$(sha256sum "$lm" | awk '{print $1}')"

  _inv --apply
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
  [ "$(sha256sum "$lm" | awk '{print $1}')" = "$before" ]
}

@test "AC8: a plan id matching no plan file and no queue entry exits non-zero" {
  _bootstrap
  _seed_gate_profiles yes
  _inv --plan P999
  [ "$status" -ne 0 ]
  [[ "$output" == *"no plan file or queue entry"* ]]
}

@test "AC8: an unknown value in the policy fails CLOSED to legacy and names the value" {
  _bootstrap
  _seed_gate_profiles yes
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  printf 'schema_version: "aid-2.0"\ndefault_mode: sideways\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"

  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == legacy_epic_release_mode* ]]
  [[ "$output" == *"unknown_policy_default"* ]]
  [[ "$output" == *"sideways"* ]]
}

@test "AC8: a project may opt OUT of the new model through its own policy copy" {
  _bootstrap
  _seed_gate_profiles yes
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/config/policies"
  printf 'schema_version: "aid-2.0"\ndefault_mode: legacy_epic_release_mode\n' \
    > "$TEST_PROJECT_ROOT/.aid-o/config/policies/plan-boundary-policy.yaml"

  _default_mode
  [ "$status" -eq 0 ]
  [[ "$output" == legacy_epic_release_mode* ]]
  [[ "$output" == *"policy_default"* ]]
  [[ "$output" != *"unknown_policy_default"* ]]
}

@test "AC8: the stamped mode must be COMMITTED, not merely present in the worktree" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  # ensure_manifest commits what it writes, so a mode stamped after that call
  # and never re-committed would live only in the worktree while the authority
  # every later reader consults — target_branch's committed tree — carried none.
  source "$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh"
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  ( cd "$TEST_PROJECT_ROOT" && aid_lifecycle_ensure_manifest "$PLAN_ID" "." >/dev/null 2>&1 ) || skip "ensure_manifest unavailable in this fixture"
  ( cd "$TEST_PROJECT_ROOT" && yq -i '.mode = "plan_branch"' "$rel" \
      && _aid_lc_isolated_commit "." "lifecycle: declare mode plan_branch for $PLAN_ID" "$rel" >/dev/null 2>&1 )

  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' 2>/dev/null | yq -r '.mode'"
  [ "$status" -eq 0 ]
  [ "$output" = "plan_branch" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC9 — the resilience matrix (E-068-2_2 Step 2).
#
# Every transactional command is SPECIFIED as intent -> git_applied ->
# state_committed. That specification is worth nothing until a crash at each
# boundary is actually exercised, so these tests kill the process there for
# real (AID_PLAN_FSM_CRASH_AFTER, exit 99) rather than mocking it, and then
# resume and assert what survived.
# ═══════════════════════════════════════════════════════════════════════════

_crash_merge() {
  run env AID_PLAN_FSM_CRASH_AFTER="$1" bash "$PLAN_FSM_CLI" plan-merge-to-main "$PLAN_ID" \
    --decision "$(_decision_file)" --project-root "$TEST_PROJECT_ROOT"
}

@test "AC9: a crash after INTENT leaves the target branch untouched and the retry is clean" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  _crash_merge intent
  [ "$status" -eq 99 ]
  [[ "$output" == *"CRASH SEAM"* ]]
  # Nothing Git-visible happened: intent is a journal entry, not an effect.
  [ "$(_main_sha)" = "$main_before" ]

  # The retry is a normal first run, not a damaged resume.
  _merge
  [ "$status" -eq 0 ]
  [ "$(_main_sha)" != "$main_before" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC9: a crash after GIT_APPLIED reuses the published merge and never makes a second one" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  _crash_merge git_applied
  [ "$status" -eq 99 ]
  # The merge IS published — that is what git_applied means — but the state
  # records that follow it are not yet written.
  local published; published="$(_main_sha)"
  [ "$published" != "$main_before" ]

  _merge
  [ "$status" -eq 0 ]
  # Exactly one merge commit: the resume reused the published one.
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC9: two crashes in a row at the same boundary behave identically — the resume is not one-shot" {
  _seed_merge_project
  _crash_merge git_applied
  [ "$status" -eq 99 ]
  _crash_merge git_applied
  [ "$status" -eq 99 ]

  _merge
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC9: a crash after git_applied leaves no SECOND tag when the plan resolves a version" {
  _seed_merge_project
  _crash_merge git_applied
  [ "$status" -eq 99 ]
  _merge
  [ "$status" -eq 0 ]
  # Whatever the tag policy resolved, it resolved it once.
  run bash -c "git -C '$TEST_PROJECT_ROOT' tag | wc -l"
  local tags="$output"
  _merge
  run bash -c "git -C '$TEST_PROJECT_ROOT' tag | wc -l"
  [ "$output" = "$tags" ]
}

@test "AC9: a pre-merge ABORT leaves the target branch unchanged and records the terminal reason" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  # `reason` is the schema's field name and the schema is closed, so an invented
  # `terminal_reason` would be rejected as malformed before the abort is even
  # considered — the decision would never reach the abort path at all.
  _merge "$(_decision_file '.decision = "ABORT" | .reason = "PM stopped it"')"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$main_before" ]

  # The plan branch and its evidence are preserved — an abort is a decision,
  # not a cleanup.
  run git -C "$TEST_PROJECT_ROOT" rev-parse --verify "plan/$PLAN_ID"
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]
}

@test "AC9: a HOTFIX on the target branch after the freeze forces resynchronisation before any merge" {
  _seed_merge_project
  local main_before; main_before="$(_main_sha)"

  # Someone lands a hotfix straight on the target branch after the candidate was
  # frozen. The authorization the PM gave describes a head that no longer exists.
  _commit_on main hotfix.txt "fix: an urgent hotfix"
  local hotfixed; hotfixed="$(_main_sha)"
  [ "$hotfixed" != "$main_before" ]

  _merge
  [ "$status" -ne 0 ]
  [[ "$output" == *"STALE AUTHORIZATION"* ]]
  [ "$(_main_sha)" = "$hotfixed" ]
  # Back to sync: the plan must re-establish a candidate against the new head.
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [[ "$output" == *"PLAN_SYNC"* ]]
}

@test "AC9: a published rollback is a NEW revert commit — history is never rewritten" {
  _seed_closable
  local mc; mc="$(_merge_commit)"
  local before; before="$(_main_sha)"

  # The rollback shape this system permits: revert forward. The controller's
  # worktree sits on the plan branch after a close, so the revert has to be made
  # ON the target branch — reverting wherever HEAD happens to point would prove
  # nothing about the target branch's history.
  run bash -c "cd '$TEST_PROJECT_ROOT' && orig=\$(git symbolic-ref --short HEAD) \
    && git checkout -q main && git revert --no-edit -m 1 '$mc' >/dev/null 2>&1 \
    && git checkout -q \"\$orig\""
  [ "$status" -eq 0 ]

  # The merge is STILL reachable — nothing was rewritten — and the branch grew.
  run git -C "$TEST_PROJECT_ROOT" merge-base --is-ancestor "$mc" main
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --count '${before}..main'"
  [ "$output" -ge 1 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC10 — the review that was recorded is the review of what was merged.
# ═══════════════════════════════════════════════════════════════════════════

@test "AC10: the recorded review is bound to the SAME candidate the merge published" {
  _seed_closable
  local recorded_cand
  recorded_cand="$(jq -r '.plan_boundary_manifest.plan_final_review.candidate_sha' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  local merged_cand
  merged_cand="$(jq -r '.plan_boundary_manifest.plan_final_merge.candidate_sha' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  # A review of one candidate and a merge of another is the precise shape of a
  # review that proves nothing.
  [ -n "$recorded_cand" ]
  [ "$recorded_cand" = "$merged_cand" ]
}

@test "AC10: EPIC work reaches the target branch ONLY through the plan branch" {
  _seed_closable
  local mc; mc="$(_merge_commit)"
  # The plan merge has exactly two parents: the previous target head and the
  # candidate. An EPIC that had merged straight to the target branch would show
  # up as its own commit on main outside this merge.
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --parents -n 1 '$mc' | wc -w"
  [ "$output" = "3" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' rev-list --merges main | wc -l"
  [ "$output" = "1" ]
}

@test "AC8: --apply COMMITS the stamp, and reports it as not durable when it cannot" {
  _bootstrap
  _seed_gate_profiles yes
  _seed_plan_file
  _seed_lifecycle_manifest >/dev/null
  yq -i 'del(.mode)' "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml"
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"

  _inv --apply
  # Whatever the outcome, it must be HONEST: either the stamp is readable from
  # the target branch's committed tree, or the run said it is not durable and
  # returned non-zero. A worktree-only stamp reported as success is the exact
  # defect this asserts against — the authority every later reader consults is
  # the committed copy, not the file on disk.
  local committed
  committed="$(git -C "$TEST_PROJECT_ROOT" show "main:${rel}" 2>/dev/null | yq -r '.mode // ""' 2>/dev/null || true)"
  if [ "$status" -eq 0 ]; then
    [ "$committed" = "legacy_epic_release_mode" ]
    [[ "$output" == *"committed"* ]]
  else
    [[ "$output" == *"NOT readable"* ]]
    [[ "$output" == *"declares nothing"* ]]
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# AC11 — the decision's derived inputs have a PRODUCER: --stage produce.
# It derives rather than fabricates: the review profile over the whole plan
# range, and the two plan-level aggregates naming every contributing EPIC.
# ═══════════════════════════════════════════════════════════════════════════

_inputs() {
  run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage produce \
    --project-root "$TEST_PROJECT_ROOT"
}

@test "AC11: --stage produce writes the derived inputs, bound to the plan and the frozen candidate" {
  _seed_merge_project_pre_review
  local dir; dir="$(_run_dir)"
  rm -f "${dir}/review-profile.json" "${dir}/acceptance-evidence.json"

  _inputs
  [ "$status" -eq 0 ]

  local cand base
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  base="$(_manifest_field "$PLAN_ID" plan_base_commit)"

  # review-profile.json: derived over the WHOLE plan range, and armed.
  [ -s "${dir}/review-profile.json" ]
  [ "$(jq -r '.revision.base_sha' "${dir}/review-profile.json")" = "$base" ]
  [ "$(jq -r '.review_profile.required_lenses | type' "${dir}/review-profile.json")" = "array" ]

  # The acceptance evidence: bound to the PLAN, never to one EPIC, and naming
  # every contributing EPIC — an empty list would assert a delivery nobody made.
  local ae="${dir}/acceptance-evidence.json"
  [ "$(jq -r '.identity.epic_id' "$ae")" = "null" ]
  [ "$(jq -r '.identity.plan_id' "$ae")" = "$PLAN_ID" ]
  [ "$(jq -r '.subject.candidate_sha' "$ae")" = "$cand" ]
  [ "$(jq -r '[.sources[] | select(.epic_id == "E-068-1_2")] | length' "$ae")" = "1" ]
  [ -s "${dir}/cp7/criteria.md" ] && [ -s "${dir}/cp7/step-check.json" ]
}

@test "AC11: --stage produce REFUSES before the candidate is frozen" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  _inputs
  [ "$status" -ne 0 ]
  [[ "$output" == *"frozen candidate"* ]]
}

@test "AC11: --stage produce REFUSES when no EPIC has merged into the plan" {
  _seed_merge_project_pre_review
  # `merged_to_plan -> abandoned` is not a legal transition, and rightly so — a
  # delivered EPIC cannot be un-delivered. So the subject is a plan whose only
  # EPIC was abandoned from `pending`, which is legal and is exactly the shape
  # "nothing merged" takes in practice.
  _add_epic "$PLAN_ID" "E-068-9_9"
  plan_manifest_set_epic_status "$PLAN_ID" "E-068-9_9" "abandoned" >/dev/null
  plan_manifest_update "$PLAN_ID" \
    '.plan_boundary_manifest.epic_runs |= [ .[] | select(.epic_id != "E-068-1_2") ]' >/dev/null
  _inputs
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing to aggregate"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC12 — the completion gate on epic-merge-to-plan (F2, found by the P067
# live dogfood 2026-07-27).
#
# The dogfood merged an EPIC into the plan branch after `epic-complete` had
# REFUSED it. Nothing at the door asked whether completion had succeeded, so
# unfinished work reached the candidate and only C4 noticed, four stages later.
# A check at the exit is not a substitute for a check at the entrance.
# ═══════════════════════════════════════════════════════════════════════════

_merge_epic() {
  run bash "$PLAN_FSM_CLI" epic-merge-to-plan "$PLAN_ID" "$1" \
    --project-root "$TEST_PROJECT_ROOT"
}

# _seed_epic_done_state <epic_id> — the EPIC's own FSM evidence, reporting DONE.
# epic-complete reads it from the evidence_dir the manifest entry records, which
# is the whole point: completion is proven by the EPIC's own run, never asserted
# by the plan layer on its behalf.
_seed_epic_done_state() {
  local eid="$1" edir
  edir="$(jq -r --arg e "$eid" \
    '[.plan_boundary_manifest.epic_runs[] | select(.epic_id == $e) | .evidence_dir][0] // ""' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  [ -n "$edir" ]
  mkdir -p "${TEST_PROJECT_ROOT}/${edir}/gates"
  printf 'epic_id: %s\nstate: DONE\ndone_phase: release\ncurrent_step: 1\ntotal_steps: 1\n' "$eid" \
    > "${TEST_PROJECT_ROOT}/${edir}/fsm-state.yaml"
  printf '{"overall":"pass","profile":"quick","gates":[]}\n' \
    > "${TEST_PROJECT_ROOT}/${edir}/gates/gates_report.json"
}

# _seed_startable_epic <epic_id> — a plan with a plan branch and ONE EPIC that
# has started (status running) and has real work on its task branch.
_seed_startable_epic() {
  local eid="$1"
  _bootstrap
  run bash "$PLAN_FSM_CLI" epic-start "$PLAN_ID" "$eid" --run-id "R-${eid}-plan" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  _commit_on "task/${eid}/main" "work-${eid}.txt" "feat: the EPIC's work"
}

@test "AC12: a PENDING epic cannot merge into the plan branch" {
  _bootstrap
  _add_epic "$PLAN_ID" "E-068-1_2"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _merge_epic "E-068-1_2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_completion_missing"* ]]
  # The plan branch is byte-identical: refusal happens before any Git mutation.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")" = "$plan_before" ]
}

@test "AC12: a RUNNING epic with no completion is refused — status alone is not proof" {
  _seed_startable_epic "E-068-1_2"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  # This is exactly the P067 shape: the EPIC started, work exists, the task
  # branch exists — and epic-complete never succeeded.
  _merge_epic "E-068-1_2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_completion_missing"* ]]
  [[ "$output" == *"merge_status"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")" = "$plan_before" ]
}

@test "AC12: a COMPLETED epic merges — the gate blocks the unproven, not the proven" {
  _seed_startable_epic "E-068-1_2"
  _seed_epic_done_state "E-068-1_2"
  run bash "$PLAN_FSM_CLI" epic-complete "$PLAN_ID" "E-068-1_2" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  _merge_epic "E-068-1_2"
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' merge-base --is-ancestor 'task/E-068-1_2/main' 'plan/$PLAN_ID'"
  [ "$status" -eq 0 ]
}

@test "AC12: work landing AFTER completion invalidates the authorization" {
  _seed_startable_epic "E-068-1_2"
  _seed_epic_done_state "E-068-1_2"
  run bash "$PLAN_FSM_CLI" epic-complete "$PLAN_ID" "E-068-1_2" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # A commit pushed onto the task branch after the check was never verified by
  # anything. Merging it would launder it into the candidate.
  _commit_on "task/E-068-1_2/main" "sneaked.txt" "feat: landed after the completion check"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _merge_epic "E-068-1_2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_completion_stale"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")" = "$plan_before" ]
}

@test "AC12: a FAILED epic-complete leaves no usable authorization behind" {
  _seed_startable_epic "E-068-1_2"
  # No DONE state file: epic-complete must refuse.
  run bash "$PLAN_FSM_CLI" epic-complete "$PLAN_ID" "E-068-1_2" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]

  # And it must not have written a merge_status a later merge could rely on.
  local ms
  ms="$(jq -r '[.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-1_2") | .merge_status // "unset"][0]' \
        "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  [ "$ms" != "pending" ]

  _merge_epic "E-068-1_2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_completion"* ]]
}

@test "AC5: after an ABORT, plan-state agrees with the authoritative state file" {
  _seed_merge_project
  _merge "$(_decision_file '.decision = "ABORT" | .reason = "diagnostic run"')"
  [ "$status" -ne 0 ]

  # The authority and the reporter must not disagree. `plan-state` answers from
  # the runtime manifest's mirror, so a transition that does not mirror leaves
  # every reader believing an aborted plan is still awaiting the PM — which is
  # exactly what the P067 close produced before the invariant admitted ABORTED.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ABORTED" ]
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABORTED"* ]]
  [[ "$output" != *"AWAITING_PM"* ]]
  # And the abandoned candidate is RETAINED — it is the proof of what was
  # refused, which is why ABORTED had to join the candidate-bearing states
  # rather than the candidate being cleared.
  [ -n "$(_manifest_field "$PLAN_ID" candidate_sha)" ]
}

@test "AC12: a DELETED FSM state file after completion blocks the merge" {
  _seed_startable_epic "E-068-1_2"
  _seed_epic_done_state "E-068-1_2"
  run bash "$PLAN_FSM_CLI" epic-complete "$PLAN_ID" "E-068-1_2" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Deleting the evidence is the cheapest way to make an unverified EPIC look
  # mergeable, so an absent state file must be a refusal, never a skipped check.
  local edir
  edir="$(jq -r '[.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-1_2") | .epic_completion_evidence_dir][0]' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  [ -n "$edir" ]
  rm -f "${TEST_PROJECT_ROOT}/${edir}/fsm-state.yaml"
  local plan_before; plan_before="$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")"

  _merge_epic "E-068-1_2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_completion_stale"* ]]
  [[ "$output" == *"never a passed check"* ]]
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "plan/$PLAN_ID")" = "$plan_before" ]
}

@test "AC12: the FSM is read from the RECORDED evidence dir, not a derived path" {
  _seed_startable_epic "E-068-1_2"
  _seed_epic_done_state "E-068-1_2"
  run bash "$PLAN_FSM_CLI" epic-complete "$PLAN_ID" "E-068-1_2" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]

  # Rewind the state the RECORDED directory holds. A merge that derived its own
  # path could miss this and pass on a completion that no longer holds.
  local edir
  edir="$(jq -r '[.plan_boundary_manifest.epic_runs[] | select(.epic_id == "E-068-1_2") | .epic_completion_evidence_dir][0]' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  printf 'epic_id: E-068-1_2\nstate: EXECUTE\ncurrent_step: 1\ntotal_steps: 2\n' \
    > "${TEST_PROJECT_ROOT}/${edir}/fsm-state.yaml"

  _merge_epic "E-068-1_2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"epic_completion_stale"* ]]
  [[ "$output" == *"not DONE"* ]]
}

@test "AC5: after a MERGE, plan-state agrees with the authoritative state file" {
  _seed_closable
  # The merge moves the plan to PLAN_MERGING. `plan-state` answers from the
  # runtime manifest's mirror, so a merge that updated only plan-state.yaml left
  # every reader believing the plan was still awaiting the PM — the same defect
  # the abort path had, found on the P075 dogfood.
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_MERGING" ]
  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLAN_MERGING"* ]]
  [[ "$output" != *"AWAITING_PM"* ]]
}

@test "AC4: a candidate that drifts in PLAN_SYNC re-freezes without any manual edit" {
  _seed_merge_project
  # Put the plan back to PLAN_SYNC with a frozen candidate, then move the plan
  # branch. Since P096 freeze folds the sync in: a moved plan branch mints the
  # next attempt and freezes the new head in the SAME call (the previous run
  # directory is left as it was) — no manual edit, no second command.
  plan_state_transition "$PLAN_ID" "PLAN_GATES" "PLAN_SYNC" >/dev/null 2>&1 || true
  _commit_on "plan/${PLAN_ID}" drift.txt "feat: work that lands after the freeze"

  _finalize "$PLAN_ID" freeze
  [ "$status" -eq 0 ]
  [[ "$output" == *"minting a new attempt"* ]]
  [[ "$output" != *"not a legal plan-state transition"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_GATES" ]
  [ "$(_manifest_field "$PLAN_ID" candidate_sha)" = "$(_plan_sha)" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC13 — the sanctioned post-merge rollback (P075 dogfood, 2026-07-27).
#
# A plan that merged and was then correctly reverted had no honest terminal
# state: abort refuses it (an aborted plan never merged) and CLOSED would claim
# a delivery that is no longer on the target branch. P075 sat in PLAN_MERGING
# forever having done everything right.
# ═══════════════════════════════════════════════════════════════════════════

_rollback() {
  run bash "$PLAN_FSM_CLI" plan-rollback "$PLAN_ID" --revert-commit "$1" \
    --project-root "$TEST_PROJECT_ROOT" "${@:2}"
}

# _revert_the_merge — revert the plan merge ON the target branch, forward.
_revert_the_merge() {
  local mc; mc="$(_merge_commit)"
  ( cd "$TEST_PROJECT_ROOT" \
    && orig="$(git symbolic-ref --short HEAD)" \
    && git checkout -q main \
    && git revert --no-edit -m 1 "$mc" >/dev/null 2>&1 \
    && git rev-parse HEAD > .revert_sha \
    && git checkout -q "$orig" )
  cat "${TEST_PROJECT_ROOT}/.revert_sha"
}

@test "AC13: a merged-then-reverted plan closes as ROLLED_BACK with all four SHAs recorded" {
  _seed_closable
  local cand mc tbefore
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  mc="$(_merge_commit)"
  tbefore="$(jq -r '.plan_boundary_manifest.plan_final_merge.target_head_before' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  local rev; rev="$(_revert_the_merge)"

  _rollback "$rev" --reason "dogfood rollback drill"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ROLLED BACK"* ]]

  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ROLLED_BACK" ]

  # All four SHAs are recorded, not merely asserted in prose.
  local m="${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  [ "$(jq -r '.plan_boundary_manifest.plan_final_rollback.candidate_sha' "$m")" = "$cand" ]
  [ "$(jq -r '.plan_boundary_manifest.plan_final_rollback.merge_commit' "$m")" = "$mc" ]
  [ "$(jq -r '.plan_boundary_manifest.plan_final_rollback.revert_commit' "$m")" = "$rev" ]
  [ "$(jq -r '.plan_boundary_manifest.plan_final_rollback.target_head_before_merge' "$m")" = "$tbefore" ]
  [ -f "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-rollback-complete" ]
}

@test "P074 F5: re-rolling back an ALREADY ROLLED BACK plan reconciles the worktree — exit 0 only when the requested revert is the one that happened" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev" --reason "dogfood rollback drill"
  [ "$status" -eq 0 ]

  # The idempotent re-run: same revert, nothing left to do, the worktree (if
  # any survived a kill) is reconciled. This is the P074 Step 11 F5 path — it
  # had NO test anywhere; `grep -rn "ALREADY ROLLED BACK"` hit only the source.
  _rollback "$rev" --reason "re-running the identical rollback request"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALREADY ROLLED BACK"* ]]
  [[ "$output" == *"$rev"* ]]           # it names the revert it actually has

  # A DIFFERENT revert is a request nothing satisfied. The ledger stays honest
  # either way, but the exit code must not claim success for it: a scripted
  # caller asking "roll back with X" against a plan rolled back with Y was
  # being told 0.
  # The merge commit is a real, different commit in this history — asking to
  # roll back "with the merge" against a plan rolled back with the revert.
  local other; other="$(_merge_commit)"
  [ "$other" != "$rev" ]
  _rollback "$other" --reason "asking for a revert that never happened here"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already ROLLED_BACK"* ]]
  [[ "$output" == *"$rev"* ]]           # names what is recorded
  [[ "$output" == *"$other"* ]]         # and what was asked for

  # Neither call rewrote the record.
  local m="${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json"
  [ "$(jq -r '.plan_boundary_manifest.plan_final_rollback.revert_commit' "$m")" = "$rev" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ROLLED_BACK" ]
}

@test "AC13: rollback REFUSES while the delivery is still on the target branch" {
  _seed_closable
  # No revert performed: the plan's files are still there, so there is nothing
  # rolled back — a record saying otherwise would be the lie the state exists to
  # avoid. A commit that is on the branch but reverts nothing must not pass.
  local head; head="$(_main_sha)"
  _rollback "$head"
  [ "$status" -ne 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "ROLLED_BACK" ]
}

@test "AC13: rollback REFUSES a revert that predates the merge" {
  _seed_closable
  local before; before="$(jq -r '.plan_boundary_manifest.plan_final_merge.target_head_before' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  # `before` is on the branch but older than the merge — it cannot be undoing it.
  _rollback "$before"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an ancestor of the revert"* || "$output" == *"still differs"* ]]
}

@test "AC13: rollback REFUSES a plan that never merged — abort remains that plan's close" {
  _seed_merge_project
  _rollback "$(_main_sha)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"PLAN_MERGING"* ]]
}

@test "AC13: the ABORT path still refuses a published merge" {
  _seed_closable
  # The rollback state must not weaken the abort contract: an aborted plan never
  # merged, and a plan that did must not be closeable as one.
  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh" "$PLAN_ID" \
    --project-root "$TEST_PROJECT_ROOT" --plan-branch --close-mode abort
  [ "$status" -ne 0 ]
  [[ "$output" == *"PUBLISHED merge"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC14 — ROLLED_BACK is durable, transactional and known system-wide.
#
# The first cut of plan-rollback recorded the state locally only: the runtime
# marker lives under gitignored .aid-o/, so a fresh clone still read `deliveries`
# and concluded the plan was delivered. Two truths — exactly what the boundary
# removes.
# ═══════════════════════════════════════════════════════════════════════════

@test "AC14: the plan-boundary schema accepts ROLLED_BACK" {
  run jq -r '[.properties.plan_boundary_manifest.properties.plan_state.enum[]] | index("ROLLED_BACK")' \
    "$AID_PLUGIN_PATH/defaults/schemas/plan-boundary-manifest.schema.json"
  [ "$output" != "null" ]
  run jq -r '[.properties.status.enum[]] | index("rolled_back")' \
    "$AID_PLUGIN_PATH/defaults/schemas/plan-lifecycle-manifest.schema.json"
  [ "$output" != "null" ]
  # The rollback block requires all four SHAs — a record naming fewer proves less.
  run jq -r '.properties.rollback.required | sort | join(",")' \
    "$AID_PLUGIN_PATH/defaults/schemas/plan-lifecycle-manifest.schema.json"
  [ "$output" = "candidate_sha,merge_commit,revert_commit,target_head_before_merge" ]
}

@test "AC14: a CLEAN CLONE can tell the plan was rolled back, with all four SHAs" {
  _seed_closable
  local cand mc tbefore
  cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  mc="$(_merge_commit)"
  tbefore="$(jq -r '.plan_boundary_manifest.plan_final_merge.target_head_before' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-boundary-manifest.json")"
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev"
  [ "$status" -eq 0 ]

  # Read it the way a fresh clone would: from git, never from .aid-o/.
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.status'"
  [ "$output" = "rolled_back" ]
  local k
  for k in candidate_sha:$cand merge_commit:$mc revert_commit:$rev target_head_before_merge:$tbefore; do
    run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.rollback.${k%%:*}'"
    [ "$output" = "${k#*:}" ]
  done
}

@test "AC14: a DECOY commit after the real revert cannot be passed off as the revert" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  # An unrelated commit AFTER the revert. The branch tip now looks correct, so a
  # check that only inspected the tip would accept this commit as the revert.
  _commit_on main decoy.txt "chore: an unrelated commit after the revert"
  local decoy; decoy="$(_main_sha)"

  _rollback "$decoy"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not itself restore"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "ROLLED_BACK" ]

  # ...while the REAL revert is still accepted, decoy and all.
  _rollback "$rev"
  [ "$status" -eq 0 ]
}

@test "AC14: a later unrelated commit does not block the rollback" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _commit_on main unrelated.txt "chore: work that has nothing to do with the plan"
  _rollback "$rev"
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ROLLED_BACK" ]
}

@test "AC14: a crash after INTENT leaves nothing recorded and the retry converges" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  run env AID_PLAN_FSM_CRASH_AFTER=intent bash "$PLAN_FSM_CLI" plan-rollback "$PLAN_ID" \
    --revert-commit "$rev" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 99 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "ROLLED_BACK" ]

  _rollback "$rev"
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ROLLED_BACK" ]
}

@test "AC14: a crash after GIT_APPLIED converges without a second durable record" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  run env AID_PLAN_FSM_CRASH_AFTER=git_applied bash "$PLAN_FSM_CLI" plan-rollback "$PLAN_ID" \
    --revert-commit "$rev" --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -eq 99 ]
  # The durable record IS written at git_applied — that is what the phase means.
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.status'"
  [ "$output" = "rolled_back" ]
  local commits_before
  commits_before="$(git -C "$TEST_PROJECT_ROOT" rev-list --count main -- "$rel")"

  _rollback "$rev"
  [ "$status" -eq 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ROLLED_BACK" ]
  # The resume did not write the record a second time.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-list --count main -- "$rel")" = "$commits_before" ]
}

@test "AC14: repair refuses a rolled-back plan, and the ABORT path still refuses a published merge" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev"
  [ "$status" -eq 0 ]

  run bash "$PLAN_FSM_CLI" plan-state "$PLAN_ID" --repair --project-root "$TEST_PROJECT_ROOT"
  [ "$status" -ne 0 ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "ROLLED_BACK" ]

  run bash "$AID_PLUGIN_PATH/scripts/aid-plan-close-check.sh" "$PLAN_ID" \
    --project-root "$TEST_PROJECT_ROOT" --plan-branch --close-mode abort
  [ "$status" -ne 0 ]
  [[ "$output" == *"PUBLISHED merge"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC15 — the four fail-open gaps in the first ROLLED_BACK cut (2026-07-27).
# Each existed because a check was skipped, not because one was missing.
# ═══════════════════════════════════════════════════════════════════════════

@test "AC15: no free-text reason reaches the git-tracked manifest" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev" --reason "a human sentence that must never enter the public ledger"
  [ "$status" -eq 0 ]

  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  # publicsafe_check forbids a `reason` key in a tracked artifact. The first cut
  # wrote one and got away with it only because this path skipped validation.
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | grep -cE '^[[:space:]]*reason[[:space:]]*:'"
  [ "$output" = "0" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | grep -c 'human sentence'"
  [ "$output" = "0" ]
  # The technical pointer IS there, so the reason remains findable.
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.rollback.decision_ref'"
  [ -n "$output" ]
  [ "$output" != "null" ]
  # And the human reason survives where free text belongs: the runtime marker.
  run grep -c 'human sentence' "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-rollback-complete"
  [ "$output" = "1" ]
}

@test "AC15: the durable record validates against the public-safe contract before it is committed" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev"
  [ "$status" -eq 0 ]
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  # The committed artifact passes the same validator the rest of the lifecycle
  # layer uses — which is the check the first cut never ran.
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' > '${TEST_TMPDIR}/lc.yaml' \
    && cd '$TEST_PROJECT_ROOT' \
    && source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh' \
    && aid_lifecycle_validate_artifact '${TEST_TMPDIR}/lc.yaml' 'plan-lifecycle-manifest.schema.json'"
  [ "$status" -eq 0 ]
}

@test "AC15: a tampered SHA in the durable record fails the read-back" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev"
  [ "$status" -eq 0 ]
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"

  # Tamper with the AUTHORITATIVE record — the copy on the target ref, which is
  # the one the read-back reads (the worktree copy is only ever a scratch buffer
  # the command materialises from the ledger and throws away). One of the five
  # fields is falsified; the other four still match.
  ( cd "$TEST_PROJECT_ROOT" \
    && orig="$(git symbolic-ref --short HEAD)" \
    && git checkout -q main \
    && yq -i '.rollback.revert_commit = "0000000000000000000000000000000000000000"' "$rel" \
    && git add -- "$rel" \
    && git commit -q -m "chore: unrelated ledger edit" \
    && git checkout -q "$orig" )
  local tampered; tampered="$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:${rel}")"

  # A crash between the durable write and the state change leaves the plan in
  # PLAN_MERGING with a record already on the target — the resume this exercises.
  sed -i 's/^plan_state: ROLLED_BACK$/plan_state: PLAN_MERGING/' \
    "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-state.yaml"
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_MERGING" ]

  # Deny the correcting write the ability to land, so the read-back is answered
  # by the tampered record rather than by the record just written. This is the
  # failure the read-back exists for: what a clean clone would read differs from
  # what this run believes it recorded.
  local hook="${TEST_PROJECT_ROOT}/.git/hooks/reference-transaction"
  mkdir -p "$(dirname "$hook")"
  printf '#!/bin/sh\nwhile read -r o n r; do case "$r" in refs/heads/main) exit 1;; esac; done\nexit 0\n' > "$hook"
  chmod +x "$hook"

  _rollback "$rev" --op-id "ac15-tamper"
  [ "$status" -ne 0 ]
  # It failed AT the read-back, naming the tampered SHA as what it read back —
  # not at some earlier precondition that would make this test pass for the
  # wrong reason. The five-field compare is what caught it: the falsified
  # revert_commit alone is a different record.
  [[ "$output" == *"read back from main:${rel} does not match what was written"* ]]
  [[ "$output" == *"read:"*"0000000000000000000000000000000000000000"* ]]
  # ...and the tampered record was NOT silently accepted as an already-durable
  # resume, which is what a status-only or single-field compare would have done.
  [[ "$output" != *"this is a resume"* ]]

  # Nothing was written: the durable record is as the tamper left it, and the
  # plan did not advance to ROLLED_BACK on a record it could not verify.
  [ "$(git -C "$TEST_PROJECT_ROOT" rev-parse "main:${rel}")" = "$tampered" ]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" = "PLAN_MERGING" ]
}

@test "AC15: a plan_branch plan with NO lifecycle manifest is refused — no state, no marker" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  # Remove the manifest from the worktree: a rollback that cannot be made
  # durable would leave the workspace saying "rolled back" while the ledger
  # still reads the plan as delivered — the two truths this work removes.
  rm -f "${TEST_PROJECT_ROOT}/${rel}"

  _rollback "$rev"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be made durable"* ]]
  run plan_state_get "$PLAN_ID" "plan_state"
  [ "$output" != "ROLLED_BACK" ]
  [ ! -f "${TEST_PROJECT_ROOT}/.aid-o/work/plan-state/${PLAN_ID}/plan-rollback-complete" ]
}

@test "AC15: the canonical closure resolver answers rolled_back, ahead of deliveries" {
  _seed_closable
  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev"
  [ "$status" -eq 0 ]

  # A rolled-back plan KEEPS its delivery bindings — they record what was merged
  # and then reverted — so a resolver that evaluated deliveries first would
  # answer delivered-but-unreconciled and contradict the ledger a clean clone
  # reads. The status must be consulted before them.
  run bash -c "cd '$TEST_PROJECT_ROOT' \
    && source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh' \
    && aid_plan_closure_state '$PLAN_ID' '$TEST_PROJECT_ROOT'"
  [ "$status" -eq 0 ]
  [ "$output" = "rolled_back" ]
}

# ═══════════════════════════════════════════════════════════════════════════
# AC16 — the git target is the ledger; the worktree is a working copy.
# Two last applications of the same rule (2026-07-27).
# ═══════════════════════════════════════════════════════════════════════════

@test "AC16: an uncommitted local status: rolled_back does NOT make the resolver say rolled_back" {
  _seed_closable
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  # Anyone can write this into a working copy without committing anything. If the
  # resolver believed it, AID would report a rollback the ledger knows nothing
  # about — the same two truths, pointing the other way.
  ( cd "$TEST_PROJECT_ROOT" && yq -i '.status = "rolled_back"' "$rel" )
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.status // \"\"'"
  [ "$output" != "rolled_back" ]

  run bash -c "cd '$TEST_PROJECT_ROOT' \
    && source '$AID_PLUGIN_PATH/scripts/lib/aid-lifecycle.sh' \
    && aid_plan_closure_state '$PLAN_ID' '$TEST_PROJECT_ROOT'"
  [ "$status" -eq 0 ]
  [ "$output" != "rolled_back" ]
}

@test "AC16: the rollback preserves deliveries the target has and the plan branch does not" {
  _seed_closable
  local rel=".aid-lifecycle/manifests/${PLAN_ID}.yaml"
  # The merge committed delivery bindings to the target. Make the plan branch's
  # working copy deliberately STALE — no deliveries — the way a plan branch cut
  # before the merge legitimately is. Editing that copy and publishing the whole
  # file would silently delete what the ledger already records.
  local target_deliveries
  target_deliveries="$(git -C "$TEST_PROJECT_ROOT" show "main:${rel}" | yq -r '.deliveries // {} | length')"
  [ "$target_deliveries" -ge 1 ]
  ( cd "$TEST_PROJECT_ROOT" && yq -i 'del(.deliveries)' "$rel" )

  local rev; rev="$(_revert_the_merge)"
  _rollback "$rev"
  [ "$status" -eq 0 ]

  # The ledger still carries every delivery, alongside the rollback record.
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.deliveries // {} | length'"
  [ "$output" = "$target_deliveries" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' show 'main:${rel}' | yq -r '.status'"
  [ "$output" = "rolled_back" ]
}

# =============================================================================
# ─── P073 Step 18: merging a review-EQUIVALENT accepted head ────────────────
# =============================================================================
#
# The PM authorized the review of the FROZEN candidate. Equivalence means that
# review still describes the delivery surface — it never means the PM
# authorized a different candidate. So the DECISION leg stays hard, the HEAD
# leg gains exactly one alternative, and the merge re-verifies equivalence LIVE
# against the current policy immediately before the irreversible action.

# _accept_ancillary — the real stage (freeze --accept-ancillary since P096), on the real seeded project.
_accept_ancillary() {
  run bash "$PLAN_FSM_CLI" plan-finalize "$PLAN_ID" --stage freeze --accept-ancillary \
    --project-root "$TEST_PROJECT_ROOT"
}

# _ancillary_commit_on_plan — one commit touching ONLY an ancillary path.
_ancillary_commit_on_plan() {
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/work"
  printf '{"event":"post-freeze note"}\n' >> "$TEST_PROJECT_ROOT/.aid-o/work/audit-log.jsonl"
  git -C "$TEST_PROJECT_ROOT" add -f .aid-o/work/audit-log.jsonl
  git -C "$TEST_PROJECT_ROOT" commit -qm "chore: an ancillary note after the freeze"
}

@test "P073 Step 18: a merge at the ACCEPTED head succeeds and carries both SHAs" {
  _seed_merge_project
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local d; d="$(_decision_file)"   # bound to the FROZEN candidate, deliberately
  _ancillary_commit_on_plan
  local accepted; accepted="$(_plan_sha)"
  _accept_ancillary
  [ "$status" -eq 0 ]

  _merge "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review-equivalent accepted head"* ]]
  # The merge really carries the accepted head. ANCESTRY, not literal
  # parentage: plan-merge-to-main re-scopes the lifecycle manifest onto the
  # plan branch first, so the merge's second parent is that re-scope commit —
  # a descendant of the accepted head, which is itself a descendant of the
  # candidate.
  run bash -c "git -C '$TEST_PROJECT_ROOT' merge-base --is-ancestor '$accepted' '$(_merge_commit)'"
  [ "$status" -eq 0 ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' merge-base --is-ancestor '$cand' '$accepted'"
  [ "$status" -eq 0 ]
  [ "$cand" != "$accepted" ]
}

@test "P073 Step 18: the equivalence-path close receipt carries merged_head and review_equivalence" {
  _seed_merge_project
  local cand; cand="$(_manifest_field "$PLAN_ID" candidate_sha)"
  local d; d="$(_decision_file)"
  _ancillary_commit_on_plan
  local accepted; accepted="$(_plan_sha)"
  _accept_ancillary
  [ "$status" -eq 0 ]
  _merge "$d"
  [ "$status" -eq 0 ]

  local ref="refs/heads/aid-evidence-close/${PLAN_ID}/${cand}/$(_manifest_field "$PLAN_ID" plan_final_run_id)"
  run bash -c "git -C '$TEST_PROJECT_ROOT' show '${ref}:receipt.json' | jq -r '.review_equivalence'"
  [ "$output" = "true" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' show '${ref}:receipt.json' | jq -r '.merged_head'"
  [ "$output" = "$accepted" ]
  run bash -c "git -C '$TEST_PROJECT_ROOT' show '${ref}:receipt.json' | jq -r '.candidate_sha'"
  [ "$output" = "$cand" ]
}

@test "P073 Step 18: a PROTECTED commit after acceptance refuses at live re-verification" {
  _seed_merge_project
  local d; d="$(_decision_file)"
  _ancillary_commit_on_plan
  _accept_ancillary
  [ "$status" -eq 0 ]
  # A delivery change lands AFTER the acceptance. The receipt is still valid
  # and still hashes correctly — only the live re-check can catch this.
  git -C "$TEST_PROJECT_ROOT" checkout -q "plan/$PLAN_ID"
  printf 'late change\n' >> "$TEST_PROJECT_ROOT/epic-work.txt"
  git -C "$TEST_PROJECT_ROOT" commit -aqm "fix: a delivery change after acceptance"

  local before; before="$(_main_sha)"
  _merge "$d"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$before" ]
}

@test "P073 Step 18: a receipt whose accepted_head disagrees with the manifest refuses" {
  _seed_merge_project
  local d; d="$(_decision_file)"
  _ancillary_commit_on_plan
  _accept_ancillary
  [ "$status" -eq 0 ]

  local r; r="$(find "$TEST_PROJECT_ROOT/.aid-o" -name 'review-equivalence-receipt*.json' | head -1)"
  jq '.accepted_head = "ffffffffffffffffffffffffffffffffffffffff"' "$r" > "$r.tmp" && mv "$r.tmp" "$r"
  # Re-bind the digest so ONLY the head binding is wrong.
  _poke_manifest ".plan_boundary_manifest.equivalence_receipt_sha256 = \"sha256:$(sha256sum "$r" | awk '{print $1}')\""

  local before; before="$(_main_sha)"
  _merge "$d"
  [ "$status" -ne 0 ]
  [ "$(_main_sha)" = "$before" ]
}

@test "P073 Step 18: accepted_head recorded but the receipt missing refuses — never merge on manifest state alone" {
  _seed_merge_project
  local d; d="$(_decision_file)"
  _ancillary_commit_on_plan
  _accept_ancillary
  [ "$status" -eq 0 ]
  find "$TEST_PROJECT_ROOT/.aid-o" -name 'review-equivalence-receipt*.json' -delete

  local before; before="$(_main_sha)"
  _merge "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"receipt"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "P073 Step 18: the DECISION leg is unchanged — a decision naming the accepted head is refused" {
  # Equivalence loosens WHICH HEAD is merged, never WHICH CANDIDATE the PM
  # authorized. A decision bound to anything but the frozen candidate fails.
  _seed_merge_project
  _ancillary_commit_on_plan
  local accepted; accepted="$(_plan_sha)"
  _accept_ancillary
  [ "$status" -eq 0 ]
  local d; d="$(_decision_file ".candidate_sha = \"$accepted\"")"

  local before; before="$(_main_sha)"
  _merge "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"candidate mismatch"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "P073 Step 18: a head that is neither the candidate nor an accepted head still refuses" {
  _seed_merge_project
  local d; d="$(_decision_file)"
  _ancillary_commit_on_plan   # moved, never accepted
  local before; before="$(_main_sha)"
  _merge "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"neither the frozen candidate"* ]]
  [ "$(_main_sha)" = "$before" ]
}

@test "P073 Step 18: a RESUME whose published merge has the other second parent refuses to seal" {
  # Codex round-1 finding 4: resume sealed merged_head/review_equivalence from
  # the CURRENT plan head without proving the published merge had that parent.
  # Here a candidate-path merge is published, the plan branch then gains an
  # accepted ancillary head, and the resumed run must refuse rather than attest
  # `review_equivalence: true` for a merge whose second parent was the candidate.
  _seed_merge_project
  local d; d="$(_decision_file)"
  _merge "$d"
  [ "$status" -eq 0 ]
  local published; published="$(_merge_commit)"

  _ancillary_commit_on_plan
  _accept_ancillary
  [ "$status" -eq 0 ]
  # Re-enter the same op: the merge is already on main.
  local main_before; main_before="$(_main_sha)"
  _merge "$d"
  [ "$status" -ne 0 ]
  # MEASURED: the refusal arrives from the stale-authorization guard (main has
  # advanced past the approved head) BEFORE the resume path is reached, and the
  # op key now differs for an accepted-head run so the candidate merge's op-log
  # entry is not read as this run's resume either. Both are fail-closed; what
  # this test guarantees is the invariant that matters — no second merge, and
  # no close evidence sealed for a merge that was not made.
  [ "$(_main_sha)" = "$main_before" ]
  [ -n "$published" ]
}

@test "P073 Step 18: the op key distinguishes a candidate merge from an accepted-head merge" {
  run grep -c 'plan_op_key "plan-merge-to-main" "$plan_id" "-" "0" "${candidate}.${merged_head}"' "$PLAN_FSM_CLI"
  [ "$output" = "1" ]
}

# =============================================================================
# ─── P073 Step 8 (remainder): forced plan-close ─────────────────────────────
# =============================================================================
#
# plan-close is the TERMINAL operation. A plan that cannot be closed cannot be
# abandoned either — that is the P082 stranding the force backdoor exists for.
# Its bookkeeping-completeness checks are therefore forceable; the physical
# ones are not. And a forced close whose lifecycle receipt cannot be committed
# must NOT claim `closed`, because aid-lifecycle.sh defines that word as
# receipt-committed-and-reachable.

_FORCE_REASON="the PM accepts an incomplete close to unstrand this plan"

@test "P073 Step 8: a blocking close-check REFUSES without --force and writes no marker" {
  _seed_closable
  rm -f "$(_run_dir)/gates_report.json"
  _close
  [ "$status" -ne 0 ]
  [ ! -f "$(_marker)" ]
}

@test "P073 Step 8: the SAME blocking close-check passes under --force, with a waiver" {
  _seed_closable
  rm -f "$(_run_dir)/gates_report.json"
  _close --force --force-reason "$_FORCE_REASON"
  [ "$status" -eq 0 ]
  [ -f "$(_marker)" ]
  # The check output is still printed — force is the second route, not a way
  # to avoid looking at what failed.
  [[ "$output" == *"FORCE: bypassing precondition 'close_check_complete'"* ]]
  run bash -c "find '$TEST_PROJECT_ROOT/.aid-o' -name 'waiver-plan-*.json' | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = "1" ]
  run bash -c "find '$TEST_PROJECT_ROOT/.aid-o' -name 'waiver-plan-*.json' -exec jq -r '.bypassed_preconditions // .bypassed // empty' {} +"
  [[ "$output" == *"close_check_complete"* ]]
}

@test "P073 Step 8: a forced close still refuses without a reason, and changes nothing" {
  _seed_closable
  rm -f "$(_run_dir)/gates_report.json"
  _close --force
  [ "$status" -ne 0 ]
  [ ! -f "$(_marker)" ]
}

@test "P073 Step 8: a missing lifecycle manifest closes under --force as closed_pending_receipt" {
  # The stranding scenario itself: the tracked manifest was deleted by hand.
  # Without force this is a blocking defect (and stays one).
  _seed_closable
  rm -f "$TEST_PROJECT_ROOT/.aid-lifecycle/manifests/${PLAN_ID}.yaml"
  git -C "$TEST_PROJECT_ROOT" rm -q --cached ".aid-lifecycle/manifests/${PLAN_ID}.yaml" 2>/dev/null || true

  _close
  [ "$status" -ne 0 ]
  [ ! -f "$(_marker)" ]

  _close --force --force-reason "$_FORCE_REASON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECONCILIATION REQUIRED"* ]]
  [[ "$output" == *"CLOSED PENDING RECEIPT"* ]]
  # The word `closed` alone is never claimed while the receipt is missing.
  [[ "$output" != *"CLOSED: ${PLAN_ID} is closed"* ]]
}

@test "P073 Step 8: closed_pending_receipt is a legal lifecycle-receipt state" {
  local schema="$AID_PLUGIN_PATH/defaults/schemas/plan-lifecycle-receipt.schema.json"
  run bash -c "jq -r '.. | .enum? // empty | .[]' '$schema' | grep -c '^closed_pending_receipt\$'"
  [ "$output" = "1" ]
}

@test "P073 Step 8: force cannot bypass a HARD precondition on close" {
  # A physical repository state has nothing on the other side to complete.
  _seed_closable
  rm -f "$TEST_PROJECT_ROOT/.aid-o/work/plan-state/$PLAN_ID/plan-boundary-manifest.json"
  _close --force --force-reason "$_FORCE_REASON"
  [ "$status" -ne 0 ]
  [ ! -f "$(_marker)" ]
}

# ─── IMP-505: the snapshot fixture layer's own guarantees ──────────────────
#
# These four cases exist because "the suite is still green" is NOT evidence that
# build-once-restore-per-case is correct. A botched version of this change looks
# green until the day two cases contaminate each other, so each property the
# layer relies on is asserted directly.

@test "IMP-505: a RESTORED merge-project fixture has the same shape as a freshly BUILT one" {
  # Fresh build, bypassing the snapshot layer entirely (the builder is called
  # with the same env input the wrapper would have keyed on).
  export AID_TEST_SEED_LIFECYCLE=1
  # 1. a FRESH build, bypassing the snapshot layer entirely.
  _seed_merge_project_build
  local fresh; fresh="$(_snap_fingerprint)"

  # 2. make sure a template exists — through the wrapper, on a clean tree.
  _snap_setup_live
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _seed_merge_project

  # 3. and NOW the restore path, proven to BE the restore path.
  _snap_setup_live
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _seed_merge_project
  [ "$_SNAP_LAST_ACTION" = "restore" ]
  local restored; restored="$(_snap_fingerprint)"

  if [[ "$fresh" != "$restored" ]]; then
    echo "--- built-vs-restored shape differs ---" >&2
    diff <(printf '%s\n' "$fresh") <(printf '%s\n' "$restored") >&2 || true
    false
  fi
}

@test "IMP-505: a RESTORED closable fixture has the same shape as a freshly BUILT one" {
  # Called exactly as an ordinary case calls it — see the twin above.
  # 1. a FRESH build, bypassing the snapshot layer entirely.
  _seed_closable_build
  local fresh; fresh="$(_snap_fingerprint)"

  # 2. make sure a template exists — through the wrapper, on a clean tree.
  _snap_setup_live
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _seed_closable

  # 3. and NOW the restore path, proven to be the restore path.
  _snap_setup_live
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _seed_closable
  [ "$_SNAP_LAST_ACTION" = "restore" ]
  local restored; restored="$(_snap_fingerprint)"

  if [[ "$fresh" != "$restored" ]]; then
    echo "--- built-vs-restored shape differs ---" >&2
    diff <(printf '%s\n' "$fresh") <(printf '%s\n' "$restored") >&2 || true
    false
  fi
}

@test "IMP-505: a restore leaves POISONED bats run state — no case may inherit a builder's \$status" {
  _seed_merge_project
  [ "$status" -eq 97 ]
  [ "$output" = "__SNAPSHOT_RESTORE_DID_NOT_RUN_A_COMMAND__" ]
}

@test "IMP-505: a mutation does not survive the next restore — every case gets its own copy" {
  # SELF-CONTAINED on purpose. This was a PAIR of cases, one dirtying the tree
  # and the next asserting the dirt was gone — which only means anything while
  # they stay adjacent, and the nightly now runs this file in a PERMUTED order
  # where they need not be. An order-dependent proof of order-independence is
  # not a proof.
  _seed_merge_project
  echo "contamination" > "$TEST_PROJECT_ROOT/CONTAMINATION-SENTINEL"
  git -C "$TEST_PROJECT_ROOT" add -A
  git -C "$TEST_PROJECT_ROOT" commit -q -m "a mutation the next restore must erase"
  run git -C "$TEST_PROJECT_ROOT" log --oneline --all
  [[ "$output" == *"a mutation the next restore must erase"* ]]

  _snap_setup_live
  export AID_PLAN_STATE_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  export AID_PLAN_MANIFEST_PROJECT_ROOT="$TEST_PROJECT_ROOT"
  _seed_merge_project
  [ "$_SNAP_LAST_ACTION" = "restore" ]
  [ ! -f "$TEST_PROJECT_ROOT/CONTAMINATION-SENTINEL" ]
  run git -C "$TEST_PROJECT_ROOT" log --oneline --all
  [[ "$output" != *"a mutation the next restore must erase"* ]]
}

# ═══════════════════════════════════════════════════════════════════════════
# P095 Step 6 — the acceptance evidence comes from the gate that verified it
#
# Until P095 the plan-level acceptance-evidence.json was aggregated from
# per-EPIC acceptance-evidence.json files nobody writes, so every plan got
# `criteria: []` and `aggregated_with_gaps` (WAN P101). It is now derived from
# plan-diff.json, the producer that actually evaluates each acceptance
# criterion.
# ═══════════════════════════════════════════════════════════════════════════

# _plan_with_acs <yaml-body> — give the fixture plan pattern acceptance criteria.
# NOT committed: a commit would move HEAD past the frozen candidate and
# plan-diff would bind to a range the manifest does not name. The stage reads
# the plan from the state root, so an untracked file is what it reads.
_plan_with_acs() {
  mkdir -p "$TEST_PROJECT_ROOT/.aid-o/plans"
  cat > "$TEST_PROJECT_ROOT/.aid-o/plans/${PLAN_ID}-acs.md" <<EOF
# ${PLAN_ID}

## Acceptance Criteria

$1
EOF
}

@test "P095: a plan with no verification_pattern yields prose_only, and --stage produce accepts it" {
  _seed_merge_project_pre_review
  _inputs
  echo "$output"; [ "$status" -eq 0 ]
  local ae; ae="$(_run_dir)/acceptance-evidence.json"
  [ "$(jq -r '.verdict.aggregation' "$ae")" = prose_only ]
  [ "$(jq -r '.acceptance_evidence.source' "$ae")" = "plan-diff.json" ]
  # and it is still the PLAN's artifact, with the contributing EPICs recorded
  [ "$(jq -r '.identity.epic_id' "$ae")" = null ]
  [ "$(jq -r '.sources | length' "$ae")" -ge 1 ]
}

@test "P095: every criterion passing yields verified, with one entry per criterion" {
  _seed_merge_project_pre_review
  _plan_with_acs '- [ ] AC1: the work file exists
  ```yaml
  verification_pattern:
    type: must_contain
    file: "epic-work.txt"
    regex: "the EPIC"
  ```
- [ ] AC2: nothing named bar was added
  ```yaml
  verification_pattern:
    type: must_not_exist
    file: "bar.ts"
  ```'
  _inputs
  echo "$output"; [ "$status" -eq 0 ]
  local ae; ae="$(_run_dir)/acceptance-evidence.json"
  [ "$(jq -r '.verdict.aggregation' "$ae")" = verified ]
  [ "$(jq -r '.acceptance_evidence.criteria | length' "$ae")" -eq 2 ]
  [ "$(jq -r '[.acceptance_evidence.criteria[] | select(.verdict == "pass")] | length' "$ae")" -eq 2 ]
  [ "$(jq -r '.acceptance_evidence.criteria[0].evidence' "$ae")" != "" ]
}

@test "P095: a criterion that fails yields partial and names it" {
  _seed_merge_project_pre_review
  _plan_with_acs '- [ ] AC1: the work file exists
  ```yaml
  verification_pattern:
    type: must_contain
    file: "epic-work.txt"
    regex: "the EPIC"
  ```
- [ ] AC2: a file nobody wrote contains a promise
  ```yaml
  verification_pattern:
    type: must_contain
    file: "never-written.txt"
    regex: "promised"
  ```'
  _inputs
  echo "$output"; [ "$status" -eq 0 ]
  local ae; ae="$(_run_dir)/acceptance-evidence.json"
  [ "$(jq -r '.verdict.aggregation' "$ae")" = partial ]
  [ "$(jq -r '.acceptance_evidence.criteria | length' "$ae")" -eq 2 ]
  [ "$(jq -r '[.acceptance_evidence.criteria[] | select(.verdict == "fail")] | length' "$ae")" -eq 1 ]
  [[ "$(jq -r '[.acceptance_evidence.criteria[] | select(.verdict == "fail") | .ac] | join(",")' "$ae")" == *"promise"* ]]
}
