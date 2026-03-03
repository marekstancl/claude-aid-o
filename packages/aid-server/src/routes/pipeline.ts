import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';
import { validateEvidencePath } from './path-validation.js';

export function pipelineRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/pipeline
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const autoState = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'auto-mode-state.yaml'));
    const queue = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'epic-queue.yaml'));

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

  // GET /api/p/:projectId/pipeline/step-statuses
  // Returns plan_progress.json for the current running EPIC — per-step status data.
  router.get('/step-statuses', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const queue = await fs.readYaml<any>(join(fs.aidoPath, '04-engine', 'epic-queue.yaml'));
    const runningEpic = queue?.queue?.find((e: any) => e.status === 'running');
    if (!runningEpic) return res.json({ ok: true, data: {} });

    const evidenceBase = join(fs.aidoPath, '04-engine', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const epicDir = epicDirs.find((d) => d.startsWith(runningEpic.epic_id));
    if (!epicDir) return res.json({ ok: true, data: {} });

    const runs = await fs.listDir(join(evidenceBase, epicDir));
    const latestRun = runs.sort().pop();
    if (!latestRun) return res.json({ ok: true, data: {} });

    const progress = await fs.readJson<any>(join(evidenceBase, epicDir, latestRun, 'plan_progress.json'));
    // Convert array format [{id, status, ...}] to map {id: {status, ...}}
    if (Array.isArray(progress)) {
      const map: Record<string, any> = {};
      for (const s of progress) {
        if (s.id) map[s.id] = { status: s.status, startedAt: s.started_at, completedAt: s.completed_at };
      }
      return res.json({ ok: true, data: map });
    }
    res.json({ ok: true, data: progress?.steps ?? progress ?? {} });
  });

  // GET /api/p/:projectId/pipeline/theater/:epicId/:runId
  router.get('/theater/:epicId/:runId', async (req: Request<ProjectParams & { epicId: string; runId: string }>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const { epicId, runId } = req.params;

    // Defense-in-depth: validate path components before constructing any path.
    // Layer 1 (regex): rejects ".", "/", "\" to block traversal sequences.
    // Layer 2 (resolve+startsWith): confirms the joined path stays within the
    //   evidence base after OS-level canonicalization.
    // CWE-22: Path Traversal — prevents reading files outside evidence/.
    const evidenceBase = join(fs.aidoPath, '04-engine', 'evidence');
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

    // Read plan_progress.json (optional -- may not exist yet)
    const progress = await fs.readJson<any>(join(runDir, 'plan_progress.json'));

    // Read stage_log.jsonl (optional)
    const stageLog = await fs.readJsonl<any>(join(runDir, 'stage_log.jsonl'));

    // Build step progress map from plan_progress.json
    const progressSteps: Record<string, any> = progress?.steps ?? {};

    // Merge plan steps with progress data
    const planSteps: any[] = plan.steps ?? [];
    const steps = planSteps.map((step: any) => {
      const stepProgress = progressSteps[step.id] ?? {};
      const startedAt = stepProgress.startedAt ?? stepProgress.started_at ?? null;
      const completedAt = stepProgress.completedAt ?? stepProgress.completed_at ?? null;

      let durationMs: number | null = null;
      if (startedAt && completedAt) {
        const startMs = new Date(startedAt).getTime();
        const endMs = new Date(completedAt).getTime();
        if (Number.isFinite(startMs) && Number.isFinite(endMs)) {
          durationMs = endMs - startMs;
        }
      }

      return {
        id: step.id,
        role: step.role ?? 'unknown',
        status: stepProgress.status ?? 'pending',
        startedAt,
        completedAt,
        durationMs,
        objective: step.objective ?? '',
      };
    });

    const completedSteps = steps.filter((s: any) => s.status === 'done' || s.status === 'completed').length;

    // Determine overall status from progress state or derive from steps
    let overallStatus = progress?.state ?? 'pending';
    if (completedSteps === steps.length && steps.length > 0) {
      overallStatus = 'done';
    } else if (steps.some((s: any) => s.status === 'executing' || s.status === 'in_progress')) {
      overallStatus = 'executing';
    } else if (steps.some((s: any) => s.status === 'failed')) {
      overallStatus = 'failed';
    }

    res.json({
      ok: true,
      data: {
        epicId,
        runId,
        steps,
        stageLog,
        totalSteps: steps.length,
        completedSteps,
        overallStatus,
      },
    });
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
