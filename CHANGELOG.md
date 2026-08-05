# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [2.71.0] — 2026-08-05

> Until now the audit classified, measured and proved — and then told the owner
> "fix" with no object. The analysts were required to record every resource with
> file:line and forbidden from concluding anything with it: their instructions
> allowed exactly two endings, a lane or a measurement. This release adds the
> third ending the whole exercise was for.

### Added
- **Findings carry concrete remediation proposals** — the exact change with file:line ("a.bats:359 writes under a fixed path; allocate a per-test temp dir"), an effort bucket built from counted facts (S/M/L/decision-required, with a separate verify bucket, because a delete is S to perform and L to verify and the verify cost is the one that decides), and a benefit that is measured, extrapolated, estimated or **unknown** — unknown being a normal answer an honest audit gives often. Time benefits count only on the critical path: 30s saved beside a 5-minute serial test saves nothing.
- **Both directions, not just subtraction** — an audit that can only shrink a suite monotonically degrades safety. New recommendation values: `add` (a missing error-path test — benefit is risk, not seconds), `strengthen` (a weak oracle gets a real assertion instead of deletion), `rewire` (a gate that runs a unit twice, a unit no gate runs, a timeout below real runtime).
- **Guards on everything destructive** — remove/merge are always decision-required; "asserts nothing" must survive checking exit-code semantics and custom helpers; a duplication claim must name its basis, never file-name similarity; a test born in a bugfix commit is presumptively load-bearing; the adversarial wave now verifies proposals like findings and flags a confident number whose evidence tier cannot support it.
- **Proposals have identity and memory** — a stable `proposal_id`, a declined ledger (`.aid-o/config/test-audit-decisions.yaml`) so a declined proposal is marked and never re-litigated, and `conflicts_with` cross-references on both sides of contradicting advice ("share the setup" vs "isolate per test"), computed as well as declared.
- **The proposals reach the artifacts people read** — findings' proposals become `decision.json` actions (a bare verb without a proposal deliberately does not), ride into the remediation brief the plan is generated from, and render as a ranked, capped list — the artifact keeps everything, the render shows the top slice, because an audit emitting four hundred proposals has produced zero.

## [2.70.8] — 2026-08-05

### Changed
- **The audit now offers the catalog approval instead of leaving it on the floor** — it produces a proposed catalog and, by design, never writes the approved one; that boundary is right, because the catalog is an execution allowlist. What was wrong is that finishing the job then required knowing two script names. The controller now says what the catalog holds, asks whether to approve it, runs both steps on a plain yes, and names anything the approval would revoke before asking. Only then does it offer the remediation plan — first make the tests run right, then decide what to fix.

## [2.70.7] — 2026-08-05

> The audit could prove which tests are safe to run side by side, and had no way
> to write that down. The proof landed in `decision.json` and the catalog — the
> file every consumer reads — came out with every unit `unknown` regardless.

### Added
- **`aid-test-catalog-apply-evidence.sh` — the missing link between what the audit proves and what the catalog says.** It promotes the units of every `proposed_parallel` lane to `parallel.status: safe`, bound to the content they were verified against, and carries forward evidence the previously approved catalog already held for units whose content has not moved. Carrying forward is safe by construction: every entry is bound to a source hash and a resource digest, so anything whose file changed fails its own binding and reverts to `unknown` with no list to maintain. It runs automatically at the end of every full audit; before this, the only path from evidence to catalog was a one-shot migration written for P071's text allowlist, and everything else was manual.

### Changed
- **A bare `/aid-audit-tests` asks instead of assuming** — it used to fall back to `static`, which answers a different question than the one most people are asking, while `full` refused to start without a budget nobody remembers. The controller now offers the recommended run (full, 180 minutes) in one sentence and accepts a plain yes. Explicit arguments still win.

## [2.70.6] — 2026-08-05

> Found by a real full audit of this repository: 174 run units and 158 447 bytes
> of findings were enough to kill the only mandatory closing step, so a
> completed audit produced no decision artifact at all.

### Fixed
- **Consolidation died on any portfolio big enough to matter** — `--argjson` puts a whole JSON value in ONE command-line argument, and Linux caps a single argument at 128 KB (`MAX_ARG_STRLEN`) no matter how large `ARG_MAX` is. The findings set, the aggregated resource maps, the pilots, the inventory, the keep/rewrite/remove sets, the lanes and the profile actions all scale with the portfolio and all went through argv, so `aid-test-audit-consolidate.sh` failed with "Argument list too long" — and because it is the only mandatory closing step and fails closed, the audit ended with nothing. Every value that grows with the portfolio is now read from a file. This is the same defect fixed in `aid-test-resource-map.sh` in 2.70.2 and not swept for at the time; the regression test builds a 226 KB artifact, and its own fixture hit the limit first, which is a fair measure of how easy it is to reach.

## [2.70.5] — 2026-08-05

### Fixed
- **An audit that loses its own evidence now survives it** — a real full audit had its entire output tree deleted during a cost-profiling run: inventory, catalog, eight agent artifacts, measurements, 112 resource maps, and finalize then had nothing to read. 2.70.3 reduced the exposure and added a detector, but detecting a loss still costs the operator the run. The tree is now copied before the profiled command starts and restored if anything disappears, so the audit keeps its evidence and continues; the receipt records `evidence_loss_restored` so a restored run is never mistaken for a quiet one. **The cause of the deletion is still not identified** — every `rm` in the production scripts, `TEST_PROJECT_ROOT`, `git clean`/`reset --hard` and `aid-job.sh --repo` were ruled out — so this is a safety net, not a fix.

## [2.70.4] — 2026-08-04

> A third real audit found the profiler emitting receipts that failed its own
> schema while reporting success, so consolidation rejected all of them and the
> audit died with no artifact naming the cause. Two of the three blockers were
> introduced by this plan's own earlier releases.

### Fixed
- **The profiler wrote receipts its own schema rejects, and exited 0 doing it** — `job.jobs_dir` was added in 2.70.3 without checking the schema, which declares `additionalProperties: false` on `job`, and the no-per-case-timing branch emitted `timing: {}` where `cases`/`planned`/`truncated` are required. Both are fixed, and the profiler now validates its own receipt and fails with exit 14 rather than moving the failure three steps downstream where no field can be named.
- **`evidence_refs` had two different contracts on either side of a wave boundary** — the wave-artifact schema set no `minItems` while the consolidated-findings schema requires 1, so an agent could hand in an artifact that passed its own validation and then killed consolidation with an internal error naming neither the finding nor the field. The producer is held to the strictest consumer's rule: a finding with no evidence is not a finding.
- **A run unit could carry two different commands and be profiled against the wrong one** — measurement reads `execution.yaml`, the profiler reads the catalog. Where they disagreed, this repository measured a 25-minute pool runner and then "diagnosed" a quarantine stub that exits in three seconds, recording `complete: true`: the check meant to prove the slow suite was diagnosed was satisfied by evidence that it never ran. Divergence is now refused with exit 15.
- **Four test fixtures invented their own inventory shape** — `run_units[]` where the scanner and the schema say `entries[]`. One was found by an audit and three more by the inventory validation added in 2.70.1, which had left two suites red across three releases because its effect was never run against every consumer.
- **A gate run's stdout is a JSON document, and 2.70.3 wrote a warning across it** — the "this run is not accounted by a ledger" notice went to stderr, which merges into stdout for any caller capturing both, so the report became unparseable and four gate-runner tests went red. The notice is now a field on the report (`_execution_ledger.accounted: false` with its reason), which is durable, machine-readable, and cannot corrupt the contract it is describing.
- **A selector fixture asserted that an unbound `safe` is parallel eligible** — since P072 a status with no provenance object resolves to `unknown`, because a status nothing verified is a claim rather than evidence. The fixture had been asserting the opposite of what the product does.
- **A suite asserted renderer wording removed when the six-part summary landed** — `finalize-production` had been checking for "audit NOT complete" and "Units left undecided" since that rewrite. Aligned to what the renderer actually prints.

## [2.70.3] — 2026-08-04

> A second real audit lost its own evidence: the entire
> `.aid-o/work/test-audits/<id>/` tree — inventory, catalog, eight agent
> artifacts, measurements, 112 resource maps — disappeared during a cost
> profiling run, and the finalize step then had nothing to read. Ninety minutes
> of work, gone, with no error.

### Fixed
- **The cost profiler wrote into the audit's own evidence tree, and that tree vanished during a profiling run** — the mechanism was not identified, so this fixes what can be fixed and refuses to let it be silent again. Job records now live inside the disposable clone instead of `--output-dir`: the profiler had no reason to write there, since the only thing the audit needs back is the receipt. And the audit's file list is recorded before the profiled command runs and checked after — anything that disappeared is named and the run exits 13, because an audit that quietly loses its own evidence reports a smaller portfolio than it examined with nothing to show anything is missing.
- **The slowest unit in the portfolio was the one guaranteed never to be profiled** — `profile-select` took only `terminal_pass`/`terminal_fail`, on the reasoning that an unfinished job has no duration worth ranking. That is backwards for a timeout: exhausting a deadline is a lower bound and the strongest cost signal there is. `timed_out` units are selected now and carry `measurement_kind: "lower_bound"` so they can never be read as a measurement; `lost` and `cancelled` stay out, because those have an absence rather than a duration.

## [2.70.2] — 2026-08-04

> A second real audit run got further and hit the next wall: the resource map
> crashed on this repository's two largest test files. Not a defect of the
> audited project — a defect of the plugin doing the auditing.

### Fixed
- **`Argument list too long` killed the resource map on large files** — the assembled document was passed to `jq` with `--argjson`, which puts the whole JSON in ONE command-line argument, and Linux caps a single argument at 128 KB (`MAX_ARG_STRLEN`) no matter how large `ARG_MAX` is. This repository's two biggest test files produce maps above that, so the script died and wrote nothing. The three unbounded values are read from files via `--slurpfile` now, and the same treatment is applied to the catalog's `source_pattern_mappings`, which scales with the selector rather than with anything bounded.

## [2.70.1] — 2026-08-04

> The first real `--mode full` audit of this repository reached a terminal state
> without producing a decision. It found three independent blockers, each fatal
> on its own, plus five smaller real defects. This release is those fixes.
>
> Live acceptance remains pending: the audit still has to complete, and the
> consumer E2E from an installed plugin has not run.

### Fixed
- **`--mode full` could never finish on real data** — the consolidator read `.run_units[]` from the inventory while the scanner and the inventory schema both say `entries[]`, so every full audit died at consolidation. The regression suite missed it because its fixture was hand-written in the invented shape, which is why the consolidator now schema-validates the inventory before reading a field: a fixture that makes up its own contract proves only that two pieces of test code agree.
- **The cost profiler refused every gate unit** — it rewrote a gate's shell-form command into `bash -c …` to hand it to the job supervisor, then asked an allowlist that compared shell-form objects for exact equality. Same command, allowed as shell, refused as argv, exit 11, no receipt — and since the selector always picks the most expensive unit, and that is always a gate, it failed every time. The allowlist now compares the canonical execution form, which widens nothing.
- **`bats --timing` was inserted into the wrong argv slot** for shell-form commands, producing `bash --timing -c …`. Those units get a file-level lower bound instead, the same fallback as any runner that cannot report per case.
- **A freshly-proposed catalog could not be approved** — the scanner wrote `source_pattern_mappings: []` unconditionally while the approver re-derived the real map from a fresh selector snapshot and refused anything that did not reproduce it. Both now call one shared derivation.
- **Approving a scan silently revoked parallel-safety evidence** — a scan classifies every unit `unknown`, so approving one over a catalog carrying real pilot evidence discarded it: 65 units out of the pool and a 24-minute concurrent run back to serial, with nothing announcing it. Approval now names what would be revoked and requires `AID_CATALOG_ACCEPT_REVOCATION=1`.
- **Seven entrypoint scripts were committed non-executable** — invoked as the docs write them, without a `bash` prefix, they exited 126. Six command-file references named scripts that only exist under `scripts/lib/`. Both are now checked by a suite.
- **A missing golden directory minted a new baseline** — `test-epic-to-json-regression.sh` recorded whatever the code currently produced and reported `0/0` with exit 0, so a broken refactor became the expected result in any checkout without the fixtures. It now fails; regenerating requires `AID_REGENERATE_GOLDEN=1`.
- **The resource map read jq's `. as $x` as a shell `source`** — dot-space at the start of a line matched the source-directive rule, producing `as` as a file to resolve, which inflated `unresolved_sources` and helped hold maps at `capped_at_unknown`.

## [2.70.0] — 2026-08-04

> Superseded by 2.70.1, which fixes three defects that made `--mode full`
> unable to finish on real data. Live acceptance is still pending — the real
> full audit (Step 24) has not completed and the consumer E2E from an installed
> candidate has not run (`docs/plans/P072-real-audit-record.md`) — and nothing
> in this line of work may be described as delivering test-suite acceleration,
> because the measurement campaign has not been run either
> (`docs/plans/P072-campaign-ledger.md`).

### Added
- **Source-aware resource map, parallel pilot and provenance-bound catalog** — parallel safety now rests on two kinds of evidence: a map read from source that cites `file:line` for every resource it records, and a pilot that runs a lane's exact membership serially and concurrently in a disposable clone. A promoted `parallel.status` carries where it came from and is bound to the unit's whole dependency closure, so a shared helper acquiring a lock reverts it on its own.
- **Execution ledger (`aid-test-execution-ledger.sh`)** — records one entry per run unit actually dispatched during a gate run and fails when the same unit ran under two gates. Four emission paths — the bats lane, the aggregate runner, the scheduler, and the gate runner itself for directly-invoked commands: without that fourth one it would have certified this repository's own double execution as clean. It is fail-closed throughout: inside an accounted run, a failed open, a failed append, a missing ledger file or an unevaluable close each fail the gate run, because a ledger with a gap reports zero duplicates exactly like a clean one.
- **Deliberate repeats are declared, not inferred** — an execution can record itself as `retry` or `escalation`, and P069's escalation subprocess marks everything beneath it that way. Those are reported separately as `deliberate_repeats` rather than failing the run, while an undeclared repeat is still a double execution — the default is `normal`, so forgetting to mark one is never a free pass.
- **Decision artifact for full audits** — `decision.json` (`aid-test-audit-decision-v1`) carries one terminal disposition per run unit, the portfolio arithmetic, the proposed actions with their impact, and the parallelization lanes. `--write-plan` is gated on it.
- **Cost profiler and deterministic profile selection** — a bounded per-unit diagnosis that runs only against a disposable clone, only through `aid-job.sh`, and reports a lower bound rather than an extrapolation when it does not finish. Which units owe a profile is a policy, and finalization fails when a selected one has no receipt.
- **Five report shapes end to end** plus a clean-clone authority E2E, both driving the real production entrypoint rather than library functions.

### Changed
- **`test-aid-fsm.bats` no longer runs twice per full and release gate run** — `bats_fsm` is dropped from those two profiles, which already run that file through `bats_all`'s pool. This was the live duplication the execution ledger found; the detector's red proof moves into a fixture so removing the waste does not blind the check.
- **Frozen portfolio counts replaced by reconciliation** — the shell-adapter check asserted "exactly 36 suites, 7 declined", which this plan's own new suites made stale. It now asserts that every `test-*.sh` present is accounted for exactly once, discovered or declined with a reason.
- **One authority over parallel safety** — `aid-bats-parallel-lane.sh`, `aid-test-scheduler.sh` and `aid-select-tests.sh` all resolve through `aid_test_catalog_effective_status_map`. The separate text allowlist is retired to a notice, and P071's evidence is migrated with `method: migrated_p071_step3` — except for files changed since P071 verified them, which stay `unknown` and are named rather than re-blessed.
- **The scheduler overlay is subordinate to provenance** — it may still promote a unit nobody has assessed, and can no longer rescue one whose content moved after it was verified. A contract change from P069, recorded with its reasoning in `docs/plans/P069-recontract-check.md`.
- **The audit's chat handoff leads with the decision** — six sections and a technical appendix, replacing a verdict followed by a severity-ranked findings list. A full audit with no decision artifact, or with one that does not validate, now refuses rather than rendering "No action needed".
- **`run-all-tests.sh` result parsing** — suite results are read token-by-token against the shapes this repository's suites really print; anything ambiguous is `unparsed` and fails the aggregate instead of counting as zero tests.

### Fixed
- **The parallel-safety resolver was unusable on the hot path** — 101s to partition this repository's own pool, because it re-parsed the catalog and shelled out to the map builder once per unit. One batch pass with a shared budget: 60s.
- **An incomplete audit could render as "Verdict: clean"** — the renderer classified from findings alone, so an audit that never finished looked like one that found nothing.
- **Profile ingestion failed open** — a corrupt, foreign or tampered receipt became an empty action list, which reads exactly like "nothing needed doing". Every lane and profile input is now schema-validated and bound to its audit.
- **Three shipped documents described `parallel.status` as having no consumer** — which stopped being true once the lane and the scheduler both began resolving through it. The sentence is corrected in all three and pinned by `test-instruction-consistency.sh` so it cannot reappear.

## [2.69.0] — 2026-08-02

### Fixed
- **Files/Scope path parser no longer silently narrows multi-path entries** — `lib/aid-scoping.sh`'s shared cleaner (`_aid_split_path_entry`) now fails loudly on any unparsed remainder after a Files/Scope entry's path list (comma-separated, conjunction-joined, or otherwise ambiguous), instead of silently keeping only the paths found before the ambiguous text. Applies uniformly to the per-step scoping block, the legacy flattened `## Scope > Allowed files/paths` broadcast fallback, the generation-time preflight (`aid-plan-to-epic.sh`), and the D5 contract gate — closing the gap where a malformed multi-path entry could authorize a narrower `allowed_paths` set than the plan actually declared.

## [2.68.0] — 2026-08-02

### Added
- **`aid-bats-parallel-lane.sh`** — replaces the self-host `gate:bats_all` quarantine stub with a real, explicit-allowlist-based parallel bats runner: an approved-safe allowlist (`defaults/config/bats-parallel-safe-allowlist.txt`, opt-in, tracked) gates which bats files enter the `bats -j N` pool; anything not on the allowlist (a brand-new file, or the catalog's still-`unknown` `parallel.status`) runs sequentially instead of being silently skipped or auto-parallelized. Fail-closed path validation rejects nonexistent files, paths escaping the repo root, arguments starting with `-`, and duplicate catalog entries before any `bats` invocation.
- **`gate:bats_boundary`** — a new, separate `required: false` gate for the 2 bats files (`test-aid-plan-final-boundary.bats`, `test-aid-plan-release-boundary.bats`) too expensive to pool or bound with a short timeout; wired into the `full`/`release` gate profiles so it is actually reachable by a real profiled run.
- **`aid-self-host-migrate-p071-gates.sh`** — an idempotent `apply`/`verify` migration script + hashed local receipt so this repo's own gitignored `.aid-o/config/execution.yaml` gate changes survive a clean re-init instead of silently vanishing; a live-guard bats test asserts the real, current execution.yaml satisfies all migrations.

### Fixed
- **`gate:plan_diff` timeout** — was a bare, unexplained `120`; now `300`, traceable to this gate's own historical baseline data, with the prior "34 min of wall clock" incident's attribution to `plan_diff` vs. `shell_pipeline_smoke` explicitly documented as unresolved (the config file predates this attempt's git history and is itself gitignored).
- **`gate:shell_pipeline_smoke` naming** — its description now states plainly that it runs the full aggregate suite (~32 min), not a fast/partial smoke check.
- **`aid-plan-diff.sh` `overall_verdict` vocabulary mismatch blocked `plan-finalize`** — `aid-plan-diff.sh` has always emitted `pass|fail|partial|skipped`, but three consumers (`aid-plan-fsm.sh`'s `--stage inputs` and `--stage review` C3-input checks, and `aid-c3-dispatch.sh`'s `build-manifest` gate) expected `present|absent|skipped` instead — a vocabulary that field never actually carries. Any plan with a required AC lens (`ac_to_test_identity`/`requirement_test_drift`) armed therefore always failed `plan-finalize`, regardless of whether its ACs actually passed. Fixed all three consumers to recognize the real `pass|fail|partial` values, translating to each consumer's own existing downstream vocabulary where one already existed (`aid-c3-dispatch.sh`'s `plan_diff_status` and the plan-boundary-manifest's `plan_diff_verdict` both keep their `present|absent|skipped` enum — only input recognition changed). Also corrected a stale `_generated_by: v2.20.2` version stamp in `aid-plan-diff.sh` to the current version.

## [2.67.0] — 2026-08-02

### Added
- **Test scheduler (opt-in, staged Constraint-8 rollout)** — a new `aid-test-scheduler.sh` batches and dispatches `targeted_tests` execution units as real, tracked async jobs (`aid-job.sh`) instead of one sequential process; enabled only after a project passes a 3-stage rollout gate (`sequential` → `observe_parallel` → `parallel`), each requiring 3 qualifying, full-catalog-covering divergence-evidence artifacts — `sequential` remains every project's default until it explicitly opts in.
- **`aid-run-gates.sh` scheduler dispatch + escalation** — `targeted_tests` now dispatches through the scheduler when a project's rollout stage allows it; an unverifiable (exit 3) or mapping-gap (exit 11) result automatically re-runs as a separate `--profile full` subprocess, never in-process, whose report becomes the verdict-bearing result.
- **Execution-unit membership + concurrency-context evidence** — `execution-unit.schema.json`, membership verification, and `concurrency_context` on `gate-runtime-baseline.yaml` give every scheduled unit a real, schema-bound identity and shared-state accounting.
- **`aid-select-tests.sh --emit-units`** — a new selector output mode the scheduler consumes directly, additive to (and behaviorally identical to) the existing default selection path.
- **`bats_all` quarantine remediation evidence collector + E2E full-path proof** — a collector (`test-integration-quarantine-remediation-evidence.sh`) now packages this repository's own `bats_all` divergence measurements (membership agreement, shared-state findings, streamed diagnostics, resume-without-orphan, measured — never invented — runtime) into a schema-valid bundle once the real, multi-hour sequential+scheduled measurement campaign has been run; that campaign itself remains deferred for this repository (unit-tested against synthetic fixtures only, per a standing PM decision), so no real bundle ships in this release yet. A genuine 10-stage E2E proof exercising the real configured-profile → gate-runner → scheduler → receipts path end-to-end DOES ship, in disposable fixtures. `plan_diff` is explicitly named as unresolved and out of this plan's scope.
- **PM quarantine-decision-record mechanism** — a schema-valid lift/keep/defer decision record, producible only via explicit PM input, citing both evidence bundles above; superseding an existing decision requires naming the current record exactly (fork- and race-proof via a per-gate lock), and no code path ever writes to `execution.yaml`'s `quarantine:` block automatically.

### Changed
- **Enforcement registry + docs** — 3 new scheduler-related enforcement rows and a new README section document the `test_audit.scheduler.mode` config knob and the rollout/escalation behavior above.

## [2.66.2] — 2026-08-02

### Added
- **Formal Curator adjudication of Auditor findings (D5, IMP-468)** — a raw Auditor blocker (severity critical/high) can no longer be waved off by a bare `curator.blocking_findings: false`; the Curator must record a schema-bound `curator.adjudications[]` entry per finding, exactly bound to the audit report hash, candidate and run. Enforced at both the plan-final review boundary and, for the first time, the `.aid-lifecycle` classifier (previously blind to adjudications, permanently misclassifying a legitimately adjudicated plan as rejected) — via a new shared resolver, `lib/aid-adjudication.sh`.
- **Plan-final C3 dispatch identity + AC-verdict pinning (D2, IMP-464)** — the shared C3 bridge now carries a plan-shaped identity (`AID_C3_PLAN_ID`) instead of misreading the plan-final run directory as an EPIC id, and pins `plan-diff.json`'s hash (`AID_PLAN_DIFF_SHA256`) so C3 cannot dispatch over evidence that drifted from what `--stage inputs` sealed. `audit-input-manifest.json` is now a required `--stage review` output, chained to `audit-report.json`'s claimed input hash.

### Fixed
- **Durable close-evidence receipt published atomically (D1, IMP-466)** — the plan-final close-evidence receipt is now sealed and pushed to the remote alongside `main` in one atomic transaction, not as an afterthought after `main` is already public; a fresh clone that has lost its local runtime evidence can recover and close a plan using only what was pushed. Two related recovery-path gaps (repair/recovery incorrectly requiring the never-pushed `plan/<id>` branch to exist) were also closed.
- **Plan-final review TOCTOU closed (D3, IMP-465)** — `--stage review` now snapshots every required output once, before validating any of them, so a file cannot be swapped between being validated and being sealed into the durable receipt.
- **Receipt inventory frozen per schema version (D4, IMP-467)** — the plan-final receipt's required-output inventory check no longer re-derives its expected list from the live plugin code (which would retroactively invalidate receipts sealed by an older version); it is now a literal, versioned list, restored at every verification and recovery site including one that had been missed.
- **C3 dispatch false-negative on a missing jq binding** — a missing `jq --arg` binding in the shared C3 bridge's report writer made every C3 dispatch (not only plan-final) silently fall back to an `outcome: "invalid_output"` unverifiable report instead of a clean pass/fail one; found via full-suite regression while validating the above.

## [2.65.0] — 2026-07-30

### Added
- **`/aid-audit-tests` — test portfolio audit capability** — deterministically inventories a project's test portfolio (Bats, package-script/CI, and declared-gate run_units), optionally measures a bounded subset safely via the approved-catalog-only command allowlist, and ends every run with a mandatory 5-part plain-language chat recommendation. Static mode never executes tests; measure/full modes run only commands already present in the target project's real `execution.yaml` or an approved test catalog — never free-form output.
- **Test catalog `proposed`→`approved` lifecycle** — `aid-test-catalog-approve.sh` force-tracks a reviewed catalog into git at the fixed canonical `.aid-o/config/test-catalog.yaml` path; a separate, mandatory `aid-test-catalog-confirm-mapping.sh` gate (with a reviewed-diff hash) is required before `source_pattern_mappings[]` may be treated as authoritative — approving the catalog file never implies approving the routing map.
- **Chat-first recommendation and sanctioned `/aid-plan write` handoff** — every completed audit's final turn contains a verdict, up to 5 evidenced reasons, what changed, a next action, and residual risk; a same-conversation "vytvoř plán oprav" reply (or `--write-plan`) resolves to one shared, fail-closed validator before the controller ever invokes `/aid-plan write` for real.
- **`/aid-init` distribution of `test-audit.yaml`** — the new project-level audit config is now installed copy-if-absent, byte-identical to its hardcoded loader defaults.
- **Self-host dogfood + generated remediation plan** — `/aid-audit-tests` was run against `aid-orchestrator` itself in a disposable clone, producing this repository's first real approved test catalog (83 run_units) and a separate, generated remediation plan (P070) tracing every item to a specific finding.
- No scheduler, batching, or `aid-run-gates.sh`/`aid-select-tests.sh` execution-path integration ships in this release — that is the dependent P069 plan's job, against this release's own shipped, stable catalog/config contract.

## [2.64.0] — 2026-07-28

### Added
- **Plan-global generation receipt** — a hash-bound receipt now proves that every generated EPIC package, its contract evidence and its plan JSON still match the reviewed source plan before strict execution may begin.

### Changed
- **Two-stage EPIC generation** — the pipeline now generates and validates every phase before it creates any run, FSM state or queue entry, so a normal plan no longer needs a PM override for an artefact that generation itself must create.
- **Source dependency graph** — C0 now receives a provisional, source-plan graph built by the same fail-closed parser used by the generator, while its per-EPIC graph remains a separate sealed input.

### Fixed
- **Generation integrity** — ambiguous dependencies, comma-separated multi-path `Files:` entries, drifted generated dependencies and incomplete multi-phase evidence now fail before execution instead of being silently accepted or overwritten.

## [2.63.2] — 2026-07-27

### Fixed
- **test-fsm's increment-step assertions** — they expected the pre-IMP-263 bare number, which the CI step timeout had hidden since 2026-07-23.

### Changed
- **Backlog records P068 as done** — released as 2.63.0, live-verified by the P077 dogfood, with the three `before P068` prerequisites marked satisfied against the code that satisfies them, and IMP-280 added: a dogfood must not run in a linked worktree sharing refs with the repository it tests.

## [2.63.1] — 2026-07-27

### Fixed
- **P064 fixtures under the completion gate** — the suite merged EPICs straight from `running`, which is the hole the gate closes; its seed now completes the EPIC it creates and the three cases that need an unfinished one say so explicitly.
- **Project-root resolution for linked worktrees** — an explicitly named `--project-root` is honoured only when the plan runtime state actually lives there, so an ordinary worktree still shares the main checkout's state while a separate dogfood checkout resolves to its own.
- **CI bash-test timeout** — the suite outgrew its five-minute step and timed out at 55 of 84; raised to twenty.

## [2.63.0] — 2026-07-26

### Added
- **Plan-final release boundary** — a plan in `plan_branch` mode now releases exactly once, at its own boundary: one gate profile run against a frozen candidate, one specialist review, one PM authorization bound to that candidate, one compare-and-swap merge to the target branch, at most one tag, and a committed lifecycle receipt without which the plan cannot be declared closed.
- **`plan-close` as a real gate** — the close transaction verifies EPIC terminality, EPIC merge ancestry, the gate report, every review output re-hashed against its record, the C4 and PM decisions, the merge record and its ancestry, the tag state, `MERGE_HEAD`, unfinished operation records and held locks before it writes anything, and only then commits the receipt and the head-bound marker.
- **`aid-plan-fsm.sh inventory`** — enumerates every plan with its declared mode, EPIC counts and disposition, and with `--apply` stamps unstamped plans `legacy_epic_release_mode` without migrating them or creating a branch.
- **`defaults/policies/plan-boundary-policy.yaml`** — the default mode, lock lease and plan-final profile floor, as a file a project can override rather than a constant it cannot.
- **`AID_PLAN_FSM_CRASH_AFTER` test seam and the AC9 resilience matrix** — every transaction boundary is exercised by real process death and asserted to converge without a duplicate merge, tag or receipt.
- **`test-control-boundary.sh` and `test-instruction-sweep.sh`** — mechanical guards that the plan boundary changed WHEN reviews run rather than whether existing enforcements enforce, and that no unqualified per-EPIC release instruction survives on an agent-facing surface.
- **Agent handoff contract** — `skills/agent-protocol.md` states the five boundary messages an agent working inside a plan-branch plan may rely on.

### Changed
- **Default mode for new plans is `plan_branch`** — guarded on the project declaring a `gate_profiles` table, falling back to `legacy_epic_release_mode` with a logged `plan_branch_unavailable: no_gate_profiles` otherwise, so a consumer project cannot flip to a mode whose gates would resolve against nothing.
- **Specialist cadence** — Auditor, Curator, Simplifier and Reporter are plan-final roles under `plan_branch`, dispatched once per plan against the frozen candidate; CP2 and CP3 remain per EPIC.
- **Lifecycle manifest write is fail-closed under `plan_branch`** — a manifest that cannot be written no longer degrades to a warning, because no manifest means no declared mode, which means the plan runs legacy while everyone believes otherwise.

### Fixed
- **`pre-push` exemption checked only the local ref** — `git push origin plan/P068:main` slipped the guarded target branch through; both sides of the refspec are now checked.
- **Stale-authorization guard could be disarmed by history** — any recorded `resulting_sha` disarmed it, so a rewound target branch let a publish land against a head the PM never approved.
- **Abort close was single-shot** — the abort's own lifecycle commit advances the target branch, which the check read as a violation, making every re-run including crash recovery permanently refused.
- **Fail-open paths closed** — a missing frozen target head, an absent tag record, an unrecognised closure state and a missing lifecycle manifest each block instead of passing.
- **The plan was closed before its evidence was checked** — `cmd_plan_close` ran the irreversible plan-layer close ahead of the required Curator/Auditor report gate, so a missing report failed only after the plan was already closed in the books.
- **The declared mode was written but never committed** — the stamp lived in the worktree while the git-tracked authority carried none.

## [2.62.1] — 2026-07-24

### Fixed
- **IMP-263 increment-step is now fail-closed** — strict binding is the default for a new (non-grandfathered) run so unbound evidence is rejected without any env, a partial binding (any missing field) is rejected instead of skipping the id/hash/commit checks, and a hand-inserted transition-ledger row can no longer masquerade as crash recovery: self-heal runs only when the live step-verify carries a complete, plan/HEAD-verified binding matching the ledger row.
- **IMP-269 C3 fail-closed checks the AC source location and receipt consistency** — `ac_source: plan` is earned only by a file under the canonical `.aid-o/plans`/`.aid-o/tasks` tree (any other in-repo file downgrades to `final_report_fallback`); a git-tracked plan is read from the reviewed HEAD, while a gitignored `.aid-o` plan is a canonical worktree artifact sealed into the bundle; and a targeted-run receipt is checked for consistency with its named command, the reviewed HEAD, and a named in-repo log (`log_sha256` must equal that log's recomputed hash). This is consistency-checking, not cryptographic provenance against an actor who can directly edit the evidence files — such an actor is outside this local AID trust model.
- **IMP-270 waiver re-validation cannot fall back to the current HEAD** — a report that declares a waived gate but omits or malforms its `revision.head_sha` now fails closed immediately instead of passing an empty HEAD to the waiver tool, which would have validated the waiver against whatever was checked out rather than the reviewed revision.
- **IMP-262 cancel-before-PID race closed** — a cancel landing before the job wrapper records its pid/pgid is no longer lost: cancel drops a durable request marker and the wrapper self-cancels at entry and immediately before exec, so a job can never start after a cancellation is recorded.

## [2.62.0] — 2026-07-24

### Added
- **Controller-owned background job supervisor (`aid-job.sh`)** — opt-in `run|status|collect|cancel|watchdog|redgreen` giving a long-running command a durable identity and a terminal result a resumed controller can collect without `tail -f`, a notification, or the launcher staying alive; `/proc` starttime pins process identity against PID reuse, `collect` returns `in_flight` never a pass, and `redgreen` stores revision-bound paired receipts that reject a fabricated pass. Advisory/opt-in — no FSM or gate path depends on it.
- **Gate-scoped single-use waiver (`aid-gate-waiver.sh`)** — a per-gate waiver bound to project/epic/run/exact-HEAD/gate-id/command-fingerprint that reports a failed required gate as `waived` (never `pass`) for exactly one gate, replacing the broad FSM `--force` that skipped every precondition; the FSM re-validates each waived row at read time and fails closed on a bare `waived`.
- **C3 test-evidence channel** — `build-manifest` seals a validated, HEAD-bound targeted-run receipt into `evidence_hashes`, so a truthful targeted suite at the reviewed HEAD is consumable rather than forcing a false `unverifiable`.

### Changed
- **Idempotent, step-bound `increment-step`** — step-verify evidence carries a binding (step index/id, plan-step hash, reviewed commit, idempotency token) validated against the live plan before any mutation, a durable ledger makes advancement replay-safe (`status=already_applied` on replay), and machine-readable `status=` stdout replaces the bare number the controller once misread as an error.
- **One committed-tree mode authority** — `cmd_init` now resolves plan mode through the same fail-closed committed-manifest resolver as `done-advance`; missing `yq`, an unparseable manifest or an unknown mode resolve to `unresolved`, never silently to legacy.
- **PM-brief evidence freshness is computed at read time** — the brief no longer echoes a frozen `head_is_current`; it preserves the referenced SHA and reports freshness by comparing it to the current HEAD, so a post-generation commit reads as stale.

### Fixed
- **C3 AC source is explicit and enforced** — the manifest records `ac_source` (`plan|final_report_fallback|stub`); when a run requires an AC lens and the source is not the real plan the build fails closed, and pointing the AC file at (or a byte-identical copy of) `final_report.md` is downgraded rather than laundered into a `plan` classification.
- **Fail-closed lineage** — an omitted lineage argument now defaults to `unproven` (was `proven`), `--repair` on a healthy manifest is a byte-identical no-op that preserves attestation, repair per-write failures propagate instead of being swallowed, and attestation re-derives ancestry from Git and fails closed when it cannot be proven. Repair still never mints `proven`.
- **Plan mode must be explicit at `plan-start`** — an omitted `--mode` is a usage error and `plan_branch` is hard-refused until the P068 plan-final commands exist (the self-asserted `--allow-incomplete-plan-final` bypass was removed as unauthenticated).
- **Queue `merge_target` is authorized, not just parsed** — a dependency's owning plan is derived from its epic id, not read from the same hand-editable `plan_id` field, so `plan_id: P999` + `merge_target: plan/P999` can no longer self-authorize an ancestry anchor; a declared `plan_id` that disagrees with the derivation is refused.
- **`grep -oP` portability guard is repo-wide** — the epic-id derivation is pure bash and a scanner refuses any new non-comment `grep -oP` under `scripts/` outside an explicit allowlist, so the portability defect cannot move between files and stay green.
- **Enforcement-registry honesty** — writer-only controls whose P068 reader does not exist yet are recorded `planned`/`unmapped`, not `active`.

## [2.61.0] — 2026-07-23

### Added
- **`epic-complete` and `epic-merge-to-plan` (`aid-plan-fsm.sh`)** — an EPIC is finalized and integrated into `plan/Pxxx` inside one reconcilable transaction, where Git ancestry is the only accepted proof that the work landed and a manifest `lineage: proven` is the only accepted authority to record it; `state: DONE`, a deleted task branch and a queue entry claiming completion are explicitly not proof, `merged_to_plan` is terminal, and the target branch is never read or written.
- **`lib/aid-queue-write.sh` — the single queue writer** — enum-validated status transitions, an atomic next-EPIC claim performed inside one lock hold, structural validation of every appended entry block, and the new `plan_id` / `merge_target` fields; `queued` stays accepted on read so entries written by older plugin versions remain parseable.
- **Boundary-split gate profiles** — `gate_profile_resolve` gained a `boundary` parameter so an EPIC boundary caps at `standard` while the unbounded result is preserved out of band as the accumulated plan-final floor; the self-host `gate_profiles` table is activated with `docs_updated` in every include list.
- **Five canonical enforcement registry rows** for the EPIC-boundary cap, the plan-final gate record, the `plan_branch` release skip, the unresolved-mode block and the single mode authority.

### Changed
- **Dependency readiness proves ancestry against a declared `merge_target`** instead of guessing `main|master|HEAD`, which reported an EPIC merged into `plan/Pxxx` but not yet released as blocked forever; for an entry carrying a `merge_target` the evidence-based fallback chain is unreachable, so a hand-edited `completed` status can no longer unblock dependent work — a queue entry is a derived view, never evidence.
- **The per-EPIC release stack is structurally silent in `plan_branch` mode** — `cmd_done_advance` resolves the plan's declared mode and skips every stage named in one `AID_PLAN_BRANCH_SKIPPED_STAGES` constant, emitting that list in the timeline; an unresolvable mode is a hard block rather than a fallback, because falling back would merge an individual EPIC into the target branch.
- **One mode authority** — both mode resolvers read the declared lifecycle manifest from the target branch's committed tree; the gitignored runtime manifest is no longer a mode input, an uncommitted or unreadable declaration is `unresolved` rather than an answer, and each resolver keeps its own fail-safe direction (gate routing degrades toward more gates, release routing hard-blocks).
- **`skills/pipeline.md` and `commands/aid-run.md`** carry the mode fork, a full exit-code table for the two new commands, and an honest statement of which parts are wired versus documented.

### Fixed
- **Queue write injection via `awk -v`** — `awk -v` is not a literal channel on either mawk or gawk, so a two-character backslash-n in a free-text reason smuggled a second assignment into the write payload and landed an entry on a terminal status the caller never requested, destroying a neighbouring key and leaving the file unparseable as YAML while the reader kept consuming it; attacker-influenced values now travel through `ENVIRON`, the parse layer aborts the whole write on a malformed payload, and reasons plus ids read back out of the file are charset-validated.
- **The queue append door** — `aid-queue-add.sh` interpolated every argument-reachable field unvalidated, and matched `depends_on` with a BRE instead of a literal so `--depends-on 'E-81.'` bound a dependency on an id that does not exist.
- **Plan id derivation no longer depends on `grep -oP`** — `-P` is a GNU-grep build option that fails outright rather than failing to match, which wrote `plan_id: null` and silently stopped a multi-EPIC plan after its first EPIC on any host without PCRE support.
- **Contract twins agree** — writer and reader resolve a dependency's branch by one rule validated with `git check-ref-format`, so a git-legal branch name can no longer be unclaimable through the queue while the FSM reports it ready.

## [2.60.1] — 2026-07-22

### Changed
- **AUTO liveness and controller ownership contract** — autonomous runs now retain controller
  ownership through a terminal outcome instead of stopping on recoverable technical forks or
  indefinite "waiting" states. Technical recovery is routed to bounded Codex adjudication; PM
  escalation is reserved for decisions that require new authority.
- **Background-job and test-evidence discipline** — instructions now forbid `tail -f` completion
  watchers, require explicit job identity/deadlines, bind test claims to the reviewed revision and
  command, prevent pre-fix aggregate results from proving post-fix code, and avoid duplicate full
  suites.
- **Agent role boundaries** — the controller owns FSM changes, commits, aggregate gates, and
  evidence finalization; implementers run targeted work without orphaning jobs, and verifiers use
  immutable isolated revisions. Instruction-consistency tests protect these contracts from drift.

## [2.60.0] — 2026-07-20

### Added
- **C0 plan-review — pre-EPIC cross-provider review (`aid-c0-plan-review.sh`)** — before a
  risky plan is even turned into an EPIC, a real independent Codex CLI review of the plan
  itself now runs (mirrors the C3 bridge's `build-manifest`/`dispatch`/`verify` shape, same
  transport, different target and schema). High-risk plans get a bounded, ledger-tracked
  fix→reverify loop (same-hash re-dispatch guard in both legacy and `AID_C0_ATTEMPT`
  attempt-explicit modes); Codex-reported `unverifiable` and content-invalid responses
  (hash/head mismatch, C3-shaped output, missing `action_owner`) are both treated as
  untrusted and correctly propagate a non-zero exit from `cmd_dispatch`, never masked as a
  clean pass.
- **CP1 revision-limit ledger (`aid-cp1-ledger.sh`)** — mechanically enforces how many
  revision rounds a plan gets during C0 review (previously only written down in
  documentation, never enforced by code). Full ledger-file invariant validation (attempt
  counts, fixed policy max, plan-id match, ordered attempts_log), `flock`-protected
  read-modify-write on increment (concurrent-safe), and a real single-use PM-override
  artifact (`cp1-pm-escalation-override.json`, atomically claimed and consumed) for
  authorized bounded-loop bypasses — replacing an earlier bare-env-var bypass.
- **Bounded C3 fix→reverify loop (`c3/attempt-NN/` + `c3/loop-summary.json`)** —
  `AID_C3_ATTEMPT`-driven per-attempt evidence layering, terminal-outcome tracking (an
  ALLOWLIST of recognized terminal values — any unrecognized/corrupted outcome is treated as
  terminal too, fail-closed), a controller-judged `escalate` subcommand for conflicting
  findings, and a `c3_fix_loop` policy (`max_rechecks: 2`) in `c3-audit-policy.yaml`.
- **Advisory Claude fallback for C3 (`c3_advisory` audit mode)** — when Codex is genuinely
  unavailable (down, rate-limited, no auth), the system runs a same-provider Claude fallback
  review instead of silently skipping. Always honestly labelled "advisory, not independent"
  and never satisfies `c3_required` (D7 echo-only) — policy default flipped
  `c3_on_unavailable: unverifiable → degraded_advisory`.
- **Versioned `c3-audit-prompt-v2.md`** (v1 frozen) — explicitly separates always-allowed
  read-only operations from `allowed_recheck_commands` (narrowly scoped to re-executing a
  named test/gate command), fixing IMP-245 (an empty `allowed_recheck_commands` list read
  over-conservatively as "no commands allowed at all," blocking even Codex's always-required
  basic repo reads — found via 2 consecutive real dogfood runs).
- **Full protocol-v2 envelope on `c3-dispatch.json`** (`aid-protocol-validate.sh`,
  `aid-c3-dispatch.sh`) — `c3_dispatch` added to `VALID_ARTIFACT_TYPES` /
  `TYPE_PAYLOAD_MAP`, and `_write_dispatch_json` now emits `control_protocol`, `identity`,
  `subject.subject_hash`, and the correct `provenance.dispatch_mode: deterministic` (was
  incorrectly hardcoded to the C3-domain value `cross_provider`, conflating the envelope's
  "how was this artifact produced" concept with C3's own
  `independence.achieved_independence_level`). Closes a gap that had silently affected every
  EPIC's evidence pack in this plan, discovered only while exercising a real end-to-end
  Curator/CP4/delivery-gate closure for the first time.

### Changed
- **FSM `done-advance` C3/C0 hooks harden against the bounded-loop bypass class** — the
  same-hash re-dispatch guard now applies in both legacy and `AID_C0_ATTEMPT` modes; a shared
  `pm_override_claimed_this_call` flag prevents one claimed PM-override artifact from being
  consumed twice when both C0 guards fire on the same dispatch call.
- **`cmd_done_advance` (`aid-fsm.sh`) gained a directional phase-edge check** —
  `review → release` is now the ONLY legal `done_phase` forward edge; a prior gap let
  `release → review` regress the phase backward with no negative test catching it.
- **`review-profiles.yaml` surface coverage improved** — `e2e/evidence/**` fixtures now
  classify as low-risk (were previously falling through to `unverifiable`, over-triggering
  C3 review on test fixture churn).
- **CI `bash-tests`** (carried from 2.58.4, first released here) — the SIGPIPE flake in
  `test-regression.sh`'s `grep -q` usage is fixed across all eight affected sites.

### Fixed
- **CRITICAL: `aid-c3-dispatch.sh verify` did not bind `audit-report.json`'s own semantic
  fields to the raw Codex response** — `status`/`review_status`/`outcome`/
  `unverifiable_reasons` were unbound, so a hand-edited `unverifiable → pass` flip on a
  committed report still verified clean and could have let `done-advance`'s merge gate
  wrongly advance under `enforcement: blocking`. Fixed with one shared
  `_derive_report_semantics` function used by both the writer and the verifier, additive
  binding checks, and an FSM-level rejection test. Independently re-verified 3 times (CP2
  security re-review + 2 fresh CP3 passes) before merge.
- **`cmd_dispatch` (`aid-c0-plan-review.sh`) returned exit 0 for a transport-genuine but
  content-invalid C0 review response** — the final exit-code decision checked only the
  transport-level `$outcome`, never the already-computed `$presp_rc` or the written report's
  own `review_status`. A hash/head mismatch, schema-invalid output, or Codex itself honestly
  reporting `unverifiable` all still returned exit 0, letting a caller treat an untrustworthy
  review as a clean pass. Found by this EPIC's own 12th live Codex CLI DONE-review audit
  against its evolving HEAD; fixed by checking `presp_rc`/`review_status` before returning 0,
  matching the pattern the ledger-increment gate already used.
- **A real Codex session UUID was briefly committed** during this plan's EPIC-4 CRITICAL-
  bypass fix cycle; already resolved via a PM-directed history rewrite (git plumbing, object
  pruned) before this release.

This release ships the full **C3 Cross-Provider Dispatch Bridge** plan (P065, 7 EPICs,
E-065-1_7 → E-065-7_7): C3's dispatch/validate/normalize/verify core (2.59.0) is now joined
by real merge-gate enforcement, the advisory fallback, the bounded fix→reverify loop, and the
plan-time C0 counterpart with its own revision-limit ledger — the first time AID's
"independent cross-provider audit" claim is backed by an actually-independent, actually-
verified second opinion end to end. Enforcement stays staged at `observe`, not `blocking`,
for both C3 and the CP1 ledger; full production promotion is a separate, deliberately
deferred decision (P062/E10). E-065-7_7 (the final EPIC) merged as an explicit PM-authorized
risk-accepted override rather than a green `aid-release-policy.sh` gate — see
`.aid-o/work/evidence/E-065-7_7/R-E065-7/merge-decision.md` for the full reasoning.

## [2.59.0] — 2026-07-15

### Added
- **C3 cross-provider dispatch bridge** — `aid-c3-dispatch.sh` performs the real independent audit that E8 only detected the feasibility of, using a genuinely different vendor (Codex) instead of an in-process Claude call. `build-manifest` assembles a hash-manifested audit brief (changed files + risk profile + rendered prompt); `dispatch` invokes the Codex CLI as a fresh subprocess, always probed as `cross_provider` and non-sticky, then crosses the untrusted-response trust boundary (schema-validate hardened against a multi-document-JSON bypass, normalize, write report or write-unverifiable); `verify [--reference]` re-binds the written `audit-report.json` to the raw Codex output and confirms it describes HEAD (provenance + faithful-transform proof). Independence comes from the vendor split and a fresh process, not a filesystem sandbox — Codex reads the repo read-only.
- **Versioned C3 prompt template and deterministic renderer** — `c3-audit-prompt-v1.md` plus `aid-render-prompt.sh` render the same brief from the same run facts every time (the prompt is versioned data, not an ad-hoc string), alongside `c3-codex-response.schema.json` as the external-response contract that routes any off-shape reply to unverifiable rather than a coerced pass.
- **`c3_executor` audit policy** — `c3-audit-policy.yaml` gains an executor-first block with a `cross_provider` probe and `c3_on_unavailable: unverifiable`, so an unavailable executor degrades fail-closed (blocking for C3-required profiles) rather than silently skipping; the `degraded_advisory` disposition ships in a later phase of this plan.

### Changed
- **FSM `done-advance` C3 hook now enforces the provenance + faithful-transform chain** — the hook shells out to `aid-c3-dispatch.sh verify`, making the full report↔raw binding a real, deterministic, merge-blocking capability in code rather than prose. Shipped enforcement stays `observe`; blocking activation is decided at a later milestone (E10) after calibration, matching every other C-stage gate's promotion pattern.
- **`pipeline.md` `c3` audit dispatch uses the real bridge** — the `c3` audit mode now calls `build-manifest`/`dispatch`/`verify` instead of an in-process Claude `Agent()` audit; `legacy_health` mode is unchanged, and `agents/auditor.md` was synced (`C3.1a` state-matrix mirror, `C3.2` scoped to `legacy_health`).

## [2.58.4] — 2026-07-14

### Fixed
- **CI `bash-tests` SIGPIPE flake in `test-regression.sh`** — the CI job had been failing for several releases on the F1 check `echo "$done_section" | grep -q 'C+A Execution Model'`. `done_section` is the whole ~36 KB §7 DONE of `pipeline.md`; `grep -q` exits on the first match and closes the pipe, so `echo` takes a `SIGPIPE` (141) and — under the suite's `set -uo pipefail` — the pipeline returns non-zero, flipping the `if` to false and falsely reporting the (present) section as missing. Reproduced locally at ~1-in-5 runs, deterministic on the CI runner. Fixed by feeding grep via a here-string (`grep -q PATTERN <<< "$var"`) so there is no early-exiting pipe reader; applied to all eight `echo "$var" | grep` sites in that suite. Other suites share the pattern only on small (sub-pipe-buffer) variables that cannot trigger the race, so they were left unchanged.

## [2.58.3] — 2026-07-14

### Added
- **Plan-time Files-shape lint (`aid-plan-lint.sh`)** — malformed `**Files:**` entries are now caught when the plan is written, not phase-by-phase during EPIC generation. A plan whose Files entries would break the generation-time D5 `allowed_paths_shape` gate (a bold-wrapped bullet, a parenthetical-only bullet, a prose-only entry, a word before the backtick path, or a verb+path split across two lines) is rejected up front, with the exact `plan.md:line` and the canonical grammar to fix it. The lint runs at two points: automatically in `/aid-plan` right after the plan is written (early feedback, before CP1), and — the enforcement of record — as a deterministic hard pre-flight inside `aid-plan-to-epic.sh` that fail-fasts before any EPIC file is written or the plan counter is bumped, so it cannot be skipped the way an agent instruction can. Two-tier severity: ERROR (the shared cleaner yields no path or a bad-shape path — WILL break the gate) always blocks; STRICT (cleaner-OK but non-canonical) blocks `lifecycle_strict` plans and is a loud advisory for legacy plans, so already-working plans are never suddenly globally blocked.

### Changed
- **Single source of truth for Files parsing** — the lint, the generator (`aid-plan-to-epic.sh`), the JSON deriver (`aid-epic-to-json.sh`) and the D5 gate (`aid-contract-validate.sh`) now all share ONE extractor (`_aid_extract_files_bullets`), ONE path cleaner (`_aid_split_path_entry`) and ONE shape predicate (`_aid_path_shape_ok`) in `lib/aid-scoping.sh`. `aid-plan-to-epic.sh`'s own duplicated copy of the cleaner and its inline Files-extraction awk were removed and replaced by the shared functions (verified byte-identical generation), and the gate's inline shape check now calls the shared predicate. An integration test proves a lint-clean plan flows clean through `plan-to-epic → epic-to-json → contract gate`, so the lint and the generator provably cannot have a different reality.
- **Plan Files-entry grammar is documented + enforced** — `skills/plan-writing.md` now states the canonical Files grammar (`- <Create|Modify|Test|Rewrite>: \`path\` [ + \`path\`]* [(lines ~N-M)] [— prose]`) with explicit NEVER rules, and `commands/aid-plan.md` runs the lint before CP1 in both brainstorm and write modes.

## [2.58.2] — 2026-07-14

### Fixed
- **Untracked manifest is no longer overwritten (parity with the receipt guard)** — `aid_lifecycle_ensure_manifest` previously wrote the manifest straight over the worktree path, so a foreign untracked `.aid-lifecycle/manifests/P<NN>.yaml` could be clobbered (the receipt path already guarded this, the manifest did not). The manifest is now built into a temp file first; an existing untracked manifest is re-committed ONLY when it is byte-identical to the freshly-generated canonical one (our own interrupted-run artifact), and a differing untracked manifest is refused fail-closed (rc 4), never overwritten.
- **Receipt-commit failure no longer returns success** — after the last required EPIC, both `record-delivery` and `plan-reconcile --apply` attempted the closure-receipt commit but, on failure, continued to the status echo and exited 0. The derived state never lied as `closed`, but automation received a false success while the closure receipt was not durable. A receipt-commit failure now propagates a non-zero return (rc 5) while the stdout state line stays honest. (Includes a fix to a bash `[[ … ]] && { … }`-as-last-statement gotcha that made a clean `plan-reconcile --apply` return 1.)
- **D1 dependencies are expressible on the normal path** — a plan can now declare `depends_on_plans:` in its frontmatter (added to the plan template) and `ensure_manifest` writes it into the tracked manifest at scaffold, so the D1 init gate actually hard-blocks on an unclosed structured dependency without a hand-crafted manifest. Legacy plans without frontmatter get an empty list, unchanged. Frontmatter extraction is mikefarah-yq safe (`// []`, not the jq-ism `[]?`) and tolerates leading blank lines before the opening `---` fence, so a stray blank line can never silently drop a declared dependency (a D1 gate fail-open).

## [2.58.1] — 2026-07-14

### Fixed
- **IMP-232 closure model wired into the runtime lifecycle** — v2.58.0 shipped the closure library/CLI but the normal AID flow never invoked it (it only wrote the legacy `ca-review-complete` marker), so no manifests/receipts or `closed` state were ever produced during real work, and the `aid-fsm.sh plan-reconcile` command the init advisory told users to run did not exist. This release completes the wiring, with one concrete, named, tested call path: (1) the pipeline creates a git-tracked lifecycle manifest — repo identity + manifest committed together — at official plan scaffold, so a new plan never waits for a manual reconcile to have a manifest; (2) a single post-merge hook `aid-fsm.sh plan-record-delivery <epic_id>` — a named, tested call path invoked as the pipeline's post-merge step (skills/pipeline.md step 15a, run on the target branch immediately after the agent-run branch merge, at the same enforcement level as that merge) — records the real merge SHA + review provenance and writes the closure receipt so the plan becomes `closed` when the last **required** EPIC is delivered + review-accepted; (3) `aid-fsm.sh plan-reconcile` / `plan-record-delivery` / `plan-state` now exist as real subcommands (no contradictory entrypoints); (4) every lifecycle commit uses a truly isolated git index (`GIT_INDEX_FILE` temp index) so the user's staged/working files are provably never touched — verified by index-fingerprint fault-injection tests, not just a clean worktree after recovery; (5) a merged EPIC whose historical review is unverifiable is recorded `delivery: delivered, review: unverifiable` — the plan stays `active`, never falsely closed and never presented as "accepted". Pre-merge `plan-close` still only verifies reviews + keeps the marker (no delivery SHA, no tracked commit on the task branch). End-to-end tested: manifest-at-scaffold, real-merge provenance recording, last-required→committed receipt→`closed`, clean-clone→same `closed`, P061-shaped delivered-but-unverifiable→`active`, and no lifecycle op changing the user's index at any interruption point.
- **Lifecycle isolated commit refuses UNSTAGED user collisions, not just staged ones** — the isolated commit builds its tree from the worktree files on disk, so an uncommitted user edit to an already-tracked `.aid-lifecycle/` manifest or receipt could previously be swept into AID's automatic commit if the user had not `git add`-ed it. The entry precheck now fail-closed refuses BOTH a staged lifecycle path AND an unstaged modification to a tracked lifecycle path, and this precheck runs before `bind_delivery` mutates the manifest in `record-delivery` and `plan-reconcile --apply` (not only inside the commit helper, which runs after AID has legitimately written its own content). Additionally, an untracked receipt already on disk from an interrupted run is only re-committed when it is byte-identical to the freshly-generated canonical receipt — a differing untracked receipt is treated as a user collision and refused, never overwritten. `record-delivery` now propagates ANY non-zero `ensure_manifest` result (including a refused collision) instead of only codes 2/3/5, so a non-durable/collided manifest can never fall through into a bind/commit. On refusal the user's edit, the index, and `HEAD` are left byte-identical.
- **Scaffold manifest enforcement is opt-in per plan, never silent** — the manifest-at-scaffold step splits by a new `lifecycle_strict: true` plan-frontmatter flag (added to the plan template, so new plans are strict by default): a strict plan whose EPIC declaration is ambiguous FAILS-CLOSED before any EPIC is generated (fix the `**EPIC N: …**` / `**EPIC N / Backlog: …**` grammar, or set `AID_LIFECYCLE_MIGRATION=1` for an explicit audited legacy run), while a legacy plan without the flag proceeds under a loud, logged migration (`[WARN] … AUDITED migration` + a `.aid-o/work/lifecycle-migration.log` marker) rather than a silent skip. This keeps pre-`lifecycle_strict` fixture plans and real legacy plans (table/`##`-header grammar) working without weakening the fail-closed guarantee for new plans.

## [2.58.0] — 2026-07-13

### Added
- **Canonical plan-level closure (IMP-232)** — a durable, evidence-anchored, PUBLIC-SAFE lifecycle model that replaces the scattered, gitignored per-EPIC `ca-review-complete` markers as the source of truth for "is this plan done?". Git-tracked `.aid-lifecycle/` artifacts (a stable repo-identity UUID, per-plan manifests, and closure receipts) survive a clean clone and the eco-dev↔eco-prod mirror, while all detailed evidence stays in gitignored `.aid-o/`. States: `active` / `delivered-but-unreconciled` / `closing_pending_commit` / `closed` / `legacy-unverifiable`, with a required-only denominator (backlog EPICs never block closing). `aid-lifecycle.sh` exposes read-only queries + artifact validation; `plan-close` (forward path) and `plan-reconcile` (`--dry-run`/`--apply`, legacy migration) are the mutating, metadata-only, fail-closed operations. A binding public-safe contract (JSON-Schema `additionalProperties:false` + a value/secret/abs-path/free-text-key net) gates every artifact before it is committed, so the tracked receipts carry only technical fields — never report bodies, findings, prompts, absolute paths, secrets, PII, or waiver reasons. `delivered` requires an unambiguous merge reachable from the configured `target_branch` bound to the EPIC via reviewed-head provenance (a well-named merge alone never closes a plan); a missing/ambiguous binding is `legacy-unverifiable`, never a guess.
- **Dependency-scoped init gate (D1)** — an independent plan's state NEVER hard-blocks another plan's `init`. The old global cross-plan `ca-review-complete` precondition (which blocked P065 because P061 was mid-flight) is removed. A hard block now occurs ONLY when the initializing plan declares a structured `depends_on_plans` target that is not closed (still `--force`-overridable and audited); legacy prose `depends_on` is advisory-only. A single actionable init advisory summarizes delivered-but-unreconciled plans (CI-suppressible), never per-EPIC. Branch-enforcement, clean-worktree, duplicate-state, and rogue-commit guards are unchanged.

### Changed
- **`per_step_scoping` gate precision** — a multi-step EPIC whose steps legitimately refine the SAME file(s) in sequence (distinct outputs) is no longer mis-flagged as the P057/P058 broadcast bug. The check is now authoritative-block-first: when the EPIC declares explicit per-step scope blocks, each generated step's `allowed_paths` must equal what its own block declares (via a shared `lib/aid-scoping.sh` cleaner, so the generator and the gate can't drift); degenerate blocks (identical files AND outputs) still fail (R7); and legacy inputs without per-step blocks fail only when BOTH `outputs` AND `allowed_paths` are identical across all steps. The genuine broadcast bug still fails.

### Fixed
- **`test-run-gates` cwd-isolation flake** — the gate-runner tests wrote their runtime `gate-runtime-baselines.yaml` into the shared `tests/` cwd, so an accumulated baseline could make `run-all` return non-zero and flake the whole suite (reproduced on a clean tree). The suite now runs from a throwaway isolated cwd.

## [2.57.2] — 2026-07-13

### Added
- **Audited cross-plan force-init passthrough (`--force-init-reason`)** — `aid-json-to-run.sh` and `aid-auto-pipeline.sh` gain an explicit, invocation-scoped `--force-init-reason "<why>"` flag that forwards the sanctioned `aid-fsm.sh init --force --reason` override to the FSM. It waives ONLY the plan-level DONE gate (the false-positive cross-plan `ca-review-complete` precondition raised when a different plan is intentionally in progress); all other init checks (branch enforcement, clean-worktree, duplicate-state) still run and are not masked. The FSM enforces a ≥20-char reason and records the override to the run timeline, the cross-EPIC audit log, and a waiver artifact. It is a CLI flag rather than an env var, so it cannot leak into unrelated inits.

### Fixed
- **`aid-epic-to-json.sh` Files-verb parser dropped `Test:`/`Rewrite:` labels into `allowed_paths`** — the label-strip step only removed `Create:`/`Modify:` prefixes, so a Files entry using the plan-template-sanctioned `Test:` or `Rewrite:` verb kept its label and produced a non-path-like `allowed_paths` entry (still carrying the `Test:`/`Rewrite:` prefix), breaking the pipeline `allowed_paths_shape` contract. All four verbs are now stripped.
- **`fsm_force_override` timeline event lost at `init` time** — the arg-parse loop reached `--force` before `cmd_init` created the evidence directory, so the timeline event was written into a nonexistent directory and silently dropped (the audit log and waiver survived because they `mkdir` first). The override is now recorded on all three surfaces (timeline + audit log + waiver).

## [2.57.1] — 2026-07-13

### Fixed
- **`aid-gate-runtime-baseline.sh` flaky `series_reset_at` on fast/CI runners** — `gate_baseline_update` and `gate_baseline_mark_policy_block` stamped `series_reset_at` with second-only precision; two calls landing in the same wall-clock second (routine on a fast machine or a GitHub Actions runner) produced an identical timestamp, spuriously failing `test-aid-gate-runtime-baseline.bats`'s AC3 regression ("command-template fingerprint change resets the series"). Added millisecond precision. Pre-existing flake, confirmed present on the CI run immediately prior to this fix; verified clean across 4 repeated local runs after the fix.

## [2.57.0] — 2026-07-12

### Added
- **Targeted Test Selector (P061 EPIC 3/6)** — `aid-select-tests.sh` maps changed paths to their corresponding test file(s) via a fixed Initial mapping and runs the union of them for real (not just a suggested command), replacing "run everything always" with deterministic, targeted coverage ahead of any self-host gate weakening (EPIC 4). Unknown production paths fail loud with a specific reason string (D-selector-1) rather than a silent skip. Registered as the `targeted_tests` gate definition in `execution.yaml` — defined only, not yet activated in any self-host `gate_profiles` (activation is EPIC 4, D1/D3).

### Fixed
- **`aid-select-tests.sh` CLI parser** — `--base`/`--paths-file`/`--evidence-file` now validate that a value actually follows the flag, returning the documented `exit 10` input-validation error instead of crashing with an unbound-variable error under `set -u` (e.g. `aid-select-tests.sh --base` with no argument).
- **Pre-commit commit-scope guard, main-fallback governance** — replaced an implicit, non-deterministic scan of every historical evidence directory with a single, explicit, FSM-managed active-run pointer. The old scan let a merged EPIC from weeks earlier (found: E-052-1_1) silently continue restricting every commit on `main` to its own stale version whitelist, with the specific historical EPIC selected depending on filesystem traversal order. `aid-fsm.sh`'s `cmd_init` now writes `.aid-o/work/active-run-pointer.json` on every run start — a single slot, always overwritten by the next run's init, self-expiring by construction. `defaults/hooks/pre-commit`'s main-fallback checks (the EXECUTE/GATES rogue-commit block and the DONE/release version whitelist) now read only this pointer, re-reading the pointed-to run's live state on every commit, and fail open on any invalid pointer (missing, malformed, or referencing a state file that no longer exists). The exact-branch-match path (a run governing its own task/epic branch) is unaffected — branch names are unique by construction and were never the buggy part. Consumer projects pick up the fixed hook on their next `/aid-init` refresh.

## [2.56.0] — 2026-07-12

P063 "Gate Runtime Baselines" (4 steps): AID runs gates against static,
human-guessed `timeout_seconds` values that never update as reality drifts.
This EPIC gives gates a real, self-updating runtime history — a percentile
library, live recording, a repeated-timeout enforcement hook, and a CLI to
read it back.

### Added
- **Gate runtime baseline library (`scripts/lib/aid-gate-runtime-baseline.sh`)** — records each gate run's duration/exit-code/timeout as a FIFO-windowed sample series (max 20, keyed by `gate_name`, reset on command-template fingerprint change), computes p50/p90/p95/max via nearest-rank percentiles over non-censored (non-timeout) samples only, and derives `timeout_recommended_seconds`/`run_mode_recommended` (background above a 10-minute p95) once enough real samples exist — atomic flock+tmpfile+validate writes, fail-open on any yq/jq error so a metrics write never blocks the real gate result.
- **`aid-run-gates.sh` integration + lazy gitignore backfill** — every gate run now feeds `gate_baseline_update`, and a one-time-per-clone `.git/info/exclude` backfill (`scripts/lib/aid-gitignore-backfill.sh`) keeps `.aid-o/metrics/` out of version control for existing projects that initialized before this EPIC (new projects already get it via shipped `defaults/.gitignore`).
- **Repeated-timeout policy block (`gate_timeout_policy_block`)** — `gate_baseline_policy_check` flags a gate whose last 3 recorded samples were ALL timeouts at/above its currently-configured `timeout_seconds`; a new `aid-fsm.sh` GATES:EXECUTE precondition refuses to keep retrying that gate (`retryable:false` + `operator_action`), closing the gap where that verdict was previously only a report field nobody read (AID-v3-principles.md §1 — Detector without Enforcement is Decoration).
- **`aid-gate-runtime-report.sh` CLI** — `[--project-root <path>] [gate_name]` reads Step 1's library directly (never re-deriving its percentile/formatting logic) to print one gate's p95/timeout/run-mode summary plus a data-sufficiency note, or every gate with recorded data when no gate name is given; project-root resolution follows the same resolve-then-`cd` idiom as `aid-plan-close-check.sh`.
- **`gate_runtime_baseline_advisory` enforcement-registry row** — documents the CLI as an advisory (non-blocking, non-FSM) reporting surface, distinct from Step 3's blocking `gate_timeout_policy_block` row.
- **`scripts/tests/verify-version-files.sh`** — dedicated checker for this project's 8-canonical-version-file release convention: asserts all 8 locations agree on one version, that it differs from the pre-release baseline, and that both `CHANGELOG.md` files mention it.

## [2.55.0] — 2026-07-11

P061 EPIC 1/6 (gate profile substrát + plan-gate floor): gates-enum unlock, `aid-run-gates.sh
--profile`, `aid-fsm.sh` plan-gate floor (`plan_gate_profile_excluded`), generic `gate_profiles`
substrate for new/existing projects, plus a mid-flight test-cost hotfix.

### Added
- **`--profile <name>` flag (`aid-run-gates.sh`)** — activates a named profile (`gate_profiles.<name>.include[]` from `execution.yaml`); gates outside it get `profile_excluded` (don't run, don't fail `overall`). New report fields: `profile`/`profile_source`/`profile_reason`/`excluded_gates`. Omitting `--profile` preserves prior behavior exactly.
- **Plan-gate floor (`aid-fsm.sh` GATES:DONE)** — cross-references `plan.json.gates[]` against `gates_report.json.excluded_gates[]`; any overlap blocks the transition with `plan_gate_profile_excluded` (never a silent skip). Malformed or wrong-shaped `plan.json.gates` (object instead of array) also fails loud (`plan_json_malformed`).
- **Gates-enum unlock (`plan.schema.json` + `aid-epic-to-json.sh`)** — `plan.json.gates[]` can now carry any gate name (was hardcoded to a 4-value enum); a previously dead validation no-op (`select(. == .)`, always true) now genuinely rejects malformed gate names.
- **Generic `gate_profiles` substrate for new projects (`/aid-init`)** — `compose_execution_yaml` emits a `gate_profile_defaults`/`gate_profiles` block per detected stack, using only that stack's own gate names, never self-host names (D3 consumer isolation).
- **Non-destructive existing-project upgrade (D9)** — `/aid-init` on a project with its own `.aid-o/config/execution.yaml` detects missing profile keys, reports the proposed block, and appends it only after explicit PM confirmation; pure-append implementation makes byte-preservation of hand-edited gate commands structural.
- **Release-policy surface-rule bootstrap check** — `scripts/tests/release-policy-surface-check.sh` (+ `test-release-policy-surface-check.bats`, 7 scenarios) gives P061's Bootstrap Fast Lane a small, explicit, testable rule for when the ~4-5 min `test-release-policy.bats` integration suite is required at step-level targeted testing (only when the diff touches release-policy surface) versus skippable for unrelated steps. Fail-safe default (no paths given) runs the suite. Does NOT change the EPIC-boundary/release-boundary requirement — `bats_all` still runs unconditionally there per D8.

### Fixed
- **`test-release-policy.bats` test-cost blocker** — the suite's 78 tests each ran the real `aid-evidence-verify.sh --at-head` subprocess (~9s/call against a real fixture), pushing the file past 5 minutes and blocking `bats_all` (and by extension this EPIC's own GATES phase) within its configured timeout. Added a double-gated test-only stub seam (`AID_TEST_MODE=1` AND `AID_RELEASE_POLICY_EVIDENCE_VERIFY_STUB=pass|fail|unverifiable`) to `aid-release-policy.sh`'s `run_verification_input()` so branch/logic tests can skip the subprocess; 4 tests (healthy real-pass, dirty-tree real-fail, stale-HEAD real-fail ×2) explicitly `unset` the stub and keep exercising the genuine subprocess end-to-end. Production/default behavior (both env vars unset) is unchanged — the real subprocess call is untouched. Suite time: ~18s/test (timing out past 300s+ overall, unreliable) → 4.6s/test for stubbed tests, ~4m50s reliable total for the full 78-test file.
- **`bats_all` gate timeout** — `.aid-o/config/execution.yaml`'s `bats_all` gate timeout raised from 1200s to 2400s to give the full suite (441 tests across ~30 files) realistic headroom; self-host config only, not shipped to consumer projects (D3).

## [2.54.0] — 2026-07-10

### Added
- **Gate-count integrity guard** — `aid-run-gates.sh` asserts gates-defined equals gates-processed before emitting `overall`, forcing `overall=fail` plus a nonzero exit on any mismatch so a lost or skipped gate can no longer silently pass, with the FSM GATES:DONE precondition loud-failing when jq is missing.
- **Undefined-gate reconciliation** — each `plan.json` gate is reconciled against `execution.yaml`, a declared-but-undefined gate emits a `result: fail / reason: undefined_gate` row that prevents `overall: pass`, and the FSM EXECUTE:GATES precondition requires a `plan_gates_reconciled` marker before advancing.
- **CP2 step-range prefilter** — the prefilter derives its diff range from the step boundary instead of `HEAD~1..HEAD`, hard-exiting on an undetermined range with a `CP2_RANGE_POLICY=observe` seam that downgrades to a `cp2_range_fallback` event.
- **CP3 head-freshness check** — GATES:DONE and done-advance compare the verifier-reviewed head against current HEAD and block on stale evidence by default, with a `CP3_FRESHNESS_POLICY=observe` seam and an explicit D4 exception event for allowed-scope gate-fix or test-only commits past the reviewed head.
- **Runtime cache preflight (IMP-179 partial)** — `scripts/lib/aid-cache-preflight.sh` compares the plugin version and a content-hash of `scripts/` against the running plugin cache, hard-stopping on the dogfood repo and recording the controller version into fsm-state/timeline on consumer repos, closing the scripts/version half of the subagent-cache-staleness gap.
- **Commit-path guard** — a `defaults/hooks/pre-commit` hook restricts orchestrated commits to the per-step `allowed_paths` and refuses when HEAD diverges from the fsm-state branch, with an FSM companion emitting `commit_scope_violation` telemetry and a `commit_guard_disclosure` event.
- **Queue dependency revalidation** — each `depends_on` dependency is re-checked via `git merge-base --is-ancestor` at EPIC start, failing loud on an unparseable queue or an unresolved dependency and otherwise recording advisory telemetry.
- **C4 head-match policy hook** — the release aggregator makes `head_match` consequential, staying observe (`c4_head_match_divergence` / `c4_head_match_unknown` events) until an E10 promotion of `head_match_policy` to blocking.
- **E11 enablement map** — `docs/plans/2026-06-29-BACKLOG.md` records which legacy CP mechanisms each P060 step makes removable or cutover-ready, plus the mandatory K4×K8 binding tying `head_match_policy: blocking` promotion to removal of the CP3 freshness branch.

### Changed
- **Enforcement registry** — 8 P060 rows added (271 to 279 total), covering the new gate-integrity, prefilter, freshness, cache-preflight, commit-path, queue, and C4 head-match mechanisms with their observe/blocking posture and OBS-ledger closures.

### Fixed
- **False-green and stale-evidence pipeline gaps** — closes the OBS-ledger family where a lost gate, an undefined gate, a wrong prefilter range, stale reviewer evidence, a stale plugin cache, an out-of-scope or wrong-branch commit, and an unrevalidated queue dependency could each pass the pipeline undetected.

## [2.53.0] — 2026-07-09

### Added
- **C4 Release Policy aggregator (E9, P059)** — `scripts/aid-release-policy.sh` deterministically aggregates the evidence pack (REQUIRED / profile-gated / advisory / conditional / optional inputs) into a protocol-v2 `release-decision.json`, deriving `release_ready` + `blockers[]` with no LLM, and fails closed on empty/unparseable inputs, a followed `plan_ref` hop, and an `--at-head` evidence mismatch (classified `fail`, never `unverifiable`).
- **PM decision brief generator** — `scripts/aid-pm-brief.sh` projects `release-decision.json` (and only that file) into a protocol-v2 `pm-decision-brief.json` plus a human `pm-summary.md`, echoing every review signal in full so an auto-merge is never silent, then patches `pm_brief_status` back into the decision.
- **FSM dual-run release hook** — `aid-fsm.sh done-advance review→release` runs C4 alongside the legacy checks in observe mode, emitting a `release_policy_dual_run` timeline event with an 8-value never-empty `divergence_class` taxonomy, a `release_policy_preempted` event when a hard-exit legacy gate fires first, a crash-safe fallback, force→waiver artifact writing, and an opt-in `RELEASE_DECISION_POLICY: enforcement: blocking` branch.
- **Protocol-v2 release artifacts** — `release_decision`, `pm_decision_brief`, and `waiver` schemas plus `aid-protocol-validate.sh` D11 field checks and a new `waiver` artifact type.
- **D11 release-decision state model** — `release-decision.json` now carries `pm_brief_required`/`pm_brief_status`, `evidence_verified_at_head`/`evidence_verification_status`, the Reporter/Simplifier CONDITIONAL 5-enum status, `merge_mode`, `delivered_summary_ref`, and `summary_for_pm`, all echoed 1:1 into the PM brief.
- **`scripts/lib/aid-review-signals.sh` shared substrate** — the Reporter/Simplifier enable-toggle + `_test_evidence` validation extracted so the C4 aggregator and the FSM compliance evaluators read identical signals.
- **Invalidation-map live caller (IMP-177 C3 activation)** — the observe-only `invalidation-map.json` producer is now wired into the live gate-fixer dispatch flow (previously test-only), closing the C3-activation half of IMP-177.
- **`docs/extending-aid.md` C4 + D11 contributor reference** — documents the release-policy aggregator, the dual-run hook, the D11 state model, and an explicit "What E9 core Does NOT Deliver" scope-honesty section (no structural merge-on-brief gate, observe-not-blocking default, IMP-179 subagent-cache staleness, IMP-191 fingerprint collision — all deferred).

### Changed
- **Reporter/Simplifier release gating is CONDITIONAL** — release readiness treats them as plan-boundary roles: `not_applicable` off the boundary, `disabled` when toggled off, `missing`→blocking on the boundary when enabled, `pass` when the artifact is present and valid.
- **`test-release-policy.bats` full Doc-1 §13.2 disposition** — the release-policy suite maps all 17 review-instruction fixtures plus 10 D11 negative fixtures (rows 18-27, names carrying `dual`/`waiver`/`d11`), with the 5 N/A/SKIP-REF rows documented in the file header.

## [2.52.0] — 2026-07-08

### Added
- **C3 Independent Audit (E8, P057)** — `agents/auditor.md` converts to dual-mode, selected by `audit_trigger.mode`: risk-gated, distrust-based `c3` (PASS is never the default) alongside the original trust-based `legacy_health` A-J audit kept as compat. C3 emits protocol-v2 `audit-report.json`/`audit-input-manifest.json` (type-named `.audit_report` key, findings top-level, `blocking_findings` boolean, `provider`/`model`/`process_id` echoed verbatim from the harness — never self-reported).
- **`aid-audit-independence.sh`** — detects the actually-achieved audit independence level (`context_only`/`cross_model`/`cross_provider`) against the level required by `c3-audit-policy.yaml` for the run's risk profile; detection-only, never dispatches a real `codex exec` audit; unconfirmable signals degrade to `unverifiable`, never a silent pass.
- **`c3-audit-policy.yaml`** — authoritative risk-profile → required-independence-level policy; only `high` (needs `cross_model`) and `unverifiable` (needs `cross_provider`) carry `c3_required: true`.
- **`aid-fsm.sh` C3 done-advance hook** — fail-closed release block on `blocking_findings`, unverifiable independence, missing/malformed provenance, or a stale audit `head_sha`; risk-gated to the `high`/`unverifiable` profiles only, with no `// false` fallback anywhere in the check.
- **Curator serial after C3 + content-ref sequencing guard** — `skills/pipeline.md` dispatches Auditor (C3) then Curator serially (was parallel); Curator dual-emits `curator-report.json` with `.curator.audit_report_ref` (sha256 of the actually-consumed `audit-report.json`), and a new `aid-fsm.sh` guard blocks unless that hash matches the current report — proving real consumption order, not just a shared commit. `recommended_disposition` merge-authority is untouched (deferred to E9).
- **`invalidation-map.json` observe-only producer** — `scripts/lib/aid-invalidation-map.sh` derives `affected_c1_checks[]` (deterministic subset, read from `delivery-gate.yaml` globs) and `affected_c2_modes[]` (conservative — any C2-touching change affects all modes) from an applied fix's changed paths, emitting the artifact plus a timeline event; registered as `invalidation_map_observe`; never triggers a re-run itself.
- **Behavioral red-green test suites** — `scripts/tests/bats/test-c3-audit.bats` (High→blocking, unavailable→unverifiable, no-provenance→fail, curator-before-audit→fail, each with a positive and negative control via subprocess `aid-fsm.sh`) and `scripts/tests/bats/test-invalidation-map.bats` (real producer execution against fixtures).
- **`docs/extending-aid.md` C3 Independent Audit (E8) section** — documents the full C3 pipeline plus an explicit "What E8 Does NOT Deliver" scope-honesty subsection (no real Codex dispatch, no auto re-run, no C4 consumption, merge-authority untouched, no cryptographic hash-equality binding — see `docs/plans/2026-06-29-BACKLOG.md` § "E8 Deferred").

## [2.51.0] — 2026-07-05

### Added
- **Per-step scoping HTML block (D2)** — `aid-plan-to-epic.sh` emits a `<!-- step-N: files=[...]; ac=[...] -->` block per step so `aid-epic-to-json.sh` scopes `outputs`/`allowed_paths`/`acceptance_criteria` per step instead of broadcasting flattened EPIC-level sections to every step, with legacy no-block EPICs keeping today's exact broadcast behavior.
- **Contract Validation Gate (D5)** — new blocking `scripts/gates/aid-contract-validate.sh` checks generated `plan.json` for per-step-scoping broadcast, AC pipe-split fragments, and prose-shaped `allowed_paths`, wired as the one blocking exception inside the observe-only C0 block of `aid-auto-pipeline.sh` and persisting `contract-validate.json` before aborting so a later phase's failure never hides behind an earlier phase's stale pass; registered as `contract_validation_gate` in `enforcement-registry.yaml`.
- **C0 Check 6 (`contract_validation`)** — `aid-c0-contract.sh`'s `review` subcommand reads (never re-runs) the persisted D5 gate result into the evidence pack.
- **`docs/extending-aid.md` section** — documents the D2 per-step scoping block and the D5 contract validation gate for contributors.

### Fixed
- **`aid-plan-diff.sh` false-green on `## Success Criteria` plans** — the AC-extraction awk used a range pattern whose terminator matched a `## Success Criteria` heading as an end-of-range marker, collapsing the whole section to `ac_count: 0` and silently skipping AC enforcement for every plan using that heading instead of `## Acceptance Criteria`; replaced with a flag-based block that recognizes both headings.
- **`ac_no_fragments` false-positive** — the D5 gate's quote-parity backstop no longer misfires on plural possessives (`users' permissions`) or on quotes inside balanced backtick spans (CP2 finding).
- **Self-consistency regen bugs** — per-step scoping line parsing now anchors on the last occurrence of the `ac=` delimiter instead of the first, and per-step Files-bullet extraction is top-level-only, fixing corruption when a plan's own text describes the block syntax it is itself written in.

### Changed
- **Minor version bump rationale** — this release is a `bug-fix`-type EPIC per its source plan, but bumps MINOR (2.50.1 → 2.51.0) rather than PATCH because it introduces a new blocking gate capability (Contract Validation Gate, D5), not just a fix.

## [2.50.1] — 2026-07-01

### Added
- **E7B existing_ui wiring** — Full pipeline support for modifying existing UI: `visual-companion/SKILL.md` phase-aware baseline capture, `role-cards.md` ui_change_contract constraint, `agent-protocol.md` branched reading order, `pipeline.md` envelope injection + mechanical verdict via `ui-compare.mjs`
- **ui_change_contract envelope transport** — `plan-writing.md` positive assertion rule; `aid-plan-to-epic.sh` encodes per-step contracts into EPIC HTML comments; `aid-epic-to-json.sh` decodes into `steps[].ui_change_contract` (T4 round-trip test proves chain)
- **FSM existing_ui guard** — `aid-fsm.sh cmd_increment_step` blocks with `frontend_visual_fidelity_block` when `ui_change_mode: existing_ui` and `steps/{id}/ui/verdict.json` is absent or result != pass; step-local only (D6 — delivery-gate/C4 aggregation deferred to E9)
- **ui_change_mode + ui_change_contract step fields** — `plan.schema.json` extended; `companion` added to `visual_assets.source_type` enum
- **ui-fidelity.schema.json result field** — `result: pass|fail|unverifiable` and `result_detail` added to verdict sub-document
- **frontend-user-outcome-contract.schema.json** — C2 lens schema for `frontend_user_outcome` (FC-35): persona, user_questions (1-5), actions, data_oracle, significant_states, success
- **`/aid-do` existing_ui redirect** — detects `--ui` flag or `existing_ui` in description, refuses with redirect to `/aid-run` (contract enforcement required); `--no-ui-check` bypass documented
- **test-fsm-ui-fidelity.sh** — 3 runtime tests: pass/fail/absent verdict; all 3 confirm guard fires (P026 pattern avoided)
- **test-ui-fidelity-e2e.sh** — 4 scenarios (happy/un-applied/collateral/capture-absent) + Playwright skip guard (exit 0 with message when browsers absent)

### Changed
- **enforcement-registry.yaml** — Added `frontend_visual_fidelity_block` row (entry 259); instruction now references `pipeline.md §4`
- **test-epic-to-json-regression.sh** — T4 added: full round-trip for existing_ui envelope
- **plan.schema.json golden** — `ui_change_mode: null, ui_change_contract: null` added to step objects

## [2.49.0] — 2026-06-30

### Added
- **E7-CAL Calibration Mechanism** — `ui-calibration-run.sh` runs 5 fixture cases (A/B/C hermetic + D-desktop/D-mobile real ScreenG via Playwright `page.route` mocks), persists 8 artifacts per case (baseline/regressed/rerun PNG + computed JSON + verdicts), writes `ui-calibration-record.json` with artifact map and D `real_surface` assertions proving live URL capture.
- **`ui-calibration-verify.sh`** — Standalone evidence verifier: checks PNG validity, JSON validity, verdict cross-check against record, D cases real_surface assertions (no `hermetic://` URL, no `DETERMINISTIC` text, correct viewport), rejects structurally incomplete records.
- **`screeng-capture.mjs`** — Playwright script capturing ScreenG in 3 states (regressed → baseline → rerun) in a single browser session using `page.route` API mocks.
- **`test-ui-calibration-verify.bats`** — 15 BATS tests preventing false-green calibration (missing PNG, hermetic URL, DETERMINISTIC text, wrong viewport, verdict mismatch, invalid JSON/PNG).
- **`ui-calibration-record.schema.json` v1.1.0** — `artifacts` object required per case; `real_surface` optional object for D cases.
- **`ui_calibration_result` gate** — Calls `ui-calibration-verify.sh`; auto-passes when no calibration record present (non-E7-CAL EPICs unaffected).
- **`ui_calibration_signoff` gate** — PM manual sign-off gate; auto-passes when no calibration record present.

### Fixed
- **`ui-compare.mjs` dimension mismatch reason** — Both `checkLockedCrops` and `checkOutsideMask` now emit `image_dimension_mismatch` (was `locked_violation` and `outside_mask_diff` respectively).

## [2.47.0] — 2026-06-30

### Added
- **E7A UI Fidelity Foundation** — Standalone `lib/ui-fidelity/` package with Playwright capture, pixelmatch comparison, typed contract schema, envelope validator, 5 calibration fixture sets (A/B/C hermetic + D-desktop/D-mobile hermetic), CI workflow, and `ui-contract-check.sh` gate script.

## [2.46.0] — 2026-06-30

### Added
- **DG-15 Route Resolve** — Literal link vs declared route-files probe (react-router/express); opt-in via delivery-map.yaml routes section; config_missing when framework unsupported or map absent
- **DG-17 Independent Oracle No-Drop** — Analytics output cardinality vs declared baseline; requires analytics_output_file + expected_cardinality; missing file → config_missing, not fake pass
- **DG-18 Acceptance Provenance** — FSM step-verify evidence adapter; surfaces acceptance history into delivery-gate.json; never emits fail (provenance-only)
- **delivery-map.schema.json** — JSON Schema for delivery-map.yaml (meta/routes/oracle_baselines, all optional)
- **aid-delivery-map.sh** — Accessor library for delivery-map.yaml with pinned exit-code contract (null → exit 2)
- **map_section_globs + has_acceptance_evidence** — Two new dispatcher condition types in aid-delivery-gate.sh

### Changed
- **enforcement-registry.yaml** — Added DG-15/17/18 rows (surface: delivery-gate, observe, planned E10); totals.enforcements corrected to 258

## [2.44.1] — 2026-06-29

### Fixed
- **`aid-acceptance-evidence.sh` + `aid-consumption-proof.sh` protocol-v2 envelopes** — both scripts now emit full protocol-v2 envelope (`schema_version`, `identity`, `subject`, `revision`, `status`, `verdict`, `provenance`); `revision.head_sha` carries the full 40-char git SHA (was short SHA, broke `--current-head` validation)
- **`aid-acceptance-evidence.sh` step naming** — verifier evidence files looked up as `step-1.md` (1-indexed, no zero-padding) instead of `step-00.md`; `ac_id` suffix changed from `_00` to `_1`
- **`aid-consumption-proof.sh` false-verified** — Strategy 2 (filename pattern fallback: `*contract*`/`*binding*`) removed; only Strategy 1 (grep for binding_id) is valid
- **`consumption_proof` protocol-v2 type registration** — added to `aid-protocol-validate.sh` + fixtures (`valid.json`, `invalid-missing-payload.json`)
- **Enforcement registry planned rows** — `semantic_wiring_would_block`, `c2_acceptance_deviation`, `c2_consumption_unresolvable` now carry `status: planned`, `deadline/deferred_until/promotion_phase: E10`
- **FC-24..28 fingerprints** — `fc{NN}neg` contained non-hex chars; fixed to `fc{NN}000...` (64 valid hex chars)
- **Evidence pack regenerated at HEAD** — `delivery-gate.json`, `acceptance-evidence.json`, `consumption-proof.json` regenerated; all pass `aid-protocol-validate --current-head --check-fingerprint`

### Added
- **E5 wiring-gate bats test** — `E5 wiring-gate observe: Critical finding logged but increment proceeds`; seeds Critical finding in `semantic-review-wiring.json`, asserts exit 0 + `semantic_wiring_would_block` in `timeline.jsonl`
- **T8 fingerprint schema validation** — `test-semantic-review.sh` T8 verifies `sha256:[0-9a-f]{64}` format per FC fixture
- **T9 mutation-survives + low-profile-no-local** — merge count dedup + final-only dispatch-mode tests
- **T10 `--current-head` regression guard** — both `aid-acceptance-evidence.sh` and `aid-consumption-proof.sh` output verified against `aid-protocol-validate --current-head` in test harness

## [2.44.0] — 2026-06-29

### Added
- **C2 Semantic Review Engine (observe)** — 4-mode dual-emit engine (local/wiring/behavior/final) producing auditable `semantic-review-{mode}.json` alongside the existing `.md` gate (D1 unchanged); 12-lens catalog from failure-mode-control-matrix FC-09, FC-24..28, FC-30..32, FC-35; no-mega-prompt rule (D2); observe-only (E5), blocking deferred to E10
- **Wiring-gate observe** — `cmd_increment_step` logs `semantic_wiring_would_block` on unresolved Critical/High wiring findings; `SEMANTIC_REVIEW_POLICY=blocking` enables E10 blocking path without code change
- **`aid-finding-merge.sh`** — lossless fingerprint-keyed merge: severity=max, detail=union sorted, conflicts in `merge_meta`; deterministic output
- **`aid-acceptance-evidence.sh`** — reconstructs `acceptance-evidence.json` from plan.json AC + LLM coverage signals (`## AC Coverage` block); ac_id=sha256[:12]_step_idx; D3: bash aggregates, LLM determines coverage
- **`aid-consumption-proof.sh`** — verifies contract-manifest.json bindings against evidence_dir (grep+filename); fail-safe: missing manifest → `unresolvable` + exit 0
- **`review-profile-check.sh` E5** — `completed_lenses` read from `lenses_run[]` union across `semantic-review-{mode}.json`; E3 backward-compat: no C2 files → same `COMPLETED_LENSES=""` behavior
- **FC-24..28 negative fixtures** — 5 runnable JSON fixtures for transaction_boundary, field_lineage, negative_case, operation_order_resource_bound, requirement_test_drift failure modes
- **`test-semantic-review.sh`** — 8-test harness covering merge, acceptance-evidence, consumption-proof, review-profile-check (E5+E3 backward-compat), fixture validity
- **Enforcement registry** — 9 new C2 entries covering wiring-gate, dual-emit, lens catalog, acceptance-evidence, consumption-proof, completed_lenses, requirement-drift, finding-merge, semantic-review-policy
- **`docs/extending-aid.md`** — C2 extension guide: how to add lenses, dual-emit protocol, fingerprint format, policy promotion path

## [2.43.0] — 2026-06-28

### Added
- **C0 Plan Contract Gate** — observe-only gate layer running in `aid-auto-pipeline.sh` after plan-graph extraction, producing `plan-graph.json`, `contract-manifest.json`, and `plan-review.json` with 5 semantic lenses (observe, E10 promotion target)
- **Shared Kahn topo-sort lib** — `scripts/lib/aid-plan-graph.sh` with `build_plan_graph` function and deterministic `topological_order` output; `aid-epic-to-json.sh` refactored to use it
- **C0 QA harness** — `test-c0-contract.sh` with 66 assertions across 7 fixture sets (clean, cycle, dup-id, p045-style, per-lens, blocking-mode, clean-low-risk)

## [2.42.1] — 2026-06-28

### Added
- **E3 Adaptive Review Profile Detector** — deterministic, LLM-free resolver (`aid-prefilter.sh profile`) computes surface→lens matrix from plan-time + candidate-time git diff union; emits `review-profile.json` with `required_lenses`, `profile_hash`, `risk_profile`, and IR cadence; FSM observe hook logs `missing_lenses` telemetry without blocking (promotion to blocking in E10); 6 surfaces, 5 risk profiles, 13-scenario test harness.

## [2.41.2] — 2026-06-28

### Fixed
- **CI: dg07/dg12 bash-test failures** — delivery-gate fixture `.aid-o/` trees were gitignored by `**/.aid-o/`; added exception in `.gitignore` matching the existing `mini/` pattern; fixture files (`fsm-state.yaml`, `execution.yaml`) are now tracked and available in CI.
- **CI: dg12 unverifiable on GitHub Actions** — `yq` was not installed in the `bash-tests` job; `dg12-authority.sh` fell through to exit=2 instead of parsing the authority YAML and returning exit=1; added `yq` install step.
- **CI: vitest `@aid/contract` resolution failure** — `dist/` is gitignored so `@aid/contract/dist/index.js` was absent in CI; added `npm run build -w @aid/contract` step before `npm test` in the vitest job.

## [2.41.1] — 2026-06-28

### Changed
- **False-Green Guardrails in Verify Commands + Contracts** — `aid-verify-implementation` and `aid-verify-plan` now enforce four additional review requirements: (1) mandatory "Independent runtime path check" output section — DONE review cannot be based on "tests pass" alone; (2) every AC using "always"/"all"/"each"/"never" must define its exact universe or the plan/AC is rejected as not objectively verifiable; (3) eval/evidence artifacts must name which pipeline slice they actually exercise; (4) every new integration function requires at least one caller-flow test, not just a unit test of the pure helper. Same four guardrails added to `review-checkpoint-contracts.md` so they apply to in-pipeline CP2–CP5 reviews, not only the manual verify commands.

## [2.41.0] — 2026-06-27

### Added
- **Evidence Pack Verifier CLI (E2.5)** — `aid-evidence-verify.sh <epic> <run> [--out <path>] [--at-head]` deterministically verifies a completed run's evidence pack: git cleanliness, artifact freshness (as-of-pack, ancestor-of-HEAD; strict `--at-head` mode for live DONE-review), protocol-v2 validation + finding fingerprints per artifact, TTL/registry guard, and observe-vs-blocking interpretation consistency; emits `verification-report.json` (protocol-v2, self-validated) + human summary; standalone CLI outside FSM.
- **`verification_report` Protocol-v2 Type** — 15th artifact type in `aid-protocol-v2.schema.json` enum + `VALID_ARTIFACT_TYPES` validator array + `TYPE_PAYLOAD_MAP` entry + `verification-report.schema.json` type schema.
- **Evidence Verifier QA** — 11 purpose-built fixtures (clean-pack, ancestor-pack, divergent-stale, inconsistent-head, invalid-artifact, enum-garbage, mixed-legacy, nondeterministic-fingerprint, dirty-git, ttl-violation, enforcement-absent) + `test-evidence-verify.sh` harness + golden sample; every check has positive and negative coverage.
- **Enforcement Registry** — 7 verifier checks registered in `defaults/enforcement-registry.yaml` (`surface: internal-guard`, `status: planned`, `deadline: 2027-06-01`); FSM wiring deferred to E9.

## [2.40.0] — 2026-06-26

### Added
- **C1 Delivery Engine** — `aid-delivery-gate.sh` + 12 DG check plugins (DG-01..12) producing protocol-v2 `delivery-gate.json`; observe mode (E2): writes `delivery_gate_would_block` telemetry, never blocks FSM transitions; blocking promotion deferred to E10.
- **Delivery Gate Policy** — `defaults/policies/delivery-gate.yaml` with profile detection (plugin-bash, npm-workspaces, unverifiable) and per-profile check commands; `skip_reason_allowlist` enforces closed vocabulary.
- **Profile Resolver** — `scripts/lib/aid-delivery-profile.sh`: `resolve_profile` + `select_commands` for deterministic argv-array dispatch (no eval).
- **DG-07 FSM Hook** — observe-mode hook in `cmd_done_advance` writes `delivery_gate_would_block` event to timeline; blocking branch is live code tested by `test-fsm-dg07-observe.bats`.
- **Full Delivery Gate Schema** — `defaults/schemas/delivery-gate.schema.json` expanded to full protocol-v2 payload covering `delivery_gate.{phase,profile,freshness,delivery_ready,checks[],summary}`.
- **QA Fixtures + Harness** — 10 per-DG fail/unverifiable fixtures, golden sample, 44-assertion `test-delivery-gate.sh`; every DG-01..12 check has at least one fixture proving it is not an untested decoration.
- **Gate Coverage Fields** — `aid-run-gates.sh` now emits `covered_paths`, `changed_paths_covered`, and `relevance` (direct|partial|none|unknown) in `gates_report.json`.
- **Enforcement Registry** — DG-07 FSM hook + DG-01/04/07/12 registered in `defaults/enforcement-registry.yaml` as observe-mode (status: planned, deadline: E10).

## [2.38.0] — 2026-06-23

### Added
- **`/aid-verify-plan` + `/aid-verify-implementation`** — two manual, PM-invoked commands that dispatch an independent fresh-context agent to adversarially review a plan before execution and an implementation after it claims DONE; each carries its full review protocol (false-green risks, producer-consumer contracts, runtime-not-statics, real-data oracle) and returns a severity-ranked verdict plus a Czech PM summary. Standalone tools outside the FSM (like `/aid-do`) — no `fsm-state.yaml`, no evidence dir, no pending-dispatches ledger.
- **AID Control System v2 protocol** — shared protocol v2 envelope (`aid-protocol-v2.schema.json`), 14 type-specific schemas, deterministic finding fingerprint helper (`aid-finding-fingerprint.sh`), and authoritative bash+jq validator (`aid-protocol-validate.sh`) with 11 blocking invariants (exit codes 2-13); schemas + validator + fixtures only — no runtime wiring (E2+).

### Fixed
- **Protocol v2 `control_protocol` enum** — validator now enforces enum membership (exit 8) in addition to field presence (exit 3); previously any non-`legacy` value (e.g. `"banana"`) passed as exit 0; fixture `invalid-bad-control-protocol.json` and consistency check added.

## [2.37.0] — 2026-06-21

### Added
- **Per-step Acceptance Criteria pre-flight** — `aid-epic-to-json.sh` hard-fails a multi-step EPIC that carries fewer acceptance criteria than steps, so every step has a contract the CP chain can verify (root cause of the E-047-4_7 cockpit REOPEN); override deliberately with `AID_ALLOW_SPARSE_AC=1`.

### Fixed
- **Plan→EPIC acceptance-criteria + role extraction** — `aid-plan-to-epic.sh` now reads acceptance criteria written as plain `-` bullets under `**Acceptance Criteria**` (with or without a colon) and the `**AID Role**` header without a colon; previously it matched only the `**Acceptance Criteria:**` + `- [ ]` + `**AID Role:**` forms, silently dropping every criterion (empty EPIC AC section) and defaulting every step to the `backend` role.
- **Compliance `overall` is severity-aware** — `write_compliance_json` now derives `overall` from blocking failures only (advisory-severity failures are recorded in `failures[]` for visibility but no longer flip it to `fail`), matching the `cmd_done_advance` release gate; previously a single advisory check such as `branch_correct:false` on a PM-controlled shared feature branch produced `overall:fail` even though the FSM correctly released, a self-contradictory record. The provenance-unverifiable integrity signal stays blocking.

## [2.36.2] — 2026-06-19

### Fixed
- **`aid-plan.md` stale CP1 lens names** — CP1-deep section updated from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement`; evidence file table updated with correct filenames and required-field column (producer→consumer drift fix).
- **`aid-cp1-gate.sh` stale header comment** — file header comment updated to match L1/L2/L3 filenames and content requirements.

### Added
- **P046 boundary manifest and delivery report committed** — `.aid-o/reports/P046-boundary.md` and `.aid-o/reports/P046-delivery.md` now tracked in git; `.gitignore` glob fix (`.aid-o/*`) makes this possible.

## [2.36.1] — 2026-06-19

### Fixed
- **CP1-deep empty-file bypass** — `aid-cp1-gate.sh` previously accepted empty evidence files (only checked `-f`); gate now requires non-empty files (`-s`) and the required field at line-start (`stop_rule_blockers:` in lens files, `verdict:` in adjudicator); empty or structurally incomplete files now fail the gate.
- **CP1-deep lens taxonomy mismatch** — lenses renamed from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement` per plan P046 taxonomy; L3 (enforcement/CI/artifact-visibility) is the class that catches gitignored artifacts and non-executing tests.
- **`/aid-init` `.gitignore` guidance** — instruction corrected to replace `.aid-o/` with `.aid-o/*` before adding `!.aid-o/reports/`; git cannot un-ignore content inside an ignored directory — the glob form is required.

## [2.36.0] — 2026-06-19

### Added
- **Behavior-first review contracts** — `skills/review-checkpoint-contracts.md` defines per-checkpoint diff scope, high-risk pattern table (8 categories: auth, routes, validation, migrations, FSM, security sinks, payment, deps), and structural gate rules for CP2/CP3/CP4/CP5/CP6 and CP1-deep.
- **`behavior_trace` structural gate** — `aid-fsm.sh:fsm_check_verifier_output()` rejects verifier outputs where `behavior_trace_required: true` but `behavior_trace_count` is 0 or missing; gate is opt-in and fires only when the verifier explicitly sets the flag.
- **Additive verifier output fields** — `verifier-output-template.md` gains optional top-level fields (`checkpoint`, `focus`, `behavior_trace_count`, `behavior_trace_required`, `behavior_trace`) that extend the output without displacing existing `_generated_by`/`classification`/`verdict` greps.
- **`aid-prefilter.sh --checkpoint` flag** — caller can now pass `--checkpoint <cp2|cp3|cp4|cp6>` to get checkpoint-specific diff scope; CP2 defaults to `HEAD~1..HEAD`, CP3 reads `base_commit` from `fsm-state.yaml`.
- **CP1 risk-scaling** — `aid-plan.md` gains a CP1 Mode Selection section defining CP1-light (standard checklist) vs CP1-deep (three-lens: security/correctness/architectural, adjudicator, max two revisions, PM escalation on unresolved stop-rules).
- **`aid-cp1-gate.sh`** — EPIC generation gate that reads plan frontmatter (`id`, `risk`), scans body for eight high-risk pattern categories, and verifies four evidence files (`cp1-deep/` directory) when risk is high; includes path-traversal guard on plan ID.
- **Enforcement homes reference** — `docs/extending-aid.md` gains an Enforcement Homes Reference section documenting where each enforcement mechanism lives (plan-close, FSM precondition, behavior_trace gate, CP5 blocking_findings, CI floor).
- **Two new enforcement registry entries** — `cp1_critical_path_flow_trace` (type lm_judgment_advisory, surface cp1) and `behavior_trace_high_risk_gate` (type fsm_precondition, surface cp2/cp3/cp4); both carry `deadline: 2026-09-01`, `status: active`, `verdict: ALIGNED`.
- **6 bats tests for behavior_trace gate** — `bats/test-behavior-trace.bats` covers count=0+required=true→fail, count=3+required=true→pass, required=false→pass, field absent→pass, count missing→fail, count=1→pass.

### Fixed
- **`.gitignore` negation pattern** — replaced `.aid-o/` directory exclude with `.aid-o/*` glob so `!.aid-o/reports/` negation works; git cannot un-ignore content inside an ignored directory.
- **CP1 gate `risk: low` precedence** — high-risk body pattern match now always triggers CP1-deep regardless of `risk: low` frontmatter; `risk: low` previously overrode the pattern scan (wrong behavior).
- **Frontmatter parser state machine** — `aid-cp1-gate.sh` parser now uses open/close `---` state machine; stops reading at opening marker, reads to closing marker, rejects plans with unclosed frontmatter instead of silently reading body as frontmatter.
- **Rule #21 `REVISE_REQUIRED` advisory label** — `plan-writing.md` rule #21 REVISE_REQUIRED outcome labeled "(advisory — see 21c, PM can override)" to match enforcement type; test-plan-writing-rules.bats updated (removed dead `FIXTURES_DIR` variable).

## [2.35.0] — 2026-06-18

### Added
- **`plan-close` FSM command** — enforces all four required reports (curator, auditor, simplifier, delivery) before writing the `ca-review-complete` marker; raw `touch` is explicitly forbidden and `pipeline.md §7` directs implementers to this command instead.
- **Toggle-skip for disabled specialists** — `simplifier.enabled:false` / `reporter.enabled:false` in `execution.yaml` exempts the corresponding report from `plan-close`; each skip is audited to `audit-log.jsonl` with specialist name and rationale.
- **`simplifier_report_present` compliance measurement** — `compliance.json` now carries `simplifier_report_present: null/true/false` (advisory severity); anchored for future enforcement promotion.
- **Boundary manifest (committed, CI-readable)** — Reporter writes `.aid-o/reports/{plan_id}-boundary.md` after every completed plan; carries provenance for all four required reports and is readable by CI without accessing gitignored evidence directories.
- **CI floor check** — `defaults/ci/plan-boundary-required-check.yml` (GitHub Actions) verifies that committed boundary manifests are complete; exits 0 gracefully when no manifests are present.
- **`/aid-audit` CI check residual** — `/aid-audit` verifies whether the boundary CI check is installed and explicitly surfaces the residual when it is not.
- **`/aid-init` optional CI check installation** — fresh or upgraded workspaces are offered the option to copy `plan-boundary-required-check.yml` to `.github/workflows/`.
- **Force-override audit enrichment** — `init --force` pre-scans to identify the blocking plan/EPIC and passes `--blocking-epic` / `--blocking-plan` to `fsm_handle_force_override`, writing both to `timeline.jsonl` and `audit-log.jsonl`.
- **13 new bats assertions** — `test-plan-close.bats` (9 tests: missing reports, toggle-skip, audit entry) and `test-ci-floor.bats` (4 tests: no manifests, valid manifest, incomplete manifest, missing delivery).
- **`_aid_read_toggle()` helper** — yq-free toggle detection extracted into a shared function, eliminating duplicated grep chains in `cmd_plan_close` and `fsm_eval_simplifier_present`.

## [2.34.2] — 2026-06-18

### Fixed
- **`plan_diff` evidence truthfulness** — gate runner recorded `result: "pass"` for exit-2 graceful skips (no AC blocks / legacy plan), making `gates_report.json` claim verification happened when it did not; changed to `result: "skip"` so evidence accurately reflects that the gate skipped rather than passed.
- **`review_result` instruction drift** — `role-cards.md` and `gate-fixer.md` still referenced the old nested `review_result.findings[]` contract after the Step 2 canonical-output migration; updated to top-level `findings:[]` per `agents/verifier.md`.

## [2.34.1] — 2026-06-18

### Fixed
- **`yaml_field()` quoted-empty bypass** — `_generated_by: ""` and `_generated_by: ''` returned a non-empty string (the literal quote characters), allowing fabricated empty fields to pass `[[ -z ]]` guards; fixed by stripping surrounding YAML quotes after whitespace trimming so quoted-empty collapses to empty and fails correctly.
- **Verdict whitelist missing** — only `pending` and empty were rejected from verifier output; any other non-standard scalar (e.g. `banana`) passed as a valid completed verdict; fixed by explicit `case` whitelist that accepts only `pass|fail`.
- **`blocking_findings` fail-closed on non-false values** — only exact scalar `true` was blocked; `maybe`, `"true"` (quoted), comment text, and any other non-empty value passed silently as clean; fixed to accept ONLY scalar `false` (after quote-stripping), treating everything else as blocking.
- **`cp4_curator_validation` registry anchor** — source line was `scripts/aid-fsm.sh:283`, actual function start is `:292`; corrected.
- **Enforcement registry seed header** — seed file still claimed "single source of truth / NOT yet promoted"; updated to "SUPERSEDED by E-046-1_3 Step 5" to match reality after promotion.

## [2.34.0] — 2026-06-18

### Added
- **Enforcement registry promoted to `defaults/`** — `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` is now git-tracked and shipped with the plugin; previously it lived only in a gitignored seed file, making it invisible to consumers and untestable in CI.
- **TTL guard for planned enforcement rows** — `scripts/aid-registry-ttl-guard.sh` exits non-zero when a `status: planned` registry row is past its `deadline` without a valid future `deferred_until` date; enforces the "Detector without Enforcement is Decoration" principle (§1) by making planned-but-never-wired items fail CI instead of silently rotting.
- **`deadline` / `deferred_until` / `deferred_by` / `deferred_reason` schema** — per-row TTL fields added to the registry schema so each planned enforcement can state when it must be wired and who deferred it if not yet done; P045 planned rows carry `deadline: 2026-09-30`.
- **`_generated_at` required in verifier output** — `fsm_check_verifier_output` now rejects files missing or empty on `_generated_at`, closing the anti-fabrication gap where a verifier's timestamp could be omitted without FSM consequence; `agents/verifier.md` output spec and the verifier output template updated to match.
- **`cp4_glob_evaluated` audit event wired** — the event was documented in `skills/agent-protocol.md` but never emitted; now emitted by `fsm_check_cp4_curator_validation` before the production-touch check, resolving the ORPHAN verdict in the enforcement registry.
- **Regression tests: cross-plan gate, `_generated_at`, CP4 content-validation, CP5 blocking_findings** — 19 new bats assertions in `test-aid-fsm.bats` (cross-plan E-→P gate, `_generated_at` enforcement, CP4 content), `test-tiered-severity.bats` (CP5 four-case matrix), and the new `test-registry-ttl.bats` (6 TTL guard assertions).
- **`run-all-tests.sh` discovers `bats/test-*.bats`** — the test runner now auto-discovers bats suites in the `bats/` subdirectory in addition to `test-*.sh`, so `test-registry-ttl.bats` and all other bats suites run in CI without manual registration.

### Changed
- **CP4 curator-validation content-validated** — `fsm_check_cp4_curator_validation` previously accepted any file at the expected path; it now routes through `fsm_check_verifier_output` and rejects files missing valid `_generated_by`, `_generated_at`, or `classification` fields.
- **`blocking_findings` reads canonical top-level field** — `done-advance review → release` now reads the auditor's `blocking_findings:` key via `yaml_field` (line-start match only) instead of `grep -ciE` on prose; fail-closed on absent field, immune to false-positives from negations or body text; `agents/auditor.md` output template updated to emit `blocking_findings:` as the first top-level key.
- **Cross-plan init gate fixed for `E-NNN` IDs** — the gate that blocks starting a new EPIC when the previous plan has unreviewed Curator/Auditor findings was silently dead because the plan-prefix derivation used `grep -oP '^P\d+'` which never matched `E-NNN` style IDs; fixed using `BASH_REMATCH[1]` on `E-([0-9]+)`.
- **Enforcement registry ORPHAN rows resolved** — `dispatch_completed_late` removed (unwireable in scope), `cp4_glob_evaluated` promoted to `status: active`, `cp4_template_stale_name` aligned; verdict distribution: ORPHAN 3 → 0, ALIGNED 71 → 73.

### Fixed
- **`test-tiered-severity.bats` fixture broken by fail-closed** — six existing tests that used a minimal `audit-report.md` without `blocking_findings:` now fail the Step 3 fail-closed precondition; fixture `setup()` updated to write `blocking_findings: false` at line-start so the tests exercise their intended provenance logic without triggering the new guard.
- **TTL guard quoted-date regex** — `aid-registry-ttl-guard.sh` regex for `deadline:` and `deferred_until:` now handles `"YYYY-MM-DD"` (quoted) in addition to unquoted values, matching the flow-style YAML format used by the registry.

## [2.33.1] — 2026-06-15

### Fixed
- **docs-writer step ID** — EPIC steps with the `docs-writer` role failed `plan.json` conversion because the role's hyphen broke the `step.id` pattern `^step_[a-z0-9_]+$`; the role is now sanitized (hyphen → underscore) when building the step ID, while `step.role` keeps its canonical hyphenated value, so docs-writer steps convert and dispatch correctly.

## [2.33.0] — 2026-06-15

### Added
- **dispatch_mode selection in /aid-init** — fresh init now asks which dispatch mode to use (agent_tool / inline / subagent) instead of silently writing a default, and re-runs preserve a manually-chosen mode instead of resetting it to `agent_tool` on every run — the silent-reset that caused P043/P044 provenance false-blocks.

### Fixed
- **done-advance critical-finding precondition** — the release precondition now reads the auditor's structured `blocking_findings` verdict instead of grepping report prose for `critical.*security`; the old grep false-positived on negations ("No Critical … security issue") and even on notes describing the false positive, blocking clean releases and pushing users to edit audit evidence to get through.

## [2.32.0] — 2026-06-15

### Added
- **Real-scale Visual Companion mockups** — when building UI on an existing frontend, the companion records the real dimensions (container/column widths, row heights, font sizes, spacing, breakpoints) from the live code and reproduces them 1:1, so a mockup reflects what actually fits on screen instead of an arbitrarily-scaled sketch.

### Changed
- **Visual Companion canvas always white** — the browser companion frame no longer follows OS dark mode (white page background, `color-scheme: light`, dark-mode media query removed), so mockups are always judged on the same white canvas the target UI uses.

### Fixed
- **pre-commit hook shebang** — the generated FSM-guard pre-commit hook had no shebang, so git ran it under `/bin/sh` (dash on Debian) where its bash syntax (`[[ ]]`, `< <(find …)`) failed and blocked every commit, forcing `--no-verify`; it now starts with `#!/usr/bin/env bash` and `/aid-init` retrofits the shebang onto hooks installed before the fix.

## [2.31.0] — 2026-06-14

### Added
- **Whisper transcription via LiteLLM proxy** — voice transcription routes through the LiteLLM AI gateway instead of calling OpenAI directly, so audio spend and routing flow through one gated proxy (D-082 F2).

### Removed
- **Orphaned docs-deploy workflow** — removed the stale Docusaurus deploy CI workflow; the docs were migrated to the central eco docs site.

## [2.30.0] — 2026-06-14

### Added
- **Simplifier + Reporter at Plan Boundary** — two plan-boundary specialist agents run after a plan's last EPIC: the Simplifier proposes reuse/dedup/clarity refinements over the whole plan diff (S/M auto-applied through the gate-fixer → CP4 revert-on-fail rail, L deferred to the PM summary), and the Reporter tests the delivered functionality and writes a plain-language `.aid-o/reports/{plan_id}-delivery.md` from a fixed 7-section template, condensing the Auditor and Curator verdicts and leaving ≥1 on-disk test artifact as anti-fabrication proof. The new `delivery_report_present` compliance check (advisory, severity-routed) verifies the report's presence and on-disk `_test_evidence` at the plan boundary and rides the existing done-advance gate (`null` before the boundary, so it never false-blocks a non-final EPIC). Both agents are config-toggled and inert until a project re-inits.
- **Contributor guide (docs/extending-aid.md)** — a single reference documenting where each enforcement type lives (the type→instruction-home convention), the checklist to add one, the severity-layer vs hard-die FSM precondition patterns, the agent_tool dispatch-mode reality, and the P045 Simplifier + Reporter worked example.

## [2.29.4] — 2026-06-12

### Fixed
- **Force-Path Recovery Alert** — compliance blocks cleared via PM `--force` override never emitted the ✅ resolution alert because the force branch of done-advance skipped the entire P042 recovery block; recovery emission now lives in a shared helper (`fsm_emit_compliance_recovery`) called from both the clean re-run and the force-override paths, so every 🛑 blocked alert is paired with a ✅ regardless of how the block was cleared.
- **aid-init dispatch_mode Template** — the `/aid-init` plugin-discovery step still wrote `dispatch_mode: subagent` into `config/plugin.yaml` on every run, overriding the P043 `agent_tool` default and reintroducing guaranteed `verifier_provenance` false-positive blocks; the template now writes `agent_tool` and the dispatch-mode docs describe all three modes including the false-positive failure class.

## [2.29.3] — 2026-06-12

### Added
- **Check-severity sync guard** — new `test-check-severity-sync.sh` suite fails when a compliance check emitted by the FSM has no entry in `defaults/check-severity.yaml`, closing the trap where an unregistered check silently defaults to advisory and can never block
- **Compliance recovery alert documentation** — pipeline.md §7 now documents the P042 block/recovery Telegram alert pair, the `fsm_done_advance_recovered` dedup marker, and the `alert_on_compliance_recovery` config gate

### Changed
- **Accurate provenance aggregate in agent_tool mode** — compliance.json now reports `provenance_aggregate: "agent_tool"` instead of the misleading `"mixed"` when verifier dispatch runs via the CC Agent tool (non-blocking behavior unchanged)
- **dispatch_mode default single-sourced** — `defaults/orchestration.yaml` `dispatch.mode` is now the single source of the default (`agent_tool`, with all three modes documented); aid-fsm.sh resolves project `plugin.yaml` → plugin `orchestration.yaml` → hard fallback, removing the stale `subagent` doc/code drift
- **FSM internals simplification** — pure-bash `yaml_field()` reader replaces 51 copy-pasted `grep|awk` field reads (~100 fewer process forks per FSM run); repeated-fail counters, CP3 verifier-output evaluation, and the increment-step precondition fail ritual each consolidated into single helpers; shared `die()` moved to `lib/aid-stage-log.sh`; step-verify content checks read the file once; behavior unchanged (all 18 suites + 115 bats tests pass)

## [2.29.2] — 2026-06-10

### Changed
- **Visual Companion — current state mandatory in mockups** — when proposing UI changes to an existing component/page, the companion must always render the current look alongside the proposed changes (side-by-side or inline delta); showing only the new design in isolation is now explicitly prohibited; applies both in the "Read the Code First" refactoring flow and as a general design tip

## [2.29.1] — 2026-06-09

### Fixed
- **verifier_provenance false-positive blocking** — `dispatch_mode` defaulted to `subagent`, which requires `verifier_dispatch_start/complete` timeline events that the CC Agent tool never writes; every EPIC in standard AID self-hosted operation was therefore permanently blocked on `verifier_provenance`; the default is now `agent_tool` (set `dispatch_mode: subagent` in `.aid-o/config/plugin.yaml` to opt into strict interval-bracket provenance enforcement); a new `verify_provenance` branch returns a non-blocking `"agent_tool"` signal so `provenance_aggregate` never escalates to `"unverifiable"` in this mode

## [2.29.0] — 2026-06-07

### Added
- **Compliance recovery alert** — when a `done-advance review→release` succeeds with zero blocking failures for an EPIC that previously emitted a `🛑 release blocked` alert, AID now emits a `✅ compliance cleared, release unblocked` Telegram alert and writes an `fsm_done_advance_recovered` timeline event (dedup marker, observable test signal); controlled by `alert_on_compliance_recovery` config gate (default on)

## [2.28.3] — 2026-06-06

### Fixed
- **Self-referential dependencies** — a step whose dependency range covered its own number (e.g. "Steps 4-6" on step 6) produced a meaningless self-edge that downstream cycle detection rejected; self-references are now dropped during dependency remapping
- **Task-keyword dependencies** — `Depends on: Task N` / `Tasks M-N` lines were silently ignored because the parser only recognized "Step", even though `## Task N:` step headers are accepted; the dependency parser now treats the Task keyword the same as Step
- **Clean-tree guard vs. runtime queue** — the FSM init clean-tree guard aborted on any tracked change including AID's own `.aid-o/config/queue.yaml`, which the auto-pipeline mutates between phases, breaking multi-phase auto runs in projects where that file is tracked; the guard now excludes the runtime queue file
- **/aid-init .gitignore backfill** — `.gitignore` setup skipped the entire AID block when any `.aid-o/` entry already existed, so projects initialized before a later ignore entry (e.g. the runtime queue file) never received it; setup now appends individual missing lines on upgrade

## [2.28.2] — 2026-06-06

### Fixed
- **EPIC dependency renumbering** — when slicing a multi-EPIC plan into per-EPIC files, the Steps table renumbered each EPIC's steps locally (1..N) but the Depends On column kept the plan's global step numbers, producing dangling references like "step 2 depends on 4" in a 3-step EPIC that crashed dependency validation in `aid-epic-to-json.sh`; intra-EPIC dependencies (and the Goal step list) are now remapped to EPIC-local numbering

## [2.28.1] — 2026-06-04

### Fixed
- **FSM force-transition crash** — `aid-fsm.sh transition --force` aborted under `set -u` with "project_root: unbound variable" because `fsm_emit_audit_log` read the variable before its guarded fallback, breaking the manual-override escape hatch
- **CI bash test coverage** — the FSM, release, and integration test suites were silently skipped in CI (no `bats` installed) and had drifted stale against new preconditions; CI now installs `bats`, the four affected suites are repaired, and the FSM precondition layer gained real red/green coverage so it cannot be weakened unnoticed

## [2.28.0] — 2026-06-04

### Added
- **Skill & command authoring standards** — `skill-writing.md` and `command-writing.md` promoted to live skills, with `aid-lint-skill.sh` + `test-skill-lint.sh` enforcing the mechanical subset (pre-existing files grandfathered until revised)
- **Frontend Visual Anchoring enforcement** — `increment-step` hard-fails a frontend step that has `visual_refs` but whose output lacks a `## Visual Anchoring` section

### Changed
- **Model single source of truth** — model tier lives only in `role-cards.md`; removed the conflicting `orchestration.yaml` models block and the phantom `role_assignments` reference
- **role-cards.md holistic unification** — `e2e` is now a real step role with one rich card; `docs` renamed to `docs-writer` everywhere; `qa` gets a full card; structure and footer unified
- **Curator is propose-only** — curator recommends a disposition, the orchestrator applies fixes at every effort (S/M/L), and CP4 reviews the applied changes (reordered to run after the apply)
- **auditor.md overhaul** — scorable A–J categories, corrected scoring math, pre-merge timing
- **planner.md rewrite** — documents the real two-script pipeline (no fictional intelligent planner)
- **Config-policy single-sourcing** — escalation triggers and `skill_conflicts` deduplicated to one authoritative source; pre-filter regexes single-sourced to `pre-filter-rules.yaml`; `not_acceptable` patterns routed to real enforcement or explicitly marked advisory

### Fixed
- **Verifier provenance false-positives** — interval-bracket window replaces the ±60s test that flagged honest runs; fails closed when the severity registry can't be read; renamed the verdict to the honest `unverifiable` and added an explicit anti-fabrication instruction to the orchestrator
- **aid-run.md fiction + task→epic terminology** — removed non-existent state transitions / branch / merge-target claims
- **role_overrides downgraded to advisory** — the global `Bash(*)` permission made per-role scoping non-enforcing; the false security claim was removed
- **deserialize_dangerous pre-filter rule** — a `(?!_safe)` lookahead (unsupported by bash ERE) made the rule silently never match; rewritten ERE-safe
- **Honest phase-end note** — `run-management.md` no longer claims the controller auto-enforces the PM-GO boundary

### Removed
- **Unread config** — `orchestration.yaml` `models:` block and `release.skip_when`, and the `execution.yaml` global `retry:` block — read by nothing (per-gate `max_retries` is the only retry knob)

## [2.27.0] — 2026-06-02

### Changed
- **FSM state file unified to `fsm-state.yaml`** — retired the parallel `state.yaml` step-array that `aid-epic-to-json.sh` wrote but nothing read; every script, doc, template, and test now refers to the single FSM state file `fsm-state.yaml`, with the legacy `state.yaml` name kept only as a read fallback for in-flight pre-migration runs.

### Fixed
- **`/aid-stop` + `/aid-run --resume` state handling** — `/aid-stop` dropped the invented `session.*` schema, now reads the real `fsm-state.yaml` fields and logs the stop event through the canonical timeline helper; `--resume` reads `fsm-state.yaml`.

### Removed
- **Queue `pause` / `resume` / `reorder` subcommands** — removed from `/aid-status` and help; documented but never backed by any script (archived, restorable).

## [2.26.0] — 2026-06-01

### Changed
- **Documentation hygiene** — stripped version-stamped headings (e.g. `(NEW v2.16.0 — P032)`) from pipeline.md, agent-protocol.md, and related skills/commands; refreshed stale `Last Updated` dates; reconciled the brainstorming severity-enum claim and the aid-status `{epic_id}` naming drift.

### Fixed
- **aid-help level detection** — counted `state: DONE` in `state.yaml` (never written by the FSM), so every user showed Level 0; now reads `fsm-state.yaml`.
- **aid-init pre-push hook docs** — clarified pre-push uses its own marker `AID-ORCHESTRATOR-PREPUSH-START` (not the pre-commit marker), preventing duplicate hook blocks on re-run.
- **CP4 curator-validation filename** — verifier-output-template + verifier.md now name the FSM-required `verifier-output-cp4-curator-validation.md`; corrected the false "FSM does NOT enforce" note.
- **implementer model selection** — replaced the duplicated, incomplete model-tier list with a pointer to role-cards.md (single source of truth covering all roles).
- **brainstorming prior-work scan** — globbed nonexistent `.aid-o/epics/`; now `.aid-o/tasks/`.

### Removed
- **aid-research command + knowledge/Context7 layer** — removed the never-wired on-demand research command, its knowledge-base template, the integrations `knowledge:` config, the `context_scope.knowledge` plan-schema flag, and all orphaned Context7 references; archived to `docs/plans/AID-audit-2026-06/removed/` (restorable). The layer had no producer wired and no consumer.

## [2.25.0] — 2026-05-31

### Added
- **aid-emit-dispatch.sh wrapper** — new bash CLI with `start` and `complete` subcommands the orchestrator MUST call before/after every `Agent({subagent_type, prompt})` dispatch; writes `verifier_dispatch_start`/`_complete` events to timeline.jsonl plus tracks state in pending-dispatches.jsonl per evidence dir.
- **fsm_check_orphan_dispatches function** — reconciliation backstop in cmd_increment_step that refuses step transitions when pending-dispatches.jsonl shows a start event older than expected_duration_max without matching complete.
- **fsm_check_cp4_curator_validation function** — precondition in cmd_done_advance review→release that requires verifier-output-cp4-curator-validation.md when curator-report.md exists and any commit in `base_commit..HEAD` range touches production code paths. Mode-aware: skips with `cp4_skipped_streamlined_advisory` audit event when streamlined_mode is true.
- **fsm_check_streamlined_integration_review function** — precondition in cmd_done_advance review→release that, when streamlined_mode is true, requires all three of `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`, `gates_report.json` present in the evidence dir.
- **fsm_check_streamlined_abandoned function** — abandoned-but-shipped detector in cmd_done_advance that fires when streamlined_mode is true and timeline.jsonl has fewer than 3 events.
- **--streamlined CLI flag in cmd_init** — first-class lightweight execution mode that writes `streamlined_mode: true` into fsm-state.yaml and propagates through cmd_increment_step / cmd_done_advance / write_compliance_json.
- **coverage_mode + skipped_dimensions fields in compliance.json** — honest accounting of which dimensions were intentionally skipped per the streamlined contract. Field name `coverage_mode` (not `mode`) avoids collision with the existing fsm-state.yaml `mode` (manual/auto execution mode).
- **Four blocking checks in defaults/check-severity.yaml** — `dispatch_orphan_complete`, `cp4_curator_validation`, `streamlined_abandoned`, `streamlined_integration_review`, all severity blocking per AID-v3-principles.md §1 with explicit PM promotion (NR 8-14 empirical evidence across 4 projects).
- **cp4_production_paths field in defaults/execution.yaml** — configurable glob alternation for CP4 trigger detection; `/aid-init` stack-scan in `scripts/lib/aid-init-execution-yaml.sh` auto-populates project-specific defaults.
- **aid-json-to-run.sh Step 18 auto-init** — calls `aid-fsm.sh init` after run.md generation when fsm-state.yaml is absent, eliminating state.yaml vs fsm-state.yaml confusion (NR 10/12/14 anchor). Accepts a `--streamlined` passthrough (threaded from `/aid-run --streamlined` and `aid-auto-pipeline.sh`) that forwards to `cmd_init` so the auto-initialized state carries `streamlined_mode: true` — without it the streamlined activation switch would be unreachable.
- **test-aid-emit-dispatch.bats** — eleven fixtures: the original eight (start-only, start+complete pair, orphan complete, ceiling clamp, concurrent flock, missing output_file, malformed agent_id, inode-swap race) plus three CP3-security fixtures (`--focus` injection rejected by allowlist, jq-escaped pending construction, per-start nonce prevents ledger double-clear).

### Changed
- **cmd_increment_step preconditions** — added Component B orphan-dispatch backstop after the existing memory_used/memory_written/verifier_output checks; conditionally skips the per-step verifier_output check when streamlined_mode is true.
- **cmd_done_advance review→release preconditions** — added Component D streamlined_integration_review check, streamlined_abandoned check, and Component C CP4 enforcement (mode-aware in streamlined); all wired before the existing curator-report check; cites AID-v3-principles.md §1.
- **write_compliance_json schema** — emits top-level coverage_mode and skipped_dimensions fields; backward-compatible (legacy compliance.json without these reads as coverage_mode "full", skipped_dimensions []). The `mode` → `coverage_mode` rename is a breaking change for any downstream consumer that read the v0 draft.
- **fsm-state.yaml unified schema** — absorbs the legacy state.yaml steps[] array; backward-compat dual-file reader preserved.
- **skills/pipeline.md** — new §4 Dispatch Protocol subsection documenting the mandatory aid-emit-dispatch.sh wrapper chain; PRE-FLIGHT auto-init note.
- **skills/agent-protocol.md** — reference tables for the new audit events and check-severity entries.
- **commands/aid-run.md, commands/aid-plan.md, commands/aid-do.md** — --streamlined flag documentation and advisory trigger criteria.

## [2.24.0] — 2026-05-31

### Added
- **FSM Artifact Templates (`step-verify-template.md` + `verifier-output-template.md`)** — two new templates in `defaults/templates/` document the exact section/field schema enforced by `aid-fsm.sh` preconditions. `step-verify-template.md` lists the six required sections (Acceptance Criteria with `- [x]` checkboxes, Commit with 7+ hex SHA, Memory Used, Memory Written, Files, Result: PASS) each annotated with the failing `cmd_increment_step` reason. `verifier-output-template.md` is a single file covering all four CP variants (CP2 per-step, CP3 code-review, CP3 security, CP4 curator) with line-start `_generated_by:` / `classification:` / `verdict:` fields tied to `fsm_check_verifier_output`. Empirically motivated: WAN P027 EPIC 1 had 11 FSM precondition failures (5 from undocumented step-verify schema, 3 from undocumented `_generated_by` schema) while EPIC 2 had 0 — proving the schema is learnable, so it should be documented up-front rather than discovered through failure (NR 10 §4D, NR 12 §4A, NR 14 RC1).

### Fixed
- **`aid-plan-to-epic.sh` step counter fenced-block bug** — parser regex `^###?[[:space:]]+(Step|Task)[[:space:]]+([0-9]+)` previously matched `### Step N:` headers inside fenced code blocks, so any plan *about AID itself* that quoted AID step syntax got mis-counted and the pipeline crashed with `objective too short` errors. Fix tracks fence depth (toggle on lines matching `^[[:space:]]*````) across four scan sites: `has_impl_steps` awk quick-check, main step-numbering while-loop, `extract_step_content()` awk helper, and the objective-fallback awk. `aid-epic-to-json.sh` confirmed unaffected (parses EPIC table rows, not plan.md headers). New `test-aid-plan-to-epic-fence.bats` fixture reliably fails pre-fix and passes post-fix. Empirical anchor: AID-self P039 (v2.23.0 brainstorming plan) tripped this bug — NR 14 §4D.
- **`defaults/policies/permissions.yaml` stale MCP refs (action required: re-run `/aid-setup permissions`)** — the autonomous preset whitelist referenced MCP servers that no longer exist in current eco infrastructure: `qdrant-memory__*`, `shared-docker__*`, `shared-minio__*`, `shared-postgres__*`, `shared-playwright__*`, `shared-telegram__*`. Replaced with the actual running set: `vulcan-memory__{find,store,list}` (excluding destructive `vulcan-delete`), `eco-admin__*` 12 GREEN read-only tools (YELLOW writes intentionally excluded — require Telegram approval per ADR-17 D-077), `claude_ai_Google_Drive__*` 6 read-only ops. Kept `shared-github`, `shared-sequential-thinking`, `svc-mcp-tg-bot__send_message`, `plugin_context7_context7`, and `qdrant-brain` (back-compat with `skills/memory-mcp.md` contract). Playwright explicitly NOT auto-allowed — opt-in via per-project `settings.local.json`. Empirical anchor: NR 11 manual audit. **Existing projects that already ran `/aid-setup` retain stale entries in their local `.claude/settings.local.json` and should re-run `/aid-setup permissions` to refresh.**

## [2.23.0] — 2026-05-31

### Added
- **Section-Review Validate-Then-Verify** — brainstorming Step 6 sections now run a Sonnet `section-review` critic followed by an Opus ground-truth re-grep, presenting the PM a claim-verification table (validator claim → real command + output → ✓/✗) before approval; Step 7 adds a `cross-section-review` consistency check over the assembled plan.

### Fixed
- **Verifier focus card naming** — the `security-review` card in `role-cards.md` is renamed to `security` to match the canonical focus name used plugin-wide (orchestration tier, CP3 dispatch, planner, aid-run, epic templates); resolves a latent card-name mismatch with the registry.

## [2.22.3] — 2026-05-14

### Fixed
- **`skills/brainstorming.md` references to renamed visual-companion path** — v2.22.1 moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` but left two stale `skills/visual-companion.md` references in `brainstorming.md` (lines 107 and 258). The `test-instruction-consistency` bash suite caught it (`✗ Referenced file MISSING`) and CI went red since v2.22.1's push. Both references updated to the directory form.

## [2.22.2] — 2026-05-14

### Changed
- **Visual Companion — explicit remote-host networking + read-first-before-redesign rule** — Standalone Invocation Step 3 now mandates picking server bind mode (`127.0.0.1` for local agent / `0.0.0.0 --url-host <IP>` for remote SSH-VPN setup) BEFORE starting the server, with detection cues (`$SSH_CONNECTION` env, `hostname -I`) and a direct ask-PM fallback. Previously the remote case was a buried footnote, leaving the agent to start a loopback-only server that PM's browser couldn't reach. Plus new "Refactoring or Redesigning Existing UI — Read the Code First" section: when PM references an existing component / screenshot / page name, agent MUST ask "should I read the current implementation first?" and produce a structured data-inventory in chat before any mockup. Saves the iteration cycles where mockups get drawn against guessed data shapes and need full rewrite after the real component is read.

## [2.22.1] — 2026-05-13

### Fixed
- **Visual Companion skill discovery (hotfix v2.22.0)** — moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` directory structure. Claude Code's plugin loader only recognizes skills as user-invokable (slash-callable) when they live in `skills/<name>/SKILL.md` form; flat files are loaded for in-plugin reference but never registered as `/<name>` slash commands regardless of any `user_invocable` frontmatter flag. v2.22.0 release flipped the flag and added the standalone section but kept the flat-file shape, so `/visual-companion` did not appear in the command palette. This release fixes the structure only — no content changes.

## [2.22.0] — 2026-05-13

### Changed
- **Visual Companion skill is now user-invocable** — `/visual-companion` slash command opens a standalone demo session for verifying the browser round-trip (server start, HTML push, click capture, events read) without going through the full `/aid-plan brainstorm` flow. Skill frontmatter flipped `user_invocable: false → true` and a new "Standalone Invocation" section was added with explicit start/stop steps, npm-install first-run handling, and node_modules fallback path. Skill remains backward-compatible with the existing brainstorming integration — per-question gate behavior inside `/aid-plan brainstorm` is unchanged.

## [2.21.1] — 2026-05-13

### Fixed
- **`try_telegram_alert` test-mode guard** — `AID_TEST_MODE=1` env var short-circuits the helper before any `jq` or `curl` invocation, so bats fixtures and smoke tests no longer fire real-world Telegram alerts. Discovered post-P038 ship: cmd_done_advance blocking precondition (Step 3) and 3 other call sites previously emitted ~30 alerts during fixture development with `E-TEST-038: 1 blocking compliance failure(s)`. Shared bats `setup_test_evidence_dir` (test-helpers.bash) and `test-tiered-severity.bats` `setup()` now export the guard. Convention: any future side-effect helper (mail/Slack/webhook) should mirror this pattern.

## [2.21.0] — 2026-05-13

### Added
- **Tiered severity registry** — `.aid-o/config/check-severity.yaml` declares each compliance check as `blocking` or `advisory`; shipped by `/aid-init` with initial bootstrap per AID-v3-principles.md §1
- **`failures[]` array in compliance.json** — every release writes per-check failure entries with severity, evidence, and promoted_at, enabling deterministic blocking decisions
- **`aid-fsm.sh promote-check`** — explicit advisory→blocking promotion with mandatory ≥20-char reason and forensic audit-log entry
- **`aid-fsm.sh check-promotion-candidates`** — read-only scan of audit-log.jsonl identifying advisory checks that meet the AID-v3-principles.md §1 promotion criterion (force_override_rate < 0.05 across N≥5 EPICs)
- **`aid-promote-checks.sh`** — PM-facing markdown report wrapping the candidate scan
- **`test-tiered-severity.bats`** — 6 fixtures covering blocking-blocks, advisory-passes, --force-with-audit, short-reason-rejection, promote-check, and candidate identification

### Changed
- **`cmd_done_advance review→release`** — now refuses transition when any compliance failure has `severity: blocking`; structured error message includes per-failure evidence and copy-paste `--force --reason --blocked-checks` override snippet; per AID-v3-principles.md §1 "Detector without Enforcement is Decoration", this is the first concrete application of the principle and closes the P026 (WAN, 2026-05-13) failure mode
- **`fsm_handle_force_override`** — accepts new `--blocked-checks "<comma-list>"` flag; propagates to both timeline.jsonl and audit-log.jsonl
- **`aid-audit-log.sh cmd_append`** — new `--<key>-array "a,b,c"` flag-suffix convention emits JSON arrays in output entries; dash-to-underscore JSON key normalization for compatibility
- **`pipeline.md §7 DONE State`** — new "Tiered Severity Enforcement" sub-section documenting the override flow, the severity table, and the promotion ceremony
- **`write_compliance_json`** — populates `failures[]` array using check-severity.yaml registry; backward compatible (empty array when no failures)

## [2.20.2] — 2026-05-12

### Added
- **Plan-AC Diff Gate (P037 Phase 2, AID-010)** — new deterministic gate `plan_diff` in `execution.yaml` runs `aid-plan-diff.sh` after EXECUTE→GATES. Script parses plan-level `## Acceptance Criteria` section, executes each `verification_pattern` (3 types: `cmd`, `must_not_exist`, `must_contain` with any-match regex semantics) against codebase HEAD, emits `plan-diff.json` with per-AC verdict. Fail if ≥1 AC absent.
- **`aid-plan-diff.sh` Standalone Script** — new 281-line bash script under `plugins/aid-orchestrator/scripts/`. Standalone testable lifecycle (own provenance fields `_generated_by: aid-plan-diff.sh@v2.20.2`, own timeline events `plan_diff_start`/`plan_diff_complete`). 4 exit codes: 0 (all present), 1 (≥1 absent), 2 (graceful skip — Fast Mode or no AC section), 10 (input validation).
- **Plan Template AC Block** — `defaults/templates/plan.md` extended with `## Acceptance Criteria` section template using executable `verification_pattern` blocks (3 example patterns: cmd, must_not_exist, must_contain). New plans (P038+) gain plan-level AC verification by default.
- **Completeness Gate Sub-Check #20** — `plan-writing.md` Completeness Gate added 3 sub-rules (20a/20b/20c) enforcing `verification_pattern` block on every AC for new plans; legacy plans (P001-P036) without AC section skip the check (no violation). EVALUATION counter updated `out of 24` → `out of 27`.
- **`compliance.json plan_ac_match` Dimension** — `evaluate_compliance_checks` reads `plan-diff.json`, sets `checks.plan_ac_match: true | false | null`. False forces `compliance.overall: "fail"`; null = graceful skip for legacy plans or missing plan-diff.json.
- **`{plan_path}` Placeholder Token** — `aid-run-gates.sh` `resolve_placeholders()` helper substitutes 4 known tokens (`{plan_path}`, `{epic_id}`, `{run_id}`, `{base_commit}`) in gate commands via bash parameter expansion. `cmd_init` writes `plan_path:` field to state.yaml (realpath-normalized absolute path or literal `null` for Fast Mode EPICs). Unknown `{<token>}` triggers fail-loud exit — silent pass-through is a debug trap.
- **Plan-AC Diff Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-plan-ac-diff.bats` (8 tests covering all 3 pattern types, fail path, Fast Mode null + empty, legacy skip, resolve_placeholders + cmd_init replicas). Full bats suite now 52/52 ok.

### Changed
- **`aid-run-gates.sh` Gate Command Resolution** — gate commands now pass through `resolve_placeholders()` before `bash -c` execution. Exit code 2 counts as pass when gate's `pass_criteria` mentions "exit 2" (graceful-skip pattern).
- **`defaults/execution.yaml`** — legacy `{base}..HEAD` tokens in `docs_updated` gate renamed to `{base_commit}..HEAD` (aligning with `scope_check` convention; required for resolve_placeholders fail-loud safety). New `plan_diff:` gate entry appended after `scope_check:` (required: true, max_retries: 0, pass_criteria documents exit 0 or exit 2).

### Fixed
- **Goalpost Shift Detection** — Five EPICs (P019 F1+F2 frontend migration, P021 F4 backlog collision, P022 F6 Playwright→backend substitution, P023 F7 five concurrent shifts) previously passed to DONE without detection because gates didn't check plan AC reality vs implementation. Phase 2 `plan_diff` gate catches this class — every new plan with `verification_pattern` blocks gets per-AC executable verification on codebase HEAD before GATES→DONE.
- **`cp2_per_step_provenance` Type Mismatch (IMP-100)** — backfill in `aid-compliance-backfill.sh` previously wrote scalar string `"unknown"` for `cp2_per_step_provenance`, while the live writer in `aid-fsm.sh evaluate_compliance_checks` emits a JSON array (one entry per CP2 step). Type drift created silent correctness risk for queries doing `| length`. Backfill now writes `["unknown"]` (single-element array) to match live writer shape. Other 3 fields (cp3_*, provenance_aggregate) remain scalar — consistent with live writer.
- **`backfill_provenance` Silent Error Conflation (IMP-102)** — previously returned exit 1 for both "already-present skip" (normal) and "jq failure" (corrupted compliance.json). Step C caller incremented skip-count for both, masking real errors. Function now returns 0 (fixed), 1 (jq failure with stderr WARN), 2 (idempotent skip); caller case-statements on exit code and reports backfilled/skipped/errors separately in summary heredoc.
- **`verify_provenance` Unused `step_n` Parameter (IMP-103)** — `$3` was received in signature but never referenced in body. Renamed to `_step_n` with code comment explaining intentional retention for future per-step forensic attribution. Positional API stable (no call-site changes needed).
- **CLI Dispatcher Help Message Clarity (IMP-104)** — `aid-stage-log.sh` dispatcher previously listed `log_event`, `log_info`, `log_warn`, `log_error` uniformly in help text, leading users to expect timeline writes from all four. Comment + help message now distinguish: only `log_event` writes to timeline; `log_info`/`log_warn`/`log_error` are stderr-only severity-prefixed echoes.
- **`aid-fsm.sh` Missing `BASH_SOURCE` Guard** — top-level case dispatcher previously exited 1 on unknown args even when the file was sourced (e.g. from bats test fixtures), killing the test process. Dispatcher now wrapped in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` (same pattern as `aid-stage-log.sh` fix from v2.20.1). Sourcing for testing purposes works cleanly. Existing `_load_aid_fsm` shim in `test-anti-fabrication.bats` becomes redundant but harmless.

## [2.20.1] — 2026-05-12

### Added
- **Verifier Provenance Verification (P037 Phase 1, AID-038)** — `aid-fsm.sh evaluate_compliance_checks` cross-references each `verifier-output-*.md` `_generated_by` field against `timeline.jsonl` `verifier_dispatch_start`/`_complete` events within a ±60s window for subagent mode, or validates `main-context@<commit-sha>` format with SHA verification for inline mode. Detected fabrication forces `compliance.overall: "fail"`.
- **Timeline Dispatch Events** — `pipeline.md` now instructs LLM to emit `verifier_dispatch_start` and `verifier_dispatch_complete` events with payload `{agentId, focus, step_n, evidence_dir, ts}` around every CP1/CP2/CP3 verifier `Agent()` call.
- **Honest Mode for No-Subagent Projects** — `.aid-o/config/plugin.yaml` new field `dispatch_mode: subagent | inline` (default subagent). Inline mode requires `_generated_by: main-context@<git-HEAD-sha>` format for verifier outputs; compliance check validates format + SHA existence rather than timeline match.
- **CLI Dispatcher for aid-stage-log.sh** — library now supports `bash aid-stage-log.sh <fn> <args>` invocation in addition to existing source-mode usage. Guard via `BASH_SOURCE[0] == ${0}` keeps source-mode behavior unchanged. Required so `pipeline.md` and `aid-plan.md` LLM-rendered docs can invoke `log_event` directly without a separate source step. Unknown function exits 1 with stderr help message listing available functions.
- **Anti-Fabrication Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-anti-fabrication.bats` (4 tests): verified subagent dispatch produces `provenance_aggregate: all_verified`; missing timeline events produce `fabricated` + `overall: fail`; inline mode with valid SHA produces `all_inline` + `pass`; CLI dispatcher regression test.

### Changed
- **`evaluate_compliance_checks` Schema** — `verifier_outputs` object now carries three new `*_provenance` fields (`cp2_per_step_provenance`, `cp3_code_review_provenance`, `cp3_security_provenance`) plus aggregate `provenance_aggregate: "all_verified" | "all_inline" | "mixed" | "fabricated" | "unknown"`. Pre-Phase-1 compliance.json files backfilled via `aid-compliance-backfill.sh` Step C (idempotent merge, adds `provenance: unknown` audit note attributing the migration to P037).

### Fixed
- **Compliance Telemetry Honesty** — post-Session-B telemetry (n=8 EPICs reporting 100% pass on all 4 dimensions) was previously vulnerable to fabricated `_generated_by` metadata. P023 reflection (NR 5, 2026-05-11) documented one such case in WAN project where agent wrote verifier outputs in main context but signed them as `aid-orchestrator:verifier@cp{2,3}-*`. Phase 1 enforcement detects this class of cheating.
- **`verify_provenance` TZ Bug** — jq <1.7 silently honors local TZ in `fromdateiso8601` even with `Z` suffix, producing a 1-hour offset on non-UTC hosts (CEST/PST/etc) and reading every dispatch as fabricated. Both `jq -s` invocations in `verify_provenance()` are now prefixed `TZ=UTC` so date parsing matches the `date -d`-derived `$min`/`$max` UTC epochs. Surfaced by Step 5 bats smoke test on CEST host.

## [2.20.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Check 17e (CLI Invocation Grounding)** — `plan-writing.md` Completeness Gate extended with 7th grounding category: for every cited `bash <script> <args>` in Implementation Detail blocks or step examples, verify the args against the actual script interface via `<script> --help` (preferred) or `head -100 <script>` (fallback). Mismatched signatures → REVISE_REQUIRED with suggested correction. Empirical: P035 C1 (2026-05-10) — plan cited a `--state-file` flag that did not exist in `aid-run-gates.sh` at write time; CP1 caught it on the 2nd pass.
- **Completeness Gate Check #19 (Design Defeat Detection)** — semantic LLM check active for plans with `type: bug-fix` in frontmatter. Reviewer answers Q1 (which precondition is being fixed?), Q2 (does the new code-path go through that same precondition?), Q3 (if not, is the bypass explicit + justified?). Q2:no + Q3:no → REVISE_REQUIRED. Pre-screening heuristic (mechanical) auto-activates #19 when goal/context contains fix/fail/bypass/precondition/validation AND the plan mutates `fsm-state.yaml` or `state.yaml` directly without a `cmd_<wrapper>` invocation. Heuristic explicitly EXCLUDES release/version mutations (CHANGELOG, README, marketplace.json, plugin.json, files in `release-policy.yaml` `version_files[]`) to prevent false positives on release plans. Empirical: P035 C2 — `yq -i '.state = "GATES"'` bypassed `cmd_transition()` and would have silently defeated the fix's own purpose.
- **Plan Type Taxonomy (`type:` frontmatter field)** — `defaults/templates/plan.md` now defines an enum `type: regular | bug-fix | refactor | docs` controlling which Completeness Gate checks activate per plan type. Default if missing: `regular`. Legacy `type: plan` (P001-P035 convention) treated as alias for `regular` — no migration required. Documented in new `## Plan Type` template section with a 4-row activation table.
- **`/aid-plan write` Mode Step 9 (CP1 Plan Quality Review)** — write mode extended from 8 to 9 steps; Step 9 mirrors brainstorm Step 9 (verifier dispatch with `docs-review` focus, codebase grounding pass, save review to `.aid-o/work/cp1-review-{plan_id}.md`). Activates #19 when `type: bug-fix` or pre-screening matches. Skip via `review_checkpoints.cp1_plan_review: false`. Closes the gap where plans written through `/aid-plan write` previously had no post-write quality review.
- **CP1 Verifier EVIDENCE REQUIREMENT** — Step 9 verifier prompt now requires concrete evidence (`command_run` + `output_excerpt`) before marking ANY item VERIFIED. Missing evidence → REJECTED with auto-retry; max 2 retries then ESCALATION. Applies to all #17 sub-checks + 17a-d + 17e + #19 (Q1/Q2/Q3 must cite plan path:line + codebase path:line). Empirical: P035 C3 — three bats helpers cited as "existing" from memory; none existed.
- **`test-plan-quality-enforcement.sh` Smoke Test** — bash smoke test exercising all 4 enforcement layers against a deliberately-defective fixture plan: layer 1 (extract `bash <script> --flag` + verify against real interface, with SKIP for already-shifted baseline), layer 2 (3-conjunctive heuristic positive + release-mutation negative control), layer 3 (count `^9.` in Mode: Write Plan section), layer 4 (header + field-name hits for EVIDENCE REQUIREMENT). Auto-discovered by `run-all-tests.sh`.

## [2.19.1] — 2026-05-10

### Fixed
- **`aid-release.sh` CHANGELOG-rename anomaly (IMP-093)** — observed 3× across v2.18.3 + v2.19.0 releases: when a `## [X.Y.Z]` header was pre-written for the upcoming release (PM/agent edited CHANGELOG before invoking script), the previous logic did a blind `sed`-replace on the newest header and silently collapsed the pre-written entry's history. Fix: detect actually-released version from `plugin.json`/`marketplace.json`/`package.json` (not CHANGELOG header) and route through new `update_changelog` helper that has 3 branches: (a) header matches new_version → skip rename (entry already correct), (b) header matches released version → bump existing header (existing behavior), (c) header is some other version → prepend new entry above (preserves history). 3 new bats assertions in `test-aid-release.bats` cover all 3 branches.

### Notes
- **README regex pattern mismatch** — second part of IMP-093 diagnosis showed that `.aid-o/config/project.yaml` regex patterns like `"Plugin: {VERSION}"` don't match actual content `**Plugin:** 2.X.Y` (markdown bold prefix missing in pattern). Consumer projects must update their `.aid-o/config/project.yaml` regex patterns to escape `**` for sed: e.g., `"\\*\\*Plugin:\\*\\* {VERSION}"`. This repo's `.aid-o/config/project.yaml` (gitignored) was updated locally; downstream projects need to edit theirs once if affected.

## [2.19.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Checks 17a–17d** — `plan-writing.md` Completeness Gate extended with 4 new grounding categories aimed at empirical gaps from P019/P021/P032: (17a) backlog ID grounding via whole-plan `\bT-[0-9]+\b` regex + `git log --since="24 hours ago" --grep` — empirical: P021 T-132/T-133 reserved by commit 1907e77 same morning; (17b) test directory convention via POSIX `find tests/ -type f -name "*<basename>*"` — empirical: P021 plan said `tests/integration/`, reality `tests/unit/`; (17c) DB-field semantics via `[A-Z][a-zA-Z]+\.[a-z_]+` regex + `grep` on models.py for stored Column vs `@property`/computed — empirical: P021 assumed automatic, reality stored Column; (17d) file removal grounding via `ls <path>` existence check — empirical: P019 `must_not_exist` file actually existed at EPIC end. EVALUATION counter bumped 18 → 22.
- **`commands/aid-plan.md` Step 9 Verifier Prompt Extension** — verifier dispatch prompt extended with extraction patterns and verification commands for the 4 new grounding categories. Each category gets explicit VERIFIED/ABSENT semantics and REVISE_REQUIRED conditions. Backlog ID ABSENT accepts "T-NNN to be allocated at plan-write time" as a plan-allocation candidate.
- **`defaults/templates/plan.md` Resources Verification Block** — new section between Constraints and Risks with 12 checkbox items: 6 (Existing Resources from #17) + 4 (Plan Assumptions from #17a-d) + 2 (Resolution gates). Auto-populated by `/aid-plan` Step 9 verifier dispatch; PM-visible manual review checklist. Detection scope clarified as whole-plan body scan — no `related_backlog` or similar field required.
- **`test-cp1-grounding.sh` Smoke Test** — bash smoke test that constructs a deliberately-broken plan with violations across all 4 sub-checks and verifies extraction patterns produce correct outputs. POSIX-only (`command -v find` guard, no `fd` dependency), trap-cleaned tmpdir, 5 PASS branches.

## [2.18.3] — 2026-05-10

### Added
- **`aid-fsm.sh advance-to-gates` Atomic Command** — single command runs gates and routes through `cmd_transition EXECUTE GATES` on success. Eliminates the `gates_no_generated_by` chicken-egg precondition fail (P020 8×, P021 4× — 12 friction events across 3 EPICs). Atomicity: state changes only on full success; gates failure leaves state at EXECUTE (never modified). No new state added — `VALID_STATES` and `VALID_TRANSITIONS` unchanged. Single source of truth for preconditions remains `check_preconditions` (`_generated_by`, `fsm_check_verifier_output`, `fsm_check_grandfather`).
- **Bats Coverage for advance-to-gates** — `test-aid-fsm.bats` expanded from 14 to 18 assertions covering all branches: success path, gates-fail path (state stays EXECUTE), missing CP3 outputs (cmd_transition rejects after gates pass), and aid-run-gates.sh env-var bypass behavior with and without `AID_GATES_TRIGGERED_BY_FSM=1`. New `test-helpers.bash` helpers: `seed_test_state_files`, `setup_passing_execution_yaml`, `setup_failing_execution_yaml`, `write_valid_verifier_output`.

### Changed
- **`aid-run-gates.sh` State Guard** — accepts env-var bypass `AID_GATES_TRIGGERED_BY_FSM=1` as the signal that the caller is `cmd_advance_to_gates`. Strict equality check (`=="1"`) prevents accidental bypass via truthy values. Manual two-step flow (state==GATES + run-all without env var) remains fully backward-compatible. Error message now hints at the atomic `advance-to-gates` alternative when state==EXECUTE without the env var.
- **`pipeline.md §5 GATES State`** — adds Recommended Flow (v2.18.3+) subsection documenting `aid-fsm.sh advance-to-gates`; preserves Manual Two-Step Flow subsection for debugging and crash recovery. Both flows fully documented with semantics, env-var signal, and timeline events.

### Fixed
- **`gates_no_generated_by` Precondition Fail Class** — empirical motivation for the atomic command: P020 had 8 such failures, P021 had 4 — 12 friction events across 3 EPICs from a single root cause (chicken-egg between gates runner state guard and transition's `_generated_by` check). Target post-deploy: 0 fails of this type.

## [2.18.1] — 2026-05-09

### Fixed
- **`aid-diagnostic.sh` 3 bugs** — (1) Branch hygiene now reads from `fsm-state.yaml` instead of `state.yaml` (which is the JSON steps array and has no `branch:` field); was reporting 88–100% "missing" for all projects. (2) Deploy era loop adds `post-session-b` so post-Session-B EPICs appear in the era distribution table — were previously silently dropped. (3) `collect_precondition_fail_reasons` → `collect_fsm_fail_reasons` extends jq filter to capture `fsm_increment_fail` and `fsm_done_advance_fail` in addition to `fsm_precondition_fail`; was missing 52% of all FSM fail events (the dominant category: `verify_no_*` format-discovery failures).

## [2.18.0] — 2026-05-08

### Added
- **CP2 Per-Step Verifier Pre-Filter** — `aid-prefilter.sh` classifies each step's git diff as `SKIP` (docs/config/test only, exit 0), `RUN` (code changed, exit 10), or `FAIL` (hardcoded secret/credential detected, exit 20). `cmd_increment_step` reads the classifier verdict and refuses to advance past a FAIL classification; SKIP bypasses CP2 verifier dispatch entirely. `pre-filter-rules.yaml` holds the rule set (docs patterns, secret patterns, code extensions). Closes the CP2 dead-weight problem where verifier was dispatched on pure-docs commits, burning tokens with no signal.
- **CP3 Integration Review Enforcement** — `EXECUTE→GATES` precondition now requires both `verifier-output-cp3-code-review.md` and `verifier-output-cp3-security.md` to exist in the evidence dir. Previously the transition was gated only on `current_step >= total_steps`. Missing CP3 outputs produce a specific precondition failure message listing which files are absent.
- **`fsm_handle_force_override` Unified Dispatcher** — replaces 4 inline `--force` bypass blocks with a single `fsm_handle_force_override from to reason state_file timeline_file` function. Validates `--reason` length ≥ 20 chars (short reasons rejected with exit 1 before any state mutation), emits `fsm_force_override` timeline event, writes to `aid-audit-log.sh` audit trail. Consistency: all force paths now go through identical logging — no more "force but no timeline event" edge cases.
- **`aid-audit-log.sh`** — standalone append-only audit log writer (`aid-audit-log.sh append <evidence_dir> <event_type> <json_payload>`). Writes to `evidence/{epic}/{run}/audit-log.jsonl`. Used by `fsm_handle_force_override` and available for future audit-requiring commands.
- **Verifier Nuanced Deprivation Context** — `agents/verifier.md` updated with classification-aware dispatch: verifier receives pre-filter classification + the specific diff that triggered RUN so it can focus on the actual change rather than the full step output. Adds step-level `## Memory Used` / `## Memory Written` enforcement to verifier output schema.
- **Compliance `verifier_outputs` Object Schema** — `compliance.json` now records per-step CP2 outcomes as an object (`{step_N: {classification, verdict, ts}}`). `evaluate_compliance_checks` validates presence and structure. `write_compliance_json` populates the field from step-verify evidence.
- **Compliance `deploy_era` Three-Tier Field** — `compliance.json` carries `deploy_era: pre-session-a | post-session-a | post-session-b` based on `DEPLOY_DATE` marker comparison. Enables longitudinal trend filtering: `--era post-session-b` sees only post-Session-B EPICs, `--era latest` auto-resolves to newest era present in evidence tree.
- **`aid-compliance-report.sh --era` + `--compare`** — `--era <name>` filters aggregated report to one deploy era; `--era latest` auto-resolves. `--compare ERA1,ERA2` produces side-by-side dimension table (pass/fail/null per era) for Session A → B delta analysis without Excel.
- **`aid-compliance-report.sh --reflect` `force_override` Extension** — `--reflect` pattern detection now includes `force_override` dimension: avg > 1 per EPIC → `🔴 SYSTEMATIC` banner. Average computed via integer arithmetic (`avg_x100 > 100`) to avoid floating-point dependency. Feeds the Session A → B "what holes remain" PM gate.
- **`aid-epic-summary.sh` Auto-Generated EPIC Summary (IMP-090 fold-in)** — `done-advance` hook calls `aid-epic-summary.sh generate <evidence_dir>` after `write_compliance_json`. Produces `<evidence_dir>/epic-summary.md` with 5 sections: ✅ Co bylo dodáno (git log since base_commit), ⚠️ Varování a přeskočené kroky (timeline events: branch mismatch, unusual branch, force override, repeated precondition fail, increment-step churn), ❌ Co se nestihlo (audit/curator blocking/L-effort findings), 📋 Co dělat dál PM akce (escalations, force override follow-up, L-effort proposals), 🔍 Honest signal trust level (HIGH/MEDIUM/LOW from compliance.json + branch heuristics). Best-effort: each section individually guarded with `|| true`; generation failure logs a warning and never blocks release flow. IMP-089 forward-compat: reads `branch_convention:` from `.aid-o/config/project.yaml` if present for feature-branch false-alarm suppression.
- **Plan-Writing Gate #18** — `plan-writing.md` Completeness Gate adds check #18: plans must not contain forbidden phrases that assert completeness without evidence ("already handles", "no changes needed", "existing implementation covers"). Accompanies Gate #17 (codebase grounding) from v2.17.0.
- **bats Suite Expanded to 33 Assertions** — 5 files: `test-aid-fsm.bats` (14, +5 CP2/force assertions), `test-aid-prefilter.bats` (6, NEW — SKIP/RUN/FAIL exit codes + output format), `test-aid-compliance.bats` (4, NEW — --era/--compare/--reflect triple-condition), `test-aid-epic-summary.bats` (2, NEW — 5-section headers + force_override timeline propagation), `test-aid-run-gates.bats` (7, unchanged from v2.16.0).

### Changed
- **pipeline.md §CP2 and §CP3** — full rewrite of both subsections to document v2.18.0 enforced protocol: pre-filter classifier, verifier dispatch conditions, CP2 evidence file naming (`verifier-output-step-N.md`), CP3 mandatory dual-file output schema, fix-loop (gate-fixer → verifier, max 2 iterations).
- **pipeline.md §force_override policy** — new subsection documenting `fsm_handle_force_override` contract: required fields, minimum reason length, audit trail, PM-only authorization, forbidden patterns.
- **pipeline.md Epic Summary** — new subsection documenting IMP-090 5-section schema, per-section data sources, trust level heuristics table, IMP-089 forward-compat note.
- **`aid-fsm.sh plan_json_hash` pipefail guard** — `grep '^plan_json_hash:'` with `set -eo pipefail` caused silent exit when field absent from `state.yaml`. Wrapped with `|| true` guard. Exposed by CP2 SKIP-classification test (step-verify without hash field).

### Fixed
- **`aid-stage-log.sh` JSON array/object prefix corruption** — `log_event` escaped payload before writing to `timeline.jsonl`; payloads starting with `[` or `{` (JSON arrays/objects) were double-escaped on the `data:` field. Added prefix detection: if payload starts with `[` or `{`, write `data: <payload>` verbatim; otherwise apply existing escape. Discovered during CP3 verifier-output path testing.

## [2.17.0] — 2026-05-06

### Added
- **CP1 Codebase Grounding Rule** — `plan-writing.md` Completeness Gate gains check #17 (16 → 17). Plans must verify every named external resource (functions, helpers, file paths, ports, services, commands, env vars) against the real codebase or running infra. Hand-wave like "presumably exists in some lib" or "should be available" is a hard fail. Addresses systematic CP1 blind spot identified in P032 retrospective: 5 PM-authorized resolutions (C1–C5 in P032) were all of this kind — reviewer cannot detect *absence* of helpers/files the plan presumes exist.
- **Verifier Codebase Grounding Pass** — `/aid-plan` Step 9 (CP1 review) verifier dispatch now MUST extract a flat list from the plan of every named function, helper, file path, port, service, command, and env var, and verify each against the real codebase / running infra (`grep`, `ls`, `docker ps`, `command -v`). Each item gets VERIFIED (with location) or ABSENT (mapped to a Create step). Plans with ABSENT items not mapped to Create steps → REVISE_REQUIRED.
- **`aid-compliance-report.sh --reflect`** — lightweight `/aid-reflect` (per AID-013). Per-dimension breakdown (pass / fail / null counts + 10-cell text bar chart) with pattern detection: 0 fails → ✅ green, 1 fail → ⚠️ INVESTIGATE (could be one-off), ≥ 2 fails → 🔴 SYSTEMATIC (hole in Session A enforcement). Recommended-next-action section addresses PM retrospective from P032: aggregate ≥ 80 % can hide a single dimension failing systematically; per-dimension trend is the actionable signal before Session B brainstorm.

## [2.16.1] — 2026-05-06

### Fixed
- **`aid-compliance-backfill.sh` aborts on legacy v1 evidence** — `set -euo pipefail` caused the backfill to abort on the first vulcan/sousto evidence dir whose `state.yaml` lacked a `branch:` field (`grep` returns 1 → pipefail propagates). Wrapped the `grep | awk` extraction (and the `jq | sort | head` pipeline in `backfill_state_created_at`) in `|| true`. Discovered during the v2.16.0 post-merge deploy run.
- **`aid-compliance-backfill.sh` corrupts legacy v1 JSON state files** — some pre-v2 evidence dirs store `state.yaml` as a JSON array of step objects (legacy `plan_progress.json` format). The backfill appended `created_at: <ts>` directly, breaking JSON validity (the line landed on the same line as the closing `]` because the file lacked a trailing newline). Added file-format detection: if the first non-blank char is `[` or `{`, log a warning and skip stamping. Plus a defensive `printf '\n'` guard before any append on YAML files. Live tree was repaired with `sed` post-incident; no data loss.

## [2.16.0] — 2026-05-05

### Added
- **Branch Enforcement in PRE-FLIGHT** — `aid-fsm.sh init` automatically creates `task/{epic_id}/main` from main/master/develop, detects mismatch with copy-paste fix, respects worktree mode. Closes AID-001 (65% of pre-Session-A state.yaml claimed `branch: main` with no actual task branch, breaking done-advance audit trail).
- **Real Gates Execution Provenance** — `aid-run-gates.sh` rewritten with yq parsing, emits `gate_runner_start` / `gate_runner_complete` timeline events and writes `_generated_by` / `_generated_at` / `_command_log` provenance fields into `gates_report.json`. EXECUTE→GATES precondition mechanically rejects hand-written reports.
- **Lazy execution.yaml Creation** — `aid-init` (and `aid-fsm.sh init` auto-recovery) generates per-project `execution.yaml` from auto-detected stacks (Python, TypeScript, Go, Rust, bash) with `# DEPENDENCY` hint comments per gate command. Closes AID-006 (71% of projects had no execution.yaml).
- **Compliance Telemetry** — `done-advance` writes per-EPIC `compliance.json` with 6-dimension schema (3 measured for Session A, 3 `null` for Sessions B/C). Standalone `aid-compliance-backfill.sh` for one-shot pre-deploy backfill (also stamps mid-FSM `state.yaml.created_at` per CP1 M2). Aggregator `aid-compliance-report.sh` produces pre vs post comparison with `--since` and `--era` filters.
- **svc-mcp-tg-bot MCP Server** — new Docker service in `services/mcp-tg-bot/` (FastMCP, stdio + HTTP transport on port 8817 — see Removed section for the legacy MCP that previously held this port). `send_message` tool with HTML parse_mode default. Token shared via `/opt/eco/services/.env`. Includes `docker-compose.snippet.yml` for PM to integrate into `/opt/eco/services/docker-compose.yml`.
- **FSM Repeated-Fail Telegram Alert** — `aid-fsm.sh` emits `fsm_precondition_repeated_fail` event and best-effort `try_telegram_alert()` HTTP POST to localhost:8817 when same precondition fails ≥ 3 times on the same EPIC.
- **Parametrized Diagnostic Script** — `aid-diagnostic.sh` reusable forensic analyzer (refactored from Krok 0 logic, supports `--evidence-root`, `--output md|json`, `--limit`).
- **bats Unit Test Suite** — 16 assertions across `test-aid-fsm.bats` (9), `test-aid-run-gates.bats` (3), `test-aid-init.bats` (4) covering all new FSM preconditions, gate runner provenance, and stack detection. Runs via `bats plugins/aid-orchestrator/scripts/tests/bats/`.
- **Dependency Pre-flight Script** — `aid-check-deps.sh` verifies `bash`, `git`, `jq`, `yq` (mikefarah variant only), plus optional `bats`, `direnv`, `docker`, `curl`. cmd_init now has fail-fast guard for `git` + `jq`.
- **README Requirements Section** — explicit dependency table in plugin README listing required runtime, optional dev, and optional Telegram-alerts tools with install commands per OS.
- **Worktree Development Guide** — plugin README section + committed `.envrc` with `AID_PLUGIN_PATH=$(pwd)/plugins/aid-orchestrator` and `PATH_add` for direnv-driven worktree workflows.
- **DEPLOY_DATE Marker File** — `plugins/aid-orchestrator/DEPLOY_DATE` (ISO 8601 UTC) consumed by `fsm_check_grandfather()` as the pre/post-Session-A threshold. Fallback chain: `AID_DEPLOY_DATE` env → `${AID_PLUGIN_PATH}/DEPLOY_DATE` → `${SCRIPT_DIR}/../DEPLOY_DATE`.

### Changed
- **pipeline.md** — three subsection rewrites: PRE-FLIGHT branch-enforcement catalog (5 HEAD states + 2 timeline events), GATES EXECUTE→GATES precondition with `_generated_by` requirement and grandfather caveat, DONE phase Compliance Telemetry section with 6-dimension table and null semantics caveat.
- **state.yaml schema** — adds `created_at` field (ISO 8601 UTC) used by grandfather logic for backward-compat with pre-deploy EPICs.
- **lib/aid-stage-log.sh** — new `log_info` / `log_warn` / `log_error` helpers with `[INFO]/[WARN]/[ERROR]` severity prefix on stderr (greppable, exported alongside `log_event`).
- **fsm_precondition_fail timeline event** — now carries `reason` field (set by individual precondition cases via `_PRECONDITION_FAIL_REASON`) so `fsm_count_recent_fails` can group repeated failures by failure type.
- **aid-fsm.sh::cmd_init** — overrides caller's `branch` arg ($5) with actual `git rev-parse --abbrev-ref HEAD` after PRE-FLIGHT enforcement so `state.yaml.branch` reflects post-enforcement reality (PM-authorized resolution C3).

### Fixed
- **Branch hygiene gap** — closes the 65% of pre-Session-A `state.yaml` files claiming `branch: main` with no actual task branch. New auto-checkout closes the loop with `done-advance` release sub-phase `git merge`.
- **Fake gates reports** — closes the 0% gate-runner execution evidence in 93 analyzed timelines. Provenance fields make hand-written reports mechanically detectable.
- **Missing execution.yaml** — closes the 5/7 (71%) projects lacking gate config, which forced agents into ad-hoc gate names per EPIC with no cross-project consistency.
- **Mid-FSM EPIC unblock (CP1 M2)** — backfill stamps `created_at:` into existing `state.yaml` from earliest timeline event ts, preventing the ~14 mid-FSM EPICs identified in diagnostic-findings from becoming unresumable post-deploy.
- **aid-run-gates.sh CLI parser** — fixed `${4:-default}` swallowing `--state-file` flag when caller skipped the optional 4th positional, which silently broke `gate_runner_start`/`gate_runner_complete` events for FSM-driven invocations. Regression test added to `test-run-gates.sh`.
- **Test suite git-context invariant** — `test-fsm.sh` and `test-integration-phase1.sh` setup() now `git init` their mktemp dirs so PRE-FLIGHT branch enforcement (new in this version) finds a working tree. Existing tests preserved without behavioral change.

### Removed
- **Legacy `svc-mcp-telegram` MCP (port 8817 takeover)** — the previous general-purpose Telegram MCP at localhost:8817 is decommissioned and replaced by `svc-mcp-tg-bot` on the same port. The old MCP exposed 9 tools (send_message, edit_message, search_dialogs, get_draft, set_draft, get_messages, media_download, message_from_link, delete_message) for general Telegram interaction; the new MCP exposes 1 tool (send_message) focused on AID-internal alerting. PM verified zero call sites in repo before removal (only permissions.yaml whitelist + docs entries referenced it). `defaults/policies/permissions.yaml` updated accordingly: 9 `mcp__shared-telegram__*` whitelist entries collapsed into 1 `mcp__svc-mcp-tg-bot__send_message` entry.

## [2.15.0] — 2026-03-25

### Added
- **Mechanically Enforced FSM** — `aid-fsm.sh transition` now verifies preconditions before allowing state changes: READY→EXECUTE requires `plan.json`, EXECUTE→GATES requires all steps complete, GATES→DONE requires `gates_report.json` with `overall: pass`, ESCALATION exits require `escalation_decision` set
- **`verify-state` Command** — new `aid-fsm.sh verify-state` returns current state + allowed transitions as JSON for LLM orientation
- **`set-field` Command** — new `aid-fsm.sh set-field` for structured state mutations (escalation decisions, custom fields)
- **FSM Audit Trail** — all `aid-fsm.sh` operations (transitions, precondition failures, force overrides) logged to `timeline.jsonl` via `aid-stage-log.sh`
- **`--force` Escape Hatch** — `aid-fsm.sh transition --force` bypasses preconditions with PM approval, logged as `fsm_force_override`
- **Gates State Check** — `aid-run-gates.sh --state-file` refuses to run unless FSM state is GATES
- **Gates Report Persistence** — `aid-run-gates.sh --report-file` auto-writes `gates_report.json` (required by GATES→DONE precondition)
- **Mechanical Enforcement Protocol** — new section in `aid-run.md` with 8 non-negotiable rules for FSM compliance
- **DONE Sub-Phases** — `done_phase: review → release` within DONE state, managed by `aid-fsm.sh done-advance` with evidence-based preconditions (curator-report, audit-report, pm_decision=merge)
- **Reserved Field Protection** — `set-field` rejects writes to `state` and `done_phase` (must use dedicated `transition`/`done-advance` commands)
- **Release Script FSM Guard** — `aid-release.sh` refuses release when `state.yaml` exists with `done_phase != release` (Layer 2 defense)
- **Git Pre-Commit Hook** — FSM guard on `task/*` and `epic/*` branches blocks commits in DONE/review and READY states (Layer 3 defense)
- **Hook Auto-Install** — `/aid-init` installs/upgrades pre-commit hook with marker-based append (coexists with existing hooks)
- **Step Verification Enforcement** — `increment-step` refuses to advance without `step-{N}-verify.md` evidence file (AC checklist + visual check)
- **Agent Dispatch Protocol** — 6 non-negotiable rules in pipeline.md: verbatim plan content, visual assets, post-step AC verification, visual verification for UI, resume-on-failure, visual context dispatch
- **Visual Companion** — browser-based HTML prototype viewer for brainstorming (opt-in, Node.js server adapted from Superpowers). Generates interactive mockups during design sections, saves approved HTML as 4th input type for visual assets pipeline. Per-question visual/text decision taxonomy.
- **Visual Assets Pipeline** — 4 input types (GitHub repo, AI Studio URL, PNG, Visual Companion) → unified `visual-spec.yaml` output; `visual_refs` field in plan.schema.json; visual dispatch protocol in pipeline.md §4; Visual Anchoring requirement in frontend role card; screenshot comparison protocol (MATCH/PARTIAL/MISMATCH); forbidden text-only UI descriptions in plan-writing.md
- **Plan-Level DONE Gate** — `aid-fsm.sh init` blocks cross-plan run if previous plan has unreviewed C+A findings (`ca-review-complete` marker required); enforces "dispatch per EPIC, validate per Plan" model
- **Step-Verify Content Validation** — `increment-step` now requires at least one `- [x]` AC checklist item and one commit hash (7+ hex chars); prevents minimal "Result: PASS" without substance
- **Plan.json Init Warning** — `aid-fsm.sh init` warns when plan.json steps lack `objective` field
- **Per-Project Agent Memory (Qdrant)** — 10-category deep codebase scan (architecture, API, data, UI, config, testing, conventions, security, DevOps/CI-CD, cross-cutting concerns); `memory-mcp.md` skill with entry schema, quality rules (≥20 word summary, real code examples, 5 rejection criteria), store/find protocol, supersede pattern; pipeline §4 memory READ (2-tier context injection ~1500 tokens); pipeline §7 Scanner dispatch at plan boundary; `memory_writes` mandatory in agent output; `## Memory Used` + `## Memory Written` enforced in step-verify by `increment-step`; Auditor Memory Health category (stale detection, conflict detection, coverage check); kondice flow (auditor flags → scanner verifies)

### Changed
- **FSM Valid States** — added ERROR to `VALID_STATES`; added `→ERROR` transitions from READY, EXECUTE, GATES, ESCALATION
- **Escalation Cleanup** — `escalation_decision` field auto-cleared when leaving ESCALATION state
- **Pipeline §3-§6** — each section now documents which FSM preconditions enforce correct behavior

### Fixed
- **Dead Cross-References** — replaced 20+ references to deleted v1 files (dispatch-protocol.md, epic-orchestration.md) with v2 equivalents across 11 files
- **v1 State Names** — replaced v1 FSM states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE) in pipeline.md; added v1 legacy headers to improvement-proposals.md and analytics.md
- **v1 Directory Paths** — updated CLAUDE.md workspace structure from v1 (01-plans/, 04-engine/) to v2 (plans/, work/)
- **Pre-Commit Hook** — removed dead case statement (non-functional code from refactoring)

## [2.6.0] — 2026-03-14

### Added
- **Standards Enforcement System** — two standard sets (`general.yaml` with 26 language-agnostic rules, `vulcan.yaml` with 22 ecosystem-specific rules + 4 severity overrides) selectable during `/aid-init`
- **Standards Gate** — new `standards_compliance` gate in `execution.yaml`, 100% deterministic (pattern/structural/file-exists rules only), custom/LLM rules are auditor-only advisory
- **Standards Audit Category** — new conditional category I) in auditor with full-codebase scan, severity-based scoring (cap 5 violations/rule), 15% weight when active
- **Standards Curator Integration** — hotspot detection (3+ violations of same rule = systemic), `source_type: standards` proposals with auto-approve for S-effort fixes
- **Standards Dispatch Context** — agents receive filtered standards in prompt (gate-blocking first, filtered by language), omitted when `standards.active == 'none'`

### Changed
- **Auditor Category Count** — 8→9 categories (5 mandatory + 4 conditional), weight redistribution when standards active (Code 30→25%, Security 30→27%, Docs 25→23%)
- **Agent Execution Summary** — includes `Standards violations noted: {count}` for trend tracking
- **Init Flow** — standards profile selection (general/vulcan/none) with `project.yaml → standards` config block

## [2.5.0] — 2026-03-13

### Added
- **Plugin Path Discovery** — `/aid-init` discovers and caches plugin installation path in `config/plugin.yaml`; Script Execution Protocol in `agent-core.md` teaches all agents how to resolve `scripts/X.sh` references
- **Brainstorming Question Format Template** — concrete format with Effort/Risk per option, recommendation with "Why not" reasoning, and webhook delivery example
- **Brainstorming Handoff Summary** — plan-writing presents decision summary + 6 options including `/aid-run --auto` with `autonomous_mode` prerequisite warning
- **Superpowers Conflict Resolution** — CLAUDE.md template includes conflict table (brainstorming, writing-plans, executing-plans → AID equivalents); 3 `skill_conflicts` entries in `orchestration.yaml`
- **Documentation Gate Enforcement** — path-pattern correlation: `docs_updated` gate fails only when API-path files changed without doc updates; auditor escalates missing API docs to high severity

### Changed
- **PRE-FLIGHT Plugin Verification** — `/aid-run` and `/aid-do` verify `plugin_path` on startup with cache invalidation fallback
- **Dispatch Context** — `agent-protocol.md` input format includes `plugin_path` for dispatched agents
- **Brainstorming Rule 8** — now explicitly requires effort estimate (S/M/L) and risk (L/M/H) per option

### Fixed
- **`/aid-plan-epic` stale references** — replaced with `/aid-plan --epic` across brainstorming, plan-writing, pipeline, and planner skills (command merged in v2.0)
- **`aid-plan.md` step count** — Steps 1-7 showed `/8` denominator instead of `/9` after CP1 review was added as Step 9

## [2.4.0] — 2026-03-12

### Added
- **PM Merge Decision Gate** — DONE state presents combined curator+auditor summary, PM explicitly chooses MERGE/FIX/ABORT before code reaches main
- **Parallel Curator+Auditor** — Both dispatch simultaneously in DONE state, reducing post-completion wait time
- **Auditor Auto-Fix** — S and M effort recommendations trigger gate-fixer dispatch pre-merge via new `recommended_fixes` output field
- **70/30 Design Principle** — Documented deterministic-first philosophy in pipeline §1: 70% bash, 30% LLM
- **Review Pre-Filter** — Bash regex checks (secrets, SQL injection, eval, debug) run before CP2/CP3/CP6 verifier dispatch, skipping LLM when unnecessary
- **Per-Escalation Templates (E1-E8)** — Each trigger shows specific context, findings, affected files, and available commands

### Changed
- **DONE State Flow** — Merge moved from step 3 to step 13 (after PM approval); prevents premature merge before review
- **Curator Auto-Evaluation** — Tier 2 default: M-effort proposals now auto-approved (was: deferred to PM)
- **PM Interaction Points** — Enhanced output at READY (gate details), CP1 (severity summary + 3 options), CP6 (evidence paths), scope warnings (actionable commands), and ESCALATION (per-type context blocks)
- **Auditor Dispatch Timing** — Now dispatched pre-merge in parallel with Curator (was: post-merge sequential)

## [2.3.0] — 2026-03-12

### Added
- **Review Checkpoints (CP1-CP6)** — Automatic verifier dispatch at 6 pipeline milestones: post-brainstorm plan review, per-step code review, pre-GATES integration review, curator proposal validation, auditor critical-finding gate, and post-/aid-do quick review
- **Fix Loop Protocol** — Verifier findings with Critical/High severity trigger gate-fixer dispatch + re-verification (max 2 iterations), replacing reactive gate-failure-only fixes
- **Critical Finding Gate (CP5)** — Auditor critical findings now block DONE state, triggering ESCALATION instead of proceeding to queue
- **Review Checkpoint Configuration** — New `review-checkpoints.yaml` policy file with per-checkpoint toggles, fix-loop settings, and trivial-skip threshold
- **Escalation triggers E7, E8** — Verifier review failure after fix loop; auditor critical security finding
- **Pipeline §13** — New Review Checkpoint Protocol section as authoritative reference

### Changed
- **Verifier agent** — Expanded from on-demand to automatic dispatch with fix-loop integration and checkpoint-specific context assembly
- **Gate-fixer agent** — Now accepts verifier review findings as input (source: `verifier_review`), not just gate failures
- **Auditor agent** — Critical findings produce `blocking_findings` flag that blocks DONE transition
- **Pipeline §4-§8** — Updated with review checkpoint dispatch points at EXECUTE, GATES, DONE, and FAST MODE

### Fixed
- **Broken cross-references** — Fixed 5 stale v2 migration references: auditor.md, gate-fixer.md, curator.md, planner.md pointed to non-existent `epic-orchestration.md`/`retry-engine.md`; pipeline.md referenced non-existent `dispatch-config.yaml`

## [2.2.0] — 2026-03-11

### Added
- **Context Persistence (Interim Document)** — `/aid-plan` now creates `.aid-o/work/interim-P{NNN}.md` at session start, updated after each step with full conversation detail; survives context window overflow and session interruptions; auto-deleted on plan completion
- **Concurrent brainstorm detection** — checks for existing interim docs before starting new brainstorm, offers resume or fresh start
- **ID Allocation Procedure** — documented read-increment-write protocol for counter.yaml in run-management ID System section

### Fixed
- **Dead `epic-orchestration.md` references** — updated brainstorming.md, plan-writing.md, and run-management.md to reference run-management ID System instead
- **Abort text accuracy** — "no files created" corrected to "no plan written, interim doc preserved"
- **plan-writing.md missing interim cleanup** — added MUST rule 15 to delete interim doc after successful plan write

## [2.1.1] — 2026-03-10

### Fixed
- **`.gitignore` missing from `/aid-init`** — Init now creates `.gitignore` appended to project root, ignoring runtime artifacts (evidence, quick logs, timeline.jsonl, queue.yaml) while keeping design artifacts versioned
- **Defaults `.gitignore` outdated** — Updated from v1 paths (`.aid-o/04-engine/`) to v2 structure

## [2.1.0] — 2026-03-10

### Changed
- **Brainstorming skill refactored** — 34% smaller (415→272 lines) with 8 new capabilities: scope decomposition, MoSCoW prioritization, risk assessment protocol, prior-plan lookup, pre-decided solution handling, context-loss recovery, workflow/AI questioning hint, Docker Compose recommendation
- **Design section templates extracted** — Moved to `defaults/templates/design-sections.md` as standalone reference, reducing brainstorming skill size while preserving all templates

### Removed
- **Obsolete planning docs** — Removed CRITICAL-ASSESSMENT.md and REDESIGN-PLAN-v2.md (completed, no longer relevant)

## [2.0.0] — 2026-03-03

### Breaking Changes
- **11-state LLM FSM → 6-state bash FSM** — States reduced from IDLE/PLANNING/PLAN_REVIEW/EXECUTING/PHASE_CHECK/NEXT_PHASE/GATES/GATE_RETRY/ESCALATION/CURATOR_RESOLVE/PM_APPROVAL/DONE to READY/EXECUTE/GATES/ESCALATION/DONE/ERROR. State transitions enforced by `aid-fsm.sh`, not LLM instructions.
- **27 skills → 8 skills** — Consolidated from 27 cross-referencing skills to 8 focused skills (agent-protocol, pipeline, planner, brainstorming, quality-gates, run-management, memory, role-cards). Removed: epic-orchestration, dispatch-protocol, gates-engine, retry-engine, first-aid-controller, auto-escalation, auto-done-state, parallel-dispatch, cost-optimization, epic-queue, slack-mcp, workflow-intelligence, and 15 others.
- **18 agents → 7 agents** — Consolidated from 18 role-based agents to 7 controller agents (implementer, verifier, gate-fixer, curator, auditor, project-scanner, run-validator). Removed: architect, backend, frontend, domain, qa, security, observability, docs-writer, release, code-reviewer, docs-reviewer, lessons-extractor, quality-gates-runner.
- **17 commands → 8 commands** — New unified commands: `/aid-do`, `/aid-plan`, `/aid-run`, `/aid-status`, `/aid-help`, `/aid-init`, `/aid-audit`, `/aid-stop`. Removed: `/aid-brainstorm`, `/aid-plan-epic`, `/aid-run-epic`, `/aid-first-aid`, `/aid-setup`, `/aid-epic-queue`, `/aid-epic-status`, `/aid-research`, and 9 others.
- **Directory structure** — `.aid-o/04-engine/` → `.aid-o/work/`, `.aid-o/02-epics/` → `.aid-o/tasks/`, `.aid-o/03-config/` → `.aid-o/config/`. Init creates 10 files (down from 40+).
- **10 policy YAMLs → 3** — `execution.yaml` (gates + dispatch), `project.yaml` (stack + preferences), `permissions.yaml` (agent permissions). Removed: decision-policies.yaml, dispatch-strategy.yaml, gates.yaml, memory-config.yaml, slack-config.yaml, and 5 others.

### Added
- **Fast Mode (`/aid-do`)** — < 2 min overhead for tasks < 2h. Creates Q-NNN.md quick log, skips full EPIC pipeline. Automatic scope detection.
- **Bash FSM (`aid-fsm.sh`)** — Deterministic 6-state finite state machine. States: READY → EXECUTE → GATES → DONE (happy path), with ESCALATION and ERROR branches. All transitions validated in bash, not LLM.
- **Bash gate runner (`aid-run-gates.sh`)** — Deterministic quality gate execution with JSON output, timeout handling, retry logic. Replaces LLM-manual gate evaluation.
- **Pipeline automation scripts** — `aid-auto-pipeline.sh` (orchestrator), `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`. All deterministic operations moved from LLM to bash.
- **Stage logging (`aid-stage-log.sh`)** — Structured timeline.jsonl event logging with standardized format across all pipeline operations.
- **Token estimator (`aid-token-count.sh`)** — Character-based token estimation for prose/code/mixed content types.
- **`@aid/contract` package** — Shared TypeScript types for all `.aid-o/` data formats (AidFsmState, AidState, AidGatesReport, AidTimeline, etc.).
- **Progressive help (`/aid-help`)** — 4-level disclosure: Level 0 (cheat sheet), Level 1 (command detail), Level 2 (architecture), Level 3 (troubleshooting).
- **Scope check gate** — `scripts/gates/scope-check.sh` verifies implementation stays within EPIC-defined file scope.
- **173 tests across 13 suites** — Up from 88 tests / 6 suites in v1.7.0. Full coverage of FSM, gates, pipeline, stage logging, token counting, scope checking.

### Changed
- **~87% token reduction** — Plugin prompt tokens reduced from ~400K to ~50K by consolidating skills/agents/commands and moving deterministic logic to bash scripts.
- **`/aid-plan` merges 3 old commands** — Replaces `/aid-brainstorm` + `/aid-write-plan` + `/aid-plan-epic` into single progressive workflow.
- **`/aid-run` merges 2 old commands** — Replaces `/aid-run-epic` + `/aid-first-aid` with unified command supporting `--auto` flag.
- **`/aid-status` merges 2 old commands** — Replaces `/aid-epic-status` + `/aid-epic-queue` with combined view.
- **`/aid-init` merges `/aid-setup`** — Single idempotent init command creating 10-file `.aid-o/` structure with stack auto-detection.
- **Role cards consolidated** — All agent role definitions in single `role-cards.md` (8 roles + 4 focus cards) instead of 18 separate agent files.
- **Pipeline skill consolidated** — Single `pipeline.md` replaces 14 old orchestration skills, documenting all 6 FSM states.
- **Evidence paths** — `stage_log.jsonl` → `timeline.jsonl`, `plan_progress.json` → `state.yaml`.
- **aid-server paths** — Updated all Express routes and WebSocket handlers for v2 `.aid-o/` structure.

## [1.7.0] — 2026-02-28

### Added
- **Path Traversal Guards** — defense-in-depth (regex + resolve+startsWith) path validation on pipeline theater, evidence, and decision routes preventing CWE-22 filesystem traversal via `epicId`/`runId` parameters
- **GUI CORS Middleware** — `cors()` middleware on the aid-gui Express server with `AID_GUI_CORS_ORIGINS` env var support, defaulting to localhost:5173 and localhost:3000
- **Agent Name Frontmatter** — all 18 agent files now have `name:` field in YAML frontmatter matching the filename stem, enabling plugin validation
- **Master Test Runner** — `run-all-tests.sh` discovers and executes all test suites with unified pass/fail reporting (88 tests across 6 suites)
- **Curator Dispatch Regression Tests** — Suite F (5 tests) verifying unconditional Curator dispatch and state-entry logging in gate-evaluation.md and first-aid-controller.md
- **Phase Marker Documentation** — `plan-writing.md` Phase Markers subsection with exact format, rules, regex, and "do NOT use" examples for LLM-generated plans
- **PARALLEL_EXECUTING Sub-State** — `epic-state-machine.md` documents the FIRST AID parallel execution sub-state with activation criteria and safety limits
- **AI Companion Project Context** — system prompt auto-built from CLAUDE.md, package.json, pipeline state, EPIC queue, plans, decisions, ideas backlog, and project structure on every message
- **AI Companion Tool Use** — 7 tools (readFile, listDirectory, searchContent, readYaml, readEpic, readPlan, getPipelineState) giving the companion full codebase access with sandboxed paths and 8-step tool call limit
- **Voice Dictation Recording Bar** — waveform visualization via AudioContext AnalyserNode, elapsed timer, live interim text display (Web Speech API), and one-click stop-and-send flow
- **Whisper Auto-Detection** — background probe on mount detects Whisper availability; uses Web Speech API as primary (Czech `cs-CZ` support) with Whisper upgrade when OPENAI_API_KEY is set
- **FIRST AID Wrapper State Mapping** — FIRST_AID_INIT, QUEUE_PROCESSING, QUEUE_ADVANCE, FIRST_AID_COMPLETE mapped to medical labels (Triage, Operating, Next Patient, All Clear) with FSM colors and active state detection
- **Satellite Card Alternation** — Ward, Lab, Escalations, Vitals cards alternate between current and total values every 4 seconds with AnimatePresence transitions

### Changed
- **CORS Wildcard Handling** — `AID_CORS_ORIGINS=*` now correctly enables wildcard CORS instead of creating a single-element array `['*']`
- **Default Server Binding** — both aid-server and aid-gui default to `127.0.0.1` (loopback only) instead of `0.0.0.0`, preventing unintentional network exposure; Docker containers retain `0.0.0.0` via explicit env var
- **GUI README Replaced** — removed Gemini/AI Studio boilerplate, replaced with accurate AID Dashboard GUI documentation including local setup and aid-server dependency
- **Root README Version** — updated from v1.5.0 to v1.6.0
- **Brainstorming Step Count Standardized** — all documentation (README, Docusaurus, aid-help) now references 8-step brainstorming matching the actual skill lifecycle
- **aid-run-epic Prerequisites** — removed false auto-generation claim; `plan.json` must pre-exist via `/aid-plan-epic`
- **Zombie Backlog Cleanup** — moved 7 already-fixed entries (IMP-010/035/049/050/057/059/067) from Active to Implemented, correcting count from 62 to 55
- **EPIC ID Regex Hardened** — `aid-auto-pipeline.sh` now accepts alphanumeric plan IDs with internal hyphens (e.g., `E-TEST-001-1_2`)
- **Dependency Parser Enhanced** — `aid-plan-to-epic.sh` supports range expansion (`Steps 3-7`), trailing text stripping, cross-phase dependency filtering, and deduplication
- **Scope Generation Granularity** — `aid-plan-to-epic.sh` generates file-level paths in EPIC scope when plan steps have `**Files:**` sections, improving FIRST AID parallel detection accuracy
- **EPIC Template Scope Guidance** — template includes guidance comments encouraging file-level path declarations over broad directories
- **Curator Dispatch Made Unconditional** — `gate-evaluation.md` and `first-aid-controller.md` now mandate Curator dispatch at CURATOR_RESOLVE regardless of discovered_issues
- **QUEUE_PROCESSING Auto-Mode** — `first-aid-controller.md` includes parallel dispatch checklist cross-referencing `aid-first-aid.md` sections 3.1-3.5
- **Curator Auto-Defer Threshold Raised** — auto-mode now defers only effort:L proposals to backlog; effort:S and effort:M are fixed inline, increasing autonomous fix rate
- **Command Center State Labels** — all FSM states renamed to medical/hospital theme (On Call, Diagnosis, Prescription, Infusing, Vital Signs, Second Opinion, Lab Results, Doctor's Orders, Recovery, Discharged, Code Red)
- **Satellite Cards Data Sources** — Ward shows queue running+waiting / completed+failed; Lab shows gate runs+retries / audit score; Escalations shows budget usage / total escalations; Vitals shows steps executed / total events
- **EPIC Runs Display** — shows last 5 completed (most recent first) instead of first 5
- **Voice Flow Simplified** — removed confirm step; recording stops and sends directly (one action instead of three)
- **CommandPalette Voice** — transcript sends as message directly instead of inserting into filter input
- **Companion Open Speed** — status and sessions pre-fetched on project select; palette/panel opens instantly without network delay
- **Pipeline API Extended** — `/pipeline` endpoint returns full autoModeSession with escalation budget/count and aggregate counters (epicsCompleted, epicsFailed, totalStepsExecuted, totalGateRuns, totalGateRetries, totalEscalations)

### Fixed
- **WebSocket Replay Parsing** — `dispatchReplay()` now reads raw stage log entries directly instead of expecting non-existent `.entry` wrapper, fixing Pipeline Theater replay after reconnection
- **CSS Custom Property Generation** — `.replaceAll('_', '-')` replaces all underscores in FSM state names for correct CSS variable references (was `.replace` which only fixed the first)
- **Curator Input File References** — corrected from `step_output.json` to `output.md` + `diff.patch` matching actual agent output format
- **Queue Field Name** — `scripts/README.md` corrected `queued_at` to `added_at` matching actual queue schema
- **Queue Field Name Mismatch** — server returned `data.entries` but GUI expected `data.queue`, causing queue entries, elapsed time, and EPIC runs to never display
- **Topbar Voice Integration** — replaced inline mic recording logic (~90 lines) with shared VoiceButton component using `compact` prop

## [1.6.0] — 2026-02-28

### Added
- **Pipeline Scripts** — 5 bash scripts (`aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`, `aid-auto-pipeline.sh`) for deterministic Plan→EPIC→json→run→queue conversion replacing LLM-driven operations
- **Shared Script Library** — `scripts/lib/common.sh` with 7 portable bash functions (YAML parsing, section extraction, slugify, prerequisites check, error formatting, timestamps)
- **Script Documentation** — `scripts/README.md` with full interface contracts, argument tables, exit codes, data flow diagram, and JSON manifest schema for all 5 pipeline scripts
- **EPIC Template Dependencies Section** — structured Dependencies section with Internal/External/Queue subsections replacing flat placeholder
- **Deterministic Work Detection Audit** — new audit category I) scanning commands, skills, and agents for LLM-performed template filling, structured parsing, and file manipulation that could be replaced by scripts, with false positive filters and -10 cap scoring
- **Pipeline Test Suite** — 76 tests across 6 test scripts (40 unit, 16 integration, 20 regression) with 3 fixture plan files covering single-phase, multi-phase, and cross-plan dependency scenarios

### Changed
- **aid-plan-epic Command** — rewritten from 544-line LLM-driven flow to 235-line script-orchestrated 6-step flow delegating deterministic work to `aid-auto-pipeline.sh`
- **aid-run-epic Command** — inline plan generation removed; `plan.json` must pre-exist (created via `/aid-plan-epic`) with clear error message and actionable suggestion when missing
- **Documentation Consistency Pass** — 10+ skill/command files updated to reference script-based pipeline, removing references to inline plan generation

## [1.5.0] — 2026-02-28

### Added
- **Token Estimation Protocol** — new `skills/token-estimator.md` defining character-based heuristic for dispatch token counting with cl100k_base approximation and calibration process
- **Dispatch Configuration** — new `defaults/policies/dispatch-config.yaml` with 18 role-to-model tier mappings (3 opus, 11 sonnet, 4 haiku), per-tier context defaults, and advisory budget alerts
- **Plan Schema Extension** — `model` (enum: haiku/sonnet/opus) and `context_scope` (knowledge, memory, previous_outputs) optional fields per step in `plan.schema.json`
- **Planner Model Assignment** — planner reads `dispatch-config.yaml` and populates `model` + `context_scope` per step with fallback to opus/all-context when config is absent
- **Dispatch Usage Logging** — pre-dispatch token estimation and post-dispatch `usage` object in stage_log.jsonl with model, tokens, duration, context sources, and budget alerts
- **Usage Aggregation** — DONE state aggregates all dispatch_complete entries into `usage_summary` in plan_progress.json with breakdowns by model, role, and step
- **Model Tiering in Dispatch** — `step.model` passed to Task tool with 3-level fallback chain (step.model → dispatch-config.yaml → opus default)
- **Selective Context Injection** — knowledge, memory, and previous outputs conditionally injected based on `step.context_scope` with full backward compatibility
- **Dispatch Prompt Trimming** — EPIC context reduced to one-line goal + step-level paths instead of full EPIC specification
- **Token Efficiency Audit** — new `/aid-audit efficiency` type with per-role baseline comparison and 2x alert threshold (advisory, 0% weight)

### Changed
- **Dispatch Protocol** — model parameter wired into Task tool calls, context injection is conditional, prompt uses trimmed EPIC context
- **Parallel Dispatch** — model tiering support with per-agent model resolution

## [1.4.0] — 2026-02-27

### Added
- **GUI Dashboard** — full-featured web dashboard (`aid-gui` package) with Express backend, WebSocket real-time updates, and React 19 + Zustand 5 frontend
- **Ideas-to-Execution Kanban** — drag-and-drop board tracking ideas through exploration → planned → running → done lifecycle with auto-status from linked plans/EPICs
- **AI Companion Chat** — SSE-streaming chat panel with markdown rendering, session management, voice input (Web Speech API), and contextual hint buttons
- **EPIC Lifecycle Manager** — GUI-driven EPIC listing with frontmatter parsing, run/schedule actions, queue integration, and status-sorted display
- **Evidence Vault** — full-text grep search across evidence files (200-result cap, binary detection), date-grouped collapsible sidebar, and markdown preview toggle with DOMPurify sanitization
- **Pipeline Theater SVG Timeline** — Gantt-like horizontal timeline with color-coded role bars (architect/backend/frontend/qa/docs/security), replay controls (0.5x–4x speed), EPIC/run selector, and live auto-scroll mode
- **Decision Hub Notifications** — Web Audio API sound alerts (440Hz sine, 3s debounce) and browser Notification API for background tabs, with Sidebar badge pulse animation
- **Evidence Search API** — `GET /evidence/search?q=&limit=` endpoint with case-insensitive text matching, path traversal protection, and binary file skipping
- **Pipeline Theater API** — `GET /pipeline/theater/:epicId/:runId` endpoint merging plan.json + plan_progress.json + stage_log.jsonl into combined theater data
- **Companion Backend** — session-store with JSON persistence, auto-detect LLM adapter (Claude/OpenAI/Ollama/stub), SSE streaming endpoint, voice transcription proxy
- **WebSocket Infrastructure** — topic-based pub/sub (pipeline, stage_log, decisions, queue) with heartbeat, auto-reconnect (exponential backoff), and replay on reconnect
- **Test Suite** — 1014 Vitest tests across 31 files covering server routes, parsers, WebSocket, store slices, and API client

### Changed
- **Project structure** — added `packages/aid-gui/` (frontend) and `packages/aid-server/` (backend) as monorepo packages alongside the plugin

## [1.3.1] — 2026-02-27

### Fixed
- **Curator evidence path** — `step_output.json` replaced with `output.md` so Curator can actually read agent improvement notes
- **FIRST AID skill reference** — `skills/first-aid-mode.md` corrected to `skills/first-aid-controller.md` in `/aid-help`
- **Czech preset descriptions** — translated to English in `permissions.yaml` (aspirin and steroids descriptions)
- **Stale epic-breakdown.md references** — 6 references across 5 files replaced with `epic.md` (the actual template)

## [1.3.0] — 2026-02-27

### Added
- **Queue dependency ordering** — `depends_on` field in queue schema with Kahn's algorithm cycle detection; `next()` computes READY/WAITING/BLOCKED eligibility per entry
- **INTERMEDIATE_GUARDRAIL** — 3-check auto-approval gate (all_steps_done, no_gate_failures, evidence_complete) for intermediate EPICs in FIRST AID mode
- **Queue write ownership** — CONFLICT_CHECK as Step 0 in add()/start()/complete() operations; single-writer constraint during FIRST AID via auto-mode flag file
- **Canonical EPIC ID format** — formal `E-{plan_id}-{phase}_{total}` specification with validation regex and cross-referenced documentation
- **Untrusted field list** — 10 untrusted and 6 trusted fields enumerated in dispatch-protocol with rationale for each classification
- **OVERLAP_CHECK algorithm** — concrete pseudocode for 3 cases (exact-exact, glob-exact, glob-glob) replacing vague prose in planner
- **R1 dependency classification** — DATA MODEL and API CONTRACT type definitions with 5-step determination algorithm replacing subjective criteria
- **plan_ref keyword matching** — 4-step algorithm with extract/score/stopping-rule/confidence-check replacing vague Strategy 3 description
- **Setup re-run detection** — `/aid-setup` detects existing workspace and offers 6-option section menu for selective reconfiguration
- **Release count verification** — RELEASE_CHECK_COUNTS ensures CLAUDE.md command/skill counts stay in sync during releases
- **DEFAULT_BASELINE** — threshold 50/100 applied when no prior audit report exists for PM_APPROVAL auditor trend check

### Changed
- **adapt_example()** — simplified from 7-step function (422 lines) to 3-step (83 lines): path substitution, tool reference update, validation
- **Credit exhaustion detection** — 5 hardcoded strings replaced with 6 case-insensitive regex patterns and short-circuit evaluation

### Fixed
- **Escalation snapshot** — now correctly writes to `interrupted_step_context.json` instead of inconsistent field names

### Removed
- **`--dry-run` flag** — removed from `/aid-first-aid` command; deferred to backlog as standalone feature

## [1.2.0] — 2026-02-27

### Removed
- **Permission Sandwich** — removed `skills/permission-sandwich.md` (750 lines) and `defaults/policies/permissions-auto.yaml` (164 lines); FIRST AID no longer backs up, elevates, or restores permissions — requires Steroids 💉 preset instead

### Changed
- **Permission presets** — Safe removed, Recommended renamed to Aspirin 💊, Advanced renamed to Steroids 💉; two-preset system with deny-list protection
- **FIRST AID startup** — permission sandwich steps (backup, elevate) replaced by single Steroids preset verification check
- **FIRST AID completion** — permission restore removed; /aid-stop simplified to 3 steps (mode flag, wait, save progress)

### Fixed
- **Plan archival** — QUEUE_ADVANCE now uses queue as ground truth for plan archival instead of filesystem scanning; DONE state no longer attempts archival (single source)
- **Version bump detection** — uses plan-level completion (`plan_epics_total`) instead of queue position; solo plans always bump, multi-EPIC plans bump on last EPIC
- **Release sub-phase** — DONE state now explicitly calls RELEASE_SUB_PHASE with mandatory stage_log entry; skipping is no longer possible without audit trail
- **Queue removal** — `/epic-queue remove` sets status "removed" (not "completed"); context boundary tracking distinguishes session total from actually-executed EPICs

## [1.1.0] — 2026-02-27

### Added

- **Plan-Writing Skill** — new `skills/plan-writing.md` with two modes: Mode A (post-brainstorming) and Mode B (standalone `/aid-write-plan`); includes Forbidden Phrase Detection hard gate, Traceability Verification, 16-point Completeness Gate, and Post-Write Handoff offering EPIC creation
- **`/aid-write-plan` Command** — standalone plan writing command that delegates to the plan-writing skill; accepts topic argument or interactive input
- **Brainstorming Critical Rules Block** — 11 critical rules at the top of `aid-brainstorm.md` with primacy effect positioning to prevent instruction drift
- **Brainstorming Step Self-Checks** — each of the 8 brainstorming steps now has a mandatory self-check checklist (2-4 items) that must pass before transitioning to the next step
- **Brainstorming Progress Tracker** — mandatory `=== Step N/8: {Name} ===` output at the start of every brainstorming step for checkpoint enforcement
- **Brainstorming Approach Hard Gate** — RULE 9 enforces minimum 2 approaches before presenting to PM; RULE 10 prevents skipping approach exploration even for "obvious" topics
- **Brainstorming Completeness Gate** — Step 8 now enumerates all PM answers from Steps 3-6 and verifies each appears in the plan document before finalizing
- **adapt_example() Implementation** — 7-step function in knowledge-acquisition.md replaces path placeholders, updates framework versions, handles Docker sections, aligns platforms, merges constraints, adjusts step count, and writes adapted EPIC
- **Knowledge Results Display** — brainstorming Step 1 now shows PM what knowledge was found ("Found N relevant docs: [names]") or "No knowledge indexed yet"
- **`/aid-help knowledge` Topic** — lists all example EPICs by category, explains search flow (Context7 → Qdrant → static), and documents indexing and research triggers
- **RESUME_SESSION safety net** — QUEUE_PROCESSING next() now filters on `status in ["queued", "running"]` with preference for running entries, so an interrupted EPIC is automatically resumed even when the RESUME_SESSION reset was skipped
- **Permission snapshot and restore** — `auto-mode-state.yaml` gains an `original_permissions_snapshot` field; RESTORE_PERMISSIONS now uses a two-tier fallback (backup file, then inline snapshot) across all three restore paths (COMPLETE, /aid-stop, crash recovery)
- **Permission grant log** — `auto-mode-state.yaml` gains a `permissions.grant_log[]` audit trail field recording each dynamic permission grant with permission, source, actor, step_ref, timestamp, and reason; PHASE_CHECK permission learning dual-writes to both `learned_permissions[]` and `grant_log[]`
- **Multi-agent parallel execution** — QUEUE_PROCESSING gains a complete parallel dispatch protocol: independence detection via EPIC scope analysis, Task agent dispatch in worktree isolation, sequential merge with shared escalation budget, failure isolation per agent, and a safety cap of 3 concurrent agents
- **Untrusted content tags in dispatch templates** — all 10 user-supplied interpolation points in `aid-run-epic.md` dispatch prompts are wrapped in `<untrusted_content>` tags with source attributes; safety preamble added to both base and re-dispatch templates to prevent prompt injection
- **Hardened deny-list entries** — `Bash(rm -fr:*)` (reversed short flags) and `Bash(dd if=/dev/urandom:*)` added to the hard-deny list in `permission-sandwich.md` and `permissions-auto.yaml` with inline rationale comments and updated Section 3.4 rationale table
- **Planner parallelism rules** — 5 named Parallel Group Assignment Rules added to `planner.md`; backend and frontend agents can now parallelize after architect+domain steps when file scopes do not overlap; includes OVERLAP_CHECK algorithm and 3 worked examples
- **Planner granularity heuristics** — HEURISTIC G1 (Layer Splitting) and G2 (Module Splitting) added to `planner.md` Section 2b with before/after examples and interaction rules; steps spanning 3+ layers or 3+ modules are automatically split
- **Audit instruction quality checks** — Section G added to `auditor.md` with 5 checks for instruction file quality (intro presence, TODO/FIXME scan, frontmatter, cross-reference accuracy, files exceeding 800 lines); weighted at 10% and conditional on `plugins/aid-orchestrator/` existing

### Changed

- **Brainstorming modular split** — 1371-line `brainstorming.md` split into core (569 lines) + two sub-skills: `brainstorming-knowledge.md` (445 lines) for knowledge acquisition and file analysis, `brainstorming-workflow.md` (443 lines) for workflow detection and Docker/MCP rules
- **Brainstorming flow simplified** — reduced from 11 steps to 8 steps; EPIC creation removed from brainstorming entirely (now handled by `/aid-plan-epic` via plan-writing handoff)
- **Plan-writing delegation** — brainstorming Step 8 now delegates to `skills/plan-writing.md` instead of writing the plan inline; plan-writing skill handles quality gates, forbidden phrase detection, and completeness verification
- **FIRST AID disclaimer** — reframed from alarmist "USE AT YOUR OWN RISK" to "Experimental Autonomous Mode"; added explicit `/aid-stop` emergency stop reference and `/aid-epic-queue` for queue review so users know how to intervene safely
- **Setup MCP advanced permissions preset** — replaced the broad `mcp__*` wildcard with 7 explicit tool patterns (`mcp__shared-github__*(*)`, etc.) matching auto-mode format; updated setup wizard comparison matrix to reflect the change
- **Epic orchestration skill split** — 2300-line `epic-orchestration.md` split into 5 modular files: slim orchestrator (138 lines), `epic-state-machine.md` (602), `dispatch-protocol.md` (498), `gate-evaluation.md` (509), and `first-aid-controller.md` (577); pure refactoring with no logic changes
- **PLAN_REVIEW template enriched** — per-step detail table added to PLAN_REVIEW state with 7 columns (Files, Tech, AC count, Output, Deps) and 6 enforcement rules so plan review captures the full structure of each step
- **DONE state release logic consolidated** — release behavior now exists in exactly one place (`auto-done-state.md`); `first-aid-controller.md` DONE state delegates to `auto-done-state.md` for all release steps, eliminating duplication

## [1.0.0] — 2026-02-26

### Added

- **GitHub MCP in Setup Wizard** — `/aid-setup` now includes GitHub MCP as recommended option 6e with full setup flow covering detection, auth check, install, verification, and troubleshooting
- **Setup Completion Banner** — `/aid-setup` displays a professional styled ASCII art banner with AID branding after successful setup completion
- **Version Pre-check in Plan Epic** — `/aid-plan-epic` Step 0 reads the local plugin version, compares it with the latest GitHub release via `gh api`, and warns if outdated (non-blocking)
- **Help Workflow Examples** — `/aid-help examples` returns three step-by-step workflows: Greenfield Feature, Quick Fix, and Multi-Phase with FIRST AID
- **Autonomous Mode Commands in Help** — `/aid-help commands` now includes detailed entries for `/aid-first-aid` and `/aid-stop` under a new AUTONOMOUS MODE COMMANDS section

### Changed

- **Setup MCP Options** — re-lettered MCP sub-options so GitHub MCP is 6e, Auto-detect is 6f, and Custom is 6g; restructured Step 5b as Optional MCP Follow-up
- **Skill Count** — updated documented skills count from 20 to 21 in CLAUDE.md and README to include the previously unlisted `workflow-intelligence.md`

### Fixed

- **Stale Paths** — replaced three remaining `workspace/workflow/` references with `.aid-o/` equivalents in `planner.md`, `aid-plan-epic.md`, and `slack-mcp.md`
- **README Version** — synced README version from stale 0.9.2 to 0.9.3 (now bumped to 1.0.0 with this release)
- **Command Frontmatter** — verified all 13 commands have `user_invocable: true`

## [0.99.0] — 2026-02-26

### Added

- **AID Server** (`packages/aid-server`) — Express + WebSocket backend serving the AID GUI dashboard; 18 REST API endpoints covering projects, pipeline state, EPIC queue, decisions, evidence, audit, ideas, usage metrics, and knowledge; real-time WebSocket pub/sub with chokidar file watching on `.aid-o/`; topic-based subscriptions with heartbeat and idle timeout
- **Docker deployment** — multi-stage Dockerfile (gui-build → server-build → production) and docker-compose.yml; single `docker compose up --build` serves both GUI and API on port 3911; health check included
- **Docusaurus documentation site** — full docs site with architecture, configuration, contributing, troubleshooting, reference docs, and Getting Started guides; deployed to GitHub Pages via GitHub Actions; EN + CS locales
- **GUI frontend polish** — AI Companion panel, replay controls, error boundaries, production build optimization (FIRST AID EPIC session, 5 EPICs completed autonomously)

### Fixed

- **MDX expression errors** — escaped `{type: performance}` in `decision-policies.md` and `{message_type}`/`{action}` in `slack-integration.md` that broke Docusaurus MDX compilation
- **GitHub Pages config** — replaced all placeholder values in `docusaurus.config.ts` (`your-org` → `marekstancl`, `your-project` → `claude-aid-o`)
- **GUI Page Crashes** — added null guards to QueueScheduler, KnowledgeBase, and HealthObservatory to prevent TypeError crashes on empty data
- **WebSocket Connection** — connected useWebSocket hook in App.tsx so real-time events flow to all dashboard screens
- **CC Usage Gauge Visibility** — removed responsive hiding so CC Usage gauge is always visible in topbar, even when disconnected
- **Mobile Connection Banner** — removed `hidden md:flex` so connection status banner shows on mobile viewports
- **Project Selector Z-Index** — added z-50 to dropdown container so it renders above the sidebar overlay
- **Sidebar Responsive Collapse** — sidebar auto-collapses to icon mode on viewports below 768px with hamburger toggle and backdrop overlay
- **Pipeline Theater Empty State** — shows "No pipeline data" message instead of stale replay counter when no runs exist
- **SVG Path Animation Error** — suppressed motion.path rendering when no pipeline data is displayed, eliminating console errors
- **API JSON Fallback** — added /api/* catch-all route returning JSON 404 before static file fallback, preventing HTML responses for unknown API routes
- **Notification/Settings Buttons** — added "Coming soon" tooltips and safe click handlers to prevent crashes
- **Project Fetch Response Parsing** — fixed App.tsx legacy fetch that expected raw array but API returns `{ ok, data }` envelope, so currentProject was never set and WebSocket never connected
- **Health Observatory Audit Data** — fixed double-wrapping of audit reports array that caused latestAudit to be an array instead of an object, breaking score display
- **Health Check Route Collision** — moved Express health-check endpoint from `/health` to `/api/health` so the GUI's `/health` route (Health Observatory page) is served by the SPA fallback instead of returning raw JSON

### Changed

- **Default port** — server default port changed to 3911 (config.ts, Dockerfile, docker-compose.yml)
- **Version bump** — all packages bumped to 0.99.0 (aid-server, aid-gui, docs)

## [0.9.3] — 2026-02-25

### Fixed

- **GATES → CURATOR_RESOLVE transition** (`skills/epic-orchestration.md`) — GATES state now correctly transitions to CURATOR_RESOLVE instead of skipping directly to PM_APPROVAL; restores the full state machine flow (GATES → CURATOR_RESOLVE → PM_APPROVAL) so Curator proposals are processed for every EPIC
- **Qdrant config unification** — `memory-config.yaml` is now the single source of truth for `memory.enabled`; removed duplicate flag from `project-profile.yaml`; added non-blocking Qdrant startup probe in IDLE state for early availability detection

### Added

- **CURATOR_RESOLVE auto-mode conditionals** (`skills/epic-orchestration.md`) — in FIRST AID mode, effort:S proposals get inline fixes while effort:M/L are auto-deferred to backlog with urgency tags; failed inline fixes silently defer (non-blocking)
- **Credit exhaustion detection** (`skills/epic-orchestration.md`) — PHASE_CHECK now validates agent output before evaluation; detects 5 Claude Code credit error patterns via string matching; auto-pauses with `interrupted_step_context.json` + git stash; FIRST AID resume recovers interrupted steps
- **Wiring step generation** (`skills/planner.md`) — POST_WAVE_WIRING_CHECK detects shared files across parallel wave steps and auto-generates a wiring step with context (shared_files, contributing_steps, expected_actions); new `wiring` and `wiring_context` fields in `plan.schema.json`; EXECUTING state recognizes wiring steps with specialized dispatch prompt
- **EPIC & plan archival** (`skills/epic-orchestration.md`, `commands/aid-first-aid.md`) — DONE state archives completed EPICs to `02-epics/archive/`; QUEUE_ADVANCE archives plans when all plan EPICs complete; non-blocking with `mkdir -p` safety
- **FIRST AID ASCII art animations** (`commands/aid-first-aid.md`) — 4-frame syringe-themed startup animation, depleted-syringe completion banner with CURATOR FINDINGS summary, re-injection resume banner
- **CURATOR FINDINGS section** in FIRST AID completion report — shows implemented/deferred/rejected proposal breakdown with per-EPIC table

## [0.9.2] — 2026-02-24

### Added

- **FIRST AID Autonomous Mode** — `/aid-first-aid` starts autonomous EPIC queue execution with agent-driven quality checks replacing PM approval points; `/aid-stop` disengages immediately, restoring manual mode at the current natural pause point
- **Permission Sandwich** (`skills/permission-sandwich.md`) — automatic permission backup, elevation, and restoration for autonomous execution with crash recovery and permission learning; permissions are scoped to the auto-mode session and restored unconditionally on exit
- **Auto-Mode Escalation Protocol** (`skills/auto-escalation.md`) — 16 trigger conditions with severity classification, pause/resume flow, escalation budget tracking (max 3 before mandatory PM review), and `continue-manual` handoff option
- **Auto-Mode DONE State** (`skills/auto-done-state.md`) — automatic release decisions (defer intermediate, mandatory bump on last EPIC), queue transitions, and cross-EPIC summary aggregation to `auto-mode-state.yaml`
- **FIRST AID command** (`commands/aid-first-aid.md`) — PM-facing command to activate autonomous mode: queue confirmation, permission elevation, and auto-mode-state initialization
- **Aid-Stop command** (`commands/aid-stop.md`) — immediate autonomous mode stop command; safe mid-EPIC stop after current step completes

### Changed

- **PLAN_REVIEW** (`skills/epic-orchestration.md` Section 3) — auto-mode: schema, completeness, dependency graph, and run file quality validation replace PM prompt; validation failure triggers ESCALATION; manual mode unchanged
- **PHASE_CHECK** (`skills/epic-orchestration.md` Section 5) — auto-mode: adds one "fresh approach" retry cycle after `max_review_fix_cycles` exhausted before escalating; manual mode unchanged
- **ESCALATION** (`skills/epic-orchestration.md` Section 9) — auto-mode: pauses mode, saves progress snapshot, increments escalation counter, presents extended PM options including `continue-manual`; manual mode unchanged
- **PM_APPROVAL** (`skills/epic-orchestration.md` Section 11) — auto-mode: intermediate EPICs auto-approved; last/standalone EPIC auto-approved only after 4 guardrails pass (gates, no critical issues, escalation budget, auditor trend); rule teaching suppressed in auto-mode; manual mode unchanged
- **DONE state** (`skills/epic-orchestration.md` Section 12) — auto-mode: intermediate EPIC version bump auto-deferred, last EPIC auto-bumped; queue transition loads next EPIC automatically; auto-mode exits and restores permissions when queue is exhausted; manual mode unchanged

## [0.9.1] — 2026-02-24

### Added

- **Initial Analysis Phase** (`skills/brainstorming.md`) — mandatory structured analysis before questioning; 8-rule protocol with 4 required elements (topic understanding, key dimensions, potential challenges, clarification preview); PM confirmation gate; trivial topic escape hatch
- **Release Sub-Phase** (`skills/epic-orchestration.md`) — version bump detection and execution in DONE state; reads `release-policy.yaml` for CHANGELOG pattern, version files, multi-phase deferral; supports `json_field` and `regex` update strategies, git tagging, GitHub releases
- **Release policy config** (`defaults/policies/release-policy.yaml`) — configurable versioning: CHANGELOG header pattern, version file locations, update methods, multi-phase plan detection, git tag and GitHub release controls

### Changed

- **Questioning Protocol strengthened** (`skills/brainstorming.md`) — Rule 2 upgraded from "Prefer MULTIPLE CHOICE" to "ALWAYS use MULTIPLE CHOICE with recommendation"; added Rules 10-11 for structured directional options and contrastive reasoning
- **MUST Rules expanded** (`skills/brainstorming.md`) — 3 new entries (15-17): mandatory analysis before questions, options at every decision point, reasoning for alternatives
- **Command flow updated** (`commands/aid-brainstorm.md`) — 10-step → 11-step flow; new Step 2 (Analysis) inserted between Context and Questions; all subsequent steps renumbered with cross-references updated
- **DONE state enhanced** (`commands/aid-run-epic.md`) — Release Sub-Phase integrated before branch merge; DONE action items reordered (run file update → release → merge → archive)

### Fixed

- **Example EPIC lookup type filter** (`skills/brainstorming.md`) — changed from `"example_epic"` to `"example"` to match actual frontmatter in 19 example files
- **Example EPIC lookup scan** (`skills/brainstorming.md`) — changed from flat `defaults/examples/` to recursive `defaults/examples/**/*.md` to find files in subdirectories

## [0.9.0] — 2026-02-24

### Added

- **Plan-ref injection** (`skills/epic-orchestration.md`) — dispatch template now includes `plan_ref` with Source Plan Integration protocol: 3-strategy matching cascade (keyword → heading → sequential), 3000-line truncation guard, `<plan_context>` block in agent prompts
- **Sequential ID generation** (`skills/epic-orchestration.md`) — ID Format Specification for Plans (`P{NNN}`), EPICs (`E-{NNN}-{epic_run}_{plan_step}`), and Runs (`R-{NNN}-{epic_run}_{plan_step}-{run_seq}`); Counter File protocol (`counter.yaml`); atomic increment rules
- **Evidence Incomplete detection** (`agents/auditor.md` section F.5) — `evidence_incomplete` finding type with `-3` deduction per missing mandatory file; only checks completed steps
- **Mandatory Evidence Write Checklist** (`skills/epic-orchestration.md`) — Step Evidence File Types table listing mandatory vs optional evidence files per step

### Changed

- **SESSION → RUN terminology** — renamed across 45+ files: `session` → `run`, `session-management.md` → `run-management.md`, `session-validator.md` → `run-validator.md`, 4 template files renamed; `sessions/` directory → `runs/`
- **Flat evidence structure** (`commands/aid-run-epic.md`, `skills/epic-orchestration.md`) — removed 5 empty subdirectory creation (analysis/, discovered_issues/, parallel_groups/, prompts/, reviews/); evidence now written directly to `steps/step_{N}_{role}/`
- **Budget references removed** — removed budget estimation lines from `defaults/templates/epic.md`, `defaults/templates/epic-example.md`, `skills/brainstorming.md`
- **Auditor check #12 path updated** (`agents/auditor.md`) — `evidence/discovered_issues/` → `steps/step_{N}_{role}/discovered_issues.md`
- **Analysis-merge evidence paths** (`skills/analysis-merge.md`) — `evidence/{epic_id}/{run_id}/analysis/` → `steps/step_{target}_{role}/`

## [0.8.2] — 2026-02-23

### Fixed

- **Czech-language content removed** — translated all Czech text to English in `agents/lessons-extractor.md`, `skills/session-management.md`, `skills/agent-core.md`
- **Broken skill reference in `aid-epic-queue.md`** — `skills/aid-epic-queue.md` → `skills/epic-queue.md`, `aid-epic-queue.yaml` → `epic-queue.yaml`
- **Stale `workspace/workflow/` paths** — 12 legacy path references replaced with `.aid-o/` equivalents in `skills/session-management.md`
- **Stale command prefixes** — `/run-epic` → `/aid-run-epic`, `/plan-epic` → `/aid-plan-epic` in `skills/retry-engine.md`, `skills/planner.md`, `defaults/templates/epic-example.md`
- **Version mismatches** — header/footer versions aligned to 0.8.2 in `session-management.md`, `epic-orchestration.md`, `retry-engine.md`, `planner.md`, `agent-core.md`
- **Hardcoded Slack channel ID** — replaced `C0AFP2GP459` with `YOUR_CHANNEL_ID` placeholder in `commands/aid-setup.md`
- **Plugin README version** — updated from 0.4.1 to 0.8.2

### Added

- **Untrusted-content framing** — SECURITY section in `skills/epic-orchestration.md` documenting mandatory `<untrusted_content>` tags for user-provided content in dispatch prompts (CWE-77, OWASP LLM01)
- **Advanced preset warning** — explicit risk documentation and PM confirmation requirement in `defaults/policies/permissions.yaml`

### Changed

- **CLAUDE.md structure info** — corrected command count (10 → 11) and skill count (14 → 17); removed stale `docs/` directory reference
- **CHANGELOG alignment** — root and plugin `[0.8.1]` entries made identical per CLAUDE.md policy

## [0.8.1] — 2026-02-23

### Added

- **Process Audit type** (`agents/auditor.md` section F) — 6th audit type, always runs, with 13 checks across 4 categories: F.1 EPIC Lifecycle (3 checks), F.2 Evidence Completeness (6 checks), F.3 Cross-Validation (3 checks), F.4 Stage Log Integrity (1 check); deduction-based scoring (0-100); `process: {0-100}` field added to YAML output; 15% weight in Overall score; Score Overview template updated with Process row

### Changed

- **Audit weight redistribution** (`agents/auditor.md` weight table) — Documentation 20% → 25%, Process 15% added; total always-run audit types: 3 → 4; audit type count: 5 → 6

## [0.8.0] — 2026-02-23

### Added

- **CURATOR_RESOLVE state** — new state between GATES and PM_APPROVAL in the epic-orchestration state machine; auto-evaluates Curator proposals via 3-tier algorithm (YAML rules → Qdrant history → default), dispatches fix agents, writes lessons with 3-layer dedup
- **`curator_auto_rules`** in `decision-policies.yaml` — configurable auto-resolution rules for improvement proposals
- **PM override + rule teaching** at PM_APPROVAL — PM can override rejected proposals and teach new auto-rules that persist via YAML + Qdrant
- **Improvement Pipeline analytics** — Report Type 4 in `/aid-analytics` for curator pipeline metrics
- **3-layer Lessons-Extractor dedup** — text, semantic, and Qdrant cross-project deduplication

### Changed

- **State machine**: 11 → 12 states (CURATOR_RESOLVE inserted)
- **DONE state simplified**: Curator + Lessons-Extractor moved to CURATOR_RESOLVE
- **`backlog.md`**: PROP-* IDs migrated to IMP-{NNN} with legacy alias table
- 9 files updated across agents, skills, commands, and policies

## [0.7.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.6.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.5.0] — 2026-02-22

### Added

**Phase 1 — Research + Storage + Consumption:**
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

**Phase 2 — On-Demand Research + Aging:**
- **`/aid-research` command** — on-demand research for specific frameworks/libraries; `--deep` mode for comprehensive documentation ingestion
- **Aging protocol** — TTL-based freshness weighting for all document types (90–365 days); stale/expired score multipliers (0.7/0.3); automatic exclusion after 180 days past TTL
- **Manual source addition** — conversational flow for adding documentation sources via URL or topic
- **Freshness weighting in `memory_find()`** — search results weighted by document age; stale chunks deprioritized automatically
- **Aging config in `memory-config.yaml`** — per-type TTL values, stale/expired weights, exclusion threshold

**Phase 3 — Auto-Extraction + Community Examples + Feedback:**
- **Example EPIC extraction protocol** — 7-stage `extract_example_epic()` function: eligibility check → extract → abstract → build text → PM approval → dedup → Qdrant storage; triggered in DONE state step 9b
- **`example_epic` document type** — Type 8 in memory-mcp.md with 11 metadata fields (frameworks, archetype, source_epic_id, complexity, roles, etc.); never-expire TTL; global project scope
- **Community example EPICs** — 3 curated templates in `defaults/examples/`: `langchain-rag-chatbot.md`, `fastapi-crud-service.md`, `react-dashboard.md`; placeholder paths, version ranges, standard EPIC template format
- **Example EPIC lookup in brainstorming** — Step 3 searches `defaults/examples/` + Qdrant for matching archetypes; PM offered: (A) Adapt, (B) Browse all, (C) Start fresh
- **Feedback tracking** — fire-and-forget `track_retrieval()` after `memory_find()`; tracks `times_retrieved` and `avg_retrieval_score` per framework in `knowledge-base.yaml`; deprecation signal after 180 days of zero retrievals
- **Feedback config in `memory-config.yaml`** — `feedback:` section with `track_retrieval`, `track_usefulness`, `deprecate_unused_after_days`

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"
- **DONE state in `epic-orchestration.md`** — new step 9b triggers example extraction after Curator; completion summary includes archetype when pattern is stored
- **`memory-mcp.md` document types** — expanded from 6 to 8 types (added Proposal, Example EPIC); feedback tracking hook in `memory_find()`
- **`brainstorming.md` non-blocking guarantee** — knowledge calls updated from 2 to 3 per session (Step 1 search + Step 3 knowledge + Step 3 examples); 7 new graceful degradation scenarios

## [0.4.2] — 2026-02-21

### Changed
- **`/plan-epic` step numbering** — renumbered all steps from fractional (0.5, 0.7, 2.5) to clean integers (1-9); internal cross-references updated
- **`/aid-brainstorm` step numbering** — renumbered Step 8b→9 and Step 9→10; new Step 10 presents interactive A-D handoff options (add items, all-phases EPIC, specific-phase EPIC, manual)
- **Cross-references** — updated plan-epic step references in run-epic.md (3 occurrences) and epic-orchestration.md (2 occurrences); updated aid-brainstorm.md and brainstorming.md internal refs

### Added
- **`/aid-init [path]` parameter** — documented optional path parameter in aid-init.md Usage section with examples for relative and absolute paths; updated aid-help.md entry
- **Phase selection** — plan-epic.md Step 2 now handles all-phases vs specific-phase EPIC generation when invoked from brainstorming with phase context
- **Re-opening protocol** — brainstorming.md documents how Option A (add items) works: load existing plan, display approved sections, return to Step 2, re-generate EPIC
- **Phase Selection section** — brainstorming.md EPIC Subagent Prompt Template includes phase handling for scoped EPIC generation

## [0.4.1] — 2026-02-20

### Added
- **`/aid-init` upgrade mode** — detects existing workspace, compares installed vs. plugin version, classifies files as NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED, asks PM before updating
- **Config manifest** — `.aid-o/03-config/.aid-manifest.yaml` tracks installed plugin version and md5 checksums of all config files; enables safe detection of PM customizations
- **Dynamic defaults scanning** — `/aid-init` scans `defaults/` directories instead of hardcoded file list; new files in future versions are automatically included
- **`source_plan` in plan schema** — `defaults/templates/plan.schema.json` now includes the `source_plan` field for Variant B pipeline

### Changed
- **CHANGELOG format** — standardized all entries to `**Bold Name** — description` format; root and plugin CHANGELOGs are now identical
- **CLAUDE.md release protocol** — added CHANGELOG format standard, README Roadmap update rules, and 10-step release workflow
- **`/aid-init` description** — updated in `aid-help.md` to reflect upgrade capabilities

## [0.4.0] — 2026-02-20

### Added
- **Zero Detail Loss Pipeline (Variant B)** — EPIC references source plan via `plan_ref`; all pipeline stages (plan.json, session, agent dispatch) read both EPIC and source plan; agents receive `## Source Plan — Implementation Detail` sections
- **Wave-based execution model** — planner groups steps by DAG level into waves (max 4 per wave) for parallel execution; replaces flat parallel group detection
- **Step decomposition** — layer-based splitting of monolithic steps (data → schema → API → test) to enable cross-domain parallelism; supports dev, docs, and infra decomposition types
- **Critical path analysis** — opt-in for 7+ step EPICs; computes critical path ratio, applies 5 relaxation rules (R1–R5) to shorten it; PM can reject individual relaxations at PLAN_REVIEW
- **Parallelism-first optimization** — 5-priority strategy (parallelism > wave density > session compactness > quality > efficiency); plan quality metrics in `optimization_metrics`; validation rules V-20–V-23
- **`/plan-epic` accepts Plan files** — 3-tier format detection (frontmatter → header → section fingerprinting); auto-generates EPIC from Plan using EPIC Subagent Template
- **`/aid-brainstorm` inline execution** — Step 8b offers to generate Plan JSON + Session immediately after EPIC draft; Step 9 split into 9a (standard handoff) / 9b (full pipeline handoff)
- **Wave-based session boundaries** — sessions are contiguous sequences of waves; never split by domain or inside a wave
- **Shorthand commands** — all 18 commands have `user_invocable: true` frontmatter enabling `/aid-setup` instead of `/aid-orchestrator:aid-setup`
- **Setup followup** — after "All recommended", `/aid-setup` now offers additional options (CLAUDE.md, Slack, auto-detected MCPs)
- **Selective `.aid-o/` gitignore** — plans, EPICs, and config are versioned; engine artifacts (sessions, evidence) are ignored
- **Centralized Qdrant storage** — `~/.local/share/aid-orchestrator/qdrant-data` with `--scope user` for global MCP; migration check for old paths

### Changed
- **EPIC template** — typed artifacts (`endpoint:`, `model:`, `component:`), `plan_ref` enforcement, Hints section, Scope with specific file paths
- **EPIC Subagent Template** — frontmatter instructions, plan task ID preservation in steps, Variant B zero detail loss instruction
- **Planner input validation** — REQUIRED/RECOMMENDED checks with typed artifact inference
- **PLAN_REVIEW** — rich plan summary with wave execution plan, optimization metrics, session breakdown
- **EXECUTING state** — agent dispatch enriched with source plan sections
- **Plan generation flow** — 13-step procedure with decomposition (2.2), wave assembly (6), CPA (6.1), session boundaries (11)

## [0.3.0] — 2026-02-19

### Added
- **Execution Summary block** — mandatory in all agent outputs with timing, self-assessment, and Qdrant storage
- **Per-agent metrics** — step duration, complexity self-report, bottleneck flags stored to Qdrant
- **Cost optimization skill** — 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking
- **EPIC completion summary** — 5 next-step options presented to PM at DONE state
- **Auto-archive** — multi-EPIC and multi-session counter awareness for session and EPIC files
- **Multi-session flow** — planner optimization engine for EPICs with 7+ steps
- **Diff patches** — `diff.patch` generation for every file-modifying step, saved to evidence store
- **Curator auto-invocation** — mandatory synchronous step in POST_PROCESSING
- **Chat-first `/aid-setup`** — detailed option presentation and guided configuration
- **Post-setup guidance** — `/aid-brainstorm` recommendation after onboarding
- **Playwright E2E agent** — optional parallel step, auto-added when frontend detected
- **Application type classification** — 11 types in project scanner (web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, infrastructure)
- **Auto-scaffold** — generates starter files for uninitialized projects before EPIC execution
- **Cross-project knowledge** — Qdrant with `project_name` metadata tagging for multi-project memory
- **Backlog categorization** — by type (bug, enhancement, tech-debt, security, docs) and source agent
- **`/aid-analytics`** — orchestration performance analysis command and skill
- **Permission presets** — dual-write system keeping `.claude/settings.json` + `.aid-o` policies in sync
- **Git branch integration** — one branch per EPIC session, auto-create and auto-merge
- **Pre-Output Quality Check** — in all code-producing playbooks (ruff lint/format, debug artifact removal, import verification)

### Fixed
- **DONE state** — now writes lessons to `lessons-learned.md`, updates session status to `completed`, writes commands to `command-history.md`, writes final `stage_log` entry with `result: success`
- **Gate reconciliation** — `plan.json` gates now reconciled with `gates.yaml` definitions
- **Qdrant isolation** — writes now include `project_name` metadata for cross-project isolation
- **Slack MCP** — onboarding corrected to use `@anthropic/slack-mcp` package with proper scopes

### Changed
- **Agent model assignments** — QA, Security, Docs agents use Sonnet; utility agents use Haiku
- **Dispatch prompts** — trimmed to deps-only context, EPIC summary, and playbook reference
- **`/aid-help` examples** — updated with full-stack development examples
- **Memory search** — `top_k` reduced from 5 to 3 for relevance and cost optimization
- **Git Discipline** — section added to all 9 role playbooks

## [0.2.0] — 2026-02-18

### Added
- **`/aid-brainstorm`** — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
- **Brainstorming skill** — process rules, key principles, EPIC subagent prompt template
- **MCP server onboarding** — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- **Permission presets** — Safe / Recommended / Advanced in `/aid-setup`
- **Document language** — `language.yaml` configuration with ISO 639-1, default EN
- **Parallel isolation strategy** — `dispatch-strategy.yaml` with worktrees / branches / sequential
- **Git worktree support** — creation and cleanup logic for parallel agent dispatch
- **Qdrant orchestration logging** — dispatch and completion events with graceful JSONL fallback
- **Enriched `final_report.md`** — generation from Qdrant data
- **Lessons learned** — auto-collection and storage in Qdrant at EPIC completion
- **CLAUDE.md marker merge** — `<!-- AID-O START/END -->` markers in `/aid-init`
- **Interactive examples** — `/aid-help examples` with 3 project prompts

### Changed
- **`/aid-setup`** — includes 4 new configuration steps (MCP, permissions, language, isolation)
- **`/aid-init`** — copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- **LLM cost estimates** — conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- **`examples/bookmark-manager/`** — replaced by interactive `/aid-brainstorm` prompts

## [0.1.0] — 2026-02-16

### Added
- **Initial release** — Controller + Workers architecture for Claude Code
- **17 slash commands** — `/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.
- **18 agents** — 9 role + 3 specialist + 6 utility
- **13 skills** — epic orchestration, planner, gates engine, parallel dispatch, etc.
- **11 role playbooks** — customizable per project
- **Quality gates** — auto-retry (3x) and PM escalation
- **Slack MCP integration** — with chat fallback
- **Qdrant vector memory** — optional, with file-based fallback
- **EPIC queue** — autonomous sequential execution
- **Evidence trail** — `stage_log.jsonl`, gate reports, agent outputs
## [2.46.0] — 2026-06-30

### Added
- **DG-15 Route Resolve** — Literal link vs declared route-files probe (react-router/express); opt-in via delivery-map.yaml routes section; config_missing when framework unsupported or map absent
- **DG-17 Independent Oracle No-Drop** — Analytics output cardinality vs declared baseline; requires analytics_output_file + expected_cardinality; missing file → config_missing, not fake pass
- **DG-18 Acceptance Provenance** — FSM step-verify evidence adapter; surfaces acceptance history into delivery-gate.json; never emits fail (provenance-only)
- **delivery-map.schema.json** — JSON Schema for delivery-map.yaml (meta/routes/oracle_baselines, all optional)
- **aid-delivery-map.sh** — Accessor library for delivery-map.yaml with pinned exit-code contract (null → exit 2)
- **map_section_globs + has_acceptance_evidence** — Two new dispatcher condition types in aid-delivery-gate.sh

### Changed
- **enforcement-registry.yaml** — Added DG-15/17/18 rows (surface: delivery-gate, observe, planned E10); totals.enforcements corrected to 258

## [2.44.1] — 2026-06-29

### Fixed
- **`aid-acceptance-evidence.sh` + `aid-consumption-proof.sh` protocol-v2 envelopes** — both scripts now emit full protocol-v2 envelope (`schema_version`, `identity`, `subject`, `revision`, `status`, `verdict`, `provenance`); `revision.head_sha` carries the full 40-char git SHA (was short SHA, broke `--current-head` validation)
- **`aid-acceptance-evidence.sh` step naming** — verifier evidence files looked up as `step-1.md` (1-indexed, no zero-padding) instead of `step-00.md`; `ac_id` suffix changed from `_00` to `_1`
- **`aid-consumption-proof.sh` false-verified** — Strategy 2 (filename pattern fallback: `*contract*`/`*binding*`) removed; only Strategy 1 (grep for binding_id) is valid
- **`consumption_proof` protocol-v2 type registration** — added to `aid-protocol-validate.sh` + fixtures (`valid.json`, `invalid-missing-payload.json`)
- **Enforcement registry planned rows** — `semantic_wiring_would_block`, `c2_acceptance_deviation`, `c2_consumption_unresolvable` now carry `status: planned`, `deadline/deferred_until/promotion_phase: E10`
- **FC-24..28 fingerprints** — `fc{NN}neg` contained non-hex chars; fixed to `fc{NN}000...` (64 valid hex chars)
- **Evidence pack regenerated at HEAD** — `delivery-gate.json`, `acceptance-evidence.json`, `consumption-proof.json` regenerated; all pass `aid-protocol-validate --current-head --check-fingerprint`

### Added
- **E5 wiring-gate bats test** — `E5 wiring-gate observe: Critical finding logged but increment proceeds`; seeds Critical finding in `semantic-review-wiring.json`, asserts exit 0 + `semantic_wiring_would_block` in `timeline.jsonl`
- **T8 fingerprint schema validation** — `test-semantic-review.sh` T8 verifies `sha256:[0-9a-f]{64}` format per FC fixture
- **T9 mutation-survives + low-profile-no-local** — merge count dedup + final-only dispatch-mode tests
- **T10 `--current-head` regression guard** — both `aid-acceptance-evidence.sh` and `aid-consumption-proof.sh` output verified against `aid-protocol-validate --current-head` in test harness

## [2.44.0] — 2026-06-29

### Added
- **C2 Semantic Review Engine (observe)** — 4-mode dual-emit engine (local/wiring/behavior/final) producing auditable `semantic-review-{mode}.json` alongside the existing `.md` gate (D1 unchanged); 12-lens catalog from failure-mode-control-matrix FC-09, FC-24..28, FC-30..32, FC-35; no-mega-prompt rule (D2); observe-only (E5), blocking deferred to E10
- **Wiring-gate observe** — `cmd_increment_step` logs `semantic_wiring_would_block` on unresolved Critical/High wiring findings; `SEMANTIC_REVIEW_POLICY=blocking` enables E10 blocking path without code change
- **`aid-finding-merge.sh`** — lossless fingerprint-keyed merge: severity=max, detail=union sorted, conflicts in `merge_meta`; deterministic output
- **`aid-acceptance-evidence.sh`** — reconstructs `acceptance-evidence.json` from plan.json AC + LLM coverage signals (`## AC Coverage` block); ac_id=sha256[:12]_step_idx; D3: bash aggregates, LLM determines coverage
- **`aid-consumption-proof.sh`** — verifies contract-manifest.json bindings against evidence_dir (grep+filename); fail-safe: missing manifest → `unresolvable` + exit 0
- **`review-profile-check.sh` E5** — `completed_lenses` read from `lenses_run[]` union across `semantic-review-{mode}.json`; E3 backward-compat: no C2 files → same `COMPLETED_LENSES=""` behavior
- **FC-24..28 negative fixtures** — 5 runnable JSON fixtures for transaction_boundary, field_lineage, negative_case, operation_order_resource_bound, requirement_test_drift failure modes
- **`test-semantic-review.sh`** — 8-test harness covering merge, acceptance-evidence, consumption-proof, review-profile-check (E5+E3 backward-compat), fixture validity
- **Enforcement registry** — 9 new C2 entries covering wiring-gate, dual-emit, lens catalog, acceptance-evidence, consumption-proof, completed_lenses, requirement-drift, finding-merge, semantic-review-policy
- **`docs/extending-aid.md`** — C2 extension guide: how to add lenses, dual-emit protocol, fingerprint format, policy promotion path

## [2.43.0] — 2026-06-28

### Added
- **C0 Plan Contract Gate** — observe-only gate layer running in `aid-auto-pipeline.sh` after plan-graph extraction, producing `plan-graph.json`, `contract-manifest.json`, and `plan-review.json` with 5 semantic lenses (observe, E10 promotion target)
- **Shared Kahn topo-sort lib** — `scripts/lib/aid-plan-graph.sh` with `build_plan_graph` function and deterministic `topological_order` output; `aid-epic-to-json.sh` refactored to use it
- **C0 QA harness** — `test-c0-contract.sh` with 66 assertions across 7 fixture sets (clean, cycle, dup-id, p045-style, per-lens, blocking-mode, clean-low-risk)

## [2.42.1] — 2026-06-28

### Added
- **E3 Adaptive Review Profile Detector** — deterministic, LLM-free resolver (`aid-prefilter.sh profile`) computes surface→lens matrix from plan-time + candidate-time git diff union; emits `review-profile.json` with `required_lenses`, `profile_hash`, `risk_profile`, and IR cadence; FSM observe hook logs `missing_lenses` telemetry without blocking (promotion to blocking in E10); 6 surfaces, 5 risk profiles, 13-scenario test harness.

## [2.41.2] — 2026-06-28

### Fixed
- **CI: dg07/dg12 bash-test failures** — delivery-gate fixture `.aid-o/` trees were gitignored by `**/.aid-o/`; added exception in `.gitignore` matching the existing `mini/` pattern; fixture files (`fsm-state.yaml`, `execution.yaml`) are now tracked and available in CI.
- **CI: dg12 unverifiable on GitHub Actions** — `yq` was not installed in the `bash-tests` job; `dg12-authority.sh` fell through to exit=2 instead of parsing the authority YAML and returning exit=1; added `yq` install step.
- **CI: vitest `@aid/contract` resolution failure** — `dist/` is gitignored so `@aid/contract/dist/index.js` was absent in CI; added `npm run build -w @aid/contract` step before `npm test` in the vitest job.

## [2.41.1] — 2026-06-28

### Changed
- **False-Green Guardrails in Verify Commands + Contracts** — `aid-verify-implementation` and `aid-verify-plan` now enforce four additional review requirements: (1) mandatory "Independent runtime path check" output section — DONE review cannot be based on "tests pass" alone; (2) every AC using "always"/"all"/"each"/"never" must define its exact universe or the plan/AC is rejected as not objectively verifiable; (3) eval/evidence artifacts must name which pipeline slice they actually exercise; (4) every new integration function requires at least one caller-flow test, not just a unit test of the pure helper. Same four guardrails added to `review-checkpoint-contracts.md` so they apply to in-pipeline CP2–CP5 reviews, not only the manual verify commands.

## [2.41.0] — 2026-06-27

### Added
- **Evidence Pack Verifier CLI (E2.5)** — `aid-evidence-verify.sh <epic> <run> [--out <path>] [--at-head]` deterministically verifies a completed run's evidence pack: git cleanliness, artifact freshness (as-of-pack, ancestor-of-HEAD; strict `--at-head` mode for live DONE-review), protocol-v2 validation + finding fingerprints per artifact, TTL/registry guard, and observe-vs-blocking interpretation consistency; emits `verification-report.json` (protocol-v2, self-validated) + human summary; standalone CLI outside FSM.
- **`verification_report` Protocol-v2 Type** — 15th artifact type in `aid-protocol-v2.schema.json` enum + `VALID_ARTIFACT_TYPES` validator array + `TYPE_PAYLOAD_MAP` entry + `verification-report.schema.json` type schema.
- **Evidence Verifier QA** — 11 purpose-built fixtures (clean-pack, ancestor-pack, divergent-stale, inconsistent-head, invalid-artifact, enum-garbage, mixed-legacy, nondeterministic-fingerprint, dirty-git, ttl-violation, enforcement-absent) + `test-evidence-verify.sh` harness + golden sample; every check has positive and negative coverage.
- **Enforcement Registry** — 7 verifier checks registered in `defaults/enforcement-registry.yaml` (`surface: internal-guard`, `status: planned`, `deadline: 2027-06-01`); FSM wiring deferred to E9.

## [2.40.0] — 2026-06-26

### Added
- **C1 Delivery Engine** — `aid-delivery-gate.sh` + 12 DG check plugins (DG-01..12) producing protocol-v2 `delivery-gate.json`; observe mode (E2): writes `delivery_gate_would_block` telemetry, never blocks FSM transitions; blocking promotion deferred to E10.
- **Delivery Gate Policy** — `defaults/policies/delivery-gate.yaml` with profile detection (plugin-bash, npm-workspaces, unverifiable) and per-profile check commands; `skip_reason_allowlist` enforces closed vocabulary.
- **Profile Resolver** — `scripts/lib/aid-delivery-profile.sh`: `resolve_profile` + `select_commands` for deterministic argv-array dispatch (no eval).
- **DG-07 FSM Hook** — observe-mode hook in `cmd_done_advance` writes `delivery_gate_would_block` event to timeline; blocking branch is live code tested by `test-fsm-dg07-observe.bats`.
- **Full Delivery Gate Schema** — `defaults/schemas/delivery-gate.schema.json` expanded to full protocol-v2 payload covering `delivery_gate.{phase,profile,freshness,delivery_ready,checks[],summary}`.
- **QA Fixtures + Harness** — 10 per-DG fail/unverifiable fixtures, golden sample, 44-assertion `test-delivery-gate.sh`; every DG-01..12 check has at least one fixture proving it is not an untested decoration.
- **Gate Coverage Fields** — `aid-run-gates.sh` now emits `covered_paths`, `changed_paths_covered`, and `relevance` (direct|partial|none|unknown) in `gates_report.json`.
- **Enforcement Registry** — DG-07 FSM hook + DG-01/04/07/12 registered in `defaults/enforcement-registry.yaml` as observe-mode (status: planned, deadline: E10).

## [2.38.0] — 2026-06-23

### Added
- **`/aid-verify-plan` + `/aid-verify-implementation`** — two manual, PM-invoked commands that dispatch an independent fresh-context agent to adversarially review a plan before execution and an implementation after it claims DONE; each carries its full review protocol (false-green risks, producer-consumer contracts, runtime-not-statics, real-data oracle) and returns a severity-ranked verdict plus a Czech PM summary. Standalone tools outside the FSM (like `/aid-do`) — no `fsm-state.yaml`, no evidence dir, no pending-dispatches ledger.
- **AID Control System v2 protocol** — shared protocol v2 envelope (`aid-protocol-v2.schema.json`), 14 type-specific schemas, deterministic finding fingerprint helper (`aid-finding-fingerprint.sh`), and authoritative bash+jq validator (`aid-protocol-validate.sh`) with 11 blocking invariants (exit codes 2-13); schemas + validator + fixtures only — no runtime wiring (E2+).

### Fixed
- **Protocol v2 `control_protocol` enum** — validator now enforces enum membership (exit 8) in addition to field presence (exit 3); previously any non-`legacy` value (e.g. `"banana"`) passed as exit 0; fixture `invalid-bad-control-protocol.json` and consistency check added.

## [2.37.0] — 2026-06-21

### Added
- **Per-step Acceptance Criteria pre-flight** — `aid-epic-to-json.sh` hard-fails a multi-step EPIC that carries fewer acceptance criteria than steps, so every step has a contract the CP chain can verify (root cause of the E-047-4_7 cockpit REOPEN); override deliberately with `AID_ALLOW_SPARSE_AC=1`.

### Fixed
- **Plan→EPIC acceptance-criteria + role extraction** — `aid-plan-to-epic.sh` now reads acceptance criteria written as plain `-` bullets under `**Acceptance Criteria**` (with or without a colon) and the `**AID Role**` header without a colon; previously it matched only the `**Acceptance Criteria:**` + `- [ ]` + `**AID Role:**` forms, silently dropping every criterion (empty EPIC AC section) and defaulting every step to the `backend` role.
- **Compliance `overall` is severity-aware** — `write_compliance_json` now derives `overall` from blocking failures only (advisory-severity failures are recorded in `failures[]` for visibility but no longer flip it to `fail`), matching the `cmd_done_advance` release gate; previously a single advisory check such as `branch_correct:false` on a PM-controlled shared feature branch produced `overall:fail` even though the FSM correctly released, a self-contradictory record. The provenance-unverifiable integrity signal stays blocking.

## [2.36.2] — 2026-06-19

### Fixed
- **`aid-plan.md` stale CP1 lens names** — CP1-deep section updated from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement`; evidence file table updated with correct filenames and required-field column (producer→consumer drift fix).
- **`aid-cp1-gate.sh` stale header comment** — file header comment updated to match L1/L2/L3 filenames and content requirements.

### Added
- **P046 boundary manifest and delivery report committed** — `.aid-o/reports/P046-boundary.md` and `.aid-o/reports/P046-delivery.md` now tracked in git; `.gitignore` glob fix (`.aid-o/*`) makes this possible.

## [2.36.1] — 2026-06-19

### Fixed
- **CP1-deep empty-file bypass** — `aid-cp1-gate.sh` previously accepted empty evidence files (only checked `-f`); gate now requires non-empty files (`-s`) and the required field at line-start (`stop_rule_blockers:` in lens files, `verdict:` in adjudicator); empty or structurally incomplete files now fail the gate.
- **CP1-deep lens taxonomy mismatch** — lenses renamed from `security/correctness/architectural` to `L1-behavior/L2-feasibility/L3-enforcement` per plan P046 taxonomy; L3 (enforcement/CI/artifact-visibility) is the class that catches gitignored artifacts and non-executing tests.
- **`/aid-init` `.gitignore` guidance** — instruction corrected to replace `.aid-o/` with `.aid-o/*` before adding `!.aid-o/reports/`; git cannot un-ignore content inside an ignored directory — the glob form is required.

## [2.36.0] — 2026-06-19

### Added
- **Behavior-first review contracts** — `skills/review-checkpoint-contracts.md` defines per-checkpoint diff scope, high-risk pattern table (8 categories: auth, routes, validation, migrations, FSM, security sinks, payment, deps), and structural gate rules for CP2/CP3/CP4/CP5/CP6 and CP1-deep.
- **`behavior_trace` structural gate** — `aid-fsm.sh:fsm_check_verifier_output()` rejects verifier outputs where `behavior_trace_required: true` but `behavior_trace_count` is 0 or missing; gate is opt-in and fires only when the verifier explicitly sets the flag.
- **Additive verifier output fields** — `verifier-output-template.md` gains optional top-level fields (`checkpoint`, `focus`, `behavior_trace_count`, `behavior_trace_required`, `behavior_trace`) that extend the output without displacing existing `_generated_by`/`classification`/`verdict` greps.
- **`aid-prefilter.sh --checkpoint` flag** — caller can now pass `--checkpoint <cp2|cp3|cp4|cp6>` to get checkpoint-specific diff scope; CP2 defaults to `HEAD~1..HEAD`, CP3 reads `base_commit` from `fsm-state.yaml`.
- **CP1 risk-scaling** — `aid-plan.md` gains a CP1 Mode Selection section defining CP1-light (standard checklist) vs CP1-deep (three-lens: security/correctness/architectural, adjudicator, max two revisions, PM escalation on unresolved stop-rules).
- **`aid-cp1-gate.sh`** — EPIC generation gate that reads plan frontmatter (`id`, `risk`), scans body for eight high-risk pattern categories, and verifies four evidence files (`cp1-deep/` directory) when risk is high; includes path-traversal guard on plan ID.
- **Enforcement homes reference** — `docs/extending-aid.md` gains an Enforcement Homes Reference section documenting where each enforcement mechanism lives (plan-close, FSM precondition, behavior_trace gate, CP5 blocking_findings, CI floor).
- **Two new enforcement registry entries** — `cp1_critical_path_flow_trace` (type lm_judgment_advisory, surface cp1) and `behavior_trace_high_risk_gate` (type fsm_precondition, surface cp2/cp3/cp4); both carry `deadline: 2026-09-01`, `status: active`, `verdict: ALIGNED`.
- **6 bats tests for behavior_trace gate** — `bats/test-behavior-trace.bats` covers count=0+required=true→fail, count=3+required=true→pass, required=false→pass, field absent→pass, count missing→fail, count=1→pass.

### Fixed
- **`.gitignore` negation pattern** — replaced `.aid-o/` directory exclude with `.aid-o/*` glob so `!.aid-o/reports/` negation works; git cannot un-ignore content inside an ignored directory.
- **CP1 gate `risk: low` precedence** — high-risk body pattern match now always triggers CP1-deep regardless of `risk: low` frontmatter; `risk: low` previously overrode the pattern scan (wrong behavior).
- **Frontmatter parser state machine** — `aid-cp1-gate.sh` parser now uses open/close `---` state machine; stops reading at opening marker, reads to closing marker, rejects plans with unclosed frontmatter instead of silently reading body as frontmatter.
- **Rule #21 `REVISE_REQUIRED` advisory label** — `plan-writing.md` rule #21 REVISE_REQUIRED outcome labeled "(advisory — see 21c, PM can override)" to match enforcement type; test-plan-writing-rules.bats updated (removed dead `FIXTURES_DIR` variable).

## [2.35.0] — 2026-06-18

### Added
- **`plan-close` FSM command** — enforces all four required reports (curator, auditor, simplifier, delivery) before writing the `ca-review-complete` marker; raw `touch` is explicitly forbidden and `pipeline.md §7` directs implementers to this command instead.
- **Toggle-skip for disabled specialists** — `simplifier.enabled:false` / `reporter.enabled:false` in `execution.yaml` exempts the corresponding report from `plan-close`; each skip is audited to `audit-log.jsonl` with specialist name and rationale.
- **`simplifier_report_present` compliance measurement** — `compliance.json` now carries `simplifier_report_present: null/true/false` (advisory severity); anchored for future enforcement promotion.
- **Boundary manifest (committed, CI-readable)** — Reporter writes `.aid-o/reports/{plan_id}-boundary.md` after every completed plan; carries provenance for all four required reports and is readable by CI without accessing gitignored evidence directories.
- **CI floor check** — `defaults/ci/plan-boundary-required-check.yml` (GitHub Actions) verifies that committed boundary manifests are complete; exits 0 gracefully when no manifests are present.
- **`/aid-audit` CI check residual** — `/aid-audit` verifies whether the boundary CI check is installed and explicitly surfaces the residual when it is not.
- **`/aid-init` optional CI check installation** — fresh or upgraded workspaces are offered the option to copy `plan-boundary-required-check.yml` to `.github/workflows/`.
- **Force-override audit enrichment** — `init --force` pre-scans to identify the blocking plan/EPIC and passes `--blocking-epic` / `--blocking-plan` to `fsm_handle_force_override`, writing both to `timeline.jsonl` and `audit-log.jsonl`.
- **13 new bats assertions** — `test-plan-close.bats` (9 tests: missing reports, toggle-skip, audit entry) and `test-ci-floor.bats` (4 tests: no manifests, valid manifest, incomplete manifest, missing delivery).
- **`_aid_read_toggle()` helper** — yq-free toggle detection extracted into a shared function, eliminating duplicated grep chains in `cmd_plan_close` and `fsm_eval_simplifier_present`.

## [2.34.2] — 2026-06-18

### Fixed
- **`plan_diff` evidence truthfulness** — gate runner recorded `result: "pass"` for exit-2 graceful skips (no AC blocks / legacy plan), making `gates_report.json` claim verification happened when it did not; changed to `result: "skip"` so evidence accurately reflects that the gate skipped rather than passed.
- **`review_result` instruction drift** — `role-cards.md` and `gate-fixer.md` still referenced the old nested `review_result.findings[]` contract after the Step 2 canonical-output migration; updated to top-level `findings:[]` per `agents/verifier.md`.

## [2.34.1] — 2026-06-18

### Fixed
- **`yaml_field()` quoted-empty bypass** — `_generated_by: ""` and `_generated_by: ''` returned a non-empty string (the literal quote characters), allowing fabricated empty fields to pass `[[ -z ]]` guards; fixed by stripping surrounding YAML quotes after whitespace trimming so quoted-empty collapses to empty and fails correctly.
- **Verdict whitelist missing** — only `pending` and empty were rejected from verifier output; any other non-standard scalar (e.g. `banana`) passed as a valid completed verdict; fixed by explicit `case` whitelist that accepts only `pass|fail`.
- **`blocking_findings` fail-closed on non-false values** — only exact scalar `true` was blocked; `maybe`, `"true"` (quoted), comment text, and any other non-empty value passed silently as clean; fixed to accept ONLY scalar `false` (after quote-stripping), treating everything else as blocking.
- **`cp4_curator_validation` registry anchor** — source line was `scripts/aid-fsm.sh:283`, actual function start is `:292`; corrected.
- **Enforcement registry seed header** — seed file still claimed "single source of truth / NOT yet promoted"; updated to "SUPERSEDED by E-046-1_3 Step 5" to match reality after promotion.

## [2.34.0] — 2026-06-18

### Added
- **Enforcement registry promoted to `defaults/`** — `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` is now git-tracked and shipped with the plugin; previously it lived only in a gitignored seed file, making it invisible to consumers and untestable in CI.
- **TTL guard for planned enforcement rows** — `scripts/aid-registry-ttl-guard.sh` exits non-zero when a `status: planned` registry row is past its `deadline` without a valid future `deferred_until` date; enforces the "Detector without Enforcement is Decoration" principle (§1) by making planned-but-never-wired items fail CI instead of silently rotting.
- **`deadline` / `deferred_until` / `deferred_by` / `deferred_reason` schema** — per-row TTL fields added to the registry schema so each planned enforcement can state when it must be wired and who deferred it if not yet done; P045 planned rows carry `deadline: 2026-09-30`.
- **`_generated_at` required in verifier output** — `fsm_check_verifier_output` now rejects files missing or empty on `_generated_at`, closing the anti-fabrication gap where a verifier's timestamp could be omitted without FSM consequence; `agents/verifier.md` output spec and the verifier output template updated to match.
- **`cp4_glob_evaluated` audit event wired** — the event was documented in `skills/agent-protocol.md` but never emitted; now emitted by `fsm_check_cp4_curator_validation` before the production-touch check, resolving the ORPHAN verdict in the enforcement registry.
- **Regression tests: cross-plan gate, `_generated_at`, CP4 content-validation, CP5 blocking_findings** — 19 new bats assertions in `test-aid-fsm.bats` (cross-plan E-→P gate, `_generated_at` enforcement, CP4 content), `test-tiered-severity.bats` (CP5 four-case matrix), and the new `test-registry-ttl.bats` (6 TTL guard assertions).
- **`run-all-tests.sh` discovers `bats/test-*.bats`** — the test runner now auto-discovers bats suites in the `bats/` subdirectory in addition to `test-*.sh`, so `test-registry-ttl.bats` and all other bats suites run in CI without manual registration.

### Changed
- **CP4 curator-validation content-validated** — `fsm_check_cp4_curator_validation` previously accepted any file at the expected path; it now routes through `fsm_check_verifier_output` and rejects files missing valid `_generated_by`, `_generated_at`, or `classification` fields.
- **`blocking_findings` reads canonical top-level field** — `done-advance review → release` now reads the auditor's `blocking_findings:` key via `yaml_field` (line-start match only) instead of `grep -ciE` on prose; fail-closed on absent field, immune to false-positives from negations or body text; `agents/auditor.md` output template updated to emit `blocking_findings:` as the first top-level key.
- **Cross-plan init gate fixed for `E-NNN` IDs** — the gate that blocks starting a new EPIC when the previous plan has unreviewed Curator/Auditor findings was silently dead because the plan-prefix derivation used `grep -oP '^P\d+'` which never matched `E-NNN` style IDs; fixed using `BASH_REMATCH[1]` on `E-([0-9]+)`.
- **Enforcement registry ORPHAN rows resolved** — `dispatch_completed_late` removed (unwireable in scope), `cp4_glob_evaluated` promoted to `status: active`, `cp4_template_stale_name` aligned; verdict distribution: ORPHAN 3 → 0, ALIGNED 71 → 73.

### Fixed
- **`test-tiered-severity.bats` fixture broken by fail-closed** — six existing tests that used a minimal `audit-report.md` without `blocking_findings:` now fail the Step 3 fail-closed precondition; fixture `setup()` updated to write `blocking_findings: false` at line-start so the tests exercise their intended provenance logic without triggering the new guard.
- **TTL guard quoted-date regex** — `aid-registry-ttl-guard.sh` regex for `deadline:` and `deferred_until:` now handles `"YYYY-MM-DD"` (quoted) in addition to unquoted values, matching the flow-style YAML format used by the registry.

## [2.33.1] — 2026-06-15

### Fixed
- **docs-writer step ID** — EPIC steps with the `docs-writer` role failed `plan.json` conversion because the role's hyphen broke the `step.id` pattern `^step_[a-z0-9_]+$`; the role is now sanitized (hyphen → underscore) when building the step ID, while `step.role` keeps its canonical hyphenated value, so docs-writer steps convert and dispatch correctly.

## [2.33.0] — 2026-06-15

### Added
- **dispatch_mode selection in /aid-init** — fresh init now asks which dispatch mode to use (agent_tool / inline / subagent) instead of silently writing a default, and re-runs preserve a manually-chosen mode instead of resetting it to `agent_tool` on every run — the silent-reset that caused P043/P044 provenance false-blocks.

### Fixed
- **done-advance critical-finding precondition** — the release precondition now reads the auditor's structured `blocking_findings` verdict instead of grepping report prose for `critical.*security`; the old grep false-positived on negations ("No Critical … security issue") and even on notes describing the false positive, blocking clean releases and pushing users to edit audit evidence to get through.

## [2.32.0] — 2026-06-15

### Added
- **Real-scale Visual Companion mockups** — when building UI on an existing frontend, the companion records the real dimensions (container/column widths, row heights, font sizes, spacing, breakpoints) from the live code and reproduces them 1:1, so a mockup reflects what actually fits on screen instead of an arbitrarily-scaled sketch.

### Changed
- **Visual Companion canvas always white** — the browser companion frame no longer follows OS dark mode (white page background, `color-scheme: light`, dark-mode media query removed), so mockups are always judged on the same white canvas the target UI uses.

### Fixed
- **pre-commit hook shebang** — the generated FSM-guard pre-commit hook had no shebang, so git ran it under `/bin/sh` (dash on Debian) where its bash syntax (`[[ ]]`, `< <(find …)`) failed and blocked every commit, forcing `--no-verify`; it now starts with `#!/usr/bin/env bash` and `/aid-init` retrofits the shebang onto hooks installed before the fix.

## [2.31.0] — 2026-06-14

### Added
- **Whisper transcription via LiteLLM proxy** — voice transcription routes through the LiteLLM AI gateway instead of calling OpenAI directly, so audio spend and routing flow through one gated proxy (D-082 F2).

### Removed
- **Orphaned docs-deploy workflow** — removed the stale Docusaurus deploy CI workflow; the docs were migrated to the central eco docs site.

## [2.30.0] — 2026-06-14

### Added
- **Simplifier + Reporter at Plan Boundary** — two plan-boundary specialist agents run after a plan's last EPIC: the Simplifier proposes reuse/dedup/clarity refinements over the whole plan diff (S/M auto-applied through the gate-fixer → CP4 revert-on-fail rail, L deferred to the PM summary), and the Reporter tests the delivered functionality and writes a plain-language `.aid-o/reports/{plan_id}-delivery.md` from a fixed 7-section template, condensing the Auditor and Curator verdicts and leaving ≥1 on-disk test artifact as anti-fabrication proof. The new `delivery_report_present` compliance check (advisory, severity-routed) verifies the report's presence and on-disk `_test_evidence` at the plan boundary and rides the existing done-advance gate (`null` before the boundary, so it never false-blocks a non-final EPIC). Both agents are config-toggled and inert until a project re-inits.
- **Contributor guide (docs/extending-aid.md)** — a single reference documenting where each enforcement type lives (the type→instruction-home convention), the checklist to add one, the severity-layer vs hard-die FSM precondition patterns, the agent_tool dispatch-mode reality, and the P045 Simplifier + Reporter worked example.

## [2.29.4] — 2026-06-12

### Fixed
- **Force-Path Recovery Alert** — compliance blocks cleared via PM `--force` override never emitted the ✅ resolution alert because the force branch of done-advance skipped the entire P042 recovery block; recovery emission now lives in a shared helper (`fsm_emit_compliance_recovery`) called from both the clean re-run and the force-override paths, so every 🛑 blocked alert is paired with a ✅ regardless of how the block was cleared.
- **aid-init dispatch_mode Template** — the `/aid-init` plugin-discovery step still wrote `dispatch_mode: subagent` into `config/plugin.yaml` on every run, overriding the P043 `agent_tool` default and reintroducing guaranteed `verifier_provenance` false-positive blocks; the template now writes `agent_tool` and the dispatch-mode docs describe all three modes including the false-positive failure class.

## [2.29.3] — 2026-06-12

### Added
- **Check-severity sync guard** — new `test-check-severity-sync.sh` suite fails when a compliance check emitted by the FSM has no entry in `defaults/check-severity.yaml`, closing the trap where an unregistered check silently defaults to advisory and can never block
- **Compliance recovery alert documentation** — pipeline.md §7 now documents the P042 block/recovery Telegram alert pair, the `fsm_done_advance_recovered` dedup marker, and the `alert_on_compliance_recovery` config gate

### Changed
- **Accurate provenance aggregate in agent_tool mode** — compliance.json now reports `provenance_aggregate: "agent_tool"` instead of the misleading `"mixed"` when verifier dispatch runs via the CC Agent tool (non-blocking behavior unchanged)
- **dispatch_mode default single-sourced** — `defaults/orchestration.yaml` `dispatch.mode` is now the single source of the default (`agent_tool`, with all three modes documented); aid-fsm.sh resolves project `plugin.yaml` → plugin `orchestration.yaml` → hard fallback, removing the stale `subagent` doc/code drift
- **FSM internals simplification** — pure-bash `yaml_field()` reader replaces 51 copy-pasted `grep|awk` field reads (~100 fewer process forks per FSM run); repeated-fail counters, CP3 verifier-output evaluation, and the increment-step precondition fail ritual each consolidated into single helpers; shared `die()` moved to `lib/aid-stage-log.sh`; step-verify content checks read the file once; behavior unchanged (all 18 suites + 115 bats tests pass)

## [2.29.2] — 2026-06-10

### Changed
- **Visual Companion — current state mandatory in mockups** — when proposing UI changes to an existing component/page, the companion must always render the current look alongside the proposed changes (side-by-side or inline delta); showing only the new design in isolation is now explicitly prohibited; applies both in the "Read the Code First" refactoring flow and as a general design tip

## [2.29.1] — 2026-06-09

### Fixed
- **verifier_provenance false-positive blocking** — `dispatch_mode` defaulted to `subagent`, which requires `verifier_dispatch_start/complete` timeline events that the CC Agent tool never writes; every EPIC in standard AID self-hosted operation was therefore permanently blocked on `verifier_provenance`; the default is now `agent_tool` (set `dispatch_mode: subagent` in `.aid-o/config/plugin.yaml` to opt into strict interval-bracket provenance enforcement); a new `verify_provenance` branch returns a non-blocking `"agent_tool"` signal so `provenance_aggregate` never escalates to `"unverifiable"` in this mode

## [2.29.0] — 2026-06-07

### Added
- **Compliance recovery alert** — when a `done-advance review→release` succeeds with zero blocking failures for an EPIC that previously emitted a `🛑 release blocked` alert, AID now emits a `✅ compliance cleared, release unblocked` Telegram alert and writes an `fsm_done_advance_recovered` timeline event (dedup marker, observable test signal); controlled by `alert_on_compliance_recovery` config gate (default on)

## [2.28.3] — 2026-06-06

### Fixed
- **Self-referential dependencies** — a step whose dependency range covered its own number (e.g. "Steps 4-6" on step 6) produced a meaningless self-edge that downstream cycle detection rejected; self-references are now dropped during dependency remapping
- **Task-keyword dependencies** — `Depends on: Task N` / `Tasks M-N` lines were silently ignored because the parser only recognized "Step", even though `## Task N:` step headers are accepted; the dependency parser now treats the Task keyword the same as Step
- **Clean-tree guard vs. runtime queue** — the FSM init clean-tree guard aborted on any tracked change including AID's own `.aid-o/config/queue.yaml`, which the auto-pipeline mutates between phases, breaking multi-phase auto runs in projects where that file is tracked; the guard now excludes the runtime queue file
- **/aid-init .gitignore backfill** — `.gitignore` setup skipped the entire AID block when any `.aid-o/` entry already existed, so projects initialized before a later ignore entry (e.g. the runtime queue file) never received it; setup now appends individual missing lines on upgrade

## [2.28.2] — 2026-06-06

### Fixed
- **EPIC dependency renumbering** — when slicing a multi-EPIC plan into per-EPIC files, the Steps table renumbered each EPIC's steps locally (1..N) but the Depends On column kept the plan's global step numbers, producing dangling references like "step 2 depends on 4" in a 3-step EPIC that crashed dependency validation in `aid-epic-to-json.sh`; intra-EPIC dependencies (and the Goal step list) are now remapped to EPIC-local numbering

## [2.28.1] — 2026-06-04

### Fixed
- **FSM force-transition crash** — `aid-fsm.sh transition --force` aborted under `set -u` with "project_root: unbound variable" because `fsm_emit_audit_log` read the variable before its guarded fallback, breaking the manual-override escape hatch
- **CI bash test coverage** — the FSM, release, and integration test suites were silently skipped in CI (no `bats` installed) and had drifted stale against new preconditions; CI now installs `bats`, the four affected suites are repaired, and the FSM precondition layer gained real red/green coverage so it cannot be weakened unnoticed

## [2.28.0] — 2026-06-04

### Added
- **Skill & command authoring standards** — `skill-writing.md` and `command-writing.md` promoted to live skills, with `aid-lint-skill.sh` + `test-skill-lint.sh` enforcing the mechanical subset (pre-existing files grandfathered until revised)
- **Frontend Visual Anchoring enforcement** — `increment-step` hard-fails a frontend step that has `visual_refs` but whose output lacks a `## Visual Anchoring` section

### Changed
- **Model single source of truth** — model tier lives only in `role-cards.md`; removed the conflicting `orchestration.yaml` models block and the phantom `role_assignments` reference
- **role-cards.md holistic unification** — `e2e` is now a real step role with one rich card; `docs` renamed to `docs-writer` everywhere; `qa` gets a full card; structure and footer unified
- **Curator is propose-only** — curator recommends a disposition, the orchestrator applies fixes at every effort (S/M/L), and CP4 reviews the applied changes (reordered to run after the apply)
- **auditor.md overhaul** — scorable A–J categories, corrected scoring math, pre-merge timing
- **planner.md rewrite** — documents the real two-script pipeline (no fictional intelligent planner)
- **Config-policy single-sourcing** — escalation triggers and `skill_conflicts` deduplicated to one authoritative source; pre-filter regexes single-sourced to `pre-filter-rules.yaml`; `not_acceptable` patterns routed to real enforcement or explicitly marked advisory

### Fixed
- **Verifier provenance false-positives** — interval-bracket window replaces the ±60s test that flagged honest runs; fails closed when the severity registry can't be read; renamed the verdict to the honest `unverifiable` and added an explicit anti-fabrication instruction to the orchestrator
- **aid-run.md fiction + task→epic terminology** — removed non-existent state transitions / branch / merge-target claims
- **role_overrides downgraded to advisory** — the global `Bash(*)` permission made per-role scoping non-enforcing; the false security claim was removed
- **deserialize_dangerous pre-filter rule** — a `(?!_safe)` lookahead (unsupported by bash ERE) made the rule silently never match; rewritten ERE-safe
- **Honest phase-end note** — `run-management.md` no longer claims the controller auto-enforces the PM-GO boundary

### Removed
- **Unread config** — `orchestration.yaml` `models:` block and `release.skip_when`, and the `execution.yaml` global `retry:` block — read by nothing (per-gate `max_retries` is the only retry knob)

## [2.27.0] — 2026-06-02

### Changed
- **FSM state file unified to `fsm-state.yaml`** — retired the parallel `state.yaml` step-array that `aid-epic-to-json.sh` wrote but nothing read; every script, doc, template, and test now refers to the single FSM state file `fsm-state.yaml`, with the legacy `state.yaml` name kept only as a read fallback for in-flight pre-migration runs.

### Fixed
- **`/aid-stop` + `/aid-run --resume` state handling** — `/aid-stop` dropped the invented `session.*` schema, now reads the real `fsm-state.yaml` fields and logs the stop event through the canonical timeline helper; `--resume` reads `fsm-state.yaml`.

### Removed
- **Queue `pause` / `resume` / `reorder` subcommands** — removed from `/aid-status` and help; documented but never backed by any script (archived, restorable).

## [2.26.0] — 2026-06-01

### Changed
- **Documentation hygiene** — stripped version-stamped headings (e.g. `(NEW v2.16.0 — P032)`) from pipeline.md, agent-protocol.md, and related skills/commands; refreshed stale `Last Updated` dates; reconciled the brainstorming severity-enum claim and the aid-status `{epic_id}` naming drift.

### Fixed
- **aid-help level detection** — counted `state: DONE` in `state.yaml` (never written by the FSM), so every user showed Level 0; now reads `fsm-state.yaml`.
- **aid-init pre-push hook docs** — clarified pre-push uses its own marker `AID-ORCHESTRATOR-PREPUSH-START` (not the pre-commit marker), preventing duplicate hook blocks on re-run.
- **CP4 curator-validation filename** — verifier-output-template + verifier.md now name the FSM-required `verifier-output-cp4-curator-validation.md`; corrected the false "FSM does NOT enforce" note.
- **implementer model selection** — replaced the duplicated, incomplete model-tier list with a pointer to role-cards.md (single source of truth covering all roles).
- **brainstorming prior-work scan** — globbed nonexistent `.aid-o/epics/`; now `.aid-o/tasks/`.

### Removed
- **aid-research command + knowledge/Context7 layer** — removed the never-wired on-demand research command, its knowledge-base template, the integrations `knowledge:` config, the `context_scope.knowledge` plan-schema flag, and all orphaned Context7 references; archived to `docs/plans/AID-audit-2026-06/removed/` (restorable). The layer had no producer wired and no consumer.

## [2.25.0] — 2026-05-31

### Added
- **aid-emit-dispatch.sh wrapper** — new bash CLI with `start` and `complete` subcommands the orchestrator MUST call before/after every `Agent({subagent_type, prompt})` dispatch; writes `verifier_dispatch_start`/`_complete` events to timeline.jsonl plus tracks state in pending-dispatches.jsonl per evidence dir.
- **fsm_check_orphan_dispatches function** — reconciliation backstop in cmd_increment_step that refuses step transitions when pending-dispatches.jsonl shows a start event older than expected_duration_max without matching complete.
- **fsm_check_cp4_curator_validation function** — precondition in cmd_done_advance review→release that requires verifier-output-cp4-curator-validation.md when curator-report.md exists and any commit in `base_commit..HEAD` range touches production code paths. Mode-aware: skips with `cp4_skipped_streamlined_advisory` audit event when streamlined_mode is true.
- **fsm_check_streamlined_integration_review function** — precondition in cmd_done_advance review→release that, when streamlined_mode is true, requires all three of `verifier-output-cp3-code-review.md`, `verifier-output-cp3-security.md`, `gates_report.json` present in the evidence dir.
- **fsm_check_streamlined_abandoned function** — abandoned-but-shipped detector in cmd_done_advance that fires when streamlined_mode is true and timeline.jsonl has fewer than 3 events.
- **--streamlined CLI flag in cmd_init** — first-class lightweight execution mode that writes `streamlined_mode: true` into fsm-state.yaml and propagates through cmd_increment_step / cmd_done_advance / write_compliance_json.
- **coverage_mode + skipped_dimensions fields in compliance.json** — honest accounting of which dimensions were intentionally skipped per the streamlined contract. Field name `coverage_mode` (not `mode`) avoids collision with the existing fsm-state.yaml `mode` (manual/auto execution mode).
- **Four blocking checks in defaults/check-severity.yaml** — `dispatch_orphan_complete`, `cp4_curator_validation`, `streamlined_abandoned`, `streamlined_integration_review`, all severity blocking per AID-v3-principles.md §1 with explicit PM promotion (NR 8-14 empirical evidence across 4 projects).
- **cp4_production_paths field in defaults/execution.yaml** — configurable glob alternation for CP4 trigger detection; `/aid-init` stack-scan in `scripts/lib/aid-init-execution-yaml.sh` auto-populates project-specific defaults.
- **aid-json-to-run.sh Step 18 auto-init** — calls `aid-fsm.sh init` after run.md generation when fsm-state.yaml is absent, eliminating state.yaml vs fsm-state.yaml confusion (NR 10/12/14 anchor). Accepts a `--streamlined` passthrough (threaded from `/aid-run --streamlined` and `aid-auto-pipeline.sh`) that forwards to `cmd_init` so the auto-initialized state carries `streamlined_mode: true` — without it the streamlined activation switch would be unreachable.
- **test-aid-emit-dispatch.bats** — eleven fixtures: the original eight (start-only, start+complete pair, orphan complete, ceiling clamp, concurrent flock, missing output_file, malformed agent_id, inode-swap race) plus three CP3-security fixtures (`--focus` injection rejected by allowlist, jq-escaped pending construction, per-start nonce prevents ledger double-clear).

### Changed
- **cmd_increment_step preconditions** — added Component B orphan-dispatch backstop after the existing memory_used/memory_written/verifier_output checks; conditionally skips the per-step verifier_output check when streamlined_mode is true.
- **cmd_done_advance review→release preconditions** — added Component D streamlined_integration_review check, streamlined_abandoned check, and Component C CP4 enforcement (mode-aware in streamlined); all wired before the existing curator-report check; cites AID-v3-principles.md §1.
- **write_compliance_json schema** — emits top-level coverage_mode and skipped_dimensions fields; backward-compatible (legacy compliance.json without these reads as coverage_mode "full", skipped_dimensions []). The `mode` → `coverage_mode` rename is a breaking change for any downstream consumer that read the v0 draft.
- **fsm-state.yaml unified schema** — absorbs the legacy state.yaml steps[] array; backward-compat dual-file reader preserved.
- **skills/pipeline.md** — new §4 Dispatch Protocol subsection documenting the mandatory aid-emit-dispatch.sh wrapper chain; PRE-FLIGHT auto-init note.
- **skills/agent-protocol.md** — reference tables for the new audit events and check-severity entries.
- **commands/aid-run.md, commands/aid-plan.md, commands/aid-do.md** — --streamlined flag documentation and advisory trigger criteria.

## [2.24.0] — 2026-05-31

### Added
- **FSM Artifact Templates (`step-verify-template.md` + `verifier-output-template.md`)** — two new templates in `defaults/templates/` document the exact section/field schema enforced by `aid-fsm.sh` preconditions. `step-verify-template.md` lists the six required sections (Acceptance Criteria with `- [x]` checkboxes, Commit with 7+ hex SHA, Memory Used, Memory Written, Files, Result: PASS) each annotated with the failing `cmd_increment_step` reason. `verifier-output-template.md` is a single file covering all four CP variants (CP2 per-step, CP3 code-review, CP3 security, CP4 curator) with line-start `_generated_by:` / `classification:` / `verdict:` fields tied to `fsm_check_verifier_output`. Empirically motivated: WAN P027 EPIC 1 had 11 FSM precondition failures (5 from undocumented step-verify schema, 3 from undocumented `_generated_by` schema) while EPIC 2 had 0 — proving the schema is learnable, so it should be documented up-front rather than discovered through failure (NR 10 §4D, NR 12 §4A, NR 14 RC1).

### Fixed
- **`aid-plan-to-epic.sh` step counter fenced-block bug** — parser regex `^###?[[:space:]]+(Step|Task)[[:space:]]+([0-9]+)` previously matched `### Step N:` headers inside fenced code blocks, so any plan *about AID itself* that quoted AID step syntax got mis-counted and the pipeline crashed with `objective too short` errors. Fix tracks fence depth (toggle on lines matching `^[[:space:]]*````) across four scan sites: `has_impl_steps` awk quick-check, main step-numbering while-loop, `extract_step_content()` awk helper, and the objective-fallback awk. `aid-epic-to-json.sh` confirmed unaffected (parses EPIC table rows, not plan.md headers). New `test-aid-plan-to-epic-fence.bats` fixture reliably fails pre-fix and passes post-fix. Empirical anchor: AID-self P039 (v2.23.0 brainstorming plan) tripped this bug — NR 14 §4D.
- **`defaults/policies/permissions.yaml` stale MCP refs (action required: re-run `/aid-setup permissions`)** — the autonomous preset whitelist referenced MCP servers that no longer exist in current eco infrastructure: `qdrant-memory__*`, `shared-docker__*`, `shared-minio__*`, `shared-postgres__*`, `shared-playwright__*`, `shared-telegram__*`. Replaced with the actual running set: `vulcan-memory__{find,store,list}` (excluding destructive `vulcan-delete`), `eco-admin__*` 12 GREEN read-only tools (YELLOW writes intentionally excluded — require Telegram approval per ADR-17 D-077), `claude_ai_Google_Drive__*` 6 read-only ops. Kept `shared-github`, `shared-sequential-thinking`, `svc-mcp-tg-bot__send_message`, `plugin_context7_context7`, and `qdrant-brain` (back-compat with `skills/memory-mcp.md` contract). Playwright explicitly NOT auto-allowed — opt-in via per-project `settings.local.json`. Empirical anchor: NR 11 manual audit. **Existing projects that already ran `/aid-setup` retain stale entries in their local `.claude/settings.local.json` and should re-run `/aid-setup permissions` to refresh.**

## [2.23.0] — 2026-05-31

### Added
- **Section-Review Validate-Then-Verify** — brainstorming Step 6 sections now run a Sonnet `section-review` critic followed by an Opus ground-truth re-grep, presenting the PM a claim-verification table (validator claim → real command + output → ✓/✗) before approval; Step 7 adds a `cross-section-review` consistency check over the assembled plan.

### Fixed
- **Verifier focus card naming** — the `security-review` card in `role-cards.md` is renamed to `security` to match the canonical focus name used plugin-wide (orchestration tier, CP3 dispatch, planner, aid-run, epic templates); resolves a latent card-name mismatch with the registry.

## [2.22.3] — 2026-05-14

### Fixed
- **`skills/brainstorming.md` references to renamed visual-companion path** — v2.22.1 moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` but left two stale `skills/visual-companion.md` references in `brainstorming.md` (lines 107 and 258). The `test-instruction-consistency` bash suite caught it (`✗ Referenced file MISSING`) and CI went red since v2.22.1's push. Both references updated to the directory form.

## [2.22.2] — 2026-05-14

### Changed
- **Visual Companion — explicit remote-host networking + read-first-before-redesign rule** — Standalone Invocation Step 3 now mandates picking server bind mode (`127.0.0.1` for local agent / `0.0.0.0 --url-host <IP>` for remote SSH-VPN setup) BEFORE starting the server, with detection cues (`$SSH_CONNECTION` env, `hostname -I`) and a direct ask-PM fallback. Previously the remote case was a buried footnote, leaving the agent to start a loopback-only server that PM's browser couldn't reach. Plus new "Refactoring or Redesigning Existing UI — Read the Code First" section: when PM references an existing component / screenshot / page name, agent MUST ask "should I read the current implementation first?" and produce a structured data-inventory in chat before any mockup. Saves the iteration cycles where mockups get drawn against guessed data shapes and need full rewrite after the real component is read.

## [2.22.1] — 2026-05-13

### Fixed
- **Visual Companion skill discovery (hotfix v2.22.0)** — moved `skills/visual-companion.md` → `skills/visual-companion/SKILL.md` directory structure. Claude Code's plugin loader only recognizes skills as user-invokable (slash-callable) when they live in `skills/<name>/SKILL.md` form; flat files are loaded for in-plugin reference but never registered as `/<name>` slash commands regardless of any `user_invocable` frontmatter flag. v2.22.0 release flipped the flag and added the standalone section but kept the flat-file shape, so `/visual-companion` did not appear in the command palette. This release fixes the structure only — no content changes.

## [2.22.0] — 2026-05-13

### Changed
- **Visual Companion skill is now user-invocable** — `/visual-companion` slash command opens a standalone demo session for verifying the browser round-trip (server start, HTML push, click capture, events read) without going through the full `/aid-plan brainstorm` flow. Skill frontmatter flipped `user_invocable: false → true` and a new "Standalone Invocation" section was added with explicit start/stop steps, npm-install first-run handling, and node_modules fallback path. Skill remains backward-compatible with the existing brainstorming integration — per-question gate behavior inside `/aid-plan brainstorm` is unchanged.

## [2.21.1] — 2026-05-13

### Fixed
- **`try_telegram_alert` test-mode guard** — `AID_TEST_MODE=1` env var short-circuits the helper before any `jq` or `curl` invocation, so bats fixtures and smoke tests no longer fire real-world Telegram alerts. Discovered post-P038 ship: cmd_done_advance blocking precondition (Step 3) and 3 other call sites previously emitted ~30 alerts during fixture development with `E-TEST-038: 1 blocking compliance failure(s)`. Shared bats `setup_test_evidence_dir` (test-helpers.bash) and `test-tiered-severity.bats` `setup()` now export the guard. Convention: any future side-effect helper (mail/Slack/webhook) should mirror this pattern.

## [2.21.0] — 2026-05-13

### Added
- **Tiered severity registry** — `.aid-o/config/check-severity.yaml` declares each compliance check as `blocking` or `advisory`; shipped by `/aid-init` with initial bootstrap per AID-v3-principles.md §1
- **`failures[]` array in compliance.json** — every release writes per-check failure entries with severity, evidence, and promoted_at, enabling deterministic blocking decisions
- **`aid-fsm.sh promote-check`** — explicit advisory→blocking promotion with mandatory ≥20-char reason and forensic audit-log entry
- **`aid-fsm.sh check-promotion-candidates`** — read-only scan of audit-log.jsonl identifying advisory checks that meet the AID-v3-principles.md §1 promotion criterion (force_override_rate < 0.05 across N≥5 EPICs)
- **`aid-promote-checks.sh`** — PM-facing markdown report wrapping the candidate scan
- **`test-tiered-severity.bats`** — 6 fixtures covering blocking-blocks, advisory-passes, --force-with-audit, short-reason-rejection, promote-check, and candidate identification

### Changed
- **`cmd_done_advance review→release`** — now refuses transition when any compliance failure has `severity: blocking`; structured error message includes per-failure evidence and copy-paste `--force --reason --blocked-checks` override snippet; per AID-v3-principles.md §1 "Detector without Enforcement is Decoration", this is the first concrete application of the principle and closes the P026 (WAN, 2026-05-13) failure mode
- **`fsm_handle_force_override`** — accepts new `--blocked-checks "<comma-list>"` flag; propagates to both timeline.jsonl and audit-log.jsonl
- **`aid-audit-log.sh cmd_append`** — new `--<key>-array "a,b,c"` flag-suffix convention emits JSON arrays in output entries; dash-to-underscore JSON key normalization for compatibility
- **`pipeline.md §7 DONE State`** — new "Tiered Severity Enforcement" sub-section documenting the override flow, the severity table, and the promotion ceremony
- **`write_compliance_json`** — populates `failures[]` array using check-severity.yaml registry; backward compatible (empty array when no failures)

## [2.20.2] — 2026-05-12

### Added
- **Plan-AC Diff Gate (P037 Phase 2, AID-010)** — new deterministic gate `plan_diff` in `execution.yaml` runs `aid-plan-diff.sh` after EXECUTE→GATES. Script parses plan-level `## Acceptance Criteria` section, executes each `verification_pattern` (3 types: `cmd`, `must_not_exist`, `must_contain` with any-match regex semantics) against codebase HEAD, emits `plan-diff.json` with per-AC verdict. Fail if ≥1 AC absent.
- **`aid-plan-diff.sh` Standalone Script** — new 281-line bash script under `plugins/aid-orchestrator/scripts/`. Standalone testable lifecycle (own provenance fields `_generated_by: aid-plan-diff.sh@v2.20.2`, own timeline events `plan_diff_start`/`plan_diff_complete`). 4 exit codes: 0 (all present), 1 (≥1 absent), 2 (graceful skip — Fast Mode or no AC section), 10 (input validation).
- **Plan Template AC Block** — `defaults/templates/plan.md` extended with `## Acceptance Criteria` section template using executable `verification_pattern` blocks (3 example patterns: cmd, must_not_exist, must_contain). New plans (P038+) gain plan-level AC verification by default.
- **Completeness Gate Sub-Check #20** — `plan-writing.md` Completeness Gate added 3 sub-rules (20a/20b/20c) enforcing `verification_pattern` block on every AC for new plans; legacy plans (P001-P036) without AC section skip the check (no violation). EVALUATION counter updated `out of 24` → `out of 27`.
- **`compliance.json plan_ac_match` Dimension** — `evaluate_compliance_checks` reads `plan-diff.json`, sets `checks.plan_ac_match: true | false | null`. False forces `compliance.overall: "fail"`; null = graceful skip for legacy plans or missing plan-diff.json.
- **`{plan_path}` Placeholder Token** — `aid-run-gates.sh` `resolve_placeholders()` helper substitutes 4 known tokens (`{plan_path}`, `{epic_id}`, `{run_id}`, `{base_commit}`) in gate commands via bash parameter expansion. `cmd_init` writes `plan_path:` field to state.yaml (realpath-normalized absolute path or literal `null` for Fast Mode EPICs). Unknown `{<token>}` triggers fail-loud exit — silent pass-through is a debug trap.
- **Plan-AC Diff Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-plan-ac-diff.bats` (8 tests covering all 3 pattern types, fail path, Fast Mode null + empty, legacy skip, resolve_placeholders + cmd_init replicas). Full bats suite now 52/52 ok.

### Changed
- **`aid-run-gates.sh` Gate Command Resolution** — gate commands now pass through `resolve_placeholders()` before `bash -c` execution. Exit code 2 counts as pass when gate's `pass_criteria` mentions "exit 2" (graceful-skip pattern).
- **`defaults/execution.yaml`** — legacy `{base}..HEAD` tokens in `docs_updated` gate renamed to `{base_commit}..HEAD` (aligning with `scope_check` convention; required for resolve_placeholders fail-loud safety). New `plan_diff:` gate entry appended after `scope_check:` (required: true, max_retries: 0, pass_criteria documents exit 0 or exit 2).

### Fixed
- **Goalpost Shift Detection** — Five EPICs (P019 F1+F2 frontend migration, P021 F4 backlog collision, P022 F6 Playwright→backend substitution, P023 F7 five concurrent shifts) previously passed to DONE without detection because gates didn't check plan AC reality vs implementation. Phase 2 `plan_diff` gate catches this class — every new plan with `verification_pattern` blocks gets per-AC executable verification on codebase HEAD before GATES→DONE.
- **`cp2_per_step_provenance` Type Mismatch (IMP-100)** — backfill in `aid-compliance-backfill.sh` previously wrote scalar string `"unknown"` for `cp2_per_step_provenance`, while the live writer in `aid-fsm.sh evaluate_compliance_checks` emits a JSON array (one entry per CP2 step). Type drift created silent correctness risk for queries doing `| length`. Backfill now writes `["unknown"]` (single-element array) to match live writer shape. Other 3 fields (cp3_*, provenance_aggregate) remain scalar — consistent with live writer.
- **`backfill_provenance` Silent Error Conflation (IMP-102)** — previously returned exit 1 for both "already-present skip" (normal) and "jq failure" (corrupted compliance.json). Step C caller incremented skip-count for both, masking real errors. Function now returns 0 (fixed), 1 (jq failure with stderr WARN), 2 (idempotent skip); caller case-statements on exit code and reports backfilled/skipped/errors separately in summary heredoc.
- **`verify_provenance` Unused `step_n` Parameter (IMP-103)** — `$3` was received in signature but never referenced in body. Renamed to `_step_n` with code comment explaining intentional retention for future per-step forensic attribution. Positional API stable (no call-site changes needed).
- **CLI Dispatcher Help Message Clarity (IMP-104)** — `aid-stage-log.sh` dispatcher previously listed `log_event`, `log_info`, `log_warn`, `log_error` uniformly in help text, leading users to expect timeline writes from all four. Comment + help message now distinguish: only `log_event` writes to timeline; `log_info`/`log_warn`/`log_error` are stderr-only severity-prefixed echoes.
- **`aid-fsm.sh` Missing `BASH_SOURCE` Guard** — top-level case dispatcher previously exited 1 on unknown args even when the file was sourced (e.g. from bats test fixtures), killing the test process. Dispatcher now wrapped in `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi` (same pattern as `aid-stage-log.sh` fix from v2.20.1). Sourcing for testing purposes works cleanly. Existing `_load_aid_fsm` shim in `test-anti-fabrication.bats` becomes redundant but harmless.

## [2.20.1] — 2026-05-12

### Added
- **Verifier Provenance Verification (P037 Phase 1, AID-038)** — `aid-fsm.sh evaluate_compliance_checks` cross-references each `verifier-output-*.md` `_generated_by` field against `timeline.jsonl` `verifier_dispatch_start`/`_complete` events within a ±60s window for subagent mode, or validates `main-context@<commit-sha>` format with SHA verification for inline mode. Detected fabrication forces `compliance.overall: "fail"`.
- **Timeline Dispatch Events** — `pipeline.md` now instructs LLM to emit `verifier_dispatch_start` and `verifier_dispatch_complete` events with payload `{agentId, focus, step_n, evidence_dir, ts}` around every CP1/CP2/CP3 verifier `Agent()` call.
- **Honest Mode for No-Subagent Projects** — `.aid-o/config/plugin.yaml` new field `dispatch_mode: subagent | inline` (default subagent). Inline mode requires `_generated_by: main-context@<git-HEAD-sha>` format for verifier outputs; compliance check validates format + SHA existence rather than timeline match.
- **CLI Dispatcher for aid-stage-log.sh** — library now supports `bash aid-stage-log.sh <fn> <args>` invocation in addition to existing source-mode usage. Guard via `BASH_SOURCE[0] == ${0}` keeps source-mode behavior unchanged. Required so `pipeline.md` and `aid-plan.md` LLM-rendered docs can invoke `log_event` directly without a separate source step. Unknown function exits 1 with stderr help message listing available functions.
- **Anti-Fabrication Smoke Test** — new `plugins/aid-orchestrator/scripts/tests/bats/test-anti-fabrication.bats` (4 tests): verified subagent dispatch produces `provenance_aggregate: all_verified`; missing timeline events produce `fabricated` + `overall: fail`; inline mode with valid SHA produces `all_inline` + `pass`; CLI dispatcher regression test.

### Changed
- **`evaluate_compliance_checks` Schema** — `verifier_outputs` object now carries three new `*_provenance` fields (`cp2_per_step_provenance`, `cp3_code_review_provenance`, `cp3_security_provenance`) plus aggregate `provenance_aggregate: "all_verified" | "all_inline" | "mixed" | "fabricated" | "unknown"`. Pre-Phase-1 compliance.json files backfilled via `aid-compliance-backfill.sh` Step C (idempotent merge, adds `provenance: unknown` audit note attributing the migration to P037).

### Fixed
- **Compliance Telemetry Honesty** — post-Session-B telemetry (n=8 EPICs reporting 100% pass on all 4 dimensions) was previously vulnerable to fabricated `_generated_by` metadata. P023 reflection (NR 5, 2026-05-11) documented one such case in WAN project where agent wrote verifier outputs in main context but signed them as `aid-orchestrator:verifier@cp{2,3}-*`. Phase 1 enforcement detects this class of cheating.
- **`verify_provenance` TZ Bug** — jq <1.7 silently honors local TZ in `fromdateiso8601` even with `Z` suffix, producing a 1-hour offset on non-UTC hosts (CEST/PST/etc) and reading every dispatch as fabricated. Both `jq -s` invocations in `verify_provenance()` are now prefixed `TZ=UTC` so date parsing matches the `date -d`-derived `$min`/`$max` UTC epochs. Surfaced by Step 5 bats smoke test on CEST host.

## [2.20.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Check 17e (CLI Invocation Grounding)** — `plan-writing.md` Completeness Gate extended with 7th grounding category: for every cited `bash <script> <args>` in Implementation Detail blocks or step examples, verify the args against the actual script interface via `<script> --help` (preferred) or `head -100 <script>` (fallback). Mismatched signatures → REVISE_REQUIRED with suggested correction. Empirical: P035 C1 (2026-05-10) — plan cited a `--state-file` flag that did not exist in `aid-run-gates.sh` at write time; CP1 caught it on the 2nd pass.
- **Completeness Gate Check #19 (Design Defeat Detection)** — semantic LLM check active for plans with `type: bug-fix` in frontmatter. Reviewer answers Q1 (which precondition is being fixed?), Q2 (does the new code-path go through that same precondition?), Q3 (if not, is the bypass explicit + justified?). Q2:no + Q3:no → REVISE_REQUIRED. Pre-screening heuristic (mechanical) auto-activates #19 when goal/context contains fix/fail/bypass/precondition/validation AND the plan mutates `fsm-state.yaml` or `state.yaml` directly without a `cmd_<wrapper>` invocation. Heuristic explicitly EXCLUDES release/version mutations (CHANGELOG, README, marketplace.json, plugin.json, files in `release-policy.yaml` `version_files[]`) to prevent false positives on release plans. Empirical: P035 C2 — `yq -i '.state = "GATES"'` bypassed `cmd_transition()` and would have silently defeated the fix's own purpose.
- **Plan Type Taxonomy (`type:` frontmatter field)** — `defaults/templates/plan.md` now defines an enum `type: regular | bug-fix | refactor | docs` controlling which Completeness Gate checks activate per plan type. Default if missing: `regular`. Legacy `type: plan` (P001-P035 convention) treated as alias for `regular` — no migration required. Documented in new `## Plan Type` template section with a 4-row activation table.
- **`/aid-plan write` Mode Step 9 (CP1 Plan Quality Review)** — write mode extended from 8 to 9 steps; Step 9 mirrors brainstorm Step 9 (verifier dispatch with `docs-review` focus, codebase grounding pass, save review to `.aid-o/work/cp1-review-{plan_id}.md`). Activates #19 when `type: bug-fix` or pre-screening matches. Skip via `review_checkpoints.cp1_plan_review: false`. Closes the gap where plans written through `/aid-plan write` previously had no post-write quality review.
- **CP1 Verifier EVIDENCE REQUIREMENT** — Step 9 verifier prompt now requires concrete evidence (`command_run` + `output_excerpt`) before marking ANY item VERIFIED. Missing evidence → REJECTED with auto-retry; max 2 retries then ESCALATION. Applies to all #17 sub-checks + 17a-d + 17e + #19 (Q1/Q2/Q3 must cite plan path:line + codebase path:line). Empirical: P035 C3 — three bats helpers cited as "existing" from memory; none existed.
- **`test-plan-quality-enforcement.sh` Smoke Test** — bash smoke test exercising all 4 enforcement layers against a deliberately-defective fixture plan: layer 1 (extract `bash <script> --flag` + verify against real interface, with SKIP for already-shifted baseline), layer 2 (3-conjunctive heuristic positive + release-mutation negative control), layer 3 (count `^9.` in Mode: Write Plan section), layer 4 (header + field-name hits for EVIDENCE REQUIREMENT). Auto-discovered by `run-all-tests.sh`.

## [2.19.1] — 2026-05-10

### Fixed
- **`aid-release.sh` CHANGELOG-rename anomaly (IMP-093)** — observed 3× across v2.18.3 + v2.19.0 releases: when a `## [X.Y.Z]` header was pre-written for the upcoming release (PM/agent edited CHANGELOG before invoking script), the previous logic did a blind `sed`-replace on the newest header and silently collapsed the pre-written entry's history. Fix: detect actually-released version from `plugin.json`/`marketplace.json`/`package.json` (not CHANGELOG header) and route through new `update_changelog` helper that has 3 branches: (a) header matches new_version → skip rename (entry already correct), (b) header matches released version → bump existing header (existing behavior), (c) header is some other version → prepend new entry above (preserves history). 3 new bats assertions in `test-aid-release.bats` cover all 3 branches.

### Notes
- **README regex pattern mismatch** — second part of IMP-093 diagnosis showed that `.aid-o/config/project.yaml` regex patterns like `"Plugin: {VERSION}"` don't match actual content `**Plugin:** 2.X.Y` (markdown bold prefix missing in pattern). Consumer projects must update their `.aid-o/config/project.yaml` regex patterns to escape `**` for sed: e.g., `"\\*\\*Plugin:\\*\\* {VERSION}"`. This repo's `.aid-o/config/project.yaml` (gitignored) was updated locally; downstream projects need to edit theirs once if affected.

## [2.19.0] — 2026-05-10

### Added
- **Completeness Gate Sub-Checks 17a–17d** — `plan-writing.md` Completeness Gate extended with 4 new grounding categories aimed at empirical gaps from P019/P021/P032: (17a) backlog ID grounding via whole-plan `\bT-[0-9]+\b` regex + `git log --since="24 hours ago" --grep` — empirical: P021 T-132/T-133 reserved by commit 1907e77 same morning; (17b) test directory convention via POSIX `find tests/ -type f -name "*<basename>*"` — empirical: P021 plan said `tests/integration/`, reality `tests/unit/`; (17c) DB-field semantics via `[A-Z][a-zA-Z]+\.[a-z_]+` regex + `grep` on models.py for stored Column vs `@property`/computed — empirical: P021 assumed automatic, reality stored Column; (17d) file removal grounding via `ls <path>` existence check — empirical: P019 `must_not_exist` file actually existed at EPIC end. EVALUATION counter bumped 18 → 22.
- **`commands/aid-plan.md` Step 9 Verifier Prompt Extension** — verifier dispatch prompt extended with extraction patterns and verification commands for the 4 new grounding categories. Each category gets explicit VERIFIED/ABSENT semantics and REVISE_REQUIRED conditions. Backlog ID ABSENT accepts "T-NNN to be allocated at plan-write time" as a plan-allocation candidate.
- **`defaults/templates/plan.md` Resources Verification Block** — new section between Constraints and Risks with 12 checkbox items: 6 (Existing Resources from #17) + 4 (Plan Assumptions from #17a-d) + 2 (Resolution gates). Auto-populated by `/aid-plan` Step 9 verifier dispatch; PM-visible manual review checklist. Detection scope clarified as whole-plan body scan — no `related_backlog` or similar field required.
- **`test-cp1-grounding.sh` Smoke Test** — bash smoke test that constructs a deliberately-broken plan with violations across all 4 sub-checks and verifies extraction patterns produce correct outputs. POSIX-only (`command -v find` guard, no `fd` dependency), trap-cleaned tmpdir, 5 PASS branches.

## [2.18.3] — 2026-05-10

### Added
- **`aid-fsm.sh advance-to-gates` Atomic Command** — single command runs gates and routes through `cmd_transition EXECUTE GATES` on success. Eliminates the `gates_no_generated_by` chicken-egg precondition fail (P020 8×, P021 4× — 12 friction events across 3 EPICs). Atomicity: state changes only on full success; gates failure leaves state at EXECUTE (never modified). No new state added — `VALID_STATES` and `VALID_TRANSITIONS` unchanged. Single source of truth for preconditions remains `check_preconditions` (`_generated_by`, `fsm_check_verifier_output`, `fsm_check_grandfather`).
- **Bats Coverage for advance-to-gates** — `test-aid-fsm.bats` expanded from 14 to 18 assertions covering all branches: success path, gates-fail path (state stays EXECUTE), missing CP3 outputs (cmd_transition rejects after gates pass), and aid-run-gates.sh env-var bypass behavior with and without `AID_GATES_TRIGGERED_BY_FSM=1`. New `test-helpers.bash` helpers: `seed_test_state_files`, `setup_passing_execution_yaml`, `setup_failing_execution_yaml`, `write_valid_verifier_output`.

### Changed
- **`aid-run-gates.sh` State Guard** — accepts env-var bypass `AID_GATES_TRIGGERED_BY_FSM=1` as the signal that the caller is `cmd_advance_to_gates`. Strict equality check (`=="1"`) prevents accidental bypass via truthy values. Manual two-step flow (state==GATES + run-all without env var) remains fully backward-compatible. Error message now hints at the atomic `advance-to-gates` alternative when state==EXECUTE without the env var.
- **`pipeline.md §5 GATES State`** — adds Recommended Flow (v2.18.3+) subsection documenting `aid-fsm.sh advance-to-gates`; preserves Manual Two-Step Flow subsection for debugging and crash recovery. Both flows fully documented with semantics, env-var signal, and timeline events.

### Fixed
- **`gates_no_generated_by` Precondition Fail Class** — empirical motivation for the atomic command: P020 had 8 such failures, P021 had 4 — 12 friction events across 3 EPICs from a single root cause (chicken-egg between gates runner state guard and transition's `_generated_by` check). Target post-deploy: 0 fails of this type.

## [2.18.1] — 2026-05-09

### Fixed
- **`aid-diagnostic.sh` 3 bugs** — (1) Branch hygiene now reads from `fsm-state.yaml` instead of `state.yaml` (which is the JSON steps array and has no `branch:` field); was reporting 88–100% "missing" for all projects. (2) Deploy era loop adds `post-session-b` so post-Session-B EPICs appear in the era distribution table — were previously silently dropped. (3) `collect_precondition_fail_reasons` → `collect_fsm_fail_reasons` extends jq filter to capture `fsm_increment_fail` and `fsm_done_advance_fail` in addition to `fsm_precondition_fail`; was missing 52% of all FSM fail events (the dominant category: `verify_no_*` format-discovery failures).

## [2.18.0] — 2026-05-08

### Added
- **CP2 Per-Step Verifier Pre-Filter** — `aid-prefilter.sh` classifies each step's git diff as `SKIP` (docs/config/test only, exit 0), `RUN` (code changed, exit 10), or `FAIL` (hardcoded secret/credential detected, exit 20). `cmd_increment_step` reads the classifier verdict and refuses to advance past a FAIL classification; SKIP bypasses CP2 verifier dispatch entirely. `pre-filter-rules.yaml` holds the rule set (docs patterns, secret patterns, code extensions). Closes the CP2 dead-weight problem where verifier was dispatched on pure-docs commits, burning tokens with no signal.
- **CP3 Integration Review Enforcement** — `EXECUTE→GATES` precondition now requires both `verifier-output-cp3-code-review.md` and `verifier-output-cp3-security.md` to exist in the evidence dir. Previously the transition was gated only on `current_step >= total_steps`. Missing CP3 outputs produce a specific precondition failure message listing which files are absent.
- **`fsm_handle_force_override` Unified Dispatcher** — replaces 4 inline `--force` bypass blocks with a single `fsm_handle_force_override from to reason state_file timeline_file` function. Validates `--reason` length ≥ 20 chars (short reasons rejected with exit 1 before any state mutation), emits `fsm_force_override` timeline event, writes to `aid-audit-log.sh` audit trail. Consistency: all force paths now go through identical logging — no more "force but no timeline event" edge cases.
- **`aid-audit-log.sh`** — standalone append-only audit log writer (`aid-audit-log.sh append <evidence_dir> <event_type> <json_payload>`). Writes to `evidence/{epic}/{run}/audit-log.jsonl`. Used by `fsm_handle_force_override` and available for future audit-requiring commands.
- **Verifier Nuanced Deprivation Context** — `agents/verifier.md` updated with classification-aware dispatch: verifier receives pre-filter classification + the specific diff that triggered RUN so it can focus on the actual change rather than the full step output. Adds step-level `## Memory Used` / `## Memory Written` enforcement to verifier output schema.
- **Compliance `verifier_outputs` Object Schema** — `compliance.json` now records per-step CP2 outcomes as an object (`{step_N: {classification, verdict, ts}}`). `evaluate_compliance_checks` validates presence and structure. `write_compliance_json` populates the field from step-verify evidence.
- **Compliance `deploy_era` Three-Tier Field** — `compliance.json` carries `deploy_era: pre-session-a | post-session-a | post-session-b` based on `DEPLOY_DATE` marker comparison. Enables longitudinal trend filtering: `--era post-session-b` sees only post-Session-B EPICs, `--era latest` auto-resolves to newest era present in evidence tree.
- **`aid-compliance-report.sh --era` + `--compare`** — `--era <name>` filters aggregated report to one deploy era; `--era latest` auto-resolves. `--compare ERA1,ERA2` produces side-by-side dimension table (pass/fail/null per era) for Session A → B delta analysis without Excel.
- **`aid-compliance-report.sh --reflect` `force_override` Extension** — `--reflect` pattern detection now includes `force_override` dimension: avg > 1 per EPIC → `🔴 SYSTEMATIC` banner. Average computed via integer arithmetic (`avg_x100 > 100`) to avoid floating-point dependency. Feeds the Session A → B "what holes remain" PM gate.
- **`aid-epic-summary.sh` Auto-Generated EPIC Summary (IMP-090 fold-in)** — `done-advance` hook calls `aid-epic-summary.sh generate <evidence_dir>` after `write_compliance_json`. Produces `<evidence_dir>/epic-summary.md` with 5 sections: ✅ Co bylo dodáno (git log since base_commit), ⚠️ Varování a přeskočené kroky (timeline events: branch mismatch, unusual branch, force override, repeated precondition fail, increment-step churn), ❌ Co se nestihlo (audit/curator blocking/L-effort findings), 📋 Co dělat dál PM akce (escalations, force override follow-up, L-effort proposals), 🔍 Honest signal trust level (HIGH/MEDIUM/LOW from compliance.json + branch heuristics). Best-effort: each section individually guarded with `|| true`; generation failure logs a warning and never blocks release flow. IMP-089 forward-compat: reads `branch_convention:` from `.aid-o/config/project.yaml` if present for feature-branch false-alarm suppression.
- **Plan-Writing Gate #18** — `plan-writing.md` Completeness Gate adds check #18: plans must not contain forbidden phrases that assert completeness without evidence ("already handles", "no changes needed", "existing implementation covers"). Accompanies Gate #17 (codebase grounding) from v2.17.0.
- **bats Suite Expanded to 33 Assertions** — 5 files: `test-aid-fsm.bats` (14, +5 CP2/force assertions), `test-aid-prefilter.bats` (6, NEW — SKIP/RUN/FAIL exit codes + output format), `test-aid-compliance.bats` (4, NEW — --era/--compare/--reflect triple-condition), `test-aid-epic-summary.bats` (2, NEW — 5-section headers + force_override timeline propagation), `test-aid-run-gates.bats` (7, unchanged from v2.16.0).

### Changed
- **pipeline.md §CP2 and §CP3** — full rewrite of both subsections to document v2.18.0 enforced protocol: pre-filter classifier, verifier dispatch conditions, CP2 evidence file naming (`verifier-output-step-N.md`), CP3 mandatory dual-file output schema, fix-loop (gate-fixer → verifier, max 2 iterations).
- **pipeline.md §force_override policy** — new subsection documenting `fsm_handle_force_override` contract: required fields, minimum reason length, audit trail, PM-only authorization, forbidden patterns.
- **pipeline.md Epic Summary** — new subsection documenting IMP-090 5-section schema, per-section data sources, trust level heuristics table, IMP-089 forward-compat note.
- **`aid-fsm.sh plan_json_hash` pipefail guard** — `grep '^plan_json_hash:'` with `set -eo pipefail` caused silent exit when field absent from `state.yaml`. Wrapped with `|| true` guard. Exposed by CP2 SKIP-classification test (step-verify without hash field).

### Fixed
- **`aid-stage-log.sh` JSON array/object prefix corruption** — `log_event` escaped payload before writing to `timeline.jsonl`; payloads starting with `[` or `{` (JSON arrays/objects) were double-escaped on the `data:` field. Added prefix detection: if payload starts with `[` or `{`, write `data: <payload>` verbatim; otherwise apply existing escape. Discovered during CP3 verifier-output path testing.

## [2.17.0] — 2026-05-06

### Added
- **CP1 Codebase Grounding Rule** — `plan-writing.md` Completeness Gate gains check #17 (16 → 17). Plans must verify every named external resource (functions, helpers, file paths, ports, services, commands, env vars) against the real codebase or running infra. Hand-wave like "presumably exists in some lib" or "should be available" is a hard fail. Addresses systematic CP1 blind spot identified in P032 retrospective: 5 PM-authorized resolutions (C1–C5 in P032) were all of this kind — reviewer cannot detect *absence* of helpers/files the plan presumes exist.
- **Verifier Codebase Grounding Pass** — `/aid-plan` Step 9 (CP1 review) verifier dispatch now MUST extract a flat list from the plan of every named function, helper, file path, port, service, command, and env var, and verify each against the real codebase / running infra (`grep`, `ls`, `docker ps`, `command -v`). Each item gets VERIFIED (with location) or ABSENT (mapped to a Create step). Plans with ABSENT items not mapped to Create steps → REVISE_REQUIRED.
- **`aid-compliance-report.sh --reflect`** — lightweight `/aid-reflect` (per AID-013). Per-dimension breakdown (pass / fail / null counts + 10-cell text bar chart) with pattern detection: 0 fails → ✅ green, 1 fail → ⚠️ INVESTIGATE (could be one-off), ≥ 2 fails → 🔴 SYSTEMATIC (hole in Session A enforcement). Recommended-next-action section addresses PM retrospective from P032: aggregate ≥ 80 % can hide a single dimension failing systematically; per-dimension trend is the actionable signal before Session B brainstorm.

## [2.16.1] — 2026-05-06

### Fixed
- **`aid-compliance-backfill.sh` aborts on legacy v1 evidence** — `set -euo pipefail` caused the backfill to abort on the first vulcan/sousto evidence dir whose `state.yaml` lacked a `branch:` field (`grep` returns 1 → pipefail propagates). Wrapped the `grep | awk` extraction (and the `jq | sort | head` pipeline in `backfill_state_created_at`) in `|| true`. Discovered during the v2.16.0 post-merge deploy run.
- **`aid-compliance-backfill.sh` corrupts legacy v1 JSON state files** — some pre-v2 evidence dirs store `state.yaml` as a JSON array of step objects (legacy `plan_progress.json` format). The backfill appended `created_at: <ts>` directly, breaking JSON validity (the line landed on the same line as the closing `]` because the file lacked a trailing newline). Added file-format detection: if the first non-blank char is `[` or `{`, log a warning and skip stamping. Plus a defensive `printf '\n'` guard before any append on YAML files. Live tree was repaired with `sed` post-incident; no data loss.

## [2.16.0] — 2026-05-05

### Added
- **Branch Enforcement in PRE-FLIGHT** — `aid-fsm.sh init` automatically creates `task/{epic_id}/main` from main/master/develop, detects mismatch with copy-paste fix, respects worktree mode. Closes AID-001 (65% of pre-Session-A state.yaml claimed `branch: main` with no actual task branch, breaking done-advance audit trail).
- **Real Gates Execution Provenance** — `aid-run-gates.sh` rewritten with yq parsing, emits `gate_runner_start` / `gate_runner_complete` timeline events and writes `_generated_by` / `_generated_at` / `_command_log` provenance fields into `gates_report.json`. EXECUTE→GATES precondition mechanically rejects hand-written reports.
- **Lazy execution.yaml Creation** — `aid-init` (and `aid-fsm.sh init` auto-recovery) generates per-project `execution.yaml` from auto-detected stacks (Python, TypeScript, Go, Rust, bash) with `# DEPENDENCY` hint comments per gate command. Closes AID-006 (71% of projects had no execution.yaml).
- **Compliance Telemetry** — `done-advance` writes per-EPIC `compliance.json` with 6-dimension schema (3 measured for Session A, 3 `null` for Sessions B/C). Standalone `aid-compliance-backfill.sh` for one-shot pre-deploy backfill (also stamps mid-FSM `state.yaml.created_at` per CP1 M2). Aggregator `aid-compliance-report.sh` produces pre vs post comparison with `--since` and `--era` filters.
- **svc-mcp-tg-bot MCP Server** — new Docker service in `services/mcp-tg-bot/` (FastMCP, stdio + HTTP transport on port 8817 — see Removed section for the legacy MCP that previously held this port). `send_message` tool with HTML parse_mode default. Token shared via `/opt/eco/services/.env`. Includes `docker-compose.snippet.yml` for PM to integrate into `/opt/eco/services/docker-compose.yml`.
- **FSM Repeated-Fail Telegram Alert** — `aid-fsm.sh` emits `fsm_precondition_repeated_fail` event and best-effort `try_telegram_alert()` HTTP POST to localhost:8817 when same precondition fails ≥ 3 times on the same EPIC.
- **Parametrized Diagnostic Script** — `aid-diagnostic.sh` reusable forensic analyzer (refactored from Krok 0 logic, supports `--evidence-root`, `--output md|json`, `--limit`).
- **bats Unit Test Suite** — 16 assertions across `test-aid-fsm.bats` (9), `test-aid-run-gates.bats` (3), `test-aid-init.bats` (4) covering all new FSM preconditions, gate runner provenance, and stack detection. Runs via `bats plugins/aid-orchestrator/scripts/tests/bats/`.
- **Dependency Pre-flight Script** — `aid-check-deps.sh` verifies `bash`, `git`, `jq`, `yq` (mikefarah variant only), plus optional `bats`, `direnv`, `docker`, `curl`. cmd_init now has fail-fast guard for `git` + `jq`.
- **README Requirements Section** — explicit dependency table in plugin README listing required runtime, optional dev, and optional Telegram-alerts tools with install commands per OS.
- **Worktree Development Guide** — plugin README section + committed `.envrc` with `AID_PLUGIN_PATH=$(pwd)/plugins/aid-orchestrator` and `PATH_add` for direnv-driven worktree workflows.
- **DEPLOY_DATE Marker File** — `plugins/aid-orchestrator/DEPLOY_DATE` (ISO 8601 UTC) consumed by `fsm_check_grandfather()` as the pre/post-Session-A threshold. Fallback chain: `AID_DEPLOY_DATE` env → `${AID_PLUGIN_PATH}/DEPLOY_DATE` → `${SCRIPT_DIR}/../DEPLOY_DATE`.

### Changed
- **pipeline.md** — three subsection rewrites: PRE-FLIGHT branch-enforcement catalog (5 HEAD states + 2 timeline events), GATES EXECUTE→GATES precondition with `_generated_by` requirement and grandfather caveat, DONE phase Compliance Telemetry section with 6-dimension table and null semantics caveat.
- **state.yaml schema** — adds `created_at` field (ISO 8601 UTC) used by grandfather logic for backward-compat with pre-deploy EPICs.
- **lib/aid-stage-log.sh** — new `log_info` / `log_warn` / `log_error` helpers with `[INFO]/[WARN]/[ERROR]` severity prefix on stderr (greppable, exported alongside `log_event`).
- **fsm_precondition_fail timeline event** — now carries `reason` field (set by individual precondition cases via `_PRECONDITION_FAIL_REASON`) so `fsm_count_recent_fails` can group repeated failures by failure type.
- **aid-fsm.sh::cmd_init** — overrides caller's `branch` arg ($5) with actual `git rev-parse --abbrev-ref HEAD` after PRE-FLIGHT enforcement so `state.yaml.branch` reflects post-enforcement reality (PM-authorized resolution C3).

### Fixed
- **Branch hygiene gap** — closes the 65% of pre-Session-A `state.yaml` files claiming `branch: main` with no actual task branch. New auto-checkout closes the loop with `done-advance` release sub-phase `git merge`.
- **Fake gates reports** — closes the 0% gate-runner execution evidence in 93 analyzed timelines. Provenance fields make hand-written reports mechanically detectable.
- **Missing execution.yaml** — closes the 5/7 (71%) projects lacking gate config, which forced agents into ad-hoc gate names per EPIC with no cross-project consistency.
- **Mid-FSM EPIC unblock (CP1 M2)** — backfill stamps `created_at:` into existing `state.yaml` from earliest timeline event ts, preventing the ~14 mid-FSM EPICs identified in diagnostic-findings from becoming unresumable post-deploy.
- **aid-run-gates.sh CLI parser** — fixed `${4:-default}` swallowing `--state-file` flag when caller skipped the optional 4th positional, which silently broke `gate_runner_start`/`gate_runner_complete` events for FSM-driven invocations. Regression test added to `test-run-gates.sh`.
- **Test suite git-context invariant** — `test-fsm.sh` and `test-integration-phase1.sh` setup() now `git init` their mktemp dirs so PRE-FLIGHT branch enforcement (new in this version) finds a working tree. Existing tests preserved without behavioral change.

### Removed
- **Legacy `svc-mcp-telegram` MCP (port 8817 takeover)** — the previous general-purpose Telegram MCP at localhost:8817 is decommissioned and replaced by `svc-mcp-tg-bot` on the same port. The old MCP exposed 9 tools (send_message, edit_message, search_dialogs, get_draft, set_draft, get_messages, media_download, message_from_link, delete_message) for general Telegram interaction; the new MCP exposes 1 tool (send_message) focused on AID-internal alerting. PM verified zero call sites in repo before removal (only permissions.yaml whitelist + docs entries referenced it). `defaults/policies/permissions.yaml` updated accordingly: 9 `mcp__shared-telegram__*` whitelist entries collapsed into 1 `mcp__svc-mcp-tg-bot__send_message` entry.

## [2.15.0] — 2026-03-25

### Added
- **Mechanically Enforced FSM** — `aid-fsm.sh transition` now verifies preconditions before allowing state changes: READY→EXECUTE requires `plan.json`, EXECUTE→GATES requires all steps complete, GATES→DONE requires `gates_report.json` with `overall: pass`, ESCALATION exits require `escalation_decision` set
- **`verify-state` Command** — new `aid-fsm.sh verify-state` returns current state + allowed transitions as JSON for LLM orientation
- **`set-field` Command** — new `aid-fsm.sh set-field` for structured state mutations (escalation decisions, custom fields)
- **FSM Audit Trail** — all `aid-fsm.sh` operations (transitions, precondition failures, force overrides) logged to `timeline.jsonl` via `aid-stage-log.sh`
- **`--force` Escape Hatch** — `aid-fsm.sh transition --force` bypasses preconditions with PM approval, logged as `fsm_force_override`
- **Gates State Check** — `aid-run-gates.sh --state-file` refuses to run unless FSM state is GATES
- **Gates Report Persistence** — `aid-run-gates.sh --report-file` auto-writes `gates_report.json` (required by GATES→DONE precondition)
- **Mechanical Enforcement Protocol** — new section in `aid-run.md` with 8 non-negotiable rules for FSM compliance
- **DONE Sub-Phases** — `done_phase: review → release` within DONE state, managed by `aid-fsm.sh done-advance` with evidence-based preconditions (curator-report, audit-report, pm_decision=merge)
- **Reserved Field Protection** — `set-field` rejects writes to `state` and `done_phase` (must use dedicated `transition`/`done-advance` commands)
- **Release Script FSM Guard** — `aid-release.sh` refuses release when `state.yaml` exists with `done_phase != release` (Layer 2 defense)
- **Git Pre-Commit Hook** — FSM guard on `task/*` and `epic/*` branches blocks commits in DONE/review and READY states (Layer 3 defense)
- **Hook Auto-Install** — `/aid-init` installs/upgrades pre-commit hook with marker-based append (coexists with existing hooks)
- **Step Verification Enforcement** — `increment-step` refuses to advance without `step-{N}-verify.md` evidence file (AC checklist + visual check)
- **Agent Dispatch Protocol** — 6 non-negotiable rules in pipeline.md: verbatim plan content, visual assets, post-step AC verification, visual verification for UI, resume-on-failure, visual context dispatch
- **Visual Companion** — browser-based HTML prototype viewer for brainstorming (opt-in, Node.js server adapted from Superpowers). Generates interactive mockups during design sections, saves approved HTML as 4th input type for visual assets pipeline. Per-question visual/text decision taxonomy.
- **Visual Assets Pipeline** — 4 input types (GitHub repo, AI Studio URL, PNG, Visual Companion) → unified `visual-spec.yaml` output; `visual_refs` field in plan.schema.json; visual dispatch protocol in pipeline.md §4; Visual Anchoring requirement in frontend role card; screenshot comparison protocol (MATCH/PARTIAL/MISMATCH); forbidden text-only UI descriptions in plan-writing.md
- **Plan-Level DONE Gate** — `aid-fsm.sh init` blocks cross-plan run if previous plan has unreviewed C+A findings (`ca-review-complete` marker required); enforces "dispatch per EPIC, validate per Plan" model
- **Step-Verify Content Validation** — `increment-step` now requires at least one `- [x]` AC checklist item and one commit hash (7+ hex chars); prevents minimal "Result: PASS" without substance
- **Plan.json Init Warning** — `aid-fsm.sh init` warns when plan.json steps lack `objective` field
- **Per-Project Agent Memory (Qdrant)** — 10-category deep codebase scan (architecture, API, data, UI, config, testing, conventions, security, DevOps/CI-CD, cross-cutting concerns); `memory-mcp.md` skill with entry schema, quality rules (≥20 word summary, real code examples, 5 rejection criteria), store/find protocol, supersede pattern; pipeline §4 memory READ (2-tier context injection ~1500 tokens); pipeline §7 Scanner dispatch at plan boundary; `memory_writes` mandatory in agent output; `## Memory Used` + `## Memory Written` enforced in step-verify by `increment-step`; Auditor Memory Health category (stale detection, conflict detection, coverage check); kondice flow (auditor flags → scanner verifies)

### Changed
- **FSM Valid States** — added ERROR to `VALID_STATES`; added `→ERROR` transitions from READY, EXECUTE, GATES, ESCALATION
- **Escalation Cleanup** — `escalation_decision` field auto-cleared when leaving ESCALATION state
- **Pipeline §3-§6** — each section now documents which FSM preconditions enforce correct behavior

### Fixed
- **Dead Cross-References** — replaced 20+ references to deleted v1 files (dispatch-protocol.md, epic-orchestration.md) with v2 equivalents across 11 files
- **v1 State Names** — replaced v1 FSM states (PM_APPROVAL, CURATOR_RESOLVE, PHASE_CHECK, IDLE) in pipeline.md; added v1 legacy headers to improvement-proposals.md and analytics.md
- **v1 Directory Paths** — updated CLAUDE.md workspace structure from v1 (01-plans/, 04-engine/) to v2 (plans/, work/)
- **Pre-Commit Hook** — removed dead case statement (non-functional code from refactoring)

## [2.6.0] — 2026-03-14

### Added
- **Standards Enforcement System** — two standard sets (`general.yaml` with 26 language-agnostic rules, `vulcan.yaml` with 22 ecosystem-specific rules + 4 severity overrides) selectable during `/aid-init`
- **Standards Gate** — new `standards_compliance` gate in `execution.yaml`, 100% deterministic (pattern/structural/file-exists rules only), custom/LLM rules are auditor-only advisory
- **Standards Audit Category** — new conditional category I) in auditor with full-codebase scan, severity-based scoring (cap 5 violations/rule), 15% weight when active
- **Standards Curator Integration** — hotspot detection (3+ violations of same rule = systemic), `source_type: standards` proposals with auto-approve for S-effort fixes
- **Standards Dispatch Context** — agents receive filtered standards in prompt (gate-blocking first, filtered by language), omitted when `standards.active == 'none'`

### Changed
- **Auditor Category Count** — 8→9 categories (5 mandatory + 4 conditional), weight redistribution when standards active (Code 30→25%, Security 30→27%, Docs 25→23%)
- **Agent Execution Summary** — includes `Standards violations noted: {count}` for trend tracking
- **Init Flow** — standards profile selection (general/vulcan/none) with `project.yaml → standards` config block

## [2.5.0] — 2026-03-13

### Added
- **Plugin Path Discovery** — `/aid-init` discovers and caches plugin installation path in `config/plugin.yaml`; Script Execution Protocol in `agent-core.md` teaches all agents how to resolve `scripts/X.sh` references
- **Brainstorming Question Format Template** — concrete format with Effort/Risk per option, recommendation with "Why not" reasoning, and webhook delivery example
- **Brainstorming Handoff Summary** — plan-writing presents decision summary + 6 options including `/aid-run --auto` with `autonomous_mode` prerequisite warning
- **Superpowers Conflict Resolution** — CLAUDE.md template includes conflict table (brainstorming, writing-plans, executing-plans → AID equivalents); 3 `skill_conflicts` entries in `orchestration.yaml`
- **Documentation Gate Enforcement** — path-pattern correlation: `docs_updated` gate fails only when API-path files changed without doc updates; auditor escalates missing API docs to high severity

### Changed
- **PRE-FLIGHT Plugin Verification** — `/aid-run` and `/aid-do` verify `plugin_path` on startup with cache invalidation fallback
- **Dispatch Context** — `agent-protocol.md` input format includes `plugin_path` for dispatched agents
- **Brainstorming Rule 8** — now explicitly requires effort estimate (S/M/L) and risk (L/M/H) per option

### Fixed
- **`/aid-plan-epic` stale references** — replaced with `/aid-plan --epic` across brainstorming, plan-writing, pipeline, and planner skills (command merged in v2.0)
- **`aid-plan.md` step count** — Steps 1-7 showed `/8` denominator instead of `/9` after CP1 review was added as Step 9

## [2.4.0] — 2026-03-12

### Added
- **PM Merge Decision Gate** — DONE state presents combined curator+auditor summary, PM explicitly chooses MERGE/FIX/ABORT before code reaches main
- **Parallel Curator+Auditor** — Both dispatch simultaneously in DONE state, reducing post-completion wait time
- **Auditor Auto-Fix** — S and M effort recommendations trigger gate-fixer dispatch pre-merge via new `recommended_fixes` output field
- **70/30 Design Principle** — Documented deterministic-first philosophy in pipeline §1: 70% bash, 30% LLM
- **Review Pre-Filter** — Bash regex checks (secrets, SQL injection, eval, debug) run before CP2/CP3/CP6 verifier dispatch, skipping LLM when unnecessary
- **Per-Escalation Templates (E1-E8)** — Each trigger shows specific context, findings, affected files, and available commands

### Changed
- **DONE State Flow** — Merge moved from step 3 to step 13 (after PM approval); prevents premature merge before review
- **Curator Auto-Evaluation** — Tier 2 default: M-effort proposals now auto-approved (was: deferred to PM)
- **PM Interaction Points** — Enhanced output at READY (gate details), CP1 (severity summary + 3 options), CP6 (evidence paths), scope warnings (actionable commands), and ESCALATION (per-type context blocks)
- **Auditor Dispatch Timing** — Now dispatched pre-merge in parallel with Curator (was: post-merge sequential)

## [2.3.0] — 2026-03-12

### Added
- **Review Checkpoints (CP1-CP6)** — Automatic verifier dispatch at 6 pipeline milestones: post-brainstorm plan review, per-step code review, pre-GATES integration review, curator proposal validation, auditor critical-finding gate, and post-/aid-do quick review
- **Fix Loop Protocol** — Verifier findings with Critical/High severity trigger gate-fixer dispatch + re-verification (max 2 iterations), replacing reactive gate-failure-only fixes
- **Critical Finding Gate (CP5)** — Auditor critical findings now block DONE state, triggering ESCALATION instead of proceeding to queue
- **Review Checkpoint Configuration** — New `review-checkpoints.yaml` policy file with per-checkpoint toggles, fix-loop settings, and trivial-skip threshold
- **Escalation triggers E7, E8** — Verifier review failure after fix loop; auditor critical security finding
- **Pipeline §13** — New Review Checkpoint Protocol section as authoritative reference

### Changed
- **Verifier agent** — Expanded from on-demand to automatic dispatch with fix-loop integration and checkpoint-specific context assembly
- **Gate-fixer agent** — Now accepts verifier review findings as input (source: `verifier_review`), not just gate failures
- **Auditor agent** — Critical findings produce `blocking_findings` flag that blocks DONE transition
- **Pipeline §4-§8** — Updated with review checkpoint dispatch points at EXECUTE, GATES, DONE, and FAST MODE

### Fixed
- **Broken cross-references** — Fixed 5 stale v2 migration references: auditor.md, gate-fixer.md, curator.md, planner.md pointed to non-existent `epic-orchestration.md`/`retry-engine.md`; pipeline.md referenced non-existent `dispatch-config.yaml`

## [2.2.0] — 2026-03-11

### Added
- **Context Persistence (Interim Document)** — `/aid-plan` now creates `.aid-o/work/interim-P{NNN}.md` at session start, updated after each step with full conversation detail; survives context window overflow and session interruptions; auto-deleted on plan completion
- **Concurrent brainstorm detection** — checks for existing interim docs before starting new brainstorm, offers resume or fresh start
- **ID Allocation Procedure** — documented read-increment-write protocol for counter.yaml in run-management ID System section

### Fixed
- **Dead `epic-orchestration.md` references** — updated brainstorming.md, plan-writing.md, and run-management.md to reference run-management ID System instead
- **Abort text accuracy** — "no files created" corrected to "no plan written, interim doc preserved"
- **plan-writing.md missing interim cleanup** — added MUST rule 15 to delete interim doc after successful plan write

## [2.1.1] — 2026-03-10

### Fixed
- **`.gitignore` missing from `/aid-init`** — Init now creates `.gitignore` appended to project root, ignoring runtime artifacts (evidence, quick logs, timeline.jsonl, queue.yaml) while keeping design artifacts versioned
- **Defaults `.gitignore` outdated** — Updated from v1 paths (`.aid-o/04-engine/`) to v2 structure

## [2.1.0] — 2026-03-10

### Changed
- **Brainstorming skill refactored** — 34% smaller (415→272 lines) with 8 new capabilities: scope decomposition, MoSCoW prioritization, risk assessment protocol, prior-plan lookup, pre-decided solution handling, context-loss recovery, workflow/AI questioning hint, Docker Compose recommendation
- **Design section templates extracted** — Moved to `defaults/templates/design-sections.md` as standalone reference, reducing brainstorming skill size while preserving all templates

### Removed
- **Obsolete planning docs** — Removed CRITICAL-ASSESSMENT.md and REDESIGN-PLAN-v2.md (completed, no longer relevant)

## [2.0.0] — 2026-03-03

### Breaking Changes
- **11-state LLM FSM → 6-state bash FSM** — States reduced from IDLE/PLANNING/PLAN_REVIEW/EXECUTING/PHASE_CHECK/NEXT_PHASE/GATES/GATE_RETRY/ESCALATION/CURATOR_RESOLVE/PM_APPROVAL/DONE to READY/EXECUTE/GATES/ESCALATION/DONE/ERROR. State transitions enforced by `aid-fsm.sh`, not LLM instructions.
- **27 skills → 8 skills** — Consolidated from 27 cross-referencing skills to 8 focused skills (agent-protocol, pipeline, planner, brainstorming, quality-gates, run-management, memory, role-cards). Removed: epic-orchestration, dispatch-protocol, gates-engine, retry-engine, first-aid-controller, auto-escalation, auto-done-state, parallel-dispatch, cost-optimization, epic-queue, slack-mcp, workflow-intelligence, and 15 others.
- **18 agents → 7 agents** — Consolidated from 18 role-based agents to 7 controller agents (implementer, verifier, gate-fixer, curator, auditor, project-scanner, run-validator). Removed: architect, backend, frontend, domain, qa, security, observability, docs-writer, release, code-reviewer, docs-reviewer, lessons-extractor, quality-gates-runner.
- **17 commands → 8 commands** — New unified commands: `/aid-do`, `/aid-plan`, `/aid-run`, `/aid-status`, `/aid-help`, `/aid-init`, `/aid-audit`, `/aid-stop`. Removed: `/aid-brainstorm`, `/aid-plan-epic`, `/aid-run-epic`, `/aid-first-aid`, `/aid-setup`, `/aid-epic-queue`, `/aid-epic-status`, `/aid-research`, and 9 others.
- **Directory structure** — `.aid-o/04-engine/` → `.aid-o/work/`, `.aid-o/02-epics/` → `.aid-o/tasks/`, `.aid-o/03-config/` → `.aid-o/config/`. Init creates 10 files (down from 40+).
- **10 policy YAMLs → 3** — `execution.yaml` (gates + dispatch), `project.yaml` (stack + preferences), `permissions.yaml` (agent permissions). Removed: decision-policies.yaml, dispatch-strategy.yaml, gates.yaml, memory-config.yaml, slack-config.yaml, and 5 others.

### Added
- **Fast Mode (`/aid-do`)** — < 2 min overhead for tasks < 2h. Creates Q-NNN.md quick log, skips full EPIC pipeline. Automatic scope detection.
- **Bash FSM (`aid-fsm.sh`)** — Deterministic 6-state finite state machine. States: READY → EXECUTE → GATES → DONE (happy path), with ESCALATION and ERROR branches. All transitions validated in bash, not LLM.
- **Bash gate runner (`aid-run-gates.sh`)** — Deterministic quality gate execution with JSON output, timeout handling, retry logic. Replaces LLM-manual gate evaluation.
- **Pipeline automation scripts** — `aid-auto-pipeline.sh` (orchestrator), `aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`. All deterministic operations moved from LLM to bash.
- **Stage logging (`aid-stage-log.sh`)** — Structured timeline.jsonl event logging with standardized format across all pipeline operations.
- **Token estimator (`aid-token-count.sh`)** — Character-based token estimation for prose/code/mixed content types.
- **`@aid/contract` package** — Shared TypeScript types for all `.aid-o/` data formats (AidFsmState, AidState, AidGatesReport, AidTimeline, etc.).
- **Progressive help (`/aid-help`)** — 4-level disclosure: Level 0 (cheat sheet), Level 1 (command detail), Level 2 (architecture), Level 3 (troubleshooting).
- **Scope check gate** — `scripts/gates/scope-check.sh` verifies implementation stays within EPIC-defined file scope.
- **173 tests across 13 suites** — Up from 88 tests / 6 suites in v1.7.0. Full coverage of FSM, gates, pipeline, stage logging, token counting, scope checking.

### Changed
- **~87% token reduction** — Plugin prompt tokens reduced from ~400K to ~50K by consolidating skills/agents/commands and moving deterministic logic to bash scripts.
- **`/aid-plan` merges 3 old commands** — Replaces `/aid-brainstorm` + `/aid-write-plan` + `/aid-plan-epic` into single progressive workflow.
- **`/aid-run` merges 2 old commands** — Replaces `/aid-run-epic` + `/aid-first-aid` with unified command supporting `--auto` flag.
- **`/aid-status` merges 2 old commands** — Replaces `/aid-epic-status` + `/aid-epic-queue` with combined view.
- **`/aid-init` merges `/aid-setup`** — Single idempotent init command creating 10-file `.aid-o/` structure with stack auto-detection.
- **Role cards consolidated** — All agent role definitions in single `role-cards.md` (8 roles + 4 focus cards) instead of 18 separate agent files.
- **Pipeline skill consolidated** — Single `pipeline.md` replaces 14 old orchestration skills, documenting all 6 FSM states.
- **Evidence paths** — `stage_log.jsonl` → `timeline.jsonl`, `plan_progress.json` → `state.yaml`.
- **aid-server paths** — Updated all Express routes and WebSocket handlers for v2 `.aid-o/` structure.

## [1.7.0] — 2026-02-28

### Added
- **Path Traversal Guards** — defense-in-depth (regex + resolve+startsWith) path validation on pipeline theater, evidence, and decision routes preventing CWE-22 filesystem traversal via `epicId`/`runId` parameters
- **GUI CORS Middleware** — `cors()` middleware on the aid-gui Express server with `AID_GUI_CORS_ORIGINS` env var support, defaulting to localhost:5173 and localhost:3000
- **Agent Name Frontmatter** — all 18 agent files now have `name:` field in YAML frontmatter matching the filename stem, enabling plugin validation
- **Master Test Runner** — `run-all-tests.sh` discovers and executes all test suites with unified pass/fail reporting (88 tests across 6 suites)
- **Curator Dispatch Regression Tests** — Suite F (5 tests) verifying unconditional Curator dispatch and state-entry logging in gate-evaluation.md and first-aid-controller.md
- **Phase Marker Documentation** — `plan-writing.md` Phase Markers subsection with exact format, rules, regex, and "do NOT use" examples for LLM-generated plans
- **PARALLEL_EXECUTING Sub-State** — `epic-state-machine.md` documents the FIRST AID parallel execution sub-state with activation criteria and safety limits
- **AI Companion Project Context** — system prompt auto-built from CLAUDE.md, package.json, pipeline state, EPIC queue, plans, decisions, ideas backlog, and project structure on every message
- **AI Companion Tool Use** — 7 tools (readFile, listDirectory, searchContent, readYaml, readEpic, readPlan, getPipelineState) giving the companion full codebase access with sandboxed paths and 8-step tool call limit
- **Voice Dictation Recording Bar** — waveform visualization via AudioContext AnalyserNode, elapsed timer, live interim text display (Web Speech API), and one-click stop-and-send flow
- **Whisper Auto-Detection** — background probe on mount detects Whisper availability; uses Web Speech API as primary (Czech `cs-CZ` support) with Whisper upgrade when OPENAI_API_KEY is set
- **FIRST AID Wrapper State Mapping** — FIRST_AID_INIT, QUEUE_PROCESSING, QUEUE_ADVANCE, FIRST_AID_COMPLETE mapped to medical labels (Triage, Operating, Next Patient, All Clear) with FSM colors and active state detection
- **Satellite Card Alternation** — Ward, Lab, Escalations, Vitals cards alternate between current and total values every 4 seconds with AnimatePresence transitions

### Changed
- **CORS Wildcard Handling** — `AID_CORS_ORIGINS=*` now correctly enables wildcard CORS instead of creating a single-element array `['*']`
- **Default Server Binding** — both aid-server and aid-gui default to `127.0.0.1` (loopback only) instead of `0.0.0.0`, preventing unintentional network exposure; Docker containers retain `0.0.0.0` via explicit env var
- **GUI README Replaced** — removed Gemini/AI Studio boilerplate, replaced with accurate AID Dashboard GUI documentation including local setup and aid-server dependency
- **Root README Version** — updated from v1.5.0 to v1.6.0
- **Brainstorming Step Count Standardized** — all documentation (README, Docusaurus, aid-help) now references 8-step brainstorming matching the actual skill lifecycle
- **aid-run-epic Prerequisites** — removed false auto-generation claim; `plan.json` must pre-exist via `/aid-plan-epic`
- **Zombie Backlog Cleanup** — moved 7 already-fixed entries (IMP-010/035/049/050/057/059/067) from Active to Implemented, correcting count from 62 to 55
- **EPIC ID Regex Hardened** — `aid-auto-pipeline.sh` now accepts alphanumeric plan IDs with internal hyphens (e.g., `E-TEST-001-1_2`)
- **Dependency Parser Enhanced** — `aid-plan-to-epic.sh` supports range expansion (`Steps 3-7`), trailing text stripping, cross-phase dependency filtering, and deduplication
- **Scope Generation Granularity** — `aid-plan-to-epic.sh` generates file-level paths in EPIC scope when plan steps have `**Files:**` sections, improving FIRST AID parallel detection accuracy
- **EPIC Template Scope Guidance** — template includes guidance comments encouraging file-level path declarations over broad directories
- **Curator Dispatch Made Unconditional** — `gate-evaluation.md` and `first-aid-controller.md` now mandate Curator dispatch at CURATOR_RESOLVE regardless of discovered_issues
- **QUEUE_PROCESSING Auto-Mode** — `first-aid-controller.md` includes parallel dispatch checklist cross-referencing `aid-first-aid.md` sections 3.1-3.5
- **Curator Auto-Defer Threshold Raised** — auto-mode now defers only effort:L proposals to backlog; effort:S and effort:M are fixed inline, increasing autonomous fix rate
- **Command Center State Labels** — all FSM states renamed to medical/hospital theme (On Call, Diagnosis, Prescription, Infusing, Vital Signs, Second Opinion, Lab Results, Doctor's Orders, Recovery, Discharged, Code Red)
- **Satellite Cards Data Sources** — Ward shows queue running+waiting / completed+failed; Lab shows gate runs+retries / audit score; Escalations shows budget usage / total escalations; Vitals shows steps executed / total events
- **EPIC Runs Display** — shows last 5 completed (most recent first) instead of first 5
- **Voice Flow Simplified** — removed confirm step; recording stops and sends directly (one action instead of three)
- **CommandPalette Voice** — transcript sends as message directly instead of inserting into filter input
- **Companion Open Speed** — status and sessions pre-fetched on project select; palette/panel opens instantly without network delay
- **Pipeline API Extended** — `/pipeline` endpoint returns full autoModeSession with escalation budget/count and aggregate counters (epicsCompleted, epicsFailed, totalStepsExecuted, totalGateRuns, totalGateRetries, totalEscalations)

### Fixed
- **WebSocket Replay Parsing** — `dispatchReplay()` now reads raw stage log entries directly instead of expecting non-existent `.entry` wrapper, fixing Pipeline Theater replay after reconnection
- **CSS Custom Property Generation** — `.replaceAll('_', '-')` replaces all underscores in FSM state names for correct CSS variable references (was `.replace` which only fixed the first)
- **Curator Input File References** — corrected from `step_output.json` to `output.md` + `diff.patch` matching actual agent output format
- **Queue Field Name** — `scripts/README.md` corrected `queued_at` to `added_at` matching actual queue schema
- **Queue Field Name Mismatch** — server returned `data.entries` but GUI expected `data.queue`, causing queue entries, elapsed time, and EPIC runs to never display
- **Topbar Voice Integration** — replaced inline mic recording logic (~90 lines) with shared VoiceButton component using `compact` prop

## [1.6.0] — 2026-02-28

### Added
- **Pipeline Scripts** — 5 bash scripts (`aid-plan-to-epic.sh`, `aid-epic-to-json.sh`, `aid-json-to-run.sh`, `aid-queue-add.sh`, `aid-auto-pipeline.sh`) for deterministic Plan→EPIC→json→run→queue conversion replacing LLM-driven operations
- **Shared Script Library** — `scripts/lib/common.sh` with 7 portable bash functions (YAML parsing, section extraction, slugify, prerequisites check, error formatting, timestamps)
- **Script Documentation** — `scripts/README.md` with full interface contracts, argument tables, exit codes, data flow diagram, and JSON manifest schema for all 5 pipeline scripts
- **EPIC Template Dependencies Section** — structured Dependencies section with Internal/External/Queue subsections replacing flat placeholder
- **Deterministic Work Detection Audit** — new audit category I) scanning commands, skills, and agents for LLM-performed template filling, structured parsing, and file manipulation that could be replaced by scripts, with false positive filters and -10 cap scoring
- **Pipeline Test Suite** — 76 tests across 6 test scripts (40 unit, 16 integration, 20 regression) with 3 fixture plan files covering single-phase, multi-phase, and cross-plan dependency scenarios

### Changed
- **aid-plan-epic Command** — rewritten from 544-line LLM-driven flow to 235-line script-orchestrated 6-step flow delegating deterministic work to `aid-auto-pipeline.sh`
- **aid-run-epic Command** — inline plan generation removed; `plan.json` must pre-exist (created via `/aid-plan-epic`) with clear error message and actionable suggestion when missing
- **Documentation Consistency Pass** — 10+ skill/command files updated to reference script-based pipeline, removing references to inline plan generation

## [1.5.0] — 2026-02-28

### Added
- **Token Estimation Protocol** — new `skills/token-estimator.md` defining character-based heuristic for dispatch token counting with cl100k_base approximation and calibration process
- **Dispatch Configuration** — new `defaults/policies/dispatch-config.yaml` with 18 role-to-model tier mappings (3 opus, 11 sonnet, 4 haiku), per-tier context defaults, and advisory budget alerts
- **Plan Schema Extension** — `model` (enum: haiku/sonnet/opus) and `context_scope` (knowledge, memory, previous_outputs) optional fields per step in `plan.schema.json`
- **Planner Model Assignment** — planner reads `dispatch-config.yaml` and populates `model` + `context_scope` per step with fallback to opus/all-context when config is absent
- **Dispatch Usage Logging** — pre-dispatch token estimation and post-dispatch `usage` object in stage_log.jsonl with model, tokens, duration, context sources, and budget alerts
- **Usage Aggregation** — DONE state aggregates all dispatch_complete entries into `usage_summary` in plan_progress.json with breakdowns by model, role, and step
- **Model Tiering in Dispatch** — `step.model` passed to Task tool with 3-level fallback chain (step.model → dispatch-config.yaml → opus default)
- **Selective Context Injection** — knowledge, memory, and previous outputs conditionally injected based on `step.context_scope` with full backward compatibility
- **Dispatch Prompt Trimming** — EPIC context reduced to one-line goal + step-level paths instead of full EPIC specification
- **Token Efficiency Audit** — new `/aid-audit efficiency` type with per-role baseline comparison and 2x alert threshold (advisory, 0% weight)

### Changed
- **Dispatch Protocol** — model parameter wired into Task tool calls, context injection is conditional, prompt uses trimmed EPIC context
- **Parallel Dispatch** — model tiering support with per-agent model resolution

## [1.4.0] — 2026-02-27

### Added
- **GUI Dashboard** — full-featured web dashboard (`aid-gui` package) with Express backend, WebSocket real-time updates, and React 19 + Zustand 5 frontend
- **Ideas-to-Execution Kanban** — drag-and-drop board tracking ideas through exploration → planned → running → done lifecycle with auto-status from linked plans/EPICs
- **AI Companion Chat** — SSE-streaming chat panel with markdown rendering, session management, voice input (Web Speech API), and contextual hint buttons
- **EPIC Lifecycle Manager** — GUI-driven EPIC listing with frontmatter parsing, run/schedule actions, queue integration, and status-sorted display
- **Evidence Vault** — full-text grep search across evidence files (200-result cap, binary detection), date-grouped collapsible sidebar, and markdown preview toggle with DOMPurify sanitization
- **Pipeline Theater SVG Timeline** — Gantt-like horizontal timeline with color-coded role bars (architect/backend/frontend/qa/docs/security), replay controls (0.5x–4x speed), EPIC/run selector, and live auto-scroll mode
- **Decision Hub Notifications** — Web Audio API sound alerts (440Hz sine, 3s debounce) and browser Notification API for background tabs, with Sidebar badge pulse animation
- **Evidence Search API** — `GET /evidence/search?q=&limit=` endpoint with case-insensitive text matching, path traversal protection, and binary file skipping
- **Pipeline Theater API** — `GET /pipeline/theater/:epicId/:runId` endpoint merging plan.json + plan_progress.json + stage_log.jsonl into combined theater data
- **Companion Backend** — session-store with JSON persistence, auto-detect LLM adapter (Claude/OpenAI/Ollama/stub), SSE streaming endpoint, voice transcription proxy
- **WebSocket Infrastructure** — topic-based pub/sub (pipeline, stage_log, decisions, queue) with heartbeat, auto-reconnect (exponential backoff), and replay on reconnect
- **Test Suite** — 1014 Vitest tests across 31 files covering server routes, parsers, WebSocket, store slices, and API client

### Changed
- **Project structure** — added `packages/aid-gui/` (frontend) and `packages/aid-server/` (backend) as monorepo packages alongside the plugin

## [1.3.1] — 2026-02-27

### Fixed
- **Curator evidence path** — `step_output.json` replaced with `output.md` so Curator can actually read agent improvement notes
- **FIRST AID skill reference** — `skills/first-aid-mode.md` corrected to `skills/first-aid-controller.md` in `/aid-help`
- **Czech preset descriptions** — translated to English in `permissions.yaml` (aspirin and steroids descriptions)
- **Stale epic-breakdown.md references** — 6 references across 5 files replaced with `epic.md` (the actual template)

## [1.3.0] — 2026-02-27

### Added
- **Queue dependency ordering** — `depends_on` field in queue schema with Kahn's algorithm cycle detection; `next()` computes READY/WAITING/BLOCKED eligibility per entry
- **INTERMEDIATE_GUARDRAIL** — 3-check auto-approval gate (all_steps_done, no_gate_failures, evidence_complete) for intermediate EPICs in FIRST AID mode
- **Queue write ownership** — CONFLICT_CHECK as Step 0 in add()/start()/complete() operations; single-writer constraint during FIRST AID via auto-mode flag file
- **Canonical EPIC ID format** — formal `E-{plan_id}-{phase}_{total}` specification with validation regex and cross-referenced documentation
- **Untrusted field list** — 10 untrusted and 6 trusted fields enumerated in dispatch-protocol with rationale for each classification
- **OVERLAP_CHECK algorithm** — concrete pseudocode for 3 cases (exact-exact, glob-exact, glob-glob) replacing vague prose in planner
- **R1 dependency classification** — DATA MODEL and API CONTRACT type definitions with 5-step determination algorithm replacing subjective criteria
- **plan_ref keyword matching** — 4-step algorithm with extract/score/stopping-rule/confidence-check replacing vague Strategy 3 description
- **Setup re-run detection** — `/aid-setup` detects existing workspace and offers 6-option section menu for selective reconfiguration
- **Release count verification** — RELEASE_CHECK_COUNTS ensures CLAUDE.md command/skill counts stay in sync during releases
- **DEFAULT_BASELINE** — threshold 50/100 applied when no prior audit report exists for PM_APPROVAL auditor trend check

### Changed
- **adapt_example()** — simplified from 7-step function (422 lines) to 3-step (83 lines): path substitution, tool reference update, validation
- **Credit exhaustion detection** — 5 hardcoded strings replaced with 6 case-insensitive regex patterns and short-circuit evaluation

### Fixed
- **Escalation snapshot** — now correctly writes to `interrupted_step_context.json` instead of inconsistent field names

### Removed
- **`--dry-run` flag** — removed from `/aid-first-aid` command; deferred to backlog as standalone feature

## [1.2.0] — 2026-02-27

### Removed
- **Permission Sandwich** — removed `skills/permission-sandwich.md` (750 lines) and `defaults/policies/permissions-auto.yaml` (164 lines); FIRST AID no longer backs up, elevates, or restores permissions — requires Steroids 💉 preset instead

### Changed
- **Permission presets** — Safe removed, Recommended renamed to Aspirin 💊, Advanced renamed to Steroids 💉; two-preset system with deny-list protection
- **FIRST AID startup** — permission sandwich steps (backup, elevate) replaced by single Steroids preset verification check
- **FIRST AID completion** — permission restore removed; /aid-stop simplified to 3 steps (mode flag, wait, save progress)

### Fixed
- **Plan archival** — QUEUE_ADVANCE now uses queue as ground truth for plan archival instead of filesystem scanning; DONE state no longer attempts archival (single source)
- **Version bump detection** — uses plan-level completion (`plan_epics_total`) instead of queue position; solo plans always bump, multi-EPIC plans bump on last EPIC
- **Release sub-phase** — DONE state now explicitly calls RELEASE_SUB_PHASE with mandatory stage_log entry; skipping is no longer possible without audit trail
- **Queue removal** — `/epic-queue remove` sets status "removed" (not "completed"); context boundary tracking distinguishes session total from actually-executed EPICs

## [1.1.0] — 2026-02-27

### Added

- **Plan-Writing Skill** — new `skills/plan-writing.md` with two modes: Mode A (post-brainstorming) and Mode B (standalone `/aid-write-plan`); includes Forbidden Phrase Detection hard gate, Traceability Verification, 16-point Completeness Gate, and Post-Write Handoff offering EPIC creation
- **`/aid-write-plan` Command** — standalone plan writing command that delegates to the plan-writing skill; accepts topic argument or interactive input
- **Brainstorming Critical Rules Block** — 11 critical rules at the top of `aid-brainstorm.md` with primacy effect positioning to prevent instruction drift
- **Brainstorming Step Self-Checks** — each of the 8 brainstorming steps now has a mandatory self-check checklist (2-4 items) that must pass before transitioning to the next step
- **Brainstorming Progress Tracker** — mandatory `=== Step N/8: {Name} ===` output at the start of every brainstorming step for checkpoint enforcement
- **Brainstorming Approach Hard Gate** — RULE 9 enforces minimum 2 approaches before presenting to PM; RULE 10 prevents skipping approach exploration even for "obvious" topics
- **Brainstorming Completeness Gate** — Step 8 now enumerates all PM answers from Steps 3-6 and verifies each appears in the plan document before finalizing
- **adapt_example() Implementation** — 7-step function in knowledge-acquisition.md replaces path placeholders, updates framework versions, handles Docker sections, aligns platforms, merges constraints, adjusts step count, and writes adapted EPIC
- **Knowledge Results Display** — brainstorming Step 1 now shows PM what knowledge was found ("Found N relevant docs: [names]") or "No knowledge indexed yet"
- **`/aid-help knowledge` Topic** — lists all example EPICs by category, explains search flow (Context7 → Qdrant → static), and documents indexing and research triggers
- **RESUME_SESSION safety net** — QUEUE_PROCESSING next() now filters on `status in ["queued", "running"]` with preference for running entries, so an interrupted EPIC is automatically resumed even when the RESUME_SESSION reset was skipped
- **Permission snapshot and restore** — `auto-mode-state.yaml` gains an `original_permissions_snapshot` field; RESTORE_PERMISSIONS now uses a two-tier fallback (backup file, then inline snapshot) across all three restore paths (COMPLETE, /aid-stop, crash recovery)
- **Permission grant log** — `auto-mode-state.yaml` gains a `permissions.grant_log[]` audit trail field recording each dynamic permission grant with permission, source, actor, step_ref, timestamp, and reason; PHASE_CHECK permission learning dual-writes to both `learned_permissions[]` and `grant_log[]`
- **Multi-agent parallel execution** — QUEUE_PROCESSING gains a complete parallel dispatch protocol: independence detection via EPIC scope analysis, Task agent dispatch in worktree isolation, sequential merge with shared escalation budget, failure isolation per agent, and a safety cap of 3 concurrent agents
- **Untrusted content tags in dispatch templates** — all 10 user-supplied interpolation points in `aid-run-epic.md` dispatch prompts are wrapped in `<untrusted_content>` tags with source attributes; safety preamble added to both base and re-dispatch templates to prevent prompt injection
- **Hardened deny-list entries** — `Bash(rm -fr:*)` (reversed short flags) and `Bash(dd if=/dev/urandom:*)` added to the hard-deny list in `permission-sandwich.md` and `permissions-auto.yaml` with inline rationale comments and updated Section 3.4 rationale table
- **Planner parallelism rules** — 5 named Parallel Group Assignment Rules added to `planner.md`; backend and frontend agents can now parallelize after architect+domain steps when file scopes do not overlap; includes OVERLAP_CHECK algorithm and 3 worked examples
- **Planner granularity heuristics** — HEURISTIC G1 (Layer Splitting) and G2 (Module Splitting) added to `planner.md` Section 2b with before/after examples and interaction rules; steps spanning 3+ layers or 3+ modules are automatically split
- **Audit instruction quality checks** — Section G added to `auditor.md` with 5 checks for instruction file quality (intro presence, TODO/FIXME scan, frontmatter, cross-reference accuracy, files exceeding 800 lines); weighted at 10% and conditional on `plugins/aid-orchestrator/` existing

### Changed

- **Brainstorming modular split** — 1371-line `brainstorming.md` split into core (569 lines) + two sub-skills: `brainstorming-knowledge.md` (445 lines) for knowledge acquisition and file analysis, `brainstorming-workflow.md` (443 lines) for workflow detection and Docker/MCP rules
- **Brainstorming flow simplified** — reduced from 11 steps to 8 steps; EPIC creation removed from brainstorming entirely (now handled by `/aid-plan-epic` via plan-writing handoff)
- **Plan-writing delegation** — brainstorming Step 8 now delegates to `skills/plan-writing.md` instead of writing the plan inline; plan-writing skill handles quality gates, forbidden phrase detection, and completeness verification
- **FIRST AID disclaimer** — reframed from alarmist "USE AT YOUR OWN RISK" to "Experimental Autonomous Mode"; added explicit `/aid-stop` emergency stop reference and `/aid-epic-queue` for queue review so users know how to intervene safely
- **Setup MCP advanced permissions preset** — replaced the broad `mcp__*` wildcard with 7 explicit tool patterns (`mcp__shared-github__*(*)`, etc.) matching auto-mode format; updated setup wizard comparison matrix to reflect the change
- **Epic orchestration skill split** — 2300-line `epic-orchestration.md` split into 5 modular files: slim orchestrator (138 lines), `epic-state-machine.md` (602), `dispatch-protocol.md` (498), `gate-evaluation.md` (509), and `first-aid-controller.md` (577); pure refactoring with no logic changes
- **PLAN_REVIEW template enriched** — per-step detail table added to PLAN_REVIEW state with 7 columns (Files, Tech, AC count, Output, Deps) and 6 enforcement rules so plan review captures the full structure of each step
- **DONE state release logic consolidated** — release behavior now exists in exactly one place (`auto-done-state.md`); `first-aid-controller.md` DONE state delegates to `auto-done-state.md` for all release steps, eliminating duplication

## [1.0.0] — 2026-02-26

### Added

- **GitHub MCP in Setup Wizard** — `/aid-setup` now includes GitHub MCP as recommended option 6e with full setup flow covering detection, auth check, install, verification, and troubleshooting
- **Setup Completion Banner** — `/aid-setup` displays a professional styled ASCII art banner with AID branding after successful setup completion
- **Version Pre-check in Plan Epic** — `/aid-plan-epic` Step 0 reads the local plugin version, compares it with the latest GitHub release via `gh api`, and warns if outdated (non-blocking)
- **Help Workflow Examples** — `/aid-help examples` returns three step-by-step workflows: Greenfield Feature, Quick Fix, and Multi-Phase with FIRST AID
- **Autonomous Mode Commands in Help** — `/aid-help commands` now includes detailed entries for `/aid-first-aid` and `/aid-stop` under a new AUTONOMOUS MODE COMMANDS section

### Changed

- **Setup MCP Options** — re-lettered MCP sub-options so GitHub MCP is 6e, Auto-detect is 6f, and Custom is 6g; restructured Step 5b as Optional MCP Follow-up
- **Skill Count** — updated documented skills count from 20 to 21 in CLAUDE.md and README to include the previously unlisted `workflow-intelligence.md`

### Fixed

- **Stale Paths** — replaced three remaining `workspace/workflow/` references with `.aid-o/` equivalents in `planner.md`, `aid-plan-epic.md`, and `slack-mcp.md`
- **README Version** — synced README version from stale 0.9.2 to 0.9.3 (now bumped to 1.0.0 with this release)
- **Command Frontmatter** — verified all 13 commands have `user_invocable: true`

## [0.99.0] — 2026-02-26

### Added

- **AID Server** (`packages/aid-server`) — Express + WebSocket backend serving the AID GUI dashboard; 18 REST API endpoints covering projects, pipeline state, EPIC queue, decisions, evidence, audit, ideas, usage metrics, and knowledge; real-time WebSocket pub/sub with chokidar file watching on `.aid-o/`; topic-based subscriptions with heartbeat and idle timeout
- **Docker deployment** — multi-stage Dockerfile (gui-build → server-build → production) and docker-compose.yml; single `docker compose up --build` serves both GUI and API on port 3911; health check included
- **Docusaurus documentation site** — full docs site with architecture, configuration, contributing, troubleshooting, reference docs, and Getting Started guides; deployed to GitHub Pages via GitHub Actions; EN + CS locales
- **GUI frontend polish** — AI Companion panel, replay controls, error boundaries, production build optimization (FIRST AID EPIC session, 5 EPICs completed autonomously)

### Fixed

- **MDX expression errors** — escaped `{type: performance}` in `decision-policies.md` and `{message_type}`/`{action}` in `slack-integration.md` that broke Docusaurus MDX compilation
- **GitHub Pages config** — replaced all placeholder values in `docusaurus.config.ts` (`your-org` → `marekstancl`, `your-project` → `claude-aid-o`)
- **GUI Page Crashes** — added null guards to QueueScheduler, KnowledgeBase, and HealthObservatory to prevent TypeError crashes on empty data
- **WebSocket Connection** — connected useWebSocket hook in App.tsx so real-time events flow to all dashboard screens
- **CC Usage Gauge Visibility** — removed responsive hiding so CC Usage gauge is always visible in topbar, even when disconnected
- **Mobile Connection Banner** — removed `hidden md:flex` so connection status banner shows on mobile viewports
- **Project Selector Z-Index** — added z-50 to dropdown container so it renders above the sidebar overlay
- **Sidebar Responsive Collapse** — sidebar auto-collapses to icon mode on viewports below 768px with hamburger toggle and backdrop overlay
- **Pipeline Theater Empty State** — shows "No pipeline data" message instead of stale replay counter when no runs exist
- **SVG Path Animation Error** — suppressed motion.path rendering when no pipeline data is displayed, eliminating console errors
- **API JSON Fallback** — added /api/* catch-all route returning JSON 404 before static file fallback, preventing HTML responses for unknown API routes
- **Notification/Settings Buttons** — added "Coming soon" tooltips and safe click handlers to prevent crashes
- **Project Fetch Response Parsing** — fixed App.tsx legacy fetch that expected raw array but API returns `{ ok, data }` envelope, so currentProject was never set and WebSocket never connected
- **Health Observatory Audit Data** — fixed double-wrapping of audit reports array that caused latestAudit to be an array instead of an object, breaking score display
- **Health Check Route Collision** — moved Express health-check endpoint from `/health` to `/api/health` so the GUI's `/health` route (Health Observatory page) is served by the SPA fallback instead of returning raw JSON

### Changed

- **Default port** — server default port changed to 3911 (config.ts, Dockerfile, docker-compose.yml)
- **Version bump** — all packages bumped to 0.99.0 (aid-server, aid-gui, docs)

## [0.9.3] — 2026-02-25

### Fixed

- **GATES → CURATOR_RESOLVE transition** (`skills/epic-orchestration.md`) — GATES state now correctly transitions to CURATOR_RESOLVE instead of skipping directly to PM_APPROVAL; restores the full state machine flow (GATES → CURATOR_RESOLVE → PM_APPROVAL) so Curator proposals are processed for every EPIC
- **Qdrant config unification** — `memory-config.yaml` is now the single source of truth for `memory.enabled`; removed duplicate flag from `project-profile.yaml`; added non-blocking Qdrant startup probe in IDLE state for early availability detection

### Added

- **CURATOR_RESOLVE auto-mode conditionals** (`skills/epic-orchestration.md`) — in FIRST AID mode, effort:S proposals get inline fixes while effort:M/L are auto-deferred to backlog with urgency tags; failed inline fixes silently defer (non-blocking)
- **Credit exhaustion detection** (`skills/epic-orchestration.md`) — PHASE_CHECK now validates agent output before evaluation; detects 5 Claude Code credit error patterns via string matching; auto-pauses with `interrupted_step_context.json` + git stash; FIRST AID resume recovers interrupted steps
- **Wiring step generation** (`skills/planner.md`) — POST_WAVE_WIRING_CHECK detects shared files across parallel wave steps and auto-generates a wiring step with context (shared_files, contributing_steps, expected_actions); new `wiring` and `wiring_context` fields in `plan.schema.json`; EXECUTING state recognizes wiring steps with specialized dispatch prompt
- **EPIC & plan archival** (`skills/epic-orchestration.md`, `commands/aid-first-aid.md`) — DONE state archives completed EPICs to `02-epics/archive/`; QUEUE_ADVANCE archives plans when all plan EPICs complete; non-blocking with `mkdir -p` safety
- **FIRST AID ASCII art animations** (`commands/aid-first-aid.md`) — 4-frame syringe-themed startup animation, depleted-syringe completion banner with CURATOR FINDINGS summary, re-injection resume banner
- **CURATOR FINDINGS section** in FIRST AID completion report — shows implemented/deferred/rejected proposal breakdown with per-EPIC table

## [0.9.2] — 2026-02-24

### Added

- **FIRST AID Autonomous Mode** — `/aid-first-aid` starts autonomous EPIC queue execution with agent-driven quality checks replacing PM approval points; `/aid-stop` disengages immediately, restoring manual mode at the current natural pause point
- **Permission Sandwich** (`skills/permission-sandwich.md`) — automatic permission backup, elevation, and restoration for autonomous execution with crash recovery and permission learning; permissions are scoped to the auto-mode session and restored unconditionally on exit
- **Auto-Mode Escalation Protocol** (`skills/auto-escalation.md`) — 16 trigger conditions with severity classification, pause/resume flow, escalation budget tracking (max 3 before mandatory PM review), and `continue-manual` handoff option
- **Auto-Mode DONE State** (`skills/auto-done-state.md`) — automatic release decisions (defer intermediate, mandatory bump on last EPIC), queue transitions, and cross-EPIC summary aggregation to `auto-mode-state.yaml`
- **FIRST AID command** (`commands/aid-first-aid.md`) — PM-facing command to activate autonomous mode: queue confirmation, permission elevation, and auto-mode-state initialization
- **Aid-Stop command** (`commands/aid-stop.md`) — immediate autonomous mode stop command; safe mid-EPIC stop after current step completes

### Changed

- **PLAN_REVIEW** (`skills/epic-orchestration.md` Section 3) — auto-mode: schema, completeness, dependency graph, and run file quality validation replace PM prompt; validation failure triggers ESCALATION; manual mode unchanged
- **PHASE_CHECK** (`skills/epic-orchestration.md` Section 5) — auto-mode: adds one "fresh approach" retry cycle after `max_review_fix_cycles` exhausted before escalating; manual mode unchanged
- **ESCALATION** (`skills/epic-orchestration.md` Section 9) — auto-mode: pauses mode, saves progress snapshot, increments escalation counter, presents extended PM options including `continue-manual`; manual mode unchanged
- **PM_APPROVAL** (`skills/epic-orchestration.md` Section 11) — auto-mode: intermediate EPICs auto-approved; last/standalone EPIC auto-approved only after 4 guardrails pass (gates, no critical issues, escalation budget, auditor trend); rule teaching suppressed in auto-mode; manual mode unchanged
- **DONE state** (`skills/epic-orchestration.md` Section 12) — auto-mode: intermediate EPIC version bump auto-deferred, last EPIC auto-bumped; queue transition loads next EPIC automatically; auto-mode exits and restores permissions when queue is exhausted; manual mode unchanged

## [0.9.1] — 2026-02-24

### Added

- **Initial Analysis Phase** (`skills/brainstorming.md`) — mandatory structured analysis before questioning; 8-rule protocol with 4 required elements (topic understanding, key dimensions, potential challenges, clarification preview); PM confirmation gate; trivial topic escape hatch
- **Release Sub-Phase** (`skills/epic-orchestration.md`) — version bump detection and execution in DONE state; reads `release-policy.yaml` for CHANGELOG pattern, version files, multi-phase deferral; supports `json_field` and `regex` update strategies, git tagging, GitHub releases
- **Release policy config** (`defaults/policies/release-policy.yaml`) — configurable versioning: CHANGELOG header pattern, version file locations, update methods, multi-phase plan detection, git tag and GitHub release controls

### Changed

- **Questioning Protocol strengthened** (`skills/brainstorming.md`) — Rule 2 upgraded from "Prefer MULTIPLE CHOICE" to "ALWAYS use MULTIPLE CHOICE with recommendation"; added Rules 10-11 for structured directional options and contrastive reasoning
- **MUST Rules expanded** (`skills/brainstorming.md`) — 3 new entries (15-17): mandatory analysis before questions, options at every decision point, reasoning for alternatives
- **Command flow updated** (`commands/aid-brainstorm.md`) — 10-step → 11-step flow; new Step 2 (Analysis) inserted between Context and Questions; all subsequent steps renumbered with cross-references updated
- **DONE state enhanced** (`commands/aid-run-epic.md`) — Release Sub-Phase integrated before branch merge; DONE action items reordered (run file update → release → merge → archive)

### Fixed

- **Example EPIC lookup type filter** (`skills/brainstorming.md`) — changed from `"example_epic"` to `"example"` to match actual frontmatter in 19 example files
- **Example EPIC lookup scan** (`skills/brainstorming.md`) — changed from flat `defaults/examples/` to recursive `defaults/examples/**/*.md` to find files in subdirectories

## [0.9.0] — 2026-02-24

### Added

- **Plan-ref injection** (`skills/epic-orchestration.md`) — dispatch template now includes `plan_ref` with Source Plan Integration protocol: 3-strategy matching cascade (keyword → heading → sequential), 3000-line truncation guard, `<plan_context>` block in agent prompts
- **Sequential ID generation** (`skills/epic-orchestration.md`) — ID Format Specification for Plans (`P{NNN}`), EPICs (`E-{NNN}-{epic_run}_{plan_step}`), and Runs (`R-{NNN}-{epic_run}_{plan_step}-{run_seq}`); Counter File protocol (`counter.yaml`); atomic increment rules
- **Evidence Incomplete detection** (`agents/auditor.md` section F.5) — `evidence_incomplete` finding type with `-3` deduction per missing mandatory file; only checks completed steps
- **Mandatory Evidence Write Checklist** (`skills/epic-orchestration.md`) — Step Evidence File Types table listing mandatory vs optional evidence files per step

### Changed

- **SESSION → RUN terminology** — renamed across 45+ files: `session` → `run`, `session-management.md` → `run-management.md`, `session-validator.md` → `run-validator.md`, 4 template files renamed; `sessions/` directory → `runs/`
- **Flat evidence structure** (`commands/aid-run-epic.md`, `skills/epic-orchestration.md`) — removed 5 empty subdirectory creation (analysis/, discovered_issues/, parallel_groups/, prompts/, reviews/); evidence now written directly to `steps/step_{N}_{role}/`
- **Budget references removed** — removed budget estimation lines from `defaults/templates/epic.md`, `defaults/templates/epic-example.md`, `skills/brainstorming.md`
- **Auditor check #12 path updated** (`agents/auditor.md`) — `evidence/discovered_issues/` → `steps/step_{N}_{role}/discovered_issues.md`
- **Analysis-merge evidence paths** (`skills/analysis-merge.md`) — `evidence/{epic_id}/{run_id}/analysis/` → `steps/step_{target}_{role}/`

## [0.8.2] — 2026-02-23

### Fixed

- **Czech-language content removed** — translated all Czech text to English in `agents/lessons-extractor.md`, `skills/session-management.md`, `skills/agent-core.md`
- **Broken skill reference in `aid-epic-queue.md`** — `skills/aid-epic-queue.md` → `skills/epic-queue.md`, `aid-epic-queue.yaml` → `epic-queue.yaml`
- **Stale `workspace/workflow/` paths** — 12 legacy path references replaced with `.aid-o/` equivalents in `skills/session-management.md`
- **Stale command prefixes** — `/run-epic` → `/aid-run-epic`, `/plan-epic` → `/aid-plan-epic` in `skills/retry-engine.md`, `skills/planner.md`, `defaults/templates/epic-example.md`
- **Version mismatches** — header/footer versions aligned to 0.8.2 in `session-management.md`, `epic-orchestration.md`, `retry-engine.md`, `planner.md`, `agent-core.md`
- **Hardcoded Slack channel ID** — replaced `C0AFP2GP459` with `YOUR_CHANNEL_ID` placeholder in `commands/aid-setup.md`
- **Plugin README version** — updated from 0.4.1 to 0.8.2

### Added

- **Untrusted-content framing** — SECURITY section in `skills/epic-orchestration.md` documenting mandatory `<untrusted_content>` tags for user-provided content in dispatch prompts (CWE-77, OWASP LLM01)
- **Advanced preset warning** — explicit risk documentation and PM confirmation requirement in `defaults/policies/permissions.yaml`

### Changed

- **CLAUDE.md structure info** — corrected command count (10 → 11) and skill count (14 → 17); removed stale `docs/` directory reference
- **CHANGELOG alignment** — root and plugin `[0.8.1]` entries made identical per CLAUDE.md policy

## [0.8.1] — 2026-02-23

### Added

- **Process Audit type** (`agents/auditor.md` section F) — 6th audit type, always runs, with 13 checks across 4 categories: F.1 EPIC Lifecycle (3 checks), F.2 Evidence Completeness (6 checks), F.3 Cross-Validation (3 checks), F.4 Stage Log Integrity (1 check); deduction-based scoring (0-100); `process: {0-100}` field added to YAML output; 15% weight in Overall score; Score Overview template updated with Process row

### Changed

- **Audit weight redistribution** (`agents/auditor.md` weight table) — Documentation 20% → 25%, Process 15% added; total always-run audit types: 3 → 4; audit type count: 5 → 6

## [0.8.0] — 2026-02-23

### Added

- **CURATOR_RESOLVE state** — new state between GATES and PM_APPROVAL in the epic-orchestration state machine; auto-evaluates Curator proposals via 3-tier algorithm (YAML rules → Qdrant history → default), dispatches fix agents, writes lessons with 3-layer dedup
- **`curator_auto_rules`** in `decision-policies.yaml` — configurable auto-resolution rules for improvement proposals
- **PM override + rule teaching** at PM_APPROVAL — PM can override rejected proposals and teach new auto-rules that persist via YAML + Qdrant
- **Improvement Pipeline analytics** — Report Type 4 in `/aid-analytics` for curator pipeline metrics
- **3-layer Lessons-Extractor dedup** — text, semantic, and Qdrant cross-project deduplication

### Changed

- **State machine**: 11 → 12 states (CURATOR_RESOLVE inserted)
- **DONE state simplified**: Curator + Lessons-Extractor moved to CURATOR_RESOLVE
- **`backlog.md`**: PROP-* IDs migrated to IMP-{NNN} with legacy alias table
- 9 files updated across agents, skills, commands, and policies

## [0.7.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.6.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.5.0] — 2026-02-22

### Added

**Phase 1 — Research + Storage + Consumption:**
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

**Phase 2 — On-Demand Research + Aging:**
- **`/aid-research` command** — on-demand research for specific frameworks/libraries; `--deep` mode for comprehensive documentation ingestion
- **Aging protocol** — TTL-based freshness weighting for all document types (90–365 days); stale/expired score multipliers (0.7/0.3); automatic exclusion after 180 days past TTL
- **Manual source addition** — conversational flow for adding documentation sources via URL or topic
- **Freshness weighting in `memory_find()`** — search results weighted by document age; stale chunks deprioritized automatically
- **Aging config in `memory-config.yaml`** — per-type TTL values, stale/expired weights, exclusion threshold

**Phase 3 — Auto-Extraction + Community Examples + Feedback:**
- **Example EPIC extraction protocol** — 7-stage `extract_example_epic()` function: eligibility check → extract → abstract → build text → PM approval → dedup → Qdrant storage; triggered in DONE state step 9b
- **`example_epic` document type** — Type 8 in memory-mcp.md with 11 metadata fields (frameworks, archetype, source_epic_id, complexity, roles, etc.); never-expire TTL; global project scope
- **Community example EPICs** — 3 curated templates in `defaults/examples/`: `langchain-rag-chatbot.md`, `fastapi-crud-service.md`, `react-dashboard.md`; placeholder paths, version ranges, standard EPIC template format
- **Example EPIC lookup in brainstorming** — Step 3 searches `defaults/examples/` + Qdrant for matching archetypes; PM offered: (A) Adapt, (B) Browse all, (C) Start fresh
- **Feedback tracking** — fire-and-forget `track_retrieval()` after `memory_find()`; tracks `times_retrieved` and `avg_retrieval_score` per framework in `knowledge-base.yaml`; deprecation signal after 180 days of zero retrievals
- **Feedback config in `memory-config.yaml`** — `feedback:` section with `track_retrieval`, `track_usefulness`, `deprecate_unused_after_days`

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"
- **DONE state in `epic-orchestration.md`** — new step 9b triggers example extraction after Curator; completion summary includes archetype when pattern is stored
- **`memory-mcp.md` document types** — expanded from 6 to 8 types (added Proposal, Example EPIC); feedback tracking hook in `memory_find()`
- **`brainstorming.md` non-blocking guarantee** — knowledge calls updated from 2 to 3 per session (Step 1 search + Step 3 knowledge + Step 3 examples); 7 new graceful degradation scenarios

## [0.4.2] — 2026-02-21

### Changed
- **`/plan-epic` step numbering** — renumbered all steps from fractional (0.5, 0.7, 2.5) to clean integers (1-9); internal cross-references updated
- **`/aid-brainstorm` step numbering** — renumbered Step 8b→9 and Step 9→10; new Step 10 presents interactive A-D handoff options (add items, all-phases EPIC, specific-phase EPIC, manual)
- **Cross-references** — updated plan-epic step references in run-epic.md (3 occurrences) and epic-orchestration.md (2 occurrences); updated aid-brainstorm.md and brainstorming.md internal refs

### Added
- **`/aid-init [path]` parameter** — documented optional path parameter in aid-init.md Usage section with examples for relative and absolute paths; updated aid-help.md entry
- **Phase selection** — plan-epic.md Step 2 now handles all-phases vs specific-phase EPIC generation when invoked from brainstorming with phase context
- **Re-opening protocol** — brainstorming.md documents how Option A (add items) works: load existing plan, display approved sections, return to Step 2, re-generate EPIC
- **Phase Selection section** — brainstorming.md EPIC Subagent Prompt Template includes phase handling for scoped EPIC generation

## [0.4.1] — 2026-02-20

### Added
- **`/aid-init` upgrade mode** — detects existing workspace, compares installed vs. plugin version, classifies files as NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED, asks PM before updating
- **Config manifest** — `.aid-o/03-config/.aid-manifest.yaml` tracks installed plugin version and md5 checksums of all config files; enables safe detection of PM customizations
- **Dynamic defaults scanning** — `/aid-init` scans `defaults/` directories instead of hardcoded file list; new files in future versions are automatically included
- **`source_plan` in plan schema** — `defaults/templates/plan.schema.json` now includes the `source_plan` field for Variant B pipeline

### Changed
- **CHANGELOG format** — standardized all entries to `**Bold Name** — description` format; root and plugin CHANGELOGs are now identical
- **CLAUDE.md release protocol** — added CHANGELOG format standard, README Roadmap update rules, and 10-step release workflow
- **`/aid-init` description** — updated in `aid-help.md` to reflect upgrade capabilities

## [0.4.0] — 2026-02-20

### Added
- **Zero Detail Loss Pipeline (Variant B)** — EPIC references source plan via `plan_ref`; all pipeline stages (plan.json, session, agent dispatch) read both EPIC and source plan; agents receive `## Source Plan — Implementation Detail` sections
- **Wave-based execution model** — planner groups steps by DAG level into waves (max 4 per wave) for parallel execution; replaces flat parallel group detection
- **Step decomposition** — layer-based splitting of monolithic steps (data → schema → API → test) to enable cross-domain parallelism; supports dev, docs, and infra decomposition types
- **Critical path analysis** — opt-in for 7+ step EPICs; computes critical path ratio, applies 5 relaxation rules (R1–R5) to shorten it; PM can reject individual relaxations at PLAN_REVIEW
- **Parallelism-first optimization** — 5-priority strategy (parallelism > wave density > session compactness > quality > efficiency); plan quality metrics in `optimization_metrics`; validation rules V-20–V-23
- **`/plan-epic` accepts Plan files** — 3-tier format detection (frontmatter → header → section fingerprinting); auto-generates EPIC from Plan using EPIC Subagent Template
- **`/aid-brainstorm` inline execution** — Step 8b offers to generate Plan JSON + Session immediately after EPIC draft; Step 9 split into 9a (standard handoff) / 9b (full pipeline handoff)
- **Wave-based session boundaries** — sessions are contiguous sequences of waves; never split by domain or inside a wave
- **Shorthand commands** — all 18 commands have `user_invocable: true` frontmatter enabling `/aid-setup` instead of `/aid-orchestrator:aid-setup`
- **Setup followup** — after "All recommended", `/aid-setup` now offers additional options (CLAUDE.md, Slack, auto-detected MCPs)
- **Selective `.aid-o/` gitignore** — plans, EPICs, and config are versioned; engine artifacts (sessions, evidence) are ignored
- **Centralized Qdrant storage** — `~/.local/share/aid-orchestrator/qdrant-data` with `--scope user` for global MCP; migration check for old paths

### Changed
- **EPIC template** — typed artifacts (`endpoint:`, `model:`, `component:`), `plan_ref` enforcement, Hints section, Scope with specific file paths
- **EPIC Subagent Template** — frontmatter instructions, plan task ID preservation in steps, Variant B zero detail loss instruction
- **Planner input validation** — REQUIRED/RECOMMENDED checks with typed artifact inference
- **PLAN_REVIEW** — rich plan summary with wave execution plan, optimization metrics, session breakdown
- **EXECUTING state** — agent dispatch enriched with source plan sections
- **Plan generation flow** — 13-step procedure with decomposition (2.2), wave assembly (6), CPA (6.1), session boundaries (11)

## [0.3.0] — 2026-02-19

### Added
- **Execution Summary block** — mandatory in all agent outputs with timing, self-assessment, and Qdrant storage
- **Per-agent metrics** — step duration, complexity self-report, bottleneck flags stored to Qdrant
- **Cost optimization skill** — 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking
- **EPIC completion summary** — 5 next-step options presented to PM at DONE state
- **Auto-archive** — multi-EPIC and multi-session counter awareness for session and EPIC files
- **Multi-session flow** — planner optimization engine for EPICs with 7+ steps
- **Diff patches** — `diff.patch` generation for every file-modifying step, saved to evidence store
- **Curator auto-invocation** — mandatory synchronous step in POST_PROCESSING
- **Chat-first `/aid-setup`** — detailed option presentation and guided configuration
- **Post-setup guidance** — `/aid-brainstorm` recommendation after onboarding
- **Playwright E2E agent** — optional parallel step, auto-added when frontend detected
- **Application type classification** — 11 types in project scanner (web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, infrastructure)
- **Auto-scaffold** — generates starter files for uninitialized projects before EPIC execution
- **Cross-project knowledge** — Qdrant with `project_name` metadata tagging for multi-project memory
- **Backlog categorization** — by type (bug, enhancement, tech-debt, security, docs) and source agent
- **`/aid-analytics`** — orchestration performance analysis command and skill
- **Permission presets** — dual-write system keeping `.claude/settings.json` + `.aid-o` policies in sync
- **Git branch integration** — one branch per EPIC session, auto-create and auto-merge
- **Pre-Output Quality Check** — in all code-producing playbooks (ruff lint/format, debug artifact removal, import verification)

### Fixed
- **DONE state** — now writes lessons to `lessons-learned.md`, updates session status to `completed`, writes commands to `command-history.md`, writes final `stage_log` entry with `result: success`
- **Gate reconciliation** — `plan.json` gates now reconciled with `gates.yaml` definitions
- **Qdrant isolation** — writes now include `project_name` metadata for cross-project isolation
- **Slack MCP** — onboarding corrected to use `@anthropic/slack-mcp` package with proper scopes

### Changed
- **Agent model assignments** — QA, Security, Docs agents use Sonnet; utility agents use Haiku
- **Dispatch prompts** — trimmed to deps-only context, EPIC summary, and playbook reference
- **`/aid-help` examples** — updated with full-stack development examples
- **Memory search** — `top_k` reduced from 5 to 3 for relevance and cost optimization
- **Git Discipline** — section added to all 9 role playbooks

## [0.2.0] — 2026-02-18

### Added
- **`/aid-brainstorm`** — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
- **Brainstorming skill** — process rules, key principles, EPIC subagent prompt template
- **MCP server onboarding** — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- **Permission presets** — Safe / Recommended / Advanced in `/aid-setup`
- **Document language** — `language.yaml` configuration with ISO 639-1, default EN
- **Parallel isolation strategy** — `dispatch-strategy.yaml` with worktrees / branches / sequential
- **Git worktree support** — creation and cleanup logic for parallel agent dispatch
- **Qdrant orchestration logging** — dispatch and completion events with graceful JSONL fallback
- **Enriched `final_report.md`** — generation from Qdrant data
- **Lessons learned** — auto-collection and storage in Qdrant at EPIC completion
- **CLAUDE.md marker merge** — `<!-- AID-O START/END -->` markers in `/aid-init`
- **Interactive examples** — `/aid-help examples` with 3 project prompts

### Changed
- **`/aid-setup`** — includes 4 new configuration steps (MCP, permissions, language, isolation)
- **`/aid-init`** — copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- **LLM cost estimates** — conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- **`examples/bookmark-manager/`** — replaced by interactive `/aid-brainstorm` prompts

## [0.1.0] — 2026-02-16

### Added
- **Initial release** — Controller + Workers architecture for Claude Code
- **17 slash commands** — `/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.
- **18 agents** — 9 role + 3 specialist + 6 utility
- **13 skills** — epic orchestration, planner, gates engine, parallel dispatch, etc.
- **11 role playbooks** — customizable per project
- **Quality gates** — auto-retry (3x) and PM escalation
- **Slack MCP integration** — with chat fallback
- **Qdrant vector memory** — optional, with file-based fallback
- **EPIC queue** — autonomous sequential execution
- **Evidence trail** — `stage_log.jsonl`, gate reports, agent outputs
