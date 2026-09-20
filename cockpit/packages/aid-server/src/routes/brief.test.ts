/**
 * Brief routes integration tests — spec §7.4, §13.4 (EPIC E-047-4_7 Step 4).
 *
 * Boots the full server over a REAL on-disk fixture tree (no mocking) and drives
 * the three brief endpoints via supertest, plus a plan-scope fixture mirroring
 * P046's tier-2/tier-3 derived membership (MF1, AC #5).
 *
 * AC matrix (route surface):
 *   AC1  — GET /api/brief → scope:"infra", probability {null,null}, sorted items
 *   AC2  — value===null && source===null on every scope
 *   AC3  — no ?since= → sinceLastSeen {since:null, items:[]} (first visit)
 *   AC5  — plan scope for a P046-like plan (derived members) → NON-EMPTY brief
 *   AC15 — read-only: GET writes nothing (mtimes unchanged after the request)
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtemp, rm, mkdir, writeFile, stat, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import supertest from 'supertest';
import { buildFixtureTree } from './__fixtures__/fixture-tree.js';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';

let tempDir: string;
let server: BuiltServer;

/**
 * Add an aid-orchestrator-like project with a P046 plan whose three member EPICs
 * carry NO plan_path: one resolves at tier-2 (frontmatter plan_ref:P046), two at
 * tier-3 (id-derived E-046-* → P046, matched to a real plans/P046-*.md). Mirrors
 * the MF1 grounding fixture so the plan-scope brief is non-empty (AC #5).
 */
async function addP046Project(root: string): Promise<void> {
  const aido = join(root, 'aid-orchestrator', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'plans'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });

  // The plan file (id-derived tier-3 needs a real plans/P046-*.md to exist).
  await writeFile(
    join(aido, 'plans', 'P046.md'),
    `---\nplan_id: P046\ntitle: Cockpit MVP\n---\n\n# P046 — Cockpit MVP\n\nThe plan body.\n`,
    'utf-8',
  );

  // Tier-2 member: active task carries plan_ref:P046 (NO plan_path).
  await writeFile(
    join(aido, 'tasks', 'E-046-3_3.md'),
    `---\nepic_id: E-046-3_3\nstatus: active\nplan_ref: P046\ntitle: Step 3\n---\n\n# Step 3\n\n## Goal\n\nx\n`,
    'utf-8',
  );

  // Tier-3 members: known ONLY via evidence dirs (no active task with plan_ref;
  // the id-derivation E-046-* → P046 + the real plan file makes them members).
  for (const [epicId, runId, state] of [
    ['E-046-1_3', 'R-E046-1', 'DONE'],
    ['E-046-2_3', 'R-E046-2', 'EXECUTE'],
    ['E-046-3_3', 'R-E046-3', 'GATES'],
  ] as const) {
    const runDir = join(aido, 'work', 'evidence', epicId, runId);
    await mkdir(runDir, { recursive: true });
    await writeFile(
      join(runDir, 'fsm-state.yaml'),
      `epic_id: ${epicId}\nrun_id: ${runId}\nstate: ${state}\ncurrent_step: 1\ntotal_steps: 3\nmode: full\nbranch: task/${epicId}/main\nbase_commit: abc\ngate_retries: 0\nescalation_count: 0\nstarted_at: "2026-06-19T10:00:00Z"\ncreated_at: "2026-06-19T10:00:00Z"\nplan_path: null\n`,
      'utf-8',
    );
  }
}

beforeAll(async () => {
  tempDir = await mkdtemp(join(tmpdir(), 'aid-brief-test-'));
  await buildFixtureTree(tempDir);
  await addP046Project(tempDir);

  const config: ServerConfig = {
    port: 3912,
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

describe('GET /api/brief — infra scope (AC1/AC2/AC3)', () => {
  it('AC1 — returns scope:"infra" with the seven brief fields', async () => {
    const res = await supertest(server.app).get('/api/brief');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    const b = res.body.data;
    expect(b.scope).toBe('infra');
    expect(b.projectId).toBeNull();
    expect(b).toHaveProperty('blockers');
    expect(b).toHaveProperty('watchOuts');
    expect(b).toHaveProperty('nextUp');
    expect(b).toHaveProperty('decisionsNeeded');
    expect(b).toHaveProperty('sinceLastSeen');
    expect(b).toHaveProperty('risk');
  });

  it('AC2 — successProbability is {value:null, source:null}', async () => {
    const res = await supertest(server.app).get('/api/brief');
    expect(res.body.data.successProbability).toEqual({ value: null, source: null });
  });

  it('AC1 — blockers + decisions are sorted blocking→warn→info', async () => {
    const res = await supertest(server.app).get('/api/brief');
    for (const list of ['blockers', 'decisionsNeeded'] as const) {
      const weights = res.body.data[list].map((i: { severity: string }) =>
        i.severity === 'blocking' ? 0 : i.severity === 'warn' ? 1 : 2,
      );
      expect(weights).toEqual([...weights].sort((a: number, b: number) => a - b));
    }
  });

  it('AC3 — no ?since= → sinceLastSeen {since:null, items:[]}', async () => {
    const res = await supertest(server.app).get('/api/brief');
    expect(res.body.data.sinceLastSeen.since).toBeNull();
    expect(res.body.data.sinceLastSeen.items).toEqual([]);
  });

  it('infra risk is a valid level with reasons (never throws / never empty shape)', async () => {
    const res = await supertest(server.app).get('/api/brief');
    expect(['nizke', 'stredni', 'vysoke', 'neurceno']).toContain(res.body.data.risk.level);
    expect(Array.isArray(res.body.data.risk.reasons)).toBe(true);
  });
});

describe('GET /api/brief/:projectId — project scope', () => {
  it('returns scope:"project" with the project id and probability invariant', async () => {
    const res = await supertest(server.app).get('/api/brief/vulcan');
    expect(res.status).toBe(200);
    expect(res.body.data.scope).toBe('project');
    expect(res.body.data.projectId).toBe('vulcan');
    expect(res.body.data.successProbability).toEqual({ value: null, source: null });
  });

  it('unknown project → 404', async () => {
    const res = await supertest(server.app).get('/api/brief/does-not-exist');
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });

  it('a since older than the run → sinceLastSeen reports the touched run', async () => {
    const res = await supertest(server.app).get(
      '/api/brief/vulcan?since=2020-01-01T00:00:00.000Z',
    );
    expect(res.body.data.sinceLastSeen.since).toBe('2020-01-01T00:00:00.000Z');
    expect(res.body.data.sinceLastSeen.counts.newRuns).toBeGreaterThan(0);
  });
});

describe('GET /api/brief/:projectId/:planId — plan scope (AC5 / MF1)', () => {
  it('AC5 — P046 (derived members) yields a NON-EMPTY brief', async () => {
    const res = await supertest(server.app).get('/api/brief/aid-orchestrator/P046');
    expect(res.status).toBe(200);
    expect(res.body.data.scope).toBe('plan');
    expect(res.body.data.planId).toBe('P046');
    expect(res.body.data.successProbability).toEqual({ value: null, source: null });

    // Non-empty: the plan-progress nextUp item + the in-flight EXECUTE/GATES runs
    // are surfaced, so at least one BriefItem exists across the lists.
    const total =
      res.body.data.blockers.length +
      res.body.data.watchOuts.length +
      res.body.data.nextUp.length +
      res.body.data.decisionsNeeded.length;
    expect(total).toBeGreaterThan(0);
    // The plan-progress item proves the three derived members were resolved.
    const progress = res.body.data.nextUp.find(
      (i: { signal: string }) => i.signal === 'plan_progress',
    );
    expect(progress).toBeDefined();
    expect(progress.planId).toBe('P046');
  });

  it('plan risk is computed over the plan members (a real level)', async () => {
    const res = await supertest(server.app).get('/api/brief/aid-orchestrator/P046');
    expect(['nizke', 'stredni', 'vysoke', 'neurceno']).toContain(res.body.data.risk.level);
  });
});

describe('AC15 — read-only: a GET writes nothing', () => {
  it('run-dir mtimes are unchanged after hitting all three scopes', async () => {
    const epicDir = join(
      tempDir,
      'aid-orchestrator',
      '.aid-o',
      'work',
      'evidence',
      'E-046-1_3',
      'R-E046-1',
    );
    const before = await snapshotMtimes(epicDir);

    await supertest(server.app).get('/api/brief');
    await supertest(server.app).get('/api/brief/aid-orchestrator');
    await supertest(server.app).get('/api/brief/aid-orchestrator/P046');

    const after = await snapshotMtimes(epicDir);
    expect(after).toEqual(before);
  });
});

/** Map of fileName → mtimeMs for every file directly under a run dir. */
async function snapshotMtimes(dir: string): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const name of await readdir(dir)) {
    const s = await stat(join(dir, name));
    if (s.isFile()) out[name] = s.mtimeMs;
  }
  return out;
}
