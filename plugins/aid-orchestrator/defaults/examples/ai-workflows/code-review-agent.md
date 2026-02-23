---
type: example
archetype: "code-review-agent"
frameworks: [langgraph, langchain, fastapi]
complexity: high
description: "Automated code review agent with multi-agent analysis, security scanning, and structured feedback using LangGraph"
platforms: [langgraph]
ui: none
---

# Example EPIC: Automated Code Review Agent

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Automating first-pass code review for pull requests
- Need multi-aspect review: correctness, security, performance, style
- Want structured feedback with file-level and line-level comments
- Building a multi-agent system where specialist agents review different aspects

### When NOT to use
- Simple linting or formatting (use ESLint/Prettier/Ruff directly)
- Security-only scanning (use dedicated SAST tools like Semgrep)
- Reviewing infrastructure/config changes (IaC tools are more appropriate)
- Codebase is proprietary and cannot be sent to external LLMs

Tech stack: LangGraph multi-agent supervisor + LangChain + FastAPI.
Greenfield: new `{backend_dir}/code_review/` module.
Pattern: LangGraph supervisor with specialist sub-agents (correctness, security, style).

## Goal

When complete, the system accepts code diffs (via API or GitHub webhook),
routes them to specialist reviewer agents (correctness, security, style),
aggregates findings, and returns structured review comments with severity
levels and line references. Integrates with GitHub PR comments via API.

## Scope

### Allowed files/paths
- `{backend_dir}/code_review/`
  - `{backend_dir}/code_review/supervisor.py` — LangGraph supervisor graph
  - `{backend_dir}/code_review/agents/` — specialist agent definitions
  - `{backend_dir}/code_review/tools.py` — code analysis tools
  - `{backend_dir}/code_review/schemas.py` — ReviewComment, ReviewReport models
  - `{backend_dir}/code_review/routes.py` — FastAPI endpoints
  - `{backend_dir}/code_review/github.py` — GitHub PR comment integration
- `{backend_dir}/tests/test_code_review/`

### Forbidden zones
- `{backend_dir}/core/` (import only)
- GitHub Actions workflows (separate concern)

## Artifacts

- endpoint: POST /api/v1/review (submit diff for review)
- endpoint: POST /api/v1/review/webhook (GitHub PR webhook handler)
- endpoint: GET /api/v1/review/{review_id} (get review results)
- graph: LangGraph supervisor → [correctness_agent, security_agent, style_agent]

## Constraints

- Tenant-safe: yes
- Budget: $20 max LLM cost

## DoD Gates

- tests_pass
- lint_pass
- security_scan_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] Accepts unified diff format via POST /api/v1/review
- [ ] [backend] Supervisor dispatches to 3 specialist agents in parallel (fan-out)
- [ ] [backend] Each agent returns ReviewComment[] with: file, line, severity, message, category
- [ ] [backend] Supervisor aggregates and deduplicates findings into ReviewReport
- [ ] [backend] GitHub webhook triggers review and posts comments on PR
- [ ] [backend] Severity levels: critical, warning, info, suggestion
- [ ] [qa] Unit tests for each specialist agent with sample code diffs
- [ ] [qa] Integration test: submit diff → receive aggregated review with all 3 categories

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design supervisor graph, agent contracts, ReviewComment schema, GitHub integration | — | — |
| 2 | backend | Implement specialist agents: correctness, security, style analysis | 1 | — |
| 3 | backend | Implement LangGraph supervisor with parallel fan-out to agents + aggregation | 2 | — |
| 4 | backend | Implement FastAPI endpoints + GitHub webhook + PR comment posting | 3 | — |
| 5 | security | Review agent prompts for injection risks; validate GitHub token scoping | 4 | group-1 |
| 6 | qa | Write tests for agents and integration | 4 | group-1 |
| 7 | docs | API docs + GitHub App setup guide | 5, 6 | — |

## Docker Compose

```yaml
services:
  api:
    build:
      context: ./{backend_dir}
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      GITHUB_TOKEN: ${GITHUB_TOKEN}
      GITHUB_WEBHOOK_SECRET: ${GITHUB_WEBHOOK_SECRET}
```

## Notes

- Use LangGraph supervisor pattern: `create_supervisor([correctness, security, style])`
- Parallel fan-out via `Send()` API dispatches all 3 agents simultaneously
- Each specialist agent has a focused system prompt and domain-specific tools
- GitHub PR comments: use `gh api repos/{owner}/{repo}/pulls/{pr}/comments`
- Limit diff size per review (e.g., 5000 lines) to stay within context window
- Consider caching reviews by commit SHA to avoid re-reviewing unchanged code
