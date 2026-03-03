import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export function usageRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/usage
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const autoState = await fs.readYaml<any>(join(fs.aidoPath, 'work', 'auto-mode-state.yaml'));
    const agg = autoState?.session?.aggregate;

    // Aggregate from evidence directories
    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const perEpic: any[] = [];

    for (const epicDir of epicDirs.filter((d) => d.startsWith('E-'))) {
      const runs = await fs.listDir(join(evidenceBase, epicDir));
      for (const run of runs) {
        const logEntries = await fs.readJsonl(join(evidenceBase, epicDir, run, 'timeline.jsonl'));
        perEpic.push({
          epicId: epicDir,
          runId: run,
          events: logEntries.length,
          durationSeconds: 0,
        });
      }
    }

    res.json({
      ok: true,
      data: {
        totalEvents: agg?.total_steps_executed ?? perEpic.reduce((sum, e) => sum + e.events, 0),
        agentDispatches: agg?.total_steps_executed ?? 0,
        gateEvaluations: agg?.total_gate_runs ?? 0,
        escalations: agg?.total_escalations ?? 0,
        perEpic,
      },
    });
  });

  return router;
}
