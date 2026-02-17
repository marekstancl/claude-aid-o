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

**Option 6: Detect Qdrant MCP (Memory)**
- Probe for Qdrant MCP availability:
  ```
  TRY: qdrant-find(query="test", collection_name="aid-memory-probe")
  IF tool exists (even if collection not found): Qdrant MCP available
  IF tool_not_found error: Qdrant MCP not available
  ```
- If available:
  ```
  Qdrant MCP server detected!

  AID can use vector memory for semantic search across sessions.
  This enables agents to learn from past decisions and patterns.

  Enable memory? (Y/N)
  Collection name: [aid-memory]
  ```
  - If Y: update `.aid-o/03-config/policies/memory-config.yaml` → `memory.enabled: true`, set `collection_name`
  - Update `project-profile.yaml` with `memory: { enabled: true, provider: "qdrant", collection: "{name}" }`
- If not available:
  ```
  Qdrant MCP server not detected (optional).
  To enable vector memory later:
    1. Install: claude mcp add qdrant-memory -e QDRANT_URL="http://localhost:6333" -e COLLECTION_NAME="aid-memory" -- uvx mcp-server-qdrant
    2. Set memory.enabled: true in .aid-o/03-config/policies/memory-config.yaml
  ```
  - Skip silently, no error

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
Workspace: .aid-o/ ✅
Gates: customized for {stack} ✅
Profile: project-profile.yaml populated ✅
CLAUDE.md: generated ✅
Memory: {enabled (Qdrant MCP) | disabled (file-based only)}

Your project is ready for AID orchestration.

Next steps:
  1. Create an EPIC: .aid-o/02-epics/E-{YYYYMMDD}-{hash}-{topic}.md
  2. Or customize further: .aid-o/03-config/
  3. Run /aid-help for full documentation
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
