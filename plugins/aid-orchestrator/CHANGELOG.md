# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.5.0] — 2026-02-22

### Added
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` (660 lines) with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"

## [0.4.1] — 2026-02-20

### Added
- **`/aid-init` upgrade mode** — detects existing workspace, compares installed vs. plugin version, classifies files as NEW / UPGRADABLE / UNCHANGED / CUSTOM / PROTECTED, asks PM before updating
- **Config manifest** — `.aid-o/03-config/.aid-manifest.yaml` tracks installed plugin version and md5 checksums of all config files; enables safe detection of PM customizations
- **Dynamic defaults scanning** — `/aid-init` scans `defaults/` directories instead of hardcoded file list; new files in future versions are automatically included
- **`source_plan` in plan schema** — `defaults/templates/plan.schema.json` now includes the `source_plan` field for Variant B pipeline

### Changed
- **CHANGELOG format** — standardized all entries to `**Bold Name** — description` format; root and plugin CHANGELOGs are now identical
- **CLAUDE.md release protocol** — added CHANGELOG format standard, README Roadmap update rules, and 10-step release workflow
- **`/aid-init` description** — updated in `aid-help.md` to reflect upgrade capabilities

## [0.4.0] — 2026-02-20

### Added
- **Zero Detail Loss Pipeline (Variant B)** — EPIC references source plan via `plan_ref`; all pipeline stages (plan.json, session, agent dispatch) read both EPIC and source plan; agents receive `## Source Plan — Implementation Detail` sections
- **Wave-based execution model** — planner groups steps by DAG level into waves (max 4 per wave) for parallel execution; replaces flat parallel group detection
- **Step decomposition** — layer-based splitting of monolithic steps (data → schema → API → test) to enable cross-domain parallelism; supports dev, docs, and infra decomposition types
- **Critical path analysis** — opt-in for 7+ step EPICs; computes critical path ratio, applies 5 relaxation rules (R1–R5) to shorten it; PM can reject individual relaxations at PLAN_REVIEW
- **Parallelism-first optimization** — 5-priority strategy (parallelism > wave density > session compactness > quality > efficiency); plan quality metrics in `optimization_metrics`; validation rules V-20–V-23
- **`/plan-epic` accepts Plan files** — 3-tier format detection (frontmatter → header → section fingerprinting); auto-generates EPIC from Plan using EPIC Subagent Template
- **`/aid-brainstorm` inline execution** — Step 8b offers to generate Plan JSON + Session immediately after EPIC draft; Step 9 split into 9a (standard handoff) / 9b (full pipeline handoff)
- **Wave-based session boundaries** — sessions are contiguous sequences of waves; never split by domain or inside a wave
- **Shorthand commands** — all 18 commands have `user_invocable: true` frontmatter enabling `/aid-setup` instead of `/aid-orchestrator:aid-setup`
- **Setup followup** — after "All recommended", `/aid-setup` now offers additional options (CLAUDE.md, Slack, auto-detected MCPs)
- **Selective `.aid-o/` gitignore** — plans, EPICs, and config are versioned; engine artifacts (sessions, evidence) are ignored
- **Centralized Qdrant storage** — `~/.local/share/aid-orchestrator/qdrant-data` with `--scope user` for global MCP; migration check for old paths

### Changed
- **EPIC template** — typed artifacts (`endpoint:`, `model:`, `component:`), `plan_ref` enforcement, Hints section, Scope with specific file paths
- **EPIC Subagent Template** — frontmatter instructions, plan task ID preservation in steps, Variant B zero detail loss instruction
- **Planner input validation** — REQUIRED/RECOMMENDED checks with typed artifact inference
- **PLAN_REVIEW** — rich plan summary with wave execution plan, optimization metrics, session breakdown
- **EXECUTING state** — agent dispatch enriched with source plan sections
- **Plan generation flow** — 13-step procedure with decomposition (2.2), wave assembly (6), CPA (6.1), session boundaries (11)

## [0.3.0] — 2026-02-19

### Added
- **Execution Summary block** — mandatory in all agent outputs with timing, self-assessment, and Qdrant storage
- **Per-agent metrics** — step duration, complexity self-report, bottleneck flags stored to Qdrant
- **Cost optimization skill** — 4 axes: model selection, file scoping, dispatch prompt trimming, token tracking
- **EPIC completion summary** — 5 next-step options presented to PM at DONE state
- **Auto-archive** — multi-EPIC and multi-session counter awareness for session and EPIC files
- **Multi-session flow** — planner optimization engine for EPICs with 7+ steps
- **Diff patches** — `diff.patch` generation for every file-modifying step, saved to evidence store
- **Curator auto-invocation** — mandatory synchronous step in POST_PROCESSING
- **Chat-first `/aid-setup`** — detailed option presentation and guided configuration
- **Post-setup guidance** — `/aid-brainstorm` recommendation after onboarding
- **Playwright E2E agent** — optional parallel step, auto-added when frontend detected
- **Application type classification** — 11 types in project scanner (web-app, api-service, cli-tool, desktop-app, mobile-app, library, plugin, script, monorepo, erp-module, infrastructure)
- **Auto-scaffold** — generates starter files for uninitialized projects before EPIC execution
- **Cross-project knowledge** — Qdrant with `project_name` metadata tagging for multi-project memory
- **Backlog categorization** — by type (bug, enhancement, tech-debt, security, docs) and source agent
- **`/aid-analytics`** — orchestration performance analysis command and skill
- **Permission presets** — dual-write system keeping `.claude/settings.json` + `.aid-o` policies in sync
- **Git branch integration** — one branch per EPIC session, auto-create and auto-merge
- **Pre-Output Quality Check** — in all code-producing playbooks (ruff lint/format, debug artifact removal, import verification)

### Fixed
- **DONE state** — now writes lessons to `lessons-learned.md`, updates session status to `completed`, writes commands to `command-history.md`, writes final `stage_log` entry with `result: success`
- **Gate reconciliation** — `plan.json` gates now reconciled with `gates.yaml` definitions
- **Qdrant isolation** — writes now include `project_name` metadata for cross-project isolation
- **Slack MCP** — onboarding corrected to use `@anthropic/slack-mcp` package with proper scopes

### Changed
- **Agent model assignments** — QA, Security, Docs agents use Sonnet; utility agents use Haiku
- **Dispatch prompts** — trimmed to deps-only context, EPIC summary, and playbook reference
- **`/aid-help` examples** — updated with full-stack development examples
- **Memory search** — `top_k` reduced from 5 to 3 for relevance and cost optimization
- **Git Discipline** — section added to all 9 role playbooks

## [0.2.0] — 2026-02-18

### Added
- **`/aid-brainstorm`** — 9-step interactive brainstorming flow (context → questions → approaches → design → sections → approval → document → EPIC draft → handoff)
- **Brainstorming skill** — process rules, key principles, EPIC subagent prompt template
- **MCP server onboarding** — Qdrant local (no Docker), Slack opt-in, auto-detect, custom
- **Permission presets** — Safe / Recommended / Advanced in `/aid-setup`
- **Document language** — `language.yaml` configuration with ISO 639-1, default EN
- **Parallel isolation strategy** — `dispatch-strategy.yaml` with worktrees / branches / sequential
- **Git worktree support** — creation and cleanup logic for parallel agent dispatch
- **Qdrant orchestration logging** — dispatch and completion events with graceful JSONL fallback
- **Enriched `final_report.md`** — generation from Qdrant data
- **Lessons learned** — auto-collection and storage in Qdrant at EPIC completion
- **CLAUDE.md marker merge** — `<!-- AID-O START/END -->` markers in `/aid-init`
- **Interactive examples** — `/aid-help examples` with 3 project prompts

### Changed
- **`/aid-setup`** — includes 4 new configuration steps (MCP, permissions, language, isolation)
- **`/aid-init`** — copies `dispatch-strategy.yaml` and `language.yaml` to workspace
- **LLM cost estimates** — conditioned on `billing_mode: api` (hidden for subscription users)

### Removed
- **`examples/bookmark-manager/`** — replaced by interactive `/aid-brainstorm` prompts

## [0.1.0] — 2026-02-16

### Added
- **Initial release** — Controller + Workers architecture for Claude Code
- **17 slash commands** — `/aid-init`, `/aid-setup`, `/run-epic`, `/plan-epic`, etc.
- **18 agents** — 9 role + 3 specialist + 6 utility
- **13 skills** — epic orchestration, planner, gates engine, parallel dispatch, etc.
- **11 role playbooks** — customizable per project
- **Quality gates** — auto-retry (3x) and PM escalation
- **Slack MCP integration** — with chat fallback
- **Qdrant vector memory** — optional, with file-based fallback
- **EPIC queue** — autonomous sequential execution
- **Evidence trail** — `stage_log.jsonl`, gate reports, agent outputs
