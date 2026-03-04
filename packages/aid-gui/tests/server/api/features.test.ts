/**
 * Integration tests for Ideas CRUD, Projects registry, and Queue Scheduling APIs.
 *
 * Tests use temp directories with HOME override to isolate ~/.aid-gui/ storage.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import request from 'supertest';
import { createApp } from '../../../server/index.ts';
import { invalidateActiveRunCache } from '../../../server/api/middleware.ts';

// ---------------------------------------------------------------------------
// Setup & Teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;
let originalHome: string | undefined;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'api-feat-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  await fs.mkdir(path.join(aidoDir, 'work'), { recursive: true });

  // Override HOME so ~/.aid-gui/ storage resolves to our temp dir
  originalHome = process.env.HOME;
  process.env.HOME = tmpDir;
  process.env.AID_PROJECT_PATH = aidoDir;
  invalidateActiveRunCache();
});

afterEach(async () => {
  process.env.HOME = originalHome;
  delete process.env.AID_PROJECT_PATH;
  invalidateActiveRunCache();
  await fs.rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Ideas API
// ---------------------------------------------------------------------------

describe('Ideas API — GET /api/p/default/ideas', () => {
  it('returns empty array when no ideas stored', async () => {
    const res = await request(createApp()).get('/api/p/default/ideas');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('returns ideas after creation', async () => {
    const app = createApp();
    await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'Test idea' });

    const res = await request(app).get('/api/p/default/ideas');
    expect(res.status).toBe(200);
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].title).toBe('Test idea');
  });

  it('filters by status query param', async () => {
    const app = createApp();
    await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'Idea A' });
    await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'Idea B' });

    // Update second to 'exploring'
    const listRes = await request(app).get('/api/p/default/ideas');
    const ideaB = listRes.body.data[1];
    await request(app)
      .put(`/api/p/default/ideas/${ideaB.id}`)
      .send({ status: 'exploring' });

    const filtered = await request(app).get('/api/p/default/ideas?status=idea');
    expect(filtered.body.data.length).toBe(1);
    expect(filtered.body.data[0].title).toBe('Idea A');
  });

  it('filters by priority query param', async () => {
    const app = createApp();
    await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'Low', priority: 'low' });
    await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'High', priority: 'high' });

    const res = await request(app).get('/api/p/default/ideas?priority=high');
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].title).toBe('High');
  });
});

describe('Ideas API — POST /api/p/default/ideas', () => {
  it('creates an idea with auto-generated ID and defaults', async () => {
    const res = await request(createApp())
      .post('/api/p/default/ideas')
      .send({ title: 'My first idea' });

    expect(res.status).toBe(201);
    expect(res.body.ok).toBe(true);
    const idea = res.body.data;
    expect(idea.id).toMatch(/^idea-/);
    expect(idea.title).toBe('My first idea');
    expect(idea.description).toBe('');
    expect(idea.tags).toEqual([]);
    expect(idea.priority).toBe('medium');
    expect(idea.status).toBe('idea');
    expect(idea.linkedPlan).toBeNull();
    expect(idea.linkedEpic).toBeNull();
    expect(idea.createdAt).toBeDefined();
    expect(idea.updatedAt).toBeDefined();
  });

  it('creates with custom fields', async () => {
    const res = await request(createApp())
      .post('/api/p/default/ideas')
      .send({
        title: 'Custom idea',
        description: 'Detailed desc',
        tags: ['ui', 'feature'],
        priority: 'high',
        linkedPlan: 'P005-C',
        linkedEpic: 'E-001',
      });

    expect(res.status).toBe(201);
    const idea = res.body.data;
    expect(idea.description).toBe('Detailed desc');
    expect(idea.tags).toEqual(['ui', 'feature']);
    expect(idea.priority).toBe('high');
    expect(idea.linkedPlan).toBe('P005-C');
    expect(idea.linkedEpic).toBe('E-001');
  });

  it('returns 400 for missing title', async () => {
    const res = await request(createApp())
      .post('/api/p/default/ideas')
      .send({ description: 'no title' });

    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
  });

  it('returns 400 for empty title', async () => {
    const res = await request(createApp())
      .post('/api/p/default/ideas')
      .send({ title: '' });

    expect(res.status).toBe(400);
    expect(res.body.ok).toBe(false);
  });
});

describe('Ideas API — GET /api/p/default/ideas/:ideaId', () => {
  it('returns a specific idea', async () => {
    const app = createApp();
    const createRes = await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'Specific idea' });
    const ideaId = createRes.body.data.id;

    const res = await request(app).get(`/api/p/default/ideas/${ideaId}`);
    expect(res.status).toBe(200);
    expect(res.body.data.id).toBe(ideaId);
    expect(res.body.data.title).toBe('Specific idea');
  });

  it('returns 404 for nonexistent idea', async () => {
    const res = await request(createApp()).get('/api/p/default/ideas/idea-999');
    expect(res.status).toBe(404);
    expect(res.body.ok).toBe(false);
  });
});

describe('Ideas API — PUT /api/p/default/ideas/:ideaId', () => {
  it('updates idea fields', async () => {
    const app = createApp();
    const createRes = await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'Original' });
    const ideaId = createRes.body.data.id;

    const res = await request(app)
      .put(`/api/p/default/ideas/${ideaId}`)
      .send({ title: 'Updated', status: 'exploring', priority: 'high' });

    expect(res.status).toBe(200);
    expect(res.body.data.title).toBe('Updated');
    expect(res.body.data.status).toBe('exploring');
    expect(res.body.data.priority).toBe('high');
  });

  it('returns 404 for nonexistent idea', async () => {
    const res = await request(createApp())
      .put('/api/p/default/ideas/idea-999')
      .send({ title: 'Nope' });
    expect(res.status).toBe(404);
  });
});

describe('Ideas API — DELETE /api/p/default/ideas/:ideaId', () => {
  it('deletes an idea', async () => {
    const app = createApp();
    const createRes = await request(app)
      .post('/api/p/default/ideas')
      .send({ title: 'To delete' });
    const ideaId = createRes.body.data.id;

    const delRes = await request(app).delete(`/api/p/default/ideas/${ideaId}`);
    expect(delRes.status).toBe(200);
    expect(delRes.body.ok).toBe(true);

    // Verify it's gone
    const getRes = await request(app).get(`/api/p/default/ideas/${ideaId}`);
    expect(getRes.status).toBe(404);
  });

  it('returns 404 for nonexistent idea', async () => {
    const res = await request(createApp()).delete('/api/p/default/ideas/idea-999');
    expect(res.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Projects API
// ---------------------------------------------------------------------------

describe('Projects API — GET /api/projects', () => {
  it('returns empty array when no projects', async () => {
    const res = await request(createApp()).get('/api/projects');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('returns registered projects', async () => {
    const app = createApp();
    await request(app)
      .post('/api/projects')
      .send({ name: 'TestProject', path: tmpDir });

    const res = await request(app).get('/api/projects');
    expect(res.body.data.length).toBe(1);
    expect(res.body.data[0].name).toBe('TestProject');
    expect(res.body.data[0].path).toBe(tmpDir);
  });
});

describe('Projects API — POST /api/projects', () => {
  it('registers a new project', async () => {
    const res = await request(createApp())
      .post('/api/projects')
      .send({ name: 'MyProject', path: tmpDir });

    expect(res.status).toBe(201);
    expect(res.body.ok).toBe(true);
    expect(res.body.data.name).toBe('MyProject');
    expect(res.body.data.id).toBeDefined();
    expect(res.body.data.registeredAt).toBeDefined();
  });

  it('returns 400 for missing name', async () => {
    const res = await request(createApp())
      .post('/api/projects')
      .send({ path: tmpDir });
    expect(res.status).toBe(400);
  });

  it('returns 400 for missing path', async () => {
    const res = await request(createApp())
      .post('/api/projects')
      .send({ name: 'Test' });
    expect(res.status).toBe(400);
  });

  it('returns 400 for duplicate path', async () => {
    const app = createApp();
    await request(app)
      .post('/api/projects')
      .send({ name: 'First', path: tmpDir });

    const res = await request(app)
      .post('/api/projects')
      .send({ name: 'Second', path: tmpDir });
    expect(res.status).toBe(400);
  });

  it('first registered project is auto-activated', async () => {
    const app = createApp();
    const res = await request(app)
      .post('/api/projects')
      .send({ name: 'First', path: tmpDir });
    expect(res.body.data.active).toBe(true);
  });
});

describe('Projects API — GET /api/projects/active', () => {
  it('returns 404 when no active project', async () => {
    const res = await request(createApp()).get('/api/projects/active');
    expect(res.status).toBe(404);
  });

  it('returns the active project', async () => {
    const app = createApp();
    await request(app)
      .post('/api/projects')
      .send({ name: 'Active', path: tmpDir });

    const res = await request(app).get('/api/projects/active');
    expect(res.status).toBe(200);
    expect(res.body.data.name).toBe('Active');
    expect(res.body.data.active).toBe(true);
  });
});

describe('Projects API — PUT /api/projects/:id/activate', () => {
  it('activates a project', async () => {
    const app = createApp();
    // Create two projects
    const dir2 = await fs.mkdtemp(path.join(os.tmpdir(), 'proj2-'));
    await fs.mkdir(path.join(dir2, '.aid-o'), { recursive: true });

    const res1 = await request(app)
      .post('/api/projects')
      .send({ name: 'First', path: tmpDir });
    const res2 = await request(app)
      .post('/api/projects')
      .send({ name: 'Second', path: dir2 });

    const id2 = res2.body.data.id;
    const activateRes = await request(app)
      .put(`/api/projects/${id2}/activate`);

    expect(activateRes.status).toBe(200);
    expect(activateRes.body.data.active).toBe(true);

    // First should now be inactive
    const listRes = await request(app).get('/api/projects');
    const first = listRes.body.data.find((p: { id: string }) => p.id === res1.body.data.id);
    expect(first.active).toBe(false);

    await fs.rm(dir2, { recursive: true, force: true });
  });

  it('returns 404 for nonexistent project', async () => {
    const res = await request(createApp())
      .put('/api/projects/proj-999/activate');
    expect(res.status).toBe(404);
  });
});

describe('Projects API — DELETE /api/projects/:id', () => {
  it('removes a project', async () => {
    const app = createApp();
    // Need two projects — can't delete active
    const dir2 = await fs.mkdtemp(path.join(os.tmpdir(), 'proj2-'));

    await request(app)
      .post('/api/projects')
      .send({ name: 'First', path: tmpDir });
    const res2 = await request(app)
      .post('/api/projects')
      .send({ name: 'Second', path: dir2 });
    const id2 = res2.body.data.id;

    const delRes = await request(app).delete(`/api/projects/${id2}`);
    expect(delRes.status).toBe(200);

    const listRes = await request(app).get('/api/projects');
    expect(listRes.body.data.length).toBe(1);

    await fs.rm(dir2, { recursive: true, force: true });
  });

  it('returns 400 when trying to delete active project', async () => {
    const app = createApp();
    const res = await request(app)
      .post('/api/projects')
      .send({ name: 'Active', path: tmpDir });
    const id = res.body.data.id;

    const delRes = await request(app).delete(`/api/projects/${id}`);
    expect(delRes.status).toBe(400);
  });

  it('returns 404 for nonexistent project', async () => {
    const res = await request(createApp()).delete('/api/projects/proj-999');
    expect(res.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Queue Scheduling API
// ---------------------------------------------------------------------------

describe('Queue Scheduling — GET /api/p/default/queue/schedule', () => {
  it('returns default schedule config when none stored', async () => {
    // Need queue file to exist for the queue router
    await fs.mkdir(path.join(aidoDir, 'work'), { recursive: true });

    const res = await request(createApp()).get('/api/p/default/queue/schedule');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    const config = res.body.data;
    expect(config.enabled).toBe(false);
    expect(config.cooldownSeconds).toBe(30);
    expect(config.maxConcurrent).toBe(1);
  });
});

describe('Queue Scheduling — PUT /api/p/default/queue/schedule', () => {
  it('updates schedule config', async () => {
    const res = await request(createApp())
      .put('/api/p/default/queue/schedule')
      .send({ enabled: true, cooldownSeconds: 60 });

    expect(res.status).toBe(200);
    expect(res.body.data.enabled).toBe(true);
    expect(res.body.data.cooldownSeconds).toBe(60);
  });

  it('returns 400 for negative cooldownSeconds', async () => {
    const res = await request(createApp())
      .put('/api/p/default/queue/schedule')
      .send({ cooldownSeconds: -5 });

    expect(res.status).toBe(400);
  });

  it('returns 400 for maxConcurrent less than 1', async () => {
    const res = await request(createApp())
      .put('/api/p/default/queue/schedule')
      .send({ maxConcurrent: 0 });

    expect(res.status).toBe(400);
  });
});

describe('Queue Scheduling — GET /api/p/default/queue/schedule/status', () => {
  it('returns schedule status snapshot', async () => {
    const res = await request(createApp())
      .get('/api/p/default/queue/schedule/status');

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    const status = res.body.data;
    expect(status.state).toBeDefined();
    expect(status.timestamp).toBeDefined();
  });
});
