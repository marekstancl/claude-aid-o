/**
 * `lastSeen` store (§13.3) — purely client-side in MVP1.
 *
 * "Co se změnilo od poslední návštěvy" needs to remember, per scope, the ISO
 * timestamp of the manager's last visit. We persist this in `localStorage` under
 * per-scope keys `aid.lastSeen.<scopeKey>`, where `scopeKey` is one of:
 *
 *   - `infra`            — the infra (Screen G) scope
 *   - `p:<project>`      — a project scope, e.g. `p:wan`
 *   - `p:<project>:<id>` — a plan scope, e.g. `p:wan:P003`
 *
 * Storage is best-effort: in private mode / over quota / with storage disabled,
 * getters return `null` (→ treated as a first visit) and setters swallow the
 * error with a `console.warn` — the UI degrades to "první návštěva", never
 * crashes.
 *
 * A legacy single-container {@link LastSeen} (v1) blob (`aid.lastSeen`) is
 * migrated lazily into the per-scope keys via {@link migrateLastSeenContainer}.
 */

import type { LastSeen } from '@aid/contract';
import { storage } from './storage';

/** Per-scope localStorage key prefix. */
const KEY_PREFIX = 'aid.lastSeen.';
/** Legacy single-blob container key (pre per-scope keys). */
const CONTAINER_KEY = 'aid.lastSeen';

/** Build the per-scope storage key for a scopeKey (`infra`, `p:wan`, `p:wan:P003`). */
export function lastSeenKey(scopeKey: string): string {
  return KEY_PREFIX + scopeKey;
}

/**
 * Read the last-seen ISO timestamp for a scope, or `null` when never seen /
 * storage is unavailable. Never throws.
 */
export function getLastSeen(scopeKey: string): string | null {
  const store = storage();
  if (!store) return null;
  try {
    return store.getItem(lastSeenKey(scopeKey));
  } catch {
    return null;
  }
}

/**
 * Persist the last-seen ISO timestamp for a scope. Swallows
 * `QuotaExceededError` / disabled-storage failures with a `console.warn`
 * (degrade gracefully — the next visit is simply treated as a first visit).
 */
export function setLastSeen(scopeKey: string, iso: string): void {
  const store = storage();
  if (!store) return;
  try {
    store.setItem(lastSeenKey(scopeKey), iso);
  } catch (err) {
    console.warn(`[lastSeen] could not persist "${scopeKey}":`, err);
  }
}

/**
 * Migrate a legacy single-container {@link LastSeen} (v1) blob into the
 * per-scope keys, then drop the container. Unrecognized / older versions are
 * discarded (treated as no data → first visit), never thrown.
 *
 * Idempotent: a no-op when the container is absent or unparseable.
 */
export function migrateLastSeenContainer(): void {
  const store = storage();
  if (!store) return;

  let rawValue: string | null;
  try {
    rawValue = store.getItem(CONTAINER_KEY);
  } catch {
    return;
  }
  if (!rawValue) return;

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawValue);
  } catch {
    // Unparseable container → discard it; treat as first-visit for all scopes.
    safeRemove(store, CONTAINER_KEY);
    return;
  }

  // Only the known version 1 shape is migrated; anything else is discarded.
  if (!isLastSeenV1(parsed)) {
    safeRemove(store, CONTAINER_KEY);
    return;
  }

  for (const [scopeKey, iso] of Object.entries(parsed.scopes)) {
    if (typeof iso === 'string') {
      try {
        store.setItem(lastSeenKey(scopeKey), iso);
      } catch (err) {
        console.warn(`[lastSeen] migration could not persist "${scopeKey}":`, err);
      }
    }
  }
  safeRemove(store, CONTAINER_KEY);
}

/** Type guard for the version-1 LastSeen container shape. */
function isLastSeenV1(value: unknown): value is LastSeen {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { version?: unknown }).version === 1 &&
    typeof (value as { scopes?: unknown }).scopes === 'object' &&
    (value as { scopes?: unknown }).scopes !== null
  );
}

/** Remove a key, swallowing any storage failure. */
function safeRemove(store: Storage, key: string): void {
  try {
    store.removeItem(key);
  } catch {
    /* ignore */
  }
}
