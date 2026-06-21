/**
 * WebSocket server with topic-AND-project subscription management.
 *
 * Adapted from the v1 salvage (`aid-gui/server/ws/websocket.ts`) for Phase 3:
 *   - Subscriptions are keyed on BOTH topic and projectId.
 *   - Every server→client frame carries a top-level `ts` (ISO 8601). The v1
 *     `timestamp` field is gone — see `events.ts` §7.3 contract note.
 *   - Replay-on-subscribe reads from a merged activity ring buffer supplier
 *     (`setActivityBufferSupplier`) rather than the v1 hardcoded stage-log
 *     supplier.
 *
 * Module: server/ws/websocket.ts
 * Contract: @aid/contract (InternalEvent, FileChangeEvent, ActivityEvent,
 *           EventTopic, ALL_EVENT_TOPICS)
 */

import { type Server as HttpServer } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type {
  ActivityEvent,
  EventTopic,
  InternalEvent,
} from '@aid/contract';
import { ALL_EVENT_TOPICS } from '@aid/contract';
import { filterActivity } from '../activity-filter.js';

// ---------------------------------------------------------------------------
// Subscription request shape (client → server)
// ---------------------------------------------------------------------------

/**
 * Filter accepted by `subscribe` / `unsubscribe`.
 *
 * Empty-set semantics (matches the v1 wildcard intent, made explicit here):
 *   - `topics: []`   → subscribe to ALL topics ("topic wildcard").
 *   - `projects: []` → match events from ALL projects ("project wildcard").
 * A subscription with both empty is therefore "everything", equivalent to the
 * v1 `*` topic wildcard with no project scoping.
 */
export interface SubscriptionFilter {
  topics: string[];
  projects: string[];
  /** Optional cap on the replay frame, applied SERVER-side (AC#28 parity). */
  limit?: number;
}

// ---------------------------------------------------------------------------
// Per-client state
// ---------------------------------------------------------------------------

interface ClientState {
  /** Topics this client subscribed to. EMPTY = all topics. */
  topics: Set<string>;
  /** Project ids this client scoped to. EMPTY = all projects. */
  projects: Set<string>;
  /** Timestamp (ms) of the last message received from this client. */
  lastActivity: number;
  /** Liveness flag toggled by the ws pong handler (heartbeat). */
  isAlive: boolean;
}

// ---------------------------------------------------------------------------
// Server-local frame types — every frame has a top-level `ts`.
// These are NOT part of @aid/contract (server↔client wire shapes only).
// ---------------------------------------------------------------------------

interface ConnectedFrame {
  type: 'connected';
  availableTopics: EventTopic[];
  ts: string;
}

interface EventFrame {
  type: 'event';
  topic: EventTopic;
  data: InternalEvent;
  ts: string;
}

interface ReplayFrame {
  type: 'replay';
  data: ActivityEvent[];
  ts: string;
}

interface HeartbeatFrame {
  type: 'heartbeat';
  clientCount: number;
  ts: string;
}

interface SubscribedFrame {
  type: 'subscribed';
  topics: string[];
  projects: string[];
  ts: string;
}

interface UnsubscribedFrame {
  type: 'unsubscribed';
  topics: string[];
  projects: string[];
  ts: string;
}

interface ErrorFrame {
  type: 'error';
  message: string;
  ts: string;
}

interface PongFrame {
  type: 'pong';
  ts: string;
}

type ServerFrame =
  | ConnectedFrame
  | EventFrame
  | ReplayFrame
  | HeartbeatFrame
  | SubscribedFrame
  | UnsubscribedFrame
  | ErrorFrame
  | PongFrame;

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Heartbeat interval in milliseconds (30 seconds). */
const HEARTBEAT_INTERVAL_MS = 30_000;

/** Idle timeout in milliseconds (90 seconds). */
const IDLE_TIMEOUT_MS = 90_000;

/** Granularity of the idle-check sweep. */
const IDLE_CHECK_INTERVAL_MS = 15_000;

/** WebSocket close code for idle timeout. */
const CLOSE_CODE_IDLE_TIMEOUT = 4001;

/** Options for tuning timers (tests may shorten them). */
export interface AidWebSocketOptions {
  heartbeatIntervalMs?: number;
  idleTimeoutMs?: number;
  idleCheckIntervalMs?: number;
}

// ---------------------------------------------------------------------------
// AidWebSocket
// ---------------------------------------------------------------------------

/**
 * WebSocket server managing topic-AND-project subscriptions and event
 * broadcasting.
 *
 * Usage:
 * ```typescript
 * const server = http.createServer(app);
 * const ws = new AidWebSocket(server);
 * watcher.on('event', (e) => ws.broadcast(e));
 * ws.setActivityBufferSupplier(() => activityRing.snapshot());
 * server.listen(0, () => ws.start());
 * ```
 */
export class AidWebSocket {
  private readonly wss: WebSocketServer;
  private readonly clients: Map<WebSocket, ClientState> = new Map();
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private idleCheckTimer: ReturnType<typeof setInterval> | null = null;
  private activityBufferSupplier: (() => ActivityEvent[]) | null = null;
  private stopped = false;

  private readonly heartbeatIntervalMs: number;
  private readonly idleTimeoutMs: number;
  private readonly idleCheckIntervalMs: number;

  /**
   * @param server - HTTP server to attach to.
   * @param path - WebSocket endpoint path. Default: "/ws".
   * @param options - Optional timer overrides (tests shorten idle/heartbeat).
   */
  constructor(
    server: HttpServer,
    path = '/ws',
    options: AidWebSocketOptions = {},
  ) {
    this.heartbeatIntervalMs =
      options.heartbeatIntervalMs ?? HEARTBEAT_INTERVAL_MS;
    this.idleTimeoutMs = options.idleTimeoutMs ?? IDLE_TIMEOUT_MS;
    this.idleCheckIntervalMs =
      options.idleCheckIntervalMs ?? IDLE_CHECK_INTERVAL_MS;

    this.wss = new WebSocketServer({ server, path });

    this.wss.on('connection', (socket: WebSocket) => {
      this.handleConnection(socket);
    });

    this.wss.on('error', (error: Error) => {
      console.error('[AidWebSocket] Server error:', error.message);
    });
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /** Start heartbeat and idle-check timers (call after server.listen). */
  start(): void {
    this.stopped = false;

    this.heartbeatTimer = setInterval(() => {
      this.sendHeartbeat();
    }, this.heartbeatIntervalMs);

    this.idleCheckTimer = setInterval(() => {
      this.checkIdleClients();
    }, this.idleCheckIntervalMs);
  }

  /** Stop the server: close all clients, clear timers, shut down the wss. */
  stop(): void {
    this.stopped = true;

    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    if (this.idleCheckTimer) {
      clearInterval(this.idleCheckTimer);
      this.idleCheckTimer = null;
    }

    for (const [socket] of this.clients) {
      try {
        socket.close(1001, 'Server shutting down');
      } catch {
        // Socket may already be closed; ignore.
      }
    }
    this.clients.clear();
    this.wss.close();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /**
   * Set the supplier providing the merged activity ring buffer for replay.
   *
   * On a new subscription the (filtered) snapshot is sent as a `type:'replay'`
   * frame. The supplier should return ActivityEvents ordered oldest → newest.
   */
  setActivityBufferSupplier(supplier: () => ActivityEvent[]): void {
    this.activityBufferSupplier = supplier;
  }

  /**
   * Broadcast an internal event using the topic-AND-project filter.
   *
   * A client receives the event iff:
   *   - the client is subscribed to the event's topic (or has an empty topic
   *     set = all topics), AND
   *   - the client's project set is empty (= all projects) OR includes the
   *     event's projectId.
   */
  broadcast(event: InternalEvent): void {
    if (this.stopped) return;

    const frame: EventFrame = {
      type: 'event',
      topic: event.topic,
      data: event,
      ts: new Date().toISOString(),
    };
    const message = JSON.stringify(frame);

    for (const [socket, state] of this.clients) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      if (this.matches(state, event.topic, event.projectId)) {
        this.safeSend(socket, message);
      }
    }
  }

  /** Number of currently connected clients. */
  get clientCount(): number {
    return this.clients.size;
  }

  // -------------------------------------------------------------------------
  // Connection handling
  // -------------------------------------------------------------------------

  private handleConnection(socket: WebSocket): void {
    const state: ClientState = {
      topics: new Set(),
      projects: new Set(),
      lastActivity: Date.now(),
      isAlive: true,
    };
    this.clients.set(socket, state);

    this.send(socket, {
      type: 'connected',
      availableTopics: [...ALL_EVENT_TOPICS],
      ts: new Date().toISOString(),
    });

    socket.on('message', (data: Buffer | ArrayBuffer | Buffer[]) => {
      this.handleMessage(socket, state, data);
    });

    socket.on('close', () => {
      this.clients.delete(socket);
    });

    socket.on('error', (error: Error) => {
      console.error('[AidWebSocket] Client socket error:', error.message);
      this.clients.delete(socket);
    });

    socket.on('pong', () => {
      state.isAlive = true;
    });
  }

  private handleMessage(
    socket: WebSocket,
    state: ClientState,
    raw: Buffer | ArrayBuffer | Buffer[],
  ): void {
    state.lastActivity = Date.now();
    state.isAlive = true;

    let text: string;
    if (Buffer.isBuffer(raw)) {
      text = raw.toString('utf-8');
    } else if (raw instanceof ArrayBuffer) {
      text = Buffer.from(raw).toString('utf-8');
    } else {
      text = Buffer.concat(raw).toString('utf-8');
    }

    let msg: unknown;
    try {
      msg = JSON.parse(text);
    } catch {
      this.sendError(socket, 'Invalid JSON');
      return;
    }

    if (typeof msg !== 'object' || msg === null || !('type' in msg)) {
      this.sendError(socket, 'Message must be an object with a "type" field');
      return;
    }

    const typed = msg as Record<string, unknown>;

    switch (typed.type) {
      case 'subscribe':
        this.subscribe(socket, state, typed);
        break;
      case 'unsubscribe':
        this.unsubscribe(socket, state, typed);
        break;
      case 'ping':
        this.send(socket, { type: 'pong', ts: new Date().toISOString() });
        break;
      default:
        this.sendError(socket, `Unknown message type: ${String(typed.type)}`);
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Subscribe / Unsubscribe
  // -------------------------------------------------------------------------

  /**
   * Apply a subscribe message: add topics + projects to the client state and,
   * if an activity supplier is set, replay the (filtered) buffer.
   */
  private subscribe(
    socket: WebSocket,
    state: ClientState,
    msg: Record<string, unknown>,
  ): void {
    const filter = this.parseFilter(msg);
    if (filter === null) {
      this.sendError(
        socket,
        'Subscribe requires "topics" (string[]) and/or "projects" (string[])',
      );
      return;
    }

    for (const topic of filter.topics) {
      if (!this.isValidTopic(topic)) {
        this.sendError(socket, `Unknown topic: ${topic}`);
        continue;
      }
      state.topics.add(topic);
    }
    for (const project of filter.projects) {
      state.projects.add(project);
    }

    this.send(socket, {
      type: 'subscribed',
      topics: [...state.topics],
      projects: [...state.projects],
      ts: new Date().toISOString(),
    });

    this.replay(socket, filter);
  }

  /**
   * Apply an unsubscribe message. Empty topics+projects clears the whole
   * subscription (full reset). Otherwise removes the named entries.
   */
  private unsubscribe(
    socket: WebSocket,
    state: ClientState,
    msg: Record<string, unknown>,
  ): void {
    const filter = this.parseFilter(msg);
    if (filter === null) {
      this.sendError(
        socket,
        'Unsubscribe requires "topics" (string[]) and/or "projects" (string[])',
      );
      return;
    }

    if (filter.topics.length === 0 && filter.projects.length === 0) {
      state.topics.clear();
      state.projects.clear();
    } else {
      for (const topic of filter.topics) state.topics.delete(topic);
      for (const project of filter.projects) state.projects.delete(project);
    }

    this.send(socket, {
      type: 'unsubscribed',
      topics: [...state.topics],
      projects: [...state.projects],
      ts: new Date().toISOString(),
    });
  }

  /**
   * Send a `type:'replay'` frame with the activity buffer filtered by the new
   * subscription. Skipped when the buffer is empty or no supplier is set.
   *
   * Filtering goes through the SHARED {@link filterActivity} helper — the exact
   * same code path the REST `GET /api/activity` bootstrap uses — so the polling
   * fallback is payload-shape-equal to this replay frame (§7.3 / AC #9c). The
   * supplier yields oldest→newest, so empty topics/projects = wildcard and the
   * topic match (raw.topic or event name) is applied identically in both
   * channels. When the subscription carries a `limit`, it is applied SERVER-side
   * here (order:'asc' keeps the newest N from the oldest→newest buffer tail), so
   * a `limit` genuinely caps the WS replay frame — not a client-side trim
   * (AC#28: "limit caps BOTH channels").
   */
  private replay(socket: WebSocket, filter: SubscriptionFilter): void {
    if (!this.activityBufferSupplier) return;

    const buffer = this.activityBufferSupplier();
    const filtered = filterActivity(buffer, {
      projects: filter.projects,
      topics: filter.topics,
      limit: filter.limit,
      order: 'asc',
    });

    if (filtered.length > 0) {
      this.send(socket, {
        type: 'replay',
        data: filtered,
        ts: new Date().toISOString(),
      });
    }
  }

  /**
   * Parse `{ topics?, projects? }` from a client message. Accepts a single
   * `topic: string` / `project: string` as convenience. Returns null only if
   * NEITHER field is present in a usable form.
   */
  private parseFilter(msg: Record<string, unknown>): SubscriptionFilter | null {
    let topics: string[] | null = null;
    let projects: string[] | null = null;

    if (Array.isArray(msg.topics)) {
      topics = msg.topics.filter((t): t is string => typeof t === 'string');
    } else if (typeof msg.topic === 'string') {
      topics = [msg.topic];
    }

    if (Array.isArray(msg.projects)) {
      projects = msg.projects.filter(
        (p): p is string => typeof p === 'string',
      );
    } else if (typeof msg.project === 'string') {
      projects = [msg.project];
    }

    if (topics === null && projects === null) return null;

    const limit =
      typeof msg.limit === 'number' && Number.isFinite(msg.limit)
        ? msg.limit
        : undefined;

    return { topics: topics ?? [], projects: projects ?? [], limit };
  }

  // -------------------------------------------------------------------------
  // Heartbeat and idle checking
  // -------------------------------------------------------------------------

  private sendHeartbeat(): void {
    if (this.stopped) return;

    const frame: HeartbeatFrame = {
      type: 'heartbeat',
      clientCount: this.clients.size,
      ts: new Date().toISOString(),
    };
    const message = JSON.stringify(frame);

    for (const [socket] of this.clients) {
      if (socket.readyState === WebSocket.OPEN) {
        // ws-level ping drives the pong→isAlive liveness check.
        try {
          socket.ping();
        } catch {
          // Ignore ping failures; idle sweep will reap dead sockets.
        }
        this.safeSend(socket, message);
      }
    }
  }

  private checkIdleClients(): void {
    if (this.stopped) return;

    const now = Date.now();
    for (const [socket, state] of this.clients) {
      const idleMs = now - state.lastActivity;
      if (idleMs >= this.idleTimeoutMs) {
        try {
          socket.close(CLOSE_CODE_IDLE_TIMEOUT, 'Idle timeout');
        } catch {
          // Socket may already be closed; ignore.
        }
        this.clients.delete(socket);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Matching
  // -------------------------------------------------------------------------

  /**
   * topic-AND-project delivery filter (see `broadcast`). Empty topic set =
   * all topics; empty project set = all projects.
   */
  private matches(
    state: ClientState,
    topic: EventTopic,
    projectId: string,
  ): boolean {
    const topicOk = state.topics.size === 0 || state.topics.has(topic);
    const projectOk =
      state.projects.size === 0 || state.projects.has(projectId);
    return topicOk && projectOk;
  }

  private isValidTopic(topic: string): boolean {
    return ALL_EVENT_TOPICS.includes(topic as EventTopic);
  }

  // -------------------------------------------------------------------------
  // Sending
  // -------------------------------------------------------------------------

  private send(socket: WebSocket, frame: ServerFrame): void {
    this.safeSend(socket, JSON.stringify(frame));
  }

  private safeSend(socket: WebSocket, message: string): void {
    try {
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(message);
      }
    } catch (error: unknown) {
      const msg = error instanceof Error ? error.message : String(error);
      console.error('[AidWebSocket] Send error:', msg);
    }
  }

  private sendError(socket: WebSocket, message: string): void {
    this.send(socket, {
      type: 'error',
      message,
      ts: new Date().toISOString(),
    });
  }
}
