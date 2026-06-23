/**
 * Aggregate / boundary AUDIT builders (EPIC E-047-4_7, Step 5 — §13.5.7 / SF4 /
 * MF7).
 *
 * Two DISTINCT plan/project audit metrics, both {@link AuditSummary}-shaped and
 * both honestly nullable:
 *
 *  - {@link pickBoundaryAudit} — `boundaryAudit`: the SINGLE plan-boundary
 *    auditor run = the `AuditSummary` of the latest audited run of the plan's
 *    LAST EPIC. Answers "how did the auditor judge this plan at its close?". One
 *    report, one score. (aid-orchestrator P046 last EPIC E-046-3_3 → 84.)
 *
 *  - {@link buildAggregateAudit} — `aggregateAudit`: the cross-EPIC aggregate =
 *    the `AuditSummary` of the EPIC whose latest-run score is the MEDIAN of the
 *    member EPICs' scored points (ties → the LATER EPIC by `startedAt`). Its
 *    `overallScore` is therefore the MEDIAN score, and its
 *    `headlineCs`/`topReasons`/`topRisks` are that REAL EPIC's — NEVER a
 *    synthesized blend or arithmetic mean (§13.5.7 "flag, never fake": the
 *    displayed number is an actual report's score, the chosen EPIC is named).
 *
 * Honest sparse/empty handling (§13.5.7): `scoredEpicCount` (member EPICs with a
 * parseable latest-run score) drives degradation —
 *   - 0 scored → `present:true, overallScore:null, medianEpicId:null` + warning
 *     "napříč plánem zatím není auditovaný EPIC se skóre" (e.g. sousto-na-miru,
 *     0 audit-report.md across its workspace). NEVER 0 %.
 *   - 1 scored → the median IS that EPIC, plus a "agregát z jediného auditu
 *     (n=1)" warning so the UI shows "1 audit" not a cross-EPIC read.
 *   - ≥2 scored → the median is meaningful.
 *
 * Pure projection over already-built per-run `AuditSummary` objects; no new
 * source of truth, no writes (SF2). Never throws.
 */

import type { AuditSummary } from "@aid/contract";

export type AggregateAudit = AuditSummary & {
  scoredEpicCount: number;
  medianEpicId: string | null;
};

/**
 * One member EPIC's contribution to the aggregate: its id, the time-ordering key
 * (latest-run `started_at`, for tie-breaking), and that EPIC's latest-run
 * {@link AuditSummary} (§5.4 run→EPIC = latest-run rule).
 */
export interface MemberEpicSummary {
  epicId: string;
  /** latest-run `started_at` — the tie-break ordering key (§13.5.4 / §13.5.7). */
  startedAt: string | null;
  summary: AuditSummary;
}

// ---------------------------------------------------------------------------
// boundaryAudit
// ---------------------------------------------------------------------------

/**
 * `boundaryAudit` (§13.5.7) — the single plan-boundary auditor run. Pass the
 * latest audited run's {@link AuditSummary} of the plan's LAST EPIC. When that
 * EPIC has no `audit-report.md`, pass `null` → a `present:false` summary.
 */
export function pickBoundaryAudit(
  lastEpicSummary: AuditSummary | null,
): AuditSummary {
  if (lastEpicSummary === null) {
    return {
      present: false,
      overallScore: null,
      scoreSource: null,
      blockingFindings: null,
      blockingFindingsSource: null,
      categories: [],
      topReasons: [],
      topRisks: [],
      countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
      autoFixableCount: 0,
      nextSteps: [],
      headlineCs: "Auditor zatím na tomto běhu neběžel.",
      previousScoreHint: null,
      rawRelPath: "audit-report.md",
      warnings: ["no audit-report.md for the plan boundary EPIC"],
    };
  }
  return lastEpicSummary;
}

// ---------------------------------------------------------------------------
// aggregateAudit — median-EPIC pick (NOT a mean)
// ---------------------------------------------------------------------------

/**
 * `aggregateAudit` (§13.5.7 / SF4 / MF7) — the median-EPIC summary across the
 * member EPICs' scored latest runs. The headline `overallScore` is the MEDIAN
 * score, sourced from a REAL on-disk report (never a synthesized mean). For an
 * even count the median is the LOWER-middle element (a real point, not an
 * interpolated midpoint). Ties resolve to the LATER EPIC by `startedAt`.
 */
export function buildAggregateAudit(
  memberEpicSummaries: MemberEpicSummary[],
): AggregateAudit {
  // Only members with a parseable latest-run score contribute to the median.
  const scored = memberEpicSummaries.filter(
    (m) => m.summary.present && typeof m.summary.overallScore === "number",
  );
  const scoredEpicCount = scored.length;

  if (scoredEpicCount === 0) {
    return {
      ...emptyAggregateBase(),
      scoredEpicCount: 0,
      medianEpicId: null,
      headlineCs: "Napříč plánem zatím není auditovaný EPIC se skóre.",
      warnings: ["napříč plánem zatím není auditovaný EPIC se skóre"],
    };
  }

  // Sort ascending by score; ties → the LATER EPIC by startedAt sorts AFTER, so
  // it lands at the higher index and is preferred by the lower-middle pick when
  // it sits at the median position.
  const sorted = [...scored].sort((a, b) => {
    const sa = a.summary.overallScore as number;
    const sb = b.summary.overallScore as number;
    if (sa !== sb) return sa - sb;
    return compareStartedAt(a.startedAt, b.startedAt); // earlier first → later last
  });

  // Lower-middle element = a REAL on-disk report (§13.5.7: never an interpolated
  // midpoint). For odd counts this is the exact median; for even counts the
  // lower of the two middles. Ties at the median position resolve to the later
  // EPIC because equal-score members are ordered earlier→later and we then step
  // to the LAST member sharing the median score.
  const medianScore = sorted[Math.floor((sorted.length - 1) / 2)].summary
    .overallScore as number;
  const sameScore = sorted.filter(
    (m) => m.summary.overallScore === medianScore,
  );
  // ties → later EPIC by startedAt (sameScore is already earlier→later).
  const chosen = sameScore[sameScore.length - 1];

  const warnings = [...chosen.summary.warnings];
  if (scoredEpicCount === 1) {
    warnings.push("agregát z jediného auditu (n=1)");
  }

  return {
    ...chosen.summary,
    overallScore: medianScore,
    scoredEpicCount,
    medianEpicId: chosen.epicId,
    warnings,
  };
}

function compareStartedAt(a: string | null, b: string | null): number {
  // null sorts FIRST (treated as oldest), so a real timestamp always wins ties.
  const ta = a ? Date.parse(a) : Number.NEGATIVE_INFINITY;
  const tb = b ? Date.parse(b) : Number.NEGATIVE_INFINITY;
  const va = Number.isNaN(ta) ? Number.NEGATIVE_INFINITY : ta;
  const vb = Number.isNaN(tb) ? Number.NEGATIVE_INFINITY : tb;
  if (va !== vb) return va - vb;
  return 0;
}

function emptyAggregateBase(): AuditSummary {
  return {
    present: true,
    overallScore: null,
    scoreSource: null,
    blockingFindings: null,
    blockingFindingsSource: null,
    categories: [],
    topReasons: [],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: "",
    previousScoreHint: null,
    rawRelPath: "audit-report.md",
    warnings: [],
  };
}
