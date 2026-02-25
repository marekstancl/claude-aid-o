/**
 * Express router for plan file endpoints.
 *
 * GET /          — List all plans (summary entries)
 * GET /:planId   — Full parsed plan content
 *
 * Source directory: `{aidoPath}/01-plans/`
 */

import { Router } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk, send404 } from './middleware.ts';
import { parseMarkdownWithFrontmatter } from '../parsers/index.ts';
import type { PlanListEntry } from '../types.ts';

const router = Router();

/**
 * Extract a human-readable title from parsed Markdown.
 *
 * Priority:
 *   1. `title` field in frontmatter
 *   2. First H1 heading in the body
 *   3. Filename without extension (fallback)
 */
function extractTitle(
  frontmatter: Record<string, unknown> | null,
  body: string,
  filename: string,
): string {
  // Try frontmatter title.
  if (
    frontmatter &&
    typeof frontmatter.title === 'string' &&
    frontmatter.title.trim()
  ) {
    return frontmatter.title.trim();
  }

  // Try first H1.
  const h1Match = body.match(/^#\s+(.+)$/m);
  if (h1Match) {
    return h1Match[1].trim();
  }

  // Fallback to filename.
  return filename.replace(/\.md$/, '');
}

// ---------------------------------------------------------------------------
// GET / — List all plans
// ---------------------------------------------------------------------------

router.get('/', async (req, res) => {
  const plansDir = path.join(req.aidoPath, '01-plans');

  let files: string[];
  try {
    files = await fs.readdir(plansDir);
  } catch {
    // Directory does not exist or is unreadable — return empty list.
    sendOk<PlanListEntry[]>(res, [], { total: 0 });
    return;
  }

  const mdFiles = files.filter(
    (f) => f.endsWith('.md') && !f.startsWith('.'),
  );

  if (mdFiles.length === 0) {
    sendOk<PlanListEntry[]>(res, [], { total: 0 });
    return;
  }

  const entries: PlanListEntry[] = [];
  const warnings: string[] = [];

  for (const file of mdFiles) {
    const filePath = path.join(plansDir, file);
    try {
      const content = await fs.readFile(filePath, 'utf-8');
      const result = parseMarkdownWithFrontmatter<Record<string, unknown>>(
        content,
        filePath,
      );

      const frontmatter = result.data?.frontmatter ?? null;
      const body = result.data?.body ?? '';

      entries.push({
        planId: file.replace(/\.md$/, ''),
        title: extractTitle(frontmatter, body, file),
        filename: file,
      });

      // Collect parser warnings.
      for (const w of result.warnings) {
        if (w.severity === 'error') {
          warnings.push(`${file}: ${w.message}`);
        }
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      warnings.push(`Error reading ${file}: ${msg}`);
    }
  }

  sendOk<PlanListEntry[]>(res, entries, {
    total: entries.length,
    ...(warnings.length > 0 && { warnings }),
  });
});

// ---------------------------------------------------------------------------
// GET /:planId — Single plan detail
// ---------------------------------------------------------------------------

router.get('/:planId', async (req, res) => {
  const { planId } = req.params;
  const filePath = path.join(req.aidoPath, '01-plans', `${planId}.md`);

  let content: string;
  try {
    content = await fs.readFile(filePath, 'utf-8');
  } catch {
    send404(res, `Plan "${planId}"`);
    return;
  }

  const result = parseMarkdownWithFrontmatter<Record<string, unknown>>(
    content,
    filePath,
  );

  const warnings =
    result.warnings.length > 0
      ? result.warnings.map((w) => w.message)
      : undefined;

  sendOk(res, result.data, {
    ...(warnings && { warnings }),
  });
});

export default router;
