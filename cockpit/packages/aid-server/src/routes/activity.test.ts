/**
 * Merged-activity feed route tests (EPIC E-047-3_7, Step 7).
 *
 * Drives the FULLY-WIRED app over a REAL temp fixture `.aid-o` tree (no mocked
 * scanner). The activity ring is seeded with REAL {@link ActivityEvent}s via the
 * cache's public `appendActivityBatch` (the same path the watcher uses live), so
 * the route reads through the un-mocked cache supplier wired in index.ts.
 *
 * Covered ACs (activity surface):
 *  - AC3: GET /api/activity?project=acta → ONLY acta events, time-sorted desc,
 *         capped at limit.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import type { ActivityEvent } from '@aid/contract';
import { buildServer, type BuiltServer } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';
import { buildFixtureTree } from './__fixtures__/fixture-tree.js';

let scanRoot: string;
const builtServers: BuiltServer[] = [];

function testConfig(projectsRoot: string): ServerConfig {
  return { ...loadConfig(), projectsRoot, hostRoot: projectsRoot };
}

async function bootServer(projectsRoot: string): Promise<BuiltServer> {
  const built = buildServer(testConfig(projectsRoot));
  builtServers.push(built);
  await built.boot();
  return built;
}

/** A minimal ActivityEvent for the ring. */
function ev(
  projectId: string,
  ts: string,
  event: string,
  extra: Partial<ActivityEvent> = {},
): ActivityEvent {
  return { projectId, ts, event, raw: {}, ...extra };
}

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-activity-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/activity (Step 7, AC3)', () => {
  it('returns ONLY the requested project events, time-sorted desc, capped at limit', async () => {
    const built = await bootServer(scanRoot);

    // Seed the merged ring with interleaved acta + vulcan events (out of order).
    built.scanner.appendActivityBatch([
      ev('vulcan', '2026-06-19T10:00:00Z', 'fsm_transition'),
      ev('acta', '2026-06-19T09:00:00Z', 'step_start', { epicId: 'E-020-1_1' }),
      ev('acta', '2026-06-19T11:00:00Z', 'gate_run', { epicId: 'E-020-1_1', gate: 'tests' }),
      ev('vulcan', '2026-06-19T12:00:00Z', 'gate_run'),
      ev('acta', '2026-06-19T10:30:00Z', 'step_complete', { epicId: 'E-020-1_1' }),
    ]);

    const res = await request(built.app).get('/api/activity?project=acta');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const events: ActivityEvent[] = res.body.data;
    // ONLY acta events.
    expect(events.length).toBe(3);
    expect(events.every((e) => e.projectId === 'acta')).toBe(true);

    // Time-sorted DESCENDING (newest first).
    const ts = events.map((e) => e.ts);
    expect(ts).toEqual([
      '2026-06-19T11:00:00Z',
      '2026-06-19T10:30:00Z',
      '2026-06-19T09:00:00Z',
    ]);
  });

  it('caps the result at the limit query param (newest N)', async () => {
    const built = await bootServer(scanRoot);
    built.scanner.appendActivityBatch([
      ev('acta', '2026-06-19T09:00:00Z', 'a'),
      ev('acta', '2026-06-19T10:00:00Z', 'b'),
      ev('acta', '2026-06-19T11:00:00Z', 'c'),
    ]);

    const res = await request(built.app).get('/api/activity?project=acta&limit=2');
    expect(res.status).toBe(200);
    const events: ActivityEvent[] = res.body.data;
    expect(events.length).toBe(2);
    // The newest two, in desc order.
    expect(events.map((e) => e.ts)).toEqual([
      '2026-06-19T11:00:00Z',
      '2026-06-19T10:00:00Z',
    ]);
  });

  it('filters by topic (matches raw.topic or the event name)', async () => {
    const built = await bootServer(scanRoot);
    built.scanner.appendActivityBatch([
      ev('acta', '2026-06-19T09:00:00Z', 'gate_run', { raw: { topic: 'gates' } }),
      ev('acta', '2026-06-19T10:00:00Z', 'fsm_transition', { raw: { topic: 'pipeline' } }),
    ]);

    const res = await request(built.app).get('/api/activity?project=acta&topic=gates');
    expect(res.status).toBe(200);
    const events: ActivityEvent[] = res.body.data;
    expect(events.length).toBe(1);
    expect(events[0].event).toBe('gate_run');
  });

  it('rejects a traversal project value with 400', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/activity?project=..%2fetc');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });
});
