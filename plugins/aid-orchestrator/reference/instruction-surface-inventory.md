# Agent-facing instruction surface inventory

**P068 Step 10 / E-068-2_2 Step 4.** Every surface an agent actually reads or
acts on, with an explicit disposition. A surface with no disposition fails
`scripts/tests/test-instruction-sweep.sh` with exit 2 — the check refuses to
treat "not listed" as "fine", because that is how a new command quietly ships
with obsolete lifecycle instructions.

This file lives under `plugins/aid-orchestrator/reference/` rather than any
`docs`-named directory: `.gitignore` carries an unanchored `docs/`, which would
match `plugins/aid-orchestrator/docs/` too, and a check cannot depend on a file
that is absent from a clean checkout.

## Dispositions

| Value | Meaning |
|-------|---------|
| `update` | Contained lifecycle instructions that assumed the per-EPIC release; revised to fork on mode. |
| `verified` | Read in full; either contains no lifecycle instruction, or its lifecycle references are already mode-correct. |
| `no-scope` | Not an instruction surface — history, or a document an agent does not act on. |

## Commands

| Surface | Disposition | Note |
|---------|-------------|------|
| `commands/aid-run.md` | `update` | PM options now fork on mode; the pre-merge review note states Curator/Auditor are plan-final roles under `plan_branch`. |
| `commands/aid-plan.md` | `update` | States the plan-mode declaration and the plan-final boundary where it describes plan lifecycle. |
| `commands/aid-init.md` | `update` | Documents the lifecycle `mode` field and the hook reinstall requirement. |
| `commands/aid-status.md` | `update` | Surfaces plan state, mode and candidate SHA alongside EPIC state. |
| `commands/aid-do.md` | `update` | States that Fast Mode neither creates nor releases a plan branch. |
| `commands/aid-verify-plan.md` | `verified` | CP1 is a plan-level review already; no per-EPIC release instruction. |
| `commands/aid-verify-implementation.md` | `verified` | Reviews an implementation, not a release cadence. |
| `commands/aid-audit.md` | `verified` | Health audit; no lifecycle instruction. |
| `commands/aid-help.md` | `verified` | Routes to other surfaces; carries no lifecycle instruction of its own. |
| `commands/aid-setup.md` | `verified` | Configuration; no release cadence. |
| `commands/aid-stop.md` | `verified` | Emergency stop; no release cadence. |

## Skills

| Surface | Disposition | Note |
|---------|-------------|------|
| `skills/pipeline.md` | `update` | Defines both modes. The legacy ritual now opens by stating it is not the default. |
| `skills/agent-protocol.md` | `update` | Carries the agent handoff contract with all five boundary messages. |
| `skills/role-cards.md` | `update` | Auditor, Curator, Simplifier and Reporter cards state the plan-final boundary. |
| `skills/review-checkpoint-contracts.md` | `update` | Records that CP3 stays per EPIC while the specialist stack moves to plan-final. |
| `skills/run-management.md` | `update` | `active.md` guidance made mode-aware. |
| `skills/plan-writing.md` | `update` | Documentation-step rule and lifecycle references made mode-aware. |
| `skills/planner.md` | `verified` | Plans work; does not instruct on release cadence. |
| `skills/brainstorming.md` | `verified` | Pre-plan activity. |
| `skills/memory.md`, `skills/memory-mcp.md` | `verified` | Memory protocol; no lifecycle instruction. |
| `skills/skill-writing.md`, `skills/command-writing.md` | `verified` | Authoring standards; no lifecycle instruction. |

## Agents

| Surface | Disposition | Note |
|---------|-------------|------|
| `agents/auditor.md` | `update` | Dispatch is plan-final, once per plan. |
| `agents/curator.md` | `update` | Dispatch is plan-final, once per plan. |
| `agents/simplifier.md` | `update` | Plan-final boundary confirmed. |
| `agents/reporter.md` | `update` | Plan-final boundary and the protocol-v2 delivery artifact. |
| `agents/verifier.md` | `verified` | CP2/CP3 are per-EPIC and stay so. |
| `agents/implementer.md` | `verified` | Implements a step; no release cadence. |
| `agents/gate-fixer.md` | `verified` | Fixes gate failures; no release cadence. |
| `agents/project-scanner.md` | `verified` | Scans a project; no lifecycle instruction. |

## Not instruction surfaces

| Surface | Disposition | Note |
|---------|-------------|------|
| `CHANGELOG.md` | `no-scope` | History. Rewriting it to match current behaviour would destroy the audit trail. |
| `README.md`, `plugins/aid-orchestrator/README.md` | `update` | Human-facing, but they describe the lifecycle, so they are kept correct. |
| `defaults/enforcement-registry.yaml` | `no-scope` | Records enforcements, including superseded ones, by design. |

## Backward compatibility

**P061, P062, P063 and P065 are legacy plans.** They were planned and, where
delivered, executed under `legacy_epic_release_mode`. P064 and P068 do not alter
their history, do not migrate them, and do not retroactively reinterpret their
completion: `aid-plan-fsm.sh inventory --apply` stamps such plans
`legacy_epic_release_mode` explicitly rather than inferring anything about them.
P062 additionally remains `write_only_until` its preconditions are met; the P068
amendment to its E10 precondition changes what that precondition means under the
new model, not P062's status.
