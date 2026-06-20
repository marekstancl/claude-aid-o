/**
 * RunDetail builder test suite (EPIC E-047-2_7, Step 8).
 *
 * Uses temp-dir fixtures (mkdtemp) that MIRROR the real E-046 evidence shapes
 * (the spec's grounding set) — the exact byte-patterns observed on disk:
 *  - fsm-state.yaml whose `steps[]` are all `status: pending` (the trap §4.0 #2)
 *  - compliance.json with `checks.verifier_outputs.*_provenance` (§4.0 #3)
 *  - timelines with ZERO dispatch events but verifier-output md files present
 *  - gates_report.json with `plan_diff` exit_code:2 (skip-as-pass §4.0 #6)
 *  - the THREE audit score shapes (frontmatter / heading / table §4.0 #5)
 *
 * NEVER reads the live tree — fixtures are isolated temp dirs torn down per test.
 *
 * Acceptance Criteria (Step 8 dispatch):
 *  AC1  done_phase:review run → pmDecision:null (pre-merge), no crash on absence.
 *  AC2  steps[] from timeline + verify-file mtimes NOT fsm-state.steps[]; a DONE
 *       run whose fsm steps[] are all pending still reports completed steps.
 *  AC3  checkpoint provenance from compliance verifier_outputs.*_provenance
 *       (provenanceSource:'compliance'); zero-dispatch run NOT 'unverifiable'.
 *  AC4  CP2/CP3 repeatCount null + repeatSource null when no dispatch events
 *       (NEVER 0); CP1 repeatCount from file count.
 *  AC5  audit score parses from all three shapes; null+warning when none.
 *  AC6  compliance.failures is ComplianceFailure[] with severity preserved;
 *       compliance is null (not {}) when no compliance.json.
 *  AC7  gates: plan_diff exit 2 → 'skipped'; per-gate durationMs preserved.
 *  AC8  buildRunDetail wired as the Step 7 cache loader (cache memoizes it).
 */

import { mkdtemp, mkdir, writeFile, rm, symlink } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { FsReader } from './fs-reader.js';
import { createPathMap } from './pathmap.js';
import { buildRunDetail, type RunDetailDeps } from './run-detail.js';
import { createScannerCache } from './scanner-cache.js';

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'aid-rundetail-'));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const deps = (): RunDetailDeps => ({
  fs: new FsReader(),
  pathMap: createPathMap({ projectsRoot: root, hostRoot: root }),
});

// ---------------------------------------------------------------------------
// Fixture material — verbatim slices of the real E-046 evidence shapes.
// ---------------------------------------------------------------------------

/** fsm-state.yaml whose `steps[]` are all pending (the §4.0 #2 trap). */
function fsmStateDone(opts: { donePhase: string; pmDecision?: string }): string {
  const pm = opts.pmDecision ? `\npm_decision: ${opts.pmDecision}` : '';
  return `epic_id: E-046-1_3
run_id: R-E046-1
state: DONE
current_step: 7
total_steps: 7
mode: full
branch: task/E-046-1_3/main
base_commit: 4d6a84588fa6acc8eefac9b1a7c91c2651a9243f
gate_retries: 0
escalation_count: 0
streamlined_mode: false
started_at: "2026-06-18T14:04:10Z"
created_at: 2026-06-18T14:04:10Z
plan_path: null
steps:
  - id: 1
    name: ""
    status: pending
    started_at: null
    completed_at: null
  - id: 2
    name: ""
    status: pending
    started_at: null
    completed_at: null
done_phase: ${opts.donePhase}${pm}
`;
}

/** compliance.json with the real verifier_outputs provenance block. */
function compliancePass(): string {
  return JSON.stringify({
    epic_id: 'E-046-1_3',
    run_id: 'R-E046-1',
    aid_version: 'v3',
    deploy_era: 'post-session-b',
    evaluated_at: '2026-06-18T17:56:16Z',
    coverage_mode: 'full',
    checks: {
      branch_correct: true,
      gates_generated_by: true,
      verifier_outputs: {
        cp2_per_step_dispatched: true,
        cp2_per_step_verdict: 'pass',
        cp2_per_step_provenance: ['agent_tool', 'agent_tool', 'agent_tool'],
        cp3_code_review_dispatched: true,
        cp3_code_review_verdict: 'pass',
        cp3_code_review_provenance: 'agent_tool',
        cp3_security_dispatched: true,
        cp3_security_verdict: 'pass',
        cp3_security_provenance: 'agent_tool',
        aggregate: true,
        provenance_aggregate: 'agent_tool',
      },
    },
    failures: [],
    force_override_count: 0,
    force_override_reasons: [],
    overall: 'pass',
    notes: [],
  });
}

/** compliance.json with a non-empty advisory failure (E-040 real shape). */
function complianceFail(): string {
  return JSON.stringify({
    epic_id: 'E-040-1_1',
    run_id: 'R-E040-1',
    aid_version: 'v3',
    deploy_era: 'post-session-b',
    evaluated_at: '2026-05-31T20:00:00Z',
    coverage_mode: 'full',
    checks: { verifier_outputs: { provenance_aggregate: 'fabricated' } },
    failures: [
      {
        check: 'verifier_provenance',
        severity: 'advisory',
        evidence: 'provenance_aggregate=fabricated (1+ verifier outputs unverifiable)',
        promoted_at: null,
      },
    ],
    force_override_count: 0,
    force_override_reasons: [],
    overall: 'fail',
    notes: [],
  });
}

/** gates_report.json with plan_diff exit_code:2 (skip-as-pass). */
function gatesReport(): string {
  return JSON.stringify({
    epic_id: 'E-046-1_3',
    run_id: 'R-E046-1',
    overall: 'pass',
    completed_at: '2026-06-18T15:22:47Z',
    gates: {
      bats_fsm: { gate: 'bats_fsm', result: 'pass', exit_code: 0, duration_ms: 18770, output: '1..58\nok 1', attempts: 1 },
      plan_diff: { gate: 'plan_diff', result: 'pass', exit_code: 2, duration_ms: 49, output: '', attempts: 1 },
    },
    _generated_by: 'aid-run-gates.sh@v2.16.0',
  });
}

/** Audit report with score in the `**Total** N/100` table shape (E-046-1). */
const AUDIT_TABLE = `blocking_findings: false
_generated_by: aid-orchestrator:auditor@E-046-1_3
_generated_at: 2026-06-18T21:00:00Z
classification: FULL_REVIEW

# Audit Report — E-046-1_3

## Score

| Dimension | Score |
|-----------|-------|
| Code      | 22/25 |
| Security  | 25/25 |
| **Total** | **89/100** |

---

## Findings

### Medium

**[CODE-1] stale references**
- Effort: S
- auto_fixable: true
`;

/** Audit report with score in the `## Score: N/100` heading shape (E-046-2). */
const AUDIT_HEADING = `# Audit Report — E-046-2_3
blocking_findings: false

## Score: 95/100

## Findings

### High

**[SEC-1] something risky**
- auto_fixable: false
`;

/** Audit report with score in the frontmatter `overall_score: N` shape (E-046-3). */
const AUDIT_FRONTMATTER = `blocking_findings: false
overall_score: 84

# Audit Report — E-046-3_3

## Executive Summary

Three low findings prevent a perfect score.

### Low

**[DOC-1] missing changelog**
`;

/** A verify markdown whose H1 carries the step name. */
function stepVerify(displayN: number, name: string): string {
  return `# Step ${displayN} Verify — ${name}\n\n## Result: PASS\n`;
}

/** A verifier-output md (provenance corroboration; no dispatch event). */
const VERIFIER_OUTPUT = `_generated_by: verifier
_generated_at: 2026-06-18T14:35:00Z
classification: RUN
verdict: pass

## CP2 Step Review
All ACs verified.
`;

/** A timeline with ZERO dispatch events (the common §4.0 #3 case). */
function timelineNoDispatch(): string {
  return [
    { ts: '2026-06-18T14:04:10Z', event: 'fsm_init', total_steps: 7, mode: 'full' },
    { ts: '2026-06-18T14:29:24Z', event: 'fsm_transition', from: 'READY', to: 'EXECUTE' },
    { ts: '2026-06-18T17:56:16Z', event: 'fsm_done_advance', from_phase: 'review', to_phase: 'release' },
  ]
    .map((r) => JSON.stringify(r))
    .join('\n');
}

/** A timeline WITH dispatch events grouped by focus (E-040 real shape). */
function timelineWithDispatch(): string {
  const rows: Record<string, unknown>[] = [];
  for (let n = 0; n < 3; n++) {
    rows.push({ ts: `2026-05-31T17:0${n}:00Z`, event: 'verifier_dispatch_start', focus: `cp2-step-${n}`, step_n: n });
    rows.push({ ts: `2026-05-31T17:0${n}:01Z`, event: 'verifier_dispatch_complete', focus: `cp2-step-${n}`, step_n: n });
  }
  // CP3 dispatched twice (a repeat) for the same focus.
  rows.push({ ts: '2026-05-31T18:36:52Z', event: 'verifier_dispatch_start', focus: 'cp3-code-review', step_n: null });
  rows.push({ ts: '2026-05-31T18:40:00Z', event: 'verifier_dispatch_start', focus: 'cp3-code-review', step_n: null });
  return rows.map((r) => JSON.stringify(r)).join('\n');
}

// ---------------------------------------------------------------------------
// Fixture builder
// ---------------------------------------------------------------------------

interface RunFixture {
  fsm?: string;
  compliance?: string | null;
  gates?: string;
  audit?: string;
  timeline?: string;
  /** Number of step-N-verify.md / verifier-output-step-N.md files (0-based). */
  verifySteps?: number;
  cp3Outputs?: boolean;
  cp4Output?: boolean;
  planJson?: string;
  /** Place gates_report.json at root instead of gates/. */
  gatesAtRoot?: boolean;
}

async function makeRun(
  projectId: string,
  epicId: string,
  runId: string,
  fx: RunFixture,
): Promise<string> {
  const runDir = join(root, projectId, '.aid-o', 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  const w = (name: string, content: string) => writeFile(join(runDir, name), content, 'utf-8');

  if (fx.fsm !== undefined) await w('fsm-state.yaml', fx.fsm);
  if (fx.compliance) await w('compliance.json', fx.compliance);
  if (fx.audit !== undefined) await w('audit-report.md', fx.audit);
  if (fx.timeline !== undefined) await w('timeline.jsonl', fx.timeline);
  if (fx.planJson !== undefined) await w('plan.json', fx.planJson);

  if (fx.gates !== undefined) {
    if (fx.gatesAtRoot) {
      await w('gates_report.json', fx.gates);
    } else {
      await mkdir(join(runDir, 'gates'), { recursive: true });
      await writeFile(join(runDir, 'gates', 'gates_report.json'), fx.gates, 'utf-8');
    }
  }

  if (fx.verifySteps) {
    for (let i = 0; i < fx.verifySteps; i++) {
      await w(`step-${i}-verify.md`, stepVerify(i + 1, `step ${i + 1} work`));
      await w(`verifier-output-step-${i}.md`, VERIFIER_OUTPUT);
    }
  }
  if (fx.cp3Outputs) {
    await w('verifier-output-cp3-code-review.md', VERIFIER_OUTPUT);
    await w('verifier-output-cp3-security.md', VERIFIER_OUTPUT);
  }
  if (fx.cp4Output) {
    await w('verifier-output-cp4-curator-validation.md', VERIFIER_OUTPUT);
  }
  return runDir;
}

const PLAN_JSON = JSON.stringify({
  epic_id: 'E-046-1_3',
  steps: [
    { id: 'step_1_backend', role: 'backend', objective: 'Replace the broken derivation' },
    { id: 'step_2_qa', role: 'qa', objective: 'Add regression tests' },
    { id: 'step_3_docs', role: 'docs-writer', objective: 'Update docs' },
  ],
});

// ===========================================================================
// AC1 — done_phase:review → pmDecision:null (pre-merge)
// ===========================================================================

describe('AC1 — pmDecision null pre-merge', () => {
  it('a done_phase:review run yields pmDecision:null and does not crash', async () => {
    const runDir = await makeRun('proj', 'E-046-3_3', 'R-E046-3', {
      fsm: fsmStateDone({ donePhase: 'review' }), // NO pm_decision line
      timeline: timelineNoDispatch(),
      verifySteps: 6,
    });
    const rd = await buildRunDetail('proj', 'E-046-3_3', 'R-E046-3', runDir, deps());
    expect(rd.pmDecision).toBeNull();
    expect(rd.donePhase).toBe('review');
    expect(rd.state).toBe('DONE');
  });

  it('a done_phase:release run with pm_decision:merge reports the decision', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      timeline: timelineNoDispatch(),
      verifySteps: 7,
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    expect(rd.pmDecision).toBe('merge');
    expect(rd.donePhase).toBe('release');
  });

  it('never throws on a completely empty run dir (stub)', async () => {
    const runDir = join(root, 'proj', '.aid-o', 'work', 'evidence', 'E-X', 'R-X');
    await mkdir(runDir, { recursive: true });
    const rd = await buildRunDetail('proj', 'E-X', 'R-X', runDir, deps());
    expect(rd.format).toBe('stub');
    expect(rd.state).toBe('READY');
    expect(rd.pmDecision).toBeNull();
    expect(rd.steps).toEqual([]);
    expect(rd.compliance).toBeNull();
    expect(rd.audit.present).toBe(false);
  });
});

// ===========================================================================
// AC2 — steps[] from timeline + verify-file mtimes, NOT fsm-state.steps[]
// ===========================================================================

describe('AC2 — steps derived from evidence, not fsm-state.steps[]', () => {
  it('a DONE run whose fsm steps[] are all pending still reports completed steps', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      timeline: timelineNoDispatch(),
      verifySteps: 7,
      planJson: PLAN_JSON,
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    // fsm-state.steps[] were ALL pending — the builder must IGNORE them.
    expect(rd.steps).toHaveLength(7);
    const doneCount = rd.steps.filter((s) => s.status === 'done').length;
    expect(doneCount).toBe(7); // all 7 verify files present → all done
    // roles come from plan.json where available
    expect(rd.steps[0].role).toBe('backend');
    expect(rd.steps[1].role).toBe('qa');
    // names come from the verify-file H1 title
    expect(rd.steps[0].name).toContain('Verify');
    // completedAt approximated from verify-file mtime
    expect(rd.steps[0].completedAt).not.toBeNull();
  });
});

// ===========================================================================
// AC3 — provenance from compliance.json verifier_outputs (not 'unverifiable')
// ===========================================================================

describe('AC3 — provenance read from compliance, not re-derived', () => {
  it('a run with verifier-output md files but ZERO dispatch events is NOT unverifiable', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      compliance: compliancePass(),
      timeline: timelineNoDispatch(), // zero dispatch events
      verifySteps: 7,
      cp3Outputs: true,
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    const cp2 = rd.checkpoints.find((c) => c.id === 'CP2')!;
    const cp3 = rd.checkpoints.find((c) => c.id === 'CP3')!;
    // Provenance comes from compliance.json, sourced as 'compliance'.
    expect(cp2.provenanceSource).toBe('compliance');
    expect(cp2.provenance).toEqual(['agent_tool', 'agent_tool', 'agent_tool']);
    expect(cp3.provenanceSource).toBe('compliance');
    expect(cp3.provenance).toEqual(['agent_tool', 'agent_tool']);
    // NEVER unverifiable just because the timeline had no dispatch records.
    expect(cp2.verdict).not.toBe('unverifiable');
    expect(cp3.verdict).not.toBe('unverifiable');
  });

  it('provenance is null (not unverifiable) when compliance.json is absent', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      compliance: null,
      timeline: timelineNoDispatch(),
      verifySteps: 3,
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    const cp2 = rd.checkpoints.find((c) => c.id === 'CP2')!;
    expect(cp2.provenance).toBeNull();
    expect(cp2.provenanceSource).toBeNull();
    expect(cp2.verdict).toBeNull(); // "not recorded", NOT unverifiable
  });
});

// ===========================================================================
// AC4 — repeatCount null+null when no dispatch; CP1 from file count
// ===========================================================================

describe('AC4 — repeatCount semantics', () => {
  it('CP2/CP3 repeatCount is null with repeatSource null when timeline has no dispatch events', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      compliance: compliancePass(),
      timeline: timelineNoDispatch(),
      verifySteps: 7,
      cp3Outputs: true,
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    const cp2 = rd.checkpoints.find((c) => c.id === 'CP2')!;
    const cp3 = rd.checkpoints.find((c) => c.id === 'CP3')!;
    expect(cp2.repeatCount).toBeNull(); // NEVER 0
    expect(cp2.repeatSource).toBeNull();
    expect(cp3.repeatCount).toBeNull();
    expect(cp3.repeatSource).toBeNull();
  });

  it('CP2/CP3 repeatCount derived from dispatch groups when events exist', async () => {
    const runDir = await makeRun('proj', 'E-040-1_1', 'R-E040-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      compliance: compliancePass(),
      timeline: timelineWithDispatch(),
      verifySteps: 3,
      cp3Outputs: true,
    });
    const rd = await buildRunDetail('proj', 'E-040-1_1', 'R-E040-1', runDir, deps());
    const cp2 = rd.checkpoints.find((c) => c.id === 'CP2')!;
    const cp3 = rd.checkpoints.find((c) => c.id === 'CP3')!;
    // Each cp2-step focus fired once → repeats = 0; source is timeline.
    expect(cp2.repeatCount).toBe(0);
    expect(cp2.repeatSource).toBe('timeline');
    // cp3-code-review fired twice → 1 repeat.
    expect(cp3.repeatCount).toBe(1);
    expect(cp3.repeatSource).toBe('timeline');
  });

  it('CP1 repeatCount comes from the file inventory (repeatSource files)', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      timeline: timelineNoDispatch(),
      planJson: PLAN_JSON, // plan.json present → CP1 dispatched
      verifySteps: 3,
    });
    // add a plan-diff.json so CP1 has a file signal
    await writeFile(join(runDir, 'plan-diff.json'), '{}', 'utf-8');
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    const cp1 = rd.checkpoints.find((c) => c.id === 'CP1')!;
    expect(cp1.repeatSource).toBe('files');
    expect(cp1.repeatCount).toBeGreaterThanOrEqual(1);
  });
});

// ===========================================================================
// AC5 — audit score in all three shapes; null+warning when none
// ===========================================================================

describe('AC5 — audit score three shapes', () => {
  it('parses the **Total** N/100 table shape (scoreSource table)', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      audit: AUDIT_TABLE,
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    expect(rd.audit.present).toBe(true);
    expect(rd.audit.overallScore).toBe(89);
    expect(rd.audit.scoreSource).toBe('table');
    expect(rd.audit.blockingFindings).toBe(false);
    expect(rd.audit.categories.length).toBeGreaterThanOrEqual(2);
  });

  it('parses the ## Score: N/100 heading shape (scoreSource heading)', async () => {
    const runDir = await makeRun('proj', 'E-046-2_3', 'R-E046-2', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      audit: AUDIT_HEADING,
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-2_3', 'R-E046-2', runDir, deps());
    expect(rd.audit.overallScore).toBe(95);
    expect(rd.audit.scoreSource).toBe('heading');
  });

  it('parses the frontmatter overall_score:N shape (scoreSource frontmatter)', async () => {
    const runDir = await makeRun('proj', 'E-046-3_3', 'R-E046-3', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      audit: AUDIT_FRONTMATTER,
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-3_3', 'R-E046-3', runDir, deps());
    expect(rd.audit.overallScore).toBe(84);
    expect(rd.audit.scoreSource).toBe('frontmatter');
  });

  it('null score + warning when no parseable score, but does not treat absence as fabrication', async () => {
    const runDir = await makeRun('proj', 'E-Z', 'R-Z', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      audit: '# Audit Report\n\nNo score here.\nblocking_findings: false\n',
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-Z', 'R-Z', runDir, deps());
    expect(rd.audit.present).toBe(true);
    expect(rd.audit.overallScore).toBeNull();
    expect(rd.audit.scoreSource).toBeNull();
    expect(rd.audit.warnings.some((w) => /score unparseable/i.test(w))).toBe(true);
    // _generated_by / classification absence is NOT treated as fabrication.
    expect(rd.audit.blockingFindings).toBe(false);
  });
});

// ===========================================================================
// AC6 — compliance.failures structured; null when no compliance.json
// ===========================================================================

describe('AC6 — compliance failures structured + null when absent', () => {
  it('failures[] is ComplianceFailure[] with severity preserved', async () => {
    const runDir = await makeRun('proj', 'E-040-1_1', 'R-E040-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      compliance: complianceFail(),
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-040-1_1', 'R-E040-1', runDir, deps());
    expect(rd.compliance).not.toBeNull();
    expect(rd.compliance!.overall).toBe('fail');
    expect(rd.compliance!.failures).toHaveLength(1);
    const f = rd.compliance!.failures[0];
    expect(f.check).toBe('verifier_provenance');
    expect(f.severity).toBe('advisory');
    expect(f.evidence).toContain('provenance_aggregate');
    // structured, not a raw string
    expect(typeof f).toBe('object');
  });

  it('compliance is null (not {}) when there is no compliance.json', async () => {
    const runDir = await makeRun('proj', 'E-046-3_3', 'R-E046-3', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-3_3', 'R-E046-3', runDir, deps());
    expect(rd.compliance).toBeNull();
  });
});

// ===========================================================================
// AC7 — gates: plan_diff exit 2 → skipped; durationMs preserved
// ===========================================================================

describe('AC7 — gates parsing', () => {
  it('plan_diff exit_code:2 maps to skipped (pass-as-spec) and durationMs preserved', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      gates: gatesReport(),
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    const planDiff = rd.gates.find((g) => g.gate === 'plan_diff')!;
    expect(planDiff.result).toBe('skipped');
    expect(planDiff.exitCode).toBe(2);
    expect(planDiff.durationMs).toBe(49);
    const bats = rd.gates.find((g) => g.gate === 'bats_fsm')!;
    expect(bats.result).toBe('pass');
    expect(bats.durationMs).toBe(18770);
  });

  it('normalizes the literal result:"skip" (real disk shape) to "skipped"', async () => {
    const gatesSkip = JSON.stringify({
      gates: {
        plan_diff: { gate: 'plan_diff', result: 'skip', exit_code: 0, duration_ms: 12, output: '', attempts: 1 },
      },
    });
    const runDir = await makeRun('proj', 'E-046-3_3', 'R-E046-3', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      gates: gatesSkip,
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-3_3', 'R-E046-3', runDir, deps());
    expect(rd.gates.find((g) => g.gate === 'plan_diff')!.result).toBe('skipped');
  });

  it('finds gates_report.json at the run-dir root as well as under gates/', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      gates: gatesReport(),
      gatesAtRoot: true,
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    expect(rd.gates.length).toBe(2);
  });
});

// ===========================================================================
// AC8 — buildRunDetail wired as the Step 7 cache loader (memoized)
// ===========================================================================

describe('AC8 — wired as the Step 7 cache RunDetailLoader', () => {
  it('createScannerCache uses the real loader and memoizes the RunDetail', async () => {
    // Build a discoverable workspace (config/ + work/ required by the scanner).
    const aido = join(root, 'proj', '.aid-o');
    await mkdir(join(aido, 'config'), { recursive: true });
    await mkdir(join(aido, 'tasks'), { recursive: true });
    await writeFile(
      join(aido, 'tasks', 'E-046-1_3.md'),
      '---\nstatus: active\nepic_id: E-046-1_3\n---\n\n# EPIC E-046-1_3\n',
      'utf-8',
    );
    await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'release', pmDecision: 'merge' }),
      compliance: compliancePass(),
      gates: gatesReport(),
      audit: AUDIT_TABLE,
      timeline: timelineNoDispatch(),
      verifySteps: 7,
      cp3Outputs: true,
      planJson: PLAN_JSON,
    });

    const cache = createScannerCache({
      projectsRoot: root,
      hostRoot: root,
      scanTtlMs: 600_000,
      activityBufferSize: 500,
    });
    await cache.buildIndex();

    const rd = await cache.getRunDetail('proj', 'E-046-1_3', 'R-E046-1');
    // The REAL loader produced a fully-assembled RunDetail.
    expect(rd.projectId).toBe('proj');
    expect(rd.epicId).toBe('E-046-1_3');
    expect(rd.runId).toBe('R-E046-1');
    expect(rd.state).toBe('DONE');
    expect(rd.audit.overallScore).toBe(89);
    expect(rd.gates.find((g) => g.gate === 'plan_diff')!.result).toBe('skipped');
    expect(rd.steps).toHaveLength(7);
    expect(rd.compliance).not.toBeNull();

    // Memoization: a second request returns the SAME object instance.
    expect(cache.runDetailCacheSize).toBe(1);
    const rd2 = await cache.getRunDetail('proj', 'E-046-1_3', 'R-E046-1');
    expect(rd2).toBe(rd);
    expect(cache.runDetailCacheSize).toBe(1);
  });
});

// ===========================================================================
// #9 — file list via root-relative walk (NEVER listDirRecursive basenames)
// ===========================================================================

describe('#9 — files via root-relative recursive walk', () => {
  it('nested gates/gates_report.json is listed with its directory, not flattened', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      gates: gatesReport(), // under gates/
      timeline: timelineNoDispatch(),
    });
    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    // The bugged listDirRecursive would give 'gates_report.json' (basename only).
    expect(rd.files).toContain('gates/gates_report.json');
    expect(rd.files).not.toContain('gates_report.json');
  });
});

// ===========================================================================
// Security — CWE-22 path traversal defense (buildRunDetail input validation)
// ===========================================================================

describe('Security — CWE-22 path traversal defense (buildRunDetail)', () => {
  it('rejects traversal in projectId and returns a safe stub', async () => {
    const runDir = join(root, 'proj', '.aid-o', 'work', 'evidence', 'E-X', 'R-X');
    await mkdir(runDir, { recursive: true });

    const rd = await buildRunDetail('../../etc', 'E-X', 'R-X', runDir, deps());
    expect(rd.format).toBe('stub');
    expect(rd.projectId).toBe('../../etc');
    // Should have security warning in audit
    expect(rd.audit.warnings[0]).toContain('Security check failed');
  });

  it('rejects traversal in epicId', async () => {
    const runDir = join(root, 'proj', '.aid-o', 'work', 'evidence', 'E-X', 'R-X');
    await mkdir(runDir, { recursive: true });

    const rd = await buildRunDetail('proj', '../../../etc', 'R-X', runDir, deps());
    expect(rd.format).toBe('stub');
    expect(rd.audit.warnings[0]).toContain('Security check failed');
  });

  it('rejects traversal in runId', async () => {
    const runDir = join(root, 'proj', '.aid-o', 'work', 'evidence', 'E-X', 'R-X');
    await mkdir(runDir, { recursive: true });

    const rd = await buildRunDetail('proj', 'E-X', '../../secret', runDir, deps());
    expect(rd.format).toBe('stub');
    expect(rd.audit.warnings[0]).toContain('Security check failed');
  });

  it('rejects empty segments', async () => {
    const runDir = join(root, 'proj', '.aid-o', 'work', 'evidence', 'E-X', 'R-X');
    await mkdir(runDir, { recursive: true });

    const rd = await buildRunDetail('', 'E-X', 'R-X', runDir, deps());
    expect(rd.format).toBe('stub');
    expect(rd.audit.warnings[0]).toContain('Security check failed');
  });

  it('rejects segments with path separators', async () => {
    const runDir = join(root, 'proj', '.aid-o', 'work', 'evidence', 'E-X', 'R-X');
    await mkdir(runDir, { recursive: true });

    const rd = await buildRunDetail('proj', 'E-001/../../etc', 'R-X', runDir, deps());
    expect(rd.format).toBe('stub');
    expect(rd.audit.warnings[0]).toContain('Security check failed');
  });

  it('accepts valid segments and builds normally', async () => {
    const runDir = await makeRun('proj', 'E-046-1_3', 'R-E046-1', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      timeline: timelineNoDispatch(),
    });

    const rd = await buildRunDetail('proj', 'E-046-1_3', 'R-E046-1', runDir, deps());
    expect(rd.format).toBe('v3');
    expect(rd.state).toBe('DONE');
    expect(rd.projectId).toBe('proj');
  });
});

// ===========================================================================
// Security — CWE-22 symlink DoS defense (walkRunFiles)
// ===========================================================================

describe('Security — CWE-22 symlink DoS / enumeration defense', () => {
  it('does NOT follow symlinks to directories — treats them as leaf files', async () => {
    const runDir = await makeRun('proj', 'E-test', 'R-test', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      timeline: timelineNoDispatch(),
    });

    // Create an external directory with files to symlink to
    const externalDir = join(root, 'external-secret');
    await mkdir(externalDir, { recursive: true });
    await writeFile(join(externalDir, 'secret.txt'), 'secret data', 'utf-8');

    // Create a symlink from runDir/link-to-external -> externalDir
    const symlinkPath = join(runDir, 'link-to-external');
    await symlink(externalDir, symlinkPath, 'dir');

    // Build runDetail — should NOT recurse into the symlink
    const rd = await buildRunDetail('proj', 'E-test', 'R-test', runDir, deps());

    // The symlink should be listed as a file, not recursed
    expect(rd.files).toContain('link-to-external');
    // Files from the external dir should NOT be listed
    expect(rd.files).not.toContain('link-to-external/secret.txt');
    // Real nested files (gates/) should still be listed normally
    expect(rd.format).toBe('v3');
  });

  it('lists a symlink-to-file as a file', async () => {
    const runDir = await makeRun('proj', 'E-test2', 'R-test2', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      timeline: timelineNoDispatch(),
    });

    // Create a file and symlink to it
    const targetFile = join(root, 'target-data.txt');
    await writeFile(targetFile, 'target data', 'utf-8');
    const symlinkPath2 = join(runDir, 'link-to-data');
    await symlink(targetFile, symlinkPath2, 'file');

    const rd = await buildRunDetail('proj', 'E-test2', 'R-test2', runDir, deps());

    // The symlink-to-file should be listed (as a leaf)
    expect(rd.files).toContain('link-to-data');
    expect(rd.format).toBe('v3');
  });

  it('still lists real nested directories normally (not regressed)', async () => {
    const runDir = await makeRun('proj', 'E-test3', 'R-test3', {
      fsm: fsmStateDone({ donePhase: 'review' }),
      gates: gatesReport(),
      timeline: timelineNoDispatch(),
    });

    const rd = await buildRunDetail('proj', 'E-test3', 'R-test3', runDir, deps());

    // Real nested gates/gates_report.json should be present
    expect(rd.files).toContain('gates/gates_report.json');
    // And it should be a proper v3 run, not degraded
    expect(rd.format).toBe('v3');
    expect(rd.gates.length).toBeGreaterThan(0);
  });

  // ===========================================================================
  // Security — CWE-22 defense layer 2 (isUnderRoot in buildRunDetail)
  // ===========================================================================

  describe('Security — CWE-22 defense layer 2 (isUnderRoot with projectsRoot)', () => {
    it('rejects runDir outside projectsRoot and returns a safe stub', async () => {
      // Create a run in an external directory outside root
      const externalDir = join(tmpdir(), 'aid-external-secret');
      const externalRunDir = join(externalDir, 'evidence', 'E-X', 'R-X');
      await mkdir(externalRunDir, { recursive: true });
      await writeFile(join(externalRunDir, 'fsm-state.yaml'), 'state: READY', 'utf-8');

      try {
        // Call buildRunDetail with projectsRoot set, but runDir outside it
        const depsWithRoot = (): RunDetailDeps => ({
          fs: new FsReader(),
          pathMap: createPathMap({ projectsRoot: root, hostRoot: root }),
          projectsRoot: root, // Layer 2 defense enabled
        });

        const rd = await buildRunDetail('proj', 'E-X', 'R-X', externalRunDir, depsWithRoot());

        // Should return a safe stub
        expect(rd.format).toBe('stub');
        expect(rd.audit.warnings[0]).toContain('Security check failed');
      } finally {
        await rm(externalDir, { recursive: true, force: true });
      }
    });

    it('accepts runDir under projectsRoot when layer 2 is enabled', async () => {
      const runDir = await makeRun('proj', 'E-test-l2', 'R-test-l2', {
        fsm: fsmStateDone({ donePhase: 'review' }),
        timeline: timelineNoDispatch(),
      });

      const depsWithRoot = (): RunDetailDeps => ({
        fs: new FsReader(),
        pathMap: createPathMap({ projectsRoot: root, hostRoot: root }),
        projectsRoot: root,
      });

      const rd = await buildRunDetail('proj', 'E-test-l2', 'R-test-l2', runDir, depsWithRoot());

      // Should build normally (layer 2 passes, inputs are valid)
      expect(rd.format).toBe('v3');
      expect(rd.state).toBe('DONE');
    });

    it('normalizes trailing slashes on projectsRoot before comparison', async () => {
      const runDir = await makeRun('proj', 'E-test-slash', 'R-test-slash', {
        fsm: fsmStateDone({ donePhase: 'review' }),
        timeline: timelineNoDispatch(),
      });

      // Pass projectsRoot with trailing slash (the normalization case per IMP-129)
      const rootWithSlash = root.endsWith('/') ? root : `${root}/`;
      const depsWithTrailingSlash = (): RunDetailDeps => ({
        fs: new FsReader(),
        pathMap: createPathMap({ projectsRoot: root, hostRoot: root }),
        projectsRoot: rootWithSlash,
      });

      const rd = await buildRunDetail(
        'proj',
        'E-test-slash',
        'R-test-slash',
        runDir,
        depsWithTrailingSlash(),
      );

      // Should still work correctly (trailing slash normalized away)
      expect(rd.format).toBe('v3');
      expect(rd.state).toBe('DONE');
    });
  });
});
