# Interim P081 — AID test-tier pilot (T0/T1/T2)

**Status:** write-mode in progress (2026-08-10). Grounding dispatched; plan write next.

## Source

- Binding standard (published 2026-08-10):
  `/opt/eco/docs/docs/ecosystem/specs/test-standard.md` —
  `docs.aidlab.dev/ecosystem/specs/test-standard`.
- PM decision chain: full suite off the merge path (2026-08-10), parallelism
  line cancelled (2026-08-09, IMP-469 rejected), removal shipped as P078
  (v2.82.0).
- Visual design record: artifact 2314654a-1378-403d-9fa0-c31b5ba37378.

## Why AID is the pilot

AID is where the pain was measured (210 sads, 12 200 s full run, 5 producers /
0 reapers) and where the tooling that must learn tiers lives. The standard
itself says the pilot's reality feeds back into the document before WAN →
ACTA → Sousto → AI-Agenti → VULCAN.

## Fixed PM decisions (no clarification needed)

- Tier is decided by measured cost/scope, never importance. No escape to T2.
- T1 budget ≤ 10 min per PR total; T0 ≤ 2 min; T2 unbounded, nightly only.
- Naming: `test-<subject>`, plan/EPIC numbers banned (lint), tier mechanically
  detectable. AID picks ONE mechanism and records it in CLAUDE.md.
- Reaper monthly, no quota; deletion is legitimate maintenance.
- Nightly: cron in CI, result JSON, Telegram only when red, dedup by known
  failure, reminder surface in `/aid-status` + plan start, red ≥3 nights
  without an owner escalates.
- No parallel execution anywhere (cancelled line).

## Known preconditions and live state

- `gate:bats_all` red on main → IMP-494. `test-aid-test-content-scan.bats`
  FIXED (phantom tests from heredoc'd fixtures, commit 704e94a).
  `test-aid-test-audit-profile.bats` — PM delegated the decision; taking
  option **B**: the suite builds its own APPROVED catalog fixture in
  `setup()` instead of reading the PM's workspace catalog (the allowlist at
  `lib/aid-test-audit-command-allowlist.sh:117-119` refuses everything unless
  root status is `approved`). Verification run in flight at write time.
- Portfolio after P078: 150 bats + 41 sh suites.
- `shell_pipeline_smoke` currently carries the 18 300 s cap + `run_mode:
  background` (P079 obligation 1) — the pilot replaces this gate's role.
- DELEGATED_SUITES has 5 entries with 1:1 CI jobs (`test-run-all-delegation.sh`
  guards the parity) — the tier split generalizes this mechanism.
- Selector `aid-select-tests.sh` exists and gates on
  `mapping_approval.status == approved`; catalog mappings have DRIFTED since
  2026-08-06 (approve script refuses on a fresh snapshot) → the pilot must
  decide whether T1 selection depends on the catalog at all, or on a simpler
  path→suite map.

## Open design questions for grounding

1. Tier mechanism for AID: directory (`tests/t0|t1|t2/`) vs bats tag in the
   header. Directory breaks every existing path reference (execution.yaml
   globs, DELEGATED_SUITES keys, CI jobs, catalog run_unit_ids, registry
   `test:` fields); a tag is cheap but needs a reader. Grounding must count
   the blast radius of each.
2. What T1 selects on: the existing catalog+selector (drifted mappings,
   approval act) vs a direct subject→suite convention derived from the naming
   rule (`test-<subject>` ⇒ subject path). The naming rule may make the
   mapping table redundant — that would be a large simplification.
3. Where the nightly result JSON lives and who reads it (the standard requires
   a reminder in `/aid-status` and at plan start).
4. How many current suites violate the naming rule (plan numbers) and how many
   have no resolvable subject.

## Groundings

(dispatched)

## Plan shape (draft)

3 EPICs: (1) classify + migrate (inventory, tier assignment from measured
cost, rename, mechanical detectability, lint); (2) run paths (execution.yaml
profiles, CI nightly + reporting, selector honesty check, reminder surfaces);
(3) anti-bloat wiring (tier declaration required at plan time, second review
question, reaper input from the content scanner) + docs/registry/release.

## CP1 review (2026-08-10) — revise_required, all findings applied

Verifier verdict: **revise_required, 21 findings (4 critical)**. Grounding: 27
of 30 factual claims verified exactly; lint, phase markers, AC patterns and the
dependency graph all passed. Every finding was applied the same session; lint +
readiness re-PASS.

The four that mattered most:

1. **F-20 (critical, structural) — the nightly artifact could never reach the
   PM.** Step 7 wrote it under `$(aid_state_root)/.aid-o/work/nightly/` INSIDE
   the CI job; Step 8 read it from the PM's checkout. The runner uses its own
   `_work` checkout, `aid_state_root()` resolves to `$PWD`'s git root, and
   `.gitignore:98` ignores `**/.aid-o/` — so the standard's mandatory second
   surface would have rendered nothing forever, indistinguishable from a
   healthy fresh project, while every AC still passed because all of them were
   fixture-driven. Fixed: a shared host path (`/opt/eco/data/aid-nightly/...`,
   overridable) plus ONE non-fixture acceptance criterion proving the transport
   end to end.
2. **F-1 (critical) — the standard's flaky-quarantine mechanism was missing
   entirely** (grep "flak" returned zero) while Step 7 emitted a `quarantined[]`
   key with no producer. Fixed: retry-once detection, an owner+date quarantine
   record with a 14-day exit, the count in every nightly report and in the
   status line.
3. **F-2/F-3 (critical/high) — the standard's aggregate budgets and the SCOPE
   half of the tier criterion were both dropped.** The plan tiered per suite
   only, so ~150 T1 suites could blow the 10-minute PR budget while reporting
   compliance, and the grounding's own 119-of-191 "no resolvable subject"
   finding was used to reject an alternative but never to classify. Fixed:
   Step 2 now sums per tier and demotes overflow with a record, and an
   unresolvable subject forces T2 regardless of cost.
4. **F-8 (critical) — the stated safety net did not hold.** For a mapped path
   (e.g. `scripts/aid-fsm.sh`) the selector picks one thin unit and exits 0, so
   the exit-3/11 escalation is structurally unreachable, while the FSM's real
   coverage lands in T2 on cost alone. Fixed: Step 9 gained a `mapped_but_thin`
   gap class, and the scope rule (F-3) stops cost-only demotion of a subject's
   only merge-path coverage.

Also corrected: my premise for Step 1 was **refuted** — `aid-test-timing-bats.sh`
DOES have a caller (`aid-test-audit-profile.sh`), which additionally carries the
scar of a `bash --timing -c` argv-slot bug and an argv-exactness guard the new
portfolio caller now inherits. Plus: case-insensitive filename regex (the
uppercase class matched none of the six live offenders), a leading-comment-block
tag window (eight suites have 40-47+ line headers, so a ten-line window read
them as untagged), allowlist seeded in Step 3 and emptied in Step 4 (its AC was
unsatisfiable), delegated-suite measurement reconciled (five, not two),
`p064-closure` profile and the plan-final set-equality assertion added to Step 6,
one refusal rule instead of two contradictory ones, per-step tag requirements,
a `workflow_dispatch` validation before release, naming rules 1/4/5 and the
deployment/cross-project sections moved to explicit deferrals, and the reaper's
missing fourth input stated as degraded rather than claimed as present.

## PM approval

(pending — plan revised, lint + readiness PASS, ready for PM GO to generation)
