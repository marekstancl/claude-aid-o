#!/usr/bin/env bash
# =============================================================================
# generation-fixture.bash — the scaffolding the P074 generation suites share.
#
# Loaded alongside test-helpers.bash by test-generation-authority.bats,
# test-authority-verify.bats, test-generation-labels.bats,
# test-generation-resume.bats and test-supersede-generation.bats.
#
# ONLY THE COMMON PARTS LIVE HERE: the temp workspace, the symlink shadow
# plugin, the counting CP1 stub, and the committed AID project. Everything a
# single suite needs for its own question — the resume suite's kill wrappers,
# the labels suite's configurable gate stub, each suite's plan seeding —
# stays in that suite, where the reader looking for it will be.
#
# WHY A SHADOW PLUGIN AT ALL: the CP1 gate is resolved through the calling
# script's own SCRIPT_DIR, so substituting it needs a directory that LOOKS
# like the plugin. It is a farm of SYMLINKS to the real scripts/defaults with
# individual files replaced, not a 32 MB copy, so setup stays cheap and every
# script that is not deliberately stubbed is byte-identical to the shipped one.
#
# FD-3 HYGIENE (applies to every suite that loads this): bats reports results
# over fd 3, and a child holding it open truncates the suite's TAP output, so
# every heavyweight invocation runs with `3>&-`. A `run` whose command is
# MISSING exits 127 and bats writes a warning to fd 3 — with fd 3 closed that
# destroys the whole file's output, so no `run` is ever handed a path that
# might not exist.
# =============================================================================

# gen_setup — the temp workspace and the environment every generation suite
# starts from. Call it first in the suite's own setup().
gen_setup() {
  export AID_TEST_MODE=1 AID_QUIET=1 AID_CI=1
  REPO_PLUGIN="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  FIXTURES="$REPO_PLUGIN/scripts/tests/fixtures"
  TEST_TMPDIR="$(mktemp -d)"
  export REPO_PLUGIN FIXTURES TEST_TMPDIR
  unset AID_PROJECT_ROOT AID_PLAN_STATE_PROJECT_ROOT AID_PLAN_MANIFEST_PROJECT_ROOT
  unset AID_TEST_CP1_FAIL AID_TEST_CP1_RC AID_TEST_CP1_OUT
  unset AID_TEST_KILL_EPIC_TO_JSON AID_TEST_KILL_QUEUE_ADD AID_TEST_KILL_FINALIZE_REWRITE
}

gen_teardown() {
  cd /
  [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# gen_shadow_farm — the symlink farm itself, with nothing stubbed yet.
gen_shadow_farm() {
  SHADOW="$TEST_TMPDIR/plugin"
  mkdir -p "$SHADOW/scripts"
  local f b
  for f in "$REPO_PLUGIN/scripts"/*; do
    b="$(basename "$f")"
    [[ "$b" == "tests" ]] && continue
    ln -s "$f" "$SHADOW/scripts/$b"
  done
  ln -s "$REPO_PLUGIN/defaults" "$SHADOW/defaults"
  PIPELINE="$SHADOW/scripts/aid-auto-pipeline.sh"
  P2E="$SHADOW/scripts/aid-plan-to-epic.sh"
  export SHADOW PIPELINE P2E
}

# gen_stub <script-name> — replace one script in the farm with stdin.
gen_stub() {
  rm -f "$SHADOW/scripts/$1"
  cat > "$SHADOW/scripts/$1"
  chmod +x "$SHADOW/scripts/$1"
}

# gen_cp1_counting_stub — the CP1 gate stub that COUNTS its invocations, plus
# the counter file the suites assert on. AID_TEST_CP1_FAIL stands in for any
# blocking condition the real gate reports (unresolved accepted blockers, a
# blocking C0 cross-provider plan review, an exhausted CP1 ledger budget) —
# which of them fired is the real gate's own suite's business, not this one's.
gen_cp1_counting_stub() {
  gen_stub aid-cp1-gate.sh <<'STUB'
#!/usr/bin/env bash
[[ -n "${AID_TEST_CP1_COUNTER:-}" ]] && printf 'call\n' >> "$AID_TEST_CP1_COUNTER"
if [[ -n "${AID_TEST_CP1_FAIL:-}" ]]; then
  echo "CP1 GATE FAIL: blocking C0 plan review with surviving blocking findings" >&2
  exit 1
fi
echo "CP1 GATE: low-risk plan, no CP1-deep evidence required"
exit 0
STUB
  CP1_COUNT="$TEST_TMPDIR/cp1.count"; : > "$CP1_COUNT"
  export CP1_COUNT
  export AID_TEST_CP1_COUNTER="$CP1_COUNT"
}

# gen_cp1_calls — how many times the counting stub was invoked.
gen_cp1_calls() { wc -l < "$CP1_COUNT" | tr -d ' '; }

# gen_mk_project <dir> — a committed AID workspace with .aid-o gitignored.
gen_mk_project() {
  local d="$1"
  mkdir -p "$d/.aid-o/plans" "$d/.aid-o/tasks" "$d/.aid-o/config" \
           "$d/.aid-o/work/evidence" "$d/.aid-o/work/runs"
  printf 'counter: 0\n' > "$d/.aid-o/config/counter.yaml"
  printf '.aid-o/\n' > "$d/.gitignore"
  printf 'seed\n' > "$d/README.md"
  (
    cd "$d"
    git init -q -b main 2>/dev/null || { git init -q; git checkout -q -b main 2>/dev/null || git branch -m main; }
    git config user.email aid-test@example.com
    git config user.name "AID Test"
    git add -A
    git commit -q -m "seed"
  )
}
