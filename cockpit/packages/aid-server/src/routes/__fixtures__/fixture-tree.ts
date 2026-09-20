/**
 * Real `.aid-o` fixture tree builder for the cross-project route tests
 * (EPIC E-047-3_7, Step 5).
 *
 * Builds a genuine on-disk projects root the REAL scanner walks (no mocking),
 * so discovery + denylist classification + RunDetail assembly are all exercised:
 *
 *   <root>/
 *     vulcan/.aid-o/           — two EPICs; a live EXECUTE run + a full DONE run
 *     cicero/.aid-o/           — one EPIC with a single LEGACY run (AC4)
 *     vulcan.broken-20260430-0741/.aid-o/   — denylisted (.broken + timestamp)
 *     cicero.broken-20260430-0735/.aid-o/   — denylisted
 *
 * The shapes mirror the real run-detail fixtures (fsm-state.yaml, gates_report,
 * compliance.json, audit-report.md, verifier-output files, queue.yaml).
 *
 * Module: src/routes/__fixtures__/fixture-tree.ts
 */

import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

/** Minimal AID workspace scaffold: config/ + work/evidence/ + tasks/. */
async function makeWorkspace(root: string, name: string): Promise<string> {
  const aido = join(root, name, '.aid-o');
  await mkdir(join(aido, 'config'), { recursive: true });
  await mkdir(join(aido, 'work', 'evidence'), { recursive: true });
  await mkdir(join(aido, 'tasks'), { recursive: true });
  return aido;
}

async function writeTask(
  aido: string,
  epicId: string,
  opts: { status?: string; title?: string; planRef?: string } = {},
): Promise<void> {
  const status = opts.status ?? 'active';
  const title = opts.title ?? `Demo ${epicId}`;
  const planRef = opts.planRef ?? 'P100';
  await writeFile(
    join(aido, 'tasks', `${epicId}.md`),
    `---
epic_id: ${epicId}
status: ${status}
plan_ref: ${planRef}
title: ${title}
---

# ${title}

## Context

Fixture EPIC for route tests.

## Goal

Exercise the cross-project read routes.

## Scope

### Allowed Paths
- packages/aid-server/

## Constraints

Read-only.

## DoD Gates
- tests pass

## Acceptance Criteria

- [ ] (backend) endpoint returns data
`,
    'utf-8',
  );
}

/** A v3 run dir with fsm-state.yaml carrying a real state + started_at. */
async function makeV3Run(
  aido: string,
  epicId: string,
  runId: string,
  opts: { state: string; startedAt: string },
): Promise<string> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(
    join(runDir, 'fsm-state.yaml'),
    `epic_id: ${epicId}
run_id: ${runId}
state: ${opts.state}
current_step: 2
total_steps: 2
mode: full
branch: task/${epicId}/main
base_commit: 4d6a84588fa6acc8eefac9b1a7c91c2651a9243f
gate_retries: 0
escalation_count: 0
streamlined_mode: false
started_at: "${opts.startedAt}"
created_at: "${opts.startedAt}"
plan_path: null
`,
    'utf-8',
  );
  return runDir;
}

/** A legacy run dir: state.yaml marker only, NO fsm-state.yaml (AC4). */
async function makeLegacyRun(
  aido: string,
  epicId: string,
  runId: string,
): Promise<string> {
  const runDir = join(aido, 'work', 'evidence', epicId, runId);
  await mkdir(runDir, { recursive: true });
  await writeFile(
    join(runDir, 'state.yaml'),
    `current_step: 3\ntotal_steps: 5\n`,
    'utf-8',
  );
  return runDir;
}

/** Add the full DONE-run evidence set (gates + compliance + audit + verify). */
async function addFullEvidence(runDir: string): Promise<void> {
  await writeFile(
    join(runDir, 'gates_report.json'),
    JSON.stringify({
      epic_id: 'E-100-1_1',
      run_id: 'R-E100-1',
      overall: 'pass',
      completed_at: '2026-06-18T15:22:47Z',
      gates: {
        bats_fsm: {
          gate: 'bats_fsm',
          result: 'pass',
          exit_code: 0,
          duration_ms: 18770,
          output: '1..58\nok 1',
          attempts: 1,
        },
        plan_diff: {
          gate: 'plan_diff',
          result: 'pass',
          exit_code: 2,
          duration_ms: 49,
          output: '',
          attempts: 1,
        },
      },
      _generated_by: 'aid-run-gates.sh@v2.16.0',
    }),
    'utf-8',
  );

  // NESTED artifact under gates/ — mirrors real runs (the bulk of artifacts live
  // in gates/, reporter/, steps/, not the run root; readGates prefers the nested
  // path per §4.4). Full gates object so RunDetail.gates is populated AND the
  // /file nested-reach test (HIGH-3) + smoke test (MED-4) have a real artifact.
  await mkdir(join(runDir, 'gates'), { recursive: true });
  await writeFile(
    join(runDir, 'gates', 'gates_report.json'),
    JSON.stringify({
      epic_id: 'E-100-1_1',
      run_id: 'R-E100-1',
      overall: 'pass',
      completed_at: '2026-06-18T15:22:47Z',
      gates: {
        bats_fsm: {
          gate: 'bats_fsm',
          result: 'pass',
          exit_code: 0,
          duration_ms: 18770,
          output: '1..58\nok 1',
          attempts: 1,
        },
        plan_diff: {
          gate: 'plan_diff',
          result: 'pass',
          exit_code: 2,
          duration_ms: 49,
          output: '',
          attempts: 1,
        },
      },
      _generated_by: 'aid-run-gates.sh@v2.16.0',
    }),
    'utf-8',
  );

  await writeFile(
    join(runDir, 'compliance.json'),
    JSON.stringify({
      epic_id: 'E-100-1_1',
      run_id: 'R-E100-1',
      aid_version: 'v3',
      deploy_era: 'post-session-b',
      evaluated_at: '2026-06-18T17:56:16Z',
      coverage_mode: 'full',
      checks: {
        verifier_outputs: {
          cp2_per_step_dispatched: true,
          cp2_per_step_verdict: 'pass',
          cp2_per_step_provenance: ['agent_tool', 'agent_tool'],
          cp3_code_review_dispatched: true,
          cp3_code_review_verdict: 'pass',
          cp3_code_review_provenance: 'agent_tool',
          provenance_aggregate: 'agent_tool',
        },
      },
      failures: [],
      force_override_count: 0,
      force_override_reasons: [],
      overall: 'pass',
      notes: [],
    }),
    'utf-8',
  );

  await writeFile(
    join(runDir, 'audit-report.md'),
    `blocking_findings: false
overall_score: 91

# Audit Report — E-100-1_1

## Executive Summary

Strong run.

### Low

**[DOC-1] missing changelog**
`,
    'utf-8',
  );

  await writeFile(
    join(runDir, 'verifier-output-step-0.md'),
    `# Step 1 Verify — backend\n\n## Result: PASS\n`,
    'utf-8',
  );
  await writeFile(
    join(runDir, 'verifier-output-step-1.md'),
    `# Step 2 Verify — qa\n\n## Result: PASS\n`,
    'utf-8',
  );
}

/**
 * Write a `work/backlog.md` whose DECLARED frontmatter counter DISAGREES with the
 * actual table rows (Step 7 honesty fixture). There are 3 rows total (2 open, 1
 * done), but the frontmatter claims `closed_count: 9` / `open_count: 1`. A
 * truthful reader MUST report the ACTUAL counts (open:2, closed:1) and a warning —
 * never the fabricated declared numbers. This is a REAL on-disk file so the test
 * proves the warning is real, not mocked.
 */
async function writeStaleBacklog(aido: string): Promise<void> {
  await mkdir(join(aido, 'work'), { recursive: true });
  await writeFile(
    join(aido, 'work', 'backlog.md'),
    `---
open_count: 1
closed_count: 9
---

# Backlog

| # | Type | Description | Priority | Status |
|---|------|-------------|----------|--------|
| IMP-1 | improvement | Add retry on flaky watcher | high | open |
| BUG-2 | bug | Activity feed drops topic filter | medium | open |
| DOC-3 | docs | Document the queue read path | low | done |
`,
    'utf-8',
  );
}

/** A config/queue.yaml with one critical queued EPIC. */
async function writeQueue(aido: string): Promise<void> {
  await writeFile(
    join(aido, 'config', 'queue.yaml'),
    `paused: false
queue:
  - epic_id: E-100-1_1
    path: .aid-o/tasks/E-100-1_1.md
    priority: critical
    status: queued
    added_at: "2026-06-18T10:00:00Z"
`,
    'utf-8',
  );
}

/**
 * Add a FAILING compliance.json run to the vulcan workspace (Step 7 AC1). The
 * `failures[]` are STRUCTURED objects (check / evidence / severity) — exactly the
 * shape the cross-project ComplianceView must surface (never raw strings). This
 * is a REAL on-disk run so the roll-up reads it through the un-mocked cache.
 *
 * Must be called AFTER {@link buildFixtureTree} (it appends a new run dir to the
 * existing vulcan EPIC and re-uses its fsm-state shape).
 */
export async function writeComplianceFailRun(root: string): Promise<void> {
  const aido = join(root, 'vulcan', '.aid-o');
  const runDir = await makeV3Run(aido, 'E-100-1_1', 'R-E100-FAIL', {
    state: 'DONE',
    startedAt: '2026-06-19T20:00:00Z',
  });
  await writeFile(
    join(runDir, 'compliance.json'),
    JSON.stringify({
      epic_id: 'E-100-1_1',
      run_id: 'R-E100-FAIL',
      aid_version: 'v3',
      deploy_era: 'post-session-b',
      evaluated_at: '2026-06-19T21:00:00Z',
      coverage_mode: 'full',
      checks: {},
      failures: [
        {
          check: 'verifier_provenance',
          evidence: 'provenance_aggregate=unverifiable for cp2-step-1',
          severity: 'blocking',
        },
        {
          check: 'dod_present',
          evidence: 'no DoD section detected in EPIC spec',
          severity: 'advisory',
        },
      ],
      force_override_count: 1,
      force_override_reasons: ['PM override: provenance noise'],
      overall: 'fail',
      notes: [],
    }),
    'utf-8',
  );
}

/**
 * Build the full fixture tree under `root`. Returns the (real, on-disk) layout
 * the scanner will discover. Idempotent per fresh temp root.
 */
export async function buildFixtureTree(root: string): Promise<void> {
  // --- vulcan: two EPICs, a live EXECUTE run + a full DONE run ---
  const vulcan = await makeWorkspace(root, 'vulcan');
  await writeTask(vulcan, 'E-100-1_1', { status: 'active', title: 'Cockpit MVP' });
  await writeTask(vulcan, 'E-099-1_1', { status: 'completed', title: 'Earlier EPIC' });
  await writeQueue(vulcan);

  const doneRun = await makeV3Run(vulcan, 'E-100-1_1', 'R-E100-1', {
    state: 'EXECUTE',
    startedAt: '2026-06-18T14:04:10Z',
  });
  await addFullEvidence(doneRun);

  await makeV3Run(vulcan, 'E-099-1_1', 'R-E099-1', {
    state: 'DONE',
    startedAt: '2026-06-10T09:00:00Z',
  });

  // --- cicero: one EPIC with a single LEGACY run (AC4) ---
  const cicero = await makeWorkspace(root, 'cicero');
  await writeTask(cicero, 'E-050-1_1', { status: 'draft', title: 'Cicero EPIC', planRef: 'P050' });
  await makeLegacyRun(cicero, 'E-050-1_1', 'run_20260224_115f');

  // --- wan: a stale-counter backlog fixture + a queue (Step 7 AC2/AC4) ---
  const wan = await makeWorkspace(root, 'wan');
  await writeTask(wan, 'E-030-1_1', { status: 'active', title: 'WAN EPIC', planRef: 'P030' });
  await writeQueue(wan); // read-only queue surface (AC4)
  await writeStaleBacklog(wan); // declared counter disagrees with rows (AC2)
  await makeV3Run(wan, 'E-030-1_1', 'R-E030-1', {
    state: 'GATES',
    startedAt: '2026-06-19T08:00:00Z',
  });

  // --- acta: an EPIC + run used by the activity-feed test (Step 7 AC3) ---
  const acta = await makeWorkspace(root, 'acta');
  await writeTask(acta, 'E-020-1_1', { status: 'active', title: 'ACTA EPIC', planRef: 'P020' });
  await makeV3Run(acta, 'E-020-1_1', 'R-E020-1', {
    state: 'EXECUTE',
    startedAt: '2026-06-19T12:00:00Z',
  });

  // --- denylisted broken workspaces (MUST NOT be discovered) ---
  await makeWorkspace(root, 'vulcan.broken-20260430-0741');
  await makeWorkspace(root, 'cicero.broken-20260430-0735');
}
