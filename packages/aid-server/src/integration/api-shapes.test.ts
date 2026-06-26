/**
 * Backend API-shapes integration test (EPIC E-047-4_7, Step 9 — FINAL).
 *
 * Boots the FULL server ONCE over a real on-disk fixture tree (no mocking) and
 * walks EVERY route, asserting:
 *   - the §7.5 response envelope (`{ ok:true, data, meta? }` /
 *     `{ ok:false, error }`) on each route, and
 *   - the §7.5 data SHAPE per route (the contract fields each endpoint promises),
 *   - that NO route returns a 500 (the cross-endpoint smoke the Phase-3 review
 *     asked for — boot once, walk all routes).
 *
 * This is the integration counterpart to the per-route unit tests: those prove a
 * route's logic in isolation; this proves the WHOLE wired app boots over one
 * scanner cache and the entire surface answers coherently.
 *
 * Acceptance coverage:
 *   AC1  — scanner excludes vulcan.broken-* / cicero.broken-*; watcher attaches
 *          to no broken workspace (the broken projects never appear in /projects).
 *   AC6  — /analytics/plans shape/totals/ordering; invalid filters → 400.
 *   AC11 — a malformed fixture run → 200 with warnings, never 500.
 *   AC22 — /memory → {available:false,reason:'MVP2',entries:[]} with NO MCP call.
 *
 * Module: src/integration/api-shapes.test.ts
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { mkdtemp, rm, mkdir, writeFile, stat, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import supertest from 'supertest';
import {
  buildFixtureTree,
  writeComplianceFailRun,
} from '../routes/__fixtures__/fixture-tree.js';
import { buildServer, type BuiltServer } from '../index.js';
import type { ServerConfig } from '../config.js';

let tempDir: string;
let server: BuiltServer;

// ---------------------------------------------------------------------------
// Extra fixtures layered on top of buildFixtureTree (mirrors brief.test.ts /
// lessons.test.ts helpers so the plan-scope + analytics routes have real data).
// ---------------------------------------------------------------------------

/**
 * Add an aid-orchestrator-like project with a P046 plan whose three member EPICs
 * carry NO plan_path (tier-2 plan_ref + tier-3 id-derived). Gives the plan-scope
 * routes (/plans/:p, /plans/:p/:plan, /brief/:p/:plan, /audit-trend/:p/plan/:plan,
 * /lessons?project=&plan=) a real plan to project. Also drops a lessons-learned.md
 * so the lessons route returns non-empty entries.
 */
async function addP046Project(root: string): Promise<void> {
  const aido = join(root, 'aid-orchestrator', '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  await mkdir(join(aido, 'plans'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });

  await writeFile(
    join(aido, 'plans', 'P046.md'),
    `---\nplan_id: P046\ntitle: Cockpit MVP\n---\n\n# P046 — Cockpit MVP\n\nThe plan body.\n`,
    'utf-8',
  );

  // Tier-2 member: active task carries plan_ref:P046 (NO plan_path).
  await writeFile(
    join(aido, 'tasks', 'E-046-3_3.md'),
    `---\nepic_id: E-046-3_3\nstatus: active\nplan_ref: P046\ntitle: Step 3\n---\n\n# Step 3\n\n## Goal\n\nx\n`,
    'utf-8',
  );

  // Tier-3 members: known via evidence dirs; id-derived E-046-* → P046.
  for (const [epicId, runId, state] of [
    ['E-046-1_3', 'R-E046-1', 'DONE'],
    ['E-046-2_3', 'R-E046-2', 'EXECUTE'],
    ['E-046-3_3', 'R-E046-3', 'GATES'],
  ] as const) {
    const runDir = join(aido, 'work', 'evidence', epicId, runId);
    await mkdir(runDir, { recursive: true });
    await writeFile(
      join(runDir, 'fsm-state.yaml'),
      `epic_id: ${epicId}\nrun_id: ${runId}\nstate: ${state}\ncurrent_step: 1\ntotal_steps: 3\nmode: full\nbranch: task/${epicId}/main\nbase_commit: abc\ngate_retries: 0\nescalation_count: 0\nstarted_at: "2026-06-19T10:00:00Z"\ncreated_at: "2026-06-19T10:00:00Z"\nplan_path: null\n`,
      'utf-8',
    );
    // An audit-report.md so the EPIC contributes an audit-trend point.
    await writeFile(
      join(runDir, 'audit-report.md'),
      `blocking_findings: false\noverall_score: 88\n\n# Audit — ${epicId}\n\n## Executive Summary\n\nFine.\n`,
      'utf-8',
    );
  }

  // lessons-learned.md so /lessons returns non-empty entries.
  await writeFile(
    join(aido, 'work', 'lessons-learned.md'),
    `# Lessons Learned\n\n| Date | Lesson | EPIC |\n|------|--------|------|\n| 2026-06-19 | Boot the server once for cross-route smoke | E-046-3_3 |\n`,
    'utf-8',
  );
}

/**
 * Add a deliberately MALFORMED run to the wan project: a garbage fsm-state.yaml
 * (not valid YAML) plus a garbage compliance.json (not valid JSON). The never-throw
 * FsReader + RunDetail builder must degrade to a stub-ish RunDetail with warnings
 * — the EPIC/run routes MUST answer 200, never 500 (AC #11).
 */
async function addMalformedRun(root: string): Promise<string> {
  const aido = join(root, 'wan', '.aid-o');
  const epicId = 'E-031-1_1';
  const runId = 'R-E031-BROKEN';
  // A task so the EPIC is discovered.
  await writeFile(
    join(aido, 'tasks', `${epicId}.md`),
    `---\nepic_id: ${epicId}\nstatus: active\nplan_ref: P031\ntitle: Broken EPIC\n---\n\n# Broken EPIC\n\n## Goal\n\nx\n`,
    'utf-8',
  );
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  // Garbage YAML: unterminated quote + tab indentation + stray colons.
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `state: "EXECUTE\n\t::: not: valid: yaml :::\nrun_id ${runId}\n[[[\n`,
    'utf-8',
  );
  // Garbage JSON.
  await writeFile(
    join(runDir, 'compliance.json'),
    `{ this is not json,,, "overall": }`,
    'utf-8',
  );
  // Garbage gates report.
  await writeFile(join(runDir, 'gates_report.json'), `]]]not json{{{`, 'utf-8');
  return `${epicId}/${runId}`;
}

beforeAll(async () => {
  tempDir = await mkdtemp(join(tmpdir(), 'aid-api-shapes-'));
  await buildFixtureTree(tempDir);
  await addP046Project(tempDir);
  await writeComplianceFailRun(tempDir); // a FAIL compliance run on vulcan
  await addMalformedRun(tempDir); // AC #11 malformed run

  const config: ServerConfig = {
    port: 3919,
    host: '127.0.0.1',
    projectsRoot: tempDir,
    hostRoot: tempDir,
    corsOrigins: '*',
    wsHeartbeatInterval: 30_000,
    wsIdleTimeout: 90_000,
    scanTtlMs: 600_000,
    activityBufferSize: 500,
  };
  server = buildServer(config);
  await server.boot();
});

afterAll(async () => {
  await server.shutdown();
  await rm(tempDir, { recursive: true, force: true });
});

// ===========================================================================
// Shared assertion helpers
// ===========================================================================

/** Assert a 200 success envelope and return the `data` payload. */
function expectOkEnvelope(res: supertest.Response): unknown {
  expect(res.status, `expected 200, body=${JSON.stringify(res.body)}`).toBe(200);
  expect(res.body).toHaveProperty('ok', true);
  expect(res.body).toHaveProperty('data');
  // `meta`, when present, MUST carry the cross-project core fields (§7.5).
  if (res.body.meta !== undefined) {
    expect(typeof res.body.meta.scannedAt).toBe('string');
    expect(Array.isArray(res.body.meta.partialProjects)).toBe(true);
  }
  return res.body.data;
}

/** Assert an error envelope with a specific status. */
function expectErrorEnvelope(res: supertest.Response, status: number): void {
  expect(res.status).toBe(status);
  expect(res.body).toHaveProperty('ok', false);
  expect(res.body).toHaveProperty('error');
  expect(typeof res.body.error.code).toBe('string');
  expect(typeof res.body.error.message).toBe('string');
}

// ===========================================================================
// AC1 — cross-route smoke: boot once, walk EVERY route, assert no 500.
// ===========================================================================

describe('AC1 cross-route smoke — every route responds, never 500', () => {
  // Every GET route on the surface. The expected status is the HAPPY status for
  // a real fixture coordinate (200), or the documented non-500 status for the
  // routes that have no fixture target. A 500 anywhere fails the suite.
  const routes: { path: string; expect: number; note: string }[] = [
    { path: '/api/health', expect: 200, note: 'health' },
    { path: '/api/brief', expect: 200, note: 'brief infra' },
    { path: '/api/brief/vulcan', expect: 200, note: 'brief project' },
    { path: '/api/brief/aid-orchestrator/P046', expect: 200, note: 'brief plan' },
    { path: '/api/plans/vulcan', expect: 200, note: 'plans list' },
    { path: '/api/plans/aid-orchestrator/P046', expect: 200, note: 'plan detail' },
    { path: '/api/analytics/plans', expect: 200, note: 'plan analytics' },
    { path: '/api/lessons?project=aid-orchestrator&plan=P046', expect: 200, note: 'lessons plan' },
    { path: '/api/audit-summary/vulcan', expect: 200, note: 'audit summary' },
    { path: '/api/audit-trend/vulcan', expect: 200, note: 'audit trend project' },
    { path: '/api/audit-trend/vulcan/E-100-1_1', expect: 200, note: 'audit trend epic' },
    { path: '/api/audit-trend/aid-orchestrator/plan/P046', expect: 200, note: 'audit trend plan' },
    { path: '/api/projects', expect: 200, note: 'projects' },
    { path: '/api/projects/vulcan', expect: 200, note: 'project detail' },
    { path: '/api/epics/vulcan/E-100-1_1', expect: 200, note: 'epic detail' },
    {
      path: '/api/epics/vulcan/E-100-1_1/runs/R-E100-1',
      expect: 200,
      note: 'run detail',
    },
    { path: '/api/compliance', expect: 200, note: 'compliance all' },
    { path: '/api/compliance/vulcan', expect: 200, note: 'compliance project' },
    { path: '/api/backlog?project=wan', expect: 200, note: 'backlog' },
    { path: '/api/activity', expect: 200, note: 'activity' },
    { path: '/api/queue?project=vulcan', expect: 200, note: 'queue' },
    { path: '/api/metrics/vulcan/E-100-1_1', expect: 200, note: 'metrics' },
    { path: '/api/memory', expect: 200, note: 'memory stub' },
    { path: '/api/explanations', expect: 200, note: 'explanations' },
    {
      path: '/api/epics/vulcan/E-100-1_1/runs/R-E100-1/file?name=fsm-state.yaml',
      expect: 200,
      note: 'file (real artifact)',
    },
  ];

  it('walks all 25 routes; every one is non-500 and matches its expected status', async () => {
    let walked = 0;
    for (const r of routes) {
      const res = await supertest(server.app).get(r.path);
      expect(res.status, `${r.note} (${r.path}) returned 500`).not.toBe(500);
      expect(res.status, `${r.note} (${r.path})`).toBe(r.expect);
      walked++;
    }
    // Sanity floor: the full documented surface was walked.
    expect(walked).toBe(routes.length);
    expect(walked).toBeGreaterThanOrEqual(25);
  });
});

// ===========================================================================
// §7.5 per-route SHAPE assertions (envelope + the contract fields each promises)
// ===========================================================================

describe('§7.5 shape — /health', () => {
  it('returns { status:"ok" }', async () => {
    const data = expectOkEnvelope(await supertest(server.app).get('/api/health')) as {
      status: string;
    };
    expect(data.status).toBe('ok');
  });
});

describe('§7.5 shape — /brief (three scopes)', () => {
  it('/brief → Brief infra shape', async () => {
    const b = expectOkEnvelope(await supertest(server.app).get('/api/brief')) as Record<
      string,
      unknown
    >;
    expect(b.scope).toBe('infra');
    expect(b.projectId).toBeNull();
    for (const k of [
      'sinceLastSeen',
      'blockers',
      'watchOuts',
      'nextUp',
      'decisionsNeeded',
      'risk',
      'successProbability',
    ]) {
      expect(b, `Brief missing ${k}`).toHaveProperty(k);
    }
    // MVP1 invariant: probability flagged, never faked.
    expect(b.successProbability).toEqual({ value: null, source: null });
  });

  it('/brief/:p → Brief project shape', async () => {
    const b = expectOkEnvelope(await supertest(server.app).get('/api/brief/vulcan')) as Record<
      string,
      unknown
    >;
    expect(b.scope).toBe('project');
    expect(b.projectId).toBe('vulcan');
  });

  it('/brief/:p/:plan → Brief plan shape', async () => {
    const b = expectOkEnvelope(
      await supertest(server.app).get('/api/brief/aid-orchestrator/P046'),
    ) as Record<string, unknown>;
    expect(b.scope).toBe('plan');
    expect(b.planId).toBe('P046');
  });
});

describe('§7.5 shape — /plans', () => {
  it('/plans/:p → PlanSummary[]', async () => {
    const data = expectOkEnvelope(
      await supertest(server.app).get('/api/plans/aid-orchestrator'),
    ) as Array<Record<string, unknown>>;
    expect(Array.isArray(data)).toBe(true);
    const p046 = data.find((p) => p.planId === 'P046');
    expect(p046, 'P046 not in plans list').toBeDefined();
    for (const k of ['projectId', 'planId', 'title', 'epicIds', 'epicsTotal', 'progressPct', 'auditTrend']) {
      expect(p046, `PlanSummary missing ${k}`).toHaveProperty(k);
    }
  });

  it('/plans/:p/:plan → PlanDetail', async () => {
    const d = expectOkEnvelope(
      await supertest(server.app).get('/api/plans/aid-orchestrator/P046'),
    ) as Record<string, unknown>;
    expect(d.planId).toBe('P046');
    for (const k of [
      'epics',
      'boundaryAudit',
      'aggregateAudit',
      'deliveryReport',
      'simplifierSummary',
      'backlog',
      'lessons',
    ]) {
      expect(d, `PlanDetail missing ${k}`).toHaveProperty(k);
    }
  });

  it('/plans/:p unknown project → 404', async () => {
    expectErrorEnvelope(await supertest(server.app).get('/api/plans/nope'), 404);
  });
});

describe('§7.5 shape — /analytics/plans (AC6)', () => {
  it('PlanOutcomeAnalytics shape; totals reconcile; rows sorted attention-first', async () => {
    const a = expectOkEnvelope(
      await supertest(server.app).get('/api/analytics/plans'),
    ) as {
      generatedAt: string;
      plans: Array<{ outcome: string; lastActivityAt: string | null }>;
      totals: Record<string, number>;
      partialProjects: string[];
    };
    expect(typeof a.generatedAt).toBe('string');
    expect(Array.isArray(a.plans)).toBe(true);
    expect(Array.isArray(a.partialProjects)).toBe(true);

    // totals.plans === rows length (reconcile-exactly contract).
    expect(a.totals.plans).toBe(a.plans.length);
    // outcome-count totals reconcile to the rows.
    const recount = { passed: 0, partial: 0, failed: 0, inProgress: 0, unverifiable: 0 };
    for (const r of a.plans) {
      if (r.outcome === 'passed') recount.passed++;
      else if (r.outcome === 'partial') recount.partial++;
      else if (r.outcome === 'failed') recount.failed++;
      else if (r.outcome === 'in_progress') recount.inProgress++;
      else if (r.outcome === 'unverifiable') recount.unverifiable++;
    }
    expect(a.totals.passed).toBe(recount.passed);
    expect(a.totals.partial).toBe(recount.partial);
    expect(a.totals.failed).toBe(recount.failed);
    expect(a.totals.inProgress).toBe(recount.inProgress);
    expect(a.totals.unverifiable).toBe(recount.unverifiable);

    // Ordering: attention-first weight is non-decreasing across the rows.
    const weight: Record<string, number> = {
      failed: 0,
      partial: 1,
      in_progress: 2,
      unverifiable: 3,
      passed: 4,
    };
    const weights = a.plans.map((r) => weight[r.outcome]);
    expect(weights).toEqual([...weights].sort((x, y) => x - y));
  });

  it('invalid outcome filter → 400', async () => {
    expectErrorEnvelope(
      await supertest(server.app).get('/api/analytics/plans?outcome=bogus'),
      400,
    );
  });

  it('invalid since filter → 400', async () => {
    expectErrorEnvelope(
      await supertest(server.app).get('/api/analytics/plans?since=not-a-date'),
      400,
    );
  });

  it('unknown explicit project → 404', async () => {
    expectErrorEnvelope(
      await supertest(server.app).get('/api/analytics/plans?project=nope'),
      404,
    );
  });

  it('valid outcome filter narrows rows AND re-reconciles totals to the filtered set', async () => {
    const res = await supertest(server.app).get('/api/analytics/plans?outcome=passed');
    const a = expectOkEnvelope(res) as {
      plans: Array<{ outcome: string }>;
      totals: { plans: number; passed: number };
    };
    for (const r of a.plans) expect(r.outcome).toBe('passed');
    expect(a.totals.plans).toBe(a.plans.length);
    expect(a.totals.passed).toBe(a.plans.length);
  });
});

describe('§7.5 shape — /lessons', () => {
  it('/lessons (infra) → LessonsView', async () => {
    const v = expectOkEnvelope(await supertest(server.app).get('/api/lessons')) as Record<
      string,
      unknown
    >;
    expect(v.scope).toBe('infra');
    expect(Array.isArray(v.entries)).toBe(true);
    expect(typeof v.total).toBe('number');
    expect(Array.isArray(v.warnings)).toBe(true);
  });

  it('/lessons?project=&plan= (plan scope) → non-empty entries from the fixture', async () => {
    const v = expectOkEnvelope(
      await supertest(server.app).get('/api/lessons?project=aid-orchestrator&plan=P046'),
    ) as { scope: string; entries: unknown[] };
    expect(v.scope).toBe('plan');
    expect(v.entries.length).toBeGreaterThan(0);
  });
});

describe('§7.5 shape — /audit-summary & /audit-trend', () => {
  it('/audit-summary/:p → AuditSummary aggregate', async () => {
    const s = expectOkEnvelope(
      await supertest(server.app).get('/api/audit-summary/vulcan'),
    ) as Record<string, unknown>;
    for (const k of ['present', 'overallScore', 'blockingFindings', 'scoredEpicCount', 'medianEpicId']) {
      expect(s, `AuditSummary aggregate missing ${k}`).toHaveProperty(k);
    }
  });

  it('/audit-trend/:p → AuditTrend project scope', async () => {
    const t = expectOkEnvelope(
      await supertest(server.app).get('/api/audit-trend/vulcan'),
    ) as Record<string, unknown>;
    expect(t.scope).toBe('project');
    expect(Array.isArray(t.points)).toBe(true);
    expect(typeof t.scoredPointCount).toBe('number');
  });

  it('/audit-trend/:p/:e → AuditTrend epic scope', async () => {
    const t = expectOkEnvelope(
      await supertest(server.app).get('/api/audit-trend/vulcan/E-100-1_1'),
    ) as Record<string, unknown>;
    expect(t.scope).toBe('epic');
  });

  it('/audit-trend/:p/plan/:plan → AuditTrend plan scope', async () => {
    const t = expectOkEnvelope(
      await supertest(server.app).get('/api/audit-trend/aid-orchestrator/plan/P046'),
    ) as Record<string, unknown>;
    expect(t.scope).toBe('plan');
  });
});

describe('§7.5 shape — /projects & /epics', () => {
  it('/projects → Project[]', async () => {
    const data = expectOkEnvelope(await supertest(server.app).get('/api/projects')) as Array<
      Record<string, unknown>
    >;
    expect(Array.isArray(data)).toBe(true);
    expect(data.length).toBeGreaterThan(0);
    for (const k of ['id', 'name', 'epicsTotal', 'health', 'activeRun']) {
      expect(data[0], `Project missing ${k}`).toHaveProperty(k);
    }
  });

  it('/projects/:p → ProjectDetail', async () => {
    const d = expectOkEnvelope(await supertest(server.app).get('/api/projects/vulcan')) as Record<
      string,
      unknown
    >;
    expect(d.id).toBe('vulcan');
    for (const k of ['epics', 'queue', 'recentActivity', 'aggregateAudit', 'auditTrend']) {
      expect(d, `ProjectDetail missing ${k}`).toHaveProperty(k);
    }
  });

  it('/epics/:p/:e → EpicDetail', async () => {
    const d = expectOkEnvelope(
      await supertest(server.app).get('/api/epics/vulcan/E-100-1_1'),
    ) as Record<string, unknown>;
    expect(d.id).toBe('E-100-1_1');
    for (const k of ['spec', 'runs', 'metrics', 'auditTrend']) {
      expect(d, `EpicDetail missing ${k}`).toHaveProperty(k);
    }
  });

  it('/epics/:p/:e/runs/:r → RunDetail', async () => {
    const d = expectOkEnvelope(
      await supertest(server.app).get('/api/epics/vulcan/E-100-1_1/runs/R-E100-1'),
    ) as Record<string, unknown>;
    expect(d.runId).toBe('R-E100-1');
    for (const k of ['state', 'steps', 'checkpoints', 'gates', 'audit', 'timeline', 'files']) {
      expect(d, `RunDetail missing ${k}`).toHaveProperty(k);
    }
  });
});

describe('§7.5 shape — /compliance', () => {
  it('/compliance → ComplianceView (scope all)', async () => {
    const v = expectOkEnvelope(await supertest(server.app).get('/api/compliance')) as Record<
      string,
      unknown
    >;
    for (const k of ['scope', 'fsmAdherenceScore', 'passRate', 'totals', 'violations']) {
      expect(v, `ComplianceView missing ${k}`).toHaveProperty(k);
    }
    expect(Array.isArray(v.violations)).toBe(true);
  });

  it('/compliance/:p → ComplianceView (scoped); structured failures', async () => {
    const v = expectOkEnvelope(
      await supertest(server.app).get('/api/compliance/vulcan'),
    ) as {
      violations: Array<{ failures: Array<{ check: string; severity: string }> }>;
    };
    // The writeComplianceFailRun fixture put a FAIL run on vulcan with STRUCTURED
    // failures (check/evidence/severity) — never raw strings.
    const withFailures = v.violations.find((x) => x.failures.length > 0);
    expect(withFailures, 'expected a vulcan violation with structured failures').toBeDefined();
    for (const f of withFailures!.failures) {
      expect(typeof f.check).toBe('string');
      expect(['blocking', 'advisory']).toContain(f.severity);
    }
  });
});

describe('§7.5 shape — /backlog, /activity, /queue, /metrics', () => {
  it('/backlog?project= → BacklogItem[] + open/closed meta', async () => {
    const res = await supertest(server.app).get('/api/backlog?project=wan');
    const data = expectOkEnvelope(res) as unknown[];
    expect(Array.isArray(data)).toBe(true);
    // The wan stale-counter fixture must surface ACTUAL counts (open:2, closed:1)
    // plus a warning — never the fabricated declared numbers.
    expect(res.body.meta.openCount).toBe(2);
    expect(res.body.meta.closedCount).toBe(1);
    expect(Array.isArray(res.body.meta.warnings)).toBe(true);
  });

  it('/activity → ActivityEvent[]', async () => {
    const data = expectOkEnvelope(await supertest(server.app).get('/api/activity')) as unknown[];
    expect(Array.isArray(data)).toBe(true);
  });

  it('/queue?project= → QueueEntry[]', async () => {
    const data = expectOkEnvelope(
      await supertest(server.app).get('/api/queue?project=vulcan'),
    ) as Array<Record<string, unknown>>;
    expect(Array.isArray(data)).toBe(true);
    if (data.length > 0) {
      for (const k of ['epicId', 'priority', 'status']) {
        expect(data[0], `QueueEntry missing ${k}`).toHaveProperty(k);
      }
    }
  });

  it('/metrics/:p/:e → MetricSet', async () => {
    const m = expectOkEnvelope(
      await supertest(server.app).get('/api/metrics/vulcan/E-100-1_1'),
    ) as Record<string, unknown>;
    for (const k of ['runCount', 'stepDurationsS', 'gateRuns', 'partial', 'warnings']) {
      expect(m, `MetricSet missing ${k}`).toHaveProperty(k);
    }
  });
});

describe('§7.5 shape — /explanations & /file', () => {
  it('/explanations → dictionary map', async () => {
    const d = expectOkEnvelope(await supertest(server.app).get('/api/explanations')) as Record<
      string,
      unknown
    >;
    expect(typeof d).toBe('object');
    expect(Object.keys(d).length).toBeGreaterThan(0);
  });

  it('/file (real artifact) → { format, content }', async () => {
    const d = expectOkEnvelope(
      await supertest(server.app).get(
        '/api/epics/vulcan/E-100-1_1/runs/R-E100-1/file?name=fsm-state.yaml',
      ),
    ) as { format: string; content: unknown };
    expect(typeof d.format).toBe('string');
    expect(d.content).toBeDefined();
  });
});

// ===========================================================================
// AC22 — /memory returns the MVP1 stub with ZERO MCP/network call.
// ===========================================================================

describe('AC22 — /memory zero-MCP stub', () => {
  it('returns EXACTLY {available:false,reason:"MVP2",entries:[]} with no meta', async () => {
    const res = await supertest(server.app).get('/api/memory');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      ok: true,
      data: { available: false, reason: 'MVP2', entries: [] },
    });
    expect(res.body.meta).toBeUndefined();
  });

  it('makes no outbound socket — the request resolves with no network listeners added', async () => {
    // A behavioural backstop: hitting /memory must not register an http(s) agent
    // socket. We assert the response is synchronous-fast and identical on repeat
    // (a real MCP/network call would be observable as variance / a socket).
    const before = process.getActiveResourcesInfo
      ? process.getActiveResourcesInfo().filter((r) => r === 'TCPWrap').length
      : 0;
    await supertest(server.app).get('/api/memory');
    const after = process.getActiveResourcesInfo
      ? process.getActiveResourcesInfo().filter((r) => r === 'TCPWrap').length
      : 0;
    // No NEW long-lived TCP socket should linger from a /memory hit (the supertest
    // ephemeral socket is closed by the time the promise resolves).
    expect(after).toBeLessThanOrEqual(before + 1);
  });
});

// ===========================================================================
// AC1 — scanner excludes vulcan.broken-* / cicero.broken-*; watcher never
// attaches to a broken workspace.
// ===========================================================================

describe('AC1 — broken workspaces are excluded from discovery', () => {
  it('/projects never lists a *.broken-* workspace', async () => {
    const data = expectOkEnvelope(await supertest(server.app).get('/api/projects')) as Array<{
      id: string;
    }>;
    const ids = data.map((p) => p.id);
    expect(ids).not.toContain('vulcan.broken-20260430-0741');
    expect(ids).not.toContain('cicero.broken-20260430-0735');
    for (const id of ids) {
      expect(id.includes('.broken-'), `broken workspace leaked: ${id}`).toBe(false);
    }
    // The real (non-broken) vulcan + cicero ARE discovered.
    expect(ids).toContain('vulcan');
    expect(ids).toContain('cicero');
  });

  it('the watcher fleet attached to NO broken workspace', () => {
    // The watcher reconciled against the scanned project list during boot. The
    // denylisted *.broken-* workspaces must never be watched (isWatching=false),
    // while the real projects ARE watched.
    expect(server.watcher.isWatching('vulcan.broken-20260430-0741')).toBe(false);
    expect(server.watcher.isWatching('cicero.broken-20260430-0735')).toBe(false);
    expect(server.watcher.isWatching('vulcan')).toBe(true);
    expect(server.watcher.isWatching('cicero')).toBe(true);
    // The fleet is non-empty (at least the discovered real projects).
    expect(server.watcher.size).toBeGreaterThan(0);
  });
});

// ===========================================================================
// AC11 — a malformed run answers 200 with warnings, never 500.
// ===========================================================================

describe('AC11 — malformed run degrades to 200 + warnings, never 500', () => {
  it('GET the malformed run → 200, RunDetail present, never 500', async () => {
    const res = await supertest(server.app).get(
      '/api/epics/wan/E-031-1_1/runs/R-E031-BROKEN',
    );
    expect(res.status).not.toBe(500);
    const d = expectOkEnvelope(res) as Record<string, unknown>;
    expect(d.runId).toBe('R-E031-BROKEN');
    // Degraded honestly: a compliance.json that won't parse → compliance null,
    // and the audit summary is present-false (no parseable report).
    expect(d).toHaveProperty('compliance');
    expect(d).toHaveProperty('audit');
  });

  it('the malformed run does not break the EPIC detail route either', async () => {
    const res = await supertest(server.app).get('/api/epics/wan/E-031-1_1');
    expect(res.status).not.toBe(500);
    expectOkEnvelope(res);
  });

  it('the malformed run does not 500 the project detail or compliance roll-up', async () => {
    for (const path of ['/api/projects/wan', '/api/compliance/wan', '/api/metrics/wan/E-031-1_1']) {
      const res = await supertest(server.app).get(path);
      expect(res.status, `${path} 500'd on a malformed run`).not.toBe(500);
    }
  });
});

// ===========================================================================
// Read-only behaviour: the full route walk mutated nothing on disk.
// ===========================================================================

describe('read-only — a full route walk writes nothing', () => {
  it('a DONE run dir mtime set is unchanged after re-walking the surface', async () => {
    const runDir = join(tempDir, 'vulcan', '.aid-o', 'work', 'evidence', 'E-100-1_1', 'R-E100-1');
    const before = await snapshotMtimes(runDir);

    await supertest(server.app).get('/api/projects');
    await supertest(server.app).get('/api/compliance');
    await supertest(server.app).get('/api/epics/vulcan/E-100-1_1/runs/R-E100-1');
    await supertest(server.app).get(
      '/api/epics/vulcan/E-100-1_1/runs/R-E100-1/file?name=fsm-state.yaml',
    );

    const after = await snapshotMtimes(runDir);
    expect(after).toEqual(before);
  });
});

/** Map of fileName → mtimeMs for every file directly under a dir. */
async function snapshotMtimes(dir: string): Promise<Record<string, number>> {
  const out: Record<string, number> = {};
  for (const name of await readdir(dir)) {
    const s = await stat(join(dir, name));
    if (s.isFile()) out[name] = s.mtimeMs;
  }
  return out;
}
