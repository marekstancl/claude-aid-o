# AID v3 — Architectural Principles

**Created:** 2026-05-13 | **Status:** binding for aid-orchestrator-internal design work
**Scope:** AID redesign decisions, plugin architecture evolution, inventory item proposals
**Not in scope:** plugin consumer projects (vulcan, wan, sousto, …). These principles
guide how AID itself evolves, not how downstream projects use it.

This document is referenced from `CLAUDE.md` and from inventory items in
`docs/plans/AID-v3-architectural-inventory.md`. Each principle is anchored to
empirical evidence — an incident that demonstrated the failure mode the
principle prevents. New principles are added when reflection sessions (`NR N`
in `docs/plans/AID-v3-agents-outputs.md`) surface cross-cutting patterns that
would otherwise be reinvented one item at a time.

---

## Principle #1 — Detector without Enforcement is Decoration

**Statement.** Any new AID detection capability (compliance check, gate,
telemetry signal, audit field) MUST be paired with a stated enforcement
mechanism at design time. Detectors without enforcement degrade to noise:
the PM and the agent both learn the signal has no consequence, and the
detection capability is effectively turned off while looking deployed.

**Three acceptable enforcement mechanisms.**

1. **FSM precondition block.** Detection failure prevents an FSM state
   transition (typical: `done-advance` refuses if `compliance.overall == "fail"`
   with `severity: blocking` failures). PM may explicitly override via
   `--force --reason "<≥20 chars>"` — the override is logged to
   `.aid-o/work/audit-log.jsonl` so the bypass is auditable.

2. **Out-of-band hard fail.** CI job, git pre-push hook, or maintainer
   script outside the agent's tool surface. Cannot be silently skipped by
   the agent because it runs in a process the agent does not control.

3. **Explicit PM confirmation gate with logged justification.** Detection
   surfaces a Y/n prompt with full context; PM action is recorded with
   timestamp and reason. Different from FSM block in that PM is the
   primary decision-maker, not the exception path.

**Empirical evidence — P026 (WAN, 2026-05-13, NR 7).** P037 Phase 1 shipped
the verifier-provenance detector (`aid-fsm.sh:292` cross-references
`timeline.jsonl` `verifier_dispatch_start`/`_complete` events within ±60s of
each verifier-output `_generated_by` timestamp). The detector worked
correctly: `compliance.json` for E-026 flagged 6/6 verifier outputs as
`provenance: "fabricated"` and set `overall: "fail"`. The PM merged anyway
because no enforcement mechanism existed — `compliance.overall == "fail"`
was advisory, not blocking. Agent reflection §6: *"100% false positive
volume to udělá ignorable — tj. neměl by mu věřit vůbec"*. The detector
was decoration.

**Application criteria.** This principle applies whenever an inventory item
or plan proposes:

- A new field in `compliance.json`
- A new check in `evaluate_compliance_checks` or `aid-run-gates.sh`
- A new telemetry signal (timeline event type, counter, ratio)
- A new audit category (auditor agent rubric extension)
- A new validation rule in any verifier prompt

The item description MUST include an **Enforcement** subsection that names
one of the three mechanisms above and identifies the exact FSM state /
hook / prompt where enforcement lives. Items lacking this subsection are
considered incomplete and should be revised before implementation.

**Anti-pattern: "will be added later."** Splitting a detector and its
enforcement into separate phases is acceptable only if Phase 2
(enforcement) is scoped, prioritized, and time-bounded at the moment
Phase 1 ships. Phase 1 alone changes the failure mode from "we don't know"
to "we know and ignore" — strictly worse, because ignored signal trains
the system to discard future signal of the same shape.

**Tiered severity caveat (added 2026-05-13 from P026 review).** Hard-blocking
every detection on first deployment creates false-positive flood, which
trains PM to use `--force` reflexively, which destroys enforcement equally
well as having none. New checks SHOULD default to `severity: advisory`
(logged, not blocking) and be auto-promoted to `severity: blocking` after
empirical validation — concretely: N=5 consecutive EPICs without
`--force --reason` invocation for that check, OR explicit PM promotion
with reason. Promotion criterion must be deterministic and tracked in
telemetry (`force_override_rate[check_name]`, see AID-027 extension).
This is not an exception to the principle — it is how the principle is
applied responsibly to new capabilities.

---

## Future principle slots

Principles emerge from reflection sessions when a pattern repeats across
≥2 EPICs and is not item-specific. Candidates currently under observation
(not yet binding):

- **#2 — Telemetry without Action Path.** Telemetry signals that have no
  documented response action accumulate as decoration. Each new metric
  must answer: "if this metric crosses threshold X, who does what?"
  Candidate empirical anchor: AID-027 `iteration_density_per_step` —
  metric is defined, threshold is documented, but no FSM/PM action path
  is wired. Watch for first real-world threshold breach to confirm.

- **#3 — Affordance Removal beats Policy.** External-feedback principle 5
  already encoded in AID-029. Promote to principle status if a second
  empirical incident shows policy-only enforcement degrading.

- **#4 — Plan AC Text is the Contract.** Goalpost-shift failure modes
  (F5/F6/F7/F8/F9 in AID-010) all share root cause: agent treats plan AC
  as starting suggestion, not final contract. Candidate principle:
  reformulation of an AC mid-flight requires explicit plan-update commit,
  not just lessons-learned note.

- **#5 — Enforcement without Instruction is Cargo Cult.** The inverse of #1.
  Every enforcement mechanism (FSM precondition, structural check, dispatch
  wrapper, schema validator) must be accompanied by a matching LLM-facing
  instruction in the relevant skill/agent/command file, OR the rule is
  rediscovered by failure each time. Cargo-cult gloss: the check fires correctly
  but no agent knows the rule, so the operator reaches for `--force` because no
  skill explains the alternative — and after enough force-overrides the check
  goes statistically invisible.
  Candidate empirical anchors: P041 brainstorm (2026-06-01) — §1-§10 section
  verifier review repeatedly found instruction-vs-enforcement misalignment in
  own design work; P041 audit Phase 2 GAP findings (focus-allowlist regex,
  plan.schema constraints unsurfaced to the plan author); P041 Phase 3/3b —
  doc-vs-code drift across planner.md (FAIL) + 3 commands with real functional
  breaks because the instruction layer drifted from the enforcement layer.
  Promotion sub-criterion: ≥3 GAP findings spanning ≥2 of the three enforcement
  mechanisms defined in §1 above. Companion: `docs/plans/AID-audit-2026-06/`
  (enforcement-registry.yaml + governance Component 2 type→instruction-home
  convention operationalize this principle). **Status: candidate, NOT binding.**

Promotion to binding principle requires: (a) ≥2 reflection sessions
citing the pattern, (b) at least one inventory item where the principle
would have changed the design, (c) PM confirmation that the principle
applies to AID-internal work specifically (not just downstream usage).

---

## How to reference this document

From inventory items:

```yaml
notes: >
  ...
  Enforcement: FSM precondition block in cmd_done_advance — refuses
  transition when compliance.overall == "fail" with severity: blocking
  failures present. See AID-v3-principles.md §1.
```

From plans during brainstorming/writing:

> "This step introduces a new compliance check `plan_ac_match`. Per
> AID-v3-principles.md §1, the enforcement mechanism is: FSM precondition
> block in cmd_done_advance once the check has reached `severity: blocking`
> status. Until then, default `severity: advisory` with logged failures."

The reference forces explicit confrontation with the principle. Without it,
the design phase silently assumes "someone will wire enforcement later" —
which is exactly the failure mode P026 demonstrated.
