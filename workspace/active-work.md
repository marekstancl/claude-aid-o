# Active Work

**Last Updated:** 2026-02-17

---

## Current Focus

No active session. Ready for Session 7.

---

## Recent Work

### 2026-02-17 — Session 6: Slack + Autonomní Běh
- **Session:** [S-20260217-d9c4](sessions/active/S-20260217-d9c4-slack-autonomous-run.md)
- **Epic:** EPIC-ADO-0001 (Session 6 of 8)
- **Branch:** `session/S-20260217-d9c4-slack-autonomous-run`
- **Summary:** Slack MCP integration protocol (7 message types, async PM communication), Epic Queue (auto-pickup, priority ordering), all PM touchpoints updated. Full autonomous pipeline.
- **Key artifacts:**
  - `plugins/aid-orchestrator/skills/slack-mcp.md` — 7 message types, MCP server interface, PM Communication Protocol, fallback, evidence logging
  - `plugins/aid-orchestrator/skills/epic-queue.md` — Queue format, operations, auto-pickup protocol, safety guards
  - `plugins/aid-orchestrator/commands/epic-queue.md` — /epic-queue CLI (list, add, remove, next, pause, resume, reorder)
  - `plugins/aid-orchestrator/defaults/policies/slack-config.yaml` — Default Slack config (enabled: false)
  - `plugin.json` — 18 agents, 17 commands, 12 skills

### 2026-02-17 — Session 5: Planner + Paralelizace + Multi-Perspective Analysis
- **Session:** [S-20260217-1ffa](sessions/active/S-20260217-1ffa-planner-parallelization.md)
- **Epic:** EPIC-ADO-0001 (Session 5 of 8)
- **Branch:** `session/S-20260217-1ffa-planner-parallelization`
- **Summary:** 3 new skills (planner, parallel-dispatch, analysis-merge), plan schema update (analysis_groups), 5 existing file updates. Full planning + parallelization layer.
- **Key artifacts:**
  - `plugins/aid-orchestrator/skills/planner.md` — Dependency graph, parallel groups, analysis groups, auto-triggers
  - `plugins/aid-orchestrator/skills/parallel-dispatch.md` — Branch strategy, concurrent dispatch, conflict detection
  - `plugins/aid-orchestrator/skills/analysis-merge.md` — 3 merge strategies (union, consensus, weighted)
  - `plugin.json` — 18 agents, 16 commands, 10 skills

### 2026-02-17 — Session 4: Worker Agents + Curator + Auditor + Scanner
- **Session:** [S-20260217-e7b3](sessions/completed/S-20260217-e7b3-worker-agents-curator-auditor-scanner.md)
- **Epic:** EPIC-ADO-0001 (Session 4 of 8)
- **Branch:** `session/S-20260217-e7b3-worker-agents`
- **Summary:** 12 new agents (9 role + 3 specialist), improvement-proposals skill, 9 playbook updates. Full agent layer for AID orchestrator.
- **Commits:** 2 | **Files:** 26 | **Lines:** +3,205

### 2026-02-16 — Session 3: Gates Engine + Retry
- **Session:** [S-20260216-c8d2](sessions/completed/S-20260216-c8d2-gates-engine-retry.md)
- **Epic:** EPIC-ADO-0001 (Session 3 of 8)
- **Summary:** Gates engine (YAML parsing + execution), retry loop (max 3), gate-fixer agent, standalone /run-gates command, escalation protocol.

### 2026-02-16 — Session 2: EPIC Runner Commands + AID Commands
- **Session:** [S-20260216-f47a](sessions/completed/S-20260216-f47a-runtime-commands.md)
- **Summary:** 6 new commands: `/plan-epic`, `/run-epic`, `/run-step`, `/epic-status`, `/aid-setup`, `/aid-help`.

### 2026-02-15 / 2026-02-16 — Session 1: Plugin Scaffold + Controller State Machine
- **Session:** [S-20260215-a1f0](sessions/completed/S-20260215-a1f0-foundation-controller.md)
- **Summary:** Bootstrap. `aid-orchestrator` plugin with full structure: 5 agents, 9 commands, 4 skills, 9 playbooks, policies, templates. ADO→AID rebrand. Workflow catalog (13 WFs).

---

## Next Steps

1. **Session 7:** E2E Test + Hardening (real EPIC, edge cases, documentation)
2. **Session 8:** Memory MCP (Qdrant vector DB, semantic search)

---

## Blockers

None.

---

## Key Decisions

| Date | Decision | Context |
|------|----------|---------|
| 2026-02-15 | Plugin-based architecture (marketplace.json) | Enables distribution as Claude Code plugin |
| 2026-02-15 | 11-state Controller FSM | Covers full EPIC lifecycle with retry + escalation |
| 2026-02-16 | ADO->AID rebrand | "AI Development aid" — clearer, more descriptive |
| 2026-02-16 | `.aid-o/` with numbered prefixes | `01-plans/`, `02-epics/`, `03-config/`, `04-engine/` |
| 2026-02-16 | 3 new agents: Curator, Auditor, Scanner | Post-session improvement, post-EPIC audit, onboarding |
| 2026-02-16 | MCP Qdrant for memory | Long-term memory via vector DB + file-based active memory |
| 2026-02-16 | Commands = markdown prompt engineering | Not executable code — Claude reads and follows instructions |
| 2026-02-16 | Two gates systems coexist | C.I.C.E.R.O. (pre-commit) + AID Gates Engine (post-EPIC-steps) |
| 2026-02-17 | improvement_notes as mandatory agent output | Every role agent outputs improvement_notes (can be empty list) |
| 2026-02-17 | IMP-{NNN} backlog ID schema | Auto-incrementing, never reused, Curator manages |
| 2026-02-17 | analysis_groups vs parallel_groups | parallel = different work concurrent; analysis = same target, different perspectives |
