/**
 * Tests for buildBacklogDelta (§13.7) — client-side backlog diffing.
 *
 * Runs under the `dom` vitest project (jsdom + globals), so `localStorage` is
 * available for the snapshot-persistence round-trip tests.
 *
 * Coverage:
 *   - firstVisit branch (snapshot === null → empty lists)
 *   - added (new id not in snapshot)
 *   - closed (status moved to a closed status, carries prevStatus)
 *   - priorityChanged (priority differs, carries prevPriority)
 *   - statusChanged (status changed but NOT to a closed status, carries prevStatus)
 *   - closedCount comes from meta, never fabricated (0 + warning when absent)
 *   - id-less rows are treated as added (never dropped) + warning
 *   - snapshot persistence round-trip + version migration discard
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type {
  BacklogItem,
  BacklogSnapshot,
  BacklogSnapshotRow,
} from '@aid/contract';
import {
  buildBacklogDelta,
  getBacklogSnapshot,
  saveBacklogSnapshot,
  backlogSnapshotKey,
  type BacklogMeta,
} from './backlog-delta';

// Allow priority on test rows (the base BacklogItem omits it; the delta reads it best-effort).
type Row = BacklogItem & { priority?: string | null };

function row(partial: Partial<Row>): Row {
  return {
    projectId: 'wan',
    id: null,
    title: 'untitled',
    status: 'open',
    raw: '',
    ...partial,
  };
}

function snapshot(rows: BacklogSnapshotRow[], lastSeen = '2026-06-01T00:00:00Z'): BacklogSnapshot {
  return { version: 1, scopeKey: 'p:wan', lastSeen, rows };
}

const META: BacklogMeta = { scope: 'project', projectId: 'wan', closedCount: 3 };

describe('buildBacklogDelta — firstVisit branch', () => {
  it('snapshot === null → firstVisit:true with four empty lists', () => {
    const rows = [row({ id: 'B-1', title: 'one' }), row({ id: 'B-2', title: 'two' })];
    const delta = buildBacklogDelta(rows, null, META);

    expect(delta.firstVisit).toBe(true);
    expect(delta.lastSeen).toBeNull();
    expect(delta.added).toEqual([]);
    expect(delta.closed).toEqual([]);
    expect(delta.priorityChanged).toEqual([]);
    expect(delta.statusChanged).toEqual([]);
    expect(delta.openCount).toBe(2);
    expect(delta.closedCount).toBe(3); // from meta, not fabricated
  });
});

describe('buildBacklogDelta — classification', () => {
  it('new id absent from snapshot → added', () => {
    const snap = snapshot([{ id: 'B-1', status: 'open', priority: 'P2' }]);
    const rows = [
      row({ id: 'B-1', title: 'one', status: 'open', priority: 'P2' }),
      row({ id: 'B-2', title: 'two', status: 'open', priority: 'P3' }),
    ];
    const delta = buildBacklogDelta(rows, snap, META);

    expect(delta.firstVisit).toBe(false);
    expect(delta.added.map((i) => i.id)).toEqual(['B-2']);
    expect(delta.closed).toEqual([]);
    expect(delta.lastSeen).toBe('2026-06-01T00:00:00Z');
  });

  it('status moved to approved → closed, carrying prevStatus', () => {
    const snap = snapshot([{ id: 'B-1', status: 'open', priority: 'P2' }]);
    const rows = [row({ id: 'B-1', title: 'one', status: 'approved', priority: 'P2' })];
    const delta = buildBacklogDelta(rows, snap, META);

    expect(delta.closed).toHaveLength(1);
    expect(delta.closed[0].id).toBe('B-1');
    expect(delta.closed[0].changeSince).toBe('closed');
    expect(delta.closed[0].prevStatus).toBe('open');
    expect(delta.statusChanged).toEqual([]);
  });

  it.each(['approved', 'rejected', 'deferred'])(
    'status moved to %s → closed',
    (closedStatus) => {
      const snap = snapshot([{ id: 'B-9', status: 'in_progress', priority: 'P1' }]);
      const rows = [row({ id: 'B-9', title: 'nine', status: closedStatus, priority: 'P1' })];
      const delta = buildBacklogDelta(rows, snap, META);
      expect(delta.closed.map((i) => i.id)).toEqual(['B-9']);
    },
  );

  it('priority differs → priorityChanged, carrying prevPriority', () => {
    const snap = snapshot([{ id: 'B-1', status: 'open', priority: 'P3' }]);
    const rows = [row({ id: 'B-1', title: 'one', status: 'open', priority: 'P1' })];
    const delta = buildBacklogDelta(rows, snap, META);

    expect(delta.priorityChanged).toHaveLength(1);
    expect(delta.priorityChanged[0].id).toBe('B-1');
    expect(delta.priorityChanged[0].changeSince).toBe('priorityChanged');
    expect(delta.priorityChanged[0].prevPriority).toBe('P3');
    expect(delta.priorityChanged[0].priority).toBe('P1');
    expect(delta.statusChanged).toEqual([]);
  });

  it('status changed but NOT to a closed status → statusChanged', () => {
    const snap = snapshot([{ id: 'B-1', status: 'open', priority: 'P2' }]);
    const rows = [row({ id: 'B-1', title: 'one', status: 'in_progress', priority: 'P2' })];
    const delta = buildBacklogDelta(rows, snap, META);

    expect(delta.statusChanged).toHaveLength(1);
    expect(delta.statusChanged[0].changeSince).toBe('statusChanged');
    expect(delta.statusChanged[0].prevStatus).toBe('open');
    expect(delta.closed).toEqual([]);
    expect(delta.priorityChanged).toEqual([]);
  });

  it('unchanged row appears in none of the lists', () => {
    const snap = snapshot([{ id: 'B-1', status: 'open', priority: 'P2' }]);
    const rows = [row({ id: 'B-1', title: 'one', status: 'open', priority: 'P2' })];
    const delta = buildBacklogDelta(rows, snap, META);

    expect(delta.added).toEqual([]);
    expect(delta.closed).toEqual([]);
    expect(delta.priorityChanged).toEqual([]);
    expect(delta.statusChanged).toEqual([]);
  });
});

describe('buildBacklogDelta — closedCount + edge cases', () => {
  it('closedCount missing from meta → 0 + warning (never fabricated)', () => {
    const delta = buildBacklogDelta([row({ id: 'B-1' })], null, {
      scope: 'project',
      projectId: 'wan',
    });
    expect(delta.closedCount).toBe(0);
    expect(delta.warnings.some((w) => w.includes('uzavřených'))).toBe(true);
  });

  it('id-less rows are treated as added (never dropped) + orientation warning', () => {
    const snap = snapshot([{ id: 'B-1', status: 'open', priority: 'P2' }]);
    const rows = [
      row({ id: null, title: 'mystery', status: 'open' }),
      row({ id: 'B-1', title: 'one', status: 'open', priority: 'P2' }),
    ];
    const delta = buildBacklogDelta(rows, snap, META);

    expect(delta.added.map((i) => i.title)).toContain('mystery');
    expect(delta.warnings.some((w) => w.includes('bez id'))).toBe(true);
  });
});

describe('snapshot persistence', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it('save → getBacklogSnapshot round-trips the rows', () => {
    const rows = [
      row({ id: 'B-1', status: 'open', priority: 'P2' }),
      row({ id: 'B-2', status: 'approved', priority: 'P1' }),
    ];
    saveBacklogSnapshot('p:wan', rows, '2026-06-21T10:00:00Z');

    const loaded = getBacklogSnapshot('p:wan');
    expect(loaded).not.toBeNull();
    expect(loaded?.version).toBe(1);
    expect(loaded?.lastSeen).toBe('2026-06-21T10:00:00Z');
    expect(loaded?.rows).toEqual([
      { id: 'B-1', status: 'open', priority: 'P2' },
      { id: 'B-2', status: 'approved', priority: 'P1' },
    ]);
  });

  it('absent snapshot → null', () => {
    expect(getBacklogSnapshot('p:never')).toBeNull();
  });

  it('snapshot of unrecognized version is discarded → null (first visit)', () => {
    localStorage.setItem(
      backlogSnapshotKey('p:wan'),
      JSON.stringify({ version: 0, scopeKey: 'p:wan', lastSeen: 'x', rows: [] }),
    );
    expect(getBacklogSnapshot('p:wan')).toBeNull();
  });

  it('unparseable snapshot blob → null (never throws)', () => {
    localStorage.setItem(backlogSnapshotKey('p:wan'), '{not json');
    expect(getBacklogSnapshot('p:wan')).toBeNull();
  });
});
