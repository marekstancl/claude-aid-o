/**
 * Integration tests for the Evidence Search REST API route.
 *
 * Tests the GET /api/p/:projectId/evidence/search?q=:query endpoint
 * defined in packages/aid-server/src/routes/evidence-search.ts.
 *
 * Test strategy:
 *   - Uses a mini Express app with a mock ProjectRegistry (Pattern 1).
 *   - Each test uses its own tmpDir so there is zero cross-test state.
 *   - Real file-system operations so binary detection and recursive
 *     listing work exactly as in production.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import express from 'express';
import request from 'supertest';
import { evidenceSearchRoutes } from '../../../../aid-server/src/routes/evidence-search.ts';
import type { ProjectRegistry } from '../../../../aid-server/src/services/project-registry.ts';

// ---------------------------------------------------------------------------
// Setup / Teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'evidence-search-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  await fs.mkdir(path.join(aidoDir, '04-engine', 'evidence'), { recursive: true });
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Mock registry
// ---------------------------------------------------------------------------

/**
 * Creates a mock ProjectRegistry that delegates all file-system operations
 * to real Node.js fs calls rooted at `aidoDir`.
 *
 * The mock implements the full FsReader surface used by evidenceSearchRoutes:
 *   listDir, listDirRecursive, readText (used for search + binary detection).
 * Note: isBinaryFile inside the route reads with readFile directly (not via
 * FsReader), so we only need readText for the content search.
 */
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

      async listDir(dirPath: string): Promise<string[]> {
        try {
          const entries = await fs.readdir(dirPath, { withFileTypes: true });
          return entries.map((e) => e.name);
        } catch {
          return [];
        }
      },

      async listDirRecursive(dirPath: string): Promise<string[]> {
        const result: string[] = [];

        async function walk(dir: string, prefix: string): Promise<void> {
          let entries;
          try {
            entries = await fs.readdir(dir, { withFileTypes: true });
          } catch {
            return;
          }
          for (const entry of entries) {
            const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
            if (entry.isDirectory()) {
              await walk(path.join(dir, entry.name), rel);
            } else {
              result.push(rel);
            }
          }
        }

        await walk(dirPath, '');
        return result;
      },
    }),
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const EVIDENCE_DIR = () => path.join(aidoDir, '04-engine', 'evidence');

/** Write a text file, creating parent directories as needed. */
async function writeTextFile(filePath: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, 'utf-8');
}

/** Write a binary file (with null bytes) to trigger binary detection. */
async function writeBinaryFile(filePath: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  const buf = Buffer.alloc(16, 0x00); // all null bytes — clearly binary
  await fs.writeFile(filePath, buf);
}

/** Create a minimal Express app with only the evidence search route mounted. */
function createTestApp(): express.Express {
  const app = express();
  app.use(express.json());
  const registry = createMockRegistry();
  app.use(
    '/api/p/:projectId/evidence',
    evidenceSearchRoutes(registry as unknown as ProjectRegistry) as any,
  );
  return app;
}

// ===========================================================================
// EVIDENCE SEARCH TESTS
// ===========================================================================

describe('Evidence Search — GET /api/p/:projectId/evidence/search', () => {
  it('returns 400 when the q parameter is missing', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search')
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 when the q parameter is an empty string', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=')
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 when q is only whitespace', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=   ')
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns empty results with total 0 when no evidence files exist', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=anything')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.results).toEqual([]);
    expect(res.body.data.total).toBe(0);
    expect(res.body.data.query).toBe('anything');
  });

  it('returns matching results with the correct fields', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'step_output.md'),
      'Line one\nThis line mentions the KEYWORD we are searching for\nLine three\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=KEYWORD')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const { results, total, query, limit } = res.body.data;
    expect(total).toBe(1);
    expect(query).toBe('KEYWORD');
    expect(limit).toBe(50); // default

    const match = results[0];
    expect(match.epicId).toBe('E-001');
    expect(match.runId).toBe('run-001');
    expect(match.filePath).toBe('step_output.md');
    expect(match.matchLine).toBe(2);
    expect(match.context).toBe('This line mentions the KEYWORD we are searching for');
  });

  it('performs case-insensitive search', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      'The word Banana appears here\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=banana')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.total).toBe(1);
    expect(res.body.data.results[0].context).toBe('The word Banana appears here');
  });

  it('respects a custom limit parameter', async () => {
    // Write a file with 10 matching lines
    const lines = Array.from({ length: 10 }, (_, i) => `Match on line ${i + 1}`).join('\n');
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      lines,
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=Match&limit=3')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.results).toHaveLength(3);
    expect(res.body.data.total).toBe(10); // total is all matches, not sliced
    expect(res.body.data.limit).toBe(3);
  });

  it('caps the limit at 200 even when a higher value is requested', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      'just one matching line here\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=matching&limit=999')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.limit).toBe(200);
  });

  it('uses default limit of 50 when limit is not supplied', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      'one matching line\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=matching')
      .expect(200);

    expect(res.body.data.limit).toBe(50);
  });

  it('uses default limit of 50 when limit is zero or negative', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      'one matching line\n',
    );

    const resZero = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=matching&limit=0')
      .expect(200);
    expect(resZero.body.data.limit).toBe(50);

    const resNeg = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=matching&limit=-5')
      .expect(200);
    expect(resNeg.body.data.limit).toBe(50);
  });

  it('skips binary files during search', async () => {
    // Binary file with null bytes — must be skipped
    await writeBinaryFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'artifact.bin'),
    );
    // Text file should still be found
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'notes.txt'),
      'The search target token is here\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=token')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.total).toBe(1);
    // Only the text file should match
    expect(res.body.data.results[0].filePath).toBe('notes.txt');
  });

  it('searches across nested file paths within a run directory', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'steps', 'step_1', 'output.md'),
      'Deep nested content with DEEPTOKEN here\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=DEEPTOKEN')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.total).toBe(1);
    expect(res.body.data.results[0].filePath).toBe('steps/step_1/output.md');
  });

  it('searches across multiple epics and runs', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'a.txt'),
      'First epic first run MULTIMATCH\n',
    );
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-002', 'b.txt'),
      'First epic second run MULTIMATCH\n',
    );
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-002', 'run-001', 'c.txt'),
      'Second epic first run MULTIMATCH\n',
    );
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-002', 'run-001', 'd.txt'),
      'No match here\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=MULTIMATCH')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.total).toBe(3);

    const epicIds = res.body.data.results.map((r: { epicId: string }) => r.epicId);
    expect(epicIds).toContain('E-001');
    expect(epicIds).toContain('E-002');
  });

  it('returns results sorted: epicId ascending, runId descending (newest first), filePath ascending', async () => {
    // E-001 run-002 (newer run — should appear before run-001 within E-001)
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-002', 'alpha.txt'),
      'SORTTOKEN in E-001 run-002\n',
    );
    // E-001 run-001 (older run)
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'beta.txt'),
      'SORTTOKEN in E-001 run-001\n',
    );
    // E-002 (should come after E-001)
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-002', 'run-001', 'gamma.txt'),
      'SORTTOKEN in E-002 run-001\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=SORTTOKEN')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const results = res.body.data.results;
    expect(results).toHaveLength(3);

    // First two should be E-001, with run-002 before run-001 (runId descending)
    expect(results[0].epicId).toBe('E-001');
    expect(results[0].runId).toBe('run-002');
    expect(results[1].epicId).toBe('E-001');
    expect(results[1].runId).toBe('run-001');
    // Third should be E-002
    expect(results[2].epicId).toBe('E-002');
  });

  it('sorts multiple files within the same run by filePath ascending', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'z_last.txt'),
      'FILEPATHSORT match\n',
    );
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'a_first.txt'),
      'FILEPATHSORT match\n',
    );
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'm_middle.txt'),
      'FILEPATHSORT match\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=FILEPATHSORT')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const filePaths = res.body.data.results.map((r: { filePath: string }) => r.filePath);
    expect(filePaths[0]).toBe('a_first.txt');
    expect(filePaths[1]).toBe('m_middle.txt');
    expect(filePaths[2]).toBe('z_last.txt');
  });

  it('reports the 1-based line number of each match correctly', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      'line one no match\nline two no match\nline three has LINENUMBER target\nline four no match\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=LINENUMBER')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.total).toBe(1);
    expect(res.body.data.results[0].matchLine).toBe(3);
  });

  it('trims leading and trailing whitespace from match context', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      '   indented TRIMTOKEN line   \n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=TRIMTOKEN')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.results[0].context).toBe('indented TRIMTOKEN line');
  });

  it('does not expose files outside the evidence base via path traversal in file names', async () => {
    // Create a secret file above the evidence directory
    await writeTextFile(
      path.join(aidoDir, '04-engine', 'secret.txt'),
      'SECRET_DATA\n',
    );
    // Create a normal evidence file for the run
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'normal.txt'),
      'normal content here\n',
    );

    // Search for something in the secret file — it should never appear in results
    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=SECRET_DATA')
      .expect(200);

    expect(res.body.ok).toBe(true);
    // Secret file is outside the evidence tree so it can never be walked;
    // total must be 0.
    expect(res.body.data.total).toBe(0);
  });

  it('returns multiple matches per file when multiple lines match', async () => {
    await writeTextFile(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001', 'output.txt'),
      'First REPEAT occurrence\nSome other content\nSecond REPEAT occurrence\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=REPEAT')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.total).toBe(2);
    expect(res.body.data.results[0].matchLine).toBe(1);
    expect(res.body.data.results[1].matchLine).toBe(3);
  });

  it('returns correct data shape including query and limit fields', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/evidence/search?q=SHAPE')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveProperty('results');
    expect(res.body.data).toHaveProperty('total');
    expect(res.body.data).toHaveProperty('limit');
    expect(res.body.data).toHaveProperty('query');
    expect(Array.isArray(res.body.data.results)).toBe(true);
    expect(typeof res.body.data.total).toBe('number');
  });
});
