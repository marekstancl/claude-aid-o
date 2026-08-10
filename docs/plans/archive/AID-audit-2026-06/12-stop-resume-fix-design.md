---
audit: P041
artifact: stop-resume fix design (proposal — NOT yet implemented)
status: proposed-for-PM + external review
generated: 2026-06-01
scope: /aid-stop + /aid-run --resume (autonomous-mode safety: brake + recovery)
---

# Fix design — /aid-stop + /aid-run --resume

PM uses autonomous mode (`/aid-run --auto`), so these are real safety mechanisms and must
WORK, not be deleted. This is a design proposal for how to fix them. No code changed yet.

## The real current model (verified against source — corrects the audit's "totally broken")

There are TWO state files by design:
1. **`auto-mode-state.yaml`** — holds the autonomous `mode` (auto / manual). Managed by the
   **controller LLM** per pipeline.md §9 (`/aid-run --auto` writes `mode: auto`; the controller
   reads it each loop at pipeline.md:1039; `/aid-stop` writes `mode: manual` to halt pickup).
   It is LLM-managed, NOT script-written — so "no script writes it" is technically true but the
   design intends the controller to manage it.
2. **`fsm-state.yaml`** (post-migration; legacy name `state.yaml`) — the FSM execution state:
   `state`, `current_step`, `mode`, `epic_id`, `run_id`. Written by `aid-fsm.sh`. `--resume`
   reads this to continue execution.

So stop (flip autonomous mode → manual) and resume (continue FSM from `current_step`) are
DIFFERENT concerns on DIFFERENT files — that part is coherent by design.

## The actual defects (narrower than "broken")

1. **aid-stop.md invents a `session.*` schema** (`session.current_epic_id`, `current_step_id`,
   `epics_completed`, `steps_executed`) that exists in NEITHER state file. Its "progress capture"
   reads fields that don't exist → yields empty/unknown. The real fields live in `fsm-state.yaml`
   (`current_step`, `state`, `epic_id`, `run_id`).
2. **aid-stop.md timeline event uses wrong keys** — writes `{timestamp, state, action, trigger}`
   but the real timeline schema (`aid-stage-log.sh`) is `{ts, event, ...}`. A `jq`-by-`.event`
   consumer skips the stop event.
3. **`mode: paused`** is referenced by aid-stop but the controller only honors `auto`/`manual`
   (pipeline.md §9). The intermediate `paused` write is vacuous.
4. **Entanglement with the state-file migration** (the still-open `state.yaml` → `fsm-state.yaml`
   decision): `--resume` and the FSM both need to agree on the file name, and stop should record
   into the SAME file resume reads.

## Proposed fix — two options

### Option A (recommended) — consolidate to one state file
Drop `auto-mode-state.yaml`; put the autonomous `mode` (auto/manual) + a `stopped` flag INTO
`fsm-state.yaml`, alongside the execution state. Then:
- `/aid-stop` → `aid-fsm.sh set-field mode manual` (+ optional `stopped: true`) in `fsm-state.yaml`,
  finishes current step, records a proper timeline event (`event: aid_stop`).
- The controller loop reads `mode` from `fsm-state.yaml` (one file, one read).
- `/aid-run --resume` → reads `fsm-state.yaml`, continues from `current_step` + `state`.
- aid-stop.md: delete the invented `session.*` schema; read/write only real fsm-state fields.
**Pros:** one source of truth, resolves the file-split + the naming migration in one move, makes
stop/resume provably consistent. **Cons:** touches `aid-fsm.sh` (add `mode`/`stopped` handling
+ a `set-field mode` path) — real code change; and it FORCES the state-migration decision.

### Option B — keep two files, just fix aid-stop
Keep `auto-mode-state.yaml` (mode) separate; only fix aid-stop.md to use the real fields:
- Drop the `session.*` schema; capture progress by reading `fsm-state.yaml` real fields.
- Fix the timeline event keys (`ts`/`event`).
- Drop the vacuous `mode: paused` step.
- `/aid-stop` writes `mode: manual` to `auto-mode-state.yaml` (as §9 intends).
**Pros:** smaller, doc-mostly. **Cons:** leaves the two-file split + the naming migration
unresolved; resume still reads a different file than stop writes (coherent-by-design but fragile).

## Recommendation
**Option A.** It's the only one that makes stop+resume robust AND clears the state-file migration
(which is otherwise a separate open decision). It's a real `aid-fsm.sh` change but small and well-
scoped (a `mode`/`stopped` field + a guarded `set-field` + the controller read).

## Open questions for PM
1. **Option A or B?** (A = consolidate, recommended; B = doc-only patch, leaves debt.)
2. **Stop granularity:** stop after the current STEP finishes (clean), or hard-stop mid-step?
   (Recommend: finish current step, then halt — matches §9 "finish current step, pause".)
3. **`stopped` vs `mode: manual`:** is flipping to `mode: manual` enough to halt auto-pickup, or
   do we want an explicit `stopped: true` the controller checks first? (Recommend: `mode: manual`
   is enough — the controller already gates auto-pickup on `mode == auto`.)

## Dependency
This is coupled to the **state.yaml → fsm-state.yaml migration** (the open D1 decision). Option A
decides it (consolidate into fsm-state.yaml). If you pick A, we resolve both together.

## Post-verification corrections (independent agent, folded in)
The design was verified against source — all claims CONFIRMED (two defects worse than first
stated). Corrections to fold into Option A when we implement:
1. **Three filenames, not two.** resume reads `state.yaml` (aid-run.md:16/25/347), the FSM writes
   `fsm-state.yaml`, stop writes `auto-mode-state.yaml`. Option A must also update aid-run.md
   (`--resume`) AND pipeline.md §11 crash-recovery (~:1090-1106 still say `state.yaml`) to the
   consolidated name, or resume keeps reading a stale file.
2. **Defect #2 is deeper:** aid-stop hand-rolls raw JSON for its timeline event instead of calling
   `log_event`. Fix = route the stop event through `aid-stage-log.sh log_event` (guarantees
   `ts`/`event` keys + escaping + non-blocking append), not just rename keys.
3. **Resume must read BOTH** `state`/`current_step` (where to continue) AND `mode`/`stopped`
   (whether auto-pickup is allowed) — a run stopped mid-EXECUTE has `state: EXECUTE` + `mode: manual`.
4. **`set-field` is non-atomic** (`sed -i`, no flock). For an emergency stop racing a running
   controller, a torn write is possible — so the "provably consistent" claim needs a flock (or a
   one-line caveat). Recommend adding flock to the stop write.
5. **Out-of-scope flag:** pipeline.md:343 writes `state: paused`, which is NOT in `VALID_STATES`
   (a separate latent bug). Don't entrench it while touching FSM state semantics.

None of these invalidate the design; Option A remains the recommendation.
