/**
 * WebSocket hook for the AID Dashboard.
 *
 * Connects to the backend WebSocket server, subscribes to topics, dispatches
 * incoming events to the Zustand store, and handles auto-reconnect with
 * exponential backoff.
 *
 * The hook is designed to be called once at the application root (e.g., App.tsx)
 * with the current project ID. When the project ID changes, the hook tears down
 * the old connection and establishes a new one with fresh subscriptions.
 *
 * Connection lifecycle:
 *   1. Connect to ws://host/ws
 *   2. Receive "connected" message from server
 *   3. Send "subscribe" for all relevant topics
 *   4. Receive "subscribed" confirmation
 *   5. Process incoming events, heartbeats, replays
 *   6. Send periodic pings (every 25s) to keep connection alive
 *   7. On disconnect: exponential backoff reconnect (1s, 2s, 4s, 8s, max 30s)
 *   8. On reconnect: resync state via REST API refetch
 *
 * @example
 * ```tsx
 * function App() {
 *   const projectId = useStore((s) => s.currentProject?.id ?? null);
 *   useWebSocket(projectId);
 *   return <Dashboard />;
 * }
 * ```
 */

import { useEffect, useRef, useCallback } from 'react';
import { useStore } from '../store';
import { createApiClient } from '../api/client';
import type {
  WsIncomingMessage,
  WsOutgoingMessage,
  WsEventMessage,
  WsReplayMessage,
  EventTopic,
} from '../types/ws';
import type { StageLogEntryResponse, StoredIdea } from '../types/api';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Base reconnect delay in milliseconds. */
const RECONNECT_BASE_MS = 1_000;

/** Maximum reconnect delay in milliseconds. */
const RECONNECT_MAX_MS = 30_000;

/** Ping interval in milliseconds (must be < server's 30s heartbeat interval). */
const PING_INTERVAL_MS = 25_000;

/** Topics to subscribe to when a project is active. */
const DEFAULT_TOPICS: EventTopic[] = [
  'pipeline',
  'pipeline.stage_log',
  'queue',
  'decisions',
  'usage',
  'audit',
  'ideas',
  'epics',
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Compute the WebSocket URL from the current page location.
 * Supports both ws:// and wss:// based on the page protocol.
 */
function getWsUrl(): string {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${window.location.host}/ws`;
}

/**
 * Calculate exponential backoff delay with jitter.
 */
function backoffDelay(attempt: number): number {
  const exponential = RECONNECT_BASE_MS * Math.pow(2, attempt);
  const capped = Math.min(exponential, RECONNECT_MAX_MS);
  // Add up to 20% jitter to prevent thundering herd
  const jitter = capped * 0.2 * Math.random();
  return capped + jitter;
}

// ---------------------------------------------------------------------------
// Event dispatch helpers
// ---------------------------------------------------------------------------

/**
 * Convert a WS stage log event payload entry into the StageLogEntryResponse
 * shape expected by the store.
 */
function toStageLogEntry(entry: {
  timestamp: string;
  state: string;
  step: string | null;
  action: string;
  details: string;
  result: 'pass' | 'fail' | 'pending' | 'skip' | 'success';
}): StageLogEntryResponse {
  return {
    timestamp: entry.timestamp,
    state: entry.state,
    step: entry.step,
    action: entry.action,
    details: entry.details,
    result: entry.result,
  };
}

/**
 * Dispatch a single WS event message to the appropriate store slice.
 */
function dispatchEvent(msg: WsEventMessage): void {
  const store = useStore.getState();
  const { topic, data } = msg;

  switch (topic) {
    case 'pipeline': {
      if (data.type === 'file_change' && data.parsedData != null) {
        // The parsedData from a pipeline file_change event contains
        // pipeline state fields. Apply what is available.
        const parsed = data.parsedData as Record<string, unknown>;

        // Check if this looks like pipeline state data
        if ('currentState' in parsed || 'state' in parsed) {
          store.setPipelineState({
            currentState: (parsed.currentState ?? parsed.state ?? store.currentState) as string,
            currentEpicId: (parsed.currentEpicId ?? parsed.epicId ?? store.currentEpicId) as string | null,
            currentStepId: (parsed.currentStepId ?? parsed.currentStep ?? store.currentStepId) as string | null,
            progress: (parsed.progress as typeof store.pipelineProgress) ?? store.pipelineProgress,
          });

          // Sync legacy slice fields for backward compatibility
          const fsm = (parsed.currentState ?? parsed.state) as string | undefined;
          if (fsm) {
            store.setFSMState(fsm as Parameters<typeof store.setFSMState>[0]);
          }
          if (parsed.currentEpicId != null || parsed.epicId != null) {
            store.updatePipeline({
              epic: (parsed.currentEpicId ?? parsed.epicId) as string | null,
              activeStep: (parsed.currentStepId ?? parsed.currentStep) as string | null,
            });
          }

          // Pipeline state changes affect idea autoStatus (running/done).
          // Re-fetch ideas so cards auto-transition in the kanban board.
          const projectId = store.activeProject?.id ?? store.currentProject?.id ?? 'default';
          const client = createApiClient(projectId);
          client.getIdeas().then((result) => {
            if (result.ok) {
              useStore.getState().setIdeas(result.data);
            }
          }).catch(() => {
            // Non-fatal
          });
        }

        // Check if this looks like plan progress data (has `steps` map)
        if ('steps' in parsed && typeof parsed.steps === 'object' && parsed.steps !== null) {
          const stepsMap = parsed.steps as Record<string, {
            status: 'pending' | 'executing' | 'done' | 'failed' | 'skipped';
            startedAt?: string;
            completedAt?: string;
            reviewCycles?: number;
          }>;
          store.setStepStatuses(stepsMap);
        }
      }
      break;
    }

    case 'pipeline.stage_log': {
      if (data.type === 'stage_log') {
        store.addStageLogEntry(toStageLogEntry(data.entry));
      }
      break;
    }

    case 'queue': {
      if (data.type === 'file_change' && data.parsedData != null) {
        const parsed = data.parsedData as Record<string, unknown>;
        if ('queue' in parsed && Array.isArray(parsed.queue)) {
          store.setQueueInfo(
            parsed.queue.length,
            (parsed.paused as boolean) ?? false,
          );
        }
      }
      break;
    }

    case 'decisions': {
      if (data.type === 'file_change' && data.parsedData != null) {
        const parsed = data.parsedData as Record<string, unknown>;
        // If the parsed data is an array, it is the decisions list
        if (Array.isArray(parsed)) {
          store.setPendingDecisions(parsed.length);
        } else if ('total' in parsed && typeof parsed.total === 'number') {
          store.setPendingDecisions(parsed.total);
        }
      }
      break;
    }

    case 'usage': {
      if (data.type === 'file_change' && data.parsedData != null) {
        const parsed = data.parsedData as Record<string, unknown>;
        if ('totalEvents' in parsed) {
          store.setCcUsage({
            totalEvents: (parsed.totalEvents as number) ?? 0,
            agentDispatches: (parsed.agentDispatches as number) ?? 0,
            gateEvaluations: (parsed.gateEvaluations as number) ?? 0,
            escalations: (parsed.escalations as number) ?? 0,
          });
        }
      }
      break;
    }

    case 'audit': {
      if (data.type === 'file_change' && data.parsedData != null) {
        const parsed = data.parsedData as Record<string, unknown>;
        if ('scores' in parsed && typeof parsed.scores === 'object' && parsed.scores !== null) {
          const scores = parsed.scores as Record<string, unknown>;
          if ('overall' in scores && typeof scores.overall === 'number') {
            store.setHealthScore(scores.overall);
          }
        } else if ('healthScore' in parsed && typeof parsed.healthScore === 'number') {
          store.setHealthScore(parsed.healthScore);
        }
      }
      break;
    }

    case 'ideas': {
      if (data.type === 'file_change' && data.parsedData != null) {
        const parsed = data.parsedData;
        // parsedData from ideas.json is the full ideas array
        if (Array.isArray(parsed)) {
          store.setIdeas(parsed as StoredIdea[]);
        }
      }
      break;
    }

    case 'epics': {
      // EPIC file changed — re-fetch ideas to reflect autoStatus changes
      // (autoStatus is server-computed from linked plan/epic lifecycle)
      if (data.type === 'file_change') {
        const projectId = store.activeProject?.id ?? store.currentProject?.id ?? 'default';
        const client = createApiClient(projectId);
        client.getIdeas().then((result) => {
          if (result.ok) {
            useStore.getState().setIdeas(result.data);
          }
        }).catch(() => {
          // Non-fatal — ideas will refresh on next poll or navigation
        });
      }
      break;
    }

    default:
      // Unhandled topics are silently ignored -- no action needed
      break;
  }
}

/**
 * Dispatch a replay message (buffered stage log entries).
 */
function dispatchReplay(msg: WsReplayMessage): void {
  const store = useStore.getState();
  const entries = msg.data.map((item) => toStageLogEntry(item.entry));
  if (entries.length > 0) {
    store.addStageLogEntries(entries);
  }
}

// ---------------------------------------------------------------------------
// REST resync
// ---------------------------------------------------------------------------

/**
 * Refetch all state from REST endpoints after reconnect.
 * Failures are logged but do not block the reconnection flow.
 */
async function resyncFromRest(projectId: string): Promise<void> {
  const client = createApiClient(projectId);
  const store = useStore.getState();

  // Fire all requests concurrently
  const [pipelineRes, stepsRes, stageLogRes, queueRes, usageRes, auditRes, ideasRes] =
    await Promise.allSettled([
      client.getPipelineState(),
      client.getPipelineSteps(),
      client.getStageLog(),
      client.getQueue(),
      client.getUsage(),
      client.getAuditHealth(),
      client.getIdeas(),
    ]);

  // Pipeline state
  if (pipelineRes.status === 'fulfilled' && pipelineRes.value.ok) {
    const d = pipelineRes.value.data;
    store.setPipelineState({
      currentState: d.currentState,
      currentEpicId: d.currentEpicId,
      currentStepId: d.currentStepId,
      progress: d.progress,
    });
    // Sync legacy fields
    store.setFSMState(d.currentState as Parameters<typeof store.setFSMState>[0]);
    store.updatePipeline({
      epic: d.currentEpicId,
      activeStep: d.currentStepId,
    });
  }

  // Steps
  if (stepsRes.status === 'fulfilled' && stepsRes.value.ok) {
    store.setSteps(stepsRes.value.data);
  }

  // Stage log
  if (stageLogRes.status === 'fulfilled' && stageLogRes.value.ok) {
    store.clearStageLog();
    store.addStageLogEntries(stageLogRes.value.data);
  }

  // Queue
  if (queueRes.status === 'fulfilled' && queueRes.value.ok) {
    const d = queueRes.value.data;
    store.setQueueInfo(d.queue.length, d.paused);
  }

  // Usage
  if (usageRes.status === 'fulfilled' && usageRes.value.ok) {
    const d = usageRes.value.data;
    store.setCcUsage({
      totalEvents: d.totalEvents,
      agentDispatches: d.agentDispatches,
      gateEvaluations: d.gateEvaluations,
      escalations: d.escalations,
    });
  }

  // Audit health
  if (auditRes.status === 'fulfilled' && auditRes.value.ok) {
    const d = auditRes.value.data;
    store.setHealthScore(d.scores.overall);
  }

  // Ideas
  if (ideasRes.status === 'fulfilled' && ideasRes.value.ok) {
    store.setIdeas(ideasRes.value.data);
  }
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

/**
 * Connect to the AID backend WebSocket and keep the store synchronized.
 *
 * Call this once in your application root component. When `projectId` is null,
 * no connection is established. When it changes, the previous connection is
 * torn down and a new one is created.
 *
 * @param projectId - The currently active project ID, or null if none.
 */
export function useWebSocket(projectId: string | null): void {
  const wsRef = useRef<WebSocket | null>(null);
  const pingIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isMountedRef = useRef(true);

  /**
   * Send a typed message over the WebSocket if it is open.
   */
  const send = useCallback((msg: WsOutgoingMessage): void => {
    const ws = wsRef.current;
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(msg));
    }
  }, []);

  /**
   * Stop the ping interval timer.
   */
  const stopPing = useCallback((): void => {
    if (pingIntervalRef.current !== null) {
      clearInterval(pingIntervalRef.current);
      pingIntervalRef.current = null;
    }
  }, []);

  /**
   * Start sending periodic pings.
   */
  const startPing = useCallback((): void => {
    stopPing();
    pingIntervalRef.current = setInterval(() => {
      send({ type: 'ping' });
    }, PING_INTERVAL_MS);
  }, [send, stopPing]);

  /**
   * Cancel any pending reconnect timeout.
   */
  const cancelReconnect = useCallback((): void => {
    if (reconnectTimeoutRef.current !== null) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
  }, []);

  /**
   * Tear down the current WebSocket connection and all timers.
   */
  const teardown = useCallback((): void => {
    cancelReconnect();
    stopPing();

    const ws = wsRef.current;
    if (ws) {
      // Remove event handlers before closing to avoid triggering onclose handler
      ws.onopen = null;
      ws.onmessage = null;
      ws.onclose = null;
      ws.onerror = null;
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
        ws.close(1000, 'Client teardown');
      }
      wsRef.current = null;
    }

    useStore.getState().setWsStatus('disconnected');
    useStore.getState().setSubscribedTopics([]);
  }, [cancelReconnect, stopPing]);

  /**
   * Establish a WebSocket connection.
   * This is the core connect function, called on mount and on reconnect.
   */
  const connect = useCallback((pid: string): void => {
    if (!isMountedRef.current) return;

    // Ensure any prior connection is cleaned up
    const existingWs = wsRef.current;
    if (existingWs) {
      existingWs.onopen = null;
      existingWs.onmessage = null;
      existingWs.onclose = null;
      existingWs.onerror = null;
      if (existingWs.readyState === WebSocket.OPEN || existingWs.readyState === WebSocket.CONNECTING) {
        existingWs.close(1000, 'Reconnecting');
      }
    }

    useStore.getState().setWsStatus('connecting');

    const ws = new WebSocket(getWsUrl());
    wsRef.current = ws;

    ws.onopen = () => {
      if (!isMountedRef.current) return;
      // Do not set "connected" here -- wait for the server's "connected" message
    };

    ws.onmessage = (event: MessageEvent) => {
      if (!isMountedRef.current) return;

      let msg: WsIncomingMessage;
      try {
        msg = JSON.parse(event.data as string) as WsIncomingMessage;
      } catch {
        // Unparseable message -- ignore
        return;
      }

      switch (msg.type) {
        case 'connected': {
          const store = useStore.getState();
          store.setWsStatus('connected');
          store.resetReconnectAttempt();

          // Subscribe to all default topics
          send({ type: 'subscribe', topics: DEFAULT_TOPICS });

          // Start keepalive pings
          startPing();

          // Resync state from REST after reconnect (async, fire-and-forget)
          resyncFromRest(pid).catch(() => {
            // Resync failures are non-fatal
          });
          break;
        }

        case 'subscribed': {
          useStore.getState().setSubscribedTopics(msg.topics);
          break;
        }

        case 'event': {
          dispatchEvent(msg);
          break;
        }

        case 'replay': {
          dispatchReplay(msg);
          break;
        }

        case 'heartbeat': {
          useStore.getState().handleHeartbeat(msg.timestamp, msg.clientCount);
          break;
        }

        case 'pong': {
          // Pong received -- connection is alive, nothing to do
          break;
        }

        case 'error': {
          console.warn('[useWebSocket] Server error:', msg.message);
          break;
        }

        case 'unsubscribed': {
          // Unsubscribe confirmation -- currently not used in the reconnect flow
          break;
        }

        default: {
          // Unknown message type -- ignore for forward compatibility
          break;
        }
      }
    };

    ws.onclose = (event: CloseEvent) => {
      if (!isMountedRef.current) return;

      stopPing();
      wsRef.current = null;

      const store = useStore.getState();
      store.setWsStatus('reconnecting');
      store.incrementReconnectAttempt();

      const attempt = store.reconnectAttempt;
      const delay = backoffDelay(attempt);

      reconnectTimeoutRef.current = setTimeout(() => {
        if (isMountedRef.current) {
          connect(pid);
        }
      }, delay);
    };

    ws.onerror = () => {
      // The onerror event is always followed by onclose, so we handle
      // reconnection there. Just log for diagnostics.
      if (!isMountedRef.current) return;
    };
  }, [send, startPing, stopPing, cancelReconnect]);

  // ---------------------------------------------------------------------------
  // Effect: manage connection lifecycle
  // ---------------------------------------------------------------------------

  useEffect(() => {
    isMountedRef.current = true;

    if (projectId) {
      connect(projectId);
    } else {
      teardown();
    }

    return () => {
      isMountedRef.current = false;
      teardown();
    };
  }, [projectId, connect, teardown]);
}
