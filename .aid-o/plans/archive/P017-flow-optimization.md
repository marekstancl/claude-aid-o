---
id: P017
type: plan
status: done
created: 2026-02-27
author: PM + AI
---

# Plan: Flow Optimization & Token Efficiency

## Context

AID orchestration pipeline dispatches all agents with the same model (opus) regardless of task complexity — a docs step writing CHANGELOG costs the same as an architect step designing API contracts. Knowledge and memory context blocks are injected into every agent dispatch regardless of whether the step benefits from them. There is no per-step usage tracking, so optimization decisions are blind. The dispatch prompt includes full EPIC specification and full plan.json content even when the agent only needs its own step section.

`cost-optimization.md` documents detailed model tier assignments and dispatch trimming strategies that reduce dispatch prompt size by an estimated ~57%, but none of this is wired into the actual dispatch pipeline. The plan schema (`plan.schema.json`) has no `model` or `context_scope` fields. The stage log has no token or efficiency metrics.

**Predecessor:** P013-flow-optimization.md (replaced — unrealistic 40-60% target, missing infrastructure steps)

**Brainstorming split already completed:** `brainstorming.md` (568 lines) split into `brainstorming.md` (core, 568 lines), `brainstorming-workflow.md` (workflow detection + Docker/MCP, separate file), and `brainstorming-knowledge.md` (knowledge acquisition, separate file). This work was done in a prior session and is NOT repeated in this plan.

## Goal

Establish a continuous improvement loop for AID pipeline speed: measure dispatch prompt sizes and step durations with tiktoken estimation, apply model tiering and selective context injection to reduce overhead without degrading quality, and install a permanent efficiency guardrail in `/aid-audit` that alerts on regression.

## Scope

**In scope:**
- Tiktoken-based token estimation utility for dispatch prompt measurement
- `dispatch-config.yaml` with model tier assignments, context injection defaults, and budget alert thresholds
- Plan schema extension (`model`, `context_scope` fields per step)
- Planner model assignment (populate `model` and `context_scope` from `dispatch-config.yaml`)
- Usage tracking in `stage_log.jsonl` and `plan_progress.json`
- Baseline benchmark on existing EPIC
- Model tiering wiring in dispatch protocol (pass `model` to Task tool)
- Selective context injection (knowledge/memory only for architect, domain, security, backend roles)
- Dispatch prompt trimming (step-scoped content, not full EPIC/plan)
- Before/after comparison measurement
- Efficiency guardrail in `/aid-audit`
- CHANGELOG and documentation updates

**Out of scope:**
- Brainstorming file splitting (already done)
- GUI token dashboard (P016 Pipeline Theater)
- Agent SDK migration
- Real-time cost billing or API-level token tracking (plugin runs on subscription, not API keys)
- Automated model selection tuning (manual via dispatch-config.yaml)

**Dependencies:**
- None — P012 step 3 (split epic-orchestration.md) is already complete

## Approach

### Option A: Infrastructure-First (Chosen)

EPIC 1: Baseline measurement + infrastructure (schema extension, dispatch-config.yaml, tiktoken tracking). EPIC 2: Wire optimizations (model tiering, selective context, prompt trimming), re-measure, install guardrail. Two-phase approach ensures data-driven optimization with a baseline checkpoint.

**Pros:**
- Data-driven — optimization decisions guided by baseline metrics
- Infrastructure is reusable — tracking persists beyond this plan
- EPIC 1 is low risk (measures and prepares, does not change dispatch behavior)
- Continuous improvement loop is the output — not a one-time optimization

**Cons:**
- EPIC 1 alone does not produce any speed improvement
- Two benchmark runs add time

### Option B: Optimize-First (Rejected)

Wire model tiering and selective context immediately, add tracking later. Rejected because optimizing without baseline data means no way to measure impact, and quality degradation from model tiering would be undetectable without retry rate baseline.

### Option C: Incremental Quick-Wins (Rejected)

Single EPIC with benchmark after each optimization step. Rejected because repeated benchmark runs (15-30 min each) after every step is prohibitively slow, and the single-EPIC scope (~12 steps) risks mid-run failure.

**Decision:** Option A — measure first, then optimize with data. The baseline checkpoint between EPICs allows course correction.

## Architecture

### Dispatch Pipeline Extension

```
Current Pipeline:
  Controller → dispatch-protocol.md → agent prompt → Task tool (opus always)

Extended Pipeline:
  Controller → dispatch-protocol.md
    1. Read dispatch-config.yaml (model tier + context defaults)
    2. Read step from plan.json (step.model, step.context_scope)
    3. Assemble dispatch prompt:
       - Step objective + acceptance criteria + allowed_paths
       - Plan section (via plan_ref — already exists)
       - Previous step outputs (filtered by context_scope.previous_outputs)
       - Knowledge context (only if context_scope.knowledge == true)
       - Memory context (only if context_scope.memory == true)
    4. Estimate input tokens via js-tiktoken (cl100k_base encoding)
    5. Log budget warning if estimate > budget_alerts threshold
    6. Dispatch via Task tool (with model parameter from step.model)
    7. On completion: log usage to stage_log.jsonl
```

### Continuous Improvement Loop

```
/aid-audit → reads stage_log.jsonl usage data from recent runs
  → computes per-role averages (estimated tokens, duration)
  → compares current run vs. historical averages
  → flags regressions (>2x baseline for any step type)
  → outputs "Token Efficiency" section in audit report
  → feeds back into dispatch-config.yaml tuning (manual PM adjustment)
```

### Integration Points

```
dispatch-config.yaml (new, defaults/policies/)
  ↑ read by planner.md (step.model + step.context_scope population)
  ↑ read by dispatch-protocol.md (model lookup fallback, budget thresholds)
  ↑ read by audit skill (baseline comparison thresholds)
  ↑ deployed by aid-init.md (dynamic defaults/policies/ scanning)

plan.schema.json (extended)
  ↑ new fields: model, context_scope per step
  ↑ backward compatible — fields optional, defaults to opus + all context

stage_log.jsonl (extended)
  ↑ new usage object per dispatch_complete entry
  ↑ existing entries unchanged (backward compatible)

plan_progress.json (extended)
  ↑ new usage_summary object at run end
```

## Data Model

### Plan Schema Extension (`plan.schema.json`)

Per-step field additions (all optional for backward compatibility):

```json
{
  "model": {
    "type": "string",
    "enum": ["haiku", "sonnet", "opus"],
    "description": "Model tier for this step, from dispatch-config.yaml role lookup"
  },
  "context_scope": {
    "type": "object",
    "properties": {
      "knowledge": {
        "type": "boolean",
        "default": true,
        "description": "Inject knowledge context from Qdrant for this step"
      },
      "memory": {
        "type": "boolean",
        "default": true,
        "description": "Inject memory context from Qdrant for this step"
      },
      "previous_outputs": {
        "type": "string",
        "enum": ["all", "direct", "none"],
        "default": "direct",
        "description": "How much dependency output to inject: all=every completed step, direct=only depends_on steps, none=skip"
      }
    },
    "additionalProperties": false
  }
}
```

### dispatch-config.yaml (new file)

```yaml
# Model tier assignments per AID role
# Agents dispatched with the model specified for their role
# Override per-project by editing .aid-o/03-config/policies/dispatch-config.yaml
model_tiers:
  architect: opus        # Complex scaffolding, API design
  domain: sonnet         # Structured writing, domain modeling
  backend: opus          # Complex logic, state management
  frontend: sonnet       # UI implementation, component work
  qa: sonnet             # Pattern-based testing
  security: sonnet       # Analysis, vulnerability scanning
  observability: sonnet  # Monitoring, alerting setup
  docs-writer: haiku     # CHANGELOG, README, documentation
  release: haiku         # Version bumps, tag creation
  code-reviewer: sonnet  # Code review analysis
  docs-reviewer: sonnet  # Documentation review
  curator: sonnet        # Improvement proposals
  auditor: sonnet        # Project health audit
  gate-fixer: haiku      # Simple gate failure fixes
  lessons-extractor: haiku  # Extract lessons from completed run
  run-validator: haiku   # Validate run file completeness
  quality-gates-runner: haiku  # Execute quality gate commands

# Context injection defaults per role
# Roles not listed here get knowledge: false, memory: false
context_defaults:
  knowledge:             # Only these roles receive knowledge context
    - architect
    - domain
    - security
  memory:                # Only these roles receive memory context
    - architect
    - domain
    - backend
    - security
  previous_outputs: "direct"  # Default for all roles: only direct dependencies

# Budget alert thresholds (estimated input tokens)
# Warning logged to stage_log when dispatch prompt exceeds threshold
# Advisory only — does not block dispatch
budget_alerts:
  haiku: 3000
  sonnet: 10000
  opus: 20000
  default: 12000
```

### stage_log.jsonl Usage Entry Extension

New `usage` object added to `dispatch_complete` action entries:

```json
{
  "timestamp": "2026-02-27T14:30:00.000Z",
  "state": "EXECUTING",
  "step": "step_3_backend",
  "action": "dispatch_complete",
  "details": "Step completed successfully",
  "result": "pass",
  "usage": {
    "model": "opus",
    "estimated_input_tokens": 8420,
    "estimated_output_tokens": 2100,
    "dispatch_prompt_chars": 28500,
    "context_sources": ["plan_section", "memory", "prev_step_2"],
    "duration_ms": 45200,
    "budget_alert": false
  }
}
```

Existing stage_log entries without `usage` field remain valid (backward compatible).

### plan_progress.json Aggregate Usage

New top-level `usage_summary` object populated at run end (DONE state):

```json
{
  "usage_summary": {
    "total_estimated_input_tokens": 84200,
    "total_estimated_output_tokens": 21000,
    "total_duration_ms": 452000,
    "steps_count": 8,
    "models_used": { "opus": 3, "sonnet": 4, "haiku": 1 },
    "per_step": [
      {
        "step": "step_1_architect",
        "model": "opus",
        "estimated_input_tokens": 12000,
        "estimated_output_tokens": 3000,
        "duration_ms": 65000,
        "budget_alert": false
      }
    ]
  }
}
```

## Testing Strategy

### Tiktoken Accuracy Validation
- Run 1 EPIC with CLI `--verbose`, capture real token counts from stderr
- Compare against tiktoken estimates for same dispatch prompts
- Accept if drift < 15% (sufficient for trend tracking, not billing)

### Quality Regression Guard
After EPIC 2 optimizations are active, compare against baseline:
- Retry rate must not increase (same or lower)
- Gate failure rate must not increase
- Step completion rate must remain 100%
- If any metric degrades, revert to opus for affected role in `dispatch-config.yaml`

### Backward Compatibility
- Plans without `model`/`context_scope` fields must work (dispatcher defaults to opus + all context)
- Missing `dispatch-config.yaml` falls back to all-opus configuration
- Existing `stage_log.jsonl` entries without `usage` field are valid (no migration needed)

### Benchmark Protocol
- Use same EPIC for both Step 6 (baseline) and Step 10 (re-measure)
- Run 2x each to account for LLM non-determinism (±15-20% variance)
- Compare averages, not single runs
- Report format: table with before/after per-step metrics + totals

### Guardrail Validation
- Inject synthetic high-usage stage_log entries into a test evidence directory
- Run `/aid-audit`, verify "Token Efficiency" section appears in report
- Verify alert triggers when any step exceeds 2x baseline average
- Verify no false alert for normal usage values

## Constraints

- AID is a Claude Code plugin — no direct API token access (subscription auth, not per-token billing)
- Tiktoken `cl100k_base` encoding is an approximation of Claude's tokenizer — ±10-15% drift acceptable for trend tracking
- `dispatch-config.yaml` must be per-project customizable (copied to `.aid-o/03-config/policies/` via `/aid-init`)
- Model tiering must be configurable — PM can override any role→model mapping
- Usage tracking must not add latency to agent dispatch (estimate before dispatch, log after completion)
- Budget alerts are advisory (warning in stage_log), not enforcement (no hard fail on budget exceed)
- Guardrail runs automatically in `/aid-audit` — no separate command needed
- All changes must be backward compatible — existing EPICs, plans, and stage logs must work unchanged
- Task tool `model` parameter must be verified to work (if not supported, document as known limitation and skip model tiering wiring)

## Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Tiktoken cl100k_base drift from Claude tokenizer | medium | low | Calibrate once against CLI verbose output; ±15% acceptable for trend tracking |
| Task tool ignores model parameter | medium | high | Verify in Step 7; if not supported, document as limitation, keep dispatch-config.yaml for future use |
| Selective context removal causes agent retries | medium | medium | Start conservative: architect/domain/security keep all context; expand restrictions only after baseline confirms safety |
| Benchmark EPIC not representative | low | medium | Document which EPIC was used; run 2x for variance; use medium-size EPIC (5-8 steps) |
| dispatch-config.yaml schema drift from role list | low | medium | Validate against known roles list in planner; warn on unknown role |
| Prompt trimming removes info agent actually needed | medium | medium | Keep plan_ref section injection (proven working); trim only full EPIC spec and full plan.json that are redundant with plan_ref |

## Success Criteria

- Per-step usage metrics (estimated tokens, model, duration, context sources) logged in `stage_log.jsonl` for every dispatch
- Aggregate `usage_summary` in `plan_progress.json` at run end
- `dispatch-config.yaml` deployed and read by planner + dispatcher
- Plan.json steps populated with `model` and `context_scope` fields
- `/aid-audit` reports "Token Efficiency" section with per-role averages and regression alerts
- Baseline and post-optimization benchmark reports saved in evidence directory
- Retry rate and gate failure rate do not increase after optimization
- Continuous improvement loop operational: measure → optimize → measure → guard

## Implementation Steps

### Step 1: Tiktoken Integration

**Objective:** Create a token estimation utility using `js-tiktoken` that can estimate input token count for any text string, providing the measurement foundation for all subsequent optimization steps.

**Files:**
- Create: `plugins/aid-orchestrator/skills/token-estimator.md` — skill document defining the `estimateTokens(text)` function signature, encoding choice (cl100k_base), and usage protocol
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~42-88) — add reference to token-estimator skill in the dispatch assembly section

**Architecture Context:**
This step creates the measurement capability that Steps 5, 6, and 10 depend on. The token estimator is a pure function that takes a text string and returns an estimated token count using the `cl100k_base` encoding (closest available approximation to Claude's tokenizer). It is defined as a skill document (not executable code) because AID is a Claude Code plugin — agents implement the function inline during dispatch. The dispatch protocol references this skill to ensure consistent estimation across all dispatches.

**Implementation Detail:**

1. Create `skills/token-estimator.md` with:
   ```
   ## Token Estimation Protocol

   When estimating tokens for dispatch prompt measurement:
   1. Use cl100k_base encoding (tiktoken)
   2. Function signature: estimateTokens(text: string) → number
   3. For dispatch prompts: estimate the full assembled prompt BEFORE dispatch
   4. For response estimation: count characters in agent output, divide by 4 (rough heuristic)
   5. Log both estimates in the usage entry (see dispatch-protocol.md)

   ## Estimation Accuracy
   - cl100k_base vs Claude tokenizer: ±10-15% drift
   - Acceptable for trend tracking and regression detection
   - NOT suitable for billing or hard budget enforcement

   ## Calibration
   - On first use: compare estimate vs CLI --verbose actual token count
   - If drift > 20%: apply correction factor (multiply estimate by actual/estimated ratio)
   - Store correction factor in dispatch-config.yaml under `token_estimation.correction_factor`
   ```

2. In `dispatch-protocol.md`, add a reference after the dispatch assembly section (after line ~88):
   ```
   ## Token Estimation
   After assembling the dispatch prompt and BEFORE dispatching the agent,
   estimate input tokens using the protocol in skills/token-estimator.md.
   Store the estimate for logging in the usage entry after dispatch completes.
   ```

**Error Handling:**
- If tiktoken encoding fails (malformed text, encoding not available): log warning, set estimated tokens to -1, continue with dispatch (estimation is non-blocking)
- If correction factor in dispatch-config.yaml is invalid or missing: use 1.0 (no correction)

**Edge Cases:**
- Empty dispatch prompt (should not happen but defensive): return 0 tokens, log warning
- Very large dispatch prompt (>50K tokens estimated): log budget alert, continue dispatch
- Non-UTF8 characters in prompt: tiktoken handles gracefully, no special handling needed

**Dependencies:**
- No dependencies — can start independently

**Acceptance Criteria:**
- [ ] `skills/token-estimator.md` exists with estimation protocol, accuracy notes, and calibration instructions
- [ ] `dispatch-protocol.md` references token-estimator skill in the dispatch assembly section
- [ ] Estimation function is defined as pure function (text → number) with cl100k_base encoding

**Effort:** S
**AID Role:** architect

---

### Step 2: dispatch-config.yaml Creation

**Objective:** Create the `dispatch-config.yaml` policy file with model tier assignments per role, context injection defaults, and budget alert thresholds — the central configuration for all optimization decisions.

**Files:**
- Create: `plugins/aid-orchestrator/defaults/policies/dispatch-config.yaml` — model tiers, context defaults, budget alerts as defined in the Data Model section
- Modify: `plugins/aid-orchestrator/commands/aid-init.md` (lines ~72-77) — verify dynamic scanning includes new file (it should automatically since aid-init scans `defaults/policies/*`)

**Architecture Context:**
This file is the configuration hub for model tiering (Step 7), selective context injection (Step 8), and budget alerts (Step 5). It lives in `defaults/policies/` and is copied to `.aid-o/03-config/policies/` by `/aid-init` via dynamic directory scanning (aid-init.md lines 72-77 already scan `defaults/policies/*` and copy new files). Projects customize their copy; the default provides sensible starting values from `cost-optimization.md` lines 32-51.

**Implementation Detail:**

1. Create `defaults/policies/dispatch-config.yaml` with the exact content from the Data Model section above (model_tiers, context_defaults, budget_alerts). Add a header comment:
   ```yaml
   # Dispatch Configuration — Model Tiering, Context Injection, Budget Alerts
   # Customize per-project in .aid-o/03-config/policies/dispatch-config.yaml
   # See: skills/cost-optimization.md for tier rationale
   # See: skills/dispatch-protocol.md for how these values are consumed
   ```

2. Add `token_estimation` section for calibration:
   ```yaml
   # Token estimation calibration
   token_estimation:
     encoding: "cl100k_base"
     correction_factor: 1.0   # Adjust after calibration against CLI --verbose
   ```

3. Verify `commands/aid-init.md` dynamic scanning — read lines 72-77 to confirm `defaults/policies/*` glob pattern. If the pattern is present, no modification needed (new file is picked up automatically). If the pattern is missing or hardcoded, add `dispatch-config.yaml` to the copy list.

**Error Handling:**
- If `dispatch-config.yaml` is malformed YAML: planner and dispatcher fall back to all-opus, all-context defaults. Log warning with parse error details.
- If a role in the file doesn't match the known role enum: log warning during plan generation, use opus as default for unknown roles.

**Edge Cases:**
- `/aid-init` run on existing project that already has older config files: dynamic scanning copies only new files, does not overwrite existing — so a project with a customized older `dispatch-config.yaml` keeps their customizations
- Role added to AID in the future but not in `dispatch-config.yaml`: planner falls back to opus (safe default)
- Empty `context_defaults.knowledge` list: no roles receive knowledge context (valid configuration for projects without Qdrant)

**Dependencies:**
- No dependencies — can start independently (parallel with Step 1)

**Acceptance Criteria:**
- [ ] `defaults/policies/dispatch-config.yaml` exists with all 17 role→model mappings from the Data Model section
- [ ] File includes `context_defaults` with knowledge (3 roles), memory (4 roles), and previous_outputs ("direct")
- [ ] File includes `budget_alerts` with per-model thresholds and default
- [ ] File includes `token_estimation` section with encoding and correction_factor
- [ ] `/aid-init` copies the file to `.aid-o/03-config/policies/` when run on a project

**Effort:** S
**AID Role:** architect

---

### Step 3: Plan Schema Extension

**Objective:** Add `model` and `context_scope` fields to `plan.schema.json` so that generated plan.json files can carry per-step model and context injection configuration.

**Files:**
- Modify: `plugins/aid-orchestrator/defaults/templates/plan.schema.json` (lines ~33-113) — add `model` and `context_scope` properties to the step object definition

**Architecture Context:**
The plan schema defines the structure of `plan.json` files consumed by the Controller state machine during EPIC execution. Adding `model` and `context_scope` fields enables the planner (Step 4) to populate per-step configuration and the dispatcher (Steps 7-8) to read and act on it. Both fields are optional with defaults (opus, all context) to maintain backward compatibility with existing plan.json files.

**Implementation Detail:**

1. In `plan.schema.json`, locate the step properties object (lines ~33-113). After the `acceptance_criteria` property, add:
   ```json
   "model": {
     "type": "string",
     "enum": ["haiku", "sonnet", "opus"],
     "default": "opus",
     "description": "Model tier for this step, populated from dispatch-config.yaml role lookup"
   },
   "context_scope": {
     "type": "object",
     "default": { "knowledge": true, "memory": true, "previous_outputs": "direct" },
     "properties": {
       "knowledge": {
         "type": "boolean",
         "default": true,
         "description": "Whether to inject knowledge context from Qdrant"
       },
       "memory": {
         "type": "boolean",
         "default": true,
         "description": "Whether to inject memory context from Qdrant"
       },
       "previous_outputs": {
         "type": "string",
         "enum": ["all", "direct", "none"],
         "default": "direct",
         "description": "How much dependency output to inject"
       }
     },
     "additionalProperties": false
   }
   ```

2. Do NOT add `model` or `context_scope` to the `required` array — they must remain optional for backward compatibility.

**Error Handling:**
- Invalid `model` value in plan.json (not in enum): dispatcher defaults to opus, logs warning
- Missing `context_scope` object: dispatcher uses defaults (knowledge: true, memory: true, previous_outputs: "direct")
- Unknown `previous_outputs` value: treat as "direct" (safe default)

**Edge Cases:**
- Existing plan.json files without these fields: dispatcher reads `undefined`, applies defaults — no migration needed
- PM manually edits plan.json and sets `model: "haiku"` for a backend step: respected (PM override is intentional)
- `context_scope.knowledge: true` but Qdrant is not configured: knowledge injection is already a no-op when Qdrant is unavailable (existing behavior in dispatch-protocol.md)

**Dependencies:**
- No dependencies — can start independently (parallel with Steps 1-2)

**Acceptance Criteria:**
- [ ] `plan.schema.json` includes `model` property with enum ["haiku", "sonnet", "opus"] and default "opus"
- [ ] `plan.schema.json` includes `context_scope` object with `knowledge`, `memory`, `previous_outputs` properties
- [ ] Both fields are NOT in the `required` array (optional for backward compatibility)
- [ ] Existing plan.json files validate against the updated schema without modification

**Effort:** S
**AID Role:** backend

---

### Step 4: Planner Model Assignment

**Objective:** Modify the planner skill to read `dispatch-config.yaml` during plan.json generation and populate each step's `model` and `context_scope` fields based on the step's assigned role.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/planner.md` — add dispatch-config.yaml reading logic and step field population in the plan generation section

**Architecture Context:**
The planner skill in `plugins/aid-orchestrator/skills/planner.md` transforms EPIC specifications into structured plan.json files. Currently it assigns `id`, `role`, `objective`, `inputs`, `outputs`, `constraints`, `allowed_paths`, `forbidden_paths`, `acceptance_criteria`, `wiring`, and `wiring_context` per step. This step adds `model` and `context_scope` population by looking up the step's role in `dispatch-config.yaml`. The planner is invoked by `/aid-plan-epic` (commands/aid-plan-epic.md Step 6).

**Implementation Detail:**

1. In the planner's plan generation section, add a config loading step at the beginning:
   ```
   ## Model and Context Assignment

   Before building the plan.json steps array:
   1. Read dispatch-config.yaml from .aid-o/03-config/policies/dispatch-config.yaml
      - If file not found: use defaults (all opus, all context enabled)
      - If file malformed: log warning, use defaults
   2. For each step in the steps array:
      a. Look up step.role in model_tiers → assign to step.model
         - If role not found in model_tiers: use "opus" (safe default)
      b. Check if step.role is in context_defaults.knowledge list → set context_scope.knowledge
      c. Check if step.role is in context_defaults.memory list → set context_scope.memory
      d. Set context_scope.previous_outputs from context_defaults.previous_outputs
   ```

2. Add the populated fields to the step JSON output template:
   ```json
   {
     "id": "step_N_role",
     "role": "backend",
     "model": "opus",
     "context_scope": {
       "knowledge": false,
       "memory": true,
       "previous_outputs": "direct"
     },
     ...existing fields...
   }
   ```

**Error Handling:**
- `dispatch-config.yaml` not found: use all-opus, all-context defaults. Log info-level message (not error — file is optional for backward compatibility).
- `dispatch-config.yaml` YAML parse error: log warning with error message, use defaults for all steps.
- Role in EPIC step table not found in `model_tiers`: use opus, log warning.

**Edge Cases:**
- EPIC with a custom role not in the standard enum (e.g., "data-engineer"): planner uses opus and context-all defaults, logs warning
- dispatch-config.yaml with empty `model_tiers` section: all steps get opus (safe)
- dispatch-config.yaml with empty `context_defaults.knowledge` list: no steps get knowledge context (valid — project may not use Qdrant)

**Dependencies:**
- Depends on: Step 2 — dispatch-config.yaml must exist
- Depends on: Step 3 — plan.schema.json must accept model and context_scope fields

**Acceptance Criteria:**
- [ ] Planner reads `dispatch-config.yaml` from `.aid-o/03-config/policies/`
- [ ] Generated plan.json includes `model` field per step matching the role→model mapping
- [ ] Generated plan.json includes `context_scope` object per step matching the role→context mapping
- [ ] Fallback to opus + all-context when dispatch-config.yaml is missing
- [ ] Warning logged when role is not found in model_tiers

**Effort:** M
**AID Role:** backend

---

### Step 5: Usage Tracking in stage_log

**Objective:** Modify the dispatch protocol to estimate input tokens before dispatch, measure duration, and log a structured `usage` entry to `stage_log.jsonl` after each agent dispatch completes.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~42-102) — add token estimation before dispatch, usage logging after dispatch completion
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` (lines ~82-86) — aggregate usage into `plan_progress.json` at DONE state

**Architecture Context:**
The dispatch protocol at `plugins/aid-orchestrator/skills/dispatch-protocol.md` defines how agent prompts are assembled and dispatched. Currently, it logs a `dispatch_complete` entry to `stage_log.jsonl` with `timestamp`, `state`, `step`, `action`, `details`, and `result` fields. This step extends the dispatch flow to: (1) estimate input tokens via the token-estimator skill before dispatching, (2) record dispatch start time, (3) on completion, compute duration and estimate output tokens, (4) append usage object to the stage_log entry. At the DONE state, `epic-orchestration.md` aggregates all usage entries into `plan_progress.json`.

**Implementation Detail:**

1. In `dispatch-protocol.md`, after assembling the dispatch prompt (line ~88) and BEFORE dispatching the agent, add:
   ```
   ## Usage Measurement (Pre-Dispatch)
   1. Estimate input tokens using token-estimator.md protocol
   2. Record context sources list: which blocks were injected
      (e.g., ["plan_section", "memory", "prev_step_2"])
   3. Check budget alert: if estimated_input > budget_alerts[step.model]
      → set budget_alert = true, log warning
   4. Record dispatch_start_time = current timestamp
   ```

2. After dispatch completes (existing `dispatch_complete` log point), extend the stage_log entry:
   ```
   ## Usage Measurement (Post-Dispatch)
   1. Compute duration_ms = current timestamp - dispatch_start_time
   2. Estimate output tokens: count agent response characters / 4
   3. Append usage object to stage_log entry:
      {
        "usage": {
          "model": step.model || "opus",
          "estimated_input_tokens": <tiktoken estimate>,
          "estimated_output_tokens": <char/4 estimate>,
          "dispatch_prompt_chars": <prompt character count>,
          "context_sources": <list of injected context blocks>,
          "duration_ms": <computed duration>,
          "budget_alert": <true if over threshold, false otherwise>
        }
      }
   ```

3. In `epic-orchestration.md` DONE state section, add usage aggregation:
   ```
   ## Usage Aggregation (DONE State)
   1. Read all stage_log.jsonl entries with action "dispatch_complete" and usage object
   2. Aggregate into usage_summary:
      - total_estimated_input_tokens: sum of all estimated_input_tokens
      - total_estimated_output_tokens: sum of all estimated_output_tokens
      - total_duration_ms: sum of all duration_ms
      - steps_count: count of entries
      - models_used: count per model value
      - per_step: array of {step, model, estimated_input_tokens, estimated_output_tokens, duration_ms, budget_alert}
   3. Write usage_summary to plan_progress.json as top-level key
   ```

**Error Handling:**
- Token estimation fails: set estimated_input_tokens to -1, continue dispatch (non-blocking)
- Duration computation overflow (unlikely): cap at MAX_SAFE_INTEGER
- stage_log write failure: log error, do not retry (usage data is advisory, not critical)
- plan_progress.json write failure at DONE state: log error, continue with remaining DONE state actions

**Edge Cases:**
- Parallel dispatch (multiple agents in same wave): each gets its own usage entry with same timestamp — aggregation sums all
- Agent dispatch times out: duration_ms reflects timeout value, estimated_output_tokens is 0
- Agent retried after gate failure: retry dispatch gets separate usage entry (both logged, both aggregated)
- Step skipped (already completed from previous run): no dispatch, no usage entry — correct behavior

**Dependencies:**
- Depends on: Step 1 — token estimation protocol must be defined
- Depends on: Step 3 — plan.schema.json must have model field (for reading step.model)

**Acceptance Criteria:**
- [ ] Every `dispatch_complete` entry in stage_log.jsonl includes a `usage` object with all 7 fields
- [ ] Token estimation runs before dispatch (non-blocking — errors logged, dispatch proceeds)
- [ ] Budget alert logged when estimated input tokens exceed threshold from dispatch-config.yaml
- [ ] `plan_progress.json` includes `usage_summary` object at run end
- [ ] Usage aggregation correctly sums metrics across all dispatched steps including parallel dispatches
- [ ] Existing stage_log entries without usage field are not affected (backward compatible)

**Effort:** M
**AID Role:** backend

---

### Step 6: Baseline Benchmark

**Objective:** Run an existing medium-size EPIC (5-8 steps) with usage tracking active to capture baseline performance metrics — per-step estimated tokens, per-role averages, total duration, retry rate, and gate failure rate.

**Files:**
- No code changes — this is an execution and measurement step
- Output: `.aid-o/04-engine/evidence/{benchmark_epic_id}/{run_id}/baseline-report.md` — structured benchmark report

**Architecture Context:**
This step produces the baseline data that EPIC 2 optimizations (Steps 7-9) will be measured against. The benchmark must use an EPIC that exercises multiple roles (architect, backend, frontend, qa) to capture meaningful per-role metrics. Steps 1-5 must be complete so that usage tracking is active during the benchmark run. The baseline report becomes the comparison reference for Step 10 (re-measure).

**Implementation Detail:**

1. Select a benchmark EPIC:
   - Ideal: a medium-size EPIC with 5-8 steps, at least 3 different roles, at least 1 gate
   - Candidates: any recent completed EPIC from P015 or P010 that can be re-run, or create a small dedicated benchmark EPIC
   - Document the chosen EPIC ID in the baseline report

2. Run the EPIC with `/aid-run-epic`:
   - All Steps 1-5 changes must be deployed (dispatch-config.yaml exists, schema extended, planner populates fields, usage tracking active)
   - Run 2x to account for LLM non-determinism (±15-20% variance)

3. After each run, extract metrics from stage_log.jsonl and plan_progress.json:
   - Per-step: model, estimated_input_tokens, estimated_output_tokens, duration_ms, context_sources
   - Per-role: average estimated_input_tokens, average duration_ms
   - Totals: sum estimated_input_tokens, sum estimated_output_tokens, sum duration_ms
   - Quality: retry count, gate failure count, step completion rate

4. Produce baseline-report.md:
   ```markdown
   # Baseline Benchmark Report
   EPIC: {epic_id}
   Runs: 2
   Date: {date}

   ## Per-Step Metrics (average of 2 runs)
   | Step | Role | Model | Est. Input Tokens | Est. Output Tokens | Duration (s) | Context Sources |
   ...

   ## Per-Role Averages
   | Role | Avg Input Tokens | Avg Output Tokens | Avg Duration (s) | Steps |
   ...

   ## Totals
   - Total estimated input tokens: {sum}
   - Total estimated output tokens: {sum}
   - Total duration: {sum}s
   - Retry rate: {count}/{total_steps}
   - Gate failure rate: {count}/{total_gates}
   - Step completion rate: {completed}/{total}

   ## Notes
   - {any observations about outliers or unexpected values}
   ```

**Error Handling:**
- Benchmark EPIC fails mid-run: use partial data for completed steps, note in report
- Usage tracking not active (Steps 1-5 not complete): abort benchmark, log error listing which steps are missing
- stage_log.jsonl has no usage entries: abort, Steps 1-5 were not properly deployed

**Edge Cases:**
- EPIC has parallel steps: usage entries for parallel steps have same timestamp — report each separately
- EPIC has zero retries (perfect run): retry rate = 0/N — valid baseline
- Second run produces significantly different metrics from first (>30% variance): note in report, run a third benchmark and use the median of three runs

**Dependencies:**
- Depends on: Steps 1-5 — all infrastructure must be in place before benchmark

**Acceptance Criteria:**
- [ ] Benchmark EPIC selected and documented (5-8 steps, 3+ roles)
- [ ] Two successful benchmark runs completed with usage tracking active
- [ ] `baseline-report.md` produced with per-step, per-role, and total metrics
- [ ] Retry rate and gate failure rate documented as quality baseline
- [ ] Report saved in evidence directory for comparison in Step 10

**Effort:** M
**AID Role:** qa

---

### Step 7: Model Tiering Wiring

**Objective:** Modify the dispatch protocol to read `step.model` from plan.json and pass it as the `model` parameter to the Task tool, so that different steps use different Claude models based on their role-assigned tier.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~332) — add model parameter to Task tool dispatch call
- Modify: `plugins/aid-orchestrator/skills/parallel-dispatch.md` (lines ~169-173) — add model parameter to parallel Task tool dispatch calls

**Architecture Context:**
The dispatch protocol at `dispatch-protocol.md` line ~332 currently dispatches agents via `Task(subagent_type="general-purpose", prompt="{agent prompt}")` without a model parameter. The parallel dispatch skill at `parallel-dispatch.md` lines 169-173 similarly dispatches without model specification. This step reads `step.model` from the plan.json step object (populated by the planner in Step 4) and passes it to the Task tool. If the Task tool does not support a `model` parameter, this step documents the limitation and the model tiering becomes a documented future capability.

**Implementation Detail:**

1. First, verify that the Task tool accepts a `model` parameter:
   - The Task tool documentation states: `"model": {"description": "Optional model to use for this agent", "enum": ["sonnet", "opus", "haiku"]}`
   - This confirms model parameter IS supported

2. In `dispatch-protocol.md`, modify the dispatch call (line ~332):
   ```
   Current:  Task(subagent_type="general-purpose", prompt="{agent prompt}")
   New:      Task(subagent_type="{agent_type}", model=step.model, prompt="{agent prompt}")
   ```
   Where `step.model` is read from plan.json. If `step.model` is undefined (old plan.json without field), omit the model parameter (Task tool uses default = opus).

3. In `parallel-dispatch.md`, modify the parallel dispatch section (lines ~169-173):
   ```
   For each agent in parallel group:
     Task(subagent_type="{agent_type}", model=step.model, prompt="{agent prompt}")
   ```

4. Add a fallback rule:
   ```
   Model Resolution Order:
   1. step.model from plan.json (populated by planner from dispatch-config.yaml)
   2. If step.model is missing: read dispatch-config.yaml directly, lookup by step.role
   3. If dispatch-config.yaml is missing: use "opus" (default)
   ```

**Error Handling:**
- `step.model` is not in the valid enum ("haiku", "sonnet", "opus"): use "opus", log warning
- Task tool rejects model parameter (unexpected): catch error, retry without model parameter (fall back to default), log error with details for investigation
- Model parameter ignored silently by Task tool: no way to detect — the calibration benchmark in Step 10 will reveal if duration patterns match expected model speed differences

**Edge Cases:**
- Plan.json generated before this change (no `model` field): model parameter omitted from Task call, Task tool uses its default — fully backward compatible
- PM manually sets `model: "haiku"` for an architect step in plan.json: respected (PM override is intentional, PM accepts quality risk)
- Retry after gate failure: retry dispatch uses same model as original dispatch (model is read from plan.json, not from dispatch-config.yaml live)

**Dependencies:**
- Depends on: Step 3 — plan.schema.json must have model field
- Depends on: Step 4 — planner must populate step.model

**Acceptance Criteria:**
- [ ] `dispatch-protocol.md` passes `model` parameter to Task tool from `step.model`
- [ ] `parallel-dispatch.md` passes `model` parameter to parallel Task tool calls
- [ ] Fallback chain works: step.model → dispatch-config.yaml lookup → opus default
- [ ] Old plan.json files without `model` field dispatch successfully (backward compatible)
- [ ] Warning logged when step.model contains an invalid value

**Effort:** M
**AID Role:** backend

---

### Step 8: Selective Context Injection

**Objective:** Modify the dispatch protocol to check `step.context_scope` before injecting knowledge and memory context blocks, skipping injection for steps where the role does not benefit from external context.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~82-86) — wrap knowledge/memory injection in context_scope checks

**Architecture Context:**
The dispatch protocol at `dispatch-protocol.md` lines 82-86 currently injects cross-project knowledge context via Qdrant for every dispatch when `memory-config.yaml` has `cross_project.enabled: true`. Memory context is similarly injected unconditionally. This step adds conditional checks: before injecting knowledge context, check `step.context_scope.knowledge === true`; before injecting memory context, check `step.context_scope.memory === true`. For `previous_outputs`, the current behavior is to inject all completed step outputs — this step filters to only direct dependencies when `context_scope.previous_outputs === "direct"`.

**Implementation Detail:**

1. In `dispatch-protocol.md`, locate the knowledge context injection section (lines ~82-86). Wrap with a conditional:
   ```
   ## Knowledge Context (Conditional)
   IF step.context_scope is defined AND step.context_scope.knowledge === false:
     SKIP knowledge context injection entirely
     Log in context_sources: "knowledge_skipped"
   ELSE:
     Proceed with existing knowledge context injection logic
     Log in context_sources: "knowledge"
   ```

2. Similarly for memory context:
   ```
   ## Memory Context (Conditional)
   IF step.context_scope is defined AND step.context_scope.memory === false:
     SKIP memory context injection entirely
     Log in context_sources: "memory_skipped"
   ELSE:
     Proceed with existing memory context injection logic
     Log in context_sources: "memory"
   ```

3. For previous step outputs, modify the dependency output injection:
   ```
   ## Previous Step Outputs (Scoped)
   Read step.context_scope.previous_outputs (default: "direct"):
     "all"    → inject outputs from ALL completed steps (current behavior)
     "direct" → inject outputs ONLY from steps listed in this step's dependencies
     "none"   → skip previous output injection entirely
   Log in context_sources: list of injected step IDs (e.g., "prev_step_2", "prev_step_3")
   ```

**Error Handling:**
- `context_scope` missing from step (old plan.json): treat as all-true (inject everything — backward compatible)
- Qdrant unavailable when knowledge injection is requested: existing graceful degradation handles this (already a no-op)
- `previous_outputs` has unknown value: treat as "direct" (safe default)

**Edge Cases:**
- Step has `context_scope.knowledge: true` but `memory-config.yaml` has `knowledge.enabled: false`: knowledge injection is already a no-op at the memory-config level — context_scope is an additional filter, not an override
- Step with no dependencies but `previous_outputs: "direct"`: no outputs injected (correct — no dependencies means no direct outputs)
- Parallel steps in same wave: each step's context_scope is independent — one may get knowledge, another may not

**Dependencies:**
- Depends on: Step 3 — plan.schema.json must have context_scope field
- Depends on: Step 4 — planner must populate context_scope per step

**Acceptance Criteria:**
- [ ] Knowledge context skipped when `step.context_scope.knowledge === false`
- [ ] Memory context skipped when `step.context_scope.memory === false`
- [ ] Previous outputs filtered by `context_scope.previous_outputs` setting ("all"/"direct"/"none")
- [ ] `context_sources` in usage entry accurately reflects which contexts were injected vs. skipped
- [ ] Old plan.json files without context_scope inject all context (backward compatible)
- [ ] Skipped contexts logged as "knowledge_skipped" / "memory_skipped" in context_sources

**Effort:** M
**AID Role:** backend

---

### Step 9: Prompt Trimming

**Objective:** Reduce the dispatch prompt size by sending only step-scoped content (step objective, acceptance criteria, allowed_paths, plan_ref section, and direct dependency outputs) instead of the full EPIC specification and full plan.json content.

**Files:**
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` (lines ~44-55) — replace full EPIC/plan injection with step-scoped summary

**Architecture Context:**
The dispatch protocol at `dispatch-protocol.md` lines 44-55 currently injects the full EPIC goal, scope, and constraints into every agent dispatch, plus the full step specification from plan.json. The `plan_ref` mechanism (lines 220-339) already injects the relevant source plan section for the step. This means the full EPIC spec is largely redundant — the agent gets the step's objective, constraints, and the detailed plan section. This step trims the EPIC injection to a 3-line summary (goal only) and removes redundant plan.json fields from the dispatch prompt.

**Implementation Detail:**

1. In `dispatch-protocol.md`, modify the EPIC context injection (lines ~44-55):
   ```
   Current (full EPIC injection):
     EPIC Goal: {full goal section}
     EPIC Scope: {full scope section — allowed paths, forbidden zones, artifacts}
     EPIC Constraints: {full constraints section}

   New (trimmed summary):
     EPIC: {epic_id} — {one-line goal summary}
     Allowed paths: {step.allowed_paths from plan.json}
     Forbidden paths: {step.forbidden_paths from plan.json}
   ```

2. For the plan step injection, send only:
   ```
   Step: {step.id}
   Role: {step.role}
   Objective: {step.objective}
   Inputs: {step.inputs}
   Outputs: {step.outputs}
   Constraints: {step.constraints}
   Acceptance Criteria: {step.acceptance_criteria}
   ```
   The detailed implementation context comes from `plan_ref` section injection (already exists, lines 220-339) — no need to duplicate.

3. Estimated savings per dispatch (from cost-optimization.md lines 113-155):
   - Playbook: already uses summary mode (no change needed)
   - EPIC spec: ~1500 tokens → ~100 tokens (trimmed to one-line goal)
   - Dependency outputs: handled by context_scope.previous_outputs in Step 8

**Error Handling:**
- plan_ref resolution fails (no matching section in source plan): fall back to including full step objective + constraints (existing fallback behavior in dispatch-protocol.md)
- Step has no allowed_paths (empty array): include empty list — agent can access any path (existing behavior)

**Edge Cases:**
- EPIC with very long goal statement (>500 chars): truncate to first sentence for the one-line summary
- Step without plan_ref (no source plan linked): the trimmed EPIC summary + step fields are the only context — sufficient for simple steps, may need more context for complex steps. Flag in stage_log if plan_ref resolution fails.
- First step in EPIC (no previous outputs): only EPIC summary + step spec + plan_ref section — minimal prompt, fastest dispatch

**Dependencies:**
- Depends on: Step 7 — model tiering must be active so trimming benefits are measurable per model tier
- Depends on: Step 8 — selective context must be active so trimming is additive

**Acceptance Criteria:**
- [ ] EPIC context in dispatch prompt reduced to one-line goal + allowed/forbidden paths
- [ ] Full EPIC scope and constraints sections no longer injected in dispatch prompt
- [ ] Plan step injection includes only essential fields (id, role, objective, inputs, outputs, constraints, AC)
- [ ] plan_ref section injection continues to work (provides detailed implementation context)
- [ ] Dispatch prompt character count measurably reduced vs. baseline (logged in usage entry)

**Effort:** M
**AID Role:** backend

---

### Step 10: Re-measure Benchmark

**Objective:** Re-run the same benchmark EPIC from Step 6 with all optimizations active (model tiering, selective context, prompt trimming) and produce a comparison report showing the impact of each optimization.

**Files:**
- No code changes — execution and measurement step
- Output: `.aid-o/04-engine/evidence/{benchmark_epic_id}/{run_id}/optimization-report.md` — comparison report

**Architecture Context:**
This step closes the measure→optimize→measure loop. The same EPIC used in Step 6 (baseline) is re-run with Steps 7-9 optimizations active. The comparison report enables data-driven validation: if quality metrics (retry rate, gate failures) degraded, the responsible optimization can be identified and reverted. The report also serves as the baseline reference for the efficiency guardrail in Step 11.

**Implementation Detail:**

1. Re-run the same benchmark EPIC from Step 6:
   - Same EPIC ID, same environment
   - All optimizations active: model tiering (Step 7), selective context (Step 8), prompt trimming (Step 9)
   - Run 2x for variance

2. Extract metrics from stage_log.jsonl and plan_progress.json (same extraction as Step 6)

3. Produce optimization-report.md:
   ```markdown
   # Optimization Benchmark Report
   EPIC: {epic_id}
   Baseline runs: Step 6 ({date})
   Optimization runs: Step 10 ({date})

   ## Before/After Comparison
   | Metric | Baseline (avg) | Optimized (avg) | Change |
   |--------|---------------|----------------|--------|
   | Total est. input tokens | {N} | {N} | {-X%} |
   | Total est. output tokens | {N} | {N} | {-X%} |
   | Total duration | {N}s | {N}s | {-X%} |
   | Retry rate | {N}/{T} | {N}/{T} | {same/better/worse} |
   | Gate failure rate | {N}/{T} | {N}/{T} | {same/better/worse} |

   ## Per-Step Comparison
   | Step | Role | Baseline Model | Optimized Model | Baseline Tokens | Optimized Tokens | Change |
   ...

   ## Per-Role Averages
   | Role | Baseline Avg Tokens | Optimized Avg Tokens | Change |
   ...

   ## Quality Assessment
   - Retry rate: {assessment — same, improved, or degraded}
   - Gate failure rate: {assessment}
   - If any degradation: identify which role/step, recommend reverting model tier

   ## Recommendations
   - {data-driven recommendations for dispatch-config.yaml tuning}
   ```

**Error Handling:**
- Benchmark EPIC fails during optimized run: note failure, compare partial results with baseline
- Quality degradation detected (retry rate increased): flag specific role, recommend reverting to opus in dispatch-config.yaml

**Edge Cases:**
- Optimization produces identical token counts as baseline (possible if dispatch prompt was already efficient): note as "no improvement from trimming" in report
- Quality improved after optimization (fewer retries): note as positive side effect of focused context
- One run succeeds, other fails: use single run data, note reduced confidence in report

**Dependencies:**
- Depends on: Steps 7-9 — all optimizations must be active
- Depends on: Step 6 — baseline data must exist for comparison

**Acceptance Criteria:**
- [ ] Same benchmark EPIC from Step 6 re-run with all optimizations active
- [ ] Two successful optimized runs completed
- [ ] `optimization-report.md` produced with before/after comparison table
- [ ] Quality assessment section confirms retry rate and gate failure rate did not degrade
- [ ] Per-role comparison identifies which roles benefited most from model tiering
- [ ] Report saved in evidence directory

**Effort:** M
**AID Role:** qa

---

### Step 11: Efficiency Guardrail in /aid-audit

**Objective:** Extend the `/aid-audit` command with a "Token Efficiency" section that reads usage data from recent runs, computes per-role averages, compares against baseline, and alerts when any step exceeds 2x the baseline average for its role.

**Files:**
- Modify: `plugins/aid-orchestrator/agents/auditor.md` — add "Token Efficiency" audit section with usage data analysis
- Modify: `plugins/aid-orchestrator/commands/aid-audit.md` (lines ~11-26) — add "efficiency" to audit types list

**Architecture Context:**
The `/aid-audit` command invokes the auditor agent (`agents/auditor.md`) to produce a health report. This step extends the auditor with a new "Token Efficiency" section that reads `stage_log.jsonl` usage entries from the most recent completed run, aggregates per-role metrics, and compares against the baseline report from Step 10. The guardrail is advisory (alerts in the report) not enforcement (does not block runs). This is the final piece of the continuous improvement loop: audit detects regression → PM adjusts dispatch-config.yaml → next run is better.

**Implementation Detail:**

1. In `agents/auditor.md`, add a new audit section:
   ```
   ## Token Efficiency Audit

   1. Find the most recent completed run:
      - Scan .aid-o/04-engine/evidence/*/*/plan_progress.json
      - Select the most recent with usage_summary present
      - If no usage_summary found: report "No usage data available — run an EPIC with P017 tracking enabled"

   2. Read usage_summary from plan_progress.json:
      - Extract per_step array with model, estimated_input_tokens, duration_ms

   3. Compute per-role averages:
      - Group steps by role
      - Average estimated_input_tokens and duration_ms per role

   4. Compare against baseline (if available):
      - Look for baseline-report.md or optimization-report.md in evidence directories
      - If found: compare current per-role averages against baseline
      - Flag any role where current average > 2x baseline average

   5. Report format:
      Token Efficiency
      ================
      Score: {0-100 based on adherence to baseline}
      Last run: {epic_id} / {run_id}

      Per-Role Summary:
      | Role | Steps | Avg Input Tokens | Avg Duration | vs Baseline |
      ...

      Alerts:
      - {WARN: role X averaged Nk tokens, 2.1x baseline of Mk — review dispatch-config.yaml}

      Recommendations:
      - {If haiku steps have high retry rate: consider upgrading to sonnet}
      - {If opus steps have low complexity: consider downgrading to sonnet}
   ```

2. In `commands/aid-audit.md`, add "efficiency" to the audit types enum (lines ~11-26):
   ```
   Audit types: code, database, documentation, frontend, security, architecture, efficiency, full
   ```
   The "full" audit type already includes all sections — "efficiency" is added to the list so it runs as part of "full" and can be run standalone.

**Error Handling:**
- No completed runs with usage data: report "No usage data available" (not an error — expected for projects that haven't run P017-tracked EPICs yet)
- Baseline report not found: skip comparison, report raw metrics only without regression detection
- plan_progress.json malformed or missing usage_summary: log warning, skip this run, try previous run
- No completed runs at all: report "No EPIC runs found in evidence directory"

**Edge Cases:**
- First EPIC after P017: no baseline exists yet — report raw metrics, suggest running Step 6 benchmark
- Multiple EPICs with usage data: compare most recent against baseline (not against each other)
- Role appears in current run but not in baseline (new role added): skip comparison for that role, report raw only
- All metrics within baseline: report "All roles within baseline — no regression detected" (score: 100)

**Dependencies:**
- Depends on: Step 5 — usage tracking must be active (otherwise no data to audit)
- Depends on: Step 10 — baseline/optimization report should exist for comparison (optional — guardrail works without baseline, just can't compare)

**Acceptance Criteria:**
- [ ] `/aid-audit efficiency` produces a "Token Efficiency" section in the audit report
- [ ] `/aid-audit full` includes the Token Efficiency section
- [ ] Per-role averages computed from most recent run's usage data
- [ ] Alert triggered when any role exceeds 2x baseline average
- [ ] Score (0-100) computed based on baseline adherence
- [ ] Graceful handling when no usage data or no baseline exists
- [ ] Recommendations section provides actionable dispatch-config.yaml tuning suggestions

**Effort:** M
**AID Role:** backend

---

### Step 12: CHANGELOG + Documentation Update

**Objective:** Update CHANGELOG (both root and plugin copies), version bump all version-bearing files, update README roadmap, and document `dispatch-config.yaml` configuration options.

**Files:**
- Modify: `CHANGELOG.md` — add new version entry with P017 features
- Modify: `plugins/aid-orchestrator/CHANGELOG.md` — identical copy
- Modify: `.claude-plugin/marketplace.json` — bump `metadata.version` and `plugins[0].version`
- Modify: `plugins/aid-orchestrator/.claude-plugin/plugin.json` — bump `version`
- Modify: `plugins/aid-orchestrator/README.md` — bump version line
- Modify: `README.md` — update Roadmap section
- Modify: `plugins/aid-orchestrator/skills/token-estimator.md` — add `**Last Updated:**` footer
- Modify: `plugins/aid-orchestrator/skills/dispatch-protocol.md` — update `**Last Updated:**` footer
- Modify: `plugins/aid-orchestrator/skills/epic-orchestration.md` — update `**Last Updated:**` footer
- Modify: `plugins/aid-orchestrator/skills/planner.md` — update `**Last Updated:**` footer

**Architecture Context:**
CLAUDE.md mandates that every push updates all 8 version-bearing files (Version File Registry). This step follows the standard release workflow: CHANGELOG entry → version bump across 8 files → README roadmap → footer dates on modified skills. The CHANGELOG format follows Keep a Changelog with `- **Bold Name** — description` entries.

**Implementation Detail:**

1. Write CHANGELOG entry:
   ```markdown
   ## [X.Y.Z] — 2026-02-27

   ### Added
   - **dispatch-config.yaml** — model tier assignments, context injection defaults, and budget alert thresholds per AID role
   - **Token Estimation** — tiktoken-based dispatch prompt measurement using cl100k_base encoding with calibration support
   - **Usage Tracking** — per-step estimated tokens, model, duration, and context sources logged in stage_log.jsonl
   - **Usage Aggregation** — usage_summary in plan_progress.json at run end with per-step and per-role metrics
   - **Efficiency Guardrail** — /aid-audit "Token Efficiency" section comparing per-role metrics against baseline with 2x regression alerts

   ### Changed
   - **Plan Schema** — added optional model and context_scope fields per step for model tiering and selective context injection
   - **Dispatch Protocol** — model parameter passed to Task tool from step.model; context injection conditioned on step.context_scope; dispatch prompt trimmed to step-scoped content
   - **Planner** — reads dispatch-config.yaml to populate step.model and step.context_scope during plan.json generation
   ```

2. Copy to `plugins/aid-orchestrator/CHANGELOG.md` (must be identical)

3. Bump version in all 8 files per CLAUDE.md Version File Registry

4. Update README roadmap with new version line

5. Update `**Last Updated:** 2026-02-27` footer on all modified skill files

**Error Handling:**
- Version mismatch across files after bump: run the pre-push check from CLAUDE.md to verify all 8 files match
- CHANGELOG format violation: ensure every entry uses `- **Bold Name** — description` format (em dash, not colon)

**Edge Cases:**
- Another version was released between EPIC 1 and EPIC 2: update version to next increment, not the one planned at EPIC 1 time
- Modified skill file does not have `**Last Updated:**` footer: add one

**Dependencies:**
- Depends on: Steps 1-11 — all implementation must be complete before release

**Acceptance Criteria:**
- [ ] CHANGELOG entry follows Keep a Changelog format with Added/Changed sections
- [ ] Root and plugin CHANGELOG entries are identical
- [ ] All 8 version-bearing files show the same version number
- [ ] README roadmap updated with new version summary
- [ ] All modified skill files have updated `**Last Updated:**` footer
- [ ] Pre-push check passes: `grep -n '"version"'` shows consistent version across files

**Effort:** S
**AID Role:** docs-writer

---

## Next Steps

- [ ] Create EPICs from P017 via `/aid-plan-epic P017`
- [ ] Queue EPICs: E-017-1_2 (Measure & Build), E-017-2_2 (Optimize & Guard)
- [ ] After EPIC 1: review baseline report, adjust dispatch-config.yaml tier assignments based on retry rate data
- [ ] After EPIC 2: verify guardrail is active, close plan

---

**Last Updated:** 2026-02-27
