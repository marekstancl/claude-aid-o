> Archivováno 2026-10-09: nahrazeno P109 a P111 — běh z plánu bez EPICů je vydání 3 roadmapy (P111). Náhrada: docs/plans/2026-10-09-roadmapa-p109.md

---
id: P104
type: regular
status: draft
created: 2026-09-27
author: PM + AI
risk: high
lifecycle_strict: true
---

# Plan: milestones beside EPICs — a new plan runs from the plan file, milestone by milestone, on the plan branch

## Context

Analysis of 27. 9. 2026 (`docs/plans/EPIC-analysis-2026-09-27.md`, brainstorming record `.aid-o/work/interim-P104.md`): about half of the friction the four AID projects recorded in `.aid-o/work/aid-plugin-issues.md` comes from splitting a plan into formal EPICs — ~33 entries from generation (four stages `aid-plan-to-epic.sh` → `aid-epic-to-json.sh` → `aid-json-to-run.sh` → `aid-queue-add.sh`, driven by `aid-auto-pipeline.sh`) and ~77 from the per-EPIC lifecycle (queue, `task/E-*/main` branches, `epic-merge-to-plan`, done-advance, manifest deliveries). 65 of 171 plans had a single EPIC. The one measured benefit of EPICs is a small review unit (CP3 prompts 161–1 860 lines).

PM decisions (27. 9.): milestones instead of EPICs; reuse the existing, tested EPIC-level controls, enforcement and evidence — invent nothing; build outside AID; a milestone does not stop for the PM unless something fails; the converter reads both `**EPIC N:` and `**Milník N:` markers. Design A (judge Codex gpt-6-sol): a milestone is its own run, with the branch bound to the run state and an atomic handoff through the manifest.

CP1 round 1 of this plan (15 blockers, 26 majors) showed that adding the milestone path and deleting generation in one plan makes each half block the other. PM decision 1A after round 1: **this plan only ADDS milestones beside generation**; a second plan P105 removes generation, the queue and task branches once a real plan has run on milestones. Findings about removal are carried to `docs/plans/P105-input.md`.

## Goal

A new plan goes from its file to `main` without generation, a queue or task branches: `/aid-run <plan>` starts milestone 1 as a run on the plan branch, each finished milestone starts the next one, and the plan end is unchanged; plans generated before this release keep running on the old path.

## Scope

In scope:
- One converter from the plan file to one milestone's `plan.json`, built on the shared plan reader (`lib/aid-source-plan-graph.sh`, `lib/aid-scoping.sh`) and the `plan.json` builder moved out of `aid-epic-to-json.sh` into a library both use.
- A milestone start that performs every duty generation performs today: `plan-start`, readiness check, CP1 gate and its sealed authority (verified at every milestone), lifecycle scaffold, D5 contract check, `epic_input.md`, manifest entry — then `init` on the plan branch.
- The branch rule bound to the run state; the pre-commit hook selecting the one unfinished run of a branch.
- The milestone handoff `milestone-next` under one lock, tip-bound, resumable.
- `/aid-run`, `/aid-plan`, `/aid-status`, help and `skills/pipeline.md` for the milestone path; registry rows for the new controls.
- A testbed scenario of a two-milestone plan; the baseline for the proof of benefit; the P105 input.

Out of scope (P105 or later):
- Removing generation, the queue, `aid-plan-continue.sh`, task branches, `epic-merge-to-plan`, their tests and registry rows.
- Refusing plans generated before milestones, closing delivered unclosed plans, rewriting the Docusaurus `/aid/` pages about generation.
- One run per plan (design B); renaming internal identifiers (`epic_id`, `E-NNN-k_m`, plan state names); new checks or enforcement mechanisms; a PM stop at a milestone.

## Standards

| Standard | Why it binds | Deviation |
|---|---|---|
| `/ecosystem/specs/test-standard` | the new suite carries a measured tier; Steps 1-4, 7 | none |
| `/ecosystem/specs/ci-versioning-standard` | Step 8 releases the next minor, both CHANGELOGs, the version registry | none |
| `/ecosystem/specs/documentation-placement` | agent text in `commands/` and `skills/`, records in `docs/plans/` with `git add -f`; Steps 5-8 | none |
| `/ecosystem/specs/agent-hooks` | Step 3 changes how the pre-commit hook selects the governing run | none |
| `/ecosystem/specs/backlog-standard` | Step 8 files the measurement follow-up as an `IMP-` row | none |
| `/ecosystem/specs/claude-md-standard` | no `CLAUDE.md` change | none |

## Resources Verification

Checked on 2026-09-27 at `main` e52b6a1b:

- [x] Shared plan reader `aid_source_plan_graph` in `plugins/aid-orchestrator/scripts/lib/aid-source-plan-graph.sh` (header: consumers must not add a second parser) and `_aid_plan_step_bounds` / `_aid_plan_step_field` in `plugins/aid-orchestrator/scripts/lib/aid-scoping.sh:284`, `:329`.
- [x] `plan.json` builder in `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` (962 lines); schema `plugins/aid-orchestrator/defaults/templates/plan.schema.json` (top-level `additionalProperties: false`, plan link `source_plan`).
- [x] Duties of generation in `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh`: lifecycle mode and scaffold (~:1237-1290), `plan-start` (:1333), sealed authority `generation-authority.json` (`_gen_authority_path` :230, seal ~:1352-1440), D5 contract check through `plugins/aid-orchestrator/scripts/gates/aid-contract-validate.sh` (:1838).
- [x] Consumers of the seal: `plugins/aid-orchestrator/scripts/aid-release-policy.sh:727-764` (reads `epic_input.md` and `generation-authority.json`); `plugins/aid-orchestrator/scripts/aid-cp1-gate.sh:171-178` (plan hash binding).
- [x] Run FSM `plugins/aid-orchestrator/scripts/aid-fsm.sh`: `cmd_init` (:3359), plan-branch lineage (:3530-3610), task-branch auto-creation in the plan worktree (:3845-3860), `_fsm_epic_plan_nnn` (:179-185).
- [x] Plan FSM `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh`: `cmd_epic_start` (manifest entry `pending`/`running`), `cmd_epic_complete` (:3146, `done_phase: release`, tip bound), state-only merge half (:2932-2945), lock nesting note (:2766-2771), crash hook `AID_PLAN_FSM_CRASH_AFTER`; manifest statuses and transitions `plugins/aid-orchestrator/scripts/lib/aid-plan-manifest.sh:1073`, `:1181`; invariants `_pm_check_invariants`, `active_epics`.
- [x] Branch guard `plugins/aid-orchestrator/scripts/lib/aid-dispatch-contract.sh:416-420`; pre-commit run selection `plugins/aid-orchestrator/defaults/hooks/pre-commit:214-242` (first sorted EXECUTE|GATES|DONE match).
- [x] Hook suites `plugins/aid-orchestrator/scripts/tests/bats/test-commit-guard.bats`, `test-hooks-worktree.bats`; instruction sweep `plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh`; registry cites `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh`.
- [x] Testbed `/opt/eco/projects/aid-testbed/bin/verify.sh` (40 checks; `generation_refuses_without_page` drives `aid-plan-to-epic.sh`).

## Approach

Chosen: **add the milestone path beside generation.** A milestone is its own run — the same state file, evidence directory, `cp3/`, `gates/`, `done_phase` and manifest entry the controls read today — created from the plan file by `aid-milestone-start.sh`, which performs every duty generation performs, on the plan branch. `milestone-next` records a finished milestone and starts the next one in one locked transaction. New plans take this path; plans generated earlier finish on the old one; P105 removes the old one after a real plan has run on milestones.

Alternatives considered and rejected:
- *Add and remove in one plan*: CP1 round 1 — each half blocks the other (15 blockers); PM 1A.
- *One run per plan (B)*: new enforcement on surfaces that work today (judge verdict A).
- *Keep EPIC runs, drop only generation*: keeps the queue, task branches and merge-to-plan.

## Architecture

A new plan never passes through generation: the milestone start does generation's duties for one milestone at a time and creates a run the existing controls cannot tell from a generated EPIC run; the handoff replaces the queue and the merge into the plan branch.

```
plan file (**EPIC N:** or **Milník N:** markers)
   ▼
/aid-run Pxxx ─► aid-milestone-start.sh Pxxx 1   (wrapper: takes the plan lock, calls aid_milestone_start)
                 aid_milestone_start (lib/aid-milestone.sh), K=1 and every K:
                   plan-start (K=1, if not started)          ← moved from aid-auto-pipeline.sh
                   aid-generation-readiness.sh
                   aid-cp1-gate.sh + seal generation-authority.json (K=1) / verify it (K>1)  ← moved
                   lifecycle scaffold (lifecycle_strict)     ← moved
                   plan.json of milestone K (lib/aid-plan-json.sh over aid_source_plan_graph)
                   epic_input.md = milestone K slice (for aid-release-policy.sh)
                   D5: gates/aid-contract-validate.sh on plan.json
                   manifest epic_runs[K] = running           (cmd_epic_start's entry, no task branch)
                   aid-fsm.sh init  (branch plan/Pxxx, run id E-xxx-K_M, --milestone: no task branch)
   ▼
milestone run = today's EPIC run: steps → CP2 → CP3 → GATES → DONE → done-advance review→release
   ▼
aid-plan-fsm.sh milestone-next Pxxx   (ONE lock; calls aid_milestone_start inside it, never the wrapper)
   epic-complete checks of the running entry; tip must equal the bound completion SHA
   epic_runs[K] = merged_to_plan @ that SHA   (existing state-only merge half)
   K < M → aid_milestone_start K+1 ;  K = M → plan state → PLAN_SYNC → plan-finalize (unchanged)
   abandoned milestone → stop, PM decides (no automatic continue)
```

## Data Model

- `plan.json` of a milestone run: today's schema plus an optional top-level `milestone: {index, total}` (added to `plan.schema.json`); `source_plan` names the plan file.
- `fsm-state.yaml`: unchanged fields; `branch: plan/Pxxx`; `epic_id` holds the run id `E-xxx-K_M` (from `aid_gen_epic_id`); new optional `milestone: K`.
- Plan manifest `epic_runs[]`: one entry per milestone, existing statuses only (`pending` → `running` → `merged_to_plan` | `abandoned`); invariant from the existing `_pm_check_invariants`/`active_epics`: at most one `running` entry.
- `generation-authority.json`: the existing sealed CP1 decision, written at milestone 1 and verified at every milestone (plan bytes unchanged since the seal, or a fresh CP1 pass).

## Implementation Steps

**EPIC 1: Steps 1-4 — A milestone runs from the plan file on the plan branch**

### Step 1: The converter — plan file to one milestone's plan.json

**Objective:** `aid_plan_json_for_milestone <plan> <K>` writes the `plan.json` of milestone K from the plan file through the shared plan reader and the `plan.json` builder `aid-epic-to-json.sh` also uses.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-plan-json.sh` — the `plan.json` building code moved out of `aid-epic-to-json.sh` (steps array, gates, analysis groups, schema validation) as functions over a step list; `aid_plan_json_for_milestone` reads milestone K's steps with `aid_source_plan_graph`, `_aid_plan_step_bounds` and `_aid_plan_step_field`, accepting `**EPIC N:` and `**Milník N:` markers.
- Modify: `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` — sources `lib/aid-plan-json.sh` and keeps its EPIC-file readers only; behaviour for generated plans unchanged.
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` — optional top-level `milestone` object `{index: integer ≥ 1, total: integer ≥ 1}`.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-source-plan-graph.sh` — the marker regex accepts `**Milník N:`.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-lint.sh` — the marker regex accepts `**Milník N:`.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-plan-summary.sh` — the marker regex accepts `**Milník N:`.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-lifecycle.sh` (lines ~644-700) — `aid_lifecycle_parse_legacy_epics` reads both markers as required units.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-milestone-start.bats` (tier: t1) — three-milestone fixture: milestone 2's `plan.json` validates against the schema, holds exactly block 2's steps with Files, AC, role, parallel group and deps (cross-milestone deps stripped), `source_plan` set, `milestone: {index: 2, total: 3}`; `Milník` and `EPIC` marker versions of the same plan give identical steps; a broken marker range is refused naming the line.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-plan-lint.bats` — `**Milník 1: Steps 1-2 — x**` passes, `**Milnik 1**` is reported.
- Test: `plugins/aid-orchestrator/scripts/tests/test-epic-to-json.sh` — unchanged cases still pass after the move (regression of the generated path).

**Reuse check:** searched: `grep -rl -e aid_source_plan_graph -e steps_section= plugins/aid-orchestrator/scripts --include=*.sh` → several matching `plugins/aid-orchestrator/scripts/lib/aid-source-plan-graph.sh`, `plugins/aid-orchestrator/scripts/aid-epic-to-json.sh` — the step reads with the canonical reader and moves the builder out of `aid-epic-to-json.sh` into the library that script then sources, so one builder serves both paths.

**Parallel group:** ---

**Architecture Context:** The converter is the `plan.json` line of the Architecture; everything downstream of `plan.json` (FSM, CP2, CP3, gates) reads the same schema as today, which keeps it unchanged.

**Implementation Detail:** Move the builder verbatim (functions and their callers' variables become parameters); `aid-epic-to-json.sh` keeps parsing its EPIC file into the same step list and calls the moved builder. `aid_plan_json_for_milestone` finds marker K with the lint's regex, collects step numbers M..P, reads each step block with `_aid_plan_step_bounds`/`_aid_plan_step_field` (Objective, Files, AC, Effort, AID Role, Parallel group, Shared interfaces), dependencies from `aid_source_plan_graph` with steps outside M..P dropped, allowed paths through `_aid_allowed_paths_from_files_json` as `aid-epic-to-json.sh` does.

**Error Handling:** Marker K missing or its range not matching the `### Step` headers → exit 1 naming the marker line (the lint's message). `aid_source_plan_graph` error → exit 1 with `_aid_spg_error`. Schema validation failure → exit 1 with the validator's path list; no file left.

**Edge Cases:**
- A plan with one marker: one milestone, `total: 1`.
- A dependency on a step of an earlier milestone: dropped (it is already on the plan branch), as `strip_cross_phase_deps` does for EPICs.
- A `**EPIC N / Backlog:` marker: not a milestone, never converted.

**Dependencies:**
- Depends on: none
- Blocks: Step 2

**Acceptance Criteria:**
- [ ] `bats plugins/aid-orchestrator/scripts/tests/bats/test-milestone-start.bats plugins/aid-orchestrator/scripts/tests/bats/test-plan-lint.bats` passes.
- [ ] `bash plugins/aid-orchestrator/scripts/tests/test-epic-to-json.sh` passes (the generated path is unchanged).
- [ ] The `Milník` and `EPIC` versions of the fixture plan produce byte-identical `steps` arrays.

**Effort:** L

**AID Role:** backend

### Step 2: The milestone start — every duty of generation, then init on the plan branch

**Objective:** `aid-milestone-start.sh <plan_id> <K>` starts milestone K after the same checks and records generation makes today, with the manifest entry written before `init` and no task branch.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-milestone.sh` — `aid_milestone_start <plan_id> <K>` (runs inside a caller-held plan lock): `plan-start` for K=1 when the plan has no state; `aid-generation-readiness.sh`; CP1 gate and seal via the functions moved from `aid-auto-pipeline.sh`, verify the seal for K>1; lifecycle scaffold; `plan.json` (Step 1); `epic_input.md` (milestone slice); D5 `gates/aid-contract-validate.sh`; manifest entry through `cmd_epic_start`'s entry writer (no task branch); `aid-fsm.sh init --milestone`.
- Create: `plugins/aid-orchestrator/scripts/aid-milestone-start.sh` — wrapper: resolves the plan, takes the plan lock, calls `aid_milestone_start`, releases the lock.
- Modify: `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh` (lines ~1237-1440, ~1838) — the lifecycle scaffold, `plan-start` call, seal writer/verifier and D5 call moved into functions in `lib/aid-milestone.sh` that this script now sources and calls; behaviour for generated plans unchanged.
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` (lines ~3359-3610, ~3840-3862) — `init --milestone`: the run's branch is `plan/P<NNN>` of its run id, required to be checked out in the plan worktree; no `task/*` branch created; `milestone: K` recorded; the manifest entry must already be `running`.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — `cmd_epic_start`'s manifest-entry writer callable without creating a task branch (flag `--no-task-branch`).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-milestone-start.bats` (tier: t1) — milestone 1 of a fixture plan: plan state, plan worktree, lifecycle manifest, sealed authority, `epic_input.md`, manifest entry `running`, `fsm-state.yaml` with `branch: plan/P901`, no `task/*` branch; a plan whose CP1 did not pass is refused and nothing is left; milestone 2 after an edit of the plan without a fresh CP1 is refused ("plan changed since the review"); a D5-broken `plan.json` is refused before `init`; a second start of a milestone with a `running` entry is refused naming it; a kill after the manifest write and before `init` (`AID_PLAN_FSM_CRASH_AFTER`) is resumed by rerunning, with one run.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats` — `init --milestone` on `plan/P901` for run `E-901-1_2` succeeds; with branch `plan/P902` refused; without a `running` manifest entry refused.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-lifecycle-e2e.bats` — the generated path still scaffolds the lifecycle manifest (regression after the move).

**Reuse check:** searched: `grep -rl -e _gen_authority_path -e aid-contract-validate plugins/aid-orchestrator/scripts --include=*.sh` → several matching `plugins/aid-orchestrator/scripts/aid-auto-pipeline.sh`, `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh`, `plugins/aid-orchestrator/scripts/gates/aid-contract-validate.sh` — the step moves the generation duties from `aid-auto-pipeline.sh` into one library both paths call, so each duty keeps one implementation.

**Parallel group:** ---

**Architecture Context:** The milestone-start block of the Architecture; it is what makes a milestone run indistinguishable, to every control that reads a run, from a generated EPIC run.

**Implementation Detail:** Order inside the lock: plan-start (K=1) → readiness → CP1 gate/seal (K=1) or seal verify (K>1: plan bytes hash equals the sealed hash, else run the gate again and re-seal only if it passes) → lifecycle scaffold → `plan.json` → `epic_input.md` → D5 → manifest entry `pending`→`running` → `init --milestone`. Every write before `init` goes to a temp path and is renamed at the end; on failure the temp paths are removed and the manifest entry, if written, is set back to `pending` so a rerun proceeds. Run id from `aid_gen_epic_id <plan_num> <K> <M>` (existing), run-attempt id from `aid_gen_run_id` (existing).

**Error Handling:** Each duty keeps its own refusal message verbatim (the moved code); the wrapper prints which duty refused. A held lock → the lock helper's message naming the holder. A `running` entry for another milestone → refuse naming it.

**Edge Cases:**
- A plan already started by `plan-start` (manually or by an older path): plan-start skipped, everything else runs.
- A plan whose EPICs were generated before this release: `aid-milestone-start.sh` refuses ("this plan was generated — continue it with /aid-run on its EPICs"), detected by `transaction.json` with phases under `.aid-o/work/evidence/<plan_id>/generation/`; the sealed authority alone is not that signal.
- `lifecycle_strict: false` plan: scaffold as the generated path does for it.

**Dependencies:**
- Depends on: Step 1
- Blocks: Step 3, Step 4

**Acceptance Criteria:**
- [ ] `bats plugins/aid-orchestrator/scripts/tests/bats/test-milestone-start.bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-fsm.bats plugins/aid-orchestrator/scripts/tests/bats/test-lifecycle-e2e.bats` passes.
- [ ] `aid-release-policy.sh` run against milestone 1's evidence of the fixture finds the plan review (no "no sealed plan review" blocking reason).
- [ ] After the fixture's milestone 1 start, `git branch --list 'task/*'` in the fixture repository prints nothing.

**Effort:** L

**AID Role:** backend

### Step 3: The branch rule bound to the run, and the pre-commit hook

**Objective:** A milestone run's step commit lands only on the plan branch its run state records, and the pre-commit hook judges a commit against the one unfinished run of the branch.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-dispatch-contract.sh` (lines ~406-425) — the allowed branch is read from `branch:` of the run's `fsm-state.yaml`; accepted when the current branch equals it AND it is `task/<epic>/main` or `plan/P<NNN>` with `<NNN>` parsed from the run id inside this file (empty parse → refuse); everything else refused as today.
- Modify: `plugins/aid-orchestrator/defaults/hooks/pre-commit` (lines ~214-242) — the governing run of a branch is the single run on it in EXECUTE or GATES, or in DONE with `done_phase` other than `release`; none → the existing no-run path; two or more → refuse naming them.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-dispatch-contract.bats` — a milestone run's commit on its plan branch is committed; with the state naming another plan refused; on `main` refused; state file missing refused; unparseable run id refused.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-commit-guard.bats` — branch `plan/P901` with milestone 1 DONE at `release` and milestone 2 in EXECUTE: a commit in milestone 2's scope passes and one outside it is refused by milestone 2's scope, not milestone 1's; two unfinished runs on one branch are refused.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-hooks-worktree.bats` — the same selection from the plan worktree.

**Parallel group:** ---

**Architecture Context:** The branch rule of the Architecture, the judge's first condition: the ACTA 31. 8. guard now takes the allowed branch from the run's own state instead of a pattern, and the hook stops assuming one run per branch.

**Implementation Detail:** In `aid_dispatch_contract_commit` the contract path already yields `<epic>` and `<run>`; read `branch:` with `sed -n` from their `fsm-state.yaml`; parse `<NNN>` with `[[ $epic =~ ^E-([0-9]+)- ]]`. In `pre-commit`, collect candidate state files by the new rule, then decide by count.

**Error Handling:** Every refusal names the branch, the run and the checkout command; nothing is committed.

**Edge Cases:**
- A generated EPIC run on `task/<epic>/main` commits as today.
- A wave step on `step/<id>` keeps its exemption.
- A plan-fix commit at plan end (all milestones DONE at `release`): no governing run → the existing plan-final path decides, as today for a plan branch.

**Dependencies:**
- Depends on: Step 2
- Blocks: Step 4

**Acceptance Criteria:**
- [ ] `bats plugins/aid-orchestrator/scripts/tests/bats/test-dispatch-contract.bats plugins/aid-orchestrator/scripts/tests/bats/test-commit-guard.bats plugins/aid-orchestrator/scripts/tests/bats/test-hooks-worktree.bats` passes.
- [ ] A step commit for run `E-901-1_2` with `branch: plan/P901` while `plan/P902` is checked out is refused and `git log` is unchanged.
- [ ] The commit-guard case with two milestone runs on one branch applies milestone 2's scope.

**Effort:** M

**AID Role:** backend

### Step 4: The milestone handoff

**Objective:** `aid-plan-fsm.sh milestone-next <plan_id>` records the finished milestone at its bound completion commit and starts the next one under one lock, resumably, and after the last milestone moves the plan to PLAN_SYNC.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` — subcommand `milestone-next` (dispatch table ~:10621): under the plan lock, the single `running` entry; `cmd_epic_complete`'s precondition block (DONE, `done_phase: release`) and its tip binding (the current `plan/<id>` tip must equal the SHA bound at completion); the state-only merge half (:2932-2945) with that SHA; then `aid_milestone_start <plan_id> <K+1>` called in-process (no second lock) or plan state `EPIC_INTEGRATION → PLAN_SYNC`; the first milestone start moves `OPEN → EPIC_INTEGRATION`; an `abandoned` entry stops with a message for the PM.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` — two-milestone fixture: `milestone-next` after milestone 1 marks it `merged_to_plan` at its bound SHA and creates milestone 2's run; after milestone 2 the plan is PLAN_SYNC and `plan-finalize --stage produce` finds two contributors; refused at `done_phase: review`; refused when a commit landed after completion (tip ≠ bound SHA); `AID_PLAN_FSM_CRASH_AFTER` after the merge-half write → rerun completes with one run of milestone 2; an abandoned milestone stops and starts nothing; `milestone-next` does not time out on its own lock.

**Parallel group:** ---

**Architecture Context:** The handoff of the Architecture, the judge's second condition: atomic and resumable through the existing manifest, with the same tip binding `epic-merge-to-plan` enforces today.

**Implementation Detail:** Idempotent by state: no `running` entry and a missing next run → only the start; `running` entry DONE at `release` → full handoff. The lock is taken once in `cmd_milestone_next`; `aid_milestone_start` assumes it is held (checked by the lock helper's owner test).

**Error Handling:** Preconditions fail → `cmd_epic_complete`'s own message, nothing written. Tip mismatch → refuse naming both SHAs and "review the commits after completion". Start of K+1 fails → K stays `merged_to_plan`, exit non-zero naming the rerun.

**Edge Cases:**
- Single-milestone plan: straight to PLAN_SYNC.
- An abandoned milestone whose partial commits are on the plan branch: `milestone-next` stops; the PM chooses to revert them or keep them (CP7 and the plan gates review the whole plan diff either way).
- Two sessions calling `milestone-next`: the second waits for the lock and finds nothing to do.

**Dependencies:**
- Depends on: Step 2, Step 3
- Blocks: Step 5, Step 7

**Acceptance Criteria:**
- [ ] `bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats` passes.
- [ ] After the crash case and a rerun, the fixture holds exactly one run of milestone 2.
- [ ] After the two-milestone fixture reaches PLAN_SYNC, `aid-plan-fsm.sh plan-finalize P901 --stage produce` succeeds.

**Effort:** L

**AID Role:** backend

**EPIC 2: Steps 5-8 — Instructions, status, testbed, release**

### Step 5: /aid-run and /aid-plan run a new plan on milestones

**Objective:** The controller starts a new plan with `aid-milestone-start.sh`, continues with `milestone-next`, and `/aid-plan` ends with a plan ready to run; generated plans keep their instructions.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — PRE-FLIGHT: a plan without generated EPICs runs `aid-milestone-start.sh <plan> 1`; the `--auto` loop continues with `milestone-next` after `done-advance review release`; a milestone stops only on failed gates, an open blocker or an abandoned milestone; the generation pipeline section is headed "plans generated before 2.110.0".
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` — after the PM page the next step is `/aid-run <plan>`; "Mode: Generate EPIC" headed "plans generated before 2.110.0 only".
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` — "Phase Markers" describes milestones and both marker words.
- Test: `plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh` — `commands/aid-run.md` names `aid-milestone-start.sh` and `milestone-next`; `commands/aid-plan.md` offers `/aid-run <plan>` after the PM page.

**Parallel group:** ---

**Architecture Context:** The commands are the controller's interface to Steps 2-4; without them no plan takes the milestone path.

**Implementation Detail:** Add the milestone path as the default flow text; move the generation text under its "generated before 2.110.0" heading without deleting it (P105 deletes it).

**Error Handling:** Not applicable to text; the instruction sweep is the guard.

**Edge Cases:**
- `/aid-run <E-id>` of a generated plan: the old flow, unchanged.
- `/aid-run --auto` interrupted between milestones: rerun `milestone-next`.
- A new plan the PM wants generated anyway: not offered; the milestone path is the only one for new plans.

**Dependencies:**
- Depends on: Step 4
- Blocks: Step 6

**Acceptance Criteria:**
- [ ] `bash plugins/aid-orchestrator/scripts/tests/test-instruction-sweep.sh` passes.
- [ ] `grep -c "aid-milestone-start.sh" plugins/aid-orchestrator/commands/aid-run.md` is at least 1 and `grep -c "milestone-next" plugins/aid-orchestrator/commands/aid-run.md` is at least 1.
- [ ] `grep -c "generated before 2.110.0" plugins/aid-orchestrator/commands/aid-plan.md` is at least 1.

**Effort:** M

**AID Role:** docs-writer

### Step 6: Status, help, pipeline skill and registry for milestones

**Objective:** The PM sees "milník k z m" for a milestone plan, the pipeline skill describes the milestone flow and its refusals, and the registry records the new controls.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` — recipe `plan-epics` labels runs with a `milestone` field as "milník k z m".
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — the flow of a new plan with milestones.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — a "Milestones" section; "When AID refuses" rows for `aid-milestone-start.sh` (each moved duty's refusal), `milestone-next` (tip mismatch, abandoned milestone) and the branch rule.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — rows `milestone_start_duties`, `milestone_handoff_tip_bound`, `step_commit_branch_from_run_state`, `precommit_single_unfinished_run` with status `active`, sources and tests.
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh` — the four rows cite existing sources and tests.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats` — a milestone plan renders "milník 2 ze 3".

**Parallel group:** ---

**Architecture Context:** The surfaces the vision's V1 test reads; the registry is where every new control is declared (CONTRIBUTING).

**Implementation Detail:** Reuse the `plan-epics` recipe; no new status recipe.

**Error Handling:** Not applicable to text; the registry cites suite guards the rows.

**Edge Cases:**
- A project with a generated plan and a milestone plan at once: both render, the generated one with EPIC wording.
- A milestone run without a manifest (should not exist): rendered as a run with a warning.
- Help-index entry for `aid-milestone-start.sh`: added.

**Dependencies:**
- Depends on: Step 5
- Blocks: Step 8

**Acceptance Criteria:**
- [ ] `bash plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh` passes.
- [ ] `bats plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats` passes.
- [ ] `grep -c "milestone-next" plugins/aid-orchestrator/skills/pipeline.md` is at least 1.

**Effort:** M

**AID Role:** docs-writer

### Step 7: Testbed scenario, baseline and the P105 input

**Objective:** The testbed proves a two-milestone plan on a foreign project; the baseline for the proof of benefit and the input for P105 are recorded.

**Files:**
- Modify: `/opt/eco/projects/aid-testbed/bin/verify.sh` — checks `milestone_plan_runs` (two `**Milník N:` blocks: start, recorded CP2/CP3 answers, gates, done-advance, `milestone-next`, milestone 2, PLAN_SYNC), `milestone_failed_gate_stops`, `milestone_handoff_resumes` (crash hook), `milestone_start_refuses_unreviewed` (the CP1 refusal on the milestone path, beside the kept `generation_refuses_without_page`); gated on the presence of `scripts/aid-milestone-start.sh`.
- Create: `docs/plans/P104-baseline.md` — friction classes G/L of 27. 9., CP3 prompt sizes of P101/P102, plan-to-main times and reviewer runs of P101/P102, plugin script and test line counts, each with its source (committed with `git add -f`).
- Create: `docs/plans/P105-input.md` — the removal findings of P104 CP1 round 1 (callers of `aid-generation-ids.sh`, `queue_revalidate`, `_pfsm_maybe_continue`, review-summary queue events, ~53 test files, 82 registry lines and the missing `retired` status, t2 suites, grep AC scope), the refusal of generated plans, closing delivered unclosed plans (17 records), the Docusaurus pages (committed with `git add -f`).

**Reuse check:** searched: `find docs/plans -name P104-baseline.md -o -name P105-input.md` → none

**Parallel group:** ---

**Architecture Context:** The testbed is the one run of a release; the baseline is the IMP-672 proof the vision's tests compare against; P105 is the second half of PM decision 1A.

**Implementation Detail:** Follow the existing step-review checks of `verify.sh` (clone, recorded answers, no API); a fixture plan under the testbed's `.aid-o/plans/`.

**Error Handling:** The checks print "skipped" against a plugin without `aid-milestone-start.sh`.

**Edge Cases:**
- The plugin given with `--plugin <dir>` (testbed before the push).
- The testbed's own layout without a plan branch: the check lets milestone 1 run `plan-start`.
- A crash simulated between manifest write and next start.

**Dependencies:**
- Depends on: Step 4
- Blocks: Step 8

**Acceptance Criteria:**
- [ ] `/opt/eco/projects/aid-testbed/bin/verify.sh --plugin /opt/eco/projects/aid-orchestrator/plugins/aid-orchestrator` passes with the four new checks.
- [ ] `docs/plans/P104-baseline.md` holds each number with its source.
- [ ] `docs/plans/P105-input.md` lists every removal finding of CP1 round 1 with its evidence.

**Effort:** M

**AID Role:** qa

### Step 8: Release 2.110.0

**Objective:** 2.110.0 is released with the milestone path, on the PM's word, with the measurement follow-up filed.

**Files:**
- Modify: `CHANGELOG.md` — `## [2.110.0]` entry: milestones for new plans, generated plans unchanged, P105 next.
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — copy of the entry.
- Modify: `.claude-plugin/marketplace.json` — version 2.110.0 (both fields).
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — version 2.110.0.
- Modify: `plugins/aid-orchestrator/README.md` — `**Plugin:** 2.110.0`.
- Modify: `README.md` — Changelog line for 2.110.0.
- Modify: `.aid-o/work/backlog.md` — `IMP-` row: measure V2-V4 on the first milestone plans against `docs/plans/P104-baseline.md`, then start P105.

**Parallel group:** ---

**Architecture Context:** The release workflow of CONTRIBUTING: testbed before the push (the marketplace auto-updates every project); additive release, so running generated plans (agents P009) are unaffected.

**Implementation Detail:** T0+T1 and the direct suites of Steps 1-7, then the testbed against the working tree, then commit, tag, push, plugin update, tag push, GitHub release.

**Error Handling:** A red testbed or suite → fix, re-run, only then push.

**Edge Cases:**
- A project mid-plan on generation: unaffected by construction.
- A PM who wants P105 first: out of scope; P105 starts after data.
- Version registry mismatch: `verify-version-files.sh` names the location.

**Dependencies:**
- Depends on: Step 6, Step 7
- Blocks: none

**Acceptance Criteria:**
- [ ] `bash plugins/aid-orchestrator/scripts/tests/verify-version-files.sh 2.110.0 --baseline 2.109.0` prints `OVERALL: PASS`.
- [ ] `bash plugins/aid-orchestrator/scripts/tests/run-all-tests.sh --tier t1` passes.
- [ ] `.aid-o/work/backlog.md` holds the measurement row naming `docs/plans/P104-baseline.md`.

**Effort:** M

**AID Role:** release

## Testing Strategy

Which behaviour: (1) the converter produces a milestone's `plan.json` from either marker word through the shared reader; (2) the milestone start performs every generation duty (plan-start, readiness, CP1 seal and its verification per milestone, lifecycle scaffold, D5, manifest before init) and leaves nothing on refusal; (3) a step commit lands only on the branch its run declares, and the pre-commit hook governs by the one unfinished run; (4) the handoff records a milestone at its bound SHA and starts the next exactly once, including after a crash, without deadlocking; (5) the generated path is unchanged. Why: these are the decisions this plan adds; everything downstream of `plan.json` keeps its suites. Where: one new suite `test-milestone-start.bats` (t1: builds fixture repositories, under 30 s per case); cases in `test-plan-lint.bats`, `test-aid-fsm.bats`, `test-dispatch-contract.bats`, `test-commit-guard.bats`, `test-hooks-worktree.bats`, `test-aid-plan-release-boundary.bats`, `test-status-two-streams.bats`, `test-instruction-sweep.sh`, `test-enforcement-registry-cites.sh`; regression of the generated path in `test-epic-to-json.sh` and `test-lifecycle-e2e.bats`; the end-to-end behaviour in the testbed (Step 7).

## Constraints

- Reuse the existing, tested controls, enforcement and evidence; each generation duty keeps one implementation, moved into a library both paths call.
- The generated path stays working and unchanged until P105.
- Internal identifiers stay (`epic_id`, `E-NNN-k_m`, plan state names).
- Built outside AID in a worktree; T0+T1 and the direct suites before the release; testbed once, before the push; merge, tag, push and plugin refresh on the PM's explicit word.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A duty of generation is missed and a milestone run is blocked at release or plan end | medium | high | Step 2 lists every duty from `aid-auto-pipeline.sh`; the testbed runs a whole plan to PLAN_SYNC; `aid-release-policy.sh` checked on milestone evidence |
| Moving code out of `aid-auto-pipeline.sh` changes the generated path | medium | high | regression suites `test-epic-to-json.sh`, `test-lifecycle-e2e.bats`; agents P009 not touched (additive) |
| The branch rule weakens the ACTA 31. 8. guard | low | high | branch from the run state, bound to the run's plan; refusal cases tested |
| Follow-up fixes after the release | high | medium | the first milestone plan is the measured one; fixes as patch releases |

## Acceptance Criteria

- [ ] AC1: The milestone suites pass.
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-milestone-start.bats plugins/aid-orchestrator/scripts/tests/bats/test-dispatch-contract.bats plugins/aid-orchestrator/scripts/tests/bats/test-commit-guard.bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-release-boundary.bats"
    expected_exit: 0
  ```
- [ ] AC2: The run start of a new plan is the milestone start.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "plugins/aid-orchestrator/commands/aid-run.md"
    regex: "aid-milestone-start\\.sh"
  ```
- [ ] AC3: The handoff exists.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "plugins/aid-orchestrator/scripts/aid-plan-fsm.sh"
    regex: "milestone-next"
  ```
- [ ] AC4: The testbed runs a two-milestone plan.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "/opt/eco/projects/aid-testbed/bin/verify.sh"
    regex: "milestone_plan_runs"
  ```
- [ ] AC5: The baseline for the proof of benefit is recorded.
  ```yaml
  verification_pattern:
    type: must_contain
    file: "docs/plans/P104-baseline.md"
    regex: "P101|P102"
  ```

## Success Criteria

- [ ] V1 (this plan's half): `/aid-run <plan>` of a new plan starts from the plan file; no EPIC file, `run.md`, queue entry or `task/*` branch is made for it; the PM reads milestones (Steps 1-6). Full V1 after P105.
- [ ] V2: measured after P105 against the baseline (backlog row, Step 8).
- [ ] V3: the first milestone plan has no milestone review prompt longer than 1 860 lines.
- [ ] V4: the first two milestone plans are not slower from start to `main` than P101/P102 at a comparable step count and use no more reviewer runs.
- [ ] V5: the milestone flow is documented in commands, `skills/pipeline.md` and help; T0+T1 and the testbed are green (Steps 5-8).

## Next Steps

- Run the first new plan on milestones and measure V3/V4 against `docs/plans/P104-baseline.md`.
- P105: remove generation, the queue and task branches from `docs/plans/P105-input.md`.
