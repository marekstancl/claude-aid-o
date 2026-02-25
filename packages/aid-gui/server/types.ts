/**
 * Server-side type definitions for AID Dashboard.
 *
 * All interfaces map to one or more files in the `.aid-o/` directory structure.
 * Parsers in `server/parsers/` return instances of these types via ParseResult<T>.
 *
 * Convention: TypeScript interfaces use camelCase property names. Parsers are
 * responsible for mapping the snake_case fields found in `.aid-o/` files to
 * camelCase when constructing typed results.
 *
 * All timestamp fields use ISO 8601 strings, not Date objects, to preserve
 * JSON serialization fidelity.
 */

// ---------------------------------------------------------------------------
// ParseResult wrapper
// ---------------------------------------------------------------------------

/**
 * Generic wrapper returned by every parser function.
 * The `data` field contains the parsed entity (possibly partial if warnings
 * were generated). `warnings` collects non-fatal parse issues encountered
 * while reading the source file.
 */
export interface ParseResult<T> {
  /** The parsed data. May be partial if warnings were generated. */
  data: T | null;
  /** Non-fatal issues encountered during parsing. Empty array on clean parse. */
  warnings: ParseWarning[];
  /** Original source file path that was parsed. */
  source: string;
}

/** A single non-fatal issue encountered during defensive parsing. */
export interface ParseWarning {
  /** Human-readable description of what went wrong. */
  message: string;
  /** Line number in the source file, if applicable. */
  line?: number;
  /**
   * Severity level:
   * - 'info'    — missing optional field, default used
   * - 'warning' — recoverable error, partial data returned
   * - 'error'   — data loss, field set to null/undefined
   */
  severity: 'info' | 'warning' | 'error';
}

// ---------------------------------------------------------------------------
// FSMState — orchestration finite state machine states
// ---------------------------------------------------------------------------

/**
 * All states the AID orchestration FSM can be in.
 * Redefining here to avoid a server → frontend dependency.
 * Must stay in sync with the frontend store FSMState definition.
 */
export type FSMState =
  | 'IDLE'
  | 'PLANNING'
  | 'PLAN_REVIEW'
  | 'EXECUTING'
  | 'PHASE_CHECK'
  | 'NEXT_PHASE'
  | 'GATES'
  | 'GATE_RETRY'
  | 'ESCALATION'
  | 'CURATOR_RESOLVE'
  | 'PM_APPROVAL'
  | 'DONE'
  | 'ERROR';

// ---------------------------------------------------------------------------
// 1. StageLogEntry
// ---------------------------------------------------------------------------

/**
 * A single line from a `stage_log.jsonl` file.
 * Each line is an independent JSON object recording one orchestration event.
 *
 * Source: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`
 */
export interface StageLogEntry {
  /** ISO 8601 timestamp of the event. */
  timestamp: string;
  /** FSM state at the time of the event. */
  state: FSMState | string;
  /** Step ID this event relates to, or null for pipeline-level events. */
  step: string | null;
  /** Action identifier — what happened (e.g., "dispatch_agent", "gates_complete"). */
  action: string;
  /** Human-readable description of the event. */
  details: string;
  /** Outcome of the event. */
  result: 'pass' | 'fail' | 'pending' | 'skip' | 'success';
}

// ---------------------------------------------------------------------------
// 2. PipelineState and AutoModeSession
// ---------------------------------------------------------------------------

/**
 * Current orchestration state for the GUI pipeline status view.
 * Derived from `auto-mode-state.yaml` (for active auto-mode sessions) or
 * `plan_progress.json` (for individual runs).
 *
 * Source: `.aid-o/04-engine/auto-mode-state.yaml`
 *         `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan_progress.json`
 */
export interface PipelineState {
  /** Current FSM state. */
  currentState: FSMState | string;
  /** The EPIC currently being executed, or null if idle. */
  currentEpicId: string | null;
  /** The step currently being executed, or null. */
  currentStepId: string | null;
  /** Auto-mode session info, present only during auto-mode runs. */
  session?: AutoModeSession;
  /** Progress counters. */
  progress: {
    epicsCompleted: number;
    epicsTotal: number;
    stepsCompleted: number;
    stepsTotal: number;
  };
}

/**
 * Full auto-mode session record from `auto-mode-state.yaml`.
 *
 * Source: `.aid-o/04-engine/auto-mode-state.yaml`
 */
export interface AutoModeSession {
  /** Session identifier (e.g., "FA-20260225T140000Z"). */
  sessionId: string;
  /** Session mode: "auto" or "manual". */
  mode: string;
  /** ISO 8601 start time of the session. */
  startedAt: string;
  /** Who started the session (e.g., "pm"). */
  startedBy: string;
  /** Snapshot of EPIC IDs queued when the session started. */
  queueSnapshot: string[];
  /** Escalation budget and usage for the session. */
  escalation: {
    budget: number;
    count: number;
  };
  /** Aggregate counters across the full session. */
  aggregate: {
    epicsCompleted: number;
    epicsFailed: number;
    totalStepsExecuted: number;
    totalGateRuns: number;
    totalGateRetries: number;
    totalEscalations: number;
  };
}

// ---------------------------------------------------------------------------
// 3. EpicSpec, AcceptanceCriterion, EpicStep
// ---------------------------------------------------------------------------

/**
 * A parsed EPIC specification file (Markdown with YAML frontmatter).
 * Frontmatter holds metadata; body contains structured sections.
 *
 * Source: `.aid-o/02-epics/{epic_id}.md`
 */
export interface EpicSpec {
  /** EPIC identifier, derived from the filename (e.g., "E-005-1_4-gui-foundation"). */
  epicId: string;

  // --- Frontmatter fields ---

  /** Lifecycle status: "active", "completed", "paused", "failed". */
  status: string;
  /** Path to the source plan file. */
  planRef: string;
  /** Total number of EPICs the parent plan contains. */
  planEpicsTotal: number;
  /** Total runs planned for this EPIC. */
  runsTotal: number;
  /** How many runs have completed. */
  runsCompleted: number;

  // --- Parsed body sections ---

  /** EPIC title from the H1 heading. */
  title: string;
  /** Context section content (raw Markdown). */
  context: string;
  /** Goal section content (raw Markdown). */
  goal: string;
  /** Scope section with allowed and forbidden paths. */
  scope: {
    allowedPaths: string[];
    forbiddenPaths: string[];
    rawMarkdown: string;
  };
  /** Artifacts section content (raw Markdown). When absent, no artifacts listed. */
  artifacts?: string;
  /** Constraints section content (raw Markdown). */
  constraints: string;
  /** DoD gate names (e.g., ["tests_pass", "lint_pass", "type_check"]). */
  dodGates: string[];
  /** Acceptance criteria parsed from the AC section. */
  acceptanceCriteria: AcceptanceCriterion[];
  /** Dependencies section content (raw Markdown). When absent, no dependencies. */
  dependencies?: string;
  /** Steps table parsed from the Markdown table in the EPIC. */
  steps: EpicStep[];
  /** Hints section parsed as key-value pairs. When absent, no hints provided. */
  hints?: Record<string, string | number>;
}

/**
 * A single acceptance criterion from an EPIC spec.
 */
export interface AcceptanceCriterion {
  /** The role responsible for this criterion (e.g., "backend", "qa"). */
  role: string;
  /** The criterion text. */
  text: string;
  /** Whether the checkbox is checked in the source Markdown. */
  checked: boolean;
}

/**
 * A single step entry from the EPIC steps table.
 */
export interface EpicStep {
  /** Step number (1-based). */
  number: number;
  /** Agent role assigned to this step. */
  role: string;
  /** Step objective text. */
  objective: string;
  /** Step IDs this step depends on. Empty array if no dependencies. */
  dependsOn: string[];
  /** Parallel group identifier, if this step belongs to a parallel group. */
  parallelGroup?: string;
}

// ---------------------------------------------------------------------------
// 4. PlanJSON, PlanWave, PlanStep, PlanDependency, AnalysisGroup
// ---------------------------------------------------------------------------

/**
 * The execution plan generated by the Planner from an EPIC specification.
 * Defines steps, dependencies, parallel groups, quality gates, and budget.
 *
 * Source: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan.json`
 */
export interface PlanJSON {
  /** EPIC identifier this plan belongs to. */
  epicId: string;
  /** Run identifier (e.g., "20260225T140000Z"). */
  runId?: string;
  /** Path to the source plan .md file. null for standalone EPICs. */
  sourcePlan?: string | null;
  /** Plan version — incremented on re-planning. */
  version?: number;
  /** ISO 8601 timestamp of plan creation. */
  createdAt?: string;
  /** ISO 8601 timestamp of plan generation (alternative to createdAt). */
  generatedAt?: string;
  /** Total number of steps in this plan. */
  totalSteps?: number;
  /** Wave assignments — groups of steps ordered by execution wave. */
  waves?: PlanWave[];
  /** Ordered list of execution steps. */
  steps: PlanStep[];
  /** Explicit ordering constraints between steps. */
  dependencies?: PlanDependency[];
  /** Groups of step IDs that can execute concurrently. */
  parallelGroups?: string[][];
  /** Multi-perspective analysis groups. */
  analysisGroups?: AnalysisGroup[];
  /** Quality gate names to run after all steps complete. */
  gates?: string[];
  /** Execution budget constraints. */
  budget?: {
    maxLlmCostUsd?: number;
    maxRetriesPerGate?: number;
  };
}

/** A wave groups steps that can be executed in the same execution round. */
export interface PlanWave {
  /** Wave number (0-based). */
  wave: number;
  /** Step IDs assigned to this wave. */
  steps: string[];
}

/** A single execution step within a plan. */
export interface PlanStep {
  /** Unique step identifier (e.g., "step_1_architect"). */
  id: string;
  /** Wave number this step belongs to. */
  wave?: number;
  /** Agent role to execute this step. */
  role: string;
  /** What this step must accomplish. */
  objective: string;
  /** Step IDs this step depends on. */
  dependsOn?: string[];
  /** Required inputs for this step. */
  inputs?: string[];
  /** Expected outputs from this step. */
  outputs?: string[];
  /** Step-specific constraints. */
  constraints?: string[];
  /** Filesystem paths this step may modify. */
  allowedPaths?: string[];
  /** Filesystem paths this step must not touch. */
  forbiddenPaths?: string[];
  /**
   * Verifiable acceptance criteria.
   * Named `acceptance` in some plan versions.
   */
  acceptance?: string[];
  /**
   * Alias for acceptance used in some plan versions.
   */
  acceptanceCriteria?: string[];
}

/** An explicit ordering constraint between two steps. */
export interface PlanDependency {
  /** Step ID that must complete first. */
  before: string;
  /** Step ID that depends on 'before'. */
  after: string;
  /** Rationale for this dependency. */
  reason?: string;
}

/** A multi-perspective analysis group — multiple agents review one step. */
export interface AnalysisGroup {
  /** Unique analysis group identifier. */
  id: string;
  /** Step ID being analyzed. */
  target: string;
  /** Agent roles performing the analysis. */
  agents: string[];
  /** Analysis mode. */
  mode: 'review' | 'audit' | 'validation';
  /** How to merge findings from multiple agents. */
  mergeStrategy: 'union' | 'consensus' | 'weighted';
  /** Whether auto-generated or manually specified. */
  trigger?: 'auto' | 'manual';
}

// ---------------------------------------------------------------------------
// 5. PlanProgress and StepProgress
// ---------------------------------------------------------------------------

/**
 * Per-run progress tracking for an EPIC execution.
 * Updated by the Controller as steps execute.
 *
 * Source: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/plan_progress.json`
 */
export interface PlanProgress {
  /** EPIC identifier. */
  epicId: string;
  /** Run identifier. */
  runId: string;
  /** Git branch for this run. */
  branch?: string;
  /** Base commit SHA before the run started. */
  baseCommit?: string;
  /** Overall run state (e.g., "PLANNING", "EXECUTING", "GATES", "DONE", "ERROR"). */
  state?: string;
  /** ISO 8601 start time of the run. */
  startedAt?: string;
  /** Currently executing step ID, or null when between steps. */
  currentStep: string | null;
  /** Per-step status map keyed by step ID. */
  steps: Record<string, StepProgress>;
  /** Gate results keyed by gate name. Shape varies; use unknown for flexibility. */
  gates?: Record<string, unknown>;
  /** PM escalation records. Shape varies per escalation type. */
  escalations?: unknown[];
}

/** Execution status for a single step within a plan run. */
export interface StepProgress {
  /** Step execution status. */
  status: 'pending' | 'executing' | 'done' | 'failed' | 'skipped';
  /** ISO 8601 time the step started. */
  startedAt?: string;
  /** ISO 8601 time the step completed. */
  completedAt?: string;
  /** Number of review/retry cycles this step underwent. */
  reviewCycles?: number;
  /** ISO 8601 timestamp of the last review, or null if none. */
  lastReview?: string | null;
  /**
   * Relative path to step evidence within the run directory.
   * Present in actual plan_progress.json files (e.g., "steps/step_1_backend/").
   */
  evidence?: string;
}

// ---------------------------------------------------------------------------
// 6. GatesReport and GateResult
// ---------------------------------------------------------------------------

/**
 * Quality gate results for a completed run.
 * Records each gate's pass/fail status, output, and attempt count.
 *
 * Source: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates_report.json`
 *         `.aid-o/04-engine/evidence/{epic_id}/{run_id}/gates/gates_report.json`
 *
 * Note: Actual files may store gates as a keyed object rather than an array.
 * Parsers normalize to this array form.
 */
export interface GatesReport {
  /** EPIC identifier. */
  epicId: string;
  /** Run identifier. */
  runId: string;
  /** ISO 8601 timestamp of the gates evaluation. */
  timestamp: string;
  /** Individual gate results (normalized from keyed object or array). */
  gates: GateResult[];
  /** Overall rollup: "pass" if all required gates pass, "fail" otherwise. */
  overall: 'pass' | 'fail';
  /** What should happen next: "pm_approval", "retry", "escalate". */
  nextAction?: string;
}

/** Result for a single quality gate. */
export interface GateResult {
  /** Gate name (e.g., "tests_pass", "lint_pass", "docs_updated"). */
  name: string;
  /** Gate outcome. */
  status: 'pass' | 'fail' | 'skip';
  /** Gate command output or summary text. */
  output: string;
  /** Which attempt this was (1-based). */
  attempt: number;
  /** Whether this gate is required for overall pass. */
  required?: boolean;
}

// ---------------------------------------------------------------------------
// 7. Decision
// ---------------------------------------------------------------------------

/**
 * A PM decision record — plan approvals, merge approvals, escalation responses.
 *
 * Source: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_decision.json`
 *         `.aid-o/04-engine/evidence/{epic_id}/{run_id}/pm_plan_approval.json`
 */
export interface Decision {
  /** ISO 8601 timestamp of the decision. */
  timestamp: string;
  /**
   * Decision type: "plan_approval", "merge_approval", "escalation_response".
   * May be absent in auto-mode plan approvals.
   */
  type?: string;
  /** EPIC this decision relates to. */
  epicId?: string;
  /** Run this decision relates to. */
  runId?: string;
  /**
   * The decision outcome: "approved", "rejected", "deferred", "GO".
   * May be absent in auto-mode approvals (implied by presence of validation).
   */
  decision?: string;
  /** Optional PM feedback or guidance text. null when no feedback provided. */
  feedback?: string | null;
  /** How the decision was made: "chat", "auto-mode", "slack". */
  channel?: string;
  /** Time between request and decision, in minutes. */
  latencyMinutes?: number;
  /** Validation details present in auto-mode plan approvals. */
  validation?: {
    schema?: string;
    completeness?: string;
    dependencyGraph?: string;
    runFileQuality?: string;
  };
  /** Who approved — "pm" or "auto-mode". */
  approver?: string;
  /** Mode of the session — "auto" or "manual". */
  mode?: string;
}

// ---------------------------------------------------------------------------
// 8. AuditReport and AuditFinding
// ---------------------------------------------------------------------------

/**
 * Parsed audit report. Normalizes both Markdown and YAML audit formats into
 * a single interface shape.
 *
 * Source: `.aid-o/04-engine/evidence/{epic_id}/{run_id}/audit-report.md`
 *         `.aid-o/04-engine/evidence/{epic_id}/{run_id}/audit-report.yaml`
 *         `.aid-o/04-engine/evidence/{epic_id}/audit-report.yaml`
 */
export interface AuditReport {
  /** EPIC identifier this audit covers. */
  epicId: string;
  /** ISO 8601 timestamp of the audit. */
  timestamp: string;
  /** Who performed the audit (e.g., "auditor-agent"). */
  auditor: string;
  /** Merge reference info (e.g., "post-merge (14 files, +207/-126)"). */
  mergeRef?: string;

  /** Category scores on a 0–100 scale. null when the category was not applicable. */
  scores: {
    overall: number;
    codeQuality: number | null;
    security: number | null;
    documentation: number | null;
    process: number | null;
    frontend: number | null;
    database: number | null;
  };

  /** Trend comparison with the previous audit for this project. */
  trend?: {
    previousAuditId: string | null;
    previousScore: number | null;
    scoreDelta: number | null;
    findingsNew: number;
    findingsResolved: number;
    findingsPersistent: number;
    direction: 'improving' | 'declining' | 'stable' | null;
  };

  /** All findings from this audit. */
  findings: AuditFinding[];
}

/** A single finding from an audit report. */
export interface AuditFinding {
  /**
   * Finding category: "code_quality", "security", "documentation",
   * "process", "frontend", "database".
   */
  category: string;
  /** Severity level. */
  severity: 'critical' | 'high' | 'medium' | 'low';
  /** Finding description — what was observed. */
  description: string;
  /** Recommendation for fixing this finding. */
  recommendation?: string;
  /** Relevant file path or area in the codebase. */
  filePath?: string;
}

// ---------------------------------------------------------------------------
// 9. Idea and IdeasFile
// ---------------------------------------------------------------------------

/**
 * A single idea entry parsed from `IDEAS.md`.
 *
 * Source: `.aid-o/01-plans/IDEAS.md`
 */
export interface Idea {
  /** Idea identifier (e.g., "I-001"). */
  id: string;
  /** Idea title. */
  title: string;
  /** Lifecycle status of the idea. */
  status: 'idea' | 'exploring' | 'planned' | 'done';
  /** Category or topic tags. */
  tags: string[];
  /** Priority level. */
  priority: 'low' | 'medium' | 'high';
  /** Links to related plans, EPICs, or other ideas (e.g., ["P005-C", "I-001"]). */
  links: string[];
  /** ISO 8601 date when the idea was created (YYYY-MM-DD format). */
  createdAt: string;
  /** Full description of the idea (raw Markdown). */
  description: string;
  /** Open questions section (raw Markdown). When absent, no questions recorded. */
  openQuestions?: string;
}

/**
 * The full parsed IDEAS.md file, including frontmatter metadata and all ideas.
 *
 * Source: `.aid-o/01-plans/IDEAS.md`
 */
export interface IdeasFile {
  /** Frontmatter metadata from the file header. */
  meta: {
    type: string;
    version: number;
    lastUpdated: string;
    counter: number;
  };
  /** All ideas parsed from the file. */
  ideas: Idea[];
}

// ---------------------------------------------------------------------------
// 10. QueueSchedule and EpicQueue
// ---------------------------------------------------------------------------

/**
 * A single entry in the EPIC execution queue.
 *
 * Source: `.aid-o/04-engine/epic-queue.yaml`
 */
export interface QueueSchedule {
  /** EPIC identifier. */
  epicId: string;
  /** Path to the EPIC spec file. */
  path: string;
  /** Execution priority. */
  priority: 'low' | 'medium' | 'high' | 'critical';
  /** Current queue status. */
  status: 'queued' | 'running' | 'completed' | 'failed' | 'paused';
  /** ISO 8601 timestamp when the entry was added to the queue. */
  addedAt: string;
  /** ISO 8601 timestamp when execution started. null when not yet started. */
  startedAt: string | null;
  /** ISO 8601 timestamp when execution completed. null when not yet completed. */
  completedAt: string | null;
}

/**
 * The full EPIC execution queue, including the global pause flag.
 *
 * Source: `.aid-o/04-engine/epic-queue.yaml`
 */
export interface EpicQueue {
  /** Whether the entire queue is paused. When true, no EPICs will start. */
  paused: boolean;
  /** Ordered list of queue entries. */
  queue: QueueSchedule[];
}

// ---------------------------------------------------------------------------
// 11. CCUsage and StepUsage
// ---------------------------------------------------------------------------

/**
 * Token usage and activity metrics for an EPIC run.
 * Derived by aggregating stage_log.jsonl entries — not stored directly in a file.
 * True LLM token counts are not available; this tracks proxy metrics.
 *
 * Source: Computed from `.aid-o/04-engine/evidence/{epic_id}/{run_id}/stage_log.jsonl`
 */
export interface CCUsage {
  /** EPIC this usage belongs to. */
  epicId: string;
  /** Run this usage belongs to. */
  runId: string;
  /** Total number of stage log entries processed. */
  totalEvents: number;
  /** Number of agent dispatch events (proxy for LLM calls). */
  agentDispatches: number;
  /** Number of gate evaluation events. */
  gateEvaluations: number;
  /** Number of escalation events. */
  escalations: number;
  /** Estimated duration in seconds (from first to last timestamp in the log). */
  durationSeconds: number;
  /** Per-step usage breakdown. */
  perStep: StepUsage[];
}

/** Per-step activity metrics derived from stage log aggregation. */
export interface StepUsage {
  /** Step identifier. */
  stepId: string;
  /** Agent role for this step. */
  role: string;
  /** Number of stage log events related to this step. */
  eventCount: number;
  /** Duration in seconds from step start to finish. */
  durationSeconds: number;
  /** How many times this step was retried. */
  retries: number;
}

// ---------------------------------------------------------------------------
// 12. Project
// ---------------------------------------------------------------------------

/**
 * A project registered in the multi-project GUI registry.
 * Represents a project that the AID GUI can monitor.
 *
 * Source: `~/.aid-gui/projects.json` (user-level config, outside `.aid-o/`)
 *
 * Note: This file does not exist yet. It will be created in the REST API EPIC.
 * The interface is defined here so all downstream agents have a consistent contract.
 */
export interface Project {
  /** Unique project identifier (user-assigned or auto-generated). */
  id: string;
  /** Human-readable project name. */
  name: string;
  /** Absolute filesystem path to the project root. */
  path: string;
  /** Whether this is the currently active/displayed project. */
  active: boolean;
  /** Absolute path to the .aid-o/ directory (usually `${path}/.aid-o/`). */
  aidoPath: string;
  /** ISO 8601 timestamp when the project was registered with the GUI. */
  registeredAt: string;
  /** ISO 8601 timestamp of last activity detected. When absent, never accessed. */
  lastActivityAt?: string;
  /** Whether the GUI can read the .aid-o/ directory for this project. */
  accessible: boolean;
}
