# I2 / AID-052 — Coverage completion (E87–E177 mapping + 6 skipped files) — 2026-06-03

Extends Phase-2 mapping (02-mapping.md covered E01–E86) to the ~91 second-pass enforcements
E87–E177, plus the 6 files the skill/command audit skipped, plus learning #11. Done via 5 parallel
read-only Explore agents; key claims spot-verified by hand. Verdict vocabulary per 02-mapping.md:
ALIGNED · GAP (enforcement exists, no instruction) · ORPHAN (instruction/contract, no enforcement) ·
CONTRADICTORY · UNREACHABLE.

## Headline
**E87–E177 (91 enforcements): ~78 ALIGNED (~86%), 13 non-aligned.** Of the 13, only **3 are the
dangerous direction** (ORPHAN — contract without enforcement, Principle #1); the rest are
inventory-doc errors (3) or low-priority "undocumented-but-working" script guards (7 GAP).

## The 3 ORPHANs — Principle #1 (detector/contract without enforcement) — NEED PM DECISION
| ID | Contract (instruction) | Enforcement status | Options |
|----|------------------------|--------------------|---------|
| **E161** | frontend MUST emit `## Visual Anchoring` before code when `visual_refs` present (role-cards.md frontend card) | NO gate checks it — instruction-only | (a) add CP/verifier check that the section exists when visual_refs set, or (b) honestly mark advisory |
| **E165** | PHASE-END CHECKPOINT HARD STOP — AI must stop + wait for PM GO (run-management.md) | NO FSM precondition blocks the next phase; procedural/conversational only | (a) add FSM phase-gate for autonomous mode, or (b) document it as a manual-mode-only convention |
| **E171** | parallel-group file-conflict → forced sequential; waves of 5+ split to sub-waves of 4 (planner.md) | NO enforcement; inventory line ref (planner.md:172) is also wrong (file is shorter) | (a) implement in scope-check.sh (compare allowed_paths across a parallel group), or (b) make it PM responsibility + document in epic.md |

## Inventory-doc corrections (fix the AUDIT inventory, NOT the plugin)
- **E140** — inventory line 270 still describes the old "±60s around _generated_by" provenance window.
  The config + code are now correct (interval-bracket, post-C1/AID-046). Inventory text is stale.
- **E155** — inventory cites `integrations.yaml` `dedup_threshold: 0.85` / `merge_threshold: 0.70`.
  **Verified: those fields do NOT exist in integrations.yaml.** Phantom reference. Ties to the
  memory subsystem (the 0.85 dedup knob lived in the MEM-AUDIT/G1 scope) → fold into MEM-AUDIT.
- **E175** — inventory says `/aid-stop` writes `mode: paused` + `resumable: true`. **Verified: aid-stop.md
  writes `mode: manual`** (auto-pickup is gated on `mode==auto`), and is internally consistent
  (FSM persists progress; aid-stop.md:164 honestly says it does not itself save progress). Inventory wrong.

## Low-priority GAPs — enforcement exists in script, not surfaced in LLM-facing instruction
(These FIRE correctly; they're just not pre-documented. GAP is the less-dangerous direction.)
- **E91** — malformed Steps-table row silently dropped (`aid-epic-to-json.sh`); planner.md doesn't say "silently".
- **E107** — detached-HEAD / empty-SHA guard (`aid-json-to-run.sh`); not in pipeline.md PRE-FLIGHT.
- **E108** — output filename >200 chars truncated silently; undocumented.
- **E113** — cmd_init git/jq preflight; error-message only, not in pipeline.md §2.
- **E121** — orphan-waiver needs BOTH `--force` AND `--blocked-checks`; coupling not instructed.
- **E124** — promote-check `--reason` yq-injection escaping; not instructed.
- **E126** — promote-check yq/write-failure guards; not instructed.
Recommendation: optional one-paragraph "PRE-FLIGHT guards & silent-truncation notes" addendum in
pipeline.md §2 + planner.md error-handling. Low value; can defer or skip.

## 6 skipped files — holistic audit
- **CLEAN:** commands/aid-setup.md, skills/setup/permissions.md, skills/setup/project-scan.md,
  skills/setup/claude-md.md, defaults/templates/design-sections.md, skills/visual-companion/SKILL.md
  (fallback path slightly fragile — cosmetic, low).
- **skills/setup/integrations.md:25–31** — example MCP list uses illustrative names
  (qdrant-memory/shared-docker/shared-slack/shared-playwright) that match neither current eco nor the
  plugin's own G-020 set. It's a GENERIC distributed-plugin example (not eco-bound), so it's cosmetic,
  not a correctness bug. Optional polish: use neutral current-ish names.

## Learning #11 (permissions preset stale)
**Already fixed** in defaults/policies/permissions.yaml (audit note dated 2026-05-31 — removed stale
qdrant-*/shared-docker/shared-telegram/shared-postgres/shared-minio/shared-playwright). The only
residue is the cosmetic integrations.md example above. #11 = effectively closed.

## ⚠️ CORRECTION after external verification (2026-06-03) — fan-out over-claimed ALIGNED on config knobs
Two external verifiers reviewed. One PASS, one FAIL with specific miscategorizations. Ground-truth
re-check (grep of each config key OUTSIDE its defining yaml) CONFIRMED the FAIL verifier: the
config-POLICY layer is largely unwired. Distinction that the fan-out missed: execution.yaml /
permissions.yaml are loaded only for GATE DEFINITIONS (test_cmd, gates[], per-gate `max_retries`,
scope_check, docs_updated, cp4_production_paths) and "auto-approve mode" — the gate-execution parts
ARE enforced. But the POLICY knobs below are referenced NOWHERE (no script reads them, no instruction
tells the LLM to honor them) → ORPHAN/decoration, not ALIGNED:

| ID | Knob | grep outside yaml | Verdict (corrected) |
|----|------|-------------------|---------------------|
| E141 | `escalation.max_per_session: 3` | 0 | ORPHAN — nothing tracks/enforces the counter |
| E142 | `release.skip_when` (no_changelog_version) | 0 | ORPHAN — aid-release.sh doesn't read it; no instruction |
| E143 | `skill_conflicts` deny list | 0 | ORPHAN — /aid-setup uses a hardcoded table instead (claude-md.md:49) |
| E148 | `escalation_triggers` HARD STOP set | 0 | ORPHAN — no instruction enumerates them |
| E149 | `not_acceptable` patterns | 0 | ORPHAN — not wired (some overlap pre-filter, separately) |
| E151 | global `retry.max_attempts: 3` | runner reads per-gate `max_retries` only | ORPHAN — global block unread |
| E154 | `search.min_score: 0.4` | 0 | ORPHAN/ memory-subsystem → MEM-AUDIT |
| E155 | `dedup/merge_threshold` | 0 (fields absent) | phantom → MEM-AUDIT |
| E157 | `permissions.yaml role_overrides` | 0 | ORPHAN — capability scoping not enforced |

Minor reclassifications:
- **E106** (atomic write) — GAP, not ALIGNED (enforcement real at aid-json-to-run.sh:597; LLM docs only say "writes run file"). Low priority.
- **E121** (orphan-waiver force+blocked-checks coupling) — ALIGNED, not GAP (coupling IS documented at pipeline.md:505; only the security *rationale* is unstated). Fix the inventory note.
- **E145** (docs_updated) — ALIGNED but has `required: false` in execution.yaml; pipeline.md doesn't mention the opt-in qualifier. Very low.
- #11 wording "qdrant-*" too broad — permissions.yaml intentionally keeps `qdrant-brain` (back-compat).

## REVISED headline
Config-EXECUTION layer (gates) is enforced. Config-POLICY layer is the real gap: **~9 policy knobs
(E141/E142/E143/E148/E149/E151/E154/E157 + phantom E155) are decoration** — present in yaml, honored
by nothing. Plus the 3 instruction ORPHANs (E161/E165/E171). That is the meaningful Principle-#1
cluster, far bigger than the first "3 ORPHANs" read.

## Net actionable for the plugin
1. **Config-policy decoration cluster (~9 knobs)** — the big one. Per-knob PM decision: wire it (script
   or explicit LLM instruction) / keep as advisory-PM-config-honored-by-judgment + document that
   honestly / delete. Some (E154/E155) fold into MEM-AUDIT. This is a design conversation.
2. **3 instruction ORPHANs (E161, E165, E171)** — harden vs advisory vs defer (parallelism off).
3. **Inventory corrections (E140/E155/E175 + E161/E171 wrong line refs + E121 reclass)** — fix
   01-enforcement-inventory.md; no plugin change.
4. **Low-priority GAP docs (E91/E106/E107/E108/E113/E124/E126)** — optional; defer/skip.
