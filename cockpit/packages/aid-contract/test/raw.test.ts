import { describe, it, expect } from 'vitest';
import type { AidFsmState, AidStateYaml } from '../src/raw.js';

describe('raw contract', () => {
  it('AidFsmState accepts ERROR', () => {
    const x: AidFsmState = 'ERROR';
    expect(x).toBe('ERROR');
  });

  it('AidStateYaml accepts pm_decision omitted', () => {
    const s: AidStateYaml = {
      epic_id: 'E-001',
      run_id: 'R-001',
      state: 'READY',
      current_step: 0,
      total_steps: 3,
      mode: 'manual',
      branch: 'main',
      base_commit: 'abc123',
      gate_retries: 0,
      escalation_count: 0,
      started_at: '2026-01-01T00:00:00Z',
    };
    expect(s.pm_decision).toBeUndefined();
  });

  it('AidStateYaml accepts plan_path: null', () => {
    const s: AidStateYaml = {
      epic_id: 'E-001',
      run_id: 'R-001',
      state: 'DONE',
      current_step: 3,
      total_steps: 3,
      mode: 'auto',
      branch: 'task/E-001/main',
      base_commit: 'abc123',
      gate_retries: 0,
      escalation_count: 0,
      started_at: '2026-01-01T00:00:00Z',
      plan_path: null,
    };
    expect(s.plan_path).toBeNull();
  });
});
