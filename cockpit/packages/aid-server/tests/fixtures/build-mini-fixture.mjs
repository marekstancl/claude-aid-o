#!/usr/bin/env node
/**
 * Deterministic generator for the COMMITTED minimal conformance fixture
 * (E-047-4_7 REOPEN, PM #1/#2/#3/#6). Writes a small, fully SANITIZED `.aid-o`
 * tree — NO copy of real project data, NO secrets — that exercises exactly the
 * bugs the PM runtime reviews caught:
 *
 *   - P701-alpha            : 3-member plan (tier-1 plan_path + tier-2 plan_ref +
 *                             tier-3 derived); all latest runs pass → `passed`.
 *                             E-701-1_1 ALSO has an OLDER ERROR run → proves PM #2
 *                             (a historical failure must NOT flip current outcome).
 *   - P702-first / P702-second : two stems sharing the number P702 (collision).
 *                             E-702-1_1 has an explicit plan_path → P702-second
 *                             stem, so it attaches to P702-second ONLY (PM #1,
 *                             never P702-first by number-first). Number "P702" is
 *                             ambiguous (alias → 409; exact stem → 200).
 *   - P703-partial          : member E-703-1_1's run has NO usable timing /
 *                             checkpoint data → metrics.partial === true (PM #6).
 *   - P709-lonely           : real plan file with ZERO members → present as
 *                             `unverifiable` (PM decision b: not dropped, not 404).
 *
 * Re-run via `scripts/refresh-fixtures.sh`. Output is committed; the blocking
 * conformance test reads it and FAILS (not skips) if missing. No Date.now()/
 * Math.random() — every value is a literal, so the fixture is byte-stable.
 */
import { mkdir, writeFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, 'mini');

async function w(rel, body) {
  const abs = join(ROOT, rel);
  await mkdir(dirname(abs), { recursive: true });
  await writeFile(abs, body, 'utf-8');
}

async function run(epic, runId, opts = {}) {
  const base = `demo/.aid-o/work/evidence/${epic}/${runId}`;
  const state = opts.state ?? 'DONE';
  const startedAt = opts.startedAt ?? '2026-06-18T14:00:00Z';
  const planPath = opts.planPath ?? 'null';
  await w(
    `${base}/fsm-state.yaml`,
    `epic_id: ${epic}\nrun_id: ${runId}\nstate: ${state}\ncurrent_step: 2\ntotal_steps: 2\n` +
      `mode: full\nbranch: task/${epic}/main\nbase_commit: abc1234\ngate_retries: 0\n` +
      `escalation_count: 0\nstreamlined_mode: false\nstarted_at: "${startedAt}"\n` +
      `created_at: "${startedAt}"\nplan_path: ${planPath}\n`,
  );
  if (opts.audit) await w(`${base}/audit-report.md`, opts.audit);
  if (opts.compliance) await w(`${base}/compliance.json`, JSON.stringify(opts.compliance));
  if (opts.gates) await w(`${base}/gates/gates_report.json`, JSON.stringify(opts.gates));
  if (opts.planDiff) await w(`${base}/plan-diff.json`, JSON.stringify(opts.planDiff));
  if (opts.timeline) await w(`${base}/timeline.jsonl`, opts.timeline);
}

const PASS_DIFF = { ac_count: 4, summary: { present_count: 4 }, overall_verdict: 'pass' };
const PASS_GATES = { gates: { tests: { gate: 'tests', result: 'pass', exit_code: 0, attempts: 1 } } };
const PASS_COMPLIANCE = { overall: 'pass', checks: {}, failures: [] };
const passRun = (extra = {}) => ({
  state: 'DONE',
  audit: `---\noverall_score: 90\nblocking_findings: false\n---\n# Audit\n`,
  planDiff: PASS_DIFF,
  gates: PASS_GATES,
  compliance: PASS_COMPLIANCE,
  ...extra,
});

async function main() {
  if (existsSync(ROOT)) await rm(ROOT, { recursive: true, force: true });

  // Layout sanity (§7.2): a valid workspace needs BOTH config/ and work/ under .aid-o/.
  await w('demo/.aid-o/config/plugin.yaml', `plugin_path: /dev/null\n`);

  // ---- Plans ----
  await w('demo/.aid-o/plans/P701-alpha.md', `---\ntitle: Alpha plan\n---\n# P701 — Alpha\n\nThree-member plan.\n`);
  await w('demo/.aid-o/plans/P702-first-foo.md', `---\ntitle: P702 first\n---\n# P702 first\n`);
  await w('demo/.aid-o/plans/P702-second-bar.md', `---\ntitle: P702 second\n---\n# P702 second\n`);
  await w('demo/.aid-o/plans/P703-partial.md', `---\ntitle: Partial plan\n---\n# P703 — Partial\n`);
  await w('demo/.aid-o/plans/P709-lonely.md', `---\ntitle: Lonely plan\n---\n# P709 — Lonely\n\nNo members.\n`);

  // ---- Tasks (membership tiers) ----
  await w('demo/.aid-o/tasks/E-701-1_1-step-one.md', `---\nepic_id: E-701-1_1\n---\n# E-701-1_1\n`); // tier-1 (plan_path on run)
  await w('demo/.aid-o/tasks/E-701-2_1-step-two.md', `---\nepic_id: E-701-2_1\nplan_ref: .aid-o/plans/P701-alpha.md\n---\n# E-701-2_1\n`); // tier-2
  await w('demo/.aid-o/tasks/E-701-4_1-step-four.md', `---\nepic_id: E-701-4_1\n---\n# E-701-4_1\n`); // tier-3 derived (E-701 → P701, single stem)
  await w('demo/.aid-o/tasks/E-702-1_1-collide.md', `---\nepic_id: E-702-1_1\n---\n# E-702-1_1\n`); // tier-1 plan_path → P702-second
  await w('demo/.aid-o/tasks/E-703-1_1-partial.md', `---\nepic_id: E-703-1_1\n---\n# E-703-1_1\n`); // tier-3 derived (E-703 → P703)

  // ---- Runs ----
  // P701 members: all LATEST runs pass; E-701-1_1 also has an OLDER ERROR run.
  await run('E-701-1_1', 'R-701-1-old', { state: 'ERROR', startedAt: '2026-06-10T09:00:00Z', planDiff: PASS_DIFF });
  await run('E-701-1_1', 'R-701-1-new', passRun({ startedAt: '2026-06-18T10:00:00Z', planPath: '.aid-o/plans/P701-alpha.md' }));
  await run('E-701-2_1', 'R-701-2', passRun({ startedAt: '2026-06-18T11:00:00Z' }));
  await run('E-701-4_1', 'R-701-4', passRun({ startedAt: '2026-06-18T12:00:00Z' }));

  // P702 collision: explicit plan_path names the P702-second stem.
  await run('E-702-1_1', 'R-702-1', passRun({ startedAt: '2026-06-18T13:00:00Z', planPath: '.aid-o/plans/P702-second-bar.md' }));

  // P703 partial: a real run (fsm-state present so it indexes) but with NO
  // timeline anchor, NO step timing, NO gates, NO checkpoints → no wall time, no
  // step durations, all CP repeats null → metrics.partial must be true (PM #6,
  // the vulcan/E-045-7_8 shape).
  await run('E-703-1_1', 'R-703-1', { state: 'DONE', startedAt: '2026-06-18T15:00:00Z' });

  // ---- work/ ----
  await w('demo/.aid-o/work/lessons-learned.md', `# Lessons Learned\n\n| Date | Lesson | Context |\n|------|--------|---------|\n| 2026-06-18 | Stem is the primary identity | E-702-1_1 |\n`);
  await w('demo/.aid-o/work/backlog.md', `# Backlog\n\n_Active proposals: 1_\n`);

  console.log(`mini fixture written to ${ROOT}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
