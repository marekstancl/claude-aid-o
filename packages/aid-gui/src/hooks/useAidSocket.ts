/**
 * useAidSocket — the AID Cockpit live-update WebSocket hook.
 *
 * Subscribes to a set of §7.3 topics + projects, then maps each inbound event
 * to one or more react-query keys and invalidates/sets that cache so the UI
 * re-reads. Same-key invalidations are debounced (~250ms) so a burst of events
 * touching one key coalesces to a single refetch.
 *
 * Lifecycle (subscribe / ping / reconnect-backoff) is salvaged from the v1
 * `useWebSocket.ts`, re-pointed at the §7.3 envelope:
 *   - subscribe frame:  { type: "subscribe", topics, projects }
 *   - inbound events carry `ts` (was `timestamp`) and a `projectId` for
 *     per-project filtering.
 *   - reconnect backoff: 1s, 2s, 4s, 8s … capped at 30s; ping every 25s.
 *
 * The socket NEVER throws on a malformed frame: JSON.parse is wrapped in
 * try/catch (console.warn + keep the socket open).
 */

import { useEffect, useRef, useState, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import type { QueryClient, QueryKey } from '@tanstack/react-query';
import type { EventTopic, RunRef } from '@aid/contract';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const RECONNECT_BASE_MS = 1_000;
const RECONNECT_MAX_MS = 30_000;
const PING_INTERVAL_MS = 25_000;
const INVALIDATE_DEBOUNCE_MS = 250;

/** Public connection status surfaced to consumers. */
export type AidSocketStatus = 'connecting' | 'open' | 'closed';

/** Options for {@link useAidSocket}. */
export interface UseAidSocketOptions {
  topics: EventTopic[];
  projects: string[];
}

// ---------------------------------------------------------------------------
// §7.3 inbound frame shapes (wire types — kept local to the consumer package)
// ---------------------------------------------------------------------------

interface SubscribeFrame {
  type: 'subscribe';
  topics: EventTopic[];
  projects: string[];
}

interface ReplayFrame {
  type: 'replay';
  topic: 'pipeline.timeline';
  data: unknown;
}

interface EventFrame {
  type: 'event';
  topic: EventTopic;
  projectId: string;
  runRef?: RunRef;
  parsed: unknown;
  ts: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Build the same-origin WS URL; wss: under https, ws: otherwise. Relative — never a hardcoded host/port. */
function buildWsUrl(): string {
  const url = new URL('/ws', location.href);
  url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.toString();
}

/** Exponential backoff with jitter, capped at RECONNECT_MAX_MS. */
function backoffDelay(attempt: number): number {
  const capped = Math.min(RECONNECT_BASE_MS * 2 ** attempt, RECONNECT_MAX_MS);
  return capped + capped * 0.2 * Math.random();
}

/** Serialize a QueryKey to a stable string for the debounce Map. */
function keyId(key: QueryKey): string {
  return JSON.stringify(key);
}

// ---------------------------------------------------------------------------
// Event → query-key routing (§7.3, P047 Step 36)
// ---------------------------------------------------------------------------

/** react-query keys that should be invalidated for a given inbound event. */
function keysForEvent(frame: EventFrame): QueryKey[] {
  const { topic, projectId, runRef } = frame;
  const keys: QueryKey[] = [];

  switch (topic) {
    case 'pipeline':
      // Pipeline state moved → the active EPIC view + the project list.
      if (runRef) keys.push(['epic', projectId, runRef.epicId]);
      keys.push(['projects']);
      break;
    case 'gates':
    case 'compliance':
    case 'checkpoints':
      // Run-level artifacts → the EPIC-detail (per-run) view.
      if (runRef) keys.push(['epic-detail', projectId, runRef.epicId, runRef.runId]);
      break;
    case 'epics':
    case 'queue':
      keys.push(['projects']);
      keys.push(['epics', projectId]);
      break;
    default:
      break;
  }

  // ANY pipeline/gates/compliance/checkpoints/plan/report change also affects
  // the cross-project plan-outcome analytics roll-up.
  if (
    topic === 'pipeline' ||
    topic === 'gates' ||
    topic === 'compliance' ||
    topic === 'checkpoints'
  ) {
    keys.push(['plan-outcomes']);
  }

  return keys;
}

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

/**
 * Connect to `/ws`, subscribe to `topics`+`projects`, and keep the react-query
 * cache fresh. Returns the live connection `status`.
 */
export function useAidSocket(opts: UseAidSocketOptions): { status: AidSocketStatus } {
  const queryClient = useQueryClient();
  const [status, setStatus] = useState<AidSocketStatus>('connecting');

  const wsRef = useRef<WebSocket | null>(null);
  const pingRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const reconnectRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const attemptRef = useRef(0);
  const mountedRef = useRef(true);
  // Per-key debounce timers so a same-key burst coalesces to one refetch.
  const debounceRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  // Keep latest opts in a ref so the connect closure stays stable across renders.
  const optsRef = useRef(opts);
  optsRef.current = opts;

  /** Debounced invalidateQueries for a single key. */
  const debouncedInvalidate = useCallback(
    (client: QueryClient, key: QueryKey): void => {
      const id = keyId(key);
      const timers = debounceRef.current;
      const existing = timers.get(id);
      if (existing) clearTimeout(existing);
      timers.set(
        id,
        setTimeout(() => {
          timers.delete(id);
          void client.invalidateQueries({ queryKey: key });
        }, INVALIDATE_DEBOUNCE_MS),
      );
    },
    [],
  );

  const stopPing = useCallback((): void => {
    if (pingRef.current !== null) {
      clearInterval(pingRef.current);
      pingRef.current = null;
    }
  }, []);

  const clearAllDebounces = useCallback((): void => {
    for (const t of debounceRef.current.values()) clearTimeout(t);
    debounceRef.current.clear();
  }, []);

  useEffect(() => {
    mountedRef.current = true;

    const handleMessage = (event: MessageEvent): void => {
      if (!mountedRef.current) return;

      let frame: SubscribeFrame | ReplayFrame | EventFrame | { type?: string };
      try {
        frame = JSON.parse(event.data as string);
      } catch {
        // Bad frame — never throw, never close. Log and keep the socket open.
        console.warn('[useAidSocket] dropped a malformed frame');
        return;
      }

      if (typeof frame !== 'object' || frame === null || !('type' in frame)) return;

      switch (frame.type) {
        case 'replay': {
          const replay = frame as ReplayFrame;
          if (replay.topic === 'pipeline.timeline') {
            queryClient.setQueryData(['activity'], replay.data);
          }
          break;
        }
        case 'event': {
          const ev = frame as EventFrame;
          // pipeline.timeline → append parsed onto the ['activity'] cache.
          if (ev.topic === 'pipeline.timeline') {
            queryClient.setQueryData<unknown[]>(['activity'], (prev) => {
              const list = prev ?? [];
              return [...list, ev.parsed];
            });
            break;
          }
          for (const key of keysForEvent(ev)) {
            debouncedInvalidate(queryClient, key);
          }
          break;
        }
        default:
          // ignore other server frames (heartbeat/pong/etc.) — forward-compatible
          break;
      }
    };

    const connect = (): void => {
      if (!mountedRef.current) return;
      setStatus('connecting');

      let ws: WebSocket;
      try {
        ws = new WebSocket(buildWsUrl());
      } catch {
        scheduleReconnect();
        return;
      }
      wsRef.current = ws;

      ws.onopen = () => {
        if (!mountedRef.current) return;
        attemptRef.current = 0;
        setStatus('open');
        const sub: SubscribeFrame = {
          type: 'subscribe',
          topics: optsRef.current.topics,
          projects: optsRef.current.projects,
        };
        ws.send(JSON.stringify(sub));
        stopPing();
        pingRef.current = setInterval(() => {
          if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }));
        }, PING_INTERVAL_MS);
      };

      ws.onmessage = handleMessage;

      ws.onerror = () => {
        // onerror is always followed by onclose — reconnection handled there.
      };

      ws.onclose = () => {
        if (!mountedRef.current) return;
        stopPing();
        wsRef.current = null;
        setStatus('closed');
        scheduleReconnect();
      };
    };

    const scheduleReconnect = (): void => {
      if (!mountedRef.current) return;
      const delay = backoffDelay(attemptRef.current);
      attemptRef.current += 1;
      reconnectRef.current = setTimeout(() => {
        if (mountedRef.current) connect();
      }, delay);
    };

    connect();

    return () => {
      mountedRef.current = false;
      stopPing();
      clearAllDebounces();
      if (reconnectRef.current !== null) {
        clearTimeout(reconnectRef.current);
        reconnectRef.current = null;
      }
      const ws = wsRef.current;
      if (ws) {
        ws.onopen = null;
        ws.onmessage = null;
        ws.onclose = null;
        ws.onerror = null;
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
          ws.close(1000, 'unmount');
        }
        wsRef.current = null;
      }
    };
    // Reconnect only when topic/project SET changes (serialized), not on every render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    queryClient,
    stopPing,
    clearAllDebounces,
    debouncedInvalidate,
    JSON.stringify(opts.topics),
    JSON.stringify(opts.projects),
  ]);

  return { status };
}
