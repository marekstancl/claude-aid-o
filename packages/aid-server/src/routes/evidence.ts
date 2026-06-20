import { Router, type Request } from 'express';
import { join, sep } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import { isValidPathComponent, type ProjectParams, type EvidenceFileParams } from './types.js';

export function evidenceRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/evidence
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    const epicDirs = await fs.listDir(evidenceBase);
    const result: any[] = [];

    for (const epicDir of epicDirs) {
      const runs = await fs.listDir(join(evidenceBase, epicDir));
      const runEntries: any[] = [];

      for (const run of runs) {
        const runPath = join(evidenceBase, epicDir, run);
        const files = await fs.listDirRecursive(runPath);
        runEntries.push({
          runId: run,
          files,
          hasTimeline: files.includes('timeline.jsonl'),
          hasPlan: files.includes('plan.json'),
          hasGatesReport: files.some((f) => f.includes('gates')),
        });
      }

      result.push({
        epicId: epicDir,
        runs: runEntries,
      });
    }

    res.json({ ok: true, data: result });
  });

  // GET /api/p/:projectId/evidence/:epicId/:runId/files/*
  router.get('/:epicId/:runId/files/*', async (req: Request<EvidenceFileParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const filePath = req.params['0'] ?? '';
    if (!filePath) return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'File path required' } });

    if (!isValidPathComponent(req.params.epicId) || !isValidPathComponent(req.params.runId)) {
      return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'Invalid epicId or runId' } });
    }

    const fullPath = join(fs.aidoPath, 'work', 'evidence', req.params.epicId, req.params.runId, filePath);

    // Security: ensure path doesn't escape evidence dir (trailing sep prevents /evidence-secret prefix match).
    const evidenceBase = join(fs.aidoPath, 'work', 'evidence');
    if (!fullPath.startsWith(evidenceBase + sep)) {
      return res.status(403).json({ ok: false, error: { code: 'FORBIDDEN', message: 'Path traversal not allowed' } });
    }

    const exists = await fs.exists(fullPath);
    if (!exists) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'File not found' } });

    const { format, content } = await fs.readParsed(fullPath);
    res.json({ ok: true, data: { filePath, format, content } });
  });

  return router;
}
