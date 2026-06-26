// @vitest-environment jsdom
/**
 * App WIRING test — the regression guard for the REOPEN blocker "Live monitoring
 * není zapojené". It asserts that rendering the shell actually MOUNTS useAidSocket
 * (a WebSocket is constructed) and usePollingFallback + the offline banner (the
 * banner shows while the socket is not OPEN). Component unit tests passed before
 * while NOTHING was wired — this test fails if App stops mounting the hooks.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';

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
  constructor(url: string) { this.url = url; MockWebSocket.instances.push(this); }
  send(d: string) { this.sent.push(d); }
  close() { this.readyState = 3; this.onclose?.({}); }
  open() { this.readyState = MockWebSocket.OPEN; this.onopen?.({}); }
}

beforeEach(() => {
  MockWebSocket.instances = [];
  vi.stubGlobal('WebSocket', MockWebSocket as unknown as typeof WebSocket);
  // getProjects() → empty OK envelope so ProjectsProvider settles.
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => ({ ok: true, json: async () => ({ ok: true, data: [] }) }) as unknown as Response),
  );
});
afterEach(() => vi.unstubAllGlobals());

function renderApp() {
  const qc = new QueryClient();
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={['/']}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('App wiring — live monitoring is mounted', () => {
  it('mounts useAidSocket (constructs a /ws WebSocket)', () => {
    renderApp();
    expect(MockWebSocket.instances.length).toBeGreaterThan(0);
    expect(MockWebSocket.instances[0].url).toContain('/ws');
  });

  it('shows the offline banner ~5s after mount while the socket is not OPEN (polling fallback wired)', async () => {
    vi.useFakeTimers();
    try {
      renderApp();
      // The banner is intentionally delayed to the first 5s poll tick (avoids
      // flashing during a normal brief connect). Advance past it.
      await act(async () => { await vi.advanceTimersByTimeAsync(5_100); });
      expect(screen.getByText(/živé spojení nejede/i)).toBeInTheDocument();
    } finally {
      vi.useRealTimers();
    }
  });

  it('hides the banner once the socket opens', async () => {
    vi.useFakeTimers();
    try {
      renderApp();
      await act(async () => { await vi.advanceTimersByTimeAsync(5_100); });
      expect(screen.getByText(/živé spojení nejede/i)).toBeInTheDocument();
      await act(async () => { MockWebSocket.instances[0].open(); });
      expect(screen.queryByText(/živé spojení nejede/i)).not.toBeInTheDocument();
    } finally {
      vi.useRealTimers();
    }
  });
});
