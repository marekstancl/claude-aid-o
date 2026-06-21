/**
 * Per-run AuditSummary builder test suite (EPIC E-047-4_7, Step 5 — §13.5).
 *
 * The HIGHEST fixture-only false-green-risk step in Phase 4. Two defenses:
 *
 *  1. INLINE fixtures are BYTE-EXACT copies of the real on-disk shapes — the
 *     fence-less frontmatter `overall_score: 84` (NO `---` fences, the §13.5.1
 *     trap that defeats gray-matter), the `**Total** **89/100**` table row, the
 *     `## Score: 95/100` heading, the numeric `blocking_findings: 0` form. These
 *     are NOT clean fixtures — they reproduce the exact patterns that fooled a
 *     naive parser.
 *
 *  2. A REAL-DISK guard block reads the actual committed-but-gitignored E-046
 *     reports when present in this workspace and asserts the SAME triples, so a
 *     fixture that drifts from disk is caught. Skipped (not failed) when the
 *     workspace evidence is absent (fresh clone / CI), keeping the suite
 *     portable while still exercising real bytes on a dev machine.
 */

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  buildAuditSummary,
  buildHeadlineCs,
  parseBlockingFindings,
  parseCategories,
  parseFindings,
  parseOverallScore,
  type ParsedAuditReport,
} from "./build-audit-summary.js";

function summaryFor(
  rawText: string | null,
  present = true,
): ReturnType<typeof buildAuditSummary> {
  const parsed: ParsedAuditReport = { present, rawText };
  return buildAuditSummary("/x/run", parsed);
}

// ---------------------------------------------------------------------------
// BYTE-EXACT inline fixtures — the three real score shapes (§13.5.1)
// ---------------------------------------------------------------------------

// E-046-3_3 — fence-less frontmatter `overall_score: 84` + `## Scores` table
// (Status column, /100). Verified on disk: gray-matter returns EMPTY frontmatter
// for this fence-less head, so the score MUST come from a raw regex.
const FX_FRONTMATTER = `blocking_findings: false
overall_score: 84

# Audit Report — E-046-3_3

## Scores

| Category       | Score | Status |
|----------------|-------|--------|
| Code Quality   | 92    | PASS   |
| Security       | 100   | PASS   |
| Documentation  | 72    | WARN   |
| Process        | 80    | PASS   |
| **Overall**    | **84**| PASS   |

## Findings

### Code Quality (score: 92, -8)

**A8 — Anti-pattern: Last Updated not bumped**
- Area: \`plan-writing.md\`
- Severity: Low
- Effort: small
- auto_fixable: true

**A8 — Magic number inlined**
- Area: \`aid-prefilter.sh:206\`
- Severity: Low
- Effort: small
- auto_fixable: true
`;

// E-046-2_3 — `## Score: 95/100` heading, no score table.
const FX_HEADING = `# Audit Report — E-046-2_3
blocking_findings: false

## Score: 95/100

## Findings

### Medium

- **area:** \`x.bats:119\`
  **severity:** Low
`;

// E-046-1_3 — `**Total** **89/100**` table row, /25 categories.
const FX_TABLE = `blocking_findings: false
_generated_by: aid-orchestrator:auditor@E-046-1_3

# Audit Report — E-046-1_3

## Score

| Dimension | Score |
|-----------|-------|
| Code      | 22/25 |
| Security  | 25/25 |
| Docs      | 22/25 |
| Process   | 20/25 |
| **Total** | **89/100** |

## Findings

### Medium

**[CODE-1] stale references**
- Area: \`role-cards.md:438\`
- Severity: Low
- Effort: S
- auto_fixable: true
`;

// E-038-1_1 — NO parseable score in any of the three shapes (score only in prose
// `Overall: 95/100` under `## Summary`, which is NOT a `## Score:` heading nor a
// `**Total**` row nor a frontmatter `overall_score:`). The real AC #17 anchor.
const FX_NOSCORE = `# Audit Report — E-038-1_1

_generated_by: aid-orchestrator:auditor

## Summary

Overall: 95/100 (trend: +1 vs E-037-2_2 which scored 94/100)
`;

// wan R-E027-1 — numeric `blocking_findings: 0` form (→ false / 'numeric').
const FX_NUMERIC_BLOCKING = `_generated_by: aid-orchestrator:auditor

# Auditor Report — EPIC E-027-1_2

## Verdict
overall_score: 90/100
blocking_findings: 0
`;

// ---------------------------------------------------------------------------
// AC1 — the three score shapes + null no-score
// ---------------------------------------------------------------------------

describe("parseOverallScore — three shapes, in order (AC1)", () => {
  it("shape 1: fence-less frontmatter overall_score: 84 → (84, frontmatter)", () => {
    expect(parseOverallScore(FX_FRONTMATTER)).toEqual({
      overallScore: 84,
      scoreSource: "frontmatter",
    });
  });

  it("shape 2: `## Score: 95/100` heading → (95, heading)", () => {
    expect(parseOverallScore(FX_HEADING)).toEqual({
      overallScore: 95,
      scoreSource: "heading",
    });
  });

  it("shape 3: `**Total** **89/100**` table row → (89, table)", () => {
    expect(parseOverallScore(FX_TABLE)).toEqual({
      overallScore: 89,
      scoreSource: "table",
    });
  });

  it("no shape matches (prose-only score) → (null, null)", () => {
    expect(parseOverallScore(FX_NOSCORE)).toEqual({
      overallScore: null,
      scoreSource: null,
    });
  });

  it("shape PRECEDENCE: frontmatter wins over a heading present in the same text", () => {
    const both = `overall_score: 70\n\n## Score: 88/100\n`;
    expect(parseOverallScore(both)).toEqual({
      overallScore: 70,
      scoreSource: "frontmatter",
    });
  });

  it("full no-score summary records a warning and takes the no-score headline branch", () => {
    const s = summaryFor(FX_NOSCORE);
    expect(s.overallScore).toBeNull();
    expect(s.scoreSource).toBeNull();
    expect(s.warnings).toContain(
      "score unparseable - none of the three shapes matched",
    );
    expect(s.headlineCs).toContain("Auditor neuvedl skóre");
  });
});

// ---------------------------------------------------------------------------
// AC2 — six blocking forms; numeric 0 → false; unparseable → null + warning
// ---------------------------------------------------------------------------

describe("parseBlockingFindings — six forms (AC2)", () => {
  it("form 1: bare frontmatter line → false / frontmatter", () => {
    expect(parseBlockingFindings("blocking_findings: false\n")).toEqual({
      blockingFindings: false,
      blockingFindingsSource: "frontmatter",
    });
  });

  it("form 2: heading `## blocking_findings: false` → false / heading", () => {
    expect(parseBlockingFindings("## blocking_findings: false\n")).toEqual({
      blockingFindings: false,
      blockingFindingsSource: "heading",
    });
  });

  it("form 3: bold `**blocking_findings: true**` → true / bold", () => {
    expect(parseBlockingFindings("**blocking_findings: true**\n")).toEqual({
      blockingFindings: true,
      blockingFindingsSource: "bold",
    });
  });

  it("form 4: backtick-wrapped `` `blocking_findings: false` `` → false / bold", () => {
    expect(
      parseBlockingFindings("Text `blocking_findings: false` text\n"),
    ).toEqual({
      blockingFindings: false,
      blockingFindingsSource: "bold",
    });
  });

  it("form 5: inline-in-prose → false / inline", () => {
    expect(
      parseBlockingFindings(
        "Žádné blocking findings nebyly. blocking_findings: false zde.",
      ),
    ).toEqual({ blockingFindings: false, blockingFindingsSource: "inline" });
  });

  it("form 6: numeric 0 → FALSE / numeric (never true)", () => {
    expect(parseBlockingFindings("blocking_findings: 0\n")).toEqual({
      blockingFindings: false,
      blockingFindingsSource: "numeric",
    });
  });

  it("form 6: numeric 2 → true / numeric", () => {
    expect(parseBlockingFindings("blocking_findings: 2\n")).toEqual({
      blockingFindings: true,
      blockingFindingsSource: "numeric",
    });
  });

  it("unparseable → null + null (NEVER assume false, §13.5.6 #2)", () => {
    expect(
      parseBlockingFindings("# Audit Report\n\nNo such field anywhere."),
    ).toEqual({
      blockingFindings: null,
      blockingFindingsSource: null,
    });
  });

  it("unparseable blocking → warning, rendered nezjištěno not false", () => {
    const s = summaryFor("# Audit Report\n\n## Score: 80/100\n\nNothing else.");
    expect(s.blockingFindings).toBeNull();
    expect(s.warnings.some((w) => w.includes("nezjištěno"))).toBe(true);
    // headline must not claim "false" — the clean-score branch is used.
    expect(s.headlineCs).toContain("Skóre 80/100");
  });
});

// ---------------------------------------------------------------------------
// Categories — column-name detection, /25 and /100, Total/Status handling
// ---------------------------------------------------------------------------

describe("parseCategories — column-name detection (§13.5.1)", () => {
  it("/100 table with Status column; Overall row excluded; status captured", () => {
    const cats = parseCategories(FX_FRONTMATTER);
    expect(cats.map((c) => c.category)).toEqual([
      "Code Quality",
      "Security",
      "Documentation",
      "Process",
    ]);
    expect(cats.find((c) => c.category === "Documentation")).toMatchObject({
      score: 72,
      rawScore: "72",
      max: 100,
      status: "WARN",
    });
    // The **Overall** headline row is NOT a category.
    expect(cats.some((c) => /overall|total/i.test(c.category))).toBe(false);
  });

  it("/25 table normalizes to /100 (×4); rawScore keeps the verbatim cell", () => {
    const cats = parseCategories(FX_TABLE);
    expect(cats.find((c) => c.category === "Code")).toMatchObject({
      score: 88, // 22/25 ×4
      rawScore: "22/25",
      max: 25,
      status: null,
    });
    expect(cats.some((c) => c.category === "Total")).toBe(false);
  });

  it("no score table → []", () => {
    expect(parseCategories(FX_HEADING)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Findings — counts, autoFixable, two layouts
// ---------------------------------------------------------------------------

describe("parseFindings — counts + autoFixable + topRisks (§13.5.2 #5)", () => {
  it("layout (b): two Low findings, both auto-fixable", () => {
    const { countsBySeverity, autoFixableCount, topRisks } =
      parseFindings(FX_FRONTMATTER);
    expect(countsBySeverity).toEqual({
      Critical: 0,
      High: 0,
      Medium: 0,
      Low: 2,
    });
    expect(autoFixableCount).toBe(2);
    expect(topRisks).toEqual([]); // clean run → no top risks
  });

  it("layout (a): single Low finding parsed from a `### Medium` block via own field", () => {
    const { countsBySeverity } = parseFindings(FX_TABLE);
    // The finding sits under `### Medium` but its own `Severity: Low` overrides.
    expect(countsBySeverity.Low).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// AC6 — deterministic headlineCs; every branch reachable; NO LLM
// ---------------------------------------------------------------------------

describe("buildHeadlineCs — deterministic, every branch (AC6, §13.5.3)", () => {
  const counts0 = { Critical: 0, High: 0, Medium: 0, Low: 0 };

  it('not present → "auditor zatím neběžel"', () => {
    expect(
      buildHeadlineCs({
        present: false,
        overallScore: null,
        blockingFindings: null,
        countsBySeverity: counts0,
        topReasons: [],
        previousScoreHint: null,
      }),
    ).toBe("Auditor zatím na tomto běhu neběžel.");
  });

  it("no score + blocking finding → merge zablokovaný", () => {
    const h = buildHeadlineCs({
      present: true,
      overallScore: null,
      blockingFindings: true,
      countsBySeverity: counts0,
      topReasons: [],
      previousScoreHint: null,
    });
    expect(h).toContain("blokující nález");
    expect(h).toContain("Skóre auditor neuvedl");
  });

  it('no score + no blocking → honest "neuvedl skóre" with finding count', () => {
    const h = buildHeadlineCs({
      present: true,
      overallScore: null,
      blockingFindings: false,
      countsBySeverity: { Critical: 0, High: 0, Medium: 1, Low: 2 },
      topReasons: [],
      previousScoreHint: null,
    });
    expect(h).toContain("Auditor neuvedl skóre");
    expect(h).toContain("3 nálezy");
  });

  it('has score, clean (no reasons) → "bez blokujících nálezů, jen N drobností"', () => {
    const h = buildHeadlineCs({
      present: true,
      overallScore: 95,
      blockingFindings: false,
      countsBySeverity: { Critical: 0, High: 0, Medium: 0, Low: 1 },
      topReasons: [],
      previousScoreHint: null,
    });
    expect(h).toBe(
      "Skóre 95/100 - bez blokujících nálezů, jen 1 drobnost ke zvážení.",
    );
  });

  it("has score + deductions → names the 1-2 biggest losers (E-046-3_3 worked example shape)", () => {
    const s = summaryFor(FX_FRONTMATTER);
    expect(s.headlineCs).toBe(
      "Skóre 84/100 - strženo hlavně za dokumentaci (72) a proces (80).",
    );
  });

  it("has score + Critical/High → leads with the risk", () => {
    const h = buildHeadlineCs({
      present: true,
      overallScore: 60,
      blockingFindings: true,
      countsBySeverity: { Critical: 1, High: 2, Medium: 0, Low: 0 },
      topReasons: ["bezpečnost (40)"],
      previousScoreHint: null,
    });
    expect(h).toContain("Skóre 60/100, ale 3 kritické/vysoké nálezy");
    expect(h).toContain("Než se mergne");
  });

  it("trend suffix appended only when a different prior score exists", () => {
    const withPrev = buildHeadlineCs({
      present: true,
      overallScore: 84,
      blockingFindings: false,
      countsBySeverity: counts0,
      topReasons: [],
      previousScoreHint: { score: 95, ref: null },
    });
    expect(withPrev).toContain("Oproti minule horší o 11.");
    const noPrev = buildHeadlineCs({
      present: true,
      overallScore: 84,
      blockingFindings: false,
      countsBySeverity: counts0,
      topReasons: [],
      previousScoreHint: { score: 84, ref: null }, // equal → no suffix
    });
    expect(noPrev).not.toContain("Oproti minule");
  });

  it("is a pure function of its inputs (no LLM, no IO) — identical output across calls", () => {
    const input = {
      present: true as const,
      overallScore: 84,
      blockingFindings: false,
      countsBySeverity: counts0,
      topReasons: ["dokumentaci (72)"],
      previousScoreHint: null,
    };
    expect(buildHeadlineCs(input)).toBe(buildHeadlineCs(input));
  });
});

// ---------------------------------------------------------------------------
// Robustness — never throws on malformed / empty / absent report (§13.5.6)
// ---------------------------------------------------------------------------

describe("buildAuditSummary — never throws, always fully shaped (§13.5.6)", () => {
  it("present:false → present:false stub with deterministic headline", () => {
    const s = summaryFor(null, false);
    expect(s.present).toBe(false);
    expect(s.overallScore).toBeNull();
    expect(s.headlineCs).toBe("Auditor zatím na tomto běhu neběžel.");
  });

  it("empty body → present:true no-score stub + warning, no throw", () => {
    const s = summaryFor("   \n  ");
    expect(s.present).toBe(true);
    expect(s.overallScore).toBeNull();
    expect(s.warnings.some((w) => w.includes("unreadable or empty"))).toBe(
      true,
    );
  });

  it("garbage body → no throw, type-valid summary", () => {
    expect(() => summaryFor("@@@ not markdown @@@ ￿")).not.toThrow();
  });

  it("numeric blocking fixture → blocking false / numeric, score 90 / frontmatter", () => {
    const s = summaryFor(FX_NUMERIC_BLOCKING);
    expect(s.blockingFindings).toBe(false);
    expect(s.blockingFindingsSource).toBe("numeric");
    expect(s.overallScore).toBe(90);
    expect(s.scoreSource).toBe("frontmatter");
  });
});

// ---------------------------------------------------------------------------
// REAL-DISK guard — assert the SAME triples against the actual on-disk reports
// when this workspace has them (gitignored; skipped on a fresh clone / CI).
// ---------------------------------------------------------------------------

const HERE = dirname(fileURLToPath(import.meta.url));
const EVIDENCE = join(
  HERE,
  "..",
  "..",
  "..",
  "..",
  ".aid-o",
  "work",
  "evidence",
);

function realReport(rel: string): string | null {
  const p = join(EVIDENCE, rel, "audit-report.md");
  return existsSync(p) ? readFileSync(p, "utf8") : null;
}

describe("REAL on-disk reports — false-green guard (skipped when absent)", () => {
  const real = realReport("E-046-1_3/R-E046-1");
  const present = real !== null;

  it.skipIf(!present)("E-046-1_3 real file → (89, table)", () => {
    expect(parseOverallScore(realReport("E-046-1_3/R-E046-1")!)).toEqual({
      overallScore: 89,
      scoreSource: "table",
    });
  });

  it.skipIf(!present)("E-046-2_3 real file → (95, heading)", () => {
    expect(parseOverallScore(realReport("E-046-2_3/R-E046-2")!)).toEqual({
      overallScore: 95,
      scoreSource: "heading",
    });
  });

  it.skipIf(!present)("E-046-3_3 real file → (84, frontmatter)", () => {
    expect(parseOverallScore(realReport("E-046-3_3/R-E046-3")!)).toEqual({
      overallScore: 84,
      scoreSource: "frontmatter",
    });
  });

  it.skipIf(!present)(
    "E-038-1_1 real file → (null, null) — real no-score (AC #17)",
    () => {
      expect(parseOverallScore(realReport("E-038-1_1/R-E038-1")!)).toEqual({
        overallScore: null,
        scoreSource: null,
      });
    },
  );
});
