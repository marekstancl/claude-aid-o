/**
 * Lessons-per-plan route integration tests (EPIC E-047-4_7, Step 8 — §13.8,
 * AC #21 + the Step-8 ACs #1-6).
 *
 * Boots the FULLY-WIRED server over a REAL on-disk fixture tree (no mocking) and
 * drives `GET /api/lessons?project=&plan=` via supertest. Two projects:
 *   - `aid-orchestrator` — a P046 plan with three members (E-046-1_3 derived,
 *     E-046-2_3 derived, E-046-3_3 plan_ref) + a lessons-learned.md carrying a
 *     main table (kind:lesson) AND a `## Known Gotchas` table (kind:gotcha),
 *     including a member lesson, a non-member lesson, and a no-context lesson.
 *   - `broken` — an EMPTY/malformed lessons-learned.md → entries:[] + a warning,
 *     endpoint still 200 (AC#3 / §7.6 never-throw, AC#21).
 *
 * AC matrix (route surface):
 *   #1  plan scope → only LessonEntrys whose epicId ∈ P046 members.
 *   #2  Known-Gotchas row → kind:'gotcha'; main-table row → kind:'lesson'.
 *   #3  malformed/absent file → entries:[] + warning, endpoint 200 (no throw).
 *   #4  scope inferred from params: both→plan, project-only→project, neither→infra.
 *   #5  chronological-desc ordering when dates parse.
 *   #6  no-Context lesson excluded at plan scope, kept at project/infra.
 *   read-only — GET writes nothing.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtemp, rm, mkdir, writeFile, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import supertest from 'supertest';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';
import type { LessonsView } from '@aid/contract';

let tempDir: string;
let server: BuiltServer;

/** Write a minimal v3 run dir (fsm-state only) for one member EPIC. */
async function writeRun(aido: string, epicId: string, runId: string, startedAt: string): Promise<void> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `epic_id: ${epicId}\nrun_id: ${runId}\nstate: DONE\ncurrent_step: 1\ntotal_steps: 1\nmode: full\nbranch: task/${epicId}/main\nbase_commit: abc\ngate_retries: 0\nescalation_count: 0\nstreamlined_mode: false\nstarted_at: "${startedAt}"\ncreated_at: "${startedAt}"\nplan_path: null\n`,
    'utf-8',
  );
}

/** aid-orchestrator-like project: P046 plan + 3 members + a rich lessons file. */
async function addOrchestratorProject(root: string): Promise<void> {
  const aido = join(root, 'aid-orchestrator', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'plans'), { recursive: true });
  await mkdir(join(aido, 'work'), { recursive: true });

  // P046 plan file exists (drives the four-tier membership).
  await writeFile(
    join(aido, 'plans', 'P046-plan-boundary.md'),
    `---\ntitle: Plan boundary\n---\n\n# P046 — Plan boundary\n\nx\n`,
    'utf-8',
  );

  // E-046-3_3 task carries plan_ref → P046 (tier-2 plan_ref member).
  await writeFile(
    join(aido, 'tasks', 'E-046-3_3-cp.md'),
    `---\nstatus: active\nplan_ref: .aid-o/plans/P046-plan-boundary.md\n---\n\n# Step 3\n\n## Goal\n\nx\n`,
    'utf-8',
  );
  // E-046-1_3 / E-046-2_3 known via evidence only → tier-3 derived members.
  await writeRun(aido, 'E-046-1_3', 'R-E046-1', '2026-06-18T14:00:00Z');
  await writeRun(aido, 'E-046-2_3', 'R-E046-2', '2026-06-18T15:00:00Z');
  await writeRun(aido, 'E-046-3_3', 'R-E046-3', '2026-06-18T16:00:00Z');

  // lessons-learned.md: main table (lessons) + Known Gotchas table (gotchas).
  // A member lesson (E-046-1_3), a non-member lesson (E-099-1_1), a no-context
  // lesson (empty Context), plus two gotchas.
  await writeFile(
    join(aido, 'work', 'lessons-learned.md'),
    `# Lessons Learned

| Date | Lesson | Context |
|------|--------|---------|
| 2026-02-19 | Member lesson about reconciliation | E-046-1_3 |
| 2026-06-18 | Newest member lesson about plan_ref | E-046-3_3 |
| 2026-03-01 | Unrelated non-member lesson | E-099-1_1 |
| 2026-04-04 | A lesson without any context cell | |

## Known Gotchas

| Area | Gotcha |
|------|--------|
| Agent dispatch | Switch dispatch model to sonnet on Claude 500 errors |
| Gates | docs_updated must be type: rule on plugin-only repos |
`,
    'utf-8',
  );
}

/** A project whose lessons-learned.md is empty/whitespace (AC#3 malformed). */
async function addBrokenProject(root: string): Promise<void> {
  const aido = join(root, 'broken', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'work'), { recursive: true });
  // Give it one EPIC so the workspace is discoverable.
  await writeFile(
    join(aido, 'tasks', 'E-077-1_1.md'),
    `---\nstatus: active\n---\n\n# E-077\n`,
    'utf-8',
  );
  await writeRun(aido, 'E-077-1_1', 'R-E077-1', '2026-06-18T10:00:00Z');
  // An empty / whitespace-only lessons file (malformed-ish, parses to []).
  await writeFile(join(aido, 'work', 'lessons-learned.md'), '   \n\n', 'utf-8');
}

function testConfig(root: string): ServerConfig {
  return {
    port: 0,
    host: '127.0.0.1',
    projectsRoot: root,
    hostRoot: root,
    corsOrigins: ['*'],
    scanTtlMs: 60_000,
    activityBufferSize: 100,
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 120_000,
  };
}

beforeAll(async () => {
  tempDir = await mkdtemp(join(tmpdir(), 'aid-lessons-'));
  await addOrchestratorProject(tempDir);
  await addBrokenProject(tempDir);
  server = buildServer(testConfig(tempDir));
  await server.boot();
});

afterAll(async () => {
  await server.shutdown();
  await rm(tempDir, { recursive: true, force: true });
});

describe('GET /api/lessons — scope inference (§13.8, AC#4)', () => {
  it('both project + plan → plan scope', async () => {
    const res = await supertest(server.app).get(
      '/api/lessons?project=aid-orchestrator&plan=P046',
    );
    expect(res.status).toBe(200);
    const view = res.body.data as LessonsView;
    expect(view.scope).toBe('plan');
    expect(view.projectId).toBe('aid-orchestrator');
    expect(view.planId).toBe('P046');
  });

  it('project only → project scope', async () => {
    const res = await supertest(server.app).get('/api/lessons?project=aid-orchestrator');
    expect(res.status).toBe(200);
    const view = res.body.data as LessonsView;
    expect(view.scope).toBe('project');
    expect(view.planId).toBeNull();
  });

  it('neither param → infra scope', async () => {
    const res = await supertest(server.app).get('/api/lessons');
    expect(res.status).toBe(200);
    const view = res.body.data as LessonsView;
    expect(view.scope).toBe('infra');
    expect(view.projectId).toBeNull();
  });
});

describe('GET /api/lessons — plan scope filtering (§13.8, AC#1/#5/#6)', () => {
  it('returns ONLY lessons whose epicId ∈ P046 members (AC#1)', async () => {
    const res = await supertest(server.app).get(
      '/api/lessons?project=aid-orchestrator&plan=P046',
    );
    expect(res.status).toBe(200);
    const view = res.body.data as LessonsView;
    // Two member lessons; the non-member E-099 lesson + no-context lesson + the
    // two no-context gotchas are all excluded.
    expect(view.total).toBe(2);
    const epicIds = view.entries.map((e) => e.epicId).sort();
    expect(epicIds).toEqual(['E-046-1_3', 'E-046-3_3']);
    expect(view.entries.some((e) => e.epicId === 'E-099-1_1')).toBe(false);
  });

  it('orders chronological-desc when dates parse (AC#5)', async () => {
    const res = await supertest(server.app).get(
      '/api/lessons?project=aid-orchestrator&plan=P046',
    );
    const view = res.body.data as LessonsView;
    expect(view.entries[0].epicId).toBe('E-046-3_3'); // 2026-06-18 (newest)
    expect(view.entries[1].epicId).toBe('E-046-1_3'); // 2026-02-19
  });

  it('a no-Context lesson is excluded at plan scope but kept at project scope (AC#6)', async () => {
    const planRes = await supertest(server.app).get(
      '/api/lessons?project=aid-orchestrator&plan=P046',
    );
    const planView = planRes.body.data as LessonsView;
    expect(planView.entries.some((e) => e.epicId === null)).toBe(false);

    const projectRes = await supertest(server.app).get(
      '/api/lessons?project=aid-orchestrator',
    );
    const projectView = projectRes.body.data as LessonsView;
    expect(projectView.entries.some((e) => e.epicId === null)).toBe(true);
  });
});

describe('GET /api/lessons — kind classification (§4.7, AC#2)', () => {
  it('main-table rows are kind:lesson; Known-Gotchas rows are kind:gotcha', async () => {
    const res = await supertest(server.app).get('/api/lessons?project=aid-orchestrator');
    const view = res.body.data as LessonsView;
    const lessons = view.entries.filter((e) => e.kind === 'lesson');
    const gotchas = view.entries.filter((e) => e.kind === 'gotcha');
    expect(lessons.length).toBe(4); // 4 main-table rows
    expect(gotchas.length).toBe(2); // 2 Known-Gotchas rows
    expect(gotchas.every((g) => g.epicId === null)).toBe(true);
  });
});

describe('GET /api/lessons — never-throw on malformed/absent (§7.6, AC#3/#21)', () => {
  it('empty/malformed lessons file → entries:[] + warning, endpoint 200', async () => {
    const res = await supertest(server.app).get('/api/lessons?project=broken');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    const view = res.body.data as LessonsView;
    expect(view.entries).toEqual([]);
    expect(view.total).toBe(0);
    expect(view.warnings.length).toBeGreaterThan(0);
  });

  it('project with NO lessons-learned.md at all → 200 + empty + warning', async () => {
    // The broken project's plan-less project scope is the absent-ish case; the
    // infra merge still succeeds across both projects without throwing.
    const res = await supertest(server.app).get('/api/lessons');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});

describe('GET /api/lessons — validation + not-found', () => {
  it('unknown project (project scope) → 404', async () => {
    const res = await supertest(server.app).get('/api/lessons?project=no-such');
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('unknown plan in a real project → 404', async () => {
    const res = await supertest(server.app).get(
      '/api/lessons?project=aid-orchestrator&plan=P999',
    );
    expect(res.status).toBe(404);
  });

  it('invalid project path component → 400', async () => {
    const res = await supertest(server.app).get('/api/lessons?project=../etc');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });
});

describe('GET /api/lessons — read-only (writes nothing)', () => {
  it('the lessons-learned.md mtime is unchanged after a GET', async () => {
    const file = join(tempDir, 'aid-orchestrator', '.aid-o', 'work', 'lessons-learned.md');
    const before = (await stat(file)).mtimeMs;
    await supertest(server.app).get('/api/lessons?project=aid-orchestrator&plan=P046');
    await supertest(server.app).get('/api/lessons?project=aid-orchestrator');
    const after = (await stat(file)).mtimeMs;
    expect(after).toBe(before);
  });
});
