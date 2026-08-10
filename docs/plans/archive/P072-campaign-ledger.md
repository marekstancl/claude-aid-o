> **ARCHIVED 2026-08-10.** Superseded by the cancellation of the entire
> test-parallelism line (PM 2026-08-09, IMP-469 rejected) and its removal in
> P078 (v2.82.0). The scheduler, parallel lane, rollout gate, divergence check
> and the acceleration campaign this document serves no longer exist. Kept as
> historical record only — do not use it to plan work.

# P072 Step 28 — campaign record

## Scenario 6, first, because it is the one people will quote

**The acceleration campaign was NOT run.** There is no measured before-and-after
wall clock for this repository's full test suite, and the combined P066, P069,
P071 and P072 line of work therefore **does not yet support a claim of
test-suite acceleration.**

That is the plan's own exit condition, and it is stated here rather than
softened. What exists is the machinery and one measured lane; what does not
exist is the campaign that would turn that into a portfolio-level figure.

## What WAS measured

| Measurement | Figure | Where |
|---|---|---|
| A real 4-unit lane, serial vs concurrent, repeated twice | **29 197 ms → 14 105 ms**, and 29 200 ms → 16 256 ms | [`P072-representative-lane-evidence.md`](P072-representative-lane-evidence.md) |
| `bats --jobs` genuinely parallelises here | 12.5 s serial → 3.4 s at 4 workers | measured before building the pilot, so its verdicts mean something |
| Lane partition cost | 101 s → 60 s after batching the resolver | the hot path a gate run pays before any test starts |
| Boundary suite lower bound | ≥ 1 200 021 ms for 57 of 245 cases | [`P072-boundary-suite-diagnosis.md`](P072-boundary-suite-diagnosis.md) |

The lane figure covers **four units**. Extrapolating it to a pool of 65 is
exactly the arithmetic this plan forbids, so it is not done here.

## Scenario-by-scenario verdict

| # | Scenario | Verdict |
|---|---|---|
| 1 | An ordinary user command produces a complete decision | **Not demonstrated.** A `--mode full` audit dispatches LLM analyst agents; see [`P072-real-audit-record.md`](P072-real-audit-record.md) |
| 2 | Approval activates real scheduled execution | **Half demonstrated.** The generated configuration is `sequential` by default and the approval scripts work; the concurrency half needs the 3-stage rollout gate, which needs divergence evidence this repository does not have. The gate was not bypassed |
| 3 | Units whose provenance no longer matches stay serial | **Demonstrated** — `test-integration-e2e-whole-path.sh`, on a fresh 4-unit project |
| 4 | Verdicts match the sequential baseline | **Demonstrated** — identical per-case sets and identical aggregate exit |
| 5 | No unit runs twice | **Demonstrated in both directions** — a clean campaign reports zero, and a genuine double dispatch is caught and named |
| 6 | Measured wall clock reported | **Reported as not run**, above |

## The double-execution verdict

The ledger detects the shape this repository actually has: `gate:bats_fsm` runs
`test-aid-fsm.bats` directly while `gate:bats_all` runs it in the pool, and the
`full` and `release` profiles include both. Verified against the real
`execution.yaml` — the fourth emission path resolves `bats_fsm →
test-aid-fsm.bats` and nothing spurious.

**That duplication has now been REMOVED** (PM review round 2, 2026-08-04):
`bats_fsm` is out of the `full` and `release` profiles, which already run that
file through `bats_all`'s pool.

The order mattered and is worth recording. A detector whose only proof is the
defect it currently flags cannot be shown to work once that defect is fixed, so
the red proof moved into a fixture FIRST — `test-aid-test-execution-ledger.bats`
case 1 asserts the same two gate ids still exit 7 — and only then did the
configuration change. Otherwise removing the waste would have been
indistinguishable from breaking the check.

Until this round the plan's own acceptance criterion for Step 26 was that a
real full run REPORTS the duplicate. That would have meant shipping a plan whose
success condition is that the repository keeps wasting the run; the criterion is
amended, and the live requirement is now zero duplicates on a real full run.

## The real full gate run of 2026-08-04 — zero duplicates, and two timeouts

A real `aid-run-gates.sh run-all --profile full` against this repository at
`2fd1f1b`, opened 07:50:57Z and closed 10:01:02Z.

**The ledger's verdict: 66 dispatched, 66 distinct, 0 duplicates, 0 deliberate
repeats.** `test-aid-fsm.bats` appears exactly once, and `bats_fsm` is reported
`profile_excluded` — the live duplication this plan found is gone, and the run
that used to double-count it no longer does.

That is the amended Step 26 criterion met. It is also the whole value of the
detector: it was built, it found a real defect in this repository, the defect
was removed, and the same detector now certifies the removal on a real run
rather than a fixture.

**What that same run does NOT show: a green aggregate.** Two gates failed, both
with exit code 124 — a timeout, not a red test. No case in the run printed
`not ok`.

| Gate | Result | Cap | Elapsed |
|---|---|---|---|
| `bats_all` | fail (124) | 600 s | 600.15 s — exhausted |
| `bats_boundary` | fail (124) | 7200 s | 7200.02 s — exhausted |
| `docs_updated` | pass | — | ~1 s |
| `plan_diff` | skip | — | — |

`bats_boundary` exhausting two hours is the already-documented boundary problem
(`P072-boundary-suite-diagnosis.md`: a lower bound of ≥ 1 200 021 ms for 57 of
245 cases in one file), and it is a deferred campaign, not a regression.

`bats_all` hitting a 600-second cap turned out to be older and more interesting
than this run. Its runtime baseline
(`.aid-o/metrics/gate-runtime-baselines.yaml`) holds **two samples, and both are
censored timeouts**:

| Recorded | Elapsed | Cap | Exit |
|---|---|---|---|
| 2026-08-02T16:16:32Z | 600 171 ms | 600 s | 124 |
| 2026-08-04T08:00:58Z | 600 150 ms | 600 s | 124 |

The first predates every commit on this branch — it is P071's own run, taken
the day the quarantine was lifted. **`bats_all` has therefore never once
completed inside its cap since it was reinstated**, and no percentile exists for
it because there is not a single uncensored sample to compute one from.

This is not a regression introduced here, and it is equally not something to
report as "a timeout happened". The gate that is supposed to be this
repository's aggregate proof has never produced one. Whether the answer is a
larger cap or a faster pool cannot be decided from two censored samples, and
deciding it is precisely the deferred measurement campaign below — which now
has a concrete reason to run rather than a general one.

### The one red case, and what it turned out to be

The uncapped pool run finished in **1556 s** — 1442 cases passed, **1 failed**.
So the 600-second cap is 2.6× too small, and that is now measured rather than
inferred from two censored samples.

The single failure was mine. `test-aid-gitignore-backfill.bats` asserts that a
gate run never touches the git state of the checkout it runs in, and the
execution ledger broke it in commit `56441cb` by doing `mkdir -p` on its own
evidence directory. Bisected: green at `v2.69.0`, red from `56441cb` — a P072
regression, introduced by the ledger itself and caught by a suite that had been
timing out before it could report.

Fixed by making the ledger obey the discipline the gate runner already had: the
timeline and the report are written INTO a directory that exists and never
create one, so the ledger now lives at
`.aid-o/work/evidence/<epic>/<run>/execution-ledger.json` and is opened only if
that directory is already there. When it is not, the run says so loudly and is
not accounted — because "not accounted" and "no duplicates" must never look
alike.

That the failure was invisible for two commits is itself the finding: a gate
that always times out cannot report anything, so its suite's verdicts were
never seen. Raising the cap is not a cosmetic change.

**So the aggregate is not green, and this plan does not claim it is.** The
no-double-execution claim is proven; the runs-clean-and-fast claim is not, and
the two are being kept apart deliberately.

## Why the campaign was not run

It is a multi-hour measurement that must run at a settled revision, and this
line of work has been changing that revision continuously. Running it against a
tree that moves would produce a figure describing no particular version.

Two further preconditions are also unmet: the P069 divergence-evidence bundles
(a separate deferred campaign) and a real full audit's decision to act on.

## To run it

1. Settle the branch and take the candidate SHA.
2. Run a real `--mode full` audit; approve its catalog and mapping.
3. Record the sequential baseline: `run-all-tests.sh` at that SHA, wall clock
   and per-suite results.
4. Satisfy the rollout gate with real divergence evidence, or record that it
   was not satisfied and stop at sequential.
5. Record the scheduled run: same membership, wall clock, per-suite results.
6. Close the execution ledger and record its summary.
7. Replace scenario 6 above with the two figures, each labelled `measured`, and
   the membership each covered.

Until then, no acceleration claim is supported by anything in this repository.
