---
id: P010
type: plan
status: done
created: 2026-02-26
author: PM + AI
---

# Plan: Plugin DX & Housekeeping

## Context

AID plugin has accumulated DX (developer experience) issues that hurt onboarding and daily use. 18 of 19 commands lack `user_invocable: true` frontmatter (forcing users to type the full `/aid-orchestrator:command` prefix), `/aid-help` doesn't document First AID or emergency stop commands, setup wizard skips GitHub MCP and other optional MCPs after "All recommended", and several files still reference the old `workspace/workflow/` path instead of `.aid-o/`. Version numbers are hardcoded in CLAUDE.md and drift between releases. These are all low-risk fixes with high impact on usability.

Additionally, the plugin lacks example workflows for new users and a satisfying completion animation after setup — both affect first-impression quality.

## Goal

All slash commands work without prefix, `/aid-help` is complete and accurate, setup onboards all relevant MCPs, stale paths are gone, version numbers auto-sync or are documented for manual sync, and new users have example workflows to follow.

## Scope

**In scope:**
- Fix `user_invocable: true` frontmatter in all 18 command files
- Update `/aid-help` with First AID + Stop commands
- Setup wizard: add GitHub MCP and optional MCP follow-up question
- Fix 3 stale `workspace/workflow/` paths (planner.md, aid-plan-epic.md, slack-mcp.md)
- Fix session-management.md stale template references and default path (IMP-030)
- CLAUDE.md command/skill counts — replace hardcoded numbers with dynamic or documented approach
- README version badge sync with plugin.json
- Setup completion animation
- `/aid-help examples` — step-by-step example workflows
- Fix brainstorming prompt: always propose 2-3 approaches (sometimes skips or gives only 1)
- Fix brainstorming plan summary: include all PM-discussed details (currently loses specifics)
- Plugin version pre-check in `/aid-plan-epic` (compare local vs. GitHub latest)
- Implement `adapt_example()` in knowledge-acquisition.md (currently not implemented — PM can browse examples but not adapt)
- Surface knowledge search results to PM in brainstorming Step 1 (currently silent)
- `/aid-help knowledge` — list available example EPICs, how knowledge search works, what's indexed

**Out of scope:**
- Usage/token optimization (P013)
- Orchestration engine changes
- GUI changes (P009)

## Approach

### Option A: Single EPIC, sequential fixes (Chosen)

All items are independent file edits in `plugins/aid-orchestrator/`. 13 steps total — split into 2 EPICs if needed (housekeeping + brainstorming/knowledge). Mostly parallel, low risk.

**Pros:**
- Fast — most items are single-file edits
- High parallelism — nearly all items are independent
- Ship as one version bump

**Cons:**
- 7 items in one EPIC is manageable but requires careful tracking

### Decision

**Chosen:** Option A
**Rationale:** All items are independent, low-risk file edits. No architectural decisions needed. One EPIC, one version bump.

## High-Level Steps

| # | Step | Description | Effort |
|---|------|-------------|--------|
| 1 | Commands frontmatter | Add `user_invocable: true` YAML frontmatter to all 18 command files missing it | S |
| 2 | `/aid-help` update | Add `/aid-first-aid` and `/aid-stop` rows to command table, update command count | S |
| 3 | Setup MCP fix | Add GitHub MCP to recommended preset, add follow-up question for optional MCPs after "All recommended" | S |
| 4 | Stale path fixes | Update 3 files (planner.md, aid-plan-epic.md, slack-mcp.md) from `workspace/workflow/` to `.aid-o/` equivalents. Fix session-management.md stale template refs and default path. | S |
| 5 | Version sync | Replace hardcoded command/skill counts in CLAUDE.md with dynamic approach or documented checklist item. Ensure README badge matches plugin.json. | S |
| 6 | Setup animation | Add ASCII art or styled completion message after successful `/aid-setup` | S |
| 7 | Help examples | Create `/aid-help examples` topic with 2-3 step-by-step example workflows (brainstorm → plan → EPIC → run) | M |
| 8 | Brainstorming: enforce approaches | Fix `brainstorming.md` Step 4 — strengthen prompt to ALWAYS present 2-3 approaches with tradeoffs. Add validation: if fewer than 2 options generated, loop back and generate more. Never skip this step. | S |
| 9 | Brainstorming: complete plan summary | Fix `brainstorming.md` Step 8 (Document) — iterate over all PM answers from Steps 3-6 and include every discussed detail in the plan. Current prompt loses specifics. Add checklist: "For each PM answer in Steps 3-6, verify the corresponding detail appears in the plan document." | S |
| 10 | Plugin version pre-check | Add Step 0 to `/aid-plan-epic`: read local `plugin.json` version, compare with `gh api repos/.../releases/latest`, warn if outdated, offer `claude plugin update`. Non-blocking (warning only). | S |
| 11 | Implement adapt_example() | Implement the 7-step `adapt_example()` function in `knowledge-acquisition.md`: replace path placeholders, update framework versions, add/remove Docker sections, align platforms, merge constraints, adjust step count, write adapted EPIC. Currently PM selects "Adapt" but nothing happens. | M |
| 12 | Surface knowledge results | In `brainstorming.md` Step 1, show PM what knowledge was found: "Found 3 relevant docs: [FastAPI patterns], [RAG architecture], [LangChain gotchas]". Currently results are used internally but PM has no visibility. | S |
| 13 | `/aid-help knowledge` | New help topic listing: available example EPICs (19 files, categories), how knowledge search works (Context7 → Qdrant → static examples), what's indexed per project, how to trigger research. | S |

## Constraints

- All changes in `plugins/aid-orchestrator/` only
- No new npm dependencies
- Must pass existing CLAUDE.md release checklist
- Version bump required (covers all changes)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Frontmatter format breaks Claude Code plugin loader | low | high | Test with `claude plugin validate .` before committing |
| Setup MCP changes break existing installations | low | medium | Test fresh `/aid-setup` in clean project |

## Success Criteria

- All 19 commands accessible via `/aid-{name}` without prefix
- `/aid-help` lists all commands including First AID and Stop
- Fresh `/aid-setup` offers GitHub MCP in recommended set
- Zero `workspace/workflow/` references in plugin files
- Version numbers consistent across all 8 registry files after release
- `/aid-brainstorm` always presents 2-3 approaches with tradeoffs (tested on 3 different topics)
- Plan document from brainstorming includes all details discussed with PM (no information loss)
- `/aid-plan-epic` warns when plugin version is behind GitHub latest
- `adapt_example()` works end-to-end: PM selects example → adapted EPIC written to `.aid-o/02-epics/`
- Brainstorming Step 1 shows PM what knowledge was found (or "no knowledge indexed yet")
- `/aid-help knowledge` lists all 19 example EPICs with categories

## Run Breakdown

### Run 1: Housekeeping (steps 1-7, 10)
**Goal:** Fix commands, help, setup, paths, versions, animation, examples, version pre-check
**Deliverables:** All DX fixes shipped, version bump

### Run 2: Brainstorming & Knowledge (steps 8-9, 11-13)
**Goal:** Fix brainstorming prompts, implement adapt_example(), surface knowledge, help knowledge topic
**Deliverables:** Brainstorming quality improved, knowledge pipeline complete

## Next Steps

- [ ] Create EPIC for P010 Run 1
- [ ] Generate execution plan for Run 1
- [ ] Run EPIC Run 1
- [ ] Create EPIC for P010 Run 2
- [ ] Run EPIC Run 2

---

**Last Updated:** 2026-02-26
