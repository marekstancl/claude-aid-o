# P041 — WORK STATE / HANDOFF (for compact-safe resume)

**Last updated:** 2026-06-01. Read this first after a context compact to resume cleanly.

## What this is
P041 = enforcement-vs-instruction audit of the `aid-orchestrator` plugin + skill/command
quality audit, now in the **FIX EXECUTION** phase. All audit deliverables + fix tracking live
in `docs/plans/AID-audit-2026-06/` (this dir is **gitignored** — local only, by repo design).

## Git state
- **Branch:** `fix/P041-wave1` (accumulates all P041 fixes; rename to fix/P041-fixes was offered, not done).
- **Last commit:** `c5e66db release: v2.26.0 — P041 audit Wave 1` (Wave 1 fixes + aid-research removal + version bump across 8 registry files).
- **Uncommitted (Wave 2 so far):** aid-help.md, aid-run.md, aid-status.md, aid-stop.md.
- **Release strategy (PM-agreed):** commit per WAVE (not per batch); NO push / tag / merge / GitHub-release / plugin-update until PM explicitly says. Wave 1 committed branch-only. Wave 2 will get its own commit + CHANGELOG + version bump at wave end.

## Working agreements (PM = Marek, Czech, non-technical in AID internals)
- **Talk human, NO internal codes** (E2/I3/A2... confused him — describe by file + what's wrong).
- **Every fix batch:** I propose (verifiable: exact file:line, before→after, why, how-to-verify) → dispatch an internal verifier agent → give Marek a copy-paste TEXT so he runs his OWN external verifier → on PASS, apply.
- **Archive, never hard-delete:** moved/removed content goes to `docs/plans/AID-audit-2026-06/removed/` (whole files via git mv; excised fragments into `*-snippets.md` with restore notes).
- **Two-round discipline:** second adversarial pass repeatedly catches misses + wrong findings — keep doing it.
- **Reclassify when prep reveals entanglement** (don't force half-fixes). Done for D1, A2, A4, E2, I3, and the queue/Context7 splits.
- Verifier prompts MUST say "branch accumulates Wave-1+ fixes — ignore unrelated prior changes" (else false "out of scope" fails).

## The roadmap / fix plan
- **`10-fix-plan.md`** = the human 8-theme + 4-wave map (PM-facing).
- **`11-fix-proposals.md`** = per-batch verifiable proposals (1.1, 1.2, 1.3-R v3, 1.4) + reclassification notes.
- **`04-decisions.md`** = 17 decisions D-01..D-17 + AID-045..058 inventory allocation.
- **`12-stop-resume-fix-design.md`** = the stop/resume design (Option B chosen).

## DONE (committed, Wave 1 = v2.26.0)
- 1.1 functional bugs: aid-help level-detect (state→fsm-state), aid-init pre-push marker, CP4 filename in template+verifier.
- 1.2 stripped 14 version-stamped headings + date bumps.
- 1.3-R: **aid-research + knowledge + Context7 fully removed**, archived to removed/ (aid-research.md, knowledge-base.yaml, knowledge-layer-snippets.md, context7-snippets.md).
- 1.4: brainstorming glob (.aid-o/epics→tasks) + severity-enum honesty + implementer model pointer + aid-status {task_id}→{epic_id}.
- Tests: 19 pre-existing failures on main = baseline (NOT caused by our changes; flagged as separate item).

## DONE this wave (Wave 2, UNCOMMITTED, both verified)
- **Queue pause/resume/reorder removed** (unbacked) — archived to removed/queue-commands-snippets.md. Internal verify PASS.
- **stop+resume fix = Option B IMPLEMENTED** in aid-stop.md + aid-run.md. Internal verify PASS (correct, complete, collision-free). 
  - aid-stop: drops session.* schema → reads real fsm-state.yaml fields; writes `mode: manual` to auto-mode-state.yaml ONLY (no collision with fsm-state `mode`=full/streamlined); logs via `aid-stage-log.sh log_event` (event `aid_stop`); display uses real fields.
  - aid-run: `--resume` 3 refs state.yaml → fsm-state.yaml.

## ⏳ WAITING ON PM RIGHT NOW
- Marek's **external review of the Option-B stop+resume implementation** (the copy-paste text was just given to him). On PASS → it stays; on issues → adjust.

## REMAINING — Wave 2 (each needs a PM decision first)
1. **auditor.md** — 3 conflicting severity scales (L50 dead 10/5/2/1, L539 live -15/-10/-5/-2, Memory-Health J 0-20×5) + TODO vs execution.yaml max_todo_count:0. → which scale to standardize on? (AID-056)
2. **planner.md** — FAIL, fictional script contract (wrong CLI, wrong EPIC table format, fabricated wave algorithm; only Kahn cycle-detection accurate). → how detailed a rewrite? (AID-045)
3. **aid-run.md rework** — fictional DONE→ERROR diagram edge, per-step branch vs single task/{epic_id}/main, merge epic/{id} wrong, parallel-as-current (parallel is disabled). → careful pass w/ PM. (part of A2)
4. **Dropped reflection learnings** — esp. #21 curator 4 auto-fix classes (homeless: role-cards has no curator card). → where to home? (AID-051)
5. **state.yaml → fsm-state.yaml migration** (D1) — coexist or fully migrate? (note: Option B already nudged --resume refs to fsm-state.yaml; the broader sweep is still open.)

## REMAINING — Wave 3 (design fixes, longer)
- **Provenance broken both ways** (over-fires on ±60s timing false-positive AND under-fires when `yq` missing → silent self-merge). Paired fix. (AID-046, the original P041 task)
- **qdrant → vulcan-memory migration** — DECIDED (vulcan, config-driven via integrations.yaml mcp_tool). Touches memory-mcp.md, project-scanner.md, pipeline.md + the deferred aid-research memory-interface bits (now moot — removed).

## REMAINING — Wave 4 (infra, code-change ceremony)
- **Promote skill-writing.md + command-writing.md** (in removed/.. no — in docs/plans/AID-audit-2026-06/, as `skill-writing-PROVISIONAL.md` + `command-writing-PROVISIONAL.md`) into plugins/aid-orchestrator/skills/ **+ build the sync-guard** (else Principle-#1 decoration). CHANGELOG + version bump. (AID-050)
- **Complete coverage** — map E87-E177 (~91 enforcements unmapped), audit 6 excluded files (setup/*, visual-companion, design-sections). (AID-052)
- **Fix the 19 failing tests** (test suite red on main).

## Key facts / decisions locked
- **qdrant→vulcan-memory:** decided (vulcan, config-driven). vulcan-memory is the live globally-wired memory (CC+Cweb+VULCAN); qdrant-brain legacy/unwired; CLAUDE.md forbids raw qdrant-*.
- **Principle #5** ("Enforcement without Instruction is Cargo Cult") added to AID-v3-principles.md as CANDIDATE (PM hasn't confirmed promotion to binding; doesn't affect fixes).
- **docs/plans/ is gitignored** (.gitignore:40) — all AID-v3 design docs + P041 audit docs are local-only by design. The 2 archived plugin files (aid-research.md, knowledge-base.yaml) ARE in git (via git mv) = restorable from history.
- Enforcement universe ≈ 177 (registry seed: `enforcement-registry.yaml`, 194 granular rows).

## NEXT ACTION after resume
1. If Marek returned an external verdict on Option-B stop+resume → record it; on PASS, that fix is locked (stays uncommitted until Wave-2 release).
2. Then ask Marek which Wave-2 item to tackle next (auditor scales / planner rewrite / aid-run rework / reflection homes / state migration), OR whether to release Wave 2 first.
3. Follow the working agreements above (propose → internal verify → give Marek external-verify text → apply).
