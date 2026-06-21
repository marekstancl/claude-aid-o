/**
 * Client-side backlog delta (§13.7) — CLIENT-SIDE in MVP1.
 *
 * "Co se v backlogu změnilo od minule" is computed in the browser by diffing the
 * current `/api/backlog` rows against a locally-persisted {@link BacklogSnapshot}
 * (stored under `aid.backlog.<scopeKey>`). The server never owns this in MVP1.
 *
 * Classification (keyed by `id` where present):
 *   - snapshot === null                       → firstVisit: true, four lists empty
 *   - current row absent from snapshot        → added
 *   - snapshot row now in a CLOSED status     → closed (carry prevStatus)
 *     (closed statuses: approved | rejected | deferred)
 *   - priority differs                        → priorityChanged (carry prevPriority)
 *   - status changed but not closed           → statusChanged
 *
 * `closedCount` comes from the `/api/backlog` meta — it is NEVER fabricated.
 * When that count is unavailable the result carries 0 + a warning rather than a
 * guessed number.
 *
 * Storage is best-effort: an unavailable/over-quota `localStorage` degrades to
 * "first visit" / "no comparison" and is never allowed to throw.
 */

import type {
  BacklogDelta,
  BacklogDeltaItem,
  BacklogItem,
  BacklogSnapshot,
  BacklogSnapshotRow,
} from '@aid/contract';
import { storage } from './storage';

/** Per-scope snapshot key prefix in localStorage. */
const SNAPSHOT_PREFIX = 'aid.backlog.';

/** Statuses that count as "closed" for delta classification (§13.7). */
const CLOSED_STATUSES = new Set(['approved', 'rejected', 'deferred']);

/** Optional fields that may ride along on a backlog row beyond the base contract. */
type EnrichedBacklogItem = BacklogItem & {
  type?: string | null;
  area?: string | null;
  priority?: string | null;
};

/** Meta from `/api/backlog` — closedCount MUST come from here, never invented. */
export interface BacklogMeta {
  scope: 'project' | 'plan';
  projectId: string;
  planId?: string | null;
  /** Authoritative closed count from the server; null/undefined → unknown (→ 0 + warning). */
  closedCount?: number | null;
}

/** Build the per-scope snapshot storage key. */
export function backlogSnapshotKey(scopeKey: string): string {
  return SNAPSHOT_PREFIX + scopeKey;
}

function isClosed(status: string | null | undefined): boolean {
  return status != null && CLOSED_STATUSES.has(status.toLowerCase());
}

/** Project a current row onto a `BacklogDeltaItem` with the given change tag. */
function toDeltaItem(
  row: EnrichedBacklogItem,
  changeSince: BacklogDeltaItem['changeSince'],
  prev?: { prevStatus?: string | null; prevPriority?: string | null },
): BacklogDeltaItem {
  return {
    id: row.id,
    title: row.title,
    type: row.type ?? null,
    area: row.area ?? null,
    status: row.status ?? null,
    priority: row.priority ?? null,
    changeSince,
    ...(prev?.prevStatus !== undefined ? { prevStatus: prev.prevStatus } : {}),
    ...(prev?.prevPriority !== undefined ? { prevPriority: prev.prevPriority } : {}),
  };
}

/** Snapshot a current row down to the persisted {@link BacklogSnapshotRow} shape. */
function toSnapshotRow(row: EnrichedBacklogItem): BacklogSnapshotRow {
  return { id: row.id, status: row.status ?? null, priority: row.priority ?? null };
}

/**
 * Diff current backlog rows against a stored snapshot.
 *
 * @param currentRows  the live `/api/backlog` rows
 * @param snapshot     the persisted prior snapshot, or null on first visit
 * @param meta         optional `/api/backlog` meta supplying the authoritative
 *                     `closedCount` and scope identity (never fabricated)
 */
export function buildBacklogDelta(
  currentRows: BacklogItem[],
  snapshot: BacklogSnapshot | null,
  meta?: BacklogMeta,
): BacklogDelta {
  const rows = currentRows as EnrichedBacklogItem[];
  const scope = meta?.scope ?? 'project';
  const projectId = meta?.projectId ?? '';
  const planId = meta?.planId ?? null;
  const openCount = rows.length;

  const warnings: string[] = [];

  // closedCount comes from server meta only — never fabricated.
  let closedCount = 0;
  if (meta?.closedCount != null) {
    closedCount = meta.closedCount;
  } else {
    warnings.push('Počet uzavřených položek není k dispozici (chybí meta z /api/backlog) - zobrazeno 0.');
  }

  // First visit / cleared storage → nothing to compare against.
  if (snapshot === null) {
    return {
      scope,
      projectId,
      planId,
      openCount,
      closedCount,
      firstVisit: true,
      lastSeen: null,
      added: [],
      closed: [],
      priorityChanged: [],
      statusChanged: [],
      warnings,
    };
  }

  // Rows lacking a parseable id can't be keyed reliably — count them and warn.
  const idlessCount = rows.filter((r) => r.id == null).length;
  if (idlessCount > 0) {
    warnings.push(`${idlessCount} řádků bez id - porovnání orientační.`);
  }

  // Index the snapshot by id (id'd rows) and by title (best-effort for id-less).
  const snapById = new Map<string, BacklogSnapshotRow>();
  const snapByTitle = new Map<string, BacklogSnapshotRow>();
  for (const sr of snapshot.rows) {
    if (sr.id != null) snapById.set(sr.id, sr);
  }
  // Title index built lazily below would need titles; snapshot rows carry no
  // title, so id-less current rows can only fall back to "added" (never dropped).

  const added: BacklogDeltaItem[] = [];
  const closed: BacklogDeltaItem[] = [];
  const priorityChanged: BacklogDeltaItem[] = [];
  const statusChanged: BacklogDeltaItem[] = [];

  for (const row of rows) {
    const prior = row.id != null ? snapById.get(row.id) : undefined;

    // New id (or id-less, un-matchable) → added on first sighting (never dropped).
    if (!prior) {
      added.push(toDeltaItem(row, 'added'));
      continue;
    }

    const curStatus = row.status ?? null;
    const prevStatus = prior.status ?? null;
    const curPriority = row.priority ?? null;
    const prevPriority = prior.priority ?? null;

    // Status moved INTO a closed status → closed (carry prevStatus).
    if (isClosed(curStatus) && !isClosed(prevStatus)) {
      closed.push(toDeltaItem(row, 'closed', { prevStatus }));
      continue;
    }

    // Priority differs → priorityChanged (carry prevPriority).
    if (curPriority !== prevPriority) {
      priorityChanged.push(toDeltaItem(row, 'priorityChanged', { prevPriority }));
      continue;
    }

    // Status changed but not into a closed status → statusChanged.
    if (curStatus !== prevStatus) {
      statusChanged.push(toDeltaItem(row, 'statusChanged', { prevStatus }));
      continue;
    }
    // Otherwise unchanged — omitted from the delta lists.
  }

  // Snapshot rows referenced above are unused for title-matching; keep the var
  // reference explicit so the intent (no silent drop path) is documented.
  void snapByTitle;

  return {
    scope,
    projectId,
    planId,
    openCount,
    closedCount,
    firstVisit: false,
    lastSeen: snapshot.lastSeen,
    added,
    closed,
    priorityChanged,
    statusChanged,
    warnings,
  };
}

// ── Snapshot persistence (best-effort, never throws) ─────────────────────────

/**
 * Read the persisted snapshot for a scope, or `null` when absent / storage is
 * unavailable / the blob is unparseable / its version is unrecognized.
 *
 * A snapshot whose `version` is not 1 is discarded (treated as first-visit),
 * never thrown — see the §13.7 "older than version 1 → migration discards" rule.
 */
export function getBacklogSnapshot(scopeKey: string): BacklogSnapshot | null {
  const store = storage();
  if (!store) return null;

  let raw: string | null;
  try {
    raw = store.getItem(backlogSnapshotKey(scopeKey));
  } catch {
    return null;
  }
  if (!raw) return null;

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  if (!isBacklogSnapshotV1(parsed)) return null;
  return parsed;
}

/**
 * Persist the current rows as a snapshot for the scope. Swallows
 * `QuotaExceededError` / disabled-storage with a `console.warn` — never throws.
 */
export function saveBacklogSnapshot(
  scopeKey: string,
  currentRows: BacklogItem[],
  lastSeen: string,
): void {
  const store = storage();
  if (!store) return;

  const snapshot: BacklogSnapshot = {
    version: 1,
    scopeKey,
    lastSeen,
    rows: (currentRows as EnrichedBacklogItem[]).map(toSnapshotRow),
  };

  try {
    store.setItem(backlogSnapshotKey(scopeKey), JSON.stringify(snapshot));
  } catch (err) {
    console.warn(`[backlog-delta] could not persist snapshot "${scopeKey}":`, err);
  }
}

/** Type guard for the version-1 BacklogSnapshot shape. */
function isBacklogSnapshotV1(value: unknown): value is BacklogSnapshot {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { version?: unknown }).version === 1 &&
    Array.isArray((value as { rows?: unknown }).rows) &&
    typeof (value as { lastSeen?: unknown }).lastSeen === 'string'
  );
}
