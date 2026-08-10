# Plan-final evidence durability and review-integrity maintenance

**Status:** ready after P066. Standalone AID maintenance; not a consumer-plan task and not a new ceremony for agents.

## Purpose

Plan-final review writes evidence below gitignored `.aid-o/work/` so it does not change the frozen candidate. P078 proved the remaining gap: review proof and `AWAITING_PM` are not durable outside the live checkout.

The ordinary flow stays unchanged:

```text
plan-finalize --stage review → PM decision → plan-merge-to-main → plan-close
```

## D1 — durable sidecar receipt (IMP-466)

`plan-finalize --stage review` automatically creates an immutable evidence commit in an AID-generated separate Git ref keyed by repository identity, plan ID, full candidate SHA and run ID. It is outside candidate and target branches, so it preserves frozen code and target-head CAS.

The sealed pack contains only schema-valid public-safe evidence: identities, verdict, output inventory and every output's relative path, type, SHA-256 and size. It never copies raw sessions, arbitrary logs, secrets, absolute paths or all of `.aid-o`. A required output that cannot be sealed blocks durable review.

Required transaction: `validate → build receipt → commit/ref CAS → read-back/hash check → runtime manifest receipt pointer → AWAITING_PM`.

The same plan/candidate/run/output hashes are idempotent; changed bytes for the same run fail. Crashes resume safely. `plan-merge-to-main` and `plan-close` require the receipt, and lifecycle records ref/SHA. `plan-state` or `plan-recover` rebuilds lost runtime pointers from it and never invents an audit. With `--push`, evidence publishes before target; failed evidence publication prevents target publication. Local-only evidence is reported explicitly.

Do not create a bookkeeping commit above the candidate: that would change it and correctly invalidate the gates/reviews just completed.

## D2 — complete C3 gate evidence (IMP-464)

Seal documented `plan-diff.json` paths as hash-bound C3 evidence beside `gates_report.json`. If a required AC lens needs it, absence/malformed content fails before dispatch; otherwise absence is explicitly classified, never read as a passed test.

## D3 — generated protocol-v2 scaffolds (IMP-465)

Curator/Verifier/Reporter do not recreate envelopes from prose. AID writes a schema-derived skeleton at the canonical path; the existing specialist fills payload only; AID merges and validates it before consumption. Prompts link to one generated example. No new agent or review round is added.

## D4 — grouped run freshness (IMP-467)

In plan-branch mode, freshness is a property of frozen candidate plus receipt, not each report's later `Head:` annotation commit. Validate plan-final reports as one receipt-bound group and do not independently auto-annotate siblings. Retain legacy behavior where no receipt exists.

## D5 — formal Curator adjudication (IMP-468)

Raw Auditor blockers are evidence, but a plain Curator `false` cannot erase them. Add schema-validated adjudication containing audit SHA, candidate, run, every blocker ID/fingerprint, disposition (`confirmed`, `fixed_in_new_candidate`, `false_positive`, `requires_pm`) and a public-safe evidence reference. Lifecycle accepts only complete, exact, fresh adjudication. Security/integrity and PM-required findings remain blocked. The already-run Curator supplies it; there is no new role.

## D6 — instruction and raw-Git policy

Put this same instruction in controller/pipeline help, plan-FSM usage, `extending-aid.md` and recovery errors:

> After freeze, do not manually edit, copy or commit plan-final evidence. Run `plan-finalize --stage review`; AID seals it. Merge only through `plan-merge-to-main`.

Hook/preflight warning for detectable raw merge is defence in depth only. Checkout normally preserves ignored files; clean, deletion/reclone, another worktree and raw workflows are the real loss hazards. Exclude runtime plan-state paths from generic `.json` functional-diff classification.

## Release proof

1. Review changes neither candidate nor target but creates one bound receipt.
2. Cleaned runtime state, new worktree and fresh clone recover/verify it.
3. Missing/stale/forged/partial/hash-mismatched receipt blocks merge and close.
4. Every crash boundary resumes idempotently without overwriting a ref.
5. Evidence publishes before target with `--push`.
6. Required C3 plan-diff is sealed before dispatch.
7. Specialist artefacts validate via scaffolds before consumption.
8. Multiple reports converge without annotation oscillation.
9. Only exact complete Curator adjudication changes lifecycle outcome.
10. Normal agents need no new manual action or PM override.

## Delivery policy

Implement after P066 on one isolated maintenance branch. Focused red-green tests cover each boundary, followed by one final plan-boundary integration run. Do not open a broad exploratory audit loop per sub-fix; unrelated findings go to backlog unless they bypass receipt, review binding or merge authorization.
