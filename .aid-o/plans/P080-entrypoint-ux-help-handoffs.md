---
id: P080
type: plan
status: draft
created: 2026-08-09
author: PM + AI
risk: high
---

# Plan: Entry-Point UX — Help Coverage, Init/Setup Ownership, Human-First Handoffs

## Stakeholder Brief

AID gained capabilities faster than its front door was updated: `/aid-help` today does not mention 4 of the 13 public command surfaces, advertises a help topic that does not exist in the file, and tells a brand-new user to run `/aid-setup` first — which itself refuses to run before `/aid-init`. Init and setup both write the same four configuration files with no declared owner, init's own text claims it absorbed setup while later routing users to setup, and a fresh init produces a permissions file whose key structure setup cannot read. Final agent handoffs are inconsistent: exactly one flow (test audit) has a deterministic human summary; everything else ends in free-form or metrics-first technical dumps. This plan fixes all three areas and makes the fixes self-enforcing: a machine-readable help index with a coverage test (a new public command fails CI until it is intentionally indexed), a single-owner table for every init/setup-written file backed by an idempotency test, and one shared communication contract — the PM's four chat decision cards — plus deterministic renderers that also publish a visual Artifact page per the ecosystem artifact standard (7-block skeleton, template-enforced caps, computed-not-claimed numbers). Risks: this plan rewrites instruction surfaces that P076 is concurrently rewriting (aid-run.md, pipeline.md, aid-status.md, one aid-help.md paragraph), so implementation is gated on P076's merge and the help rewrite folds around P076's landed auto-mode paragraph. The evidence-registry and visual-verification work from the same source document is deliberately split into a separate follow-up plan.

## Context

Source document: `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md` §1–9 (D1–D5, Slices 1–5) plus §14 (D16–D17 chat decision cards; D18 evidence minimisation is split out) — chosen by the PM on 2026-08-09 as the next stream ("blok č. 4") while P076 implements in a parallel worktree. Two independent grounding sweeps verified every claim file:line against main (v2.79.3, HEAD d822957); one adversarial Codex round converged with near-total adoption (record: `.aid-o/work/interim-P080.md`). The PM approved the split (this plan = EPICs 1–3; evidence registry + visual reconciliation = separate follow-up plan after the parallelism-removal work lands) and added one binding requirement: EPIC 3 outputs must ship as Artifact pages per the ecosystem artifact standard (`/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md`) with an AID-specific template spec published to Docusaurus. Key grounded facts this plan stands on: all 12 command files carry uniform `name`/`description`/`user_invocable` frontmatter and `skills/visual-companion/SKILL.md` is a 13th slash-callable surface; no mechanical help-coverage test, no setup behavior test, and no workspace-level init idempotency test exist anywhere; the enforcement registry contains three rows citing the nonexistent `commands/aid-research.md`; exactly one deterministic chat renderer exists (`lib/aid-test-audit-chat-summary.sh`, presented verbatim by the controller, already Artifact-first); `pm-summary.md` has a hard mechanical reader (`aid-plan-fsm.sh` plan-finalize refuses without it); the step-index seam has P073 prior art (`_fsm_human_step`, aid-fsm.sh:830-840) used at only 3 call sites while an identical "Step rendering rule" paragraph is copy-pasted verbatim in 4 instruction files; and P076 is rewriting aid-run.md/pipeline.md/role-cards.md/aid-status.md plus one aid-help.md paragraph targeting an "auto-mode topic region" that does not exist yet.

## Goal

Every public AID surface is mechanically discoverable through an accurate help layer, every init/setup-written file has exactly one declared owner protected by tests, and every final user-facing outcome is delivered as an outcome-first decision card in the PM's language — with structured flows additionally rendered deterministically into a one-screen Artifact page that links to the full evidence.

## Scope

**In scope:**
- Machine-readable help index (`defaults/help-index.yaml`, checked-in only — never copied into `.aid-o/`) covering all public command surfaces, with disposition, topic route, audience, config-ownership and output-contract columns; a coverage test enforcing bijection between real surfaces, the index, and `commands/aid-help.md`.
- Full rewrite of `commands/aid-help.md`: truthful topics (including the advertised-but-missing `status` topic and new `tests`, `plan-lifecycle`, `generation`, `recovery`, `init` topics), corrected first-run ordering (init before setup), removal of stale claims, an explicit statement of the plan-release model, and next-action guidance reusing `/aid-status`'s existing `next_epic` recipe by reference.
- Enforcement-registry hygiene: a cite-validation test (every `source:`/`instruction:` path must exist) plus repair of the three dangling `aid-research` rows and the stale `init_idempotency` cite.
- Init/setup single ownership: carve-out paragraphs for the four double-written files (permissions.yaml, project.yaml, integrations.yaml, CLAUDE.md) following the existing gate_profiles precedent; removal of aid-init.md's false "merges setup" claim; one authoritative workspace item count; footer placement fix; roots-vocabulary paragraphs in both files; init's permissions template gains the `active_preset` key setup reads; one preset vocabulary sourced from `defaults/policies/permissions.yaml`.
- Shared read-only configuration summary renderer `scripts/aid-config-summary.sh` printed by both init (end) and setup (start), bats-tested on fresh and customized fixtures.
- Workspace-level init idempotency test: fresh create, re-run on a customized fixture (zero byte changes outside declared exceptions), declined-upgrade untouched.
- One shared communication reference `skills/communication.md` carrying the PM's four decision cards (§14 D17 verbatim), the D16 audience/product table and the language rule; a mechanical wiring test asserting required surfaces reference it and superseded inline fragments are gone.
- AID artifact template family per the ecosystem artifact standard: a deterministic artifact renderer library with template-enforced caps and computed tiles, templates shipped in the plugin, and an AID artifact-template spec page for Docusaurus (cross-repo deliverable to `/opt/eco/docs`).
- Two new deterministic renderers reusing existing canonical JSON: gate/waiver outcome (from the merged gate report) and plan-close (from `pm-decision-brief.json`), each emitting a chat card plus an artifact body, wired with verbatim-presentation tests.
- Step-index seam finish: "Plan Step N" human rendering on the defined public seams via `_fsm_human_step`, and collapse of the six verbatim "Step rendering rule" copies (across five files) to one referenced section, including the rewrite of the shipped bats block that currently requires the full text in five files. Machine fields and evidence filenames stay frozen.
- Contributor docs (`docs/extending-aid.md` new sections incl. the human ownership table), enforcement-registry entries for every new mechanical check, CHANGELOGs and release metadata per repository policy.

**Out of scope:**
- Evidence-write registry, retention/pruning rules, and visual-verification reconciliation (§14 D18, §15 D19–D21) — split into the follow-up plan agreed with the PM on 2026-08-09, sequenced after the parallelism-removal work lands.
- Implementing the versioned all-project settings schema (IMP-261) — this plan discharges only its analysis portion via the ownership/disposition inventory; the schema is its own future plan per source doc §4.
- Merging `/aid-init` and `/aid-setup` into one command (source doc §6 non-goal).
- Any automatic audit after EPICs/plans, any generic LLM tone/prose gate (source doc §2/§6).
- Editing historical plans, changelog archives, or transcripts — only live instruction surfaces are swept.
- Changing any FSM state semantics, evidence filename, or protocol JSON shape — `current_step`, `verify-state` JSON and evidence filenames remain frozen compatibility surfaces.
- An external-audience artifact specification (ecosystem standard explicitly defers it).

## Approach

Chosen approach: **index-and-enforce** — make the help/ownership/handoff facts machine-readable once (help index, ownership columns, output contracts), rewrite the prose surfaces from those facts, and add cheap deterministic tests that fail when reality and index drift apart. Renderers reuse existing canonical JSON producers rather than deriving new state, and the artifact layer is a deterministic template fill (script computes tiles, caps and truncation; the model writes only bounded prose blocks), following the ecosystem rule "brevity is enforced by the template, not requested politely".

Alternatives considered and rejected: (a) parsing `aid-help.md` prose as the coverage authority — rejected with Codex: recreates a brittle parser, the checked-in YAML index is the authority; (b) one plan carrying the evidence-registry and visual work too — rejected: those EPICs additionally depend on the parallelism-removal outcome and would hold EPICs 1–3 hostage; (c) three separate inventory files (ownership doc + output-contract doc + help index) — rejected with Codex: one index file with columns, one human table in contributor docs; (d) LLM-only cards without deterministic renderers for gates/plan-close — rejected: deterministic verdicts matter precisely where waivers and releases are decided.

## Architecture

Three layers, each independently testable:

1. **Inventory layer** — `defaults/help-index.yaml` is the single machine-readable authority for public surfaces. Row schema: `command` (slash name), `file` (repo-relative source), `purpose` (one line), `topic` (aid-help topic route or `none`), `audience` (`beginner|regular|power|internal`), `disposition` (`current|update|index_only|intentionally_internal|remove_or_deprecate`), `writes` (list of config files this command may write, empty for read-only), `final_turn` (`renderer:<script>` | `card:<type>` | `internal`). Disposition semantics are exact: `current|update` require a topic route; `index_only` is indexed without a topic route; `intentionally_internal` must NOT appear in help. The enumerator that feeds the coverage test discovers surfaces mechanically: frontmatter of `plugins/aid-orchestrator/commands/*.md` (awk over lines 1–6, the shipped convention) plus `plugins/aid-orchestrator/skills/*/SKILL.md` directories.
2. **Prose layer** — `commands/aid-help.md`, `commands/aid-init.md`, `commands/aid-setup.md` and the swept instruction files are rewritten FROM the inventory; each fix is anchored to a grounded defect (listed per step). The help rewrite lands after P076's merge and integrates P076's auto-mode paragraph into the new topic structure.
3. **Handoff layer** — `skills/communication.md` defines the four cards and the language rule once; `lib/aid-artifact-render.sh` provides the deterministic artifact skeleton (7 blocks: header, tiles, human summary, core, related links, "what I need from you", detail link) with hard caps (5 findings, 3 next steps, ~220 chars/sentence, overflow truncated with an explicit count); `lib/aid-gate-outcome-summary.sh` and `lib/aid-plan-close-summary.sh` render chat card + artifact body from their canonical JSON inputs, following the `aid-test-audit-chat-summary.sh` precedent (fail closed, controller presents verbatim, Artifact-first mandate). The FSM's `_fsm_human_step` is the one step-rendering helper.

Data flow for a rendered outcome: canonical JSON (merged gate report / pm-decision-brief.json) → renderer lib (computes tiles + assembles capped blocks) → (a) chat card text on stdout, (b) artifact body file in the run's evidence dir → controller publishes the artifact via the Artifact tool and presents the chat card verbatim with the artifact link appended.

## Implementation Steps

**EPIC 1: Steps 1-4 — Command inventory and mechanical help coverage**

### Step 1: Create the machine-readable help index

**Objective:** Create `defaults/help-index.yaml` covering all 13 public surfaces with the full column schema, so coverage tests and later ownership/output-contract columns have one authority file.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/help-index.yaml` — one row per public surface (12 commands + visual-companion) with command/file/purpose/topic/audience/disposition/writes/final_turn columns; header comment documents the exact disposition semantics and the enumeration contract.

**Architecture Context:** This is the inventory layer's authority file (Architecture §1). Every later step that changes a command's help route, config ownership or final-turn contract updates its row here first; the coverage test (Step 2) makes drift failing. It is checked-in only — `/aid-init` never copies it into `.aid-o/` (Codex-adopted decision: no second source of truth, no init idempotency complication).

**Implementation Detail:** YAML list `surfaces:` with one mapping per surface. Populate from the grounded inventory: the 12 files in `plugins/aid-orchestrator/commands/` (all `user_invocable: true`) plus `skills/visual-companion/SKILL.md`. Initial dispositions: `current` for aid-do/aid-run/aid-status/aid-stop/aid-audit; `update` for aid-help/aid-init/aid-setup/aid-plan (their prose changes in this plan); `index_only` for aid-verify-plan/aid-verify-implementation/aid-audit-tests/visual-companion until Step 3 gives them routes (Step 3 flips them to `current` with topics `plan-lifecycle`/`tests`). `writes:` starts populated for init (workspace + config files it creates) and setup (permissions/integrations/CLAUDE.md/project re-scan) from the Step 5 ownership decisions — enter the target filenames now, exact owner semantics land in Step 5. `final_turn:` starts as `card:finished` for most, `renderer:aid-test-audit-chat-summary.sh` for aid-audit-tests; Steps 11-12 update gate/plan-close consumers. Keep the file under 120 lines; no prose beyond the header comment.

**Error Handling:** Malformed YAML must fail the Step 2 test loudly (`yq` parse error propagates, test exits nonzero with the yq message). A surface listed twice → the coverage test's uniqueness assertion fails naming the duplicate slash name.

**Edge Cases:**
- A skills directory without `SKILL.md` (e.g. `skills/setup/`) — enumerator matches only `skills/*/SKILL.md`, so `skills/setup/*.md` flat files are correctly excluded.
- Flat skills carrying `user_invocable: false` — inert metadata per grounding; the enumerator ignores flat skills entirely and the header comment documents why.
- A future command added with `user_invocable: false` — enumerator keys on the flag value, indexes it only if `true`; the header comment states internal commands still get an `intentionally_internal` row so the classification is explicit, not accidental.

**Dependencies:**
- Depends on: none
- Blocks: Step 2 — the test consumes this file; Step 3 — the rewrite is driven by it.

**Acceptance Criteria:**
- [ ] `yq '.surfaces | length' defaults/help-index.yaml` returns 13.
- [ ] Every row has all 8 columns non-empty (`writes` may be `[]`).
- [ ] Disposition values are only from the 5-value enum; semantics documented in the header comment.

**Effort:** S
**AID Role:** backend

### Step 2: Coverage test — surfaces ↔ index ↔ help bijection

**Objective:** Add a deterministic test that fails whenever a public surface, the help index, and `commands/aid-help.md` disagree — the §5 Slice-1 acceptance ("a newly added public command fails until intentionally indexed").

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-help-index-coverage.bats` — enumerates real surfaces, asserts index bijection and help routing per disposition semantics.
- Create: `plugins/aid-orchestrator/scripts/lib/aid-help-index.sh` — sourceable enumerator + index reader shared by the test (and any future consumer): `aid_help_enumerate_surfaces <plugin_root>` (awk frontmatter scan of `commands/*.md` lines 1-6 for `user_invocable: true`, plus `skills/*/SKILL.md` glob) and `aid_help_index_rows <index_path>` (yq → TSV).

**Architecture Context:** The enforcement half of the inventory layer. It follows the shipped frontmatter convention (fixed line-window scan, the same approach as `aid-lint-skill.sh:58-70`) rather than introducing a YAML frontmatter parser; file type and flag position are uniform across all 12 commands per grounding.

**Implementation Detail:** Bats cases: (1) enumerated set == index `command` set (diff both directions, name missing/extra entries); (2) uniqueness of slash names in the index; (3) for every row with disposition `current|update`: its `topic` value appears as a literal `### Topic: <topic>` heading in `commands/aid-help.md` AND the command's slash name appears somewhere in that topic's section body (extract section with awk from `### Topic: <t>` to next `### ` or EOF); (4) for every advertised topic in help's router table: a matching `### Topic:` section exists (kills the advertised-but-missing class); (5) `intentionally_internal` rows do NOT appear anywhere in aid-help.md outside fenced code blocks (reuse the `fenced_stripped()` awk pattern from `aid-lint-skill.sh:39-44`); (6) every `file` column path exists. The test discovers the plugin root via `$AID_PLUGIN_PATH` like sibling bats suites (`test-aid-test-scheduler.bats:26` precedent).

**Error Handling:** If `commands/aid-help.md` is missing the router table (grep for the topic-list line fails), the test fails with a message naming the expected anchor, not a silent pass. yq absent → standard bats `skip`-free hard failure (yq is a repo-wide hard dependency).

**Edge Cases:**
- Command mentioned only inside a fenced example in help — case (3) must match outside fences only, so a code-block mention does not satisfy routing.
- Topic present in a section but absent from the router table — case (4) run in both directions: router ⊆ sections and sections ⊆ router.
- Index row `index_only` — must appear in the index but no routing assertion; must still pass case (6).

**Dependencies:**
- Depends on: Step 1 — consumes the index file.
- Blocks: Step 3 — the rewrite must land green against this test.

**Acceptance Criteria:**
- [ ] Test fails on current main's aid-help.md (proves it detects the 4 known missing surfaces and the missing status topic) — demonstrated in the step's verify output by running it BEFORE Step 3 lands.
- [ ] Adding a dummy `commands/aid-x.md` with `user_invocable: true` in a fixture makes the suite fail with the surface named.
- [ ] Suite is auto-discovered by `run-all-tests.sh` (naming convention `test-*.bats`, no registration needed).

**Effort:** M
**AID Role:** qa

### Step 3: Rewrite aid-help.md truthfully from the index

**Objective:** Rewrite `commands/aid-help.md` as an outcome-oriented index that routes every public surface, fixes all grounded false claims, and folds in P076's landed auto-mode paragraph.

**Files:**
- Rewrite: `plugins/aid-orchestrator/commands/aid-help.md` — new topic structure, all public surfaces routed, grounded defects fixed.
- Modify: `plugins/aid-orchestrator/defaults/help-index.yaml` — flip the four `index_only` rows to `current` with their new topics.
- Modify: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — remove `commands/aid-help.md` from the GRANDFATHERED list (it already lints clean, so delisting is free) per the plan-level grandfathering decision below.

**Architecture Context:** Prose layer regenerated from the inventory (Architecture §2). P076 has now MERGED and its auto-mode text has already landed inside `### Topic: run` (`commands/aid-help.md:155-190`, verified at CP1) — so this step is a **MOVE of shipped content** into the new `### Topic: auto` section, not the authoring of a new paragraph. Move it unchanged.

**Implementation Detail:** Keep progressive disclosure (Level 0–3) but make it truthful: Level 0 = `/aid-init` → `/aid-setup` → `/aid-do` → `/aid-status` in that order (fixes the grounded init/setup ordering contradiction: setup refuses without init); the "Level 0 = 3 commands" self-description line is corrected to match the actual list. Topic set: `do, run, plan, plan-lifecycle, generation, tests, gates, recovery, config, fsm, init, setup, status, auto` — each with a `### Topic:` section; the router table lists exactly these. New content anchors: `tests` routes `/aid-audit-tests` (catalog/audit surface, aligned with whatever survives the parallelism removal — implementation rebases on the then-current audit command text); `plan-lifecycle` routes `/aid-verify-plan` + `/aid-verify-implementation` + plan_branch lifecycle; `status` documents the four `/aid-status` sub-surfaces; `recovery` covers `/aid-stop`, resume, escalation and points to the P073 force surface (public commands only, no internals). Fix the stale claim at the config topic: `execution.yaml` is eagerly generated by `/aid-init` (P032) with `aid-fsm.sh init` auto-recovery as fallback. State the release model explicitly in the plan-lifecycle topic: `plan_branch` = one release at plan end; `legacy_epic_release_mode` = per-EPIC release; name the coupling "declining the gate_profiles upgrade at init silently selects legacy mode" (grounded at aid-init.md:690-694). Next-action guidance: the status topic states "run `/aid-status` — its next-EPIC line is computed by the shipped `next_epic` recipe" (reference, not reimplementation). Footer `**Last Updated:** 2026-08-09` (or implementation date).

**Error Handling:** If at implementation time the P076-merged aid-help.md differs from the grounded baseline (P076's paragraph landed somewhere unexpected), the implementer reconciles by moving P076's text into the auto topic unchanged and records the move in the step's verify output — never deletes P076-landed content.

**Edge Cases:**
- `/aid-audit` vs `/aid-audit-tests` confusion — both routed, one line in each topic disambiguating the other.
- The bogus `/aid-token-count` token match in old help (a script path, not a command) — the rewrite must not carry it as a command reference.
- A user on a legacy in-flight plan — plan-lifecycle topic keeps the explicit legacy route wording (source doc Slice 2 item 8: never retroactively claim plan_branch).

**Dependencies:**
- Depends on: Step 2 — the rewrite must turn that test green.
- Blocks: Step 14 — final wiring sweep references the new topics.

**Acceptance Criteria:**
- [ ] `test-help-index-coverage.bats` passes on the rewritten file.
- [ ] `grep -c '^### Topic:' commands/aid-help.md` equals the router-table row count.
- [ ] `grep -n 'execution.yaml.*lazy-created' commands/aid-help.md` returns nothing — narrowed deliberately: :263 (execution.yaml) is the stale claim, but :264 (queue.yaml, genuinely created by `aid-queue-add.sh`) is TRUE and a blanket ban on the phrase would delete a correct line.
- [ ] The plan-lifecycle topic contains both mode names verbatim (`plan_branch`, `legacy_epic_release_mode`).
- [ ] P076's landed text survives the move: a distinctive P076 literal (`awaiting_host_resume`) appears exactly once in the rewritten file.
- [ ] `bash scripts/aid-lint-skill.sh commands/aid-help.md` reports zero findings, and the file no longer appears in `test-skill-lint.sh`'s GRANDFATHERED list.

**Grandfathering decision (CP1) — binds Steps 3, 5 and 6, and each of them carries it in its OWN Files list and ACs (a decision stated only here would never reach a per-step dispatch):** `commands/aid-help.md`, `commands/aid-init.md` and `commands/aid-setup.md` sit on the GRANDFATHERED list in `scripts/tests/test-skill-lint.sh` (~:30-51), which downgrades their structural lint findings to advisory. All three are substantively rewritten by this plan, and the repo's CLAUDE.md requires delisting a file once it is brought up to standard. Measured at CP1: aid-help.md and aid-setup.md already lint clean, so delisting them is free; aid-init.md costs three `version_stamped_heading` fixes. Therefore Step 3 (aid-help.md) and Steps 5-6 (aid-init.md, aid-setup.md) each add `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` to their Files list, remove their own file from the GRANDFATHERED array, and add the AC `bash scripts/aid-lint-skill.sh <their file>` reports zero findings. If a file cannot be brought clean inside its step, that step records an explicit PM-visible decision to keep it grandfathered — never a silent retention.

**Effort:** M
**AID Role:** docs-writer

### Step 4: Enforcement-registry cite validation and repair

**Objective:** Add a registry-hygiene test asserting every registry `source:`/`instruction:` file path resolves, and repair the rows it flags today — the MEASURED repair set, not the three `aid-research` dangles the source doc assumed (two independent CP1 measurements bracket the repair set at **9–13 rows** — iteration 1 counted 13 with a coarser tokeniser, iteration 2 counted 9 after the per-token skip below, because 4 of the enumerated rows resolve cleanly under the corrected rule. The candidate set is: `c2_completed_lenses_e5`, `c2_wiring_gate_observe`, `knowledge_base_write_protect`, `knowledge_dedup_threshold`, `provenance_aggregate_fabricated`, `recovery_escalation_terminus`, `release_version_sealed`, `research_idempotency`, `research_quality_gates`, `test_audit_catalog_approval_boundary`, `test_audit_never_auto_invoked` (active) plus `release_policy_preempted`, `semantic_wiring_would_block` (planned). **The implementer MEASURES the real set with the finished parser before repairing anything** and records the measured list in the verify output; the numbers here are a bracket, not an authority.)

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh` — walks `defaults/enforcement-registry.yaml` rows, extracts the file component of `source:` and `instruction:` values, resolves each against the registry's THREE real cite bases (below), and fails on any token resolving under none; allowlist for `n/a`/`planned` scalar values; also asserts row-`id` uniqueness (`yq '.enforcements[].id' | sort | uniq -d` must be empty — closes the append-duplication class this step and Step 16 both create).
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — repair the measured 13 rows (repoint to the real owning surface, or mark `status: dead` with rationale per the registry's own schema, recording the decision as a `(P080 Step 4: …)` suffix on the row description), refresh the `init_idempotency` row's stale line cite to the current Idempotency section, and register the Step 2 coverage test as a new enforcement row (`help_index_coverage`, type structural check, source the bats file, severity blocking, surface internal-guard).

**Architecture Context:** Class-wide fix per Codex adoption №7: not just the three known bad rows but a test that keeps every future cite honest. Line-number drift is deliberately NOT asserted (too brittle); file existence is the invariant. The new test lands in `scripts/tests/` as a flat harness (auto-discovered by `run-all-tests.sh:164`).

**Implementation Detail:** Parse with `yq -o=json` then jq iterate rows; for each `source`/`instruction` string: skip the exact scalar values `n/a` and `planned`. **The "no slash = prose label" skip is applied PER TOKEN, after tokenising — never per whole value.** Measured at CP1: applying it per value leaves ~40 false positives, because a value like `scripts/aid-fsm.sh (search: 'foo') + Step 3` contains a slash overall while several of its split tokens are prose and must be dropped individually. A token containing no `/` is prose and is skipped; the harness cannot exit 0 otherwise.

*Resolution order per path token* (the registry's cite base is MIXED — measured at CP1: 430 tokens resolve only under the plugin root, 2 only under the repo root, and a third convention writes bare `lib/…` meaning plugin+`scripts/`): (1) plugin root `plugins/aid-orchestrator/`, (2) repo root, (3) plugin root + `scripts/`. A token resolving under **none** of the three is a violation. `-e` is the test, so directories are accepted.

*Tokenising:* split on `;` and ` + `; take the leading path token of each part; strip a trailing `:<digits>`, `:~<digits>`, `:<identifier>`, `'s` (possessive), ` §…`, ` (…)`, ` — …`, ` Step …`. All four annotation grammars are present verbatim in the shipped file (`scripts/aid-plan-fsm.sh:cmd_plan_finalize --stage gates`, `scripts/lib/review-profile-check.sh:~84`, `scripts/aid-fsm.sh's`, `scripts/aid-plan-to-epic.sh (search: '…') + lib/aid-scoping.sh:_aid_classify_files_bullet`) — a parser handling only `;`/`:N`/`§` reports hundreds of false dangles.

Emit one line per violation `CITE|<row-id>|<field>|<path>`; exit 1 on any. Repair rule: a cite whose only resolution is an **untracked** path is itself a violation — repair the row, never allowlist the path.

**Error Handling:** A row with an unparseable structure (missing `id`) fails the test with the row index, so hand-edited registry corruption is caught here rather than in downstream consumers. The TTL guard (`aid-registry-ttl-guard.sh`) is untouched and must stay green.

**Edge Cases:**
- Multi-path sources like `"a.sh; b.sh"` — both validated.
- Sources citing directories (`skills/visual-companion/`) — `-e` accepts directories; allowed.
- Rows with `status: removed_scoped` keep citing removed files by design — skip path validation for `status: dead|removed_scoped` rows.

**Dependencies:**
- Depends on: Step 2 — registers that test's enforcement row in the same edit.
- Blocks: Step 16 — final registry additions build on a clean baseline.

**Acceptance Criteria:**
- [ ] Against the pre-repair registry the test exits 1 flagging exactly the rows the finished parser MEASURES (the measured list recorded in the verify output and reconciled against this step's 9–13 bracket), plus a deliberately corrupted cite injected into a fixture as a negative control; after the repairs it exits 0 with zero false positives.
- [ ] No `source:`/`instruction:` VALUE references `commands/aid-research.md` outside a `status: dead` row (prose descriptions are out of scope — registry line ~226's active `knowledge_base_write_protect` row mentions it only in its description and is not in this step's scope).
- [ ] `yq '.enforcements[].id' defaults/enforcement-registry.yaml | sort | uniq -d` is empty.
- [ ] Registry totals comment updated per its own recompute command.

**Effort:** L
**AID Role:** backend

**EPIC 2: Steps 5-8 — Init/setup single ownership**

### Step 5: Ownership adjudication in both command surfaces

**Objective:** Give every init/setup-written file exactly one declared owner with explicit carve-outs, and remove the grounded contradictions in `aid-init.md` (false merge claim, three item counts, content after footer, missing roots vocabulary).

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — remove line 7's "Merges the old `/aid-setup` interactive onboarding" claim (init CREATES initial files; setup MUTATES them later — state that); **recount the real fresh-init product before stating it** — the currently-claimed "6 files + 5 directories = 11 items" is itself false, because a fresh init also eagerly generates `config/execution.yaml` (:114-124, P032). State ONE base manifest (the 6 files + 5 directories PLUS `config/execution.yaml`) and two separately labelled categories: **git hooks** (pre-commit :433-434, pre-push :502 — consumer-repo files AID owns only within its markers) and **conditional writes** (`config/integrations.yaml` :404, written only when the memory integration is enabled — not part of the base count). State the recomputed base count ONCE and reconcile the four existing count statements: frontmatter `description` (:3, currently "10-file"), `## Files Created (11 total)` (:16), the `Total:` line (:35) and `- **11 items**` (:668). Repair the `## Lazy-Created (NOT at init time)` heading (:577) whose first row is the init-EAGER execution.yaml — move that row out or rename the heading. Move the `## Plan mode` section (lines ~682-696) above the `**Last Updated:**` footer; add a roots paragraph after the workspace-creation section: `.aid-o/` is created at the state root resolved per `lib/aid-roots.sh` semantics (primary checkout, never a linked worktree — same contract `commands/aid-status.md` documents), including behavior when invoked from inside `.aid-worktrees/plan-*`; add carve-out sentences at each of the four file-creation sites: "created here; subsequent changes are owned by `/aid-setup` (module X) — `/aid-init` re-runs never rewrite it".
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` — mirror carve-outs in the module table ("mutates files created by `/aid-init`; never creates the workspace, never runs migrations/upgrades — those are init-owned"), extend the existing gate_profiles carve-out block (lines ~83-89) into a four-row ownership list covering permissions.yaml, project.yaml, integrations.yaml, CLAUDE.md; add a 3-line roots note (state root = primary checkout; running setup from a linked worktree edits the primary checkout's config).
- Modify: `plugins/aid-orchestrator/defaults/help-index.yaml` — fill the `writes:` columns for aid-init and aid-setup rows with the adjudicated owner semantics (`creates:` vs `mutates:` prefixes on each filename).
- Modify: `plugins/aid-orchestrator/scripts/tests/test-skill-lint.sh` — remove `commands/aid-init.md` and `commands/aid-setup.md` from the GRANDFATHERED list per the plan-level grandfathering decision (aid-setup.md already lints clean; aid-init.md needs three `version_stamped_heading` fixes, applied in this step).
- Modify: `README.md` (repo ROOT — verified at CP1: the command table is at :66-78, "10-file structure" at :72 and "auto-configures everything" at :110; `plugins/aid-orchestrator/README.md` contains none of these strings) — the 9-row command table gains the missing `/aid-setup`, `/aid-verify-plan`, `/aid-verify-implementation`, `/visual-companion` rows; :110 "auto-configures everything" becomes "init creates, setup configures"; :72's "10-file structure" references the init doc's recomputed count. Root `README.md` is also touched by Step 16 (version bump line) — the two steps must not both rewrite :110.

**Architecture Context:** Prose layer (Architecture §2) driven by the inventory's `writes:` columns. The adjudication follows the source doc D1 table exactly: init owns create/upgrade/additive migration; setup owns explicit chosen-configuration change. The gate_profiles carve-out at aid-setup.md:83-89 is the shipped precedent being generalized.

**Implementation Detail:** Ownership decisions (from grounding, PM-approved via interim): `permissions.yaml` — init creates from template, setup owns all later preset/custom changes; `project.yaml` — init auto-detects and creates, setup's project-scan module owns re-detection updates; `integrations.yaml` — init writes only `memory.enabled: true` at creation, setup owns enable/disable changes; `CLAUDE.md` — setup's claude-md module is the sole AID writer (init's current "mandates Vulcan ecosystem references" text becomes a pointer to the setup module — init itself stops instructing CLAUDE.md content). Each carve-out is one or two sentences at the existing write site, not a new section. The README edit keeps its table format and adds no new prose sections.

**Error Handling:** If implementation finds an additional double-write site not in the grounded four, it adds the same carve-out pattern and records the addition in the verify output — silent extra owners are the defect class this step exists to kill. The sweep MUST be wider than the three-file grep the source doc assumed: `grep -rn 'permissions.yaml\|project.yaml\|integrations.yaml\|CLAUDE.md' commands/ skills/ agents/ scripts/` — CP1 already found one third writer this way (`agents/project-scanner.md:46-50`, Mode B, Orchestrator-triggered post-milestone, output "Extended project.yaml"), and three shipped surfaces contradict each other on it (scanner ":1097 each scan overwrites the previous", `skills/setup/project-scan.md:43,48` "merge, preserve custom fields", `skills/memory.md:72` "NEVER write to project.yaml"). The `project.yaml` carve-out must therefore name the scanner as a **delegated writer under setup's project-scan module** and reconcile those three claims, not assert a two-owner model that main already falsifies.

**Edge Cases:**
- `permissions-auto.yaml` (exists in `.aid-o/config/` per grounding) — distinct file, not part of the four; if either surface mentions it, its owner is stated in the same pass; if neither does, out of scope.
- A consumer project that hand-edited an init-owned file — idempotency contract (never overwrite existing) already covers it; the carve-out text must not promise re-generation.
- The `--upgrade` path — additive upgrades stay init-owned (gate_profiles precedent already states this); carve-outs must not accidentally forbid them.

**Dependencies:**
- Depends on: Step 1 — writes into the index's columns.
- Blocks: Step 6 — vocabulary fix builds on adjudicated ownership; Step 8 — idempotency test asserts the declared exceptions.

**Acceptance Criteria:**
- [ ] `grep -n 'Merges the old' commands/aid-init.md` returns nothing; exactly ONE base-count sentence remains and the frontmatter `description` agrees with it (the three legacy phrasings — "10-file", "(11 total)", "**11 items**" — grep to nothing).
- [ ] `config/execution.yaml` appears in the base manifest and no longer sits under the `## Lazy-Created (NOT at init time)` heading.
- [ ] No content follows the `**Last Updated:**` footer line in aid-init.md (tail check).
- [ ] Both files contain the string `lib/aid-roots.sh` at least once; each of the four filenames has a carve-out sentence naming the other command in both files, and the `project.yaml` carve-out names the project-scanner as a delegated writer.
- [ ] Repo-root `README.md`'s command table lists all 13 public surfaces.
- [ ] `bash scripts/aid-lint-skill.sh commands/aid-init.md` and the same for `commands/aid-setup.md` report zero findings, and neither file appears in `test-skill-lint.sh`'s GRANDFATHERED list.

**Effort:** M
**AID Role:** docs-writer

### Step 6: Permissions template and preset vocabulary unification

**Objective:** Make a fresh init produce a permissions.yaml that setup can read, and correct the ONE stale preset surface. Measured at CP1: `yq '.presets | keys' defaults/policies/permissions.yaml` returns exactly `["autonomous"]` (plus the `custom` overlay documented at :15), so `skills/setup/permissions.md:60` "Two presets: autonomous (default), custom" is **already correct** and the single stale surface is `commands/aid-setup.md:80`, which names two presets (`aspirin`, `steroids`) that exist nowhere in the policy file.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (lines ~284-292) — permissions template block: template gains `active_preset: autonomous` and a comment naming `defaults/policies/permissions.yaml` as the preset catalog; keeps `autonomous_mode`/`auto_commit`/`auto_push` keys unchanged. State the first-run display rule explicitly, because the seeded pair is contradictory on its face (see the two canonical display strings in Implementation Detail below).
- Modify: `plugins/aid-orchestrator/skills/setup/permissions.md` — the preset claim at :60 is CORRECT and stays; only the menu render changes, to tolerate a missing `active_preset` key on legacy workspaces (treat as `autonomous`, offer to write the key).
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (line ~80) — replace the stale `(autonomous, aspirin, steroids)` list with `autonomous` plus the `custom` overlay, per the policy file.
- Modify: `plugins/aid-orchestrator/commands/aid-help.md` — config/setup topics: same preset names.

**Architecture Context:** The grounded defect: init's template has no `active_preset` key while setup's first menu read expects it; and three surfaces disagree on preset names. Single source of truth = the shipped policy file; every prose surface cites it instead of restating the list where possible.

**Implementation Detail:** Read `defaults/policies/permissions.yaml` at implementation time to re-confirm the authoritative preset set; the policy file WINS over every prose claim, in both directions — a prose surface naming a preset the policy file does not define is corrected, and a prose surface that already matches the policy file is left alone. **Two display cases, two canonical strings, used VERBATIM by all three surfaces (`commands/aid-init.md`, `skills/setup/permissions.md`, and Step 7's `aid-config-summary.sh`) — no third phrasing anywhere.** Case A, key present: `<preset> (preset) — autonomous_mode: <value>`, so a fresh workspace reads `autonomous (preset) — autonomous_mode: false`, which is honest rather than self-contradictory. Case B, key absent (legacy workspace): `autonomous (implicit — key missing, will be written on first change)`. The legacy-tolerance behavior in setup/permissions.md is instruction text (setup is prose-executed, no script — grounded), phrased as the exact conditional "if `active_preset` is absent: display case B".

**Error Handling:** If the policy file itself is missing in a consumer project (init not re-run since it shipped), setup's instruction says to fall back to the plugin's `defaults/policies/permissions.yaml` copy — the plugin path is always present.

**Edge Cases:**
- Workspace with hand-written `active_preset: custom` and a custom block — menu shows it verbatim; unification must not rename user values.
- `permissions-auto.yaml` coexistence — untouched by this step.

**Dependencies:**
- Depends on: Step 3, Step 5 — every step number is listed BEFORE the em dash, because `parse_step_deps` truncates the line at the first em dash and a number in the prose tail is silently dropped. Step 5 lands the ownership carve-outs this edit references; Step 3 rewrites `commands/aid-help.md` wholesale, which this step also modifies, so it must land after that rewrite or the two race on one file.
- Blocks: Step 7 — the summary renderer prints the preset value this step makes coherent.

**Acceptance Criteria:**
- [ ] The init template block contains `active_preset:`.
- [ ] No prose surface names a preset key absent from `.presets` in `defaults/policies/permissions.yaml`: `grep -rn 'aspirin\|steroids' commands/ skills/` returns nothing.
- [ ] Both canonical display strings appear in aid-init.md, in `skills/setup/permissions.md` and in Step 7's renderer, and NO other phrasing of the preset display exists across the three surfaces (grep each string; grep that no fourth variant appears).

**Effort:** S
**AID Role:** docs-writer

### Step 7: Shared read-only config summary renderer

**Objective:** One deterministic script both init and setup present, reporting the effective configuration without mutating anything — discharging source doc §5 item 11 and IMP-261's read-only "config effective" surface.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/aid-config-summary.sh` — bash+yq, read-only; prints: detected state root (via `lib/aid-roots.sh`), workspace present yes/no, plan mode default + why (gate_profiles present → plan_branch; absent → legacy with the named reason), gate profile list, permissions `active_preset` (with the legacy-absent fallback wording from Step 6), dispatch mode from orchestration config, and plugin version from `.claude-plugin/plugin.json`.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-config-summary.bats` — fixture-driven: fresh empty repo (no `.aid-o`), configured fixture (custom preset + gate_profiles), worktree invocation resolving to the primary root.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — final section, before footer: init's closing output = run `scripts/aid-config-summary.sh` and present its output verbatim, replacing the current ad-hoc summary prose.
- Modify: `plugins/aid-orchestrator/commands/aid-setup.md` (lines ~44-56) — menu preamble: setup opens by presenting the same script's output before the module menu.

**Architecture Context:** The one net-new runtime component of EPIC 2. Sourcing pattern per repo convention (`SCRIPT_DIR` + `source lib/aid-roots.sh`); read-only contract stated in the header ("never writes; a missing workspace is a report line, not an error"). yq is an existing repo-wide dependency (Codex objection overridden with that fact in the interim).

**Implementation Detail:** Exit codes per repo convention: 0 = rendered (even for "no workspace"), 2 = usage, 3 = unresolvable root (propagates `aid_state_root`'s loud failure outside a git repo). Output is a fixed-order plain-text block (one `label: value` per line, stable ordering for fixture tests). Reads: `.aid-o/config/execution.yaml` (`gate_profiles` keys via yq), `.aid-o/config/permissions.yaml` (rendered with the two canonical display strings defined in Step 6 — verbatim, no third phrasing), `.aid-o/config/orchestration.yaml` if present else plugin default path, `.aid-lifecycle/manifests/` count for active plan modes. Every read guards file absence with an explicit `absent` value — no empty strings.

**Error Handling:** Unreadable YAML in any config file → the line renders `<file>: unparseable (yq: <first error line>)` and the script still exits 0 — a summary must summarize a broken config, not crash on it.

**Edge Cases:**
- Invocation from inside `.aid-worktrees/plan-*` — root line shows the primary checkout path (bats-asserted).
- Repo with `.aid-o` but no `config/` subdir (ancient v1) — workspace line says `present (v1 layout — run /aid-init --upgrade)`.
- No git repo at all — exit 3 with the roots lib's own error text.

**Dependencies:**
- Depends on: Step 6 — renders the unified preset vocabulary.
- Blocks: Step 8 — the idempotency fixtures reuse this script's fixtures pattern.

**Acceptance Criteria:**
- [ ] Bats: fresh fixture renders `workspace: absent`; configured fixture renders the custom preset and gate profile names; worktree fixture resolves the primary root.
- [ ] `grep -rn 'aid-config-summary.sh' commands/aid-init.md commands/aid-setup.md` shows both wiring points.
- [ ] Script contains no write operation (`grep -nE '>>|>[^&]|yq -i|sed -i' scripts/aid-config-summary.sh` returns nothing beyond the shebang-safe matches; reviewed in verify).

**Effort:** M
**AID Role:** backend

### Step 8: Workspace-level init idempotency test

**Objective:** Fixture-based proof of init's contract: fresh creation matches the declared item set; re-run changes zero bytes outside declared exceptions; a declined upgrade leaves the tree untouched.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/test-init-idempotency.sh` — flat harness (init is LLM-executed prose, so the test exercises the SCRIPTED parts init delegates to plus the declared file manifest): builds a fixture repo, replays init's scripted operations (`lib/aid-init-execution-yaml.sh` compose, `lib/aid-gitignore-backfill.sh`, hook install from `defaults/hooks/`, config defaults copy from `defaults/`), snapshots `sha256sum` of the tree, replays again, diffs — asserting only the declared exceptions may change; then simulates the declined gate_profiles upgrade path (skip the append) and asserts byte-identity. **The declared exception set is `config/execution.yaml`'s generated header timestamp** (`lib/aid-init-execution-yaml.sh:336-337` writes `date -u` into it — the real and only source of non-determinism in the scripted substrate); the test normalises that line before diffing. `work/active.md` is NOT an exception here: it is written by the lifecycle layer, not by any script this harness replays (`commands/aid-init.md:594-597`), and aid-init.md:610 states the opposite of :594 about it — Step 5 reconciles those two lines and this test asserts the reconciled statement.
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` — Idempotency section: add one sentence naming this test as the mechanical anchor of the contract.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — the `init_idempotency` row gains a `test:` field pointing at the new harness and flips verdict `unmapped` → `ALIGNED`.

**Architecture Context:** Closes the verified absence "no workspace-level init idempotency test". The test cannot execute LLM prose; it pins the scripted substrate and the file manifest, which is where every past idempotency regression lived (gitignore backfill, hook marker blocks, execution.yaml compose).

**Implementation Detail:** Fixture = `mktemp -d` + `git init` + minimal package.json for stack detection. The recomputed Step 5 base manifest hardcoded in the test and cross-checked against the single count sentence in aid-init.md (grep the authoritative count line — drift between doc and test fails the test, keeping Step 5's single count honest). Hook replay uses the marker-block replace path twice to prove marker idempotency. Use `sha256sum` manifest diff, not mtime.

**Error Handling:** If a replayed lib writes outside the fixture (absolute-path bug), the tree diff catches unexpected paths; the test also runs the replay under `cd fixture` with `AID_PROJECT_ROOT` set to the fixture to keep the roots contract honest.

**Edge Cases:**
- Existing customized `execution.yaml` in the fixture — compose must not run (init's contract: never overwrite existing); test asserts byte-identity for it.
- Pre-existing non-AID `.gitignore` content — backfill appends only missing lines, second run appends nothing (grounded per-line contract).
- Hooks installed by an older AID (different marker content) — replace-within-markers only; bytes outside markers untouched.

**Dependencies:**
- Depends on: Step 5 — asserts the count/exceptions Step 5 made authoritative.
- Blocks: Step 16 — registry totals recompute includes this row's update.

**Acceptance Criteria:**
- [ ] Harness passes; deliberately corrupting one hook marker in the fixture makes it fail naming the file.
- [ ] Second replay produces an empty tree diff after normalising the one declared exception (execution.yaml's generated-at header line).
- [ ] Declined-upgrade branch: `diff -r` between before/after returns empty.

**Effort:** M
**AID Role:** qa

**EPIC 3: Steps 9-16 — Human-first handoffs, artifact layer, step seam**

### Step 9: Shared communication reference with the four decision cards

**Objective:** One short skill file carrying the PM's four chat cards, the D16 audience table and the language rule — plus a mechanical test that required surfaces reference it and superseded inline fragments are gone.

**Files:**
- Create: `plugins/aid-orchestrator/skills/communication.md` — `user_invocable: false`; contents: the D16 three-product table (decision handoff / evidence record / on-demand detail view with owners), the four card skeletons from source doc §14 D17 VERBATIM (Finished / Decision required / Blocked / Progress), the ordering rule (outcome first, technical identifiers as optional final lines, never claim completion from an agent's assertion — render only the canonical controller verdict), and the language rule (conversation and final cards in the PM's language; documents per `document_language`, whose real and only home is `defaults/orchestration.yaml:10` — verified at CP1: neither `defaults/language.yaml` nor `.aid-o/config/language.yaml` exists anywhere, so promoting brainstorming.md's claim verbatim would enshrine a stale contract).
- Modify: `plugins/aid-orchestrator/skills/brainstorming.md` (:399) — correct the same stale `language.yaml` cite to `defaults/orchestration.yaml` in this edit, so the SSOT has exactly one statement.
- Create: `plugins/aid-orchestrator/scripts/tests/test-communication-wiring.sh` — asserts (a) each required surface (`commands/aid-run.md`, `commands/aid-do.md`, `commands/aid-plan.md`, `commands/aid-audit-tests.md`, `skills/run-management.md`, `skills/pipeline.md`, `agents/reporter.md`, `agents/simplifier.md`, `commands/aid-verify-implementation.md`, `commands/aid-verify-plan.md`) contains the literal reference `skills/communication.md`; (a2) **publication wiring** — each site that invokes a renderer ALSO carries the publish-before-present clause, so the PM's binding "EPIC 3 output ships as Artifact pages" requirement has a mechanical enforcement rather than only prose (CP1 found it had none; registered as `artifact_publication_wiring` in Step 16, per principle #1 "Detector without Enforcement is Decoration"). **The assertion greps ONE canonical literal, defined in `skills/communication.md` and reused verbatim by Steps 11 and 12** — today those two steps word the clause differently, which would let a loose grep pass on a paraphrase. The enumerated sites are exactly: `commands/aid-run.md` (gate boundary) and `commands/aid-plan.md` + `skills/pipeline.md` (plan-close boundary). The registry row is worded as a wiring-PRESENCE guard — it can never claim a page was actually published; (b) superseded fragments are absent: the metrics-first DONE-review block header pattern in aid-run.md (grounded ~lines 352-360), the hardcoded "in **Czech**" requirement in BOTH `aid-verify-implementation.md` (:59, :149) and `aid-verify-plan.md` (:33, :122) — verified at CP1 as four identical lines across two files — and duplicate card-shape definitions outside communication.md (grep for the distinctive card line `Potřebuji tvoje rozhodnutí:` — exactly one file may define it).

**Architecture Context:** Handoff layer's contract file (Architecture §3). It is a reference card, NOT a style guide — target under 120 lines so dispatch injection stays cheap. Wiring is grep-enforced (Codex adoption №5), same style as P076's acceptance greps.

**Implementation Detail:** Frontmatter per skill convention (name/description/user_invocable). The card skeletons keep the source doc's Czech placeholder text as EXAMPLES with an explicit note "cards render in the PM's language; these examples are Czech because the requirements were" — the structure is what binds, not the language. Include the §14 rule "a path absent from the output-contract inventory cannot quietly emit a final technical dump" pointing at the index's `final_turn` column (Step 14 fills it).

**Error Handling:** The wiring test must not false-positive on fenced examples — reuse `fenced_stripped()`; the uniqueness assertion for card definitions counts unfenced occurrences only.

**Edge Cases:**
- `aid-audit-tests.md` already mandates its own renderer — it references communication.md for card vocabulary but its renderer mandate stays authoritative (no double definition; the test's uniqueness check excludes renderer-emitted text, which lives in the script not the doc).
- Progress card during long work — one-line status only; the skill states the P076 `awaiting_host_resume` card is a specialization owned by aid-run.md (no duplication here).

**Dependencies:**
- Depends on: none
- Blocks: Step 10 — artifact templates cite the card contract; Step 14 — the sweep rewires surfaces to this file.

**Acceptance Criteria:**
- [ ] `test-communication-wiring.sh` fails before Step 14 lands (surfaces not yet wired — demonstrated in verify output) and passes after.
- [ ] communication.md under 120 lines, contains all four card skeletons and the D16 table.
- [ ] `aid-lint-skill.sh skills/communication.md` reports zero findings (new file must lint clean).

**Effort:** M
**AID Role:** docs-writer

### Step 10: Deterministic artifact renderer and template family

**Objective:** A shared library that fills the ecosystem artifact skeleton deterministically (computed tiles, hard caps, truncation with counts) plus the AID artifact templates — the substrate Steps 11-12 render into.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-artifact-render.sh` — sourceable; `aid_artifact_render <template_id> <facts_json> <prose_json> <out_path>`: emits a self-contained styled HTML artifact page with the mandatory 7-block skeleton (Header; Tiles 2-4 computed values; Human summary; Core; Related links by NAME; "What I need from you" — ALWAYS present, "Nic — ozvu se, až bude hotovo" equivalent when empty; Detail link). Caps enforced in code: ≤5 result items, ≤3 next steps, ~220 chars/sentence soft-wrap, overflow truncated with an explicit "and N more in the technical detail" line. Tiles come ONLY from `facts_json` (computed by callers from canonical JSON); `prose_json` carries the bounded model-written blocks; a missing prose block renders the standard "summary missing — the numbers below are computed and valid" warning instead of failing.
- Create: `plugins/aid-orchestrator/defaults/templates/artifact-outcome.html` — the generic outcome template (used by gate/waiver and plan-close renderers), VISUALLY IDENTICAL to the shipped ecosystem report template: the HTML/CSS skeleton is vendored from `/opt/eco/services/agent-runtime/agent-report.py` (the standard's named template source — CSS custom properties with the three-state light/dark theme guards, masthead with eyebrow + serif title + timestamp, tile grid with `state-ok|state-warn|state-critical` left-border tiles, uppercase section labels, the split good/bad columns, the accent `ask` block for "Co se čeká ode mě", the `golink` detail button, provenance footer). AID changes only content slots, never the layout ("stejný layout pokaždé"). Block order, tile slots (result / duration / scope / unresolved) and placeholder grammar `{{fact:key}}` / `{{prose:key}}` documented in a header comment.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-artifact-render.bats` — golden fixture: full facts+prose renders all 7 blocks in order; empty prose renders the warning block; overflow list of 9 items renders 5 + "and 4 more"; block 6 present even when input says nothing is needed.

**Architecture Context:** Implements the ecosystem artifact standard (`/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md`) inside the plugin so consumer projects work standalone: 7-block mandatory skeleton, "brevity enforced by template not request", computed-not-claimed numbers, one-A4 target with detail linked, internal-audience rules. The publication channel (Claude Artifacts via the controller's Artifact tool) is deliberately outside this lib — it produces the BODY; the controller instruction (Steps 11-12) owns publication, mirroring the shipped audit renderer's Artifact-first banner precedent.

**Implementation Detail:** Pure bash+jq (no yq need — inputs are JSON). At implementation time, first READ `/opt/eco/services/agent-runtime/agent-report.py` and copy its rendered HTML skeleton verbatim into the template (fallback when that path is unreachable from the implementation host: reconstruct from the live artifact captured in the interim — the CSS variable set and section classes are recorded there); HTML-escape all substituted values. Template parsing: read the template file, substitute `{{fact:*}}` from facts_json (missing fact → literal `—`, never invented), `{{prose:*}}` from prose_json with per-block char caps (truncate at word boundary + ellipsis + overflow note). Sentence-cap enforcement: split prose blocks on `. ` and hard-truncate sentences over ~220 chars with `…`. The lib never reads run state itself — callers pass facts; this keeps it a pure function (testable with fixtures, reusable by the follow-up plan's renderers).

**Error Handling:** Invalid facts_json → exit 1 with the jq error (fail closed — an artifact with wrong numbers is worse than none); invalid/missing prose_json → render with the standard warning (per the ecosystem standard: a half-empty page must SAY the summary is missing). Unwritable out_path → exit 3.

**Edge Cases:**
- Facts containing `{{` literal — substitution is single-pass on template placeholders only, facts are inserted raw (no re-expansion).
- Tile value absent (e.g. no duration measured) — tile renders `—`, never a fabricated number.
- Related-links block with zero links — block omitted entirely (standard: optional block), order of remaining blocks unchanged.

**Dependencies:**
- Depends on: Step 9 — the template's chat-card cross-reference cites communication.md.
- Blocks: Steps 11, 12 — both render through this lib.

**Acceptance Criteria:**
- [ ] Golden bats fixtures pass; overflow, missing-prose and empty-block-6 cases each covered by a dedicated test.
- [ ] The rendered golden artifact contains all 7 blocks in the standard's order AND carries the vendored theme skeleton (grep asserts the three-state theme guards `data-theme="dark"` / `prefers-color-scheme` and the `state-ok`/`state-critical` tile classes).
- [ ] `grep -n 'Nic' <golden output>` proves block 6 renders even for the nothing-needed case (or its English equivalent per template language).

**Effort:** L
**AID Role:** backend

### Step 11: Gate/waiver outcome renderer

**Objective:** Deterministic chat card + artifact body for gate-run outcomes including waivers, rendered from the merged gate report — replacing free-form gate summaries at the run boundary.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-gate-outcome-summary.sh` — `aid_gate_outcome_render <gates_report_json> <run_dir> [waiver_dir]`: computes facts (gates passed/failed/skipped/profile-excluded/waived counts, total duration, failed gate names with exit codes, waiver facts as the waiver document actually carries them — do NOT assume `id`/`scope` fields exist; read the shipped shape at implementation time), calls `aid_artifact_render` with template `artifact-outcome`, writes `<run_dir>/gate-outcome-artifact.html`, prints the chat card (Finished or Blocked card shape per communication.md — Blocked when any required gate failed unwaived) to stdout with the final line `Artifact: <path>` for the controller to publish.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — GATES section: after the gate runner returns, the controller runs the renderer and presents its stdout VERBATIM as the gate-boundary message, publishing the artifact body via the Artifact tool first (audit-renderer precedent); applies in both manual and auto mode at the GATES→DONE (or fail) boundary.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — gates phase: same wiring, replacing the current free-form gate summary instruction.
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-gate-outcome-summary.bats` — fixtures: all-pass report → Finished card + artifact with correct tile counts; one failed required gate → Blocked card naming the gate and the smallest recovery action line; waived gate → waiver rendered as "PM risk acceptance", NEVER as a pass (the D3 rule, asserted by grep on the fixture output: the words rendered for a waiver must include `waived` and must not include `passed`).

**Architecture Context:** First consumer of the artifact layer. Input is the ordinary gate run's canonical artifact `<run_dir>/gates/gates_report.json`, produced by `scripts/aid-run-gates.sh` (:1629). Corrected at CP1: `lib/aid-run-gates-report.sh` exposes only `merge_escalation_report()` and produces a report ONLY on a targeted→full escalation, so it is not the canonical input — the renderer must additionally ACCEPT that escalation-shaped variant, but the ordinary report is the primary. The renderer re-derives nothing. A recommendation is never represented as fact and a waiver never as a passing gate — this is the regression rule §7/4-5 of the source doc, enforced by fixture assertions rather than prose.

**Implementation Detail:** Facts extraction with `jq 'to_entries'` over the report's `.gates` **object** (keyed by gate name — verified at CP1: it is a map, not a row array), whose `result` enum is `pass|fail|skip|profile_excluded`. **Card selection reads the envelope's `.overall`, never a per-gate verdict.** Verified at CP1: gate rows carry `{gate, result, reason, exit_code, duration_ms, output, attempts}` and have NO `required` key — required-ness lives in `execution.yaml` and survives only in `.overall`, which `aid-run-gates.sh` already computes correctly (a failing non-required gate leaves `overall=pass` at :2001/:2259, a waived required failure is treated as a pass at :2145, and `skip`/`profile_excluded` never affect it). So: `.overall == "fail"` → Blocked card; otherwise Finished card. Deriving the card from individual `result` values would tell the PM a run is blocked while the FSM advances — the exact mismatch this rule exists to prevent. Individual `skip` and `profile_excluded` rows are reported in the core table and never counted as failures. Waiver facts from the waiver receipts dir when passed (existing waiver verdict vocabulary per `aid-gate-waiver.sh`: valid/consumed/expired…). On the Blocked branch, the `Doporučené řešení` line is derived from what the gate row actually carries — corrected at CP1: gate definitions have only `description`/`required`/`command`/`timeout_seconds`/`pass_criteria`, there is **no** registered fix-loop/remediation field anywhere, so the line renders the gate's own `command` as the reproduction step plus the exact public force command from the P073 surface as the risk-acceptance line. Duration tile = sum of rows' duration_ms rendered human (m/s).

**Error Handling:** Missing/invalid merged report → exit 1 with a one-line error; the instruction wiring states the controller then falls back to the Blocked card written by hand FROM the raw gate output and must say the renderer failed (never silently skip the boundary message).

**Edge Cases:**
- Zero gates in profile (empty report) — Finished card with tile `gates: 0` and core note "profile ran no gates"; artifact still rendered.
- Retried gate (attempts >1) — attempts surfaced in the core table, not in tiles.
- Waiver present but expired/consumed — rendered in the failed section with its verdict word; never counted as waived-ok.

**Dependencies:**
- Depends on: Step 10 — renders through the artifact lib.
- Blocks: Step 14 — sweep verifies old free-form gate summary fragments are gone.

**Acceptance Criteria:**
- [ ] All three fixture classes pass; the waiver fixture proves waived ≠ passed by exact-string assertion.
- [ ] A fixture whose report contains one `skip` and one `profile_excluded` row selects the Finished card (neither is a failure).
- [ ] A fixture with a FAILING non-required gate but `overall: pass` selects the Finished card — proving the card follows `.overall` and not a per-row verdict.
- [ ] `grep -rn 'aid-gate-outcome-summary.sh' commands/aid-run.md skills/pipeline.md` shows both wiring points.
- [ ] Rendered artifact validates against the 7-block order (reuses Step 10's structural check helper).

**Effort:** M
**AID Role:** backend

### Step 12: Plan-close outcome renderer

**Objective:** Deterministic chat card + artifact body for the plan-final/close boundary, rendered from the canonical decision pair (`pm-decision-brief.json` + the `release-decision.json` it was generated from) — the PM's plan-level decision moment gets the card + one-screen artifact instead of raw file listings.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/lib/aid-plan-close-summary.sh` — `aid_plan_close_render <pm_decision_brief_json> <release_decision_json> <plan_id> <out_dir>`. The two inputs are explicitly split, because CP1 verified that the brief does NOT carry the SHA/tag/count facts: `build_brief_payload()` (`scripts/aid-pm-brief.sh:111-133`) emits exactly 14 keys, and the labelled facts reach only `pm-summary.md` (:257-260). **From the brief:** `release_ready`, `merge_mode`, `blockers`, `waivers_applied`, `evidence_verification_status`, `evidence_verified_at_head`, `summary_for_pm`, `delivered_summary_ref`. **From `release-decision.json` → `.release_decision.plan_summary`** (the exact shipped field set, read from its producer `scripts/aid-release-policy.sh:1114-1136` at CP1 — it is emitted in PLAN mode only): `reviewed_candidate_sha`, `approved_target_sha`, `target_ref`, `final_merge_sha` (null until the main merge is recorded), `release_tag_status`, the `epics[]` array (each with `epic_id`/`status`/`skipped`/`reason` — EPIC totals are COUNTED from this array, not read as a number), `plan_final_gates.{report,result}`, `specialist_review` and `remaining_backlog`. **There are no gate totals in this artifact** — only a single `plan_final_gates.result` verdict plus the path to the report; if the card wants per-gate counts it must read that report path, and the plan states which of the two it does. Tag vocabulary is `not_tagged` (the default until the release step runs) / `none` / `v<version>` — the value `tagged` does not exist and must not appear in the renderer or its fixtures. Decision-required card when `release_ready` is false or `merge_mode` is not an auto-merge value; Finished card when recording a completed close; artifact body `<out_dir>/plan-close-artifact.html`.
- Modify: `plugins/aid-orchestrator/commands/aid-plan.md` — plan-final/close section: controller renders and presents at the plan-final boundary; artifact published before the card, per the same precedent.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — plan boundary section, the pm-brief handoff (locate by the literal anchor `aid-pm-brief.sh`, NOT by line number: the previously cited ~2145-2174 region now holds unrelated content post-P076): the existing "canonical machine handoff" paragraph gains the renderer as the presentation layer; `aid-pm-brief.sh`, `pm-summary.md` and their plan-finalize guard are UNTOUCHED (hard mechanical reader, grounded).
- Create: `plugins/aid-orchestrator/scripts/tests/bats/test-aid-plan-close-summary.bats` — fixtures: not-release-ready brief → Decision card with recommendation line and the derived option set; completed close → Finished card; **fail-closed fixture** = brief missing one of the eight named brief fields, OR `release-decision.json` missing `.release_decision.plan_summary` → renderer exits 1 (mirrors plan-finalize's own labelled-fields check).

**Architecture Context:** Renders FROM the canonical chain the repo already trusts (`release-decision.json` → `aid-pm-brief.sh` → `pm-decision-brief.json`); this step adds only presentation. The cycle-break contract of aid-pm-brief is preserved: this renderer reads the brief plus the `release-decision.json` the brief was generated from, and NO sibling evidence.

**Implementation Detail:** jq extraction from the two declared inputs; the Decision card's `Proč teď` line = the reason implied by `release_ready`/`merge_mode`; `Riziko` = the brief's unresolved `blockers` list (cap 5 via the artifact lib). Tag status tile uses `release_tag_status` from `plan_summary` verbatim; the shipped vocabulary is `not_tagged` / `none` / `v<version>` (CP1 verified there is no `pending` and no `tagged` value, and no `options` field anywhere in the brief). Fixtures must be built from a real PLAN-mode `release-decision.json` shape — note that every one of the 13 such artifacts currently in the repo is EPIC-mode and therefore carries `plan_summary: null`, so the fixture is hand-authored from the producer's field set and the step says so. The option set is DERIVED from `merge_mode` + `release_ready`, not read from the brief, and each option renders its exact public command (merge / defer / abandon), satisfying §14's "the exact public --force command/decision" rule for the risk path.

**Error Handling:** Brief absent at the boundary → the instruction states the controller reports the Blocked card "plan-close brief missing — run aid-pm-brief.sh" rather than improvising a summary from evidence files (which would recreate the cycle aid-pm-brief exists to break).

**Edge Cases:**
- Legacy plan (no brief producer in that flow) — instruction wiring scopes the renderer to plan_branch closes; legacy per-EPIC release keeps its existing text (never retroactively re-shaped).
- Brief with zero unresolved blockers — Riziko line renders the standard "no material uncertainty" wording, not omitted (Decision card requires the field).

**Dependencies:**
- Depends on: Step 10 — artifact lib.
- Blocks: Step 14 — sweep checks the boundary wiring.

**Acceptance Criteria:**
- [ ] All three fixture classes pass; both fail-closed shapes (missing brief field / missing `plan_summary`) exit 1.
- [ ] `grep -rn 'aid-plan-close-summary.sh' commands/aid-plan.md skills/pipeline.md` shows both wiring points.
- [ ] The pending-decision fixture's card contains `Doporučení:` and at least one exact public command string.

**Effort:** M
**AID Role:** backend

### Step 13: Step-index seam — human rendering finished

**Objective:** Humans always read "Plan Step N"; machine fields and evidence filenames stay frozen. Collapse the SIX verbatim "Step rendering rule" copies (in five files) to one referenced section — and rewrite the shipped test that currently REQUIRES the full text in five files, because without that rewrite the collapse turns a green suite red.

**Files:**
- Modify: `plugins/aid-orchestrator/scripts/aid-fsm.sh` — extend `_fsm_human_step` output wording and append it at the remaining PUBLIC seams. Locate the helper by its literal name (all previously cited line anchors were wrong; at CP1 the comment is at :1128, the definition at :1132, and there are **three** existing call sites — :2858, :2870, :5246 — not four). Sweep the file for other `current_step` interpolations into operator-facing echo strings and append the helper there; machine-parsed stdout such as the `verify-state` JSON payload is explicitly untouched.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` (lines ~1322-2756) — this file holds TWO of the six copies: the ~1322 one stays as the ONE authoritative "Step rendering rule" section (its text updated to the new wording), the ~2756 one becomes a one-line reference to it.
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` (lines ~402) — verbatim copy becomes a one-line reference to pipeline.md's authoritative section.
- Modify: `plugins/aid-orchestrator/commands/aid-status.md` (lines ~984) — same reference replacement.
- Modify: `plugins/aid-orchestrator/commands/aid-stop.md` (lines ~119) — same reference replacement. This file was missing from the plan entirely; it is one of the six copies verified at CP1 (and already six at the plan's own grounding baseline d822957 — never P076 drift).
- Modify: `plugins/aid-orchestrator/skills/memory.md` (lines ~28) — same reference replacement; also missing from the plan until CP1.
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-fsm-step-render.bats` — **two rewrites, not just additions.** (a) The `@test "P073 Step 4: every enumerated prose surface renders executing_step and states the rule"` block (:103-116) currently loops the five surfaces and asserts each contains BOTH the phrase `Step rendering rule` AND the literal `executing_step = min(current_step + 1, total_steps)`; it is rewritten to assert "each of the five surfaces contains a REFERENCE to the one authoritative section" and "exactly one file states the full rule". (b) The four verbatim `(human: step N of T …)` assertions at :33/:41/:49/:76 are updated to the new wording. New cases then assert the wording at each newly covered seam and that the verify-state JSON payload still emits the bare 0-based integer (frozen surface regression).

**Architecture Context:** Finishes P073 Step 4's prior art. The helper appends AFTER machine values so existing greps keep matching (the helper's own documented contract); the six-copy collapse removes the drift risk that produced today's `{executing_step}` vs `Plan Step N` mismatch. The new wording MUST keep the disambiguator — `Plan Step N of T is next` / `all T steps complete`, never a bare `Plan Step N of T` — because the underlying field is 0-based and unreadable without it.

**Implementation Detail:** Sweep method: `grep -n 'current_step' scripts/aid-fsm.sh` — classify each interpolation site as machine (JSON/yq writes/greps) vs human echo; touch only human echoes. P076 CONFLICT NOTE: aid-fsm.sh and aid-status.md are P076 target files — this step lands after P076's merge and rebases its line anchors then; the P076 acceptance grep (absence of the permissions.yaml string in aid-run.md, P076:697) must remain satisfied by the aid-run.md edit here.

**Error Handling:** If a human/machine classification is uncertain for a site, leave it untouched and list it in the verify output — under-rendering is recoverable, breaking a machine grep is not (Codex adoption №6: fix the defined public seams, leave internal diagnostics alone).

**Edge Cases:**
- `current_step` equal to total (run complete) — helper's existing "step T of T complete" wording asserted at one new seam.
- Evidence filename construction sites (`step-N-verify.md`) — filename math untouched; one bats case pins `step-0-verify.md` naming for plan step 1.
- Czech/localized card text — the helper emits English; cards translate at presentation per communication.md (the helper's output is a technical suffix, exempt from the language rule).

**Dependencies:**
- Depends on: Step 9 — communication.md documents the "Plan Step N" convention the seams render.
- Blocks: Step 15 — golden card fixtures include the step wording.

**Acceptance Criteria:**
- [ ] Extended bats suite passes — including the two REWRITTEN blocks (the P073 five-surface assertion and the four verbatim wording assertions); the frozen-surface case proves verify-state JSON unchanged.
- [ ] `grep -rc 'Step rendering rule' plugins/aid-orchestrator/commands plugins/aid-orchestrator/skills` yields exactly one full definition plus five references.
- [ ] No evidence filename or fsm-state field changed (fixture diff in the suite).

**Effort:** M
**AID Role:** backend

### Step 14: Wire the communication contract across surfaces and fill output contracts

**Objective:** Every required surface references communication.md, superseded inline fragments are removed, the DONE-review template becomes a card, and the help index's `final_turn` column reflects reality — turning Step 9's test green.

**Files:**
- Modify: `plugins/aid-orchestrator/commands/aid-run.md` — locate both blocks BY LITERAL, not by line number (CP1 re-checked: the DONE-review block is near :440-443 and the ESCALATION template near :385, not the ~352-360/~294-315 the source doc cited). Anchor the first on `Auditor Score:` and the second on `ESCALATION — {trigger_reason}`. The DONE-review PM summary block is rewritten as a Finished card (outcome first, metrics moved to the artifact/detail line); the ESCALATION template is reframed as the Decision-required card (structure from communication.md, content unchanged); add the communication.md reference line.
- Modify: `plugins/aid-orchestrator/skills/pipeline.md` — the ESCALATION duplicate (locate by the literal `ESCALATION — {trigger_reason}`; the previously cited ~1176-1194 region now holds unrelated content post-P076) becomes a reference to aid-run.md's card + communication.md; PHASE-END summary instruction in `skills/run-management.md` (lines ~135-153) keeps its HARD STOP semantics but its summary items 3/4/7 are reshaped to the Finished/Decision card shapes.
- Modify: `plugins/aid-orchestrator/skills/run-management.md` — as above (PHASE-END card wording + reference).
- Modify: `plugins/aid-orchestrator/commands/aid-do.md` + `plugins/aid-orchestrator/commands/aid-plan.md` — Step 8 output (~163-191) and the PM-report lines (~71, ~97) respectively: final outputs reference the card shapes; escalation-is-advisory wording preserved.
- Modify: `plugins/aid-orchestrator/commands/aid-verify-implementation.md` (lines ~59, ~149) — "in **Czech**" → "in the PM's language (skills/communication.md)".
- Modify: `plugins/aid-orchestrator/commands/aid-verify-plan.md` (lines ~33, ~122) — the SAME two hardcoded-Czech lines, verified at CP1 as identical text in a second file the plan had missed; same replacement.
- Modify: `plugins/aid-orchestrator/commands/aid-audit-tests.md` — add the communication.md reference line, and correct the single part-count outlier: the shipped contract is **four-part** (:50, :285, :331) and :202's "5-part" is the one wrong word. ("6-part" appears nowhere in the file — the plan's earlier claim was wrong in both directions.) The renderer itself is untouched.
- Modify: `plugins/aid-orchestrator/agents/reporter.md` + `plugins/aid-orchestrator/agents/simplifier.md` — their human-summary instructions cite communication.md for card vocabulary (reporter's `document_language` rule for DOCUMENTS stays).
- Modify: `plugins/aid-orchestrator/defaults/help-index.yaml` — fill `final_turn` for every row from the now-real wiring (audit → its renderer; run → gate renderer at GATES boundary + cards; plan → plan-close renderer; others → card types; internal rows → `internal`).
- Modify: `plugins/aid-orchestrator/scripts/tests/bats/test-help-index-coverage.bats` — add the output-contract assertions: every `final_turn: renderer:*` value names an existing script; every public row has a non-empty `final_turn` (the §14 D17 inventory rule, enforced in the existing test rather than a new harness).

**Architecture Context:** The convergence step: Step 9 defined the contract, Steps 11-12 built the renderers, this step makes every surface point one way and makes the index's `final_turn` column the tested output-contract inventory (Codex adoption: inventory-as-test, no new runtime).

**Implementation Detail:** Each edit is a bounded region replace anchored on grounded line ranges (rebased post-P076 — aid-run.md and pipeline.md are P076 targets). The DONE-review card keeps every fact the old block carried (steps, gates, duration, auditor score) but moves them to the technical-detail line/artifact; the first line becomes the outcome sentence. Sweep for orphaned fragments after edits: `grep -rn 'DONE REVIEW —' commands/ skills/` must match only the card version.

**Error Handling:** If a grounded line range has drifted beyond recognition post-P076, locate by the block's distinctive literal (e.g. `Auditor Score:`) instead of line numbers; if the literal is gone entirely (P076 removed it), record `verified_current: superseded-by-P076` in the verify output and skip that edit — never re-introduce removed text.

**Edge Cases:**
- P076's `awaiting_host_resume` card in aid-run.md — left byte-identical; it is already card-shaped and owned by P076.
- `aid-audit-tests.md` — reference added but its FOUR-part renderer mandate unchanged; only the :202 "5-part" outlier is corrected (one word).
- Surfaces in the sweep that P076 deleted — handled per Error Handling.

**Dependencies:**
- Depends on: Step 1, Step 2, Step 9, Step 11, Step 12, Step 13 — all six numbers listed before the em dash so `parse_step_deps` actually records them. Steps 9/11/12/13 build what this step wires; Steps 1/2 create `defaults/help-index.yaml` and `test-help-index-coverage.bats`, which this step modifies.
- Blocks: Step 15 — fixtures snapshot the final wording.

**Acceptance Criteria:**
- [ ] `test-communication-wiring.sh` passes (all references present, superseded fragments absent).
- [ ] `test-help-index-coverage.bats` passes with the new final_turn assertions.
- [ ] `grep -rn 'Czech' plugins/aid-orchestrator/commands/aid-verify-plan.md plugins/aid-orchestrator/commands/aid-verify-implementation.md` returns nothing. The grep is deliberately on the bare word across BOTH files: the mandate ships in **two different literal forms** — `in **Czech**` (aid-verify-plan.md:33, aid-verify-implementation.md:59) and `**in Czech**` (aid-verify-plan.md:122, aid-verify-implementation.md:149) — so any asterisk-bearing pattern silently passes with half the mandate still in place. Scoped to the two verify files because `commands/aid-audit-tests.md:54` mentions "a Czech user" as legitimate prose that must NOT be removed.
- [ ] `grep -c '5-part' commands/aid-audit-tests.md` returns 0.

**Effort:** L
**AID Role:** docs-writer

### Step 15: Golden fixtures and whole-suite regression

**Objective:** Golden fixtures prove the five §14 delivery cases render correctly end-to-end, and the full targeted test set passes together.

**Files:**
- Create: `plugins/aid-orchestrator/scripts/tests/test-integration-handoff-rendering.sh` — drives the three renderers (audit renderer untouched — smoke only; gate outcome; plan close) over fixture JSON for the five cases: finished, decision-required, blocked, force-used (waiver present), incomplete (missing prose → warning block); asserts card-first ordering (first non-empty line is the outcome/decision sentence, no JSON/paths before it) and artifact 7-block structure; asserts a raw technical list cannot be the only output (fixture where facts exist but prose missing still yields a card + warning).
- Test: `plugins/aid-orchestrator/scripts/tests/bats/test-help-index-coverage.bats` + `test-aid-config-summary.bats` + `test-init-idempotency.sh` + `test-communication-wiring.sh` + `test-enforcement-registry-cites.sh` + `test-fsm-step-render.bats` + `test-aid-artifact-render.bats` + `test-aid-gate-outcome-summary.bats` + `test-aid-plan-close-summary.bats` — full pass documented in the harness header. **Not** a "scoped `run-all-tests.sh` invocation": verified at CP1 that `scripts/tests/run-all-tests.sh` accepts only `--verbose/-v/--list/--help` and exits on an unknown argument (:132), so there is no scoping flag. Use either explicit per-suite `bats`/`bash` invocations for the nine suites, or one full `run-all-tests.sh --verbose` run — state which, and record the command in the verify output.

**Architecture Context:** §14 delivery item 1-2 (golden fixtures for the card cases; renderer contract test: structure and factual source, not prose aesthetics) and source doc §7 regression rule 6 (no full-suite ceremony per docs slice — one proportionate final check).

**Implementation Detail:** Fixtures are checked-in JSON under `scripts/tests/fixtures/handoff/` (small, hand-authored, commented provenance). Language assertion: fixture prose in Czech renders unmodified (renderers never translate — the model wrote the prose in the PM's language upstream); a structural grep asserts card labels, not Czech literals, so other locales pass.

**Error Handling:** Any renderer nonzero exit inside the harness prints the failing fixture name and the renderer stderr verbatim — the harness never swallows a child's diagnostics.

**Edge Cases:**
- Fixture drift after a renderer wording change — goldens assert structure (headings order, label presence, first-line class) not full byte-equality, so benign wording edits don't churn fixtures; byte-golden only for the artifact block ORDER check.
- CI without the Artifact tool — renderers only write files/stdout; publication is controller instruction, so the harness runs anywhere.

**Dependencies:**
- Depends on: Step 14 — snapshots final wiring.
- Blocks: Step 16 — release rides on the green set.

**Acceptance Criteria:**
- [ ] Integration harness passes all five cases; the blocked case's first line starts with the Blocked card label.
- [ ] The listed suites all pass, by the invocation form this step declares (log excerpt in verify output).
- [ ] No fixture contains a real secret/token pattern (grep sweep in the harness — artifact standard's hard rule).

**Effort:** M
**AID Role:** qa

### Step 16: Documentation, registry, Docusaurus spec and release

**Objective:** Contributor docs and the ecosystem docs describe the new layers, every new mechanical check is registered, and the release ships per repository policy.

**Files:**
- Modify: `docs/extending-aid.md` — new section "Entry-point UX layer (P080)": the help index contract + coverage test, the init/setup ownership table (the HUMAN table — one row per config file: owner, carve-out cite, test), the communication contract + renderer family + artifact layer (template placeholder grammar, caps, how to add a new renderer), each subsection ending with its "Adding to this area" note per the file's convention.
- Modify: `plugins/aid-orchestrator/defaults/enforcement-registry.yaml` — new rows: `help_index_coverage` (if not landed in Step 4), `registry_cite_validation`, `init_workspace_idempotency`, `communication_reference_wiring`, `handoff_renderer_contract`, `artifact_template_caps`, `artifact_publication_wiring` (Step 9's publish-before-present assertion — worded as a wiring-PRESENCE guard, never as a claim that a page was published), `version_registry_sync` (wiring the existing but uncalled `verify-version-files.sh` into the release ceremony), plus `config_summary_read_only` (Step 7's read-only contract) and `step_seam_human_rendering` (Step 13's regression) — each with type/source/instruction/severity/surface/test per the registry schema; totals recomputed. Row `id` uniqueness is asserted by Step 4's test, so an append on a re-run cannot silently duplicate a row.
- Create: `/opt/eco/docs/docs/aid/specs/artifact-templates.md` — CROSS-REPO deliverable (the docs repo, not this repo): the AID artifact-template spec page deriving from the ecosystem standard — template family list (artifact-outcome now; audit alignment noted as existing), the 7-block mapping to AID facts, caps table, computed-vs-model table, and the note that the publication channel is temporary per the ecosystem standard.
- Modify: `/opt/eco/docs/sidebars.ts` — CROSS-REPO: register the new page id in the AID section. Verified at CP1: that site's sidebar is 100% explicit (`grep -c autogenerated sidebars.ts` → 0), so a `_category_.json` is inert there and an unregistered page never appears; `onBrokenLinks`/`onBrokenAnchors` are both `throw`, so a half-registered page breaks the build.
- Create: `plugins/aid-orchestrator/defaults/templates/artifact-templates-spec.md` — the in-repo fallback copy of the spec page, used only if the cross-repo write is refused at run time. Deliberately NOT under any `docs/` directory: verified at CP1 that `.gitignore:87` is a bare `docs/`, which matches at ANY depth, so the previously planned `plugins/aid-orchestrator/docs/…` fallback would have been an untracked file satisfying its own AC while nobody else ever sees it.

**Commit authority for the two cross-repo files:** `/opt/eco/docs` is a SEPARATE git repository (`git -C /opt/eco/docs rev-parse --show-toplevel` → itself), so this plan's plan_branch ceremony cannot commit them and `test -w` proves permission, not authority. The two files are written here and committed by the PM in the docs repo as a separate commit outside this plan; the step records the exact commit command and the resulting SHA in its verify output. If the PM has not committed at plan-close, the step reports the deliverable as PM-pending — never as done.
- Modify: `CHANGELOG.md` + `plugins/aid-orchestrator/CHANGELOG.md` — identical entry per the repo format (Added: help index + coverage; init/setup ownership + config summary + idempotency test; communication contract + renderers + artifact layer; Fixed: help false claims, permissions template mismatch, registry dangles; Changed: DONE-review/ESCALATION card shapes, step rendering).
- Modify: `.claude-plugin/marketplace.json` + `plugins/aid-orchestrator/.claude-plugin/plugin.json` + `plugins/aid-orchestrator/README.md` + `README.md` — version bump per the 8-location registry (CHANGELOG headers are locations 1-2; README roadmap updated, license line untouched).

**Architecture Context:** MUST rule 16 (docs step last before E2E/none) + the repo's release workflow. The Docusaurus page is the PM-required ecosystem deliverable; its fallback path keeps the plan executable when generation-time scoping cannot authorize a second repo.

**Implementation Detail:** extending-aid.md placement: after the P074 section (the file is chronological by plan). The ownership human table cites carve-out locations by file + section name (not line numbers — they drift). Registry rows follow the block style for prose-heavy entries (grounded precedent at rows ~1456+). Release: `release: vX.Y.Z — the front door tells the truth` commit + tag + GitHub release + plugin cache refresh per CLAUDE.md workflow; version chosen at implementation time from the then-current head (minor bump — new capability, no breaking change).

**Error Handling:** The cross-repo write is attempted only after `test -w /opt/eco/docs/docs/aid` confirms access; on failure the fallback path activates and the verify output records it. Version-registry drift (another plan released between generation and this step) → re-read the current version and bump from it; never hardcode the number in the plan. **The release sub-step is idempotent by declaration:** if the version files already sit at the target version, the bump is a no-op rather than a second increment — a fix-loop re-dispatch of this step must not double-bump (the class P079 carried as a residual). The shipped `release_changelog_paths` guard (registry ~:257, `test-aid-release.bats`) applies whenever `scripts/aid-release.sh` is used; state explicitly which of the 8 locations the script handles and which stay manual.

**Edge Cases:**
- `docs/aid/specs/` directory absent in the docs repo (verified absent at CP1) — create it, and register the page in `sidebars.ts`; do NOT rely on `_category_.json`, which is inert on a fully explicit sidebar.
- Parallelism-removal landed between planning and this step and renamed audit surfaces cited in extending-aid.md — the section cites the audit renderer only as "existing alignment", updated to the then-current name during implementation.
- P076's Step 14 appended IMP rows that renumbered around IMP-473/474 — CHANGELOG references IMPs by topic, not number, to stay merge-safe.

**Dependencies:**
- Depends on: Step 4, Step 8, Step 15 — registers and documents what they proved.
- Blocks: none — terminal step.

**Acceptance Criteria:**
- [ ] All 8 version locations agree, proven by RUNNING `bash plugins/aid-orchestrator/scripts/tests/verify-version-files.sh` (exit 0) — not by a manual grep. That script already exists (P079) but CP1 confirmed it has no mechanical caller anywhere: it misses `run-all-tests.sh`'s `test-*.sh` glob, `aid-release.sh` never calls it, and `.github/workflows/version-sync.yml` has the plugin check commented out at ~:21 with the note "Plugin has independent versioning". This step makes its invocation an explicit release-ceremony command and registers it as `version_registry_sync` in the enforcement registry with severity and surface stated honestly (invocation-time, release-boundary — NOT a CI gate). Deliberate decision recorded here rather than left implicit: the check stays release-boundary rather than being renamed into the suite glob, because the 8 locations legitimately diverge mid-development and a suite-wide run would fail every non-release commit.
- [ ] Both CHANGELOGs byte-identical for the new entry.
- [ ] Primary path: `git -C /opt/eco/docs ls-files docs/aid/specs/artifact-templates.md` returns the file AND `sidebars.ts` references its id (mere existence is NOT acceptance — an untracked or unregistered page reaches nobody). If the PM commit is still pending, the step reports PM-pending with the exact command handed over.
- [ ] Fallback path (if used): `git ls-files <chosen path>` returns the file.
- [ ] Either way the page contains the 7-block mapping table.
- [ ] Registry totals match the recompute command's output; `yq '.enforcements[].id' | sort | uniq -d` is empty.

**Effort:** L
**AID Role:** release

## Testing Strategy

- **Unit/bats:** every new script ships its `tests/bats/test-<name>.bats` (artifact render, gate outcome, plan close, config summary) — auto-discovered, no registration.
- **Flat harnesses:** registry cites, communication wiring, init idempotency, handoff integration — `scripts/tests/test-*.sh`, auto-discovered.
- **Coverage-as-regression:** `test-help-index-coverage.bats` is the standing guard for the whole inventory layer; extended (not duplicated) when columns gain assertions in Step 14.
- **Fixtures:** checked-in under `scripts/tests/fixtures/handoff/`; goldens assert structure not bytes (except block order) to avoid churn.
- **Frozen-surface regression:** `test-fsm-step-render.bats` proves machine outputs unchanged.
- **Proportionality:** per source doc §7 rule 6 — targeted suites per step; one combined pass at Step 15; no repo-wide ceremony per docs edit.

## Constraints

- **Sequencing (hard):** implementation starts only after P076 merges to main (shared target files: aid-run.md, pipeline.md, aid-status.md, aid-fsm.sh, aid-help.md region). Steps 3, 13, 14 explicitly rebase their line anchors on the merged text and must keep P076's acceptance grep (absence of the `config/permissions.yaml` decision string in aid-run.md) satisfied.
- **Sequencing (soft):** the parallelism-removal work (separate session) rewrites audit instruction surfaces; Step 3's `tests` topic and Step 16's docs cite the then-current audit surface at implementation time. EPIC 1-3 content does not otherwise depend on it (the evidence/visual follow-up plan does — out of scope here).
- Frozen compatibility surfaces: `current_step` semantics, `verify-state` JSON, evidence filenames, fsm-state.yaml fields — read-only for this plan.
- `pm-summary.md`/`aid-pm-brief.sh`/plan-finalize guard untouched (hard mechanical reader).
- Plugin code/docs in English; card EXAMPLES may be Czech per source doc; conversation-language rule lives in communication.md.
- No new runtime dependency: bash, jq, yq, awk only — all already required repo-wide.
- Language split: this plan document in English (document_language default), PM conversation in Czech.

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| P076 merge reshapes grounded line anchors | High | Medium | Steps 3/13/14 anchor by distinctive literals with explicit drift protocol; implementation rebases before EXECUTE |
| Help rewrite reintroduces drift later | Medium | Medium | Coverage test is the standing enforcement; disposition semantics make "intentionally missing" explicit |
| Renderer wording churn breaks goldens | Medium | Low | Goldens assert structure/labels, not bytes |
| Cross-repo Docusaurus write refused by scoping | Medium | Low | Explicit in-repo fallback path + PM move note, defined in Step 16 |
| Card reshaping of PHASE-END weakens the HARD STOP | Low | High | Step 14 keeps the stop semantics verbatim; only summary SHAPE changes; wiring test asserts the stop lines survive |
| Artifact caps truncate something the PM needed | Low | Medium | Truncation always states the overflow count + detail link; caps mirror the ecosystem standard's PM-authored values |

## Success Criteria

1. A newly added `user_invocable: true` command fails CI until intentionally indexed and routed (or classified internal).
2. `commands/aid-help.md` routes all 13 surfaces; no advertised topic without a section; no stale lifecycle claim (spot-checks in Step 3 ACs).
3. Every init/setup-written config file has exactly one declared owner, protected by the idempotency harness.
4. Every public surface's final turn is inventoried (`final_turn` column) and the three deterministic renderers ship with verbatim-presentation wiring and passing goldens; a waiver is never rendered as a pass.
5. Humans read `Plan Step N` at the public seams; machine surfaces byte-unchanged.
6. Release shipped with all 8 version locations synchronized and the AID artifact spec page published (primary or fallback path).

## Acceptance Criteria

- [ ] AC1 — Coverage bijection holds on the shipped tree.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-help-index-coverage.bats"
  expected_exit: 0
```
- [ ] AC2 — Registry cites are valid on the shipped tree.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-enforcement-registry-cites.sh"
  expected_exit: 0
```
- [ ] AC3 — The false init merge claim is gone.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! grep -n \"Merges the old\" plugins/aid-orchestrator/commands/aid-init.md'"
  expected_exit: 0
```
- [ ] AC4 — Init idempotency harness passes.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-init-idempotency.sh"
  expected_exit: 0
```
- [ ] AC5 — Communication wiring complete, superseded fragments gone.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-communication-wiring.sh"
  expected_exit: 0
```
- [ ] AC6 — Handoff rendering integration passes all five golden cases.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash plugins/aid-orchestrator/scripts/tests/test-integration-handoff-rendering.sh"
  expected_exit: 0
```
- [ ] AC7 — The hardcoded Czech mandate is relaxed.
```yaml
verification_pattern:
  type: cmd
  cmd: "bash -c '! grep -rn Czech plugins/aid-orchestrator/commands/aid-verify-plan.md plugins/aid-orchestrator/commands/aid-verify-implementation.md'"
  expected_exit: 0
```
- [ ] AC8 — Artifact renderer enforces block 6 and truncation.
```yaml
verification_pattern:
  type: cmd
  cmd: "bats plugins/aid-orchestrator/scripts/tests/bats/test-aid-artifact-render.bats"
  expected_exit: 0
```

## Next Steps

1. `aid-plan-lint.sh` + `aid-generation-readiness.sh --total 3` on this document; repair diagnostics.
2. CP1-deep (8 lenses + adjudicator) + C0 Codex loop per current pipeline; budget 5 attempts then PM force per standing policy.
3. Generate EPICs (3) after P076 merges; queue chain; implementation in a per-plan worktree.
4. Follow-up plan (evidence registry D18 + visual D19-D21) brainstormed after the parallelism removal lands — design notes already in `.aid-o/work/interim-P080.md`.
