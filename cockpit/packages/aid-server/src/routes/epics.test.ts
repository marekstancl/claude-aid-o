/**
 * Cross-project EPIC + run read-route tests (EPIC E-047-3_7, Step 5).
 *
 * Drives the FULLY-WIRED app over a REAL temp fixture `.aid-o` tree (no mocked
 * scanner) so EpicDetail/RunDetail assembly is exercised end-to-end through the
 * Phase-2 cache loader.
 *
 * Covered ACs (epics/runs surface):
 *  - AC3: GET /api/epics/<p>/<e> → full EpicDetail (spec, runs, latest RunDetail,
 *         metrics, auditTrend); GET /.../runs/<r> → RunDetail (state, steps,
 *         checkpoints, gates).
 *  - AC4: a legacy run yields format:'legacy' with empty checkpoints/gates and
 *         NO thrown error.
 *  - AC5: a traversal path component (`..`) → 400; a non-existent epic → 404.
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
  scanRoot = await mkdtemp(join(tmpdir(), 'aid-routes-epics-'));
  await buildFixtureTree(scanRoot);
});

afterEach(async () => {
  for (const b of builtServers.splice(0)) await b.shutdown();
  await rm(scanRoot, { recursive: true, force: true });
});

describe('GET /api/epics/:projectId/:epicId (Step 5, AC3)', () => {
  it('returns a full EpicDetail (spec, runs, latest RunDetail, metrics, auditTrend)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/epics/vulcan/E-100-1_1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const d = res.body.data;
    expect(d.id).toBe('E-100-1_1');
    // spec parsed from tasks/<id>.md (title from H1 / frontmatter).
    expect(d.spec.epicId).toBe('E-100-1_1');
    expect(d.spec.title).toContain('Cockpit MVP');

    // runs[] (cheap summaries) + latest full RunDetail.
    expect(Array.isArray(d.runs)).toBe(true);
    expect(d.runs.length).toBeGreaterThan(0);
    expect(d.latest).toBeTruthy();
    expect(d.latest.runId).toBe('R-E100-1');
    expect(d.latest.format).toBe('v3');
    expect(d.latest.state).toBe('EXECUTE');

    // metrics + epic-scope audit trend present and type-valid.
    expect(d.metrics.runCount).toBeGreaterThan(0);
    expect(d.auditTrend.scope).toBe('epic');
    // The DONE-run audit score (91) is captured as a real trend point.
    const scored = d.auditTrend.points.filter((p: { score: number | null }) => p.score !== null);
    expect(scored.some((p: { score: number }) => p.score === 91)).toBe(true);
  });
});

describe('GET /api/epics/:projectId/:epicId/runs/:runId (Step 5, AC3)', () => {
  it('returns a RunDetail with state, steps, checkpoints, and gates', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/epics/vulcan/E-100-1_1/runs/R-E100-1');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const d = res.body.data;
    expect(d.projectId).toBe('vulcan');
    expect(d.epicId).toBe('E-100-1_1');
    expect(d.runId).toBe('R-E100-1');
    expect(d.format).toBe('v3');
    expect(d.state).toBe('EXECUTE');

    // steps derived from verify files; checkpoints + gates assembled.
    expect(Array.isArray(d.steps)).toBe(true);
    expect(d.steps.length).toBeGreaterThan(0);
    expect(Array.isArray(d.checkpoints)).toBe(true);
    expect(d.checkpoints.length).toBeGreaterThan(0);
    expect(Array.isArray(d.gates)).toBe(true);
    // bats_fsm + plan_diff(skip) → two gate entries.
    const gateNames = d.gates.map((g: { gate: string }) => g.gate);
    expect(gateNames).toContain('bats_fsm');
    expect(gateNames).toContain('plan_diff');
  });
});

describe('legacy run handling (Step 5, AC4)', () => {
  it('yields format:legacy with empty checkpoints/gates and no thrown error', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get(
      '/api/epics/cicero/E-050-1_1/runs/run_20260224_115f',
    );
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const d = res.body.data;
    expect(d.format).toBe('legacy');
    // No gates_report.json on a legacy run → gates is empty.
    expect(d.gates).toEqual([]);
    // The builder still emits the standard CP rows, but a legacy run dispatched
    // none of them: every checkpoint is un-dispatched with a null verdict (no
    // fabricated pass/fail) — and nothing threw.
    for (const cp of d.checkpoints) {
      expect(cp.verdict).toBeNull();
    }
    expect(d.checkpoints.every((cp: { dispatched: boolean }) => cp.dispatched === false)).toBe(
      true,
    );
  });
});

describe('path validation + not-found (Step 5, AC5)', () => {
  it('rejects a traversal epicId with 400 (envelope)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/epics/vulcan/..%2fetc');
    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for a non-existent epic (envelope)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/epics/vulcan/E-NOPE');
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns 404 for a non-existent run (envelope)', async () => {
    const built = await bootServer(scanRoot);

    const res = await request(built.app).get('/api/epics/vulcan/E-100-1_1/runs/R-NOPE');
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});
