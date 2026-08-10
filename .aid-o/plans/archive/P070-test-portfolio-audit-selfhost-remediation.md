---
id: P070
type: regular
status: done
created: 2026-07-30
author: PM + AI
lifecycle_strict: true
depends_on_plans: [P066]
---

> **Closure (2026-08-09):** Absorbed by P072 (documented in docs/plans/2026-08-02-SPEC-P072...md §2.3); all 3 ACs verified shipped at v2.79.x HEAD (2026-08-08 audit)

# Plan: Test Portfolio Audit — Self-Host Remediation

## Plan Type

This plan is type: `regular` (new capability additions: a shell-suite discovery adapter, plus a
documented/tooled precondition for disposable-clone audits).

## Context

Generated via P066's own sanctioned handoff (Step 16/22): `/aid-audit-tests` was run against
`aid-orchestrator` itself in a disposable clone (P066 Step 21, `test-integration-self-host-audit.sh`),
and its real, reproduced findings recommend remediation. This plan traces every item to that
specific audit run — it is generated output, never auto-executed; P066 itself carries no
quarantine-lift or remediation AC of its own (P066 Constraint 3).

## Goal

Close the two real gaps P066's self-host audit found in its own tooling: (1) a disposable-clone
audit silently loses all declared-command gates unless the operator manually copies gitignored
project config first; (2) the audit's fixed EPIC-1 adapter set has no way to discover standalone
shell test scripts, so 36 of this repo's own real, CI-run test suites are invisible to
`run_units`.

## Scope

**In scope:**
- Item 1 (Step 21 finding 1, `.aid-o/work/test-audits/self-host-audit-findings.txt`): document
  and/or tool the "copy `.aid-o/config/`" precondition for any disposable-clone audit invocation,
  so it is never a silent, undiscoverable gap again.
- Item 2 (Step 21 finding 2, same findings file): design and add a `sh:`-runner shell-suite
  discovery adapter (schema already reserves the naming convention — `sh:<relative-path-without-
  extension>` — per `test-catalog.schema.json`'s own `run_unit` doc comment), so standalone
  `test-*.sh` scripts become real, schedulable `run_units`.

**Out of scope:**
- Any scheduler/gate-integration work (P069's job).
- Modifying `aid-select-tests.sh` (deferred entirely to P069, same as P066).
- Re-running a broad audit beyond what already produced these two findings.

## Approach

### Option A: Fix both items in one small, focused plan (Recommended)

Both items are narrow, independent fixes discovered by the same audit run; bundling them avoids
a second CP1 pass for what is, in total, still S/M effort.

**Pros:** one bounded review pass; both items trace to the same audit evidence file.
**Cons:** none identified — the two items don't interact, so there is no coupling risk from
bundling them.

### Option B: Split into two separate plans

**Cons:** doubles CP1/review overhead for two items that are each individually small; rejected.

### Decision

**Chosen:** Option A.
**Rationale:** both items are small, independently testable, and already traced to the same
Step 21 evidence — no reason to split.

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1 | Disposable-clone config precondition | Document (`/aid-audit-tests` command file) and/or tool (a `--project-root` pre-check that warns if `.aid-o/config/` is absent while `.git/` exists) the gap Step 21 found | S |
| 2 | `sh:` shell-suite adapter | New `aid-test-adapter-shell-suite.sh` (or extend package-script adapter) discovering standalone `test-*.sh` files following the bats-adapter's own one-run_unit-per-file convention; wire into `aid-test-inventory.sh` alongside the existing 3 adapters | M |
| 3 | Re-run self-host audit | Re-run `/aid-audit-tests repo --mode static` against `aid-orchestrator` and confirm `run_units` now includes the 36 previously-invisible shell suites, with no double-counting against existing declared-command gates | S |

## Constraints

- Never modify `aid-select-tests.sh` (P066's own constraint, inherited here).
- The new `sh:` adapter must follow the EXACT same "one run_unit per file, never per assertion"
  convention the bats adapter established in P066 Step 2 — no re-litigating that decision.
- No second job/process supervisor; if any command execution is needed for verification, reuse
  `aid-job.sh` exactly as P066 already does.

## Resources Verification

### Existing Resources (must exist in codebase)

- [x] `plugins/aid-orchestrator/scripts/lib/aid-test-adapter-bats.sh` — the convention this new
  adapter must mirror (verified: exists, P066 Step 2)
- [x] `plugins/aid-orchestrator/scripts/aid-test-inventory.sh` — orchestrates existing adapters,
  Step 2's new adapter wires in here (verified: exists, P066 Step 4)
- [x] `plugins/aid-orchestrator/defaults/schemas/test-catalog.schema.json` — already documents
  the `sh:<relative-path-without-extension>` convention for this exact adapter (verified: exists,
  P066 Step 1)
- [x] `.aid-o/work/test-audits/self-host-audit-findings.txt` — the source evidence for both items
  (verified: exists, produced by P066 Step 21's `test-integration-self-host-audit.sh`)

### Plan Assumptions (must match reality)

- [x] Real counts verified directly against this repository at plan-authoring time (2026-07-30):
  74 `.bats` files, 36 standalone `test-*.sh` scripts, 83 total `run_units` in the current
  approved catalog (`.aid-o/config/test-catalog.yaml`), 0 of which have `runner=="sh"`.

### Resolution

- [x] All items verified against real, current codebase state — none absent.

## Acceptance Criteria

- [ ] AC1: `/aid-audit-tests`'s disposable-clone precondition (config copy) is documented and/or
  tooled, closing Step 21 finding 1
  - verification_pattern: `must_contain` — `plugins/aid-orchestrator/commands/aid-audit-tests.md`
    contains a case-insensitive match for `disposable clone`
- [ ] AC2: a `sh:`-runner adapter exists and is wired into `aid-test-inventory.sh`
  - verification_pattern: `cmd` — `grep -q 'sh_adapter_discover\|aid-test-adapter-shell' plugins/aid-orchestrator/scripts/aid-test-inventory.sh`, `expected_exit: 0`
- [ ] AC3: re-running the self-host audit against this repository shows `run_units` with
  `runner=="sh"` greater than 0
  - verification_pattern: `cmd` — `yq -o=json '.run_units' .aid-o/config/test-catalog.yaml | jq -e '[.[] | select(.runner=="sh")] | length > 0'`, `expected_exit: 0`

## Traceability

| Item | Source finding | Evidence |
|---|---|---|
| Step 1 (disposable-clone config precondition) | P066 Step 21 finding 1 | `.aid-o/work/test-audits/self-host-audit-findings.txt`; reproduced in `test-integration-self-host-audit.sh` |
| Step 2/3 (`sh:` adapter) | P066 Step 21 finding 2 | Same findings file (`standalone_sh_test_scripts: 36`, `sh_runner_run_units: 0`); reproduced in `test-integration-self-host-audit.sh` and `test-integration-remediation-handoff.sh` (Step 22) |

## Next Steps

- [ ] PM reviews this plan.
- [ ] Run `aid-plan-lint.sh` and the normal CP1/C0 review pass before any EPIC generation.
- [ ] Do not run `/aid-run` until EPICs exist and the CP1/C0 outcome is reviewed.

---

**Last Updated:** 2026-07-30
