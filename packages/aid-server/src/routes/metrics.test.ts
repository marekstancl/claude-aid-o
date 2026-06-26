/**
 * Per-EPIC metrics read-route tests (EPIC E-047-3_7, Step 7).
 *
 * Drives the FULLY-WIRED app over a REAL temp fixture `.aid-o` tree (no mocked
 * scanner). The MetricSet is built from the EPIC's latest RunDetail through the
 * un-mocked cache loader.
 *
 * Covered ACs (metrics surface):
 *  - AC5: GET /api/metrics/:projectId/:epicId → MetricSet.
 *  - 400 on a traversal component; 404 on an unknown project/epic.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import type { MetricSet } from '@aid/contract';
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
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-metrics-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/metrics/:projectId/:epicId (Step 7, AC5)', () => {
  it('returns a MetricSet for the EPIC', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/metrics/vulcan/E-100-1_1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const m: MetricSet = res.body.data;
    // Type-valid MetricSet shape (the buildMetrics output).
    expect(typeof m.runCount).toBe('number');
    expect(m.runCount).toBeGreaterThan(0);
    expect(Array.isArray(m.stepDurationsS)).toBe(true);
    expect(m.checkpointRepeats).toBeTruthy();
    expect('CP1' in m.checkpointRepeats).toBe(true);
    expect(Array.isArray(m.warnings)).toBe(true);
    expect(typeof m.gateRuns).toBe('number');
  });

  it('rejects a traversal component with 400 (envelope)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/metrics/vulcan/..%2fetc');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for an unknown epic (envelope)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/metrics/vulcan/E-NOPE');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns 404 for an unknown project (envelope)', async () => {
    const built = await bootServer(scanRoot);
    const res = await request(built.app).get('/api/metrics/no-such/E-100-1_1');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});
