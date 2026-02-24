# Changelog

All notable changes to the AID Orchestrator plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.9.1] — 2026-02-24

### Added

- **Initial Analysis Phase** (`skills/brainstorming.md`) — mandatory structured analysis before questioning; 8-rule protocol with 4 required elements (topic understanding, key dimensions, potential challenges, clarification preview); PM confirmation gate; trivial topic escape hatch
- **Release Sub-Phase** (`skills/epic-orchestration.md`) — version bump detection and execution in DONE state; reads `release-policy.yaml` for CHANGELOG pattern, version files, multi-phase deferral; supports `json_field` and `regex` update strategies, git tagging, GitHub releases
- **Release policy config** (`defaults/policies/release-policy.yaml`) — configurable versioning: CHANGELOG header pattern, version file locations, update methods, multi-phase plan detection, git tag and GitHub release controls

### Changed

- **Questioning Protocol strengthened** (`skills/brainstorming.md`) — Rule 2 upgraded from "Prefer MULTIPLE CHOICE" to "ALWAYS use MULTIPLE CHOICE with recommendation"; added Rules 10-11 for structured directional options and contrastive reasoning
- **MUST Rules expanded** (`skills/brainstorming.md`) — 3 new entries (15-17): mandatory analysis before questions, options at every decision point, reasoning for alternatives
- **Command flow updated** (`commands/aid-brainstorm.md`) — 10-step → 11-step flow; new Step 2 (Analysis) inserted between Context and Questions; all subsequent steps renumbered with cross-references updated
- **DONE state enhanced** (`commands/aid-run-epic.md`) — Release Sub-Phase integrated before branch merge; DONE action items reordered (run file update → release → merge → archive)

### Fixed

- **Example EPIC lookup type filter** (`skills/brainstorming.md`) — changed from `"example_epic"` to `"example"` to match actual frontmatter in 19 example files
- **Example EPIC lookup scan** (`skills/brainstorming.md`) — changed from flat `defaults/examples/` to recursive `defaults/examples/**/*.md` to find files in subdirectories

## [0.9.0] — 2026-02-24

### Added

- **Plan-ref injection** (`skills/epic-orchestration.md`) — dispatch template now includes `plan_ref` with Source Plan Integration protocol: 3-strategy matching cascade (keyword → heading → sequential), 3000-line truncation guard, `<plan_context>` block in agent prompts
- **Sequential ID generation** (`skills/epic-orchestration.md`) — ID Format Specification for Plans (`P{NNN}`), EPICs (`E-{NNN}-{epic_run}_{plan_step}`), and Runs (`R-{NNN}-{epic_run}_{plan_step}-{run_seq}`); Counter File protocol (`counter.yaml`); atomic increment rules
- **Evidence Incomplete detection** (`agents/auditor.md` section F.5) — `evidence_incomplete` finding type with `-3` deduction per missing mandatory file; only checks completed steps
- **Mandatory Evidence Write Checklist** (`skills/epic-orchestration.md`) — Step Evidence File Types table listing mandatory vs optional evidence files per step

### Changed

- **SESSION → RUN terminology** — renamed across 45+ files: `session` → `run`, `session-management.md` → `run-management.md`, `session-validator.md` → `run-validator.md`, 4 template files renamed; `sessions/` directory → `runs/`
- **Flat evidence structure** (`commands/aid-run-epic.md`, `skills/epic-orchestration.md`) — removed 5 empty subdirectory creation (analysis/, discovered_issues/, parallel_groups/, prompts/, reviews/); evidence now written directly to `steps/step_{N}_{role}/`
- **Budget references removed** — removed budget estimation lines from `defaults/templates/epic.md`, `defaults/templates/epic-example.md`, `skills/brainstorming.md`
- **Auditor check #12 path updated** (`agents/auditor.md`) — `evidence/discovered_issues/` → `steps/step_{N}_{role}/discovered_issues.md`
- **Analysis-merge evidence paths** (`skills/analysis-merge.md`) — `evidence/{epic_id}/{run_id}/analysis/` → `steps/step_{target}_{role}/`

## [0.8.2] — 2026-02-23

### Fixed

- **Czech-language content removed** — translated all Czech text to English in `agents/lessons-extractor.md`, `skills/session-management.md`, `skills/agent-core.md`
- **Broken skill reference in `aid-epic-queue.md`** — `skills/aid-epic-queue.md` → `skills/epic-queue.md`, `aid-epic-queue.yaml` → `epic-queue.yaml`
- **Stale `workspace/workflow/` paths** — 12 legacy path references replaced with `.aid-o/` equivalents in `skills/session-management.md`
- **Stale command prefixes** — `/run-epic` → `/aid-run-epic`, `/plan-epic` → `/aid-plan-epic` in `skills/retry-engine.md`, `skills/planner.md`, `defaults/templates/epic-example.md`
- **Version mismatches** — header/footer versions aligned to 0.8.2 in `session-management.md`, `epic-orchestration.md`, `retry-engine.md`, `planner.md`, `agent-core.md`
- **Hardcoded Slack channel ID** — replaced `C0AFP2GP459` with `YOUR_CHANNEL_ID` placeholder in `commands/aid-setup.md`
- **Plugin README version** — updated from 0.4.1 to 0.8.2

### Added

- **Untrusted-content framing** — SECURITY section in `skills/epic-orchestration.md` documenting mandatory `<untrusted_content>` tags for user-provided content in dispatch prompts (CWE-77, OWASP LLM01)
- **Advanced preset warning** — explicit risk documentation and PM confirmation requirement in `defaults/policies/permissions.yaml`

### Changed

- **CLAUDE.md structure info** — corrected command count (10 → 11) and skill count (14 → 17); removed stale `docs/` directory reference
- **CHANGELOG alignment** — root and plugin `[0.8.1]` entries made identical per CLAUDE.md policy

## [0.8.1] — 2026-02-23

### Added

- **Process Audit type** (`agents/auditor.md` section F) — 6th audit type, always runs, with 13 checks across 4 categories: F.1 EPIC Lifecycle (3 checks), F.2 Evidence Completeness (6 checks), F.3 Cross-Validation (3 checks), F.4 Stage Log Integrity (1 check); deduction-based scoring (0-100); `process: {0-100}` field added to YAML output; 15% weight in Overall score; Score Overview template updated with Process row

### Changed

- **Audit weight redistribution** (`agents/auditor.md` weight table) — Documentation 20% → 25%, Process 15% added; total always-run audit types: 3 → 4; audit type count: 5 → 6

## [0.8.0] — 2026-02-23

### Added

- **CURATOR_RESOLVE state** — new state between GATES and PM_APPROVAL in the epic-orchestration state machine; auto-evaluates Curator proposals via 3-tier algorithm (YAML rules → Qdrant history → default), dispatches fix agents, writes lessons with 3-layer dedup
- **`curator_auto_rules`** in `decision-policies.yaml` — configurable auto-resolution rules for improvement proposals
- **PM override + rule teaching** at PM_APPROVAL — PM can override rejected proposals and teach new auto-rules that persist via YAML + Qdrant
- **Improvement Pipeline analytics** — Report Type 4 in `/aid-analytics` for curator pipeline metrics
- **3-layer Lessons-Extractor dedup** — text, semantic, and Qdrant cross-project deduplication

### Changed

- **State machine**: 11 → 12 states (CURATOR_RESOLVE inserted)
- **DONE state simplified**: Curator + Lessons-Extractor moved to CURATOR_RESOLVE
- **`backlog.md`**: PROP-* IDs migrated to IMP-{NNN} with legacy alias table
- 9 files updated across agents, skills, commands, and policies

## [0.7.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.6.0] — 2026-02-23

### Added

**Phase 2 — Seed Research + Example EPICs:**
- **Qdrant seed research** — 147 Qdrant chunks stored across 3 platforms: LangChain/LangGraph (64 chunks from 14+ repos), N8N (48 chunks from 5+ repos), LangFlow (35 chunks from 5+ sources)
- **AI workflow example EPICs** — 12 example EPICs in `defaults/examples/ai-workflows/` covering RAG chatbot, multi-agent systems, code review agent, data extraction pipeline, and more
- **Common project example EPICs** — 7 example EPICs in `defaults/examples/common-projects/` covering FastAPI CRUD, Next.js fullstack, React dashboard, SaaS starter, e-commerce, and more
- **Context7 live research verified** — all 4 platforms (LangChain, LangGraph, N8N, LangFlow) return relevant documentation via Context7 MCP
- **Qdrant knowledge retrieval verified** — seed research patterns retrievable via qdrant-find with correct metadata

## [0.5.0] — 2026-02-22

### Added

**Phase 1 — Research + Storage + Consumption:**
- **Knowledge acquisition skill** — new `skills/knowledge-acquisition.md` with Research, Storage, and Consumption protocols; Context7 MCP as primary source, WebSearch fallback, dual storage (per-project YAML index + global Qdrant), 4-gate quality protocol
- **Context7 MCP in `/aid-setup`** — Option 6b for framework documentation via MCP; auto-detection, verification, troubleshooting guide
- **Docker MCP elevated to recommended** — Option 6d in `/aid-setup`; auto-detection of Dockerfile/docker-compose.yml, dedicated install section
- **Documentation type in memory-mcp** — Type 6 with full metadata schema and 4-gate Documentation Quality Gate Protocol
- **Knowledge-Augmented Brainstorming** — `brainstorming.md` Step 1 and Step 3 integration with `knowledge_find()`; non-blocking with 5s timeout, graceful degradation
- **KNOWLEDGE CONTEXT block in agent-core** — 3-section block (Framework Documentation, Patterns, Lessons) with type-specific staleness thresholds (90/180/365 days)
- **`knowledge-base.yaml` template** — per-project reference index for documentation sources
- **Knowledge config in `memory-config.yaml`** — `knowledge:` root-level section with research, quality, and context7 subsections

**Phase 2 — On-Demand Research + Aging:**
- **`/aid-research` command** — on-demand research for specific frameworks/libraries; `--deep` mode for comprehensive documentation ingestion
- **Aging protocol** — TTL-based freshness weighting for all document types (90–365 days); stale/expired score multipliers (0.7/0.3); automatic exclusion after 180 days past TTL
- **Manual source addition** — conversational flow for adding documentation sources via URL or topic
- **Freshness weighting in `memory_find()`** — search results weighted by document age; stale chunks deprioritized automatically
- **Aging config in `memory-config.yaml`** — per-type TTL values, stale/expired weights, exclusion threshold

**Phase 3 — Auto-Extraction + Community Examples + Feedback:**
- **Example EPIC extraction protocol** — 7-stage `extract_example_epic()` function: eligibility check → extract → abstract → build text → PM approval → dedup → Qdrant storage; triggered in DONE state step 9b
- **`example_epic` document type** — Type 8 in memory-mcp.md with 11 metadata fields (frameworks, archetype, source_epic_id, complexity, roles, etc.); never-expire TTL; global project scope
- **Community example EPICs** — 3 curated templates in `defaults/examples/`: `langchain-rag-chatbot.md`, `fastapi-crud-service.md`, `react-dashboard.md`; placeholder paths, version ranges, standard EPIC template format
- **Example EPIC lookup in brainstorming** — Step 3 searches `defaults/examples/` + Qdrant for matching archetypes; PM offered: (A) Adapt, (B) Browse all, (C) Start fresh
- **Feedback tracking** — fire-and-forget `track_retrieval()` after `memory_find()`; tracks `times_retrieved` and `avg_retrieval_score` per framework in `knowledge-base.yaml`; deprecation signal after 180 days of zero retrievals
- **Feedback config in `memory-config.yaml`** — `feedback:` section with `track_retrieval`, `track_usefulness`, `deprecate_unused_after_days`

### Changed
- **Command prefix standardization** — 5 commands renamed to `aid-*` prefix (`run-epic` → `aid-run-epic`, etc.) for discoverability; 9 unused command files removed; 20+ cross-references updated
- **`/aid-plan-epic` UX text** — updated intro and Step 9 output for unified Plan→EPIC→Plan flow
- **`/aid-help` command description** — updated `/aid-plan-epic` entry to "Unified Plan→EPIC→Plan entry point"
- **DONE state in `epic-orchestration.md`** — new step 9b triggers example extraction after Curator; completion summary includes archetype when pattern is stored
- **`memory-mcp.md` document types** — expanded from 6 to 8 types (added Proposal, Example EPIC); feedback tracking hook in `memory_find()`
- **`brainstorming.md` non-blocking guarantee** — knowledge calls updated from 2 to 3 per session (Step 1 search + Step 3 knowledge + Step 3 examples); 7 new graceful degradation scenarios

## [0.4.2] — 2026-02-21

### Changed
- **`/plan-epic` step numbering** — renumbered all steps from fractional (0.5, 0.7, 2.5) to clean integers (1-9); internal cross-references updated
- **`/aid-brainstorm` step numbering** — renumbered Step 8b→9 and Step 9→10; new Step 10 presents interactive A-D handoff options (add items, all-phases EPIC, specific-phase EPIC, manual)
- **Cross-references** — updated plan-epic step references in run-epic.md (3 occurrences) and epic-orchestration.md (2 occurrences); updated aid-brainstorm.md and brainstorming.md internal refs

### Added
- **`/aid-init [path]` parameter** — documented optional path parameter in aid-init.md Usage section with examples for relative and absolute paths; updated aid-help.md entry
- **Phase selection** — plan-epic.md Step 2 now handles all-phases vs specific-phase EPIC generation when invoked from brainstorming with phase context
- **Re-opening protocol** — brainstorming.md documents how Option A (add items) works: load existing plan, display approved sections, return to Step 2, re-generate EPIC
- **Phase Selection section** — brainstorming.md EPIC Subagent Prompt Template includes phase handling for scoped EPIC generation

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
