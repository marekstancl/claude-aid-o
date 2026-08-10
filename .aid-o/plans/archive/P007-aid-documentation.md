---
id: P007
type: plan
status: done
created: 2026-02-25
author: PM + AI
---

# Plan: AID Plugin Complete Documentation

## Context

AID (AI Development Orchestrator) has reached v1.0.0 with a full feature set: 13 commands, 18 agents, 21 skills, FIRST AID autonomous mode, Qdrant memory, and quality gates. The project is publicly available on GitHub under AGPL-3.0 but has no structured documentation beyond the README and inline markdown in source files. Users and potential contributors lack a proper documentation site to understand installation, usage, architecture, and contribution workflows.

This plan was triggered by brainstorming session on 2026-02-25. The PM also considered source code protection options and decided to keep AGPL-3.0 as-is (CLA and trademark deferred to future consideration).

## Goal

Create a complete, Docusaurus-based documentation site for the AID plugin — covering user guides, command/agent/skill reference, architecture overview, and contributor docs — auto-generated from source files with a mandatory humanization pass, hosted on GitHub Pages.

## Scope

**In scope:**
- Docusaurus site setup in `docs/` directory (monorepo)
- Auto-generation of reference docs from `plugins/aid-orchestrator/commands/*.md` (13 files)
- Auto-generation of reference docs from `plugins/aid-orchestrator/agents/*.md` (18 files)
- Auto-generation of reference docs from `plugins/aid-orchestrator/skills/*.md` (21 files)
- Mandatory humanization pass on all generated docs (user-friendly language, consistent structure)
- Manual docs: getting started, architecture overview, configuration, contributing, troubleshooting
- GitHub Actions CI/CD for build + deploy to GitHub Pages
- English as primary language
- Czech translation infrastructure (Docusaurus i18n setup, actual translation as follow-up)

**Out of scope:**
- AID-GUI documentation (separate plan when GUI is complete)
- Czech translations content (only i18n infrastructure in this plan)
- Tutorials, video embeds, use-case cookbook (future enhancement)
- Source code protection changes (staying with AGPL-3.0)
- Algolia DocSearch setup (can be added after site is live)
- Custom Docusaurus plugins or React components

## Approach

### Option A: Docs-from-source (Chosen)
Auto-generate reference documentation by parsing existing command, agent, and skill markdown files, transforming them into Docusaurus-compatible pages. Complement with manually written guides for architecture, getting started, and contributing.

**Pros:**
- Docs stay in sync with code — command reference generated from real source files
- Less manual work — AID agents read existing `.md` files and transform them
- Consistent format across all reference docs
- Easy maintenance — change in command file = regenerate docs

**Cons:**
- Initial setup requires parsing logic for heterogeneous source formats
- Some docs (architecture, guides) must be written from scratch

### Option B: Manual-first
Write all documentation manually, independent of source files.

**Pros:**
- Full control over content and narrative style

**Cons:**
- High effort — 52+ source files to document manually
- Docs quickly diverge from code
- Information duplication

### Option C: Hybrid
Generate reference automatically, write guides manually, link both in Docusaurus.

**Pros:**
- Best of both worlds

**Cons:**
- Two different maintenance workflows

### Decision

**Chosen:** Option A — Docs-from-source
**Rationale:** AID already has rich markdown files for every command, agent, and skill. Transforming these into user-facing docs is the most efficient approach. The mandatory humanization pass ensures generated docs are not too technical. Manual docs complement where generation cannot help (architecture, guides).

## High-Level Steps

| # | Step | Description | Estimated Effort |
|---|------|-------------|-----------------|
| 1 | Docusaurus scaffold | Initialize Docusaurus project in `docs/`, configure theme, sidebars, i18n infrastructure, basic layout | S |
| 2 | GitHub Actions CI/CD | Create workflow for build + deploy to GitHub Pages on push to main | S |
| 3 | Getting Started section | Write installation.md, quick-start.md, configuration.md manually | M |
| 4 | Command reference generation | Parse all 13 `commands/*.md` files, transform into Docusaurus pages with frontmatter, usage, parameters, examples | M |
| 5 | Agent reference generation | Parse all 18 `agents/*.md` files, transform into Docusaurus pages with role description, capabilities, dispatch context | M |
| 6 | Skill reference generation | Parse all 21 `skills/*.md` files, transform into Docusaurus pages with description, usage, key principles | M |
| 7 | Humanization pass | Review ALL generated docs (steps 4-6), rewrite into user-friendly language, unify structure across sections, ensure consistency | M |
| 8 | Architecture section | Write overview.md (pipeline diagram, state machine), orchestration-flow.md, quality-gates.md, memory-system.md, first-aid-mode.md | M |
| 9 | Configuration section | Write docs for gates.yaml, decision-policies.yaml, dispatch-strategy.yaml, slack-integration | S |
| 10 | Contributing section | Write how-to-contribute.md, plugin-structure.md, adding-commands.md, adding-agents.md, code-style.md | M |
| 11 | Troubleshooting + FAQ | Write common-issues.md and faq.md based on known issues and typical user questions | S |
| 12 | Landing page + navigation | Create intro.md landing page, finalize sidebars.ts, verify cross-links, broken link check | S |
| 13 | Final review + deploy | Full review of all docs, test build, verify GitHub Pages deployment, confirm site is live | S |

## Constraints

- Must use Docusaurus v3+ (current stable)
- Must deploy to GitHub Pages (free tier)
- Docs live in `docs/` directory within existing `claude-aid-o` monorepo
- English is primary language; Czech i18n infrastructure only (no content translation in this plan)
- Generated docs must go through humanization pass before being considered done
- No custom React components — standard Docusaurus markdown/MDX features only

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Source files have inconsistent formats | medium | medium | Normalization pass during generation; agent adapts parsing per file |
| Generated docs too technical for end users | medium | high | Mandatory humanization pass (step 7) rewrites all generated content |
| Docs drift from code over time | low | medium | CI check: build docs on every PR; future enhancement: auto-regeneration |
| i18n infrastructure adds complexity | low | low | Only setup in this plan, actual translations deferred |
| GitHub Pages custom domain issues | low | low | Start with default `.github.io` URL, custom domain later |

## Success Criteria

- Docusaurus site builds without errors
- All 13 commands documented with usage, parameters, and examples
- All 18 agents documented with role description and capabilities
- All 21 skills documented with description and key principles
- Architecture section explains the full pipeline (IDLE→DONE) with diagrams
- Getting started guide enables a new user to install and run their first `/aid-brainstorm`
- Contributing guide enables a developer to add a new command or agent
- Site is live on GitHub Pages
- No broken links (Docusaurus built-in check passes)

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Review EPIC steps and role assignments
- [ ] Run `/aid-plan-epic` to generate execution plan
- [ ] Run `/aid-run-epic` to start documentation generation

---

**Last Updated:** 2026-02-25
