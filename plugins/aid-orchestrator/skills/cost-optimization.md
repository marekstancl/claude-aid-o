# Cost Optimization -- Token & Latency Efficiency

**Version:** 0.1.0
**Skill:** cost-optimization
**Dependencies:** epic-orchestration, parallel-dispatch, agent-core

---

## BMK-001 Baseline (reference data)

6-step EPIC, 140 min active compute, ~3.5M tokens, ~$95.
89% of tokens consumed inside agent execution (tool calls, file reads, code generation).
Only 3.3% in dispatch prompts. Optimization must target agent execution first.

---

## Axis 1: Model Selection (HIGHEST IMPACT -- speed)

Assign the fastest model capable of each agent's task complexity.
On MAX plan (flat rate), cost per token is irrelevant. Sonnet is ~2-3x faster
output than Opus, making model selection a SPEED optimization, not a cost one.

### Model Tiers

| Tier | Model | Use for |
|------|-------|---------|
| Tier 1 | haiku | Utility: extract, validate, format |
| Tier 2 | sonnet | Review, analysis, docs, security audit |
| Tier 3 | opus (inherit) | Code generation, architecture, complex QA |

### Agent Model Assignments

| Agent | Current | Target | Rationale |
|-------|---------|--------|-----------|
| architect | opus | **opus** | Complex scaffolding, ADR decisions |
| domain | opus | **sonnet** | Schema/model writing is structured, not creative |
| backend | opus | **opus** | Full API implementation, complex logic |
| frontend | opus | **opus** | Component architecture, state management |
| qa | opus | **sonnet** | Test writing follows patterns, reads existing code |
| security | opus | **sonnet** | Security review is analysis, not generation |
| docs-writer | opus | **sonnet** | Documentation from existing code |
| code-reviewer | opus | **sonnet** | Analysis task |
| docs-reviewer | opus | **sonnet** | Validation task |
| curator | opus | **sonnet** | Backlog analysis |
| auditor | opus | **sonnet** | Project health analysis |
| gate-fixer | opus | **haiku** | Simple lint/format fixes |
| lessons-extractor | opus | **haiku** | Extract and format text |
| session-validator | opus | **haiku** | Schema validation |
| quality-gates-runner | opus | **haiku** | Run commands, check exit codes |
| project-scanner | opus | **sonnet** | Codebase analysis |
| observability | opus | **sonnet** | Monitoring setup |
| release | opus | **sonnet** | Release process (mostly scripted) |

**Speed impact (BMK-001 scenario):**

Steps 4-6 (QA, Security, Docs) consumed ~89% of agent tokens (~2.75M tokens).
Moving QA+Security+Docs from Opus to Sonnet:
- Sonnet produces ~2-3x faster output per token
- Estimated speed improvement: ~30-40% faster for those steps

Steps 1-3 (Architect, Domain, Backend) keep Opus for complex code generation.
Moving Domain to Sonnet saves additional time on structured model writing.

---

## Axis 2: Agent File Scoping (HIGHEST IMPACT -- speed + tokens)

89% of tokens are consumed inside agents (tool calls). Agents spend significant
time on Glob/Grep/Read operations to discover project structure. Providing an
explicit file scope in the dispatch eliminates this exploration overhead.

### File Scope in Dispatch Prompt

Each step in plan.json already defines `allowed_paths`. Extend this with
`relevant_files` -- an explicit list of files the agent should READ first:

```json
{
  "step_id": "step_3_backend",
  "role": "backend",
  "allowed_paths": ["app/routers/", "app/services/", "app/main.py"],
  "relevant_files": [
    "app/models/bookmark.py (ORM model -- from step_2)",
    "app/schemas/bookmark.py (Pydantic schemas -- from step_2)",
    "app/models/user.py (auth model -- from step_2)",
    "app/main.py (FastAPI app -- from step_1)"
  ]
}
```

### Rules for File Scoping

1. **Architect** generates the file manifest as part of its output
2. **Controller** extracts the manifest and includes relevant subset per step
3. **Agents** read `relevant_files` FIRST before any Glob/Grep exploration
4. **Agents** should NOT Glob the entire project tree -- only their allowed_paths

### Implementation in agent-core.md

Agents receiving a `relevant_files` list in their dispatch prompt:
1. Read ALL listed files FIRST (these are your primary inputs)
2. Only Glob/Grep within `allowed_paths` if you need additional context
3. NEVER Glob outside allowed_paths
4. Prefer targeted Read over broad Glob -- you already know the key files

**Estimated impact:**
- Reduces agent Glob/Grep operations by ~50-70%
- Each avoided Glob saves ~500-2000 tokens (tool result) + ~200 tokens (response)
- For a 38-min agent doing ~114 tool ops: saving 30-50 ops = ~30K-100K tokens
- **Across 6 agents: ~100K-400K tokens saved (~3-12% of total)**

---

## Axis 3: Dispatch Prompt Trimming (MEDIUM IMPACT)

The dispatch prompt is 3.3% of total but still worth optimizing for latency.

### Rule 1: Playbook Summary, Not Full Playbook

```
BAD (875 tokens): [full playbook pasted in prompt]
GOOD (50 tokens):
  ROLE: backend
  MISSION: Implement API endpoints and service layer.
  CONSTRAINTS: Only modify allowed_paths. No direct DB queries in routes.
  PLAYBOOK: Read defaults/playbooks/backend.md for details.
```

### Rule 2: Dependency Outputs Only

Include only direct-dependency step outputs, not ALL prior outputs.
BMK-001: steps 4-6 each received ~90-102K chars of prior output.
With deps-only: each gets ~30K chars (step_3 output only).
**Saves ~49K tokens across 6 dispatches.**

### Rule 3: EPIC Summary, Not Full EPIC

```
BAD (1,574 tokens): [full EPIC spec]
GOOD (100 tokens):
  GOAL: Personal Bookmark Manager REST API
  CONSTRAINTS: FastAPI, async SQLAlchemy, JWT auth, SQLite
  YOUR AC: [only this step's acceptance criteria]
```

### Rule 4: Memory Search top_k 3 (not 5)

When searching Qdrant for pre-step context, use top_k=3 instead of 5.
Fewer results = less context = faster first response.

### Rule 5: Cache Policy Reads

Read policy files ONCE at IDLE. Do not re-read per state transition:
- project-profile.yaml, gates.yaml, decision-policies.yaml, permissions.yaml

**Total dispatch savings: ~65K tokens (56.7% reduction on dispatch prompts)**

---

## Axis 4: Token Consumption Tracking & Qdrant Storage

Every EPIC run should record its token consumption profile in Qdrant for
cross-project analysis via /aid-analytics.

### What to Track

At DONE state, the Controller aggregates and stores:

```json
{
  "collection_name": "aid-memory",
  "data": "EPIC {epic_id} token profile: {total_tokens_estimated} total, {agent_execution_pct}% agent execution, {dispatch_pct}% dispatch, {controller_pct}% controller. Cost ~${estimated_cost}. Slowest: {slowest_step} ({slowest_duration} min, {slowest_tokens} tokens). Model mix: {models_used}.",
  "metadata": {
    "type": "metric",
    "metric_kind": "token_profile",
    "project_name": "{project_name}",
    "epic_id": "{epic_id}",
    "total_tokens_estimated": 0,
    "agent_execution_pct": 0,
    "dispatch_pct": 0,
    "controller_pct": 0,
    "step_count": 0,
    "active_compute_minutes": 0,
    "models_used": {"opus": 0, "sonnet": 0, "haiku": 0},
    "estimated_cost_usd": 0,
    "timestamp": "{ISO 8601}"
  }
}
```

### Per-Step Token Estimate

For each step, store:
```json
{
  "type": "metric",
  "metric_kind": "step_token_profile",
  "step_id": "{step_id}",
  "model": "{opus|sonnet|haiku}",
  "dispatch_prompt_tokens": 0,
  "estimated_execution_tokens": 0,
  "duration_seconds": 0,
  "tool_operations_estimated": 0,
  "files_in_scope": 0
}
```

The Controller estimates execution tokens from:
- `duration_seconds x ops_per_minute_estimate x avg_tokens_per_op`
- Where ops_per_minute ~ 3, avg_tokens_per_op ~ 2600 (from BMK-001 baseline)

This is an ESTIMATE, not exact API billing. Exact API usage data is not
available to the Controller. The estimate provides useful relative comparison
across steps and EPICs for optimization decisions.

---

## Combined Expected Impact (MAX plan -- speed is the metric, not cost)

| Optimization Axis | Token Reduction | Speed Impact | Why |
|---|---|---|---|
| Model selection (QA,Security,Docs->Sonnet, Utility->Haiku) | -- | **Sonnet ~2-3x faster output** | Sonnet has higher tokens/sec than Opus |
| Agent file scoping (fewer Glob/Grep) | ~100K-400K | **-20-40% duration** | Fewer tool round-trips = less wall-clock time |
| Dispatch prompt trimming | ~65K | -5-10% | Smaller initial context = faster first response |
| Token tracking to Qdrant | ~0 (overhead) | ~0 | Data collection for /aid-analytics |
| **COMBINED** | **~165K-465K** | **-30-50% faster** | |

For BMK-001 (140 min active compute): optimized run ~**70-100 min** estimated.

---

## Reference Files

| File | Relevance |
|------|-----------|
| `skills/epic-orchestration.md` | EXECUTING + DONE state (dispatch, metrics) |
| `skills/parallel-dispatch.md` | Dispatch prompt template, file scoping |
| `skills/agent-core.md` | File scope execution rules |
| `skills/planner.md` | relevant_files generation per step |
| `agents/*.md` | Model assignments (frontmatter) |

---

**Version:** 0.1.0
**Last Updated:** 2026-02-19
