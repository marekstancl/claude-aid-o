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

**That duplication is still present in this repository.** It is now detected
rather than silent; removing it is a configuration change to the gate profiles,
not a code change, and it is deliberately not made here — a plan that both
introduces a detector and edits the configuration it flags leaves nobody able
to tell whether the detector works.

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
