# CP1-deep adjudicator (P090)

Plan: `.aid-o/plans/P090-fronta-ktera-nezastavi.md`
Inputs: `cp1-lens-L1-behavior.md`, `cp1-lens-L2-feasibility.md`, `cp1-lens-L3-enforcement.md`,
and — per the MUST-consume rule for a `full`-band plan — `../c0-plan-review.json`.

verdict: pass

revision_count: 5

## The cross-provider review, consumed rather than observed

`c0-plan-review.json` (created 2026-08-26, `review_status: findings`,
`achieved_independence_level: cross_provider`) reports **`blocking_findings: false` and
`findings: []`** for the plan as it now stands. That is the FIFTH round: the four before it
returned 21 findings, 13 of them high, and every one was folded into the plan (the rounds are
recorded in the plan's own step prose, each with what it changed). A clean cross-provider round
therefore carries no blocker into this adjudication — it removes the external grounds for one.

The verdict below rests entirely on the three lenses.

## accepted_blockers

None. No lens raised a `stop_rule_blocker`, and none of the findings below prevents EPIC
generation from producing a coherent, implementable EPIC. The verdict is `revise` rather than
`pass` because two findings would put a FALSE claim in front of the PM, and one would put a real
cost in CI — all three are single-paragraph edits.

## resolved_in_revision_6 (was must_fix_before_generation)

- id: L2-1
  lens: L2 (feasibility)
  claim: Step 5's Edge Cases still say the dispatcher does not run the rule at `stop_hook_active`,
    while the same step's Architecture Context and AC15 say it runs and may speak but may not
    refuse.
  evidence: plan Step 5, "Edge Cases" vs "Architecture Context"; `scripts/aid-hook.sh:315-319`
    (`no_block=1`).
  why accepted: it is a direct self-contradiction inside one step, and the stale half is the one
    an implementer would turn into a test that cannot pass.
- id: L3-1
  lens: L3 (enforcement)
  claim: the Goal promises unattended completion; the step that starts work ships with
    `autonomy.spawn_next_epic: false`.
  evidence: plan `## Goal` vs Step 6 ("Výchozí stav je vypnuto").
  why accepted: the PM would read the Goal and expect behaviour the shipped default does not
    provide. The opt-in itself is a good decision with a stated reason — only the promise needs
    to match it.
- id: L3-2
  lens: L3 (enforcement)
  claim: nothing makes it a test failure if the spawn suite reaches a real `claude` binary.
  evidence: Step 6 Tests; `scripts/tests/run-all-tests.sh:268` (glob discovery — the suite runs on
    the merge path and nightly).
  why accepted: a silently-broken stub costs money and minutes on every CI run while the test
    still reports green. The fix is one assertion.

## should_fix (accepted as findings, not gating)

- L1-1 — two caps on continuation, the prose one being the only brake in the default
  configuration. Accepted as a real design gap; folding both into one code-owned cap is a design
  choice the implementer can make, so it does not gate generation.
- L2-2 — the wave table promises six waves while four steps declare `---`. Documentation vs
  contract; the contract (the declarations) is the one the tooling reads and it is coherent.
- L1-2 — `spawned_count` needs to be incremented under the queue lock, or a lost update raises
  the cap.
- L2-3, L2-4, L3-3, L3-5 — one-sentence clarifications, each named in its lens.

## rejected_blockers

- id: (none raised)
  rejection_reason: n/a — the lenses raised no `stop_rule_blockers`, which is itself the point
    worth recording: after five cross-provider rounds the remaining findings are about what the
    plan SAYS, not about whether it can be built.

## note on L1-4

L1-4 records a suspicion that was checked and dismissed: the ancestry proof in Step 3 would be
defeated by a squash merge, but `aid-plan-fsm.sh:3643` merges with `git merge --no-ff`, and the
queue's own dependency test uses the same ancestry check (`aid-queue-write.sh:847`). Recorded so
the next reader does not spend the same minutes.


## Revision 6 — what the plan did with all of it

All three `must_fix` items are resolved in the plan:
- **L2-1** — the stale Edge Case sentence is gone; Step 5 now says the rule runs and speaks but
  may not refuse, in both places, matching `aid-hook.sh:315-319` and AC15.
- **L3-1** — `## Goal` now separates what holds by DEFAULT (the state advances by itself; nothing
  can be forgotten) from what needs `autonomy.spawn_next_epic: true` (work actually starting).
  AC16 carries it into the registry row.
- **L3-2** — the spawn suite's stub writes a marker the test insists on, so reaching a real
  `claude` binary turns the suite red instead of expensive-green.

Every `should_fix` was also folded in rather than deferred, because each was one paragraph:
one code-owned cap (L1-1), check-and-increment under the queue lock (IM-1), a named idempotence
signal (IM-2), an explicitly manual `--reclaim` for a stale `running` (IM-3), Step 5 depending on
Step 4 (PF-2), four registry rows instead of three (PF-4), the `$(...)` lock discipline preserved
in the extracted helper (RC-1), a deadline as a normal terminal result (RC-3), spawn decisions
logged and the cap declared per-plan (AR-1), both autonomous plans named by the reminder (AR-2),
and the wave table rewritten to say what it is — one real concurrent pair, the rest a chain (L2-2).

One item is deliberately NOT resolved in the plan but recorded as a precondition inside the step
that needs it: **DG-1** — whether `claude -p "/aid-run …"` dispatches a slash command at all. The
repository's only precedent (`aid-hook-verify.sh:131`) passes prose. Step 6 now says one manual run
decides it before implementation, and what to do in either case. Grounding a dependency's behaviour
by running it is implementation work, not planning work.

c0_lens_observations:
  - {lens: reuse_evidence,            blockers_count: 0, confidence: high}
  - {lens: reuse_compat,              blockers_count: 0, confidence: medium}
  - {lens: planned_call_feasibility,  blockers_count: 0, confidence: high}
  - {lens: dep_api_grounding,         blockers_count: 0, confidence: medium}
  - {lens: idempotency_matrix,        blockers_count: 0, confidence: high}
  - {lens: authority_runtime_matrix,  blockers_count: 0, confidence: medium}

All six C0 lenses are observe-only in E4: none of their findings entered `accepted_blockers`, and
none changed this verdict. They are recorded because the plan acted on them anyway.
