---
id: IMP-232-maintenance
type: maintenance
risk: high
status: blueprint-v3
execution_mode: out-of-band-manual
do_not: "Do NOT run /aid-plan --epic on this plan. It is implemented directly (manual, staged commits), NOT through the AID EPIC pipeline — the pipeline is exactly what this plan repairs (bootstrap), and its implementer agents would edit the running orchestrator (aid-fsm.sh, aid-contract-validate.sh) mid-orchestration."
backlog_ref: IMP-232
supersedes_partial: AID-035 (plan-level closure, PARTIAL since P036)
target_release: v2.58.0 (single coordinated maintenance release; NOT a per-blocker patch)
scope: EXCLUSIVELY /opt/eco/projects/aid-orchestrator (WAN + same-numbered plans elsewhere are unrelated; WAN SHAs e655bb1/f00fc14 irrelevant)
created: 2026-07-13
revised: 2026-07-13 (v3 — folds re-review round 2: EPIC scope required/backlog + strict legacy grammar, two-phase delivery capture with serialized post-merge commit, §5.8 interruption/dirty-tree safety, backlog-after-closure policy, plan_manifest_sha canonicalization)
---

# IMP-232 — Canonical Plan-Level Closure + Legacy Reconciliation + per_step_scoping Precision

## 1. Problem, scope & authoritative state

Dogfooding P065 generation surfaced two guards that repeatedly block *legitimate*
work and force `--force-init` band-aids that only push the same pain to the next
EPIC/plan:

1. **`per_step_scoping` false positive** — `aid-contract-validate.sh` hard-fails a
   multi-step EPIC when every step's `allowed_paths` are byte-identical, reading a
   legitimate same-file sequential refinement (P065 EPIC 2: `dispatch` → validation
   → `verify`, all in `aid-c3-dispatch.sh`, `outputs_unique=3`) as the P057/P058
   broadcast bug.
2. **Cross-plan closure coupling** — `cmd_init`'s plan-level DONE gate hard-blocks a
   new plan when *any other* plan has an EPIC with `audit-report.md` but no
   `ca-review-complete` marker, deriving "done?" from scattered, gitignored per-EPIC
   markers that vanish on a clean clone.

Root gap (AID-035, partial since P036): **no canonical, durable, evidence-anchored
plan-level closure.** This is cheaper to fix systematically now than to keep paying
the administrative tax on every future plan.

**Scope is EXCLUSIVELY `/opt/eco/projects/aid-orchestrator`.** Same-numbered plans in
other repos (WAN) are unrelated; WAN SHAs `e655bb1`/`f00fc14` are irrelevant.

**Authoritative AID state at planning time:**
- **P061** — declares 6 EPICs, of which E1-E5 are `required` and E6 is explicitly
  `**EPIC 6 / Backlog**` (out-of-scope follow-up). E1-E3 merged + DONE, E4-E5 not yet
  realized ⇒ `active`; it closes at 5/5 required, with E6 recorded as `backlog`.
- **P064** — does not exist here (roadmap note only).
- **P065** — declares 7 EPICs; task files exist for E1+E2, E1 FSM = READY ⇒ `active`.

### Why out-of-band (the bootstrap)
`/aid-plan --epic` on this plan would hit the very `per_step_scoping` false positive
(steps edit `aid-fsm.sh` repeatedly) and the very cross-plan gate (P061 + P065 in
progress); `/aid-run` would have implementer agents rewrite `aid-fsm.sh` /
`aid-contract-validate.sh` **while the FSM orchestrates them**. So this plan is the
design + acceptance/audit blueprint; implementation is direct, in four staged
commits, as v2.57.2 was done. After release + independent audit, P065 continues the
official way (§9).

## 2. Goal
Ship **v2.58.0** — one tested release after which: legitimate same-file EPICs pass
`per_step_scoping` while real broadcast stays blocked; plan-level closure is
canonical, durable across clones, evidence-anchored, and CANNOT be "really done but
accounting-incomplete"; a new independent plan is never blocked by unrelated history;
`plan-reconcile` truthfully dorovnává legacy plans **without fabricating** anything;
`--force-init` reverts to emergency-only; all seven declared P065 EPICs pass a full
preflight with no scratchpad/fake reports/manual evidence.

## 3. Durable artifacts & identity (foundation)

Because prose plans live in gitignored `.aid-o/plans/`, closure state must NOT depend
on them at read time. Two small **git-tracked** artifacts carry durability:

### 3.1 Repo identity — `.aid-repo-id` (git-tracked)
- A once-generated stable UUID persisted in a git-tracked file at repo root
  (`.aid-repo-id`), so it is copied by clone AND by the eco-dev↔eco-prod mirror.
- Created on first `aid-*` run that needs it if absent; NEVER derived from the git
  remote URL (a mirror would then have two identities).
- Root-commit SHA is ONLY a legacy bootstrap fallback when the file is somehow
  absent; the resolved identity is then persisted into `.aid-repo-id`.
- Plan IDs are repo-local; identity is always `repo_id + plan_id`.

### 3.2 Plan lifecycle manifest — `docs/plans/lifecycle/P<NN>.yaml` (git-tracked)
Created at **plan acceptance / first-EPIC generation** — i.e. the durable denominator
exists BEFORE any closure. The prose plan stays gitignored. Contents:
```yaml
schema_version: aid-lifecycle-1.0
repo_id: <uuid from .aid-repo-id>
plan_id: P065
source_plan_sha: sha256:<hash of the .aid-o prose plan at manifest time>
declared_epics:               # ordered; each carries a mandatory scope
  - { id: E-065-1_7, scope: required }
  - { id: E-065-2_7, scope: required }
  - { id: E-065-3_7, scope: required }
  - { id: E-065-4_7, scope: required }
  - { id: E-065-5_7, scope: required }
  - { id: E-065-6_7, scope: required }
  - { id: E-065-7_7, scope: required }
depends_on_plans: []          # structured; the ONLY dependency source honored for hard-block
created_at: <UTC>
aid_version: <x.y.z>
```
- New plans MUST carry structured `declared_epics` (each with a mandatory
  `scope: required|backlog`) + `depends_on_plans` in the plan frontmatter; the
  manifest is generated from them (deterministic).
- The manifest is the **denominator source**. Counting task/evidence directories as a
  denominator is FORBIDDEN.
- **Scope semantics:** `required` EPICs form the closure denominator; `backlog`
  EPICs are recorded (denominator honesty) but NEVER block `closed`.
- **Legacy strict grammar (no fuzzy hint search):** for legacy plans without a
  manifest, EPIC declarations are parsed ONLY from unambiguous bold lines —
  `**EPIC N: …**` ⇒ `required`; `**EPIC N / Backlog: …**` ⇒ `backlog`; any other or
  ambiguous form ⇒ the whole plan is `legacy-unverifiable` (never a guess). EPIC IDs
  are derived deterministically (`E-0NN-i_K`).
- **Backlog-after-closure policy:** once a plan is `closed`, a `backlog` EPIC MUST
  NOT be activated under the closed plan. If it is ever done, it is promoted into a
  NEW active plan / backlog item; the closed plan's receipt is NEVER retroactively
  rewritten.

### 3.3 Closure receipt — finalized into `docs/plans/lifecycle/P<NN>.yaml`
The same git-tracked file gains a `closure:` block when the plan closes (§5). The
receipt re-embeds/finalizes `declared_epics` + per-EPIC provenance so closure is
self-contained even if the gitignored reports are later deleted:
```yaml
closure:
  state: closed | delivered-but-unreconciled | legacy-unverifiable | closing_pending_commit
  finalized_at: <UTC>
  aid_version: 2.58.0
  target_branch: main               # from config (§3.4), not hardcoded
  plan_manifest_sha: sha256:<hash of the manifest block above, committed & durable>
  epics:                            # one row per DECLARED epic id
    - epic_id: E-065-1_7
      delivery_sha: <merge SHA reachable from target_branch>
      reviewed_sha: <SHA the audit provenance attests>
      verdict: pass                 # auditor decision (§5.3)
      unresolved_blocker_count: 0
      waivers: [...]                # explicit; never conflated with an open blocker
      report_hashes: { audit: sha256:..., curator: sha256:..., simplifier: sha256:..., delivery: sha256:... }
      review_profile: <profile id>
      report_schema_versions: { audit: <v>, curator: <v>, ... }
```

**`plan_manifest_sha` canonicalization:** the hash covers ONLY the §3.2 manifest keys
(`repo_id, plan_id, source_plan_sha, declared_epics[ordered, with scope],
depends_on_plans, created_at, aid_version`), serialized canonically (fixed key order,
normalized whitespace), explicitly EXCLUDING the `closure:` block — so co-locating
manifest + closure in one file carries no circular-hash risk.

### 3.4 Target branch config
Add a real config key `target_branch` (in `orchestration.yaml`) with a documented
default of `main`. All "reachable from target branch" checks read it; nothing
hardcodes `main`.

## 4. Component 1 — `per_step_scoping` precision fix

**File:** `plugins/aid-orchestrator/scripts/gates/aid-contract-validate.sh` (Check 1,
`unique_outputs==1 || unique_allowed==1` at lines ~96-104).

**New logic (authoritative-block-first):**
1. If the source EPIC.md carries explicit per-step scope blocks
   (`<!-- step-N: files=[...]; ac=[...] -->`, consumed by `_aid_parse_scoping_line`
   / `_ac_block_count`), those blocks are **authoritative**: each generated step's
   `allowed_paths` must match its declared block. Match ⇒ PASS (identical
   `allowed_paths` across steps is legitimate when the blocks say so). Generated-step
   ↔ block mismatch ⇒ FAIL.
2. **R7 guard:** authoritative blocks that are THEMSELVES degenerately broadcast
   (all steps' block `files` byte-identical AND all `outputs` identical) do NOT
   auto-pass — they are still scrutinized as a potential source-level broadcast.
3. Legacy inputs with NO authoritative blocks: hard-fail ONLY when **both** `outputs`
   AND `allowed_paths` are byte-identical across all steps. A single-field match is
   NOT a hard fail (documented trade-off: a legacy `allowed_paths`-only broadcast
   with distinct outputs now PASSes; rule 1 catches it for block-carrying inputs).
4. Preserve genuine P057/P058 broadcast detection (it broadcasts BOTH fields).

**Mandatory regressions (all seven):**
| # | Input | Expected |
|---|-------|----------|
| R1 | same `allowed_paths`, different `outputs` | PASS |
| R2 | same `allowed_paths` AND `outputs`, exactly matching explicit per-step blocks | PASS |
| R3 | generated step conflicts with its explicit block | FAIL |
| R4 | legacy input, same `allowed_paths` AND `outputs` | FAIL |
| R5 | legacy input, only one field matching | PASS |
| R6 | original P057/P058 broadcast reproduction | FAIL |
| R7 | explicit per-step blocks that are themselves degenerately broadcast | FAIL (not auto-passed) |

Update the header contract (lines 14-19) to document authoritative-block-first + the
two-independent-stages assumption (`aid-plan-to-epic.sh` block-gen vs
`aid-epic-to-json.sh` allowed_paths-gen). Register in the enforcement registry.

## 5. Component 2 — IMP-232 closure/lifecycle model

### 5.1 States
```
active                     → some declared EPIC not yet delivered+accepted
delivered-but-unreconciled → all declared EPICs delivered+accepted, no committed receipt
closing_pending_commit     → receipt prepared+staged, not yet committed & reachable
closed                     → committed receipt reachable from target_branch; all EPICs delivered+accepted
legacy-unverifiable        → evidence missing/ambiguous/conflicting (incl. inconsistent)
```
State is **derived from evidence** (git + reports) and the committed receipt; the
local cache only materializes it.

### 5.2 `delivered` predicate (two-phase capture, strict historical fallback)
Delivery binding is captured in TWO phases so the FSM never commits or dirties the
tree, and `delivery_sha` is bound only when it actually exists (post-merge):
- **Phase 1 — pre-merge, in the FSM (`done-advance`):** record ONLY what is available
  and to the existing per-run evidence (gitignored, no git-tracked write, no dirty
  tracked files): `reviewed_sha`, the EPIC head/tree, and review provenance. The FSM
  commits nothing.
- **Phase 2 — post-merge, in the orchestration layer (on `target_branch`):** verify
  the merge is reachable from `target_branch`, bind `delivery_sha` (now that it
  exists), update the git-tracked lifecycle manifest, and make the standard
  orchestration metadata commit. **Only the committed record is permanent delivery
  proof.** Post-merge metadata commits are **serialized** (a lock) so two concurrent
  merge processes cannot overwrite each other.
- **Interrupt between merge and the metadata commit:** the code IS delivered but the
  EPIC is `delivered-but-unreconciled`. Recovery safely COMPLETES the post-merge
  record — it MUST NOT re-merge and MUST NOT claim the EPIC is not delivered.
- **Historical EPICs** (no Phase-2 recorded binding): the commit message may ONLY
  locate a
  *candidate*, never serve as proof. `delivered` then requires ALL of:
  - the merge is reachable from the configured `target_branch`;
  - it has the expected parent topology (a real 2-parent merge);
  - the candidate is UNAMBIGUOUS for the EPIC (multiple candidates ⇒ `legacy-unverifiable`);
  - the `reviewed_sha` from audit provenance matches the delivered EPIC head/tree;
  - reports are not stale vs. the delivered content;
  - any declared scope matches the change.
  - "second parent touched the declared files" ALONE is insufficient. Missing
    reviewed-head provenance OR multiple candidates ⇒ `legacy-unverifiable`.

### 5.3 `reviewed-and-accepted` (distinct from `review-completed`)
A FAIL report is a *completed* review but NOT closure-eligible.
- **Auditor is the closure verdict:** `audit-report.schema.json` `blocking_findings`
  (mechanical from `severity`) == 0, known schema version, references the correct
  `reviewed_sha`, fresh vs. delivered content. Accepted waivers explicitly recorded
  and NEVER conflated with an open blocker.
- **Curator / simplifier / delivery are presence + freshness artifacts only** (they
  have no machine verdict contract yet: `curator.schema.json` has only
  `proposal_status`, there is no simplifier schema, delivery has no verdict). They
  must be PRESENT (per the run's review profile) and FRESH vs. delivered content, but
  their *content* is not a pass/fail gate until they gain their own verdict contract.
- Prefer structured fields; do NOT parse free English when a structured field exists.
  Legacy reports → conservative adapter; unclear ⇒ `legacy-unverifiable`, never PASS.

### 5.4 Denominator
= the ordered `declared_epics` with `scope: required` from the pinned lifecycle
manifest (§3.2). `backlog` EPICs are recorded but excluded from the denominator, so a
plan can reach `closed` without them (e.g. P061 closes at 5/5 required; E6 stays
`backlog`). NEVER the count of task / evidence directories. The receipt stores
`plan_manifest_sha` so a later plan edit cannot retroactively change the required set
(mismatch ⇒ re-verification).

### 5.5 `plan-close` orchestration (receipt-first, fail-closed, no hidden commit)
1. Resolve the lifecycle manifest → declared EPIC set + hash.
2. For each declared EPIC evaluate `delivered` (§5.2) + `reviewed-and-accepted` (§5.3).
3. If ANY fails → emit the precise reason, write NO `closed`/`delivered` state.
4. If ALL pass → build the receipt payload and write it to the git-tracked file
   (staged), set state `closing_pending_commit`. **Low-level `plan-close` performs NO
   hidden git commit.**
5. The standard **plan-boundary orchestration** (higher layer) commits the receipt,
   then runs `finalize/verify`: state becomes `closed` ONLY when the receipt is
   committed AND reachable from `target_branch`.
6. Ordering invariant: **receipt (canonical) first, local cache second.** A
   cache-only `closed` is ALWAYS invalid. A staged-but-uncommitted receipt is NOT
   `closed`.
7. Compatibility: during the transition, `plan-close` DUAL-WRITES the legacy
   `ca-review-complete` marker AND the receipt; all readers switch to receipt-first
   with the marker as legacy fallback.

### 5.6 Local cache — `.aid-o/work/closure/P<NN>.yaml` (gitignored)
A fast, rebuildable runtime index. NOT canonical; auto-rebuilt from the committed
receipt (+ evidence) when missing. Cache × receipt × evidence conflict ⇒
`legacy-unverifiable`/`inconsistent`, never auto-`closed`.

### 5.7 Clean-clone precedence
On a clean clone the gitignored reports are absent. A **committed, self-contained
receipt is authoritative** — its absence-of-reports is NOT a conflict. If the
original reports DO still exist, verify them against the receipt's `report_hashes`.
Only a genuine hash/SHA/topology contradiction ⇒ `legacy-unverifiable`.

### 5.8 Interruption safety (no orphaned dirty tree; idempotent recovery)
An interrupted close/reconcile must NEVER leave a dirty worktree/index that
permanently blocks the next `init`.
- All git-tracked writes (manifest + receipt) happen ONLY in the orchestration
  layer's commit — never inside the FSM. Prefer an **isolated temporary index /
  worktree** (or an equally safe mechanism) for staging the receipt commit over
  touching the user's index; NEVER roll back user changes.
- Recovery is idempotent: an interrupted close re-derives from evidence to
  `delivered-but-unreconciled`; re-running `--apply` resumes — it either reuses a
  valid staged receipt or rebuilds it, then commits + finalizes. An interrupt
  between merge and the metadata commit (§5.2) completes the post-merge record
  without re-merging.
- The orchestration unambiguously recognizes ITS OWN in-flight
  `closing_pending_commit` artifacts (by content/marker) and safely auto-completes
  them; anything it cannot positively attribute to itself is left untouched.
- After a fault at ANY of these points — before receipt write, after tmpfile
  create, after worktree write, after `git add`, after commit but before
  finalize/cache-update — the invariant holds: EITHER worktree AND index are clean,
  OR the orchestration recognizes and safely completes its own change. `init` is
  never permanently blocked by an orphaned staged receipt.

### 5.9 Implementation notes (final re-review mediums)
- **Serialization lock (§5.2):** a concrete `flock` on a repo-local path
  (`.aid-o/work/closure/.lock`) guards the post-merge metadata commit. Worst case is
  retry/conflict, never a bad `closed` (closed still requires committed + reachable).
- **Phase-2 delivery bindings home:** the manifest gains a `deliveries:` block (per
  EPIC `{delivery_sha, reviewed_sha, merged_tree, bound_at}`) written in Phase-2.
  `plan_manifest_sha` (§3.3) covers ONLY the §3.2 identity/denominator keys and
  EXCLUDES both `deliveries:` and `closure:` — so binding/closing never churns the
  denominator hash.
- **State enumeration:** the first-class lifecycle states are the five in §5.1;
  `not_found`/`no_plan` (§6.3) is a reconcile RESULT for an absent plan (not a stored
  state); `inconsistent` is an alias of `legacy-unverifiable`; `abandoned` is derived
  advisory only (never a hard block, §6.2).

## 6. Component 3 — Legacy reconciliation + migration

**New CLI:** `aid-fsm.sh plan-reconcile P<NN> [--dry-run | --apply] [--quiet]` (or
`aid-plan-reconcile.sh`).
- `--dry-run` (default): classify from evidence; print state + per-EPIC evidence
  table + what `--apply` would write. Mutates nothing.
- `--apply`: if and only if evidence proves a receiptable state, write the manifest
  (if missing) + receipt via the same receipt-first path.
- **Metadata-only (hard):** reconcile reads ONLY existing commits/reports/evidence.
  It NEVER fabricates a report/delivery, NEVER marks an in-progress plan `closed`,
  and NEVER edits a plan's steps, acceptance criteria, EPICs, or content. An active
  mid-flight plan stays `active`. A successful legacy migration creates the tracked
  lifecycle manifest + receipt metadata but leaves the original prose plan untouched.
- **Legacy denominator:** derived ONLY by a STRICT parser over unambiguous EPIC
  headers / numbering, producing exact deterministic IDs. Any ambiguity ⇒
  `legacy-unverifiable`, never a guess.
- Every auto-reconcile leaves an audit trail (timeline event + the git receipt commit
  is the durable record).

### 6.1 `status:` double-truth
The legacy frontmatter `status:` (`draft`/`ready`) already diverges from reality.
- Lifecycle state is **derived** (from manifest + receipt + evidence). Plan-file
  `status:` is demoted to NON-authoritative; readers stop trusting it.
- NO auto-mirror back into legacy plan files (that would edit them, violating AC14).
- A stale `status:` NEVER overrides the derived state and is NEVER a migration
  precondition.

### 6.2 Cross-plan gate rewrite (D1) — remove global hard-block from BOTH regions
**File:** `aid-fsm.sh cmd_init` — the plan-level DONE gate exists in TWO regions:
the force-override capture (~2118-2133) AND the actual block (~2183-2199). Both are
removed.
- **No hard block** based on any *other* plan's state.
- Hard block ONLY when the initializing plan declares a **structured**
  `depends_on_plans: [P<M>]` whose target's derived state != `closed`. Legacy prose
  `depends_on:` is advisory-only (never a hard block) — this preserves AC14.
- Emit ONE init advisory: a single actionable summary of `delivered-but-unreconciled`
  plans (+ count of `legacy-unverifiable`) with the exact `plan-reconcile` command.
  Suppressed under `--quiet`/CI. Unrelated `abandoned`/`legacy-unverifiable`/
  `inconsistent` plans NEVER create a global hard block.
- Untouched: branch-enforcement, clean-worktree, duplicate-state, rogue-commit
  (pre-commit) guards. `--force-init-reason` remains the audited emergency override.

### 6.3 Concrete migration cases (authoritative AID state)
- **P061 → `active`.** Denominator = 5 `required` (E1-E5); E6 is `backlog`. E1-E3
  delivered, E4-E5 not. No receipt; not `closed`/`delivered`; done EPICs/steps/reports
  untouched; E4-E5 remain normally completable; closes at 5/5 required with E6 kept as
  recorded `backlog` (post-closure E6 realized only in a NEW plan). `status: ready`
  non-authoritative.
- **P064 → `not_found`/`no_plan`.** Does not exist; reconcile synthesizes NO state; a
  sequence gap has no lifecycle meaning; a future P064 is authored under the new
  model.
- **P065 → `active`.** 7 declared EPICs; E1/E2 artifacts byte-preserved; PAUSED during
  IMP-232; after release, E2's unfinished generation resumes via the sanctioned
  resume/init path, then E3-E7 generate officially; receipt only after 7/7.
- **Positive close test = ISOLATED fixture** with complete merge+review evidence for
  every declared EPIC. NEVER reclassify live P061/P065 for a test.

## 7. Implementation — four separate, independently verifiable commits
1. **`per_step_scoping` precision fix** — Component 1 + R1-R7 + header/registry.
2. **IMP-232 lifecycle/closure model** — §3 (identity file, lifecycle manifest with
   per-EPIC `scope`, target_branch config) + §5 (states inc. `closing_pending_commit`,
   two-phase delivery capture [pre-merge FSM evidence / post-merge serialized
   orchestration commit], receipt-first `plan-close` with no hidden commit +
   orchestration commit/finalize via isolated temp index, dual-write marker,
   clean-clone precedence, §5.8 interruption safety) + §6.2 gate rewrite + closure
   unit tests.
3. **Legacy reconciliation + migration** — §6 `plan-reconcile` `--dry-run`/`--apply`,
   strict legacy grammar (required/backlog), safety invariants, repo-identity +
   two-repo isolation tests, §5.8 fault-injection tests (5 interrupt points),
   P061/P064/P065 migration + isolated positive-close fixture tests.
4. **Tests, docs, changelogs, version bump** — enforcement-registry, extending-aid
   docs, both CHANGELOGs, 8 version files → **v2.58.0**.

Each commit lands green on the full suite before the next.

## 8. Pre-release preflight (before the v2.58.0 tag)
- Full **dry-run of all seven DECLARED P065 EPICs** through generation + contract +
  FSM + queue + branch-enforcement.
- Confirm legitimate variants pass: same-file refinement (P065 EPIC 2); multiple
  plans in progress (P061 + P065 independent).
- Any further false positive is analyzed **holistically** first — NOT patched
  EPIC-by-EPIC.

## 9. After release — resume P065 the official way
Install v2.58.0 → re-validate P065 E2's unfinished generation via the sanctioned
resume/init path → generate E3-E7 officially → the seven-EPIC preflight passes here →
P065 closes via the IMP-232 mechanism after all seven are delivered + review-accepted.

## 10. Acceptance Criteria
- **AC1** `per_step_scoping`: R1-R7 behave as tabled; real P057/P058 broadcast FAILs.
- **AC2** Committed receipt is self-contained: a simulated clean clone (local cache +
  gitignored reports deleted) reproduces identical `closed` state from the committed
  receipt alone.
- **AC3** `plan-close` is receipt-first + fail-closed: an injected mid-write failure
  leaves NO `closed` anywhere; a cache-only `closed` is rejected as invalid; a staged
  but uncommitted receipt reads as `closing_pending_commit`, not `closed`.
- **AC4** Denominator = declared EPIC IDs from the pinned lifecycle manifest; adding
  an EPIC to the prose plan after closure does not flip an existing receipt
  (`plan_manifest_sha` mismatch ⇒ re-verification).
- **AC5** `delivered` rejects a renamed/fabricated merge whose message names the EPIC
  but whose reviewed-head provenance/topology does not bind it; multiple candidates ⇒
  `legacy-unverifiable`.
- **AC6** `reviewed-and-accepted` rejects a FAIL audit, a stale audit
  (`reviewed_sha` ≠ delivered), and unresolved blocking findings; accepts a clean
  audit with an explicitly-recorded waiver; curator/simplifier/delivery are enforced
  as present + fresh only.
- **AC7** P061 derives `active` — denominator = 5 `required` (E1-E5, E4-E5 pending),
  E6 recorded as `backlog`; no receipt written; it would reach `closed` at 5/5.
- **AC8** An ISOLATED complete-evidence fixture plan reconciles to a truthful
  `closed` without touching any live plan.
- **AC9** A new plan `init`s with NO hard block from any unrelated plan's state; hard
  block occurs only for an unclosed **structured** `depends_on_plans` target; legacy
  prose `depends_on` never hard-blocks.
- **AC10** Init advisory is a single actionable summary, suppressed in CI.
- **AC11** `plan-reconcile` never fabricates and never closes an in-progress plan;
  every auto-reconcile leaves an audit trail.
- **AC12** Branch/worktree/rogue-commit guards unchanged (regression-covered).
- **AC13** All seven DECLARED P065 EPICs pass the §8 preflight with no force-init,
  scratchpad, fake reports, or manual evidence edits.
- **AC14** Reconcile is metadata-only: a plan's steps/AC/EPIC files are byte-identical
  before/after `--apply`; an active mid-flight plan stays `active`.
- **AC15** `status:` is non-authoritative & never auto-mirrored into legacy plans; a
  stale `status` never overrides the derived state and is never a migration
  precondition.
- **AC16** `plan-reconcile P064` (absent) returns clean `not_found`/`no_plan` and
  synthesizes NO state.
- **AC17** Repo identity: same identity after clone/mirror (git-tracked `.aid-repo-id`
  persists); two unrelated repos differ; same-plan-ID (`P061`) isolates across two
  repos with zero cross-contamination.
- **AC18** New plans carry structured `declared_epics` (each with `scope:
  required|backlog`) + `depends_on_plans`; the git-tracked lifecycle manifest is
  created at plan acceptance / first-EPIC gen (the durable denominator exists before
  closure); the legacy strict grammar maps `**EPIC N: …**`→`required`,
  `**EPIC N / Backlog: …**`→`backlog`, anything else ⇒ `legacy-unverifiable` (no
  fuzzy hint search).
- **AC19** Delivery is two-phase: `done-advance` writes reviewed_sha/head/tree/
  provenance to run evidence with NO git-tracked write and NO dirty tree; a post-merge
  orchestration step binds `delivery_sha` (reachable from `target_branch`) and commits
  the manifest under a serialization lock; an interrupt between merge and commit yields
  `delivered-but-unreconciled` and recovery completes the record without re-merging or
  claiming non-delivery.
- **AC20** Fault-injection at each of {before receipt write, after tmpfile create,
  after worktree write, after `git add`, after commit before finalize/cache-update}
  leaves EITHER a clean worktree+index OR an orchestration that recognizes and safely
  completes its own `closing_pending_commit` change; a subsequent `init` is never
  blocked by an orphaned staged receipt; user changes are never rolled back.
- **AC21** Backlog-after-closure: a `backlog` EPIC cannot be activated under a
  `closed` plan; realizing it requires a NEW plan and never retroactively rewrites the
  closed plan's receipt.

## 11. Independent audit (post-implementation, required)
Adversarial auditor confirms, with explicit sign-off:
1. The original P057/P058 broadcast bug is still blocked.
2. P061 is NOT falsely closed (stays `active`, E4-6 pending).
3. An isolated complete-evidence fixture reconciles truthfully to `closed`; NO live
   plan (P061/P065) is reclassified for a test.
4. A new plan is not blocked by unrelated historical administration.
5. Plan identity is repo-local + stable across clone/mirror.
6. All seven DECLARED P065 EPICs pass the complete preflight.

## 12. Out of scope
- Auto-generating/back-filling any missing review report (forbidden).
- Retiring `--force-init` (kept as audited emergency path).
- Parallelism re-enable (separate track).
- Changing branch-enforcement / rogue-commit semantics.
- Giving curator/simplifier/delivery a machine verdict contract (future; here they
  are presence+freshness only).

## 13. Risks
- **R-a** Editing the orchestrator — mitigated by out-of-band manual staging +
  full-suite green per commit + §8 preflight before release.
- **R-b** `delivered` binding depends on git history for legacy EPICs; squash/rebase
  workflows weaken it — record-at-merge (new EPICs) + the receipt's durable per-EPIC
  provenance are the fallback; strict historical predicate returns
  `legacy-unverifiable` rather than guessing.
- **R-c** Legacy-adapter over-conservatism may classify a genuinely-done old plan as
  `legacy-unverifiable` — acceptable (safe default); reconcile reports exactly what
  evidence is missing (never fabricated).

---
**Last Updated:** 2026-07-13
