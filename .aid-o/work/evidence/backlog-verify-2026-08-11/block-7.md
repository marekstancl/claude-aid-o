# Backlog verification — block 7 (IMP-471, 490, 491, 492, 493, 495, 496)

Repo `/opt/eco/projects/aid-orchestrator`, branch `main` @ `3da7331` (v2.83.1).
All file:line references opened first-hand. Experiments run in
`git clone --local` at `<scratchpad>/rel2`; the real repo was never mutated.

---

## IMP-471 — standing whole-plan auto-GO as a mechanically consumed record

verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/aid-fsm.sh:353-359` — `_active_runs_auto_controller()`
  is the ONLY source of a run's auto flag: `[[ "${AID_AUTO_MODE:-}" == "1" ]]` →
  `active`, else `manual`. It is an environment variable read at init time.
- `aid-fsm.sh:344` `AID_ACTIVE_RUN_FIELDS="auto_controller resume_artifact"`,
  `:472-492` — the value is stamped per-EPIC into the **active-runs map**
  (`upsert_active_run`), not into `fsm-state.yaml` as the entry says.
- `aid-fsm.sh:3702-3709` — `auto_controller` is re-asserted `active` only when
  the CURRENT invocation is itself an auto run; there is no read of any
  plan-scoped record.
- `grep -rn "pm-auto-go" plugins/aid-orchestrator/` returns exactly ONE hit —
  a prose comment in `scripts/lib/aid-obligations.sh:17`. No writer, no reader.
  The live prototype file exists only as a hand-written artifact:
  `.aid-o/work/plan-state/P076/pm-auto-go.json`.
- The PHASE-END rule is prose: `plugins/aid-orchestrator/skills/run-management.md:23`
  — "**PHASE-END = HARD STOP** — stop, summarize what was done, wait for PM GO".
  (Entry cites `:24`; it is line 23 on main. Same line, off-by-one.)

what_is_true: The entry is accurate in substance with two corrections. (1) The
mode lives in the active-runs map, not `fsm-state.yaml`. (2) It is not "passed
as `--auto`" to the FSM at all — it is the env var `AID_AUTO_MODE=1`, which a
fresh session or a chained next-EPIC init simply will not have set, so the run
is honestly stamped `manual`. `pm-auto-go.json` is confirmed to be a record
with zero mechanical consumers — the AID-v3 §1 "detector without enforcement"
shape, in its purest form: a file whose only mention in the codebase is a
comment about where files like it live.

impact: Between EPICs of a chained plan the PM's standing GO evaporates. A
controller that resumes the chain without `AID_AUTO_MODE=1` in its environment
degrades to manual and stops for a GO the PM already gave — the exact stall the
P076 run hit. There is no place to record the GO that anything reads, so the
only recovery is the PM repeating himself in chat.

fix_sketch: Add `pm-auto-go.json` (schema: grantor/granted_at/scope/expiry) written
by a `pm-override grant`-family subcommand in `aid-plan-fsm.sh`, and make
`_active_runs_auto_controller` fall back to reading the plan's record when
`AID_AUTO_MODE` is unset — plus the revoke record and the `/aid-status` render.
effort: M (the record + writer + the one read in `_active_runs_auto_controller`
is half a day; the PHASE-END consumer and the audited manual-flip exception push
it to the top of M).

---

## IMP-490 — plan-final cannot be force-completed past a dead stage

verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh:4744-4748` — when any
  plan-final gate assertion fails: "the plan stays in PLAN_GATES and no
  transition was made". A bare `return 1`; not routed through the force framework.
- `aid-plan-fsm.sh:4426` — `--stage gates` runs ONLY out of `PLAN_GATES`;
  `:5887` — `--stage review` refuses without a frozen candidate and names
  sync/freeze/gates as prerequisites; `:6463` — `--stage c4` likewise. The
  stages are strictly ordered and each demands the prior state.
- `aid-plan-fsm.sh:6779-6782` — the ONLY forceable precondition on
  `plan-finalize` is `clean_worktree`. Every state/assertion refusal above is a
  plain `echo … >&2; exit 1`, i.e. `_pfsm_handle_force`'s "NOTICE: … none of its
  preconditions is wired to the forceable classifier yet" case (`:667`).
- `aid-plan-fsm.sh:6635` — `--stage summary` refuses without
  `release_decision.plan_summary`, i.e. without the C4 artifact.
- The force/waiver machinery the entry wants to reuse does exist and is real:
  `aid-plan-fsm.sh:428-509` (`_pfsm_precondition <name> forceable|hard`),
  `:487` (≥20-char reason), `:538-583` (fail-closed waiver artifact),
  `:606-619` (timeline `plan_force_override` + cross-plan audit).

what_is_true: Confirmed — there is no PM-forceable path from a BLOCKED
plan-final stage to the next one. Two nuances the entry omits:
1. A narrower escape hatch DOES exist for a specific case:
   `--substitute-receipt <gate_id>=<path>` plus gate quarantine
   (`aid-plan-fsm.sh:4599-4726`). A quarantined gate may report `waived` /
   `unverifiable` / `fail` provided a `quarantine_substitutes[]` entry bound to
   the candidate AND base SHA, with `exit_code == 0` and `failed == 0`, is
   present. That is a *narrower and stricter* thing than a stage waiver: it
   still demands a real, passing, targeted run. It does not cover "the broad
   suite's cap expired 9× and produced no result at all".
2. `plan_diff` is explicitly excluded from any substitute path (`:4700-4701`).
   Any stage-waiver design must keep that exclusion or it becomes the fraud path.

impact: When a plan-final gate cannot complete (not fails — cannot complete),
the honest options are (a) fabricate the C4 artifact, or (b) leave the FSM and
merge by hand. P076/v2.80.0 took (b). Every such event costs the release its
artifact chain: no `release-decision.json`, no plan tag through `tag-plan`, and
the plan record says the ceremony ran only through the inputs stage.

fix_sketch: Route the three stage-entry state checks (`:4426`, `:5887`, `:6463`)
and the gates-assertion refusal (`:4744`) through
`_pfsm_precondition <name> forceable`, and have the bypass write `stage_status:
waived` (never `passed`) into the plan-final run record so `--stage c4` can emit
a `release-decision.json` carrying `waivers_applied[]` with the receipt id.
effort: M–L (the wiring is M; the honest part — C4 rendering a decision that
says "gates: waived by PM <receipt>" without any downstream consumer treating
`waived` as `passed`, plus the `plan_diff`-is-never-waivable carve-out — is what
makes it L).

---

## IMP-491 — `aid-release.sh` rollback leaves `marketplace.json` on the new version

verdict: REAL (reproduced first-hand)

evidence:
- `plugins/aid-orchestrator/scripts/aid-release.sh:645-662` — in the no-config
  fallback the `.version` branch does `UPDATED+=("$jf")` (`:647`), but the
  `.metadata.version` branch (`:651-656`, comment `# Don't double-add`) and the
  `.plugins[0].version` branch (`:657-662`) do NOT. `.claude-plugin/marketplace.json`
  has keys `metadata,name,owner,plugins` — **no top-level `.version`** — so `:647`
  never fires for it and the file never enters `UPDATED[]` at all.
- `aid-release.sh:775-791` — `_release_rollback_updated()` iterates
  `"${UPDATED[@]:-}"` and nothing else, and its message (`:789`) enumerates
  `$restored`, i.e. exactly what it iterated.
- Same class one screen lower: `:672-675`, the README `Plugin: ` branch, also
  omits `UPDATED+=`.
- **Reproduced** in `<scratchpad>/rel2` (clone of main, branch `plan/PTEST`):
  `bash plugins/aid-orchestrator/scripts/aid-release.sh prepare-plan P999 --bump patch --plan-branch plan/PTEST`
  → prints 7 `Updated:` lines but "Updated 4 files total.", CHANGELOG validation
  fails, then:
  `Rolled back this run's version-file edits …: CHANGELOG.md plugins/aid-orchestrator/CHANGELOG.md plugins/aid-orchestrator/.claude-plugin/plugin.json README.md`
  — marketplace.json absent from the list. Post-state:
  `jq '.metadata.version, .plugins[0].version'` = `2.83.2` (bumped) while
  everything else is back at `2.83.1`; `git status --porcelain` =
  `M .claude-plugin/marketplace.json`.

what_is_true: The entry is correct and the mechanism is exactly as the earlier
review described. The critical detail nobody has written down yet is **why the
main checkout looks safe and a real release is not**: `_release_update_files`
has two paths (`aid-release.sh:544-598` config-driven vs `:599-677` fallback).
The config path reads `.aid-o/config/project.yaml → versioning.files[]`, which
in this repo DOES list both marketplace.json fields, and it collects every
touched file into `UPDATED[]` via the temp-file loop (`:589-597`). But
`.aid-o/` is gitignored (`.gitignore:96`) and `project.yaml` is untracked —
so **any clone or `git worktree` takes the fallback path**. Verified:
`.aid-worktrees/plan-P080/.aid-o/config/project.yaml` does not exist. Since AID
runs its plan-final releases inside plan worktrees, the fallback path is the
LIVE release path, not a hypothetical.

Two further defects in the same fallback block, both first-hand from the run
above: the "Updated N files total" count (`:681`) is derived from `UPDATED[]`
and therefore under-reports (said 4, printed 7); and because `prepare-plan`
stages only `"${UPDATED[@]}"` (`:1050-1055`), a *successful* fallback-path
prepare would freeze a candidate commit **missing the marketplace.json bump
entirely** — a worse failure than the rollback one, and the plausible root of
IMP-482's "release script renames a tagged version" family.

impact: Every release run from a worktree/clone. On a rollback the operator is
told the tree is back at base while marketplace.json is one version ahead — the
next run re-derives CURRENT and can bump from the wrong base. On a success the
frozen, reviewed candidate silently omits two of the eight registry locations.

fix_sketch: Add `UPDATED+=("$jf")` to the `.metadata.version` and
`.plugins[0].version` branches (`:651-662`) and to the README `Plugin: ` branch
(`:672-675`), guarding against duplicates with a small
`_release_mark_updated <path>` helper that appends only if absent — the "don't
double-add" intent was right, the implementation dropped the file instead of
de-duplicating it.
effort: S (three call sites + one 5-line helper; the one bats case the entry
asks for — interrupted release → rollback → all 8 locations byte-equal —
runs cleanly in a `git clone --local` fixture with no `project.yaml`).

---

## IMP-492 — the catalog's root `status` field after the parallelism removal

verdict: REAL (the CORRECTION is true; the original Summary is false and must be replaced)

evidence:
- `plugins/aid-orchestrator/scripts/lib/aid-test-audit-command-allowlist.sh:117-119`
  — verbatim:
  `status="$(jq -r '.status // empty' <<<"$catalog_json")"` /
  `[[ "$status" == "approved" ]] || return 1`. This is inside
  `_tacl_matches_approved_catalog_command`.
- `.aid-o/config/test-catalog.yaml:3` — `status: proposed` (live value, and the
  file IS force-tracked: `git ls-files` returns it).
- `plugins/aid-orchestrator/scripts/aid-test-catalog-approve.sh:136` —
  `approved_json="$(jq -c '.status = "approved"' <<<"$proposed_json")"`. The
  field has a sanctioned writer.
- `plugins/aid-orchestrator/defaults/schemas/test-catalog.schema.json` — `status`
  is in `required[]`, enum `["proposed","approved"]`, with a description that
  already assigns it a meaning ("proposed = gitignored, evidence-only … approved
  = force-tracked … written only by the explicit catalog-approval step").
- `plugins/aid-orchestrator/scripts/aid-select-tests.sh:269,295` — the selector
  gates on `.mapping_approval.status` and per-row `.status`, never the root
  field. So the entry is right that the selector is a different reader.
- Commit `5f24304` = "config: approve TAUD-20260806-0440 catalog (54
  parallel-safe of 181) + configure observe_parallel" — message claims approval,
  file says `proposed`.

what_is_true: The correction stands; the original "no consumer reads it / lie
with no reader" framing is retracted and should be **deleted**, not left
alongside. One refinement to the correction itself: the field does not gate "the
whole command allowlist". `aid_test_audit_check_allowed`
(`aid-test-audit-command-allowlist.sh:134-159`) has TWO independent allow-paths
for `measure|full`: `_tacl_matches_gate_command` against `execution.yaml` (an
allow that does not consult the catalog at all), and then the catalog path.
Root `status != approved` therefore kills **every catalog-derived command** —
which for a test-portfolio audit is nearly all of them, since bats suites are
not registered gates — while gate-registered commands still run.

The IMP-494 half of this is already closed: the 15 profile-suite failures were
fixed by making the suite build its own approved fixture (option B). What
remains live and unfixed is the workspace state itself — the tracked catalog
says `proposed`, so a real `--mode measure|full` audit against it still refuses
every catalog command, and `aid-test-catalog-approve.sh` will not simply
re-approve it because `source_pattern_mappings[]` has genuinely drifted since
P076/P078/P079.

impact: Any live test-audit `measure`/`full` run silently degrades to
"gate-registered commands only" and reports a portfolio it never measured. The
schema description already states the intended meaning, so the field is not
ambiguous — the workspace file is simply stale.

fix_sketch: Do NOT drop the field (option (b) in the entry is now wrong).
Confirm the drifted mapping via `aid-test-catalog-confirm-mapping.sh`, re-run
`aid-test-catalog-approve.sh` so the root flips to `approved` through its
sanctioned writer, and add one bats case asserting a `proposed` root catalog
makes `aid_test_audit_check_allowed measure` refuse with its named reason (the
behaviour is currently unpinned).
effort: S for the pinning test; the mapping confirmation is a PM decision, not
engineering time.

Rewritten entry content (drop the old Summary, keep only this):
> `.aid-o/config/test-catalog.yaml`'s document-root `status` is load-bearing:
> `lib/aid-test-audit-command-allowlist.sh:117-119` refuses every
> catalog-derived command unless it is `approved` (gate-registered commands
> still pass via the independent `_tacl_matches_gate_command` path). Its live
> value is `proposed` from commit `5f24304`, whose message claimed the opposite,
> so a real `measure`/`full` audit measures only registered gates. Re-approval
> is blocked on drifted `source_pattern_mappings[]`. Fix = confirm the mapping,
> re-approve through `aid-test-catalog-approve.sh`, never by hand; plus one bats
> case pinning the refusal.

---

## IMP-493 — gate runtime baseline still accepts parallel concurrency contexts

verdict: REAL

evidence:
- `plugins/aid-orchestrator/scripts/lib/aid-gate-runtime-baseline.sh:319` —
  `concurrency_context="${7:-sequential}"`; `:329-333` — the acceptor
  `case … sequential|observe_parallel|parallel) ;;` with a warn+skip default.
- Branch sites confirmed at `:401` (`if [[ "$concurrency_context" == "sequential" ]]`),
  `:507-527` (the non-sequential path + the fingerprint-reset refusal at `:527`),
  `:535`, `:561`, `:591` (`percentiles_by_context` / `recent_samples_by_context`
  assembly). `:853` and the usage string at `:874` also carry the vocabulary.
- Producers — the entry names one, there are **two**, both hardcoded:
  `aid-run-gates.sh:2024` `local gate_concurrency_context="sequential"` (passed
  at `:2101`), and `aid-fsm.sh:3762-3769` `_resume_concurrency_context()` whose
  entire body is `printf 'sequential'`.
- `defaults/schemas/execution-unit-receipt.schema.json:52-58` — the receipt
  field is already narrowed to `enum: ["sequential"]`.

what_is_true: Confirmed dead vocabulary, with the producer list corrected to two
(both hardcoding `sequential`, and `aid-fsm.sh:3764-3766` says so explicitly:
"P078 removed the scheduler, so every gate … executes sequentially"). The
entry's stated migration risk is measurably smaller than it assumes here: the
live baseline `.aid-o/metrics/gate-runtime-baselines.yaml` has
`recent_samples_by_context: {}` and `percentiles_by_context: {}` on every entry
(checked lines 226-227, 350-351, 384-385) — there are no non-sequential samples
in the live history at all. The reader-narrowing risk is therefore about
*other* projects' baseline files, not this one.

impact: None operationally — nothing produces a non-sequential value. The cost
is comprehension: ~90 lines of by-context grouping and fingerprint-reset logic
in a hot library that reads as if a scheduler still existed, plus a stale
`--help` string. It is exactly the residue that makes the next reader believe
parallelism is still a live mode.

fix_sketch: Narrow the `:329-333` acceptor to `sequential`, delete the
non-sequential branches at `:401`/`:507-591` and the `*_by_context` assembly,
keep the two map fields present-but-empty for read compatibility with old files,
and add one bats case that a legacy baseline containing `observe_parallel`
samples still reads without error.
effort: S (the branches are contiguous and the live data has nothing to migrate;
budget the hour for the read-compat test, not the deletion).

---

## IMP-495 — the PM-facing decision card must be produced, not requested

verdict: REAL

evidence:
- Nothing on main renders a PM decision card. `grep -rln "decision.card\|decision_card"
  plugins/aid-orchestrator/` → no hits. None of the P080-specified renderers exist:
  `scripts/lib/aid-artifact-render.sh`, `scripts/lib/aid-gate-outcome-summary.sh`,
  `scripts/lib/aid-plan-close-summary.sh`, `skills/communication.md` — all absent.
- The single precedent the P080 plan names is real and shipped:
  `plugins/aid-orchestrator/scripts/lib/aid-test-audit-chat-summary.sh` (26 KB,
  deterministic, controller-presents-verbatim).
- `grep -rn "final_turn" plugins/aid-orchestrator/` → no hits. The output-contract
  field the enforcement would hang on does not exist yet.
- P080 is written but NOT implemented; it already specifies most of this entry:
  `.aid-o/plans/P080-entrypoint-ux-help-handoffs.md:33` (communication.md with
  §14 D17 four cards verbatim + a mechanical wiring test), `:35` and `:60-62`
  (two deterministic renderers, the 7-block artifact skeleton with hard caps —
  5 findings / 3 next steps / ~220 chars per sentence / explicit overflow count),
  `:546` (assert every `final_turn: renderer:*` names an existing script and
  every public row has a non-empty `final_turn`).

what_is_true: The gap is real on main — a "decision required" turn today is
whatever prose the model writes, with no renderer and no refusal. But the
entry's Proposed change items (1) and (3) are **already P080 EPIC 3 scope**, in
more detail than the entry states (P080 already carries the caps, the artifact
skeleton, the verbatim-presentation tests and the malicious-fixture redaction
acceptance criterion at `:611`). The genuinely distinct residue of IMP-495 is
item (2): *a "decision required" turn without an options list is refused* — an
enforcement, and P080 has no such refusal; its `final_turn` test only asserts
that a renderer is NAMED, not that a card was PRODUCED with options filled in.
The entry's own closing sentence ("Land after P080 ships the card contract; this
entry is the enforcement half") is therefore the correct reading and should be
promoted into the Summary so nobody builds the renderers twice.

impact: The PM receives technical findings lists he cannot act on at first
reading — the observed failure that produced this entry. Until enforcement
exists, compliance is per-turn model discipline, which by the standard's own
argument fails precisely on the long, high-stakes report.

fix_sketch: After P080 lands, make the options list a required field of the
"Decision required" renderer input (fail closed if empty, same shape as the
release-entry placeholder refusal at `aid-release.sh:_release_validate_updated_changelogs`)
and add the `final_turn` contract row asserting the card was produced, not just
that a renderer is named.
effort: S **as scoped to the enforcement half only, and only after P080 ships**.
Standalone (renderers included) it is L and duplicates P080 EPIC 3 — do not
schedule it that way.

---

## IMP-496 — a closed plan is never archived, while its EPIC task files are

verdict: REAL (the defect is real; the entry's mechanism for the task-file half is wrong)

evidence:
- `grep -rn "plans/archive" plugins/aid-orchestrator/scripts/` returns exactly
  ONE hit: `scripts/lib/aid-lifecycle.sh:1385`, a READ —
  `ls "${root}/.aid-o/plans/${plan_id}"-*.md "${root}/.aid-o/plans/archive/${plan_id}"-*.md`.
  No `mv` into `plans/archive/` exists anywhere in the plugin.
- `aid-plan-close-check.sh` contains no occurrence of "archive" at all.
- **The task-file claim is wrong.** `aid-fsm.sh:6894-6907` is a *precondition*,
  not an action: it `find`s the task file and, if present, emits
  `PRECONDITION FAIL: EPIC task file still in tasks/ (not archived)` plus
  `Move to tasks/archive/ before advancing: mv $task_file …/archive/`, and
  increments `errors`. Nothing in `aid-fsm.sh` executes that `mv` — grep for
  `mv .*archive` in that file returns only these two comment/echo lines.
- Live state: `.aid-o/plans/*.md` = 38 files (entry says 35), spanning
  P031…P069 plus the three current ones; `.aid-o/plans/archive/` holds 55 files,
  so archiving has been happening — by hand.
- The natural hook exists: `aid_lifecycle_plan_close` in
  `scripts/lib/aid-lifecycle.sh:780-875` already resolves the plan, writes and
  commits the closure receipt, and returns named states
  (`not_found` `:826`, `active` `:828`).

what_is_true: The end-state asymmetry the entry describes is real, but the cause
is not "tasks are automated and plans are not" — **neither is automated**. Task
files are archived because a blocking FSM precondition refuses to advance until
a human or controller does the `mv`; plan files are archived because someone
remembers. The correct framing: the task file has an *enforcement*, the plan
file has *nothing* — no mover and no checker. `aid-lifecycle.sh:1385` reading
both locations confirms `plans/archive/` is a supported, first-class location,
so the fix adds no new concept.

impact: `.aid-o/plans/` accumulates shipped plans (38 live, 55 already archived
by hand) and stops answering "what is being worked on". Directly caused the PM
review that raised this entry. Second-order: `aid-lifecycle.sh:1385` globs both
directories, so a stale live copy and an archived copy of the same plan id would
both match and `head -1` picks by `ls` order — the backfill should therefore
move, never copy.

fix_sketch: In `aid_lifecycle_plan_close` (`aid-lifecycle.sh:~838`, after the
receipt is committed and reachable), `git mv` the resolved plan file into
`.aid-o/plans/archive/` and prepend the closure annotation (version, date,
merge SHA) — idempotent no-op when already under `archive/`; ship the one-shot
backfill sweep for the 38 live files in the same change.
effort: S for the close-time move plus its bats case (the receipt path already
resolves the plan file, so it is one `git mv` and an idempotence guard); the
backfill is a separate half-hour of mechanical work with a PM eyeball on which
of the 38 are genuinely closed.

---

## Method notes

- Every claim above was checked by opening the cited file at the cited lines on
  `main` @ `3da7331`; entry paraphrases were not accepted anywhere.
- The only execution performed was `aid-release.sh prepare-plan P999` inside
  `git clone --local … /scratchpad/rel2` on a throwaway branch `plan/PTEST`.
  The real repository was not run against and not modified.
- Line-number corrections found against the entries as written: IMP-471 cites
  `skills/run-management.md:24` (actual `:23`); IMP-493 names one baseline
  producer (actual two); IMP-496 cites 35 plan files (actual 38) and attributes
  an automatic `mv` to `aid-fsm.sh` (actual: a blocking precondition, no `mv`).
