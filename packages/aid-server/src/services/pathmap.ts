/**
 * Container <-> host path normalization (EPIC E-047-2_7, Step 3).
 *
 * The Cockpit runs inside a container where target projects are mounted at one
 * root (e.g. `/projects`), but evidence files on disk embed ABSOLUTE HOST paths
 * (e.g. `/opt/eco/projects/acta/.aid-o/work/...` in `evidence_dir` fields and
 * run ids). The UI must display host paths; every file read must resolve to the
 * in-container path. This module is the single seam that translates between the
 * two views.
 *
 * Design (spec §9.6, risk #18): the two roots are injected via the factory.
 * There is ZERO `/opt/eco/projects` string literal in the translation logic —
 * the only occurrence in this file is the clearly-labelled DEFAULT_HOST_ROOT
 * constant offered for tests / standalone use, never consulted by the functions.
 */

import { sep, posix } from 'node:path';

/**
 * Default host root, offered ONLY as a convenience for tests and standalone
 * callers. It is NOT referenced anywhere in the translation logic below — the
 * functions derive everything from the injected {@link PathMapRoots}.
 */
export const DEFAULT_HOST_ROOT = '/opt/eco/projects';

/** Roots that parameterize a {@link PathMap}. */
export interface PathMapRoots {
  /** Container view of the projects mount (e.g. `/projects`). */
  projectsRoot: string;
  /** Host view of the projects mount (e.g. `/opt/eco/projects`). */
  hostRoot: string;
}

/** Bidirectional path translator bound to a pair of roots. */
export interface PathMap {
  /** Rewrite a container-rooted path to its host equivalent. */
  containerToHost(p: string): string;
  /** Rewrite a host-rooted path to its container equivalent. */
  hostToContainer(p: string): string;
}

/**
 * Normalize a root for segment-aware comparison: strip every trailing path
 * separator (both `posix.sep` and the platform `sep`) so prefix matching can be
 * done on an exact segment boundary.
 */
function stripTrailingSep(root: string): string {
  let end = root.length;
  while (end > 1 && (root[end - 1] === posix.sep || root[end - 1] === sep)) {
    end -= 1;
  }
  return root.slice(0, end);
}

/**
 * Replace the leading `fromRoot` segment of `p` with `toRoot`, preserving the
 * remainder of the path exactly.
 *
 * Returns `p` unchanged when:
 * - `p` is not rooted under `fromRoot` (segment-boundary aware — `/projects`
 *   does NOT match `/projects-backup`), or
 * - `p` is already rooted under `toRoot` (idempotent).
 *
 * Uses a path-segment-aware comparison rather than a naive `startsWith` so that
 * `/projects-backup/x` is never rewritten when the root is `/projects`.
 */
function rewriteRoot(p: string, fromRoot: string, toRoot: string): string {
  const from = stripTrailingSep(fromRoot);
  const to = stripTrailingSep(toRoot);

  // Identity roots: nothing to translate.
  if (from === to) return p;

  // Already in the target root -> idempotent no-op.
  if (isUnderRoot(p, to)) return p;

  // Not under the source root -> leave untouched (no throw, no partial mangle).
  if (!isUnderRoot(p, from)) return p;

  // Replace only the leading root segment; preserve the rest verbatim.
  return to + p.slice(from.length);
}

/**
 * Segment-boundary-aware "is `p` under `root`" check. True when `p` equals
 * `root` exactly, or `p` continues with a path separator immediately after
 * `root` (so `/projects/x` matches but `/projects-backup/x` does not).
 */
function isUnderRoot(p: string, root: string): boolean {
  if (p === root) return true;
  if (!p.startsWith(root)) return false;
  const boundary = p[root.length];
  return boundary === posix.sep || boundary === sep;
}

/**
 * Create a bidirectional path translator from a pair of roots.
 *
 * When `hostRoot === projectsRoot` (host-native dev), both functions are
 * identity no-ops.
 */
export function createPathMap({ projectsRoot, hostRoot }: PathMapRoots): PathMap {
  return {
    containerToHost: (p: string): string => rewriteRoot(p, projectsRoot, hostRoot),
    hostToContainer: (p: string): string => rewriteRoot(p, hostRoot, projectsRoot),
  };
}
