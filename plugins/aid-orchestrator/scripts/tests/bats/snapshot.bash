# snapshot.bash — build a costly fixture ONCE per bats file and restore a
# byte copy of it per case (IMP-505, moved out of test-aid-plan-final-boundary
# so other suites that replay the same lifecycle can use it). A suite loads it
# AFTER declaring _SNAP_ENV_VARS, calls _snap_setup_live from setup(), and
# wraps each builder: `_seed() { _snap_fixture "<key>" _seed_build "$@"; }`.
# The key must name everything the builder's output depends on.

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
    echo "$(basename "$BATS_TEST_FILENAME"): fixed-path snapshot fixtures require serial bats (--jobs 1)." >&2
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

# _SNAP_ENV_VARS — the env vars a builder sets or reads as a SIDE EFFECT. The
# loading suite declares the array (before `load`); it goes into the template
# key and is carried across the copy.

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
