/**
 * Integration tests for EPIC routes (packages/aid-server/src/routes/epics.ts).
 *
 * Focused on:
 *   GET  /api/p/:projectId/epics        — YAML frontmatter parsing, status sort, edge cases
 *   POST /api/p/:projectId/epics/:id/run — enqueue 'now' and 'schedule', conflict, not-found, bad-request
 *
 * Test strategy:
 *   - Uses a mini Express app created with just the epicRoutes, mounted with
 *     a mock ProjectRegistry (same pattern as ideas-link.test.ts)
 *   - Each test gets an isolated tmpDir via os.tmpdir() + mkdtemp
 *   - No ENV overrides needed — the mock registry is pointed directly at tmpDir
 *
 * Note: The GUI server (server/api/epics.ts) has different fields than the
 * aid-server routes. These tests exercise the aid-server epicRoutes directly.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import express from 'express';
import yaml from 'js-yaml';
import request from 'supertest';
import { epicRoutes } from '../../../aid-server/src/routes/epics.ts';
import type { ProjectRegistry } from '../../../aid-server/src/services/project-registry.ts';

// ---------------------------------------------------------------------------
// Setup / Teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'epics-route-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  await fs.mkdir(path.join(aidoDir, 'work'), { recursive: true });
  await fs.mkdir(path.join(aidoDir, 'config'), { recursive: true });
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Mock registry factory
// ---------------------------------------------------------------------------

function createMockRegistry(): Record<string, unknown> {
  return {
    getFsReader: (_projectId: string) => ({
      aidoPath: aidoDir,
      async readText(filePath: string): Promise<string | null> {
        try {
          return await fs.readFile(filePath, 'utf-8');
        } catch {
          return null;
        }
      },
      async readJson<T>(filePath: string): Promise<T | null> {
        try {
          const text = await fs.readFile(filePath, 'utf-8');
          return JSON.parse(text) as T;
        } catch {
          return null;
        }
      },
      async readYaml<T>(filePath: string): Promise<T | null> {
        try {
          const text = await fs.readFile(filePath, 'utf-8');
          return yaml.load(text) as T;
        } catch {
          return null;
        }
      },
    }),
  };
}

function createTestApp(): express.Express {
  const app = express();
  app.use(express.json());
  const registry = createMockRegistry();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  app.use('/api/p/:projectId/epics', epicRoutes(registry as unknown as ProjectRegistry) as any);
  return app;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function writeEpic(fileName: string, content: string): Promise<void> {
  const epicsDir = path.join(aidoDir, 'tasks');
  await fs.mkdir(epicsDir, { recursive: true });
  await fs.writeFile(path.join(epicsDir, fileName), content, 'utf-8');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const EPIC_WITH_FRONTMATTER = `---
id: E-016
status: active
plan_ref: .aid-o/plans/P001.md
runs_total: 3
runs_completed: 1
---

# E-016 Companion Feature

This EPIC covers the AI companion implementation.
`;

const EPIC_WITHOUT_FRONTMATTER = `# E-017 Plain EPIC

This EPIC has no YAML frontmatter.
`;

const EPIC_READY = `---
id: E-018
status: ready
runs_total: 0
runs_completed: 0
---

# E-018 Ready EPIC
`;

const EPIC_COMPLETED = `---
id: E-019
status: completed
runs_total: 2
runs_completed: 2
---

# E-019 Completed EPIC
`;

// ---------------------------------------------------------------------------
// GET /api/p/default/epics — frontmatter parsing
// ---------------------------------------------------------------------------

describe('GET /api/p/default/epics — frontmatter parsing', () => {
  it('parses id from frontmatter when present', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    const epic = res.body.data[0];
    expect(epic.id).toBe('E-016');
  });

  it('extracts title from the first markdown h1 heading', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.title).toBe('E-016 Companion Feature');
  });

  it('reads status from frontmatter', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.status).toBe('active');
  });

  it('reads runs_total and runs_completed from frontmatter', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.runsTotal).toBe(3);
    expect(epic.runsCompleted).toBe(1);
  });

  it('falls back to filename-derived id when frontmatter has no id', async () => {
    await writeEpic('E-017-plain.md', EPIC_WITHOUT_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.id).toBe('E-017-plain');
  });

  it('defaults status to "draft" when not specified in frontmatter', async () => {
    await writeEpic('E-017-plain.md', EPIC_WITHOUT_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.status).toBe('draft');
  });

  it('defaults runs_total and runs_completed to 0 when absent', async () => {
    await writeEpic('E-017-plain.md', EPIC_WITHOUT_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.runsTotal).toBe(0);
    expect(epic.runsCompleted).toBe(0);
  });

  it('includes the correct path field in the format "tasks/<fileName>"', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.path).toBe('tasks/E-016-companion.md');
  });

  it('includes the fileName field', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.fileName).toBe('E-016-companion.md');
  });

  it('reads planRef from frontmatter when plan_ref is set', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.planRef).toBe('.aid-o/plans/P001.md');
  });
});

// ---------------------------------------------------------------------------
// GET /api/p/default/epics — edge cases
// ---------------------------------------------------------------------------

describe('GET /api/p/default/epics — edge cases', () => {
  it('returns 200 with empty array when tasks directory is missing', async () => {
    // Directory not created
    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('excludes files that are not .md extension', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const epicsDir = path.join(aidoDir, 'tasks');
    await fs.writeFile(path.join(epicsDir, 'notes.txt'), 'not an epic');
    await fs.writeFile(path.join(epicsDir, 'README'), 'also not an epic');

    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].fileName).toBe('E-016-companion.md');
  });

  it('returns planRef as null when frontmatter has no plan_ref', async () => {
    // EPIC_READY has no plan_ref
    await writeEpic('E-018-ready.md', EPIC_READY);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    const epic = res.body.data[0];
    expect(epic.planRef).toBeNull();
  });

  it('returns 200 ok response structure', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// GET /api/p/default/epics — status sort order
// ---------------------------------------------------------------------------

describe('GET /api/p/default/epics — status sort order', () => {
  it('places active EPICs before ready EPICs', async () => {
    await writeEpic('E-018-ready.md', EPIC_READY);
    await writeEpic('E-016-active.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.body.data[0].status).toBe('active');
    expect(res.body.data[1].status).toBe('ready');
  });

  it('places ready EPICs before completed EPICs', async () => {
    await writeEpic('E-019-completed.md', EPIC_COMPLETED);
    await writeEpic('E-018-ready.md', EPIC_READY);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.body.data[0].status).toBe('ready');
    expect(res.body.data[1].status).toBe('completed');
  });

  it('sorts EPICs of the same status alphabetically by filename', async () => {
    await writeEpic('beta-epic.md', `---\nstatus: draft\n---\n# Beta\n`);
    await writeEpic('alpha-epic.md', `---\nstatus: draft\n---\n# Alpha\n`);

    const res = await request(createTestApp()).get('/api/p/default/epics');

    expect(res.body.data[0].fileName).toBe('alpha-epic.md');
    expect(res.body.data[1].fileName).toBe('beta-epic.md');
  });
});

// ---------------------------------------------------------------------------
// POST /api/p/default/epics/:epicId/run — success cases
// ---------------------------------------------------------------------------

describe('POST /api/p/default/epics/:epicId/run — success', () => {
  it('returns 200 with ok:true when mode is "now" and EPIC exists', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('response includes epicId, path, priority, status, addedAt', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    const data = res.body.data;
    expect(data.epicId).toBe('E-016');
    expect(typeof data.path).toBe('string');
    expect(typeof data.priority).toBe('string');
    expect(data.status).toBe('queued');
    expect(typeof data.addedAt).toBe('string');
  });

  it('assigns "critical" priority when mode is "now"', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.body.data.priority).toBe('critical');
  });

  it('assigns "medium" priority when mode is "schedule"', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'schedule' });

    expect(res.body.data.priority).toBe('medium');
  });

  it('returns 200 with ok:true when mode is "schedule"', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'schedule' });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('writes the queue file after enqueuing an EPIC', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    const raw = await fs.readFile(queuePath, 'utf-8');
    const parsed = yaml.load(raw) as { queue: { epic_id: string }[] };

    expect(parsed.queue).toBeDefined();
    expect(parsed.queue.length).toBeGreaterThan(0);
    expect(parsed.queue[0].epic_id).toBe('E-016');
  });

  it('inserts "now" mode entry at the front of an existing queue', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);
    await writeEpic('E-018-ready.md', EPIC_READY);

    const app = createTestApp();

    // Enqueue E-018 first with schedule mode
    await request(app)
      .post('/api/p/default/epics/E-018/run')
      .send({ mode: 'schedule' });

    // Enqueue E-016 with "now" mode — should go to the front
    await request(app)
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    const raw = await fs.readFile(queuePath, 'utf-8');
    const parsed = yaml.load(raw) as { queue: { epic_id: string }[] };

    expect(parsed.queue[0].epic_id).toBe('E-016');
    expect(parsed.queue[1].epic_id).toBe('E-018');
  });

  it('appends "schedule" mode entry at the back of an existing queue', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);
    await writeEpic('E-018-ready.md', EPIC_READY);

    const app = createTestApp();

    await request(app)
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    await request(app)
      .post('/api/p/default/epics/E-018/run')
      .send({ mode: 'schedule' });

    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    const raw = await fs.readFile(queuePath, 'utf-8');
    const parsed = yaml.load(raw) as { queue: { epic_id: string }[] };

    expect(parsed.queue[0].epic_id).toBe('E-016');
    expect(parsed.queue[1].epic_id).toBe('E-018');
  });

  it('matches EPIC by exact filename <epicId>.md', async () => {
    await writeEpic('E-016.md', `---\nstatus: ready\n---\n# E-016 Direct\n`);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('matches EPIC by filename prefix <epicId>-<rest>.md', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('path in response uses the .aid-o prefix format', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.body.data.path).toMatch(/^\.aid-o\/tasks\//);
  });
});

// ---------------------------------------------------------------------------
// POST /api/p/default/epics/:epicId/run — error cases
// ---------------------------------------------------------------------------

describe('POST /api/p/default/epics/:epicId/run — error cases', () => {
  it('returns 404 when EPIC does not exist', async () => {
    await fs.mkdir(path.join(aidoDir, 'tasks'), { recursive: true });

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-999/run')
      .send({ mode: 'now' });

    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns 404 when the epics directory does not exist', async () => {
    // tasks directory was never created
    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });

  it('returns 400 when mode is missing from the request body', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({});

    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 when mode is an invalid value', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'invalid-mode' });

    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
  });

  it('returns 409 when the EPIC is already queued with status "queued"', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const app = createTestApp();

    // First enqueue succeeds
    await request(app)
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    // Second enqueue for the same EPIC must conflict
    const res = await request(app)
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.status).toBe(409);
    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('CONFLICT');
  });

  it('allows re-queuing an EPIC that was previously completed (not status "queued")', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    // Pre-populate queue with a completed entry for E-016
    const existingQueue = {
      queue: [
        {
          epic_id: 'E-016',
          path: '.aid-o/tasks/E-016-companion.md',
          priority: 'critical',
          status: 'completed',
          added_at: '2026-02-01T00:00:00.000Z',
        },
      ],
    };
    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    await fs.writeFile(queuePath, yaml.dump(existingQueue), 'utf-8');

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    // Must not conflict — previous entry has status 'completed', not 'queued'
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('error response includes a message explaining the not-found condition', async () => {
    await fs.mkdir(path.join(aidoDir, 'tasks'), { recursive: true });

    const res = await request(createTestApp())
      .post('/api/p/default/epics/E-999/run')
      .send({ mode: 'now' });

    expect(typeof res.body.error.message).toBe('string');
    expect(res.body.error.message.length).toBeGreaterThan(0);
  });

  it('conflict error message mentions the epicId', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    const app = createTestApp();
    await request(app).post('/api/p/default/epics/E-016/run').send({ mode: 'now' });

    const res = await request(app)
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    expect(res.body.error.message).toMatch(/E-016/);
  });
});

// ---------------------------------------------------------------------------
// POST /api/p/default/epics/:epicId/run — queue persistence
// ---------------------------------------------------------------------------

describe('POST /api/p/default/epics/:epicId/run — queue persistence', () => {
  it('persists the queued entry to queue.yaml with all required fields', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'schedule' });

    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    const raw = await fs.readFile(queuePath, 'utf-8');
    const parsed = yaml.load(raw) as {
      queue: {
        epic_id: string;
        path: string;
        priority: string;
        status: string;
        added_at: string;
      }[];
    };

    const entry = parsed.queue[0];
    expect(entry.epic_id).toBe('E-016');
    expect(typeof entry.path).toBe('string');
    expect(entry.priority).toBe('medium');
    expect(entry.status).toBe('queued');
    expect(typeof entry.added_at).toBe('string');
    // added_at must be a valid ISO 8601 date
    expect(new Date(entry.added_at).getTime()).not.toBeNaN();
  });

  it('queued entry path references the correct EPIC file', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);

    await request(createTestApp())
      .post('/api/p/default/epics/E-016/run')
      .send({ mode: 'now' });

    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    const raw = await fs.readFile(queuePath, 'utf-8');
    const parsed = yaml.load(raw) as { queue: { path: string }[] };

    expect(parsed.queue[0].path).toContain('E-016-companion.md');
  });

  it('preserves existing queue entries when adding a new one', async () => {
    await writeEpic('E-016-companion.md', EPIC_WITH_FRONTMATTER);
    await writeEpic('E-018-ready.md', EPIC_READY);

    const app = createTestApp();

    await request(app).post('/api/p/default/epics/E-016/run').send({ mode: 'now' });
    await request(app).post('/api/p/default/epics/E-018/run').send({ mode: 'schedule' });

    const queuePath = path.join(aidoDir, 'config', 'queue.yaml');
    const raw = await fs.readFile(queuePath, 'utf-8');
    const parsed = yaml.load(raw) as { queue: { epic_id: string }[] };

    expect(parsed.queue).toHaveLength(2);

    const ids = parsed.queue.map((e) => e.epic_id);
    expect(ids).toContain('E-016');
    expect(ids).toContain('E-018');
  });
});
