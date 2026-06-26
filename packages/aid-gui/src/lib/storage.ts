/**
 * Browser storage access guard — shared between lastSeen.ts and backlog-delta.ts.
 *
 * Returns the global `localStorage` when available, or `null` when it is
 * unavailable (SSR/private mode). Never throws.
 */

/** Return the global localStorage, or null when it is unavailable (SSR/private mode). */
export function storage(): Storage | null {
  try {
    return typeof localStorage !== 'undefined' ? localStorage : null;
  } catch {
    // Some browsers throw on the very access of `localStorage` in private mode.
    return null;
  }
}
