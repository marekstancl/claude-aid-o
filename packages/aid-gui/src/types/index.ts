/**
 * Barrel export for all frontend type definitions.
 *
 * Usage:
 * ```ts
 * import type { PipelineStateResponse, WsIncomingMessage, DashboardStore } from './types';
 * ```
 *
 * For runtime values (constants, arrays):
 * ```ts
 * import { ALL_EVENT_TOPICS, WS_CLOSE_CODES } from './types';
 * ```
 */

// ---------------------------------------------------------------------------
// API response types
// ---------------------------------------------------------------------------

export type {
  // Envelope types
  ApiResponse,
  ApiError,
  ApiResult,

  // FSM state
  FSMState,

  // Pipeline
  AutoModeSession,
  PipelineStateResponse,
  StageLogEntryResponse,
  PlanStep,
  PipelineStepsResponse,
  StepProgress,
  PlanProgressResponse,

  // Queue
  QueueScheduleEntry,
  QueueResponse,
  ScheduleConfig,
  ScheduleStatusResponse,

  // Decisions
  DecisionEntry,
  PendingDecisionEntry,
  DecisionsResponse,
  PendingDecisionsResponse,
  DecisionWriteRequest,

  // Usage
  UsagePerEpicEntry,
  UsageResponse,

  // Audit
  AuditFinding,
  AuditReportResponse,
  AuditHealthResponse,

  // Epics & Plans
  EpicListEntry,
  PlanListEntry,

  // Evidence
  EvidenceRunEntry,
  EvidenceEpicEntry,
  EvidenceFileResponse,

  // Ideas
  StoredIdea,
  IdeaCreateRequest,
  IdeaUpdateRequest,

  // Knowledge
  KnowledgeItem,

  // Projects
  Project,
} from './api';

// ---------------------------------------------------------------------------
// WebSocket protocol types
// ---------------------------------------------------------------------------

export type {
  // Topics
  EventTopic,
  WildcardTopic,
  SubscriptionTopic,

  // Connection state
  WsConnectionStatus,

  // Client -> Server
  WsSubscribeMessage,
  WsUnsubscribeMessage,
  WsPingMessage,
  WsOutgoingMessage,

  // Server -> Client
  WsConnectedMessage,
  WsSubscribedMessage,
  WsUnsubscribedMessage,
  WsEventMessage,
  WsReplayMessage,
  WsHeartbeatMessage,
  WsPongMessage,
  WsErrorMessage,
  WsIncomingMessage,

  // Event payloads
  WsFileChangeEventPayload,
  WsStageLogEventPayload,
  WsHeartbeatEventPayload,
  WsConnectionEventPayload,
  WsScheduleStatusEventPayload,
  WsEventPayload,

  // Close codes
  WsCloseCode,
} from './ws';

export { ALL_EVENT_TOPICS, WS_CLOSE_CODES } from './ws';

// ---------------------------------------------------------------------------
// Store slice types
// ---------------------------------------------------------------------------

export type {
  // Slices
  ConnectionSlice,
  PipelineSlice,
  PipelineProgress,
  StepStatus,
  StageLogSlice,
  SatelliteSlice,
  LegacySlice,
  LegacySliceState,
  LegacyFSMState,
  LegacyProject,
  DecisionsSlice,
  EvidenceSlice,
  AuditSlice,
  IdeasSlice,
  QueueDetailSlice,
  KnowledgeSlice,
  ProjectsSlice,
  ReplaySlice,
  ReplayState,

  // Combined store
  DashboardStore,
} from './store';
