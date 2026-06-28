---
name: aid-verify-plan
description: Independent adversarial review of an implementation plan before it goes to execution
user_invocable: true
---

# /aid-verify-plan — Independent Plan Review

Dispatch an **independent** agent to adversarially review an implementation plan
*before* it is sent to execution. Catches false-green plans, scope creep, and
plans that deliver no real value — before any code is written.

## Arguments

```
/aid-verify-plan [plan-path | EPIC-id]
```

- **No argument (default)** — review the plan that is live in *this* session: the
  plan just written or discussed here, otherwise the newest file in
  `.aid-o/plans/` or the newest EPIC in `.aid-o/tasks/`.
- **`plan-path | EPIC-id`** — explicit path to a plan/EPIC file to review instead.

## What it does

1. **Identify the target.** Resolve the plan from the current session context
   (the plan just produced or under discussion), or from the argument.
2. **Dispatch an independent subagent.** Dispatch a `general-purpose` Agent in a
   **fresh context** with the Review Protocol below, the target plan, and read
   access to the repo. Do **not** review inline — independence from the session
   that authored the plan is the entire point ("don't trust prior PASSes").
3. **Relay the verdict.** Return the subagent's structured findings to the PM.
   The human summary is delivered in **Czech** (see protocol); the severity
   labels and verdict keep their canonical form.

## Why independent

The session that wrote a plan is the worst judge of it — it already believes the
plan is correct. A fresh agent with no stake in the plan, instructed to refute
rather than confirm, is what surfaces the false-green path. This mirrors the
project rule: *adversarially verify non-trivial plans before presenting as final.*

## Review Protocol (subagent instruction — pass verbatim)

> Perform an independent review of an implementation plan.
>
> **Important:**
> - Implement nothing.
> - Do not trust that the plan is correct just because it is long or formally
>   looks good.
> - Be adversarial: look for where the plan can lead to a false-green
>   implementation, wasted work, or non-delivery of real value.
> - Verify the plan against the real repo state, not just against the brief text.
>
> **Review steps:**
>
> 1. **Verify what the plan must actually deliver.** What problem does it solve?
>    What concrete outcome is produced? Who is the user/consumer? Is it clear how
>    we recognise DONE?
> 2. **Compare the plan with repo reality.** Do the named files, scripts,
>    registries, commands, skills exist? Does it plan changes into wrong paths?
>    Does it ignore existing implementation or introduce a parallel system? Does
>    it rely on nonexistent helpers, schemas, ports, fixtures, services?
> 3. **Check scope.** Too broad for one EPIC/step? A hidden runtime change
>    disguised as doc/schema-only? Side problems that should be a separate plan?
>    Conversely, a critical part missing without which the result is unusable?
> 4. **Check acceptance criteria.** Concrete, verifiable, blocking? Each
>    step/phase its own AC? Not just "tests pass" or "file exists"? Is PASS /
>    FAIL / PARTIAL / UNVERIFIABLE clearly defined? Every AC that says
>    "always", "all", "each", "never", or similar must define its exact
>    universe (for example: "all documents" vs "documents with `client_id`").
>    If the universe is implicit, require a plan fix before implementation.
> 5. **Check producer-consumer contracts.** Who produces the artifact? Who reads
>    it? How is it bound to HEAD/revision/hash? How is stale evidence detected?
>    Is there a cycle or a missing consumer? For any eval/evidence artifact, the
>    plan must say which part of the pipeline it actually runs and which parts
>    are not exercised, so it cannot be misread as full coverage.
> 6. **Check the test strategy.** Positive *and* negative fixtures? Negative
>    controls that must fail on a typical regression? Not dependent on synthetic
>    data alone? Real-data/oracle verification where needed? Is it clear how
>    absence-of-evidence, stale evidence, and a wrong enum/schema are tested?
>    Every new integration function must have at least one caller-flow test, not
>    only a unit test of the pure function.
> 7. **Check false-green risks.** Can it pass while the result is unusable? Can
>    the LLM rewrite a deterministic fail into a pass? Can old evidence apply to a
>    new commit? Can a missing fixture cause a skip instead of a fail? Can the
>    implementer ship a formal artifact with no functional consumer?
> 8. **Check fit with the AID control system.** Is it clear whether this is
>    C0/C1/C2/C3/C4 or a legacy CP alias? Is observe vs dual-run vs blocking
>    clear? Does it turn blocking on too early? Does it have a clear place in the
>    roadmap and dependencies? Does it duplicate Auditor/Curator/CP logic instead
>    of unifying it?
> 9. **Check operational and security impact.** A new dependency without
>    justification? Requires a nonexistent Node/Python/tooling version? Opens
>    ports outside the rules? Introduces write/exec where it should be read-only?
>    Is there a rollback or safe observe mode?
> 10. **Check value to the PM/user.** Will the result be understandable after
>     implementation? Will it expose concrete past mistakes? Is it clear how it
>     improves controls vs today? Is it just another document/layer without
>     enforcement?
>
> **Write the output like this:**
>
> **Verdict:** PASS / PASS WITH CONDITION / FAIL / CANNOT VERIFY
>
> **Most important findings:** ordered by severity BLOCKER / HIGH / MEDIUM / LOW.
> Each finding must have: the concrete location in the plan, why it is a problem,
> which requirement or principle it violates, and exactly what to change.
>
> **Missing decisions:** list the questions without which the plan must not be
> implemented.
>
> **Missing acceptance / tests:** what must be added so the plan can be
> objectively verified.
>
> **Missing runtime/eval coverage:** any planned evidence that does not identify
> the real caller path, pipeline slice, inputs, outputs, and untested parts.
>
> **Recommended revised approach:** the concrete order of plan fixes; what must
> be blocking before implementation starts; what can remain a later extension.
>
> **Short human summary for the PM:** 5–10 sentences **in Czech**. Clearly say
> whether to send the plan to implementation. No technical noise.

## Reads / Writes

- **Reads:** the target plan/EPIC file (session context, `.aid-o/plans/`, or
  `.aid-o/tasks/`); repo state (read-only, via the subagent).
- **Writes:** nothing. The review is advisory — it produces a verdict for the PM,
  not an evidence file (unless the PM asks to save it).

## Relationship to FSM / skills

- **Standalone PM tool, outside the FSM** — like `/aid-do`, it does not write
  `fsm-state.yaml`, does not create an evidence dir, and does not touch the
  pending-dispatches ledger. The `aid-emit-dispatch.sh` wrapper therefore does
  not apply: outside an FSM run there is no orphan-dispatch reconciliation to
  feed.
- **Complements `agents/verifier.md`** — that agent runs the in-pipeline review
  checkpoints (CP2–CP5) during `/aid-run`. `/aid-verify-plan` is the manual,
  pre-execution gut-check the PM fires by hand on a plan that is not yet running.

**Last Updated:** 2026-06-28
