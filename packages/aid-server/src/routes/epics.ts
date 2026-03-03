import { Router, type Request } from 'express';
import { join } from 'node:path';
import { readdir, writeFile } from 'node:fs/promises';
import yaml from 'js-yaml';
import type { ProjectRegistry } from '../services/project-registry.js';
import { isValidPathComponent, type ProjectParams, type EpicParams } from './types.js';

export interface EpicMetadata {
  id: string;
  title: string;
  status: string;
  planRef: string | null;
  runsTotal: number;
  runsCompleted: number;
  fileName: string;
  path: string;
}

interface RunBody {
  mode: 'now' | 'schedule';
}

interface QueueEntry {
  epic_id: string;
  path: string;
  priority: string;
  status: string;
  added_at: string;
}

/** Status sort priority — active/running EPICs first, then by name. */
const STATUS_PRIORITY: Record<string, number> = {
  active: 0,
  running: 0,
  in_progress: 1,
  ready: 2,
  draft: 3,
  completed: 4,
  archived: 5,
};

function statusWeight(status: string): number {
  return STATUS_PRIORITY[status.toLowerCase()] ?? 3;
}

/**
 * Parse YAML frontmatter from markdown content.
 * Returns the parsed object or null if no valid frontmatter found.
 */
function parseFrontmatter(content: string): Record<string, unknown> | null {
  const trimmed = content.trimStart();
  if (!trimmed.startsWith('---')) return null;

  const endIdx = trimmed.indexOf('---', 3);
  if (endIdx === -1) return null;

  const yamlBlock = trimmed.slice(3, endIdx).trim();
  if (!yamlBlock) return null;

  try {
    const parsed = yaml.load(yamlBlock);
    return typeof parsed === 'object' && parsed !== null ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

/**
 * Extract the first markdown heading (# Title) from content.
 */
function extractTitle(content: string): string {
  const match = content.match(/^#\s+(.+)$/m);
  return match ? match[1].trim() : 'Untitled';
}

export function epicRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/epics — List all EPICs with parsed metadata
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) {
      return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
    }

    const epicsDir = join(fs.aidoPath, '02-epics');
    let files: string[];
    try {
      files = await readdir(epicsDir);
    } catch {
      // Directory doesn't exist or isn't readable — return empty list
      return res.json({ ok: true, data: [] });
    }

    // Filter to .md files, excluding archive/ subdirectory entries
    const mdFiles = files.filter((f) => f.endsWith('.md') && f !== 'archive');

    const epics: EpicMetadata[] = [];

    for (const fileName of mdFiles) {
      const filePath = join(epicsDir, fileName);
      const content = await fs.readText(filePath);
      if (!content) continue;

      const frontmatter = parseFrontmatter(content);

      const id = (frontmatter?.id as string) ?? fileName.replace(/\.md$/, '');
      const title = extractTitle(content);
      const status = (frontmatter?.status as string) ?? 'draft';
      const planRef = (frontmatter?.plan_ref as string) ?? null;
      const runsTotal = typeof frontmatter?.runs_total === 'number' ? frontmatter.runs_total : 0;
      const runsCompleted = typeof frontmatter?.runs_completed === 'number' ? frontmatter.runs_completed : 0;

      epics.push({
        id,
        title,
        status,
        planRef,
        runsTotal,
        runsCompleted,
        fileName,
        path: `02-epics/${fileName}`,
      });
    }

    // Sort: active/running first, then by filename
    epics.sort((a, b) => {
      const sw = statusWeight(a.status) - statusWeight(b.status);
      if (sw !== 0) return sw;
      return a.fileName.localeCompare(b.fileName);
    });

    res.json({ ok: true, data: epics });
  });

  // POST /api/p/:projectId/epics/:epicId/run — Add EPIC to execution queue
  router.post('/:epicId/run', async (req: Request<EpicParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) {
      return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });
    }

    const { mode } = req.body as RunBody;
    if (!mode || (mode !== 'now' && mode !== 'schedule')) {
      return res.status(400).json({
        ok: false,
        error: { code: 'BAD_REQUEST', message: "mode must be 'now' or 'schedule'" },
      });
    }

    if (!isValidPathComponent(req.params.epicId)) {
      return res.status(400).json({ ok: false, error: { code: 'BAD_REQUEST', message: 'Invalid epicId' } });
    }
    const epicId = req.params.epicId;

    // Verify the EPIC file exists
    const epicsDir = join(fs.aidoPath, '02-epics');
    let epicFileName: string | null = null;
    try {
      const files = await readdir(epicsDir);
      epicFileName = files.find(
        (f) => f.endsWith('.md') && (f === `${epicId}.md` || f.startsWith(`${epicId}-`)),
      ) ?? null;
    } catch {
      // epics dir missing
    }

    if (!epicFileName) {
      return res.status(404).json({
        ok: false,
        error: { code: 'NOT_FOUND', message: `EPIC ${epicId} not found` },
      });
    }

    // Read or initialize the queue
    const queuePath = join(fs.aidoPath, '04-engine', 'epic-queue.yaml');
    const queueData = (await fs.readYaml<{ queue?: QueueEntry[]; paused?: boolean }>(queuePath)) ?? { queue: [] };
    const queue: QueueEntry[] = queueData.queue ?? [];

    // Check if the EPIC is already in the queue with status 'queued'
    const existing = queue.find((e) => e.epic_id === epicId && e.status === 'queued');
    if (existing) {
      return res.status(409).json({
        ok: false,
        error: { code: 'CONFLICT', message: `EPIC ${epicId} is already queued` },
      });
    }

    const newEntry: QueueEntry = {
      epic_id: epicId,
      path: `.aid-o/02-epics/${epicFileName}`,
      priority: mode === 'now' ? 'critical' : 'medium',
      status: 'queued',
      added_at: new Date().toISOString(),
    };

    if (mode === 'now') {
      // Insert at front of queue
      queue.unshift(newEntry);
    } else {
      // Append to end of queue
      queue.push(newEntry);
    }

    // Write updated queue back
    const updatedQueueData = { ...queueData, queue };
    try {
      await writeFile(queuePath, yaml.dump(updatedQueueData), 'utf-8');
    } catch (err) {
      return res.status(500).json({
        ok: false,
        error: { code: 'WRITE_ERROR', message: 'Failed to write queue file' },
      });
    }

    res.json({
      ok: true,
      data: {
        epicId: newEntry.epic_id,
        path: newEntry.path,
        priority: newEntry.priority,
        status: newEntry.status,
        addedAt: newEntry.added_at,
      },
    });
  });

  return router;
}
