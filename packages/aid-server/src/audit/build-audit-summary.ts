/**
 * Per-run structured AUDIT SUMMARY builder (EPIC E-047-4_7, Step 5 — §13.5).
 *
 * Projects the auditor's `audit-report.md` (§4.3) into the managerial
 * {@link AuditSummary} contract — structured, never raw markdown. This is the
 * HIGHEST fixture-only false-green-risk step in Phase 4: real disk carries
 *
 *   - THREE score shapes (§4.3 / §13.5.1), tried in order, null if none:
 *       1. frontmatter `overall_score: N`            → scoreSource 'frontmatter'
 *       2. `## Score: N/100` heading                 → scoreSource 'heading'
 *       3. `**Total** N/100` table row               → scoreSource 'table'
 *     CRITICAL: the real frontmatter form is FENCE-LESS on disk (bare
 *     `overall_score: 84` lines before the H1, NO `---` fences — verified on
 *     E-046-3_3 / E-046-1_3). `gray-matter` returns EMPTY frontmatter for these,
 *     so the score MUST be regex-scanned from the raw text, never trusted from a
 *     parsed-frontmatter object. ~1/4 of real audited runs have NO parseable
 *     score → `overallScore: null` is the NORMAL case, not an edge case.
 *
 *   - SIX `blocking_findings` textual forms (§13.5.1). Numeric `0` → false,
 *     `1`+ → true (`blockingFindingsSource:'numeric'`). When even prose inference
 *     fails → `blockingFindings: null` + warning, rendered "nezjištěno" by the
 *     UI, NEVER "false".
 *
 *   - 50+ distinct per-category table headers → parse by column-name detection,
 *     not fixed position; `/25` and `/100` denominators both occur.
 *
 * Honesty contract (§13.5.6): unparseable score ⇒ no number (null); blocking ⇒
 * null not false; headlineCs is assembled DETERMINISTICALLY from the structured
 * fields (string templates, NO LLM — that is MVP2). A malformed/empty report
 * yields a fully-shaped no-score summary, never a throw.
 */

import type {
  AuditCategoryScore,
  AuditEffort,
  AuditFinding,
  AuditNextStep,
  AuditSeverity,
  AuditSummary,
} from "@aid/contract";

// ---------------------------------------------------------------------------
// Input — the already-parsed report (projection over the scanner cache, SF2)
// ---------------------------------------------------------------------------

/**
 * Input to {@link buildAuditSummary}. `rawText` is the FULL on-disk markdown
 * (frontmatter + body) — deliberately NOT a `gray-matter` parsed object, because
 * the real frontmatter is fence-less and `gray-matter` drops it (see file
 * header). `present:false` ⇒ no `audit-report.md` for this run.
 */
export interface ParsedAuditReport {
  present: boolean;
  rawText: string | null;
  /** relative path to `audit-report.md` for the raw-markdown drawer (§7.4.1). */
  rawRelPath?: string;
}

// ---------------------------------------------------------------------------
// Score parsing — THREE shapes, in order (§4.3 / §13.5.1 / §13.5.2 step 2)
// ---------------------------------------------------------------------------

/** Shape 1: leading/bare or fenced `overall_score: N` (E-046-3_3 → 84). */
const SCORE_FRONTMATTER_RE = /^[ \t]*overall_score[ \t]*:[ \t]*(\d{1,3})\b/im;
/** Shape 2: `## Score: N/100` heading — optional plural `s`, optional `/100`. */
const SCORE_HEADING_RE =
  /^##[ \t]+scores?[ \t]*:[ \t]*(\d{1,3})(?:[ \t]*\/[ \t]*100)?[ \t]*$/im;
/** Shape 3: `**Total** N/100` (or `**Overall**`) table row (E-046-1_3 → 89). */
const SCORE_TOTAL_ROW_RE =
  /\|[ \t]*\*{0,2}(?:total|overall)\*{0,2}[ \t]*\|[ \t]*\*{0,2}[ \t]*(\d{1,3})[ \t]*\/[ \t]*100/i;

export interface OverallScoreResult {
  overallScore: number | null;
  scoreSource: AuditSummary["scoreSource"];
}

/**
 * Parse the overall score by trying the THREE §4.3 shapes IN ORDER (frontmatter
 * → heading → table row); first match wins. `null`/`null` when none match
 * (≈1/4 of real runs). The frontmatter shape is matched against RAW text so the
 * fence-less on-disk form is caught (the §13.5.1 trap).
 */
export function parseOverallScore(text: string): OverallScoreResult {
  const fm = SCORE_FRONTMATTER_RE.exec(text);
  if (fm)
    return {
      overallScore: clampScore(parseInt(fm[1], 10)),
      scoreSource: "frontmatter",
    };

  const heading = SCORE_HEADING_RE.exec(text);
  if (heading)
    return {
      overallScore: clampScore(parseInt(heading[1], 10)),
      scoreSource: "heading",
    };

  const total = SCORE_TOTAL_ROW_RE.exec(text);
  if (total)
    return {
      overallScore: clampScore(parseInt(total[1], 10)),
      scoreSource: "table",
    };

  return { overallScore: null, scoreSource: null };
}

// ---------------------------------------------------------------------------
// Blocking findings — SIX forms (§13.5.1), numeric 0→false, null never assumed
// ---------------------------------------------------------------------------

export interface BlockingFindingsResult {
  blockingFindings: boolean | null;
  blockingFindingsSource: AuditSummary["blockingFindingsSource"];
}

/** Forms 1-5: bare line / heading / bold / backtick-wrapped / inline-in-prose. */
const BLOCKING_BOOL_FRONTMATTER_RE =
  /^[ \t]*blocking_findings[ \t]*:[ \t]*(true|false)\b/im;
const BLOCKING_BOOL_HEADING_RE =
  /^[ \t]*#{1,6}[ \t]*blocking_findings[ \t]*:[ \t]*(true|false)\b/im;
const BLOCKING_BOOL_BOLD_RE =
  /\*\*[ \t]*blocking_findings[ \t]*:[ \t]*(true|false)[ \t]*\*\*/i;
const BLOCKING_BOOL_BACKTICK_RE =
  /`[ \t]*blocking_findings[ \t]*:[ \t]*(true|false)[ \t]*`/i;
/** Form 6: numeric `blocking_findings: 0|1+` (R-E027-1/2) — 0→false, 1+→true. */
const BLOCKING_NUMERIC_RE = /\bblocking_findings[ \t]*:[ \t]*(\d+)\b/i;
/** Inline-in-prose fallback: any `blocking_findings: true|false` anywhere. */
const BLOCKING_INLINE_RE = /\bblocking_findings[ \t]*:[ \t]*(true|false)\b/i;

/**
 * Parse `blocking_findings` from the SIX on-disk forms (§13.5.1) — the ONE field
 * that gates CP5/merge. Forms are tried most-specific first so the `source` is
 * accurate. Numeric `0` → `false` (`source:'numeric'`), `1`+ → `true`. When
 * EVERY form fails → `null` + caller warning — NEVER assume `false` (§13.5.6 #2).
 */
export function parseBlockingFindings(text: string): BlockingFindingsResult {
  // Bold + backtick must be checked before the bare/inline boolean form, because
  // the bare regex would also match inside `**...**` / `` `...` `` wrappers and
  // mislabel the source.
  const bold = BLOCKING_BOOL_BOLD_RE.exec(text);
  if (bold)
    return {
      blockingFindings: toBool(bold[1]),
      blockingFindingsSource: "bold",
    };

  const backtick = BLOCKING_BOOL_BACKTICK_RE.exec(text);
  if (backtick)
    return {
      blockingFindings: toBool(backtick[1]),
      blockingFindingsSource: "bold",
    };

  const heading = BLOCKING_BOOL_HEADING_RE.exec(text);
  if (heading)
    return {
      blockingFindings: toBool(heading[1]),
      blockingFindingsSource: "heading",
    };

  const frontmatter = BLOCKING_BOOL_FRONTMATTER_RE.exec(text);
  if (frontmatter)
    return {
      blockingFindings: toBool(frontmatter[1]),
      blockingFindingsSource: "frontmatter",
    };

  // Numeric form (0→false, 1+→true). Checked before the generic inline boolean
  // so a `blocking_findings: 0` line is classified 'numeric', not skipped.
  const numeric = BLOCKING_NUMERIC_RE.exec(text);
  if (numeric)
    return {
      blockingFindings: parseInt(numeric[1], 10) > 0,
      blockingFindingsSource: "numeric",
    };

  // Inline-in-prose boolean anywhere in the body (not at line start).
  const inline = BLOCKING_INLINE_RE.exec(text);
  if (inline)
    return {
      blockingFindings: toBool(inline[1]),
      blockingFindingsSource: "inline",
    };

  return { blockingFindings: null, blockingFindingsSource: null };
}

function toBool(s: string): boolean {
  return s.toLowerCase() === "true";
}

// ---------------------------------------------------------------------------
// Per-category table — column-name detection, /25 or /100 (§13.5.1 / §13.5.2 #4)
// ---------------------------------------------------------------------------

/**
 * Parse the per-category score table by COLUMN-NAME detection (50+ header
 * variants observed; never fixed position — §13.5.1). The score column is the
 * first header matching `Score`; the category column the first matching
 * `Category|Dimension|Area`; an optional `Status` column is captured when
 * present. `score` is normalized to /100 (a `/25` cell ×4); `rawScore` keeps the
 * verbatim cell; `max` records the detected denominator. The `**Total**` /
 * `**Overall**` headline row is excluded. Returns `[]` for a report with no
 * recognizable score table.
 */
export function parseCategories(text: string): AuditCategoryScore[] {
  const block = isolateScoreTableBlock(text);
  if (block === null) return [];

  const lines = block.split("\n").filter((l) => l.includes("|"));
  if (lines.length < 2) return [];

  // Header row = first row that names a Category-like AND a Score-like column.
  let headerIdx = -1;
  let headers: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const cells = splitRow(lines[i]);
    const lc = cells.map((c) => c.toLowerCase());
    const hasCat = lc.some((c) => /\b(category|dimension|area)\b/.test(c));
    const hasScore = lc.some((c) => /\bscore\b/.test(c));
    if (hasCat && hasScore) {
      headerIdx = i;
      headers = lc;
      break;
    }
  }
  if (headerIdx === -1) return [];

  const catCol = headers.findIndex((c) =>
    /\b(category|dimension|area)\b/.test(c),
  );
  const scoreCol = headers.findIndex((c) => /\bscore\b/.test(c));
  const statusCol = headers.findIndex((c) => /\bstatus\b/.test(c));
  if (catCol === -1 || scoreCol === -1) return [];

  const out: AuditCategoryScore[] = [];
  for (let i = headerIdx + 1; i < lines.length; i++) {
    const cells = splitRow(lines[i]);
    if (cells.length <= Math.max(catCol, scoreCol)) continue;
    // Skip the markdown header separator row (`|---|---|`).
    if (cells.every((c) => /^:?-+:?$/.test(c.trim()) || c.trim() === ""))
      continue;

    const category = stripMarkup(cells[catCol]);
    const lower = category.toLowerCase();
    if (lower === "" || /^-+$/.test(category)) continue;
    if (lower === "total" || lower === "overall") continue; // headline, not a category

    const cell = stripMarkup(cells[scoreCol]);
    const sm = cell.match(/(\d{1,3})(?:[ \t]*\/[ \t]*(\d{1,3}))?/);
    if (!sm) continue;
    const rawNum = parseInt(sm[1], 10);
    const denom = sm[2] ? parseInt(sm[2], 10) : 100;
    const max: 25 | 100 = denom === 25 ? 25 : 100;
    const normalized = max === 25 ? rawNum * 4 : rawNum;

    out.push({
      category,
      score: clampScore(normalized) ?? 0,
      rawScore: cell,
      max,
      status:
        statusCol !== -1 && cells[statusCol]
          ? stripMarkup(cells[statusCol]) || null
          : null,
    });
  }
  return out;
}

/**
 * Isolate the table body under a `## Score` / `## Scores` / `## Score Overview` /
 * `## Scores by Dimension` heading: from that heading to the next `## ` heading
 * or `---` rule. Returns `null` when no score heading exists.
 */
function isolateScoreTableBlock(text: string): string | null {
  const headingMatch = /^##[ \t]+scores?\b.*$/im.exec(text);
  if (!headingMatch) return null;
  const after = text.slice(headingMatch.index + headingMatch[0].length);
  const stop = after.search(/\n##[ \t]|\n-{3,}/);
  return stop === -1 ? after : after.slice(0, stop);
}

function splitRow(line: string): string[] {
  // Drop the leading/trailing pipe, then split. Keeps interior empties.
  const trimmed = line.trim().replace(/^\|/, "").replace(/\|$/, "");
  return trimmed.split("|").map((c) => c.trim());
}

function stripMarkup(s: string): string {
  return s.replace(/[*`]/g, "").trim();
}

// ---------------------------------------------------------------------------
// Findings → counts + topRisks + autoFixableCount (§13.5.2 #5; two layouts)
// ---------------------------------------------------------------------------

interface FindingsResult {
  findings: AuditFinding[];
  topRisks: AuditFinding[];
  countsBySeverity: AuditSummary["countsBySeverity"];
  autoFixableCount: number;
}

const SEVERITY_ORDER: Record<AuditSeverity, number> = {
  Critical: 4,
  High: 3,
  Medium: 2,
  Low: 1,
};

/**
 * Parse findings from the TWO on-disk layouts (§13.5.1):
 *   (a) `### Critical|High|Medium|Low` section headers with `**[ID] title**`
 *       markers and `Severity:`/`Effort:`/`auto_fixable:` fields underneath
 *       (E-046-2_3, E-046-1_3); or
 *   (b) inline `- Severity: Low` lines under a `### <Category>` heading
 *       (E-046-3_3).
 *
 * Each finding's own `Severity:` field, when present, OVERRIDES the section
 * heading (E-046-1_3 has a finding under `### Medium` whose own field says
 * `Severity: Low`). `effort` is normalized to `S|M|L`; a missing `auto_fixable`
 * stays `null` (distinct from explicit `false`).
 */
export function parseFindings(text: string): FindingsResult {
  const counts = { Critical: 0, High: 0, Medium: 0, Low: 0 };
  const findings: AuditFinding[] = [];

  // Collect every `###` heading with its byte offset; the severity of a block is
  // the heading's own severity word when it IS one, else inherited from context.
  const blocks = splitByH3(text);
  for (const b of blocks) {
    const sectionSev = severityFromHeading(b.heading);

    // Layout (a): bold finding markers within the block.
    const markers = matchAll(
      b.body,
      /^[ \t]*\*\*\[?[^\n*\]]*\]?[^\n]*\*\*[ \t]*$/gim,
    );
    if (markers.length > 0 && sectionSev) {
      // Slice the block per marker so each marker's own fields are scoped.
      const segs = sliceByMarkers(
        b.body,
        /^[ \t]*\*\*\[?[^\n*\]]*\]?[^\n]*\*\*[ \t]*$/gim,
      );
      for (const seg of segs) {
        const own = severityFromField(seg.text);
        const sev = own ?? sectionSev;
        findings.push(buildFinding(sev, stripMarkup(seg.marker), seg.text));
      }
      continue;
    }

    // Layout (b): inline `- Severity: X` lines under a `### <Category>` heading.
    const inlineSev = matchAll(
      b.body,
      /^[ \t]*-?[ \t]*severity[ \t]*:[ \t]*(critical|high|medium|low)\b/gim,
    );
    if (inlineSev.length > 0) {
      // Split the block into finding records on the `**A8 — ...**` / blank-line
      // boundaries; each record carries its own Severity/Effort/auto_fixable.
      const recs = splitInlineFindings(b.body);
      for (const rec of recs) {
        const sev = severityFromField(rec);
        if (!sev) continue;
        findings.push(buildFinding(sev, firstNonEmptyLine(rec), rec));
      }
      continue;
    }
  }

  for (const f of findings) {
    counts[f.severity] += 1;
  }
  const autoFixableCount = findings.filter(
    (f) => f.autoFixable === true,
  ).length;
  const topRisks = findings
    .filter((f) => f.severity === "Critical" || f.severity === "High")
    .sort((a, b) => SEVERITY_ORDER[b.severity] - SEVERITY_ORDER[a.severity]);

  return { findings, topRisks, countsBySeverity: counts, autoFixableCount };
}

function buildFinding(
  severity: AuditSeverity,
  label: string,
  body: string,
): AuditFinding {
  return {
    severity,
    area: extractField(
      body,
      /(?:^|\n)[ \t]*-?[ \t]*(?:\*\*)?area(?:\*\*)?[ \t]*:[ \t]*`?([^\n`]+)`?/i,
    ),
    auditType: extractField(
      body,
      /(?:^|\n)[ \t]*-?[ \t]*(?:\*\*)?audit_type(?:\*\*)?[ \t]*:[ \t]*([^\n]+)/i,
    ),
    finding: label.slice(0, 300),
    recommendation: extractField(
      body,
      /(?:^|\n)[ \t]*-?[ \t]*(?:\*\*)?recommendation(?:\*\*)?[ \t]*:[ \t]*([^\n]+)/i,
    ),
    effort: normalizeEffort(
      extractField(
        body,
        /(?:^|\n)[ \t]*-?[ \t]*(?:\*\*)?effort(?:\*\*)?[ \t]*:[ \t]*([^\n]+)/i,
      ),
    ),
    autoFixable: parseAutoFixable(body),
  };
}

function splitByH3(text: string): { heading: string; body: string }[] {
  const re = /^###[ \t]+([^\n]+)$/gim;
  const heads: { heading: string; index: number; end: number }[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    heads.push({
      heading: m[1].trim(),
      index: m.index,
      end: m.index + m[0].length,
    });
  }
  return heads.map((h, i) => ({
    heading: h.heading,
    body: text.slice(
      h.end,
      i + 1 < heads.length ? heads[i + 1].index : findSectionEnd(text, h.end),
    ),
  }));
}

/** Stop a `###` block at the next `## ` (h2) heading or end of text. */
function findSectionEnd(text: string, from: number): number {
  const rest = text.slice(from);
  const next = rest.search(/\n##[ \t]/);
  return next === -1 ? text.length : from + next;
}

function severityFromHeading(heading: string): AuditSeverity | null {
  const lc = heading.toLowerCase();
  if (/^critical\b/.test(lc)) return "Critical";
  if (/^high\b/.test(lc)) return "High";
  if (/^medium\b/.test(lc)) return "Medium";
  if (/^low\b/.test(lc)) return "Low";
  return null;
}

function severityFromField(body: string): AuditSeverity | null {
  const m =
    /(?:^|\n)[ \t]*-?[ \t]*(?:\*\*)?severity(?:\*\*)?[ \t]*:[ \t]*(critical|high|medium|low)\b/i.exec(
      body,
    );
  if (!m) return null;
  const w = m[1].toLowerCase();
  return (w[0].toUpperCase() + w.slice(1)) as AuditSeverity;
}

function sliceByMarkers(
  body: string,
  re: RegExp,
): { marker: string; text: string }[] {
  const markers: { marker: string; index: number; end: number }[] = [];
  let m: RegExpExecArray | null;
  const g = new RegExp(
    re.source,
    re.flags.includes("g") ? re.flags : re.flags + "g",
  );
  while ((m = g.exec(body)) !== null) {
    markers.push({
      marker: m[0].trim(),
      index: m.index,
      end: m.index + m[0].length,
    });
  }
  return markers.map((mk, i) => ({
    marker: mk.marker,
    text: body.slice(
      mk.end,
      i + 1 < markers.length ? markers[i + 1].index : body.length,
    ),
  }));
}

/**
 * Split a layout-(b) block (E-046-3_3) into per-finding records. Findings begin
 * at a `**...**` bold marker line; everything until the next such line is one
 * record. Falls back to the whole block when there are no bold markers.
 */
function splitInlineFindings(body: string): string[] {
  const segs = sliceByMarkers(body, /^[ \t]*\*\*[^\n]+\*\*[ \t]*$/gim);
  if (segs.length === 0) return [body];
  return segs.map((s) => `${s.marker}\n${s.text}`);
}

function firstNonEmptyLine(rec: string): string {
  for (const line of rec.split("\n")) {
    const t = stripMarkup(line);
    if (t) return t.slice(0, 300);
  }
  return "";
}

function extractField(body: string, re: RegExp): string | null {
  const m = re.exec(body);
  return m ? m[1].trim() : null;
}

function normalizeEffort(raw: string | null): AuditEffort {
  if (!raw) return null;
  const lc = raw.trim().toLowerCase();
  if (lc === "s" || lc.startsWith("small")) return "S";
  if (lc === "m" || lc.startsWith("medium")) return "M";
  if (lc === "l" || lc.startsWith("large")) return "L";
  return null;
}

function parseAutoFixable(body: string): boolean | null {
  const m =
    /(?:^|\n)[ \t]*-?[ \t]*(?:\*\*)?auto_fixable(?:\*\*)?[ \t]*:[ \t]*(true|false)\b/i.exec(
      body,
    );
  if (!m) return null;
  return m[1].toLowerCase() === "true";
}

function matchAll(text: string, re: RegExp): RegExpMatchArray[] {
  return [...text.matchAll(re)];
}

// ---------------------------------------------------------------------------
// topReasons + nextSteps + previousScoreHint (§13.5.2 #6/#7/#9)
// ---------------------------------------------------------------------------

/**
 * Derive `topReasons` deterministically — WHY the score is what it is (§13.5.2
 * #6). Prefers the lowest-scoring categories (they dragged the score) and the
 * highest-severity findings; each reason is a short Czech clause naming the
 * category/severity. Falls back to a finding-count clause when no categories.
 */
export function buildTopReasons(
  categories: AuditCategoryScore[],
  counts: AuditSummary["countsBySeverity"],
): string[] {
  const reasons: string[] = [];

  // Lowest-scoring categories first (only those below a clean 100).
  const losers = categories
    .filter((c) => c.score < 100)
    .sort((a, b) => a.score - b.score)
    .slice(0, 2);
  for (const c of losers) {
    reasons.push(`${czCategory(c.category)} (${c.rawScore})`);
  }

  if (counts.Critical > 0) {
    reasons.push(`${counts.Critical} kritických nálezů`);
  }
  if (counts.High > 0) {
    reasons.push(`${counts.High} vysokých nálezů`);
  }
  return reasons;
}

/**
 * Build `nextSteps` from each finding, ranked by severity-weight ×
 * effort-cheapness (§13.5.2 #7): Critical=4…Low=1; S=3,M=2,L=1 → highest product
 * floats up, so "high-severity & cheap" is first. Auto-fixable items are tagged.
 */
export function buildNextSteps(findings: AuditFinding[]): AuditNextStep[] {
  const steps = findings.map((f) => ({
    finding: f.recommendation ?? f.finding,
    severity: f.severity,
    effort: f.effort,
    autoFixable: f.autoFixable,
    rank: SEVERITY_ORDER[f.severity] * effortCheapness(f.effort),
  }));
  steps.sort((a, b) => b.rank - a.rank);
  return steps;
}

function effortCheapness(e: AuditEffort): number {
  if (e === "S") return 3;
  if (e === "M") return 2;
  if (e === "L") return 1;
  return 2; // unknown effort → middle weight, never 0 (would zero the rank)
}

const PREVIOUS_SCORE_RE =
  /previous audit[^\n]*?(?:score|overall)[ \t]*:?[ \t]*(\d{1,3})[ \t]*\/[ \t]*100/i;

/** Capture the auditor's own `Previous audit … Score: N/100` self-report. */
export function parsePreviousScoreHint(
  text: string,
): AuditSummary["previousScoreHint"] {
  const m = PREVIOUS_SCORE_RE.exec(text);
  if (!m) return null;
  return { score: clampScore(parseInt(m[1], 10)), ref: null };
}

// ---------------------------------------------------------------------------
// Deterministic Czech headline (§13.5.3) — assembled, NEVER generated (no LLM)
// ---------------------------------------------------------------------------

/**
 * Assemble the deterministic `headlineCs` from the structured fields by string
 * templates (§13.5.3) — NO LLM. Every branch is reachable from `present` /
 * `overallScore` / `blockingFindings` / `countsBySeverity` alone, all of which
 * are populated (or explicitly null) by {@link buildAuditSummary}. Always safe
 * to render. Tone: lidská řeč, krátká pomlčka " - " (§6 dictionary).
 */
export function buildHeadlineCs(
  summary: Pick<
    AuditSummary,
    | "present"
    | "overallScore"
    | "blockingFindings"
    | "countsBySeverity"
    | "topReasons"
    | "previousScoreHint"
  >,
): string {
  if (!summary.present) {
    return "Auditor zatím na tomto běhu neběžel.";
  }

  const counts = summary.countsBySeverity;
  const totalFindings =
    counts.Critical + counts.High + counts.Medium + counts.Low;
  const minor = counts.Medium + counts.Low;
  const topRiskCount = counts.Critical + counts.High;

  // --- No score branches ---
  if (summary.overallScore === null) {
    if (summary.blockingFindings === true) {
      return "Auditor našel blokující nález - merge je zablokovaný, dokud to PM neposoudí. (Skóre auditor neuvedl.)";
    }
    return `Auditor neuvedl skóre, ale nenašel blokující nález (${totalFindings} ${czFindings(totalFindings)} celkem).`;
  }

  // --- Has score branches ---
  const n = summary.overallScore;
  let headline: string;
  if (topRiskCount > 0) {
    headline = `Skóre ${n}/100, ale ${topRiskCount} ${czCriticalHigh(topRiskCount)} - ${worstArea(summary.topReasons)}. Než se mergne, koukni na ně.`;
  } else if (summary.topReasons.length > 0) {
    const r1 = summary.topReasons[0];
    const r2 = summary.topReasons[1];
    headline = r2
      ? `Skóre ${n}/100 - strženo hlavně za ${r1} a ${r2}.`
      : `Skóre ${n}/100 - strženo hlavně za ${r1}.`;
  } else {
    headline = `Skóre ${n}/100 - bez blokujících nálezů, jen ${minor} ${czMinor(minor)} ke zvážení.`;
  }

  // --- Optional trend suffix ---
  const prev = summary.previousScoreHint?.score;
  if (typeof prev === "number" && prev !== n) {
    const delta = n - prev;
    const dir = delta > 0 ? "lepší" : "horší";
    headline += ` Oproti minule ${dir} o ${Math.abs(delta)}.`;
  }

  return headline;
}

// ---------------------------------------------------------------------------
// Czech micro-helpers (deterministic; declension + category translation)
// ---------------------------------------------------------------------------

function czFindings(n: number): string {
  if (n === 1) return "nález";
  if (n >= 2 && n <= 4) return "nálezy";
  return "nálezů";
}

function czMinor(n: number): string {
  if (n === 1) return "drobnost";
  if (n >= 2 && n <= 4) return "drobnosti";
  return "drobností";
}

function czCriticalHigh(n: number): string {
  if (n === 1) return "kritický/vysoký nález";
  if (n >= 2 && n <= 4) return "kritické/vysoké nálezy";
  return "kritických/vysokých nálezů";
}

function worstArea(topReasons: string[]): string {
  return topReasons.length > 0 ? topReasons[0] : "viz nálezy";
}

const CATEGORY_CS: Record<string, string> = {
  "code quality": "kvalitu kódu",
  code: "kód",
  security: "bezpečnost",
  documentation: "dokumentaci",
  docs: "dokumentaci",
  process: "proces",
  frontend: "frontend",
  database: "databázi",
  standards: "standardy",
  memory: "paměť",
};

function czCategory(category: string): string {
  return CATEGORY_CS[category.toLowerCase()] ?? category.toLowerCase();
}

// ---------------------------------------------------------------------------
// Top-level builder (§13.5.2 — the 10-step per-run derivation)
// ---------------------------------------------------------------------------

function clampScore(n: number): number | null {
  if (Number.isNaN(n)) return null;
  return Math.max(0, Math.min(100, n));
}

/**
 * The empty/no-score `AuditSummary` — fully type-shaped, never throws (§13.5.6).
 * `present` and `warnings` vary; `headlineCs` is filled deterministically.
 */
function shapedEmpty(
  present: boolean,
  rawRelPath: string,
  warnings: string[],
): AuditSummary {
  const base: AuditSummary = {
    present,
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
    rawRelPath,
    warnings,
  };
  base.headlineCs = buildHeadlineCs(base);
  return base;
}

/**
 * Build the per-run {@link AuditSummary} from a run's parsed `audit-report.md`
 * (§13.5.2 — the 10-step derivation). Pure projection over already-parsed
 * content; no new source of truth, no writes (SF2). NEVER throws on a partial /
 * malformed / empty report — it degrades to a fully-shaped no-score summary.
 *
 * @param runDir   the run's evidence dir (provenance only; reads use `parsed`)
 * @param parsed   the parsed `audit-report.md` (`present` + raw text)
 */
export function buildAuditSummary(
  runDir: string,
  parsed: ParsedAuditReport,
): AuditSummary {
  void runDir; // provenance arg (signature parity §13.5); reads go through `parsed`
  const rawRelPath = parsed.rawRelPath ?? "audit-report.md";

  // (1) present
  if (!parsed.present) {
    return shapedEmpty(false, rawRelPath, ["no audit-report.md for this run"]);
  }
  const text = parsed.rawText;
  if (text === null || text.trim().length === 0) {
    return shapedEmpty(true, rawRelPath, [
      "audit-report.md unreadable or empty",
    ]);
  }

  const warnings: string[] = [];

  // (2) overallScore + scoreSource — three shapes, in order
  const { overallScore, scoreSource } = parseOverallScore(text);
  if (overallScore === null) {
    warnings.push("score unparseable - none of the three shapes matched");
  }

  // (3) blockingFindings + source — six forms; null never assumed false
  const { blockingFindings, blockingFindingsSource } =
    parseBlockingFindings(text);
  if (blockingFindings === null) {
    warnings.push(
      "blocking_findings inferred from prose failed - reported as null (nezjištěno)",
    );
  }

  // (4) categories — column-name-detected table parse
  const categories = parseCategories(text);

  // (5) findings → counts + topRisks + autoFixableCount
  const { findings, topRisks, countsBySeverity, autoFixableCount } =
    parseFindings(text);

  // (6) topReasons — deterministic, from largest deductions / severities
  const topReasons = buildTopReasons(categories, countsBySeverity);

  // (7) nextSteps — severity × effort-cheapness rank
  const nextSteps = buildNextSteps(findings);

  // (9) previousScoreHint — auditor self-report
  const previousScoreHint = parsePreviousScoreHint(text);

  const summary: AuditSummary = {
    present: true,
    overallScore,
    scoreSource,
    blockingFindings,
    blockingFindingsSource,
    categories,
    topReasons,
    topRisks,
    countsBySeverity,
    autoFixableCount,
    nextSteps,
    headlineCs: "",
    previousScoreHint,
    rawRelPath,
    warnings,
  };

  // (3 / §13.5.3) headlineCs — DETERMINISTIC, assembled from the fields above
  summary.headlineCs = buildHeadlineCs(summary);
  return summary;
}
