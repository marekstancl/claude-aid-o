/**
 * WebSocket message protocol types for the AID Dashboard frontend.
 *
 * Defines the full client-server WebSocket contract based on the server
 * implementation in `server/ws/websocket.ts`. The protocol is JSON-based
 * with discriminated unions keyed on the `type` field.
 *
 * Message flow:
 *   1. Client connects -> Server sends `WsConnectedMessage`
 *   2. Client sends `WsSubscribeMessage` for topics of interest
 *   3. Server confirms with `WsSubscribedMessage`
 *   4. Server pushes `WsEventMessage` for matching events
 *   5. Server sends `WsHeartbeatMessage` every 30s to all clients
 *   6. Client sends `WsPingMessage` -> Server replies `WsPongMessage`
 *   7. Server closes idle connections after 90s of no client messages
 *
 * If the client subscribes to `pipeline.stage_log`, the server immediately
 * sends a `WsReplayMessage` with buffered entries.
 */

// ---------------------------------------------------------------------------
// Event topics
// ---------------------------------------------------------------------------

/**
 * Semantic topics that the WebSocket server supports.
 *
 * Subscribing to a topic means the client will receive all `event` messages
 * classified under that topic. Topics are flat with one level of dot-separated
 * nesting. Subscribing to `pipeline` does NOT include `pipeline.stage_log` --
 * they are independent subscriptions.
 */
export type EventTopic =
  | 'pipeline'
  | 'pipeline.stage_log'
  | 'evidence'
  | 'decisions'
  | 'config'
  | 'queue'
  | 'audit'
  | 'usage'
  | 'queue.schedule'
  | 'ideas'
  | 'epics'
  | 'companion.stream'
  | 'companion.session'
  | 'system';

/**
 * Runtime array of all valid EventTopic values.
 *
 * Useful for subscribing to all topics or for validation.
 */
export const ALL_EVENT_TOPICS: readonly EventTopic[] = [
  'pipeline',
  'pipeline.stage_log',
  'evidence',
  'decisions',
  'config',
  'queue',
  'audit',
  'usage',
  'queue.schedule',
  'ideas',
  'epics',
  'companion.stream',
  'companion.session',
  'system',
] as const;

/**
 * Wildcard subscription token. When sent in a subscribe message, the client
 * receives events for all topics.
 */
export type WildcardTopic = '*';

/**
 * A topic specifier that can be used in subscribe/unsubscribe messages.
 * Includes both concrete topics and the wildcard.
 */
export type SubscriptionTopic = EventTopic | WildcardTopic;

// ---------------------------------------------------------------------------
// Connection state
// ---------------------------------------------------------------------------

/**
 * WebSocket connection lifecycle states.
 *
 * Managed by the frontend connection manager:
 * - `connecting`    -- Initial connection attempt in progress
 * - `connected`     -- Connection open, server confirmed with `connected` message
 * - `reconnecting`  -- Connection lost, automatic reconnection in progress
 * - `disconnected`  -- Connection closed, no reconnection scheduled
 */
export type WsConnectionStatus =
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'disconnected';

// ---------------------------------------------------------------------------
// Client -> Server messages (outgoing from frontend)
// ---------------------------------------------------------------------------

/**
 * Subscribe to one or more event topics.
 *
 * The server accepts both `topics` (array) and `topic` (single string)
 * formats. Prefer `topics` for consistency.
 *
 * @example
 * ```json
 * { "type": "subscribe", "topics": ["pipeline", "pipeline.stage_log"] }
 * ```
 */
export interface WsSubscribeMessage {
  /** Message discriminant. */
  type: 'subscribe';
  /** Topics to subscribe to. Use `["*"]` for wildcard. */
  topics: SubscriptionTopic[];
}

/**
 * Unsubscribe from one or more event topics.
 *
 * @example
 * ```json
 * { "type": "unsubscribe", "topics": ["queue"] }
 * ```
 */
export interface WsUnsubscribeMessage {
  /** Message discriminant. */
  type: 'unsubscribe';
  /** Topics to unsubscribe from. Use `["*"]` to clear all subscriptions. */
  topics: SubscriptionTopic[];
}

/**
 * Application-level ping. The server replies with a `pong` message.
 *
 * Clients should send a ping at least once every 90 seconds to prevent
 * the server's idle timeout from closing the connection.
 *
 * @example
 * ```json
 * { "type": "ping" }
 * ```
 */
export interface WsPingMessage {
  /** Message discriminant. */
  type: 'ping';
}

/**
 * Discriminated union of all messages the client can send to the server.
 */
export type WsOutgoingMessage =
  | WsSubscribeMessage
  | WsUnsubscribeMessage
  | WsPingMessage;

// ---------------------------------------------------------------------------
// Server -> Client messages (incoming to frontend)
// ---------------------------------------------------------------------------

/**
 * Sent immediately after a successful WebSocket connection.
 *
 * Provides the list of topics available for subscription.
 *
 * @example
 * ```json
 * {
 *   "type": "connected",
 *   "topic": "system",
 *   "availableTopics": ["pipeline", "pipeline.stage_log", "queue", ...],
 *   "timestamp": "2026-02-25T14:00:00.000Z"
 * }
 * ```
 */
export interface WsConnectedMessage {
  /** Message discriminant. */
  type: 'connected';
  /** Always "system" for connection events. */
  topic: 'system';
  /** Topics the client can subscribe to. */
  availableTopics: EventTopic[];
  /** ISO 8601 timestamp of the connection acknowledgement. */
  timestamp: string;
}

/**
 * Confirmation that the server accepted a subscribe request.
 *
 * @example
 * ```json
 * {
 *   "type": "subscribed",
 *   "topics": ["pipeline", "pipeline.stage_log"],
 *   "timestamp": "2026-02-25T14:00:01.000Z"
 * }
 * ```
 */
export interface WsSubscribedMessage {
  /** Message discriminant. */
  type: 'subscribed';
  /** Topics that were successfully subscribed. */
  topics: EventTopic[];
  /** ISO 8601 timestamp. */
  timestamp: string;
}

/**
 * Confirmation that the server accepted an unsubscribe request.
 *
 * @example
 * ```json
 * {
 *   "type": "unsubscribed",
 *   "topics": ["queue"],
 *   "timestamp": "2026-02-25T14:00:02.000Z"
 * }
 * ```
 */
export interface WsUnsubscribedMessage {
  /** Message discriminant. */
  type: 'unsubscribed';
  /** Topics that were unsubscribed. May include "*" for wildcard unsubscribe. */
  topics: string[];
  /** ISO 8601 timestamp. */
  timestamp: string;
}

/**
 * A real-time event pushed to subscribed clients.
 *
 * This is the primary data delivery message. The `data` field contains the
 * full event payload (FileChangeEvent, StageLogEvent, etc. from the server's
 * internal event system).
 *
 * @example
 * ```json
 * {
 *   "type": "event",
 *   "topic": "pipeline",
 *   "data": { "type": "file_change", "topic": "pipeline", "filePath": "...", ... },
 *   "timestamp": "2026-02-25T14:01:00.000Z"
 * }
 * ```
 */
export interface WsEventMessage {
  /** Message discriminant. */
  type: 'event';
  /** The topic this event belongs to. */
  topic: EventTopic;
  /** The event payload. Shape varies by topic. */
  data: WsEventPayload;
  /** ISO 8601 timestamp when the server broadcast the event. */
  timestamp: string;
}

/**
 * Buffered stage log entries replayed after subscribing to `pipeline.stage_log`.
 *
 * Sent once immediately after the `subscribed` confirmation if the server
 * has buffered entries. The `data` array contains events ordered oldest-first.
 *
 * @example
 * ```json
 * {
 *   "type": "replay",
 *   "topic": "pipeline.stage_log",
 *   "data": [{ "timestamp": "...", "state": "...", "step": null, "action": "...", "details": "...", "result": "pass" }, ...],
 *   "timestamp": "2026-02-25T14:00:01.100Z"
 * }
 * ```
 */
export interface WsReplayMessage {
  /** Message discriminant. */
  type: 'replay';
  /** Always "pipeline.stage_log" for replay messages. */
  topic: 'pipeline.stage_log';
  /** Raw stage log entries, ordered oldest-first (no `.entry` wrapper). */
  data: WsReplayStageLogEntry[];
  /** ISO 8601 timestamp when the replay was sent. */
  timestamp: string;
}

/**
 * A raw stage log entry as sent in replay messages.
 *
 * Unlike `WsStageLogEventPayload` (used in live events), replay entries are
 * sent without the `type`/`topic`/`entry` wrapper — they are the inner entry
 * directly.
 */
export interface WsReplayStageLogEntry {
  /** ISO 8601 timestamp of the event. */
  timestamp: string;
  /** FSM state at the time of the event. */
  state: string;
  /** Step ID this event relates to, or null. */
  step: string | null;
  /** Action identifier. */
  action: string;
  /** Human-readable description. */
  details: string;
  /** Outcome of the event. */
  result: 'pass' | 'fail' | 'pending' | 'skip' | 'success';
}

/**
 * Periodic heartbeat sent to all connected clients every 30 seconds.
 *
 * Sent regardless of subscription state (system topic is implicit).
 * Clients can use `timestamp` to detect stale connections.
 *
 * @example
 * ```json
 * {
 *   "type": "heartbeat",
 *   "topic": "system",
 *   "timestamp": "2026-02-25T14:00:30.000Z",
 *   "clientCount": 3
 * }
 * ```
 */
export interface WsHeartbeatMessage {
  /** Message discriminant. */
  type: 'heartbeat';
  /** Always "system" for heartbeats. */
  topic: 'system';
  /** ISO 8601 timestamp of the heartbeat. */
  timestamp: string;
  /** Number of clients currently connected to the server. */
  clientCount: number;
}

/**
 * Response to a client `ping` message.
 *
 * @example
 * ```json
 * { "type": "pong", "timestamp": "2026-02-25T14:00:05.000Z" }
 * ```
 */
export interface WsPongMessage {
  /** Message discriminant. */
  type: 'pong';
  /** ISO 8601 timestamp. */
  timestamp: string;
}

/**
 * Error message sent when the server cannot process a client message.
 *
 * Does not close the connection. The client should log or display the error
 * and continue operating.
 *
 * @example
 * ```json
 * {
 *   "type": "error",
 *   "message": "Unknown topic: invalid_topic",
 *   "timestamp": "2026-02-25T14:00:06.000Z"
 * }
 * ```
 */
export interface WsErrorMessage {
  /** Message discriminant. */
  type: 'error';
  /** Human-readable error description. */
  message: string;
  /** ISO 8601 timestamp. */
  timestamp: string;
}

/**
 * Discriminated union of all messages the client can receive from the server.
 *
 * Switch on the `type` field to narrow to a specific message shape.
 */
export type WsIncomingMessage =
  | WsConnectedMessage
  | WsSubscribedMessage
  | WsUnsubscribedMessage
  | WsEventMessage
  | WsReplayMessage
  | WsHeartbeatMessage
  | WsPongMessage
  | WsErrorMessage;

// ---------------------------------------------------------------------------
// Event payload types
// ---------------------------------------------------------------------------

/**
 * File change event payload within a `WsEventMessage`.
 *
 * Pushed when a file in the `.aid-o/` directory is created, modified, or deleted.
 */
export interface WsFileChangeEventPayload {
  /** Discriminant for the event union. */
  type: 'file_change';
  /** Semantic topic this event belongs to. */
  topic: EventTopic;
  /** Absolute path of the changed file on the server. */
  filePath: string;
  /** Kind of filesystem change. */
  changeType: 'add' | 'change' | 'unlink';
  /** Parsed data from the file, or null if parsing failed or file was deleted. */
  parsedData: unknown | null;
  /** ISO 8601 timestamp when the event was created. */
  timestamp: string;
}

/**
 * Stage log event payload within a `WsEventMessage` or `WsReplayMessage`.
 *
 * Pushed when a new line is appended to a `stage_log.jsonl` file.
 */
export interface WsStageLogEventPayload {
  /** Discriminant for the event union. */
  type: 'stage_log';
  /** Always "pipeline.stage_log". */
  topic: 'pipeline.stage_log';
  /** The parsed stage log entry. */
  entry: {
    /** ISO 8601 timestamp of the event. */
    timestamp: string;
    /** FSM state at the time of the event. */
    state: string;
    /** Step ID this event relates to, or null. */
    step: string | null;
    /** Action identifier. */
    action: string;
    /** Human-readable description. */
    details: string;
    /** Outcome of the event. */
    result: 'pass' | 'fail' | 'pending' | 'skip' | 'success';
  };
  /** EPIC ID extracted from the file path. */
  epicId: string;
  /** Run ID extracted from the file path. */
  runId: string;
  /** ISO 8601 timestamp when the event was created. */
  timestamp: string;
}

/**
 * Heartbeat event payload (identical to WsHeartbeatMessage body).
 */
export interface WsHeartbeatEventPayload {
  /** Discriminant for the event union. */
  type: 'heartbeat';
  /** Always "system". */
  topic: 'system';
  /** ISO 8601 timestamp. */
  timestamp: string;
  /** Number of clients currently connected. */
  clientCount: number;
}

/**
 * Connection event payload (identical to WsConnectedMessage body).
 */
export interface WsConnectionEventPayload {
  /** Discriminant for the event union. */
  type: 'connected';
  /** Always "system". */
  topic: 'system';
  /** ISO 8601 timestamp. */
  timestamp: string;
  /** Available topics. */
  availableTopics: EventTopic[];
}

/**
 * Schedule status event payload, received on topic `queue.schedule`.
 */
export interface WsScheduleStatusEventPayload {
  /** Discriminant for the event union. */
  type: 'schedule_status';
  /** Always "queue.schedule". */
  topic: 'queue.schedule';
  /** Current scheduler state. */
  state: 'idle' | 'cooldown' | 'waiting' | 'ready' | 'paused';
  /** Seconds remaining in cooldown/wait, or null. */
  remainingSeconds: number | null;
  /** Current schedule configuration. */
  config: {
    enabled: boolean;
    cooldownSeconds: number;
    maxConcurrent: number;
    delayedStartAt: string | null;
    autoPauseAtCcLimit: boolean;
    ccLimitThreshold: number;
    lastRunCompletedAt: string | null;
  };
  /** ISO 8601 timestamp. */
  timestamp: string;
}

/**
 * Discriminated union of all event payloads that can appear in `WsEventMessage.data`.
 *
 * Switch on the `type` field to narrow to a specific payload shape.
 */
export type WsEventPayload =
  | WsFileChangeEventPayload
  | WsStageLogEventPayload
  | WsHeartbeatEventPayload
  | WsConnectionEventPayload
  | WsScheduleStatusEventPayload;

// ---------------------------------------------------------------------------
// WebSocket close codes
// ---------------------------------------------------------------------------

/**
 * Custom WebSocket close codes used by the server.
 */
export const WS_CLOSE_CODES = {
  /** Normal closure by the server (e.g., server shutting down). */
  NORMAL: 1001,
  /** Client was idle for too long (90 seconds). */
  IDLE_TIMEOUT: 4001,
} as const;

/**
 * Type for the custom close code values.
 */
export type WsCloseCode = (typeof WS_CLOSE_CODES)[keyof typeof WS_CLOSE_CODES];
