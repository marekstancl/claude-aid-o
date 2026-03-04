/**
 * Integration tests for the Pipeline Theater REST API route.
 *
 * Tests the GET /api/p/:projectId/pipeline/theater/:epicId/:runId endpoint
 * defined in packages/aid-server/src/routes/pipeline.ts.
 *
 * Test strategy:
 *   - Uses a mini Express app with a mock ProjectRegistry (Pattern 1).
 *   - Each test uses its own tmpDir so there is zero cross-test state.
 *   - The mock registry implements the FsReader surface required by pipelineRoutes:
 *     readJson, readJsonl, exists, listDir.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import express from 'express';
import request from 'supertest';
import { pipelineRoutes } from '../../../../aid-server/src/routes/pipeline.ts';
import type { ProjectRegistry } from '../../../../aid-server/src/services/project-registry.ts';

// ---------------------------------------------------------------------------
// Setup / Teardown
// ---------------------------------------------------------------------------

let tmpDir: string;
let aidoDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'pipeline-theater-test-'));
  aidoDir = path.join(tmpDir, '.aid-o');
  await fs.mkdir(path.join(aidoDir, 'work', 'evidence'), { recursive: true });
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Mock registry
// ---------------------------------------------------------------------------

/**
 * Creates a mock ProjectRegistry whose FsReader performs real file-system
 * operations. Implements the full method surface used by pipelineRoutes:
 *   exists, readJson, readJsonl, listDir, readYaml.
 */
function createMockRegistry(): Record<string, unknown> {
  return {
    getFsReader: (_projectId: string) => ({
      aidoPath: aidoDir,

      async exists(filePath: string): Promise<boolean> {
        try {
          await fs.access(filePath);
          return true;
        } catch {
          return false;
        }
      },

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
          return JSON.parse(text) as T;
        } catch {
          return null;
        }
      },

      async readJsonl<T>(filePath: string): Promise<T[]> {
        try {
          const text = await fs.readFile(filePath, 'utf-8');
          return text
            .split('\n')
            .filter((line) => line.trim())
            .map((line) => {
              try {
                return JSON.parse(line) as T;
              } catch {
                return null;
              }
            })
            .filter((item): item is T => item !== null);
        } catch {
          return [];
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
    }),
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const EVIDENCE_DIR = () => path.join(aidoDir, 'work', 'evidence');

/** Write a text file, creating parent directories as needed. */
async function writeTextFile(filePath: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, 'utf-8');
}

/** Create the Express test app with only the pipeline router mounted. */
function createTestApp(): express.Express {
  const app = express();
  app.use(express.json());
  const registry = createMockRegistry();
  app.use(
    '/api/p/:projectId/pipeline',
    pipelineRoutes(registry as unknown as ProjectRegistry) as any,
  );
  return app;
}

/** Build a minimal plan.json with the given steps. */
function makePlan(epicId: string, runId: string, steps: Array<{ id: string; role?: string; objective?: string }>) {
  return JSON.stringify({
    epicId,
    runId,
    steps: steps.map((s) => ({
      id: s.id,
      role: s.role ?? 'backend',
      objective: s.objective ?? `Objective for ${s.id}`,
      dependsOn: [],
    })),
  });
}

/** Build a state.yaml (v2 FSM format: state + current_step index). */
function makeState(fsmState: string, currentStep: number, totalSteps?: number) {
  return JSON.stringify({
    state: fsmState,
    current_step: currentStep,
    total_steps: totalSteps ?? currentStep,
  });
}

// ===========================================================================
// PIPELINE THEATER TESTS
// ===========================================================================

describe('Pipeline Theater — GET /api/p/:projectId/pipeline/theater/:epicId/:runId', () => {
  it('returns 404 when the run directory does not exist', async () => {
    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-999')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('E-001');
    expect(res.body.error.message).toContain('run-999');
  });

  it('returns 404 when the run directory exists but plan.json is missing', async () => {
    // Create the run directory without plan.json
    await fs.mkdir(
      path.join(EVIDENCE_DIR(), 'E-001', 'run-001'),
      { recursive: true },
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(404);

    expect(res.body.ok).toBe(false);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(res.body.error.message).toContain('plan.json');
  });

  it('returns theater data when plan.json exists but state.yaml is absent', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [
        { id: 'step_1_architect', role: 'architect', objective: 'Design API' },
        { id: 'step_2_backend', role: 'backend', objective: 'Implement endpoints' },
      ]),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const data = res.body.data;
    expect(data.epicId).toBe('E-001');
    expect(data.runId).toBe('run-001');
    expect(data.totalSteps).toBe(2);
    expect(data.completedSteps).toBe(0);
    // All steps should be pending (no progress data)
    expect(data.steps[0].status).toBe('pending');
    expect(data.steps[1].status).toBe('pending');
  });

  it('returns theater data with merged plan and progress when both files exist', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [
        { id: 'step_1_architect', role: 'architect', objective: 'Design API' },
        { id: 'step_2_backend', role: 'backend', objective: 'Implement endpoints' },
      ]),
    );
    // v2: current_step=1 means step 0 is done, step 1 is executing (FSM state EXECUTE)
    await writeTextFile(
      path.join(runDir, 'state.yaml'),
      makeState('EXECUTE', 1, 2),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const { data } = res.body;
    expect(data.totalSteps).toBe(2);
    expect(data.completedSteps).toBe(1); // step 0 is done (idx < current_step)

    const step1 = data.steps.find((s: { id: string }) => s.id === 'step_1_architect');
    expect(step1.role).toBe('architect');
    expect(step1.status).toBe('done');       // idx 0 < current_step 1
    expect(step1.objective).toBe('Design API');

    const step2 = data.steps.find((s: { id: string }) => s.id === 'step_2_backend');
    expect(step2.role).toBe('backend');
    expect(step2.status).toBe('executing');  // idx 1 === current_step 1, FSM=EXECUTE
  });

  it('counts completedSteps based on steps before current_step index', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [
        { id: 'step_1' },
        { id: 'step_2' },
        { id: 'step_3' },
      ]),
    );
    // v2: current_step=2 means steps 0 and 1 are done, step 2 is executing
    await writeTextFile(
      path.join(runDir, 'state.yaml'),
      makeState('EXECUTE', 2, 3),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.completedSteps).toBe(2);
    expect(res.body.data.totalSteps).toBe(3);
  });

  it('derives overallStatus as "done" when all steps are complete', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [{ id: 'step_1' }, { id: 'step_2' }]),
    );
    // v2: current_step=2 with 2 total steps means all steps done
    await writeTextFile(
      path.join(runDir, 'state.yaml'),
      makeState('DONE', 2, 2),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.overallStatus).toBe('done');
  });

  it('derives overallStatus as "EXECUTE" when FSM state is EXECUTE', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [{ id: 'step_1' }, { id: 'step_2' }]),
    );
    // v2: FSM state EXECUTE, current_step=1 (step 0 done, step 1 active)
    await writeTextFile(
      path.join(runDir, 'state.yaml'),
      makeState('EXECUTE', 1, 2),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.overallStatus).toBe('EXECUTE');
  });

  it('parses and includes timeline.jsonl entries when present', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [{ id: 'step_1' }]),
    );

    const logEntries = [
      { timestamp: '2026-02-25T10:00:00Z', state: 'PLANNING', action: 'start', result: 'pass' },
      { timestamp: '2026-02-25T10:01:00Z', state: 'EXECUTING', step: 'step_1', action: 'dispatch', result: 'success' },
    ];
    await writeTextFile(
      path.join(runDir, 'timeline.jsonl'),
      logEntries.map((e) => JSON.stringify(e)).join('\n') + '\n',
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data.timeline)).toBe(true);
    expect(res.body.data.timeline).toHaveLength(2);
    expect(res.body.data.timeline[0].action).toBe('start');
    expect(res.body.data.timeline[1].action).toBe('dispatch');
    expect(res.body.data.timeline[1].step).toBe('step_1');
  });

  it('returns an empty timeline array when timeline.jsonl is absent', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [{ id: 'step_1' }]),
    );
    // No timeline.jsonl written

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(Array.isArray(res.body.data.timeline)).toBe(true);
    expect(res.body.data.timeline).toHaveLength(0);
  });

  it('preserves plan step order in the theater steps array', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [
        { id: 'step_1_architect', role: 'architect' },
        { id: 'step_2_backend', role: 'backend' },
        { id: 'step_3_qa', role: 'qa' },
      ]),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    const ids = res.body.data.steps.map((s: { id: string }) => s.id);
    expect(ids).toEqual(['step_1_architect', 'step_2_backend', 'step_3_qa']);
  });

  it('returns epicId and runId in the response data', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-42');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-42', [{ id: 'step_1' }]),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-42')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.epicId).toBe('E-001');
    expect(res.body.data.runId).toBe('run-42');
  });

  it('returns totalSteps and completedSteps as numbers in the response', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [{ id: 'step_1' }, { id: 'step_2' }, { id: 'step_3' }]),
    );
    // v2: current_step=1 means step 0 is done
    await writeTextFile(
      path.join(runDir, 'state.yaml'),
      makeState('EXECUTE', 1, 3),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(typeof res.body.data.totalSteps).toBe('number');
    expect(typeof res.body.data.completedSteps).toBe('number');
    expect(res.body.data.totalSteps).toBe(3);
    expect(res.body.data.completedSteps).toBe(1);
  });

  it('returns overallStatus matching FSM state for error/escalation states', async () => {
    const runDir = path.join(EVIDENCE_DIR(), 'E-001', 'run-001');
    await writeTextFile(
      path.join(runDir, 'plan.json'),
      makePlan('E-001', 'run-001', [{ id: 'step_1' }, { id: 'step_2' }]),
    );
    // v2: FSM state ESCALATION — overallStatus reflects the FSM state directly
    await writeTextFile(
      path.join(runDir, 'state.yaml'),
      makeState('ESCALATION', 1, 2),
    );

    const res = await request(createTestApp())
      .get('/api/p/default/pipeline/theater/E-001/run-001')
      .expect(200);

    expect(res.body.ok).toBe(true);
    expect(res.body.data.overallStatus).toBe('ESCALATION');
  });
});
