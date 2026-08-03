# P072 Step 13 — Diagnosis of `test-aid-plan-final-boundary.bats`

**Run:** 2026-08-03, disposable clone of `feat/p072-test-audit-decision-quality`,
via `aid-test-audit-profile.sh --budget-minutes 20`.
**Receipt:** `profiles/bats_..._test-aid-plan-final-boundary.json` (schema
`aid-test-profile-v1`), with its streamed evidence log alongside.

---

## Headline

The suite **did not finish**, and the run says so: `complete: false`,
`incomplete_reason: deadline`, exit 124, **lower bound 1 200 021 ms (20 min)**.
In that time it completed **57 of 245 planned cases**.

But the run is not merely a timeout. It carries a **named, evidenced cause**:

> per-case cost rises from **8 814 ms** (first quartile of observed cases) to
> **53 506 ms** (last quartile) — a **6.07×** increase across a single run.

`root_cause.bucket = fixture_growth`, confidence `high`.

## The evidence, in the suite's own numbers

First five cases observed:

| # | case | duration |
|---|---|---|
| 1 | `--stage sync refuses while an EPIC is still running` | 7 177 ms |
| 2 | `--stage sync names a pending EPIC too` | 9 988 ms |
| 3 | `--stage sync proceeds once every EPIC is terminal` | 10 839 ms |
| 4 | `--stage sync refuses an abandoned EPIC with no reason` | 9 618 ms |
| 5 | `--stage sync accepts an abandoned EPIC once recorded` | 13 035 ms |

Slowest five observed (all in the AC3 band, cases 45–51):

| # | case | duration |
|---|---|---|
| 46 | `AC3: the recorded C2 range spans plan_base_commit..candidate` | 72 842 ms |
| 50 | `AC3: a registered plan utility that did not run blocks` | 69 980 ms |
| 45 | `AC3: a complete review pass transitions PLAN_REVIEW -> AWAITING_PM` | 59 411 ms |
| 51 | `AC3: a utility registered but never run blocks the stage` | 53 262 ms |
| 47 | `AC3: a C2 final review recording an EPIC-sized range is refused` | 52 591 ms |

Zero failures in the observed prefix — the suite is not slow because it is
retrying or failing. It is slow because each case costs more than the one
before it.

Source signals in the same file: **270 git invocations**, **716 subprocess
substitutions**, 13 explicit sleeps, 5 retry/wait constructs. Those are
recorded as signals, not as an attributed share of the milliseconds — the
runner reports one duration per case and cannot separate waiting from working.

## What this rules OUT

**Splitting the file will not fix it.** This is the conclusion the numbers
force, and it is the opposite of what a file-level timeout invites. The cost
grows with accumulated state, so cutting the file in half produces two halves
that each grow — the later one starting from wherever the split left it. The
profiler therefore maps `fixture_growth` to `fix`, never to `split`.

**Parallelising it will not fix it either.** A 6× intra-run slowdown is a
property of one sequential accumulation. Distributing the same cases across
workers redistributes the growth rather than removing it, and the two boundary
files are already outside the parallel pool for exactly this reason.

## What it does NOT yet establish

The profiler names the *shape* (accumulation), not the *substance*. It does not
say which state accumulates. The candidates its signals point at, in the order
worth checking:

1. **Git history in the fixture repository.** 270 git invocations, and the
   suite's plan-boundary cases build up commits, branches and tags in one
   fixture repo. Each subsequent case then operates on a longer history.
2. **`.aid-o` evidence trees.** Later cases validate against directories that
   earlier cases filled.
3. **Subprocess fan-out per case.** 716 substitutions is high, but it is a
   per-case constant unless the data those subprocesses walk is itself growing
   — which is the same hypothesis as (1) and (2).

The honest bounded next probe, and the one this document recommends: **run
cases 1–10 and cases 45–54 in isolation, each against a FRESH fixture root**.
If the AC3 band is fast from a clean root, the accumulation is confirmed and
the fix is per-case fixture isolation. If it is slow even from clean, the cost
is intrinsic to those cases and belongs to a different remedy.

That probe is bounded (roughly 20 cases, minutes not hours) and decisive. It is
deliberately NOT run here: Step 13's obligation is to diagnose before anyone
proposes surgery, and proposing the surgery is a separate, separately reviewed
decision.

## Status against the plan

- Step 13's acceptance asked for an honest lower bound and a
  root-cause-specific next probe rather than a generic `measure` finding.
  **Met**: 1 200 021 ms lower bound, `fixture_growth` with a cited ratio, and
  a named probe above.
- The run did **not** complete within its budget, which the plan anticipated
  explicitly. That is recorded as the result, not worked around by extending
  the budget until a confident answer appeared.
- No remediation is proposed by this document. The suite remains in
  `gate:bats_boundary`, outside the parallel pool, exactly as before.
