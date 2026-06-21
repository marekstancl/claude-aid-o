// @vitest-environment jsdom
/**
 * WS frame CONFORMANCE test for useAidSocket — drives the hook with the EXACT
 * frame shapes the deployed aid-server emits (`ws/websocket.ts`), not the spec's
 * flat shape. This is the regression guard for the REOPEN finding "WS klient a
 * server mají nekompatibilní protokol": the client was reading projectId/runRef/
 * parsed at the top of the frame while the server nests them under `data`, and
 * the replay frame carries no topic. A passing test here means live monitoring
 * actually wires against the real producer.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useAidSocket } from './useAidSocket';

// --- Controllable mock WebSocket -------------------------------------------
class MockWebSocket {
  static OPEN = 1;
  static instances: MockWebSocket[] = [];
  url: string;
  readyState = 0;
  sent: string[] = [];
  onopen: ((e: unknown) => void) | null = null;
  onmessage: ((e: { data: string }) => void) | null = null;
  onclose: ((e: unknown) => void) | null = null;
  onerror: ((e: unknown) => void) | null = null;
  constructor(url: string) {
    this.url = url;
    MockWebSocket.instances.push(this);
  }
  send(data: string) { this.sent.push(data); }
  close() { this.readyState = 3; this.onclose?.({}); }
  open() { this.readyState = MockWebSocket.OPEN; this.onopen?.({}); }
  emit(frame: unknown) { this.onmessage?.({ data: JSON.stringify(frame) }); }
}

let qc: QueryClient;
const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider client={qc}>{children}</QueryClientProvider>
);

beforeEach(() => {
  MockWebSocket.instances = [];
  vi.stubGlobal('WebSocket', MockWebSocket as unknown as typeof WebSocket);
  vi.useFakeTimers();
  qc = new QueryClient();
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('useAidSocket — real-server frame conformance', () => {
  it('builds a relative /ws URL (never :3911) and sends a subscribe frame on open', () => {
    renderHook(() => useAidSocket({ topics: [], projects: [] }), { wrapper });
    const ws = MockWebSocket.instances[0];
    expect(ws).toBeDefined();
    expect(ws.url).toContain('/ws');
    expect(ws.url).not.toContain('3911');
    act(() => ws.open());
    expect(ws.sent.length).toBeGreaterThan(0);
    const sub = JSON.parse(ws.sent[0]);
    expect(sub.type).toBe('subscribe');
    expect(sub).toHaveProperty('topics');
    expect(sub).toHaveProperty('projects');
  });

  it('a real EVENT frame (event nested in `data`) invalidates the correct key', () => {
    const spy = vi.spyOn(qc, 'invalidateQueries');
    renderHook(() => useAidSocket({ topics: [], projects: [] }), { wrapper });
    const ws = MockWebSocket.instances[0];
    act(() => ws.open());
    // EXACT server shape: { type:'event', topic, data: InternalEvent, ts }
    act(() => {
      ws.emit({
        type: 'event',
        topic: 'gates',
        data: {
          type: 'file_change',
          projectId: 'wan',
          runRef: { epicId: 'E-001-1_1', runId: 'R-1' },
          parsedData: {},
        },
        ts: '2026-06-21T00:00:00Z',
      });
    });
    act(() => { vi.advanceTimersByTime(300); }); // flush the 250ms debounce
    const keys = spy.mock.calls.map((c) => JSON.stringify((c[0] as { queryKey: unknown }).queryKey));
    expect(keys).toContain(JSON.stringify(['epic-detail', 'wan', 'E-001-1_1', 'R-1']));
    expect(keys).toContain(JSON.stringify(['activity']));
  });

  it('a real REPLAY frame (no topic, data array) seeds the activity cache', () => {
    renderHook(() => useAidSocket({ topics: [], projects: [] }), { wrapper });
    const ws = MockWebSocket.instances[0];
    act(() => ws.open());
    const buffer = [{ ts: '2026-06-21T00:00:00Z', kind: 'x' }];
    act(() => { ws.emit({ type: 'replay', data: buffer, ts: '2026-06-21T00:00:01Z' }); });
    expect(qc.getQueryData(['activity'])).toEqual(buffer);
  });

  it('a malformed frame never throws and keeps the socket open', () => {
    renderHook(() => useAidSocket({ topics: [], projects: [] }), { wrapper });
    const ws = MockWebSocket.instances[0];
    act(() => ws.open());
    expect(() => act(() => ws.onmessage?.({ data: 'not json{' }))).not.toThrow();
    expect(ws.readyState).toBe(MockWebSocket.OPEN);
  });
});
