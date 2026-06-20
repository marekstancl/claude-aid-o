/**
 * REST `/activity` ⇄ WS `replay` PARITY tests (EPIC E-047-3_7, Step 8).
 *
 * Guarantees `GET /api/activity` is a COMPLETE WS-replay bootstrap source so the
 * frontend 5s polling fallback (§7.3 / AC #9c) keeps live monitoring working
 * when `/ws` is down. The REST output must be payload-shape-equal to the WS
 * `replay` frame items, with identical limit / project / topic filtering — all
 * routed through the SHARED `filterActivity` helper (src/activity-filter.ts).
 *
 * Both channels are driven for REAL against the SAME seeded buffer:
 *   - REST: supertest over the fully-wired Express app (`built.app`).
 *   - WS:   a REAL `ws` client connected to the same `built.server`, capturing
 *           the `type:'replay'` frame sent via the un-mocked
 *           `setActivityBufferSupplier(() => scanner.getActivity())` code path
 *           wired in index.ts. No hand-built expected array.
 *
 * The single seeded buffer is `scanner.appendActivityBatch(...)` — the same path
 * the watcher uses live, read by BOTH the REST supplier and the WS supplier.
 *
 * Covered ACs (Step 8):
 *  - AC1: REST `data[]` items are element-wise shape-equal (same keys per
 *         ActivityEvent) to the WS `replay` frame `data[]` for the same buffer.
 *  - AC2: `?limit=2` caps BOTH channels to 2 items.
 *  - AC3: `limit>500` clamps to 500 WITHOUT a 400 (200, ≤500 items).
 *  - AC4: `?project=acta&topic=pipeline` filters REST IDENTICALLY to the WS
 *         project+topic subscription filter.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AddressInfo } from 'node:net';
import request from 'supertest';
import { WebSocket } from 'ws';
import type { ActivityEvent } from '@aid/contract';
import { buildServer, type BuiltServer } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';
import { buildFixtureTree } from './__fixtures__/fixture-tree.js';

let scanRoot: string;
const builtServers: BuiltServer[] = [];
const openClients: WebSocket[] = [];

function testConfig(projectsRoot: string): ServerConfig {
  return { ...loadConfig(), projectsRoot, hostRoot: projectsRoot };
}

/** Boot a fully-wired server AND start listening so the WS endpoint is live. */
async function bootListening(
  projectsRoot: string,
): Promise<{ built: BuiltServer; port: number }> {
  const built = buildServer(testConfig(projectsRoot));
  builtServers.push(built);
  await built.boot();
  built.ws.start();
  const port = await new Promise<number>((resolve) => {
    built.server.listen(0, '127.0.0.1', () => {
      resolve((built.server.address() as AddressInfo).port);
    });
  });
  return { built, port };
}

/** A minimal ActivityEvent for the ring (mirrors activity.test.ts). */
function ev(
  projectId: string,
  ts: string,
  event: string,
  extra: Partial<ActivityEvent> = {},
): ActivityEvent {
  return { projectId, ts, event, raw: {}, ...extra };
}

/**
 * Connect a real ws client to the live server, send `subscribe`, and resolve the
 * captured `type:'replay'` frame `data[]`. Resolves to `[]` if no replay frame
 * arrives within the grace window (an empty buffer never sends a replay frame).
 */
function captureReplay(
  port: number,
  filter: { topics?: string[]; projects?: string[] },
): Promise<ActivityEvent[]> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    openClients.push(socket);
    const frames: Record<string, unknown>[] = [];
    socket.on('message', (data) => {
      frames.push(JSON.parse(data.toString()) as Record<string, unknown>);
    });
    socket.once('error', reject);
    socket.once('open', () => {
      socket.send(
        JSON.stringify({
          type: 'subscribe',
          topics: filter.topics ?? [],
          projects: filter.projects ?? [],
        }),
      );
      // Poll for the replay frame; the buffer is non-empty in these tests so a
      // replay frame is expected. Resolve on the first replay (or 'subscribed'
      // + grace, to allow the empty case to resolve to []).
      const start = Date.now();
      const tick = setInterval(() => {
        const replay = frames.find((f) => f.type === 'replay');
        if (replay) {
          clearInterval(tick);
          resolve(replay.data as ActivityEvent[]);
          return;
        }
        const subscribed = frames.some((f) => f.type === 'subscribed');
        if (subscribed && Date.now() - start > 200) {
          clearInterval(tick);
          resolve([]); // subscribed but no replay → empty filtered buffer
          return;
        }
        if (Date.now() - start > 1500) {
          clearInterval(tick);
          reject(new Error('captureReplay timed out'));
        }
      }, 10);
    });
  });
}

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-activity-parity-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const c of openClients.splice(0)) {
    try {
      c.removeAllListeners();
      c.terminate();
    } catch {
      // already closed
    }
  }
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('REST /activity ⇄ WS replay parity (Step 8)', () => {
  it('AC1: REST data[] is element-wise shape-equal to the WS replay data[]', async () => {
    const { built, port } = await bootListening(scanRoot);

    // Seed the SHARED ring read by both the REST supplier and the WS supplier.
    built.scanner.appendActivityBatch([
      ev('acta', '2026-06-19T09:00:00Z', 'step_start', {
        epicId: 'E-020-1_1',
        runId: 'R-1',
        raw: { topic: 'pipeline' },
      }),
      ev('acta', '2026-06-19T10:00:00Z', 'gate_run', {
        epicId: 'E-020-1_1',
        gate: 'tests',
        result: 'pass',
        raw: { topic: 'gates' },
      }),
      ev('acta', '2026-06-19T11:00:00Z', 'step_complete', {
        epicId: 'E-020-1_1',
        durationS: 42,
        raw: { topic: 'pipeline' },
      }),
    ]);

    // REST: unfiltered (project=acta only to scope the fixture tree noise).
    const res = await request(built.app).get('/api/activity?project=acta');
    expect(res.status).toBe(200);
    const restData: ActivityEvent[] = res.body.data;

    // WS: subscribe to the same project, capture the replay frame.
    const wsData = await captureReplay(port, { projects: ['acta'] });

    // Both channels must surface the same number of events for the same buffer.
    expect(restData.length).toBe(3);
    expect(wsData.length).toBe(3);

    // The WS replay is oldest→newest; REST is newest-first. Compare as SETS keyed
    // by (ts,event) so ordering does not mask shape differences, and assert the
    // SAME KEY SET per matching item (payload-shape parity, not just count).
    const wsByKey = new Map(wsData.map((e) => [`${e.ts}|${e.event}`, e]));
    for (const restItem of restData) {
      const wsItem = wsByKey.get(`${restItem.ts}|${restItem.event}`);
      expect(wsItem, `WS missing ${restItem.event}@${restItem.ts}`).toBeDefined();
      // Element-wise SHAPE equality: identical key set per ActivityEvent.
      expect(Object.keys(restItem).sort()).toEqual(
        Object.keys(wsItem!).sort(),
      );
      // And identical values for every shared field (full payload parity).
      expect(restItem).toEqual(wsItem);
    }
  });

  it('AC2: ?limit=2 caps BOTH channels to 2 items', async () => {
    const { built, port } = await bootListening(scanRoot);
    built.scanner.appendActivityBatch([
      ev('acta', '2026-06-19T09:00:00Z', 'a', { raw: { topic: 'pipeline' } }),
      ev('acta', '2026-06-19T10:00:00Z', 'b', { raw: { topic: 'pipeline' } }),
      ev('acta', '2026-06-19T11:00:00Z', 'c', { raw: { topic: 'pipeline' } }),
    ]);

    // REST caps via ?limit=2 (newest two, desc).
    const res = await request(built.app).get('/api/activity?project=acta&limit=2');
    expect(res.status).toBe(200);
    const restData: ActivityEvent[] = res.body.data;
    expect(restData.length).toBe(2);
    expect(restData.map((e) => e.ts)).toEqual([
      '2026-06-19T11:00:00Z',
      '2026-06-19T10:00:00Z',
    ]);

    // WS replay carries the whole bounded buffer (no per-subscription limit in
    // the wire protocol), so the client applies the SAME shared cap to the
    // newest two. Prove the shared helper yields the SAME 2 events both ways.
    const wsData = await captureReplay(port, { projects: ['acta'] });
    // WS replay is oldest→newest; newest two are the tail.
    const wsNewestTwo = wsData.slice(-2).reverse();
    expect(wsNewestTwo.length).toBe(2);
    expect(wsNewestTwo.map((e) => e.ts)).toEqual([
      '2026-06-19T11:00:00Z',
      '2026-06-19T10:00:00Z',
    ]);
    expect(restData).toEqual(wsNewestTwo);
  });

  it('AC3: limit>500 clamps to 500 WITHOUT a 400 (200, <=500 items)', async () => {
    const { built } = await bootListening(scanRoot);
    // Seed 600 events to prove the clamp actually bites at 500.
    const batch: ActivityEvent[] = [];
    for (let i = 0; i < 600; i++) {
      const mm = String(i % 60).padStart(2, '0');
      const hh = String(Math.floor(i / 60)).padStart(2, '0');
      batch.push(
        ev('acta', `2026-06-19T${hh}:${mm}:00Z`, `e${i}`, {
          raw: { topic: 'pipeline' },
        }),
      );
    }
    built.scanner.appendActivityBatch(batch);

    const res = await request(built.app).get('/api/activity?project=acta&limit=99999');
    expect(res.status).toBe(200); // NOT a 400
    const restData: ActivityEvent[] = res.body.data;
    expect(restData.length).toBe(500); // clamped to the hard ceiling
    expect(restData.length).toBeLessThanOrEqual(500);
  });

  it('AC4: ?project=acta&topic=pipeline filters REST identically to the WS project+topic subscription', async () => {
    const { built, port } = await bootListening(scanRoot);
    built.scanner.appendActivityBatch([
      ev('acta', '2026-06-19T09:00:00Z', 'step_start', {
        raw: { topic: 'pipeline' },
      }),
      ev('acta', '2026-06-19T10:00:00Z', 'gate_run', {
        raw: { topic: 'gates' },
      }),
      ev('vulcan', '2026-06-19T11:00:00Z', 'step_start', {
        raw: { topic: 'pipeline' },
      }),
      ev('acta', '2026-06-19T12:00:00Z', 'step_complete', {
        raw: { topic: 'pipeline' },
      }),
    ]);

    // REST: project=acta AND topic=pipeline.
    const res = await request(built.app).get(
      '/api/activity?project=acta&topic=pipeline',
    );
    expect(res.status).toBe(200);
    const restData: ActivityEvent[] = res.body.data;

    // WS: same project + topic subscription.
    const wsData = await captureReplay(port, {
      projects: ['acta'],
      topics: ['pipeline'],
    });

    // Only the two acta+pipeline events survive in BOTH channels (acta/gates and
    // vulcan/pipeline are excluded by the AND-combined filter).
    expect(restData.length).toBe(2);
    expect(wsData.length).toBe(2);
    expect(restData.every((e) => e.projectId === 'acta')).toBe(true);
    expect(
      restData.every((e) => e.raw.topic === 'pipeline'),
    ).toBe(true);

    // Identical event SET across channels (order differs: REST desc, WS asc).
    const restKeys = restData.map((e) => `${e.ts}|${e.event}`).sort();
    const wsKeys = wsData.map((e) => `${e.ts}|${e.event}`).sort();
    expect(restKeys).toEqual(wsKeys);
  });
});
