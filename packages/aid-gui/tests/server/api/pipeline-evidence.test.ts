/**
 * Integration tests for the Pipeline and Evidence REST API routes.
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
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'api-test-'));
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
const STATE_PATH = () => path.join(ENGINE_DIR(), 'auto-mode-state.yaml');

/** Standard auto-mode-state.yaml content pointing at E-001 in EXECUTING state. */
const AUTO_MODE_STATE_YAML = `session:
  mode: auto
  session_id: FA-test
current_epic_id: E-001
current_state: EXECUTING
`;

/** Create a minimal evidence run directory with common files. */
async function createRunDir(
  epicId: string,
  runId: string,
  opts: {
    plan?: boolean;
    stageLog?: boolean;
    planProgress?: boolean;
    gatesReport?: boolean;
  } = {},
): Promise<string> {
  const runDir = await mkdirs(EVIDENCE_DIR(), epicId, runId);

  if (opts.plan) {
    await writeFile(
      path.join(runDir, 'plan.json'),
      JSON.stringify({
        epicId,
        runId,
        steps: [
          {
            id: 'step_1_architect',
            role: 'architect',
            objective: 'Design the API',
            dependsOn: [],
          },
          {
            id: 'step_2_backend',
            role: 'backend',
            objective: 'Implement endpoints',
            dependsOn: ['step_1_architect'],
          },
        ],
      }),
    );
  }

  if (opts.stageLog) {
    const entries = [
      {
        timestamp: '2026-02-25T10:00:00Z',
        state: 'PLANNING',
        step: null,
        action: 'start_planning',
        details: 'Planning started',
        result: 'pass',
      },
      {
        timestamp: '2026-02-25T10:01:00Z',
        state: 'EXECUTING',
        step: 'step_1_architect',
        action: 'dispatch_agent',
        details: 'Dispatched architect agent',
        result: 'success',
      },
      {
        timestamp: '2026-02-25T10:02:00Z',
        state: 'EXECUTING',
        step: 'step_2_backend',
        action: 'dispatch_agent',
        details: 'Dispatched backend agent',
        result: 'success',
      },
    ];
    await writeFile(
      path.join(runDir, 'timeline.jsonl'),
      entries.map((e) => JSON.stringify(e)).join('\n') + '\n',
    );
  }

  if (opts.planProgress) {
    await writeFile(
      path.join(runDir, 'state.yaml'),
      JSON.stringify({
        epicId,
        runId,
        state: 'EXECUTING',
        currentStep: 'step_2_backend',
        steps: {
          step_1_architect: { status: 'done', startedAt: '2026-02-25T10:00:00Z' },
          step_2_backend: { status: 'executing', startedAt: '2026-02-25T10:01:00Z' },
        },
      }),
    );
  }

  if (opts.gatesReport) {
    await writeFile(
      path.join(runDir, 'gates_report.json'),
      JSON.stringify({
        epicId,
        runId,
        timestamp: '2026-02-25T10:05:00Z',
        gates: [{ name: 'tests_pass', status: 'pass', output: 'OK', attempt: 1 }],
        overall: 'pass',
      }),
    );
  }

  return runDir;
}

// ===========================================================================
// PIPELINE TESTS
// ===========================================================================

describe('Pipeline API — GET /api/p/:projectId/pipeline', () => {
  it('returns IDLE state when no auto-mode-state.yaml exists', async () => {
    // Create the engine directory but not the state file.
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/pipeline')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.currentState).toBe('IDLE');
    expect(res.body.data.currentEpicId).toBeNull();
    expect(res.body.data.currentStepId).toBeNull();
    expect(res.body.data.progress).toEqual({
      epicsCompleted: 0,
      epicsTotal: 0,
      stepsCompleted: 0,
      stepsTotal: 0,
    });
  });

  it('returns pipeline state when auto-mode-state.yaml exists', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(STATE_PATH(), AUTO_MODE_STATE_YAML);
    // Create a run directory so findActiveRun can resolve the evidence path.
    await createRunDir('E-001', 'run1', { planProgress: true });

    const res = await request(createApp())
      .get('/api/p/default/pipeline')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.currentState).toBe('EXECUTING');
    expect(res.body.data.currentEpicId).toBe('E-001');
    expect(res.body.data.currentStepId).toBe('step_2_backend');
    expect(res.body.data.session).toBeDefined();
    expect(res.body.data.session.mode).toBe('auto');
    expect(res.body.data.progress.stepsCompleted).toBe(1);
    expect(res.body.data.progress.stepsTotal).toBe(2);
  });
});

describe('Pipeline API — GET /api/p/:projectId/pipeline/steps', () => {
  it('returns 404 when no active run exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/pipeline/steps')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns step list when plan.json exists in the active run', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(STATE_PATH(), AUTO_MODE_STATE_YAML);
    await createRunDir('E-001', 'run1', { plan: true });

    const res = await request(createApp())
      .get('/api/p/default/pipeline/steps')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.data[0].id).toBe('step_1_architect');
    expect(res.body.data[1].id).toBe('step_2_backend');
    expect(res.body.data[1].dependsOn).toEqual(['step_1_architect']);
  });
});

describe('Pipeline API — GET /api/p/:projectId/pipeline/stage-log', () => {
  it('returns 404 when no active run exists', async () => {
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/pipeline/stage-log')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns stage log entries for the active run', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(STATE_PATH(), AUTO_MODE_STATE_YAML);
    await createRunDir('E-001', 'run1', { stageLog: true });

    const res = await request(createApp())
      .get('/api/p/default/pipeline/stage-log')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data).toHaveLength(3);
    expect(res.body.data[0].action).toBe('start_planning');
    expect(res.body.data[2].action).toBe('dispatch_agent');
    expect(res.body.meta.total).toBe(3);
  });

  it('respects the limit query parameter', async () => {
    await mkdirs(ENGINE_DIR());
    await writeFile(STATE_PATH(), AUTO_MODE_STATE_YAML);
    await createRunDir('E-001', 'run1', { stageLog: true });

    const res = await request(createApp())
      .get('/api/p/default/pipeline/stage-log?limit=2')
      .expect(200);

    expect(res.body.ok).toBe(true);
    // With limit=2, should return the last 2 entries (most recent).
    expect(res.body.data).toHaveLength(2);
    expect(res.body.data[0].action).toBe('dispatch_agent');
    expect(res.body.data[0].step).toBe('step_1_architect');
    expect(res.body.data[1].action).toBe('dispatch_agent');
    expect(res.body.data[1].step).toBe('step_2_backend');
    expect(res.body.meta.total).toBe(3);
  });
});

describe('Pipeline API — non-default projectId', () => {
  it('returns 404 for unknown projectId', async () => {
    const res = await request(createApp())
      .get('/api/p/unknown-project/pipeline')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('PROJECT_NOT_FOUND');
  });
});

// ===========================================================================
// EVIDENCE TESTS
// ===========================================================================

describe('Evidence API — GET /api/p/:projectId/evidence', () => {
  it('returns empty array when no evidence directory exists', async () => {
    // Create engine dir but not the evidence subdirectory.
    await mkdirs(ENGINE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/evidence')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data).toEqual([]);
  });

  it('returns EPIC list with runs', async () => {
    await createRunDir('E-001', 'run1', {
      plan: true,
      stageLog: true,
      gatesReport: true,
    });
    await createRunDir('E-002', 'run1', { plan: true });

    const res = await request(createApp())
      .get('/api/p/default/evidence')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);

    // Find E-001 entry.
    const e001 = res.body.data.find(
      (e: { epicId: string }) => e.epicId === 'E-001',
    );
    expect(e001).toBeDefined();
    expect(e001.runs).toHaveLength(1);
    expect(e001.runs[0].runId).toBe('run1');
    expect(e001.runs[0].hasPlan).toBe(true);
    expect(e001.runs[0].hasStageLog).toBe(true);
    expect(e001.runs[0].hasGatesReport).toBe(true);
    // files should list the top-level file names.
    expect(e001.runs[0].files).toContain('plan.json');
    expect(e001.runs[0].files).toContain('timeline.jsonl');
    expect(e001.runs[0].files).toContain('gates_report.json');

    // Find E-002 entry.
    const e002 = res.body.data.find(
      (e: { epicId: string }) => e.epicId === 'E-002',
    );
    expect(e002).toBeDefined();
    expect(e002.runs).toHaveLength(1);
    expect(e002.runs[0].hasPlan).toBe(true);
    expect(e002.runs[0].hasStageLog).toBe(false);
    expect(e002.runs[0].hasGatesReport).toBe(false);
  });

  it('skips FIRST-AID directories', async () => {
    await createRunDir('E-001', 'run1', { plan: true });
    await mkdirs(EVIDENCE_DIR(), 'FIRST-AID-recovery');
    // Add a file inside FIRST-AID so it is non-empty.
    await writeFile(
      path.join(EVIDENCE_DIR(), 'FIRST-AID-recovery', 'dummy.txt'),
      'recovery data',
    );

    const res = await request(createApp())
      .get('/api/p/default/evidence')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const epicIds = res.body.data.map((e: { epicId: string }) => e.epicId);
    expect(epicIds).toContain('E-001');
    expect(epicIds).not.toContain('FIRST-AID-recovery');
  });
});

describe('Evidence API — GET /api/p/:projectId/evidence/:epicId', () => {
  it('returns 404 for a missing EPIC', async () => {
    await mkdirs(EVIDENCE_DIR());

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-999')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('E-999');
  });

  it('returns runs for an existing EPIC', async () => {
    await createRunDir('E-001', 'run1', { plan: true, stageLog: true });
    await createRunDir('E-001', 'run2', { plan: true });

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data)).toBe(true);
    expect(res.body.data).toHaveLength(2);

    const runIds = res.body.data.map((r: { runId: string }) => r.runId);
    expect(runIds).toContain('run1');
    expect(runIds).toContain('run2');

    const run1 = res.body.data.find((r: { runId: string }) => r.runId === 'run1');
    expect(run1.hasPlan).toBe(true);
    expect(run1.hasStageLog).toBe(true);

    const run2 = res.body.data.find((r: { runId: string }) => r.runId === 'run2');
    expect(run2.hasPlan).toBe(true);
    expect(run2.hasStageLog).toBe(false);
  });
});

describe('Evidence API — GET /api/p/:projectId/evidence/:epicId/:runId', () => {
  it('returns 404 for a missing run', async () => {
    await mkdirs(EVIDENCE_DIR(), 'E-001');

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/nonexistent-run')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('returns file tree for an existing run', async () => {
    const runDir = await createRunDir('E-001', 'run1', {
      plan: true,
      stageLog: true,
    });
    // Add a nested file to test recursive listing.
    await writeFile(
      path.join(runDir, 'steps', 'step_1', 'output.md'),
      '# Step 1 output',
    );

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-001');
    expect(res.body.data.runId).toBe('run1');
    expect(Array.isArray(res.body.data.files)).toBe(true);
    expect(res.body.data.files).toContain('plan.json');
    expect(res.body.data.files).toContain('timeline.jsonl');
    // Nested file should use relative path with OS separator.
    expect(res.body.data.files).toContain(
      path.join('steps', 'step_1', 'output.md'),
    );
  });
});

describe('Evidence API — GET /api/p/:projectId/evidence/:epicId/:runId/files/*', () => {
  it('serves parsed JSON for .json files', async () => {
    await createRunDir('E-001', 'run1', { plan: true });

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/plan.json')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.filePath).toBe('plan.json');
    expect(res.body.data.format).toBe('json');
    expect(res.body.data.content).toBeDefined();
    expect(res.body.data.content.epicId).toBe('E-001');
    expect(Array.isArray(res.body.data.content.steps)).toBe(true);
  });

  it('serves parsed YAML for .yaml files', async () => {
    const runDir = await createRunDir('E-001', 'run1');
    await writeFile(
      path.join(runDir, 'report.yaml'),
      'title: Test Report\nstatus: pass\nitems:\n  - name: check1\n    ok: true\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/report.yaml')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.filePath).toBe('report.yaml');
    expect(res.body.data.format).toBe('yaml');
    expect(res.body.data.content).toBeDefined();
    expect(res.body.data.content.title).toBe('Test Report');
    expect(res.body.data.content.status).toBe('pass');
    expect(Array.isArray(res.body.data.content.items)).toBe(true);
  });

  it('serves parsed markdown for .md files', async () => {
    const runDir = await createRunDir('E-001', 'run1');
    await writeFile(
      path.join(runDir, 'notes.md'),
      '---\nauthor: tester\n---\n# Notes\n\nSome important notes here.\n',
    );

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/notes.md')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.filePath).toBe('notes.md');
    expect(res.body.data.format).toBe('markdown');
    expect(res.body.data.content).toBeDefined();
  });

  it('serves parsed JSONL for .jsonl files', async () => {
    await createRunDir('E-001', 'run1', { stageLog: true });

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/timeline.jsonl')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.filePath).toBe('timeline.jsonl');
    expect(res.body.data.format).toBe('jsonl');
    expect(Array.isArray(res.body.data.content)).toBe(true);
    expect(res.body.data.content).toHaveLength(3);
  });

  it('serves raw text for unknown file extensions', async () => {
    const runDir = await createRunDir('E-001', 'run1');
    await writeFile(path.join(runDir, 'output.log'), 'Line 1\nLine 2\nLine 3\n');

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/output.log')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.filePath).toBe('output.log');
    expect(res.body.data.format).toBe('text');
    expect(res.body.data.content).toContain('Line 1');
  });

  it('returns 404 for a file that does not exist', async () => {
    await createRunDir('E-001', 'run1');

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/nonexistent.json')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('blocks path traversal with ../', async () => {
    await createRunDir('E-001', 'run1');
    // Write a file outside the run directory that an attacker might try to reach.
    await writeFile(path.join(EVIDENCE_DIR(), 'secret.txt'), 'top-secret');

    // Express normalizes URL paths, so ../../ in the URL gets resolved before
    // reaching the route handler. The important thing is that the secret file
    // content is never served. Depending on how the URL is resolved, this may
    // return 400 (if the handler sees the traversal) or 404 (if Express
    // resolves the path to a non-matching route). Either way, ok must be false
    // and the secret content must not be exposed.
    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/../../secret.txt');

    // The response should NOT contain the secret content.
    expect(JSON.stringify(res.body)).not.toContain('top-secret');
    // Should be an error status (400 or 404).
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
  });

  it('blocks absolute path traversal', async () => {
    await createRunDir('E-001', 'run1');

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files//etc/passwd')
      .expect(400);

    expect(res.body.ok).toBe(false);
    // Should be either BAD_REQUEST or NOT_FOUND — the point is it does not serve the file.
    expect(res.body.ok).toBe(false);
  });

  it('serves nested files within the run directory', async () => {
    const runDir = await createRunDir('E-001', 'run1');
    await writeFile(
      path.join(runDir, 'steps', 'step_1', 'output.json'),
      JSON.stringify({ result: 'success' }),
    );

    const res = await request(createApp())
      .get('/api/p/default/evidence/E-001/run1/files/steps/step_1/output.json')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.filePath).toBe('steps/step_1/output.json');
    expect(res.body.data.format).toBe('json');
    expect(res.body.data.content.result).toBe('success');
  });
});
