/**
 * Cross-project Plan Outcome Analytics — `buildPlanOutcomeAnalytics` (EPIC
 * E-047-4_7, Step 7 — §13.12, Rev 4.1 addendum).
 *
 * Pure projection over the SAME scanner-cache objects (`RunDetail`, checkpoints,
 * timeline, gates, compliance) used elsewhere. It performs NO new disk writes and
 * MUST NOT execute the shell diagnostic (`aid-diagnostic.sh`) on a request — that
 * script is a regression oracle for overlapping fixture fields only, never the
 * backend implementation (§13.12 "Source and ownership").
 *
 * Binding honesty contract (§13.12):
 *  - Missing proof can NEVER classify `passed` (rule 2). Unknowns (legacy/stub/
 *    missing artifacts, unknown CP repeats) → `unverifiable` + `dataPartial`,
 *    NEVER folded to zero, NEVER green.
 *  - An id-derived ('derived') membership is official-but-weaker (a warning),
 *    not an orphan — orphans are excluded upstream (this builder only sees tiers
 *    1-3 members).
 *  - Plans sort attention-first (`failed`, `partial`, `in_progress`,
 *    `unverifiable`, `passed`) then newest activity (`lastActivityAt` desc).
 *
 * The five-branch classification precedence ({@link classifyPlanOutcome}):
 *  1. failed         — explicit terminal evidence on any member's latest run.
 *  2. passed         — EVERY member's latest run is DONE + AC 100% + gates pass
 *                      + compliance pass. Missing proof can never pass.
 *  3. in_progress    — no explicit failure + ≥1 latest run non-terminal.
 *  4. partial        — no active/failed run, ≥1 member passed, another incomplete.
 *  5. unverifiable   — the remaining cases (legacy/stub/missing/unknown proofs).
 *
 * Module: src/plan/build-plan-outcomes.ts
 */

import type {
  PlanOutcome,
  PlanOutcomeAnalytics,
  PlanOutcomeSummary,
} from '@aid/contract';

// ===========================================================================
// Inputs (the route assembles these from the scanner cache — pure builder)
// ===========================================================================

/** One member EPIC's latest-run signals the outcome classifier needs. */
export interface OutcomeMemberRun {
  epicId: string;
  runId: string;
  /** RunFormat: legacy/stub members are unverifiable proof, not failures. */
  format: 'v3' | 'legacy' | 'stub';
  /** FSM state of the LATEST run; null when not v3-parseable. */
  state: string | null;
  /** AC verification: present/total from plan-diff.json; null = not measured. */
  ac: { present: number; total: number } | null;
  /** Final gate verdict over this run's gates: 'pass'|'fail'|null (no gates). */
  gateFinal: 'pass' | 'fail' | null;
  /** Compliance overall: 'pass'|'fail'|null (no compliance.json). */
  compliance: 'pass' | 'fail' | null;
}

/** Aggregate signals across ALL runs of ALL member EPICs of one plan. */
export interface OutcomePlanInput {
  projectId: string;
  /** The plan number `P{NNN}` (tier-resolved member set). */
  planId: string;
  title: string;
  /** Latest run per member EPIC (the classification basis). */
  members: OutcomeMemberRun[];
  /** Count of member EPICs (tiers 1-3). */
  epicsTotal: number;
  /** Member EPICs whose latest run is DONE. */
  epicsDone: number;
  /** Total runs across all member EPICs. */
  runsTotal: number;
  /** Runs whose state is ERROR. */
  failedRuns: number;
  /** Final-gate FAILURES across member latest runs. */
  gateFailures: number;
  /** Σ gate retries across member runs (fsm-state gate_retries / attempts-1). */
  gateRetries: number;
  /** Known CP repeat total + unknown-CP count (NEVER fold unknown to 0, §13.12). */
  checkpointRetries: { knownTotal: number; unknownCheckpoints: number };
  /** FSM failure buckets from member timelines (§13.12). */
  fsmFailures: { precondition: number; increment: number; doneAdvance: number; other: number };
  /** Σ escalation_count across member runs. */
  escalations: number;
  /** Σ force_override_count across member runs. */
  forceOverrides: number;
  /** Compliance pass/fail/unknown counts across member latest runs. */
  compliance: { passed: number; failed: number; unknown: number };
  /** Normalized top failure reasons (gate/compliance/precond reasons, counted). */
  topFailureReasons: { reason: string; count: number }[];
  /** Plan-boundary Reporter outcome: 'pass'|'fail'|'partial'|null (§13.12 rule 1). */
  reporterOutcome: 'pass' | 'fail' | 'partial' | null;
  firstStartedAt: string | null;
  lastCompletedAt: string | null;
  lastActivityAt: string | null;
}

// ===========================================================================
// Classification (§13.12 binding precedence)
// ===========================================================================

/** Non-terminal v3 FSM states (a member still in flight). */
const NON_TERMINAL = new Set(['READY', 'EXECUTE', 'GATES', 'ESCALATION']);

/**
 * Classify ONE plan into exactly one of the five outcomes by the §13.12 binding
 * precedence. Returns the outcome plus `dataPartial` (true when ANY required
 * proof is unknown — legacy/stub member, unmeasured AC, missing gates/compliance,
 * or unknown CP repeats) and the warnings that explain a non-defensible result.
 *
 * Missing proof can NEVER yield `passed` (rule 2): the passed branch requires
 * EVERY member to have an explicit DONE + AC 100% + gate pass + compliance pass.
 */
export function classifyPlanOutcome(input: OutcomePlanInput): {
  outcome: PlanOutcome;
  dataPartial: boolean;
  warnings: string[];
} {
  const warnings: string[] = [];

  // Data-coverage flags — any unknown proof makes the data partial. Never zeroed.
  const hasLegacyOrStub = input.members.some((m) => m.format !== 'v3');
  const unknownCps = input.checkpointRetries.unknownCheckpoints > 0;
  if (hasLegacyOrStub) {
    warnings.push('některý člen je legacy/stub běh — důkaz nelze ověřit');
  }
  if (unknownCps) {
    warnings.push(
      `${input.checkpointRetries.unknownCheckpoints} checkpoint(ů) bez známého počtu opakování — nelze ověřit`,
    );
  }

  // --- Rule 1: failed — explicit terminal evidence on any member's latest run.
  const anyFailed =
    input.failedRuns > 0 ||
    input.reporterOutcome === 'fail' ||
    input.members.some(
      (m) =>
        m.state === 'ERROR' ||
        m.gateFinal === 'fail' ||
        m.compliance === 'fail',
    );
  if (anyFailed) {
    return { outcome: 'failed', dataPartial: hasLegacyOrStub || unknownCps, warnings };
  }

  // --- Rule 3 (checked before passed/partial when active): in_progress —
  // no explicit failure + at least one latest run is GENUINELY non-terminal.
  // Gated on a v3 format: a legacy/stub run's RunDetail.state defaults to
  // 'READY' (the builder fills a missing state) — that is NOT a real in-flight
  // run, it is unverifiable. Only a v3 run can be truly active. (Escalations are
  // still counted; ESCALATION counts as non-terminal here.)
  const anyActive = input.members.some(
    (m) => m.format === 'v3' && m.state !== null && NON_TERMINAL.has(m.state),
  );

  // Per-member "passed" verdict (rule 2 atom): explicit DONE + AC 100% + gate
  // pass + compliance pass. A member missing ANY proof is NOT passed.
  const memberPassed = (m: OutcomeMemberRun): boolean =>
    m.format === 'v3' &&
    m.state === 'DONE' &&
    m.ac !== null &&
    m.ac.total > 0 &&
    m.ac.present === m.ac.total &&
    m.gateFinal === 'pass' &&
    m.compliance === 'pass';

  const passedMembers = input.members.filter(memberPassed);
  const allPassed =
    input.members.length > 0 && passedMembers.length === input.members.length;

  if (anyActive) {
    // No explicit failure, something still running → in_progress.
    return { outcome: 'in_progress', dataPartial: hasLegacyOrStub || unknownCps, warnings };
  }

  // --- Rule 2: passed — EVERY member passed (full proof). Missing proof can
  // never reach here. Unknown CP repeats / legacy members fail this gate.
  if (allPassed && !hasLegacyOrStub && !unknownCps) {
    return { outcome: 'passed', dataPartial: false, warnings };
  }

  // --- Rule 4: partial — no active/failed run, ≥1 member passed, another known
  // incomplete (a non-passed, non-active member that still has a defensible
  // "incomplete" signal — a v3 DONE run lacking full proof, or a measured AC gap).
  const knownIncomplete = (m: OutcomeMemberRun): boolean =>
    !memberPassed(m) &&
    m.format === 'v3' &&
    (m.state === 'DONE' || (m.ac !== null && m.ac.total > 0));
  const anyKnownIncomplete = input.members.some(knownIncomplete);
  if (passedMembers.length > 0 && anyKnownIncomplete) {
    warnings.push('plán je částečný — část EPICů hotová s plným důkazem, část ne');
    return { outcome: 'partial', dataPartial: hasLegacyOrStub || unknownCps, warnings };
  }

  // --- Rule 5: unverifiable — everything else (legacy/stub/missing/unknown
  // proof prevents a defensible result). NOT failure, NOT success (§13.12).
  warnings.push('výsledek nelze obhájit — chybí nebo neúplné důkazy (nelze ověřit)');
  return { outcome: 'unverifiable', dataPartial: true, warnings };
}

// ===========================================================================
// Per-plan summary
// ===========================================================================

/** Build a single {@link PlanOutcomeSummary} from one plan's aggregated input. */
export function buildPlanOutcomeSummary(input: OutcomePlanInput): PlanOutcomeSummary {
  const { outcome, dataPartial, warnings } = classifyPlanOutcome(input);

  return {
    projectId: input.projectId,
    planId: input.planId,
    title: input.title,
    outcome,
    epicsTotal: input.epicsTotal,
    epicsDone: input.epicsDone,
    runsTotal: input.runsTotal,
    failedRuns: input.failedRuns,
    gateFailures: input.gateFailures,
    gateRetries: input.gateRetries,
    checkpointRetries: { ...input.checkpointRetries },
    fsmFailures: { ...input.fsmFailures },
    escalations: input.escalations,
    forceOverrides: input.forceOverrides,
    compliance: { ...input.compliance },
    topFailureReasons: [...input.topFailureReasons].sort(
      (a, b) => b.count - a.count || a.reason.localeCompare(b.reason),
    ),
    firstStartedAt: input.firstStartedAt,
    lastCompletedAt: input.lastCompletedAt,
    lastActivityAt: input.lastActivityAt,
    dataPartial,
    warnings,
  };
}

// ===========================================================================
// Analytics roll-up + sort + filters
// ===========================================================================

/** Attention-first outcome sort weight (§13.12). */
const OUTCOME_WEIGHT: Record<PlanOutcome, number> = {
  failed: 0,
  partial: 1,
  in_progress: 2,
  unverifiable: 3,
  passed: 4,
};

/**
 * Build the cross-project {@link PlanOutcomeAnalytics} from all discovered plans'
 * aggregated inputs. Sorts attention-first then newest-activity-desc, reconciles
 * `totals` EXACTLY to the returned rows, and emits a sorted-unique
 * `partialProjects` list (projects with any `dataPartial` plan). Pure.
 *
 * @param plans   one input per tier-1-to-3 plan across all projects.
 * @param generatedAt server scan time (ISO).
 */
export function buildPlanOutcomeAnalytics(
  plans: OutcomePlanInput[],
  generatedAt: string,
): PlanOutcomeAnalytics {
  const rows = plans.map(buildPlanOutcomeSummary).sort(comparePlanRow);
  return {
    generatedAt,
    plans: rows,
    totals: reconcileTotals(rows),
    partialProjects: sortedUniqueProjects(rows.filter((r) => r.dataPartial)),
  };
}

/** Attention-first then newest-activity-desc; deterministic id tiebreak. */
export function comparePlanRow(a: PlanOutcomeSummary, b: PlanOutcomeSummary): number {
  const ow = OUTCOME_WEIGHT[a.outcome] - OUTCOME_WEIGHT[b.outcome];
  if (ow !== 0) return ow;
  const ta = a.lastActivityAt ? Date.parse(a.lastActivityAt) : NaN;
  const tb = b.lastActivityAt ? Date.parse(b.lastActivityAt) : NaN;
  const va = Number.isNaN(ta) ? -Infinity : ta;
  const vb = Number.isNaN(tb) ? -Infinity : tb;
  if (va !== vb) return vb - va; // newest first
  const byProj = a.projectId.localeCompare(b.projectId);
  if (byProj !== 0) return byProj;
  return a.planId.localeCompare(b.planId);
}

/** Reconcile totals EXACTLY to the (already-filtered) rows. */
export function reconcileTotals(
  rows: PlanOutcomeSummary[],
): PlanOutcomeAnalytics['totals'] {
  const t = {
    plans: rows.length,
    passed: 0,
    partial: 0,
    failed: 0,
    inProgress: 0,
    unverifiable: 0,
    failedRuns: 0,
    gateFailures: 0,
    gateRetries: 0,
    escalations: 0,
    forceOverrides: 0,
  };
  for (const r of rows) {
    if (r.outcome === 'passed') t.passed++;
    else if (r.outcome === 'partial') t.partial++;
    else if (r.outcome === 'failed') t.failed++;
    else if (r.outcome === 'in_progress') t.inProgress++;
    else if (r.outcome === 'unverifiable') t.unverifiable++;
    t.failedRuns += r.failedRuns;
    t.gateFailures += r.gateFailures;
    t.gateRetries += r.gateRetries;
    t.escalations += r.escalations;
    t.forceOverrides += r.forceOverrides;
  }
  return t;
}

function sortedUniqueProjects(rows: PlanOutcomeSummary[]): string[] {
  return [...new Set(rows.map((r) => r.projectId))].sort((a, b) =>
    a.localeCompare(b),
  );
}

// ===========================================================================
// Filter validation (route uses these; invalid → 400, unknown project → 404)
// ===========================================================================

/** The five valid outcome enum values, for `?outcome=` validation. */
export const VALID_OUTCOMES: ReadonlySet<PlanOutcome> = new Set<PlanOutcome>([
  'passed',
  'partial',
  'failed',
  'in_progress',
  'unverifiable',
]);

/** True iff `v` is a valid {@link PlanOutcome} enum value. */
export function isValidOutcome(v: string): v is PlanOutcome {
  return VALID_OUTCOMES.has(v as PlanOutcome);
}

/** True iff `v` is a parseable ISO-8601 timestamp (for `?since=` validation). */
export function isValidSince(v: string): boolean {
  if (v.trim().length === 0) return false;
  return !Number.isNaN(Date.parse(v));
}

/**
 * Apply the exact `outcome` + ISO `since` (lower bound on `lastActivityAt`)
 * filters to a row set. `project` is applied upstream (it gates 404). Pure.
 */
export function filterOutcomeRows(
  rows: PlanOutcomeSummary[],
  filters: { outcome?: PlanOutcome | null; since?: string | null },
): PlanOutcomeSummary[] {
  let out = rows;
  if (filters.outcome) {
    out = out.filter((r) => r.outcome === filters.outcome);
  }
  if (filters.since) {
    const sinceMs = Date.parse(filters.since);
    out = out.filter((r) => {
      if (r.lastActivityAt === null) return false;
      const ms = Date.parse(r.lastActivityAt);
      return !Number.isNaN(ms) && ms >= sinceMs;
    });
  }
  return out;
}
