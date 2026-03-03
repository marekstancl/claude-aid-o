import { Router, type Request } from 'express';
import { join } from 'node:path';
import { appendFile, mkdir } from 'node:fs/promises';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export function decisionRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/decisions
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const logPath = join(fs.aidoPath, 'work', 'decisions.jsonl');
    const entries = await fs.readJsonl(logPath);
    res.json({ ok: true, data: entries, meta: { total: entries.length } });
  });

  // GET /api/p/:projectId/decisions/pending
  router.get('/pending', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const pendingPath = join(fs.aidoPath, 'work', 'pending-decisions.jsonl');
    const entries = await fs.readJsonl(pendingPath);
    res.json({ ok: true, data: entries });
  });

  // POST /api/p/:projectId/decisions
  router.post('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const { epicId, runId, decision, feedback } = req.body;
    if (!epicId || !decision) {
      return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'epicId and decision are required' } });
    }

    const entry = {
      timestamp: new Date().toISOString(),
      type: 'decision',
      epicId,
      runId: runId ?? null,
      decision,
      feedback: feedback ?? null,
      channel: 'gui',
      approver: 'pm',
      mode: 'manual',
    };

    const logPath = join(fs.aidoPath, 'work', 'decisions.jsonl');
    await mkdir(join(fs.aidoPath, 'work'), { recursive: true });
    await appendFile(logPath, JSON.stringify(entry) + '\n', 'utf-8');

    res.json({ ok: true, data: entry });
  });

  return router;
}
