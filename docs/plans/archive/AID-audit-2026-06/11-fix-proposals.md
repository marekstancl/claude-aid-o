---
audit: P041
artifact: fix-proposals (per-batch, externally verifiable)
status: proposed (awaiting PM + independent verification before apply)
generated: 2026-06-01
note: each proposal is self-contained — a third party can verify it against the cited files without other context
---

# P041 — Fix Proposals

Each proposal states: the problem, the **evidence** (exact file:line + current text),
the **proposed change** (exact before → after), **why**, and **how to verify** (what an
independent agent should check). Nothing is applied until PM + independent verification
approve.

**Apply note:** all files below are plugin-distribution files (`plugins/aid-orchestrator/`).
Per CLAUDE.md, applying them is a code change that bundles with a CHANGELOG entry +
version bump — so we apply a whole approved batch as one release, not per-fix.

---

## BATCH 1.1 — Wave 1, functional bugs with an unambiguous fix (B1, B4, B5)

### Proposal B1 — `/aid-help` level detection greps a file that never exists

**Problem.** `/aid-help` decides the user's experience level by counting completed
tasks. It greps for `state: DONE` inside `state.yaml`, but the FSM writes that field
into `fsm-state.yaml` (the file `state.yaml`, when present, is a different
progress-array file with no `state:` field). Result: the count is always 0, so **every
user is shown Level 0 (beginner)** regardless of history.

**Evidence (verifiable).**
- Current — `commands/aid-help.md:29`:
  `- Task runs: count `state: DONE` in `.aid-o/work/evidence/*/*/state.yaml``
- Ground truth — the FSM state file is `fsm-state.yaml`:
  - `scripts/aid-json-to-run.sh:630` creates `fsm-state.yaml` (the FSM state).
  - `scripts/aid-fsm.sh:277` treats `state.yaml` as a *legacy fallback* only.
  - `cmd_transition` writes `state: DONE` into the FSM state file (fsm-state.yaml), not the progress-array `state.yaml`.

**Proposed change (one line).**
- `commands/aid-help.md:29`
  - BEFORE: `count `state: DONE` in `.aid-o/work/evidence/*/*/state.yaml``
  - AFTER:  `count `state: DONE` in `.aid-o/work/evidence/*/*/fsm-state.yaml``

**Why.** Restores correct level detection. Surgical: only the detection grep changes.
(The other `state.yaml` mentions in this file — lines 83, 106, 141, 192 — are FSM-state
*descriptions*, not the detection logic; they are handled by D1, the mechanical rename
sweep, not here. Keeping B1 to line 29 keeps the bug-fix isolated.)

**How to verify (independent agent).**
1. Confirm `commands/aid-help.md:29` currently says `state.yaml` in the detection bullet.
2. Confirm the real FSM state file is `fsm-state.yaml` (check `aid-json-to-run.sh` around line 630 + `aid-fsm.sh` around line 277).
3. Confirm `state: DONE` is written to `fsm-state.yaml` (search `aid-fsm.sh` for where `state: DONE` / the DONE transition writes the state file).
4. Confirm the change is exactly the filename in that one bullet, nothing else.

---

### Proposal B4 — `/aid-init` pre-push hook description implies the wrong marker → duplicate hooks

**Problem.** `aid-init.md` says the pre-push hook is installed with the "same … markers"
as pre-commit. But the two hooks use **different** marker strings. An installer (LLM or
script) that follows this and searches the pre-push file for the *pre-commit* marker
won't find it → it appends a fresh block **every** time `/aid-init` runs → duplicate
hook blocks accumulate.

**Evidence (verifiable).**
- Current — `commands/aid-init.md:297`:
  `3. **Logic:** Same as pre-commit (copy/append/upgrade with markers)`
- Ground truth — the markers differ:
  - `defaults/hooks/pre-commit:1`: `# AID-ORCHESTRATOR-HOOK-START (do not edit this block manually)`
  - `defaults/hooks/pre-push:2`: `# AID-ORCHESTRATOR-PREPUSH-START (do not edit this block manually)`

**Proposed change (one line).**
- `commands/aid-init.md:297`
  - BEFORE: `3. **Logic:** Same as pre-commit (copy/append/upgrade with markers)`
  - AFTER:  `3. **Logic:** Same copy/append/upgrade flow as pre-commit, but matched on pre-push's OWN marker `AID-ORCHESTRATOR-PREPUSH-START` (NOT the pre-commit `AID-ORCHESTRATOR-HOOK-START`) — idempotency depends on using the correct marker.`

**Why.** Makes idempotent install possible: the installer matches the right marker, so a
re-run upgrades the existing block instead of appending a duplicate.

**How to verify (independent agent).**
1. Confirm `aid-init.md:297` currently says "Same as pre-commit (copy/append/upgrade with markers)".
2. Confirm the two hook files use different START markers (`HOOK-START` vs `PREPUSH-START`) — grep both files in `defaults/hooks/`.
3. Confirm the proposed text names the pre-push marker correctly (`AID-ORCHESTRATOR-PREPUSH-START`).

---

### Proposal B5 — CP4 curator-validation: the template tells the verifier to write the wrong filename → the CP4 gate can never find it

**Problem.** The FSM's CP4 gate (`fsm_check_cp4_curator_validation`) refuses to advance to
release unless a file named **`verifier-output-cp4-curator-validation.md`** exists. But
the output template tells the verifier to write **`verifier-output-cp4-curator.md`** (no
`-validation`), and additionally claims "FSM does NOT enforce" — which is false. So a
verifier following the template writes a filename the gate never looks for → the CP4 gate
silently cannot be satisfied.

**Evidence (verifiable).**
- Wrong filename + false claim — `defaults/templates/verifier-output-template.md`:
  - line 20: `CP4 curator   .aid-o/work/evidence/{epic_id}/{run_id}/verifier-output-cp4-curator.md`
  - line 42: `D. CP4 curator → verifier-output-cp4-curator.md (classification: FULL_REVIEW; FSM does NOT enforce)`
- Ground truth (what the gate requires) — `scripts/aid-fsm.sh:330`:
  `local cp4_file="${evidence_dir}/verifier-output-cp4-curator-validation.md"` (and `:250` "Requires verifier-output-cp4-curator-validation.md").
- pipeline.md agrees with the FSM — `skills/pipeline.md:929`:
  `--output-file "$evidence_dir/verifier-output-cp4-curator-validation.md"`.
- verifier.md gives no CP4 filename at all — `agents/verifier.md:109` only says "CP4: Review curator-proposed changes".

**Proposed change (3 edits, all converging on the FSM/pipeline name).**
1. `verifier-output-template.md:20`
   - BEFORE: `...verifier-output-cp4-curator.md`
   - AFTER:  `...verifier-output-cp4-curator-validation.md`
2. `verifier-output-template.md:42`
   - BEFORE: `D. CP4 curator → verifier-output-cp4-curator.md (classification: FULL_REVIEW; FSM does NOT enforce)`
   - AFTER:  `D. CP4 curator-validation → verifier-output-cp4-curator-validation.md (classification: FULL_REVIEW; FSM DOES enforce presence in cmd_done_advance via fsm_check_cp4_curator_validation)`
3. `agents/verifier.md:109` — add the exact output filename so the agent knows it:
   - BEFORE: `- **CP4:** Review curator-proposed changes (pre-merge, not yet committed to main).`
   - AFTER:  `- **CP4:** Review curator-proposed changes (pre-merge, not yet committed to main). Write output to `verifier-output-cp4-curator-validation.md` (FSM requires this exact name).`

**Why.** Makes the CP4 gate satisfiable: the verifier writes the filename the FSM scans
for, and the template stops falsely claiming the gate is unenforced. Note we converge on
the FSM/pipeline name (`-curator-validation`) because two of three sources already use it
and it's the name the gate actually checks — changing the FSM instead would be a larger,
riskier change touching live enforcement code.

**Scope note.** The "CP4 curator" *labels* and section titles at template lines 61/125/136/157
are dispatch-label / section-content text, not the enforced filename — left unchanged here
(no functional impact). If you want them renamed for tidiness too, that's a D-class cosmetic, not part of this bug-fix.

**How to verify (independent agent).**
1. Confirm the FSM requires `verifier-output-cp4-curator-validation.md` (`aid-fsm.sh:330` + `:250`).
2. Confirm the template currently says `verifier-output-cp4-curator.md` (lines 20, 42) and falsely "FSM does NOT enforce".
3. Confirm pipeline.md already uses `-curator-validation` (`:929`) — i.e. the proposed name matches the majority + the enforcer.
4. Confirm the 3 edits all use the exact string `verifier-output-cp4-curator-validation.md`.

---

## Batch 1.1 summary
| Fix | File(s) | Lines | Risk | Needs your decision? |
|-----|---------|-------|------|----------------------|
| B1 | aid-help.md | 1 | low | no — verify only |
| B4 | aid-init.md | 1 | low | no — verify only |
| B5 | verifier-output-template.md + verifier.md | 3 | low | no — verify only |

All three are doc-only, single-target, and converge on already-existing ground truth in
the scripts. Recommended: hand this batch to an independent verifier; on PASS, I apply all
three as one change (bundled into the Wave-1 release with CHANGELOG + version bump).

**STATUS: applied to branch `fix/P041-wave1` (working tree, not committed) after independent verify returned 3 PASS / 0 REVISE / 0 REJECT.**

---

## D1 RECLASSIFIED — NOT a mechanical sweep (moved to Wave 2 / FEEDBACK)

Prep for D1 (rename `state.yaml` → `fsm-state.yaml` across docs) revealed it is a
**migration decision, not a find-replace.** Evidence:
- `skills/pipeline.md` uses `state.yaml` as the primary name in ~17 places and at `:171`
  explicitly says both files (`state.yaml` + `fsm-state.yaml`) coexist for backward compat.
- `defaults/orchestration.yaml:46` `state_file: ...state.yaml` is a **config value that
  drives behavior**, not documentation.
- `defaults/hooks/pre-commit:21` searches for BOTH names; grandfathering reads
  `state.yaml.created_at` (template `:23`, step-verify `:20`).
A blind rename risks breaking the legacy-fallback / grandfathering / config paths.
**Decision needed (Wave 2):** is `state.yaml` fully superseded by `fsm-state.yaml`, or do
they coexist? The B1 fix (aid-help detection grep) was safe because it targeted the
`state: DONE` field which lives only in `fsm-state.yaml` — but the general rename is not.

---

## BATCH 1.2 — Wave 1, D2: strip version-stamped headings (mechanical, safe)

**The rule applied:** strip trailing version/plan parentheticals — `(vX.Y.Z+)`,
`(NEW vX…)`, `(UPDATED vX…)`, `(P0NN, vX…)`, `(P0NN — …)` — from markdown `##`/`###`
**headings only**. Attribution that mattered already lives in the body / CHANGELOG.
Per skill-writing Forbidden Pattern #1: version metadata in headings accretes into noise.

**Explicitly NOT touched (and why):**
- `defaults/{integrations,execution,orchestration}.yaml:1` title comments `(v2)` — config
  file-format markers, not accreting doc headings. Keep.
- `defaults/execution.yaml:234` section divider `(P040 Component C)` — config comment naming the feature, not a doc heading. Keep.
- `commands/aid-init.md:350` `## Upgrade (v1 → v2)` — semantic (describes the v1→v2 upgrade direction), not a "when-added" stamp. Keep.
- `skills/visual-companion/SKILL.md:343` `(P027 …)` — visual-companion is OUT of audit scope. Skip.
- `agent-protocol.md:253` `### P040 audit events` — strip only the `(v2.25.0+)`; keep "P040 audit events" (it names the event family, referenced elsewhere).

**The 14 heading edits (exact before → after):**

| # | file:line | BEFORE (heading) | AFTER |
|---|-----------|------------------|-------|
| 1 | agent-protocol.md:197 | `## Tiered Severity Reference (v2.21.0)` | `## Tiered Severity Reference` |
| 2 | agent-protocol.md:253 | `### P040 audit events (v2.25.0+)` | `### P040 audit events` |
| 3 | brainstorming.md:309 | `### Section Verdict Format (P039 — validate-then-verify)` | `### Section Verdict Format` |
| 4 | aid-init.md:79 | `### execution.yaml Generation (P032)` | `### execution.yaml Generation` |
| 5 | aid-plan.md:370 | `### Streamlined Mode Advisory (P040, v2.25.0+)` | `### Streamlined Mode Advisory` |
| 6 | pipeline.md:64 | `### force_override Usage Policy (v2.18.0+)` | `### force_override Usage Policy` |
| 7 | pipeline.md:142 | `### Branch Enforcement (NEW v2.16.0 — P032 Step 2)` | `### Branch Enforcement` |
| 8 | pipeline.md:464 | `### Dispatch Protocol (P040, v2.25.0+)` | `### Dispatch Protocol` |
| 9 | pipeline.md:609 | `### EXECUTE→GATES Precondition (UPDATED v2.16.0 — P032 Step 3)` | `### EXECUTE→GATES Precondition` |
| 10 | pipeline.md:634 | `#### Recommended Flow (v2.18.3+): aid-fsm.sh advance-to-gates` | `#### Recommended Flow: aid-fsm.sh advance-to-gates` |
| 11 | pipeline.md:780 | `### Compliance Telemetry (NEW v2.16.0 — P032 Step 4)` | `### Compliance Telemetry` |
| 12 | pipeline.md:813 | `### Tiered Severity Enforcement (NEW v2.21.0 — P038 AID-038 Phase 2)` | `### Tiered Severity Enforcement` |
| 13 | verifier.md:26 | `## Context Handed to Verifier (v2.18.0+ nuanced deprivation)` | `## Context Handed to Verifier` |
| 14 | aid-status.md:159 | `## Evidence Paths (v2)` | `## Evidence Paths` |

(14 rows — #14 aid-status `(v2)` included as a heading stamp; the yaml `(v2)` title comments are NOT.)

**Date bumps (justified — each file gets a real content change):** bump `**Last Updated:**`
to 2026-06-01 on the files destamped: agent-protocol.md, brainstorming.md, aid-plan.md,
pipeline.md, aid-status.md (aid-init.md + verifier.md already bumped in Batch 1.1).

**Why.** Removes the most common skeleton class (Forbidden Pattern #1) in one sweep.
Purely cosmetic to behavior — no code, no logic, only heading text. The named feature/plan
context survives in the body prose + CHANGELOG.

**Risk check (important):** does any heading get *referenced by its full stamped text*
elsewhere? Checked: cross-references use the bare name (e.g. "pipeline.md §4 Dispatch
Protocol", "Tiered Severity"), not the parenthetical — so stripping is safe. The independent
verifier should re-confirm this (grep for the stamped strings as references).

**How to verify (independent agent).**
1. For each of the 14 rows, confirm the BEFORE heading exists verbatim at that file:line.
2. Confirm each is a markdown `##`/`###` heading (not a YAML comment / config value).
3. Confirm no other file references the heading by its *stamped* form (grep e.g. `(NEW v2.16.0`, `(P040, v2.25.0` as cross-refs) — stripping must not break a link.
4. Confirm the AFTER text keeps the descriptive name intact (only the version/plan paren removed).
5. Confirm the 5 listed date bumps are on files that actually received a heading edit.

**Batch 1.2 summary:** 14 heading edits + 5 date bumps across 6 files (agent-protocol,
brainstorming, aid-plan, pipeline, aid-status, verifier). Doc-only, no logic. Apply with
Batch 1.1 in the Wave-1 release.

**STATUS: applied to branch `fix/P041-wave1` after independent verify returned 14/14 PASS.**
(Also fixed the agent-protocol header/footer date mismatch found in the second audit pass,
and corrected a "13 vs 14" stale count in this doc.)

---

## A2 + A4 RECLASSIFIED — NOT clean batches (moved out of Wave 1)

Prep revealed both are more tangled than line-level findings suggested:

- **A2 (aid-run.md fictional content) → Wave 2 careful rework.** The §EXECUTE block,
  the 6-state ASCII diagram (`DONE → error → ERROR` is fabricated — `VALID_TRANSITIONS`
  has NO `DONE:` edge; aid-fsm.sh:34-37 sources ERROR from READY/EXECUTE/GATES/ESCALATION),
  the per-step branch (`task/{task_id}/step_{N}` vs the real single `task/{epic_id}/main`,
  aid-fsm.sh:1323), the merge target (`git merge epic/{id}` — no such branch), the
  `{task_id}` vs `{epic_id}` drift, the `steps/` evidence subdir, and the parallel-dispatch
  prose are ALL intertwined with the (currently-disabled) parallel model + the FSM
  single-branch reality. Cherry-picking 2 lines leaves the section inconsistent, and the
  ASCII diagram needs a careful redraw (high risk of introducing a new wrong diagram). This
  is a focused rework with PM eyes, not a mechanical batch.
- **A4 (memory.md:21 wrong fields) → folds into D1.** `cat state.yaml` shows fields
  (`current_step`/`total_steps`) that live in `fsm-state.yaml` — same state-file migration
  question as D1, handle together.

---

## BATCH 1.3 — Wave 1, A3-clean: aid-research dead references (migration-independent)

aid-research.md has several doc-vs-code defects. The ones tied to the memory *interface*
(fabricated `knowledge_research()`/`memory_store()`/`run_quality_gates()` functions at
:114/:116/:187/:196, the "4 quality gates" set at :128, qdrant naming) are DEFERRED to
Wave 3 / G1 — they get rewritten when the memory layer migrates to vulcan-memory, so fixing
them now means touching them twice. This batch is ONLY the migration-independent dead refs:

### A3a — dead `/aid-setup Option 6a/6b` references
**Problem.** aid-research points users to "/aid-setup Option 6a" (Qdrant) and "Option 6b"
(Context7), but `/aid-setup` has no numbered options — it reads a preset, counts
integrations, and runs named modules (aid-setup.md:47-72). Dead instruction.
**Evidence.**
- `commands/aid-research.md:29`: `- For persistent storage: Qdrant MCP configured (see `/aid-setup` Option 6a)`
- `commands/aid-research.md:30`: `- For Context7 source: Context7 MCP configured (see `/aid-setup` Option 6b)`
- `commands/aid-setup.md:47-72`: no "Option 6a/6b"; setup runs modules (permissions, integrations, ...).
**Proposed change.**
- `:29` AFTER: `- For persistent storage: a memory MCP configured (run `/aid-setup`, integrations module)`
- `:30` AFTER: `- For Context7 source: Context7 MCP configured (run `/aid-setup`, integrations module)`

### A3b — reads template config instead of live project config (this is B3)
**Problem.** Reads `defaults/integrations.yaml` (the plugin TEMPLATE, `enabled: false`)
instead of `.aid-o/config/integrations.yaml` (the live project config written by /aid-init).
Every other runtime reader uses `.aid-o/config/`.
**Evidence.**
- `commands/aid-research.md:76`: `1. Read `defaults/integrations.yaml` for knowledge configuration (memory + knowledge sections)`
- contrast `commands/aid-setup.md:48` + `skills/memory-mcp.md:282` use `.aid-o/config/`.
**Proposed change.**
- `:76` AFTER: `1. Read `.aid-o/config/integrations.yaml` for knowledge configuration (memory + knowledge sections)`

### A3c — dead-ref to a file that doesn't exist
**Problem.** `defaults/integrations.yaml:82` points to `skills/knowledge-acquisition.md` for
protocol details — that file does not exist. The real protocol home is `skills/memory-mcp.md`
(which aid-research already cites at :233).
**Evidence.**
- `defaults/integrations.yaml:82`: `# See: skills/knowledge-acquisition.md for protocol details.`
- `ls skills/knowledge-acquisition.md` → No such file.
- `skills/memory-mcp.md` exists and is the storage-protocol home.
**Proposed change.**
- `integrations.yaml:82` AFTER: `# See: skills/memory-mcp.md for storage-protocol details.`

**Date bump:** aid-research.md footer (`2026-03-19` → `2026-06-01`). integrations.yaml has no Last Updated footer.

**Why.** Removes three dead/wrong references that send the operator to nonexistent options/
files/config. All migration-independent (don't touch the memory interface).

**How to verify (independent agent).**
1. Confirm `/aid-setup` has no "Option 6a/6b" (read aid-setup.md menu/flow).
2. Confirm runtime config is `.aid-o/config/integrations.yaml`, and `defaults/` is the /aid-init template (check aid-setup.md / memory-mcp.md usage; check defaults/integrations.yaml `enabled: false`).
3. Confirm `skills/knowledge-acquisition.md` does NOT exist and `skills/memory-mcp.md` does.
4. Confirm the deferred items (fabricated functions :114/:116/:187/:196, gate set :128) are NOT touched in this batch (they're Wave-3/G1).

**Batch 1.3 summary:** 4 edits (aid-research ×3 + integrations.yaml ×1) + 1 date bump. Doc/config-comment only, migration-independent.

**SUPERSEDED by Batch 1.3-R** — PM decided aid-research is to be DELETED entirely, so fixing
its dead refs is moot. See below.

---

## BATCH 1.3-R — FEATURE REMOVAL: aid-research + the dead knowledge-base layer

**PM decision (2026-06-01):** delete aid-research entirely, including all references.

**Why it's safe to delete (verified).** aid-research is an aspirational command that was
never wired up: it calls functions that don't exist (`knowledge_research()`,
`memory_store()`, `run_quality_gates()`), reads template config, and cites a nonexistent
skill. Crucially, **nothing consumes the knowledge base it claims to feed** — the
aid-research.md claim "for use by brainstorming and agent dispatch" is false; the only
"knowledge" hit in brainstorming.md is the word "ac**knowledge**" (false match). So the
entire `knowledge:` layer is dead: one incomplete producer, zero consumers.

**Scope verification (whole repo).** `grep -rln aid-research` (excluding audit docs) →
only: `commands/aid-research.md`, `defaults/templates/knowledge-base.yaml`, both CHANGELOGs.
No `.json` manifest lists it (commands auto-discover from the dir). README does not mention
it. aid-help.md does not mention it (the audit's "add aid-research to help" item is now moot).
aid-init.md does not name knowledge-base.yaml. The `memory:` section of integrations.yaml is
SEPARATE and STAYS (it's the real agent memory); only `knowledge:` goes.

### Removal actions

**DELETE 2 files:**
- `plugins/aid-orchestrator/commands/aid-research.md` (the command)
- `plugins/aid-orchestrator/defaults/templates/knowledge-base.yaml` (template, only used by aid-research)

**EDIT — remove the knowledge bits:**
- `defaults/integrations.yaml`:
  - line 4 comment: `# Controls: Slack MCP integration, Qdrant memory, knowledge acquisition.` → drop "knowledge acquisition"
  - lines 81–112 (the whole `# ─── Knowledge Acquisition ───` header through the end-of-file `knowledge:` block incl. research/quality/aging) → DELETE entirely
- `skills/setup/integrations.md`:
  - line 41: `(slack, memory, knowledge)` → `(slack, memory)`
  - line 49: the table row `| `*context7*` | `knowledge:` + `knowledge.context7:` | Library docs |` → DELETE the row

**CHANGELOG (root + plugin, identical) — add a `### Removed` entry:**
- `- **aid-research command + knowledge-base layer** — removed the aspirational on-demand research command and its unused knowledge-base template + integrations `knowledge:` config; it was never wired (called nonexistent functions, had no consumer).`
- Keep the historical aid-research entries (they are history; don't rewrite).

**NOT touched:** the historical CHANGELOG entries that mention aid-research's introduction
(they record what happened); the `memory:` section of integrations.yaml (real, stays);
the qdrant→vulcan migration (separate, Wave 3).

**This obsoletes:** Batch 1.3 (A3a/b/c) — those fixed aid-research's dead refs; pointless now.
Also moots the audit's "add aid-research to aid-help" recommendation.

**How to verify (independent agent).**
1. Confirm `grep -rln aid-research` (excluding docs/plans/AID-audit-2026-06) returns ONLY the
   2 files-to-delete + the 2 CHANGELOGs. Nothing else references it.
2. Confirm nothing CONSUMES the knowledge base: grep `knowledge_research|knowledge-base|knowledge:`
   across skills/agents/scripts — only the producer side (aid-research + its config/template) +
   setup/integrations.md routing. Confirm brainstorming.md's "knowledge" hit is "acknowledge".
3. Confirm `memory:` (integrations.yaml:35) is independent of `knowledge:` (line 84) — deleting
   knowledge must not touch memory.
4. Confirm no `.json` manifest or README enumerates aid-research (auto-discovery).
5. Confirm aid-init.md does not explicitly copy knowledge-base.yaml (so its deletion can't break init).

**Risk:** low. Deleting a never-consumed, never-wired feature. Reversible via git if needed.
Bundle into the Wave-1 release (CHANGELOG + version bump).

### Batch 1.3-R v2 — REVISED after 3rd-pass verify (verdict was REVISE)

The 3rd independent pass confirmed the deletion is safe but found the v1 scope **incomplete**
and one claim **false**. Both corrected here. Key insight: **Context7 exists in the plugin
ONLY as the knowledge layer's source** (`knowledge.primary_source: context7`) — verified by
grep, Context7 has no other plugin use. So removing the knowledge layer orphans ALL Context7
references too. Per PM's "remove all references", Context7's plugin references go with the
layer (the Context7 MCP *server* itself is not ours to remove — only the plugin's now-dead
references to it).

**CORRECTED FALSE CLAIM:** v1 said "setup/integrations.md — nic mimo ř.41/49". False —
the same file references Context7 at :28 and :59 too. Retracted.

**COMPLETE edit set (v1 + the 7 leftovers the 3rd pass found):**

DELETE 2 files (unchanged): `commands/aid-research.md`, `defaults/templates/knowledge-base.yaml`.

EDIT:
- `defaults/integrations.yaml` — :4 comment (drop "knowledge acquisition"); :81–112 `knowledge:` block (delete). [v1]
- `skills/setup/integrations.md`:
  - :41 `(slack, memory, knowledge)` → `(slack, memory)` [v1]
  - :49 delete the `*context7*` → `knowledge:` routing row [v1]
  - **:28 delete** the example line `  [disabled]   context7 — library documentation lookup` [NEW]
  - **:59 fix** example output `  enabled: qdrant-memory, context7` → `  enabled: qdrant-memory` [NEW]
- **`commands/aid-help.md:204`** — `(Qdrant, Context7, Slack, ...)` → `(Qdrant, Slack, ...)` [NEW]
- **`defaults/policies/permissions.yaml:41–43`** — delete the 3-line Context7 allowlist block (`# ── Context7 (plugin-loaded) ──` + `resolve-library-id` + `query-docs`) — orphaned tool grant [NEW]
- **`defaults/templates/plan.schema.json:92–96`** — delete the `knowledge` boolean property from `context_scope` (keep `memory`); the knowledge-injection consumer was never wired in pipeline.md [NEW]
- **`skills/plan-writing.md`**:
  - **:66 delete** line `- Knowledge context (if knowledge acquisition was active)` [NEW]
  - **:464 delete** table row `| Knowledge context references | Inline citations in relevant sections |` [NEW]

CHANGELOG `### Removed` (root + plugin, identical), expanded:
- `- **aid-research command + knowledge-base/Context7 layer** — removed the never-wired on-demand research command, its knowledge-base template, the integrations `knowledge:` config, the `context_scope.knowledge` plan-schema flag, and all orphaned Context7 references (allowlist, setup examples, help text). The layer had no producer wired and no consumer; Context7 had no other plugin use.`

**Runtime note (out of plugin-distribution scope, but in THIS repo):**
`.aid-o/config/policies/dispatch-config.yaml` carries per-tier `knowledge: true/false` keys
+ a dead ref to `skills/knowledge-acquisition.md` at ~:89. It is NOT generated from a defaults
template, so it's not part of the plugin removal — but after this batch it carries dead refs.
**Recommend a separate small cleanup** of that local file (strip `knowledge:` keys + the dead
ref). Flag for PM: do it now or leave the local workspace as-is?

**Context7 decision (needs PM confirm):** Option A (recommended) — Context7's plugin refs go
with the layer, since it has no other plugin use. Option B — keep Context7 as a general MCP
capability (then we'd KEEP permissions.yaml:41-43 + reword help/examples instead of deleting,
and the "entire layer dead" framing would need softening). Recommending A per "remove all
references".

**Re-verify scope:** the complete edit set above (2 deletes + ~9 edits across 6 files +
CHANGELOG), plus confirm Context7 has no non-knowledge plugin use (grep), plus the runtime
dispatch-config note.

### Batch 1.3-R v3 — ARCHIVE (not delete) + split into R1 (research/knowledge) then R2 (Context7)

PM decisions (2026-06-01): (a) Context7 confirmed removable (Option A). (b) **Don't delete —
ARCHIVE**, so it can be restored later. (c) **Two phases**: research/knowledge first, Context7 second.

**Archive mechanism.** New dir `docs/plans/AID-audit-2026-06/removed/` (in repo, OUTSIDE the
plugin so it isn't distributed):
- Whole files → `git mv` into `removed/` (full content + git history preserved).
- Excised fragments (cut from files that stay) → appended to `removed/knowledge-layer-snippets.md`
  with a header per fragment: source file:line + the exact removed text + a one-line "to restore: …".
Nothing is lost; restore = copy back from `removed/`.

#### Phase R1 — research / knowledge layer (do first)
- **Move whole:** `commands/aid-research.md` → `removed/aid-research.md`;
  `defaults/templates/knowledge-base.yaml` → `removed/knowledge-base.yaml` (git mv).
- **Excise → snippets archive, then remove from source:**
  - `integrations.yaml`: the `knowledge:` block (:81–112) + drop "knowledge acquisition" from the :4 comment.
  - `plan.schema.json`: the `context_scope.knowledge` boolean property (:92–96).
  - `plan-writing.md`: :66 line + :464 row.
  - `skills/setup/integrations.md`: :41 drop the word "knowledge" from `(slack, memory, knowledge)`.
- **CHANGELOG** `### Removed` entry (root + plugin) — note items ARCHIVED to `removed/`, not deleted.
- **Local runtime cleanup** (this repo's `.aid-o/`): strip `knowledge:` keys + dead ref from
  `.aid-o/config/policies/dispatch-config.yaml` (archive the removed keys to snippets too).
- NOT in R1: Context7 references (they're R2).

#### Phase R2 — Context7 references (do after R1)
- **Excise → snippets archive, then remove from source:**
  - `skills/setup/integrations.md`: :28 example line + :49 routing row + :59 example output.
  - `commands/aid-help.md`: :204 drop "Context7" from the integrations list.
  - `defaults/policies/permissions.yaml`: :41–43 Context7 allowlist block.
- **CHANGELOG** `### Removed` entry for the Context7 references (archived).
- Note: the Context7 MCP *server* is untouched (not ours) — only AID's now-dead refs to it.

**This v3 supersedes v2's "delete" framing** — same scope, but archived + 2-phase. Scope was
already verified 3× (the edit set is unchanged); the only new things to verify are the archive
moves land correctly and R1/R2 split is clean.

**STATUS: R1 executed + verified (4/4 content PASS). R2 executed + verified (4/4 PASS). aid-research fully removed + archived to `removed/`.**

---

## E2 + I3 RECLASSIFIED — partial (only the clean bits stay in Wave 1)

Prep split both:
- **E2 (aid-status):** the `pause`/`resume`/`reorder` subcommands + "Auto-pickup" display
  have NO backing script → that's **F1 (Wave 2, FEEDBACK: build or delete?)**, not a doc fix.
  The status mapping (`[DONE]`→completed, `[FAIL]`→failed) IS documented (aid-status.md:117-118),
  so it's NOT a bug. The only clean Wave-1 bit is the `{task_id}`→`{epic_id}` path drift.
- **I3:** the memory-mcp un-sourced dedup threshold ties to the memory interface →
  **Wave 3 / G1 (memory migration)**. The implementer model-block (Forbidden Pattern #3) is clean.

---

## BATCH 1.4 — Wave 1, last clean batch (E3 + implementer + aid-status naming)

### E3a — brainstorming prior-work glob points at a nonexistent dir
**Problem.** Globs `.aid-o/epics/*.md` for prior EPICs, but EPIC specs live in `.aid-o/tasks/`
(per CLAUDE.md + run-management.md). `.aid-o/epics/` doesn't exist → silently matches nothing.
**Evidence.** `skills/brainstorming.md:64`: `        prior work: glob .aid-o/plans/*.md and .aid-o/epics/*.md for keyword overlap`
**Change.** `.aid-o/epics/*.md` → `.aid-o/tasks/*.md` (keep `.aid-o/plans/*.md`).

### E3b — brainstorming claims "enum unchanged" then narrows it (internal contradiction)
**Problem.** Says it reuses the verifier `review_result` enum **unchanged**, but then lists
`severity critical|low` (2 levels) while the canonical enum (role-cards.md section-review) is
`critical|high|medium|low` (4). Claiming "unchanged" while changing it is the N2 contradiction.
**Evidence.** `skills/brainstorming.md:330-331`: `... reuse the verifier `review_result` enum unchanged (verdict PASS|FAIL|PASS_WITH_NOTES; severity critical|low). Map only at render: ...`
**Change (minimal, honesty fix).** `reuse the verifier `review_result` enum unchanged (verdict PASS|FAIL|PASS_WITH_NOTES; severity critical|low)` → `reuse the verifier `review_result` enum (verdict PASS|FAIL|PASS_WITH_NOTES; severity critical|high|medium|low — brainstorm section-review typically uses critical|low)`. (Stops the false "unchanged" claim + names the full scale; doesn't touch render markers.)

### I3-impl — implementer model-block duplicates role-cards + omits roles
**Problem.** Enumerates model tiers for [architect/backend/frontend]=opus, [domain/observability/
docs-writer]=sonnet, default sonnet — duplicating role-cards' `**Model:**` fields (Forbidden
Pattern #3) AND omitting security/release/VULCAN roles → they silently fall to default sonnet,
masking role-cards' explicit tiers.
**Evidence.** `agents/implementer.md:13-16` (the `**Model selection (from role-cards.md):**` block).
**Change.** Replace the enumerated block with a pointer:
```
**Model selection:** use the `**Model:**` field of your role card in `skills/role-cards.md`
(single source of truth — covers all roles incl. security/release/VULCAN specialists).
```

### E2-naming — aid-status uses `{task_id}` where the system uses `{epic_id}`
**Problem.** Evidence-path templates say `{task_id}`; the real evidence path is
`evidence/{epic_id}/...` (aid-fsm.sh). Terminology drift (low severity, but inconsistent).
**Evidence.** `commands/aid-status.md:29, 57, 126, 162` use `{task_id}`.
**Change.** `{task_id}` → `{epic_id}` at those 4 path templates (display examples with real
E-prefixed IDs are already correct; only the `{task_id}` placeholders change).

**Date bumps:** brainstorming.md (already 2026-06-01 from Batch 1.2), implementer.md
(2026-03-03 → 2026-06-01), aid-status.md (already 2026-06-01 from Batch 1.2).

**How to verify (independent agent).** Branch fix/P041-wave1 accumulates Wave 1 — verify only Batch 1.4:
1. `.aid-o/tasks/` is the canonical EPIC dir, `.aid-o/epics/` does not exist (check CLAUDE.md / run-management.md).
2. role-cards.md section-review uses `critical|high|medium|low` (confirm the 4-level enum).
3. role-cards.md has `**Model:**` fields covering security/release/VULCAN roles that implementer's old block omitted.
4. aid-fsm.sh evidence path uses `{epic_id}` not `{task_id}`.
5. Each before→after string matches the cited file:line verbatim.

**Batch 1.4 summary:** 4 edits across 3 files (brainstorming ×2, implementer ×1 block, aid-status ×4 placeholders) + 1 date bump. Doc-only. Last clean Wave-1 batch — after this, Wave 1 = release (commit + version bump + CHANGELOG).
