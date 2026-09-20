/**
 * Plan route-side I/O assembly (EPIC E-047-4_7, Step 7).
 *
 * The pure builders live in `build-plan.ts` / `build-plan-outcomes.ts`; THIS
 * module performs the scanner-cache reads they need and shapes them into the
 * builders' input structs. Shared by `routes/plans.ts` and
 * `routes/plan-analytics.ts` so membership / AC / audit / lessons / delivery /
 * simplifier reads are computed identically across both surfaces.
 *
 * Read-only: every read routes through the never-throw scanner cache / FsReader;
 * the membership resolution operates over the scanner's ACTIVE `tasks/` index
 * (archive/ EXCLUDED by the Tier-1 indexer) plus `work/evidence/` run dirs — so
 * an EPIC known ONLY via evidence (archived task) is still placed at the right
 * tier (P046's E-046-1_3/E-046-2_3 → 'derived'). NEVER writes; NEVER execs the
 * shell diagnostic.
 *
 * Module: src/plan/plan-assembly.ts
 */

import { basename, join } from 'node:path';
import type {
  AuditSummary,
  BacklogItem,
  EpicSummary,
  LessonEntry,
  ReporterTestEvidence,
} from '@aid/contract';
import type {
  IndexedEpic,
  IndexedProject,
  ScannerCache,
} from '../services/scanner-cache.js';
import { pickLatestIndexedRun, buildEpicSummary } from '../services/view-assembly.js';
import { parseLessons } from '../lessons/build-lessons.js';
import { FsReader } from '../services/fs-reader.js';
import { buildAuditTrend } from '../audit/build-audit-trend.js';
import {
  buildAggregateAudit,
  pickBoundaryAudit,
  type AggregateAudit,
  type MemberEpicSummary,
} from '../audit/build-aggregate-audit.js';
import {
  resolveMembership,
  planNumberPrefix,
  planNumberFrom,
  planStemFrom,
  buildReporterDelivery,
  buildSimplifierSummary,
  type PlanBuildInput,
  type PlanMemberInput,
  type MembershipInput,
} from './build-plan.js';
import type { OutcomeMemberRun, OutcomePlanInput } from './build-plan-outcomes.js';

// ===========================================================================
// Canonical EPIC view (real-tree reconciliation — the false-green trap)
// ===========================================================================

/**
 * On the REAL tree an EPIC can surface as TWO Tier-1 index entries: a task file
 * whose frontmatter has no `epic_id` indexes under its long FILENAME STEM
 * (`E-046-3_3-cp-enforcement-layer-…`, carrying `plan_ref` but NO runs), while
 * the `work/evidence/<epicId>/` dir indexes under the canonical id
 * (`E-046-3_3`, carrying the run but NO frontmatter). They are the SAME logical
 * EPIC. Without reconciliation P046 would show FOUR members (a duplicate
 * E-046-3_3) and the plan_ref tier would attach to the run-less stem entry.
 *
 * This merges all index entries that share a canonical `E-{NNN}-{N}_{N}` id into
 * one synthetic {@link IndexedEpic}: runs UNION'd, frontmatter taken from the
 * entry that has one (the task entry). The result is the three-member P046 the
 * spec/AC require, with `E-046-3_3` resolving at tier-2 `plan_ref` (its merged
 * view now has BOTH the run and the frontmatter) and E-046-1_3/E-046-2_3 at
 * tier-3 `derived` (evidence-only, no task frontmatter).
 *
 * @returns a map keyed by canonical EPIC id → merged synthetic IndexedEpic.
 */
export function canonicalEpics(indexed: IndexedProject): Map<string, IndexedEpic> {
  const merged = new Map<string, IndexedEpic>();
  for (const epic of indexed.epics.values()) {
    const id = canonicalEpicId(epic.epicId);
    const existing = merged.get(id);
    if (existing === undefined) {
      merged.set(id, {
        epicId: id,
        taskPath: epic.taskPath,
        frontmatter: epic.frontmatter,
        runs: new Map(epic.runs),
      });
      continue;
    }
    // Merge: keep the first non-null frontmatter/taskPath, union the runs.
    if (existing.frontmatter === null && epic.frontmatter !== null) {
      existing.frontmatter = epic.frontmatter;
    }
    if (existing.taskPath === null && epic.taskPath !== null) {
      existing.taskPath = epic.taskPath;
    }
    for (const [runId, run] of epic.runs) {
      if (!existing.runs.has(runId)) existing.runs.set(runId, run);
    }
  }
  return merged;
}

/**
 * Reduce a raw index key to its canonical EPIC id. A key beginning with the
 * `E-{NNN}-{N}_{N}` pattern (task filename stems append a slug after it) is
 * truncated to that pattern; anything else is returned unchanged.
 */
export function canonicalEpicId(rawId: string): string {
  const m = rawId.match(/^(E-?\d+-\d+_\d+)/i);
  return m ? m[1] : rawId;
}

// ===========================================================================
// Plan discovery (which planIds exist + which EPICs are members)
// ===========================================================================

/** Map a plan filename stem → its plan NUMBER (P{NNN}). */
export function planNumberOfStem(stem: string): string | null {
  return planNumberPrefix(stem);
}

/** A discovered plan: its stem (PRIMARY identity), optional plan number (alias), and member EPIC ids. */
export interface DiscoveredPlan {
  planStem: string; // filename stem, PRIMARY identity (e.g. P046-plan-boundary-…, ideas, roadmap)
  planNumber: string | null; // P{NNN} (alias, null when stem has no parseable number)
  ambiguousNumber: boolean; // true when planNumber maps to multiple stems (can't look up by number)
  memberEpicIds: string[];
  orphanEpicCount: number;
  warnings: string[]; // ambiguity warnings, etc.
}

/**
 * A predicate over a project's plan index: does a `plans/P{NNN}-*.md` (or bare
 * `P{NNN}.md`) file exist for this plan number? Drives the §13.6 tier resolution
 * (a plan_ref/derived candidate with no plan file degrades to orphan).
 */
export function makePlanFileExists(
  indexed: IndexedProject,
): (planNumber: string) => boolean {
  const numbers = new Set<string>();
  for (const stem of indexed.plans.keys()) {
    const n = planNumberPrefix(stem);
    if (n !== null) numbers.add(n.toUpperCase());
  }
  return (planNumber: string) => numbers.has(planNumber.toUpperCase());
}

/** Find the plan-file stem for a plan number (first match), or null. */
export function planStemForNumber(
  indexed: IndexedProject,
  planNumber: string,
): string | null {
  for (const stem of indexed.plans.keys()) {
    if (planNumberPrefix(stem)?.toUpperCase() === planNumber.toUpperCase()) {
      return stem;
    }
  }
  return null;
}

/**
 * A predicate over a project's plan index: does an EXACT plan STEM file exist
 * (`plans/P022-b-foo.md`)? Drives stem-primary tier-1/2 resolution (PM #1) so an
 * explicit `plan_path → P022-b-foo` resolves to that stem, never collapsing to
 * the number and picking the first colliding stem.
 */
export function makeStemFileExists(
  indexed: IndexedProject,
): (planStem: string) => boolean {
  const stems = new Set<string>();
  for (const stem of indexed.plans.keys()) stems.add(stem.toLowerCase());
  return (planStem: string) => stems.has(planStem.toLowerCase());
}

/** How many plan stems share a given plan number (>1 ⇒ ambiguous). */
export function stemsForNumber(indexed: IndexedProject, planNumber: string): string[] {
  const out: string[] = [];
  for (const stem of indexed.plans.keys()) {
    if (planNumberPrefix(stem)?.toUpperCase() === planNumber.toUpperCase()) out.push(stem);
  }
  return out;
}

/**
 * Resolve a single EPIC's membership tier within a project. Tier-1 reads the
 * latest run's fsm-state `plan_path` (authoritative); tier-2 reads frontmatter
 * `plan_ref`; tier-3 uses id-derivation (`E-{NNN}` → `P{NNN}`); tier-4 orphan.
 * Returns the firing tier + plan number (orphan → null number) + the resolved stem
 * (null for orphan or derived ambiguous memberships). Never throws.
 */
export async function resolveEpicMembership(
  scanner: ScannerCache,
  indexed: IndexedProject,
  epic: IndexedEpic,
  planFileExists: (planNumber: string) => boolean,
  stemFileExists: (planStem: string) => boolean = makeStemFileExists(indexed),
): Promise<{
  source: ReturnType<typeof resolveMembership>['source'];
  planNumber: string | null;
  planStem: string | null;
}> {
  // Tier-1: latest run's fsm-state plan_path. Validate the target exists at STEM
  // level first (PM #1), then number level; an unusable plan_path is downgraded.
  let planPath: string | null = null;
  const latest = pickLatestIndexedRun([...epic.runs.values()]);
  if (latest !== null) {
    const detail = await scanner.getRunDetail(indexed.projectId, epic.epicId, latest.runId);
    const rawPlanPath = detail.planPath ?? null;
    if (rawPlanPath !== null) {
      const stemCand = planStemFrom(rawPlanPath);
      const numCand = planNumberFrom(rawPlanPath);
      const stemOk = stemCand !== null && stemFileExists(stemCand);
      const numOk = numCand !== null && planFileExists(numCand);
      if (stemOk || numOk) planPath = rawPlanPath;
    }
  }

  const planRef = epic.frontmatter?.planRef ?? epic.frontmatter?.planPath ?? null;

  const input: MembershipInput = { epicId: epic.epicId, planPath, planRef };
  const membership = resolveMembership(input, planFileExists, stemFileExists);

  // planStem is the resolver's resolvedStem — set ONLY for explicit stem-bearing
  // plan_path/plan_ref whose stem exists. Number-only and id-derived → null, so
  // the caller never collapses them to the first colliding stem.
  return {
    source: membership.source,
    planNumber: membership.planNumber,
    planStem: membership.resolvedStem,
  };
}

/**
 * Group every EPIC in a project by plan stem (tiers 1-3). Returns one
 * {@link DiscoveredPlan} per plan STEM (primary identity), even if it has no
 * parseable P{NNN} number or no members. For ambiguous numbers (multiple stems
 * mapping to the same P{NNN}), sets `ambiguousNumber:true` and a warning on
 * each colliding stem. Each plan is emitted exactly once. Never throws.
 */
export async function discoverPlans(
  scanner: ScannerCache,
  indexed: IndexedProject,
): Promise<DiscoveredPlan[]> {
  const planFileExists = makePlanFileExists(indexed);
  const stemFileExists = makeStemFileExists(indexed);

  // number → stems (ambiguity detection).
  const numberToStems = new Map<string, string[]>();
  for (const stem of indexed.plans.keys()) {
    const planNumber = planNumberOfStem(stem);
    if (planNumber !== null) {
      const list = numberToStems.get(planNumber) ?? [];
      list.push(stem);
      numberToStems.set(planNumber, list);
    }
  }

  // Two member buckets: by EXPLICIT stem (tier-1/2 with resolvedStem), and by
  // NUMBER (number-only / id-derived). Number-only members are attached to a
  // stem ONLY when that number is unambiguous — never fanned out to every
  // colliding stem (PM #1).
  const membersByStem = new Map<string, string[]>();
  const membersByNumber = new Map<string, string[]>();
  for (const epic of canonicalEpics(indexed).values()) {
    const m = await resolveEpicMembership(scanner, indexed, epic, planFileExists, stemFileExists);
    if (m.source === 'orphan') continue;
    if (m.planStem !== null) {
      const list = membersByStem.get(m.planStem) ?? [];
      list.push(epic.epicId);
      membersByStem.set(m.planStem, list);
    } else if (m.planNumber !== null) {
      const list = membersByNumber.get(m.planNumber) ?? [];
      list.push(epic.epicId);
      membersByNumber.set(m.planNumber, list);
    }
  }

  const out: DiscoveredPlan[] = [];
  // Emit ALL plans (indexed.plans keys), including those with no P{NNN} number or no members.
  for (const stem of indexed.plans.keys()) {
    const planNumber = planNumberOfStem(stem);
    const warnings: string[] = [];

    let ambiguousNumber = false;
    if (planNumber !== null) {
      const collisions = numberToStems.get(planNumber) ?? [];
      if (collisions.length > 1) {
        ambiguousNumber = true;
        warnings.push(
          `planNumber ${planNumber} is ambiguous (maps to ${collisions.length} stems: ${collisions.join(', ')})`,
        );
      }
    }

    const memberSet = new Set<string>(membersByStem.get(stem) ?? []);
    if (planNumber !== null) {
      const numberOnly = membersByNumber.get(planNumber) ?? [];
      if (!ambiguousNumber) {
        for (const e of numberOnly) memberSet.add(e);
      } else if (numberOnly.length > 0) {
        warnings.push(
          `${numberOnly.length} number-only member(s) not assigned to a stem — ambiguous number needs an explicit plan_path stem`,
        );
      }
    }

    out.push({
      planStem: stem,
      planNumber,
      ambiguousNumber,
      memberEpicIds: [...memberSet].sort((a, b) => a.localeCompare(b)),
      orphanEpicCount: 0,
      warnings,
    });
  }
  out.sort((a, b) => a.planStem.localeCompare(b.planStem));
  return out;
}

// ===========================================================================
// Per-member read shapes
// ===========================================================================

/** Read a member EPIC's AC counters from its latest run's plan-diff.json. */
async function readEpicAc(
  fs: FsReader,
  runDir: string,
): Promise<{ present: number; total: number } | null> {
  const parsed = await fs.readJsonParsed<Record<string, unknown>>(
    join(runDir, 'plan-diff.json'),
  );
  const d = parsed.data;
  if (d === null || typeof d !== 'object') return null;
  const acCount = asNumber((d as Record<string, unknown>).acCount);
  // ac_count 0 (or absent) → fast mode / skipped → NOT measured (null, §5.5).
  if (acCount === null || acCount <= 0) return null;
  const summary = (d as Record<string, unknown>).summary;
  let present = 0;
  if (typeof summary === 'object' && summary !== null) {
    present = asNumber((summary as Record<string, unknown>).presentCount) ?? 0;
  }
  return { present, total: acCount };
}

/** Final-gate verdict over a run's gates: fail if any fails, else pass, else null. */
function gateFinalOf(gates: { result: 'pass' | 'fail' | 'skipped' }[]): 'pass' | 'fail' | null {
  if (gates.length === 0) return null;
  const considered = gates.filter((g) => g.result !== 'skipped');
  // All-skipped is NOT a pass (PM #4): nothing was actually proven, so there is
  // no gate-proof → null (a member with gateFinal:null is NOT classified passed).
  if (considered.length === 0) return null;
  return considered.some((g) => g.result === 'fail') ? 'fail' : 'pass';
}

/**
 * Build one {@link PlanMemberInput} for a member EPIC: its status-weighted
 * {@link EpicSummary}, latest-run anchors (start/terminal mtime for §5.1), and
 * AC counters (§5.5). Never throws.
 */
export async function buildPlanMember(
  scanner: ScannerCache,
  fs: FsReader,
  indexed: IndexedProject,
  epic: IndexedEpic,
  membershipSource: PlanMemberInput['membershipSource'],
): Promise<PlanMemberInput> {
  const summary: EpicSummary = {
    ...buildEpicSummary(indexed, epic),
    membershipSource,
  };

  const latest = pickLatestIndexedRun([...epic.runs.values()]);
  if (latest === null) {
    return { epicId: epic.epicId, membershipSource, summary, latestRun: null, ac: null };
  }

  const runDir = scanner.runDirFor(indexed.projectId, epic.epicId, latest.runId);
  const detail = await scanner.getRunDetail(indexed.projectId, epic.epicId, latest.runId);
  const startedAtMs = detail.startedAt ? Date.parse(detail.startedAt) : latest.startedAtMs;
  const ac = runDir ? await readEpicAc(fs, runDir) : null;

  return {
    epicId: epic.epicId,
    membershipSource,
    summary,
    latestRun: {
      runId: latest.runId,
      state: detail.state,
      startedAtMs: Number.isNaN(startedAtMs as number) ? null : startedAtMs,
      lastActivityMs: latest.mtimeMs,
    },
    ac,
  };
}

// ===========================================================================
// Lessons (project-wide read; filtered to plan members by the builder)
// ===========================================================================

/** Read + parse all lessons from a project's `work/lessons-learned.md`. */
export async function readAllLessons(
  fs: FsReader,
  indexed: IndexedProject,
): Promise<LessonEntry[]> {
  const path = join(indexed.aidoPath, 'work', 'lessons-learned.md');
  const text = await fs.readText(path);
  if (text === null) return [];
  return parseLessons(text);
}

// parseLessons is the canonical Step-8 parser, imported from
// ../lessons/build-lessons.js (single source of truth). The earlier private copy
// here had drifted (a no-op date ternary `? cell : cell` that never emitted ISO),
// making PlanDetail.lessons disagree with /api/lessons on the same row.

// ===========================================================================
// Audits (boundary + aggregate) over plan members
// ===========================================================================

/**
 * Build the boundary + aggregate audits for a plan's members. boundaryAudit =
 * the latest audited run of the LAST EPIC (by id order); aggregateAudit =
 * median-EPIC over audited members (SF4). Never throws.
 */
export async function buildPlanAudits(
  scanner: ScannerCache,
  indexed: IndexedProject,
  memberEpicIds: string[],
): Promise<{ boundary: AuditSummary; aggregate: AggregateAudit }> {
  const members: MemberEpicSummary[] = [];
  let lastEpicAudit: AuditSummary | null = null;
  const lastEpicId =
    memberEpicIds.length > 0
      ? [...memberEpicIds].sort((a, b) => a.localeCompare(b))[memberEpicIds.length - 1]
      : null;

  const canon = canonicalEpics(indexed);
  for (const epicId of memberEpicIds) {
    const epic = canon.get(epicId);
    if (!epic) continue;
    const latest = pickLatestIndexedRun([...epic.runs.values()]);
    if (latest === null) continue;
    const detail = await scanner.getRunDetail(indexed.projectId, epicId, latest.runId);
    members.push({ epicId, startedAt: detail.startedAt, summary: detail.audit });
    if (epicId === lastEpicId && detail.audit.present) {
      lastEpicAudit = detail.audit;
    }
  }

  return {
    boundary: pickBoundaryAudit(lastEpicAudit),
    aggregate: buildAggregateAudit(members),
  };
}

// ===========================================================================
// Reporter delivery + Simplifier (MF6) — existence-checked
// ===========================================================================

/**
 * Read + project the plan-boundary Reporter delivery for a plan number. The
 * delivery file is `.aid-o/reports/{planNumber}-delivery.md`; its
 * `_test_evidence[]` paths are existence-checked under the member run reporter
 * dirs (§4.3 anti-fabrication — a missing file → exists:false, never dropped).
 */
export async function buildPlanDelivery(
  scanner: ScannerCache,
  fs: FsReader,
  indexed: IndexedProject,
  planNumber: string,
  memberEpicIds: string[],
) {
  const relPath = `reports/${planNumber}-delivery.md`;
  const abs = join(indexed.aidoPath, relPath);
  const text = await fs.readText(abs);
  if (text === null) {
    return buildReporterDelivery({ present: false, text: null, rawRelPath: null, testEvidence: [] });
  }

  const cited = parseTestEvidence(text);
  const testEvidence: ReporterTestEvidence[] = [];
  for (const name of cited) {
    const exists = await testEvidenceExists(scanner, fs, indexed, memberEpicIds, name);
    testEvidence.push({ name: basename(name), relPath: name, exists });
  }

  return buildReporterDelivery({ present: true, text, rawRelPath: relPath, testEvidence });
}

/** Parse the `_test_evidence:` YAML list out of a delivery report's frontmatter. */
export function parseTestEvidence(text: string): string[] {
  const out: string[] = [];
  const m = text.match(/^_test_evidence\s*:\s*$/im);
  if (!m) {
    // Inline form `_test_evidence: ["a", "b"]`.
    const inline = text.match(/^_test_evidence\s*:\s*\[([^\]]*)\]/im);
    if (inline) {
      for (const piece of inline[1].split(',')) {
        const v = piece.replace(/^["'\s]+|["'\s]+$/g, '');
        if (v.length > 0) out.push(v);
      }
    }
    return out;
  }
  // Block list: subsequent `  - "path"` lines until a non-list line.
  const after = text.slice(m.index! + m[0].length);
  for (const raw of after.split('\n')) {
    const item = raw.match(/^\s+-\s+(.+?)\s*$/);
    if (!item) {
      if (raw.trim().length === 0) continue;
      break; // end of the block list
    }
    const v = item[1].replace(/^["']|["']$/g, '').trim();
    if (v.length > 0) out.push(v);
  }
  return out;
}

/**
 * Check whether a cited test-evidence file exists under ANY member run's
 * reporter/run dir. A path like `reporter/test-suite.txt` is resolved against
 * each member's latest-run dir. Returns true on the first hit.
 */
async function testEvidenceExists(
  scanner: ScannerCache,
  fs: FsReader,
  indexed: IndexedProject,
  memberEpicIds: string[],
  citedPath: string,
): Promise<boolean> {
  const canon = canonicalEpics(indexed);
  for (const epicId of memberEpicIds) {
    const epic = canon.get(epicId);
    if (!epic) continue;
    for (const run of epic.runs.values()) {
      const runDir = scanner.runDirFor(indexed.projectId, epicId, run.runId);
      if (runDir === null) continue;
      if (await fs.exists(join(runDir, citedPath))) return true;
    }
  }
  return false;
}

/**
 * Read + project the plan-boundary Simplifier proposals. The MVP1 source is the
 * member runs' `simplifier-report.md` (the plan-close simplifier output lands in
 * the last EPIC's run, §4.3). Picks the first member run that has one.
 */
export async function buildPlanSimplifier(
  scanner: ScannerCache,
  fs: FsReader,
  indexed: IndexedProject,
  memberEpicIds: string[],
) {
  // Last EPIC first (plan-close simplifier runs on the plan's last EPIC).
  const canon = canonicalEpics(indexed);
  const ordered = [...memberEpicIds].sort((a, b) => b.localeCompare(a));
  for (const epicId of ordered) {
    const epic = canon.get(epicId);
    if (!epic) continue;
    const latest = pickLatestIndexedRun([...epic.runs.values()]);
    if (latest === null) continue;
    const runDir = scanner.runDirFor(indexed.projectId, epicId, latest.runId);
    if (runDir === null) continue;
    const relPath = join('work', 'evidence', epicId, latest.runId, 'simplifier-report.md');
    const text = await fs.readText(join(runDir, 'simplifier-report.md'));
    if (text !== null) {
      return buildSimplifierSummary({ present: true, text, rawRelPath: relPath });
    }
  }
  return buildSimplifierSummary({ present: false, text: null, rawRelPath: null });
}

// ===========================================================================
// Backlog (current rows scoped to plan members)
// ===========================================================================

/** Read current backlog rows scoped to a plan's member EPICs + absolute counts. */
export async function buildPlanBacklog(
  fs: FsReader,
  indexed: IndexedProject,
  memberEpicIds: string[],
): Promise<{ items: BacklogItem[]; openCount: number; closedCount: number; warnings: string[] }> {
  const warnings: string[] = [];
  const path = join(indexed.aidoPath, 'work', 'backlog.md');
  const text = await fs.readText(path);
  if (text === null) {
    return { items: [], openCount: 0, closedCount: 0, warnings: ['no backlog.md'] };
  }
  // The full backlog rows are not EPIC-keyed reliably; MVP1 surfaces the absolute
  // "Active proposals: N" header count and serves rows that mention a member EPIC
  // id in their text (best-effort scoping — the FE owns the precise delta, MF2).
  const items: BacklogItem[] = [];
  const epicIds = new Set(memberEpicIds);
  for (const raw of text.split('\n')) {
    const row = raw.match(/^\s*\|(.+)\|\s*$/);
    if (!row) continue;
    const cells = row[1].split('|').map((c) => c.trim());
    if (cells.length < 2) continue;
    if (cells.some((c) => [...epicIds].some((e) => c.includes(e)))) {
      items.push({
        projectId: indexed.projectId,
        id: cells[0].length > 0 ? cells[0] : null,
        title: cells[1] ?? '',
        status: null,
        raw: raw.trim(),
      });
    }
  }
  const openMatch = text.match(/Active proposals:\s*(\d+)/i);
  const openCount = openMatch ? parseInt(openMatch[1], 10) : items.length;
  if (!openMatch) warnings.push('open count not derivable — header counter absent');
  return { items, openCount, closedCount: 0, warnings };
}

// ===========================================================================
// Full PlanBuildInput assembly (routes/plans.ts)
// ===========================================================================

/**
 * Assemble the full {@link PlanBuildInput} for a plan stem (or plan number) in a
 * project. Reads members (with membership tiers), plan body/title, AC, audits,
 * lessons, delivery, simplifier, backlog. Returns null when the plan has no real
 * file / no members (404 at the route). Never throws.
 *
 * Accepts either a plan stem (e.g. "P046-foo", "ideas", "roadmap") or a BARE
 * plan number (e.g. "P046"). STEM is checked FIRST (PM #1): a stem like
 * "P22-DA14-foo" also begins with `P{NNN}`, so number-detection must NOT win
 * over an exact stem match, or it would collapse to the first colliding stem.
 * A bare number that maps to multiple stems resolves to the first; routes detect
 * ambiguity and return 409 before calling this.
 */
export async function assemblePlanBuildInput(
  scanner: ScannerCache,
  fs: FsReader,
  indexed: IndexedProject,
  planIdOrNumber: string,
): Promise<PlanBuildInput | null> {
  const planFileExists = makePlanFileExists(indexed);

  // STEM-FIRST resolution: an exact stem match wins. Only a BARE number
  // (`^P\d+$`, no slug suffix) is resolved via planStemForNumber.
  let stem: string | null = null;
  if (indexed.plans.has(planIdOrNumber)) {
    stem = planIdOrNumber; // exact stem (primary identity)
  } else if (/^P\d+$/i.test(planIdOrNumber)) {
    stem = planStemForNumber(indexed, planIdOrNumber);
  }
  if (stem === null) return null;

  // Members + their tier (over the canonical merged EPIC view).
  // Explicit plan_path/plan_ref (tier-1/2) attach via the RESOLVED STEM. Tier-3
  // (id-derived) / number-only attach via the number — but ONLY when that number
  // is unambiguous; at a colliding number a number-only member is NOT assigned
  // (PM #1: never fan the same EPIC out to every colliding stem).
  const stemFileExists = makeStemFileExists(indexed);
  const members: PlanMemberInput[] = [];
  let orphanEpicCount = 0;
  const stemNumber = planNumberOfStem(stem);
  const numberAmbiguous = stemNumber !== null && stemsForNumber(indexed, stemNumber).length > 1;
  for (const epic of canonicalEpics(indexed).values()) {
    const m = await resolveEpicMembership(scanner, indexed, epic, planFileExists, stemFileExists);
    if (m.source !== 'orphan') {
      if (m.planStem !== null) {
        if (m.planStem === stem) {
          members.push(await buildPlanMember(scanner, fs, indexed, epic, m.source));
        }
      } else if (m.planNumber && stemNumber === m.planNumber && !numberAmbiguous) {
        members.push(await buildPlanMember(scanner, fs, indexed, epic, m.source));
      }
    } else {
      orphanEpicCount++;
    }
  }
  // A plan whose FILE exists but has zero resolved members is NOT a 404 (PM
  // decision b): it is a real plan with an unverifiable outcome + dataPartial.
  // Returning null here would (a) 404 an existing plan detail and (b) DROP it
  // from the /api/plans list, disagreeing with /api/analytics/plans which keeps
  // it. We only return null above when the STEM itself doesn't exist.

  const memberEpicIds = members.map((m) => m.epicId);

  // Plan body / title / description.
  const planFile = indexed.plans.get(stem) ?? null;
  const fm = planFile?.frontmatter ?? null;
  let title = (fm?.title as string | undefined) ?? stem;
  let description: string | null = null;
  if (planFile) {
    const text = await fs.readText(planFile.path);
    if (text !== null) {
      const h1 = text.match(/^#\s+(.+)$/m);
      if (h1 && (fm?.title === undefined)) title = h1[1].trim();
      description = firstPlanProse(text);
    }
  }
  const planRef = planFile?.path
    ? planFile.path.replace(`${indexed.projectDir}/`, '')
    : `.aid-o/plans/${stem}.md`;

  const allLessons = await readAllLessons(fs, indexed);
  const { boundary, aggregate } = await buildPlanAudits(scanner, indexed, memberEpicIds);
  const deliveryReport = await buildPlanDelivery(
    scanner,
    fs,
    indexed,
    stemNumber ?? stem,
    memberEpicIds,
  );
  const simplifierSummary = await buildPlanSimplifier(scanner, fs, indexed, memberEpicIds);
  const backlog = await buildPlanBacklog(fs, indexed, memberEpicIds);

  // plan-scope audit trend: one point per audited member (latest audited run).
  const trendCanon = canonicalEpics(indexed);
  const trendPoints = [];
  for (const epicId of memberEpicIds) {
    const epic = trendCanon.get(epicId);
    if (!epic) continue;
    const latest = pickLatestIndexedRun([...epic.runs.values()]);
    if (latest === null) continue;
    const detail = await scanner.getRunDetail(indexed.projectId, epicId, latest.runId);
    if (!detail.audit.present) continue;
    trendPoints.push({
      runId: detail.runId,
      epicId,
      startedAt:
        detail.startedAt ??
        (latest.mtimeMs != null ? new Date(latest.mtimeMs).toISOString() : null),
      score: detail.audit.overallScore,
      blockingFindings: detail.audit.blockingFindings,
    });
  }
  const auditTrend = buildAuditTrend(trendPoints, 'plan');

  return {
    projectId: indexed.projectId,
    planId: stem,
    title,
    planRef,
    description,
    members,
    orphanEpicCount,
    auditTrend,
    allLessons,
    boundaryAudit: boundary,
    aggregateAudit: aggregate,
    deliveryReport,
    simplifierSummary,
    backlog,
  };
}

// ===========================================================================
// Outcome input assembly (routes/plan-analytics.ts)
// ===========================================================================

/**
 * Assemble the {@link OutcomePlanInput} for one plan number in a project — the
 * aggregate signals the §13.12 classifier needs. Pure projection over scanner
 * objects; NEVER execs the shell diagnostic. Returns input for ALL plans,
 * including those with zero members (outcome: unverifiable, dataPartial:true).
 */
export async function assembleOutcomePlanInput(
  scanner: ScannerCache,
  fs: FsReader,
  indexed: IndexedProject,
  plan: DiscoveredPlan,
): Promise<OutcomePlanInput | null> {
  // Proceed even with zero members — will emit outcome:unverifiable + dataPartial:true
  const stem = plan.planStem;
  const fm = indexed.plans.get(stem)?.frontmatter ?? null;
  const title = (fm?.title as string | undefined) ?? stem;

  const memberRuns: OutcomeMemberRun[] = [];
  let runsTotal = 0;
  let failedRuns = 0;
  let gateFailures = 0;
  let gateRetries = 0;
  let escalations = 0;
  let forceOverrides = 0;
  let knownCpTotal = 0;
  let unknownCheckpoints = 0;
  const fsmFailures = { precondition: 0, increment: 0, doneAdvance: 0, other: 0 };
  const compliance = { passed: 0, failed: 0, unknown: 0 };
  const reasonCounts = new Map<string, number>();
  let firstStartedMs: number | null = null;
  let lastCompletedMs: number | null = null;
  let lastActivityMs: number | null = null;
  let epicsDone = 0;

  const canon = canonicalEpics(indexed);
  for (const epicId of plan.memberEpicIds) {
    const epic = canon.get(epicId);
    if (!epic) continue;
    const allRuns = [...epic.runs.values()];
    runsTotal += allRuns.length;

    // Aggregate cumulative signals across ALL runs of this EPIC (§5.4 sum).
    for (const run of allRuns) {
      const detail = await scanner.getRunDetail(indexed.projectId, epicId, run.runId);
      if (run.mtimeMs !== null && (lastActivityMs === null || run.mtimeMs > lastActivityMs)) {
        lastActivityMs = run.mtimeMs;
      }
      const startMs = detail.startedAt ? Date.parse(detail.startedAt) : run.startedAtMs;
      if (startMs !== null && !Number.isNaN(startMs) && (firstStartedMs === null || startMs < firstStartedMs)) {
        firstStartedMs = startMs;
      }
      if (detail.state === 'ERROR') failedRuns++;
      if (detail.state === 'DONE' && run.mtimeMs !== null) {
        if (lastCompletedMs === null || run.mtimeMs > lastCompletedMs) lastCompletedMs = run.mtimeMs;
      }
      gateRetries += detail.gateRetries;
      escalations += detail.escalationCount;
      forceOverrides += detail.compliance?.forceOverrideCount ?? 0;

      // gate failures (final-gate fails on this run).
      const gf = gateFinalOf(detail.gates);
      if (gf === 'fail') {
        gateFailures++;
        for (const g of detail.gates) {
          if (g.result === 'fail') bump(reasonCounts, `gate:${g.gate}`);
        }
      }

      // checkpoint repeats (known vs unknown). repeatCount null → unknown.
      for (const cp of detail.checkpoints) {
        if (cp.repeatCount === null) unknownCheckpoints++;
        else knownCpTotal += cp.repeatCount;
      }

      // FSM failure buckets from this run's timeline events.
      for (const ev of detail.timeline) {
        if (ev.event === 'fsm_precondition_fail') {
          fsmFailures.precondition++;
          bump(reasonCounts, normalizeReason(ev.raw.reason) ?? 'precondition_fail');
        } else if (ev.event === 'fsm_increment_fail') {
          fsmFailures.increment++;
          bump(reasonCounts, normalizeReason(ev.raw.reason) ?? 'increment_fail');
        } else if (ev.event === 'fsm_done_advance_fail') {
          fsmFailures.doneAdvance++;
          bump(reasonCounts, normalizeReason(ev.raw.reason) ?? 'done_advance_fail');
        } else if (/_fail$/.test(ev.event)) {
          fsmFailures.other++;
        }
      }

      // compliance reasons.
      if (detail.compliance) {
        for (const f of detail.compliance.failures) {
          bump(reasonCounts, `compliance:${f.check}`);
        }
      }
    }

    // Latest-run signals per member (classification basis).
    const latest = pickLatestIndexedRun(allRuns);
    if (latest === null) continue;
    const detail = await scanner.getRunDetail(indexed.projectId, epicId, latest.runId);
    if (detail.state === 'DONE') epicsDone++;
    const runDir = scanner.runDirFor(indexed.projectId, epicId, latest.runId);
    const ac = runDir ? await readEpicAc(fs, runDir) : null;
    const gateFinal = gateFinalOf(detail.gates);
    const comp = detail.compliance ? detail.compliance.overall : null;
    if (comp === 'pass') compliance.passed++;
    else if (comp === 'fail') compliance.failed++;
    else compliance.unknown++;

    memberRuns.push({
      epicId,
      runId: latest.runId,
      format: detail.format,
      state: detail.state,
      ac,
      gateFinal,
      compliance: comp,
    });
  }

  // Plan-boundary reporter outcome (rule 1 explicit-fail source).
  const planIdForDelivery = plan.planNumber ?? plan.planStem;
  const delivery = await buildPlanDelivery(scanner, fs, indexed, planIdForDelivery, plan.memberEpicIds);
  const reporterOutcome = delivery.present ? delivery.outcome : null;

  const topFailureReasons = [...reasonCounts.entries()]
    .map(([reason, count]) => ({ reason, count }))
    .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason))
    .slice(0, 5);

  return {
    projectId: indexed.projectId,
    // STEM is the primary identity (PM #1) — colliding numbers (e.g. six P22-*
    // plans) must surface as DISTINCT rows, never collapse to one "P22" label.
    planId: plan.planStem,
    ambiguousNumber: plan.ambiguousNumber,
    title,
    members: memberRuns,
    epicsTotal: plan.memberEpicIds.length,
    epicsDone,
    runsTotal,
    failedRuns,
    gateFailures,
    gateRetries,
    checkpointRetries: { knownTotal: knownCpTotal, unknownCheckpoints },
    fsmFailures,
    escalations,
    forceOverrides,
    compliance,
    topFailureReasons,
    reporterOutcome,
    firstStartedAt: firstStartedMs !== null ? new Date(firstStartedMs).toISOString() : null,
    lastCompletedAt: lastCompletedMs !== null ? new Date(lastCompletedMs).toISOString() : null,
    lastActivityAt: lastActivityMs !== null ? new Date(lastActivityMs).toISOString() : null,
  };
}

// ===========================================================================
// Small helpers
// ===========================================================================

function bump(map: Map<string, number>, key: string): void {
  map.set(key, (map.get(key) ?? 0) + 1);
}

function normalizeReason(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function asNumber(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

/** First prose block of a plan .md body (after frontmatter + H1), ≤400 chars. */
function firstPlanProse(text: string): string | null {
  const body = text
    .replace(/^---\s*\n[\s\S]*?\n---\s*\n?/, '')
    .replace(/^#\s+[^\n]*$/m, '');
  for (const raw of body.split('\n')) {
    const line = raw.trim();
    if (line.length === 0 || line.startsWith('#') || line.startsWith('>')) continue;
    return line.length > 400 ? line.slice(0, 400) : line;
  }
  return null;
}
