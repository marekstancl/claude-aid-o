/**
 * WebSocket server with topic-based subscription management.
 *
 * Accepts connections on the same HTTP server as Express, manages per-client
 * topic subscriptions, broadcasts InternalEvents to subscribed clients, sends
 * heartbeat every 30s, and enforces idle timeout at 90s.
 *
 * Protocol reference: ADR-002, Section "WebSocket Protocol"
 *
 * Module: server/ws/websocket.ts
 * Depends on: server/types.ts
 */

import { type Server as HttpServer } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type {
  EventTopic,
  InternalEvent,
  StageLogEvent,
} from '../types.ts';
import { ALL_EVENT_TOPICS } from '../types.ts';

// ---------------------------------------------------------------------------
// Client metadata tracked per WebSocket connection
// ---------------------------------------------------------------------------

interface ClientState {
  /** Set of topics this client is subscribed to. */
  subscriptions: Set<EventTopic | '*'>;
  /** Timestamp (ms) of the last message received from this client. */
  lastActivity: number;
  /** Whether this client is still alive (for ws ping/pong). */
  isAlive: boolean;
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Heartbeat interval in milliseconds (30 seconds). */
const HEARTBEAT_INTERVAL_MS = 30_000;

/** Idle timeout in milliseconds (90 seconds). */
const IDLE_TIMEOUT_MS = 90_000;

/** WebSocket close code for idle timeout. */
const CLOSE_CODE_IDLE_TIMEOUT = 4001;

// ---------------------------------------------------------------------------
// AidWebSocket class
// ---------------------------------------------------------------------------

/**
 * WebSocket server managing topic-based subscriptions and event broadcasting.
 *
 * Usage:
 * ```typescript
 * import http from 'node:http';
 * import express from 'express';
 *
 * const app = express();
 * const server = http.createServer(app);
 * const ws = new AidWebSocket(server);
 *
 * // Wire events from watchers
 * fileWatcher.on('event', (e) => ws.broadcast(e));
 * stageLogStream.on('event', (e) => ws.broadcast(e));
 *
 * // Provide a stage log buffer supplier for replay
 * ws.setStageLogBufferSupplier(() => stageLogStream.getBuffer());
 *
 * ws.start();
 * // ... later
 * ws.stop();
 * ```
 */
export class AidWebSocket {
  private readonly wss: WebSocketServer;
  private readonly clients: Map<WebSocket, ClientState> = new Map();
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private idleCheckTimer: ReturnType<typeof setInterval> | null = null;
  private stageLogBufferSupplier: (() => StageLogEvent[]) | null = null;
  private stopped: boolean = false;

  /**
   * Create a new AidWebSocket attached to the given HTTP server.
   *
   * The WebSocket server is created immediately but does not accept
   * connections until `start()` is called (heartbeat/idle timers).
   * However, the underlying wss will begin accepting connections as
   * soon as the HTTP server starts listening.
   *
   * @param server - The HTTP server to attach to.
   * @param path - WebSocket endpoint path. Default: "/ws".
   */
  constructor(server: HttpServer, path: string = '/ws') {
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

  /**
   * Start heartbeat and idle-check timers.
   * Call this after the HTTP server begins listening.
   */
  start(): void {
    this.stopped = false;

    // Heartbeat: send to all connected clients every 30s.
    this.heartbeatTimer = setInterval(() => {
      this.sendHeartbeat();
    }, HEARTBEAT_INTERVAL_MS);

    // Idle check: close connections that have not sent any message for 90s.
    // Check every 15s to keep granularity reasonable.
    this.idleCheckTimer = setInterval(() => {
      this.checkIdleClients();
    }, 15_000);
  }

  /**
   * Stop the WebSocket server and clean up all resources.
   *
   * Closes all client connections, clears timers, and shuts down the
   * underlying WebSocketServer.
   */
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

    // Close all client connections gracefully.
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
   * Set the supplier function that provides the stage log buffer for replay.
   *
   * This is called when a client subscribes to `pipeline.stage_log` to send
   * the buffered entries. The supplier should return an array of StageLogEvent
   * ordered from oldest to newest.
   */
  setStageLogBufferSupplier(supplier: () => StageLogEvent[]): void {
    this.stageLogBufferSupplier = supplier;
  }

  /**
   * Broadcast an internal event to all clients subscribed to the event's topic.
   *
   * @param event - The InternalEvent to broadcast.
   */
  broadcast(event: InternalEvent): void {
    if (this.stopped) return;

    const topic = event.topic;
    const message = JSON.stringify({
      type: 'event',
      topic,
      data: event,
      timestamp: new Date().toISOString(),
    });

    for (const [socket, state] of this.clients) {
      if (socket.readyState !== WebSocket.OPEN) continue;

      if (this.isSubscribed(state, topic)) {
        this.safeSend(socket, message);
      }
    }
  }

  /**
   * Return the number of currently connected clients.
   */
  get clientCount(): number {
    return this.clients.size;
  }

  // -------------------------------------------------------------------------
  // Connection handling
  // -------------------------------------------------------------------------

  /**
   * Handle a new WebSocket connection.
   */
  private handleConnection(socket: WebSocket): void {
    const state: ClientState = {
      subscriptions: new Set(),
      lastActivity: Date.now(),
      isAlive: true,
    };

    this.clients.set(socket, state);

    // Send connection acknowledgement.
    this.safeSend(socket, JSON.stringify({
      type: 'connected',
      topic: 'system',
      availableTopics: [...ALL_EVENT_TOPICS],
      timestamp: new Date().toISOString(),
    }));

    // Wire up message handling.
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

    // ws-level pong (for idle detection fallback).
    socket.on('pong', () => {
      state.isAlive = true;
    });
  }

  /**
   * Handle an incoming message from a client.
   */
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
      // Buffer[] — concatenate
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
        this.handleSubscribe(socket, state, typed);
        break;

      case 'unsubscribe':
        this.handleUnsubscribe(socket, state, typed);
        break;

      case 'ping':
        this.safeSend(socket, JSON.stringify({
          type: 'pong',
          timestamp: new Date().toISOString(),
        }));
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
   * Handle a subscribe message.
   *
   * Supports both the ADR-specified `topics: string[]` format and a
   * single-topic `topic: string` format for convenience.
   */
  private handleSubscribe(
    socket: WebSocket,
    state: ClientState,
    msg: Record<string, unknown>,
  ): void {
    const topics = this.extractTopics(msg);
    if (topics === null) {
      this.sendError(socket, 'Subscribe requires "topics" (array) or "topic" (string)');
      return;
    }

    const subscribedTopics: EventTopic[] = [];

    for (const topic of topics) {
      if (topic === '*') {
        // Wildcard: subscribe to all topics.
        state.subscriptions.add('*');
        subscribedTopics.push(...ALL_EVENT_TOPICS);
        break;
      }

      if (!this.isValidTopic(topic)) {
        this.sendError(socket, `Unknown topic: ${topic}`);
        continue;
      }

      state.subscriptions.add(topic as EventTopic);
      subscribedTopics.push(topic as EventTopic);
    }

    // Deduplicate the list for the confirmation message.
    const uniqueTopics = [...new Set(subscribedTopics)];

    this.safeSend(socket, JSON.stringify({
      type: 'subscribed',
      topics: uniqueTopics,
      timestamp: new Date().toISOString(),
    }));

    // If the client subscribed to pipeline.stage_log, replay the buffer.
    if (
      uniqueTopics.includes('pipeline.stage_log') &&
      this.stageLogBufferSupplier
    ) {
      const buffer = this.stageLogBufferSupplier();
      if (buffer.length > 0) {
        this.safeSend(socket, JSON.stringify({
          type: 'replay',
          topic: 'pipeline.stage_log',
          data: buffer,
          timestamp: new Date().toISOString(),
        }));
      }
    }
  }

  /**
   * Handle an unsubscribe message.
   */
  private handleUnsubscribe(
    socket: WebSocket,
    state: ClientState,
    msg: Record<string, unknown>,
  ): void {
    const topics = this.extractTopics(msg);
    if (topics === null) {
      this.sendError(socket, 'Unsubscribe requires "topics" (array) or "topic" (string)');
      return;
    }

    const unsubscribedTopics: string[] = [];

    for (const topic of topics) {
      if (topic === '*') {
        // Wildcard unsubscribe: clear all subscriptions.
        state.subscriptions.clear();
        unsubscribedTopics.push('*');
        break;
      }

      if (state.subscriptions.has(topic as EventTopic)) {
        state.subscriptions.delete(topic as EventTopic);
        unsubscribedTopics.push(topic);
      }
    }

    this.safeSend(socket, JSON.stringify({
      type: 'unsubscribed',
      topics: unsubscribedTopics,
      timestamp: new Date().toISOString(),
    }));
  }

  /**
   * Extract topics from a client message. Supports both `topics: string[]`
   * and `topic: string` formats.
   */
  private extractTopics(msg: Record<string, unknown>): string[] | null {
    // ADR-specified format: topics as array.
    if (Array.isArray(msg.topics)) {
      const filtered = msg.topics.filter(
        (t): t is string => typeof t === 'string',
      );
      return filtered.length > 0 ? filtered : null;
    }

    // Convenience format: single topic string.
    if (typeof msg.topic === 'string') {
      return [msg.topic];
    }

    return null;
  }

  // -------------------------------------------------------------------------
  // Heartbeat and idle checking
  // -------------------------------------------------------------------------

  /**
   * Send a heartbeat message to all connected clients.
   * Heartbeat goes to all clients regardless of subscriptions (system topic
   * is implicitly subscribed).
   */
  private sendHeartbeat(): void {
    if (this.stopped) return;

    const message = JSON.stringify({
      type: 'heartbeat',
      topic: 'system',
      timestamp: new Date().toISOString(),
      clientCount: this.clients.size,
    });

    for (const [socket] of this.clients) {
      if (socket.readyState === WebSocket.OPEN) {
        this.safeSend(socket, message);
      }
    }
  }

  /**
   * Check for idle clients and close their connections.
   *
   * A client is considered idle if no message has been received from it
   * within IDLE_TIMEOUT_MS (90 seconds).
   */
  private checkIdleClients(): void {
    if (this.stopped) return;

    const now = Date.now();

    for (const [socket, state] of this.clients) {
      const idleMs = now - state.lastActivity;
      if (idleMs >= IDLE_TIMEOUT_MS) {
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
  // Utility methods
  // -------------------------------------------------------------------------

  /**
   * Check whether a client is subscribed to a given topic.
   *
   * The `system` topic is always implicitly subscribed. The `*` wildcard
   * matches all topics.
   */
  private isSubscribed(state: ClientState, topic: string): boolean {
    if (topic === 'system') return true;
    if (state.subscriptions.has('*')) return true;
    return state.subscriptions.has(topic as EventTopic);
  }

  /**
   * Validate that a topic string is a known EventTopic or the wildcard `*`.
   */
  private isValidTopic(topic: string): boolean {
    return topic === '*' || ALL_EVENT_TOPICS.includes(topic as EventTopic);
  }

  /**
   * Safely send a message to a WebSocket client.
   * Catches and logs errors to prevent unhandled exceptions from crashing
   * the server.
   */
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

  /**
   * Send an error message to a specific client.
   * Does not close the connection.
   */
  private sendError(socket: WebSocket, message: string): void {
    this.safeSend(socket, JSON.stringify({
      type: 'error',
      message,
      timestamp: new Date().toISOString(),
    }));
  }
}
