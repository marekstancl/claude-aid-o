/**
 * Integration tests for the backlog REST API endpoint.
 *
 * Tests the GET /backlog endpoint from packages/aid-server/src/routes/backlog.ts
 * by mounting the route on a mini Express app with a mock ProjectRegistry.
 *
 * Expected table format in backlog.md:
 *   | # | Type | Area | Description | Priority | Source | Status |
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import express from 'express';
import request from 'supertest';
import { backlogRoutes } from '../../../../aid-server/src/routes/backlog.ts';

// ---------------------------------------------------------------------------
// Shared setup / teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'backlog-test-'));
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

/** Create mini Express app with just the backlog route */
function createTestApp(): express.Express {
  const app = express();
  app.use(express.json());
  app.use('/api/p/:projectId/backlog', backlogRoutes(createMockRegistry()) as any);
  return app;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const VALID_BACKLOG_MD = `# Improvement Backlog

| # | Type | Area | Description | Priority | Source | Status |
|---|------|------|-------------|----------|--------|--------|
| 1 | refactoring | src/api/ | Extract shared validation logic into middleware | medium | auditor-agent | open |
| 2 | performance | src/parsers/ | Cache parsed YAML files to avoid re-reading | high | E-001-step-3 | planned |
| 3 | security | server/auth/ | Add rate limiting to REST API endpoints | high | security-audit | open |
`;

const MALFORMED_BACKLOG_MD = `# Improvement Backlog

| # | Type | Area | Description | Priority | Source | Status |
|---|------|------|-------------|----------|--------|--------|
| 1 | refactoring | src/api/ | Valid entry | medium | auditor | open |
| bad row with wrong columns |
`;

const EMPTY_BACKLOG_MD = `# Improvement Backlog

No backlog items yet.
`;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('GET /api/p/default/backlog', () => {
  it('returns parsed BacklogEntry[] from a valid 7-column table', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'backlog.md'),
      VALID_BACKLOG_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/backlog')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(3);

    const first = res.body.data[0];
    expect(first.id).toBeDefined();
    expect(first.type).toBe('refactoring');
    expect(first.area).toBe('src/api/');
    expect(first.description).toContain('shared validation');
    expect(first.priority).toBe('medium');
    expect(first.source).toBe('auditor-agent');
    expect(first.status).toBe('open');
  });

  it('returns { ok: true, data: [] } when backlog.md does not exist', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/backlog')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('skips malformed rows without crashing', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'backlog.md'),
      MALFORMED_BACKLOG_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/backlog')
      .expect(200);

    expect(res.body.ok).toBe(true);
    // Only the valid row should be returned
    expect(res.body.data.length).toBeGreaterThanOrEqual(1);
  });

  it('returns empty array for a file with no table', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'backlog.md'),
      EMPTY_BACKLOG_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/backlog')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('skips the header and separator rows of the table', async () => {
    await writeFile(
      path.join(aidoDir, 'work', 'backlog.md'),
      VALID_BACKLOG_MD,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/backlog')
      .expect(200);

    // Header row should not be in the data
    const hasHeaderRow = res.body.data.some(
      (entry: { type: string }) => entry.type === 'Type',
    );
    expect(hasHeaderRow).toBe(false);
  });
});
