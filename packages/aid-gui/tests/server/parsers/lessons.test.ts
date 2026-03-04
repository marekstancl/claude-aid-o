/**
 * Integration tests for the lessons REST API endpoint.
 *
 * Tests the GET /lessons endpoint from packages/aid-server/src/routes/lessons.ts
 * by mounting the route on a mini Express app with a mock ProjectRegistry.
 *
 * Expected file format (lessons-learned.md):
 *   ## Lessons Learned
 *   | # | Lesson | Context | Impact |
 *
 *   ## Known Gotchas
 *   | # | Gotcha | When | Workaround |
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import express from 'express';
import request from 'supertest';
import { lessonsRoutes } from '../../../../aid-server/src/routes/lessons.ts';

// ---------------------------------------------------------------------------
// Shared setup / teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'lessons-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

/** Write a file, creating parent directories if needed. */
async function writeFile(filePath: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, 'utf-8');
}

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
    }),
  };
}

/** Create mini Express app with just the lessons route */
function createTestApp(): express.Express {
  const app = express();
  app.use(express.json());
  app.use('/api/p/:projectId/lessons', lessonsRoutes(createMockRegistry()) as any);
  return app;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const LESSONS_ONLY_MD = `# Project Insights

## Lessons Learned

| # | Lesson | Context | Impact |
|---|--------|---------|--------|
| 1 | Always validate input at boundaries | API testing revealed missing checks | Prevented 3 downstream bugs |
| 2 | Use structured logging from day one | Debugging blind without structured logs | Reduced debugging time by 60% |
`;

const GOTCHAS_ONLY_MD = `# Project Insights

## Known Gotchas

| # | Gotcha | When | Workaround |
|---|--------|------|------------|
| 1 | Express middleware order matters | Adding middleware after error handler | Always register error handler last |
| 2 | File watcher races on macOS | Rapid file saves during auto-mode | Add 50ms debounce to watcher events |
`;

const MIXED_MD = `# Project Insights

## Lessons Learned

| # | Lesson | Context | Impact |
|---|--------|---------|--------|
| 1 | Test edge cases first | Missing edge case caused regression | Critical bug caught in QA |

## Known Gotchas

| # | Gotcha | When | Workaround |
|---|--------|------|------------|
| 1 | YAML parser silently drops invalid keys | Malformed YAML config files | Validate YAML schema on load |
`;

const MALFORMED_LESSONS_MD = `# Project Insights

## Lessons Learned

| # | Lesson | Context | Impact |
|---|--------|---------|--------|
| 1 | Valid lesson | Valid context | Valid impact |
| bad row |
| 3 | Another valid | More context | More impact |

## Known Gotchas

| # | Gotcha | When | Workaround |
|---|--------|------|------------|
| 1 | Valid gotcha | Valid when | Valid workaround |
`;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('GET /api/p/default/lessons — Lessons Learned table', () => {
  it('returns LessonEntry[] with category "lesson" from lessons-only file', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'lessons-learned.md'),
      LESSONS_ONLY_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/lessons')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);

    const first = res.body.data[0];
    expect(first.id).toBeDefined();
    expect(first.category).toBe('lesson');
    expect(first.lesson).toContain('validate input');
    expect(first.context).toContain('API testing');
    expect(first.impact).toContain('3 downstream');
  });
});

describe('GET /api/p/default/lessons — Known Gotchas table', () => {
  it('returns entries with category "gotcha" from gotchas-only file', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'lessons-learned.md'),
      GOTCHAS_ONLY_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/lessons')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);

    const first = res.body.data[0];
    expect(first.category).toBe('gotcha');
    expect(first.gotcha).toContain('Express middleware');
    expect(first.when).toContain('Adding middleware');
    expect(first.workaround).toContain('error handler last');
  });
});

describe('GET /api/p/default/lessons — mixed file', () => {
  it('returns mixed array with both lesson and gotcha entries', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'lessons-learned.md'),
      MIXED_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/lessons')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);

    const lessons = res.body.data.filter(
      (e: { category: string }) => e.category === 'lesson',
    );
    const gotchas = res.body.data.filter(
      (e: { category: string }) => e.category === 'gotcha',
    );
    expect(lessons).toHaveLength(1);
    expect(gotchas).toHaveLength(1);
  });
});

describe('GET /api/p/default/lessons — edge cases', () => {
  it('returns { ok: true, data: [] } when lessons file does not exist', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/lessons')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('skips malformed rows without crashing', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'lessons-learned.md'),
      MALFORMED_LESSONS_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/lessons')
      .expect(200);

    expect(res.body.ok).toBe(true);
    // Valid rows: 2 lessons + 1 gotcha = 3
    expect(res.body.data.length).toBeGreaterThanOrEqual(2);
  });
});
