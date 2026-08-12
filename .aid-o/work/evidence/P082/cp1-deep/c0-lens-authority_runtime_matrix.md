# CP1-deep — C0 lens authority_runtime_matrix — P082

I read all 551 lines of `.aid-o/plans/P082-backlog-truth-and-live-holes.md` and then verified every path each step names against the live tree at HEAD (3da7331, main): which side of the plugin / defaults / consumer-workspace line each file sits on, who writes it and who reads it at runtime, who is authorised to mint the values the plan touches (`lineage: proven`, FSM `set-field`, the release-mode default), and what other sessions currently hold. Concretely I compared `plugins/aid-orchestrator/defaults/hooks/pre-commit` against this repo's installed `.git/hooks/pre-commit`; traced the release-mode resolution chain (`_pfsm_default_mode` → `_pfsm_has_gate_profiles` → `.aid-o/config/execution.yaml` → `compose_execution_yaml`/`render_gate_profiles_block` → `defaults/execution-stacks/*`); traced the prefilter output filename and every reader of `verifier-output-step-N.md` / `verifier-output-cp3-{focus}.md`; traced `plan_manifest_add_epic`'s CLI dispatcher versus its sourced legitimate producer; confirmed the enforcement-registry target is the live one (`defaults/enforcement-registry.yaml`, not the archived `docs/plans/archive/AID-audit-2026-06/` copy — no finding there); confirmed Step 8's path claim and Step 7's collision claim are both factually correct; and enumerated the live worktrees and the current dirty working tree for concurrency collisions. Seven findings, none of which stop the review.

stop_rule_blockers: []

findings:

  - severity: high
    ref: C0-ARM-1
    summary: >
      Step 1 designs the placeholder predicate as a plugin library that "both callers source"
      (`Create: plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh` — the one shared predicate
      both callers source). One of those callers is the git pre-commit hook, which is COPIED into
      the consumer's `.git/hooks/` and runs there — it cannot resolve the plugin cache path, and the
      hook's own header says so in as many words at
      `plugins/aid-orchestrator/defaults/hooks/pre-commit:34-39` ("`_aid_state_root` is a deliberate
      tiny COPY of the plugin lib resolver … a consumer-repo hook cannot know the plugin cache path,
      so it cannot source the lib"). The plugin/consumer runtime boundary makes the step's central
      anti-drift mechanism unbuildable as written; an implementer will either duplicate the rule
      after all (the exact drift Step 1 exists to prevent) or make the hook depend on a path it
      cannot see, which fails open in every consumer.
    evidence: plugins/aid-orchestrator/defaults/hooks/pre-commit:34-39 (verbatim precedent for the same problem in P074); plan line 73 "Create: `plugins/aid-orchestrator/scripts/lib/aid-scope-match.sh` — the one shared predicate both callers source, so a future third consumer cannot invent a third rule"; the two predicates today: defaults/hooks/pre-commit:89-95 (`_aid_in_scope`) and plugins/aid-orchestrator/scripts/aid-fsm.sh:6059-6062
    suggested_fix: State the P074-precedented shape explicitly in Step 1 — the lib is the single AUTHORING source for the FSM side, and the hook carries a marked, deliberately-copied block whose byte-equality with the lib's predicate body is asserted by the new bats suite (an equality test is the anti-drift mechanism a sourced lib cannot be here). Say this in Files and in the AC, not in prose.

  - severity: high
    ref: C0-ARM-2
    summary: >
      Step 1's objective is "A plan whose `allowed_paths` contains a generated-name placeholder no
      longer blocks every commit in the run", but the file that blocks commits is never the template
      — it is the installed copy at each repo's `.git/hooks/pre-commit`, refreshed only when a PM
      re-runs `/aid-init` (`plugins/aid-orchestrator/commands/aid-init.md:433-443`). This repo's own
      installed hook is already 76 lines behind the template (254 vs 330 lines; it still reads the
      pre-P074 single-slot `active-run-pointer.json` and has no `_aid_state_root`), so P082's own
      EXECUTE commits would run through a hook that never receives the fix. No step re-installs
      hooks, no AC verifies an installed hook, and no test detects template/installed divergence.
    evidence: `diff .git/hooks/pre-commit plugins/aid-orchestrator/defaults/hooks/pre-commit` — 254 vs 330 lines, installed copy missing the whole P074 state-root block; plugins/aid-orchestrator/commands/aid-init.md:430-443; plan line 68 (Step 1 Objective)
    suggested_fix: Add to Step 1 an explicit hook-refresh obligation — re-run the documented install/upgrade path against this repo as part of the step, record the installed hook's post-fix hash in the verify output, and add an AC that the installed hook and the template agree on the scope predicate. Separately note in the step that consumers only get the fix on their next `/aid-init`, so the CHANGELOG entry (Step 12) must say so.

  - severity: high
    ref: C0-ARM-3
    summary: >
      Step 2 fixes the wrong side of the defaults/consumer boundary. It claims "the shipped
      `defaults/execution.yaml` lacking a `gate_profiles` table … every project initialised from
      defaults silently falls back to per-EPIC releases". In the live tree the release-mode resolver
      reads the CONSUMER file only — `_pfsm_has_gate_profiles` opens
      `${root}/.aid-o/config/execution.yaml` (aid-plan-fsm.sh:9869) — and that file is never copied
      from `defaults/execution.yaml`; it is COMPOSED from `defaults/execution-stacks/<stack>.yaml`
      plus `render_gate_profiles_block` (aid-init-execution-yaml.sh:395, 206-265). Nothing at
      runtime reads `defaults/execution.yaml` at all (only tests, the registry and CHANGELOG
      reference it). So the step as written would ship a table nobody resolves, while the real
      consumer-facing hole stays open: `render_gate_profiles_block` emits only a COMMENT when no
      stack is detected (aid-init-execution-yaml.sh:239-241 — "no stacks detected — add gate
      definitions above"), which is precisely the fresh-project case Step 2 is about, and even in
      the happy path it emits only `targeted` and `full`, not the `quick < targeted < standard <
      full < release` order Step 2 promises — a plan-branch project with no `release` profile hits
      `PRECONDITION FAIL: profile 'release' has an empty or missing include[]` at
      aid-plan-fsm.sh:4491-4493.
    evidence: plan line 104 "Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (lines ~1-160) — add a `gate_profiles` table"; aid-plan-fsm.sh:9867-9877; scripts/lib/aid-init-execution-yaml.sh:389-395 and :239-241 and :255-265; aid-plan-fsm.sh:4491-4493
    suggested_fix: Retarget Step 2's Files at the generation path — `scripts/lib/aid-init-execution-yaml.sh` (`render_gate_profiles_block`: emit a real minimal table in the zero-stack case, and define the profiles the plan-branch lifecycle actually requires including `release`) and, if `defaults/execution.yaml` is kept in scope, say plainly that it is a documentation reference with no runtime reader. Restate the AC as "a workspace composed by `compose_execution_yaml` — with and without a detected stack — resolves `__default-mode` to plan_branch and exposes a non-empty `release` profile".

  - severity: high
    ref: C0-ARM-4
    summary: >
      Step 2 modifies `plugins/aid-orchestrator/commands/aid-init.md` while another session is
      mid-run on exactly that file. `.aid-worktrees/plan-P080` is checked out at
      `task/E-080-1_3/main`, and P080's plan rewrites aid-init.md substantively in three steps —
      including MOVING the very section Step 2 edits ("Move the `## Plan mode` section (lines
      ~682-696) above the `**Last Updated:**` footer",
      `.aid-o/plans/P080-entrypoint-ux-help-handoffs.md:215`), delisting the file from the
      test-skill-lint GRANDFATHERED array (:218) and adding an AC that
      `aid-lint-skill.sh commands/aid-init.md` reports ZERO findings (:242, :276). P082's Constraints
      sequence only against P081 ("Sequenced after P081's tier work…", line 462) and never mention
      P080. Step 1 and Step 2 also overlap P080's new `test-init-idempotency.sh`, which replays
      "hook install from `defaults/hooks/`" and the execution.yaml compose (:319). A P082 edit landing
      into aid-init.md concurrently is a merge collision at best and a silently reverted lint-clean
      state at worst.
    evidence: `git worktree list` → `/opt/eco/projects/aid-orchestrator/.aid-worktrees/plan-P080  193fc0b [task/E-080-1_3/main]`; .aid-o/plans/P080-entrypoint-ux-help-handoffs.md:215, :218, :242, :276, :319; plan line 462 (Constraints name P081 only)
    suggested_fix: Add P080 to the Constraints as a hard ordering ("Step 2's aid-init.md edit lands only after P080 merges; if P080 is still open, Step 2 records the coupling and the prose edit moves to a P080 follow-up"), and make Step 2's aid-init.md change conditional on P080's post-merge line numbers rather than today's. Also add the lint-clean AC to Step 2 so a P082 edit cannot re-dirty a file P080 just delisted from GRANDFATHERED.

  - severity: medium
    ref: C0-ARM-5
    summary: >
      Step 7 proposes "the output filename is derived after the checkpoint is known and carries it",
      but the plan's own Constraints declare "Frozen surfaces: evidence filenames" (line 463), and
      the repo ALREADY has a canonical CP3 filename — `verifier-output-cp3-{focus}.md`
      (agents/verifier.md:86, :248; defaults/templates/verifier-output-template.md:39), which
      `fsm_check_streamlined_integration_review` reads literally (aid-fsm.sh:1822-1823). Minting a
      third spelling for CP3 prefilter output crosses a contract several independent readers hold:
      aid-fsm.sh:1229 (the validator), aid-fsm.sh:2477 and :5705 (CP2 preconditions) and
      aid-acceptance-evidence.sh:164 (`evidence_ref="verifier-output-step-${step_num}.md"`). The
      collision Step 7 describes is real (aid-prefilter.sh:96 computes
      `verifier-output-step-${step_n}.md` before the checkpoint branch at :150-166), but the fix must
      land inside the existing naming authority, not beside it.
    evidence: plan line 264 vs plan line 463; plugins/aid-orchestrator/scripts/aid-prefilter.sh:96; agents/verifier.md:86 and :248; aid-fsm.sh:1822-1823, :2477, :5705; scripts/aid-acceptance-evidence.sh:164
    suggested_fix: Name the existing convention in Step 7 — the CP3 classify output is written as `verifier-output-cp3-{focus}.md`, which is not a new surface — and reconcile the Constraints line ("frozen" means no rename of CP2's `verifier-output-step-N.md`, which this step preserves). Add an AC that every current reader of both filenames still resolves after the change, listing them by path.

  - severity: medium
    ref: C0-ARM-6
    summary: >
      Scope claims three P081 leftovers (line 37), one of which is squarely a runtime-boundary
      defect — "the durations journal is written under `.aid-o/` inside the CI checkout and wiped
      every run" — but NO implementation step owns any of the three. The word "durations" appears
      exactly once in the plan, in that scope sentence. This matters for my lens because the fix
      necessarily crosses the CI-checkout / shared-host boundary that the nightly workflow already
      treats as a deliberate decision ("The artifact lands on a shared HOST path, never under
      `.aid-o/`", .github/workflows/nightly-tests.yml:70, writing
      `/opt/eco/data/aid-nightly/aid-orchestrator/*.json` at :93), while the journal itself is
      resolved repo-relative (`AID_DURATIONS_REL=.aid-o/work/test-durations.jsonl`,
      scripts/lib/aid-test-durations.sh:62). Declared-in-scope-but-unowned means an implementer
      improvises where the journal lives and who may write it, on a host path shared with other
      projects.
    evidence: plan line 37 (scope items a/b/c) with no corresponding entry in Steps 1-12; .github/workflows/nightly-tests.yml:70, :93; plugins/aid-orchestrator/scripts/lib/aid-test-durations.sh:62; aid-test-tier-lint.sh:64-65
    suggested_fix: Either add an explicit step that names the journal's home and its writer/reader authority (repo-relative under `.aid-o/` for local, published to the existing host path by the nightly, with the read order stated), or move (a)(b)(c) to Out of scope with the reason. Do not leave a boundary decision to the implementer.

  - severity: low
    ref: C0-ARM-7
    summary: >
      Step 10 says the `add-epic` subcommand "on the executable path no longer accepts a lineage
      argument (or is removed)". The CLI dispatcher forwards straight into the shared function —
      `add-epic) plan_manifest_add_epic "$@"` (aid-plan-manifest.sh:1639) — and that SAME function
      is how the one legitimate producer asserts provenance: `_pfsm_epic_finish_write` passes
      `"proven"` as the 8th positional (aid-plan-fsm.sh:1122-1123). An implementer reading "no
      longer accepts a lineage argument" as "drop the 8th parameter" would silently disarm the only
      authorised producer, turning every epic-start into `unproven` — an authority change in the
      opposite direction, and one the step's own negative test (CLI cannot mint proven) would still
      pass.
    evidence: plan line 361; plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh:1639 and :997-1011 (the documented IMP-265 contract at :977-991); plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:1117-1123
    suggested_fix: State in Step 10 that the restriction lives in `main()`'s dispatcher (reject an 8th positional on the `bash aid-plan-manifest.sh add-epic` path), that the sourced `plan_manifest_add_epic` KEEPS its optional lineage parameter, and add a positive AC that `epic-start` still writes `lineage: proven` after the change — not only the negative CLI test.

confidence: high
