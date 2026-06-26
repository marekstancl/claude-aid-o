/**
 * Cross-project queue read-route tests (EPIC E-047-3_7, Step 7).
 *
 * Drives the FULLY-WIRED app over a REAL temp fixture `.aid-o` tree (no mocked
 * scanner). The queue surface is READ-ONLY: this test proves both the GET
 * behavior AND — by inspecting the route source — that NO mutation verbs exist
 * (AC4: queue.ts defines ONLY router.get).
 *
 * Covered ACs (queue surface):
 *  - AC4: GET /api/queue?project= is read-only — the route source contains ONLY
 *         `router.get` (no PUT/POST/DELETE/PATCH).
 *  - GET returns QueueEntry[] for a project; 400 on missing project; 404 unknown.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import request from 'supertest';
import type { QueueEntry } from '@aid/contract';
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

beforeEach(async () => {
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-queue-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/queue?project= (Step 7)', () => {
  it('returns the project QueueEntry[]', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/queue?project=vulcan');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);

    const entries: QueueEntry[] = res.body.data;
    const queued = entries.find((e) => e.epicId === 'E-100-1_1');
    expect(queued).toBeTruthy();
    expect(queued!.priority).toBe('critical');
    expect(queued!.status).toBe('queued');
  });

  it('requires a valid project query param (400)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/queue');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for an unknown project', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/queue?project=no-such');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

describe('queue is read-only (Step 7, AC4)', () => {
  it('routes/queue.ts defines ONLY router.get (no PUT/POST/DELETE/PATCH)', async () => {
    const here = dirname(fileURLToPath(import.meta.url));
    const src = await readFile(join(here, 'queue.ts'), 'utf-8');

    // Strip block + line comments so doc references to dropped verbs don't trip
    // the assertion; only real code is inspected.
    const code = src
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/^[ \t]*\/\/.*$/gm, '');

    expect(/router\.get\b/.test(code)).toBe(true);
    expect(/router\.put\b/.test(code)).toBe(false);
    expect(/router\.post\b/.test(code)).toBe(false);
    expect(/router\.delete\b/.test(code)).toBe(false);
    expect(/router\.patch\b/.test(code)).toBe(false);
  });

  it('mutation verbs against the queue surface are not routed (404)', async () => {
    const built = await bootServer(scanRoot);

    const put = await request(built.app).put('/api/queue?project=vulcan').send({ status: 'x' });
    expect(put.status).toBe(404);
    const post = await request(built.app).post('/api/queue/launch').send({});
    expect(post.status).toBe(404);
  });
});
