/**
 * Shared utilities for server-side parsers.
 *
 * The primary utility here is `snakeToCamel`, which recursively converts all
 * object keys from snake_case to camelCase. This is used by every parser to
 * normalize `.aid-o/` file data (which uses snake_case) into TypeScript
 * convention (camelCase).
 */

/**
 * Convert a single snake_case string to camelCase.
 *
 * Examples:
 *   "epic_id"        -> "epicId"
 *   "depends_on"     -> "dependsOn"
 *   "started_at"     -> "startedAt"
 *   "already_camel"  -> "alreadyCamel"
 *   "ALL_CAPS"       -> "allCaps"  (lowercases first segment)
 */
export function snakeToCamelKey(key: string): string {
  // If the key contains no underscores, return it as-is.
  if (!key.includes('_')) return key;

  return key.replace(/_([a-zA-Z0-9])/g, (_match, char: string) =>
    char.toUpperCase(),
  );
}

/**
 * Recursively convert all object keys from snake_case to camelCase.
 *
 * - Handles nested objects and arrays.
 * - Preserves primitive values (string, number, boolean, null, undefined).
 * - Preserves Date objects and other non-plain-object types.
 * - Does not modify the original object; returns a new one.
 */
export function snakeToCamel<T = unknown>(obj: unknown): T {
  if (obj === null || obj === undefined) {
    return obj as T;
  }

  if (Array.isArray(obj)) {
    return obj.map((item) => snakeToCamel(item)) as T;
  }

  if (typeof obj === 'object' && obj.constructor === Object) {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(obj)) {
      result[snakeToCamelKey(key)] = snakeToCamel(value);
    }
    return result as T;
  }

  // Primitives and non-plain objects pass through unchanged.
  return obj as T;
}
