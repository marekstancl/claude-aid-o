/**
 * Managerial `Brief` read routes (EPIC E-047-4_7, Step 4) — spec §7.4, §13.4.
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api` by the bootstrap:
 *   - `GET /api/brief?since=`                       → `Brief` (scope `infra`)
 *   - `GET /api/brief/:projectId?since=`            → `Brief` (scope `project`)
 *   - `GET /api/brief/:projectId/:planId?since=`    → `Brief` (scope `plan`)
 *
 * The three routes differ ONLY in how they assemble the run set from the scanner
 * cache (§13.4 "one implementation, three callers"); the projection itself is the
 * pure {@link buildBrief}. Every read routes through the never-throw cache; a
 * malformed `queue.yaml` for one project yields an empty nextUp for that project
 * plus a `partialProjects` flag — never a 500 (§13.4 honesty). The server writes
 * NOTHING (read-only; the §7.6 grep test stays green).
 *
 * §5.7 resolution: a blocking compliance failure is "open" only when NO later run
 * of the same EPIC lacks it (a later run that re-passes the check resolves it).
 * The brief receives the latest run's compliance with already-resolved failures.
 *
 * Module: src/routes/brief.ts
 */

import { Router } from 'express';
import { join } from 'node:path';
import type { ComplianceFailure, RunDetail } from '@aid/contract';
import type { IndexedProject, IndexedRun, ScannerCache } from '../services/scanner-cache.js';
import { pickLatestIndexedRun } from '../services/view-assembly.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send404, send400, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import {
  buildBrief,
  type BriefProjectContext,
  type BriefQueueEntry,
  type BriefRunMember,
  type BriefRunSet,
} from '../brief/build-brief.js';

/** Coerce an unknown to a non-empty string, else null. */
function asString(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

/** Normalize the `?since=` query param to a single string or null. */
function readSince(raw: unknown): string | null {
  return typeof raw === 'string' && raw.length > 0 ? raw : null;
}

/**
 * Build the READ-ONLY brief router backed by the {@link ScannerCache}.
 * GET only — no mutation endpoints exist on this surface.
 */
export function briefRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /brief — INFRA scope. Latest run of every active EPIC across all
  // discovered projects + each project's queue (§13.4 infra scope).
  // -------------------------------------------------------------------------
  router.get('/brief', async (req, res) => {
    const since = readSince(req.query.since);
    const idx = await scanner.getIndex();

    const members: BriefRunMember[] = [];
    const projects: BriefProjectContext[] = [];
    const partialProjects: string[] = [];

    for (const indexed of [...idx.projects.values()].sort((a, b) =>
      a.projectId.localeCompare(b.projectId),
    )) {
      const projMembers = await assembleProjectMembers(scanner, indexed);
      members.push(...projMembers);
      const ctx = await readProjectContext(fs, indexed);
      projects.push(ctx);
      if (ctx.queuePartial) partialProjects.push(indexed.projectId);
    }

    const runSet: BriefRunSet = {
      projectId: null,
      planId: null,
      members,
      projects,
      partialProjects,
    };

    const brief = buildBrief(runSet, 'infra', since, isoNow());
    sendOk(res, brief, { scannedAt: brief.generatedAt, partialProjects });
  });

  // -------------------------------------------------------------------------
  // GET /brief/:projectId — PROJECT scope. One project's active EPICs + queue.
  // -------------------------------------------------------------------------
  router.get('/brief/:projectId', async (req, res) => {
    const { projectId } = req.params;
    if (!isValidPathComponent(projectId)) {
      send400(res, 'Invalid projectId path component');
      return;
    }

    const since = readSince(req.query.since);
    const idx = await scanner.getIndex();
    const indexed = idx.projects.get(projectId) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    const members = await assembleProjectMembers(scanner, indexed);
    const ctx = await readProjectContext(fs, indexed);
    const partialProjects = ctx.queuePartial ? [projectId] : [];

    const runSet: BriefRunSet = {
      projectId,
      planId: null,
      members,
      projects: [ctx],
      partialProjects,
    };

    const brief = buildBrief(runSet, 'project', since, isoNow());
    sendOk(res, brief, { scannedAt: brief.generatedAt, partialProjects });
  });

  // -------------------------------------------------------------------------
  // GET /brief/:projectId/:planId — PLAN scope. The plan's member EPICs per the
  // §13.6 four-tier rule (tiers 1-3 included; tier-4 orphans excluded — MF1).
  // -------------------------------------------------------------------------
  router.get('/brief/:projectId/:planId', async (req, res) => {
    const { projectId, planId } = req.params;
    if (!isValidPathComponent(projectId) || !isValidPathComponent(planId)) {
      send400(res, 'Invalid projectId/planId path component');
      return;
    }

    const since = readSince(req.query.since);
    const idx = await scanner.getIndex();
    const indexed = idx.projects.get(projectId) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectId}"`);
      return;
    }

    // Plan membership (MF1): which EPICs belong to this plan (tiers 1-3).
    const memberEpicIds = resolvePlanMembers(indexed, planId);
    const members: BriefRunMember[] = [];
    for (const epicId of memberEpicIds) {
      const epic = indexed.epics.get(epicId);
      if (!epic) continue;
      const m = await assembleEpicMember(scanner, indexed, epic.epicId, [...epic.runs.values()]);
      if (m) members.push(m);
    }

    const ctx = await readProjectContext(fs, indexed);
    const partialProjects = ctx.queuePartial ? [projectId] : [];

    const planEpicsTotal = memberEpicIds.length;
    const planEpicsDone = members.filter((m) => m.detail.state === 'DONE').length;

    const runSet: BriefRunSet = {
      projectId,
      planId,
      members,
      projects: [ctx],
      plan: {
        planId,
        progressPct:
          planEpicsTotal > 0 ? Math.round((planEpicsDone / planEpicsTotal) * 100) : null,
        epicsTotal: planEpicsTotal,
        epicsDone: planEpicsDone,
        lessons: [], // lessons-per-plan projection wires in via Step 8 (§13.8)
      },
      partialProjects,
    };

    const brief = buildBrief(runSet, 'plan', since, isoNow());
    sendOk(res, brief, { scannedAt: brief.generatedAt, partialProjects });
  });

  return router;
}

// ===========================================================================
// Run-set assembly (route-side I/O — buildBrief stays pure over the result)
// ===========================================================================

/**
 * Assemble the latest-run {@link BriefRunMember} for every ACTIVE EPIC in a
 * project (infra / project scope, §13.4). An EPIC with no runs is skipped (no
 * latest run to summarise). Resolution (§5.7) is applied per EPIC.
 */
async function assembleProjectMembers(
  scanner: ScannerCache,
  indexed: IndexedProject,
): Promise<BriefRunMember[]> {
  const out: BriefRunMember[] = [];
  for (const epic of indexed.epics.values()) {
    const m = await assembleEpicMember(scanner, indexed, epic.epicId, [...epic.runs.values()]);
    if (m) out.push(m);
  }
  return out;
}

/**
 * Build one EPIC's latest-run member: pick the latest run (shared selector), load
 * its full {@link RunDetail} via the memoizing cache, apply §5.7 resolution to
 * its blocking compliance failures, and capture the run-dir mtime as the
 * "touched since" reference. Returns null when the EPIC has no runs.
 */
async function assembleEpicMember(
  scanner: ScannerCache,
  indexed: IndexedProject,
  epicId: string,
  runs: IndexedRun[],
): Promise<BriefRunMember | null> {
  const latest = pickLatestIndexedRun(runs);
  if (latest === null) return null;

  const detail = await scanner.getRunDetail(indexed.projectId, epicId, latest.runId);
  const resolved = applyResolution(detail, runs, indexed, scanner);

  const touchedAtMs = latest.mtimeMs;
  return {
    projectId: indexed.projectId,
    epicId,
    runId: latest.runId,
    detail: await resolved,
    touchedAt: touchedAtMs !== null ? new Date(touchedAtMs).toISOString() : null,
    touchedAtMs,
  };
}

/**
 * Apply the §5.7 resolution rule to the latest run's blocking compliance
 * failures: a blocking failure is RESOLVED when a strictly-later run of the SAME
 * EPIC re-passes that check (i.e. has a compliance.json that lacks a blocking
 * failure with the same `.check`). Since we feed buildBrief the LATEST run, a
 * failure on it can only be resolved by an even-later run — which by definition
 * does not exist, so the latest-run failures stand. This function nonetheless
 * filters out any check that a later run cleared (defensive — handles the case
 * where the "latest" selector and the compliance run differ). Pure; never throws.
 */
async function applyResolution(
  detail: RunDetail,
  runs: IndexedRun[],
  indexed: IndexedProject,
  scanner: ScannerCache,
): Promise<RunDetail> {
  if (detail.compliance === null) return detail;
  const blocking = detail.compliance.failures.filter((f) => f.severity === 'blocking');
  if (blocking.length === 0) return detail;

  // Runs strictly newer than the one we summarised (by started_at/mtime order).
  const latestStarted = detail.startedAt ? Date.parse(detail.startedAt) : null;
  const cleared = new Set<string>();
  for (const r of runs) {
    if (r.runId === detail.runId) continue;
    // Only consider runs that look newer than the summarised run.
    const newer =
      r.startedAtMs !== null && latestStarted !== null
        ? r.startedAtMs > latestStarted
        : (r.mtimeMs ?? -Infinity) > (detail.startedAt ? latestStarted ?? -Infinity : -Infinity);
    if (!newer) continue;
    const laterDetail = await scanner.getRunDetail(indexed.projectId, detail.epicId, r.runId);
    if (laterDetail.compliance === null) continue;
    const laterBlocking = new Set(
      laterDetail.compliance.failures
        .filter((f) => f.severity === 'blocking')
        .map((f) => f.check),
    );
    for (const f of blocking) {
      if (!laterBlocking.has(f.check)) cleared.add(f.check);
    }
  }

  if (cleared.size === 0) return detail;
  const remaining: ComplianceFailure[] = detail.compliance.failures.filter(
    (f) => f.severity !== 'blocking' || !cleared.has(f.check),
  );
  return {
    ...detail,
    compliance: { ...detail.compliance, failures: remaining },
  };
}

/** Read a project's brief context: parsed queue + a partial flag. Never throws. */
async function readProjectContext(
  fs: FsReader,
  indexed: IndexedProject,
): Promise<BriefProjectContext> {
  const queuePath = join(indexed.aidoPath, 'config', 'queue.yaml');
  const parsed = await fs.readYamlParsed<{ queue?: unknown[] }>(queuePath);
  const hasError = parsed.warnings?.some((w) => w.severity === 'error') ?? false;

  const queue: BriefQueueEntry[] = [];
  if (parsed.data !== null) {
    const rows = Array.isArray(parsed.data.queue) ? parsed.data.queue : [];
    for (const r of rows) {
      if (typeof r !== 'object' || r === null) continue;
      const e = r as Record<string, unknown>;
      queue.push({
        epicId: asString(e.epic_id ?? e.epicId) ?? '',
        priority: asString(e.priority) ?? 'medium',
        status: asString(e.status) ?? 'queued',
        addedAt: asString(e.added_at ?? e.addedAt),
      });
    }
  }

  return { projectId: indexed.projectId, queue, queuePartial: hasError };
}

/**
 * Resolve a plan's member EPIC ids (§13.6 four-tier rule, MF1). Tiers 1-3 are
 * INCLUDED; tier-4 orphans are excluded. Because the scanner Tier-1 index only
 * carries scalar frontmatter (no `plan_path` body), this MVP1 assembly resolves:
 *   - tier-2 `plan_ref`  — the EPIC's task frontmatter `planRef` === planId;
 *   - tier-3 `derived`   — the EPIC id `E-{NNN}-…` maps to `P{NNN}` === planId
 *                          AND a real `plans/<planId>.md` exists.
 * The member SET is identical whether the label lands at tier-2 or tier-3 (the
 * spec's MF1 note) — only the `membershipSource` tag would shift. P046's three
 * null-`plan_path` members therefore resolve to a NON-EMPTY set (AC #5).
 */
export function resolvePlanMembers(indexed: IndexedProject, planId: string): string[] {
  const planExists = indexed.plans.has(planId);
  const out: string[] = [];
  for (const epic of indexed.epics.values()) {
    // Tier-2: frontmatter plan_ref.
    const planRef = epic.frontmatter?.planRef ?? epic.frontmatter?.planPath ?? null;
    if (planRef !== null && planRefMatches(planRef, planId)) {
      out.push(epic.epicId);
      continue;
    }
    // Tier-3: id-derived (E-{NNN} → P{NNN}), only when a real plan file exists.
    // The route planId is the plan filename stem (e.g. "P046-foo"); compare its
    // leading plan number (P046) against the EPIC-derived number.
    const derived = idDerivedPlan(epic.epicId);
    if (planExists && derived !== null && planNumberPrefix(planId) === derived) {
      out.push(epic.epicId);
    }
  }
  out.sort((a, b) => a.localeCompare(b));
  return out;
}

/** True when a frontmatter plan_ref names this plan (exact or path stem match). */
function planRefMatches(planRef: string, planId: string): boolean {
  if (planRef === planId) return true;
  // plan_ref may be a path like "plans/P046-foo.md" or a stem "P046-foo".
  const stem = planRef.replace(/^.*\//, '').replace(/\.md$/i, '');
  if (stem === planId) return true;
  // Or just the bare plan number "P046".
  const num = stem.match(/^(P\d+)/);
  return num !== null && num[1] === planId;
}

/** Derive the plan number from an EPIC id: `E-046-3_3` → `P046` (id-derived tier). */
function idDerivedPlan(epicId: string): string | null {
  const m = epicId.match(/^E-?(\d+)/i);
  return m ? `P${m[1]}` : null;
}

/** Extract the leading plan number from a plan id stem: `P046-foo` → `P046`. */
function planNumberPrefix(planId: string): string | null {
  const m = planId.match(/^(P\d+)/i);
  return m ? m[1] : null;
}
