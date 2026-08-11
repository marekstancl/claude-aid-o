# CP1-deep Adjudicator — P082

I read all 551 lines of `.aid-o/plans/P082-backlog-truth-and-live-holes.md` and all eight lens reports (L1/L2/L3 blocking, five C0 advisory), then verified the load-bearing claims against the live tree at `main` (`3da7331`, v2.83.1) rather than trusting any lens. First-hand spot-checks I ran myself: `git check-ignore` and a real `git add` probe against `docs/plans/archive/` (refused, `.gitignore:87`); `grep -n gate_profiles plugins/aid-orchestrator/defaults/execution.yaml` (absent) plus every reader of that file (none at runtime) and the resolver `_pfsm_has_gate_profiles` at `aid-plan-fsm.sh:9867-9877` with its verbatim "THE GUARD ON THE FLIP" comment recording the omission as deliberate; `render_gate_profiles_block` (`lib/aid-init-execution-yaml.sh:199-265`) emitting only `targeted`/`full` and a bare comment on zero stacks; the pre-commit hook's own statement at `defaults/hooks/pre-commit:34-40` that it cannot source a plugin lib, plus a grep proving it sources nothing; `aid-fsm.sh:6885-6907` — a DONE precondition, not an archival path, with no `mv` anywhere under `scripts/` and no `runs_completed` in the FSM at all; `aid-plan-to-epic.sh:1040-1075` and a live `_aid_files_bullet_tier` probe returning rc=1 on the plan's own Test bullet, with all four named suites confirmed missing on disk; `gates/scope-check.sh:28-42` wired as a required gate at `defaults/execution.yaml:104`; `aid-prefilter.sh:56-170` (checkpoint parsed at :61-76, `output_file` at :95, CP3's `merge-base`/`HEAD~5` guess at :150-166); the AC8 pattern run against a four-spelling fixture (matched 2 of 4) and against the live library (exit 1, two `grep -qP` at :24-25); both READMEs (no `## Roadmap` anywhere; root has `## Changelog` with 13 entries, plugin README has no version list); `aid-release.sh:645-670`/`:772-791` (rollback set omits the marketplace.json branches); `aid-plan-manifest.sh:1639` forwarding into the same function the legitimate producer uses at `aid-plan-fsm.sh:1122`; the live P080 worktree at `task/E-080-1_3/main` and P080's own rewrite of the `## Plan mode` section of `aid-init.md`; and the backlog's real heading count (126, not 101). The shape of the verdict: the plan's prose is excellent and its intent is right, but seven of its twelve steps are grounded against code that does not exist, is not the runtime path, or cannot be built as described — and the plan in its current form cannot even be generated into an EPIC.

verdict: fail

revision_count: 1

accepted_blockers:

  - ref: AB-1
    lenses: [L2, C0-reuse_compat, C0-planned_call_feasibility, C0-authority_runtime_matrix]
    severity: critical
    summary: >
      Step 1's central anti-drift mechanism — "the one shared predicate both callers
      source" — is unbuildable. One of the two callers is the git pre-commit hook, which
      /aid-init copies verbatim into a consumer's `.git/hooks/`, where no plugin cache
      path is resolvable. The hook's own header states this rule and already carries a
      deliberate hand-copy of a plugin lib function for exactly this reason; the shipped
      hook sources nothing at all. Implemented as written, the step either duplicates the
      rule anyway (the drift it exists to prevent) or makes the hook depend on a path it
      cannot see — which fails open in every consumer.
    evidence: >
      `plugins/aid-orchestrator/defaults/hooks/pre-commit:34-40` — "a consumer-repo hook
      cannot know the plugin cache path, so it cannot source the lib"; my own
      `grep -nE '^\s*(source|\.)\s' defaults/hooks/pre-commit` returns nothing (exit 1).
      Contradicts plan:73 "Create: `plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh`
      — the one shared predicate both callers source".
    required_change: >
      Restate Step 1 with the P074-precedented shape: the library is the single AUTHORING
      source for the FSM side; the hook carries a marked, generated copy; the anti-drift
      mechanism is a bats assertion of byte-equality between the hook's block and the
      library's function body over a shared case table. Say this in Files and in the AC,
      not in prose. "Both callers source it" must not appear.

  - ref: AB-2
    lenses: [L1]
    severity: critical
    summary: >
      Step 1 declares two consumers of the `allowed_paths` predicate. There are four, and
      the one omitted is BLOCKING: `gates/scope-check.sh` is wired as a required gate and
      matches each changed file against each entry with a bash `case` glob, in which `{`
      is not a metacharacter — so `migrations/{rev}_add_users.py` fails to admit
      `migrations/a1b2c3_add_users.py` there exactly as it does in the hook. A fourth rule,
      `_aid_ancillary_glob_match`, is used by the DONE routed-findings precondition.
      Implemented as written, Step 1 unblocks the commit and the run then dies at the
      GATES scope gate, so Success Criterion 1 is never reached, and the new library is a
      fifth predicate rather than "the one".
    evidence: >
      `plugins/aid-orchestrator/scripts/gates/scope-check.sh:33-42` (bash `case $pattern`,
      `VIOLATIONS` → exit 1); `plugins/aid-orchestrator/defaults/execution.yaml:100-107`
      (`scope_check`, `required: true`, `max_retries: 0`);
      `plugins/aid-orchestrator/scripts/lib/aid-ancillary.sh:124-147` consumed at
      `aid-fsm.sh:1382-1389`. Contradicts plan:71-73 and plan:481.
    required_change: >
      Name all four consumers in Step 1's Files with the outcome for each, decide whether
      the new predicate is built on the existing `_aid_ancillary_glob_match` or why a fifth
      is justified, and add an acceptance criterion that an Alembic-shaped entry passes the
      scope GATE, not only the hook.

  - ref: AB-3
    lenses: [L1, L2, C0-reuse_compat, C0-authority_runtime_matrix, C0-idempotency_matrix]
    severity: critical
    summary: >
      Step 2 edits a file with no runtime reader, and its premise is false. The release-mode
      resolver reads the CONSUMER file `${root}/.aid-o/config/execution.yaml`, which is never
      copied from `defaults/execution.yaml` — it is COMPOSED by `compose_execution_yaml`,
      which unconditionally appends `render_gate_profiles_block`. So a fresh project with any
      detected stack ALREADY gets a table and already resolves to `plan_branch`; the claim
      that "every project initialised from defaults silently falls back to per-EPIC releases"
      is wrong. Worse, the omission Step 2 wants to reverse is a recorded design decision with
      its reason written directly above the resolver. The real holes are elsewhere: the
      zero-detected-stack branch emits only a comment, and the emitted table carries two of the
      five profile names — a plan-branch project with no `release` profile hits a hard
      precondition failure.
    evidence: >
      `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:9861-9877` — "P064 adds it to THIS
      repository's self-host execution.yaml, not to the defaults/execution.yaml that /aid-init
      distributes, so a consumer project that merely upgrades the plugin would flip to
      plan_branch and resolve its gates against nothing at all"; `_pfsm_has_gate_profiles`
      opens `${root}/.aid-o/config/execution.yaml` (:9869);
      `lib/aid-init-execution-yaml.sh:238-241` (zero-stack comment) and `:255-265` (only
      `targeted` + `full`), invoked unconditionally at `:395`; my grep for readers of
      `defaults/execution.yaml` returns only CHANGELOG entries, one test and one runner
      comment. Contradicts plan:57 and plan:101-108.
    required_change: >
      Retarget Step 2's Files at `scripts/lib/aid-init-execution-yaml.sh`
      (`render_gate_profiles_block`), state the actual defects (zero-stack emits no table;
      the emitted table lacks `release`, which the plan-branch lifecycle requires), quote and
      explicitly override the recorded decision at `aid-plan-fsm.sh:9861-9866` if the
      plugin-upgrade-only population is meant to flip, and restate the AC against a workspace
      COMPOSED by `compose_execution_yaml` — with and without a detected stack — not "a
      workspace composed from the shipped template".

  - ref: AB-4
    lenses: [L2, L3]
    severity: critical
    summary: >
      The plan cannot be generated into an EPIC. `aid-plan-to-epic.sh` hard-fails on any
      `Test:` Files bullet naming a not-yet-existing suite without a `(tier: t0|t1|t2)`
      declaration, gated on tier adoption which is true in this repo. Four of the plan's Test
      bullets name new suites with no tier. EPIC 1 and EPIC 3 both abort at generation. The
      plan states the rule in prose at line 458 but does not carry it where the generator
      reads it.
    evidence: >
      `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:1055-1075` ("Test bullet names a
      NEW suite with no tier" → `error_exit`); my probe
      `source lib/aid-scoping.sh; _aid_files_bullet_tier "<Step 1 Test bullet>"` → rc=1; all
      four suites confirmed MISSING on disk. Plan lines 74, 137, 362, 394.
    required_change: >
      Add `(tier: tN)` to all four new-suite Test bullets in the canonical form
      `- Test: \`<path>\` (tier: t1) — <what it proves>`, pick the tier from measured cost per
      the standard, and note that each new file must additionally carry an `# aid-tier: tN`
      header or `run-all-tests.sh` refuses the whole portfolio and turns every gate red.

  - ref: AB-5
    lenses: [L3, C0-planned_call_feasibility, C0-idempotency_matrix]
    severity: critical
    summary: >
      Step 11's archive file cannot be committed. `.gitignore:87` excludes `docs/` wholesale;
      the single negation covers only the live backlog file, which survives because it is
      already tracked. So the closing evidence for 45 entries would be DELETED from a tracked
      file and land in an untracked one — gone on every fresh clone and in every CI checkout —
      and the step's own "append-only relative to the previous commit" assertion has no
      baseline. The `.gitignore` comment immediately above the negation records that this exact
      backlog file was already destroyed once for losing tracking; the plan recreates that
      failure for the archived half. `.gitignore` is not in Step 11's Files.
    evidence: >
      `git check-ignore -v docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md` →
      `.gitignore:87:docs/` (exit 0); real `git add` probe → "The following paths are ignored
      by one of your .gitignore files: docs" (exit 1). Contradicts plan:392-394.
    required_change: >
      Add `.gitignore` to Step 11's Files with an explicit narrow negation for the archive path,
      record that the first commit needs `git add -f`, and make the hygiene check assert the
      archive is TRACKED (`git ls-files --error-unmatch`) before it evaluates anything else —
      a check that cannot find its baseline must refuse, not pass.

  - ref: AB-6
    lenses: [L1, L2, C0-planned_call_feasibility, C0-idempotency_matrix]
    severity: critical
    summary: >
      Step 9's second half modifies a code path that does not exist. `aid-fsm.sh:6894-6907`
      is a read-only DONE precondition that fails when the task file is STILL in `tasks/` and
      tells a human to `mv` it — it passes precisely when there is no file left to restamp.
      No script under `scripts/` performs the move; archival is a controller/skill action. The
      `runs_completed` half is worse: nothing in the tree ever increments it — it is only ever
      written as literal `0` — so the AC "shows its terminal status and run count" reads a
      number no producer computes. The step's Test bullet has no FSM entry point to exercise.
    evidence: >
      `plugins/aid-orchestrator/scripts/aid-fsm.sh:6894-6906` (precondition + "Move to
      tasks/archive/ before advancing: mv ..."); my `grep -rn 'tasks/archive'
      plugins/aid-orchestrator/scripts --include=*.sh` returns ONLY that comment and that
      message; `grep -n runs_completed aid-fsm.sh` returns nothing. Contradicts plan:329 "the
      archival path: archiving a completed EPIC restamps its task frontmatter".
    required_change: >
      Name a real producer: either add an `archive-task` FSM subcommand (Create, not Modify)
      that performs the move AND the restamp and make the existing precondition accept only
      files archived through it, or move the restamp to the controller instruction and give it
      an enforcement. State where `runs_completed` gets its value or drop it from the AC and
      restamp `status` only. Make the restamp write absolute derived values, not an increment,
      and add an AC that restamping twice is byte-identical (the precondition is retried).

  - ref: AB-7
    lenses: [L1, L2, C0-reuse_compat, C0-authority_runtime_matrix, C0-idempotency_matrix]
    severity: critical
    summary: >
      Step 7 defers a decision it must make, and its preferred arm breaks the plan's own
      frozen-surface constraint. `verifier-output-step-N.md` is a hardcoded contract in at
      least seven places (the prefilter, the CP2 completeness sweep, the increment-step
      precondition whose wrong-checkpoint refusal this step's own AC requires to keep firing,
      the acceptance-evidence emitter, the output template, the pipeline skill and the verifier
      agent, which says "the format must not change"). Renaming it contradicts plan:463
      ("Frozen surfaces: evidence filenames") and would make the step's own AC vacuous. The
      stated root cause is also false: the checkpoint IS known 19 lines before the filename is
      assigned — the template simply omits it. And the repo already HAS a canonical CP3 name,
      `verifier-output-cp3-{focus}.md`, so the fix belongs inside the existing naming authority.
      The collision is additionally wider than declared: cp4 and cp6 overwrite CP2 output too.
    evidence: >
      `aid-prefilter.sh:61-76` (checkpoint parsed) and `:95` (`output_file` assigned, one name
      for cp2|cp3|cp4|cp6); consumers at `aid-fsm.sh:2477`, `:5705`, `:5756`,
      `aid-acceptance-evidence.sh:164`, `defaults/templates/verifier-output-template.md:15,39`,
      `agents/verifier.md:86,248`, `skills/pipeline.md:781-839`. Contradicts plan:58, plan:264
      and plan:463.
    required_change: >
      Decide in the plan, not "the step picks one": CP2's filename is frozen; the CP3 arm
      either writes the existing `verifier-output-cp3-{focus}.md` or the classify path refuses
      CP3 with a named error, with a pre-write guard that refuses to overwrite an existing
      output carrying a different `checkpoint:`. Correct the root-cause sentence (the template
      omits the checkpoint; there is no ordering bug), extend the objective and ACs to cp4 and
      cp6, and list every consumer in Files.

  - ref: AB-8
    lenses: [C0-planned_call_feasibility]
    severity: high
    summary: >
      Steps 3 and 12 anchor on a "roadmap section" that neither README has. The root README's
      version list lives under `## Changelog` and holds 13 entries; the plugin README has no
      version list at all, only `- **Plugin:** 2.83.1`. Under Step 3's own error handling ("No
      roadmap section found ⇒ warn and skip that file"), the new anchored edit skips BOTH
      READMEs on every release, silently stopping the update of version-registry location #7 —
      a regression on the current blind `sed`, which at least hits the line. Step 12's AC "the
      release's roadmap edit is recorded before and after" then has nothing to record. The
      "keeping three" rule applied to a 13-entry list also deletes ten tracked lines that no
      step authorises.
    evidence: >
      `grep -n 'Roadmap\|## Changelog' README.md plugins/aid-orchestrator/README.md` → only
      `README.md:118:## Changelog`; `README.md:120-132` = 13 entries;
      `plugins/aid-orchestrator/README.md:3` = `- **Plugin:** 2.83.1`. Contradicts plan:136,
      plan:143, plan:156 and plan:448. (Note: CLAUDE.md's "update the `## Roadmap` section"
      instruction is itself stale — the plan inherited the error.)
    required_change: >
      Name the real anchors: `## Changelog` in the root README, and the `- **Plugin:** X.Y.Z`
      line in the plugin README — a different edit, not a roadmap. State explicitly what
      happens to the 13-entry list (trim to three as a stated, reviewed content change, or
      leave the length alone) and add a bats case for it. Also state what happens to
      NON-anchored version references the current global `sed` updates today (badges, install
      snippets in consumer READMEs) — after Step 3 they stop being updated, which is an
      undeclared user-visible regression — and fix the sibling `grep -q "Plugin: $CURRENT"`
      matcher, which never fires today because the real text is `- **Plugin:** 2.83.1`.

  - ref: AB-9
    lenses: [L2, L3, C0-authority_runtime_matrix]
    severity: high
    summary: >
      This is the plan-level question, and the lenses are right. The three P081 leftovers added
      to Scope at line 37 — (a) the durations journal under `.aid-o/` in the CI checkout, (b)
      156 of 161 T2 suites tiered by subject-resolution failure, (c) the unread quarantine
      flags — have NO implementing step, NO test and NO success criterion anywhere in Steps
      1-12 or in Success Criteria 1-6. I confirmed this against the plan text: the words
      "durations", "quarantine" and "nightly" appear only in the narrative (lines 14, 22, 37,
      44, 45, 458, 462), never in a step. The plan would close claiming them fixed. Item (c)'s
      premise is additionally half false: `quarantine_unreadable` IS read and surfaced in the
      alert; only `quarantine_write_failed` is write-only. Item (a) also forces an
      undeclared decision about a shared host path used by other projects.
    evidence: >
      `grep -n 'duration\|quarantine\|nightly' P082-...md` → lines 37 and 44 only, both prose;
      real subjects exist and are untouched: `scripts/lib/aid-test-durations.sh:62`,
      `scripts/aid-test-tier-assign.sh`, `scripts/aid-nightly-report.sh:162,187,231-237` with
      its single reader at `:255` (`quarantine_unreadable` → alert message);
      `.github/workflows/nightly-tests.yml` (host path `/opt/eco/data/aid-nightly/...`).
    required_change: >
      Either add explicit steps that name their files (a durations-journal relocation naming
      `lib/aid-test-durations.sh` and the workflow, with the journal's home and its
      writer/reader authority stated; a re-tier pass naming `aid-test-tier-assign.sh` and the
      affected suites with recorded reasons; a consumer for `quarantine_write_failed` in
      `/aid-status`'s `nightly_line()` or an unconditional alert), each with its own AC and
      success criterion — or move all three to Out of scope with a named successor plan.
      Leaving work in Scope with no step is not acceptable. If they stay, narrow (c) to
      `quarantine_write_failed`.

  - ref: AB-10
    lenses: [L3]
    severity: critical
    summary: >
      Step 10 ships the dogfood ref-isolation guard as a library and wires no caller. The two
      live dogfood entry points exist and are absent from the step's Files, so AC6 is
      satisfiable entirely by a fixture that calls the library directly — it would pass green
      while a real dogfood run still shares refs with the repository under test, which the plan
      itself says has already advanced the real branch once. Step 12 then registers this in the
      enforcement registry, recording an enforcement no execution path invokes. This is the
      literal Principle #1 violation ("Detector without Enforcement is Decoration") that this
      repository treats as binding.
    evidence: >
      plan:360-362 and plan:379-382; live entry points confirmed present:
      `plugins/aid-orchestrator/scripts/tests/e2e/c3-dogfood.sh` and
      `.../e2e/c3-dogfood-real-ac.sh`, neither in the Files list.
    required_change: >
      Add both e2e dogfood entry points to Step 10's Files (and reconcile with any existing
      common-dir comparison already in `aid-test-audit-profile.sh` — one predicate, not two),
      and reword AC6 so it asserts a real dogfood invocation is refused, not that the library
      returns non-zero.

  - ref: AB-11
    lenses: [C0-dep_api_grounding, L1, L2, C0-planned_call_feasibility]
    severity: high
    summary: >
      The plan's only concrete PCRE-detection pattern — AC8's — cannot match two of the four
      spellings Step 5 explicitly promises to catch. I reproduced it: against a fixture holding
      `-Pq`, `--perl-regexp`, `-qP` and `-oP`, the AC8 pattern matched only the last two.
      `-Pq` fails because `\b` requires a non-word character after `P`; `--perl-regexp` has no
      capital `P` at all. If the implementer reuses AC8's pattern as "the widened detector"
      (it is the only pattern the plan supplies), the rebuilt guard reproduces exactly the
      defect the step exists to fix. Compounding: `\b` is itself a GNU-only ERE extension, and
      AC8 is phrased as a negation, so on a non-GNU grep a non-match reports PASS — a false
      green on precisely the hosts the invariant protects. AC8 also has no comment exclusion,
      unlike the existing IMP-274 guard, so a correctly-fixed file whose comment explains the
      fix fails its own AC.
    evidence: >
      My run: `/bin/grep -nE 'grep[^|;]*-[A-Za-z]*P\b' /tmp/pcre-fix.sh` matched lines 3 and 4
      only (the `-Pq` and `--perl-regexp` lines were NOT matched). Live:
      `bash -c '! grep -nE "grep[^|;]*-[A-Za-z]*P\b" .../lib/aid-review-signals.sh'` → exit 1,
      hits `:24` and `:25`. Contradicts plan:207 and plan:214 against plan:543.
    required_change: >
      Replace AC8's pattern with one that has no trailing-`\b` dependency and covers the long
      form (e.g. `grep([[:space:]]+-[A-Za-z]*P([[:space:]]|$)|[[:space:]]+--perl-regexp)`), add
      a comment exclusion mirroring the existing guard, state in Step 5 that the self-test
      fixture MUST contain all four spellings (fixture-completeness assertion), and instruct
      that the replacement patterns in `aid-review-signals.sh` use `[[:space:]]` rather than
      `\s` — which is also GNU-only, so a naive `-qP` → `-qE` keeps the defect while satisfying
      the plan's text. Also declare the behaviour change: after the fix, `enabled: false`
      sections stop being silently ignored on non-GNU grep, which can flip a previously-passing
      compliance/release verdict.

  - ref: AB-12
    lenses: [L1, L2, C0-reuse_compat]
    severity: high
    summary: >
      Step 4 speaks of "the awk block that emits acceptance criteria" as if there were one.
      There are two, ~25 lines apart, with identical extraction logic: `step_ac` feeds the
      human-facing flattened section, `step_ac_raw` feeds the machine-facing per-step `ac[]`
      block that `aid-epic-to-json.sh` turns into `acceptance_criteria[]` and that the contract
      gate treats as authoritative. The plan's line range covers only the first. Fixing one
      leaves the machine-facing criterion truncated while the human-facing one is whole — the
      opposite of the step's intent, and exactly the "one rule with two drifting copies" shape
      the plan says it exists to end. Separately, the step's justification is false: the
      Files-bullet grammar it claims to mirror captures only column-0 dashes and silently DROPS
      indented continuations; it never joins them. The plan is inventing a rule, not reusing one.
    evidence: >
      `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:909-925` (`step_ac`) and `:936-950`
      (`step_ac_raw`); `lib/aid-scoping.sh:126-138` (`_AID_FILES_BULLETS_AWK`, drops
      continuations); `gates/aid-contract-validate.sh:346`. Contradicts plan:167 and plan:172.
    required_change: >
      Name both awk blocks in Files (or factor the extraction into one shared awk program in
      `lib/aid-scoping.sh` as `_AID_FILES_BULLETS_AWK` already is), add an AC that the flattened
      section and the per-step `ac[]` carry byte-identical joined text, and rewrite the
      Implementation Detail to say this INTRODUCES a continuation rule.

  - ref: AB-13
    lenses: [C0-authority_runtime_matrix]
    severity: high
    summary: >
      Step 2 modifies `commands/aid-init.md` while another plan is mid-run on exactly that
      file. P080's worktree is live, and P080 rewrites aid-init.md substantively — including
      MOVING the very `## Plan mode` section Step 2 edits, delisting the file from the
      test-skill-lint GRANDFATHERED array, and adding an AC that the file lints clean. P082's
      Constraints sequence only against P081 and never mention P080. A P082 edit landing
      concurrently is a merge collision at best and a silently reverted lint-clean state at
      worst.
    evidence: >
      `git worktree list` → `/opt/eco/projects/aid-orchestrator/.aid-worktrees/plan-P080
      4c65b59 [task/E-080-1_3/main]`;
      `.aid-o/plans/P080-entrypoint-ux-help-handoffs.md:215` ("Move the `## Plan mode` section
      (lines ~682-696) above the `**Last Updated:**` footer"), `:218`, `:242`. Contradicts
      plan:462 (Constraints name P081 only).
    required_change: >
      Add P080 to the Constraints as a hard ordering: Step 2's aid-init.md edit lands only
      after P080 merges, against P080's post-merge line numbers; if P080 is still open, the
      prose edit moves to a P080 follow-up. Add the lint-clean AC so a P082 edit cannot
      re-dirty a file P080 just delisted.

  - ref: AB-14
    lenses: [C0-authority_runtime_matrix]
    severity: high
    summary: >
      Step 10 says the `add-epic` subcommand "no longer accepts a lineage argument (or is
      removed)". The CLI dispatcher forwards straight into the shared function, and that SAME
      function is how the one legitimate producer asserts provenance. An implementer reading
      "no longer accepts a lineage argument" as "drop the 8th parameter" would silently disarm
      the only authorised producer, turning every epic-start into `unproven` — an authority
      change in the opposite direction — and the step's negative test (CLI cannot mint proven)
      would still pass.
    evidence: >
      `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh:1639`
      (`add-epic) plan_manifest_add_epic "$@"`) vs the legitimate producers at
      `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:1122` and `:8973`. Plan:361.
    required_change: >
      State that the restriction lives in `main()`'s dispatcher (reject an 8th positional on
      the `bash aid-plan-manifest.sh add-epic` path), that the sourced `plan_manifest_add_epic`
      KEEPS its optional lineage parameter, and add a POSITIVE AC that `epic-start` still
      writes `lineage: proven` after the change — not only the negative CLI test.

  - ref: AB-15
    lenses: [C0-idempotency_matrix]
    severity: high
    summary: >
      Step 12 is the plan's own first live exercise of `aid-release.sh`, and Step 3 edits the
      same function, but neither addresses a reproduced defect in it: the release rollback does
      not restore `.claude-plugin/marketplace.json`, because the `metadata.version` and
      `plugins[0].version` branches deliberately skip `UPDATED+=(...)` while the rollback
      iterates exactly `UPDATED[]`. An aborted release therefore strands marketplace.json at a
      version nobody released, and the next invocation's jq equality test no longer matches, so
      it is never repaired. Step 12's AC "All eight version locations agree" is the first thing
      that would fail.
    evidence: >
      `plugins/aid-orchestrator/scripts/aid-release.sh:650-661` (both branches update the file
      and print, but only the `.version` branch at `:647` pushes to `UPDATED`; comment "# Don't
      double-add") vs `_release_rollback_updated` at `:780-788` iterating `"${UPDATED[@]:-}"`.
      Plan:136, plan:427, plan:447.
    required_change: >
      Add the one-line fix to Step 3's Files — push `$jf` into `UPDATED[]` on the metadata and
      plugins[0] branches too, deduping on push — and add an AC that an aborted release leaves
      every version file at the pre-run version, proven by running the script twice.

rejected_blockers:

  - ref: L2-8
    rejection_reason: >
      REFUTED first-hand. The lens claims `README.md:120-123` carries FOUR roadmap lines. There
      is no roadmap section in either README; the root README's list lives under `## Changelog`
      at `README.md:118` and holds THIRTEEN entries, and the plugin README has no version list
      at all. The underlying concern (the "keeping three" rule is a destructive content change
      the plan does not authorise) is real but is stated correctly only by
      C0-planned_call_feasibility, and is folded into AB-8. Filed at the wrong count and the
      wrong anchor, it would have sent an implementer to a section that does not exist.

  - ref: L1-B3 / L2-1 / C0-RC-4 / C0-IM-8 (as separate blockers)
    rejection_reason: >
      Not rejected on the merits — MERGED into AB-7. Four independent lenses found the same
      frozen-filename collision; counting them separately would inflate the blocker count. The
      corroboration is recorded in AB-7's `lenses` list and materially strengthens it, and
      C0-authority_runtime_matrix's contribution (the repo already HAS
      `verifier-output-cp3-{focus}.md`) is what makes the required change concrete rather than
      a choice between two bad arms.

  - ref: L1-5
    rejection_reason: >
      Correct but not blocking-tier. No shipped instruction passes `--checkpoint cp3` today, so
      Steps 6 and 7 are hardening-before-use rather than closing a live incident. This changes
      the plan's priority framing and should be stated, but it does not make any step
      unimplementable or wrong. Kept as advisory.

  - ref: L1-4 / C0-RC-7
    rejection_reason: >
      Reduced to advisory. Step 8's premise is factually correct (I confirmed the runner writes
      `${evidence_dir}/gates/gates_report.json` while the streamlined check reads the flat
      sibling), and the fix is right. Only the surrounding CLAIMS are wrong — "one constant, one
      reader" and "the last consumer still on the pre-consolidation path" are both false, since
      two other readers do a root-then-`gates/` fallback and `aid-plan-close-check.sh` is
      flat-only. Worth correcting in the step, but it does not block: an implementer who adopts
      the same fallback the other readers use lands in the right place.

  - ref: L2-10 / L3-10
    rejection_reason: >
      Not findings against the plan — confirmations that the plan targets the correct
      enforcement registry while CLAUDE.md's path is stale. Kept as advisory so the step is not
      "corrected" to the wrong file during implementation.

  - ref: L2-9 / C0-PCF-5 / C0-DAG-2 (as separate blockers)
    rejection_reason: >
      MERGED into AB-11. All three concern AC8's GNU-only `\b`; C0-dep_api_grounding is the one
      that proved mechanically that the pattern misses two of the four promised spellings, which
      is what lifts the cluster to blocking.

  - ref: L1-1 / L2-B4 / C0-PCF-2 / C0-IM-6 (as separate blockers)
    rejection_reason: >
      MERGED into AB-6. Four lenses, one defect, verified by me directly.

  - ref: L3-1 / C0-PCF-4 / C0-IM-3 (as separate blockers)
    rejection_reason: >
      MERGED into AB-5.

  - ref: L2-B1 / C0-RC-1 / C0-PCF-1 / C0-ARM-1 (as separate blockers)
    rejection_reason: >
      MERGED into AB-1. Note that AB-2 (the four consumers, one of them a blocking gate) is a
      genuinely DIFFERENT Step 1 defect with a different required change, and is kept separate
      deliberately.

advisory_findings_worth_keeping:

  - ref: L3-5
    summary: > Step 11's "append-only relative to the previous commit" cannot run on CI's
      depth-1 shallow checkout; either drop the history assertion or make it refuse loudly on a
      shallow repo.

  - ref: C0-IM-5
    summary: > The append-only assertion contradicts the plan's own reversibility mitigation —
      moving a wrongly-archived entry back deletes an archive line and is refused by the check
      the step introduces.

  - ref: C0-IM-4
    summary: > The archive is `Create:` with no destination-exists rule and a month-granular
      filename; a resumed Step 11 either duplicates entries (the hygiene check tests no
      uniqueness) or silently drops an earlier pass.

  - ref: L3-7, L3-8
    summary: > Three of the plan's regressions land in T2 suites off the merge path, and the
      widened portability detector's own suite is both T2 and delegated — so the plan's claim
      that its defects "cannot return unnoticed" is true of the nightly, not of a merge. State
      which pins are merge-blocking.

  - ref: C0-RC-5, C0-DAG-3, C0-DAG-4, L3-9
    summary: > "The per-file allowlist is re-derived" is far more work than the sentence implies:
      the allowlist is a provenance ledger declared shrink-only, `test-instruction-consistency.sh`
      goes 2 → 5 under the widened pattern (a forbidden GROW), the `aid-release.sh 3` row has
      scanned as 0 for its whole life, and the scanner walks only `*.sh` so `-oP` in
      `test-aid-release.bats` and `.github/workflows/version-sync.yml` stays invisible.

  - ref: C0-IM-2
    summary: > Step 3's re-run rule keys on the wrong state — a run dying between insert and
      demote leaves two `(current)` lines, which `verify-version-files.sh`'s `grep -m1` cannot
      see and the no-op rule then freezes forever. Make the edit atomic and assert "exactly one
      `(current)` line".

  - ref: C0-ARM-2
    summary: > The file that blocks commits is the INSTALLED `.git/hooks/pre-commit`, not the
      template; this repo's own installed hook is 254 lines against the template's 330 and
      predates P074, so P082's own EXECUTE commits would run a hook that never receives the fix.
      No step re-installs hooks and no test detects template/installed divergence.

  - ref: C0-IM-7
    summary: > `cmd_set_field` is routinely re-invoked on controller retry, so the new
      `fsm_field_change` journal is retry-tolerant by design; say that any "state matches events"
      reader must fold on the LAST event per field, never count occurrences.

  - ref: L2-6
    summary: > CP2 and CP3 want deliberately DIFFERENT resolution orders (a step boundary would
      give CP3 a too-narrow full-EPIC range), so "one shared helper" must take the priority order
      as a parameter; and Step 6's Files range covers only the CP3 branch, not the CP2 machinery
      it would have to move.

  - ref: L1-8
    summary: > The plan's own counts are stale against the tree it will run on: the backlog has
      126 headings, not 101 (I confirmed), and Context says v2.82.0 while the tree is v2.83.1.
      Also, at least one live document cites the backlog by SECTION name, which a preserved
      filename does not preserve.

  - ref: C0-IM-9
    summary: > Nothing today copies `defaults/execution.yaml` into a project, but if any path
      ever seeds a workspace from the template and then runs the composer, the file carries two
      top-level `gate_profiles:` keys and the presence-only upgrade guard cannot notice.

  - ref: L2-10 / L3-10
    summary: > `defaults/enforcement-registry.yaml` is the registry under test; CLAUDE.md still
      names an archived path. Say so in Step 12 so the implementer is not "corrected" into
      editing a dead copy.
