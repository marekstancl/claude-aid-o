---
id: P075
type: bug-fix
status: done
created: 2026-08-08
author: PM + AI
lifecycle_strict: true
depends_on_plans: []
---

# Plan: Test Audit Remediation (TAUD-20260806-0440)

## Plan Type

This plan is type: `bug-fix` (per frontmatter `type:` field). Every step fixes an existing
precondition/validation/behavior failure found by a real audit; none adds a new capability.

## Context

`/aid-audit-tests --mode full` (audit `TAUD-20260806-0440`, 2026-08-06/08) produced a
`remediation recommended` verdict with 8 findings that carry a ready-made proposal (out
of 33 total actionable findings — the rest are 7 `measure`-only cost-outlier findings with
no fix locus yet, plus 2 `cost_blindspot` gates needing a pilot run, both out of scope
here). Two of the 8 findings (`sha256:cad4afeccd34` and `sha256:f4186bdeaf8c`, both about
`gate:bats_boundary`'s reconciliation — see Step 3) are the same root cause reported from
two independent waves (shard-1's static analysis and the wave-3 adversarial review), so
this plan collapses them into one step — 7 steps total. Every cited file:line was independently re-verified against
the current repo AND against the audit's own JSON artifacts before this plan was written
(a first CP1 pass on 2026-08-08 found 3 factual mismatches between the plan's narrative and
`consolidated-findings.json`/`decision.json`; all three are corrected below and every
severity/count/category claim in this revision was re-checked directly against those
files).

**Step 7's finding has no corresponding action in `decision.json`.** `decision.json`'s
`actions[]` array — the audit's authoritative, schema-validated decision record — carries
`fix` actions for Steps 1-6's findings but no `split` action for `npm:test`
(`sha256:21297310e12a`). The proposal exists in `consolidated-findings.json` (which
`decision.json` is derived from) with a full effort/benefit block, so it is real,
evidenced work — just not one `decision.json` itself promoted to an action for reasons
this plan cannot determine from the artifacts alone. Flagged here so the PM can confirm
Step 7 is still wanted; nothing about its content is in question.

**Execution note (2026-08-08):** PM directed direct implementation of all 7 steps in this
same session — no `/aid-plan epic`/`/aid-run` pipeline, no EPIC/plan.json scaffold, no
CP2/CP3 gates. Each step's "Implementation outcome" line records what actually happened,
including one finding (Step 1) that turned out to be a false positive on real
verification. All 7 steps ran their own real verification command (bats suite, standalone
CLI invocation, or both) before being marked done — none was accepted on inspection alone.

## Goal

Fix the 7 concrete, evidenced defects the full test audit found: one real CI coverage gap
(23 of 24 aid-gui test files never collected), one catalog/CI build-dependency drift, one
dead regression check, two false-positive/silent-skip sources in test/audit tooling, and
one under-specified run unit split.

## Scope

**In scope:**
- The 7 fixes listed in Steps 1-7 below, each traced to a specific finding in
  `.aid-o/work/test-audits/TAUD-20260806-0440/consolidated-findings.json`.

**Out of scope:**
- The 7 cost-outlier findings (4 `cost_outlier_timeout_censored` — critical, the unit was
  killed by the measurement deadline before finishing; 3 `cost_outlier_slow_unit` — high
  for `test-aid-fsm` and `test-aid-audit-tests-finalize-production`, medium for
  `test-aid-gate-waiver` — all `measure`-only, no proposal exists yet. They need a
  raised-deadline re-measurement pass before any fix can be proposed, per the audit's own
  report).
- The 2 `cost_blindspot` gates (`gate:bats_boundary`, `gate:shell_pipeline_smoke`,
  severity medium) — each needs a completed, non-timed-out run to get real cost data, not
  a code change.
- Re-running the audit itself or approving a new test catalog.

## Approach

### Option A: One plan, seven independent steps (Recommended)
Each finding is an independent, small, unrelated fix (different files, no shared state
between steps — confirmed: every step's `Depends on:` below is `none`). A single flat plan
with no cross-step dependency lets every step ship on its own EPIC without waiting on the
others. This is a maintenance/bug-fix bundle, not a design decision with alternatives —
there is no meaningful Option B for "should this CI install line exist."

## Implementation Steps

### Step 1: Widen aid-gui vitest collection to include src/

**Implementation outcome (2026-08-08): FALSE POSITIVE — no code change made.** The audit's
finding was produced by static analysis (grepping `vitest.config.ts`'s `include` field and
counting matching files), which never accounted for `packages/aid-gui/vitest.workspace.ts`
— a separate, pre-existing, untouched file that Vitest actually uses at runtime and takes
precedence over `vitest.config.ts` for a plain `vitest run`. That workspace file already
defines a second project (`name: 'dom'`) whose own `include: ['src/**/*.test.{ts,tsx}']`
and `setupFiles: ['./vitest.setup.ts']` (which already stubs `matchMedia`,
`ResizeObserver`, `IntersectionObserver` for jsdom) correctly collect and run all 23
`src/`-tree test files. Ran `npm run build -w @aid/contract && npm run test -w @aid/gui`
for real: **24/24 test files pass, 257/257 tests pass**, with zero source changes. An
earlier attempt in this same session to "fix" `vitest.config.ts`'s include directly
actually broke this — Vitest's workspace `extends: './vitest.config.ts'` on the sibling
`node` project merged the widened include into ITS effective glob too, causing every
`src/` file to also run a second time under the wrong (`node`, no DOM) environment. That
attempt was fully reverted; `vitest.config.ts` and `vitest.workspace.ts` are both
byte-identical to their pre-plan state.

**Objective (original, not executed):** Make `vitest run` in the `aid-gui` workspace
actually collect the 23 test files that currently exist in the repo but are silently
excluded from every CI run.

**Files:**
- Modify: `packages/aid-gui/vitest.config.ts` (lines ~1-9) — widen the `include` glob
- Test: `packages/aid-gui/vitest.config.ts` — run the existing suite and confirm collected
  count

**Architecture Context:** `aid-gui` is a Vite/Vitest workspace inside the npm workspaces
monorepo (`package.json`'s `workspaces` field includes `packages/aid-gui`). CI's `vitest`
job (`.github/workflows/ci.yml:142`) runs the root `npm test`, which resolves to
`npm run test --workspaces --if-present` and so includes `@aid/gui` among all workspaces —
its `vitest.config.ts`'s `test.include` glob decides what that delegated run collects for
this package specifically. This step changes only that
glob, not the CI invocation itself.

**Implementation Detail:** `packages/aid-gui/vitest.config.ts:6` currently reads
`include: ['tests/**/*.test.ts']`. Confirmed via `find packages/aid-gui -name
'*.test.ts*' | wc -l` → 24 total test files; only `tests/frontend/error-boundary-toast.test.ts`
matches the current glob (it is the one file under `tests/`). The other 23 live under
`src/` — every lettered screen (`ScreenA`-`ScreenG`, `ScreenPlan`), hooks
(`useAidSocket`, `usePollingFallback`), shell/managerial components, `lib/` modules, and
`App.wiring.test.tsx` — and use the `.test.tsx`/`.test.ts` extension under `src/**`, which
the current glob never reaches. Change `include` to:
`['tests/**/*.test.ts', 'src/**/*.test.{ts,tsx}']`.

**Error Handling:** if `vitest run -w @aid/gui` exits non-zero after the glob widens, that
is expected new signal, not a bug in this step — the 23 files have not run against current
`src/` for an unknown period. Do not revert the glob to make CI green again; instead, file
the specific failing test(s) as follow-up work and let this step land with the failures
visible.

**Edge Cases:**
- A file under `src/` matching `*.test.ts` but colocated with a non-test module of the
  same base name — the glob is extension-specific (`.test.ts`/`.test.tsx`), so this is not
  a real risk, but confirm no `*.test.ts` file was intentionally excluded for a reason not
  captured in this plan (grep for a `vitest.skip`/`.only` marker at the file level before
  landing).
- A newly-collected file that itself imports a module that does not yet build (e.g. a
  half-finished component) — surfaces as a collection-time error, not a test failure;
  triage the same way as a genuine test failure.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] `npm run test -w @aid/gui` collects and reports on 24 test files, not 1.
- [ ] Every pre-existing passing test in `tests/frontend/error-boundary-toast.test.ts`
  still passes (glob widening did not change matching for the original file).

**Effort:** S (perform) / M (verify — includes triaging any newly-surfaced failures, per
the audit's own effort bucket for this finding).
**AID Role:** qa

### Step 2: Fix npm:test catalog command's undeclared build dependency

**Implementation outcome (2026-08-08): DONE.** `.aid-o/config/test-catalog.yaml`'s command
changed from `argv: [npm, run, test]` to `type: shell, shell: "npm run build -w
@aid/contract && npm run test --workspaces --if-present"` (superseded by Step 7's split,
below, which carries the same build prefix forward per-package). Schema-validated;
`npm run build -w @aid/contract` verified to succeed standalone.

**Objective:** Make the test catalog's `npm:test` reproducer command actually runnable
standalone, outside CI's specific job ordering.

**Files:**
- Modify: `.aid-o/config/test-catalog.yaml` — the `npm:test` run unit's `command.argv`
  field
- Test: `.aid-o/config/test-catalog.yaml` — re-run the catalogued command standalone in a
  clean clone/workspace, confirming it no longer depends on a prior CI step having run

**Architecture Context:** `.aid-o/config/test-catalog.yaml` is the approved test catalog
the audit tooling's allowlist (`aid-test-audit-command-allowlist.sh`) matches measured/full
commands against — it is meant to be a faithful, standalone reproduction of what CI
actually runs, not merely CI's final step in isolation.

**Implementation Detail:** the catalogued `npm:test` command is the bare argv
`["npm", "run", "test"]` (`.aid-o/config/test-catalog.yaml:13835-13837`). CI always runs
`npm run build -w @aid/contract` immediately before `npm test`
(`.github/workflows/ci.yml:141` build step, `:142` test step) because `aid-contract`'s
`package.json` points `main`/`types` at `dist/index.js`/`dist/index.d.ts`, which are
build outputs, not committed source, and `aid-gui`/`aid-server` source import `@aid/contract`
directly. Checked `plugins/aid-orchestrator/defaults/schemas/test-catalog.schema.json` for
a prerequisite/dependency field on a run unit — none exists (`grep -c
"prerequisite\|precondition\|depends_on"` → 0) — so record the build inline: change
`command.argv` to represent
`npm run build -w @aid/contract && npm run test --workspaces --if-present` (as a `shell`
command type, since `argv` cannot express a compound shell command; use the same `type:
"shell"` shape the audit's own `gate:bats_all`/`gate:bats_boundary` entries already use in
this file as a precedent).

**Error Handling:** if the build step itself fails (e.g. a TypeScript error in
`aid-contract`), the compound command must fail non-zero as a whole (the `&&` already
guarantees this) rather than silently proceeding to run tests against a stale `dist/`.

**Edge Cases:**
- A clean clone with no prior `npm install` — the compound command still requires
  `npm install` to have run first; this step does not change that precondition, only adds
  the missing build step on top of it.
- `npm run build -w @aid/contract` itself has side effects beyond `dist/` (e.g. writes a
  build cache) — verify the compound command is still idempotent across repeated audit
  measurement runs, since `aid-test-audit-measure.sh` may invoke it more than once.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] The catalogued `npm:test` command, run standalone in a fresh clone after `npm install`
  only, succeeds without any other CI step having run first.
- [ ] `aid_test_audit_check_allowed` still matches the updated command against the approved
  catalog (no allowlist regression).

**Effort:** S / S.
**AID Role:** domain

### Step 3: Fix aid-test-inventory.sh's gate:bats_boundary reconciliation

**Implementation outcome (2026-08-08): DONE.** `contains_json`'s `--dedicated-only` branch
now returns only the 2 `BOUNDARY_RELATIVE_PATHS` run_unit_ids (cross-referenced to
`aid-bats-parallel-lane.sh:74-77`); the `--pool-only` branch excludes them. New bats case
added and passing; full suite 19/19 green. Ran the real scanner: `gate:bats_boundary`
reports exactly 2 members, `gate:bats_all` excludes both — verified directly, not just via
the test.

**Findings:** `sha256:cad4afeccd34` (`proposal_missing_fix_locus`, from shard-1's static
analysis) and `sha256:f4186bdeaf8c` (`catalog_reconciliation_error`, from the wave-3
adversarial review) — same root cause reported independently by two audit waves,
collapsed into this one step.

**Objective:** Make `inventory.json`'s `reconciliation.contains` report the real 2-file
membership of `gate:bats_boundary` instead of the full 132-file pool `gate:bats_all` owns.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-inventory.sh` (lines ~214-285) — the
  contains_json derivation
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-inventory.bats` — add a
  case asserting `bats_boundary.contains` has exactly 2 members and `bats_all.contains`
  excludes them

**Architecture Context:** `aid-test-inventory.sh`'s `contains_json` is the Wave-0 scanner's
own reconciliation record — it is what later shard/pilot/consolidator logic reads to tell
"gate X legitimately runs unit Y" apart from "unit Y was reached twice by two independent
gates" (per the script's own header comment at line ~214). A wrong `contains` set for one
gate can produce a false duplicate-execution finding against the other.

**Implementation Detail:** verified the derivation currently gives `gate:bats_all`
(`--pool-only`) and `gate:bats_boundary` (`--dedicated-only`) the identical `run_unit_ids`
list — every `bats`-runner unit in the catalog — differing only in the `partition` field
(`aid-test-inventory.sh:247-251`). The script that actually executes `bats_boundary`,
`aid-bats-parallel-lane.sh:74-77`, hard-codes exactly 2 entries in
`BOUNDARY_RELATIVE_PATHS`: `test-aid-plan-final-boundary.bats` and
`test-aid-plan-release-boundary.bats`. Add a dedicated-only special case: when deriving
`contains_json` for a gate invoking `aid-bats-parallel-lane.sh --dedicated-only`, source (or
duplicate, with a comment cross-referencing the source of truth) the same
`BOUNDARY_RELATIVE_PATHS` list instead of falling through to the full bats-runner set.

**Error Handling:** if `aid-bats-parallel-lane.sh`'s `BOUNDARY_RELATIVE_PATHS` list changes
in the future without a matching update here, the two lists silently diverge again — add a
one-line comment at both call sites cross-referencing the other file:line, so a future
editor sees the coupling.

**Edge Cases:**
- A future third `--dedicated-only`-style gate with a different boundary file list — the
  fix must key off the actual invoked list, not hard-code the current 2 paths a second
  time in `aid-test-inventory.sh`; prefer sourcing the array from
  `aid-bats-parallel-lane.sh` over duplicating it.
- `gate:bats_all`'s own `contains` set must correspondingly EXCLUDE the 2 boundary files
  (verified today it does not — this is the flip side of the same bug) — the new test case
  must assert both directions, not just `bats_boundary`'s membership.
- A boundary file removed from `BOUNDARY_RELATIVE_PATHS` in the future without a
  corresponding catalog update — the fix should read the list live rather than caching a
  count, so a shrink to 1 or growth to 3 boundary files updates `contains` automatically.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] `inventory.json`'s `reconciliation.contains` for `gate:bats_boundary` lists exactly
  the 2 boundary files.
- [ ] `gate:bats_all`'s `contains` set excludes those same 2 files.
- [ ] New bats case in `test-aid-test-inventory.bats` passes and fails against the
  pre-fix behavior (verified by temporarily reverting the fix and confirming the new test
  goes red).

**Effort:** M / M.
**AID Role:** backend

### Step 4: Install python3-jsonschema in CI so schema tests can't silently skip

**Implementation outcome (2026-08-08): DONE.** All 4 "Install jq + bats + yq" steps in
`.github/workflows/ci.yml` now also run `python3 -c 'import jsonschema' || sudo apt-get
install -y python3-jsonschema`. YAML validated.

**Objective:** Stop 24 schema-validation tests across 2 files from silently reporting
`skipped` instead of `ok`/`not ok` whenever the CI runner lacks `python3-jsonschema`.

**Files:**
- Modify: `.github/workflows/ci.yml` — the "Install jq + bats + yq" steps (4 occurrences)
- Test: `.github/workflows/ci.yml` — confirm via a CI run that both schema-test files'
  `_have_jsonschema` checks no longer skip

**Architecture Context:** CI's bash-tests jobs each run an "Install jq + bats + yq" step
before executing bats suites. `test-aid-test-catalog-schema.bats` (15 `@test` bodies) and
`test-execution-unit-receipt-schema.bats` (9 `@test` bodies) each gate on a
`_have_jsonschema` helper; when it returns false the test calls `skip` instead of running
its assertion.

**Implementation Detail:** confirmed `.github/workflows/ci.yml` has 4 "Install jq + bats +
yq" steps (lines 28, 55, 81, 107) and zero references to `jsonschema` anywhere in the file.
`test-aid-test-catalog-schema.bats`'s 15 skip sites are at lines
67/86/105/124/141/160/170/180/193/208/223/238/256/274/292 (finding `sha256:92c165e4f75b`,
severity **medium** per `consolidated-findings.json` — not critical; the earlier plan draft
mis-stated this). `test-execution-unit-receipt-schema.bats` has 9 more sites (a distinct,
separate finding, `sha256:f70857e60057`, severity **low**) — this step fixes both files'
skip risk with the same CI change, since they share the same install-step root cause.
Add `pip install jsonschema` (or `apt-get install -y python3-jsonschema`, matching whatever
package-install convention the existing "Install jq + bats + yq" steps already use) to each
of the 4 steps that precedes a job running either file.

**Falsification check (from the audit finding):** before landing, verify on the actual
self-hosted runner host whether `python3` + `jsonschema` are ALREADY present as a standing
host property outside this workflow's own install step — if so, the "silent skip" risk is
currently latent, not live, and this step becomes a defense-in-depth hardening rather than
a fix for an active gap. Either way the change is safe to make; this only affects how the
finding is framed in the fix's own commit message.

**Error Handling:** if `pip install jsonschema` fails on the runner (e.g. no network egress
to PyPI from the self-hosted host), fall back to `apt-get install -y python3-jsonschema`
from the OS package mirror — confirm at least one of the two paths is actually reachable
from the runner before landing, rather than assuming.

**Edge Cases:**
- A CI job that runs bats suites but never touches either schema-test file — installing
  jsonschema there is harmless but unnecessary; scope the change to the 4 existing install
  steps rather than adding new ones, since all 4 already precede jobs that may run either
  file.
- `jsonschema` version pinning — the tests only call `import jsonschema`; no specific
  version is asserted anywhere in the 2 test files, so an unpinned install is acceptable.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] All 4 "Install jq + bats + yq" CI steps also install `python3-jsonschema`.
- [ ] `test-aid-test-catalog-schema.bats`'s 15 previously-skippable tests report `ok`
  (or a real `not ok`), never `skipped`, in the next CI run.
- [ ] `test-execution-unit-receipt-schema.bats`'s 9 previously-skippable tests likewise
  report `ok`/`not ok`, never `skipped`.

**Effort:** S / S.
**AID Role:** release

### Step 5: Stop aid-test-resource-map.sh from flagging fixture string literals as live code

**Implementation outcome (2026-08-08): DONE — option (a), the full exclusion, not the
rejected tag-only fallback.** Added `_in_dquote_string_literal()`: a single-pass
unescaped-double-quote count before a match's start position on its own source line,
gating the `flock`/`git`/`git worktree`/`port` emit sites. Real re-scan of
`test-aid-catalog-parallel-authority.bats` confirms the `lock/shared` false positive is
gone while the file's other 71 legitimate resource findings are unaffected. 2 new
regression cases (string-literal suppressed, real invocation still caught) pass; full
suite 31/31 green. Known limitation, documented in the helper's own comment: the
unescaped-quote count is per-line/per-segment, not a real shell parser — it does not
track an open double-quoted string across a `;`/`&`/`|` segment boundary beyond the first
segment. This closes the specific finding and its regression test; it is not a general
shell-string-literal parser.

**Objective:** Make the audit's own resource-map scanner distinguish a `lock`/`shared`
reference that is real, executed code from one that is quoted-string test-fixture data,
so it stops producing false-positive `shared`-resource findings.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-resource-map.sh` (lines ~779-790) —
  the flock-matching branch and its siblings
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-resource-map.bats` — add
  a regression case

**Architecture Context:** `aid-test-resource-map.sh` is the audit's Step-14 resource-map
generator — its findings feed directly into whether a run unit can ever be promoted out of
`parallel.status: unknown`. A prior audit (`TAUD-20260805`) was rejected specifically for
false lock-positives blocking every promotion; this finding is the same failure class
recurring.

**Implementation Detail:** `test-aid-catalog-parallel-authority.bats:114-121` writes a
synthetic fixture file via
`_file a "${AT} \"a\" { flock /var/lock/x.lock true; }"` — the text `flock
/var/lock/x.lock` is DATA being written to a throwaway temp fixture, never code this
`.bats` file itself executes. The scanner's line-based match at
`aid-test-resource-map.sh:781` (`if [[ "$_seg" =~ (^|[^[:alnum:]_])flock[[:space:]]+... ]];
then _emit "lock" "shared" ...`) is a single-pass regex over each source line with no
awareness of string/heredoc-body boundaries, so it matches the literal `flock` text inside
the quoted fixture string the same as it would match real invoked code. This repo's own
test suite frequently authors bats/shell source as heredoc or quoted-string fixtures to
test the catalog/resource tooling itself (the same pattern recurs in
`test-aid-test-resource-map.bats`'s own fixture helpers), so this false-positive class is
not a one-off. Fix by tracking whether the current line/segment being scanned falls inside
an open string literal or heredoc body passed as an argument to a known test-fixture helper
function (e.g. `_file`, `_map` — grep the test suite for the actual helper names in use)
and skipping the emit in that case.

**Error Handling / rejected fallback:** a weaker fallback — flagging such hits with a
distinct `in_string_literal: true` field instead of skipping them — was considered and
REJECTED for this step: `grep -rn "in_string_literal" plugins/aid-orchestrator/scripts/`
returns 0 matches, meaning no downstream consumer of resource-map output reads such a field
today, so a hit tagged that way would still be treated as a live `shared` finding by every
current caller. Implement the full skip (exclude string/heredoc-body spans from scanning),
not the tag-only fallback, unless a concrete consumer for the tag is added in the same
step.

**Edge Cases:**
- A test file that DOES execute a real `flock` call AND separately writes fixture strings
  containing the word `flock` — the fix must still emit the real invocation's finding;
  verify both directions in the regression test (real call still flagged, fixture string
  no longer flagged).
- A multi-line heredoc body spanning several source lines — the string-literal detection
  must track state across lines, not just within a single line's regex match, since a
  single-line-only fix would miss heredoc-body cases.
- The other `shared`-emitting kinds sharing this same single-pass-scan weakness (`git_repo`,
  `port`, `socket`, etc., per the plan's original Change note) — this step's fix should
  apply to the shared line-classification helper all of them go through, not just the
  `flock` branch, so the same false-positive class does not recur under a different
  resource kind.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] The new regression test proves a quoted-string `flock`/`git worktree`/etc. reference
  written by a `_file`-style fixture helper is NOT reported as a live resource hit.
- [ ] The same regression test proves a REAL, executed `flock`/`git worktree`/etc. call is
  STILL reported (no false negative introduced).
- [ ] `test-aid-catalog-parallel-authority.bats`'s own resource-map re-run no longer
  reports `lock/shared` at the fixture-writing line.

**Effort:** L / M.
**AID Role:** backend

### Step 6: Fix or replace the dead --state-file drift-detection branch

**Implementation outcome (2026-08-08): DONE — inverted, not replaced.** Layer 1c now
asserts `aid-run-gates.sh`'s usage header DOES advertise `--state-file` (today's real
baseline) and fails loudly if it ever stops. Verified live in both directions: the real
repo passes; temporarily masking `--state-file` in a scratch copy made the check fail with
exit 1 and a named message, then the file was restored byte-identical (confirmed via
`git diff`, no residual change).

**Objective:** Make `test-plan-quality-enforcement.sh`'s Layer-1c check assert against
current reality instead of permanently taking its `SKIP` branch.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/test-plan-quality-enforcement.sh` (lines ~116-125)
- Test: `plugins/aid-orchestrator/scripts/tests/test-plan-quality-enforcement.sh` — this
  file is itself the check being fixed; its own execution is the regression signal

**Architecture Context:** this Layer-1c check exists to catch `aid-run-gates.sh` silently
gaining an interface (`--state-file`) that `plan-writing.md`'s check #17e claims it does
NOT expose. It is a drift-detector, not a feature test.

**Implementation Detail:** confirmed via `head -100
plugins/aid-orchestrator/scripts/aid-run-gates.sh | grep -q -- "--state-file"` that the flag
IS present in the usage header today (`aid-run-gates.sh:6`) and is parsed as a real flag at
`:346`. The check's current logic (`test-plan-quality-enforcement.sh:118-120`) takes the
`SKIP` branch whenever `--state-file` is found, meaning it has taken that branch on every
run since the drift happened and will continue to forever — it no longer asserts anything.
Invert the check: assert that `plan-writing.md`'s 17e example text matches the CURRENT real
invocation shape of `aid-run-gates.sh --state-file ...` (not the pre-drift claim that the
flag doesn't exist), so the check goes back to being a live regression guard against the
NEW baseline instead of a permanently-passing no-op.

**Error Handling:** if `plan-writing.md`'s 17e section is not updated in the same change to
describe the current `--state-file` behavior, the inverted check will immediately fail —
treat that as the correct, intended signal (the doc genuinely needs updating), not as a bug
in this step.

**Edge Cases:**
- A future checkout where `aid-run-gates.sh` drifts AGAIN (e.g. `--state-file` renamed or
  removed) — the inverted check must fail loudly in that case too, not silently SKIP a
  second time; do not reintroduce the same SKIP-on-any-change pattern this step is
  removing.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] The Layer-1c check no longer has a reachable branch that silently SKIPs on the
  current, real `aid-run-gates.sh` interface.
- [ ] Running the check against the current repo state produces a genuine pass (not a
  skip) confirming `plan-writing.md`'s 17e example matches reality.
- [ ] Temporarily reverting `aid-run-gates.sh`'s `--state-file` support causes the check to
  fail (proves it is live, not another permanent pass).

**Effort:** S / S.
**AID Role:** qa

### Step 7: Split npm:test into per-workspace run units

**Implementation outcome (2026-08-08): DONE.** PM confirmed proceeding despite the missing
`decision.json` action (see Note below). `npm:test` replaced by `npm:test:contract`,
`npm:test:server`, `npm:test:gui` in `.aid-o/config/test-catalog.yaml` (schema-valid,
correct sha256 fingerprints per `gate_baseline_fingerprint`, 183 unique run_unit_ids, no
duplicates). All 3 commands verified standalone: contract 3/3 files, 19/19 tests; gui
24/24 files, 257/257 tests; server 44/44 files, 612/616 tests (4 pre-existing skips,
unrelated to this change). `.github/workflows/ci.yml`'s own `npm test` step (line 162,
still the aggregate `npm run test --workspaces --if-present`) confirmed untouched.

**Objective:** Give the test catalog per-package (`aid-contract`/`aid-server`/`aid-gui`)
visibility into `npm:test`'s 71 aggregated test files, instead of one opaque unit.

**Note:** this finding (`sha256:21297310e12a`) exists in `consolidated-findings.json` with
a full proposal but has no corresponding `fix`/`split` entry in `decision.json`'s
`actions[]` — see Context above. Confirm with PM this step is still wanted before
scheduling it; Steps 1-6 all have a matching `decision.json` action and are unconditionally
in scope.

**Files:**
- Modify: `.aid-o/config/test-catalog.yaml` — replace the single `npm:test` run unit with
  3 split units
- Test: `.aid-o/config/test-catalog.yaml` — verify each split command runs standalone and
  their combined coverage matches the original aggregate

**Architecture Context:** the test catalog's per-run-unit granularity is what lets audit
waves attribute cost/reliability/parallel-safety per unit. An aggregate unit blends 3
workspaces' results into one signal, which is a structural limitation of the catalog entry
itself, not of any single package's tests.

**Implementation Detail:** confirmed via `find packages/* -name '*.test.ts*' | wc -l` per
package: `aid-contract` 3 files, `aid-server` 44, `aid-gui` 24 (see Step 1), 71 total. The
catalog's `npm:test` currently has `test_cases: []` and `confidence: low`. Replace it with
3 run units — `npm:test:contract`, `npm:test:server`, `npm:test:gui` — each with command
`npm run test -w @aid/<pkg>`. The `aid-contract` and `aid-gui` units MUST inherit Step 2's
build-dependency fix (prefix `npm run build -w @aid/contract &&`) since both packages'
tests depend on the built `dist/`.

**Error Handling:** if the 3 split commands' combined test-case count does not match the
original aggregate's 71-file scope, the split introduced a coverage gap — treat as a
blocking defect in this step, not a follow-up.

**Edge Cases:**
- `.github/workflows/ci.yml`'s actual CI job explicitly keeps using the aggregate
  `npm run test --workspaces --if-present` command — this step changes ONLY the AUDIT
  catalog's bookkeeping, never CI's real execution path. Confirm at implementation time
  that no CI file is touched by this step.
- A future 4th workspace added to `package.json`'s `workspaces` array — the split must be
  revisited manually; this step does not add automatic workspace discovery to the catalog.

**Dependencies:**
- Depends on: none

**Acceptance Criteria:**
- [ ] The test catalog has 3 independently-measurable `npm:test:*` run units instead of 1
  opaque aggregate.
- [ ] Each split unit's standalone command succeeds in a clean workspace.
- [ ] `.github/workflows/ci.yml` is unchanged by this step (verified by diff).

**Effort:** M (perform) / M (verify) — decision-required per the audit's own effort
classification, since it changes catalog bookkeeping that future audit waves depend on.
**AID Role:** domain

## Acceptance Criteria

- [ ] AC1: `npm run test -w @aid/gui` collects 24 test files, not 1 (Step 1).
  ```yaml
  verification_pattern:
    type: must_contain
    file: packages/aid-gui/vitest.config.ts
    regex: "src/\\*\\*/\\*\\.test\\.\\{ts,tsx\\}"
  ```
- [ ] AC2: the catalogued `npm:test` command declares its `@aid/contract` build dependency
  instead of relying on CI's job ordering (Step 2).
  ```yaml
  verification_pattern:
    type: must_contain
    file: .aid-o/config/test-catalog.yaml
    regex: "build -w @aid/contract"
  ```
- [ ] AC3: `inventory.json`'s `reconciliation.contains` reports exactly 2 members for
  `gate:bats_boundary`, verified by the new bats regression case (Step 3).
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-inventory.bats"
    expected_exit: 0
  ```
- [ ] AC4: CI installs `jsonschema` so the schema-validation tests can report real results
  (Step 4).
  ```yaml
  verification_pattern:
    type: must_contain
    file: .github/workflows/ci.yml
    regex: "jsonschema"
  ```
- [ ] AC5: the resource-map regression fixture proves a quoted-string tool-syntax
  reference inside test fixture data is not reported as a live shared-resource hit
  (Step 5).
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-resource-map.bats"
    expected_exit: 0
  ```
- [ ] AC6: `test-plan-quality-enforcement.sh`'s Layer-1c check asserts against current
  reality instead of permanently SKIPping (Step 6).
  ```yaml
  verification_pattern:
    type: cmd
    cmd: "bash plugins/aid-orchestrator/scripts/tests/test-plan-quality-enforcement.sh"
    expected_exit: 0
  ```
- [ ] AC7: the test catalog has `npm:test:gui` (and its 2 siblings) instead of one opaque
  `npm:test` aggregate (Step 7).
  ```yaml
  verification_pattern:
    type: must_contain
    file: .aid-o/config/test-catalog.yaml
    regex: "npm:test:gui"
  ```

## Risks

- Step 1 may surface real, previously-invisible regressions in the 23 newly-collected
  files — expected and desired, but the EPIC executing this step must budget time to
  triage them rather than treating any new failure as this step's own bug.
- Step 5 is the highest-effort, highest-risk item (production audit tooling used by every
  future audit) — a wrong fix here could introduce new false negatives (real shared
  resources silently reclassified as fixture data). Its Test entry is load-bearing, not
  optional, and must prove both directions (false positive removed, true positive kept).
- Step 7 has no matching `decision.json` action (see Context) — confirm with PM before
  scheduling; if declined, the other 6 steps are unaffected (no cross-step dependency).
- Step 7 changes catalog bookkeeping only; explicitly does NOT touch
  `.github/workflows/ci.yml`'s own `npm run test --workspaces --if-present` step — confirm
  this at implementation time so CI's actual execution path is unaffected.

## Source

Generated from `/aid-audit-tests --mode full` audit `TAUD-20260806-0440`'s write-plan
handoff (`.aid-o/work/test-audits/TAUD-20260806-0440/implementation-plan-brief.json`,
`durable-record.json`, verdict: `remediation recommended`). Revised once after a CP1-light
review (2026-08-08) found 3 factual mismatches against `consolidated-findings.json`/
`decision.json` and 2 template-completeness gaps; all corrected in this revision.
