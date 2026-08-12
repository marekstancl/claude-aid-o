# CP1-deep — C0 lens idempotency_matrix — P082

I read all 551 lines of the plan and then walked every step that mutates a file on disk against the real tree: `aid-release.sh` (version-file bump + rollback + README substitution), `verify-version-files.sh`, `aid-prefilter.sh` (output-file naming, CP2/CP3 range resolution), `aid-fsm.sh` (the archival precondition at ~6890 and `cmd_set_field` at ~6100), `defaults/hooks/pre-commit` (`_aid_in_scope`), `lib/aid-init-execution-yaml.sh` (`compose_execution_yaml` / `execution_yaml_has_gate_profiles` / `append_gate_profiles_block`), `.gitignore`, and the backlog file's tracking status. Where it was cheap I ran the real thing twice in a throwaway clone under the scratchpad (`scratchpad/relrepo`, cloned with `git clone --local`; the real repo was never touched): two consecutive `aid-release.sh` invocations, and a hand-built half-applied README roadmap fed to `verify-version-files.sh`. Two of the findings below are reproduced facts, not inferences. Steps 1, 4, 5, 6, 8 introduce no persistent mutation and are idempotency-clean; the findings concentrate in Steps 3, 7, 9, 11 and 12.

stop_rule_blockers: []

findings:

  - severity: high
    ref: C0-IM-1
    summary: >
      Reproduced live: `aid-release.sh`'s rollback — the mechanism that exists precisely so a failed
      release can be re-run from the same base — does not restore `.claude-plugin/marketplace.json`,
      because the `metadata.version` and `plugins[0].version` branches (aid-release.sh:651-663, comment
      "# Don't double-add") deliberately skip `UPDATED+=(...)`, and `_release_rollback_updated`
      (aid-release.sh:775-791) iterates exactly `UPDATED[]`. I ran `aid-release.sh patch --force` in a
      clone: it bumped 2.83.1 → 2.83.2, the CHANGELOG placeholder check refused, and the rollback
      restored `CHANGELOG.md plugins/.../CHANGELOG.md plugin.json README.md` — while marketplace.json
      stayed at 2.83.2. The second invocation (`minor`) then computed CURRENT=2.83.1 from plugin.json,
      so marketplace.json's jq equality test `.metadata.version == "2.83.1"` did not match and it was
      never touched again; it is now permanently stranded at a version nobody ever released
      (`verify-version-files.sh 2.84.0` reports it as two of ten FAILs). Step 12 is the plan's own first
      live exercise of this script ("this release is its first live exercise", plan:427) and Step 3 edits
      the very same function without addressing the rollback set.
    evidence: plugins/aid-orchestrator/scripts/aid-release.sh:651-663 and :775-791; reproduced in scratchpad/relrepo (two invocations, marketplace.json left at 2.83.2 with plugin.json at 2.83.1); plan:136 "Modify … aid-release.sh (lines ~655-680)"; plan:427
    suggested_fix: Add to Step 3's Files a one-line fix — push `$jf` into `UPDATED[]` on the metadata/plugins[0] branches too (dedupe on push) — and add an acceptance criterion "an aborted release leaves every version file at the pre-run version, proven by re-running the script twice".

  - severity: medium
    ref: C0-IM-2
    summary: >
      Step 3 defines its re-run rule as "a roadmap already containing the new version (a re-run) — no-op"
      (plan:147). That condition keys on the wrong state. The roadmap edit is composed of two mutations
      (insert the new `(current)` line, demote the old one); if the run dies between them — or the
      implementer writes them as two `sed -i` passes — the file holds TWO `(current)` lines, the new
      version IS present, and Step 3's no-op rule then freezes the corruption forever. Nothing detects
      it: `verify-version-files.sh:184` reads the roadmap with `grep -m1`, i.e. only the first
      `(current)` line. I reproduced this: a README with `- **v2.84.0** (current)` inserted above the
      surviving `- **v2.83.1** (current)` yields `PASS: README.md '(current)' Roadmap line == 2.84.0`.
      Step 12's AC3 ("the release's roadmap edit is recorded before and after and is correct") therefore
      rests on a checker that cannot see the failure mode Step 3 introduces.
    evidence: plan:147 and plan:448; plugins/aid-orchestrator/scripts/tests/verify-version-files.sh:184 (`grep -m1 -oE '^\- \*\*v[0-9]+\.[0-9]+\.[0-9]+\*\* \(current\)'`); reproduced in scratchpad/relrepo
    suggested_fix: Make the roadmap edit a single atomic rewrite (build the new list, write via temp file + mv) and state the invariant, not the version, as the re-run condition — "exactly one `(current)` line" — asserted by both the new bats suite and `verify-version-files.sh` (change `grep -m1` to a count == 1 check).

  - severity: high
    ref: C0-IM-3
    summary: >
      Step 11 creates `docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md`, which is git-ignored:
      `.gitignore:87` ignores `docs/` wholesale and the only negation is `.gitignore:93`
      `!docs/plans/2026-06-29-BACKLOG.md` — the live file alone (`git check-ignore -v` on the proposed
      archive path returns `.gitignore:87`, exit 0). So the 45 archived entries and their closing
      evidence leave the tracked live file (a real deletion) and land in a file that is never committed
      unless someone remembers `git add -f`; on any fresh clone the content is simply gone. Step 11's
      own hygiene check ("the archive is append-only relative to the previous commit", plan:394) has no
      committed baseline to compare against in that state and will either error or pass vacuously. The
      .gitignore comment immediately above the negation (lines 88-92) records that this exact backlog
      file was already destroyed once by a merge resolution *because* it lost tracking — the plan
      recreates that precise failure for the archived half, and `.gitignore` is not in Step 11's Files.
    evidence: .gitignore:87-93; `git check-ignore -v docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md` → `.gitignore:87` (exit 0); plan:392-394
    suggested_fix: Add `.gitignore` to Step 11's Files with a negation for the archive path (`!docs/plans/archive/2026-06-29-BACKLOG-archive-*.md`), and make the hygiene check assert the archive is tracked (`git ls-files --error-unmatch`) before it evaluates append-only — a check that cannot find its baseline must refuse, not pass.

  - severity: medium
    ref: C0-IM-4
    summary: >
      The archive is declared `Create:` with no behaviour defined for "the destination already exists"
      (plan:392), and its filename is dated only to the month (`-archive-2026-08`). A resumed or repeated
      Step 11 — an interrupt after writing the archive but before pruning the live file is the obvious
      case — has two plausible implementations and the plan picks neither: append again (duplicate
      entries; the hygiene check at plan:394 tests append-only and status/reason coverage, never
      uniqueness, so duplicates ship green) or regenerate (silently drops anything archived by an
      earlier pass). A second archival pass later in the same month collides on the same filename.
    evidence: plan:392 ("Create: docs/plans/archive/2026-06-29-BACKLOG-archive-2026-08.md"); plan:394 (hygiene assertions — no uniqueness check); plan:400 (error handling covers only ambiguous verdicts)
    suggested_fix: State the destination-exists rule explicitly (merge by entry id, skipping ids already present) and add "no entry id appears twice in the archive, and no id appears in both files" to the hygiene harness.

  - severity: medium
    ref: C0-IM-5
    summary: >
      The reverse case. Step 11 ships a check asserting the archive is "append-only relative to the
      previous commit" (plan:394), while the plan's own Risks row promises that a wrong closure is
      "visible and reversible" (plan:477) and its error handling says an ambiguous entry stays live
      (plan:400). Once an entry has been archived, moving it back — the documented remedy for the
      audit having been wrong — deletes a line from the archive and is refused by the very check the
      step introduced. The mitigation and the enforcement contradict each other, and the enforcement
      wins.
    evidence: plan:394 vs plan:477 and plan:400
    suggested_fix: Scope the append-only assertion to "no entry disappears without a recorded revival note", or drop it in favour of the id-uniqueness/round-trip check from C0-IM-4, so a correction is possible without disabling the gate.

  - severity: medium
    ref: C0-IM-6
    summary: >
      Step 9 says "Modify aid-fsm.sh (lines ~6890-6910) — the archival path: archiving a completed EPIC
      restamps its task frontmatter" (plan:329). There is no archival path there. aid-fsm.sh:6894-6906
      is a PRECONDITION check inside `done-advance`: it searches `.aid-o/tasks/` and, if the file is
      still there, increments `errors` and prints "Move to tasks/archive/ before advancing: mv …" — the
      move is performed by hand/controller, and the check runs on every done-advance attempt (the
      normal loop is: attempt → precondition fails → operator fixes → attempt again). A restamp placed
      on that path therefore executes 1..N times per EPIC, and the plan pins no re-run behaviour.
      `runs_completed` makes this concrete: no script anywhere increments it — it is only ever written
      as literal `0` (aid-plan-to-epic.sh:1463), and `defaults/templates/epic.md:7` documents it as
      "incremented at each run DONE" — so the natural implementation is an increment, which
      double-counts on the second attempt. AC "An archived completed EPIC's frontmatter shows its
      terminal status and run count" (plan:349) passes either way.
    evidence: plugins/aid-orchestrator/scripts/aid-fsm.sh:6894-6906 (precondition, not an archiver); plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh:1463; plugins/aid-orchestrator/defaults/templates/epic.md:7; plan:329, plan:340, plan:349
    suggested_fix: Name the real archival site (or state that Step 9 adds one), make the restamp write absolute derived values rather than an increment, and add an AC: "restamping twice leaves the frontmatter byte-identical".

  - severity: low
    ref: C0-IM-7
    summary: >
      Step 9 requires an `fsm_field_change` event on every `cmd_set_field` call including no-ops
      ("Setting a field to its current value — event still emitted", plan:339). `cmd_set_field`
      (aid-fsm.sh:6093-6127) is routinely re-invoked by controllers on retry, so a retried
      `set-field pm_decision merge` appends a second identical record. The plan's AC is worded per-call
      ("appends exactly one event", plan:348) and says nothing about what a consumer of the resulting
      journal may assume — and this codebase does contain count-comparing consumers (the
      `gate_fixer_fix_applied` vs `invalidation_map_produced` comparison, enforcement-registry.yaml:929).
    evidence: plan:339, plan:348; plugins/aid-orchestrator/scripts/aid-fsm.sh:6093-6127; plugins/aid-orchestrator/defaults/enforcement-registry.yaml:929
    suggested_fix: State in the step that the journal is retry-tolerant by design and that any "state matches events" reader must fold on the LAST event per field, not count occurrences.

  - severity: low
    ref: C0-IM-8
    summary: >
      Step 7 leaves the implementer a choice, one arm of which renames evidence: "the output filename is
      derived after the checkpoint is known and carries it" (plan:264). `aid-prefilter.sh:96` computes
      `verifier-output-step-${step_n}.md` for every checkpoint, and three readers hardcode that exact
      name — aid-fsm.sh:2477, aid-fsm.sh:5705 and aid-acceptance-evidence.sh:164 — none of which is in
      Step 7's Files. If the CP2 name changes with it, a run interrupted before this change and resumed
      after the plugin update looks for a filename that its own earlier evidence was not written under,
      and the CP2 precondition hard-fails on evidence that exists. It also collides with the plan's own
      Constraints, which freeze evidence filenames (plan:463).
    evidence: plugins/aid-orchestrator/scripts/aid-prefilter.sh:96; plugins/aid-orchestrator/scripts/aid-fsm.sh:2477, :5705; plugins/aid-orchestrator/scripts/aid-acceptance-evidence.sh:164; plan:264 vs plan:463
    suggested_fix: Constrain the choice in the plan: CP2's filename is frozen, only the CP3 arm may carry a checkpoint suffix (or CP3 classify is refused outright), and say so in Step 7's objective rather than leaving it to the implementer.

  - severity: low
    ref: C0-IM-9
    summary: >
      Step 2 adds a `gate_profiles` table to `defaults/execution.yaml` (plan:104). The fresh-init path
      does not copy that file — `compose_execution_yaml` builds execution.yaml from
      `defaults/execution-stacks/*.yaml` fragments and then appends its OWN rendered block via
      `render_gate_profiles_block` (lib/aid-init-execution-yaml.sh). If any path ever seeds a workspace
      from the template and then runs the composer or the additive upgrade, the file carries two
      top-level `gate_profiles:` keys (last wins in yq, silently) and the upgrade guard cannot notice:
      `execution_yaml_has_gate_profiles` is presence-only, not count-only. Step 2's AC "Re-running init
      over a project with its own table changes nothing" (plan:126) is satisfied by the existing guard
      and does not cover the duplicate-key case.
    evidence: plugins/aid-orchestrator/scripts/lib/aid-init-execution-yaml.sh (`compose_execution_yaml` → `render_gate_profiles_block`; `execution_yaml_has_gate_profiles` returns true if EITHER key is present); plan:104, plan:115, plan:126
    suggested_fix: Add an assertion to Step 2's test that a composed workspace contains exactly one top-level `gate_profiles:` key, and state in the step which path actually delivers the template to a consumer (no script copies `defaults/execution.yaml` today).

confidence: high
