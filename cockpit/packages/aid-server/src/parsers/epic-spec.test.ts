/**
 * EPIC-spec parser test suite (EPIC E-047-2_7, Step 2).
 *
 * Covers the two now-exported section parsers `parseStepsTable` and
 * `parseScope`, using on-disk EPIC-spec markdown fixtures under
 * `__fixtures__/`. These functions previously existed as module-private
 * helpers in `markdown.ts` (used by `parseEpicSpec`); Step 2 exported them so
 * they can be unit-tested independently. The contract is §6.1 "never throw" —
 * ragged / hand-edited markdown yields a defensible result, not an exception.
 *
 * Both functions take a *section body* (the text after a `## Scope` /
 * `## Steps` H2 heading). The fixtures store the full section incl. the H2;
 * `sectionBody()` strips the heading line the same way `splitSections()` does
 * internally, so the unit under test sees exactly what `parseEpicSpec` feeds it.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { parseStepsTable, parseScope } from './index.js';

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), '__fixtures__');

function readFixture(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf8');
}

/**
 * Extract the body of the named H2 section from a fixture, mirroring the way
 * `splitSections()` in markdown.ts isolates a section for the helpers.
 */
function sectionBody(content: string, heading: string): string {
  const lines = content.split('\n');
  const startIdx = lines.findIndex(
    (l) => l.trim().toLowerCase() === `## ${heading.toLowerCase()}`,
  );
  if (startIdx === -1) return '';
  const rest = lines.slice(startIdx + 1);
  const endRel = rest.findIndex((l) => /^##\s+/.test(l));
  const body = (endRel === -1 ? rest : rest.slice(0, endRel)).join('\n');
  return body.trim();
}

// ---------------------------------------------------------------------------
// AC1 + AC6 — parseStepsTable parses a real multi-step EPIC table
// ---------------------------------------------------------------------------

describe('AC1 — parseStepsTable parses a real EPIC table into EpicStep[]', () => {
  const body = sectionBody(readFixture('epic-steps.md'), 'Steps (Role Pipeline)');
  const steps = parseStepsTable(body);

  it('returns one EpicStep per valid table row', () => {
    // 9 data rows authored; the final ragged row (< 3 cells) is dropped → 8.
    expect(steps.length).toBe(8);
  });

  it('parses number, role, and objective correctly', () => {
    expect(steps[0]).toMatchObject({
      number: 1,
      role: 'architect',
      objective: 'Wire packages as a root npm-workspaces monorepo',
    });
    expect(steps[6]).toMatchObject({ number: 7, role: 'qa' });
  });

  it('dependsOn is always a string[]', () => {
    for (const s of steps) {
      expect(Array.isArray(s.dependsOn)).toBe(true);
    }
    // "---" sentinel → []
    expect(steps[0].dependsOn).toEqual([]);
    // single dep "1" → ["1"]
    expect(steps[1].dependsOn).toEqual(['1']);
    // multi dep "4, 5, 6" → ["4","5","6"]
    expect(steps[6].dependsOn).toEqual(['4', '5', '6']);
  });

  it('parallelGroup is set ONLY when not a —/-/---/empty sentinel', () => {
    // Step 1: "---" sentinel → no group.
    expect(steps[0].parallelGroup).toBeUndefined();
    // Step 3 & 4: real group "core" → set.
    expect(steps[2].parallelGroup).toBe('core');
    expect(steps[3].parallelGroup).toBe('core');
    // Step 5: "—" (em dash) sentinel → no group.
    expect(steps[4].parallelGroup).toBeUndefined();
    // Step 6: "-" (hyphen) sentinel → no group.
    expect(steps[5].parallelGroup).toBeUndefined();
    // Step 8: empty cell → no group.
    expect(steps[7].parallelGroup).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// AC2 — ragged row (fewer than 3 cells) skipped without throwing
// ---------------------------------------------------------------------------

describe('AC2 — parseStepsTable tolerates ragged rows', () => {
  it('skips a < 3-cell row and still returns the valid rows (no throw)', () => {
    const ragged = [
      '| # | Role | Objective | Depends On | Parallel Group |',
      '|---|------|-----------|------------|----------------|',
      '| 1 | backend | Valid row | --- | --- |',
      '| 2 | backend |', // ragged: only 2 cells
      '| 3 |', // ragged: only 1 cell
      '| 4 | qa | Another valid row | 1 | --- |',
    ].join('\n');

    let steps: ReturnType<typeof parseStepsTable> = [];
    expect(() => {
      steps = parseStepsTable(ragged);
    }).not.toThrow();

    expect(steps.length).toBe(2);
    expect(steps[0].number).toBe(1);
    expect(steps[1].number).toBe(4);
  });

  it('returns [] (no throw) on empty / whitespace-only input', () => {
    expect(() => parseStepsTable('')).not.toThrow();
    expect(parseStepsTable('')).toEqual([]);
    expect(parseStepsTable('   \n\t ')).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// AC6 — parseDependsOn semantics (exercised through parseStepsTable)
// ---------------------------------------------------------------------------

describe('AC6 — dependsOn parsing semantics', () => {
  function depsOf(cell: string): string[] {
    const table = [
      '| # | Role | Objective | Depends On | Parallel Group |',
      '|---|------|-----------|------------|----------------|',
      `| 1 | backend | obj | ${cell} | --- |`,
    ].join('\n');
    return parseStepsTable(table)[0].dependsOn;
  }

  it('"backend:2, frontend:3" → ["backend:2","frontend:3"]', () => {
    expect(depsOf('backend:2, frontend:3')).toEqual(['backend:2', 'frontend:3']);
  });

  it('"—" and "---" and "-" → []', () => {
    expect(depsOf('—')).toEqual([]);
    expect(depsOf('---')).toEqual([]);
    expect(depsOf('-')).toEqual([]);
  });

  it('splits on both comma and semicolon', () => {
    expect(depsOf('backend:2; frontend:3')).toEqual(['backend:2', 'frontend:3']);
  });
});

// ---------------------------------------------------------------------------
// AC3 — parseScope extracts allowed/forbidden paths from a real EPIC section
// ---------------------------------------------------------------------------

describe('AC3 — parseScope extracts a real EPIC Scope section', () => {
  const raw = readFixture('epic-scope.md');
  const body = sectionBody(raw, 'Scope');
  const scope = parseScope(body);

  it('extracts allowedPaths and strips inline annotations', () => {
    expect(scope.allowedPaths).toEqual([
      '`/opt/eco/projects/aid-orchestrator/packages/aid-server/src/parsers/markdown.ts`',
      '`/opt/eco/projects/aid-orchestrator/packages/aid-server/src/parsers/index.ts`',
      '`/opt/eco/projects/aid-orchestrator/packages/aid-contract/package.json`',
      '`/opt/eco/projects/aid-orchestrator/packages/aid-contract/src/view.ts`',
      '`/opt/eco/projects/aid-orchestrator/tsconfig.base.json`',
    ]);
    // The "(lines 1-21)" and "(read-only reference)" annotations are stripped.
    expect(scope.allowedPaths.some((p) => p.includes('('))).toBe(false);
  });

  it('extracts forbiddenPaths incl. the Distribution-boundary entry', () => {
    expect(scope.forbiddenPaths).toContain('`.claude-plugin/marketplace.json`');
    expect(scope.forbiddenPaths).toContain(
      '`plugins/aid-orchestrator/.claude-plugin/plugin.json`',
    );
    expect(scope.forbiddenPaths).toContain(
      '`plugins/aid-orchestrator/defaults/`',
    );
    expect(scope.forbiddenPaths.length).toBe(4);
  });

  it('preserves the raw section body in rawMarkdown', () => {
    expect(scope.rawMarkdown).toBe(body);
    expect(scope.rawMarkdown).toContain('### Allowed files/paths');
    expect(scope.rawMarkdown).toContain('### Forbidden zones');
  });
});

// ---------------------------------------------------------------------------
// AC4 — parseScope returns empty arrays + raw body on unrecognized sections
// ---------------------------------------------------------------------------

describe('AC4 — parseScope degrades gracefully with no sub-headings', () => {
  const body = sectionBody(readFixture('epic-scope-empty.md'), 'Scope');

  it('returns empty arrays + the raw body, never throws', () => {
    let scope: ReturnType<typeof parseScope> | undefined;
    expect(() => {
      scope = parseScope(body);
    }).not.toThrow();

    expect(scope?.allowedPaths).toEqual([]);
    expect(scope?.forbiddenPaths).toEqual([]);
    expect(scope?.rawMarkdown).toBe(body);
    expect(scope?.rawMarkdown).toContain('described in prose');
  });

  it('returns empty arrays + empty raw body on empty input (no throw)', () => {
    expect(() => parseScope('')).not.toThrow();
    const scope = parseScope('');
    expect(scope.allowedPaths).toEqual([]);
    expect(scope.forbiddenPaths).toEqual([]);
    expect(scope.rawMarkdown).toBe('');
  });
});
