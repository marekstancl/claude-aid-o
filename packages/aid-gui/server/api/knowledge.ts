/**
 * Express router for the knowledge inventory endpoint.
 *
 * GET / — List skills, agents, and commands from the plugin directory.
 *
 * Source directories (relative to project root, NOT .aid-o/):
 *   - plugins/aid-orchestrator/skills/*.md       — skills
 *   - plugins/aid-orchestrator/agents/*.md       — agent types
 *   - plugins/aid-orchestrator/defaults/commands/*.md — commands
 */

import { Router } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { sendOk } from './middleware.ts';
import { parseMarkdownWithFrontmatter } from '../parsers/index.ts';
import type { KnowledgeItem } from '../types.ts';

const router = Router();

/**
 * Derive the project root from the aidoPath.
 *
 * The aidoPath typically points to `{project}/.aid-o/`, so the project root
 * is one level up. For the monorepo, the plugin lives at the repository root,
 * which is the grandparent of `.aid-o/`.
 */
function deriveProjectRoot(aidoPath: string): string {
  // aidoPath is typically `/path/to/project/.aid-o`
  // Project root is the parent directory.
  return path.dirname(aidoPath);
}

/**
 * Map a directory name to a KnowledgeItem type.
 */
function dirToType(dirName: string): KnowledgeItem['type'] {
  switch (dirName) {
    case 'skills':
      return 'skill';
    case 'agents':
      return 'agent';
    case 'commands':
      return 'command';
    default:
      return 'skill';
  }
}

/**
 * Extract a short description from parsed Markdown content.
 *
 * Priority:
 *   1. `description` field in frontmatter
 *   2. First non-empty paragraph in the body (after any H1 heading)
 *   3. Empty string fallback
 */
function extractDescription(
  frontmatter: Record<string, unknown> | null,
  body: string,
): string {
  // Try frontmatter description.
  if (
    frontmatter &&
    typeof frontmatter.description === 'string' &&
    frontmatter.description.trim()
  ) {
    return frontmatter.description.trim();
  }

  // Try first non-empty paragraph after optional H1.
  const lines = body.split('\n');
  let pastHeading = false;

  for (const line of lines) {
    const trimmed = line.trim();

    // Skip empty lines.
    if (!trimmed) {
      if (pastHeading) continue;
      continue;
    }

    // Skip H1 heading.
    if (trimmed.startsWith('# ')) {
      pastHeading = true;
      continue;
    }

    // Skip other headings.
    if (trimmed.startsWith('#')) {
      pastHeading = true;
      continue;
    }

    // Skip horizontal rules and metadata lines.
    if (trimmed.startsWith('---') || trimmed.startsWith('**Last Updated')) {
      continue;
    }

    // Found a paragraph line — return it (truncated to a reasonable length).
    return trimmed.length > 200 ? trimmed.slice(0, 200) + '...' : trimmed;
  }

  return '';
}

interface ScanTarget {
  dir: string;
  type: KnowledgeItem['type'];
}

// ---------------------------------------------------------------------------
// GET / — Knowledge inventory
// ---------------------------------------------------------------------------

router.get('/', async (req, res) => {
  const projectRoot = deriveProjectRoot(req.aidoPath);
  const pluginBase = path.join(projectRoot, 'plugins', 'aid-orchestrator');

  const targets: ScanTarget[] = [
    { dir: path.join(pluginBase, 'skills'), type: 'skill' },
    { dir: path.join(pluginBase, 'agents'), type: 'agent' },
    { dir: path.join(pluginBase, 'defaults', 'commands'), type: 'command' },
  ];

  // Check if the plugin directory exists at all.
  try {
    await fs.access(pluginBase);
  } catch {
    // Plugin directory does not exist — return empty inventory.
    sendOk<KnowledgeItem[]>(res, [], { total: 0 });
    return;
  }

  const items: KnowledgeItem[] = [];
  const warnings: string[] = [];

  for (const target of targets) {
    let files: string[];
    try {
      files = await fs.readdir(target.dir);
    } catch {
      // Directory does not exist or is unreadable — skip.
      continue;
    }

    const mdFiles = files.filter(
      (f) => f.endsWith('.md') && !f.startsWith('.'),
    );

    for (const file of mdFiles) {
      const filePath = path.join(target.dir, file);
      try {
        const content = await fs.readFile(filePath, 'utf-8');
        const result = parseMarkdownWithFrontmatter<Record<string, unknown>>(
          content,
          filePath,
        );

        const frontmatter = result.data?.frontmatter ?? null;
        const body = result.data?.body ?? '';

        items.push({
          type: target.type,
          name: file.replace(/\.md$/, ''),
          description: extractDescription(frontmatter, body),
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
  }

  sendOk<KnowledgeItem[]>(res, items, {
    total: items.length,
    ...(warnings.length > 0 && { warnings }),
  });
});

export default router;
