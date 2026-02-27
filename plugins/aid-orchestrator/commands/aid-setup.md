---
name: aid-setup
description: Interactive project onboarding — detect stack, configure AID
user_invocable: true
---

Interactive project onboarding — analyze the project's tech stack and configure AID for it.

This is the first-time user experience. It detects what the project uses, initializes the workspace, and customizes AID configuration to match the project's tooling.

## Usage

```
/aid-setup
```

No arguments — runs in the current project root.

## Flow

### Step 0: Re-Run Detection

**Execute this BEFORE any other setup step.**

```
RE-RUN DETECTION:

1. Check if .aid-o/04-engine/memory/project-profile.yaml exists AND has initialized: true
2. IF yes (re-run detected):
   a. Read existing project-profile.yaml into memory
   b. Present to PM:
      "Existing AID configuration detected.
       Initialized: {scanned_at date from profile}
       Project: {project_name}

       Select sections to update (comma-separated numbers, or 'all'):
       (1) Tech Stack — re-detect languages, frameworks, tools
       (2) MCP Servers — re-scan available MCP servers
       (3) Directories — re-detect project directory structure
       (4) Memory — reconfigure memory provider settings
       (5) Knowledge — reconfigure knowledge/context7 settings
       (6) Full re-scan — re-detect everything from scratch (keeps custom values as defaults)
       (0) Cancel — keep current configuration, exit setup"
   c. Read PM's selection
   d. IF PM selects "0": exit setup without changes
   e. IF PM selects "6" or "all": run full setup but pre-populate prompts with existing values
      (PM sees current value as default, can press Enter to keep or type new value)
   f. IF PM selects specific sections (e.g., "1,3"):
      Run only those sections of the setup wizard
      Merge results into existing project-profile.yaml:
      - Update only the fields belonging to selected sections
      - Preserve all fields from unselected sections unchanged
      - Preserve any custom fields not in the standard schema
   g. Update scanned_at timestamp after any changes
3. IF no (fresh install): proceed with full setup as before

SECTION-TO-FIELD MAPPING:
  (1) Tech Stack  -> tech_stack.languages, tech_stack.frameworks, tech_stack.test,
                     tech_stack.lint, tech_stack.build, tech_stack.type_check
  (2) MCP Servers -> mcp_servers.*
  (3) Directories -> directories.root, directories.plugin, directories.backend,
                     directories.frontend, directories.source, directories.docs,
                     directories.docker
  (4) Memory      -> memory.*
  (5) Knowledge   -> knowledge.*, context7.*

Custom fields (anything NOT in the standard schema above) are always preserved
during selective updates.

ERROR HANDLING:
- If project-profile.yaml exists but is corrupted (invalid YAML):
  "Existing project-profile.yaml is corrupted (parse error: {error}).
   Options: (A) Start fresh — overwrites corrupted file. (B) Abort — fix manually first."
  Do not silently overwrite.
- If PM selects a section that depends on another (e.g., Knowledge depends on MCP Servers
  for context7 availability):
  "Knowledge configuration depends on MCP Servers. Recommended to update MCP Servers (2)
   as well. Proceed anyway? (Y/N)"
```

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
   .aid-o/04-engine/runs/
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

5. Parse remote URL for hosting, visibility, and organization:

   **Skip condition:** If `remote` is empty (no remote configured), skip this step entirely.

   **a. Extract owner and repo from the remote URL.**

   Supported formats:
   - HTTPS: `https://github.com/{owner}/{repo}.git` or `https://github.com/{owner}/{repo}`
   - SSH: `git@github.com:{owner}/{repo}.git` or `git@github.com:{owner}/{repo}`
   - HTTPS with port: `https://git.example.com:8443/{owner}/{repo}.git`

   Parse logic:
   - For SSH (`git@{host}:{owner}/{repo}.git`): split on `:`, then split path on `/`
   - For HTTPS (`https://{host}/{owner}/{repo}.git`): parse URL path, split on `/`
   - Strip trailing `.git` from repo name if present

   **b. Determine hosting platform** from the parsed host:

   | Host | `hosting` value |
   |------|-----------------|
   | `github.com` | `"github"` |
   | `gitlab.com` | `"gitlab"` |
   | `bitbucket.org` | `"bitbucket"` |
   | Any other host | `"other"` |

   **c. Determine repository visibility** (GitHub only; skip for other platforms):

   If `gh` CLI is available, run:
   ```
   gh repo view {owner}/{repo} --json isPrivate -q '.isPrivate'
   ```
   - If returns `true` → visibility: `"private"`
   - If returns `false` → visibility: `"public"`
   - If `gh` is not installed or command fails → ask PM:
     ```
     Could not determine repository visibility automatically (gh CLI unavailable).
     Is this repository public or private?
     (A) Public
     (B) Private
     ```

   For non-GitHub platforms, set visibility: `"unknown"` (detection not supported).

   **d. Determine organization type** (GitHub only; skip for other platforms):

   If `gh` CLI is available, run:
   ```
   gh api /users/{owner} --jq '.type'
   ```
   - If returns `"Organization"` → organization: `"{owner}"`
   - If returns `"User"` → organization: `"personal"`
   - If `gh` is not installed or command fails → ask PM:
     ```
     Could not determine if "{owner}" is a personal account or an organization (gh CLI unavailable).
     Is "{owner}" a GitHub organization or your personal account?
     (A) Organization
     (B) Personal account
     ```

   For non-GitHub platforms, set organization: `"unknown"`.

   **e. Store extended fields** in project-profile.yaml under the existing `git:` section:
   ```yaml
   git:
     initialized: true
     default_branch: "main"
     remote: "git@github.com:org/repo.git"
     gitignore: true
     hosting: "github"         # NEW — github | gitlab | bitbucket | other
     visibility: "public"      # NEW — public | private | unknown
     organization: "org-name"  # NEW — org name string, "personal", or "unknown"
   ```

   **f. Fallback on parse failure:**

   If the remote URL does not match any recognized HTTPS or SSH pattern:
   ```
   Could not parse remote URL: {url}
   Skipping remote detection. You can set git hosting details manually in project-profile.yaml.
   ```
   Set `hosting: "unknown"`, `visibility: "unknown"`, `organization: "unknown"` and continue.
   This is non-blocking — setup proceeds normally.

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
  Hosting: {github | gitlab | bitbucket | other}
  Visibility: {public | private | unknown}
  Organization: {org name | personal | unknown}
  Commits: {total count}

Claude Code:
  Plan recommendation: Max plan (4x Opus) — optimal for orchestrated workflows
  Note: Pro plan works but may hit rate limits with parallel agents
```

### Step 4: Present Options with Details (Chat-First)

BEFORE asking PM to select options, present ALL options with detailed descriptions:

```
Setup Options Available
====================================

1. Initialize .aid-o/ workspace
   Creates the directory structure for plans, epics, runs, and evidence.
   Required for all AID features. (Recommended: always)

2. Customize gates.yaml
   Configures quality gates for your tech stack:
   - Tests: {detected_test_framework or "none detected"}
   - Linting: {detected_linter or "none detected"}
   - Security: {detected_security_tool or "none detected"}
   (Recommended: yes)

3. Populate project-profile.yaml
   Saves your project's tech stack, architecture, and conventions for agents.
   Detected: {languages}, {frameworks}
   (Recommended: yes)

4. Generate/update CLAUDE.md
   Adds AID commands reference and workspace info to your CLAUDE.md.
   (Recommended: if CLAUDE.md exists or you want one)

5. Add .aid-o/ to .gitignore
   Prevents committing evidence and engine files to git.
   (Recommended: yes for most projects)

6. MCP Servers
   a. Qdrant — vector memory for cross-run knowledge
   b. Context7 — framework documentation via MCP (knowledge acquisition)
   c. Slack — PM communication via Slack messages
   d. Docker — container management via MCP
   e. GitHub — repository operations, PR management, issue tracking
   f. Auto-detect — {list detected MCPs based on stack}
   g. Custom — add your own MCP servers
   (Recommended: at minimum Qdrant local + GitHub for GitHub-hosted projects)

7. Permission Preset
   Controls what Claude Code can do without asking:
   - Aspirin 💊: edit files, run tests/linters, local git — VS Code asks for risky ops
   - Steroids 💉: full access, zero prompts — required for /aid-first-aid
   Both presets deny destructive commands (rm -rf /, git push --force, sudo, etc.)
   (Default: Aspirin 💊)

8. Document Language
   Language for generated plans, EPICs, and reports.
   Default: EN (English). Conversation always follows your language.
   (Recommended: EN unless you prefer another)

9. Parallel Isolation Strategy
   How agents are isolated when running in parallel:
   - Worktrees: full filesystem isolation (recommended, requires git)
   - Branches: lighter isolation, shared filesystem
   - Sequential: no parallelism (safest, slowest)
   (Recommended: Worktrees if git available, Sequential otherwise)

10. Documentation Platform Setup
    Recommends a docs platform based on your project type and scaffolds the
    basic structure (dirs + config skeleton).
    Current docs detection: {detected docs.platform or "none"}
    (Recommended: yes, if no docs platform detected)

11. Skill Conflict Detection
    Scans for installed plugins that conflict with AID skills.
    Detected conflicts are auto-denied in .claude/settings.json.
    Conflicts are reversible — you can remove deny rules manually.
    (Recommended: yes)
```

THEN ask PM:
```
Which options would you like to configure?
(A) All recommended (options 1,2,3,6a,6b,6d,6e,7,8,9{",10" if docs.platform is "none" or "generic-markdown"},11)
(B) Let me pick specific options
(C) Everything (all options)
```

If (B): present a numbered list for PM to select from (e.g., "Enter option numbers: 1,2,3,5").

### Step 5: Execute Selected Options

**Option 1: Initialize .aid-o/**
- Check if `.aid-o/` exists
- If not → run `/aid-init` logic (from `commands/aid-init.md`)
- If yes → report "Already initialized, skipping"
- **After init (automatic):** Configure `.gitignore` for runtime artifacts:
  1. Check if `.gitignore` exists in project root
  2. If yes: check if `.aid-o/04-engine/` rule already exists (grep)
  3. If not present: append the AID gitignore block from `defaults/.gitignore`
  4. If `.gitignore` doesn't exist: create it with the AID rules
  - The appended block:
    ```
    # AID Orchestrator — runtime artifacts
    .aid-o/04-engine/
    ```
  - IMPORTANT: Never overwrite existing .gitignore rules. Always append.
  - This makes Option 5 (Add .aid-o/ to .gitignore) effectively automatic —
    it happens as part of init. Option 5 remains available for manual re-runs.

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
    hosting: "{github | gitlab | bitbucket | other}"
    visibility: "{public | private | unknown}"
    organization: "{org name | personal | unknown}"
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
  # .aid-o/04-engine/runs/archive/
  ```
  Note: These are commented out by default — user decides what to track in git.

**Option 6: MCP Server Onboarding**

This option replaces and extends the previous Qdrant-only detection with full MCP server onboarding.

**6a. Qdrant — Cross-Project Knowledge Database (Recommended)**

Qdrant is NOT just "optional memory" -- it is the **cross-project knowledge base**.

```
Why Qdrant?
====================================
Without Qdrant:
  - Lessons learned stay in THIS project only
  - When you start a new project, you start from zero
  - No way to search "what did I learn about FastAPI?"

With Qdrant:
  - Lessons, commands, and decisions from ALL your projects are searchable
  - Starting a new project? AID automatically finds relevant knowledge
  - "How did I handle auth last time?" -> instant answer from Project B
  - Semantic search: find by meaning, not just keywords

Qdrant runs locally (embedded or Docker). Your data never leaves your machine.
```

Present to PM:

```
MCP Server Onboarding
====================================

1. Qdrant Memory (Recommended)
   Cross-project knowledge database — learn from ALL your projects.
   Local mode: no Docker needed. Data stored centrally at
   ~/.local/share/aid-orchestrator/qdrant-data (shared across all projects).

   Install command:
     claude mcp add qdrant-memory --scope user \
       --qdrant-local-path ~/.local/share/aid-orchestrator/qdrant-data \
       -- uvx mcp-server-qdrant

   Install Qdrant for cross-project knowledge? (Recommended)
   (A) Yes — set up Qdrant local (recommended)
   (B) No — per-project knowledge only (lessons stay in each project)
   Collection name: [aid-memory]
```

- **Migration Check:** IF `.aid-o/qdrant-data/` exists in project root:
  ```
  Found local Qdrant data from previous setup. This data should be
  in the centralized location (~/.local/share/aid-orchestrator/qdrant-data).
  Would you like to migrate it? (Y/N)
  ```
  - If Y: move data, remove old directory, re-register MCP with --scope user
  - If N: keep both, warn about potential duplicate entries

- If Y: run the install command, update `.aid-o/03-config/policies/memory-config.yaml`:
  - Set `memory.enabled: true`
  - Set `memory.provider: "qdrant"`
  - Set `memory.collection_name: "{name}"`
  - Set `memory.local_path: "~/.local/share/aid-orchestrator/qdrant-data"`
- Update `project-profile.yaml` with `memory: { enabled: true, provider: "qdrant-local", collection: "{name}" }`
- Probe to confirm availability after install:
  ```
  TRY: qdrant-find(query="test", collection_name="aid-memory-probe")
  IF tool exists: Qdrant MCP confirmed
  IF tool_not_found: warn and continue (user can fix later)
  ```

**6b. Context7 MCP -- Framework Documentation (Recommended)**

Context7 provides curated, up-to-date documentation for 1000+ libraries directly via MCP.
It powers the knowledge-acquisition skill, enabling AID to research framework docs and serve
relevant knowledge to brainstorming runs and agent dispatch.

```
Why Context7?
====================================
Without Context7:
  - Agents rely on training data (may be outdated)
  - WebSearch fallback is slower and less reliable
  - No structured documentation for framework-specific questions

With Context7:
  - Curated docs for React, FastAPI, Next.js, LangChain, and 1000+ more
  - Always up-to-date (maintained by the Context7 community)
  - Two MCP tools: resolve-library-id + query-docs
  - No API key needed -- runs via npx

Context7 is optional. Without it, AID falls back to WebSearch for documentation.
```

**Setup flow:**

1. **Auto-detect:** Check if Context7 MCP is already available.
   ```
   TRY: resolve-library-id(libraryName="react", query="setup")
   IF tool exists AND returns results:
     -> Context7 already configured
     -> Skip to step 4 (Configuration)
   IF tool_not_found:
     -> Context7 not installed, proceed to step 2
   ```

2. **Install:** Present install option to PM.
   ```
   Context7 MCP Setup
   ====================================

   Context7 provides curated framework documentation via MCP.
   Package: @upstash/context7-mcp

   Install Context7 for framework documentation? (Recommended)
   (A) Yes — user scope (recommended, shared across all projects)
   (B) Yes — project scope (this project only)
   (C) No — use WebSearch fallback for documentation

   Scope explanation:
     User scope:    Available in ALL your projects. Installed once.
                    Command: claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
     Project scope: Available only in THIS project. Creates .mcp.json entry.
                    Command: claude mcp add context7 -- npx -y @upstash/context7-mcp
   ```

   - If A: run `claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp`
   - If B: run `claude mcp add context7 -- npx -y @upstash/context7-mcp`
   - If C: skip, set `knowledge.context7.available: false` in memory-config.yaml, continue

3. **Verification:** After install, confirm Context7 is working.
   ```
   TRY: resolve-library-id(libraryName="react", query="setup")

   IF returns library results:
     -> Display: "Context7 MCP verified -- ready to use."
   IF tool_not_found OR timeout:
     -> Display:
        Context7 verification failed.
        This may be a cold start issue (first npx call downloads the package).
        You can retry later by running /aid-setup and selecting Option 6b.
     -> Set knowledge.context7.available: false
     -> Continue (non-blocking)
   ```

4. **Configuration:** Update memory-config.yaml with Context7 status.
   - Set `knowledge.context7.available: true`
   - Set `knowledge.context7.scope: "user"` (or `"project"`)
   - Set `knowledge.context7.installed_at: "{ISO 8601 date}"`
   - Set `knowledge.primary_source: "context7"`
   - If Context7 was skipped or failed:
     - Set `knowledge.context7.available: false`
     - Set `knowledge.primary_source: "websearch"`

   Configuration written to `.aid-o/03-config/policies/memory-config.yaml` under
   the `knowledge:` section (see `skills/knowledge-acquisition.md` for full schema).

**Common issues:**

```
Context7 Troubleshooting
====================================

1. "npx: command not found"
   Context7 requires Node.js and npx. Install Node.js (v18+):
     macOS:   brew install node
     Linux:   curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt-get install -y nodejs
     Windows: https://nodejs.org/
   After installing Node.js, restart your terminal and retry.

2. Cold start timeout (first call is slow)
   The first call to Context7 downloads the @upstash/context7-mcp package via npx.
   This can take 10-30 seconds depending on your network.
   Subsequent calls are fast (package is cached by npx).
   If verification fails on first try, wait 30 seconds and retry.

3. "Library not found" for a specific framework
   Context7 covers 1000+ libraries but not all. If resolve-library-id returns
   no results for a framework, AID automatically falls back to WebSearch for
   that framework. No action needed.

4. MCP server crashes or restarts
   Context7 runs as a stdio MCP server via npx. If it crashes, Claude Code
   will restart it automatically on the next tool call.
   If persistent crashes occur, try reinstalling:
     claude mcp remove context7
     claude mcp add context7 --scope user -- npx -y @upstash/context7-mcp
```

**6c. Slack MCP Server**

**Package:** `slack-mcp-server` by @korotovsky
(NOT `@anthropic/mcp-slack` -- does not exist. NOT `@kazuph/mcp-slack` -- has Linux platform bug.)

**Setup flow:**

1. Ask PM: "Do you want Slack integration for PM notifications?"
   If no: skip, set `slack.enabled: false` in slack-config.yaml

2. If yes, display requirements:
   ```
   Slack Setup Requirements
   ====================================

   You need a Slack Bot with these scopes:
     Required:
       - chat:write        (send messages)
       - channels:read     (find channels)
       - channels:history  (read channel messages)
       - users:read        (CRITICAL: server crashes without this)
     Recommended:
       - channels:join     (auto-join channels)
       - groups:history    (private channel access)
       - groups:read       (private channel discovery)

   Setup steps:
     1. Go to https://api.slack.com/apps
     2. Select your app (or create one)
     3. Go to OAuth & Permissions -> Bot Token Scopes
     4. Add ALL required scopes listed above
     5. Reinstall app to workspace if you changed scopes
     6. Copy the Bot User OAuth Token (xoxb-...)
     7. In Slack, type: /invite @YourAppName in your channel
   ```

3. Ask PM for bot token: "Paste your Bot Token (xoxb-...):"

4. Ask PM for channel: "Which channel? (e.g., #aid-orchestrator):"

5. Ask PM for channel ID (for add_message tool):
   "Channel ID for sending messages (e.g., YOUR_CHANNEL_ID):"
   "Find it in Slack: right-click channel name -> View channel details -> scroll down"

6. Create `.env` file (if not exists) with:
   ```
   SLACK_MCP_XOXB_TOKEN=xoxb-...
   SLACK_MCP_ADD_MESSAGE_TOOL=YOUR_CHANNEL_ID
   ```

7. Add `.env` to `.gitignore` (if not already there)

8. Configure MCP server in `.mcp.json`:
   ```json
   {
     "slack": {
       "type": "stdio",
       "command": "bash",
       "args": [
         "-c",
         "[ -f .env ] && set -a && source .env && set +a; exec npx -y slack-mcp-server 2>/dev/null"
       ]
     }
   }
   ```
   Note: `2>/dev/null` suppresses stderr logs that interfere with VSCode MCP protocol.

9. Update `slack-config.yaml`:
   ```yaml
   slack:
     enabled: true
     channel: "#aid-orchestrator"
     pm_user_id: ""  # Optional: PM's Slack user ID for @mentions
   ```

10. Verify: Test MCP connection by asking Claude to list Slack channels.
    If it fails, check: scopes, token, channel invite, .env file.

**Common issues:**
- "FATAL: users:read scope required" -- Add `users:read` scope in Slack app settings, reinstall
- "conversations_add_message disabled" -- Set `SLACK_MCP_ADD_MESSAGE_TOOL` env var
- MCP stderr JSON logs -- Already handled by `2>/dev/null` in config

**6d. Docker MCP -- Container Management (Recommended)**

Docker MCP lets AID agents manage containers, build images, and run services directly
from Claude Code. For projects using Docker, this eliminates context-switching between
the terminal and the IDE for container operations.

```
Why Docker MCP?
====================================
Without Docker MCP:
  - Agents cannot interact with containers or images
  - Build/run commands must be executed manually
  - No visibility into running containers from Claude

With Docker MCP:
  - Build images, start/stop containers from Claude Code
  - Inspect logs, exec into containers, manage volumes
  - Agents can verify their work against real services
  - Works with both Dockerfile and docker-compose setups

Docker MCP runs locally. It connects to your existing Docker daemon.
```

**Setup flow:**

1. **Detection:** Check if `Dockerfile` or `docker-compose.yml` exists in the project.
   - If neither found: inform PM that Docker was not detected, but offer install anyway
     (some projects use Docker for dependencies only).

2. **Auto-detect:** Check if Docker MCP is already available.
   ```
   TRY: docker_list_containers()
   IF tool exists:
     -> Docker MCP already configured, skip to confirmation
   IF tool_not_found:
     -> Docker MCP not installed, proceed to step 3
   ```

3. **Install:** Present install option to PM.
   ```
   Docker MCP Setup
   ====================================

   Docker MCP provides container management via MCP.
   Package: @anthropic/mcp-docker

   Install Docker MCP? (Recommended)
   (A) Yes — user scope (recommended, shared across all projects)
   (B) Yes — project scope (this project only)
   (C) No — skip Docker MCP

   Scope explanation:
     User scope:    Available in ALL your projects. Installed once.
                    Command: claude mcp add docker --scope user -- npx -y @anthropic/mcp-docker
     Project scope: Available only in THIS project. Creates .mcp.json entry.
                    Command: claude mcp add docker -- npx -y @anthropic/mcp-docker
   ```

   - If A: run `claude mcp add docker --scope user -- npx -y @anthropic/mcp-docker`
   - If B: run `claude mcp add docker -- npx -y @anthropic/mcp-docker`
   - If C: skip, continue
   - No environment variables needed.

4. **Verification:** After install, confirm Docker MCP is working.
   ```
   TRY: docker_list_containers()

   IF returns results (even empty list):
     -> Display: "Docker MCP verified -- ready to use."
   IF tool_not_found OR error:
     -> Display:
        Docker MCP verification failed.
        Ensure Docker daemon is running: docker info
        You can retry later by running /aid-setup and selecting Option 6d.
     -> Continue (non-blocking)
   ```

5. **Configuration:** Update project-profile.yaml.
   - Append `docker` to `mcp_servers: [...]`

**Common issues:**

```
Docker MCP Troubleshooting
====================================

1. "Cannot connect to Docker daemon"
   Docker MCP requires the Docker daemon to be running.
   Start Docker:
     macOS:   Open Docker Desktop
     Linux:   sudo systemctl start docker
   Verify: docker info

2. "npx: command not found"
   Docker MCP requires Node.js and npx. Install Node.js (v18+):
     macOS:   brew install node
     Linux:   curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt-get install -y nodejs

3. Permission denied on Linux
   Add your user to the docker group:
     sudo usermod -aG docker $USER
   Then log out and back in.
```

**6e. GitHub MCP -- Repository & PR Management (Recommended)**

GitHub MCP gives AID agents direct access to GitHub operations: repository metadata,
pull request management, issue tracking, code search, and more. For any project hosted
on GitHub, this eliminates manual context-switching for common GitHub workflows.

```
Why GitHub MCP?
====================================
Without GitHub MCP:
  - Agents cannot read PRs, issues, or repository metadata
  - PR creation and review must be done manually
  - No way to search code across GitHub from Claude Code

With GitHub MCP:
  - Create, read, and update pull requests and issues
  - Search code across repositories
  - Read file contents and commit history from GitHub
  - Agents can verify branch status and CI checks
  - Works with both public and private repositories (with gh auth)

GitHub MCP uses your existing gh CLI authentication. No extra tokens needed.
```

**Setup flow:**

1. **Detection:** Check if the project is hosted on GitHub.
   - If `git.hosting` is `"github"` (from Git Detection): proceed to step 2.
   - If `git.hosting` is NOT `"github"` or no remote configured:
     ```
     GitHub hosting not detected for this project.
     GitHub MCP is still useful for cross-repo search and issue management.
     Install anyway?
     (A) Yes
     (B) No — skip
     ```
     If B: skip, continue to next option.

2. **Auto-detect:** Check if GitHub MCP is already available.
   ```
   TRY: get_me()   (GitHub MCP tool)
   IF tool exists AND returns user info:
     -> GitHub MCP already configured, skip to confirmation
   IF tool_not_found:
     -> GitHub MCP not installed, proceed to step 3
   ```

3. **Prerequisites:** Check that `gh` CLI is authenticated.
   ```
   TRY: gh auth status
   IF authenticated:
     -> Proceed to install
   IF not authenticated:
     -> Display:
        GitHub MCP requires gh CLI authentication.
        Run: gh auth login
        Then retry /aid-setup and select Option 6e.
     -> Skip (non-blocking), continue
   ```

4. **Install:** Present install option to PM.
   ```
   GitHub MCP Setup
   ====================================

   GitHub MCP provides repository operations, PR management,
   and issue tracking via MCP.
   Package: @anthropic/mcp-github

   Install GitHub MCP? (Recommended for GitHub-hosted projects)
   (A) Yes — user scope (recommended, shared across all projects)
   (B) Yes — project scope (this project only)
   (C) No — skip GitHub MCP

   Scope explanation:
     User scope:    Available in ALL your projects. Installed once.
                    Command: claude mcp add github --scope user -- npx -y @anthropic/mcp-github
     Project scope: Available only in THIS project. Creates .mcp.json entry.
                    Command: claude mcp add github -- npx -y @anthropic/mcp-github
   ```

   - If A: run `claude mcp add github --scope user -- npx -y @anthropic/mcp-github`
   - If B: run `claude mcp add github -- npx -y @anthropic/mcp-github`
   - If C: skip, continue
   - No environment variables needed (uses gh CLI auth).

5. **Verification:** After install, confirm GitHub MCP is working.
   ```
   TRY: get_me()

   IF returns user info:
     -> Display: "GitHub MCP verified -- authenticated as @{username}."
   IF tool_not_found OR error:
     -> Display:
        GitHub MCP verification failed.
        Ensure gh CLI is authenticated: gh auth status
        You can retry later by running /aid-setup and selecting Option 6e.
     -> Continue (non-blocking)
   ```

6. **Configuration:** Update project-profile.yaml.
   - Append `github` to `mcp_servers: [...]`

**Common issues:**

```
GitHub MCP Troubleshooting
====================================

1. "gh auth status" fails
   GitHub MCP relies on the gh CLI for authentication.
   Install and authenticate:
     macOS:   brew install gh && gh auth login
     Linux:   https://github.com/cli/cli/blob/trunk/docs/install_linux.md
   Then: gh auth login (follow interactive prompts)

2. "npx: command not found"
   GitHub MCP requires Node.js and npx. Install Node.js (v18+):
     macOS:   brew install node
     Linux:   curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt-get install -y nodejs

3. "Resource not accessible by integration"
   Your gh token may lack required scopes. Re-authenticate with:
     gh auth login --scopes "repo,read:org"
   This grants access to private repos and organization data.

4. Rate limiting (403 errors)
   GitHub API has rate limits. For authenticated requests, the limit is
   5000 requests/hour. If you hit limits, wait or check:
     gh api rate_limit --jq '.resources.core'
```

**6f. Auto-detect Tech MCPs**

Based on the project stack detected in Step 1, suggest relevant MCP servers
that were NOT already installed as recommended MCPs (skip Qdrant, Context7,
Docker, and GitHub if already configured above):

| Detected | MCP Server | Install Command |
|----------|-----------|-----------------|
| PostgreSQL in deps | Postgres MCP | `claude mcp add postgres -e DATABASE_URL="{url}" -- npx -y @anthropic/mcp-postgres` |
| Frontend framework (React/Vue/Angular/Svelte) or .tsx/.jsx/.vue files | Playwright MCP | `claude mcp add playwright -- npx -y @anthropic/mcp-playwright` |
| MinIO/S3 in deps or docker-compose | MinIO MCP | `claude mcp add minio -- npx -y minio-mcp` |

```
Auto-detected MCP servers for your stack:
  [x] Playwright MCP (detected: frontend framework)

Install selected? (Y/N/select numbers)
```

- Install each selected MCP server using its command
- Log installed MCPs to `project-profile.yaml` under `mcp_servers: [...]`

**6g. Custom MCP Server**

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

  1. Aspirin 💊  — Edit, test, local git. VS Code asks for risky ops.  [DEFAULT]
                   Tools: Read, Write, Edit, Glob, Grep, local git,
                          test runners, Qdrant memory
                   Blocked: git push, package install, unrestricted bash
                   Best for: most development workflows

  2. Steroids 💉 — Full access, zero prompts. Required for /aid-first-aid.
                   Tools: everything enabled
                   MCP: GitHub, MinIO, Docker, Playwright, Context7,
                        Qdrant memory
                   Best for: trusted CI, experienced users, first-aid

Comparison:
  +--------------------+-------------+-------------+
  |                    | Aspirin 💊  | Steroids 💉 |
  +--------------------+-------------+-------------+
  | Read files         |      Y      |      Y      |
  | Edit/Write files   |      Y      |      Y      |
  | Git (local)        |      Y      |      Y      |
  | Git push           |      N      |      Y      |
  | Run tests/lint     |      Y      |      Y      |
  | Package install    |      N      |      Y      |
  | Bash (unrestricted)|      N      |      Y      |
  | All MCP servers    |      N      |      Y      |
  | Destructive cmds   |      N      |      N      |
  +--------------------+-------------+-------------+
  Note: Steroids 💉 is required for /aid-first-aid.
  Destructive commands are ALWAYS denied (both presets).

Select preset: (1/2) [1]
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
   permission_preset: "aspirin"   # aspirin | steroids
   ```

4. Confirm to PM:
   ```
   Permissions applied:
     - Preset: {Aspirin 💊 | Steroids 💉}
     - AID agents: .aid-o/03-config/policies/permissions.yaml
     - VS Code auto-allow: .claude/settings.local.json ({count} entries)
     - VS Code will NOT prompt for commands in the allow list
     - Destructive commands are ALWAYS denied regardless of preset
   ```

**Important:**
- NEVER overwrite existing user entries in `.claude/settings.local.json`
- Read -> merge -> write (additive, never destructive)
- For "steroids": `Bash(*:*)` means VS Code never prompts for ANY bash command
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

**Option 10: Documentation Platform Setup**

**Skip condition:** If Step 1 detected an existing documentation platform (`docs.platform` is NOT `"none"` and NOT `"generic-markdown"`), display:
```
Documentation platform already detected: {docs.platform}
Skipping platform recommendation. To change, edit project-profile.yaml.
```
and skip this option.

**If no platform detected:**

1. Determine recommendation based on project type (from Step 2):

| Project Type | Recommendation | Reasoning |
|-------------|----------------|-----------|
| Single app (Node.js/TS) | MkDocs Material or Docusaurus | Needs good API docs and guides |
| Monorepo (split) | Docusaurus | Best for multi-package docs |
| Monorepo (workspace) | Docusaurus | Best for multi-package docs |
| Python project | MkDocs Material | MkDocs native to Python ecosystem |
| Systems project (Go/Rust) | MkDocs Material | Clean, fast, markdown-native |
| Plugin / extension | GitHub Pages or MkDocs | Lightweight, easy to maintain |
| Custom / Mixed | Plain Markdown | Start simple, upgrade later |
| New project | Plain Markdown | Start simple, upgrade later |

**Visibility upgrade:** If `git.visibility` is `"public"` (from Git Detection step 5) AND the recommendation is "Plain Markdown", upgrade to "MkDocs Material" — public/open-source projects benefit from a proper docs site.

2. Present to PM:

```
Documentation Platform Setup
====================================
Based on your project type ({type}), we recommend: {recommendation}

Choose a documentation platform:
(A) Plain Markdown — docs/ directory with .md files. No build step. Simple and universal.
(B) GitHub Pages — Static site from docs/ via GitHub Actions. Supports Jekyll themes.
(C) MkDocs Material — Feature-rich static site. Excellent search, navigation, and theming.
(D) Docusaurus — React-based docs framework. Versioning, i18n, blog support. Best for large projects.
(E) Skip — Keep current setup (or no docs)

Select: (A/B/C/D/E)
```

3. Scaffold based on choice:

**(A) Plain Markdown:**
- Create `docs/` directory
- Create `docs/README.md` with:
  ```markdown
  # {project_name}

  Project documentation.
  ```

**(B) GitHub Pages:**
- Create `docs/` directory
- Create `docs/index.md` with project name header
- Create `.github/workflows/pages.yml` skeleton:
  ```yaml
  name: Deploy to GitHub Pages
  on:
    push:
      branches: [main]
      paths: ['docs/**']
  jobs:
    deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/configure-pages@v4
        - uses: actions/upload-pages-artifact@v3
          with:
            path: docs/
        - uses: actions/deploy-pages@v4
  ```

**(C) MkDocs Material:**
- Create `docs/` directory
- Create `docs/index.md` with project name header
- Create `mkdocs.yml` skeleton:
  ```yaml
  site_name: {project_name}
  theme:
    name: material
    palette:
      scheme: default
  nav:
    - Home: index.md
  ```
- Display: "Run `pip install mkdocs-material` to install, then `mkdocs serve` to preview."

**(D) Docusaurus:**
- Create `docs/` directory
- Create `docs/intro.md` with project name header
- Display:
  ```
  Docusaurus scaffolding is minimal. For a full setup, run:
    npx create-docusaurus@latest docs-site classic
  This creates a complete Docusaurus project with default configuration.
  ```

**(E) Skip:**
- Do nothing. Display: "Skipped documentation platform setup."

4. Update `project-profile.yaml` `docs:` section:
```yaml
docs:
  platform: "{chosen platform — markdown | github-pages | mkdocs | docusaurus | none}"
  path: "docs/"
  format: "{md | mdx}"
  build_command: "{platform-specific or null}"
  frontmatter_required: false
  recommended_by: "aid-setup"
  chosen_at: "{ISO 8601 timestamp}"
```

5. Confirm to PM:
```
Documentation platform set to: {platform}
Scaffold created: {list of files/dirs created}
Stored in: project-profile.yaml → docs section
```

**Option 11: Skill Conflict Detection**

a. **Load conflict registry:**
   - First check `.aid-o/03-config/policies/skill-conflicts.yaml` (project-level override)
   - If not found, read `defaults/policies/skill-conflicts.yaml` (plugin default)
   - If neither exists, display "No conflict registry found. Skipping." and continue.

b. **Scan for conflicts:**
   For each entry in `conflicts:` array:
   1. Check if both skills listed in `skills:` are available (present in the installed plugins/skills list visible in the conversation context)
   2. If both are present → conflict detected
   3. If only one or neither is present → no conflict, skip

c. **Apply deny rules:**
   For each detected conflict:
   1. Read `.claude/settings.json` (create with `{"permissions":{"deny":[]}}` if file does not exist)
   2. Check if `"Skill({deny_skill} *)"` is already in `permissions.deny[]`
   3. If not present → append it
   4. Write updated `.claude/settings.json`

d. **Report to PM:**
   If conflicts were found and resolved:
   ```
   Skill Conflict Detection
   ====================================

   Detected conflicts:
     - {skills[0]} vs {skills[1]}
       Action: Denied "{deny}" in .claude/settings.json
       Reason: {reason}
       Preferred: {prefer}

   {count} conflict(s) resolved. Denied skills will not be invoked.

   To reverse: remove the Skill() entry from .claude/settings.json → permissions.deny
   ```

   If no conflicts detected:
   ```
   Skill Conflict Detection
   ====================================
   No conflicts detected. All installed skills are compatible.
   ```

e. **Important notes:**
   - Target file is `.claude/settings.json` (NOT `.claude/settings.local.json`)
   - Deny rules are additive — never remove existing entries
   - PM can manually reverse any deny by editing the file

### Step 5b: Optional MCP Follow-up

After all recommended options complete, if PM selected "(A) All recommended":

**Part 1: Optional MCP servers**

Run project-profile auto-detection for optional MCP candidates:
  1. Check `has_frontend: true` in project-profile → Playwright MCP candidate
  2. Check `tech_stack.database` → Postgres/MySQL MCP candidate
  3. Check `docker-compose.yml` for MinIO/S3 services → MinIO MCP candidate
  4. Always include Slack as an optional MCP

Build the optional MCP list dynamically. Only include MCPs that:
  - Were NOT already installed as recommended (Qdrant, Context7, Docker, GitHub are excluded)
  - Are relevant to the detected project stack OR are always-available options (Slack, Custom)

Present to PM:

```
Recommended setup complete!

Would you also like to configure any optional MCPs?
These are not required but can enhance your workflow:

  [ ] Slack MCP — PM notifications and approvals via Slack
      Requires: Slack app with bot token
  [ ] Playwright MCP — browser automation and testing
      {shown if: frontend framework detected}
  [ ] Postgres MCP — direct database access from Claude
      {shown if: PostgreSQL detected in deps or docker-compose}
  [ ] MinIO MCP — S3-compatible object storage management
      {shown if: MinIO/S3 detected in deps or docker-compose}
  [ ] Custom — add your own MCP servers

Select optional MCPs to install (comma-separated numbers, or Enter to skip):
```

- If PM selects any: process each using the corresponding Option 6 logic
  (6c for Slack, 6f auto-detect for Playwright/Postgres/MinIO, 6g for Custom)
- If PM presses Enter/skips: continue to Part 2

**Part 2: Additional non-MCP options**

After optional MCPs are handled (or skipped), present remaining options:

```
Additional options available:

  (4) CLAUDE.md — Generate project context file for Claude Code
      Adds AID markers to CLAUDE.md so Claude understands your project
      structure, conventions, and workflow.

  (10) Documentation Platform — Recommend and scaffold a docs platform
       Based on your project type. Creates docs/ + config skeleton.

Configure any of these? (select numbers, or Enter to skip)
```

Process selected options using existing Step 5 logic for each.
If PM presses Enter/skips: continue to Step 6.

NOTE: Option 5 (.gitignore) is NOT offered here — it becomes automatic
after Task A (selective .aid-o gitignore is applied during init).
NOTE: Option 11 (Skill Conflict Detection) is NOT offered here — it is
always included in the recommended batch.

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

- **Option 1:** Start a brainstorming run → create Plan in `.aid-o/01-plans/`
- **Option 2:** Ask for project type and generate basic scaffold
- **Option 3:** Just run `/aid-init`

### Step 7: Summary and Next Steps

After all selected options are configured, display the following styled
completion banner. Replace `{placeholders}` with actual session values.
Right-pad all content lines with spaces to maintain consistent frame width
(68 inner characters). Terminal width assumed: 80 columns (frame is 72 chars
including 2-space left indent).

```
  ╔══════════════════════════════════════════════════════════════════════╗
  ║                                                                    ║
  ║         ╔═══╗    A.I.D. Setup Complete                             ║
  ║         ║ + ║    ═════════════════════                             ║
  ║         ╚═══╝    AI Development Orchestrator                       ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Configured:  {N}/{total} options                                  ║
  ║  Workspace:   .aid-o/ (ready)                                      ║
  ║  Profile:     {detected_stack_summary}                             ║
  ║                                                                    ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║  WHAT'S NEXT?                                                      ║
  ╠══════════════════════════════════════════════════════════════════════╣
  ║                                                                    ║
  ║  Have an idea?    ->  /aid-brainstorm "your idea"                  ║
  ║                       Interactive design session -- AID asks        ║
  ║                       questions and produces a plan + EPIC draft.   ║
  ║                                                                    ║
  ║  Ready to build?  ->  Create EPIC in .aid-o/02-epics/              ║
  ║                   ->  /aid-plan-epic .aid-o/02-epics/your-epic.md  ║
  ║                   ->  /aid-run-epic                                ║
  ║                                                                    ║
  ║  Need help?       ->  /aid-help            full documentation      ║
  ║                   ->  /aid-help examples   step-by-step guides     ║
  ║                   ->  /aid-help commands   all available commands   ║
  ║                                                                    ║
  ║  Tip: Start with /aid-brainstorm -- the best way to explore ideas  ║
  ║       and let AID help you design before writing code.             ║
  ║                                                                    ║
  ╚══════════════════════════════════════════════════════════════════════╝
```

**Banner variable reference:**

| Placeholder | Source | Example |
|---|---|---|
| `{N}/{total}` | Count of configured options / total available | `5/12` |
| `{detected_stack_summary}` | From `project-profile.yaml` detected stack | `Node.js 20 + TypeScript + React + Docker` |

**Banner formatting rules:**
- The outer frame uses double-line box-drawing characters (`╔ ═ ╗ ║ ╠ ╣ ╚ ╝`), matching the FIRST AID banner style for visual consistency across AID commands
- The cross icon (`╔═══╗ ║ + ║ ╚═══╝`) is the AID branding mark -- it appears in a "loaded" state (with `+`) to signal a fresh, ready workspace
- Section dividers use `╠══...══╣` to separate the status block from the next-steps block
- All content lines are right-padded with spaces so the right border (`║`) aligns consistently
- If `{detected_stack_summary}` is longer than 46 characters, truncate with `...` to fit within the frame
- If no options were configured (user ran setup but skipped everything), show `0/{total} options` and still display the next-steps section

**Do NOT** end with just "Your project is ready." Always provide concrete,
actionable next steps with command examples.

## Reference Files

- `commands/aid-init.md` — workspace initialization (called internally)
- `defaults/policies/skill-conflicts.yaml` — known skill conflict pairs (used by Option 11)
- Plan P-20260216-b3a1, sections D-006 (Project Scanner) and D-007 (/aid-setup)

## Important

- **NEVER delete existing project files** — only create/modify AID configuration
- If `.aid-o/` already exists, do NOT re-run `/aid-init` unless user asks (skip and report)
- Re-run safety is handled by Step 0: Re-Run Detection at the beginning of this flow.
  If we reach later steps, PM has already approved the scope of this run.
- Detection is best-effort — if uncertain about a tool, ask the user
- For monorepos: detect all workspaces and configure gates for each relevant one

**Last Updated:** 2026-02-27
