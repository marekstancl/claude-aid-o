/**
 * Pipeline REST API router.
 *
 * Provides endpoints for querying the current orchestration pipeline state,
 * step list, and stage log entries. All data is read from the `.aid-o/`
 * directory structure on the filesystem.
 *
 * Mounted at: /api/projects/:projectId/pipeline
 */

import { Router, type Request, type Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, send404, sendError, findActiveRun } from './middleware.ts';
import { parseYaml, parseJson, parseJsonl } from '../parsers/index.ts';
import type {
  PipelineState,
  PlanProgress,
  PlanJSON,
  StageLogEntry,
} from '../types.ts';

const router = Router();

// ---------------------------------------------------------------------------
// GET / — Pipeline state
// ---------------------------------------------------------------------------

router.get('/', async (req: Request, res: Response): Promise<void> => {
  const aidoPath = req.aidoPath;

  try {
    // Read auto-mode-state.yaml for current FSM state.
    let currentState = 'IDLE';
    let currentEpicId: string | null = null;
    let currentStepId: string | null = null;
    let session: PipelineState['session'] = undefined;

    const statePath = path.join(aidoPath, 'work', 'auto-mode-state.yaml');
    try {
      const stateContent = await fs.readFile(statePath, 'utf-8');
      const stateResult = parseYaml<Record<string, unknown>>(stateContent, statePath);
      if (stateResult.data) {
        const data = stateResult.data;
        currentState = (data.currentState as string) ?? (data.state as string) ?? 'IDLE';
        currentEpicId = (data.currentEpicId as string) ?? null;
        currentStepId = (data.currentStepId as string) ?? (data.currentStep as string) ?? null;

        // Extract session info if present.
        if (data.session && typeof data.session === 'object') {
          session = data.session as PipelineState['session'];
        }
      }
    } catch {
      // auto-mode-state.yaml does not exist — pipeline is idle.
    }

    // Read state.yaml from the active run for progress counters.
    let progress: PipelineState['progress'] = {
      epicsCompleted: 0,
      epicsTotal: 0,
      stepsCompleted: 0,
      stepsTotal: 0,
    };

    const activeRun = await findActiveRun(aidoPath);
    if (activeRun) {
      // Override epicId from active run if not set from state file.
      if (!currentEpicId) {
        currentEpicId = activeRun.epicId;
      }

      const progressPath = path.join(activeRun.evidencePath, 'state.yaml');
      try {
        const progressContent = await fs.readFile(progressPath, 'utf-8');
        const progressResult = parseYaml<PlanProgress>(progressContent, progressPath);
        if (progressResult.data) {
          const pp = progressResult.data;

          // Override state from progress if state file did not provide one.
          if (currentState === 'IDLE' && pp.state) {
            currentState = pp.state;
          }

          // Override currentStep from progress if not set.
          if (!currentStepId && pp.currentStep) {
            currentStepId = pp.currentStep;
          }

          // Compute step progress counters.
          const stepEntries = Object.values(pp.steps ?? {});
          progress = {
            epicsCompleted: session?.aggregate?.epicsCompleted ?? 0,
            epicsTotal: session?.aggregate
              ? (session.aggregate.epicsCompleted + session.aggregate.epicsFailed)
              : (currentEpicId ? 1 : 0),
            stepsCompleted: stepEntries.filter(
              (s) => s.status === 'done' || s.status === 'skipped',
            ).length,
            stepsTotal: stepEntries.length,
          };
        }
      } catch {
        // state.yaml may not exist yet if run just started.
      }
    }

    const pipelineState: PipelineState = {
      currentState,
      currentEpicId,
      currentStepId,
      session,
      progress,
    };

    sendOk(res, pipelineState);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading pipeline state';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /steps — Step list from plan.json
// ---------------------------------------------------------------------------

router.get('/steps', async (req: Request, res: Response): Promise<void> => {
  const aidoPath = req.aidoPath;

  try {
    const activeRun = await findActiveRun(aidoPath);
    if (!activeRun) {
      send404(res, 'Active run');
      return;
    }

    const planPath = path.join(activeRun.evidencePath, 'plan.json');
    let planContent: string;
    try {
      planContent = await fs.readFile(planPath, 'utf-8');
    } catch {
      send404(res, 'plan.json');
      return;
    }

    const planResult = parseJson<PlanJSON>(planContent, planPath);
    if (!planResult.data) {
      sendError(res, 500, 'PARSE_ERROR', 'Failed to parse plan.json', planResult.warnings);
      return;
    }

    const meta = planResult.warnings.length > 0
      ? { warnings: planResult.warnings.map((w) => w.message) }
      : undefined;

    sendOk(res, planResult.data.steps, meta);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading steps';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

// ---------------------------------------------------------------------------
// GET /stage-log — Stage log entries
// ---------------------------------------------------------------------------

router.get('/stage-log', async (req: Request, res: Response): Promise<void> => {
  const aidoPath = req.aidoPath;

  try {
    const activeRun = await findActiveRun(aidoPath);
    if (!activeRun) {
      send404(res, 'Active run');
      return;
    }

    const stageLogPath = path.join(activeRun.evidencePath, 'timeline.jsonl');
    let logContent: string;
    try {
      logContent = await fs.readFile(stageLogPath, 'utf-8');
    } catch {
      send404(res, 'timeline.jsonl');
      return;
    }

    const logResult = parseJsonl<StageLogEntry>(logContent, stageLogPath);
    const entries = logResult.data ?? [];

    // Apply limit — default 100, clamped to 1..10000.
    const rawLimit = req.query.limit;
    let limit = 100;
    if (typeof rawLimit === 'string') {
      const parsed = parseInt(rawLimit, 10);
      if (!isNaN(parsed) && parsed > 0) {
        limit = Math.min(parsed, 10000);
      }
    }

    // Return the last `limit` entries (most recent).
    const sliced = entries.slice(-limit);

    const meta: { total: number; warnings?: string[] } = { total: entries.length };
    if (logResult.warnings.length > 0) {
      meta.warnings = logResult.warnings.map((w) => w.message);
    }

    sendOk(res, sliced, meta);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error reading stage log';
    sendError(res, 500, 'INTERNAL_ERROR', message);
  }
});

export default router;
