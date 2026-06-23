/**
 * Audit-trend + audit-summary route integration tests — spec §7.4, §13.5.4 /
 * §13.5.7 (EPIC E-047-4_7 Step 6).
 *
 * Boots the full server over a REAL on-disk fixture tree (no mocking) and drives
 * the four endpoints via supertest. The flagship fixture mirrors aid-orchestrator
 * P046: three audited E-046 runs whose `started_at` order is 89 → 95 → 84, one
 * score-less audited run (kept as a `score:null` gap), and a no-audit run (no
 * point). A second project (sousto-like) has ZERO audit reports (honest empty).
 *
 * AC matrix (route surface):
 *   AC1 — EPIC trend ordered 89,95,84 by started_at; scoredPointCount 3; delta -5
 *   AC2 — a score-less run kept as score:null (never dropped/interpolated)
 *   AC5 — /audit-trend/:p → project; /:p/:e → epic; /:p/plan/:planId → plan;
 *         /audit-summary/:p → median-EPIC aggregateAudit (89 for P046)
 *   AC6 — zero audited EPICs → points:[], scoredPointCount:0, delta:null +
 *         aggregateAudit present:true, overallScore:null, scoredEpicCount:0
 *   read-only — GET writes nothing (run-dir mtimes unchanged)
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtemp, rm, mkdir, writeFile, stat, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import supertest from 'supertest';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';

let tempDir: string;
let server: BuiltServer;

/** Write a v3 run dir with fsm-state.yaml + an optional audit-report.md. */
async function writeRun(
  aido: string,
  epicId: string,
  runId: string,
  state: string,
  startedAt: string,
  auditReport: string | null,
): Promise<void> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `epic_id: ${epicId}\nrun_id: ${runId}\nstate: ${state}\ncurrent_step: 2\ntotal_steps: 2\nmode: full\nbranch: task/${epicId}/main\nbase_commit: abc\ngate_retries: 0\nescalation_count: 0\nstreamlined_mode: false\nstarted_at: "${startedAt}"\ncreated_at: "${startedAt}"\nplan_path: null\n`,
    'utf-8',
  );
  if (auditReport !== null) {
    await writeFile(join(runDir, 'audit-report.md'), auditReport, 'utf-8');
  }
}

/**
 * aid-orchestrator-like P046 project: three audited E-046 EPICs whose runs carry
 * the real three score SHAPES (table-Total 89, heading 95, fence-less frontmatter
 * 84) and the §13.5.4 started_at order. Plus a score-less audited run (E-046-4_3)
 * and a no-audit run (E-046-5_3).
 */
async function addP046Project(root: string): Promise<void> {
  const aido = join(root, 'aid-orchestrator', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'plans'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });

  await writeFile(
    join(aido, 'plans', 'P046.md'),
    `---\nplan_id: P046\ntitle: Cockpit MVP\n---\n\n# P046 — Cockpit MVP\n\nbody\n`,
    'utf-8',
  );
  // Tier-2 member: active task with plan_ref. The other E-046 members resolve at
  // tier-3 (id-derived E-046-* → P046 + the real plan file).
  await writeFile(
    join(aido, 'tasks', 'E-046-3_3.md'),
    `---\nepic_id: E-046-3_3\nstatus: active\nplan_ref: P046\ntitle: Step 3\n---\n\n# Step 3\n\n## Goal\n\nx\n`,
    'utf-8',
  );

  // The flagship trio — table-Total 89, heading 95, fence-less frontmatter 84.
  await writeRun(
    aido,
    'E-046-1_3',
    'R-E046-1',
    'DONE',
    '2026-06-18T14:04:10Z',
    `# Audit — E-046-1_3\n\n## Score\n\n| Metric | Value |\n|---|---|\n| **Total** | **89/100** |\n\nblocking_findings: 0\n`,
  );
  await writeRun(
    aido,
    'E-046-2_3',
    'R-E046-2',
    'DONE',
    '2026-06-18T14:04:24Z',
    `# Audit — E-046-2_3\n\n## Score: 95/100\n\nblocking_findings: 0\n`,
  );
  await writeRun(
    aido,
    'E-046-3_3',
    'R-E046-3',
    'GATES',
    '2026-06-18T14:04:37Z',
    `overall_score: 84\nblocking_findings: 0\n\n# Audit — E-046-3_3\n\n## Scores\n`,
  );

  // A score-less BUT audited run (audit-report.md present, no parseable score).
  await writeRun(
    aido,
    'E-046-4_3',
    'R-E046-4',
    'DONE',
    '2026-06-18T14:04:50Z',
    `# Audit — E-046-4_3\n\nThe auditor wrote prose but no score and no blocking line.\n`,
  );

  // An un-audited run (NO audit-report.md → contributes no point).
  await writeRun(aido, 'E-046-5_3', 'R-E046-5', 'EXECUTE', '2026-06-18T14:05:00Z', null);
}

/** A sousto-like project with ZERO audit reports across its workspace (AC6). */
async function addSoustoProject(root: string): Promise<void> {
  const aido = join(root, 'sousto-na-miru', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });
  await writeRun(aido, 'E-009-1_2', 'R-1', 'DONE', '2026-06-01T10:00:00Z', null);
}

async function snapshotMtimes(dir: string): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const name of await readdir(dir)) {
    out[name] = (await stat(join(dir, name))).mtimeMs;
  }
  return out;
}

beforeAll(async () => {
  tempDir = await mkdtemp(join(tmpdir(), 'aid-audit-test-'));
  await addP046Project(tempDir);
  await addSoustoProject(tempDir);

  const config: ServerConfig = {
    port: 3913,
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

describe('GET /api/audit-trend/:projectId/:epicId — EPIC scope (AC1)', () => {
  it('orders the E-046-1_3 single run as a one-point trend', async () => {
    const res = await supertest(server.app).get('/api/audit-trend/aid-orchestrator/E-046-1_3');
    expect(res.status).toBe(200);
    expect(res.body.data.scope).toBe('epic');
    expect(res.body.data.points.map((p: { score: number }) => p.score)).toEqual([89]);
    expect(res.body.data.scoredPointCount).toBe(1);
    expect(res.body.data.delta).toBeNull();
  });

  it('AC2 — a score-less audited run is kept as a point with score:null', async () => {
    const res = await supertest(server.app).get('/api/audit-trend/aid-orchestrator/E-046-4_3');
    expect(res.body.data.points).toHaveLength(1);
    expect(res.body.data.points[0].score).toBeNull();
    expect(res.body.data.scoredPointCount).toBe(0);
  });

  it('unknown EPIC → 404', async () => {
    const res = await supertest(server.app).get('/api/audit-trend/aid-orchestrator/E-999');
    expect(res.status).toBe(404);
  });
});

describe('GET /api/audit-trend/:projectId/plan/:planId — PLAN scope (AC1/AC5)', () => {
  it('orders the P046 members 89 → 95 → 84 by started_at; delta -5 (AC #18)', async () => {
    const res = await supertest(server.app).get(
      '/api/audit-trend/aid-orchestrator/plan/P046',
    );
    expect(res.status).toBe(200);
    expect(res.body.data.scope).toBe('plan');
    // One point per audited member EPIC, ordered by started_at; the score-less
    // member (E-046-4_3) is kept as a null gap LAST (started 14:04:50).
    const scores = res.body.data.points.map((p: { score: number | null }) => p.score);
    expect(scores).toEqual([89, 95, 84, null]);
    expect(res.body.data.scoredPointCount).toBe(3);
    expect(res.body.data.delta).toBe(-5);
  });

  it('plan ordering is by started_at, NOT lexicographic epic-id', async () => {
    const res = await supertest(server.app).get(
      '/api/audit-trend/aid-orchestrator/plan/P046',
    );
    expect(res.body.data.points.map((p: { epicId: string }) => p.epicId)).toEqual([
      'E-046-1_3',
      'E-046-2_3',
      'E-046-3_3',
      'E-046-4_3',
    ]);
  });
});

describe('GET /api/audit-trend/:projectId — PROJECT scope (AC5)', () => {
  it('returns scope:"project" with one point per audited EPIC, ordered by started_at', async () => {
    const res = await supertest(server.app).get('/api/audit-trend/aid-orchestrator');
    expect(res.status).toBe(200);
    expect(res.body.data.scope).toBe('project');
    // Audited EPICs only (E-046-5_3 has no audit-report.md → no point).
    const scores = res.body.data.points.map((p: { score: number | null }) => p.score);
    expect(scores).toEqual([89, 95, 84, null]);
    expect(res.body.data.scoredPointCount).toBe(3);
    expect(res.body.data.delta).toBe(-5);
  });

  it('AC6 — a project with zero audited EPICs → empty-but-honest trend', async () => {
    const res = await supertest(server.app).get('/api/audit-trend/sousto-na-miru');
    expect(res.status).toBe(200);
    expect(res.body.data.points).toEqual([]);
    expect(res.body.data.scoredPointCount).toBe(0);
    expect(res.body.data.delta).toBeNull();
  });

  it('unknown project → 404', async () => {
    const res = await supertest(server.app).get('/api/audit-trend/does-not-exist');
    expect(res.status).toBe(404);
  });
});

describe('GET /api/audit-summary/:projectId — project aggregateAudit (AC5/AC6)', () => {
  it('AC5 — median-EPIC aggregate of {89,95,84} = 89 (the E-046-1_3 summary)', async () => {
    const res = await supertest(server.app).get('/api/audit-summary/aid-orchestrator');
    expect(res.status).toBe(200);
    // {84,89,95} sorted → lower-middle (median) = 89.
    expect(res.body.data.overallScore).toBe(89);
    expect(res.body.data.scoredEpicCount).toBe(3);
    expect(res.body.data.medianEpicId).toBe('E-046-1_3');
    expect(res.body.data.present).toBe(true);
  });

  it('AC6 — sousto-na-miru (0 audited EPICs) → present:true, overallScore:null', async () => {
    const res = await supertest(server.app).get('/api/audit-summary/sousto-na-miru');
    expect(res.status).toBe(200);
    expect(res.body.data.present).toBe(true);
    expect(res.body.data.overallScore).toBeNull();
    expect(res.body.data.scoredEpicCount).toBe(0);
    expect(res.body.data.medianEpicId).toBeNull();
    expect(res.body.data.warnings.length).toBeGreaterThan(0);
  });

  it('unknown project → 404', async () => {
    const res = await supertest(server.app).get('/api/audit-summary/nope');
    expect(res.status).toBe(404);
  });
});

describe('read-only — a GET writes nothing', () => {
  it('run-dir mtimes are unchanged after hitting every audit endpoint', async () => {
    const runDir = join(
      tempDir,
      'aid-orchestrator',
      '.aid-o',
      'work',
      'evidence',
      'E-046-1_3',
      'R-E046-1',
    );
    const before = await snapshotMtimes(runDir);
    await supertest(server.app).get('/api/audit-trend/aid-orchestrator');
    await supertest(server.app).get('/api/audit-trend/aid-orchestrator/E-046-1_3');
    await supertest(server.app).get('/api/audit-trend/aid-orchestrator/plan/P046');
    await supertest(server.app).get('/api/audit-summary/aid-orchestrator');
    expect(await snapshotMtimes(runDir)).toEqual(before);
  });
});
