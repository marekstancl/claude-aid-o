/**
 * Shared react-query client for the AID Cockpit (read-only monitoring PWA).
 *
 * Tuned for a live dashboard fed by a WebSocket + a 5s REST polling fallback:
 *   - staleTime ~4s    — within a single WS burst, repeated reads of the same
 *                        key are served from cache instead of refetching.
 *   - refetchOnWindowFocus: true — when the operator returns to the tab the
 *                        dashboard re-reads so a stale view never lingers.
 *   - retry: 1         — one transient retry; the polling fallback handles
 *                        sustained outages, so we do not hammer a dead server.
 */

import { QueryClient } from '@tanstack/react-query';

/** Default stale window in ms — see module doc. */
export const DEFAULT_STALE_TIME_MS = 4_000;

/**
 * The single QueryClient instance for the app. Created once at module load and
 * shared via <QueryClientProvider> in main.tsx.
 */
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: DEFAULT_STALE_TIME_MS,
      refetchOnWindowFocus: true,
      retry: 1,
    },
  },
});
