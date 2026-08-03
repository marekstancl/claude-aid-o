# P072 Step 13 — Diagnosis of `test-aid-plan-final-boundary.bats`

**Run:** 2026-08-03, disposable clone of `feat/p072-test-audit-decision-quality`,
via `aid-test-audit-profile.sh --budget-minutes 20`.
**Receipt:** `profiles/bats_..._test-aid-plan-final-boundary.json` (schema
`aid-test-profile-v1`), with its streamed evidence log alongside.

> **Correction, same day.** The first version of this document claimed the
> suite's cost came from accumulating fixture state, and rated that `high`
> confidence. That claim was wrong, and it is retracted below rather than
> quietly edited. The measurement it rested on is unchanged; the causal
> conclusion drawn from it was never established. The profiler's bucket has
> since been renamed from `fixture_growth` to `cost_rises_across_run` for the
> same reason: the old name asserted a cause the measurement cannot see.

---

## Headline

The suite **did not finish**, and the run says so: `complete: false`,
`incomplete_reason: deadline`, **lower bound 1 200 021 ms (20 min)**. In that
time it completed **57 of 245 planned cases**.

What the run establishes is a correlation, and only that:

> per-case cost rises from **8 814 ms** (first quartile of observed cases) to
> **53 506 ms** (last quartile) — a **6.07×** increase across a single run.

Later cases were more expensive than earlier ones. That is the whole finding.

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
retrying or failing.

Source signals in the same file: **270 git invocations**, **716 subprocess
substitutions**, 13 explicit sleeps, 5 retry/wait constructs. Those are
recorded as signals, not as an attributed share of the milliseconds — the
runner reports one duration per case and cannot separate waiting from working.

## The retracted claim, and why it was false

The first version read the rising curve as accumulating fixture state, and
went on to rule out splitting the file on that basis. Checking the suite's own
setup shows why that could not be right:

```bash
# scripts/tests/bats/test-helpers.bash — setup_test_evidence_dir(), called
# from this suite's setup(), i.e. once PER TEST CASE:
TEST_TMPDIR=$(mktemp -d)
export TEST_PROJECT_ROOT="$TEST_TMPDIR/project"
mkdir -p "$TEST_EVIDENCE_DIR"
cd "$TEST_PROJECT_ROOT"
git init -q -b main
...
git commit -q -m "initial"
```

Every case gets a freshly mktemp'd root and a freshly initialised git
repository. There is no fixture carried from one case to the next, so there is
no accumulating fixture for the cost to grow with. The mechanism named in the
original diagnosis does not exist in this suite.

The measurement was fine. The story attached to it was not, and it was rated
`high` confidence — which is the specific failure mode this whole capability
was built to remove: a plausible-sounding cause, cited with a real number,
pointing remediation at the wrong thing.

## What is actually still open

Two explanations remain live, and the run cannot rank them:

1. **The later cases are simply heavier work.** Case ordering in the file is
   not random: cases 45+ are the AC3 band, which drives full review passes,
   C2 commit ranges and plan-utility registration. Heavier setup per case
   would produce exactly this curve with no accumulation anywhere.
2. **Something outside the per-case fixture accumulates.** Per-case roots are
   fresh, but they are all created under the same `TMPDIR` and never removed
   during the run; 245 temp trees, each with its own git repository, is a
   plausible source of a cost that grows with position. This is a *different*
   mechanism from the retracted one, and it is equally unproven.

## The probe that would settle it

**Run cases 1–10 and cases 45–54 in isolation, each from a fresh fixture root,
and then run the same two bands in reversed order.**

- If the AC3 band is slow whether it runs first or last, the cost is intrinsic
  to those cases — and splitting the file becomes a reasonable option rather
  than a ruled-out one.
- If the AC3 band is fast when it runs first and slow when it runs last, then
  something accumulates across the run, and hypothesis (2) is where to look
  next.

The probe is bounded — roughly 20 cases in each ordering, minutes rather than
hours — and it discriminates. Until it runs, the profiler maps this receipt to
`measure`, not to `fix` and not to `split`.

## Status against the plan

- Step 13's acceptance asked for an honest lower bound and a
  root-cause-specific next probe rather than a generic `measure` finding.
  **Met on the lower bound** (1 200 021 ms, with the observed prefix kept) and
  **met on the probe**, which is specific to this file's structure.
  **Not met on naming a cause** — and the corrected receipt now says so
  rather than supplying one.
- The run did **not** complete within its budget, which the plan anticipated
  explicitly. That is recorded as the result, not worked around by extending
  the budget until a confident answer appeared.
- No remediation is proposed by this document. The suite remains in
  `gate:bats_boundary`, outside the parallel pool, exactly as before.
