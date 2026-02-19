# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.3.0] — 2026-02-19

### Added
- Mandatory Execution Summary block in all agent outputs with timing, self-assessment, and Qdrant storage (Task 6)
- Per-agent metrics: step duration, complexity self-report, bottleneck flags stored to Qdrant (Task 6)
- Cost optimization skill with 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking (Task 7)
- EPIC completion summary with 5 next-step options presented to PM at DONE state (Task 8)
- Auto-archive with multi-EPIC and multi-session counter awareness for session and EPIC files (Task 9)
- Multi-session flow with Planner optimization engine for EPICs with 7+ steps (Task 10)
- `diff.patch` generation for every file-modifying step, saved to evidence store (Task 11)
- Curator auto-invocation as mandatory synchronous step in POST_PROCESSING (Task 13)
- Chat-first `/aid-setup` flow with detailed option presentation and guided configuration (Task 14)
- Post-setup next-step guidance with `/aid-brainstorm` recommendation after onboarding (Task 16)
- Playwright E2E agent as optional parallel step, auto-added when frontend detected (Task 18)
- 11 application type classifications in project scanner (Task 20)
- Auto-scaffold step for uninitialized projects (Task 21)
- Cross-project knowledge via Qdrant with `project_name` metadata tagging (Task 22)
- Backlog categorization by type and source agent (Task 23)
- Analytics skill and `/aid-analytics` command for orchestration performance analysis (Task 26)
- Permission presets with dual-write system — `.claude/settings.json` + `.aid-o` policies kept in sync (Task 2)
- Git branch integration: one branch per EPIC session, auto-create and auto-merge (Task 3)
- Pre-Output Quality Check in all code-producing playbooks (Task 5)

### Fixed
- DONE state now writes lessons to `lessons-learned.md` (PROP-001)
- DONE state now updates session status to `completed` (PROP-002)
- DONE state now writes commands to `command-history.md` (PROP-003)
- DONE state now writes final `stage_log` entry with `result: success` (PROP-010)
- `plan.json` gates now reconciled with `gates.yaml` definitions (PROP-005)
- Qdrant writes now include `project_name` metadata for cross-project isolation (PROP-001)
- Slack MCP onboarding corrected: uses `@anthropic/slack-mcp` package with proper scopes (Task 17)

### Changed
- Agent model assignments optimized: QA, Security, Docs agents use Sonnet; Utility agents use Haiku (Task 7)
- Dispatch prompts trimmed to deps-only context, EPIC summary, and playbook reference (Task 7)
- `/aid-help` examples topic updated with full-stack development examples (Task 19)
- Memory search `top_k` reduced from 5 to 3 for relevance and cost optimization (Task 7)
- Git Discipline section added to all 9 role playbooks (Task 3)

## [0.2.0] — 2026-02-18

### Added
- `/aid-brainstorm` command — 9-step interactive brainstorming flow (context → questions → approaches → design → plan)
- `skills/brainstorming.md` — process rules, key principles, EPIC subagent prompt template
- MCP server onboarding in `/aid-setup` — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- Permission presets (Safe / Recommended / Advanced) in `/aid-setup`
- Document language configuration (`language.yaml`) — ISO 639-1, default EN
- Parallel isolation strategy selection (`dispatch-strategy.yaml`) — worktrees / branches / sequential
- Git worktree creation/cleanup logic for parallel agent dispatch
- Qdrant orchestration logging — dispatch and completion events with graceful JSONL fallback
- Enriched `final_report.md` generation from Qdrant data
- Lessons learned auto-collection and storage in Qdrant at EPIC completion
- CLAUDE.md marker-based merge in `/aid-init` (`<!-- AID-O START/END -->`)
- Interactive examples topic in `/aid-help` (3 project prompts replacing static bookmark-manager)

### Changed
- `/aid-setup` now includes 4 new configuration steps (MCP, permissions, language, isolation)
- `/aid-init` copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- LLM cost estimates conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- `examples/bookmark-manager/` directory (replaced by interactive `/aid-brainstorm` prompts)

## [0.1.0] — 2026-02-16

### Added
- Initial release — Controller + Workers architecture for Claude Code
- 17 slash commands (`/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.)
- 18 agents (9 role + 3 specialist + 6 utility)
- 13 skills (epic orchestration, planner, gates engine, parallel dispatch, etc.)
- 11 role playbooks (customizable per project)
- Quality gates with auto-retry (3x) and PM escalation
- Slack MCP integration with chat fallback
- Qdrant vector memory (optional)
- EPIC queue for autonomous sequential execution
- Evidence trail (stage_log.jsonl, gate reports, agent outputs)
