/**
 * Integration tests for the PUT /ideas/:ideaId/link endpoint.
 *
 * Tests the linking of ideas to plans and/or EPICs, which sets autoStatus:
 *   - linkedPlan only  → autoStatus: 'plan'
 *   - linkedEpic only  → autoStatus: 'epic'
 *   - both             → autoStatus: 'epic' (EPIC takes precedence)
 *   - neither/null     → autoStatus: null
 *
 * Uses the route from packages/aid-server/src/routes/ideas.ts, mounted
 * on a mini Express app with a mock ProjectRegistry.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import express from 'express';
import request from 'supertest';
import { ideaRoutes } from '../../../../aid-server/src/routes/ideas.ts';

// ---------------------------------------------------------------------------
// Shared setup / teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ideas-link-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  await fs.mkdir(aidoDir, { recursive: true });
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

/** Create mock ProjectRegistry that reads from aidoDir */
function createMockRegistry(): any {
  return {
    getFsReader: () => ({
      aidoPath: aidoDir,
      async readText(filePath: string): Promise<string | null> {
        try {
          return await fs.readFile(filePath, 'utf-8');
        } catch {
          return null;
        }
      },
      async readJson(filePath: string): Promise<any> {
        try {
          const text = await fs.readFile(filePath, 'utf-8');
          return JSON.parse(text);
        } catch {
          return null;
        }
      },
    }),
  };
}

/** Create mini Express app with just the ideas route */
function createTestApp(): express.Express {
  const app = express();
  app.use(express.json());
  app.use('/api/p/:projectId/ideas', ideaRoutes(createMockRegistry()) as any);
  return app;
}

/** Create an idea via POST and return its ID */
async function createIdea(
  app: express.Express,
  title: string,
): Promise<string> {
  const res = await request(app)
    .post('/api/p/default/ideas')
    .send({ title })
    .expect(200);

  return res.body.data.id;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('PUT /api/p/default/ideas/:ideaId/link', () => {
  it('sets autoStatus to "plan" when linkedPlan is provided', async () => {
    const app = createTestApp();
    const ideaId = await createIdea(app, 'Test idea for plan link');

    const res = await request(app)
      .put(`/api/p/default/ideas/${ideaId}/link`)
      .send({ linkedPlan: 'P001' })
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.linkedPlan).toBe('P001');
    expect(res.body.data.autoStatus).toBe('plan');
  });

  it('sets autoStatus to "epic" when linkedEpic is provided', async () => {
    const app = createTestApp();
    const ideaId = await createIdea(app, 'Test idea for EPIC link');

    const res = await request(app)
      .put(`/api/p/default/ideas/${ideaId}/link`)
      .send({ linkedEpic: 'E-001' })
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.linkedEpic).toBe('E-001');
    expect(res.body.data.autoStatus).toBe('epic');
  });

  it('sets autoStatus to "epic" when both are provided (EPIC takes precedence)', async () => {
    const app = createTestApp();
    const ideaId = await createIdea(app, 'Test idea for both links');

    const res = await request(app)
      .put(`/api/p/default/ideas/${ideaId}/link`)
      .send({ linkedPlan: 'P001', linkedEpic: 'E-001' })
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.linkedPlan).toBe('P001');
    expect(res.body.data.linkedEpic).toBe('E-001');
    expect(res.body.data.autoStatus).toBe('epic');
  });

  it('returns autoStatus null when unlinking', async () => {
    const app = createTestApp();
    const ideaId = await createIdea(app, 'Test idea for unlink');

    // First link to an EPIC
    await request(app)
      .put(`/api/p/default/ideas/${ideaId}/link`)
      .send({ linkedEpic: 'E-001' })
      .expect(200);

    // Then unlink
    const res = await request(app)
      .put(`/api/p/default/ideas/${ideaId}/link`)
      .send({ linkedPlan: null, linkedEpic: null })
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.linkedPlan).toBeNull();
    expect(res.body.data.linkedEpic).toBeNull();
    expect(res.body.data.autoStatus).toBeNull();
  });

  it('returns 404 for a non-existent idea', async () => {
    const app = createTestApp();

    const res = await request(app)
      .put('/api/p/default/ideas/nonexistent-id/link')
      .send({ linkedPlan: 'P001' })
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('does not modify other idea fields (only link-related fields change)', async () => {
    const app = createTestApp();

    const createRes = await request(app)
      .post('/api/p/default/ideas')
      .send({
        title: 'Original title',
        description: 'Original description',
        tags: ['original'],
        priority: 'high',
      })
      .expect(200);

    const ideaId = createRes.body.data.id;

    const linkRes = await request(app)
      .put(`/api/p/default/ideas/${ideaId}/link`)
      .send({ linkedPlan: 'P001' })
      .expect(200);

    // Non-link fields should be unchanged
    expect(linkRes.body.data.title).toBe('Original title');
    expect(linkRes.body.data.description).toBe('Original description');
    expect(linkRes.body.data.tags).toEqual(['original']);
    expect(linkRes.body.data.priority).toBe('high');
  });
});
