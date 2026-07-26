> **Location note.** These four reports are PLAN-level artifacts of P068, not
> artifacts of E-068-2_2. They live under this EPIC's evidence directory because
> the commit-scope hook governs the FSM state this run is in and permits only it;
> filing them here keeps them tracked rather than dropping them. The plan-final
> run directory is where they belong once the plan's own boundary runs.

# Auditor report — P068 plan-final

_generated_by: controller (performed directly; the PM instructed on 2026-07-26 that nothing in this run is to be delegated)
_generated_at: 2026-07-26T19:09:39Z
reviewed_head: e7e3d5f2821a28d12cd8b44c7ab0845896b56dde
reviewed_range: 0158a68..e7e3d5f2821a28d12cd8b44c7ab0845896b56dde
blocking_findings: false

## Scope

38 commits, 47 files, +10529/-269, across both EPICs of P068. The delivery is a
release boundary: the machinery by which a plan — not an EPIC — becomes a
release.

## Score: 84/100

| Dimension | Score | Basis |
|-----------|-------|-------|
| Code | 86 | Every guard fails closed; the two CAS paths are the only writers of the target ref; no TODO/FIXME introduced. Two occurrences of one durability defect (below) cost it. |
| Security | 88 | Nothing reaches the target branch without a schema-valid PM decision bound to plan, attempt, candidate and approved head. Every degenerate input blocks rather than being assumed benign. |
| Docs | 82 | Both CHANGELOGs identical, registry at 320 with derived total, surface inventory complete. The plan's own `Files:` lists were wrong often enough to cost points. |
| Process | 80 | Every step has evidence, every CP2 verdict is recorded including the failures, and no override was self-issued. One delegated fix pass had to be reverted wholesale. |

## Findings

### The one defect worth naming: durability was forgotten twice

The same mistake occurred in two different files: writing a declaration into the
worktree and treating it as recorded. First in `aid-auto-pipeline.sh` (the mode
stamp after `ensure_manifest` had already committed), then in
`inventory --apply`. Both are fixed and both now read the value back from the
target branch.

The recurrence is the interesting part. "Write the file" and "make the
declaration durable" are separate acts, and the first looks finished. Any future
code that writes to `.aid-lifecycle/` should be assumed to have this bug until
it demonstrates a read-back.

### Findings fixed during the run, not carried

Two HIGH (abort close single-shot and unrecoverable; the target-unchanged
assertion falling open on a nullable field), eleven MEDIUM and several LOW, all
from CP2/CP3 self-review. Notably: the `pre-push` exemption checking only the
local side of a refspec, which let `git push origin plan/P068:main` through; and
`cmd_plan_close` running the irreversible close ahead of its evidence gate.

### Carried, with reasons

1. **The live dogfood** and its four dependent acceptance criteria — needs PM
   authorization because it advances the real target branch.
2. **`plan_finalize_c4_reader_gap`** — the c4 stage validates three inputs no
   step of EPIC 1 produces. Recorded in the registry as `planned`/GAP rather
   than hidden.
3. **P068 has no committed lifecycle manifest**, so its own mode is not
   mechanically declared. Blocking for its plan-final merge; `inventory` now
   exists to fix it.
4. **The stale-auth landing state** — firing from `PLAN_MERGING` cannot reach
   `PLAN_SYNC`; publishing is still refused, but the recorded state does not
   match the message.

## Verdict

No blocking findings. The boundary invariants hold on the reviewed HEAD, and the
gaps are recorded rather than papered over.
