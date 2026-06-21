/**
 * LESSONS-PER-PLAN read route (EPIC E-047-4_7, Step 8 — spec §7.4, §13.8, AC#21).
 *
 * Scanner-backed, READ-ONLY (GET only). Mounted under `/api`, BEFORE the `/api/*`
 * catch-all:
 *
 *   - `GET /api/lessons?project=&plan=` → `LessonsView`. Scope is INFERRED from
 *     the query params (§13.8):
 *       - both `project` + `plan`  → **plan**    (lessons whose Context(epic_id)
 *                                                 ∈ the plan's member EPICs)
 *       - `project` only           → **project** (all of that project's lessons)
 *       - neither                  → **infra**   (all projects' lessons merged)
 *
 * The route does the I/O (reads each project's `work/lessons-learned.md` via the
 * never-throw {@link FsReader}, resolves plan membership via the §13.6 four-tier
 * {@link discoverPlans}); the pure {@link buildLessons} builder shapes the view.
 *
 * Honesty (§13.8 / §7.6, AC#21): an absent / malformed lessons-learned.md yields
 * `entries:[]` + a `warnings[]` note and the endpoint still returns **200** —
 * NEVER a 500 / throw. The server writes NOTHING (read-only; §7.6 grep stays
 * green).
 *
 * Module: src/routes/lessons.ts
 */

import { Router } from 'express';
import { join } from 'node:path';
import type { LessonEntry, LessonsView } from '@aid/contract';
import type { IndexedProject, ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send400, send404, isoNow } from '../api/middleware.js';
import { isValidPathComponent } from './path-validation.js';
import { buildLessons, parseLessons, type LessonScope } from '../lessons/build-lessons.js';
import { planNumberPrefix } from '../plan/build-plan.js';
import { discoverPlans } from '../plan/plan-assembly.js';

/**
 * Build the READ-ONLY lessons router backed by the {@link ScannerCache}. GET only.
 */
export function lessonsRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // -------------------------------------------------------------------------
  // GET /lessons?project=&plan= — LessonsView (scope inferred from params).
  // -------------------------------------------------------------------------
  router.get('/lessons', async (req, res) => {
    const projectParam = typeof req.query.project === 'string' ? req.query.project : '';
    const planParam = typeof req.query.plan === 'string' ? req.query.plan : '';

    // Scope inference (§13.8): both → plan, project-only → project, neither → infra.
    const scope: LessonScope =
      projectParam !== '' && planParam !== ''
        ? 'plan'
        : projectParam !== ''
          ? 'project'
          : 'infra';

    // Validate the params that are present (an invalid component → 400).
    if (projectParam !== '' && !isValidPathComponent(projectParam)) {
      send400(res, 'Query param "project" must be a valid path component');
      return;
    }
    if (planParam !== '' && !isValidPathComponent(planParam)) {
      send400(res, 'Query param "plan" must be a valid path component');
      return;
    }

    const idx = await scanner.getIndex();

    // ---- infra scope: merge every project's lessons (no project required) ----
    if (scope === 'infra') {
      const merged: LessonEntry[] = [];
      for (const indexed of idx.projects.values()) {
        merged.push(...(await readProjectLessons(fs, indexed)));
      }
      const view = buildLessons(merged, 'infra');
      sendOk(res, view, { scannedAt: isoNow(), partialProjects: [] });
      return;
    }

    // ---- project / plan scope: a real project is required ----
    const indexed = idx.projects.get(projectParam) ?? null;
    if (indexed === null) {
      send404(res, `Project "${projectParam}"`);
      return;
    }

    const lessons = await readProjectLessons(fs, indexed);

    if (scope === 'project') {
      const view = buildLessons(lessons, 'project', undefined, {
        projectId: indexed.projectId,
      });
      sendOk(res, view, { scannedAt: isoNow(), partialProjects: [] });
      return;
    }

    // ---- plan scope: resolve the plan's member EPIC ids (§13.6 four-tier) ----
    const planNumber = planNumberPrefix(planParam);
    if (planNumber === null) {
      send404(res, `Plan "${planParam}"`);
      return;
    }

    const plans = await discoverPlans(scanner, indexed);
    const plan = plans.find(
      (p) => p.planNumber && p.planNumber.toUpperCase() === planNumber.toUpperCase(),
    );
    if (plan === undefined) {
      send404(res, `Plan "${planNumber}" in project "${indexed.projectId}"`);
      return;
    }

    const view: LessonsView = buildLessons(lessons, 'plan', plan.memberEpicIds, {
      projectId: indexed.projectId,
      planId: plan.planNumber ?? plan.planStem,
    });
    sendOk(res, view, { scannedAt: isoNow(), partialProjects: [] });
  });

  return router;
}

/**
 * Read + parse one project's `work/lessons-learned.md`. Never throws — an absent
 * file → `[]` (the {@link buildLessons} builder turns that into an honest empty
 * view + a warning). Malformed content is parsed defensively by
 * {@link parseLessons}.
 */
async function readProjectLessons(
  fs: FsReader,
  indexed: IndexedProject,
): Promise<LessonEntry[]> {
  const path = join(indexed.aidoPath, 'work', 'lessons-learned.md');
  const text = await fs.readText(path);
  return parseLessons(text);
}
