import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export interface BacklogEntry {
  id: string;
  type: string;
  area: string;
  description: string;
  priority: string;
  source: string;
  status: string;
}

/**
 * Parse a markdown table from backlog.md into BacklogEntry[].
 *
 * Expected columns: | # | Type | Area | Description | Priority | Source | Status |
 */
function parseBacklogTable(text: string): BacklogEntry[] {
  const entries: BacklogEntry[] = [];
  const lines = text.split('\n');

  for (const line of lines) {
    const trimmed = line.trim();

    // Skip non-table lines, header separators, and the header row
    if (!trimmed.startsWith('|')) continue;
    if (trimmed.includes('|---|')) continue;

    const cells = trimmed
      .split('|')
      .map((c) => c.trim())
      .filter((c) => c.length > 0);

    // Expect exactly 7 columns: #, Type, Area, Description, Priority, Source, Status
    if (cells.length !== 7) continue;

    const [id, type, area, description, priority, source, status] = cells;

    // Skip the header row (first cell is literally "#" or "No" etc.)
    if (id === '#' || id.toLowerCase() === 'no') continue;

    entries.push({ id, type, area, description, priority, source, status });
  }

  return entries;
}

export function backlogRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/backlog
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const filePath = join(fs.aidoPath, '04-engine', 'backlog.md');
    const text = await fs.readText(filePath);

    if (!text) {
      return res.json({ ok: true, data: [] });
    }

    const data = parseBacklogTable(text);
    res.json({ ok: true, data });
  });

  return router;
}
