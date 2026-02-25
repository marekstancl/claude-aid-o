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

import type { FSMState, PlanStep, StageLogEntryResponse } from './api';
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
  & LegacySlice;
