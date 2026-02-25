# Type Contracts for `.aid-o/` Entities

**EPIC:** E-005-1_4-gui-foundation
**Author:** Architect agent (Step 1)
**Consumer:** Domain agent (Step 3) -- implement these in `server/types.ts`
**Date:** 2026-02-25

---

## Overview

This document defines the TypeScript interfaces that Step 3 (domain agent) will
implement in `packages/aid-gui/server/types.ts`. Every interface maps to one or
more files in the `.aid-o/` directory structure. All parsers in `server/parsers/`
will return instances of these types.

### Conventions

- All timestamp fields use ISO 8601 strings (`string`), not `Date` objects, to
  preserve JSON serialization fidelity.
- Optional fields are marked with `?` and documented with "When absent" notes.
- Every parser returns a `ParseResult<T>` wrapper (defined below) rather than
  the raw type, to carry warnings from defensive parsing.

---

## ParseResult Wrapper

Every parser function returns this wrapper. The `data` field contains the parsed
entity (possibly partial), and `warnings` collects non-fatal parse issues.

```typescript
interface ParseResult<T> {
  /** The parsed data. May be partial if warnings were generated. */
  data: T;
  /** Non-fatal issues encountered during parsing. Empty array on clean parse. */
  warnings: ParseWarning[];
}

interface ParseWarning {
  /** What went wrong — human-readable message */
  message: string;
  /** Line number in the source file, if applicable */
  line?: number;
  /** Severity: 'info' for missing optional fields, 'warn' for recoverable errors, 'error' for data loss */
  severity: 'info' | 'warn' | 'error';
}
```

**Source file:** N/A (generic wrapper, not tied to a specific `.aid-o/` file)

---

## 1. StageLogEntry

A single line from `stage_log.jsonl`. Each line is an independent JSON object
recording one orchestration event.

```typescript
interface StageLogEntry {
  /** ISO 8601 timestamp of the event */
  timestamp: string;
  /** FSM state at the time of the event */
  state: string;
  /** Step ID this event relates to, or null for pipeline-level events */
  step: string | null;
  /** Action identifier — what happened (e.g., "dispatch_agent", "gates_complete", "transition") */
  action: string;
  /** Human-readable description of the event */
  details: string;
  /** Outcome: "pass", "fail", "pending", "skip" */
  result: 'pass' | 'fail' | 'pending' | 'skip';
}
```

**Source file:** `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`
**Parser:** `server/parsers/jsonl.ts`

**Example (one line from the JSONL file):**
```json
{
  "timestamp": "2026-02-24T14:43:00Z",
  "state": "EXECUTING",
  "step": "step_1_architect",
  "action": "dispatch_agent",
  "details": "Dispatching architect agent for release-policy.yaml design",
  "result": "pending"
}
```

---

## 2. PipelineState

Current orchestration state, derived from either `auto-mode-state.yaml` (for
active auto-mode sessions) or `plan_progress.json` (for individual runs). This
is a composite type that the GUI uses to show the current pipeline status.

```typescript
interface PipelineState {
  /** Current FSM state: IDLE, PLANNING, PLAN_REVIEW, EXECUTING, PHASE_CHECK, NEXT_PHASE, GATES, CURATOR_RESOLVE, PM_APPROVAL, DONE, ERROR */
  currentState: string;
  /** The EPIC currently being executed, or null if idle */
  currentEpicId: string | null;
  /** The step currently being executed, or null */
  currentStepId: string | null;
  /** Auto-mode session info, present only during auto-mode runs */
  session?: AutoModeSession;
  /** Progress counters */
  progress: {
    epicsCompleted: number;
    epicsTotal: number;
    stepsCompleted: number;
    stepsTotal: number;
  };
}

interface AutoModeSession {
  /** Session identifier (e.g., "FA-20260225T140000Z") */
  sessionId: string;
  /** "auto" or "manual" */
  mode: string;
  /** ISO 8601 start time */
  startedAt: string;
  /** Who started the session (e.g., "pm") */
  startedBy: string;
  /** List of EPIC IDs queued for this session */
  queueSnapshot: string[];
  /** Escalation budget and usage */
  escalation: {
    budget: number;
    count: number;
  };
  /** Aggregate counters for the full session */
  aggregate: {
    epicsCompleted: number;
    epicsFailed: number;
    totalStepsExecuted: number;
    totalGateRuns: number;
    totalGateRetries: number;
    totalEscalations: number;
  };
}
```

**Source files:**
- `.aid-o/04-engine/auto-mode-state.yaml` (primary during auto-mode)
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan_progress.json` (per-run state)
**Parser:** `server/parsers/yaml.ts` and `server/parsers/json.ts`

**Example (auto-mode-state.yaml excerpt mapped to interface):**
```yaml
session:
  session_id: "FA-20260225T140000Z"
  mode: "auto"
  started_at: "2026-02-25T14:00:00Z"
  progress:
    current_epic_id: "E-005-1_4-gui-foundation"
    current_step_id: null
    current_state: "EXECUTING"
    epics_completed: 0
    epics_total: 4
```

---

## 3. EpicSpec

An EPIC specification file parsed from Markdown with YAML frontmatter. The
frontmatter contains metadata; the body contains structured sections.

```typescript
interface EpicSpec {
  /** EPIC identifier (derived from filename, e.g., "E-005-1_4-gui-foundation") */
  epicId: string;

  /** --- Frontmatter fields --- */
  /** Lifecycle status: "active", "completed", "paused", "failed" */
  status: string;
  /** Path to the source plan file */
  planRef: string;
  /** How many EPICs the parent plan contains */
  planEpicsTotal: number;
  /** Total runs planned for this EPIC */
  runsTotal: number;
  /** How many runs have completed */
  runsCompleted: number;

  /** --- Parsed body sections --- */
  /** EPIC title (from the H1 heading) */
  title: string;
  /** Context section content (raw Markdown) */
  context: string;
  /** Goal section content (raw Markdown) */
  goal: string;
  /** Scope section with allowed and forbidden paths */
  scope: {
    allowedPaths: string[];
    forbiddenPaths: string[];
    rawMarkdown: string;
  };
  /** Artifacts section content (raw Markdown) */
  artifacts?: string;
  /** Constraints section content (raw Markdown) */
  constraints: string;
  /** DoD gate names (e.g., ["tests_pass", "lint_pass", "type_check"]) */
  dodGates: string[];
  /** Acceptance criteria — raw text items */
  acceptanceCriteria: AcceptanceCriterion[];
  /** Dependencies section content (raw Markdown) */
  dependencies?: string;
  /** Steps table — parsed from Markdown table */
  steps: EpicStep[];
  /** Hints section — parsed key-value pairs */
  hints?: Record<string, string | number>;
}

interface AcceptanceCriterion {
  /** The role responsible (e.g., "backend", "qa") */
  role: string;
  /** The criterion text */
  text: string;
  /** Whether the checkbox is checked in the source markdown */
  checked: boolean;
}

interface EpicStep {
  /** Step number */
  number: number;
  /** Agent role */
  role: string;
  /** Step objective text */
  objective: string;
  /** Step IDs this depends on */
  dependsOn: string[];
  /** Parallel group identifier, if any */
  parallelGroup?: string;
}
```

**Source file:** `.aid-o/02-epics/{epic_id}.md`
**Parser:** `server/parsers/markdown.ts` (gray-matter for frontmatter, custom section parsing for body)

**Example (frontmatter):**
```yaml
---
status: active
plan_ref: .aid-o/01-plans/P005-C-aid-gui-backend-post-prototype.md
plan_epics_total: 4
runs_total: 1
runs_completed: 0
---
```

---

## 4. PlanJSON

The execution plan generated by the Planner from an EPIC specification. Defines
steps, their dependencies, parallel groups, analysis groups, quality gates, and
budget constraints.

```typescript
interface PlanJSON {
  /** EPIC identifier this plan belongs to */
  epicId: string;
  /** Run identifier (e.g., "20260225T140000Z") */
  runId?: string;
  /** Path to the source plan .md file */
  sourcePlan?: string;
  /** Plan version — incremented on re-planning */
  version?: number;
  /** ISO 8601 timestamp of plan creation */
  createdAt?: string;
  /** ISO 8601 timestamp of plan generation (alternative field name used in some runs) */
  generatedAt?: string;
  /** Total number of steps */
  totalSteps?: number;
  /** Wave assignments — groups of steps by execution order */
  waves?: PlanWave[];
  /** Ordered list of execution steps */
  steps: PlanStep[];
  /** Explicit ordering constraints between steps */
  dependencies?: PlanDependency[];
  /** Groups of step IDs that can execute concurrently */
  parallelGroups?: string[][];
  /** Multi-perspective analysis groups */
  analysisGroups?: AnalysisGroup[];
  /** Quality gate names to run after all steps complete */
  gates?: string[];
  /** Execution budget constraints */
  budget?: {
    maxLlmCostUsd?: number;
    maxRetriesPerGate?: number;
  };
}

interface PlanWave {
  /** Wave number (0-based) */
  wave: number;
  /** Step IDs in this wave */
  steps: string[];
}

interface PlanStep {
  /** Unique step identifier (e.g., "step_1_architect") */
  id: string;
  /** Wave number this step belongs to */
  wave?: number;
  /** Agent role to execute this step */
  role: string;
  /** What this step must accomplish */
  objective: string;
  /** Step IDs this step depends on */
  dependsOn?: string[];
  /** Required inputs */
  inputs?: string[];
  /** Expected outputs */
  outputs?: string[];
  /** Step-specific constraints */
  constraints?: string[];
  /** Filesystem paths this step may modify */
  allowedPaths?: string[];
  /** Filesystem paths this step must not touch */
  forbiddenPaths?: string[];
  /** Verifiable acceptance criteria */
  acceptance?: string[];
  /** Alias for acceptance (used in some plan versions) */
  acceptanceCriteria?: string[];
}

interface PlanDependency {
  /** Step ID that must complete first */
  before: string;
  /** Step ID that depends on 'before' */
  after: string;
  /** Why this dependency exists */
  reason?: string;
}

interface AnalysisGroup {
  /** Unique analysis group identifier */
  id: string;
  /** Step ID being analyzed */
  target: string;
  /** Agent roles performing the analysis */
  agents: string[];
  /** Analysis mode: review, audit, or validation */
  mode: 'review' | 'audit' | 'validation';
  /** How to merge findings from multiple agents */
  mergeStrategy: 'union' | 'consensus' | 'weighted';
  /** Whether auto-generated or manually specified */
  trigger?: 'auto' | 'manual';
}
```

**Source file:** `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json`
**Parser:** `server/parsers/json.ts`
**Schema reference:** `.aid-o/03-config/templates/plan.schema.json`

**Example:**
```json
{
  "epic_id": "E-005-1_4-gui-foundation",
  "run_id": "20260225T140000Z",
  "generated_at": "2026-02-25T14:00:10Z",
  "total_steps": 6,
  "waves": [
    {"wave": 0, "steps": ["step_0_backend"]},
    {"wave": 1, "steps": ["step_1_architect"]}
  ],
  "gates": ["tests_pass", "lint_pass", "type_check"],
  "steps": [
    {
      "id": "step_0_backend",
      "wave": 0,
      "role": "backend",
      "objective": "Monorepo migration...",
      "depends_on": [],
      "inputs": ["AID-GUI repo"],
      "outputs": ["packages/aid-gui/ directory"],
      "allowed_paths": ["package.json", "packages/aid-gui/"],
      "forbidden_paths": ["plugins/"],
      "acceptance": ["AID-GUI contents in packages/aid-gui/"]
    }
  ]
}
```

**Note on field naming:** The `.aid-o/` JSON files use `snake_case` (e.g.,
`epic_id`, `depends_on`). The TypeScript interfaces use `camelCase` per TS
conventions. Parsers are responsible for the mapping.

---

## 5. PlanProgress

Per-run progress tracking. Updated by the Controller as steps execute.

```typescript
interface PlanProgress {
  /** EPIC identifier */
  epicId: string;
  /** Run identifier */
  runId: string;
  /** Git branch for this run */
  branch?: string;
  /** Base commit SHA before the run started */
  baseCommit?: string;
  /** Overall run state: "PLANNING", "EXECUTING", "GATES", "DONE", "ERROR" */
  state?: string;
  /** ISO 8601 start time */
  startedAt?: string;
  /** Currently executing step ID, or null */
  currentStep: string | null;
  /** Per-step status map */
  steps: Record<string, StepProgress>;
  /** Gate results, keyed by gate name */
  gates?: Record<string, unknown>;
  /** PM escalation records */
  escalations?: unknown[];
}

interface StepProgress {
  /** Step execution status */
  status: 'pending' | 'executing' | 'done' | 'failed' | 'skipped';
  /** ISO 8601 time the step started */
  startedAt?: string;
  /** ISO 8601 time the step completed */
  completedAt?: string;
  /** Number of review/retry cycles */
  reviewCycles?: number;
  /** Last review timestamp */
  lastReview?: string | null;
}
```

**Source file:** `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan_progress.json`
**Parser:** `server/parsers/json.ts`

**Example:**
```json
{
  "epic_id": "E-005-1_4-gui-foundation",
  "run_id": "20260225T140000Z",
  "branch": "epic/E-005-1_4-gui-foundation",
  "base_commit": "3867b38",
  "current_step": "step_1_architect",
  "steps": {
    "step_0_backend": {"status": "done", "started_at": "2026-02-25T14:00:15Z", "completed_at": "2026-02-25T14:02:00Z"},
    "step_1_architect": {"status": "executing", "started_at": "2026-02-25T14:02:05Z"},
    "step_2_backend": {"status": "pending"}
  }
}
```

---

## 6. GatesReport

Quality gate results for a completed run. Records each gate's pass/fail status,
output details, and attempt count.

```typescript
interface GatesReport {
  /** EPIC identifier */
  epicId: string;
  /** Run identifier */
  runId: string;
  /** ISO 8601 timestamp of the gates evaluation */
  timestamp: string;
  /** Individual gate results */
  gates: GateResult[];
  /** Overall rollup: "pass" if all gates pass, "fail" otherwise */
  overall: 'pass' | 'fail';
  /** What should happen next: "pm_approval", "retry", "escalate" */
  nextAction: string;
}

interface GateResult {
  /** Gate name (e.g., "tests_pass", "lint_pass", "security_scan_pass") */
  name: string;
  /** Gate outcome */
  status: 'pass' | 'fail' | 'skip';
  /** Gate command output or summary */
  output: string;
  /** Which attempt this was (1-based) */
  attempt: number;
}
```

**Source file:** `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json`
  or `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates/gates_report.json`
**Parser:** `server/parsers/json.ts`

**Example:**
```json
{
  "epic_id": "E-001-1_1",
  "run_id": "run_20260224_1957",
  "timestamp": "2026-02-24T15:32:00Z",
  "gates": [
    {"name": "tests_pass", "status": "pass", "output": "no tests ran in 0.01s", "attempt": 1},
    {"name": "lint_pass", "status": "pass", "output": "All checks passed!", "attempt": 1}
  ],
  "overall": "pass",
  "next_action": "pm_approval"
}
```

---

## 7. Decision

PM decision records — plan approvals, merge approvals, escalation responses.

```typescript
interface Decision {
  /** ISO 8601 timestamp of the decision */
  timestamp: string;
  /** Decision type: "plan_approval", "merge_approval", "escalation_response" */
  type: string;
  /** EPIC this decision relates to */
  epicId: string;
  /** Run this decision relates to */
  runId: string;
  /** The decision outcome: "approved", "rejected", "deferred", "GO" */
  decision: string;
  /** Optional PM feedback or guidance text */
  feedback?: string | null;
  /** How the decision was made: "chat", "auto-mode", "slack" */
  channel?: string;
  /** Time between request and decision, in minutes */
  latencyMinutes?: number;
  /** Validation details (for auto-mode approvals) */
  validation?: {
    schema?: string;
    completeness?: string;
    dependencyGraph?: string;
    runFileQuality?: string;
  };
  /** Who approved — "pm" or "auto-mode" */
  approver?: string;
  /** Mode — "auto" or "manual" */
  mode?: string;
}
```

**Source files:**
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_decision.json` (merge decisions)
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_plan_approval.json` (plan approval)
**Parser:** `server/parsers/json.ts`

**Example (merge approval):**
```json
{
  "timestamp": "2026-02-23T14:37:00Z",
  "type": "merge_approval",
  "epic_id": "E-20260223-6366",
  "run_id": "run_20260223_ffab",
  "decision": "approved",
  "feedback": null,
  "channel": "chat",
  "latency_minutes": 1
}
```

**Example (auto-mode plan approval):**
```json
{
  "approver": "auto-mode",
  "mode": "auto",
  "timestamp": "2026-02-25T14:00:12Z",
  "validation": {
    "schema": "pass",
    "completeness": "pass",
    "dependency_graph": "pass",
    "run_file_quality": "pass"
  }
}
```

---

## 8. AuditReport

Parsed audit report. Audit reports exist in two formats — Markdown
(`audit-report.md`) with human-readable tables and YAML (`audit-report.yaml`)
with machine-readable scores. The interface normalizes both into a single shape.

```typescript
interface AuditReport {
  /** EPIC identifier */
  epicId: string;
  /** ISO 8601 timestamp of the audit */
  timestamp: string;
  /** Who performed the audit (e.g., "auditor-agent") */
  auditor: string;
  /** Merge reference info (e.g., "post-merge (14 files, +207/-126)") */
  mergeRef?: string;

  /** Category scores (0-100 scale, null if not applicable) */
  scores: {
    overall: number;
    codeQuality: number | null;
    security: number | null;
    documentation: number | null;
    process: number | null;
    frontend: number | null;
    database: number | null;
  };

  /** Trend comparison with previous audit */
  trend?: {
    previousAuditId: string | null;
    previousScore: number | null;
    scoreDelta: number | null;
    findingsNew: number;
    findingsResolved: number;
    findingsPersistent: number;
    direction: 'improving' | 'declining' | 'stable' | null;
  };

  /** Individual findings */
  findings: AuditFinding[];
}

interface AuditFinding {
  /** Finding category: "code_quality", "security", "documentation", "process", "frontend", "database" */
  category: string;
  /** Severity: "critical", "high", "medium", "low" */
  severity: 'critical' | 'high' | 'medium' | 'low';
  /** Finding description */
  description: string;
  /** Recommendation for fixing */
  recommendation?: string;
  /** File path related to the finding */
  filePath?: string;
}
```

**Source files:**
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/audit-report.md` (Markdown format)
- `.aid-o/04-engine/evidence/{epic_id}/{run_id}/audit-report.yaml` or
  `.aid-o/04-engine/evidence/{epic_id}/audit-report.yaml` (YAML format)
**Parser:** `server/parsers/markdown.ts` (for .md) and `server/parsers/yaml.ts` (for .yaml)

**Example (YAML format excerpt):**
```yaml
audit_report:
  epic_id: "E-20260223-6366"
  timestamp: "2026-02-23T15:00:00Z"
  auditor: "auditor-agent"
  scores:
    overall: 71
    code_quality: 71
    security: 64
    documentation: 71
    process: 85
    frontend: null
    database: null
```

---

## 9. Idea

An idea entry from `IDEAS.md`. The IDEAS file is a Markdown document with YAML
frontmatter and structured sections per idea. The parser extracts individual
idea records.

```typescript
interface Idea {
  /** Idea identifier (e.g., "I-001") */
  id: string;
  /** Idea title */
  title: string;
  /** Lifecycle status */
  status: 'idea' | 'exploring' | 'planned' | 'done';
  /** Category/topic tags */
  tags: string[];
  /** Priority level */
  priority: 'low' | 'medium' | 'high';
  /** Links to related plans, EPICs, or other ideas (e.g., ["P005-C", "I-001"]) */
  links: string[];
  /** ISO 8601 date when the idea was created (date only, YYYY-MM-DD) */
  createdAt: string;
  /** Full description (raw Markdown) */
  description: string;
  /** Open questions section (raw Markdown). When absent, no questions recorded. */
  openQuestions?: string;
}

interface IdeasFile {
  /** Frontmatter metadata */
  meta: {
    type: string;
    version: number;
    lastUpdated: string;
    counter: number;
  };
  /** All ideas parsed from the file */
  ideas: Idea[];
}
```

**Source file:** `.aid-o/01-plans/IDEAS.md`
**Parser:** `server/parsers/markdown.ts` (gray-matter for frontmatter, custom
section parsing for individual ideas)

**Example (one idea section):**
```markdown
## I-001 -- UI strategie: 3 cesty k frontendu

**Status:** idea
**Kategorie:** gui, frontend, strategy
**Priorita:** high
**Propojeni:** P005-C, P005-D
**Vytvoreno:** 2026-02-25

### Popis
Existujici AID-GUI prototyp...
```

---

## 10. QueueSchedule

A single entry in the EPIC execution queue. The queue file contains an array of
these entries plus a global `paused` flag.

```typescript
interface QueueSchedule {
  /** EPIC identifier */
  epicId: string;
  /** Path to the EPIC spec file */
  path: string;
  /** Execution priority */
  priority: 'low' | 'medium' | 'high' | 'critical';
  /** Queue status */
  status: 'queued' | 'running' | 'completed' | 'failed' | 'paused';
  /** ISO 8601 timestamp when added to queue */
  addedAt: string;
  /** ISO 8601 timestamp when execution started. When absent, not yet started. */
  startedAt: string | null;
  /** ISO 8601 timestamp when execution completed. When absent, not yet completed. */
  completedAt: string | null;
}

interface EpicQueue {
  /** Whether the entire queue is paused */
  paused: boolean;
  /** Ordered list of queue entries */
  queue: QueueSchedule[];
}
```

**Source file:** `.aid-o/04-engine/epic-queue.yaml`
**Parser:** `server/parsers/yaml.ts`

**Example:**
```yaml
paused: false
queue:
  - epic_id: "E-005-1_4-gui-foundation"
    path: ".aid-o/02-epics/E-005-1_4-gui-foundation.md"
    priority: high
    status: running
    added_at: "2026-02-25T14:00:00Z"
    started_at: "2026-02-25T14:00:05Z"
    completed_at: null
```

---

## 11. CCUsage

Token usage tracking, estimated from `stage_log.jsonl` entries. This is a
derived/computed type — not directly stored in a file, but calculated by
aggregating stage log data. The GUI uses this for cost dashboards.

```typescript
interface CCUsage {
  /** EPIC this usage belongs to */
  epicId: string;
  /** Run this usage belongs to */
  runId: string;
  /** Total number of stage log entries processed */
  totalEvents: number;
  /** Number of agent dispatch events (proxy for LLM calls) */
  agentDispatches: number;
  /** Number of gate evaluation events */
  gateEvaluations: number;
  /** Number of escalation events */
  escalations: number;
  /** Estimated duration in seconds (from first to last timestamp) */
  durationSeconds: number;
  /** Per-step usage breakdown */
  perStep: StepUsage[];
}

interface StepUsage {
  /** Step identifier */
  stepId: string;
  /** Agent role for this step */
  role: string;
  /** Number of events related to this step */
  eventCount: number;
  /** Duration in seconds (start to finish of this step) */
  durationSeconds: number;
  /** How many times this step was retried */
  retries: number;
}
```

**Source file:** Derived from `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`
  and `.aid-o/04-engine/auto-mode-state.yaml` (aggregate section)
**Parser:** Computed by aggregation logic on top of `server/parsers/jsonl.ts`

**Note:** Actual LLM token counts are not available in `.aid-o/` files. This
interface tracks proxy metrics (event counts, dispatch counts, durations) that
the GUI can display. True token usage may be added in a future EPIC if Claude
Code exposes usage data.

---

## 12. Project

Multi-project registry entry. Represents a project that the GUI can monitor.
Since AID can be installed in multiple projects, the GUI needs to know which
projects exist and where their `.aid-o/` directories are.

```typescript
interface Project {
  /** Unique project identifier (user-assigned or auto-generated) */
  id: string;
  /** Human-readable project name */
  name: string;
  /** Absolute filesystem path to the project root */
  path: string;
  /** Whether this is the currently active/displayed project */
  active: boolean;
  /** Path to the .aid-o/ directory (usually `${path}/.aid-o/`) */
  aidoPath: string;
  /** ISO 8601 timestamp when the project was registered */
  registeredAt: string;
  /** ISO 8601 timestamp of last activity detected. When absent, never accessed. */
  lastActivityAt?: string;
  /** Quick health check — can the GUI read the .aid-o/ directory? */
  accessible: boolean;
}
```

**Source file:** `~/.aid-gui/projects.json` (user-level config, outside `.aid-o/`)
**Parser:** `server/parsers/json.ts`

**Note:** This file does not exist yet. It will be created in EPIC 3 (REST API)
when the projects endpoint is implemented. The interface is defined here so that
all downstream agents have a consistent contract.

**Example:**
```json
[
  {
    "id": "ai-orchestrator",
    "name": "AID Orchestrator",
    "path": "/opt/_home/small-personal-projetcs/ai-orchestrator",
    "active": true,
    "aido_path": "/opt/_home/small-personal-projetcs/ai-orchestrator/.aid-o",
    "registered_at": "2026-02-25T14:00:00Z",
    "last_activity_at": "2026-02-25T14:30:00Z",
    "accessible": true
  }
]
```

---

## FSMState Reuse

The React frontend already defines FSM states in `src/store.ts`. The server
should define its own `FSMState` type (or string union) in `server/types.ts`
for the pipeline states used throughout the interfaces above:

```typescript
type FSMState =
  | 'IDLE'
  | 'PLANNING'
  | 'PLAN_REVIEW'
  | 'EXECUTING'
  | 'PHASE_CHECK'
  | 'NEXT_PHASE'
  | 'GATES'
  | 'CURATOR_RESOLVE'
  | 'PM_APPROVAL'
  | 'DONE'
  | 'ERROR';
```

The `PipelineState.currentState` and `StageLogEntry.state` fields should use this
type instead of bare `string` where practical. The domain agent should evaluate
whether to import from `src/store.ts` or redefine in `server/types.ts`. Redefining
is preferred to avoid a server-to-frontend dependency.

---

## Field Naming Convention: snake_case vs camelCase

All `.aid-o/` files use `snake_case` field names (e.g., `epic_id`, `depends_on`,
`started_at`). TypeScript interfaces use `camelCase` per convention (e.g., `epicId`,
`dependsOn`, `startedAt`).

Each parser is responsible for mapping `snake_case` to `camelCase` when constructing
the typed result. This mapping must be documented in the parser implementation.

---

## Summary Table

| # | Interface | Source File(s) | Parser | Format |
|---|-----------|---------------|--------|--------|
| 1 | `StageLogEntry` | `evidence/{epic}/{run}/stage_log.jsonl` | `jsonl.ts` | JSONL |
| 2 | `PipelineState` | `auto-mode-state.yaml`, `plan_progress.json` | `yaml.ts`, `json.ts` | YAML + JSON |
| 3 | `EpicSpec` | `02-epics/{epic}.md` | `markdown.ts` | Markdown + YAML frontmatter |
| 4 | `PlanJSON` | `evidence/{epic}/{run}/plan.json` | `json.ts` | JSON |
| 5 | `PlanProgress` | `evidence/{epic}/{run}/plan_progress.json` | `json.ts` | JSON |
| 6 | `GatesReport` | `evidence/{epic}/{run}/gates_report.json` | `json.ts` | JSON |
| 7 | `Decision` | `evidence/{epic}/{run}/pm_decision.json` | `json.ts` | JSON |
| 8 | `AuditReport` | `evidence/{epic}/{run}/audit-report.{md,yaml}` | `markdown.ts`, `yaml.ts` | Markdown or YAML |
| 9 | `Idea` / `IdeasFile` | `01-plans/IDEAS.md` | `markdown.ts` | Markdown + YAML frontmatter |
| 10 | `QueueSchedule` / `EpicQueue` | `04-engine/epic-queue.yaml` | `yaml.ts` | YAML |
| 11 | `CCUsage` | Derived from `stage_log.jsonl` | `jsonl.ts` (aggregation) | Computed |
| 12 | `Project` | `~/.aid-gui/projects.json` | `json.ts` | JSON |
