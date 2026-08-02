# AID Entry-Point UX — Help, Init, Setup and Human Handoffs

**Status:** proposed implementation plan; planning only, no production changes
are authorized by this document.
**Prepared:** 2026-08-02.
**Base:** `main` at v2.66.2 (`281f87f`).
**Relationship:** separate from P066/P069. It may be planned while P069 is
active, but implementation begins only from a clean post-P069 base and must
not redefine P069's scheduler or catalog contract.

## 1. User problem

AID has gained substantial capabilities — plan-branch lifecycle, plan-final
closure, durable receipts, scoped waivers, recovery commands and test-portfolio
audit — faster than its entry-point guidance was updated. The result is a
working feature that a user cannot discover, or an agent report that lists
technical facts without explaining what happened, why it matters and what the
user should do next.

This is visible in current shipped command material:

- `aid-help.md` is labelled last updated on 2026-06-01, lists a small legacy
  command/topic set and does not route to `/aid-audit-tests`;
- `aid-init.md` says it merged interactive onboarding from setup, while
  `aid-setup.md` still owns repeatable permissions, integrations, CLAUDE.md
  and stack scan modules; and
- structured outcomes already exist for several flows, but their final chat
  presentation is inconsistent and often begins with raw technical detail.

The aim is not a cosmetic rewrite. A user must be able to discover the real
installed capability, safely initialize or upgrade a project, understand what
configuration owns what, and receive an actionable chat handoff without
memorising commands.

## 2. Product outcome

The normal interaction follows one simple pattern:

> **Outcome first → what it means → relevant evidence/risk → one recommended
> next action → technical detail if wanted.**

`/aid-help` is a concise navigation layer over real, installed commands. It
does not duplicate pipeline internals. `/aid-init` remains the idempotent
workspace/bootstrap-and-upgrade authority. `/aid-setup` remains the explicit,
repeatable configuration authority. They share vocabulary and a coherent user
journey, but neither silently performs the other's writes.

This work must make it easier to use AID, not introduce another mandatory
administrative ceremony. There is no generic “prose gate,” no automatic audit
after every EPIC and no requirement that a user remember a follow-up command.

## 3. Architecture decisions

### D1 — retain two authority boundaries

Do **not** merge init and setup into one ambiguous command.

| Boundary | Owns | Must not do silently |
|---|---|---|
| `/aid-init` | create/upgrade `.aid-o`, safe default generation, additive migrations, plugin/config provenance and detected bootstrap facts | reset a configured project or overwrite user configuration |
| `/aid-setup` | explicit change of chosen permissions, integrations, CLAUDE.md, stack re-scan and later project configuration | recreate init-owned state or write an upgrade/migration it does not own |

The commands may share a configuration summary, vocabulary and handoff. A
grounding pass may move one narrowly proven operation, but every move needs a
single owner, idempotency behavior and existing-project migration proof.

### D2 — help is hand-written navigation with mechanical coverage

Help prose remains concise and hand-written. A deterministic test discovers
every command frontmatter file with `user_invocable: true` and verifies that
the help index exposes a route for it. The test proves coverage, not literary
quality. Internal/hidden commands must be explicitly classified as such.

### D3 — structured outcomes use deterministic renderers

For flows with structured evidence — test audit, gates/waivers, plan-final and
close, blocked/escalation — the controller renders a fixed human-first
summary. Free-form roles use one shared short communication reference instead
of copying a long style guide into every agent card.

The renderer must distinguish fact, recommendation and PM risk acceptance. It
must not turn a waiver into a passing result or hide an unresolved condition.

### D4 — user language and detail level

The default final handoff uses the user's language and plain terms. Technical
paths, IDs, commands and raw evidence follow the summary or appear on request.
This does not require translating protocol artifacts or source documentation;
it constrains the final user-facing explanation.

### D5 — no invented host lifecycle controls

The plan may add a command-discovery diagnostic only after grounding what the
host/plugin platform exposes. It must not promise that AID can force a plugin
reload, session restart or slash-command registration if the host controls
those actions.

## 4. Required grounding before implementation

The implementer begins with a read-only inventory against the then-current
main, not with edits to `aid-help.md`.

For every user-invocable command, record:

- command frontmatter identity, arguments and actual controller/skill entry;
- whether it is discoverable in help and which topic routes to it;
- its authority: create, update, migrate, observe, stop, external coordinate;
- project files it may read/write and whether those files are versioned;
- expected first-run, existing-project and failed/declined behavior; and
- any obsolete command name, lifecycle claim or missing route.

For every init/setup operation, record:

- actual caller, script/skill and target file;
- one owner command and configuration precedence;
- idempotency, preview/confirmation and rollback/partial-failure behavior;
- fresh-project behavior versus already-configured project behavior; and
- current tests or the absence of tests.

The result is a checked-in disposition table with values:
`current | update | index_only | intentionally_internal | remove_or_deprecate`.
No implementation slice may claim a command/function is wired until the table
names its production caller and a test exercises that caller.

This grounding explicitly discharges the **analysis** portion of IMP-261:
inventory behavior-affecting settings and their source/precedence across
plugin defaults, project configuration, environment and invocation overrides.
Current code confirms the motivating gap remains real: C0/C3 models have
environment-only overrides while their shared Codex transport hard-codes
`model_reasoning_effort=high`. The analysis must decide what belongs in a
durable project policy and what remains immutable/host-local. Implementing a
new versioned all-project settings schema is deliberately a **separate next
plan**; it must not be smuggled into this UX/instruction scope.

## 5. Delivery slices

### Slice 1 — authoritative command/help inventory

1. Build a deterministic command-frontmatter enumerator and fixture set.
2. Create the checked-in disposition table from the grounding inventory.
3. Define a small help-index data contract: command, one-line purpose, route,
   audience/category and intentionally-internal disposition. It contains no
   long generated prose.
4. Add a coverage test: every `user_invocable: true` command has exactly one
   indexed help route; each indexed command exists; no obsolete route remains.
5. Re-ground all current command variants, especially audit tests, plan
   generation, verification, lifecycle/recovery and stop/status surfaces.

**Acceptance:** a newly added public command fails the discoverability test
until it is intentionally indexed; a removed/renamed command cannot remain in
help as a dead instruction.

### Slice 2 — help information architecture

6. Rewrite `/aid-help` as an outcome-oriented index, keeping progressive
   disclosure without pretending that the old three-command beginner view is
   the complete product.
7. Add focused routes at minimum for `tests`, `plan-lifecycle`, `generation`,
   `gates`, `recovery`, `config`, `init` and `setup`.
8. Describe `plan_branch` truthfully: EPIC work accumulates, one expensive
   release boundary occurs at plan end, and legacy/in-flight plans retain their
   explicit legacy route. Never retroactively say a legacy plan used the new
   mode.
9. Make help recommend the next action from current state where this is already
   mechanically known; otherwise present a small choice without pretending to
   infer user intent.
10. Add a grounded diagnostic route only if host capabilities support useful
    checks such as plugin provenance/version/config presence. Its result must
    clearly separate what AID observed from what requires a host restart.

**Acceptance:** fresh-install/help fixtures expose all public commands and
the current test-audit/plan lifecycle paths; power-user help no longer points
to obsolete per-EPIC release behavior.

### Slice 3 — init/setup ownership and safe upgrade journey

11. Implement or tighten one shared, read-only configuration-summary renderer
    used by init and setup. It reports detected root, existing workspace,
    configuration sources, effective plan mode/gate profiles and proposed
    action — it does not itself mutate configuration.
12. Reconcile each inventory item to one owner. Preserve `/aid-init` as the
    only owner of workspace creation, initialization-owned default generation
    and additive upgrades such as execution configuration blocks.
13. Preserve `/aid-setup` as the explicit owner of modular configuration
    changes. Every mutation shows scope and requires the existing appropriate
    confirmation; “all” remains an ordered composition of named modules, not
    a hidden reset.
14. Standardise root detection, target-branch terminology, plan mode,
    configuration precedence and project/plugin provenance in both command
    surfaces.
15. Add migration/upgrade receipts or existing structured evidence only where
    a current operation already needs durable recovery. Do not create a new
    bookkeeping subsystem for simple help/setup text changes.

**Acceptance:** fixtures prove a fresh project initializes correctly; an
existing custom project is not overwritten; a declined additive upgrade leaves
bytes unchanged; init and setup give the same effective configuration summary;
and no configuration file has two write owners.

### Slice 4 — human-first handoff contract

16. Create one concise shared reference for user-facing agent/controller
communication: outcome, meaning, relevant evidence/risk, one recommended next
action, then technical detail.
17. Wire that reference into user-facing command/controller instructions and
relevant agent cards. Preserve strict JSON/protocol outputs for machine
interfaces; translate only their final human presentation.
18. Add deterministic renderers or renderer adapters for existing structured
outcomes: test audit, gate/waiver, plan-final/close and blocked/escalation.
19. For test audit, consume the decision-quality P066 follow-up contract when
available. Until then, report only what current evidence proves and say when a
diagnostic result is incomplete; do not fabricate parallelisation advice.
20. Require the final user-facing response to use the user's language and
avoid unexplained internal jargon. Do not build a brittle global “tone”
detector; test required structured sections, not prose aesthetics.
21. Resolve the verified 0-index/1-index UX seam: machine state and evidence
filenames may retain their compatibility index, but every human-facing status,
blocker and handoff must render `Plan Step N` and, where useful, the internal
index in parentheses. Current FSM/pipeline text still exposes bare
`current_step` values.

**Acceptance:** golden fixtures for success, blocked, waiver, incomplete audit
and plan-close show outcome-first summaries. A raw technical list cannot be
the only final handoff. JSON-producing agents keep valid protocol output; a
state value of `current_step: 0` is rendered to a human as `Plan Step 1`.

### Slice 5 — whole-path consistency and release

21. Sweep every agent-facing instruction surface from the disposition table.
For each match, record `updated | verified_current | intentionally_internal`.
Do not sweep historical plans, changelogs or archive transcripts as though
they were live instructions.
22. Add targeted regression tests for command discoverability, help routing,
init/setup ownership, fresh/existing-project safety and structured handoff
rendering.
23. Run one independent whole-diff review focused on obsolete lifecycle claims,
unwired help/config promises, authority drift and user-language regression.
24. Update contributor-facing documentation, enforcement registry entries for
new mechanical checks, both CHANGELOGs and release metadata according to the
repository release policy.

**Acceptance:** all live instruction surfaces agree on the same command
authority and lifecycle. No release is made merely because prose was edited;
the mechanical coverage/ownership checks and relevant targeted suites pass.

## 6. Explicit non-goals

- Do not merge init and setup into one command merely to reduce names.
- Do not change P069 scheduling, test catalog approval or worker policy.
- Do not automatically invoke `/aid-audit-tests` after EPICs/plans/releases.
- Do not use a generic LLM tone/prose detector as a hard gate.
- Do not rewrite `.aid-o` consumer configuration or erase custom settings.
- Do not promise plugin reload behavior controlled by the host application.
- Do not edit historical plans/archives simply because they contain old
  instructions; only live instructional surfaces are subject to the sweep.

## 7. Whole-system regression rules

1. Every new public command is discoverable, but no internal command is
   accidentally exposed as public.
2. Help content points to installed command identities, never a guessed alias.
3. Init/setup changes are tested both against an empty fixture and a
   hand-customized project fixture.
4. A change to a structured renderer cannot alter the underlying gate,
   waiver, lifecycle or protocol verdict.
5. A recommendation is never represented as fact, and a PM acceptance is
   never represented as a passing gate.
6. No large full-suite run is required after each documentation slice; run
   focused tests and one proportionate final candidate check under the current
   quarantine policy.

## 8. Exit criteria

The work is complete only when:

1. all public commands are mechanically discoverable through help;
2. help accurately routes a user to test audit, generation, lifecycle,
   recovery, init and setup;
3. init/setup have one grounded ownership table and no conflicting writer;
4. fresh and existing projects are both protected by regression tests;
5. structured outcomes produce human-first, language-appropriate handoffs;
6. live instruction sweep finds no obsolete lifecycle wording;
7. the P066 decision-quality output is used where available, without making
   this UX work depend on a scheduler activation; and
8. all changes are documented and released according to the plugin policy.

## 9. Sequencing

This plan intentionally follows the P066 decision-quality follow-up for the
test-audit-specific renderer contract, but its grounding inventory can begin
immediately. P069 must finish or freeze before implementation starts, because
the final command/config authority inventory has to describe the released
gate-scheduler surface. Implement this as its own maintenance stream after the
P066/P069 contract re-grounding; do not fold it into either active plan.
