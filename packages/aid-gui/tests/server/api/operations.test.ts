/**
 * Integration tests for the Decisions, Audit, Queue, and Usage REST API routes.
 *
 * Uses supertest against a fresh Express app created via createApp().
 * Each test gets its own temporary .aid-o/ directory to avoid cross-test
 * contamination. The AID_PROJECT_PATH environment variable is set to point
 * the project resolver middleware at the temp directory.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import request from 'supertest';
import { createApp } from '../../../server/index.ts';
import { invalidateActiveRunCache } from '../../../server/api/middleware.ts';

// ---------------------------------------------------------------------------
// Shared setup / teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'api-ops-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  process.env.AID_PROJECT_PATH = aidoDir;
  invalidateActiveRunCache();
});

afterEach(async () => {
  delete process.env.AID_PROJECT_PATH;
  invalidateActiveRunCache();
  await fs.rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Create directories recursively and return the leaf path. */
async function mkdirs(...segments: string[]): Promise<string> {
  const dirPath = path.join(...segments);
  await fs.mkdir(dirPath, { recursive: true });
  return dirPath;
}

/** Write a file, creating parent directories if needed. */
async function writeFile(filePath: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, 'utf-8');
}

const ENGINE_DIR = () => path.join(aidoDir, 'work');
const EVIDENCE_DIR = () => path.join(ENGINE_DIR(), 'evidence');
const CONFIG_DIR = () => path.join(aidoDir, 'config');

// ===========================================================================
// DECISIONS TESTS
// ===========================================================================

describe('Decisions API -- GET /api/p/:projectId/decisions', () => {
  it('returns empty array when no evidence directory exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/decisions')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns decision history when pm_decision.json files exist', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(runDir, 'pm_decision.json'),
      JSON.stringify({
        decision: 'GO',
        timestamp: '2026-01-01T00:00:00Z',
        approver: 'pm',
      }),
    );

    const res = await request(createApp())
      .get('/api/p/default/decisions')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].decision).toBe('GO');
    expect(res.body.data[0].timestamp).toBe('2026-01-01T00:00:00Z');
    expect(res.body.data[0].approver).toBe('pm');
    // epicId and runId should be enriched from path.
    expect(res.body.data[0].epicId).toBe('E-001');
    expect(res.body.data[0].runId).toBe('run1');
    // type should default to 'decision' for pm_decision.json.
    expect(res.body.data[0].type).toBe('decision');
    expect(res.body.meta.total).toBe(1);
  });

  it('returns pm_plan_approval.json files with type plan_approval', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-002', 'run1');
    await writeFile(
      path.join(runDir, 'pm_plan_approval.json'),
      JSON.stringify({
        timestamp: '2026-01-02T00:00:00Z',
        approver: 'auto-mode',
        validation: { schema: 'pass' },
      }),
    );

    const res = await request(createApp())
      .get('/api/p/default/decisions')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].type).toBe('plan_approval');
    expect(res.body.data[0].epicId).toBe('E-002');
  });

  it('sorts decisions by timestamp descending (newest first)', async () => {
    const run1Dir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(run1Dir, 'pm_decision.json'),
      JSON.stringify({
        decision: 'GO',
        timestamp: '2026-01-01T00:00:00Z',
      }),
    );

    const run2Dir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run2');
    await writeFile(
      path.join(run2Dir, 'pm_decision.json'),
      JSON.stringify({
        decision: 'STOP',
        timestamp: '2026-02-01T00:00:00Z',
      }),
    );

    const res = await request(createApp())
      .get('/api/p/default/decisions')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);
    // Newest first.
    expect(res.body.data[0].decision).toBe('STOP');
    expect(res.body.data[1].decision).toBe('GO');
  });
});

describe('Decisions API -- GET /api/p/:projectId/decisions/pending', () => {
  it('returns empty array when no evidence directory exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/decisions/pending')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns empty array when all runs have decisions', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(runDir, 'state.yaml'),
      JSON.stringify({
        epicId: 'E-001',
        runId: 'run1',
        state: 'PM_APPROVAL',
        currentStep: null,
        steps: {},
      }),
    );
    // Already has a decision, so it should NOT be pending.
    await writeFile(
      path.join(runDir, 'pm_decision.json'),
      JSON.stringify({ decision: 'GO', timestamp: '2026-01-01T00:00:00Z' }),
    );

    const res = await request(createApp())
      .get('/api/p/default/decisions/pending')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('returns pending decisions for runs awaiting PM approval', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(runDir, 'state.yaml'),
      JSON.stringify({
        epicId: 'E-001',
        runId: 'run1',
        state: 'PM_APPROVAL',
        currentStep: null,
        steps: {},
      }),
    );
    // No pm_decision.json -- so this run is pending.

    const res = await request(createApp())
      .get('/api/p/default/decisions/pending')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].epicId).toBe('E-001');
    expect(res.body.data[0].runId).toBe('run1');
    expect(res.body.data[0].state).toBe('PM_APPROVAL');
    expect(res.body.meta.total).toBe(1);
  });
});

describe('Decisions API -- POST /api/p/:projectId/decisions', () => {
  it('creates decision file atomically when evidence dir exists', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');

    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({ epicId: 'E-001', runId: 'run1', decision: 'GO' })
      .expect(201);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-001');
    expect(res.body.data.runId).toBe('run1');
    expect(res.body.data.decision).toBe('GO');
    expect(res.body.data.channel).toBe('gui');
    expect(res.body.data.type).toBe('decision');
    expect(res.body.data.timestamp).toBeDefined();

    // Verify the file was actually written to disk.
    const written = JSON.parse(
      await fs.readFile(path.join(runDir, 'pm_decision.json'), 'utf-8'),
    );
    expect(written.decision).toBe('GO');
    expect(written.epicId).toBe('E-001');
  });

  it('includes feedback when provided', async () => {
    await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');

    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({
        epicId: 'E-001',
        runId: 'run1',
        decision: 'GO',
        feedback: 'Looks good, proceed.',
      })
      .expect(201);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.feedback).toBe('Looks good, proceed.');
  });

  it('returns 400 when epicId is missing', async () => {
    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({ runId: 'run1', decision: 'GO' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('epicId');
  });

  it('returns 400 when runId is missing', async () => {
    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({ epicId: 'E-001', decision: 'GO' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('runId');
  });

  it('returns 400 when decision is missing', async () => {
    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({ epicId: 'E-001', runId: 'run1' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('decision');
  });

  it('returns 400 when body is empty', async () => {
    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({})
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 404 for nonexistent evidence directory', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .post('/api/p/default/decisions')
      .send({ epicId: 'E-999', runId: 'run1', decision: 'GO' })
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('E-999');
  });
});

// ===========================================================================
// AUDIT TESTS
// ===========================================================================

describe('Audit API -- GET /api/p/:projectId/audit', () => {
  it('returns empty array when no evidence directory exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/audit')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
    expect(res.body.meta.total).toBe(0);
  });

  it('returns audit reports when audit-report.yaml files exist', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(runDir, 'audit-report.yaml'),
      [
        'score: 85',
        'status: pass',
        'epic_id: E-001',
        'timestamp: "2026-01-15T00:00:00Z"',
        'auditor: auditor-agent',
        'scores:',
        '  overall: 85',
        '  code_quality: 80',
        '  security: 90',
        '  documentation: 75',
        '  process: 85',
        '  frontend: null',
        '  database: null',
        'findings: []',
      ].join('\n'),
    );

    const res = await request(createApp())
      .get('/api/p/default/audit')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(1);
    expect(res.body.data[0].epicId).toBe('E-001');
    expect(res.body.data[0].score).toBe(85);
    expect(res.body.data[0].status).toBe('pass');
    expect(res.body.meta.total).toBe(1);
  });

  it('returns audit reports from multiple EPICs sorted by timestamp', async () => {
    const run1Dir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(run1Dir, 'audit-report.yaml'),
      [
        'timestamp: "2026-01-01T00:00:00Z"',
        'auditor: auditor-agent',
        'score: 75',
        'scores:',
        '  overall: 75',
        'findings: []',
      ].join('\n'),
    );

    const run2Dir = await mkdirs(EVIDENCE_DIR(), 'E-002', 'run1');
    await writeFile(
      path.join(run2Dir, 'audit-report.yaml'),
      [
        'timestamp: "2026-02-01T00:00:00Z"',
        'auditor: auditor-agent',
        'score: 90',
        'scores:',
        '  overall: 90',
        'findings: []',
      ].join('\n'),
    );

    const res = await request(createApp())
      .get('/api/p/default/audit')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toHaveLength(2);
    // Newest first.
    expect(res.body.data[0].timestamp).toBe('2026-02-01T00:00:00Z');
    expect(res.body.data[1].timestamp).toBe('2026-01-01T00:00:00Z');
    expect(res.body.meta.total).toBe(2);
  });
});

describe('Audit API -- GET /api/p/:projectId/audit/:epicId', () => {
  it('returns audit report for a specific EPIC', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(runDir, 'audit-report.yaml'),
      [
        'timestamp: "2026-01-15T00:00:00Z"',
        'auditor: auditor-agent',
        'score: 85',
        'scores:',
        '  overall: 85',
        '  code_quality: 80',
        'findings:',
        '  - category: code_quality',
        '    severity: medium',
        '    description: Missing error handling',
      ].join('\n'),
    );

    const res = await request(createApp())
      .get('/api/p/default/audit/E-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-001');
    expect(res.body.data.score).toBe(85);
    expect(res.body.data.auditor).toBe('auditor-agent');
  });

  it('returns 404 for nonexistent EPIC', async () => {
    await mkdirs(EVIDENCE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/audit/nonexistent')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('nonexistent');
  });

  it('returns 404 when EPIC dir exists but has no audit report', async () => {
    await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');

    const res = await request(createApp())
      .get('/api/p/default/audit/E-001')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

// ===========================================================================
// QUEUE TESTS
// ===========================================================================

describe('Queue API -- GET /api/p/:projectId/queue', () => {
  it('returns 404 when no queue file exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/queue')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns queue state when queue.yaml exists', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
        '    started_at: null',
        '    completed_at: null',
      ].join('\n'),
    );

    const res = await request(createApp())
      .get('/api/p/default/queue')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.paused).toBe(false);
    expect(res.body.data.queue).toHaveLength(1);
    expect(res.body.data.queue[0].epicId).toBe('E-001');
    expect(res.body.data.queue[0].path).toBe('.aid-o/tasks/E-001.md');
    expect(res.body.data.queue[0].priority).toBe('high');
    expect(res.body.data.queue[0].status).toBe('queued');
    expect(res.body.data.queue[0].addedAt).toBe('2026-01-01T00:00:00Z');
  });

  it('returns queue with multiple entries', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
        '  - epic_id: E-002',
        '    path: .aid-o/tasks/E-002.md',
        '    priority: medium',
        '    status: running',
        '    added_at: "2026-01-02T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .get('/api/p/default/queue')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.queue).toHaveLength(2);
    expect(res.body.data.queue[0].epicId).toBe('E-001');
    expect(res.body.data.queue[1].epicId).toBe('E-002');
    expect(res.body.data.queue[1].priority).toBe('medium');
    expect(res.body.data.queue[1].status).toBe('running');
  });
});

describe('Queue API -- POST /api/p/:projectId/queue', () => {
  it('adds an entry to the queue when no queue file exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .post('/api/p/default/queue')
      .send({ epicId: 'E-002', path: '.aid-o/tasks/E-002.md' })
      .expect(201);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-002');
    expect(res.body.data.path).toBe('.aid-o/tasks/E-002.md');
    expect(res.body.data.priority).toBe('medium'); // default priority
    expect(res.body.data.status).toBe('queued');
    expect(res.body.data.addedAt).toBeDefined();

    // Verify the file was created on disk.
    const content = await fs.readFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      'utf-8',
    );
    expect(content).toContain('E-002');
  });

  it('adds an entry to an existing queue', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .post('/api/p/default/queue')
      .send({
        epicId: 'E-002',
        path: '.aid-o/tasks/E-002.md',
        priority: 'critical',
      })
      .expect(201);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-002');
    expect(res.body.data.priority).toBe('critical');

    // Verify both entries exist in the file.
    const readRes = await request(createApp())
      .get('/api/p/default/queue')
      .expect(200);

    expect(readRes.body.data.queue).toHaveLength(2);
  });

  it('returns 400 when epicId is missing', async () => {
    const res = await request(createApp())
      .post('/api/p/default/queue')
      .send({ path: '.aid-o/tasks/E-002.md' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('epicId');
  });

  it('returns 400 when path is missing', async () => {
    const res = await request(createApp())
      .post('/api/p/default/queue')
      .send({ epicId: 'E-002' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('path');
  });

  it('returns 400 for invalid priority', async () => {
    const res = await request(createApp())
      .post('/api/p/default/queue')
      .send({
        epicId: 'E-002',
        path: '.aid-o/tasks/E-002.md',
        priority: 'ultra',
      })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('priority');
  });

  it('returns 400 for duplicate epicId', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .post('/api/p/default/queue')
      .send({ epicId: 'E-001', path: '.aid-o/tasks/E-001.md' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('already exists');
  });
});

describe('Queue API -- PUT /api/p/:projectId/queue/:epicId', () => {
  it('updates entry priority', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: medium',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .put('/api/p/default/queue/E-001')
      .send({ priority: 'critical' })
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-001');
    expect(res.body.data.priority).toBe('critical');

    // Verify persistence by re-reading.
    const readRes = await request(createApp())
      .get('/api/p/default/queue')
      .expect(200);

    expect(readRes.body.data.queue[0].priority).toBe('critical');
  });

  it('updates entry status', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .put('/api/p/default/queue/E-001')
      .send({ status: 'running' })
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.status).toBe('running');
  });

  it('returns 400 when no fields are provided', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .put('/api/p/default/queue/E-001')
      .send({})
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
  });

  it('returns 400 for invalid priority value', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .put('/api/p/default/queue/E-001')
      .send({ priority: 'mega' })
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.message).toContain('priority');
  });

  it('returns 404 when queue file does not exist', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .put('/api/p/default/queue/E-001')
      .send({ priority: 'high' })
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns 404 when epicId is not found in queue', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .put('/api/p/default/queue/E-999')
      .send({ priority: 'low' })
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('E-999');
  });
});

describe('Queue API -- DELETE /api/p/:projectId/queue/:epicId', () => {
  it('removes a queued entry', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
        '  - epic_id: E-002',
        '    path: .aid-o/tasks/E-002.md',
        '    priority: medium',
        '    status: queued',
        '    added_at: "2026-01-02T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .delete('/api/p/default/queue/E-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-001');

    // Verify only E-002 remains.
    const readRes = await request(createApp())
      .get('/api/p/default/queue')
      .expect(200);

    expect(readRes.body.data.queue).toHaveLength(1);
    expect(readRes.body.data.queue[0].epicId).toBe('E-002');
  });

  it('returns 400 when trying to remove a non-queued (running) entry', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: running',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .delete('/api/p/default/queue/E-001')
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('running');
    expect(res.body.error.message).toContain('queued');
  });

  it('returns 400 when trying to remove a completed entry', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: completed',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .delete('/api/p/default/queue/E-001')
      .expect(400);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.message).toContain('completed');
  });

  it('returns 404 when queue file does not exist', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .delete('/api/p/default/queue/E-001')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns 404 when epicId is not found in queue', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(
      path.join(CONFIG_DIR(), 'queue.yaml'),
      [
        'paused: false',
        'queue:',
        '  - epic_id: E-001',
        '    path: .aid-o/tasks/E-001.md',
        '    priority: high',
        '    status: queued',
        '    added_at: "2026-01-01T00:00:00Z"',
      ].join('\n'),
    );

    const res = await request(createApp())
      .delete('/api/p/default/queue/E-999')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('E-999');
  });
});

// ===========================================================================
// USAGE TESTS
// ===========================================================================

describe('Usage API -- GET /api/p/:projectId/usage', () => {
  it('returns zero metrics when no evidence directory exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/usage')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.totalEvents).toBe(0);
    expect(res.body.data.agentDispatches).toBe(0);
    expect(res.body.data.gateEvaluations).toBe(0);
    expect(res.body.data.escalations).toBe(0);
    expect(res.body.data.perEpic).toEqual([]);
  });

  it('returns zero metrics when evidence directory exists but has no stage logs', async () => {
    // Create evidence directories without timeline.jsonl files.
    await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');

    const res = await request(createApp())
      .get('/api/p/default/usage')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.totalEvents).toBe(0);
    expect(res.body.data.perEpic).toEqual([]);
  });

  it('returns aggregated metrics when timeline.jsonl exists', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    const entries = [
      {
        timestamp: '2026-01-01T00:00:00Z',
        state: 'PLANNING',
        step: null,
        action: 'start_planning',
        details: 'Planning started',
        result: 'pass',
      },
      {
        timestamp: '2026-01-01T00:01:00Z',
        state: 'EXECUTING',
        step: 'step_1',
        action: 'dispatch_agent',
        details: 'Dispatched architect',
        result: 'pass',
      },
      {
        timestamp: '2026-01-01T00:02:00Z',
        state: 'EXECUTING',
        step: 'step_2',
        action: 'dispatch_agent',
        details: 'Dispatched backend',
        result: 'pass',
      },
      {
        timestamp: '2026-01-01T00:03:00Z',
        state: 'GATES',
        step: null,
        action: 'gate_evaluation',
        details: 'Running quality gates',
        result: 'pass',
      },
      {
        timestamp: '2026-01-01T00:04:00Z',
        state: 'ESCALATION',
        step: null,
        action: 'escalation_triggered',
        details: 'Budget exceeded',
        result: 'fail',
      },
    ];
    await writeFile(
      path.join(runDir, 'timeline.jsonl'),
      entries.map((e) => JSON.stringify(e)).join('\n') + '\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/usage')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.totalEvents).toBe(5);
    expect(res.body.data.agentDispatches).toBe(2); // 2 dispatch_agent
    expect(res.body.data.gateEvaluations).toBe(1); // 1 gate_evaluation
    expect(res.body.data.escalations).toBe(1); // 1 escalation_triggered
    expect(res.body.data.perEpic).toHaveLength(1);
    expect(res.body.data.perEpic[0].epicId).toBe('E-001');
    expect(res.body.data.perEpic[0].runId).toBe('run1');
    expect(res.body.data.perEpic[0].events).toBe(5);
    // Duration: from 00:00 to 00:04 = 240 seconds.
    expect(res.body.data.perEpic[0].durationSeconds).toBe(240);
  });

  it('aggregates metrics across multiple EPICs and runs', async () => {
    // EPIC 1, run 1.
    const run1Dir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(run1Dir, 'timeline.jsonl'),
      [
        JSON.stringify({
          timestamp: '2026-01-01T00:00:00Z',
          state: 'EXECUTING',
          step: 'step_1',
          action: 'dispatch_agent',
          details: 'test',
          result: 'pass',
        }),
        JSON.stringify({
          timestamp: '2026-01-01T00:05:00Z',
          state: 'GATES',
          step: null,
          action: 'gate_evaluation',
          details: 'test',
          result: 'pass',
        }),
      ].join('\n') + '\n',
    );

    // EPIC 2, run 1.
    const run2Dir = await mkdirs(EVIDENCE_DIR(), 'E-002', 'run1');
    await writeFile(
      path.join(run2Dir, 'timeline.jsonl'),
      [
        JSON.stringify({
          timestamp: '2026-01-02T00:00:00Z',
          state: 'EXECUTING',
          step: 'step_1',
          action: 'dispatch_agent',
          details: 'test',
          result: 'pass',
        }),
      ].join('\n') + '\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/usage')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.totalEvents).toBe(3); // 2 + 1
    expect(res.body.data.agentDispatches).toBe(2); // 1 + 1
    expect(res.body.data.gateEvaluations).toBe(1); // 1 + 0
    expect(res.body.data.perEpic).toHaveLength(2);

    const e001 = res.body.data.perEpic.find(
      (e: { epicId: string }) => e.epicId === 'E-001',
    );
    expect(e001).toBeDefined();
    expect(e001.events).toBe(2);
    expect(e001.durationSeconds).toBe(300); // 5 minutes

    const e002 = res.body.data.perEpic.find(
      (e: { epicId: string }) => e.epicId === 'E-002',
    );
    expect(e002).toBeDefined();
    expect(e002.events).toBe(1);
    expect(e002.durationSeconds).toBe(0); // single entry, no duration
  });

  it('handles malformed JSONL lines gracefully', async () => {
    const runDir = await mkdirs(EVIDENCE_DIR(), 'E-001', 'run1');
    await writeFile(
      path.join(runDir, 'timeline.jsonl'),
      [
        JSON.stringify({
          timestamp: '2026-01-01T00:00:00Z',
          state: 'EXECUTING',
          step: 'step_1',
          action: 'dispatch_agent',
          details: 'test',
          result: 'pass',
        }),
        '{ this is not valid JSON }',
        JSON.stringify({
          timestamp: '2026-01-01T00:01:00Z',
          state: 'GATES',
          step: null,
          action: 'gate_check',
          details: 'test',
          result: 'pass',
        }),
      ].join('\n') + '\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/usage')
      .expect(200);

    expect(res.body.ok).toBe(true);
    // The valid lines should still be counted.
    expect(res.body.data.totalEvents).toBeGreaterThanOrEqual(2);
  });
});
