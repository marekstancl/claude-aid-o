---
name: aid-verify-plan
description: Run one plan reviewer by hand on a plan, outside the plan review rounds, and relay what it found
user_invocable: true
---

# /aid-verify-plan — One Plan Reviewer, By Hand

Put a plan in front of ONE of the six plan review roles (`skills/plan-review-roles.md`)
without starting a review round: the same packet, the same prompt and the same
evidence rule as a real round, written under `cp1/manual/`, which the CP1 gate
never reads. Use it for a quick second look while a plan is still being
written; the rounds in `commands/aid-plan.md` "Plan review (CP1)" stay the only
review that counts before EPIC generation.

## Arguments

```
/aid-verify-plan [plan-path] [--role <role>]
```

- **`plan-path`** — the plan to review; default: the plan written or discussed
  in this session, otherwise the newest file in `.aid-o/plans/`.
- **`--role`** — one of `generalist_a` (default), `generalist_b`,
  `behaviour_edges`, `feasibility_deps`, `reuse`, `enforcement_tests`.

## What it does

1. Make the deterministic report current, then prepare a manual packet for the
   one role; it prints the directory:

   ```bash
   bash "$AID_PLUGIN_PATH/scripts/aid-plan-check.sh" <plan> --json .aid-o/work/evidence/<plan_id>/plan-check.json
   bash "$AID_PLUGIN_PATH/scripts/aid-plan-review-round.sh" prepare <plan> --round 1 --only <role> --manual
   ```

2. Dispatch that reviewer in a fresh context; its model is the role's `model`
   in `review_checkpoints.plan_review`, and it reads its prompt file itself:

   ```
   Agent(subagent_type: "general-purpose", model: <the role's model>,
         prompt: "Your complete instructions are in <manual dir>/prompt-<role>.md. Read that whole file first and follow it exactly.")
   ```

   Only a role whose provider is `claude` runs by hand; a codex role runs
   inside a real round (`aid-plan-review-round.sh dispatch`).

3. Relay the answer in `<manual dir>/reviewer-<role>.json` as one information
   card (`skills/communication.md`): each finding in plain words with its step,
   and the command that shows it.

## Reads / Writes

- **Reads:** the plan, `plan-check.json`, the repository (the reviewer, read-only).
- **Writes:** `.aid-o/work/evidence/<plan_id>/cp1/manual/<timestamp>/` only. No
  round index entry, no measurement, nothing the gate reads.

**Last Updated:** 2026-09-18
