# Interim P080 — entry-point UX: help, init/setup, human-first handoffs, visual proof (category 4)

**Status:** brainstorm in progress (2026-08-09). Grounding dispatched (2 Explore
agents); Codex opponent pending; PM approval pending.

## Source

- `docs/plans/2026-08-02-IMP-AID-ENTRYPOINT-UX-HELP-INIT-SETUP-HANDOFFS.md`
  §1–9 (original core: D1–D5, Slices 1–5), §14 (D16–D18 chat decision cards +
  evidence minimisation), §15 (D19–D21 proportionate visual proof).
- PM GO 2026-08-09 ("vrhni se na blok č 4" — interpreted as category 4;
  stated interpretation in chat, PM did not correct).

## PM binding constraints (inherited)

- Loosen, don't add ceremony (§2 explicitly: "no generic prose gate, no
  automatic audit after every EPIC").
- Everything wired (AID-v3 §1); instruction surfaces consistent (no kočkopes);
  no rocket science; bulletproof via external opponent.

## Known sequencing constraints (2026-08-09 live state)

- P076 implementation running in PM's window — rewrites aid-run.md /
  run-management.md / pipeline.md surfaces that §14 also touches. P080
  implementation must start AFTER P076 merges.
- Parallelism-removal plan being written in another session (PM decision
  2026-08-09, see interim-P077.md) — will rewrite audit instruction surfaces
  (aid-audit-tests.md, test-portfolio-analyst.md, README test sections) that
  the §5 Slice-1/5 inventory + sweep must describe. Sequence P080
  implementation after that removal lands, or the inventory describes a
  surface that is about to disappear.
- §9's original sequencing ("after P066 contract, P069 must finish or freeze")
  is now partly moot: P069 line cancelled entirely; §5 Slice 4 item 19's
  "consume the P066 decision-quality contract" needs re-grounding against
  what survives the parallelism removal.

## Groundings (condensed; full F1–F16 with file:line in session scratchpad
p078-design-draft.md; agents' raw H*/R* facts in session transcript)

Highest-signal contradictions found live:
- aid-help.md: advertises 8 topics, only 7 sections exist (Topic: status
  absent); never mentions /aid-audit-tests, /aid-verify-plan,
  /aid-verify-implementation, /visual-companion; Level 0 sends a fresh user
  to /aid-setup which itself refuses without /aid-init; stale "execution.yaml
  lazy-created" claim (eager since P032); says "Level 0 = 3 commands" while
  listing 4; silent on the release model.
- init/setup: "10-file" vs "11 total" vs README "10-file"; aid-init.md:7
  claims it merged setup while :677 routes users to setup; init's
  permissions.yaml template lacks the active_preset key setup reads; preset
  vocabulary 3-way inconsistent; content after the Last Updated footer;
  double ownership without carve-outs for permissions/project/integrations/
  CLAUDE.md (only gate_profiles is adjudicated).
- NO mechanical help-coverage test, NO setup behavior test, NO workspace-level
  init idempotency test; all 4 target files lint-grandfathered.
- Registry: 3 rows cite nonexistent commands/aid-research.md; init_idempotency
  cite stale.
- Handoffs: exactly ONE deterministic chat renderer exists (audit); pm-summary
  has a HARD mechanical reader (plan-finalize fails without it) — §14
  consolidation must be surgical; one E-065 run holds 20+ verifier-output
  rerun narratives (the proven "pile"); output_contract and shared
  communication reference: 0 hits; language rules scattered (one command
  hardcodes Czech).
- Step seam: P073 prior art _fsm_human_step used at only 3 call sites; a
  "Step rendering rule" paragraph copy-pasted verbatim in 4 files.
- Visual: three contradictory rules (any-UI-step vs conditional vs
  visual_refs-only); capture/compare scripts exist but explicitly unwired;
  visual-companion does unconstrained npm install; no runner/cache-key/
  equivalence receipts anywhere.
- IMP-261 C0/C3 claim verified true (model_reasoning_effort=high hardcoded in
  shared transport, aid-c3-dispatch.sh:1113).
- P076 collision map: rewrites aid-run.md/pipeline.md/role-cards.md
  (~210-245 = same region as the conditional-Playwright rule)/aid-status.md,
  and targets an aid-help "auto-mode topic region" that DOES NOT EXIST yet;
  P076 has not yet touched any command/skill file on disk. P076 does NOT
  touch aid-init/aid-setup/run-management.

## Design draft

Full draft: scratchpad p078-design-draft.md (D1–D15, Q1–Q5). Shape: one plan,
4 EPICs, risk high; implementation gated on P076 merge + parallelism-removal
landing. EPIC 1 = help index + coverage test + help rewrite; EPIC 2 =
init/setup ownership table + contradiction fixes + shared read-only
config-summary renderer + idempotency test; EPIC 3 = communication reference
skill + 4 decision cards + output_contract inventory + 2 deterministic
renderers (gate/waiver, plan-close from pm-decision-brief.json) + step-seam
finish; EPIC 4 = evidence-write registry (read-only + one proven retention
rule) + visual rule unification (D19) + npm-ci reuse (D20-lite; D21 receipts
deferred as IMP) + sweep/release. Exclusions: no init/setup merge, no
settings schema (IMP-261 impl = next plan), no container visual runner, no
deletion of artifacts with live readers.

## Codex reconciliation (1 round sufficed, 2026-08-09; artifact
codex-p078-round1.md in session scratchpad — near-total adoption, no
contested design point left except the PM split decision)

Adopted:
1. Disposition semantics defined precisely: `current|update` ⇒ help route
   required; `index_only` ⇒ indexed, no topic route; `intentionally_internal`
   ⇒ no route, coverage test asserts absence from help.
2. `defaults/help-index.yaml` stays checked-in ONLY — no .aid-o copy (no
   second source of truth, no init idempotency complication).
3. ONE inventory file: ownership + output_contract columns fold into
   help-index.yaml; the human table is a short doc referencing it (kills the
   three-table "doc family").
4. D10 renderers get full wiring in the plan: controller call sites, output
   destination, fail-closed behavior, verbatim-presentation test (audit
   renderer precedent); merged-gate input verified end-to-end first.
5. D8 communication reference gets mechanical enforcement: a targeted lint
   asserting required surfaces reference it AND superseded inline fragments
   are gone (grep-based, same style as P076's acceptance greps).
6. D11 step-seam scope narrowed to the defined public human-facing seams
   (status/run/pipeline/FSM error paths); internal diagnostics untouched.
7. D15 adds a registry-cite validation test (source/instruction paths must
   exist — kills aid-research dangles class-wide, not just the 3 known rows).
8. Q5/P076 help collision: WAIT — P076 lands its auto paragraph first, P080
   rebases and folds the rewrite around landed text (already implied by the
   sequencing gate; now explicit).
9. D12 (evidence) pruning only after a verified reader search; D13 visual
   classifier becomes a machine-readable policy beside the enforcement code,
   referenced (not defined) in role-cards; D14 npm-ci rule needs a named
   owner script — all three land in the SECOND plan if the PM approves the
   split (below).

Overridden (factual): Codex objected to yq as a new dependency for the
config-summary renderer — yq (mikefarah) is already a hard dependency of the
shipped scheduler/lane/provenance stack; no new dependency is introduced.

PM DECISION №1 — plan shape:
- R1 (Codex, doporučení): SPLIT. P080 = EPICs 1–3 (help index + coverage,
  init/setup ownership, handoff cards/renderers/step seam). Evidence registry
  + visual reconciliation (old EPIC 4) = separate small follow-up plan.
  Argument: 4 EPICs cross too many independently risky instruction systems;
  the evidence/visual EPIC's prerequisites (P076 merge + parallelism removal)
  gate the whole plan otherwise.
- R2: keep ONE plan × 4 EPICs (one ceremony, one release; EPIC 4 simply runs
  last behind the same preconditions).

PM DECISION №2 (unchanged from draft): IMP-261 settings-schema implementation
stays OUT (separate future plan); this plan discharges only its analysis
portion. Confirm.

## PM approval (2026-08-09)

- **Decision №1 = A (SPLIT).** P080 = EPICs 1–3 (help index/coverage,
  init/setup ownership, handoff cards/renderers/step seam). Evidence registry
  + visual reconciliation = separate follow-up plan after the parallelism
  removal lands.
- **Decision №2 confirmed implicitly** (no objection): IMP-261 settings-schema
  implementation stays out; only its analysis portion is discharged here.
- **PM binding addition — Artifact outputs (EPIC 3):** final outcomes must
  also ship as an Artifact page, not only a chat card: visually summarized
  what happened + link to the full log/evidence. AID must derive its OWN
  artifact template spec (possibly several templates) from the ecosystem
  standards, and publish it in Docusaurus:
  - ecosystem standard: `docs.aidlab.dev/ecosystem/specs/artifact-standard`
    (source `/opt/eco/docs/docs/ecosystem/specs/artifact-standard.md`) —
    7-block mandatory skeleton (Hlavička / Dlaždice / Shrnutí / Jádro /
    Odkazy / Co se čeká ode mě / Odkaz na detail), "stručnost vynucuje
    šablona, ne prosba" (hard caps, template truncates + counts overflow),
    computed-not-claimed numbers, one-A4 + separate detail page, both color
    schemes, self-contained, internal-only for now, publication channel
    (Claude Artifacts) is temporary — skeleton survives a future self-hosted
    server.
  - agent-report example spec: `/opt/eco/docs/docs/ecosystem/ai-agents/report-spec.md`.
  - Design consequence for EPIC 3 (D16 added): the deterministic renderers
    emit BOTH the short chat card AND the artifact body (deterministic
    template fill: computed tiles/caps in the script, model writes only
    bounded prose blocks); chat card ends with the artifact link; audit
    renderer's existing Artifact-first mandate (R7) is the prior art and gets
    aligned to the same template family. Templates live IN the plugin
    (defaults/templates/artifact-*.md) so consumer projects work standalone;
    the Docusaurus spec page for the AID template family is a cross-repo
    deliverable (/opt/eco/docs) — carried as an explicit final step with a
    cross-repo note, or PM hand-off if generation rejects the out-of-repo
    path.
- **PM-forwarded live feedback from the P076 run — registered:** IMP-473
  (review findings need a mechanical route to a step allowed to fix them —
  the CP2→step-5-can't-touch-the-file incident), IMP-474 (prefilter seeds
  verifier-output inconsistently), IMP-472 extended (docs show uppercase
  `## Result: PASS` while the parser wants lowercase — sweep doc examples
  too). The 0-based evidence-filename trap is NOT a new IMP: filenames stay a
  frozen compatibility surface; the human-facing rendering fix is exactly
  P080 EPIC 3's step-seam item.

## Artifact visual reference (captured 2026-08-09 from live artifact 93449673, PM-shown)

The production template (source `/opt/eco/services/agent-runtime/agent-report.py`)
renders a self-contained styled HTML page — AID's Step 10 template MUST vendor
this skeleton, changing content slots only:
- CSS custom properties, three-state theme: bare `:root` light palette;
  `@media (prefers-color-scheme: dark)` guarded `:root:not([data-theme="light"])`;
  explicit `:root[data-theme="dark"]` block. Palette keys: ground/surface/sunken,
  ink/ink-soft/muted/line, accent/accent-soft, ok/warn/critical (+warn-bg,
  critical-bg).
- Structure: `.wrap` column (max 46rem) → `.masthead` (uppercase `.eyebrow`
  "Report agenta", serif `h1`, `.when` timestamp) → `.tiles` grid (`.tile` with
  `.k` uppercase label + `.v` value; `state-ok|state-warn|state-critical` = 4px
  colored left border + colored value) → `section.block` with uppercase `h2`
  labels (Zadání / Co se dělo / Jak to šlo with `.split` two-column `.good`
  (ok markers) vs `.bad` (critical markers) / Výsledek (≤5 bullets, overflow
  ellipsis) / Jak pokračovat `ol.steps` / Čeho se to týká links) →
  `section.block.ask` (accent background + left border, "Co potřebuju od tebe")
  → `.golink` button "Technický detail →" (separate artifact URL) → `footer`
  provenance line ("Napsal X, zkontroloval Y, schválil Z. Úkol `id`.").
- `.alarm` class (critical-bg) exists for the red warning blocks (no-contract /
  missing-summary cases).
- Detail is a SECOND artifact page (`.wrap.detail`, `.doc` card with full
  markdown-ish styling incl. `.tablewrap` horizontal scroll) linked from golink.

Next: /aid-plan write (load skill + instructions first), then CP1-deep +
generation per current pipeline; implementation gated on P076 merge (EPIC 3
also rebases the help auto-topic on P076's landed paragraph).
