---
name: planner
description: Plan → plan.json — how plan-run turns a reviewed plan into the run's plan.json, what it computes deterministically, and the judgment calls the LLM owns
user_invocable: false
---

# Planner — Plan → plan.json

**Skill:** planner
**Dependencies:** pipeline, plan-writing

---

## Purpose

The "Planner" is **not an intelligent agent**. `aid-plan-fsm.sh plan-run P<NNN>`
turns a reviewed Plan into the run's `plan.json` deterministically, through ONE
builder (`scripts/lib/aid-plan-json.sh`): it reads the whole plan, builds the
dependency graph and refuses a cycle in bash. The LLM's job is narrow: (1) write
the Plan in the format the builder reads (`skills/plan-writing.md`), (2) sanity-check
the output, (3) interpret a refusal for the PM.

The LLM never hand-generates `plan.json`. Since 3.0.0 (P114) there is no EPIC
file between the plan and `plan.json` — the plan is the input and a plan has one
run.

## Before the run: mandatory readiness

Run `aid-generation-readiness.sh <plan.md> --total 1` after writing the plan and
before CP1. It validates `Files:` grammar and builds the whole-plan dependency
graph from the source plan, rejecting missing, duplicate, self, forward or cyclic
dependencies. `plan-run` runs the same check itself, so a plan that passes here is
not refused there.

---

## The chain

```
Plan.md ── readiness ──► CP1 seal ──► plan.json (whole plan) ── D5 ──► init --direct
   ▲ written per plan-writing.md      ▲ sealed to the plan bytes    ▲ steps / dependencies /
   │ (### Step N + AID Role + deps)   │ and the target head         │ parallel_groups / gates
```

`plan-run` is one resumable transaction (`skills/pipeline.md` §2): rerun the same
command after an interruption; a run that made no step starts again with
`--restart --reason`.

---

## Output: plan.json

Full schema: `defaults/templates/plan.schema.json`. A plan's run carries
`direct: true`, `source_plan`, `version`, `repo_roots`, `steps`, `dependencies`,
`parallel_groups`, `analysis_groups` and `gates`.

```json
{
  "epic_id": "E-019-1_1",
  "source_plan": ".aid-o/plans/P019-auth.md",
  "direct": true,
  "steps": [
    { "id": "step_1_backend", "role": "backend", "plan_step": 1,
      "objective": "Design API contracts + ADR",
      "outputs": ["Create: `contracts/api.yaml` — …"], "allowed_paths": ["contracts/api.yaml"],
      "acceptance_criteria": ["..."] }
  ],
  "dependencies": [ { "before": "step_1_backend", "after": "step_2_backend", "reason": "..." } ],
  "parallel_groups": [ ["step_3_backend", "step_4_frontend"] ],
  "gates": ["tests_pass", "lint_pass"]
}
```

- **A step object has** `id` (`step_{N}_{role}`), `role`, `plan_step`, `objective`,
  `outputs`, `allowed_paths`, `forbidden_paths`, `acceptance_criteria`. It has **no
  `depends_on`** — dependencies live in the top-level `dependencies[]` as
  `{before, after, reason}`.
- **No `model`.** The model is chosen at dispatch time (EXECUTE) by the controller from
  `skills/role-cards.md` per the step's `role` (`pipeline.md` §4).
- **No `waves[]` field.** Ordering is derived at execution time from `dependencies`;
  parallelism is `parallel_groups`.

---

## What the builder computes deterministically

1. Every `### Step N:` of the plan → one step; its role from `**AID Role:**`, its
   objective, its `**Files:**` lines → `outputs` and `allowed_paths`.
2. `**Dependencies:**` → `dependencies[]`; **cycle detection** refuses a cycle with
   its member steps.
3. `**Parallel group:**` → `parallel_groups[]` (groups of 2+).
4. The plan's gates (`execution.yaml`) → `gates[]`; the plan's `repo_roots` → `repo_roots[]`.

What it does **not** do: no level assignment, no wave reorganisation, no model assignment.

---

## The LLM's job (the only judgment calls)

1. **Before running:** the plan's steps carry `**AID Role:**`, `**Objective:**`,
   `**Files:**` and `**Dependencies:**` (`plan-writing.md`), and the roles are valid.
2. **After running:** sanity-check what syntax cannot judge — dependencies that are
   *logically* wrong, or steps of one parallel group whose `allowed_paths` overlap
   (flag to the PM, do not run them in parallel).
3. **On a refusal:** surface the message to the PM (below).

---

## Error Handling

| Refusal | LLM action |
|---|---|
| Readiness: missing `### Step N:`, bad `Files:` grammar, invalid role | Fix the plan per `plan-writing.md`, rerun readiness |
| Readiness: unresolvable, forward or cyclic dependency | Report the steps; fix `**Dependencies:**` |
| `aid_generation_force_required: …` | The CP1 gate refused a forceable condition. Show the PM the printed conditions; the printed `--force --reason` command is the PM's decision, never the LLM's. |
| `aid_cp1_blocked: …` | The CP1 gate refused something `--force` cannot cover. Fix the named hard condition — do not suggest `--force`. |
| `plan_changed_since_seal` | The plan changed after the seal; restore it or archive the transaction as the line says. |
| `epic_path_removed` | A plan generated the old (EPIC) way: finish it on 2.118.x, or close it and start a new plan. |
| any other error | The failing script's own message is the real error — read that. |

---

## Reference Files

- `skills/plan-writing.md` — **the Plan step format the builder reads**
- `commands/aid-run.md` "PRE-FLIGHT" — `plan-run`, `--restart`, `repo_roots`
- `{plugin_path}/scripts/lib/aid-plan-json.sh` — the builder
- `{plugin_path}/scripts/aid-generation-readiness.sh` — readiness
- `defaults/templates/plan.schema.json` — full plan.json schema
- `skills/role-cards.md` — model tier per role

---

**Last Updated:** 2026-10-13
