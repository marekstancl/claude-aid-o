# Active Work

**Last Updated:** 2026-02-16

---

## Current Focus

**Session 3: Gates Engine + Retry** — EPIC-ADO-0001 (Session 3 of 8)
- **Session:** [S-20260216-c8d2](sessions/active/S-20260216-c8d2-gates-engine-retry.md)
- **Branch:** `session/S-20260216-c8d2-gates-engine-retry`
- **Goal:** Gates engine (gates.yaml parsing + execution), pass/fail reports, retry loop (max 3), gate-fixer agent, escalation protocol.
- **Deliverables:**
  - `skills/gates-engine.md` — Gates execution protocol
  - `skills/retry-engine.md` — Retry loop + fix dispatch
  - `agents/gate-fixer.md` — Specialized fix agent
  - `commands/run-gates.md` — Standalone gates command
  - Update `commands/run-epic.md` — GATES + GATE_RETRY concrete refs
  - Update `plugin.json` — new command + agent + 2 skills

---

## Recent Work

### 2026-02-16 — Session 2: EPIC Runner Commands + AID Commands
- **Session:** [S-20260216-f47a](sessions/completed/S-20260216-f47a-runtime-commands.md)
- **Epic:** EPIC-ADO-0001 (Session 2 of 8)
- **Branch:** `session/S-20260216-f47a-runtime-commands`
- **Summary:** 6 new commands implementing the runtime layer: `/plan-epic` (EPIC→Plan JSON), `/run-epic` (11-state Controller loop), `/run-step` (manual dispatch), `/epic-status` (pipeline status), `/aid-setup` (onboarding), `/aid-help` (self-knowledge). Plugin.json updated to 15 commands.
- **Files created:** 7 | **Lines:** +1,745 (commands)
- **Key artifacts:**
  - `plugins/aid-orchestrator/commands/run-epic.md` — Controller state machine loop (449 lines)
  - `plugins/aid-orchestrator/commands/plan-epic.md` — EPIC parser + Plan JSON generator (216 lines)
  - `plugins/aid-orchestrator/commands/aid-setup.md` — Tech stack detection + onboarding (269 lines)
  - `plugins/aid-orchestrator/commands/aid-help.md` — Self-knowledge, 7 topics (493 lines)

### 2026-02-15 / 2026-02-16 — Session 1: Plugin Scaffold + Controller State Machine
- **Session:** [S-20260215-a1f0](sessions/completed/S-20260215-a1f0-foundation-controller.md)
- **Epic:** EPIC-ADO-0001 (Session 1 of 8)
- **Branch:** `session/S-20260215-a1f0-foundation-controller`
- **Summary:** Bootstrap session. Created `aid-orchestrator` marketplace plugin with full structure: 5 agents, 9 commands, 4 skills (incl. Controller State Machine), 9 playbooks, policies, templates. Rebranded ADO→AID with `.aid-o/` workspace structure. Created workflow catalog (13 WFs).
- **Commits:** 7 | **Files:** 45 | **Lines:** +6,133
- **Key artifacts:**
  - `plugins/aid-orchestrator/skills/epic-orchestration.md` — Controller (11 states)
  - `plugins/aid-orchestrator/commands/aid-init.md` — `.aid-o/` workspace scaffold
  - `plugins/aid-orchestrator/defaults/policies/decision-policies.yaml` — autonomy rules
  - `workspace/workflow/WORKFLOWS.md` — 13 workflows, Mermaid, RACI

---

## Next Steps

1. **Session 3:** Gates Engine + Retry ← **ACTIVE**
2. **Session 4:** Worker Agents + Curator + Auditor + Scanner (9 role agents + 3 new specialists)
3. **Session 5:** Planner + Parallelization (auto plan generation, parallel dispatch, branches)
4. **Session 6:** Slack + Autonomous Run (MCP Slack, escalation, epic queue)
5. **Session 7:** E2E Test + Hardening (real EPIC, edge cases, documentation)
6. **Session 8:** Memory MCP (Qdrant vector DB, semantic search)

---

## Blockers

None.

---

## Key Decisions

| Date | Decision | Context |
|------|----------|---------|
| 2026-02-15 | Plugin-based architecture (marketplace.json) | Enables distribution as Claude Code plugin |
| 2026-02-15 | 11-state Controller FSM | Covers full EPIC lifecycle with retry + escalation |
| 2026-02-16 | ADO→AID rebrand | "AI Development aid" — clearer, more descriptive |
| 2026-02-16 | `.aid-o/` with numbered prefixes | `01-plans/`, `02-epics/`, `03-config/`, `04-engine/` |
| 2026-02-16 | 3 new agents: Curator, Auditor, Scanner | Post-session improvement, post-EPIC audit, onboarding |
| 2026-02-16 | MCP Qdrant for memory | Long-term memory via vector DB + file-based active memory |
| 2026-02-16 | Commands = markdown prompt engineering | Not executable code — Claude reads and follows instructions |
| 2026-02-16 | Two gates systems coexist | C.I.C.E.R.O. (pre-commit) + AID Gates Engine (post-EPIC-steps) |
