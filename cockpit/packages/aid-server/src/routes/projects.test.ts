/**
 * Cross-project read-route tests (EPIC E-047-3_7, Step 5).
 *
 * Drives the FULLY-WIRED Express app (via {@link buildServer}.app + supertest,
 * no real port) over a REAL temp fixture `.aid-o` tree — the scanner is NOT
 * mocked. A genuine scan exercises discovery + denylist classification so the
 * "broken-* absent" and "empty-root" assertions actually mean something
 * (Phase-2 lesson).
 *
 * Covered ACs (projects surface):
 *  - AC1: GET /api/projects → 200, data is an array, active/running first,
 *         meta.scannedAt present, broken-* fixtures ABSENT.
 *  - AC2: GET /api/projects/<id> → ProjectDetail (epics/queue/recentActivity).
 *  - AC5: invalid projectId (`..`) → 400; non-existent project → 404 (envelope).
 *  - AC6: empty AID_PROJECTS_ROOT → data:[].
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
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
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-projects-'));
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/projects (Step 5, AC1)', () => {
  it('returns 200 with an array, active/running first, meta.scannedAt, broken-* ABSENT', async () => {
    await buildFixtureTree(scanRoot);
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/projects');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);

    const ids: string[] = res.body.data.map((p: { id: string }) => p.id);
    // The two real projects are discovered; both broken dirs are denylisted.
    expect(ids).toContain('vulcan');
    expect(ids).toContain('cicero');
    expect(ids.some((id) => id.includes('broken'))).toBe(false);

    // meta carries the cross-project scan marker.
    expect(typeof res.body.meta.scannedAt).toBe('string');
    expect(Number.isNaN(Date.parse(res.body.meta.scannedAt))).toBe(false);
    expect(Array.isArray(res.body.meta.partialProjects)).toBe(true);

    // vulcan has a live EXECUTE run → sorts before cicero (no active run).
    expect(ids.indexOf('vulcan')).toBeLessThan(ids.indexOf('cicero'));
  });
});

describe('GET /api/projects/:projectId (Step 5, AC2)', () => {
  it('returns a ProjectDetail with epics, queue, and recentActivity', async () => {
    await buildFixtureTree(scanRoot);
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/projects/vulcan');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const d = res.body.data;
    expect(d.id).toBe('vulcan');
    expect(Array.isArray(d.epics)).toBe(true);
    expect(d.epics.length).toBeGreaterThan(0);
    expect(Array.isArray(d.queue)).toBe(true);
    expect(Array.isArray(d.recentActivity)).toBe(true);
    // ProjectDetail-specific aggregate shapes are present (type-valid, not faked).
    expect(d.aggregateAudit).toBeTruthy();
    expect(d.auditTrend.scope).toBe('project');

    // The queued EPIC from config/queue.yaml is surfaced (camelCased).
    const queued = d.queue.find((q: { epicId: string }) => q.epicId === 'E-100-1_1');
    expect(queued).toBeTruthy();
    expect(queued.priority).toBe('critical');
  });
});

describe('GET /api/projects/:projectId/epics (Step 5)', () => {
  it('returns an EpicSummary[] sorted active first', async () => {
    await buildFixtureTree(scanRoot);
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/projects/vulcan/epics');
    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.data)).toBe(true);
    const summaries = res.body.data as { id: string; status: string; runsTotal: number }[];
    expect(summaries.length).toBeGreaterThan(0);
    const e100 = summaries.find((s) => s.id === 'E-100-1_1');
    expect(e100).toBeTruthy();
    expect(e100!.runsTotal).toBeGreaterThan(0);
  });
});

describe('path validation + not-found (Step 5, AC5)', () => {
  it('rejects a traversal projectId with 400 (envelope)', async () => {
    await buildFixtureTree(scanRoot);
    const built = await bootServer(scanRoot);

    // `..%2f` decodes to `../`, reaching the handler as a param value that still
    // carries the traversal — the route guard rejects it as 400 (CWE-22).
    const res = await request(built.app).get('/api/projects/..%2fetc');
    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for a non-existent project (envelope)', async () => {
    await buildFixtureTree(scanRoot);
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/projects/no-such-project');
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

describe('empty projects root (Step 5, AC6)', () => {
  it('boots on an EMPTY root and GET /api/projects returns data:[]', async () => {
    // scanRoot is freshly created and empty (no projects).
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/projects');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });
});
