# Active Work

**Last Updated:** 2026-02-17

---

## Current Focus

No active session. Session 4 completed, awaiting merge to main.

- **Branch:** `session/S-20260217-e7b3-worker-agents`
- **Commits:** `bd0208e`, `0f7872a`
- **Status:** Ready to merge

---

## Recent Work

### 2026-02-17 — Session 4: Worker Agents + Curator + Auditor + Scanner
- **Session:** [S-20260217-e7b3](sessions/completed/S-20260217-e7b3-worker-agents-curator-auditor-scanner.md)
- **Epic:** EPIC-ADO-0001 (Session 4 of 8)
- **Branch:** `session/S-20260217-e7b3-worker-agents`
- **Summary:** 12 new agents (9 role + 3 specialist), improvement-proposals skill, 9 playbook updates. Full agent layer for AID orchestrator.
- **Commits:** 2 | **Files:** 26 | **Lines:** +3,205
- **Key artifacts:**
  - `plugins/aid-orchestrator/skills/improvement-proposals.md` — Standard format, collection, dedup, backlog (320 lines)
  - `plugins/aid-orchestrator/agents/{architect,domain,backend,frontend,qa,security,observability,docs-writer,release}.md` — 9 role agents
  - `plugins/aid-orchestrator/agents/curator.md` — Post-session specialist (240 lines)
  - `plugins/aid-orchestrator/agents/auditor.md` — Post-Epic specialist (304 lines)
  - `plugins/aid-orchestrator/agents/project-scanner.md` — On-demand specialist (246 lines)
  - `plugin.json` — 18 agents, 16 commands, 7 skills

### 2026-02-16 — Session 3: Gates Engine + Retry
- **Session:** [S-20260216-c8d2](sessions/completed/S-20260216-c8d2-gates-engine-retry.md)
- **Epic:** EPIC-ADO-0001 (Session 3 of 8)
- **Branch:** `session/S-20260216-c8d2-gates-engine-retry`
- **Summary:** Gates engine (YAML parsing + execution), retry loop (max 3), gate-fixer agent, standalone /run-gates command, escalation protocol.
- **Key artifacts:**
  - `plugins/aid-orchestrator/skills/gates-engine.md` — Gates execution protocol
  - `plugins/aid-orchestrator/skills/retry-engine.md` — Retry loop + fix dispatch
  - `plugins/aid-orchestrator/agents/gate-fixer.md` — Specialized fix agent
  - `plugins/aid-orchestrator/commands/run-gates.md` — Standalone gates command

### 2026-02-16 — Session 2: EPIC Runner Commands + AID Commands
- **Session:** [S-20260216-f47a](sessions/completed/S-20260216-f47a-runtime-commands.md)
- **Epic:** EPIC-ADO-0001 (Session 2 of 8)
- **Branch:** `session/S-20260216-f47a-runtime-commands`
- **Summary:** 6 new commands implementing the runtime layer: `/plan-epic` (EPIC->Plan JSON), `/run-epic` (11-state Controller loop), `/run-step` (manual dispatch), `/epic-status` (pipeline status), `/aid-setup` (onboarding), `/aid-help` (self-knowledge). Plugin.json updated to 15 commands.
- **Files created:** 7 | **Lines:** +1,745 (commands)

### 2026-02-15 / 2026-02-16 — Session 1: Plugin Scaffold + Controller State Machine
- **Session:** [S-20260215-a1f0](sessions/completed/S-20260215-a1f0-foundation-controller.md)
- **Epic:** EPIC-ADO-0001 (Session 1 of 8)
- **Branch:** `session/S-20260215-a1f0-foundation-controller`
- **Summary:** Bootstrap session. Created `aid-orchestrator` marketplace plugin with full structure: 5 agents, 9 commands, 4 skills (incl. Controller State Machine), 9 playbooks, policies, templates. Rebranded ADO->AID with `.aid-o/` workspace structure. Created workflow catalog (13 WFs).
- **Commits:** 7 | **Files:** 45 | **Lines:** +6,133

---

## Next Steps

1. **Merge Session 4** to main
2. **Session 5:** Planner + Parallelization (auto plan generation, parallel dispatch, branches)
3. **Session 6:** Slack + Autonomous Run (MCP Slack, escalation, epic queue)
4. **Session 7:** E2E Test + Hardening (real EPIC, edge cases, documentation)
5. **Session 8:** Memory MCP (Qdrant vector DB, semantic search)

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
