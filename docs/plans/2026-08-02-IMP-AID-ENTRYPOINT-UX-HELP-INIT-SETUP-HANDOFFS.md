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

## 10. Validated follow-up — PM emergency override and plan-boundary recovery

> **Plan written: P073 (EPIC 2)** — D6 universal force, D7.1-7.4 trap fixes, and the
> D7.5 deterministic UX repairs (P073 EPIC 1) are tracked in
> `.aid-o/plans/P073-loosening-force-ancillary.md` (2026-08-04). D14/D13 from §13
> are folded into the same plan (EPIC 2 / EPIC 1).
>
> **TODO — remaining after P073 (PM 2026-08-04: must be finished in a later plan):**
> - D7.3(a) as a SEPARATE `--rebase-epic` transaction was replaced by extending
>   `plan-state --attest-source-ref --recompute-base`; if dogfood shows that
>   extension does not cover a real rebase case, deliver the full transaction.
> - D7.5 item 2 (lint Testing Strategy/AC file references against the step
>   `Files:` allowlist) was consciously DROPPED from P073 as new ceremony —
>   revisit only with a concrete incident justifying it.

**Trigger:** P082 and P083 dogfood in the `wan` workspace. This is a product
requirement: the PM needs an intentional, universal backdoor when AID's own
bookkeeping or an implementation defect prevents the supported path from
making progress. It is not an agent privilege and it must never be a silent
success.

### Grounding result

This follow-up was independently checked against the implementation and its
focused regression tests before being added to this plan:

1. `plan-finalize --stage review` deliberately invalidates a frozen candidate
   after either a plan-branch commit or a tracked dirty write; the focused
   "accepted Curator fix" test proves that it invalidates the gate report and
   all review outputs. This behavior is correct for ordinary operation.
2. The Reporter contract nevertheless tells an agent to commit the delivery
   report and boundary manifest, while the same plan-final contract says that
   any tracked write is a fix. The P082 sequence (reviewed candidate moved by
   report/backlog/state commits) is therefore an instruction/ownership
   contradiction, not merely an operator sequencing error.
3. `aid-auto-pipeline.sh` commits/stamps lifecycle state and then calls
   `plan-start`, but does not first prove that the source plan is committed in
   the target branch. P083 consequently permitted task branches whose recorded
   base predated the committed plan. Moving those branches manually made the
   recorded lineage stale, as the lineage check is designed to detect.
4. Existing `--force --reason` already provides an audited escape hatch for
   selected FSM init/transition paths (and the focused lineage test proves it).
   `plan-close` and `plan-finalize` reject `--force` as an unknown flag, even
   though `plan-close` is the terminal operation that a PM must be able to
   complete when AID itself is defective.
5. The advertised "re-init EPIC" remedy for a legitimate mid-EPIC `plan.json`
   change is incomplete: normal init rejects the existing state file and
   `plan-state --repair` intentionally cannot rewrite lineage. A supported,
   audited recovery transaction is required.

### D6 — universal PM `--force` backdoor

Every public, state-changing AID lifecycle command must accept:

```text
--force --reason "<PM decision and concrete reason, minimum 20 characters>"
```

This includes init/re-init, transitions, increment/done advance,
plan-finalize, plan-merge-to-main, plan-close, repair/attestation and any
subsequently added lifecycle command. A controller may pass it only after an
explicit PM instruction; implementers, reviewers and delegated agents must
never select or synthesize it.

`--force` means that the PM consciously accepts the named failed preconditions
in order to recover control of the project. It is a real backdoor: a broken AID
path must not be able to strand the PM merely because the normal verifier or
bookkeeping state cannot be repaired first. It must, however, preserve truth:

- parse and require `--reason` consistently on every command;
- record command, normalized arguments (with secrets redacted), plan/EPIC/run,
  current and requested state, target/candidate SHA where applicable, each
  precondition bypassed, timestamp and reason in the timeline, audit log and a
  durable force receipt;
- for a plan merge/close, commit or otherwise durably attach the force receipt
  to the target/lifecycle record where possible; if that durable write is the
  broken operation, write the local receipt and return a clear reconciliation
  instruction rather than pretending the audit is complete;
- mark every resulting marker, receipt and human handoff as
  `forced_override: true` with the reason/receipt reference. A forced close may
  end the plan, but must not be rendered as an ordinary fully-verified PASS;
- make the override invocation-scoped and single-operation only. It must not
  leak through an environment variable into a later command; and
- never let a force receipt silently satisfy a normal evidence or gate check in
  another plan. It is PM risk acceptance, not fabricated evidence.

The normal path remains fail-closed. AID must print the exact normal recovery
first; the PM backdoor is the explicit second route. This preserves useful
diagnostics while ensuring the operator is never trapped by a tool defect.

### D7 — eliminate the P082/P083 traps before force is needed

1. **Committed-source preflight.** Before lifecycle creation, `plan-start` or
   any `epic-start`, require the source plan path to resolve from the target
   branch and require its committed bytes to equal the plan being generated.
   Refuse before creating a branch, with: "commit the plan on `<target>` and
   rerun generation." Add a fixture proving no lifecycle/plan/task branch is
   created when the plan exists only in the worktree.
2. **Immutable review boundary.** After freeze, plan-final agents write only
   run-scoped evidence. Move the committed delivery/boundary projection to a
   post-merge/close transaction that derives it from already verified evidence;
   no agent or controller may commit it to `plan/<id>` during review. Add a
   regression test proving the normal Reporter path completes one review round
   without moving `candidate_sha`.
3. **Supported recovery, before generic force.** Add a PM-audited transaction
   that can (a) verify and record a legitimate task-branch rebase/fast-forward
   onto `plan/<id>`, updating the recorded base, and (b) supersede/archive a
   stale EPIC FSM run and reinitialize it against the new `plan.json` hash.
   It must validate real Git ancestry, preserve old evidence, create a new run
   identity and refuse after the EPIC merged. `--force` remains available when
   even that recovery code is the defect.
4. **Instruction handoff.** Put one identical rule in controller, implementer
   and specialist-facing material: commit the source plan before plan start;
   agents never alter branch lineage or FSM state; after freeze only evidence
   outside the candidate may be written; a tracked candidate write is a FIX and
   requires a new candidate/review. The controller alone may use force after PM
   authorization.
5. **Small deterministic UX repairs.** Align the documented no-dependency
   syntax with its parser, lint Testing Strategy/AC file references against a
   step's `Files:` allowlist, render the first machine index (`0`) as human
   "Step 1", and ensure batch generation restores its original branch without
   leaving its own runtime pointer as a false dirty-tree blocker.

**Acceptance:** focused tests cover normal fail-closed behavior and one forced
case for every lifecycle command; each forced case creates all applicable audit
records and has `forced_override: true` in its resulting artifact. A PM can
force-close a deliberately corrupted fixture, the fixture is terminal, and
both CLI and final handoff visibly state that its normal evidence guarantees
were overridden. The P082 Reporter fixture needs no second review solely to
commit reporting output. The P083 uncommitted-plan fixture fails before any
plan/task branch exists, while the supported recovery fixture preserves prior
evidence and restarts with an auditable new run.

## 11. Validated follow-up — release truthfulness and project hook extension

> **Plan written: P073 (EPIC 1)** — shipped in v2.72.0. Grounding items 3-4
> and D10 are covered: the release script no longer reads a SIGPIPE'd probe as
> a clean absence, and a release whose CHANGELOG section is empty or a
> placeholder is refused.
>
> **NOT covered, still unplanned:** D8 (per-commit release-impact trailer) and
> D9 (a stable project pre-commit interface). The trailer grammar and the hook
> interface are a separate design.

> **Partially covered by P073 (EPIC 1)** — grounding items 3 and 4 (the
> `aid-release.sh` fail-loud probes and the unvalidated CHANGELOG placeholder,
> i.e. the D10 subset) are tracked in
> `.aid-o/plans/P073-loosening-force-ancillary.md`.
>
> **TODO — remaining after P073 (PM 2026-08-04: must be finished in a later plan):**
> - D8 (Release-Impact trailers) — start with the MINIMAL variant: fix the
>   pre-push hook so it stops recommending `--no-verify` and gains a simple,
>   reviewable exemption; the full trailer/validator design only if that proves
>   insufficient.
> - D9 (project pre-commit extension point `.githooks/project-pre-commit`) —
>   small, can ride along with the future init/setup UX plan (§ Slices 1-5).
> - D10 remainder (authoritative-version-source decision when CHANGELOG is a
>   landing page; configured changelog format contract) — P073 covers only the
>   fail-loud probes and target-version placeholder validation.

**Trigger:** dogfood in the `wan` workspace exposed two unsafe escape hatches:
a `feat:`/`fix:` implementation with no user-visible effect is forced to invent
a release entry, or to use `--no-verify`; and project-owned pre-commit checks
can be silently placed after AID's unconditional `exit 0`.

This is not a request to weaken release protection.  The normal path must
separate the technical type of a commit from its release impact, make a
deliberate no-release decision durable, and retain a clear blocking path for
an unclassified user-facing change.

### Grounding result

The four reported defects are confirmed in the shipped source:

1. `defaults/hooks/pre-push` currently treats any subject beginning with
   `feat` or `fix` since the last tag as requiring a `release:` commit.  It
   reads only `--oneline` subjects and its only printed escape is
   `git push --no-verify`.  Conventional-commit type cannot reliably express
   whether a user has received a change, so this produces either a false
   changelog claim or an unrecorded bypass.
2. `defaults/hooks/pre-commit` has an unconditional `exit 0` immediately
   before `AID-ORCHESTRATOR-HOOK-END`.  A project command appended after that
   marker is dead code.  `/aid-init` also replaces a non-AID hook, so there is
   no supported, upgrade-safe project extension point.
3. `aid-release.sh` uses `grep ... | head -1` in optional CHANGELOG and
   `pyproject.toml` detection under `set -euo pipefail`, without `|| true`.
   An otherwise legitimate changelog without a `## [X.Y.Z]` heading can abort
   before the script's explicit "cannot detect version" diagnostic.  The same
   optional-header pattern occurs in its changelog updater.
4. The updater can write the literal placeholder
   `_PM/agent: fill in entry content_`, but no legacy or `prepare-plan` path
   verifies that the entry for the intended version was actually completed
   before a release commit/tag is made.

### D8 — release impact is an explicit, per-commit assertion

Add commit trailers for every unreleased commit whose conventional subject is
`feat` or `fix`:

```text
Release-Impact: user | none
Release-Impact-Reason: <concrete explanation; required for none>
```

`user` keeps the existing release requirement.  `none` means the change is
deliberately not a user release; it is accepted by pre-push only with a
non-empty, reviewable reason.  The trailer is part of the signed/immutable
commit history when a project uses signed commits, and in every case travels
with the commit through normal review/push history; it is therefore a durable
record rather than a local bypass.

The hook must inspect full commit bodies, not only one-line subjects, and must
evaluate *every* applicable unreleased commit.  It must block if any such
commit has no valid impact assertion, has a malformed/conflicting assertion,
or declares `user` without a valid release.  One unrelated `none` trailer can
never exempt a user-facing commit.  Existing history before this migration is
handled explicitly and conservatively (a documented compatibility baseline or
PM-audited force), never silently reclassified.

The error message offers three honest routes: add/fix the trailer on the
relevant commit, make a real release with completed user-facing notes, or use
the universal PM `--force --reason` route where that command supports it.
It must no longer recommend `--no-verify` as a normal release-policy escape.
`--no-verify` remains a Git capability, not an endorsed AID workflow.

### D9 — a stable project pre-commit interface

Before its final successful exit, AID's installed pre-commit hook must invoke
an executable project hook at `.githooks/project-pre-commit`, if present.
The interface is deliberately narrow:

- absent or non-executable means no project extension and succeeds normally;
- it receives stable context such as `AID_HOOK_STAGE=pre-commit`, repository
  root and current branch, without exposing mutable AID internals;
- exit status `0` passes; any non-zero status blocks the commit and is relayed
  with a clear `AID project hook` diagnostic; and
- `/aid-init` preserves this project file across AID hook template upgrades;
  projects no longer edit `.git/hooks/pre-commit` to add checks.

Run it only after AID's own applicable guard has passed, so a blocked AID
commit does not execute unrelated project code.  Do not silently support an
arbitrary second hook location: one documented contract is auditable and
testable.

### D10 — fail-loud release preparation and completed notes

Replace optional version/header probes with non-fatal, portable detection and
then make one explicit decision: use an authoritative version source when it
exists; otherwise emit a non-zero, actionable diagnostic naming the missing
version source.  A CHANGELOG that is a landing page rather than a version
ledger is valid when another configured source owns the version; its updater
must use a defined configured format or say it cannot safely write it.  It
must never look as though a release completed when it did not.

Replace the visible prose placeholder with a recognizable release-entry
marker.  Before any release commit, plan-final candidate preparation, tag or
push, validate the entry for *that new version only*: it must have no marker
and contain a non-empty user-facing description.  A historical placeholder
outside that target section is reported as debt but cannot make every future
release impossible.  The validation failure names the file, target version
and edit required; it leaves the worktree uncommitted for correction.

### Delivery and acceptance

1. Add a shared parser/validator for release-impact trailers and full-body
   hook fixtures covering all-none, user, missing, malformed, conflicting and
   mixed commit ranges.  Cover protected target, plan/task exemption and the
   migration baseline separately.
2. Add the project-hook runner to the template and `/aid-init` installation
   contract, with fixtures for absent, successful, failing and upgrade-preserved
   project hooks.  Verify a command after AID's end marker never becomes the
   supported integration method.
3. Add regression fixtures for a no-header CHANGELOG with an authoritative
   JSON version, no authoritative version at all, a configured unsupported
   changelog form, and the updater's optional-header path.  Each failure must
   be non-zero and contain the actionable diagnostic.
4. Add legacy and `prepare-plan` tests proving a generated or pre-existing
   target-version marker blocks commit/tag until replaced by meaningful notes,
   while an old historical marker does not falsely block a new valid release.
5. Update `/aid-help`, `/aid-init`, `/aid-do`, release command guidance and
   agent handoff rules so agents never use `--no-verify` as routine policy
   bypass and know when to use `Release-Impact: none`.

**Acceptance:** an infrastructure-only `feat:`/`fix:` can be pushed without a
false version bump, but leaves a reviewable per-commit `none` reason.  A mixed
range containing one user-impacting or unclassified change cannot pass without
a completed release.  A project check has one upgrade-safe extension point and
its non-zero exit actually blocks a commit.  No supported release path can
commit/tag an unfinished target-version changelog entry or fail silently while
detecting its version.

## 12. Validated follow-up — review-equivalent ancillary writes after freeze

> **Plan written: P073 (EPIC 3)** — shipped in v2.72.0. D11, D12 and the
> required consumer matrix are covered end to end: the protected surface is
> computed at freeze, `plan-finalize --stage accept-ancillary` records an
> ancillary-only head, and the drift detector, review, C4 and the merge all
> honour it while every other consumer stays exact-only.
>
> The consumer matrix itself lives in `docs/extending-aid.md` under "Ancillary
> paths and review equivalence"; the operator instructions are in
> `skills/pipeline.md`.

> **Plan written: P073 (EPIC 3)** — tracked in
> `.aid-o/plans/P073-loosening-force-ancillary.md` (2026-08-04), with a deliberate
> scope cut after an adversarial Codex design round: no content digest (path-set +
> ancestry instead), equivalence wired into candidate drift/review/C4 and
> plan-merge-to-main only.
>
> **TODO — remaining after P073 (PM 2026-08-04: must be finished in a later plan):**
> - Consumer-matrix rows NOT wired by P073: CP3 final-review freshness, C3 audit
>   freshness, `plan-close-check` docs-only classifier, and the explicit
>   plan-final receipt argument for `aid-evidence-verify`. Each keeps its private
>   mechanism for now; fold it onto the shared ancillary/equivalence resolver as
>   soon as dogfood shows it still forces an unnecessary re-review.
> - The hard glob-overlap rejection from D12 was relaxed to path-level precedence
>   (protected paths always win) + a warning; revisit if a real overlap incident
>   occurs.

**Trigger:** plan-final dogfood repeatedly invalidated a complete review when
an agent or controller wrote a tracked report, runtime record, planning note or
other non-delivery document after the candidate was frozen. The current rule
uses the entire `plan/<id>` commit SHA as the candidate identity and treats
every remaining tracked dirty path (apart from a short hard-coded exception
list) as a fix. This is safe but too coarse: it makes harmless bookkeeping
look indistinguishable from a code or contract change and drives unnecessary
full review reruns.

The solution is a controlled relaxation, not a broad exclusion of `docs/**` or
`.aid-o/**`. Both trees can contain delivery-relevant files: the current plan,
lifecycle manifest, user-facing documentation and a durable evidence receipt
must never be smuggled past review merely because of their directory.

### D11 — candidate identity is a protected review surface

At freeze, retain the Git candidate SHA for provenance, but also calculate and
store a `protected_surface_digest`. The surface contains exactly:

- every delivery path declared by the current plan's `Files:`/acceptance
  contract, including its tests and delivery-relevant configuration;
- user-facing documentation explicitly declared by that plan;
- the source plan currently being closed; and
- its lifecycle manifest and all durable close/evidence receipts that the
  final decision actually consumes.

A change to this surface is a real fix: it clears review evidence and requires
a new freeze/gates/review cycle exactly as today. A path absent from the
surface is **not automatically safe**; it may be allowed only by the
ancillary-path policy below. This preserves fail-closed behavior for a new
source/configuration file that an agent tries to add outside the plan.

### D12 — explicitly allow review-equivalent ancillary writes

Add project policy `plan_final.ancillary_paths` with a narrow default set for
runtime and non-authoritative projections, for example:

```text
.aid-o/work/**
.aid-o/reports/**
.aid-o/metrics/**
```

Projects may extend it for their own generated planning/projection locations,
but may not use it to cover the current plan source, lifecycle manifest,
declared delivery paths or durable evidence consumed by close. AID rejects an
overlap between an ancillary glob and the protected surface, naming the
conflicting paths. There is deliberately no default `docs/**` or `.aid-o/**`
wildcard. An unrelated documentation path can be declared ancillary by a
project; documentation explicitly in the plan remains review-relevant.

For an uncommitted tracked write, drift validation ignores only a path matching
this approved ancillary policy. For a commit after freeze, AID may preserve
the review only when all of the following hold:

1. the frozen candidate is an ancestor of the new plan-branch head;
2. every changed path since the accepted head is ancillary;
3. recomputing `protected_surface_digest` yields the frozen digest; and
4. no evidence/receipt consumed by the close operation was replaced or
   modified outside its defined immutable evidence flow.

That condition is called **review equivalence**. It permits a real ancillary
commit without pretending that the commit SHA did not move; normal reviews and
gates stay bound to the frozen delivery surface, while the plan records the
new accepted head separately.

Every accepted ancillary commit writes a durable
`review-equivalence receipt` containing the plan/run IDs, frozen candidate,
prior and accepted heads, exact changed paths, protected-surface digest before
and after, policy version/hash, timestamp and controller identity. The final
handoff states that review equivalence was used and links the receipt. A
receipt is not proof of a normal fix and can never waive a protected-surface
change.

### Ownership and sequencing

1. During review, agents write raw logs and non-authoritative reports only to
   the run-scoped evidence/runtime area or the dedicated `aid-evidence/...`
   branch. They never commit a projection to `plan/<id>` themselves.
2. The controller alone may accept an ancillary projection commit after the
   mechanical review-equivalence check; it is not a delegated-agent decision.
3. The human delivery projection is normally generated after merge/close. If
   a project needs it earlier, it is an ancillary projection with the receipt,
   never an unlabelled candidate mutation.
4. PM `--force --reason` remains the emergency route for an incorrectly
   classified or broken path. It is not the normal mechanism for reports and
   runtime output.

### Required consumer matrix — no partial freshness relaxation

`protected_surface_digest` and the review-equivalence receipt are a shared
freshness primitive. Implementation must inventory every consumer that today
compares an evidence/review SHA with `HEAD` or rejects a dirty tracked tree.
For every consumer, it must either call the one shared equivalence resolver or
be explicitly documented as **exact-SHA-only** with a reason. No controller may
reimplement a private `docs-only`/runtime exception.

| Consumer | Current behavior | Required disposition |
|---|---|---|
| plan-final review, C4 and summary | candidate/head drift or a tracked write invalidates the cycle | **Use equivalence.** The review, C4 and summary must accept only an unchanged protected digest plus the durable receipt. |
| `plan-merge-to-main` | requires plan-branch head, candidate and PM decision SHA to be identical | **Use equivalence.** Merge the accepted equivalent head only after rechecking ancestry, policy and digest; retain the frozen SHA in provenance. |
| plan-mode release policy and `aid-evidence-verify --at-head` | derived artifacts must name the exact current candidate/HEAD | **Use equivalence only in plan-final context.** Default `--at-head` remains exact; an explicit plan-final receipt argument supplies the reviewed protected surface. |
| CP3 final review freshness | permits a separate hard-coded test/fixture/current-evidence exception plus a trailer | **Use equivalence.** Replace the private path exception with the shared EPIC-scoped protected surface and receipt, so ancillary docs/runtime commits do not force CP3 again while a production change still does. |
| C3 audit freshness/provenance | `audit-report.json` reviewed head must equal current HEAD | **Use equivalence.** Keep report/dispatch identity strict, but accept a reviewed protected surface proven equivalent by the shared receipt. |
| `plan-close-check` report freshness | has an independent docs-only annotation classifier | **Use equivalence.** Retire the separate broad docs classifier in favour of ancillary policy and a receipt; report self-annotation remains a named ancillary projection. |
| FSM init and plan sync/freeze/gates dirty-tree preflight | blocks any tracked dirt except a short hard-coded list | **Use the shared ancillary classifier for preflight only.** It may permit approved runtime dirt, but cannot itself assert a review remains fresh. |
| pre-commit scope guards | blocks commits outside the active run's allowed paths | **Exact scope only.** This is a prevention guard, not a review-freshness decision; do not weaken it through ancillary policy. |
| release preparation and gate waivers | release preparation requires a clean staging area; waivers bind one exact command/HEAD | **Exact-SHA-only for this slice.** Do not broaden release staging or waiver semantics incidentally; a future waiver-equivalence design needs its own PM decision and threat model. |

The matrix is an implementation gate: a focused fixture must demonstrate one
ancillary commit travelling through every consumer marked **Use equivalence**
without a second review, and a protected source/configuration change must fail
at every one of those consumers. A consumer not covered by that fixture is
treated as exact-SHA-only until deliberately added; it must never silently
inherit the relaxation.

### Acceptance

- A tracked runtime/reporting write in an allowed ancillary path does not
  invalidate a frozen candidate.
- An ancillary-only commit after freeze preserves the review only with a valid
  receipt and unchanged protected-surface digest.
- A commit changing a declared source, test, user document, plan or lifecycle
  manifest always invalidates review, even if its parent directory is broadly
  named ancillary.
- An undeclared new source/configuration path fails closed rather than becoming
  ancillary by omission.
- Fixtures cover an ancillary report commit, an unrelated planning document,
  a current-plan edit, a lifecycle-manifest edit, a durable-evidence edit and
  an attempted glob overlap; only the first two can be review-equivalent.
- The consumer-matrix full-path fixture proves that the same ancillary commit
  passes every declared equivalence consumer and that the corresponding
  protected-surface commit fails each one; release preparation, waivers and
  scope guards retain their deliberately exact behavior.

## 13. Validated follow-up — deeper Codex reviews and one PM exhaustion override

> **Plan written: P073 (EPICs 1 and 2)** — shipped in v2.72.0. D13 (the review
> budget raised from 3 to 5, with legacy ledgers keeping their old cap) and D14
> (one public PM force path on all eight lifecycle commands, bounded by a
> forceable/hard classification) are covered.
>
> **NOT covered, still unplanned:** D15 — making the Codex review instruction
> PROVE coverage rather than merely request it.

> **Plan written: P073 (EPIC 1 + EPIC 2)** — D13 budget raise (EPIC 1; PM
> confirmed 2026-08-04 from live experience that 3 sessions never suffice) and
> D14 unified PM force path (EPIC 2, without a separate `--accept-exhausted`
> flag — the forced lifecycle transition IS the risk acceptance) are tracked in
> `.aid-o/plans/P073-loosening-force-ancillary.md` (2026-08-04).
>
> **TODO — remaining after P073 (PM 2026-08-04: must be finished in a later plan):**
> - D15 (Codex coverage ledger) — deferred; if picked up, start with the soft
>   variant (risk lenses added to the prompt, no machine-checked coverage field).
> - Per-project policy override for the CP1 budget (P073 ships a constant of 5;
>   a real `.aid-o` policy-read path is deliberately NOT built until a consumer
>   project actually needs a different cap).

**Finding:** there are two real, independent Codex review loops, both set to
only three genuinely dispatched sessions today:

| Review | Current authority | Current budget | What it reviews |
|---|---|---:|---|
| C0 / CP1 | `review-checkpoints.yaml` → `cp1_codex_review.max_rechecks: 2` plus the CP1 revision ledger | initial review + 2 rechecks = **3** | a high-risk plan before EPIC generation |
| C3 | `c3-audit-policy.yaml` → `c3_fix_loop.max_rechecks: 2` | initial audit + 2 rechecks = **3** | a high-risk completed change-set before merge/close |

This is not one cross-plan global limit and it is not the generic
`execution.yaml.content_quality.max_review_fix_cycles` setting. C0's budget is
per plan and C3's is per review evidence/run. A Codex outage, timeout or
unparseable response is deliberately not charged as an iteration; a real
fresh review after a changed plan/HEAD is. Raising either configured value
therefore does not create repeated reviews of identical content.

The intent of the bound is sound: avoid an unattended agent repeatedly
changing a candidate until a reviewer happens to pass it. The present override
surface is not sound UX: C3 asks a human to set the internal environment
variable `AID_C3_FORCE_BEYOND_ESCALATION`, while C0 asks them to hand-create
and consume `cp1-pm-escalation-override.json`. Neither is a normal public PM
command, neither is discoverable from one place, and C3's environment value
does not itself make a durable, queryable PM decision receipt.

### D13 — increase the automatic budget, independently and explicitly

Change the shipped defaults to four rechecks for each Codex loop:

```yaml
# review-checkpoints.yaml
review_checkpoints:
  cp1_codex_review:
    max_rechecks: 4       # initial + 4 = 5 Codex C0 sessions

# c3-audit-policy.yaml
c3_fix_loop:
  max_rechecks: 4         # initial + 4 = 5 Codex C3 sessions
```

Five sessions is a practical default for a hard change: it permits discovering
an issue, fixing it, uncovering a consequence, and still converging without
normal work immediately becoming a PM escalation. It remains finite; projects
that need a lower cost/latency cap may override the two keys separately.

The implementation must remove every baked-in `2`/`3` assumption from C0
ledger validation, C3 summary/dispatch, CLI help, agent instructions and test
fixtures. Each controller reads the same policy key it enforces; an unreadable
or malformed value fails closed to the shipped default of four, not to an
unbounded loop. A completed session only consumes budget when it is bound to a
new plan hash (C0) or a new reviewed HEAD (C3); transient dispatch failures and
same-candidate retries remain uncharged exactly as today.

### D14 — one public PM force path for every exhausted review controller

Extend the universal PM override from §10 to the public C0 and C3 entrypoints.
The human-facing shape is always:

```text
<aid public command> ... --force --reason '<specific PM decision, at least 20 characters>'
```

No agent instruction, environment variable or hand-authored evidence file is
an authorized substitute. Internal controllers receive only a sealed,
single-use override receipt created by that public command; agents cannot make
one by exporting `AID_C3_FORCE_BEYOND_ESCALATION` or writing an artifact.

At a Codex budget/same-fingerprint/conflicting-findings exhaustion, force has
two deliberately distinct effects that must never be conflated:

1. **One additional review attempt.** `--force --reason` authorizes exactly
   one new, fresh C0 or C3 session for the next changed candidate. The receipt
   records the prior attempts, terminal reason, old and new candidate IDs,
   invoker, time and reason. It is atomically consumed; another exhausted
   attempt needs another explicit PM force. This is the ordinary answer to
   “give Codex one more chance”, not a hidden unlimited loop.
2. **Explicit risk acceptance.** A separate explicit public action such as
   `--force --reason ... --accept-exhausted` may advance despite a remaining
   blocking/unverifiable review only where the normal lifecycle transition is
   otherwise forceable. It writes `decision: forced_acceptance`, preserves the
   raw reports and every unresolved finding, and makes the final summary/close
   visibly non-PASS. It must never rewrite a failed or unverifiable C0/C3
   artifact into `pass`, nor silently make later evidence look clean.

The command must reject `--accept-exhausted` while a normal budget remains, so
it cannot become a shortcut around a review that could still be performed.
Both choices emit the same durable `pm-force-override` schema used by §10 and
are visible in `/aid-status`, the timeline, merge decision and plan-close
report. Existing C0 JSON artifacts and C3 environment variables are retained
only as migration inputs: they are converted into/validated against the new
receipt during one compatibility release, then rejected with an actionable
message. This gives the PM the requested backdoor everywhere, without giving
delegated agents a private bypass or producing a false audit PASS.

### D15 — make the Codex review instruction prove coverage, not merely request it

I reviewed the actual C0 and C3 prompts as a Codex reviewer. They already have
good foundations: read-only operation, prompt-injection boundary, sealed input
identity, a strict JSON schema, no-assumption rule, C0's six plan checks, and
C3's mandatory diff/evidence/gate/state-machine checks. I would follow them
and they catch several important classes of failure.

They do **not** yet make a complete review of a non-trivial change reliably
repeatable. C3's check-table is unusually strong on provenance, but its only
semantic deep-dive is state machines; a non-stateful API, error path,
concurrency, compatibility, authorization, performance or integration defect
can receive no explicit lens. C0 asks for feasibility and testability, but
does not require a reviewer to account for every declared deliverable or to
show which repository dependencies were inspected. In both prompts, a `pass`
can therefore be syntactically valid after a partial inspection.

Do not demand an impossible “review the entire repository” claim. Define
complete as: **every changed/declaratively affected path plus the bounded
dependency closure needed to understand its behaviour is accounted for**.
Add this shared reviewer contract to C0 and C3:

1. First build a coverage ledger from the real diff (C3) or declared plan
   deliverables (C0). Every item receives `inspected`, `not-applicable` with a
   reason, or `unverifiable`; `pass` is forbidden if an item is omitted or
   unverifiable without a finding.
2. Inspect each affected interface end-to-end: caller/input, validation,
   state/storage or side effect, output/consumer, failure handling and the
   tests/observability that prove it. Follow only the dependency closure needed
   for those paths; name every dependency read.
3. Apply risk lenses conditionally but explicitly: API/schema compatibility,
   authorization/data isolation, error and rollback behaviour,
   concurrency/idempotency, resource/performance impact, configuration and
   deployment/rollback, and user-visible documentation. A lens may be marked
   not applicable only with a concrete scope reason.
4. For every acceptance criterion, report its exact implementation evidence
   and test/gate evidence. A claimed gate PASS is supporting evidence, never a
   replacement for reading the changed implementation. C3 retains its strict
   hashing of runtime evidence; C0 retains its plan-to-repository grounding.
5. Findings must identify the affected file/contract and location or a precise
   plan section. If a location cannot be established, report that limitation as
   `unverifiable` rather than issuing an untraceable vague finding.

The JSON artifact schema needs a compact, machine-checked `coverage` field
(or a separately sealed coverage artifact referenced by it): reviewed items,
dependency paths, lens outcomes, AC mapping and explicit limitations. The
bridge validates that every C3 changed path / C0 declared delivery item occurs
once, that no claimed `pass` contains an unresolved limitation, and that the
coverage digest is bound to the reviewed candidate. This is preferable to
asking Codex to put prose outside its current strict output schema.

### Delivery and acceptance

1. Update both policy defaults, their schemas/validators and every user-facing
   count to five total Codex sessions; add fixtures proving C0 and C3 stop
   automatically after the fifth genuinely dispatched session, never after a
   timeout or same candidate.
2. Implement one public PM `--force --reason` receipt producer and route all
   C0/C3 exhaustion paths through it. Fixtures must prove a bare environment
   variable, a delegated agent and a hand-written legacy artifact cannot
   bypass; one receipt grants exactly one extra review; explicit forced
   acceptance stays visibly failed/unverifiable in all downstream reports.
3. Update C0/C3 prompt templates, response schema/normalizer and prompts tests
   with seeded defects for API compatibility, authorization, error/rollback,
   concurrency/idempotency, configuration and non-stateful semantic wiring.
   The test asserts a coverage ledger and a traceable finding, not merely a
   keyword in prompt text.
4. Update `/aid-help`, `/aid-plan`, `/aid-run`, pipeline instructions and role
   cards so an implementer stops on exhaustion and offers the PM the precise
   public command; it must never set an internal force variable itself.

**Acceptance:** ordinary high-risk C0 and C3 reviews have up to five fresh
Codex sessions and retain bounded, non-automatic behaviour. After any terminal
condition, the PM can either request exactly one more audited review or
explicitly accept the residual risk from a public command; no output is forged
as PASS. A Codex PASS demonstrates bounded coverage of all affected paths,
relevant dependency closure, applicable risk lenses and every acceptance
criterion, with any missing evidence made visible rather than assumed away.

## 14. Validated follow-up — human decisions in chat, minimal evidence behind it

### What already exists and what is missing

The original UX scope already establishes the correct principle in §2/D3/D4
and Slice 4: **outcome → meaning → relevant evidence/risk → one recommended
next action**, in the user's language, while JSON/protocol artifacts stay
machine-facing. `/aid-audit-tests` also has a concrete chat-handoff shape.

That is a useful start, but it is not yet a system-wide contract. It does not
inventory every point where AID or a delegated agent talks to the PM, it does
not define distinct shapes for success, a choice, a block and progress, and it
does not prevent several background files from restating the same human prose.
The current pipeline explicitly keeps `final_report.md`, `epic-summary.md`,
`pm-summary.md`, plan delivery reports, audit prose and raw agent outputs side
by side. Some are genuinely consumed by guards; others are projections or
legacy coexistence. They must not be removed on the assumption that they are
unused.

### D16 — two different output products, with different owners

Separate every output by audience and purpose:

| Product | Audience | Form | Rule |
|---|---|---|---|
| **Decision handoff** | PM in the active chat | short, natural language in the PM's language | rendered at a real decision/change/block boundary; says what happened and what to do now |
| **Evidence record** | controller, later agent, CI/audit tooling | canonical structured data plus only indispensable raw material | proves a fact, binds it to input/HEAD, or enables recovery; it is not a second chat transcript |
| **On-demand detail view** | PM when asking “why/show evidence” | deterministic rendering from canonical evidence | expands the decision handoff; it does not cause a new agent to invent a retrospective story |

No agent writes a long human narrative merely because a background directory
exists. A Markdown report is justified only when an identified human consumer
or a compatibility consumer needs it. Its producer, canonical input and
retention class must be explicit. The controller, not a delegated implementer,
owns the final chat handoff.

### D17 — mandatory chat decision cards

Audit every user-invocable command, every FSM/plan boundary, every
blocked/escalation/force path and every delegated-agent completion. Give each
one an `output_contract` entry: trigger, audience, whether a PM decision is
required, canonical facts it may use, renderer and evidence/detail command.
The inventory is an implementation prerequisite; a path absent from it cannot
quietly emit a final user-facing technical dump.

All final chat messages use plain language and the following small cards.
They are a skeleton, not a requirement to pad empty sections:

1. **Finished — no PM decision.**
   ```text
   Hotovo: <plain-language outcome>.
   Změnilo se: <1–3 user-relevant effects>.
   Ověřeno: <tests/gates or “neověřeno”, with the reason>.
   Další krok: <one concrete recommendation, or “nic dalšího není potřeba”>.
   ```
2. **Decision required.**
   ```text
   Potřebuji tvoje rozhodnutí: <one question>.
   Proč teď: <plain consequence of waiting/choosing>.
   Doporučení: A — <recommended action and consequence>.
   Alternativy: B — <meaningful alternative>; C — <stop/defer when relevant>.
   Riziko / co není ověřeno: <only material uncertainty>.
   ```
3. **Blocked or failed.**
   ```text
   Zastaveno: <the concrete blocker, not an internal error label>.
   Dopad: <what has not happened and what remains safe>.
   Doporučené řešení: <smallest safe action>.
   Pokud chceš převzít riziko: <the exact public --force command/decision>,
   <what it will and will not override>.
   ```
4. **Progress / handoff between agents.** One short status line while work is
   ongoing; at a true boundary, use one of the three cards above. Never paste
   command logs, full paths, raw JSON or an agent's chain of thought into chat
   by default.

Technical identifiers and a link/path to detail are optional final lines, not
the opening. A message must state the actual decision before naming `C3`, a
SHA, FSM state or a report file. It must never claim completion from an agent's
assertion alone; the renderer reads only the canonical controller verdict.

### D18 — evidence minimisation audit before consolidation

Run a read-only evidence inventory on current `main` before deleting or
renaming any artifact. For every runtime/evidence/report write, capture:

- producer and exact write location;
- schema/format and canonical input(s);
- every live reader/guard, including tests and external/project compatibility;
- whether it is authoritative proof, raw diagnostic capture, a derived view,
  a temporary workspace product or an obsolete duplicate;
- retention requirement, maximum size/line budget and safe pruning point; and
- which decision-card fact, if any, it supplies.

Publish this as a concise machine-readable registry plus a small human table.
The registry makes ownership and deletion mechanically reviewable; it is not
another prose report. A write with no reader, retention reason or declared
diagnostic value is a candidate for removal. A write needed by a guard remains
even if no PM reads it.

Apply these reduction rules after the inventory proves safety:

1. **One canonical fact, many renderers.** Keep one structured
   `release_decision`/review/gate record; derive chat and a requested detail
   view from it. Do not independently ask an agent to narrate the same result
   into `final_report.md`, `epic-summary.md`, `pm-summary.md` and delivery
   prose.
2. **Raw evidence is for reconstruction, not reading.** Preserve the smallest
   immutable raw response/log/command output required to prove or reproduce a
   verifier result. Compress, content-address or prune only after its declared
   retention window and only when no live verifier consumes it. Never replace
   it with a paraphrase.
3. **Derived prose is disposable.** A report that is a deterministic rendering
   of canonical JSON is generated on demand or retained only as a short
   compatibility projection. It cannot become an additional source of truth.
4. **No agent-transcript archives by default.** Store an agent's result as
   structured findings, references and bounded raw tool evidence, not a long
   “what I thought while working” document. A diagnostic transcript is opt-in,
   run-scoped and has a retention class.
5. **Bounded files and summaries.** Define per-artifact size/entry limits and
   deterministic truncation/roll-up rules. When a limit is reached, retain a
   digest, count, first/last relevant records and an explicit `truncated`
   marker; do not silently discard evidence or create a fresh essay.

The requested later reconstruction for a human is intentionally **not** a
background AID agent task. It is an on-demand controller view derived from the
canonical record, with links to raw evidence when needed. This prevents a
second layer of unread, potentially divergent “human summaries” from being
generated merely for archival purposes.

### Delivery and acceptance

1. Build the output-contract inventory and test that every public command and
   every terminal FSM/controller result has exactly one final chat renderer or
   is explicitly internal. Golden fixtures cover finished, decision-required,
   blocked, force-used and delegated-agent-handoff cases in Czech and preserve
   a user's chosen language for other locales.
2. Add a renderer contract test: final chat starts with the outcome/decision,
   contains the required card facts, has one recommended next step, and does
   not expose raw JSON/logs/internal jargon unless the user requested detail.
   Test structure and factual source, not subjective literary style.
3. Produce the evidence registry and consumer graph before changing writes.
   For each proposed deletion/consolidation, require a proof that no guard,
   status command, migration path, test or documented compatibility consumer
   reads it. Preserve a compatibility alias only for a bounded migration.
4. Consolidate only proven duplicate derived reports onto their authoritative
   JSON input; add size/retention tests for raw captures and prove that C0/C3,
   gates, force receipts and plan-close still reconstruct and verify exactly.

**Acceptance:** at every real decision point the PM immediately sees, in
human language, what happened, why it matters, the recommended next move and
only the material uncertainty. Background storage contains proof and compact
state rather than a pile of unread narratives. A later agent can reconstruct
the factual state from canonical records and bounded raw evidence, while the
PM can request a clear detail view without AID manufacturing duplicate prose.

## 15. Validated follow-up — proportionate visual proof without rebuilding the world

**Finding:** a real screenshot comparison caught a real UI defect (red dots on
unrelated fields), so visual verification must not be discarded just because a
change mostly deletes UI. Deletion can still change layout, focus, conditional
rendering or stale validation state. The cost described — a second container
over a detached worktree plus a fresh dependency install twice for one EPIC —
is nevertheless not a required consequence of trustworthy visual proof.

Current instructions conflict in emphasis: `/aid-run` says “after any UI step:
Playwright screenshot + compare”, while the role card correctly makes browser
verification conditional on a user-facing surface and a relevant acceptance
criterion. An isolated worktree or immutable revision is correct for a
reviewer, but it does **not** require a new dependency installation or a cold
container image for each visual comparison.

### D19 — visual verification is scoped to a visual delivery boundary

Replace the blanket “after any UI step” rule with a mechanical
`visual_verification` classification established from the plan and actual diff:

- **Required:** the step/candidate changes a user-visible component, CSS/layout,
  client interaction/state, route, visual asset, form/validation presentation,
  or has a UI/visual acceptance criterion or `visual_refs`.
- **Not required:** pure server, worker, API, test, documentation, build/CI or
  internal refactor change with no user-visible rendering path. It must record
  the concrete classification reason; it cannot simply say “not needed”.
- **Aggregate allowed:** several adjacent UI implementation steps may share one
  final visual delivery boundary when their acceptance criteria are evaluated
  together and no intermediate UI state is itself a promised deliverable.
  A plan that promises a specific intermediate visual state still needs proof
  at that state.

For a required boundary, capture a real flow and the specified desktop/mobile
viewports, compare with the declared reference where one exists, and keep the
current rule that a UI AC cannot be silently substituted with backend-only
proof. “Mostly deletion” is an input to the cost decision, not an automatic
skip. The normal default is one visual proof at the last affected UI boundary
of an EPIC, not one full environment preparation for every code step.

### D20 — fresh candidate runtime, reusable immutable build inputs

Separate what must be fresh from what may be cached:

| Must be fresh/bound to the candidate | May be safely reused when content-addressed |
|---|---|
| source revision, rendered application output, test fixture/data seed, browser run, screenshot, comparator result and command result | container base layers, browser binary, package-manager download cache and installed dependency layer keyed by lockfile + runtime/platform digest |

The runner creates a disposable process/container per visual candidate (or a
strictly reset equivalent), exposes only its own port and does not mutate the
primary worktree. It may reuse a cached image/dependency layer only when the
lockfile, package-manager version, Node/runtime platform and build-relevant
configuration digest match. Use the lockfile-respecting install command (for
example `npm ci`), never a fresh unconstrained `npm install` as routine test
setup. A changed lockfile, Dockerfile/base image, build configuration or
runtime dependency invalidates that cache key automatically.

The evidence receipt records candidate SHA, visual-surface digest, fixture/seed
digest, viewport/browser version, rendered image/container digest, command and
comparison result. This proves that cache reuse did not mean reuse of an old
application. The first cold run remains expected; repeated runs should reuse
the immutable dependency/build inputs and pay mainly for build-output and
browser startup, not dependency resolution.

### D21 — recheck only when visual evidence became stale

A completed visual proof remains valid for later non-visual changes only if a
shared resolver proves all of these: the prior candidate is an ancestor, the
visual-surface digest is unchanged, the lock/runtime/build digest is unchanged,
and the data fixture/command/browser viewport contract is unchanged. It then
writes a `visual-evidence-equivalence` receipt, analogous to §12's protected
surface receipt, rather than pretending the SHA did not move.

Any change to the visual surface or its runtime inputs invalidates the proof
and requires a fresh browser run. A final review may never reuse a screenshot
from a different visual digest merely because tests passed. If the environment
cannot be started, report `visual_unverifiable` clearly to the PM with the
smallest recovery action; do not describe backend tests as visual proof.

### Delivery and acceptance

1. Inventory and reconcile every current UI/screenshot instruction so
   `/aid-run`, pipeline, role cards, verifier prompts and plan templates use
   the same visual-boundary classifier rather than contradictory “every UI
   step” wording.
2. Add a visual runner with cache-key provenance and a disposable candidate
   runtime. Fixtures prove a second candidate with the same lock/runtime uses
   the dependency cache but produces a new candidate-bound screenshot; a
   lockfile/config change rebuilds; and no run mutates the main worktree.
3. Add visual-surface/equivalence fixtures: a documentation/test-only change
   preserves a valid screenshot with a receipt; CSS/component/route/form-state
   changes invalidate it; a UI AC cannot be accepted from API evidence alone.
4. Add timing telemetry for cold setup, cached setup, build, startup and
   browser comparison. The PM handoff reports the actual cost and whether it
   was required or reused, so a 35-minute cold path becomes diagnosable rather
   than folklore.

**Acceptance:** the red-dot class of visual regression is still catchable by a
real browser comparison, but one EPIC no longer performs multiple cold
`npm install`/container builds merely because an unrelated fix triggered a
review rerun. Every accepted screenshot is fresh for the visual surface it
proves, and every reuse is explicit, digest-bound and safe for the primary
worktree.

## 16. Validated follow-up — make auto mode own waits instead of pretending

> **Plan written: P076** — D22 (owned jobs: `run_mode: background` gates delegated
> to `aid-job.sh`, supervised-resumable-synchronous, crash-rerun re-attaches by
> command fingerprint), D23 (declared services + `lib/aid-service.sh` over
> aid-job: health probes, per-run ports, acquire-once/release-once lifecycle),
> D24 (eager `auto_resume_required.json` + single-use-claimed `resume` command +
> `auto_controller` status states + honest host card), D25 (machine-readable
> `auto-recovery.yaml` superseding the 2026-07-21 stop-taxonomy design,
> named per-class emitters, formalized Codex adjudication ending in
> ESCALATION / P073 force). The plan itself is
> `.aid-o/plans/P076-auto-mode-owned-waits.md` (2026-08-08) — **untracked**:
> `.gitignore` ignores `**/.aid-o/`, so that path resolves to nothing outside
> the authoring checkout and is named here as provenance, not as a citation a
> reader can follow. The supersede record is likewise split: the shipped half
> lives in `auto-recovery.yaml`'s own `supersedes:` block, because the
> 2026-07-21 document is untracked too and its section markers are not on the
> branch. (Plan-vs-shipped divergence, recorded rather than absorbed: this
> paragraph originally read *"reconciled with the 2026-07-21 stop-taxonomy
> design"*. Step 17 changed it to *"superseding"* because that is what shipped —
> `auto-recovery.yaml` carries a `supersedes:` block, not a reconciliation. The
> word was wrong, not the intent; the original wording is kept here so the
> correction is visible instead of silently overwritten.) Two config layers made
> explicit: `/aid-init`'s `execution.yaml`
> template gains the FIELDS only (`run_mode`, `needs_services` and a `services:`
> block that ships as commentary with zero active services), while
> `auto-recovery.yaml` and three JSON schemas ship as new template files with
> content; the bats_all/bats_boundary background flip lands solely in
> aid-orchestrator's own project config.
>
> **STILL OPEN after P076 (each registered as an IMP backlog entry by the plan —
> numbers allocated 2026-08-09 in `docs/plans/2026-06-29-BACKLOG.md`):**
> - **IMP-484** — fire-and-return ASYNC gates (the runner returning before job
>   completion); P076 ships the supervised-synchronous variant only;
> - **IMP-485** — services↔resource-map integration (`service-resources.jsonl`
>   emission is observe-only evidence; the shared-port classifier stays
>   untouched);
> - **IMP-486** — foreground-gate `timeout -k` hardening (foreground path kept
>   byte-identical);
> - **IMP-487** — visual-companion server migration onto `lib/aid-service.sh`;
> - **IMP-488** — a true host push-continuation adapter (task-notification
>   behaviour stays instruction-only host guidance; the artifact is the enforced
>   fallback).
>
> Each backlog entry states what shipped instead, why it was deferred, and the
> `file:line` hook point of the P076 mechanism it would extend. Cross-reference
> consistency between this block and the backlog is enforced by
> `plugins/aid-orchestrator/scripts/tests/bats/test-p076-backlog-closure.bats`.

### Current state and root cause

The desired rule is already written in `aid-run.md` and `pipeline.md`: in auto
mode the controller must not end merely because a test, backend operation or
reviewer is running; it records PID/log/revision/deadline, polls liveness and
resumes/diagnoses after five minutes without progress. `aid-job.sh` is a solid
primitive: it owns a process group, survives a controller crash, records a
terminal receipt, detects PID reuse and can mark stale results.

But the primitive is explicitly **opt-in**, not required by `/aid-run` or the
gate/controller path. More importantly, it supervises a shell process; it
cannot itself resume an LLM turn after the host has ended that turn. The result
is a false promise: an agent can write “waiting for tests/backend” and finish,
with no persistent controller left to poll or take the next action. `--auto`
then means auto-approval at a few FSM decisions, not end-to-end autonomy.

This is not solved by making timeouts infinite or allowing an implementer to
own background processes. The fix is explicit ownership and a real
continuation mechanism.

### D22 — first-class owned jobs for every long operation in auto mode

In auto mode, every command expected to exceed a small foreground threshold
(default 30 seconds, project-configurable) must be classified before launch as
one of `test_or_gate`, `service_readiness`, `build`, `browser`, `external_read`
or `reviewer`. The controller launches it through one shared job API backed by
`aid-job.sh`; direct `&`, `tail -f`, sleep loops and “agent will tell us when
done” are prohibited.

The durable job record contains the existing identity/provenance fields plus
owner run/plan, operation class, allowed recovery policy, expected p95, hard
deadline, poll interval, source revision/tree hash and successor action. The
controller stores the job ID in FSM/run state before releasing its own turn.
A delegated agent may request a job handoff, but it never starts/owns the
long-lived operation itself.

On each poll the controller performs exactly one of these mechanical actions:

| Job state | Controller action |
|---|---|
| running and before deadline | record bounded progress; continue safe independent read-only/controller work if any; otherwise schedule the next poll — never claim it completed |
| terminal pass at current candidate | collect receipt, bind it as evidence, continue the FSM automatically |
| terminal fail | collect log tail + structured result, run the declared bounded diagnosis/recovery path, then retry only when policy permits |
| timed out / lost / stale | cancel/reconcile process group, preserve receipt, diagnose once; route to technical recovery or a PM decision according to authority |
| no live job and no progress for watchdog interval | resume from the last confirmed FSM boundary and diagnose; it is never an indefinite waiting state |

`aid-gate-runtime-baseline.sh` already learns a p95 and recommends background
mode after enough samples. Wire that recommendation into this dispatcher
instead of leaving it as unused telemetry. Unknown jobs begin conservatively
with an explicit deadline; their observed duration feeds the same baseline.

### D23 — backend/service readiness is an active state machine

Waiting for a backend is not one opaque operation. Add a controller-owned
readiness contract per declared service: start/attach command, scoped
environment/port, health probe, expected startup p95, hard deadline, log
source, reset/cleanup command and whether automatic restart is authorized.

The state flow is `absent → starting → healthy | unhealthy | timed_out |
lost`, with durable transitions. Polling uses the declared health probe, not a
sleep or a log line. Before escalating, the controller may perform only the
pre-authorized bounded repairs (for example one restart, stale owned-container
cleanup, or a migration command explicitly declared safe). It then either
continues, produces a concrete technical failure for Codex adjudication, or
asks the PM only for missing authority: credentials, an externally shared
service, destructive reset, material configuration change or security risk.

Every auto-started service is namespaced to the run/worktree and cleaned by the
same owner. A controller must never wait on an unowned shared backend whose
state it cannot inspect or safely recover.

### D24 — honest host continuation capability

An AID shell job cannot summon a model by itself. Implement one explicit
host-adapter boundary:

- where the host supports durable scheduled/resumed agent execution, register a
  `resume_token`/callback when the owned job starts; terminal job state queues
  exactly one idempotent controller continuation;
- where it does not, write `auto_resume_required.json` with the exact run,
  expected job ID/state and safe next controller action, and render a short
  honest chat card: “test is still running; AID will not claim to continue by
  itself in this host — resume with … after this job is terminal.”

The status surface shows `auto_controller: active | awaiting_host_resume |
manual | blocked_for_pm`, never just `auto`. `/aid-help` and `/aid-run --auto`
must describe this capability before starting work. A host without continuation
is useful semi-autonomy, but it must not be marketed as unattended execution.
When an adapter exists, deduplicate resume requests by job ID + terminal
receipt digest so a crash, repeated poll or duplicate notification cannot
dispatch two fixers or advance the FSM twice.

### D25 — bounded autonomous recovery, not autonomous scope growth

For each job class configure an allowlisted recovery ladder: diagnostic reads,
one safe restart/retry, targeted test rerun, then a Codex adjudication among
pre-authorized reversible actions. The ladder has attempt/time budgets and
records each action. It stops for PM only when the next step changes product
intent/scope, needs credentials or external coordination, risks data/security,
would be destructive, or would require `--force` risk acceptance.

This keeps the useful part of autonomy — tests finish, a known backend is
started/restarted, a timeout is diagnosed and an unambiguous retry happens —
without turning auto mode into permission for hidden resets or endless retries.

### Delivery and acceptance

1. Inventory all long-running controller operations and replace direct waits
   with the shared owned-job dispatch. Test that auto mode cannot finish a turn
   with an unrecorded in-flight process or a bare “waiting” status.
2. Wire gate p95/background recommendations into job dispatch and add fixtures
   for pass, failure, timeout, lost PID, stale candidate and watchdog resume.
   A terminal receipt must cause one continuation, never zero or two.
3. Implement service readiness contracts with namespaced fixtures covering
   healthy start, failed health probe, one allowed restart, deadline, cleanup
   and a shared/unowned backend that correctly asks for PM authority.
4. Implement and test the host-adapter capability states. Without an adapter,
   the CLI/status/chat handoff says `awaiting_host_resume`; with one, a
   simulated terminal job resumes the controller from the recorded FSM boundary
   exactly once.
5. Update agent cards: implementers never wait on, silently detach or report
   completion of a test/backend job; they hand it to the controller with its
   declared contract.

**Acceptance:** auto mode no longer dies in “waiting for tests/backend”. In a
capable host it continuously polls and resumes its recorded work; in an
incapable host it reports the precise continuation limit instead of pretending
to be autonomous. Long jobs and services are bounded, owned, diagnosable and
safe to recover, while PM interruption remains reserved for decisions that
actually need PM authority.

## 16a. Validated follow-up — one PM force for the whole EPIC-generation transaction

> **DELIVERED: P074 (EPIC 3), v2.73.0 (2026-08-06)** — D26 generation-authority
> receipt + public `--force --reason`, D27 transaction manifest/resume, and the
> three 2026-08-04 generation defects (adjudicator empty-list parse,
> escaped-pipe table parser, target-branch diagnosis) all shipped; the plan is
> `.aid-o/plans/P074-project-concurrency-generation-transaction.md` (2026-08-05).
> Added beyond the four items below: `supersede-generation` as a separate
> audited invocation, the stale-`queue_status` receipt-rewrite fix, and the
> identity-bound queue-ownership rule (a queue entry is only "ours" when the
> transaction can prove it, never by epic id alone).
>
> **STILL OPEN after P074:** delivery item 4's `host_permission_or_session_blocked`
> class — P074 deliberately ships only the two AID-owned labels
> (`aid_cp1_blocked`, `aid_generation_force_required`) plus verbatim passthrough
> of unrecognized subprocess failures; a reliable host-error detector has no
> defined signature today and would be guesswork.
>
> **ALSO STILL OPEN (found by P074's own two-stream acceptance fixture,
> `test-p074-integration.bats`):** generation completes stage 1 (authority once,
> every phase generated and recorded) but the pipeline's stage 2 — the per-phase
> run initialisation — does not reach a queued EPIC in either configuration once
> a second stream is genuinely in play. For a LEGACY plan, `aid-fsm.sh init`
> runs in the primary checkout, auto-creates and checks out `task/<epic>/main`
> there, and only then refuses on its own (deliberately kept) uncommitted-changes
> guard — leaving the PM's checkout on that task branch. For a `plan_branch`
> plan it correctly redirects into the plan's own worktree and then refuses on
> the plan-branch lineage check, because the pipeline never runs `epic-start`
> for the EPICs it has just generated. Both are pinned as tests with their exact
> production messages.

### Confirmed current failure

The universal lifecycle-force intent in §10/D6 is correct, but it does not yet
cover this entrypoint precisely enough. Today `aid-auto-pipeline.sh` accepts
only `--force-init-reason`, not public `--force --reason`. It invokes
`aid-plan-to-epic.sh` once for every phase, and that script invokes the CP1
gate every time. CP1's current override artifact is deliberately one-shot: the
first phase atomically consumes it. The second phase therefore blocks despite
the PM having authorized generation of the same plan.

This is a control-scope bug, not evidence that the PM did not grant authority.
CP1 evaluates one source plan; it is nonsensical to make a PM re-authorize the
same failed CP1 condition separately for each deterministic phase derived from
the unchanged plan.

The proposed shell loop is not a safe workaround. Each call starts the full
pipeline at phase 1; it has no phase-resume contract, and can allocate duplicate
EPIC/run IDs or recreate partial outputs. Rewriting the artifact before each
call also leaves an unclear audit trail. Do not normalize this pattern.

An AID force can override only AID's own CP1/lifecycle checks. It cannot grant
host-level Bash permission, defeat a sandbox/rate-limit policy or resurrect an
ended agent session. If the reported “system guard above me” is the agent host,
the public AID command must fail honestly with that host error; the PM needs a
host-approved invocation, not another AID receipt.

### D26 — generation authority is plan-scoped, not phase-scoped

Make `/aid-plan epic` and its public CLI controller (`aid-auto-pipeline.sh`)
accept the standard form:

```text
aid-auto-pipeline.sh --plan <plan> --queue-mode chain \
  --force --reason '<PM decision, at least 20 characters>'
```

Normal generation runs CP1 once against the source plan **before any phase
output, counter allocation, task branch or lifecycle state is written**. It
creates a sealed `generation-authority` receipt bound to:

- plan ID and exact source-plan hash;
- target branch/head and generation mode;
- deterministic total-phase count and phase derivation version;
- CP1 verdict/evidence references, or every failed condition bypassed by PM;
- public invoker, timestamp and the force waiver/reason where applicable.

The receipt is a transaction capability, not a general bypass. It authorizes
only generation of the exact phase set for that exact source plan and target
head. Each internal `aid-plan-to-epic` call verifies this receipt instead of
running/consuming CP1 again. Standalone `aid-plan-to-epic` retains its existing
CP1 gate, so this does not create an undocumented lower-level escape hatch.

With no force, a passing CP1 receipt likewise covers all phases of the one
pipeline transaction. With force, one public PM decision covers all and only
those phases. The result carries `forced_override: true` and the exact CP1
failure; it is never rewritten as a clean CP1 pass.

### D27 — generation is resumable and duplicate-safe

Before producing phase 1, create a durable transaction manifest. For each
phase it records `not_started | generated | packaged | initialized | queued`,
the allocated EPIC/run identifiers, output hashes and the source-plan hash.
Write each transition atomically before proceeding.

On repeat invocation with the same source-plan/target/derivation identity,
the controller resumes from the first unfinished phase and verifies existing
outputs rather than allocating a second EPIC. A different plan hash, target
head or phase count is a new transaction and must explicitly supersede/abort
the old incomplete one; it never silently mixes artifacts from both.

The force receipt is retained with that transaction and remains valid across a
crash/resume only for its exact manifest. It is not re-consumed by phase 2 or
silently reusable by a later changed plan. A PM can cancel the transaction;
the cancellation records what was generated and leaves cleanup/branch deletion
to the existing lifecycle-safe recovery path.

### Delivery and acceptance

1. Add public `--force --reason` parsing and help to the plan-generation
   controller, routed through the §10 audit receipt writer. Reject internal
   environment variables and hand-created CP1 artifacts as the normal public
   interface after a bounded compatibility migration.
2. Move CP1 invocation to the plan-transaction boundary and implement sealed
   generation-authority receipt verification for internal phase generation.
   Fixtures prove three high-risk phases invoke CP1 once, and one forced PM
   grant authorizes all three without presenting a false PASS.
3. Add transaction manifest/resume fixtures: crash after phase 1 resumes at
   phase 2 with the same IDs; rerun never duplicates a queue entry/counter
   allocation; altered source plan/head rejects the old receipt; standalone
   phase generation still fails closed without CP1 authority.
4. Render failures clearly: distinguish `aid_cp1_blocked`,
   `aid_generation_force_required`, and `host_permission_or_session_blocked`.
   Only the first two offer an AID force command; the host case names the
   external approval/continuation limitation rather than promising a bypass.

**Acceptance:** a PM who force-authorizes generation of a fixed high-risk plan
gets one audited, resumable transaction that generates its complete declared
EPIC set. Phase 2 never asks again for the same CP1 decision, no rerun creates
duplicates, and a host-level permission block is reported honestly rather than
misdiagnosed as an AID gate.

## 17. PM requirement — project-level concurrency: plan while implementing

> **DELIVERED: P074 (EPIC 1 + EPIC 2), v2.73.0 (2026-08-06)** — scoped
> preflights, locked plan-ID allocation, active-runs map, shared root resolver
> + worktree-safe hooks (EPIC 1), and per-plan execution worktrees with
> command-level enforcement, in-worktree branch topology, teardown/repair and a
> two-stream status surface (EPIC 2) all shipped; the plan is
> `.aid-o/plans/P074-project-concurrency-generation-transaction.md` (2026-08-05).
> Also delivered, beyond the EPIC 1/2 headline: `work/active.md` as a generated
> index with named writers, and the audited `plan-state --recreate-worktree`
> repair.
> This is NOT the archived intra-plan parallelism plan
> (`docs/plans/archive/AID-parallelism-re-enable-plan.md`, multiple agents
> inside one plan) — that remains deferred.
>
> **STILL OPEN after P074:** the ~17 class-B root-resolution sites using
> `git rev-parse --show-toplevel` (each already honours the `AID_PROJECT_ROOT`
> override, now canonicalized) — deferred to a later normalization sweep;
> stale line cites in this section (init dirty guard is at `aid-fsm.sh:2824-2825`,
> not `:2661`); the legacy `active-run-pointer.json` fallback reader, kept for
> one release and due for removal after it.
>
> **ALSO STILL OPEN — the concurrency promise stops at run initialisation.**
> P074's own two-stream fixture (`test-p074-integration.bats`) proves plan B can
> be allocated, written and GENERATED from the primary checkout while plan A
> implements in its worktree, with the primary checkout's HEAD byte-identical
> across every plan-B command. It also proves the promise does not yet reach a
> queued EPIC when a second stream is live: for a legacy plan, `aid-fsm.sh init`
> still refuses on the PM's unrelated dirty tracked edit AND leaves the primary
> checkout on the `task/<epic>/main` branch it auto-created; for a `plan_branch`
> plan it redirects into the plan's own worktree (where the dirty edit is
> irrelevant, as designed) and then refuses because the pipeline never
> `epic-start`s the EPICs it just generated. See §16a for the same two gaps from
> the generation side.

### User story

While plan A is being implemented (agent working), the PM must be able to:

1. brainstorm and write plan B — allocate a new plan ID, create the plan file
   in `.aid-o/plans/`, run CP1, generate its EPICs and evidence scaffolding;
2. do unrelated manual development in the same repository outside AID; and
3. keep their primary checkout free — implementation work must not hold the
   PM's working tree hostage (branch switches, dirty-tree refusals).

Today this simply does not work: generation and lifecycle preconditions assume
one active stream per checkout.

### Known concrete blockers (grounded 2026-08-04 during P073 work)

- Clean-worktree preflights refuse to start lifecycle operations when the tree
  carries ANY unrelated tracked work: `aid-plan-fsm.sh:274`
  (`_pfsm_check_clean_worktree`, plan-start/epic-start) and `aid-fsm.sh:2661`
  (`cmd_init`). The PM's in-progress manual edits block starting/generating
  another plan.
- EPIC generation SWITCHES THE BRANCH of the working checkout (`aid-fsm.sh
  init`, lines ~2596-2607, checkout of the task branch) and restores it
  afterwards (`aid-json-to-run.sh:722-731`) — the PM's checkout is briefly
  hijacked, and concurrently running implementation in the same checkout makes
  this a collision. P073 EPIC 1 Step 6 only makes a FAILED restore loud; it
  does not remove the hijack.
- Shared mutable runtime state under one `.aid-o/` (counter.yaml allocation,
  queue.yaml, work/plan-state/) is written by both streams; today's answer is
  the dirty-exception list, not real per-stream isolation.
- P073 EPIC 3 loosens post-freeze dirt classification, which helps, but does
  not give implementation its own worktree.

### Direction (to be designed in its own brainstorm, not here)

- Implementation (EPIC execution) runs in a DEDICATED git worktree per plan
  (`git worktree add`), so branch switches, dirty trees and gate runs never
  touch the PM's primary checkout. §15 D20 (disposable candidate runtime) and
  §16 D23 (services namespaced to run/worktree) already point this way for
  their subsystems; execution should follow.
- Planning-side operations (brainstorm, plan write, CP1, EPIC generation) must
  either not require a clean PRIMARY tree at all, or scope their cleanliness
  checks to the paths they actually touch.
- Concurrent-safe ID allocation and queue writes (two streams may allocate a
  plan ID / append to the queue at the same time — needs flock or equivalent,
  some of which exists in adjacent tooling already).
- One PM status surface that shows both streams without conflating them.

**Sequencing:** design AFTER P073 merges (its force/ancillary/preflight changes
touch the same files); candidate ID P074. Intra-plan parallelism (the archived
plan) stays a separate, later decision.
