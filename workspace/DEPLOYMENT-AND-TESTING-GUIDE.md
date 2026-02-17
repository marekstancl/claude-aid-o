# AID Orchestrator — Deployment & Testing Guide

Complete guide for publishing the plugin, setting up a marketplace, installing in a test project, and manually testing all features.

---

## Part 1: GitHub Publish

### 1.1 Prepare the Repository

The plugin lives in `plugins/aid-orchestrator/`. For publishing, you need a dedicated Git repository for the marketplace.

**Option A: Monorepo with marketplace** (recommended for single plugin)

```bash
# Your current structure works — the marketplace wraps the plugin
ai-orchestrator/
  plugins/
    aid-orchestrator/         # The plugin itself
      .claude-plugin/
        plugin.json
      agents/
      commands/
      skills/
      defaults/
      README.md
  .claude-plugin/
    marketplace.json          # Marketplace manifest (create this)
```

**Option B: Standalone plugin repo** (for distribution)

```bash
# Extract the plugin to its own repo
mkdir aid-orchestrator-plugin
cp -r plugins/aid-orchestrator/* aid-orchestrator-plugin/
cd aid-orchestrator-plugin
git init
git add .
git commit -m "feat: AID Orchestrator plugin v0.1.0"
```

### 1.2 Create Marketplace Manifest

Create `.claude-plugin/marketplace.json` at the repository root:

```json
{
  "name": "aid-orchestrator-marketplace",
  "owner": {
    "name": "Marek Stancl",
    "email": "your-email@example.com"
  },
  "plugins": [
    {
      "name": "aid-orchestrator",
      "source": "./plugins/aid-orchestrator",
      "description": "Controller + Workers architecture for multi-agent software development. Takes an EPIC, generates a Plan, dispatches role-based agents, enforces quality gates.",
      "version": "0.1.0"
    }
  ]
}
```

> If using Option B (standalone repo), change `source` to `"."`.

### 1.3 Push to GitHub

```bash
# Create GitHub repo (public or private)
gh repo create aid-orchestrator --public --description "AID — AI Development Orchestrator for Claude Code"

# Push
git remote add origin git@github.com:YOUR_USERNAME/aid-orchestrator.git
git push -u origin main

# Optional: create a release tag
git tag v0.1.0
git push --tags
```

### 1.4 Validate

```bash
# Validate plugin structure (run from plugin directory)
cd plugins/aid-orchestrator
claude plugin validate .

# Validate marketplace (run from repo root)
cd ../..
claude plugin validate .
```

---

## Part 2: Marketplace Setup

### 2.1 Register Your Marketplace

Users register your marketplace once:

```bash
# Using GitHub shorthand
/plugin marketplace add YOUR_USERNAME/aid-orchestrator

# Or using full URL
/plugin marketplace add https://github.com/YOUR_USERNAME/aid-orchestrator.git
```

### 2.2 Install the Plugin

```bash
# Install for the current user (available in all projects)
/plugin install aid-orchestrator@aid-orchestrator-marketplace

# Or install for a specific project only
/plugin install aid-orchestrator@aid-orchestrator-marketplace --scope project
```

### 2.3 Verify Installation

After installation, Claude Code should recognize all 17 commands:

```bash
# Test that the plugin loaded
/aid-help

# Expected: Full AID overview with all commands listed
```

### 2.4 Update Plugin

When you push updates to the repository:

```bash
# Refresh marketplace catalog
/plugin marketplace update

# Reinstall to get latest version
/plugin install aid-orchestrator@aid-orchestrator-marketplace
```

---

## Part 3: Test Project Setup

### 3.1 Create a Test Project

Create a minimal but realistic project for testing AID features:

```bash
mkdir test-aid-project
cd test-aid-project
git init

# Create a minimal FastAPI + React project structure
mkdir -p backend/app/core backend/app/users backend/tests
mkdir -p frontend/src/components frontend/src/features
mkdir -p docs/api docs/architecture/adr

# Backend files
cat > backend/app/main.py << 'EOF'
from fastapi import FastAPI

app = FastAPI(title="Test Project", version="0.1.0")

@app.get("/health")
def health():
    return {"status": "ok"}
EOF

cat > backend/app/core/__init__.py << 'EOF'
# Core infrastructure - shared across modules
EOF

cat > backend/requirements.txt << 'EOF'
fastapi>=0.100.0
uvicorn>=0.23.0
pytest>=7.0.0
ruff>=0.1.0
EOF

# Frontend files
cat > frontend/package.json << 'EOF'
{
  "name": "test-aid-frontend",
  "version": "0.1.0",
  "scripts": {
    "build": "echo 'Build successful'",
    "test": "echo 'Tests passed'",
    "lint": "echo 'Lint passed'"
  }
}
EOF

cat > frontend/src/App.tsx << 'EOF'
export default function App() {
  return <div>Test Project</div>;
}
EOF

# Docs
cat > docs/api/README.md << 'EOF'
# API Documentation
Placeholder for API docs.
EOF

# CHANGELOG
cat > CHANGELOG.md << 'EOF'
# Changelog
## [Unreleased]
- Initial project setup
EOF

# Git setup
cat > .gitignore << 'EOF'
node_modules/
__pycache__/
*.pyc
.env
.aid-o/04-engine/
EOF

git add .
git commit -m "chore: initial project structure"
```

### 3.2 Initialize AID

```bash
# Run interactive setup (detects tech stack)
/aid-setup
```

**Expected behavior:**
- Detects FastAPI backend + React frontend
- Creates `.aid-o/` directory structure
- Generates `project-profile.yaml` with detected stack
- Configures `gates.yaml` with appropriate commands
- Copies templates and playbooks

**Verify:**
```bash
# Check workspace was created
ls .aid-o/
# Expected: 01-plans/ 02-epics/ 03-config/ 04-engine/

# Check profile was generated
cat .aid-o/04-engine/memory/project-profile.yaml
# Expected: tech stack, paths, conventions detected
```

### 3.3 Create Test EPIC

Copy the example EPIC from the plugin templates:

```bash
# Copy example EPIC (adjust source path to your plugin installation)
cp .aid-o/03-config/templates/epic-example.md .aid-o/02-epics/E-20260217-t001-task-management.md
```

Or create a simpler test EPIC for quick testing:

```bash
cat > .aid-o/02-epics/E-20260217-t001-simple-test.md << 'EPICEOF'
# EPIC: TEST-0001 — Health Check Endpoint Enhancement

## Context

The project has a basic /health endpoint. We need to enhance it with
dependency checks (database, cache) and structured response format.

## Goal

The /health endpoint returns structured JSON with individual dependency
status checks. Frontend displays a health dashboard component.

## Scope

### Allowed files/paths
- backend/app/health/
- backend/tests/test_health/
- frontend/src/features/health/
- docs/api/health.md

### Forbidden zones
- backend/app/core/
- backend/app/users/
- frontend/src/shared/

## Artifacts

- Enhanced GET /health endpoint with dependency checks
- React HealthDashboard component
- API documentation for health endpoint

## Constraints

- Tenant-safe: no
- Audit trail: no
- Outbox pattern: no
- Structured outputs: yes
- Budget: $5 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] GET /health returns JSON with "status", "dependencies" fields
- [ ] Each dependency has "name", "status", "latency_ms" fields
- [ ] Endpoint returns 200 when all healthy, 503 when any unhealthy
- [ ] HealthDashboard component renders dependency list
- [ ] Unit tests cover healthy and unhealthy scenarios
- [ ] API docs updated with new response schema

## Dependencies

None.

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design health check contract (OpenAPI) | -- | -- |
| 2 | backend | Implement enhanced health endpoint | 1 | group-impl |
| 3 | frontend | Build HealthDashboard component | 1 | group-impl |
| 4 | qa | Write unit + integration tests | 2, 3 | -- |
| 5 | docs | Update API documentation | 2 | -- |

## Session Breakdown

Single session — fits in one orchestrated run.
EPICEOF
```

---

## Part 4: Feature Testing — Step by Step

### Test 1: `/aid-help` — Self-Knowledge

```bash
/aid-help
```

**Verify:**
- [ ] Full overview displayed with all 17 commands
- [ ] Version shows 0.1.0
- [ ] `.aid-o/` status shown (if workspace exists)

```bash
/aid-help commands
/aid-help workflow
/aid-help epic
/aid-help agents
/aid-help planning
/aid-help gates
/aid-help evidence
/aid-help config
/aid-help slack
/aid-help queue
```

**Verify:**
- [ ] Each topic displays relevant, complete content
- [ ] No placeholder text or template markers

---

### Test 2: `/aid-init` — Workspace Creation

```bash
# In a fresh project (no .aid-o/)
/aid-init
```

**Verify:**
- [ ] `.aid-o/01-plans/` created (with `archive/`)
- [ ] `.aid-o/02-epics/` created (with `archive/`)
- [ ] `.aid-o/03-config/policies/gates.yaml` exists
- [ ] `.aid-o/03-config/policies/decision-policies.yaml` exists
- [ ] `.aid-o/03-config/policies/slack-config.yaml` exists
- [ ] `.aid-o/03-config/templates/` has epic.md, plan.md, plan.schema.json, 4 session templates, epic-example.md
- [ ] `.aid-o/03-config/playbooks/` has 11 playbooks (9 role + 2 docs platform)
- [ ] `.aid-o/04-engine/sessions/` created (with `archive/`)
- [ ] `.aid-o/04-engine/memory/active-work.md` exists
- [ ] `.aid-o/04-engine/backlog.md` exists
- [ ] `.aid-o/04-engine/lessons-learned.md` exists
- [ ] `.aid-o/04-engine/command-history.md` exists
- [ ] Running `/aid-init` again is idempotent (no errors, no duplicates)

---

### Test 3: `/aid-setup` — Project Onboarding

```bash
/aid-setup
```

**Verify:**
- [ ] Tech stack detected (FastAPI, React/TypeScript, PostgreSQL)
- [ ] Project structure analyzed
- [ ] `.aid-o/04-engine/memory/project-profile.yaml` generated
- [ ] Profile contains: language, framework, test commands, lint commands
- [ ] `gates.yaml` updated with project-specific commands
- [ ] Calls `/aid-init` internally if needed

---

### Test 4: `/plan-epic` — Plan Generation

```bash
/plan-epic .aid-o/02-epics/E-20260217-t001-simple-test.md
```

**Verify:**
- [ ] EPIC validation passes (all required sections present)
- [ ] `epic_id` extracted correctly from filename
- [ ] Plan JSON generated with steps matching EPIC
- [ ] Dependency graph correct (step 4 depends on 2+3, step 5 depends on 2)
- [ ] Parallel group `group-impl` detected (steps 2+3)
- [ ] Plan validated against `plan.schema.json`
- [ ] Session file generated in `.aid-o/04-engine/sessions/`
- [ ] Evidence directory created: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/`
- [ ] `plan.json` saved to evidence
- [ ] Plan summary displayed for PM review

**Negative test:**
```bash
# Create an invalid EPIC (missing Goal section)
echo "# EPIC: BAD-0001\n## Scope\n- stuff" > /tmp/bad-epic.md
/plan-epic /tmp/bad-epic.md
```

- [ ] Validation error reported with specific missing sections
- [ ] No plan generated

---

### Test 5: `/run-epic` — Full Pipeline

```bash
/run-epic
```

> This is the main orchestration test. It should walk through the state machine.

**State: IDLE**
- [ ] EPIC file resolved (auto-detect or from argument)
- [ ] EPIC validated
- [ ] `decision-policies.yaml` loaded
- [ ] `gates.yaml` loaded
- [ ] Evidence directory created (with subdirectories)
- [ ] Plan JSON found or generated
- [ ] `plan_progress.json` initialized
- [ ] EPIC copied to evidence

**State: PLANNING** (if plan doesn't exist)
- [ ] Plan generated from EPIC
- [ ] Validated against schema
- [ ] Session file generated
- [ ] Session file quality check passed

**State: PLAN_REVIEW**
- [ ] Plan summary displayed (steps, roles, parallel groups, budget)
- [ ] PM asked for approval (GO / REVISE / ABORT)
- [ ] PM response recorded in `pm_plan_approval.json`
- [ ] Test REVISE: PM says REVISE with feedback → returns to PLANNING
- [ ] Test GO: PM approves → transitions to EXECUTING

**State: EXECUTING** (per step)
- [ ] Correct step selected (dependency order respected)
- [ ] Branch created: `epic/{epic_id}/step_{N}_{role}`
- [ ] Playbook loaded for the role
- [ ] Agent prompt built with context (EPIC goal, step details, previous outputs)
- [ ] Agent dispatched via Task tool
- [ ] Output collected and saved to evidence
- [ ] For parallel groups: multiple agents dispatched concurrently

**State: PHASE_CHECK** (per step)
- [ ] Output presence verified
- [ ] Scope check (allowed/forbidden paths)
- [ ] Acceptance criteria evaluated
- [ ] For parallel groups: dry-run merge test
- [ ] Discovered issues triaged (if any)
- [ ] Auto-decision applied correctly

**State: NEXT_PHASE**
- [ ] `plan_progress.json` updated
- [ ] Session file updated
- [ ] Next step(s) identified from dependency graph
- [ ] Transitions to EXECUTING or GATES

**State: GATES**
- [ ] `gates.yaml` parsed
- [ ] Required gates executed
- [ ] Conditional gates skipped when conditions not met
- [ ] `gates_report.json` generated
- [ ] Gate outputs saved to `evidence/gates/`

**State: GATE_RETRY** (if any gate fails)
- [ ] Failure analyzed (error type classified)
- [ ] Gate-fixer agent dispatched
- [ ] Fix applied, gate re-run
- [ ] `gates_report.json` updated with retry
- [ ] After fix: ALL gates re-checked (not just failed one)
- [ ] After max retries: escalation triggered

**State: PM_APPROVAL**
- [ ] Final summary compiled (steps, gates, files, commits)
- [ ] PM asked for merge approval
- [ ] PM response recorded

**State: DONE**
- [ ] Branches merged (or PR created)
- [ ] EPIC file updated (status: Completed)
- [ ] Session file archived
- [ ] `active-work.md` updated
- [ ] `final_report.md` generated
- [ ] Curator agent dispatched (collects improvement notes)
- [ ] Auditor agent dispatched (post-EPIC audit)
- [ ] Status update sent

---

### Test 6: `/epic-status` — Pipeline Status

```bash
# During or after /run-epic
/epic-status
/epic-status TEST-0001
```

**Verify:**
- [ ] Shows step progress (done/pending/running)
- [ ] Shows gate results
- [ ] Shows budget usage
- [ ] Shows recent activity from `stage_log.jsonl`

---

### Test 7: `/run-step` — Manual Step

```bash
/run-step TEST-0001 step_3_backend
```

**Verify:**
- [ ] Single step dispatched without full pipeline
- [ ] Correct playbook loaded
- [ ] Output saved to evidence
- [ ] `plan_progress.json` updated

---

### Test 8: `/run-gates` — Standalone Gates

```bash
/run-gates
/run-gates TEST-0001
/run-gates --dry-run
```

**Verify:**
- [ ] Gates executed from `gates.yaml`
- [ ] `gates_report.json` generated
- [ ] `--dry-run` shows which gates would run without executing
- [ ] Standalone mode works without active EPIC

---

### Test 9: `/epic-queue` — Queue Management

```bash
# Add EPICs to queue
/epic-queue add .aid-o/02-epics/E-20260217-t001-simple-test.md --priority high
/epic-queue add .aid-o/02-epics/E-20260217-t002-another-test.md

# List queue
/epic-queue

# Check next
/epic-queue next

# Reorder
/epic-queue reorder TEST-0002 --priority critical

# Pause/resume
/epic-queue pause
/epic-queue resume

# Remove
/epic-queue remove TEST-0002
```

**Verify:**
- [ ] Queue displayed with priority ordering
- [ ] Duplicate detection (same EPIC can't be added twice)
- [ ] Priority ordering correct (critical > high > medium > low)
- [ ] Pause prevents auto-pickup
- [ ] Resume allows auto-pickup
- [ ] `epic-queue.yaml` file updated correctly

---

### Test 10: Session Management

```bash
# Start session
/session-start

# During work: verify session file created + updated
# End session
/session-end
```

**Verify:**
- [ ] Session file created with correct ID format (`S-YYYYMMDD-xxxx`)
- [ ] Correct template used based on task type
- [ ] `active-work.md` updated at start
- [ ] Session file archived to `sessions/archive/` at end
- [ ] `active-work.md` cleared at end
- [ ] `session-log.md` updated

---

### Test 11: `/handoff` — Session Handoff

```bash
/handoff
```

**Verify:**
- [ ] Handoff block generated with current state
- [ ] References session file
- [ ] Includes what's done, what's next, blockers

---

### Test 12: `/quality-gates` — Pre-Commit Gates

```bash
/quality-gates
```

**Verify:**
- [ ] 6 gates checked (logs, docs, cleanup, git status, commit message, tests)
- [ ] Report in standard format
- [ ] PASS/FAIL/SKIP per gate with details

---

### Test 13: `/audit` — Project Health Audit

```bash
/audit
```

**Verify:**
- [ ] Auditor agent dispatched
- [ ] 5 audit types run (code, security, docs, frontend, database)
- [ ] Health score generated (0-100)
- [ ] Report saved to evidence

---

### Test 14: `/coding-standards`, `/testing`, `/docs-protocol`

```bash
/coding-standards
/testing
/docs-protocol
```

**Verify:**
- [ ] Each loads appropriate standards/instructions
- [ ] References project-profile.yaml for project-specific context
- [ ] No template placeholders in output

---

### Test 15: Slack Integration (if configured)

> Requires a Slack MCP server to be installed and configured.

```bash
# Configure Slack
# Edit .aid-o/03-config/policies/slack-config.yaml
# Set enabled: true, channel, pm_user_id

# Run EPIC — messages should go to Slack
/run-epic
```

**Verify:**
- [ ] Plan approval message sent to Slack (Type B)
- [ ] PM can respond in Slack (GO/REVISE/ABORT)
- [ ] Status updates appear in Slack (Type G)
- [ ] Escalation messages formatted correctly (Type A)
- [ ] Merge approval message sent (Type C)
- [ ] Curator proposals sent (Type D)
- [ ] Audit summary sent (Type F)

**Fallback test:**
- [ ] Disable Slack (enabled: false) — all messages fall back to chat
- [ ] Simulate Slack failure — retry 3x, then fallback

---

### Test 16: Edge Cases

| # | Test | How to Trigger | Expected |
|---|------|---------------|----------|
| 1 | Empty EPIC | Create EPIC with no steps | Validation error at `/plan-epic` |
| 2 | Invalid Plan JSON | Manually corrupt plan.json | Schema validation fails |
| 3 | Missing playbook | Delete a playbook file | ESCALATION with error message |
| 4 | All gates pass | Ensure tests/lint pass | Direct to PM_APPROVAL |
| 5 | Circular dependency | Step A depends on B, B on A | Planner detects cycle, error |
| 6 | Parallel conflict | Two agents edit same file | PHASE_CHECK detects, ESCALATION |
| 7 | Gate retry | Introduce lint error | Gate-fixer dispatched, retried |
| 8 | PM timeout | Don't respond to Slack | Reminder sent, then timeout action |
| 9 | Duplicate in queue | `/epic-queue add` same EPIC twice | "Already in queue" rejection |
| 10 | Queue empty | No EPICs queued, last one completes | "Queue empty. Idle." message |

---

## Part 5: Troubleshooting

### Plugin Not Loading

```bash
# Check plugin is installed
claude plugin list

# Reinstall
/plugin install aid-orchestrator@aid-orchestrator-marketplace

# Check for errors in plugin.json
cd plugins/aid-orchestrator
claude plugin validate .
```

### Commands Not Recognized

- Verify plugin is installed in the correct scope (user/project/local)
- Check `.claude/settings.json` for plugin entry
- Restart Claude Code after installation

### `/aid-init` Fails

- Ensure you're in a git repository
- Check write permissions on current directory
- Verify plugin defaults/ directory has all template files

### `/run-epic` Errors

- Check `.aid-o/` workspace exists (`/aid-init`)
- Verify EPIC file format (`/plan-epic` validates)
- Check `plan_progress.json` is not corrupted
- Read `stage_log.jsonl` for state transition history

### Gates Always Fail

- Check `gates.yaml` commands match your tech stack
- Run `/aid-setup` to auto-configure for your project
- Check `command-history.md` for known working commands
- Verify test/lint tools are installed in your project

---

## Appendix: File Inventory

After full setup and one EPIC run, your project should have:

```
.aid-o/
  01-plans/
  02-epics/
    E-20260217-t001-simple-test.md
    archive/
  03-config/
    policies/
      gates.yaml
      decision-policies.yaml
      slack-config.yaml
    templates/
      plan.md, epic.md, epic-example.md, plan.schema.json
      session-bug-fix.md, session-new-feature.md
      session-refactoring.md, session-exploration.md
    playbooks/
      architect.md, domain.md, backend.md, frontend.md
      qa.md, security.md, observability.md, docs.md, release.md
      docs-docusaurus.md, docs-generic.md
  04-engine/
    sessions/
      archive/
        S-YYYYMMDD-xxxx-topic.md      (completed sessions)
    memory/
      active-work.md
      project-profile.yaml
      decisions.yaml
    evidence/
      TEST-0001/
        run_2026-02-17T.../
          epic_input.md
          plan.json
          plan_progress.json
          pm_plan_approval.json
          pm_decision.json
          stage_log.jsonl
          gates_report.json
          final_report.md
          prompts/
          steps/
          gates/
    backlog.md
    lessons-learned.md
    command-history.md
    epic-queue.yaml
```
