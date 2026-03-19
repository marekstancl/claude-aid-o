---
name: token-estimator
description: Dispatch token tracking — character-based heuristic, execution estimation, calibration, budget alerts
user_invocable: false
---

# Token Estimator — Dispatch Token Tracking

**Skill:** token-estimator
**Dependencies:** pipeline.md §4, pipeline.md §1, defaults/orchestration.yaml

---

## Purpose

Provide a lightweight, non-blocking token estimation protocol for measuring
dispatch and agent execution costs. Estimates are used for advisory budget
alerts, cross-EPIC analytics, and model-tier optimization — never for
enforcement or blocking dispatch.

This skill defines:
1. How to estimate token counts from text (character-based heuristic)
2. Where estimation runs in the dispatch flow
3. How results are logged to timeline.jsonl
4. How to calibrate estimates using actual usage data

---

## Estimation Protocol

### Character-Based Heuristic (cl100k_base Approximation)

Token estimation uses a character-to-token ratio heuristic inspired by the
cl100k_base tokenizer (used by GPT-4 and Claude-family models). The actual
tokenizer is not invoked — this is a fast approximation suitable for
measurement and budgeting purposes.

#### Ratios

| Content Type | Chars per Token | Rationale |
|---|---|---|
| English prose | ~4.0 | Average for natural language with cl100k_base |
| Code (Python, JS, TS) | ~3.0 | Keywords, operators, and short identifiers compress less |
| Code (verbose: Java, Go) | ~3.5 | Longer identifiers, more boilerplate |
| Mixed (prose + code) | ~3.5 | Weighted average for typical agent prompts |
| YAML / JSON config | ~3.2 | Structured data with repeated keys |
| Markdown documentation | ~3.8 | Headers, lists, and formatting tokens |

#### Estimation Function

```
estimate_tokens(text, content_type="mixed"):
  1. char_count = length(text)
  2. ratio = RATIOS[content_type]  # default: 3.5 for mixed
  3. estimated_tokens = ceil(char_count / ratio)
  4. return estimated_tokens
```

When content type cannot be determined, use `mixed` (3.5 chars/token) as the
safe default. This slightly overestimates for pure English and slightly
underestimates for dense code — acceptable for advisory purposes.

#### Prompt Token Estimation

For dispatch prompts, estimate total prompt tokens by summing components:

```
estimate_dispatch_tokens(prompt_components):
  total = 0
  for component in prompt_components:
    type = classify_content(component)
      # "prose" for EPIC goal, playbook summary, constraints
      # "code" for code blocks, file contents
      # "config" for YAML/JSON sections
      # "mixed" for everything else
    total += estimate_tokens(component.text, type)
  return total
```

#### Execution Token Estimation

Agent execution tokens cannot be measured directly (the Controller does not
have access to API billing data). Estimate from observable signals:

```
estimate_execution_tokens(duration_seconds, tool_operations_count):
  # Baseline from BMK-001: ~3 ops/min, ~2600 tokens/op
  ops_per_minute = 3
  tokens_per_op = 2600

  IF tool_operations_count is available:
    estimated = tool_operations_count * tokens_per_op
  ELSE:
    ops_estimated = (duration_seconds / 60) * ops_per_minute
    estimated = ops_estimated * tokens_per_op

  return estimated
```

The `tool_operations_count` is extracted from the agent's Execution Summary
block (see `skills/agent-core.md`). When unavailable, the duration-based
fallback applies.

---

## Accuracy Notes

### Expected Drift: +/-10-15%

The character-based heuristic is an approximation. Measured accuracy:

| Scenario | Expected Drift | Notes |
|---|---|---|
| Pure English prompts | +/-5-8% | Closest to cl100k_base behavior |
| Code-heavy prompts | +/-10-15% | Varies by language verbosity |
| Mixed prompts (typical) | +/-8-12% | Most dispatch prompts |
| Execution estimates | +/-15-25% | Derived from time and ops, inherently noisier |

### Why Drift Is Acceptable

1. **Advisory only** — estimates inform budget alerts and analytics, never
   block dispatch or reject agent output.
2. **Relative accuracy** — even with +/-15% drift, step-to-step and EPIC-to-EPIC
   comparisons remain valid for identifying bottlenecks and trends.
3. **Calibration loop** — projects with BMK data can refine ratios over time
   (see Calibration section below).

### Known Limitations

- Unicode-heavy content (CJK, emoji) compresses differently — estimates may
  undercount tokens by 20-30%. If the project is predominantly non-Latin,
  adjust `chars_per_token` ratios in `orchestration.yaml`.
- Very short texts (< 100 chars) have high relative error — but these
  contribute negligibly to total token counts.
- System prompt tokens (injected by the API, not visible to the Controller)
  are not included in estimates.

---

## Integration Points

### Where Estimation Runs

Token estimation occurs at two points in the dispatch flow:

```
DISPATCH FLOW:
  1. Controller builds dispatch prompt
     |
     v
  2. >>> ESTIMATE PROMPT TOKENS <<<          -- token-estimator runs here
     |   estimate_dispatch_tokens(prompt_components)
     |   Log to timeline.jsonl: dispatch_prompt_tokens
     |
     v
  3. Controller dispatches agent (Task tool)
     |
     v
  4. Agent executes (duration tracked by Controller)
     |
     v
  5. Agent returns output with Execution Summary
     |
     v
  6. >>> ESTIMATE EXECUTION TOKENS <<<       -- token-estimator runs here
     |   estimate_execution_tokens(duration, tool_ops)
     |   Log to timeline.jsonl: estimated_execution_tokens
     |
     v
  7. Controller proceeds to GATES
```

### Non-Blocking Behavior

Estimation MUST be non-blocking. If estimation fails for any reason (malformed
text, missing Execution Summary, unexpected content type), the Controller:

1. Logs the error to timeline.jsonl with `"estimation_error": "{reason}"`
2. Sets token fields to `null` (not 0 — null indicates missing data)
3. Continues dispatch or proceeds to GATES normally
4. NEVER retries estimation synchronously
5. NEVER blocks agent dispatch or post-dispatch processing

```
ON ESTIMATION ERROR:
  try:
    tokens = estimate_tokens(text, content_type)
  catch (any error):
    log_to_stage_log({
      "state": "EXECUTING",
      "action": "token_estimation_error",
      "step_id": step_id,
      "error": error.message,
      "fallback": "null tokens — estimation skipped"
    })
    tokens = null
    CONTINUE — do not block
```

### Where Results Are Logged

All token estimates are appended to `timeline.jsonl` in the run's evidence
directory: `.aid-o/work/evidence/{epic_id}/{run_id}/timeline.jsonl`

#### Pre-Dispatch Entry (after prompt assembly, before agent dispatch)

```json
{
  "state": "EXECUTING",
  "action": "token_estimate_pre_dispatch",
  "step_id": "{step_id}",
  "timestamp": "{ISO 8601}",
  "dispatch_prompt_tokens": 1250,
  "prompt_char_count": 4375,
  "content_type_breakdown": {
    "prose": 620,
    "code": 380,
    "config": 250
  }
}
```

#### Post-Dispatch Entry (after agent returns, before GATES)

```json
{
  "state": "EXECUTING",
  "action": "token_estimate_post_dispatch",
  "step_id": "{step_id}",
  "timestamp": "{ISO 8601}",
  "estimated_execution_tokens": 78000,
  "duration_seconds": 600,
  "tool_operations_count": 30,
  "model": "sonnet",
  "estimation_method": "tool_ops_count"
}
```

When `tool_operations_count` is not available from the Execution Summary:

```json
{
  "state": "EXECUTING",
  "action": "token_estimate_post_dispatch",
  "step_id": "{step_id}",
  "timestamp": "{ISO 8601}",
  "estimated_execution_tokens": 78000,
  "duration_seconds": 600,
  "tool_operations_count": null,
  "model": "sonnet",
  "estimation_method": "duration_fallback"
}
```

### Qdrant Metric Storage (at DONE state)

At the DONE state, the Controller aggregates per-step estimates into EPIC-level
token profiles and stores them in Qdrant. This reuses the schema defined in
`skills/cost-optimization.md` Axis 4:

- Per-step: `metric_kind: "step_token_profile"` — model, dispatch tokens,
  execution tokens, duration, tool operations
- Per-EPIC: `metric_kind: "token_profile"` — total estimated tokens, model
  distribution, active compute minutes, estimated cost

The token-estimator skill provides the raw data; the cost-optimization skill
defines the aggregation and storage schema.

---

## Calibration

### Purpose

Calibration refines the character-to-token ratios using actual usage data from
completed EPIC runs. Over time, calibrated ratios reduce estimation drift from
+/-15% toward +/-5%.

### Baseline: BMK-001

The initial ratios are derived from the BMK-001 benchmark (documented in
`skills/cost-optimization.md`):

| BMK-001 Metric | Value |
|---|---|
| Total tokens (estimated) | ~3.5M |
| Active compute | 140 min |
| Steps | 6 |
| Agent execution share | 89% |
| Dispatch share | 3.3% |
| Ops per minute (avg) | ~3 |
| Tokens per op (avg) | ~2,600 |

These values are configured as defaults in `orchestration.yaml` under the
`token_estimation` section.

### Calibration Process

When a project has 3+ completed EPIC runs with token estimates stored in
Qdrant, the Controller can refine ratios:

```
calibrate_ratios(project_name):
  1. Query Qdrant for all step_token_profile metrics for project_name
  2. For each step:
     a. actual_duration = step.duration_seconds
     b. actual_tool_ops = step.tool_operations_count (if available)
     c. estimated_tokens = step.estimated_execution_tokens
     d. prompt_chars = step.prompt_char_count
     e. prompt_tokens = step.dispatch_prompt_tokens
  3. Compute actual chars_per_token for prompts:
     actual_ratio = prompt_chars / prompt_tokens
     # This is still an estimate vs. estimate, but the aggregate
     # across many steps converges toward the true ratio
  4. Compute actual tokens_per_op:
     IF actual_tool_ops is available:
       actual_tpo = estimated_tokens / actual_tool_ops
  5. Update orchestration.yaml calibration section:
     token_estimation.calibration.last_calibration_date
     token_estimation.calibration.samples_used
     token_estimation.calibration.chars_per_token_adjusted
     token_estimation.calibration.tokens_per_op_adjusted
```

### Calibration Rules

1. **Minimum 3 EPIC runs** before calibration adjustments are applied.
   Fewer runs have too much variance.
2. **Calibration is advisory** — adjusted ratios are stored in
   `orchestration.yaml` but do not override the base ratios until PM
   confirms via `/aid-setup` or manual edit.
3. **Outlier rejection** — discard steps with duration < 30 seconds or
   > 3600 seconds (likely aborted or stuck). Discard steps with 0 tool
   operations reported.
4. **Recalibrate periodically** — suggested frequency: every 5 EPIC runs or
   when analytics show drift > 20% from estimates.

### Manual Calibration

PMs can manually adjust ratios in `orchestration.yaml` based on observed
patterns:

```yaml
token_estimation:
  chars_per_token:
    english: 4.0      # Increase if estimates consistently undercount
    code: 3.0          # Decrease if estimates consistently overcount
    mixed: 3.5
  calibration:
    chars_per_token_adjusted:
      english: 3.8     # <-- manual override based on project data
      code: 2.8
      mixed: 3.3
```

When `chars_per_token_adjusted` values are present, the estimator uses them
instead of the base `chars_per_token` values.

---

## Budget Alert Integration

Token estimates feed into the advisory budget alert system defined in
`orchestration.yaml`. The alert flow:

```
AFTER EACH STEP:
  1. Sum all estimated tokens for completed steps
  2. Compare against budget_alerts thresholds:
     - warn_at_tokens: log WARNING to stage_log
     - critical_at_tokens: log CRITICAL WARNING to stage_log + PM notification
  3. Neither threshold triggers enforcement — dispatch continues regardless
  4. Budget alerts appear in /aid-analytics reports for post-hoc review
```

See `defaults/policies/orchestration.yaml` for threshold configuration.

---

## Reference Files

| File | Relevance |
|------|-----------|
| `skills/cost-optimization.md` | BMK-001 baseline, token tracking schema, model tiers |
| `skills/pipeline.md §4` | Dispatch flow where estimation integrates |
| `skills/agent-core.md` | Execution Summary block (source of tool_operations_count) |
| `skills/analytics.md` | Consumes token_profile and step_token_profile metrics |
| `defaults/policies/orchestration.yaml` | Ratios, calibration config, budget thresholds |

---

**Last Updated:** 2026-02-28
