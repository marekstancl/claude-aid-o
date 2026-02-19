Interactive project onboarding — analyze the project's tech stack and configure AID for it.

This is the first-time user experience. It detects what the project uses, initializes the workspace, and customizes AID configuration to match the project's tooling.

## Usage

```
/aid-setup
```

No arguments — runs in the current project root.

## Flow

### Step 1: Project Detection

Scan the project root for indicator files. For each found, extract key information:

| Indicator File | Language/Tool | What to Extract |
|---------------|---------------|-----------------|
| `package.json` | Node.js / TypeScript | name, scripts (build/test/lint/dev), dependencies (top frameworks), devDependencies |
| `tsconfig.json` | TypeScript | strict mode, target, paths |
| `pyproject.toml` | Python | name, tool sections (ruff, pytest, mypy), dependencies |
| `setup.py` / `requirements.txt` | Python (legacy) | packages, versions |
| `Cargo.toml` | Rust | name, dependencies, edition |
| `go.mod` | Go | module name, Go version, dependencies |
| `Gemfile` | Ruby | gems, Rails version |
| `pom.xml` / `build.gradle` | Java / Kotlin | groupId, artifactId, dependencies |
| `Dockerfile` | Docker | base image, exposed ports |
| `docker-compose.yml` | Docker Compose | services, databases |
| `.git/` | Git | current branch, remote URL, recent commits |
| `.github/workflows/` | GitHub Actions | workflow names, triggers |
| `.gitlab-ci.yml` | GitLab CI | stages, jobs |
| `Makefile` / `justfile` | Build system | available targets |

**Framework Detection** (from dependencies):
| Dependency | Framework |
|-----------|-----------|
| `next` | Next.js |
| `react` | React |
| `vue` | Vue.js |
| `express` | Express.js |
| `fastapi` | FastAPI |
| `django` | Django |
| `flask` | Flask |
| `rails` | Ruby on Rails |
| `spring-boot` | Spring Boot |

**Test Framework Detection:**
| Indicator | Test Framework |
|-----------|---------------|
| `jest.config.*` or jest in devDeps | Jest |
| `vitest.config.*` or vitest in devDeps | Vitest |
| `[tool.pytest]` or pytest in deps | Pytest |
| `mocha` in devDeps | Mocha |
| `cypress` in devDeps | Cypress |
| `playwright` in devDeps | Playwright |

**Linter Detection:**
| Indicator | Linter |
|-----------|--------|
| `.eslintrc.*` or eslint in devDeps | ESLint |
| `[tool.ruff]` or ruff in deps | Ruff |
| `pylint` in deps | Pylint |
| `.prettierrc.*` | Prettier |
| `[tool.mypy]` | mypy |

**Docs Platform Detection:**

| Indicator File | Platform | Format | Build Command |
|---------------|----------|--------|---------------|
| `docusaurus.config.js` or `docusaurus.config.ts` | `docusaurus` | `mdx` | `npm run build` |
| `mkdocs.yml` | `mkdocs` | `md` | `mkdocs build` |
| `conf.py` + `index.rst` | `sphinx` | `rst` | `make html` |
| `.vitepress/config.js` or `.vitepress/config.ts` | `vitepress` | `md` | `vitepress build` |
| `book.toml` | `mdbook` | `md` | `mdbook build` |
| `docs/` exists, none of above | `generic-markdown` | `md` | _(none)_ |
| No `docs/` directory | `none` | — | — |

Search for indicator files in project root first, then inside `docs/` directory.

### Git Detection and Health Check

1. Check if `.git/` exists in project root

2. If NOT a git repo:
   - Display warning:
     ```
     Git Status: Not initialized
     ====================================
     AID works best with git for branch isolation, evidence tracking,
     and diff generation. Without git, these features are disabled.
     ```
   - Ask PM:
     ```
     Initialize git in this project?
     (A) Yes — run `git init` and create initial commit (Recommended)
     (B) No — proceed without git (branch isolation disabled)
     ```
   - If A: run `git init`, create `.gitignore` (see below), initial commit
   - If B: log decision, force `dispatch-strategy: sequential`

3. If IS a git repo — check for .gitignore:
   - If `.gitignore` does NOT exist: create it with sensible defaults
   - If `.gitignore` exists but missing `.aid-o/04-engine/` entries:
     append AID-specific patterns

   Default .gitignore additions for AID:
   ```
   # AID Engine (internal state — not for version control)
   .aid-o/04-engine/sessions/
   .aid-o/04-engine/evidence/
   .aid-o/04-engine/memory/
   .aid-o/logs/

   # Environment
   .env
   .env.local
   ```

4. Record git status in project-profile.yaml:
   ```yaml
   git:
     initialized: true|false
     default_branch: "main"  # or detected from remote
     remote: ""              # or detected
     gitignore: true|false
   ```

### Step 2: Detect Project Type

Based on scan results, classify:

| Structure | Type | Description |
|-----------|------|-------------|
| Single `package.json` in root | **Single app** | One JS/TS application |
| `frontend/` + `backend/` dirs | **Monorepo (split)** | Separate frontend/backend |
| Root `package.json` with workspaces | **Monorepo (workspace)** | npm/yarn/pnpm workspaces |
| Only Python files | **Python project** | Python application/library |
| Only Go/Rust files | **Systems project** | Go or Rust application |
| Mix with no clear structure | **Custom** | Needs manual classification |
| Empty or only `.git` | **New project** | Nothing built yet |

### Step 3: Present Analysis

```
AID Setup — Project Analysis
====================================
Project: {name} (from package.json / pyproject.toml / directory name)
Type: {project type from step 2}

Tech Stack:
  Language:   {TypeScript, Python, Go, ...}
  Framework:  {Next.js, FastAPI, ...}
  Test:       {Jest, Pytest, ...}
  Lint:       {ESLint, Ruff, ...}
  Build:      {npm run build, cargo build, ...}
  CI/CD:      {GitHub Actions, GitLab CI, none}
  Docs:       {platform} ({format}) — build: {build_command}
  Database:   {PostgreSQL, MongoDB, ... (from docker-compose or deps)}

Structure:
  {directory tree of top-level dirs with brief description}

Git:
  Branch: {current branch}
  Remote: {origin URL}
  Commits: {total count}
```

### Step 4: Offer Setup Options

Present interactive checklist:

```
Setup options:
  1. [x] Initialize .aid-o/ workspace (/aid-init)
  2. [x] Customize gates.yaml for your tech stack
  3. [x] Populate project-profile.yaml
  4. [ ] Generate/update CLAUDE.md for this project
  5. [ ] Add .aid-o/ patterns to .gitignore
  6. [x] MCP server onboarding (Qdrant local, Slack, custom)
  7. [x] Permission preset selection (Safe/Recommended/Advanced)
  8. [x] Document language (default: EN)
  9. [x] Parallel isolation strategy (default: worktrees)

  [x] = recommended, [ ] = optional

Proceed with recommended? (Y/N/select numbers, e.g., "1,2,3,5")
```

### Step 5: Execute Selected Options

**Option 1: Initialize .aid-o/**
- Check if `.aid-o/` exists
- If not → run `/aid-init` logic (from `commands/aid-init.md`)
- If yes → report "Already initialized, skipping"

**Option 2: Customize gates.yaml**
- Read `.aid-o/03-config/policies/gates.yaml`
- Update gate commands based on detected stack:

| Detected | Gate | Command |
|----------|------|---------|
| pytest | tests_pass | `pytest -q --tb=short` |
| jest | tests_pass | `npx jest --ci` |
| vitest | tests_pass | `npx vitest run` |
| cargo test | tests_pass | `cargo test` |
| ruff | lint_pass | `ruff check . && ruff format --check .` |
| eslint | lint_pass | `npx eslint .` |
| eslint + prettier | lint_pass | `npx eslint . && npx prettier --check .` |
| bandit | security_scan | `bandit -q -r . -ll` |
| npm audit | security_scan | `npm audit --audit-level=high` |
| tsc | type_check | `npx tsc --noEmit` |
| mypy | type_check | `mypy .` |
| npm run build | build_pass | `npm run build` |
| cargo build | build_pass | `cargo build --release` |

- For monorepos: adjust commands to target correct directories
- Present diff of changes before applying:
  ```
  gates.yaml changes:
    tests_pass.command: "pytest -q --tb=short" → "npx jest --ci"
    lint_pass.command: "ruff check . && ruff format --check ." → "npx eslint . && npx prettier --check ."
    + type_check.required: true  (TypeScript detected)
    + build_pass.required: true  (build script detected)

  Apply? (Y/N)
  ```

**Option 3: Populate project-profile.yaml**
- Write to `.aid-o/04-engine/memory/project-profile.yaml`:
  ```yaml
  project_name: "{name}"
  tech_stack:
    languages: [{detected languages}]
    frameworks: [{detected frameworks}]
    test: [{detected test frameworks}]
    lint: [{detected linters}]
    build: ["{build commands}"]
    type_check: ["{type checkers}"]
  architecture: "{project type}"
  directories:
    root: "."
    frontend: "{path if detected}"
    backend: "{path if detected}"
    docs: "{path if detected}"
    tests: "{path if detected}"
  databases: [{detected from docker-compose or deps}]
  docs:
    platform: "{detected platform or 'none'}"
    path: "{detected docs root directory}"
    format: "{mdx|md|rst}"
    build_command: "{platform-specific build command or null}"
    frontmatter_required: true|false
  ci_cd: "{GitHub Actions | GitLab CI | none}"
  git:
    default_branch: "{branch}"
    remote: "{origin URL}"
  initialized: true
  scanned_at: "{ISO 8601}"
  scan_type: "quick"
  ```

**Option 4: Generate CLAUDE.md**
- Create or update `CLAUDE.md` in project root with:
  ```markdown
  # {project name}

  ## Tech Stack
  {from detection}

  ## Build & Test
  {working commands from detection}

  ## Project Structure
  {directory overview}

  ## AID Orchestrator
  This project uses AID for multi-agent orchestration.
  Workspace: .aid-o/
  Run /aid-help for usage information.
  ```

**Option 5: Update .gitignore**
- Add AID-specific patterns if not already present:
  ```
  # AID Orchestrator — engine internals (optional: exclude from VCS)
  # .aid-o/04-engine/evidence/
  # .aid-o/04-engine/sessions/archive/
  ```
  Note: These are commented out by default — user decides what to track in git.

**Option 6: MCP Server Onboarding**

This option replaces and extends the previous Qdrant-only detection with full MCP server onboarding.

**6a. Qdrant Local (Recommended)**

Recommend Qdrant local for vector memory — no Docker required:

```
MCP Server Onboarding
====================================

1. Qdrant Memory (Recommended)
   Enables semantic search across sessions — agents learn from past decisions.
   Local mode: no Docker needed, data stored in .aid-o/qdrant-data.

   Install command:
     claude mcp add qdrant-memory \
       --qdrant-local-path .aid-o/qdrant-data \
       -- uvx mcp-server-qdrant

   Enable Qdrant local memory? (Y/N) [Y]
   Collection name: [aid-memory]
```

- If Y: run the install command, update `.aid-o/03-config/policies/memory-config.yaml`:
  - Set `memory.enabled: true`
  - Set `memory.provider: "qdrant"`
  - Set `memory.collection_name: "{name}"`
  - Set `memory.local_path: ".aid-o/qdrant-data"`
- Update `project-profile.yaml` with `memory: { enabled: true, provider: "qdrant-local", collection: "{name}" }`
- Probe to confirm availability after install:
  ```
  TRY: qdrant-find(query="test", collection_name="aid-memory-probe")
  IF tool exists: Qdrant MCP confirmed
  IF tool_not_found: warn and continue (user can fix later)
  ```

**6b. Slack MCP (Opt-in)**

```
2. Slack MCP (Optional)
   Send EPIC status updates and gate results to a Slack channel.
   Requires a Slack Bot Token with chat:write scope.

   Enable Slack integration? (Y/N) [N]
```

- If Y: prompt for bot token and channel:
  ```
  Slack Bot Token: [xoxb-...]
  Default channel: [#aid-updates]
  ```
  - Run: `claude mcp add slack -e SLACK_BOT_TOKEN="{token}" -- npx -y @anthropic/mcp-slack`
  - Update `.aid-o/03-config/policies/slack-config.yaml` with channel and enable flag
- If N: skip silently

**6c. Auto-detect Tech MCPs**

Based on the project stack detected in Step 1, suggest relevant MCP servers:

| Detected | MCP Server | Install Command |
|----------|-----------|-----------------|
| `.github/` or GitHub remote | GitHub MCP | `claude mcp add github -- npx -y @anthropic/mcp-github` |
| `Dockerfile` / `docker-compose.yml` | Docker MCP | `claude mcp add docker -- npx -y @anthropic/mcp-docker` |
| PostgreSQL in deps | Postgres MCP | `claude mcp add postgres -e DATABASE_URL="{url}" -- npx -y @anthropic/mcp-postgres` |

```
Auto-detected MCP servers for your stack:
  [x] GitHub MCP (GitHub repository detected)
  [ ] Docker MCP (Docker detected)

Install selected? (Y/N/select numbers)
```

- Install each selected MCP server using its command
- Log installed MCPs to `project-profile.yaml` under `mcp_servers: [...]`

**6d. Custom MCP Server**

```
Add a custom MCP server? (Y/N) [N]
```

- If Y:
  ```
  MCP server name: [my-server]
  Install command: [npx -y @scope/mcp-server]
  Environment variables (KEY=VALUE, comma-separated, or blank): []
  ```
  - Run: `claude mcp add {name} {env_flags} -- {command}`
  - Append to `project-profile.yaml` under `mcp_servers`
- Repeat prompt: "Add another? (Y/N)"

**Option 7: Permission Preset Selection — Dual Write**

Present permission presets with a comparison matrix:

```
Permission Presets
====================================

Choose a permission level for AID agents:

  1. Safe       — Read-only. No file writes, no command execution.
                  Tools: Read, Glob, Grep, Task, WebSearch
                  Best for: auditing, code review, exploration

  2. Recommended — Edit, test, local git. No push, no remote MCP.  [DEFAULT]
                  Tools: Read, Write, Edit, Glob, Grep, local git,
                         test runners, Qdrant memory
                  Blocked: git push, rm -rf, curl, wget, Slack MCP
                  Best for: most development workflows

  3. Advanced   — Full access. Push, web, all MCP servers.
                  Tools: everything enabled, nothing blocked
                  Best for: trusted CI, experienced users

Comparison:
  +-------------------+------+-------------+----------+
  | Capability        | Safe | Recommended | Advanced |
  +-------------------+------+-------------+----------+
  | Read files        |  Y   |      Y      |    Y     |
  | Write/Edit files  |  N   |      Y      |    Y     |
  | Run tests         |  N   |      Y      |    Y     |
  | Local git ops     |  N   |      Y      |    Y     |
  | git push          |  N   |      N      |    Y     |
  | Web access        |  Y*  |      N      |    Y     |
  | Qdrant memory     |  N   |      Y      |    Y     |
  | Slack MCP         |  N   |      N      |    Y     |
  | Destructive cmds  |  N   |      N      |    Y     |
  +-------------------+------+-------------+----------+
  * Safe allows WebSearch (read-only) but not WebFetch

Select preset: (1/2/3) [2]
```

When PM selects a preset, perform **dual write** to BOTH files:

1. **Write preset to `.aid-o/03-config/policies/permissions.yaml`** (AID internal —
   tells agents what they're allowed to do via prompt):
   - Set `active_preset` to the selected value
   - The preset definitions are already in the file (copied from defaults)

2. **Update `.claude/settings.local.json`** (Claude Code enforcement —
   controls what VS Code auto-allows without prompting):
   a. Read existing `.claude/settings.local.json` (create `{"permissions":{"allow":[]}}` if missing)
   b. Read the selected preset's `claude_code_permissions` array from permissions.yaml
   c. Merge into `permissions.allow[]`, preserving existing user entries, avoiding duplicates
   d. Write updated `.claude/settings.local.json`

3. Save the selected preset to `project-profile.yaml` under `permission_preset`:
   ```yaml
   permission_preset: "recommended"   # safe | recommended | advanced
   ```

4. Confirm to PM:
   ```
   Permissions applied:
     - Preset: {name}
     - AID agents: .aid-o/03-config/policies/permissions.yaml
     - VS Code auto-allow: .claude/settings.local.json ({count} entries)
     - VS Code will NOT prompt for commands in the allow list
   ```

**Important:**
- NEVER overwrite existing user entries in `.claude/settings.local.json`
- Read -> merge -> write (additive, never destructive)
- For "advanced": `Bash(*:*)` means VS Code never prompts for ANY bash command
- Target file is `.claude/settings.local.json` (NOT `.claude/settings.json`)

**Option 8: Document Language**

```
Document Language
====================================

AID-generated documents (plans, reports, gate reviews, lessons learned)
can be written in your preferred language.

Internal commands, YAML keys, and code comments always remain in English.

Common options:
  EN — English (default)
  ES — Spanish
  PT — Portuguese
  FR — French
  DE — German
  JA — Japanese
  ZH — Chinese (Simplified)
  KO — Korean

Any ISO 639-1 code is accepted.

Document language: [EN]
```

- Copy `defaults/policies/language.yaml` to `.aid-o/03-config/policies/language.yaml`
- Update the `document_language` field with the user's choice
- Update `project-profile.yaml` with `document_language: "{code}"`
- If the user enters an unrecognized code, accept it but warn:
  ```
  Note: "{code}" is not in the common list. If the model cannot produce
  output in this language, it will fall back to English (logged as warning).
  ```

**Option 9: Parallel Isolation Strategy**

```
Parallel Isolation Strategy
====================================

AID runs agents in parallel during EPIC execution. Choose how to isolate
their work:

  1. Worktrees (Recommended)  [DEFAULT]
     Each agent gets a dedicated git worktree under .aid-o/worktrees/.
     Full filesystem isolation — agents can build and test independently.
     Requires: git 2.15+

  2. Branches
     Agents share the working tree but operate on separate branches.
     Lighter weight, but risk of file collisions during concurrent writes.
     Use when: disk space is limited.

  3. Sequential
     No parallelism. Steps run one at a time in the current working tree.
     Use when: small EPICs or CI environments.

Select strategy: (1/2/3) [1]
```

- Copy `defaults/policies/dispatch-strategy.yaml` to `.aid-o/03-config/policies/dispatch-strategy.yaml`
- Update the `strategy` field based on user choice:
  - 1 → `"worktrees"`, 2 → `"branches"`, 3 → `"sequential"`
- Update `project-profile.yaml` with `dispatch_strategy: "{strategy}"`
- Display confirmation:
  ```
  Strategy set to: {strategy}
  You can change this later by editing:
    .aid-o/03-config/policies/dispatch-strategy.yaml
  ```

### Step 6: New Project Flow

If the project is empty (no source files, only `.git`):

```
New project detected!

AID can help you get started:
  1. Brainstorm your project (interactive Q&A → Plan)
  2. Scaffold from template (choose a starter)
  3. Just initialize .aid-o/ (manual setup)

Choose: (1/2/3)
```

- **Option 1:** Start a brainstorming session → create Plan in `.aid-o/01-plans/`
- **Option 2:** Ask for project type and generate basic scaffold
- **Option 3:** Just run `/aid-init`

### Step 7: Summary

```
AID Setup Complete
====================================
Workspace:    .aid-o/ initialized
Gates:        customized for {stack}
Profile:      project-profile.yaml populated
CLAUDE.md:    {generated | skipped}
MCP servers:  {Qdrant local, Slack, GitHub MCP, ... | none}
Permissions:  {safe | recommended | advanced}
Language:     {EN | user choice}
Isolation:    {worktrees | branches | sequential}
Memory:       {enabled (Qdrant local) | disabled (file-based only)}

Your project is ready for AID orchestration.

Config files written:
  .aid-o/03-config/policies/permissions.yaml
  .aid-o/03-config/policies/language.yaml
  .aid-o/03-config/policies/dispatch-strategy.yaml

Next steps:
  1. Create an EPIC: .aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md
  2. Or customize further: .aid-o/03-config/
  3. Run /aid-help for full documentation
  4. Change isolation strategy: edit .aid-o/03-config/policies/dispatch-strategy.yaml
  5. Change permissions: edit .aid-o/03-config/policies/permissions.yaml
```

## Reference Files

- `commands/aid-init.md` — workspace initialization (called internally)
- Plan P-20260216-b3a1, sections D-006 (Project Scanner) and D-007 (/aid-setup)

## Important

- **NEVER delete existing project files** — only create/modify AID configuration
- If `.aid-o/` already exists, do NOT re-run `/aid-init` unless user asks (skip and report)
- If `project-profile.yaml` already has `initialized: true`, ask before overwriting
- Detection is best-effort — if uncertain about a tool, ask the user
- For monorepos: detect all workspaces and configure gates for each relevant one
