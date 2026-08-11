# CP1-deep — Lens L2 FEASIBILITY — P083

Plan: `.aid-o/plans/P083-ten-verified-defects.md` (497 lines, risk: high, 10 steps / 3 EPICs)
Repo: `/opt/eco/projects/aid-orchestrator` @ `main` (HEAD `1d5cd04`, v2.83.1)
Method: every claim re-verified against the real tree; all experiments in a `git clone --local`
under `/tmp/claude-1000/-opt-eco-projects-aid-orchestrator/50d5999a-d6f6-42c1-a512-479b5d12dbb9/scratchpad/repo`.
The primary checkout was not mutated.

## What was executed (not eyeballed)

1. **P082's killer check.** Sourced `plugins/aid-orchestrator/scripts/lib/aid-scoping.sh` and called
   `_aid_files_bullet_tier` on each of the 10 `- Test:` bullets verbatim. **All 10 return rc=0**
   (9 × `t1`, 1 × `t0` for Step 10). All 10 suites are genuinely new (`ls` — none exist), so the
   `aid-plan-to-epic.sh:1064` refusal is the live path and it does not fire. P082's failure mode
   does not recur.
2. **`aid-plan-lint.sh`** on the plan → `PASS — all Files entries are canonical.` (exit 0).
3. **`aid-generation-readiness.sh --write-provisional`** → `READINESS: PASS`, graph
   `aid-source-plan-graph/v1`, plan-sha-bound, acyclic (exit 0).
4. **Full generation dry-run in the clone** — `aid-plan-to-epic.sh` phases 1/2/3 (CP1-deep + C0
   stubbed with a PM override, since those are exactly what this review produces) → all three EPIC
   files generated; then `aid-epic-to-json.sh` on each → EPIC 1 and 2 produce valid `plan.json`,
   **EPIC 3 hard-fails** (see B1).
5. **`aid-plan-diff.sh --plan … --evidence-dir <tmp> --base-commit HEAD`** → `ac_count: 11` ✅,
   exit **1** (all 11 `absent`, expected pre-implementation). All 11 `cmd:` strings extracted through
   the script's own `extract_yaml_val` and checked with `bash -n` → **11/11 well-formed**, including
   AC6, whose `\"$(yq -r '… // \"\"' …)\"` unescapes correctly to
   `test -n "$(yq -r '.gates.plan_diff.command // ""' .aid-o/config/execution.yaml)"`.
6. Every named file opened; every named line range read; producers/consumers grepped.

stop_rule_blockers: 2

findings:

- severity: blocker
  ref: "Step 10 — `**AID Role:** docs` (plan line 383)"
  summary: "EPIC 3 cannot be converted to plan.json. `docs` is not a valid AID role; the enum is `docs-writer`. Reproduced end to end."
  evidence: |
    Plan line 383: `**AID Role:** docs` (the only non-`backend` role in the plan).
    Generation carries it into the EPIC Steps table (`| 3 | docs | … |`) and
    `aid-epic-to-json.sh:234` refuses it against `VALID_ROLES` at `:63`:
      VALID_ROLES="architect domain backend frontend qa security observability docs-writer release e2e"
    Live run in the clone:
      $ aid-epic-to-json.sh --epic E-083-3_3-….md --schema …/plan.schema.json --output-dir …
      {"error": "Invalid role 'docs' in step 3. Valid roles: architect domain backend frontend qa security observability docs-writer release e2e", "code": 1}
    Patching the table row to `docs-writer` in the clone makes the same command succeed and emit
    `step_3_docs_writer` with correct `allowed_paths`. Same enum is duplicated at
    `aid-epic-to-json.sh:866` and in `defaults/templates/plan.schema.json`.
    Note the failure surfaces AFTER `aid-plan-to-epic.sh` succeeds — i.e. after the CP1/C0 gates
    have been consumed — so it strands EPIC 3 at the machine-conversion step, exactly the P082
    "ungeneratable" shape.
  suggested_fix: "Change plan line 383 to `**AID Role:** docs-writer`."

- severity: blocker
  ref: "Step 5 — `required: true` on `plan_diff` vs. AC9/AC10/AC11 landing only in EPIC 3"
  summary: "Step 5 makes a gate blocking that evaluates ALL 11 of the plan's acceptance criteria, including three whose suites are created two EPICs later. EPIC 2's own gate run therefore cannot pass: a consumer reads what no step has produced yet."
  evidence: |
    Plan line 199: the self-host `plan_diff` gate "regains the `command:` … and an explicit
    `required: true`". Step 5 is EPIC 2 step 1.
    The gate command (`defaults/execution.yaml:113`) is
      aid-plan-diff.sh --plan {plan_path} --evidence-dir … --base-commit {base_commit}
    and `{plan_path}` resolves to the SOURCE PLAN, not the EPIC (`aid-run-gates.sh:204`,
    `:1636` reads `plan_path:` from fsm-state.yaml). So every EPIC-level gate run evaluates the
    whole of P083 — all 11 ACs.
    `aid-plan-diff.sh:365` — `[[ "$absent_count" -gt 0 ]] && exit 1`. Exit 1, not the
    pass_criteria-tolerated exit 2 (`aid-run-gates.sh:2083` only converts exit **2** to `skip`).
    `aid-run-gates.sh:2001` — `if [[ "${required:-false}" == "true" ]]; then overall="fail"; fi`.
    Measured now: `aid-plan-diff.sh --plan .aid-o/plans/P083-ten-verified-defects.md …` →
    ac_count 11, absent 11, **exit 1**.
    Sequence after Step 5 lands: EPIC 2 finishes with AC1–AC8's suites on disk; AC9
    (`test-gate-baseline-sequential-only.bats`), AC10 (`test-c0-plan-graph-input.bats`) and AC11
    (`test-backlog-verdicts.bats`) are Steps 8/9/10 = EPIC 3. `plan_diff` therefore exits 1 on
    EPIC 2's gate run and, being `required: true`, sets `overall=fail`.
    `plan_diff` is in the `standard` (:365), `full` (:390), `release` (:397) and
    `release_quarantine` (:436) profiles of `.aid-o/config/execution.yaml`, and omitting
    `--profile` runs *all* gates (`aid-run-gates.sh:24`) — there is no EPIC-level profile in this
    repo's config that both runs gates and excludes it except `p064-closure`.
    Today this is harmless only because the gate has no `command` and no `required`, so it records
    `skip/no_command` (`aid-run-gates.sh:1953-1962`) — the very state Step 5 removes.
  suggested_fix: |
    Either (a) restore the `command:` but leave `required: false` for the duration of this plan and
    let the plan-final `release` run (where all 11 suites exist) be the blocking one — the runner-side
    refusal in Step 5 lands regardless and is the part that carries the value; or (b) move Step 5 to
    EPIC 3 after Step 10 so no later EPIC gate run is held to criteria the plan has not produced yet;
    or (c) state explicitly in Step 5 that EPIC 2/3 gate runs are expected to fail `plan_diff` and
    name the audited force path — but that reintroduces exactly the "correct run pushed toward a
    force waiver" failure Step 1 exists to remove.

- severity: medium
  ref: "Step 5 — Architecture Context, plan line 203"
  summary: "\"Because `.aid-o/` is gitignored there is no history to say when the command disappeared\" is false: the file is tracked and has 16 commits."
  evidence: |
    `git ls-files .aid-o/config/` → `counter.yaml`, `execution.yaml`, `test-catalog.yaml`.
    `git log --oneline -- .aid-o/config/execution.yaml | wc -l` → 16; first added `2fd1f1b`
    (2026-08-04).
    The *conclusion* survives in a narrower form: `git log -S 'aid-plan-diff.sh --plan' --
    .aid-o/config/execution.yaml` returns nothing, i.e. the command was never present in the
    tracked window (which starts 2026-08-04) — so history exists, it simply predates nothing useful.
    The stated reason is wrong and the same wrong premise ("`.aid-o/` therefore has no history")
    is load-bearing for the step's argument that the runner-side refusal matters more than the
    config fix.
    Side effect that is *good* for feasibility: because the file IS tracked, Step 5's Modify does
    produce a committed diff.
  suggested_fix: "Reword to: tracked since 2026-08-04; `git log -S` over that window shows the command was never present, so the removal predates tracking."

- severity: medium
  ref: "Step 9 — Implementation Detail, plan line 334"
  summary: "\"emitted `aid-source-plan-graph/v1` with 11 steps, 2 edges\" — the real numbers are 10 steps and 1 edge."
  evidence: |
    $ aid-generation-readiness.sh .aid-o/plans/P083-ten-verified-defects.md --write-provisional <tmp>
      READINESS: PASS  (exit 0, ~1 s — the timing claim holds)
    $ jq '{n_steps:(.steps|length), n_edges:(.edges|length), edges:.edges}' <tmp>
      { "n_steps": 10, "n_edges": 1, "edges": [ {"before":"step-3","after":"step-4"} ] }
    The plan has 10 steps and one declared dependency (Step 4 → Step 3). "11 steps, 2 edges" is
    almost certainly carried over from a draft. The step's *conclusion* — the graph is a pure
    function of the plan text and needs no generation state — is independently confirmed:
    `aid-generation-readiness.sh:16-27` takes only a plan path, and
    `lib/aid-c0-plan-review.sh:385-397` already validates schema, plan-hash binding and cycles when
    the artifact is present, so `build-manifest` producing it first is mechanically sound.
  suggested_fix: "Correct to 10 steps / 1 edge, or re-run and paste the actual jq output."

- severity: medium
  ref: "Step 5 — Implementation Detail, plan line 205"
  summary: "\"`aid-plan-diff.sh --plan <this plan> …` exits 0\" is not true of the plan as written: it exits 1 with 11/11 absent."
  evidence: |
    Re-run verbatim against the final plan text:
      ac_count 11, present 0, absent 11, overall "fail", exit 1.
    Exit 1 is the correct pre-implementation verdict, so the claim is stale rather than harmful on
    its own — but it is the measurement Step 5's whole restore-not-remove decision is anchored to,
    in a plan whose stated reason for existing is that P082 died of second-hand facts. It also
    directly feeds blocker 2 above: the reviewer reading "exits 0" has no reason to notice that
    `required: true` makes an exit-1 gate blocking.
  suggested_fix: "Restate as: parses 11 ACs and produces a valid plan-diff.json; exits 1 today because none of the 11 suites exist yet, and will exit 0 once the plan lands."

- severity: medium
  ref: "Constraints (plan line 479) vs. every step's Files list"
  summary: "The plan requires two new enforcements to be registered in the enforcement registry \"in the same commit that adds them\", but no step's Files list names the registry file — the edit has no declared home and falls outside every step's allowed_paths."
  evidence: |
    Plan line 479: "Steps 5 and 10 add a refusal *inside an existing check* … and both are
    registered in the enforcement registry in the same commit that adds them."
    Live registry: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` (the archived copy
    at `docs/plans/archive/AID-audit-2026-06/enforcement-registry.yaml` is under the ignored
    `docs/` tree — `.gitignore:87` with only `!docs/plans/2026-06-29-BACKLOG.md` negated, confirmed
    via `git check-ignore`).
    Generated `plan.json` allowed_paths (from the clone dry-run):
      EPIC2 step_1 → [".aid-o/config/execution.yaml", "…/aid-run-gates.sh", "…/test-gate-command-required.bats"]
      EPIC3 step_3 → ["docs/plans/2026-06-29-BACKLOG.md", "…/test-backlog-verdicts.bats"]
    Neither includes the registry. `scope_check` happens not to be defined in this repo's own
    `execution.yaml`, so no gate blocks it today — which makes it a silent scope escape rather than
    a loud one.
    (Also: "Steps 5 and 10" is itself odd — Step 10 is a backlog-annotation step with no new
    refusal in code; the refusal the constraint means is Step 5's, and possibly Step 8's
    non-sequential-context refusal, which the constraint does not mention.)
  suggested_fix: "Add `Modify: plugins/aid-orchestrator/defaults/enforcement-registry.yaml` to Step 5's Files list (and Step 8's, if its named refusal counts), and fix the step numbers in the constraint."

- severity: medium
  ref: "Steps 3 and 4 — overlapping edits to `aid-release.sh`"
  summary: "The two declared ranges overlap on the README loop; Step 3's fix to the `Plugin:` branch is inside the block Step 4 rewrites, and Step 4 carries no acceptance criterion pinning the UPDATED[]/count invariant Step 3 established."
  evidence: |
    Verified line numbers in `plugins/aid-orchestrator/scripts/aid-release.sh`:
      :651-656  `.metadata.version` branch, `# Don't double-add` at :654 — no `UPDATED+=`
      :657-662  `.plugins[0].version` branch — no `UPDATED+=`
      :666-676  README loop; :667-670 the `v$CURRENT` sed (which DOES `UPDATED+=` at :669),
                :672-675 the `Plugin: ` branch — no `UPDATED+=`
      :680      `echo "Updated ${#UPDATED[@]} files total."`
      :775-791  `_release_rollback_updated` — iterates `${UPDATED[@]}` only
    Step 3 declares `~645-681` and explicitly names `:672-675`; Step 4 declares `~660-677` and
    replaces the whole README loop. The overlap is 660-677. The dependency IS declared
    (Step 4 "Depends on: Step 3", Step 3 "Blocks: Step 4") and the generated graph carries exactly
    that one edge, so the ordering is enforced — this is not a blocker. But Step 3's ACs
    ("printed count equals the number of files the rollback restores") are asserted by a suite that
    exercises the pre-Step-4 README path, and Step 4's three ACs say nothing about `UPDATED[]`.
    A Step 4 rewrite that forgets `UPDATED+=("$readme")` on its new anchored path would pass all of
    Step 4's own criteria and silently re-open Step 3's defect.
  suggested_fix: "Add a fourth AC to Step 4: every README the anchored updater edits is recorded in UPDATED[] exactly once and is restored by an aborted prepare — and have test-aid-release-readme.bats assert it, not only test-aid-release-rollback.bats."

- severity: medium
  ref: "Step 9 — Acceptance Criterion 1 (plan line 348)"
  summary: "\"No shipped prompt describes an artifact the manifest records as absent\" is unsatisfiable as literally written, because the per-EPIC contract graph legitimately stays absent pre-generation and the prompt describes it."
  evidence: |
    `lib/aid-c0-plan-review.sh:377-379` — `plan_graph_rel="$evidence_dir_rel/c0/plan-graph.json"`,
    genuinely a post-generation artifact; `:449-454` seals `"absent_pre_generation"` for it.
    Step 9 fixes only `source_graph_rel` (`generation/provisional-graph.json`, `:385-387`).
    `defaults/prompts/c0-plan-review-prompt-v1.md:31` still says
      "- Per-EPIC contract graph (may be absent before generation): `{{plan_graph_path}}`"
    so after Step 9 a prompt still describes an artifact the manifest records as absent — arguably
    satisfied by the parenthetical, but the criterion as phrased has no mechanical reading that
    passes. Line 31 is inside the declared `~30-45` range, but the Files bullet only mentions
    "mandatory check-table item 2" (:40-42), so the implementer has no instruction to touch it.
  suggested_fix: "Rephrase AC1 to scope it to the source dependency graph, e.g. \"the whole-plan source dependency graph is never recorded as absent for a lint-clean plan\", and say in the Files bullet that line 31's parenthetical is kept deliberately."

- severity: low
  ref: "Step 8 — Acceptance Criterion 1 (plan line 316)"
  summary: "`grep -c` returns a number; the criterion asserts it \"returns only the refusal message and the read-compat handling\". Not machine-checkable as written."
  evidence: |
    Plan line 316: "- [ ] `grep -c 'observe_parallel\\|parallel' aid-gate-runtime-baseline.sh`
    returns only the refusal message and the read-compat handling."
    `-c` prints a count. The intended check is presumably `grep -n` plus a human/asserted
    line-set, or a `-c` against an expected number. AC9's bats suite is the real machine check,
    so this is a step-AC quality issue, not a gate risk.
  suggested_fix: "Either `grep -n … | wc -l` against an asserted number, or drop the grep and let the bats suite carry it."

- severity: low
  ref: "Several steps — line-reference drift"
  summary: "A handful of cited line numbers are off by one or two, or the cited range only partly covers the construct named. All verified as pointing at the right code."
  evidence: |
    Verified vs. plan text:
      Step 1: `aid-fsm.sh` fn at 1817, flat path at **:1824**, message 1834-1836, caller 6608 — ✅
              writer `aid-run-gates.sh:1628-1629` ✅; readers 2453/2880/2991/3286/5262 ✅;
              `aid-diagnostic.sh:57`, `aid-compliance-backfill.sh:103` ✅.
              Also confirmed the precondition's `evidence_dir` is the RUN dir
              (`aid-fsm.sh:6604` → `.aid-o/work/evidence/{epic}/{run_id}`), the same shape the
              writer uses — so the proposed fix genuinely lands on the written path.
      Step 2: `step_ac` 909-925 ✅, `step_ac_raw` 936-**948** (plan says 936-949) — the filter
              `if (in_ac && $0 ~ /^-[[:space:]]/)` is present in both copies exactly as described.
      Step 3: 651-656 / 657-662 / 672-675 / :680 (plan says :681 for the count) / 775-791 ✅.
      Step 5: `.aid-o/config/execution.yaml` `plan_diff` block is **223-244** (plan says ~218-228);
              the "P038+" note is at 224-225. Runner no-command branch is **1943-1964**
              (plan says ~1944-1963). ✅ in substance.
      Step 6: `_aid_read_toggle` at **22-30** (plan ~20-30) ✅ — two `grep -qP` inside one `if`,
              `return 0` on failure = fail-open, exactly as described.
      Step 7: `render_gate_profiles_block` 206-266, here-doc 256-265 emitting only
              `targeted`+`full`, zero-stacks branch 239-242 ✅ — all three exact.
              Chain confirmed: `plan-boundary-policy.yaml:28` `default_mode: plan_branch`,
              `:37` `plan_final_profile_floor: release`; `_pfsm_has_gate_profiles`
              `aid-plan-fsm.sh:9867-9879`; abort text at `:4492-4494`. `defaults/execution.yaml`
              has no `gate_profiles` key — the P064 decision Step 7 promises not to reverse.
      Step 8: acceptor **329-335** (plan 329-333), :401, :507-527, dispatch **:853** ✅ exact,
              usage string **:874** ✅ exact. Producers: `aid-run-gates.sh:2023` (plan :2024) and
              `:2100` (plan :2101), `aid-fsm.sh:3768-3770` (plan 3762-3769) — all hardcode
              `sequential`, as claimed.
      Step 9: manifest 447-460 (plan ~440-465) ✅; prompt "the pre-generation authority" at
              **:32** ✅ exact.
      Step 4 anchors: root `README.md:3` still `v2.69.0` ✅, list under `## Changelog` (:118) with
              `- **v2.83.1** (current)` at :120 ✅, no `## Roadmap` anywhere ✅;
              plugin README `- **Plugin:** 2.83.1` at :3, no list ✅.
      Step 3 premise: `.aid-o/config/project.yaml` is NOT in `git ls-files` → a clone/worktree
              genuinely takes the fallback ✅.
  suggested_fix: "Optional. Tighten Step 5's `~218-228` to 223-244 and Step 2's 936-949 to 936-948; the rest are within the plan's own `~` tolerance."

- severity: low
  ref: "Plan `## Acceptance Criteria` — `- [ ] AC1 — …` bullet form"
  summary: "`aid-plan-diff.sh` finds all 11 verification patterns but records every `ac_label`/`ac_text` as empty, because its parser wants `AC1:` (colon) and the plan writes `AC1 —` (em dash)."
  evidence: |
    `aid-plan-diff.sh:167` — `if ($0 ~ /^- \[[ x]\] AC[0-9]+:/ || $0 ~ /^- \[[ x]\] \[[a-z_]+\]/)`.
    The plan's bullets are `- [ ] AC6 — The self-host \`plan_diff\` gate has a command again.`
    Result of the live run: all 11 rows carry `"ac_label": ""`, `"ac_text": ""`, while
    `ac_count` is correctly 11 and each pattern is executed. Verdicts and exit code are unaffected;
    only the evidence artifact is unreadable ("which AC failed?" cannot be answered from
    plan-diff.json). Relevant because Step 5 makes this artifact a blocking gate's output.
  suggested_fix: "Write the bullets as `- [ ] AC1: The streamlined integration review …` so the labels survive into plan-diff.json. Cheap, and it makes the gate's own evidence legible."

confidence: high

Rationale for the confidence level: every claim above is backed by a command whose output is
quoted, both blockers were reproduced (B1 end-to-end in a clone, B2 from the three code paths that
compose it plus a live `aid-plan-diff.sh` exit code), and the plan was driven through lint,
readiness, all three generation phases and all three JSON conversions. The residual uncertainty is
confined to B2's blast radius — which gate profile an EPIC-level run actually selects in this repo
is decided at dispatch time and I did not run a full `aid-run-gates.sh` EPIC cycle; `plan_diff` is
in `standard`/`full`/`release` and an unprofiled run executes every gate, so at least one blocking
path exists under every configuration I could read, but the exact EPIC that first trips it could
be 2 or 3.
