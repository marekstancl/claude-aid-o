/**
 * IDEAS.md migration service.
 *
 * - importFromIdeasMd: reads IDEAS.md at startup, parses ideas, and merges
 *   into ideas.json with deduplication by case-insensitive title.
 * - exportToIdeasMd: writes ideas.json back to IDEAS.md at shutdown,
 *   creating a .bak backup first.
 */

import { readFile, writeFile, mkdir, copyFile } from 'node:fs/promises';
import { join } from 'node:path';

/** Shape matching the StoredIdea used in routes/ideas.ts */
interface StoredIdea {
  id: string;
  title: string;
  description: string;
  tags: string[];
  priority: string;
  status: string;
  autoStatus: string | null;
  linkedPlan: string | null;
  linkedEpic: string | null;
  createdAt: string;
  updatedAt: string;
}

/** Minimal parsed idea from IDEAS.md */
interface ParsedIdea {
  title: string;
  description: string;
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

/**
 * Parse IDEAS.md content into idea entries.
 *
 * Supports two formats:
 * 1. Heading format: `## Title` followed by body lines as description.
 * 2. Bullet format:  `- Title: description` or `- Title — description`.
 *
 * Metadata blocks (YAML front-matter, HTML comments, blockquotes, tables,
 * index sections) are skipped.
 */
function parseIdeasMd(content: string): ParsedIdea[] {
  const ideas: ParsedIdea[] = [];
  const lines = content.split('\n');

  let currentTitle: string | null = null;
  let currentBody: string[] = [];
  let inFrontMatter = false;
  let inComment = false;
  let inIndex = false;

  const flushHeadingIdea = () => {
    if (currentTitle) {
      ideas.push({
        title: currentTitle,
        description: currentBody
          .join('\n')
          .trim()
          // Strip metadata lines that start with **Key:**
          .replace(/^\*\*[A-Za-zÁ-Žá-ž]+:\*\*.*$/gm, '')
          .replace(/\n{3,}/g, '\n\n')
          .trim(),
      });
    }
    currentTitle = null;
    currentBody = [];
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // --- skip YAML front-matter ---
    if (i === 0 && line.trim() === '---') {
      inFrontMatter = true;
      continue;
    }
    if (inFrontMatter) {
      if (line.trim() === '---') inFrontMatter = false;
      continue;
    }

    // --- skip HTML comments ---
    if (line.includes('<!--')) inComment = true;
    if (inComment) {
      if (line.includes('-->')) inComment = false;
      continue;
    }

    // --- skip index/table sections ---
    if (/^##\s+Index/i.test(line) || /^##\s+PM Notes/i.test(line)) {
      flushHeadingIdea();
      inIndex = true;
      continue;
    }
    if (inIndex) {
      // Exit index when we hit a real idea heading (## I-NNN or ## Anything without "Index"/"PM Notes")
      if (/^##\s+/.test(line) && !/^##\s+Index/i.test(line) && !/^##\s+PM Notes/i.test(line)) {
        inIndex = false;
        // fall through to process this heading
      } else {
        continue;
      }
    }

    // --- skip horizontal rules ---
    if (/^---+\s*$/.test(line)) continue;

    // --- skip top-level heading (#) and blockquotes ---
    if (/^#\s+/.test(line)) continue;
    if (/^>\s/.test(line)) continue;

    // --- Heading-based ideas: ## Title ---
    const headingMatch = line.match(/^##\s+(.+)/);
    if (headingMatch) {
      flushHeadingIdea();
      // Strip ID prefix like "I-001 — "
      let title = headingMatch[1].trim();
      title = title.replace(/^I-\d+\s*[—–-]\s*/, '');
      currentTitle = title;
      continue;
    }

    // --- Bullet-based ideas: - Title: desc or - Title — desc ---
    const bulletMatch = line.match(/^[-*]\s+(.+?)(?:\s*[:—–]\s*)(.*)$/);
    if (bulletMatch && !currentTitle) {
      const title = bulletMatch[1].trim();
      const desc = bulletMatch[2]?.trim() ?? '';
      // Skip strikethrough items (~~text~~)
      if (/^~~.*~~$/.test(title)) continue;
      if (title.length > 0) {
        ideas.push({ title, description: desc });
      }
      continue;
    }

    // --- Body lines for current heading ---
    if (currentTitle) {
      // Skip sub-headings (###) metadata labels but keep content
      if (/^###\s+(Popis|Description)/i.test(line)) continue;
      if (/^###\s+/.test(line)) {
        // Include sub-section content as part of description
        currentBody.push('');
        currentBody.push(line.replace(/^###\s+/, '').trim() + ':');
        continue;
      }
      currentBody.push(line);
    }
  }

  // Flush last heading-based idea
  flushHeadingIdea();

  return ideas;
}

// ---------------------------------------------------------------------------
// File I/O helpers
// ---------------------------------------------------------------------------

function ideasJsonPath(projectRoot: string): string {
  return join(projectRoot, '.aid-o', 'work', 'ideas.json');
}

function ideasMdPath(projectRoot: string): string {
  return join(projectRoot, '.aid-o', 'plans', 'IDEAS.md');
}

async function readIdeasJson(projectRoot: string): Promise<StoredIdea[]> {
  try {
    const text = await readFile(ideasJsonPath(projectRoot), 'utf-8');
    return JSON.parse(text) as StoredIdea[];
  } catch {
    return [];
  }
}

async function saveIdeasJson(projectRoot: string, ideas: StoredIdea[]): Promise<void> {
  const dir = join(projectRoot, '.aid-o', 'work');
  await mkdir(dir, { recursive: true });
  await writeFile(ideasJsonPath(projectRoot), JSON.stringify(ideas, null, 2), 'utf-8');
}

function generateId(): string {
  return `idea-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Import ideas from IDEAS.md into ideas.json.
 * Deduplicates by case-insensitive title match.
 * If IDEAS.md does not exist, this is a silent no-op.
 */
export async function importFromIdeasMd(projectRoot: string): Promise<void> {
  const mdPath = ideasMdPath(projectRoot);

  let content: string;
  try {
    content = await readFile(mdPath, 'utf-8');
  } catch {
    // IDEAS.md does not exist — silent no-op
    return;
  }

  const parsed = parseIdeasMd(content);
  if (parsed.length === 0) return;

  const existing = await readIdeasJson(projectRoot);
  const existingTitles = new Set(existing.map((i) => i.title.toLowerCase()));

  const now = new Date().toISOString();
  let imported = 0;
  let duplicates = 0;

  for (const idea of parsed) {
    if (existingTitles.has(idea.title.toLowerCase())) {
      duplicates++;
      continue;
    }

    existing.push({
      id: generateId(),
      title: idea.title,
      description: idea.description,
      tags: [],
      priority: 'medium',
      status: 'idea',
      autoStatus: null,
      linkedPlan: null,
      linkedEpic: null,
      createdAt: now,
      updatedAt: now,
    });

    existingTitles.add(idea.title.toLowerCase());
    imported++;
  }

  if (imported > 0) {
    await saveIdeasJson(projectRoot, existing);
  }

  console.log(`  IDEAS.md: imported ${imported} new idea(s) (${duplicates} duplicate(s) skipped)`);
}

/**
 * Export ideas from ideas.json to IDEAS.md.
 * Creates IDEAS.md.bak backup before overwriting.
 */
export async function exportToIdeasMd(projectRoot: string): Promise<void> {
  const ideas = await readIdeasJson(projectRoot);
  if (ideas.length === 0) return;

  const mdPath = ideasMdPath(projectRoot);

  // Backup existing IDEAS.md if it exists
  try {
    await copyFile(mdPath, mdPath + '.bak');
  } catch {
    // No existing file to back up — that is fine
  }

  // Generate markdown
  const lines: string[] = [
    '# Ideas',
    '',
    '> Managed by AID Orchestrator. Edits are synced with ideas.json on server startup.',
    '',
    '---',
    '',
  ];

  for (const idea of ideas) {
    lines.push(`## ${idea.title}`);
    lines.push('');
    if (idea.status !== 'idea') {
      lines.push(`**Status:** ${idea.status}`);
    }
    if (idea.priority && idea.priority !== 'medium') {
      lines.push(`**Priority:** ${idea.priority}`);
    }
    if (idea.tags && idea.tags.length > 0) {
      lines.push(`**Tags:** ${idea.tags.join(', ')}`);
    }
    if (idea.linkedPlan) {
      lines.push(`**Plan:** ${idea.linkedPlan}`);
    }
    if (idea.linkedEpic) {
      lines.push(`**Epic:** ${idea.linkedEpic}`);
    }
    if (idea.description) {
      lines.push('');
      lines.push(idea.description);
    }
    lines.push('');
    lines.push('---');
    lines.push('');
  }

  const dir = join(projectRoot, '.aid-o', '01-plans');
  await mkdir(dir, { recursive: true });
  await writeFile(mdPath, lines.join('\n'), 'utf-8');

  console.log(`  IDEAS.md: exported ${ideas.length} idea(s)`);
}
