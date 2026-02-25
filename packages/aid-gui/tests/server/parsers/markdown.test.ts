/**
 * Unit tests for server/parsers/markdown.ts
 *
 * Covers: parseMarkdownWithFrontmatter (generic frontmatter extraction) and
 * parseEpicSpec (full EPIC spec parsing). Uses the epic-sample.md fixture
 * (derived from real .aid-o/ data) and synthetic inline content.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import {
  parseMarkdownWithFrontmatter,
  parseEpicSpec,
} from '../../../server/parsers/markdown.ts';
import type { EpicSpec } from '../../../server/types.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(__dirname, '../../fixtures');

function readFixture(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf-8');
}

// ---------------------------------------------------------------------------
// parseMarkdownWithFrontmatter — generic frontmatter extraction
// ---------------------------------------------------------------------------

describe('parseMarkdownWithFrontmatter — valid markdown with frontmatter', () => {
  it('returns non-null data for markdown that has frontmatter', () => {
    const content = readFixture('epic-sample.md');
    const result = parseMarkdownWithFrontmatter(content, 'epic-sample.md');

    expect(result.data).not.toBeNull();
    expect(result.data?.frontmatter).not.toBeNull();
  });

  it('returns no warnings when frontmatter is present', () => {
    const content = readFixture('epic-sample.md');
    const result = parseMarkdownWithFrontmatter(content, 'epic-sample.md');

    expect(result.warnings).toHaveLength(0);
  });

  it('extracts frontmatter fields and converts snake_case keys to camelCase', () => {
    const content = readFixture('epic-sample.md');
    const result = parseMarkdownWithFrontmatter<{
      status: string;
      planRef: string;
      planEpicsTotal: number;
      runsTotal: number;
      runsCompleted: number;
    }>(content, 'epic-sample.md');

    const fm = result.data?.frontmatter;
    // Source has "plan_ref" — output should have "planRef".
    expect(fm).toHaveProperty('planRef', '.aid-o/01-plans/P005-C-aid-gui-backend-post-prototype.md');
    // Source has "plan_epics_total" — output should have "planEpicsTotal".
    expect(fm).toHaveProperty('planEpicsTotal', 4);
    expect(fm).toHaveProperty('status', 'active');
    expect(fm).toHaveProperty('runsTotal', 1);
    expect(fm).toHaveProperty('runsCompleted', 0);
  });

  it('extracts the body content after the frontmatter block', () => {
    const content = readFixture('epic-sample.md');
    const result = parseMarkdownWithFrontmatter(content, 'epic-sample.md');

    // Body should contain the H1 heading.
    expect(result.data?.body).toContain('# EPIC: E-005-1_4');
    // Body should NOT contain the YAML frontmatter delimiters.
    expect(result.data?.body).not.toMatch(/^---/m);
  });

  it('propagates the source string', () => {
    const content = readFixture('epic-sample.md');
    const source = 'fixtures/epic-sample.md';
    const result = parseMarkdownWithFrontmatter(content, source);

    expect(result.source).toBe(source);
  });
});

describe('parseMarkdownWithFrontmatter — no frontmatter', () => {
  it('returns data with null frontmatter and the full body', () => {
    const content = readFixture('no-frontmatter.md');
    const result = parseMarkdownWithFrontmatter(content, 'no-frontmatter.md');

    expect(result.data?.frontmatter).toBeNull();
    expect(result.data?.body).toContain('# A Markdown File Without Frontmatter');
  });

  it('returns an info-severity warning when frontmatter is missing', () => {
    const content = readFixture('no-frontmatter.md');
    const result = parseMarkdownWithFrontmatter(content, 'no-frontmatter.md');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('info');
    expect(result.warnings[0].message).toContain('frontmatter');
  });
});

describe('parseMarkdownWithFrontmatter — empty content', () => {
  it('returns empty body and null frontmatter for empty string', () => {
    const result = parseMarkdownWithFrontmatter('', 'empty.md');

    expect(result.data?.frontmatter).toBeNull();
    expect(result.data?.body).toBe('');
  });

  it('returns a warning for empty content', () => {
    const result = parseMarkdownWithFrontmatter('', 'empty.md');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('warning');
  });
});

describe('parseMarkdownWithFrontmatter — inline valid content', () => {
  it('parses a minimal frontmatter block correctly', () => {
    const content = `---
key_name: value
another_key: 42
---

# Body heading

Some body text.
`;
    const result = parseMarkdownWithFrontmatter<{ keyName: string; anotherKey: number }>(
      content,
      'inline.md',
    );

    expect(result.data?.frontmatter).toEqual({ keyName: 'value', anotherKey: 42 });
    expect(result.data?.body).toContain('# Body heading');
    expect(result.warnings).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// parseEpicSpec — full EPIC specification parsing
// ---------------------------------------------------------------------------

describe('parseEpicSpec — valid epic-sample.md', () => {
  it('returns non-null data from the fixture', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data).not.toBeNull();
  });

  it('derives the epicId from the filename when not in frontmatter', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.epicId).toBe('E-005-1_4-gui-foundation');
  });

  it('extracts the status from frontmatter', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.status).toBe('active');
  });

  it('extracts planRef from frontmatter (snake_case converted)', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.planRef).toBe('.aid-o/01-plans/P005-C-aid-gui-backend-post-prototype.md');
  });

  it('extracts numeric frontmatter fields', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.planEpicsTotal).toBe(4);
    expect(result.data?.runsTotal).toBe(1);
    expect(result.data?.runsCompleted).toBe(0);
  });

  it('extracts the H1 title from the Markdown body', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.title).toContain('AID GUI Foundation');
  });

  it('extracts the Context section', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.context).toContain('TypeScript + Express + Vite');
  });

  it('extracts the Goal section', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.goal).toContain('packages/aid-gui/');
  });

  it('extracts the Constraints section', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'E-005-1_4-gui-foundation.md');

    expect(result.data?.constraints).toContain('TypeScript strict mode');
  });
});

describe('parseEpicSpec — scope section', () => {
  it('populates allowedPaths from the Scope section', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.scope.allowedPaths).toContain('packages/aid-gui/server/');
    expect(result.data?.scope.allowedPaths).toContain('packages/aid-gui/tests/');
  });

  it('populates forbiddenPaths from the Scope section', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.scope.forbiddenPaths).toContain('packages/aid-gui/src/');
    expect(result.data?.scope.forbiddenPaths).toContain('plugins/');
  });

  it('includes the rawMarkdown of the scope section', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.scope.rawMarkdown).toBeTruthy();
    expect(result.data?.scope.rawMarkdown.length).toBeGreaterThan(0);
  });
});

describe('parseEpicSpec — DoD Gates', () => {
  it('parses the DoD Gates section into an array of gate names', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.dodGates).toEqual(['tests_pass', 'lint_pass', 'type_check']);
  });
});

describe('parseEpicSpec — Acceptance Criteria', () => {
  it('parses acceptance criteria items into structured objects', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.acceptanceCriteria.length).toBeGreaterThan(0);
  });

  it('correctly identifies unchecked criteria (checked = false)', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    const unchecked = result.data?.acceptanceCriteria.filter((c) => !c.checked);
    expect(unchecked?.length).toBeGreaterThan(0);
  });

  it('correctly identifies checked criteria (checked = true)', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    // The fixture has one checked criterion: "[x] [backend] YAML parser..."
    const checked = result.data?.acceptanceCriteria.filter((c) => c.checked);
    expect(checked?.length).toBe(1);
    expect(checked?.[0].role).toBe('backend');
    expect(checked?.[0].text).toContain('YAML parser');
  });

  it('extracts the role tag from each criterion', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    const criteria = result.data?.acceptanceCriteria ?? [];
    // Every criterion in the fixture has a role tag.
    for (const criterion of criteria) {
      expect(criterion.role).not.toBe('');
    }
  });
});

describe('parseEpicSpec — Steps table', () => {
  it('parses the steps table into an array of EpicStep objects', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.steps.length).toBeGreaterThan(0);
  });

  it('assigns the correct step numbers', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    const steps = result.data?.steps ?? [];
    expect(steps[0].number).toBe(1);
    expect(steps[steps.length - 1].number).toBe(5);
  });

  it('assigns the correct role for each step', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    const steps = result.data?.steps ?? [];
    expect(steps[0].role).toBe('architect');
    expect(steps[1].role).toBe('backend');
    expect(steps[4].role).toBe('qa');
  });

  it('parses dependsOn correctly for a step with a dependency', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    const steps = result.data?.steps ?? [];
    // Step 2 (backend) depends on "architect".
    expect(steps[1].dependsOn).toContain('architect');
  });

  it('sets dependsOn to empty array for the first step (no dependency)', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    const steps = result.data?.steps ?? [];
    // Step 1 (architect) has "—" as depends on.
    expect(steps[0].dependsOn).toEqual([]);
  });
});

describe('parseEpicSpec — Hints section', () => {
  it('parses hints as key-value pairs', () => {
    const content = readFixture('epic-sample.md');
    const result = parseEpicSpec(content, 'epic-sample.md');

    expect(result.data?.hints).toBeDefined();
    expect(result.data?.hints?.['expected_steps']).toBe(6);
    expect(result.data?.hints?.['complexity']).toBe('medium');
  });
});

describe('parseEpicSpec — empty content', () => {
  it('returns null data for empty string', () => {
    const result = parseEpicSpec('', 'empty.md');

    expect(result.data).toBeNull();
  });

  it('returns an error-severity warning for empty content', () => {
    const result = parseEpicSpec('', 'empty.md');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('error');
  });
});

describe('parseEpicSpec — inline minimal EPIC', () => {
  it('parses a minimal EPIC with all required sections', () => {
    const content = `---
status: draft
plan_ref: .aid-o/01-plans/P001.md
plan_epics_total: 1
runs_total: 1
runs_completed: 0
---

# EPIC: E-001 — Minimal Test

## Context

Minimal context here.

## Goal

Minimal goal here.

## Scope

### Allowed files/paths
- \`src/\`

### Forbidden zones
- \`node_modules/\`

## Constraints

No special constraints.

## DoD Gates

- tests_pass

## Acceptance Criteria

- [ ] [backend] Thing must work

## Steps (Role Pipeline)

| # | Role | Objective | Depends On | Parallel Group |
|---|------|-----------|------------|----------------|
| 1 | backend | Do the thing | — | — |
`;

    const result = parseEpicSpec(content, 'E-001-minimal.md');

    expect(result.data).not.toBeNull();
    expect(result.data?.epicId).toBe('E-001-minimal');
    expect(result.data?.title).toBe('EPIC: E-001 — Minimal Test');
    expect(result.data?.status).toBe('draft');
    expect(result.data?.dodGates).toEqual(['tests_pass']);
    expect(result.data?.acceptanceCriteria).toHaveLength(1);
    expect(result.data?.acceptanceCriteria[0].checked).toBe(false);
    expect(result.data?.acceptanceCriteria[0].role).toBe('backend');
    expect(result.data?.steps).toHaveLength(1);
    expect(result.data?.steps[0].role).toBe('backend');
    expect(result.data?.steps[0].dependsOn).toEqual([]);
  });

  it('warns about missing optional sections (context, goal) when absent', () => {
    const content = `---
status: draft
---

# EPIC: E-minimal

## DoD Gates

- tests_pass
`;
    const result = parseEpicSpec(content, 'E-minimal.md');

    // Should get info warnings about missing Context and Goal.
    const infoWarnings = result.warnings.filter((w) => w.severity === 'info');
    expect(infoWarnings.length).toBeGreaterThanOrEqual(2);
  });
});
