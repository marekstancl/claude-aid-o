/**
 * LESSONS-PER-PLAN — `buildLessons` projection + never-throw parser
 * (EPIC E-047-4_7, Step 8 — spec §13.8 / §4.7 / §7.6).
 *
 * A pure, READ-ONLY managerial projection over a project's
 * `work/lessons-learned.md` (§4.7). The route reads the file once and hands the
 * already-parsed {@link LessonEntry}[] to {@link buildLessons}; the builder
 * shapes a scoped {@link LessonsView} at one of three altitudes (§13.8):
 *
 *   - **plan**    — only lessons whose `Context(epic_id)` ∈ the plan's member
 *                   EPICs (a lesson with NO Context cell → `epicId:null` is
 *                   EXCLUDED at plan scope; kept at project/infra).
 *   - **project** — every lesson in that project's file.
 *   - **infra**   — every lesson (all projects merged by the route).
 *
 * Honesty posture (§13.8 / §7.6 never-throw parser):
 *   - Absent or malformed file ⇒ the route parses to `[]`; {@link buildLessons}
 *     yields `entries:[]` + a `warnings[]` note — NEVER a throw.
 *   - A date is emitted as ISO ONLY when it parses; an unparseable date cell is
 *     kept as the RAW string (never faked into an ISO), an empty cell → `null`.
 *   - Entries sort chronological-desc when the date parses; entries whose date
 *     does NOT parse fall back to FILE ORDER (stable) and sort after dated ones.
 *
 * The parser ({@link parseLessons}) is the canonical never-throw reader: the
 * main `| Date | Lesson | Context |` table → `kind:'lesson'`; rows under a
 * `## Known Gotchas` heading → `kind:'gotcha'` (§4.7). It tolerates ragged rows,
 * missing columns, header/separator rows, and a `Known Gotchas` table whose
 * columns are `| Area | Gotcha |` (no Date/Context) without throwing.
 *
 * Module: src/lessons/build-lessons.ts
 */

import type { LessonEntry, LessonsView } from '@aid/contract';

/** The three projection altitudes (§13.8). */
export type LessonScope = LessonsView['scope']; // 'plan' | 'project' | 'infra'

// ===========================================================================
// buildLessons — the scoped projection (pure, never throws)
// ===========================================================================

/**
 * Project the already-parsed lessons into a scoped {@link LessonsView}.
 *
 * @param parsed       all lessons parsed from a project's lessons-learned.md
 *                     (file order preserved). Empty array ⇒ honest empty view.
 * @param scope        'plan' | 'project' | 'infra' (the route infers it from the
 *                     query params: both → plan, project-only → project, neither
 *                     → infra).
 * @param planEpicIds  the plan's member EPIC ids — REQUIRED for plan scope; the
 *                     filter keeps only lessons whose `epicId` ∈ this set. Absent
 *                     / undefined at plan scope ⇒ no member can match ⇒ empty +
 *                     a warning (honest, never a throw).
 * @param meta         optional projectId / planId stamped onto the view.
 */
export function buildLessons(
  parsed: LessonEntry[],
  scope: LessonScope,
  planEpicIds?: readonly string[],
  meta?: { projectId?: string | null; planId?: string | null },
): LessonsView {
  const warnings: string[] = [];

  // Honest empty: an absent/malformed file parses to [] upstream.
  if (parsed.length === 0) {
    warnings.push('lessons-learned.md absent or empty — no lessons to show');
  }

  let entries: LessonEntry[];
  if (scope === 'plan') {
    const members = new Set(planEpicIds ?? []);
    if (members.size === 0 && parsed.length > 0) {
      warnings.push('plan scope requested without member EPIC ids — no lessons match');
    }
    // A lesson with NO Context cell (epicId:null) is EXCLUDED at plan scope; a
    // lesson whose epicId is not a plan member is excluded too (§13.8).
    entries = parsed.filter((l) => l.epicId !== null && members.has(l.epicId));
  } else {
    // project / infra: every parsed lesson (the route merges files for infra).
    entries = [...parsed];
  }

  entries = sortLessons(entries);

  return {
    scope,
    projectId: meta?.projectId ?? null,
    planId: meta?.planId ?? null,
    entries,
    total: entries.length,
    warnings,
  };
}

/**
 * Sort lessons chronological-desc when the date parses; entries whose date does
 * NOT parse keep FILE ORDER and sort AFTER all dated entries (§13.8). Stable:
 * ties (and the undated tail) preserve their original relative order.
 */
export function sortLessons(entries: LessonEntry[]): LessonEntry[] {
  return entries
    .map((entry, index) => ({ entry, index, t: parseableTime(entry.date) }))
    .sort((a, b) => {
      const aDated = a.t !== null;
      const bDated = b.t !== null;
      // Dated entries come first; among them, newest-first.
      if (aDated && bDated) {
        if (a.t! !== b.t!) return b.t! - a.t!;
        return a.index - b.index; // stable tie-break
      }
      if (aDated) return -1;
      if (bDated) return 1;
      return a.index - b.index; // both undated → file order (stable)
    })
    .map((x) => x.entry);
}

/** Epoch ms when the (possibly ISO, possibly raw) date string parses, else null. */
function parseableTime(date: string | null): number | null {
  if (date === null || date.length === 0) return null;
  const ms = Date.parse(date);
  return Number.isNaN(ms) ? null : ms;
}

// ===========================================================================
// parseLessonDate — ISO when parseable, else raw cell, else null (§13.8 AC#5)
// ===========================================================================

/**
 * Normalize a Date-column cell:
 *   - empty / whitespace-only cell ⇒ `null`,
 *   - a parseable date (e.g. `2026-02-19`, `2026-06-18T14:00:00Z`) ⇒ its ISO
 *     `YYYY-MM-DD` form (date-only inputs stay date-only; datetime inputs keep
 *     their full ISO instant),
 *   - anything else (e.g. a free-text `Area` cell from the Known Gotchas table)
 *     ⇒ the RAW cell verbatim (NEVER faked into an ISO).
 */
export function parseLessonDate(cell: string): string | null {
  const trimmed = cell.trim();
  if (trimmed.length === 0) return null;

  const ms = Date.parse(trimmed);
  if (Number.isNaN(ms)) return trimmed; // unparseable → keep raw

  // A bare `YYYY-MM-DD` stays date-only; a fuller timestamp keeps its instant.
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return trimmed;
  return new Date(ms).toISOString();
}

// ===========================================================================
// classifyKind — section-heading → kind (§4.7)
// ===========================================================================

/**
 * Classify a table's rows by the most recent section heading above them. A
 * heading matching `Known Gotchas` (any heading level, case-insensitive) ⇒
 * `'gotcha'`; everything else (the main lessons table, no heading) ⇒ `'lesson'`
 * (§4.7).
 *
 * @param sectionHeading the current section heading text (with or without the
 *   leading `#`s), or null/empty when the row is under no heading yet.
 */
export function classifyKind(sectionHeading: string | null): LessonEntry['kind'] {
  if (sectionHeading === null) return 'lesson';
  const text = sectionHeading.replace(/^#+\s*/, '').trim().toLowerCase();
  return text.includes('known gotchas') ? 'gotcha' : 'lesson';
}

// ===========================================================================
// parseLessons — the canonical never-throw markdown reader (§4.7 / §7.6)
// ===========================================================================

/**
 * Parse a `lessons-learned.md` body into {@link LessonEntry}[] in FILE ORDER
 * (§4.7). Never throws — ragged rows, missing columns, header/separator rows,
 * and an alternately-shaped `## Known Gotchas` table (`| Area | Gotcha |`, no
 * Date/Context) are all handled defensively.
 *
 * Row → entry mapping:
 *   - main table (`| Date | Lesson | Context |`): cell[0]=date, cell[1]=lesson,
 *     cell[2]=epicId (absent ⇒ null).
 *   - Known Gotchas table (`| Area | Gotcha |`): cell[0] is a free-text Area
 *     (kept raw as `date` via {@link parseLessonDate}), cell[1]=lesson (the
 *     gotcha text), no Context cell ⇒ epicId:null. kind:'gotcha'.
 *
 * Rows with no lesson text are dropped. The `## Known Gotchas` heading switches
 * subsequent rows to `kind:'gotcha'` via {@link classifyKind}.
 */
export function parseLessons(text: string | null): LessonEntry[] {
  const out: LessonEntry[] = [];
  if (text === null || text.trim().length === 0) return out;

  let currentHeading: string | null = null;

  for (const raw of text.split('\n')) {
    const line = raw.trim();

    // Track the most recent heading so rows are classified by section (§4.7).
    if (/^#{1,6}\s+/.test(line)) {
      currentHeading = line;
      continue;
    }

    // Only `| … |` table rows are candidate lessons.
    const rowMatch = line.match(/^\|(.+)\|$/);
    if (!rowMatch) continue;

    const cells = rowMatch[1].split('|').map((c) => c.trim());
    if (cells.length < 2) continue;

    // Skip the header row (`| Date | Lesson | … |` / `| Area | Gotcha |`).
    const c0 = cells[0].toLowerCase();
    if (c0 === 'date' || c0 === 'area') continue;
    // Skip a separator row (`|---|---|`) — every cell is dashes/colons or empty.
    if (cells.every((c) => c === '' || /^:?-+:?$/.test(c))) continue;

    const kind = classifyKind(currentHeading);
    const date = parseLessonDate(cells[0]);
    const lesson = cells[1] ?? '';
    if (lesson.length === 0) continue; // a row with no lesson text is not a lesson
    const epicId = cells.length >= 3 && cells[2].length > 0 ? cells[2] : null;

    out.push({ date, lesson, epicId, kind });
  }

  return out;
}
