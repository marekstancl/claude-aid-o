# CP1-deep — C0 lens planned_call_feasibility — P082

I read all 551 lines of the plan and then verified, against the real tree at `main` (v2.83.1), every artifact, code path, section anchor, subcommand, flag and test file the plan calls: the twelve steps' Files/Test lists, the eight `verification_pattern` commands, and the "Next Steps" invocations. Confirmed present and callable: `plugins/aid-orchestrator/defaults/hooks/pre-commit:89` (`_aid_in_scope`), `scripts/aid-fsm.sh:6032-6069` (`commit_scope_violation`), `:6090` (`cmd_set_field`), `:1817` (`fsm_check_streamlined_integration_review`, reading `${evidence_dir}/gates_report.json` while the runner writes `${_evidence_dir}/gates/gates_report.json` at `scripts/aid-run-gates.sh:1629` — the step's premise holds), `scripts/aid-fsm.sh:5754` (the wrong-checkpoint refusal Step 7's AC leans on), `scripts/aid-prefilter.sh:99` (filename computed before the checkpoint) and `:149-165` (the CP3 `merge-base`/`HEAD~5` guess vs CP2's `range_undetermined` at `:141-143`), `scripts/lib/aid-review-signals.sh:24-25` (two live `grep -qP`), `scripts/aid-release.sh:341` (`grep -m1 -oP`) and `:666-670` (the blind `sed -i "s/v$CURRENT/v$NEW_VERSION/g"` over `find -maxdepth 3 -name README.md`), the IMP-274 literal-string scan at `scripts/tests/bats/test-aid-plan-release-boundary.bats:7194-7264`, `scripts/lib/aid-plan-manifest.sh:997` (`plan_manifest_add_epic` taking `lineage="${8:-unproven}"` and reachable from the CLI at `:1639` while the usage line `:1622` documents only 7 args — so the plan's claim is real), `defaults/enforcement-registry.yaml` (with its own recompute command at `:51` and a documented `test` field at `:33`), the byte-identity assertion Step 12 relies on at `scripts/tests/verify-version-files.sh:102-131`, `aid-generation-readiness.sh --total` (`:19`), `aid-plan-lint.sh`, and every named bats/sh suite (`test-aid-init.bats`, `test-aid-prefilter.bats`, `test-aid-fsm.bats`, `test-plan-to-epic.sh`) plus `run-all-tests.sh:273,278` glob discovery for the two new `test-*.sh`/`*.bats` suites. Step 2's mechanism also checks out end to end (`aid-plan-fsm.sh __default-mode` → `_pfsm_default_mode` → `_pfsm_has_gate_profiles` reading `.aid-o/config/execution.yaml`; policy `default_mode: plan_branch` at `defaults/policies/plan-boundary-policy.yaml:28`; `defaults/execution.yaml` indeed has no `gate_profiles`). Four calls do not survive verification.

stop_rule_blockers: []

findings:

  - severity: high
    ref: C0-PCF-1
    summary: >
      Step 1 makes the pre-commit hook and the FSM companion "source" one shared predicate,
      but the hook is not a script that can source anything from the plugin. `/aid-init`
      copies `plugins/aid-orchestrator/defaults/hooks/pre-commit` verbatim to the consumer's
      `.git/hooks/pre-commit` (`plugins/aid-orchestrator/commands/aid-init.md:433-434`;
      installed path also at `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:1303`), where
      it runs standalone inside an arbitrary consumer repo that has no copy of
      `plugins/aid-orchestrator/scripts/lib/`. The shipped hook sources nothing today —
      `grep -n '^source|^\. |CLAUDE_PLUGIN_ROOT|SCRIPT_DIR' defaults/hooks/pre-commit`
      returns zero hits — and no step in P082 creates a plugin-root resolver, a vendoring
      copy, or an inline-block generator. So the one artifact Step 1 leans on ("the one
      shared predicate both callers source") has no producer for one of its two callers, and
      AC1 ("in both the hook and the FSM companion") can only be met by the duplicated rule
      the step exists to abolish.
    evidence: plan:73 "Create: `plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh` — the one shared predicate both callers source, so a future third consumer cannot invent a third rule." vs plugins/aid-orchestrator/commands/aid-init.md:433-434; plugins/aid-orchestrator/defaults/hooks/pre-commit:1-30,89-96 (no source/require line anywhere)
    suggested_fix: Name the delivery mechanism in Step 1's Files list — either an AID-block code generator that inlines the predicate into the installed hook at init time (with a test asserting the inlined bytes equal the library's), or keep the library for `aid-fsm.sh` only and state that the hook carries a generated copy plus an equality test. "Both callers source it" is not implementable for a `.git/hooks` file.

  - severity: high
    ref: C0-PCF-2
    summary: >
      Step 9's second half modifies an archival code path in `aid-fsm.sh` that does not
      exist. `plugins/aid-orchestrator/scripts/aid-fsm.sh:6894-6906` — the region the plan
      cites — is a done-advance PRECONDITION that fails when the task file is still in
      `tasks/`, and whose remedy line tells a human to `mv` it; the FSM never moves the file
      itself (`grep -rn 'tasks/archive' scripts/*.sh scripts/lib/*.sh` returns only that
      comment and that message; archival is prose in `skills/run-management.md:22,167,246`).
      There is therefore no producer to hook a restamp onto, and no step creates one.
      The `runs_completed` half is worse: the value is only ever WRITTEN as `0`
      (`scripts/aid-plan-to-epic.sh:1463`, `defaults/templates/epic.md:7` whose comment
      claims "incremented at each run DONE"); nothing in the tree increments it, so
      AC "an archived completed EPIC's frontmatter shows ... its run count" reads a number
      no producer computes.
    evidence: plan:329 "Modify `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~6890-6910) — the archival path: archiving a completed EPIC restamps its task frontmatter (`status`, `runs_completed`)"; scripts/aid-fsm.sh:6894 "# EPIC task file must be archived (moved to tasks/archive/)", :6905 "Move to tasks/archive/ before advancing: mv $task_file ..."; scripts/aid-plan-to-epic.sh:1463 "runs_completed: 0"
    suggested_fix: Split Step 9's second half into a real producer: either add an `archive-task` FSM subcommand (Create, not Modify) that performs the move and the restamp and is called from the done-advance path, or make the existing precondition restamp-on-detect. Either way state where `runs_completed` gets its value — add the increment at run DONE, or drop `runs_completed` from the AC and restamp `status` only.

  - severity: high
    ref: C0-PCF-3
    summary: >
      Steps 3 and 12 anchor on a "roadmap section" that no README in this repo has. The root
      `README.md` carries its version list under `## Changelog` (README.md:118-132), and
      `plugins/aid-orchestrator/README.md` has no version list at all — only
      `- **Plugin:** 2.83.1` (README:3). Under Step 3's own error handling ("No roadmap
      section found ⇒ warn and skip that file"), the new anchored edit would skip BOTH
      READMEs on every release, silently stopping the `- **vX.Y.Z** (current)` update that
      the version-file registry requires as location #7 — a regression on the current blind
      `sed`, which at least hits the line. Step 12's AC "The release's roadmap edit is
      recorded before and after and is correct" then has nothing to record. Secondary: the
      "keep the three most recent versions per the repository's own documented convention"
      is a call on a state that does not exist either — the live list holds 13 entries
      (README.md:120-132), so an implementation honouring the AC deletes ten tracked lines
      with no step authorising it.
    evidence: plan:136 "replace the global `sed s/v$CURRENT/v$NEW_VERSION/g` ... with an anchored roadmap edit: insert a new `- **vX.Y.Z** (current) — …` line" and plan:143 "No roadmap section found ⇒ warn and skip that file"; README.md:118 "## Changelog"; plugins/aid-orchestrator/README.md:3 "- **Plugin:** 2.83.1"
    suggested_fix: Name the real anchor in Step 3 (`## Changelog` in root README, and the `- **Plugin:** X.Y.Z` line in the plugin README — a different edit, not a roadmap), and make the "keep three" behaviour explicit about the existing 13-entry list: either drop the trimming from the AC or add the trim as a stated, reviewed content change.

  - severity: medium
    ref: C0-PCF-4
    summary: >
      Step 11's archive file cannot be committed as written, and its "append-only relative to
      the previous commit" assertion has no baseline to compare against. `.gitignore:87`
      ignores all of `docs/`; the single negation `!docs/plans/2026-06-29-BACKLOG.md`
      (.gitignore:93) is decorative — that file survives only because it is already tracked
      (`git ls-files` confirms), and git cannot re-include a path whose parent directory is
      excluded. `git check-ignore -v docs/plans/archive/x.md` returns `.gitignore:87 docs/`.
      So the new `docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md` will be invisible
      to `git add`, will not reach a commit, and the hygiene test's git-history check reads a
      file with no history. No step modifies `.gitignore` or specifies `git add -f`.
    evidence: plan:392 "Create: `docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md`" and plan:394 "the archive is append-only relative to the previous commit"; /opt/eco/projects/aid-orchestrator/.gitignore:87 "docs/", :93 "!docs/plans/2026-06-29-BACKLOG.md"; git check-ignore -v → ".gitignore:87 docs/  docs/plans/archive/x.md"
    suggested_fix: Add `.gitignore` to Step 11's Files list with an explicit negation for the archive path AND for its parent directory (`!docs/plans/`-style rules, or `git add -f` recorded in the step), and drop or re-baseline the append-only assertion for the file's first commit (first commit = no previous version).

  - severity: low
    ref: C0-PCF-5
    summary: >
      AC8's verification command is itself GNU-grep-specific in a step whose subject is grep
      portability: `grep -nE "...\\b"` uses `\b`, a GNU ERE extension absent from BSD/POSIX
      grep. It works on this repo's runner today (so it is not a blocker), but it makes the
      portability guard's own acceptance evidence unportable, which is exactly the class
      Step 5 exists to end.
    evidence: plan:543 "cmd: \"bash -c '! grep -nE \\\"grep[^|;]*-[A-Za-z]*P\\\\b\\\" plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh'\""; the target lines it must catch today are plugins/aid-orchestrator/scripts/lib/aid-review-signals.sh:24-25
    suggested_fix: Replace `\b` with a POSIX bracket alternative (e.g. `-[A-Za-z]*P([^A-Za-z]|$)`), or point AC8 at the widened bats detector from Step 5 rather than an ad-hoc inline grep.

confidence: high
