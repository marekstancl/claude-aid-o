/**
 * Unit tests for server/parsers/jsonl.ts
 *
 * Covers: valid JSONL from real stage_log fixture, camelCase key conversion,
 * malformed lines, empty content, empty lines skipped, and mixed valid/invalid.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { parseJsonl } from '../../../server/parsers/jsonl.ts';
import type { StageLogEntry } from '../../../server/types.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(__dirname, '../../fixtures');

function readFixture(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf-8');
}

// ---------------------------------------------------------------------------
// Valid JSONL — stage_log.jsonl (real .aid-o/ data)
// ---------------------------------------------------------------------------

describe('parseJsonl — valid stage_log.jsonl', () => {
  it('parses all valid lines and returns the correct entry count', () => {
    const content = readFixture('stage_log.jsonl');
    const result = parseJsonl<StageLogEntry>(content, 'stage_log.jsonl');

    // The fixture has 10 non-empty lines (plus a trailing newline that should be skipped).
    expect(result.data).toHaveLength(10);
  });

  it('returns no warnings for a fully valid JSONL file', () => {
    const content = readFixture('stage_log.jsonl');
    const result = parseJsonl<StageLogEntry>(content, 'stage_log.jsonl');

    expect(result.warnings).toHaveLength(0);
  });

  it('converts snake_case keys to camelCase for every entry', () => {
    const content = readFixture('stage_log.jsonl');
    const result = parseJsonl<StageLogEntry>(content, 'stage_log.jsonl');

    // All entries should have camelCase keys — spot-check first and last.
    const first = result.data?.[0];
    expect(first).toHaveProperty('timestamp', '2026-02-24T14:40:00Z');
    expect(first).toHaveProperty('state', 'IDLE');
    expect(first).toHaveProperty('action', 'load_epic');
    // Source JSONL has "result" key — not snake_case, should remain as-is.
    expect(first).toHaveProperty('result', 'pass');
    // step is null in the first entry.
    expect(first).toHaveProperty('step', null);
  });

  it('parses the executing-state entry correctly (has a non-null step)', () => {
    const content = readFixture('stage_log.jsonl');
    const result = parseJsonl<StageLogEntry>(content, 'stage_log.jsonl');

    const dispatchEntry = result.data?.find((e) => e.action === 'dispatch_agent');
    expect(dispatchEntry).toBeDefined();
    expect(dispatchEntry?.step).toBe('step_1_architect');
    expect(dispatchEntry?.state).toBe('EXECUTING');
  });

  it('propagates the source string in the result', () => {
    const content = readFixture('stage_log.jsonl');
    const source = 'fixtures/stage_log.jsonl';
    const result = parseJsonl<StageLogEntry>(content, source);

    expect(result.source).toBe(source);
  });
});

// ---------------------------------------------------------------------------
// Empty content
// ---------------------------------------------------------------------------

describe('parseJsonl — empty content', () => {
  it('returns an empty data array (not null) for empty string content', () => {
    const result = parseJsonl('', 'test.jsonl');

    expect(result.data).toEqual([]);
  });

  it('returns a warning when content is empty', () => {
    const result = parseJsonl('', 'test.jsonl');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('warning');
    expect(result.warnings[0].message).toContain('empty');
  });

  it('returns an empty array for whitespace-only content', () => {
    const result = parseJsonl('   \n\n   ', 'test.jsonl');

    expect(result.data).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Empty lines in valid JSONL are skipped silently
// ---------------------------------------------------------------------------

describe('parseJsonl — empty lines skipped silently', () => {
  it('skips blank lines between valid entries without warnings', () => {
    const content = [
      '{"state": "IDLE", "action": "start"}',
      '',
      '{"state": "EXECUTING", "action": "dispatch"}',
      '',
      '',
      '{"state": "DONE", "action": "complete"}',
    ].join('\n');

    const result = parseJsonl<{ state: string; action: string }>(content, 'inline.jsonl');

    expect(result.data).toHaveLength(3);
    expect(result.warnings).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Malformed lines — mixed valid/invalid
// ---------------------------------------------------------------------------

describe('parseJsonl — malformed.jsonl (mixed valid and invalid lines)', () => {
  it('parses the valid lines and returns them in data', () => {
    const content = readFixture('malformed.jsonl');
    const result = parseJsonl<{ timestamp: string; action: string }>(content, 'malformed.jsonl');

    // Fixture has 3 valid JSON lines and 2 invalid ones.
    expect(result.data).toHaveLength(3);
  });

  it('produces one warning per invalid line', () => {
    const content = readFixture('malformed.jsonl');
    const result = parseJsonl<Record<string, unknown>>(content, 'malformed.jsonl');

    // 2 invalid lines in the fixture.
    expect(result.warnings).toHaveLength(2);
  });

  it('assigns warning severity "warning" (not "error") for bad lines', () => {
    const content = readFixture('malformed.jsonl');
    const result = parseJsonl<Record<string, unknown>>(content, 'malformed.jsonl');

    for (const w of result.warnings) {
      expect(w.severity).toBe('warning');
    }
  });

  it('includes the line number in each malformed-line warning', () => {
    const content = readFixture('malformed.jsonl');
    const result = parseJsonl<Record<string, unknown>>(content, 'malformed.jsonl');

    // Both warnings must have a numeric line property >= 1.
    for (const w of result.warnings) {
      expect(w.line).toBeGreaterThanOrEqual(1);
    }
  });

  it('includes "Malformed JSON on line" in the warning message', () => {
    const content = readFixture('malformed.jsonl');
    const result = parseJsonl<Record<string, unknown>>(content, 'malformed.jsonl');

    for (const w of result.warnings) {
      expect(w.message).toContain('Malformed JSON on line');
    }
  });

  it('converts camelCase keys in the successfully parsed entries', () => {
    const content = readFixture('malformed.jsonl');
    const result = parseJsonl<{ timestamp: string; action: string }>(content, 'malformed.jsonl');

    // All parsed entries should have a "timestamp" field (already camelCase).
    const firstEntry = result.data?.[0];
    expect(firstEntry?.timestamp).toBe('2026-02-24T14:40:00Z');
  });
});

// ---------------------------------------------------------------------------
// All-invalid JSONL (every line fails)
// ---------------------------------------------------------------------------

describe('parseJsonl — all invalid lines', () => {
  it('returns an empty data array and one warning per line', () => {
    const content = 'not json\nalso not json\n{broken';
    const result = parseJsonl<Record<string, unknown>>(content, 'bad.jsonl');

    expect(result.data).toHaveLength(0);
    expect(result.warnings).toHaveLength(3);
  });
});

// ---------------------------------------------------------------------------
// Single valid line
// ---------------------------------------------------------------------------

describe('parseJsonl — single valid line', () => {
  it('returns exactly one entry with the correct parsed data', () => {
    const content = '{"epic_id": "E-001", "run_id": "run_001", "result": "pass"}\n';
    const result = parseJsonl<{ epicId: string; runId: string; result: string }>(content, 'single.jsonl');

    expect(result.data).toHaveLength(1);
    expect(result.data?.[0]).toEqual({
      epicId: 'E-001',
      runId: 'run_001',
      result: 'pass',
    });
    expect(result.warnings).toHaveLength(0);
  });
});
