# E-047-6_7 REOPEN — Cockpit Productization Addendum

Binding addendum to **P047 (AID Cockpit MVP1)** and the Cockpit spec. Supersedes
the original E-047-6_7 acceptance criteria where they conflict. Status: **active
reopen** — E-047-7_7 paused until E-047-6_7 passes new acceptance.

## Why

The shipped Phase 6 was a technically-complete telemetry monitor, not a product.
Verified against live data, the managerial read-model leaks raw signals as titles,
lists ungrouped historical failures as current blockers, omits impact/action, and
the explanation layer leaves untranslated events + raw `{placeholders}`. Root cause
is the **backend Brief read-model + the original AC + GUI hierarchy** — not cosmetics.

Scope now permits changes to `packages/aid-contract`, `packages/aid-server`, and
`packages/aid-gui`.

## Product goal

From any screen the user learns within tens of seconds: what needs my decision /
what truly blocks progress and why / which projects+plans are healthy or at risk /
what phase they're in and what's running / what changed since last visit / what's
next / how audits, checks and delivery turned out. Managerial screens are primary;
technical identifiers, raw events and evidence live behind a detail expand.

## Binding decisions

### A) Lifecycle (evidence-based — NOT a time window)

Every managerial problem carries `lifecycle`:

- **active** — the newest authoritative evidence of the *same* problem still
  requires action. An unresolved decision is active even after a month.
- **resolved** — newer evidence shows the same root cause passed / was fixed /
  approved / merged / otherwise closed.
- **historical** — the EPIC/run ended or was archived and no open action remains.
- **stale** — still active, unchanged > 7 days. **Stays among current**, raised
  attention. (7 days means "stale", never "move to history".)

**Supersession requires evidence.** A newer EPIC in the same plan is NOT proof.
A problem may be marked resolved/superseded ONLY by: a newer run of the *same*
EPIC, an explicit declared relation, a successful follow-up proof, or a confirmed
prior-phase closure.

**Archived-with-unclosed-evidence.** An archived EPIC whose last run failed must
NOT render as a current blocker → it is `historical`, plus a distinct
inconsistency flag `archived_unclosed_evidence` so the anomaly is visible without
masquerading as an active blocker.

### B) Dění default filter (significant only)

Default view shows ONLY: decisions, blockers, escalations, gate failures,
significant audit/compliance results, EPIC/plan completion, significant state
change. Orchestration (`pipeline_start`, `gate_runner_*`, `brain_context_loaded`,
…) appears ONLY in the raw technical mode.

### C) Contract — ONE unified managerial type

`BriefItem` is extended into the single managerial type (no parallel
`ManagedProblem`). Technical screens consume `ActivityEvent`, `ComplianceFailure`
and the raw/view contracts.

Each managerial item carries:

| field | meaning |
|---|---|
| `humanTitle` | human Czech name (never snake_case) |
| `projectId` / `planId?` / `epicId?` / `runId?` | scope |
| `whatHappened` | plain-language what occurred |
| `whyItMatters` | impact / why the user should care |
| `whatBlocks` | what it blocks (null when it blocks nothing) |
| `recommendedAction` | what the user should do |
| `nextActor` | who/what is the expected next actor (`pm` / `aid` / `agent` / …) |
| `firstSeen` / `lastSeen` | first + last occurrence of this root cause |
| `occurrenceCount` | **count of distinct RUNS currently exhibiting this root cause** |
| `affectedEpics[]` | the EPICs those runs belong to (EPIC count derivable) |
| `rootCauseKey` | `projectId : signal : concreteKey` where concreteKey is the specific check / gate / reason (NOT just the generic signal) |
| `lifecycle` | `active` / `resolved` / `historical` / `stale` |
| `severity` | `blocking` / `warn` / `info` |
| `requiresDecision` / `isBlocker` | routing flags (one item, many views) |
| `relatedIds[]` | explicit links to related items |
| `evidenceRefs[]` | `{ label, href, kind }[]` — replaces single `evidenceHref` |
| `inconsistencyFlags[]` | e.g. `archived_unclosed_evidence` |

**No duplication.** A problem has ONE home. Precedence **decision > blocker**:
an item that both blocks and needs a decision lives once (as a decision, with
`isBlocker:true`); brief views filter the one deduplicated set; cross-references
go through `relatedIds`, never a second copy.

`Brief` gains a one-line `ecosystemLine` (Czech state summary) and exposes the
deduplicated managerial set; `blockers` / `decisionsNeeded` / `watchOuts` /
`nextUp` are projections of it, each item appearing once.

### A′) Archive evidence + F1/F2 staging (binding refinements)

- **`archiveStatus` is evidence-based tri-state**, never "absent from the active
  set": `archived` requires explicit proof (`tasks/archive/`, `runs/archive/`,
  task status, or another authoritative artifact); `active` = demonstrably active
  (live FSM state or a pending decision); `unknown` = unprovable → surfaced in a
  `needsTriage` bucket, NEVER filed as historical, NEVER posed as a confident
  current blocker.
- **F1 is a temporary stage** of THIS reopen. `resolvedEvidence` is always false
  in F1 — nothing is marked resolved without evidence. 7 days only adds `stale`;
  the problem stays active.
- **F2 is binding before DONE** (not backlog, not a later MVP). F2 evaluates
  NEWER runs of the SAME EPIC matched by the SAME `rootCauseKey`. "A newer run
  passed" is NOT a universal resolver — each signal has its own closure rule
  (`CLOSURE_RULES` in `managerial-model.ts`): gate→newer same-gate success;
  compliance→newer complete same-check result with no violation; audit→newer
  audit without the same blocking finding; merge→recorded PM decision/merge;
  precondition→subsequent successful transition.
- **One shared history source**: F2 reuses the scanner's per-EPIC `epic.runs`
  Map (already consumed by `compliance-rollup`) — NO second parallel resolver.

### D) Vertical-slice delivery

Order: contract → read-model → explanation layer → **Screen G over real data →
live PM acceptance of its content + hierarchy** → only then extend the same model
to Projekt/Plán, EPIC, Dění, Compliance. Safeguard against another
technically-complete-but-unreadable result.

## Blocking acceptance criteria

1. No visible `{placeholder}` on managerial screens.
2. No raw snake_case outside an expanded technical detail.
3. Duplicate problems grouped (root-cause).
4. Resolved/historical problems are NOT among current blockers.
5. Every blocker and decision carries impact + recommended action.
6. Real data produces a meaningful summary — not just green component tests.
7. Playwright verifies desktop + mobile and captures screenshots of all main screens.
8. **E-047-6_7 MUST NOT re-enter DONE without live PM acceptance over real projects.**
