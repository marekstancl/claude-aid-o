/**
 * usePollingFallback — REST polling fallback for when the live WS is down.
 *
 * Whenever the socket is not OPEN (including the INITIAL connecting/closed state
 * at mount), this starts a 5s interval that refetches the `['activity']` feed
 * plus every supplied active query key — so the dashboard keeps updating off
 * `GET /api/activity` (+ the active keys) instead of going stale. The first poll
 * fires ~5s after the socket leaves OPEN, which is also when the UI shows the
 * "živé spojení nejede - aktualizuji po 5 s" banner (driven by `polling: true`).
 *
 * When the socket returns to OPEN the interval is cleared and `polling` goes
 * false. The interval is always cleared before a new one starts, so there is
 * never a duplicate interval.
 */

import { useEffect, useRef, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import type { QueryKey } from '@tanstack/react-query';
import type { AidSocketStatus } from './useAidSocket';

/** Poll cadence in ms while the live connection is down. */
export const POLL_INTERVAL_MS = 5_000;

/**
 * Engage a 5s REST polling fallback while `socketStatus` is not 'open'.
 *
 * @param socketStatus   current WS status from {@link useAidSocket}.
 * @param activeQueryKeys keys for the currently-visible screen to refetch each tick.
 * @returns `{ polling }` — true while the fallback interval is active (banner flag).
 */
export function usePollingFallback(
  socketStatus: AidSocketStatus,
  activeQueryKeys: QueryKey[],
): { polling: boolean } {
  const queryClient = useQueryClient();
  const [polling, setPolling] = useState(false);

  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  // Keep latest keys in a ref so changing the key list does not restart the timer.
  const keysRef = useRef<QueryKey[]>(activeQueryKeys);
  keysRef.current = activeQueryKeys;

  useEffect(() => {
    const clear = (): void => {
      if (intervalRef.current !== null) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };

    if (socketStatus === 'open') {
      // Live connection healthy → tear down the fallback.
      clear();
      setPolling(false);
      return;
    }

    // Socket is connecting or closed → engage the 5s fallback. Clear any
    // existing interval first so we never run two in parallel.
    clear();
    intervalRef.current = setInterval(() => {
      void queryClient.invalidateQueries({ queryKey: ['activity'] });
      for (const key of keysRef.current) {
        void queryClient.invalidateQueries({ queryKey: key });
      }
      // First tick (~5s after losing OPEN) raises the banner flag.
      setPolling(true);
    }, POLL_INTERVAL_MS);

    return clear;
  }, [socketStatus, queryClient]);

  return { polling };
}
