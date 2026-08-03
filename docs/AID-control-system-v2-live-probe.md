# AID Control System v2 - live usage probe

Status: proposed operating mode
Created: 2026-07-01
Source: field report from real AID v2.50.1 usage during a multi-EPIC plan run

## Purpose

The Control System v2 work should not rely only on planned fixtures and self-contained
EPIC evidence. AID is now large enough that some failures appear only when another
agent uses the latest AID version on a real plan.

This probe is a temporary observation mode:

1. Let a normal implementer agent run AID on real work.
2. A separate observer session watches the run from outside the implementation context.
3. The observer records friction, false-green risk, confusing instructions, stale
   evidence, overwritten evidence, and undocumented requirements.
4. Findings go to `docs/plans/2026-06-29-BACKLOG.md` with origin date and source.
5. After several EPICs/plans, run a dedicated AID cleanup/refactor session.

The probe must not turn every observation into an immediate fix. The goal is to find
patterns before changing the control system again.

## Runbook

**Observer role, not implementer:**

- The observer never implements fixes, never touches the branch under
  observation, and never deletes or overwrites evidence.
- If active evidence corruption or a hard blocker is found, stop and flag the PM
  immediately instead of continuing to watch silently.
- Otherwise, findings are only recorded as OBS entries (see Probe Output Format)
  — no live intervention in the observed run.
- The observer tracks AID control-system process behavior, not project
  implementation quality. Skip findings that are only about implementation
  quality unless they are also relevant to AID control-system behavior.

**What to check, continuously — not just from transcript:**

- `git log` / `git status` on the branch under observation
- `.aid-o/work/evidence/**`
- `fsm-state.yaml`
- `plan.json`
- `run.md`
- `verifier-output-*`
- `gates_report.json`
- `delivery-gate.json`
- audit / curator / reporter outputs
- pipeline/docs text vs actual script behavior

Check local on-disk state directly and periodically. The implementer's transcript
is a supplementary signal only, not the primary source.

**Per-run setup:**

- Observed plan/EPIC: filled in at the start of each run
- AID version: verified from repo HEAD/CHANGELOG at run start, never assumed
- Observed worktree/branch: discovered by the observer from `git worktree list`,
  `git status --short --branch`, and `fsm-state.yaml branch`, not assumed from
  the PM transcript.
- Evidence root: discovered from `.aid-o/work/evidence/{epic_id}/{run_id}/`
  and checked against `fsm-state.yaml`, `plan.json`, and the active branch.

If a prepared run exists but its branch is not checked out anywhere, this is a
baseline observation, not an OBS finding by itself. It becomes a finding only if
the controller proceeds using the wrong branch/worktree, writes evidence under
the wrong run, or reports progress that the on-disk FSM does not show.

**Continuous polling mode:**

The observer should actively poll local state. Do not wait only for PM pings or
the implementer's transcript.

Default cadence:

- every 5-10 minutes while the run is active,
- immediately after visible FSM/gate/checkpoint activity,
- immediately after a new commit,
- immediately after the implementer claims DONE / PASS / MERGE readiness.

Each poll should be cheap and read-only. The observer should capture only the
delta since the last poll unless a stop condition appears.

Minimum poll checklist:

- current branch and worktree mapping (`git worktree list`, `git status --short --branch`)
- latest commits since run base (`git log --oneline --decorate`)
- FSM state, `current_step`, `total_steps`, `done_phase`, `base_commit`, branch
- `timeline.jsonl` tail and new event types
- newly created/modified evidence files and their mtimes
- verifier outputs and whether they match the expected checkpoint names
- gate reports: `overall`, required vs optional failures, command exit codes
- protocol-v2 JSON artifacts: `revision.head_sha`, `freshness`, `status`, `verdict`
- delivery/audit/curator/reporter artifacts if present
- whether any old evidence file was overwritten after a later checkpoint
- whether docs/instructions used by the agent match the scripts that enforced the step

**"Significant state" means:**

- an FSM transition
- a CP2 / CP3 / CP4 / CP5 checkpoint
- a gate run
- creation or change of an evidence artifact
- a precondition fail
- a force override
- a merge / release / plan-close decision
- the agent visibly hesitating over an unclear instruction
- documentation saying one thing while a script does another

**When to write an OBS entry:** write to `docs/plans/2026-06-29-BACKLOG.md` immediately
once a finding is confirmed. An unconfirmed suspicion stays as a working note
in the observer report only — it does not become a backlog item until
confirmed.

**Working-notes persistence (lesson from 2026-07-02):** keep all unconfirmed
suspicions, active watch items, and positive control moments in a persistent
observer-working-notes file (session scratchpad or equivalent), not only in
conversation memory. Each poll re-reads the watch items; each report updates
the file. This survives context compaction and lets a follow-up session resume
the probe without losing the pre-confirmation state.

**Record positive control moments too:** when an enforcement mechanism
demonstrably works (a precondition blocks an invalid advance, a stub is
rejected, append-only history enables detection), record it in the working
notes as calibration. The cleanup session needs to know what must NOT be
broken as much as what must be fixed.

**Proactive trap checks:** when a new EPIC's plan.json/evidence appears, check
it immediately against already-confirmed OBS patterns (declared-but-undefined
gates, reused run_ids, CP3 freshness exposure) instead of waiting for the
failure to replay. A recurrence confirmed from static state counts toward the
cleanup trigger the same as an observed replay.

Confirmation threshold:

- Confirm immediately when the observer can point to a file, command output, or
  git state proving the issue.
- Keep as working note when the only source is transcript wording, missing future
  activity, or a state that may still be normal setup.
- Promote a repeated working note to confirmed when the same friction happens in
  two independent checkpoints/EPICs even if each instance was individually
  recoverable.

**When to stop the run and flag the PM immediately:**

- active evidence corruption
- an existing valid evidence file gets overwritten
- a false-green gate/release result
- stale evidence used as release proof
- a branch/merge situation that risks losing work
- a hard blocker that prevents the run from continuing

**Report format, after each significant state:**

1. What happened
2. Whether the AID process worked / failed / was confusing
3. Whether an OBS finding results
4. Whether the observer needs to stop and flag the PM

**What the observer is trying to improve in AID:**

The probe is successful when it reveals how AID itself should be simplified,
made stricter, or made less confusing. Prioritize observations that help improve:

- evidence integrity: stale, overwritten, non-canonical, or unauthenticated evidence
- checkpoint ownership: old CP aliases vs new C0-C4 mechanisms conflicting
- script/doc alignment: instructions that do not match enforced behavior
- branch/worktree safety: wrong branch, stale branch, merge ambiguity, lost work risk
- verifier independence: fake, reused, self-written, or under-specified reviews
- false-green prevention: reports that say PASS while required proof is missing
- step/run identity: 0-index vs 1-index, plan/run/EPIC mismatch, ambiguous file names
- release semantics: per-EPIC vs per-Plan ambiguity, stale evidence used for release
- performance/cost: checks that look hung, repeat wastefully, or hide timeouts
- GUI/read-model readiness: whether evidence has enough stable fields for future AID Cockpit views
- PM communication: summaries that hide important caveats or require source-code archaeology

Do not spend observer attention on product-level bugs unless they expose one of
the AID control-system issues above.

**Observer commit discipline (lesson from 2026-07-02):**

The aid-orchestrator repo checkout is shared with other sessions, including AID
runs executed on the AID repo itself. Before every observer commit (OBS entries,
runbook updates), verify with `git status --short --branch` that the checkout is
on `main`. If a `task/*`/`epic/*` branch is checked out, a parallel AID run owns
the checkout — do not commit there and do not leave uncommitted edits in it;
defer the write until the checkout returns to `main`, or flag the PM. (Incident:
an OBS commit landed on `task/E-057-1_2/main`; recovered by fast-forwarding
`main` to the commit since its parent was the `main` tip.)

**Read verdicts, not just file presence (lesson 2026-07-08):** a new artifact
in the evidence dir is not yet a signal — open it. Check `verdict`, `status`,
`overall`, `ready`, `findings[]`, and internal consistency (e.g. a
delivery-gate `status: fail` with zero failing checks and empty findings, or
two contradictory `freshness` fields in one JSON). An artifact that cannot
explain its own verdict without source-code archaeology is itself a finding.

**Record/reality drift check (lesson 2026-07-08):** at every EPIC start and
before every CP3, compare fsm-state `base_commit` against the actual
`git merge-base <task-branch> main`. Silent drift between recorded state and
git reality is a recurring family (5 instances); verifiers/tools compensating
with the real base is a positive moment worth recording, but the drift still
counts.

**Release watch does not end at merge (lesson 2026-07-08):** after a
merge/release advance, keep watching: done-advance events (incl. fail+retry
visible only in timeline), version tag creation, push to origin, and the
plugin-update rollout to consumer projects. Each of these has independently
stalled or been forgotten in observed runs.

**Self-refreshing poll prompts (multi-probe mode):** each probe's scheduled
poll prompt carries its own state summary. When the observed state changes
materially (FSM phase change, new EPIC, cadence change), replace the job with
an updated prompt instead of letting the next poll run on stale context.
Cadence defaults: 6 min while active; thin to 15-30 min after 5 consecutive
no-ops; restore 6 min on first resumed activity.

**Flush discipline (extends observer commit discipline):** the moment the
shared checkout returns to `main`, flush ALL deferred writes accumulated in
the working notes — not only the finding that triggered the check. Mark
flushed sections in the working notes with the commit hash so a resumed
session knows what is already in the BACKLOG.

**PM relay pattern:** when the PM relays an implementer request (e.g. a
--no-verify approval), the observer answers with a concrete recommendation
plus the relevant OBS tally/context — not just a description. The PM decides;
the observer's job is to make the decision cheap and the bypass loud
(explicit reason in the commit message body).

**Bookkeeping staleness check (lesson 2026-07-09):** delta-polling (git/FSM/
evidence-file mtimes) catches NEW activity but not STALE secondary status
descriptions — `active.md` prose, `queue.yaml` per-EPIC `status:` field, task
file YAML frontmatter (`status:`, `runs_completed:`) — that silently keep
describing an earlier moment of the EPIC after the canonical `fsm-state.yaml`
has moved on, because nothing forces them to refresh. At every poll where
`done_phase` or `state` changes, cross-check these secondary artifacts
against `fsm-state.yaml` and flag mismatches. (Found by the PM's own local
check on WAN P059/E-059-1_2, not by the probe — a real methodology gap, not
a one-off.)

**Proactive branch-ancestry check on parent DONE/merge, not just at child
EXECUTE start (lesson 2026-07-09):** the moment a multi-EPIC plan's EPIC N
reaches DONE/merges to main, immediately check whether EPIC N+1's task
branch (if it already exists) has been rebased/re-based onto that merge —
don't wait for EPIC N+1's own EXECUTE start to notice it's still sitting on
the pre-merge base. This is the same record/reality drift family as
`fsm-state.yaml base_commit` (5+ instances tracked 2026-07-08) one layer up:
branch ancestry itself, before FSM even inits. Same failure mode as the P060
precedent.

**Known blind spots — explicitly out of scope for a disk-only observer
(logged 2026-07-09, PM asked directly):** three classes the probe
structurally cannot see and should stop being asked to infer from disk
alone:
1. Aggregate evidence-quality error rates across EPICs ("X% of EPICs have
   wrong evidence at DONE") — the probe does spot-checks and recurrence
   tallies, never a systematic audit computing a rate across all evidence
   dirs. Doable in principle (batch-read `.aid-o/work/evidence/**`), not
   part of the current continuous-poll methodology — would need a dedicated
   audit pass, not a live poll.
2. Whether a merge happened after explicit PM consultation vs. was
   self-approved — the probe only sees the disk outcome (a merge commit
   exists, possibly with "PM MERGE rozhodnutí" in the message) and cannot
   verify an actual back-and-forth occurred; it has no visibility into the
   implementer session's own conversation.
3. Whether Reporter/Simplifier stage output actually reaches the PM in
   chat — the probe only confirms these stages produced disk artifacts
   (screenshots, proposal reports), never whether that content was relayed
   to the PM conversationally. Structurally invisible to a session reading
   only git + filesystem.
If any of these three matter, they need a different observation method
(conversation-transcript review, or an explicit PM-side confirmation step),
not an extension of this disk-polling runbook.

**Recovering from a deleted/untracked evidence file (lesson 2026-07-09):**
if `docs/plans/2026-06-29-BACKLOG.md` or this runbook itself goes missing from disk
(e.g. a merge conflict resolves by deleting a file that a `.gitignore`
change untracked earlier), do not silently start a fresh file. First check
`git log --all --oneline -- <path>` for the last commit that touched it,
recover the content with `git show <commit>:<path>`, confirm it has the
expected recent sections (grep for known recent headers), THEN restore it to
disk and continue appending — this preserves full history instead of
starting over. Flag the deletion to the PM before assuming intent either
way; a `.gitignore` change untracking a directory does not, by itself,
delete already-tracked files from disk or history — an actual `rm`/merge
conflict resolution is a separate, more consequential step worth confirming
was intentional.

**C4 release-decision observability contract (PM-defined, 2026-07-09):** once
P059 Phase 2 (AID E-059-2, C4 dual-run core) lands — and at EVERY release/
plan-close observed after that — check these as hard expectations, not
nice-to-haves. Each is a disk-observable check; a miss is a finding:

1. `release-decision.json` exists in run evidence and contains ALL of:
   `release_ready`, `merge_mode` (manual|auto|blocked), `pm_brief_required`,
   `evidence_verified_at_head`, `reporter_status`, `reporter_reason`,
   `summary_for_pm`. A missing field = finding (schema gap), not a skip.
2. Auto-merge must not bypass the PM brief: if a merge commit exists and
   `merge_mode: auto`, a machine-stored human-readable brief artifact
   (pm-decision-brief) MUST also exist on disk. Auto-merge without a stored
   brief = finding, even if the merge itself was correct.
3. Reporter absence must not be silence: `reporter_status` must be exactly
   one of `pass` / `failed` / `missing` / `not_applicable` (with
   `reporter_reason`, e.g. `not_plan_boundary`). No field + no artifact +
   no reason = finding. The probe's own blind spot (can't see chat) is
   irrelevant here — the CONTRACT is that the status lives on disk.
4. Post-merge evidence freshness: after the final merge commit, either
   (a) evidence was re-verified at the new HEAD (fresh verification
   artifact whose head_sha == post-merge HEAD), or (b) release-decision
   says `evidence_verified_at_head: false` AND the merge is not presented
   as "verified". Stale evidence + verified claim = false-green finding
   (OBS-03 family).
5. Public/private hygiene: `.aid-o/reports/` delivery/boundary reports must
   NOT be committed git artifacts (local evidence only). Check
   `git ls-files .aid-o/reports/`. Baseline 2026-07-09: WAN has 5 committed
   (P039/P058×2/P060×2) — pre-existing practice this contract reverses;
   tally recurrences after C4 lands.
6. Simplifier — same rule as Reporter: it is a plan-boundary stage. If it
   did not run at a plan-close, an explicit status must exist
   (`not_applicable` for per-EPIC release / `missing` / `failed` / `pass`)
   — silence = finding. Observed positive precedent: WAN P060 ran it with a
   dedicated `verifier-output-cp4-simplifier-validation.md` re-verify;
   that's the pattern to pin.

**After each completed run:** update this Runbook section with anything that
made the next round of monitoring more accurate — additional artifacts worth
checking, a sharper definition of "significant state", recurring false
positives to filter out, etc. This section evolves; it is not a fixed
checklist.

## What To Observe

Record an item when any of these happens:

- The agent runs a supported command that should not exist or should not be used in
  that phase.
- A command overwrites valid evidence or writes to an ambiguous path.
- Documentation tells the agent to do one thing while scripts enforce another.
- The agent must inspect bash source to discover a required field or convention.
- A fallback silently approximates important evidence such as `base_commit`.
- A report says `pass` while important advisory checks failed without clear wording.
- Step numbering, file names, or checkpoint names cause the agent to pick the wrong
  target more than once.
- Old CP checks and new C0-C4 checks duplicate, conflict, or leave unclear ownership.
- Evidence is stale against HEAD, generated outside canonical paths, or not tied to
  a real failure mode.

## Probe Output Format

Each observed issue should be recorded in this shape:

```markdown
### OBS-YYYYMMDD-NN - Short title

**Observed in:** project/plan/EPIC/run if known
**AID version:** vX.Y.Z
**Observed at:** YYYY-MM-DD
**Status:** raw / confirmed / backlog / fixed
**Severity:** low / medium / high / critical
**Class:** docs drift / evidence integrity / UX indexing / stale evidence / command surface / checkpoint overlap / merge policy

**What happened:** concrete behavior.
**Why it matters:** risk to AID control quality.
**Reproduction:** command or evidence path, if known.
**Likely fix:** concrete next action.
```

## When To Cleanup

Do not start a large cleanup after a single observation unless it is actively
corrupting evidence or blocking work.

Trigger cleanup when one of these is true:

- The same failure class appears in at least two independent EPICs.
- A command can overwrite valid evidence.
- A documented required flow is contradicted by a script.
- A stale/false-green pattern recurs after the verifier/evidence pack controls were
  introduced.
- A PM decision is repeatedly needed because the AID process itself is ambiguous.

## Initial Findings From 2026-07-01

The first field report produced five confirmed AID-system findings:

1. `aid-prefilter.sh classify --checkpoint cp3` writes to the same
   `verifier-output-step-N.md` file used by CP2.
2. CP3 documentation expects `verifier-output-cp3-code-review.md` and
   `verifier-output-cp3-security.md`, creating a mismatch with the CP3 prefilter
   command surface.
3. FSM requires `classification:` in verifier outputs, but the CP3 instructions do
   not make this requirement prominent enough.
4. `current_step` is 0-indexed while plan steps are presented as 1-indexed, causing
   repeated operator mistakes.
5. CP3 `base_commit` fallback can silently approximate the review range when the
   exact run base cannot be read.

These are tracked in `docs/plans/2026-06-29-BACKLOG.md` as B-004 through B-008.
