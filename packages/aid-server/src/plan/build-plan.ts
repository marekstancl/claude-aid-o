/**
 * PLAN as a first-class entity — `buildPlan` projection (EPIC E-047-4_7, Step 7 —
 * §13.6 / §5.4 / §5.5 / §5.1 / SF4 / MF6).
 *
 * Pure, never-throw projection over already-parsed EPIC/run data (no new disk
 * reads inside the builders themselves — the route does the I/O and feeds the
 * already-built per-EPIC member structs; SF2). The builders here own:
 *
 *  - {@link resolveMembership} — the §13.6 FOUR-TIER precedence per EPIC:
 *      tier-1 `plan_path` (latest run's fsm-state) → tier-2 frontmatter
 *      `plan_ref` → tier-3 id-derived (`E-{NNN}` → `P{NNN}`) → tier-4 orphan.
 *      A candidate planId resolved by ANY tier is a real member ONLY when a
 *      matching `plans/P{NNN}-*.md` file EXISTS; otherwise the EPIC degrades to
 *      orphan (tier-4) — never a phantom plan / broken screen. So E-041
 *      (`plan_ref` → P041, but NO `P041-*.md` on disk) correctly resolves to
 *      orphan, while P046's three null-`plan_path` members resolve at tier-2
 *      (`E-046-3_3` active task carries `plan_ref`) + tier-3 (`E-046-1_3`/
 *      `E-046-2_3`, surfaced via `work/evidence/` only — their `plan_ref` task
 *      files live under `tasks/archive/` which §5.2 excludes from the scan).
 *
 *  - {@link buildPlanSummary} / {@link buildPlanDetail} — the list-row and full
 *    Plan-screen read-models, rolling up progress / AC% per §5.4/§5.5
 *    (`acPct:null` → "N/A — fast mode", NEVER 0%), `plan_duration_sec` per §5.1.
 *
 *  - {@link buildReporterDelivery} / {@link buildSimplifierSummary} — the MF6
 *    plan-boundary role projections, with existence-checked `_test_evidence[]`
 *    (a cited file missing on disk → `exists:false` + a warning, never dropped).
 *
 * Honesty posture (flag-never-fake): missing signals become `null` / `[]` +
 * warnings; an id-derived ('derived') member carries a warning so the weaker
 * grouping is visible; degradations land in `PlanDetail.warnings`. Never throws.
 *
 * Module: src/plan/build-plan.ts
 */

import type {
  AuditSummary,
  AuditTrend,
  BacklogItem,
  DeliveryOutcome,
  EpicSummary,
  LessonEntry,
  LessonsView,
  MembershipSource,
  PlanDetail,
  PlanSummary,
  ReporterDelivery,
  ReporterTestEvidence,
  SimplifierDisposition,
  SimplifierProposal,
  SimplifierSummary,
} from '@aid/contract';
import type { AggregateAudit } from '../audit/build-aggregate-audit.js';

// ===========================================================================
// Membership resolution (§13.6 four-tier precedence)
// ===========================================================================

/** The four membership tiers + the planId each candidate resolves to. */
export interface MembershipResult {
  /** Which tier fired (`'orphan'` when nothing resolves to a real plan file). */
  source: MembershipSource;
  /** The plan NUMBER (`P{NNN}`) the EPIC resolves to, or null when orphan. */
  planNumber: string | null;
  /**
   * The SPECIFIC plan STEM this EPIC resolves to (e.g. `P022-b-foo`) when the
   * firing source was a stem-bearing plan_path/plan_ref whose stem exists.
   * null for number-only refs and id-derived membership — the caller MUST NOT
   * assign those to a stem when the number is ambiguous (PM #1: stem identity is
   * preserved, never collapsed to number→first-stem).
   */
  resolvedStem: string | null;
}

/**
 * The minimal per-EPIC signal the membership resolver needs (the route extracts
 * these from the Tier-1 index + the latest-run RunDetail). Keeping it a plain
 * struct keeps {@link resolveMembership} a PURE function (no scanner coupling).
 */
export interface MembershipInput {
  epicId: string;
  /** Latest run's fsm-state `plan_path` (tier-1), null when absent/`null` on disk. */
  planPath: string | null;
  /** EPIC task-file frontmatter `plan_ref` / `plan_path` (tier-2), null when absent. */
  planRef: string | null;
}

/**
 * Resolve ONE EPIC's plan membership by the §13.6 four-tier precedence. Returns
 * the firing tier and the `P{NNN}` plan number — but ONLY when a matching plan
 * file exists (per {@link planFileExists}); otherwise the EPIC is `'orphan'`.
 *
 * Precedence (first that resolves to a REAL plan file wins):
 *   1. `plan_path`  — the latest run's fsm-state plan_path (authoritative).
 *   2. `plan_ref`   — the task frontmatter plan_ref stem (authoritative).
 *   3. id-derived   — `E-{NNN}` → `P{NNN}` (official but WEAKER — caller warns).
 *   4. orphan       — none of the above maps to an existing plan file.
 *
 * @param planFileExists predicate: does a `plans/P{NNN}-*.md` (or `P{NNN}.md`)
 *   file exist for this plan number? The caller supplies it from the Tier-1
 *   plan index so the resolver stays pure.
 */
export function resolveMembership(
  input: MembershipInput,
  planFileExists: (planNumber: string) => boolean,
  stemFileExists: (planStem: string) => boolean = () => false,
): MembershipResult {
  // Tier-1: fsm-state plan_path. PREFER the explicit STEM when the ref carries
  // one and that stem exists on disk (PM #1: `plan_path → P022-b` must resolve
  // to P022-b, never collapse to P022 → first stem). Fall back to number-level
  // when the ref is number-only or the stem is unknown.
  const pathStem = planStemFrom(input.planPath);
  if (pathStem !== null && stemFileExists(pathStem)) {
    return { source: 'plan_path', planNumber: planNumberPrefix(pathStem), resolvedStem: pathStem };
  }
  const fromPlanPath = planNumberFrom(input.planPath);
  if (fromPlanPath !== null && planFileExists(fromPlanPath)) {
    return { source: 'plan_path', planNumber: fromPlanPath, resolvedStem: null };
  }

  // Tier-2: frontmatter plan_ref → stem-first, then number.
  const refStem = planStemFrom(input.planRef);
  if (refStem !== null && stemFileExists(refStem)) {
    return { source: 'plan_ref', planNumber: planNumberPrefix(refStem), resolvedStem: refStem };
  }
  const fromPlanRef = planNumberFrom(input.planRef);
  if (fromPlanRef !== null && planFileExists(fromPlanRef)) {
    return { source: 'plan_ref', planNumber: fromPlanRef, resolvedStem: null };
  }

  // Tier-3: id-derived E-{NNN} → P{NNN}, only when a real plan file exists.
  // Number-only by construction → resolvedStem null (caller must NOT assign to a
  // stem when the number is ambiguous).
  const derived = idDerivedPlanNumber(input.epicId);
  if (derived !== null && planFileExists(derived)) {
    return { source: 'derived', planNumber: derived, resolvedStem: null };
  }

  // Tier-4: orphan (no plan_path, no plan_ref, no matching P{NNN} file). Note:
  // a plan_ref/derived that points at a NON-EXISTENT plan file (e.g. E-041 →
  // P041 with no P041-*.md) lands here, NOT at tier-2/3 — §13.6 "degrades to
  // orphan, never to a broken Plan screen".
  return { source: 'orphan', planNumber: null, resolvedStem: null };
}

/**
 * Extract the full plan STEM from a plan_path / plan_ref string, when one is
 * present. `.aid-o/plans/P022-b-foo.md` → `P022-b-foo`; bare stem `P022-b-foo`
 * → `P022-b-foo`. Returns null for a number-only ref (`P022` / `P022.md`) — a
 * bare number carries no stem identity, so the caller resolves it via the number
 * (and treats it as ambiguous when several stems share that number).
 */
export function planStemFrom(ref: string | null): string | null {
  if (ref === null) return null;
  // Take the basename (drop any directory + .md extension), then require it to
  // be a real stem: P{digits} followed by a `-` and at least one more char.
  const base = ref.split('/').pop()!.replace(/\.md$/i, '');
  return /^P\d+-.+/i.test(base) ? base : null;
}

/**
 * Extract the `P{NNN}` plan number from a plan_path / plan_ref string. Accepts a
 * full path (`.aid-o/plans/P046-foo.md`), a bare stem (`P046-foo`), or just the
 * number (`P046`). Returns null when no `P{digits}` token is present (covers the
 * literal `null` plan_path on disk).
 */
export function planNumberFrom(ref: string | null): string | null {
  if (ref === null) return null;
  const m = ref.match(/P(\d+)/i);
  return m ? `P${m[1]}` : null;
}

/** Derive the plan number from an EPIC id: `E-046-3_3` → `P046` (tier-3). */
export function idDerivedPlanNumber(epicId: string): string | null {
  const m = epicId.match(/^E-?(\d+)/i);
  return m ? `P${m[1]}` : null;
}

/** Extract the leading plan number from a plan id / stem: `P046-foo` → `P046`. */
export function planNumberPrefix(planId: string): string | null {
  const m = planId.match(/^(P\d+)/i);
  return m ? m[1] : null;
}

// ===========================================================================
// Plan member assembly inputs (the route fills these from the scanner cache)
// ===========================================================================

/** One member EPIC's already-built read shapes + its membership tier. */
export interface PlanMemberInput {
  epicId: string;
  membershipSource: MembershipSource; // 'plan_path' | 'plan_ref' | 'derived'
  /** The EPIC's status-weighted {@link EpicSummary} (already built, §5.4). */
  summary: EpicSummary;
  /** The EPIC value = its LATEST run (§5.4 run→EPIC = latest-run rule). */
  latestRun: {
    runId: string;
    state: string | null;
    startedAtMs: number | null;
    /** terminal-marker mtime (epoch ms) for plan_duration_sec end bound. */
    lastActivityMs: number | null;
  } | null;
  /** AC counters from this EPIC's latest run's plan-diff.json (§5.5). */
  ac: { present: number; total: number } | null;
}

/** The full input the route assembles for a single plan (tiers 1-3 members). */
export interface PlanBuildInput {
  projectId: string;
  /** The plan-file stem (e.g. "P046-plan-boundary-…"). */
  planId: string;
  title: string;
  planRef: string; // the plan .md path
  /** Plan body description (first prose block), null when unparseable. */
  description: string | null;
  /** tier-1-to-3 members only (orphans are NOT here). */
  members: PlanMemberInput[];
  /** tier-4 orphan EPICs count (§13.6). */
  orphanEpicCount: number;
  /** plan-scope audit trend (already built; one point per audited member EPIC). */
  auditTrend: AuditTrend;
  /** All lesson entries from the project's lessons-learned.md (route reads once). */
  allLessons: LessonEntry[];
  /** boundaryAudit = latest audited run of the plan's LAST EPIC (§13.5.7). */
  boundaryAudit: AuditSummary;
  /** aggregateAudit = median-EPIC summary across audited members (SF4). */
  aggregateAudit: AggregateAudit;
  /** plan-boundary Reporter delivery (already projected, MF6). */
  deliveryReport: ReporterDelivery;
  /** plan-boundary Simplifier proposals (already projected, MF6). */
  simplifierSummary: SimplifierSummary;
  /** current backlog rows scoped to the plan's EPICs + absolute counts (MF2). */
  backlog: { items: BacklogItem[]; openCount: number; closedCount: number; warnings: string[] };
}

// ===========================================================================
// PlanSummary (list-row / brief scope)
// ===========================================================================

/** Max lessonsPreview entries surfaced in the thin list-row shape. */
const LESSONS_PREVIEW_MAX = 3;

/**
 * Build the list-row {@link PlanSummary} from the assembled member set. Rolls up
 * progress (`done_epics/total_epics*100`, §5.5) and AC% (`Σpresent/Σac_count`,
 * §5.5; `null` when NO member measured ACs — "N/A — fast mode", never 0%).
 */
export function buildPlanSummary(input: PlanBuildInput): PlanSummary {
  const epicsTotal = input.members.length;
  const epicsDone = input.members.filter(
    (m) => m.latestRun?.state === 'DONE',
  ).length;
  const progressPct =
    epicsTotal > 0 ? Math.round((epicsDone / epicsTotal) * 100) : 0;

  const acPct = rollupAcPct(input.members);

  const epicMembers = input.members
    .map((m) => ({ epicId: m.epicId, membershipSource: m.membershipSource }))
    .sort((a, b) => a.epicId.localeCompare(b.epicId));

  const membershipMixed =
    new Set(epicMembers.map((m) => m.membershipSource)).size > 1;

  const lessons = filterLessons(input.allLessons, input.members);
  const lessonsPreview = lessons
    .slice(0, LESSONS_PREVIEW_MAX)
    .map((l) => ({ date: l.date, lesson: l.lesson, epicId: l.epicId }));

  return {
    projectId: input.projectId,
    // STEM is the primary identity (PM #1); input.planId is already the stem.
    planId: input.planId,
    title: input.title,
    planRef: input.planRef,
    epicIds: epicMembers.map((m) => m.epicId),
    epicMembers,
    membershipMixed,
    epicsTotal,
    epicsDone,
    progressPct,
    acPct,
    lessonsPreview,
    auditTrend: input.auditTrend,
    lastActivityAt: rollupLastActivity(input.members),
  };
}

// ===========================================================================
// PlanDetail (full Plan screen)
// ===========================================================================

/**
 * Build the full {@link PlanDetail} (extends {@link PlanSummary}). Adds the
 * member EPIC list (status-weighted, §5.4), orphan count, `plan_duration_sec`
 * (§5.1), the two distinct audit metrics (boundary vs aggregate, SF4), the MF6
 * delivery / simplifier projections, current backlog rows (MF2), and the full
 * `LessonsView`. Aggregation degradations land in `warnings`.
 */
export function buildPlanDetail(input: PlanBuildInput): PlanDetail {
  const summary = buildPlanSummary(input);

  // Member EPIC list, status-weighted (same order Screen B uses) — carries the
  // per-EPIC membershipSource so the weaker 'derived' tier is visible.
  const epics: EpicSummary[] = input.members
    .map((m) => ({ ...m.summary, membershipSource: m.membershipSource }))
    .sort(compareEpicSummary);

  const warnings: string[] = [];
  for (const m of input.members) {
    if (m.membershipSource === 'derived') {
      warnings.push(
        `${m.epicId} přiřazeno k ${summary.planId} podle čísla EPICu, ne podle plan_path`,
      );
    }
  }
  if (input.aggregateAudit.scoredEpicCount === 1) {
    warnings.push('aggregateAudit z jediného auditovaného EPICu (n=1)');
  }
  warnings.push(...input.backlog.warnings.map((w) => `backlog: ${w}`));

  const lessons = buildLessonsView(input);

  return {
    ...summary,
    description: input.description,
    epics,
    orphanEpicCount: input.orphanEpicCount,
    durationS: rollupPlanDuration(input.members),
    boundaryAudit: input.boundaryAudit,
    aggregateAudit: input.aggregateAudit,
    deliveryReport: input.deliveryReport,
    simplifierSummary: input.simplifierSummary,
    backlog: {
      items: input.backlog.items,
      openCount: input.backlog.openCount,
      closedCount: input.backlog.closedCount,
      warnings: input.backlog.warnings,
    },
    lessons,
    warnings,
  };
}

// ===========================================================================
// Reporter delivery projection (MF6) — existence-checked _test_evidence[]
// ===========================================================================

/** The raw delivery-report material the route reads off disk. */
export interface DeliveryReportInput {
  /** false → no reports/{plan_id}-delivery.md (present:false). */
  present: boolean;
  /** Raw markdown body (frontmatter + body) when present; null otherwise. */
  text: string | null;
  /** Path to the full delivery .md for the drawer (/file); null when absent. */
  rawRelPath: string | null;
  /**
   * Per-cited-evidence existence check the route performed on disk. Each entry
   * pairs the cited `_test_evidence[]` name/relPath with whether the file
   * actually exists. A missing file → `exists:false` (flagged, never dropped).
   */
  testEvidence: ReporterTestEvidence[];
}

/**
 * Project a {@link ReporterDelivery} from the route-read delivery material.
 * Parses the `_generated_by`/`_generated_at` frontmatter, the PASS/FAIL/PARTIAL
 * outcome, and a short Czech summary. Test-evidence rows are passed through
 * verbatim (the route did the on-disk existence check); a missing one yields a
 * `warnings[]` note. Pure; never throws.
 */
export function buildReporterDelivery(input: DeliveryReportInput): ReporterDelivery {
  if (!input.present || input.text === null) {
    return {
      present: false,
      outcome: null,
      summaryCs: null,
      generatedBy: null,
      generatedAt: null,
      testEvidence: [],
      rawRelPath: null,
      warnings: [],
    };
  }

  const text = input.text;
  const warnings: string[] = [];

  const generatedBy = matchScalar(text, /_generated_by/);
  const generatedAt = matchScalar(text, /_generated_at/);

  const outcome = parseDeliveryOutcome(text);
  if (outcome === null) warnings.push('outcome unparseable');

  const summaryCs = parseDeliverySummary(text);

  const missing = input.testEvidence.filter((e) => !e.exists);
  if (missing.length > 0) {
    warnings.push(
      `${missing.length} test-evidence ${missing.length === 1 ? 'soubor chybí' : 'souborů chybí'} na disku`,
    );
  }

  return {
    present: true,
    outcome,
    summaryCs,
    generatedBy,
    generatedAt,
    testEvidence: input.testEvidence,
    rawRelPath: input.rawRelPath,
    warnings,
  };
}

/**
 * Parse the delivery report's PASS/FAIL/PARTIAL outcome. Reads an explicit
 * `outcome:` / `test_outcome:` / `Outcome:` line OR the `## Výsledek` heading
 * value. A value that is not pass/fail/partial (e.g. `no-runtime`) → null (NOT
 * fabricated). Pure.
 */
export function parseDeliveryOutcome(text: string): DeliveryOutcome {
  const line =
    matchScalar(text, /(?:test_)?outcome/i) ??
    headingValue(text, /(?:Výsledek|Outcome)/i);
  if (line === null) return null;
  const v = line.toLowerCase();
  if (v === 'pass' || v === 'passed' || v === 'ok' || v === 'success') return 'pass';
  if (v === 'fail' || v === 'failed') return 'fail';
  if (v === 'partial') return 'partial';
  return null;
}

/** Short Czech "co se dodalo" line — first non-empty prose line under "Co bylo dodáno". */
function parseDeliverySummary(text: string): string | null {
  const m = text.match(/^##\s+[^\n]*?(?:Co bylo dodáno|Co se dodalo|Souhrn|Summary)[^\n]*$/im);
  if (m) {
    const after = text.slice(m.index! + m[0].length);
    const line = firstProseLine(after);
    if (line) return line;
  }
  // Fallback: first prose line of the body (after frontmatter + H1).
  const body = stripFrontmatter(text).replace(/^#\s+[^\n]*$/m, '');
  return firstProseLine(body);
}

// ===========================================================================
// Simplifier projection (MF6)
// ===========================================================================

/** The raw simplifier-report material the route reads off disk. */
export interface SimplifierReportInput {
  present: boolean;
  text: string | null;
  rawRelPath: string | null;
}

/**
 * Project a {@link SimplifierSummary} from the route-read simplifier material.
 * Parses the YAML-ish `proposals:` list (id / area / title-or-text / effort /
 * recommended_disposition). Propose-only (never edits code, §4.3). Pure; never
 * throws — an unparseable body yields `proposals:[]` + a warning.
 */
export function buildSimplifierSummary(input: SimplifierReportInput): SimplifierSummary {
  if (!input.present || input.text === null) {
    return {
      present: false,
      proposalCount: 0,
      proposals: [],
      headlineCs: null,
      rawRelPath: null,
      warnings: [],
    };
  }

  const warnings: string[] = [];
  const proposals = parseSimplifierProposals(input.text);
  if (proposals.length === 0) warnings.push('no parseable proposals');

  const headlineCs =
    proposals.length === 0
      ? 'Zjednodušovač zatím nenavrhl žádné zjednodušení.'
      : `Zjednodušovač navrhuje ${proposals.length} ${plural(proposals.length, 'zjednodušení', 'zjednodušení', 'zjednodušení')}.`;

  return {
    present: true,
    proposalCount: proposals.length,
    proposals,
    headlineCs,
    rawRelPath: input.rawRelPath,
    warnings,
  };
}

/**
 * Parse the `proposals:` block of a simplifier-report.md into
 * {@link SimplifierProposal}[]. Each `- id:` item is a proposal; `title`/`area`/
 * `effort`/`recommended_disposition` are read per-item. Best-effort + defensive.
 */
export function parseSimplifierProposals(text: string): SimplifierProposal[] {
  const out: SimplifierProposal[] = [];
  // Split on `- id:` item markers within the proposals block.
  const items = text.split(/^\s*-\s+id\s*:/im);
  // items[0] is the preamble before the first `- id:`; skip it.
  for (let i = 1; i < items.length; i++) {
    const block = items[i];
    const idMatch = block.match(/^\s*["']?([A-Za-z]+-\d+)["']?/);
    const id = idMatch ? idMatch[1] : null;
    const title =
      scalarInBlock(block, 'title') ?? scalarInBlock(block, 'proposal') ?? '';
    const area = scalarInBlock(block, 'area');
    const effort = normalizeEffort(scalarInBlock(block, 'effort'));
    const disposition = normalizeDisposition(
      scalarInBlock(block, 'recommended_disposition') ??
        scalarInBlock(block, 'disposition'),
    );
    out.push({
      id,
      area,
      proposal: title.length > 0 ? title : (id ?? 'návrh na zjednodušení'),
      disposition,
      effort,
    });
  }
  return out;
}

// ===========================================================================
// Roll-ups (§5.4 / §5.5 / §5.1)
// ===========================================================================

/**
 * AC% roll-up (§5.5): `Σpresent/Σac_count*100`. Returns null when NO member
 * measured ACs (no plan-diff.json on any member) — rendered "N/A — fast mode",
 * NEVER 0%.
 */
export function rollupAcPct(members: PlanMemberInput[]): number | null {
  let present = 0;
  let total = 0;
  let measured = false;
  for (const m of members) {
    if (m.ac !== null) {
      measured = true;
      present += m.ac.present;
      total += m.ac.total;
    }
  }
  if (!measured || total === 0) return null;
  return Math.round((present / total) * 100);
}

/**
 * `plan_duration_sec` (§5.1): `min(member latest-run start) → max(member terminal
 * end)`. Null when no member run has BOTH a parseable start and end anchor.
 */
export function rollupPlanDuration(members: PlanMemberInput[]): number | null {
  let minStart: number | null = null;
  let maxEnd: number | null = null;
  for (const m of members) {
    const s = m.latestRun?.startedAtMs ?? null;
    const e = m.latestRun?.lastActivityMs ?? null;
    if (s !== null && (minStart === null || s < minStart)) minStart = s;
    if (e !== null && (maxEnd === null || e > maxEnd)) maxEnd = e;
  }
  if (minStart === null || maxEnd === null || maxEnd < minStart) return null;
  return Math.round((maxEnd - minStart) / 1000);
}

/** lastActivityAt roll-up: the newest member terminal/activity mtime, or null. */
function rollupLastActivity(members: PlanMemberInput[]): string | null {
  let max: number | null = null;
  for (const m of members) {
    const e = m.latestRun?.lastActivityMs ?? null;
    if (e !== null && (max === null || e > max)) max = e;
  }
  return max !== null ? new Date(max).toISOString() : null;
}

// ===========================================================================
// Lessons projection (§13.8 — minimal in this step; full builder is Step 8)
// ===========================================================================

/** Filter all-project lessons to this plan's member EPICs (chronological-desc). */
function filterLessons(
  all: LessonEntry[],
  members: PlanMemberInput[],
): LessonEntry[] {
  const epicIds = new Set(members.map((m) => m.epicId));
  const filtered = all.filter((l) => l.epicId !== null && epicIds.has(l.epicId));
  return [...filtered].sort(compareLessonDesc);
}

/** Build the full plan-scope {@link LessonsView}. Never throws. */
export function buildLessonsView(input: PlanBuildInput): LessonsView {
  const entries = filterLessons(input.allLessons, input.members);
  return {
    scope: 'plan',
    projectId: input.projectId,
    planId: input.planId, // stem-primary (PM #1)
    entries,
    total: entries.length,
    warnings: [],
  };
}

function compareLessonDesc(a: LessonEntry, b: LessonEntry): number {
  const ta = a.date ? Date.parse(a.date) : NaN;
  const tb = b.date ? Date.parse(b.date) : NaN;
  const va = Number.isNaN(ta) ? -Infinity : ta;
  const vb = Number.isNaN(tb) ? -Infinity : tb;
  return vb - va; // newest first
}

// ===========================================================================
// Sort + small parse helpers
// ===========================================================================

const STATUS_PRIORITY: Record<string, number> = {
  active: 0,
  running: 0,
  in_progress: 1,
  ready: 2,
  draft: 3,
  completed: 4,
  archived: 5,
};

function statusWeight(status: string): number {
  return STATUS_PRIORITY[status.toLowerCase()] ?? 3;
}

function compareEpicSummary(a: EpicSummary, b: EpicSummary): number {
  const sw = statusWeight(a.status) - statusWeight(b.status);
  if (sw !== 0) return sw;
  return a.id.localeCompare(b.id);
}

/** Strip a leading `---\n…\n---` frontmatter fence. */
function stripFrontmatter(text: string): string {
  return text.replace(/^---\s*\n[\s\S]*?\n---\s*\n?/, '');
}

/** Match a leading `key: value` scalar (frontmatter or bare), de-quoted. */
function matchScalar(text: string, keyRe: RegExp): string | null {
  const re = new RegExp(`^\\s*${keyRe.source}\\s*:\\s*(.+?)\\s*$`, 'im');
  const m = text.match(re);
  if (!m) return null;
  return dequote(m[1]);
}

/** Read a `## Heading: value` heading's inline value. */
function headingValue(text: string, headingRe: RegExp): string | null {
  const re = new RegExp(`^#{1,3}\\s+${headingRe.source}\\s*:?\\s*(\\w+)`, 'im');
  const m = text.match(re);
  return m ? dequote(m[1]) : null;
}

/** A scalar `key: value` within a single proposal block (de-quoted, single-line). */
function scalarInBlock(block: string, key: string): string | null {
  const re = new RegExp(`^\\s*${key}\\s*:\\s*(.+?)\\s*$`, 'im');
  const m = block.match(re);
  if (!m) return null;
  let v = dequote(m[1]);
  // Drop YAML block-scalar indicators (`>` / `|`) — the value is on later lines.
  if (v === '>' || v === '|' || v === '>-' || v === '|-') {
    const after = block.slice(m.index! + m[0].length);
    v = firstProseLine(after) ?? '';
  }
  return v.length > 0 ? v : null;
}

/** First non-empty, non-heading prose line of a markdown blob (≤200 chars). */
function firstProseLine(text: string): string | null {
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line.length === 0) continue;
    if (line.startsWith('#')) continue;
    if (line.startsWith('---')) continue;
    const clean = line.replace(/^[-*]\s+/, '').replace(/^_+|_+$/g, '');
    if (clean.length === 0) continue;
    return clean.length > 200 ? clean.slice(0, 200) : clean;
  }
  return null;
}

/** Strip surrounding single/double quotes. */
function dequote(v: string): string {
  return v.replace(/^["']|["']$/g, '').trim();
}

/** Normalize an effort token to the audit S|M|L scale, else null. */
function normalizeEffort(v: string | null): SimplifierProposal['effort'] {
  if (v === null) return null;
  const t = v.trim().toUpperCase();
  if (t === 'S' || t === 'SMALL') return 'S';
  if (t === 'M' || t === 'MEDIUM') return 'M';
  if (t === 'L' || t === 'LARGE') return 'L';
  return null;
}

/** Normalize a recommended_disposition to approve|reject|defer, else null. */
function normalizeDisposition(v: string | null): SimplifierDisposition {
  if (v === null) return null;
  const t = v.trim().toLowerCase();
  if (t === 'approve' || t === 'accept' || t === 'apply') return 'approve';
  if (t === 'reject' || t === 'decline') return 'reject';
  if (t === 'defer' || t === 'deferred') return 'defer';
  return null;
}

/** Czech plural picker (1 / 2-4 / 5+). */
function plural(n: number, one: string, few: string, many: string): string {
  if (n === 1) return one;
  if (n >= 2 && n <= 4) return few;
  return many;
}
