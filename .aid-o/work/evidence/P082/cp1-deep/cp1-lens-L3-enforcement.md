# CP1-deep — Lens L3 ENFORCEMENT — P082

I read all 551 lines of the plan, then verified every claim it makes about current behaviour against the tree at `main` (v2.83.1, HEAD `3da7331`). Concretely I: read `.gitignore` and empirically probed whether a new file under `docs/plans/archive/` can be staged (`git add` → refused, "The following paths are ignored ... docs"); read `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` discovery, tier-filter and untagged-refusal logic; read `.github/workflows/ci.yml`, `nightly-tests.yml`, `version-sync.yml`; read `.aid-o/config/execution.yaml` gate commands and confirmed `plugins/aid-orchestrator/defaults/execution.yaml` really has no `gate_profiles`; located the durations journal path and the nightly report's quarantine fields; checked the tier tag of every suite the plan touches or creates; located every live `-P` grep call site under `scripts/` and in the workflows; confirmed which enforcement registry is the one under test; and traced whether each newly created mechanism has a caller. Two of the plan's twelve steps ship a mechanism nothing can reach, and one whole scope bullet has no implementation step at all.

stop_rule_blockers:

  - ref: L3-1
    severity: critical
    summary: Step 11's archive file is created under `docs/`, which `.gitignore` excludes wholesale — it can never be committed, so the closing evidence for 45 backlog entries would exist only on one machine, and the step's own append-only test cannot run in CI.
    evidence: ".gitignore:87 `docs/`; probe: `git add docs/plans/archive/__probe-P082.md` → `The following paths are ignored by one of your .gitignore files: docs` (exit 1). Plan line 392: `Create: docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md`."

  - ref: L3-2
    severity: critical
    summary: Step 10 creates the dogfood ref-isolation guard as a library and wires no caller, so the guard is a detector with no enforcement path — the exact Principle #1 violation this repo treats as binding.
    evidence: "Plan lines 360-362 (Files: Create `scripts/lib/aid-dogfood-guard.sh`; Modify `lib/aid-plan-manifest.sh`; Test `bats/test-dogfood-guard.bats`) — no modification to `plugins/aid-orchestrator/scripts/tests/e2e/c3-dogfood.sh` or `e2e/c3-dogfood-real-ac.sh`, the two live dogfood entry points."

  - ref: L3-3
    severity: high
    summary: The three P081 leftovers the plan declares in scope (durations journal, T2 mis-tiering, unread quarantine flags) have no implementation step, no test and no acceptance criterion anywhere in Steps 1-12 — the plan would close claiming them fixed.
    evidence: "Plan line 37 lists (a)/(b)/(c) as in scope; `grep -n 'durations\\|quarantine\\|nightly' P082…md` returns only lines 14/22/37/44/45/458/462 — narrative, never a step. Commit `3da7331` (\"plan: P082 absorbs the three remaining P081 review leftovers\") added scope prose only."

findings:

  - severity: critical
    ref: L3-1
    summary: >
      Step 11 (plan:392) creates `docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md`.
      `.gitignore:87` ignores `docs/` entirely; the only negation is
      `.gitignore:94 !docs/plans/2026-06-29-BACKLOG.md` (the live file, which is why it
      alone survives). I probed this empirically: `git add` on a new file under
      `docs/plans/archive/` is refused as ignored. The 83 tracked files under `docs/`
      are grandfathered (added with `-f` before or despite the rule), so the plan's
      paraphrase "entries move whole with their closing evidence" is false as written —
      the archive would be a local-only file, absent from every clone and from every CI
      checkout. The step's own test (plan:394) asserts "the archive is append-only
      relative to the previous commit", which is unsatisfiable against an untracked file.
    evidence: ".gitignore:87 `docs/`; git add probe refused; plan lines 392-394"
    suggested_fix: >
      Add `.gitignore` to Step 11's Files list with an explicit narrow negation pair
      (`!docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md`, following the
      existing narrow-negation convention at .gitignore:40-60), note that the initial
      commit needs `git add -f`, and state in the AC that the archive is TRACKED
      (`git ls-files --error-unmatch <path>`), not merely present on disk.

  - severity: critical
    ref: L3-2
    summary: >
      Step 10 ships `plugins/aid-orchestrator/scripts/lib/aid-dogfood-guard.sh` and a
      bats suite that calls it, and modifies nothing else except the manifest CLI. No
      dogfood entry point sources it: the live ones are
      `plugins/aid-orchestrator/scripts/tests/e2e/c3-dogfood.sh` and
      `.../e2e/c3-dogfood-real-ac.sh`, neither of which appears in the step. AC6
      ("A shared-common-dir dogfood target is refused") is therefore satisfiable purely
      by the fixture that calls the library directly — it would pass in full while a
      real dogfood run still shares refs with the repository under test, which the plan
      itself (line 364) says has already advanced the real branch once. Step 12 then
      registers this guard in the enforcement registry, recording an enforcement that
      no execution path invokes.
    evidence: "plan lines 360-362 and 379-382; live entry points `scripts/tests/e2e/c3-dogfood.sh`, `scripts/tests/e2e/c3-dogfood-real-ac.sh` absent from the Files list"
    suggested_fix: >
      Add the call sites to Step 10's Files list (both e2e dogfood scripts, and any
      `aid-test-audit-profile.sh` path that already does its own common-dir comparison at
      lines 88-90 — one predicate, not two), and reword AC6 so it asserts a real dogfood
      invocation is refused, not that the library returns non-zero.

  - severity: high
    ref: L3-3
    summary: >
      Scope line 37 admits three P081 leftovers, all of them L3-class. (a) the durations
      journal is written to `<state root>/.aid-o/work/test-durations.jsonl`
      (`scripts/lib/aid-test-durations.sh:62`), which `**/.aid-o/` ignores and the CI
      checkout discards every run — so the nightly's `--timing` pass
      (`.github/workflows/nightly-tests.yml`, "Run the whole portfolio with timing")
      refreshes nothing anyone else reads, and `aid-test-tier-lint.sh`'s AFFORDABLE check
      is machine-local; the workflow's own comment ("The artifact lands on a shared HOST
      path, never under `.aid-o/`") is true of the report and false of the journal.
      (c) `quarantine_unreadable` / `quarantine_write_failed` are produced at
      `scripts/aid-nightly-report.sh:187,162` and written into the artifact at 231-237;
      the only reader is line 255, inside a message block gated on
      `new_failures > 0 || escalating > 0 || prev_undelivered`, so on a green night an
      unreadable quarantine record is silent. Both are real; neither has a step. So does
      (b). A plan that lists work in Scope and never schedules it closes with the work
      undone and the record saying otherwise.
    evidence: "plan:37; scripts/lib/aid-test-durations.sh:62; .github/workflows/nightly-tests.yml (timing step + 'never under .aid-o/' comment); scripts/aid-nightly-report.sh:187,231-237,255"
    suggested_fix: >
      Either add Steps 13-15 (journal on the shared host path used by the nightly
      artifact, `/opt/eco/data/aid-nightly/...`, with a fallback and a test that the
      nightly's write is readable by the next run; a T2 re-tiering pass with recorded
      reasons; a consumer for the two quarantine flags in `/aid-status` or an
      unconditional alert) — or move all three to Out of scope with a named successor
      plan. Do not leave them in Scope with no step.

  - severity: high
    ref: L3-4
    summary: >
      The plan creates four suites — `bats/test-scope-placeholder-match.bats` (plan:74),
      `bats/test-aid-release-readme.bats` (plan:137), `bats/test-dogfood-guard.bats`
      (plan:362), `test-backlog-hygiene.sh` (plan:394) — and never declares a tier for
      any of them. `run-all-tests.sh` does not merely skip an untagged suite: because
      213 suites already carry tags, TAGGED_COUNT > 0 and the runner exits 1 with
      "this portfolio declares test tiers, but N suite(s) carry no '# aid-tier:' tag".
      That runner is the repo's merge gate command
      (`.aid-o/config/execution.yaml:49`) and both CI bash-test steps
      (`.github/workflows/ci.yml`, `--tier t0` then `--tier t1`), so the first untagged
      suite turns every gate red. The precedent is explicit: P080 needed commit
      `efb7128` "plan: P080 — Step 15 declares a tier per suite, as the generator
      requires". `Testing Strategy` (plan:458) says only "new suites declare their tier",
      which no step operationalises.
    evidence: "plan lines 74, 137, 362, 394, 458; run-all-tests.sh untagged-refusal block ('An untagged suite would silently never run under --tier'); .aid-o/config/execution.yaml:49; .github/workflows/ci.yml bash-tests step; commit efb7128"
    suggested_fix: >
      State the tier tag per new suite in each step's Test bullet (e.g. `# aid-tier: t0`
      for the placeholder-match and backlog-hygiene suites, `t1` for release-readme and
      dogfood-guard), and add an AC that `aid-test-tier-lint.sh` is clean.

  - severity: medium
    ref: L3-5
    summary: >
      Step 11's hygiene test asserts "the archive is append-only relative to the previous
      commit" (plan:394). Even once L3-1 is fixed and the archive is tracked, the merge
      gate runs it in `.github/workflows/ci.yml`'s `bash-tests` job, whose
      `actions/checkout@v5` step sets no `fetch-depth` and therefore produces a depth-1
      shallow clone — there is no previous commit to diff against. The `nightly-tests.yml`
      job had to set `fetch-depth: 50` for exactly this reason, and says so.
    evidence: ".github/workflows/ci.yml bash-tests `- uses: actions/checkout@v5` (no fetch-depth); .github/workflows/nightly-tests.yml `fetch-depth: 50` with its stated reason; plan:394"
    suggested_fix: >
      Either drop the git-history assertion (keep the content assertions, which need no
      history) or make the check skip explicitly and loudly when the checkout is shallow
      (`git rev-parse --is-shallow-repository`), and say which in the step.

  - severity: medium
    ref: L3-6
    summary: >
      AC8 (plan:543) greps `aid-review-signals.sh` for `grep[^|;]*-[A-Za-z]*P\b` with no
      comment exclusion. This repo's house style puts a long explanatory comment on every
      such fix, and the existing IMP-274 guard is careful to exclude comment lines
      (`test-aid-plan-release-boundary.bats:7224`,
      `grep -n 'grep -oP' "$f" | grep -cv ':[[:space:]]*#'`). A correctly-fixed file whose
      comment explains "these two were `grep -qP`" fails AC8. The AC is also the plan's
      only mechanical proof of Step 5, so a false red here blocks the whole EPIC.
    evidence: "plan:543; scripts/lib/aid-review-signals.sh:24-25 (`grep -qP` ×2); test-aid-plan-release-boundary.bats:7224"
    suggested_fix: >
      Mirror the existing guard: pipe through `grep -v ':[[:space:]]*#'` before asserting
      empty, exactly as the IMP-274 test does.

  - severity: medium
    ref: L3-7
    summary: >
      Step 5's widened portability detector and its self-test live in
      `bats/test-aid-plan-release-boundary.bats`, which is tagged `# aid-tier: t2` (line 2)
      AND is in `run-all-tests.sh`'s `DELEGATED_SUITES` map. It is therefore skipped twice
      over by every local gate and by both CI `--tier t0/--tier t1` steps; only the
      dedicated `plan-boundary-tests` GitHub job runs it. P082's acceptance criteria
      contain no invocation of that suite at all — AC8 only greps one library — so the
      plan's own closure never exercises the detector it widened. The step whose whole
      point is "a detector ships with a self-test that proves it catches the evading form"
      has no self-test in its own acceptance set.
    evidence: "test-aid-plan-release-boundary.bats:2 `# aid-tier: t2`; run-all-tests.sh DELEGATED_SUITES[\"test-aid-plan-release-boundary.bats\"]=\"plan-boundary-tests\"; plan ACs 490-545 contain no `test-aid-plan-release-boundary.bats` command"
    suggested_fix: >
      Add an AC invoking the suite's portability tests directly
      (`bats -f 'IMP-274' plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats`),
      or move the widened scan into its own cheap T0/T1 suite so the merge path sees it.

  - severity: medium
    ref: L3-8
    summary: >
      Three of the plan's regressions land in suites that are off the merge path:
      Step 4's in `test-plan-to-epic.sh` (`# aid-tier: t2`), Steps 8 and 9's in
      `bats/test-aid-fsm.bats` (`# aid-tier: t2`). CI runs only `--tier t0` and
      `--tier t1` before a merge, so those pins fire at best the following night. The plan
      asserts (line 455) "so the specific defect cannot return unnoticed" — that is true
      of AC time and of the nightly, not of a merge. This is the same defect the plan's
      own scope item (b) complains about, applied to its own work.
    evidence: "plugins/aid-orchestrator/scripts/tests/test-plan-to-epic.sh and bats/test-aid-fsm.bats both `# aid-tier: t2`; .github/workflows/ci.yml runs `--tier t0` then `--tier t1`; plan:455"
    suggested_fix: >
      Say so explicitly in the Testing Strategy (which pins are merge-blocking and which
      are nightly), or place the three new cases in a small T0/T1 suite instead of the
      T2 aggregates.

  - severity: low
    ref: L3-9
    summary: >
      Step 5 widens the detector's PATTERN but not its SCOPE. The guard scans only under
      `plugins/aid-orchestrator/scripts/` (test-aid-plan-release-boundary.bats:7194-7245),
      so `.github/workflows/version-sync.yml:15` (`grep -oP "$pattern"`, twice via
      `check_version`) stays invisible — benign on `ubuntu-latest`, but the plan's claim
      of "the two live PCRE call sites" is scope-relative and should say so. Separately,
      widening the pattern will newly surface `-P` uses the literal scan misses or
      allowlists — `aid-fsm.sh:2475`, `lib/delivery-checks/dg08-runtime-env.sh:109`,
      `tests/test-instruction-consistency.sh:90,158,169,180` — so "the per-file allowlist
      is re-derived" (plan:200) is more work than the sentence implies and must be
      verified against that concrete list or the boundary suite goes red.
    evidence: ".github/workflows/version-sync.yml:15; scripts/aid-fsm.sh:2475; scripts/lib/delivery-checks/dg08-runtime-env.sh:109; scripts/tests/test-instruction-consistency.sh:90,158,169,180; plan:200-202"
    suggested_fix: >
      Name the six pre-existing sites in the step's Implementation Detail as the
      re-derivation input, and state whether the scan's scope stays `scripts/` (and thus
      that `.github/` PCRE is a knowing exclusion).

  - severity: low
    ref: L3-10
    summary: >
      Step 12 registers the new rows in `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`,
      which is correct — that is the file `scripts/tests/test-enforcement-registry-test-audit.sh:18`
      actually reads and whose `totals:` block (line 50) it recomputes. Worth recording
      only because `CLAUDE.md` still names `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`,
      a path that no longer exists (the file moved to `docs/plans/archive/AID-audit-2026-06/`).
      The plan targets the live registry; no change needed to the plan, but an implementer
      following CLAUDE.md would edit a dead archive copy.
    evidence: "scripts/tests/test-enforcement-registry-test-audit.sh:18 `REGISTRY=\"${PLUGIN_DIR}/defaults/enforcement-registry.yaml\"`; `ls docs/plans/AID-audit-2026-06/` → No such file or directory; actual `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml`; plan:424"
    suggested_fix: >
      One sentence in Step 12 stating that `defaults/enforcement-registry.yaml` is the
      registry under test and the archived copy is history, so the implementer does not
      follow CLAUDE.md's stale path.

confidence: high
