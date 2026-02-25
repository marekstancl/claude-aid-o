/**
 * YAML parser for `.aid-o/` files.
 *
 * Handles: epic-queue.yaml, auto-mode-state.yaml, gates.yaml,
 * decision-policies.yaml, and any other YAML configuration files.
 *
 * Uses `js-yaml` for YAML parsing. Never throws -- all errors are captured
 * as warnings in the returned ParseResult.
 *
 * snake_case keys in the YAML source are converted to camelCase in the output.
 */

import yaml from 'js-yaml';
import type { ParseResult, ParseWarning } from '../types.ts';
import { snakeToCamel } from './utils.ts';

/**
 * Parse a YAML string into a typed result.
 *
 * @param content - Raw YAML string content.
 * @param source  - Source file path (used for diagnostics).
 * @returns ParseResult with the parsed data (or null on failure) and any warnings.
 */
export function parseYaml<T>(content: string, source: string): ParseResult<T> {
  const warnings: ParseWarning[] = [];

  // Handle empty / whitespace-only content.
  if (!content || content.trim().length === 0) {
    warnings.push({
      message: 'YAML content is empty',
      severity: 'warning',
    });
    return { data: null, warnings, source };
  }

  try {
    const raw = yaml.load(content);

    // yaml.load returns undefined for empty documents (e.g., just "---").
    if (raw === undefined || raw === null) {
      warnings.push({
        message: 'YAML document is empty or contains only comments',
        severity: 'warning',
      });
      return { data: null, warnings, source };
    }

    // Convert snake_case keys to camelCase.
    const data = snakeToCamel<T>(raw);

    return { data, warnings, source };
  } catch (err: unknown) {
    const message =
      err instanceof Error ? err.message : 'Unknown YAML parse error';

    // js-yaml YAMLException includes a `mark` property with line info.
    const line =
      err !== null &&
      typeof err === 'object' &&
      'mark' in err &&
      err.mark !== null &&
      typeof err.mark === 'object' &&
      'line' in err.mark &&
      typeof (err.mark as Record<string, unknown>).line === 'number'
        ? ((err.mark as Record<string, unknown>).line as number) + 1 // 0-indexed -> 1-indexed
        : undefined;

    warnings.push({
      message: `Malformed YAML: ${message}`,
      line,
      severity: 'error',
    });

    return { data: null, warnings, source };
  }
}
