---
audit: P041
phase: addendum (PM-requested)
artifact: enforcement-governance-recommendation
status: draft-for-PM
generated: 2026-06-01
depends_on: 01-enforcement-inventory.md, 02-mapping.md
---

# P041 — Recommendation: Enforcement Governance System

> **One-paragraph summary (plain language):** The audit found ~177 "turnstiles"
> (automatic checks that block or validate behavior) scattered across 50+ files,
> and no single place lists them. The first careful pass captured under half of
> them. The fix is not more checks — it's **order**: one registry that lists
> every check in one place, one rule for *where* the matching human-readable
> instruction must live, and one automated guard that fails the build if a check
> exists without a registry entry or an instruction. Two of these three pieces
> already exist in the repo in partial form; this recommendation connects them
> into a system and makes "register + document" a creation-time requirement, not
> an afterthought.

---

## Why this is needed (the two findings, restated)

1. **No single inventory exists.** Enforcement lives in bash (`aid-fsm.sh`,
   generators, hooks), YAML policy (`execution.yaml`, `orchestration.yaml`,
   `check-severity.yaml`, `integrations.yaml`, `permissions.yaml`), templates,
   skills, and agent role-cards. `check-severity.yaml` registers ~13 of them.
   The other ~160 are discoverable only by reading code.
2. **Drift is structural, not careless.** The first audit pass — done carefully —
   missed ~51% of the enforcements (measured by two independent agent sweeps).
   When the map is that scattered, humans and LLMs both under-track it; rules get
   added without instructions, and instructions outlive the code they describe
   (we found GAP, ORPHAN, CONTRADICTORY, and UNREACHABLE cases in Phase 2).

This recommendation gives the enforcement layer the same discipline the FSM gives
the task lifecycle: a deterministic source of truth + a mechanical guard.

---

## The system — 3 components

### Component 1 — Single enforcement registry (source of truth)

**A new file:** `plugins/aid-orchestrator/defaults/enforcement-registry.yaml`
(shipped with the plugin; the canonical list of every enforcement mechanism).

One entry per enforcement, using the schema already proven in
`02-mapping.md`:

```yaml
version: 1
enforcements:
  - id: gates_generated_by          # snake_case, matches check-severity.yaml keys where they exist
    type: 1                          # 1–15 taxonomy
    source: "scripts/aid-fsm.sh:1102"
    description: "EXECUTE→GATES requires gates_report.json with _generated_by"
    instruction: "skills/pipeline.md:544"   # where the human/LLM-facing rule lives (Component 2)
    severity: blocking               # blocking | advisory | n/a (informational guard)
    surface: llm-facing              # llm-facing | internal-guard  (drift-risk tier)
    status: active                   # active | planned | deprecated
    test: "scripts/tests/bats/test-anti-fabrication.bats"   # regression gate, if any
```

Key fields and why they matter:
- **`instruction`** — forces every enforcement to name *where* its cedule is. A
  blank `instruction` on an `llm-facing` enforcement is exactly the GAP class.
- **`surface`** — separates the ~4 material LLM-facing gaps from the ~10 internal
  hygiene guards. Only `llm-facing` enforcements *require* an instruction; an
  `internal-guard` (nonce, flock, source-only) may set `instruction: n/a`.
- **`status: planned`** — captures the ORPHAN class honestly (e.g.
  `dispatch_completed_late`, `cp4_glob_evaluated` are documented but not wired).
  A `planned` entry with no `source` is the legitimate way to record intent
  without it reading as a live check.
- **`status: deprecated` + dead-code detection** — an entry whose `source`
  resolves to no executing code path is the UNREACHABLE class (the 3 ratio checks).

The 86 mapped enforcements (01/02) seed this file; E87–E177 are appended as the
backfill task.

### Component 2 — Convention: where the instruction lives (one home per type)

The Phase-2 heuristic table is **promoted from a one-off audit aid to a binding
convention.** Every enforcement type has exactly one canonical instruction home,
so authors never wonder where the cedule goes:

| Type | Enforcement | Canonical instruction home |
|------|-------------|----------------------------|
| 1 | FSM-precondition (orchestrator) | `skills/pipeline.md` (state/transition sections) |
| 2 | FSM-precondition (subagent output) | `agents/verifier.md` **or** `skills/agent-protocol.md` |
| 3 | Dispatch-wrapper | `skills/pipeline.md` §4 Dispatch Protocol |
| 4 | Structural-check | `skills/pipeline.md` (relevant §) or the generating script's header |
| 5 | Pre-filter-regex | `defaults/pre-filter-rules.yaml` (self) + `pipeline.md` §13 |
| 6 | Schema-validator (plan) | `skills/plan-writing.md` + `skills/planner.md` |
| 7 | Command-orchestration-rule | `commands/<cmd>.md` |
| 8 | Hook-enforcement | `defaults/hooks/*` + `agent-protocol.md` git discipline |
| 9 | YAML-policy-driven | the policy YAML (self) + `pipeline.md` if FSM-consumed |
| 10 | Template-shaped | the template (self) + consumer skill |
| 11 | Audit-log invariant | `agent-protocol.md` "P040 audit events" table |
| 12 | Skill-loaded-protocol | the skill itself |
| 13 | Agent-contract | `agents/<agent>.md` or `skills/role-cards.md` |
| 14 | Test-regression-gate | the `test-*.sh` itself |
| 15 | Stack-gate-binding | `defaults/execution-stacks/<lang>.yaml` |

**What an instruction (cedule) must contain** — minimal contract, to be codified
in the new `skill-writing.md` (P041 Phase 4b deliverable):
1. **The rule** in plain imperative ("gates_report.json must carry `_generated_by`").
2. **The trigger** — when the check fires (which transition / which diff / which output).
3. **The failure mode** — the exact reason string the user will see.
4. **The fix** — the copy-paste remediation (most `die` messages already embed this).

This closes the E30/E31/E32 class: `plan-writing.md` would have to surface the
schema constraints (role enum, `objective minLength:10`, step-id pattern) because
type-6 enforcements are conventionally homed there.

### Component 3 — Mechanical sync guard (enforcement of the enforcement)

This is the Principle #1 move ("Detector without Enforcement is Decoration"):
the registry itself needs a guard, or it becomes another stale doc.

**Extend the existing `scripts/tests/test-instruction-consistency.sh`** (which
already checks that pipeline.md matches aid-fsm.sh states) into a registry checker
that fails CI when:
- a registry `source` file:line no longer matches a real check (stale entry),
- an `llm-facing` enforcement has a blank/`n/a` `instruction` (GAP),
- an `instruction` anchor doesn't resolve in the named file (ORPHAN),
- a `status: active` entry's `source` resolves to dead code (UNREACHABLE),
- (stretch) a heuristic scan finds an `exit 1`/`die`/`error_exit` in scripts with
  no matching registry entry (new unregistered enforcement).

The last check is what would have caught the ~91 second-pass misses automatically.

---

## Lifecycle rule (the cultural change)

Add to `CLAUDE.md` (aid-orchestrator section) and `skill-writing.md`, anchored to
the existing `AID-v3-principles.md` Principle #1 and candidate Principle #5:

> **Every new enforcement mechanism MUST, in the same change that introduces it:**
> (a) add an `enforcement-registry.yaml` entry, (b) add or cite its instruction in
> the type's canonical home, (c) state its `severity` and `surface`. A check
> shipped without a registry entry or (for llm-facing) an instruction is treated
> as incomplete, the same way `AID-v3-principles.md` already treats a detector
> without enforcement.

This makes "register + document" a definition-of-done, not later cleanup —
directly the lesson Principle #5 candidate encodes.

---

## What already exists vs what's new (effort framing for PM)

| Piece | Status today | Work to build the system |
|-------|--------------|--------------------------|
| Partial registry | `check-severity.yaml` (~13 entries, severity only) | Generalize to full registry schema; backfill 177 entries (01/02 seeds 86) |
| Type→instruction convention | Implicit; reconstructed in this audit | Write down as binding table (above) + codify in skill-writing.md |
| Sync guard | `test-instruction-consistency.sh` (states only) | Extend to registry ↔ source ↔ instruction checks |
| Lifecycle rule | `AID-v3-principles.md` #1 (detectors only) | Add #5 (enforcement→instruction) + CLAUDE.md DoD line |

**Two of three components exist in seed form.** The heavy lifting is the one-time
backfill of the registry (~177 entries) and extending the consistency test. None
of it requires changing how enforcement works — it adds a map and a guard over
the checks that already run.

---

## Recommended sequencing (if PM proceeds)

1. **Now (cheap, high value):** create `enforcement-registry.yaml` schema + seed
   it with the 86 mapped entries (01/02 already have everything needed). Adopt
   the type→instruction convention table.
2. **Next:** backfill E87–E177 into the registry (mechanical; map each to its
   instruction home, surfacing new GAPs as they appear).
3. **Then:** extend `test-instruction-consistency.sh` to gate the registry; wire
   it into `run-all-tests.sh` so it's a real CI gate (Component 3 = the part that
   makes the system self-maintaining).
4. **Fold into P041 synthesis:** Components 2–3 + lifecycle rule are the concrete
   payload for candidate Principle #5 and the new `skill-writing.md` (Phase 4),
   so this recommendation slots directly into the plan's existing synthesis phase
   rather than spawning a separate plan.

This is the "order" you asked for: one list, one place per instruction, one guard
that keeps them honest.
