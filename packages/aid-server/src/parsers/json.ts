/**
 * JSON parser for `.aid-o/` files.
 *
 * Handles: plan.json, state.yaml, gates_report.json, pm_decision.json,
 * projects.json, and any other JSON data files.
 *
 * No external library required -- uses built-in JSON.parse. Never throws;
 * malformed JSON produces a null data result with a warning.
 *
 * snake_case keys in the JSON source are converted to camelCase in the output.
 */

import type { ParseResult, ParseWarning } from '@aid/contract';
import { snakeToCamel } from './utils.js';

/**
 * Parse a JSON string into a typed result.
 *
 * @param content - Raw JSON string content.
 * @param source  - Source file path (used for diagnostics).
 * @returns ParseResult with the parsed data (or null on failure) and any warnings.
 */
export function parseJson<T>(content: string, source: string): ParseResult<T> {
  const warnings: ParseWarning[] = [];

  // Handle empty / whitespace-only content.
  if (!content || content.trim().length === 0) {
    warnings.push({
      message: 'JSON content is empty',
      severity: 'warning',
    });
    return { data: null, warnings, source };
  }

  try {
    const raw = JSON.parse(content);

    // Convert snake_case keys to camelCase.
    const data = snakeToCamel<T>(raw);

    return { data, warnings, source };
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown JSON parse error';

    warnings.push({
      message: `Malformed JSON: ${message}`,
      severity: 'error',
    });

    return { data: null, warnings, source };
  }
}
