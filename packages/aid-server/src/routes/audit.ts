import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export function auditRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/audit
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const evidenceBase = join(fs.aidoPath, '04-engine', 'evidence');
    const dirs = await fs.listDir(evidenceBase);
    const auditDirs = dirs.filter((d) => d.startsWith('audit-')).sort().reverse();

    const reports: any[] = [];
    for (const dir of auditDirs.slice(0, 10)) {
      const reportPath = join(evidenceBase, dir, 'audit-report.json');
      const report = await fs.readJson<any>(reportPath);
      if (report) reports.push(report);
    }

    res.json({ ok: true, data: reports });
  });

  return router;
}
