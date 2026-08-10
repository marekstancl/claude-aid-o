---
id: P081
type: plan
status: draft
created: 2026-08-10
author: PM + AI
risk: high
---

# Plan: Test-Tier Pilot — Take the Full Suite Off the Merge Path

## Stakeholder Brief

AID runs its entire test portfolio — 191 suites, last timed at 12 200 s on a shared host — as part of closing every plan (`bats_all` is the `required: true` gate; the 191-suite `shell_pipeline_smoke` is `required: false` but sits in the release profile), and the process has five places that add tests and none that remove them. The published ecosystem standard fixes that with three tiers: a two-minute pulse, targeted tests that block merges, and the full suite running once a night where it delays nobody. This plan makes AID the pilot. Three grounded facts shaped it. First, tiers must be marked by a **header tag, not a directory**: moving suites into `tests/t0|t1|t2/` would break roughly 420 literal path references — 201 enforcement-registry rows, 468 catalog fields, every CI job and gate command — while a tag breaks none. Second, **no live per-suite timing exists**: the only measurement is a stale partial snapshot taken in a sibling worktree that still lists deleted suites, so the plan first wires the timing parser the repo already ships but never calls, then assigns tiers from real numbers rather than opinion. Third, the hoped-for simplification — deriving each suite's subject from its name and retiring the approval-gated mapping table — **does not work**: 119 of 191 suites (62 %) name a concept, not a file. The plan therefore keeps the existing selector and adds the standard's honesty check instead. Main risk: T1 becomes the only merge gate while the selector's live fallback maps just nine paths; the plan keeps the existing unverifiable-path escalation as the safety net and proves it.

## Context

Binding source: the ecosystem standard `/ecosystem/specs/test-standard` (`/opt/eco/docs/docs/ecosystem/specs/test-standard.md`, published 2026-08-10), which names AID as the pilot and says the pilot's reality feeds back into the document before WAN → ACTA → Sousto → AI-Agenti → VULCAN. Decision record: `.aid-o/work/interim-P081.md`. The PM cancelled the test-parallelism line on 2026-08-09 (IMP-469 rejected) and P078 removed the machinery in v2.82.0, so "make the suite faster" is off the table and "take the suite off the merge path" replaces it. Preconditions already met: `gate:bats_all` no longer carries a permanent red (IMP-494 resolved — one suite had phantom tests from heredoc'd fixtures, the other decided on the PM's workspace catalog); the portfolio is at its smallest (150 bats + 41 sh); `shell_pipeline_smoke` carries a measured 18 300 s cap and `run_mode: background` from P079's obligation, which this plan supersedes by removing the gate from the merge path entirely.

Grounding facts this plan stands on, all verified at `8470b13`: the tier-mechanism blast radius (directories ≈ 420 literal references vs a tag's zero); `lib/aid-test-timing-bats.sh` parses `bats --timing` TAP and has exactly ONE caller — `aid-test-audit-profile.sh` (:36 sources it, :137 gates on `bats_timing_supported`, :139 inserts `--timing`, :384 parses) — a per-unit diagnostic path, never the portfolio runner; that caller also carries the scar of a recorded `bash --timing -c` argv-slot bug and the argv-exactness guard at :184-201 that came out of it; the only per-suite durations are `.aid-o/work/test-audits/TAUD-20260806-0440/measurements.jsonl` — 66 records covering a partial subset of the portfolio, produced in a sibling worktree, still listing suites P078 deleted; `run-all-tests.sh` discovers with two flat globs and derives ledger unit-ids from paths; `DELEGATED_SUITES` is basename-keyed and consulted only inside the bats loop, so `.sh` suites cannot be delegated today; `aid-select-tests.sh` runs its **hardcoded nine-arm fallback** because `mapping_approval.status` is `proposed`, and an unmapped path inside the production surface exits 3 (`unverifiable`) or 11 (`mapping_gap`), which is what currently escalates to a full profile; `.github/workflows/` contains **no `schedule:` trigger at all**; `/opt/eco/services/scripts/lib/telegram-notify.sh` ships `send_telegram_alert`; `/aid-status`'s `render-overview` output is asserted byte-wise by `test-status-two-streams.bats`; and this repo's `CLAUDE.md` has no `## Conventions` section although the plugin's own generator template defines one.

## Goal

AID's merge path runs only cheap, targeted checks; the full portfolio runs once a night and reports itself; every suite declares a tier that was assigned from a measured duration; and the portfolio has a budget on the way in and a reaper on the way out.

## Scope

**In scope:**
- A per-suite timing pipeline: wire the shipped-but-uncalled `bats --timing` parser, add an equivalent for `.sh` suites, and emit durations into a refreshable record.
- A measured tier assignment for all 191 suites, recorded as a machine-readable header tag plus a lint that every suite carries one.
- Tier-aware execution: `execution.yaml` gate/profile changes so the merge path is T0 + T1 only, and `run-all-tests.sh` learns `--tier`.
- Nightly T2: a scheduled CI workflow, a result JSON, a Telegram report on red only with repeat-suppression, and the standard's reminder line in `/aid-status` and at plan start.
- The selector honesty check the standard requires (a T2 failure that the selector would not have picked for the last merge is a finding about the selector).
- Anti-bloat wiring: tier declaration required at plan-write time, the second review question, and the reaper's monthly candidate list fed by the existing content scanner.
- Renaming the six suites whose filenames carry plan numbers, and recording the tier convention in `CLAUDE.md` + contributor docs.

**Out of scope:**
- Any parallel execution (cancelled line; the nightly runs sequentially).
- Moving suites into tier directories — rejected on measured blast radius; recorded in the plan so the decision is not re-litigated.
- Replacing the catalog's mapping table with a name-derived convention — rejected on measured coverage (62 % unresolvable).
- Re-approving the workspace catalog's drifted `source_pattern_mappings` (IMP-492 / option A) — an independent PM act; this plan neither needs nor blocks it.
- Rolling the standard out to other projects — that follows the pilot.
- Rewriting the audit (`/aid-audit-tests`) or the catalog schema beyond an additive tier field.
- Enforcing the standard's naming rules 1 (name states the subject), 4 (one suite = one subject, split at ~500 lines) and 5 (mandatory header stating what the suite proves) — the tag, the plan-number ban and the tier lint land here; these three are **deferred to a follow-up** because they need a subject registry the pilot's own scope column will produce, and enforcing an unwritable rule on 191 files at once is the churn this plan exists to avoid.
- The standard's deployment rules (§Produkce a výjimky — green-nightly-≤24 h tag with a named exception) and cross-project ownership (§Mezi projekty) — **deferred, not dropped**: AID is not deployed, and cross-project ownership only becomes meaningful when a second project adopts the standard. Step 12 records the ownership line in `## Conventions` so the successor has an anchor.

## Approach

Chosen: **measure, then classify, then re-route** — in that order, because a tier assigned from opinion is the same defect the standard was written to prevent. The tier lives in a header tag so the portfolio does not move; the runner learns to filter by tier; only then does the merge path lose the full suite. Anti-bloat wiring lands last, when there is a real tier field for it to enforce.

Alternatives rejected with evidence: (a) **tier directories** — grounding counted ≈420 literal references that would need editing, including 201 enforcement-registry `test:` fields with line and grep anchors and ~468 catalog fields whose ids are join keys for the ledger, membership verification and receipts; the tag costs zero of those; (b) **name-derived subjects replacing the mapping table** — 119 of 191 suites resolve to no file, so the table cannot be retired; (c) **classifying from the existing measurement snapshot** — it covers only part of the portfolio, was taken in a sibling worktree, and lists suites that no longer exist; (d) **making the nightly job the same runner invocation as today** — that would keep `.sh` suites undelegatable and leave the tier filter unexpressed.

## Architecture

Four layers, each independently testable.

1. **Timing.** `lib/aid-test-timing-bats.sh` already parses per-test durations out of `bats --timing` TAP but nothing calls it. `run-all-tests.sh` gains an opt-in timing mode that invokes `bats --timing`, feeds that parser, and for `.sh` suites brackets each run with a millisecond stopwatch — the same technique `lib/aid-test-audit-measure.sh` uses. Output is one JSONL record per suite (`suite`, `runner`, `duration_ms`, `exit_code`, `at`) under the state root, appended, never overwritten, so tiers can be re-derived later without a special campaign.
2. **Classification.** A suite declares its tier in a header comment (`# aid-tier: t0|t1|t2`) — the one mechanism whose blast radius is zero. `lib/aid-test-tier.sh` is the single reader: it extracts the tag, and a companion linter asserts every discovered suite carries one and that the declared tier is consistent with the newest measured duration against the standard's thresholds (<2 s/case T0, <30 s/case T1, else T2). The catalog gains an additive `tier` field for units that have one; nothing existing is renumbered.
3. **Routing.** `run-all-tests.sh` gains `--tier <t0|t1|t2>` filtering on the tag, keeping its existing discovery globs, delegation map and ledger emission untouched. `execution.yaml` stops pointing the merge path at the whole portfolio: `bats_all` becomes the T0+T1 selection, `shell_pipeline_smoke` leaves every merge-path profile and becomes the nightly job's command. The nightly workflow is a new `schedule:`-triggered job — the repo has none today — that runs T2, writes the result JSON, and reports.
4. **Feedback.** Reporting has two independent surfaces so a missed message is recoverable: `send_telegram_alert` from the shared ecosystem helper on red only, with repeat suppression; and one rendered line in `/aid-status` plus the plan-start orientation read. Anti-bloat closes the loop at plan time (a Test bullet without a tier fails generation), at review time (the second question), and monthly (the reaper's candidate list, whose inputs the content scanner already computes).

## Implementation Steps

**EPIC 1: Steps 1-5 — Measure and classify**

### Step 1: Per-suite timing pipeline

**Objective:** Produce a refreshable per-suite duration record by giving the shipped timing parser a portfolio-wide caller, reusing the argv discipline its existing per-unit caller learned the hard way.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-test-audit-profile.sh` (lines ~130-200) — no behaviour change; extract its `--timing` argv-insertion and its one-token-diff guard into the shared lib below so the portfolio runner cannot re-introduce the `bash --timing -c` bug.
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~170-250) — add an opt-in `--timing` mode: for bats suites invoke `bats --timing` and pipe the TAP through `lib/aid-test-timing-bats.sh`; for `test-*.sh` suites bracket the run with a millisecond stopwatch (`date +%s%3N` before/after, the technique `lib/aid-test-audit-measure.sh` already uses); append one JSONL record per suite to the durations file; default behaviour without the flag is byte-identical.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-durations.sh` — sourceable reader/writer for the durations record: `aid_durations_append <suite> <runner> <duration_ms> <exit_code>` appends one line to `$(aid_state_root)/.aid-o/work/test-durations.jsonl`; `aid_durations_latest <suite>` folds the journal and prints the newest duration; refuses when the state root cannot resolve.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-durations.bats` — append then read back the newest record; two records for one suite yield the newer; unresolvable state root refuses loudly; a malformed line fails closed rather than reading as absent.

**Architecture Context:** Layer 1. The parser `lib/aid-test-timing-bats.sh` exists, is correct, and already has one caller — `aid-test-audit-profile.sh`, a per-unit diagnostic path. This step adds the PORTFOLIO caller instead of writing a second timing implementation, and inherits that caller's scar tissue: `--timing` must be inserted at the argv slot the runner actually executes (the recorded bug produced `bash --timing -c …` for shell-form commands) and the inserted token must be a checked one-token diff from the approved argv, per the guard at `aid-test-audit-profile.sh:184-201`. The journal lives in the state root for the same reason P079's obligations journal does: it must survive worktree teardown.

**Implementation Detail:** The timing flag is opt-in so every existing invocation (gates, CI, developers) keeps its current cost. Records are appended with `>>` in single sub-4 KB writes, matching the timeline journal precedent. `duration_ms` for a bats suite is the sum of its per-test durations from the parser when available, falling back to the wall-clock bracket when the TAP carries no timing (older bats); the record names which source it used so a later reader can tell a measured value from a bracketed one.

**Error Handling:** `bats --timing` unsupported by the installed bats version ⇒ fall back to the wall-clock bracket and record `source: wallclock`, never fail the run. An unwritable durations path ⇒ warn once and continue: timing is observational and must never break a test run.

**Edge Cases:**
- A suite that times out under the runner's own limit — the record carries its exit code and the partial duration, marked `censored: true`, so classification can refuse to tier it.
- A delegated suite — the five in `DELEGATED_SUITES` are skipped by the inline runner, so the measurement run invokes each of them DIRECTLY (outside the delegation filter) and records them like any other; a suite that still ends with no record is reported as unmeasured and never defaulted into a tier.
- Concurrent appends from two runs — single-line appends tolerate interleaving; the fold takes the newest by timestamp.

**Dependencies:**
- Depends on: none
- Blocks: Step 2 — classification needs real numbers.

**Acceptance Criteria:**
- [ ] `--timing` produces one record per executed suite with a non-null `duration_ms`; without the flag the runner's output and exit code are unchanged.
- [ ] Bats suites record `source: bats_timing` when the installed bats supports it, `wallclock` otherwise.
- [ ] All four bats cases pass, including the fail-closed malformed-line case.

**Effort:** M
**AID Role:** backend

### Step 2: Measure the portfolio and assign tiers from the numbers

**Objective:** Run the timing pipeline over the whole portfolio once and derive each suite's tier from its measured cost, not from opinion.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-test-tier-assign.sh` — reads the durations journal and the discovered suite list and applies BOTH halves of the standard's criterion. **Cost:** per case `<2 s` ⇒ t0 candidate, `<30 s` ⇒ t1 candidate, else t2. **Scope:** a suite whose subject cannot be resolved to an existing path (the grounded 119-of-191 class) is t2 regardless of cost, per the standard's rule that a test without a resolvable subject is cross-component. **Aggregate budgets:** after per-suite assignment it sums each tier and, while T0 exceeds 2 min or T1 exceeds 10 min, demotes the most expensive member and records the demotion with its reason — the standard forbids silent tolerance of an overflow. Output columns: suite, runner, subject (or `unresolvable`), measured ms, cases, ms/case, proposed tier, reason, demoted-from. Read-only: it proposes, it never edits a suite.
- Create: `docs/plans/P081-tier-assignment.md` — the checked-in assignment record produced by that run: the table, the measurement date and host, and an explicit list of suites with no measurement.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-tier-assign.bats` — a fixture journal plus a fixture suite list yields the expected tiers at each threshold boundary; a suite with no measurement is reported as `unmeasured`, never defaulted into a tier; a censored (timed-out) measurement is reported as `unmeasured` too.

**Architecture Context:** Layer 2's input half. The standard's rule is that tier follows measured cost and scope; this step supplies the measurement half mechanically so the human judgement is confined to scope (does the suite cross components) rather than to cost.

**Implementation Detail:** Cases per suite come from the TAP plan line for bats and from the durations record's own count for `.sh` (which has no case concept — treat the suite as one case). The tool prints its reasoning per row; the PM-visible artifact is the checked-in table, not the tool's stdout. The measurement run itself is one `run-all-tests.sh --timing` invocation recorded in the artifact with its host and date, since the standard forbids inheriting numbers from another machine or an old tree — the existing snapshot is explicitly not reused.

**Error Handling:** Fewer measurements than discovered suites ⇒ the table still prints, with the unmeasured ones listed separately and the count stated; the tool exits non-zero so a caller cannot mistake a partial table for a complete one.

**Edge Cases:**
- A suite whose per-case cost sits exactly on a threshold — the rule is `<`, so the boundary value falls into the more expensive tier; pinned by a bats case.
- The five delegated suites (two boundary + service + service-lifecycle + owned-jobs integration) are measured by the direct invocations Step 1 defines, not by the inline run; on cost alone they land in T2, which is where delegation already puts them.
- A suite that fails during the measurement run — its duration is still valid input; the tool records the exit code but classifies on time.

**Dependencies:**
- Depends on: Step 1 — consumes the journal.
- Blocks: Step 3 — the tags come from this table.

**Acceptance Criteria:**
- [ ] The assignment tool reproduces the checked-in table from the journal (re-running it yields the same tiers).
- [ ] Every one of the discovered suites appears exactly once, either with a tier or in the unmeasured list, and every row carries a subject value.
- [ ] The assigned T0 total is ≤ 2 min and the T1 total ≤ 10 min; every demotion forced by those budgets is listed with its reason.
- [ ] Every suite with an unresolvable subject is t2, whatever its measured cost.
- [ ] Threshold-boundary and unmeasured cases pass in bats.

**Effort:** M
**AID Role:** backend

### Step 3: Every suite declares its tier, and a linter enforces it

**Objective:** Stamp the assigned tier into each suite's header and make an undeclared or contradicted tier a blocking lint failure.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-test-tier.sh` — the single reader: `aid_test_tier_of <suite_path>` extracts `# aid-tier: <t0|t1|t2>` from the file's LEADING COMMENT BLOCK — the consecutive `#` lines following an optional shebang, however long (measured: eight bats suites and `test-cp1-gate.sh` carry headers of 40-47+ lines, so a fixed ten-line window would read them as untagged) — prints it, and prints nothing plus returns non-zero when absent; two tags anywhere in the file is a violation, never first-wins; `aid_test_tier_list <tier>` prints every discovered suite carrying that tier.
- Create: `plugins/aid-orchestrator/scripts/aid-test-tier-lint.sh` — asserts every discovered suite carries exactly one valid tag; asserts no suite filename contains a plan, EPIC or task number, matched CASE-INSENSITIVELY (`[Pp][0-9]+`, `[Ee]-[0-9]+`, `[Tt]-[0-9]+` — every live offender is lowercase, so an uppercase-only class would match none of them), with an allowlist file for sanctioned exceptions that this step SEEDS with the six current offenders so the tree is lint-clean before Step 4 renames them; asserts a declared tier is not cheaper than the newest measurement supports. Exit 0 clean, 1 violations, 2 usage.
- Modify: `plugins/aid-orchestrator/scripts/tests/` — every discovered suite (150 bats + 41 sh at plan time) gains exactly ONE `# aid-tier:` line per the Step 2 table, inserted as the FIRST line of the leading comment block (immediately after the shebang, before any existing header prose) so placement and the reader's scan rule cannot disagree; the step's own verification asserts the per-file diff is exactly one added line, since a whole-directory scope cannot otherwise distinguish a stamp from a rewrite.
- Create: `plugins/aid-orchestrator/scripts/tests/tier-lint-allowlist.txt` — the sanctioned filename exceptions, seeded with the six plan-numbered suites and emptied by Step 4.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-tier-lint.bats` — a fixture tree with a missing tag, an invalid value, a plan-numbered filename, an allowlisted filename and a tier cheaper than its measurement each produce the expected verdict; a clean tree exits 0.

**Architecture Context:** Layer 2's enforcement half, and the mechanism decision made concrete: the tag is why nothing moves. `lib/aid-test-tier.sh` is the one reader every later consumer uses (the runner's filter, the lint, the plan-time check), so the tier has exactly one authority — the same doctrine the parallel-status resolver had before it was removed.

**Implementation Detail:** The tag goes in a comment so both bats and shell suites carry it identically and no runner needs to parse a new file format. The lint's measurement cross-check reads through `lib/aid-test-durations.sh`, so a suite that grows past its tier's budget is caught the next time the durations journal is refreshed rather than silently staying cheap on paper.

**Error Handling:** A suite with two tags ⇒ violation naming both lines (never "first wins"). A tag with an unknown value ⇒ violation naming the accepted set. A suite with no measurement ⇒ the tag is accepted as declared and the row is reported as unverified, not failed — the standard's rule is that measurement moves a tier, and absence of measurement is not evidence of cheapness.

**Edge Cases:**
- Non-suite helpers in the tests directory (`run-all-tests.sh`, `verify-version-files.sh` and the three others) — the linter uses the runner's own discovery globs, so helpers are never asked for a tier.
- A fixture file under `scripts/tests/fixtures/` that happens to be named `test-*` — excluded by the same discovery rule.
- The allowlist file itself missing ⇒ treated as empty (no exceptions), never as "allow everything".

**Dependencies:**
- Depends on: Step 2 — the table is the source of the tags.
- Blocks: Step 4 — renaming happens once the lint exists to keep it true.

**Acceptance Criteria:**
- [ ] `aid-test-tier-lint.sh` exits 0 over the shipped tree with the six offenders allowlisted; removing an allowlist entry before Step 4 makes it exit 1 naming that file.
- [ ] Removing a tag from any suite makes it exit 1 naming that file; a suite whose leading comment block is 40+ lines is still read correctly.
- [ ] Every stamped file's diff is exactly one added line.
- [ ] All five fixture cases pass in bats.

**Effort:** L
**AID Role:** backend

### Step 4: Rename the six plan-numbered suites

**Objective:** No suite is named after the plan that produced it; each carries its subject instead.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-p073-integration.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-p074-integration.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-p076-integration.bats` — renamed to subject names (`test-force-framework-integration.bats`, `test-plan-worktree-integration.bats`, `test-owned-jobs-integration.bats`) with a header line recording the originating plan, so provenance survives outside the filename.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-p076-backlog-closure.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-p076-cp3-regressions.bats` + `plugins/aid-orchestrator/scripts/tests/bats/test-p076-docs-closure.bats` — renamed the same way (`test-deferred-work-registration.bats`, `test-owned-jobs-review-regressions.bats`, `test-owned-jobs-docs-closure.bats`).
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~150-165) — the `DELEGATED_SUITES` key for the renamed integration suite, plus its CI job name if the job is renamed with it.
- Modify: `.github/workflows/ci.yml` (lines ~160-180) — the delegated job's suite path for the renamed file.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — every `test:` field naming one of the six files.
- Test: `plugins/aid-orchestrator/scripts/tests/test-run-all-delegation.sh` — unchanged assertions must still pass, proving the delegation map and the CI jobs stayed in parity across the rename.

**Architecture Context:** The naming rule's one-off migration. It is small precisely because the grounding measured it: six files, not the sweeping rename the rule sounds like.

**Implementation Detail:** `git mv` preserves history, which the reaper's age signals depend on. Each renamed file gains one header line naming its originating plan, so the provenance the filename used to carry is not lost — it moves to where the standard says it belongs.

**Error Handling:** A reference discovered after the rename (registry row, doc, fixture) ⇒ the rename is incomplete; the step's own verification greps the whole tree for the six old basenames and must find zero outside CHANGELOG and archived plans.

**Edge Cases:**
- A renamed suite that is also delegated — the map key, the CI job's path and the registry row must move together; the delegation test is the mechanical proof.
- Historical references in `CHANGELOG.md` and `docs/plans/archive/` — deliberately left, they are records of what happened.
- The catalog's `run_unit_id` for a renamed suite — updated in the same step, since the id embeds the path.

**Dependencies:**
- Depends on: Step 3 — the lint that forbids plan numbers must exist before the tree is made to satisfy it.
- Blocks: none

**Acceptance Criteria:**
- [ ] `grep -rni "test-p07[346]-" plugins/ .github/ --include=* | grep -v CHANGELOG` returns nothing.
- [ ] The delegation parity test passes unchanged.
- [ ] `tier-lint-allowlist.txt` is EMPTY and `aid-test-tier-lint.sh` still exits 0 — the migration window is closed, not merely tolerated.

**Effort:** M
**AID Role:** backend

### Step 5: The runner filters by tier

**Objective:** `run-all-tests.sh` can execute exactly one tier, keeping its discovery, delegation and ledger behaviour intact.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/tests/run-all-tests.sh` (lines ~110-200) — add `--tier <t0|t1|t2>`: after discovery, filter the suite list through `lib/aid-test-tier.sh`; report skipped-by-tier counts the way delegated suites are already reported (never silently); `--list` gains a tier column; without the flag every suite runs exactly as today.
- Modify: `plugins/aid-orchestrator/scripts/tests/test-run-all-delegation.sh` — extend the `--list` parser for the new column and assert that tier filtering and delegation compose (a delegated T2 suite is reported once, not twice).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-run-all-tier-filter.bats` — a fixture tree with one suite per tier: `--tier t1` runs only the T1 suite and reports the others as skipped-by-tier; an untagged suite in the tree makes the run refuse (fail closed, pointing at the lint); no flag runs everything.

**Architecture Context:** Layer 3's runner half. Filtering happens after discovery so the existing globs, the empty-set guard and the ledger unit-id derivation are untouched — the grounding showed those are the parts a directory move would have broken.

**Implementation Detail:** Skipped-by-tier suites are counted and printed in the same summary block that already prints `DELEGATED:` lines, because a suite silently not running is the exact failure this whole plan exists to prevent. The refusal rule is stated ONCE and applies to both layers: the runner refuses an untagged suite **only when at least one suite in the tree already carries a tag** — a tiered project must stay tiered, while a project that has never adopted tiers (a fresh consumer) runs everything exactly as today. Inside a tiered tree, defaulting is how a portfolio drifts back into "everything is cheap", so there the refusal is absolute.

**Error Handling:** `--tier` with an unknown value ⇒ usage error, exit 2. Tier filter selecting zero suites ⇒ report it and exit 0 (an empty tier is a legitimate state), unlike the existing empty-discovery guard which stays a hard failure.

**Edge Cases:**
- A delegated suite that also matches the requested tier — delegation wins (it runs in its own job), reported once under `DELEGATED:`.
- `--tier t2` on a tree where every T2 suite is delegated — zero inline suites, reported, exit 0.
- `--tier` combined with `--list` — lists without running, tier column populated.

**Dependencies:**
- Depends on: Step 3 — needs the tag reader.
- Blocks: Step 6 — the gates call the filtered runner.

**Acceptance Criteria:**
- [ ] `--tier t1` runs only T1 suites; skipped-by-tier counts appear in the summary.
- [ ] An untagged suite makes the run refuse with a message naming the file and the lint.
- [ ] Existing invocations without `--tier` are unchanged (delegation test still passes).

**Effort:** M
**AID Role:** backend

**EPIC 2: Steps 6-9 — Re-route the merge path and build the nightly**

### Step 6: The merge path loses the full suite

**Objective:** Merge-path gate profiles run T0 and T1 only; the full portfolio stops being a precondition for closing anything.

**Files:**
- Modify: `.aid-o/config/execution.yaml` (lines ~1-260) — `bats_all` becomes a T0+T1 invocation (`run-all-tests.sh --tier` calls, replacing the `ls | grep -v` glob); `shell_pipeline_smoke` is removed from every merge-path profile and retained only as the nightly command, with its P079 cap and `run_mode: background` comment updated to say the gate no longer sits on the merge path; the `quick`, `targeted`, `standard`, `full`, `release`, `bats_all_quarantine`, `release_quarantine` and **`p064-closure`** profiles are re-pointed accordingly — all eight the file defines, not the five the first draft named.
- Modify: `plugins/aid-orchestrator/defaults/execution.yaml` (lines ~40-140) — the shipped template gains the same shape so consumer projects inherit tiers rather than the old whole-portfolio gate; the commented consumer example shows a tier-filtered invocation.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-fsm.sh` (lines ~4270-4300) — `_pfsm_profile_include` and the plan-final `--stage gates` set-equality assertion between `release_quarantine` and `release` (execution.yaml:360-364 records that it refuses to run otherwise) are updated together with the profiles, so the boundary cannot refuse on a set the same commit rewrote.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-tier-gate-routing.bats` — every merge-path profile resolves to gates whose commands invoke only `--tier t0` or `--tier t1`; no merge-path profile references `shell_pipeline_smoke`; the nightly command is exactly the T2 invocation; and the plan-final set-equality assertion still holds for the rewritten `release`/`release_quarantine` pair.

**Architecture Context:** Layer 3's configuration half — the step where the 3 h 23 min actually leaves the merge path. Profiles keep their existing rank order and names; only their contents change.

**Implementation Detail:** `bats_all`'s current command is a glob with a negative filename filter that hardcodes the two boundary suites; tier filtering plus the existing delegation map expresses the same partition declaratively, so the negative filter is removed rather than translated. The gate keeps its name so every profile, registry row and historical baseline that references it stays valid.

**Error Handling:** A profile that would end up with no gates ⇒ the step fails at authoring time; an empty merge-path profile is a silent no-gate merge, which is worse than a slow one.

**Edge Cases:**
- `targeted_tests` (the selector-driven gate) is unchanged — it is already T1-shaped and stays on the merge path.
- The quarantine profiles (`bats_all_quarantine`, `release_quarantine`) — re-pointed the same way, keeping their quarantine semantics.
- A consumer project with no tiers yet — degradation is the single rule stated in Step 5 (refuse only inside an already-tiered tree), so the template's tier-filtered command runs everything and `/aid-init` upgrades do not break an untiered project; the two layers do not carry two rules.

**Dependencies:**
- Depends on: Step 5 — the gates call the filtered runner.
- Blocks: Step 7 — the nightly runs what the merge path stopped running.

**Acceptance Criteria:**
- [ ] No merge-path profile includes `shell_pipeline_smoke`.
- [ ] Every merge-path gate command names a tier filter.
- [ ] The routing bats suite passes, including the untiered-consumer degradation case.

**Effort:** M
**AID Role:** backend

### Step 7: The nightly job

**Objective:** The full portfolio runs once a night in CI, records a result artifact, and reports itself.

**Files:**
- Create: `.github/workflows/nightly-tests.yml` — a `schedule:`-triggered workflow (the repo has none today) running `run-all-tests.sh --tier t2 --timing` on the self-hosted runner at AID's allotted hour, plus `workflow_dispatch` for manual runs; writes the result artifact and calls the reporter; generous timeout since it blocks nobody.
- Create: `plugins/aid-orchestrator/scripts/aid-nightly-report.sh` — reads the runner's output and the durations journal and writes the result to a **shared host path outside any checkout**: `${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}/<date>.json` plus a `latest.json` pointer. The transport is deliberate: the CI job runs in the self-hosted runner's own `_work` checkout, `aid_state_root()` resolves to whatever `$PWD`'s git root is, and `.gitignore:98` ignores `**/.aid-o/`, so an artifact written under `.aid-o/` inside CI can never be read from the PM's checkout — the standard's mandatory second surface would render nothing forever and look identical to a healthy fresh project. Fields: `date`, `suites_run`, `passed`, `failed[]`, `flaky[]`, `quarantined[]`, `duration_ms`, `log_url`, `notified`. **Flaky handling per the standard:** a suite that fails and then passes on exactly one retry is recorded as `flaky`, the run continues, and the suite is written into the quarantine record below rather than counted as a failure; and on red calls `send_telegram_alert` from `/opt/eco/services/scripts/lib/telegram-notify.sh` — but only for failures not already reported with an owner, printing `N. night in a row` for known ones.
- Create: `plugins/aid-orchestrator/scripts/aid-test-quarantine.sh` — the flaky-quarantine record the standard requires: `quarantine add <suite> <owner> ` stamps an entry with its date, `quarantine list` prints open entries with their age, `quarantine close <suite> <fixed|deleted>` retires one. A quarantined suite does not block a merge, appears in every nightly report with its age, and past 14 days without an owner escalates exactly like a red streak.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-nightly-report.bats` — a green run writes the artifact and sends nothing; a red run sends once and records the failure; a second red night with the same failing suite counts instead of re-sending; a fail-then-pass-on-retry suite is recorded as flaky and quarantined, not as a failure; the quarantine count appears in every report; an entry past 14 days without an owner escalates; a missing Telegram helper degrades to a warning without failing the job.

**Architecture Context:** Layer 4's producer. The report is a file first and a message second, so a lost Telegram message never means a lost result — the standard requires the second surface for exactly that reason.

**Implementation Detail:** The nightly hour is AID's alone; the standard requires per-project stagger because one self-hosted runner cannot carry six portfolios at once, and the grounding confirms all bash jobs share that host. `--timing` runs in the nightly so the durations journal refreshes without a special campaign, which is what keeps tier assignments honest over time.

**Error Handling:** Telegram credentials unconfigured ⇒ `send_telegram_alert` already returns 2 silently; the reporter records `notified: false` in the artifact so the miss is visible in the file. The runner crashing outright ⇒ the artifact still records the failure with the exit code, never an absent file.

**Edge Cases:**
- The first ever run (no previous artifact) ⇒ every failure is new; the streak counter starts at 1.
- A failing suite that was renamed since the previous night ⇒ treated as new, not as a continued streak.
- A run that times out at the workflow level ⇒ the artifact is written by the reporter step with `censored: true` if the runner produced partial output, else the job's own failure is the record.

**Dependencies:**
- Depends on: Step 6 — the nightly runs the tier the merge path shed.
- Blocks: Step 8 — the reminder reads this artifact.

**Acceptance Criteria:**
- [ ] A green fixture run writes the artifact and sends no message; a red one sends exactly one.
- [ ] A repeated known failure increments a streak instead of re-sending; a fail-then-pass-on-retry suite is recorded flaky and quarantined, and the quarantine count appears in the report.
- [ ] The workflow declares a `schedule:` trigger and `workflow_dispatch`, and the artifact lands under the shared host path, not under any `.aid-o/`.

**Effort:** L
**AID Role:** backend

### Step 8: The result is impossible to miss

**Objective:** The last nightly result is stated where work starts, so a red night surfaces even if the message is missed.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (lines ~330-900) — the `state-root` recipe family gains a `nightly-line` recipe reading `${AID_NIGHTLY_DIR:-/opt/eco/data/aid-nightly/aid-orchestrator}/latest.json` — the shared host path Step 7 writes, NOT a `.aid-o/` path, which no CI job can reach — and `render-overview` prints one line: green with its date, or red with the failing count, the streak and the artifact path; absent artifact prints nothing at all.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-status-two-streams.bats` — the byte-asserted overview fixture gains the nightly line, since the rendered example in the command file is asserted by this suite.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` (lines ~60-105) — the orientation reads gain the nightly check, with the same one-line report and an explicit rule that it never blocks planning.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-nightly-reminder.bats` — green, red-with-streak, quarantine-count and absent-artifact fixtures each render the expected single line (or nothing), and none of them changes any other overview row; plus ONE non-fixture case: a real `workflow_dispatch` nightly run's artifact is read by `/aid-status` from the PM's checkout, proving the transport end to end rather than proving the renderer against a file the test itself wrote.

**Architecture Context:** Layer 4's second surface. The grounding established that `/aid-status`'s rendered example is byte-asserted by an existing suite, so the fixture must move with the renderer — that coupling is the reason this is its own step rather than a footnote in Step 7.

**Implementation Detail:** The line is derived, never authored: the renderer reads the artifact and states what it says, including "not run since <date>" when the newest artifact is older than two days — a nightly that silently stopped running is itself a failure the standard wants visible.

**Error Handling:** A malformed artifact ⇒ render one honest line saying the result is unreadable and naming the path, never a fabricated verdict and never silence.

**Edge Cases:**
- No `.aid-o/work/nightly/` at all (fresh project) ⇒ nothing rendered; a project without a nightly is not in a red state.
- A nightly older than two days ⇒ rendered as stale with its age.
- Invocation from a plan worktree ⇒ the artifact resolves through the state root like every other status read.

**Dependencies:**
- Depends on: Step 7 — reads its artifact.
- Blocks: none

**Acceptance Criteria:**
- [ ] All fixture states render exactly one line (or none) and leave other rows untouched; the quarantine count appears when the record is non-empty.
- [ ] The end-to-end case passes: an artifact produced by a real CI run is rendered by `/aid-status` in the PM's checkout.
- [ ] The byte-asserted overview fixture passes with the new line.
- [ ] A stale artifact renders its age.

**Effort:** M
**AID Role:** backend

### Step 9: The selector's honesty check

**Objective:** A nightly failure that the merge-path selector would not have chosen becomes a finding about the selector, not just about the test.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-selector-honesty-check.sh` — for each failing suite in the newest nightly artifact, replay `aid-select-tests.sh` against the last merge's changed paths and report whether that suite would have been selected; emits `<nightly dir>/<date>-selector-gaps.json` listing misses with the changed paths that should have reached them, in THREE classes: `unmapped` (the selector picked nothing for the path), **`mapped_but_thin`** (the selector picked a suite, exited 0, and the suite that actually failed was not among them — the class that matters most after the merge path narrows, because the exit-3/11 escalation is structurally unreachable for a mapped path), and `unmappable` (a cross-cutting invariant no path could ever select).
- Modify: `.github/workflows/nightly-tests.yml` — run the honesty check after the report and attach its output; a miss is reported, never a job failure.
- Modify: `plugins/aid-orchestrator/scripts/aid-nightly-report.sh` — the Telegram line names the number of selector gaps when there are any, because a selector gap is more urgent than the test failure that revealed it.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-selector-honesty-check.bats` — a failing suite the selector would have picked yields no gap; one it would have missed yields an `unmapped` gap naming the path; a change that the selector mapped to a DIFFERENT suite than the one that failed yields a `mapped_but_thin` gap; the selector's `unverifiable` exit (its safety net) counts as selected, not as a gap.

**Architecture Context:** The standard's rule that a selector nobody can trust is worse than none. The grounding matters here: the live selector runs a nine-arm hardcoded fallback because the catalog mapping is unapproved, so gaps are expected at first — the check's value is making them countable instead of invisible.

**Implementation Detail:** "The last merge's changed paths" comes from the merge commit's diff against its first parent. The `unverifiable` (exit 3) and `mapping_gap` (exit 11) outcomes are treated as selection, because both escalate to a fuller profile today — counting them as misses would manufacture false gaps.

**Error Handling:** No merge since the previous nightly ⇒ the check reports "no merge to evaluate" and writes an empty gap list, never an error.

**Edge Cases:**
- A failing suite that is delegated (ran in its own CI job) ⇒ still evaluated, since selection is about the merge path, not about where it ran.
- Multiple merges since the last nightly ⇒ the union of their changed paths is used.
- A failing suite with no subject the selector could ever map (a cross-cutting invariant) ⇒ reported as `unmappable`, a distinct outcome from a gap.

**Dependencies:**
- Depends on: Step 7 — consumes the nightly artifact.
- Blocks: none

**Acceptance Criteria:**
- [ ] A would-have-been-selected failure produces no gap; a missed one names the path; a mapped-but-thin miss is reported in its own class, not as a pass.
- [ ] `unverifiable`/`mapping_gap` outcomes never count as gaps.
- [ ] The nightly workflow attaches the gap file and never fails on a gap.

**Effort:** M
**AID Role:** backend

**EPIC 3: Steps 10-13 — Budget in, reaper out, and release**

### Step 10: A test cannot be planned without a tier

**Objective:** Plan-time work declares its tier, so the portfolio cannot grow untiered.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/plan-writing.md` (lines ~250-470) — the per-step template's Files grammar gains the rule that a `Test:` bullet naming a new suite must state its tier, and the mandatory-fields table gains the tier requirement with the standard's thresholds and the "into T2 only with a stated reason" rule.
- Modify: `plugins/aid-orchestrator/scripts/lib/aid-scoping.sh` (lines ~120-230) — the Files-bullet classifier recognises an optional trailing tier declaration on a `Test:` bullet and exposes it, so generation can refuse a new-suite bullet that lacks one.
- Modify: `plugins/aid-orchestrator/scripts/aid-plan-to-epic.sh` (lines ~980-1030) — a `Test:` bullet naming a path that does not yet exist and carries no tier stops generation with the same loud message class P079 introduced for dropped bullets.
- Test: `plugins/aid-orchestrator/scripts/tests/test-epic-to-json-regression.sh` — a new-suite Test bullet without a tier fails generation naming the step; with a tier it generates; an existing-suite bullet needs no tier.

**Architecture Context:** The budget on the way in. It reuses the Files-grammar authority (`lib/aid-scoping.sh`) rather than adding a second parser, and the refusal shape P079 already established, so authors meet one rule and one error style.

**Implementation Detail:** Only NEW suites need a declaration — a Test bullet pointing at an existing file inherits that file's tag, which the lint already guards. This keeps the rule cheap for the common case (adding a case to an existing suite), which is also the behaviour the standard wants to encourage.

**Error Handling:** A tier declaration naming an unknown value ⇒ refusal naming the accepted set, at generation, not at run time.

**Edge Cases:**
- A Test bullet for a fixture rather than a suite ⇒ not a suite path by the discovery rule, no tier required.
- A plan that renames an existing suite ⇒ existing tag moves with the file; no declaration required.
- Consumer projects with no tiers ⇒ the check activates only when the project's own config declares a tier mechanism, so an untiered project generates exactly as today.

**Dependencies:**
- Depends on: Step 3 — the tier vocabulary must exist.
- Blocks: Step 12 — the registry records this enforcement.

**Acceptance Criteria:**
- [ ] Generation refuses a new-suite Test bullet without a tier, naming the step.
- [ ] An existing-suite bullet still generates untouched.
- [ ] The regression harness passes with all three cases.

**Effort:** M
**AID Role:** backend

### Step 11: Review asks the second question, and the reaper gets its list

**Objective:** Review can find an unnecessary test, and once a month the portfolio proposes what to delete.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/review-checkpoint-contracts.md` (lines ~60-200) — CP2 and CP3 gain the second mandatory question ("is each added test the cheapest sufficient proof — does an existing test already cover it?"), with the standard's rule that a redundant test is a finding of the same weight as a missing one, and the explicit guard that "it is probably covered somewhere" without naming the covering test is not a valid answer.
- Create: `plugins/aid-orchestrator/scripts/aid-test-reaper.sh` — assembles the monthly candidate list from three inputs that exist (the content scanner's vacuous-green and duplicate findings, and the durations journal for cost) and one that does NOT: the standard's fourth input, age since the last real failure, has no source in the tree — `git log --follow` gives CHANGE age, not failure age, and no per-suite failure history exists anywhere. The nightly journal accumulates exit codes from this plan onward, so that input is DEGRADED AT FIRST and the tool names it as unavailable rather than proposing from three while implying four. It prints a table with a reason per candidate and writes it beside the nightly artifact. It proposes only — deletion is a normal PR.
- Modify: `plugins/aid-orchestrator/scripts/aid-nightly-report.sh` — on the month's first run, attach the reaper list to the report.
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-reaper.bats` — a vacuous suite, a duplicate pair and an expensive never-failing suite each appear with their reason; a suite with a recent real failure never appears; the list is empty-safe.

**Architecture Context:** The reaper on the way out. Three of the standard's four inputs exist (the content scanner's vacuous-green and duplicate checks from P079, and Step 1's durations journal), so this step is mostly assembly; the fourth — failure age — starts empty and fills as nightlies accumulate, which the tool says out loud.

**Implementation Detail:** No quota: the tool never targets a count, and each row carries its own reason so the PM approves individually. Age is read with `git log --follow` so a renamed suite keeps its history, closing the "rename to reset the signal" gaming path the standard names.

**Error Handling:** A missing content-scan artifact ⇒ the list is produced from the remaining inputs and says which input was unavailable, rather than silently proposing less.

**Edge Cases:**
- A suite that is both vacuous and expensive ⇒ one row, both reasons.
- Failure-age unavailable (no nightly history yet) ⇒ the list is produced from the three live inputs and names the missing one, never silently implying full coverage.
- A newly added suite with no history ⇒ never a candidate (nothing to judge yet).
- The first month with no previous list ⇒ full list, marked as the first run.

**Dependencies:**
- Depends on: Step 1, Step 7 — consumes the durations journal and rides the nightly report.
- Blocks: Step 12.

**Acceptance Criteria:**
- [ ] Each candidate class appears with its reason; a recently-failing suite never appears.
- [ ] The tool proposes only — it performs no deletion (verified by the absence of any removal operation in the script).
- [ ] Review contracts contain the second question and the invalid-answer guard.

**Effort:** M
**AID Role:** backend

### Step 12: Conventions, contributor docs and the registry

**Objective:** The tier rule is written where authors read, and every new mechanical check is registered.

**Files:**
- Modify: `CLAUDE.md` (lines ~155-200) — a `## Conventions` section (the repo has none, although the plugin's own generator template defines one) recording AID's chosen tier mechanism, the header-tag syntax, the naming rule and the thresholds, with a pointer to the ecosystem standard as the binding source.
- Modify: `docs/extending-aid.md` (lines ~1267-1340) — a "Test tiers (P081)" section: how to choose a tier, how the tag is read, what the nightly does, how the reaper works, and the "Adding to this area" note the file's convention requires.
- Modify: `plugins/aid-orchestrator/scripts/README.md` (lines ~666-720) — the Testing section gains the tier rule, the `--tier` and `--timing` options (its options table is stale — it lists neither `--list` nor these), and the placement rule.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — new rows for the tier lint, the runner's untagged refusal, the plan-time tier requirement and the selector honesty check, each with source, instruction, severity, surface and test; totals recomputed by the file's own command.
- Test: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-test-audit.sh` — extended `REQUIRED_IDS` covering the new rows, with their source citations resolving to real files.

**Architecture Context:** The mandate from `CLAUDE.md` that every detection capability is registered, executed once at the end when all four mechanisms exist.

**Implementation Detail:** The registry rows follow the block style used for prose-heavy entries; source fields name real post-implementation paths, since the registry test resolves them.

**Error Handling:** Totals mismatch ⇒ the registry tests fail in this step's own verification, before release.

**Edge Cases:**
- A row whose `test:` field names a suite this plan renames ⇒ updated in Step 4, re-verified here.
- The `## Conventions` section colliding with a future `/aid-setup` generator run ⇒ the section is written in the generator's own shape so a regeneration merges rather than duplicates.
- Another session editing the registry concurrently ⇒ ids are unique and additive; the totals command is re-run at merge.

**Dependencies:**
- Depends on: Step 3, Step 5, Step 9, Step 10, Step 11 — registers and documents what they built.
- Blocks: Step 13.

**Acceptance Criteria:**
- [ ] Registry tests pass with the new rows and recomputed totals.
- [ ] `CLAUDE.md` states the tier mechanism, syntax, thresholds and the standard's URL.
- [ ] The scripts README documents `--tier`, `--timing` and `--list`.

**Effort:** M
**AID Role:** docs-writer

### Step 13: Release and feed the standard back

**Objective:** Ship the pilot and record what the pilot taught, as the standard requires before any other project adopts it.

**Files:**
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — one identical entry per the repo format (Added: timing pipeline, tier tags and lint, tier-filtered runner, nightly workflow and report, selector honesty check, reaper; Changed: merge path no longer runs the full portfolio, six suites renamed to their subjects; Fixed: none claimed unless the measurement run surfaced one).
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — the remaining version-registry locations per the eight-location table, with the roadmap line updated.
- Create: `docs/plans/P081-pilot-feedback.md` — what the pilot changed about the standard: the measured merge-path duration before and after, how many suites landed in each tier, which standard rules proved unworkable or needed wording changes, and the concrete edits to make to `/ecosystem/specs/test-standard` before WAN adopts it.
- Test: `plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` — full pass including the CHANGELOG byte-identity assertion P079 added.

**Architecture Context:** The standard says the pilot's reality feeds back into the document before the next project. This step produces that feedback as a checked-in artifact rather than a memory.

**Implementation Detail:** The before/after merge-path duration is measured, not estimated: the same gate profile timed once before Step 6 and once after, both recorded in the feedback document. The version is read from the actual head at implementation time.

**Error Handling:** A version-location mismatch blocks the push under the existing pre-push discipline; the release runs through the sealed path P079 built, so the previous tagged heading cannot be retitled.

**Edge Cases:**
- Another plan releasing between this plan's start and its release ⇒ bump from the actual current version.
- The measurement showing the merge path did not get materially faster ⇒ the feedback document says so plainly; the pilot's honesty is the deliverable, not a target number.
- A standard rule the pilot could not implement ⇒ recorded as a proposed standard amendment, not silently skipped.

**Dependencies:**
- Depends on: Step 12 — releases what it documented.
- Blocks: none — terminal step.

**Acceptance Criteria:**
- [ ] All eight version locations agree; both CHANGELOG entries byte-identical.
- [ ] The feedback document records before/after merge-path duration and the per-tier counts.
- [ ] One `workflow_dispatch` T2 run under the NEW configuration completed and its result is recorded — the tier partition this plan invents is proven green across the full portfolio before release, not after.
- [ ] Every standard rule is marked implemented, amended or deferred with a reason.

**Effort:** M
**AID Role:** release

## Testing Strategy

- Every new script ships its own bats suite, and **each step that creates a suite carries the tag in the same edit** — from Step 5 onward the runner refuses any run containing an untagged suite, so an untagged new suite would brick every gate invocation in this plan's own execution. Each such step's acceptance criteria assert the tag.
- The two migration steps (3 and 4) are proved by mechanical greps in their acceptance criteria, not by inspection.
- The runner changes are guarded by the existing delegation parity test plus a new tier-filter suite, so discovery, delegation and tier filtering are proved to compose.
- The nightly and reminder steps are fixture-driven; no test depends on a real scheduled run.
- Per the standard, no full-portfolio run is required to close this plan — the plan's own merge path is T0+T1 from Step 6 onward, and the full run happens that night.

## Constraints

- No parallel execution anywhere; the nightly runs sequentially (cancelled line, IMP-469).
- Tier is decided by measured cost and scope, never by importance, and never chosen to avoid blocking.
- The tag mechanism is fixed by measured blast radius; a later move to directories would need its own plan and a new count.
- Frozen surfaces: catalog `run_unit_id` values (except the six renamed suites), ledger schema, evidence filenames, and `/aid-status`'s existing rendered rows.
- No new runtime dependency: bash, jq, yq, awk, git, bats.
- The nightly runs on the shared self-hosted runner at AID's own hour; other projects get different hours when they adopt.
- Language: plan and code in English, PM conversation in Czech.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| T1 misses a regression the full suite would have caught | Medium | High | The selector's `unverifiable`/`mapping_gap` escalation stays; the nightly plus the honesty check make every miss countable |
| Tier tags drift from real cost as suites grow | Medium | Medium | The nightly refreshes the durations journal; the lint fails a tier cheaper than its newest measurement |
| The measurement run itself is unrepresentative (shared host contention) | Medium | Medium | Host and date recorded in the assignment artifact; boundary cases tier upward; re-derivable from any later nightly |
| Renaming breaks a reference the greps miss | Low | High | Step 4's own verification greps the whole tree; the delegation parity test is mechanical |
| Nightly noise causes alert fatigue | Medium | Medium | Red-only, repeat-suppressed with streak counting, and a second surface in `/aid-status` so a muted channel is not a lost result |
| The plan's own portfolio changes invalidate the P079 gate cap comment | Low | Low | Step 6 updates that comment as part of re-pointing the gate |

## Success Criteria

1. Closing a plan no longer runs the full portfolio; the merge path is T0 + T1 and its duration is measured before and after.
2. Every suite carries a tier tag that a linter enforces and that a measurement can contradict.
3. The full portfolio runs nightly, writes a durable result, and reports red once with a streak — with a second surface that survives a missed message.
4. A nightly failure the merge-path selector would have missed is reported as a selector gap.
5. A new suite cannot be planned without a tier, and once a month the portfolio proposes what to delete without a quota.
6. The pilot's feedback into the ecosystem standard is a checked-in document, not a memory.

## Acceptance Criteria

- [ ] AC1 — Tier tags are complete and enforced.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/aid-test-tier-lint.sh"
  expected_exit: 0
```
- [ ] AC2 — The runner filters by tier and refuses untagged suites.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-run-all-tier-filter.bats"
  expected_exit: 0
```
- [ ] AC3 — No merge-path profile runs the full portfolio.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-tier-gate-routing.bats"
  expected_exit: 0
```
- [ ] AC4 — The nightly report is green-silent, red-once, streak-counting.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-nightly-report.bats"
  expected_exit: 0
```
- [ ] AC5 — The reminder renders exactly one line in each state.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-nightly-reminder.bats"
  expected_exit: 0
```
- [ ] AC6 — Selector gaps are detected and never manufactured.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-selector-honesty-check.bats"
  expected_exit: 0
```
- [ ] AC7 — A new suite cannot be planned without a tier.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-epic-to-json-regression.sh"
  expected_exit: 0
```
- [ ] AC8 — The reaper proposes with reasons and never deletes.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-test-reaper.bats"
  expected_exit: 0
```
- [ ] AC9 — No suite filename carries a plan number.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! ls plugins/aid-orchestrator/scripts/tests/bats/ plugins/aid-orchestrator/scripts/tests/ | grep -qE \"test-(p|e-|t-)[0-9]+\"'"
  expected_exit: 0
```

## Next Steps

1. `aid-plan-lint.sh` + `aid-generation-readiness.sh --total 3`; repair diagnostics.
2. CP1 verifier with the evidence protocol; risk high ⇒ CP1-deep + C0 Codex loop at generation time, standing budget 5 then PM force.
3. Implement after PM approval; the measurement run in Step 2 is the long pole and should start early in EPIC 1.
4. Feed `docs/plans/P081-pilot-feedback.md` into `/ecosystem/specs/test-standard` before WAN adopts it.
