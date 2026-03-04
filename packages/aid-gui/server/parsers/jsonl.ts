/**
 * JSONL (JSON Lines) parser for `.aid-o/` files.
 *
 * Handles: timeline.jsonl, slack_log.jsonl, and any other JSONL files.
 *
 * No external library required -- parses line by line using built-in
 * JSON.parse. Malformed lines produce a warning but do not fail the whole
 * parse. Empty lines are skipped silently.
 *
 * snake_case keys in each JSON line are converted to camelCase in the output.
 */

import type { ParseResult, ParseWarning } from '../types.ts';
import { snakeToCamel } from './utils.ts';

/**
 * Parse a JSONL string into an array of typed entries.
 *
 * @param content - Raw JSONL string (one JSON object per line).
 * @param source  - Source file path (used for diagnostics).
 * @returns ParseResult with an array of parsed entries and any per-line warnings.
 */
export function parseJsonl<T>(
  content: string,
  source: string,
): ParseResult<T[]> {
  const warnings: ParseWarning[] = [];

  // Handle empty / whitespace-only content.
  if (!content || content.trim().length === 0) {
    warnings.push({
      message: 'JSONL content is empty',
      severity: 'warning',
    });
    return { data: [], warnings, source };
  }

  const lines = content.split('\n');
  const entries: T[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();

    // Skip empty lines silently.
    if (line.length === 0) continue;

    try {
      const raw = JSON.parse(line);
      const entry = snakeToCamel<T>(raw);
      entries.push(entry);
    } catch (err: unknown) {
      const message =
        err instanceof Error ? err.message : 'Unknown JSON parse error';
      warnings.push({
        message: `Malformed JSON on line ${i + 1}: ${message}`,
        line: i + 1,
        severity: 'warning',
      });
    }
  }

  return { data: entries, warnings, source };
}
