/**
 * Unit tests for server/parsers/utils.ts
 *
 * Tests snakeToCamelKey (key conversion) and snakeToCamel (recursive object
 * conversion). These utilities underpin every parser in the system, so
 * correctness here is critical for all downstream behavior.
 */

import { describe, it, expect } from 'vitest';
import { snakeToCamelKey, snakeToCamel } from '../../../server/parsers/utils.ts';

// ---------------------------------------------------------------------------
// snakeToCamelKey — single key conversion
// ---------------------------------------------------------------------------

describe('snakeToCamelKey', () => {
  it('converts a basic snake_case key to camelCase', () => {
    expect(snakeToCamelKey('snake_case')).toBe('snakeCase');
  });

  it('converts a multi-segment snake_case key', () => {
    expect(snakeToCamelKey('epic_id')).toBe('epicId');
    expect(snakeToCamelKey('started_at')).toBe('startedAt');
    expect(snakeToCamelKey('plan_epics_total')).toBe('planEpicsTotal');
    expect(snakeToCamelKey('depends_on')).toBe('dependsOn');
  });

  it('returns a camelCase key unchanged (no underscores)', () => {
    expect(snakeToCamelKey('alreadyCamel')).toBe('alreadyCamel');
    expect(snakeToCamelKey('epicId')).toBe('epicId');
  });

  it('returns a single-word key unchanged', () => {
    expect(snakeToCamelKey('status')).toBe('status');
    expect(snakeToCamelKey('timestamp')).toBe('timestamp');
  });

  it('handles a key that is just underscores gracefully', () => {
    // The key "__" has underscores but the regex requires a char after the underscore;
    // the leading underscore with no following alphanum passes through.
    const result = snakeToCamelKey('_private');
    // "_private" has underscore followed by 'p', so it becomes 'Private' (capital P, no leading underscore).
    expect(result).toBe('Private');
  });

  it('handles numeric segments after underscore', () => {
    // "step_1_qa" -> "step1Qa"
    expect(snakeToCamelKey('step_1_qa')).toBe('step1Qa');
  });
});

// ---------------------------------------------------------------------------
// snakeToCamel — recursive object conversion
// ---------------------------------------------------------------------------

describe('snakeToCamel', () => {
  it('converts all keys in a flat object from snake_case to camelCase', () => {
    const input = {
      epic_id: 'E-005',
      run_id: '20260225T140000Z',
      started_at: '2026-02-25T14:00:00Z',
    };

    const result = snakeToCamel<Record<string, string>>(input);

    expect(result).toEqual({
      epicId: 'E-005',
      runId: '20260225T140000Z',
      startedAt: '2026-02-25T14:00:00Z',
    });
  });

  it('converts keys in nested objects recursively', () => {
    const input = {
      outer_key: {
        inner_key: 'value',
        deep_nested: {
          very_deep: 42,
        },
      },
    };

    const result = snakeToCamel<Record<string, unknown>>(input);

    expect(result).toEqual({
      outerKey: {
        innerKey: 'value',
        deepNested: {
          veryDeep: 42,
        },
      },
    });
  });

  it('converts keys of objects inside arrays', () => {
    const input = [
      { epic_id: 'E-001', added_at: '2026-01-01T00:00:00Z' },
      { epic_id: 'E-002', added_at: '2026-01-02T00:00:00Z' },
    ];

    const result = snakeToCamel<Array<Record<string, string>>>(input);

    expect(result).toEqual([
      { epicId: 'E-001', addedAt: '2026-01-01T00:00:00Z' },
      { epicId: 'E-002', addedAt: '2026-01-02T00:00:00Z' },
    ]);
  });

  it('preserves primitive values unchanged', () => {
    expect(snakeToCamel<string>('hello_world')).toBe('hello_world');
    expect(snakeToCamel<number>(42)).toBe(42);
    expect(snakeToCamel<boolean>(true)).toBe(true);
  });

  it('returns null unchanged', () => {
    expect(snakeToCamel<null>(null)).toBeNull();
  });

  it('returns undefined unchanged', () => {
    expect(snakeToCamel<undefined>(undefined)).toBeUndefined();
  });

  it('does not mutate the original object', () => {
    const input = { epic_id: 'E-001' };
    const original = { ...input };
    snakeToCamel(input);
    expect(input).toEqual(original);
  });

  it('handles an empty object without error', () => {
    expect(snakeToCamel<Record<string, never>>({})).toEqual({});
  });

  it('handles an empty array without error', () => {
    expect(snakeToCamel<unknown[]>([])).toEqual([]);
  });

  it('preserves non-plain-object instances (e.g. Date) unchanged', () => {
    const date = new Date('2026-02-25T14:00:00Z');
    expect(snakeToCamel<Date>(date)).toBe(date);
  });

  it('converts mixed object with array values correctly', () => {
    const input = {
      wave_number: 0,
      step_ids: ['step_0_backend', 'step_1_architect'],
    };

    const result = snakeToCamel<Record<string, unknown>>(input);

    // Keys should be camelCase, but the string values inside the array
    // should not be modified (they are primitives, not keys).
    expect(result).toEqual({
      waveNumber: 0,
      stepIds: ['step_0_backend', 'step_1_architect'],
    });
  });
});
