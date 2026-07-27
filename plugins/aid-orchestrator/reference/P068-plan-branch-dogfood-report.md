# P068 plan-branch dogfood report

**Status: EXECUTED 2026-07-27 and HALTED at the boundary, by the boundary.** The
plan ran the whole path and stopped at `AWAITING_PM` with C4 reporting
`release_ready=false` and four blockers. Nothing was merged to `main`.

*Updated 2026-07-27 with the PM decision on the bootstrap question and the
authorized execution order.*

## Authorization

The live dogfood run **has not been performed**, and this section says so first
because a report that buried it would be worse than no report at all.

The dogfood, as specified, advances the real `main` branch of this repository: it
runs a small follow-up plan (P067) end to end through `plan_branch` mode and
merges it to the target branch. That is an irreversible, outward-facing act on
the repository's mainline, and it is exactly the class of action this controller
does not take on its own initiative. The standing instruction for this run has
been that `main` stays untouched and nothing is pushed; every commit of P068 to
date has honoured that, and `main` has not moved from `0158a68`.

**What the PM is being asked to authorize**, explicitly, before execution:

1. Creating the P067 dogfood subject plan (the number is already reserved in
   `.aid-o/config/counter.yaml`).
2. Running it end to end in `plan_branch` mode.
3. **Merging it to `main`** — the first time the plan-final boundary moves the
   real target branch.
4. Re-synchronising `plan/P068` onto the advanced `main` afterwards.

Nothing in this report should be read as a claim that the end-to-end path has
been exercised on real branches. What HAS been proven is stated under
"Evidence that exists today", and what has not is stated under "What only the
live run can prove".

## PM decision of 2026-07-27, and what it changes

The PM ruled on the bootstrap question this report raised:

- **P068 is declared `legacy_epic_release_mode`, never `plan_branch`.** It did
  not run through the new path — `plan/P068` never received either EPIC, and no
  plan-state for P068 exists — so stamping it plan_branch would be a false record
  of how it ran. P068 built the new line; it was itself built on the old one.
  That is a bootstrap situation, not a failure. Claiming otherwise would be.
- **No standalone manifest commit to `main` now.** `aid_lifecycle_ensure_manifest`
  makes an isolated commit onto the target branch, so it would move `main`
  without verifying or unblocking anything: P068 would still not be a plan-branch
  run, and the dogfood would still not have happened.
- **P067 is the first real `plan_branch` run**, and the proof the new path works.
- **P068 closes afterwards as a one-time bootstrap legacy release**, with its
  close evidence stating explicitly that P068 DELIVERED the mechanism and P067
  LIVE-VERIFIED it.
- **2.63.0 tags and releases only after that.**

## Execution order, as authorized

1. ~~Targeted CP2/CP3 over the C4 producer wiring~~ — **done** 2026-07-27,
   recorded in `.aid-o/work/evidence/E-068-2_2/R-E068-2/plan-final/c4-producer-review.md`.
   One defect found and fixed (the producer could silently invalidate a
   completed review); targeted plan-final set 44/44.
2. **P067 live dogfood** — prepared below. **Requires explicit PM authorization
   to merge to `main`; not started.**
3. P068 bootstrap legacy close: legacy merge to `main`, then the durable
   lifecycle manifest with `mode: legacy_epic_release_mode`, then the close
   record.
4. Tag and release 2.63.0.

## Preparation completed

### Git hooks reinstalled

`defaults/hooks/*` are templates; `/aid-init` copies them into `.git/hooks/`, and
the copies are NOT updated when the templates change. A stale `pre-push` would
have blocked the dogfood's first push on the very guard P068 Step 5 fixed — and,
worse, a stale hook that happened to pass could be mistaken for the exemption
working.

| Hook | Before | After | Template |
|------|--------|-------|----------|
| `pre-push` | `cd98d5f62e3fa810` | `a9228495b1cc8190` | `a9228495b1cc8190` |
| `pre-commit` | `effc7def5762e32c` | `effc7def5762e32c` | `effc7def5762e32c` |

`pre-push` was stale — it predated the Step 5 fix that checks BOTH sides of a
refspec, so `git push origin plan/P068:main` would have slipped the target branch
past it. It is now identical to the template. `pre-commit` was already current.

### Bootstrap topology (the chicken-and-egg, resolved)

Before P068 is released, `main` does not contain `plan-finalize` or
`plan-merge-to-main`, and `aid-plan-fsm.sh` refuses `--mode plan_branch` while
they are absent. A P067 branch cut from `plan/P068` would carry P068's own
unapproved implementation commits into `main` when the dogfood merges; a branch
cut from `main` would lack the commands the dogfood needs. Neither is acceptable,
so the run uses two checkouts:

1. **Tool worktree** — a `git worktree` of the P068 candidate, providing the
   executables only. Every dogfood command is invoked as
   `<p068-worktree>/plugins/aid-orchestrator/scripts/aid-plan-fsm.sh … --project-root <dogfood-checkout>`.
2. **Dogfood checkout** — clean and `main`-based. P067's plan and EPIC branches
   are cut from `main` and contain only P067's own small payload.
3. **Isolation proof, asserted not assumed** — before the dogfood merge,
   `git log --oneline main..plan/P067` must contain only P067 payload commits and
   zero P068 implementation commits, verified by asserting that each P068
   candidate commit fails `git merge-base --is-ancestor` against
   `main..plan/P067`. Both SHAs and the command output go in this report.
4. **Resynchronise after** — once the dogfood advances `main`, `plan/P068` is
   re-synchronised onto the new `main` so its candidate is re-frozen against
   reality rather than a pre-dogfood target head.

The point of the topology is narrow and worth stating plainly: **the tool under
test must never smuggle itself into the target branch as a side effect of testing
itself.**

### Subject eligibility

`P067` is reserved in `.aid-o/config/counter.yaml` for exactly this purpose. The
subject must have 2 or 3 EPICs, touch no high-risk path, and carry a small
tracked payload under `plugins/`. Selection is bounded by those criteria rather
than left to taste, and the chosen subject's screening goes here before the run.

## Evidence that exists today

The mechanisms the dogfood would exercise are covered by executable tests on this
branch, run against real Git state rather than mocks:

| Claim | Where it is proven |
|-------|--------------------|
| The specialist cadence is recorded, exactly once each | AC10 — a real review pass writes `dispatch_counts`; AC3 covers the refusals |
| Review outputs are bound by content hash and re-verified at close | AC10, AC7 |
| The gate profile runs once, against the frozen candidate | AC7 (removal blocks close) |
| EPIC work reaches the target branch only through the plan branch | AC10 — the plan merge has exactly two parents and is the only merge on the target |
| The merge is a compare-and-swap against the approved head | AC5, CP2 M1/M2 regressions |
| A crash at every transaction boundary converges without duplication | AC9 |
| A published rollback is a revert, never a rewrite | AC9 |
| Close is refused without durable proof | AC7, and the CP3 finding on the mandatory receipt |

## What only the live run can prove

- That the two-checkout isolation holds in practice, with the recorded SHAs.
- That the hooks behave correctly on a real push.
- Cadence counts observed across a genuinely multi-EPIC plan rather than a
  fixture.
- The rollback drill on a target branch that was really advanced.
- The fresh-agent simulation (manual, and deliberately not an executable
  acceptance criterion).

## Fresh-agent simulation

Not performed. It belongs to the live run and is recorded here as supporting
evidence when it happens, never as a mechanical assertion.


---

# Run record — 2026-07-27

PM authorization was given. The dogfood ran. It did not merge, and the reason it
did not merge is the most useful thing it produced.

## What happened, in order

| Step | Result |
|------|--------|
| `plan-start P067 --mode plan_branch` | OK — the first plan ever created in plan_branch mode |
| EPIC 1 work, then `epic-merge-to-plan` | merged into `plan/P067` |
| EPIC 2 work, then `epic-merge-to-plan` | merged into `plan/P067` |
| `--stage sync` / `--stage freeze` | candidate `f3c68d5`, run `R-P067-final-1` |
| `--stage gates` (attempt 1) | **FAILED** — and correctly |
| candidate re-freeze | `307b654`, run `R-P067-final-2` |
| `--stage gates` (attempt 2) | **PASSED**, profile `release`, exactly one run |
| `--stage inputs` | produced all three C4 inputs from the real candidate |
| `--stage review` | **PASSED** — every output protocol-valid and candidate-bound |
| `--stage c4` | **release_ready=false, 4 blockers** |
| `--stage summary` | PM summary rendered; plan held at `AWAITING_PM` |
| merge to `main` | **NOT PERFORMED** |

## The four C4 blockers

1. `plan_review` — P067 has no C0 plan review, a required input at the boundary.
2. `verification_report` — the at-HEAD verification failed.
3. `epic_rollup:E-067-1_2` — the per-EPIC evidence directory is absent.
4. `epic_rollup:E-067-2_2` — likewise.

Blockers 3 and 4 are honest consequences of how the run was driven: both EPICs
were merged into the plan branch without ever going through the EPIC FSM, so
they produced no per-EPIC evidence. C4 noticed. That is the boundary doing
precisely what it exists to do — refusing to call a plan releasable when the
evidence behind it does not exist.

**No merge was attempted.** Merging past a not-ready C4 requires an explicit PM
override, which is a PM-authority act and not one the controller takes.

## Two real findings, surfaced by running it

**F1 — an explicitly named `--project-root` was ignored for a linked worktree
(FIXED).** `_pfsm_resolve_project_root` collapsed any worktree to the git common
dir, so the named dogfood checkout resolved back to the main repository and every
lifecycle write aimed at the wrong tree: it refused "on branch
task/E-068-2_2/main" while the caller had named a checkout sitting on `main`. The
two-checkout topology could not work at all. A named worktree root is now
honoured as given; an inferred root keeps the previous behaviour, which stays
correct because plan runtime state is shared across worktrees.

**F2 — `epic-merge-to-plan` does not require `epic-complete` to have succeeded
(RECORDED, NOT FIXED).** For EPIC 1 the completion check refused — "cannot
confirm the EPIC reached DONE" — and the merge into the plan branch proceeded
anyway; the manifest went `pending` to `merged_to_plan`, a permitted transition.
So an EPIC can reach the plan branch, and therefore the candidate, with no proof
it ever completed. C4's roll-up blockers catch the consequence downstream, but
the EPIC-level gate itself does not hold. Changing it amends the transition
contract, so it is written down for a decision rather than patched mid-run.

## Isolation proof — measured, not assumed

Commits on the plan branch and nowhere else:

    307b654 docs(P067): record the gate-authoring correction
    f3c68d5 merge(plan-final): main into plan/P067
    5fc8093 merge(epic): E-067-2_2 into plan/P067
    34d18c6 feat(P067): dogfood payload 2
    c069ba9 merge(epic): E-067-1_2 into plan/P067
    76014ef feat(P067): dogfood payload 1

Files the plan would deliver:

    plugins/aid-orchestrator/reference/P067-dogfood-note-1.md
    plugins/aid-orchestrator/reference/P067-dogfood-note-2.md
    plugins/aid-orchestrator/reference/P067-dogfood-note-3.md

Every P068 implementation commit was tested against the plan branch with
`git merge-base --is-ancestor`: **none is an ancestor**. The tool under test did
not smuggle itself into the candidate.

## What the run proved

- A plan can be created, worked, merged and finalized in `plan_branch` mode.
- The gate profile runs **once** per attempt. A second run was refused even after
  the configuration was corrected — a corrected config does not get to overwrite
  the history of the attempt it was corrected in.
- A failing candidate is shown, never silently retried.
- Changing the candidate invalidates every plan-final field and returns the plan
  to `PLAN_FIX`, leaving the previous run directory byte-identical.
- `--stage inputs` produces the three C4 inputs from the real candidate and the
  real EPIC set, and `--stage review` accepts exactly what it produced.
- C4 refuses to declare a plan releasable on absent evidence.

## What it did not prove

The merge itself, the tag, the push, and the rollback drill on a really-advanced
target branch. All of them sit behind the four blockers above.

## `main` during the run

`main` moved twice, both by the lifecycle layer and both by design: `a61154f`
(the P067 manifest) and `7e51603` (its `mode: plan_branch` stamp). No plan
content reached `main`.
