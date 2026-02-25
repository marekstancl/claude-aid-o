/**
 * Unit tests for server/parsers/json.ts
 *
 * Covers: valid JSON from real .aid-o/ fixtures (plan.json, plan_progress.json),
 * camelCase key conversion, malformed JSON, and empty content.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { parseJson } from '../../../server/parsers/json.ts';
import type { PlanJSON, PlanProgress } from '../../../server/types.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = join(__dirname, '../../fixtures');

function readFixture(name: string): string {
  return readFileSync(join(FIXTURES, name), 'utf-8');
}

// ---------------------------------------------------------------------------
// Valid JSON — plan.json (real .aid-o/ data)
// ---------------------------------------------------------------------------

describe('parseJson — valid plan.json', () => {
  it('parses the fixture successfully and returns non-null data', () => {
    const content = readFixture('plan.json');
    const result = parseJson<PlanJSON>(content, 'plan.json');

    expect(result.data).not.toBeNull();
  });

  it('returns no warnings for a valid JSON document', () => {
    const content = readFixture('plan.json');
    const result = parseJson<PlanJSON>(content, 'plan.json');

    expect(result.warnings).toHaveLength(0);
  });

  it('converts snake_case keys to camelCase', () => {
    const content = readFixture('plan.json');
    const result = parseJson<PlanJSON>(content, 'plan.json');

    // Source has "epic_id" — output should have "epicId".
    expect(result.data).toHaveProperty('epicId', 'E-005-1_4-gui-foundation');
    // Source has "run_id" — output should have "runId".
    expect(result.data).toHaveProperty('runId', '20260225T140000Z');
    // Source has "generated_at" — output should have "generatedAt".
    expect(result.data).toHaveProperty('generatedAt', '2026-02-25T14:00:10Z');
    // Source has "total_steps" — output should have "totalSteps".
    expect(result.data).toHaveProperty('totalSteps', 6);
    // Source has "source_plan" — output should have "sourcePlan".
    expect(result.data).toHaveProperty('sourcePlan', '.aid-o/01-plans/P005-C-aid-gui-backend-post-prototype.md');
  });

  it('does NOT retain raw snake_case keys', () => {
    const content = readFixture('plan.json');
    const result = parseJson<Record<string, unknown>>(content, 'plan.json');

    expect(result.data).not.toHaveProperty('epic_id');
    expect(result.data).not.toHaveProperty('run_id');
    expect(result.data).not.toHaveProperty('generated_at');
  });

  it('parses the waves array correctly', () => {
    const content = readFixture('plan.json');
    const result = parseJson<PlanJSON>(content, 'plan.json');

    expect(result.data?.waves).toHaveLength(6);
    expect(result.data?.waves?.[0]).toEqual({ wave: 0, steps: ['step_0_backend'] });
  });

  it('parses the gates array correctly', () => {
    const content = readFixture('plan.json');
    const result = parseJson<PlanJSON>(content, 'plan.json');

    expect(result.data?.gates).toEqual(['tests_pass', 'lint_pass', 'type_check']);
  });

  it('converts snake_case keys inside nested step objects', () => {
    const content = readFixture('plan.json');
    const result = parseJson<PlanJSON>(content, 'plan.json');

    const firstStep = result.data?.steps[0];
    // Source has "depends_on" — output should have "dependsOn".
    expect(firstStep).toHaveProperty('dependsOn');
    // Source has "allowed_paths" — output should have "allowedPaths".
    expect(firstStep).toHaveProperty('allowedPaths');
    // Source has "forbidden_paths" — output should have "forbiddenPaths".
    expect(firstStep).toHaveProperty('forbiddenPaths');
  });

  it('propagates the source string in the result', () => {
    const content = readFixture('plan.json');
    const source = 'fixtures/plan.json';
    const result = parseJson<PlanJSON>(content, source);

    expect(result.source).toBe(source);
  });
});

// ---------------------------------------------------------------------------
// Valid JSON — plan_progress.json (real .aid-o/ data)
// ---------------------------------------------------------------------------

describe('parseJson — valid plan_progress.json', () => {
  it('parses successfully with non-null data', () => {
    const content = readFixture('plan_progress.json');
    const result = parseJson<PlanProgress>(content, 'plan_progress.json');

    expect(result.data).not.toBeNull();
    expect(result.warnings).toHaveLength(0);
  });

  it('converts top-level snake_case keys', () => {
    const content = readFixture('plan_progress.json');
    const result = parseJson<PlanProgress>(content, 'plan_progress.json');

    expect(result.data).toHaveProperty('epicId', 'E-005-1_4-gui-foundation');
    expect(result.data).toHaveProperty('runId', '20260225T140000Z');
    expect(result.data).toHaveProperty('currentStep', 'step_5_qa');
    expect(result.data).toHaveProperty('baseCommit', '3867b38');
  });

  it('converts snake_case keys inside nested step progress objects', () => {
    const content = readFixture('plan_progress.json');
    // Access the raw parsed result as a plain record to inspect actual key names.
    const result = parseJson<Record<string, unknown>>(content, 'plan_progress.json');

    // snakeToCamel converts object KEYS too, so "step_0_backend" -> "step0Backend"
    // and the inner fields "started_at" -> "startedAt" etc.
    const steps = result.data?.steps as Record<string, Record<string, unknown>>;
    expect(steps).toBeDefined();

    const step0 = steps['step0Backend'];
    expect(step0).toBeDefined();
    expect(step0).toHaveProperty('status', 'done');
    // Source has "started_at" — output should have "startedAt".
    expect(step0).toHaveProperty('startedAt', '2026-02-25T14:00:15Z');
    // Source has "completed_at" — output should have "completedAt".
    expect(step0).toHaveProperty('completedAt', '2026-02-25T14:02:00Z');
  });

  it('reflects the executing step correctly', () => {
    const content = readFixture('plan_progress.json');
    const result = parseJson<Record<string, unknown>>(content, 'plan_progress.json');

    // "step_5_qa" -> "step5Qa" after snakeToCamel key conversion
    const steps = result.data?.steps as Record<string, Record<string, unknown>>;
    const step5 = steps['step5Qa'];
    expect(step5).toBeDefined();
    expect(step5).toHaveProperty('status', 'executing');
    expect(step5).not.toHaveProperty('completedAt');
  });
});

// ---------------------------------------------------------------------------
// Empty content
// ---------------------------------------------------------------------------

describe('parseJson — empty content', () => {
  it('returns null data for an empty string', () => {
    const result = parseJson('', 'test.json');

    expect(result.data).toBeNull();
  });

  it('returns a warning with severity "warning" for empty content', () => {
    const result = parseJson('', 'test.json');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('warning');
    expect(result.warnings[0].message).toContain('empty');
  });

  it('returns null data for whitespace-only content', () => {
    const result = parseJson('  \n  ', 'test.json');

    expect(result.data).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Malformed JSON
// ---------------------------------------------------------------------------

describe('parseJson — malformed JSON', () => {
  it('returns null data instead of throwing', () => {
    const content = readFixture('malformed.json');
    const result = parseJson(content, 'malformed.json');

    expect(result.data).toBeNull();
  });

  it('returns an error-severity warning for malformed JSON', () => {
    const content = readFixture('malformed.json');
    const result = parseJson(content, 'malformed.json');

    expect(result.warnings).toHaveLength(1);
    expect(result.warnings[0].severity).toBe('error');
    expect(result.warnings[0].message).toContain('Malformed JSON');
  });

  it('propagates the source string even when parsing fails', () => {
    const content = readFixture('malformed.json');
    const source = 'fixtures/malformed.json';
    const result = parseJson(content, source);

    expect(result.source).toBe(source);
  });

  it('returns null data for inline invalid JSON', () => {
    const result = parseJson('{broken: json}', 'inline.json');

    expect(result.data).toBeNull();
    expect(result.warnings[0].severity).toBe('error');
  });
});

// ---------------------------------------------------------------------------
// Inline valid JSON — no file I/O
// ---------------------------------------------------------------------------

describe('parseJson — inline valid content', () => {
  it('parses a simple flat object', () => {
    const content = '{"status": "active", "version": 2}';
    const result = parseJson<{ status: string; version: number }>(content, 'inline.json');

    expect(result.data).toEqual({ status: 'active', version: 2 });
    expect(result.warnings).toHaveLength(0);
  });

  it('parses a JSON array at the top level', () => {
    const content = '[{"id": 1}, {"id": 2}]';
    const result = parseJson<{ id: number }[]>(content, 'inline.json');

    expect(result.data).toHaveLength(2);
    expect(result.data?.[0]).toEqual({ id: 1 });
  });

  it('converts snake_case keys in a simple inline object', () => {
    const content = '{"epic_id": "E-001", "run_id": "run_001"}';
    const result = parseJson<{ epicId: string; runId: string }>(content, 'inline.json');

    expect(result.data).toEqual({ epicId: 'E-001', runId: 'run_001' });
  });
});
