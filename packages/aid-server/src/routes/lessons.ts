import { Router, type Request } from 'express';
import { join } from 'node:path';
import type { ProjectRegistry } from '../services/project-registry.js';
import type { ProjectParams } from './types.js';

export interface LessonEntry {
  id: string;
  lesson: string;
  context: string;
  impact: string;
  category: 'lesson';
}

export interface GotchaEntry {
  id: string;
  gotcha: string;
  when: string;
  workaround: string;
  category: 'gotcha';
}

export type LessonOrGotcha = LessonEntry | GotchaEntry;

/**
 * Parse lessons-learned.md into LessonOrGotcha[].
 *
 * The file contains two tables:
 *   "Lessons Learned" — columns: | # | Lesson | Context | Impact |
 *   "Known Gotchas"   — columns: | # | Gotcha | When | Workaround |
 *
 * We detect which table we are in by tracking section headers (## headings).
 */
function parseLessonsFile(text: string): LessonOrGotcha[] {
  const entries: LessonOrGotcha[] = [];
  const lines = text.split('\n');

  let section: 'lesson' | 'gotcha' | null = null;

  for (const line of lines) {
    const trimmed = line.trim();

    // Detect section headers
    if (/^##\s+.*lessons\s+learned/i.test(trimmed)) {
      section = 'lesson';
      continue;
    }
    if (/^##\s+.*known\s+gotchas/i.test(trimmed)) {
      section = 'gotcha';
      continue;
    }
    // A new ## heading that is neither resets section (stop parsing previous table)
    if (/^##\s+/.test(trimmed) && section !== null) {
      section = null;
      continue;
    }

    if (section === null) continue;

    // Skip non-table lines and separator rows
    if (!trimmed.startsWith('|')) continue;
    if (trimmed.includes('|---|')) continue;

    const cells = trimmed
      .split('|')
      .map((c) => c.trim())
      .filter((c) => c.length > 0);

    // Both tables have exactly 4 columns
    if (cells.length !== 4) continue;

    const [id, col2, col3, col4] = cells;

    // Skip header rows
    if (id === '#' || id.toLowerCase() === 'no') continue;

    if (section === 'lesson') {
      entries.push({ id, lesson: col2, context: col3, impact: col4, category: 'lesson' });
    } else {
      entries.push({ id, gotcha: col2, when: col3, workaround: col4, category: 'gotcha' });
    }
  }

  return entries;
}

export function lessonsRoutes(registry: ProjectRegistry): Router {
  const router = Router({ mergeParams: true });

  // GET /api/p/:projectId/lessons
  router.get('/', async (req: Request<ProjectParams>, res) => {
    const fs = registry.getFsReader(req.params.projectId);
    if (!fs) return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'Project not found' } });

    const filePath = join(fs.aidoPath, '04-engine', 'lessons-learned.md');
    const text = await fs.readText(filePath);

    if (!text) {
      return res.json({ ok: true, data: [] });
    }

    const data = parseLessonsFile(text);
    res.json({ ok: true, data });
  });

  return router;
}
