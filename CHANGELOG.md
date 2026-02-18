# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.2.0] — 2026-02-18

### Added
- `/aid-brainstorm` command — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
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
