# CP1-deep — Lens L1 BEHAVIOR — P082

I read all 551 lines of `.aid-o/plans/P082-backlog-truth-and-live-holes.md`, then traced each of the twelve steps onto the runtime path it claims to sit on, reading the actual code at every file the plan names rather than trusting the plan's paraphrase. Concretely: I opened `defaults/hooks/pre-commit` (`_aid_in_scope`, the scope build for EXECUTE/GATES/DONE), `aid-fsm.sh` (the `commit_scope_violation` companion, `_fsm_routed_findings_check`, `fsm_check_streamlined_integration_review`, `cmd_set_field`, the DONE→release precondition block), `aid-prefilter.sh` (the whole cp2/cp3/cp4/cp6 range + output-file logic), `aid-release.sh` (`_release_update_files`, `_release_probe_first`), `aid-plan-to-epic.sh` (both acceptance-criteria awk blocks), `lib/aid-review-signals.sh`, `lib/aid-plan-manifest.sh`, `lib/aid-init-execution-yaml.sh`, `aid-plan-fsm.sh` (`_pfsm_has_gate_profiles` / `_pfsm_default_mode`), `gates/scope-check.sh` and `lib/aid-ancillary.sh`. I ran the plan's own AC8 command against the live tree, grepped for every consumer of `allowed_paths`, `verifier-output-step-N.md`, `gates_report.json`, `defaults/execution.yaml`, `add-epic` and `tasks/archive`, and checked which shipped instruction actually invokes the prefilter with a checkpoint. Three steps turn out to sit on a path other than the one they describe; the rest are accurate but under-declare adjacent branches.

stop_rule_blockers:

  - ref: L1-B1
    severity: critical
    summary: >
      Step 1 declares exactly two consumers of the allowed_paths scope predicate ("the one shared
      predicate both callers source, so a future third consumer cannot invent a third rule",
      plan:73). There are already four, and the one Step 1 omits is BLOCKING. `gates/scope-check.sh`
      is wired as a gate in `defaults/execution.yaml:104` and matches each changed file against each
      allowed_paths entry with a bash `case` glob (`gates/scope-check.sh:36-39`), exiting 1 on any
      unmatched file. `{rev}` is not a glob metacharacter, so `migrations/{rev}_add_users.py` matches
      `migrations/a1b2c3_add_users.py` there no better than in the hook. A fourth rule lives in
      `lib/aid-ancillary.sh:124` (`_aid_ancillary_glob_match`, permissive) and is used by the DONE
      precondition `_fsm_routed_findings_check` (`aid-fsm.sh:1388`) to decide which review findings
      were in scope. Implemented exactly as written, Step 1 unblocks the commit and the run then dies
      at the GATES scope gate instead — Success Criterion 1 ("A project with generated migration
      filenames can commit", plan:481) is not reached, and the new library becomes a fifth predicate
      rather than "the one".
    evidence: "plugins/aid-orchestrator/defaults/execution.yaml:104; plugins/aid-orchestrator/scripts/gates/scope-check.sh:33-42; plugins/aid-orchestrator/scripts/lib/aid-ancillary.sh:124-146; plugins/aid-orchestrator/scripts/aid-fsm.sh:1382-1389; plan lines 71-73"
    suggested_fix: >
      Name all four consumers in Step 1's Files block and state the outcome for each: `gates/scope-check.sh`
      (blocking gate — must adopt the shared predicate or the run still fails), the pre-commit hook,
      the FSM `commit_scope_violation` companion, and `_aid_ancillary_glob_match`/`_fsm_routed_findings_check`.
      Either build the new predicate on top of the existing `_aid_ancillary_glob_match` (which already
      is "the shipped path-vs-pattern predicate", aid-fsm.sh:1385-1388) or state explicitly why a fifth
      one is justified. Add an acceptance criterion that an Alembic-shaped entry passes the scope GATE,
      not only the hook.

  - ref: L1-B2
    severity: critical
    summary: >
      Step 2 modifies `plugins/aid-orchestrator/defaults/execution.yaml` "so the plan-mode default
      resolves to plan_branch for a fresh project" (plan:104). Nothing reads that file at init time.
      `/aid-init` COMPOSES `.aid-o/config/execution.yaml` from `defaults/execution-stacks/*.yaml` via
      `compose_execution_yaml` (`commands/aid-init.md:123`, `lib/aid-init-execution-yaml.sh:316-400`),
      and the gate table is rendered by `render_gate_profiles_block` (same file:206-266), which already
      emits a real `gate_profiles:` table whenever any stack is detected — so the plan's claim that
      "every project initialised from defaults silently falls back to per-EPIC releases" (plan:57) is
      false for every stack-detected project; only the zero-stack case emits the bare comment at
      `lib/aid-init-execution-yaml.sh:240`. The mode resolver reads the composed consumer file, not the
      template: `_pfsm_has_gate_profiles` opens `${root}/.aid-o/config/execution.yaml`
      (`aid-plan-fsm.sh:9867-9877`). Worse, the comment directly above it records that putting the table
      into `defaults/execution.yaml` was DELIBERATELY avoided because "a consumer project that merely
      upgrades the plugin would flip to plan_branch and resolve its gates against nothing at all"
      (`aid-plan-fsm.sh:9862-9866`). So Step 2 as written is either a no-op on the runtime path, or —
      if the implementer chases the objective — it reintroduces the exact hazard a prior decision named.
    evidence: "plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:9862-9877; plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh:206-266 and :316-400; plugins/aid-orchestrator/commands/aid-init.md:123,157-160; `grep -rn 'defaults/execution.yaml' plugins/aid-orchestrator --include=*.sh` returns no reader/copier; plan lines 101-108"
    suggested_fix: >
      Re-target Step 2 at the actual mechanism: `render_gate_profiles_block` and the zero-stack branch
      (`lib/aid-init-execution-yaml.sh:240`), and state what a stack-less project should get. Address the
      recorded objection at `aid-plan-fsm.sh:9862-9866` head-on (why shipping a table no longer means
      gates resolving against nothing), and make the AC test the composed `.aid-o/config/execution.yaml`
      that `_pfsm_has_gate_profiles` actually reads, not "a workspace composed from the shipped template".

  - ref: L1-B3
    severity: high
    summary: >
      Step 7 proposes that the prefilter's "output filename is derived after the checkpoint is known and
      carries it" (plan:264), while the plan's own Constraints freeze evidence filenames
      ("Frozen surfaces: evidence filenames", plan:463). The collision is also wider than the plan states:
      `aid-prefilter.sh:96` computes ONE `verifier-output-step-${step_n}.md` for all four checkpoints, so
      cp4 and cp6 overwrite a CP2 output exactly as cp3 does — the plan declares only the CP3 branch. And a
      CP3 output renamed to carry its checkpoint is read by nobody: the FSM's CP3 evidence is
      `verifier-output-cp3-{focus}.md` (`aid-fsm.sh:1229`, `fsm_check_streamlined_integration_review`
      at :1823-1824), while `verifier-output-step-N.md` is consumed by `aid-fsm.sh:2477`, :5705, the
      cp2-checkpoint assertion at :5756 and `aid-acceptance-evidence.sh:164`. Implemented literally, either
      the CP2 filename moves (breaking five consumers and the frozen-surface constraint) or the CP3 output
      becomes an orphan file no reader picks up — neither outcome is declared.
    evidence: "plugins/aid-orchestrator/scripts/aid-prefilter.sh:96 (single output_file for cp2|cp3|cp4|cp6); plugins/aid-orchestrator/scripts/aid-fsm.sh:1229,2477,5705,5756,1823-1824; plugins/aid-orchestrator/scripts/aid-acceptance-evidence.sh:164; plan lines 264 and 463"
    suggested_fix: >
      State the decision in the plan rather than deferring it to the step ("The step picks one"): keep
      `verifier-output-step-N.md` byte-stable for cp2 and give cp3/cp4/cp6 either a suffixed name whose
      reader is named, or a refusal. Extend the objective and the ACs to cp4 and cp6, and reconcile the
      choice with the frozen-evidence-filenames constraint explicitly.

findings:

  - severity: high
    ref: L1-1
    summary: >
      Step 9's second half targets "the archival path" at `aid-fsm.sh` lines ~6890-6910 (plan:329), but
      there is no archival path there. That range is a read-only DONE→release PRECONDITION which asserts
      the task file has ALREADY been moved out of `tasks/` and tells the operator to move it by hand
      (`aid-fsm.sh:6894-6906`: "PRECONDITION FAIL: EPIC task file still in tasks/ (not archived)" +
      "Move to tasks/archive/ before advancing: mv ..."). The mover is the controller/LLM per
      `skills/run-management.md:167` and `skills/pipeline.md:1832-1838`; no script performs the move.
      Implemented literally, either the step does nothing, or a precondition check silently gains a
      file-mutation side effect on a file it does not own and which, at the moment the check runs, has
      already left the directory the check scans (`find "${_tasks_dir}/" -maxdepth 1`).
    evidence: "plugins/aid-orchestrator/scripts/aid-fsm.sh:6894-6906; plugins/aid-orchestrator/skills/run-management.md:167; plugins/aid-orchestrator/skills/pipeline.md:1832-1838; plan line 329"
    suggested_fix: >
      Name the real owner of archival (the controller step in run-management.md/pipeline.md, or a new
      script that both moves and restamps) and say which component does the restamp. If the FSM is to own
      it, say so explicitly — a precondition that also mutates state is a new behaviour that needs its own
      declaration and its own failure mode.

  - severity: high
    ref: L1-2
    summary: >
      Step 4 fixes "the awk block that emits acceptance criteria" (plan:167) as if there were one. There are
      two, ~25 lines apart, with identical `^-[[:space:]]` matching: `step_ac` (aid-plan-to-epic.sh:908-925)
      feeds the human-facing flattened `## Acceptance Criteria` section, and `step_ac_raw`
      (aid-plan-to-epic.sh:934-950) feeds the machine-facing per-step `<!-- step-N: files=[...]; ac=[...] -->`
      block, which `aid-epic-to-json.sh` turns into `acceptance_criteria[]` and which
      `gates/aid-contract-validate.sh:346` treats as authoritative for the count comparison. The plan's line
      range (~885-910) covers only the first. Fixing one leaves the machine-facing criterion truncated while
      the human-facing one is whole — the opposite of the step's intent — and changes the two AC counts
      relative to each other, which `aid-epic-to-json.sh:262-278` also reasons about.
    evidence: "plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:908-925 and :934-950; plugins/aid-orchestrator/scripts/gates/aid-contract-validate.sh:232-239,346; plugins/aid-orchestrator/scripts/aid-epic-to-json.sh:262-278; plan line 167"
    suggested_fix: >
      Name both awk blocks in Step 4's Files entry (or factor the continuation rule into one shared awk
      program in `lib/aid-scoping.sh`, matching what that library already does for Files bullets), and add
      an AC that the flattened section and the per-step `ac=[]` block carry the same joined text.

  - severity: high
    ref: L1-3
    summary: >
      Step 3 removes `sed -i "s/v$CURRENT/v$NEW_VERSION/g"` over every README within three levels
      (`aid-release.sh:665-671`) and replaces it with a roadmap-only edit, with "No roadmap section found ⇒
      warn and skip that file" (plan:143). The plan treats that sed purely as a corruption risk and never
      notes it is also the only thing that bumps NON-roadmap version references in a consumer's README —
      badges, install snippets, "requires vX.Y.Z" lines. After Step 3 those silently stop being updated in
      every consumer project, which is a user-visible regression the plan does not declare. In this repo the
      sibling `grep -q "Plugin: $CURRENT"` branch (`aid-release.sh:672-675`) already never fires, because the
      actual text is `- **Plugin:** 2.83.1` and `grep -c "Plugin: 2.83.1" plugins/aid-orchestrator/README.md`
      returns 0 — so registry location #6 is not script-updated today, yet Step 12 asserts "All eight version
      locations agree" (plan:447) as if the release script produced them.
    evidence: "plugins/aid-orchestrator/scripts/aid-release.sh:665-675; `grep -c \"Plugin: 2.83.1\" plugins/aid-orchestrator/README.md` → 0; plugins/aid-orchestrator/README.md:3; plan lines 136, 143, 447"
    suggested_fix: >
      Say what happens to non-roadmap version references after the change (keep a narrowly anchored bump for
      the declared registry lines, or state that consumers must bump them by hand), and have Step 3 or Step 12
      fix the `Plugin: $CURRENT` matcher so location #6 is genuinely script-updated instead of relying on an
      unstated manual edit.

  - severity: medium
    ref: L1-4
    summary: >
      Step 8's Implementation Detail claims "One constant, one reader — the fix is small precisely because
      every other consumer already migrated" (plan:300). No consumer migrated to a single constant; the two
      other readers do a two-location fallback, root first then `gates/`:
      `aid-release-policy.sh:792-795` and `lib/aid-c3-dispatch.sh:765-769`. The runner's default is
      `${evidence_dir}/gates/gates_report.json` (`aid-run-gates.sh:1629`) but `--report-file` is caller-supplied
      (`aid-fsm.sh:2910,2946`, `aid-plan-fsm.sh:4572`, `skills/pipeline.md:1115`), so a root-path report is
      still producible. A fix implemented as "one constant" pointing at `gates/` would newly hard-fail
      (`die "streamlined_integration_review"`, aid-fsm.sh:1852) a streamlined run whose report sits at the
      root — a currently-passing path turned red.
    evidence: "plugins/aid-orchestrator/scripts/aid-fsm.sh:1825,1852; plugins/aid-orchestrator/scripts/aid-release-policy.sh:792-795; plugins/aid-orchestrator/scripts/lib/aid-c3-dispatch.sh:765-769; plugins/aid-orchestrator/scripts/aid-run-gates.sh:1629; plan line 300"
    suggested_fix: >
      Change Step 8 to adopt the same root-then-`gates/` fallback the other two readers use, and say so; make
      the AC assert both locations pass and that absence at BOTH still hard-fails with the documented message.

  - severity: medium
    ref: L1-5
    summary: >
      Steps 6 and 7 rest on the premise that CP3 is "the more consequential review (the final one)" running
      through this code (plan:236). No shipped instruction invokes the prefilter with a checkpoint at all:
      every call site is the bare cp2 default (`skills/pipeline.md:775`, `aid-fsm.sh:5737`, :5759), and
      `--checkpoint cp3|cp4|cp6` appears only in the script's own usage text (`aid-prefilter.sh:16,45,58`).
      So both the CP3 range guess and the CP2-evidence overwrite are reachable only by hand invocation, which
      changes the priority and the risk framing, and means Step 6's new fail-closed refusal has no live caller
      to protect but does add a new operator-facing refusal plus a new `CP3_RANGE_POLICY`-style escape surface
      that does not exist today.
    evidence: "plugins/aid-orchestrator/scripts/aid-prefilter.sh:16,45,58,148-168; plugins/aid-orchestrator/skills/pipeline.md:775; plugins/aid-orchestrator/scripts/aid-fsm.sh:5737,5759; plan lines 233-236"
    suggested_fix: >
      State in Steps 6/7 that no shipped caller passes `--checkpoint cp3` today, so the change is
      hardening-before-use rather than closing a live incident; name the env var of the new observe escape
      explicitly and register it, since it is a new operator-facing toggle.

  - severity: medium
    ref: L1-6
    summary: >
      AC8's command is narrower than Step 5's stated invariant. Step 5 promises the widened detector tolerates
      "`-oP`, `-qP`, `-Pq`, `--perl-regexp`" and that the long form is "caught" (plan:207,214), but AC8's regex
      `grep[^|;]*-[A-Za-z]*P\b` requires a literal uppercase `P` after a dash and therefore cannot match
      `--perl-regexp` (all lowercase). The AC that is supposed to prove the invariant would stay green over a
      file that reintroduces the long form. I ran AC8 against the current tree: it exits 1 (the two live
      `grep -qP` hits at `lib/aid-review-signals.sh:24-25`), so the AC is meaningful today but incomplete as a
      standing guard.
    evidence: "`bash -c '! grep -nE \"grep[^|;]*-[A-Za-z]*P\\b\" plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh'` → exit 1, matches lines 24 and 25; plan lines 207, 214, 543"
    suggested_fix: >
      Widen AC8's pattern to include the long form (e.g. add `|--perl-regexp`) so the AC and the step's claimed
      invariant are the same invariant.

  - severity: medium
    ref: L1-7
    summary: >
      Step 5 converts `_aid_read_toggle`'s two PCRE greps to POSIX (plan:201). The plan describes the failure
      correctly — on a grep without `-P` the `&&` chain short-circuits and `_aid_read_toggle` returns 0, i.e.
      "enabled", so a section explicitly disabled in execution.yaml is treated as enabled — but it does not
      declare the converse outcome of the fix: on machines where the toggle currently misreports "enabled",
      the corrected POSIX read will start honouring `enabled: false`, so FSM checks
      (`fsm_eval_delivery_report_present`, `fsm_eval_simplifier_present`) and the C4 release aggregator, which
      share this substrate (`lib/aid-review-signals.sh:5-13`), will change verdicts on existing projects that
      had disabled a section and never saw it take effect. That is a user-visible behaviour change on both
      consumers, unmentioned in the step.
    evidence: "plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:5-13,22-30; plan lines 201, 205"
    suggested_fix: >
      Add the declared outcome to Step 5: after the fix, `enabled: false` sections stop being silently ignored
      on non-GNU grep, which can flip a previously-passing compliance/release verdict; note it in the CHANGELOG
      entry Step 12 writes.

  - severity: low
    ref: L1-8
    summary: >
      Step 11 moves the July narrative sections into the archive and relies on "the archive header records the
      original file so a reader can follow" (plan:403). At least one live document references the backlog by
      SECTION, not by file — `docs/plans/AID-control-system-v2-roadmap.md:242` points at
      `docs/plans/2026-06-29-BACKLOG.md` sections "STALE PLUGIN CACHE" and "Pre-E10 control hygiene block" as a
      binding precondition for the observe→blocking promotion. Preserving the filename does not preserve those
      section anchors. Separately, the plan's counts are stale against the tree it will be implemented on:
      `grep -c '^#\{2,4\} ' docs/plans/2026-06-29-BACKLOG.md` reports 126 headings, not the 101 the Context and
      Architecture sections assert, and the Context says main is at v2.82.0 while `README.md:120` and
      `plugins/aid-orchestrator/README.md:3` say 2.83.1.
    evidence: "docs/plans/AID-control-system-v2-roadmap.md:242; `grep -c '^#\\{2,4\\} ' docs/plans/2026-06-29-BACKLOG.md` → 126; README.md:120; plan lines 18, 396, 403"
    suggested_fix: >
      Have Step 11 leave a one-line stub with a forwarding pointer for any section another live document cites
      by name, and refresh the Context's entry count and baseline version against the tree at generation time.

confidence: high
