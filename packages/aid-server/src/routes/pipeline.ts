import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export function pipelineRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/pipeline
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const autoState = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'auto-mode-state.yaml'));
    const queue = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'epic-queue.yaml'));

    const runningEpic = queue?.queue?.find((e: any) => e.status === 'running');

    res.json({
      ok: true,
      data: {
        currentState: autoState?.session?.progress?.current_state ?? 'IDLE',
        currentEpicId: runningEpic?.epic_id ?? autoState?.session?.progress?.current_epic_id ?? null,
        currentStepId: autoState?.session?.progress?.current_step_id ?? null,
        autoModeSession: autoState?.session ? {
          sessionId: autoState.session.session_id,
          mode: autoState.session.mode,
          startedAt: autoState.session.started_at,
        } : null,
        progress: {
          epicsCompleted: autoState?.session?.aggregate?.epics_completed ?? 0,
          epicsTotal: autoState?.session?.progress?.epics_total ?? 0,
          stepsCompleted: autoState?.session?.aggregate?.total_steps_executed ?? 0,
          stepsTotal: autoState?.session?.aggregate?.total_steps_executed ?? 0,
        },
      },
    });
  });

  // GET /api/p/:projectId/pipeline/steps
  router.get('/steps', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    // Find current running epic and its plan
    const queue = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'epic-queue.yaml'));
    const runningEpic = queue?.queue?.find((e: any) => e.status === 'running');

    if (!runningEpic) {
      return res.json({ ok: true, data: [] });
    }

    // Find evidence dir for the epic
    const evidenceBase = join(fs.aidoPath, '04-engine', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const epicDir = epicDirs.find((d) => d.startsWith(runningEpic.epic_id));

    if (!epicDir) return res.json({ ok: true, data: [] });

    // Find latest run
    const runs = await fs.listDir(join(evidenceBase, epicDir));
    const latestRun = runs.sort().pop();
    if (!latestRun) return res.json({ ok: true, data: [] });

    const plan = await fs.readJson<any>(join(evidenceBase, epicDir, latestRun, 'plan.json'));
    res.json({ ok: true, data: plan?.steps ?? [] });
  });

  // GET /api/p/:projectId/pipeline/stage-log
  router.get('/stage-log', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    // Collect stage logs from all evidence dirs
    const evidenceBase = join(fs.aidoPath, '04-engine', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const allEntries: any[] = [];

    for (const epicDir of epicDirs.slice(-5)) { // last 5 epics
      const runs = await fs.listDir(join(evidenceBase, epicDir));
      for (const run of runs) {
        const logPath = join(evidenceBase, epicDir, run, 'stage_log.jsonl');
        const entries = await fs.readJsonl(logPath);
        allEntries.push(...entries);
      }
    }

    // Sort by timestamp
    allEntries.sort((a: any, b: any) => (a.timestamp ?? '').localeCompare(b.timestamp ?? ''));

    res.json({ ok: true, data: allEntries });
  });

  return router;
}
