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
  DecisionsSlice,
  EvidenceSlice,
  AuditSlice,
  IdeasSlice,
  QueueDetailSlice,
  KnowledgeSlice,
  ProjectsSlice,
  ReplaySlice,
  ReplayState,
} from './types/store';
import type {
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
  Project as ApiProject,
} from './types/api';
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
// DecisionsSlice
// ---------------------------------------------------------------------------

const createDecisionsSlice: StateCreator<
  DashboardStore,
  [],
  [],
  DecisionsSlice
> = (set) => ({
  pendingDecisionsList: [] as PendingDecisionEntry[],
  decisionHistory: [] as DecisionEntry[],
  decisionsLoading: false,

  setPendingDecisionsList: (decisions: PendingDecisionEntry[]) =>
    set({ pendingDecisionsList: decisions }),

  setDecisionHistory: (history: DecisionEntry[]) =>
    set({ decisionHistory: history }),

  setDecisionsLoading: (loading: boolean) =>
    set({ decisionsLoading: loading }),

  addDecisionToHistory: (decision: DecisionEntry) =>
    set((state) => ({
      decisionHistory: [decision, ...state.decisionHistory],
    })),

  removePendingDecision: (epicId: string, runId: string) =>
    set((state) => ({
      pendingDecisionsList: state.pendingDecisionsList.filter(
        (d) => !(d.epicId === epicId && d.runId === runId),
      ),
      pendingDecisions: Math.max(0, state.pendingDecisions - 1),
    })),
});

// ---------------------------------------------------------------------------
// EvidenceSlice
// ---------------------------------------------------------------------------

const createEvidenceSlice: StateCreator<
  DashboardStore,
  [],
  [],
  EvidenceSlice
> = (set) => ({
  evidenceEpics: [] as EvidenceEpicEntry[],
  selectedEvidenceEpic: null,
  selectedEvidenceRun: null,
  selectedEvidenceFile: null,
  evidenceFileContent: null,
  evidenceLoading: false,

  setEvidenceEpics: (epics: EvidenceEpicEntry[]) =>
    set({ evidenceEpics: epics }),

  setEvidenceSelection: (epicId: string | null, runId: string | null, file: string | null) =>
    set({
      selectedEvidenceEpic: epicId,
      selectedEvidenceRun: runId,
      selectedEvidenceFile: file,
      evidenceFileContent: file === null ? null : undefined as unknown as EvidenceFileResponse | null,
    }),

  setEvidenceFileContent: (content: EvidenceFileResponse | null) =>
    set({ evidenceFileContent: content }),

  setEvidenceLoading: (loading: boolean) =>
    set({ evidenceLoading: loading }),
});

// ---------------------------------------------------------------------------
// AuditSlice
// ---------------------------------------------------------------------------

const createAuditSlice: StateCreator<
  DashboardStore,
  [],
  [],
  AuditSlice
> = (set) => ({
  auditReports: [] as AuditReportResponse[],
  latestAudit: null,
  auditLoading: false,

  setAuditReports: (reports: AuditReportResponse[]) =>
    set({
      auditReports: reports,
      latestAudit: reports.length > 0 ? reports[0] : null,
      healthScore: reports.length > 0 ? reports[0].scores.overall : null,
    }),

  setAuditLoading: (loading: boolean) =>
    set({ auditLoading: loading }),
});

// ---------------------------------------------------------------------------
// IdeasSlice
// ---------------------------------------------------------------------------

const createIdeasSlice: StateCreator<
  DashboardStore,
  [],
  [],
  IdeasSlice
> = (set) => ({
  ideas: [] as StoredIdea[],
  ideasLoading: false,

  setIdeas: (ideas: StoredIdea[]) =>
    set({ ideas }),

  addIdea: (idea: StoredIdea) =>
    set((state) => ({ ideas: [...state.ideas, idea] })),

  updateIdea: (ideaId: string, updates: Partial<StoredIdea>) =>
    set((state) => ({
      ideas: state.ideas.map((i) =>
        i.id === ideaId ? { ...i, ...updates } : i,
      ),
    })),

  removeIdea: (ideaId: string) =>
    set((state) => ({
      ideas: state.ideas.filter((i) => i.id !== ideaId),
    })),

  setIdeasLoading: (loading: boolean) =>
    set({ ideasLoading: loading }),
});

// ---------------------------------------------------------------------------
// QueueDetailSlice
// ---------------------------------------------------------------------------

const createQueueDetailSlice: StateCreator<
  DashboardStore,
  [],
  [],
  QueueDetailSlice
> = (set) => ({
  queueEntries: [] as QueueScheduleEntry[],
  scheduleConfig: null,
  scheduleStatus: null,
  usageData: null,
  queueDetailLoading: false,

  setQueueEntries: (entries: QueueScheduleEntry[]) =>
    set({ queueEntries: entries }),

  setScheduleConfig: (config: ScheduleConfig | null) =>
    set({ scheduleConfig: config }),

  setScheduleStatus: (status: ScheduleStatusResponse | null) =>
    set({ scheduleStatus: status }),

  setUsageData: (usage: UsageResponse | null) =>
    set({ usageData: usage }),

  setQueueDetailLoading: (loading: boolean) =>
    set({ queueDetailLoading: loading }),

  reorderQueueEntry: (epicId: string, newIndex: number) =>
    set((state) => {
      const entries = [...state.queueEntries];
      const currentIndex = entries.findIndex((e) => e.epicId === epicId);
      if (currentIndex === -1 || currentIndex === newIndex) return {};
      const [entry] = entries.splice(currentIndex, 1);
      entries.splice(newIndex, 0, entry);
      return { queueEntries: entries };
    }),
});

// ---------------------------------------------------------------------------
// KnowledgeSlice
// ---------------------------------------------------------------------------

const createKnowledgeSlice: StateCreator<
  DashboardStore,
  [],
  [],
  KnowledgeSlice
> = (set) => ({
  knowledgeItems: [] as KnowledgeItem[],
  knowledgeLoading: false,

  setKnowledgeItems: (items: KnowledgeItem[]) =>
    set({ knowledgeItems: items }),

  setKnowledgeLoading: (loading: boolean) =>
    set({ knowledgeLoading: loading }),
});

// ---------------------------------------------------------------------------
// Combined store
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// ProjectsSlice
// ---------------------------------------------------------------------------

const createProjectsSlice: StateCreator<
  DashboardStore,
  [],
  [],
  ProjectsSlice
> = (set) => ({
  projects: [] as ApiProject[],
  activeProject: null,
  projectsLoading: false,

  setProjects: (projects: ApiProject[]) =>
    set({ projects }),

  setActiveProject: (project: ApiProject | null) =>
    set({ activeProject: project }),

  setProjectsLoading: (loading: boolean) =>
    set({ projectsLoading: loading }),
});

// ---------------------------------------------------------------------------
// ReplaySlice
// ---------------------------------------------------------------------------

const createReplaySlice: StateCreator<
  DashboardStore,
  [],
  [],
  ReplaySlice
> = (set) => ({
  replayState: 'idle' as ReplayState,
  replayEvents: [] as StageLogEntryResponse[],
  replayIndex: 0,
  playbackSpeed: 1,

  setReplayState: (state: ReplayState) =>
    set({ replayState: state }),

  setReplayEvents: (events: StageLogEntryResponse[]) =>
    set({ replayEvents: events }),

  setReplayIndex: (index: number) =>
    set({ replayIndex: index }),

  setPlaybackSpeed: (speed: number) =>
    set({ playbackSpeed: speed }),

  resetReplay: () =>
    set({
      replayState: 'idle' as ReplayState,
      replayEvents: [] as StageLogEntryResponse[],
      replayIndex: 0,
      playbackSpeed: 1,
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
  ...createDecisionsSlice(...args),
  ...createEvidenceSlice(...args),
  ...createAuditSlice(...args),
  ...createIdeasSlice(...args),
  ...createQueueDetailSlice(...args),
  ...createKnowledgeSlice(...args),
  ...createProjectsSlice(...args),
  ...createReplaySlice(...args),
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
