---
id: P006
type: plan
status: done
created: 2026-02-23
author: PM + AID
depends_on: P002
---

# Plan: Onboarding & Setup v2

## Context

AID's `/aid-init` and `/aid-setup` commands work but are incomplete. Several detection
capabilities are missing: GitHub repository awareness (for GitHub Pages recommendation),
documentation platform selection, skill conflict detection, and Claude Code version
recommendation. These gaps mean users must manually handle setup tasks that should be
automated.

This plan combines Roadmap items 1 (Detection — init/setup), 2 partial (documentation
platform selection), and 3a (skill conflict detection during setup).

Depends on C4 (Core Structure Refactoring) because setup must generate new ID scheme
and use updated terminology (RUN instead of SESSION).

## Goal

Enhance aid-setup with GitHub detection, documentation platform recommendation, skill
conflict auto-resolution, and Claude Code version guidance — making the onboarding
experience complete and user-friendly without rewriting the existing flow.

## Scope

**In scope:**
- GitHub remote detection (public/private, org/personal)
- Documentation platform recommendation based on project type
- Skill conflict detection and auto-deny via `.claude/settings.json`
- Claude Code version/plan recommendation text
- Updates to aid-setup command and project-profile.yaml

**Out of scope:**
- Rewriting aid-init or aid-setup from scratch (enhancement only)
- Actually creating documentation content (that's a separate effort)
- Implementing documentation platforms (setup only recommends and scaffolds)
- MCP server auto-configuration (already handled)

## Approach

**Chosen: Extend existing aid-setup with new detection steps**

Add new steps to the existing aid-setup flow. Each step is independent — detection,
recommendation, optional action. Setup already has a step-by-step structure; new steps
fit naturally.

**Rejected alternatives:**
- *Merge aid-init + aid-setup into one command* — Unnecessary disruption. Both work,
  they serve different purposes (init = create structure, setup = detect and configure).
- *Separate /aid-detect command* — Fragments the onboarding. Users would need to run
  3 commands instead of 2.

## Decision

Extend aid-setup with 4 new detection steps. Each step follows the pattern:
detect → recommend → ask PM → apply (or skip).

## High-Level Steps

1. **GitHub detection step** — Check for `.git/` and remote URL. Parse remote to determine:
   GitHub vs other (GitLab, Bitbucket), public vs private, org vs personal. Store in
   `project-profile.yaml` under `git:` section (extend existing fields with `hosting`,
   `visibility`, `organization`).
   Effort: XS

2. **Documentation platform recommendation** — Based on project type detected during setup:
   - CLI tool / library / npm package → recommend MkDocs Material or Docusaurus
   - Plugin / extension → recommend GitHub Pages or MkDocs
   - Web application → recommend plain .md in repo
   - Internal / private project → recommend plain .md
   - Open-source with community → recommend MkDocs Material or Docusaurus
   - Large projects → Docusaurus explicitly offered
   Ask PM which platform they want (A: plain .md / B: GitHub Pages / C: MkDocs Material /
   D: Docusaurus). Scaffold basic structure based on choice (create docs/ dir, mkdocs.yml,
   or docusaurus.config.js skeleton). Store choice in `project-profile.yaml` under `docs:`.
   Effort: S

3. **Skill conflict detection** — Scan for installed plugins/skills that may conflict with
   AID skills. Known conflicts: `superpowers:brainstorming` vs `aid-orchestrator:aid-brainstorm`.
   Maintain a conflict registry in `defaults/policies/skill-conflicts.yaml` listing known
   conflicting skill pairs. For each detected conflict: add `Skill({conflicting_skill} *)`
   to `.claude/settings.json` → `permissions.deny`. Inform PM what was disabled and why.
   Effort: S

4. **Claude Code version/plan recommendation** — Display text recommendation during setup:
   "Recommended: Claude Code with Max plan (4x Opus). Pro plan is limiting for orchestrated
   workflows due to rate limits and context constraints." Store nothing — purely informational.
   Effort: XS

5. **Update aid-setup command documentation** — Add new steps to `commands/aid-setup.md`.
   Update step numbering and flow description.
   Effort: XS

## Constraints

- Enhancement only — do not break existing aid-setup flow
- New steps are additive (appended to existing step sequence)
- Skill conflict deny must be reversible (PM can remove deny rules manually)
- Documentation scaffolding is minimal (create dirs + config skeleton, not content)
- CC version recommendation is text only (no version check, no blocking)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Skill deny syntax doesn't work as expected | Medium | High | Test `Skill(superpowers:brainstorming *)` deny before shipping; fallback to CLAUDE.md instruction |
| GitHub remote parsing fails for unusual URLs | Low | Low | Regex covers HTTPS and SSH formats; fallback: ask PM |
| PM confused by docs platform options | Low | Medium | Clear descriptions with project-type-based recommendation |
| Conflict registry becomes stale | Medium | Low | Start with known conflicts only; community can contribute |

## Success Criteria

- [ ] aid-setup detects GitHub remote and stores hosting/visibility in project-profile.yaml
- [ ] aid-setup recommends docs platform based on project type
- [ ] aid-setup scaffolds basic docs structure for chosen platform
- [ ] aid-setup detects and auto-denies conflicting skills via permissions.deny
- [ ] aid-setup displays CC version/plan recommendation
- [ ] Existing aid-setup functionality unaffected
- [ ] skill-conflicts.yaml exists with at least superpowers:brainstorming entry

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Test skill deny mechanism before implementation
- [ ] Run via `/aid-run-epic`
