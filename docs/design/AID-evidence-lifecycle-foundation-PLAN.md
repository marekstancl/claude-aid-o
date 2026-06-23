---
id: P049-DRAFT
type: plan
status: draft
created: 2026-06-22
author: AID planning (foundation)
source: docs/AID-evidence-lifecycle-current-state-foundation-handoff.md
blocks: [E-047-6_7, E-047-7_7]
---

# AID Evidence Lifecycle & Current-State Foundation — Implementation Plan (v2)

> Standalone, reviewable prerequisite plan. **Blocks** E-047-6_7 (paused) + E-047-7_7 (paused).
> Golden product oracle: `docs/design/E-047-6-expected-screen-G.md`. **This is a plan for
> independent review — NOT an implementation.** Proposed plan id **P049** (assign on approval).

## Stakeholder Brief

The Cockpit tried to read "what is true now" out of historical evidence that was never meant to
answer that question, so it showed finished work as active, history as current blockers, and wrong
plan progress. This plan builds the missing layer underneath the Cockpit: AID will **record** the
real lifecycle of every project, plan, EPIC, run and problem as durable, append-only events the
moment they happen, and a single deterministic reconciler folds those events (plus historical
evidence) into a per-project current-state manifest the Cockpit simply reads. No guessing, no LLM,
no overwriting history. When evidence is missing or sources conflict, the answer is an honest
`unknown` — never a fabricated positive. After this foundation is accepted, the paused Cockpit
work (E-047-6_7) resumes on top of it.

## v1 review — the eight findings and how v2 resolves them

| # | v1 finding | v2 resolution |
|---|---|---|
| 1 | Operational reconciler fallback in Cockpit contradicts "missing manifest → unknown" | **Removed.** Reconciler is audit/backfill/producer-validation ONLY. Cockpit with no manifest → `unknown`, never runs the reconciler at request time (§2, §Phase 6). |
| 2 | Backfill not reconstructible; rollback would delete the audit log | **Event log is the durable source of truth; manifest is a materialized fold.** Backfill emits a `baseline_imported` event + writes to an append-only **manual-override ledger** with provenance/approval. Rollback regenerates/deletes ONLY the materialized manifest, never `.aid-o/state/events/` or the override ledger (§2, §Phase 5). |
| 3 | Producer still depends on the LLM calling an emit lib | **One deterministic closure command** (`aid-epic-close`) performs PM-decision + merge + task-archive + queue-transition + lifecycle-event + manifest-regen as a single transactional operation. Skills call THIS command, not individual shell steps. `aid-release.sh` stays a version-bump tool, NOT the EPIC-closure owner (§Phase 4.4). |
| 4 | Precedence row "run terminal/merged" conflates 6 distinct facts | **Split into six independent claims** (run-execution-complete · gates-success · PM-approval-recorded · git-merge-present · archived · plan-complete). Compliance/gates are never merge proof; live FSM conflicting with later merge/closure does not auto-mean frontier (§5). |
| 5 | No producer transaction rule for partial failures | **Outbox/recovery protocol** added: the append-only event log IS the outbox; the manifest is rebuilt from it; a `pending`/`committed` marker per operation enables replay. AC: no successful lifecycle operation may exist without a reconstructible event (§Producer transaction protocol, §Phase 4.2). |
| 6 | Phase 4 too large (FSM+queue+merge+archive+skills+hooks+event-log+bundling at once) | **Split into 6 sub-steps** (4.1–4.6), each with its own AC + CP checkpoint scope (§Phase 4). |
| 7 | Missing packaging/distribution + Node-18 runtime decision | **New Phase 0 (packaging)** + D-1 expanded with the Node-18 runtime decision, reproducible-bundle build, vendored-bundle ↔ TS-source equivalence check, root build/test scripts, server dep, plugin version/changelog/distribution rules (§3, §Phase 0). |
| 8 | Grounding errors (`compliance-rollup` path; "No flock anywhere") + missing P047/spec cross-check | **Corrected:** path is `services/compliance-rollup.ts`; `aid-emit-dispatch.sh` DOES use `flock` + a `.lock` sidecar (reused as the event-log write pattern). Full P047/spec cross-check added (§4). |

## Scope

**In scope:** evidence readiness audit (6 projects); canonical current-state + lifecycle contract;
the deterministic reconciler (audit/backfill/validation tool); the append-only lifecycle event log
+ materialized manifest; producer lifecycle emission + the deterministic closure command + outbox
recovery; backfill + rollout to 6 projects with a durable override ledger; runtime acceptance vs the
approved oracle; the contract/API hand-back to E-047-6_7.

**Out of scope (binding):** LLM summary/enrichment/lifecycle decisions; new Cockpit UI / propagating
F1 to Screen B/Plan/C/D/E; a second Cockpit-specific resolver; rewriting the Cockpit historical
analytics; backlog-write UI; deleting/rewriting raw evidence or audit history; auto-deciding
ambiguous business state without an approved rule.

## Approach

Three layers (historical evidence untouched → one shared deterministic reconciler → durable
event log + materialized manifest written by the AID producer; Cockpit reads only). **Alternatives
rejected:** (a) Cockpit-side multi-source resolver — rejected, violates "one reconciler" + read-only
Cockpit; (b) manifest as sole state with no event log — rejected, not reconstructible after deletion
(v1 finding 2); (c) bash-only reconciler — rejected, the cockpit needs the same logic and bash can't
carry the precedence/alias/provenance complexity (see D-1).

## Binding boundaries (from handoff)

LLM out of scope · no new Cockpit UI now · one shared reconciler · mtime/FSM/git never universal
authorities · conflict/missing → `unknown`/`conflicting` · a project may have ≥1 open plans ·
project-level concerns without `planId` stay visible · historical evidence never deleted/rewritten ·
E-047-6_7 resumes only after foundation acceptance + a new live PM acceptance.

---

## 1. Grounded findings (repository research — corrected)

**Producer** (`plugins/aid-orchestrator/scripts/`): no current-state manifest exists today; state is
per-run `fsm-state.yaml` (`aid-fsm.sh`) + per-run `timeline.jsonl` (`lib/aid-stage-log.sh log_event`,
atomic append) + project-level `work/audit-log.jsonl` (`aid-audit-log.sh`) + `config/queue.yaml`
(`aid-queue-add.sh`, append-only `status:queued`). **Archive moves, the EPIC-release `git merge
--no-ff`, and queue `queued→running→completed` are NOT scripted — they are LLM-executed steps in
`skills/pipeline.md` / `skills/run-management.md` / `commands/aid-run.md`.** So closure/merge/archive
are not recorded as machine events today — the core gap. `aid-release.sh` is the **plugin version-bump
tool**, not an EPIC-closure owner. **`flock` IS used** — `aid-emit-dispatch.sh` (lines 130/137/164)
uses `flock -x` on a `.lock` sidecar; this is the reusable atomic-write precedent for the new event log.

**Evidence variance + conflict surface** (real `.aid-o`, 6 projects): `fsm-state.yaml` schema grew
across eras (early runs lack `steps[]`/`streamlined_mode`/`done_phase`/`pm_decision`); legacy
`state.yaml` (per-step JSON array) coexists in 45/130 runs; plan pointer has 3 names
(`plan_path`/`plan_ref`/`plan`); task `status` chronically `active` on merged EPICs (40+);
plan `status` 9+ spellings; `queue.yaml` 2 shapes, hand-reconciled/stale; transitions recorded under
4 event names; some timeline lines malformed; archive dirs inconsistent (`tasks/archive` universal,
`plans/archive` only 2 projects, run archives split). 8 conflict classes → §5 fixtures.

**Consumer (Cockpit)** (`packages/aid-server/src/`): no single lifecycle authority; 3 guessing sites
— `project-scanner.ts:250` (`epicsActive`="≥1 run dir"), `scanner-cache.ts:785`/`project-scanner.ts:465`
`pickLatestRun` (mtime/started_at), `routes/brief.ts:250` `deriveArchiveStatus` (placeholder→`unknown`).
**Archive dirs excluded from the scan** (`project-scanner.ts:228-231,305`; `scanner-cache.ts:314,334,369`).
`services/compliance-rollup.ts:112` iterates `epic.runs.values()` — shared per-EPIC history source.
Read-only invariant enforced by `integration/read-only-invariant.test.ts`.

---

## 2. Architecture (three layers — NO operational fallback)

```
Historical evidence (UNTOUCHED, read-only)  ── per-run fsm-state/timeline/compliance/gates/audit, tasks, plans, queue, ledgers, git
        │ read-only (audit/backfill/validation only)            │ read-only (audit + analytics)
        ▼                                                       ▼
  Reconciler (ONE shared, deterministic, PURE)            Cockpit server (read-only)
  facts → signal-specific precedence → classify           reads MANIFEST only.
  → provenance + confidence + review-queue                NO reconciler at request time.
  modes: dry-run · backfill · producer-validation         Missing manifest ⇒ `unknown` (never fallback).
        │ folds
        ▼
  Lifecycle event log  ──(append-only, durable = SOURCE OF TRUTH)──►  Manifest (materialized FOLD)
  .aid-o/state/events/*.jsonl  +  overrides.jsonl                     .aid-o/state/current-state.json
        ▲ writes (atomic, flock+.lock)                                ▲ writes (atomic temp+rename; regenerable)
        │
  Producer = AID plugin (aid-fsm.sh + lib/aid-lifecycle-emit.sh + aid-epic-close)
```

**Authority model (finding 1):** the **event log is the durable source of truth**; the **manifest is
a materialized fold** that can always be regenerated from `events/*.jsonl` + the historical evidence +
`overrides.jsonl`. The **Cockpit reads the manifest only** and never runs the reconciler at request
time; a missing manifest renders `unknown`. The reconciler-as-library is for the *producer* (to
regenerate the manifest) and for *audit/backfill/dry-run tooling* — never an inline Cockpit code path.

**Reframing the spec contradiction (cross-check §4):** spec:2374 says the Cockpit "introduces no new
SOURCE OF TRUTH and performs no writes". That invariant is **preserved** — the *Cockpit* still owns
nothing and writes nothing; the *AID producer* now owns durable current-state. The manifest is, from
the Cockpit's view, just one more read-only on-disk artifact.

---

## 3. Ownership map + D-1 (cross-language + Node-18 runtime decision)

| Concern | Owner | Boundary |
|---|---|---|
| Historical evidence | unchanged | producers keep writing per-run evidence as today |
| Canonical schema + reconciler + manifest contract | **new shared TS package `@aid/lifecycle`** (`packages/`) | sibling to `@aid/contract`; pure, deterministic, no LLM/network |
| Lifecycle event emission + closure command + manifest regen | **AID plugin** (`aid-fsm.sh` + `lib/aid-lifecycle-emit.sh` + `aid-epic-close`) | invokes the vendored reconciler |
| Manifest consumption | **Cockpit server** | read-only; NO reconciler at request time |

**DECISION D-1 (PM, gates Phase 0 packaging; does NOT gate the schema):** how the bash plugin runs the
TS reconciler, given (a) the plugin must stay self-contained (distribution boundary: the plugin
manifest must never reference `packages/`), and (b) **the host runs Node 18.20.4** (cross-check §2
preserve-list; packages pin `vite@6`/`lru-cache@10` for Node-18).
- **D-1a (recommended, pending runtime sign-off):** `@aid/lifecycle` compiles to a single dependency-free
  **Node-18-target** CJS bundle vendored into the plugin (`plugins/aid-orchestrator/vendor/aid-lifecycle.cjs`);
  `aid-fsm.sh`/`aid-epic-close` run `node vendor/aid-lifecycle.cjs <cmd>`. Requires: a reproducible build
  (esbuild `--target=node18 --platform=node --bundle`), a CI equivalence check that the vendored bundle
  matches the committed TS source (rebuild + diff), and an explicit "Node ≥18 required to run the plugin"
  declaration. **Cannot be approved without the runtime sign-off** (is Node guaranteed wherever the plugin
  runs?).
- **D-1b:** manifest schema is the ONLY cross-layer contract; plugin emits events in bash, a separate
  (TS) backfill/validation tool reconciles. Rejected unless D-1a build proves infeasible — risks two
  partial implementations.
- **D-1c:** runtime npm dependency on `@aid/lifecycle` in the plugin. Rejected — breaks self-containedness.

---

## 4. P047 / Cockpit-spec cross-check (mandatory — the contract delta)

**Types survive; four derivation rules are superseded.** No contract type (`Project`, `EpicSummary`,
`RunDetail`, `Brief`, `PlanSummary`/`PlanDetail`, `PlanOutcome`, `ComplianceRun`/`ComplianceFailure`,
`AuditSummary`/`AuditTrend`, `LessonsView`) is renamed/removed — the foundation changes their *source*,
additively (new optional lifecycle/confidence/qualifier fields).

**Superseded derivation rules (mark in spec on acceptance):**
1. **§4.0 #8 latest-run / activeRun** (spec:90, spec:626) — `max(started_at|mtime)` sort → superseded by
   manifest lifecycle; mtime stays a *freshness/timing* signal only (timing uses like `run_duration_sec`
   spec:267 are KEPT).
2. **§5.7 "resolved violation" rule** (spec:332, spec:2410) — "a later run lacks the `.check`" inference →
   superseded by explicit problem-lifecycle/closure facts with provenance.
3. **§13.2 S6/S7 mtime/dwell lifecycle inference** (spec:2416) — `staleRun`/`stuck` derived from mtime →
   superseded by manifest `qualifiers` (`stale` is a qualifier, never a lifecycle).
4. **§5.4 active-set = state ∈ {READY,EXECUTE,GATES}** (spec:344) — superseded by manifest project/EPIC
   lifecycle (which also honors archive evidence the scan currently can't see).

**Must preserve (cross-check §2):** read-only Cockpit invariant (producer/reconciler stay AID-side); the
`packages/` ↔ plugin distribution boundary (the foundation deliberately splits across it, each half under
its own contribution rules); the `/file` §7.4.1 allow-list (the manifest path under `.aid-o/state/` must be
**added** explicitly or it 404s); WS protocol; §6 explanation dictionary (new lifecycle states/qualifiers
need dictionary keys so terminology doesn't drift); Node-18 pins; the Tier-1 scanner index pattern
(spec:638 — add the manifest to it).

**House plan format (cross-check §3):** front-matter + Stakeholder Brief + Context/Goal/Scope(in/out)/
Approach(+rejected) + EPIC grouping (`**EPIC n: Steps a-b — …**`) + per-step anatomy (Objective/Files/
Architecture Context/Implementation Detail/Error Handling/Edge Cases/Dependencies/Acceptance Criteria/
Effort/AID Role) + plan-level **machine-verifiable AC** as `verification_pattern` YAML blocks parsed by
`aid-plan-diff.sh`. This plan follows it; §Plan-level AC supplies the executable blocks.

**Spec proto-acknowledgments (reuse, don't reinvent):** the spec already noted `fsm-state.steps[]` is
unreliable (spec:84), that `fsm_init` mtime misrepresents lifecycle (spec:260), and built per-field
mini-reconcilers (§5.7, §13.6) — the foundation generalizes these. The spec's `confidence`/`partial`/
`warnings` apparatus is a proto-`evidenceQuality`/`confidence` — promote, don't duplicate.

---

## 5. Signal-specific precedence matrix (split claims — finding 4)

The v1 "run terminal/merged" row is decomposed into **six independent claims**, each with its own
ordered sources + conflict rule. No global "git wins"/"mtime wins". (Full matrix + a fixture per row
lands in Phase 2; this is the binding skeleton.)

| Claim | Sources (high→low) | Conflict / missing → |
|---|---|---|
| **run-execution-complete** | fsm-state `state==DONE` (+ `current_step>=total_steps`) > legacy `state.yaml` all-steps-completed | mismatch → `unknown` |
| **gates-success** | `gates_report.json overall==pass` > timeline `gates_complete overall` | absent → `missing` (NOT pass) |
| **pm-approval-recorded** | fsm-state `pm_decision==merge` > a `decision_recorded` lifecycle event | absent → not approved (`waiting_decision` if review) |
| **git-merge-present** | a `merge_recorded` lifecycle event (from `aid-epic-close`) > `git log` merge SHA for the EPIC | git merge ≠ run/plan completion; alone proves only "merged in git" |
| **archived** | task in `tasks/archive/` OR run in `runs/archive/` (explicit) OR an `archive` event | absence from active set → NOT archived |
| **plan-complete** | explicit `plan_closed` event / closure marker OR ALL mandatory member EPICs satisfy the evidence contract (run-complete ∧ pm-approval ∧ — per policy — gates/audit) | one merged EPIC → NOT complete; missing member → `completed_unclosed`/`unknown` |

Other rows (unchanged from v1 intent): **frontier** = live fsm state AND not-archived; *a live FSM state
that conflicts with a later merge/closure event for the same entity does NOT auto-mean frontier — it is a
conflict → `unknown` pending rule/override.* **plan member set** = `plan_path`>`plan_ref`/`plan`>id-derived>orphan
(file must exist). **plan paused vs stale** = explicit pause marker→`paused`; age-only→`active`+`stale`.
**problem resolved** = per-signal closure over the SAME `rootCauseIdentity` via `epic.runs` (gate→newer
same-gate pass; compliance→newer complete same-check no-violation; audit→newer audit no same blocking
finding; merge→`decision_recorded`; precondition→subsequent successful transition); bigger EPIC number →
NEVER supersession. **project concern w/o planId** = backlog P0/issue → stays visible at project scope.
**override** = explicit author+reason+timestamp+provenance (recorded in `overrides.jsonl`), wins but logged.

---

## Producer transaction & recovery protocol (finding 5)

Every lifecycle-changing operation is an **outbox transaction** over the append-only event log:
1. Write an event record with `status:"pending"` (+ `eventId` idempotency key) under `flock`+`.lock`
   (reusing the `aid-emit-dispatch.sh` pattern) BEFORE the side effect (merge/archive/queue/FSM mutation).
2. Perform the side effect.
3. Append a `status:"committed"` marker for that `eventId` (or `status:"failed"` with the error).
4. Regenerate the manifest (fold over committed events + evidence). Manifest write is atomic (temp+rename).

**Recovery** (`aid-lifecycle recover`): on startup / next command, scan for `pending` events without a
`committed`/`failed` marker → reconcile against ground truth (git/archive/fsm) → mark `committed` if the
side effect actually landed, else `failed` + surface in the review queue. **Failure cases handled:**
FSM changed but event write failed → the FSM mutation is gated *after* the pending-event write, so this
ordering is impossible for the gated paths; event written but reconcile failed → manifest is stale but
regenerable (idempotent re-run); merge happened but archive failed → `aid-epic-close` is one transaction,
partial completion leaves a `pending` event → recovery completes or flags it. **AC:** no successful
lifecycle operation may exist without a reconstructible committed event (asserted by a chaos test that
kills the command between each step and verifies recoverability).

---

## Canonical entities, enums, manifest (concept → Phase 2 locks exact schema)

Machine enums (separate from Czech display labels in the Cockpit dictionary):
- **Project:** `active|paused|idle|blocked|archived|unknown` + `qualifiers[]`, `openPlanIds[]`, `projectConcernIds[]`.
- **Plan:** `planned|ready|active|waiting_decision|blocked|paused|completed_unclosed|completed|abandoned|historical|unknown`; `stale`=qualifier.
- **EPIC/run:** `queued|ready|active|gates|waiting_decision|blocked|completed|abandoned|superseded|archived|unknown` + explicit FSM/legacy mapping (Phase 2).
- **Problem:** `active|resolved|historical|unknown` + `resolvedBy`/`supersededBy`/`evidenceRefs[]`/`rootCauseIdentity`; `stale`=qualifier.
- **Evidence quality:** `complete|partial|conflicting|missing`; confidence (`high|low`) ≠ state.

Manifest `.aid-o/state/current-state.json` (path proposed; Phase 2 confirms): `schemaVersion`, `generatedAt`
(injected), `producerVersion`, project block, `plans[]` (id/title/objective/lifecycle/qualifiers/confidence/
evidenceQuality/progress/frontierEpics/nextExpectedAction/decisions/blockers/risks/audit+backlog+delivery+
lessons summaries/lastMeaningfulActivity/evidenceRefs), `projectConcerns[]`, `queue[]`, `aliases[]`,
`dataQualityIssues[]`, `provenance[]`. Every count/status reproducible from `provenance[]`; unproven → `null`/`unknown`.

---

## Phase 0 — Packaging & runtime foundation (finding 7) — NEW

**Objective:** stand up `@aid/lifecycle` as a buildable, testable workspace package with a reproducible
Node-18 plugin bundle + the distribution rules, so later phases have a home. **Gated on D-1.**

- **Steps:** 0.1 scaffold `packages/aid-lifecycle` (package.json, tsconfig, vitest) + add to root `package-lock.json` + root build/typecheck/test scripts + `packages/aid-server` devDep (for the reader type); 0.2 esbuild bundle target `node18`, output `plugins/aid-orchestrator/vendor/aid-lifecycle.cjs`; 0.3 CI equivalence check (rebuild bundle in CI, `git diff --exit-code` the vendored file) + a test that the bundle runs on Node 18; 0.4 plugin distribution rules (CHANGELOG/version/enforcement-registry entry for the new vendored producer dependency).
- **Files:** `packages/aid-lifecycle/{package.json,tsconfig.json,vitest.config.ts,src/index.ts}`, root `package.json` scripts, `plugins/aid-orchestrator/vendor/.gitkeep`, a CI script `packages/aid-lifecycle/scripts/check-vendored-bundle.sh`.
- **Ownership:** packages/ (build) + plugin (vendored artifact + distribution rules).
- **Error handling / rollback:** bundle build failure → CI red; rollback = the vendored bundle is additive, delete it + the package.
- **Fixtures/negative controls:** a "hello" reconcile that runs under `node18` in CI proving the toolchain; negative: a deliberately-stale vendored bundle fails the equivalence check.
- **AC:** `npm run build/test -w @aid/lifecycle` green on Node 18; vendored bundle equivalence check passes; plugin self-containedness preserved (no plugin manifest ref to `packages/`).
- **Dependencies:** D-1 (Node-18 runtime sign-off). **Effort/risk:** 2–3 d / medium (toolchain + cross-boundary).

## Phase 1 — Evidence readiness audit

**Objective:** machine + human inventory of 6 projects; alias/conflict/closure-debt/legacy/stub/unknown
census; freeze the hand-approved `oracle.json`. (Largely done by the per-project agents.)
- **Files:** `tools/lifecycle-audit/{inventory.ts,report.md.ts,fixtures/oracle.json}` (dev tool; reads `.aid-o`, writes only `out/` + committed fixtures + the sanitized conflict fixtures via the E-047-4 sanitizer pattern + secret-scan).
- **Error handling:** tolerate malformed timeline lines (skip+count), missing dirs (`missing`), legacy dialects.
- **Rollback:** read-only; delete `out/`.
- **Negative controls:** a test asserts the inventory emits ZERO lifecycle verdicts (raw facts + refs only).
- **AC:** every project/plan/EPIC/run/problem present with ≥1 source ref; conflict/closure-debt/alias lists populated; `oracle.json` PM-approved + frozen.
- **Dependencies:** none. **Effort/risk:** 2–3 d / low.

## Phase 2 — Current-state & lifecycle contract

**Objective:** lock entity schemas/enums/qualifiers/nullability; the §5 split precedence matrix;
completion/closure/supersession rules; manifest ownership/path/format/`schemaVersion`/migration; contract
tests + a fixture per matrix row.
- **Files:** `packages/aid-lifecycle/src/{schema.ts,precedence.ts,closure-rules.ts}`, `schema/current-state.schema.json`, `schema/lifecycle-event.schema.json`, `docs/design/AID-lifecycle-contract.md`.
- **I/O schema:** the manifest + event-record schema + the FSM↔canonical mapping table (modern/legacy/stub eras).
- **Error handling:** schema validation fails closed → `unknown`; unknown enum rejected.
- **Migration/rollback:** `schemaVersion` semver; sidecar manifest → rollback = delete manifest (NOT the event log).
- **Negative controls:** contract tests — mtime-only → never positive; git-merge-only → never plan-complete; bigger EPIC number → never supersession; missing → `unknown`.
- **AC:** every enum has a fixture; D-1 decided; mapping covers all eras; each of the 6 §5 claims has a passing+failing fixture.
- **Dependencies:** Phase 0, Phase 1. **Effort/risk:** 4–6 d / **high** (conceptual core).

## Phase 3 — Shared reconciler & dry-run tooling

**Objective:** the single deterministic reconciler (facts→precedence→classify) with provenance/confidence,
dry-run, alias resolution, review queue; negative controls proving mtime/FSM/git alone can't fabricate state.
- **Files:** `packages/aid-lifecycle/src/{facts.ts,reconcile.ts,alias.ts,review-queue.ts,cli.ts}` (CLI: `reconcile|dry-run|backfill|validate|recover`); tolerant parsers reuse `aid-server/src/services/run-detail.ts` patterns.
- **I/O:** input = project root (read-only) + injected `generatedAt` + the event log; output = manifest (write mode) OR dry-run report (writes nothing) + `review-queue.json`. Pure core (no Date.now/random/network in the decision path).
- **Error handling:** classification carries provenance+confidence; unparseable/conflicting → `unknown`/`conflicting` + `dataQualityIssues`; never throws.
- **Migration/rollback:** dry-run default; write idempotent (same inputs → byte-identical manifest mod timestamp).
- **Negative controls (MANDATORY):** mutate ONLY mtime → output unchanged; git-merge-only → plan stays `completed_unclosed`/`active`; archived task + touched run → `archived`/not-frontier; conflicting sources → deterministic `conflicting` across repeated runs.
- **AC:** dry-run writes nothing (asserted); idempotent; review-queue = exactly the low-confidence cases; alias map deterministic+provenance-backed; reconciler over the 6 fixtures matches `oracle.json` (or PM-approved deviation).
- **Dependencies:** Phase 2. **Effort/risk:** 6–8 d / **high**.

## Phase 4 — Producer lifecycle enforcement (SPLIT — finding 6)

Each sub-step is independently shippable with its own AC + CP-checkpoint scope (so no broad step passes
with a missing contract part).

- **4.1 Event-log writer + recovery primitive.** New `lib/aid-lifecycle-emit.sh` (append `pending`/`committed`
  events under `flock`+`.lock`, reusing the `aid-emit-dispatch.sh` pattern) + `aid-lifecycle recover`.
  *AC:* events append atomically; idempotency key dedupes; chaos-kill between steps is recoverable.
  *Effort:* 2 d.
- **4.2 FSM transition events + outbox ordering.** `aid-fsm.sh` emits a `pending` lifecycle event BEFORE each
  state mutation, `committed` after, then regenerates the manifest. *AC:* every FSM transition has a
  reconstructible committed event; manifest regenerates atomically; existing 6-state behavior unchanged when
  `AID_LIFECYCLE=0`. *Effort:* 2 d.
- **4.3 Decision + problem/blocker open-close events.** Emit `decision_requested`/`decision_recorded`,
  `problem_opened`/`problem_resolved` (with `rootCauseIdentity`+closure rule), gate/compliance/audit closure
  relevant to a problem. *AC:* problem lifecycle round-trips; closure obeys §5 per-signal rules. *Effort:* 1–2 d.
- **4.4 The deterministic closure command `aid-epic-close` (finding 3).** ONE transactional command: record PM
  decision → `git merge --no-ff` → archive task → queue transition → emit `merge_recorded`+`archive`+
  `epic_completed` events → regenerate manifest. Skills (`pipeline.md`/`run-management.md`/`commands/aid-run.md`)
  call THIS command, not the individual shell steps. `aid-release.sh` stays version-bump only.
  *AC:* a single invocation performs all six effects or leaves a recoverable `pending` event; skills no longer
  contain ad-hoc merge/archive/queue steps; producer REFUSES `completed` without closure data (→
  `completed_unclosed`, never silent `completed`). *Effort:* 3 d / **high**.
- **4.5 Plan closure / pause-resume / abort / archive / supersession events.** `aid-plan-close` extension +
  pause/resume/abort/supersession (with origin link). *AC:* plan lifecycle transitions emit events; supersession
  requires explicit link, never EPIC-number inference. *Effort:* 1–2 d.
- **4.6 Queue ownership.** `aid-queue-add.sh` + the closure command emit queue insert/remove/reorder; queue
  lifecycle becomes manifest-backed. *AC:* queue transitions are events; manifest queue matches. *Effort:* 1 d.
- **Files:** `aid-fsm.sh`, new `lib/aid-lifecycle-emit.sh`, new `aid-epic-close.sh`, `aid-queue-add.sh`,
  `aid-plan-close` path, `skills/*.md`+`commands/aid-run.md` (call the command), `defaults/hooks/` (optional
  post-merge emit), `defaults/enforcement-registry.yaml` (register the new enforcement).
- **Migration/rollback:** all behind `AID_LIFECYCLE` flag; event log + manifest are additive sidecars; rollback =
  unset flag + regenerate-or-delete the **manifest only** (NEVER `.aid-o/state/events/` or `overrides.jsonl`).
- **Negative controls:** completion without closure → refused/`completed_unclosed`; duplicate transition → no
  duplicate event; interrupted write → old-or-recoverable, never corrupt.
- **Dependencies:** Phases 0,3. **Effort/risk (phase):** 10–11 d / **high** (split mitigates).

## Phase 5 — Backfill & rollout (finding 2 — reconstructible)

**Objective:** generate each project's manifest via dry-run→approve→write, durably + idempotently, with a
reconstructible baseline.
- **Files:** `tools/lifecycle-audit/backfill.ts`; per project it (1) emits a **`baseline_imported`** lifecycle
  event capturing the reconciled baseline + its provenance, (2) records every manual review-queue resolution
  in the **append-only `.aid-o/state/overrides.jsonl`** (author/reason/timestamp/provenance/approval), (3)
  materializes the manifest as a fold over events+overrides+evidence.
- **Migration/rollback:** dry-run before every write; **rollback regenerates/deletes ONLY the materialized
  manifest** — `events/*.jsonl` + `overrides.jsonl` are the durable record and are never deleted by rollback;
  a pre/post checksum proves ZERO change to historical evidence (everything outside `.aid-o/state/`).
- **Negative controls:** delete the manifest → re-fold from `events`+`overrides` reproduces the approved state
  (the v1 finding-2 reproducibility test); re-run backfill → identical manifest (idempotence); removed evidence → `unknown`.
- **AC:** 6 manifests generated; review-queue resolved or explicitly `unknown`; `baseline_imported` + overrides
  persisted; manifest reproducible after deletion; historical-evidence checksum unchanged.
- **Dependencies:** Phases 3,4. **Effort/risk:** 3–4 d / medium.

## Phase 6 — Foundation acceptance & Cockpit hand-back (finding 1 — no fallback)

**Objective:** prove runtime current-state = approved oracle on 6 projects; define the contract/API hand-back.
- **Files:** `packages/aid-lifecycle/src/reader.ts` (typed manifest reader; **no reconcile path**), a thin
  adapter seam in `packages/aid-server` where `routes/brief.ts:deriveArchiveStatus`/`project-scanner` lifecycle
  guessing lives (adapter only — full re-point is E-047-6_7 work), `docs/design/AID-lifecycle-contract.md`
  (hand-back: manifest fields → API endpoints), `/file` allow-list addition for `.aid-o/state/current-state.json`.
- **Error handling:** missing manifest → `unknown` (asserted); reader fails closed; **the Cockpit never invokes
  the reconciler** (a test greps the server bundle for any reconcile import → must be absent).
- **Migration/rollback:** adapter behind the flag; E-047-6_7 stays paused until this passes.
- **Negative controls:** delete a manifest → Cockpit shows `unknown`, not a positive fallback; `conflicting`
  manifest → shown as conflicting; server-side reconciler import = test failure.
- **AC:** runtime current-state of 6 = oracle (or approved deviation); hand-back contract written; P047 +
  E-047-6_7 get an explicit `completed` dependency marker; only THEN Screen G / F2 / other-screen propagation resume.
- **Dependencies:** Phases 1–5. **Effort/risk:** 3–4 d / medium.

---

## Plan-level machine-verifiable acceptance criteria (house format — sample)

```yaml
# AC: Cockpit server contains NO reconciler/library call at request time (finding 1)
verification_pattern:
  type: must_not_contain
  file: packages/aid-server/src/**/*.ts
  regex: "from '@aid/lifecycle'.*reconcile|reconcile\\("
  expected: absent
```
```yaml
# AC: manifest is reproducible from the durable event log (finding 2)
verification_pattern:
  type: cmd
  cmd: "node packages/aid-lifecycle/dist/cli.js reconcile <fixtureRoot> --from-events | diff - <fixtureRoot>/.aid-o/state/current-state.json"
  expected_exit: 0
```
```yaml
# AC: vendored plugin bundle matches the TS source (finding 7)
verification_pattern:
  type: cmd
  cmd: "bash packages/aid-lifecycle/scripts/check-vendored-bundle.sh"
  expected_exit: 0
```
```yaml
# AC: rollback never deletes the event log / overrides ledger (finding 2)
verification_pattern:
  type: cmd
  cmd: "bash tools/lifecycle-audit/tests/rollback-preserves-eventlog.sh"
  expected_exit: 0
```
(Full set — one per the 18 blocking AC below — authored in Phase 2/each phase.)

## Blocking acceptance criteria (18 — mapped)

1. 6 projects have canonical state w/ provenance + evidence quality — P5/P6. 2. Every plan has a lifecycle or
explicit `unknown`; none lost — P3/P6. 3. ≥1 open plans concurrently — P2/P3. 4. Archived/touched-historical
never active frontier — P2/P3 neg-control. 5. mtime alone never lifecycle — P3 neg-control. 6. Git merge alone
never whole-plan completion — P2 (split claim)/P3. 7. Closure debt distinct (`completed_unclosed`) — P2. 8.
Planned pause ≠ stale; age never changes lifecycle — P2. 9. Project concern w/o plan visible — P2/P3. 10.
Alias resolution deterministic+provenance — P3. 11. Conflict → `unknown/conflicting`, no random winner — P3.
12. Never deletes/rewrites historical evidence — P5 checksum. 13. Producer emits start/finish/pause/resume/
abort/archive/supersession + problem/decision closure — P4. 14. Idempotent producer/reconciler — P3/P4/P5. 15.
6 = oracle or approved deviation — P6. 16. Cockpit reads current-state without its own multi-source guessing —
P6 (+ no-reconciler-import test). 17. Missing current-state → `unknown`, not positive fallback — P6 neg-control.
18. Negative controls for known false-active + false-completed — P3/P4/P5. **+19 (new):** every successful
lifecycle operation has a reconstructible committed event — P4 chaos test. **+20 (new):** manifest reproducible
from the durable event log after deletion — P5.

## Protection of existing unmerged work (binding)

Commit `3b40e88` unmerged; `E-047-6-expected-screen-G.md` = golden oracle; the productization addendum is
complemented not overwritten; F1 `managerial-model.ts`/components/playbook/placeholder-tests NOT discarded,
NOT propagated to Screen B/Plan/C/D/E. After acceptance a deliberate decision picks reusable F1 contracts
(playbook + dictionary + presentation likely reusable; the lifecycle derivation in `deriveArchiveStatus`/
`classifyGroupLifecycle` is replaced by the manifest).

## Sequencing, effort, risk

Sequential P0→P6 (each gates the next). Total ≈ **30–39 person-days** (v2 adds Phase 0 packaging + the split
Phase 4 + backfill ledger). Highest risk: **Phase 2 (precedence)** + **Phase 4.4 (the closure command +
skill re-point into the live pipeline)** — mitigated by fixtures, negative controls, the `AID_LIFECYCLE`
flag, the split sub-steps, and the existing bats/integration suites.

## Pre-implementation gate

No implementation authorized. Requires: (a) PM approval of this plan; (b) **D-1 decision incl. Node-18 runtime
sign-off**; (c) Phase-1 `oracle.json` hand-approval; (d) plan id assignment (proposed P049). Only then does
Phase 0 begin.
