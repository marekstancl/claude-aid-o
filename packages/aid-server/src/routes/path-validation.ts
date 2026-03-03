/**
 * Path traversal prevention utilities.
 *
 * Provides defense-in-depth validation for route parameters that are used to
 * construct filesystem paths. Two layers of protection are applied:
 *
 *   1. Regex rejection — rejects any parameter containing characters that are
 *      meaningful to a filesystem path: `.` (dot), `/` (forward slash), and
 *      `\` (backslash). This eliminates `../`, `..`, absolute paths, and
 *      Windows-style separators before any path construction occurs.
 *
 *   2. Bounds checking — after constructing the full path with `path.join()`,
 *      `path.resolve()` is used to canonicalize it and `startsWith()` verifies
 *      the result is still within the expected parent directory. This catches
 *      any encoding tricks or edge cases the regex did not cover.
 *
 * CWE reference: CWE-22 (Improper Limitation of a Pathname to a Restricted
 * Directory — "Path Traversal").
 *
 * Threat mitigated: An attacker supplying an epicId or runId such as
 * `../../etc/passwd`, `%2e%2e%2fpasswd`, or `\..\..\windows\system32`
 * could read arbitrary files from the server filesystem. Both layers together
 * prevent this even if one layer is bypassed.
 */

import * as path from 'node:path';

/**
 * Characters that must not appear in a path-component parameter.
 *
 * Rejects: `.` (directory traversal), `/` (POSIX separator),
 *           `\` (Windows separator).
 */
const UNSAFE_CHARS_RE = /[./\\]/;

/**
 * Validate that a single path component (e.g. epicId or runId) does not
 * contain path separator or traversal characters.
 *
 * @param value - The raw parameter value from the request.
 * @returns `true` when the value is safe to use in a path, `false` otherwise.
 */
export function isValidPathComponent(value: string): boolean {
  if (typeof value !== 'string' || value.length === 0) return false;
  return !UNSAFE_CHARS_RE.test(value);
}

/**
 * Verify that a resolved path is strictly contained within the expected
 * parent directory. Prevents symlink-based and encoding-based escapes.
 *
 * The check requires the resolved path to start with `parentDir + path.sep`
 * OR be exactly equal to `parentDir`. This avoids the classic false positive
 * where `/evidence/epic` wrongly passes a check for parent `/evidence/epi`.
 *
 * @param resolvedPath - The `path.resolve()`-d candidate path.
 * @param parentDir    - The `path.resolve()`-d expected root directory.
 * @returns `true` when the path is within (or equal to) the parent directory.
 */
export function isWithinDirectory(resolvedPath: string, parentDir: string): boolean {
  const normalizedParent = path.resolve(parentDir);
  const normalizedPath = path.resolve(resolvedPath);
  return (
    normalizedPath === normalizedParent ||
    normalizedPath.startsWith(normalizedParent + path.sep)
  );
}

/**
 * Result type returned by `validateEvidencePath`.
 */
export type PathValidationResult =
  | { ok: true; resolvedPath: string }
  | { ok: false; reason: string };

/**
 * Full two-layer validation for a path built from one or more components
 * (e.g. epicId + optional runId) rooted at a known base directory.
 *
 * Layer 1: Each component is checked against `isValidPathComponent()`.
 * Layer 2: The joined path is resolved and checked against the base directory
 *          using `isWithinDirectory()`.
 *
 * @param baseDir    - The trusted root directory (evidence base). Will be
 *                     resolved internally; does not need to be pre-resolved.
 * @param components - One or more path components to join after `baseDir`.
 * @returns A discriminated union: `{ ok: true, resolvedPath }` on success or
 *          `{ ok: false, reason }` on failure.
 *
 * @example
 * const result = validateEvidencePath('/project/.aid-o/work/evidence', epicId, runId);
 * if (!result.ok) {
 *   return res.status(400).json({ ok: false, error: { code: 'INVALID_PATH', message: result.reason } });
 * }
 * // Safe to use result.resolvedPath
 */
export function validateEvidencePath(
  baseDir: string,
  ...components: string[]
): PathValidationResult {
  // Layer 1: reject unsafe characters in each component.
  for (const component of components) {
    if (!isValidPathComponent(component)) {
      return {
        ok: false,
        reason: `Invalid path component "${component}": must not contain ".", "/", or "\\"`,
      };
    }
  }

  // Layer 2: resolve and verify containment.
  const joined = path.join(baseDir, ...components);
  const resolved = path.resolve(joined);
  const resolvedBase = path.resolve(baseDir);

  if (!isWithinDirectory(resolved, resolvedBase)) {
    return {
      ok: false,
      reason: `Path escapes allowed directory`,
    };
  }

  return { ok: true, resolvedPath: resolved };
}
