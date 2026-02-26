---
sidebar_position: 3
title: "Configuration"
description: "Customize AID Orchestrator with project profiles, quality gates, permissions, and coding standards."
---

# Configuration

AID Orchestrator is configured through files inside the `.aid-o/03-config/` directory. When you run `/aid-init`, AID copies sensible defaults for all configuration files. When you run `/aid-setup`, it customizes those defaults to match your project's tech stack automatically.

You can fine-tune any of these files at any time. AID reads them fresh at the start of each EPIC run.

## Directory Structure

```text
.aid-o/
  03-config/
    policies/
      gates.yaml               Quality gates — test, lint, security, build commands
      decision-policies.yaml   Autonomy level — what the Controller decides vs. escalates
      permissions-auto.yaml    Permissions for FIRST AID autonomous mode
      dispatch-strategy.yaml   Parallel isolation — worktrees / branches / sequential
      slack-config.yaml        Slack channel, timeouts, and reminder settings
      memory-config.yaml       Qdrant vector memory settings
      release-policy.yaml      Version files, SemVer rules, git tag settings
      language.yaml            Document language for plans, EPICs, and reports
      skill-conflicts.yaml     Plugin conflict detection rules
    templates/
      epic.md                  EPIC specification template
      plan.md                  Plan document template
      plan.schema.json         Plan JSON schema (for /aid-plan-epic)
      run-new-feature.md       Run file template for new features
      run-bug-fix.md           Run file template for bug fixes
      run-refactoring.md       Run file template for refactoring
      run-exploration.md       Run file template for exploration runs
    playbooks/
      architect.md             Instructions for the Architect agent
      backend.md               Instructions for the Backend agent
      frontend.md              Instructions for the Frontend agent
      qa.md                    Instructions for the QA agent
      security.md              Instructions for the Security agent
      docs.md                  Instructions for the Docs Writer agent
      release.md               Instructions for the Release agent
      ... (11 playbooks total)
    .aid-manifest.yaml         Installed version + checksums (do not edit manually)
  04-engine/
    memory/
      project-profile.yaml     Project metadata, tech stack, conventions
```

Most of your day-to-day customization happens in `policies/`. Playbooks are the place to add project-specific conventions for individual agents.

---

## project-profile.yaml

**Location:** `.aid-o/04-engine/memory/project-profile.yaml`

This file describes your project to every agent. It is auto-populated by `/aid-setup` and updated over time as agents learn more about the project.

```yaml
project_name: "my-api"
tech_stack:
  language: TypeScript
  framework: Next.js
  test_framework: Vitest
  linter: ESLint
  build: "npm run build"
architecture: monorepo
initialized: true
git:
  initialized: true
  default_branch: main
  remote: "git@github.com:org/my-api.git"
  hosting: github
  visibility: private
  organization: org
conventions:
  commit_style: conventional
  naming: camelCase
  api_style: REST
```

Every agent reads this file at the start of its step. It tells them which patterns to follow, which tools to use, and how the project is structured. If `/aid-setup` did not detect something correctly, edit this file directly.

**Key fields to keep accurate:**

- `tech_stack` — drives gate command selection and agent behavior
- `architecture` — helps agents understand the project layout (`monorepo`, `single-app`, `microservices`)
- `conventions` — agents follow these when making naming and style decisions

---

## gates.yaml

**Location:** `.aid-o/03-config/policies/gates.yaml`

This file defines the quality gates that run after every EPIC execution and before PM approval. All `required: true` gates must pass for the EPIC to proceed.

```yaml
gates:
  tests_pass:
    description: "All tests pass (unit + integration)"
    required: true
    command: "pytest -q --tb=short"
    timeout_seconds: 300
    pass_criteria: "exit code 0"

  lint_pass:
    description: "Code passes linting and formatting checks"
    required: true
    command: "ruff check . && ruff format --check ."
    timeout_seconds: 120
    pass_criteria: "exit code 0"

  security_scan_pass:
    description: "No high/critical security findings"
    required: true
    command: "bandit -q -r . -ll"
    timeout_seconds: 180
    pass_criteria: "exit code 0, no HIGH or CRITICAL findings"

  docs_updated:
    description: "Documentation updated for all changed APIs/models"
    required: true
    rule: "CHANGELOG.md must be updated if code changes affect public API"
    pass_criteria: "manual or automated check"

  type_check:
    description: "TypeScript type checking passes"
    required: false
    command: "npx tsc --noEmit"
    timeout_seconds: 120
    when: "frontend files changed"
```

**To customize:**

- Replace commands with your project's actual test/lint commands (e.g., `npx vitest run` instead of `pytest`)
- Set `required: false` on gates that do not apply to your stack
- Add custom gates by following the same structure — AID will execute any gate with a `command` field
- Adjust `timeout_seconds` if your test suite is slow

`/aid-setup` updates this file automatically based on the detected stack. Run `/aid-setup` again after adding a new test framework to pick up the changes.

---

## decision-policies.yaml

**Location:** `.aid-o/03-config/policies/decision-policies.yaml`

This file controls what the Controller decides autonomously versus what gets escalated to you. It also sets quality thresholds that agents are expected to meet.

```yaml
quality_thresholds:
  min_test_coverage_percent: 80
  min_review_score: 7          # out of 10 (code-reviewer agent score)
  max_todo_count: 0            # no TODO/FIXME in committed code
  max_security_findings_high: 0
  max_security_findings_medium: 3

architecture_principles:
  - name: "contract-first"
    description: "API/event contracts must be defined before implementation"
  - name: "YAGNI"
    description: "Only implement what the EPIC requires, nothing more"

escalation_triggers:
  - trigger: "gate fails after max_attempts retries"
    action: "HARD STOP — present failure details to PM"
  - trigger: "LLM cost exceeds budget"
    action: "HARD STOP — present cost report to PM"
  - trigger: "security finding classified as CRITICAL"
    action: "HARD STOP — immediate PM notification"
```

**To customize:**

- Lower `min_test_coverage_percent` if your project does not yet have high coverage and you want to build up incrementally
- Add your own `architecture_principles` — agents read these and follow them when making implementation decisions
- Edit `not_acceptable` (the list of absolute blockers) to add patterns specific to your project, like banned imports or required license headers
- The `curator_auto_rules` section controls which improvement proposals are auto-approved after each EPIC — you can tune this to match how aggressively you want AID to apply suggestions

---

## permissions-auto.yaml

**Location:** `.aid-o/03-config/policies/permissions-auto.yaml`

This file controls what Claude Code auto-allows when you use `/aid-first-aid` (autonomous queue mode). In normal interactive mode (`/aid-run-epic`), you approve each permission prompt as usual. In FIRST AID mode, AID elevates permissions using this file so the pipeline can run unattended.

The file defines an `allow` list (patterns that are permitted) and a `deny` list (patterns that are always blocked, even if someone tries to add them to `allow`):

```yaml
allow:
  # Claude Code built-in tools
  - "Read(*)"
  - "Edit(*)"
  - "Write(*)"
  - "Glob(*)"
  - "Grep(*)"

  # Local git operations
  - "Bash(git add:*)"
  - "Bash(git commit:*)"
  - "Bash(git diff:*)"
  - "Bash(git status:*)"

  # Testing and linting
  - "Bash(pytest:*)"
  - "Bash(ruff check:*)"
  - "Bash(npm test:*)"

deny:
  # Hard deny — never permitted regardless of allow list
  - "Bash(rm -rf /:*)"
  - "Bash(git push --force:*)"
  - "Bash(git reset --hard:*)"
  - "Bash(sudo:*)"
```

**To customize:**

- Add project-specific commands to `allow` that your gates or agents need (e.g., `"Bash(cargo test:*)"` for a Rust project)
- The plugin default file at `defaults/policies/permissions-auto.yaml` includes a comprehensive starting set. Copy it to `.aid-o/03-config/permissions-auto.yaml` to start from that baseline
- Items in `deny` override items in `allow` — hard deny patterns cannot be overridden even if explicitly added to the allow list
- The `learned` section at the bottom of this file is auto-managed. When you manually approve a permission prompt during a FIRST AID session, AID adds it to `learned` so you are not prompted again next time

**Permission resolution order:**

1. `.aid-o/03-config/permissions-auto.yaml` (your project-specific file, if it exists)
2. Plugin defaults (`defaults/policies/permissions-auto.yaml`)

If your project file exists, it takes full precedence — the plugin defaults are not merged in.

---

## Playbooks

**Location:** `.aid-o/03-config/playbooks/`

Playbooks are instruction files for each agent role. The Architect agent reads `architect.md` before executing its step; the Backend agent reads `backend.md`, and so on. The defaults are general-purpose and work for most projects.

Customizing a playbook is how you inject project-specific conventions directly into agent behavior:

**Example — adding conventions to `backend.md`:**

```markdown
## Project-Specific Conventions

This project uses the Repository pattern. Every data access operation MUST go
through a repository class in `src/repositories/`. Never query the database
directly from a service or controller.

All API endpoints return responses in this structure:
  { "data": <payload>, "meta": { "request_id": "<uuid>" } }

Import order: stdlib → third-party → internal (enforced by ruff isort).
```

The agent reads these conventions at the start of its step and applies them alongside the default playbook instructions. You do not need to replace the entire playbook — you can add a `## Project-Specific Conventions` section at the bottom of any playbook file.

---

## Upgrading Configuration

When you update the AID plugin, your customized config files are preserved. Run `/aid-init` after updating to pick up new default files:

```text
/aid-init
```

AID shows you a classified upgrade plan:

```text
Upgrade Plan (v0.9.1 → v0.9.2)
====================================

[NEW]        playbooks/e2e.md
[UPGRADE]    playbooks/architect.md
[UNCHANGED]  policies/decision-policies.yaml
[CUSTOM]     policies/gates.yaml (locally modified — skipped)
```

Files you have modified are classified as `CUSTOM` and skipped — your changes are never overwritten automatically. You can choose to review and merge changes manually using the diff hint AID provides.

To protect a specific file from ever being auto-upgraded (even if you have not modified it), add `custom: true` to its entry in `.aid-o/03-config/.aid-manifest.yaml`:

```yaml
files:
  policies/gates.yaml:
    checksum: "abc123..."
    custom: true    # Never auto-upgrade this file
```
