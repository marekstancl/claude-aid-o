/**
 * Tolerant-parser test suite (EPIC E-047-2_7, Step 1).
 *
 * Verifies the §6.1 "never throw" contract for the salvaged parsers plus the
 * §4.0 reliability findings #4 (queue.yaml mixed indentation / mojibake →
 * capture the error line) and #5 (audit-log.jsonl corrupt lines → tolerate
 * per-line). Each parser must return `{ data, warnings, source }` on empty,
 * whitespace-only, and malformed input without throwing.
 */

import { describe, it, expect } from 'vitest';
import {
  parseJson,
  parseYaml,
  parseJsonl,
  parseMarkdownWithFrontmatter,
  snakeToCamel,
  snakeToCamelKey,
} from './index.js';

// ---------------------------------------------------------------------------
// AC1 — never throw on empty / whitespace-only / malformed input
// ---------------------------------------------------------------------------

describe('AC1 — parsers never throw and return the canonical shape', () => {
  describe('parseJson', () => {
    it('returns { data: null, warnings, source } on empty input', () => {
      const r = parseJson<unknown>('', 'empty.json');
      expect(r.data).toBeNull();
      expect(r.source).toBe('empty.json');
      expect(Array.isArray(r.warnings)).toBe(true);
      expect(r.warnings.length).toBeGreaterThan(0);
    });

    it('returns null data (no throw) on whitespace-only input', () => {
      expect(() => parseJson<unknown>('   \n\t  ', 'ws.json')).not.toThrow();
      const r = parseJson<unknown>('   \n\t  ', 'ws.json');
      expect(r.data).toBeNull();
    });

    it('returns null data (no throw) on malformed JSON', () => {
      expect(() => parseJson<unknown>('{ not: valid', 'bad.json')).not.toThrow();
      const r = parseJson<unknown>('{ not: valid', 'bad.json');
      expect(r.data).toBeNull();
      expect(r.warnings.some((w) => w.severity === 'error')).toBe(true);
    });
  });

  describe('parseYaml', () => {
    it('returns { data: null, warnings, source } on empty input', () => {
      const r = parseYaml<unknown>('', 'empty.yaml');
      expect(r.data).toBeNull();
      expect(r.source).toBe('empty.yaml');
      expect(r.warnings.length).toBeGreaterThan(0);
    });

    it('returns null data (no throw) on whitespace-only input', () => {
      expect(() => parseYaml<unknown>('   \n  ', 'ws.yaml')).not.toThrow();
      const r = parseYaml<unknown>('   \n  ', 'ws.yaml');
      expect(r.data).toBeNull();
    });

    it('returns null data (no throw) on malformed YAML', () => {
      const malformed = 'key: [unclosed\n  bad: : :';
      expect(() => parseYaml<unknown>(malformed, 'bad.yaml')).not.toThrow();
      const r = parseYaml<unknown>(malformed, 'bad.yaml');
      expect(r.data).toBeNull();
      expect(r.warnings.some((w) => w.severity === 'error')).toBe(true);
    });
  });

  describe('parseJsonl', () => {
    it('returns { data: [], warnings, source } on empty input', () => {
      const r = parseJsonl<unknown>('', 'empty.jsonl');
      expect(r.data).toEqual([]);
      expect(r.source).toBe('empty.jsonl');
      expect(r.warnings.length).toBeGreaterThan(0);
    });

    it('returns empty array (no throw) on whitespace-only input', () => {
      expect(() => parseJsonl<unknown>('  \n\n ', 'ws.jsonl')).not.toThrow();
      const r = parseJsonl<unknown>('  \n\n ', 'ws.jsonl');
      expect(r.data).toEqual([]);
    });

    it('does not throw on fully malformed input', () => {
      expect(() =>
        parseJsonl<unknown>('not json\nalso not json', 'bad.jsonl'),
      ).not.toThrow();
    });
  });

  describe('parseMarkdownWithFrontmatter', () => {
    it('returns { frontmatter: null, body: "" } on empty input', () => {
      const r = parseMarkdownWithFrontmatter<unknown>('', 'empty.md');
      expect(r.data).toEqual({ frontmatter: null, body: '' });
      expect(r.source).toBe('empty.md');
      expect(r.warnings.length).toBeGreaterThan(0);
    });

    it('does not throw on whitespace-only input', () => {
      expect(() =>
        parseMarkdownWithFrontmatter<unknown>('   \n  ', 'ws.md'),
      ).not.toThrow();
      const r = parseMarkdownWithFrontmatter<unknown>('   \n  ', 'ws.md');
      expect(r.data).toEqual({ frontmatter: null, body: '' });
    });
  });
});

// ---------------------------------------------------------------------------
// AC2 + §4.0 #5 — parseJsonl tolerates a corrupt middle line
// ---------------------------------------------------------------------------

describe('AC2 — parseJsonl tolerates corrupt lines (audit-log.jsonl, §4.0 #5)', () => {
  it('returns all valid entries + one warning per bad line', () => {
    const content = [
      '{"event": "start", "epic_id": "E-1"}',
      '{ THIS LINE IS CORRUPT',
      '{"event": "complete", "epic_id": "E-1"}',
    ].join('\n');

    const r = parseJsonl<{ event: string; epicId: string }>(
      content,
      'audit-log.jsonl',
    );

    // Two valid lines parsed.
    expect(r.data).not.toBeNull();
    expect(r.data?.length).toBe(2);
    expect(r.data?.[0].event).toBe('start');
    expect(r.data?.[1].event).toBe('complete');

    // snake_case → camelCase applied per entry.
    expect(r.data?.[0].epicId).toBe('E-1');

    // Exactly one per-line warning, severity 'warning', pointing at line 2.
    const lineWarnings = r.warnings.filter((w) => w.severity === 'warning');
    expect(lineWarnings.length).toBe(1);
    expect(lineWarnings[0].line).toBe(2);
  });

  it('data length equals the valid-line count for multiple bad lines', () => {
    const content = [
      '{"n": 1}',
      'broken-1',
      '{"n": 2}',
      'broken-2',
      '{"n": 3}',
    ].join('\n');

    const r = parseJsonl<{ n: number }>(content, 'multi.jsonl');
    expect(r.data?.length).toBe(3);
    expect(r.warnings.filter((w) => w.severity === 'warning').length).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// AC3 — snakeToCamel recursion + value preservation
// ---------------------------------------------------------------------------

describe('AC3 — snakeToCamel converts keys recursively, preserves values', () => {
  it('converts top-level snake_case keys', () => {
    expect(snakeToCamelKey('epic_id')).toBe('epicId');
    expect(snakeToCamelKey('started_at')).toBe('startedAt');
    expect(snakeToCamelKey('already')).toBe('already');
  });

  it('recurses through nested objects and arrays', () => {
    const input = {
      epic_id: 'E-1',
      started_at: '2026-06-20T00:00:00Z',
      nested_obj: {
        inner_key: 1,
        deeper_list: [{ list_item_key: 'a' }, { list_item_key: 'b' }],
      },
    };

    const out = snakeToCamel<{
      epicId: string;
      startedAt: string;
      nestedObj: {
        innerKey: number;
        deeperList: { listItemKey: string }[];
      };
    }>(input);

    expect(out.epicId).toBe('E-1');
    expect(out.startedAt).toBe('2026-06-20T00:00:00Z');
    expect(out.nestedObj.innerKey).toBe(1);
    expect(out.nestedObj.deeperList[0].listItemKey).toBe('a');
    expect(out.nestedObj.deeperList[1].listItemKey).toBe('b');

    // Original is not mutated.
    expect('epic_id' in input).toBe(true);
  });

  it('leaves null, Date, and primitives untouched', () => {
    expect(snakeToCamel<null>(null)).toBeNull();
    expect(snakeToCamel<undefined>(undefined)).toBeUndefined();
    expect(snakeToCamel<number>(42)).toBe(42);
    expect(snakeToCamel<string>('plain_string_value')).toBe(
      'plain_string_value',
    );

    const d = new Date('2026-06-20T00:00:00Z');
    const out = snakeToCamel<Date>(d);
    // Date is a non-plain object: passed through by reference, unchanged.
    expect(out).toBe(d);
    expect(out instanceof Date).toBe(true);

    // null nested inside an object is preserved.
    const withNull = snakeToCamel<{ someKey: null }>({ some_key: null });
    expect(withNull.someKey).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// AC4 — parseMarkdownWithFrontmatter: no-frontmatter vs frontmatter
// ---------------------------------------------------------------------------

describe('AC4 — parseMarkdownWithFrontmatter frontmatter handling', () => {
  it('returns { frontmatter: null, body } when no --- block exists (no throw)', () => {
    const md = '# Title\n\nSome body text without frontmatter.';
    expect(() =>
      parseMarkdownWithFrontmatter<Record<string, unknown>>(md, 'doc.md'),
    ).not.toThrow();

    const r = parseMarkdownWithFrontmatter<Record<string, unknown>>(
      md,
      'doc.md',
    );
    expect(r.data?.frontmatter).toBeNull();
    expect(r.data?.body).toContain('Some body text without frontmatter.');
  });

  it('camelCases frontmatter keys when present', () => {
    const md = [
      '---',
      'epic_id: E-047-2_7',
      'plan_ref: docs/plan.md',
      'runs_total: 7',
      '---',
      '',
      '# Heading',
      'Body content.',
    ].join('\n');

    const r = parseMarkdownWithFrontmatter<{
      epicId: string;
      planRef: string;
      runsTotal: number;
    }>(md, 'epic.md');

    expect(r.data?.frontmatter).not.toBeNull();
    expect(r.data?.frontmatter?.epicId).toBe('E-047-2_7');
    expect(r.data?.frontmatter?.planRef).toBe('docs/plan.md');
    expect(r.data?.frontmatter?.runsTotal).toBe(7);
    expect(r.data?.body).toContain('Body content.');
  });
});

// ---------------------------------------------------------------------------
// §4.0 #4 — parseYaml captures the error line for mixed indentation / mojibake
// ---------------------------------------------------------------------------

describe('§4.0 #4 — parseYaml captures the offending line (queue.yaml)', () => {
  it('attaches a line number to the malformed-YAML warning', () => {
    // Mixed/illegal indentation that js-yaml rejects with a mark.
    const queueYaml = [
      'queue:',
      '  - epic_id: E-1',
      '    priority: high',
      '   priority: broken-indent', // bad indentation under list item
    ].join('\n');

    const r = parseYaml<unknown>(queueYaml, 'queue.yaml');
    expect(r.data).toBeNull();
    const errorWarning = r.warnings.find((w) => w.severity === 'error');
    expect(errorWarning).toBeDefined();
    expect(typeof errorWarning?.line).toBe('number');
    expect((errorWarning?.line ?? 0) > 0).toBe(true);
  });

  it('tolerates non-ASCII / mojibake content without throwing', () => {
    const mojibake = 'name: "Ã¤Ã¶Ã¼ â mojibake �"\nok: true';
    expect(() => parseYaml<unknown>(mojibake, 'queue.yaml')).not.toThrow();
    const r = parseYaml<{ name: string; ok: boolean }>(mojibake, 'queue.yaml');
    // Valid YAML despite odd bytes — should parse, not crash.
    expect(r.data?.ok).toBe(true);
  });
});
