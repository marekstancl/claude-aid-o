# Orchestrator Architectural Gaps — Design

**Date:** 2026-02-17
**Status:** Approved
**Scope:** 3 independent gaps in AID Orchestrator plugin

---

## Problem Statement

AID Orchestrator has 3 architectural gaps that reduce autonomous quality and platform flexibility:

1. **No content quality validation** — PHASE_CHECK verifies file existence and scope compliance, but never evaluates whether the agent's work actually meets acceptance criteria. Quality issues surface only at gates (end of EPIC), when fixing is expensive.

2. **No agent-discovered issue reporting** — Agents that find problems during work have no structured way to signal them to the Controller. Problems either go unreported or surface late as gate failures.

3. **Hardcoded Docusaurus assumptions** — 15+ locations in the plugin assume Docusaurus as the docs platform (MDX escaping, `sidebar_label`, `npm run build` in docs/). The plugin is meant to be project-agnostic.

---

## Gap 1: Content Quality Loop

### Current State

PHASE_CHECK validates 3 things:
1. Expected output artifacts exist on filesystem
2. Agent stayed within `allowed_paths` / didn't touch `forbidden_paths`
3. Agent completed without error

It does NOT read `output.md` for content quality. It does NOT compare outputs against acceptance criteria.

### Design: Acceptance Validation (PHASE_CHECK Step 4)

Add a 4th validation step to PHASE_CHECK:

```
4. Acceptance Validation:
   a. Read agent's output.md from evidence
   b. Read step's acceptance criteria from plan.json
   c. For each acceptance criterion, evaluate:
      - Verifiable from output.md + git diff? → verify directly
      - Requires domain knowledge? → mark "needs_review"
   d. Decision:
      - All criteria clearly met → PASS
      - Any "needs_review" AND step triggers review → dispatch code-reviewer
      - Any criterion clearly NOT met → REJECT (re-dispatch with feedback)
```

### Review Trigger Rules (decision-policies.yaml)

```yaml
content_quality:
  auto_accept_when:
    - all acceptance criteria verifiable from output.md
    - step role is: docs, config, release
    - step has <= 3 acceptance criteria

  review_required_when:
    - step role is: architect, backend, frontend, security
    - step has 5+ acceptance criteria
    - step is target of analysis_group
    - orchestrator cannot determine if criterion is met

  review_agent: code-reviewer
  max_review_fix_cycles: 2
```

### Rejection Flow

```
Agent delivers output
    → PHASE_CHECK (existing: outputs + scope + errors)
    → Acceptance Validation (NEW step 4)
        → PASS → NEXT_PHASE
        → NEEDS_REVIEW → dispatch code-reviewer
            → APPROVED → NEXT_PHASE
            → REJECTED (feedback) → re-dispatch original agent with feedback
                → max 2 review-fix cycles → ESCALATION
        → CLEARLY_NOT_MET → re-dispatch agent with specific feedback
            → max 2 review-fix cycles → ESCALATION
```

### Evidence

- `evidence/{epic_id}/{run_id}/reviews/step_{N}_{role}_review_{cycle}.md`
- `stage_log.jsonl` entries for each acceptance check and review cycle
- Session file: acceptance items marked checked/failed per phase

### Files to Modify

- `skills/epic-orchestration.md` — PHASE_CHECK state: add step 4 (acceptance validation)
- `commands/run-epic.md` — PHASE_CHECK implementation: add acceptance check + review dispatch
- `defaults/policies/decision-policies.yaml` — add `content_quality` section
- `skills/agent-core.md` — document that acceptance criteria are checked post-delivery

---

## Gap 2: Agent-Discovered Issues

### Current State

Agents produce: (a) implementation files on a git branch, (b) prose `output.md` saved to evidence. There is NO structured field for reporting problems discovered during work. An agent that partially completes work but wants to flag "I found problem X" has no way to do so.

### Design: DISCOVERED ISSUES Section in output.md

Agents add an optional section at the end of output.md:

```markdown
## DISCOVERED ISSUES

- **[CRITICAL]** Database migration script fails on PostgreSQL 14
  - Impact: Blocks deployment to staging
  - Recommendation: Fix before proceeding (needs backend agent)

- **[HIGH]** API endpoint /users lacks rate limiting
  - Impact: Potential DoS vector
  - Recommendation: Add to security backlog, not blocking for this step

- **[MEDIUM]** Test helper uses deprecated API
  - Impact: Will break on next framework upgrade
  - Recommendation: Add to improvement_notes

- **[INFO]** Test coverage for auth module is 62%
  - Impact: Below 80% threshold, will fail coverage gate
  - Recommendation: QA step should address this
```

If no issues found → section does not exist → Controller proceeds normally.

### Severity Levels

| Severity | Blocks Step | Controller Action |
|----------|:-----------:|-------------------|
| CRITICAL | YES | Auto-fix if pattern matches → else ESCALATION |
| HIGH | NO | Forward to later step if natural fit → else backlog + PM notification |
| MEDIUM | NO | Log to improvement_notes (Curator picks up) |
| INFO | NO | Log to improvement_notes |

### Controller Triage Logic

```
For each discovered issue:

  CRITICAL:
    → Check decision-policies.yaml auto_fix_patterns
    → Match found → dispatch appropriate agent with fix instructions
    → No match → ESCALATION (PM decides: fix / skip / abort)
    → Current step BLOCKED until resolved

  HIGH:
    → Log to evidence/discovered_issues/
    → Is there a later step that naturally addresses this?
      → Yes → prepend to that step's inputs
      → No → create entry in .aid-o/04-engine/backlog.md
    → PM notification via Slack (informational, non-blocking)
    → Current step NOT blocked

  MEDIUM / INFO:
    → Log to evidence/discovered_issues/
    → Add to improvement_notes (Curator flow)
    → Current step NOT blocked
```

### Decision-policies.yaml Extension

```yaml
discovered_issues:
  critical:
    auto_fix_patterns:
      - pattern: "migration.*fail"
        dispatch: backend
      - pattern: "dependency.*conflict"
        dispatch: backend
      - pattern: "security.*critical"
        dispatch: security
    default_action: escalate_to_pm
    blocks_current_step: true

  high:
    forward_to_later_step: true
    create_backlog_entry: true
    pm_notification: true
    blocks_current_step: false

  medium:
    log_to_improvement_notes: true
    blocks_current_step: false

  info:
    log_to_improvement_notes: true
    blocks_current_step: false
```

### Integration with Existing Systems

- **Curator:** MEDIUM/INFO → improvement_notes → Curator picks up in post-EPIC audit
- **Backlog:** HIGH without natural resolution → backlog.md → PM sees in next planning
- **Evidence:** All issues → `evidence/{epic_id}/{run_id}/discovered_issues/step_{N}.md`
- **Session file:** CRITICAL/HIGH → Session Log entry
- **Slack:** CRITICAL → escalation message; HIGH → informational notification

### Files to Modify

- `skills/epic-orchestration.md` — PHASE_CHECK: add discovered issues parsing after acceptance validation
- `commands/run-epic.md` — PHASE_CHECK: implement triage logic
- `defaults/policies/decision-policies.yaml` — add `discovered_issues` section
- `skills/agent-core.md` — document DISCOVERED ISSUES output format for all agents
- All 9 role playbooks — add instruction to report discovered issues
- `commands/run-epic.md` — agent prompt template: add "report issues in ## DISCOVERED ISSUES"

---

## Gap 3: Docs Platform Detection & Playbooks

### Current State

15+ locations hardcode Docusaurus assumptions:
- **Behavioral rules (3 files):** session-management.md (3x), agent-core.md (3x) — mandatory "Docusaurus docs update" at session-end
- **Agent identity (2 files):** docs-reviewer.md (MDX, sidebar_label, sidebars.js), docs playbook (MDX format, npm run build)
- **Path/command defaults (~10 files):** gates-engine.md, run-gates.md, architect/domain playbooks — literal `docs/`

No docs platform detection exists in aid-setup. project-profile.yaml has no docs configuration.

### Design: Platform-Aware Docs Architecture

```
aid-setup detects platform
    ↓
project-profile.yaml → docs.platform, docs.build_command, docs.path, docs.format
    ↓
Agents/skills read project-profile → load platform-specific docs playbook
    ↓
playbooks/docs-{platform}.md → detailed instructions per platform
```

### aid-setup Detection

Add to `commands/aid-setup.md`:

```
Detect docs platform:
  docusaurus.config.js|ts     → platform: docusaurus, format: mdx, build: "npm run build"
  mkdocs.yml                  → platform: mkdocs, format: md, build: "mkdocs build"
  conf.py + index.rst         → platform: sphinx, format: rst, build: "make html"
  .vitepress/config.*         → platform: vitepress, format: md, build: "vitepress build"
  book.toml                   → platform: mdbook, format: md, build: "mdbook build"
  docs/ exists, none of above → platform: generic-markdown, format: md, build: none
  no docs/ directory           → platform: none
```

### project-profile.yaml Extension

```yaml
docs:
  platform: docusaurus          # detected or manually set
  path: docs/                   # detected root directory
  format: mdx                   # mdx | md | rst
  build_command: "npm run build" # platform-specific, null if none
  frontmatter_required: true    # platform-specific
```

### Platform Docs Playbooks

**New files:**

`defaults/playbooks/docs-docusaurus.md` — consolidated from existing hardcoded instructions:
- Frontmatter: title, sidebar_label, last_updated (required)
- MDX escaping: braces in backticks, `<` → `&lt;`, JSX tags must be valid
- Build verification: `npm run build` in `{project.docs.path}`
- Sidebar: sidebars.js configuration, IDs match file paths
- File format: .mdx preferred, .md supported

`defaults/playbooks/docs-generic.md` — plain Markdown:
- No special frontmatter requirements
- No build step required
- Standard Markdown formatting
- No framework-specific escaping

Future: `docs-mkdocs.md`, `docs-sphinx.md`, `docs-vitepress.md` (add when needed).

### Parametrization of Main Files (5 key changes)

1. **`skills/session-management.md`** (lines 10, 183, 438):
   - "Update Docusaurus docs" → "Update project docs (per `playbooks/docs-{project.docs.platform}.md`)"
   - `npm run build` → `{project.docs.build_command}` (skip if null)

2. **`skills/agent-core.md`** (lines 279, 286, 326):
   - "Docusaurus docs update" → "docs update (per project docs playbook)"

3. **`defaults/playbooks/docs.md`**:
   - Replace hardcoded MDX instructions with: "Load platform playbook: `playbooks/docs-{project.docs.platform}.md`"
   - Build: `{project.docs.build_command}` in `{project.docs.path}`
   - Format: `{project.docs.format}`

4. **`agents/docs-reviewer.md`**:
   - Condition MDX/frontmatter rules: "If `project.docs.platform == docusaurus`: apply MDX escaping + sidebar_label"
   - "If `project.docs.platform != docusaurus`: apply generic Markdown checks only"

5. **`commands/aid-setup.md`**:
   - Add docs platform detection step (see detection table above)
   - Write results to project-profile.yaml

### Deferred (~10 secondary locations)

These use literal `docs/` paths but are not behavioral rules — they'll be updated incrementally:
- `skills/gates-engine.md` (4 locations)
- `commands/run-gates.md` (1 location)
- `defaults/playbooks/architect.md` (1 location — ADR path)
- `defaults/playbooks/domain.md` (2 locations — domain doc paths)
- `defaults/policies/gates.yaml` (1 location — docs_updated rule)
- `skills/quality-gates.md` (1 location — conditional MDX note)

---

## Implementation Scope

### Files to Create (3)
- `defaults/playbooks/docs-docusaurus.md`
- `defaults/playbooks/docs-generic.md`
- Design doc (this file)

### Files to Modify (~15)
- `skills/epic-orchestration.md` — PHASE_CHECK expansion (acceptance + discovered issues)
- `commands/run-epic.md` — PHASE_CHECK implementation + agent prompt template
- `defaults/policies/decision-policies.yaml` — content_quality + discovered_issues sections
- `skills/agent-core.md` — DISCOVERED ISSUES format + docs parametrization
- `skills/session-management.md` — docs parametrization (3 locations)
- `defaults/playbooks/docs.md` — platform-aware delegation
- `agents/docs-reviewer.md` — conditional platform rules
- `commands/aid-setup.md` — docs platform detection
- 9 role playbooks — add DISCOVERED ISSUES instruction

### Estimated Task Count
- Gap 1 (Content Quality Loop): ~4 tasks
- Gap 2 (Discovered Issues): ~4 tasks
- Gap 3 (Docs Platform): ~5 tasks
- Cross-references + verification: 1 task
- **Total: ~14 tasks**

---

## EPIC Placement

These 3 gaps are independent of Session 7 (E2E Test) and should be implemented before it — E2E testing benefits from having quality loops and issue reporting in place.

**Recommended:** Session 6.7 (Content Quality Loop + Discovered Issues) + Session 6.8 (Docs Platform Detection). Or a single Session 6.7 with all 3 gaps.
