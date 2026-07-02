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
4. Findings go to `docs/plans/BACKLOG.md` with origin date and source.
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

**When to write an OBS entry:** write to `docs/plans/BACKLOG.md` immediately
once a finding is confirmed. An unconfirmed suspicion stays as a working note
in the observer report only — it does not become a backlog item until
confirmed.

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

These are tracked in `docs/plans/BACKLOG.md` as B-004 through B-008.
