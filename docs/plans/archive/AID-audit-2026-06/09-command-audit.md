---
audit: P041
phase: 3b (command audit — PM-requested, two rounds)
artifact: command-audit
status: draft-for-PM
generated: 2026-06-01
covers: 10 command files × 4 dimensions, two rounds (audit + adversarial re-audit)
criteria: skill-writing-PROVISIONAL.md (adapted) + 00-canonical-learnings.md
---

# P041 Phase 3b — Command Audit (10 files, two rounds)

Commands were outside the original Phase-3 scope (the L2 critic flagged this as the
biggest coverage hole). PM requested a dedicated two-round audit. Round 1 = 10
parallel per-command audits; Round 2 = 3 adversarial re-audit agents (find missed +
refute wrong).

## Headline

**Commands are in WORSE shape than skills/agents.** Beyond doc hygiene, the round
exposed real **functional defects**: aid-help's Level detection always returns 0,
aid-stop's resume/progress-save guarantee is broken, and aid-research's happy path
silently reads template config + cites menu options that don't exist. The same
doc-vs-code drift that made planner.md a FAIL recurs across the command surface.

## Per-command findings (rounds merged)

### aid-run.md (388) — PASS_WITH_NOTES (NOT fictional — matches aid-fsm.sh)
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :137-141 | P1 | FSM diagram invents a `DONE→ERROR` edge; DONE is terminal (no outgoing edges in VALID_TRANSITIONS); real ERROR edges are READY/EXECUTE/GATES/ESCALATION |
| 3a | :181-185 vs :63 | P1 | EXECUTE step 4 describes live parallel dispatch, but rule #15 + orchestration.yaml max_parallel:1 + pipeline.md:566 say sequential-only (parallel disabled). Presents disabled feature as current |
| 3a | :314 | P1 | Merge step `git merge epic/{id}`; no `epic/{id}` branch exists — FSM uses single `task/{epic_id}/main` |
| 3a | :184 | HIGH | Per-step branch `task/{task_id}/step_N` contradicts single-branch model (would trip fsm_branch_mismatch) |
| 3a | :186 vs :272 | P2 | Evidence path id drift: `{task_id}` vs `{epic_id}` (FSM uses epic_id) |
| 3a | :186 | P2 | `steps/` subdir; FSM reads flat `step-*-verify.md` (maxdepth 1); steps/ is the disabled parallel layout |
| 3d | :198-204 | HIGH | Learning #16: CP3 stated as workflow step, not as the hard EXECUTE→GATES precondition it is; no consolidated prereq checklist |
| 3d | state.yaml refs | MED | #16 state.yaml vs fsm-state.yaml naming reproduced |
| 3b | :351-385 | MED | `--streamlined` block duplicates aid-fsm internals (Forbidden Pattern #3); accurate but too deep for a command |
| 3a | :366 | P3 | streamlined check reads `evidence_dir/gates_report.json` but GATES/CP4 read `gates/gates_report.json` — script path inconsistency surfaced |

### aid-plan.md (391) — PASS_WITH_NOTES
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a/3d | :107-128, :297-318 | P1 | CP1 uses raw `aid-stage-log.sh log_event` instead of mandated `aid-emit-dispatch.sh start/complete` wrapper (which supports cp1) → bypasses pending-dispatches ledger + agent_id enforcement |
| 3a | :249, :287 | HIGH | Gate-count stale: says "24 checks" vs plan-writing.md's "27" |
| 3a | :17 vs :55,253 | P2 | Internal contradiction: L17 "8-step" vs L55+banners "9-step" |
| 3c | :370 | MED | Version-stamped heading `### Streamlined Mode Advisory (P040, v2.25.0+)` |
| 3a | :130,320 | LOW | Re-derives `<dispatch-focus>` convention pipeline.md owns |

### aid-init.md (412) — PASS_WITH_NOTES
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :297 | HIGH | pre-push "same markers as pre-commit" WRONG — hooks use different markers (HOOK-START vs PREPUSH-START); LLM searching pre-commit marker in pre-push appends duplicates each run |
| 3a/3d | :3,16,35,403 | HIGH | File-count contradiction restated 4×: "10-file" (L3) vs "11 total" vs "6+5=11" — and the 6+5 breakdown is itself wrong (4 empty dirs, not 5; config/ duplicated L21/L30) |
| 3a | :20 vs :37-39 | P3 | Tree shows `.aid-o/.gitignore` as created; actually appended to project-root .gitignore |
| 3a | :291 | MED | Hook blocks "DONE/review"; actual blocks DONE && done_phase != release (any non-release) |
| 3c | :412 | MED | Stale footer 2026-05-13 vs documented dispatch_mode/severity content |

### aid-do.md (183) — PASS_WITH_NOTES (fix-loop matches pipeline §8)
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :53 vs pipeline.md:1016 | MED | Execution-model contradiction: "Implement directly" (inline) vs pipeline §8 "Dispatch single agent (sonnet)" |
| 3a | :101-138 vs pipeline.md:1015 | HIGH | Never mentions `.aid-o/logs/aid-do-log.jsonl` (aid_do_start/complete) that pipeline §8 mandates |
| 3a | :80-81 | MED | Prefilter emits SKIP/RUN/FAIL; command names only skip/FAIL/dispatch (RUN unnamed) |
| 3c | :183 | HIGH | Stale date 2026-03-19 predates CP6/pre-filter content |
| 3a | :117 vs pipeline:1023 | LOW | Field drift `duration_s` vs `duration_seconds` |
| 3a | :30 | LOW | Unbalanced inline-code backtick |

### aid-research.md (249) — PASS_WITH_NOTES (no raw qdrant-* → no CLAUDE.md violation)
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :76 | HIGH | Reads `defaults/integrations.yaml` (template, `enabled:false`) for runtime config; every other reader uses `.aid-o/config/integrations.yaml` → reads template defaults, not project config |
| 3a | :29-30 | HIGH | Cites "/aid-setup Option 6a/6b" — no such options exist (dead instruction) |
| 3a | :114,116,196 | MED | Invokes `knowledge_research()`/`memory_store()`/`run_quality_gates()` "per memory-mcp.md" — none exist there (fabricated contract) |
| 3a | :128,184 | MED | "4 quality gates" are a fabricated gate set (no source in memory-mcp.md or integrations.yaml; reframed from "contradiction") |
| 3c | :114,233 + integrations.yaml:82 | HIGH | Dead-ref chain to nonexistent `skills/knowledge-acquisition.md` (cited by shipped default config) |
| 3a | :204,208 | MED | TTL/dedup hardcoded; integrations.yaml owns them |
| 3c | :249 | MED | Stale date 2026-03-19 |

### aid-status.md (184) — PASS_WITH_NOTES
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a/3d | :57,69-72,160,180 | HIGH | Documents legacy `state.yaml` as canonical; production is `fsm-state.yaml` (#16) |
| 3a | :106-118,126,153 | HIGH | Queue schema drift: `task_id`/`done`/`fail` vs script `epic_id`/`completed`/`failed`; eligibility tags computed nowhere |
| 3a | :128-138 | HIGH | pause/resume/reorder documented as write subcommands but NO script implements them (Principle #1: feature without enforcement) |
| 3a | :50,109 | MED | "Auto-pickup: active" display has no backing store/toggle |
| 3c | :184 | MED | Stale date 2026-03-03 |

### aid-stop.md (202) — PASS_WITH_NOTES (most severe functional break)
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :57-61 | HIGH | Reads `session.current_epic_id/...` schema — exists in NO state file (FSM has flat current_step/state/mode) |
| 3a | :38-47 | HIGH | Reads/writes `auto-mode-state.yaml` — NO script writes it; only LLM-prose in pipeline §9 |
| 3a | :146 vs aid-run.md:347 | HIGH | `--resume` reads `state.yaml`, NOT auto-mode-state.yaml → **progress-save/resume guarantee BROKEN** (saves where resume never looks) |
| 3a | :109-122 | MED | Timeline JSON uses wrong keys (`timestamp`/`state`/`action` vs real `ts`/`event`) → jq consumers skip the stop event |
| 3a | :41,51-79 | MED | `mode: paused` never emitted by FSM; Step2 paused→Step3 manual window vacuous |
| 3c | :202 | MED | Stale date 2026-03-19 |

### aid-setup.md (91) — PASS_WITH_NOTES
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :80 | HIGH | Lists presets "autonomous, aspirin, steroids"; actual = `autonomous \| custom` (aspirin/steroids removed) |
| 3d | (whole) + integrations.md:29 | MED | NR-11 staleness: setup chain references skills showing removed MCP servers (shared-docker/slack/playwright). NOTE: no runtime "guard" exists — the defect is staleness, not a missing guard (round-2 correction) |
| 3c | :91 | MED | Stale date 2026-03-04 |

### aid-help.md (226) — PASS_WITH_NOTES (functional bug)
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a/3d | :29 | HIGH | **Level detection BROKEN:** greps `evidence/*/*/state.yaml` for `state: DONE`, but production writes `fsm-state.yaml` → count always 0 → every user mis-detected as Level 0 |
| 3a | :35-48,98-107 | HIGH | `/aid-research` (real command) appears NOWHERE in aid-help (violates its own "all commands surfaced" rule) |
| 3a | :139-143 | MED | `/aid-run` topic omits `--streamlined` flag |
| 3a | :133-143,181-190 | MED | FSM diagram omits ERROR transitions + done_phase review→release sub-phase |
| 3c | :226 | MED | Stale date 2026-03-22 |

### aid-audit.md (29) — PASS_WITH_NOTES (thin delegating shell)
| dim | file:line | pri | finding |
|-----|-----------|-----|---------|
| 3a | :14-21 | HIGH | Menu lists 8 audit types; auditor.md defines 10 categories (A-J) — PM gets wrong mental model |
| 3a | :25 | HIGH | Severity "Critical/Warning/Suggestion" contradicts auditor.md Critical/High/Medium/Low |
| 3c | :29 | MED | Stale date 2026-03-04 (oldest); predates A-J expansion |
| 3a | :9 | LOW | Doesn't state auditor is a post-EPIC DONE-state agent (invocation semantics) |

## Round-2 refutations (corrected first-round findings — prevented bad fixes)

| first-round claim | verdict | correction |
|--------------------|---------|------------|
| aid-audit "evidence path omits {run_id}" | **REFUTED** | auditor.md uses `evidence/{epic_id}/audit-report.md` (no run_id) — the command's path is CORRECT |
| aid-stop "#7/#12 streamlined telemetry only fires on auto/paused" | **REFUTED** | Garbled — describes a non-existent mechanism; streamlined_abandoned is an unrelated done-advance guard |
| aid-setup "NR-11 guard not propagated" | **WRONG PREMISE** | No runtime guard exists to propagate; real defect is staleness (N4) |
| aid-research "4 gates CONTRADICTS memory-mcp §8" | **REFRAME** | Different subsystem; reframe to "fabricated gate set with no source definition" |
| aid-plan "9-step vs brainstorming 7-step" | **REFUTED** | brainstorming.md is also 9-step; real defect is aid-plan L17 "8-step" intra-file |
| aid-run "CP3 not stated as precondition" | **PARTIAL** | It IS stated (L198-204) but as a workflow step, not a hard-fail precondition — clarity gap, not absence |

## Cross-command patterns (systemic)

1. **state.yaml vs fsm-state.yaml drift (canonical learning #16, never propagated to commands)** — aid-run, aid-status, aid-stop, aid-help. In aid-help it's a **functional bug** (Level detection always 0). The reflection corpus flagged this naming friction repeatedly; it reached aid-fsm.sh but not the command layer.
2. **Doc-vs-code fabrication (same class as planner.md FAIL)** — aid-stop `session.*`/`auto-mode-state.yaml` (no writer), aid-research fabricated functions + dead `/aid-setup Option 6a/6b` + reads template not live config, aid-run invented DONE→ERROR edge. Commands invent contracts the scripts don't honor.
3. **Unenforced documented capabilities (Principle #1)** — aid-status pause/resume/reorder (no script), auto-mode-state `mode` field (written by nothing). Features documented, never built.
4. **Stale dates everywhere** — all 10 commands stale (2026-03-xx) despite P040 content through 2026-05-31.
5. **Cross-file count/schema drift** — aid-init file count, aid-plan gate count, aid-audit menu, queue schema, qdrant tool naming.
6. **Dispatch-convention divergence** — aid-plan CP1 uses old aid-stage-log instead of the aid-emit-dispatch wrapper every other CP uses.

## Verdict
10/10 PASS_WITH_NOTES, but with **3 real functional defects** (aid-help Level detection, aid-stop resume, aid-research config-path/dead-options) that are worse than anything in the skill/agent corpus except planner.md. The command surface drifted hardest because it had no authoring standard and was never previously audited. **This is the strongest argument for `command-writing.md`** (the base standard, built next).
