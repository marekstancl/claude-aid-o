/**
 * Zustand store slice interfaces for the AID Dashboard.
 *
 * Defines the shape of each store slice and the combined `DashboardStore`
 * type. The store is organized into feature slices that are composed using
 * Zustand's slice pattern (`StateCreator`).
 *
 * Existing store fields from `src/store.ts` (fsmState, progress, epic,
 * duration, currentProject, setProject, setFSMState, updatePipeline) are
 * preserved in the `LegacySlice` and `DashboardStore` to maintain backward
 * compatibility during migration.
 *
 * Slice composition:
 *   DashboardStore = ConnectionSlice
 *                  & PipelineSlice
 *                  & StageLogSlice
 *                  & SatelliteSlice
 *                  & LegacySlice
 */

import type {
  FSMState,
  PlanStep,
  StageLogEntryResponse,
  PendingDecisionEntry,
  DecisionEntry,
  EvidenceEpicEntry,
  EvidenceFileResponse,
  AuditReportResponse,
  StoredIdea,
  QueueScheduleEntry,
  ScheduleConfig,
  ScheduleStatusResponse,
  UsageResponse,
  KnowledgeItem,
  Project,
  BacklogEntry,
  LessonEntry,
  CompanionMessage,
  CompanionSessionSummary,
  CompanionSession,
  CompanionStatus,
} from './api';
import type { WsConnectionStatus, EventTopic } from './ws';

// ---------------------------------------------------------------------------
// ConnectionSlice — WebSocket connection state
// ---------------------------------------------------------------------------

/**
 * Manages the WebSocket connection lifecycle.
 *
 * Tracks connection status, heartbeat timing, reconnection attempts, and
 * active subscriptions. The connection manager writes to this slice;
 * UI components read from it.
 */
export interface ConnectionSlice {
  // --- State ---

  /** Current WebSocket connection status. */
  wsStatus: WsConnectionStatus;

  /** ISO 8601 timestamp of the last heartbeat received from the server. */
  lastHeartbeat: string | null;

  /**
   * Number of consecutive reconnection attempts since the last successful
   * connection. Reset to 0 on successful connect.
   */
  reconnectAttempt: number;

  /** Number of clients connected to the server (from heartbeat). */
  serverClientCount: number;

  /** Topics the client is currently subscribed to. */
  subscribedTopics: EventTopic[];

  // --- Actions ---

  /** Update the WebSocket connection status. */
  setWsStatus: (status: WsConnectionStatus) => void;

  /** Record a heartbeat from the server. */
  handleHeartbeat: (timestamp: string, clientCount: number) => void;

  /** Increment the reconnection attempt counter. */
  incrementReconnectAttempt: () => void;

  /** Reset the reconnection attempt counter (called on successful connect). */
  resetReconnectAttempt: () => void;

  /** Update the list of subscribed topics. */
  setSubscribedTopics: (topics: EventTopic[]) => void;
}

// ---------------------------------------------------------------------------
// PipelineSlice — orchestration pipeline state
// ---------------------------------------------------------------------------

/**
 * Progress counters for the current EPIC run.
 */
export interface PipelineProgress {
  /** Number of EPICs completed in the session. */
  epicsCompleted: number;
  /** Total EPICs in the session. */
  epicsTotal: number;
  /** Number of steps completed in the current run. */
  stepsCompleted: number;
  /** Total steps in the current plan. */
  stepsTotal: number;
}

/**
 * Manages the orchestration pipeline state.
 *
 * This is the primary data slice, populated from both the REST API
 * (initial load) and WebSocket events (real-time updates).
 */
export interface PipelineSlice {
  // --- State ---

  /** Current FSM state from the pipeline. */
  currentState: FSMState | string;

  /** The EPIC currently being executed, or null if idle. */
  currentEpicId: string | null;

  /** The step currently being executed, or null. */
  currentStepId: string | null;

  /** Progress counters for the current run. */
  pipelineProgress: PipelineProgress;

  /** Ordered list of steps from plan.json. Empty when no plan is loaded. */
  steps: PlanStep[];

  /** Per-step status keyed by step ID. */
  stepStatuses: Record<string, StepStatus>;

  // --- Actions ---

  /** Replace the full pipeline state (from REST or WS event). */
  setPipelineState: (state: {
    currentState: FSMState | string;
    currentEpicId: string | null;
    currentStepId: string | null;
    progress: PipelineProgress;
  }) => void;

  /** Replace the steps list (from GET /pipeline/steps). */
  setSteps: (steps: PlanStep[]) => void;

  /** Update the status of a single step. */
  updateStepStatus: (stepId: string, status: StepStatus) => void;

  /** Bulk-update step statuses (from plan_progress). */
  setStepStatuses: (statuses: Record<string, StepStatus>) => void;
}

/**
 * Status record for a single pipeline step.
 *
 * This is the frontend projection of `StepProgress` from the API, with
 * the addition of a computed `isActive` flag.
 */
export interface StepStatus {
  /** Step execution status. */
  status: 'pending' | 'executing' | 'done' | 'failed' | 'skipped';
  /** ISO 8601 time the step started. */
  startedAt?: string;
  /** ISO 8601 time the step completed. */
  completedAt?: string;
  /** Number of review/retry cycles. */
  reviewCycles?: number;
}

// ---------------------------------------------------------------------------
// StageLogSlice — live stage log feed
// ---------------------------------------------------------------------------

/**
 * Manages the stage log entry buffer for the live log panel.
 *
 * Entries are appended from WebSocket events and from the initial REST
 * fetch. A maximum buffer size prevents unbounded memory growth.
 */
export interface StageLogSlice {
  // --- State ---

  /** Buffered stage log entries, ordered oldest-first. */
  stageLogEntries: StageLogEntryResponse[];

  /**
   * Maximum number of entries to retain in the buffer.
   * Older entries are discarded when this limit is exceeded.
   */
  stageLogMaxEntries: number;

  // --- Actions ---

  /** Append a single entry to the log buffer. */
  addStageLogEntry: (entry: StageLogEntryResponse) => void;

  /**
   * Append multiple entries to the log buffer.
   * Used for initial REST load and WebSocket replay.
   */
  addStageLogEntries: (entries: StageLogEntryResponse[]) => void;

  /** Clear all entries from the buffer. */
  clearStageLog: () => void;
}

// ---------------------------------------------------------------------------
// SatelliteSlice — secondary dashboard data
// ---------------------------------------------------------------------------

/**
 * Manages data for the satellite panels: queue, audit health, pending
 * decisions, and CC usage metrics.
 *
 * These are updated less frequently than pipeline state, typically on
 * initial load and when relevant WebSocket events arrive.
 */
export interface SatelliteSlice {
  // --- State ---

  /** Number of entries currently in the EPIC queue. */
  queueCount: number;

  /** Whether the queue is paused. */
  queuePaused: boolean;

  /** Overall audit health score (0-100). Null if no audit data. */
  healthScore: number | null;

  /** Number of pending PM decisions. */
  pendingDecisions: number;

  /** CC usage summary metrics. */
  ccUsage: {
    /** Total stage log events across all runs. */
    totalEvents: number;
    /** Number of agent dispatch events. */
    agentDispatches: number;
    /** Number of gate evaluation events. */
    gateEvaluations: number;
    /** Number of escalation events. */
    escalations: number;
  };

  // --- Actions ---

  /** Update queue count and paused state. */
  setQueueInfo: (count: number, paused: boolean) => void;

  /** Update the audit health score. */
  setHealthScore: (score: number | null) => void;

  /** Update the pending decisions count. */
  setPendingDecisions: (count: number) => void;

  /** Update the CC usage metrics. */
  setCcUsage: (usage: {
    totalEvents: number;
    agentDispatches: number;
    gateEvaluations: number;
    escalations: number;
  }) => void;
}

// ---------------------------------------------------------------------------
// LegacySlice — backward-compatible fields from the existing store
// ---------------------------------------------------------------------------

/**
 * Existing store fields from `src/store.ts`.
 *
 * These are preserved for backward compatibility during migration. New code
 * should prefer the typed slice fields (e.g., `currentState` over `fsmState`,
 * `pipelineProgress` over `progress`).
 *
 * The existing `FSMState` type from the store includes states not in the
 * server FSM (PLAN_READY, PHASE_RETRY, GATES_RETRY). These are preserved
 * here as a string union for compatibility.
 */
export type LegacyFSMState =
  | 'IDLE'
  | 'PLAN_REVIEW'
  | 'PLAN_READY'
  | 'EXECUTING'
  | 'PHASE_CHECK'
  | 'PHASE_RETRY'
  | 'GATES'
  | 'GATES_RETRY'
  | 'PM_APPROVAL'
  | 'CURATOR_RESOLVE'
  | 'DONE'
  | 'ERROR';

/**
 * Lightweight project reference used in the existing store.
 *
 * The existing store's Project type is simpler than the full server Project.
 * This is preserved for backward compatibility.
 */
export interface LegacyProject {
  /** Project identifier. */
  id: string;
  /** Project display name. */
  name: string;
  /** Project health score. */
  health: number;
}

export interface LegacySlice {
  // --- State ---

  /** Current project. Null when no project is selected. */
  currentProject: LegacyProject | null;

  /** FSM state (legacy type with store-specific states). */
  fsmState: LegacyFSMState;

  /** Progress percentage (0-100). */
  progress: number;

  /** Active step identifier. */
  activeStep: string | null;

  /** Current EPIC identifier. */
  epic: string | null;

  /** Duration display string (e.g., "2m 30s"). */
  duration: string | null;

  // --- Actions ---

  /** Set the current project. */
  setProject: (project: LegacyProject) => void;

  /** Set the FSM state (legacy). */
  setFSMState: (state: LegacyFSMState) => void;

  /** Partial update of the store (legacy catch-all updater). */
  updatePipeline: (data: Partial<LegacySliceState>) => void;
}

/**
 * The state-only portion of LegacySlice (without actions), used as the
 * parameter type for `updatePipeline`.
 */
export type LegacySliceState = Omit<LegacySlice, 'setProject' | 'setFSMState' | 'updatePipeline'>;

// ---------------------------------------------------------------------------
// ProjectsSlice — multi-project management
// ---------------------------------------------------------------------------

/**
 * Manages the list of registered projects and the active project.
 */
export interface ProjectsSlice {
  // --- State ---

  /** All registered projects. */
  projects: Project[];

  /** The currently active project, or null. */
  activeProject: Project | null;

  /** Whether projects are loading. */
  projectsLoading: boolean;

  // --- Actions ---

  /** Replace the projects list. */
  setProjects: (projects: Project[]) => void;

  /** Set the active project. */
  setActiveProject: (project: Project | null) => void;

  /** Set projects loading state. */
  setProjectsLoading: (loading: boolean) => void;
}

// ---------------------------------------------------------------------------
// ReplaySlice — Pipeline Theater replay state
// ---------------------------------------------------------------------------

/** Replay state machine states. */
export type ReplayState = 'idle' | 'playing' | 'paused' | 'scrubbing';

/**
 * Manages Pipeline Theater replay state.
 */
export interface ReplaySlice {
  // --- State ---

  /** Current replay state. */
  replayState: ReplayState;

  /** Full stage log entries for replay. */
  replayEvents: StageLogEntryResponse[];

  /** Current event index in the replay. */
  replayIndex: number;

  /** Playback speed multiplier (1, 2, or 4). */
  playbackSpeed: number;

  // --- Actions ---

  /** Set the replay state. */
  setReplayState: (state: ReplayState) => void;

  /** Load events for replay. */
  setReplayEvents: (events: StageLogEntryResponse[]) => void;

  /** Set the current replay index. */
  setReplayIndex: (index: number) => void;

  /** Set the playback speed. */
  setPlaybackSpeed: (speed: number) => void;

  /** Reset replay to initial state. */
  resetReplay: () => void;
}

// ---------------------------------------------------------------------------
// DashboardStore — combined store type
// ---------------------------------------------------------------------------

/**
 * The complete Zustand store type.
 *
 * This is the intersection of all slices. Components can select individual
 * fields or entire slices using Zustand selectors:
 *
 * @example
 * ```ts
 * const wsStatus = useStore((s) => s.wsStatus);
 * const { currentState, currentEpicId } = useStore((s) => ({
 *   currentState: s.currentState,
 *   currentEpicId: s.currentEpicId,
 * }));
 * ```
 */
// ---------------------------------------------------------------------------
// DecisionsSlice — Decision Hub data
// ---------------------------------------------------------------------------

/**
 * Manages pending decisions and decision history for the Decision Hub screen.
 */
export interface DecisionsSlice {
  // --- State ---

  /** Pending decisions requiring PM action. */
  pendingDecisionsList: PendingDecisionEntry[];

  /** Historical decision records, newest first. */
  decisionHistory: DecisionEntry[];

  /** Whether the decisions data is currently loading. */
  decisionsLoading: boolean;

  // --- Actions ---

  /** Replace the pending decisions list. */
  setPendingDecisionsList: (decisions: PendingDecisionEntry[]) => void;

  /** Replace the decision history. */
  setDecisionHistory: (history: DecisionEntry[]) => void;

  /** Set decisions loading state. */
  setDecisionsLoading: (loading: boolean) => void;

  /** Add a new decision to history (optimistic update). */
  addDecisionToHistory: (decision: DecisionEntry) => void;

  /** Remove a pending decision by epicId+runId (after approve/reject). */
  removePendingDecision: (epicId: string, runId: string) => void;
}

// ---------------------------------------------------------------------------
// EvidenceSlice — Evidence Vault data
// ---------------------------------------------------------------------------

/**
 * Manages evidence tree and file content for the Evidence Vault screen.
 */
export interface EvidenceSlice {
  // --- State ---

  /** EPIC evidence entries with their runs. */
  evidenceEpics: EvidenceEpicEntry[];

  /** Currently selected EPIC ID in the evidence browser. */
  selectedEvidenceEpic: string | null;

  /** Currently selected run ID in the evidence browser. */
  selectedEvidenceRun: string | null;

  /** Currently selected file path in the evidence browser. */
  selectedEvidenceFile: string | null;

  /** Content of the currently selected evidence file. */
  evidenceFileContent: EvidenceFileResponse | null;

  /** Whether evidence data is loading. */
  evidenceLoading: boolean;

  // --- Actions ---

  /** Replace the evidence EPIC list. */
  setEvidenceEpics: (epics: EvidenceEpicEntry[]) => void;

  /** Set the selected EPIC/run/file in the evidence browser. */
  setEvidenceSelection: (epicId: string | null, runId: string | null, file: string | null) => void;

  /** Set the file content for the selected evidence file. */
  setEvidenceFileContent: (content: EvidenceFileResponse | null) => void;

  /** Set evidence loading state. */
  setEvidenceLoading: (loading: boolean) => void;
}

// ---------------------------------------------------------------------------
// AuditSlice — Health Observatory data
// ---------------------------------------------------------------------------

/**
 * Manages audit report data for the Health Observatory screen.
 */
export interface AuditSlice {
  // --- State ---

  /** All available audit reports (most recent first). */
  auditReports: AuditReportResponse[];

  /** The latest audit report (first in auditReports). */
  latestAudit: AuditReportResponse | null;

  /** Whether audit data is loading. */
  auditLoading: boolean;

  // --- Actions ---

  /** Replace the audit reports list. */
  setAuditReports: (reports: AuditReportResponse[]) => void;

  /** Set audit loading state. */
  setAuditLoading: (loading: boolean) => void;
}

// ---------------------------------------------------------------------------
// IdeasSlice — Ideas to Execution data
// ---------------------------------------------------------------------------

/**
 * Manages idea items for the Ideas to Execution Kanban screen.
 */
export interface IdeasSlice {
  // --- State ---

  /** All ideas. */
  ideas: StoredIdea[];

  /** Whether ideas data is loading. */
  ideasLoading: boolean;

  // --- Actions ---

  /** Replace the full ideas list. */
  setIdeas: (ideas: StoredIdea[]) => void;

  /** Add a new idea (from Quick Capture). */
  addIdea: (idea: StoredIdea) => void;

  /** Update an existing idea (status change, edit, etc.). */
  updateIdea: (ideaId: string, updates: Partial<StoredIdea>) => void;

  /** Remove an idea by ID. */
  removeIdea: (ideaId: string) => void;

  /** Set ideas loading state. */
  setIdeasLoading: (loading: boolean) => void;
}

// ---------------------------------------------------------------------------
// QueueDetailSlice — Queue Scheduler data
// ---------------------------------------------------------------------------

/**
 * Manages detailed queue data for the Queue Scheduler screen.
 *
 * This extends the basic SatelliteSlice queue data with full entry details,
 * schedule configuration, and usage metrics.
 */
export interface QueueDetailSlice {
  // --- State ---

  /** Full queue entries with all details. */
  queueEntries: QueueScheduleEntry[];

  /** Schedule configuration. */
  scheduleConfig: ScheduleConfig | null;

  /** Current scheduler status. */
  scheduleStatus: ScheduleStatusResponse | null;

  /** Detailed usage data. */
  usageData: UsageResponse | null;

  /** Whether queue detail data is loading. */
  queueDetailLoading: boolean;

  // --- Actions ---

  /** Replace the full queue entries list. */
  setQueueEntries: (entries: QueueScheduleEntry[]) => void;

  /** Update the schedule configuration. */
  setScheduleConfig: (config: ScheduleConfig | null) => void;

  /** Update the scheduler status. */
  setScheduleStatus: (status: ScheduleStatusResponse | null) => void;

  /** Update the usage data. */
  setUsageData: (usage: UsageResponse | null) => void;

  /** Set queue detail loading state. */
  setQueueDetailLoading: (loading: boolean) => void;

  /** Reorder a queue entry (move to new index). */
  reorderQueueEntry: (epicId: string, newIndex: number) => void;
}

// ---------------------------------------------------------------------------
// KnowledgeSlice — Knowledge Base data
// ---------------------------------------------------------------------------

/**
 * Manages knowledge base items for the Knowledge Base screen.
 */
export interface KnowledgeSlice {
  // --- State ---

  /** All knowledge items (agents, skills, commands). */
  knowledgeItems: KnowledgeItem[];

  /** Whether knowledge data is loading. */
  knowledgeLoading: boolean;

  // --- Actions ---

  /** Replace the knowledge items list. */
  setKnowledgeItems: (items: KnowledgeItem[]) => void;

  /** Set knowledge loading state. */
  setKnowledgeLoading: (loading: boolean) => void;
}

// ---------------------------------------------------------------------------
// InsightsSlice — Backlog & Lessons data
// ---------------------------------------------------------------------------

/**
 * Manages backlog entries and lesson/gotcha entries for the Insights panel.
 *
 * Data is fetched from the backlog and lessons REST endpoints and displayed
 * in the Insights UI. The slice provides loading state for coordinated
 * fetch indicators.
 */
export interface InsightsSlice {
  // --- State ---

  /** Improvement backlog entries. */
  backlogEntries: BacklogEntry[];

  /** Lessons learned and gotcha entries. */
  lessonEntries: LessonEntry[];

  /** Whether insights data is currently loading. */
  insightsLoading: boolean;

  // --- Actions ---

  /** Replace the backlog entries list. */
  setBacklogEntries: (entries: BacklogEntry[]) => void;

  /** Replace the lesson entries list. */
  setLessonEntries: (entries: LessonEntry[]) => void;

  /** Set insights loading state. */
  setInsightsLoading: (loading: boolean) => void;
}

// ---------------------------------------------------------------------------
// CompanionSlice — AI Companion chat state
// ---------------------------------------------------------------------------

/**
 * Manages the AI Companion chat panel state: sessions, messages, streaming,
 * and adapter status.
 */
export interface CompanionSlice {
  // --- State ---

  /** Whether the companion panel is open. */
  companionOpen: boolean;

  /** List of session summaries for the session selector. */
  companionSessions: CompanionSessionSummary[];

  /** The currently active session with full message history, or null. */
  companionCurrentSession: CompanionSession | null;

  /** Whether an SSE stream is currently in progress. */
  companionStreaming: boolean;

  /** Accumulated text from the current SSE stream (displayed as typing). */
  companionStreamingText: string;

  /** Adapter availability status, or null if not yet fetched. */
  companionStatus: CompanionStatus | null;

  /** Current error message, or null. */
  companionError: string | null;

  // --- Actions ---

  /** Set whether the companion panel is open. */
  setCompanionOpen: (open: boolean) => void;

  /** Toggle the companion panel open/closed. */
  toggleCompanion: () => void;

  /** Replace the session summaries list. */
  setCompanionSessions: (sessions: CompanionSessionSummary[]) => void;

  /** Set the current session (with messages). */
  setCompanionCurrentSession: (session: CompanionSession | null) => void;

  /** Set the streaming flag. */
  setCompanionStreaming: (streaming: boolean) => void;

  /** Append text to the streaming buffer. */
  appendCompanionStreamText: (text: string) => void;

  /** Reset the streaming buffer to empty. */
  resetCompanionStream: () => void;

  /** Add a message to the current session's message list. */
  addCompanionMessage: (message: CompanionMessage) => void;

  /** Set the adapter status. */
  setCompanionStatus: (status: CompanionStatus | null) => void;

  /** Set or clear the error message. */
  setCompanionError: (error: string | null) => void;
}

// ---------------------------------------------------------------------------
// DashboardStore — combined store type
// ---------------------------------------------------------------------------

/**
 * The complete Zustand store type.
 *
 * This is the intersection of all slices. Components can select individual
 * fields or entire slices using Zustand selectors:
 *
 * @example
 * ```ts
 * const wsStatus = useStore((s) => s.wsStatus);
 * const { currentState, currentEpicId } = useStore((s) => ({
 *   currentState: s.currentState,
 *   currentEpicId: s.currentEpicId,
 * }));
 * ```
 */
export type DashboardStore =
  & ConnectionSlice
  & PipelineSlice
  & StageLogSlice
  & SatelliteSlice
  & LegacySlice
  & DecisionsSlice
  & EvidenceSlice
  & AuditSlice
  & IdeasSlice
  & QueueDetailSlice
  & KnowledgeSlice
  & InsightsSlice
  & ProjectsSlice
  & ReplaySlice
  & CompanionSlice;
