/**
 * Cross-project backlog read-route tests (EPIC E-047-3_7, Step 7).
 *
 * Drives the FULLY-WIRED app over a REAL temp fixture `.aid-o` tree (no mocked
 * scanner). The `wan` fixture carries a backlog.md whose DECLARED frontmatter
 * counter DISAGREES with the actual rows — proving the route reports the ACTUAL
 * counts + a warning, never the fabricated declared number (§5.7 honesty).
 *
 * Covered ACs (backlog surface):
 *  - AC2: GET /api/backlog?project=wan → current BacklogItem[] +
 *         meta.openCount / meta.closedCount.
 *  - AC2: the stale-counter fixture yields closedCount:1 (the REAL count) + a
 *         warning (NOT the declared closed_count:9).
 *  - AC2: GET /api/backlog-delta → 404 (endpoint deliberately absent).
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
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
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-backlog-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/backlog?project= (Step 7, AC2)', () => {
  it('returns current BacklogItem[] + meta.openCount/closedCount', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/backlog?project=wan');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);

    // 3 rows: IMP-1 (open), BUG-2 (open), DOC-3 (done).
    expect(res.body.data.length).toBe(3);
    const ids = res.body.data.map((b: { id: string }) => b.id);
    expect(ids).toContain('IMP-1');
    expect(ids).toContain('DOC-3');

    // Each item carries the contract BacklogItem shape.
    const first = res.body.data[0];
    expect(first.projectId).toBe('wan');
    expect(typeof first.raw).toBe('string');
    expect('status' in first).toBe(true);

    // Counts are ABSOLUTE and derived from the ACTUAL rows.
    expect(res.body.meta.openCount).toBe(2);
    expect(res.body.meta.closedCount).toBe(1);
  });

  it('a STALE counter yields the REAL closedCount + a warning (never fabricated)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/backlog?project=wan');
    expect(res.status).toBe(200);

    // The fixture frontmatter declares closed_count:9 / open_count:1, but the
    // real rows are open:2 / closed:1 — the REAL counts MUST win.
    expect(res.body.meta.closedCount).toBe(1); // NOT 9
    expect(res.body.meta.openCount).toBe(2); // NOT 1

    const warnings: string[] = res.body.meta.warnings;
    expect(Array.isArray(warnings)).toBe(true);
    expect(warnings.length).toBeGreaterThan(0);
    // The warning names the stale declared counter.
    expect(warnings.some((w) => w.includes('9') || w.toLowerCase().includes('stale'))).toBe(true);
  });

  it('requires a valid project query param (400)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/backlog');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for an unknown project', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/backlog?project=no-such');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

describe('no backlog-delta endpoint (Step 7, AC2)', () => {
  it('GET /api/backlog-delta → 404 (endpoint absent — delta is out of scope)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/backlog-delta?project=wan');
    // Falls through to the /api/* catch-all 404.
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });
});
