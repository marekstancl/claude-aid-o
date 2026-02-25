/**
 * Zustand store for the AID Dashboard.
 *
 * Composed from typed slices defined in `src/types/store.ts`. All existing
 * exports (FSMState, Project, useStore, stateColors) are preserved for
 * backward compatibility with screens and components that import them.
 *
 * Slice composition:
 *   DashboardStore = ConnectionSlice
 *                  & PipelineSlice
 *                  & StageLogSlice
 *                  & SatelliteSlice
 *                  & LegacySlice
 */

import { create, type StateCreator } from 'zustand';

import type {
  ConnectionSlice,
  PipelineSlice,
  PipelineProgress,
  StageLogSlice,
  SatelliteSlice,
  LegacySlice,
  LegacyFSMState,
  LegacyProject,
  DashboardStore,
  StepStatus,
} from './types/store';
import type { StageLogEntryResponse } from './types/api';
import type { WsConnectionStatus, EventTopic } from './types/ws';

// ---------------------------------------------------------------------------
// Re-exports for backward compatibility
// ---------------------------------------------------------------------------

/**
 * @deprecated Use `LegacyFSMState` from `./types/store` for new code.
 * Kept here so existing screens that `import { FSMState } from '../store'`
 * continue to compile.
 */
export type FSMState =
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
 * @deprecated Use the `Project` type from `./types/api` for full server
 * project data, or `LegacyProject` from `./types/store` for the lightweight
 * store reference. Kept here for backward compatibility.
 */
export interface Project {
  id: string;
  name: string;
  health: number;
}

// ---------------------------------------------------------------------------
// Default stage log buffer size
// ---------------------------------------------------------------------------

const STAGE_LOG_MAX_ENTRIES = 500;

// ---------------------------------------------------------------------------
// Slice creators
// ---------------------------------------------------------------------------

const createConnectionSlice: StateCreator<
  DashboardStore,
  [],
  [],
  ConnectionSlice
> = (set) => ({
  // State
  wsStatus: 'disconnected' as WsConnectionStatus,
  lastHeartbeat: null,
  reconnectAttempt: 0,
  serverClientCount: 0,
  subscribedTopics: [] as EventTopic[],

  // Actions
  setWsStatus: (status: WsConnectionStatus) =>
    set({ wsStatus: status }),

  handleHeartbeat: (timestamp: string, clientCount: number) =>
    set({ lastHeartbeat: timestamp, serverClientCount: clientCount }),

  incrementReconnectAttempt: () =>
    set((state) => ({ reconnectAttempt: state.reconnectAttempt + 1 })),

  resetReconnectAttempt: () =>
    set({ reconnectAttempt: 0 }),

  setSubscribedTopics: (topics: EventTopic[]) =>
    set({ subscribedTopics: topics }),
});

const createPipelineSlice: StateCreator<
  DashboardStore,
  [],
  [],
  PipelineSlice
> = (set) => ({
  // State
  currentState: 'IDLE',
  currentEpicId: null,
  currentStepId: null,
  pipelineProgress: {
    epicsCompleted: 0,
    epicsTotal: 0,
    stepsCompleted: 0,
    stepsTotal: 0,
  } as PipelineProgress,
  steps: [],
  stepStatuses: {} as Record<string, StepStatus>,

  // Actions
  setPipelineState: (pipelineState) =>
    set({
      currentState: pipelineState.currentState,
      currentEpicId: pipelineState.currentEpicId,
      currentStepId: pipelineState.currentStepId,
      pipelineProgress: pipelineState.progress,
    }),

  setSteps: (steps) =>
    set({ steps }),

  updateStepStatus: (stepId: string, status: StepStatus) =>
    set((state) => ({
      stepStatuses: { ...state.stepStatuses, [stepId]: status },
    })),

  setStepStatuses: (statuses: Record<string, StepStatus>) =>
    set({ stepStatuses: statuses }),
});

const createStageLogSlice: StateCreator<
  DashboardStore,
  [],
  [],
  StageLogSlice
> = (set) => ({
  // State
  stageLogEntries: [] as StageLogEntryResponse[],
  stageLogMaxEntries: STAGE_LOG_MAX_ENTRIES,

  // Actions
  addStageLogEntry: (entry: StageLogEntryResponse) =>
    set((state) => {
      const entries = [...state.stageLogEntries, entry];
      if (entries.length > state.stageLogMaxEntries) {
        return { stageLogEntries: entries.slice(entries.length - state.stageLogMaxEntries) };
      }
      return { stageLogEntries: entries };
    }),

  addStageLogEntries: (newEntries: StageLogEntryResponse[]) =>
    set((state) => {
      const entries = [...state.stageLogEntries, ...newEntries];
      if (entries.length > state.stageLogMaxEntries) {
        return { stageLogEntries: entries.slice(entries.length - state.stageLogMaxEntries) };
      }
      return { stageLogEntries: entries };
    }),

  clearStageLog: () =>
    set({ stageLogEntries: [] }),
});

const createSatelliteSlice: StateCreator<
  DashboardStore,
  [],
  [],
  SatelliteSlice
> = (set) => ({
  // State
  queueCount: 0,
  queuePaused: false,
  healthScore: null,
  pendingDecisions: 0,
  ccUsage: {
    totalEvents: 0,
    agentDispatches: 0,
    gateEvaluations: 0,
    escalations: 0,
  },

  // Actions
  setQueueInfo: (count: number, paused: boolean) =>
    set({ queueCount: count, queuePaused: paused }),

  setHealthScore: (score: number | null) =>
    set({ healthScore: score }),

  setPendingDecisions: (count: number) =>
    set({ pendingDecisions: count }),

  setCcUsage: (usage) =>
    set({ ccUsage: usage }),
});

const createLegacySlice: StateCreator<
  DashboardStore,
  [],
  [],
  LegacySlice
> = (set) => ({
  // State
  currentProject: null,
  fsmState: 'IDLE' as LegacyFSMState,
  progress: 0,
  activeStep: null,
  epic: null,
  duration: null,

  // Actions
  setProject: (project: LegacyProject) =>
    set({ currentProject: project }),

  setFSMState: (state: LegacyFSMState) =>
    set({ fsmState: state }),

  updatePipeline: (data) =>
    set((current) => {
      // Only spread state-like fields, not actions
      const update: Record<string, unknown> = {};
      if (data.currentProject !== undefined) update.currentProject = data.currentProject;
      if (data.fsmState !== undefined) update.fsmState = data.fsmState;
      if (data.progress !== undefined) update.progress = data.progress;
      if (data.activeStep !== undefined) update.activeStep = data.activeStep;
      if (data.epic !== undefined) update.epic = data.epic;
      if (data.duration !== undefined) update.duration = data.duration;
      return update;
    }),
});

// ---------------------------------------------------------------------------
// Combined store
// ---------------------------------------------------------------------------

export const useStore = create<DashboardStore>((...args) => ({
  ...createConnectionSlice(...args),
  ...createPipelineSlice(...args),
  ...createStageLogSlice(...args),
  ...createSatelliteSlice(...args),
  ...createLegacySlice(...args),
}));

// ---------------------------------------------------------------------------
// State color mapping (backward compatible)
// ---------------------------------------------------------------------------

export const stateColors: Record<FSMState, string> = {
  IDLE: 'var(--color-state-idle)',
  PLAN_REVIEW: 'var(--color-state-plan-review)',
  PLAN_READY: 'var(--color-state-plan-ready)',
  EXECUTING: 'var(--color-state-executing)',
  PHASE_CHECK: 'var(--color-state-phase-check)',
  PHASE_RETRY: 'var(--color-state-phase-retry)',
  GATES: 'var(--color-state-gates)',
  GATES_RETRY: 'var(--color-state-gates-retry)',
  PM_APPROVAL: 'var(--color-state-pm-approval)',
  CURATOR_RESOLVE: 'var(--color-state-curator-resolve)',
  DONE: 'var(--color-state-done)',
  ERROR: 'var(--color-state-error)',
};
