/**
 * Tests for usePollingFallback — the 5s REST fallback that engages whenever the
 * live WebSocket is not OPEN.
 *
 * Verifies (AC):
 *  - engages within ~5s of the socket leaving OPEN,
 *  - polls ['activity'] + each active key every 5s,
 *  - sets the banner flag (polling=true),
 *  - clears on re-OPEN (polling=false, no further invalidations),
 *  - engages on the INITIAL closed/connecting state too,
 *  - never runs duplicate intervals.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { createElement, type ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { QueryKey } from '@tanstack/react-query';
import { usePollingFallback, POLL_INTERVAL_MS } from './usePollingFallback';
import type { AidSocketStatus } from './useAidSocket';

function makeWrapper(client: QueryClient) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client }, children);
  };
}

describe('usePollingFallback', () => {
  let client: QueryClient;
  let invalidateSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers();
    client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    invalidateSpy = vi.fn();
    // Spy on invalidateQueries to observe which keys are refetched per tick.
    client.invalidateQueries = invalidateSpy as unknown as QueryClient['invalidateQueries'];
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('engages within ~5s of socket loss, polls activity + active keys, sets banner flag', () => {
    const activeKeys: QueryKey[] = [['epic', 'wan', 'E-035']];
    const { result, rerender } = renderHook(
      ({ status }) => usePollingFallback(status, activeKeys),
      {
        initialProps: { status: 'open' as AidSocketStatus },
        wrapper: makeWrapper(client),
      },
    );

    // While OPEN: no polling, no invalidations.
    expect(result.current.polling).toBe(false);
    act(() => {
      vi.advanceTimersByTime(POLL_INTERVAL_MS);
    });
    expect(invalidateSpy).not.toHaveBeenCalled();

    // Socket drops to 'closed'.
    act(() => {
      rerender({ status: 'closed' as AidSocketStatus });
    });
    // Banner not raised yet (no tick has fired).
    expect(result.current.polling).toBe(false);

    // After ~5s the first tick fires: banner raised + activity + active key refetched.
    act(() => {
      vi.advanceTimersByTime(POLL_INTERVAL_MS);
    });
    expect(result.current.polling).toBe(true);

    const calledKeys = invalidateSpy.mock.calls.map((c) => JSON.stringify(c[0].queryKey));
    expect(calledKeys).toContain(JSON.stringify(['activity']));
    expect(calledKeys).toContain(JSON.stringify(['epic', 'wan', 'E-035']));
  });

  it('clears on re-OPEN: polling=false and no further invalidations', () => {
    const { result, rerender } = renderHook(
      ({ status }) => usePollingFallback(status, []),
      {
        initialProps: { status: 'closed' as AidSocketStatus },
        wrapper: makeWrapper(client),
      },
    );

    // First tick engages the fallback.
    act(() => {
      vi.advanceTimersByTime(POLL_INTERVAL_MS);
    });
    expect(result.current.polling).toBe(true);
    const countAfterEngage = invalidateSpy.mock.calls.length;
    expect(countAfterEngage).toBeGreaterThan(0);

    // Socket reconnects.
    act(() => {
      rerender({ status: 'open' as AidSocketStatus });
    });
    expect(result.current.polling).toBe(false);

    // No further invalidations after re-OPEN, even as time advances.
    act(() => {
      vi.advanceTimersByTime(POLL_INTERVAL_MS * 3);
    });
    expect(invalidateSpy.mock.calls.length).toBe(countAfterEngage);
  });

  it('engages on the INITIAL closed/connecting state (banner ~5s after mount)', () => {
    const { result } = renderHook(
      ({ status }) => usePollingFallback(status, []),
      {
        initialProps: { status: 'connecting' as AidSocketStatus },
        wrapper: makeWrapper(client),
      },
    );

    expect(result.current.polling).toBe(false);
    act(() => {
      vi.advanceTimersByTime(POLL_INTERVAL_MS);
    });
    expect(result.current.polling).toBe(true);
    expect(invalidateSpy).toHaveBeenCalled();
  });

  it('does not run duplicate intervals across status churn', () => {
    const { result, rerender } = renderHook(
      ({ status }) => usePollingFallback(status, []),
      {
        initialProps: { status: 'connecting' as AidSocketStatus },
        wrapper: makeWrapper(client),
      },
    );

    // connecting -> closed (still down): the effect re-runs and must clear the
    // old interval before starting a new one.
    act(() => {
      rerender({ status: 'closed' as AidSocketStatus });
    });

    // One tick window should produce exactly one ['activity'] invalidation, not two.
    act(() => {
      vi.advanceTimersByTime(POLL_INTERVAL_MS);
    });
    const activityCalls = invalidateSpy.mock.calls.filter(
      (c) => JSON.stringify(c[0].queryKey) === JSON.stringify(['activity']),
    );
    expect(activityCalls.length).toBe(1);
  });
});
