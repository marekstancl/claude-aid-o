/**
 * Frontend API response types for the AID Dashboard.
 *
 * These types mirror the server-side types defined in `server/types.ts` but are
 * redefined here because the frontend cannot import from the server module
 * directly (different build targets, no shared package boundary).
 *
 * All response types use the `ApiResponse<T>` envelope returned by every
 * REST endpoint. Error responses use `ApiError`.
 *
 * Convention: All timestamp fields are ISO 8601 strings. Property names use
 * camelCase, matching the server parser output.
 */

// ---------------------------------------------------------------------------
// Response envelope types
// ---------------------------------------------------------------------------

/**
 * Standard API success response envelope.
 *
 * Every successful REST response wraps data in this shape. The `ok` literal
 * discriminant allows callers to narrow between success and error at the
 * type level.
 *
 * @example
 * ```ts
 * const res = await fetch('/api/projects/default/pipeline');
 * const body: ApiResponse<PipelineStateResponse> | ApiError = await res.json();
 * if (body.ok) {
 *   console.log(body.data.currentState);
 * }
 * ```
 */
export interface ApiResponse<T> {
  /** Discriminant: always `true` on success. */
  ok: true;
  /** The response payload. */
  data: T;
  /** Optional metadata attached by the server. */
  meta?: {
    /** Total count of items (before pagination/slicing). */
    total?: number;
    /** Non-fatal warnings generated during request processing. */
    warnings?: string[];
  };
}

/**
 * Standard API error response.
 *
 * Returned for 4xx and 5xx responses. The `ok: false` discriminant allows
 * type-safe narrowing against `ApiResponse<T>`.
 *
 * @example
 * ```ts
 * const body: ApiResponse<unknown> | ApiError = await res.json();
 * if (!body.ok) {
 *   console.error(body.error.code, body.error.message);
 * }
 * ```
 */
export interface ApiError {
  /** Discriminant: always `false` on error. */
  ok: false;
  /** Error details. */
  error: {
    /** Machine-readable error code (e.g., "NOT_FOUND", "BAD_REQUEST"). */
    code: string;
    /** Human-readable error message. */
    message: string;
    /** Additional structured details, when available. */
    details?: unknown;
  };
}

/**
 * Union type for any API response body. Use the `ok` field to narrow.
 */
export type ApiResult<T> = ApiResponse<T> | ApiError;

// ---------------------------------------------------------------------------
// FSMState
// ---------------------------------------------------------------------------

/**
 * All states the AID orchestration FSM can be in.
 *
 * This is the canonical server-side FSM state set. The existing frontend
 * store uses a slightly different set (e.g., PLAN_READY vs PLANNING). Both
 * are retained for backward compatibility; consumers should accept `string`
 * as a fallback for forward-compatibility with new states.
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
// Pipeline endpoint responses
// ---------------------------------------------------------------------------

/**
 * Auto-mode session record.
 *
 * Present in `PipelineStateResponse` only during active auto-mode runs.
 * Source: auto-mode-state.yaml on the server.
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
    /** Maximum escalations allowed in this session. */
    budget: number;
    /** Number of escalations consumed so far. */
    count: number;
  };
  /** Aggregate counters across the full session. */
  aggregate: {
    /** Number of EPICs completed successfully. */
    epicsCompleted: number;
    /** Number of EPICs that failed. */
    epicsFailed: number;
    /** Total steps executed across all EPICs. */
    totalStepsExecuted: number;
    /** Total gate evaluation runs. */
    totalGateRuns: number;
    /** Total gate retries. */
    totalGateRetries: number;
    /** Total escalation events. */
    totalEscalations: number;
  };
}

/**
 * Response from GET /api/projects/:projectId/pipeline.
 *
 * Contains the current orchestration state, active EPIC/step identifiers,
 * optional auto-mode session data, and progress counters.
 */
export interface PipelineStateResponse {
  /** Current FSM state (e.g., "IDLE", "EXECUTING", "GATES"). */
  currentState: FSMState | string;
  /** The EPIC currently being executed, or null if idle. */
  currentEpicId: string | null;
  /** The step currently being executed, or null. */
  currentStepId: string | null;
  /** Auto-mode session info, present only during auto-mode runs. */
  session?: AutoModeSession;
  /** Progress counters for the active run. */
  progress: {
    /** Number of EPICs completed in this session. */
    epicsCompleted: number;
    /** Total EPICs in this session. */
    epicsTotal: number;
    /** Number of steps completed in the current EPIC run. */
    stepsCompleted: number;
    /** Total steps in the current EPIC's plan. */
    stepsTotal: number;
  };
}

// ---------------------------------------------------------------------------
// Stage log
// ---------------------------------------------------------------------------

/**
 * A single stage log entry.
 *
 * Returned as array items from GET /api/projects/:projectId/pipeline/stage-log
 * and also pushed via WebSocket on the `pipeline.stage_log` topic.
 */
export interface StageLogEntryResponse {
  /** ISO 8601 timestamp of the event. */
  timestamp: string;
  /** FSM state at the time of the event. */
  state: FSMState | string;
  /** Step ID this event relates to, or null for pipeline-level events. */
  step: string | null;
  /** Action identifier (e.g., "dispatch_agent", "gates_complete"). */
  action: string;
  /** Human-readable description of the event. */
  details: string;
  /** Outcome of the event. */
  result: 'pass' | 'fail' | 'pending' | 'skip' | 'success';
}

// ---------------------------------------------------------------------------
// Pipeline steps (plan.json steps)
// ---------------------------------------------------------------------------

/**
 * A single execution step from plan.json.
 *
 * Returned as array items from GET /api/projects/:projectId/pipeline/steps.
 */
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
  /** Verifiable acceptance criteria. */
  acceptance?: string[];
  /** Alias for acceptance used in some plan versions. */
  acceptanceCriteria?: string[];
}

/**
 * Response from GET /api/projects/:projectId/pipeline/steps.
 *
 * Returns the flat array of plan steps. The `ApiResponse<T>` envelope
 * wraps this as `ApiResponse<PlanStep[]>`.
 */
export type PipelineStepsResponse = PlanStep[];

// ---------------------------------------------------------------------------
// Step progress
// ---------------------------------------------------------------------------

/**
 * Execution status for a single step within a plan run.
 *
 * Keyed by step ID in PlanProgressResponse.steps.
 */
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
  /** Relative path to step evidence within the run directory. */
  evidence?: string;
}

/**
 * Per-run progress tracking for an EPIC execution.
 *
 * Not directly exposed as a top-level API endpoint, but included in
 * pipeline state computations and WebSocket events.
 */
export interface PlanProgressResponse {
  /** EPIC identifier. */
  epicId: string;
  /** Run identifier. */
  runId: string;
  /** Git branch for this run. */
  branch?: string;
  /** Base commit SHA before the run started. */
  baseCommit?: string;
  /** Overall run state (e.g., "PLANNING", "EXECUTING", "GATES", "DONE"). */
  state?: string;
  /** ISO 8601 start time of the run. */
  startedAt?: string;
  /** Currently executing step ID, or null when between steps. */
  currentStep: string | null;
  /** Per-step status map keyed by step ID. */
  steps: Record<string, StepProgress>;
  /** Gate results keyed by gate name. */
  gates?: Record<string, unknown>;
  /** PM escalation records. */
  escalations?: unknown[];
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

/**
 * A single entry in the EPIC execution queue.
 */
export interface QueueScheduleEntry {
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
  /** ISO 8601 timestamp when execution started. Null when not yet started. */
  startedAt: string | null;
  /** ISO 8601 timestamp when execution completed. Null when not yet completed. */
  completedAt: string | null;
}

/**
 * Response from GET /api/projects/:projectId/queue.
 *
 * Contains the global pause flag and ordered list of queue entries.
 */
export interface QueueResponse {
  /** Whether the entire queue is paused. */
  paused: boolean;
  /** Ordered list of queue entries. */
  queue: QueueScheduleEntry[];
}

/**
 * Schedule configuration for a project.
 */
export interface ScheduleConfig {
  /** Whether scheduling is enabled. */
  enabled: boolean;
  /** Cooldown between runs in seconds. */
  cooldownSeconds: number;
  /** Maximum concurrent runs. */
  maxConcurrent: number;
  /** Delayed start time (ISO 8601), or null. */
  delayedStartAt: string | null;
  /** Whether to auto-pause when CC limit is reached. */
  autoPauseAtCcLimit: boolean;
  /** CC usage threshold for auto-pause. */
  ccLimitThreshold: number;
  /** ISO 8601 timestamp of last completed run, or null. */
  lastRunCompletedAt: string | null;
}

/**
 * Response from GET /api/projects/:projectId/queue/schedule/status.
 */
export interface ScheduleStatusResponse {
  /** Current scheduler state. */
  state: 'idle' | 'cooldown' | 'waiting' | 'ready' | 'paused';
  /** Seconds remaining in cooldown/wait, or null. */
  remainingSeconds: number | null;
  /** Current schedule configuration. */
  config: ScheduleConfig;
  /** ISO 8601 timestamp of this status snapshot. */
  timestamp: string;
}

// ---------------------------------------------------------------------------
// Decisions
// ---------------------------------------------------------------------------

/**
 * A PM decision record.
 *
 * Returned as array items from GET /api/projects/:projectId/decisions.
 */
export interface DecisionEntry {
  /** ISO 8601 timestamp of the decision. */
  timestamp: string;
  /** Decision type: "plan_approval", "merge_approval", "escalation_response", "decision". */
  type?: string;
  /** EPIC this decision relates to. */
  epicId?: string;
  /** Run this decision relates to. */
  runId?: string;
  /** The decision outcome: "approved", "rejected", "deferred", "GO". */
  decision?: string;
  /** Optional PM feedback or guidance text. */
  feedback?: string | null;
  /** How the decision was made: "chat", "auto-mode", "slack", "gui". */
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
  /** Who approved: "pm" or "auto-mode". */
  approver?: string;
  /** Mode of the session: "auto" or "manual". */
  mode?: string;
}

/**
 * A pending decision that requires PM action.
 *
 * Returned as array items from GET /api/projects/:projectId/decisions/pending.
 */
export interface PendingDecisionEntry {
  /** EPIC identifier. */
  epicId: string;
  /** Run identifier. */
  runId: string;
  /** Current state of the run (e.g., "PLAN_REVIEW", "PM_APPROVAL"). */
  state: string;
  /** Absolute path to the evidence directory on the server. */
  evidencePath: string;
}

/**
 * Response from GET /api/projects/:projectId/decisions.
 *
 * The API wraps this as `ApiResponse<DecisionEntry[]>` with `meta.total`.
 */
export type DecisionsResponse = DecisionEntry[];

/**
 * Response from GET /api/projects/:projectId/decisions/pending.
 *
 * The API wraps this as `ApiResponse<PendingDecisionEntry[]>` with `meta.total`.
 */
export type PendingDecisionsResponse = PendingDecisionEntry[];

/**
 * Request body for POST /api/projects/:projectId/decisions.
 */
export interface DecisionWriteRequest {
  /** EPIC identifier. */
  epicId: string;
  /** Run identifier. */
  runId: string;
  /** Decision outcome (e.g., "approved", "rejected"). */
  decision: string;
  /** Optional PM feedback text. */
  feedback?: string;
}

// ---------------------------------------------------------------------------
// Usage
// ---------------------------------------------------------------------------

/**
 * Per-EPIC/run usage entry within the usage summary.
 */
export interface UsagePerEpicEntry {
  /** EPIC identifier. */
  epicId: string;
  /** Run identifier. */
  runId: string;
  /** Number of stage log events in this run. */
  events: number;
  /** Duration in seconds from first to last event. */
  durationSeconds: number;
}

/**
 * Response from GET /api/projects/:projectId/usage.
 *
 * Aggregated activity metrics computed from all stage_log.jsonl files.
 */
export interface UsageResponse {
  /** Total number of stage log entries across all runs. */
  totalEvents: number;
  /** Number of agent dispatch events (proxy for LLM calls). */
  agentDispatches: number;
  /** Number of gate evaluation events. */
  gateEvaluations: number;
  /** Number of escalation events. */
  escalations: number;
  /** Per-EPIC/run breakdown. */
  perEpic: UsagePerEpicEntry[];
}

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

/**
 * A single finding from an audit report.
 */
export interface AuditFinding {
  /** Finding category (e.g., "code_quality", "security", "documentation"). */
  category: string;
  /** Severity level. */
  severity: 'critical' | 'high' | 'medium' | 'low';
  /** Finding description. */
  description: string;
  /** Recommendation for fixing this finding. */
  recommendation?: string;
  /** Relevant file path or area in the codebase. */
  filePath?: string;
}

/**
 * Audit report scores and trend data.
 *
 * Returned from GET /api/projects/:projectId/audit and
 * GET /api/projects/:projectId/audit/:epicId.
 */
export interface AuditReportResponse {
  /** EPIC identifier this audit covers. */
  epicId: string;
  /** ISO 8601 timestamp of the audit. */
  timestamp: string;
  /** Who performed the audit (e.g., "auditor-agent"). */
  auditor: string;
  /** Merge reference info. */
  mergeRef?: string;

  /** Category scores on a 0-100 scale. Null when not applicable. */
  scores: {
    /** Overall health score. */
    overall: number;
    /** Code quality score. */
    codeQuality: number | null;
    /** Security score. */
    security: number | null;
    /** Documentation score. */
    documentation: number | null;
    /** Process adherence score. */
    process: number | null;
    /** Frontend quality score. */
    frontend: number | null;
    /** Database quality score. */
    database: number | null;
  };

  /** Trend comparison with the previous audit. */
  trend?: {
    /** Previous audit ID, or null if this is the first. */
    previousAuditId: string | null;
    /** Previous overall score, or null. */
    previousScore: number | null;
    /** Score delta (positive = improvement). */
    scoreDelta: number | null;
    /** Number of new findings. */
    findingsNew: number;
    /** Number of resolved findings. */
    findingsResolved: number;
    /** Number of persistent findings. */
    findingsPersistent: number;
    /** Overall trend direction. */
    direction: 'improving' | 'declining' | 'stable' | null;
  };

  /** All findings from this audit. */
  findings: AuditFinding[];
}

/**
 * Convenience type for the audit health summary used by the satellite panel.
 *
 * This is a lightweight projection of `AuditReportResponse` for dashboard
 * display — just the overall score and finding counts.
 */
export interface AuditHealthResponse {
  /** Overall health score (0-100). Null if no audit has been run. */
  healthScore: number | null;
  /** Total number of findings. */
  totalFindings: number;
  /** Findings broken down by severity. */
  findingsBySeverity: {
    critical: number;
    high: number;
    medium: number;
    low: number;
  };
  /** Trend direction, if available. */
  trendDirection: 'improving' | 'declining' | 'stable' | null;
}

// ---------------------------------------------------------------------------
// Epics
// ---------------------------------------------------------------------------

/**
 * EPIC list entry (summary, not full spec).
 *
 * Returned as array items from GET /api/projects/:projectId/epics.
 */
export interface EpicListEntry {
  /** EPIC identifier. */
  epicId: string;
  /** EPIC title. */
  title: string;
  /** Lifecycle status: "active", "completed", "paused", "failed". */
  status: string;
  /** Path to the source plan file. */
  planRef: string;
}

// ---------------------------------------------------------------------------
// Plans
// ---------------------------------------------------------------------------

/**
 * Plan list entry (summary from frontmatter).
 *
 * Returned as array items from GET /api/projects/:projectId/plans.
 */
export interface PlanListEntry {
  /** Plan identifier. */
  planId: string;
  /** Plan title. */
  title: string;
  /** Plan filename. */
  filename: string;
}

// ---------------------------------------------------------------------------
// Evidence
// ---------------------------------------------------------------------------

/**
 * An entry in the evidence tree representing a run directory.
 */
export interface EvidenceRunEntry {
  /** Run identifier. */
  runId: string;
  /** List of file names in this run directory. */
  files: string[];
  /** Whether a stage_log.jsonl exists in this run. */
  hasStageLog: boolean;
  /** Whether a plan.json exists in this run. */
  hasPlan: boolean;
  /** Whether a gates_report.json exists in this run. */
  hasGatesReport: boolean;
}

/**
 * An entry in the evidence tree representing an EPIC directory.
 */
export interface EvidenceEpicEntry {
  /** EPIC identifier. */
  epicId: string;
  /** Runs within this EPIC's evidence directory. */
  runs: EvidenceRunEntry[];
}

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

/**
 * A project registered in the GUI.
 */
export interface Project {
  /** Unique project identifier. */
  id: string;
  /** Human-readable project name. */
  name: string;
  /** Absolute filesystem path to the project root. */
  path: string;
  /** Whether this is the currently active/displayed project. */
  active: boolean;
  /** Absolute path to the .aid-o/ directory. */
  aidoPath: string;
  /** ISO 8601 timestamp when the project was registered. */
  registeredAt: string;
  /** ISO 8601 timestamp of last activity detected. */
  lastActivityAt?: string;
  /** Whether the GUI can read the .aid-o/ directory. */
  accessible: boolean;
}

// ---------------------------------------------------------------------------
// Evidence file content
// ---------------------------------------------------------------------------

/**
 * Response from GET /api/p/:projectId/evidence/:epicId/:runId/files/*
 *
 * The server parses the file and returns its content in the appropriate format.
 */
export interface EvidenceFileResponse {
  /** Relative path to the file within the run directory. */
  filePath: string;
  /** Detected format of the file content. */
  format: 'json' | 'yaml' | 'jsonl' | 'markdown' | 'text' | 'raw';
  /** Parsed file content. JSON/YAML return objects, JSONL returns array, others return string. */
  content: unknown;
}

// ---------------------------------------------------------------------------
// Ideas
// ---------------------------------------------------------------------------

/**
 * A stored idea with full metadata.
 *
 * Returned from GET/POST/PUT /api/p/:projectId/ideas.
 */
export interface StoredIdea {
  /** Idea identifier (e.g., "I-001"). */
  id: string;
  /** Idea title. */
  title: string;
  /** Full description (Markdown). */
  description: string;
  /** Category or topic tags. */
  tags: string[];
  /** Priority level. */
  priority: 'low' | 'medium' | 'high';
  /** Lifecycle status. */
  status: 'idea' | 'exploring' | 'planned' | 'done';
  /** Linked plan reference, or null. */
  linkedPlan: string | null;
  /** Linked EPIC reference, or null. */
  linkedEpic: string | null;
  /** ISO 8601 creation timestamp. */
  createdAt: string;
  /** ISO 8601 last update timestamp. */
  updatedAt: string;
}

/**
 * Request body for POST /api/p/:projectId/ideas.
 */
export interface IdeaCreateRequest {
  title: string;
  description?: string;
  tags?: string[];
  priority?: 'low' | 'medium' | 'high';
  linkedPlan?: string;
  linkedEpic?: string;
}

/**
 * Request body for PUT /api/p/:projectId/ideas/:ideaId.
 */
export interface IdeaUpdateRequest {
  title?: string;
  description?: string;
  tags?: string[];
  priority?: 'low' | 'medium' | 'high';
  status?: 'idea' | 'exploring' | 'planned' | 'done';
  linkedPlan?: string | null;
  linkedEpic?: string | null;
}

// ---------------------------------------------------------------------------
// Knowledge
// ---------------------------------------------------------------------------

/**
 * A knowledge base item (agent, skill, or command).
 *
 * Returned from GET /api/p/:projectId/knowledge.
 */
export interface KnowledgeItem {
  /** Item type. */
  type: 'agent' | 'skill' | 'command';
  /** Item name (e.g., "architect", "epic-orchestration", "/aid-run-epic"). */
  name: string;
  /** Human-readable description extracted from the Markdown file. */
  description: string;
  /** Source filename (e.g., "architect.md"). */
  filename: string;
}
