# P072 Step 24 — the real full audit, and the half of it I could not run

Step 24 asks for a real `--mode full` audit of this repository through the
ordinary user path, with its catalog and mapping approved through the
sanctioned scripts.

**Status: LIVE-ACCEPTANCE PENDING.** Not partial-but-finishable — *pending*, and
the whole P072 plan inherits that status. Nothing in this line of work may be
described as complete, and no `v2.70.0` tag or release may be created, until the
two live runs at the bottom of this page have actually happened and are green.

That is a PM ruling of 2026-08-04, taken after a review found this step being
counted as done on the strength of the machinery around it.

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

## The two live runs that clear this status

Both are controller actions with real agents and a real installed plugin.
Neither can be satisfied by a fixture, and neither has been performed.

### Run 1 — the real full audit (this step)

In a disposable clone with `.aid-o/config/` copied in:

```
/aid-audit-tests repo --mode full --budget-minutes 60
```

Real `test-portfolio-analyst` dispatches, then approval through
`aid-test-catalog-approve.sh` and `aid-test-catalog-confirm-mapping.sh` on that
audit's own output. Record here: the audit id, the six-part rendered output
verbatim, `inventory_count` / `assigned_count` / `disposition_count`, the
per-runner counts, how many units reached each disposition, and how many remain
`measure` with their named next measurement.

### Run 2 — the consumer E2E from the installed release candidate

Not from this working tree. From the plugin as a consumer would actually receive
it — the marketplace clone at the release-candidate commit:

```
fresh clone → /aid-init → full audit → approval
            → real gate runner / scheduler → ledger close
```

The evidence must carry **the resolved plugin version and the commit SHA it was
installed from**. Every automated proof in this plan runs scripts out of the
working tree, which cannot show that what ships is what was tested.

### Only then

Green Run 1 + green Run 2 → the plan may be called complete, and the `v2.70.0`
tag and release may be created. Not before, and not in the other order.

## Why this is pending rather than done

The machinery that consumes all of it is in place and tested; what is missing is
the dispatch, which is a controller action, and the install, which needs a
published candidate. Recording that gap as a status is the point — a plan that
calls itself complete while its own acceptance step never ran is precisely the
failure mode this plan was written to detect in others.
