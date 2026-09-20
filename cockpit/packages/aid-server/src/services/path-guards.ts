/**
 * Shared path validation and security helpers.
 *
 * These utilities defend against CWE-22 (path traversal) attacks and provide
 * segment-boundary-aware containment checks used throughout the scanner, cache,
 * and run-detail modules. Consolidated into a single source to prevent
 * regex/logic divergence.
 */

import { posix, sep } from 'node:path';
import type { FsmState } from '@aid/contract';

// Re-export FsmState for convenience (used by stateLineFrom and validation)
export type { FsmState };

// ===========================================================================
// Security helpers — path traversal defense (CWE-22)
// ===========================================================================

/**
 * Validate that a path segment (projectId/epicId/runId) is safe — does not
 * contain traversal patterns (`..`), separators (`/`, `\`), or be empty/`.`.
 * Returns false for any dangerous input; never throws.
 */
export function isValidPathSegment(segment: string): boolean {
  if (!segment || segment === '.' || segment === '..') return false;
  if (segment.includes('/') || segment.includes('\\')) return false;
  if (segment.includes('..')) return false;
  return true;
}

/**
 * Segment-boundary-aware "is `p` under `root`" check.
 * True when `p` equals `root` exactly, or `p` continues with a path separator
 * immediately after `root` (so `/projects/x` matches but `/projects-backup/x`
 * does not). Never throws.
 *
 * Note: Callers should normalize trailing slashes on both `p` and `root` before
 * calling (strip trailing sep to ensure consistent behavior across platforms).
 */
export function isUnderRoot(p: string, root: string): boolean {
  if (p === root) return true;
  if (!p.startsWith(root)) return false;
  const boundary = p[root.length];
  return boundary === posix.sep || boundary === sep;
}

// ===========================================================================
// FSM state validation
// ===========================================================================

/**
 * The six valid v3 FSM states (mirrors spec §4.0 #9 and project-scanner.ts).
 * Replaces scattered VALID_FSM_STATES definitions across modules.
 */
export const VALID_FSM_STATES: ReadonlySet<string> = new Set<FsmState>([
  'READY',
  'EXECUTE',
  'GATES',
  'ESCALATION',
  'DONE',
  'ERROR',
]);

// ===========================================================================
// YAML / scalar parsing helpers
// ===========================================================================

/**
 * Strip surrounding quotes from a YAML scalar value.
 * Handles both single and double quotes; preserves unquoted values as-is.
 */
export function stripYamlScalar(raw: string): string {
  const v = raw.trim();
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    return v.slice(1, -1);
  }
  return v;
}
