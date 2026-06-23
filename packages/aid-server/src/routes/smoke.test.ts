/**
 * Integration smoke test: boot the full server and ping all 9 endpoints.
 * (EPIC E-047-3_7, Phase 3, IMP-141).
 *
 * Verifies that the server can boot over a fixture tree and all cross-project
 * routes respond without 500 errors. Tests the complete surface:
 *   1. /api/health
 *   2. /api/projects
 *   3. /api/epics/:projectId/:epicId
 *   4. /api/file/:projectId/:epicId/:runId/files/*
 *   5. /api/compliance
 *   6. /api/backlog?project=<id>
 *   7. /api/activity
 *   8. /api/queue?project=<id>
 *   9. /api/metrics/:projectId/:epicId
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import supertest from 'supertest';
import { buildFixtureTree } from './__fixtures__/fixture-tree.js';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';

let tempDir: string;
let server: BuiltServer;

beforeAll(async () => {
  // Create a temporary directory for the fixture tree.
  tempDir = await mkdtemp(join(tmpdir(), 'aid-smoke-test-'));

  // Build the fixture tree with multiple projects and runs.
  await buildFixtureTree(tempDir);

  // Build the server with the fixture tree as projectsRoot.
  const config: ServerConfig = {
    port: 3911,
    host: '127.0.0.1',
    projectsRoot: tempDir,
    hostRoot: tempDir,
    corsOrigins: '*',
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 90_000,
    scanTtlMs: 600_000,
    activityBufferSize: 500,
  };

  server = buildServer(config);
  await server.boot();
});

afterAll(async () => {
  await server.shutdown();
  await rm(tempDir, { recursive: true, force: true });
});

describe('Smoke test: all 9 routes', () => {
  it('1. GET /api/health returns 200', async () => {
    const res = await supertest(server.app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveProperty('status', 'ok');
  });

  it('2. GET /api/projects returns 200 with project list', async () => {
    const res = await supertest(server.app).get('/api/projects');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data.length).toBeGreaterThan(0);
  });

  it('3. GET /api/epics/:projectId/:epicId returns 200', async () => {
    const res = await supertest(server.app).get('/api/epics/vulcan/E-100-1_1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toBeDefined();
  });

  it('4. GET /epics/:p/:e/runs/:r/file?name= serves real root AND nested artifacts (200)', async () => {
    // The real route is /api/epics/:p/:e/runs/:r/file?name=… (not /api/file/…).
    // The DONE run (R-E100-1) has both a root fsm-state.yaml and a nested
    // gates/gates_report.json — BOTH must serve 200 (MED-4: no "200-or-404").

    // Root-level artifact → MUST be 200.
    const rootRes = await supertest(server.app).get(
      '/api/epics/vulcan/E-100-1_1/runs/R-E100-1/file?name=fsm-state.yaml',
    );
    expect(rootRes.status).toBe(200);
    expect(rootRes.body.ok).toBe(true);
    expect(rootRes.body.data).toBeDefined();

    // Nested artifact (HIGH-3) → MUST be 200, content present.
    const nestedRes = await supertest(server.app).get(
      '/api/epics/vulcan/E-100-1_1/runs/R-E100-1/file?name=gates/gates_report.json',
    );
    expect(nestedRes.status).toBe(200);
    expect(nestedRes.body.ok).toBe(true);
    expect(nestedRes.body.data?.content).toBeDefined();
  });

  it('5. GET /api/compliance returns 200', async () => {
    const res = await supertest(server.app).get('/api/compliance');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toBeDefined();
  });

  it('6. GET /api/backlog?project=vulcan returns 200', async () => {
    const res = await supertest(server.app).get('/api/backlog?project=vulcan');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('7. GET /api/activity returns 200', async () => {
    const res = await supertest(server.app).get('/api/activity');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('8. GET /api/queue?project=vulcan returns 200', async () => {
    const res = await supertest(server.app).get('/api/queue?project=vulcan');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
  });

  it('9. GET /api/metrics/:projectId/:epicId returns 200', async () => {
    const res = await supertest(server.app).get('/api/metrics/vulcan/E-100-1_1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toBeDefined();
  });
});
