# Post-P064 → P062/E10 execution checklist

**Created:** 2026-07-23
**Purpose:** canonical delivery order after P064, through executable completion of P062/E10
**Status:** active PM checklist — refreshed **2026-08-14**. Since the 08-10
refresh: **P080 merged and released (v2.85.0)** and independently verified
(13 DONE / 3 PARTIAL / 0 NOT DONE); **P083 merged and released (v2.85.1)** —
ten backlog-verified defects, after a review chain that returned 15 CP1
blockers and then five rounds of cross-provider findings. The delivery order
below is therefore at its **last two steps: P061 close → P062/E10
re-grounding.**

**Update 2026-08-14, later the same day: P061 IS CLOSED** (Phase 6 below, and
the `## Uzavření` table in the plan itself). It closed with **one** named
deferral — **IMP-506**, `/aid-do` escalating on task size instead of risk —
accepted by the PM as risk rather than recorded as delivery. Everything else
E1–E5 is delivered and evidenced against code at v2.86.1; E6 was always
backlog. **The remaining step is the last one: re-ground P062/E10.** Its
frontmatter's "all six EPICs" precondition is a P062 defect and gets corrected
there.

**Ale POZOR — před nimi stojí věci, které tenhle checklist neznal**, protože
vznikly 11.-14. 8. Nejsou to volitelné úklidy; dvě z nich se týkají toho, jak
tenhle projekt měří a hlídá sám sebe:

| | Co | Kde |
|---|---|---|
| **A** | Merge cesta je **81 % nad rozpočtem** (18 min proti 10) a **jedna sada je 47 % celého portfolia** (199 min). Noční běh proto tři noci nedoběhl. | `HANDOFF-2026-08-14.md`, okno A — IMP-505, IMP-501 |
| **B** | Riziko plánu se pozná **z prózy, ne z dotčených souborů** (P080 „srovnej nápovědu" se trefil 13×, první výskyt je odkaz v hlavičce). Spadne jeden test → pouští se celá sada. Nastavení se čte z jiného stromu, než ve kterém běží kód — kouslo to dvakrát za den. | `HANDOFF-2026-08-14.md`, okno B — IMP-497/498/499 |
| **C** | Tento checklist + entry-point dokument = podklady pro **P061 → P062/E10** | tento soubor a `2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` |

**Předchozí znění statusu (2026-08-10):** P064, Phase 1,
P068, P066, P069, P071, P072, P073, P074, P075, **P076 (v2.80.0)**,
**P079 (v2.81.0)** and **P078 (v2.82.0)** are implemented and released.
**The test-acceleration campaign is CANCELLED**: the PM cancelled the entire
test-parallelism line on 2026-08-09 (P077 allocated-then-cancelled, IMP-469
rejected) and P078 removed the machinery. The delivery order that replaces it
is: **green `bats_all` (IMP-494) → ecosystem test-tier standard → AID tier
pilot → entry-point UX (now P080) → P061 close → P062/E10 re-grounding.**
**Sources:** P061, P062, P064, P066 interim, P068, P072–P075, IMP-258 and
IMP-261–281, IMP-464–468,
`2026-08-02-IMP-TEST-AUDIT-DECISION-QUALITY-AND-DIAGNOSTICS.md`,
`2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md`

## Current checkpoint

| Item | State |
|---|---|
| P064 | **DONE** — both EPICs merged |
| P064 delivery baseline | `2a1ca60` |
| Checklist handoff on `main` | `e1341be` |
| P064 local release | `v2.61.0` at `193fd4a` |
| **Phase 1 (1A–1D)** | **DONE** — see per-item progress log; 1B + 1C completed 2026-07-24 |
| **Fail-closed hardening (PM review 2026-07-24)** | **DONE** — IMP-263/269/270/262 made genuinely fail-closed (`cfdaed4`, `d1bf7f0`, `8e94dd4`, `6751157`); one independent adversarial review found no residual bypass |
| **P068** | **DONE** — released v2.63.0; v2.63.1 repaired CI; v2.63.2 records final backlog/checklist repair |
| P068 delivery proof | P077 clean dogfood reached `release_ready=true` → merge → durable receipt → `CLOSED`; its isolated history is archived on `archive/P068-dogfood-P067-P077-20260727` |
| **Current pushed version** | `v2.82.0` at `ae6ac60`; `main` head `704e94a` on `origin/main` |
| **P076** | **DONE** — auto mode owns its waits; released v2.80.0. Merged by direct git merge outside the FSM (plan-final gate could not complete; gap recorded as IMP-490) |
| **P079** | **DONE** — twelve fixes found by the first live P076 run; released v2.81.0 |
| **P078** | **DONE** — test-parallelism machinery removed; released v2.82.0. Portfolio 170→150 bats, 48→41 sh |
| **P077** | **CANCELLED** — standalone parallel runner; number burned, never planned |
| **P080** | **WRITTEN, not implemented** — entry-point UX (renumbered from P078 after an ID collision with the removal plan); lint + readiness + CP1 all pass |
| P071 | **DONE** — released in the v2.68.0 line |
| P072 | **IMPLEMENTATION DONE** — decision-quality audit and subsequent report/collector hardening released through v2.79.0; the portfolio-wide acceleration campaign remains unrun and no whole-suite speedup may yet be claimed |
| P073 | **DONE** — all three EPICs merged; released in v2.72.0 |
| P074 | **DONE** — per-plan worktrees and resumable generation transaction merged; released in v2.75.0 after integration with the concurrent release line |
| P075 | **DONE in the repository currently visible here** — `3f284c5` merged the epic-start/generation wiring and branch restoration; released as v2.77.0. If another window still reports P075 active, reconcile it before allowing further writes: it is operating from stale state or doing a distinct, not-yet-recorded continuation. |
| Local/remote topology | local `main` is at `46a026a`, one Docker-layout commit ahead but nine commits behind `origin/main`; reconcile this divergence before the next commit/push instead of developing further directly on the stale checkout |
| Git identity | corrected to `Marek Stancl <stancl.marek@gmail.com>` for all new commits; 38 pre-fix commits keep `Test <test@test.local>` — remedy is a documented push-time decision (`git-identity-remedy-proposal.md`), history NOT rewritten |
| E-064-2_2 targeted boundary suite | 241/241 at reviewed HEAD, hash-bound receipt |
| Accepted waivers | `bats_all` quarantine, `plan_diff` quarantine, CP3 revision disagreement |
| C3 | real plan AC source proven; final result `unverifiable`, zero findings, targeted receipt not consumable by the sealed manifest |
| IMP-266 | **RESOLVED — PM ratified Option B (2026-07-24)**: `merged_to_plan` stays terminal; wrong entries corrected via the documented recovery ceremony (`IMP-266-merged-to-plan-recovery-CEREMONY.md`), doc-only, no code edge; Option A deferred to P068+ |
| Next work | Close Phase 5 operationally: run one frozen-SHA sequential-vs-scheduled campaign through the installed plugin, prove identical membership/verdicts, no duplicate execution and real before/after wall-clock, then take an explicit PM quarantine decision. After that implement the separate Help/Init/Setup/Release UX stream, finish P061 E4/E5 and re-ground P062/E10. |

The E-064-2_2 Curator used provisional labels `IMP-270…IMP-279` from a task
branch that did not contain the canonical backlog update. Canonical `IMP-270`
is already the gate-scoped waiver. Do not copy those provisional numbers into
the project backlog; deduplicate and renumber any surviving Curator proposals
from `IMP-271` onward.

## Outcome

Reach E10 only after AID has:

1. a reliable plan-level release cadence;
2. scoped, auditable waivers instead of broad FSM bypasses;
3. controller-owned long-running jobs and replay-safe step advancement;
4. an audited, isolated and materially shorter test portfolio;
5. completed risk-based profiles; and
6. a re-grounded E10 plan whose preconditions match the current repository.

## Current continuation — authoritative order after P078 (2026-08-10)

This section supersedes every earlier continuation section, including the
2026-08-08 one below it, and all wording that calls P069, P071–P076, P078 or
P079 pending. **It also retires the acceleration campaign as a delivery gate.**

**Order in force:**

0. [x] **IMP-494 — `gate:bats_all` is green.** Both red suites fixed
   2026-08-10 (phantom tests from heredoc'd fixtures; a profiler suite that
   decided on the PM's workspace catalog).
0b. [x] **Ecosystem test-tier standard published** 2026-08-10
   (`/ecosystem/specs/test-standard`), Codex-reviewed, amended 2026-08-11 with
   the pilot's finding that a tier budget must be verified by one real run,
   not by summing its suites.
0c. [~] **P081 AID tier pilot IMPLEMENTED** 2026-08-11 (v2.83.0, worktree
   `.claude/worktrees/p081-test-tier-pilot`, head `4ec1946`): 202 suites
   measured and tagged, **merge path 24 542 s → 793 s (6 h 49 min → 13 min)**,
   25/25 targeted suites green. Awaiting whole-diff review → merge → tag →
   release → cache refresh. `CLAUDE.md`'s `## Conventions` block was inserted
   by hand (the file is gitignored, so no merge delivers it).
0d. [x] **Backlog audited entry by entry** 2026-08-11 against v2.82.0: 45 of
   101 entries were already done and are now closed with their evidence, 3 are
   dead, ~30 remain (half consciously parked). The surviving live holes are
   planned as **P082** (written, lint + readiness PASS, CP1 pending).
1. [~] **SUPERSEDED — IMP-494 is closed; kept for provenance:** One of its
   two red suites is fixed (`test-aid-test-content-scan.bats`, phantom tests
   from heredoc'd fixtures); the other (`test-aid-test-audit-profile.bats`)
   depends on the PM's gitignored workspace catalog and needs either a mapping
   confirmation or a fixture redesign — see IMP-494's diagnosis. A permanently
   red required gate is why two orphaned suites reached a merge request.
2. [ ] **Ecosystem test-tier standard** (`/ecosystem/specs/test-standard`,
   drafted 2026-08-10, Codex-reviewed) — PM approval, then publish.
3. [ ] **AID tier pilot** — T0/T1/T2 split, nightly cron for the full suite,
   naming + tier migration, selector honesty check, budget-in/reaper-out.
4. [ ] **P080 entry-point UX** — after the pilot, because the pilot moves the
   test paths P080 documents.
5. [ ] Close P061; then re-ground P062/E10.

*(Historical 2026-08-08 list retained below for provenance.)*

1. [x] Release P071 and integrate its parallel Bats lane and gate fixes.
2. [x] Implement the P066 decision-quality follow-up as P072, including the
   P070 discovery gap: Bats, standalone shell, declared gates, package scripts
   and CI-only suites are inventory inputs rather than invisible work.
3. [x] Complete P073 process loosening/recovery and P074 per-plan concurrency
   plus resumable generation; land the P075 epic-start/restore integration fix.
4. [ ] **Reconcile local `main` with `origin/main` first.** Preserve local
   Docker commit `46a026a`, but do not build or release from a branch nine
   remote commits behind v2.79.0.
5. [ ] **Run the one missing acceleration campaign on one frozen SHA.** Use the
   installed plugin path, approved catalog/mapping and real gate runner. Record
   a sequential baseline and scheduled run with identical membership and
   verdicts, terminal receipts, execution-ledger proof that no unit ran twice,
   and measured before/after wall-clock. Do not substitute another schema or
   fixture review for this run.
6. [ ] **Take the explicit PM quarantine decision from that evidence.** Remove
   or narrow `bats_all`/`plan_diff` quarantine only for gates whose replacement
   coverage and runtime are proven; otherwise retain the truthful waived state
   with a named follow-up. This is the point where the project may finally
   claim a real acceleration — not at component release time.
7. [ ] **Then implement the separate Help/Init/Setup/Release maintenance
   stream** from
   `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md`,
   including the release-liveness items routed through
   `docs/plans/2026-08-02-IMP-POST-P068-INTEGRITY-LIVENESS-HARDENING.md`.
8. [ ] Finish P061 E4/E5, reconcile superseded work, record E6 as backlog and
   close P061 durably.
9. [ ] Re-ground P062/E10 against the released P061/P068/P069/P072/P074
   contracts; regenerate its EPICs and execute E10 only from that reviewed
   plan.

**Immediate next action:** reconcile `main`, then run and adjudicate the single
measured acceleration campaign. Do not start another test-framework plan before
that result; the missing deliverable is operational proof, not another layer.

This order is deliberate:

```text
P064 close
  → critical maintenance
  → P068 plan-final cutover
  → EPIC-generation integrity maintenance
  → P066/P069/P071/P072 test audit + scheduler + decision quality
  → P073/P074/P075 liveness, concurrency and generation wiring
  → measured acceleration campaign + quarantine decision
  → Help/Init/Setup/Release entry-point UX
  → P061 E4/E5 completion and P061 close
  → P062 re-grounding/preflight
  → P062 E10 execution
```

## Temporary policy currently in force

- [ ] Keep `bats_all` quarantined in the AID self-host
  `.aid-o/config/execution.yaml`.
- [ ] Do not invoke `bats_all` directly or through `full`/`release`.
- [ ] Treat its quarantine result as `waived`/`profile_excluded`, never `pass`.
- [ ] Treat the current `plan_diff` timeout as unresolved/waived, never `pass`.
- [ ] Use affected targeted suites with terminal, HEAD-bound evidence.
- [ ] Never run two gate/test commands concurrently against the same mutable
  repository unless a scheduler has proved them isolated.
- [ ] Preserve the E-064-2_2 waiver, `exit 143` cancellations and
  `plan_diff exit 124` as evidence. Do not rewrite them green.

The local quarantine is temporary operating configuration, not a shipped AID
feature. It remains until the P066 exit criteria below are met and the PM
explicitly removes it.

## Phase 0 — close P064 honestly

- [x] Finish the single targeted
  `test-aid-plan-release-boundary.bats` run on the reviewed HEAD.
- [x] Store its terminal exit code, test counts, command fingerprint and HEAD.
- [x] Perform at most one C3 recheck focused on the corrected AC evidence.
- [x] Do not open another broad exploratory review loop from that recheck.
- [x] Run Curator, Auditor and CP4 against the same frozen revision.
- [x] Close and merge E-064-2_2, then close P064.
- [x] Create the local `v2.61.0` release/tag.
- [ ] Push `main` and the local releases (`v2.61.0`, `v2.62.0`) only when
  explicitly authorized.
- [x] Installed plugin cache refreshed and resolves the current local release
  `v2.62.0` (scripts-tree recorded in the checkpoint); re-confirm after any push.
- [x] Preserve all quarantine/waiver evidence in the delivery report.

**GO to Phase 1:** P064 is merged and closed; main and the plugin cache resolve
the same released plugin code.

## Phase 1 — critical manual maintenance before P068

These changes repair the mechanisms that would otherwise orchestrate their
own broken implementation. Implement and verify them manually outside
`/aid-run`, in small independent commits. Do not combine them into one large
plan.

### 1A — gate-scoped waiver (file as IMP-270) — DONE `3f08c80`

- [x] Replace broad transition `--force` for gate exceptions with a
  gate-scoped authorization. (`aid-gate-waiver.sh` issue/check/consume.)
- [x] Bind authorization to project, plan/EPIC, run, exact HEAD, gate ID,
  command fingerprint, authorizer, reason and expiry/single use.
- [x] A waived required gate is reported as `waived`, never `pass`. (Two teeth:
  run-gates stamps `waived` + top-level `waived_gates[]`; FSM re-validates each
  waived row at read time and fails closed on a bare `waived`.)
- [x] Every unrelated gate and FSM precondition remains enforced. (`--force`
  unchanged and still the only path for non-gate preconditions.)
- [x] Missing, stale, forged or mismatched authorization fails immediately.
- [x] Add negative tests proving a `bats_all` waiver cannot waive
  `plan_diff`, CP3 freshness, another HEAD or another run. (22 waiver cases;
  security review pass, F1 durable-consume folded in.)

### 1B — AUTO liveness and replay safety

- [x] **IMP-262:** controller-owned job supervisor with durable terminal
  receipts, process-group ownership, resume/collect and no orphan watchers. (`a02e866` — opt-in `aid-job.sh`.)
- [x] **IMP-263:** idempotent `increment-step`, bound to the exact step,
  plan-step hash, reviewed commit and idempotency token. (`c3d493c`.)
- [x] Prove that duplicate invocation advances once and that a renamed
  previous-step verifier cannot complete the next step. (`c3d493c` — double-advance + copied-file tests.)

### 1C — audit and lineage integrity

- [x] **IMP-269:** C3 records and enforces
  `ac_source: plan|final_report_fallback|stub`; required AC lenses accept only
  the explicit plan source. (`00ef981`; F1 laundering vector closed.)
- [x] Extend **IMP-269** to bind test evidence as well as AC evidence:
  accept a revision-bound, command-fingerprinted targeted-run receipt in the
  sealed manifest, or seal a narrowly allow-listed recheck command. A
  quarantined gate must not force C3 to `unverifiable` merely because valid
  targeted evidence has no manifest channel. (`00ef981` — `AID_TEST_RECEIPT_FILE` sealed into `evidence_hashes`.)
- [x] Preserve `unverifiable` as distinct from `fail`; C3 must not be promoted
  to blocking while the quarantine/targeted-evidence contract is unresolved. (`00ef981` — enforcement stays `observe`.)
- [x] **IMP-264:** compute evidence freshness at read time; stop trusting a
  persisted `head_is_current: true`. (`0263276` — pm-brief was the sole read-time leak.)
- [x] **IMP-265:** lineage omission defaults to `unproven`; healthy repair is
  idempotent and preserves valid attestations. (`45ae9aa`.)
- [x] **IMP-267:** attestation re-derives merge/base ancestry from Git. (`45ae9aa` — fails closed when unprovable.)
- [x] **IMP-258:** repair propagates per-write failures instead of swallowing
  them through `|| true`. (`45ae9aa`.)
- [x] Decide **IMP-266:** audited reopen from an incorrect
  `merged_to_plan`, or a documented deliberately terminal recovery ceremony. (`e40f9ca` decision brief → **PM ratified Option B on 2026-07-24**: keep `merged_to_plan` terminal + documented recovery ceremony in `IMP-266-merged-to-plan-recovery-CEREMONY.md`; doc-only, no code edge; Option A deferred to P068+.)

### 1D — P064 dormant-path blockers owed before P068

These were non-blocking for P064 because its lifecycle manifest remained
`legacy_epic_release_mode`. They become live the moment P068 enables the new
path.

- [x] Make `plan-start --mode` explicit. Omission must not silently default
  to `plan_branch`; alternatively refuse `plan_branch` until
  `plan-finalize` and `plan-merge-to-main` are installed. (IMP-271 `c82be23`;
  the self-asserted `--allow-incomplete-plan-final` escape hatch was then found
  bypassable in AUTO and **removed** by Codex-adjudicated A1, `23fe72e` — the
  refusal is now hard, lifted only by the mechanical P068-subcommand probe.)
- [x] Constrain queue `merge_target` semantically, in both contract twins, to
  the owning `plan/Pxxx` branch or resolved target branch. A hand-edited
  dependency branch must not self-satisfy ancestry. (IMP-272 `e544715`; the
  owning plan was still read from the hand-editable `plan_id` field — a HIGH
  self-authorization bypass — **hardened** in `a18b183` to derive the plan from
  the epic id and fail-closed cross-check `plan_id`.)
- [x] Route `cmd_init` through the same fail-closed committed-manifest mode
  authority as `done-advance`. Missing `yq`, malformed manifests and unknown
  modes must resolve to `unresolved`, never silently to legacy. (IMP-273 `48270af`.)
- [x] Replace the second `grep -oP` in `aid-queue-add.sh` (`f60efab`).
- [x] Widen the regression guard from one `$FSM` file to every relevant
  `plugins/aid-orchestrator/scripts/**` shell source so the same portability
  defect cannot be reintroduced elsewhere. (IMP-274 `214a9fc` — repo-wide scan
  with a per-file allowlist of the seven pre-existing instances and a detector
  self-test.)
- [x] Correct the new enforcement rows that claim `active` behavior whose
  P068 reader does not exist yet; writer-only controls remain
  `planned`/`unmapped`. (IMP-274 `214a9fc` — `plan_final_required_gates_record`
  demoted to `planned`/`unmapped`.)

**Verification policy:** targeted red-green suites only. The quarantined
`bats_all` is not a required implementation check for this maintenance.

**GO to Phase 2:** scoped waivers, job ownership, replay-safe steps and the
AC/lineage fixes are released and present in the plugin cache.

## Phase 2 — re-ground P068 before execution — DONE

P068 is already drafted and EPIC files exist, but it was authored before P064
finished. Do not execute the existing generated tasks without this pass.

- [x] Verify every P064 interface and artifact against post-merge main.
- [x] Update stale paths, commands, schemas, counts, version assumptions and
  acceptance commands.
- [x] Re-run plan lint, dependency/artifact ownership checks and bounded C0.
- [x] Regenerate P068 EPIC files only after the reviewed plan is final.
- [x] Carry every unresolved P064 handoff finding explicitly.
- [x] Add the following mandatory **full-suite-last** cadence:
  1. targeted checks and exploratory reviews run first;
  2. fixes converge before candidate freeze;
  3. one frozen candidate receives the plan-final expensive gates;
  4. a production fix invalidates the candidate and may justify one rerun;
  5. further reruns require a gate-scoped PM/Codex decision;
  6. no concurrent gates against one mutable worktree.
- [x] While quarantine is active, plan-final evidence must display the waived
  `bats_all`/`plan_diff` status and use approved targeted evidence. It must not
  claim a clean full-suite result.

**GO to Phase 3:** P068 is re-grounded against released P064 and its generated
EPICs match the reviewed plan byte-for-byte.

## Phase 3 — deliver P068 — DONE

- [x] Deliver candidate synchronization and immutable freeze.
- [x] Deliver one plan-final gate/review stack per plan.
- [x] Deliver plan-mode C4 and exact-SHA PM/Codex authorization.
- [x] Deliver compare-and-swap merge, one tag/push and durable close receipt.
- [x] Complete cutover and remove obsolete per-EPIC release instructions.
- [x] Dogfood the complete multi-EPIC path on tracked changes.
- [x] Demonstrate that intermediate EPICs do not run the release stack.
- [x] Demonstrate that a plan normally pays the expensive release boundary
  once, not once per EPIC.

**GO to Phase 4:** `plan_branch` is the proven default for new plans and the
legacy path remains explicitly available for already in-flight plans.

## Phase 4 — EPIC-generation integrity maintenance

This is a manual maintenance package on an isolated branch, not an `/aid-run`
plan. It removes a false circular precondition which currently blocks ordinary
plan generation: C0/CP1 request a dependency graph that is only produced after
EPIC generation.

- [x] Build one shared, fail-closed parser for the source plan's dependency
  syntax; accept only documented one-line and multi-line forms. (`930fcd7`)
- [x] Before generation, produce a hash-bound, plan-global provisional graph
  from the plan and reject missing steps, self dependencies, duplicates,
  forbidden forward dependencies, cycles and invalid phase/EPIC allocation.
  (`930fcd7`)
- [x] Seal that graph into the C0 input, so C0 reviews real graph evidence
  before EPIC files exist. The whole-plan source graph lives at
  `generation/provisional-graph.json`; it is deliberately separate from the
  later per-EPIC C0 contract graph at `c0/plan-graph.json`. (`1bbf119`)
- [x] Make the generator consume the same parser; reject ambiguous dependency
  syntax rather than silently producing an empty edge set. (`930fcd7`)
- [x] Preserve every declared Files path; a comma is not a valid path separator.
  (`930fcd7`; `+` is the only multi-path separator.)
- [x] Split auto-pipeline into two truthful stages: generate and validate the
  complete EPIC package first; only then initialise/queue any EPIC. Do not add
  a receipt guard to the current per-phase init loop — that would recreate the
  producer-before-consumer deadlock.
- [x] After all EPICs are generated, create a plan-global final graph, compare
  it to the provisional graph, and write a hash-bound receipt owned by the
  generation stage.
- [x] Require that receipt before strict/high-risk first-EPIC init; preserve
  an explicit legacy path rather than retroactively blocking in-flight plans.
- [x] Add red-green reproductions for P074-style pre-generation review,
  multi-line dependencies, ambiguity, graph disagreement and multi-path Files.
  (Source-plan cases and multi-path coverage in `930fcd7`; final-graph
  disagreement, complete-package receipt and post-receipt FSM/queue E2E are
  covered by `test-generation-finalize.sh`.)

**Explicitly out of this package:** CP2 orchestration and generic delivery-gate
policy redesign. Those are separate auto/gate work, not prerequisites for
making ordinary EPIC generation truthful.

**GO to Phase 5:** a valid plan can generate EPICs without a fake graph or PM
override, while an invalid or later-divergent graph fails closed.

### Phase 4.5 — later process and concurrency hardening — DONE

- [x] **P073:** five-session review budgets, fail-loud release probes,
  supported force/recovery paths and review-equivalent ancillary writes;
  released in v2.72.0.
- [x] **P074:** per-plan execution worktrees, locked identifiers, multi-run
  accounting and resumable all-phase generation transaction; released in the
  v2.75.0 line.
- [x] **P075:** connect the previously dormant `epic-start` producer to real
  generation and restore every checkout/worktree moved by init, including
  multi-phase runs; merged at `3f284c5`, released as v2.77.0.

These plans make parallel project work and generation survivable. They do not
replace the Phase-5 measurement campaign and do not prove that the test
portfolio is faster.

## Phase 5 — P066 test portfolio audit, scheduler and remediation

### 5A — P066 audit capability — DONE

P066's audit-only capability is released on `main` through v2.66.2. It
inventories runner units, performs bounded measurement/dispatch, records
receipts, and can produce a remediation brief. Historical checklist entries
below explain the original delivery intent; they are not evidence that P066 is
still merely an interim specification.

### 5B — P069 scheduler/gate integration — DONE

P069 connects approved, evidence-backed catalog mappings to the real gate
runner and consumer `/aid-init` configuration path. It owns scheduler
execution, not audit diagnosis, and is released in the v2.67.0 line.

### 5C — decision-quality audit follow-up — IMPLEMENTED; CAMPAIGN OPEN

Canonical plan:
`docs/plans/2026-08-02-IMP-TEST-AUDIT-DECISION-QUALITY-AND-DIAGNOSTICS.md`.

- [x] Re-ground the narrow P066↔P069 catalog contract after P069 is merged or
  frozen.
- [x] Make a materially unresolved audit return `audit_status: incomplete`,
  not a remediation-ready portfolio-wide `unknown`.
- [x] Add bounded root-cause profiling for high-cost run units, source-aware
  resource maps and disposable-clone parallel pilots.
- [x] Produce a strict decision artifact and a human-first output: fix/merge/
  remove/split, proposed parallel lanes, serial exceptions, current time and
  measured/estimated/unknown future impact.
- [x] Keep all scheduler activation and catalog approval in P069's explicit
  authority boundary.
- [x] Extend discovery and reporting across runner types and CI/wrapper
  reachability; subsequent hardening is released through v2.79.0.
- [~] **CANCELLED 2026-08-09.** The frozen-SHA sequential-vs-scheduled
  acceleration campaign will never run: the PM cancelled the whole
  test-parallelism line after the measured economics came in — 3–6 % speedup
  (5–9 min on a 212-min portfolio), ~15 h of qualification compute per HEAD,
  and rollout evidence invalidated by every commit. P078 removed the
  machinery (v2.82.0). The replacement for "make the suite faster" is
  **"take the suite off the merge path"** — the test-tier standard.

### 5D — entry-point UX and human handoffs — PLAN WRITTEN (P080), queued behind the tier pilot

Canonical requirements:
`docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md`.
Executable plan: `.aid-o/plans/P080-entrypoint-ux-help-handoffs.md` (written
2026-08-09 as P078, **renumbered to P080** on 2026-08-10 after an ID collision
with the parallelism-removal plan; lint, generation-readiness and CP1 all
pass; EPICs deliberately not generated).

- [ ] Ground every public command and every init/setup write authority.
- [ ] Make `/aid-help` mechanically complete, while keeping its prose concise
  and hand-written.
- [ ] Preserve separate init/bootstrap and setup/configure authorities;
  unify the user journey rather than merging commands blindly.
- [ ] Render structured outcomes in human-first, user-language form without
  weakening their underlying gate/waiver/lifecycle truth.
- [ ] Complete IMP-261's grounded configuration/precedence matrix as input to
  a separate project-policy implementation plan; do not hide a new global
  settings schema inside the UX rewrite.

The historical P066 roadmap tasks below are retained as context. The current
order is **IMP-494 green gate → tier standard → AID tier pilot → 5D/P080 →
close P061 → re-ground P062/E10**. The 5C campaign is cancelled, not pending.

### Verified standalone release hygiene — before the next release automation use

- [ ] **IMP-282:** make optional version-source probes in `aid-release.sh`
  safe under `set -euo pipefail`, with explicit diagnostics when no source is
  usable. This is a small standalone release-liveness fix, not P066/P069/UX
  scope; it is tracked in `BACKLOG.md` and must not be lost in a broad plan.

- [ ] **Post-P068 integrity/liveness hardening:** implement IMP-282 together
  with the verified dogfood common-dir protection (IMP-280) and CP3 prefilter
  evidence/range fixes, from
  `docs/plans/2026-08-02-IMP-POST-P068-INTEGRITY-LIVENESS-HARDENING.md`. Keep WAN-only
  `docs_updated` report IMP-281 out until it has a local reproduction.

- [x] Ground the interim brief against current main and produce a reviewable
  roadmap: `docs/plans/P066-test-portfolio-audit-scheduler-remediation.md`
  (2026-07-28). Confirms/corrects the interim brief's claims with file:line
  evidence (test entry point inventory, `bats_all`/`plan_diff` root causes,
  P061/P063 reuse surfaces, `/aid-init` distribution mechanism), fixes the
  EPIC decomposition and quarantine exit criteria, and lists open PM
  decisions (O1-O5: incident root cause, the unverified "34 min" figure, the
  20-min p95 target, catalog/selector ownership, new-agent-card direction).
  Independently adversarially reviewed before hand-off (8 findings, all
  corrected: sample-count/line-count fixes, the `plan_diff`-vs-`bats_all`
  quarantine-mechanism distinction, a CI-delegated-jobs count fix, a config-
  key-rename flag). No code changed, no `/aid-run`, no EPICs, no quarantine
  policy change — this is prerequisite grounding only.
- [ ] PM reviews the roadmap and O1-O5; on approval, convert it via
  `/aid-plan write` into a grounded executable plan.
- [ ] Explicitly include both `bats_all` and `plan_diff` as primary incidents.
- [ ] Inventory every configured test entry point and stable test identity.
- [ ] Prove which tests protect real behavior and which are duplicate, stale,
  flaky, mock-only or unnecessarily expensive.
- [ ] Identify live-repository, Git, `.aid-o`, port, Docker, database,
  environment and filesystem interference.
- [ ] Stream per-suite output while running; never retain the only diagnostic
  in memory until the aggregate ends.
- [ ] Give every run controller ownership, a process group, a deadline,
  separate logs and a terminal receipt.
- [ ] Build deterministic, resource-aware batches. Unknown isolation remains
  sequential.
- [ ] Compare sequential and parallel membership and verdicts before
  promotion.
- [ ] Generate and approve a separate AID self-host remediation plan.
- [ ] Execute that remediation plan: repair isolation/performance, remove or
  quarantine tests only with explicit PM approval.

### Quarantine exit criteria

Do not restore the real `bats_all` command merely because one run happens to
pass.

- [ ] No configured test entry point is missing from the catalog.
- [ ] No overlapping runner can mutate the same live state without a lock or
  isolated workspace.
- [ ] A failure identifies the exact suite/test before the aggregate exits.
- [ ] Sequential and scheduled runs have identical membership and verdicts
  across the calibrated sample.
- [ ] Cancellation/restart cannot orphan work or duplicate a run.
- [ ] `plan_diff` no longer launches an opaque nested aggregate against live
  mutable state.
- [ ] A PM-approved measured runtime target is met. Proposed target for the
  P066 writer to validate: AID self-host full-suite p95 at or below 20 minutes
  on the reference host, without reduced coverage.
- [ ] The restored command, timeout, retry and concurrency settings are based
  on measured post-remediation data.
- [ ] PM explicitly removes the quarantine.

**Phase 5.5 record:** P069 has a released/frozen contract before any later
test-scheduler promotion. The durable-evidence package itself was delivered in
v2.66.0; its still-open operational hardening is tracked separately above so
it is not conflated with scheduler work.

## Phase 5.5 — durable plan-final evidence and review integrity — DONE in v2.66.0

P078 exposed a plan-boundary gap: review correctly leaves the frozen candidate
unchanged, but its runtime evidence is not durable outside the active checkout.
It was delivered as standalone AID maintenance in v2.66.0 (`d1fada8`), before
relying on plan-boundary closure for subsequent major plans:
`docs/plans/IMP-PLAN-FINAL-EVIDENCE-DURABILITY-AND-REVIEW-INTEGRITY.md`.

- [x] Seal plan-final outputs into an immutable, public-safe, candidate- and
  run-bound Git sidecar receipt without moving candidate or target.
- [x] Require and verify that receipt at plan merge and close; recover runtime
  pointers after a clean/reclone/worktree loss.
- [x] Correct C3's missing plan-diff input (IMP-464).
- [x] Generate and validate protocol-v2 specialist envelopes (IMP-465).
- [x] Make plan-final freshness run/receipt scoped, not a per-report Head
  annotation loop (IMP-467).
- [x] Add the exact, schema-bound Curator adjudication path required for a
  validated false-positive disposition to affect lifecycle status (IMP-468).
- [x] Make raw-Git/evidence-loss guidance consistent everywhere (IMP-466),
  treating warnings/hooks as defence in depth rather than proof.
- [ ] Add the still-live dogfood ref-isolation preflight (IMP-280): a dogfood
  must refuse a source checkout with the same Git common-dir unless it uses an
  explicit safe namespace/separate clone.
- [ ] Remove or make CP3-specific the live `aid-prefilter.sh classify
  --checkpoint cp3` path: it still writes the generic
  `verifier-output-step-N.md` target and can overwrite CP2 evidence.
- [ ] Remove CP3's live guessed-range fallback in that same prefilter path:
  missing canonical `base_commit` must fail loud/unverifiable, not review
  `merge-base`/`HEAD~5` as an approximation.

**GO to Phase 6:** the P066 quarantine is removed by a reviewed change, and
plan-final evidence is durable, recoverable and required for a close.

## Phase 6 — finish and close P061 — CLOSED 2026-08-14

P061 determines **which** tests run. P068 determines **when** expensive
validation runs. P066 makes the remaining run efficient.

**Outcome: closed with one named deferral, by explicit PM decision.** The
re-grounding pass found less open than this checklist assumed: E4 had been
delivered through the `/aid-init` execution-yaml composer, and E5's D6 had been
delivered through the OTHER of the two routes the plan permitted — plan-final
resolves `max(plan_final_required_profile, release)` and runs that profile
(`aid-plan-fsm.sh:4530`), so the `release` profile is not a dead YAML line. The
one genuinely missing piece is D5. Full per-EPIC evidence table: the
`## Uzavření` section at the top of
`.aid-o/plans/P061-gate-profiles-test-cost-reduction.md`.

- [x] Re-ground P061 E4/E5 against the P064/P068/P066 implementation. Checked
  against code at v2.86.1, not against the plan's prose.
- [x] E4: project/consumer distribution of gate profiles and safe `/aid-init`
  upgrade behavior — delivered (`lib/aid-init-execution-yaml.sh`); D3 consumer
  isolation still holds (no self-host gate name anywhere under `defaults/`).
- [~] E5: **D6 delivered** (plan-final release invocation, above);
  **D5 NOT delivered** — `/aid-do` escalates on task SIZE, never calling the
  shared risk resolver, so risk enforcement is bypassable by choosing the
  command. Filed as **IMP-506**, accepted by the PM as risk, not as delivery.
- [x] Reconcile anything superseded by P064/P068 rather than implementing it
  twice. D6's release invocation is exactly this case: P068's plan-final
  boundary absorbed it, so building the `aid-release.sh` variant too would have
  been the second implementation.
- [x] Resolve the denominator explicitly: **E1–E5 required, E6 backlog**, which
  is what D1 always said. P062's frontmatter claim of "all six EPICs" is a P062
  defect and is corrected during its re-grounding — never satisfied by inflated
  merge counts. Recorded in the plan's frontmatter (`closure_denominator`).
  There is no durable lifecycle manifest for P061: it predates the plan-branch
  lifecycle and has no `.aid-o/work/plan-state/P061/`, so the plan document and
  this checklist ARE its closure evidence. Do not invent a manifest to make the
  bookkeeping look uniform.
- [x] Close P061 only after every required EPIC is delivered and accepted —
  satisfied in the form the PM chose: E1–E4 delivered, E5 accepted at half with
  its remainder named and filed.

**GO to Phase 7:** P061 is durably closed and consumer projects can use the
same risk-based profiles instead of AID self-host-only configuration.

## Phase 7 — re-ground P062/E10

The current P062 document is stale and must not be executed as written:

- it says P061 must merge all six EPICs, while the current P061 design treats
  E6 as non-blocking backlog;
- it reports only P061 E1 as merged;
- it targets version 2.56.0 although the repository is already beyond 2.60;
- it predates the P064/P068 cadence, P066 scheduler and current C3 evidence
  contract.

Required work:

- [ ] Re-read every P062 citation, path, command and schema against current
  main.
- [ ] Resolve and document the P061 denominator mismatch; never satisfy it by
  fake merge counts.
- [ ] Replace stale version numbers with a release-time version policy.
- [ ] Make speed calibration consume P061 profile events, P063 baselines,
  P066 scheduling context and P068 plan-boundary cadence.
- [ ] Verify non-zero real C3 hook evidence from P065-era runs.
- [ ] Resolve IMP-179 instruction/cache freshness prerequisite.
- [ ] Resolve IMP-201 or explicitly keep the affected C4 control in observe.
- [ ] Run bookkeeping hygiene preflight without mutating unrelated plans.
- [ ] Re-run lint, CP1/C0 and independent plan verification with a bounded
  review budget.
- [ ] Regenerate P062 EPICs from the final reviewed plan.

**GO to Phase 8:** every E10 hard precondition is executable and true on
current main; no prerequisite depends on stale prose or obsolete bookkeeping.

## Phase 8 — execute P062/E10

- [ ] Build the preflight and freshness evidence.
- [ ] Measure detection, false-DONE, false-positive and unique-detection
  behavior.
- [ ] Measure wall-clock, profile savings and full-suite/scheduler cost.
- [ ] Run the grounded regression dataset and old-vs-new dual run.
- [ ] Calibrate C4 content verdict and risk-profile escalation.
- [ ] Produce a per-control decision table:
  `promote_to_blocking|keep_observe|keep_dual_run|defer|E11-removal-candidate`.
- [ ] Promote only controls supported by evidence and satisfied
  preconditions.
- [ ] Delete no legacy control in E10; removal belongs to E11.
- [ ] Publish the E10 report, release and durable plan closure.

## Explicitly deferred

These do not block the path to E10 unless reclassified by a fresh finding:

- IMP-268 debug CLI hardening;
- IMP-255–257 and IMP-259–260 refactoring/diagnostic cleanup;
- IMP-261 INIT/SETUP redesign implementation (analysis may proceed
  independently, but do not fold it into P068/P066/E10);
- E11 legacy-control deletion;
- cross-plan train releases and parallel implementation agents.

## PM stop rules

- A waiver never becomes a fabricated pass.
- No full-suite retry starts automatically after the bounded allowance.
- No background job without an owned terminal receipt can block AUTO.
- A new unrelated audit finding is classified and recorded; it does not
  silently expand the current delivery scope.
- A direct regression of the invariant currently being fixed remains a
  blocker.
- Any proposed removal of test coverage requires explicit PM approval.

## Implementer progress log

The implementer owns this section during Phase 1. Append one row after every
independently reviewable commit; do not rewrite earlier rows.

| UTC date | Batch | Commit | Targeted red/green evidence | Independent review | Remaining blocker |
|---|---|---|---|---|---|
| 2026-07-23 | P064 baseline | `2a1ca60` | boundary 241/241; three waivers remain visible | Auditor 89/100, no merge blocker | Phase 1 not started |
| 2026-07-23 | 1D IMP-271 | `c82be23` | 7 red-green cases; boundary 248/248; Security F-2 5/5 | verifier pass, 1 LOW to P068 | superseded by A1 below |
| 2026-07-23 | 1D IMP-272 | `e544715` | attack repro both twins; queue/dep 30/30; revalidation 8/8 | verifier pass; ordering note applied | HIGH bypass found post-review → a18b183 |
| 2026-07-23 | 1D IMP-273 | `48270af` | 6 red-green cases; test-aid-fsm 88/88; registry 13/13 | verifier pass | — |
| 2026-07-23 | 1D IMP-274 | `214a9fc` | repo-wide grep-oP guard + self-test; registry honesty (307, TTL green) | controller self-check | — |
| 2026-07-23 | 1A IMP-270 | `3f08c80` | 22 waiver cases; run-gates 41/41; F1 folded; registry 308 | security review pass, no HIGH | — |
| 2026-07-23 | HIGH IMP-272 hardening | `a18b183` | PM collusion attack (plan_id+merge_target) refused both twins; derive plan from epic id | security review pass, bypass closed | — |
| 2026-07-23 | HIGH IMP-271 A1 | `23fe72e` | Codex-adjudicated bypass removal; bootstrap stub refactor; full boundary 258/258, tree clean | Codex A1 + full-suite green | — |
| 2026-07-23 | 1B IMP-263 | `c3d493c` | double-advance repro + fix; forged-ledger bound; test-aid-fsm 100/100 | verifier pass; MEDIUM (self-heal bound) folded | — |
| 2026-07-23 | 1B IMP-262 | `a02e866` | job supervisor 18/18; no process/jobs leak; PID-reuse/cancel/redgreen | security review pass; 2 MEDIUM + LOW folded | — |
| 2026-07-23 | 1C IMP-269 | `00ef981` | both-gap repro; test-c3-audit 45/45; F-2 5/5 | security review pass; borderline-HIGH F1 + F2 + F3 folded | — |
| 2026-07-23 | 1C IMP-265/258/267 | `45ae9aa` | lineage repro; 8 new cases + AC7/AC8; Security F-2 5/5 unmodified | security review pass; invariant holds every path; LOW folded | — |
| 2026-07-23 | 1C IMP-264 | `0263276` | staleness repro; pm-brief 23/23; protocol-validate 60/60 | controller-verified (display-only, low risk) | — |
| 2026-07-24 | 1C IMP-266 | `e40f9ca` | decision brief only — NOT implemented; recommends Option B | Codex adjudication hung; deferred to PM ratification | PM ratifies A or B |
| 2026-07-24 | Phase-1 close | `a6a3363` | v2.62.0 bump (8 files), CHANGELOGs identical, checkpoint + 1B/1C boxes; cache reset to `a6a3363` (scripts-tree `1bf86b3`) | version sync verified; tree clean; not pushed, not tagged | PM: push + git-identity remedy decision; P068 start |
| 2026-07-24 | Hardening IMP-263 | `cfdaed4` | 3 bypasses repro'd RED (forged-ledger self-heal, partial binding, no-binding default); fix; test-aid-fsm 103/103 | strict-by-default, partial rejected, self-heal binding-gated | — |
| 2026-07-24 | Hardening IMP-269 | `d1bf7f0` | 5 gaps repro'd RED (2 canonical, 1 revision, 2 log); fix; test-c3-audit 50/50 | canonical-only AC source; git-tracked plan read from reviewed HEAD (else canonical worktree artifact); receipt consistency-checked vs named command/HEAD/log — consistency, not provenance against direct evidence tampering | — |
| 2026-07-24 | Hardening IMP-262 | `8e94dd4` | 3 pre-PID fault tests; handshake; set-e/pipefail abort also fixed; test-aid-job 21/21 | marker + wrapper self-cancel; job never starts after cancel | — |
| 2026-07-24 | Hardening IMP-270 | `6751157` | 2 tests repro'd RED on pre-fix (empty + malformed head); fix; test-aid-gate-waiver 24/24 | missing/malformed report HEAD fails closed, no current-HEAD fallback | — |
| 2026-07-24 | Hardening review + close | `cee4685` | one independent adversarial review of all 4 boundaries → no residual bypass; registry 4 rows updated; v2.62.1 bump; two stale intro lines fixed; IMP-269 wording corrected (consistency-check, not provenance) folded into the local release; cache reset to `cee4685` (scripts-tree `6aea929`) | version sync verified; tree clean; not pushed, not tagged | PM: push + git-identity remedy; P068 start |
| 2026-07-24 | IMP-266 ratified (B) | committed with this row | PM chose Option B; wrote recovery ceremony (`IMP-266-merged-to-plan-recovery-CEREMONY.md`); updated decision brief + adjudication + checklist | doc-only, `merged_to_plan` stays terminal, no code edge; Option A deferred to P068+ | — |

When Phase 1 finishes, update the top-level checkpoint, mark only genuinely
completed checkboxes, and record the released version plus cache SHA.
