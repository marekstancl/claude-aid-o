import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';
import { validateEvidencePath } from './path-validation.js';
import type { AidStateYaml, AidTimelineEntry } from '@aid/contract';

export function pipelineRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/pipeline
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const autoState = await fs.readYaml<any>(join(fs.aidoPath, 'work', 'auto-mode-state.yaml'));
    const queue = await fs.readYaml<any>(join(fs.aidoPath, 'config', 'queue.yaml'));

    const runningEpic = queue?.queue?.find((e: any) => e.status === 'running');

    // Derive stepsTotal from per-EPIC plan step counts in aggregate data
    const perEpic: any[] = autoState?.session?.aggregate?.per_epic ?? [];
    const stepsTotal = perEpic.reduce((sum: number, e: any) => sum + (e.steps_total ?? e.steps_executed ?? 0), 0);

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
          startedBy: autoState.session.started_by ?? 'pm',
          queueSnapshot: autoState.session.queue_snapshot ?? [],
          escalation: {
            budget: autoState.session.escalation?.budget ?? 0,
            count: autoState.session.escalation?.count ?? 0,
          },
          aggregate: {
            epicsCompleted: autoState.session.aggregate?.epics_completed ?? 0,
            epicsFailed: autoState.session.aggregate?.epics_failed ?? 0,
            totalStepsExecuted: autoState.session.aggregate?.total_steps_executed ?? 0,
            totalGateRuns: autoState.session.aggregate?.total_gate_runs ?? 0,
            totalGateRetries: autoState.session.aggregate?.total_gate_retries ?? 0,
            totalEscalations: autoState.session.aggregate?.total_escalations ?? 0,
          },
        } : null,
        progress: {
          epicsCompleted: autoState?.session?.aggregate?.epics_completed ?? 0,
          epicsTotal: autoState?.session?.progress?.epics_total ?? 0,
          stepsCompleted: autoState?.session?.aggregate?.total_steps_executed ?? 0,
          stepsTotal: stepsTotal || (autoState?.session?.aggregate?.total_steps_executed ?? 0),
        },
      },
    });
  });

  // GET /api/p/:projectId/pipeline/steps
  router.get('/steps', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    // Find current running epic and its plan
    const queue = await fs.readYaml<any>(join(fs.aidoPath, 'config', 'queue.yaml'));
    const runningEpic = queue?.queue?.find((e: any) => e.status === 'running');

    if (!runningEpic) {
      return res.json({ ok: true, data: [] });
    }

    // Find evidence dir for the epic
    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
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

  // GET /api/p/:projectId/pipeline/step-statuses
  // Returns state.yaml for the current running EPIC — per-step status data.
  router.get('/step-statuses', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const queue = await fs.readYaml<any>(join(fs.aidoPath, 'config', 'queue.yaml'));
    const runningEpic = queue?.queue?.find((e: any) => e.status === 'running');
    if (!runningEpic) return res.json({ ok: true, data: {} });

    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const epicDir = epicDirs.find((d) => d.startsWith(runningEpic.epic_id));
    if (!epicDir) return res.json({ ok: true, data: {} });

    const runs = await fs.listDir(join(evidenceBase, epicDir));
    const latestRun = runs.sort().pop();
    if (!latestRun) return res.json({ ok: true, data: {} });

    const state = await fs.readYaml<AidStateYaml>(join(evidenceBase, epicDir, latestRun, 'state.yaml'));
    res.json({ ok: true, data: state ?? {} });
  });

  // GET /api/p/:projectId/pipeline/theater/:epicId/:runId
  router.get('/theater/:epicId/:runId', async (req: Request<ProjectParams & { epicId: string; runId: string }>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const { epicId, runId } = req.params;

    // Defense-in-depth: validate path components before constructing any path.
    // CWE-22: Path Traversal — prevents reading files outside evidence/.
    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const validation = validateEvidencePath(evidenceBase, epicId, runId);
    if (!validation.ok) {
      return res.status(400).json({
        ok: false,
        error: { code: 'INVALID_PATH', message: validation.reason },
      });
    }

    const runDir = validation.resolvedPath;

    // Verify the run directory exists
    const runDirExists = await fs.exists(runDir);
    if (!runDirExists) {
      return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: `Run directory not found: ${epicId}/${runId}` } });
    }

    // Read plan.json (required)
    const planPath = join(runDir, 'plan.json');
    const plan = await fs.readJson<any>(planPath);
    if (!plan) {
      return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: `plan.json not found in ${epicId}/${runId}` } });
    }

    // Read state.yaml (optional -- may not exist yet)
    const state = await fs.readYaml<AidStateYaml>(join(runDir, 'state.yaml'));

    // Read timeline.jsonl (optional)
    const timeline = await fs.readJsonl<AidTimelineEntry>(join(runDir, 'timeline.jsonl'));

    // Build step progress from state
    const planSteps: any[] = plan.steps ?? [];
    const currentStep = state?.current_step ?? 0;
    const steps = planSteps.map((step: any, idx: number) => {
      const isDone = idx < currentStep;
      const isActive = idx === currentStep && state?.state === 'EXECUTE';
      return {
        id: step.id,
        role: step.role ?? 'unknown',
        status: isDone ? 'done' : isActive ? 'executing' : 'pending',
        objective: step.objective ?? '',
      };
    });

    const completedSteps = steps.filter((s) => s.status === 'done').length;

    // Determine overall status from state
    let overallStatus: string = state?.state ?? 'pending';
    if (completedSteps === steps.length && steps.length > 0) {
      overallStatus = 'done';
    }

    res.json({
      ok: true,
      data: {
        epicId,
        runId,
        steps,
        timeline,
        totalSteps: steps.length,
        completedSteps,
        overallStatus,
      },
    });
  });

  // GET /api/p/:projectId/pipeline/timeline
  router.get('/timeline', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    // Collect timeline entries from all evidence dirs
    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const allEntries: AidTimelineEntry[] = [];

    for (const epicDir of epicDirs.slice(-5)) { // last 5 epics
      const runs = await fs.listDir(join(evidenceBase, epicDir));
      for (const run of runs) {
        const logPath = join(evidenceBase, epicDir, run, 'timeline.jsonl');
        const entries = await fs.readJsonl<AidTimelineEntry>(logPath);
        allEntries.push(...entries);
      }
    }

    // Sort by timestamp
    allEntries.sort((a, b) => (a.ts ?? '').localeCompare(b.ts ?? ''));

    res.json({ ok: true, data: allEntries });
  });

  // GET /api/p/:projectId/pipeline/stage-log (backward compat alias)
  router.get('/stage-log', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const allEntries: AidTimelineEntry[] = [];

    for (const epicDir of epicDirs.slice(-5)) {
      const runs = await fs.listDir(join(evidenceBase, epicDir));
      for (const run of runs) {
        const logPath = join(evidenceBase, epicDir, run, 'timeline.jsonl');
        const entries = await fs.readJsonl<AidTimelineEntry>(logPath);
        allEntries.push(...entries);
      }
    }

    allEntries.sort((a, b) => (a.ts ?? '').localeCompare(b.ts ?? ''));
    res.json({ ok: true, data: allEntries });
  });

  return router;
}
