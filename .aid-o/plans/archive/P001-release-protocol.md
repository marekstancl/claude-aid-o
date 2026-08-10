---
id: P001
type: plan
status: done
created: 2026-02-23
author: PM + AID
depends_on: P002
updated: 2026-02-23
update_notes: "Added FIRST AID auto-mode integration, git tags + GitHub Releases moved to in-scope, dual versioning made configurable (default: single), terminology SESSION→RUN noted"
---

# Plan: Automated Release Protocol — Version Bumping & Release Policy

## Context

Version bumping is currently manual and error-prone. During EPIC E-20260223-799c (Workflow
Intelligence Phase 2), the version files (`marketplace.json`, `plugin.json`, `README.md`) were
not updated after completion — the CHANGELOGs were bumped by a QA step, but the actual version
numbers in manifest files stayed at 0.5.0 until manually fixed. This has happened before
(the previous release `v0.5.0` also needed a separate manual commit `14ba594`).

The root cause: there is no enforced release step in the orchestration pipeline. The `release`
agent and playbook exist but are never automatically included. The DONE state handles archiving,
metrics, and memory but not versioning.

**Additionally**, when a Plan has multiple EPICs (phases), intermediate EPICs should not necessarily
bump the version — the PM should decide whether to release after each phase or wait for the full
plan to complete.

## Goal

Implement an automated release protocol that:
1. Detects when version bumps are needed after EPIC completion
2. Handles multi-phase plans (defer vs release now)
3. Enforces consistent SemVer rules across all version files
4. Integrates into the existing state machine without adding unnecessary complexity

## Scope

**In scope:**
- New `release-policy.yaml` configuration file defining versioning rules
- DONE state extension in `epic-orchestration.md` with release sub-phase
- PM choice for multi-phase plans (release now vs defer)
- Version file registry (which files to update, how)
- SemVer determination rules (when MAJOR/MINOR/PATCH)
- Configurable versioning: single (default) or dual (for monorepos with sub-packages)
- Git tags (`git tag vX.Y.Z`) after version bump
- GitHub Releases (`gh release create` from CHANGELOG section)

**Out of scope:**
- CI/CD pipeline integration
- NPM/PyPI publishing
- Automated CHANGELOG generation (already handled by QA steps)
- Breaking changes detection automation

## Approach

**Chosen: Extend DONE state with release sub-phase**

Add a release sub-phase inside the existing DONE state (between PM_APPROVAL transition and
archive/metrics). This avoids adding a new top-level state to the state machine while still
making release mandatory and visible.

**Rejected alternatives:**
- *New RELEASE state between PM_APPROVAL and DONE* — adds state machine complexity, requires
  changes to every state transition diagram, and the release logic is simple enough to be a
  DONE sub-phase.
- *Release step in every EPIC plan (planner.md rule)* — fragile, depends on planner remembering,
  duplicates logic across plans, doesn't handle the "defer for multi-phase" scenario well.
- *Quality gate (version_bumped)* — gates run BEFORE PM_APPROVAL, but version bump should happen
  AFTER approval (you don't bump versions for rejected EPICs).

## Decision

Extend DONE state with a release sub-phase. Create `release-policy.yaml` for configuration.
The Controller handles version detection and bumping directly (no agent dispatch needed — it's
mechanical string replacement, not creative work).

## Versioning Strategy — Definitive Rules

### SemVer Determination

AID follows [Semantic Versioning 2.0.0](https://semver.org/). While in 0.x.y (pre-1.0), minor
bumps may include breaking changes — but the intent is the same:

| Change Type | Bump | Examples |
|-------------|------|----------|
| Breaking API/config/behavior change | **MAJOR** (or MINOR while 0.x) | Renamed commands, removed features, changed config format |
| New user-visible feature | **MINOR** | New skill, new agent, new command, new examples |
| Multiple new features in one EPIC | **MINOR** (one bump, not one per feature) | Phase 2 added skill + examples + research = one 0.5→0.6 |
| Bug fix only | **PATCH** | Fixed gate retry logic, fixed template typo |
| Internal refactoring (no user impact) | **PATCH** | Reorganized evidence structure, optimized prompts |
| Documentation-only changes | **PATCH** | Updated README, added help topics |
| New default templates/examples | **MINOR** | New example EPICs, new config templates |

### Versioning Modes

Configurable via `release-policy.yaml`:

```yaml
versioning:
  mode: single              # single (default) | dual (monorepo with sub-packages)
```

**Single mode (default):** One version track. One CHANGELOG. One set of version files.
This is what 99% of user projects need.

**Dual mode (monorepo only):** Two independent version tracks for projects like AID itself
where the project version and plugin version can diverge. Each track has its own CHANGELOG
as source of truth. Configured explicitly in `release-policy.yaml` with named tracks.

**Rule:** Version(s) are derived from CHANGELOG(s). The CHANGELOG is the source of truth —
version files are mirrors that must stay in sync.

### Version File Registry

Files that must be updated on release:

| File | Field | Tracks |
|------|-------|--------|
| `.claude-plugin/marketplace.json` | `metadata.version` | Project version |
| `.claude-plugin/marketplace.json` | `plugins[0].version` | Plugin version |
| `plugins/aid-orchestrator/.claude-plugin/plugin.json` | `version` | Plugin version |
| `README.md` | Roadmap "current" entry | Project version |
| `README.md` | License footer `MIT — vX.Y.Z` | Project version |

### Multi-Phase Plan Handling

When a Plan has multiple EPICs (phases):

```
Plan P-xxxx (3 phases)
  ├── EPIC 1 (Phase 1) — completed → release?
  ├── EPIC 2 (Phase 2) — completed → release?
  └── EPIC 3 (Phase 3) — completed → mandatory release
```

**Rules:**
1. **Last EPIC of a Plan** → mandatory version bump (no deferral option)
2. **Intermediate EPIC** → PM chooses:
   - **"Release now"** — bump version, commit, tag (if enabled)
   - **"Defer to final"** — skip version bump, CHANGELOG already updated, version files
     stay at current version until final EPIC
3. **Standalone EPIC (no plan or single-phase plan)** → mandatory version bump
4. **Detection:** Check `source_plan` field in plan.json → find all EPICs for that plan →
   determine if current EPIC is the last one

### DONE State Release Sub-Phase

Insert after PM_APPROVAL transition, before archive/metrics:

```
DONE state actions (updated order):
  1. Release sub-phase (NEW)
  2. Branch merge (existing)
  3. Auditor dispatch (existing)
  4. Qdrant metrics (existing)
  5. Archive logic (existing)
  6. Example EPIC extraction (existing)
  7. Completion summary (existing)
  8. EPIC queue check (existing)
  9. Final stage log entry (existing)
```

**Release sub-phase logic:**

```
1. DETECT changes:
   - Read root CHANGELOG.md → extract latest version header [x.y.z]
   - Read plugin CHANGELOG.md → extract latest version header [x.y.z]
   - Read current version files → extract current versions
   - Compare: if CHANGELOG version > file version → bump needed

2. If no bump needed → skip, log "versions current"

3. If bump needed:
   a. Check if multi-phase plan:
      - Read plan.json → source_plan
      - Check if more EPICs exist for this plan (status != done)
      - If intermediate EPIC:
        - Manual mode → ask PM: "Release now or defer?"
        - FIRST AID mode → auto-defer (default for intermediate)
      - If last/standalone EPIC → mandatory bump (both modes)

   b. If deferred → skip, log "version bump deferred"

   c. If bumping:
      - Update all files in Version File Registry
      - Read current README Roadmap, add/update "current" entry
      - Commit: "release: v{project_version} — {one-line summary}"
      - If git_tag enabled: `git tag v{version}`
      - If github_release enabled: `gh release create v{version} --notes "{CHANGELOG section}"`
      - Log to stage_log: {"state": "DONE", "action": "release", ...}

4. Present to PM what was done:
   - "Versions updated: project v0.6.0 → v0.7.0, plugin v0.7.0 → v0.8.0"
   - OR "Version bump deferred (intermediate phase, 2/3 EPICs complete)"
   - OR "Versions already current, no bump needed"
```

## High-Level Steps

1. **Create `defaults/policies/release-policy.yaml`** — version file registry, SemVer rules,
   multi-phase handling config, dual versioning definition.
   Effort: XS

2. **Extend `epic-orchestration.md` DONE state (section 12)** — add release sub-phase as
   action 1 (before branch merge). Include: version detection logic, multi-phase plan check,
   PM deferral flow, version file update procedure, commit format, stage_log entries.
   Effort: S

3. **Update `aid-run-epic.md`** — add release sub-phase to the DONE state description so the
   command documentation reflects the new behavior.
   Effort: XS

4. **Update PM_APPROVAL merge summary template** — add note about post-approval actions:
   "After approval: version bump (if needed) → archive → audit → metrics"
   so PM knows what happens after they confirm.
   Effort: XS

5. **Verify with current state** — walkthrough against E-20260223-799c: CHANGELOG says 0.6.0,
   marketplace.json was 0.5.0 → would detect mismatch → bump. Confirm logic is correct.
   Effort: XS

## Constraints

- DONE state must remain a single state (no new top-level state)
- Release sub-phase must not block on external services (no npm publish, no GitHub API)
- Version detection is purely string-based (parse CHANGELOG headers, compare to file values)
- PM deferral choice must be logged in evidence
- If CHANGELOG has no version header, skip gracefully (not all EPICs update CHANGELOGs)

## Risks

| Risk | Probability | Mitigation |
|------|-------------|------------|
| CHANGELOG version format varies | Low | Strict regex: `## [x.y.z]` — already standardized |
| Multi-EPIC plan detection fails (orphaned EPICs) | Medium | Fallback: treat as standalone, always bump |
| PM always defers, versions never bumped | Low | Last EPIC is mandatory — no deferral option |
| README Roadmap format changes | Medium | Version file registry is config — update in one place |
| Dual versioning confuses users | Low | Document clearly in release-policy.yaml |

## Success Criteria

- [ ] `release-policy.yaml` exists with version file registry, SemVer rules, and multi-phase config
- [ ] `epic-orchestration.md` DONE state includes release sub-phase with full logic
- [ ] Version mismatch between CHANGELOG and version files is auto-detected
- [ ] Multi-phase plans: PM can defer intermediate version bumps
- [ ] Last EPIC of a plan: version bump is mandatory (no deferral)
- [ ] Standalone EPICs: version bump is mandatory
- [ ] PM_APPROVAL summary mentions post-approval actions
- [ ] Walkthrough against E-20260223-799c produces correct detection and bump

## FIRST AID Integration

In autonomous mode (FIRST AID), the release sub-phase operates without PM interaction:

```
Manual mode:
  Intermediate EPIC → ask PM "Release now or defer?"
  Last EPIC → mandatory bump, PM informed

FIRST AID mode:
  Intermediate EPIC → auto-defer (no PM interaction)
  Last EPIC in queue → mandatory bump + tag + release (auto)
  Escalation → only if version detection fails or CHANGELOG is malformed
```

Both modes use the same release logic. The only difference is the decision point for
intermediate EPICs.

## release-policy.yaml Configuration

```yaml
versioning:
  mode: single                    # single | dual
  # dual mode config (only if mode: dual):
  # tracks:
  #   - name: project
  #     changelog: CHANGELOG.md
  #     files: [README.md, package.json]
  #   - name: plugin
  #     changelog: plugins/xyz/CHANGELOG.md
  #     files: [plugins/xyz/plugin.json]

release:
  git_tag: true                   # git tag vX.Y.Z after bump
  github_release: true            # gh release create from CHANGELOG
  draft_release: false            # publish immediately (not draft)

  # FIRST AID mode behavior:
  auto_tag: true                  # tag automatically in auto mode
  auto_release: true              # release automatically in auto mode

  # Manual mode behavior:
  confirm_before_tag: true        # "Create git tag v0.9.0? (Y/N)"
```

## Terminology Note

This plan uses "SESSION" in historical references. After C4 (Core Structure Refactoring),
all references will be updated to "RUN". The ID scheme will also migrate from UIDs
(`P-20260223-05aa`) to sequential autoincrement (`P001`).

## Future Enhancements (not in this plan)

- Automated CHANGELOG entry validation (format, date, version sequence)
- Pre-release versions (`0.7.0-rc.1`) for multi-phase plans
- Publish hooks (npm, PyPI) triggered by release commit

## Next Steps

- [ ] Create EPIC from this plan
- [ ] Ensure C4 (Core Structure Refactoring) completes first for terminology alignment
- [ ] Run via `/aid-run-epic`
