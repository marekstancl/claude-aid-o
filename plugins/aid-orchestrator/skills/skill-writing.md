---
name: skill-writing
description: How to write, maintain, and retire AID skill files — structure, length, freshness, enforcement-instruction pairing, and completeness gate
user_invocable: false
---

# Skill Writing — Authoring and Maintaining AID Skills

**Last Updated:** 2026-06-03

How to create and maintain skill files for the AID orchestrator plugin.
This file is self-applicable: it obeys every rule it prescribes.
It is the criteria source for auditing other skills (P041 Phase 4).

---

## Purpose

AID skills are the instruction layer between the plugin's enforcement
mechanisms and the LLMs that implement them. A skill file is not
documentation — it is an executable specification. Every rule it contains
must be actionable by an LLM with no side-channel context.

This skill ensures that skill files remain correct, tight, and internally
consistent. It closes the cargo-cult loop: a check without a matching
instruction is a Detector without Enforcement (Principle #1); an instruction
without a matching check is an Enforcement without Instruction (Principle #5
candidate — see §Anti-Circumvention).

---

## When to Invoke

Invoke this skill when:

- Writing a new skill file for the AID plugin.
- Substantially revising an existing skill (>25% of content changing).
- Reviewing a skill as part of an audit run (P041 or equivalent).
- A reflection session (NR) produces a learning that belongs in a skill.
- An enforcement-registry.yaml entry is added or changed and its instruction home is a skill.

Do NOT invoke for:

- Agent-card files (`agents/*.md`) — those follow `agents/` conventions, not skill conventions.
- Command files (`commands/*.md`) — type-7 enforcements live there, not here.
- One-line factual corrections that do not change structure or rules.

---

## Standard Structure

Every AID skill MUST contain these sections in this order. Omit a section
only when explicitly marked optional below.

| # | Section | Required? | Notes |
|---|---------|-----------|-------|
| 1 | YAML frontmatter | MUST | `name`, `description`, `user_invocable` |
| 2 | H1 title + **Last Updated** | MUST | Title matches `name`; date on line 2 |
| 3 | One-paragraph purpose | MUST | What this skill governs; NOT a summary of sections |
| 4 | When to invoke | MUST | Positive triggers + explicit "Do NOT invoke for" |
| 5 | Core content sections | MUST | Domain-specific; varies by skill |
| 6 | MUST Rules | MUST | Hard constraints for skill authors/actors; numbered list |
| 7 | Completeness Gate | MUST | Checklist that the skill itself must pass before shipping |
| 8 | Reference Files | SHOULD | Upstream/downstream skills, scripts, config |
| 9 | **Last Updated** footer | MUST | Same date as header; on last non-blank line |

The `## MUST Rules` and `## Completeness Gate` sections are always present,
even if the skill is short. They are the audit surface.

### Frontmatter Convention

```yaml
---
name: kebab-case-name           # matches filename without .md
description: One sentence — what the skill teaches or governs
user_invocable: false           # true only for PM-facing commands
---
```

`status: provisional` is added during draft phase and removed on PM sign-off.
No other custom frontmatter keys are permitted (they will be ignored by the
plugin loader and add confusion).

---

## Length Guidelines

Skills have natural size bands. Stay in the correct band — padding is as
harmful as over-compression.

| Band | Lines | When |
|------|-------|------|
| **Tight** | 80 – 200 | Single-focus skills: one protocol, one output format |
| **Standard** | 200 – 450 | Most skills: multiple rules + gate + examples |
| **Reference** | 450 – 900 | Cross-cutting skills consumed by many agents |
| **Epic** | 900+ | Pipeline specs only — `pipeline.md` (~1207 lines) is the acknowledged exception; `plan-writing.md` (~1029 lines) is a second exception due to its embedded completeness gate. Both exist because their scope cannot be split without losing internal consistency |

Observed range in this plugin: `agent-protocol.md` at ~286 lines (tight/standard
boundary) to `pipeline.md` at ~1207 lines (epic, justified). A skill over its
classified band's ceiling (Standard 450 / Reference 900) without justification is a
smell — look for sections that belong in a different skill or can be expressed as a
table.

**Band classification rule (deterministic).** A skill is **Tight** if it covers a
single interaction pattern (one output format, one protocol step, one config
convention) with no sub-types. It is **Standard** if it covers multiple distinct
rules, two or more actor roles, or requires a gate. It is **Reference** if it is
consumed by many agents/authors as a cross-cutting standard. **Epic** is reserved
for pipeline specs. When in doubt between two bands, pick the larger.

**Self-classification:** this skill is a **Reference** standard (consumed by every
skill author + the audit). Its length lives in the Reference band (450–900); the
Tight-band overhead carve-out below keeps it from forcing bloat on small skills.

---

## Freshness Rules

### Last Updated Footer

Every skill file carries exactly two date stamps:

1. `**Last Updated:** YYYY-MM-DD` on line 2 (after the H1 title, before the
   first `---` separator).
2. `**Last Updated:** YYYY-MM-DD` as the last non-blank line of the file.

Both dates MUST be identical. They are bumped whenever any rule, section
content, or enforcement reference changes. Reformatting whitespace or fixing
typos does not require a bump; changing a rule trigger, adding an example, or
updating a reference does.

### When to Bump

Bump the date when:

- A rule is added, removed, or its trigger/failure/fix changes.
- A referenced enforcement changes its behavior (the instruction must keep pace).
- A new section is added or an existing section is retired.
- A reflection (NR) produces a propagated learning (see §Reflection Propagation).

Do NOT bump for spelling corrections, Markdown formatting fixes, or link
updates that do not change the rule semantics.

### Retiring Stale Sections

When a feature is removed or a rule is superseded:

1. **Remove the content entirely.** Do not add "(deprecated)" headers or
   grayed-out notes. If there is genuine historical context that future
   authors need, add one sentence to the CHANGELOG, not to the skill.
2. The "historical-skeleton" anti-pattern is a section kept around because
   "someone might want the history." History lives in git. Skills must
   describe current behavior only.
3. Exception: a `status: planned` note (≤ 2 lines) is permitted when a rule
   is intentionally incomplete pending a future phase. It MUST carry a
   pointer to the tracking issue or plan ID, never a bare "(planned)".

---

## Forbidden Patterns

These patterns produce audit findings when present in a skill file.

### 1. Version-Stamped Section Titles

```
# WRONG
## Force Override Policy (v2.16.0+)
## Tiered Severity (NEW v2.21.0 — P038 AID-038 Phase 2)

# RIGHT
## Force Override Policy
## Tiered Severity Enforcement
```

Version stamps in headings accrete. After 3 EPICs the section title is noise.
If you need to attribute a change, use a one-line parenthetical in the body
(`Added in v2.21.0 / P038.`) or put it only in the CHANGELOG.

### 2. Dead "(planned)" Entries

An entry that says a feature "will be added" with no tracking ID is an
**ORPHAN**. It was true when written; it becomes false without anyone noticing.
Either:

- Link to a concrete plan or backlog ID: `*(planned — IMP-042)*`
- Remove it. The absence is honest; the stale note is not.

The P040 audit events table in `agent-protocol.md` carries two `*(planned)*`
annotations — both are acceptable because they carry the specific feature name
and version context, and the surrounding table makes their status unambiguous.
Standalone `(planned)` bullets with no traceability are not acceptable.

### 3. Duplicated Content Across Skills

If the same rule appears verbatim in two skill files, one of them is the
canonical home (per the type→instruction convention in §Anti-Circumvention)
and the other must reference it, not copy it.

Duplication causes drift: the two copies diverge, and the audit detects a
CONTRADICTORY finding. When in doubt, the convention table in
`03-governance-recommendation.md` names the canonical home per enforcement
type.

**Carve-out (not a violation):** a downstream skill MAY restate a constraint in
its own actor's terms — e.g. `agent-protocol.md` stating the agent-side
*consequence* of a controller rule that lives canonically in `pipeline.md` —
provided it adds a `See also: <canonical home>` reference. This is layered
abstraction, not duplication. The test: if a rule change in the canonical home
would silently leave the restatement wrong (verbatim copy) → duplication; if the
restatement is a perspective ("what this means for you, the agent") that survives
small wording changes → carve-out.

### 4. Rules Without Observable Failure Modes

Any instruction that tells an LLM "do X" but provides no signal for what
happens when X is skipped is decoration. Pair every imperative rule with
its failure mode or enforcement pointer (see §Instruction Style).

---

## Instruction Style

Skills are LLM-facing specifications. Write them in plain imperative English.

### The 4-Part Contract

Any instruction that documents an enforcement (a check that fires automatically)
MUST contain all four parts:

| Part | What it states | Example |
|------|---------------|---------|
| **Rule** | The imperative in plain English | `gates_report.json MUST carry a _generated_by field` |
| **Trigger** | When the check fires | `On EXECUTE→GATES transition` |
| **Failure mode** | The exact error the user sees | `"hand-written reports are rejected with copy-paste remediation in stderr"` |
| **Fix** | The copy-paste remediation | `Use aid-fsm.sh advance-to-gates instead of manual yq mutation` |

A rule with missing parts creates a GAP finding in the enforcement registry.

### Style Principles

- Use active voice, present tense: "The controller MUST emit..." not "It
  should be noted that emission is required..."
- Imperatives are `MUST` / `MUST NOT` / `SHOULD` / `MAY` — no weakeners like
  "typically" or "in most cases" on a MUST.
- Tables over bullet lists for multi-attribute content (trigger/failure/fix).
- No meta-commentary ("This section explains..."). State the rule.
- One concept per sentence. Long compound sentences hide the rule boundary.

---

## MUST Rules

1. **ALWAYS include all 9 standard sections** — in the canonical order. Missing
   sections are a Completeness Gate failure.
2. **ALWAYS use identical Last Updated dates** in header and footer. Mismatched
   dates signal uncommitted mid-edit state.
3. **ALWAYS bump Last Updated** when any rule trigger, failure mode, or fix
   changes — not just when prose changes.
4. **NEVER duplicate a rule** that has a canonical home in another skill — reference
   it by file and section instead. `skills/pipeline.md §4` is the home for
   type-3 dispatch-wrapper enforcements; do not copy-paste the rule here.
5. **NEVER use version-stamped section titles** — version metadata belongs in
   CHANGELOG and one-line body annotations, not headings.
6. **NEVER leave a `(planned)` annotation without a tracking ID** — IMP-NNN or plan
   path required. Bare `(planned)` is an ORPHAN.
7. **ALWAYS write the 4-part contract** (rule + trigger + failure + fix) for every
   instruction that documents an enforcement mechanism.
8. **ALWAYS retire removed content** by deleting it, not marking it deprecated
   in-place. Update the date and note the removal in CHANGELOG.
9. **NEVER exceed the length band correct for the skill's classification** (Tight
   ≤200, Standard ≤450, Reference ≤900, Epic = pipeline specs only — see Band
   classification rule in §Length Guidelines). A draft over its band's ceiling must
   split or compress before shipping.
10. **ALWAYS run the Completeness Gate** before marking a skill ready. The gate is
    below; every check must pass or be explicitly marked N/A with reason.

---

## Completeness Gate

Run before marking the skill file ready for review or shipping.

```
COMPLETENESS GATE — evaluate each check:

STRUCTURE:
  1. Does the file have YAML frontmatter with name, description, user_invocable?
  2. Is H1 title present and does it match the name field?
  3. Is **Last Updated** on line 2 (after H1) AND on the last non-blank line,
     and are both dates identical?
  4. Are all 9 standard sections present in canonical order?
  5. Is the skill within the correct length band for its scope?

RULES QUALITY:
  6. Does every enforcement instruction include all 4 parts of the contract
     (rule, trigger, failure mode, fix)?
  7. Are all MUST rules numbered and in imperative form?
  8. Are there zero version-stamped section headings?
  9. Are there zero bare (planned) annotations without tracking IDs?
  10. Is there zero content that duplicates another skill's canonical rule?

FRESHNESS:
  11. Does the content reflect current enforcement behavior
      (no references to removed features, no stale version guards)?
  12. If the skill was updated in response to a reflection (NR), is the
      propagation marked per §Reflection Propagation rules?

ANTI-CIRCUMVENTION:
  13. For every enforcement mechanism the skill describes: does a corresponding
      instruction appear in the type's canonical home per the convention table?
      (If this skill IS the canonical home, the instruction must be here.)
  14. For every instruction in this skill: is there a corresponding enforcement
      that fires when the instruction is violated? If not, is the absence
      explicitly acknowledged with reason?
      N/A guidance: instructions for type-12 (skill-loaded-protocol) and type-13
      (agent-contract) enforcements have no external mechanical check — the
      enforcement IS the loaded skill/contract. Mark these N/A with reason
      "type-12/13 — enforcement is the loaded skill". All other llm-facing types
      require a named enforcement.

  Check classification: mechanical (author/CI can verify): 1,2,3,5,7,8,9.
  Judgment (author/reviewer attestation): 4,6,10,11,12,13,14,15. Do not let an
  LLM auditor treat judgment checks as binary pass/fail.

SELF-CONSISTENCY:
  15. Does the skill itself obey every rule it prescribes? (A skill-writing skill
      that has a version-stamped heading violates its own rule.)

EVALUATION:
  IF all 15 checks pass (or explicitly marked N/A with reason) → ready to ship
  IF any check fails → fix before shipping. Do NOT ship with known failures.
```

---

## Anti-Circumvention

### Principle #1 — Detector without Enforcement is Decoration

Per `docs/plans/AID-v3-principles.md §1`: any detection capability shipped
without a stated enforcement mechanism degrades to noise. The PM and the agent
both learn the signal has no consequence. The P026 incident (WAN, 2026-05-13)
is the empirical anchor: a working detector flagged fabrications correctly;
the PM merged anyway because `compliance.overall == "fail"` was advisory only.

When writing or reviewing a skill: if a rule describes a check, the check MUST
have one of the three enforcement mechanisms named in Principle #1 (FSM
precondition block, out-of-band hard fail, or explicit PM confirmation gate with
logged justification).

### Candidate Principle #5 — Enforcement without Instruction is Cargo Cult

The inverse failure mode: a check fires but no human-readable instruction tells
the operator what triggered it, why, or how to fix it. The operator runs
`--force` because no skill explains the alternative. After enough force-overrides,
the check becomes statistically invisible. This is cargo cult enforcement: the
ritual exists, the meaning is lost.

**Rule:** Every `llm-facing` enforcement in `enforcement-registry.yaml` MUST
name its instruction home (`instruction:` field). A blank instruction on an
`llm-facing` enforcement is a **GAP** finding. The canonical instruction home
per enforcement type is:

| Type | Enforcement | Canonical instruction home |
|------|-------------|---------------------------|
| 1 | FSM-precondition (orchestrator) | `skills/pipeline.md` (state/transition sections) |
| 2 | FSM-precondition (subagent output) | `agents/verifier.md` or `skills/agent-protocol.md` |
| 3 | Dispatch-wrapper | `skills/pipeline.md §4 Dispatch Protocol` |
| 4 | Structural-check | `skills/pipeline.md` (relevant §) or generating script header |
| 5 | Pre-filter-regex | `defaults/pre-filter-rules.yaml` (self) + `pipeline.md §13` |
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

Source: `docs/plans/AID-audit-2026-06/03-governance-recommendation.md §Component 2`.

**Lifecycle rule (for new enforcements):** Every new enforcement mechanism MUST,
in the same change that introduces it:

1. Add an `enforcement-registry.yaml` entry.
2. Add or cite its instruction in the type's canonical home.
3. State its `severity` and `surface`.

A check shipped without a registry entry or (for `llm-facing`) an instruction
is treated as incomplete — the same way Principle #1 treats a detector without
enforcement.

---

## Reflection Propagation

When a reflection session (`NR N` in `AID-v3-agents-outputs.md`) or a Curator
report produces a learning that belongs in a skill, the learning MUST be
propagated using the type→canonical-home convention above.

**Protocol:**

1. Identify the enforcement type(s) the learning touches.
2. Look up the canonical instruction home in the table above.
3. Update that skill file: add the rule, bump Last Updated, note in CHANGELOG.
4. If the learning is cross-cutting (affects 2+ skills), update each canonical
   home — do NOT create a summary doc instead.
5. Mark the NR entry with one of two dispositions:

   - `PROPAGATED: skills/<target>.md §<section> — <date>` — learning was applied.
   - `NOT-PROPAGATED-DELIBERATE: <reason>` — e.g., "learning is project-specific,
     not plugin-level" or "superseded by IMP-NNN resolution".

A reflection entry with neither disposition is open and will appear in the next
audit as an unresolved NR.

**What counts as a skill-relevant learning:**

- A rule that was missing and caused a failure (GAP).
- A rule that fired but had no instruction, causing operator confusion (Principle #5).
- A behavior that changed but the skill still describes the old behavior (STALE).
- A pattern that repeated across ≥2 EPICs without a rule capturing it.

**What does NOT require propagation:**

- Project-specific conventions (e.g., a particular repo's naming scheme).
- Transient findings that were fixed without identifying a general rule.
- Performance observations with no actionable rule change.

---

## Migration & Grandfathering

Skills authored before this standard's adoption are audited under relaxed criteria:
**structural** non-conformance (missing header `Last Updated`, no `## MUST Rules` /
`## Completeness Gate` section, a version-stamped heading) is logged **advisory**,
not blocking, until the skill undergoes substantive revision (>25% content change).
At that point the full gate applies. New skills (authored after adoption) must pass
all 15 checks.

This on-ramp is deliberate: the existing canonical references (`pipeline.md`,
`plan-writing.md`, `agent-protocol.md`) each fail one or more checks today (header
date, MUST-Rules section, a version-stamped heading). Without grandfathering, the
first audit run floods the PM with structural noise on the most-used files. They
remain valid *content* references even while structurally non-conformant.

**Tight-band overhead carve-out.** For Tight-band skills (80–200 lines), the
`## MUST Rules` section MAY collapse to one sentence ("All instructions follow the
4-part contract in `skill-writing.md §Instruction Style`."), and `## Completeness
Gate` MAY be a one-line attestation ("Gate passed: [date] — see skill-writing.md").
This preserves auditability without mandating ~30 lines of boilerplate on a small
skill (which would itself violate "padding is as harmful as over-compression").

**MUST vs SHOULD audit consequence.** A `MUST`/`MUST NOT` violation is a
Completeness-Gate failure (blocking). A `SHOULD` violation is an advisory finding —
a skill author may deviate with a documented reason.

## Examples

### Good: Tight 4-Part Enforcement Instruction

```markdown
**Rule:** `gates_report.json` MUST carry a `_generated_by` field set by
`aid-run-gates.sh`.

**Trigger:** On `EXECUTE→GATES` transition, `aid-fsm.sh transition` reads
the report and rejects if the field is absent.

**Failure mode:** `"hand-written reports are rejected — use
aid-run-gates.sh, not manual yq mutation"` (stderr, exit 1).

**Fix:** Use `aid-fsm.sh advance-to-gates "$STATE_FILE"` instead of
running gates and transitioning separately.
```

This passes Completeness Gate check #6. It is concise, actionable, and
complete. An operator who hits the failure mode reads the fix in ≤10 seconds.

---

### Bad: Instruction Without Trigger or Fix

```markdown
The gates report must be generated by the official script and contain
provenance fields. Manually crafted reports are not acceptable and will
cause issues during the transition phase.
```

Failures: no trigger (when does "will cause issues" fire?), no failure mode
(what does the user see?), no fix (what should they do instead?). This is a
GAP finding. The instruction is decoration — an operator who hits the problem
will reach for `--force` because no path forward is documented.

---

## Reference Files

- `docs/plans/AID-v3-principles.md` — Principle #1 (Detector without Enforcement);
  candidate Principle #5 (Enforcement without Instruction)
- `docs/plans/AID-audit-2026-06/03-governance-recommendation.md` — type→instruction
  convention table (Component 2) and enforcement-registry.yaml schema
- `plugins/aid-orchestrator/skills/pipeline.md` — canonical home for type-1/3/4
  enforcements; observed length ceiling reference (~1207 lines)
- `plugins/aid-orchestrator/skills/agent-protocol.md` — canonical home for type-2/8/11
  enforcements; observed lower length bound (~286 lines)
- `plugins/aid-orchestrator/skills/plan-writing.md` — canonical home for type-6
  enforcements; Completeness Gate pattern reference
- `plugins/aid-orchestrator/CLAUDE.md §On Plugin Changes` — Last Updated footer
  convention, CHANGELOG update rules

---

**Last Updated:** 2026-06-03
