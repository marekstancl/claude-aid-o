/**
 * Managerial `Brief` projection (EPIC E-047-4_7, Step 4) — spec §13.1-§13.4.
 *
 * `buildBrief(runSet, scope, since): Brief` is the SINGLE projection that powers
 * all three brief scopes (D1):
 *   - infra   → `GET /api/brief`              (Screen G "Co potřebuju vědět")
 *   - project → `GET /api/brief/:projectId`   (Screen B tab 1)
 *   - plan    → `GET /api/brief/:projectId/:planId` (Plan screen tab 1)
 *
 * It is DETERMINISTIC and PURE: same `runSet` → identical `Brief` (apart from the
 * caller-supplied `generatedAt`), no LLM, no network, no disk reads, no writes,
 * never throws. The routes assemble `runSet` from the scanner cache (already-
 * parsed §4/§5 signals — compliance, gates, FSM, queue, timeline, audit) and
 * hand it to this projection; this module re-reads NOTHING from disk (SF2 — the
 * brief adds no new file reads, §13.1/§13.4).
 *
 * Honesty contract (§5.7 / D2 "flag, never fake"):
 *  - `successProbability` is ALWAYS `{value:null, source:null}` in MVP1 (MF5
 *    invariant, AC #14) — no model exists to produce a number.
 *  - A `neurceno` project NEVER drags the infra risk to a false green: infra
 *    `risk.level` is the WORST (max) level across DETERMINABLE projects, and
 *    `neurceno` projects are merely named in `reasons`, never lowering the level
 *    (the Step-3 coverage floor extends to infra aggregation, §13.4 step 3).
 *  - No `?since=` → `sinceLastSeen:{since:null, items:[], counts:zeroed}` (first
 *    visit) — the UI renders "první návštěva", not the whole history (AC #15).
 *
 * Every `BriefItem.explanation` is resolved via `explain()` over a real §6.3 /
 * §13.10 dictionary key, so the managerial brief speaks the exact same Czech as
 * Screen C/D — terminology cannot drift (§13.1).
 *
 * Module: src/brief/build-brief.ts
 */

import type {
  Brief,
  BriefItem,
  ComplianceFailure,
  ComplianceRun,
  FsmState,
  GateResult,
  Risk,
  RiskLevel,
  RunDetail,
  SuccessProbability,
} from '@aid/contract';
import { explain } from '../explain/index.js';
import { computeRisk, RISK, type RiskSignals } from './risk.js';

// ===========================================================================
// Input shape — the assembled run set (pure projection input, no disk)
// ===========================================================================

/** A queue entry the brief surfaces in `nextUp` (already parsed by the route). */
export interface BriefQueueEntry {
  epicId: string;
  priority: string;
  status: string;
  addedAt: string | null;
}

/**
 * One member of a scope's run set: the latest run of an EPIC plus the identity
 * needed to build stable `BriefItem.id`s and deep-link `href`s. `detail` is the
 * already-assembled {@link RunDetail} (compliance / gates / audit / timeline /
 * state) — the brief reads ONLY from it, never from disk.
 *
 * `membershipSource` is set for plan-scope members (MF1) so a `derived` member
 * can carry the §13.10 `concept:plan_membership_derived` note; it is omitted /
 * undefined for infra + project scope.
 */
export interface BriefRunMember {
  projectId: string;
  epicId: string;
  runId: string;
  detail: RunDetail;
  /** Run-dir max-file mtime as ISO (drives `sinceLastSeen` "touched since"). */
  touchedAt: string | null;
  /** Run-dir max-file mtime as epoch ms (drives the §13.2 S7 staleRun signal). */
  touchedAtMs: number | null;
  membershipSource?: 'plan_path' | 'plan_ref' | 'derived' | 'orphan';
}

/** Per-project context the brief needs beyond its run members. */
export interface BriefProjectContext {
  projectId: string;
  /** `config/queue.yaml` rows, already parsed (camelCased). Empty when absent. */
  queue: BriefQueueEntry[];
  /** True when the project's `queue.yaml` was present but unparseable (§13.4). */
  queuePartial: boolean;
}

/**
 * Plan-scope-only extras (omitted for infra/project). Lessons surface as `info`
 * `BriefItem`s ("co jsme se na tomhle plánu naučili", §13.4 plan scope) and
 * `progressPct` frames `nextUp`.
 */
export interface BriefPlanContext {
  planId: string;
  /** Plan progress (done_epics/total_epics*100), null when not measurable. */
  progressPct: number | null;
  epicsTotal: number;
  epicsDone: number;
  /** Lessons filtered to the plan's EPIC ids (§4.7), already parsed. */
  lessons: { epicId: string | null; lesson: string; at: string | null }[];
}

/**
 * The fully-assembled input to {@link buildBrief}. One shape, three scopes — the
 * route differs only in how it fills this from the scanner cache (§13.4 "one
 * implementation, three callers").
 */
export interface BriefRunSet {
  /** null at infra scope; the single project id at project/plan scope. */
  projectId: string | null;
  /** set only at plan scope. */
  planId: string | null;
  /** The latest-run members in scope (all active EPICs for infra/project; the
   *  plan's member EPICs for plan scope). */
  members: BriefRunMember[];
  /** Per-project context keyed by projectId (queue + partial flags). */
  projects: BriefProjectContext[];
  /** Plan extras — only present at plan scope. */
  plan?: BriefPlanContext;
  /** Project ids that returned partial/degraded data (surfaced in route meta). */
  partialProjects: string[];
}

// ===========================================================================
// Constants
// ===========================================================================

/** Active FSM states — a run in one of these is "in flight" (§13.2 S7). */
const ACTIVE_STATES: ReadonlySet<FsmState> = new Set<FsmState>([
  'READY',
  'EXECUTE',
  'GATES',
  'ESCALATION',
]);

/** Severity → sort weight (blocking first, §13.1 "Sorting inside each list"). */
const SEVERITY_WEIGHT: Record<BriefItem['severity'], number> = {
  blocking: 0,
  warn: 1,
  info: 2,
};

/** Retry hot-spot threshold (§13.1 row 3 — surfaced only when count is known). */
const RETRY_HOTSPOT_MIN = 3;

/** sinceLastSeen item cap per scope (§13.3 — bounds payload). */
const SINCE_ITEM_CAP = 50;

/** The MVP1 successProbability envelope — binding invariant (MF5, AC #14). */
const MVP1_SUCCESS_PROBABILITY: SuccessProbability = { value: null, source: null };

/** RiskLevel → numeric rank for the infra worst-level (max) rule (§13.4 step 3). */
const RISK_RANK: Record<RiskLevel, number> = {
  neurceno: -1, // EXCLUDED from the max — never raises or lowers the level
  nizke: 0,
  stredni: 1,
  vysoke: 2,
};

// ===========================================================================
// Main entry
// ===========================================================================

/**
 * Build the managerial `Brief` for an assembled run set at one scope.
 *
 * @param runSet      the assembled members + per-project context (route-built).
 * @param scope       'infra' | 'project' | 'plan'.
 * @param since       the client `?since=` ISO timestamp, or null (first visit).
 * @param generatedAt server scan time (ISO) — injected so the function stays
 *                    pure/testable (no internal `Date.now()` in the decision path).
 */
export function buildBrief(
  runSet: BriefRunSet,
  scope: Brief['scope'],
  since: string | null,
  generatedAt: string,
): Brief {
  // The reference "now" for staleness (§13.2 S7) is the caller-supplied
  // `generatedAt` — NOT an internal Date.now() — so the function stays pure and
  // deterministic for a fixed (runSet, generatedAt). Unparseable → no stale.
  const nowMs = Date.parse(generatedAt);
  const refNowMs = Number.isNaN(nowMs) ? null : nowMs;

  // The seven answer dimensions (§13.1), each a sorted BriefItem[].
  const blockers = sortBriefItems(assembleBlockers(runSet));
  const watchOuts = sortBriefItems(assembleWatchOuts(runSet, refNowMs));
  const nextUp = sortBriefItems(assembleNextUp(runSet));
  const decisionsNeeded = sortBriefItems(assembleDecisionsNeeded(runSet));
  const sinceLastSeen = buildSinceLastSeen(runSet, since);
  const risk = buildScopeRisk(runSet, scope, refNowMs);

  return {
    scope,
    projectId: runSet.projectId,
    planId: runSet.planId,
    generatedAt,
    sinceLastSeen,
    blockers,
    watchOuts,
    nextUp,
    decisionsNeeded,
    risk,
    // MVP1 INVARIANT (MF5, AC #14): value AND source are ALWAYS null on EVERY
    // scope — no model exists to produce a number (D2). Cloned so a caller can
    // never mutate the shared literal.
    successProbability: { ...MVP1_SUCCESS_PROBABILITY },
  };
}

// ===========================================================================
// §13.1 row 2 — blockers ("co blokuje postup")
// ===========================================================================

/**
 * "Co blokuje postup": open blocking compliance failures (§4.5), runs in
 * ESCALATION (§4.1), repeated precondition fails, stuck/stale runs (§13.2
 * S5/S7), and a run in `done_phase==review` with no `pm_decision` (merge stuck).
 * Each item carries an `explanation` resolved via `explain()` over a real key.
 */
export function assembleBlockers(runSet: BriefRunSet): BriefItem[] {
  const items: BriefItem[] = [];

  for (const m of runSet.members) {
    const d = m.detail;

    // Open blocking compliance violations (§5.7-resolved upstream by the route).
    for (const f of openBlockingFailures(d.compliance)) {
      items.push({
        id: `${m.projectId}/${m.epicId}/${f.check}`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: f.check,
        explanation: explain({ kind: 'severity', id: 'blocking' }),
        severity: 'blocking',
        signal: 'open_blocking_violation',
        at: d.compliance?.evaluatedAt ?? m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // ESCALATION — a human is the blocker (also a decision; same id de-dupes).
    if (d.state === 'ESCALATION') {
      items.push(escalationItem(m));
    }

    // Repeated precondition fails (§13.2 S5) — pattern ≥2 by construction. This
    // is a hard blocker: the same transition keeps being refused.
    if (repeatedPreconditionFails(d)) {
      items.push({
        id: `${m.projectId}/${m.epicId}/repeated_precondition_fail`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'repeated_precondition_fail',
        explanation: explain({ kind: 'concept', id: 'stuck_or_looping' }),
        severity: 'blocking',
        signal: 'repeated_precondition_fail',
        at: m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // done_phase==review with no pm_decision while a merge gate is unmet.
    if (mergeStuck(d)) {
      items.push({
        id: `${m.projectId}/${m.epicId}/merge_pending`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'merge_pending',
        explanation: explain({ kind: 'concept', id: 'decision_needed' }),
        severity: 'blocking',
        signal: 'merge_pending',
        at: d.startedAt ?? m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }
  }

  return items;
}

// ===========================================================================
// §13.1 row 3 — watchOuts ("na co si dát pozor")
// ===========================================================================

/**
 * "Na co si dát pozor": advisory violations, force-overrides (+SYSTEMATIC),
 * retry hot-spots (≥3, only when the count is KNOWN, §5.2), stale runs, and
 * auditor NON-blocking findings (best-effort score / recommendations §4.3).
 */
export function assembleWatchOuts(runSet: BriefRunSet, refNowMs: number | null): BriefItem[] {
  const items: BriefItem[] = [];

  for (const m of runSet.members) {
    const d = m.detail;

    // Stale active run (§13.2 S7 / §13.1 row 3) — idle ≥ STALE_DAYS → warn.
    const stale = staleDaysFor(m, refNowMs);
    if (stale !== null) {
      items.push({
        id: `${m.projectId}/${m.epicId}/stale_run`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'stale_run',
        explanation: explain({
          kind: 'concept',
          id: 'stale_run',
          context: { staleDays: stale },
        }),
        severity: 'warn',
        signal: 'stale_run',
        at: m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // Advisory compliance failures.
    for (const f of advisoryFailures(d.compliance)) {
      items.push({
        id: `${m.projectId}/${m.epicId}/advisory/${f.check}`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: f.check,
        explanation: explain({ kind: 'severity', id: 'advisory' }),
        severity: 'warn',
        signal: 'advisory_violation',
        at: d.compliance?.evaluatedAt ?? m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // Force overrides (§4.5) — any bypass is a watch-out.
    const foc = d.compliance?.forceOverrideCount ?? 0;
    if (foc > 0) {
      const reasons = d.compliance?.forceOverrideReasons ?? [];
      items.push({
        id: `${m.projectId}/${m.epicId}/force_override`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'force_override',
        explanation: explain({
          kind: 'event',
          id: 'fsm_force_override',
          context: {
            blocked_checks: blockedChecksLabel(d.compliance),
            reason: reasons[0] ?? null,
          },
        }),
        severity: 'warn',
        signal: 'force_override',
        at: d.compliance?.evaluatedAt ?? m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // Retry hot-spot (§13.1 row 3) — gate retries known and ≥3.
    if (d.gateRetries >= RETRY_HOTSPOT_MIN) {
      items.push({
        id: `${m.projectId}/${m.epicId}/retry_hotspot`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'retry_hotspot',
        explanation: explain({ kind: 'concept', id: 'stuck_or_looping' }),
        severity: 'warn',
        signal: 'retry_hotspot',
        at: m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // Auditor NON-blocking findings (best-effort recommendations §4.3).
    const auditWatch = auditWatchItem(m);
    if (auditWatch) items.push(auditWatch);
  }

  return items;
}

// ===========================================================================
// §13.1 row 4 — nextUp ("co bude následovat")
// ===========================================================================

/**
 * "Co bude následovat": next `status:queued` EPICs by priority (§4.6), runs in
 * READY/EXECUTE (§4.1), and (plan scope) the plan progress. A malformed
 * queue.yaml for one project yields NO nextUp queue items for that project —
 * never a 500 (the route flags it in `partialProjects`, §13.4 honesty).
 */
export function assembleNextUp(runSet: BriefRunSet): BriefItem[] {
  const items: BriefItem[] = [];

  // Queued EPICs by priority, across the scope's projects.
  for (const proj of runSet.projects) {
    const queued = proj.queue
      .filter((q) => q.status === 'queued')
      .sort((a, b) => priorityWeight(a.priority) - priorityWeight(b.priority));
    for (const q of queued) {
      items.push({
        id: `${proj.projectId}/${q.epicId}/queued`,
        projectId: proj.projectId,
        epicId: q.epicId,
        title: q.epicId,
        explanation: explain({ kind: 'state', id: 'READY' }),
        severity: 'info',
        signal: 'queued_next',
        at: q.addedAt,
        href: hrefFor(proj.projectId, q.epicId),
      });
    }
  }

  // Runs in READY / EXECUTE (work in flight).
  for (const m of runSet.members) {
    if (m.detail.state === 'READY' || m.detail.state === 'EXECUTE') {
      items.push({
        id: `${m.projectId}/${m.epicId}/in_flight`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: m.detail.state,
        explanation: explain({ kind: 'state', id: m.detail.state }),
        severity: 'info',
        signal: 'run_in_flight',
        at: m.detail.startedAt ?? m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }
  }

  // Plan progress (plan scope only).
  if (runSet.plan) {
    const p = runSet.plan;
    items.push({
      id: `${runSet.projectId}/${p.planId}/progress`,
      projectId: runSet.projectId ?? '',
      planId: p.planId,
      title: 'plan_progress',
      explanation: explain({ kind: 'state', id: 'EXECUTE' }),
      severity: 'info',
      signal: 'plan_progress',
      at: null,
      href: `/p/${runSet.projectId}/plans/${p.planId}`,
    });
  }

  return items;
}

// ===========================================================================
// §13.1 row 5 — decisionsNeeded ("jaká rozhodnutí jsou potřeba")
// ===========================================================================

/**
 * "Jaká rozhodnutí jsou potřeba": runs awaiting `pm_decision`/merge (§4.0/§4.1),
 * ESCALATION (needs a human), and auditor `blocking_findings:true` (CP5 blocks
 * MERGE §4.2). ESCALATION items reuse the SAME `BriefItem.id` they carry in
 * `blockers` so the FE can de-dupe (§13.1) — intentional, not double counting.
 */
export function assembleDecisionsNeeded(runSet: BriefRunSet): BriefItem[] {
  const items: BriefItem[] = [];

  for (const m of runSet.members) {
    const d = m.detail;

    // Run awaiting a PM merge decision (done_phase==review, no pm_decision).
    if (mergeStuck(d)) {
      items.push({
        id: `${m.projectId}/${m.epicId}/merge_pending`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'merge_pending',
        explanation: explain({ kind: 'concept', id: 'decision_needed' }),
        severity: 'blocking',
        signal: 'merge_pending',
        at: d.startedAt ?? m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }

    // ESCALATION — same id as the blockers list (de-dupe, §13.1).
    if (d.state === 'ESCALATION') {
      items.push(escalationItem(m));
    }

    // Auditor blocking findings — CP5 blocks merge (§4.2).
    if (d.audit.blockingFindings === true) {
      items.push({
        id: `${m.projectId}/${m.epicId}/audit_blocking`,
        projectId: m.projectId,
        epicId: m.epicId,
        runId: m.runId,
        title: 'audit_blocking_findings',
        explanation: explain({ kind: 'role', id: 'auditor', context: { outcome: 'blocking' } }),
        severity: 'blocking',
        signal: 'audit_blocking_findings',
        at: m.touchedAt,
        href: hrefFor(m.projectId, m.epicId),
      });
    }
  }

  return items;
}

// ===========================================================================
// §13.3 — sinceLastSeen ("co se změnilo od poslední návštěvy")
// ===========================================================================

/**
 * Build the "touched since you left" view (§13.3). No `since` → first visit:
 * `since:null`, empty items, zeroed counts (AC #15 — the server stays read-only;
 * it writes nothing). With a `since`, a member whose run-dir max-file mtime is
 * `> since` is a changed run; a fresh blocking/advisory violation or gate fail on
 * such a member adds to the bucket counts. Items are capped to the most recent
 * {@link SINCE_ITEM_CAP} per scope to bound the payload.
 */
export function buildSinceLastSeen(
  runSet: BriefRunSet,
  since: string | null,
): Brief['sinceLastSeen'] {
  const zeroCounts = {
    newRuns: 0,
    newGateFails: 0,
    newViolations: 0,
    newBacklog: 0,
    stateTransitions: 0,
  };

  // First visit (no since / cleared storage): show nothing, write nothing.
  if (since === null) {
    return { since: null, items: [], counts: { ...zeroCounts } };
  }

  const sinceMs = Date.parse(since);
  // Unparseable since → treat as first visit (honest, never a flood).
  if (Number.isNaN(sinceMs)) {
    return { since, items: [], counts: { ...zeroCounts } };
  }

  const items: BriefItem[] = [];
  const counts = { ...zeroCounts };

  for (const m of runSet.members) {
    const touchedMs = m.touchedAtMs;
    if (touchedMs === null || touchedMs <= sinceMs) continue;

    // The run dir was touched since last visit → a changed run.
    counts.newRuns += 1;
    items.push({
      id: `${m.projectId}/${m.epicId}/${m.runId}/touched`,
      projectId: m.projectId,
      epicId: m.epicId,
      runId: m.runId,
      title: m.detail.state,
      explanation: explain({ kind: 'state', id: m.detail.state }),
      severity: 'info',
      signal: 'run_touched',
      at: m.touchedAt,
      href: hrefFor(m.projectId, m.epicId),
    });

    // New gate fails on a touched run.
    if (hasGateFail(m.detail.gates)) counts.newGateFails += 1;
    // New violations on a touched run (any failures present).
    if ((m.detail.compliance?.failures.length ?? 0) > 0) counts.newViolations += 1;
    // State transitions whose ts > since (from the per-run timeline).
    counts.stateTransitions += countTransitionsSince(m.detail, sinceMs);
  }

  // Cap to the most recent N (newest `at` first) to bound the payload (§13.3).
  items.sort((a, b) => (b.at ?? '').localeCompare(a.at ?? ''));
  const capped = items.slice(0, SINCE_ITEM_CAP);

  return { since, items: capped, counts };
}

// ===========================================================================
// §13.2 / §13.4 — risk (per-scope; infra = worst across determinable projects)
// ===========================================================================

/**
 * Resolve the scope's `Risk`. For project + plan scope the run set is one
 * project's members, so a single {@link computeRisk} over the aggregated signals
 * is the level. For infra scope the level is the WORST (max) across DETERMINABLE
 * projects (§13.4 step 3): `neurceno` projects are named in `reasons` but NEVER
 * lower the level (the Step-3 floor extends to infra aggregation, AC #4).
 */
export function buildScopeRisk(
  runSet: BriefRunSet,
  scope: Brief['scope'],
  refNowMs: number | null,
): Risk {
  if (scope !== 'infra') {
    // One project (or plan) → one signal set → one computeRisk.
    return computeRisk(extractRiskSignals(runSet.members, refNowMs));
  }
  return infraRisk(perProjectRisks(runSet, refNowMs));
}

/** Group infra members by project and compute each project's deterministic Risk. */
export function perProjectRisks(
  runSet: BriefRunSet,
  refNowMs: number | null,
): { projectId: string; risk: Risk }[] {
  const byProject = new Map<string, BriefRunMember[]>();
  for (const m of runSet.members) {
    const arr = byProject.get(m.projectId) ?? [];
    arr.push(m);
    byProject.set(m.projectId, arr);
  }
  // Include projects with zero in-scope members (they still get a neurceno risk
  // from an empty signal set — never a fake green).
  for (const proj of runSet.projects) {
    if (!byProject.has(proj.projectId)) byProject.set(proj.projectId, []);
  }
  const out: { projectId: string; risk: Risk }[] = [];
  for (const [projectId, members] of byProject) {
    out.push({ projectId, risk: computeRisk(extractRiskSignals(members, refNowMs)) });
  }
  out.sort((a, b) => a.projectId.localeCompare(b.projectId));
  return out;
}

/**
 * Infra worst-level aggregation (§13.4 step 3). The level is the MAX over
 * projects whose risk is DETERMINABLE (level !== 'neurceno'); `neurceno`
 * projects are listed in `reasons` ("u {n} projektů zatím málo dat") and do NOT
 * lower the level. When EVERY project is `neurceno`, the infra level is
 * `neurceno` too (honest — never a fake green by absence).
 */
export function infraRisk(perProject: { projectId: string; risk: Risk }[]): Risk {
  const determinable = perProject.filter((p) => p.risk.level !== 'neurceno');
  const undetermined = perProject.filter((p) => p.risk.level === 'neurceno');

  // No determinable project → infra is neurceno (coverage floor extends, AC #4).
  if (determinable.length === 0) {
    const reasons: Risk['reasons'] = [
      {
        text:
          undetermined.length > 0
            ? `U ${undetermined.length} projektů je zatím málo dat na odhad rizika.`
            : 'Zatím není žádný projekt s určitelným rizikem.',
        status: 'pozor',
        signal: 'insufficient_coverage',
        value: undetermined.length,
      },
    ];
    return { level: 'neurceno', reasons, confidence: 'low' };
  }

  // Worst (max) level across determinable projects.
  let worst: RiskLevel = 'nizke';
  for (const p of determinable) {
    if (RISK_RANK[p.risk.level] > RISK_RANK[worst]) worst = p.risk.level;
  }

  // Name the projects that drove the worst level, plus the neurceno tail.
  const drivers = determinable
    .filter((p) => p.risk.level === worst)
    .map((p) => p.projectId)
    .sort();
  const reasons: Risk['reasons'] = [];
  reasons.push({
    text: `Riziko ekosystému je ${czRiskLevel(worst)} kvůli: ${drivers.join(', ')}.`,
    status: worst === 'vysoke' ? 'selhalo' : worst === 'stredni' ? 'pozor' : 'proslo',
    signal: `infra_worst_${worst}`,
    value: drivers.length,
  });
  if (undetermined.length > 0) {
    reasons.push({
      text: `U ${undetermined.length} projektů zatím málo dat (nezapočítává se do úrovně).`,
      status: 'pozor',
      signal: 'insufficient_coverage',
      value: undetermined.length,
    });
  }

  // Confidence follows the worst project's own confidence (level-setting signal).
  const worstProject = determinable.find((p) => p.risk.level === worst);
  const confidence = worstProject?.risk.confidence ?? 'low';

  return { level: worst, reasons, confidence };
}

// ===========================================================================
// RiskSignals extraction (§13.2.1 — from real run data)
// ===========================================================================

/**
 * Extract a {@link RiskSignals} set from a scope's run members (§13.2.1). The
 * signals fold across the members (one EPIC's latest run each): availability
 * flags OR across members (a source present on any member counts as available);
 * count signals SUM; boolean signals OR. This feeds {@link computeRisk} verbatim
 * — the extraction here mirrors the §13.2.1 source column exactly.
 */
export function extractRiskSignals(
  members: BriefRunMember[],
  refNowMs: number | null,
): RiskSignals {
  let openBlockingViolations = 0;
  let escalationCount = 0;
  let escalationActive = false;
  let forceOverrideCount = 0;
  let forceOverrideSystematic = false;
  let repeatedPreconditionFails = false;
  let stuckOrLoopingFsm = false;
  let staleRun = false;
  let staleDays: number | undefined;
  let auditBlockingFindings = false;

  let complianceAvailable = false;
  let gatesAvailable = false;
  let timelineAvailable = false;
  let auditAvailable = false;
  let fsmStateAvailable = false;
  let runDirAvailable = false;

  // S4 — first-pass gate rate over runs WITH a gates_report.json (§5.7 denom).
  let gateRunCount = 0;
  let gateFirstPassRuns = 0;

  for (const m of members) {
    const d = m.detail;

    // Availability: a v3 run always has a run dir + fsm-state (S7 / S2 presence).
    runDirAvailable = true;
    if (d.format === 'v3') fsmStateAvailable = true;

    // S1 — open blocking compliance violations (route resolved §5.7).
    if (d.compliance !== null) {
      complianceAvailable = true;
      openBlockingViolations += openBlockingFailures(d.compliance).length;
      // S3 — force overrides (+SYSTEMATIC per §4.5).
      forceOverrideCount += d.compliance.forceOverrideCount;
      if (isSystematicOverride(d.compliance)) forceOverrideSystematic = true;
    }

    // S2 — escalation count + any run currently ESCALATION.
    escalationCount += d.escalationCount;
    if (d.state === 'ESCALATION') escalationActive = true;

    // S4 — gates source + first-pass rate (a run is first-pass when it has gate
    // results AND every gate's attempts ≤ 1 AND no gate failed).
    if (hasGatesReport(d.gates)) {
      gatesAvailable = true;
      gateRunCount += 1;
      if (isFirstPassRun(d.gates)) gateFirstPassRuns += 1;
    }

    // S5 / S6 — timeline-derived patterns (require a non-empty per-run timeline).
    if (d.timeline.length > 0) {
      timelineAvailable = true;
      if (repeatedPreconditionFails || repeatedPreconditionFailsIn(d)) {
        repeatedPreconditionFails = true;
      }
      if (stuckOrLoopingFsm || loopingIncrementIn(d)) stuckOrLoopingFsm = true;
    }

    // S8 — auditor blocking findings on the latest run.
    if (d.audit.present) {
      auditAvailable = true;
      if (d.audit.blockingFindings === true) auditBlockingFindings = true;
    }

    // S7 — stale active run (idle ≥ STALE_DAYS). Always-available source.
    const stale = staleDaysFor(m, refNowMs);
    if (stale !== null) {
      staleRun = true;
      staleDays = staleDays === undefined ? stale : Math.max(staleDays, stale);
    }
  }

  const gateFirstPassRate = gateRunCount > 0 ? gateFirstPassRuns / gateRunCount : null;

  return {
    openBlockingViolations,
    escalationCount,
    escalationActive,
    forceOverrideCount,
    forceOverrideSystematic,
    gateFirstPassRate,
    gateRunCount,
    repeatedPreconditionFails,
    stuckOrLoopingFsm,
    staleRun,
    ...(staleDays !== undefined ? { staleDays } : {}),
    auditBlockingFindings,
    complianceAvailable,
    gatesAvailable,
    timelineAvailable,
    auditAvailable,
    fsmStateAvailable,
    runDirAvailable,
  };
}

// ===========================================================================
// Shared item builders
// ===========================================================================

/** The ESCALATION BriefItem — shared between blockers and decisionsNeeded. */
function escalationItem(m: BriefRunMember): BriefItem {
  return {
    id: `${m.projectId}/${m.epicId}/escalation`,
    projectId: m.projectId,
    epicId: m.epicId,
    runId: m.runId,
    title: 'ESCALATION',
    explanation: explain({ kind: 'state', id: 'ESCALATION' }),
    severity: 'blocking',
    signal: 'escalation_active',
    at: m.detail.startedAt ?? m.touchedAt,
    href: hrefFor(m.projectId, m.epicId),
  };
}

/**
 * Auditor non-blocking watch-out (§13.1 row 3) — present audit, NOT blocking,
 * with at least one risk/recommendation. null when there is nothing to surface.
 */
function auditWatchItem(m: BriefRunMember): BriefItem | null {
  const a = m.detail.audit;
  if (!a.present || a.blockingFindings === true) return null;
  const hasFindings = a.topRisks.length > 0 || a.nextSteps.length > 0 || a.autoFixableCount > 0;
  if (!hasFindings) return null;
  return {
    id: `${m.projectId}/${m.epicId}/audit_recommended`,
    projectId: m.projectId,
    epicId: m.epicId,
    runId: m.runId,
    title: 'audit_recommended',
    explanation: explain({
      kind: 'role',
      id: 'auditor',
      context: { outcome: 'recommended', count: a.nextSteps.length || a.autoFixableCount },
    }),
    severity: 'warn',
    signal: 'audit_recommended',
    at: m.touchedAt,
    href: hrefFor(m.projectId, m.epicId),
  };
}

// ===========================================================================
// Pure signal helpers (all over already-parsed RunDetail — no disk)
// ===========================================================================

/** Open blocking failures on a run's compliance (route applies §5.7 resolution). */
function openBlockingFailures(c: ComplianceRun | null): ComplianceFailure[] {
  if (c === null) return [];
  return c.failures.filter((f) => f.severity === 'blocking');
}

/** Advisory failures on a run's compliance. */
function advisoryFailures(c: ComplianceRun | null): ComplianceFailure[] {
  if (c === null) return [];
  return c.failures.filter((f) => f.severity === 'advisory');
}

/**
 * SYSTEMATIC force-override (§4.5): a coarse deterministic proxy over the parsed
 * compliance — many overrides (≥3) OR a low-quality reason. The fine §4.5
 * heuristics (avg>1, ≥30% forced) need cross-run aggregation the route does not
 * pass here; this conservative single-run proxy never FALSELY flags systematic
 * (it only fires on a clearly-repeated bypass), keeping the vysoke tier honest.
 */
function isSystematicOverride(c: ComplianceRun): boolean {
  if (c.forceOverrideCount >= 3) return true;
  // Low-quality reasons (empty / too short) on an actual override → systematic.
  if (c.forceOverrideCount > 0) {
    const reasons = c.forceOverrideReasons;
    if (reasons.length === 0) return true;
    if (reasons.every((r) => r.trim().length < 8)) return true;
  }
  return false;
}

/** A label of the blocked checks behind a force override (for the explanation). */
function blockedChecksLabel(c: ComplianceRun | null): string | null {
  if (c === null) return null;
  const checks = c.failures.map((f) => f.check);
  return checks.length > 0 ? checks.join(', ') : null;
}

/** True when a run is in `done_phase==review` with no `pm_decision` (merge stuck). */
function mergeStuck(d: RunDetail): boolean {
  return d.donePhase === 'review' && (d.pmDecision === null || d.pmDecision === '');
}

/** True when ANY gate failed in a run (drives `sinceLastSeen.newGateFails`). */
function hasGateFail(gates: GateResult[]): boolean {
  return gates.some((g) => g.result === 'fail');
}

/** True when a run carries any gate results at all (S4 gates-report presence). */
function hasGatesReport(gates: GateResult[]): boolean {
  return gates.length > 0;
}

/**
 * True when a run passed every gate on the FIRST attempt: it has gate results,
 * no gate failed, and no gate needed >1 attempt (§5.7 first-pass definition).
 */
function isFirstPassRun(gates: GateResult[]): boolean {
  if (gates.length === 0) return false;
  for (const g of gates) {
    if (g.result === 'fail') return false;
    // attempts 0 (unknown) is treated as 1 (first pass) — never penalize unknown.
    if (g.attempts > 1) return false;
  }
  return true;
}

/**
 * Stale-active-run check (§13.2 S7): an ACTIVE run whose max-file mtime is older
 * than {@link RISK.STALE_DAYS}. Returns the idle day count when stale, else null.
 */
function staleDaysFor(m: BriefRunMember, refNowMs: number | null): number | null {
  if (refNowMs === null) return null;
  if (!ACTIVE_STATES.has(m.detail.state)) return null;
  if (m.touchedAtMs === null) return null;
  const idleMs = refNowMs - m.touchedAtMs;
  if (idleMs <= 0) return null;
  const idleDays = Math.floor(idleMs / 86_400_000);
  return idleDays >= RISK.STALE_DAYS ? idleDays : null;
}

/**
 * Repeated precondition fails within ONE run's timeline (§13.2 S5): the same
 * `(from,to,reason)` `fsm_precondition_fail` ≥ {@link RISK.REPEAT_FAIL_MIN}, or
 * any explicit `fsm_precondition_repeated_fail` event.
 */
function repeatedPreconditionFailsIn(d: RunDetail): boolean {
  const counts = new Map<string, number>();
  for (const e of d.timeline) {
    if (e.event === 'fsm_precondition_repeated_fail') return true;
    if (e.event !== 'fsm_precondition_fail') continue;
    const reason = asRawString(e.raw, 'reason');
    const key = `${e.from ?? ''}→${e.to ?? ''}|${reason ?? ''}`;
    const n = (counts.get(key) ?? 0) + 1;
    counts.set(key, n);
    if (n >= RISK.REPEAT_FAIL_MIN) return true;
  }
  return false;
}

/**
 * Looping increment fails within ONE run's timeline (§13.2 S6): the same
 * `(step,reason)` `fsm_increment_fail` ≥ {@link RISK.INCREMENT_FAIL_MIN}.
 */
function loopingIncrementIn(d: RunDetail): boolean {
  const counts = new Map<string, number>();
  for (const e of d.timeline) {
    if (e.event !== 'fsm_increment_fail') continue;
    const reason = asRawString(e.raw, 'reason');
    const key = `${e.step ?? ''}|${reason ?? ''}`;
    const n = (counts.get(key) ?? 0) + 1;
    counts.set(key, n);
    if (n >= RISK.INCREMENT_FAIL_MIN) return true;
  }
  return false;
}

/** True when this run's timeline shows ANY repeated precondition pattern. */
function repeatedPreconditionFails(d: RunDetail): boolean {
  return repeatedPreconditionFailsIn(d);
}

/** Count `fsm_transition` events with `ts > sinceMs` (§13.3 state transitions). */
function countTransitionsSince(d: RunDetail, sinceMs: number): number {
  let n = 0;
  for (const e of d.timeline) {
    if (e.event !== 'fsm_transition') continue;
    const ms = Date.parse(e.ts);
    if (!Number.isNaN(ms) && ms > sinceMs) n += 1;
  }
  return n;
}

// ===========================================================================
// Sorting / formatting helpers
// ===========================================================================

/**
 * Sort a BriefItem list (§13.1): blocking → warn → info, then newest `at` first.
 * Stable tie-break on `id` so the order is fully deterministic.
 */
export function sortBriefItems(items: BriefItem[]): BriefItem[] {
  return [...items].sort((a, b) => {
    const sw = SEVERITY_WEIGHT[a.severity] - SEVERITY_WEIGHT[b.severity];
    if (sw !== 0) return sw;
    const at = (b.at ?? '').localeCompare(a.at ?? '');
    if (at !== 0) return at;
    return a.id.localeCompare(b.id);
  });
}

/** Deep-link to an EPIC's Screen B/C view (§13.1). */
function hrefFor(projectId: string, epicId: string): string {
  return `/p/${projectId}/e/${epicId}`;
}

/** Queue priority → sort weight (critical first). */
function priorityWeight(priority: string): number {
  switch (priority.toLowerCase()) {
    case 'critical':
      return 0;
    case 'high':
      return 1;
    case 'medium':
      return 2;
    case 'low':
      return 3;
    default:
      return 2;
  }
}

/** Czech label for a risk level (for the infra worst-level reason text). */
function czRiskLevel(level: RiskLevel): string {
  switch (level) {
    case 'vysoke':
      return 'vysoké';
    case 'stredni':
      return 'střední';
    case 'nizke':
      return 'nízké';
    default:
      return 'neurčeno';
  }
}

/** Read a string field out of an ActivityEvent.raw bag (never throws). */
function asRawString(raw: Record<string, unknown>, key: string): string | null {
  const v = raw[key];
  return typeof v === 'string' && v.length > 0 ? v : null;
}
