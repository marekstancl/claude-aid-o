# CP1-deep — C0 lens planned_call_feasibility — P083

Lens question: does the plan call an output, API, field, flag or artifact that neither
exists today nor is produced by any step?

Method: every call verified against the real tree at `main` (v2.83.1, HEAD `1d5cd04`).
Executions were done in `git clone --local` at
`/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/50d5999a-.../scratchpad/c0clone`
(workspace `.aid-o` and the tracked backlog copied in). No mutation of the real repo;
`aid-release.sh` was never run.

stop_rule_blockers: none

Every executable call the plan names resolves. Summary of the positive verifications
(these are the "no blocker" evidence, not findings):

- **All 11 AC `cmd:` blocks parse and dispatch.** Ran the real gate command in the clone:
  `aid-plan-diff.sh --plan .aid-o/plans/P083-ten-verified-defects.md --evidence-dir <tmp>
  --base-commit HEAD` → exit 1, `ac_count: 11`, 11 `cmd` rows, 0 skipped. All 10 bats
  suites are `absent` today because they do not exist yet — and each one is declared
  `Create`/`Test:` by its own step (Step 1→`test-streamlined-integration-review.bats`,
  2→`test-ac-extraction.bats`, 3→`test-aid-release-rollback.bats`,
  4→`test-aid-release-readme.bats`, 5→`test-gate-command-required.bats`,
  6→`test-review-signal-toggle.bats`, 7→`test-init-gate-profiles.bats`,
  8→`test-gate-baseline-sequential-only.bats`, 9→`test-c0-plan-graph-input.bats`,
  10→`test-backlog-verdicts.bats`). Confirmed none exist in
  `plugins/aid-orchestrator/scripts/tests/bats/` today. `bats` is on PATH (`/usr/bin/bats`).
- **AC6's nested-quoted `yq` command survives the extractor and runs.** Instrumented
  `run_pattern` (`aid-plan-diff.sh:222`) in the clone to dump `$cmd`; the string reaching
  `timeout … bash -c` is exactly
  `test -n "$(yq -r '.gates.plan_diff.command // ""' .aid-o/config/execution.yaml)"`.
  Run standalone today: exit 1 (correct — the command is absent). After injecting a
  `command:` under `.gates.plan_diff` in the clone's config: exit 0. `yq` is v4.53.2.
  The `.aid-o/config/execution.yaml` file is present inside a plan worktree too
  (verified `.aid-worktrees/plan-P080/.aid-o/config/execution.yaml` exists), so the gate
  is not defeated by the gitignore the plan flags for `project.yaml`.
- **Step 5's `defaults/execution.yaml:109-116` claim is exact.** `plan_diff` block is
  lines 109-116; `command:` at `:113` is
  `plugins/aid-orchestrator/scripts/aid-plan-diff.sh --plan {plan_path} --evidence-dir … --base-commit {base_commit}`,
  and that script exists and is executable (`14649` bytes, mode `rwxrwxr-x`). Invocable —
  ran it end to end above. `aid-plan-diff.sh:164` does accept both
  `## Acceptance Criteria` and `## Success Criteria`, as Step 5 claims.
  Shipped `defaults/execution.yaml` has **no** `gate_profiles` block at all, so Step 5's
  "the shipped defaults pass unchanged" holds trivially.
- **Step 9's `--write-provisional` exists and does what the step needs.**
  `aid-generation-readiness.sh:21` `--write-provisional) out="$2"`; usage documented at
  `:7`; writes the graph at `:39-42`. Ran it against P083 in the clone: exit 0 in 1.1 s,
  emitted `schema: aid-source-plan-graph/v1` with `plan_sha256`, `steps`, `edges`,
  `topological_order`, `cycles`. It takes a plan path only (arg loop `:17-25`), confirming
  the step's "pure function of the plan" premise.
- **Step 7's two named functions behave as described.** `gate_profile_max` exists
  (`lib/aid-gate-profile.sh:225-241`) over the rank table `quick..release` at `:205-211`.
  `_pfsm_has_gate_profiles` (`aid-plan-fsm.sh:9867-9878`) returns 0 when the table has
  `length > 0` — so a `{targeted, full}` table does flip a consumer to `plan_branch`
  (`_pfsm_default_mode:9889-9892`), and `aid-plan-fsm.sh:4485` then
  `gate_profile_max "$required_profile" release` and `:4490-4493` aborts with
  "profile '…' has an empty or missing include[]". Chain confirmed exactly as stated.
  `render_gate_profiles_block` is `lib/aid-init-execution-yaml.sh:206-266`, here-doc
  emitting only `targeted` + `full` at `:259-265`, zero-stacks branch at `:239-242`.
- **Step 1's cited readers all check out** (spot-checked 8 of 8, not 3): writer
  `aid-run-gates.sh:1628` `report_path="${_evidence_dir}/gates/gates_report.json"`;
  readers `aid-fsm.sh:2453, 2880, 2991, 3286, 5262`, `aid-diagnostic.sh:57`,
  `aid-compliance-backfill.sh:103` — every one uses `gates/`. The outlier is
  `aid-fsm.sh:1826` (`local gates="${evidence_dir}/gates_report.json"`) inside
  `fsm_check_streamlined_integration_review` (`:1817`), called from `:6608`.
- **Step 3's claims are literally true.** `UPDATED+=` appears at
  `aid-release.sh:521,528,534,539,595,632,637,647,669`. In the fallback block the
  `.metadata.version` branch (`:650-656`, comment `# Don't double-add` at `:654`), the
  `.plugins[0].version` branch (`:657-662`) and the README `Plugin: ` branch (`:672-675`)
  each rewrite a file and **never** append to `UPDATED[]`.
  `_release_rollback_updated` (`:775-791`) iterates `"${UPDATED[@]:-}"` only. The count
  print is at `:680` (plan says `:681` — off by one, immaterial).
- **Step 2, 6, 8 line ranges verified.** `aid-plan-to-epic.sh` `step_ac` awk `:909-925`
  and `step_ac_raw` awk `:936-948`, both with the same `if (in_ac && $0 ~ /^-[[:space:]]/)`
  line filter; `lib/aid-scoping.sh:140-145` `_aid_extract_files_bullets*` really is
  Files-only, so the backlog's pointer is wrong as the step says.
  `lib/aid-review-signals.sh:21-29` `_aid_read_toggle`, two `grep -qP` at `:24-25`,
  bare `return 0` at `:28` — the fail-open is real.
  `lib/aid-gate-runtime-baseline.sh`: acceptor `:330`, non-sequential branches `:401`,
  `:507-527`, `:535`, `:591`, dispatch default at `:853`, usage string at `:874`.
  `aid-run-gates.sh:1953-1964` is the `skip/no_command` row, `required // false` at `:1945`.
- **Step 9's C0 surfaces exist.** `lib/aid-c0-plan-review.sh` seals
  `generation/provisional-graph.json` at `:385-397` with schema+hash+cycle validation and
  writes `'"absent_pre_generation"'` at `:455-461`.
  `defaults/prompts/c0-plan-review-prompt-v1.md:32` is literally
  "Whole-plan source dependency graph (the pre-generation authority)"; check-table item 2
  is `:42-43`.
- **Step 10's target is committable.** `.gitignore:87` ignores `docs/`, `:93` negates
  `!docs/plans/2026-06-29-BACKLOG.md` — the one file Step 10 edits.

findings:

1. **`defaults/enforcement-registry.yaml` is required by the plan's own Constraints but is
   in no step's Files list — the registration cannot be committed inside declared scope.**
   Plan quote (Constraints): *"Steps 5 and 10 add a refusal inside an existing check; that
   is the only new enforcement surface in the plan, and both are registered in the
   enforcement registry in the same commit that adds them."* The registry exists at
   `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (the path named in
   `CLAUDE.md`, `docs/plans/AID-audit-2026-06/enforcement-registry.yaml`, does **not**
   exist — `ls` errors). No Files list in Steps 1-10 names it. Scope is enforced: gate
   `scope_check` runs `gates/scope-check.sh … allowed_paths.txt` (`defaults/execution.yaml:103`),
   and `allowed_paths` is derived from the Files lists. Secondary: the constraint names
   **Step 10** as adding a refusal; Step 10 is the backlog-verdict step with no refusal in
   it — the refusing step is **Step 6** ("the unreadable case is a named failure, not a
   silent `return 0`"). Severity: medium — an implementer either violates scope or drops
   a stated obligation.

2. **Step 7's test calls `gate_profile_max` to answer a question that function cannot
   answer.** Plan quote (Step 7 Test): *"`gate_profile_max <anything> release` resolves
   against it"*. `gate_profile_max` (`lib/aid-gate-profile.sh:225-241`) reads only the
   static `_AID_GATE_PROFILE_RANK` map at `:205-211`; it never opens an `execution.yaml`
   and cannot see a composed profile table. `gate_profile_max targeted release` returns
   `release` today, on any repo, with or without a `release` profile — so the assertion as
   written passes vacuously. The function that actually reads the composed table is
   `_pfsm_profile_include "$execution_yaml" "$resolved"` (`aid-plan-fsm.sh:4490`), whose
   empty result is the abort the step is trying to prevent. Severity: medium — the test
   named in the step would not pin the defect.

3. **Step 8's AC1 uses `grep -c`, which returns a count, and then describes line content.**
   Plan quote (Step 8 AC): *"`grep -c 'observe_parallel\|parallel' aid-gate-runtime-baseline.sh`
   returns only the refusal message and the read-compat handling."* Run today against
   `plugins/aid-orchestrator/scripts/lib/aid-gate-runtime-baseline.sh`: output is `4`.
   `-c` can never return "the refusal message"; the AC is not executable as written and has
   no verification_pattern of its own (AC9's `cmd:` runs the suite instead). Severity: low
   — prose AC, but it is the only place the deletion's completeness is stated.

4. **Step 5 undercounts the affected profiles by one and never names
   `bats_all_quarantine`.** Plan quote (Step 5 Architecture Context): *"the gate sits in
   four merge-path profiles"*; Edge Cases: *"`release_quarantine` — treated exactly as the
   other three profiles."* Measured on `.aid-o/config/execution.yaml`: `plan_diff` appears
   in **five** — `standard`, `full`, `release`, `bats_all_quarantine`, `release_quarantine`
   (enumerated by iterating `gate_profiles.*.include[]` and testing
   `.gates.plan_diff.command // "NULL"`; all five report `NO_COMMAND`). `bats_all_quarantine`
   is the one the plan never mentions. AC5 ("no profile … includes a gate without a
   `command`") still covers it, so this is descriptive drift, not an unbuildable call.
   Severity: low.

5. **Step 9's stated measurement of the provisional graph does not reproduce.** Plan quote:
   *"it exited 0 in about a second and emitted `aid-source-plan-graph/v1` with 11 steps,
   2 edges, no cycles, bound to the plan's own sha256."* Reproduced in the clone: exit 0,
   1.1 s, schema and sha binding correct, **but `steps = 10` and `edges = 1`** — which is
   what this plan's ten steps and its single `Step 4 depends on Step 3` edge should give.
   The 11/2 figures belong to some other (earlier or P082) draft. The artifact is
   producible, so this is a provenance defect in the stated evidence, not an infeasible
   call. Severity: low, but it is exactly the class of stale-paraphrase the plan's Context
   section says it exists to avoid.

6. **Step 9's Files line range does not contain the place the production must be inserted.**
   Plan quote: *"Modify: `plugins/aid-orchestrator/scripts/lib/aid-c0-plan-review.sh`
   (lines ~440-465) — `build-manifest` produces the provisional graph itself … before
   sealing the manifest."* The presence probe that would have to be preceded by the
   production is `:386-387` (`source_graph_rel` / `source_graph_present`), and the
   validation gate is `:388-397`; `440-465` is only the entry-assembly tail. The `~` makes
   this survivable, but an implementer honouring the range literally would insert the call
   after the presence test and produce nothing. Severity: low.

7. **This plan's own AC line format yields empty `ac_label`/`ac_text` in the very
   `plan-diff.json` Step 5 makes a required gate.** Observed in the live run above: all 11
   result rows carry `"ac_label": ""` and `"ac_text": ""`. Cause is
   `aid-plan-diff.sh:167`, which recognises `- [ ] AC<N>:` (colon) or `- [ ] [role]`; P083
   writes `- [ ] AC1 — …` (em dash). Verdicts are still computed per pattern, so nothing
   fails — but the evidence Step 5 is restoring the gate to produce will be unlabelled for
   this plan. Severity: low, and cheap to avoid by writing `- [ ] AC1: …`.

confidence: high

Every claim above was executed or read first-hand at the cited line; the only calls I did
not exercise end to end are the ten not-yet-existing bats suites (necessarily) and
`aid-release.sh` (forbidden). No planned call was found that neither exists nor is created
by a step, so the lens's stop rule is not tripped.
