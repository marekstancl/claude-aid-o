# CP1-deep — Lens L2 FEASIBILITY — P082

I read the whole plan, then verified every named file, line range and premise against the real tree at `3da7331` (v2.83.1, `main`). Concretely: I existence-checked all 25 paths the plan names; opened and read `_aid_in_scope` (`defaults/hooks/pre-commit:87-96`), the FSM scope companion (`aid-fsm.sh:6032-6074`), `cmd_set_field` (`aid-fsm.sh:6090-6120`), the DONE precondition block at `aid-fsm.sh:6894-6907`, `fsm_check_streamlined_integration_review` (`aid-fsm.sh:1817-1854`), `aid-prefilter.sh:56-165`, both AC-extraction awk blocks in `aid-plan-to-epic.sh` (909-925, 936-948), the IMP-274 portability scanner (`test-aid-plan-release-boundary.bats:7220-7260`), `aid-review-signals.sh:24-25`, `aid-release.sh:334-350` and `:665-676`, `plan_manifest_add_epic` + its CLI dispatch (`aid-plan-manifest.sh:997-1024, 1622-1639`), `compose_execution_yaml` / `render_gate_profiles_block` (`lib/aid-init-execution-yaml.sh:199-267, 316-400`), and `_pfsm_has_gate_profiles` / `_pfsm_default_mode` (`aid-plan-fsm.sh:9858-9900`). I ran `aid-plan-to-epic.sh` against the plan itself (it stops at the CP1 gate, as expected), then isolated the Files-bullet tier check by sourcing `lib/aid-scoping.sh` and calling `_aid_files_bullet_tier` on the plan's four new-suite `Test:` bullets, and confirmed `_p081_tiers_adopted` returns yes in this repo. I also ran `aid-test-tier-lint.sh` (PASS, 202 suites) and executed AC8's literal command. All temporary probe plans and evidence stubs I created were deleted; `git status` is clean.

stop_rule_blockers:

  - ref: L2-B1
    severity: critical
    summary: >
      Step 1 declares `Create: plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh`
      as "the one shared predicate both callers source". The pre-commit hook cannot
      source a plugin lib, and the repository says so in the hook itself:
      `defaults/hooks/pre-commit:36-40` — "`_aid_state_root` is a deliberate tiny COPY
      of the plugin lib resolver (scripts/lib/aid-roots.sh `aid_state_root`, minus
      caching): a consumer-repo hook cannot know the plugin cache path, so it cannot
      source the lib." The hook is installed into a consumer project's `.git/hooks/`
      with no `AID_PLUGIN_PATH` and no resolver for one; `_aid_emit` at line 70 carries
      the same note ("No lib dependency; never fails the commit"). The step as written
      cannot be implemented; the sourcing model is the step's stated architectural point
      ("so a future third consumer cannot invent a third rule").
    evidence: plugins/aid-orchestrator/defaults/hooks/pre-commit:36-40 and :69-70; plan line 73
    suggested_fix: >
      Restate Step 1 as a generated/asserted COPY, not a shared source: keep the canonical
      predicate in `scripts/lib/aid-scope-match.sh` for the FSM companion, embed the same
      body in the hook block, and make the bats suite assert byte-equality of the two
      copies over a shared case table (the step's own Test bullet already asks the two to
      "agree on every case"). Name the copy-drift assertion as the mechanism.

  - ref: L2-B2
    severity: critical
    summary: >
      Step 2 names the wrong producer, so its objective and AC cannot follow from its
      edit. The consumer of the gate table is `_pfsm_has_gate_profiles`
      (`aid-plan-fsm.sh:9868-9877`), which reads `${root}/.aid-o/config/execution.yaml`
      — the PROJECT's file. A fresh project's file is not copied from
      `defaults/execution.yaml`; it is COMPOSED by `compose_execution_yaml`
      (`lib/aid-init-execution-yaml.sh:316`), invoked from `commands/aid-init.md:120-124`,
      which at line 395 unconditionally appends `render_gate_profiles_block`. Nothing in
      the tree copies `defaults/execution.yaml` into a project — its only referents are
      three bats suites and `test-instruction-consistency.sh:108`. So a fresh project
      with any detected stack ALREADY gets a `gate_profiles` table and already resolves
      to `plan_branch`, and adding a table to `defaults/execution.yaml` changes nothing
      for any consumer. The real gap, if one exists, is inside
      `render_gate_profiles_block` (`lib/aid-init-execution-yaml.sh:206-266`): it emits
      only `targeted` and `full`, not the five canonical ranks
      (`quick < targeted < standard < full < release`,
      `lib/aid-gate-profile.sh:87`), and emits only a comment line when zero stacks are
      detected (:238-241) — which is the one case that does fall back to legacy mode.
    evidence: |
      plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:9868-9877 (reads .aid-o/config/execution.yaml)
      plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:391-395 (compose always calls render_gate_profiles_block)
      plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:238-241 (zero-stack case emits a comment, no table)
      plan line 104: "Modify: `plugins/aid-orchestrator/defaults/execution.yaml` … so the plan-mode default resolves to `plan_branch` for a fresh project"
    suggested_fix: >
      Retarget Step 2 at `scripts/lib/aid-init-execution-yaml.sh`
      (`render_gate_profiles_block`) and state the actual defect: the zero-detected-stack
      path emits no table (→ legacy fallback), and the emitted table covers 2 of the 5
      profile names the resolver can return. Keep the `defaults/execution.yaml` edit only
      if the plan also states what reads that file. Rewrite AC1 of the step as "a
      workspace COMPOSED by `compose_execution_yaml` with zero detected stacks resolves
      to plan_branch (or records the named reason)" so it is checkable against the real
      producer.

  - ref: L2-B3
    severity: critical
    summary: >
      The plan cannot be generated into an EPIC as written. `aid-plan-to-epic.sh:1033-1067`
      hard-fails (`error_exit`, :1073-1075) on any `Test:` Files bullet that names a
      not-yet-existing suite without a `(tier: t0|t1|t2)` declaration, gated on
      `_p081_tiers_adopted` (:825-835), which returns yes in this repo. Four of the plan's
      `Test:` bullets name new suites with no tier: Step 1
      (`tests/bats/test-scope-placeholder-match.bats`, plan:74), Step 3
      (`tests/bats/test-aid-release-readme.bats`, plan:137), Step 10
      (`tests/bats/test-dogfood-guard.bats`, plan:362), Step 11
      (`tests/test-backlog-hygiene.sh`, plan:394). All four match the suite path patterns
      at :1048 and none exists on disk (verified), so `_names_suite=true` and
      `_names_new_suite=true`. Sourcing `lib/aid-scoping.sh` and calling
      `_aid_files_bullet_tier` on each of the four bullets returns rc=1, tier empty —
      exactly the ":1065 Test bullet names a NEW suite with no tier" refusal. EPIC 1 and
      EPIC 3 generation will both abort. The plan is aware of the rule in prose
      (line 458, "new suites declare their tier") but does not carry it in the Files
      blocks, which is where the generator reads it.
    evidence: |
      plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:1064-1065 and :1073-1075
      probe: bash -c 'source plugins/aid-orchestrator/scripts/lib/aid-scoping.sh; _aid_files_bullet_tier "Test: `plugins/aid-orchestrator/scripts/tests/bats/test-scope-placeholder-match.bats` — …"' → rc=1, tier=""
      plan lines 74, 137, 362, 394
    suggested_fix: >
      Add the tier declaration to all four new-suite Test bullets in the canonical form
      `- Test: \`<path>\` (tier: t1) — <what it proves>`. Cheap shell/bats regressions of
      this shape are t0/t1; pick from measured cost per the standard, and note that
      `aid-test-tier-lint.sh` additionally requires an `# aid-tier: tN` header line in
      each new file.

  - ref: L2-B4
    severity: high
    summary: >
      Step 9's second Files bullet points at code that does not exist. It says
      "Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6890-6910) — the
      archival path: archiving a completed EPIC restamps its task frontmatter". Lines
      6894-6907 are not an archival path — they are a DONE precondition that asserts the
      task file has ALREADY been moved out of `tasks/`, and it passes precisely when
      `find` returns nothing, i.e. when there is no file to restamp. There is no `mv` to
      `tasks/archive/` anywhere under `scripts/`: the only two matches are the comment at
      :6894 and the operator hint at :6905. Archival is a controller/skill action
      (`skills/run-management.md:167`, `:246`). Consistently, `runs_completed` appears
      nowhere in `aid-fsm.sh` — only in `aid-plan-to-epic.sh:1463` (generation) and
      fixtures. The step's Test bullet ("archival restamps the frontmatter" in
      `test-aid-fsm.bats`) therefore has no FSM entry point to exercise.
    evidence: |
      plugins/aid-orchestrator/scripts/aid-fsm.sh:6894-6907 (precondition, not archival)
      grep -rn "tasks/archive" --include=*.sh plugins/aid-orchestrator/scripts → only :6894 comment and :6905 hint
      grep -rn "runs_completed" plugins/aid-orchestrator/scripts/aid-fsm.sh → no matches
      plugins/aid-orchestrator/skills/run-management.md:167
    suggested_fix: >
      Either (a) split the restamp into a new FSM subcommand (e.g. `aid-fsm.sh
      archive-task <epic_id>`) that performs the move AND the restamp, make the existing
      precondition at :6894 accept only files archived through it, and list that
      subcommand's file/line as the change; or (b) move the restamp to the controller
      instruction (`skills/run-management.md`) and give it an enforcement — the FSM
      precondition additionally checking the archived file's `status`/`runs_completed`.
      Naming a mechanism at design time is required by AID-v3-principles.md §1.

findings:

  - severity: high
    ref: L2-1
    summary: >
      Step 7's Files list is materially incomplete and its preferred option violates the
      plan's own Constraints. The step names only `aid-prefilter.sh` (~90-100) and one
      bats file, but `verifier-output-step-${step_n}.md` is a hardcoded contract in at
      least three other producers/readers: `aid-fsm.sh:2477` (CP2 completeness sweep),
      `aid-fsm.sh:5705` (the increment-step precondition, whose wrong-checkpoint refusal
      at :5756 the step's own AC requires to keep firing), and
      `aid-acceptance-evidence.sh:164` (`evidence_ref` emission), plus
      `defaults/templates/verifier-output-template.md:15,39`, `skills/pipeline.md:781-839`
      and `agents/verifier.md:86,248`. Changing the filename to carry the checkpoint
      breaks every one of them. It also directly contradicts plan line 463: "Frozen
      surfaces: evidence filenames, machine-facing JSON field names…".
    evidence: |
      plugins/aid-orchestrator/scripts/aid-prefilter.sh:96
      plugins/aid-orchestrator/scripts/aid-fsm.sh:2477, :5705, :5756
      plugins/aid-orchestrator/scripts/aid-acceptance-evidence.sh:164
      plan line 264 ("the output filename is derived after the checkpoint is known and carries it") vs plan line 463 ("Frozen surfaces: evidence filenames")
    suggested_fix: >
      Resolve the alternative at plan time instead of deferring it to "the step picks one":
      given the frozen-filename constraint, choose the refusal branch — CP3 is refused for
      the classify path with a named error, or a pre-write guard refuses to overwrite an
      existing output whose recorded `checkpoint:` differs. If the filename option is kept
      instead, list all seven consumers in Files and lift the frozen-surface constraint
      explicitly.

  - severity: high
    ref: L2-2
    summary: >
      Step 7's stated root cause is factually false. Plan line 58 says the prefilter
      "computes its output filename before it knows the checkpoint", and line 264 repeats
      it. In `aid-prefilter.sh` the `--checkpoint` flag is parsed at :62-77 and
      `output_file` is assigned at :96 — the checkpoint is fully known 19 lines earlier.
      The collision is real, but its cause is simply that the filename template omits the
      checkpoint, not an ordering bug. An implementer following the plan would look for a
      reordering that does not exist.
    evidence: plugins/aid-orchestrator/scripts/aid-prefilter.sh:62-77 (checkpoint parsed) and :96 (output_file assigned); plan lines 58 and 264
    suggested_fix: >
      Rewrite the premise: "the output filename template omits the checkpoint, so a CP3
      classify run writes to the CP2 path and destroys valid CP2 evidence" — and drop the
      ordering claim.

  - severity: high
    ref: L2-3
    summary: >
      Three items are declared IN SCOPE at plan line 37 — (a) the durations journal
      written under `.aid-o/` in the CI checkout, (b) 156 of 161 T2 suites tiered by
      subject-resolution failure, (c) the unread `quarantine_write_failed` /
      `quarantine_unreadable` keys — and no step among Steps 1-12 implements any of them.
      Steps 1-12 cover pre-commit scope, `defaults/execution.yaml`, README release edit,
      plan→EPIC AC wrapping, `grep -oP`, CP3 range, prefilter collision, streamlined
      report path, set-field/archival, dogfood guard, backlog split, and registry+release.
      None touches `scripts/lib/aid-test-durations.sh`, `scripts/aid-test-tier-assign.sh`,
      `scripts/aid-nightly-report.sh` or `.github/workflows/nightly-tests.yml`. The
      Success Criteria (lines 481-486) also omit all three. A generated EPIC will silently
      not contain them.
    evidence: |
      plan line 37 (scope) vs plan lines 64-451 (Steps 1-12) — no step names any of the three subjects
      real subjects exist: plugins/aid-orchestrator/scripts/lib/aid-test-durations.sh (sourced at scripts/aid-test-tier-assign.sh:45), plugins/aid-orchestrator/scripts/aid-nightly-report.sh:187-237
    suggested_fix: >
      Either add explicit steps (a durations-journal relocation step naming
      `lib/aid-test-durations.sh` + the workflow; a re-tier step naming
      `aid-test-tier-assign.sh` and the affected suites; a nightly-consumer step naming
      `aid-nightly-report.sh` and `commands/aid-status.md` `nightly_line()`), or move the
      three items to Out of scope with a reason. Do not leave them in Scope with no step.

  - severity: high
    ref: L2-4
    summary: >
      Step 3 requires input the release script does not have. It says to "insert a new
      `- **vX.Y.Z** (current) — …` line" into the roadmap, but `aid-release.sh` has no
      summary argument, no `--summary` flag and no summary variable anywhere (its usage
      block is at :3-9; `grep -n "summary"` matches only two comment lines at :456 and
      :492). Today's global `sed s/v$CURRENT/v$NEW_VERSION/g` (:668) sidesteps the
      problem by rewriting the version token in place and carrying the OLD summary
      forward — which is itself a defect, but it means the anchored rewrite needs a text
      source that must be designed. Step 3's Files list names only `aid-release.sh`
      (~655-680) and a new bats file, so no plumbing for the new input is planned, and no
      AC checks that the inserted summary is correct.
    evidence: plugins/aid-orchestrator/scripts/aid-release.sh:3-9 (usage, no summary), :665-676 (the sed), plan line 136
    suggested_fix: >
      State where the roadmap summary text comes from — most naturally the first
      `### Added`/`### Changed` bullet of the target version's CHANGELOG section (already
      parsed by the placeholder checker at :655+), or a new required `--summary` argument
      threaded through both `cmd_prepare_plan` and the legacy path. Add the plumbing to
      Files and an AC that pins it.

  - severity: medium
    ref: L2-5
    summary: >
      Step 4 names one awk block but there are two identical ones. The step says
      "Modify: `aid-plan-to-epic.sh` (lines ~885-910) — the awk block that emits
      acceptance criteria". The `step_ac` block is at :909-925 and a second,
      byte-equivalent extraction, `step_ac_raw`, is at :936-948 — same header match, same
      `^-[[:space:]]` item rule, same silent drop of continuation lines. `step_ac` feeds
      the flattened `## Acceptance Criteria` section; `step_ac_raw` feeds the per-step
      scoping block's `ac[]`. Fixing only one produces exactly the "one rule with two
      drifting copies" shape the plan says it is fighting (line 456): the flattened AC
      would carry the wrapped criterion and the per-step `ac[]` would not.
    evidence: plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:909-925 and :936-948; plan line 167
    suggested_fix: >
      Name both blocks in Files (or factor them into one shell function used by both), and
      add an AC that the flattened `## Acceptance Criteria` section and the per-step
      `ac[]` carry byte-identical criterion text for a wrapped criterion.

  - severity: medium
    ref: L2-6
    summary: >
      Step 6's "one shared helper" AC is under-specified against two deliberately
      DIFFERENT resolution orders. CP2 resolves step_commit-from-timeline first, then
      `base_commit`, then refuses (`aid-prefilter.sh:106-147`, order documented at
      :110-113). CP3 wants the EPIC base first — a step boundary would give it the wrong
      (too narrow) range for a full-EPIC diff. Plan line 233 nonetheless prescribes that
      CP3 "adopts the CP2 resolution order: the recorded base, else the step boundary",
      and AC2 (line 253) requires "CP2 and CP3 resolve through one shared helper". A
      single helper with one fixed order would either change CP2's classification —
      contradicting the step's own "with a recorded base it classifies exactly as today"
      — or silently narrow CP3. Separately, the step's Files range (~155-170) covers only
      the CP3 branch (:148-165); extracting a shared helper also has to move the CP2
      machinery at :106-147, which the Files list does not mention.
    evidence: plugins/aid-orchestrator/scripts/aid-prefilter.sh:106-147 (CP2) and :148-165 (CP3); plan lines 233, 238, 249, 253
    suggested_fix: >
      Say that the shared helper takes the priority order as a parameter (CP2:
      step_commit → base_commit → refuse; CP3: base_commit → refuse), so only the refusal
      and the observe-escape are shared. Extend Files to `aid-prefilter.sh:106-165`.

  - severity: medium
    ref: L2-7
    summary: >
      Scope item (c) is half false as stated. Plan line 37 says the nightly "writes
      `quarantine_unreadable` and `quarantine_write_failed` that no consumer reads".
      `quarantine_unreadable` IS read and surfaced —
      `scripts/aid-nightly-report.sh:255` appends "! the quarantine record is
      unreadable" to the alert message. Only `quarantine_write_failed` is write-only:
      it is set at :162, emitted into the JSON at :232/:237, and read nowhere (a
      repo-wide grep outside the emitting script returns nothing, including
      `commands/aid-status.md`'s `nightly_line()` at :362-395). Whichever step ends up
      owning this must be given the correct, narrower premise.
    evidence: plugins/aid-orchestrator/scripts/aid-nightly-report.sh:255 (unreadable IS consumed) vs :162/:232/:237 (write_failed never read); plan line 37
    suggested_fix: >
      Narrow the claim to `quarantine_write_failed` (write-only in the JSON, invisible in
      the Telegram alert and in `/aid-status`'s `nightly_line()`), and note that
      `quarantine_unreadable` already reaches the alert but not `/aid-status`.

  - severity: low
    ref: L2-8
    summary: >
      Step 3's acceptance criterion "keeping three" does not match the file it will edit.
      `README.md:120-123` currently carries FOUR roadmap lines (v2.83.1 current, v2.82.0,
      v2.81.0, v2.80.0). The CONTRIBUTING convention in `CLAUDE.md` says "Keep the 3 most
      recent versions", so implementing the AC literally means the release also DELETES
      the v2.80.0 line — a behaviour change beyond "insert and demote" that no AC pins
      and no bats case is described for.
    evidence: README.md:120-123 (four entries); plan lines 136 and 156 ("keeping three")
    suggested_fix: >
      State the trim explicitly ("truncate the roadmap to the three most recent entries,
      deleting the surplus") and add a bats case for a four-entry roadmap, or drop the
      trim from scope and say the list length is left alone.

  - severity: low
    ref: L2-9
    summary: >
      AC8's own verification command relies on a GNU-grep extension in a step whose whole
      subject is grep portability. `bash -c '! grep -nE "grep[^|;]*-[A-Za-z]*P\\b" …'`
      uses `\b`, which is a GNU ERE extension and not POSIX. It works here (verified: the
      command currently exits 1 and prints `aid-review-signals.sh:24` and `:25`, i.e. it
      correctly detects the two live violations today), but it is the same class of
      dependency Step 5 exists to remove.
    evidence: |
      plan lines 543-544
      run: bash -c '! grep -nE "grep[^|;]*-[A-Za-z]*P\b" plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh' → exit 1, matches at :24 and :25
    suggested_fix: >
      Replace `\b` with an explicit character-class boundary, e.g.
      `grep[^|;]*-[A-Za-z]*P([[:space:]]|$)`, so the plan's own gate is portable.

  - severity: low
    ref: L2-10
    summary: >
      A confirmation, not a defect, recorded so the adjudicator does not re-open it:
      Step 12 targets `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`,
      which exists and carries its own recompute commands (`:51`, `:106-108`). `CLAUDE.md`
      still points contributors at `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`,
      which does NOT exist in this checkout (it is gitignored per the header at
      `defaults/enforcement-registry.yaml:4-9`). The plan is right and CLAUDE.md is stale;
      an implementer following CLAUDE.md instead of the plan would edit nothing.
    evidence: plugins/aid-orchestrator/defaults/enforcement-registry.yaml:1-9 and :50-51; `test -e docs/plans/AID-audit-2026-06/enforcement-registry.yaml` → missing
    suggested_fix: >
      Add a one-line note to Step 12 that the canonical registry is the `defaults/` file
      and that CLAUDE.md's path is the retired seed, so the step does not get "corrected"
      to the wrong file during implementation.

confidence: high
