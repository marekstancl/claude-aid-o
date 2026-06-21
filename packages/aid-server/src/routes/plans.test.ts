/**
 * Plan + Plan-Analytics route integration tests (EPIC E-047-4_7, Step 7 —
 * §13.6 / SF4 / MF6 / §13.12, AC #16/#19/#24/#25).
 *
 * Boots the full server over a REAL on-disk fixture tree (no mocking) and drives
 * the endpoints via supertest. The fixture deliberately reproduces the real-tree
 * DUPLICATE-EPIC trap: E-046-3_3's task file has NO `epic_id` frontmatter (so it
 * indexes under its long filename stem) while its run lives under the canonical
 * `E-046-3_3` evidence dir — the membership resolver MUST reconcile these into
 * ONE tier-2 member, not two. Also: an E-041-like orphan (plan_ref → P041 with
 * NO P041 plan file) must be excluded.
 *
 * AC matrix (route surface):
 *   #16/#19 — P046 → 3 members (E-046-3_3 plan_ref + E-046-1/2_3 derived);
 *             membershipMixed:true; boundary 84 ≠ aggregate 89; acPct null.
 *   #24     — present:false delivery/simplifier; a missing _test_evidence file →
 *             exists:false (never dropped).
 *   #25     — /analytics/plans: one row per tier-1-3 plan; invalid filter → 400;
 *             unknown project → 404; totals reconcile; unknowns not zeroed.
 *   read-only — GET writes nothing (run-dir mtimes unchanged).
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtemp, rm, mkdir, writeFile, stat, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import supertest from 'supertest';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';
import type { PlanDetail, PlanSummary, PlanOutcomeAnalytics } from '@aid/contract';

let tempDir: string;
let server: BuiltServer;

/** Write a v3 run dir with fsm-state + optional artifacts. */
async function writeRun(
  aido: string,
  epicId: string,
  runId: string,
  opts: {
    state?: string;
    startedAt?: string;
    audit?: string | null;
    compliance?: object | null;
    gates?: object | null;
    planDiff?: object | null;
    extraFiles?: Record<string, string>;
  } = {},
): Promise<void> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  const state = opts.state ?? 'DONE';
  const startedAt = opts.startedAt ?? '2026-06-18T14:00:00Z';
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `epic_id: ${epicId}\nrun_id: ${runId}\nstate: ${state}\ncurrent_step: 2\ntotal_steps: 2\nmode: full\nbranch: task/${epicId}/main\nbase_commit: abc\ngate_retries: 0\nescalation_count: 0\nstreamlined_mode: false\nstarted_at: "${startedAt}"\ncreated_at: "${startedAt}"\nplan_path: null\n`,
    'utf-8',
  );
  if (opts.audit) await writeFile(join(runDir, 'audit-report.md'), opts.audit, 'utf-8');
  if (opts.compliance) await writeFile(join(runDir, 'compliance.json'), JSON.stringify(opts.compliance), 'utf-8');
  if (opts.gates) {
    await mkdir(join(runDir, 'gates'), { recursive: true });
    await writeFile(join(runDir, 'gates', 'gates_report.json'), JSON.stringify(opts.gates), 'utf-8');
  }
  if (opts.planDiff) await writeFile(join(runDir, 'plan-diff.json'), JSON.stringify(opts.planDiff), 'utf-8');
  for (const [rel, body] of Object.entries(opts.extraFiles ?? {})) {
    const abs = join(runDir, rel);
    await mkdir(join(abs, '..'), { recursive: true });
    await writeFile(abs, body, 'utf-8');
  }
}

/**
 * aid-orchestrator-like project reproducing the P046 four-tier fixture + the
 * duplicate-EPIC trap + the E-041 orphan.
 */
async function addOrchestratorProject(root: string): Promise<void> {
  const aido = join(root, 'aid-orchestrator', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks', 'archive'), { recursive: true });
  await mkdir(join(aido, 'plans'), { recursive: true });
  await mkdir(join(aido, 'reports'), { recursive: true });
  await mkdir(join(aido, 'work'), { recursive: true });

  // Plan file P046 exists; P041 does NOT (drives the orphan case).
  await writeFile(
    join(aido, 'plans', 'P046-plan-boundary.md'),
    `---\ntitle: Plan boundary enforcement\n---\n\n# P046 — Plan boundary\n\nEnforce CP layer and plan boundary.\n`,
    'utf-8',
  );

  // THE TRAP: E-046-3_3's task file has NO epic_id → indexes under the long stem.
  await writeFile(
    join(aido, 'tasks', 'E-046-3_3-cp-enforcement-layer-repair.md'),
    `---\nstatus: active\nplan_ref: /abs/.aid-o/plans/P046-plan-boundary.md\nplan_epics_total: 3\n---\n\n# Step 3\n\n## Goal\n\nx\n`,
    'utf-8',
  );
  // E-041 active task carries plan_ref → P041, but NO P041 plan file exists.
  await writeFile(
    join(aido, 'tasks', 'E-041-1_3-skill-audit.md'),
    `---\nstatus: active\nplan_ref: .aid-o/plans/P041-skill-instruction-audit.md\n---\n\n# E-041\n\n## Goal\n\ny\n`,
    'utf-8',
  );
  // Archived E-046 task files carry plan_ref but live under archive/ (EXCLUDED).
  await writeFile(
    join(aido, 'tasks', 'archive', 'E-046-1_3-cp.md'),
    `---\nstatus: completed\nplan_ref: .aid-o/plans/P046-plan-boundary.md\n---\n\n# E-046-1_3\n`,
    'utf-8',
  );
  await writeFile(
    join(aido, 'tasks', 'archive', 'E-046-2_3-cp.md'),
    `---\nstatus: completed\nplan_ref: .aid-o/plans/P046-plan-boundary.md\n---\n\n# E-046-2_3\n`,
    'utf-8',
  );

  // The flagship trio — table 89, heading 95, frontmatter 84 (by started_at).
  // Fast-mode plan-diff (ac_count 0) → acPct null on every member.
  const skipDiff = { ac_count: 0, summary: { present_count: 0 }, overall_verdict: 'skipped' };
  await writeRun(aido, 'E-046-1_3', 'R-E046-1', {
    startedAt: '2026-06-18T14:04:10Z',
    audit: `# Audit\n\n## Score\n\n| Metric | Value |\n|---|---|\n| **Total** | **89/100** |\n\nblocking_findings: false\n`,
    planDiff: skipDiff,
    compliance: { overall: 'pass', checks: {}, failures: [] },
    gates: { gates: { tests: { gate: 'tests', result: 'pass', exit_code: 0, attempts: 1 } } },
  });
  await writeRun(aido, 'E-046-2_3', 'R-E046-2', {
    startedAt: '2026-06-18T14:04:24Z',
    audit: `# Audit\n\n## Score: 95/100\n\nblocking_findings: false\n`,
    planDiff: skipDiff,
    compliance: { overall: 'pass', checks: {}, failures: [] },
    gates: { gates: { tests: { gate: 'tests', result: 'pass', exit_code: 0, attempts: 1 } } },
    extraFiles: {
      'simplifier-report.md':
        '_generated_by: aid-orchestrator:simplifier@x\nsimplifier_report:\n  proposals:\n    - id: "SMP-001"\n      title: "Dedup regex"\n      area: "scripts/x.sh"\n      effort: L\n      recommended_disposition: defer\n',
    },
  });
  // E-046-3_3: run under the CANONICAL evidence dir (no task file here).
  await writeRun(aido, 'E-046-3_3', 'R-E046-3', {
    startedAt: '2026-06-18T14:04:37Z',
    audit: `---\noverall_score: 84\nblocking_findings: false\n---\n\n# Audit\n`,
    planDiff: skipDiff,
    compliance: { overall: 'pass', checks: {}, failures: [] },
    gates: { gates: { tests: { gate: 'tests', result: 'pass', exit_code: 0, attempts: 1 } } },
    extraFiles: { 'reporter/test-suite.txt': 'PASS\n' },
  });
  // E-041 orphan run (no plan file).
  await writeRun(aido, 'E-041-1_3', 'R-E041-1', { startedAt: '2026-06-17T10:00:00Z', planDiff: skipDiff });

  // Plan-boundary delivery report: one existing + one MISSING _test_evidence.
  await writeFile(
    join(aido, 'reports', 'P046-delivery.md'),
    [
      '---',
      '_generated_by: aid-orchestrator:reporter@E-046-3_3',
      '_generated_at: "2026-06-19T08:00:00Z"',
      'plan_id: P046',
      'test_outcome: no-runtime',
      '_test_evidence:',
      '  - "reporter/test-suite.txt"',
      '  - "reporter/ghost-evidence.html"',
      '---',
      '',
      '# Zpráva o dodání — P046',
      '',
      '## 1. Co bylo dodáno',
      '',
      'Plan-close a CI floor.',
    ].join('\n'),
    'utf-8',
  );

  // lessons-learned.md scoped to plan members.
  await writeFile(
    join(aido, 'work', 'lessons-learned.md'),
    `# Lessons Learned\n\n| Date | Lesson | Context |\n|------|--------|---------|\n| 2026-06-18 | Reconcile duplicate EPIC index entries | E-046-1_3 |\n| 2026-06-10 | Unrelated lesson | E-099-1_1 |\n`,
    'utf-8',
  );
  await writeFile(join(aido, 'work', 'backlog.md'), `# Backlog\n\n_Active proposals: 2_\n`, 'utf-8');
}

/** A second project with a plan whose only run is a STUB → unverifiable. */
async function addStubProject(root: string): Promise<void> {
  const aido = join(root, 'stubproj', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'plans'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });
  await writeFile(join(aido, 'plans', 'P010-stub.md'), `---\ntitle: Stub\n---\n# P010\n`, 'utf-8');
  await writeFile(join(aido, 'tasks', 'E-010-1_1.md'), `---\nepic_id: E-010-1_1\nplan_ref: P010\n---\n# E-010\n`, 'utf-8');
  // A stub run: no fsm-state, just a timeline → format 'stub'.
  const runDir = join(aido, 'work', 'evidence', 'E-010-1_1', 'R-E010-1');
  await mkdir(runDir, { recursive: true });
  await writeFile(join(runDir, 'timeline.jsonl'), `{"ts":"2026-06-15T00:00:00Z","event":"fsm_init"}\n`, 'utf-8');
}

beforeAll(async () => {
  tempDir = await mkdtemp(join(tmpdir(), 'aid-plans-test-'));
  await addOrchestratorProject(tempDir);
  await addStubProject(tempDir);

  const config: ServerConfig = {
    port: 0, host: '127.0.0.1',
    projectsRoot: tempDir, hostRoot: tempDir,
    corsOrigins: '*',
    scanTtlMs: 600000, activityBufferSize: 500,
    wsHeartbeatInterval: 30000, wsIdleTimeout: 120000,
  } as ServerConfig;
  server = buildServer(config);
  await server.boot();
});

afterAll(async () => {
  await server.shutdown();
  await rm(tempDir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// GET /api/plans/:projectId/:planId — PlanDetail (AC #16/#19/#24)
// ---------------------------------------------------------------------------

describe('GET /api/plans/:projectId/:planId — P046 four-tier membership (AC #16/#19)', () => {
  it('P046 → exactly 3 members; E-046-3_3 plan_ref, E-046-1/2_3 derived; mixed', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    expect(res.status).toBe(200);
    const d = res.body.data as PlanDetail;
    expect(d.epicMembers).toHaveLength(3); // the duplicate-EPIC trap is reconciled
    const byId = Object.fromEntries(d.epicMembers.map((m) => [m.epicId, m.membershipSource]));
    expect(byId['E-046-3_3']).toBe('plan_ref');
    expect(byId['E-046-1_3']).toBe('derived');
    expect(byId['E-046-2_3']).toBe('derived');
    expect(d.membershipMixed).toBe(true);
    expect(d.epics.length).toBe(3);
  });

  it('E-041 (plan_ref → P041, no P041 file) is NOT a member of P046', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    const d = res.body.data as PlanDetail;
    expect(d.epicIds).not.toContain('E-041-1_3');
  });

  it('boundary 84 ≠ aggregate 89 (SF4)', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    const d = res.body.data as PlanDetail;
    expect(d.boundaryAudit.overallScore).toBe(84);
    expect(d.aggregateAudit.overallScore).toBe(89);
  });

  it('acPct is null (fast mode) — never 0% (AC #19)', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    const d = res.body.data as PlanDetail;
    expect(d.acPct).toBeNull();
  });

  it('lessons filtered to plan members', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    const d = res.body.data as PlanDetail;
    expect(d.lessons.total).toBe(1);
    expect(d.lessons.entries[0].epicId).toBe('E-046-1_3');
  });

  it('an unknown plan → 404', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P999');
    expect(res.status).toBe(404);
  });

  it('an unknown project → 404', async () => {
    const res = await supertest(server.app).get('/api/plans/nope/P046');
    expect(res.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Reporter delivery + Simplifier (MF6, AC #24)
// ---------------------------------------------------------------------------

describe('Reporter delivery + Simplifier (MF6, AC #24)', () => {
  it('delivery present; a missing _test_evidence file → exists:false, never dropped', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    const d = res.body.data as PlanDetail;
    expect(d.deliveryReport.present).toBe(true);
    expect(d.deliveryReport.testEvidence).toHaveLength(2);
    const ghost = d.deliveryReport.testEvidence.find((e) => e.name === 'ghost-evidence.html');
    expect(ghost!.exists).toBe(false);
    const real = d.deliveryReport.testEvidence.find((e) => e.name === 'test-suite.txt');
    expect(real!.exists).toBe(true);
    expect(d.deliveryReport.warnings.some((w) => w.includes('chybí'))).toBe(true);
    // no-runtime is not a pass/fail/partial outcome → null (never fabricated)
    expect(d.deliveryReport.outcome).toBeNull();
  });

  it('simplifier proposals are projected', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    const d = res.body.data as PlanDetail;
    expect(d.simplifierSummary.present).toBe(true);
    expect(d.simplifierSummary.proposalCount).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// GET /api/plans/:projectId — list (PlanSummary[])
// ---------------------------------------------------------------------------

describe('GET /api/plans/:projectId — list', () => {
  it('lists P046 as a PlanSummary with 3 members', async () => {
    const res = await supertest(server.app).get('/api/plans/aid-orchestrator');
    expect(res.status).toBe(200);
    const summaries = res.body.data as PlanSummary[];
    const p046 = summaries.find((s) => s.planId === 'P046');
    expect(p046).toBeDefined();
    expect(p046!.epicIds).toHaveLength(3);
    // P041 is not a real plan (no file) → not listed.
    expect(summaries.some((s) => s.planId === 'P041')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// GET /api/analytics/plans — Plan Outcome Analytics (AC #25)
// ---------------------------------------------------------------------------

describe('GET /api/analytics/plans — outcome analytics (§13.12, AC #25)', () => {
  it('returns one row per tier-1-3 plan across all projects; totals reconcile', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans');
    expect(res.status).toBe(200);
    const a = res.body.data as PlanOutcomeAnalytics;
    expect(a.plans.length).toBe(a.totals.plans);
    const sum =
      a.totals.passed + a.totals.partial + a.totals.failed + a.totals.inProgress + a.totals.unverifiable;
    expect(sum).toBe(a.totals.plans);
    // P046 + P010 are the two discoverable plans.
    expect(a.plans.some((p) => p.planId === 'P046')).toBe(true);
    expect(a.plans.some((p) => p.planId === 'P010')).toBe(true);
  });

  it('P046 is unverifiable (fast-mode AC + unknown CP repeats) — unknowns NOT zeroed', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?project=aid-orchestrator');
    const a = res.body.data as PlanOutcomeAnalytics;
    const p046 = a.plans.find((p) => p.planId === 'P046')!;
    expect(p046.outcome).toBe('unverifiable'); // missing proof never passes
    expect(p046.dataPartial).toBe(true);
    expect(p046.checkpointRetries.unknownCheckpoints).toBeGreaterThan(0); // never folded to 0
  });

  it('a stub-only plan is unverifiable, never passed', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?project=stubproj');
    const a = res.body.data as PlanOutcomeAnalytics;
    const p010 = a.plans.find((p) => p.planId === 'P010')!;
    expect(p010.outcome).toBe('unverifiable');
  });

  it('the project filter scopes rows + reconciles totals to the subset', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?project=aid-orchestrator');
    const a = res.body.data as PlanOutcomeAnalytics;
    expect(a.plans.every((p) => p.projectId === 'aid-orchestrator')).toBe(true);
    expect(a.totals.plans).toBe(a.plans.length);
  });

  it('the outcome filter is exact', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?outcome=unverifiable');
    const a = res.body.data as PlanOutcomeAnalytics;
    expect(a.plans.every((p) => p.outcome === 'unverifiable')).toBe(true);
  });

  it('invalid outcome → 400', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?outcome=bogus');
    expect(res.status).toBe(400);
  });

  it('invalid since → 400', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?since=not-a-date');
    expect(res.status).toBe(400);
  });

  it('unknown explicit project → 404', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?project=ghostproject');
    expect(res.status).toBe(404);
  });

  it('partialProjects is sorted unique', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans');
    const a = res.body.data as PlanOutcomeAnalytics;
    const sorted = [...a.partialProjects].sort((x, y) => x.localeCompare(y));
    expect(a.partialProjects).toEqual(sorted);
    expect(new Set(a.partialProjects).size).toBe(a.partialProjects.length);
  });
});

// ---------------------------------------------------------------------------
// Read-only invariant
// ---------------------------------------------------------------------------

describe('read-only — GET writes nothing', () => {
  it('run-dir mtimes are unchanged after driving the endpoints', async () => {
    const runDir = join(tempDir, 'aid-orchestrator', '.aid-o', 'work', 'evidence', 'E-046-3_3', 'R-E046-3');
    const before = (await stat(runDir)).mtimeMs;
    const filesBefore = (await readdir(runDir)).sort();
    await supertest(server.app).get('/api/plans/aid-orchestrator/P046');
    await supertest(server.app).get('/api/analytics/plans');
    const after = (await stat(runDir)).mtimeMs;
    const filesAfter = (await readdir(runDir)).sort();
    expect(after).toBe(before);
    expect(filesAfter).toEqual(filesBefore);
  });
});
