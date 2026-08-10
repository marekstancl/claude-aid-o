# IMP — Lightweight Codex adjudication for AID auto-mode stops

Status: draft / backlog candidate  
Created: 2026-07-21  
Decision: lightweight Codex adjudication first; heavy mechanical recovery
framework deferred  
Scope: AID auto mode, operator escalation, decision evidence

## Problem

AID "auto" mode currently behaves as a sequence of automated steps that often
stop and ask the PM/operator for decisions that are mostly technical recovery or
workflow-adjudication questions.

In practice, those questions are usually copied to Codex and Codex provides the
operational decision. The current routing therefore makes the PM a manual
message broker between the running AID agent and Codex.

Different incidents look unrelated, but the result is the same:

- autonomous execution pauses,
- the user is asked to choose from A/B/C options,
- the user forwards the question to Codex,
- Codex chooses the pragmatic technical path,
- the user forwards the answer back.

This is not real autonomy.

Recent examples:

- `plan.json` byte-hash drift during E-064-1_2 required a semantic equivalence
  check and reseal decision.
- A double `increment-step` call advanced FSM state twice and required a
  truthful rewind decision.
- P065/P064 review loops needed terminal rules for when to stop fixing and
  when to split/waive/backlog.
- WAN/P070 CP1-deep hit provider/session limits; mandatory lenses did not run,
  and the agent asked whether to bypass the gate instead of waiting/resuming.
- Cache-preflight stopped P064 dogfooding because the marketplace plugin cache
  differed from the WIP branch that intentionally edits the plugin itself.

The common issue is not that AID is too strict. The issue is that AID escalates
technical ambiguity directly to the PM instead of first asking an adjudicator
that can make the same kind of operational decision the PM currently asks Codex
to make manually.

## Chosen direction

Do **not** build a large new mechanical recovery subsystem first.

The first implementation should be lightweight:

> Before an auto-mode agent asks the PM a technical A/B/C question, it routes the
> question to Codex as an adjudicator. Codex classifies the stop, chooses the
> default operational path when safe, and says whether PM input is genuinely
> required. The decision is copied into evidence so the PM can review it after
> the auto run.

This changes the escalation route, not the core FSM.

## Goals

- Reduce unnecessary PM interruptions during auto mode.
- Preserve strict gates and evidence.
- Keep real PM decisions with the PM.
- Record Codex operational decisions so they are reviewable after the run.
- Avoid introducing another hard gate that can itself become a new source of
  stops.

## Non-goals

- Do not weaken existing gates.
- Do not make `--force` easier or more common.
- Do not let Codex silently accept product/security risk.
- Do not build a full new FSM/recovery command framework in the first version.
- Do not make missing adjudication evidence a new release blocker in v1.

## What Codex may decide without PM

> **Partially superseded by P076 (2026-08-09) — this section only.**
> `plugins/aid-orchestrator/defaults/policies/auto-recovery.yaml` is now the authority for the
> actions an AUTO run may take **on its own, before adjudication**: a closed set of six reversible
> actions (`wait_and_resume`, `retry_once`, `restart_service_once`, `rerun_targeted`,
> `resume_missing_lenses`, `collect_and_continue`), enum-enforced by
> `defaults/schemas/auto-recovery.schema.json`.
> The list below is **preserved, not replaced**: it remains the adjudicator's own decision
> vocabulary, and it is deliberately broader than the six (reseal, rewind, backlog and the A/B/C
> recommendation have no ladder action and reach the adjudicator by design).

Codex adjudication may answer technical/operational questions such as:

- wait and resume a mandatory gate after quota/session reset,
- reject a proposed bypass when a gate simply did not finish,
- choose deterministic recovery over `--force`,
- approve semantic `plan.json` reseal when source EPIC and regenerated canonical
  content are equivalent,
- approve truthful FSM rewind after a documented operator error when no
  implementation occurred for the falsely completed step,
- classify a cache-preflight mismatch as expected self-dogfood WIP drift when
  changed paths are in EPIC scope,
- apply a predeclared terminal review-loop rule,
- put clearly out-of-scope findings into backlog,
- choose the recommended option from an agent's A/B/C prompt when the tradeoff
  is technical and already evidenced.

## What must still go to PM

Codex must escalate to the PM when the next action is a real PM decision:

- merge/release despite a known security blocker,
- accept product or user-facing behavior risk,
- change acceptance criteria,
- materially expand or reduce plan/EPIC scope,
- remove or weaken a gate,
- perform destructive git/history operations,
- publish a public release while a release gate is red,
- choose between two legitimate product strategies,
- accept a waiver outside an already declared policy.

If Codex is unsure whether a decision is technical or PM-owned, it must mark
`pm_required: true`.

## Lightweight adjudication flow

1. Auto agent reaches a point where it would normally ask the PM.
2. Agent writes the question exactly as it would ask the PM, including evidence
   paths, current branch, recommended option and risk.
3. Agent routes the question to Codex adjudicator.
4. Codex responds in a small structured block:

   ```yaml
   decision: wait_and_resume
   pm_required: false
   stop_class: GATE_INCOMPLETE
   reason: mandatory CP1 lenses did not run because provider quota was exhausted
   allowed_actions:
     - wait_until_quota_reset
     - resume_missing_lenses
   forbidden_actions:
     - force
     - waive_missing_gate
   evidence_to_record:
     - missing_lenses
     - quota_reset_time
   ```

5. Agent copies the question and Codex answer into the current evidence area.
6. If `pm_required: false`, agent continues.
7. If `pm_required: true`, agent stops and asks PM with Codex's summary.

## Evidence format

v1 can be markdown or JSON. The important requirement is that the decision is
captured, not that it becomes a new strict schema.

Suggested path:

```text
.aid-o/work/evidence/<id>/<run_id>/adjudications/<timestamp>-codex-adjudication.md
```

Suggested content:

```markdown
# Codex adjudication

- question_source: <agent / command / run id>
- stop_class: <class>
- decision: <decision>
- pm_required: <true|false>
- branch: <branch>
- head: <sha>
- evidence_refs:
  - <path>

## Original question

...

## Codex decision

...

## Follow-up action taken

...
```

Missing adjudication evidence should be reported in the final summary in v1. It
should not become a new hard blocker until the pattern has proven useful.

## Stop classes for the adjudicator

> **Superseded by P076 (2026-08-09) — this section only.**
> The machine-readable stop classes now live in
> `plugins/aid-orchestrator/defaults/policies/auto-recovery.yaml`
> (GATE_TIMEOUT, SERVICE_UNHEALTHY, JOB_LOST, TRANSIENT_INFRA, DISPATCH_ORPHANED,
> REVIEW_EXHAUSTED, UNCLASSIFIED), each with a named emitter code site, honest
> `detector` / `ladder_entry` labels, allowed actions, a budget and the
> adjudicate → escalation → pm_force terminus. That file — not this table — is what an AUTO run
> classifies against.
> The table below stays readable as adjudicator-facing vocabulary for the conditions P076 does not
> define a class for (`STATE_DRIFT_RECOVERABLE`, `FSM_OPERATOR_ERROR`, `GATE_FAILED_IN_SCOPE`,
> `GATE_FAILED_OUT_OF_SCOPE`, `POLICY_DECISION_REQUIRED`, `SCOPE_EXPANSION_REQUIRED`,
> `TERMINAL_RULE_TRIGGERED`); in the ladder those all route as UNCLASSIFIED, straight to
> adjudication.

Codex should use these classes to keep decisions consistent:

| Class | Meaning | Usual action |
| --- | --- | --- |
| `TRANSIENT_INFRA` | Timeout, rate limit, provider/session quota, flaky transport | Wait/resume/retry within budget |
| `GATE_INCOMPLETE` | Mandatory gate/lens did not run or evidence is missing because execution was interrupted | Resume missing gate |
| `STATE_DRIFT_RECOVERABLE` | State/evidence byte drift with semantic equivalence provable from source artifacts | Approve documented reseal |
| `FSM_OPERATOR_ERROR` | Operator/agent caused inconsistent local FSM state, but true state is reconstructable | Approve documented repair/rewind |
| `GATE_FAILED_IN_SCOPE` | Gate found a real defect in the current change scope | Fix and verify |
| `GATE_FAILED_OUT_OF_SCOPE` | Gate found a real defect outside current scope | Backlog or PM escalation depending on severity |
| `POLICY_DECISION_REQUIRED` | Continuing requires accepting known risk | PM required |
| `SCOPE_EXPANSION_REQUIRED` | Fix requires changing plan/EPIC scope materially | PM required |
| `TERMINAL_RULE_TRIGGERED` | Predeclared terminal condition fired | Execute declared terminal action |

## Prompt requirement

Agent-facing instructions should include:

> If you would ask the PM a technical A/B/C continuation question during auto
> mode, first ask Codex adjudicator. Continue without PM only if Codex returns
> `pm_required: false`. Always copy the question and Codex decision into
> evidence. Escalate to PM for product/security/scope/risk decisions.

## Acceptance criteria

- Auto agents route technical continuation questions to Codex before PM.
- Codex decisions are copied into evidence.
- Codex can choose wait/resume/retry/reseal/rewind/backlog when those are
  technical and evidenced.
- Codex cannot silently accept PM-owned risk.
- PM receives fewer interruptions and gets a final decision log after auto mode.
- Missing adjudication evidence is a summary gap, not a hard blocker in v1.

## Deferred: heavy mechanical recovery framework

The original proposal included a larger mechanical system:

```text
aid-fsm.sh reseal-plan-json <epic_id> <run_dir> --reason <text>
aid-fsm.sh rewind-step <epic_id> <run_dir> --to <step_index> --reason <text>
aid-fsm.sh resume-incomplete-gates <epic_id|plan_id> <run_dir>
aid-review-loop classify-stop <evidence_dir>
aid-review-loop adjudicate <evidence_dir> --terminal-policy <file>
aid-auto-mode wait-and-resume <run_id> --until-quota-reset
```

> **Partially delivered by P076 (2026-08-09) — this section only.** Two of the six sketches above
> have a real half shipped; the rest are untouched and remain deferred.
>
> | Sketch | Status after P076 |
> | --- | --- |
> | `aid-auto-mode wait-and-resume <run_id> --until-quota-reset` | **Partially delivered.** `wait_and_resume` is a declared action of the recovery policy, and `aid-fsm.sh resume` is the real resume path (P076 EPIC 2 Step 5). **Still open:** the `--until-quota-reset` wait itself — nothing sleeps out a quota window, and no runtime reads the policy yet. |
> | `aid-fsm.sh resume-incomplete-gates <epic_id\|plan_id> <run_dir>` | **Partially delivered.** `resume_missing_lenses` is a declared action, and the ladder gives it a class (TRANSIENT_INFRA) with a budget and a terminus. **Still open:** the subcommand — there is no gate-scoped resume that re-dispatches only the lenses that did not run. |
> | `aid-fsm.sh reseal-plan-json` | Still open, unchanged. |
> | `aid-fsm.sh rewind-step` | Still open, unchanged. |
> | `aid-review-loop classify-stop <evidence_dir>` | Still open, unchanged. The classification now has a policy to classify *against*, but no command performs it. |
> | `aid-review-loop adjudicate <evidence_dir> --terminal-policy <file>` | Still open, unchanged. |

That direction is intentionally deferred.

Reason: building another hard mechanical layer now risks creating another
source of blocking conditions before the lighter escalation-routing change has
proven itself. The heavy framework may still be useful later, but it should be
driven by observed Codex adjudication logs rather than designed upfront as a
large new FSM.

Candidate future hardening items:

- make `increment-step` output unambiguous,
- bind step verification evidence to step id/hash/current commit,
- add sanctioned `plan.json` reseal command,
- add sanctioned step rewind command,
- make cache-preflight self-dogfood-aware,
- mechanically enforce bounded review-loop terminal rules.

## Temporary operator rule

Until implemented:

> If an auto agent asks the PM a technical continuation question, route it to
> Codex first. If Codex says `pm_required: false`, let the agent continue and
> record the decision. If Codex says `pm_required: true`, treat it as a real PM
> decision.

