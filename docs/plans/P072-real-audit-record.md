# P072 Step 24 — the real full audit, and the half of it I could not run

Step 24 asks for a real `--mode full` audit of this repository through the
ordinary user path, with its catalog and mapping approved through the
sanctioned scripts.

**Status: PARTIAL, and deliberately recorded as such.**

A full audit dispatches read-only `test-portfolio-analyst` agents, one per
shard, and consolidates their terminal dispositions. That dispatch is a
controller action with real LLM agents — it is not something this
implementation session can perform on its own, and pretending otherwise would
produce exactly the fabricated record this plan exists to prevent.

What follows is what was actually run, and what was not.

---

## What WAS run, end to end, against this repository

Every one of these is a real invocation against a real disposable clone
prepared per the Step 8 precondition (`git clone` + an explicit copy of the
gitignored `.aid-o/config/`).

| Chain | Evidence |
|---|---|
| Wave-0 scanner → schema-valid proposed catalog | `test-integration-self-host-audit.sh` — 8/8, including "all 36 standalone shell suites are represented as `runner:"sh"` run units" |
| measure → select → profile → finalize | `.aid-o/work/evidence/p072-profile-production-chain/` — real measurements of two units, a real profile of the selected one, a decision with two actions |
| committed catalog → lane partition → helper drift → every consumer → restored | `test-integration-parallel-authority-e2e.sh` — 10/10 from a clean clone |
| a real 4-unit lane, piloted twice | `docs/plans/P072-representative-lane-evidence.md` — 29.2s serial vs 16.3s concurrent, 36 cases matching |
| five report shapes through the production finalize entrypoint | `test-integration-audit-report-shapes.sh` — 23/23 |
| scheduler consumption agrees with the resolver | `test-integration-scheduler-catalog-consumption.sh` — 6/6 |

## The portfolio figures, measured

| Figure | Value |
|---|---|
| Bats run units in the catalog | 74 |
| `.bats` files in the tree | 106 |
| Standalone `test-*.sh` suites | 36 |
| Suites the aggregate runner discovers | 150 |
| Catalog units with `parallel.status: safe` | 66 |
| Lane pool / sequential / boundary | 65 / 7 / 2 |
| Units refused by the P071 migration | 6 — 4 changed since P071 verified them, 2 whose dependency closure still cannot be fully read |

## What was NOT run, and why

- **The agent dispatch waves.** A `full` audit's shard and specialist waves are
  LLM dispatches. Their outputs — one terminal disposition per assigned run
  unit — are what the consolidator reconciles. Without them there is no
  `disposition_count` to reconcile against `inventory_count`, so the
  end-to-end coverage figure this step asks for does not exist yet.
- **`aid-test-catalog-approve.sh` + `aid-test-catalog-confirm-mapping.sh` on a
  real audit's output.** Both scripts are exercised by the integration suites
  against fixtures, but not against a catalog that a real audit proposed.

## What that means for the steps that depend on this one

- **Step 25** did not need the audit output: it re-grounds P069 against the
  final *schema*, which exists. Complete — see
  [`P069-recontract-check.md`](P069-recontract-check.md).
- **Step 26** is keyed by gate-run receipts, not audit receipts. Complete.
- **Step 28**'s measured-wall-clock campaign is the one thing genuinely
  blocked: it needs a real audit's decision to act on.

## To finish this step

Run, in a disposable clone with `.aid-o/config/` copied in:

```
/aid-audit-tests repo --mode full --budget-minutes 60
```

Then approve through the sanctioned scripts and record here: the audit id, the
six-part rendered output verbatim, `inventory_count` / `assigned_count` /
`disposition_count`, the per-runner counts, how many units reached each
disposition, and how many remain `measure` with their named next measurement.

The machinery that consumes all of it is in place and tested; what is missing
is the dispatch, which is a controller action.
