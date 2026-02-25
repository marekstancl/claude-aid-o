/**
 * Unit tests for server/parsers/yaml.ts
 *
 * Covers: valid YAML from real .aid-o/ fixture, camelCase key conversion,
 * empty content, malformed YAML, and source propagation.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { parseYaml } from '../../../server/parsers/yaml.ts';
import type { EpicQueue } from '../../../server/types.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(__dirname, '../../fixtures');

function readFixture(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf-8');
}

// ---------------------------------------------------------------------------
// Valid YAML — epic-queue.yaml (real .aid-o/ data)
// ---------------------------------------------------------------------------

describe('parseYaml — valid epic-queue.yaml', () => {
  it('parses the fixture successfully and returns non-null data', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<EpicQueue>(content, 'epic-queue.yaml');

    expect(result.data).not.toBeNull();
  });

  it('returns no warnings on a clean valid YAML document', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<EpicQueue>(content, 'epic-queue.yaml');

    expect(result.warnings).toHaveLength(0);
  });

  it('parses the paused flag correctly', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<EpicQueue>(content, 'epic-queue.yaml');

    expect(result.data?.paused).toBe(false);
  });

  it('parses the queue array with the correct number of entries', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<EpicQueue>(content, 'epic-queue.yaml');

    expect(result.data?.queue).toHaveLength(4);
  });

  it('converts snake_case keys to camelCase in the output', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<EpicQueue>(content, 'epic-queue.yaml');

    const firstEntry = result.data?.queue[0];
    // Source has "epic_id" — should be "epicId" in output.
    expect(firstEntry).toHaveProperty('epicId', 'E-005-1_4-gui-foundation');
    // Source has "added_at" — should be "addedAt" in output.
    expect(firstEntry).toHaveProperty('addedAt', '2026-02-25T14:00:00Z');
    // Source has "started_at" — should be "startedAt" in output.
    expect(firstEntry).toHaveProperty('startedAt', '2026-02-25T14:00:05Z');
    // Source has "completed_at" — should be "completedAt" in output.
    expect(firstEntry).toHaveProperty('completedAt', null);
  });

  it('does NOT use raw snake_case keys (original keys must be absent)', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<Record<string, unknown>>(content, 'epic-queue.yaml');

    const firstEntry = (result.data?.queue as Record<string, unknown>[])[0];
    expect(firstEntry).not.toHaveProperty('epic_id');
    expect(firstEntry).not.toHaveProperty('added_at');
  });

  it('parses the status and priority of the running EPIC correctly', () => {
    const content = readFixture('epic-queue.yaml');
    const result = parseYaml<EpicQueue>(content, 'epic-queue.yaml');

    const running = result.data?.queue[0];
    expect(running?.status).toBe('running');
    expect(running?.priority).toBe('high');
  });

  it('propagates the source string in the result', () => {
    const content = readFixture('epic-queue.yaml');
    const source = 'fixtures/epic-queue.yaml';
    const result = parseYaml<EpicQueue>(content, source);

    expect(result.source).toBe(source);
  });
});

// ---------------------------------------------------------------------------
// Empty content
// ---------------------------------------------------------------------------

describe('parseYaml — empty content', () => {
  it('returns null data when content is an empty string', () => {
    const result = parseYaml('', 'test.yaml');

    expect(result.data).toBeNull();
  });

  it('returns a warning when content is empty', () => {
    const result = parseYaml('', 'test.yaml');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('warning');
    expect(result.warnings[0].message).toContain('empty');
  });

  it('returns null data when content is only whitespace', () => {
    const result = parseYaml('   \n\t  \n', 'test.yaml');

    expect(result.data).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// YAML document that is null/empty after parsing
// ---------------------------------------------------------------------------

describe('parseYaml — null/empty document', () => {
  it('returns null data and a warning for a document with only "---"', () => {
    const result = parseYaml('---', 'test.yaml');

    expect(result.data).toBeNull();
    expect(result.warnings.length).toBeGreaterThan(0);
    expect(result.warnings[0].severity).toBe('warning');
  });

  it('returns null data and a warning for a document with only comments', () => {
    const result = parseYaml('# This is just a comment\n# Another comment\n', 'test.yaml');

    expect(result.data).toBeNull();
    expect(result.warnings.length).toBeGreaterThan(0);
  });
});

// ---------------------------------------------------------------------------
// Malformed YAML
// ---------------------------------------------------------------------------

describe('parseYaml — malformed YAML', () => {
  it('returns null data for malformed YAML instead of throwing', () => {
    const content = readFixture('malformed.yaml');
    const result = parseYaml(content, 'malformed.yaml');

    expect(result.data).toBeNull();
  });

  it('returns an error-severity warning for malformed YAML', () => {
    const content = readFixture('malformed.yaml');
    const result = parseYaml(content, 'malformed.yaml');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('error');
    expect(result.warnings[0].message).toContain('Malformed YAML');
  });

  it('includes a line number in the warning for malformed YAML', () => {
    const content = readFixture('malformed.yaml');
    const result = parseYaml(content, 'malformed.yaml');

    // js-yaml provides line info; the parser should surface it (>= 1).
    expect(result.warnings[0].line).toBeGreaterThanOrEqual(1);
  });

  it('propagates the source string even when parsing fails', () => {
    const content = readFixture('malformed.yaml');
    const source = 'fixtures/malformed.yaml';
    const result = parseYaml(content, source);

    expect(result.source).toBe(source);
  });
});

// ---------------------------------------------------------------------------
// Inline valid YAML — no file I/O
// ---------------------------------------------------------------------------

describe('parseYaml — inline valid content', () => {
  it('parses a minimal valid YAML object', () => {
    const content = 'status: active\nversion: 1\n';
    const result = parseYaml<{ status: string; version: number }>(content, 'inline.yaml');

    expect(result.data).toEqual({ status: 'active', version: 1 });
    expect(result.warnings).toHaveLength(0);
  });

  it('converts nested snake_case keys', () => {
    const content = `
outer_key:
  inner_key: hello
  nested_value: 42
`.trim();

    const result = parseYaml<Record<string, unknown>>(content, 'inline.yaml');

    expect(result.data).toEqual({
      outerKey: {
        innerKey: 'hello',
        nestedValue: 42,
      },
    });
  });
});
