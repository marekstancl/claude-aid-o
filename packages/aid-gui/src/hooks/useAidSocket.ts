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
import type { EventTopic, RunRef, InternalEvent } from '@aid/contract';

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

// Wire shapes MUST match the deployed aid-server (`ws/websocket.ts`), which is
// the producer of record. The server nests the event payload under `data`
// (the InternalEvent) and the replay frame carries NO topic — earlier this
// consumer was written to the spec §7.3 FLAT shape and silently never matched a
// real frame (live monitoring was dead). Aligned to the server here.
interface ReplayFrame {
  type: 'replay';
  data: unknown[]; // merged activity ring buffer (ActivityEvent[])
  ts: string;
}

interface EventFrame {
  type: 'event';
  topic: EventTopic;
  data: InternalEvent; // { projectId, runRef?, parsedData, ... }
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
  const { topic } = frame;
  // projectId/runRef live INSIDE the InternalEvent payload (server wire shape).
  const projectId = frame.data.projectId;
  const runRef: RunRef | undefined = frame.data.runRef;
  const keys: QueryKey[] = [];

  switch (topic) {
    case 'pipeline':
      // Pipeline state moved (FSM transition) → the EPIC deep view + project list.
      // Use the EPIC-detail key Screen C actually reads (['epic-detail',p,e]); the
      // old ['epic',...] key had NO consumer, so FSM transitions never live-refreshed
      // the deep view. Push both run-scoped + epic-scoped for prefix-match coverage.
      if (runRef) {
        keys.push(['epic-detail', projectId, runRef.epicId, runRef.runId]);
        keys.push(['epic-detail', projectId, runRef.epicId]);
      }
      keys.push(['projects']);
      break;
    case 'gates':
    case 'compliance':
    case 'checkpoints':
      // Run-level artifacts → the EPIC-detail view. Invalidate BOTH the
      // run-scoped key AND the epic-scoped key: react-query prefix-matching means
      // a 4-element filter never matches Screen C's 3-element ['epic-detail',p,e]
      // query (whose queryFn is getEpic(project,epic) — runId is correctly NOT in
      // its key). Without the epic-scoped push, the EPIC deep view would not
      // live-update on these events (only the 4s poll would).
      if (runRef) {
        keys.push(['epic-detail', projectId, runRef.epicId, runRef.runId]);
        keys.push(['epic-detail', projectId, runRef.epicId]);
      }
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
          // Server replay frame has NO topic — it is the merged activity ring
          // buffer sent once on subscribe. Seed the ['activity'] cache.
          const replay = frame as ReplayFrame;
          if (Array.isArray(replay.data)) {
            queryClient.setQueryData(['activity'], replay.data);
          }
          break;
        }
        case 'event': {
          const ev = frame as EventFrame;
          // Keep the live activity feed fresh on every event (debounced refetch
          // of /api/activity — the REST item shape == the replay item shape).
          debouncedInvalidate(queryClient, ['activity']);
          // Invalidate the per-topic read-model keys (projectId/runRef from data).
          for (const key of keysForEvent(ev)) {
            debouncedInvalidate(queryClient, key);
          }
          break;
        }
        default:
          // ignore other server frames (connected/subscribed/heartbeat) — forward-compatible
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
