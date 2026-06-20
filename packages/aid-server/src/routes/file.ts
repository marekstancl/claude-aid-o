/**
 * Hardened raw-artifact endpoint (`/file`) — EPIC E-047-3_7, Step 6 (SECURITY).
 *
 * Serves a SINGLE evidence artifact's parsed contents for the raw-artifact
 * drawer. The `name` query parameter is user-supplied, so this endpoint is the
 * one cross-project read surface exposed to path-traversal (CWE-22). It is
 * hardened exactly per spec §7.4.1:
 *
 *   1. Resolution root — the file is resolved ONLY within the validated run dir
 *      (and therefore its `gates/`/`reporter/`/`steps/` subdirs, which are
 *      subtrees of the run dir) PLUS `<proj>/.aid-o/reports/`. Anything that
 *      resolves outside both roots → 404.
 *   2. Name allow-list — `name` must match a known artifact name/pattern
 *      (§7.4.1). An allow-list miss → 404.
 *   3. Canonicalize + assert prefix — after `fs.realpath` the resolved path MUST
 *      `startsWith(resolvedRoot + sep)` (segment-boundary, via the Step 3
 *      `isWithinDirectory` helper). Any `..`, any absolute path, or an escape
 *      → 404.
 *   4. Symlink → 403 — `lstat` the named target; a symlink is NEVER followed
 *      (there are no symlinks under `.aid-o`, so one is always anomalous).
 *   5. Size cap — a file over 1 MB → 413; an over-long `name`/URI → 414.
 *
 * READ-ONLY (GET only). Never throws — every failure maps to a status through
 * the standard envelope. Checks are ordered cheapest-first: URI cap before any
 * fs work, allow-list before `realpath`, symlink before the content read.
 *
 * Reuses `routes/path-validation.ts` (`isWithinDirectory`, `isValidPathComponent`,
 * Step 3) for the segment-boundary containment assert.
 *
 * Module: src/routes/file.ts
 */

import { Router } from 'express';
import { join, isAbsolute } from 'node:path';
import { realpath, lstat, stat } from 'node:fs/promises';
import type { ScannerCache } from '../services/scanner-cache.js';
import { FsReader } from '../services/fs-reader.js';
import { sendOk, send404, send400, sendError } from '../api/middleware.js';
import { isValidPathComponent, isWithinDirectory } from './path-validation.js';

/** Maximum served file size — 1 MB (§7.4.1; largest real artifact is 125 KB). */
const MAX_FILE_BYTES = 1024 * 1024;

/** Maximum length of the `name` query parameter — over this → 414 (§7.4.1). */
const MAX_NAME_LENGTH = 1024;

/**
 * Allow-list of artifact names served by `/file` (§7.4.1). Exact names matched
 * literally; a `name` matching none of these (nor a pattern below) → 404.
 */
const ALLOWED_EXACT: ReadonlySet<string> = new Set([
  'fsm-state.yaml',
  'compliance.json',
  'gates_report.json',
  'plan.json',
  'plan-diff.json',
  'timeline.jsonl',
  'epic-summary.md',
  'final_report.md',
  'audit-report.md',
  'curator-report.md',
  'simplifier-report.md',
]);

/** Glob-style patterns from §7.4.1, compiled to anchored RegExps. */
const ALLOWED_PATTERNS: ReadonlyArray<RegExp> = [
  /^verifier-output-[A-Za-z0-9._-]+\.md$/, // verifier-output-*.md
  /^step-[A-Za-z0-9._-]+-verify\.md$/, // step-*-verify.md
  /^reporter\/[A-Za-z0-9._-]+$/, // reporter/* (single segment)
];

/**
 * Decide whether a (already traversal-checked) `name` is on the §7.4.1
 * allow-list. Returns true for an exact-name match or an anchored pattern match.
 */
function isAllowedArtifactName(name: string): boolean {
  if (ALLOWED_EXACT.has(name)) return true;
  return ALLOWED_PATTERNS.some((re) => re.test(name));
}

/**
 * Build the hardened `/file` router backed by the Phase-2 {@link ScannerCache}.
 * `runDirFor` resolves the exact discovered run dir; the Tier-1 index `aidoPath`
 * yields the second resolution root `<proj>/.aid-o/reports/`.
 */
export function fileRoutes(scanner: ScannerCache): Router {
  const router = Router();
  const fs = new FsReader();

  // GET /epics/:projectId/:epicId/runs/:runId/file?name=…
  router.get(
    '/epics/:projectId/:epicId/runs/:runId/file',
    async (req, res) => {
      const { projectId, epicId, runId } = req.params;

      // --- 1. URI cap (414) — cheapest check, before ANY fs work. ---
      const rawName = req.query.name;
      const name = typeof rawName === 'string' ? rawName : '';
      if (name.length > MAX_NAME_LENGTH) {
        sendError(res, 414, 'URI_TOO_LONG', 'Requested artifact name is too long');
        return;
      }
      if (name.length === 0) {
        send400(res, 'Query parameter "name" is required');
        return;
      }

      // --- 2. Validate the run-coordinate path components (no traversal). ---
      if (
        !isValidPathComponent(projectId) ||
        !isValidPathComponent(epicId) ||
        !isValidPathComponent(runId)
      ) {
        send400(res, 'Invalid projectId/epicId/runId path component');
        return;
      }

      // --- 3. Reject `..` and absolute paths in `name` outright (404). ---
      // Segment-split so a dot-bearing basename like `gates_report.json` is NOT
      // mistaken for traversal — only a literal `..` segment is rejected.
      if (isAbsolute(name) || name.split(/[/\\]/).some((seg) => seg === '..')) {
        send404(res, 'Artifact');
        return;
      }

      // --- 4. Allow-list miss → 404 (before any realpath / disk read). ---
      if (!isAllowedArtifactName(name)) {
        send404(res, 'Artifact');
        return;
      }

      // --- 5. Resolve the two allowed roots (run dir + `<proj>/.aid-o/reports`). ---
      const runDir = scanner.runDirFor(projectId, epicId, runId);
      if (!runDir) {
        send404(res, `Run "${runId}" (EPIC "${epicId}", project "${projectId}")`);
        return;
      }

      const idx = await scanner.getIndex();
      const aidoPath = idx.projects.get(projectId)?.aidoPath ?? null;
      const reportsDir = aidoPath ? join(aidoPath, 'reports') : null;

      // Candidate roots, in priority order: run dir, then the project reports dir.
      const candidateRoots: string[] = [runDir, ...(reportsDir ? [reportsDir] : [])];

      // --- 6. For each root: join, realpath, assert containment (404 on escape). ---
      // `matchedRoot` keeps the PRE-realpath root so the symlink check (step 7)
      // can lstat the exact entry the client named (never the realpath result).
      let servedReal: string | null = null;
      let matchedRoot: string | null = null;
      for (const root of candidateRoots) {
        const joined = join(root, name);
        let real: string;
        let realRoot: string;
        try {
          real = await realpath(joined);
          realRoot = await realpath(root);
        } catch {
          // ENOENT / unreadable under this root → try the next root.
          continue;
        }
        // The realpath MUST stay inside its (canonicalized) root.
        if (isWithinDirectory(real, realRoot)) {
          servedReal = real;
          matchedRoot = root;
          break;
        }
        // Resolved outside its root → keep scanning the remaining roots.
      }

      if (servedReal === null || matchedRoot === null) {
        send404(res, 'Artifact');
        return;
      }

      // --- 7. Symlink → 403. lstat the NAMED target (pre-realpath join) so a
      //        symlink is detected before its target is ever read. ---
      const namedTarget = join(matchedRoot, name);
      try {
        const ls = await lstat(namedTarget);
        if (ls.isSymbolicLink()) {
          sendError(res, 403, 'FORBIDDEN', 'Symlinked artifacts are not served');
          return;
        }
      } catch {
        // The entry vanished between realpath and lstat — treat as not found.
        send404(res, 'Artifact');
        return;
      }

      // --- 8. Size cap (413). stat the resolved real path. ---
      let size: number;
      try {
        size = (await stat(servedReal)).size;
      } catch {
        send404(res, 'Artifact');
        return;
      }
      if (size > MAX_FILE_BYTES) {
        sendError(res, 413, 'PAYLOAD_TOO_LARGE', 'Artifact exceeds the 1 MB size limit');
        return;
      }

      // --- 9. Read + parse + serve. Never throws (FsReader is tolerant). ---
      const { format, content } = await fs.readParsed(servedReal);
      sendOk(res, { format, content });
    },
  );

  return router;
}
