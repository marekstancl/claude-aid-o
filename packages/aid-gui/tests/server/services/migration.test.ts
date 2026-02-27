/**
 * Tests for the IDEAS.md migration service.
 *
 * Validates importFromIdeasMd / exportToIdeasMd functions from
 * packages/aid-server/src/services/ideas-migration.ts.
 *
 * File paths used by the service:
 *   - ideas.json: {projectRoot}/.aid-o/04-engine/ideas.json
 *   - IDEAS.md:   {projectRoot}/.aid-o/01-plans/IDEAS.md
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';
import { importFromIdeasMd, exportToIdeasMd } from '../../../../aid-server/src/services/ideas-migration.ts';

let tmpDir: string;

beforeEach(async () => {
  tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'migration-test-'));
});

afterEach(async () => {
  await fs.rm(tmpDir, { recursive: true, force: true });
});

/** Write a file, creating parent directories if needed. */
async function writeFile(filePath: string, content: string): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, 'utf-8');
}

function ideasJsonPath(): string {
  return path.join(tmpDir, '.aid-o', '04-engine', 'ideas.json');
}

function ideasMdPath(): string {
  return path.join(tmpDir, '.aid-o', '01-plans', 'IDEAS.md');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const HEADING_FORMAT_IDEAS_MD = `---
type: ideas
version: 1
last_updated: 2026-02-27
counter: 3
---

# Ideas

## Add dark mode

Add a dark mode toggle to the dashboard for better readability.

## Performance monitoring

Integrate APM metrics into the dashboard.

## Add Dark Mode

This is a duplicate entry with different case.
`;

const BULLET_FORMAT_IDEAS_MD = `# Ideas

- CLI improvements: Better CLI help output and autocomplete
- Docker support — Containerize the GUI server
`;

// ---------------------------------------------------------------------------
// importFromIdeasMd
// ---------------------------------------------------------------------------

describe('importFromIdeasMd — heading format', () => {
  it('imports ideas from heading-format IDEAS.md into ideas.json', async () => {
    await writeFile(ideasMdPath(), HEADING_FORMAT_IDEAS_MD);

    await importFromIdeasMd(tmpDir);

    const content = JSON.parse(await fs.readFile(ideasJsonPath(), 'utf-8'));
    // ideas.json is a flat StoredIdea[] array
    expect(Array.isArray(content)).toBe(true);
    expect(content.length).toBeGreaterThanOrEqual(2);
  });

  it('deduplicates by case-insensitive title', async () => {
    await writeFile(ideasMdPath(), HEADING_FORMAT_IDEAS_MD);

    await importFromIdeasMd(tmpDir);

    const content = JSON.parse(await fs.readFile(ideasJsonPath(), 'utf-8'));

    // "Add dark mode" appears twice with different case — should be deduped
    const darkModeEntries = content.filter(
      (i: { title: string }) => i.title.toLowerCase() === 'add dark mode',
    );
    expect(darkModeEntries).toHaveLength(1);
  });
});

describe('importFromIdeasMd — bullet format', () => {
  it('imports ideas from bullet-format IDEAS.md', async () => {
    await writeFile(ideasMdPath(), BULLET_FORMAT_IDEAS_MD);

    await importFromIdeasMd(tmpDir);

    const content = JSON.parse(await fs.readFile(ideasJsonPath(), 'utf-8'));
    expect(Array.isArray(content)).toBe(true);
    expect(content.length).toBe(2);
  });
});

describe('importFromIdeasMd — edge cases', () => {
  it('is a silent no-op when IDEAS.md does not exist', async () => {
    await expect(importFromIdeasMd(tmpDir)).resolves.toBeUndefined();

    // ideas.json should not be created
    await expect(fs.access(ideasJsonPath())).rejects.toThrow();
  });

  it('merges into existing ideas.json without losing entries', async () => {
    // Pre-existing ideas.json with one entry
    const existing = [
      {
        id: 'idea-existing-001',
        title: 'Existing idea',
        description: 'Already in JSON',
        tags: [],
        priority: 'low',
        status: 'idea',
        autoStatus: null,
        linkedPlan: null,
        linkedEpic: null,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    ];
    await writeFile(ideasJsonPath(), JSON.stringify(existing, null, 2));
    await writeFile(ideasMdPath(), BULLET_FORMAT_IDEAS_MD);

    await importFromIdeasMd(tmpDir);

    const content = JSON.parse(await fs.readFile(ideasJsonPath(), 'utf-8'));
    // Should have existing (1) + new ideas (2) = 3
    expect(content.length).toBe(3);

    const existingEntry = content.find(
      (i: { id: string }) => i.id === 'idea-existing-001',
    );
    expect(existingEntry).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// exportToIdeasMd
// ---------------------------------------------------------------------------

describe('exportToIdeasMd', () => {
  it('creates IDEAS.md from ideas.json', async () => {
    const ideas = [
      {
        id: 'idea-001',
        title: 'Test idea',
        description: 'A test idea for export',
        tags: ['test'],
        priority: 'high',
        status: 'idea',
        autoStatus: null,
        linkedPlan: null,
        linkedEpic: null,
        createdAt: '2026-02-27T00:00:00Z',
        updatedAt: '2026-02-27T00:00:00Z',
      },
    ];
    await writeFile(ideasJsonPath(), JSON.stringify(ideas, null, 2));

    await exportToIdeasMd(tmpDir);

    const mdContent = await fs.readFile(ideasMdPath(), 'utf-8');
    expect(mdContent).toContain('Test idea');
  });

  it('creates a .bak backup of existing IDEAS.md before overwriting', async () => {
    await writeFile(ideasMdPath(), '# Old Ideas\n\nOld content.\n');

    const ideas = [
      {
        id: 'idea-001',
        title: 'New idea',
        description: 'Replacing old content',
        tags: [],
        priority: 'medium',
        status: 'idea',
        autoStatus: null,
        linkedPlan: null,
        linkedEpic: null,
        createdAt: '2026-02-27T00:00:00Z',
        updatedAt: '2026-02-27T00:00:00Z',
      },
    ];
    await writeFile(ideasJsonPath(), JSON.stringify(ideas, null, 2));

    await exportToIdeasMd(tmpDir);

    // Backup should exist with old content
    const bakContent = await fs.readFile(ideasMdPath() + '.bak', 'utf-8');
    expect(bakContent).toContain('Old content');

    // New content should be written
    const newContent = await fs.readFile(ideasMdPath(), 'utf-8');
    expect(newContent).toContain('New idea');
  });
});

// ---------------------------------------------------------------------------
// Round-trip
// ---------------------------------------------------------------------------

describe('import/export round-trip', () => {
  it('import then export preserves all ideas', async () => {
    await writeFile(ideasMdPath(), HEADING_FORMAT_IDEAS_MD);

    // Import from MD to JSON
    await importFromIdeasMd(tmpDir);

    const imported = JSON.parse(await fs.readFile(ideasJsonPath(), 'utf-8'));
    const importedCount = imported.length;
    expect(importedCount).toBeGreaterThan(0);

    // Export back to MD
    await exportToIdeasMd(tmpDir);

    // Re-import from the exported MD into a fresh tmpDir
    const tmpDir2 = await fs.mkdtemp(path.join(os.tmpdir(), 'roundtrip-'));
    const mdPath2 = path.join(tmpDir2, '.aid-o', '01-plans', 'IDEAS.md');
    const jsonPath2 = path.join(tmpDir2, '.aid-o', '04-engine', 'ideas.json');

    const exportedMd = await fs.readFile(ideasMdPath(), 'utf-8');
    await writeFile(mdPath2, exportedMd);

    await importFromIdeasMd(tmpDir2);

    const reimported = JSON.parse(await fs.readFile(jsonPath2, 'utf-8'));
    expect(reimported.length).toBe(importedCount);

    await fs.rm(tmpDir2, { recursive: true, force: true });
  });
});
