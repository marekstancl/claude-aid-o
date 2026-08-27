# CP1-deep L3 — enforcement / visibility lens (P090)

Plan: `.aid-o/plans/P090-fronta-ktera-nezastavi.md`
Lens: gitignored artifacts, CI visibility, does the test actually run, release/CI breakage
Reviewer: controller (single-provider)

stop_rule_blockers: []

findings:
  - id: L3-1
    severity: high
    title: the plan's Goal is delivered by a step that ships switched OFF
    evidence: |
      Goal: "Plán v autonomním režimu **doběhne sám**". What makes work actually start is Step 6,
      and Step 6 is opt-in with `autonomy.spawn_next_epic` defaulting to `false`. Steps 1-4 leave
      the next EPIC claimed, its branch registered and the state written — but nothing running.
      With the default configuration, a PM who installs this and walks away comes back to a plan
      that advanced by exactly one registration.
    why_it_matters: |
      This is the plan's own Principle #1 turned inward: a capability that ships disabled is a
      capability whose enforcement is a configuration file nobody edited. The plan is honest about
      WHY it is opt-in (spending money on sessions that spawn sessions), and that reason is good —
      but the Goal must then say what holds by default.
    recommendation: |
      Either state in Goal and in the registry row that unattended completion requires
      `autonomy.spawn_next_epic: true`, or make the default `true` for autonomous runs only and say
      so. Do not leave the Goal promising what the shipped default does not do.
  - id: L3-2
    severity: high
    title: nothing forbids the spawn test from launching a real Claude session
    evidence: |
      Step 6's Tests say `claude` is replaced by a stub on `PATH`. Nothing states that a real
      `claude` invocation is a test FAILURE — and `run-all-tests.sh` discovers suites by glob
      (`:268`), so this suite runs on every merge-path run and in the nightly.
    why_it_matters: |
      A stub that silently stops working (renamed helper, changed PATH order) turns a t0 suite into
      something that spends money and takes minutes, on every run, in CI. The failure is invisible
      because the test still passes.
    recommendation: |
      Require the suite to assert it invoked the stub (a marker file the stub writes), so a real
      binary being reached is a red test rather than an expensive green one.
  - id: L3-3
    severity: medium
    title: `queue_peek_next` could repeat the exact history this plan is fixing
    evidence: |
      Step 1 adds a library function. The reason `queue_claim_next` is in this plan at all is that
      it shipped as a library with no production caller and the instruction to call it lived in
      `pipeline.md`. Step 3 does give `peek` a caller — but the plan never says that a library
      function without one is the defect being repaired.
    recommendation: |
      One line in Step 1 stating that `peek` ships WITH its caller (Step 3) and that the registry
      row records the caller, not just the function.
  - id: L3-4
    severity: low
    title: the new suites do run — verified
    evidence: |
      `run-all-tests.sh:268` globs `bats/test-*.bats`, so all six new suites execute without
      registration. Tier tags are enforced separately by `aid-test-tier-lint.sh`.
    assessment: no action.
  - id: L3-5
    severity: low
    title: `continue-state.json` lives under evidence — check it is not ignored
    evidence: |
      Step 4 writes `.aid-o/work/evidence/<plan_id>/continue-state.json`. Evidence directories in
      this repository are partly git-ignored (this session had to use `git add -f` for several
      files under `.aid-o/`). The plan does not say whether this artifact is meant to be committed.
    recommendation: |
      State it: a crash-recovery hint that only exists in an ignored directory is fine for one
      machine and useless after a clone — decide which is intended.

confidence: high
