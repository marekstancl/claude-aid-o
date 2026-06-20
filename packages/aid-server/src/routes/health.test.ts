/**
 * Bootstrap + health-route tests (EPIC E-047-3_7, Step 4).
 *
 * Drives the Express app via supertest (no real port). Covers:
 *   - AC1: GET /api/health → 200 with { ok:true, data:{ status:'ok', ts } }.
 *   - AC2: GET /api/no-such-route → 404 with { ok:false, error:{ code:'NOT_FOUND' } }
 *          from the /api/* catch-all (before the static GUI fallback).
 *   - AC4: buildServer boots against an EMPTY AID_PROJECTS_ROOT without crashing
 *          and the health route still responds.
 */

import { describe, it, expect, afterEach } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import { createApp, buildServer, type BuiltServer } from '../index.js';
import { loadConfig, type ServerConfig } from '../config.js';

/** A minimal config pointing at an arbitrary (here unused) projects root. */
function testConfig(projectsRoot: string): ServerConfig {
  return { ...loadConfig(), projectsRoot, hostRoot: projectsRoot };
}

describe('health route + bootstrap (Step 4)', () => {
  const builtServers: BuiltServer[] = [];
  const tempDirs: string[] = [];

  afterEach(async () => {
    for (const b of builtServers.splice(0)) await b.shutdown();
    for (const d of tempDirs.splice(0)) await rm(d, { recursive: true, force: true });
  });

  it('AC1 — GET /api/health returns 200 with { ok, data:{ status, ts } }', async () => {
    const app = createApp(testConfig('/tmp/does-not-matter'), undefined as never);
    const res = await request(app).get('/api/health');

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data.status).toBe('ok');
    expect(typeof res.body.data.ts).toBe('string');
    // ts is an ISO-8601 timestamp that round-trips through Date.
    expect(Number.isNaN(Date.parse(res.body.data.ts))).toBe(false);
  });

  it('AC2 — GET /api/no-such-route returns 404 with code NOT_FOUND from the catch-all', async () => {
    const app = createApp(testConfig('/tmp/does-not-matter'), undefined as never);
    const res = await request(app).get('/api/no-such-route');

    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('AC2 — the /api/* catch-all also covers non-GET methods', async () => {
    const app = createApp(testConfig('/tmp/does-not-matter'), undefined as never);
    const res = await request(app).post('/api/whatever').send({});
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('AC4 — buildServer boots against an EMPTY projects root and health still responds', async () => {
    const emptyRoot = await mkdtemp(join(tmpdir(), 'aid-empty-root-'));
    tempDirs.push(emptyRoot);

    const built = buildServer(testConfig(emptyRoot));
    builtServers.push(built);

    // Boot must not throw on an empty root (no projects to discover/watch).
    await expect(built.boot()).resolves.toBeUndefined();
    expect(built.watcher.size).toBe(0);

    const res = await request(built.app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('ok');
  });
});
