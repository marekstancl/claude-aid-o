/**
 * Aggregate / boundary audit builder test suite (EPIC E-047-4_7, Step 5 —
 * §13.5.7 / SF4 / MF7).
 *
 * The aggregate is the median-EPIC summary across the member EPICs' scored
 * latest runs — its `overallScore` MUST be a REAL on-disk score (never a
 * synthesized mean), and the chosen `medianEpicId` MUST be a real EPIC. Worked
 * numbers are the §13.5.7 disk-verified sets:
 *   - aid-orchestrator project {84,89,92,92,95} → median 92 (ties→later EPIC).
 *   - aid-orchestrator P046 plan {89,95,84} → median 89, distinct from the
 *     boundaryAudit (E-046-3_3 = 84) — SF4 / AC #23.
 *   - sousto-na-miru (0 audited EPICs) → present:true, overallScore:null,
 *     scoredEpicCount:0 + warning (never 0).
 */

import { describe, expect, it } from "vitest";
import type { AuditSummary } from "@aid/contract";
import {
  buildAggregateAudit,
  pickBoundaryAudit,
  type MemberEpicSummary,
} from "./build-aggregate-audit.js";

// A minimal real-shaped per-run summary carrying a given score (or null = the
// honest no-score run). headlineCs/topReasons are that "EPIC's own" — we tag
// them with the epic id so we can prove the aggregate copies the REAL chosen
// EPIC's fields verbatim, not a blend.
function epicSummary(score: number | null): AuditSummary {
  return {
    present: true,
    overallScore: score,
    scoreSource: score === null ? null : "frontmatter",
    blockingFindings: false,
    blockingFindingsSource: "frontmatter",
    categories: [],
    topReasons: score === null ? [] : [`score-${score}-reason`],
    topRisks: [],
    countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 0 },
    autoFixableCount: 0,
    nextSteps: [],
    headlineCs: `headline-for-${score}`,
    previousScoreHint: null,
    rawRelPath: "audit-report.md",
    warnings: [],
  };
}

function member(
  epicId: string,
  score: number | null,
  startedAt: string | null,
): MemberEpicSummary {
  return { epicId, startedAt, summary: epicSummary(score) };
}

// ---------------------------------------------------------------------------
// AC3 — median-EPIC pick (worked numbers) + distinct boundary
// ---------------------------------------------------------------------------

describe("buildAggregateAudit — median-EPIC pick (AC3, §13.5.7)", () => {
  it("aid-orchestrator project {84,89,92,92,95} → overallScore 92, real EPIC, ties→later", () => {
    const members = [
      member("E-036", 92, "2026-06-05T10:00:00Z"),
      member("E-042", 92, "2026-06-07T10:00:00Z"),
      member("E-046-1", 89, "2026-06-18T14:04:10Z"),
      member("E-046-2", 95, "2026-06-18T14:04:24Z"),
      member("E-046-3", 84, "2026-06-18T14:04:37Z"),
    ];
    const agg = buildAggregateAudit(members);
    expect(agg.overallScore).toBe(92);
    expect(agg.scoredEpicCount).toBe(5);
    // ties (E-036 vs E-042, both 92) → later EPIC by startedAt = E-042.
    expect(agg.medianEpicId).toBe("E-042");
    // the headline is the CHOSEN real EPIC's own — never a blend.
    expect(agg.headlineCs).toBe("headline-for-92");
    expect(agg.topReasons).toEqual(["score-92-reason"]);
  });

  it("P046 plan {89,95,84} → overallScore 89 (E-046-1); distinct from boundary 84 (SF4/AC#23)", () => {
    const members = [
      member("E-046-1", 89, "2026-06-18T14:04:10Z"),
      member("E-046-2", 95, "2026-06-18T14:04:24Z"),
      member("E-046-3", 84, "2026-06-18T14:04:37Z"),
    ];
    const agg = buildAggregateAudit(members);
    expect(agg.overallScore).toBe(89);
    expect(agg.medianEpicId).toBe("E-046-1");

    const boundary = pickBoundaryAudit(epicSummary(84)); // last EPIC E-046-3_3
    expect(boundary.overallScore).toBe(84);
    // The two metrics are genuinely distinct numbers.
    expect(agg.overallScore).not.toBe(boundary.overallScore);
  });

  it("krok P013 {93,90,89,91,86} → median 90 (a real five-EPIC aggregate)", () => {
    const members = [
      member("E-013-1", 93, "2026-04-01T10:00:00Z"),
      member("E-013-2", 90, "2026-04-02T10:00:00Z"),
      member("E-013-3", 89, "2026-04-03T10:00:00Z"),
      member("E-013-4", 91, "2026-04-04T10:00:00Z"),
      member("E-013-5", 86, "2026-04-05T10:00:00Z"),
    ];
    const agg = buildAggregateAudit(members);
    expect(agg.overallScore).toBe(90);
    expect(agg.medianEpicId).toBe("E-013-2");
  });

  it("the median is always a REAL on-disk score — never a synthesized mean", () => {
    // mean of {80, 100} = 90, but neither EPIC scored 90. median-EPIC picks 80.
    const agg = buildAggregateAudit([
      member("E-a", 80, "2026-01-01T00:00:00Z"),
      member("E-b", 100, "2026-01-02T00:00:00Z"),
    ]);
    expect([80, 100]).toContain(agg.overallScore); // a real point
    expect(agg.overallScore).not.toBe(90); // not the mean
    expect(agg.overallScore).toBe(80); // lower-middle = real point
  });
});

// ---------------------------------------------------------------------------
// AC4 / AC5 — sparse + tie handling
// ---------------------------------------------------------------------------

describe("buildAggregateAudit — sparse/empty handling (AC4, AC5, §13.5.7)", () => {
  it("0 scored EPICs (sousto-na-miru) → present:true, overallScore:null, count 0 + warning (NEVER 0)", () => {
    const agg = buildAggregateAudit([]);
    expect(agg.present).toBe(true);
    expect(agg.overallScore).toBeNull();
    expect(agg.scoredEpicCount).toBe(0);
    expect(agg.medianEpicId).toBeNull();
    expect(agg.overallScore).not.toBe(0); // honesty: never a fabricated 0
    expect(
      agg.warnings.some((w) => w.includes("není auditovaný EPIC se skóre")),
    ).toBe(true);
    expect(agg.headlineCs).toContain(
      "Napříč plánem zatím není auditovaný EPIC se skóre",
    );
  });

  it("members present but all no-score → treated as 0 scored", () => {
    const agg = buildAggregateAudit([
      member("E-x", null, "2026-01-01T00:00:00Z"),
      member("E-y", null, "2026-01-02T00:00:00Z"),
    ]);
    expect(agg.scoredEpicCount).toBe(0);
    expect(agg.overallScore).toBeNull();
  });

  it('exactly 1 scored → median is that EPIC + "n=1" warning (AC5)', () => {
    const agg = buildAggregateAudit([
      member("E-only", 84, "2026-06-19T10:00:00Z"),
      member("E-none", null, "2026-06-18T10:00:00Z"),
    ]);
    expect(agg.scoredEpicCount).toBe(1);
    expect(agg.overallScore).toBe(84);
    expect(agg.medianEpicId).toBe("E-only");
    expect(agg.warnings).toContain("agregát z jediného auditu (n=1)");
  });

  it("ties at the median resolve to the LATER EPIC by started_at (AC5)", () => {
    // three 50s; later startedAt wins the tie.
    const agg = buildAggregateAudit([
      member("E-early", 50, "2026-01-01T00:00:00Z"),
      member("E-mid", 50, "2026-01-02T00:00:00Z"),
      member("E-late", 50, "2026-01-03T00:00:00Z"),
    ]);
    expect(agg.overallScore).toBe(50);
    expect(agg.medianEpicId).toBe("E-late");
  });

  it("null startedAt sorts oldest so a real timestamp wins a tie", () => {
    const agg = buildAggregateAudit([
      member("E-null", 70, null),
      member("E-dated", 70, "2026-01-01T00:00:00Z"),
    ]);
    expect(agg.overallScore).toBe(70);
    expect(agg.medianEpicId).toBe("E-dated");
  });
});

// ---------------------------------------------------------------------------
// pickBoundaryAudit
// ---------------------------------------------------------------------------

describe("pickBoundaryAudit — single plan-boundary run (§13.5.7)", () => {
  it("returns the last EPIC summary verbatim", () => {
    const last = epicSummary(84);
    expect(pickBoundaryAudit(last)).toBe(last);
  });

  it("null (last EPIC unaudited) → present:false stub, deterministic headline, no throw", () => {
    const b = pickBoundaryAudit(null);
    expect(b.present).toBe(false);
    expect(b.overallScore).toBeNull();
    expect(b.headlineCs).toBe("Auditor zatím na tomto běhu neběžel.");
    expect(b.warnings.length).toBeGreaterThan(0);
  });
});
