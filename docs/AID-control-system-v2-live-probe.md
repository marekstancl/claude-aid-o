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

