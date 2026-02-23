---
type: example
archetype: "ai-workflow-automation"
frameworks: [n8n, postgresql, openai]
complexity: medium
description: "AI-powered workflow automation with webhook triggers, LLM classification, and multi-channel notifications using N8N"
platforms: [n8n]
ui: none
---

# Example EPIC: N8N AI-Powered Workflow Automation

> **NOTE:** This is a community example EPIC. Adapt paths, model names, and
> configuration to your project before running. Replace all `{placeholder}`
> values with your actual project paths.

## Context

### When to use
- Automating business processes that require AI classification, summarization, or decision-making
- Team needs visual, low-code workflow building with drag-and-drop AI nodes
- Integrating AI capabilities into existing webhook-driven pipelines (Slack, GitHub, email, CRM)
- Building approval workflows with human-in-the-loop using N8N Wait node
- Non-engineers need to modify workflow logic without touching Python code

### When NOT to use
- Building a conversational chatbot with multi-turn memory (use LangChain/LangGraph instead)
- Complex multi-agent reasoning requiring custom state machines (use LangGraph)
- Need fine-grained control over LLM prompting, retrieval, or chain composition (use LangChain)
- High-throughput real-time inference (>100 requests/second) where N8N's Node.js runtime is a bottleneck
- Custom ML model training or fine-tuning workflows

Tech stack: N8N 1.70+ (self-hosted via Docker), PostgreSQL 16 (workflow metadata + execution history), OpenAI GPT-4o (via AI Agent node), Slack/Gmail for notifications.
Greenfield: new N8N instance with workflow JSON files. No prior N8N setup assumed.
Pattern: Webhook Trigger -> AI Agent node (LangChain-backed with OpenAI LLM + Buffer Window Memory + tools) -> conditional branching (IF/Switch) -> multi-channel notification (Slack + Email) -> Wait node for human approval.

## Goal

When complete, an N8N instance processes incoming webhook events, classifies them using the
AI Agent node with an OpenAI LLM, routes to appropriate handling branches via Switch node,
generates AI-powered responses or summaries, sends notifications via Slack and email, and
optionally pauses for human approval via Wait node before taking final action. Workflows
are version-controlled as JSON files and deployed via LANGFLOW_LOAD_FLOWS_PATH pattern.

## Scope

### Allowed files/paths
- `{project_root}/workflows/` (N8N workflow JSON files)
  - `{project_root}/workflows/ai-classifier.json` — main AI classification workflow
  - `{project_root}/workflows/notification-sender.json` — reusable multi-channel notification sub-workflow
  - `{project_root}/workflows/approval-handler.json` — human-in-the-loop approval sub-workflow
- `{project_root}/docker-compose.yml` — N8N + PostgreSQL production stack
- `{project_root}/.env` — environment variables and secrets
- `{project_root}/docs/workflows.md` — workflow documentation and operational guide

### Forbidden zones
- N8N internal database schemas (managed by N8N automatically)
- N8N core node source code (use built-in nodes only)
- External service configurations (Slack apps, Gmail OAuth -- configure via N8N credentials UI)

## Artifacts

- workflow: AI Classifier (Webhook -> AI Agent -> Switch -> actions)
- workflow: Notification Sender (sub-workflow: Slack + Email parallel branches)
- workflow: Approval Handler (sub-workflow: Wait node + callback URL)
- webhook: POST /webhook/ai-classifier (production webhook URL)
- config: `.env` keys -- N8N_ENCRYPTION_KEY, POSTGRES_PASSWORD, N8N_HOST, WEBHOOK_URL, OPENAI_API_KEY
- doc: `docs/workflows.md`

## Constraints

- Tenant-safe: yes (workflow scoped, webhook paths unique per workflow)
- Audit trail: yes (N8N execution history with full input/output logging)
- Budget: $15 max LLM cost
- Execution mode: regular (single server) -- upgrade to queue mode with Redis for scaling

## DoD Gates

- tests_pass
- lint_pass
- docs_updated

## Acceptance Criteria

- [ ] [backend] Webhook trigger accepts POST requests with JSON payload and responds within 30s
- [ ] [backend] AI Agent node classifies incoming events into categories using OpenAI LLM with structured system prompt
- [ ] [backend] Switch node routes to correct branch based on AI classification result (minimum 3 categories)
- [ ] [backend] Notification sub-workflow sends to both Slack channel and email in parallel
- [ ] [backend] Approval workflow pauses execution via Wait node and resumes on approve/reject callback
- [ ] [backend] All workflows use Buffer Window Memory (k=5) for multi-turn context within a session
- [ ] [infra] Docker Compose deploys N8N + PostgreSQL with health checks, persistent volumes, and encryption key
- [ ] [infra] N8N_RUNNERS_ENABLED=true for code execution support in AI workflows
- [ ] [qa] Manual test: send webhook payload, verify classification, notification delivery, and approval flow
- [ ] [docs] docs/workflows.md describes each workflow purpose, trigger configuration, and credential setup

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | architect | Design workflow topology: trigger types, AI agent configuration, branching logic, sub-workflow boundaries, credential plan | — | — |
| 2 | backend | Build AI Classifier workflow: Webhook trigger, AI Agent node (OpenAI LLM + system prompt for classification), Switch node routing | 1 | — |
| 3 | backend | Build Notification Sender sub-workflow: Execute Workflow Trigger, parallel Slack + Email branches, dynamic message formatting | 1 | A |
| 4 | backend | Build Approval Handler sub-workflow: Wait node with callback URL, IF node for approve/reject, timeout handling | 1 | A |
| 5 | backend | Integrate sub-workflows: connect classifier -> notification sender and classifier -> approval handler via Execute Workflow nodes | 2, 3, 4 | — |
| 6 | devops | Configure Docker Compose: N8N + PostgreSQL, env vars, health checks, volume persistence, encryption key management | 1 | B |
| 7 | qa | Manual testing: end-to-end webhook -> classify -> notify -> approve flow with test payloads | 5, 6 | — |
| 8 | docs | Write operational guide: workflow descriptions, credential setup, webhook URLs, monitoring via /healthz and /metrics | 7 | — |

## Docker Compose

```yaml
version: "3.9"

services:
  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  n8n:
    image: docker.n8n.io/n8nio/n8n
    ports:
      - "5678:5678"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - GENERIC_TIMEZONE=${TIMEZONE:-UTC}
      - TZ=${TIMEZONE:-UTC}
      - N8N_HOST=${N8N_HOST:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-http}
      - WEBHOOK_URL=${WEBHOOK_URL:-http://localhost:5678/}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_METRICS=true
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - EXECUTIONS_DATA_MAX_AGE=168
      - N8N_LOG_LEVEL=info
    volumes:
      - n8n_data:/home/node/.n8n
    restart: always

volumes:
  postgres_data:
  n8n_data:
```

## Notes

- **Encryption key:** The `N8N_ENCRYPTION_KEY` encrypts all stored credentials. Never lose this key -- losing it makes all saved credentials (API keys, OAuth tokens) unrecoverable. Generate with `openssl rand -hex 32`.
- **Queue mode scaling:** For high-throughput, switch to `EXECUTIONS_MODE=queue` and add Redis + worker instances. Workers: `docker run ... n8n worker`. Webhook processor: `docker run -p 5679:5678 ... n8n webhook`.
- **Workflow version control:** Export workflows as JSON via N8N API (`GET /api/v1/workflows/{id}`) or UI export. Store in git. Deploy to production via `POST /api/v1/source-control/pull` with GitHub Actions CI/CD.
- **AI Agent tools:** The AI Agent node accepts tool sub-nodes: HTTP Request (REST API calls), Code (JavaScript/Python execution), Wikipedia, Calculator, Vector Store Retriever (RAG). Connect via the tools port.
- **MCP integration:** N8N supports MCP client nodes, connecting AI agents to any MCP server (GitHub, filesystem, database) without custom node development.
- **Monitoring:** Enable `N8N_METRICS=true` for Prometheus-compatible `/metrics` endpoint. Use `QUEUE_HEALTH_CHECK_ACTIVE=true` for `/healthz` on workers. Configure an Error Trigger workflow for Slack alerting on failures.
- **Form triggers:** For internal tools, use N8N's Form Trigger node instead of webhooks -- it generates hosted HTML forms with no frontend development required.
